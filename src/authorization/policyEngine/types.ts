import type { Capability } from "../Capability";
import type { ApplicationErrorCode } from "../../errors/applicationErrors";

/**
 * Tipos e contratos do policy engine da F4-03 (Issue #90).
 *
 * Contrato aprovado em docs/F4-03-desenho-tecnico.md (D1–D18 fechadas):
 *   capability = ação; scope = alcance; relação = alvo ∈ scope;
 *   estado do domínio = condicionante soberana (probe); fail-closed.
 */

export type ScopeType =
  | "SELF"
  | "DIRECT_REPORTS"
  | "DESCENDANTS"
  | "ORGANIZATIONAL_UNIT"
  | "ORGANIZATION"
  | "ASSIGNED";

/** Alvo tipado, sem strings livres nem polimorfismo inseguro (D4). */
export type TargetRef =
  | { type: "collaborator"; id: string }
  | { type: "position"; id: string }
  | { type: "organizational_unit"; id: string }
  | { type: "cycle"; id: string }
  | { type: "evaluation"; id: string }
  | { type: "goal"; id: string }
  | { type: "observation"; id: string };

/** Razões internas de negação — nunca expostas ao frontend (D6). */
export type DenialReason =
  | "NO_IDENTITY"
  | "PROFILE_DISABLED"
  | "MEMBERSHIP_INVALID"
  | "CROSS_TENANT"
  | "TARGET_INVALID"
  | "CAPABILITY_MISSING"
  | "SCOPE_INSUFFICIENT"
  | "DOMAIN_STATE_INVALID"
  | "INDETERMINATE";

export interface ActorRef {
  /** Identidade do ator resolvida pela sessão/serviço (nunca pela UI). */
  actorId: string;
  organizationId: string;
}

export interface AuthorizationRequest {
  actor: ActorRef;
  /** Ação pretendida (pedida pelo chamador; a posse é resolvida por providers). */
  capability: Capability;
  target: TargetRef;
  context: {
    /** Data de contexto explícita (D13 F4-03 / D16 F4-02). */
    date: Date;
    cycleId?: string;
  };
  /**
   * Predicado de estado do domínio (D3): o domínio declara, o engine consome.
   * Ausente = indeterminação = DENY (fail-closed).
   */
  domainState?: DomainStateProbe;
}

export interface DomainStateProbe {
  allows(capability: Capability): boolean;
}

export interface AuthorizationDecision {
  allowed: boolean;
  denial?: {
    reason: DenialReason;
    /** Código público F0-05 (o que pode chegar ao frontend). */
    publicCode: ApplicationErrorCode;
  };
  diagnostics?: {
    matchedScope?: ScopeType;
  };
}

/** Contratos dos providers — o engine resolve tudo por aqui (D5/D16). */
export interface IdentityProvider {
  isProfileActive(actorId: string): boolean;
  isMembershipActive(actorId: string, organizationId: string): boolean;
}

export interface CapabilityProvider {
  hasCapability(actorId: string, organizationId: string, capability: Capability): boolean;
}

export interface ScopeProvider {
  getActiveScopes(actorId: string, organizationId: string): ScopeType[];
}

export interface TargetProvider {
  /** Tenant do alvo derivado do recurso carregado; undefined = não existe/inacessível. */
  resolveTargetTenant(target: TargetRef): string | undefined;
}

export interface RelationProvider {
  /** O alvo pertence ao scope do ator, na data? */
  isTargetInScope(
    actorId: string,
    organizationId: string,
    scope: ScopeType,
    target: TargetRef,
    date: Date
  ): boolean;
}

export interface PolicyEngineProviders {
  identity: IdentityProvider;
  capabilities: CapabilityProvider;
  scopes: ScopeProvider;
  targets: TargetProvider;
  relations: RelationProvider;
}
