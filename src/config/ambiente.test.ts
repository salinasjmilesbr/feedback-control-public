import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("configuração central de ambiente", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.stubEnv("DEV", false);
    vi.stubEnv("VITE_APP_ENV", undefined);
    vi.stubEnv("VITE_PUBLIC_API_URL", undefined);
  });

  afterEach(() => vi.unstubAllEnvs());

  it.each([
    [true, undefined, "development", true],
    [false, undefined, "production", false],
    [false, "", "production", false],
    [true, "development", "development", true],
    [true, "homologation", "homologation", false],
    [false, "homologation", "homologation", false],
    [true, "production", "production", false],
    [false, "production", "production", false],
  ] as const)("DEV=%s, configuração=%s resolve %s e reset=%s", async (dev, informado, esperado, reset) => {
    vi.stubEnv("DEV", dev);
    vi.stubEnv("VITE_APP_ENV", informado);
    const modulo = await import("./ambiente");

    expect(modulo.configuracaoAmbiente.ambiente).toBe(esperado);
    expect(modulo.resetDesenvolvimentoPermitido).toBe(reset);
    expect(modulo.configuracaoAmbiente.urlApiPublica).toBeUndefined();
    expect(Object.isFrozen(modulo.configuracaoAmbiente)).toBe(true);
  });

  it("sem contexto confiável resolve produção, inclusive com flags contraditórias", async () => {
    const { resolverConfiguracaoAmbiente } = await import("./ambiente");
    expect(resolverConfiguracaoAmbiente({}).ambiente).toBe("production");
    expect(resolverConfiguracaoAmbiente({ DEV: true, PROD: true }).ambiente).toBe("production");
  });

  it.each(["invalido", "development"])("produção rejeita configuração %s", async (ambiente) => {
    vi.stubEnv("VITE_APP_ENV", ambiente);
    await expect(import("./ambiente")).rejects.toThrow("VITE_APP_ENV");
  });

  it("URL futura é opcional até ser exigida por uma operação", async () => {
    const { exigirUrlApiPublica, resolverConfiguracaoAmbiente } = await import("./ambiente");
    for (const ambiente of ["homologation", "production"]) {
      const configuracao = resolverConfiguracaoAmbiente({ VITE_APP_ENV: ambiente });
      expect(() => exigirUrlApiPublica(configuracao)).toThrow(
        `VITE_PUBLIC_API_URL é obrigatória para esta operação em ${ambiente}.`
      );
    }
    const configuracao = resolverConfiguracaoAmbiente({ VITE_PUBLIC_API_URL: "https://api.example.invalid" });
    expect(exigirUrlApiPublica(configuracao)).toBe("https://api.example.invalid");
  });

  it.each(["relativa", "ftp://example.invalid", "https://usuario:senha-ficticia@example.invalid"])(
    "rejeita URL inválida sem expor seu conteúdo: %s", async (url) => {
      vi.stubEnv("VITE_PUBLIC_API_URL", url);
      await expect(import("./ambiente")).rejects.toThrow("VITE_PUBLIC_API_URL");
      await expect(import("./ambiente")).rejects.not.toThrow(url);
    }
  );
});
