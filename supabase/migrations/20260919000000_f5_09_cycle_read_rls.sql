-- ============================================================================
-- F5-09 P5: leitura soberana de ciclos — policy own-tenant + grant MINIMO
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md §9 (RLS: "policy ANTES do grant", no
-- padrao F4-08), §13.5 (leitura por PostgREST sob RLS; nenhuma leitura de ciclo
-- por `localStorage` como autoridade), §19 P5 e D22; auditoria read-only
-- docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md (§3: own-tenant read,
-- cross-tenant/IDOR, RLS deny-by-default).
-- Pre-requisitos: F4-08 (RLS hardening + helper de tenant), P1 (schema/trilha) e
-- P2/P3/P4 (RPCs de mutacao).
--
-- Entregue AQUI (e somente isto):
--   1) policy `evaluation_cycles_select_same_tenant` — SELECT, `authenticated`,
--      `USING (public.user_has_active_membership(organization_id))`: o tenant
--      NUNCA e aceito do cliente; a autorizacao e derivada da identidade
--      soberana (`auth.uid()`) + profile ativo + membership ATIVA na organizacao
--      da PROPRIA linha (helper F4-08 `user_has_active_membership`);
--   2) `grant select` a `authenticated` — o MINIMO necessario (nenhum DML).
--
-- Fora do escopo (P6+), deliberadamente NAO implementado aqui: Policy Engine
-- `cycle.read`/`cycle.manage` (P6), Edge `ciclos` + reconciliacao do bundle
-- `admin` (P7), cutover das paginas/consumidores para a porta soberana (P8) e
-- validacao integrada (P9). Nenhuma capability nova, nenhuma RPC nova, nenhuma
-- tabela/coluna nova, nenhuma alteracao nas RPCs de mutacao P2/P3/P4 e nenhuma
-- policy/ACL em `cycle_events` (que permanece deny-by-default integral).
--
-- Invariantes preservadas (D1–D28), em especial:
--   - RLS e barreira de TENANT, nao de capability: qualquer membro ATIVO le os
--     ciclos da PROPRIA organizacao; capability/escopo/elegibilidade continuam
--     no Policy Engine (P6) e nas RPCs (D20/D21);
--   - escrita direta do cliente continua PROIBIDA (nenhum grant de DML e nenhuma
--     policy de escrita): a mutacao continua exclusivamente pelas RPCs `ciclo_*`
--     com `EXECUTE` so `service_role` (D22);
--   - `service_role` executa e NAO decide autorizacao; mantem os privilegios que
--     a F5-06/P1 exigem (SELECT/INSERT/UPDATE) e continua SEM `DELETE`/
--     `TRUNCATE` (D9);
--   - a trilha `cycle_events` NAO e exposta: permanece sem policy e sem acesso a
--     `authenticated`/`anon` (leitura server-side), como no §9;
--   - as constraints/triggers da P1 (I5, I6, append-only) e as RPCs das fases
--     P2/P3/P4 permanecem intactas (guarda final fail-closed).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
do $$
declare
  v_fn         text;
  v_faltando   text[] := array[]::text[];
  v_policy     record;
  v_existe     boolean;
begin
  -- F4-08: a tabela ja tem RLS habilitada e o helper de tenant existe, e
  -- INVOKER, STABLE e acessivel apenas a `authenticated`.
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'evaluation_cycles' and c.relrowsecurity
  ) then
    v_faltando := v_faltando || 'RLS nao habilitada em evaluation_cycles'::text;
  end if;
  select p.prosecdef, p.provolatile into v_policy
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'user_has_active_membership' and p.pronargs = 1;
  if not found then
    v_faltando := v_faltando || 'helper user_has_active_membership(uuid) ausente'::text;
  else
    if v_policy.prosecdef then
      v_faltando := v_faltando || 'helper user_has_active_membership e SECURITY DEFINER'::text;
    end if;
    if v_policy.provolatile <> 's' then
      v_faltando := v_faltando || 'helper user_has_active_membership nao e STABLE'::text;
    end if;
  end if;
  if has_function_privilege('authenticated', 'public.user_has_active_membership(uuid)', 'EXECUTE') is not true then
    v_faltando := v_faltando || 'authenticated sem EXECUTE no helper de tenant'::text;
  end if;

  -- F5-06/F5-09: a tabela existe e NAO tem nenhum acesso de escrita a cliente.
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT') then
    v_faltando := v_faltando || 'baseline com acesso de cliente ja concedido (drift)'::text;
  end if;

  -- P1: constraints/triggers da integridade de ciclos.
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_faltando := v_faltando || 'I5 (uq_evaluation_cycles_org_ativo) ausente'::text;
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycles'::regclass
       and c.conname = 'ex_evaluation_cycles_periodo_no_overlap' and c.contype = 'x'
  ) then
    v_faltando := v_faltando || 'I6 (ex_evaluation_cycles_periodo_no_overlap) ausente'::text;
  end if;

  -- P2/P3/P4: as RPCs de mutacao existem e continuam fechadas ao cliente.
  foreach v_fn in array array[
    'ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)',
    'ciclo_ativar(uuid, uuid, integer, uuid, uuid)',
    'ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)']
  loop
    if to_regprocedure('public.' || v_fn) is null then
      v_faltando := v_faltando || ('ausente: ' || v_fn);
    end if;
  end loop;

  -- P1: a trilha continua fechada (sem policy, sem acesso a cliente).
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'cycle_events') then
    v_faltando := v_faltando || 'cycle_events com policy (deveria ser deny-by-default)'::text;
  end if;
  if has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_faltando := v_faltando || 'cycle_events legivel por cliente (deveria ser fechada)'::text;
  end if;

  -- A policy desta fase NAO pode existir com definicao divergente (drift).
  select exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and policyname = 'evaluation_cycles_select_same_tenant'
  ) into v_existe;
  if v_existe then
    select p.cmd, p.roles, coalesce(p.qual, '') as qual into v_policy
      from pg_policies p
     where p.schemaname = 'public' and p.tablename = 'evaluation_cycles'
       and p.policyname = 'evaluation_cycles_select_same_tenant';
    if v_policy.cmd <> 'SELECT'
       or not ('authenticated'::name = any(v_policy.roles))
       or position('user_has_active_membership' in v_policy.qual) = 0
       or position('organization_id' in v_policy.qual) = 0 then
      v_faltando := v_faltando || 'policy evaluation_cycles_select_same_tenant ja existe com definicao divergente'::text;
    end if;
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception 'F5_09_P5_PREFLIGHT: baseline incompativel: %', array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-09 P5: preflight OK (RLS ja habilitada, helper de tenant INVOKER/STABLE disponivel, integridade da P1 e RPCs P2/P3/P4 presentes, trilha fechada e nenhuma policy divergente)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) Leitura own-tenant: policy ANTES do grant (padrao F4-08 §9)
-- ----------------------------------------------------------------------------
-- A expressao da policy e EXATAMENTE a do desenho (§9): o predicado e a
-- membership ATIVA do ator autenticado na organizacao da linha. Nenhum filtro
-- vem do cliente e nenhuma capability e exigida aqui (RLS = tenant boundary).
alter table public.evaluation_cycles enable row level security;

do $$
begin
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and policyname = 'evaluation_cycles_select_same_tenant'
  ) then
    raise notice 'F5-09 P5: policy evaluation_cycles_select_same_tenant ja existia com a definicao do contrato — nao recriada';
  else
    create policy evaluation_cycles_select_same_tenant on public.evaluation_cycles
      for select
      to authenticated
      using (public.user_has_active_membership(organization_id));
  end if;
end $$;

-- Grant MINIMO: somente SELECT (nenhum DML e nenhuma coluna privilegiada).
grant select on public.evaluation_cycles to authenticated;

-- ----------------------------------------------------------------------------
-- 2) Guarda final FAIL-CLOSED (§19 P5 / D22)
-- ----------------------------------------------------------------------------
-- A migration so termina se: a policy existir com a definicao do contrato; o
-- unico privilegio novo de `authenticated` for SELECT (nenhum DML, nenhuma
-- REFERENCES/TRIGGER); `anon` continuar sem qualquer privilegio; a trilha seguir
-- fechada; `service_role` manter os privilegios da F5-06/P1 SEM `DELETE`/
-- `TRUNCATE` (D9); e as RPCs das fases anteriores continuarem INVOKER com
-- `EXECUTE` so `service_role` (nenhuma superficie nova de mutacao).
do $$
declare
  v_policy   record;
  v_fn       text;
  v_rec      record;
  v_problemas text[] := array[]::text[];
  v_n        int;
begin
  -- (1) Policy presente com a definicao exata do contrato.
  select p.cmd, p.roles, coalesce(p.qual, '') as qual, p.permissive into v_policy
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'evaluation_cycles'
     and p.policyname = 'evaluation_cycles_select_same_tenant';
  if not found then
    v_problemas := v_problemas || 'policy evaluation_cycles_select_same_tenant ausente'::text;
  else
    if v_policy.cmd <> 'SELECT' then
      v_problemas := v_problemas || ('policy com cmd divergente: ' || v_policy.cmd);
    end if;
    if not ('authenticated'::name = any(v_policy.roles)) then
      v_problemas := v_problemas || 'policy nao se aplica a authenticated'::text;
    end if;
    if 'anon'::name = any(v_policy.roles) or 'public'::name = any(v_policy.roles) then
      v_problemas := v_problemas || 'policy exposta a anon/public'::text;
    end if;
    if position('user_has_active_membership' in v_policy.qual) = 0
       or position('organization_id' in v_policy.qual) = 0 then
      v_problemas := v_problemas || 'policy sem o predicado de tenant do contrato'::text;
    end if;
    if v_policy.permissive <> 'PERMISSIVE' then
      v_problemas := v_problemas || 'policy nao e PERMISSIVE (contrato F4-08)'::text;
    end if;
  end if;

  -- (2) Existe EXATAMENTE UMA policy na tabela e ela e de SELECT (nenhuma
  -- policy de escrita pode ter sido aberta acidentalmente).
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'evaluation_cycles';
  if v_n <> 1 then
    v_problemas := v_problemas || ('evaluation_cycles com ' || v_n || ' policies (esperado 1 de SELECT)');
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_cycles' and cmd <> 'SELECT'
  ) then
    v_problemas := v_problemas || 'policy de ESCRITA aberta em evaluation_cycles'::text;
  end if;

  -- (3) Privilegios: SELECT para authenticated; NENHUM DML/REFERENCES/TRIGGER.
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'SELECT') is not true then
    v_problemas := v_problemas || 'authenticated sem SELECT em evaluation_cycles'::text;
  end if;
  foreach v_fn in array array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']
  loop
    if has_table_privilege('authenticated', 'public.evaluation_cycles', v_fn) then
      v_problemas := v_problemas || ('authenticated com ' || v_fn || ' em evaluation_cycles');
    end if;
    if has_table_privilege('anon', 'public.evaluation_cycles', v_fn) then
      v_problemas := v_problemas || ('anon com ' || v_fn || ' em evaluation_cycles');
    end if;
  end loop;
  if has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT') then
    v_problemas := v_problemas || 'anon com SELECT em evaluation_cycles'::text;
  end if;

  -- (4) service_role mantem o contrato F5-06/P1 (sem DELETE/TRUNCATE — D9).
  if has_table_privilege('service_role', 'public.evaluation_cycles', 'SELECT') is not true
     or has_table_privilege('service_role', 'public.evaluation_cycles', 'INSERT') is not true
     or has_table_privilege('service_role', 'public.evaluation_cycles', 'UPDATE') is not true then
    v_problemas := v_problemas || 'service_role perdeu privilegio exigido pela F5-06/P1'::text;
  end if;
  if has_table_privilege('service_role', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_cycles', 'TRUNCATE') then
    v_problemas := v_problemas || 'service_role com DELETE/TRUNCATE (D9 violado)'::text;
  end if;

  -- (5) Trilha continua fechada ao cliente e sem policy.
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'cycle_events') then
    v_problemas := v_problemas || 'policy em cycle_events (deveria seguir deny-by-default)'::text;
  end if;
  if has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'cycle_events com acesso de cliente'::text;
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'SELECT') is not true
     or has_table_privilege('service_role', 'public.cycle_events', 'INSERT') is not true then
    v_problemas := v_problemas || 'service_role perdeu SELECT/INSERT na trilha'::text;
  end if;

  -- (6) Fases anteriores intactas: 8 RPCs INVOKER com EXECUTE so service_role.
  foreach v_fn in array array[
    'ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)',
    'ciclo_ativar(uuid, uuid, integer, uuid, uuid)',
    'ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)']
  loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config into v_rec
      from pg_proc p where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      v_problemas := v_problemas || ('RPC ausente: ' || v_fn);
      continue;
    end if;
    if v_rec.prosecdef then
      v_problemas := v_problemas || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_problemas := v_problemas || ('sem search_path fixo: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_problemas := v_problemas || ('service_role sem EXECUTE: ' || v_fn);
    end if;
    if has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE') then
      v_problemas := v_problemas || ('RPC de mutacao exposta a cliente: ' || v_fn);
    end if;
  end loop;

  -- (7) Nenhuma RPC de LEITURA foi criada nesta fase (a leitura e RLS/PostgREST;
  -- as RPCs de leitura do §13.2 pertencem ao P7).
  if exists (
    select 1 from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('ciclo_painel', 'ciclo_historico', 'ciclo_listar_colaborador_por_ciclo')
  ) then
    v_problemas := v_problemas || 'RPC de leitura antecipada (pertence ao P7)'::text;
  end if;

  -- (8) P6 NAO antecipado: nenhuma capability nova (catalogo intacto).
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_problemas := v_problemas || ('catalogo de capabilities alterado: ' || v_n);
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception 'F5_09_P5_GUARD: superficie de leitura inconsistente: %',
      array_to_string(v_problemas, '; ');
  end if;

  raise notice 'F5-09 P5: guarda final OK (policy own-tenant unica de SELECT com predicado de tenant; authenticated com SELECT e SEM DML; anon sem acesso; trilha fechada; service_role intacto sem DELETE/TRUNCATE; 8 RPCs de mutacao INVOKER com EXECUTE so service_role; nenhum P6/P7 antecipado)';
end $$;
