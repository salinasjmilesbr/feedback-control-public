import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import EntradaPlataforma, { EntradaPlataformaVisivel } from "./EntradaPlataforma";
import ComponenteFonte from "./EntradaPlataforma.tsx?raw";
import LoginFonte from "./LoginPage.tsx?raw";
import AguardandoFonte from "./AguardandoSelecao.tsx?raw";
import SemOrganizacaoFonte from "./SemOrganizacao.tsx?raw";
import type { ProvisionamentoPlataforma } from "../application/ports/ProvisionamentoPlataforma";

/**
 * F6-A04 (Issue #269) — entrada da superfície de plataforma (contrato §3.1 e §6).
 *
 * Prova, com o tooling disponível (render sem DOM + leitura estática do código):
 * - **visibilidade**: `visivel === false` não renderiza NADA e `visivel === true`
 *   renderiza o link para `/plataforma/nova-organizacao` (critério 6);
 * - **portão fail-closed**: o render inicial é sempre vazio (o portão começa
 *   fechado; só a sonda positiva o abre) e o caminho de produção sem caminho
 *   soberano também não oferece entrada;
 * - **componente único (D3)**: os quatro call sites usam o MESMO componente e
 *   **nenhum** deles reimplementa a sonda;
 * - **barreiras**: sem `localStorage`/`sessionStorage`, sem `.rpc(`, sem
 *   credencial privilegiada, sem `authorize(`/`can(`/`capability` e sem dado de
 *   tenant.
 *
 * Limitação declarada: o projeto não possui ambiente DOM (effects não executam em
 * `renderToStaticMarkup`), então o estado pós-sonda é provado pela separação
 * apresentação × portão e pela semântica fail-closed do próprio portão
 * (`controladorProvisionamento.test.ts` prova que `souOperadorDaPlataforma`
 * resolve `true` SOMENTE com `ok: true` e `operador === true`, e nunca lança).
 */

const ROTA = "/plataforma";

/** Remove comentários: as barreiras valem para o CÓDIGO, não para a prosa. */
function apenasCodigo(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

/** Sonda que nunca resolve: o portão permanece fechado no render. */
const portaPendente: ProvisionamentoPlataforma = {
  provisionarOrganizacao: async () => ({ organizationId: "o-1" }),
  souOperadorDaPlataforma: () => new Promise<boolean>(() => {}),
  identidadeDoOperadorAutenticado: async () => null,
};

describe("F6-A04 — entrada de plataforma: apresentação pura (critério 6)", () => {
  it("`visivel === false` NÃO renderiza nada", () => {
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <EntradaPlataformaVisivel visivel={false} />
      </MemoryRouter>
    );

    expect(html).toBe("");
    expect(html).not.toContain("Criar organização");
    expect(html).not.toContain(ROTA);
  });

  it("`visivel === true` renderiza o link para a superfície de plataforma", () => {
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <EntradaPlataformaVisivel visivel={true} />
      </MemoryRouter>
    );

    expect(html).toContain(`href="${ROTA}"`);
    expect(html).toContain("Administração da plataforma");
    // Nada de identificador interno, token, hash ou dado de tenant.
    expect(html).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
    expect(html).not.toContain("F6_A03_");
  });
});

describe("F6-A04 — entrada de plataforma: portão fail-closed", () => {
  it("o render inicial é vazio — com e sem caminho soberano no ambiente", () => {
    const comSonda = renderToStaticMarkup(
      <MemoryRouter>
        <EntradaPlataforma provisionamento={portaPendente} />
      </MemoryRouter>
    );
    const semCaminho = renderToStaticMarkup(
      <MemoryRouter>
        <EntradaPlataforma provisionamento={null} />
      </MemoryRouter>
    );

    // Nada aparece antes de a sonda responder (nem quando o ambiente não oferece
    // o caminho soberano): fail-closed, sem exposição prematura.
    for (const html of [comSonda, semCaminho]) {
      expect(html).toBe("");
      expect(html).not.toContain("<a");
    }
  });

  it("sem injeção o caminho de produção também não oferece entrada neste ambiente", () => {
    // Sem `VITE_SUPABASE_*` não há cliente ⇒ `obterProvisionamentoPlataforma()`
    // devolve `null` ⇒ portão fechado.
    const html = renderToStaticMarkup(
      <MemoryRouter>
        <EntradaPlataforma />
      </MemoryRouter>
    );
    expect(html).toBe("");
  });
});

describe("F6-A04 — barreiras estáticas do componente (D1/D2/D3/D20)", () => {
  it("o portão é fechado por construção e só a sonda o abre", () => {
    const codigo = apenasCodigo(ComponenteFonte as string);

    // Estado inicial SEMPRE oculto + único caminho de abertura é a sonda.
    expect(codigo).toContain("useState(false)");
    expect(codigo).toContain("souOperadorDaPlataforma()");
    expect(codigo).toMatch(/\.then\(\(operador\) => \{\s*if \(vigente\) setVisivel\(operador\);/);

    // O link está DEPOIS da guarda: sem `visivel` nada é renderizado.
    const guarda = codigo.indexOf("if (!visivel) return null;");
    const link = codigo.indexOf("<Link to={ROTA_PLATAFORMA}");
    expect(guarda).toBeGreaterThan(-1);
    expect(link).toBeGreaterThan(guarda);
  });

  it("não escreve no navegador, não chama RPC, não usa credencial e não decide autorização", () => {
    const codigo = apenasCodigo(ComponenteFonte as string);

    for (const proibido of [
      "localStorage",
      "sessionStorage",
      ".rpc(",
      "service_role",
      "SERVICE_ROLE",
      "serviceRoleKey",
      "authorize(",
      "can(",
      "capability",
      "Policy Engine",
      "organization_id",
    ]) {
      expect(codigo, proibido).not.toContain(proibido);
    }
    // A rota vem do guard único da F6-A03 — nada de literal duplicado.
    expect(codigo).toContain("ROTA_PLATAFORMA");
  });
});

describe("F6-A04 — call sites: componente ÚNICO e sem sonda duplicada (D3)", () => {
  const CALL_SITES: readonly (readonly [string, string])[] = [
    ["LoginPage", LoginFonte as string],
    ["AguardandoSelecao", AguardandoFonte as string],
    ["SemOrganizacao", SemOrganizacaoFonte as string],
  ];

  it("os três call sites importam e renderizam `<EntradaPlataforma />`", () => {
    for (const [nome, fonte] of CALL_SITES) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).toContain('from "./EntradaPlataforma"');
      expect(codigo, nome).toContain("<EntradaPlataforma />");
    }
  });

  it("NENHUM call site reimplementa a sonda (prova do componente único)", () => {
    for (const [nome, fonte] of CALL_SITES) {
      const codigo = apenasCodigo(fonte);
      expect(codigo, nome).not.toContain("souOperadorDaPlataforma");
      expect(codigo, nome).not.toContain("obterProvisionamentoPlataforma");
      expect(codigo, nome).not.toContain("ROTA_PLATAFORMA_NOVA_ORGANIZACAO");
    }
  });

  it("nenhum call site ganhou storage, RPC ou credencial", () => {
    for (const [nome, fonte] of CALL_SITES) {
      const codigo = apenasCodigo(fonte);
      for (const proibido of ["localStorage", "sessionStorage", ".rpc(", "service_role"]) {
        expect(codigo, `${nome}:${proibido}`).not.toContain(proibido);
      }
    }
  });
});
