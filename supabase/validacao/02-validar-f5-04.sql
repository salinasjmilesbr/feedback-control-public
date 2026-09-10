-- ============================================================================
-- F5-04 (Issue #165): validação automatizada — access roles e capabilities reais
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f5-04.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f5-04.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f5-04.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; falha aborta (código
-- não-zero). NÃO toca projeto remoto, NÃO altera policies e remove ao final os
-- dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Estrutura: colunas de catálogo (D14/D15), trilha (D18), funções (D16)
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from information_schema.columns
  where table_schema = 'public' and table_name = 'capabilities'
    and column_name in ('grantable_via_role', 'deprecated');
  if v_n <> 2 then
    raise exception '[FAIL] capabilities sem grantable_via_role/deprecated (F5-04 D14/D15)';
  end if;
  raise notice '[PASS] capabilities com marcadores grantable_via_role e deprecated (D14/D15)';
end $$;

do $$
begin
  if not exists (
    select 1 from pg_tables t
    where t.schemaname = 'public' and t.tablename = 'privilege_mutation_audit'
  ) then
    raise exception '[FAIL] tabela de trilha privilege_mutation_audit ausente (D18)';
  end if;
  if not exists (
    select 1 from pg_class c
    where c.oid = 'public.privilege_mutation_audit'::regclass
      and c.relrowsecurity = true
  ) then
    raise exception '[FAIL] RLS nao habilitado em privilege_mutation_audit';
  end if;
  if exists (
    select 1 from pg_policies p
    where p.schemaname = 'public' and p.tablename = 'privilege_mutation_audit'
  ) then
    raise exception '[FAIL] policy indevida em privilege_mutation_audit (deny-by-default)';
  end if;
  raise notice '[PASS] trilha privilege_mutation_audit presente, RLS habilitado, zero policies (D18)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in (
    'conceder_acesso_role_rpc', 'revogar_acesso_role_rpc',
    'enforce_role_capability_grantable', 'enforce_privilege_audit_append_only'
  );
  if v_n <> 4 then
    raise exception '[FAIL] funcoes F5-04 esperadas=4, encontradas=%', v_n;
  end if;
  raise notice '[PASS] funcoes F5-04 presentes (rpc grant/revoke + triggers D15/D18)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public'
    and p.proname in ('conceder_acesso_role_rpc', 'revogar_acesso_role_rpc')
    and p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] RPC administrativo deveria ser SECURITY INVOKER (sem DEFINER novo — AC7)';
  end if;
  raise notice '[PASS] RPCs administrativos sao SECURITY INVOKER (nenhum DEFINER novo)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in ('conceder_acesso_role_rpc','revogar_acesso_role_rpc')
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] EXECUTE indevido (public/anon/authenticated) nos RPCs F5-04: %', v_n;
  end if;
  raise notice '[PASS] RPCs administrativos sem EXECUTE para public/anon/authenticated';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in ('conceder_acesso_role_rpc','revogar_acesso_role_rpc')
    and a.privilege_type='EXECUTE'
    and a.grantee = 'service_role'::regrole;
  if v_n <> 2 then
    raise exception '[FAIL] EXECUTE service_role ausente nos RPCs F5-04 (esperado=2, encontrado=%)', v_n;
  end if;
  raise notice '[PASS] RPCs administrativos com EXECUTE somente para service_role';
end $$;

-- ============================================================================
-- 2) Catálogo reconciliado (D14/D15): 31 linhas; 29 canônicas; 25 concedíveis;
--    4 controle; 2 deprecadas; bundle admin = 8 funcionais.
-- ============================================================================

do $$
declare
  v_total int; v_dep int; v_grant int; v_control int;
begin
  select count(*) into v_total from public.capabilities;
  select count(*) into v_dep from public.capabilities where deprecated;
  select count(*) into v_grant from public.capabilities where grantable_via_role and not deprecated;
  select count(*) into v_control from public.capabilities where not grantable_via_role;

  if v_total <> 31 then
    raise exception '[FAIL] catalogo deveria ter 31 linhas, encontrado %', v_total;
  end if;
  if v_dep <> 2 then
    raise exception '[FAIL] deprecadas deveriam ser 2, encontrado %', v_dep;
  end if;
  if v_control <> 4 then
    raise exception '[FAIL] controle (nao-concedivel) deveria ser 4, encontrado %', v_control;
  end if;
  if v_grant <> 25 then
    raise exception '[FAIL] concediveis deveriam ser 25, encontrado %', v_grant;
  end if;
  raise notice '[PASS] catalogo reconciliado: 31 linhas (29 canonicas, 25 concediveis, 4 controle, 2 deprecadas)';
end $$;

do $$
declare
  v_codes text[];
  v_esperado text[] := array[
    'access_role.manage','exceptional_access.grant','membership.manage','pilot_full_access.grant'
  ]::text[];
begin
  select array_agg(c.code order by c.code) into v_codes
  from public.capabilities c
  where not c.grantable_via_role;
  if v_codes is distinct from v_esperado then
    raise exception '[FAIL] conjunto de controle divergente (D15)';
  end if;
  raise notice '[PASS] plano administrativo (controle/C-D) = membership.manage, access_role.manage, exceptional_access.grant, pilot_full_access.grant';
end $$;

do $$
declare
  v_codes text[];
  v_esperado text[] := array[
    'collaborator.create','collaborator.edit','collaborator.read','cycle.read',
    'membership.read','org.catalog.manage','org.structure.manage','settings.manage'
  ]::text[];
begin
  select array_agg(c.code order by c.code) into v_codes
  from public.access_role_capabilities rc
  join public.capabilities c on c.id = rc.capability_id
  where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_codes is distinct from v_esperado then
    raise exception '[FAIL] bundle admin divergente (F5-04 D15)';
  end if;
  raise notice '[PASS] bundle admin = 8 capabilities FUNCIONAIS (sem controle, sem deprecado, sem confidencial)';
end $$;

-- ============================================================================
-- 3) D15: trigger rejeita associar controle/deprecada a role
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.access_role_capabilities (access_role_id, capability_id)
    select 'd5f00000-0000-0000-0000-0000000000f1', c.id
      from public.capabilities c
     where c.code = 'membership.manage';
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] capability de controle NAO foi rejeitada em access_role (D15)';
  end if;
  raise notice '[PASS] trigger D15 rejeita capability de controle (membership.manage) em access_role';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.access_role_capabilities (access_role_id, capability_id)
    select 'd5f00000-0000-0000-0000-0000000000f1', c.id
      from public.capabilities c
     where c.code = 'collaborator.manage';
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] capability deprecada NAO foi rejeitada em access_role (D14)';
  end if;
  raise notice '[PASS] trigger D15 rejeita capability deprecada (collaborator.manage) em access_role';
end $$;

-- ============================================================================
-- 4) Resolução efetiva (D1–D13): bundle admin e fail-closed
-- ============================================================================

do $$
declare
  v_codes text[];
  v_esperado text[] := array[
    'collaborator.create','collaborator.edit','collaborator.read','cycle.read',
    'membership.read','org.catalog.manage','org.structure.manage','settings.manage'
  ]::text[];
begin
  select array_agg(capability_code order by capability_code) into v_codes
  from public.resolver_capabilities_efetivas(
    'd5b00000-0000-0000-0000-0000000000a1',
    'd5a00000-0000-0000-0000-0000000000a1'
  );
  if v_codes is distinct from v_esperado then
    raise exception '[FAIL] resolver ADMIN_A/Alfa divergente';
  end if;
  raise notice '[PASS] ADMIN_A (sem collaborator) resolve 8 capabilities funcionais em Alfa';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd5b00000-0000-0000-0000-0000000000a2',
    'd5a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then
    raise exception '[FAIL] USER_A sem atribuicao deveria resolver vazio';
  end if;
  raise notice '[PASS] membro sem atribuicao resolve vazio (fail-closed)';
end $$;

-- ============================================================================
-- 5) D16: RPC soberana (auth.uid), tenant revalidado, anti-self-escalation
-- ============================================================================

-- 5.1) Concessão válida (ADMIN_A concede a USER_A)
select set_config('request.jwt.claim.sub', 'd5b00000-0000-0000-0000-0000000000a1', false);
do $$
declare
  v_n int;
begin
  perform public.conceder_acesso_role_rpc(
    'd5d00000-0000-0000-0000-0000000000a2',
    'd5f00000-0000-0000-0000-0000000000f1'
  );

  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd5b00000-0000-0000-0000-0000000000a2',
    'd5a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 1 then
    raise exception '[FAIL] apos concessao USER_A deveria resolver 1 capability (%)', v_n;
  end if;
  raise notice '[PASS] RPC concede role com ator soberano auth.uid() (USER_A resolve evaluation.read)';
end $$;

-- 5.2) Trilha D18 registrada com autoria soberana
do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.privilege_mutation_audit
  where membership_id = 'd5d00000-0000-0000-0000-0000000000a2'
    and access_role_id = 'd5f00000-0000-0000-0000-0000000000f1'
    and action = 'grant'
    and actor_user_profile_id = 'd5b00000-0000-0000-0000-0000000000a1'
    and organization_id = 'd5a00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] trilha grant nao registrada com autoria soberana (%)', v_n;
  end if;
  raise notice '[PASS] trilha append-only registra grant com autoria soberana (D18)';
end $$;

-- 5.3) Self-escalation negada
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a1',
      'd5f00000-0000-0000-0000-0000000000f1'
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] self-escalation NAO foi negada (D15/D16)';
  end if;
  raise notice '[PASS] self-escalation negada (ator nao concede a propria membership)';
end $$;

-- 5.4) Cross-tenant negado (ator de Alfa concedendo em Beta)
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a3',
      'd5f00000-0000-0000-0000-0000000000f1'
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] cross-tenant NAO foi negado (D16)';
  end if;
  raise notice '[PASS] cross-tenant negado (ator sem membership ativa na organizacao alvo)';
end $$;

-- 5.5) Ator sem membership na org alvo negado
select set_config('request.jwt.claim.sub', 'd5b00000-0000-0000-0000-0000000000a4', false);
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a2',
      'd5f00000-0000-0000-0000-0000000000f1'
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] ator sem membership na org alvo NAO foi negado';
  end if;
  raise notice '[PASS] ator sem membership ativa na organizacao alvo negado (tenant revalidado)';
end $$;

-- 5.6) Ator soberano ausente (auth.uid() null)
select set_config('request.jwt.claim.sub', '', false);
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a2',
      'd5f00000-0000-0000-0000-0000000000f1'
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] ator soberano ausente NAO foi negado';
  end if;
  raise notice '[PASS] ator soberano ausente (auth.uid() null) negado (fail-closed)';
end $$;

-- ============================================================================
-- 6) D17: revogação efetiva na operação subsequente
-- ============================================================================
select set_config('request.jwt.claim.sub', 'd5b00000-0000-0000-0000-0000000000a1', false);
do $$
declare
  v_n int;
begin
  perform public.revogar_acesso_role_rpc(
    'd5d00000-0000-0000-0000-0000000000a2',
    'd5f00000-0000-0000-0000-0000000000f1'
  );

  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd5b00000-0000-0000-0000-0000000000a2',
    'd5a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then
    raise exception '[FAIL] revogacao deveria tornar o resolver vazio imediatamente (%)', v_n;
  end if;
  raise notice '[PASS] revogacao efetiva na operacao subsequente (D17)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.privilege_mutation_audit
  where membership_id = 'd5d00000-0000-0000-0000-0000000000a2'
    and access_role_id = 'd5f00000-0000-0000-0000-0000000000f1'
    and action = 'revoke'
    and actor_user_profile_id = 'd5b00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] trilha revoke nao registrada (%)', v_n;
  end if;
  raise notice '[PASS] trilha append-only registra revoke com autoria soberana (D18)';
end $$;

reset request.jwt.claim.sub;

-- ============================================================================
-- 7) D18: append-only (UPDATE negado) e RLS deny-by-default
-- ============================================================================

do $$
declare v_ok boolean := false;
begin
  begin
    update public.privilege_mutation_audit set action = 'revoke';
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] UPDATE da trilha append-only NAO foi bloqueado (D18)';
  end if;
  raise notice '[PASS] trilha append-only bloqueia UPDATE (D18)';
end $$;

set role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin perform 1 from public.privilege_mutation_audit; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated leu a trilha fechada'; end if;
  raise notice '[PASS] authenticated sem SELECT na trilha privilege_mutation_audit';
end $$;

do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a2',
      'd5f00000-0000-0000-0000-0000000000f1'
    );
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated executou RPC administrativo'; end if;
  raise notice '[PASS] authenticated sem EXECUTE nos RPCs administrativos';
end $$;
reset role;

-- ============================================================================
-- 8) Limpeza do cenário sintético (catálogo de sistema da migration intacto)
-- ============================================================================

delete from public.privilege_mutation_audit
where organization_id in (
  'd5a00000-0000-0000-0000-0000000000a1',
  'd5a00000-0000-0000-0000-0000000000b1'
);

delete from public.membership_access_role_assignments
where organization_id in (
  'd5a00000-0000-0000-0000-0000000000a1',
  'd5a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_capabilities
where access_role_id = 'd5f00000-0000-0000-0000-0000000000f1';

delete from public.access_roles
where id = 'd5f00000-0000-0000-0000-0000000000f1';

delete from public.user_organization_memberships
where organization_id in (
  'd5a00000-0000-0000-0000-0000000000a1',
  'd5a00000-0000-0000-0000-0000000000b1'
);

delete from public.user_profiles
where id::text like 'd5b00000-0000-0000-0000-0000000000%';

delete from auth.users
where id::text like 'd5b00000-0000-0000-0000-0000000000%';

delete from public.organizations
where id in (
  'd5a00000-0000-0000-0000-0000000000a1',
  'd5a00000-0000-0000-0000-0000000000b1'
);

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    raise exception '[FAIL] catalogo de sistema foi alterado pela limpeza (% capabilities)', v_n;
  end if;
  select count(*) into v_n
  from public.privilege_mutation_audit
  where organization_id::text like 'd5a00000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F5-04 incompleta (audit)';
  end if;
  raise notice '[PASS] cenario sintetico F5-04 removido ao final; catalogo de sistema intacto';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-04: todas as verificacoes passaram (catalogo reconciliado, D14/D15, RPC soberana D16, revogacao D17, trilha D18, RLS fechado).';
end $$;
