import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { criarAutenticador, criarRepositorioIdentidade } from "./adaptadores";
import { AuthContext } from "./AuthContext";
import { criarClienteAuthSupabase } from "./cliente";
import { criarControladorSessao, type EstadoSessao } from "./controladorSessao";

export function AuthProvider({ children }: { children: ReactNode }) {
  const cliente = useMemo(() => criarClienteAuthSupabase(), []);
  const [estado, setEstado] = useState<EstadoSessao>({ status: "verificando" });

  const controlador = useMemo(() => {
    const autenticador = cliente ? criarAutenticador(cliente) : null;
    const repositorio = cliente ? criarRepositorioIdentidade(cliente) : null;
    return criarControladorSessao({ autenticador, repositorio, notificar: setEstado });
  }, [cliente]);

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

  return (
    <AuthContext.Provider value={{ estado, entrar, sair }}>
      {children}
    </AuthContext.Provider>
  );
}
