/**
 * F5-11 P4 (Issue #248) — superfície de contrato da Edge Function `observacoes`.
 *
 * A fonte ÚNICA do contrato é `src/infrastructure/supabase/observacoes/contrato.ts`,
 * compartilhada entre esta Edge, o adapter de cliente
 * (`src/infrastructure/supabase/observacoes/edgeObservacoes.ts`) e os testes —
 * nenhuma cópia de operações, gates, capabilities, mapa de RPC ou validação de
 * forma existe aqui.
 *
 * Este módulo só reexporta o contrato para que a pasta da Edge exponha a mesma
 * estrutura das demais (`index` / `core` / `contrato`), como em
 * `supabase/functions/metas/contrato.ts` (cujo contrato-fonte vive em
 * `src/infrastructure/supabase/metas/contrato.ts`).
 */

export * from "../../../src/infrastructure/supabase/observacoes/contrato.ts";
