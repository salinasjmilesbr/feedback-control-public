export type OrdemPorCiclo = "RECENTES" | "ANTIGAS";

type ItemComAnoECiclo = {
  id: string;
  ano?: number;
  ciclo?: number;
};

export function ordenarPorAnoECiclo<T extends ItemComAnoECiclo>(
  itens: readonly T[],
  ordem: OrdemPorCiclo
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

    return a.id.localeCompare(b.id);
  });
}
