import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { TechnicalError } from "../errors/applicationErrors";
import { criarAutenticador, criarRepositorioIdentidade } from "./adaptadores";
import { AuthContext } from "./AuthContext";
import { criarClienteAuthSupabase } from "./cliente";
import { criarControladorSessao, type EstadoSessao } from "./controladorSessao";
import {
  redefinirSenha as redefinirSenhaServico,
  solicitarRecuperacaoDeSenha as solicitarRecuperacaoDeSenhaServico,
} from "./servico";

function origemParaRedefinicao(): string {
  if (typeof window === "undefined") return "/redefinir-senha";
  return `${window.location.origin}/redefinir-senha`;
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const cliente = useMemo(() => criarClienteAuthSupabase(), []);
  const [estado, setEstado] = useState<EstadoSessao>({ status: "verificando" });

  const autenticador = useMemo(
    () => (cliente ? criarAutenticador(cliente) : null),
    [cliente]
  );
  const repositorio = useMemo(
    () => (cliente ? criarRepositorioIdentidade(cliente) : null),
    [cliente]
  );

  const controlador = useMemo(
    () => criarControladorSessao({ autenticador, repositorio, notificar: setEstado }),
    [autenticador, repositorio]
  );

  useEffect(() => {
    void controlador.inicializar();
    return () => controlador.dispose();
  }, [controlador]);

  const entrar = useCallback(
    async (email: string, senha: string) => {
      await controlador.entrar(email, senha);
    },
    [controlador]
  );

  const sair = useCallback(async () => {
    await controlador.sair();
  }, [controlador]);

  const solicitarRecuperacaoDeSenha = useCallback(
    async (email: string) => {
      if (!autenticador) throw new TechnicalError();
      await solicitarRecuperacaoDeSenhaServico(
        email,
        origemParaRedefinicao(),
        autenticador
      );
    },
    [autenticador]
  );

  const redefinirSenha = useCallback(
    async (novaSenha: string) => {
      if (!autenticador) throw new TechnicalError();
      await redefinirSenhaServico(novaSenha, autenticador);
    },
    [autenticador]
  );

  return (
    <AuthContext.Provider
      value={{
        estado,
        entrar,
        sair,
        solicitarRecuperacaoDeSenha,
        redefinirSenha,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
