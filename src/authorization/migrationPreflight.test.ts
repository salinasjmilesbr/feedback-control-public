import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { describe, expect, it } from "vitest";

const script = readFileSync(resolve(process.cwd(), "scripts/preflight-migrations.mjs"), "utf8");
const scriptPath = resolve(process.cwd(), "scripts/preflight-migrations.mjs");

function runWithFiles(files: Record<string, string>) {
  const directory = mkdtempSync(resolve(tmpdir(), "virtus-migration-preflight-"));
  try {
    for (const [name, content] of Object.entries(files)) {
      writeFileSync(resolve(directory, name), content, "utf8");
    }
    return spawnSync(process.execPath, [scriptPath], {
      env: { ...process.env, MIGRATIONS_DIR: directory },
      encoding: "utf8",
    });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

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

  it("retorna exit code diferente de zero para versão duplicada", () => {
    const result = runWithFiles({
      "20260101000000_one.sql": "select 1;",
      "20260101000000_two.sql": "select 1;",
    });
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("versao duplicada");
  });

  it("retorna exit code diferente de zero para nome inválido", () => {
    const result = runWithFiles({ "migration-invalida.sql": "select 1;" });
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain("nome fora do formato");
  });
});
