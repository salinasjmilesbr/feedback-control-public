import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter, Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext, type AuthContextValue } from "./AuthContext";
import type { EstadoSessao } from "./controladorSessao";
import LayoutAutenticado from "./LayoutAutenticado";

const CONTEUDO = "CONTEUDO FUNCIONAL PROTEGIDO";
const CARREGANDO = "Verificando sessão";

function contexto(estado: EstadoSessao): AuthContextValue {
  return {
    estado,
    entrar: async () => {},
    sair: async () => {},
    solicitarRecuperacaoDeSenha: async () => {},
    redefinirSenha: async () => {},
    convidarUsuario: async () => ({ userId: "uuid-1" }),
    reconhecerExpiracao: () => {},
    revalidar: async () => {},
    organizacaoAtivaId: null,
    organizacoesDisponiveis: [],
    selecionarOrganizacao: () => {},
    organizacaoVersao: 0,
  };
}

function renderizar(
  estado: EstadoSessao,
  simulacaoDev: boolean,
  caminho = "/pagina"
): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={contexto(estado)}>
      <MemoryRouter initialEntries={[caminho]}>
        <Routes>
          <Route
            element={<LayoutAutenticado simulacaoDev={simulacaoDev} />}
          >
            <Route
              path="/pagina"
              element={<p>{CONTEUDO}</p>}
            />
            <Route path="/login" element={<p>PAGINA DE LOGIN</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    </AuthContext.Provider>
  );
}

describe("LayoutAutenticado (F2-04)", () => {
  it("usuário autenticado renderiza a rota funcional", () => {
    const html = renderizar(
      {
        status: "autenticado",
        sessao: { usuario: { id: "uuid-1" } },
        identidade: {
          authUserId: "uuid-1",
          perfil: { id: "uuid-1", status: "active" },
          memberships: [],
          organizacoes: [],
        },
      },
      false
    );

    expect(html).toContain(CONTEUDO);
    expect(html).not.toContain(CARREGANDO);
  });

  it("estado semOrganizacao renderiza tela dedicada e bloqueia o conteúdo funcional", () => {
    const html = renderizar(
      {
        status: "semOrganizacao",
        sessao: { usuario: { id: "uuid-1" } },
        identidade: {
          authUserId: "uuid-1",
          perfil: { id: "uuid-1", status: "active" },
          memberships: [],
          organizacoes: [],
        },
      },
      false
    );

    expect(html).toContain("Sem organização");
    expect(html).not.toContain(CONTEUDO);
    expect(html).not.toContain(CARREGANDO);
  });

  it("estado aguardandoSelecao bloqueia o conteúdo funcional", () => {
    const html = renderizar(
      {
        status: "aguardandoSelecao",
        sessao: { usuario: { id: "uuid-1" } },
        identidade: {
          authUserId: "uuid-1",
          perfil: { id: "uuid-1", status: "active" },
          memberships: [
            { id: "m1", organizationId: "org-1", status: "active" },
            { id: "m2", organizationId: "org-2", status: "active" },
          ],
          organizacoes: [],
        },
      },
      false
    );

    expect(html).toContain("Selecione a organização");
    expect(html).not.toContain(CONTEUDO);
    expect(html).not.toContain(CARREGANDO);
  });

  it("estado sessaoIndisponivel bloqueia o conteúdo funcional e permite tentar novamente", () => {
    const html = renderizar({ status: "sessaoIndisponivel" }, false);

    expect(html).toContain("Verificação indisponível");
    expect(html).toContain("Tentar novamente");
    expect(html).not.toContain(CONTEUDO);
  });

  it("durante a verificação renderiza apenas o carregamento (sem conteúdo protegido)", () => {
    const html = renderizar({ status: "verificando" }, false);

    expect(html).toContain(CARREGANDO);
    expect(html).not.toContain(CONTEUDO);
  });

  it("visitante sem sessão não recebe conteúdo protegido", () => {
    const html = renderizar({ status: "naoAutenticado" }, false);

    expect(html).not.toContain(CONTEUDO);
    expect(html).not.toContain(CARREGANDO);
  });

  it("sessão com acesso negado não recebe conteúdo protegido", () => {
    const html = renderizar(
      {
        status: "acessoNegado",
        erro: {
          code: "FORBIDDEN",
          category: "authorization",
          message: "acesso negado",
        },
      },
      false
    );

    expect(html).not.toContain(CONTEUDO);
  });

  it("auth indisponível em DEV com simulação preservada mantém o acesso", () => {
    const html = renderizar({ status: "indisponivel" }, true);

    expect(html).toContain(CONTEUDO);
  });

  it("auth indisponível fora do DEV não libera rotas funcionais", () => {
    const html = renderizar({ status: "indisponivel" }, false);

    expect(html).not.toContain(CONTEUDO);
    expect(html).not.toContain(CARREGANDO);
  });
});
