import { describe, expect, it, vi } from "vitest";
import { criarRepositorioRelatoriosSoberanos } from "./repositorioRelatoriosSoberanos";

type ClienteTeste = { functions: { invoke: ReturnType<typeof vi.fn> } };

function clienteComResposta(data: unknown, error: unknown = null): ClienteTeste {
  return { functions: { invoke: vi.fn().mockResolvedValue({ data, error }) } };
}

describe("repositorioRelatoriosSoberanos", () => {
  it("envia somente tenant e ciclo e preserva a projeção UUID-first", async () => {
    const cliente = clienteComResposta({
      ok: true, operacao: "report.listar", resultado: {
        organizationId: "org-1", cycleId: "cycle-1", scope: "DESCENDANTS",
        colaboradores: [{ collaboratorId: "collab-1", nome: "Felipe", positionId: "position-1", status: "ATIVO", evaluationId: null, evaluationStatus: null, notaMedia: null, dataConclusao: null }],
      },
    });
    const resultado = await criarRepositorioRelatoriosSoberanos(cliente as never).listar("org-1", "cycle-1");
    expect(resultado.ok).toBe(true);
    expect(cliente.functions.invoke).toHaveBeenCalledWith("avaliacoes", { body: { organization_id: "org-1", operacao: "report.listar", cycle_id: "cycle-1" } });
    expect(resultado.ok && resultado.data.colaboradores[0].collaboratorId).toBe("collab-1");
  });

  it("falha fechado quando a resposta é de outro tenant ou ciclo", async () => {
    const cliente = clienteComResposta({ ok: true, operacao: "report.listar", resultado: { organizationId: "other", cycleId: "cycle-1", scope: "DESCENDANTS", colaboradores: [] } });
    await expect(criarRepositorioRelatoriosSoberanos(cliente as never).listar("org-1", "cycle-1")).resolves.toMatchObject({ ok: false, code: "FORBIDDEN" });
  });

  it("preserva estado sem avaliação como nulo", async () => {
    const cliente = clienteComResposta({ ok: true, operacao: "report.listar", resultado: { organizationId: "org-1", cycleId: "cycle-1", scope: "DESCENDANTS", colaboradores: [{ collaboratorId: "c", nome: "João", positionId: "p", evaluationId: null, evaluationStatus: null, notaMedia: null, dataConclusao: null }] } });
    const resultado = await criarRepositorioRelatoriosSoberanos(cliente as never).listar("org-1", "cycle-1");
    expect(resultado.ok && resultado.data.colaboradores[0]).toMatchObject({ collaboratorId: "c", evaluationId: null, notaMedia: null });
  });
});
