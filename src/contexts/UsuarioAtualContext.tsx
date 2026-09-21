import { createContext, useContext } from "react";
import type { Colaborador, IdentidadeColaborador } from "../types/Colaborador";

export type UsuarioAtualContextValue = {
  /** #333: identidade soberana (vínculo). Matrícula é rótulo opcional. */
  usuarioAtual?: IdentidadeColaborador;
  /**
   * Projeção LEGADA da identidade (domínios antigos que ainda exigem matrícula
   * numérica). undefined quando a matrícula não foi informada — nenhum número é
   * inventado. Quem precisa de Colaborador consome este campo.
   */
  usuarioAtualLegado?: Colaborador;
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
