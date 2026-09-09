-- ============================================================================
-- F4-08 (Issue #95): least privilege de tabela — remover privilégios excedentes
-- de anon/authenticated (auditoria adversarial: TRUNCATE/TRIGGER/REFERENCES/etc.)
-- ----------------------------------------------------------------------------
-- O Supabase concede, por default privileges, TODOS os privilégios de tabela
-- (INSERT/SELECT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) a
-- `anon`/`authenticated`/`service_role` em `public`. RLS NÃO protege TRUNCATE,
-- então authenticated/anon poderiam TRUNCATE qualquer tabela. O GRANT SELECT das
-- migrations anteriores não remove esses privilégios herdados.
--
-- Correção (least privilege, sem FORCE RLS):
--   - revoga TODOS os privilégios de tabela/sequência de anon e authenticated;
--   - regaranta SOMENTE o SELECT previsto pelo contrato a authenticated nas 21
--     tabelas legíveis (3 identidade + 18 F4-08);
--   - corrige os default privileges de `postgres` e `supabase_admin` para que
--     novas tabelas/sequências/funções NÃO voltem a herdar privilégios
--     excedentes para anon/authenticated.
--
-- `service_role` (server-side, BYPASSRLS) mantém seus privilégios completos —
-- fronteira confiável usada apenas por Edge Functions/tooling local, nunca no
-- cliente. `postgres` (superuser) não é afetado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Revoga tudo de anon/authenticated nas tabelas e sequências existentes
-- ----------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- ----------------------------------------------------------------------------
-- 2) Regaranta somente o SELECT contratado a authenticated (21 tabelas)
-- ----------------------------------------------------------------------------
-- Identidade/raiz (F2-03):
grant select on public.user_profiles to authenticated;
grant select on public.user_organization_memberships to authenticated;
grant select on public.organizations to authenticated;

-- Tenant-rooted estruturais (A) — 13:
grant select on public.collaborators to authenticated;
grant select on public.collaborator_identifiers to authenticated;
grant select on public.job_roles to authenticated;
grant select on public.seniority_levels to authenticated;
grant select on public.organizational_units to authenticated;
grant select on public.organizational_unit_parent_periods to authenticated;
grant select on public.organizational_positions to authenticated;
grant select on public.position_reporting_lines to authenticated;
grant select on public.occupations to authenticated;
grant select on public.temporary_responsibilities to authenticated;
grant select on public.collegiate_configurations to authenticated;
grant select on public.collegiate_configuration_members to authenticated;
grant select on public.cycle_evaluation_responsibilities to authenticated;

-- Filha indireta (B) — 1:
grant select on public.collaborator_status_periods to authenticated;

-- Snapshots/histórico (E) — 3:
grant select on public.collegiate_cycle_snapshots to authenticated;
grant select on public.collegiate_cycle_snapshot_positions to authenticated;
grant select on public.collegiate_cycle_snapshot_members to authenticated;

-- Catálogo global read-only — 1:
grant select on public.capabilities to authenticated;

-- ----------------------------------------------------------------------------
-- 3) Default privileges endurecidos (novas tabelas/sequências/funções)
-- ----------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated;

-- NOTA (auditoria adversarial — limitação documentada): os default privileges de
-- `supabase_admin` NÃO podem ser alterados pela role de migration (`postgres`,
-- que não é superuser no Supabase local — somente `supabase_admin` é superuser,
-- e `postgres` não é membro dela). Eles permanecem gerenciados pelo roles.sql do
-- Supabase e afetam apenas objetos criados POR `supabase_admin` (as migrations
-- criam as tabelas como `postgres`, cobertas acima). Mitigação compensatória: o
-- schema guard da validação F4-08 (has_table_privilege) falha o CI se QUALQUER
-- tabela de `public`, independentemente do criador, tiver grant excedente a
-- anon/authenticated (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER).
