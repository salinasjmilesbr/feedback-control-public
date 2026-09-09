import { createContext, useContext } from "react";
import type { EstadoSessao } from "./controladorSessao";
import type { OrganizacaoResolvida } from "./tipos";

export type AuthContextValue = {
  estado: EstadoSessao;
  entrar: (email: string, senha: string) => Promise<void>;
  sair: () => Promise<void>;
  /** F2-05: solicita recuperação (nunca revela se o e-mail existe). */
  solicitarRecuperacaoDeSenha: (email: string) => Promise<void>;
  /** F2-05: define a nova senha na sessão de recuperação corrente. */
  redefinirSenha: (novaSenha: string) => Promise<void>;
  /** F2-06: convida um usuário por e-mail via Edge Function (server-side). */
  convidarUsuario: (email: string, organizationId: string) => Promise<{ userId: string }>;
  /** F2-08: reconhece o aviso de sessão expirada e volta à tela de login comum. */
  reconhecerExpiracao: () => void;
  /** F5-01 (Q1): reintenta a revalidação da sessão (ex.: tela de indisponibilidade). */
  revalidar: () => Promise<void>;
  /** F5-03: organização efetiva atual (implícita se N=1; selecionada se N>1; null se nenhuma). */
  organizacaoAtivaId: string | null;
  /** F5-03: organizações disponíveis (memberships ativas) — lista soberana (snapshot). */
  organizacoesDisponiveis: OrganizacaoResolvida[];
  /** F5-03: seleciona a organização (intenção de UX); no-op se inválida. */
  selecionarOrganizacao: (organizationId: string) => void;
  /** F5-03: versão de troca de organização (sinal de invalidação de caches por tenant). */
  organizacaoVersao: number;
};

export const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function useAuth() {
  const contexto = useContext(AuthContext);

  if (!contexto) {
    throw new Error("useAuth deve ser usado dentro de AuthProvider.");
  }

  return contexto;
}
