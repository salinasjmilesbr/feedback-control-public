import type { CicloSoberano } from "../application/ports/CycleRepository";
import type { ObservacaoSoberana } from "../application/ports/ObservationRepository";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Observacao } from "../types/Observacao";
import { ordenarPorAnoECiclo } from "../utils/ordenacaoPorCiclo";

/**
 * F5-11 P5 (Issue #250), L3 — filtro/KPI de observações com a IDENTIDADE
 * SOBERANA (`cycleId` UUID).
 *
 * ## Por que o filtro mudou de eixo
 *
 * A projeção soberana (`ObservacaoSoberana`) identifica o ciclo por `cycleId`
 * (UUID de `evaluation_cycles.id`) e **não** carrega `ano`/`ciclo`: esses são
 * RÓTULOS de projeção (§7.1/D1/D3), não identidade nem chave de leitura. Derivar
 * `ano`/`ciclo` a partir de um UUID exigiria uma tabela de identidade local —
 * exatamente a autoridade local que o cutover elimina. Logo:
 *
 * - `FiltroCicloObservacoesSoberano` é `{ cycleId }` ou `TODOS`;
 * - `filtrarObservacoesSoberanasPorCiclo`/`contarObservacoesSoberanasPorTipo`
 *   operam sobre a projeção soberana por `cycleId`;
 * - `ordenarCiclosSoberanosParaFiltro`/`getFiltroCicloSoberanoInicial` usam
 *   `CicloSoberano`, cujos `ano`/`numero` são **rótulos da própria projeção
 *   soberana** (não derivação) — por isso podem rotular o seletor.
 *
 * ## Legado preservado (compatibilidade de chamada, NÃO dual-read)
 *
 * As funções por `ano`/`ciclo` numéricos permanecem para o consumidor legado
 * ainda **não migrado** (`ColaboradorDetalhePage` → `AcervoLegado`, classificado
 * no §11.5 como consumidor de arrasto do cutover de página). Elas operam
 * EXCLUSIVAMENTE sobre o tipo legado `Observacao`: a leitura local **não** é
 * fallback do caminho soberano e **não existe** conversão UUID ↔ `ano`/`ciclo` em
 * nenhuma direção (não há ponte autoritativa — §10/D13).
 */

// ---------------------------------------------------------------------------
// Filtro SOBERANO (identidade por `cycleId`)
// ---------------------------------------------------------------------------

/** Filtro soberano: o UUID do ciclo ou todos os ciclos. */
export type FiltroCicloObservacoesSoberano = "TODOS" | { readonly cycleId: string };

/** Filtro inicial "todos" do painel (ausência explícita de recorte). */
export const FILTRO_OBSERVACOES_TODOS: FiltroCicloObservacoesSoberano = "TODOS";

export function getChaveCicloObservacoesSoberano(ciclo: Pick<CicloSoberano, "id">): string {
  return ciclo.id;
}

/**
 * Ordena os ciclos soberanos para o seletor, com o ciclo `ATIVO` primeiro.
 * `ano`/`numero` entram apenas como ORDENAÇÃO/rótulo da projeção soberana.
 */
export function ordenarCiclosSoberanosParaFiltro(
  ciclos: readonly CicloSoberano[]
): CicloSoberano[] {
  const ordenados = [...ciclos].sort((a, b) =>
    a.ano === b.ano ? b.numero - a.numero : b.ano - a.ano
  );
  const ativo = ordenados.find((ciclo) => ciclo.status === "ATIVO");

  return ativo ? [ativo, ...ordenados.filter((ciclo) => ciclo.id !== ativo.id)] : ordenados;
}

/** Filtro inicial: ciclo `ATIVO` (se houver) ou o mais recente; `TODOS` se vazio. */
export function getFiltroCicloSoberanoInicial(
  ciclos: readonly CicloSoberano[]
): FiltroCicloObservacoesSoberano {
  const primeiro = ordenarCiclosSoberanosParaFiltro(ciclos)[0];
  return primeiro ? { cycleId: primeiro.id } : FILTRO_OBSERVACOES_TODOS;
}

/** Filtra as observações soberanas pelo `cycleId` escolhido. */
export function filtrarObservacoesSoberanasPorCiclo(
  observacoes: readonly ObservacaoSoberana[],
  filtro: FiltroCicloObservacoesSoberano
): ObservacaoSoberana[] {
  if (filtro === "TODOS") return [...observacoes];
  return observacoes.filter((observacao) => observacao.cycleId === filtro.cycleId);
}

/** KPI por tipo sobre a projeção soberana (não depende de `ano`/`ciclo`). */
export function contarObservacoesSoberanasPorTipo(
  observacoes: readonly ObservacaoSoberana[]
): Record<ObservacaoSoberana["tipo"], number> {
  return observacoes.reduce(
    (total, observacao) => ({
      ...total,
      [observacao.tipo]: total[observacao.tipo] + 1,
    }),
    { POSITIVA: 0, NEUTRA: 0, NEGATIVA: 0 }
  );
}

// ---------------------------------------------------------------------------
// LEGADO (por `ano`/`ciclo` numéricos) — compatibilidade de chamada
// ---------------------------------------------------------------------------

export type FiltroCicloObservacoes = "TODOS" | `${number}-${number}`;

/**
 * União dos filtros aceitos: o SOBERANO (por `cycleId`) e o LEGADO (por
 * `ano`-`ciclo`). Cada consumidor passa a variante da SUA projeção.
 */
export type FiltroObservacoes =
  | FiltroCicloObservacoesSoberano
  | FiltroCicloObservacoes;

/**
 * KPI por tipo. Depende apenas de `tipo`, campo presente nas duas projeções —
 * por isso serve ao painel soberano e ao acervo legado, sem inventar identidade.
 */
export function contarObservacoesPorTipo(
  observacoes: readonly { readonly tipo: ObservacaoSoberana["tipo"] }[]
): Record<ObservacaoSoberana["tipo"], number> {
  return observacoes.reduce(
    (total, observacao) => ({
      ...total,
      [observacao.tipo]: total[observacao.tipo] + 1,
    }),
    { POSITIVA: 0, NEUTRA: 0, NEGATIVA: 0 }
  );
}

export function getChaveCicloObservacoes(
  ciclo: Pick<CicloAvaliacao, "ano" | "ciclo">
): FiltroCicloObservacoes {
  return `${ciclo.ano}-${ciclo.ciclo}`;
}

export function ordenarCiclosParaFiltro(
  ciclos: readonly CicloAvaliacao[]
): CicloAvaliacao[] {
  const ordenados = ordenarPorAnoECiclo(ciclos, "RECENTES");
  const ativo = ordenados.find((ciclo) => ciclo.status === "ATIVO");

  return ativo
    ? [ativo, ...ordenados.filter((ciclo) => ciclo.id !== ativo.id)]
    : ordenados;
}

export function getFiltroCicloInicial(
  ciclos: readonly CicloAvaliacao[]
): FiltroCicloObservacoes {
  const primeiro = ordenarCiclosParaFiltro(ciclos)[0];
  return primeiro ? getChaveCicloObservacoes(primeiro) : "TODOS";
}

/**
 * Filtro LEGADO por `ano`/`ciclo` numéricos. Se receber o filtro SOBERANO, a
 * resposta é a lista VAZIA: não existe derivação `cycleId` → `ano`/`ciclo`
 * (fail-closed; nada de heurística nem de dado inventado).
 */
export function filtrarObservacoesPorCiclo(
  observacoes: readonly Observacao[],
  filtro: FiltroObservacoes
): Observacao[] {
  if (filtro === "TODOS") return [...observacoes];
  if (typeof filtro !== "string") return [];

  const [ano, ciclo] = filtro.split("-").map(Number);
  return observacoes.filter(
    (observacao) => observacao.ano === ano && observacao.ciclo === ciclo
  );
}
