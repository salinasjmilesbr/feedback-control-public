import { describe, expect, it } from "vitest";

/**
 * F5-11 P4 (Issue #248) — GATE FOCADO do IMPORT GRAPH da Edge `observacoes`.
 *
 * Mesmo motivo do gate da F5-10 (`metasEdgeImportGraph.test.ts`) e da F5-09
 * (`ciclosEdgeImportGraph.test.ts`): `npm run build`/`tsc` NÃO compilam a Edge
 * Function (nada em `src/` importa `supabase/functions/observacoes/index.ts`),
 * então um import relativo apontando para arquivo INEXISTENTE — ou com casing
 * divergente — passaria por `build`/`lint`/`tsc` e só quebraria no deploy Deno da
 * Supabase. Este gate resolve o grafo REAL contra os arquivos do repositório (via
 * `import.meta.glob`, sem APIs do Node, que o tsconfig do app não tipa).
 *
 * Prova também a fronteira de confiança do Bloco 1 (§6.7/D16 do desenho):
 * - as dependências soberanas vêm do `src/` (fonte ÚNICA do contrato);
 * - o núcleo testável não tem API de runtime nem a credencial privilegiada;
 * - `index.ts` é o ÚNICO arquivo do caminho que lê `SUPABASE_SERVICE_ROLE_KEY`;
 * - o caminho de cliente (contrato/adapter) NÃO importa nada da Edge, não fala
 *   com tabela soberana (`from("evaluation_observation…")`), não usa storage
 *   local e NUNCA chama RPC do banco (`.rpc(`) — a superfície do cliente é
 *   exclusivamente `functions.invoke("observacoes")`.
 */

const DIRETORIO_DO_GATE = "src/authorization";
const ENTRADA = "supabase/functions/observacoes/index.ts";
const ARQUIVOS_DA_EDGE = [
  "supabase/functions/observacoes/index.ts",
  "supabase/functions/observacoes/core.ts",
  "supabase/functions/observacoes/contrato.ts",
] as const;
const CAMINHO_CLIENTE = [
  "src/infrastructure/supabase/observacoes/contrato.ts",
  "src/infrastructure/supabase/observacoes/edgeObservacoes.ts",
] as const;

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

/** Specifier relativo resolvido a partir do diretório do arquivo. */
function resolver(caminho: string, specifier: string): string {
  const pilha = caminho.split("/").slice(0, -1);
  for (const parte of specifier.split("/")) {
    if (parte === "" || parte === ".") continue;
    if (parte === "..") pilha.pop();
    else pilha.push(parte);
  }
  return pilha.join("/");
}

const SUFIXOS = ["", ".ts", ".tsx", "/index.ts", "/index.tsx"];

/** Caminho REAL no repositório (casing exato) ou `null`. */
function caminhoReal(alvo: string): string | null {
  for (const sufixo of SUFIXOS) {
    const candidato = `${alvo}${sufixo}`;
    if (POR_CAMINHO.has(candidato)) return candidato;
  }
  return null;
}

/**
 * Código sem comentários (linha e bloco): os cabeçalhos CITAM, por texto, os
 * caminhos e as tabelas que o arquivo NÃO usa — as guardas negativas precisam
 * valer para o CÓDIGO, não para a documentação.
 */
function codigoSemComentarios(codigo: string): string {
  return codigo
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

const PADRAO_IMPORT = /(?:from|import)\s+"([^"]+)"/g;

function especificadores(codigo: string): readonly string[] {
  const encontrados: string[] = [];
  let achado: RegExpExecArray | null;
  while ((achado = PADRAO_IMPORT.exec(codigo)) !== null) encontrados.push(achado[1]!);
  return encontrados;
}

interface Grafo {
  readonly visitados: ReadonlySet<string>;
  readonly externos: ReadonlySet<string>;
  readonly quebrados: readonly string[];
}

function percorrerGrafo(entrada: string): Grafo {
  const visitados = new Set<string>();
  const externos = new Set<string>();
  const quebrados: string[] = [];
  const pendentes = [entrada];

  while (pendentes.length > 0) {
    const atual = pendentes.pop()!;
    if (visitados.has(atual)) continue;
    visitados.add(atual);
    const conteudo = POR_CAMINHO.get(atual);
    if (conteudo === undefined) {
      quebrados.push(`arquivo ausente: ${atual}`);
      continue;
    }
    for (const specifier of especificadores(conteudo)) {
      if (!specifier.startsWith(".")) {
        externos.add(specifier);
        continue;
      }
      const alvo = resolver(atual, specifier);
      const real = caminhoReal(alvo);
      if (real === null) quebrados.push(`${specifier} em ${atual}`);
      else pendentes.push(real);
    }
  }

  return { visitados, externos, quebrados };
}

const grafo = percorrerGrafo(ENTRADA);

/** Código do adapter de cliente (sem comentários) — base das guardas negativas. */
function codigoDoCliente(caminho: string): string {
  return codigoSemComentarios(POR_CAMINHO.get(caminho) as string);
}

describe("F5-11 P4 — import graph da Edge `observacoes`", () => {
  it("a premissa do gate é verdadeira (o repositório tem os arquivos esperados)", () => {
    for (const caminho of [...ARQUIVOS_DA_EDGE, ...CAMINHO_CLIENTE]) {
      expect(POR_CAMINHO.has(caminho), caminho).toBe(true);
    }
  });

  it("TODO import relativo da Edge resolve em arquivo REAL (casing exato)", () => {
    expect(grafo.quebrados).toEqual([]);
  });

  it("o grafo é substantivo, só depende da URL externa esperada e inclui a fonte única do contrato", () => {
    // index + core + contrato da Edge + contrato-fonte + contexto de autorização.
    expect(grafo.visitados.size).toBeGreaterThanOrEqual(4);
    expect([...grafo.externos]).toContain("https://esm.sh/@supabase/supabase-js@2");
    // Nenhum import RELATIVO escapa do grafo (todos foram resolvidos acima) e
    // nenhuma dependência externa aponta para dentro do repositório.
    for (const externo of grafo.externos) {
      expect(externo.startsWith("."), externo).toBe(false);
      expect(externo, externo).not.toContain("supabase/functions");
    }
    expect([...grafo.visitados]).toContain(
      "src/infrastructure/supabase/observacoes/contrato.ts"
    );
    expect([...grafo.visitados]).toContain("src/authorization/contextoAutorizacao.ts");
  });

  it("o núcleo testável não tem API de runtime nem a credencial privilegiada", () => {
    const core = POR_CAMINHO.get("supabase/functions/observacoes/core.ts") as string;
    for (const proibido of ["Deno.", "Deno.serve", "process.env", "createClient"]) {
      expect(core, proibido).not.toContain(proibido);
    }
    for (const credencial of ["service_role", "SERVICE_ROLE", "serviceRole"]) {
      expect(core, credencial).not.toContain(credencial);
    }
    // O núcleo também não decide por conta própria: nenhuma RPC e nenhuma
    // leitura direta de tabela moram nele (a decisão é do Policy Engine e a
    // execução, do wiring privilegiado).
    const codigoCore = codigoSemComentarios(core);
    expect(codigoCore).not.toMatch(/\.rpc\s*\(/);
    expect(codigoCore).not.toMatch(/\.from\s*\(/);
  });

  it("`index.ts` é o ÚNICO arquivo do caminho que lê a credencial privilegiada", () => {
    const comCredencial = [...ARQUIVOS_DA_EDGE, ...CAMINHO_CLIENTE].filter((caminho) =>
      (POR_CAMINHO.get(caminho) as string).includes("SUPABASE_SERVICE_ROLE_KEY")
    );
    expect(comCredencial).toEqual(["supabase/functions/observacoes/index.ts"]);
    // O wiring é o único lugar com API de runtime (a Edge roda em Deno).
    expect(POR_CAMINHO.get("supabase/functions/observacoes/index.ts") as string).toContain(
      "Deno.serve"
    );
  });

  it("a Edge reexporta o contrato-fonte (nenhuma cópia local da superfície)", () => {
    const contrato = POR_CAMINHO.get("supabase/functions/observacoes/contrato.ts") as string;
    expect(contrato).toContain(
      'export * from "../../../src/infrastructure/supabase/observacoes/contrato.ts";'
    );
    expect(contrato).not.toContain("DEFINICAO_POR_OPERACAO = {");
    expect(contrato).not.toContain("CHAVES_POR_OPERACAO = {");
    expect(contrato).not.toContain("RPC_POR_OPERACAO = {");
  });

  it("o caminho de CLIENTE não importa a Edge, não lê tabela soberana e não usa storage local", () => {
    for (const caminho of CAMINHO_CLIENTE) {
      const codigo = codigoDoCliente(caminho);
      for (const specifier of especificadores(codigo)) {
        expect(specifier, `${caminho}: ${specifier}`).not.toContain("supabase/functions");
      }
      for (const proibido of [
        'from("evaluation_observation',
        'from("evaluation_observations',
        "localStorage",
        "sessionStorage",
        'from("capabilities")',
      ]) {
        expect(codigo, `${caminho}: ${proibido}`).not.toContain(proibido);
      }
    }
  });

  it("o caminho de CLIENTE não chama RPC do banco (`.rpc(`) e não conhece a service role", () => {
    // P4 §6.7: o cliente fala EXCLUSIVAMENTE por `functions.invoke("observacoes")`.
    // Um `.rpc(` no caminho de cliente significaria PostgREST direto — exatamente
    // a superfície que a P2/P3 fecharam com `EXECUTE` só de `service_role`.
    for (const caminho of CAMINHO_CLIENTE) {
      const codigo = codigoDoCliente(caminho);
      expect(codigo, `${caminho}: .rpc(`).not.toMatch(/\.rpc\s*\(/);
      for (const proibido of ["service_role", "SERVICE_ROLE", "serviceRole"]) {
        expect(codigo, `${caminho}: ${proibido}`).not.toContain(proibido);
      }
    }

    // O adapter usa a Edge por `functions.invoke` e conhece o nome da função.
    const adapter = codigoDoCliente("src/infrastructure/supabase/observacoes/edgeObservacoes.ts");
    expect(adapter).toContain("functions.invoke");
    expect(adapter).toContain('FUNCAO_OBSERVACOES = "observacoes"');
  });

  it("o grafo da Edge não toca nenhuma tabela soberana diretamente (só RPC e resolvers)", () => {
    // A Edge autentica, autoriza e executa RPC: a LEITURA da linha soberana
    // acontece no wiring, via `admin.from(...)` de `user_profiles`/memberships e
    // do recurso — nunca uma escrita. Guarda explícita: nenhum `insert`/`update`/
    // `delete` de tabela no caminho da Edge.
    for (const caminho of ARQUIVOS_DA_EDGE) {
      const codigo = codigoSemComentarios(POR_CAMINHO.get(caminho) as string);
      expect(codigo, caminho).not.toMatch(/\.(insert|update|delete|upsert)\s*\(/);
    }
  });
});
