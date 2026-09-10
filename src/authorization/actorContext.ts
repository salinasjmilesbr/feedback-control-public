import type { AuthIdentity, MembershipAutenticada } from "../auth/tipos.ts";
import type { ActorRef } from "./policyEngine/types.ts";

/**
 * F5-05 (D1–D5, D14, D15, D19, D20) — ActorContext real.
 *
 * O `ActorContext` de ENFORCEMENT agrega a identidade soberana (F5-01), a
 * organização ativa validada (F5-03), a membership ativa e o vínculo de
 * colaborador (F5-02) e produz o `ActorRef` do Policy Engine (F4-03).
 *
 * Fronteira confiável (D20): este contexto é montado **por operação** em
 * Edge Function / RPC / backend confiável equivalente. Browser, React, hooks,
 * `localStorage`, client SDK e `src/services` executados no browser são
 * CLIENTE NÃO CONFIÁVEL: nenhum deles pode montar/fornecer este contexto como
 * prova de autorização.
 *
 * Marco de soberania: o contexto é marcado com um símbolo PRIVADO do módulo
 * (`MARCA_ATOR_SOBERANO`), criado apenas por `montarActorContext`. Um objeto
 * literal vindo do browser — ainda que estruturalmente idêntico — NÃO passa em
 * `ehActorContextSoberano` e é recusado pelo enforcement.
 */

const MARCA_ATOR_SOBERANO: unique symbol = Symbol("virtus.f5-05.actorContext.soberano");

export interface ActorContext {
  /** Marca privada de soberania — ver `ehActorContextSoberano`. */
  readonly [MARCA_ATOR_SOBERANO]: true;
  /** Snapshot de identidade (F5-01): authUserId, perfil ativo, memberships ativas. */
  readonly identity: AuthIdentity;
  /** Organização em uso — intenção (F5-03) VALIDADA contra membership ativa. */
  readonly organizationId: string;
  /** Membership ativa que ancora a organização em uso. */
  readonly membership: MembershipAutenticada;
  /** Vínculo (F5-02) — opcional; `null` = sem colaborador (ex.: ADMIN). */
  readonly collaboratorId: string | null;
  /** Contrato do engine: `{ actorId: identity.authUserId, organizationId }`. */
  toActorRef(): ActorRef;
}

/**
 * Projeção NÃO soberana para UX (D20): pode existir/transitar no browser para
 * habilitar/ocultar elementos e chamar a fachada de `can()`. NUNCA é aceita por
 * `authorize()`/`podeOperacao()` como prova de autorização.
 */
export interface ProjecaoUxAtor {
  readonly actorId: string;
  readonly organizationId: string;
}

export type MotivoAtorInvalido =
  | "SEM_IDENTIDADE"
  | "PERFIL_INATIVO"
  | "ORGANIZACAO_AUSENTE"
  | "ORGANIZACAO_NAO_DISPONIVEL"
  | "MEMBERSHIP_AUSENTE";

export type ResultadoMontagemAtor =
  | { readonly ok: true; readonly actorContext: ActorContext }
  | { readonly ok: false; readonly motivo: MotivoAtorInvalido };

export interface EntradaMontagemAtor {
  /** Snapshot soberano de identidade (F5-01). Nunca um objeto do cliente. */
  readonly identity: AuthIdentity | null | undefined;
  /** Organização em uso (intenção validada contra membership ativa). */
  readonly organizationId: string | null | undefined;
  /** Vínculo F5-02 (resolvido server-side); `null` quando não há. */
  readonly collaboratorId: string | null | undefined;
}

function normalizarIdOpcional(valor: string | null | undefined): string | null {
  if (typeof valor !== "string") return null;
  const limpo = valor.trim();
  return limpo.length > 0 ? limpo : null;
}

/**
 * Monta o `ActorContext` a partir de dados SOBERANOS já resolvidos
 * server-side. Fail-closed: qualquer elo ausente/inválido ⇒ resultado `ok:false`
 * (o chamador NÃO decide; apenas devolve DENY).
 */
export function montarActorContext(entrada: EntradaMontagemAtor): ResultadoMontagemAtor {
  const identity = entrada.identity ?? null;
  if (!identity || !identity.authUserId) {
    return { ok: false, motivo: "SEM_IDENTIDADE" };
  }
  // Invariante F5-01: authUserId === user_profile.id.
  if (!identity.perfil || identity.perfil.id !== identity.authUserId) {
    return { ok: false, motivo: "SEM_IDENTIDADE" };
  }
  if (identity.perfil.status !== "active") {
    return { ok: false, motivo: "PERFIL_INATIVO" };
  }

  const organizationId = normalizarIdOpcional(entrada.organizationId);
  if (!organizationId) {
    return { ok: false, motivo: "ORGANIZACAO_AUSENTE" };
  }

  const organizacaoDisponivel = identity.organizacoes.some(
    (organizacao) => organizacao.id === organizationId
  );
  if (!organizacaoDisponivel) {
    return { ok: false, motivo: "ORGANIZACAO_NAO_DISPONIVEL" };
  }

  const membership = identity.memberships.find(
    (item) => item.organizationId === organizationId && item.status === "active"
  );
  if (!membership) {
    return { ok: false, motivo: "MEMBERSHIP_AUSENTE" };
  }

  const actorContext: ActorContext = {
    [MARCA_ATOR_SOBERANO]: true,
    identity,
    organizationId,
    membership,
    collaboratorId: normalizarIdOpcional(entrada.collaboratorId),
    toActorRef(): ActorRef {
      return { actorId: identity.authUserId, organizationId };
    },
  };

  return { ok: true, actorContext };
}

/**
 * Guarda de runtime da marca de soberania (D20). Um contexto forjado no browser
 * (objeto literal, cópia, JSON.parse) NÃO é reconhecido.
 */
export function ehActorContextSoberano(valor: unknown): valor is ActorContext {
  if (typeof valor !== "object" || valor === null) return false;
  return (valor as Record<PropertyKey, unknown>)[MARCA_ATOR_SOBERANO] === true;
}

/**
 * Projeta o contexto soberano para uso em UX (D20). A projeção é um dado
 * derivado, sem marca de soberania: serve apenas para a camada de apresentação.
 */
export function projetarParaUx(actorContext: ActorContext): ProjecaoUxAtor {
  return {
    actorId: actorContext.identity.authUserId,
    organizationId: actorContext.organizationId,
  };
}
