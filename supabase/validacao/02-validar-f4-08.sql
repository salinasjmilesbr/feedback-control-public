-- ============================================================================
-- F4-08 (Issue #95): validação automatizada — RLS base e isolamento real entre
-- tenants (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f4-08.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f4-08.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f4-08.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; qualquer falha levanta
-- exceção e aborta com código de saída não-zero. NÃO toca projeto remoto, NÃO
-- altera policies e remove ao final os dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Schema guard: FORCE RLS, RLS global, DEFINER, EXECUTE PUBLIC, policies
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and c.relforcerowsecurity;
  if v_n <> 0 then
    raise exception '[FAIL] FORCE RLS presente em % tabela(s)', v_n;
  end if;
  raise notice '[PASS] nenhuma tabela com FORCE ROW LEVEL SECURITY';
end $$;

do $$
declare
  v_t text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_t
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if v_t is not null then
    raise exception '[FAIL] tabelas public sem RLS: %', v_t;
  end if;
  raise notice '[PASS] todas as tabelas public com RLS habilitado';
end $$;

do $$
declare
  v_n int;
  v_t text;
begin
  select count(*), string_agg(p.proname, ',' order by p.proname) into v_n, v_t
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4
     or v_t <> 'conceder_acesso_role,criar_perfil_membership,resolver_capabilities_efetivas,revogar_acesso_role' then
    raise exception '[FAIL] SECURITY DEFINER esperado=4 (%), encontrado=% (%)',
      'conceder_acesso_role,criar_perfil_membership,resolver_capabilities_efetivas,revogar_acesso_role', v_n, v_t;
  end if;
  raise notice '[PASS] exatamente 4 funcoes SECURITY DEFINER (sem novo DEFINER)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname = 'public'
    and p.proname in (
      'organizacao_resolver_responsavel_posicao',
      'organizacao_resolver_gestor_direto',
      'organizacao_resolver_subordinados_diretos',
      'organizacao_resolver_descendentes',
      'organizacao_resolver_cadeia',
      'organizacao_resolver_escopo_posicoes',
      'organizacao_resolver_escopo_unidades',
      'organizacao_resolver_responsavel_avaliativo_posicao',
      'organizacao_resolver_avaliador_avaliado',
      'resolver_responsavel_avaliacao_vigente',
      'resolver_collaborador_vinculado',
      'resolver_capabilities_escopos_efetivas',
      'resolver_alvos_escopo',
      'materializar_colegiado_ciclo',
      'materializar_responsabilidades_avaliacao',
      'registrar_sucessao_avaliador'
    )
    and a.privilege_type = 'EXECUTE'
    and (
      a.grantee = 0
      or a.grantee = 'anon'::regrole
      or a.grantee = 'authenticated'::regrole
    );
  if v_n <> 0 then
    raise exception '[FAIL] EXECUTE public/anon/authenticated ainda presente em % funcao(oes) resolvers/RPC', v_n;
  end if;
  raise notice '[PASS] 16 resolvers/RPC sem EXECUTE para public/anon/authenticated (revoke aplicado)';
end $$;

do $$
declare
  v_n int;
  v_auth boolean;
begin
  -- Helper: EXECUTE somente a authenticated (necessário às policies); sem
  -- public/anon. authenticated deve ter o grant para a RLS funcionar.
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname = 'public'
    and p.proname = 'user_has_active_membership'
    and a.privilege_type = 'EXECUTE'
    and (a.grantee = 0 or a.grantee = 'anon'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] helper user_has_active_membership com EXECUTE para public/anon';
  end if;

  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
    where n.nspname = 'public'
      and p.proname = 'user_has_active_membership'
      and a.privilege_type = 'EXECUTE'
      and a.grantee = 'authenticated'::regrole
  ) into v_auth;
  if not v_auth then
    raise exception '[FAIL] helper user_has_active_membership sem EXECUTE para authenticated';
  end if;
  raise notice '[PASS] helper user_has_active_membership: EXECUTE so authenticated (sem public/anon)';
end $$;

do $$
declare
  v_def boolean;
  v_stable boolean;
begin
  select p.prosecdef, p.provolatile = 's'
    into v_def, v_stable
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'user_has_active_membership'
    and p.pronargs = 1;
  if v_def then
    raise exception '[FAIL] helper user_has_active_membership nao deveria ser SECURITY DEFINER';
  end if;
  if not v_stable then
    raise exception '[FAIL] helper user_has_active_membership deveria ser STABLE';
  end if;
  raise notice '[PASS] helper user_has_active_membership e SECURITY INVOKER e STABLE';
end $$;

do $$
declare
  v_tab text;
  v_readable text[] := array[
    'collaborators','collaborator_identifiers','job_roles','seniority_levels',
    'organizational_units','organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','temporary_responsibilities',
    'collegiate_configurations','collegiate_configuration_members',
    'cycle_evaluation_responsibilities','collaborator_status_periods',
    'collegiate_cycle_snapshots','collegiate_cycle_snapshot_positions',
    'collegiate_cycle_snapshot_members','capabilities'
  ];
begin
  foreach v_tab in array v_readable loop
    if not exists (
      select 1 from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = v_tab
        and p.cmd = 'SELECT'
        and 'authenticated'::name = any (p.roles)
    ) then
      raise exception '[FAIL] tabela legivel sem policy SELECT para authenticated: %', v_tab;
    end if;
  end loop;
  raise notice '[PASS] 18 tabelas legiveis possuem policy SELECT para authenticated';
end $$;

do $$
declare
  v_tab text;
  v_closed text[] := array[
    'access_roles','access_role_capabilities','membership_access_role_assignments',
    'membership_collaborator_links','access_role_assignment_scopes',
    'access_role_assignment_unit_targets','evaluation_succession_events'
  ];
begin
  foreach v_tab in array v_closed loop
    if exists (
      select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = v_tab
    ) then
      raise exception '[FAIL] tabela fechada com policy indevida: %', v_tab;
    end if;
  end loop;
  raise notice '[PASS] 7 tabelas fechadas (seguranca/auditoria) permanecem sem policy';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_policies p where p.schemaname = 'public';
  if v_n <> 21 then
    raise exception '[FAIL] quantidade de policies esperada=21, encontrada=%', v_n;
  end if;
  raise notice '[PASS] 21 policies presentes (3 identidade + 18 F4-08)';
end $$;

-- ============================================================================
-- 2) Triggers F3-04/F3-05/F3-06 fail-closed (parent inexistente -> raise)
-- ============================================================================

drop table if exists _f408_occ;
create temp table _f408_occ (
  organizational_position_id uuid,
  valid_from timestamptz,
  valid_to   timestamptz
);
create trigger _f408_occ_trg
  before insert on _f408_occ
  for each row execute function public.enforce_occupation_within_position();

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into _f408_occ values
      ('d8f00000-0000-0000-0000-0000000000ff', '2024-01-01T00:00:00Z', null);
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] enforce_occupation_within_position nao falhou fechado';
  end if;
  raise notice '[PASS] enforce_occupation_within_position falha fechado (parent inexistente)';
end $$;

drop table if exists _f408_tr;
create temp table _f408_tr (
  organizational_position_id uuid,
  valid_from timestamptz,
  valid_to   timestamptz
);
create trigger _f408_tr_trg
  before insert on _f408_tr
  for each row execute function public.enforce_temporary_responsibility_within_position();

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into _f408_tr values
      ('d8f00000-0000-0000-0000-0000000000ff', '2024-01-01T00:00:00Z', null);
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] enforce_temporary_responsibility_within_position nao falhou fechado';
  end if;
  raise notice '[PASS] enforce_temporary_responsibility_within_position falha fechado';
end $$;

drop table if exists _f408_prl;
create temp table _f408_prl (
  subordinate_position_id uuid,
  manager_position_id     uuid,
  valid_from              timestamptz,
  valid_to                timestamptz
);
create trigger _f408_prl_trg
  before insert on _f408_prl
  for each row execute function public.enforce_position_reporting_lines_within_positions();

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into _f408_prl values
      ('d8f00000-0000-0000-0000-0000000000ff',
       'd8f00000-0000-0000-0000-0000000000d1',
       '2024-01-01T00:00:00Z', null);
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] enforce_position_reporting_lines_within_positions nao falhou fechado';
  end if;
  raise notice '[PASS] enforce_position_reporting_lines_within_positions falha fechado';
end $$;

drop table if exists _f408_occ;
drop table if exists _f408_tr;
drop table if exists _f408_prl;

-- ============================================================================
-- 3) registrar_sucessao_avaliador: sucessão cross-tenant negada
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.registrar_sucessao_avaliador(
      array[
        'd8a00000-0000-0000-0000-0000000000aa',
        'd8a00000-0000-0000-0000-0000000000bb'
      ]::uuid[],
      '2099-06-01T00:00:00Z',
      'teste cross-tenant',
      'd8b00000-0000-0000-0000-0000000000a6'
    );
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] registrar_sucessao_avaliador nao bloqueou sucessao cross-tenant';
  end if;
  raise notice '[PASS] registrar_sucessao_avaliador nega sucessao cross-tenant (guard de organization)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.evaluation_succession_events
  where organization_id = 'd8a00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] sucessao cross-tenant produziu evento em Beta';
  end if;
  raise notice '[PASS] nenhum evento de sucessao foi criado em Beta (fail-closed)';
end $$;

-- ============================================================================
-- 4) RLS em execução — USER_A (membership ativa apenas em Alfa)
-- ============================================================================

select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a1', false);
set role authenticated;

do $$
declare
  v_ok boolean;
  v_n int;
begin
  -- Helper: membership ativa em Alfa => true; Beta => false.
  select public.user_has_active_membership('d8a00000-0000-0000-0000-0000000000a1') into v_ok;
  if v_ok is not true then
    raise exception '[FAIL] helper deveria retornar true para membership ativa (Alfa)';
  end if;
  select public.user_has_active_membership('d8a00000-0000-0000-0000-0000000000b1') into v_ok;
  if v_ok is not false then
    raise exception '[FAIL] helper deveria retornar false para organizacao sem membership (Beta)';
  end if;

  -- Own-tenant: USER_A ve somente o colaborador de Alfa.
  select count(*) into v_n from public.collaborators;
  if v_n <> 1 then
    raise exception '[FAIL] USER_A deveria ver 1 colaborador (Alfa), viu %', v_n;
  end if;
  raise notice '[PASS] helper correto + USER_A le somente colaborador do proprio tenant (Alfa)';
end $$;

do $$
declare
  v_n int;
begin
  -- Cross-tenant por ID direto: colaborador de Beta invisível.
  select count(*) into v_n from public.collaborators
  where id = 'd8c00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] USER_A leu colaborador de Beta por ID direto';
  end if;
  raise notice '[PASS] USER_A nao le colaborador de Beta (cross-tenant DENY por ID direto)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.organizational_positions;
  if v_n <> 1 then
    raise exception '[FAIL] USER_A deveria ver 1 posicao (Alfa), viu %', v_n;
  end if;
  select count(*) into v_n from public.job_roles;
  if v_n <> 1 then
    raise exception '[FAIL] USER_A deveria ver 1 job_role (Alfa), viu %', v_n;
  end if;
  select count(*) into v_n from public.organizational_units;
  if v_n <> 1 then
    raise exception '[FAIL] USER_A deveria ver 1 unidade (Alfa), viu %', v_n;
  end if;
  raise notice '[PASS] USER_A le somente estrutura do proprio tenant (posicao/job_role/unidade)';
end $$;

do $$
declare
  v_n int;
begin
  -- Filha indireta (sem organization_id) via EXISTS em collaborators.
  select count(*) into v_n from public.collaborator_status_periods;
  if v_n <> 1 then
    raise exception '[FAIL] USER_A deveria ver 1 status period (via collaborator Alfa), viu %', v_n;
  end if;
  raise notice '[PASS] collaborator_status_periods respeita tenant via parent (EXISTS)';
end $$;

do $$
declare
  v_n int;
begin
  -- Snapshots own-tenant: USER_A ve somente S_A (Alfa).
  select count(*) into v_n from public.collegiate_cycle_snapshots;
  if v_n <> 1 then
    raise exception '[FAIL] USER_A deveria ver 1 snapshot (Alfa), viu %', v_n;
  end if;
  raise notice '[PASS] snapshots/historico respeitam tenant (leitura own-tenant)';
end $$;

do $$
declare
  v_n int;
begin
  -- Catálogo GLOBAL de capabilities: read-only para authenticated.
  select count(*) into v_n from public.capabilities;
  if v_n < 1 then
    raise exception '[FAIL] authenticated deveria ler o catalogo global de capabilities';
  end if;
  raise notice '[PASS] capabilities e catalogo global read-only para authenticated (%)', v_n;
end $$;

do $$
declare
  v_n int;
  v_tab text;
  v_closed text[] := array[
    'access_roles','access_role_capabilities','membership_access_role_assignments',
    'membership_collaborator_links','access_role_assignment_scopes',
    'access_role_assignment_unit_targets','evaluation_succession_events'
  ];
begin
  foreach v_tab in array v_closed loop
    execute format('select count(*) from public.%I', v_tab) into v_n;
    if v_n <> 0 then
      raise exception '[FAIL] authenticated leu % linha(s) da tabela fechada %', v_n, v_tab;
    end if;
  end loop;
  raise notice '[PASS] authenticated nao le tabelas de seguranca/auditoria (deny-by-default)';
end $$;

do $$
declare
  v_n int;
begin
  -- DML direto negado (sem policy de escrita).
  update public.collaborators set version = version + 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated atualizou collaborators indevidamente';
  end if;

  delete from public.collaborators where organization_id = 'd8a00000-0000-0000-0000-0000000000a1';
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated excluiu collaborators indevidamente';
  end if;
  raise notice '[PASS] authenticated nao atualiza/exclui tabelas estruturais (sem policy de escrita)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.collaborators (id, organization_id)
    values ('d8c00000-0000-0000-0000-0000000000a9', 'd8a00000-0000-0000-0000-0000000000a1');
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated inseriu em collaborators indevidamente';
  end if;
  raise notice '[PASS] authenticated nao insere em tabelas estruturais (sem policy de escrita)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    perform 1
    from public.organizacao_resolver_responsavel_posicao(
      'd8f00000-0000-0000-0000-0000000000d1', '2024-06-01T00:00:00Z');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated executou resolver estrutural (EXECUTE deveria estar revogado)';
  end if;
  raise notice '[PASS] authenticated nao executa resolver estrutural (EXECUTE revogado na F4-08)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.registrar_sucessao_avaliador(
      array['d8a00000-0000-0000-0000-0000000000aa']::uuid[],
      '2099-06-01T00:00:00Z', 'teste', 'd8b00000-0000-0000-0000-0000000000a6');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated executou registrar_sucessao_avaliador (EXECUTE deveria estar revogado)';
  end if;
  raise notice '[PASS] authenticated nao executa registrar_sucessao_avaliador (EXECUTE revogado)';
end $$;

reset role;

-- ============================================================================
-- 5) USER_AB (multi-tenant: Alfa + Beta, nunca Gama)
-- ============================================================================

select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a3', false);
set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 2 then
    raise exception '[FAIL] USER_AB deveria ver 2 colaboradores (Alfa+Beta), viu %', v_n;
  end if;
  select count(*) into v_n from public.collaborators
  where id = 'd8c00000-0000-0000-0000-0000000000c1';  -- Gama
  if v_n <> 0 then
    raise exception '[FAIL] USER_AB leu colaborador de Gama (sem membership)';
  end if;
  raise notice '[PASS] multi-tenant: USER_AB le Alfa+Beta e nao le Gama (sem membership)';
end $$;

reset role;

-- ============================================================================
-- 6) USER_INACTIVE (membership Alfa disabled) e USER_NONE (sem membership)
-- ============================================================================

select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a4', false);
set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 0 then
    raise exception '[FAIL] membership disabled ainda concede leitura (% linha(s))', v_n;
  end if;
  raise notice '[PASS] membership disabled remove acesso (deny-by-default)';
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'd8b00000-0000-0000-0000-0000000000a5', false);
set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 0 then
    raise exception '[FAIL] usuario sem membership leu estrutura (% linha(s))', v_n;
  end if;
  select count(*) into v_n from public.user_profiles;
  if v_n <> 1 then
    raise exception '[FAIL] usuario sem membership deveria ler somente o proprio profile';
  end if;
  raise notice '[PASS] usuario sem membership nao le estrutura; le somente o proprio profile';
end $$;

reset role;

-- ============================================================================
-- 7) anon sem acesso a dados privados
-- ============================================================================

set role anon;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 0 then
    raise exception '[FAIL] anon leu colaboradores (% linha(s))', v_n;
  end if;
  select count(*) into v_n from public.capabilities;
  if v_n <> 0 then
    raise exception '[FAIL] anon leu capabilities (% linha(s))', v_n;
  end if;
  raise notice '[PASS] anon sem acesso a dados privados (collaborators/capabilities vazios)';
end $$;

reset role;

-- ============================================================================
-- 8) Limpeza do cenário sintético
-- ============================================================================

delete from public.evaluation_succession_events
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.cycle_evaluation_responsibilities
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshots
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
where collaborator_id::text like 'd8c00000-0000-0000-0000-0000000000%';

delete from public.organizational_positions
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.organizational_units
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id::text like 'd8c00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.user_organization_memberships
where id::text like 'd8d00000-0000-0000-0000-0000000000%';

delete from public.user_profiles
where id::text like 'd8b00000-0000-0000-0000-0000000000%';

delete from auth.users
where id::text like 'd8b00000-0000-0000-0000-0000000000%';

delete from public.organizations
where id::text like 'd8a00000-0000-0000-0000-0000000000%';

do $$
begin
  if exists (select 1 from public.collaborators where id::text like 'd8c00000%') then
    raise exception '[FAIL] limpeza do cenario F4-08 incompleta (collaborators)';
  end if;
  if exists (select 1 from public.organizations where id::text like 'd8a00000%') then
    raise exception '[FAIL] limpeza do cenario F4-08 incompleta (organizations)';
  end if;
  raise notice '[PASS] cenario sintetico F4-08 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F4-08: todas as verificacoes passaram (schema guard, triggers, RLS own-tenant, cross-tenant, multi-tenant, grants).';
end $$;
