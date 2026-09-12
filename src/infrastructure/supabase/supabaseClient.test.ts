import { describe, expect, it } from "vitest";
import type { ConfiguracaoAmbiente } from "../../config/ambiente";
import { criarClienteSupabase, OPCOES_CLIENTE_SOBERANO } from "./supabaseClient";

const configuracaoSemSupabase: ConfiguracaoAmbiente = Object.freeze({
  ambiente: "development",
});

const configuracaoSomenteUrl: ConfiguracaoAmbiente = Object.freeze({
  ambiente: "development",
  supabaseUrl: "https://projeto-ficticio.supabase.co",
});

const configuracaoValida: ConfiguracaoAmbiente = Object.freeze({
  ambiente: "development",
  supabaseUrl: "https://projeto-ficticio.supabase.co",
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.assinatura_fake-AA11",
});

describe("cliente Supabase encapsulado em infrastructure (F1-04)", () => {
  it("retorna null quando Supabase não está configurado", () => {
    expect(criarClienteSupabase(configuracaoSemSupabase)).toBeNull();
  });

  it("retorna null quando apenas a URL está presente", () => {
    expect(criarClienteSupabase(configuracaoSomenteUrl)).toBeNull();
  });

  it("cria cliente apenas com configuração pública válida", () => {
    const cliente = criarClienteSupabase(configuracaoValida);
    expect(cliente).not.toBeNull();
    expect(typeof cliente?.from).toBe("function");
  });

  /**
   * F5-08 P4: o cliente soberano LÊ a sessão persistida pelo cliente de auth
   * (fonte única) e NÃO mantém um segundo mecanismo de renovação — sem JWT as
   * chamadas à Edge sairiam sem identidade e as leituras RLS devolveriam vazio.
   */
  it("carrega a sessão persistida e não duplica o refresh do cliente de auth", () => {
    expect(OPCOES_CLIENTE_SOBERANO.auth.persistSession).toBe(true);
    expect(OPCOES_CLIENTE_SOBERANO.auth.autoRefreshToken).toBe(false);
    expect(OPCOES_CLIENTE_SOBERANO.auth.detectSessionInUrl).toBe(false);
  });
});
