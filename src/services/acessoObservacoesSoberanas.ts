/**
 * F5-11 P5 (Issue #250) — PORTA ÚNICA de acesso soberano ao domínio de
 * OBSERVAÇÕES.
 *
 * Nenhuma página/componente deve compor o cliente Supabase, a Edge `observacoes`
 * ou o repositório por conta própria: a composição vive aqui, espelhando
 * `acessoMetasSoberanas.ts` (F5-10 P6) e `acessoColaboradoresSoberanos.ts`
 * (F5-07).
 *
 * Contrato desta porta:
 * - entrega o `ObservationRepository` (porta da aplicação, L1) ligado à Edge
 *   `observacoes` pelo adapter da P4 — leitura INCLUSIVE (D22);
 * - é **FAIL-CLOSED**: sem configuração de ambiente não há caminho soberano e a
 *   função devolve `null` — as páginas DEVEM tratar isso como indisponibilidade
 *   explícita. Nunca há fallback para o acervo do navegador, nem dual-read, nem
 *   leitura direta de tabela ou RPC `observacao_*` no cliente: a autoridade é
 *   sempre server-side (Edge + Policy Engine + RPC soberana);
 * - NÃO decide autorização, tenant nem identidade: `organizationId` e o ESCOPO
 *   de leitura são INTENÇÃO de UX (UUIDs/escopo revalidados na fronteira) e o
 *   alvo das observações é o `collaborator_id` soberano — nunca matrícula, nome,
 *   cargo ou ano/ciclo;
 * - NÃO gera identidade: o `id` da observação é o UUID da linha, atribuído pelo
 *   banco. Nada aqui fabrica UUID nem persiste no navegador.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";
import { criarEdgeObservacoes } from "../infrastructure/supabase/observacoes/edgeObservacoes";
import { criarRepositorioObservacoesSoberanas } from "../infrastructure/supabase/observacoes/repositorioObservacoesSoberanas";
import type { ObservationRepository } from "../application/ports/ObservationRepository";

export type { ObservationRepository };

export interface DependenciasAcessoObservacoes {
  /** Injeção do repositório (teste). Por padrão usa o caminho de produção. */
  readonly repositorio?: ObservationRepository;
  /** Cliente Supabase explícito (teste); `null` força "sem caminho soberano". */
  readonly cliente?: SupabaseClient | null;
}

/**
 * Instância resolvida uma única vez por sessão de página. `undefined` = ainda
 * não resolvido; `null` = ambiente sem caminho soberano (fail-closed).
 */
let repositorioMemoizado: ObservationRepository | null | undefined;

/** Somente para testes: descarta a memoização do caminho soberano. */
export function redefinirAcessoObservacoesSoberanas(): void {
  repositorioMemoizado = undefined;
}

/**
 * Devolve o repositório soberano de observações, ou `null` quando o ambiente não
 * oferece o caminho novo (fail-closed — nenhum fallback local é oferecido).
 */
export function obterRepositorioObservacoesSoberanas(
  deps: DependenciasAcessoObservacoes = {}
): ObservationRepository | null {
  if (deps.repositorio) return deps.repositorio;
  if (repositorioMemoizado !== undefined) return repositorioMemoizado;

  const cliente = deps.cliente !== undefined ? deps.cliente : criarClienteSupabase();
  repositorioMemoizado = cliente
    ? criarRepositorioObservacoesSoberanas(criarEdgeObservacoes(cliente))
    : null;
  return repositorioMemoizado;
}
