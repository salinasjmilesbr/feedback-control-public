/**
 * F5-09 P7 (Issue #202) — superfície de contrato da Edge Function `ciclos`.
 *
 * A fonte ÚNICA do contrato é `src/infrastructure/supabase/ciclos/contrato.ts`,
 * compartilhada entre esta Edge, o adapter de cliente
 * (`src/infrastructure/supabase/ciclos/edgeCiclos.ts`) e os testes — nenhuma
 * cópia de operações, gates, capabilities ou validação de forma existe aqui.
 *
 * Este módulo só reexporta o contrato para que a pasta da Edge exponha a mesma
 * estrutura das demais (`index` / `core` / `contrato`), como na Edge `avaliacoes`
 * (cujo contrato vive em `src/infrastructure/supabase/avaliacoes/contrato.ts`).
 */

export * from "../../../src/infrastructure/supabase/ciclos/contrato.ts";
