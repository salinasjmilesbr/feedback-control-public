/**
 * F5-10 P6 (Issue #220) — PORTA ÚNICA de acesso soberano ao domínio de METAS.
 *
 * Nenhuma página/componente deve compor o cliente Supabase, a Edge `metas` ou o
 * repositório por conta própria: a composição vive aqui, espelhando
 * `acessoCiclosSoberanos.ts` (F5-09) e `acessoColaboradoresSoberanos.ts` (F5-07).
 *
 * Contrato desta porta:
 * - entrega o `GoalRepository` (porta da aplicação) ligado à Edge `metas`;
 * - é **FAIL-CLOSED**: sem configuração de ambiente não há caminho soberano e a
 *   função devolve `null` — as páginas DEVEM tratar isso como indisponibilidade
 *   explícita. Nunca há fallback para `localStorage`/`metaStorage`, nem leitura
 *   direta de tabela (`.from("evaluation_goal…")`) e nem RPC `meta_*` no cliente:
 *   a autoridade é sempre server-side (Edge + Policy Engine + RPC soberana).
 * - NÃO decide autorização, tenant, ciclo ou identidade: `organizationId` e
 *   `cycleId` são INTENÇÃO de UX (UUIDs soberanos) e a fronteira os revalida.
 * - `operationId` continua sendo chave de IDEMPOTÊNCIA (nunca identidade): quem
 *   gera é a tentativa lógica do fluxo, não este módulo.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";
import { criarEdgeMetas } from "../infrastructure/supabase/metas/edgeMetas";
import { criarRepositorioMetasSoberanas } from "../infrastructure/supabase/metas/repositorioMetasSoberanas";
import type { GoalRepository } from "../application/ports/GoalRepository";

export type { GoalRepository };

export interface DependenciasAcessoMetas {
  /** Injeção do repositório (testes). Por padrão usa o caminho de produção. */
  readonly repositorio?: GoalRepository;
  /** Cliente Supabase explícito (testes); `null` força "sem caminho soberano". */
  readonly cliente?: SupabaseClient | null;
}

/**
 * Instância resolvida uma única vez por sessão de página. `undefined` = ainda não
 * resolvido; `null` = ambiente sem caminho soberano (fail-closed).
 */
let repositorioMemoizado: GoalRepository | null | undefined;

/** Somente para testes: descarta a memoização do caminho soberano. */
export function redefinirAcessoMetasSoberanas(): void {
  repositorioMemoizado = undefined;
}

/**
 * Devolve o repositório soberano de metas, ou `null` quando o ambiente não
 * oferece o caminho novo (fail-closed — nenhum fallback local é oferecido).
 */
export function obterRepositorioMetasSoberanas(
  deps: DependenciasAcessoMetas = {}
): GoalRepository | null {
  if (deps.repositorio) return deps.repositorio;
  if (repositorioMemoizado !== undefined) return repositorioMemoizado;

  const cliente = deps.cliente !== undefined ? deps.cliente : criarClienteSupabase();
  repositorioMemoizado = cliente
    ? criarRepositorioMetasSoberanas(criarEdgeMetas(cliente))
    : null;
  return repositorioMemoizado;
}
