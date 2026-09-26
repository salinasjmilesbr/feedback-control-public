import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  resolve(process.cwd(), "supabase/migrations/20260926000000_f6_issue366_contrato_temporal.sql"),
  "utf8",
);

describe("Issue #366 — contrato temporal estrutural", () => {
  it("normaliza a entrada timestamptz para o início do dia civil UTC nos quatro RPCs", () => {
    expect(migration).toContain("create or replace function public.f6_vigencia_civil_utc");
    expect(migration).toContain("p_vigencia := public.f6_vigencia_civil_utc(p_vigencia);");
  });

  it("guarda a segunda transição distinta por relação e data antes do DML", () => {
    expect(migration.match(/segunda transicao de ocupacao na mesma relacao e data civil/g)).toHaveLength(1);
    expect(migration.match(/segunda transicao de reporting line na mesma relacao e data civil/g)).toHaveLength(1);
    expect(migration).toContain("e.effective_date = p_vigencia");
  });

  it("preserva os contratos temporais e a serialização existentes", () => {
    expect(migration).toContain("pg_advisory_xact_lock(hashtext(''position_reporting_lines:'' ||");
    expect(migration.indexOf("v_source := replace(v_source,")).toBeLessThan(migration.indexOf("execute v_source;"));
    expect(migration).toContain("execute v_source;");
    expect(migration).not.toContain("20260914020000_f5_08_lock_key_alignment.sql");
  });
});
