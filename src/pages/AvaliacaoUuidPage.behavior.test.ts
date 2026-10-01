import { describe, expect, it, vi } from "vitest";
import type { PainelParticipante } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import { concluirFormularioAvaliacaoUuid, salvarFormularioAvaliacaoUuid, type OperacoesFormularioAvaliacaoUuid } from "./avaliacaoUuidFormulario";

const ORG = "11111111-1111-4111-8111-111111111111";
const EVAL = "22222222-2222-4222-8222-222222222222";
const TARGET = "33333333-3333-4333-8333-333333333333";
const SUB = "44444444-4444-4444-8444-444444444444";

function painel(overrides: Partial<PainelParticipante> = {}): PainelParticipante {
  return {
    evaluationId: EVAL,
    organizationId: ORG,
    cycleId: "55555555-5555-4555-8555-555555555555",
    cycleAno: 2026,
    cycleNumero: 1,
    configVersionId: "66666666-6666-4666-8666-666666666666",
    status: "RASCUNHO",
    evaluatedCollaboratorId: TARGET,
    meusPapeis: ["GESTAO_DIRETA"],
    participanteOcorrenciaId: "77777777-7777-4777-8777-777777777777",
    participanteRoleType: "GESTAO_DIRETA",
    participanteVigencia: { validFrom: "2026-01-01T00:00:00Z", validTo: null },
    criterios: [{ criterionId: "88888888-8888-4888-8888-888888888888", code: "C1", name: "Critério", position: 1 }],
    subcriterios: [{ subcriterionId: SUB, code: "S1", name: "Subcritério", position: 1, criterionCode: "C1" }],
    minhasNotas: [{ subcriterionId: SUB, nota: 2 }],
    meusComentarios: [{ escopo: "FINAL", criterionId: null, texto: "Comentário inicial" }],
    papeisComFeedbackFinal: ["GESTAO_DIRETA"],
    ...overrides,
  };
}

function ops(overrides: Partial<OperacoesFormularioAvaliacaoUuid> = {}) {
  return {
    gravarNotas: vi.fn(async () => ({ ok: true as const, data: 1 })),
    gravarObservacoes: vi.fn(async () => ({ ok: true as const, data: 0 })),
    gravarComentarioFinal: vi.fn(async () => ({ ok: true as const, data: null })),
    carregarPainel: vi.fn(async () => ({ ok: true as const, data: painel() })),
    ...overrides,
  } satisfies OperacoesFormularioAvaliacaoUuid;
}

describe("AvaliacaoUuidPage: comportamento do formulário soberano", () => {
  it("salvar e depois concluir sem novas alterações não reenvia notas nem comentários", async () => {
    const original = painel();
    const atualizado = painel({
      minhasNotas: [{ subcriterionId: SUB, nota: 4 }],
      meusComentarios: [{ escopo: "FINAL", criterionId: null, texto: "Comentário novo" }],
    });
    const operacoes = ops({ carregarPainel: vi.fn(async () => ({ ok: true as const, data: atualizado })) });
    const valores = { organizationId: ORG, evaluationId: EVAL, notas: { [SUB]: "4" }, observacoes: {}, comentarioFinal: "Comentário novo", operacoes };

    const salvo = await salvarFormularioAvaliacaoUuid({ ...valores, painel: original });
    expect(salvo.ok).toBe(true);
    expect(operacoes.gravarNotas).toHaveBeenCalledTimes(1);
    expect(operacoes.gravarComentarioFinal).toHaveBeenCalledTimes(1);

    const concluido = vi.fn(async () => ({ ok: true as const, data: null }));
    const resultadoConclusao = await concluirFormularioAvaliacaoUuid({ ...valores, painel: salvo.painel, concluir: concluido });
    expect(resultadoConclusao.ok).toBe(true);
    expect(operacoes.gravarNotas).toHaveBeenCalledTimes(1);
    expect(operacoes.gravarComentarioFinal).toHaveBeenCalledTimes(1);
    expect(concluido).toHaveBeenCalledTimes(1);
  });

  it("recusa esvaziar comentário persistido e não chama operações de escrita", async () => {
    const operacoes = ops();
    const resultado = await salvarFormularioAvaliacaoUuid({
      organizationId: ORG, evaluationId: EVAL, painel: painel(), notas: { [SUB]: "2" },
      observacoes: {}, comentarioFinal: "   ", operacoes,
    });
    expect(resultado.ok).toBe(false);
    expect(resultado.erro).toContain("não permite remover comentários");
    expect(resultado.painel.meusComentarios[0]?.texto).toBe("Comentário inicial");
    expect(operacoes.gravarNotas).not.toHaveBeenCalled();
    expect(operacoes.gravarComentarioFinal).not.toHaveBeenCalled();
  });

  it("exibe DENY de escrita, recarrega o painel e não tenta concluir", async () => {
    const operacoes = ops({
      gravarNotas: vi.fn(async () => ({ ok: false as const, erro: "Acesso negado pela autorização." })),
      carregarPainel: vi.fn(async () => ({ ok: true as const, data: painel() })),
    });
    const concluir = vi.fn(async () => ({ ok: true as const, data: null }));
    const resultado = await concluirFormularioAvaliacaoUuid({
      organizationId: ORG, evaluationId: EVAL, painel: painel(), notas: { [SUB]: "5" },
      observacoes: {}, comentarioFinal: "Comentário inicial", operacoes, concluir,
    });
    expect(resultado.ok).toBe(false);
    expect(resultado.erro).toContain("Acesso negado");
    expect(operacoes.carregarPainel).toHaveBeenCalledTimes(1);
    expect(concluir).not.toHaveBeenCalled();
  });

  it("bloqueia nova escrita/conclusão se a referência não pôde ser sincronizada", async () => {
    const operacoes = ops({
      carregarPainel: vi.fn(async () => ({ ok: false as const, erro: "Leitura indisponível." })),
    });
    const concluir = vi.fn(async () => ({ ok: true as const, data: null }));
    const resultado = await concluirFormularioAvaliacaoUuid({
      organizationId: ORG, evaluationId: EVAL, painel: painel(), notas: { [SUB]: "5" },
      observacoes: {}, comentarioFinal: "Comentário inicial", operacoes, concluir,
    });
    expect(resultado.ok).toBe(false);
    expect(resultado.sincronizado).toBe(false);
    expect(resultado.erro).toBe("Leitura indisponível.");
    expect(concluir).not.toHaveBeenCalled();
  });
});
