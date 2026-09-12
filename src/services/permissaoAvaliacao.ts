import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import { getCicloAtivo } from "./cicloAvaliacaoStorage";
import { getColaboradoresEfetivosNoCiclo } from "./historicoOrganizacionalStorage";
import {
  avaliadoresColegiadoSoberanos,
  gestorSoberano,
  raizDaCadeiaSoberana,
  resolverProjecaoEstrutural,
  usaEstruturaAvaliacaoSoberana,
  vinculoEstrutural,
  type ProjecaoEstruturalSoberana,
} from "./projecaoEstruturalSoberana";

export type PermissoesAvaliacao = {
  podeAvaliarComoGerente: boolean;
  podeAvaliarComoCoordenador: boolean;
  podeAvaliarComoColegiado: boolean;
  podeAvaliar: boolean;
  papeisPermitidos: string[];
};

function semPermissoes(): PermissoesAvaliacao {
  return {
    podeAvaliarComoGerente: false,
    podeAvaliarComoCoordenador: false,
    podeAvaliarComoColegiado: false,
    podeAvaliar: false,
    papeisPermitidos: [],
  };
}

/**
 * Mundo de apoio: os colaboradores EFETIVOS do ciclo (snapshot F3-08), apenas
 * para o adaptador de fixture em DEV. Em produção a projeção é a soberana
 * (injetada) ou VAZIA — este mundo nunca decide papel.
 */
function mundoEfetivo(
  colaboradorAvaliado: Colaborador,
  colaboradores: readonly Colaborador[],
  ciclo: CicloAvaliacao | undefined
): readonly Colaborador[] {
  const porMatricula = new Map<number, Colaborador>();
  [...colaboradores, colaboradorAvaliado].forEach((colaborador) =>
    porMatricula.set(colaborador.matricula, colaborador)
  );
  const base = Array.from(porMatricula.values());
  return ciclo ? getColaboradoresEfetivosNoCiclo(ciclo, base) : base;
}

/**
 * Permissões de avaliação (gerente responsável, coordenador direto, colegiado).
 *
 * F5-08 P6 (correção da auditoria): papel, cadeia e colegiado vêm da PROJEÇÃO
 * ESTRUTURAL SOBERANA — nunca de `funcao` textual nem de
 * `gestorDiretoMatricula` local. Sem evidência estrutural NENHUM papel é
 * concedido (fail-closed), jamais por fallback local.
 */
export function obterPermissoesAvaliacao(
  usuarioAtual: Colaborador | undefined,
  colaboradorAvaliado: Colaborador,
  colaboradores: Colaborador[],
  ciclo: CicloAvaliacao | undefined = getCicloAtivo(),
  projecaoEstrutural?: ProjecaoEstruturalSoberana
): PermissoesAvaliacao {
  if (!usuarioAtual) return semPermissoes();

  const projecao =
    projecaoEstrutural ??
    resolverProjecaoEstrutural(
      undefined,
      mundoEfetivo(colaboradorAvaliado, colaboradores, ciclo)
    );

  const vinculo = vinculoEstrutural(projecao, colaboradorAvaliado.matricula);
  // FAIL-CLOSED: sem evidência estrutural soberana não há papel a conceder.
  if (!vinculo) return semPermissoes();

  // F4-09 (D2/D3): o "gerente responsável" é a RAIZ da cadeia (dado
  // estrutural), nunca `funcao`.
  const raiz = raizDaCadeiaSoberana(projecao, colaboradorAvaliado.matricula);
  const podeAvaliarComoGerente =
    raiz !== null && raiz === usuarioAtual.matricula;

  const usaEstrutura = usaEstruturaAvaliacaoSoberana(
    projecao,
    colaboradorAvaliado.matricula
  );

  const podeAvaliarComoCoordenador =
    usaEstrutura &&
    gestorSoberano(projecao, colaboradorAvaliado.matricula) ===
      usuarioAtual.matricula;

  const podeAvaliarComoColegiado =
    usaEstrutura &&
    avaliadoresColegiadoSoberanos(
      projecao,
      colaboradorAvaliado.matricula
    ).includes(usuarioAtual.matricula);

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
