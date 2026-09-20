import { describe, expect, it } from "vitest";
import { callbackAuthType, isInviteCallback } from "./callbackAuth";

describe("callback Auth", () => {
  it("reconhece convite no fragmento do Supabase", () => {
    const url = "https://virtus.example/redefinir-senha#access_token=token&type=invite";
    expect(callbackAuthType(url)).toBe("invite");
    expect(isInviteCallback(url)).toBe(true);
  });

  it("não confunde recuperação ou URL comum com convite", () => {
    expect(isInviteCallback("https://virtus.example/redefinir-senha#type=recovery")).toBe(false);
    expect(callbackAuthType("https://virtus.example/login")).toBeNull();
  });

  it("não aceita URL malformada", () => {
    expect(callbackAuthType("not-a-url")).toBeNull();
  });
});
