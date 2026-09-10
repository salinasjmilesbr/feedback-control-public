import { describe, expect, it } from "vitest";
import type { AuthIdentity } from "../auth/tipos";
import {
  ehActorContextSoberano,
  montarActorContext,
  projetarParaUx,
} from "./actorContext";
import {
  ehAlvoSinteticoGlobal,
  montarResourceContextSoberano,
  motivoAlvoNaoAutorizavel,
} from "./resourceContextReal";
import { montarRequisicaoAutorizacao } from "./contextoAutorizacao";

function identidadeValida(overrides?: Partial<AuthIdentity>): AuthIdentity {
  return {
    authUserId: "u-1",
    perfil: { id: "u-1", status: "active" },
    memberships: [{ id: "m-1", organizationId: "org-1", status: "active" }],
    organizacoes: [{ id: "org-1", name: "Org 1" }],
    ...overrides,
  };
}

function atorOk() {
  const resultado = montarActorContext({
    identity: identidadeValida(),
    organizationId: "org-1",
    collaboratorId: "col-1",
  });
  if (!resultado.ok) throw new Error(`esperado ator válido: ${resultado.motivo}`);
  return resultado.actorContext;
}

describe("F5-05 — ActorContext real (D1–D5, D14, D15, D20)", () => {
  it("monta o contexto soberano e produz o ActorRef correto", () => {
    const actorContext = atorOk();
    expect(actorContext.identity.authUserId).toBe("u-1");
    expect(actorContext.organizationId).toBe("org-1");
    expect(actorContext.membership.id).toBe("m-1");
    expect(actorContext.collaboratorId).toBe("col-1");
    expect(actorContext.toActorRef()).toEqual({ actorId: "u-1", organizationId: "org-1" });
  });

  it("ADMIN sem colaborador é válido (collaboratorId = null)", () => {
    const resultado = montarActorContext({
      identity: identidadeValida(),
      organizationId: "org-1",
      collaboratorId: null,
    });
    expect(resultado.ok).toBe(true);
    if (resultado.ok) expect(resultado.actorContext.collaboratorId).toBeNull();
  });

  it("fail-closed: sem identidade, perfil inativo, org ausente/indisponível, membership ausente", () => {
    const semIdentidade = montarActorContext({
      identity: null,
      organizationId: "org-1",
      collaboratorId: null,
    });
    expect(semIdentidade.ok ? "" : semIdentidade.motivo).toBe("SEM_IDENTIDADE");

    const perfilInativo = montarActorContext({
      identity: identidadeValida({ perfil: { id: "u-1", status: "disabled" } }),
      organizationId: "org-1",
      collaboratorId: null,
    });
    expect(perfilInativo.ok ? "" : perfilInativo.motivo).toBe("PERFIL_INATIVO");

    const orgAusente = montarActorContext({
      identity: identidadeValida(),
      organizationId: null,
      collaboratorId: null,
    });
    expect(orgAusente.ok ? "" : orgAusente.motivo).toBe("ORGANIZACAO_AUSENTE");

    const orgIndisponivel = montarActorContext({
      identity: identidadeValida(),
      organizationId: "org-2",
      collaboratorId: null,
    });
    expect(orgIndisponivel.ok ? "" : orgIndisponivel.motivo).toBe("ORGANIZACAO_NAO_DISPONIVEL");

    const membershipAusente = montarActorContext({
      identity: identidadeValida({
        memberships: [{ id: "m-1", organizationId: "org-1", status: "disabled" }],
      }),
      organizationId: "org-1",
      collaboratorId: null,
    });
    expect(membershipAusente.ok ? "" : membershipAusente.motivo).toBe("MEMBERSHIP_AUSENTE");
  });

  it("divergência authUserId × perfil.id é recusada (invariante F5-01)", () => {
    const resultado = montarActorContext({
      identity: identidadeValida({ perfil: { id: "u-outro", status: "active" } }),
      organizationId: "org-1",
      collaboratorId: null,
    });
    expect(resultado.ok).toBe(false);
  });

  it("contexto do browser NÃO é soberano (D20): literal, clone e projeção falham", () => {
    const actorContext = atorOk();
    expect(ehActorContextSoberano(actorContext)).toBe(true);

    // Objeto literal estruturalmente idêntico, forjado no browser.
    const forjado = {
      identity: identidadeValida(),
      organizationId: "org-1",
      membership: { id: "m-1", organizationId: "org-1", status: "active" },
      collaboratorId: "col-1",
      toActorRef: () => ({ actorId: "u-1", organizationId: "org-1" }),
    };
    expect(ehActorContextSoberano(forjado)).toBe(false);

    // Cópia via JSON (perde o símbolo privado).
    const clone = JSON.parse(JSON.stringify(projetarParaUx(actorContext)));
    expect(ehActorContextSoberano(clone)).toBe(false);
    expect(ehActorContextSoberano(projetarParaUx(actorContext))).toBe(false);
    expect(ehActorContextSoberano(null)).toBe(false);
  });
});

describe("F5-05 — ResourceContext real (D6, D8, D19, D22)", () => {
  it("monta recurso estrutural tenant-rooted", () => {
    const resultado = montarResourceContextSoberano({
      recurso: {
        kind: "collaborator",
        id: "col-1",
        organizationId: "org-1",
        ownerCollaboratorId: "col-1",
      },
      organizationIdEsperada: "org-1",
    });
    expect(resultado.ok).toBe(true);
    if (resultado.ok) {
      expect(resultado.resourceContext.organizationId).toBe("org-1");
      expect(resultado.resourceContext.target).toEqual({ type: "collaborator", id: "col-1" });
      expect(resultado.resourceContext.ownerCollaboratorId).toBe("col-1");
    }
  });

  it("tenant ausente e tenant divergente falham (cross-tenant por construção)", () => {
    const semTenant = montarResourceContextSoberano({
      recurso: { kind: "collaborator", id: "col-1", organizationId: "" },
      organizationIdEsperada: "org-1",
    });
    expect(semTenant.ok ? "" : semTenant.motivo).toBe("TENANT_AUSENTE");

    const divergente = montarResourceContextSoberano({
      recurso: { kind: "collaborator", id: "col-1", organizationId: "org-2" },
      organizationIdEsperada: "org-1",
    });
    expect(divergente.ok ? "" : divergente.motivo).toBe("TENANT_DIVERGENTE");
  });

  it("id ausente falha (recurso inválido/inconsistente)", () => {
    const resultado = montarResourceContextSoberano({
      recurso: { kind: "collaborator", id: "  ", organizationId: "org-1" },
      organizationIdEsperada: "org-1",
    });
    expect(resultado.ok ? "" : resultado.motivo).toBe("IDENTIFICADOR_AUSENTE");
  });

  it("alvos globais/sintéticos e domínios legados não são autorizáveis (D19/D22)", () => {
    expect(ehAlvoSinteticoGlobal({ type: "cycle", id: "global" })).toBe(true);
    expect(motivoAlvoNaoAutorizavel({ type: "cycle", id: "global" })).toBe("TARGET_NAO_SOBERANO");
    expect(motivoAlvoNaoAutorizavel({ type: "cycle", id: "c-1" })).toBe("TARGET_NAO_SOBERANO");
    expect(motivoAlvoNaoAutorizavel({ type: "goal", id: "g-1" })).toBe("TARGET_NAO_SOBERANO");
    expect(motivoAlvoNaoAutorizavel({ type: "collaborator", id: "col-1" })).toBeNull();
  });
});

describe("F5-05 — requisição do engine (paridade e fronteira)", () => {
  const recursoOk = () => {
    const r = montarResourceContextSoberano({
      recurso: { kind: "collaborator", id: "col-1", organizationId: "org-1" },
      organizationIdEsperada: "org-1",
    });
    if (!r.ok) throw new Error("recurso inválido no fixture");
    return r.resourceContext;
  };

  it("usa o INSTANTE SOBERANO como data da decisão, nunca a data de negócio (D21)", () => {
    const instante = new Date("2026-01-10T12:00:00Z");
    const request = montarRequisicaoAutorizacao({
      actorContext: atorOk(),
      resourceContext: recursoOk(),
      capability: "collaborator.read",
      instanteSoberano: instante,
    });
    expect(request).not.toBeNull();
    expect(request?.context.date).toBe(instante);
    expect(request?.actor).toEqual({ actorId: "u-1", organizationId: "org-1" });
  });

  it("recusa contexto de ator NÃO soberano (browser como autoridade)", () => {
    const forjado = {
      identity: identidadeValida(),
      organizationId: "org-1",
      membership: { id: "m-1", organizationId: "org-1", status: "active" },
      collaboratorId: null,
      toActorRef: () => ({ actorId: "u-1", organizationId: "org-1" }),
    };
    const request = montarRequisicaoAutorizacao({
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      actorContext: forjado as any,
      resourceContext: recursoOk(),
      capability: "collaborator.read",
      instanteSoberano: new Date(),
    });
    expect(request).toBeNull();
  });

  it("recusa capability desconhecida, alvo global, tenant divergente e instante inválido", () => {
    const base = {
      actorContext: atorOk(),
      resourceContext: recursoOk(),
      instanteSoberano: new Date("2026-01-10T12:00:00Z"),
    };

    expect(
      montarRequisicaoAutorizacao({ ...base, capability: "nao.existe" as never })
    ).toBeNull();

    const global = { ...recursoOk(), kind: "collaborator" as const, target: { type: "cycle" as never, id: "global" } };
    expect(
      montarRequisicaoAutorizacao({ ...base, resourceContext: global, capability: "collaborator.read" })
    ).toBeNull();

    const outroTenant = { ...recursoOk(), organizationId: "org-2" };
    expect(
      montarRequisicaoAutorizacao({ ...base, resourceContext: outroTenant, capability: "collaborator.read" })
    ).toBeNull();

    expect(
      montarRequisicaoAutorizacao({
        ...base,
        capability: "collaborator.read",
        instanteSoberano: new Date("invalida"),
      })
    ).toBeNull();
  });
});
