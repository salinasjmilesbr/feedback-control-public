/**
 * F5-10 P5 (Issue #218) — superfície de contrato da Edge Function `metas`.
 *
 * A fonte ÚNICA do contrato é `src/infrastructure/supabase/metas/contrato.ts`,
 * compartilhada entre esta Edge, o adapter de cliente
 * (`src/infrastructure/supabase/metas/edgeMetas.ts`) e os testes — nenhuma
 * cópia de operações, gates, capabilities ou validação de forma existe aqui.
 *
 * Este módulo só reexporta o contrato para que a pasta da Edge exponha a mesma
 * estrutura das demais (`index` / `core` / `contrato`), como em
 * `supabase/functions/ciclos/contrato.ts` (cujo contrato-fonte vive em
 * `src/infrastructure/supabase/ciclos/contrato.ts`).
 */

export * from "../../../src/infrastructure/supabase/metas/contrato.ts";
