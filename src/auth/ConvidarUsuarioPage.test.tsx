import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext, type AuthContextValue } from "./AuthContext";
import type { EstadoSessao } from "./controladorSessao";
import type { EstadoEstrutura } from "../pages/apoioEstrutura";
import ConvidarUsuarioPage from "./ConvidarUsuarioPage";

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

/** Fotografia soberana sintética com UMA colaboradora já cadastrada. */
const ESTRUTURA_COM_COLABORADORA: EstadoEstrutura = {
  fase: "pronto",
  estrutura: {
    unidades: [],
    periodosParent: [],
    posicoes: [],
    reportingLines: [],
    ocupacoes: [],
    cargos: [],
    senioridades: [],
    colegiados: [],
    colaboradores: [
      {
        collaboratorId: "22222222-2222-4222-8222-222222222222",
        nome: "Colaboradora Fictícia Alfa",
      },
    ],
  },
};

function renderizar(estado: EstadoSessao, estadoInicial?: EstadoEstrutura): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={contexto(estado)}>
      <MemoryRouter initialEntries={["/convidar-usuario"]}>
        <ConvidarUsuarioPage {...(estadoInicial ? { estadoInicial } : {})} />
      </MemoryRouter>
    </AuthContext.Provider>
  );
}

describe("ConvidarUsuarioPage (F2-06 + F6-A19)", () => {
  it("usuário autenticado com organizações vê o formulário mínimo de convite", () => {
    const html = renderizar(autenticado);

    expect(html).toContain("Convidar usuário");
    expect(html).toContain('type="email"');
    expect(html).toContain("Organização A");
    expect(html).toContain("Convidar");
  });

  it("exige a colaboradora já cadastrada: a conta nunca fica solta (#319)", () => {
    const html = renderizar(autenticado, ESTRUTURA_COM_COLABORADORA);

    expect(html).toContain("Colaboradora");
    expect(html).toContain("Colaboradora Fictícia Alfa");
    expect(html).toContain('value="22222222-2222-4222-8222-222222222222"');
  });

  it("sem sessão autenticada não renderiza o formulário", () => {
    const html = renderizar({ status: "indisponivel" });

    expect(html).not.toContain("Convidar usuário");
  });
});
