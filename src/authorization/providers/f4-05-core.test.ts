import { describe, expect, it } from "vitest";
import { ForbiddenError } from "../../errors/applicationErrors";
import { decidir, listAllowedTargets, authorize } from "../policyEngine/policyEngine";
import type {
  PolicyEngineProviders,
  ResponsibilityType,
  TargetRef,
} from "../policyEngine/types";
import {
  createTemporaryProvider,
  getActiveTemporaryResponsibilities,
  getEligibleTemporaryCapabilities,
  TEMPORARY_RESPONSIBILITY_CAPABILITIES,
} from "./temporary";
import type { TemporaryResponsibility } from "./temporary";
import { resolveDirectReports } from "./structure";
import type { Occupant, PositionEdge } from "./structure";
import { createStructuralRelationProvider } from "./structuralRelation";
import * as temporaryModule from "./temporary";

const ORG = "org-a";
const OTHER = "org-b";

// Data de contexto: dentro da vigência [2026-01-01, 2026-03-01).
const D = new Date("2026-02-01T00:00:00Z");

// ---------------------------------------------------------------------------
// Estrutura F3-shaped (sem cargo): árvore de positions + reporting lines.
// p1 é a posição substituída (resposta operacional/avaliativa); p4 é a posição
// PRÓPRIA do substituto (occupation normal, independente da substitution).
// ---------------------------------------------------------------------------
const positions: PositionEdge[] = [
  { positionId: "p0", organizationId: ORG, managerPositionId: null },
  { positionId: "p1", organizationId: ORG, managerPositionId: "p0" }, // substituída
  { positionId: "p2", organizationId: ORG, managerPositionId: "p1" }, // avaliada
  { positionId: "p3", organizationId: ORG, managerPositionId: "p1" }, // avaliada
  { positionId: "p6", organizationId: ORG, managerPositionId: "p1" }, // vaga intermediária
  { positionId: "p7", organizationId: ORG, managerPositionId: "p6" }, // abaixo da vaga
  { positionId: "p4", organizationId: ORG, managerPositionId: "p0" }, // própria do substituto
  { positionId: "p5", organizationId: ORG, managerPositionId: "p4" },
  { positionId: "p8", organizationId: ORG, managerPositionId: "p0" }, // 2ª posição substituída
  { positionId: "p9", organizationId: ORG, managerPositionId: "p8" },
];

const occupants: Occupant[] = [
  { positionId: "p0", collaboratorId: "c_dir" },
  { positionId: "p1", collaboratorId: "c_titular" },
  { positionId: "p2", collaboratorId: "c_an1" },
  { positionId: "p3", collaboratorId: "c_an2" },
  { positionId: "p6", collaboratorId: null }, // vaga
  { positionId: "p7", collaboratorId: "c_deep" },
  { positionId: "p4", collaboratorId: "c_sub" }, // occupation própria do substituto
  { positionId: "p5", collaboratorId: "c_other" },
  { positionId: "p8", collaboratorId: "c_titular2" },
  { positionId: "p9", collaboratorId: "c_y" },
];

const respOperational: TemporaryResponsibility = {
  id: "r1",
  organizationId: ORG,
  organizationalPositionId: "p1",
  substituteCollaboratorId: "c_sub",
  responsibilityType: "operational",
  validFrom: new Date("2026-01-01T00:00:00Z"),
  validTo: new Date("2026-03-01T00:00:00Z"),
};

const respSecond: TemporaryResponsibility = {
  id: "r2",
  organizationId: ORG,
  organizationalPositionId: "p8",
  substituteCollaboratorId: "c_sub",
  responsibilityType: "operational",
  validFrom: new Date("2026-01-01T00:00:00Z"),
  validTo: new Date("2026-03-01T00:00:00Z"),
};

const respEvaluative: TemporaryResponsibility = {
  id: "rE",
  organizationId: ORG,
  organizationalPositionId: "p1",
  substituteCollaboratorId: "c_sub",
  responsibilityType: "evaluative",
  validFrom: new Date("2026-01-01T00:00:00Z"),
  validTo: new Date("2026-03-01T00:00:00Z"),
};

// Posição ocupada por cada avaliado (para o alvo avaliativo).
const positionPorAvaliado: Record<string, string> = {
  c_an1: "p2",
  c_an2: "p3",
  c_y: "p9",
  c_other: "p5",
};

const resolveEvaluationTarget = (
  t: TargetRef,
  cycleId: string | undefined,
  org: string
) => {
  if (!cycleId || (t.type !== "collaborator" && t.type !== "evaluation")) {
    return undefined;
  }
  const positionId = positionPorAvaliado[t.id];
  return positionId
    ? { cycleId, organizationId: org, evaluatedCollaboratorId: t.id, positionId }
    : undefined;
};

function makeTemporary(
  responsibilities: readonly TemporaryResponsibility[],
  isEvaluationFrozen: (() => boolean | undefined) = () => false
) {
  return createTemporaryProvider({
    organizationId: ORG,
    responsibilities,
    positions,
    occupants,
    resolveEvaluationTarget,
    isEvaluationFrozen: () => isEvaluationFrozen(),
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
  capability: Parameters<typeof decidir>[0]["capability"],
  targetId: string,
  overrides: Partial<Parameters<typeof decidir>[0]> = {}
): Parameters<typeof decidir>[0] {
  return {
    actor: { actorId: "c_sub", organizationId: ORG },
    capability,
    target: { type: "collaborator", id: targetId },
    context: { date: D, cycleId: "c1" },
    domainState: { allows: () => true },
    ...overrides,
  };
}

describe("F4-05 — vigência (por data, sem cache)", () => {
  it("1. substituição vigente concede capability permitida", () => {
    const providers = makeProviders({
      temporary: makeTemporary([respOperational]),
    });
    const decision = decidir(req("goal.approve", "c_an1"), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.temporaryOrigins).toEqual(["temporary:r1"]);
  });

  it("2. substituição futura = DENY", () => {
    const futura: TemporaryResponsibility = {
      ...respOperational,
      validFrom: new Date("2026-04-01T00:00:00Z"),
      validTo: new Date("2026-05-01T00:00:00Z"),
    };
    const providers = makeProviders({ temporary: makeTemporary([futura]) });
    const decision = decidir(req("goal.approve", "c_an1"), providers);
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("3. substituição expirada = DENY", () => {
    const expirada: TemporaryResponsibility = {
      ...respOperational,
      validFrom: new Date("2025-01-01T00:00:00Z"),
      validTo: new Date("2026-01-15T00:00:00Z"),
    };
    const providers = makeProviders({ temporary: makeTemporary([expirada]) });
    const decision = decidir(req("goal.approve", "c_an1"), providers);
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("4. retorno antecipado (valid_to atualizado) reflete imediatamente", () => {
    // Mesmo provider re-lê a responsabilidade: encerrar o período antes da data
    // corrente remove o grant na hora (sem cache/estado copiado).
    const encerrada: TemporaryResponsibility = {
      ...respOperational,
      validTo: new Date("2026-01-15T00:00:00Z"),
    };
    const providers = makeProviders({ temporary: makeTemporary([encerrada]) });
    expect(decidir(req("goal.approve", "c_an1"), providers).allowed).toBe(false);
  });

  it("atividade por data respeita [valid_from, valid_to)", () => {
    const active = getActiveTemporaryResponsibilities("c_sub", ORG, D, [
      respOperational,
      { ...respOperational, id: "rX", validTo: D }, // fim exato = fora (meio-aberto)
      { ...respOperational, id: "rY", validFrom: new Date("2026-02-01T00:00:00Z") }, // início exato = dentro
    ]);
    expect(active.map((r) => r.id)).toEqual(["r1", "rY"]);
  });
});

describe("F4-05 — contrato responsibility_type × capability (fechado)", () => {
  it("5. responsibility_type incompatível com a capability = DENY", () => {
    // operational não concede evaluation.write (avaliative).
    const providers = makeProviders({ temporary: makeTemporary([respOperational]) });
    const decision = decidir(req("evaluation.write", "c_an1"), providers);
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("6. substituto não herda capability não prevista (goal.write próprio)", () => {
    const providers = makeProviders({ temporary: makeTemporary([respOperational]) });
    const decision = decidir(req("goal.write", "c_an1"), providers);
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("7. substituto não herda scopes/capabilities do titular", () => {
    // O titular possui evaluation.view.admin na membership; o substituto não
    // herda nada disso (nem via membership, nem via temporary).
    const providers = makeProviders({
      capabilities: {
        hasCapability: (actorId, _org, cap) =>
          actorId === "c_titular" && cap === "evaluation.view.admin",
      },
      scopes: { getActiveScopes: () => ["ORGANIZATION"] },
      relations: { isTargetInScope: (_a, _o, s) => s === "ORGANIZATION" },
      temporary: makeTemporary([respOperational]),
    });
    const titular = decidir(
      req("evaluation.view.admin", "c_an1", {
        actor: { actorId: "c_titular", organizationId: ORG },
      }),
      providers
    );
    expect(titular.allowed).toBe(true);

    const substituto = decidir(req("evaluation.view.admin", "c_an1"), providers);
    expect(substituto.allowed).toBe(false);
    expect(substituto.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("allowlist fechada: operational = 7 capabilities (DESCENDANTS)", () => {
    const rules = TEMPORARY_RESPONSIBILITY_CAPABILITIES.operational;
    expect(rules.map((r) => r.capability).sort()).toEqual(
      [
        "collaborator.list",
        "goal.approve",
        "goal.view.admin",
        "observation.create",
        "observation.delete",
        "observation.edit",
        "report.view",
      ].sort()
    );
    expect(rules.every((r) => r.scope === "DESCENDANTS")).toBe(true);
  });

  it("allowlist fechada: evaluative = 3 capabilities (ASSIGNED)", () => {
    const rules = TEMPORARY_RESPONSIBILITY_CAPABILITIES.evaluative;
    expect(rules.map((r) => r.capability).sort()).toEqual(
      ["evaluation.create", "evaluation.read", "evaluation.write"].sort()
    );
    expect(rules.every((r) => r.scope === "ASSIGNED")).toBe(true);
  });

  it("operational_evaluative = união dos dois conjuntos", () => {
    const rules = TEMPORARY_RESPONSIBILITY_CAPABILITIES.operational_evaluative;
    const caps = rules.map((r) => `${r.capability}:${r.scope}`).sort();
    expect(caps).toEqual(
      [
        ...TEMPORARY_RESPONSIBILITY_CAPABILITIES.operational,
        ...TEMPORARY_RESPONSIBILITY_CAPABILITIES.evaluative,
      ]
        .map((r) => `${r.capability}:${r.scope}`)
        .sort()
    );
  });

  it("23. tipo desconhecido = DENY (sem capabilities)", () => {
    const desconhecido: TemporaryResponsibility = {
      ...respOperational,
      responsibilityType: "desconhecido" as ResponsibilityType,
    };
    expect(
      getEligibleTemporaryCapabilities("c_sub", ORG, D, [desconhecido])
    ).toEqual([]);
    const providers = makeProviders({ temporary: makeTemporary([desconhecido]) });
    expect(decidir(req("goal.approve", "c_an1"), providers).allowed).toBe(false);
  });
});

describe("F4-05 — titular × substituto e exclusividade", () => {
  function providersComTitular(): PolicyEngineProviders {
    const membershipRelations = createStructuralRelationProvider({
      organizationId: ORG,
      resolveActorPositions: (actorId) => (actorId === "c_titular" ? ["p1"] : []),
      positions,
      occupants,
      collegiateMemberships: [],
      evaluationResponsibilities: [],
      resolveEvaluationTarget,
    });
    return makeProviders({
      capabilities: {
        hasCapability: (actorId, _org, cap) =>
          actorId === "c_titular" && cap === "goal.approve",
      },
      scopes: { getActiveScopes: () => ["DESCENDANTS"] },
      relations: membershipRelations,
      temporary: makeTemporary([respOperational]),
    });
  }

  it("8. titular mantém autorização própria durante a substituição", () => {
    const providers = providersComTitular();
    const titular = decidir(
      req("goal.approve", "c_an1", {
        actor: { actorId: "c_titular", organizationId: ORG },
      }),
      providers
    );
    expect(titular.allowed).toBe(true);
    // o substituto também permanece autorizado, simultaneamente.
    const substituto = decidir(req("goal.approve", "c_an1"), providers);
    expect(substituto.allowed).toBe(true);
    expect(substituto.diagnostics?.temporaryOrigins).toEqual(["temporary:r1"]);
  });

  it("9. exclusividade NÃO é decidida genericamente pelo engine (é domínio)", () => {
    const providers = providersComTitular();

    // Ambos autorizados: o engine não arbitra "titular vs substituto".
    expect(
      decidir(
        req("goal.approve", "c_an1", {
          actor: { actorId: "c_titular", organizationId: ORG },
        }),
        providers
      ).allowed
    ).toBe(true);
    expect(decidir(req("goal.approve", "c_an1"), providers).allowed).toBe(true);

    // Exclusividade é expressa pelo estado do domínio (probe), não pelo engine.
    const exclusivo = { allows: () => false };
    const titularNegado = decidir(
      req("goal.approve", "c_an1", {
        actor: { actorId: "c_titular", organizationId: ORG },
        domainState: exclusivo,
      }),
      providers
    );
    const substitutoNegado = decidir(
      req("goal.approve", "c_an1", { domainState: exclusivo }),
      providers
    );
    expect(titularNegado.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    expect(substitutoNegado.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });
});

describe("F4-05 — raiz do grant temporário (position substituída)", () => {
  it("11. DIRECT_REPORTS da position substituída (mecanismo)", () => {
    const direct = resolveDirectReports(["p1"], positions, occupants, ORG);
    expect([...direct.positionIds].sort()).toEqual(["p2", "p3", "p6"]);
    expect([...direct.collaboratorIds].sort()).toEqual(["c_an1", "c_an2"]);
  });

  it("12. DESCENDANTS correto pela position substituída", () => {
    const providers = makeProviders({ temporary: makeTemporary([respOperational]) });
    expect(decidir(req("goal.approve", "c_an1"), providers).allowed).toBe(true);
    expect(decidir(req("goal.approve", "c_an2"), providers).allowed).toBe(true);
    // c_other está sob p4 (position própria do substituto), fora de p1.
    expect(decidir(req("goal.approve", "c_other"), providers).allowed).toBe(false);
  });

  it("13. posição vaga intermediária não quebra descendants", () => {
    const providers = makeProviders({ temporary: makeTemporary([respOperational]) });
    expect(decidir(req("goal.approve", "c_deep"), providers).allowed).toBe(true);
  });

  it("10/14. occupations próprias do substituto NÃO ampliam o grant temporário", () => {
    const providers = makeProviders({ temporary: makeTemporary([respOperational]) });
    // c_sub ocupa p4 normalmente; o grant temporário enraíza em p1 (substituída),
    // nunca em p4. Logo c_other (sob p4) NÃO é alcançado pela substitution.
    const decision = decidir(req("goal.approve", "c_other"), providers);
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });
});

describe("F4-05 — autorizações próprias × temporárias (independentes)", () => {
  function providersComProprios(): PolicyEngineProviders {
    const membershipRelations = createStructuralRelationProvider({
      organizationId: ORG,
      resolveActorPositions: (actorId) => (actorId === "c_sub" ? ["p4"] : []),
      positions,
      occupants,
      collegiateMemberships: [],
      evaluationResponsibilities: [],
      resolveEvaluationTarget,
    });
    return makeProviders({
      capabilities: {
        hasCapability: (actorId, _org, cap) =>
          actorId === "c_sub" && cap === "goal.approve",
      },
      scopes: { getActiveScopes: () => ["DESCENDANTS"] },
      relations: membershipRelations,
      temporary: makeTemporary([respOperational]),
    });
  }

  it("15. autorizações próprias continuam válidas e independentes", () => {
    const providers = providersComProprios();
    // Próprio grant (DESCENDANTS de p4) cobre c_other.
    const proprio = decidir(req("goal.approve", "c_other"), providers);
    expect(proprio.allowed).toBe(true);
    expect(proprio.diagnostics?.matchedScope).toBe("DESCENDANTS");

    // Grant temporário (DESCENDANTS de p1) cobre c_an1.
    const temporario = decidir(req("goal.approve", "c_an1"), providers);
    expect(temporario.allowed).toBe(true);
    expect(temporario.diagnostics?.temporaryOrigins).toEqual(["temporary:r1"]);
  });

  it("16. múltiplas origens válidas produzem união deduplicada (origem preservada)", () => {
    const providers = providersComProprios();
    // Mesmo alvo coberto por ambas as origens: decisão única ALLOW, sem duplicar.
    const decision = decidir(req("goal.approve", "c_an1"), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.temporaryOrigins).toEqual(["temporary:r1"]);
    // A origem temporária não é duplicada e convive com a membership.
    expect(decision.diagnostics?.temporaryOrigins?.length).toBe(1);
  });

  it("17. múltiplas substituições em positions diferentes funcionam corretamente", () => {
    const providers = makeProviders({
      temporary: makeTemporary([respOperational, respSecond]),
    });
    expect(decidir(req("goal.approve", "c_an1"), providers).allowed).toBe(true);
    expect(decidir(req("goal.approve", "c_y"), providers).allowed).toBe(true);
    expect(decidir(req("goal.approve", "c_other"), providers).allowed).toBe(false);
  });

  it("18/19. caller não escolhe position nem responsibility convenientes", () => {
    const providers = makeProviders({
      temporary: makeTemporary([respOperational, respSecond]),
    });
    // O request não tem campo de position/responsibility; a raiz é derivada dos
    // dados. c_an1 só é alcançável por r1 (p1), nunca "escolhendo" p4/p8.
    const viaResp1 = decidir(req("goal.approve", "c_an1"), providers);
    expect(viaResp1.diagnostics?.temporaryOrigins).toEqual(["temporary:r1"]);

    const viaResp2 = decidir(req("goal.approve", "c_y"), providers);
    expect(viaResp2.diagnostics?.temporaryOrigins).toEqual(["temporary:r2"]);

    // A position própria do substituto (p4) não autoriza c_other via temporary.
    expect(decidir(req("goal.approve", "c_other"), providers).allowed).toBe(false);
  });
});

describe("F4-05 — ASSIGNED avaliativo e fronteira vivo × congelado", () => {
  function evaluativeProviders(
    isEvaluationFrozen: () => boolean | undefined
  ): PolicyEngineProviders {
    return makeProviders({
      temporary: makeTemporary([respEvaluative], isEvaluationFrozen),
    });
  }

  it("25. evaluative temporária funciona em contexto vivo compatível", () => {
    const providers = evaluativeProviders(() => false);
    const decision = decidir(req("evaluation.write", "c_an1"), providers);
    expect(decision.allowed).toBe(true);
    expect(decision.diagnostics?.temporaryOrigins).toEqual(["temporary:rE"]);
  });

  it("26. contexto congelado F3-08/F3-09 não é sobrescrito por temporary", () => {
    const providers = evaluativeProviders(() => true);
    const decision = decidir(req("evaluation.write", "c_an1"), providers);
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("27. ausência de informação vivo × congelado = DENY", () => {
    const providers = evaluativeProviders(() => undefined);
    const decision = decidir(req("evaluation.write", "c_an1"), providers);
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("28. ASSIGNED temporário não vira wildcard (correlação específica)", () => {
    const providers = evaluativeProviders(() => false);
    // c_an1 e c_an2 estão sob p1 (substituída) → autorizados.
    expect(decidir(req("evaluation.write", "c_an1"), providers).allowed).toBe(true);
    expect(decidir(req("evaluation.write", "c_an2"), providers).allowed).toBe(true);
    // c_y está sob p8 (não substituída) e c_other sob p4 → negados.
    expect(decidir(req("evaluation.write", "c_y"), providers).allowed).toBe(false);
    expect(decidir(req("evaluation.write", "c_other"), providers).allowed).toBe(false);
  });
});

describe("F4-05 — tenant, identidade e fail-closed", () => {
  it("20. cross-tenant = DENY", () => {
    const responsabilidadeOutraOrg: TemporaryResponsibility = {
      ...respOperational,
      organizationId: OTHER,
    };
    const providers = makeProviders({
      temporary: makeTemporary([responsabilidadeOutraOrg]),
    });
    // Responsabilidade de outra organização não gera grant no tenant do ator.
    expect(decidir(req("goal.approve", "c_an1"), providers).allowed).toBe(false);
    // Alvo de outro tenant também é negado (passo 4 do engine).
    const alvoCross = decidir(req("goal.approve", "cross"), providers);
    expect(alvoCross.denial?.reason).toBe("CROSS_TENANT");
  });

  it("21. membership disabled = DENY (mesmo com substitution vigente)", () => {
    const providers = makeProviders({
      identity: { isProfileActive: () => true, isMembershipActive: () => false },
      temporary: makeTemporary([respOperational]),
    });
    expect(decidir(req("goal.approve", "c_an1"), providers).denial?.reason).toBe(
      "MEMBERSHIP_INVALID"
    );
  });

  it("22. profile disabled = DENY (mesmo com substitution vigente)", () => {
    const providers = makeProviders({
      identity: { isProfileActive: () => false, isMembershipActive: () => true },
      temporary: makeTemporary([respOperational]),
    });
    expect(decidir(req("goal.approve", "c_an1"), providers).denial?.reason).toBe(
      "PROFILE_DISABLED"
    );
  });

  it("24. capability × target incompatível = DENY (TARGET_INCOMPATIBLE)", () => {
    const providers = makeProviders({ temporary: makeTemporary([respOperational]) });
    const decision = decidir(
      req("goal.approve", "c_an1", { target: { type: "cycle", id: "c1" } }),
      providers
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("TARGET_INCOMPATIBLE");
  });
});

describe("F4-05 — listAllowedTargets e ausência de cargo", () => {
  it("29. listAllowedTargets é auxiliar e nunca substitui authorize()", () => {
    const providers = makeProviders({ temporary: makeTemporary([respOperational]) });
    const candidatos: TargetRef[] = [
      { type: "collaborator", id: "c_an1" },
      { type: "collaborator", id: "c_other" },
    ];
    const permitidos = listAllowedTargets(
      {
        actor: { actorId: "c_sub", organizationId: ORG },
        capability: "goal.approve",
        context: { date: D, cycleId: "c1" },
        domainState: { allows: () => true },
      },
      providers,
      candidatos
    );
    expect(permitidos).toEqual([{ type: "collaborator", id: "c_an1" }]);
    // "Estar na lista" não autoriza: authorize nega o alvo fora do alcance.
    expect(() =>
      authorize(req("goal.approve", "c_other"), providers)
    ).toThrow(ForbiddenError);
  });

  it("30. a autorização temporária não consulta cargo/job_role (comportamental)", () => {
    // O request e o TemporaryProvider não possuem campo de cargo/função; a
    // decisão é idêntica para qualquer ator com as mesmas responsabilidades.
    const providers = makeProviders({ temporary: makeTemporary([respOperational]) });
    const decision = decidir(req("goal.approve", "c_an1"), providers);
    expect(decision.allowed).toBe(true);

    // A superfície do módulo temporário não expõe símbolo de cargo/função.
    const exported = Object.keys(temporaryModule);
    expect(exported.some((k) => /cargo|funcao|job/i.test(k))).toBe(false);
  });
});
