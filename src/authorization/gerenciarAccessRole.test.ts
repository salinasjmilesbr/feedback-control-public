import { describe, expect, it, vi } from "vitest";
import {
  gerenciarAcessoRole,
  type DepsGerenciarAcessoRole,
} from "../../supabase/functions/gerenciar-access-role/core.ts";

/**
 * F5-04 (D16): prova do fluxo de produção com IDENTIDADE × EXECUÇÃO separadas.
 *
 * Regressão que este teste detecta: propagar o JWT do usuário ao RPC faria o
 * PostgREST assumir a role `authenticated` e perder o EXECUTE de service_role.
 * O fluxo correto resolve a identidade via auth.getUser e executa o RPC com
 * service_role passando o user.id VERIFICADO (nunca o JWT, nunca actor_id).
 */

const MEMBERSHIP = "11111111-1111-4111-8111-111111111111";
const ROLE = "22222222-2222-4222-8222-222222222222";
const ACTOR = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

function makeDeps(
  overrides?: Partial<DepsGerenciarAcessoRole>
): DepsGerenciarAcessoRole {
  return {
    resolveCaller: vi.fn(async () => ACTOR),
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

describe("F5-04 D16 — identidade × execução privilegiada separadas", () => {
  it("resolve a identidade via auth.getUser e executa o RPC com o user.id (sem JWT, sem actor_id)", async () => {
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
    // O RPC é chamado com o user.id VERIFICADO — não com o JWT (que rebaixaria
    // a role para authenticated) e não com um actor_id do corpo.
    expect(deps.executarRpc).toHaveBeenCalledWith(
      "grant",
      MEMBERSHIP,
      ROLE,
      ACTOR
    );
  });

  it("revoke propaga a ação e o ator verificado", async () => {
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
      "revoke",
      MEMBERSHIP,
      ROLE,
      ACTOR
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

  it("erro do RPC (sem autoridade/self-escalation/cross-tenant) ⇒ 403 fail-closed", async () => {
    const deps = makeDeps({
      executarRpc: vi.fn(async () => ({
        code: "F5-04",
        message: "ator sem autoridade administrativa",
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
