import type { Capability } from "./Capability.ts";
import type { DomainStateProbe } from "./policyEngine/types.ts";

/**
 * F5-06 (§8.1, D8, D18) + F6 Incremento 1 (R2/R3) — ESTADO DE DOMÍNIO do
 * recurso AVALIAÇÃO.
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
 * - **LEITURA (Incremento 1, R2/R3)**: `evaluation.read` NÃO é mais livre por
 *   estado. Concede quando o ator é PARTICIPANTE materializado vigente (R2: lê
 *   em RASCUNHO, PRONTA_PARA_FEEDBACK e CONCLUIDA) ou quando o ator é o próprio
 *   AVALIADO e a avaliação está `CONCLUIDA` (R3: janela pós-conclusão).
 *   Qualquer outro leitor — administrativo/excepcional sem ocorrência vigente,
 *   ex-participante, cross-tenant — NEGA. Antes de CONCLUIDA o avaliado não
 *   recebe resultado, status nem conteúdo por nenhuma rota `evaluation.read`.
 * - **LEITURA COLETIVA (Incremento 1, R2)**: probe PRÓPRIO que admite os três
 *   estados para os entitlements de participante; a concessão aqui comprova
 *   elegibilidade de LEITURA e não libera escrita alguma (o probe de mutação
 *   acima permanece o gate de `evaluation.write`).
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
  /**
   * R2: o ator possui ocorrência materializada e VIGENTE nesta avaliação,
   * resolvida server-side (nunca declarada pelo cliente). Ausente ⇒ `false`
   * (fail-closed): sem participação comprovada não há leitura participante.
   */
  readonly atorEhParticipanteVigente?: boolean;
  /**
   * R3: o ator É o colaborador avaliado (SELF), derivado do vínculo soberano
   * contra a linha real da avaliação. Ausente ⇒ `false` (fail-closed).
   */
  readonly atorEhAvaliado?: boolean;
}

/** Capabilities de operação EXCEPCIONAL: pré-condições próprias na RPC. */
const CAPABILITIES_EXCEPCIONAIS: readonly Capability[] = [
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
 * R2/R3 — quem pode LER o recurso avaliação neste estado.
 *
 * - participante materializado vigente ⇒ sim, em qualquer estado (inclusive
 *   CONCLUIDA — leitura coletiva permitida, mutação NÃO);
 * - avaliado (SELF) ⇒ somente com `CONCLUIDA` (janela pós-conclusão da R3);
 * - os demais ⇒ NÃO (leitor administrativo/excepcional sem ocorrência,
 *   ex-participante e cross-tenant falham fechado).
 */
export function avaliacaoLegivel(entrada: EstadoAvaliacaoSoberano): boolean {
  const status = estadoNormalizado(entrada);
  // R2: somente RASCUNHO, PRONTA_PARA_FEEDBACK e CONCLUIDA são legíveis.
  // CANCELADA não é legível para ninguém (nem para participante).
  if (status !== "RASCUNHO" && status !== "PRONTA_PARA_FEEDBACK" && status !== "CONCLUIDA") {
    return false;
  }
  if (entrada.atorEhParticipanteVigente === true) return true;
  return entrada.atorEhAvaliado === true && status === "CONCLUIDA";
}

/**
 * Probe de domínio do recurso avaliação. Ausência de status ⇒ NÃO editável e
 * NÃO legível (fail-closed): o recurso não foi carregado corretamente.
 */
export function estadoDominioAvaliacao(
  entrada: EstadoAvaliacaoSoberano
): DomainStateProbe {
  return {
    allows: (capability: Capability): boolean => {
      if (capability === "evaluation.read") return avaliacaoLegivel(entrada);
      if (CAPABILITIES_EXCEPCIONAIS.includes(capability)) return true;
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
 * R2 — probe de domínio PRÓPRIO da LEITURA COLETIVA dos participantes.
 *
 * Admite `RASCUNHO`, `PRONTA_PARA_FEEDBACK` e `CONCLUIDA` para os entitlements
 * de participante (o gate de mutação continua sendo `estadoDominioAvaliacao`,
 * que nega `evaluation.write` em CONCLUIDA). `CANCELADA` não é legível e a
 * ausência de status falha fechado.
 *
 * O probe NÃO decide quem é participante: isso é resolvido antes (ocorrência
 * materializada vigente + relação/scope no Policy Engine).
 */
export function estadoDominioLeituraColetivaAvaliacao(
  entrada: EstadoAvaliacaoSoberano
): DomainStateProbe {
  const status = estadoNormalizado(entrada);
  const legivel =
    status === "RASCUNHO" || status === "PRONTA_PARA_FEEDBACK" || status === "CONCLUIDA";
  return {
    allows: (capability: Capability): boolean => {
      if (!legivel) return false;
      // L1 (auditoria): `evaluation.create` NÃO é entitlement da leitura coletiva
      // (R2 admite `evaluation.write` ou `evaluation.read + ASSIGNED`). O probe
      // reflete apenas os entitlements válidos desta operação de LEITURA.
      return capability === "evaluation.read" || capability === "evaluation.write";
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
