import type { Colaborador } from "../types/Colaborador";

export type PermissoesAvaliacao = {
  podeAvaliarComoGerente: boolean;
  podeAvaliarComoCoordenador: boolean;
  podeAvaliarComoColegiado: boolean;
  podeAvaliar: boolean;
  papeisPermitidos: string[];
};

function encontrarGerenteResponsavel(
  colaborador: Colaborador,
  colaboradores: Colaborador[]
): Colaborador | undefined {
  const porMatricula = new Map(
    colaboradores.map((item) => [item.matricula, item])
  );

  let atual: Colaborador | undefined = colaborador;
  const visitados = new Set<number>();

  while (atual?.gestorDiretoMatricula) {
    if (visitados.has(atual.gestorDiretoMatricula)) {
      return undefined;
    }

    visitados.add(atual.gestorDiretoMatricula);
    const gestor = porMatricula.get(atual.gestorDiretoMatricula);

    if (!gestor) return undefined;
    if (gestor.funcao === "GERENTE") return gestor;

    atual = gestor;
  }

  return undefined;
}

export function obterPermissoesAvaliacao(
  usuarioAtual: Colaborador | undefined,
  colaboradorAvaliado: Colaborador,
  colaboradores: Colaborador[]
): PermissoesAvaliacao {
  if (!usuarioAtual) {
    return {
      podeAvaliarComoGerente: false,
      podeAvaliarComoCoordenador: false,
      podeAvaliarComoColegiado: false,
      podeAvaliar: false,
      papeisPermitidos: [],
    };
  }

  const gerenteResponsavel = encontrarGerenteResponsavel(
    colaboradorAvaliado,
    colaboradores
  );

  const podeAvaliarComoGerente =
    usuarioAtual.funcao === "GERENTE" &&
    gerenteResponsavel?.matricula === usuarioAtual.matricula;

  const podeAvaliarComoCoordenador =
    usuarioAtual.funcao === "COORDENADOR" &&
    colaboradorAvaliado.gestorDiretoMatricula === usuarioAtual.matricula;

  const podeAvaliarComoColegiado =
    colaboradorAvaliado.avaliadoresColegiadoMatriculas?.includes(
      usuarioAtual.matricula
    ) ?? false;

  const papeisPermitidos: string[] = [];

  if (podeAvaliarComoGerente) papeisPermitidos.push("Gerente");
  if (podeAvaliarComoCoordenador) papeisPermitidos.push("Coordenador direto");
  if (podeAvaliarComoColegiado) papeisPermitidos.push("Colegiado");

  return {
    podeAvaliarComoGerente,
    podeAvaliarComoCoordenador,
    podeAvaliarComoColegiado,
    podeAvaliar:
      podeAvaliarComoGerente ||
      podeAvaliarComoCoordenador ||
      podeAvaliarComoColegiado,
    papeisPermitidos,
  };
}
