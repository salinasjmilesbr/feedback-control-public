-- ============================================================================
-- F4-02 (Issue #89): validação automatizada — escopos de autorização
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f4-02.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f4-02.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f4-02.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; falha aborta (código
-- não-zero). NÃO toca projeto remoto, NÃO altera policies e remove ao final os
-- dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Estrutura: tabelas/constraints/triggers/funções F4-02
-- ============================================================================

do $$
declare
  v_tabela text;
  v_tabelas text[] := array[
    'membership_collaborator_links',
    'access_role_assignment_scopes',
    'access_role_assignment_unit_targets'
  ];
begin
  foreach v_tabela in array v_tabelas loop
    if not exists (select 1 from pg_tables t where t.schemaname='public' and t.tablename=v_tabela) then
      raise exception '[FAIL] tabela F4-02 ausente: %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] tabelas F4-02 presentes (links, scopes, unit targets)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_constraint
  where conname in (
    'uq_membership_access_role_assignments_id_organization',
    'pk_membership_collaborator_links',
    'fk_membership_collaborator_links_memberships',
    'fk_membership_collaborator_links_membership_organization',
    'fk_membership_collaborator_links_collaborators',
    'ck_membership_collaborator_links_status',
    'pk_access_role_assignment_scopes',
    'uq_access_role_assignment_scopes_id_organization',
    'uq_access_role_assignment_scopes_assignment_type',
    'fk_access_role_assignment_scopes_assignments',
    'fk_access_role_assignment_scopes_assignment_organization',
    'fk_access_role_assignment_scopes_author',
    'ck_access_role_assignment_scopes_type',
    'ck_access_role_assignment_scopes_status',
    'pk_access_role_assignment_unit_targets',
    'uq_access_role_assignment_unit_targets_scope_unit',
    'fk_access_role_assignment_unit_targets_scopes',
    'fk_access_role_assignment_unit_targets_units'
  );
  if v_n <> 18 then
    raise exception '[FAIL] constraints F4-02 esperadas=18, encontradas=%', v_n;
  end if;
  raise notice '[PASS] constraints pk/unique/fk/check esperadas presentes (18)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname in (
    'resolver_collaborador_vinculado',
    'resolver_capabilities_escopos_efetivas',
    'resolver_alvos_escopo',
    'enforce_unit_target_scope_type'
  );
  if v_n <> 4 then
    raise exception '[FAIL] funcoes F4-02 esperadas=4, encontradas=%', v_n;
  end if;
  raise notice '[PASS] funcoes F4-02 presentes (vinculado/capabilities-escopos/alvos/enforce)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public'
    and p.proname in ('resolver_collaborador_vinculado',
                      'resolver_capabilities_escopos_efetivas',
                      'resolver_alvos_escopo')
    and p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] resolver de escopo deveria ser SECURITY INVOKER (D18)';
  end if;
  raise notice '[PASS] resolvers de escopo sao SECURITY INVOKER (sem DEFINER novo)';
end $$;

-- ============================================================================
-- 2) Cenário: vínculo, scopes e capabilities × scope
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_collaborador_vinculado(
    'd1b00000-0000-0000-0000-0000000000a2',
    'd1a00000-0000-0000-0000-0000000000a1');
  if v_n <> 1 then
    raise exception '[FAIL] MANAGER deveria ter exatamente 1 colaborador vinculado (%)', v_n;
  end if;
  raise notice '[PASS] MANAGER resolve o colaborador vinculado (GER)';
end $$;

do $$
declare
  v_codes text[];
begin
  -- MANAGER: gestao_equipe = collaborator.read + evaluation.read × 3 scopes
  select array_agg(capability_code || ':' || scope_type order by capability_code, scope_type)
    into v_codes
  from public.resolver_capabilities_escopos_efetivas(
    'd1b00000-0000-0000-0000-0000000000a2',
    'd1a00000-0000-0000-0000-0000000000a1');
  if v_codes is distinct from array[
    'collaborator.read:DESCENDANTS','collaborator.read:DIRECT_REPORTS','collaborator.read:ORGANIZATIONAL_UNIT',
    'evaluation.read:DESCENDANTS','evaluation.read:DIRECT_REPORTS','evaluation.read:ORGANIZATIONAL_UNIT'
  ]::text[] then
    raise exception '[FAIL] capabilities×scopes do MANAGER divergentes';
  end if;
  raise notice '[PASS] mesma capability opera com scopes diferentes (collaborator.read × 3 scopes)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1',
    'SELF', null, '2024-12-01T00:00:00Z');
  if v_n <> 1 then
    raise exception '[FAIL] SELF deveria resolver 1 alvo (colaborador vinculado)';
  end if;
  raise notice '[PASS] SELF resolve somente o colaborador vinculado';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a3', 'd1a00000-0000-0000-0000-0000000000a1',
    'DESCENDANTS', null, '2024-12-01T00:00:00Z');
  if v_n <> 0 then
    raise exception '[FAIL] usuario sem vinculo deveria falhar fechado em DESCENDANTS';
  end if;
  raise notice '[PASS] usuario sem vinculo collaborator falha fechado nos scopes estruturais';
end $$;

do $$
declare
  v_cids uuid[];
begin
  select array_agg(collaborator_id order by collaborator_id) into v_cids
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1',
    'DIRECT_REPORTS', null, '2024-12-01T00:00:00Z');
  if v_cids is distinct from array['d1c00000-0000-0000-0000-0000000000c3']::uuid[] then
    raise exception '[FAIL] DIRECT_REPORTS deveria resolver somente COORD';
  end if;
  raise notice '[PASS] DIRECT_REPORTS usa reporting line (somente COORD), nao job_role';
end $$;

do $$
declare
  v_pos uuid[];
begin
  select array_agg(position_id order by position_id) into v_pos
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1',
    'DESCENDANTS', null, '2024-12-01T00:00:00Z')
  where position_id is not null;
  if v_pos is distinct from array[
    'd1e00000-0000-0000-0000-0000000000e2',
    'd1e00000-0000-0000-0000-0000000000e3',
    'd1e00000-0000-0000-0000-0000000000e4',
    'd1e00000-0000-0000-0000-0000000000e5',
    'd1e00000-0000-0000-0000-0000000000e6',
    'd1e00000-0000-0000-0000-0000000000e8'
  ]::uuid[] then
    raise exception '[FAIL] DESCENDANTS divergente da arvore F3 esperada';
  end if;
  raise notice '[PASS] DESCENDANTS resolve a arvore F3 completa (6 posicoes)';
end $$;

do $$
declare
  v_cids uuid[];
begin
  select array_agg(collaborator_id order by collaborator_id) into v_cids
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a4', 'd1a00000-0000-0000-0000-0000000000a1',
    'DESCENDANTS', null, '2024-12-01T00:00:00Z');
  if v_cids is distinct from array['d1c00000-0000-0000-0000-0000000000c8']::uuid[] then
    raise exception '[FAIL] uniao de multiplas positions divergente (esperado MULTI_CHILD)';
  end if;
  raise notice '[PASS] multiplas positions produzem uniao correta (MULTI = 2 positions -> MULTI_CHILD)';
end $$;

do $$
declare
  v_cids uuid[];
begin
  select array_agg(collaborator_id order by collaborator_id) into v_cids
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1',
    'ORGANIZATIONAL_UNIT', 'd1e00000-0000-0000-0000-0000000000c1', '2024-12-01T00:00:00Z');
  if v_cids is distinct from array[
    'd1c00000-0000-0000-0000-0000000000c1',
    'd1c00000-0000-0000-0000-0000000000c2'
  ]::uuid[] then
    raise exception '[FAIL] UNIT(u1) deveria alcancar somente DIR e GER (sem subunidades)';
  end if;
  raise notice '[PASS] ORGANIZATIONAL_UNIT alcanca somente a unidade explicita (DIR+GER; sem subunidade)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a1', 'd1a00000-0000-0000-0000-0000000000a1',
    'ORGANIZATION', null, '2024-12-01T00:00:00Z');
  if v_n <> 7 then
    raise exception '[FAIL] ORGANIZATION deveria alcancar 7 colaboradores de Alfa (%)', v_n;
  end if;
  raise notice '[PASS] ORGANIZATION permanece limitado ao tenant (7 colaboradores de Alfa)';
end $$;

do $$
begin
  if exists (
    select 1 from public.resolver_capabilities_escopos_efetivas(
      'd1b00000-0000-0000-0000-0000000000a1', 'd1a00000-0000-0000-0000-0000000000a1')
    where capability_code in ('evaluation.read','goal.read','observation.read','report.read')
  ) then
    raise exception '[FAIL] ADMIN+ORGANIZATION resolve capability de conteudo confidencial';
  end if;
  raise notice '[PASS] ADMIN + ORGANIZATION nao cria capability confidencial (bundle admin intacto)';
end $$;

-- ============================================================================
-- 3) Fail-closed: assignment sem scope; ASSIGNED não vira hierarquia
-- ============================================================================

do $$
declare
  v_n int;
begin
  perform public.conceder_acesso_role(
    'd1d00000-0000-0000-0000-0000000000a5',
    'c0000000-0000-4000-8000-0000000000f1',
    'd1b00000-0000-0000-0000-0000000000a5');

  select count(*) into v_n
  from public.resolver_capabilities_escopos_efetivas(
    'd1b00000-0000-0000-0000-0000000000a5', 'd1a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] assignment sem scope deveria resolver vazio (%)', v_n;
  end if;
  raise notice '[PASS] assignment sem scope resolve vazio (fail-closed)';
end $$;

do $$
declare
  v_n int;
begin
  insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
  select a.id, a.organization_id, 'ASSIGNED', 'active', 'd1b00000-0000-0000-0000-0000000000a5'
    from public.membership_access_role_assignments a
   where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a5';

  select count(*) into v_n
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a5', 'd1a00000-0000-0000-0000-0000000000a1',
    'ASSIGNED', null, '2024-12-01T00:00:00Z');
  if v_n <> 0 then
    raise exception '[FAIL] ASSIGNED nao deveria derivar alvo estrutural (colegiado nao e hierarquia)';
  end if;
  raise notice '[PASS] ASSIGNED nao transforma colegiado em hierarquia (resolucao vazia na F4-02)';
end $$;

-- ============================================================================
-- 4) Cross-tenant bloqueado
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.membership_collaborator_links (membership_id, organization_id, collaborator_id)
    values ('d1d00000-0000-0000-0000-0000000000a3', 'd1a00000-0000-0000-0000-0000000000a1',
            'd1c00000-0000-0000-0000-0000000000d1');  -- colaborador de Beta
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] vinculo com colaborador de outra organizacao NAO foi bloqueado';
  end if;
  raise notice '[PASS] vinculo membership->collaborator cross-tenant bloqueado (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
    select a.id, 'd1a00000-0000-0000-0000-0000000000b1', 'ORGANIZATION', 'active', 'd1b00000-0000-0000-0000-0000000000a5'
      from public.membership_access_role_assignments a
     where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a1'
     limit 1;
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] scope com organization_id inconsistente NAO foi bloqueado';
  end if;
  raise notice '[PASS] scope com organization_id inconsistente bloqueado (FK composta)';
end $$;

-- ============================================================================
-- 5) Lifecycle: membership/profile disabled; revogação pai e granular
-- ============================================================================

do $$
declare
  v_n int;
begin
  update public.user_organization_memberships set status='disabled'
   where id='d1d00000-0000-0000-0000-0000000000a2';
  select count(*) into v_n
  from public.resolver_capabilities_escopos_efetivas(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] membership desabilitada ainda resolve';
  end if;
  update public.user_organization_memberships set status='active'
   where id='d1d00000-0000-0000-0000-0000000000a2';
  raise notice '[PASS] membership disabled resolve vazio';
end $$;

do $$
declare
  v_n int;
begin
  update public.user_profiles set status='disabled'
   where id='d1b00000-0000-0000-0000-0000000000a2';
  select count(*) into v_n
  from public.resolver_capabilities_escopos_efetivas(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] perfil desabilitado ainda resolve';
  end if;
  update public.user_profiles set status='active'
   where id='d1b00000-0000-0000-0000-0000000000a2';
  raise notice '[PASS] profile disabled resolve vazio';
end $$;

do $$
declare
  v_n int;
begin
  perform public.revogar_acesso_role(
    'd1d00000-0000-0000-0000-0000000000a2', 'd1f00000-0000-0000-0000-0000000000f1',
    'd1b00000-0000-0000-0000-0000000000a5');

  select count(*) into v_n
  from public.resolver_capabilities_escopos_efetivas(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] revogacao da assignment nao invalidou os scopes filhos';
  end if;

  select count(*) into v_n
  from public.access_role_assignment_scopes s
  join public.membership_access_role_assignments a on a.id = s.assignment_id
  where a.membership_id='d1d00000-0000-0000-0000-0000000000a2';
  if v_n <> 3 then
    raise exception '[FAIL] revogacao deveria preservar as linhas de scope (%)', v_n;
  end if;

  perform public.conceder_acesso_role(
    'd1d00000-0000-0000-0000-0000000000a2', 'd1f00000-0000-0000-0000-0000000000f1',
    'd1b00000-0000-0000-0000-0000000000a5');
  raise notice '[PASS] revogacao do pai invalida scopes filhos e preserva linhas (reativacao restaura)';
end $$;

do $$
declare
  v_n int;
begin
  update public.access_role_assignment_scopes s
     set status='revoked'
  from public.membership_access_role_assignments a
   where a.id = s.assignment_id
     and a.membership_id='d1d00000-0000-0000-0000-0000000000a2'
     and s.scope_type='DESCENDANTS';

  select count(*) into v_n
  from public.resolver_capabilities_escopos_efetivas(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1')
  where scope_type='DESCENDANTS';
  if v_n <> 0 then
    raise exception '[FAIL] scope granular revogado ainda resolve DESCENDANTS';
  end if;

  select count(*) into v_n
  from public.resolver_capabilities_escopos_efetivas(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1')
  where scope_type='DIRECT_REPORTS';
  if v_n <> 2 then
    raise exception '[FAIL] revogacao granular afetou outros scopes indevidamente';
  end if;

  select count(*) into v_n
  from public.access_role_assignment_scopes s
  join public.membership_access_role_assignments a on a.id = s.assignment_id
  where a.membership_id='d1d00000-0000-0000-0000-0000000000a2'
    and s.scope_type='DESCENDANTS' and s.status='revoked';
  if v_n <> 1 then
    raise exception '[FAIL] revogacao granular deveria preservar a linha com status revoked';
  end if;

  update public.access_role_assignment_scopes s
     set status='active'
  from public.membership_access_role_assignments a
   where a.id = s.assignment_id
     and a.membership_id='d1d00000-0000-0000-0000-0000000000a2'
     and s.scope_type='DESCENDANTS';
  raise notice '[PASS] revogacao granular de scope funciona sem apagar historico';
end $$;

-- ============================================================================
-- 6) Posição vaga e contexto histórico
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1',
    'DESCENDANTS', null, '2024-12-01T00:00:00Z')
  where position_id = 'd1e00000-0000-0000-0000-0000000000e6'
    and collaborator_id is null;
  if v_n <> 1 then
    raise exception '[FAIL] posicao vaga deveria aparecer sem collaborator alvo';
  end if;
  raise notice '[PASS] posicao vaga nao cria collaborator alvo artificial (collaborator NULL)';
end $$;

do $$
declare
  v_cid_hist uuid;
  v_cid_now  uuid;
begin
  select collaborator_id into v_cid_hist
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1',
    'DESCENDANTS', null, '2024-03-01T00:00:00Z')
  where position_id='d1e00000-0000-0000-0000-0000000000e3';

  select collaborator_id into v_cid_now
  from public.resolver_alvos_escopo(
    'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1',
    'DESCENDANTS', null, '2024-12-01T00:00:00Z')
  where position_id='d1e00000-0000-0000-0000-0000000000e3';

  if v_cid_hist is distinct from 'd1c00000-0000-0000-0000-0000000000c4' then
    raise exception '[FAIL] contexto historico deveria resolver AN1 (titular antigo)';
  end if;
  if v_cid_now is distinct from 'd1c00000-0000-0000-0000-0000000000c7' then
    raise exception '[FAIL] contexto atual deveria resolver SUCCESSOR';
  end if;
  raise notice '[PASS] contexto historico nao e reescrito pela estrutura atual (AN1 -> SUCCESSOR)';
end $$;

-- ============================================================================
-- 7) RLS deny-by-default em execução (como authenticated)
-- ============================================================================

set role authenticated;

do $$
declare
  v_tabela text;
  v_ok boolean;
  v_tabelas text[] := array[
    'membership_collaborator_links',
    'access_role_assignment_scopes',
    'access_role_assignment_unit_targets'
  ];
begin
  foreach v_tabela in array v_tabelas loop
    v_ok := false;
    begin
      execute format('select count(*) from public.%I', v_tabela);
    exception when insufficient_privilege then
      v_ok := true;
    end;
    if not v_ok then
      raise exception '[FAIL] authenticated leu a tabela fechada %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] RLS/grants: authenticated sem leitura das tres tabelas F4-02 (permission denied)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    perform 1 from public.resolver_capabilities_escopos_efetivas(
      'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1');
  exception when insufficient_privilege then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] authenticated executou resolver de escopo (deveria ser negado)';
  end if;
  raise notice '[PASS] RLS/grants: resolvers de escopo sem EXECUTE para authenticated (deny-by-default)';
end $$;

reset role;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_policies p
  where p.schemaname='public'
    and p.policyname in (
      'user_profiles_select_own',
      'user_organization_memberships_select_own',
      'organizations_select_via_membership'
    );
  if v_n <> 3 then
    raise exception '[FAIL] policies de identidade/sessao da F2 ausentes (esperado 3, encontrado %)', v_n;
  end if;
  raise notice '[PASS] 3 policies de identidade/sessao da F2 presentes (total de policies evolui com F4-08)';
end $$;

-- ============================================================================
-- 8) Limpeza do cenário sintético
-- ============================================================================

delete from public.access_role_assignment_unit_targets
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_assignment_scopes
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.membership_access_role_assignments
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.membership_collaborator_links
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_capabilities
where access_role_id = 'd1f00000-0000-0000-0000-0000000000f1';

delete from public.access_roles
where id = 'd1f00000-0000-0000-0000-0000000000f1';

delete from public.user_organization_memberships
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.user_profiles
where id::text like 'd1b00000-0000-0000-0000-0000000000%';

delete from auth.users
where id::text like 'd1b00000-0000-0000-0000-0000000000%';

delete from public.occupations
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.position_reporting_lines
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_positions
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_unit_parent_periods
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_units
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.collaborators
where id::text like 'd1c00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.organizations
where id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

do $$
begin
  if exists (
    select 1 from public.access_role_assignment_scopes
    where organization_id::text like 'd1a00000%'
  ) then
    raise exception '[FAIL] limpeza do cenario F4-02 incompleta (scopes)';
  end if;
  if exists (
    select 1 from public.membership_collaborator_links
    where organization_id::text like 'd1a00000%'
  ) then
    raise exception '[FAIL] limpeza do cenario F4-02 incompleta (links)';
  end if;
  raise notice '[PASS] cenario sintetico F4-02 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F4-02: todas as verificacoes passaram (scopes, links, resolvers, RLS, cross-tenant, lifecycle).';
end $$;
