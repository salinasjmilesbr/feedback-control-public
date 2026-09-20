import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { BrandingConfig } from "../types/Branding";
import {
  CHAVE_LEGADA_BRANDING,
  PREFIXO_CHAVE_BRANDING,
  brandingPadrao,
  getBranding,
  resetarBranding,
  salvarBranding,
} from "./brandingStorage";

/**
 * Issue #317 (Fase 1) — a aparência é do TENANT e tem de ficar isolada por
 * organização. Dados sintéticos: nenhum nome/logo real.
 */

const ORG_A = "a1a1a1a1-0000-4000-8000-000000000001";
const ORG_B = "b2b2b2b2-0000-4000-8000-000000000002";

function configuracao(nome: string, corPrimaria: string): BrandingConfig {
  return {
    nomeSistema: nome,
    subtituloSistema: "Subtítulo sintético",
    corPrimaria,
    corSecundaria: "#445566",
    corDestaque: "#778899",
    corFundo: "#ffffff",
  };
}

describe("brandingStorage — aparência segregada por organização (#317)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it("sem organização ativa devolve os defaults seguros (superfície de plataforma)", () => {
    expect(getBranding(null)).toEqual(brandingPadrao);
    expect(getBranding(undefined)).toEqual(brandingPadrao);
    expect(getBranding("")).toEqual(brandingPadrao);
  });

  it("o padrão seguro é a identidade OFICIAL Virtus (#312), nunca a legada", () => {
    expect(brandingPadrao.nomeSistema).toBe("Virtus");
    expect(brandingPadrao.subtituloSistema).toBe(
      "Performance & Feedback Management"
    );
    // Paleta aprovada: destaque (CTA), primário navy, apoio, superfície.
    expect(brandingPadrao.corPrimaria).toBe("#6366F1");
    expect(brandingPadrao.corSecundaria).toBe("#0F172A");
    expect(brandingPadrao.corDestaque).toBe("#0EA5E9");
    expect(brandingPadrao.corFundo).toBe("#F1F5F9");

    const serializado = JSON.stringify(brandingPadrao);
    expect(serializado).not.toContain("Feedback Control");
    expect(serializado.toUpperCase()).not.toContain("#660099");
    expect(serializado.toUpperCase()).not.toContain("#8A2BE2");
  });

  it("grava e lê a aparência de UMA organização", () => {
    salvarBranding(ORG_A, configuracao("Alfa", "#112233"));

    expect(getBranding(ORG_A).nomeSistema).toBe("Alfa");
    expect(getBranding(ORG_A).corPrimaria).toBe("#112233");
  });

  it("ISOLAMENTO: duas organizações no mesmo navegador não compartilham aparência", () => {
    salvarBranding(ORG_A, configuracao("Alfa", "#112233"));
    salvarBranding(ORG_B, configuracao("Beta", "#445566"));

    expect(getBranding(ORG_A).nomeSistema).toBe("Alfa");
    expect(getBranding(ORG_B).nomeSistema).toBe("Beta");

    // A organização sem configuração própria recebe os defaults, nunca a de outra.
    expect(getBranding("c3c3c3c3-0000-4000-8000-000000000003")).toEqual(
      brandingPadrao
    );
  });

  it("a chave gravada inclui o organizationId (não existe chave de escopo global)", () => {
    salvarBranding(ORG_A, configuracao("Alfa", "#112233"));

    expect(localStorage.getItem(`${PREFIXO_CHAVE_BRANDING}${ORG_A}`)).not.toBeNull();
    expect(localStorage.getItem(CHAVE_LEGADA_BRANDING)).toBeNull();
  });

  it("NÃO lê a chave legada global — adotá-la reintroduziria vazamento entre tenants", () => {
    localStorage.setItem(
      CHAVE_LEGADA_BRANDING,
      JSON.stringify(configuracao("Legado", "#000000"))
    );

    expect(getBranding(ORG_A)).toEqual(brandingPadrao);
    expect(getBranding(null)).toEqual(brandingPadrao);
  });

  it("configuração corrompida cai nos defaults seguros (fail-closed)", () => {
    localStorage.setItem(`${PREFIXO_CHAVE_BRANDING}${ORG_A}`, "{nao-e-json");

    expect(getBranding(ORG_A)).toEqual(brandingPadrao);
  });

  it("resetarBranding remove apenas a chave da organização informada", () => {
    salvarBranding(ORG_A, configuracao("Alfa", "#112233"));
    salvarBranding(ORG_B, configuracao("Beta", "#445566"));

    expect(resetarBranding(ORG_A)).toEqual(brandingPadrao);
    expect(getBranding(ORG_A)).toEqual(brandingPadrao);
    expect(getBranding(ORG_B).nomeSistema).toBe("Beta");
  });

  it("salvar sem organização não grava nada (fail-closed)", () => {
    salvarBranding("", configuracao("Alfa", "#112233"));

    expect(localStorage.length).toBe(0);
  });

  it("mantém o fallback de forma legada (`nomeEmpresa`) dentro do payload da organização", () => {
    localStorage.setItem(
      `${PREFIXO_CHAVE_BRANDING}${ORG_A}`,
      JSON.stringify({ nomeEmpresa: "Empresa Sintética" })
    );

    expect(getBranding(ORG_A).subtituloSistema).toBe("Empresa Sintética");
  });
});
