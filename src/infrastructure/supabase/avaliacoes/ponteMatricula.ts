/**
 * F5-06 (Issue #103) — PONTE matrícula → identidade técnica (UUID).
 *
 * As telas legadas identificam pessoas por MATRÍCULA (`Colaborador.matricula`,
 * número). O caminho soberano identifica por `collaborators.id` (UUID). A F3-01
 * guarda a matrícula como identificador de negócio (`collaborator_identifiers.
 * business_code`) com validade temporal — é essa a fonte estrutural da ponte.
 *
 * Regras:
 * - a resolução acontece SEMPRE na fronteira confiável (a tabela é fechada a
 *   `authenticated`); este módulo só define o formato e interpreta o resultado;
 * - nada aqui concede autorização: o UUID resolvido é apenas o ALVO da operação,
 *   que ainda passa pelo Policy Engine;
 * - matrícula ausente, inválida ou não resolvida ⇒ `null` (fail-closed): a tela
 *   não pode inventar identidade.
 */

/** Matrícula legada: inteiro positivo (o cliente usa `number`). */
export function normalizarMatricula(valor: unknown): number | null {
  if (typeof valor === "number") {
    return Number.isInteger(valor) && valor > 0 ? valor : null;
  }
  if (typeof valor === "string") {
    const limpo = valor.trim();
    if (!/^\d+$/.test(limpo)) return null;
    const numero = Number.parseInt(limpo, 10);
    return numero > 0 ? numero : null;
  }
  return null;
}

/** Código de negócio usado na consulta (texto canônico da matrícula). */
export function codigoDeNegocioDaMatricula(valor: unknown): string | null {
  const matricula = normalizarMatricula(valor);
  return matricula === null ? null : String(matricula);
}

interface LinhaIdentificador {
  collaborator_id?: unknown;
  organization_id?: unknown;
  business_code?: unknown;
  valid_to?: unknown;
}

/**
 * Interpreta o resultado da consulta de identificadores, escolhendo a linha
 * ABERTA (`valid_to` nulo) do tenant. Sem linha aberta ⇒ `null` (fail-closed).
 */
export function extrairColaboradorDoIdentificador(
  linhas: unknown,
  organizationId: string
): string | null {
  if (!Array.isArray(linhas) || linhas.length === 0) return null;

  const abertas = (linhas as LinhaIdentificador[]).filter(
    (linha) =>
      linha.organization_id === organizationId &&
      (linha.valid_to === null || linha.valid_to === undefined) &&
      typeof linha.collaborator_id === "string" &&
      linha.collaborator_id.length > 0
  );

  // Mais de uma linha aberta é inconsistência: não escolhe arbitrariamente.
  if (abertas.length !== 1) return null;
  return String(abertas[0]!.collaborator_id);
}
