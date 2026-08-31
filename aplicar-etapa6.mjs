import fs from "node:fs";
import path from "node:path";

const cwd = process.cwd();
const indexFile = path.join(cwd, "src/index.css");
const foundationFile = path.join(cwd, "src/styles/virtus-foundation.css");

for (const f of [indexFile, foundationFile]) {
  if (!fs.existsSync(f)) throw new Error(`Arquivo não encontrado: ${f}`);
}

let index = fs.readFileSync(indexFile, "utf8");
let foundation = fs.readFileSync(foundationFile, "utf8");

if (foundation.includes("VIRTUS SHELL AUDIT — etapa 6")) {
  console.log("Etapa 6 já aplicada.");
  process.exit(0);
}

/* ---------------------------------------------------------
   1. Remove o starter CSS do Vite que ainda existia antes da
      fundação white-label. Preservamos somente as fontes-base.
   --------------------------------------------------------- */
const whiteLabelMarker = "/* White-label branding foundation */";
const markerPos = index.indexOf(whiteLabelMarker);
if (markerPos === -1) {
  throw new Error("Marcador White-label branding foundation não encontrado.");
}

const legacyPrefix = index.slice(0, markerPos);

if (!legacyPrefix.includes("color-scheme: light dark")) {
  throw new Error("Starter CSS esperado não encontrado no início de index.css.");
}
if (!legacyPrefix.includes("#root")) {
  throw new Error("Regra legacy de #root não encontrada.");
}
if (!legacyPrefix.includes("h1 {")) {
  throw new Error("Regra legacy de h1 não encontrada.");
}

const cleanPrefix = `:root {
  --sans: system-ui, 'Segoe UI', Roboto, sans-serif;
  --heading: system-ui, 'Segoe UI', Roboto, sans-serif;
  --mono: ui-monospace, Consolas, monospace;

  color-scheme: light;
  font-family: var(--sans);
  font-synthesis: none;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

html,
body,
#root {
  width: 100%;
  min-height: 100%;
}

html {
  background: var(--brand-bg, #f6f7fb);
}

body {
  min-width: 320px;
  margin: 0;
}

#root {
  margin: 0;
  border: 0;
  text-align: left;
}

p {
  margin: 0;
}

code,
.counter {
  font-family: var(--mono);
}

`;

index = cleanPrefix + index.slice(markerPos);

/* ---------------------------------------------------------
   2. Torna o shell explícito no design system.
   A largura já era padronizada; faltava registrar o layout
   interno do header e as garantias do eixo.
   --------------------------------------------------------- */

const insertAfter = `.app-header__inner {
  min-height: 82px;
  padding-left: 0 !important;
  padding-right: 0 !important;
}
`;

if (!foundation.includes(insertAfter)) {
  throw new Error("Bloco .app-header__inner esperado não encontrado em virtus-foundation.css.");
}

const shellRules = `${insertAfter}
.app-header__inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
}

.app-header__brand,
.app-header__user {
  min-width: 0;
}

.app-header__user {
  justify-content: flex-end;
}

`;

foundation = foundation.replace(insertAfter, shellRules);

/* Reforça a política light para impedir que controles nativos
   mudem de aparência conforme preferência do sistema operacional. */
foundation = foundation.replace(
  `body {
  color: var(--brand-text);
}
`,
  `body {
  color: var(--brand-text);
  background: var(--brand-bg);
}
`
);

foundation += `
/* =========================================================
   VIRTUS SHELL AUDIT — etapa 6
   Shell global consolidado após auditoria visual.
   ========================================================= */

@media (max-width: 820px) {
  .app-header__inner {
    align-items: flex-start;
    flex-direction: column;
    gap: 12px;
    padding-top: 12px !important;
    padding-bottom: 12px !important;
  }

  .app-header__user {
    width: 100%;
    justify-content: flex-start;
    flex-wrap: wrap;
  }
}
`;

fs.writeFileSync(indexFile, index, "utf8");
fs.writeFileSync(foundationFile, foundation, "utf8");

console.log("Etapa 6 aplicada com sucesso.");
console.log("- removido starter CSS legado do Vite");
console.log("- color-scheme fixado em light");
console.log("- shell/header interno explicitamente alinhado ao container global");
console.log("- comportamento mobile do header consolidado");
