import type { Capability } from "./Capability.ts";
import type { DomainStateProbe } from "./policyEngine/types.ts";

/**
 * F5-10 P4 (§10, D6–D9, D14/D25) — ESTADO DE DOMÍNIO do recurso META.
 *
 * O Policy Engine decide **QUEM** pode agir (identidade, membership, capability
 * efetiva, escopo e relação); este módulo declara **SE** a ação é possível no
 * estado atual da meta. É a ÚNICA declaração dessa condição para o recurso
 * `goal`: a fronteira soberana (`contextoAutorizacao.ts`) deriva o probe desta
 * matriz, a partir da **LINHA SOBERANA** (`evaluation_goals.status`,
 * `excluida` e o status do ciclo da meta) — nunca do `domainState` declarado
 * pelo cliente. A matriz não é duplicada em nenhum outro caminho.
 *
 * Matriz contratada (§10 do desenho técnico; fonte única):
 *
 * | capability     | estados que PERMITEM                                                  |
 * | `goal.read`    | meta real carregada (qualquer status conhecido), INCLUSIVE excluída    |
 * | `goal.write`   | `EM_ANDAMENTO`, `ATINGIDA`, `NAO_ATINGIDA` — criar/editar/progredir/    |
 * |                | finalizar/excluir e a **revisão de fechamento**; nunca excluída e       |
 * |                | SEMPRE com o ciclo em `ATIVO`                                           |
 * | `goal.approve` | `EM_ANDAMENTO`, `ATINGIDA`, `NAO_ATINGIDA` — nunca excluída e SEMPRE    |
 * |                | com o ciclo em `ATIVO`                                                  |
 *
 * Regras complementares (todas fail-closed):
 * - `excluida = true` ⇒ SOMENTE `goal.read` (leitura histórica; §10);
 * - ciclo fora de `ATIVO` ⇒ nega `goal.write` e `goal.approve` (§10: só ciclo
 *   `ATIVO` permite mutação; o status é lido da LINHA soberana do ciclo);
 * - status ausente ou fora do domínio fechado ⇒ nega TUDO (fail-closed): uma
 *   linha sem status real não é um recurso carregado de fonte soberana;
 * - `default: false` — capability fora da matriz nunca é liberada.
 *
 * `goal.approve` **não** implica `goal.write` (D7/D9): são ações distintas e o
 * probe é consultado por capability; o alcance de cada uma é decidido nos
 * providers reais (escrita = SELF do dono; aprovação = aprovador congelado).
 */

/** Status do domínio fechado de meta (CHECK da F5-10 P1). */
export const STATUS_META_CONHECIDOS = [
  "EM_ANDAMENTO",
  "ATINGIDA",
  "NAO_ATINGIDA",
] as const;

export type StatusMeta = (typeof STATUS_META_CONHECIDOS)[number];

/** Projeção mínima consumida pelo probe: estado REAL da linha da meta. */
export interface EstadoMetaSoberano {
  readonly status: string;
  /** Soft delete (`evaluation_goals.excluida`) — leitura histórica apenas. */
  readonly excluida?: boolean;
  /** Status REAL da linha do ciclo da meta (mutação exige `ATIVO`). */
  readonly cicloStatus?: string;
}

/** Normaliza o status (trim + maiúsculas) ou `null` quando fora do domínio. */
export function statusMetaConhecido(valor: unknown): StatusMeta | null {
  if (typeof valor !== "string") return null;
  const normalizado = valor.trim().toUpperCase();
  return (STATUS_META_CONHECIDOS as readonly string[]).includes(normalizado)
    ? (normalizado as StatusMeta)
    : null;
}

/** Ciclo REAL da meta em `ATIVO` — condição temporal de mutação (§10). */
function cicloAtivo(valor: unknown): boolean {
  return typeof valor === "string" && valor.trim().toUpperCase() === "ATIVO";
}

/** Meta REAL carregada: status dentro do domínio fechado (qualquer um deles). */
export function metaExistente(entrada: EstadoMetaSoberano): boolean {
  return statusMetaConhecido(entrada?.status) !== null;
}

/**
 * Meta VIVA em ciclo `ATIVO` — condição de MUTAÇÃO (`goal.write`/`goal.approve`).
 * Excluída, status desconhecido/ausente ou ciclo fora de `ATIVO` ⇒ `false`.
 */
export function metaEditavel(entrada: EstadoMetaSoberano): boolean {
  return (
    metaExistente(entrada) &&
    entrada?.excluida !== true &&
    cicloAtivo(entrada?.cicloStatus)
  );
}

/**
 * Probe de domínio do recurso META. Capability desconhecida ⇒ NEGADO: o probe
 * nunca libera uma ação que não esteja na matriz.
 */
export function estadoDominioMeta(entrada: EstadoMetaSoberano): DomainStateProbe {
  const estado: EstadoMetaSoberano = {
    status: entrada?.status ?? "",
    excluida: entrada?.excluida === true,
    cicloStatus: entrada?.cicloStatus ?? "",
  };

  return {
    allows: (capability: Capability): boolean => {
      // Linha sem status real (ou fora do domínio) não autoriza NADA.
      if (!metaExistente(estado)) return false;
      // Leitura histórica: permanece possível inclusive para meta excluída.
      if (capability === "goal.read") return true;
      // Excluída ⇒ somente leitura (§10); mutação exige ciclo `ATIVO`.
      if (capability === "goal.write" || capability === "goal.approve") {
        return metaEditavel(estado);
      }
      return false;
    },
  };
}
