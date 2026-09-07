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

  it.each([
    [true, undefined, true],
    [true, "development", true],
    [false, undefined, false],
    [false, "production", false],
    [true, "homologation", false],
    [true, "production", false],
  ] as const)("simulação DEV (F2-04): DEV=%s, ambiente=%s => %s", async (dev, informado, simulacao) => {
    vi.stubEnv("DEV", dev);
    vi.stubEnv("VITE_APP_ENV", informado);
    const modulo = await import("./ambiente");

    expect(modulo.simulacaoDevPermitida).toBe(simulacao);
    expect(modulo.simulacaoDevPermitida).toBe(modulo.resetDesenvolvimentoPermitido);
  });

  it("HOMOLOG/PROD nunca habilitam a impersonação DEV, mesmo com flags DEV ligadas (F2-09)", async () => {
    const combinacoes: ReadonlyArray<readonly [boolean, string]> = [
      [true, "homologation"],
      [false, "homologation"],
      [true, "production"],
      [false, "production"],
    ];

    for (const [dev, informado] of combinacoes) {
      vi.resetModules();
      vi.stubEnv("DEV", dev);
      vi.stubEnv("PROD", false);
      vi.stubEnv("VITE_APP_ENV", informado);
      const modulo = await import("./ambiente");

      expect(modulo.configuracaoAmbiente.ambiente).toBe(informado);
      expect(modulo.simulacaoDevPermitida).toBe(false);
    }
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

  it("Supabase ausente permanece opcional e sem efeito", async () => {
    const { resolverConfiguracaoAmbiente } = await import("./ambiente");
    const configuracao = resolverConfiguracaoAmbiente({ VITE_APP_ENV: "production" });
    expect(configuracao.supabaseUrl).toBeUndefined();
    expect(configuracao.supabaseAnonKey).toBeUndefined();
  });

  it("resolve configuração Supabase pública válida", async () => {
    const { resolverConfiguracaoAmbiente } = await import("./ambiente");
    const url = "https://projeto-ficticio.supabase.co";
    const chave = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.assinatura_fake-AA11";
    const configuracao = resolverConfiguracaoAmbiente({
      VITE_APP_ENV: "production",
      VITE_SUPABASE_URL: `  ${url}  `,
      VITE_SUPABASE_ANON_KEY: `  ${chave}  `,
    });
    expect(configuracao.supabaseUrl).toBe(url);
    expect(configuracao.supabaseAnonKey).toBe(chave);
  });

  it.each([
    { rotulo: "somente URL", variaveis: { VITE_SUPABASE_URL: "https://projeto-ficticio.supabase.co" } },
    { rotulo: "somente chave", variaveis: { VITE_SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.fake" } },
  ] as const)("Supabase parcial ($rotulo) exige URL e chave juntas", async ({ variaveis }) => {
    const { resolverConfiguracaoAmbiente } = await import("./ambiente");
    expect(() => resolverConfiguracaoAmbiente(variaveis)).toThrow("devem ser definidas juntas");
  });

  it.each(["supabase.local", "ftp://projeto.supabase.co", "https://usuario:senha@projeto.supabase.co"])(
    "Supabase rejeita URL inválida ou com credenciais: %s", async (url) => {
      const { resolverConfiguracaoAmbiente } = await import("./ambiente");
      const chave = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.fake";
      expect(() => resolverConfiguracaoAmbiente({ VITE_SUPABASE_URL: url, VITE_SUPABASE_ANON_KEY: chave })).toThrow(
        "VITE_SUPABASE_URL"
      );
    }
  );

  it.each(["chave", "abc.def", "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.chave com espaco"])(
    "Supabase rejeita chave anônima fora do formato JWT: %s", async (chave) => {
      const { resolverConfiguracaoAmbiente } = await import("./ambiente");
      expect(() =>
        resolverConfiguracaoAmbiente({
          VITE_SUPABASE_URL: "https://projeto-ficticio.supabase.co",
          VITE_SUPABASE_ANON_KEY: chave,
        })
      ).toThrow("VITE_SUPABASE_ANON_KEY");
    }
  );
});
