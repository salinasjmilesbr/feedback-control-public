/**
 * F5-08 P5 (correção da auditoria) — ORQUESTRAÇÃO testável do Novo colaborador:
 * criação da pessoa + ALOCAÇÃO opcional (ocupação e reporting line) + RETRIES
 * separados por estado parcial.
 *
 * Contrato do fluxo (D25 / Q5=A):
 * - criar colaborador e criar ocupação são operações DISTINTAS: não há transação
 *   única no frontend e não existe rollback local;
 * - se a ocupação falhar, o colaborador PERMANECE criado e fica SEM ALOCAÇÃO
 *   (`sem-ocupacao`) — o retry tenta a OCUPAÇÃO (e, se houver gestor escolhido, a
 *   reporting line depois dela);
 * - se a ocupação tiver sucesso e a reporting line falhar (`sem-gestor`), a
 *   ocupação JÁ ESTÁ GRAVADA: o retry tenta SOMENTE a reporting line, com novo
 *   `operationId` — nunca recria a ocupação, nunca encerra a ocupação existente e
 *   nunca recria o colaborador;
 * - cada operação distinta recebe o SEU `operationId` (idempotência da Edge);
 * - nenhuma identidade é fabricada: a posição subordinada vem da ocupação
 *   vigente da fotografia CORRENTE (com fallback para a posição aceita pelo
 *   servidor no passo anterior) e a posição gerente é sempre o UUID escolhido.
 *
 * Este módulo não conhece React: recebe a fotografia + intenção e chama as
 * portas JÁ EXISTENTES da F5-07 (`criarColaborador`, `definirOcupacao`,
 * `definirReportingLine`). Nenhuma operação nova, nenhuma capability, nenhuma
 * RPC direta e nenhuma escrita local.
 */

import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import {
  criarColaborador,
  type DependenciasAcessoColaboradores,
} from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import {
  confirmarDefinicaoOcupacao,
  confirmarReportingLine,
  ocupacaoVigenteDoColaborador,
} from "./alocacaoSoberana";

/** Estado PARCIAL da alocação: o que foi gravado e o que não foi. */
export type ParcialAlocacao = "sem-ocupacao" | "sem-gestor";

/** Resultado da etapa de alocação (após o colaborador existir). */
export type AlocacaoResultante =
  | { readonly estado: "completa" }
  | { readonly estado: "nenhuma" }
  | {
      readonly estado: "sem-ocupacao";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | {
      readonly estado: "sem-gestor";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    };

export type DesfechoCadastroAlocacao =
  | {
      readonly tipo: "erro-cadastro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | {
      readonly tipo: "criado";
      readonly collaboratorId: string;
      readonly alocacao: AlocacaoResultante;
    };

/**
 * A fotografia soberana precisa ser RECARREGADA depois desta alocação?
 *
 * Correção da auditoria (BLOCKER 1B): sempre que a OCUPAÇÃO foi gravada e a
 * reporting line falhou (`sem-gestor`), houve mutação soberana bem-sucedida — a
 * recarga é obrigatória QUALQUER que seja o código da falha (FORBIDDEN,
 * INVALID_INPUT, INTERNAL, …), não apenas CONFLICT/NOT_FOUND. Em `sem-ocupacao`
 * nada foi gravado: recarrega somente quando a leitura está desatualizada.
 */
export function deveRecarregarFotografia(alocacao: AlocacaoResultante): boolean {
  if (alocacao.estado === "sem-gestor") return true;
  if (alocacao.estado === "sem-ocupacao") {
    return alocacao.codigo === "CONFLICT" || alocacao.codigo === "NOT_FOUND";
  }
  return false;
}

export interface DadosNovaPessoa {
  readonly fullName: string;
  readonly email: string;
  readonly matricula: string;
  readonly admissionDate?: string;
  readonly statusInicial: "active" | "leave";
}

/** Alocação desejada no formulário (posição/gestor por UUID, nunca por rótulo). */
export interface AlocacaoDesejada {
  readonly posicaoId: string;
  readonly vigencia: string;
  readonly motivo: string;
  readonly gestorPosicaoId: string | null;
}

export interface EntradaCriarComAlocacao {
  readonly estrutura: EstruturaSoberana;
  readonly organizationId?: string | null;
  readonly dados: DadosNovaPessoa;
  readonly operationIdCadastro: string;
  readonly alocacao: (AlocacaoDesejada & {
    readonly operationIdOcupacao: string;
    readonly operationIdReporting: string;
  }) | null;
}

/** Traduz a recusa local das operações de alocação em código/mensagem públicos. */
function recusaParaErro(
  recusa:
    | { readonly tipo: "sem-motivo" }
    | { readonly tipo: "sem-vigencia" }
    | {
        readonly tipo: "fotografia-desatualizada";
        readonly codigo: CodigoPublico;
        readonly mensagem: string;
      }
): { readonly codigo: CodigoPublico; readonly mensagem: string } {
  if (recusa.tipo === "fotografia-desatualizada") {
    return { codigo: recusa.codigo, mensagem: recusa.mensagem };
  }
  return {
    codigo: "INVALID_INPUT",
    mensagem:
      recusa.tipo === "sem-vigencia"
        ? "Informe a vigência da alocação."
        : "Informe o motivo da alocação.",
  };
}

/**
 * Define a ocupação e, quando houver gestor escolhido, a reporting line.
 *
 * NUNCA chama `definirOcupacao` duas vezes por chamada e nunca desfaz a ocupação
 * já gravada: se a reporting line falhar, o desfecho é `sem-gestor`.
 */
export async function tentarOcupacao(
  entrada: {
    readonly estrutura: EstruturaSoberana;
    readonly organizationId?: string | null;
    readonly collaboratorId: string;
    readonly posicaoId: string;
    readonly vigencia: string;
    readonly motivo: string;
    readonly gestorPosicaoId: string | null;
    readonly operationIdOcupacao: string;
    readonly operationIdReporting: string;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<AlocacaoResultante> {
  const ocupacao = await confirmarDefinicaoOcupacao(
    {
      estrutura: entrada.estrutura,
      collaboratorId: entrada.collaboratorId,
      posicaoId: entrada.posicaoId,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo,
      operationId: entrada.operationIdOcupacao,
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  if (ocupacao.tipo !== "concluida") {
    const erro = recusaParaErro(ocupacao);
    return { estado: "sem-ocupacao", codigo: erro.codigo, mensagem: erro.mensagem };
  }
  if (!ocupacao.resultado.ok) {
    return {
      estado: "sem-ocupacao",
      codigo: ocupacao.resultado.codigo,
      mensagem: ocupacao.resultado.mensagem,
    };
  }

  // Ocupação GRAVADA. Sem gestor escolhido, a alocação está completa.
  if (!entrada.gestorPosicaoId) return { estado: "completa" };

  return tentarReportingLine(
    {
      estrutura: entrada.estrutura,
      organizationId: entrada.organizationId,
      collaboratorId: entrada.collaboratorId,
      posicaoId: entrada.posicaoId,
      gestorPosicaoId: entrada.gestorPosicaoId,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo,
      operationIdReporting: entrada.operationIdReporting,
    },
    deps
  );
}

/**
 * Tenta SOMENTE a reporting line (retry de `sem-gestor` ou passo após a ocupação).
 *
 * A posição subordinada é resolvida pela ocupação VIGENTE da fotografia corrente
 * (o servidor é a fonte); quando a leitura ainda não reflete a ocupação recém
 * gravada, usa-se a posição que o servidor ACEITOU em `posicaoId` — nunca um
 * rótulo/cargo/nome. A posição gerente é sempre `gestorPosicaoId` (UUID).
 */
export async function tentarReportingLine(
  entrada: {
    readonly estrutura: EstruturaSoberana;
    readonly organizationId?: string | null;
    readonly collaboratorId: string;
    readonly posicaoId: string;
    readonly gestorPosicaoId: string | null;
    readonly vigencia: string;
    readonly motivo: string;
    readonly operationIdReporting: string;
  },
  deps: DependenciasAcessoColaboradores = {}
): Promise<AlocacaoResultante> {
  if (!entrada.gestorPosicaoId) {
    return {
      estado: "sem-gestor",
      codigo: "INVALID_INPUT",
      mensagem: "Selecione a posição do gestor para definir a reporting line.",
    };
  }

  const ocupacao = ocupacaoVigenteDoColaborador(entrada.estrutura, entrada.collaboratorId);
  const subordinatePositionId = ocupacao?.posicaoId ?? entrada.posicaoId;

  const linha = await confirmarReportingLine(
    {
      estrutura: entrada.estrutura,
      subordinatePositionId,
      managerPositionId: entrada.gestorPosicaoId,
      vigencia: entrada.vigencia,
      motivo: entrada.motivo,
      operationId: entrada.operationIdReporting,
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  if (linha.tipo !== "concluida") {
    const erro = recusaParaErro(linha);
    return { estado: "sem-gestor", codigo: erro.codigo, mensagem: erro.mensagem };
  }
  if (!linha.resultado.ok) {
    return {
      estado: "sem-gestor",
      codigo: linha.resultado.codigo,
      mensagem: linha.resultado.mensagem,
    };
  }

  return { estado: "completa" };
}

/**
 * Fluxo completo do formulário: cria a pessoa e, se pedido, aloca. Chamado UMA
 * vez por submissão — a tela não pode reutilizá-lo depois de existir
 * `collaboratorId` (a criação da pessoa está encerrada).
 */
export async function criarColaboradorComAlocacao(
  entrada: EntradaCriarComAlocacao,
  deps: DependenciasAcessoColaboradores = {}
): Promise<DesfechoCadastroAlocacao> {
  const cadastro = await criarColaborador(
    {
      fullName: entrada.dados.fullName,
      email: entrada.dados.email,
      matricula: entrada.dados.matricula,
      ...(entrada.dados.admissionDate ? { admissionDate: entrada.dados.admissionDate } : {}),
      statusInicial: entrada.dados.statusInicial,
      operationId: entrada.operationIdCadastro,
      ...(entrada.organizationId ? { organizationId: entrada.organizationId } : {}),
    },
    deps
  );

  if (!cadastro.ok) {
    return { tipo: "erro-cadastro", codigo: cadastro.codigo, mensagem: cadastro.mensagem };
  }

  const collaboratorId = cadastro.dados;
  if (!entrada.alocacao) {
    return { tipo: "criado", collaboratorId, alocacao: { estado: "nenhuma" } };
  }

  const alocacao = await tentarOcupacao(
    {
      estrutura: entrada.estrutura,
      organizationId: entrada.organizationId,
      collaboratorId,
      posicaoId: entrada.alocacao.posicaoId,
      vigencia: entrada.alocacao.vigencia,
      motivo: entrada.alocacao.motivo,
      gestorPosicaoId: entrada.alocacao.gestorPosicaoId,
      operationIdOcupacao: entrada.alocacao.operationIdOcupacao,
      operationIdReporting: entrada.alocacao.operationIdReporting,
    },
    deps
  );

  return { tipo: "criado", collaboratorId, alocacao };
}
