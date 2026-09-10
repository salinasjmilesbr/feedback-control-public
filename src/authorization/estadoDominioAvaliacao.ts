import type { Capability } from "./Capability.ts";
import type { DomainStateProbe } from "./policyEngine/types.ts";

/**
 * F5-06 (§8.1, D8, D18) — ESTADO DE DOMÍNIO do recurso AVALIAÇÃO.
 *
 * O Policy Engine consome `domainState` como condicionante soberana: a
 * autorização decide QUEM pode agir; o domínio decide se a AÇÃO é possível no
 * estado atual. Este módulo é a única declaração dessa condição para o recurso
 * `evaluation` — a Edge Function carrega a linha real e monta o probe; nenhum
 * predicado de autorização é duplicado aqui.
 *
 * Regras (espelham o workflow contratado, não a autorização):
 * - `CONCLUIDA` e `CANCELADA` são estados IMUTÁVEIS: nenhuma mutação normal é
 *   possível (reabertura/cancelamento seguem por operação própria, autorizada
 *   por capability específica);
 * - reabertura só é possível a partir de `CONCLUIDA` (D8);
 * - cancelamento só é possível quando ainda não cancelada;
 * - leitura e transparência não são bloqueadas por estado aqui (a janela de
 *   transparência é garantida server-side na projeção da RPC).
 */

/** Estados em que a avaliação não aceita mutação normal (D8). */
export const STATUS_AVALIACAO_IMUTAVEIS = ["CONCLUIDA", "CANCELADA"] as const;

export type StatusAvaliacao =
  | "RASCUNHO"
  | "PRONTA_PARA_FEEDBACK"
  | "CONCLUIDA"
  | "CANCELADA";

export interface EstadoAvaliacaoSoberano {
  readonly status: string;
  /** Marcador permanente de pendência (fechamento incompleto do ciclo). */
  readonly encerradaComPendencias?: boolean;
}

/** Capabilities que NÃO são bloqueadas pelo estado do domínio. */
const CAPABILITIES_DE_LEITURA: readonly Capability[] = [
  "evaluation.read",
  "evaluation.cancel",
  "evaluation.reopen",
];

function estadoNormalizado(entrada: EstadoAvaliacaoSoberano): string {
  return typeof entrada.status === "string" ? entrada.status.trim().toUpperCase() : "";
}

export function avaliacaoEditavel(entrada: EstadoAvaliacaoSoberano): boolean {
  const status = estadoNormalizado(entrada);
  return status !== "" && !(STATUS_AVALIACAO_IMUTAVEIS as readonly string[]).includes(status);
}

export function avaliacaoConcluida(entrada: EstadoAvaliacaoSoberano): boolean {
  return estadoNormalizado(entrada) === "CONCLUIDA";
}

export function avaliacaoCancelada(entrada: EstadoAvaliacaoSoberano): boolean {
  return estadoNormalizado(entrada) === "CANCELADA";
}

/**
 * Probe de domínio do recurso avaliação. Ausência de status ⇒ NÃO editável
 * (fail-closed): o recurso não foi carregado corretamente.
 */
export function estadoDominioAvaliacao(
  entrada: EstadoAvaliacaoSoberano
): DomainStateProbe {
  return {
    allows: (capability: Capability): boolean => {
      if (CAPABILITIES_DE_LEITURA.includes(capability)) return true;
      switch (capability) {
        case "evaluation.create":
        case "evaluation.write":
          return avaliacaoEditavel(entrada);
        default:
          return false;
      }
    },
  };
}

/**
 * Probe de domínio da CRIAÇÃO (`evaluation.create` sobre o colaborador
 * avaliado): o ciclo precisa aceitar novas avaliações e o avaliado precisa
 * estar apto. Nenhum dado vem do cliente — a Edge Function resolve ambos.
 */
export function estadoDominioCriacaoAvaliacao(entrada: {
  readonly cicloPermiteNovaAvaliacao: boolean;
  readonly avaliadoApto: boolean;
}): DomainStateProbe {
  return {
    allows: (capability: Capability): boolean => {
      if (capability === "evaluation.read") return true;
      if (capability === "evaluation.write" || capability === "evaluation.create") {
        return entrada.cicloPermiteNovaAvaliacao && entrada.avaliadoApto;
      }
      return false;
    },
  };
}
