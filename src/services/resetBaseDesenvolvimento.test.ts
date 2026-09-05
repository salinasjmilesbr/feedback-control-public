import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";

const marcador = "feedback-control-reset-2026-08-26-base-enxuta-v1";
const chavesDoReset = [
  "feedback-control-colaboradores",
  "feedback-control-feedbacks",
  "feedback-control-observacoes",
  "feedback-control-metas",
  "feedback-control-ciclos",
  "feedback-control-usuario-atual",
];

describe("reset exclusivo de desenvolvimento", () => {
  beforeEach(() => {
    vi.resetModules();
    instalarLocalStorageEmMemoria();
    chavesDoReset.forEach((chave) => localStorage.setItem(chave, "dados fictícios"));
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  it("em DEV limpa somente as chaves previstas e registra a versão atual", async () => {
    vi.stubEnv("DEV", true);
    const preservadas = ["feedback-control-historico-organizacional", "preferencia-ficticia"];
    preservadas.forEach((chave) => localStorage.setItem(chave, "preservado"));
    const { executarResetBaseDesenvolvimento } = await import("./resetBaseDesenvolvimento");

    executarResetBaseDesenvolvimento();

    chavesDoReset.forEach((chave) => expect(localStorage.getItem(chave)).toBeNull());
    preservadas.forEach((chave) => expect(localStorage.getItem(chave)).toBe("preservado"));
    expect(localStorage.getItem(marcador)).toBe("ok");
  });

  it("em DEV executa uma vez por versão, preservando dados criados após o reset", async () => {
    vi.stubEnv("DEV", true);
    const { executarResetBaseDesenvolvimento } = await import("./resetBaseDesenvolvimento");
    executarResetBaseDesenvolvimento();
    localStorage.setItem(chavesDoReset[0], "novo cadastro fictício");
    const remover = vi.spyOn(localStorage, "removeItem");
    const gravar = vi.spyOn(localStorage, "setItem");

    executarResetBaseDesenvolvimento();

    expect(localStorage.getItem(chavesDoReset[0])).toBe("novo cadastro fictício");
    expect(remover).not.toHaveBeenCalled();
    expect(gravar).not.toHaveBeenCalled();
  });

  it("em DEV marcador de versão anterior não impede o reset atual", async () => {
    vi.stubEnv("DEV", true);
    localStorage.setItem("feedback-control-reset-versao-anterior", "ok");
    const { executarResetBaseDesenvolvimento } = await import("./resetBaseDesenvolvimento");

    executarResetBaseDesenvolvimento();

    expect(localStorage.getItem(marcador)).toBe("ok");
    chavesDoReset.forEach((chave) => expect(localStorage.getItem(chave)).toBeNull());
  });

  it.each([null, "ok", "versão antiga"])(
    "em produção importar e chamar diretamente não acessa storage com marcador %s",
    async (valorMarcador) => {
      vi.stubEnv("DEV", false);
      if (valorMarcador !== null) localStorage.setItem(marcador, valorMarcador);
      const ler = vi.spyOn(localStorage, "getItem");
      const gravar = vi.spyOn(localStorage, "setItem");
      const remover = vi.spyOn(localStorage, "removeItem");
      const limpar = vi.spyOn(localStorage, "clear");

      const { executarResetBaseDesenvolvimento, resetBaseDesenvolvimentoHabilitado } =
        await import("./resetBaseDesenvolvimento");
      executarResetBaseDesenvolvimento();

      expect(resetBaseDesenvolvimentoHabilitado).toBe(false);
      expect(ler).not.toHaveBeenCalled();
      expect(gravar).not.toHaveBeenCalled();
      expect(remover).not.toHaveBeenCalled();
      expect(limpar).not.toHaveBeenCalled();
      chavesDoReset.forEach((chave) => expect(localStorage.getItem(chave)).toBe("dados fictícios"));
      expect(localStorage.getItem(marcador)).toBe(valorMarcador);
    }
  );
});
