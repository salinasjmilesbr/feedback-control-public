/**
 * F6 — Ação da ficha derivada do payload mínimo da descoberta.
 *
 * A tela NÃO decide autorização: `podeEditar` e a própria existência do payload
 * já vêm decididos pelo servidor. Aqui garantimos apenas a tradução para
 * rótulo + destino com UUID, e o fail-closed (`null` ⇒ nenhuma ação).
 */
import { describe, expect, it } from "vitest";
import { acaoDaAvaliacaoDoColaborador } from "./colaboradorDetalheAvaliacaoAcao.ts";
import type { DescobertaAvaliacaoDoColaborador } from "../infrastructure/supabase/avaliacoes/contrato.ts";

const COLAB = "33333333-3333-4333-8333-333333333333";
const AVALIACAO = "44444444-4444-4444-8444-444444444444";
const BASE = `/colaborador/${COLAB}/avaliacoes`;

function descoberta(
  parcial: Partial<DescobertaAvaliacaoDoColaborador> = {}
): DescobertaAvaliacaoDoColaborador {
  return { evaluationId: null, status: null, podeEditar: false, ...parcial };
}

describe("ação da ficha por status da descoberta", () => {
  it("sem avaliação ⇒ Nova avaliação (rota UUID)", () => {
    expect(acaoDaAvaliacaoDoColaborador(COLAB, descoberta())).toEqual({
      label: "Nova avaliação",
      tipo: "NOVA",
      destino: `${BASE}/nova`,
    });
  });

  it("CANCELADA equivale a ausência para quem pode criar ⇒ Nova avaliação", () => {
    // O servidor devolve `evaluationId: null` quando só existe cancelada.
    expect(acaoDaAvaliacaoDoColaborador(COLAB, descoberta({ status: null }))?.tipo).toBe("NOVA");
  });

  it("RASCUNHO editável ⇒ Editar avaliação", () => {
    expect(
      acaoDaAvaliacaoDoColaborador(
        COLAB,
        descoberta({ evaluationId: AVALIACAO, status: "RASCUNHO", podeEditar: true })
      )
    ).toEqual({
      label: "Editar avaliação",
      tipo: "EDITAR",
      destino: `${BASE}/${AVALIACAO}/editar`,
    });
  });

  it("RASCUNHO somente leitura ⇒ Consultar avaliação (sem edição)", () => {
    expect(
      acaoDaAvaliacaoDoColaborador(
        COLAB,
        descoberta({ evaluationId: AVALIACAO, status: "RASCUNHO", podeEditar: false })
      )
    ).toEqual({
      label: "Consultar avaliação",
      tipo: "CONSULTAR",
      destino: `${BASE}/${AVALIACAO}`,
    });
  });

  it("CONCLUIDA ⇒ Consultar avaliação", () => {
    expect(
      acaoDaAvaliacaoDoColaborador(
        COLAB,
        descoberta({ evaluationId: AVALIACAO, status: "CONCLUIDA", podeEditar: false })
      )
    ).toEqual({
      label: "Consultar avaliação",
      tipo: "CONSULTAR",
      destino: `${BASE}/${AVALIACAO}`,
    });
  });

  it("CREATE-only com avaliação existente ⇒ estado neutro sem link", () => {
    expect(acaoDaAvaliacaoDoColaborador(COLAB, {
      existeSemAcesso: true,
      podeEditar: false,
    })).toEqual({
      label: "Já existe avaliação neste ciclo",
      tipo: "EXISTENTE_SEM_ACESSO",
    });
  });

  it("nenhum destino usa matrícula (identidade é UUID)", () => {
    const destinos = [
      acaoDaAvaliacaoDoColaborador(COLAB, descoberta())?.destino,
      acaoDaAvaliacaoDoColaborador(
        COLAB,
        descoberta({ evaluationId: AVALIACAO, status: "RASCUNHO", podeEditar: true })
      )?.destino,
      acaoDaAvaliacaoDoColaborador(
        COLAB,
        descoberta({ evaluationId: AVALIACAO, status: "CONCLUIDA" })
      )?.destino,
    ];
    for (const destino of destinos) {
      expect(destino).toContain(COLAB);
      expect(destino).toMatch(/\/colaborador\/[0-9a-f-]{36}\/avaliacoes/);
    }
  });

  it("erro/DENY (payload ausente) ⇒ NENHUMA ação (fail-closed)", () => {
    expect(acaoDaAvaliacaoDoColaborador(COLAB, null)).toBeNull();
  });
});
