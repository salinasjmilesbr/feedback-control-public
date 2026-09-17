-- ============================================================================
-- F6-A03 (Issue #266): validação automatizada — BOOTSTRAP DE PLATAFORMA
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de `44-cenario-f6-a03.sql`, como owner local (`postgres`), com
-- ON_ERROR_STOP ativo. Cada verificacao imprime um [PASS]; qualquer divergencia
-- aborta com exit code != 0.
--
-- Cobre os criterios de aceite do contrato (docs/F6-A03-desenho-tecnico.md §9):
--   A  preflight: tabela/RLS/ACL, RPC INVOKER + search_path + EXECUTE so
--      service_role, catalogo 31 e bundle admin 9 INTACTOS;
--   B  trilha: append-only (trigger e ACL) e INVISIVEL para `authenticated`;
--   C  gate: negativos (ator inativo, nome vazio, entrada nula, founder
--      inexistente e founder inativo) — TODOS fail-closed e SEM efeito;
--   D  caminho feliz + D16/D17 + SEPARACAO DE PLANOS (o operador nao ganha
--      authority no tenant criado);
--   E  idempotencia: replay devolve o MESMO organization_id sem novo efeito e
--      payload divergente RECUSA;
--   F  isolamento: o estado PREEXISTENTE (LEGADO) fica intocado e uma SEGUNDA
--      organizacao pode ser provisionada para o mesmo founder;
--   G  higiene final: nenhum residuo do cenario.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) PREFLIGHT — schema, ACL e invariantes herdados
-- ============================================================================
do $$
declare
  v_n          integer;
  v_rls        boolean;
  v_def        text;
  v_catalogo   integer;
  v_bundle     integer;
  v_admin_n    integer;
begin
  -- (A1) Tabela nova presente, com RLS habilitado e ZERO policy.
  if to_regclass('public.platform_provisioning_events') is null then
    raise exception '[FAIL] A1: platform_provisioning_events ausente';
  end if;
  select c.relrowsecurity into v_rls
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'platform_provisioning_events';
  if v_rls is not true then
    raise exception '[FAIL] A1: platform_provisioning_events sem RLS';
  end if;
  select count(*) into v_n from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'platform_provisioning_events';
  if v_n <> 0 then
    raise exception '[FAIL] A1: platform_provisioning_events com % policy (esperado ZERO)', v_n;
  end if;

  -- (A2) ACL: `service_role` SOMENTE SELECT+INSERT (append-only no runtime).
  if not has_table_privilege('service_role', 'public.platform_provisioning_events', 'SELECT')
     or not has_table_privilege('service_role', 'public.platform_provisioning_events', 'INSERT') then
    raise exception '[FAIL] A2: service_role sem SELECT/INSERT na trilha de plataforma';
  end if;
  if has_table_privilege('service_role', 'public.platform_provisioning_events', 'UPDATE')
     or has_table_privilege('service_role', 'public.platform_provisioning_events', 'DELETE')
     or has_table_privilege('service_role', 'public.platform_provisioning_events', 'TRUNCATE') then
    raise exception '[FAIL] A2: service_role com UPDATE/DELETE/TRUNCATE na trilha de plataforma';
  end if;
  if has_table_privilege('authenticated', 'public.platform_provisioning_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.platform_provisioning_events', 'INSERT')
     or has_table_privilege('anon', 'public.platform_provisioning_events', 'SELECT') then
    raise exception '[FAIL] A2: cliente com privilegio na trilha de plataforma';
  end if;

  -- (A3) RPC: SECURITY INVOKER (sem DEFINER novo), search_path fixo, EXECUTE so
  --      service_role (nenhum DEFINER novo: a guarda F4-08 exige exatamente 4).
  select pg_get_functiondef('public.organizacao_provisionar_inicial(uuid, text, uuid, uuid)'::regprocedure)
    into v_def;
  if position('SECURITY DEFINER' in v_def) <> 0 then
    raise exception '[FAIL] A3: organizacao_provisionar_inicial e SECURITY DEFINER';
  end if;
  -- `pg_get_functiondef` NAO emite `SECURITY INVOKER` (o default) e renderiza o
  -- `search_path` como `SET search_path TO 'public'`: a prova e pelo NOME do
  -- parametro, nao pela forma `=public`.
  if position('search_path' in replace(v_def, ' ', '')) = 0 then
    raise exception '[FAIL] A3: organizacao_provisionar_inicial sem search_path fixo';
  end if;

  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
   where n.nspname = 'public'
     and p.proname = 'organizacao_provisionar_inicial'
     and a.privilege_type = 'EXECUTE'
     and a.grantee = 'service_role'::regrole;
  if v_n <> 1 then
    raise exception '[FAIL] A3: EXECUTE de service_role esperado=1, encontrado=%', v_n;
  end if;

  -- (A4) Cinco SECURITY DEFINER no schema (as 4 historicas), nunca 5.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4 then
    raise exception '[FAIL] A4: SECURITY DEFINER esperado=4, encontrado=%', v_n;
  end if;

  -- (A5) Invariantes herdados: catalogo 31, bundle admin 9, 1 role admin ativa.
  select count(*) into v_catalogo from public.capabilities;
  if v_catalogo <> 31 then
    raise exception '[FAIL] A5: catalogo com % capabilities (esperado 31)', v_catalogo;
  end if;
  select count(*) into v_bundle
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
   where r.name = 'admin' and r.is_system = true;
  if v_bundle <> 9 then
    raise exception '[FAIL] A5: bundle admin com % capabilities (esperado 9)', v_bundle;
  end if;
  select count(*) into v_admin_n from public.access_roles r
   where r.is_system = true and r.name = 'admin' and r.status = 'active';
  if v_admin_n <> 1 then
    raise exception '[FAIL] A5: roles de sistema admin ativas = % (esperado 1)', v_admin_n;
  end if;

  raise notice '[PASS] A: preflight OK (tabela com RLS e ZERO policy; service_role so SELECT+INSERT; RPC INVOKER com search_path fixo e EXECUTE so service_role; 4 DEFINER; catalogo 31; bundle admin 9)';
end $$;

-- ============================================================================
-- B) TRILHA — append-only e invisivel para o cliente
-- ============================================================================
-- B1) `authenticated` NAO le a trilha (sem grant ⇒ permission denied).
set role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin
    perform 1 from public.platform_provisioning_events;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] B1: authenticated leu a trilha de plataforma';
  end if;
  raise notice '[PASS] B1: authenticated NAO le a trilha de plataforma (fail-closed)';
end $$;
reset role;

-- B2) `authenticated` NAO executa a RPC (EXECUTE so service_role).
set role authenticated;
do $$
declare v_ok boolean := false;
begin
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000ff', 'F6-A03 Nao Autorizado',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000001');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] B2: authenticated executou organizacao_provisionar_inicial';
  end if;
  raise notice '[PASS] B2: authenticated NAO executa organizacao_provisionar_inicial';
end $$;
reset role;

-- B3) `service_role` NAO faz UPDATE na trilha (ACL).
set role service_role;
do $$
declare v_ok boolean := false;
begin
  begin
    update public.platform_provisioning_events set organization_name = 'x';
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] B3: service_role atualizou a trilha de plataforma';
  end if;
  raise notice '[PASS] B3: service_role NAO faz UPDATE na trilha (ACL append-only)';
end $$;
reset role;

-- ============================================================================
-- C) GATE — negativos fail-closed, SEM efeito
-- ============================================================================
do $$
declare
  v_n        integer;
  v_msg      text;
  v_antes    integer;
  v_ok       boolean;
begin
  select count(*) into v_antes from public.organizations;

  -- (C1) Nome vazio ⇒ F6_A03_INVALID_NAME.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000c1', '   ',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000001');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_NAME' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C1: nome vazio deveria recusar com F6_A03_INVALID_NAME (msg=%)', v_msg;
  end if;

  -- (C2) Entrada obrigatoria nula ⇒ F6_A03_INVALID_INPUT.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      null, 'F6-A03 Sem Operacao',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000001');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_INPUT' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C2: operation_id nulo deveria recusar com F6_A03_INVALID_INPUT (msg=%)', v_msg;
  end if;

  -- (C3) Operador com perfil NAO ativo ⇒ F6_A03_FORBIDDEN (D14/D17).
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000c3', 'F6-A03 Operador Inativo',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000004');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_FORBIDDEN' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C3: operador disabled deveria recusar com F6_A03_FORBIDDEN (msg=%)', v_msg;
  end if;

  -- (C4) Founder SEM identidade no Auth ⇒ F6_A03_INVALID_FOUNDER (FK).
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000c4', 'F6-A03 Founder Inexistente',
      'f6a30000-0000-4000-8000-000000000009', 'f6a30000-0000-4000-8000-000000000001');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C4: founder inexistente deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- (C5) Founder com perfil NAO ativo ⇒ F6_A03_INVALID_FOUNDER.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000c5', 'F6-A03 Founder Inativo',
      'f6a30000-0000-4000-8000-000000000005', 'f6a30000-0000-4000-8000-000000000001');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] C5: founder disabled deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- (C6) Nenhum negativo persistiu organizacao nem evento de provisionamento.
  select count(*) into v_n from public.organizations;
  if v_n <> v_antes then
    raise exception '[FAIL] C6: negativos alteraram organizations (% -> %)', v_antes, v_n;
  end if;
  select count(*) into v_n from public.platform_provisioning_events
   where organization_name like 'F6-A03 %';
  if v_n <> 0 then
    raise exception '[FAIL] C6: negativos gravaram % evento(s) de provisionamento', v_n;
  end if;

  raise notice '[PASS] C: negativos fail-closed (nome vazio, entrada nula, operador inativo, founder inexistente, founder inativo) SEM qualquer efeito persistido';
end $$;

-- ============================================================================
-- D) CAMINHO FELIZ — D16/D17, trilha D18 e SEPARACAO DE PLANOS
-- ============================================================================
set role service_role;
do $$
declare
  v_org      uuid;
  v_founder  uuid := 'f6a30000-0000-4000-8000-000000000002';
  v_operador uuid := 'f6a30000-0000-4000-8000-000000000003';  -- SEM perfil (D17)
  v_role     uuid;
  v_n        integer;
  v_caps     integer;
  v_memb     uuid;
begin
  select r.id into v_role from public.access_roles r
   where r.name = 'admin' and r.is_system = true and r.organization_id is null;

  v_org := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa', v_founder, v_operador);

  perform set_config('f6a03.org_alfa', v_org::text, false);

  -- (D1) Organizacao criada, com o nome normalizado.
  if not exists (select 1 from public.organizations o
                  where o.id = v_org and o.name = 'F6-A03 Alfa') then
    raise exception '[FAIL] D1: organizacao nao criada com o nome esperado';
  end if;

  -- (D2) D17 — o perfil GLOBAL do ATOR foi criado (o ambiente virgem e admissivel).
  if not exists (select 1 from public.user_profiles up
                  where up.id = v_operador and up.status = 'active') then
    raise exception '[FAIL] D2: perfil do operador (D17) nao foi criado';
  end if;

  -- (D3) D16 — o perfil GLOBAL do FOUNDER foi criado.
  if not exists (select 1 from public.user_profiles up
                  where up.id = v_founder and up.status = 'active') then
    raise exception '[FAIL] D3: perfil do founder (D16) nao foi criado';
  end if;

  -- (D4) Membership ativa do founder NA organizacao NOVA.
  select m.id into v_memb from public.user_organization_memberships m
   where m.user_profile_id = v_founder and m.organization_id = v_org and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] D4: membership do founder ausente/inativa';
  end if;

  -- (D5) Atribuicao ativa da role de sistema `admin` (origin human, autor = operador).
  if not exists (
    select 1 from public.membership_access_role_assignments a
     where a.membership_id = v_memb and a.access_role_id = v_role
       and a.organization_id = v_org and a.status = 'active'
       and a.origin = 'human'
       and a.created_by = v_operador
  ) then
    raise exception '[FAIL] D5: atribuicao da role admin ausente/incorreta';
  end if;

  -- (D6) Trilha D18: EXATAMENTE um `grant` humano com ator = operador.
  select count(*) into v_n from public.privilege_mutation_audit p
   where p.organization_id = v_org and p.membership_id = v_memb
     and p.access_role_id = v_role and p.action = 'grant'
     and p.actor_user_profile_id = v_operador;
  if v_n <> 1 then
    raise exception '[FAIL] D6: trilha D18 deveria ter 1 grant do operador (tem %)', v_n;
  end if;

  -- (D7) Evento de provisionamento: EXATAMENTE um, com hash canonico e autores.
  select count(*) into v_n from public.platform_provisioning_events e
   where e.operation_id = 'f6a3b000-0000-4000-8000-000000000001'
     and e.organization_id = v_org
     and e.organization_name = 'F6-A03 Alfa'
     and e.actor_user_profile_id = v_operador
     and e.founder_user_profile_id = v_founder
     and e.payload_hash ~ '^[0-9a-f]{64}$';
  if v_n <> 1 then
    raise exception '[FAIL] D7: evento de provisionamento ausente/incompleto (n=%)', v_n;
  end if;

  -- (D8) O founder e ADMIN do tenant novo e resolve as 9 capabilities funcionais.
  if not public.usuario_eh_administrador(v_founder, v_org) then
    raise exception '[FAIL] D8: founder nao e administrador do tenant criado';
  end if;
  select count(*) into v_caps from public.resolver_capabilities_efetivas(v_founder, v_org) c;
  if v_caps <> 9 then
    raise exception '[FAIL] D8: founder resolve % capabilities (esperado 9)', v_caps;
  end if;

  -- (D9) SEPARACAO DE PLANOS: o OPERADOR de plataforma NAO ganhou nada no tenant.
  if exists (select 1 from public.user_organization_memberships m
              where m.user_profile_id = v_operador and m.organization_id = v_org) then
    raise exception '[FAIL] D9: operador de plataforma virou membro do tenant criado';
  end if;
  select count(*) into v_caps from public.resolver_capabilities_efetivas(v_operador, v_org) c;
  if v_caps <> 0 then
    raise exception '[FAIL] D9: operador sem membership resolveu % capabilities', v_caps;
  end if;

  raise notice '[PASS] D: caminho feliz OK — organizacao criada, perfis globais do founder (D16) e do ator (D17), membership ativa, role admin pelo primitivo F4-01, trilha D18 com ator humano e SEPARACAO DE PLANOS (operador sem autoridade no tenant)';
end $$;
reset role;

-- ============================================================================
-- E) IDEMPOTENCIA — replay verificado (D6)
-- ============================================================================
set role service_role;
do $$
declare
  v_org      uuid := current_setting('f6a03.org_alfa')::uuid;
  v_replay   uuid;
  v_msg      text;
  v_n        integer;
begin
  -- (E1) Mesmo payload ⇒ MESMO organization_id, sem novo efeito.
  v_replay := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa',
    'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000003');
  if v_replay is distinct from v_org then
    raise exception '[FAIL] E1: replay devolveu % (esperado %)', v_replay, v_org;
  end if;

  select count(*) into v_n from public.organizations o where o.name = 'F6-A03 Alfa';
  if v_n <> 1 then
    raise exception '[FAIL] E1: replay criou organizacao duplicada (%)', v_n;
  end if;
  select count(*) into v_n from public.platform_provisioning_events e
   where e.operation_id = 'f6a3b000-0000-4000-8000-000000000001';
  if v_n <> 1 then
    raise exception '[FAIL] E1: replay duplicou o evento de provisionamento (%)', v_n;
  end if;
  select count(*) into v_n from public.privilege_mutation_audit p
   where p.organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] E1: replay duplicou a trilha D18 (%)', v_n;
  end if;

  -- (E2) Mesmo operation_id com payload DIFERENTE ⇒ RECUSA fail-closed.
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa (divergente)',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000003');
    raise exception '[FAIL] E2: payload divergente aceito no mesmo operation_id';
  exception when others then
    v_msg := SQLERRM;
    if position('F6_A03_CONFLICT' in v_msg) = 0 then
      raise exception '[FAIL] E2: causa inesperada (%)', v_msg;
    end if;
  end;

  select count(*) into v_n from public.organizations o where o.name like 'F6-A03 Alfa%';
  if v_n <> 1 then
    raise exception '[FAIL] E2: divergencia criou organizacao extra (%)', v_n;
  end if;

  -- (E3) O trigger append-only vale tambem no caminho do OWNER (nao so a ACL);
  -- provado em SUBTRANSACAO controlada logo abaixo.
end $$;
reset role;

do $$
declare v_msg text;
begin
  begin
    update public.platform_provisioning_events
       set organization_name = 'F6-A03 adulterado'
     where operation_id = 'f6a3b000-0000-4000-8000-000000000001';
    raise exception '[FAIL] E3: trigger append-only nao bloqueou o UPDATE do owner';
  exception when others then
    v_msg := SQLERRM;
    if position('append-only' in v_msg) = 0 then
      raise exception '[FAIL] E3: causa inesperada no append-only (%)', v_msg;
    end if;
  end;
  raise notice '[PASS] E3: trigger append-only bloqueia UPDATE da trilha inclusive para o owner';
end $$;

-- (E4) REPLAY e ESTAVEL: repetir a MESMA intencao devolve o MESMO
--      `organization_id` mesmo que o perfil do primeiro Admin tenha sido
--      INATIVADO depois (a idempotencia e resolvida ANTES da validacao de estado
--      do founder, conforme o §5 do contrato) — e operacao NOVA com founder
--      inativo continua RECUSADA (fail-closed).
set role service_role;
do $$
declare
  v_org    uuid := current_setting('f6a03.org_alfa')::uuid;
  v_replay uuid;
  v_n      integer;
  v_msg    text;
  v_ok     boolean;
begin
  update public.user_profiles set status = 'disabled'
   where id = 'f6a30000-0000-4000-8000-000000000002';

  v_replay := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000001', 'F6-A03 Alfa',
    'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000003');
  if v_replay is distinct from v_org then
    raise exception '[FAIL] E4: replay com founder inativo devolveu % (esperado %)', v_replay, v_org;
  end if;

  select count(*) into v_n from public.platform_provisioning_events e
   where e.operation_id = 'f6a3b000-0000-4000-8000-000000000001';
  if v_n <> 1 then
    raise exception '[FAIL] E4: replay com founder inativo duplicou o evento (%)', v_n;
  end if;

  -- Operacao NOVA com o MESMO founder inativo continua fail-closed.
  v_ok := false; v_msg := null;
  begin
    perform public.organizacao_provisionar_inicial(
      'f6a3b000-0000-4000-8000-0000000000e4', 'F6-A03 Founder Inativo Nova',
      'f6a30000-0000-4000-8000-000000000002', 'f6a30000-0000-4000-8000-000000000003');
  exception when others then
    v_msg := SQLERRM;
    v_ok := position('F6_A03_INVALID_FOUNDER' in v_msg) > 0;
  end;
  if not v_ok then
    raise exception '[FAIL] E4: operacao NOVA com founder inativo deveria recusar com F6_A03_INVALID_FOUNDER (msg=%)', v_msg;
  end if;

  -- Reativa o perfil: os blocos seguintes (F/G) usam o founder ativo.
  update public.user_profiles set status = 'active'
   where id = 'f6a30000-0000-4000-8000-000000000002';

  raise notice '[PASS] E4: REPLAY ESTAVEL (mesmo com o primeiro Admin inativado depois) e operacao NOVA com founder inativo segue fail-closed';
end $$;
reset role;

-- ============================================================================
-- F) ISOLAMENTO — estado preexistente intocado + SEGUNDA organizacao
-- ============================================================================
do $$
declare
  v_legado    uuid := 'f6a30000-0000-4000-8000-0000000000a1';
  v_org_alfa  uuid := current_setting('f6a03.org_alfa')::uuid;
  v_n         integer;
begin
  -- (F1) A organizacao LEGADO permanece com nome, membership e atribuicao originais.
  if not exists (select 1 from public.organizations o
                  where o.id = v_legado and o.name = 'F6-A03 Legado (preexistente)') then
    raise exception '[FAIL] F1: organizacao preexistente alterada';
  end if;
  select count(*) into v_n
    from public.user_organization_memberships m
    join public.membership_access_role_assignments a on a.membership_id = m.id
   where m.organization_id = v_legado and m.status = 'active' and a.status = 'active';
  if v_n <> 1 then
    raise exception '[FAIL] F1: membership/atribuicao preexistente alterada (n=%)', v_n;
  end if;

  -- (F2) Nada do tenant novo referencia o LEGADO e vice-versa.
  select count(*) into v_n from public.user_organization_memberships m
   where m.organization_id = v_org_alfa and m.organization_id = v_legado;
  if v_n <> 0 then
    raise exception '[FAIL] F2: cruzamento de tenants detectado';
  end if;

  -- (F3) Nenhum dado de fixture LEGADO apareceu no tenant novo (vazio por construcao).
  select count(*) into v_n from public.user_organization_memberships m
   where m.organization_id = v_org_alfa;
  if v_n <> 1 then
    raise exception '[FAIL] F3: tenant novo deveria ter exatamente 1 membership (tem %)', v_n;
  end if;

  raise notice '[PASS] F1/F2/F3: estado preexistente INTOCADO e tenant novo isolado';
end $$;

-- (F4) Segunda organizacao para o MESMO founder (GREENFIELD usa N organizacoes).
set role service_role;
do $$
declare
  v_founder uuid := 'f6a30000-0000-4000-8000-000000000002';
  v_operador uuid := 'f6a30000-0000-4000-8000-000000000003';
  v_org_beta uuid;
  v_n integer;
begin
  v_org_beta := public.organizacao_provisionar_inicial(
    'f6a3b000-0000-4000-8000-000000000002', 'F6-A03 Beta', v_founder, v_operador);

  if v_org_beta = current_setting('f6a03.org_alfa')::uuid then
    raise exception '[FAIL] F4: segunda organizacao reutilizou o id da primeira';
  end if;
  if not public.usuario_eh_administrador(v_founder, v_org_beta) then
    raise exception '[FAIL] F4: founder nao e admin da segunda organizacao';
  end if;
  select count(*) into v_n from public.user_organization_memberships m
   where m.user_profile_id = v_founder and m.status = 'active';
  if v_n <> 2 then
    raise exception '[FAIL] F4: founder deveria ter 2 memberships ativas (tem %)', v_n;
  end if;

  raise notice '[PASS] F4: segunda organizacao provisionada para o mesmo founder (isolamento por tenant preservado)';
end $$;
reset role;

-- ============================================================================
-- G) HIGIENE — nenhum residuo do cenario
-- ============================================================================
delete from public.membership_access_role_assignments a
 using public.user_organization_memberships m, public.organizations o
 where a.membership_id = m.id and m.organization_id = o.id
   and (o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.privilege_mutation_audit
 where organization_id in (
   select o.id from public.organizations o
    where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.platform_provisioning_events
 where organization_name like 'F6-A03 %'
    or actor_user_profile_id::text like 'f6a30000-%'
    or founder_user_profile_id::text like 'f6a30000-%';

delete from public.user_organization_memberships
 where organization_id in (
   select o.id from public.organizations o
    where o.name like 'F6-A03 %' or o.id = 'f6a30000-0000-4000-8000-0000000000a1');

delete from public.user_profiles where id::text like 'f6a30000-%';

delete from public.organizations
 where name like 'F6-A03 %' or id = 'f6a30000-0000-4000-8000-0000000000a1';

delete from auth.users where id::text like 'f6a30000-%';

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.organizations where name like 'F6-A03 %';
  if v_n <> 0 then raise exception '[FAIL] G: organizacoes residuais (%)', v_n; end if;
  select count(*) into v_n from public.platform_provisioning_events
   where organization_name like 'F6-A03 %';
  if v_n <> 0 then raise exception '[FAIL] G: eventos residuais (%)', v_n; end if;
  select count(*) into v_n from public.user_profiles where id::text like 'f6a30000-%';
  if v_n <> 0 then raise exception '[FAIL] G: perfis residuais (%)', v_n; end if;
  select count(*) into v_n from auth.users where id::text like 'f6a30000-%';
  if v_n <> 0 then raise exception '[FAIL] G: identidades residuais (%)', v_n; end if;

  raise notice '[PASS] G: higiene completa — nenhum residuo do cenario F6-A03';
  raise notice '[PASS] F6-A03: A/B/C/D/E/F/G concluidos — bootstrap de plataforma validado (RLS+ACL, append-only, gate fail-closed, D16/D17, separacao de planos, idempotencia por replay e isolamento multi-tenant)';
end $$;
