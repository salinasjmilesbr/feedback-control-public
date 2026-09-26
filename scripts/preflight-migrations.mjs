import { readdirSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(process.cwd(), "supabase", "migrations");
const files = readdirSync(root)
  .filter((name) => name.endsWith(".sql"))
  .sort((a, b) => a.localeCompare(b));
const versionPattern = /^(\d{14})_[a-z0-9][a-z0-9_-]*\.sql$/;
const seen = new Map();
const failures = [];

for (const name of files) {
  const match = name.match(versionPattern);
  if (!match) {
    failures.push(`${name}: nome fora do formato <YYYYMMDDHHMMSS>_<descricao>.sql`);
    continue;
  }
  const version = match[1];
  const prior = seen.get(version);
  if (prior) failures.push(`versao duplicada ${version}: ${prior} e ${name}`);
  seen.set(version, name);

  const path = resolve(root, name);
  if (!statSync(path).isFile() || readFileSync(path, "utf8").trim() === "") {
    failures.push(`${name}: migration vazia ou nao regular`);
  }
}

for (let index = 1; index < files.length; index += 1) {
  const previous = files[index - 1].match(versionPattern)?.[1];
  const current = files[index].match(versionPattern)?.[1];
  if (previous && current && current <= previous) {
    failures.push(`ordem de versao invalida: ${files[index - 1]} antes de ${files[index]}`);
  }
}

if (failures.length > 0) {
  console.error("Migration preflight FAILED");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log(`Migration preflight PASS: ${files.length} migrations, versoes unicas e ordenadas.`);
}
