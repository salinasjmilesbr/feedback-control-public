import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const migration = readFileSync(
  new URL("../../supabase/migrations/20261016000000_f6_provisionamento_gestores.sql", import.meta.url),
  "utf8"
);

describe("F6 provisionamento funcional — guardas server-side", () => {
  it("rejeita perfil alvo inativo e roles administrativas", () => {
    expect(migration).toContain("v_target_profile_status <> 'active'");
    expect(migration).toContain("c.code in ('access_role.manage', 'membership.manage')");
  });

  it("mantém DENY para role inativa e cross-tenant", () => {
    expect(migration).toContain("v_role_status <> 'active'");
    expect(migration).toContain("v_role_org is not null and v_role_org <> v_org");
  });
});
