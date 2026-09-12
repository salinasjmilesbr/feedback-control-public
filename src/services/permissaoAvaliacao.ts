import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import { getCicloAtivo } from "./cicloAvaliacaoStorage";
import { getColaboradoresEfetivosNoCiclo } from "./historicoOrganizacionalStorage";
import {
  estruturaSoberanaEfetiva,
  visaoEstruturalLegada,
  type EstruturaSoberanaDoCliente,
} from "./estruturaSoberanaCliente";

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
 * para o adaptador de fixture em DEV. Em produção a estrutura é a SOBERANA
 * publicada pelo shell autenticado — este mundo nunca decide papel.
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
 * F5-08 P6 (correção da auditoria): os fatos vêm da ESTRUTURA SOBERANA —
 * relações de posição/reporting line/ocupação vigente e colegiado vigente.
 * Nenhum papel é inferido de `funcao` textual, cargo, nome ou matrícula; sem
 * evidência estrutural NENHUM papel é concedido (fail-closed).
 */
export function obterPermissoesAvaliacao(
  usuarioAtual: Colaborador | undefined,
  colaboradorAvaliado: Colaborador,
  colaboradores: Colaborador[],
  ciclo: CicloAvaliacao | undefined = getCicloAtivo(),
  estruturaSoberana?: EstruturaSoberanaDoCliente
): PermissoesAvaliacao {
  if (!usuarioAtual) return semPermissoes();

  const estrutura =
    estruturaSoberana ??
    estruturaSoberanaEfetiva(
      mundoEfetivo(colaboradorAvaliado, colaboradores, ciclo)
    );

  const visao = visaoEstruturalLegada(estrutura, colaboradorAvaliado.matricula);
  // FAIL-CLOSED: sem evidência estrutural soberana não há papel a conceder.
  if (!visao) return semPermissoes();

  // F4-09 (D2/D3): o "gerente responsável" é a RAIZ da cadeia (dado relacional,
  // nunca `funcao`).
  const podeAvaliarComoGerente =
    visao.raizMatriculaLegada !== null &&
    visao.raizMatriculaLegada === usuarioAtual.matricula;

  // "Coordenador direto" = gestor direto que é NÍVEL INTERMEDIÁRIO (tem
  // superior). Gestor direto na raiz é o gerente responsável, não coordenador.
  const podeAvaliarComoCoordenador =
    visao.gestorMatriculaLegada !== null &&
    visao.gestorMatriculaLegada === usuarioAtual.matricula &&
    visao.gestorTemSuperior;

  // Colegiado: configuração VIGENTE na estrutura soberana.
  const podeAvaliarComoColegiado = visao.colegiadoMatriculasLegadas.includes(
    usuarioAtual.matricula
  );

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
