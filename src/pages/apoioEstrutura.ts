/**
 * F5-08 P4 — apoio das telas de ESTRUTURA (Unidades, Posições, Colegiado) e
 * CATÁLOGOS (cargos e senioridades).
 *
 * Só utilidades de APRESENTAÇÃO e de formulário:
 * - nenhuma regra de autorização, de tenant, de ciclo ou de vigência é decidida
 *   aqui (as guardas I1–I5 vivem na RPC/banco e o gate de capability vive na
 *   Edge);
 * - nomes/códigos são RÓTULOS: toda identidade manipulada e enviada é UUID;
 * - ausência é exibida explicitamente ("sem colegiado", "sem superior",
 *   "sem relação registrada"), nunca preenchida por heurística local;
 * - nada é lido/escrito em `localStorage`.
 */

import type { CodigoPublico } from "../infrastructure/supabase/colaboradores/contrato";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";

/** Estado explícito da leitura soberana da estrutura. */
export type EstadoEstrutura =
  | { readonly fase: "carregando" }
  | {
      readonly fase: "erro";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    }
  | { readonly fase: "pronto"; readonly estrutura: EstruturaSoberana };

export type ErroOperacao = {
  readonly codigo: CodigoPublico;
  readonly mensagem: string;
};

export const SEM_ORGANIZACAO_ATIVA =
  "Selecione uma organização ativa para administrar a estrutura.";

export const TEXTO_ERRO_ESTRUTURA =
  "Sem estrutura cadastrada: nenhuma unidade, posição, cargo ou senioridade foi " +
  "registrada nesta organização.";

/**
 * `operationId` (idempotência da mutação, D13) gerado pelo chamador. NÃO é
 * identidade nem autoridade: existe apenas para a fronteira não duplicar efeito.
 */
export function novoOperationId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (caractere) => {
    const aleatorio = Math.floor(Math.random() * 16);
    const valor = caractere === "x" ? aleatorio : (aleatorio & 0x3) | 0x8;
    return valor.toString(16);
  });
}

/** Data local de hoje (`YYYY-MM-DD`) — default de formulário, não regra. */
export function hojeLocal(): string {
  const agora = new Date();
  const offset = agora.getTimezoneOffset();
  return new Date(agora.getTime() - offset * 60000).toISOString().slice(0, 10);
}

/**
 * Instante de referência da apresentação temporal (ISO-8601 em UTC).
 *
 * É apenas o "agora" usado para decidir o que está VIGENTE na fotografia lida do
 * servidor. Nenhum fuso é inventado: o valor é um INSTANTE e a comparação é feita
 * em época (ms), de modo que `2026-06-15T09:00:00-03:00` e
 * `2026-06-15T12:00:00Z` são o MESMO instante. Injetável em teste.
 */
export function agoraIso(): string {
  return new Date().toISOString();
}

/** Converte um valor temporal do PostgREST em época (ms); `null` se inválido. */
function instanteMs(valor: string | null | undefined): number | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  if (limpo.length === 0) return null;
  const ms = Date.parse(limpo);
  return Number.isFinite(ms) ? ms : null;
}

/**
 * Situação de uma janela temporal na data de referência, no modelo MEIO-ABERTO
 * `[valid_from, valid_to)` do contrato F5-08/F3:
 *
 * - `vigente`  ⇒ `valid_from <= referencia && (valid_to === null || referencia < valid_to)`;
 * - `futura`   ⇒ a janela ainda não começou;
 * - `encerrada`⇒ a janela já terminou (`referencia >= valid_to`).
 *
 * Valor inválido/ausente é FAIL-CLOSED: nunca é tratado como vigente. Isto é
 * SELEÇÃO/APRESENTAÇÃO temporal da fotografia soberana — as guardas de domínio
 * (I1–I5, ciclo, imutabilidade) continuam na RPC/banco.
 */
export type SituacaoTemporal = "vigente" | "futura" | "encerrada";

export function situacaoTemporal(
  validFrom: string | null | undefined,
  validTo: string | null | undefined,
  referencia: string = agoraIso()
): SituacaoTemporal | "invalida" {
  const inicio = instanteMs(validFrom);
  const ref = instanteMs(referencia);
  // `null`/ausente = "sem término definido"; presente e inválido = FAIL-CLOSED.
  const fimBruto = validTo === null || validTo === undefined ? null : validTo;
  const fim = fimBruto === null ? null : instanteMs(fimBruto);

  if (inicio === null || ref === null) return "invalida";
  if (fimBruto !== null && fim === null) return "invalida";
  if (fim !== null && fim <= inicio) return "invalida"; // janela degenerada

  if (ref < inicio) return "futura";
  if (fim !== null && ref >= fim) return "encerrada";
  return "vigente";
}

/**
 * A janela está VIGENTE na referência? Intervalo meio-aberto `[from, to)`:
 * o início é INCLUSIVO e o fim é EXCLUSIVO (`referencia === valid_to` ⇒ NÃO
 * vigente). `valid_to` nulo significa "sem término definido" — inclusive para
 * uma linha que hoje já tem `valid_to` FUTURO (continua vigente até a data).
 */
export function estaVigente(
  validFrom: string | null | undefined,
  validTo: string | null | undefined,
  referencia: string = agoraIso()
): boolean {
  return situacaoTemporal(validFrom, validTo, referencia) === "vigente";
}

/** Rótulo de apresentação da janela temporal (vigente/futura/encerrada). */
export function rotuloVigencia(
  validFrom: string | null | undefined,
  validTo: string | null | undefined,
  referencia: string = agoraIso()
): string {
  const situacao = situacaoTemporal(validFrom, validTo, referencia);
  if (situacao === "vigente") {
    return validTo
      ? `Vigente desde ${formatarData(validFrom ?? "")} até ${formatarData(validTo)}`
      : `Vigente desde ${formatarData(validFrom ?? "")}`;
  }
  if (situacao === "futura") {
    return `Programada para ${formatarData(validFrom ?? "")}`;
  }
  if (situacao === "encerrada") {
    return `Encerrada em ${formatarData(validTo ?? "")}`;
  }
  return "Vigência não informada pelo servidor";
}

export function rotuloStatusCatalogo(status: string): string {
  if (status === "active") return "Ativo";
  if (status === "disabled") return "Inativo";
  return status || "—";
}

/** Data legível; valores ausentes/ inválidos permanecem explícitos. */
export function formatarData(valor: string): string {
  if (!valor) return "—";
  const somenteData = valor.slice(0, 10);
  const partes = somenteData.split("-");
  if (partes.length !== 3) return somenteData;
  const [ano, mes, dia] = partes;
  return `${dia}/${mes}/${ano}`;
}

function nomeOuAusente(
  itens: readonly { readonly id: string; readonly nome: string }[],
  id: string
): string {
  const encontrado = itens.find((item) => item.id === id);
  return encontrado && encontrado.nome ? encontrado.nome : "—";
}

/** Nome do colaborador como RÓTULO; desconhecido ⇒ "—" (nunca inventa). */
export function nomeDoColaborador(estrutura: EstruturaSoberana, collaboratorId: string): string {
  return nomeOuAusente(
    estrutura.colaboradores.map((item) => ({
      id: item.collaboratorId,
      nome: item.nome,
    })),
    collaboratorId
  );
}

/** Nome da unidade como RÓTULO; desconhecida ⇒ "—" (nunca inventa). */
export function nomeDaUnidade(estrutura: EstruturaSoberana, unitId: string): string {
  return nomeOuAusente(
    estrutura.unidades.map((item) => ({ id: item.unitId, nome: item.nome })),
    unitId
  );
}

/** Rótulo do cargo (`CODE — nome` quando há código). */
export function rotuloDoCargo(estrutura: EstruturaSoberana, jobRoleId: string): string {
  const cargo = estrutura.cargos.find((item) => item.jobRoleId === jobRoleId);
  if (!cargo) return "—";
  if (cargo.code && cargo.nome) return `${cargo.code} — ${cargo.nome}`;
  return cargo.nome || cargo.code || "—";
}

export function rotuloDaSenioridade(
  estrutura: EstruturaSoberana,
  seniorityLevelId: string | null
): string {
  if (!seniorityLevelId) return "sem senioridade";
  const senioridade = estrutura.senioridades.find(
    (item) => item.seniorityLevelId === seniorityLevelId
  );
  return senioridade?.nome || "—";
}

/** Período pai/filho VIGENTE na referência (meio-aberto `[from, to)`). */
export function periodoParentVigente(
  estrutura: EstruturaSoberana,
  unitId: string,
  referencia: string = agoraIso()
): { readonly parentUnitId: string | null } | null {
  const vigente = estrutura.periodosParent.find(
    (periodo) =>
      periodo.unitId === unitId &&
      estaVigente(periodo.validFrom, periodo.validTo, referencia)
  );
  return vigente ? { parentUnitId: vigente.parentUnitId } : null;
}

/** Ocupação VIGENTE de uma posição (quem ocupa hoje), se houver. */
export function ocupanteDaPosicao(
  estrutura: EstruturaSoberana,
  posicaoId: string,
  referencia: string = agoraIso()
): string | null {
  const vigente = estrutura.ocupacoes.find(
    (ocupacao) =>
      ocupacao.posicaoId === posicaoId &&
      estaVigente(ocupacao.validFrom, ocupacao.validTo, referencia)
  );
  return vigente ? vigente.collaboratorId : null;
}

/** Reporting line VIGENTE de uma posição (superior formal), se houver. */
export function superiorDaPosicao(
  estrutura: EstruturaSoberana,
  posicaoId: string,
  referencia: string = agoraIso()
): string | null {
  const vigente = estrutura.reportingLines.find(
    (linha) =>
      linha.subordinatePositionId === posicaoId &&
      estaVigente(linha.validFrom, linha.validTo, referencia)
  );
  return vigente ? vigente.managerPositionId : null;
}

/**
 * Rótulo curto de uma posição para seleção/exibição: `unidade • cargo
 * (senioridade)`. É apresentação — a identidade enviada continua sendo o UUID.
 */
export function rotuloDaPosicao(estrutura: EstruturaSoberana, posicaoId: string): string {
  const posicao = estrutura.posicoes.find((item) => item.posicaoId === posicaoId);
  if (!posicao) return "—";
  const unidade = nomeDaUnidade(estrutura, posicao.unitId);
  const cargo = rotuloDoCargo(estrutura, posicao.jobRoleId);
  const senioridade = posicao.seniorityLevelId
    ? rotuloDaSenioridade(estrutura, posicao.seniorityLevelId)
    : null;
  return `${unidade} • ${cargo}${senioridade ? ` (${senioridade})` : ""}`;
}

/**
 * Configuração de colegiado VIGENTE do avaliado (ou `null` quando não há).
 * A ausência de versão vigente é exibida como tal — nunca como "sem colegiado"
 * (que é uma versão vigente com ZERO membros).
 */
export function colegiadoVigente(
  estrutura: EstruturaSoberana,
  collaboratorId: string,
  referencia: string = agoraIso()
): { readonly colegiadoId: string; readonly membroIds: readonly string[] } | null {
  const vigente = estrutura.colegiados.find(
    (colegiado) =>
      colegiado.collaboratorId === collaboratorId &&
      estaVigente(colegiado.validFrom, colegiado.validTo, referencia)
  );
  return vigente
    ? { colegiadoId: vigente.colegiadoId, membroIds: [...vigente.membroIds] }
    : null;
}

/** Histórico de versões do avaliado, da mais recente para a mais antiga. */
export function historicoColegiado(
  estrutura: EstruturaSoberana,
  collaboratorId: string
): readonly {
  readonly colegiadoId: string;
  readonly validFrom: string;
  readonly validTo: string | null;
  readonly membroIds: readonly string[];
}[] {
  return estrutura.colegiados
    .filter((colegiado) => colegiado.collaboratorId === collaboratorId)
    .map((colegiado) => ({
      colegiadoId: colegiado.colegiadoId,
      validFrom: colegiado.validFrom,
      validTo: colegiado.validTo,
      membroIds: [...colegiado.membroIds],
    }));
}

/**
 * Profundidade de apresentação da unidade na árvore de parent. É EXIBIÇÃO: a
 * ausência de ciclo é garantida no banco (I1 + trigger), e o corte por
 * `visitados` protege apenas o render contra dado inconsistente.
 */
export function profundidadeDaUnidade(
  estrutura: EstruturaSoberana,
  unitId: string,
  referencia: string = agoraIso()
): number {
  let profundidade = 0;
  let atual = unitId;
  const visitados = new Set<string>([unitId]);
  for (let passo = 0; passo < 64; passo += 1) {
    const periodo = periodoParentVigente(estrutura, atual, referencia);
    if (!periodo || !periodo.parentUnitId) break;
    if (visitados.has(periodo.parentUnitId)) break;
    visitados.add(periodo.parentUnitId);
    atual = periodo.parentUnitId;
    profundidade += 1;
  }
  return profundidade;
}

// ---------------------------------------------------------------------------
// F5-08 P4 — versão otimista a partir da FOTOGRAFIA soberana
//
// `expectedVersion` NUNCA é fabricado: ou vem da fotografia lida do servidor, ou
// a intenção é recusada localmente (fail-closed) por estar construída sobre uma
// leitura que já não contém a entidade. Nenhuma regra de domínio é replicada: a
// decisão real de concorrência continua no servidor (`CONFLICT`).
// ---------------------------------------------------------------------------

export const MENSAGEM_FOTOGRAFIA_DESATUALIZADA =
  "A estrutura foi atualizada e o item em edição não está mais na leitura atual. " +
  "A leitura foi recarregada: revise o estado e tente novamente.";

export type DecisaoVersaoOtimista =
  | { readonly tipo: "enviar"; readonly expectedVersion: number }
  | {
      readonly tipo: "fotografia-desatualizada";
      readonly codigo: CodigoPublico;
      readonly mensagem: string;
    };

/**
 * Decide a versão otimista a enviar com base na fotografia CORRENTE. Devolve
 * `fotografia-desatualizada` (sem versão alguma) quando a entidade não existe
 * mais na leitura — jamais `0`, `1` ou qualquer default.
 */
export function decidirVersaoOtimista(
  itens: readonly { readonly id: string; readonly version: number }[],
  id: string
): DecisaoVersaoOtimista {
  const item = itens.find((candidato) => candidato.id === id);
  if (!item || typeof item.version !== "number" || !Number.isFinite(item.version)) {
    return {
      tipo: "fotografia-desatualizada",
      codigo: "CONFLICT",
      mensagem: MENSAGEM_FOTOGRAFIA_DESATUALIZADA,
    };
  }
  return { tipo: "enviar", expectedVersion: item.version };
}
