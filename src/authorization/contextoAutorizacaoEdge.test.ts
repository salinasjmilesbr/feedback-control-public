import { describe, expect, it, vi } from "vitest";
import {
  avaliarRequisicaoAutorizacao,
  type DepsCoreContextoAutorizacao,
} from "../../supabase/functions/contexto-autorizacao/core";
import type { DepsContextoAutorizacao } from "./contextoAutorizacao";
import type { AuthIdentity } from "../auth/tipos";
import type { AlvoEscopoResolvido, CapabilityComEscopos } from "./providers/reais";
import type { RecursoSoberanoCarregado } from "./resourceContextReal";
import type { ScopeType } from "./policyEngine/types";

const ORG = "org-1";
const USER = "u-1";
const COL = "col-1";

function identidade(): AuthIdentity {
  return {
    authUserId: USER,
    perfil: { id: USER, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Org 1" }],
  };
}

interface Cenario {
  capabilities?: readonly CapabilityComEscopos[];
  alvos?: Partial<Record<ScopeType, readonly AlvoEscopoResolvido[]>>;
  recurso?: RecursoSoberanoCarregado | null;
}

function deps(
  cenario: Cenario = {},
  resolveCaller: (authHeader: string) => Promise<string | null> = async () => USER
): DepsCoreContextoAutorizacao {
  const autorizacao: DepsContextoAutorizacao = {
    agora: () => new Date("2026-02-01T10:00:00Z"),
    resolverIdentidade: async () => identidade(),
    resolverColaboradorVinculado: async () => COL,
    resolverCapabilitiesEscopos: async () => cenario.capabilities ?? [],
    resolverAlvosEscopo: async ({ scope }) => cenario.alvos?.[scope] ?? [],
    carregarRecurso: async () =>
      cenario.recurso === undefined
        ? { kind: "collaborator", id: COL, organizationId: ORG, ownerCollaboratorId: COL }
        : cenario.recurso,
  };
  return { resolveCaller, autorizacao };
}

function requisicao(corpo: unknown, authHeader?: string, metodo = "POST"): Request {
  const headers = new Headers();
  if (authHeader) headers.set("Authorization", authHeader);
  return new Request("http://localhost/fn", {
    method: metodo,
    headers,
    body: metodo === "POST" ? JSON.stringify(corpo) : undefined,
  });
}

const corpoOk = {
  organization_id: ORG,
  capability: "collaborator.read",
  target: { type: "collaborator", id: COL },
};

const cenarioPermitido: Cenario = {
  capabilities: [{ capability: "collaborator.read", scopes: ["SELF"] }],
  alvos: { SELF: [{ collaboratorId: COL, positionId: null }] },
};

describe("F5-05 — Edge Function da fronteira confiável (D20)", () => {
  it("OPTIONS responde CORS e método não permitido é 405", async () => {
    const preflight = await avaliarRequisicaoAutorizacao(
      requisicao(undefined, undefined, "OPTIONS"),
      deps()
    );
    expect(preflight.status).toBe(200);

    const get = await avaliarRequisicaoAutorizacao(
      requisicao(undefined, "Bearer jwt", "GET"),
      deps()
    );
    expect(get.status).toBe(405);
  });

  it("sem Authorization ⇒ 401; JWT inválido ⇒ 401 (identidade soberana ausente)", async () => {
    const semHeader = await avaliarRequisicaoAutorizacao(requisicao(corpoOk), deps());
    expect(semHeader.status).toBe(401);

    const jwtInvalido = await avaliarRequisicaoAutorizacao(
      requisicao(corpoOk, "Bearer invalido"),
      deps({}, async () => null)
    );
    expect(jwtInvalido.status).toBe(401);
  });

  it("actor_id/actor_user_profile_id no corpo são rejeitados (nunca confiados ao cliente)", async () => {
    const comActorId = await avaliarRequisicaoAutorizacao(
      requisicao({ ...corpoOk, actor_id: "u-invasor" }, "Bearer jwt"),
      deps(cenarioPermitido)
    );
    expect(comActorId.status).toBe(400);

    const comUserProfileId = await avaliarRequisicaoAutorizacao(
      requisicao({ ...corpoOk, user_profile_id: "u-invasor" }, "Bearer jwt"),
      deps(cenarioPermitido)
    );
    expect(comUserProfileId.status).toBe(400);
  });

  it("parâmetros ausentes ⇒ 400", async () => {
    const semAlvo = await avaliarRequisicaoAutorizacao(
      requisicao({ organization_id: ORG, capability: "collaborator.read" }, "Bearer jwt"),
      deps(cenarioPermitido)
    );
    expect(semAlvo.status).toBe(400);

    const semCapability = await avaliarRequisicaoAutorizacao(
      requisicao({ organization_id: ORG, target: { type: "collaborator", id: COL } }, "Bearer jwt"),
      deps(cenarioPermitido)
    );
    expect(semCapability.status).toBe(400);
  });

  it("happy path ⇒ 200 allowed:true (identidade do JWT, não do corpo)", async () => {
    const resposta = await avaliarRequisicaoAutorizacao(
      requisicao(corpoOk, "Bearer jwt-do-usuario"),
      deps(cenarioPermitido)
    );
    expect(resposta.status).toBe(200);
    const corpo = (await resposta.json()) as { allowed: boolean };
    expect(corpo.allowed).toBe(true);
  });

  it("DENY ⇒ 200 allowed:false com código público (sem razão interna)", async () => {
    const resposta = await avaliarRequisicaoAutorizacao(
      requisicao(corpoOk, "Bearer jwt"),
      deps({ capabilities: [] })
    );
    expect(resposta.status).toBe(200);
    const corpo = (await resposta.json()) as { allowed: boolean; code: string };
    expect(corpo.allowed).toBe(false);
    expect(corpo.code).toBe("FORBIDDEN");
    expect(JSON.stringify(corpo)).not.toContain("CAPABILITY_MISSING");
  });

  it("capability desconhecida ⇒ DENY", async () => {
    const resposta = await avaliarRequisicaoAutorizacao(
      requisicao({ ...corpoOk, capability: "capability.inventada" }, "Bearer jwt"),
      deps(cenarioPermitido)
    );
    const corpo = (await resposta.json()) as { allowed: boolean };
    expect(corpo.allowed).toBe(false);
  });

  it("alvo global/sintético ⇒ DENY (NOT_FOUND, sem vazar existência)", async () => {
    const resposta = await avaliarRequisicaoAutorizacao(
      requisicao({ ...corpoOk, target: { type: "cycle", id: "global" } }, "Bearer jwt"),
      deps(cenarioPermitido)
    );
    const corpo = (await resposta.json()) as { allowed: boolean; code: string };
    expect(corpo.allowed).toBe(false);
    expect(corpo.code).toBe("NOT_FOUND");
  });

  it("organização spoofada (sem membership ativa) ⇒ DENY", async () => {
    const resposta = await avaliarRequisicaoAutorizacao(
      requisicao({ ...corpoOk, organization_id: "org-2" }, "Bearer jwt"),
      deps(cenarioPermitido)
    );
    const corpo = (await resposta.json()) as { allowed: boolean; code: string };
    expect(corpo.allowed).toBe(false);
    expect(corpo.code).toBe("FORBIDDEN");
  });

  it("recurso de outro tenant/inexistente ⇒ DENY NOT_FOUND", async () => {
    const outroTenant = await avaliarRequisicaoAutorizacao(
      requisicao(corpoOk, "Bearer jwt"),
      deps({ ...cenarioPermitido, recurso: { kind: "collaborator", id: COL, organizationId: "org-2" } })
    );
    const corpoOutro = (await outroTenant.json()) as { allowed: boolean; code: string };
    expect(corpoOutro.allowed).toBe(false);
    expect(corpoOutro.code).toBe("NOT_FOUND");

    const inexistente = await avaliarRequisicaoAutorizacao(
      requisicao(corpoOk, "Bearer jwt"),
      deps({ ...cenarioPermitido, recurso: null })
    );
    const corpoInexistente = (await inexistente.json()) as { allowed: boolean; code: string };
    expect(corpoInexistente.allowed).toBe(false);
    expect(corpoInexistente.code).toBe("NOT_FOUND");
  });

  it("data de negócio ISO válida (string JSON) ⇒ não nega por formato (achado 2)", async () => {
    for (const iso of ["2026-02-15", "2026-02-15T13:45:00Z"]) {
      const resposta = await avaliarRequisicaoAutorizacao(
        requisicao({ ...corpoOk, data_negocio: iso }, "Bearer jwt"),
        deps(cenarioPermitido)
      );
      const corpo = (await resposta.json()) as { allowed: boolean; code?: string };
      expect(corpo.allowed).toBe(true);
    }
  });

  it("data de negócio inválida ⇒ DENY (validação server-side — D21)", async () => {
    for (const invalida of ["nao-e-data", "2026-02-30", 1750000000000, { d: "2026-02-15" }]) {
      const resposta = await avaliarRequisicaoAutorizacao(
        requisicao({ ...corpoOk, data_negocio: invalida }, "Bearer jwt"),
        deps(cenarioPermitido)
      );
      const corpo = (await resposta.json()) as { allowed: boolean; code: string };
      expect(corpo.allowed).toBe(false);
      expect(corpo.code).toBe("FORBIDDEN");
    }
  });

  it("resolve a identidade a partir do JWT (o corpo não participa)", async () => {
    const resolveCaller = vi.fn(async () => USER);
    await avaliarRequisicaoAutorizacao(
      requisicao(corpoOk, "Bearer jwt-do-usuario"),
      deps(cenarioPermitido, resolveCaller)
    );
    expect(resolveCaller).toHaveBeenCalledWith("Bearer jwt-do-usuario");
  });
});
