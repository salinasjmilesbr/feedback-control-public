/**
 * F6 — AÇÃO soberana da avaliação do colaborador no ciclo ativo.
 *
 * Traduz o payload MÍNIMO da descoberta (`evaluationId`, `status`, `podeEditar`
 * ou somente `existeSemAcesso`)
 * em rótulo + destino com UUID. Este módulo NÃO reconstrói autorização:
 *
 * - `podeEditar` vem decidido SERVER-SIDE pelo ramo `evaluation.write`
 *   (ocorrência materializada vigente + scope). A UI nunca recalcula
 *   scopes/relações para decidir edição;
 * - `CREATE` sobre avaliação existente revela somente a existência; o estado
 *   neutro não possui destino nem oferece consulta;
 * - `null` (sem ação) é o resultado fail-closed para erro/DENY.
 *
 * Nada aqui usa `localStorage`, matrícula ou API legada: os destinos são as
 * rotas UUID já existentes (`/colaborador/:collaboratorId/avaliacoes/...`).
 */

import type { DescobertaAvaliacaoDoColaborador } from "../infrastructure/supabase/avaliacoes/contrato.ts";

export interface AcaoAvaliacaoDoColaborador {
  readonly label: string;
  /** Rótulo estável para teste/telemetria (sem texto humano). */
  readonly tipo: "NOVA" | "EDITAR" | "CONSULTAR" | "EXISTENTE_SEM_ACESSO";
  readonly destino?: string;
}

/**
 * Decide a ação da ficha. `descoberta === null` (erro/DENY/indeterminação) ⇒
 * nenhuma ação — jamais cai para o acervo legado.
 */
export function acaoDaAvaliacaoDoColaborador(
  colaboradorId: string,
  descoberta: DescobertaAvaliacaoDoColaborador | null
): AcaoAvaliacaoDoColaborador | null {
  if (!descoberta) return null;

  if (descoberta.existeSemAcesso === true) {
    return { label: "Já existe avaliação neste ciclo", tipo: "EXISTENTE_SEM_ACESSO" };
  }

  if (descoberta.evaluationId === undefined || descoberta.status === undefined) return null;

  const base = `/colaborador/${colaboradorId}/avaliacoes`;

  // Nenhuma avaliação NÃO CANCELADA: o servidor só devolve isto a quem pode
  // CRIAR (CANCELADA equivale a ausência para esse ator).
  if (!descoberta.evaluationId) {
    if (descoberta.status !== null || descoberta.podeEditar) return null;
    return { label: "Nova avaliação", tipo: "NOVA", destino: `${base}/nova` };
  }

  if (descoberta.podeEditar) {
    return {
      label: "Editar avaliação",
      tipo: "EDITAR",
      destino: `${base}/${descoberta.evaluationId}/editar`,
    };
  }

  // Sem escrita: leitura autorizada (o servidor só devolve dados com conteúdo
  // acessível). Concluída e rascunho somente-leitura são consulta.
  return {
    label: "Consultar avaliação",
    tipo: "CONSULTAR",
    destino: `${base}/${descoberta.evaluationId}`,
  };
}
