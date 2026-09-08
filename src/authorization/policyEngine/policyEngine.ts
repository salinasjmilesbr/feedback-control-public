import { codigoPublicoDeNegacao, erroDeNegacao } from "./errors";
import { isCapabilityTargetCompatible } from "./capabilityTarget";
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
 *   1 identidade → 2 profile → 3 membership → 4 tenant → 5 capability
 *   (membership ⊕ temporária elegível) → 5.1 capability×target → 6/7 scope e
 *   relação (membership ⊕ temporária, união deduplicada com origem preservada) →
 *   8 contexto temporal → 9 estado do domínio → 10 ALLOW.
 *
 * F4-06 (Issue #93) adiciona a ORIGEM C — acesso excepcional — como fallback
 * pontual: C é consultada SOMENTE quando A/B DENY, a capability está na
 * allowlist fechada de exceção e o alvo é soberanamente classificado como
 * confidencial. C nunca é avaliada antes de A/B, nunca substitui a avaliação
 * normal e não participa de listAllowedTargets (D6/D7/D8/D16/D18).
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

  // 5) capability efetiva: membership OU origem temporária elegível (união D12)
  const hasMembershipCapability = providers.capabilities.hasCapability(
    actor.actorId,
    actor.organizationId,
    capability
  );
  const eligibleTemporarily = providers.temporary
    ? providers.temporary
        .getEligibleCapabilities(actor.actorId, actor.organizationId, context.date)
        .includes(capability)
    : false;

  if (!hasMembershipCapability && !eligibleTemporarily) {
    // A/B negam por capability: a origem C (F4-06) só pode elevar pontualmente.
    if (providers.exceptional) {
      return autorizarOrigemExcepcional(request, providers, "CAPABILITY_MISSING");
    }
    return negar("CAPABILITY_MISSING");
  }

  // 5.1) contrato capability × tipo de alvo (D18 F4-04): compartilhado pelas
  // duas origens — só rejeita combinações semanticamente impossíveis.
  if (!isCapabilityTargetCompatible(capability, target)) {
    return negar("TARGET_INCOMPATIBLE");
  }

  // 6) scope membership (pelo menos um ativo com alvo no alcance)
  let matchedScope: ScopeType | undefined;
  const scopes = providers.scopes.getActiveScopes(actor.actorId, actor.organizationId);
  if (scopes.length > 0) {
    for (const scope of scopes) {
      if (providers.relations.isTargetInScope(actor.actorId, actor.organizationId, scope, target, context.date, context.cycleId)) {
        matchedScope = scope;
        break;
      }
    }
  }

  // 6.1) origem temporária: grants cujo alcance (raiz = position substituída)
  // cobre o alvo; origem preservada por grant (D10).
  const temporaryGrants = providers.temporary
    ? providers.temporary.resolveTemporaryGrants(
        actor.actorId,
        actor.organizationId,
        capability,
        target,
        context.date,
        context.cycleId
      )
    : [];
  const temporaryOrigins = Array.from(
    new Set(temporaryGrants.map((g) => g.origin))
  );

  if (!matchedScope && temporaryGrants.length === 0) {
    // A/B negam por scope/relação: a origem C só pode elevar pontualmente.
    if (providers.exceptional) {
      return autorizarOrigemExcepcional(request, providers, "SCOPE_INSUFFICIENT");
    }
    return negar("SCOPE_INSUFFICIENT");
  }

  // 8) contexto temporal explícito
  if (!context.date) return negar("INDETERMINATE");

  // 9) estado do domínio (probe soberano; ausente = indeterminação = DENY)
  if (!request.domainState) return negar("INDETERMINATE");
  if (!request.domainState.allows(capability)) {
    return negar("DOMAIN_STATE_INVALID");
  }

  // 10) ALLOW — união deduplicada das origens válidas, preservando cada origem.
  return {
    allowed: true,
    diagnostics: {
      ...(matchedScope ? { matchedScope } : {}),
      ...(temporaryOrigins.length > 0 ? { temporaryOrigins } : {}),
    },
  };
}

/**
 * Origem C — acesso excepcional (F4-06, contrato fechado D6/D7/D8/D16/D17).
 * Só é chamada quando A/B DENY. Não substitui os gates globais (1–4, 5.1, 8, 9):
 * tenant, contrato capability×target, data explícita e estado do domínio
 * continuam soberanos. Fail-closed: 0 grants ⇒ mantém a negação original;
 * >1 grant sem identificação inequívoca ⇒ DENY.
 */
function autorizarOrigemExcepcional(
  request: AuthorizationRequest,
  providers: PolicyEngineProviders,
  fallbackReason: DenialReason
): AuthorizationDecision {
  const exceptional = providers.exceptional!;
  const { actor, capability, target, context } = request;

  // D8: capability ∈ allowlist FECHADA de exceção (sem prefixo/wildcard).
  if (!exceptional.isCapabilityExceptionalEligible(capability)) {
    return negar(fallbackReason);
  }

  // 5.1 compartilhado: C não fura o contrato capability × tipo de alvo (F4-04).
  if (!isCapabilityTargetCompatible(capability, target)) {
    return negar("TARGET_INCOMPATIBLE");
  }

  // D7: classificação soberana (domínio/probe). false/undefined ⇒ DENY (o
  // caller nunca informa confidencialidade; indeterminação é fail-closed).
  if (exceptional.isTargetConfidential(target, context.cycleId, actor.organizationId) !== true) {
    return negar(fallbackReason);
  }

  // 8) contexto temporal explícito (compartilhado).
  if (!context.date) return negar("INDETERMINATE");

  // 9) estado do domínio (compartilhado): C não fura regra de domínio.
  if (!request.domainState) return negar("INDETERMINATE");
  if (!request.domainState.allows(capability)) {
    return negar("DOMAIN_STATE_INVALID");
  }

  const grants = exceptional.resolveExceptionalGrants(
    actor.actorId,
    actor.organizationId,
    capability,
    target,
    context.date,
    context.cycleId
  );

  // 0 grants: C não autoriza; preserva a negação A/B original.
  if (grants.length === 0) return negar(fallbackReason);

  // D16: >1 grant aplicável sem identificação inequívoca ⇒ DENY fail-closed
  // (nunca escolher arbitrariamente; nunca o caller escolhe).
  if (grants.length > 1) return negar(fallbackReason);

  const grant = grants[0];
  const origin = `exceptional:${grant.id}`;

  // D12/Q3: evento de uso efetivo — somente quando C transforma DENY em ALLOW.
  exceptional.recordUsage?.({
    grantId: grant.id,
    organizationId: grant.organizationId,
    beneficiaryUserProfileId: grant.beneficiaryUserProfileId,
    capability,
    target,
    cycleId: context.cycleId,
    date: context.date,
    origin,
  });

  return {
    allowed: true,
    diagnostics: { exceptionalGrant: { id: grant.id, origin } },
  };
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
 * substituto de authorize(). F4-06 D18: a origem C NÃO participa desta
 * listagem — não descobre/lista conteúdo confidencial.
 */
export function listAllowedTargets(
  request: Omit<AuthorizationRequest, "target">,
  providers: PolicyEngineProviders,
  candidateTargets: readonly TargetRef[]
): TargetRef[] {
  // D18: remove a origem excepcional para que a listagem não revele inventário
  // de targets confidenciais; authorize() continua sendo a única decisão real.
  const providersSemExcecao: PolicyEngineProviders = {
    ...providers,
    exceptional: undefined,
  };
  return candidateTargets.filter((target) =>
    decidir({ ...request, target }, providersSemExcecao).allowed
  );
}
