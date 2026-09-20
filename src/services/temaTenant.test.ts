import { describe, expect, it } from "vitest";
import type { BrandingConfig } from "../types/Branding";
import { brandingPadrao } from "./brandingStorage";
import { TITULO_PLATAFORMA, temaDoTenant, tituloDaPagina } from "./temaTenant";

/**
 * Issue #317 (Fase 1) — tradução PURA da aparência do tenant para custom
 * properties, com escopo explícito e sem qualquer DOM.
 */

const ORG = "a1a1a1a1-0000-4000-8000-000000000001";

const configTenant: BrandingConfig = {
  nomeSistema: "Organização Sintética",
  subtituloSistema: "Subtítulo sintético",
  corPrimaria: "#112233",
  corSecundaria: "#445566",
  corDestaque: "#778899",
  corFundo: "#fafafa",
};

describe("temaDoTenant — escopo e mapa de custom properties (#317)", () => {
  it("PLATAFORMA (sem organização ativa) ⇒ escopo plataforma e mapa VAZIO", () => {
    for (const semOrganizacao of [null, undefined, ""]) {
      const tema = temaDoTenant(semOrganizacao, configTenant);

      expect(tema.escopo).toBe("plataforma");
      expect(tema.variaveis).toEqual({});
    }
  });

  it("TENANT (com organização ativa) ⇒ escopo tenant e apenas o conjunto fechado de cores", () => {
    const tema = temaDoTenant(ORG, configTenant);

    expect(tema.escopo).toBe("tenant");
    expect(tema.variaveis).toEqual({
      "--brand-primary": "#112233",
      "--brand-secondary": "#445566",
      "--brand-accent": "#778899",
      "--brand-bg": "#fafafa",
    });
  });

  it("NUNCA devolve tokens de plataforma (`--virtus-*`) no mapa do tenant", () => {
    const chaves = Object.keys(temaDoTenant(ORG, configTenant).variaveis);

    expect(chaves.every((chave) => chave.startsWith("--brand-"))).toBe(true);
  });

  it("cor inválida cai no default seguro (fail-closed), nunca em valor de terceiro", () => {
    const tema = temaDoTenant(ORG, {
      ...configTenant,
      corPrimaria: "vermelho",
      corSecundaria: "#12345",
      corDestaque: "  ",
      corFundo: "#ABCDEF",
    });

    expect(tema.variaveis["--brand-primary"]).toBe(brandingPadrao.corPrimaria);
    expect(tema.variaveis["--brand-secondary"]).toBe(
      brandingPadrao.corSecundaria
    );
    expect(tema.variaveis["--brand-accent"]).toBe(brandingPadrao.corDestaque);
    // Hex de 6 dígitos em caixa alta é válido e preservado (trim aplicado).
    expect(tema.variaveis["--brand-bg"]).toBe("#ABCDEF");
  });

  it("a plataforma não recebe NADA do tenant mesmo com configuração preenchida", () => {
    const tema = temaDoTenant(null, configTenant);

    expect(JSON.stringify(tema.variaveis)).not.toContain("#112233");
    expect(JSON.stringify(tema.variaveis)).not.toContain(
      configTenant.nomeSistema
    );
  });
});

describe("tituloDaPagina — título por contexto (#317)", () => {
  it("plataforma ⇒ título da identidade Virtus, nunca o nome legado", () => {
    expect(TITULO_PLATAFORMA).toBe("Virtus");
    expect(tituloDaPagina(null, configTenant)).toBe("Virtus");
    expect(tituloDaPagina(undefined, configTenant)).toBe("Virtus");
    expect(tituloDaPagina(null, configTenant)).not.toBe("Feedback Control");
  });

  it("tenant ⇒ nome da organização, com fallback no título fixo", () => {
    expect(tituloDaPagina(ORG, configTenant)).toBe("Organização Sintética");
    expect(tituloDaPagina(ORG, { ...configTenant, nomeSistema: "   " })).toBe(
      TITULO_PLATAFORMA
    );
  });
});
