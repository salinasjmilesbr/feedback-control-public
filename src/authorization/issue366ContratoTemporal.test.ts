import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  resolve(process.cwd(), "supabase/migrations/20261013000000_f6_issue366_contrato_temporal.sql"),
  "utf8",
);

describe("Issue #366 — contrato temporal estrutural", () => {
  it("normaliza a entrada timestamptz para o início do dia civil UTC nos quatro RPCs", () => {
    expect(migration).toContain("foreach v_name in array array['estrutura_ocupacao_definir', 'estrutura_ocupacao_encerrar',");
    expect(migration).toContain("'estrutura_reporting_definir', 'estrutura_reporting_encerrar']");
    expect(migration).toContain("create or replace function public.f6_vigencia_civil_utc");
    expect(migration).toContain("p_vigencia := public.f6_vigencia_civil_utc(p_vigencia);");
  });

  it("guarda a segunda transição distinta por relação e data antes do DML", () => {
    expect(migration.match(/segunda transicao de ocupacao na mesma relacao e data civil/g)).toHaveLength(2);
    expect(migration.match(/segunda transicao de reporting line na mesma relacao e data civil/g)).toHaveLength(1);
    expect(migration).toContain("e.effective_date = p_vigencia");
    expect(migration).toContain("e.organization_id = p_organization_id");
    expect(migration).toContain("e.collaborator_id = p_collaborator_id");
    expect(migration).toContain("e.position_id = p_position_id");
    expect(migration).toContain("join public.occupations o");
    expect(migration).toContain("o.organizational_position_id = e.position_id");
    expect(migration).not.toContain("v_guard := null");
    expect(migration).toContain("v_guard_pos < v_dml_pos");
  });

  it("preserva os contratos temporais e a serialização existentes", () => {
    expect(migration).toContain("pg_advisory_xact_lock(hashtext(''position_reporting_lines:'' ||");
    expect(migration.indexOf("v_source := replace(v_source,")).toBeLessThan(migration.indexOf("execute v_source;"));
    expect(migration).toContain("execute v_source;");
    expect(migration).toContain("marcador de normalizacao ausente ou ambiguo");
    expect(migration).toContain("marcador de lock ausente ou ambiguo");
    expect(migration).toContain("guarda temporal nao inserida exatamente uma vez");
    expect(migration).not.toContain("20260914020000_f5_08_lock_key_alignment.sql");
  });
});
