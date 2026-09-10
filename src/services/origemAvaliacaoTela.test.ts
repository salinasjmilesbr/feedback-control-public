import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { criarArmazenamentoMemoria } from "../infrastructure/supabase/avaliacoes/cutover";
import { criarCutoverAvaliacoes } from "./avaliacoesSoberanas/cutoverAvaliacoesService";
import type { RepositorioAvaliacoes } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import { ehAvaliacaoNova, lerAvaliacaoParaTela } from "./origemAvaliacaoTela";

/**
 * F5-06 (Issue #103) — ORIGEM da avaliação na tela.
 *
 * O acervo legado (localStorage) e o novo (PostgreSQL) convivem, mas NUNCA se
 * misturam: a origem é decidida ESTRUTURALMENTE pelo id (id técnico = banco) e,
 * quando o id é técnico, a leitura SÓ pode vir do banco — sem fallback local
 * (fail-closed, D12/§11.3).
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const AVALIACAO = "33333333-3333-4333-8333-333333333333";
const OCORRENCIA = "55555555-5555-4555-8555-555555555555";
const CHAVE_LEGADO = "feedback-control-feedbacks";

function repositorioFalso(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): RepositorioAvaliacoes {
  const base: RepositorioAvaliacoes = {
    criar: async () => ({ ok: true, data: AVALIACAO }),
    ler: async () => ({ ok: true, data: null }),
    gravarNotas: async () => ({ ok: true, data: null }),
    gravarComentario: async () => ({ ok: true, data: null }),
    concluir: async () => ({ ok: true, data: null }),
    reabrir: async () => ({ ok: true, data: null }),
    cancelar: async () => ({ ok: true, data: null }),
    realinharParticipantes: async () => ({ ok: true, data: 0 }),
    transparenciaDoAvaliado: async () => {
      throw new Error("não usado neste teste");
    },
    painelParticipante: async () => ({
      ok: true,
      data: {
        evaluationId: AVALIACAO,
        organizationId: ORG,
        cycleId: "22222222-2222-4222-8222-222222222222",
        cycleAno: 2026,
        cycleNumero: 1,
        configVersionId: "77777777-7777-4777-8777-777777777777",
        status: "RASCUNHO",
        evaluatedCollaboratorId: "44444444-4444-4444-8444-444444444444",
        meusPapeis: ["GESTAO_CADEIA"],
        participanteOcorrenciaId: OCORRENCIA,
        participanteRoleType: "GESTAO_CADEIA",
        participanteVigencia: {
          validFrom: "2026-01-01T00:00:00Z",
          validTo: null,
        },
        criterios: [
          { criterionId: "c-1", code: "c1", name: "Criterio", position: 0 },
        ],
        subcriterios: [
          {
            subcriterionId: "66666666-6666-4666-8666-666666666666",
            code: "s1",
            name: "Sub",
            position: 0,
            criterionCode: "c1",
          },
        ],
        minhasNotas: [],
        meusComentarios: [],
        papeisComFeedbackFinal: [],
      },
    }),
    resolverCiclo: async () => ({
      ok: true,
      data: "22222222-2222-4222-8222-222222222222",
    }),
  };
  return { ...base, ...comportamentos };
}

function deps(comportamentos: Partial<RepositorioAvaliacoes> = {}) {
  const repositorio = repositorioFalso(comportamentos);
  return {
    criarCutover: () =>
      criarCutoverAvaliacoes({
        repositorio,
        armazenamento: criarArmazenamentoMemoria(),
      }),
  };
}

describe("ehAvaliacaoNova (classificação estrutural)", () => {
  it.each([
    [AVALIACAO, true],
    ["avaliacao-local-1", false],
    ["", false],
    [undefined, false],
    ["   ", false],
  ] as const)("id %s ⇒ nova=%s", (id, esperado) => {
    expect(ehAvaliacaoNova(id)).toBe(esperado);
  });
});

describe("lerAvaliacaoParaTela", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      CHAVE_LEGADO,
      JSON.stringify([{ id: "avaliacao-legada", status: "RASCUNHO" }])
    );
  });

  it("id local é lido do acervo LEGADO (somente leitura)", async () => {
    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: "avaliacao-legada" },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("LEGADO_LOCAL");
    expect(resultado.leitura?.painel).toBeUndefined();
  });

  it("id local inexistente devolve leitura vazia (sem inventar registro)", async () => {
    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: "nao-existe" },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura).toBeNull();
  });

  it("id técnico é lido do BANCO e nunca do legado", async () => {
    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: AVALIACAO },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("POSTGRES");
    expect(resultado.leitura?.painel?.participanteOcorrenciaId).toBe(OCORRENCIA);
  });

  it("id técnico com leitura recusada NÃO cai para o legado (fail-closed)", async () => {
    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: AVALIACAO },
      deps({
        painelParticipante: async () => ({
          ok: false,
          error: { code: "FORBIDDEN", message: "negado" },
        }),
      })
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erro).toBeTruthy();
  });

  it("sem caminho soberano configurado, id técnico é recusado", async () => {
    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: AVALIACAO },
      { criarCutover: () => null }
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erro).toContain("PostgreSQL");
  });
});
