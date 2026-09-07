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
import { mapearErroConvite } from "./conviteAdministrativo";
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

  // F2-07: revalida a sessão vigente periodicamente e ao focar a janela, para
  // detectar desativação/revogação sem esperar a expiração do JWT.
  useEffect(() => {
    if (typeof window === "undefined") return;

    const intervalo = setInterval(() => {
      void controlador.revalidar();
    }, 60_000);

    const aoFocar = () => {
      void controlador.revalidar();
    };
    window.addEventListener("focus", aoFocar);
    document.addEventListener("visibilitychange", aoFocar);

    return () => {
      clearInterval(intervalo);
      window.removeEventListener("focus", aoFocar);
      document.removeEventListener("visibilitychange", aoFocar);
    };
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

  const convidarUsuario = useCallback(
    async (email: string, organizationId: string) => {
      if (!cliente) throw new TechnicalError();
      try {
        const { data, error } = await cliente.functions.invoke("convidar-usuario", {
          body: { email, organization_id: organizationId },
        });
        if (error) throw error;
        if (!data || typeof data.userId !== "string") throw new TechnicalError();
        return { userId: data.userId };
      } catch (erro) {
        throw mapearErroConvite(erro);
      }
    },
    [cliente]
  );

  return (
    <AuthContext.Provider
      value={{
        estado,
        entrar,
        sair,
        solicitarRecuperacaoDeSenha,
        redefinirSenha,
        convidarUsuario,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
