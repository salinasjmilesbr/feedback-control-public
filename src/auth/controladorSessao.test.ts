import { describe, expect, it, vi } from "vitest";
import type { Autenticador, RepositorioIdentidade } from "./contratos";
import { criarControladorSessao, type EstadoSessao } from "./controladorSessao";

interface AutenticadorFalso {
  autenticador: Autenticador;
  unsubscribe: ReturnType<typeof vi.fn>;
  notificarSessao: (sessao: Parameters<Autenticador["observarAutenticacao"]>[0] extends (s: infer S) => void ? S : never) => void;
  senhasRecebidas: string[];
}

function criarAutenticadorFalso(opcoes: {
  sessaoInicial?: { id: string; email?: string } | null;
  usuarioLogin?: { id: string; email?: string } | null;
  erroLogin?: unknown | null;
} = {}): AutenticadorFalso {
  const unsubscribe = vi.fn();
  let aoMudar: ((sessao: { usuario: { id: string; email?: string | null } } | null) => void) | null = null;
  const senhasRecebidas: string[] = [];

  const autenticador: Autenticador = {
    entrarComSenha: vi.fn(async (_email: string, senha: string) => {
      senhasRecebidas.push(senha);
      if (opcoes.erroLogin) return { data: null, error: opcoes.erroLogin };
      const usuario = opcoes.usuarioLogin ?? { id: "uuid-1", email: "pessoa@example.invalid" };
      return { data: { id: usuario.id, email: usuario.email ?? null }, error: null };
    }),
    sair: vi.fn(async () => ({ data: null, error: null })),
    obterSessao: vi.fn(async () => {
      const sessao = opcoes.sessaoInicial ?? null;
      return { data: sessao ? { usuario: { id: sessao.id, email: sessao.email ?? null } } : null, error: null };
    }),
    observarAutenticacao: vi.fn((callback) => {
      aoMudar = callback;
      return unsubscribe;
    }),
    solicitarRecuperacaoDeSenha: vi.fn(async () => ({ data: null, error: null })),
    definirNovaSenha: vi.fn(async () => ({ data: null, error: null })),
  };

  return {
    autenticador,
    unsubscribe,
    notificarSessao: (sessao) => aoMudar?.(sessao),
    senhasRecebidas,
  };
}

function repositorioFalso(parcial: Partial<RepositorioIdentidade> = {}): RepositorioIdentidade {
  return {
    buscarPerfil: vi.fn(async () => ({ id: "uuid-1", status: "active" as const })),
    buscarMembershipsAtivas: vi.fn(async () => []),
    buscarOrganizacoes: vi.fn(async () => []),
    ...parcial,
  };
}

function ultimo(estados: EstadoSessao[]): EstadoSessao {
  return estados[estados.length - 1] as EstadoSessao;
}

async function microtarefas() {
  await new Promise((resolve) => setTimeout(resolve, 0));
}

describe("controlador de sessão (F2-03)", () => {
  it("restaura sessão existente no bootstrap e resolve identidade", async () => {
    const fake = criarAutenticadorFalso({
      sessaoInicial: { id: "uuid-1", email: "pessoa@example.invalid" },
    });
    const repositorio = repositorioFalso();
    const estados: EstadoSessao[] = [];

    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();

    expect(ultimo(estados)).toEqual({
      status: "autenticado",
      sessao: { usuario: { id: "uuid-1", email: "pessoa@example.invalid" } },
      identidade: {
        authUserId: "uuid-1",
        perfil: { id: "uuid-1", status: "active" },
        memberships: [],
        organizacoes: [],
      },
    });
  });

  it("sem sessão inicial fica não autenticado", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();

    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });
  });

  it("sem configuração de Supabase fica indisponível (sem fabricar identidade)", async () => {
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: null,
      repositorio: null,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();

    expect(ultimo(estados)).toEqual({ status: "indisponivel" });
  });

  it("login válido autentica e resolve identidade sem vazar a senha no estado", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const repositorio = repositorioFalso({
      buscarMembershipsAtivas: vi.fn(async () => [
        { id: "m1", organizationId: "org-1", status: "active" as const },
      ]),
      buscarOrganizacoes: vi.fn(async () => [{ id: "org-1", name: "Organização A" }]),
    });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    await controlador.entrar("pessoa@example.invalid", "senha-secreta");

    expect(fake.senhasRecebidas).toEqual(["senha-secreta"]);
    expect(ultimo(estados).status).toBe("autenticado");
    expect(JSON.stringify(ultimo(estados))).not.toContain("senha-secreta");
    expect(repositorio.buscarPerfil).toHaveBeenCalledWith("uuid-1");
    expect(repositorio.buscarPerfil).toHaveBeenCalledTimes(1);
  });

  it("credencial inválida rejeita o login com erro público", async () => {
    const fake = criarAutenticadorFalso({
      sessaoInicial: null,
      erroLogin: { code: "invalid_credentials", message: "Invalid login credentials" },
    });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    await expect(controlador.entrar("pessoa@example.invalid", "errada")).rejects.toMatchObject({
      code: "INVALID_CREDENTIALS",
    });
  });

  it("logout encerra a sessão local", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    expect(ultimo(estados).status).toBe("autenticado");

    await controlador.sair();

    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });
    expect(fake.autenticador.sair).toHaveBeenCalledOnce();
  });

  it("auth user sem perfil interno resulta em acesso negado com erro seguro", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const repositorio = repositorioFalso({ buscarPerfil: vi.fn(async () => null) });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    await controlador.entrar("pessoa@example.invalid", "senha-secreta");

    const estado = ultimo(estados);
    expect(estado.status).toBe("acessoNegado");
    if (estado.status === "acessoNegado") {
      expect(estado.erro.code).toBe("FORBIDDEN");
      expect(estado.erro.message).toBe("Você não tem permissão para realizar esta operação.");
    }
  });

  it("usuário com múltiplas memberships não tem seleção arbitrária de organização", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const repositorio = repositorioFalso({
      buscarMembershipsAtivas: vi.fn(async () => [
        { id: "m1", organizationId: "org-1", status: "active" as const },
        { id: "m2", organizationId: "org-2", status: "active" as const },
      ]),
      buscarOrganizacoes: vi.fn(async () => [
        { id: "org-1", name: "Organização A" },
        { id: "org-2", name: "Organização B" },
      ]),
    });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    await controlador.entrar("pessoa@example.invalid", "senha-secreta");

    const estado = ultimo(estados);
    expect(estado.status).toBe("autenticado");
    if (estado.status === "autenticado") {
      expect(estado.identidade.organizacoes.map((o) => o.id)).toEqual(["org-1", "org-2"]);
      expect(estado.identidade.memberships).toHaveLength(2);
    }
  });

  it("mudança de sessão para sem sessão é propagada (logout externo)", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    fake.notificarSessao(null);
    await microtarefas();

    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });
  });

  it("registra uma única assinatura e a remove no dispose", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: () => {},
    });

    await controlador.inicializar();
    expect(fake.autenticador.observarAutenticacao).toHaveBeenCalledTimes(1);

    controlador.dispose();
    expect(fake.unsubscribe).toHaveBeenCalledOnce();
  });
});
