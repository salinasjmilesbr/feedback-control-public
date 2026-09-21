/**
 * F6-A03 (Issue #266) — GUARD da rota de PLATAFORMA (D19).
 *
 * Módulo PURO (sem React, sem autorização): decide apenas se a rota de
 * plataforma pode ser RENDERIZADA, exatamente como `src/auth/rotasProtegidas.ts`
 * faz para as rotas funcionais. Um guard de rota é controle de UX — a decisão
 * real é sempre server-side (Edge + RPC soberana).
 *
 * POR QUE ESTE GUARD NÃO É O `LayoutAutenticado` (D19/§3 B5): o plano de
 * PLATAFORMA não pode depender da resolução de identidade de TENANT. No ambiente
 * virgem o operador não está em `autenticado` — sem perfil interno o estado é
 * `acessoNegado` e, com perfil e sem membership, `semOrganizacao`; e o shell
 * funcional ainda tentaria carregar a estrutura soberana de um tenant que ainda
 * não existe. Por isso a rota admite esses estados e NÃO monta
 * `AuthorizationContext` nem lê estrutura de tenant.
 *
 * Fail-closed: `sessaoIndisponivel` e `indisponivel` BLOQUEIAM (nada de fallback
 * simulado); ausência de sessão/expirada redireciona ao login.
 */
import type { EstadoSessao } from "../auth/controladorSessao";

/** Rota única da superfície mínima de plataforma (§6.5.4). */
export const ROTA_PLATAFORMA_NOVA_ORGANIZACAO = "/plataforma/nova-organizacao";

export type DecisaoRotaPlataforma =
  | { tipo: "carregando" }
  | { tipo: "permitir" }
  | { tipo: "bloquear" }
  | { tipo: "redirecionarLogin" };

export function decidirAcessoARotaDePlataforma(estado: EstadoSessao): DecisaoRotaPlataforma {
  switch (estado.status) {
    case "verificando":
      return { tipo: "carregando" };

    // Sessão viva com identidade de TENANT resolvida (ou não).
    case "autenticado":
    case "semOrganizacao":
    case "aguardandoSelecao":
      return { tipo: "permitir" };

    case "primeiroAcessoPendente":
      return { tipo: "bloquear" };

    // Exceção DELIBERADA (D19): a ausência de identidade de tenant é exatamente
    // a condição que a superfície de plataforma existe para resolver. A decisão
    // efetiva continua server-side e fail-closed.
    case "acessoNegado":
      return { tipo: "permitir" };

    case "naoAutenticado":
    case "sessaoExpirada":
      return { tipo: "redirecionarLogin" };

    // Revalidação não confirmada ou ambiente sem autenticação configurada:
    // bloqueio fail-closed, sem fallback simulado.
    case "sessaoIndisponivel":
    case "indisponivel":
      return { tipo: "bloquear" };
  }
}
