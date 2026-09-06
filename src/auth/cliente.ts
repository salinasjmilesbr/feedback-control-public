import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  configuracaoAmbiente,
  type ConfiguracaoAmbiente,
} from "../config/ambiente";

/**
 * Cliente Supabase específico de autenticação (F2-03/F2-05).
 *
 * - Usa o mecanismo oficial de sessão do Supabase Auth: `persistSession` e
 *   `autoRefreshToken` habilitados; `detectSessionInUrl` habilitado a partir da
 *   F2-05 para que o link de recuperação de senha (implicit flow, tokens no
 *   hash) seja processado pelo SDK — sem parsing manual de token.
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
        detectSessionInUrl: true,
      },
    }
  );
}
