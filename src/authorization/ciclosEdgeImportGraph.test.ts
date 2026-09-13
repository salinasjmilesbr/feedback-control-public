import { describe, expect, it } from "vitest";

/**
 * F5-09 P7 (Issue #202) — GATE FOCADO do IMPORT GRAPH das Edge Functions.
 *
 * Motivo (BLOCKER da auditoria do PR #203): `npm run build`/`tsc` NÃO incluem a
 * Edge Function no programa compilado (nada em `src/` importa
 * `supabase/functions/ciclos/index.ts`), então um import relativo apontando para
 * arquivo INEXISTENTE — ou com casing/nome divergente do arquivo real — passava
 * por `build`/`lint`/`tsc` e só quebrava no bundle/deploy Deno da Supabase.
 *
 * Este gate percorre o grafo REAL de imports RELATIVOS de cada Edge, resolvendo
 * cada specifier contra o conjunto de arquivos do repositório (com o casing
 * REAL, vindo do `import.meta.glob`) e FALHA se algum não corresponder. Roda no
 * `npm test`, sem Docker/Deno/CLI e sem APIs do Node (o tsconfig do app não
 * inclui tipos de Node).
 *
 * Validação complementar (bundle REAL do runtime Supabase/Deno, manual):
 *   npx --yes supabase@2.116.0 functions serve ciclos --no-verify-jwt
 * — o CLI valida a árvore INTEIRA de functions; por isso ele só chega em
 * `ciclos` quando o import pré-existente de `avaliacoes` (abaixo) está sadio.
 *
 * Exceção CONHECIDA (defeito PRÉ-EXISTENTE, fora do escopo da P7): a Edge
 * `avaliacoes` (F5-06, commit f540f0f) importa `catalogoCapacidades.ts`, que não
 * existe — o arquivo real é `catalogoCapabilities.ts`. A exceção é declarada e
 * AUTO-VERIFICADA: se o defeito for corrigido, este teste FALHA pedindo a
 * remoção da exceção (ela não pode virar permissão permanente).
 */

/**
 * As chaves do `import.meta.glob` são relativas a ESTE arquivo — por isso cada
 * chave é ancorada no diretório do gate antes de normalizar (uma chave
 * `./x.ts` vira `src/authorization/x.ts`; `../../supabase/...` vira
 * `supabase/...`). A premissa é auto-verificada no teste de sanity abaixo.
 */
const DIRETORIO_DO_GATE = "src/authorization";

const ARQUIVOS: Readonly<Record<string, string>> = import.meta.glob(
  ["../../src/**/*.{ts,tsx}", "../../supabase/**/*.ts"],
  { query: "?raw", import: "default", eager: true }
) as Readonly<Record<string, string>>;

/** Remove `./` e `../`, deixando o caminho relativo ao repositório. */
function normalizar(caminho: string): string {
  const pilha: string[] = [];
  for (const parte of caminho.split("/")) {
    if (parte === "" || parte === ".") continue;
    if (parte === "..") {
      pilha.pop();
      continue;
    }
    pilha.push(parte);
  }
  return pilha.join("/");
}

/** Caminho relativo ao repositório → conteúdo do arquivo REAL. */
const POR_CAMINHO = new Map<string, string>();
for (const [chave, conteudo] of Object.entries(ARQUIVOS)) {
  POR_CAMINHO.set(normalizar(`${DIRETORIO_DO_GATE}/${chave}`), conteudo);
}

interface Resolucao {
  readonly caminho: string | null;
  /** Arquivo existente que difere apenas por CASING (diagnóstico do erro). */
  readonly sugestaoCasing: string | null;
}

function resolver(relativo: string): Resolucao {
  const alvo = normalizar(relativo);
  for (const candidato of [alvo, `${alvo}.ts`, `${alvo}.tsx`, `${alvo}/index.ts`]) {
    if (POR_CAMINHO.has(candidato)) return { caminho: candidato, sugestaoCasing: null };
  }
  const alvoMinusculo = alvo.toLowerCase();
  const sugestao =
    [...POR_CAMINHO.keys()].find((chave) => chave.toLowerCase() === alvoMinusculo) ?? null;
  return { caminho: null, sugestaoCasing: sugestao };
}

function specifiersDe(codigo: string): readonly string[] {
  const encontrados: string[] = [];
  for (const padrao of [/from\s+"([^"]+)"/g, /import\(\s*"([^"]+)"/g]) {
    let correspondencia: RegExpExecArray | null;
    while ((correspondencia = padrao.exec(codigo)) !== null) {
      encontrados.push(correspondencia[1]!);
    }
  }
  return encontrados;
}

interface Grafo {
  readonly visitados: ReadonlySet<string>;
  readonly quebrados: readonly string[];
  readonly diagnostico: readonly string[];
  readonly externos: ReadonlySet<string>;
}

function percorrerGrafo(entry: string): Grafo {
  const fila = [entry];
  const visitados = new Set<string>();
  const quebrados: string[] = [];
  const diagnostico: string[] = [];
  const externos = new Set<string>();

  while (fila.length > 0) {
    const arquivo = fila.shift()!;
    if (visitados.has(arquivo)) continue;
    visitados.add(arquivo);

    const conteudo = POR_CAMINHO.get(arquivo);
    if (conteudo === undefined) {
      quebrados.push(`arquivo do grafo ausente: ${arquivo}`);
      continue;
    }

    for (const specifier of specifiersDe(conteudo)) {
      if (!specifier.startsWith(".")) {
        externos.add(specifier.split("?")[0]!);
        continue;
      }
      const base = arquivo.slice(0, arquivo.lastIndexOf("/"));
      const { caminho, sugestaoCasing } = resolver(`${base}/${specifier}`);

      if (caminho === null) {
        quebrados.push(`import quebrado: "${specifier}" em ${arquivo}`);
        if (sugestaoCasing) {
          diagnostico.push(
            `${arquivo}: "${specifier}" tem CASING divergente — o arquivo real é ${sugestaoCasing}`
          );
        }
        continue;
      }
      fila.push(caminho);
    }
  }

  return { visitados, quebrados, diagnostico, externos };
}

/** Entries reais das Edge Functions do projeto. */
const ENTRIES = [...POR_CAMINHO.keys()]
  .filter((caminho) => /^supabase\/functions\/[^/]+\/index\.ts$/.test(caminho))
  .sort();

const ENTRY_CICLOS = "supabase/functions/ciclos/index.ts";

/**
 * Defeitos PRÉ-EXISTENTES tolerados (nenhum deles na Edge `ciclos`). Se o import
 * passar a resolver, o teste falha pedindo a remoção da exceção.
 */
const EXCECOES_CONHECIDAS: Readonly<Record<string, string>> = {
  "supabase/functions/avaliacoes/index.ts":
    'import quebrado: "../../../src/authorization/catalogoCapacidades.ts" em supabase/functions/avaliacoes/index.ts',
};

const grafoCiclos = percorrerGrafo(ENTRY_CICLOS);

describe("F5-09 P7 — import graph da Edge `ciclos` (Deno/Supabase)", () => {
  it("o índice do repositório e o entry da Edge existem (gate não é vazio)", () => {
    expect(POR_CAMINHO.size).toBeGreaterThan(150);
    expect(ENTRIES).toContain(ENTRY_CICLOS);
  });

  it("TODO import relativo do grafo de `ciclos` resolve para arquivo EXISTENTE", () => {
    expect({ quebrados: grafoCiclos.quebrados, diagnostico: grafoCiclos.diagnostico }).toEqual({
      quebrados: [],
      diagnostico: [],
    });
  });

  it("o grafo de `ciclos` alcança contrato, núcleo, autorização e domínio", () => {
    const caminhos = [...grafoCiclos.visitados];
    const termina = (sufixo: string) => caminhos.some((caminho) => caminho.endsWith(sufixo));

    expect(termina("/ciclos/index.ts")).toBe(true);
    expect(termina("/ciclos/core.ts")).toBe(true);
    expect(termina("/ciclos/contrato.ts")).toBe(true);
    expect(caminhos.some((c) => c.includes("infrastructure/supabase/ciclos/"))).toBe(true);
    expect(termina("/authorization/contextoAutorizacao.ts")).toBe(true);
    expect(termina("/authorization/resourceContextReal.ts")).toBe(true);
    // O catálogo canônico de capabilities é importado pela Edge — o caminho
    // precisa EXISTIR (foi exatamente o BLOCKER do PR #203).
    expect(caminhos.some((c) => /\/authorization\/catalogo[a-zA-Z]+\.ts$/.test(c))).toBe(true);
    expect(termina("/auth/tipos.ts")).toBe(true);
  });

  it("o grafo de `ciclos` é substantivo e só depende da URL externa esperada", () => {
    expect(grafoCiclos.visitados.size).toBeGreaterThanOrEqual(15);
    expect([...grafoCiclos.externos]).toContain("https://esm.sh/@supabase/supabase-js@2");
  });
});

describe("F5-09 P7 — import graph das DEMAIS Edge Functions (regressão)", () => {
  it("toda Edge tem grafo íntegro, exceto os defeitos PRÉ-EXISTENTES declarados", () => {
    const problemas: string[] = [];

    for (const entry of ENTRIES) {
      const grafo = entry === ENTRY_CICLOS ? grafoCiclos : percorrerGrafo(entry);
      const esperado = EXCECOES_CONHECIDAS[entry];
      for (const quebrado of grafo.quebrados) {
        if (quebrado === esperado) continue;
        problemas.push(`${entry}: ${quebrado}`);
      }
      for (const linha of grafo.diagnostico) problemas.push(`${entry}: ${linha}`);
    }

    expect(problemas).toEqual([]);
  });

  it("as exceções conhecidas continuam NECESSÁRIAS (remova-as quando corrigidas)", () => {
    for (const [entry, quebrado] of Object.entries(EXCECOES_CONHECIDAS)) {
      const grafo = entry === ENTRY_CICLOS ? grafoCiclos : percorrerGrafo(entry);
      if (!grafo.quebrados.includes(quebrado)) {
        throw new Error(
          `${entry}: o import antes quebrado agora RESOLVE — remova a exceção de EXCECOES_CONHECIDAS.`
        );
      }
    }
  });
});

describe("F5-09 P7 — sanity do índice do gate", () => {
  it("o índice cobre src/ e supabase/ com a âncora correta do diretório do gate", () => {
    const caminhos = [...POR_CAMINHO.keys()];
    // Auto-verificação da premissa: as chaves do glob são relativas a ESTE
    // diretório (o próprio arquivo do gate é excluído pelo `import.meta.glob`).
    expect(POR_CAMINHO.has("src/authorization/contextoAutorizacao.ts")).toBe(true);
    expect(POR_CAMINHO.has("supabase/functions/ciclos/index.ts")).toBe(true);
    expect(caminhos.some((c) => c.startsWith("src/authorization/"))).toBe(true);
    expect(caminhos.some((c) => c.startsWith("supabase/functions/"))).toBe(true);
    expect(caminhos.filter((c) => c.startsWith("supabase/functions/ciclos/")).length).toBe(3);
    // Diretório inexistente no repositório (o BLOCKER do PR #203).
    expect(caminhos.some((c) => c.includes("catalogoCapacidades"))).toBe(false);
  });
});
