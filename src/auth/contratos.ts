import type {
  MembershipAutenticada,
  OrganizacaoResolvida,
  PerfilAutenticado,
  SessaoAuth,
  UsuarioAuth,
} from "./tipos";

/**
 * Contratos de infraestrutura para autenticação/identidade (F2-03).
 *
 * A camada de serviço depende apenas destas interfaces, o que permite testar o
 * fluxo sem rede e sem Supabase real. O adaptador concreto vive em
 * `adaptadores.ts` sobre `@supabase/supabase-js`.
 */

export interface ResultadoAuth<T> {
  data: T | null;
  error: unknown | null;
}

/**
 * Classificação da mudança de sessão observada (F2-08), derivada dos eventos
 * do Supabase Auth. Permite à máquina de sessão distinguir uma restauração
 * (INITIAL_SESSION — deve preservar o marcador de início e aplicar a duração
 * máxima) de um novo login/recuperação (SIGNED_IN/PASSWORD_RECOVERY — reinicia
 * a janela da política), sem depender de nomes internos do SDK.
 */
export type EventoMudancaSessao =
  | "inicial"
  | "entrou"
  | "saiu"
  | "tokenAtualizado"
  | "outro";

export interface Autenticador {
  entrarComSenha(email: string, senha: string): Promise<ResultadoAuth<UsuarioAuth>>;
  sair(): Promise<ResultadoAuth<null>>;
  obterSessao(): Promise<ResultadoAuth<SessaoAuth>>;
  /**
   * Registra um observador de mudanças de sessão e retorna a função de
   * cancelamento. A implementação deve garantir uma única assinatura por
   * chamada e permitir `unsubscribe` sem efeitos colaterais. O primeiro
   * argumento classifica o evento (F2-08) para as decisões de política.
   */
  observarAutenticacao(
    aoMudar: (evento: EventoMudancaSessao, sessao: SessaoAuth | null) => void
  ): () => void;
  /**
   * Revalida a sessão corrente no servidor (`auth.getUser`). Usado na F2-07
   * para detectar revogação/banimento sem depender da expiração do JWT.
   */
  validarSessaoAtual(): Promise<ResultadoAuth<UsuarioAuth>>;
  /**
   * Solicita a recuperação de senha (F2-05). O resultado NÃO deve ser usado
   * para revelar se o e-mail possui conta: a camada de serviço ignora `error`.
   */
  solicitarRecuperacaoDeSenha(email: string, redirectTo: string): Promise<ResultadoAuth<null>>;
  /** Define a nova senha na sessão de recuperação corrente (`updateUser`). */
  definirNovaSenha(senha: string): Promise<ResultadoAuth<null>>;
}

export interface RepositorioIdentidade {
  buscarPerfil(authUserId: string): Promise<PerfilAutenticado | null>;
  buscarMembershipsAtivas(authUserId: string): Promise<MembershipAutenticada[]>;
  buscarOrganizacoes(ids: string[]): Promise<OrganizacaoResolvida[]>;
}
