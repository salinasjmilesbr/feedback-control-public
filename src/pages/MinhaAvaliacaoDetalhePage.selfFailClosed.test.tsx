/**
 * F5-11 P5.1 (Issue #252) — SELF/read SOBERANO das observações comunicadas.
 *
 * A visão do avaliado deixou de ser um vazio fail-closed da P5 e passou a ler as
 * observações COMUNICADAS pela PORTA soberana, no escopo `SELF` do contrato
 * fechado. Como a página não tem render testável sem dublês de metade da
 * aplicação, a prova abaixo é ESTÁTICA e incide sobre o CÓDIGO DE PRODUÇÃO real:
 *
 * 1. a leitura passa pela porta soberana com o escopo `SELF` do contrato;
 * 2. NENHUMA leitura local (`observacaoStorage`/`localStorage`/`sessionStorage`)
 *    e nenhum fallback/dual-read;
 * 3. NENHUMA autoridade no browser (`can`/`authorize`), nenhuma RPC direta e
 *    nenhuma credencial privilegiada;
 * 4. o cliente NÃO reimplementa o filtro do backend (`comunicado`/`excluida`) —
 *    quem filtra é a RPC soberana (comunicado-only, não excluída, tenant, vínculo);
 * 5. a lista entregue à tela e ao PDF é a MESMA lista SOBERANA, por parâmetro —
 *    a constante vazia da P5 não existe mais;
 * 6. os estados de carregando/erro são explícitos (fail-closed com erro público).
 */

import { describe, expect, it } from "vitest";
import MinhaAvaliacaoDetalheFonte from "./MinhaAvaliacaoDetalhePage.tsx?raw";
import { ESCOPOS_OBSERVACAO } from "../infrastructure/supabase/observacoes/contrato";

/** Código sem comentários: a documentação DESCREVE o que a página não faz. */
const FONTE = MinhaAvaliacaoDetalheFonte.replace(/\/\*[\s\S]*?\*\//g, "");

describe("F5-11 P5.1 — SELF/read soberano das observações comunicadas", () => {
  it("o fonte é varrido como string (prova não-vacuamente verde)", () => {
    expect(MinhaAvaliacaoDetalheFonte).toBeTypeOf("string");
    expect(MinhaAvaliacaoDetalheFonte).toContain("MinhaAvaliacaoDetalhePage");
    expect(FONTE.length).toBeGreaterThan(1000);
  });

  it("lê as comunicadas pela PORTA soberana, no escopo SELF do contrato fechado", () => {
    // O escopo é o do contrato (allowlist fechada) — não um literal inventado.
    expect(ESCOPOS_OBSERVACAO).toContain("SELF");
    expect(FONTE).toContain("obterRepositorioObservacoesSoberanas");
    expect(FONTE).toMatch(/listarObservacoesPorEscopo\s*\(/);
    expect(FONTE).toContain('"SELF"');
  });

  it("fail-closed explícito: sem caminho soberano ou com erro do backend nada é exibido", () => {
    expect(FONTE).toMatch(/if\s*\(!repositorio\)/);
    expect(FONTE).toMatch(/if\s*\(!resultado\.ok\)/);
    expect(FONTE).toContain(
      "As observações comunicadas não estão disponíveis pelo caminho soberano neste ambiente."
    );
    expect(FONTE).toContain("Não foi possível carregar as observações comunicadas.");
    // Estados explícitos de carregando/erro (mesmo padrão já usado na página).
    expect(FONTE).toContain("Carregando observações comunicadas…");
    expect(FONTE).toContain("Observações comunicadas indisponíveis.");
  });

  it("não lê observação no acervo local nem no armazenamento do navegador", () => {
    for (const proibido of [
      "observacaoStorage",
      "getObservacoesComunicadasByCiclo",
      "getObservacoesComunicadasByColaborador",
      "localStorage",
      "sessionStorage",
    ]) {
      expect(FONTE, proibido).not.toContain(proibido);
    }
  });

  it("não reimplementa autorização no browser nem fala RPC/credencial", () => {
    expect(FONTE).not.toMatch(/\bauthorize\s*\(/);
    expect(FONTE).not.toMatch(/\bcan\s*\(/);
    expect(FONTE).not.toMatch(/\.rpc\s*\(/);
    expect(FONTE).not.toMatch(/SERVICE_ROLE_KEY|service_role/);
    expect(FONTE).not.toMatch(/createClient\s*\(/);
  });

  it("NÃO refiltra comunicado/excluída no cliente (o filtro é do backend)", () => {
    // Reimplementar o filtro da RPC seria uma segunda verdade de autorização.
    expect(FONTE).not.toMatch(/\.filter\([^)]*comunicado/);
    expect(FONTE).not.toMatch(/\.filter\([^)]*excluida/);
    expect(FONTE).not.toMatch(/comunicado\s*===\s*true/);
  });

  it("entrega a MESMA lista soberana à tela e ao PDF (a constante vazia da P5 morreu)", () => {
    expect(FONTE).not.toContain(
      "const observacoesComunicadas: readonly ObservacaoSoberana[] = [];"
    );
    expect(FONTE).toContain(
      "const observacoesComunicadas = resultadoDasObservacoes.observacoes;"
    );
    expect(FONTE).toMatch(
      /exportarAvaliacaoPdf\(\s*ator,\s*avaliacao,\s*metasDoCiclo,\s*observacoesComunicadas\s*\)/
    );
  });

  it("a seção da tela continua condicionada à lista NÃO vazia (nada inventado)", () => {
    expect(FONTE).toContain("{observacoesComunicadas.length > 0 && (");
  });
});
