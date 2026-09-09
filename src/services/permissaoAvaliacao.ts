import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import { funcaoUsaEstruturaAvaliacaoAnalista } from "../types/Colaborador";
import { getCicloAtivo } from "./cicloAvaliacaoStorage";
import { getColaboradorEfetivoNoCiclo } from "./historicoOrganizacionalStorage";

export type PermissoesAvaliacao = {
  podeAvaliarComoGerente: boolean;
  podeAvaliarComoCoordenador: boolean;
  podeAvaliarComoColegiado: boolean;
  podeAvaliar: boolean;
  papeisPermitidos: string[];
};

function efetivo(
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  ciclo?: CicloAvaliacao
): Colaborador {
  return ciclo
    ? getColaboradorEfetivoNoCiclo(colaborador, ciclo, colaboradores)
    : colaborador;
}

function encontrarGerenteResponsavel(
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  ciclo?: CicloAvaliacao
): Colaborador | undefined {
  const porMatricula = new Map(
    colaboradores.map((item) => [item.matricula, item])
  );

  let atual: Colaborador | undefined = efetivo(
    colaborador,
    colaboradores,
    ciclo
  );
  const visitados = new Set<number>();

  while (atual?.gestorDiretoMatricula) {
    if (visitados.has(atual.gestorDiretoMatricula)) {
      return undefined;
    }

    visitados.add(atual.gestorDiretoMatricula);
    const gestorBase = porMatricula.get(atual.gestorDiretoMatricula);

    if (!gestorBase) return undefined;
    const gestor = efetivo(gestorBase, colaboradores, ciclo);
    atual = gestor;
  }

  // F4-09 (D2/D3): o "gerente responsável" é a RAIZ da cadeia (dado
  // estrutural `gestorDiretoMatricula`), nunca `funcao`.
  return atual;
}

export function obterPermissoesAvaliacao(
  usuarioAtual: Colaborador | undefined,
  colaboradorAvaliado: Colaborador,
  colaboradores: Colaborador[],
  ciclo = getCicloAtivo()
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

  const colaboradorEfetivo = efetivo(
    colaboradorAvaliado,
    colaboradores,
    ciclo
  );
  const gerenteResponsavel = encontrarGerenteResponsavel(
    colaboradorAvaliado,
    colaboradores,
    ciclo
  );

  const podeAvaliarComoGerente =
    gerenteResponsavel?.matricula === usuarioAtual.matricula;

  const podeAvaliarComoCoordenador =
    funcaoUsaEstruturaAvaliacaoAnalista(colaboradorEfetivo.funcao) &&
    colaboradorEfetivo.gestorDiretoMatricula === usuarioAtual.matricula;

  const podeAvaliarComoColegiado =
    funcaoUsaEstruturaAvaliacaoAnalista(colaboradorEfetivo.funcao) &&
    (colaboradorEfetivo.avaliadoresColegiadoMatriculas?.includes(
      usuarioAtual.matricula
    ) ?? false);

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
