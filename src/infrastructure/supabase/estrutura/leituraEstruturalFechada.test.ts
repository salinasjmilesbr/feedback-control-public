/// <reference types="node" />
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * #327/P3 — PROVA 7: o cliente NAO referencia mais as 10 tabelas estruturais
 * para leitura.
 *
 * Depois do P2B o cliente le SOMENTE as tres views aprovadas
 * (`estrutura_administrativa`, `estrutura_pessoal`, `estrutura_autorizacao`), e
 * o P3 revogou `SELECT`/policies das tabelas que `lerEstrutura` lia diretamente
 * (mais `collaborator_status_periods`, fechada por consequencia mecanica). Esta
 * guarda estatica falha se qualquer modulo de producao sob `src/` voltar a
 * apontar `.from()` para uma dessas tabelas — o caminho antigo nao pode
 * reaparecer por descuido.
 *
 * Leitura por `node:fs` (nao `?raw`): o alvo e o codigo REAL do repositorio, e o
 * mesmo padrao de `src/styles/tokensFoundation.test.ts`. As Edge Functions
 * (`supabase/functions`, server-side, `service_role`) ficam fora do escopo: elas
 * continuam lendo as tabelas legitimamente.
 */

const DIR_SRC = join(process.cwd(), "src");

/** Tabelas cuja leitura direta foi FECHADA pelo #327/P3. */
const TABELAS_FECHADAS = [
  "collaborators",
  "job_roles",
  "seniority_levels",
  "organizational_units",
  "organizational_unit_parent_periods",
  "organizational_positions",
  "position_reporting_lines",
  "occupations",
  "collegiate_configurations",
  "collegiate_configuration_members",
  "collaborator_status_periods",
] as const;

const VIEWS_APROVADAS = [
  "estrutura_administrativa",
  "estrutura_pessoal",
  "estrutura_autorizacao",
] as const;

function fontesDeProducao(): ReadonlyArray<readonly [string, string]> {
  return readdirSync(DIR_SRC, { recursive: true, encoding: "utf8" })
    .map((nome) => nome.replace(/\\/g, "/"))
    .filter((nome) => /\.tsx?$/.test(nome) && !/\.test\.tsx?$/.test(nome))
    .sort()
    .map((nome) => [nome, readFileSync(join(DIR_SRC, nome), "utf8")] as const);
}

/** `.from("x")` / `.from('x')` — a unica forma de leitura PostgREST do cliente. */
function leDe(fonte: string, tabela: string): boolean {
  return new RegExp(`\\.from\\(\\s*["']${tabela}["']`).test(fonte);
}

function fonte(relativo: string): string {
  return readFileSync(join(DIR_SRC, relativo), "utf8");
}

describe("#327/P3 — leitura estrutural antiga fechada no cliente", () => {
  it("nenhum modulo de producao le as 11 tabelas fechadas", () => {
    const fontes = fontesDeProducao();
    // Anti-vacuidade: a varredura precisa ver o codigo real do src/.
    expect(fontes.length).toBeGreaterThan(50);

    const infratores: string[] = [];
    for (const [nome, conteudo] of fontes) {
      for (const tabela of TABELAS_FECHADAS) {
        if (leDe(conteudo, tabela)) infratores.push(`${nome} → .from("${tabela}")`);
      }
    }
    expect(infratores).toEqual([]);
  });

  it("o repositorio de leitura estrutural le SOMENTE as views aprovadas", () => {
    const conteudo = fonte(
      "infrastructure/supabase/estrutura/repositorioEstruturaSoberana.ts"
    );

    // Prova positiva (nao-vacua): a leitura existe e e por view.
    expect(conteudo).toContain('.from(escopo === "pessoal" ? "estrutura_pessoal" : "estrutura_administrativa")');
    expect(conteudo).toContain(".maybeSingle()");
    for (const tabela of TABELAS_FECHADAS) {
      expect(leDe(conteudo, tabela), tabela).toBe(false);
    }
  });

  it("a projecao de menu le a view de autorizacao (e nenhuma tabela)", () => {
    const conteudo = fonte("services/autorizacaoEstruturalSoberana.ts");

    expect(conteudo).toContain('.from("estrutura_autorizacao")');
    for (const tabela of TABELAS_FECHADAS) {
      expect(leDe(conteudo, tabela), tabela).toBe(false);
    }
  });

  it("as views aprovadas sao exatamente as tres usadas em .from()", () => {
    const conteudo = [
      fonte("infrastructure/supabase/estrutura/repositorioEstruturaSoberana.ts"),
      fonte("services/autorizacaoEstruturalSoberana.ts"),
    ].join("\n");

    for (const view of VIEWS_APROVADAS) {
      expect(conteudo, view).toContain(view);
    }
  });
});
