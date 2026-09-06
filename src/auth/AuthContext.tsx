import { createContext, useContext } from "react";
import type { EstadoSessao } from "./controladorSessao";

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
};

export const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function useAuth() {
  const contexto = useContext(AuthContext);

  if (!contexto) {
    throw new Error("useAuth deve ser usado dentro de AuthProvider.");
  }

  return contexto;
}
