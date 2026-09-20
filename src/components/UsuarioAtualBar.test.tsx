import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it } from "vitest";
import { AuthContext, type AuthContextValue } from "../auth/AuthContext";
import {
  UsuarioAtualContext,
  type UsuarioAtualContextValue,
} from "../contexts/UsuarioAtualContext";
import type { Colaborador } from "../types/Colaborador";
import UsuarioAtualBar from "./UsuarioAtualBar";

/** Apenas dados sintéticos (F2-09): nunca nomes/e-mails reais da equipe. */
function colaboradorSintetico(parcial: Partial<Colaborador> & Pick<Colaborador, "matricula" | "nome">): Colaborador {
  return {
    status: "ATIVO",
    email: `sintetico.${parcial.matricula}@example.invalid`,
    cargo: "Cargo sintético",
    area: "Área sintética",
    respondePara: "",
    ...parcial,
  };
}

const GERENTE = colaboradorSintetico({
  matricula: 2001,
  nome: "Gerente Sintetico Alfa",
  funcao: "GERENTE",
});
const COORDENADOR = colaboradorSintetico({
  matricula: 2002,
  nome: "Coordenadora Sintetica Beta",
  funcao: "COORDENADOR",
});

const EMAIL_AUTENTICADO = "pessoa.real.sintetica@example.invalid";

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

function contextoUsuario(valor: UsuarioAtualContextValue): UsuarioAtualContextValue {
  return valor;
}

/**
 * Issue #317 (Fase 2): a MARCA (`VIRTUS · [empresa]`) e a SESSÃO real
 * (`AuthStatus`) passaram a ser do `ShellVirtus` — cobertas em
 * `shell/ShellVirtus.test.tsx`. Aqui o alvo é o que ficou exclusivo do contexto
 * de empresa: o gate da simulação DEV (F2-09).
 */
function renderizar(impersonacao: UsuarioAtualContextValue): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={authFalso()}>
      <MemoryRouter>
        <UsuarioAtualContext.Provider value={impersonacao}>
          <UsuarioAtualBar />
        </UsuarioAtualContext.Provider>
      </MemoryRouter>
    </AuthContext.Provider>
  );
}

describe("UsuarioAtualBar (F2-09)", () => {
  it("DEV: exibe o seletor de impersonação sintética claramente rotulado", () => {
    const html = renderizar(
      contextoUsuario({
        usuarioAtual: GERENTE,
        usuariosDisponiveis: [GERENTE, COORDENADOR],
        selecionarUsuario: () => {},
        simulacaoDevAtiva: true,
      })
    );

    expect(html).toContain('id="usuario-atual"');
    expect(html).toContain("simulação DEV");
    expect(html).toContain("Gerente Sintetico Alfa");
    expect(html).toContain("Coordenadora Sintetica Beta");
    // O componente NÃO apresenta identidade nem sessão: isso é do shell.
    expect(html).not.toContain("VIRTUS");
    expect(html).not.toContain(EMAIL_AUTENTICADO);
  });

  it("HOMOLOG/PROD: sem impersonação DEV não há seletor nem colaborador simulado", () => {
    const html = renderizar(
      contextoUsuario({
        usuarioAtual: undefined,
        usuariosDisponiveis: [],
        selecionarUsuario: () => {},
        simulacaoDevAtiva: false,
      })
    );

    expect(html).not.toContain('id="usuario-atual"');
    expect(html).not.toContain("simulação DEV");
    expect(html).not.toContain("Gerente Sintetico Alfa");
    // Sem controles no contexto de plataforma/uma única organização, não há
    // markup algum deste componente (o shell segue renderizando o resto).
    expect(html).toBe("");
  });

  it("HOMOLOG/PROD: mesmo com lista presente, o gate desligado não expõe o seletor (defesa em profundidade)", () => {
    const html = renderizar(
      contextoUsuario({
        usuarioAtual: GERENTE,
        usuariosDisponiveis: [GERENTE],
        selecionarUsuario: () => {},
        simulacaoDevAtiva: false,
      })
    );

    expect(html).not.toContain('id="usuario-atual"');
    expect(html).not.toContain("Gerente Sintetico Alfa");
  });
});
