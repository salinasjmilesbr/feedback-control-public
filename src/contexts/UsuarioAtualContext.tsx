import { createContext, useContext } from "react";
import type { Colaborador } from "../types/Colaborador";

export type UsuarioAtualContextValue = {
  usuarioAtual?: Colaborador;
  usuariosDisponiveis: Colaborador[];
  selecionarUsuario: (matricula: number) => void;
  /**
   * F2-09: `true` quando este contexto representa a impersonação DEV (somente
   * DEV explícito). Fora de DEV não há colaborador sintético carregado, a
   * troca é bloqueada e o seletor não é exibido. Nunca é autenticação real.
   */
  simulacaoDevAtiva?: boolean;
};

export const UsuarioAtualContext = createContext<UsuarioAtualContextValue | undefined>(
  undefined
);

export function useUsuarioAtual() {
  const contexto = useContext(UsuarioAtualContext);

  if (!contexto) {
    throw new Error(
      "useUsuarioAtual deve ser usado dentro de UsuarioAtualProvider."
    );
  }

  return contexto;
}
