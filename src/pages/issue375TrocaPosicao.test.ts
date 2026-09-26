import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";

describe("Issue #375 — contrato de troca atômica", () => {
  it("expõe uma RPC única e uma única operação de idempotência", () => {
    const migration = readFileSync("supabase/migrations/20261015000000_f6_issue375_troca_posicao_atomica.sql", "utf8");
    expect(migration).toContain("create or replace function public.estrutura_ocupacao_trocar");
    expect(migration).toContain("update public.occupations");
    expect(migration).toContain("insert into public.occupations");
    expect(migration).toContain("raise exception 'F5_07_CONFLICT");
    expect(migration).toContain("pg_advisory_xact_lock");
    expect(migration).toContain("p_current_position_id");
    expect(migration).toContain("p_new_position_id");
  });
});
