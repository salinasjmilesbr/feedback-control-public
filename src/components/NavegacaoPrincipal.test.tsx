import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext } from "../auth/AuthContext";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import type { Colaborador } from "../types/Colaborador";
import menuFonte from "./NavegacaoPrincipal.tsx?raw";
import NavegacaoPrincipal from "./NavegacaoPrincipal";

const usuario: Colaborador = {
  matricula: 1,
  status: "ATIVO",
  nome: "Admin Fictício",
  email: "admin@example.invalid",
  cargo: "",
  area: "",
  funcao: undefined,
  respondePara: "",
};

function renderizar(): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={{
      estado: {
        status: "autenticado",
        sessao: { usuario: { id: "user-1", email: usuario.email } },
        identidade: {
          authUserId: "user-1",
          perfil: { id: "user-1", status: "active" },
          memberships: [{ id: "membership-1", organizationId: "org-1", status: "active" }],
          organizacoes: [{ id: "org-1", name: "Org" }],
        },
      },
      entrar: async () => undefined,
      sair: async () => undefined,
      solicitarRecuperacaoDeSenha: async () => undefined,
      redefinirSenha: async () => undefined,
      convidarUsuario: async () => ({ userId: "user-2" }),
      reconhecerExpiracao: () => undefined,
      revalidar: async () => undefined,
      organizacaoAtivaId: "org-1",
      organizacoesDisponiveis: [{ id: "org-1", name: "Org" }],
      selecionarOrganizacao: () => undefined,
      organizacaoVersao: 0,
    }}>
      <UsuarioAtualContext.Provider value={{
        usuarioAtual: usuario,
        usuariosDisponiveis: [usuario],
        selecionarUsuario: () => undefined,
      }}>
        <MemoryRouter><NavegacaoPrincipal /></MemoryRouter>
      </UsuarioAtualContext.Provider>
    </AuthContext.Provider>
  );
}

describe("NavegacaoPrincipal — gates soberanos", () => {
  it("mantém estrutura/catálogos visíveis no primeiro render sem capabilities carregadas", () => {
    const html = renderizar();
    expect(html).toContain("Unidades");
    expect(html).toContain("Posições");
    expect(html).toContain("Colegiado");
    expect(html).toContain("Catálogos");
    expect(html).not.toContain("Ciclos");
  });

  it("usa somente códigos canônicos e snapshot soberano", () => {
    for (const capability of [
      "cycle.read",
      "evaluation.read",
      "goal.read",
      "report.read",
      "settings.manage",
    ]) expect(menuFonte).toContain(`possui("${capability}")`);
    expect(menuFonte).toContain("listarCapabilitiesEfetivas");
    expect(menuFonte).not.toContain("perfilPossuiFluxosPropriosAtuais");
    expect(menuFonte).not.toContain("report.view");
    expect(menuFonte).not.toContain("can(");
  });
});
