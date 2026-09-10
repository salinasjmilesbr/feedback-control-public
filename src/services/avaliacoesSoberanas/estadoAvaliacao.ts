/**
 * F5-06 (Issue #103) — predicados de estado da avaliação (sem dependências).
 *
 * Fonte única da regra de "estado permite mutação normal" (D8): RASCUNHO e
 * PRONTA_PARA_FEEDBACK admitem edição; CONCLUIDA e CANCELADA não. Não é
 * autorização — é estado de domínio declarado pela fronteira confiável e usado
 * pela UI apenas para decidir o que exibir.
 */

import type { AvaliacaoSoberana } from "../../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";

/** Estados que admitem mutação normal (notas/comentários/conclusão). */
export const STATUS_EDITAVEIS = ["RASCUNHO", "PRONTA_PARA_FEEDBACK"] as const;

export function statusEditavel(avaliacao: {
  readonly status: string;
}): boolean {
  return (STATUS_EDITAVEIS as readonly string[]).includes(avaliacao.status);
}

export function statusConcluido(avaliacao: Pick<AvaliacaoSoberana, "status">): boolean {
  return avaliacao.status === "CONCLUIDA";
}

export function statusCancelado(avaliacao: Pick<AvaliacaoSoberana, "status">): boolean {
  return avaliacao.status === "CANCELADA";
}
