import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { TechnicalError } from "../errors/applicationErrors";
import { criarAutenticador, criarRepositorioIdentidade } from "./adaptadores";
import { criarArmazenamentoInicioSessaoLocal } from "./armazenamentoSessao";
import { AuthContext } from "./AuthContext";
import { criarClienteAuthSupabase } from "./cliente";
import { mapearErroConvite } from "./conviteAdministrativo";
import { criarControladorSessao, type EstadoSessao } from "./controladorSessao";
import { INTERVALO_VERIFICACAO_SESSAO_MS } from "./politicaSessao";
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
  const armazenamentoInicioSessao = useMemo(
    () => criarArmazenamentoInicioSessaoLocal(),
    []
  );

  const controlador = useMemo(
    () =>
      criarControladorSessao({
        autenticador,
        repositorio,
        notificar: setEstado,
        inicioSessao: armazenamentoInicioSessao,
      }),
    [autenticador, repositorio, armazenamentoInicioSessao]
  );

  useEffect(() => {
    void controlador.inicializar();
    return () => controlador.dispose();
  }, [controlador]);

  // F2-07/F2-08: revalida a sessão vigente periodicamente e ao focar a janela —
  // detecta desativação/revogação (F2-07) e aplica os limites de inatividade
  // (60 min) e duração máxima (1 dia) da F2-08 sem esperar a expiração do JWT.
  useEffect(() => {
    if (typeof window === "undefined") return;

    const intervalo = setInterval(() => {
      void controlador.revalidar();
    }, INTERVALO_VERIFICACAO_SESSAO_MS);

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

  // F2-08: atividade real do usuário na janela (teclado, ponteiro, toque,
  // rolagem) reinicia o relógio de inatividade. O foco/visibilidade acima
  // verifica os limites ANTES de registrar atividade — voltar de uma ausência
  // longa não "reanima" uma sessão que já deveria ter expirado.
  useEffect(() => {
    if (typeof window === "undefined") return;

    const aoAtividade = () => controlador.registrarAtividade();
    const eventos = ["keydown", "pointerdown", "pointermove", "wheel", "touchstart"];
    eventos.forEach((evento) =>
      window.addEventListener(evento, aoAtividade, { passive: true })
    );

    return () => {
      eventos.forEach((evento) =>
        window.removeEventListener(evento, aoAtividade)
      );
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

  const reconhecerExpiracao = useCallback(() => {
    controlador.reconhecerExpiracao();
  }, [controlador]);

  const revalidar = useCallback(() => controlador.revalidar(), [controlador]);

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
        reconhecerExpiracao,
        revalidar,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
