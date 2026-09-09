import { describe, expect, it, vi } from "vitest";
import type { ArmazenamentoInicioSessao } from "./armazenamentoSessao";
import type { Autenticador, EventoMudancaSessao, RepositorioIdentidade } from "./contratos";
import { criarControladorSessao, type EstadoSessao } from "./controladorSessao";
import {
  DURACAO_MAXIMA_SESSAO_MS,
  LIMITE_INATIVIDADE_MS,
} from "./politicaSessao";

type SessaoObservada = { usuario: { id: string; email?: string | null } } | null;

interface AutenticadorFalso {
  autenticador: Autenticador;
  unsubscribe: ReturnType<typeof vi.fn>;
  notificarSessao: (evento: EventoMudancaSessao, sessao: SessaoObservada) => void;
  senhasRecebidas: string[];
}

function criarAutenticadorFalso(opcoes: {
  sessaoInicial?: { id: string; email?: string } | null;
  usuarioLogin?: { id: string; email?: string } | null;
  erroLogin?: unknown | null;
} = {}): AutenticadorFalso {
  const unsubscribe = vi.fn();
  let aoMudar: ((evento: EventoMudancaSessao, sessao: SessaoObservada) => void) | null = null;
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
    validarSessaoAtual: vi.fn(async () => ({
      data: { id: "uuid-1", email: "pessoa@example.invalid" },
      error: null,
    })),
    solicitarRecuperacaoDeSenha: vi.fn(async () => ({ data: null, error: null })),
    definirNovaSenha: vi.fn(async () => ({ data: null, error: null })),
  };

  return {
    autenticador,
    unsubscribe,
    notificarSessao: (evento, sessao) => aoMudar?.(evento, sessao),
    senhasRecebidas,
  };
}

function repositorioFalso(parcial: Partial<RepositorioIdentidade> = {}): RepositorioIdentidade {
  return {
    buscarPerfil: vi.fn(async () => ({ id: "uuid-1", status: "active" as const })),
    buscarMembershipsAtivas: vi.fn(async () => [
      { id: "m1", organizationId: "org-1", status: "active" as const },
    ]),
    buscarOrganizacoes: vi.fn(async () => [{ id: "org-1", name: "Organização A" }]),
    ...parcial,
  };
}

/** Relógio controlado para testes temporais da F2-08. */
function relogioControlado(inicial = 1_700_000_000_000) {
  let agora = inicial;
  return {
    relogio: () => agora,
    avancar(ms: number): void {
      agora += ms;
    },
  };
}

/** Marcador de início de sessão em memória, com spies para asserções. */
function marcadoresFalso(iniciais: Record<string, number> = {}) {
  const valores = new Map<string, number>(Object.entries(iniciais));
  const ler = vi.fn((userId: string) => valores.get(userId) ?? null);
  const definir = vi.fn((userId: string, inicioMs: number) => {
    valores.set(userId, inicioMs);
  });
  const remover = vi.fn((userId: string) => {
    valores.delete(userId);
  });
  return { ler, definir, remover, valores } satisfies ArmazenamentoInicioSessao & {
    valores: Map<string, number>;
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
    // F5-01 (Q2): sem membership ativa, o bootstrap resolve a identidade e
    // entra no estado dedicado `semOrganizacao`.
    const repositorio = repositorioFalso({
      buscarMembershipsAtivas: vi.fn(async () => []),
      buscarOrganizacoes: vi.fn(async () => []),
    });
    const estados: EstadoSessao[] = [];

    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();

    expect(ultimo(estados)).toEqual({
      status: "semOrganizacao",
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
      expect(estado.erro.code).toBe("ACCESS_NOT_PROVISIONED");
      expect(estado.erro.message).toBe(
        "Seu acesso ainda não foi liberado. Fale com o administrador."
      );
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
    expect(estado.status).toBe("aguardandoSelecao");
    if (estado.status === "aguardandoSelecao") {
      // N>1: nenhuma organização é escolhida silenciosamente — ambas são
      // preservadas, aguardando seleção explícita (F5-03).
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
    fake.notificarSessao("saiu", null);
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

describe("revalidação de sessão (F2-07)", () => {
  it("revalida e re-resolve a identidade para uma sessão ainda válida", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const repositorio = repositorioFalso();
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    await controlador.revalidar();

    expect(fake.autenticador.validarSessaoAtual).toHaveBeenCalled();
    expect(ultimo(estados).status).toBe("autenticado");
  });

  it("sessão revogada no servidor derruba o usuário para não autenticado", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    vi.mocked(fake.autenticador.validarSessaoAtual).mockResolvedValue({
      data: null,
      error: { status: 401 },
    });

    await controlador.revalidar();

    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });
  });

  it("perfil que passou a disabled na revalidação vira acesso negado", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const repositorio = repositorioFalso();
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    vi.mocked(repositorio.buscarPerfil).mockResolvedValueOnce(null);

    await controlador.revalidar();

    const estado = ultimo(estados);
    expect(estado.status).toBe("acessoNegado");
  });

  it("não revalida quando não há sessão (sem chamada ao servidor)", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: () => {},
    });

    await controlador.inicializar();
    await controlador.revalidar();

    expect(fake.autenticador.validarSessaoAtual).not.toHaveBeenCalled();
  });
});

describe("política de sessão (F2-08)", () => {
  it("sessão persistida com mais de 1 dia não é restaurada no bootstrap", async () => {
    const tempo = relogioControlado();
    const marcador = marcadoresFalso({
      "uuid-1": tempo.relogio() - DURACAO_MAXIMA_SESSAO_MS - 1,
    });
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const repositorio = repositorioFalso();
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();

    expect(ultimo(estados)).toEqual({ status: "sessaoExpirada", motivo: "duracaoMaxima" });
    // Nenhuma resolução de identidade acontece para uma sessão já vencida.
    expect(repositorio.buscarPerfil).not.toHaveBeenCalled();
    await microtarefas();
    // Revogação global (mesmo signOut do logout explícito), best-effort.
    expect(fake.autenticador.sair).toHaveBeenCalled();
    expect(marcador.valores.has("uuid-1")).toBe(false);
  });

  it("restauração dentro do prazo preserva o marcador original e autentica", async () => {
    const tempo = relogioControlado();
    const inicioOriginal = tempo.relogio() - 10 * 60 * 60 * 1000;
    const marcador = marcadoresFalso({ "uuid-1": inicioOriginal });
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();

    expect(ultimo(estados).status).toBe("autenticado");
    expect(marcador.definir).not.toHaveBeenCalled();
    expect(marcador.valores.get("uuid-1")).toBe(inicioOriginal);
  });

  it("novo login reinicia a janela mesmo com marcador antigo no dispositivo", async () => {
    const tempo = relogioControlado();
    const marcador = marcadoresFalso({
      "uuid-1": tempo.relogio() - DURACAO_MAXIMA_SESSAO_MS - 60_000,
    });
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();
    await controlador.entrar("pessoa@example.invalid", "senha-secreta");

    expect(ultimo(estados).status).toBe("autenticado");
    expect(marcador.definir).toHaveBeenCalledWith("uuid-1", tempo.relogio());
  });

  it("inatividade acima de 60 minutos exige nova autenticação (sem chamar o servidor)", async () => {
    const tempo = relogioControlado();
    const marcador = marcadoresFalso();
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();
    expect(ultimo(estados).status).toBe("autenticado");

    tempo.avancar(LIMITE_INATIVIDADE_MS);
    await controlador.revalidar();

    expect(ultimo(estados)).toEqual({ status: "sessaoExpirada", motivo: "inatividade" });
    expect(fake.autenticador.validarSessaoAtual).not.toHaveBeenCalled();
    await microtarefas();
    expect(fake.autenticador.sair).toHaveBeenCalled();
  });

  it("atividade recente dentro da janela preserva a sessão autenticada", async () => {
    const tempo = relogioControlado();
    const marcador = marcadoresFalso();
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();

    tempo.avancar(50 * 60 * 1000);
    controlador.registrarAtividade();
    tempo.avancar(50 * 60 * 1000);

    await controlador.revalidar();

    expect(fake.autenticador.validarSessaoAtual).toHaveBeenCalled();
    expect(ultimo(estados).status).toBe("autenticado");
  });

  it("sessão operante que ultrapassa 1 dia expira por duração máxima", async () => {
    const tempo = relogioControlado();
    const marcador = marcadoresFalso();
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();

    tempo.avancar(DURACAO_MAXIMA_SESSAO_MS);
    controlador.registrarAtividade();
    await controlador.revalidar();

    expect(ultimo(estados)).toEqual({ status: "sessaoExpirada", motivo: "duracaoMaxima" });
    expect(fake.autenticador.validarSessaoAtual).not.toHaveBeenCalled();
  });

  it("logout explícito remove o marcador de início de sessão", async () => {
    const tempo = relogioControlado();
    const marcador = marcadoresFalso();
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();
    await controlador.sair();

    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });
    expect(marcador.remover).toHaveBeenCalledWith("uuid-1");
    expect(marcador.valores.has("uuid-1")).toBe(false);
  });

  it("aviso de expiração não é sobrescrito por eventos de sessão e é reconhecido no login", async () => {
    const tempo = relogioControlado();
    const marcador = marcadoresFalso();
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();
    tempo.avancar(LIMITE_INATIVIDADE_MS);
    await controlador.revalidar();
    expect(ultimo(estados)).toEqual({ status: "sessaoExpirada", motivo: "inatividade" });

    // SIGNED_OUT do signOut assíncrono da própria política não sobrescreve o aviso.
    fake.notificarSessao("saiu", null);
    await microtarefas();
    expect(ultimo(estados)).toEqual({ status: "sessaoExpirada", motivo: "inatividade" });

    // Restauração duplicada ("inicial") também não recria o marcador sem novo login.
    fake.notificarSessao("inicial", { usuario: { id: "uuid-1" } });
    await microtarefas();
    expect(ultimo(estados)).toEqual({ status: "sessaoExpirada", motivo: "inatividade" });

    controlador.reconhecerExpiracao();
    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });

    // Reconhecer novamente é inócuo.
    controlador.reconhecerExpiracao();
    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });
  });

  it("evento de novo sign-in via assinatura inicia a janela da política", async () => {
    const tempo = relogioControlado();
    const marcador = marcadoresFalso();
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
      relogio: tempo.relogio,
      inicioSessao: marcador,
    });

    await controlador.inicializar();
    fake.notificarSessao("entrou", { usuario: { id: "uuid-1" } });
    await microtarefas();

    expect(ultimo(estados).status).toBe("autenticado");
    expect(marcador.definir).toHaveBeenCalledWith("uuid-1", tempo.relogio());
  });
});

describe("estado semOrganizacao (F5-01, Q2 aprovada)", () => {
  it("perfil ativo sem membership ativa entra em semOrganizacao", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: null });
    const repositorio = repositorioFalso({
      buscarMembershipsAtivas: vi.fn(async () => []),
      buscarOrganizacoes: vi.fn(async () => []),
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
    expect(estado.status).toBe("semOrganizacao");
    if (estado.status === "semOrganizacao") {
      expect(estado.identidade.memberships).toEqual([]);
      expect(estado.identidade.organizacoes).toEqual([]);
    }
  });

  it("revalidação que resolve para zero memberships transita para semOrganizacao", async () => {
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const repositorio = repositorioFalso();
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio,
      notificar: (estado) => estados.push(estado),
    });

    await controlador.inicializar();
    expect(ultimo(estados).status).toBe("autenticado");

    vi.mocked(repositorio.buscarMembershipsAtivas).mockResolvedValue([]);
    await controlador.revalidar();

    expect(ultimo(estados).status).toBe("semOrganizacao");
  });
});

describe("revalidação × falha transitória (F5-01, Q1 aprovada)", () => {
  function montar() {
    const fake = criarAutenticadorFalso({ sessaoInicial: { id: "uuid-1" } });
    const estados: EstadoSessao[] = [];
    const controlador = criarControladorSessao({
      autenticador: fake.autenticador,
      repositorio: repositorioFalso(),
      notificar: (estado) => estados.push(estado),
    });
    return { fake, estados, controlador };
  }

  it("falha transitória de transporte (sem status) preserva a sessão e bloqueia (sessaoIndisponivel)", async () => {
    const { fake, estados, controlador } = montar();
    await controlador.inicializar();
    expect(ultimo(estados).status).toBe("autenticado");

    vi.mocked(fake.autenticador.validarSessaoAtual).mockResolvedValue({
      data: null,
      error: new TypeError("fetch failed"),
    });
    await controlador.revalidar();

    expect(ultimo(estados).status).toBe("sessaoIndisponivel");
    expect(fake.autenticador.sair).not.toHaveBeenCalled();
  });

  it("falha 5xx preserva a sessão e bloqueia (sem logout automático)", async () => {
    const { fake, estados, controlador } = montar();
    await controlador.inicializar();
    vi.mocked(fake.autenticador.validarSessaoAtual).mockResolvedValue({
      data: null,
      error: { status: 503 },
    });
    await controlador.revalidar();

    expect(ultimo(estados).status).toBe("sessaoIndisponivel");
    expect(fake.autenticador.sair).not.toHaveBeenCalled();
  });

  it("após revalidação bem-sucedida, o acesso retorna (sai de sessaoIndisponivel)", async () => {
    const { fake, estados, controlador } = montar();
    await controlador.inicializar();
    expect(ultimo(estados).status).toBe("autenticado");

    vi.mocked(fake.autenticador.validarSessaoAtual).mockResolvedValueOnce({
      data: null,
      error: new TypeError("fetch failed"),
    });
    await controlador.revalidar();
    expect(ultimo(estados).status).toBe("sessaoIndisponivel");

    await controlador.revalidar();
    expect(ultimo(estados).status).toBe("autenticado");
  });

  it("sessão revogada (401) encerra o acesso", async () => {
    const { fake, estados, controlador } = montar();
    await controlador.inicializar();
    vi.mocked(fake.autenticador.validarSessaoAtual).mockResolvedValue({
      data: null,
      error: { status: 401 },
    });
    await controlador.revalidar();

    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });
  });

  it("usuário banido/removido (403) encerra o acesso", async () => {
    const { fake, estados, controlador } = montar();
    await controlador.inicializar();
    vi.mocked(fake.autenticador.validarSessaoAtual).mockResolvedValue({
      data: null,
      error: { status: 403 },
    });
    await controlador.revalidar();

    expect(ultimo(estados)).toEqual({ status: "naoAutenticado" });
  });
});
