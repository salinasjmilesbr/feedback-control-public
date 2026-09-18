import { useEffect, useMemo, useState, type ReactNode } from "react";
import { simulacaoDevPermitida } from "../config/ambiente";
import { listarColaboradores, type ColaboradorSoberano } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import { getColaboradores } from "../services/colaboradorStorage";
import type { Colaborador } from "../types/Colaborador";
import { UsuarioAtualContext } from "./UsuarioAtualContext";
import {
  candidatosImpersonacaoDev,
  CHAVE_USUARIO_ATUAL_DEV,
  resolverMatriculaInicialDev,
  selecionarMatriculaDev,
} from "./impersonacaoDev";

/**
 * Contexto de impersonação de desenvolvimento (F2-09).
 *
 * Este provider NÃO representa autenticação: ele mantém o contexto local de
 * qual colaborador sintético a aplicação está "vendo" durante o
 * desenvolvimento (funcionalidades simuladas sobre o seed sintético do
 * localStorage). O Supabase Auth permanece soberano e separado — nada aqui
 * altera `auth.uid()`, JWT, sessão do Supabase nem participa de chamadas
 * server-side como autorização.
 *
 * Fora de DEV explícito (`simulacaoDev`/`simulacaoDevPermitida` === false):
 * - nenhum colaborador sintético é carregado como identidade;
 * - o marcador local de identidade não é lido nem escrito;
 * - a troca de identidade é bloqueada (fail-closed) — HOMOLOG/PROD não expõem
 *   o seletor nem aceitam impersonação local.
 */
function mapearColaboradorSoberanoParaApresentacao(
  colaborador: ColaboradorSoberano
): Colaborador {
  const matricula = Number(colaborador.matricula);
  if (!Number.isSafeInteger(matricula)) {
    throw new Error("Colaborador soberano sem matricula numerica para apresentacao.");
  }
  return {
    matricula,
    status: colaborador.status === "active" ? "ATIVO" : colaborador.status === "leave" ? "LICENCA" : "DESLIGADO",
    nome: colaborador.fullName,
    email: colaborador.email,
    cargo: colaborador.jobRoleName ?? "",
    area: colaborador.unitName ?? "",
    respondePara: colaborador.managerFullName ?? "",
    dataAdmissao: colaborador.admissionDate ?? undefined,
  };
}

export function UsuarioAtualProvider({
  children,
  simulacaoDev = simulacaoDevPermitida,
  organizacaoAtivaId = null,
  usuarioAutenticadoEmail = null,
}: {
  children: ReactNode;
  /** F2-09: permite injetar o gate nos testes; em runtime usa a config central. */
  simulacaoDev?: boolean;
  /** Tenant autenticado ativo; impede contaminar sua apresentação com fixture global. */
  organizacaoAtivaId?: string | null;
  usuarioAutenticadoEmail?: string | null;
}) {
  const simulacaoDevDaSessao = simulacaoDev && !organizacaoAtivaId;
  const usuariosDev = useMemo(
    () =>
      simulacaoDevDaSessao
        ? candidatosImpersonacaoDev(true, getColaboradores())
        : [],
    [simulacaoDevDaSessao]
  );
  const [leituraSoberana, setLeituraSoberana] = useState<{
    chave: string;
    usuarios: Colaborador[];
  } | null>(null);
  const chaveSoberana = `${organizacaoAtivaId ?? "sem-organizacao"}|${usuarioAutenticadoEmail ?? "sem-usuario"}`;

  useEffect(() => {
    if (!organizacaoAtivaId || !usuarioAutenticadoEmail) {
      return;
    }
    let vigente = true;
    void listarColaboradores({ organizationId: organizacaoAtivaId }).then((resultado) => {
      if (!vigente) return;
      setLeituraSoberana({
        chave: chaveSoberana,
        usuarios:
        resultado.ok
          ? resultado.dados
              .filter((item) => item.email.toLowerCase() === usuarioAutenticadoEmail.toLowerCase())
              .map(mapearColaboradorSoberanoParaApresentacao)
          : [],
      });
    });
    return () => { vigente = false; };
  }, [chaveSoberana, organizacaoAtivaId, usuarioAutenticadoEmail]);

  const usuariosSoberanos =
    leituraSoberana?.chave === chaveSoberana ? leituraSoberana.usuarios : [];
  const usuariosDisponiveis = organizacaoAtivaId ? usuariosSoberanos : usuariosDev;

  const [matriculaAtual, setMatriculaAtual] = useState<number | undefined>(() => {
    if (!simulacaoDevDaSessao) return undefined;
    const salva = Number(localStorage.getItem(CHAVE_USUARIO_ATUAL_DEV) ?? "");
    return resolverMatriculaInicialDev(
      Number.isFinite(salva) ? salva : undefined,
      usuariosDev
    );
  });

  const usuarioAtual = organizacaoAtivaId
    ? usuariosSoberanos[0]
    : usuariosDisponiveis.find((usuario) => usuario.matricula === matriculaAtual);

  function selecionarUsuario(matricula: number) {
    const proxima = selecionarMatriculaDev(simulacaoDevDaSessao, matricula);
    if (proxima === undefined) return;
    setMatriculaAtual(proxima);
    localStorage.setItem(CHAVE_USUARIO_ATUAL_DEV, String(proxima));
  }

  return (
    <UsuarioAtualContext.Provider
      value={{
        usuarioAtual,
        usuariosDisponiveis,
        selecionarUsuario,
        simulacaoDevAtiva: simulacaoDevDaSessao,
      }}
    >
      {children}
    </UsuarioAtualContext.Provider>
  );
}
