-- ============================================================================
-- F4-01 (Issue #88): validação automatizada — capabilities e access_roles
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f4-01.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f4-01.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f4-01.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; qualquer falha levanta
-- exceção e aborta com código de saída não-zero. O script NÃO toca projeto
-- remoto, NÃO altera policies e remove ao final os dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Estrutura: tabelas novas presentes, RLS habilitado, zero policies
-- ============================================================================

do $$
declare
  v_tabela text;
  v_tabelas text[] := array[
    'capabilities',
    'access_roles',
    'access_role_capabilities',
    'membership_access_role_assignments'
  ];
begin
  foreach v_tabela in array v_tabelas loop
    if not exists (
      select 1 from pg_tables t
      where t.schemaname = 'public' and t.tablename = v_tabela
    ) then
      raise exception '[FAIL] tabela F4-01 ausente: %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] tabelas F4-01 presentes (capabilities, access_roles, access_role_capabilities, membership_access_role_assignments)';
end $$;

do $$
declare
  v_tabela text;
  v_tabelas text[] := array[
    'capabilities',
    'access_roles',
    'access_role_capabilities',
    'membership_access_role_assignments'
  ];
begin
  foreach v_tabela in array v_tabelas loop
    if not exists (
      select 1 from pg_class c
      where c.oid = (quote_ident('public') || '.' || quote_ident(v_tabela))::regclass
        and c.relrowsecurity = true
    ) then
      raise exception '[FAIL] RLS nao habilitado em %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] RLS habilitado nas quatro tabelas F4-01';
end $$;

do $$
begin
  if exists (
    select 1 from pg_policies p
    where p.schemaname = 'public'
      and p.tablename in (
        'capabilities', 'access_roles', 'access_role_capabilities',
        'membership_access_role_assignments'
      )
  ) then
    raise exception '[FAIL] existe policy nas tabelas F4-01 (deny-by-default violado)';
  end if;
  raise notice '[PASS] zero policies nas quatro tabelas F4-01 (deny-by-default estrutural)';
end $$;

-- ============================================================================
-- 2) Colunas exatas das quatro tabelas
-- ============================================================================

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name) into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'capabilities';
  if v_cols is distinct from
     array['code','created_at','description','id','name','status','updated_at','version']::text[]
  then
    raise exception '[FAIL] capabilities: colunas fora do contrato (id/code/name/description/status/timestamps/version)';
  end if;

  select array_agg(column_name order by column_name) into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'access_roles';
  if v_cols is distinct from
     array['created_at','id','is_system','name','organization_id','status','updated_at','version']::text[]
  then
    raise exception '[FAIL] access_roles: colunas fora do contrato';
  end if;

  select array_agg(column_name order by column_name) into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'access_role_capabilities';
  if v_cols is distinct from
     array['access_role_id','capability_id','created_at','id','updated_at','version']::text[]
  then
    raise exception '[FAIL] access_role_capabilities: colunas fora do contrato';
  end if;

  select array_agg(column_name order by column_name) into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'membership_access_role_assignments';
  if v_cols is distinct from
     array['access_role_id','created_at','created_by','id','membership_id','organization_id','status','updated_at','version']::text[]
  then
    raise exception '[FAIL] membership_access_role_assignments: colunas fora do contrato';
  end if;

  raise notice '[PASS] colunas exatas das quatro tabelas F4-01 (contrato docs/F4-01)';
end $$;

-- ============================================================================
-- 3) Constraints, triggers e funções esperadas
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'uq_user_organization_memberships_id_organization',
    'pk_capabilities', 'uq_capabilities_code', 'ck_capabilities_code',
    'ck_capabilities_name', 'ck_capabilities_status',
    'pk_access_roles', 'uq_access_roles_organization_name',
    'fk_access_roles_organizations', 'ck_access_roles_name',
    'ck_access_roles_status', 'ck_access_roles_system_scope',
    'pk_access_role_capabilities', 'uq_access_role_capabilities_role_capability',
    'fk_access_role_capabilities_roles', 'fk_access_role_capabilities_capabilities',
    'pk_membership_access_role_assignments',
    'uq_membership_access_role_assignments_membership_role',
    'fk_membership_access_role_assignments_memberships',
    'fk_membership_access_role_assignments_membership_organization',
    'fk_membership_access_role_assignments_roles',
    'fk_membership_access_role_assignments_author',
    'ck_membership_access_role_assignments_status'
  );
  if v_n <> 23 then
    raise exception '[FAIL] constraints F4-01 esperadas=23, encontradas=%', v_n;
  end if;
  raise notice '[PASS] constraints pk/unique/fk/check esperadas presentes (23)';
end $$;

do $$
begin
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public' and tablename = 'access_roles'
      and indexname = 'uq_access_roles_system_name'
  ) then
    raise exception '[FAIL] indice parcial uq_access_roles_system_name ausente';
  end if;
  raise notice '[PASS] unicidade parcial de nome das roles de sistema presente (uq_access_roles_system_name)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgname in (
      'trg_capabilities_updated_at',
      'trg_access_roles_updated_at',
      'trg_access_role_capabilities_updated_at',
      'trg_membership_access_role_assignments_updated_at',
      'trg_membership_access_role_assignments_role_organization'
    );
  if v_n <> 5 then
    raise exception '[FAIL] triggers F4-01 esperados=5, encontrados=%', v_n;
  end if;
  raise notice '[PASS] triggers de updated_at e de tenant da role presentes (5)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'conceder_acesso_role',
      'revogar_acesso_role',
      'resolver_capabilities_efetivas',
      'enforce_membership_role_within_organization'
    );
  if v_n <> 4 then
    raise exception '[FAIL] funcoes F4-01 esperadas=4, encontradas=%', v_n;
  end if;
  raise notice '[PASS] funcoes F4-01 presentes (conceder/revogar/resolver/enforce)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('conceder_acesso_role', 'revogar_acesso_role', 'resolver_capabilities_efetivas')
    and not p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] funcao de atribuicao/resolucao sem SECURITY DEFINER (server-side)';
  end if;
  raise notice '[PASS] funcoes de atribuicao/resolucao sao SECURITY DEFINER (server-side)';
end $$;

-- ============================================================================
-- 4) Independência estrutural: cargo/collaborator/occupation NÃO concedem
--    capability (nenhuma FK entre autorização e estrutura F3)
-- ============================================================================

do $$
begin
  if exists (
    select 1 from pg_constraint c
    where c.contype = 'f'
      and c.conrelid in (
        'public.capabilities'::regclass,
        'public.access_roles'::regclass,
        'public.access_role_capabilities'::regclass,
        'public.membership_access_role_assignments'::regclass
      )
      and c.confrelid in (
        'public.job_roles'::regclass,
        'public.seniority_levels'::regclass,
        'public.collaborators'::regclass,
        'public.organizational_positions'::regclass,
        'public.occupations'::regclass,
        'public.temporary_responsibilities'::regclass
      )
  ) then
    raise exception '[FAIL] FK da autorizacao para estrutura F3 (cargo/collaborator/occupation concede acesso)';
  end if;
  raise notice '[PASS] nenhuma FK entre o modelo de autorizacao e job_roles/seniority/collaborators/positions/occupations';
end $$;

do $$
begin
  if exists (
    select 1 from pg_constraint c
    where c.contype = 'f'
      and c.confrelid in (
        'public.capabilities'::regclass,
        'public.access_roles'::regclass,
        'public.access_role_capabilities'::regclass,
        'public.membership_access_role_assignments'::regclass
      )
      and c.conrelid in (
        'public.job_roles'::regclass,
        'public.seniority_levels'::regclass,
        'public.collaborators'::regclass,
        'public.organizational_positions'::regclass,
        'public.occupations'::regclass
      )
  ) then
    raise exception '[FAIL] estrutura F3 referencia autorizacao (acoplamento indevido)';
  end if;
  raise notice '[PASS] estrutura F3 nao referencia o modelo de autorizacao (acoplamento zero)';
end $$;

-- ============================================================================
-- 5) Catálogo de sistema determinístico (D9/D16)
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.capabilities;
  if v_n <> 21 then
    raise exception '[FAIL] catalogo de capabilities deveria ter 21 linhas, encontrado %', v_n;
  end if;
  select count(distinct code) into v_n from public.capabilities;
  if v_n <> 21 then
    raise exception '[FAIL] codigos de capability nao sao unicos';
  end if;
  raise notice '[PASS] catalogo global com 21 capabilities e codigos unicos (deterministico)';
end $$;

do $$
declare
  v_n int;
  v_id uuid;
begin
  select count(*) into v_n
  from public.access_roles
  where id = 'c0000000-0000-4000-8000-0000000000f1'
    and name = 'admin' and is_system = true
    and organization_id is null and status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] access_role de sistema admin ausente ou inconsistente';
  end if;
  raise notice '[PASS] access_role de sistema admin (is_system, organization_id null, active) presente';
end $$;

do $$
declare
  v_codes text[];
  v_esperado text[] := array[
    'access_role.manage','collaborator.manage','collaborator.read','cycle.read',
    'membership.manage','membership.read','org.catalog.manage',
    'org.structure.manage','settings.manage'
  ]::text[];
begin
  select array_agg(c.code order by c.code) into v_codes
  from public.access_role_capabilities rc
  join public.capabilities c on c.id = rc.capability_id
  where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1';

  if v_codes is distinct from v_esperado then
    raise exception '[FAIL] bundle admin divergente do contrato D14';
  end if;
  raise notice '[PASS] bundle admin = 9 capabilities de administracao (sem conteudo confidencial)';
end $$;

-- ============================================================================
-- 6) Resolução de capabilities efetivas (cenário)
-- ============================================================================

do $$
declare
  v_codes text[];
  v_esperado text[] := array[
    'access_role.manage','collaborator.manage','collaborator.read','cycle.read',
    'membership.manage','membership.read','org.catalog.manage',
    'org.structure.manage','settings.manage'
  ]::text[];
begin
  select array_agg(capability_code order by capability_code) into v_codes
  from public.resolver_capabilities_efetivas(
    'd0b00000-0000-0000-0000-0000000000a1',
    'd0a00000-0000-0000-0000-0000000000a1'
  );
  if v_codes is distinct from v_esperado then
    raise exception '[FAIL] resolver de ADMIN_A/Alfa divergente';
  end if;
  raise notice '[PASS] ADMIN_A (sem collaborator) resolve as 9 capabilities de administracao em Alfa';
end $$;

do $$
declare
  v_codes text[];
begin
  select array_agg(capability_code order by capability_code) into v_codes
  from public.resolver_capabilities_efetivas(
    'd0b00000-0000-0000-0000-0000000000a2',
    'd0a00000-0000-0000-0000-0000000000b1'
  );
  if v_codes is distinct from array[
    'access_role.manage','collaborator.manage','collaborator.read','cycle.read',
    'membership.manage','membership.read','org.catalog.manage',
    'org.structure.manage','settings.manage'
  ]::text[] then
    raise exception '[FAIL] resolver de ADMIN_B/Beta divergente (role de sistema deveria valer em qualquer org)';
  end if;
  raise notice '[PASS] ADMIN_B resolve admin em Beta (role de sistema atribuivel por membership em qualquer organizacao)';
end $$;

do $$
declare
  v_codes text[];
begin
  select array_agg(capability_code order by capability_code) into v_codes
  from public.resolver_capabilities_efetivas(
    'd0b00000-0000-0000-0000-0000000000a3',
    'd0a00000-0000-0000-0000-0000000000a1'
  );
  if v_codes is distinct from array['cycle.manage','report.read']::text[] then
    raise exception '[FAIL] uniao de multiplas roles divergente (esperado cycle.manage+report.read)';
  end if;
  raise notice '[PASS] multiplas roles produzem a uniao esperada (COLLAB_USER = cycle.manage + report.read)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd0b00000-0000-0000-0000-0000000000a4',
    'd0a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then
    raise exception '[FAIL] membro sem atribuicao deveria resolver vazio (cargo/collaborator nao concedem)';
  end if;
  raise notice '[PASS] membro sem atribuicao resolve vazio (job_role/collaborator nao concedem capability)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd0b00000-0000-0000-0000-0000000000a1',
    'd0a00000-0000-0000-0000-0000000000b1'
  );
  if v_n <> 0 then
    raise exception '[FAIL] usuario sem membership em Beta deveria resolver vazio';
  end if;
  raise notice '[PASS] usuario sem membership na organizacao resolve vazio (tenant isolation)';
end $$;

-- ============================================================================
-- 7) Cross-tenant: role customizada de Alfa não pode ser atribuída em Beta
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role(
      'd0d00000-0000-0000-0000-0000000000a2',  -- membership Beta (ADMIN_B)
      'd0c00000-0000-0000-0000-0000000000c1',  -- role customizada de Alfa (ciclos)
      'd0b00000-0000-0000-0000-0000000000a2'
    );
  exception when raise_exception then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] atribuicao cross-organization NAO foi rejeitada pelo mecanismo server-side';
  end if;
  raise notice '[PASS] role customizada da Organizacao A nao pode ser atribuida a membership da Organizacao B (conceder rejeita)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.membership_access_role_assignments
      (membership_id, organization_id, access_role_id, created_by)
    values
      ('d0d00000-0000-0000-0000-0000000000a4',  -- membership Alfa (SEM_ROLE, sem atribuicoes)
       'd0a00000-0000-0000-0000-0000000000b1',  -- org Beta (inconsistente com a membership)
       'c0000000-0000-4000-8000-0000000000f1',  -- admin (sistema; trigger passa)
       'd0b00000-0000-0000-0000-0000000000a2');
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] organization_id inconsistente com a membership NAO foi rejeitado por FK composta';
  end if;
  raise notice '[PASS] organization_id da atribuicao e garantido igual ao da membership por FK composta (cross-tenant por construcao)';
end $$;

-- ============================================================================
-- 8) Status/lifecycle: membership e perfil desabilitados não produzem
--    autorização efetiva
-- ============================================================================

do $$
declare
  v_n int;
begin
  update public.user_organization_memberships
     set status = 'disabled'
   where id = 'd0d00000-0000-0000-0000-0000000000a3';

  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd0b00000-0000-0000-0000-0000000000a3',
    'd0a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then
    raise exception '[FAIL] membership desabilitada ainda resolve capabilities';
  end if;
  raise notice '[PASS] membership desabilitada nao produz autorizacao efetiva (resolver vazio)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role(
      'd0d00000-0000-0000-0000-0000000000a3',
      'c0000000-0000-4000-8000-0000000000f1',
      'd0b00000-0000-0000-0000-0000000000a1'
    );
  exception when raise_exception then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] concessao a membership desabilitada NAO foi rejeitada';
  end if;
  update public.user_organization_memberships
     set status = 'active'
   where id = 'd0d00000-0000-0000-0000-0000000000a3';
  raise notice '[PASS] concessao a membership desabilitada rejeitada (membership ativa e pre-condicao)';
end $$;

do $$
declare
  v_n int;
begin
  update public.user_profiles
     set status = 'disabled'
   where id = 'd0b00000-0000-0000-0000-0000000000a3';

  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd0b00000-0000-0000-0000-0000000000a3',
    'd0a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then
    raise exception '[FAIL] perfil desabilitado ainda resolve capabilities';
  end if;
  update public.user_profiles
     set status = 'active'
   where id = 'd0b00000-0000-0000-0000-0000000000a3';
  raise notice '[PASS] perfil desabilitado nao produz autorizacao efetiva (resolver vazio)';
end $$;

-- ============================================================================
-- 9) ADMIN não contém capability confidencial (D18)
-- ============================================================================

do $$
begin
  if exists (
    select 1 from public.capabilities c
    where lower(c.code) like '%confidential%'
  ) then
    raise exception '[FAIL] existe capability confidencial generica no catalogo (D18 violado)';
  end if;
  raise notice '[PASS] nenhuma capability confidencial generica (confidential.*) no catalogo';
end $$;

do $$
begin
  if exists (
    select 1
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
    where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
      and c.code in ('evaluation.read', 'evaluation.create', 'evaluation.write',
                     'evaluation.cancel', 'evaluation.reopen',
                     'goal.read', 'goal.write', 'goal.approve',
                     'observation.read', 'observation.write', 'report.read')
  ) then
    raise exception '[FAIL] bundle admin contem capability de conteudo confidencial';
  end if;
  raise notice '[PASS] bundle admin nao contem capability de leitura de conteudo (avaliacoes/metas/observacoes/relatorios)';
end $$;

-- ============================================================================
-- 10) Sem exclusão física indevida (catálogos/atribuições)
-- ============================================================================

do $$
declare
  v_n int;
begin
  perform public.revogar_acesso_role(
    'd0d00000-0000-0000-0000-0000000000a3',
    'd0c00000-0000-0000-0000-0000000000c1',
    'd0b00000-0000-0000-0000-0000000000a1'
  );

  select count(*) into v_n
  from public.membership_access_role_assignments
  where membership_id = 'd0d00000-0000-0000-0000-0000000000a3'
    and access_role_id = 'd0c00000-0000-0000-0000-0000000000c1'
    and status = 'revoked';
  if v_n <> 1 then
    raise exception '[FAIL] revogacao deveria preservar a linha com status revoked';
  end if;
  raise notice '[PASS] revogacao preserva a atribuicao (status revoked; sem exclusao fisica)';
end $$;

do $$
declare
  v_codes text[];
begin
  select array_agg(capability_code order by capability_code) into v_codes
  from public.resolver_capabilities_efetivas(
    'd0b00000-0000-0000-0000-0000000000a3',
    'd0a00000-0000-0000-0000-0000000000a1'
  );
  if v_codes is distinct from array['report.read']::text[] then
    raise exception '[FAIL] role revogada ainda concede capability';
  end if;
  raise notice '[PASS] role revogada deixa de conceder capability (resolver = report.read apenas)';
end $$;

do $$
declare
  v_n int;
begin
  perform public.conceder_acesso_role(
    'd0d00000-0000-0000-0000-0000000000a3',
    'd0c00000-0000-0000-0000-0000000000c1',
    'd0b00000-0000-0000-0000-0000000000a1'
  );

  select count(*) into v_n
  from public.membership_access_role_assignments
  where membership_id = 'd0d00000-0000-0000-0000-0000000000a3'
    and access_role_id = 'd0c00000-0000-0000-0000-0000000000c1';
  if v_n <> 1 then
    raise exception '[FAIL] reativacao deveria reusar a linha (sem duplicar)';
  end if;
  raise notice '[PASS] reativacao no lugar (uma linha por par membership/role; historico preservado)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    delete from public.access_roles
    where id = 'c0000000-0000-4000-8000-0000000000f1';
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] exclusao fisica de role com atribuicoes NAO foi bloqueada (FK RESTRICT)';
  end if;
  raise notice '[PASS] exclusao fisica de access_role com atribuicoes bloqueada (FK RESTRICT)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    delete from public.capabilities
    where code = 'membership.read';
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] exclusao fisica de capability em uso NAO foi bloqueada (FK RESTRICT)';
  end if;
  raise notice '[PASS] exclusao fisica de capability em uso por role bloqueada (FK RESTRICT)';
end $$;

-- ============================================================================
-- 11) RLS deny-by-default em execução (como authenticated)
-- ============================================================================

set role authenticated;

do $$
declare
  v_n int;
  v_tabela text;
  v_tabelas text[] := array[
    'capabilities', 'access_roles', 'access_role_capabilities',
    'membership_access_role_assignments'
  ];
begin
  foreach v_tabela in array v_tabelas loop
    execute format('select count(*) from public.%I', v_tabela) into v_n;
    if v_n <> 0 then
      raise exception '[FAIL] authenticated enxergou linhas de %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] RLS: authenticated nao le linhas das quatro tabelas F4-01';
end $$;

do $$
begin
  begin
    insert into public.capabilities (code, name)
    values ('x.probe', 'Probe RLS');
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em capabilities';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated em capabilities negado (row-level security)';
end $$;

do $$
declare
  v_n int;
begin
  update public.access_roles set version = version + 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu UPDATE de authenticated em access_roles (%)', v_n;
  end if;
  raise notice '[PASS] RLS: UPDATE de authenticated em access_roles afeta zero linhas';
end $$;

do $$
declare
  v_n int;
begin
  delete from public.membership_access_role_assignments;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu DELETE de authenticated em membership_access_role_assignments (%)', v_n;
  end if;
  raise notice '[PASS] RLS: DELETE de authenticated em membership_access_role_assignments afeta zero linhas';
end $$;

do $$
begin
  begin
    perform 1 from public.resolver_capabilities_efetivas(
      'd0b00000-0000-0000-0000-0000000000a1',
      'd0a00000-0000-0000-0000-0000000000a1'
    );
    raise exception '[FAIL] authenticated conseguiu executar resolver_capabilities_efetivas';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] authenticated nao executa resolver_capabilities_efetivas (EXECUTE so service_role)';
end $$;

reset role;

-- ============================================================================
-- 12) Regressões: policies e RLS anteriores intactas
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_policies p where p.schemaname = 'public';
  if v_n <> 3 then
    raise exception '[FAIL] quantidade de policies alterada (esperado 3, encontrado %)', v_n;
  end if;
  raise notice '[PASS] 3 policies de identidade/sessao da F2 inalteradas';
end $$;

do $$
begin
  if exists (
    select 1 from pg_class c
    where c.oid in (
      'public.collaborators'::regclass,
      'public.job_roles'::regclass,
      'public.organizations'::regclass,
      'public.user_profiles'::regclass,
      'public.user_organization_memberships'::regclass
    )
    and c.relrowsecurity = false
  ) then
    raise exception '[FAIL] RLS de tabelas pre-existentes foi enfraquecido';
  end if;
  raise notice '[PASS] RLS das tabelas pre-existentes (F2/F3) permanece habilitado';
end $$;

-- ============================================================================
-- 13) Limpeza do cenário sintético (banco local permanece limpo; catálogo de
--     sistema da migration permanece intacto)
-- ============================================================================

delete from public.membership_access_role_assignments
where organization_id in (
  'd0a00000-0000-0000-0000-0000000000a1',
  'd0a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_capabilities
where access_role_id in (
  'd0c00000-0000-0000-0000-0000000000c1',
  'd0c00000-0000-0000-0000-0000000000c2'
);

delete from public.access_roles
where id in (
  'd0c00000-0000-0000-0000-0000000000c1',
  'd0c00000-0000-0000-0000-0000000000c2'
);

delete from public.user_organization_memberships
where organization_id in (
  'd0a00000-0000-0000-0000-0000000000a1',
  'd0a00000-0000-0000-0000-0000000000b1'
);

delete from public.user_profiles
where id::text like 'd0b00000-0000-0000-0000-0000000000%';

delete from auth.users
where id::text like 'd0b00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id = 'd0c00000-0000-0000-0000-0000000000e1';

delete from public.job_roles
where organization_id = 'd0a00000-0000-0000-0000-0000000000a1';

delete from public.organizations
where id in (
  'd0a00000-0000-0000-0000-0000000000a1',
  'd0a00000-0000-0000-0000-0000000000b1'
);

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.capabilities;
  if v_n <> 21 then
    raise exception '[FAIL] catalogo de sistema (migration) foi alterado pela limpeza (% capabilities)', v_n;
  end if;
  select count(*) into v_n
  from public.access_role_capabilities
  where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    raise exception '[FAIL] bundle admin (migration) foi alterado pela limpeza';
  end if;
  select count(*) into v_n
  from public.membership_access_role_assignments
  where organization_id::text like 'd0a00000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F4-01 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F4-01 removido ao final; catalogo de sistema (migration) intacto';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F4-01: todas as verificacoes passaram (catalogos, roles, constraints, triggers, RLS, cross-tenant, lifecycle).';
end $$;
