import { describe, expect, it } from "vitest";
import rota from "../routes/AppRoutes.tsx?raw";
import ficha from "./ColaboradorDetalhePage.tsx?raw";
import jornada from "./AvaliacaoUuidPage.tsx?raw";
import acao from "./colaboradorDetalheAvaliacaoAcao.ts?raw";

describe("jornada canônica de avaliação por UUID", () => {
  it("parte da ficha UUID, DESCOBRE a avaliação no ciclo ativo e preserva as três rotas", () => {
    // A ação soberana NÃO é decidida na tela: a ficha chama a descoberta e
    // traduz o payload mínimo (id/status/podeEditar) em rótulo + destino.
    expect(ficha).toContain("descobrirAvaliacaoDoColaboradorNoCiclo(");
    expect(ficha).toContain("obterCicloAtivo(organizacaoAtivaId)");
    expect(ficha).toContain("acaoDaAvaliacaoDoColaborador(");
    expect(rota).toContain('path="/colaborador/:collaboratorId/avaliacoes/nova"');
    expect(rota).toContain('path="/colaborador/:collaboratorId/avaliacoes/:evaluationId/editar"');
    expect(rota).toContain('path="/colaborador/:collaboratorId/avaliacoes/:evaluationId"');
  });

  it("a ficha é FAIL-CLOSED: só usa o payload autorizado e nunca cai para o acervo legado", () => {
    expect(ficha).toContain("descoberta.ok && descoberta.data");
    expect(ficha).toContain("? acaoDaAvaliacaoDoColaborador(");
    // A descoberta não pode ser decidida por capability lida no cliente.
    expect(ficha).not.toContain("listarCapabilitiesEfetivas");
    expect(ficha).not.toContain('capabilities.includes("evaluation.create")');
    // A ação usa apenas as rotas UUID.
    expect(acao).toContain("/avaliacoes");
    expect(acao).toContain("podeEditar");
    // Nenhuma resolução de identidade local/matrícula no CÓDIGO do tradutor.
    expect(acao).not.toMatch(/getColaboradorByMatricula|Number\(|feedbackStorage/);
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
