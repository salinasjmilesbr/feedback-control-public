import type { SupabaseClient } from "@supabase/supabase-js";
import { criarClienteSupabase } from "../infrastructure/supabase/supabaseClient";

/**
 * #327/P2B — PROJEÇÃO MÍNIMA de autorização estrutural para a UI (menu/rotas).
 *
 * Lê a view `estrutura_autorizacao` (P1): uma linha por membership ATIVA do
 * PRÓPRIO ator, com `pode_estrutura` (`org.structure.manage`) e `pode_catalogo`
 * (`org.catalog.manage`) já decididos SERVER-SIDE.
 *
 * Isto é PROJEÇÃO, nunca autorização: quem entrega os dados é
 * `estrutura_administrativa`/`estrutura_pessoal`, e uma URL direta continua
 * dependendo da view (zero linha ⇒ `FORBIDDEN`). Ausência de linha, erro de
 * leitura ou cliente indisponível ⇒ NENHUMA capability (fail-closed: o menu não
 * mostra, e o servidor nega de qualquer forma).
 */

export interface AutorizacaoEstruturalSoberana {
  readonly podeEstrutura: boolean;
  readonly podeCatalogo: boolean;
}

/** Sem autorização estrutural: estado inicial e todo caminho fail-closed. */
export const SEM_AUTORIZACAO_ESTRUTURAL: AutorizacaoEstruturalSoberana = {
  podeEstrutura: false,
  podeCatalogo: false,
};

export async function lerAutorizacaoEstrutural(
  organizationId: string | null | undefined,
  cliente: SupabaseClient | null = criarClienteSupabase()
): Promise<AutorizacaoEstruturalSoberana> {
  if (!cliente || !organizationId) return SEM_AUTORIZACAO_ESTRUTURAL;

  const { data, error } = await cliente
    .from("estrutura_autorizacao")
    .select("organization_id, pode_estrutura, pode_catalogo")
    .eq("organization_id", organizationId)
    .maybeSingle();

  if (error || !data) return SEM_AUTORIZACAO_ESTRUTURAL;

  return {
    podeEstrutura: data.pode_estrutura === true,
    podeCatalogo: data.pode_catalogo === true,
  };
}
