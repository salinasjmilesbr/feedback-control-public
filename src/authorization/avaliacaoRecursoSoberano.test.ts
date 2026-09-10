import { describe, expect, it } from "vitest";
import {
  avaliacaoCancelada,
  avaliacaoConcluida,
  avaliacaoEditavel,
  estadoDominioAvaliacao,
  estadoDominioCriacaoAvaliacao,
} from "./estadoDominioAvaliacao.ts";
import {
  ehTipoRecursoSoberano,
  montarResourceContextSoberano,
  motivoAlvoNaoAutorizavel,
  TIPOS_RECURSO_NAO_SOBERANOS,
  TIPOS_RECURSO_SOBERANOS,
} from "./resourceContextReal.ts";
import { avaliarOperacaoAutorizacao, type DepsContextoAutorizacao } from "./contextoAutorizacao.ts";
import type { Capability } from "./Capability.ts";
import type { RecursoSoberanoCarregado } from "./resourceContextReal.ts";
import type { AuthIdentity } from "../auth/tipos.ts";

/**
 * F5-06 (§8.1/D8/D10/D20/D27) — o recurso AVALIAÇÃO passa a ser soberano:
 * ResourceContext real derivado da linha do banco, domainState do status real e
 * decisão pelo Policy Engine com capability × scope.
 */

const ORG = "org-1";
const ORG_B = "org-2";
const USER = "u-1";
const AVALIADO = "col-avaliado";
const GESTOR = "col-gestor";
const COLEGA = "col-colega";
const AVALIACAO = "eval-1";

function identidade(): AuthIdentity {
  return {
    authUserId: USER,
    perfil: { id: USER, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Org sintetica" }],
  } as AuthIdentity;
}

interface Cenario {
  readonly recurso?: RecursoSoberanoCarregado | null;
  readonly contexto?: { status: string; encerradaComPendencias?: boolean } | null;
  readonly capabilities?: readonly { capability: Capability; scopes: readonly string[] }[];
  readonly alvos?: Record<string, readonly { collaboratorId: string | null; positionId: string | null }[]>;
  readonly vinculo?: string | null;
}

function deps(cenario: Cenario = {}): DepsContextoAutorizacao {
  const recurso =
    cenario.recurso === undefined
      ? ({
          kind: "evaluation",
          id: AVALIACAO,
          organizationId: ORG,
          evaluatedCollaboratorId: AVALIADO,
          cycleId: "ciclo-1",
          status: "RASCUNHO",
        } as RecursoSoberanoCarregado)
      : cenario.recurso;

  return {
    agora: () => new Date("2026-02-01T10:00:00Z"),
    resolverIdentidade: async () => identidade(),
    resolverColaboradorVinculado: async () =>
      cenario.vinculo === undefined ? COLEGA : cenario.vinculo,
    resolverCapabilitiesEscopos: async () =>
      (cenario.capabilities ?? [{ capability: "evaluation.read", scopes: ["SELF"] }]).map(
        (item) => ({ capability: item.capability, scopes: item.scopes as never })
      ),
    resolverAlvosEscopo: async ({ scope }) => cenario.alvos?.[scope] ?? [],
    carregarRecurso: async () => recurso,
    carregarContextoAvaliacao: async () =>
      cenario.contexto === undefined
        ? { status: "RASCUNHO" }
        : (cenario.contexto ?? null),
  };
}

describe("estado de domínio da avaliação (F5-06 D8/D18)", () => {
  it("reconhece estados imutáveis", () => {
    expect(avaliacaoConcluida({ status: "CONCLUIDA" })).toBe(true);
    expect(avaliacaoCancelada({ status: "cancelada" })).toBe(true);
    expect(avaliacaoEditavel({ status: "RASCUNHO" })).toBe(true);
    expect(avaliacaoEditavel({ status: "PRONTA_PARA_FEEDBACK" })).toBe(true);
    expect(avaliacaoEditavel({ status: "CONCLUIDA" })).toBe(false);
    expect(avaliacaoEditavel({ status: "" })).toBe(false);
  });

  it("bloqueia nota/escrita quando CONCLUIDA ou CANCELADA", () => {
    for (const status of ["CONCLUIDA", "CANCELADA"]) {
      const probe = estadoDominioAvaliacao({ status });
      expect(probe.allows("evaluation.write")).toBe(false);
      expect(probe.allows("evaluation.create")).toBe(false);
      // leitura e operações excepcionais seguem para o engine decidir (capability própria)
      expect(probe.allows("evaluation.read")).toBe(true);
      expect(probe.allows("evaluation.reopen")).toBe(true);
      expect(probe.allows("evaluation.cancel")).toBe(true);
    }
  });

  it("permite escrita em RASCUNHO/PRONTA_PARA_FEEDBACK", () => {
    for (const status of ["RASCUNHO", "PRONTA_PARA_FEEDBACK"]) {
      expect(estadoDominioAvaliacao({ status }).allows("evaluation.write")).toBe(true);
    }
  });

  it("probe de criação exige ciclo apto E avaliado apto (fail-closed)", () => {
    expect(
      estadoDominioCriacaoAvaliacao({ cicloPermiteNovaAvaliacao: true, avaliadoApto: true }).allows(
        "evaluation.create"
      )
    ).toBe(true);
    expect(
      estadoDominioCriacaoAvaliacao({ cicloPermiteNovaAvaliacao: false, avaliadoApto: true }).allows(
        "evaluation.create"
      )
    ).toBe(false);
    expect(
      estadoDominioCriacaoAvaliacao({ cicloPermiteNovaAvaliacao: true, avaliadoApto: false }).allows(
        "evaluation.create"
      )
    ).toBe(false);
  });
});

describe("ResourceContext real de avaliação (F5-06 §8.1)", () => {
  it("a avaliação é um tipo soberano e não é mais alvo legado", () => {
    expect(ehTipoRecursoSoberano("evaluation")).toBe(true);
    expect((TIPOS_RECURSO_SOBERANOS as readonly string[]).includes("evaluation")).toBe(true);
    expect((TIPOS_RECURSO_NAO_SOBERANOS as readonly string[]).includes("evaluation")).toBe(false);
    expect(motivoAlvoNaoAutorizavel({ type: "evaluation", id: AVALIACAO })).toBeNull();
  });

  it("deriva o tenant e o dono (avaliado) da LINHA REAL do recurso", () => {
    const resultado = montarResourceContextSoberano({
      recurso: {
        kind: "evaluation",
        id: AVALIACAO,
        organizationId: ORG,
        evaluatedCollaboratorId: AVALIADO,
        cycleId: "ciclo-1",
      },
      organizationIdEsperada: ORG,
    });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.resourceContext.organizationId).toBe(ORG);
    expect(resultado.resourceContext.ownerCollaboratorId).toBe(AVALIADO);
    expect(resultado.resourceContext.structure.collaboratorId).toBe(AVALIADO);
    expect(resultado.resourceContext.target).toEqual({ type: "evaluation", id: AVALIACAO });
    expect(resultado.resourceContext.cycleId).toBe("ciclo-1");
  });

  it("tenant divergente ⇒ TENANT_DIVERGENTE (cross-tenant fail-closed)", () => {
    const resultado = montarResourceContextSoberano({
      recurso: {
        kind: "evaluation",
        id: AVALIACAO,
        organizationId: ORG_B,
        evaluatedCollaboratorId: AVALIADO,
      },
      organizationIdEsperada: ORG,
    });
    expect(resultado).toEqual({ ok: false, motivo: "TENANT_DIVERGENTE" });
  });
});

describe("Policy Engine sobre o recurso avaliação", () => {
  it("avaliado FORA do escopo do ator ⇒ DENY com scope insuficiente", async () => {
    // O ator tem `evaluation.read` com scope SELF e está vinculado a OUTRO
    // colaborador: a avaliação de `AVALIADO` não está no seu alcance.
    const decisao = await avaliarOperacaoAutorizacao(
      { authUserId: USER, organizationId: ORG, capability: "evaluation.read", alvo: { type: "evaluation", id: AVALIACAO } },
      deps({ capabilities: [{ capability: "evaluation.read", scopes: ["SELF"] }], vinculo: GESTOR })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });

  it("capability presente mas SEM o scope necessário ⇒ DENY (não herda alcance de outra capability)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      { authUserId: USER, organizationId: ORG, capability: "evaluation.write", alvo: { type: "evaluation", id: AVALIACAO } },
      deps({
        capabilities: [{ capability: "evaluation.write", scopes: ["ORGANIZATION"] }],
        alvos: { ORGANIZATION: [{ collaboratorId: AVALIADO, positionId: null }] },
        contexto: { status: "RASCUNHO" },
      })
    );
    // ORGANIZATION é escopo de tenant: alcança o recurso do mesmo tenant.
    expect(decisao.allowed).toBe(true);
  });

  it("SELF correto ⇒ ALLOW (o próprio avaliado lê a sua avaliação)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      { authUserId: USER, organizationId: ORG, capability: "evaluation.read", alvo: { type: "evaluation", id: AVALIACAO } },
      deps({ alvos: { SELF: [{ collaboratorId: AVALIADO, positionId: null }] }, vinculo: AVALIADO })
    );
    expect(decisao.allowed).toBe(true);
  });

  it("DIRECT_REPORTS/DESCENDANTS alcançam a avaliação do colaborador em escopo", async () => {
    for (const scope of ["DIRECT_REPORTS", "DESCENDANTS"]) {
      const decisao = await avaliarOperacaoAutorizacao(
        {
          authUserId: USER,
          organizationId: ORG,
          capability: "evaluation.write",
          alvo: { type: "evaluation", id: AVALIACAO },
        },
        deps({
          capabilities: [{ capability: "evaluation.write", scopes: [scope as never] }],
          alvos: { [scope]: [{ collaboratorId: AVALIADO, positionId: null }] },
        })
      );
      expect(decisao.allowed).toBe(true);
    }
  });

  it("avaliação INEXISTENTE ⇒ TARGET_INVALID (fail-closed)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      { authUserId: USER, organizationId: ORG, capability: "evaluation.read", alvo: { type: "evaluation", id: AVALIACAO } },
      deps({ recurso: null })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("TARGET_INVALID");
    expect(decisao.denial?.publicCode).toBe("NOT_FOUND");
  });

  it("avaliação de OUTRO TENANT ⇒ CROSS_TENANT (NOT_FOUND público)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      { authUserId: USER, organizationId: ORG, capability: "evaluation.read", alvo: { type: "evaluation", id: AVALIACAO } },
      deps({
        recurso: {
          kind: "evaluation",
          id: AVALIACAO,
          organizationId: ORG_B,
          evaluatedCollaboratorId: AVALIADO,
        },
      })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CROSS_TENANT");
    expect(decisao.denial?.publicCode).toBe("NOT_FOUND");
  });

  it("capability fora do catálogo ⇒ DENY (fail-closed do vocabulário)", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      {
        authUserId: USER,
        organizationId: ORG,
        capability: "evaluation.complete" as Capability,
        alvo: { type: "evaluation", id: AVALIACAO },
      },
      deps()
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("CAPABILITY_MISSING");
  });

  it("domainState derivado server-side: CONCLUIDA nega escrita mesmo com capability", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      { authUserId: USER, organizationId: ORG, capability: "evaluation.write", alvo: { type: "evaluation", id: AVALIACAO } },
      deps({
        contexto: { status: "CONCLUIDA" },
        capabilities: [{ capability: "evaluation.write", scopes: ["DESCENDANTS"] }],
        alvos: { DESCENDANTS: [{ collaboratorId: AVALIADO, positionId: null }] },
      })
    );
    expect(decisao.allowed).toBe(false);
    expect(decisao.denial?.reason).toBe("DOMAIN_STATE_INVALID");
  });

  it("escrita em RASCUNHO com scope adequado ⇒ ALLOW", async () => {
    const decisao = await avaliarOperacaoAutorizacao(
      { authUserId: USER, organizationId: ORG, capability: "evaluation.write", alvo: { type: "evaluation", id: AVALIACAO } },
      deps({
        contexto: { status: "RASCUNHO" },
        capabilities: [{ capability: "evaluation.write", scopes: ["DESCENDANTS"] }],
        alvos: { DESCENDANTS: [{ collaboratorId: AVALIADO, positionId: null }] },
      })
    );
    expect(decisao.allowed).toBe(true);
  });
});
