import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  configuracaoAmbiente,
  type ConfiguracaoAmbiente,
} from "../config/ambiente";

/**
 * Cliente Supabase específico de autenticação (F2-03).
 *
 * - Usa o mecanismo oficial de sessão do Supabase Auth: `persistSession` e
 *   `autoRefreshToken` habilitados; `detectSessionInUrl` desabilitado porque não
 *   há fluxo de magic link/confirmação nesta etapa.
 * - Retorna `null` quando a configuração pública (URL + chave anônima) está
 *   ausente, preservando a regra da F0-04/F1-04: nenhuma operação é iniciada e
 *   o estado de autenticação fica "indisponível".
 * - Nenhum signup é exposto por este módulo; o fluxo de login usa somente
 *   `signInWithPassword` via o contrato `Autenticador`.
 */
export function criarClienteAuthSupabase(
  configuracao: ConfiguracaoAmbiente = configuracaoAmbiente
): SupabaseClient | null {
  if (!configuracao.supabaseUrl || !configuracao.supabaseAnonKey) {
    return null;
  }

  return createClient(
    configuracao.supabaseUrl,
    configuracao.supabaseAnonKey,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
      },
    }
  );
}
