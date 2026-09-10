import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import {
  CHAVE_CICLO_AVALIACOES,
  criarArmazenamentoMemoria,
  esquecerAvaliacaoNovaDoColaboradorNoCiclo,
  lerAvaliacaoNovaDoColaboradorNoCiclo,
  lerAvaliacoesDoCiclo,
  registrarAvaliacaoCortada,
  registrarAvaliacoesDoCiclo,
  type ArmazenamentoCutover,
} from "../infrastructure/supabase/avaliacoes/cutover";
import { cacheConheciaComoTecnicaPostgres } from "./origemAvaliacaoTela";

/**
 * F5-06 (Issue #103) — CACHE DE NAVEGAÇÃO namespaceado por ORGANIZAÇÃO.
 *
 * O índice local é apenas cache/roteamento: ajuda a tela a encontrar avaliações
 * novas (que não existem no legado) e a evitar tentativas redundantes. Ele NÃO
 * estabelece existência, tenant nem autorização — por isso a organização entra
 * somente como NAMESPACE, e toda operação real revalida o tenant no servidor.
 *
 * Sem o namespace, a mesma matrícula/ano/ciclo em organizações diferentes
 * colidiria no mesmo navegador.
 */

const ORG_A = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const UUID_A = "44444444-4444-4444-8444-444444444444";
const UUID_B = "55555555-5555-4555-8555-555555555555";
const MATRICULA = 101;

describe("índice de navegação (cache) namespaceado por organização", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it("persiste e recupera o id por organização + ciclo (sobrevive ao reload)", () => {
    const registro = criarArmazenamentoMemoria();

    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], registro, MATRICULA);

    // "Reload": novo acesso ao MESMO armazenamento persistente.
    expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 1, registro)).toEqual([UUID_A]);
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, registro)
    ).toBe(UUID_A);
  });

  it("permite LOCALIZAR a avaliação nova depois do reload (cache → servidor)", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacaoCortada(UUID_A, registro);
    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], registro, MATRICULA);

    const idLocalizado = lerAvaliacaoNovaDoColaboradorNoCiclo(
      ORG_A,
      2026,
      1,
      MATRICULA,
      registro
    );
    expect(idLocalizado).not.toBeNull();
    // O cache orienta; a existência é confirmada no servidor a cada operação.
    expect(cacheConheciaComoTecnicaPostgres(idLocalizado!, registro)).toBe(true);
  });

  it("a MESMA matrícula/ano/ciclo em organizações diferentes NÃO colide", () => {
    const registro = criarArmazenamentoMemoria();

    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], registro, MATRICULA);
    registrarAvaliacoesDoCiclo(ORG_B, 2026, 1, [UUID_B], registro, MATRICULA);

    expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 1, registro)).toEqual([UUID_A]);
    expect(lerAvaliacoesDoCiclo(ORG_B, 2026, 1, registro)).toEqual([UUID_B]);
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, registro)
    ).toBe(UUID_A);
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_B, 2026, 1, MATRICULA, registro)
    ).toBe(UUID_B);
  });

  it("avaliação da org A nunca bloqueia a criação legítima na org B", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], registro, MATRICULA);

    // Trocar de organização ativa não reutiliza o índice da outra.
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_B, 2026, 1, MATRICULA, registro)
    ).toBeNull();
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, registro)
    ).toBe(UUID_A);
  });

  it("não mistura anos nem ciclos dentro da mesma organização", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], registro, MATRICULA);
    registrarAvaliacoesDoCiclo(ORG_A, 2026, 2, [UUID_B], registro, 202);

    expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 2, registro)).toEqual([UUID_B]);
    expect(lerAvaliacoesDoCiclo(ORG_A, 2027, 1, registro)).toEqual([]);
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, 202, registro)
    ).toBeNull();
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 2, MATRICULA, registro)
    ).toBeNull();
  });

  it("é idempotente e mantém o id mais recente do colaborador no ciclo", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], registro, MATRICULA);
    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], registro, MATRICULA);
    expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 1, registro)).toEqual([UUID_A]);

    // Recriação após cancelamento: o id novo passa a ser o navegável.
    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_B], registro, MATRICULA);
    expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 1, registro)).toEqual([UUID_A, UUID_B]);
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, registro)
    ).toBe(UUID_B);
  });

  it("esquece entrada OBSOLETA sem tocar no acervo legado nem na evidência", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacaoCortada(UUID_A, registro);
    registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], registro, MATRICULA);

    esquecerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, registro);

    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, registro)
    ).toBeNull();
    // A evidência de cutover é append-only e permanece.
    expect(cacheConheciaComoTecnicaPostgres(UUID_A, registro)).toBe(true);
    // E o id continua listável no índice do ciclo (histórico de navegação).
    expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 1, registro)).toEqual([UUID_A]);

    // Esquecer entrada inexistente é no-op.
    expect(() =>
      esquecerAvaliacaoNovaDoColaboradorNoCiclo(ORG_B, 2026, 1, MATRICULA, registro)
    ).not.toThrow();
  });

  it("ignora id NÃO técnico: nada é registrado sem evidência do caminho novo", () => {
    const registro = criarArmazenamentoMemoria();

    registrarAvaliacoesDoCiclo(
      ORG_A,
      2026,
      1,
      ["avaliacao-legada", "101", ""],
      registro,
      MATRICULA
    );

    expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 1, registro)).toEqual([]);
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, registro)
    ).toBeNull();
    expect(registro.getItem(CHAVE_CICLO_AVALIACOES)).toBeNull();
  });

  it("sem armazenamento disponível o índice é inerte (não lança)", () => {
    expect(() =>
      registrarAvaliacoesDoCiclo(ORG_A, 2026, 1, [UUID_A], null, MATRICULA)
    ).not.toThrow();
    expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 1, null)).toEqual([]);
    expect(
      lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, null)
    ).toBeNull();
    expect(() =>
      esquecerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, null)
    ).not.toThrow();
  });

  it("conteúdo corrompido do índice não quebra nem promove nada", () => {
    const registro: ArmazenamentoCutover = criarArmazenamentoMemoria();

    for (const conteudo of [
      "{nao-e-json",
      JSON.stringify([1, 2, 3]),
      JSON.stringify({ ids: "nao-e-objeto" }),
      JSON.stringify({ ids: { qualquer: ["nao-e-uuid"] } }),
      JSON.stringify({ porColaborador: { qualquer: "nao-e-uuid" } }),
    ]) {
      registro.setItem(CHAVE_CICLO_AVALIACOES, conteudo);
      expect(lerAvaliacoesDoCiclo(ORG_A, 2026, 1, registro)).toEqual([]);
      expect(
        lerAvaliacaoNovaDoColaboradorNoCiclo(ORG_A, 2026, 1, MATRICULA, registro)
      ).toBeNull();
    }
  });
});
