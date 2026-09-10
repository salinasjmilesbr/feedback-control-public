import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock.ts";
import { criarServiceAvaliacoes } from "./avaliacoesSoberanas/serviceAvaliacoes.ts";
import {
  avaliacaoVinculadaAoBanco,
  criarArmazenamentoMemoria,
} from "../infrastructure/supabase/avaliacoes/cutover.ts";
import type {
  AvaliacaoSoberana,
  RepositorioAvaliacoes,
} from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";
import type { Feedback } from "../types/Feedback.ts";

/**
 * F5-06 (Issue #103) — CUTOVER do domínio (§11, D12): a partir da primeira
 * escrita exclusiva no PostgreSQL, Supabase é a fonte de verdade das avaliações
 * NOVAS e o `localStorage` permanece apenas como legado de LEITURA.
 *
 * Este teste comprova, no caminho real do service:
 * - avaliação nova é criada APENAS no banco (nenhum espelho em localStorage);
 * - o acervo legado continua legível e SEM edição, sem se misturar ao novo;
 * - a chave de avaliações do legado nunca recebe a avaliação nova.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const AVALIACAO = "22222222-2222-4222-8222-222222222222";
const COLABORADOR = "44444444-4444-4444-8444-444444444444";

const CHAVE_LEGADO = "feedback-control-feedbacks";

function feedbackLegado(parcial: Partial<Feedback> = {}): Feedback {
  return {
    id: "legado-1",
    colaboradorId: 101,
    colaboradorNome: "Pessoa Sintetica",
    status: "CONCLUIDA",
    data: "2025-06-01T00:00:00.000Z",
    dataCriacao: "2025-06-01T00:00:00.000Z",
    ano: 2025,
    ciclo: 1,
    competencias: [],
    notaMedia: 3.5,
    ...parcial,
  } as Feedback;
}

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

function repositorioFalso(): RepositorioAvaliacoes {
  return {
    criar: async () => ({ ok: true, data: AVALIACAO }),
    ler: async () => ({ ok: true, data: avaliacaoSoberana() }),
    gravarNotas: async () => ({ ok: true, data: 3.5 }),
    gravarComentario: async () => ({ ok: true, data: null }),
    concluir: async () => ({ ok: true, data: null }),
    reabrir: async () => ({ ok: true, data: null }),
    cancelar: async () => ({ ok: true, data: null }),
    realinharParticipantes: async () => ({ ok: true, data: 0 }),
    transparenciaDoAvaliado: async () => ({
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
}

describe("cutover do domínio de avaliações (§11/D12)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it("criação nova acontece SÓ no banco: nenhum espelho no localStorage", async () => {
    const service = criarServiceAvaliacoes({
      repositorio: repositorioFalso(),
      lerRegistrosLegados: () => [],
      armazenamento: criarArmazenamentoMemoria(),
    });

    const resultado = await service.criar({
      organizationId: ORG,
      cycleId: CICLO,
      evaluatedCollaboratorId: COLABORADOR,
    });

    expect(resultado.ok).toBe(true);
    // Nenhuma avaliação foi espelhada na chave legada (sem dual-write).
    expect(localStorage.getItem(CHAVE_LEGADO)).toBeNull();
  });

  it("acervo mostra o legado como somente leitura e o novo separado dele", async () => {
    localStorage.setItem(CHAVE_LEGADO, JSON.stringify([feedbackLegado()]));

    const registrosLegados = JSON.parse(
      localStorage.getItem(CHAVE_LEGADO) ?? "[]"
    ) as Feedback[];

    const service = criarServiceAvaliacoes({
      repositorio: repositorioFalso(),
      lerRegistrosLegados: () => registrosLegados,
      armazenamento: criarArmazenamentoMemoria(),
    });

    const acervo = await service.listarAcervo({
      organizationId: ORG,
      cycleId: CICLO,
      evaluationIds: [AVALIACAO],
      ehEditavel: () => true,
    });

    expect(acervo.ok).toBe(true);
    if (!acervo.ok) return;
    expect(acervo.data.avaliacoes).toHaveLength(1);
    expect(acervo.data.legado).toHaveLength(1);
    expect(acervo.data.legado[0]!.editavel).toBe(false);
    expect(acervo.data.legado[0]!.origem).toBe("LEGADO_LOCAL");
    expect(acervo.data.avisoLegado).not.toBeNull();
    // O legado continua intacto no armazenamento (nenhuma migração silenciosa).
    expect(localStorage.getItem(CHAVE_LEGADO)).toContain("legado-1");
  });

  it("depois de criar, a avaliação está vinculada ao banco (não volta ao legado)", async () => {
    const armazenamento = criarArmazenamentoMemoria();
    const service = criarServiceAvaliacoes({
      repositorio: repositorioFalso(),
      lerRegistrosLegados: () => [],
      armazenamento,
    });

    await service.criar({
      organizationId: ORG,
      cycleId: CICLO,
      evaluatedCollaboratorId: COLABORADOR,
    });

    expect(avaliacaoVinculadaAoBanco(AVALIACAO, armazenamento)).toBe(true);
  });

  it("avaliação sem cutover registrado é tratada como legado (fail-closed)", () => {
    const armazenamento = criarArmazenamentoMemoria();
    expect(avaliacaoVinculadaAoBanco("avaliacao-desconhecida", armazenamento)).toBe(false);
  });
});
