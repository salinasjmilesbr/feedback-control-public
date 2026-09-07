-- ============================================================================
-- F3-01 (Issue #78): habilitar extensão btree_gist (migration dedicada)
-- ----------------------------------------------------------------------------
-- Propósito: habilitar a extensão `btree_gist` do PostgreSQL para permitir
-- exclusion constraints com comparação de igualdade sobre colunas escalares
-- (uuid) combinada com operadores de intervalo temporal (`&&`), utilizadas
-- pelas tabelas de lifecycle da F3-01 (`collaborator_status_periods` e
-- `collaborator_identifiers`).
--
-- Convenção F1-02 (supabase/migrations/README.md): extensões somente quando
-- realmente necessárias e suportadas pelo Supabase, cada uma habilitada em
-- migration dedicada e justificada. `btree_gist` é extensão padrão distribuída
-- com o PostgreSQL e suportada pelo Supabase (local e hospedado); nenhuma
-- credencial, secret ou dado real está envolvido.
--
-- A migration F3-01 seguinte
-- (`20260907103100_collaborators_identifiers_status_periods.sql`) referencia
-- esta extensão nas exclusion constraints de não-sobreposição temporal.
--
-- Comportamento:
--   - aplica em banco vazio (fluxo local de rebuild/`supabase db reset`);
--   - `create extension if not exists` torna a migration segura para
--     reexecução e idempotente;
--   - não depende de estado manual nem de projeto hospedado.
-- ============================================================================

create extension if not exists btree_gist;

comment on extension btree_gist is
  'F3-01 (Issue #78): permite exclusion constraints com igualdade escalar '
  '(uuid) + operadores de intervalo temporal (`&&`) para impedir sobreposicao '
  'de periodos do mesmo colaborador no banco, sem depender da aplicacao. '
  'Habilitada em migration dedicada conforme convencao F1-02.';
