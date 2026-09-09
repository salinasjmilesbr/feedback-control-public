-- ============================================================================
-- F4-08 (Issue #95): validação automatizada — RLS base, isolamento entre
-- tenants, least privilege e schema guard (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de 01-cenario-f4-08.sql, como superuser local, com
-- ON_ERROR_STOP ativo. Um `[PASS]` por verificação; falha aborta (código ≠ 0).
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Schema guard: FORCE RLS, RLS global, DEFINER, EXECUTE, policies, grants
-- ============================================================================

do $$
declare v_n int;
begin
  select count(*) into v_n from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relkind='r' and c.relforcerowsecurity;
  if v_n <> 0 then raise exception '[FAIL] FORCE RLS presente em % tabela(s)', v_n; end if;
  raise notice '[PASS] nenhuma tabela com FORCE ROW LEVEL SECURITY';
end $$;

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_t
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity;
  if v_t is not null then raise exception '[FAIL] tabelas public sem RLS (ou particionadas): %', v_t; end if;
  raise notice '[PASS] todas as tabelas public (incl. particionadas) com RLS habilitado';
end $$;

do $$
declare v_n int; v_t text;
begin
  select count(*), string_agg(p.proname, ',' order by p.proname) into v_n, v_t
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.prosecdef;
  if v_n <> 4 or v_t <> 'conceder_acesso_role,criar_perfil_membership,resolver_capabilities_efetivas,revogar_acesso_role' then
    raise exception '[FAIL] DEFINER esperado=4, encontrado=% (%)', v_n, v_t;
  end if;
  raise notice '[PASS] exatamente 4 funcoes SECURITY DEFINER (sem novo DEFINER)';
end $$;

do $$
declare v_n int;
begin
  select count(*) into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public' and p.prosecdef
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] EXECUTE indevido em SECURITY DEFINER (public/anon/authenticated): %', v_n;
  end if;
  raise notice '[PASS] 4 SECURITY DEFINER sem EXECUTE para public/anon/authenticated (privilegios efetivos)';
end $$;

do $$
declare v_n int;
begin
  select count(*) into v_n
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in (
      'organizacao_resolver_responsavel_posicao','organizacao_resolver_gestor_direto',
      'organizacao_resolver_subordinados_diretos','organizacao_resolver_descendentes',
      'organizacao_resolver_cadeia','organizacao_resolver_escopo_posicoes',
      'organizacao_resolver_escopo_unidades','organizacao_resolver_responsavel_avaliativo_posicao',
      'organizacao_resolver_avaliador_avaliado','resolver_responsavel_avaliacao_vigente',
      'resolver_collaborador_vinculado','resolver_capabilities_escopos_efetivas',
      'resolver_alvos_escopo','materializar_colegiado_ciclo',
      'materializar_responsabilidades_avaliacao','registrar_sucessao_avaliador')
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
  if v_n <> 0 then raise exception '[FAIL] EXECUTE public/anon/authenticated presente em % resolvers/RPC', v_n; end if;
  raise notice '[PASS] 16 resolvers/RPC sem EXECUTE para public/anon/authenticated';
end $$;

do $$
declare v_n int; v_auth boolean;
begin
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public' and p.proname='user_has_active_membership'
    and a.privilege_type='EXECUTE' and (a.grantee = 0 or a.grantee='anon'::regrole);
  if v_n <> 0 then raise exception '[FAIL] helper com EXECUTE para public/anon'; end if;
  select exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
    where n.nspname='public' and p.proname='user_has_active_membership'
      and a.privilege_type='EXECUTE' and a.grantee='authenticated'::regrole) into v_auth;
  if not v_auth then raise exception '[FAIL] helper sem EXECUTE para authenticated'; end if;
  raise notice '[PASS] helper user_has_active_membership: EXECUTE so authenticated';
end $$;

do $$
declare v_def boolean; v_stable boolean;
begin
  select p.prosecdef, p.provolatile='s' into v_def, v_stable
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='user_has_active_membership' and p.pronargs=1;
  if v_def then raise exception '[FAIL] helper nao deveria ser SECURITY DEFINER'; end if;
  if not v_stable then raise exception '[FAIL] helper deveria ser STABLE'; end if;
  raise notice '[PASS] helper e SECURITY INVOKER e STABLE';
end $$;

do $$
declare v_tab text;
  v_readable text[] := array[
    'collaborators','collaborator_identifiers','job_roles','seniority_levels',
    'organizational_units','organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','temporary_responsibilities',
    'collegiate_configurations','collegiate_configuration_members',
    'cycle_evaluation_responsibilities','collaborator_status_periods',
    'collegiate_cycle_snapshots','collegiate_cycle_snapshot_positions',
    'collegiate_cycle_snapshot_members','capabilities'];
begin
  foreach v_tab in array v_readable loop
    if not exists (select 1 from pg_policies p where p.schemaname='public'
      and p.tablename=v_tab and p.cmd='SELECT' and 'authenticated'::name = any(p.roles)) then
      raise exception '[FAIL] tabela legivel sem policy SELECT para authenticated: %', v_tab;
    end if;
  end loop;
  raise notice '[PASS] 18 tabelas legiveis possuem policy SELECT para authenticated';
end $$;

do $$
declare v_tab text;
  v_closed text[] := array[
    'access_roles','access_role_capabilities','membership_access_role_assignments',
    'membership_collaborator_links','access_role_assignment_scopes',
    'access_role_assignment_unit_targets','evaluation_succession_events'];
begin
  foreach v_tab in array v_closed loop
    if exists (select 1 from pg_policies p where p.schemaname='public' and p.tablename=v_tab) then
      raise exception '[FAIL] tabela fechada com policy indevida: %', v_tab;
    end if;
  end loop;
  raise notice '[PASS] 7 tabelas fechadas permanecem sem policy';
end $$;

do $$
declare v_n int;
begin
  select count(*) into v_n from pg_policies p where p.schemaname='public';
  if v_n <> 21 then raise exception '[FAIL] policies esperadas=21, encontradas=%', v_n; end if;
  raise notice '[PASS] 21 policies (3 identidade + 18 F4-08)';
end $$;

-- ----------------------------------------------------------------------------
-- Guard de privilégios efetivos (has_table_privilege) — auditoria item 1
-- ----------------------------------------------------------------------------
do $$
declare
  v_tab text;
  v_priv text;
  v_todos text[] := array[
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
    'access_role_assignment_scopes','access_role_assignment_unit_targets'];
  v_privs text[] := array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
begin
  foreach v_tab in array v_todos loop
    foreach v_priv in array v_privs loop
      if has_table_privilege('anon', format('public.%I', v_tab), v_priv) then
        raise exception '[FAIL] anon tem % em public.%', v_priv, v_tab;
      end if;
    end loop;
  end loop;
  raise notice '[PASS] anon sem qualquer privilegio de tabela (28 tabelas x 7 privs)';
end $$;

do $$
declare
  v_tab text;
  v_priv text;
  v_dml text[] := array['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
  v_todos text[] := array[
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
    'access_role_assignment_scopes','access_role_assignment_unit_targets'];
begin
  foreach v_tab in array v_todos loop
    foreach v_priv in array v_dml loop
      if has_table_privilege('authenticated', format('public.%I', v_tab), v_priv) then
        raise exception '[FAIL] authenticated tem % em public.%', v_priv, v_tab;
      end if;
    end loop;
  end loop;
  raise notice '[PASS] authenticated sem INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER (28 tabelas)';
end $$;

do $$
declare v_tab text;
  v_readable text[] := array[
    'collaborators','collaborator_identifiers','job_roles','seniority_levels',
    'organizational_units','organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','temporary_responsibilities',
    'collegiate_configurations','collegiate_configuration_members',
    'cycle_evaluation_responsibilities','collaborator_status_periods',
    'organizations','user_profiles','user_organization_memberships',
    'collegiate_cycle_snapshots','collegiate_cycle_snapshot_positions',
    'collegiate_cycle_snapshot_members','capabilities'];
  v_closed text[] := array[
    'access_roles','access_role_capabilities','membership_access_role_assignments',
    'membership_collaborator_links','access_role_assignment_scopes',
    'access_role_assignment_unit_targets','evaluation_succession_events'];
begin
  foreach v_tab in array v_readable loop
    if not has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT') then
      raise exception '[FAIL] authenticated sem SELECT em public.%', v_tab;
    end if;
  end loop;
  foreach v_tab in array v_closed loop
    if has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT') then
      raise exception '[FAIL] authenticated com SELECT em tabela fechada public.%', v_tab;
    end if;
  end loop;
  raise notice '[PASS] authenticated com SELECT somente nas 21 tabelas legiveis';
end $$;

-- ----------------------------------------------------------------------------
-- Schema guard: evolução insegura
-- ----------------------------------------------------------------------------
do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_t
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
  if v_t is not null then
    raise exception '[FAIL] tabela public nao classificada (D16 — catalogacao explicita obrigatoria): %', v_t;
  end if;
  raise notice '[PASS] todas as 28 tabelas public estao explicitamente classificadas (D16)';
end $$;

do $$
declare v_t text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_t
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('v','m');
  if v_t is not null then
    raise exception '[FAIL] view/materialized view public nao aprovada (D19 — contrato atual nao preve views): %', v_t;
  end if;
  raise notice '[PASS] nenhuma view/materialized view public nao aprovada (D19)';
end $$;

do $$
declare v_t text;
begin
  select string_agg(p.tablename, ', ') into v_t
  from pg_policies p
  join information_schema.columns c
    on c.table_schema='public' and c.table_name=p.tablename and c.column_name='organization_id'
  where p.schemaname='public' and (p.qual = 'true' or p.with_check = 'true');
  if v_t is not null then
    raise exception '[FAIL] policy trivially-permissive em tabela tenant-specific: %', v_t;
  end if;
  raise notice '[PASS] nenhuma policy trivially-permissive em tabela tenant-specific';
end $$;

-- ============================================================================
-- 2) Triggers fail-closed — causa ESPECÍFICA (não WHEN OTHERS)
-- ============================================================================

drop table if exists _f408_occ;
create temp table _f408_occ (organizational_position_id uuid, valid_from timestamptz, valid_to timestamptz);
create trigger _f408_occ_trg before insert on _f408_occ for each row execute function public.enforce_occupation_within_position();
do $$
declare v_msg text := null;
begin
  begin
    insert into _f408_occ values ('d8f00000-0000-0000-0000-0000000000ff', '2024-01-01T00:00:00Z', null);
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%posicao alvo inexistente%' then
    raise exception '[FAIL] occupation trigger nao falhou pela causa esperada (msg=%)', v_msg;
  end if;
  raise notice '[PASS] enforce_occupation_within_position: causa especifica (posicao inexistente)';
end $$;
drop table if exists _f408_occ;

drop table if exists _f408_tr;
create temp table _f408_tr (organizational_position_id uuid, valid_from timestamptz, valid_to timestamptz);
create trigger _f408_tr_trg before insert on _f408_tr for each row execute function public.enforce_temporary_responsibility_within_position();
do $$
declare v_msg text := null;
begin
  begin
    insert into _f408_tr values ('d8f00000-0000-0000-0000-0000000000ff', '2024-01-01T00:00:00Z', '2024-12-31T00:00:00Z');
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%posicao alvo inexistente%' then
    raise exception '[FAIL] temp-responsibility trigger nao falhou pela causa esperada (msg=%)', v_msg;
  end if;
  raise notice '[PASS] enforce_temporary_responsibility_within_position: causa especifica';
end $$;
drop table if exists _f408_tr;

drop table if exists _f408_prl;
create temp table _f408_prl (subordinate_position_id uuid, manager_position_id uuid, valid_from timestamptz, valid_to timestamptz);
create trigger _f408_prl_trg before insert on _f408_prl for each row execute function public.enforce_position_reporting_lines_within_positions();
do $$
declare v_msg text := null;
begin
  begin
    insert into _f408_prl values ('d8f00000-0000-0000-0000-0000000000ff', 'd8f00000-0000-0000-0000-0000000000d1', '2024-01-01T00:00:00Z', null);
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%posicao subordinada inexistente%' then
    raise exception '[FAIL] reporting-line trigger nao falhou pela causa esperada (msg=%)', v_msg;
  end if;
  raise notice '[PASS] enforce_position_reporting_lines_within_positions: causa especifica';
end $$;
drop table if exists _f408_prl;

-- ============================================================================
-- 3) enforce_membership_role_within_organization — role inexistente ≠ system
-- ============================================================================
drop table if exists _f408_assign;
create temp table _f408_assign (access_role_id uuid, organization_id uuid);
create trigger _f408_assign_trg before insert on _f408_assign for each row execute function public.enforce_membership_role_within_organization();
do $$
declare v_msg text := null;
begin
  begin
    insert into _f408_assign values ('d8f00000-0000-0000-0000-0000000000ff', 'd8a00000-0000-0000-0000-0000000000a1');
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%access_role inexistente%' then
    raise exception '[FAIL] role inexistente NAO falhou fechado (msg=%)', v_msg;
  end if;
  raise notice '[PASS] enforce_membership_role_within_organization: role inexistente = fail-closed (nao wildcard)';
end $$;
drop table if exists _f408_assign;

-- ============================================================================
-- 4) registrar_sucessao_avaliador — guard de organization com causa específica
-- ============================================================================
do $$
declare v_msg text := null;
begin
  begin
    perform public.registrar_sucessao_avaliador(
      array['d8a00000-0000-0000-0000-0000000000aa','d8a00000-0000-0000-0000-0000000000bb']::uuid[],
      '2099-07-01T00:00:00Z', 'mistura AB', 'd8b00000-0000-0000-0000-0000000000a6');
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%organizacoes distintas%' then
    raise exception '[FAIL] [A,B] nao rejeitado pelo guard de organization (msg=%)', v_msg;
  end if;
  raise notice '[PASS] [A,B] rejeitado especificamente pelo guard de organization (rollback)';
end $$;

do $$
declare v_msg text := null;
begin
  begin
    perform public.registrar_sucessao_avaliador(
      array['d8a00000-0000-0000-0000-0000000000bb','d8a00000-0000-0000-0000-0000000000aa']::uuid[],
      '2099-07-01T00:00:00Z', 'mistura BA', 'd8b00000-0000-0000-0000-0000000000a6');
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%organizacoes distintas%' then
    raise exception '[FAIL] [B,A] nao rejeitado pelo guard de organization (msg=%)', v_msg;
  end if;
  raise notice '[PASS] [B,A] rejeitado especificamente pelo guard de organization (rollback)';
end $$;

do $$
declare v_msg text := null;
begin
  begin
    perform public.registrar_sucessao_avaliador(
      array['d8a00000-0000-0000-0000-0000000000bb']::uuid[],
      '2099-01-01T00:00:00Z', 'data invalida', 'd8b00000-0000-0000-0000-0000000000a6');
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%data de sucessao%' then
    raise exception '[FAIL] data invalida nao rejeitada pela causa esperada (msg=%)', v_msg;
  end if;
  raise notice '[PASS] B em contexto indevido (data <= valid_from) rejeitado pela causa esperada';
end $$;

do $$
declare v_msg text := null;
begin
  begin
    perform public.registrar_sucessao_avaliador(
      array['d8a00000-0000-0000-0000-0000000000ff']::uuid[],
      '2099-06-01T00:00:00Z', 'id inexistente', 'd8b00000-0000-0000-0000-0000000000a6');
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%nao encontrada%' then
    raise exception '[FAIL] id inexistente nao rejeitado pela causa esperada (msg=%)', v_msg;
  end if;
  raise notice '[PASS] ID inexistente rejeitado pela causa esperada (nao encontrada)';
end $$;

do $$
declare v_msg text := null;
begin
  begin
    perform public.registrar_sucessao_avaliador(
      array[null::uuid]::uuid[], '2099-06-01T00:00:00Z', 'array null', 'd8b00000-0000-0000-0000-0000000000a6');
  exception when others then v_msg := SQLERRM; end;
  if v_msg is null or v_msg not like '%nao encontrada%' then
    raise exception '[FAIL] array com NULL nao rejeitado pela causa esperada (msg=%)', v_msg;
  end if;
  raise notice '[PASS] array contendo NULL rejeitado pela causa esperada (nao encontrada)';
end $$;

-- Sucessão A isolada (válida): C3_A (avaliador antigo) -> C1_A (titular de P1).
do $$
declare v_n int;
begin
  select count(*) into v_n from public.cycle_evaluation_responsibilities
  where id = 'd8a00000-0000-0000-0000-0000000000aa' and valid_to is null;
  if v_n <> 1 then raise exception '[FAIL] pre-condicao: R_A deveria estar aberta'; end if;

  perform public.registrar_sucessao_avaliador(
    array['d8a00000-0000-0000-0000-0000000000aa']::uuid[],
    '2099-06-01T00:00:00Z', 'sucessao A', 'd8b00000-0000-0000-0000-0000000000a6');

  select count(*) into v_n from public.cycle_evaluation_responsibilities
  where id = 'd8a00000-0000-0000-0000-0000000000aa'
    and valid_to = '2099-06-01T00:00:00Z';
  if v_n <> 1 then raise exception '[FAIL] R_A nao foi encerrada'; end if;

  select count(*) into v_n from public.cycle_evaluation_responsibilities
  where snapshot_id = 'd8a00000-0000-0000-0000-0000000000a9'
    and position_id = 'd8f00000-0000-0000-0000-0000000000d2'
    and responsible_collaborator_id = 'd8c00000-0000-0000-0000-0000000000a1'
    and valid_from = '2099-06-01T00:00:00Z' and valid_to is null;
  if v_n <> 1 then raise exception '[FAIL] nova responsabilidade de A nao aberta'; end if;

  select count(*) into v_n from public.evaluation_succession_events
  where snapshot_id = 'd8a00000-0000-0000-0000-0000000000a9'
    and position_id = 'd8f00000-0000-0000-0000-0000000000d2'
    and previous_responsible_collaborator_id = 'd8c00000-0000-0000-0000-0000000000a3'
    and new_responsible_collaborator_id = 'd8c00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then raise exception '[FAIL] evento de sucessao de A nao registrado'; end if;

  raise notice '[PASS] registrar_sucessao A isolada: valida (close+open + evento)';
end $$;

do $$
declare v_n int;
begin
  perform public.registrar_sucessao_avaliador(
    array['d8a00000-0000-0000-0000-0000000000bb']::uuid[],
    '2099-06-01T00:00:00Z', 'sucessao B', 'd8b00000-0000-0000-0000-0000000000a6');

  select count(*) into v_n from public.cycle_evaluation_responsibilities
  where snapshot_id = 'd8a00000-0000-0000-0000-0000000000b9'
    and position_id = 'd8f00000-0000-0000-0000-0000000000d4'
    and responsible_collaborator_id = 'd8c00000-0000-0000-0000-0000000000b1'
    and valid_from = '2099-06-01T00:00:00Z' and valid_to is null;
  if v_n <> 1 then raise exception '[FAIL] sucessao B isolada deveria ser valida'; end if;
  raise notice '[PASS] registrar_sucessao B isolada: valida (close+open + evento)';
end $$;

-- ============================================================================
-- 5) RLS em execução — USER_A (Alfa)
-- ============================================================================

select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a1', false);
set role authenticated;

do $$
declare v_ok boolean;
begin
  select public.user_has_active_membership('d8a00000-0000-0000-0000-0000000000a1') into v_ok;
  if v_ok is not true then raise exception '[FAIL] helper deveria ser true para USER_A/Alfa'; end if;
  select public.user_has_active_membership('d8a00000-0000-0000-0000-0000000000b1') into v_ok;
  if v_ok is not false then raise exception '[FAIL] helper deveria ser false para USER_A/Beta'; end if;
  raise notice '[PASS] helper correto para USER_A (Alfa true, Beta false)';
end $$;

do $$
declare
  v_tables text[] := array[
    'collaborators','collaborator_identifiers','job_roles','seniority_levels',
    'organizational_units','organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','temporary_responsibilities',
    'collegiate_configurations','collegiate_configuration_members',
    'cycle_evaluation_responsibilities','collaborator_status_periods',
    'collegiate_cycle_snapshots','collegiate_cycle_snapshot_positions',
    'collegiate_cycle_snapshot_members'];
  v_counts int[] := array[3,3,1,1,2,1,2,1,2,1,1,1,2,3,1,1,1];
  v_i int; v_n int;
begin
  for v_i in 1..array_length(v_tables,1) loop
    execute format('select count(*) from public.%I', v_tables[v_i]) into v_n;
    if v_n <> v_counts[v_i] then
      raise exception '[FAIL] USER_A viu % linhas em % (esperado %)', v_n, v_tables[v_i], v_counts[v_i];
    end if;
  end loop;
  raise notice '[PASS] USER_A le somente linhas do proprio tenant em TODAS as tabelas abertas';
end $$;

do $$
declare v_n int;
begin
  select count(*) into v_n from public.collaborators where id = 'd8c00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then raise exception '[FAIL] USER_A leu colaborador de Beta'; end if;
  select count(*) into v_n from public.collaborators where id = 'd8c00000-0000-0000-0000-0000000000c1';
  if v_n <> 0 then raise exception '[FAIL] USER_A leu colaborador de Gama'; end if;
  select count(*) into v_n from public.organizational_positions where organization_id = 'd8a00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then raise exception '[FAIL] USER_A leu posicoes de Beta'; end if;
  select count(*) into v_n from public.collegiate_cycle_snapshots where organization_id = 'd8a00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then raise exception '[FAIL] USER_A leu snapshots de Beta'; end if;
  raise notice '[PASS] cross-tenant por ID direto/filtro = DENY (Beta e Gama invisiveis)';
end $$;

do $$
declare v_n int;
begin
  select count(*) into v_n from public.organizations;
  if v_n <> 1 then raise exception '[FAIL] USER_A deveria ver 1 organizacao (Alfa), viu %', v_n; end if;
  select count(*) into v_n from public.organizations where id = 'd8a00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then raise exception '[FAIL] USER_A leu organizacao Beta'; end if;
  raise notice '[PASS] organizations: USER_A ve somente Alfa (profile ativo + membership ativa)';
end $$;

do $$
declare v_n int;
begin
  select count(*) into v_n from public.capabilities;
  if v_n < 1 then raise exception '[FAIL] authenticated nao le capabilities'; end if;
  raise notice '[PASS] capabilities global read-only para authenticated (%)', v_n;
end $$;

do $$
declare v_ok boolean := false;
begin
  begin insert into public.collaborators (id, organization_id) values ('d8c00000-0000-0000-0000-0000000000a9', 'd8a00000-0000-0000-0000-0000000000a1'); exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated inseriu em collaborators'; end if;
  raise notice '[PASS] authenticated nao insere em tabela estrutural (permission denied)';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin update public.collaborators set version = version + 1; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated atualizou collaborators'; end if;
  raise notice '[PASS] authenticated nao atualiza tabela estrutural (permission denied)';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin delete from public.collaborators; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated excluiu collaborators'; end if;
  raise notice '[PASS] authenticated nao exclui tabela estrutural (permission denied)';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin truncate table public.collaborators; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated truncou collaborators (RLS nao protege TRUNCATE)'; end if;
  raise notice '[PASS] authenticated nao trunca tabela (TRUNCATE revogado)';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin insert into public.capabilities (code, name) values ('x.test', 'x'); exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated inseriu em capabilities'; end if;
  raise notice '[PASS] capabilities INSERT negado';
end $$;
do $$
declare v_ok boolean := false;
begin
  begin update public.capabilities set name = 'y'; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated atualizou capabilities'; end if;
  raise notice '[PASS] capabilities UPDATE negado';
end $$;
do $$
declare v_ok boolean := false;
begin
  begin delete from public.capabilities; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated excluiu capabilities'; end if;
  raise notice '[PASS] capabilities DELETE negado';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin update public.user_profiles set status='disabled'; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated atualizou user_profiles'; end if;
  raise notice '[PASS] user_profiles UPDATE negado';
end $$;
do $$
declare v_ok boolean := false;
begin
  begin insert into public.user_organization_memberships (id, user_profile_id, organization_id, status) values (gen_random_uuid(), 'd8b00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000b1', 'active'); exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated inseriu membership'; end if;
  raise notice '[PASS] user_organization_memberships INSERT negado';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin update public.evaluation_succession_events set motive='x'; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated atualizou evaluation_succession_events'; end if;
  raise notice '[PASS] auditoria (evaluation_succession_events) UPDATE negado';
end $$;
do $$
declare v_ok boolean := false;
begin
  begin delete from public.collegiate_cycle_snapshots; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated reescreveu snapshot'; end if;
  raise notice '[PASS] snapshots DELETE negado (sem rewrite)';
end $$;
do $$
declare v_ok boolean := false;
begin
  begin update public.collegiate_cycle_snapshots set ano = 1; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated atualizou snapshot'; end if;
  raise notice '[PASS] snapshots UPDATE negado (sem rewrite)';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin update public.collaborators set organization_id = 'd8a00000-0000-0000-0000-0000000000b1' where id = 'd8c00000-0000-0000-0000-0000000000a1'; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated trocou organization_id A->B'; end if;
  raise notice '[PASS] troca organization_id A->B negada (permission denied)';
end $$;

do $$
declare v_n int; v_ok boolean := false;
begin
  select count(*) into v_n from public.collaborators c join public.organizations o on o.id = c.organization_id;
  if v_n <> 3 then raise exception '[FAIL] join collaborators x organizations vazou (% linhas)', v_n; end if;
  begin
    perform 1 from public.collaborators c join public.membership_collaborator_links l on l.collaborator_id = c.id;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] join com tabela fechada deveria ser negado (permission denied)'; end if;
  raise notice '[PASS] joins sem vazamento (own-tenant 3; join com tabela fechada = permission denied)';
end $$;

do $$
declare v_t text; v_ok boolean;
  v_closed text[] := array['access_roles','access_role_capabilities','membership_access_role_assignments','membership_collaborator_links','access_role_assignment_scopes','access_role_assignment_unit_targets','evaluation_succession_events'];
begin
  foreach v_t in array v_closed loop
    v_ok := false;
    begin execute format('select count(*) from public.%I', v_t); exception when insufficient_privilege then v_ok := true; end;
    if not v_ok then raise exception '[FAIL] authenticated leu tabela fechada %', v_t; end if;
  end loop;
  raise notice '[PASS] 7 tabelas fechadas invisiveis (permission denied) apesar de dados de fixture';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin perform 1 from public.organizacao_resolver_responsavel_posicao('d8f00000-0000-0000-0000-0000000000d1','2024-06-01T00:00:00Z'); exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated executou resolver'; end if;
  raise notice '[PASS] authenticated nao executa resolver (EXECUTE revogado)';
end $$;

reset role;

-- ============================================================================
-- 6) Parent/FK A->B (FK poisoning) — superuser, FK composta bloqueia
-- ============================================================================
do $$
declare v_ok boolean := false;
begin
  begin
    insert into public.membership_collaborator_links (membership_id, organization_id, collaborator_id, status)
    values ('d8d00000-0000-0000-0000-0000000000a3', 'd8a00000-0000-0000-0000-0000000000a1', 'd8c00000-0000-0000-0000-0000000000b1', 'active');
  exception when foreign_key_violation then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] parent/FK cross-tenant (colaborador de Beta) NAO foi bloqueado'; end if;
  raise notice '[PASS] parent/FK cross-tenant A->B bloqueado (FK composta de tenant)';
end $$;

-- ============================================================================
-- 7) USER_AB (multi-tenant) + membership revogada durante a sessão
-- ============================================================================
select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a3', false);
set role authenticated;
do $$
declare v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 6 then raise exception '[FAIL] USER_AB deveria ver 6 (Alfa+Beta), viu %', v_n; end if;
  select count(*) into v_n from public.collaborators where id = 'd8c00000-0000-0000-0000-0000000000c1';
  if v_n <> 0 then raise exception '[FAIL] USER_AB leu Gama'; end if;
  raise notice '[PASS] multi-tenant: USER_AB le Alfa+Beta, nao Gama';
end $$;
reset role;

update public.user_organization_memberships set status='disabled' where id='d8d00000-0000-0000-0000-0000000000a3';
select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a3', false);
set role authenticated;
do $$
declare v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 3 then raise exception '[FAIL] apos revogacao Alfa, USER_AB deveria ver 3 (so Beta), viu %', v_n; end if;
  raise notice '[PASS] membership revogada durante a sessao: acesso a Alfa removido (so Beta)';
end $$;
reset role;
update public.user_organization_memberships set status='active' where id='d8d00000-0000-0000-0000-0000000000a3';

-- ============================================================================
-- 8) USER_INACTIVE, USER_PROFILE_INACTIVE, USER_NONE, anon
-- ============================================================================
select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a4', false);
set role authenticated;
do $$
declare v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 0 then raise exception '[FAIL] membership disabled ainda le (% linhas)', v_n; end if;
  raise notice '[PASS] membership disabled remove acesso';
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a7', false);
set role authenticated;
do $$
declare v_ok boolean; v_n int;
begin
  select public.user_has_active_membership('d8a00000-0000-0000-0000-0000000000a1') into v_ok;
  if v_ok is not false then raise exception '[FAIL] helper deveria ser false para profile inativo'; end if;
  select count(*) into v_n from public.collaborators;
  if v_n <> 0 then raise exception '[FAIL] profile inativo leu estrutura (% linhas)', v_n; end if;
  select count(*) into v_n from public.organizations;
  if v_n <> 0 then raise exception '[FAIL] profile inativo leu organizations (% linhas)', v_n; end if;
  select count(*) into v_n from public.organizations where id = 'd8a00000-0000-0000-0000-0000000000a1';
  if v_n <> 0 then raise exception '[FAIL] profile inativo leu Alfa por ID direto'; end if;
  select count(*) into v_n from public.user_profiles;
  if v_n <> 0 then raise exception '[FAIL] profile inativo leu o proprio perfil'; end if;
  raise notice '[PASS] profile inativo + membership ativa = DENY (estrutura, organizations e perfil)';
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a5', false);
set role authenticated;
do $$
declare v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 0 then raise exception '[FAIL] usuario sem membership leu estrutura'; end if;
  select count(*) into v_n from public.organizations;
  if v_n <> 0 then raise exception '[FAIL] usuario sem membership leu organizations'; end if;
  raise notice '[PASS] usuario sem membership nao le estrutura/organizations';
end $$;
reset role;

set role anon;
do $$
declare v_ok boolean := false;
begin
  begin perform 1 from public.collaborators; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] anon leu collaborators'; end if;
  raise notice '[PASS] anon sem acesso a dados privados (permission denied)';
end $$;
reset role;

-- ============================================================================
-- 9) Limpeza do cenário sintético
-- ============================================================================
delete from public.evaluation_succession_events where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.cycle_evaluation_responsibilities where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.collegiate_cycle_snapshot_members where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.collegiate_cycle_snapshot_positions where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.collegiate_cycle_snapshots where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.collegiate_configuration_members where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.collegiate_configurations where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.temporary_responsibilities where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.occupations where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.position_reporting_lines where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.access_role_assignment_unit_targets where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.access_role_assignment_scopes where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.membership_access_role_assignments where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.membership_collaborator_links where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.access_role_capabilities where access_role_id::text like 'd8f00000-0000-0000-0000-0000000000f%';
delete from public.access_roles where id::text like 'd8f00000-0000-0000-0000-0000000000f%';
delete from public.organizational_positions where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.organizational_unit_parent_periods where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.organizational_units where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.collaborator_identifiers where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.collaborator_status_periods where collaborator_id::text like 'd8c00000-0000-0000-0000-0000000000%';
delete from public.collaborators where id::text like 'd8c00000-0000-0000-0000-0000000000%';
delete from public.seniority_levels where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.job_roles where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';
delete from public.user_organization_memberships where id::text like 'd8d00000-0000-0000-0000-0000000000%';
delete from public.user_profiles where id::text like 'd8b00000-0000-0000-0000-0000000000%';
delete from auth.users where id::text like 'd8b00000-0000-0000-0000-0000000000%';
delete from public.organizations where id::text like 'd8a00000-0000-0000-0000-0000000000%';

do $$
begin
  if exists (select 1 from public.collaborators where id::text like 'd8c00000%') then
    raise exception '[FAIL] limpeza incompleta (collaborators)';
  end if;
  if exists (select 1 from public.organizations where id::text like 'd8a00000%') then
    raise exception '[FAIL] limpeza incompleta (organizations)';
  end if;
  raise notice '[PASS] cenario sintetico F4-08 removido ao final';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F4-08: todas as verificacoes passaram (schema guard, grants, triggers, RLS, cross-tenant, multi-tenant, least privilege).';
end $$;
