/**
 * F5-11 P5 (Issue #250) — SELF **fail-closed e sem autoridade local**.
 *
 * A página de detalhe da própria avaliação (`MinhaAvaliacaoDetalhePage`) deixou
 * de arrastar observações do acervo do navegador. Não há teste de render para
 * esta página (a criação de um não estava no escopo do lote); a prova abaixo é
 * ESTÁTICA e incide sobre o código de produção:
 *
 * 1. nenhuma leitura local de observação (`observacaoStorage` /
 *    `getObservacoesComunicadasByCiclo` / armazenamento do navegador);
 * 2. nenhuma autoridade local criada no browser (sem `authorize`/`can`);
 * 3. a lista entregue à tela e ao PDF é VAZIA e EXPLÍCITA;
 * 4. o PDF recebe a lista soberana por PARÂMETRO (nunca lê acervo);
 * 5. a leitura SELF soberana fica declarada como dependente da concessão mínima
 *    de `observation.read` ao avaliado, decidida para a fase P5.1.
 */

import { describe, expect, it } from "vitest";
import MinhaAvaliacaoDetalheFonte from "./MinhaAvaliacaoDetalhePage.tsx?raw";

describe("F5-11 P5 — SELF fail-closed sem autoridade local", () => {
  it("o fonte é varrido como string (prova não-vacuamente verde)", () => {
    expect(MinhaAvaliacaoDetalheFonte).toBeTypeOf("string");
    expect(MinhaAvaliacaoDetalheFonte).toContain("MinhaAvaliacaoDetalhePage");
  });

  it("não lê observação no acervo local nem no armazenamento do navegador", () => {
    for (const proibido of [
      "observacaoStorage",
      "getObservacoesComunicadasByCiclo",
      "getObservacoesComunicadasByColaborador",
      "localStorage",
      "sessionStorage",
    ]) {
      expect(MinhaAvaliacaoDetalheFonte, proibido).not.toContain(proibido);
    }
  });

  it("não reimplementa autorização no browser", () => {
    expect(MinhaAvaliacaoDetalheFonte).not.toMatch(/\bauthorize\s*\(/);
    expect(MinhaAvaliacaoDetalheFonte).not.toMatch(/\bcan\s*\(/);
    // Nenhuma credencial privilegiada e nenhuma RPC direta do cliente.
    expect(MinhaAvaliacaoDetalheFonte).not.toMatch(/\.rpc\s*\(/);
    expect(MinhaAvaliacaoDetalheFonte).not.toMatch(/SERVICE_ROLE_KEY|service_role/);
  });

  it("entrega lista VAZIA e explícita (fail-closed, sem dado presumido)", () => {
    expect(MinhaAvaliacaoDetalheFonte).toContain(
      "const observacoesComunicadas: readonly ObservacaoSoberana[] = [];"
    );
  });

  it("o PDF recebe a lista soberana por parâmetro", () => {
    expect(MinhaAvaliacaoDetalheFonte).toContain("exportarAvaliacaoPdf(");
    expect(MinhaAvaliacaoDetalheFonte).toMatch(
      /exportarAvaliacaoPdf\(\s*ator,\s*avaliacao,\s*metasDoCiclo,\s*observacoesComunicadas\s*\)/
    );
  });

  it("declara a dependência da concessão mínima de leitura SELF para P5.1", () => {
    expect(MinhaAvaliacaoDetalheFonte).toContain("P5.1");
    expect(MinhaAvaliacaoDetalheFonte).toContain("observation.read");
  });
});
