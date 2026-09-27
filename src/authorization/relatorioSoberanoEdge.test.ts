import { describe, expect, it, vi } from "vitest";
import { avaliacoes, type DepsAvaliacoes } from "../../supabase/functions/avaliacoes/core.ts";
import { validarEntradaAvaliacao } from "../infrastructure/supabase/avaliacoes/contrato.ts";
import fonteEdge from "../../supabase/functions/avaliacoes/index.ts?raw";

const ORG = "11111111-1111-4111-8111-111111111111";
const CYCLE = "55555555-5555-4555-8555-555555555555";
const COL = "33333333-3333-4333-8333-333333333333";
const CALLER = "77777777-7777-4777-8777-777777777777";

function request(body: unknown) {
  return new Request("http://localhost/functions/v1/avaliacoes", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer ok" },
    body: JSON.stringify(body),
  });
}

describe("#400-A — report.listar", () => {
  it("o loader de collaborator não depende de collaborators.status", () => {
    const bloco = fonteEdge.match(/if \(target\.type === "collaborator"\) \{[\s\S]*?ownerCollaboratorId: data\.id,[\s\S]*?\} as RecursoSoberanoCarregado;/)?.[0];
    expect(bloco).toBeDefined();
    expect(bloco).toContain('.select("id, organization_id")');
    expect(bloco).not.toContain("status: data.status");
  });

  it("requer ciclo UUID e não aceita alvo do cliente", () => {
    expect(validarEntradaAvaliacao({ organization_id: ORG, operacao: "report.listar", cycle_id: CYCLE }).ok).toBe(true);
    expect(validarEntradaAvaliacao({ organization_id: ORG, operacao: "report.listar" }).ok).toBe(false);
    expect(validarEntradaAvaliacao({ organization_id: ORG, operacao: "report.listar", cycle_id: CYCLE, alvo: { type: "collaborator", id: COL } }).ok).toBe(false);
  });

  function makeDeps(allowed: boolean): { deps: DepsAvaliacoes; execute: ReturnType<typeof vi.fn> } {
    const execute = vi.fn(async () => ({
      data: { organizationId: ORG, cycleId: CYCLE, scope: "DESCENDANTS" as const, colaboradores: [{ collaboratorId: COL, nome: "Pessoa sintética", positionId: "88888888-8888-4888-8888-888888888888", status: null, evaluationId: null, evaluationStatus: null, notaMedia: null, dataConclusao: null }] },
      error: null,
    }));
    return {
      execute,
      deps: {
        resolveCaller: async () => CALLER,
        avaliarAutorizacao: async () => ({ allowed: false }),
        avaliarRelatorio: async () => ({ allowed }),
        executarRpc: async () => ({ data: null, error: null }),
        executarRelatorio: execute,
      },
    };
  }

  it("ALLOW devolve somente a projeção server-side UUID-first", async () => {
    const { deps, execute } = makeDeps(true);
    const response = await avaliacoes(request({ organization_id: ORG, operacao: "report.listar", cycle_id: CYCLE }), deps);
    expect(response.status).toBe(200);
    expect(execute).toHaveBeenCalledWith({ authUserId: CALLER, organizationId: ORG, cycleId: CYCLE });
    expect((await response.json()).resultado.colaboradores[0].collaboratorId).toBe(COL);
  });

  it("DENY sem capability/scope não executa leitura", async () => {
    const { deps, execute } = makeDeps(false);
    const response = await avaliacoes(request({ organization_id: ORG, operacao: "report.listar", cycle_id: CYCLE }), deps);
    expect(response.status).toBe(403);
    expect(execute).not.toHaveBeenCalled();
  });
});
