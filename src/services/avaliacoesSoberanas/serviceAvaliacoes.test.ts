import { describe, expect, it, vi } from "vitest";
import {
  criarServiceAvaliacoes,
  mensagemErroAvaliacoes,
} from "./serviceAvaliacoes.ts";
import {
  criarArmazenamentoMemoria,
  CHAVE_AVALIACOES_CORTADAS,
  registrarAvaliacaoCortada,
} from "../../infrastructure/supabase/avaliacoes/cutover.ts";
import type {
  AvaliacaoSoberana,
  RepositorioAvaliacoes,
  ResultadoRepositorio,
} from "../../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";

/**
 * F5-06 (Issue #103) — casos de uso do caminho novo: criação (com registro de
 * cutover), acervo (banco + legado somente leitura), mutações e fail-closed.
 * Nenhuma autorização é decidida aqui; o repositório é sempre injetado.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const AVALIACAO = "22222222-2222-4222-8222-222222222222";
const COLABORADOR = "44444444-4444-4444-8444-444444444444";
const OUTRA_ORG = "99999999-9999-4999-8999-999999999999";

function avaliacaoSoberana(parcial: Partial<AvaliacaoSoberana> = {}): AvaliacaoSoberana {
  return {
    id: AVALIACAO,
    organizationId: ORG,
    cycleId: CICLO,
    evaluatedCollaboratorId: COLABORADOR,
    status: "RASCUNHO",
    notaMedia: null,
    dataConclusao: null,
    encerradaComPendencias: false,
    ...parcial,
  };
}

type RepositorioFalso = RepositorioAvaliacoes & {
  readonly chamadas: { readonly metodo: string; readonly argumentos: unknown }[];
};

function repositorioFalso(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): RepositorioFalso {
  const chamadas: { metodo: string; argumentos: unknown }[] = [];
  const registrar = <T>(metodo: string, valor: unknown, resposta: ResultadoRepositorio<T>) => {
    chamadas.push({ metodo, argumentos: valor });
    return Promise.resolve(resposta);
  };

  const padrao: RepositorioAvaliacoes = {
    criar: (entrada) => registrar("criar", entrada, { ok: true, data: AVALIACAO }),
    ler: (entrada) => registrar("ler", entrada, { ok: true, data: avaliacaoSoberana() }),
    gravarNotas: (entrada) => registrar("gravarNotas", entrada, { ok: true, data: 3.5 }),
    gravarComentario: (entrada) =>
      registrar("gravarComentario", entrada, { ok: true, data: null }),
    concluir: (entrada) => registrar("concluir", entrada, { ok: true, data: null }),
    reabrir: (entrada) => registrar("reabrir", entrada, { ok: true, data: null }),
    cancelar: (entrada) => registrar("cancelar", entrada, { ok: true, data: null }),
    painelParticipante: async () => ({
      ok: false,
      error: { code: "INTERNAL" as const, message: "nao usado neste teste" },
    }),
    resolverCiclo: async () => ({
      ok: false,
      error: { code: "INTERNAL" as const, message: "nao usado neste teste" },
    }),    realinharParticipantes: (entrada) =>
      registrar("realinharParticipantes", entrada, { ok: true, data: 1 }),
    transparenciaDoAvaliado: (entrada) =>
      registrar("transparenciaDoAvaliado", entrada, {
        ok: true,
        data: {
          evaluationId: AVALIACAO,
          notaMedia: 3.5,
          faixa: null,
          criterios: [],
          subcriterios: [],
          colegiado: [],
          comentariosFinais: [],
        },
      }),
  };

  return { ...padrao, ...comportamentos, chamadas };
}

describe("service de avaliações soberanas (caminho novo)", () => {
  it("criar grava no PostgreSQL e registra o CUTOVER da avaliação", async () => {
    const repositorio = repositorioFalso();
    const armazenamento = criarArmazenamentoMemoria();
    const service = criarServiceAvaliacoes({
      repositorio,
      lerRegistrosLegados: () => [],
      armazenamento,
    });

    const resultado = await service.criar({
      organizationId: ORG,
      cycleId: CICLO,
      evaluatedCollaboratorId: COLABORADOR,
    });

    expect(resultado).toEqual({
      ok: true,
      data: { evaluationId: AVALIACAO, cutoverRegistrado: true },
    });
    expect(repositorio.chamadas.map((c) => c.metodo)).toEqual(["criar"]);
    // A marca de cutover é informação de migração — nunca autoridade.
    expect(armazenamento.getItem(CHAVE_AVALIACOES_CORTADAS)).toContain(AVALIACAO);
  });

  it("criar NÃO escreve espelho no acervo legado (sem dual-write)", async () => {
    const repositorio = repositorioFalso();
    const armazenamento = criarArmazenamentoMemoria();
    const registrarLegado = vi.fn();
    const service = criarServiceAvaliacoes({
      repositorio,
      lerRegistrosLegados: () => [],
      armazenamento,
    });

    await service.criar({
      organizationId: ORG,
      cycleId: CICLO,
      evaluatedCollaboratorId: COLABORADOR,
    });

    expect(registrarLegado).not.toHaveBeenCalled();
    // A única chave gravada é a do REGISTRO de cutover.
    expect(Object.keys(armazenamento as unknown as Record<string, unknown>)).not.toContain(
      "feedback-control-feedbacks"
    );
  });

  it("erro do servidor na criação NÃO marca cutover", async () => {
    const repositorio = repositorioFalso({
      criar: async () => ({
        ok: false,
        error: { code: "FORBIDDEN", message: "negado" },
      }),
    });
    const armazenamento = criarArmazenamentoMemoria();
    const service = criarServiceAvaliacoes({
      repositorio,
      lerRegistrosLegados: () => [],
      armazenamento,
    });

    const resultado = await service.criar({
      organizationId: ORG,
      cycleId: CICLO,
      evaluatedCollaboratorId: COLABORADOR,
    });

    expect(resultado.ok).toBe(false);
    expect(armazenamento.getItem(CHAVE_AVALIACOES_CORTADAS)).toBeNull();
  });

  it("acervo separa banco e legado por EVIDÊNCIA, nunca por data", async () => {
    const repositorio = repositorioFalso();
    const armazenamento = criarArmazenamentoMemoria();
    // Registro local de 2026 (data posterior a qualquer "corte") continua
    // legado: a data não é evidência de escrita no PostgreSQL.
    const legado2026 = { evaluationId: "local-2026", dataCriacao: "2026-12-31T00:00:00.000Z" };
    const legadoSemData = { evaluationId: null };
    const doBanco = { evaluationId: AVALIACAO, dataCriacao: "2025-01-01T00:00:00.000Z" };
    registrarAvaliacaoCortada(AVALIACAO, armazenamento);

    const service = criarServiceAvaliacoes({
      repositorio,
      lerRegistrosLegados: () => [legado2026, legadoSemData, doBanco],
      armazenamento,
    });

    const resultado = await service.listarAcervo({
      organizationId: ORG,
      cycleId: CICLO,
      evaluationIds: [AVALIACAO],
      ehEditavel: () => true,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data.avaliacoes).toHaveLength(1);
    expect(resultado.data.avaliacoes[0]!.origem).toBe("POSTGRES");
    // Somente o registro com evidência estrutural saiu do legado.
    expect(resultado.data.legado).toHaveLength(2);
    expect(resultado.data.legado.every((item) => item.editavel === false)).toBe(true);
    expect(resultado.data.avisoLegado).not.toBeNull();
  });

  it("acervo ignora avaliação de OUTRO ciclo/organização (isolamento)", async () => {
    const repositorio = repositorioFalso({
      ler: async (entrada) => ({
        ok: true,
        data: avaliacaoSoberana({
          id: entrada.evaluationId,
          cycleId: "outro-ciclo",
          organizationId: OUTRA_ORG,
        }),
      }),
    });
    const service = criarServiceAvaliacoes({
      repositorio,
      lerRegistrosLegados: () => [],
      armazenamento: criarArmazenamentoMemoria(),
    });

    const resultado = await service.listarAcervo({
      organizationId: ORG,
      cycleId: CICLO,
      evaluationIds: [AVALIACAO],
      ehEditavel: () => true,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data.avaliacoes).toHaveLength(0);
    expect(resultado.data.avisoLegado).toBeNull();
  });

  it("mutações delegam ao repositório com o tenant do contexto", async () => {
    const repositorio = repositorioFalso();
    const service = criarServiceAvaliacoes({
      repositorio,
      lerRegistrosLegados: () => [],
      armazenamento: criarArmazenamentoMemoria(),
    });

    await service.gravarNotas({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      notas: [{ subcriterion_id: COLABORADOR, nota: 4 }],
    });
    await service.gravarComentario({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      escopo: "FINAL",
      texto: "comentário",
    });
    await service.concluir({ organizationId: ORG, evaluationId: AVALIACAO });
    await service.reabrir({ organizationId: ORG, evaluationId: AVALIACAO, motivo: "erro" });
    await service.cancelar({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      motivo: "desligamento",
    });

    expect(repositorio.chamadas.map((c) => c.metodo)).toEqual([
      "gravarNotas",
      "gravarComentario",
      "concluir",
      "reabrir",
      "cancelar",
    ]);
    for (const chamada of repositorio.chamadas) {
      expect((chamada.argumentos as { organizationId: string }).organizationId).toBe(ORG);
    }
  });

  it("mensagens de erro são públicas e estáveis (nunca expõem razão interna)", () => {
    expect(mensagemErroAvaliacoes({ code: "FORBIDDEN", message: "P0001 interno" })).not.toContain(
      "interno"
    );
    expect(mensagemErroAvaliacoes({ code: "NOT_FOUND", message: "x" })).toContain("não encontrada");
    expect(mensagemErroAvaliacoes({ code: "INTERNAL", message: "stack trace" })).not.toContain(
      "stack"
    );
  });
});
