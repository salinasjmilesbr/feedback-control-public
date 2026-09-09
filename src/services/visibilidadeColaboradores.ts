import type { Colaborador } from "../types/Colaborador";

function obterDescendentes(
  gestorMatricula: number,
  colaboradores: Colaborador[]
): Colaborador[] {
  const resultado: Colaborador[] = [];
  const fila = [gestorMatricula];
  const visitados = new Set<number>();

  while (fila.length > 0) {
    const gestorAtual = fila.shift();

    if (gestorAtual === undefined || visitados.has(gestorAtual)) {
      continue;
    }

    visitados.add(gestorAtual);

    const subordinados = colaboradores.filter(
      (colaborador) =>
        colaborador.gestorDiretoMatricula === gestorAtual
    );

    for (const subordinado of subordinados) {
      if (
        !resultado.some(
          (item) => item.matricula === subordinado.matricula
        )
      ) {
        resultado.push(subordinado);
      }

      fila.push(subordinado.matricula);
    }
  }

  return resultado;
}

/**
 * F4-09 (D2/D3): alcance derivado dos DADOS (cadeia `gestorDiretoMatricula` e
 * colegiado), nunca de `funcao`. A raiz (sem gestor) enxerga os descendentes;
 * o gestor de 1º nível enxerga seus diretos + colegiado; demais não enxergam
 * ninguém (fail-closed).
 */
export function getColaboradoresVisiveis(
  usuarioAtual: Colaborador,
  colaboradores: Colaborador[]
): Colaborador[] {
  const ehRaiz = !usuarioAtual.gestorDiretoMatricula;

  if (ehRaiz) {
    return obterDescendentes(usuarioAtual.matricula, colaboradores);
  }

  const subordinadosDiretos = colaboradores.filter(
    (colaborador) =>
      colaborador.gestorDiretoMatricula === usuarioAtual.matricula
  );

  const participantesColegiado = colaboradores.filter(
    (colaborador) =>
      colaborador.avaliadoresColegiadoMatriculas?.includes(
        usuarioAtual.matricula
      ) ?? false
  );

  if (
    subordinadosDiretos.length === 0 &&
    participantesColegiado.length === 0
  ) {
    return [];
  }

  const unicos = new Map<number, Colaborador>();
  [...subordinadosDiretos, ...participantesColegiado].forEach(
    (colaborador) => unicos.set(colaborador.matricula, colaborador)
  );
  return Array.from(unicos.values());
}
