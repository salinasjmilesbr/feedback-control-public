import { describe, expect, it } from "vitest";

import migration from "../../supabase/migrations/20261017000000_f6_issue379_gestao_equipe.sql?raw";

const CAPABILITIES = [
  "collaborator.read",
  "cycle.read",
  "evaluation.read",
  "goal.read",
  "goal.write",
  "observation.read",
  "observation.create",
  "observation.edit",
  "observation.delete",
  "report.read",
] as const;

describe("Issue #379 — bundle Gestão de equipe", () => {
  it("declara exatamente as capabilities funcionais do contrato", () => {
    const expectedBlock = migration.match(/v_expected text\[\] := array\[(.*?)\];/s)?.[1];
    expect(expectedBlock).toBeDefined();
    const actual = [...(expectedBlock ?? "").matchAll(/'([^']+)'/g)].map((match) => match[1]);
    expect(actual).toEqual([...CAPABILITIES]);
    expect(new Set(actual).size).toBe(CAPABILITIES.length);
  });

  it("mantém o bundle global, sem autoridade administrativa, e preserva o escopo soberano", () => {
    expect(migration).toContain("name = 'gestao_equipe'");
    expect(migration).toContain("is_system = true");
    expect(migration).toContain("organization_id is null");
    expect(migration).toContain("access_role_assignment_scopes");
    const forbidden = [
      "access_role.manage",
      "membership.manage",
      "cycle.manage",
      "org.structure.manage",
      "org.catalog.manage",
      "settings.manage",
    ];
    const guardBlock = migration.match(/if exists \(\s*select 1.*?c\.code in \((.*?)\)\s*\) then/s)?.[1];
    expect(guardBlock).toBeDefined();
    expect([...((guardBlock ?? "").matchAll(/'([^']+)'/g))].map((match) => match[1])).toEqual(forbidden);
  });
});
