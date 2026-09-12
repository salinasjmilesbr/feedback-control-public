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

/** Vigência aberta = `valid_to` nulo (período meio-aberto [from, to)). */
export function estaVigente(validTo: string | null): boolean {
  return validTo === null;
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

/** Períodos pai/filho ABERTOS (vigentes) por unidade. */
export function periodoParentVigente(
  estrutura: EstruturaSoberana,
  unitId: string
): { readonly parentUnitId: string | null } | null {
  const aberto = estrutura.periodosParent.find(
    (periodo) => periodo.unitId === unitId && estaVigente(periodo.validTo)
  );
  return aberto ? { parentUnitId: aberto.parentUnitId } : null;
}

/** Ocupação ABERTA de uma posição (quem ocupa hoje), se houver. */
export function ocupanteDaPosicao(
  estrutura: EstruturaSoberana,
  posicaoId: string
): string | null {
  const aberta = estrutura.ocupacoes.find(
    (ocupacao) => ocupacao.posicaoId === posicaoId && estaVigente(ocupacao.validTo)
  );
  return aberta ? aberta.collaboratorId : null;
}

/** Reporting line ABERTA de uma posição (superior formal), se houver. */
export function superiorDaPosicao(
  estrutura: EstruturaSoberana,
  posicaoId: string
): string | null {
  const aberta = estrutura.reportingLines.find(
    (linha) => linha.subordinatePositionId === posicaoId && estaVigente(linha.validTo)
  );
  return aberta ? aberta.managerPositionId : null;
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
  collaboratorId: string
): { readonly colegiadoId: string; readonly membroIds: readonly string[] } | null {
  const vigente = estrutura.colegiados.find(
    (colegiado) => colegiado.collaboratorId === collaboratorId && estaVigente(colegiado.validTo)
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
export function profundidadeDaUnidade(estrutura: EstruturaSoberana, unitId: string): number {
  let profundidade = 0;
  let atual = unitId;
  const visitados = new Set<string>([unitId]);
  for (let passo = 0; passo < 64; passo += 1) {
    const periodo = periodoParentVigente(estrutura, atual);
    if (!periodo || !periodo.parentUnitId) break;
    if (visitados.has(periodo.parentUnitId)) break;
    visitados.add(periodo.parentUnitId);
    atual = periodo.parentUnitId;
    profundidade += 1;
  }
  return profundidade;
}
