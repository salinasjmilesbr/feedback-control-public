import { describe, expect, it } from "vitest";
import {
  ForbiddenError,
  ValidationError,
} from "../../errors/applicationErrors";
import {
  authorize,
  can,
  decidir,
  listAllowedTargets,
} from "../policyEngine/policyEngine";
import type {
  DomainStateProbe,
  ExceptionalGrant,
  PilotFullAccessGrant,
  PilotUsageRecord,
  PolicyEngineProviders,
  TargetRef,
  TemporaryProvider,
} from "../policyEngine/types";
import { createExceptionalProvider } from "./exceptional";
import {
  createPilotFullAccessProvider,
  PILOT_PROFILE_V1,
  PILOT_PROFILES,
} from "./pilot";
import {
  concederPilotFullAccess,
  renunciarPilotFullAccess,
  revogarPilotFullAccess,
  PILOT_MAX_DURATION_DAYS,
} from "../pilotAccess";
import type { PilotAuditEvent } from "../pilotAccess";
import * as pilotModule from "./pilot";

const ORG = "org-a";
const OTHER = "org-b";
const D = new Date("2026-02-01T00:00:00Z");

const COL_1: TargetRef = { type: "collaborator", id: "col-1" };
const EVAL_1: TargetRef = { type: "evaluation", id: "eval-1" };
const CYCLE_1: TargetRef = { type: "cycle", id: "c1" };

const confidentialIds = new Set(["eval-1", "eval-2"]);

function defaultClassify(
  target: TargetRef,
  _cycleId: string | undefined,
  organizationId: string
): boolean | undefined {
  if (organizationId !== ORG) return undefined;
  return target.type === "evaluation" && confidentialIds.has(target.id);
}

const semprePermite: DomainStateProbe = { allows: () => true };

function pilotGrant(overrides: Partial<PilotFullAccessGrant> = {}): PilotFullAccessGrant {
  return {
    id: "pg1",
    organizationId: ORG,
    beneficiaryUserProfileId: "ben1",
    grantedByUserProfileId: "granter1",
    justification: "validação do piloto",
    validFrom: new Date("2026-01-01T00:00:00Z"),
    validTo: new Date("2026-02-28T00:00:00Z"),
    status: "active",
    profileVersion: "PILOT_PROFILE_V1",
    createdAt: D,
    version: 0,
    ...overrides,
  };
}

function makePilot(
  grants: PilotFullAccessGrant[],
  environment: "development" | "homologation" | "production" = "development",
  recordUsage?: (record: PilotUsageRecord) => void
) {
  return createPilotFullAccessProvider({
    organizationId: ORG,
    grants,
    environment,
    isTargetConfidential: defaultClassify,
    recordUsage,
  });
}

function makeProviders(overrides: Partial<PolicyEngineProviders> = {}): PolicyEngineProviders {
  return {
    identity: { isProfileActive: () => true, isMembershipActive: () => true },
    capabilities: { hasCapability: () => false },
    scopes: { getActiveScopes: () => [] },
    targets: {
      resolveTargetTenant: (t: TargetRef) => (t.id === "cross" ? OTHER : ORG),
    },
    relations: { isTargetInScope: () => false },
    ...overrides,
  };
}

function req(
  overrides: Partial<Parameters<typeof decidir>[0]> = {}
): Parameters<typeof decidir>[0] {
  return {
    actor: { actorId: "ben1", organizationId: ORG },
    capability: "goal.write",
    target: COL_1,
    context: { date: D },
    domainState: semprePermite,
    ...overrides,
  };
}

describe("F4-07 — origem D no Policy Engine (resolução de grant)", () => {
  it("1/28. grant válido em development ⇒ ALLOW pilot + origem + uso", () => {
    const usages: PilotUsageRecord[] = [];
    const providers = makeProviders({
      pilot: makePilot([pilotGrant()], "development", (r) => usages.push(r)),
    });
    const decision = decidir(req(), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.pilotGrant).toEqual({ id: "pg1", origin: "pilot:pg1" });
    expect(decision.diagnostics?.matchedScope).toBeUndefined();
    expect(decision.diagnostics?.exceptionalGrant).toBeUndefined();
    expect(usages).toHaveLength(1);
    expect(usages[0]).toMatchObject({
      grantId: "pg1",
      organizationId: ORG,
      beneficiaryUserProfileId: "ben1",
      capability: "goal.write",
      profileVersion: "PILOT_PROFILE_V1",
      origin: "pilot:pg1",
    });
  });

  it("2. grant futuro ⇒ DENY", () => {
    const providers = makeProviders({
      pilot: makePilot([
        pilotGrant({
          validFrom: new Date("2026-03-01T00:00:00Z"),
          validTo: new Date("2026-03-10T00:00:00Z"),
        }),
      ]),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("3. grant expirado ⇒ DENY", () => {
    const providers = makeProviders({
      pilot: makePilot([
        pilotGrant({
          validFrom: new Date("2026-01-01T00:00:00Z"),
          validTo: new Date("2026-01-15T00:00:00Z"),
        }),
      ]),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("4. grant revogado ⇒ DENY", () => {
    const providers = makeProviders({
      pilot: makePilot([pilotGrant({ status: "revoked", revokedAt: D, revokedBy: "granter1" })]),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("8. tenant diferente (grant de outra org) ⇒ DENY", () => {
    const providers = makeProviders({
      pilot: makePilot([pilotGrant({ organizationId: OTHER })]),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("8b. tenant diferente (alvo de outra org) ⇒ CROSS_TENANT", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    const decision = decidir(req({ target: { type: "collaborator", id: "cross" } }), providers);
    expect(decision.denial?.reason).toBe("CROSS_TENANT");
  });

  it("9. beneficiário diferente ⇒ DENY", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req({ actor: { actorId: "ben2", organizationId: ORG } }), providers).allowed).toBe(false);
  });

  it("10. profile inválido ⇒ DENY", () => {
    const providers = makeProviders({
      identity: { isProfileActive: () => false, isMembershipActive: () => true },
      pilot: makePilot([pilotGrant()]),
    });
    expect(decidir(req(), providers).denial?.reason).toBe("PROFILE_DISABLED");
  });

  it("11. membership inválida ⇒ DENY", () => {
    const providers = makeProviders({
      identity: { isProfileActive: () => true, isMembershipActive: () => false },
      pilot: makePilot([pilotGrant()]),
    });
    expect(decidir(req(), providers).denial?.reason).toBe("MEMBERSHIP_INVALID");
  });

  it("12. profileVersion desconhecido ⇒ DENY", () => {
    const providers = makeProviders({
      pilot: makePilot([pilotGrant({ profileVersion: "PILOT_PROFILE_UNKNOWN" })]),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("13. capability pilot-eligible ⇒ ALLOW (outra capability do perfil)", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    const decision = decidir(req({ capability: "observation.create" }), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.pilotGrant?.origin).toBe("pilot:pg1");
  });

  it("14. capability fora do perfil ⇒ DENY", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    // goal.approve.manager é variante legada excluída do perfil.
    expect(decidir(req({ capability: "goal.approve.manager" }), providers).allowed).toBe(false);
  });

  it("15. capability futura/nova não presente no perfil ⇒ DENY", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req({ capability: "settings.manage", target: CYCLE_1 }), providers).allowed).toBe(false);
  });

  it("16. evaluation.* fora de D ⇒ DENY (confidencial; sem C)", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    const decision = decidir(
      req({ capability: "evaluation.read", target: EVAL_1, context: { date: D, cycleId: "c1" } }),
      providers
    );
    expect(decision.allowed).toBe(false);
  });

  it("17. report.view fora de D ⇒ DENY", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req({ capability: "report.view" }), providers).allowed).toBe(false);
  });

  it("18. settings.manage fora de D ⇒ DENY", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req({ capability: "settings.manage", target: CYCLE_1 }), providers).allowed).toBe(false);
  });

  it("19. exceptional_access.grant fora de D ⇒ DENY", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req({ capability: "exceptional_access.grant", target: EVAL_1 }), providers).allowed).toBe(false);
  });

  it("20. pilot_full_access.grant fora de D ⇒ DENY (D não concede D)", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req({ capability: "pilot_full_access.grant", target: CYCLE_1 }), providers).allowed).toBe(false);
  });

  it("21. capability × target inválido ⇒ TARGET_INCOMPATIBLE", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    const decision = decidir(req({ capability: "goal.write", target: EVAL_1 }), providers);
    expect(decision.denial?.reason).toBe("TARGET_INCOMPATIBLE");
  });

  it("22. DOMAIN_STATE inválido ⇒ DENY", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    const decision = decidir(req({ domainState: { allows: () => false } }), providers);
    expect(decision.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("23/24. target confidencial + D válido + C inexistente ⇒ DENY (D não é fallback)", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    const decision = decidir(
      req({ capability: "evaluation.read", target: EVAL_1, context: { date: D, cycleId: "c1" } }),
      providers
    );
    expect(decision.allowed).toBe(false);
  });

  it("25. target confidencial + C válido + D válido ⇒ C autoriza, D não consome", () => {
    const usages: PilotUsageRecord[] = [];
    const exceptionalGrant: ExceptionalGrant = {
      id: "g1",
      organizationId: ORG,
      beneficiaryUserProfileId: "ben1",
      grantedByUserProfileId: "granter1",
      capability: "evaluation.read",
      target: EVAL_1,
      cycleId: "c1",
      justification: "auditoria",
      validFrom: new Date("2026-01-01T00:00:00Z"),
      validTo: new Date("2026-03-01T00:00:00Z"),
      status: "active",
    };
    const providers = makeProviders({
      exceptional: createExceptionalProvider({
        organizationId: ORG,
        grants: [exceptionalGrant],
        isTargetConfidential: defaultClassify,
      }),
      pilot: makePilot([pilotGrant()], "development", (r) => usages.push(r)),
    });
    const decision = decidir(
      req({ capability: "evaluation.read", target: EVAL_1, context: { date: D, cycleId: "c1" } }),
      providers
    );
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.exceptionalGrant?.origin).toBe("exceptional:g1");
    expect(decision.diagnostics?.pilotGrant).toBeUndefined();
    expect(usages).toHaveLength(0);
  });

  it("26. target não confidencial + A ALLOW + D existente ⇒ A autoriza, D não consome", () => {
    const usages: PilotUsageRecord[] = [];
    const providers = makeProviders({
      capabilities: {
        hasCapability: (a, _o, cap) => a === "ben1" && cap === "goal.write",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, s) => s === "ORGANIZATION" },
      pilot: makePilot([pilotGrant()], "development", (r) => usages.push(r)),
    });
    const decision = decidir(req(), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.matchedScope).toBe("ORGANIZATION");
    expect(decision.diagnostics?.pilotGrant).toBeUndefined();
    expect(usages).toHaveLength(0);
  });

  it("27. target não confidencial + B ALLOW + D existente ⇒ B autoriza, D não consome", () => {
    const usages: PilotUsageRecord[] = [];
    const temporary: TemporaryProvider = {
      getEligibleCapabilities: () => ["goal.write"],
      resolveTemporaryGrants: (a, o, c, t) =>
        a === "ben1" && o === ORG && c === "goal.write" && t.id === "col-1"
          ? [
              {
                origin: "temporary:r1",
                responsibilityId: "r1",
                responsibilityType: "operational",
                capability: "goal.write",
                scope: "DESCENDANTS",
                substitutedPositionId: "p1",
              },
            ]
          : [],
    };
    const providers = makeProviders({
      temporary,
      pilot: makePilot([pilotGrant()], "development", (r) => usages.push(r)),
    });
    const decision = decidir(req(), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.temporaryOrigins).toEqual(["temporary:r1"]);
    expect(decision.diagnostics?.pilotGrant).toBeUndefined();
    expect(usages).toHaveLength(0);
  });

  it("29/30/31. ambiente: development elegível; homologation/production DENY", () => {
    const dev = makeProviders({ pilot: makePilot([pilotGrant()], "development") });
    expect(decidir(req(), dev).allowed).toBe(true);

    const hom = makeProviders({ pilot: makePilot([pilotGrant()], "homologation") });
    expect(decidir(req(), hom).allowed).toBe(false);

    const prod = makeProviders({ pilot: makePilot([pilotGrant()], "production") });
    expect(decidir(req(), prod).allowed).toBe(false);
  });

  it("32/33. caller não escolhe grant nem origem (resolução por dados)", () => {
    const providers = makeProviders({
      pilot: makePilot([
        pilotGrant({ id: "pg1" }),
        pilotGrant({ id: "pg2", beneficiaryUserProfileId: "ben2" }),
      ]),
    });
    const decision = decidir(req(), providers);
    expect(decision.diagnostics?.pilotGrant?.id).toBe("pg1");
    // origem D é a única presente; sem matchedScope/temporary/exceptional.
    expect(decision.diagnostics?.matchedScope).toBeUndefined();
    expect(decision.diagnostics?.temporaryOrigins).toBeUndefined();
    expect(decision.diagnostics?.exceptionalGrant).toBeUndefined();
  });

  it("34. múltiplos grants ambíguos ⇒ DENY", () => {
    const providers = makeProviders({
      pilot: makePilot([pilotGrant({ id: "pg1" }), pilotGrant({ id: "pg1b" })]),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("42/43. revogação/renúncia com efeito imediato (grant revogado não autoriza)", () => {
    const providers = makeProviders({
      pilot: makePilot([
        pilotGrant({ status: "revoked", revokedAt: D, revokedBy: "granter1" }),
      ]),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("44. novo grant após expiração funciona de forma independente", () => {
    const providers = makeProviders({
      pilot: makePilot([
        pilotGrant({ id: "exp", validTo: new Date("2026-01-15T00:00:00Z") }),
        pilotGrant({ id: "novo", validFrom: new Date("2026-01-20T00:00:00Z"), validTo: new Date("2026-02-20T00:00:00Z") }),
      ]),
    });
    const decision = decidir(req(), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.pilotGrant?.id).toBe("novo");
  });

  it("52. histórico congelado não pode ser alterado (mutações de avaliação fora de D)", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    // evaluation.write é conteúdo confidencial ⇒ fora de D ⇒ DENY.
    const decision = decidir(
      req({ capability: "evaluation.write", target: EVAL_1, context: { date: D, cycleId: "c1" } }),
      providers
    );
    expect(decision.allowed).toBe(false);
  });

  it("53. leitura elegível respeita DOMAIN_STATE", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req({ capability: "collaborator.list" }), providers).allowed).toBe(true);
    expect(
      decidir(req({ capability: "collaborator.list", domainState: { allows: () => false } }), providers)
        .allowed
    ).toBe(false);
  });

  it("54. cross-tenant (alvo de outra org) ⇒ DENY", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req({ target: { type: "collaborator", id: "cross" } }), providers).allowed).toBe(false);
  });

  it("55. caminho D não consulta cargo/job_role (comportamental)", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    expect(decidir(req(), providers).allowed).toBe(true);
    const exported = Object.keys(pilotModule);
    expect(exported.some((k) => /cargo|funcao|job/i.test(k))).toBe(false);
  });

  it("56/57. perfil é lista explícita, sem wildcard e sem expansão automática", () => {
    expect(PILOT_PROFILE_V1).toHaveLength(20);
    expect(PILOT_PROFILE_V1.some((c) => c.includes("*"))).toBe(false);
    expect(PILOT_PROFILES["PILOT_PROFILE_V1"]).toEqual(PILOT_PROFILE_V1);
    // capabilities novas/segurança não entram automaticamente no perfil.
    expect(PILOT_PROFILE_V1.includes("exceptional_access.grant")).toBe(false);
    expect(PILOT_PROFILE_V1.includes("pilot_full_access.grant")).toBe(false);
    expect(PILOT_PROFILE_V1.includes("evaluation.read")).toBe(false);
  });

  it("can() devolve decisão estruturada sem lançar para DENY da origem D", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant({ validTo: new Date("2026-01-15T00:00:00Z") })]) });
    expect(() => can(req(), providers)).not.toThrow();
    expect(can(req(), providers).allowed).toBe(false);
  });
});

describe("F4-07 — concessão (D10/D11/D14)", () => {
  function grantorProviders(grantor = "granter1"): PolicyEngineProviders {
    return makeProviders({
      capabilities: {
        hasCapability: (a, _o, cap) => a === grantor && cap === "pilot_full_access.grant",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, s) => s === "ORGANIZATION" },
    });
  }

  const base = () => ({
    organizationId: ORG,
    grantedByUserProfileId: "granter1",
    beneficiaryUserProfileId: "ben1",
    justification: "validação do piloto",
    validFrom: new Date("2026-02-01T00:00:00Z"),
    validTo: new Date("2026-02-11T00:00:00Z"),
    profileVersion: "PILOT_PROFILE_V1",
    providers: grantorProviders(),
    domainState: semprePermite,
    date: D,
    authorizationTarget: CYCLE_1,
    grantId: "pgx",
  });

  it("37. concessão válida gera grant ativo + evento granted", () => {
    const events: PilotAuditEvent[] = [];
    const g = concederPilotFullAccess({ ...base(), audit: (e) => events.push(e) });
    expect(g.status).toBe("active");
    expect(g.grantedByUserProfileId).toBe("granter1");
    expect(g.beneficiaryUserProfileId).toBe("ben1");
    expect(g.profileVersion).toBe("PILOT_PROFILE_V1");
    expect(events).toHaveLength(1);
    expect(events[0].kind).toBe("granted");
  });

  it("9. justificativa ausente ⇒ rejeitada", () => {
    expect(() => concederPilotFullAccess({ ...base(), justification: "  " })).toThrow(ValidationError);
  });

  it("10/11. período inválido/permanente ⇒ rejeitado", () => {
    expect(() =>
      concederPilotFullAccess({
        ...base(),
        validFrom: new Date("2026-02-11T00:00:00Z"),
        validTo: new Date("2026-02-01T00:00:00Z"),
      })
    ).toThrow(ValidationError);
  });

  it("5/12. grant > 30 dias ⇒ inválido", () => {
    expect(() =>
      concederPilotFullAccess({
        ...base(),
        validTo: new Date("2026-03-04T00:00:00Z"), // 31 dias após validFrom
      })
    ).toThrow(ValidationError);
    expect(PILOT_MAX_DURATION_DAYS).toBe(30);
  });

  it("7. retroativo (validFrom anterior à concessão) ⇒ rejeitado", () => {
    expect(() =>
      concederPilotFullAccess({ ...base(), validFrom: new Date("2026-01-01T00:00:00Z") })
    ).toThrow(ValidationError);
  });

  it("12b. profileVersion desconhecido ⇒ rejeitado", () => {
    expect(() => concederPilotFullAccess({ ...base(), profileVersion: "NOPE" })).toThrow(ValidationError);
  });

  it("35. auto-concessão ⇒ proibida", () => {
    expect(() =>
      concederPilotFullAccess({
        ...base(),
        grantedByUserProfileId: "ben1",
        beneficiaryUserProfileId: "ben1",
      })
    ).toThrow(ValidationError);
  });

  it("36. concedente sem pilot_full_access.grant ⇒ ForbiddenError", () => {
    expect(() =>
      concederPilotFullAccess({
        ...base(),
        providers: makeProviders({
          capabilities: { hasCapability: () => false },
          scopes: { getActiveScopes: () => ["ORGANIZATION"] },
          relations: { isTargetInScope: (_a, _o, s) => s === "ORGANIZATION" },
        }),
      })
    ).toThrow(ForbiddenError);
  });

  it("48b. pilot_full_access.grant não é concedida pelo próprio D (capability fora do perfil)", () => {
    expect(PILOT_PROFILE_V1.includes("pilot_full_access.grant")).toBe(false);
  });
});

describe("F4-07 — revogação e renúncia (D12/D14)", () => {
  function grantorProviders(grantor = "granter1"): PolicyEngineProviders {
    return makeProviders({
      capabilities: {
        hasCapability: (a, _o, cap) => a === grantor && cap === "pilot_full_access.grant",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, s) => s === "ORGANIZATION" },
    });
  }

  it("38. revogação pelo concedente gera evento revoked", () => {
    const events: PilotAuditEvent[] = [];
    const revoked = revogarPilotFullAccess({
      grant: pilotGrant(),
      revokedByUserProfileId: "granter1",
      motive: "fim do piloto",
      providers: grantorProviders(),
      domainState: semprePermite,
      date: D,
      authorizationTarget: CYCLE_1,
      audit: (e) => events.push(e),
    });
    expect(revoked.status).toBe("revoked");
    expect(revoked.revokedBy).toBe("granter1");
    expect(revoked.revocationMotive).toBe("fim do piloto");
    expect(events).toHaveLength(1);
    expect(events[0].kind).toBe("revoked");
  });

  it("39. revogação por outro ator com capability apropriada", () => {
    const revoked = revogarPilotFullAccess({
      grant: pilotGrant(),
      revokedByUserProfileId: "granter2",
      motive: "revogação administrativa",
      providers: grantorProviders("granter2"),
      domainState: semprePermite,
      date: D,
      authorizationTarget: CYCLE_1,
    });
    expect(revoked.status).toBe("revoked");
    expect(revoked.revokedBy).toBe("granter2");
  });

  it("40. renúncia pelo beneficiário gera evento relinquished", () => {
    const events: PilotAuditEvent[] = [];
    const relinquished = renunciarPilotFullAccess({
      grant: pilotGrant(),
      beneficiaryUserProfileId: "ben1",
      date: D,
      audit: (e) => events.push(e),
    });
    expect(relinquished.status).toBe("revoked");
    expect(relinquished.revokedBy).toBe("ben1");
    expect(events).toHaveLength(1);
    expect(events[0].kind).toBe("relinquished");
  });

  it("41. terceiro tentando renunciar ⇒ ForbiddenError", () => {
    expect(() =>
      renunciarPilotFullAccess({
        grant: pilotGrant(),
        beneficiaryUserProfileId: "outro",
        date: D,
      })
    ).toThrow(ForbiddenError);
  });

  it("42. revogação tem efeito imediato (grant revogado não autoriza)", () => {
    const revoked = revogarPilotFullAccess({
      grant: pilotGrant(),
      revokedByUserProfileId: "granter1",
      motive: "m",
      providers: grantorProviders(),
      domainState: semprePermite,
      date: D,
      authorizationTarget: CYCLE_1,
    });
    const providers = makeProviders({ pilot: makePilot([revoked]) });
    expect(decidir(req(), providers).allowed).toBe(false);
  });
});

describe("F4-07 — listAllowedTargets (D8)", () => {
  it("50/51. D lista somente elegíveis não confidenciais; nunca confidencial", () => {
    const providers = makeProviders({ pilot: makePilot([pilotGrant()]) });
    const candidatos: TargetRef[] = [COL_1, EVAL_1];
    const listados = listAllowedTargets(
      {
        actor: { actorId: "ben1", organizationId: ORG },
        capability: "goal.write",
        context: { date: D },
        domainState: semprePermite,
      },
      providers,
      candidatos
    );
    expect(listados).toEqual([COL_1]);
    // authorize continua sendo a decisão real.
    expect(() => authorize(req({ target: EVAL_1 }), providers)).toThrow(ForbiddenError);
  });
});
