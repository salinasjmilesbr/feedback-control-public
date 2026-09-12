/**
 * F5-09 P5 — GUARDAS ESTÁTICOS da leitura soberana de ciclos.
 *
 * Sweeps globais sobre os módulos de PRODUÇÃO (`import.meta.glob`), no padrão de
 * `src/authorization/estruturaUiSeguranca.test.ts` (F5-08 P6): um arquivo NOVO que
 * reintroduza leitura local de ciclo como autoridade, dual-read ou fallback
 * silencioso é reprovado sem depender de lista manual.
 *
 * O que se prova:
 *  1. a PORTA (`application/ports/CycleRepository.ts`) é ASSÍNCRONA e UUID-first:
 *     nenhum método do contrato síncrono/local antigo e nenhum import de storage;
 *  2. o caminho SOBERANO (adapter de RLS + porta de serviço) não IMPORTA o storage
 *     local nem o adapter legado — não há como ele cair para o `localStorage`;
 *  3. NENHUM módulo de produção faz dual-read: quem importa o caminho soberano
 *     NUNCA importa o storage local de ciclos;
 *  4. `localCycleRepository` continua explicitamente classificado como LEGACY.
 *
 * As asserções usam IMPORT (e não texto cru): os cabeçalhos dos módulos soberanos
 * MENCIONAM `localStorage` justamente para documentar que ele não participa.
 */

import { describe, expect, it } from "vitest";

const MODULOS: Readonly<Record<string, string>> = Object.fromEntries(
  Object.entries(
    import.meta.glob("../**/*.{ts,tsx}", {
      query: "?raw",
      import: "default",
      eager: true,
    })
  ).filter(([caminho]) => !caminho.includes(".test."))
) as Readonly<Record<string, string>>;

/**
 * Resolve o módulo de produção pelo SUFIXO distintivo do caminho: as chaves do
 * `import.meta.glob` são relativas ao arquivo de teste (`./` para o próprio
 * diretório), então o sufixo é mais estável que o caminho literal.
 */
function fonte(sufixo: string): string {
  const encontrados = Object.entries(MODULOS).filter(([caminho]) => caminho.endsWith(sufixo));
  if (encontrados.length !== 1) {
    const chaves = encontrados.map(([caminho]) => caminho).join(", ") || "nenhum";
    throw new Error(`Esperado exatamente 1 módulo com sufixo "${sufixo}"; encontrados: ${chaves}`);
  }
  return encontrados[0][1];
}

/** `true` quando o módulo importa (estática ou dinamicamente) o caminho dado. */
function importa(modulo: string, conteudo: string): boolean {
  const estatico = new RegExp(`from\\s+["'][^"']*${modulo}["']`).test(conteudo);
  const dinamico = new RegExp(`import\\(\\s*["'][^"']*${modulo}["']`).test(conteudo);
  return estatico || dinamico;
}

const PORTA = "ports/CycleRepository.ts";
const ADAPTER = "ciclos/repositorioCiclosSoberanos.ts";
const SERVICO = "acessoCiclosSoberanos.ts";
const LEGADO = "localCycleRepository.ts";
/** Trecho do caminho soberano suficiente para reconhecer quem o importa. */
const MODULOS_SOBERANOS = ["repositorioCiclosSoberanos", "acessoCiclosSoberanos"];

describe("F5-09 P5 — guardas estáticos da leitura soberana de ciclos", () => {
  it("a porta é assíncrona e falha com código público (sem contrato síncrono local)", () => {
    const conteudo = fonte(PORTA);

    // Contrato assíncrono e UUID-first.
    expect(conteudo).toContain("interface CycleRepository");
    expect(conteudo).toContain("listarCiclos(");
    expect(conteudo).toContain("obterCicloAtivo(");
    expect(conteudo).toMatch(/Promise<ResultadoCiclos/);
    expect(conteudo).toContain("cycleId: string");

    // O contrato síncrono/local anterior não pode sobreviver na porta.
    expect(conteudo).not.toContain("getCiclosAvaliacao(");
    expect(conteudo).not.toContain("getCicloAtivo(");
    expect(conteudo).not.toContain("criarCiclo(");
    expect(importa("localStorage", conteudo)).toBe(false);
    expect(importa("cicloAvaliacaoStorage", conteudo)).toBe(false);
    expect(importa("localCycleRepository", conteudo)).toBe(false);
  });

  it("o caminho soberano (RLS) não importa storage local nem adapter legado", () => {
    for (const sufixo of [ADAPTER, SERVICO]) {
      const conteudo = fonte(sufixo);
      expect(importa("cicloAvaliacaoStorage", conteudo)).toBe(false);
      expect(importa("localCycleRepository", conteudo)).toBe(false);
      expect(importa("localStorage", conteudo)).toBe(false);
      // Nem a chave física do storage legado pode aparecer no caminho soberano.
      expect(conteudo).not.toContain("feedback-control-ciclos");
    }
  });

  it("nenhum módulo de produção faz dual-read (soberano + storage local juntos)", () => {
    const comSoberano = Object.entries(MODULOS)
      .filter(([, conteudo]) => MODULOS_SOBERANOS.some((modulo) => importa(modulo, conteudo)))
      .map(([caminho]) => caminho);

    // Sanidade do sweep: o caminho soberano (a porta de serviço, que compõe o
    // adapter) precisa ter sido encontrado pelo glob.
    expect(comSoberano.length).toBeGreaterThanOrEqual(1);

    const dualRead = comSoberano.filter((caminho) =>
      importa("cicloAvaliacaoStorage", MODULOS[caminho])
    );
    expect(dualRead).toEqual([]);
  });

  it("o adapter legado permanece explicitamente classificado como LEGACY", () => {
    const conteudo = fonte(LEGADO);

    expect(conteudo).toContain("LEGACY");
    expect(conteudo).toContain("não é fallback");
    // O legado cumpre a MESMA porta (marca da transitoriedade): sem abstração paralela.
    expect(importa("CycleRepository", conteudo)).toBe(true);
  });
});
