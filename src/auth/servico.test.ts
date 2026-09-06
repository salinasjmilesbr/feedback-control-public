import { describe, expect, it, vi } from "vitest";
import {
  ForbiddenError,
  InvalidCredentialsError,
  TechnicalError,
} from "../errors/applicationErrors";
import type { Autenticador, RepositorioIdentidade } from "./contratos";
import { entrar, obterSessaoInicial, resolverIdentidade, sair } from "./servico";

function autenticadorFalso(parcial: Partial<Autenticador> = {}): Autenticador {
  return {
    entrarComSenha: vi.fn(async () => ({ data: null, error: null })),
    sair: vi.fn(async () => ({ data: null, error: null })),
    obterSessao: vi.fn(async () => ({ data: null, error: null })),
    observarAutenticacao: vi.fn(() => () => {}),
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

  it("auth user sem perfil interno é erro de acesso seguro", async () => {
    const repositorio = repositorioFalso({
      buscarPerfil: vi.fn<RepositorioIdentidade["buscarPerfil"]>(async () => null),
    });

    await expect(resolverIdentidade("uuid-auth-1", repositorio)).rejects.toBeInstanceOf(
      ForbiddenError
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
