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
  ExceptionalUsageRecord,
  PolicyEngineProviders,
  TargetRef,
  TemporaryProvider,
} from "../policyEngine/types";
import {
  createExceptionalProvider,
  EXCEPTIONAL_CAPABILITIES,
} from "./exceptional";
import {
  concederAcessoExcepcional,
  revogarAcessoExcepcional,
} from "../exceptionalAccess";
import type { ExceptionalAuditEvent } from "../exceptionalAccess";
import * as exceptionalModule from "./exceptional";

const ORG = "org-a";
const OTHER = "org-b";
const D = new Date("2026-02-01T00:00:00Z");

const EVAL_1: TargetRef = { type: "evaluation", id: "eval-1" };
const EVAL_2: TargetRef = { type: "evaluation", id: "eval-2" };

const confidentialIds = new Set(["eval-1", "eval-2"]);

function defaultClassify(
  target: TargetRef,
  _cycleId: string | undefined,
  organizationId: string
): boolean | undefined {
  if (organizationId !== ORG) return undefined;
  if (target.type !== "evaluation") return false;
  return confidentialIds.has(target.id);
}

function grant(overrides: Partial<ExceptionalGrant> = {}): ExceptionalGrant {
  return {
    id: "g1",
    organizationId: ORG,
    beneficiaryUserProfileId: "ben1",
    grantedByUserProfileId: "granter1",
    capability: "evaluation.read",
    target: EVAL_1,
    cycleId: "c1",
    justification: "auditoria de avaliação confidencial",
    validFrom: new Date("2026-01-01T00:00:00Z"),
    validTo: new Date("2026-03-01T00:00:00Z"),
    status: "active",
    ...overrides,
  };
}

interface ExceptionalOpts {
  grants: ExceptionalGrant[];
  isTargetConfidential?: (
    target: TargetRef,
    cycleId: string | undefined,
    organizationId: string
  ) => boolean | undefined;
  recordUsage?: (record: ExceptionalUsageRecord) => void;
}

function makeExceptional(opts: ExceptionalOpts) {
  return createExceptionalProvider({
    organizationId: ORG,
    grants: opts.grants,
    isTargetConfidential: opts.isTargetConfidential ?? defaultClassify,
    recordUsage: opts.recordUsage,
  });
}

function makeProviders(overrides: Partial<PolicyEngineProviders> = {}): PolicyEngineProviders {
  return {
    identity: {
      isProfileActive: () => true,
      isMembershipActive: () => true,
    },
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
    capability: "evaluation.read",
    target: EVAL_1,
    context: { date: D, cycleId: "c1" },
    domainState: { allows: () => true },
    ...overrides,
  };
}

const semprePermite: DomainStateProbe = { allows: () => true };

describe("F4-06 — origem C no Policy Engine (resolução de grant)", () => {
  it("1. grant válido ⇒ ALLOW excepcional com origem exceptional:<id> + uso", () => {
    const usages: ExceptionalUsageRecord[] = [];
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()], recordUsage: (r) => usages.push(r) }),
    });
    const decision = decidir(req(), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.exceptionalGrant).toEqual({
      id: "g1",
      origin: "exceptional:g1",
    });
    expect(decision.diagnostics?.matchedScope).toBeUndefined();
    expect(usages).toHaveLength(1);
    expect(usages[0]).toMatchObject({
      grantId: "g1",
      organizationId: ORG,
      beneficiaryUserProfileId: "ben1",
      capability: "evaluation.read",
      origin: "exceptional:g1",
    });
  });

  it("2. grant expirado ⇒ DENY (sem uso)", () => {
    const usages: ExceptionalUsageRecord[] = [];
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [
          grant({
            validFrom: new Date("2025-01-01T00:00:00Z"),
            validTo: new Date("2026-01-15T00:00:00Z"),
          }),
        ],
        recordUsage: (r) => usages.push(r),
      }),
    });
    const decision = decidir(req(), providers);
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("CAPABILITY_MISSING");
    expect(usages).toHaveLength(0);
  });

  it("3. grant futuro ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [
          grant({
            validFrom: new Date("2026-04-01T00:00:00Z"),
            validTo: new Date("2026-05-01T00:00:00Z"),
          }),
        ],
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("4. grant revogado ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [grant({ status: "revoked", revokedAt: D, revokedBy: "granter1" })],
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("5. capability diferente da concedida ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    // evaluation.write não está na allowlist de exceção.
    expect(decidir(req({ capability: "evaluation.write" }), providers).allowed).toBe(false);
  });

  it("6. target diferente ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    expect(decidir(req({ target: EVAL_2 }), providers).allowed).toBe(false);
  });

  it("7. target type diferente (colaborador) ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    const decision = decidir(
      req({ target: { type: "collaborator", id: "ben1" } }),
      providers
    );
    expect(decision.allowed).toBe(false);
  });

  it("7b. target type incompatível com a capability ⇒ TARGET_INCOMPATIBLE", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    const decision = decidir(req({ target: { type: "goal", id: "x" } }), providers);
    expect(decision.denial?.reason).toBe("TARGET_INCOMPATIBLE");
  });

  it("8. cycleId errado ⇒ DENY; cycleId ausente ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    expect(
      decidir(req({ context: { date: D, cycleId: "c2" } }), providers).allowed
    ).toBe(false);
    expect(
      decidir(req({ context: { date: D } }), providers).allowed
    ).toBe(false);
  });

  it("9. cross-tenant (grant de outra org) ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [grant({ organizationId: OTHER })],
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("9b. cross-tenant (alvo de outra org) ⇒ CROSS_TENANT", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    const decision = decidir(req({ target: { type: "evaluation", id: "cross" } }), providers);
    expect(decision.denial?.reason).toBe("CROSS_TENANT");
  });

  it("10. beneficiário diferente ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    const decision = decidir(
      req({ actor: { actorId: "ben2", organizationId: ORG } }),
      providers
    );
    expect(decision.allowed).toBe(false);
  });

  it("11/12. caller não seleciona grant nem origem (resolução por dados)", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [
          grant({ id: "g1" }),
          grant({ id: "g2", target: EVAL_2 }),
        ],
      }),
    });
    // o pedido referencia somente o target; o engine resolve o grant exato.
    const decision = decidir(req({ target: EVAL_1 }), providers);
    expect(decision.diagnostics?.exceptionalGrant?.id).toBe("g1");
    const decision2 = decidir(req({ target: EVAL_2 }), providers);
    expect(decision2.diagnostics?.exceptionalGrant?.id).toBe("g2");
  });

  it("13. membership inválido ⇒ DENY (C não é consultada)", () => {
    const usages: ExceptionalUsageRecord[] = [];
    const providers = makeProviders({
      identity: {
        isProfileActive: () => true,
        isMembershipActive: () => false,
      },
      exceptional: makeExceptional({
        grants: [grant()],
        recordUsage: (r) => usages.push(r),
      }),
    });
    expect(decidir(req(), providers).denial?.reason).toBe("MEMBERSHIP_INVALID");
    expect(usages).toHaveLength(0);
  });

  it("14. profile desabilitado ⇒ DENY (C não é consultada)", () => {
    const providers = makeProviders({
      identity: {
        isProfileActive: () => false,
        isMembershipActive: () => true,
      },
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    expect(decidir(req(), providers).denial?.reason).toBe("PROFILE_DISABLED");
  });
});

describe("F4-06 — classificação de confidencialidade (D7)", () => {
  it("15. conteúdo normal (não confidencial) ⇒ C não consultada ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [grant()],
        isTargetConfidential: () => false,
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("16. conteúdo confidencial ⇒ C consultada (ALLOW excepcional)", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [grant()],
        isTargetConfidential: () => true,
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(true);
  });

  it("17. classificação indeterminada (undefined) ⇒ DENY fail-closed", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [grant()],
        isTargetConfidential: () => undefined,
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("18. caller NÃO informa confidencialidade (não há campo no request)", () => {
    // O AuthorizationRequest não possui flag de confidencialidade; a
    // classificação vem somente do provider/domínio.
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    expect(decidir(req(), providers).allowed).toBe(true);
  });
});

describe("F4-06 — ordem A/B → C (D6)", () => {
  it("19. A/B ALLOW + grant C existente ⇒ ALLOW normal, C não consumida, sem uso", () => {
    const usages: ExceptionalUsageRecord[] = [];
    const providers = makeProviders({
      capabilities: {
        hasCapability: (actorId, _org, cap) =>
          actorId === "ben1" && cap === "evaluation.read",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, scope) => scope === "ORGANIZATION" },
      exceptional: makeExceptional({
        grants: [grant()],
        recordUsage: (r) => usages.push(r),
      }),
    });
    const decision = decidir(req(), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.matchedScope).toBe("ORGANIZATION");
    expect(decision.diagnostics?.exceptionalGrant).toBeUndefined();
    expect(usages).toHaveLength(0);
  });

  it("20. A/B DENY + grant C válido ⇒ ALLOW excepcional com uso", () => {
    const usages: ExceptionalUsageRecord[] = [];
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [grant()],
        recordUsage: (r) => usages.push(r),
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(true);
    expect(usages).toHaveLength(1);
  });

  it("21. C não é consultada quando A/B negam por estado de domínio", () => {
    // DOMAIN_STATE continua soberano (passo 9): C não fura regra de domínio.
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    const decision = decidir(
      req({ domainState: { allows: () => false } }),
      providers
    );
    expect(decision.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });
});

describe("F4-06 — coexistência com a F4-05 (origem B independente)", () => {
  it("22. B (temporary) e C (exceptional) coexistem com origens distintas", () => {
    const temporaryProvider: TemporaryProvider = {
      getEligibleCapabilities: () => ["goal.approve"],
      resolveTemporaryGrants: (a, o, c, t) =>
        a === "ben1" && o === ORG && c === "goal.approve" && t.type === "collaborator" && t.id === "col-1"
          ? [
              {
                origin: "temporary:r1",
                responsibilityId: "r1",
                responsibilityType: "operational",
                capability: "goal.approve",
                scope: "DESCENDANTS",
                substitutedPositionId: "p1",
              },
            ]
          : [],
    };
    const providers = makeProviders({
      temporary: temporaryProvider,
      exceptional: makeExceptional({ grants: [grant()] }),
    });

    // B autoriza goal.approve sobre col-1 (origem temporary:<id>).
    const viaB = decidir(
      req({
        capability: "goal.approve",
        target: { type: "collaborator", id: "col-1" },
      }),
      providers
    );
    expect(viaB.allowed).toBe(true);
    expect(viaB.diagnostics?.temporaryOrigins).toEqual(["temporary:r1"]);
    expect(viaB.diagnostics?.exceptionalGrant).toBeUndefined();

    // C autoriza evaluation.read sobre eval-1 (origem exceptional:<id>).
    const viaC = decidir(req(), providers);
    expect(viaC.allowed).toBe(true);
    expect(viaC.diagnostics?.exceptionalGrant?.origin).toBe("exceptional:g1");
    expect(viaC.diagnostics?.temporaryOrigins).toBeUndefined();
  });

  it("23. temporary responsibility NÃO cria C (capability não elegível)", () => {
    // goal.approve não pertence à allowlist excepcional: mesmo com B ativo,
    // a origem C não concede goal.approve sobre alvo confidencial.
    expect(EXCEPTIONAL_CAPABILITIES).toEqual(["evaluation.read"]);
    expect(EXCEPTIONAL_CAPABILITIES.includes("goal.approve")).toBe(false);
  });
});

describe("F4-06 — múltiplos grants (D16)", () => {
  it("24. múltiplos grants aplicáveis ao mesmo pedido ⇒ DENY fail-closed", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [
          grant({ id: "g1" }),
          grant({ id: "g1b" }), // mesmo beneficiário/capability/target/ciclo/janela
        ],
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("25. múltiplos grants, apenas um corresponde ⇒ ALLOW pelo correspondente", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [
          grant({ id: "g1" }),
          grant({ id: "g2", target: EVAL_2 }),
        ],
      }),
    });
    expect(decidir(req({ target: EVAL_1 }), providers).diagnostics?.exceptionalGrant?.id).toBe("g1");
    expect(decidir(req({ target: EVAL_2 }), providers).diagnostics?.exceptionalGrant?.id).toBe("g2");
  });

  it("26. nunca escolher primeiro/último/mais recente (ambiguidade ⇒ DENY)", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [
          grant({ id: "antigo", validFrom: new Date("2026-01-01T00:00:00Z") }),
          grant({ id: "recente", validFrom: new Date("2026-01-20T00:00:00Z") }),
        ],
      }),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });
});

describe("F4-06 — somente leitura e allowlist fechada (D8)", () => {
  it("27. capability não elegível (escrita) ⇒ DENY", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    expect(decidir(req({ capability: "evaluation.write" }), providers).allowed).toBe(false);
  });

  it("28. allowlist é fechada: somente evaluation.read", () => {
    expect(EXCEPTIONAL_CAPABILITIES).toEqual(["evaluation.read"]);
  });

  it("29. capability administrativa não é capability de conteúdo (e vice-versa)", () => {
    expect(EXCEPTIONAL_CAPABILITIES.includes("exceptional_access.grant")).toBe(false);
  });
});

describe("F4-06 — auditoria (concessão, revogação, uso)", () => {
  function concedentes(): PolicyEngineProviders {
    return makeProviders({
      capabilities: {
        hasCapability: (actorId, _org, cap) =>
          actorId === "granter1" && cap === "exceptional_access.grant",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, scope) => scope === "ORGANIZATION" },
    });
  }

  it("30. concessão válida gera evento granted + grant ativo", () => {
    const events: ExceptionalAuditEvent[] = [];
    const g = concederAcessoExcepcional({
      organizationId: ORG,
      grantedByUserProfileId: "granter1",
      beneficiaryUserProfileId: "ben1",
      capability: "evaluation.read",
      target: EVAL_1,
      cycleId: "c1",
      justification: "auditoria confidencial",
      validFrom: new Date("2026-01-01T00:00:00Z"),
      validTo: new Date("2026-03-01T00:00:00Z"),
      providers: concedentes(),
      domainState: semprePermite,
      date: D,
      grantId: "g1",
      audit: (e) => events.push(e),
    });
    expect(g.status).toBe("active");
    expect(g.grantedByUserProfileId).toBe("granter1");
    expect(g.beneficiaryUserProfileId).toBe("ben1");
    expect(events).toHaveLength(1);
    expect(events[0].kind).toBe("granted");
  });

  it("31. revogação gera evento revoked com quem/quando/motivo (não exclui)", () => {
    const events: ExceptionalAuditEvent[] = [];
    const active = grant();
    const revoked = revogarAcessoExcepcional({
      grant: active,
      revokedByUserProfileId: "granter1",
      motive: "fim da necessidade",
      providers: concedentes(),
      domainState: semprePermite,
      date: D,
      audit: (e) => events.push(e),
    });
    expect(revoked.status).toBe("revoked");
    expect(revoked.revokedBy).toBe("granter1");
    expect(revoked.revocationMotive).toBe("fim da necessidade");
    expect(revoked.revokedAt).toEqual(D);
    expect(events).toHaveLength(1);
    expect(events[0].kind).toBe("revoked");
    // registro não é fisicamente apagado (o objeto preserva os campos)
    expect(revoked.id).toBe(active.id);
  });

  it("32. revogação por ator com capability apropriada (não concedente)", () => {
    const providers = makeProviders({
      capabilities: {
        hasCapability: (actorId, _org, cap) =>
          actorId === "granter2" && cap === "exceptional_access.grant",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, scope) => scope === "ORGANIZATION" },
    });
    const revoked = revogarAcessoExcepcional({
      grant: grant(),
      revokedByUserProfileId: "granter2",
      motive: "revogação por administrador",
      providers,
      domainState: semprePermite,
      date: D,
    });
    expect(revoked.status).toBe("revoked");
    expect(revoked.revokedBy).toBe("granter2");
  });

  it("33. uso efetivo registrado somente quando C autoriza (posse ≠ consumo)", () => {
    const usages: ExceptionalUsageRecord[] = [];
    const providers = makeProviders({
      exceptional: makeExceptional({
        grants: [grant()],
        recordUsage: (r) => usages.push(r),
      }),
    });
    // A/B negam (sem capability/scope) → C autoriza → uso registrado.
    expect(decidir(req(), providers).allowed).toBe(true);
    expect(usages).toHaveLength(1);

    // A/B autorizam → C não consumida → sem uso.
    const usages2: ExceptionalUsageRecord[] = [];
    const providersAb = makeProviders({
      capabilities: {
        hasCapability: (a, _o, cap) => a === "ben1" && cap === "evaluation.read",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, s) => s === "ORGANIZATION" },
      exceptional: makeExceptional({
        grants: [grant()],
        recordUsage: (r) => usages2.push(r),
      }),
    });
    expect(decidir(req(), providersAb).allowed).toBe(true);
    expect(usages2).toHaveLength(0);
  });
});

describe("F4-06 — validações de concessão (D5/D8/D10/D11/D13)", () => {
  function concedentes(): PolicyEngineProviders {
    return makeProviders({
      capabilities: {
        hasCapability: (actorId, _org, cap) =>
          actorId === "granter1" && cap === "exceptional_access.grant",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, scope) => scope === "ORGANIZATION" },
    });
  }

  const base = () => ({
    organizationId: ORG,
    grantedByUserProfileId: "granter1",
    beneficiaryUserProfileId: "ben1",
    capability: "evaluation.read" as const,
    target: EVAL_1,
    cycleId: "c1",
    justification: "auditoria confidencial",
    validFrom: new Date("2026-01-01T00:00:00Z"),
    validTo: new Date("2026-03-01T00:00:00Z"),
    providers: concedentes(),
    domainState: semprePermite,
    date: D,
    grantId: "gx",
  });

  it("34. justificativa ausente ⇒ rejeitada", () => {
    expect(() =>
      concederAcessoExcepcional({ ...base(), justification: "   " })
    ).toThrow(ValidationError);
  });

  it("35. período inválido (validTo <= validFrom) ⇒ rejeitado", () => {
    expect(() =>
      concederAcessoExcepcional({
        ...base(),
        validFrom: new Date("2026-03-01T00:00:00Z"),
        validTo: new Date("2026-01-01T00:00:00Z"),
      })
    ).toThrow(ValidationError);
  });

  it("36. auto-concessão (grantedBy = beneficiary) ⇒ proibida", () => {
    expect(() =>
      concederAcessoExcepcional({
        ...base(),
        grantedByUserProfileId: "ben1",
        beneficiaryUserProfileId: "ben1",
      })
    ).toThrow(ValidationError);
  });

  it("37. cycleId ausente em recurso por ciclo ⇒ rejeitado", () => {
    expect(() =>
      concederAcessoExcepcional({ ...base(), cycleId: "" })
    ).toThrow(ValidationError);
  });

  it("38. target não elegível (não-evaluation) ⇒ rejeitado (sem wildcard)", () => {
    expect(() =>
      concederAcessoExcepcional({
        ...base(),
        target: { type: "collaborator", id: "ben1" },
      })
    ).toThrow(ValidationError);
  });

  it("39. capability fora da allowlist (escrita/administrativa) ⇒ rejeitada", () => {
    expect(() =>
      concederAcessoExcepcional({ ...base(), capability: "evaluation.write" })
    ).toThrow(ValidationError);
    expect(() =>
      concederAcessoExcepcional({ ...base(), capability: "exceptional_access.grant" })
    ).toThrow(ValidationError);
  });

  it("40. concedente sem exceptional_access.grant ⇒ ForbiddenError", () => {
    const providers = makeProviders({
      capabilities: { hasCapability: () => false },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, scope) => scope === "ORGANIZATION" },
    });
    expect(() =>
      concederAcessoExcepcional({ ...base(), providers })
    ).toThrow(ForbiddenError);
  });

  it("41. capability de concessão não concede leitura do conteúdo", () => {
    // granter1 tem only exceptional_access.grant (não evaluation.read) e não
    // possui grant C: ler o conteúdo é negado.
    const providers = makeProviders({
      capabilities: {
        hasCapability: (actorId, _org, cap) =>
          actorId === "granter1" && cap === "exceptional_access.grant",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, scope) => scope === "ORGANIZATION" },
      exceptional: makeExceptional({ grants: [] }),
    });
    const decision = decidir(
      req({
        actor: { actorId: "granter1", organizationId: ORG },
        capability: "evaluation.read",
        target: EVAL_1,
      }),
      providers
    );
    expect(decision.allowed).toBe(false);
  });

  it("42. possuir evaluation.read (grant) não concede a capability de concessão", () => {
    // ben1 tem grant C de leitura, mas tenta conceder → sem exceptional_access.grant.
    const providers = makeProviders({
      capabilities: { hasCapability: () => false },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, scope) => scope === "ORGANIZATION" },
    });
    expect(() =>
      concederAcessoExcepcional({
        ...base(),
        grantedByUserProfileId: "ben1",
        beneficiaryUserProfileId: "other",
        providers,
      })
    ).toThrow(ForbiddenError);
  });
});

describe("F4-06 — revogação/vigência/identidade (D13/D14)", () => {
  it("43. revogação tem efeito imediato (grant revogado não autoriza)", () => {
    const active = grant();
    const revoked = revogarAcessoExcepcional({
      grant: active,
      revokedByUserProfileId: "granter1",
      motive: "m",
      providers: makeProviders(),
      domainState: semprePermite,
      date: D,
    });
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [revoked] }),
    });
    expect(decidir(req(), providers).allowed).toBe(false);
  });

  it("44. grant vencendo entre duas operações ⇒ segunda operação DENY", () => {
    const g = grant({
      validFrom: new Date("2026-01-01T00:00:00Z"),
      validTo: new Date("2026-02-01T12:00:00Z"),
    });
    const providers = makeProviders({ exceptional: makeExceptional({ grants: [g] }) });
    expect(
      decidir(req({ context: { date: new Date("2026-02-01T10:00:00Z"), cycleId: "c1" } }), providers).allowed
    ).toBe(true);
    expect(
      decidir(req({ context: { date: new Date("2026-02-01T13:00:00Z"), cycleId: "c1" } }), providers).allowed
    ).toBe(false);
  });

  it("45. membership inválido ⇒ grant não autoriza (sem fallback/job)", () => {
    const providers = makeProviders({
      identity: { isProfileActive: () => true, isMembershipActive: () => false },
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    expect(decidir(req(), providers).denial?.reason).toBe("MEMBERSHIP_INVALID");
  });
});

describe("F4-06 — listAllowedTargets (D18) e ausência de cargo", () => {
  it("46. C NÃO participa de listAllowedTargets", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    const candidatos: TargetRef[] = [EVAL_1, EVAL_2];
    // A/B negam tudo; a origem C (stripped na listagem) não adiciona targets.
    const listados = listAllowedTargets(
      {
        actor: { actorId: "ben1", organizationId: ORG },
        capability: "evaluation.read",
        context: { date: D, cycleId: "c1" },
        domainState: semprePermite,
      },
      providers,
      candidatos
    );
    expect(listados).toEqual([]);
    // authorize continua sendo a decisão real: C autoriza eval-1 pontualmente.
    expect(decidir(req({ target: EVAL_1 }), providers).allowed).toBe(true);
    expect(() => authorize(req({ target: EVAL_2 }), providers)).toThrow(ForbiddenError);
  });

  it("47. caminho C não consulta cargo/job_role (comportamental)", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    expect(decidir(req(), providers).allowed).toBe(true);
    // superfície do módulo não expõe símbolo de cargo/função/job.
    const exported = Object.keys(exceptionalModule);
    expect(exported.some((k) => /cargo|funcao|job/i.test(k))).toBe(false);
    expect(EXCEPTIONAL_CAPABILITIES.includes("exceptional_access.grant")).toBe(false);
  });

  it("48. can() devolve decisão estruturada sem lançar para DENY da origem C", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant({ validTo: new Date("2026-01-15T00:00:00Z") })] }),
    });
    expect(() => can(req(), providers)).not.toThrow();
    expect(can(req(), providers).allowed).toBe(false);
  });
});

describe("F4-06 — D10 fail-closed de cycleId no ExceptionalProvider", () => {
  function providerDireto(grants: ExceptionalGrant[]) {
    return createExceptionalProvider({
      organizationId: ORG,
      grants,
      isTargetConfidential: () => true,
    });
  }

  it("49. grant evaluation sem cycleId + request sem cycleId ⇒ NÃO aplicável", () => {
    const p = providerDireto([grant({ cycleId: undefined })]);
    expect(
      p.resolveExceptionalGrants("ben1", ORG, "evaluation.read", EVAL_1, D, undefined)
    ).toEqual([]);
  });

  it("50. grant evaluation sem cycleId + request com cycleId ⇒ NÃO aplicável", () => {
    const p = providerDireto([grant({ cycleId: undefined })]);
    expect(
      p.resolveExceptionalGrants("ben1", ORG, "evaluation.read", EVAL_1, D, "c1")
    ).toEqual([]);
  });

  it("51. grant evaluation com cycleId + request sem cycleId ⇒ NÃO aplicável", () => {
    const p = providerDireto([grant({ cycleId: "c1" })]);
    expect(
      p.resolveExceptionalGrants("ben1", ORG, "evaluation.read", EVAL_1, D, undefined)
    ).toEqual([]);
  });

  it("52. grant evaluation com cycleId diferente ⇒ NÃO aplicável", () => {
    const p = providerDireto([grant({ cycleId: "c1" })]);
    expect(
      p.resolveExceptionalGrants("ben1", ORG, "evaluation.read", EVAL_1, D, "c2")
    ).toEqual([]);
  });

  it("53. grant evaluation com cycleId exatamente igual ⇒ aplicável", () => {
    const p = providerDireto([grant({ cycleId: "c1" })]);
    expect(
      p.resolveExceptionalGrants("ben1", ORG, "evaluation.read", EVAL_1, D, "c1")
    ).toEqual([grant({ cycleId: "c1" })]);
  });

  it("54. engine: ciclo exato autoriza; ausente/diferente negam (fail-closed)", () => {
    const providers = makeProviders({
      exceptional: makeExceptional({ grants: [grant()] }),
    });
    expect(decidir(req({ context: { date: D, cycleId: "c1" } }), providers).allowed).toBe(true);
    expect(decidir(req({ context: { date: D } }), providers).allowed).toBe(false);
    expect(decidir(req({ context: { date: D, cycleId: "c2" } }), providers).allowed).toBe(false);
  });
});
