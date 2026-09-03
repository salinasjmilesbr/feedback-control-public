export type OrdemPorCiclo = "RECENTES" | "ANTIGAS";

type ItemComAnoECiclo = {
  id: string;
  ano?: number;
  ciclo?: number;
};

export function ordenarPorAnoECiclo<T extends ItemComAnoECiclo>(
  itens: readonly T[],
  ordem: OrdemPorCiclo,
  obterDataOriginal?: (item: T) => string | undefined
): T[] {
  const direcao = ordem === "RECENTES" ? -1 : 1;

  return [...itens].sort((a, b) => {
    const aTemCiclo = a.ano !== undefined && a.ciclo !== undefined;
    const bTemCiclo = b.ano !== undefined && b.ciclo !== undefined;

    if (aTemCiclo !== bTemCiclo) return aTemCiclo ? -1 : 1;

    if (aTemCiclo && bTemCiclo) {
      const porAno = (a.ano! - b.ano!) * direcao;
      if (porAno !== 0) return porAno;

      const porCiclo = (a.ciclo! - b.ciclo!) * direcao;
      if (porCiclo !== 0) return porCiclo;
    }

    if (obterDataOriginal) {
      const dataA = Date.parse(obterDataOriginal(a) ?? "");
      const dataB = Date.parse(obterDataOriginal(b) ?? "");

      if (!Number.isNaN(dataA) && !Number.isNaN(dataB)) {
        const porData = (dataA - dataB) * direcao;
        if (porData !== 0) return porData;
      }
    }

    return a.id.localeCompare(b.id);
  });
}
