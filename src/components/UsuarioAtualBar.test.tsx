import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, beforeEach } from "vitest";
import { AuthContext, type AuthContextValue } from "../auth/AuthContext";
import { BrandingProvider } from "../contexts/BrandingProvider";
import {
  UsuarioAtualContext,
  type UsuarioAtualContextValue,
} from "../contexts/UsuarioAtualContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
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
  };
}

function contextoUsuario(valor: UsuarioAtualContextValue): UsuarioAtualContextValue {
  return valor;
}

function renderizar(impersonacao: UsuarioAtualContextValue): string {
  return renderToStaticMarkup(
    <AuthContext.Provider value={authFalso()}>
      <BrandingProvider>
        <MemoryRouter>
          <UsuarioAtualContext.Provider value={impersonacao}>
            <UsuarioAtualBar />
          </UsuarioAtualContext.Provider>
        </MemoryRouter>
      </BrandingProvider>
    </AuthContext.Provider>
  );
}

describe("UsuarioAtualBar (F2-09)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it("DEV: exibe o seletor de impersonação sintética claramente rotulado, junto da sessão real", () => {
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
    // A sessão real do Supabase Auth continua separada e visível (AuthStatus).
    expect(html).toContain(EMAIL_AUTENTICADO);
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
    // Auth real permanece soberano: o usuário autenticado continua visível.
    expect(html).toContain(EMAIL_AUTENTICADO);
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
    expect(html).toContain(EMAIL_AUTENTICADO);
  });
});
