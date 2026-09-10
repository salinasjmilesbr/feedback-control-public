/**
 * F5-06 (Issue #103) — contrato TRANSPORTÁVEL do caminho novo de avaliações.
 *
 * Este módulo define a superfície que o cliente pode pedir e o que a fronteira
 * confiável devolve. Invariantes (D3/D6/D10/D23/D26/D27):
 * - o cliente envia apenas a INTENÇÃO (operação, alvo, dados de entrada);
 * - `organization_id` é intenção a ser REVALIDADA contra membership ativa;
 * - identificadores são UUID (`collaborators.id` / `evaluations.id`), nunca
 *   matrícula, nome ou e-mail;
 * - nenhum `actor_id`, `participant_id` forjado ou `config_version_id` do
 *   cliente é aceito como autoridade: o snapshot de participantes e a versão de
 *   configuração são derivados server-side;
 * - a resposta de erro expõe somente código público (F0-05), nunca a razão
 *   interna da negação.
 */

/** Operações suportadas pelo caminho novo (avaliações em PostgreSQL). */
export type OperacaoAvaliacao =
  | "evaluation.criar"
  | "evaluation.ler"
  | "evaluation.gravar_notas"
  | "evaluation.gravar_comentario"
  | "evaluation.concluir"
  | "evaluation.reabrir"
  | "evaluation.cancelar"
  | "evaluation.participantes_realinhar"
  | "evaluation.transparencia";

/** Alvo autorizável (mesmo `TargetRef` do Policy Engine). */
export interface AlvoAvaliacao {
  readonly type: "evaluation" | "collaborator";
  readonly id: string;
}

export interface EntradaAvaliacao {
  readonly organization_id: string;
  readonly operacao: OperacaoAvaliacao;
  readonly alvo: AlvoAvaliacao;
  /** Notas do lote: `{ subcriterion_id, nota }[]` (1..5). */
  readonly notas?: readonly { readonly subcriterion_id: string; readonly nota: number }[];
  readonly participant_id?: string;
  readonly escopo?: "CRITERIO" | "FINAL";
  readonly criterion_id?: string | null;
  readonly texto?: string;
  readonly motivo?: string;
  /** Ciclo pretendido (intenção) na criação da avaliação. */
  readonly cycle_id?: string;
}

export type CodigoPublico =
  | "FORBIDDEN"
  | "NOT_FOUND"
  | "CONFLICT"
  | "INVALID_INPUT"
  | "INTERNAL"
  | "NOT_AUTHORIZED";

export interface RespostaAvaliacao {
  readonly ok: boolean;
  readonly code?: CodigoPublico;
  readonly message?: string;
  readonly resultado?: unknown;
}

/** Capacidade exigida por operação (contrato §8.3 — nenhuma capability nova). */
export const CAPABILITY_POR_OPERACAO: Readonly<Record<OperacaoAvaliacao, string>> = {
  "evaluation.criar": "evaluation.create",
  "evaluation.ler": "evaluation.read",
  "evaluation.gravar_notas": "evaluation.write",
  "evaluation.gravar_comentario": "evaluation.write",
  "evaluation.concluir": "evaluation.write",
  "evaluation.reabrir": "evaluation.reopen",
  "evaluation.cancelar": "evaluation.cancel",
  "evaluation.participantes_realinhar": "evaluation.write",
  "evaluation.transparencia": "evaluation.read",
};

/** Alvo autorizável de cada operação (criação usa o colaborador avaliado). */
export function tipoAlvoDaOperacao(operacao: OperacaoAvaliacao): AlvoAvaliacao["type"] {
  return operacao === "evaluation.criar" ? "collaborator" : "evaluation";
}

export const OPERACOES_AVALIACAO: readonly OperacaoAvaliacao[] = Object.keys(
  CAPABILITY_POR_OPERACAO
) as readonly OperacaoAvaliacao[];

export function ehOperacaoAvaliacao(valor: unknown): valor is OperacaoAvaliacao {
  return typeof valor === "string" && (OPERACOES_AVALIACAO as readonly string[]).includes(valor);
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function ehUuid(valor: unknown): valor is string {
  return typeof valor === "string" && UUID.test(valor.trim());
}

export type ResultadoValidacao =
  | { readonly ok: true; readonly entrada: EntradaAvaliacao }
  | { readonly ok: false; readonly code: CodigoPublico; readonly message: string };

/**
 * Valida a FORMA da intenção (nunca a autoridade): campos obrigatórios, UUIDs
 * bem formados e ausência de campos de identidade proibidos. Qualquer desvio é
 * `INVALID_INPUT` — fail-closed.
 */
export function validarEntradaAvaliacao(corpo: unknown): ResultadoValidacao {
  if (typeof corpo !== "object" || corpo === null || Array.isArray(corpo)) {
    return { ok: false, code: "INVALID_INPUT", message: "Corpo da requisição inválido." };
  }
  const cru = corpo as Record<string, unknown>;

  // Identidade nunca vem do cliente (D20/D27).
  for (const proibido of ["actor_id", "actor_user_profile_id", "user_profile_id", "ator"]) {
    if (cru[proibido] !== undefined) {
      return {
        ok: false,
        code: "INVALID_INPUT",
        message: "A identidade do ator não é aceita no corpo da requisição.",
      };
    }
  }

  if (!ehOperacaoAvaliacao(cru.operacao)) {
    return { ok: false, code: "INVALID_INPUT", message: "Operação de avaliação desconhecida." };
  }
  if (!ehUuid(cru.organization_id)) {
    return { ok: false, code: "INVALID_INPUT", message: "organization_id inválido." };
  }

  const alvoCru = cru.alvo;
  if (typeof alvoCru !== "object" || alvoCru === null || Array.isArray(alvoCru)) {
    return { ok: false, code: "INVALID_INPUT", message: "Alvo inválido." };
  }
  const alvo = alvoCru as Record<string, unknown>;
  const tipoEsperado = tipoAlvoDaOperacao(cru.operacao);
  if (alvo.type !== tipoEsperado || !ehUuid(alvo.id)) {
    return {
      ok: false,
      code: "INVALID_INPUT",
      message: `A operação ${cru.operacao} exige alvo do tipo ${tipoEsperado}.`,
    };
  }

  if (cru.cycle_id !== undefined && cru.cycle_id !== null && !ehUuid(cru.cycle_id)) {
    return { ok: false, code: "INVALID_INPUT", message: "cycle_id inválido." };
  }
  if (cru.participant_id !== undefined && cru.participant_id !== null && !ehUuid(cru.participant_id)) {
    return { ok: false, code: "INVALID_INPUT", message: "participant_id inválido." };
  }
  if (cru.criterion_id !== undefined && cru.criterion_id !== null && !ehUuid(cru.criterion_id)) {
    return { ok: false, code: "INVALID_INPUT", message: "criterion_id inválido." };
  }
  if (cru.escopo !== undefined && cru.escopo !== null && cru.escopo !== "CRITERIO" && cru.escopo !== "FINAL") {
    return { ok: false, code: "INVALID_INPUT", message: "escopo inválido." };
  }

  if (cru.notas !== undefined) {
    if (!Array.isArray(cru.notas)) {
      return { ok: false, code: "INVALID_INPUT", message: "notas deve ser uma lista." };
    }
    for (const item of cru.notas) {
      if (typeof item !== "object" || item === null) {
        return { ok: false, code: "INVALID_INPUT", message: "Item de nota inválido." };
      }
      const nota = item as Record<string, unknown>;
      if (!ehUuid(nota.subcriterion_id)) {
        return { ok: false, code: "INVALID_INPUT", message: "subcriterion_id inválido." };
      }
      const valor = nota.nota;
      if (typeof valor !== "number" || !Number.isInteger(valor) || valor < 1 || valor > 5) {
        return { ok: false, code: "INVALID_INPUT", message: "Nota deve ser inteiro de 1 a 5." };
      }
    }
  }

  return { ok: true, entrada: cru as unknown as EntradaAvaliacao };
}
