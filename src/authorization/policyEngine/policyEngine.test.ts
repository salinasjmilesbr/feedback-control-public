import { describe, expect, it } from "vitest";
import {
  ConflictError,
  ForbiddenError,
  NotFoundError,
} from "../../errors/applicationErrors";
import { criarProvidersMundoLocal } from "../providers/localWorld";
import type { Colaborador } from "../../types/Colaborador";
import type {
  AuthorizationRequest,
  PolicyEngineProviders,
  TargetRef,
} from "./types";
import * as policyEngineModule from "./policyEngine";
import { authorize, can, listAllowedTargets } from "./policyEngine";
import { LEGACY_AUTHORIZATION_MAP } from "./legacyMap";

const ORG = "org-a";
const OTHER_ORG = "org-b";

function baseRequest(overrides: Partial<AuthorizationRequest> = {}): AuthorizationRequest {
  return {
    actor: { actorId: "1", organizationId: ORG },
    capability: "goal.write",
    target: { type: "collaborator", id: "1" },
    context: { date: new Date("2026-01-01T00:00:00Z") },
    domainState: { allows: () => true },
    ...overrides,
  };
}

function makeProviders(overrides: Partial<PolicyEngineProviders> = {}): PolicyEngineProviders {
  return {
    identity: {
      isProfileActive: () => true,
      isMembershipActive: () => true,
    },
    capabilities: { hasCapability: () => true },
    scopes: { getActiveScopes: () => ["SELF"] },
    targets: { resolveTargetTenant: (t: TargetRef) => (t.id === "missing" ? undefined : ORG) },
    relations: {
      isTargetInScope: (_a, _o, scope, target: TargetRef) =>
        scope === "SELF" && target.type === "collaborator" && target.id === "1",
    },
    ...overrides,
  };
}

describe("policyEngine — matriz positiva/negativa", () => {
  it("capability + scope + relação + estado válidos => ALLOW", () => {
    expect(can(baseRequest(), makeProviders()).allowed).toBe(true);
  });

  it("capability sem scope => DENY (SCOPE_INSUFFICIENT)", () => {
    const decision = can(
      baseRequest(),
      makeProviders({ scopes: { getActiveScopes: () => [] } })
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("scope sem capability => DENY (CAPABILITY_MISSING)", () => {
    const decision = can(
      baseRequest(),
      makeProviders({ capabilities: { hasCapability: () => false } })
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("estado inválido com capability+scope válidos => DENY (DOMAIN_STATE_INVALID)", () => {
    const decision = can(
      baseRequest({ domainState: { allows: () => false } }),
      makeProviders()
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("DOMAIN_STATE_INVALID");
    expect(decision.denial?.publicCode).toBe("CONFLICT");
  });

  it("cross-tenant => DENY com público NOT_FOUND", () => {
    const decision = can(
      baseRequest(),
      makeProviders({ targets: { resolveTargetTenant: () => OTHER_ORG } })
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("CROSS_TENANT");
    expect(decision.denial?.publicCode).toBe("NOT_FOUND");
  });

  it("membership disabled => DENY (MEMBERSHIP_INVALID)", () => {
    const decision = can(
      baseRequest(),
      makeProviders({ identity: { isProfileActive: () => true, isMembershipActive: () => false } })
    );
    expect(decision.denial?.reason).toBe("MEMBERSHIP_INVALID");
  });

  it("profile disabled => DENY (PROFILE_DISABLED)", () => {
    const decision = can(
      baseRequest(),
      makeProviders({ identity: { isProfileActive: () => false, isMembershipActive: () => true } })
    );
    expect(decision.denial?.reason).toBe("PROFILE_DISABLED");
  });

  it("SELF sobre terceiro => DENY (SCOPE_INSUFFICIENT)", () => {
    const decision = can(
      baseRequest({ target: { type: "collaborator", id: "2" } }),
      makeProviders()
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("DESCENDANTS fora da árvore => DENY (SCOPE_INSUFFICIENT)", () => {
    const decision = can(
      baseRequest({ target: { type: "collaborator", id: "2" } }),
      makeProviders({
        scopes: { getActiveScopes: () => ["DESCENDANTS"] },
        relations: { isTargetInScope: () => false },
      })
    );
    expect(decision.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("ORGANIZATION sem capability => DENY (CAPABILITY_MISSING)", () => {
    const decision = can(
      baseRequest(),
      makeProviders({
        scopes: { getActiveScopes: () => ["ORGANIZATION"] },
        capabilities: { hasCapability: () => false },
      })
    );
    expect(decision.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("ADMIN sem capability confidencial => DENY (CAPABILITY_MISSING)", () => {
    const decision = can(
      baseRequest({ capability: "report.view" }),
      makeProviders({
        scopes: { getActiveScopes: () => ["ORGANIZATION"] },
        capabilities: {
          hasCapability: (_a, _o, cap) => cap !== "report.view",
        },
      })
    );
    expect(decision.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("múltiplas positions produzem união correta (alvo em qualquer posição => ALLOW)", () => {
    const providers = makeProviders({
      scopes: { getActiveScopes: () => ["DESCENDANTS"] },
      relations: {
        isTargetInScope: (_a, _o, scope, target) =>
          scope === "DESCENDANTS" &&
          target.type === "collaborator" &&
          ["2", "3"].includes(target.id),
      },
    });
    expect(can(baseRequest({ target: { type: "collaborator", id: "2" } }), providers).allowed).toBe(true);
    expect(can(baseRequest({ target: { type: "collaborator", id: "3" } }), providers).allowed).toBe(true);
    expect(can(baseRequest({ target: { type: "collaborator", id: "9" } }), providers).allowed).toBe(false);
  });

  it("contexto temporal/histórico é usado pela relação (data repassada ao provedor)", () => {
    const datas: Date[] = [];
    const providers = makeProviders({
      relations: {
        isTargetInScope: (_a, _o, _s, _t, date) => {
          datas.push(date);
          return true;
        },
      },
    });
    const data = new Date("2024-03-01T00:00:00Z");
    can(baseRequest({ context: { date: data } }), providers);
    expect(datas[0]).toEqual(data);
  });

  it("ASSIGNED sem resolução => DENY (SCOPE_INSUFFICIENT — fail-closed)", () => {
    const decision = can(
      baseRequest(),
      makeProviders({
        scopes: { getActiveScopes: () => ["ASSIGNED"] },
        relations: { isTargetInScope: () => false },
      })
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("estado do domínio ausente => DENY (INDETERMINATE — fail-closed)", () => {
    const decision = can(
      baseRequest({ domainState: undefined }),
      makeProviders()
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("INDETERMINATE");
  });

  it("tenant do alvo é derivado do provider (não do request)", () => {
    // O TargetRef não carrega tenant; o provider é a única fonte do tenant do alvo.
    const decision = can(
      baseRequest({ target: { type: "collaborator", id: "1" } }),
      makeProviders({ targets: { resolveTargetTenant: () => OTHER_ORG } })
    );
    expect(decision.denial?.reason).toBe("CROSS_TENANT");
  });
});

describe("policyEngine — API (can / authorize / listAllowedTargets)", () => {
  it("can devolve decisão estruturada sem lançar", () => {
    expect(() =>
      can(baseRequest(), makeProviders({ capabilities: { hasCapability: () => false } }))
    ).not.toThrow();
  });

  it("authorize lança erro público F0-05 coerente com a razão", () => {
    expect(() =>
      authorize(baseRequest(), makeProviders({ capabilities: { hasCapability: () => false } }))
    ).toThrow(ForbiddenError);
    expect(() =>
      authorize(baseRequest(), makeProviders({ targets: { resolveTargetTenant: () => OTHER_ORG } }))
    ).toThrow(NotFoundError);
    expect(() =>
      authorize(baseRequest({ domainState: { allows: () => false } }), makeProviders())
    ).toThrow(ConflictError);
  });

  it("listAllowedTargets é auxiliar (filtra), nunca substituto de authorize()", () => {
    const providers = makeProviders();
    const alvos: TargetRef[] = [
      { type: "collaborator", id: "1" },
      { type: "collaborator", id: "2" },
    ];
    const permitidos = listAllowedTargets(
      {
        actor: { actorId: "1", organizationId: ORG },
        capability: "goal.write",
        context: { date: new Date() },
        domainState: { allows: () => true },
      },
      providers,
      alvos
    );
    expect(permitidos).toEqual([{ type: "collaborator", id: "1" }]);
    // "Estar na lista" não autoriza: authorize ainda nega o alvo fora do scope.
    expect(() =>
      authorize(baseRequest({ target: { type: "collaborator", id: "2" } }), providers)
    ).toThrow(ForbiddenError);
  });
});

describe("policyEngine — fluxo-piloto (mundo local, sem cargo)", () => {
  function pessoa(matricula: number, funcao?: Colaborador["funcao"]): Colaborador {
    return {
      matricula,
      status: "ATIVO",
      nome: `Pessoa ${matricula}`,
      email: `${matricula}@example.com`,
      cargo: funcao ?? "Analista",
      area: "Teste",
      funcao,
      respondePara: "",
    };
  }

  it("GERENTE também gerencia metas próprias (decisão não consulta cargo)", () => {
    const gerente = pessoa(1, "GERENTE");
    const providers = criarProvidersMundoLocal(gerente, [gerente]);
    expect(
      can(
        {
          actor: { actorId: "1", organizationId: "organizacao-sintetica-local" },
          capability: "goal.write",
          target: { type: "collaborator", id: "1" },
          context: { date: new Date() },
          domainState: { allows: () => true },
        },
        providers
      ).allowed
    ).toBe(true);
  });

  it("SELF sobre outro colaborador é negado (mundo local)", () => {
    const gerente = pessoa(1, "GERENTE");
    const outro = pessoa(2, "ANALISTA");
    const providers = criarProvidersMundoLocal(gerente, [gerente, outro]);
    const decision = can(
      {
        actor: { actorId: "1", organizationId: "organizacao-sintetica-local" },
        capability: "goal.write",
        target: { type: "collaborator", id: "2" },
        context: { date: new Date() },
        domainState: { allows: () => true },
      },
      providers
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });
});

describe("policyEngine — testes de fronteira", () => {
  it("engine não exporta o mapa legado (não é consultado em runtime)", () => {
    // Superfície pública do engine é apenas decisão/listagem; o mapa legado
    // vive em módulo separado (legacyMap) e nunca é importado/exportado aqui.
    const exported = Object.keys(policyEngineModule);
    expect(exported).not.toContain("legacyMap");
    expect(exported).not.toContain("LEGACY_AUTHORIZATION_MAP");
  });

  it("engine não consulta cargo/job_role (comportamental)", () => {
    // A decisão é a mesma para qualquer cargo: o request não carrega cargo e
    // os providers não recebem funcao. Gerente e Analista, com os mesmos
    // providers locais, resolvem igualmente o fluxo próprio (SELF).
    const gerente: Colaborador = {
      matricula: 1,
      status: "ATIVO",
      nome: "Pessoa Gerente",
      email: "1@example.com",
      cargo: "Gerente",
      area: "Teste",
      funcao: "GERENTE",
      respondePara: "",
    };
    const analista: Colaborador = {
      ...gerente,
      cargo: "Analista",
      funcao: "ANALISTA",
    };
    const req = (actorId: string) => ({
      actor: { actorId, organizationId: "organizacao-sintetica-local" },
      capability: "goal.write" as const,
      target: { type: "collaborator" as const, id: "1" },
      context: { date: new Date() },
      domainState: { allows: () => true },
    });
    expect(
      can(req("1"), criarProvidersMundoLocal(gerente, [gerente])).allowed
    ).toBe(true);
    expect(
      can(req("1"), criarProvidersMundoLocal(analista, [analista])).allowed
    ).toBe(true);
  });

  it("o mapa legado existe apenas como artefato documental", () => {
    expect(LEGACY_AUTHORIZATION_MAP.length).toBeGreaterThan(0);
    expect(
      LEGACY_AUTHORIZATION_MAP.filter(
        (m) => m.capability === "goal.write" && m.scope === "SELF"
      ).length
    ).toBeGreaterThanOrEqual(5);
  });
});
