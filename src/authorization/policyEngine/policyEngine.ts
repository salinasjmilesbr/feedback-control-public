import { codigoPublicoDeNegacao, erroDeNegacao } from "./errors";
import type {
  AuthorizationDecision,
  AuthorizationRequest,
  DenialReason,
  PolicyEngineProviders,
  ScopeType,
  TargetRef,
} from "./types";

/**
 * Policy engine da F4-03 (Issue #90) — fonte única de decisão na application
 * layer (D1/D2). TipoScript, estruturado por providers (interfaces) para que a
 * origem dos dados migre para Supabase/server-side sem reescrever a semântica.
 *
 * Pipeline determinística (D/§7), fail-closed (qualquer indeterminação = DENY):
 *   1 identidade → 2 profile → 3 membership → 4 tenant → 5 capability →
 *   6 scope → 7 relação (alvo ∈ scope) → 8 contexto temporal → 9 estado do
 *   domínio → 10 ALLOW.
 */

function negar(
  reason: DenialReason,
  matchedScope?: ScopeType
): AuthorizationDecision {
  return {
    allowed: false,
    denial: { reason, publicCode: codigoPublicoDeNegacao(reason) },
    ...(matchedScope ? { diagnostics: { matchedScope } } : {}),
  };
}

export function decidir(
  request: AuthorizationRequest,
  providers: PolicyEngineProviders
): AuthorizationDecision {
  const { actor, capability, target, context } = request;

  // 1) identidade
  if (!actor.actorId) return negar("NO_IDENTITY");

  // 2) profile ativo
  if (!providers.identity.isProfileActive(actor.actorId)) {
    return negar("PROFILE_DISABLED");
  }

  // 3) membership ativa
  if (!providers.identity.isMembershipActive(actor.actorId, actor.organizationId)) {
    return negar("MEMBERSHIP_INVALID");
  }

  // 4) tenant do alvo (derivado do recurso, nunca do request)
  const targetTenant = providers.targets.resolveTargetTenant(target);
  if (targetTenant === undefined) return negar("TARGET_INVALID");
  if (targetTenant !== actor.organizationId) return negar("CROSS_TENANT");

  // 5) capability efetiva
  if (!providers.capabilities.hasCapability(actor.actorId, actor.organizationId, capability)) {
    return negar("CAPABILITY_MISSING");
  }

  // 6) scope efetivo (pelo menos um ativo)
  const scopes = providers.scopes.getActiveScopes(actor.actorId, actor.organizationId);
  if (scopes.length === 0) return negar("SCOPE_INSUFFICIENT");

  // 7) relação: alvo pertence a AO MENOS um scope do ator, na data
  let matchedScope: ScopeType | undefined;
  for (const scope of scopes) {
    if (providers.relations.isTargetInScope(actor.actorId, actor.organizationId, scope, target, context.date)) {
      matchedScope = scope;
      break;
    }
  }
  if (!matchedScope) return negar("SCOPE_INSUFFICIENT");

  // 8) contexto temporal explícito
  if (!context.date) return negar("INDETERMINATE");

  // 9) estado do domínio (probe soberano; ausente = indeterminação = DENY)
  if (!request.domainState) return negar("INDETERMINATE");
  if (!request.domainState.allows(capability)) {
    return negar("DOMAIN_STATE_INVALID");
  }

  // 10) ALLOW
  return { allowed: true, diagnostics: { matchedScope } };
}

/** Auxiliar de UX/predicação: nunca enforcement (invariante 1). */
export function can(
  request: AuthorizationRequest,
  providers: PolicyEngineProviders
): AuthorizationDecision {
  return decidir(request, providers);
}

/**
 * Protege mutações: lança erro público F0-05 quando a decisão é DENY (D5/D9).
 * Deve ser chamado na camada de serviço, imediatamente antes da mutação.
 */
export function authorize(
  request: AuthorizationRequest,
  providers: PolicyEngineProviders
): void {
  const decision = decidir(request, providers);
  if (!decision.allowed) {
    throw erroDeNegacao(decision.denial!.reason);
  }
}

/**
 * Serviço AUXILIAR de listagem/resolução de alvos (D5 = A ajustada).
 * NÃO é fonte de decisão: uma mutação nunca considera "estar na lista" como
 * substituto de authorize().
 */
export function listAllowedTargets(
  request: Omit<AuthorizationRequest, "target">,
  providers: PolicyEngineProviders,
  candidateTargets: readonly TargetRef[]
): TargetRef[] {
  return candidateTargets.filter((target) =>
    decidir({ ...request, target }, providers).allowed
  );
}
