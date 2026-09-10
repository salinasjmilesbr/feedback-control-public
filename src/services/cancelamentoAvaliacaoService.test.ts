import { beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { criarArmazenamentoMemoria } from "../infrastructure/supabase/avaliacoes/cutover";
import { criarCutoverAvaliacoes } from "./avaliacoesSoberanas/cutoverAvaliacoesService";
import type { RepositorioAvaliacoes } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import { cancelarAvaliacao } from "./cancelamentoAvaliacaoService";

/**
 * F5-06 (Issue #103) — CANCELAMENTO SOBERANO.
 *
 * O cancelamento deixou de ser decidido no navegador: o serviço apenas envia a
 * INTENÇÃO (id + motivo + organização ativa) para a fronteira confiável e
 * traduz o erro público. Os testes abaixo verificam exatamente isso:
 *
 * - o motivo é obrigatório ANTES de qualquer chamada (validação de entrada);
 * - a decisão ALLOW/DENY pertence ao Policy Engine server-side — a recusa chega
 *   como erro público e NADA é gravado localmente (fail-closed, sem dual-write);
 * - nenhum registro é tocado no `localStorage` em nenhum cenário.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const AVALIACAO = "33333333-3333-4333-8333-333333333333";
const CHAVE_LEGADO = "feedback-control-feedbacks";

function repositorioFalso(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): RepositorioAvaliacoes & { readonly chamadas: string[] } {
  const chamadas: string[] = [];
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
    painelParticipante: async () => {
      throw new Error("não usado neste teste");
    },
    resolverCiclo: async () => ({ ok: true, data: "22222222-2222-4222-8222-222222222222" }),
  };

  const instrumentado = Object.fromEntries(
    Object.entries({ ...base, ...comportamentos }).map(([nome, fn]) => [
      nome,
      async (...args: unknown[]) => {
        chamadas.push(nome);
        return (fn as (...a: unknown[]) => unknown)(...args);
      },
    ])
  ) as unknown as RepositorioAvaliacoes;

  return Object.assign(instrumentado, { chamadas });
}

function deps(comportamentos: Partial<RepositorioAvaliacoes> = {}) {
  const repositorio = repositorioFalso(comportamentos);
  return {
    repositorio,
    criarCutover: () =>
      criarCutoverAvaliacoes({
        repositorio,
        armazenamento: criarArmazenamentoMemoria(),
      }),
  };
}

describe("cancelarAvaliacao (soberano)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(CHAVE_LEGADO, JSON.stringify([{ id: AVALIACAO }]));
  });

  it("envia a intenção ao servidor e NÃO escreve no localStorage", async () => {
    const dependencias = deps();
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);

    const resultado = await cancelarAvaliacao(
      AVALIACAO,
      "  Não se aplica mais  ",
      ORG,
      dependencias
    );

    expect(resultado.ok).toBe(true);
    expect(dependencias.repositorio.chamadas).toEqual(["cancelar"]);
    // Sem dual-write: o acervo legado permanece byte a byte o mesmo.
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });

  it("recusa motivo vazio antes de chamar o servidor", async () => {
    const dependencias = deps();

    await expect(
      cancelarAvaliacao(AVALIACAO, "   ", ORG, dependencias)
    ).rejects.toThrow("Informe o motivo do cancelamento.");
    expect(dependencias.repositorio.chamadas).toEqual([]);
  });

  it("recusa do Policy Engine vira erro público e nada é gravado localmente", async () => {
    const dependencias = deps({
      cancelar: async () => ({
        ok: false,
        error: { code: "FORBIDDEN", message: "negado" },
      }),
    });
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);

    const resultado = await cancelarAvaliacao(
      AVALIACAO,
      "Motivo válido",
      ORG,
      dependencias
    );

    expect(resultado.ok).toBe(false);
    expect(resultado.erro).toBeTruthy();
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });

  it("sem caminho soberano configurado a operação é recusada (fail-closed)", async () => {
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);
    const resultado = await cancelarAvaliacao(AVALIACAO, "Motivo válido", ORG, {
      criarCutover: () => null,
    });

    expect(resultado.ok).toBe(false);
    expect(resultado.erro).toContain("PostgreSQL");
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });

  it("propaga o erro de rede do repositório sem cair para o caminho legado", async () => {
    const dependencias = deps({
      cancelar: vi.fn(async () => {
        throw new Error("rede indisponível");
      }) as unknown as RepositorioAvaliacoes["cancelar"],
    });

    await expect(
      cancelarAvaliacao(AVALIACAO, "Motivo válido", ORG, dependencias)
    ).rejects.toThrow("rede indisponível");
    expect(localStorage.getItem(CHAVE_LEGADO)).not.toBeNull();
  });
});
