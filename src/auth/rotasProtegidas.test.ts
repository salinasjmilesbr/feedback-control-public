import { describe, expect, it } from "vitest";
import type { EstadoSessao } from "./controladorSessao";
import { decidirAcessoARotasFuncionais } from "./rotasProtegidas";

const identidadeValida = {
  authUserId: "uuid-1",
  perfil: { id: "uuid-1", status: "active" as const },
  memberships: [],
  organizacoes: [],
};

const estadoAutenticado: EstadoSessao = {
  status: "autenticado",
  sessao: { usuario: { id: "uuid-1", email: "pessoa@example.invalid" } },
  identidade: identidadeValida,
};

const estadoAcessoNegado: EstadoSessao = {
  status: "acessoNegado",
  erro: { code: "FORBIDDEN", category: "authorization", message: "acesso negado" },
};

describe("decisão de acesso às rotas funcionais (F2-04)", () => {
  it("durante o bootstrap nada de conteúdo protegido é liberado", () => {
    expect(decidirAcessoARotasFuncionais({ status: "verificando" }, true)).toEqual({
      tipo: "carregando",
    });
    expect(decidirAcessoARotasFuncionais({ status: "verificando" }, false)).toEqual({
      tipo: "carregando",
    });
  });

  it("usuário autenticado acessa as rotas funcionais", () => {
    expect(decidirAcessoARotasFuncionais(estadoAutenticado, true)).toEqual({
      tipo: "permitir",
    });
    expect(decidirAcessoARotasFuncionais(estadoAutenticado, false)).toEqual({
      tipo: "permitir",
    });
  });

  it("usuário sem organização tem a área funcional bloqueada (semOrganizacao)", () => {
    const estadoSemOrganizacao: EstadoSessao = {
      status: "semOrganizacao",
      sessao: { usuario: { id: "uuid-1" } },
      identidade: identidadeValida,
    };
    expect(decidirAcessoARotasFuncionais(estadoSemOrganizacao, true)).toEqual({
      tipo: "semOrganizacao",
    });
    expect(decidirAcessoARotasFuncionais(estadoSemOrganizacao, false)).toEqual({
      tipo: "semOrganizacao",
    });
  });

  it("visitante sem sessão é direcionado ao login", () => {
    expect(decidirAcessoARotasFuncionais({ status: "naoAutenticado" }, false)).toEqual({
      tipo: "redirecionarLogin",
    });
    expect(decidirAcessoARotasFuncionais({ status: "naoAutenticado" }, true)).toEqual({
      tipo: "redirecionarLogin",
    });
  });

  it("sessão com acesso negado não libera rotas funcionais", () => {
    expect(decidirAcessoARotasFuncionais(estadoAcessoNegado, true)).toEqual({
      tipo: "redirecionarLogin",
    });
    expect(decidirAcessoARotasFuncionais(estadoAcessoNegado, false)).toEqual({
      tipo: "redirecionarLogin",
    });
  });

  it("sessão expirada (F2-08) não libera rotas funcionais", () => {
    expect(
      decidirAcessoARotasFuncionais(
        { status: "sessaoExpirada", motivo: "inatividade" },
        true
      )
    ).toEqual({ tipo: "redirecionarLogin" });
    expect(
      decidirAcessoARotasFuncionais(
        { status: "sessaoExpirada", motivo: "duracaoMaxima" },
        false
      )
    ).toEqual({ tipo: "redirecionarLogin" });
  });

  it("auth indisponível permite apenas no DEV com simulação preservada", () => {
    expect(decidirAcessoARotasFuncionais({ status: "indisponivel" }, true)).toEqual({
      tipo: "permitir",
    });
    expect(decidirAcessoARotasFuncionais({ status: "indisponivel" }, false)).toEqual({
      tipo: "redirecionarLogin",
    });
  });

  it("nunca devolve redirecionamento para usuário autenticado (sem loop)", () => {
    const decisoes = [true, false].map((dev) =>
      decidirAcessoARotasFuncionais(estadoAutenticado, dev)
    );
    expect(decisoes).not.toContainEqual({ tipo: "redirecionarLogin" });
  });
});
