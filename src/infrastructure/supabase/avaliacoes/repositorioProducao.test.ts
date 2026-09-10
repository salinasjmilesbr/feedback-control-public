import { describe, expect, it } from "vitest";
import { criarRepositorioAvaliacoesProducao } from "./repositorioProducao.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * F5-06 (Issue #103) — montagem do repositório em produção: só existe com
 * ambiente configurado; sem configuração devolve `null` (fail-closed, sem
 * fallback para o `localStorage`).
 */

function clienteFalso(): SupabaseClient {
  return {
    functions: { invoke: async () => ({ data: { ok: true }, error: null }) },
  } as unknown as SupabaseClient;
}

describe("repositório de avaliações em produção", () => {
  it("sem configuração de ambiente devolve null (fail-closed)", () => {
    const repositorio = criarRepositorioAvaliacoesProducao({ criarCliente: () => null });
    expect(repositorio).toBeNull();
  });

  it("com cliente disponível devolve o repositório do caminho novo", () => {
    const repositorio = criarRepositorioAvaliacoesProducao({
      criarCliente: () => clienteFalso(),
    });
    expect(repositorio).not.toBeNull();
    expect(typeof repositorio?.criar).toBe("function");
    expect(typeof repositorio?.transparenciaDoAvaliado).toBe("function");
  });

  it("encaminha a configuração recebida para a fábrica do cliente", () => {
    const recebidas: unknown[] = [];
    criarRepositorioAvaliacoesProducao({
      configuracao: { ambiente: "development", supabaseUrl: "https://exemplo.invalid", supabaseAnonKey: "chave" },
      criarCliente: (configuracao) => {
        recebidas.push(configuracao);
        return clienteFalso();
      },
    });
    expect(recebidas[0]).toEqual({
      ambiente: "development",
      supabaseUrl: "https://exemplo.invalid",
      supabaseAnonKey: "chave",
    });
  });
});
