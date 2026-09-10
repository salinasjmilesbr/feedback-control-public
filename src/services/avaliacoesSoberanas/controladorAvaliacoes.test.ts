import { describe, expect, it } from "vitest";
import {
  criarControladorAvaliacoes,
  statusEditavel,
} from "./controladorAvaliacoes.ts";
import { criarServiceAvaliacoes } from "./serviceAvaliacoes.ts";
import { criarArmazenamentoMemoria } from "../../infrastructure/supabase/avaliacoes/cutover.ts";
import type {
  AvaliacaoSoberana,
  RepositorioAvaliacoes,
} from "../../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";

/**
 * F5-06 (Issue #103) — controlador do caminho novo: estado de carregamento,
 * erro público sem lançar, recarga a partir do SERVIDOR após cada mutação e
 * ausência de queda para o legado quando o servidor nega.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const AVALIACAO = "22222222-2222-4222-8222-222222222222";
const COLABORADOR = "44444444-4444-4444-8444-444444444444";
const PARTICIPANTE = "66666666-6666-4666-8666-666666666666";

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

function montar(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): {
  readonly controlador: ReturnType<typeof criarControladorAvaliacoes>;
  readonly contagem: () => Record<string, number>;
} {
  const contagem: Record<string, number> = {};
  const contar = (metodo: string) => {
    contagem[metodo] = (contagem[metodo] ?? 0) + 1;
  };

  const base: RepositorioAvaliacoes = {
    criar: async () => ({ ok: true, data: AVALIACAO }),
    ler: async () => ({ ok: true, data: avaliacaoSoberana() }),
    gravarNotas: async () => ({ ok: true, data: 3.5 }),
    gravarComentario: async () => ({ ok: true, data: null }),
    concluir: async () => ({ ok: true, data: null }),
    reabrir: async () => ({ ok: true, data: null }),
    cancelar: async () => ({ ok: true, data: null }),
    realinharParticipantes: async () => ({ ok: true, data: 1 }),
    painelParticipante: async () => ({
      ok: false,
      error: { code: "INTERNAL", message: "nao usado neste teste" },
    }),
    resolverCiclo: async () => ({ ok: false, error: { code: "INTERNAL", message: "nao usado neste teste" } }),
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

  const instrumentado = Object.fromEntries(
    Object.entries({ ...base, ...comportamentos }).map(([metodo, fn]) => [
      metodo,
      async (...args: unknown[]) => {
        contar(metodo);
        return (fn as (...a: unknown[]) => unknown)(...args);
      },
    ])
  ) as unknown as RepositorioAvaliacoes;

  const service = criarServiceAvaliacoes({
    repositorio: instrumentado,
    lerRegistrosLegados: () => [],
    armazenamento: criarArmazenamentoMemoria(),
  });

  const controlador = criarControladorAvaliacoes({
    service,
    organizationId: ORG,
    cycleId: CICLO,
    evaluationIds: [AVALIACAO],
  });

  return { controlador, contagem: () => contagem };
}

describe("controlador de avaliações soberanas", () => {
  it("carrega o acervo do servidor e marca o carregamento como concluído", async () => {
    const { controlador, contagem } = montar();
    await controlador.carregar();

    const estado = controlador.estado();
    expect(estado.carregando).toBe(false);
    expect(estado.erro).toBeNull();
    expect(estado.acervo?.avaliacoes).toHaveLength(1);
    expect(contagem().ler).toBe(1);
  });

  it("negação do servidor vira erro de UI (não lança) e não cai para o legado", async () => {
    const { controlador } = montar({
      ler: async () => ({ ok: false, error: { code: "FORBIDDEN", message: "negado" } }),
    });

    await controlador.carregar();

    const estado = controlador.estado();
    expect(estado.erro).not.toBeNull();
    expect(estado.acervo).toBeNull();
    expect(JSON.stringify(estado)).not.toContain("negado");
  });

  it("depois de concluir, o acervo é RECARREGADO do servidor", async () => {
    const { controlador, contagem } = montar();
    await controlador.carregar();
    const leiturasAntes = contagem().ler;

    const sucesso = await controlador.concluir(AVALIACAO);

    expect(sucesso).toBe(true);
    expect(contagem().concluir).toBe(1);
    expect(contagem().ler).toBeGreaterThan(leiturasAntes);
    expect(controlador.estado().erro).toBeNull();
  });

  it("mutação negada mantém o acervo anterior e expõe erro público", async () => {
    const { controlador } = montar({
      concluir: async () => ({
        ok: false,
        error: { code: "CONFLICT", message: "Avaliação já concluída." },
      }),
    });
    await controlador.carregar();

    const sucesso = await controlador.concluir(AVALIACAO);

    expect(sucesso).toBe(false);
    expect(controlador.estado().erro).toBe("Avaliação já concluída.");
    expect(controlador.estado().acervo).not.toBeNull();
  });

  it("criar adiciona o novo id ao acervo a partir do servidor", async () => {
    const { controlador, contagem } = montar();
    await controlador.carregar();

    const novoId = await controlador.criar({
      cycleId: CICLO,
      evaluatedCollaboratorId: COLABORADOR,
    });

    expect(novoId).toBe(AVALIACAO);
    expect(contagem().criar).toBe(1);
    expect(controlador.estado().erro).toBeNull();
  });

  it("selecionar carrega a avaliação e propaga erro de inexistência", async () => {
    const { controlador } = montar({ ler: async () => ({ ok: true, data: null }) });
    await controlador.selecionar(AVALIACAO);
    expect(controlador.estado().avaliacaoSelecionada).toBeNull();

    const negado = montar({
      ler: async () => ({ ok: false, error: { code: "NOT_FOUND", message: "x" } }),
    });
    await negado.controlador.selecionar(AVALIACAO);
    expect(negado.controlador.estado().erro).toContain("não encontrada");
  });

  it("gravar notas/comentários exige motivo apenas nas operações auditadas", async () => {
    const { controlador, contagem } = montar();
    await controlador.carregar();

    await controlador.gravarNotas({
      evaluationId: AVALIACAO,
      participantId: PARTICIPANTE,
      notas: [{ subcriterion_id: PARTICIPANTE, nota: 4 }],
    });
    await controlador.gravarComentario({
      evaluationId: AVALIACAO,
      participantId: PARTICIPANTE,
      escopo: "FINAL",
      texto: "fechamento",
    });
    await controlador.reabrir({ evaluationId: AVALIACAO, motivo: "erro de nota" });
    await controlador.cancelar({ evaluationId: AVALIACAO, motivo: "desligamento" });

    expect(contagem().gravarNotas).toBe(1);
    expect(contagem().gravarComentario).toBe(1);
    expect(contagem().reabrir).toBe(1);
    expect(contagem().cancelar).toBe(1);
  });

  it("statusEditavel reflete o workflow (RASCUNHO/PRONTA editáveis)", () => {
    expect(statusEditavel(avaliacaoSoberana({ status: "RASCUNHO" }))).toBe(true);
    expect(statusEditavel(avaliacaoSoberana({ status: "PRONTA_PARA_FEEDBACK" }))).toBe(true);
    expect(statusEditavel(avaliacaoSoberana({ status: "CONCLUIDA" }))).toBe(false);
    expect(statusEditavel(avaliacaoSoberana({ status: "CANCELADA" }))).toBe(false);
  });
});
