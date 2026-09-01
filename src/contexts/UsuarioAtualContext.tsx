import { createContext, useContext } from "react";
import type { Colaborador } from "../types/Colaborador";

export type UsuarioAtualContextValue = {
  usuarioAtual?: Colaborador;
  usuariosDisponiveis: Colaborador[];
  selecionarUsuario: (matricula: number) => void;
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
