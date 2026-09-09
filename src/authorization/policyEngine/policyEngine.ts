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
 *
 * F4-07 (Issue #94) adiciona a ORIGEM D — Pilot Full Access — como fallback
 * pontual SOMENTE quando A/B DENY e o alvo NÃO é confidencial; D é development-
 * only, baseada em perfil versionado fechado (PILOT_PROFILE_V1), nunca cobre
 * conteúdo confidencial nem capabilities de segurança, e preserva origem
 * `pilot:<grantId>` (D1–D18). C e D nunca se misturam; D nunca é fallback para
 * confidencial.
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
    // A/B negam por capability: as origens derivadas (C/D) só elevam pontualmente.
    if (providers.exceptional || providers.pilot) {
      return autorizarOrigemDerivada(request, providers, "CAPABILITY_MISSING");
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
    // A/B negam por scope/relação: as origens derivadas (C/D) só elevam pontualmente.
    if (providers.exceptional || providers.pilot) {
      return autorizarOrigemDerivada(request, providers, "SCOPE_INSUFFICIENT");
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
 * Dispatcher das origens derivadas (C — exceptional / D — Pilot Full Access),
 * chamado SOMENTE quando A/B DENY. Reaplica os gates globais compartilhados
 * (5.1 capability×target, 8 data, 9 DOMAIN_STATE) e roteia pela classificação
 * soberana de confidencialidade (D7): confidencial ⇒ C; não confidencial ⇒ D;
 * indeterminado ⇒ DENY (fail-closed). D nunca é fallback para confidencial.
 */
function autorizarOrigemDerivada(
  request: AuthorizationRequest,
  providers: PolicyEngineProviders,
  fallbackReason: DenialReason
): AuthorizationDecision {
  const { actor, capability, target, context } = request;

  // 5.1 compartilhado (D4 F4-04/F4-07): nunca tornar combinação inválida válida.
  if (!isCapabilityTargetCompatible(capability, target)) {
    return negar("TARGET_INCOMPATIBLE");
  }

  // 8) contexto temporal explícito (compartilhado).
  if (!context.date) return negar("INDETERMINATE");

  // 9) estado do domínio (compartilhado): C e D não furam regra de domínio.
  if (!request.domainState) return negar("INDETERMINATE");
  if (!request.domainState.allows(capability)) {
    return negar("DOMAIN_STATE_INVALID");
  }

  // Classificação soberana (D7): quem fornece é o domínio/probe (mesma fonte
  // da F4-06), nunca o caller.
  const classifier =
    providers.pilot?.isTargetConfidential ??
    providers.exceptional?.isTargetConfidential;
  const confidential = classifier
    ? classifier(target, context.cycleId, actor.organizationId)
    : undefined;

  // Confidencial ⇒ somente C (F4-06); D NÃO participa.
  if (confidential === true) {
    if (providers.exceptional) {
      return autorizarOrigemExcepcional(request, providers, fallbackReason);
    }
    return negar(fallbackReason);
  }

  // Não confidencial ⇒ somente D (F4-07).
  if (confidential === false) {
    if (providers.pilot) {
      return autorizarOrigemPilot(request, providers, fallbackReason);
    }
    return negar(fallbackReason);
  }

  // Indeterminado/ausente ⇒ fail-closed (nem C, nem D).
  return negar(fallbackReason);
}

/**
 * Origem C — acesso excepcional (F4-06, D6/D8/D16/D17). Só é chamada quando
 * A/B DENY e o alvo é CONFIDENCIAL. Gates globais já reaplicados no dispatcher.
 * Fail-closed: 0 grants ⇒ mantém a negação; >1 grant ⇒ DENY.
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

  const grants = exceptional.resolveExceptionalGrants(
    actor.actorId,
    actor.organizationId,
    capability,
    target,
    context.date,
    context.cycleId
  );

  if (grants.length === 0) return negar(fallbackReason);
  if (grants.length > 1) return negar(fallbackReason); // D16: ambiguidade ⇒ DENY

  const grant = grants[0];
  const origin = `exceptional:${grant.id}`;

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

/**
 * Origem D — Pilot Full Access (F4-07, D1/D6/D7/D13/D22). Só é chamada quando
 * A/B DENY e o alvo NÃO é confidencial. Gates globais já reaplicados no
 * dispatcher. Fail-closed: ambiente não-development ⇒ DENY; capability fora do
 * perfil ⇒ DENY; 0 grants ⇒ negação original; >1 grant ⇒ DENY.
 */
function autorizarOrigemPilot(
  request: AuthorizationRequest,
  providers: PolicyEngineProviders,
  fallbackReason: DenialReason
): AuthorizationDecision {
  const pilot = providers.pilot!;
  const { actor, capability, target, context } = request;

  // D13: D é exclusiva de development (gate no provider, fail-closed).
  if (!pilot.isEnvironmentEligible()) return negar(fallbackReason);

  // D1/D3: capability ∈ perfil versionado fechado (PILOT_PROFILE_V1).
  if (!pilot.isCapabilityPilotEligible(capability)) return negar(fallbackReason);

  const grants = pilot.resolvePilotFullAccessGrants(
    actor.actorId,
    actor.organizationId,
    capability,
    context.date
  );

  if (grants.length === 0) return negar(fallbackReason);
  if (grants.length > 1) return negar(fallbackReason); // D22: ambiguidade ⇒ DENY

  const grant = grants[0];
  const origin = `pilot:${grant.id}`;

  pilot.recordUsage?.({
    grantId: grant.id,
    organizationId: grant.organizationId,
    beneficiaryUserProfileId: grant.beneficiaryUserProfileId,
    capability,
    target,
    cycleId: context.cycleId,
    date: context.date,
    profileVersion: grant.profileVersion,
    origin,
  });

  return {
    allowed: true,
    diagnostics: { pilotGrant: { id: grant.id, origin } },
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
 * listagem. F4-07 D8: a origem D participa apenas para capabilities
 * pilot-eligible em alvo NÃO confidencial (o engine mantém o gate).
 */
export function listAllowedTargets(
  request: Omit<AuthorizationRequest, "target">,
  providers: PolicyEngineProviders,
  candidateTargets: readonly TargetRef[]
): TargetRef[] {
  // Remove a origem excepcional (C) para que a listagem não revele inventário
  // de targets confidenciais; a origem D (pilot) permanece, mas só lista alvos
  // não confidenciais pilot-eligible (fail-closed por ambiente/perfil).
  // authorize() continua sendo a única decisão real.
  const providersSemExcecao: PolicyEngineProviders = {
    ...providers,
    exceptional: undefined,
  };
  return candidateTargets.filter((target) =>
    decidir({ ...request, target }, providersSemExcecao).allowed
  );
}
