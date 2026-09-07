import {
  TechnicalError,
  toPublicError,
  type PublicApplicationError,
} from "../errors/applicationErrors";
import type {
  ArmazenamentoInicioSessao,
} from "./armazenamentoSessao";
import type { Autenticador, RepositorioIdentidade } from "./contratos";
import {
  excedeuDuracaoMaxima,
  motivoDeExpiracao,
  type MotivoExpiracaoSessao,
} from "./politicaSessao";
import {
  entrar as entrarServico,
  obterSessaoInicial,
  resolverIdentidade,
  sair as sairServico,
} from "./servico";
import type {
  IdentidadeResolvida,
  SessaoAuth,
  UsuarioAuth,
} from "./tipos";

/**
 * Máquina de sessão autenticada (F2-03), sem dependência de React.
 *
 * Estados:
 * - `verificando`: bootstrap inicial ainda em andamento;
 * - `naoAutenticado`: sem sessão (login pendente);
 * - `autenticado`: sessão válida + identidade resolvida;
 * - `acessoNegado`: sessão existe, mas o perfil interno não é válido (erro
 *   seguro de acesso) — o usuário deve sair;
 * - `indisponivel`: Supabase não configurado (em DEV a simulação segue
 *   disponível; não há fabricação de identidade);
 * - `sessaoExpirada` (F2-08): a política de sessão encerrou a sessão por
 *   inatividade (60 min) ou duração máxima (1 dia) — o usuário é informado e
 *   precisa autenticar novamente.
 *
 * Política de sessão (F2-08), mantendo o Supabase Auth como gestor da sessão:
 * - o início da sessão deste dispositivo é marcado por usuário em
 *   `ArmazenamentoInicioSessao` (metadado; nunca credencial) e a duração
 *   máxima é aplicada na restauração (refresh/reabertura) e durante o uso;
 * - a inatividade é medida por eventos reais de atividade do usuário
 *   (`registrarAtividade`, disparado pelo `AuthProvider`) e verificada na
 *   mesma cadência da revalidação da F2-07;
 * - ao expirar, o controlador revoga a sessão no Supabase (mesmo `signOut`
 *   global do logout explícito, de forma tolerante a falha de rede) e notifica
 *   `sessaoExpirada` com o motivo; o aviso é reconhecido por
 *   `reconhecerExpiracao()` quando o usuário volta a interagir com o login.
 */

export type EstadoSessao =
  | { status: "verificando" }
  | { status: "naoAutenticado" }
  | { status: "autenticado"; sessao: SessaoAuth; identidade: IdentidadeResolvida }
  | { status: "acessoNegado"; erro: PublicApplicationError }
  | { status: "indisponivel" }
  | { status: "sessaoExpirada"; motivo: MotivoExpiracaoSessao };

export interface ControladorSessao {
  inicializar(): Promise<void>;
  entrar(email: string, senha: string): Promise<UsuarioAuth>;
  sair(): Promise<void>;
  /** F2-07: revalida a sessão vigente no servidor e re-resolve a identidade. */
  revalidar(): Promise<void>;
  /** F2-08: registra atividade real do usuário (reinicia o relógio de inatividade). */
  registrarAtividade(): void;
  /** F2-08: reconhece o aviso de sessão expirada e volta à tela de login comum. */
  reconhecerExpiracao(): void;
  dispose(): void;
}

export interface DependenciasControladorSessao {
  autenticador: Autenticador | null;
  repositorio: RepositorioIdentidade | null;
  notificar: (estado: EstadoSessao) => void;
  /** F2-08: fonte de tempo injetável para testes temporais controlados. */
  relogio?: () => number;
  /** F2-08: marcador persistente do início da sessão por usuário (opcional). */
  inicioSessao?: ArmazenamentoInicioSessao;
}

export function criarControladorSessao(
  deps: DependenciasControladorSessao
): ControladorSessao {
  const { autenticador, repositorio, notificar } = deps;
  const relogio = deps.relogio ?? (() => Date.now());

  let geracao = 0;
  let ultimoUserId: string | null = null;
  let cancelarAssinatura: (() => void) | null = null;

  // F2-08: política de sessão (memória + marcador persistente opcional).
  const marcadores = new Map<string, number>();
  let sessaoOperante = false;
  let ultimaAtividadeMs: number | null = null;
  let expiracaoPendente: MotivoExpiracaoSessao | null = null;

  function agoraMs(): number {
    return relogio();
  }

  function lerMarcador(userId: string): number | null {
    if (deps.inicioSessao) {
      try {
        const guardado = deps.inicioSessao.ler(userId);
        if (typeof guardado === "number" && Number.isFinite(guardado) && guardado > 0) {
          return guardado;
        }
      } catch {
        // armazenamento indisponível: segue pela memória
      }
    }
    const emMemoria = marcadores.get(userId);
    return typeof emMemoria === "number" ? emMemoria : null;
  }

  function gravarMarcador(userId: string, inicioMs: number): void {
    marcadores.set(userId, inicioMs);
    try {
      deps.inicioSessao?.definir(userId, inicioMs);
    } catch {
      // sem persistência: a política segue em memória nesta sessão de app
    }
  }

  function removerMarcador(userId: string | null): void {
    if (!userId) return;
    marcadores.delete(userId);
    try {
      deps.inicioSessao?.remover(userId);
    } catch {
      // sem persistência: apenas a memória é limpa
    }
  }

  /**
   * Abre a janela da política para uma sessão efetiva de `userId`. Na
   * restauração (`reiniciar === false`) preserva o marcador original — a
   * duração máxima é medida desde o início real da sessão; em um novo
   * login/recuperação (`reiniciar === true`) a janela recomeça.
   */
  function iniciarVigenciaSessao(userId: string, reiniciar: boolean): void {
    let inicio: number | null = null;
    if (!reiniciar) {
      inicio = lerMarcador(userId);
    }
    if (inicio === null) {
      inicio = agoraMs();
      gravarMarcador(userId, inicio);
    }
    ultimaAtividadeMs = agoraMs();
    expiracaoPendente = null;
  }

  function encerrarVigenciaSessao(userId: string | null): void {
    removerMarcador(userId);
    ultimaAtividadeMs = null;
  }

  /**
   * Aplica os limites da F2-08 apenas sobre sessões efetivamente operantes
   * (`autenticado`). Estados de acesso negado não usam a aplicação e seguem
   * dependendo da revalidação F2-07/RLS.
   */
  function verificarLimitesDeSessao(): MotivoExpiracaoSessao | null {
    if (!sessaoOperante || ultimoUserId === null) return null;
    return motivoDeExpiracao(lerMarcador(ultimoUserId), ultimaAtividadeMs, agoraMs());
  }

  /**
   * Encerra a sessão por política (F2-08). Revoga no Supabase com o mesmo
   * `signOut` global do logout explícito, mas de forma tolerante: mesmo que a
   * revogação remota falhe (offline), o estado local cai para `sessaoExpirada`.
   * `userId` explícito cobre expirações decididas antes de `ultimoUserId` ser
   * atribuído (ex.: restauração com idade acima do limite).
   */
  async function expirarSessao(
    motivo: MotivoExpiracaoSessao,
    userId: string | null = ultimoUserId
  ): Promise<void> {
    encerrarVigenciaSessao(userId);
    ultimoUserId = null;
    sessaoOperante = false;
    expiracaoPendente = motivo;
    notificar({ status: "sessaoExpirada", motivo });

    if (autenticador) {
      try {
        await sairServico(autenticador);
      } catch {
        // best-effort: a sessão local já foi encerrada
      }
    }
  }

  async function resolver(sessao: SessaoAuth, gen: number): Promise<void> {
    if (gen !== geracao) return;
    if (!repositorio) {
      notificar({ status: "acessoNegado", erro: toPublicError(new TechnicalError()) });
      return;
    }

    try {
      const identidade = await resolverIdentidade(sessao.usuario.id, repositorio);
      if (gen !== geracao) return;
      if (!sessaoOperante) {
        // Transição para sessão operante (login/restauração/retomada): a
        // presença atual do usuário conta como atividade a partir de agora.
        ultimaAtividadeMs = agoraMs();
      }
      sessaoOperante = true;
      notificar({ status: "autenticado", sessao, identidade });
    } catch (erro) {
      if (gen !== geracao) return;
      sessaoOperante = false;
      notificar({ status: "acessoNegado", erro: toPublicError(erro) });
    }
  }

  async function aplicarSessao(
    evento: "inicial" | "entrou" | "saiu" | "tokenAtualizado" | "outro",
    sessao: SessaoAuth | null,
    gen: number
  ): Promise<void> {
    if (gen !== geracao) return;

    if (!sessao) {
      // Enquanto o aviso de expiração está pendente, ignora o SIGNED_OUT do
      // signOut assíncrono da própria política (não sobrescreve o motivo).
      if (expiracaoPendente) return;
      encerrarVigenciaSessao(ultimoUserId);
      ultimoUserId = null;
      sessaoOperante = false;
      notificar({ status: "naoAutenticado" });
      return;
    }

    const userId = sessao.usuario.id;
    if (userId === ultimoUserId) return;

    // Enquanto o aviso de expiração está pendente, apenas um novo sign-in
    // explícito ("entrou") pode reabrir a janela da política — restaurações
    // duplicadas ("inicial") não recriam o marcador sem nova autenticação.
    if (expiracaoPendente && evento !== "entrou") return;

    if (evento === "inicial") {
      // Restauração (refresh/reabertura): preserva o marcador e não restaura
      // sessões com mais de 1 dia — a sessão persistida não contorna o limite.
      const guardado = lerMarcador(userId);
      if (guardado !== null && excedeuDuracaoMaxima(guardado, agoraMs())) {
        void expirarSessao("duracaoMaxima", userId);
        return;
      }
      iniciarVigenciaSessao(userId, false);
    } else {
      // Novo sign-in (login, recuperação) ou evento de outra natureza: a
      // janela da política recomeça agora.
      iniciarVigenciaSessao(userId, true);
    }

    ultimoUserId = userId;
    await resolver(sessao, gen);
  }

  return {
    async inicializar() {
      const gen = ++geracao;

      if (!autenticador) {
        notificar({ status: "indisponivel" });
        return;
      }

      cancelarAssinatura = autenticador.observarAutenticacao((evento, sessao) => {
        void aplicarSessao(evento, sessao, gen);
      });

      let sessao: SessaoAuth | null;
      try {
        sessao = await obterSessaoInicial(autenticador);
      } catch (erro) {
        if (gen !== geracao) return;
        notificar({ status: "acessoNegado", erro: toPublicError(erro) });
        return;
      }

      await aplicarSessao("inicial", sessao, gen);
    },

    async entrar(email, senha) {
      if (!autenticador) throw new TechnicalError();

      const usuario = await entrarServico(email, senha, autenticador);
      const sessao: SessaoAuth = { usuario };
      iniciarVigenciaSessao(usuario.id, true);
      ultimoUserId = usuario.id;

      await resolver(sessao, geracao);
      return usuario;
    },

    async sair() {
      if (!autenticador) {
        notificar({ status: "indisponivel" });
        return;
      }

      await sairServico(autenticador);
      encerrarVigenciaSessao(ultimoUserId);
      ultimoUserId = null;
      sessaoOperante = false;
      expiracaoPendente = null;
      notificar({ status: "naoAutenticado" });
    },

    async revalidar() {
      if (!autenticador || !repositorio || ultimoUserId === null) return;

      // F2-08: limites de inatividade/duração máxima têm prioridade — evita a
      // chamada ao servidor quando a política já exige nova autenticação.
      const motivo = verificarLimitesDeSessao();
      if (motivo) {
        await expirarSessao(motivo);
        return;
      }

      const { data, error } = await autenticador.validarSessaoAtual();
      if (error || !data) {
        encerrarVigenciaSessao(ultimoUserId);
        ultimoUserId = null;
        sessaoOperante = false;
        notificar({ status: "naoAutenticado" });
        return;
      }

      // Força a re-resolução para refletir o estado vigente (perfil/membership).
      ultimoUserId = data.id;
      await resolver({ usuario: data }, geracao);
    },

    registrarAtividade() {
      if (!sessaoOperante || ultimoUserId === null || expiracaoPendente) return;
      ultimaAtividadeMs = agoraMs();
    },

    reconhecerExpiracao() {
      if (expiracaoPendente === null) return;
      expiracaoPendente = null;
      notificar({ status: "naoAutenticado" });
    },

    dispose() {
      geracao += 1;
      cancelarAssinatura?.();
      cancelarAssinatura = null;
    },
  };
}
