import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  resolve(process.cwd(), "supabase/migrations/20261013000000_f6_issue366_contrato_temporal.sql"),
  "utf8",
);

describe("Issue #373 — upgrade incremental da #366", () => {
  it("não depende de igualdade textual de formatação para normalização ou lock", () => {
    expect(migration).toContain("regexp_count(v_source, v_norm_pattern");
    expect(migration).toContain("regexp_replace(v_source, v_norm_pattern");
    expect(migration).toContain("regexp_count(v_source, v_lock_pattern");
    expect(migration).toContain("regexp_replace(v_source, v_lock_pattern");
    expect(migration).not.toContain("replace(v_source,\n      '  if p_vigencia is null then");
  });

  it("mantém falha fechada e a prova da ordem temporal da #366", () => {
    expect(migration).toContain("raise exception 'F6_366: marcador de normalizacao ausente ou ambiguo em %'");
    expect(migration).toContain("raise exception 'F6_366: marcador de lock ausente ou ambiguo em %'");
    expect(migration).toContain("raise exception 'F6_366: ordem lock -> guarda -> DML invalida em %'");
    expect(migration).toContain("v_lock_pos < v_guard_pos and v_guard_pos < v_dml_pos");
  });
});
