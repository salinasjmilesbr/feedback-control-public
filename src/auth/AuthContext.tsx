import { createContext, useContext } from "react";
import type { EstadoSessao } from "./controladorSessao";

export type AuthContextValue = {
  estado: EstadoSessao;
  entrar: (email: string, senha: string) => Promise<void>;
  sair: () => Promise<void>;
};

export const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function useAuth() {
  const contexto = useContext(AuthContext);

  if (!contexto) {
    throw new Error("useAuth deve ser usado dentro de AuthProvider.");
  }

  return contexto;
}
