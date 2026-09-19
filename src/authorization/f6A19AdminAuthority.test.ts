import { describe, expect, it } from "vitest";

const MIGRATIONS = import.meta.glob("../../supabase/migrations/*.sql", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

function migration(nome: string): string {
  const chave = Object.keys(MIGRATIONS).find((item) => item.endsWith(nome));
  if (!chave) throw new Error(`migration ausente: ${nome}`);
  return MIGRATIONS[chave]!;
}

describe("F6-306 — autoridade administrativa não deriva de evaluator", () => {
  it("restringe usuario_eh_administrador nominalmente à role admin", () => {
    const sql = migration("20260945000000_f6_306_admin_role_discriminator.sql");
    expect(sql).toContain("r.name = 'admin'");
    expect(sql).toContain("r.is_system = true");
    expect(sql).not.toContain("r.is_system = true and r.status = 'active'\n     where");
  });

  it("mantém evaluator fora do bundle admin e fixa evaluator em evaluation.read", () => {
    const sql = migration("20260944000000_f6_306_role_evaluator.sql");
    expect(sql).toContain("name, status, is_system, organization_id");
    expect(sql).toContain("'evaluator', 'active', true, null");
    expect(sql).toContain("c.code = 'evaluation.read'");
    expect(sql).toContain("r.name='admin' and c.code like 'evaluation.%'");
    expect(sql).toContain("scope_type, status, created_by");
    expect(sql).toContain("'ASSIGNED', 'active'");
  });

  it("audita os dois consumidores administrativos sem reabrir bypass", () => {
    const sql = migration("20260945000000_f6_306_admin_role_discriminator.sql");
    const evaluator = migration("20260944000000_f6_306_role_evaluator.sql");
    expect(evaluator.match(/usuario_eh_administrador\(/g)).toHaveLength(2);
    expect(sql).toContain("roles de dominio, inclusive evaluator");
  });
});
