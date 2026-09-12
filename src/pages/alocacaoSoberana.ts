/**
 * F5-08 P5 — ALOCAÇÃO SOBERANA do colaborador (ocupação) e da POSIÇÃO
 * (reporting line).
 *
 * Este módulo é a camada de decisão DECIDÍVEL E TESTÁVEL das telas de alocação,
 * sem React: recebe a fotografia soberana (leitura RLS do P4) + a intenção do
 * usuário e chama as portas JÁ EXISTENTES da F5-07 — nenhuma operação nova,
 * nenhuma capability nova, nenhuma autoridade local.
 *
 * Regras preservadas:
 * - `occupations`/`position_reporting_lines` são entidades TEMPORAIS; a única
 *   definição de "vigente" é o intervalo meio-aberto `[valid_from, valid_to)`
 *   com referência injetável (`apoioEstrutura.estaVigente`);
 * - a ocupação nasce da POSIÇÃO (`positionId`) e a reporting line da POSIÇÃO
 *   SUBORDINADA para a POSIÇÃO GERENTE (`subordinatePositionId` →
 *   `managerPositionId`): gestor NUNCA é derivado de cargo, nome ou matrícula;
 * - NÃO existe `expectedVersion` nestas operações (contrato F5-07): a proteção
 *   contra fotografia desatualizada é LOCAL e fail-closed — se a posição/ocupação
 *   não está mais vigente na leitura corrente, NADA é enviado e a tela recarrega;
 * - NÃO existe transação única entre operações distintas: "trocar de posição" é
 *   explicitamente `encerrarOcupacao` + `definirOcupacao`, com desfecho PARCIAL
 *   visível (o colaborador pode ficar sem alocação) — jamais rollback local;
 * - nenhum algoritmo de ciclo/self-relation é replicado aqui: ciclos, guardas
 *   I1–I5 e integridade continuam no banco/RPC (a tela apenas não oferece a
 *   posição selecionada como seu próprio gestor).
 */

import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import type {
  OcupacaoSoberana,
  PosicaoSoberana,
  ReportingLineSoberana,
  EstruturaSoberana,
} from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import {
  definirOcupacao,
  definirReportingLine,
  encerrarOcupacao,
  encerrarReportingLine,
  type DependenciasAcessoColaboradores,
  type ResultadoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { agoraIso, estaVigente } from "./apoioEstrutura";

/** Mensagem pública de fotografia desatualizada (fail-closed, sem envio). */
export const MENSAGEM_POSICAO_DESATUALIZADA =
  "A estrutura foi atualizada e a posição selecionada não está mais vigente na leitura " +
  "atual. A leitura foi recarregada: revise o estado e tente novamente.";

export const MENSAGEM_OCUPACAO_DESATUALIZADA =
  "A alocação mudou desde a sua leitura: não existe ocupação vigente para encerrar. " +
  "A leitura foi recarregada: revise o estado e tente novamente.";

export const MENSAGEM_REPORTING_DESATUALIZADO =
  "A estrutura foi atualizada e a posição não está mais vigente para esta operação. " +
  "A leitura foi recarregada: revise o estado e tente novamente.";

// ---------------------------------------------------------------------------
// Seleção temporal da fotografia soberana (apresentação + guards)
// ---------------------------------------------------------------------------

/** Posições VIGENTES na referência (meio-aberto `[valid_from, valid_to)`). */
export function posicoesVigentes(
  estrutura: EstruturaSoberana,
  referencia: string = agoraIso()
): readonly PosicaoSoberana[] {
  return estrutura.posicoes.filter((posicao) =>
    estaVigente(posicao.validFrom, posicao.validTo, referencia)
  );
}

/** Posição por UUID, apenas se VIGENTE na referência. */
export function posicaoVigente(
  estrutura: EstruturaSoberana,
  posicaoId: string,
  referencia: string = agoraIso()
): PosicaoSoberana | null {
  const posicao = estrutura.posicoes.find((item) => item.posicaoId === posicaoId);
  if (!posicao) return null;
  return estaVigente(posicao.validFrom, posicao.validTo, referencia) ? posicao : null;
}

/** Ocupação VIGENTE do colaborador (a que a tela encerra/troca). */
export function ocupacaoVigenteDoColaborador(
  estrutura: EstruturaSoberana,
  collaboratorId: string,
  referencia: string = agoraIso()
): OcupacaoSoberana | null {
  const vigente = estrutura.ocupacoes.find(
    (ocupacao) =>
      ocupacao.collaboratorId === collaboratorId &&
      estaVigente(ocupacao.validFrom, ocupacao.validTo, referencia)
  );
  return vigente ?? null;
}

/** Reporting line VIGENTE da posição subordinada (superior formal atual). */
export function reportingVigenteDaPosicao(
  estrutura: EstruturaSoberana,
  subordinatePositionId: string,
  referencia: string = agoraIso()
): ReportingLineSoberana | null {
  const vigente = estrutura.reportingLines.find(
    (linha) =>
      linha.subordinatePositionId === subordinatePositionId &&
      estaVigente(linha.validFrom, linha.validTo, referencia)
  );
  return vigente ?? null;
}

/**
 * Candidatas a posição GERENTE: vigentes, exceto a própria posição subordinada
 * (a auto-relação é recusada pelo banco; aqui é apenas UX — nenhum algoritmo de
 * ciclo é implementado no cliente).
 */
export function posicoesGerentesCandidatas(
  estrutura: EstruturaSoberana,
  subordinatePositionId: string,
  referencia: string = agoraIso()
): readonly PosicaoSoberana[] {
  return posicoesVigentes(estrutura, referencia).filter(
    (posicao) => posicao.posicaoId !== subordinatePositionId
  );
}

// ---------------------------------------------------------------------------
// Desfechos
// ---------------------------------------------------------------------------

export type RecusaAlocacao =
  | { readonly tipo: "sem-motivo" }
  | { readonly tipo: "sem-vigencia" }
  | {
      readonly tipo: "fotografia-desatualizada";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    };

export type DesfechoAlocacao =
  | RecusaAlocacao
  | { readonly tipo: "concluida"; readonly resultado: ResultadoColaboradores<unknown> };

/**
 * Troca de posição: DUAS operações distintas e NÃO atômicas. O desfecho expõe
 * exatamente o que aconteceu no servidor:
 * - `falhou-encerrar`  ⇒ nada mudou (a ocupação anterior continua vigente);
 * - `parcial`          ⇒ a ocupação anterior foi ENCERRADA e a nova NÃO foi
 *                        definida: o colaborador está SEM ALOCAÇÃO (sem rollback
 *                        local, apenas o estado soberano real + recarga);
 * - `concluida`        ⇒ encerrou e definiu.
 */
export type DesfechoTrocaPosicao =
  | RecusaAlocacao
  | { readonly tipo: "concluida" }
  | {
      readonly tipo: "falhou-encerrar";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | {
      readonly tipo: "parcial";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    };

function recusa(entrada: {
  readonly motivo: string;
  readonly vigencia: string;
}): RecusaAlocacao | null {
  if (!entrada.motivo.trim()) return { tipo: "sem-motivo" };
  if (!entrada.vigencia.trim()) return { tipo: "sem-vigencia" };
  return null;
}

function recusaPosicao(mensagem: string): RecusaAlocacao {
  return { tipo: "fotografia-desatualizada", codigo: "CONFLICT", mensagem };
}

// ---------------------------------------------------------------------------
// Ocupação
// ---------------------------------------------------------------------------

export interface EntradaDefinirOcupacaoSoberana {
  readonly estrutura: EstruturaSoberana;
  readonly collaboratorId: string;
  readonly posicaoId: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly operationId: string;
  readonly organizationId?: string | null;
}

/**
 * Define a ocupação do colaborador a partir da fotografia CORRENTE. Se a posição
 * escolhida não existe ou não está vigente na leitura atual, NADA é enviado.
 */
export async function confirmarDefinicaoOcupacao(
  entrada: EntradaDefinirOcupacaoSoberana,
  deps: DependenciasAcessoColaboradores = {}
): Promise<DesfechoAlocacao> {
  const falta = recusa(entrada);
  if (falta) return falta;

  if (!posicaoVigente(entrada.estrutura, entrada.posicaoId)) {
    return recusaPosicao(MENSAGEM_POSICAO_DESATUALIZADA);
  }

  const resultado = await definirOcupacao(
    {
      collaboratorId: entrada.collaboratorId,
      operationId: entrada.operationId,
      positionId: entrada.posicaoId,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo.trim(),
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  return { tipo: "concluida", resultado };
}

export interface EntradaEncerrarOcupacaoSoberana {
  readonly estrutura: EstruturaSoberana;
  readonly collaboratorId: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly operationId: string;
  readonly organizationId?: string | null;
}

/**
 * Encerra a ocupação VIGENTE do colaborador. Sem ocupação vigente na fotografia
 * corrente, a intenção não é enviada (fail-closed + recarga pelo chamador).
 */
export async function confirmarEncerramentoOcupacao(
  entrada: EntradaEncerrarOcupacaoSoberana,
  deps: DependenciasAcessoColaboradores = {}
): Promise<DesfechoAlocacao> {
  const falta = recusa(entrada);
  if (falta) return falta;

  if (!ocupacaoVigenteDoColaborador(entrada.estrutura, entrada.collaboratorId)) {
    return recusaPosicao(MENSAGEM_OCUPACAO_DESATUALIZADA);
  }

  const resultado = await encerrarOcupacao(
    {
      collaboratorId: entrada.collaboratorId,
      operationId: entrada.operationId,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo.trim(),
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  return { tipo: "concluida", resultado };
}

export interface EntradaTrocarPosicaoSoberana {
  readonly estrutura: EstruturaSoberana;
  readonly collaboratorId: string;
  readonly posicaoId: string;
  readonly vigencia: string;
  readonly motivo: string;
  /** Idempotência da operação de encerramento (F5-07). */
  readonly operationIdEncerramento: string;
  /** Idempotência da operação de definição (F5-07) — id distinto por operação. */
  readonly operationIdDefinicao: string;
  readonly organizationId?: string | null;
}

/**
 * Troca de posição = `encerrarOcupacao` + `definirOcupacao` (sem atomicidade
 * fingida e sem rollback local). Cada etapa usa o SEU `operationId`.
 */
export async function confirmarTrocaDePosicao(
  entrada: EntradaTrocarPosicaoSoberana,
  deps: DependenciasAcessoColaboradores = {}
): Promise<DesfechoTrocaPosicao> {
  const falta = recusa(entrada);
  if (falta) return falta;

  if (!posicaoVigente(entrada.estrutura, entrada.posicaoId)) {
    return recusaPosicao(MENSAGEM_POSICAO_DESATUALIZADA);
  }
  if (!ocupacaoVigenteDoColaborador(entrada.estrutura, entrada.collaboratorId)) {
    return recusaPosicao(MENSAGEM_OCUPACAO_DESATUALIZADA);
  }

  const encerramento = await encerrarOcupacao(
    {
      collaboratorId: entrada.collaboratorId,
      operationId: entrada.operationIdEncerramento,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo.trim(),
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  if (!encerramento.ok) {
    return {
      tipo: "falhou-encerrar",
      codigo: encerramento.codigo,
      mensagem: encerramento.mensagem,
    };
  }

  const definicao = await definirOcupacao(
    {
      collaboratorId: entrada.collaboratorId,
      operationId: entrada.operationIdDefinicao,
      positionId: entrada.posicaoId,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo.trim(),
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  if (!definicao.ok) {
    // Estado soberano REAL: a ocupação anterior já foi encerrada e a nova não
    // existe. O colaborador está sem alocação; nenhum rollback local é feito.
    return { tipo: "parcial", codigo: definicao.codigo, mensagem: definicao.mensagem };
  }

  return { tipo: "concluida" };
}

// ---------------------------------------------------------------------------
// Reporting line (posição subordinada → posição gerente)
// ---------------------------------------------------------------------------

export interface EntradaDefinirReportingSoberana {
  readonly estrutura: EstruturaSoberana;
  readonly subordinatePositionId: string;
  readonly managerPositionId: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly operationId: string;
  readonly organizationId?: string | null;
}

/**
 * Define/altera o gestor FORMAL da posição. Ambos os lados são POSIÇÕES (UUID):
 * nunca colaborador, cargo, nome ou matrícula. Se qualquer das posições não está
 * vigente na leitura corrente, NADA é enviado.
 */
export async function confirmarReportingLine(
  entrada: EntradaDefinirReportingSoberana,
  deps: DependenciasAcessoColaboradores = {}
): Promise<DesfechoAlocacao> {
  const falta = recusa(entrada);
  if (falta) return falta;

  if (
    !posicaoVigente(entrada.estrutura, entrada.subordinatePositionId) ||
    !posicaoVigente(entrada.estrutura, entrada.managerPositionId)
  ) {
    return recusaPosicao(MENSAGEM_REPORTING_DESATUALIZADO);
  }

  const resultado = await definirReportingLine(
    {
      subordinatePositionId: entrada.subordinatePositionId,
      managerPositionId: entrada.managerPositionId,
      operationId: entrada.operationId,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo.trim(),
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  return { tipo: "concluida", resultado };
}

export interface EntradaEncerrarReportingSoberana {
  readonly estrutura: EstruturaSoberana;
  readonly subordinatePositionId: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly operationId: string;
  readonly organizationId?: string | null;
}

/**
 * Encerra a reporting line VIGENTE da posição (a posição volta a ser raiz). Sem
 * linha vigente na fotografia corrente, nada é enviado.
 */
export async function confirmarEncerramentoReportingLine(
  entrada: EntradaEncerrarReportingSoberana,
  deps: DependenciasAcessoColaboradores = {}
): Promise<DesfechoAlocacao> {
  const falta = recusa(entrada);
  if (falta) return falta;

  if (!posicaoVigente(entrada.estrutura, entrada.subordinatePositionId)) {
    return recusaPosicao(MENSAGEM_REPORTING_DESATUALIZADO);
  }
  if (!reportingVigenteDaPosicao(entrada.estrutura, entrada.subordinatePositionId)) {
    return recusaPosicao(MENSAGEM_REPORTING_DESATUALIZADO);
  }

  const resultado = await encerrarReportingLine(
    {
      subordinatePositionId: entrada.subordinatePositionId,
      operationId: entrada.operationId,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo.trim(),
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  return { tipo: "concluida", resultado };
}

// ---------------------------------------------------------------------------
// Apresentação (rótulos soberanos)
// ---------------------------------------------------------------------------

/** Gestor direto derivado: ocupante da POSIÇÃO gerente da reporting line vigente. */
export function gestorDiretoDaPosicao(
  estrutura: EstruturaSoberana,
  subordinatePositionId: string,
  referencia: string = agoraIso()
): { readonly managerPositionId: string; readonly collaboratorId: string | null } | null {
  const linha = reportingVigenteDaPosicao(estrutura, subordinatePositionId, referencia);
  if (!linha) return null;
  const ocupacao = estrutura.ocupacoes.find(
    (item) =>
      item.posicaoId === linha.managerPositionId &&
      estaVigente(item.validFrom, item.validTo, referencia)
  );
  return {
    managerPositionId: linha.managerPositionId,
    collaboratorId: ocupacao ? ocupacao.collaboratorId : null,
  };
}
