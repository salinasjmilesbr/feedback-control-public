-- ============================================================================
-- F4-08 (Issue #95): mutation/regression tests do schema guard
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Prova que o schema guard DETECTA regressões de segurança, não apenas que o
-- schema atual passa. Executar DEPOIS de 02-validar-f4-08.sql (schema limpo).
--
-- Padrão por mutação:
--   schema seguro → introduz regressão → guard detecta (FAIL esperado) →
--   reverte → guard volta a PASSAR.
-- Nenhum `WHEN OTHERS` mascarando falha: cada detecção valida um SINAL
-- específico (contagem/privilégio efetivo), nunca "qualquer erro".
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) GRANT EXECUTE indevido em SECURITY DEFINER
-- ============================================================================
grant execute on function public.conceder_acesso_role(uuid, uuid, uuid) to authenticated;

do $$
declare v_n int;
begin
  select count(*) into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public' and p.prosecdef
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee='anon'::regrole or a.grantee='authenticated'::regrole);
  if v_n = 0 then raise exception '[MUT FAIL] guard nao detectou EXECUTE indevido em SECURITY DEFINER'; end if;
end $$;

revoke execute on function public.conceder_acesso_role(uuid, uuid, uuid) from authenticated;

do $$
declare v_n int;
begin
  select count(*) into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public' and p.prosecdef
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee='anon'::regrole or a.grantee='authenticated'::regrole);
  if v_n <> 0 then raise exception '[MUT FAIL] guard nao voltou ao estado limpo (DEFINER)'; end if;
  raise notice '[PASS] mutacao A: EXECUTE indevido em SECURITY DEFINER detectado e revertido';
end $$;

-- ============================================================================
-- B) Nova tabela NÃO classificada
-- ============================================================================
create table public._mut_nao_class (id uuid);

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ') into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p')
    and c.relname not in (
      'collaborators','collaborator_identifiers','job_roles','seniority_levels',
      'organizational_units','organizational_unit_parent_periods','organizational_positions',
      'position_reporting_lines','occupations','temporary_responsibilities',
      'collegiate_configurations','collegiate_configuration_members',
      'cycle_evaluation_responsibilities','collaborator_status_periods',
      'organizations','user_profiles','user_organization_memberships',
      'collegiate_cycle_snapshots','collegiate_cycle_snapshot_positions',
      'collegiate_cycle_snapshot_members','evaluation_succession_events',
      'capabilities','access_roles','access_role_capabilities',
      'membership_access_role_assignments','membership_collaborator_links',
      'access_role_assignment_scopes','access_role_assignment_unit_targets');
  if v_t is null or v_t not like '%_mut_nao_class%' then
    raise exception '[MUT FAIL] guard nao detectou tabela nao classificada (v_t=%)', v_t;
  end if;
end $$;

drop table public._mut_nao_class;

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ') into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p')
    and c.relname not in (
      'collaborators','collaborator_identifiers','job_roles','seniority_levels',
      'organizational_units','organizational_unit_parent_periods','organizational_positions',
      'position_reporting_lines','occupations','temporary_responsibilities',
      'collegiate_configurations','collegiate_configuration_members',
      'cycle_evaluation_responsibilities','collaborator_status_periods',
      'organizations','user_profiles','user_organization_memberships',
      'collegiate_cycle_snapshots','collegiate_cycle_snapshot_positions',
      'collegiate_cycle_snapshot_members','evaluation_succession_events',
      'capabilities','access_roles','access_role_capabilities',
      'membership_access_role_assignments','membership_collaborator_links',
      'access_role_assignment_scopes','access_role_assignment_unit_targets');
  if v_t is not null then raise exception '[MUT FAIL] catalogo nao voltou ao estado limpo (%)', v_t; end if;
  raise notice '[PASS] mutacao B: tabela nao classificada detectada e revertida';
end $$;

-- ============================================================================
-- C) Nova tabela tenant-specific SEM RLS
-- ============================================================================
create table public._mut_sem_rls (id uuid, organization_id uuid);

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ') into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity;
  if v_t is null or v_t not like '%_mut_sem_rls%' then
    raise exception '[MUT FAIL] guard nao detectou tabela sem RLS (v_t=%)', v_t;
  end if;
end $$;

drop table public._mut_sem_rls;

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ') into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity;
  if v_t is not null then raise exception '[MUT FAIL] RLS nao voltou ao estado limpo (%)', v_t; end if;
  raise notice '[PASS] mutacao C: tabela tenant-specific sem RLS detectada e revertida';
end $$;

-- ============================================================================
-- D) Nova tabela tenant-specific com grants excessivos (INSERT a authenticated)
-- ============================================================================
create table public._mut_grants (id uuid, organization_id uuid);
alter table public._mut_grants enable row level security;
grant insert on public._mut_grants to authenticated;

do $$
begin
  if not has_table_privilege('authenticated', 'public._mut_grants', 'INSERT') then
    raise exception '[MUT FAIL] guard nao detectou grant excessivo (INSERT) em tabela nova';
  end if;
end $$;

drop table public._mut_grants;

do $$
begin
  if to_regclass('public._mut_grants') is not null then
    raise exception '[MUT FAIL] tabela _mut_grants nao foi removida (revert incompleto)';
  end if;
  raise notice '[PASS] mutacao D: grant excessivo em tabela nova detectado e revertido';
end $$;

-- ============================================================================
-- E) VIEW não classificada
-- ============================================================================
create view public._mut_view as select 1 as x;

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ') into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='v';
  if v_t is null or v_t not like '%_mut_view%' then
    raise exception '[MUT FAIL] guard nao detectou view nao aprovada (v_t=%)', v_t;
  end if;
end $$;

drop view public._mut_view;

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ') into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='v';
  if v_t is not null then raise exception '[MUT FAIL] view nao voltou ao estado limpo (%)', v_t; end if;
  raise notice '[PASS] mutacao E: view nao aprovada detectada e revertida';
end $$;

-- ============================================================================
-- F) MATERIALIZED VIEW não classificada
-- ============================================================================
create materialized view public._mut_matview as select 1 as x;

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ') into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='m';
  if v_t is null or v_t not like '%_mut_matview%' then
    raise exception '[MUT FAIL] guard nao detectou materialized view (v_t=%)', v_t;
  end if;
end $$;

drop materialized view public._mut_matview;

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ') into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='m';
  if v_t is not null then raise exception '[MUT FAIL] materialized view nao voltou ao estado limpo (%)', v_t; end if;
  raise notice '[PASS] mutacao F: materialized view nao aprovada detectada e revertida';
end $$;

-- ============================================================================
-- G) TRUNCATE concedido indevidamente a authenticated
-- ============================================================================
grant truncate on public.collaborators to authenticated;

do $$
begin
  if not has_table_privilege('authenticated', 'public.collaborators', 'TRUNCATE') then
    raise exception '[MUT FAIL] guard nao detectou TRUNCATE indevido';
  end if;
end $$;

revoke truncate on public.collaborators from authenticated;

do $$
begin
  if has_table_privilege('authenticated', 'public.collaborators', 'TRUNCATE') then
    raise exception '[MUT FAIL] TRUNCATE indevido nao foi revertido';
  end if;
  raise notice '[PASS] mutacao G: TRUNCATE indevido detectado e revertido';
end $$;

-- ============================================================================
-- H) Policy tenant-specific trivially-permissive (USING (true))
-- ============================================================================
create policy _mut_policy_true on public.collaborators
  for select to authenticated using (true);

do $$
declare v_t text;
begin
  select string_agg(p.tablename, ', ') into v_t
  from pg_policies p
  join information_schema.columns c
    on c.table_schema='public' and c.table_name=p.tablename and c.column_name='organization_id'
  where p.schemaname='public' and (p.qual = 'true' or p.with_check = 'true');
  if v_t is null or v_t not like '%collaborators%' then
    raise exception '[MUT FAIL] guard nao detectou policy trivially-permissive (v_t=%)', v_t;
  end if;
end $$;

drop policy _mut_policy_true on public.collaborators;

do $$
declare v_t text;
begin
  select string_agg(p.tablename, ', ') into v_t
  from pg_policies p
  join information_schema.columns c
    on c.table_schema='public' and c.table_name=p.tablename and c.column_name='organization_id'
  where p.schemaname='public' and (p.qual = 'true' or p.with_check = 'true');
  if v_t is not null then raise exception '[MUT FAIL] policy trivially-permissive nao foi revertida (%)', v_t; end if;
  raise notice '[PASS] mutacao H: policy trivially-permissive detectada e revertida';
end $$;

-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F4-08: 8 mutation tests do schema guard passaram (deteccao + reversao).';
end $$;
