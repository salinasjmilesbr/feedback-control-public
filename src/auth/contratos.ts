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

export interface Autenticador {
  entrarComSenha(email: string, senha: string): Promise<ResultadoAuth<UsuarioAuth>>;
  sair(): Promise<ResultadoAuth<null>>;
  obterSessao(): Promise<ResultadoAuth<SessaoAuth>>;
  /**
   * Registra um observador de mudanças de sessão e retorna a função de
   * cancelamento. A implementação deve garantir uma única assinatura por
   * chamada e permitir `unsubscribe` sem efeitos colaterais.
   */
  observarAutenticacao(aoMudar: (sessao: SessaoAuth | null) => void): () => void;
}

export interface RepositorioIdentidade {
  buscarPerfil(authUserId: string): Promise<PerfilAutenticado | null>;
  buscarMembershipsAtivas(authUserId: string): Promise<MembershipAutenticada[]>;
  buscarOrganizacoes(ids: string[]): Promise<OrganizacaoResolvida[]>;
}
