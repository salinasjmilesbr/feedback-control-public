import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { BrandingConfig } from "../types/Branding";
import { salvarBranding } from "../services/brandingStorage";
import { BrandingProvider } from "./BrandingProvider";
import { useBranding } from "./BrandingContext";
import fonteProvider from "./BrandingProvider.tsx?raw";
import fonteStorage from "../services/brandingStorage.ts?raw";
import fonteTema from "../services/temaTenant.ts?raw";

/**
 * Issue #317 (Fase 1) — barreiras da arquitetura de theming:
 * (a) NENHUM tema de tenant em elemento global;
 * (b) escopo explícito (plataforma ⇒ mapa vazio);
 * (c) segregação por organização.
 */

const ORG = "a1a1a1a1-0000-4000-8000-000000000001";

const estadoAuth = vi.hoisted(() => ({
  organizacaoAtivaId: null as string | null,
}));

vi.mock("../auth/AuthContext", () => ({
  useAuth: () => ({ organizacaoAtivaId: estadoAuth.organizacaoAtivaId }),
}));

const configTenant: BrandingConfig = {
  nomeSistema: "Organização Sintética",
  subtituloSistema: "Subtítulo sintético",
  corPrimaria: "#112233",
  corSecundaria: "#445566",
  corDestaque: "#778899",
  corFundo: "#fafafa",
};

function Sonda() {
  const { tema, branding } = useBranding();

  return (
    <span
      data-escopo={tema.escopo}
      data-variaveis={JSON.stringify(tema.variaveis)}
      data-nome={branding.nomeSistema}
    />
  );
}

function renderizar(): string {
  return renderToStaticMarkup(
    <BrandingProvider>
      <Sonda />
    </BrandingProvider>
  );
}

describe("BrandingProvider — escopo do tema (#317)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    estadoAuth.organizacaoAtivaId = null;
  });

  it("sem organização ativa (plataforma) o tema é VAZIO, mesmo com tenant salvo", () => {
    salvarBranding(ORG, configTenant);

    const html = renderizar();

    expect(html).toContain('data-escopo="plataforma"');
    expect(html).toContain("data-variaveis=\"{}\"");
    expect(html).not.toContain("#112233");
    expect(html).not.toContain("Organização Sintética");
  });

  it("com organização ativa o mapa é do tenant e vem daquela organização", () => {
    salvarBranding(ORG, configTenant);
    estadoAuth.organizacaoAtivaId = ORG;

    const html = renderizar();

    expect(html).toContain('data-escopo="tenant"');
    expect(html).toContain("--brand-primary");
    expect(html).toContain("#112233");
    expect(html).toContain("Organização Sintética");
  });

  it("trocar de organização troca o tema (não há estado global de aparência)", () => {
    salvarBranding(ORG, configTenant);
    estadoAuth.organizacaoAtivaId = ORG;
    const comTenant = renderizar();

    estadoAuth.organizacaoAtivaId = "b2b2b2b2-0000-4000-8000-000000000002";
    const outraOrganizacao = renderizar();

    expect(comTenant).toContain("#112233");
    expect(outraOrganizacao).toContain('data-escopo="tenant"');
    expect(outraOrganizacao).not.toContain("#112233");
  });
});

/**
 * A barreira vale para o CÓDIGO, nunca para a prosa que DESCREVE o que o módulo
 * não faz (mesma semântica do helper `apenasCodigo` de
 * `src/authorization/estruturaUiSeguranca.test.ts`).
 */
function apenasCodigo(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

describe("BrandingProvider — barreiras estáticas do theming (#317)", () => {
  it("o provedor NÃO escreve tema em elemento global (documentElement/body/setProperty)", () => {
    const codigo = apenasCodigo(fonteProvider);

    expect(codigo).not.toContain("documentElement");
    expect(codigo).not.toContain("document.body");
    expect(codigo).not.toContain("setProperty");
    // Nada de reescrever o `:root` por JS.
    expect(codigo).not.toContain(":root");
  });

  it("o provedor depende da ORGANIZAÇÃO ATIVA para resolver a aparência", () => {
    const codigo = apenasCodigo(fonteProvider);

    expect(codigo).toContain("organizacaoAtivaId");
    expect(codigo).toContain("temaDoTenant");
    expect(codigo).toContain("tituloDaPagina");
  });

  it("a persistência só usa a chave por organização e não toca a chave legada global", () => {
    const codigo = apenasCodigo(fonteStorage);

    expect(codigo).toContain("PREFIXO_CHAVE_BRANDING");
    expect(codigo).not.toMatch(/getItem\(\s*CHAVE_LEGADA_BRANDING/);
    expect(codigo).not.toMatch(/setItem\(\s*CHAVE_LEGADA_BRANDING/);
    expect(codigo).not.toMatch(/removeItem\(\s*CHAVE_LEGADA_BRANDING/);
  });

  it("o cálculo do tema é PURO: nenhum acesso a DOM", () => {
    const codigo = apenasCodigo(fonteTema);

    expect(codigo).not.toMatch(/document\./);
    expect(codigo).not.toContain("window.");
  });
});
