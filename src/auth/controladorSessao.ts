import {
  TechnicalError,
  toPublicError,
  type PublicApplicationError,
} from "../errors/applicationErrors";
import type { Autenticador, RepositorioIdentidade } from "./contratos";
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
 *   disponível; não há fabricação de identidade).
 */

export type EstadoSessao =
  | { status: "verificando" }
  | { status: "naoAutenticado" }
  | { status: "autenticado"; sessao: SessaoAuth; identidade: IdentidadeResolvida }
  | { status: "acessoNegado"; erro: PublicApplicationError }
  | { status: "indisponivel" };

export interface ControladorSessao {
  inicializar(): Promise<void>;
  entrar(email: string, senha: string): Promise<UsuarioAuth>;
  sair(): Promise<void>;
  /** F2-07: revalida a sessão vigente no servidor e re-resolve a identidade. */
  revalidar(): Promise<void>;
  dispose(): void;
}

export function criarControladorSessao(deps: {
  autenticador: Autenticador | null;
  repositorio: RepositorioIdentidade | null;
  notificar: (estado: EstadoSessao) => void;
}): ControladorSessao {
  const { autenticador, repositorio, notificar } = deps;

  let geracao = 0;
  let ultimoUserId: string | null = null;
  let cancelarAssinatura: (() => void) | null = null;

  async function resolver(sessao: SessaoAuth, gen: number): Promise<void> {
    if (gen !== geracao) return;
    if (!repositorio) {
      notificar({ status: "acessoNegado", erro: toPublicError(new TechnicalError()) });
      return;
    }

    try {
      const identidade = await resolverIdentidade(sessao.usuario.id, repositorio);
      if (gen !== geracao) return;
      notificar({ status: "autenticado", sessao, identidade });
    } catch (erro) {
      if (gen !== geracao) return;
      notificar({ status: "acessoNegado", erro: toPublicError(erro) });
    }
  }

  async function aplicarSessao(sessao: SessaoAuth | null, gen: number): Promise<void> {
    if (gen !== geracao) return;

    if (!sessao) {
      ultimoUserId = null;
      notificar({ status: "naoAutenticado" });
      return;
    }

    const userId = sessao.usuario.id;
    if (userId === ultimoUserId) return;
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

      cancelarAssinatura = autenticador.observarAutenticacao((sessao) => {
        void aplicarSessao(sessao, gen);
      });

      let sessao: SessaoAuth | null;
      try {
        sessao = await obterSessaoInicial(autenticador);
      } catch (erro) {
        if (gen !== geracao) return;
        notificar({ status: "acessoNegado", erro: toPublicError(erro) });
        return;
      }

      await aplicarSessao(sessao, gen);
    },

    async entrar(email, senha) {
      if (!autenticador) throw new TechnicalError();

      const usuario = await entrarServico(email, senha, autenticador);
      const sessao: SessaoAuth = { usuario };
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
      ultimoUserId = null;
      notificar({ status: "naoAutenticado" });
    },

    async revalidar() {
      if (!autenticador || !repositorio || ultimoUserId === null) return;

      const { data, error } = await autenticador.validarSessaoAtual();
      if (error || !data) {
        ultimoUserId = null;
        notificar({ status: "naoAutenticado" });
        return;
      }

      // Força a re-resolução para refletir o estado vigente (perfil/membership).
      ultimoUserId = data.id;
      await resolver({ usuario: data }, geracao);
    },

    dispose() {
      geracao += 1;
      cancelarAssinatura?.();
      cancelarAssinatura = null;
    },
  };
}
