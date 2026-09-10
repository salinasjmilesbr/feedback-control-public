/**
 * F5-06 (Issue #103) — STATUS REAL da avaliação no caminho novo.
 *
 * Leitura de status pelo service soberano (PostgreSQL), com precedência
 * explícita sobre qualquer projeção legada:
 *
 *   status do banco (avaliação vinculada ao PostgreSQL)
 *     > projeção legada (somente leitura, registros anteriores ao cutover)
 *
 * Nenhuma autorização é decidida aqui: a leitura passa pela Edge Function e,
 * portanto, pelo Policy Engine. Quando não há caminho novo configurado, a
 * função devolve `null` em vez de inventar um estado a partir do legado.
 */

import type { AvaliacaoSoberana } from "../../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";
import { mensagemErroAvaliacoes, type ServiceAvaliacoes } from "./serviceAvaliacoes.ts";
import { statusEditavel } from "./estadoAvaliacao.ts";

export interface StatusAvaliacaoSoberana {
  readonly evaluationId: string;
  readonly status: string;
  readonly origem: "POSTGRES";
  /** Somente RASCUNHO/PRONTA_PARA_FEEDBACK admitem mutação normal (D8). */
  readonly editavel: boolean;
  readonly encerradaComPendencias: boolean;
  readonly notaMedia: number | null;
}

export type ResultadoStatusAvaliacao =
  | { readonly ok: true; readonly status: StatusAvaliacaoSoberana | null }
  | { readonly ok: false; readonly erro: string };

export function projetarStatus(avaliacao: AvaliacaoSoberana): StatusAvaliacaoSoberana {
  return {
    evaluationId: avaliacao.id,
    status: avaliacao.status,
    origem: "POSTGRES",
    editavel: statusEditavel(avaliacao),
    encerradaComPendencias: avaliacao.encerradaComPendencias,
    notaMedia: avaliacao.notaMedia,
  };
}

/**
 * Busca o status real de uma avaliação. `null` = inexistente para o ator
 * (cross-tenant/IDOR e inexistência são indistinguíveis de propósito, para não
 * vazar a existência de recurso alheio).
 */
export async function obterStatusAvaliacao(
  service: ServiceAvaliacoes<unknown>,
  entrada: { readonly organizationId: string; readonly evaluationId: string }
): Promise<ResultadoStatusAvaliacao> {
  const resultado = await service.ler({
    organizationId: entrada.organizationId,
    evaluationId: entrada.evaluationId,
  });
  if (!resultado.ok) {
    return { ok: false, erro: mensagemErroAvaliacoes(resultado.error) };
  }
  return { ok: true, status: resultado.data ? projetarStatus(resultado.data) : null };
}

/**
 * O ciclo pode ser encerrado quando NENHUMA avaliação nova admite mutação
 * normal. Lista vazia ⇒ `false` (não há o que encerrar) — nunca assume estado
 * por omissão.
 */
export function cicloEncerravel(status: readonly StatusAvaliacaoSoberana[]): boolean {
  if (status.length === 0) return false;
  return status.every((item) => !item.editavel);
}

/** Reexporta o predicado único de estado (evita duas regras divergentes). */
export { statusEditavel };
