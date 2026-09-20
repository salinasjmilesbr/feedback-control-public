import { describe, expect, it } from "vitest";
import { podeConvidarPorMembershipManage } from "./core";

describe("Issue #319 — gate soberano da fronteira de convite", () => {
  it("ALLOW com membership.manage efetiva", () => {
    expect(
      podeConvidarPorMembershipManage(
        [{ capability_code: "collaborator.manage" }, { capability_code: "membership.manage" }],
        null
      )
    ).toBe(true);
  });

  it("DENY sem membership.manage", () => {
    expect(
      podeConvidarPorMembershipManage([{ capability_code: "collaborator.manage" }], null)
    ).toBe(false);
  });

  it("DENY cross-tenant ou falha de resolução (fail-closed)", () => {
    expect(
      podeConvidarPorMembershipManage([{ capability_code: "membership.manage" }], {
        code: "PGRST116",
      })
    ).toBe(false);
    expect(podeConvidarPorMembershipManage([], null)).toBe(false);
    expect(podeConvidarPorMembershipManage({ capability_code: "membership.manage" }, null)).toBe(
      false
    );
  });
});
