import { describe, expect, it } from "vitest";
import rota from "../routes/AppRoutes.tsx?raw";
import ficha from "./ColaboradorDetalhePage.tsx?raw";
import jornada from "./AvaliacaoUuidPage.tsx?raw";

describe("jornada canônica de avaliação por UUID", () => {
  it("parte da ficha UUID, consulta ciclo ativo soberano e preserva três rotas navegáveis", () => {
    expect(ficha).toContain('capabilities.includes("evaluation.create")');
    expect(ficha).toContain("obterCicloAtivo(organizacaoAtivaId)");
    expect(ficha).toContain("/avaliacoes/nova");
    expect(rota).toContain('path="/colaborador/:collaboratorId/avaliacoes/nova"');
    expect(rota).toContain('path="/colaborador/:collaboratorId/avaliacoes/:evaluationId/editar"');
    expect(rota).toContain('path="/colaborador/:collaboratorId/avaliacoes/:evaluationId"');
  });

  it("cria com ciclo e colaborador UUID, edita por catálogo soberano e conclui no servidor", () => {
    expect(jornada).toContain("criarAvaliacaoPorUuidSoberano({");
    expect(jornada).toContain("evaluatedCollaboratorId: collaboratorId");
    expect(jornada).toContain("carregarPainelSoberano(");
    expect(jornada).toContain("gravarNotasPorIdSoberanas(");
    expect(jornada).toContain("concluirAvaliacaoSoberana(");
    expect(jornada).toContain("lerStatusSoberano(");
    expect(jornada).not.toMatch(/feedbackStorage|localStorage|matriculaAvaliado|getCicloAtivo/);
  });
});
