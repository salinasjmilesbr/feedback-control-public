/**
 * Issue #427 — F6: cardinalidade soberana de ocupações.
 *
 * Contrato estático da migration aditiva (o SQL executável é provado nos
 * validadores de `supabase/validacao`, que exigem runtime descartável):
 *
 * 1. exclusão temporal por `collaborator_id` (meio-aberta `[)`) PRESERVANDO a
 *    exclusão existente por posição;
 * 2. guardas de cardinalidade explícita nos dois caminhos de escrita;
 * 3. resolvers estruturais fail-closed diante de origem ambígua (nunca união,
 *    nunca `LIMIT 1`);
 * 4. cardinalidade explícita nas materializações (colegiado e avaliação) e na
 *    admissão pós-ativação;
 * 5. nenhuma migration histórica editada e nenhuma regra de substituição
 *    temporária tocada.
 */

import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

const MIGRATION =
  "supabase/migrations/20261028000000_f6_issue427_cardinalidade_ocupacoes.sql";
const MIGRATION_HISTORICA =
  "supabase/migrations/20260907150000_occupations.sql";

describe("Issue #427 — cardinalidade soberana de ocupações (contrato da migration)", () => {
  const migration = readFileSync(MIGRATION, "utf8");

  it("adiciona exclusão temporal por collaborator_id em intervalos meio-abertos", () => {
    expect(migration).toContain("ex_occupations_collaborator_no_overlap");
    expect(migration).toContain("exclude using gist (");
    expect(migration).toContain("collaborator_id with =");
    expect(migration).toContain(
      "tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&"
    );
  });

  it("preserva a exclusão existente por posição e não altera migrations históricas", () => {
    expect(migration).not.toContain("drop constraint ex_occupations_position_no_overlap");
    expect(migration).not.toContain("drop table");
    // A migration histórica da F3-05 permanece intacta: ela ainda documenta a
    // regra antiga ("Sem exclusion por colaborador"), que esta Issue substitui
    // apenas por migration aditiva.
    const historica = readFileSync(MIGRATION_HISTORICA, "utf8");
    expect(historica).toContain("multiplas posicoes simultaneas sao validas");
    expect(historica).not.toContain("ex_occupations_collaborator_no_overlap");
  });

  it("preserva o contrato temporal da #366 nos dois caminhos de escrita", () => {
    expect(migration).toContain("p_vigencia := public.f6_vigencia_civil_utc(p_vigencia);");
    expect(migration).toContain("v_vigencia := public.f6_vigencia_civil_utc(p_vigencia);");
    expect(migration).toContain(
      "F5_07_CONFLICT: segunda transicao de ocupacao na mesma relacao e data civil"
    );
  });

  it("exige cardinalidade explícita em definir e trocar, sem fechamento em lote", () => {
    expect(migration).toContain("create or replace function public.estrutura_ocupacao_definir");
    expect(migration).toContain("create or replace function public.estrutura_ocupacao_trocar");
    expect(migration).toContain("cardinalidade de ocupacao ambigua");
    // definir: zero ou uma origem atravessando a data efetiva.
    expect(migration).toContain("if v_vigentes_qtd > 1 then");
    // trocar: exatamente uma origem e correspondência com a posição atual.
    expect(migration).toContain("if v_vigentes_qtd = 0 then");
    expect(migration).toContain(
      "ocupacao vigente nao corresponde a posicao atual informada"
    );
    // recusa de sobreposição futura nos dois caminhos.
    expect(migration).toContain("se sobreporia a nova ocupacao");
  });

  it("expõe primitivas server-side de cardinalidade fail-closed", () => {
    expect(migration).toContain(
      "create or replace function public.colaborador_ocupacoes_cardinalidade"
    );
    expect(migration).toContain("create or replace function public.colaborador_posicao_soberana");
    expect(migration).toContain("from public, anon, authenticated");
    expect(migration).toContain("to service_role");
  });

  it("torna os resolvers estruturais fail-closed diante de origem ambígua", () => {
    for (const assinatura of [
      "public.organizacao_resolver_gestor_direto",
      "public.organizacao_resolver_subordinados_diretos",
      "public.organizacao_resolver_descendentes",
      "public.organizacao_resolver_cadeia",
      "public.organizacao_resolver_escopo_posicoes",
      "public.organizacao_resolver_avaliador_avaliado",
    ]) {
      expect(migration).toContain(`create or replace function ${assinatura}`);
    }
    // A origem ambígua deixa de produzir união: nenhuma linha é devolvida.
    expect(migration).toContain("cross join cardinalidade c");
    expect(migration).toContain("where c.qtd <= 1");
    expect(migration).not.toContain("order by o.valid_from desc, o.created_at desc");
  });

  it("comprova cardinalidade nas materializações e na admissão pós-ativação", () => {
    expect(migration).toContain(
      "create or replace function public.materializar_colegiado_ciclo"
    );
    expect(migration).toContain(
      "create or replace function public.evaluation_snapshot_participantes"
    );
    expect(migration).toContain(
      "create or replace function public.ciclo_admissao_pos_ativacao_elegivel"
    );
    expect(migration).toContain(
      "colaborador_ocupacoes_cardinalidade(x.cid, p_reference_date) > 1"
    );
    expect(migration).toContain("v_ocup_qtd > 1");
    expect(migration).toContain("ESTRUTURA_AMBIGUA");
    // 0 preserva a semântica existente de ausência de ocupação.
    expect(migration).toContain("ESTRUTURA_IRRESOLVEL");
  });

  it("não toca substituições temporárias (fora da constraint)", () => {
    expect(migration).not.toContain("alter table public.temporary_responsibilities");
    expect(migration).not.toContain("create table public.temporary_responsibilities");
  });

  it("não introduz SECURITY DEFINER novo", () => {
    expect(migration).not.toContain("security definer");
  });
});
