import { describe, expect, it, vi } from "vitest";
import {
  gerenciarAcessoRole,
  type DepsGerenciarAcessoRole,
} from "../../supabase/functions/gerenciar-access-role/core.ts";

/**
 * F5-04 (D16): prova do fluxo de produção da identidade soberana — do JWT do
 * usuário autenticado até `auth.uid()` dentro do RPC, SEM depender de
 * `set_config('request.jwt.claim.sub', ...)` (simulação privilegiada) e SEM
 * aceitar `actor_id` do cliente.
 */

const MEMBERSHIP = "11111111-1111-4111-8111-111111111111";
const ROLE = "22222222-2222-4222-8222-222222222222";

function makeDeps(
  overrides?: Partial<DepsGerenciarAcessoRole>
): DepsGerenciarAcessoRole {
  return {
    resolveCaller: vi.fn(async () => "user-soberano-123"),
    executarRpc: vi.fn(async () => null),
    ...overrides,
  };
}

function makeRequest(body?: unknown, authHeader?: string): Request {
  const headers = new Headers();
  if (authHeader) headers.set("Authorization", authHeader);
  return new Request("http://localhost/fn", {
    method: "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

describe("F5-04 D16 — fluxo de produção da identidade soberana", () => {
  it("propaga o MESMO JWT ao RPC (auth.uid) sem aceitar actor_id", async () => {
    const deps = makeDeps();
    const res = await gerenciarAcessoRole(
      makeRequest(
        { membership_id: MEMBERSHIP, access_role_id: ROLE, action: "grant" },
        "Bearer jwt-do-usuario"
      ),
      deps
    );

    expect(res.status).toBe(200);
    expect(deps.resolveCaller).toHaveBeenCalledWith("Bearer jwt-do-usuario");
    // O JWT é preservado na chamada ao RPC (auth.uid() = usuário autenticado),
    // nunca substituído por um actor_id vindo do corpo.
    expect(deps.executarRpc).toHaveBeenCalledWith(
      "Bearer jwt-do-usuario",
      "grant",
      MEMBERSHIP,
      ROLE
    );
  });

  it("revoke propaga a ação corretamente", async () => {
    const deps = makeDeps();
    const res = await gerenciarAcessoRole(
      makeRequest(
        { membership_id: MEMBERSHIP, access_role_id: ROLE, action: "revoke" },
        "Bearer jwt-do-usuario"
      ),
      deps
    );

    expect(res.status).toBe(200);
    expect(deps.executarRpc).toHaveBeenCalledWith(
      "Bearer jwt-do-usuario",
      "revoke",
      MEMBERSHIP,
      ROLE
    );
  });

  it("sem Authorization ⇒ 401 (identidade soberana ausente)", async () => {
    const deps = makeDeps();
    const res = await gerenciarAcessoRole(
      makeRequest({
        membership_id: MEMBERSHIP,
        access_role_id: ROLE,
        action: "grant",
      }),
      deps
    );

    expect(res.status).toBe(401);
    expect(deps.resolveCaller).not.toHaveBeenCalled();
    expect(deps.executarRpc).not.toHaveBeenCalled();
  });

  it("JWT inválido (getUser falha) ⇒ 401", async () => {
    const deps = makeDeps({ resolveCaller: vi.fn(async () => null) });
    const res = await gerenciarAcessoRole(
      makeRequest(
        { membership_id: MEMBERSHIP, access_role_id: ROLE, action: "grant" },
        "Bearer jwt-invalido"
      ),
      deps
    );

    expect(res.status).toBe(401);
    expect(deps.executarRpc).not.toHaveBeenCalled();
  });

  it("actor_id no corpo é rejeitado (nunca confiado ao cliente)", async () => {
    const deps = makeDeps();
    const res = await gerenciarAcessoRole(
      makeRequest(
        {
          membership_id: MEMBERSHIP,
          access_role_id: ROLE,
          action: "grant",
          actor_id: "33333333-3333-4333-8333-333333333333",
        },
        "Bearer jwt-do-usuario"
      ),
      deps
    );

    expect(res.status).toBe(400);
    expect(deps.executarRpc).not.toHaveBeenCalled();
  });

  it("erro do RPC (self-escalation/cross-tenant) ⇒ 403 fail-closed", async () => {
    const deps = makeDeps({
      executarRpc: vi.fn(async () => ({
        code: "F5-04",
        message: "self-escalation negada",
      })),
    });
    const res = await gerenciarAcessoRole(
      makeRequest(
        { membership_id: MEMBERSHIP, access_role_id: ROLE, action: "grant" },
        "Bearer jwt-do-usuario"
      ),
      deps
    );

    expect(res.status).toBe(403);
  });
});
