/**
 * F5-06 (Issue #103) — montagem do repositório do caminho novo em produção.
 *
 * O repositório Supabase só existe quando há configuração de ambiente
 * (`VITE_SUPABASE_URL` + chave anon, validadas em `src/config/ambiente`). Sem
 * configuração devolve `null` — fail-closed: o caminho novo simplesmente não é
 * oferecido, e NADA cai de volta para o `localStorage` como autoridade.
 *
 * A chave `service_role` nunca entra no bundle (o app é anon-only); toda a
 * execução privilegiada acontece na Edge Function.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { ConfiguracaoAmbiente } from "../../../config/ambiente.ts";
import { criarClienteSupabase } from "../supabaseClient.ts";
import {
  criarRepositorioAvaliacoesSupabase,
  type RepositorioAvaliacoes,
} from "./repositorioAvaliacoes.ts";

export interface DependenciasRepositorioProducao {
  /** Injeção do cliente (teste) — por padrão usa o cliente do ambiente. */
  readonly criarCliente?: (configuracao?: ConfiguracaoAmbiente) => SupabaseClient | null;
  readonly configuracao?: ConfiguracaoAmbiente;
}

/**
 * Devolve o repositório de avaliações do caminho novo, ou `null` quando o
 * ambiente não está configurado (fail-closed, sem fallback para o legado).
 */
export function criarRepositorioAvaliacoesProducao(
  deps: DependenciasRepositorioProducao = {}
): RepositorioAvaliacoes | null {
  const criarCliente = deps.criarCliente ?? criarClienteSupabase;
  const cliente = criarCliente(deps.configuracao);
  if (!cliente) return null;
  return criarRepositorioAvaliacoesSupabase(cliente);
}
