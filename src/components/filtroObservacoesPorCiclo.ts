import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Observacao } from "../types/Observacao";
import { ordenarPorAnoECiclo } from "../utils/ordenacaoPorCiclo";

export type FiltroCicloObservacoes = "TODOS" | `${number}-${number}`;

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

export function filtrarObservacoesPorCiclo(
  observacoes: readonly Observacao[],
  filtro: FiltroCicloObservacoes
): Observacao[] {
  if (filtro === "TODOS") return [...observacoes];

  const [ano, ciclo] = filtro.split("-").map(Number);
  return observacoes.filter(
    (observacao) => observacao.ano === ano && observacao.ciclo === ciclo
  );
}

export function contarObservacoesPorTipo(observacoes: readonly Observacao[]) {
  return observacoes.reduce(
    (total, observacao) => ({
      ...total,
      [observacao.tipo]: total[observacao.tipo] + 1,
    }),
    { POSITIVA: 0, NEUTRA: 0, NEGATIVA: 0 }
  );
}
