import { renderToStaticMarkup } from "react-dom/server";
import {
  MemoryRouter,
  Outlet,
  Route,
  Routes,
} from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext, type AuthContextValue } from "./AuthContext";
import type { EstadoSessao } from "./controladorSessao";
import LayoutAutenticado from "./LayoutAutenticado";
import LoginPage from "./LoginPage";

const CONTEUDO = "CONTEUDO FUNCIONAL PROTEGIDO";

function contexto(estado: EstadoSessao): AuthContextValue {
  return {
    estado,
    entrar: async () => {},
    sair: async () => {},
    solicitarRecuperacaoDeSenha: async () => {},
    redefinirSenha: async () => {},
    convidarUsuario: async () => ({ userId: "uuid-1" }),
  };
}

/**
 * Árvore que reproduz a ordem das rotas do AppRoutes (F2-04): `/login` fora do
 * guard autenticado; rotas funcionais dentro de `LayoutAutenticado`.
 */
function renderizar(estado: EstadoSessao, caminho: string): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={contexto(estado)}>
      <MemoryRouter initialEntries={[caminho]}>
        <Routes>
          <Route
            element={
              <main className="app-main">
                <Outlet />
              </main>
            }
          >
            <Route path="/login" element={<LoginPage />} />
          </Route>

          <Route element={<LayoutAutenticado simulacaoDev={false} />}>
            <Route path="/pagina" element={<p>{CONTEUDO}</p>} />
            <Route path="*" element={<p>FALLBACK FUNCIONAL</p>} />
          </Route>
        </Routes>
      </MemoryRouter>
    </AuthContext.Provider>
  );
}

describe("roteamento autenticado (F2-04)", () => {
  it("visitante acessando a rota pública /login vê o formulário de login", () => {
    const html = renderizar({ status: "naoAutenticado" }, "/login");

    expect(html).toContain("Entrar");
    expect(html).not.toContain(CONTEUDO);
    expect(html).not.toContain("FALLBACK FUNCIONAL");
  });

  it("usuário autenticado acessa rota funcional direta", () => {
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
      "/pagina"
    );

    expect(html).toContain(CONTEUDO);
  });

  it("visitante acessando rota funcional não recebe conteúdo (guard direciona ao login)", () => {
    const html = renderizar({ status: "naoAutenticado" }, "/pagina");

    expect(html).not.toContain(CONTEUDO);
    expect(html).not.toContain("Verificando sessão");
  });

  it("auth indisponível fora do DEV não libera rota funcional (falha segura)", () => {
    const html = renderizar({ status: "indisponivel" }, "/pagina");

    expect(html).not.toContain(CONTEUDO);
  });
});
