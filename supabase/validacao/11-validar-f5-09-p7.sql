-- ============================================================================
-- F5-09 P7 (Issue #202): validacao da reconciliacao do catalogo (D28) e da
-- integridade herdada de P5/P6 (Supabase local apenas).
-- ----------------------------------------------------------------------------
-- Executar como superuser local, com ON_ERROR_STOP ativo. Nao exige cenario
-- proprio: valida o estado do catalogo/bundle e as garantias ja entregues
-- (RLS de leitura, escrita fechada, trilha fechada, RPCs soberanas).
-- ============================================================================

-- ============================================================================
-- 1) D28 — bundle administrativo de sistema (`admin`)
-- ============================================================================
do $$
declare
  v_role constant uuid := 'c0000000-0000-4000-8000-0000000000f1';
  v_codes text[];
  v_esperado text[] := array[
    'collaborator.create','collaborator.edit','collaborator.read','cycle.manage','cycle.read',
    'membership.read','org.catalog.manage','org.structure.manage','settings.manage'
  ]::text[];
begin
  select array_agg(c.code order by c.code) into v_codes
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where rc.access_role_id = v_role;

  if v_codes is distinct from v_esperado then
    raise exception '[FAIL] D28: bundle admin divergente do contrato (esperado 9 funcionais com cycle.manage)';
  end if;

  raise notice '[PASS] D28: bundle admin = 9 capabilities FUNCIONAIS (inclui cycle.manage; sem controle, sem deprecado, sem confidencial)';
end $$;

do $$
begin
  -- As tres excepcionais NAO podem estar em NENHUM bundle/role de SISTEMA — o
  -- contrato e "fora do bundle administrativo padrao", concediveis apenas por
  -- configuracao explicita de role. (Roles de FIXTURE criadas pelos validadores
  -- de P3/P4 nao sao roles de sistema e por isso nao entram nesta guarda.)
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct')
  ) then
    raise exception '[FAIL] D28: cycle.cancel/cycle.reopen/cycle.period.correct concedidas a role de sistema';
  end if;

  raise notice '[PASS] D28: cycle.cancel, cycle.reopen e cycle.period.correct permanecem FORA de todo bundle de sistema';
end $$;

do $$
declare
  v_role constant uuid := 'c0000000-0000-4000-8000-0000000000f1';
  v_n integer;
begin
  -- Nenhuma capability de CONTROLE, deprecada ou de conteudo confidencial no
  -- bundle administrativo (F5-04 D15 preservada depois da reconciliacao).
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where rc.access_role_id = v_role
     and (c.grantable_via_role = false or c.deprecated = true
          or c.code in ('evaluation.read','goal.read','observation.read','report.read'));

  if v_n <> 0 then
    raise exception '[FAIL] D28/F5-04 D15: bundle admin com capability de controle/deprecada/confidencial (%)', v_n;
  end if;

  raise notice '[PASS] D28/F5-04 D15 preservada: bundle admin sem controle, sem deprecada e sem leitura de conteudo';
end $$;

-- ============================================================================
-- 2) Catalogo de capabilities — nenhuma capability nova (D20/D28)
-- ============================================================================
do $$
declare
  v_total integer;
  v_cycle text[];
begin
  -- Catalogo F5-04 reconciliado: 31 LINHAS (29 canonicas + 2 deprecadas) — a P7
  -- NAO cria capability alguma (D20/D28).
  select count(*) into v_total from public.capabilities;
  if v_total <> 31 then
    raise exception '[FAIL] P7: catalogo de capabilities deveria ter 31 linhas, encontradas %', v_total;
  end if;

  select array_agg(code order by code) into v_cycle from public.capabilities where code like 'cycle.%';
  if v_cycle is distinct from array[
    'cycle.cancel','cycle.manage','cycle.period.correct','cycle.read','cycle.reopen'
  ]::text[] then
    raise exception '[FAIL] P7: conjunto de capabilities de ciclo divergente: %', v_cycle;
  end if;

  raise notice '[PASS] P7: catalogo intacto (31 linhas; 5 capabilities de ciclo, nenhuma nova)';
end $$;

do $$
declare
  v_descricao text;
begin
  -- P6: a descricao da capability de cancelamento foi ampliada (D8).
  select description into v_descricao from public.capabilities where code = 'cycle.cancel';
  if v_descricao is null or v_descricao not like '%PLANEJADO%' then
    raise exception '[FAIL] P6/P7: descricao de cycle.cancel nao reflete {PLANEJADO, ATIVO}: %', v_descricao;
  end if;

  raise notice '[PASS] P6/P7: descricao de cycle.cancel reflete a ampliacao para {PLANEJADO, ATIVO} (D8)';
end $$;

-- ============================================================================
-- 3) P5 preservada — RLS de leitura own-tenant e escrita fechada
-- ============================================================================
do $$
declare
  v_policies integer;
  v_rls boolean;
begin
  select relrowsecurity into v_rls
    from pg_class where oid = 'public.evaluation_cycles'::regclass;
  if v_rls is not true then
    raise exception '[FAIL] P5: RLS nao esta habilitado em evaluation_cycles';
  end if;

  select count(*) into v_policies
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'evaluation_cycles'
     and p.cmd = 'SELECT' and p.roles = array['authenticated']::name[]
     and p.qual like '%user_has_active_membership%';
  if v_policies <> 1 then
    raise exception '[FAIL] P5: policy de leitura own-tenant ausente ou duplicada (%)', v_policies;
  end if;

  if exists (
    select 1 from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'evaluation_cycles'
       and p.cmd <> 'SELECT'
  ) then
    raise exception '[FAIL] P5: policy de escrita indevida em evaluation_cycles';
  end if;

  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT') then
    raise exception '[FAIL] P5: escrita/leitura indevida de evaluation_cycles para authenticated/anon';
  end if;

  if exists (
    select 1 from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'cycle_events'
  ) then
    raise exception '[FAIL] P5: cycle_events deveria seguir deny-by-default (sem policy)';
  end if;

  raise notice '[PASS] P5 preservada: RLS own-tenant de leitura, escrita fechada e trilha deny-by-default';
end $$;

-- ============================================================================
-- 4) P2–P4 preservadas — RPCs soberanas com EXECUTE restrito a service_role
-- ============================================================================
do $$
declare
  v_rpc text;
  v_rpcs text[] := array[
    'ciclo_criar','ciclo_editar','ciclo_ativar','ciclo_encerrar',
    'ciclo_cancelar','ciclo_reabrir','ciclo_corrigir_periodo','ciclo_incluir_admissao'
  ];
  v_oid oid;
  v_qtd integer;
  v_prosecdef boolean;
begin
  foreach v_rpc in array v_rpcs loop
    select count(*) into v_qtd
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_rpc;
    if v_qtd <> 1 then
      raise exception '[FAIL] P7: RPC soberana % ausente ou sobrecarregada (%)', v_rpc, v_qtd;
    end if;

    select p.oid, p.prosecdef into v_oid, v_prosecdef
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_rpc;

    if v_prosecdef is true then
      raise exception '[FAIL] P7: RPC % deveria ser SECURITY INVOKER', v_rpc;
    end if;

    if has_function_privilege('authenticated', v_oid, 'EXECUTE')
       or has_function_privilege('anon', v_oid, 'EXECUTE') then
      raise exception '[FAIL] P7: RPC % com EXECUTE para authenticated/anon', v_rpc;
    end if;

    if not has_function_privilege('service_role', v_oid, 'EXECUTE') then
      raise exception '[FAIL] P7: RPC % sem EXECUTE para service_role', v_rpc;
    end if;
  end loop;

  raise notice '[PASS] P2–P4 preservadas: 8 RPCs soberanas presentes, SECURITY INVOKER e EXECUTE só service_role';
end $$;
