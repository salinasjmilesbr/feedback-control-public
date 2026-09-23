import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext } from "../auth/AuthContext";
import { UsuarioAtualContext } from "../contexts/UsuarioAtualContext";
import type { Colaborador } from "../types/Colaborador";
import type { AutorizacaoEstruturalSoberana } from "../services/autorizacaoEstruturalSoberana";
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

/**
 * #327/P2B — o menu PROJETA `estrutura_autorizacao` (view do P1); a semente
 * `autorizacaoInicial` fixa a projeção no SSR/teste, sem ler a view.
 */
function renderizar(
  usuarioAtual?: Colaborador,
  autorizacaoInicial?: AutorizacaoEstruturalSoberana
): string {
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
        usuarioAtual,
        usuariosDisponiveis: usuarioAtual ? [usuarioAtual] : [],
        selecionarUsuario: () => undefined,
      }}>
        <MemoryRouter>
          <NavegacaoPrincipal autorizacaoInicial={autorizacaoInicial} />
        </MemoryRouter>
      </UsuarioAtualContext.Provider>
    </AuthContext.Provider>
  );
}

describe("NavegacaoPrincipal — gates soberanos", () => {
  it("sem projeção de autorização não mostra superfícies administrativas", () => {
    const html = renderizar();

    expect(html).toContain("Início");
    expect(html).not.toContain("Minha equipe");
    expect(html).not.toContain("Unidades");
    expect(html).not.toContain("Posições");
    expect(html).not.toContain("Colegiado");
    expect(html).not.toContain("Catálogos");
    expect(html).not.toContain("Ciclos");
  });

  it("membership sem capability não projeta estrutura nem catálogos", () => {
    const html = renderizar(undefined, { podeEstrutura: false, podeCatalogo: false, collaboratorId: null });

    expect(html).toContain("Início");
    expect(html).not.toContain("Unidades");
    expect(html).not.toContain("Catálogos");
  });

  it("org.structure.manage projeta Unidades/Posições/Colegiado e não Catálogos", () => {
    const html = renderizar(undefined, { podeEstrutura: true, podeCatalogo: false, collaboratorId: null });

    expect(html).toContain("Unidades");
    expect(html).toContain("Posições");
    expect(html).toContain("Colegiado");
    expect(html).not.toContain("Catálogos");
  });

  it("org.catalog.manage projeta somente Catálogos", () => {
    const html = renderizar(undefined, { podeEstrutura: false, podeCatalogo: true, collaboratorId: null });

    expect(html).toContain("Catálogos");
    expect(html).not.toContain("Unidades");
    expect(html).not.toContain("Posições");
    expect(html).not.toContain("Colegiado");
  });

  it("as duas capabilities projetam as quatro superfícies", () => {
    const html = renderizar(undefined, { podeEstrutura: true, podeCatalogo: true, collaboratorId: null });

    expect(html).toContain("Unidades");
    expect(html).toContain("Posições");
    expect(html).toContain("Colegiado");
    expect(html).toContain("Catálogos");
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
    expect(menuFonte).toContain("listarEscoposMinhaEquipe");
    expect(menuFonte).toContain('snapshot.escoposMinhaEquipe.size > 0');
    expect(menuFonte).toContain('to="/colaboradores"');
    expect(menuFonte).toContain('to="/" end');
    expect(menuFonte).not.toContain("perfilPossuiFluxosPropriosAtuais");
    expect(menuFonte).not.toContain("report.view");
    expect(menuFonte).not.toContain("can(");
  });

  it("projeta a view de autorização e nunca lê as views de dados", () => {
    expect(menuFonte).toContain("lerAutorizacaoEstrutural");
    expect(menuFonte).toContain("estrutura_autorizacao");
    // O menu não é autoridade: nenhuma view de DADOS é consultada aqui e a
    // URL direta continua dependendo da view que entrega a estrutura.
    expect(menuFonte).not.toContain("estrutura_administrativa");
    expect(menuFonte).not.toContain("estrutura_pessoal");
    expect(menuFonte).not.toContain("criarLeituraEstrutura");
  });
});
