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

export function getColaboradoresVisiveis(
  usuarioAtual: Colaborador,
  colaboradores: Colaborador[]
): Colaborador[] {
  if (usuarioAtual.funcao === "GERENTE") {
    return obterDescendentes(usuarioAtual.matricula, colaboradores);
  }

  if (usuarioAtual.funcao === "COORDENADOR") {
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

    const unicos = new Map<number, Colaborador>();

    [...subordinadosDiretos, ...participantesColegiado].forEach(
      (colaborador) => unicos.set(colaborador.matricula, colaborador)
    );

    return Array.from(unicos.values());
  }

  return [];
}
