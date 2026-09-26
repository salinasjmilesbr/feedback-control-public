import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  resolve(process.cwd(), "supabase/migrations/20261014000000_f6_issue365_historico_reporting.sql"),
  "utf8",
);

describe("Issue #365 — histórico de reporting", () => {
  it("reutiliza a RPC soberana e projeta os dois eventos de reporting", () => {
    expect(migration).toContain("create or replace function public.colaborador_historico_listar");
    expect(migration).toContain("REPORTING_LINE_INICIADA");
    expect(migration).toContain("REPORTING_LINE_ENCERRADA");
    expect(migration).toContain("e.collaborator_id is null");
  });

  it("resolve ocupante gestor pela vigência UTC do evento e preserva UUIDs", () => {
    expect(migration).toContain("o.valid_from <= e.effective_date");
    expect(migration).toContain("o.valid_to is null or o.valid_to > e.effective_date");
    expect(migration).toContain("manager_position_id");
    expect(migration).toContain("historical_manager_occupants");
    expect(migration).toContain("order by o.valid_from desc, o.id");
  });

  it("mantém tenant, autorização e ausência de prova sem inferência", () => {
    expect(migration).toContain("colaborador_ator_valido");
    expect(migration).toContain("e.organization_id = p_organization_id");
    expect(migration).toContain("o.organization_id = p_organization_id");
    expect(migration).toContain("coalesce(jsonb_agg");
  });
});
