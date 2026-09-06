import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter, Outlet, Route, Routes } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext, type AuthContextValue } from "./AuthContext";
import type { EstadoSessao } from "./controladorSessao";
import LayoutAutenticado from "./LayoutAutenticado";
import RecuperarSenhaPage from "./RecuperarSenhaPage";
import RedefinirSenhaPage from "./RedefinirSenhaPage";

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

function renderizar(componente: React.ReactNode, estado: EstadoSessao): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={contexto(estado)}>
      <MemoryRouter initialEntries={["/"]}>{componente}</MemoryRouter>
    </AuthContext.Provider>
  );
}

describe("telas de recuperação/redefinição (F2-05)", () => {
  it("formulário de recuperação é acessível com ação de envio e retorno", () => {
    const html = renderizar(<RecuperarSenhaPage />, { status: "naoAutenticado" });

    expect(html).toContain("Recuperar senha");
    expect(html).toContain('type="email"');
    expect(html).toContain("Enviar link");
    expect(html).toContain("Voltar para entrar");
    expect(html).not.toContain(CONTEUDO);
  });

  it("tela de redefinição não renderiza o formulário durante a verificação do link", () => {
    const html = renderizar(<RedefinirSenhaPage />, { status: "verificando" });

    expect(html).toContain("Verificando o link de recuperação");
    expect(html).not.toContain("Nova senha");
  });

  it("sem sessão de recuperação a tela falha de forma segura (sem formulário)", () => {
    const html = renderizar(<RedefinirSenhaPage />, { status: "naoAutenticado" });

    expect(html).toContain("Redefinição indisponível");
    expect(html).toContain("O link de recuperação é inválido ou expirou.");
    expect(html).not.toContain("Nova senha");
  });

  it("rotas públicas de recuperação/redefinição não passam pelo guard funcional", () => {
    const arvore = (caminho: string) =>
      renderToStaticMarkup(
        <AuthContext.Provider value={contexto({ status: "naoAutenticado" })}>
          <MemoryRouter initialEntries={[caminho]}>
            <Routes>
              <Route
                element={
                  <main className="app-main">
                    <Outlet />
                  </main>
                }
              >
                <Route path="/login" element={<p>LOGIN</p>} />
                <Route path="/recuperar-senha" element={<RecuperarSenhaPage />} />
                <Route path="/redefinir-senha" element={<RedefinirSenhaPage />} />
              </Route>
              <Route element={<LayoutAutenticado simulacaoDev={false} />}>
                <Route path="/pagina" element={<p>{CONTEUDO}</p>} />
              </Route>
            </Routes>
          </MemoryRouter>
        </AuthContext.Provider>
      );

    expect(arvore("/recuperar-senha")).toContain("Recuperar senha");
    expect(arvore("/redefinir-senha")).toContain("Redefinição indisponível");
    expect(arvore("/pagina")).not.toContain(CONTEUDO);
  });
});
