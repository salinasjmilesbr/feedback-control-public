import {
  createContext,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { getColaboradores } from "../services/colaboradorStorage";
import type { Colaborador } from "../types/Colaborador";

const STORAGE_KEY = "feedback-control-usuario-atual";

type UsuarioAtualContextValue = {
  usuarioAtual?: Colaborador;
  usuariosDisponiveis: Colaborador[];
  selecionarUsuario: (matricula: number) => void;
};

const UsuarioAtualContext = createContext<UsuarioAtualContextValue | undefined>(
  undefined
);

function obterMatriculaInicial(usuarios: Colaborador[]): number | undefined {
  const matriculaSalva = Number(localStorage.getItem(STORAGE_KEY));

  if (
    Number.isFinite(matriculaSalva) &&
    usuarios.some((usuario) => usuario.matricula === matriculaSalva)
  ) {
    return matriculaSalva;
  }

  return (
    usuarios.find(
      (usuario) =>
        usuario.status === "ATIVO" && usuario.funcao === "GERENTE"
    )?.matricula ?? usuarios[0]?.matricula
  );
}

export function UsuarioAtualProvider({ children }: { children: ReactNode }) {
  const usuariosDisponiveis = useMemo(
    () =>
      getColaboradores()
        .filter(
          (usuario) =>
            usuario.status === "ATIVO" &&
            (usuario.funcao === "GERENTE" ||
              usuario.funcao === "COORDENADOR")
        )
        .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR")),
    []
  );

  const [matriculaAtual, setMatriculaAtual] = useState<number | undefined>(() =>
    obterMatriculaInicial(usuariosDisponiveis)
  );

  const usuarioAtual = usuariosDisponiveis.find(
    (usuario) => usuario.matricula === matriculaAtual
  );

  function selecionarUsuario(matricula: number) {
    setMatriculaAtual(matricula);
    localStorage.setItem(STORAGE_KEY, String(matricula));
  }

  return (
    <UsuarioAtualContext.Provider
      value={{ usuarioAtual, usuariosDisponiveis, selecionarUsuario }}
    >
      {children}
    </UsuarioAtualContext.Provider>
  );
}

export function useUsuarioAtual() {
  const contexto = useContext(UsuarioAtualContext);

  if (!contexto) {
    throw new Error(
      "useUsuarioAtual deve ser usado dentro de UsuarioAtualProvider."
    );
  }

  return contexto;
}
