import type { Capability } from "../Capability.ts";
import type { ApplicationErrorCode } from "../../errors/applicationErrors.ts";

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

/**
 * Tipo de responsabilidade temporária (F3-06). É dado de domínio — a tradução
 * para capabilities é feita pela allowlist FECHADA da F4-05 (D3), nunca aqui.
 */
export type ResponsibilityType =
  | "operational"
  | "evaluative"
  | "operational_evaluative";

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
  | "TARGET_INCOMPATIBLE"
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
    /** Origens temporárias válidas (união deduplicada), ex.: "temporary:<id>". */
    temporaryOrigins?: string[];
    /** Grant excepcional que autorizou a decisão (F4-06), ex.: exceptional:<grantId>. */
    exceptionalGrant?: { id: string; origin: string };
    /** Grant de Pilot Full Access que autorizou a decisão (F4-07), ex.: pilot:<grantId>. */
    pilotGrant?: { id: string; origin: string };
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
  /** O alvo pertence ao scope do ator, na data/contexto? */
  isTargetInScope(
    actorId: string,
    organizationId: string,
    scope: ScopeType,
    target: TargetRef,
    date: Date,
    cycleId?: string
  ): boolean;
}

/**
 * Grant temporário (F4-05) derivado de uma temporary_responsibility vigente.
 * Origem preservada no diagnóstico para auditoria (D10); raiz = position
 * substituída (D4/D5). NUNCA é informado/forçado pelo caller.
 */
export interface TemporaryGrant {
  origin: string;
  responsibilityId: string;
  responsibilityType: ResponsibilityType;
  capability: Capability;
  scope: ScopeType;
  substitutedPositionId: string;
}

/**
 * Origem temporária independente da origem membership (D2/D12): o engine
 * considera a UNIÃO DEDUPLICADA das duas origens, preservando a origem de cada
 * grant. Falha fechado para tipo desconhecido, tenant divergente, data fora da
 * vigência ou dados insuficientes (D1/D3/D9/D15).
 */
export interface TemporaryProvider {
  /** Capabilities elegíveis (união deduplicada) das responsabilidades vigentes do ator na data. */
  getEligibleCapabilities(
    actorId: string,
    organizationId: string,
    date: Date
  ): Capability[];
  /** Grants temporários cujo alcance (raiz = position substituída) cobre o alvo. */
  resolveTemporaryGrants(
    actorId: string,
    organizationId: string,
    capability: Capability,
    target: TargetRef,
    date: Date,
    cycleId?: string
  ): TemporaryGrant[];
}

/**
 * Grant excepcional (F4-06, contrato fechado D1–D20). 1 grant = 1 beneficiário
 * + 1 capability + 1 target específico + 1 tenant + cycleId quando aplicável +
 * 1 janela temporal fechada. Somente leitura no piloto; auto-concessão
 * proibida; sem wildcard; nunca é informado/forçado pelo caller.
 */
export interface ExceptionalGrant {
  id: string;
  organizationId: string;
  /** Identidade soberana do beneficiário (user_profile/membership; sem exigir collaborator). */
  beneficiaryUserProfileId: string;
  grantedByUserProfileId: string;
  capability: Capability;
  target: TargetRef;
  /** Obrigatório quando o tipo de recurso é associado a ciclo (avaliação). */
  cycleId?: string;
  justification: string;
  validFrom: Date;
  validTo: Date;
  status: "active" | "revoked";
  revokedAt?: Date;
  revokedBy?: string;
  revocationMotive?: string;
}

/** Registro de uso efetivo da origem C (D12/Q3): somente quando C autoriza. */
export interface ExceptionalUsageRecord {
  grantId: string;
  organizationId: string;
  beneficiaryUserProfileId: string;
  capability: Capability;
  target: TargetRef;
  cycleId?: string;
  date: Date;
  origin: string;
}

/**
 * Origem C — acesso excepcional (F4-06, D6/D7/D8/D16). Independente de A
 * (membership) e B (temporary). É consultada SOMENTE quando A/B DENY; a
 * classificação de confidencialidade é soberana (domínio/probe), nunca do
 * caller; mais de um grant aplicável sem identificação inequívoca ⇒ DENY.
 */
export interface ExceptionalProvider {
  /** Capability pertence à allowlist fechada de exceção (D8)? */
  isCapabilityExceptionalEligible(capability: Capability): boolean;
  /**
   * Classificação soberana do recurso: true = confidencial elegível;
   * false = não confidencial; undefined = indeterminado/ausente (fail-closed).
   */
  isTargetConfidential(
    target: TargetRef,
    cycleId: string | undefined,
    organizationId: string
  ): boolean | undefined;
  /** Grants excepcionais aplicáveis (beneficiário/tenant/capability/target/ciclo/data/status). */
  resolveExceptionalGrants(
    beneficiaryId: string,
    organizationId: string,
    capability: Capability,
    target: TargetRef,
    date: Date,
    cycleId?: string
  ): ExceptionalGrant[];
  /** Evento de uso efetivo — invocado pelo engine quando C autoriza. */
  recordUsage?(record: ExceptionalUsageRecord): void;
}

/**
 * Grant de Pilot Full Access (F4-07, contrato fechado D1–D18). Tenant-scoped,
 * development-only, perfil versionado fechado (PILOT_PROFILE_V1), máx. 30 dias,
 * sem confidencial/segurança. Nunca é informado/forçado pelo caller.
 */
export interface PilotFullAccessGrant {
  id: string;
  organizationId: string;
  beneficiaryUserProfileId: string;
  grantedByUserProfileId: string;
  justification: string;
  validFrom: Date;
  validTo: Date;
  status: "active" | "revoked";
  revokedAt?: Date;
  revokedBy?: string;
  revocationMotive?: string;
  /** Perfil versionado fechado de capabilities pilot-eligible (ex.: "PILOT_PROFILE_V1"). */
  profileVersion: string;
  createdAt?: Date;
  version?: number;
}

/** Registro de uso efetivo da origem D (D14): somente quando D autoriza. */
export interface PilotUsageRecord {
  grantId: string;
  organizationId: string;
  beneficiaryUserProfileId: string;
  capability: Capability;
  target: TargetRef;
  cycleId?: string;
  date: Date;
  profileVersion: string;
  origin: string;
}

/**
 * Origem D — Pilot Full Access (F4-07, D6/D7/D13). Exclusiva de development;
 * consultada SOMENTE quando A/B DENY e o alvo NÃO é confidencial; perfil
 * versionado fechado; mais de um grant aplicável sem identificação inequívoca
 * ⇒ DENY. Nunca cobre conteúdo confidencial nem capabilities de segurança.
 */
export interface PilotFullAccessProvider {
  /** Ambiente elegível? D só produz ALLOW em "development" (D13). */
  isEnvironmentEligible(): boolean;
  /** Capability pertence a algum perfil versionado suportado (PILOT_PROFILE_V1)? */
  isCapabilityPilotEligible(capability: Capability): boolean;
  /**
   * Classificação soberana do recurso (mesma fonte da F4-06): true =
   * confidencial; false = não confidencial; undefined = indeterminado.
   */
  isTargetConfidential(
    target: TargetRef,
    cycleId: string | undefined,
    organizationId: string
  ): boolean | undefined;
  /** Grants de Pilot Full Access aplicáveis (beneficiário/tenant/capability/data/status/perfil). */
  resolvePilotFullAccessGrants(
    beneficiaryId: string,
    organizationId: string,
    capability: Capability,
    date: Date
  ): PilotFullAccessGrant[];
  /** Evento de uso efetivo — invocado pelo engine quando D autoriza. */
  recordUsage?(record: PilotUsageRecord): void;
}

export interface PolicyEngineProviders {
  identity: IdentityProvider;
  capabilities: CapabilityProvider;
  scopes: ScopeProvider;
  targets: TargetProvider;
  relations: RelationProvider;
  /** Origem temporária (F4-05); ausente = sem grants temporários (retrocompatível). */
  temporary?: TemporaryProvider;
  /** Origem excepcional (F4-06); ausente = sem acesso excepcional (retrocompatível). */
  exceptional?: ExceptionalProvider;
  /** Origem Pilot Full Access (F4-07); ausente = sem pilot (retrocompatível). */
  pilot?: PilotFullAccessProvider;
}
