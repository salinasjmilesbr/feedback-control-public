import { describe, expect, it, vi } from "vitest";
import { colaboradores, type DepsColaboradores } from "../../supabase/functions/colaboradores/core.ts";
import edgeFonte from "../../supabase/functions/colaboradores/index.ts?raw";

const ORG = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ATOR = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const POSITION = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const RESPONSIBILITY = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

function requisicao(corpo: Record<string, unknown>): Request {
  return new Request("http://localhost/functions/v1/colaboradores", {
    method: "POST",
    headers: { Authorization: "Bearer jwt-sintetico", "Content-Type": "application/json" },
    body: JSON.stringify(corpo),
  });
}

function deps(opcoes: {
  readonly capabilities?: readonly string[];
  readonly rpcData?: unknown;
  readonly rpcError?: { code?: string; message?: string };
} = {}) {
  const executarRpc = vi.fn<DepsColaboradores["executarRpc"]>(async () => ({
    data: opcoes.rpcData ?? RESPONSIBILITY,
    error: opcoes.rpcError ?? null,
  }));
  const d: DepsColaboradores = {
    resolveCaller: async () => ATOR,
    resolverOrganizacoesDoAtor: async () => [ORG],
    colaboradorPertenceAoAtor: async () => true,
    resolverMatricula: async () => null,
    resolverColaboradorVinculado: async () => null,
    avaliarAutorizacao: async () => ({ permitido: false, code: "FORBIDDEN" }),
    resolverCapabilitiesEfetivas: async () =>
      (opcoes.capabilities ?? ["org.structure.manage"]).map((capability_code) => ({
        capability_code,
      })),
    executarRpc,
  };
  return { d, executarRpc };
}

describe("F6-A22 P3 — fronteira Edge estrutural", () => {
  it("deriva o ator do JWT e encaminha criar com org.structure.manage", async () => {
    const { d, executarRpc } = deps();
    const resposta = await colaboradores(
      requisicao({
        organization_id: ORG,
        operacao: "estrutura.people_management.criar",
        operation_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
        position_id: POSITION,
        responsibility_code: "PEOPLE_MANAGEMENT",
        valid_from: "2026-01-01T00:00:00Z",
        valid_to: null,
        actor_user_profile_id: "ffffffff-ffff-4fff-8fff-ffffffffffff",
      }),
      d
    );

    expect(resposta.status).toBe(400);
    expect(executarRpc).not.toHaveBeenCalled();

    const semIdentidadeNoCorpo = await colaboradores(
      requisicao({
        organization_id: ORG,
        operacao: "estrutura.people_management.criar",
        operation_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
        position_id: POSITION,
        responsibility_code: "PEOPLE_MANAGEMENT",
        valid_from: "2026-01-01T00:00:00Z",
        valid_to: null,
      }),
      d
    );
    expect(semIdentidadeNoCorpo.status).toBe(200);
    expect(executarRpc).toHaveBeenCalledTimes(1);
    const contexto = executarRpc.mock.calls[0]![1];
    expect(contexto.actorUserProfileId).toBe(ATOR);
    expect(executarRpc.mock.calls[0]![0].operacao).toBe("estrutura.people_management.criar");
  });

  it("encaminha encerrar com expected_version e consulta sem abrir atalho de cliente", async () => {
    const { d, executarRpc } = deps({ rpcData: [RESPONSIBILITY] });
    const encerrar = await colaboradores(
      requisicao({
        organization_id: ORG,
        operacao: "estrutura.people_management.encerrar",
        operation_id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeef",
        responsibility_id: RESPONSIBILITY,
        valid_to: "2026-09-01T00:00:00Z",
        expected_version: 0,
      }),
      d
    );
    expect(encerrar.status).toBe(200);
    expect(executarRpc.mock.calls[0]![0].operacao).toBe("estrutura.people_management.encerrar");
    if (executarRpc.mock.calls[0]![0].operacao === "estrutura.people_management.encerrar") {
      expect(executarRpc.mock.calls[0]![0].entrada.expected_version).toBe(0);
    }

    executarRpc.mockClear();
    const consultar = await colaboradores(
      requisicao({ organization_id: ORG, operacao: "estrutura.people_management.consultar" }),
      d
    );
    expect(consultar.status).toBe(200);
    expect(executarRpc.mock.calls[0]![0].operacao).toBe("estrutura.people_management.consultar");
  });

  it("nega sem org.structure.manage antes da RPC", async () => {
    const { d, executarRpc } = deps({ capabilities: ["org.catalog.manage"] });
    const resposta = await colaboradores(
      requisicao({ organization_id: ORG, operacao: "estrutura.people_management.consultar" }),
      d
    );
    expect(resposta.status).toBe(403);
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("mantém o mapeamento Edge para as RPCs P3 e o ator verificado", () => {
    expect(edgeFonte).toContain('admin.rpc("estrutura_responsabilidade_criar"');
    expect(edgeFonte).toContain('admin.rpc("estrutura_responsabilidade_revogar"');
    expect(edgeFonte).toContain('admin.rpc("estrutura_responsabilidades_consultar"');
    expect(edgeFonte).toContain("p_actor_user_profile_id: ator");
  });
});
