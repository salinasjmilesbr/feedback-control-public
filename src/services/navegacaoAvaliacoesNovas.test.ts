import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import {
  CHAVE_CICLO_AVALIACOES,
  criarArmazenamentoMemoria,
  lerAvaliacaoNovaDoColaboradorNoCiclo,
  lerAvaliacoesDoCiclo,
  registrarAvaliacaoCortada,
  registrarAvaliacoesDoCiclo,
  type ArmazenamentoCutover,
} from "../infrastructure/supabase/avaliacoes/cutover";
import { classificarOrigem } from "./origemAvaliacaoTela";

/**
 * F5-06 (Issue #103) — NAVEGAÇÃO das avaliações NOVAS (correção pós-auditoria).
 *
 * Uma avaliação criada exclusivamente no PostgreSQL NÃO existe no
 * `localStorage` legado. Para que o produto continue localizável depois do
 * reload, o cliente mantém um ÍNDICE DE NAVEGAÇÃO (ano+ciclo → ids; e
 * ano+ciclo+matrícula → id), alimentado somente por escritas soberanas
 * confirmadas.
 *
 * O índice é ROTEAMENTO, nunca autoridade: quem confirma existência, tenant e
 * permissão é o PostgreSQL, a cada leitura soberana.
 */

const UUID_A = "44444444-4444-4444-8444-444444444444";
const UUID_B = "55555555-5555-4555-8555-555555555555";
const MATRICULA = 101;

describe("índice de navegação do cutover", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it("persiste e recupera o id por ciclo (sobrevive ao reload)", () => {
    const registro = criarArmazenamentoMemoria();

    registrarAvaliacoesDoCiclo(2026, 1, [UUID_A], registro, MATRICULA);

    // "Reload": novo acesso ao MESMO armazenamento persistente.
    expect(lerAvaliacoesDoCiclo(2026, 1, registro)).toEqual([UUID_A]);
    expect(lerAvaliacaoNovaDoColaboradorNoCiclo(2026, 1, MATRICULA, registro)).toBe(
      UUID_A
    );
  });

  it("permite LOCALIZAR a avaliação nova depois do reload (classificação)", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacaoCortada(UUID_A, registro);
    registrarAvaliacoesDoCiclo(2026, 1, [UUID_A], registro, MATRICULA);

    // A tela descobre o id pelo índice e confirma a origem pela EVIDÊNCIA.
    const idLocalizado = lerAvaliacaoNovaDoColaboradorNoCiclo(
      2026,
      1,
      MATRICULA,
      registro
    );
    expect(idLocalizado).not.toBeNull();
    expect(classificarOrigem(idLocalizado!, registro)).toBe("POSTGRES");
  });

  it("não mistura ciclos, anos nem colaboradores", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacoesDoCiclo(2026, 1, [UUID_A], registro, MATRICULA);
    registrarAvaliacoesDoCiclo(2026, 2, [UUID_B], registro, 202);

    expect(lerAvaliacoesDoCiclo(2026, 1, registro)).toEqual([UUID_A]);
    expect(lerAvaliacoesDoCiclo(2026, 2, registro)).toEqual([UUID_B]);
    expect(lerAvaliacoesDoCiclo(2027, 1, registro)).toEqual([]);
    expect(lerAvaliacaoNovaDoColaboradorNoCiclo(2026, 1, 202, registro)).toBeNull();
    expect(lerAvaliacaoNovaDoColaboradorNoCiclo(2026, 2, MATRICULA, registro)).toBeNull();
  });

  it("é idempotente e mantém o id mais recente do colaborador no ciclo", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacoesDoCiclo(2026, 1, [UUID_A], registro, MATRICULA);
    registrarAvaliacoesDoCiclo(2026, 1, [UUID_A], registro, MATRICULA);
    expect(lerAvaliacoesDoCiclo(2026, 1, registro)).toEqual([UUID_A]);

    // Recriação após cancelamento: o id novo passa a ser o navegável.
    registrarAvaliacoesDoCiclo(2026, 1, [UUID_B], registro, MATRICULA);
    expect(lerAvaliacoesDoCiclo(2026, 1, registro)).toEqual([UUID_A, UUID_B]);
    expect(lerAvaliacaoNovaDoColaboradorNoCiclo(2026, 1, MATRICULA, registro)).toBe(
      UUID_B
    );
  });

  it("ignora id NÃO técnico: nada é registrado sem evidência do caminho novo", () => {
    const registro = criarArmazenamentoMemoria();

    registrarAvaliacoesDoCiclo(2026, 1, ["avaliacao-legada", "101", ""], registro, MATRICULA);

    expect(lerAvaliacoesDoCiclo(2026, 1, registro)).toEqual([]);
    expect(lerAvaliacaoNovaDoColaboradorNoCiclo(2026, 1, MATRICULA, registro)).toBeNull();
    expect(registro.getItem(CHAVE_CICLO_AVALIACOES)).toBeNull();
  });

  it("sem armazenamento disponível o índice é inerte (não lança)", () => {
    expect(() =>
      registrarAvaliacoesDoCiclo(2026, 1, [UUID_A], null, MATRICULA)
    ).not.toThrow();
    expect(lerAvaliacoesDoCiclo(2026, 1, null)).toEqual([]);
    expect(lerAvaliacaoNovaDoColaboradorNoCiclo(2026, 1, MATRICULA, null)).toBeNull();
  });

  it("conteúdo corrompido do índice não quebra nem promove nada", () => {
    const registro: ArmazenamentoCutover = criarArmazenamentoMemoria();

    for (const conteudo of [
      "{nao-e-json",
      JSON.stringify([1, 2, 3]),
      JSON.stringify({ ids: "nao-e-objeto" }),
      JSON.stringify({ ids: { "2026-1": ["nao-e-uuid"] } }),
      JSON.stringify({ porColaborador: { "2026-1-101": "nao-e-uuid" } }),
    ]) {
      registro.setItem(CHAVE_CICLO_AVALIACOES, conteudo);
      expect(lerAvaliacoesDoCiclo(2026, 1, registro)).toEqual([]);
      expect(
        lerAvaliacaoNovaDoColaboradorNoCiclo(2026, 1, MATRICULA, registro)
      ).toBeNull();
    }
  });
});
