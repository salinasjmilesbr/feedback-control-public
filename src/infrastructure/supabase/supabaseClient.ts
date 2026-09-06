/**
 * Cliente Supabase encapsulado na fronteira de infraestrutura (F1-04).
 *
 * - Cria o cliente oficial apenas quando a configuração pública (URL + chave
 *   anônima) está presente; caso contrário retorna `null`, preservando o
 *   funcionamento atual do frontend sem Supabase (decisão F0-04).
 * - Consome exclusivamente `configuracaoAmbiente` (única leitora de VITE_*):
 *   `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY`. Ambas são públicas por
 *   definição; nenhuma credencial privilegiada ou segredo server-side é aceita.
 * - Auth fica desativado no cliente: nenhum fluxo de autenticação, sessão,
 *   refresh ou leitura de URL é iniciado aqui (Auth pertence a fases futuras).
 * - Nenhum fluxo funcional importa este módulo nesta fase; o localStorage
 *   permanece a persistência funcional ativa.
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  configuracaoAmbiente,
  type ConfiguracaoAmbiente,
} from "../../config/ambiente";

const opcoesTecnicas = {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
} as const;

export function criarClienteSupabase(
  configuracao: ConfiguracaoAmbiente = configuracaoAmbiente
): SupabaseClient | null {
  if (!configuracao.supabaseUrl || !configuracao.supabaseAnonKey) {
    return null;
  }
  return createClient(configuracao.supabaseUrl, configuracao.supabaseAnonKey, opcoesTecnicas);
}
