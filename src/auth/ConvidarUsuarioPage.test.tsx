import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext, type AuthContextValue } from "./AuthContext";
import type { EstadoSessao } from "./controladorSessao";
import ConvidarUsuarioPage from "./ConvidarUsuarioPage";

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

const autenticado: EstadoSessao = {
  status: "autenticado",
  sessao: { usuario: { id: "uuid-admin", email: "admin@example.invalid" } },
  identidade: {
    authUserId: "uuid-admin",
    perfil: { id: "uuid-admin", status: "active" },
    memberships: [{ id: "m1", organizationId: "org-1", status: "active" }],
    organizacoes: [{ id: "org-1", name: "Organização A" }],
  },
};

describe("ConvidarUsuarioPage (F2-06)", () => {
  it("usuário autenticado com organizações vê o formulário mínimo de convite", () => {
    const html = renderToStaticMarkup(
      <AuthContext.Provider value={contexto(autenticado)}>
        <MemoryRouter initialEntries={["/convidar-usuario"]}>
          <ConvidarUsuarioPage />
        </MemoryRouter>
      </AuthContext.Provider>
    );

    expect(html).toContain("Convidar usuário");
    expect(html).toContain('type="email"');
    expect(html).toContain("Organização A");
    expect(html).toContain("Convidar");
  });

  it("sem sessão autenticada não renderiza o formulário", () => {
    const html = renderToStaticMarkup(
      <AuthContext.Provider value={contexto({ status: "indisponivel" })}>
        <MemoryRouter initialEntries={["/convidar-usuario"]}>
          <ConvidarUsuarioPage />
        </MemoryRouter>
      </AuthContext.Provider>
    );

    expect(html).not.toContain("Convidar usuário");
  });
});
