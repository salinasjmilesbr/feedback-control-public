import { describe, expect, it } from "vitest";
import {
  cicloEncerravel,
  obterStatusAvaliacao,
  projetarStatus,
  statusEditavel,
} from "./statusAvaliacoes.ts";
import { criarServiceAvaliacoes } from "./serviceAvaliacoes.ts";
import { criarArmazenamentoMemoria } from "../../infrastructure/supabase/avaliacoes/cutover.ts";
import type {
  AvaliacaoSoberana,
  RepositorioAvaliacoes,
} from "../../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";

/**
 * F5-06 (Issue #103) — status real da avaliação: o estado de domínio vem do
 * PostgreSQL (projeção do banco), nunca de uma projeção legada; inexistência e
 * negação são fail-closed.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const AVALIACAO = "22222222-2222-4222-8222-222222222222";
const COLABORADOR = "44444444-4444-4444-8444-444444444444";

function avaliacao(parcial: Partial<AvaliacaoSoberana> = {}): AvaliacaoSoberana {
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

function repositorio(ler: RepositorioAvaliacoes["ler"]): RepositorioAvaliacoes {
  return {
    criar: async () => ({ ok: true, data: AVALIACAO }),
    ler,
    gravarNotas: async () => ({ ok: true, data: null }),
    gravarComentario: async () => ({ ok: true, data: null }),
    concluir: async () => ({ ok: true, data: null }),
    reabrir: async () => ({ ok: true, data: null }),
    cancelar: async () => ({ ok: true, data: null }),
    realinharParticipantes: async () => ({ ok: true, data: 0 }),
    transparenciaDoAvaliado: async () => ({
      ok: true,
      data: {
        evaluationId: AVALIACAO,
        notaMedia: null,
        faixa: null,
        criterios: [],
        subcriterios: [],
        colegiado: [],
        comentariosFinais: [],
      },
    }),
  };
}

function service(ler: RepositorioAvaliacoes["ler"]) {
  return criarServiceAvaliacoes<unknown>({
    repositorio: repositorio(ler),
    lerRegistrosLegados: () => [],
    armazenamento: criarArmazenamentoMemoria(),
  });
}

describe("status real da avaliação (caminho novo)", () => {
  it("projeta o status do banco com editabilidade e agregados", () => {
    const status = projetarStatus(
      avaliacao({ status: "CONCLUIDA", notaMedia: 4.5, dataConclusao: "2026-02-01T00:00:00Z" })
    );
    expect(status).toEqual({
      evaluationId: AVALIACAO,
      status: "CONCLUIDA",
      origem: "POSTGRES",
      editavel: false,
      encerradaComPendencias: false,
      notaMedia: 4.5,
    });
  });

  it("statusEditavel reconhece apenas RASCUNHO/PRONTA_PARA_FEEDBACK", () => {
    expect(statusEditavel({ status: "RASCUNHO" })).toBe(true);
    expect(statusEditavel({ status: "PRONTA_PARA_FEEDBACK" })).toBe(true);
    expect(statusEditavel({ status: "CONCLUIDA" })).toBe(false);
    expect(statusEditavel({ status: "CANCELADA" })).toBe(false);
    expect(statusEditavel({ status: "desconhecido" })).toBe(false);
  });

  it("avaliação existente devolve o status real do PostgreSQL", async () => {
    const resultado = await obterStatusAvaliacao(
      service(async () => ({ ok: true, data: avaliacao({ status: "CONCLUIDA" }) })),
      { organizationId: ORG, evaluationId: AVALIACAO }
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.status?.origem).toBe("POSTGRES");
    expect(resultado.status?.status).toBe("CONCLUIDA");
    expect(resultado.status?.editavel).toBe(false);
  });

  it("inexistente/cross-tenant devolve null (não vaza existência)", async () => {
    const resultado = await obterStatusAvaliacao(
      service(async () => ({ ok: true, data: null })),
      { organizationId: ORG, evaluationId: AVALIACAO }
    );

    expect(resultado).toEqual({ ok: true, status: null });
  });

  it("negação do servidor vira erro público", async () => {
    const resultado = await obterStatusAvaliacao(
      service(async () => ({
        ok: false,
        error: { code: "NOT_FOUND", message: "F5-06: avaliacao inexistente" },
      })),
      { organizationId: ORG, evaluationId: AVALIACAO }
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erro).toContain("não encontrada");
    expect(resultado.erro).not.toContain("F5-06");
  });

  it("ciclo é encerrável apenas quando nenhuma avaliação nova admite mutação", () => {
    const concluida = projetarStatus(avaliacao({ status: "CONCLUIDA" }));
    const cancelada = projetarStatus(avaliacao({ status: "CANCELADA" }));
    const rascunho = projetarStatus(avaliacao({ status: "RASCUNHO" }));

    expect(cicloEncerravel([concluida, cancelada])).toBe(true);
    expect(cicloEncerravel([concluida, rascunho])).toBe(false);
    // Lista vazia não assume estado por omissão.
    expect(cicloEncerravel([])).toBe(false);
  });
});
