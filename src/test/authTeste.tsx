/**
 * F5-06 (Issue #103) — provedor de autenticação para testes de tela.
 *
 * As telas de avaliação passaram a ler a organização ativa do contexto de
 * autenticação para enviá-la como INTENÇÃO à fronteira confiável (a autoridade
 * continua server-side). Testes de render que não exercitam a sessão real usam
 * este provedor com uma organização FICTÍCIA — nenhum dado real participa.
 */

import type { ReactNode } from "react";
import { AuthContext, type AuthContextValue } from "../auth/AuthContext";
import type { EstadoSessao } from "../auth/controladorSessao";

/** Organização sintética usada apenas em testes. */
export const ORGANIZACAO_TESTE = "11111111-1111-4111-8111-111111111111";

const ESTADO_NAO_AUTENTICADO: EstadoSessao = { status: "naoAutenticado" };

const CONTEXTO_TESTE: AuthContextValue = {
  estado: ESTADO_NAO_AUTENTICADO,
  entrar: async () => undefined,
  sair: async () => undefined,
  solicitarRecuperacaoDeSenha: async () => undefined,
  redefinirSenha: async () => undefined,
  convidarUsuario: async () => ({ userId: "perfil-ficticio" }),
  reconhecerExpiracao: () => undefined,
  revalidar: async () => undefined,
  organizacaoAtivaId: ORGANIZACAO_TESTE,
  organizacoesDisponiveis: [],
  selecionarOrganizacao: () => undefined,
  organizacaoVersao: 0,
};

export function ProvedorAuthTeste({ children }: { children: ReactNode }) {
  return (
    <AuthContext.Provider value={CONTEXTO_TESTE}>
      {children}
    </AuthContext.Provider>
  );
}

