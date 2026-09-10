import { describe, expect, it, vi } from "vitest";
import type { AuthIdentity } from "../auth/tipos";
import { ForbiddenError, NotFoundError } from "../errors/applicationErrors";
import {
  avaliarOperacaoAutorizacao,
  autorizarOperacao,
  montarRequisicaoAutorizacao,
  podeOperacao,
  type DepsContextoAutorizacao,
} from "./contextoAutorizacao";
import { montarActorContext } from "./actorContext";
import {
  criarProvidersReais,
  type AlvoEscopoResolvido,
  type CapabilityComEscopos,
  type DadosAssignedSoberanos,
} from "./providers/reais";
import {
  montarResourceContextSoberano,
  type RecursoSoberanoCarregado,
} from "./resourceContextReal";
import type {
  ExceptionalProvider,
  PilotFullAccessProvider,
  ScopeType,
  TemporaryProvider,
} from "./policyEngine/types";

const ORG = "org-1";
const USER = "u-1";
const COL = "col-1";
const OUTRO = "col-9";

function identidade(overrides?: Partial<AuthIdentity>): AuthIdentity {
  return {
    authUserId: USER,
    perfil: { id: USER, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Org 1" }],
    ...overrides,
  };
}

function recurso(overrides?: Partial<RecursoSoberanoCarregado>): RecursoSoberanoCarregado {
  return {
    kind: "collaborator",
    id: COL,
    organizationId: ORG,
    ownerCollaboratorId: COL,
    ...overrides,
  };
}

const alvo = { type: "collaborator" as const, id: COL };

function capability(
  code: CapabilityComEscopos["capability"],
  scopes: readonly ScopeType[],
  unitIds?: readonly string[]
): CapabilityComEscopos {
  return { capability: code, scopes, ...(unitIds ? { unitIds } : {}) };
}

interface Cenario {
  identidade?: AuthIdentity | null;
  vinculo?: string | null;
  capabilities?: readonly CapabilityComEscopos[];
  alvos?: Partial<Record<ScopeType, readonly AlvoEscopoResolvido[]>>;
  recurso?: RecursoSoberanoCarregado | null;
  agora?: Date;
  assigned?: DadosAssignedSoberanos;
  temporary?: TemporaryProvider;
  exceptional?: ExceptionalProvider;
  pilot?: PilotFullAccessProvider;
}

function deps(cenario: Cenario = {}): DepsContextoAutorizacao {
  const chamadasIdentidade: string[] = [];
  const base: DepsContextoAutorizacao = {
    agora: () => cenario.agora ?? new Date("2026-02-01T10:00:00Z"),
    resolverIdentidade: async (authUserId: string) => {
      chamadasIdentidade.push(authUserId);
      if (cenario.identidade === null) return null;
      return cenario.identidade ?? identidade();
    },
    resolverColaboradorVinculado: async () =>
      cenario.vinculo === undefined ? COL : cenario.vinculo,
    resolverCapabilitiesEscopos: async () => cenario.capabilities ?? [],
    resolverAlvosEscopo: async ({ scope }) => cenario.alvos?.[scope] ?? [],
    carregarRecurso: async () =>
      cenario.recurso === undefined ? recurso() : cenario.recurso,
    ...(cenario.assigned ? { assigned: cenario.assigned } : {}),
    ...(cenario.temporary ? { temporary: cenario.temporary } : {}),
    ...(cenario.exceptional ? { exceptional: cenario.exceptional } : {}),
    ...(cenario.pilot ? { pilot: cenario.pilot } : {}),
  };
  // expõe as chamadas para asserções de spoofing
  (base as DepsContextoAutorizacao & { chamadasIdentidade: string[] }).chamadasIdentidade =
    chamadasIdentidade;
  return base;
}

function entrada(overrides: Partial<Parameters<typeof avaliarOperacaoAutorizacao>[0]> = {}) {
  return {
    authUserId: USER,
    organizationId: ORG,
    capability: "collaborator.read" as const,
    alvo,
    ...overrides,
  };
}

describe("F5-05 — happy path por scope (SELF/DR/DESC/UNIT/ORG/ASSIGNED)", () => {
  it("SELF permite o próprio colaborador vinculado", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({
        capabilities: [capability("collaborator.read", ["SELF"])],
        alvos: { SELF: [{ collaboratorId: COL, positionId: null }] },
      })
    );
    expect(decisao.allowed).toBe(true);
    expect(decisao.diagnostics?.matchedScope).toBe("SELF");
  });

  it("DIRECT_REPORTS permite subordinado direto resolvido server-side", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada({ alvo: { type: "collaborator", id: "sub-1" } }),
      deps({
        capabilities: [capability("collaborator.read", ["DIRECT_REPORTS"])],
        alvos: { DIRECT_REPORTS: [{ collaboratorId: "sub-1", positionId: "p-1" }] },
        recurso: recurso({ id: "sub-1", ownerCollaboratorId: "sub-1" }),
      })
    );
    expect(decisao.allowed).toBe(true);
    expect(decisao.diagnostics?.matchedScope).toBe("DIRECT_REPORTS");
  });

  it("DESCENDANTS permite descendente resolvido server-side", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada({ alvo: { type: "collaborator", id: "neto-1" } }),
      deps({
        capabilities: [capability("collaborator.read", ["DESCENDANTS"])],
        alvos: { DESCENDANTS: [{ collaboratorId: "neto-1", positionId: "p-9" }] },
        recurso: recurso({ id: "neto-1" }),
      })
    );
    expect(decisao.allowed).toBe(true);
    expect(decisao.diagnostics?.matchedScope).toBe("DESCENDANTS");
  });

  it("ORGANIZATIONAL_UNIT permite alvo da unidade atribuída", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada({ alvo: { type: "collaborator", id: COL } }),
      deps({
        capabilities: [capability("collaborator.read", ["ORGANIZATIONAL_UNIT"], ["unit-1"])],
        alvos: { ORGANIZATIONAL_UNIT: [{ collaboratorId: COL, positionId: "p-42" }] },
        recurso: recurso({ unitId: "unit-1" }),
      })
    );
    expect(decisao.allowed).toBe(true);
    expect(decisao.diagnostics?.matchedScope).toBe("ORGANIZATIONAL_UNIT");
  });

  it("ORGANIZATION cobre o tenant; ADMIN sem colaborador é válido (D14)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({
        capabilities: [capability("collaborator.read", ["ORGANIZATION"])],
        vinculo: null,
      })
    );
    expect(decisao.allowed).toBe(true);
    expect(decisao.diagnostics?.matchedScope).toBe("ORGANIZATION");
  });

  it("ASSIGNED só resolve com fonte soberana F3-08/09 e vínculo (fail-closed sem ela)", async () => {
    const assigned: DadosAssignedSoberanos = {
      collegiateMemberships: [
        { cycleId: "c-1", organizationId: ORG, evaluatedCollaboratorId: COL, memberCollaboratorId: COL },
      ],
      evaluationResponsibilities: [],
      resolveEvaluationTarget: () => ({
        cycleId: "c-1",
        organizationId: ORG,
        evaluatedCollaboratorId: COL,
        positionId: "p-1",
      }),
    };

    const comDados = await avaliarOperacaoAutorizacao(
      entrada({ capability: "evaluation.read" }),
      deps({
        capabilities: [capability("evaluation.read", ["ASSIGNED"])],
        assigned,
      })
    );
    expect(comDados.allowed).toBe(true);
    expect(comDados.diagnostics?.matchedScope).toBe("ASSIGNED");

    const semDados = await avaliarOperacaoAutorizacao(
      entrada({ capability: "evaluation.read" }),
      deps({ capabilities: [capability("evaluation.read", ["ASSIGNED"])] })
    );
    expect(semDados.allowed).toBe(false);
    expect(semDados.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("self-review: alvo fora do scope ⇒ SCOPE_INSUFFICIENT", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada({ alvo: { type: "collaborator", id: OUTRO } }),
      deps({
        capabilities: [capability("collaborator.read", ["SELF"])],
        alvos: { SELF: [{ collaboratorId: COL, positionId: null }] },
        recurso: recurso({ id: OUTRO }),
      })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });
});

describe("F5-05 — spoofing e fronteira do cliente", () => {
  it("usa o authUserId do servidor (nunca um actorId do corpo)", async () => {
    const d = deps({
      capabilities: [capability("collaborator.read", ["SELF"])],
      alvos: { SELF: [{ collaboratorId: COL, positionId: null }] },
    });
    await avaliarOperacaoAutorizacao(
      // campo extra "actor_id" no corpo não altera a identidade resolvida
      { ...entrada(), ...({ actor_id: "u-invasor", user_profile_id: "u-invasor" } as object) },
      d
    );
    const chamadas = (d as DepsContextoAutorizacao & { chamadasIdentidade: string[] })
      .chamadasIdentidade;
    expect(chamadas).toEqual([USER]);
  });

  it("organizationId spoofada sem membership ativa ⇒ MEMBERSHIP_INVALID", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada({ organizationId: "org-2" }),
      deps({ capabilities: [capability("collaborator.read", ["ORGANIZATION"])] })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("MEMBERSHIP_INVALID");
    expect(decisao.denial?.publicCode).toBe("FORBIDDEN");
  });

  it("membership inativa e perfil inativo ⇒ DENY", async () => {
    const membershipInativa = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({
        identidade: identidade({
          memberships: [{ id: "m-1", organizationId: ORG, status: "disabled" }],
        }),
      })
    );
    expect(membershipInativa.denial?.reason).toBe("MEMBERSHIP_INVALID");

    const perfilInativo = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({ identidade: identidade({ perfil: { id: USER, status: "disabled" } }) })
    );
    expect(perfilInativo.denial?.reason).toBe("PROFILE_DISABLED");

    const semIdentidade = await avaliarOperacaoAutorizacao(entrada(), deps({ identidade: null }));
    expect(semIdentidade.denial?.reason).toBe("NO_IDENTITY");
  });

  it("capability desconhecida ⇒ DENY (fail-closed do vocabulário)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada({ capability: "capability.inventada" as never }),
      deps()
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("alvo global/sintético e domínio legado ⇒ TARGET_INVALID (D19/D22)", async () => {
    const global = await avaliarOperacaoAutorizacao(
      entrada({ alvo: { type: "cycle", id: "global" } }),
      deps()
    );
    expect(global.denial?.reason).toBe("TARGET_INVALID");

    const legado = await avaliarOperacaoAutorizacao(
      entrada({ capability: "goal.write", alvo: { type: "goal", id: "g-1" } }),
      deps()
    );
    expect(legado.denial?.reason).toBe("TARGET_INVALID");
  });
});

describe("F5-05 — cross-tenant, IDOR e recurso inválido", () => {
  it("recurso de outro tenant ⇒ CROSS_TENANT (defesa em profundidade)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({
        capabilities: [capability("collaborator.read", ["ORGANIZATION"])],
        recurso: recurso({ organizationId: "org-2" }),
      })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CROSS_TENANT");
    expect(decisao.denial?.publicCode).toBe("NOT_FOUND");
  });

  it("recurso inexistente/inacessível ⇒ TARGET_INVALID (nunca ALLOW por omissão)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({ capabilities: [capability("collaborator.read", ["ORGANIZATION"])], recurso: null })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("TARGET_INVALID");
    expect(decisao.denial?.publicCode).toBe("NOT_FOUND");
  });

  it("recurso inválido/inconsistente (id vazio) ⇒ TARGET_INVALID", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({
        capabilities: [capability("collaborator.read", ["ORGANIZATION"])],
        recurso: recurso({ id: "   " }),
      })
    );
    expect(decisao.denial?.reason).toBe("TARGET_INVALID");
  });
});

describe("F5-05 — freshness/revogação (D10) e contexto temporal (D21)", () => {
  it("capability revogada entre operações surte efeito na operação seguinte", async () => {
    let capabilities: CapabilityComEscopos[] = [capability("collaborator.read", ["SELF"])];
    const d: DepsContextoAutorizacao = {
      ...deps(),
      resolverCapabilitiesEscopos: async () => capabilities,
      resolverAlvosEscopo: async () => [{ collaboratorId: COL, positionId: null }],
    };

    const antes = await avaliarOperacaoAutorizacao(entrada(), d);
    expect(antes.allowed).toBe(true);

    capabilities = []; // revogação
    const depois = await avaliarOperacaoAutorizacao(entrada(), d);
    expect(depois.allowed).toBe(false);
    expect(depois.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("scope revogado entre operações surte efeito na operação seguinte", async () => {
    let alvos: AlvoEscopoResolvido[] = [{ collaboratorId: COL, positionId: null }];
    const d: DepsContextoAutorizacao = {
      ...deps({ capabilities: [capability("collaborator.read", ["SELF"])] }),
      resolverAlvosEscopo: async () => alvos,
    };

    const antes = await avaliarOperacaoAutorizacao(entrada(), d);
    expect(antes.allowed).toBe(true);

    alvos = []; // revogação do scope
    const depois = await avaliarOperacaoAutorizacao(entrada(), d);
    expect(depois.allowed).toBe(false);
    expect(depois.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("sem instante soberano válido ⇒ INDETERMINATE", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({
        capabilities: [capability("collaborator.read", ["SELF"])],
        alvos: { SELF: [{ collaboratorId: COL, positionId: null }] },
        agora: new Date("data-invalida"),
      })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("INDETERMINATE");
  });

  it("sem domainState ⇒ DENY no engine (INDETERMINATE)", () => {
    const ator = montarActorContext({
      identity: identidade(),
      organizationId: ORG,
      collaboratorId: COL,
    });
    const rec = montarResourceContextSoberano({
      recurso: recurso(),
      organizationIdEsperada: ORG,
    });
    if (!ator.ok || !rec.ok) throw new Error("fixtures inválidos");

    const request = montarRequisicaoAutorizacao({
      actorContext: ator.actorContext,
      resourceContext: rec.resourceContext,
      capability: "collaborator.read",
      instanteSoberano: new Date("2026-02-01T10:00:00Z"),
    });
    if (!request) throw new Error("request inválido");

    const providers = criarProvidersReais({
      actorId: USER,
      collaboratorId: COL,
      organizationId: ORG,
      perfilAtivo: true,
      membershipAtiva: true,
      capabilities: [capability("collaborator.read", ["SELF"])],
      escoposResolvidos: [
        { scope: "SELF", unitId: null, alvos: [{ collaboratorId: COL, positionId: null }] },
      ],
      alvo,
      tenantDoAlvo: ORG,
    });

    const semDomain = { ...request, domainState: undefined };
    const decisao = podeOperacao(semDomain, providers);
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("INDETERMINATE");
  });
});

describe("F5-05 — origens B/C/D preservadas (D11)", () => {
  const temporary: TemporaryProvider = {
    getEligibleCapabilities: () => ["collaborator.read"],
    resolveTemporaryGrants: () => [
      {
        origin: "temporary:r-1",
        responsibilityId: "r-1",
        responsibilityType: "evaluative",
        capability: "collaborator.read",
        scope: "DESCENDANTS",
        substitutedPositionId: "pos-substituida",
      },
    ],
  };

  it("origem B (temporária) eleva pontualmente, sem virar role", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      entrada(),
      deps({ capabilities: [], temporary })
    );
    expect(decisao.allowed).toBe(true);
    expect(decisao.diagnostics?.temporaryOrigins).toEqual(["temporary:r-1"]);
  });

  it("providers B/C/D são repassados sem alteração (não viram role)", () => {
    const exceptional = {
      isCapabilityExceptionalEligible: () => true,
      isTargetConfidential: () => true,
      resolveExceptionalGrants: () => [],
    } as unknown as ExceptionalProvider;
    const pilot = {
      isEnvironmentEligible: () => true,
      isCapabilityPilotEligible: () => true,
      isTargetConfidential: () => false,
      resolvePilotFullAccessGrants: () => [],
    } as unknown as PilotFullAccessProvider;

    const providers = criarProvidersReais({
      actorId: USER,
      collaboratorId: COL,
      organizationId: ORG,
      perfilAtivo: true,
      membershipAtiva: true,
      capabilities: [],
      escoposResolvidos: [],
      alvo,
      tenantDoAlvo: ORG,
      temporary,
      exceptional,
      pilot,
    });

    expect(providers.temporary).toBe(temporary);
    expect(providers.exceptional).toBe(exceptional);
    expect(providers.pilot).toBe(pilot);
  });
});

describe("F5-05 — paridade can() × authorize() (D13)", () => {
  function contexto() {
    const ator = montarActorContext({
      identity: identidade(),
      organizationId: ORG,
      collaboratorId: COL,
    });
    const rec = montarResourceContextSoberano({
      recurso: recurso(),
      organizationIdEsperada: ORG,
    });
    if (!ator.ok || !rec.ok) throw new Error("fixtures inválidos");
    const request = montarRequisicaoAutorizacao({
      actorContext: ator.actorContext,
      resourceContext: rec.resourceContext,
      capability: "collaborator.read",
      instanteSoberano: new Date("2026-02-01T10:00:00Z"),
    });
    if (!request) throw new Error("request inválido");
    return request;
  }

  it("mesma pipeline: ALLOW em can() ⇒ authorize() não lança", () => {
    const providers = criarProvidersReais({
      actorId: USER,
      collaboratorId: COL,
      organizationId: ORG,
      perfilAtivo: true,
      membershipAtiva: true,
      capabilities: [capability("collaborator.read", ["SELF"])],
      escoposResolvidos: [
        { scope: "SELF", unitId: null, alvos: [{ collaboratorId: COL, positionId: null }] },
      ],
      alvo,
      tenantDoAlvo: ORG,
    });
    const request = contexto();
    expect(podeOperacao(request, providers).allowed).toBe(true);
    expect(() => autorizarOperacao(request, providers)).not.toThrow();
  });

  it("mesma pipeline: DENY em can() ⇒ authorize() lança erro público coerente", () => {
    const providers = criarProvidersReais({
      actorId: USER,
      collaboratorId: COL,
      organizationId: ORG,
      perfilAtivo: true,
      membershipAtiva: true,
      capabilities: [],
      escoposResolvidos: [],
      alvo,
      tenantDoAlvo: ORG,
    });
    const request = contexto();
    const decisao = podeOperacao(request, providers);
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CAPABILITY_MISSING");
    expect(() => autorizarOperacao(request, providers)).toThrow(ForbiddenError);
  });

  it("cross-tenant ⇒ código público NOT_FOUND (não vaza existência)", () => {
    const ator = montarActorContext({
      identity: identidade(),
      organizationId: ORG,
      collaboratorId: COL,
    });
    const rec = montarResourceContextSoberano({
      recurso: recurso({ organizationId: ORG }),
      organizationIdEsperada: ORG,
    });
    if (!ator.ok || !rec.ok) throw new Error("fixtures inválidos");
    const request = montarRequisicaoAutorizacao({
      actorContext: ator.actorContext,
      resourceContext: rec.resourceContext,
      capability: "collaborator.read",
      instanteSoberano: new Date(),
    });
    if (!request) throw new Error("request inválido");

    const providers = criarProvidersReais({
      actorId: USER,
      collaboratorId: COL,
      organizationId: ORG,
      perfilAtivo: true,
      membershipAtiva: true,
      capabilities: [capability("collaborator.read", ["ORGANIZATION"])],
      escoposResolvidos: [],
      alvo,
      // tenant do alvo divergente: engine devolve CROSS_TENANT
      tenantDoAlvo: "org-2",
    });

    const decisao = podeOperacao(request, providers);
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CROSS_TENANT");
    expect(() => autorizarOperacao(request, providers)).toThrow(NotFoundError);
  });
});

describe("F5-05 — providers reais: isolamento e fail-closed", () => {
  it("código de capability fora do catálogo não é concedido", () => {
    const providers = criarProvidersReais({
      actorId: USER,
      collaboratorId: COL,
      organizationId: ORG,
      perfilAtivo: true,
      membershipAtiva: true,
      capabilities: [{ capability: "colaborador.fantasma" as never, scopes: ["SELF"] }],
      escoposResolvidos: [],
      alvo,
      tenantDoAlvo: ORG,
    });
    expect(providers.capabilities.hasCapability(USER, ORG, "colaborador.fantasma" as never)).toBe(
      false
    );
  });

  it("identidade de outro ator/organização não é aceita pelos providers", () => {
    const providers = criarProvidersReais({
      actorId: USER,
      collaboratorId: COL,
      organizationId: ORG,
      perfilAtivo: true,
      membershipAtiva: true,
      capabilities: [capability("collaborator.read", ["SELF"])],
      escoposResolvidos: [],
      alvo,
      tenantDoAlvo: ORG,
    });
    expect(providers.identity.isProfileActive("outro")).toBe(false);
    expect(providers.identity.isMembershipActive(USER, "org-2")).toBe(false);
    expect(providers.capabilities.hasCapability(USER, "org-2", "collaborator.read")).toBe(false);
    expect(providers.scopes.getActiveScopes("outro", ORG)).toEqual([]);
    // tenant de alvo não carregado ⇒ undefined (TARGET_INVALID no engine)
    expect(providers.targets.resolveTargetTenant({ type: "collaborator", id: OUTRO })).toBeUndefined();
  });

  it("perfil/membership inativos ⇒ providers negam", () => {
    const providers = criarProvidersReais({
      actorId: USER,
      collaboratorId: null,
      organizationId: ORG,
      perfilAtivo: false,
      membershipAtiva: false,
      capabilities: [],
      escoposResolvidos: [],
      alvo,
      tenantDoAlvo: ORG,
    });
    expect(providers.identity.isProfileActive(USER)).toBe(false);
    expect(providers.identity.isMembershipActive(USER, ORG)).toBe(false);
  });

  it("erro de resolução propagado não é engolido (fail-closed no chamador)", async () => {
    const d: DepsContextoAutorizacao = {
      ...deps(),
      resolverCapabilitiesEscopos: vi.fn(async () => {
        throw new Error("banco indisponível");
      }),
    };
    await expect(avaliarOperacaoAutorizacao(entrada(), d)).rejects.toThrow("banco indisponível");
  });
});
