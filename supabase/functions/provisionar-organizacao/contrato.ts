/**
 * F6-A03 (Issue #266) — superfície de contrato da Edge Function
 * `provisionar-organizacao`.
 *
 * A fonte ÚNICA do contrato é `src/infrastructure/supabase/plataforma/contrato.ts`,
 * compartilhada entre esta Edge, o adapter de cliente
 * (`src/infrastructure/supabase/plataforma/edgePlataforma.ts`) e os testes —
 * nenhuma cópia de operações, allowlist de chaves ou validação de forma existe
 * aqui.
 *
 * Este módulo só reexporta o contrato para que a pasta da Edge exponha a mesma
 * estrutura das demais (`index` / `core` / `contrato`), como em
 * `supabase/functions/metas/contrato.ts` e
 * `supabase/functions/observacoes/contrato.ts`.
 */

export * from "../../../src/infrastructure/supabase/plataforma/contrato.ts";
