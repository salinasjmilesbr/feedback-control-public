import { describe, expect, it } from "vitest";
import {
  DURACAO_MAXIMA_SESSAO_MS,
  LIMITE_INATIVIDADE_MS,
  excedeuDuracaoMaxima,
  excedeuInatividade,
  mensagemDeExpiracao,
  motivoDeExpiracao,
} from "./politicaSessao";

describe("política de sessão (F2-08) — limites temporais puros", () => {
  it("limites são exatamente 60 minutos e 1 dia", () => {
    expect(LIMITE_INATIVIDADE_MS).toBe(60 * 60 * 1000);
    expect(DURACAO_MAXIMA_SESSAO_MS).toBe(24 * 60 * 60 * 1000);
  });

  it("inatividade: abaixo do limite não expira; no/ após o limite expira", () => {
    const inicio = 1_700_000_000_000;
    expect(excedeuInatividade(inicio, inicio + LIMITE_INATIVIDADE_MS - 1)).toBe(false);
    expect(excedeuInatividade(inicio, inicio + LIMITE_INATIVIDADE_MS)).toBe(true);
    expect(excedeuInatividade(inicio, inicio + LIMITE_INATIVIDADE_MS + 1)).toBe(true);
  });

  it("inatividade: sem janela de atividade registrada nunca expira por inatividade", () => {
    expect(excedeuInatividade(null, Date.now())).toBe(false);
  });

  it("duração máxima: abaixo de 1 dia não expira; no/ após 1 dia expira", () => {
    const inicio = 1_700_000_000_000;
    expect(excedeuDuracaoMaxima(inicio, inicio + DURACAO_MAXIMA_SESSAO_MS - 1)).toBe(false);
    expect(excedeuDuracaoMaxima(inicio, inicio + DURACAO_MAXIMA_SESSAO_MS)).toBe(true);
    expect(excedeuDuracaoMaxima(inicio, inicio + DURACAO_MAXIMA_SESSAO_MS + 1)).toBe(true);
  });

  it("duração máxima: sem marcador de início nunca expira por duração", () => {
    expect(excedeuDuracaoMaxima(null, Date.now())).toBe(false);
  });

  it("motivo de expiração prioriza a duração máxima quando ambos os limites caíram", () => {
    const inicio = 1_000;
    expect(motivoDeExpiracao(inicio, inicio + 1, inicio + DURACAO_MAXIMA_SESSAO_MS)).toBe(
      "duracaoMaxima"
    );
    expect(
      motivoDeExpiracao(inicio, inicio, inicio + LIMITE_INATIVIDADE_MS)
    ).toBe("inatividade");
    expect(motivoDeExpiracao(inicio, inicio + 1, inicio + 1)).toBeNull();
    expect(motivoDeExpiracao(null, null, Date.now())).toBeNull();
  });

  it("mensagens de expiração informam o motivo sem expor detalhes técnicos", () => {
    expect(mensagemDeExpiracao("inatividade")).toContain("inatividade");
    expect(mensagemDeExpiracao("duracaoMaxima")).toContain("1 dia");
    expect(mensagemDeExpiracao("inatividade")).not.toContain("ms");
    expect(mensagemDeExpiracao("duracaoMaxima")).not.toContain("token");
  });
});
