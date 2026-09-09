import { describe, expect, it, vi } from "vitest";
import {
  AccessNotProvisionedError,
  ForbiddenError,
  InvalidCredentialsError,
  TechnicalError,
} from "../errors/applicationErrors";
import type { Autenticador, RepositorioIdentidade } from "./contratos";
import {
  entrar,
  obterSessaoInicial,
  redefinirSenha,
  resolverIdentidade,
  sair,
  solicitarRecuperacaoDeSenha,
  validarNovaSenha,
} from "./servico";

function autenticadorFalso(parcial: Partial<Autenticador> = {}): Autenticador {
  return {
    entrarComSenha: vi.fn(async () => ({ data: null, error: null })),
    sair: vi.fn(async () => ({ data: null, error: null })),
    obterSessao: vi.fn(async () => ({ data: null, error: null })),
    observarAutenticacao: vi.fn(() => () => {}),
    validarSessaoAtual: vi.fn(async () => ({ data: null, error: null })),
    solicitarRecuperacaoDeSenha: vi.fn(async () => ({ data: null, error: null })),
    definirNovaSenha: vi.fn(async () => ({ data: null, error: null })),
    ...parcial,
  };
}

function repositorioFalso(parcial: Partial<RepositorioIdentidade> = {}): RepositorioIdentidade {
  return {
    buscarPerfil: vi.fn<RepositorioIdentidade["buscarPerfil"]>(async () => null),
    buscarMembershipsAtivas: vi.fn<RepositorioIdentidade["buscarMembershipsAtivas"]>(async () => []),
    buscarOrganizacoes: vi.fn<RepositorioIdentidade["buscarOrganizacoes"]>(async () => []),
    ...parcial,
  };
}

const usuarioFicticio = { id: "uuid-auth-1", email: "pessoa@example.invalid" };

describe("serviço de autenticação (F2-03)", () => {
  it("login válido devolve o usuário autenticado", async () => {
    const autenticador = autenticadorFalso({
      entrarComSenha: vi.fn(async () => ({ data: usuarioFicticio, error: null })),
    });

    const usuario = await entrar("pessoa@example.invalid", "senha-secreta", autenticador);

    expect(usuario).toEqual(usuarioFicticio);
    expect(autenticador.entrarComSenha).toHaveBeenCalledWith(
      "pessoa@example.invalid",
      "senha-secreta"
    );
  });

  it("credencial inválida vira erro público seguro, sem expor detalhe do Supabase", async () => {
    const autenticador = autenticadorFalso({
      entrarComSenha: vi.fn(async () => ({
        data: null,
        error: { code: "invalid_credentials", message: "Invalid login credentials" },
      })),
    });

    await expect(entrar("pessoa@example.invalid", "senha-errada", autenticador)).rejects.toBeInstanceOf(
      InvalidCredentialsError
    );
  });

  it("erro inesperado no login vira falha técnica segura", async () => {
    const autenticador = autenticadorFalso({
      entrarComSenha: vi.fn(async () => ({ data: null, error: new Error("rede fora") })),
    });

    await expect(entrar("pessoa@example.invalid", "x", autenticador)).rejects.toBeInstanceOf(
      TechnicalError
    );
  });

  it("logout sem erro conclui normalmente", async () => {
    const autenticador = autenticadorFalso();
    await expect(sair(autenticador)).resolves.toBeUndefined();
    expect(autenticador.sair).toHaveBeenCalledOnce();
  });

  it("obter sessão inicial devolve sessão quando presente", async () => {
    const autenticador = autenticadorFalso({
      obterSessao: vi.fn(async () => ({ data: { usuario: usuarioFicticio }, error: null })),
    });

    await expect(obterSessaoInicial(autenticador)).resolves.toEqual({
      usuario: usuarioFicticio,
    });
  });

  it("auth user sem perfil interno é acesso ainda não provisionado (mensagem neutra)", async () => {
    const repositorio = repositorioFalso({
      buscarPerfil: vi.fn<RepositorioIdentidade["buscarPerfil"]>(async () => null),
    });

    await expect(resolverIdentidade("uuid-auth-1", repositorio)).rejects.toBeInstanceOf(
      AccessNotProvisionedError
    );
  });

  it("perfil desabilitado é tratado como acesso negado", async () => {
    const repositorio = repositorioFalso({
      buscarPerfil: vi.fn<RepositorioIdentidade["buscarPerfil"]>(async () => ({
        id: "uuid-auth-1",
        status: "disabled",
      })),
    });

    await expect(resolverIdentidade("uuid-auth-1", repositorio)).rejects.toBeInstanceOf(
      ForbiddenError
    );
  });

  it("perfil com status inconsistente é negado (fail-closed, nunca ativo)", async () => {
    const repositorio = repositorioFalso({
      buscarPerfil: vi.fn<RepositorioIdentidade["buscarPerfil"]>(async () => ({
        id: "uuid-auth-1",
        status: "pending" as never,
      })),
    });

    await expect(resolverIdentidade("uuid-auth-1", repositorio)).rejects.toBeInstanceOf(
      ForbiddenError
    );
  });

  it("perfil válido sem membership ativa resolve identidade sem organização", async () => {
    const repositorio = repositorioFalso({
      buscarPerfil: vi.fn<RepositorioIdentidade["buscarPerfil"]>(async () => ({
        id: "uuid-auth-1",
        status: "active",
      })),
    });

    const identidade = await resolverIdentidade("uuid-auth-1", repositorio);

    expect(identidade.perfil).toEqual({ id: "uuid-auth-1", status: "active" });
    expect(identidade.memberships).toEqual([]);
    expect(identidade.organizacoes).toEqual([]);
  });

  it("usuário com uma membership resolve a organização correspondente", async () => {
    const repositorio = repositorioFalso({
      buscarPerfil: vi.fn<RepositorioIdentidade["buscarPerfil"]>(async () => ({
        id: "uuid-auth-1",
        status: "active",
      })),
      buscarMembershipsAtivas: vi.fn<RepositorioIdentidade["buscarMembershipsAtivas"]>(async () => [
        { id: "m1", organizationId: "org-1", status: "active" },
      ]),
      buscarOrganizacoes: vi.fn<RepositorioIdentidade["buscarOrganizacoes"]>(async () => [
        { id: "org-1", name: "Organização A" },
      ]),
    });

    const identidade = await resolverIdentidade("uuid-auth-1", repositorio);

    expect(identidade.memberships).toHaveLength(1);
    expect(identidade.organizacoes).toEqual([{ id: "org-1", name: "Organização A" }]);
  });

  it("múltiplas memberships são preservadas sem seleção arbitrária", async () => {
    const repositorio = repositorioFalso({
      buscarPerfil: vi.fn<RepositorioIdentidade["buscarPerfil"]>(async () => ({
        id: "uuid-auth-1",
        status: "active",
      })),
      buscarMembershipsAtivas: vi.fn<RepositorioIdentidade["buscarMembershipsAtivas"]>(async () => [
        { id: "m1", organizationId: "org-1", status: "active" },
        { id: "m2", organizationId: "org-2", status: "active" },
      ]),
      buscarOrganizacoes: vi.fn<RepositorioIdentidade["buscarOrganizacoes"]>(async () => [
        { id: "org-1", name: "Organização A" },
        { id: "org-2", name: "Organização B" },
      ]),
    });

    const identidade = await resolverIdentidade("uuid-auth-1", repositorio);

    expect(identidade.memberships.map((m) => m.organizationId)).toEqual(["org-1", "org-2"]);
    expect(identidade.organizacoes.map((o) => o.id)).toEqual(["org-1", "org-2"]);
  });
});

describe("recuperação e redefinição de senha (F2-05)", () => {
  it("solicitação dispara a chamada correta com e-mail e redirectTo", async () => {
    const autenticador = autenticadorFalso();

    await solicitarRecuperacaoDeSenha(
      "pessoa@example.invalid",
      "http://localhost:5173/redefinir-senha",
      autenticador
    );

    expect(autenticador.solicitarRecuperacaoDeSenha).toHaveBeenCalledWith(
      "pessoa@example.invalid",
      "http://localhost:5173/redefinir-senha"
    );
  });

  it("conta existente e inexistente produzem resultado indistinguível (sempre resolve)", async () => {
    const contaExistente = autenticadorFalso();
    const contaInexistente = autenticadorFalso({
      solicitarRecuperacaoDeSenha: vi.fn(async () => ({
        data: null,
        error: { code: "user_not_found", message: "User not found" },
      })),
    });

    await expect(
      solicitarRecuperacaoDeSenha("existe@example.invalid", "/x", contaExistente)
    ).resolves.toBeUndefined();
    await expect(
      solicitarRecuperacaoDeSenha("naoexiste@example.invalid", "/x", contaInexistente)
    ).resolves.toBeUndefined();
  });

  it("erro interno na solicitação não vaza (não lança mensagem técnica)", async () => {
    const autenticador = autenticadorFalso({
      solicitarRecuperacaoDeSenha: vi.fn(async () => ({
        data: null,
        error: new Error("detalhe interno fictício"),
      })),
    });

    await expect(
      solicitarRecuperacaoDeSenha("pessoa@example.invalid", "/x", autenticador)
    ).resolves.toBeUndefined();
  });

  it("redefinição chama o método correto e não vaza erro interno", async () => {
    const autenticador = autenticadorFalso();
    await redefinirSenha("SenhaNova1!", autenticador);
    expect(autenticador.definirNovaSenha).toHaveBeenCalledWith("SenhaNova1!");

    const comErro = autenticadorFalso({
      definirNovaSenha: vi.fn(async () => ({ data: null, error: new Error("interno") })),
    });
    await expect(redefinirSenha("SenhaNova1!", comErro)).rejects.toBeInstanceOf(TechnicalError);
  });

  it("validação local rejeita vazio, confirmação divergente e senha curta", () => {
    expect(validarNovaSenha("", "")).toBe("Informe e confirme a nova senha.");
    expect(validarNovaSenha("SenhaNova1!", "OutraSenha!")).toBe(
      "As senhas informadas não coincidem."
    );
    expect(validarNovaSenha("abc12", "abc12")).toBe(
      "A nova senha deve ter pelo menos 6 caracteres."
    );
    expect(validarNovaSenha("SenhaNova1!", "SenhaNova1!")).toBeNull();
  });
});
