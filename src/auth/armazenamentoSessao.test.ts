import { describe, expect, it } from "vitest";
import {
  CHAVE_INICIO_SESSAO,
  criarArmazenamentoInicioSessaoLocal,
} from "./armazenamentoSessao";

function storageEmMemoria() {
  const dados = new Map<string, string>();
  return {
    dados,
    storage: {
      getItem: (chave: string) => dados.get(chave) ?? null,
      setItem: (chave: string, valor: string) => {
        dados.set(chave, valor);
      },
      removeItem: (chave: string) => {
        dados.delete(chave);
      },
    },
  };
}

describe("armazenamento do início de sessão (F2-08)", () => {
  it("persiste por usuário sob uma única chave e permite ler/remover", () => {
    const { storage, dados } = storageEmMemoria();
    const armazenamento = criarArmazenamentoInicioSessaoLocal(() => storage);

    armazenamento.definir("uuid-1", 1_700_000_000_000);
    armazenamento.definir("uuid-2", 1_700_000_100_000);

    expect(armazenamento.ler("uuid-1")).toBe(1_700_000_000_000);
    expect(armazenamento.ler("uuid-2")).toBe(1_700_000_100_000);
    expect(armazenamento.ler("uuid-ausente")).toBeNull();

    const bruto = dados.get(CHAVE_INICIO_SESSAO);
    expect(bruto).toBeTruthy();
    expect(JSON.parse(bruto ?? "{}")).toEqual({
      "uuid-1": 1_700_000_000_000,
      "uuid-2": 1_700_000_100_000,
    });

    armazenamento.remover("uuid-1");
    expect(armazenamento.ler("uuid-1")).toBeNull();
    expect(armazenamento.ler("uuid-2")).toBe(1_700_000_100_000);
  });

  it("restaura valores previamente persistidos (refresh/reabertura do navegador)", () => {
    const { storage } = storageEmMemoria();
    const primeiro = criarArmazenamentoInicioSessaoLocal(() => storage);
    primeiro.definir("uuid-1", 1_700_000_000_000);

    // Nova instância do módulo (como após um reload) lê o mesmo marcador.
    const segundo = criarArmazenamentoInicioSessaoLocal(() => storage);
    expect(segundo.ler("uuid-1")).toBe(1_700_000_000_000);
  });

  it("tolerante a JSON corrompido: não lança e segue disponível", () => {
    const { storage, dados } = storageEmMemoria();
    dados.set(CHAVE_INICIO_SESSAO, "{corrompido");
    const armazenamento = criarArmazenamentoInicioSessaoLocal(() => storage);

    expect(() => armazenamento.ler("uuid-1")).not.toThrow();
    expect(armazenamento.ler("uuid-1")).toBeNull();

    armazenamento.definir("uuid-1", 42);
    expect(armazenamento.ler("uuid-1")).toBe(42);
    // Corrige a persistência após o próximo uso.
    expect(JSON.parse(dados.get(CHAVE_INICIO_SESSAO) ?? "{}")).toEqual({ "uuid-1": 42 });
  });

  it("ignora valores inválidos no registro persistido", () => {
    const { storage, dados } = storageEmMemoria();
    dados.set(CHAVE_INICIO_SESSAO, JSON.stringify({ "uuid-1": "não-numérico", "uuid-2": -5 }));
    const armazenamento = criarArmazenamentoInicioSessaoLocal(() => storage);

    expect(armazenamento.ler("uuid-1")).toBeNull();
    expect(armazenamento.ler("uuid-2")).toBeNull();
  });

  it("funciona sem storage (memória) sem lançar", () => {
    const armazenamento = criarArmazenamentoInicioSessaoLocal(() => null);
    armazenamento.definir("uuid-1", 123);
    expect(armazenamento.ler("uuid-1")).toBe(123);
    armazenamento.remover("uuid-1");
    expect(armazenamento.ler("uuid-1")).toBeNull();
  });

  it("storage que lança não quebra a política (fallback em memória)", () => {
    const armazenamento = criarArmazenamentoInicioSessaoLocal(() => {
      throw new Error("localStorage indisponível");
    });

    armazenamento.definir("uuid-1", 1_700_000_000_000);
    expect(armazenamento.ler("uuid-1")).toBe(1_700_000_000_000);
    armazenamento.remover("uuid-1");
    expect(armazenamento.ler("uuid-1")).toBeNull();
  });
});
