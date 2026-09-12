/**
 * Cliente Supabase encapsulado na fronteira de infraestrutura (F1-04).
 *
 * - Cria o cliente oficial apenas quando a configuração pública (URL + chave
 *   anônima) está presente; caso contrário retorna `null`, preservando o
 *   funcionamento atual do frontend sem Supabase (decisão F0-04).
 * - Consome exclusivamente `configuracaoAmbiente` (única leitora de VITE_*):
 *   `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY`. Ambas são públicas por
 *   definição; nenhuma credencial privilegiada ou segredo server-side é aceito
 *   (a chave `service_role` NUNCA entra no bundle).
 * - **F5-08 P4 — cliente do caminho soberano com a SESSÃO do usuário.** O
 *   contrato do desenho técnico exige que o navegador chegue ao PostgREST com o
 *   JWT do usuário (RLS F4-08/D16) e à Edge `colaboradores` com o MESMO JWT
 *   (§12.1); sem sessão o SDK cairia para a chave anônima e as leituras
 *   devolveriam conjuntos vazios (negação SILENCIOSA pela RLS). Por isso:
 *   `persistSession: true` faz este cliente LER a sessão já persistida pelo
 *   cliente de auth (`src/auth/cliente.ts`) — fonte única de sessão.
 * - `autoRefreshToken: false` e `detectSessionInUrl: false`: a renovação do
 *   token e o processamento de sessão na URL pertencem EXCLUSIVAMENTE ao cliente
 *   de auth (F2-03/F2-05). Este módulo não autentica, não renova, não grava e
 *   não emite sessão — evita um segundo ticker de refresh concorrente sobre a
 *   mesma sessão e mantém uma única fonte de verdade.
 * - A ausência de sessão é FAIL-CLOSED no caminho soberano: quem consome este
 *   cliente verifica a sessão antes de ler/escrever e recusa a operação com
 *   código público quando ela não existe (nunca "lista vazia" por negação).
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import {
  configuracaoAmbiente,
  type ConfiguracaoAmbiente,
} from "../../config/ambiente";

const opcoesTecnicas = {
  auth: {
    persistSession: true,
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

/** Opções efetivas do cliente soberano (expostas para teste/auditoria). */
export const OPCOES_CLIENTE_SOBERANO = opcoesTecnicas;
