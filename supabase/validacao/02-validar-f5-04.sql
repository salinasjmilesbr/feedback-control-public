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
-- Cobre D14 (catálogo), D15 (plano administrativo), D16 (RPC soberana com
-- autorização administrativa e separação identidade × execução privilegiada),
-- D17 (revogação) e D18 (trilha append-only imutável).
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
    'usuario_eh_administrador',
    'enforce_role_capability_grantable', 'enforce_privilege_audit_append_only'
  );
  if v_n <> 5 then
    raise exception '[FAIL] funcoes F5-04 esperadas=5, encontradas=%', v_n;
  end if;
  raise notice '[PASS] funcoes F5-04 presentes (rpc grant/revoke + admin + triggers D15/D18)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public'
    and p.proname in ('conceder_acesso_role_rpc', 'revogar_acesso_role_rpc', 'usuario_eh_administrador')
    and p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] funcao F5-04 deveria ser SECURITY INVOKER (sem DEFINER novo — AC7)';
  end if;
  raise notice '[PASS] RPCs/helper administrativos sao SECURITY INVOKER (nenhum DEFINER novo)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in ('conceder_acesso_role_rpc','revogar_acesso_role_rpc','usuario_eh_administrador')
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] EXECUTE indevido (public/anon/authenticated) nas funcoes F5-04: %', v_n;
  end if;
  raise notice '[PASS] RPCs/helper administrativos sem EXECUTE para public/anon/authenticated';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public'
    and p.proname in ('conceder_acesso_role_rpc','revogar_acesso_role_rpc','usuario_eh_administrador')
    and a.privilege_type='EXECUTE'
    and a.grantee = 'service_role'::regrole;
  if v_n <> 3 then
    raise exception '[FAIL] EXECUTE service_role ausente nas funcoes F5-04 (esperado=3, encontrado=%)', v_n;
  end if;
  raise notice '[PASS] RPCs/helper administrativos com EXECUTE somente para service_role';
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
    raise exception '[FAIL] efetivamente concediveis deveriam ser 25, encontrado %', v_grant;
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
    'collaborator.create','collaborator.edit','collaborator.read','cycle.manage','cycle.read',
    'membership.read','org.catalog.manage','org.structure.manage','settings.manage'
  ]::text[];
begin
  select array_agg(c.code order by c.code) into v_codes
  from public.access_role_capabilities rc
  join public.capabilities c on c.id = rc.capability_id
  where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_codes is distinct from v_esperado then
    raise exception '[FAIL] bundle admin divergente (F5-04 D15 + D28)';
  end if;
  -- F5-09 P7 (D28): `cycle.manage` entra ADITIVAMENTE no bundle administrativo
  -- (a gestao de ciclo precisa ser executavel em producao); as tres excepcionais
  -- (`cycle.cancel`/`cycle.reopen`/`cycle.period.correct`) permanecem FORA e sao
  -- validadas em `11-validar-f5-09-p7.sql`.
  raise notice '[PASS] bundle admin = 9 capabilities FUNCIONAIS (F5-04 D15 + D28: cycle.manage aditivo; sem controle, sem deprecado, sem confidencial)';
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
    'collaborator.create','collaborator.edit','collaborator.read','cycle.manage','cycle.read',
    'membership.read','org.catalog.manage','org.structure.manage','settings.manage'
  ]::text[];
begin
  select array_agg(capability_code order by capability_code) into v_codes
  from public.resolver_capabilities_efetivas(
    'd5b00000-0000-0000-0000-0000000000a1',
    'd5a00000-0000-0000-0000-0000000000a1'
  );
  if v_codes is distinct from v_esperado then
    raise exception '[FAIL] resolver ADMIN_A/Alfa divergente (F5-04 D15 + F5-09 P7 D28)';
  end if;
  -- F5-09 P7 (D28): o bundle `admin` ganhou `cycle.manage` aditivamente, então a
  -- resolução efetiva do ADMIN passou de 8 para 9 capabilities funcionais.
  raise notice '[PASS] ADMIN_A (sem collaborator) resolve 9 capabilities funcionais em Alfa (D28: cycle.manage aditivo)';
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
-- 5) D16: caminho de produção — identidade × execução privilegiada separadas,
--    autorização administrativa, anti-self-escalation, cross-tenant, tenant.
-- ============================================================================
--
-- Regressão detectada em 5.1: JWT de usuário no `Authorization` faz o PostgREST
-- assumir `authenticated`; como o RPC tem EXECUTE só service_role, a chamada
-- falha por permissão. Provamos isso com `set role authenticated`.
--
-- A execução real (service_role) está nas seções seguintes; o ator é o
-- `p_actor_user_profile_id` VERIFICADO server-side (auth.getUser na Edge
-- Function), nunca derivado de payload do cliente.

-- 5.1) Regressão: authenticated (JWT de usuário) NÃO executa o RPC.
set role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a2',
      'd5f00000-0000-0000-0000-0000000000f1',
      'd5b00000-0000-0000-0000-0000000000a1'
    );
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] authenticated executou o RPC administrativo (regressao de role)';
  end if;
  raise notice '[PASS] authenticated (JWT de usuario) NAO executa o RPC — EXECUTE so service_role (regressao detectada)';
end $$;
reset role;

-- 5.2) Autorização administrativa: USER_A (não-admin) não concede.
set role service_role;
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a1',  -- membership do ADMIN_A
      'd5f00000-0000-0000-0000-0000000000f1',  -- avaliadores
      'd5b00000-0000-0000-0000-0000000000a2'   -- ator = USER_A (nao-admin)
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] nao-admin concedeu role (autoridade administrativa ausente)';
  end if;
  raise notice '[PASS] autorizacao administrativa: nao-admin NAO concede (D16/Q3)';
end $$;

-- 5.3) Concessão válida (ADMIN_A concede avaliadores a USER_A) + trilha.
do $$
declare
  v_n int;
begin
  perform public.conceder_acesso_role_rpc(
    'd5d00000-0000-0000-0000-0000000000a2',
    'd5f00000-0000-0000-0000-0000000000f1',
    'd5b00000-0000-0000-0000-0000000000a1'
  );

  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd5b00000-0000-0000-0000-0000000000a2',
    'd5a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 1 then
    raise exception '[FAIL] apos concessao USER_A deveria resolver 1 capability (%)', v_n;
  end if;

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
  raise notice '[PASS] RPC concede role com ator verificado (service_role) e grava trilha D18 com autoria soberana';
end $$;

-- 5.4) Self-escalation negada.
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a1',
      'd5f00000-0000-0000-0000-0000000000f1',
      'd5b00000-0000-0000-0000-0000000000a1'
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] self-escalation NAO foi negada (D15/D16)';
  end if;
  raise notice '[PASS] self-escalation negada (ator nao concede a propria membership)';
end $$;

-- 5.5) Cross-tenant negado (ADMIN_A de Alfa concedendo em Beta).
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a3',
      'd5f00000-0000-0000-0000-0000000000f1',
      'd5b00000-0000-0000-0000-0000000000a1'
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] cross-tenant NAO foi negado (D16)';
  end if;
  raise notice '[PASS] cross-tenant negado (ator sem membership ativa na organizacao alvo)';
end $$;

-- 5.6) Ator sem membership na org alvo negado (SEM_MEMBRO).
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a2',
      'd5f00000-0000-0000-0000-0000000000f1',
      'd5b00000-0000-0000-0000-0000000000a4'
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] ator sem membership na org alvo NAO foi negado';
  end if;
  raise notice '[PASS] ator sem membership ativa na organizacao alvo negado (tenant revalidado)';
end $$;

-- 5.7) Ator ausente (null).
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.conceder_acesso_role_rpc(
      'd5d00000-0000-0000-0000-0000000000a2',
      'd5f00000-0000-0000-0000-0000000000f1',
      null
    );
  exception when raise_exception then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] ator ausente NAO foi negado';
  end if;
  raise notice '[PASS] ator ausente (null) negado (fail-closed)';
end $$;

-- ============================================================================
-- 6) D17: revogação efetiva na operação subsequente
-- ============================================================================

do $$
declare
  v_n int;
begin
  perform public.revogar_acesso_role_rpc(
    'd5d00000-0000-0000-0000-0000000000a2',
    'd5f00000-0000-0000-0000-0000000000f1',
    'd5b00000-0000-0000-0000-0000000000a1'
  );

  select count(*) into v_n
  from public.resolver_capabilities_efetivas(
    'd5b00000-0000-0000-0000-0000000000a2',
    'd5a00000-0000-0000-0000-0000000000a1'
  );
  if v_n <> 0 then
    raise exception '[FAIL] revogacao deveria tornar o resolver vazio imediatamente (%)', v_n;
  end if;

  select count(*) into v_n
  from public.privilege_mutation_audit
  where membership_id = 'd5d00000-0000-0000-0000-0000000000a2'
    and access_role_id = 'd5f00000-0000-0000-0000-0000000000f1'
    and action = 'revoke'
    and actor_user_profile_id = 'd5b00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] trilha revoke nao registrada (%)', v_n;
  end if;
  raise notice '[PASS] revogacao efetiva na operacao subsequente (D17) + trilha revoke (D18)';
end $$;

reset role;

-- ============================================================================
-- 7) D18: append-only (UPDATE negado; service_role sem UPDATE/DELETE/TRUNCATE)
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

do $$
declare v_ok boolean := true;
begin
  -- D18: a credencial do caminho de aplicação (service_role) só grava (INSERT)
  -- e lê (SELECT) a trilha; UPDATE/DELETE/TRUNCATE são revogados. A
  -- higienização pertence ao proprietário/superuser (fora do runtime).
  if has_table_privilege('service_role', 'public.privilege_mutation_audit', 'UPDATE') then v_ok := false; end if;
  if has_table_privilege('service_role', 'public.privilege_mutation_audit', 'DELETE') then v_ok := false; end if;
  if has_table_privilege('service_role', 'public.privilege_mutation_audit', 'TRUNCATE') then v_ok := false; end if;
  if not has_table_privilege('service_role', 'public.privilege_mutation_audit', 'INSERT') then v_ok := false; end if;
  if not has_table_privilege('service_role', 'public.privilege_mutation_audit', 'SELECT') then v_ok := false; end if;
  if not v_ok then
    raise exception '[FAIL] service_role com privilegio indevido na trilha (deveria ser somente SELECT+INSERT)';
  end if;
  raise notice '[PASS] service_role com somente SELECT+INSERT na trilha (UPDATE/DELETE/TRUNCATE revogados — D18)';
end $$;

set role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin perform 1 from public.privilege_mutation_audit; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] authenticated leu a trilha fechada'; end if;
  raise notice '[PASS] authenticated sem SELECT na trilha privilege_mutation_audit';
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
  raise notice 'F5-04: todas as verificacoes passaram (catalogo reconciliado, D14/D15, RPC soberana D16, autorizacao administrativa, revogacao D17, trilha D18, RLS fechado).';
end $$;
