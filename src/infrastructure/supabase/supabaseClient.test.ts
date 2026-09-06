import { describe, expect, it } from "vitest";
import type { ConfiguracaoAmbiente } from "../../config/ambiente";
import { criarClienteSupabase } from "./supabaseClient";

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
});
