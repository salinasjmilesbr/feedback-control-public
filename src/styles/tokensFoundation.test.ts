/// <reference types="node" />
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * Issue #317 (Fase 1) — guarda da FUNDAÇÃO DE TOKENS.
 *
 * Duas invariantes que a reconstrução tem de manter:
 * 1. `src/styles/virtus-tokens.css` é a FONTE ÚNICA de `--virtus-*` (estrutura da
 *    plataforma) e dos defaults de `--brand-*` (superfície de theming do tenant);
 * 2. nenhuma outra folha de estilo declara esses tokens — sem isso a aparência
 *    volta a depender da ORDEM de import (defeito da branch experimental).
 *
 * POR QUE LER DO DISCO (e não `import ... from "*.css?raw"`): o Vitest roda com
 * `css: false` (padrão, sem bloco `test` no `vite.config.ts`), ou seja, CSS é
 * substituído por stub — um `?raw` de `.css` devolve **string VAZIA**. Uma guarda
 * escrita assim passa sem verificar nada (foi o caso da guarda da #315). Aqui a
 * leitura é do arquivo real, com `node:fs`, o que também cobre arquivos que o
 * bundler não veria.
 */

const DIR_SRC = fileURLToPath(new URL("..", import.meta.url));
const CAMINHO_RELATIVO_TOKENS = "styles/virtus-tokens.css";
const CAMINHO_TOKENS = join(DIR_SRC, "styles", "virtus-tokens.css");
const CAMINHO_ENTRYPOINT = join(DIR_SRC, "main.tsx");

/** Todas as folhas de estilo sob `src/`, por caminho relativo (com `/`). */
function folhasDeEstilo(): ReadonlyArray<readonly [string, string]> {
  const nomes = readdirSync(DIR_SRC, { recursive: true, encoding: "utf8" })
    .map((nome) => nome.replace(/\\/g, "/"))
    .filter((nome) => nome.endsWith(".css"))
    .sort();

  return nomes.map(
    (nome) => [nome, readFileSync(join(DIR_SRC, nome), "utf8")] as const
  );
}

/** Tokens com declaração esperada EXATAMENTE uma vez (base). */
const TOKENS_UNICOS = [
  "--virtus-container",
  "--virtus-gutter-desktop",
  "--virtus-gutter-tablet",
  "--virtus-gutter-mobile",
  "--virtus-font-aux",
  "--virtus-font-label",
  "--virtus-font-body",
  "--virtus-font-body-strong",
  "--virtus-font-nav",
  "--brand-primary",
  "--brand-secondary",
  "--brand-accent",
  "--brand-bg",
  "--brand-surface",
  "--brand-surface-soft",
  "--brand-text",
  "--brand-text-muted",
  "--brand-border",
  "--brand-radius",
  "--brand-shadow",
] as const;

/**
 * Conta DECLARAÇÕES — não usos `var(--token)` e não prefixos de token mais longo:
 * o lookbehind recusa `(`/`-`/`\w` antes do token e o `:` é obrigatório depois,
 * de modo que `--virtus-gutter` não casa dentro de `--virtus-gutter-tablet` nem
 * `var(--brand-primary)`.
 */
function declaracoes(fonte: string, token: string): number {
  const padrao = new RegExp(`(?<![\\w-])${token}\\s*:`, "g");
  return (fonte.match(padrao) ?? []).length;
}

describe("Foundation de tokens — fonte única (#317)", () => {
  it("o índice cobre o repositório e o arquivo de tokens tem conteúdo real", () => {
    const folhas = folhasDeEstilo();
    const nomes = folhas.map(([nome]) => nome);
    const tokens = folhas.find(([nome]) => nome === CAMINHO_RELATIVO_TOKENS);

    expect(nomes.length).toBeGreaterThan(20);
    expect(nomes, nomes.join(", ")).toContain(CAMINHO_RELATIVO_TOKENS);
    expect((tokens?.[1] ?? "").length).toBeGreaterThan(200);
  });

  it("o arquivo de tokens declara `--virtus-*` de estrutura e os defaults de `--brand-*`", () => {
    const tokens = readFileSync(CAMINHO_TOKENS, "utf8");

    for (const token of TOKENS_UNICOS) {
      expect(declaracoes(tokens, token), token).toBe(1);
    }
    // Override responsivo do gutter: base + 900px + 620px, no MESMO arquivo.
    expect(declaracoes(tokens, "--virtus-gutter")).toBe(3);
  });

  it("o arquivo de tokens não usa `!important`", () => {
    expect(readFileSync(CAMINHO_TOKENS, "utf8")).not.toContain("!important");
  });

  it("os defaults de `--brand-*` seguem a paleta OFICIAL Virtus (#312)", () => {
    const tokens = readFileSync(CAMINHO_TOKENS, "utf8");
    // Recorte do bloco de theming do tenant: os semânticos da plataforma não
    // entram nesta checagem (verde só é permitido como estado de sucesso).
    const blocoBrand = tokens.split("Superfície de theming do tenant")[1] ?? "";
    const minusculo = blocoBrand.toLowerCase();

    expect(blocoBrand.length).toBeGreaterThan(100);
    for (const cor of ["#6366f1", "#0f172a", "#0ea5e9", "#f1f5f9", "#e2e8f0", "#64748b"]) {
      expect(minusculo, cor).toContain(cor);
    }
    // Nunca a identidade legada nem verde como branding (contrato #312 §2).
    expect(minusculo).not.toContain("#660099");
    expect(minusculo).not.toContain("#8a2be2");
    expect(minusculo).not.toContain("#10b981");
  });

  it("NENHUM outro CSS declara `--virtus-*` de estrutura nem `--brand-*` (anti-ordem de import)", () => {
    const problemas: string[] = [];

    for (const [nome, fonte] of folhasDeEstilo()) {
      if (nome === CAMINHO_RELATIVO_TOKENS) continue;
      for (const token of TOKENS_UNICOS) {
        if (declaracoes(fonte, token) > 0) problemas.push(`${nome}: ${token}`);
      }
      if (declaracoes(fonte, "--virtus-gutter") > 0) {
        problemas.push(`${nome}: --virtus-gutter`);
      }
    }

    expect(problemas).toEqual([]);
  });

  it("a fundação é importada antes do CSS legado (ordem explícita no entrypoint)", () => {
    const entrypoint = readFileSync(CAMINHO_ENTRYPOINT, "utf8");
    const posTokens = entrypoint.indexOf("./styles/virtus-tokens.css");
    const posIndex = entrypoint.indexOf("./index.css");

    expect(posTokens).toBeGreaterThan(-1);
    expect(posIndex).toBeGreaterThan(-1);
    expect(posTokens).toBeLessThan(posIndex);
  });
});
