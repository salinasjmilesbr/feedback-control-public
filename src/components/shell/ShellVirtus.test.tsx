/// <reference types="node" />
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext, type AuthContextValue } from "../../auth/AuthContext";
import ShellVirtus from "./ShellVirtus";

/**
 * Issue #317 (Fase 2) — guarda do SHELL UNIVERSAL.
 *
 * O que estes testes protegem (e por quê):
 * 1. o contexto do shell é EXPLÍCITO: a plataforma mantém identidade Virtus fixa
 *    e IGNORA qualquer mapa de tema, mesmo que um chamador o envie por engano
 *    (fail-closed);
 * 2. no contexto de empresa o mapa de custom properties do tenant é aplicado
 *    SOMENTE no container do shell — a marca não escreve em
 *    `documentElement`/`body`;
 * 3. o chrome legado (`.app-header*`/`.app-footer*`/`.app-role-badge`) não pode
 *    voltar, e o eixo horizontal continua único (o shell participa dele).
 *
 * A leitura de CSS/TSX é feita com `node:fs`: no Vitest o CSS é stub
 * (`css: false`), então `?raw` devolveria string vazia e a guarda seria vacuosa.
 * As asserções NEGATIVAS usam `apenasCodigo`: a documentação do próprio arquivo
 * cita os termos proibidos (ex.: "Admin Virtus") justamente para explicá-los —
 * comentário não é implementação.
 */

const DIR_SRC = fileURLToPath(new URL("../..", import.meta.url));
const EMAIL_AUTENTICADO = "pessoa.sintetica@example.invalid";

function fonte(caminhoRelativo: string): string {
  return readFileSync(join(DIR_SRC, caminhoRelativo), "utf8");
}

/** Remove comentários de bloco e de linha (o resto é tratado como código). */
function apenasCodigo(conteudo: string): string {
  return conteudo
    .replace(/\/\*[\s\S]*?\*\//g, " ")
    .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
}

function authFalso(): AuthContextValue {
  return {
    estado: {
      status: "autenticado",
      sessao: { usuario: { id: "uuid-auth-1", email: EMAIL_AUTENTICADO } },
      identidade: {
        authUserId: "uuid-auth-1",
        perfil: { id: "uuid-auth-1", status: "active" },
        memberships: [],
        organizacoes: [],
      },
    },
    entrar: async () => {},
    sair: async () => {},
    solicitarRecuperacaoDeSenha: async () => {},
    redefinirSenha: async () => {},
    convidarUsuario: async () => ({ userId: "uuid-auth-1" }),
    reconhecerExpiracao: () => {},
    revalidar: async () => {},
    organizacaoAtivaId: null,
    organizacoesDisponiveis: [],
    selecionarOrganizacao: () => {},
    organizacaoVersao: 0,
  };
}

function renderizar(elemento: ReactNode): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={authFalso()}>
      <MemoryRouter>{elemento}</MemoryRouter>
    </AuthContext.Provider>
  );
}

/**
 * Tag do container do shell. O React 19 hoista `<link rel="preload">` de imagens
 * para o topo da saída, então a primeira tag do HTML não é o `<div>` do shell.
 */
function tagDoContainer(html: string): string {
  return html.match(/<div[^>]*class="virtus-shell"[^>]*>/)?.[0] ?? "";
}

describe("ShellVirtus — contexto de PLATAFORMA (Virtus puro)", () => {
  it("usa a identidade oficial fixa e NENHUMA variável de tenant", () => {
    const html = renderizar(
      <ShellVirtus contexto="plataforma">
        <p>conteúdo</p>
      </ShellVirtus>
    );

    expect(html).toContain("VIRTUS");
    expect(html).toContain("Gestão Virtus");
    // Texto SSR: o React escapa `&` da tagline (§1) para `&amp;`.
    expect(html).toContain("Performance &amp; Feedback Management");
    expect(html).toContain("Versão 1.0.0");
    // §1: consome o asset oficial versionado.
    expect(html).toContain('src="/brand/virtus-symbol.png"');
    // Sem mapa de tema: o container não carrega `style` inline nenhum.
    expect(html).not.toContain("--brand-");
    expect(html).not.toContain("style=");
    // A sessão real continua visível (AuthStatus no header universal).
    expect(html).toContain(EMAIL_AUTENTICADO);
    // Nada de estrutura soberana de tenant na plataforma (D19/D21).
    expect(html).not.toContain("app-nav");
  });

  it("IGNORA tema de tenant enviado por engano (fail-closed)", () => {
    const html = renderizar(
      <ShellVirtus
        contexto="plataforma"
        nomeEmpresa="Empresa Sintética Alfa"
        tema={{ "--brand-primary": "#ff0000", "--brand-bg": "#00ff00" }}
      >
        <p>conteúdo</p>
      </ShellVirtus>
    );

    expect(html).not.toContain("--brand-primary");
    expect(html).not.toContain("#ff0000");
    expect(html).not.toContain("#00ff00");
    expect(tagDoContainer(html)).not.toContain("style=");
    // Nem o rótulo de empresa entra no contexto de plataforma.
    expect(html).not.toContain("Empresa Sintética Alfa");
  });
});

describe("ShellVirtus — contexto de EMPRESA (tema escopado ao container)", () => {
  it("aplica o tema da organização SOMENTE no container do shell", () => {
    const html = renderizar(
      <ShellVirtus
        contexto="empresa"
        nomeEmpresa="Empresa Sintética Alfa"
        tema={{ "--brand-primary": "#123456", "--brand-bg": "#010203" }}
      >
        <p>conteúdo</p>
      </ShellVirtus>
    );

    const container = tagDoContainer(html);
    expect(container).toContain('class="virtus-shell"');
    expect(container).toContain('data-contexto="empresa"');
    expect(container).toMatch(/--brand-primary:\s*#123456/);
    expect(container).toMatch(/--brand-bg:\s*#010203/);
    // A marca é a oficial, com o contexto da empresa ao lado (§6).
    expect(html).toContain("VIRTUS");
    expect(html).toContain("Empresa Sintética Alfa");
    expect(html).toContain('src="/brand/virtus-symbol.png"');
    expect(html).toContain(EMAIL_AUTENTICADO);
  });

  it("sem tema calculado não há `style` inline (defaults seguros da fundação)", () => {
    const html = renderizar(
      <ShellVirtus contexto="empresa" nomeEmpresa="Empresa Sintética Beta">
        <p>conteúdo</p>
      </ShellVirtus>
    );

    expect(html).not.toContain("style=");
    expect(html).toContain("Empresa Sintética Beta");
  });

  it("sem nome de empresa o header não repete a marca (só o rodapé tem contexto)", () => {
    const html = renderizar(
      <ShellVirtus contexto="empresa">
        <p>conteúdo</p>
      </ShellVirtus>
    );

    // O contexto aparece UMA vez (rodapé com a tagline), nunca no header.
    expect((html.match(/virtus-shell__context/g) ?? []).length).toBe(1);
    expect(html).not.toMatch(/virtus-shell__context[^>]*>VIRTUS</);
  });
});

describe("ShellVirtus — barreiras estáticas", () => {
  it("o shell não escreve tema em elemento global nem lê persistência local", () => {
    for (const caminho of [
      "components/shell/ShellVirtus.tsx",
      "components/shell/MarcaVirtus.tsx",
      "components/shell/identidadeVirtus.ts",
      "styles/virtus-shell.css",
    ]) {
      const codigo = apenasCodigo(fonte(caminho));
      expect(codigo, caminho).not.toContain("documentElement");
      expect(codigo, caminho).not.toContain("document.body");
      expect(codigo, caminho).not.toContain("localStorage");
      expect(codigo, caminho).not.toContain("Feedback Control");
      // O tema do tenant nunca é decidido pelo chrome: ele só o recebe pronto.
      expect(codigo, caminho).not.toContain("temaDoTenant");
      // Verde permanece exclusivamente semântico (§2): nunca no chrome.
      expect(codigo.toLowerCase(), caminho).not.toContain("#10b981");
    }
  });

  it("a plataforma não carrega estrutura soberana de tenant (D19)", () => {
    const layout = apenasCodigo(fonte("routes/LayoutPlataforma.tsx"));

    expect(layout).toContain("ShellVirtus");
    expect(layout).toContain('contexto="plataforma"');
    for (const proibido of [
      "UsuarioAtualBar",
      "NavegacaoPrincipal",
      "useBranding",
      "organizacaoAtivaId",
      "AuthorizationContext",
    ]) {
      expect(layout, proibido).not.toContain(proibido);
    }
  });

  it("somente o layout de EMPRESA entrega o mapa de tema do tenant", () => {
    const rotas = apenasCodigo(fonte("routes/AppRoutes.tsx"));

    expect(rotas).toContain('contexto="empresa"');
    expect(rotas).toContain("tema={tema.variaveis}");
    expect(rotas).toContain("<UsuarioAtualBar />");
    expect(rotas).toContain("<NavegacaoPrincipal />");
    // O componente legado do rodapé não existe mais (substituído pelo shell).
    expect(rotas).not.toContain("AppFooter");
  });

  it("o chrome legado não volta e o eixo horizontal segue ÚNICO", () => {
    const folhas = readdirSync(join(DIR_SRC), { recursive: true, encoding: "utf8" })
      .map((nome) => nome.replace(/\\/g, "/"))
      .filter((nome) => nome.endsWith(".css"))
      .sort();

    // Não-vacuidade: o índice precisa cobrir o repositório.
    expect(folhas.length).toBeGreaterThan(20);

    for (const nome of folhas) {
      const css = apenasCodigo(readFileSync(join(DIR_SRC, nome), "utf8"));
      expect(css, nome).not.toMatch(
        /\.app-(?:header|footer|role-badge)(?:__[\w-]+)?(?![\w-])/
      );
    }

    const caminhoShell = folhas.find((nome) =>
      nome.endsWith("styles/virtus-shell.css")
    );
    expect(caminhoShell, "styles/virtus-shell.css ausente").toBeDefined();

    const cssShell = apenasCodigo(
      readFileSync(join(DIR_SRC, caminhoShell as string), "utf8")
    );
    // A folha do shell tem conteúdo real e não redeclara tokens.
    expect((cssShell.match(/\.virtus-shell/g) ?? []).length).toBeGreaterThan(20);
    expect(cssShell).not.toContain(":root");

    const foundation = apenasCodigo(fonte("styles/virtus-foundation.css"));
    expect(foundation).toContain(".virtus-shell__header-inner");
    expect(foundation).toContain(".virtus-shell__footer-inner");
    expect(foundation).toContain(".app-nav__inner");
  });

  it("a identidade do shell é exatamente a do contrato aprovado (#312)", () => {
    const identidade = apenasCodigo(fonte("components/shell/identidadeVirtus.ts"));

    expect(identidade).toContain('"VIRTUS"');
    expect(identidade).toContain('"Performance & Feedback Management"');
    expect(identidade).toContain('"Gestão Virtus"');
    expect(identidade).toContain('"/brand/virtus-symbol.png"');
    // Identidade legada e nomenclatura reprovada na matriz de aceite.
    expect(identidade).not.toContain("#660099");
    expect(identidade).not.toContain("Admin Virtus");
  });
});
