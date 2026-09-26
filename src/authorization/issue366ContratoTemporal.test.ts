import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  resolve(process.cwd(), "supabase/migrations/20260914020000_f5_08_lock_key_alignment.sql"),
  "utf8",
);

describe("Issue #366 — contrato temporal estrutural", () => {
  it("normaliza a entrada timestamptz para o início do dia civil UTC nos quatro RPCs", () => {
    expect(migration.match(/p_vigencia := date_trunc\('day', p_vigencia at time zone 'UTC'\) at time zone 'UTC';/g)).toHaveLength(4);
  });

  it("guarda a segunda transição distinta por relação e data antes do DML", () => {
    expect(migration.match(/segunda transicao de ocupacao na mesma relacao e data civil/g)).toHaveLength(2);
    expect(migration.match(/segunda transicao de reporting line na mesma relacao e data civil/g)).toHaveLength(2);
    expect(migration).toContain("e.effective_date = p_vigencia");
  });

  it("preserva os contratos temporais e a serialização existentes", () => {
    expect(migration).toContain("p_vigencia timestamptz");
    expect(migration).toContain("pg_advisory_xact_lock(hashtext('position_reporting_lines:' || p_organization_id::text))");
    expect(migration).toContain("return v_evento.result_entity_id;");
    expect(migration).toContain("return;");
  });
});
