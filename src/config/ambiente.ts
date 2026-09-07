export type Ambiente = "development" | "homologation" | "production";

interface VariaveisAmbiente {
  DEV?: boolean;
  PROD?: boolean;
  VITE_APP_ENV?: string;
  VITE_PUBLIC_API_URL?: string;
  VITE_SUPABASE_URL?: string;
  VITE_SUPABASE_ANON_KEY?: string;
}

export interface ConfiguracaoAmbiente {
  readonly ambiente: Ambiente;
  readonly urlApiPublica?: string;
  readonly supabaseUrl?: string;
  readonly supabaseAnonKey?: string;
}

export function resolverConfiguracaoAmbiente(
  variaveis: VariaveisAmbiente
): ConfiguracaoAmbiente {
  const contextoDev = variaveis.DEV === true && variaveis.PROD === false;
  const informado = variaveis.VITE_APP_ENV?.trim();
  const ambiente = informado || (contextoDev ? "development" : "production");

  if (ambiente !== "development" && ambiente !== "homologation" && ambiente !== "production") {
    throw new Error("VITE_APP_ENV deve ser development, homologation ou production.");
  }
  if (ambiente === "development" && !contextoDev) {
    throw new Error("VITE_APP_ENV=development exige o contexto DEV do Vite.");
  }

  const urlApiPublica = variaveis.VITE_PUBLIC_API_URL?.trim() || undefined;
  if (urlApiPublica) {
    let url: URL;
    try {
      url = new URL(urlApiPublica);
    } catch {
      throw new Error("VITE_PUBLIC_API_URL deve ser uma URL pública HTTP(S) absoluta.");
    }
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) {
      throw new Error("VITE_PUBLIC_API_URL deve usar HTTP(S), sem credenciais na URL.");
    }
  }

  const supabaseUrl = variaveis.VITE_SUPABASE_URL?.trim() || undefined;
  const supabaseAnonKey = variaveis.VITE_SUPABASE_ANON_KEY?.trim() || undefined;

  if (Boolean(supabaseUrl) !== Boolean(supabaseAnonKey)) {
    throw new Error("VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY devem ser definidas juntas.");
  }
  if (supabaseUrl) {
    let url: URL;
    try {
      url = new URL(supabaseUrl);
    } catch {
      throw new Error("VITE_SUPABASE_URL deve ser uma URL pública HTTP(S) absoluta.");
    }
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) {
      throw new Error("VITE_SUPABASE_URL deve usar HTTP(S), sem credenciais na URL.");
    }
  }
  if (supabaseAnonKey && !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(supabaseAnonKey)) {
    throw new Error("VITE_SUPABASE_ANON_KEY deve ser uma chave anônima pública no formato JWT.");
  }

  return Object.freeze({ ambiente, urlApiPublica, supabaseUrl, supabaseAnonKey });
}

// Único ponto de leitura: variáveis VITE_* são públicas e incorporadas ao frontend.
export const configuracaoAmbiente = resolverConfiguracaoAmbiente({
  DEV: import.meta.env.DEV,
  PROD: import.meta.env.PROD,
  VITE_APP_ENV: import.meta.env.VITE_APP_ENV,
  VITE_PUBLIC_API_URL: import.meta.env.VITE_PUBLIC_API_URL,
  VITE_SUPABASE_URL: import.meta.env.VITE_SUPABASE_URL,
  VITE_SUPABASE_ANON_KEY: import.meta.env.VITE_SUPABASE_ANON_KEY,
});

// A condição estática também permite eliminar o reset do bundle de produção.
export const resetDesenvolvimentoPermitido =
  import.meta.env.DEV && !import.meta.env.PROD && configuracaoAmbiente.ambiente === "development";

/**
 * Gate de DEV para a impersonação/simulação de desenvolvimento (F2-09 —
 * `UsuarioAtualProvider`/seletor) e demais conveniências de DEV (guard F2-04).
 * É sempre false fora do contexto DEV do Vite com ambiente development: em
 * HOMOLOG/PROD nenhuma identidade simulada substitui autenticação real e o
 * seletor de impersonação não é exibido nem aceita troca local.
 */
export const simulacaoDevPermitida =
  import.meta.env.DEV && !import.meta.env.PROD && configuracaoAmbiente.ambiente === "development";

/** Uso futuro: só exigir a URL quando o consumidor realmente precisar dela. */
export function exigirUrlApiPublica(
  configuracao: ConfiguracaoAmbiente = configuracaoAmbiente
): string {
  if (!configuracao.urlApiPublica) {
    throw new Error(`VITE_PUBLIC_API_URL é obrigatória para esta operação em ${configuracao.ambiente}.`);
  }
  return configuracao.urlApiPublica;
}
