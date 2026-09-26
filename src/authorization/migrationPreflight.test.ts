import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const script = readFileSync(resolve(process.cwd(), "scripts/preflight-migrations.mjs"), "utf8");

describe("migration preflight", () => {
  it("detecta duplicidade de versao e nomes fora do contrato", () => {
    expect(script).toContain("versao duplicada");
    expect(script).toContain("nome fora do formato");
  });

  it("falha para migration vazia e ordem temporal invalida", () => {
    expect(script).toContain("migration vazia ou nao regular");
    expect(script).toContain("ordem de versao invalida");
    expect(script).toContain("process.exitCode = 1");
  });
});
