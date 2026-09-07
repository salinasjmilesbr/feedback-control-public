import { useMemo, useState, type ReactNode } from "react";
import { simulacaoDevPermitida } from "../config/ambiente";
import { getColaboradores } from "../services/colaboradorStorage";
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
export function UsuarioAtualProvider({
  children,
  simulacaoDev = simulacaoDevPermitida,
}: {
  children: ReactNode;
  /** F2-09: permite injetar o gate nos testes; em runtime usa a config central. */
  simulacaoDev?: boolean;
}) {
  const usuariosDisponiveis = useMemo(
    () => candidatosImpersonacaoDev(simulacaoDev, getColaboradores()),
    [simulacaoDev]
  );

  const [matriculaAtual, setMatriculaAtual] = useState<number | undefined>(() => {
    if (!simulacaoDev) return undefined;
    const salva = Number(localStorage.getItem(CHAVE_USUARIO_ATUAL_DEV) ?? "");
    return resolverMatriculaInicialDev(
      Number.isFinite(salva) ? salva : undefined,
      usuariosDisponiveis
    );
  });

  const usuarioAtual = usuariosDisponiveis.find(
    (usuario) => usuario.matricula === matriculaAtual
  );

  function selecionarUsuario(matricula: number) {
    const proxima = selecionarMatriculaDev(simulacaoDev, matricula);
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
        simulacaoDevAtiva: simulacaoDev,
      }}
    >
      {children}
    </UsuarioAtualContext.Provider>
  );
}
