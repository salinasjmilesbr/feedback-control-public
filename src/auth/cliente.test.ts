import { describe, expect, it } from "vitest";
import type { ConfiguracaoAmbiente } from "../config/ambiente";
import { criarClienteAuthSupabase } from "./cliente";

const configuracaoSemSupabase: ConfiguracaoAmbiente = Object.freeze({
  ambiente: "development",
});

const configuracaoValida: ConfiguracaoAmbiente = Object.freeze({
  ambiente: "development",
  supabaseUrl: "https://projeto-ficticio.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.assinatura_fake-AA11",
});

describe("cliente Supabase de autenticação (F2-03)", () => {
  it("retorna null quando Supabase não está configurado", () => {
    expect(criarClienteAuthSupabase(configuracaoSemSupabase)).toBeNull();
  });

  it("cria cliente de auth apenas com configuração pública válida", () => {
    const cliente = criarClienteAuthSupabase(configuracaoValida);
    expect(cliente).not.toBeNull();
    expect(typeof cliente?.auth.signInWithPassword).toBe("function");
    expect(typeof cliente?.auth.signOut).toBe("function");
    expect(typeof cliente?.auth.onAuthStateChange).toBe("function");
  });
});
