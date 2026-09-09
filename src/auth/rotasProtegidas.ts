import type { EstadoSessao } from "./controladorSessao";

/**
 * Decisão de acesso às rotas funcionais (F2-04), centralizada em um único
 * ponto. O route guard é controle de UX/acesso do frontend — o backend/RLS
 * continua sendo a fronteira real de segurança.
 *
 * - `carregando`: bootstrap/restauração em andamento — nada de conteúdo
 *   protegido é renderizado (sem flicker);
 * - `permitir`: sessão real autenticada, ou DEV com simulação preservada
 *   (Supabase ausente e ambiente de desenvolvimento);
 * - `semOrganizacao` (F5-01/Q2 aprovada): autenticado sem membership ativa —
 *   área funcional bloqueada com tela dedicada (não é login nem conteúdo);
 * - `aguardandoSelecao` (F5-01/Q4 aprovada): autenticado com N>1 memberships —
 *   nenhuma escolha silenciosa; área funcional bloqueada até a seleção (F5-03);
 * - `indisponivelTemporaria` (F5-01/Q1 aprovada): revalidação não confirmada
 *   por falha transitória — a sessão local é preservada, mas a área funcional
 *   permanece bloqueada (fail-closed);
 * - `redirecionarLogin`: usuário sem sessão, sessão expirada (F2-08), acesso
 *   negado ou HOMOLOG/PROD sem autenticação configurada (falha segura, sem
 *   fallback simulado).
 */
export type DecisaoRotaFuncional =
  | { tipo: "carregando" }
  | { tipo: "permitir" }
  | { tipo: "semOrganizacao" }
  | { tipo: "aguardandoSelecao" }
  | { tipo: "indisponivelTemporaria" }
  | { tipo: "redirecionarLogin" };

export function decidirAcessoARotasFuncionais(
  estado: EstadoSessao,
  simulacaoDevPermitida: boolean,
  organizacaoAtivaId: string | null = null
): DecisaoRotaFuncional {
  switch (estado.status) {
    case "verificando":
      return { tipo: "carregando" };

    case "autenticado":
      return { tipo: "permitir" };

    case "semOrganizacao":
      return { tipo: "semOrganizacao" };

    case "aguardandoSelecao":
      // F5-03: com N>1, a área funcional só é liberada quando há uma organização
      // selecionada válida (organizacaoAtivaId); sem seleção, bloqueia.
      return organizacaoAtivaId ? { tipo: "permitir" } : { tipo: "aguardandoSelecao" };

    case "sessaoIndisponivel":
      return { tipo: "indisponivelTemporaria" };

    case "indisponivel":
      // Só o contexto DEV com a simulação preservada mantém o acesso sem auth
      // real; em HOMOLOG/PROD a ausência de configuração falha de forma segura
      // e não permite identidade simulada.
      return simulacaoDevPermitida
        ? { tipo: "permitir" }
        : { tipo: "redirecionarLogin" };

    case "naoAutenticado":
    case "acessoNegado":
    case "sessaoExpirada":
      return { tipo: "redirecionarLogin" };
  }
}
