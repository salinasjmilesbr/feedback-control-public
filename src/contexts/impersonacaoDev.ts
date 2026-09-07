import type { Colaborador } from "../types/Colaborador";

/**
 * Lógica pura da impersonação de desenvolvimento (F2-09).
 *
 * A impersonação DEV é um contexto local de visão sobre colaboradores
 * SINTÉTICOS (seed de desenvolvimento) — ela NÃO é autenticação: não altera
 * `auth.uid()`, JWT ou sessão do Supabase Auth, não participa de chamadas
 * server-side como autorização e nunca deve contornar RLS/segurança do
 * servidor. Fora de DEV explícito (`simulacaoDev === false`) nada é carregado
 * e a troca é bloqueada (fail-closed).
 */

/** Marcador local da seleção de impersonação DEV (compatível com dados antigos). */
export const CHAVE_USUARIO_ATUAL_DEV = "feedback-control-usuario-atual";

function ordemFuncao(usuario: Colaborador): number {
  if (usuario.funcao === "GERENTE") return 0;
  if (usuario.funcao === "COORDENADOR") return 1;
  if (usuario.funcao === "CONSULTOR") return 2;
  if (usuario.funcao === "ANALISTA" && usuario.senioridade === "SENIOR") {
    return 3;
  }
  if (usuario.funcao === "ANALISTA" && usuario.senioridade === "PLENO") {
    return 4;
  }
  if (usuario.funcao === "ANALISTA" && usuario.senioridade === "JUNIOR") {
    return 5;
  }
  if (usuario.funcao === "ANALISTA") return 6;
  if (usuario.funcao === "ESTAGIARIO") return 7;
  return 8;
}

/**
 * Candidatos da impersonação DEV: somente em DEV explícito (fora dele devolve
 * lista vazia — HOMOLOG/PROD nunca carregam colaborador simulado). Dentro do
 * gate, filtra ativos e ordena pelo perfil operacional.
 */
export function candidatosImpersonacaoDev(
  simulacaoDev: boolean,
  usuarios: Colaborador[]
): Colaborador[] {
  if (!simulacaoDev) return [];

  return usuarios
    .filter((usuario) => usuario.status === "ATIVO")
    .sort((a, b) => {
      const ordemA = ordemFuncao(a);
      const ordemB = ordemFuncao(b);

      if (ordemA !== ordemB) return ordemA - ordemB;

      return a.nome.localeCompare(b.nome, "pt-BR");
    });
}

/**
 * Matrícula inicial da impersonação DEV: preserva a seleção anterior quando
 * ela continua válida (compatibilidade com `localStorage` existente); senão,
 * usa o primeiro perfil operacional padrão (GERENTE ativo) ou o primeiro da
 * lista. Sem candidatos, retorna `undefined`.
 */
export function resolverMatriculaInicialDev(
  matriculaSalva: number | undefined,
  candidatos: Colaborador[]
): number | undefined {
  if (
    matriculaSalva !== undefined &&
    Number.isFinite(matriculaSalva) &&
    candidatos.some((usuario) => usuario.matricula === matriculaSalva)
  ) {
    return matriculaSalva;
  }

  return (
    candidatos.find(
      (usuario) =>
        usuario.status === "ATIVO" && usuario.funcao === "GERENTE"
    )?.matricula ?? candidatos[0]?.matricula
  );
}

/**
 * Porta única da troca de identidade DEV: fora de DEV explícito a troca é
 * bloqueada (devolve `undefined` — nada é persistido ou aplicado).
 */
export function selecionarMatriculaDev(
  simulacaoDev: boolean,
  matricula: number
): number | undefined {
  return simulacaoDev ? matricula : undefined;
}
