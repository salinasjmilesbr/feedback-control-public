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
        .filter((usuario) => usuario.status === "ATIVO")
        .sort((a, b) => {
          const ordemFuncao = (usuario: Colaborador): number => {
            if (usuario.funcao === "GERENTE") return 0;
            if (usuario.funcao === "COORDENADOR") return 1;
            if (usuario.funcao === "CONSULTOR") return 2;
            if (
              usuario.funcao === "ANALISTA" &&
              usuario.senioridade === "SENIOR"
            ) {
              return 3;
            }
            if (
              usuario.funcao === "ANALISTA" &&
              usuario.senioridade === "PLENO"
            ) {
              return 4;
            }
            if (
              usuario.funcao === "ANALISTA" &&
              usuario.senioridade === "JUNIOR"
            ) {
              return 5;
            }
            if (usuario.funcao === "ANALISTA") return 6;
            if (usuario.funcao === "ESTAGIARIO") return 7;
            return 8;
          };

          const ordemA = ordemFuncao(a);
          const ordemB = ordemFuncao(b);

          if (ordemA !== ordemB) return ordemA - ordemB;

          return a.nome.localeCompare(b.nome, "pt-BR");
        }),
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
