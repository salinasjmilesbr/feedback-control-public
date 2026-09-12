-- ============================================================================
-- F5-09 P5: validacao automatizada da LEITURA SOBERANA de ciclos (RLS own-tenant)
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (migrations)
--   2) `09-cenario-f5-09-p5.sql` (fixture isolada)
--   3) este arquivo             (asserts `[PASS]`/`[FAIL]`)
--
-- Contrato coberto (docs/F5-09-desenho-tecnico.md §9 RLS, §13.5, §19 P5; D22):
--   A  authenticated com membership ATIVA le os ciclos do PROPRIO tenant;
--   B  cross-tenant (por filtro e por UUID/IDOR) NAO retorna ciclo alheio;
--   C  membership inexistente => zero linhas;
--   D  membership revogada/inativa e profile inativo => zero linhas (fail-closed);
--   E  JWT sem profile/membership (sem vinculo soberano) => zero linhas;
--   F  INSERT direto de authenticated => negado (42501, causa especifica);
--   G  UPDATE direto de authenticated => negado (42501, causa especifica);
--   H  DELETE direto de authenticated => negado (42501, causa especifica);
--   I  policy e grants do contrato existem (policy SELECT own-tenant + SELECT);
--   J  nenhuma policy abriu ESCRITA, anon sem acesso e a trilha segue fechada;
--   K  regressoes P1–P4 intactas (I5/I6/trilha append-only + 8 RPCs de mutacao
--      continuam INVOKER com EXECUTE so service_role).
--
-- A prova central e SEMANTICA: sob o MESMO papel (`authenticated`) e o MESMO
-- grant de SELECT, a visibilidade muda conforme a MEMBERSHIP do ator — ou seja,
-- quem filtra e a POLICY (tenant boundary), nao o privilegio.
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer falha aborta.
-- Nenhuma excecao e capturada de forma generica: as negativas de escrita usam
-- `when insufficient_privilege` explicito (negacao por ACL nunca conta como
-- sucesso de outro motivo).
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture, RLS, policy/grants do contrato e baseline P1–P4
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'eca00000-0000-0000-0000-0000000000a1';
  v_n      int;
  v_policy record;
  v_fn     text;
  v_rec    record;
begin
  select count(*) into v_n from public.evaluation_cycles
   where organization_id = v_org;
  if v_n <> 2 then
    raise exception '[FAIL] pre-condicao: fixture F5-09 P5 ausente (ciclos em Alfa=%) — execute 09-cenario-f5-09-p5.sql', v_n;
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'evaluation_cycles' and c.relrowsecurity
  ) then
    raise exception '[FAIL] pre-condicao: RLS desabilitada em evaluation_cycles';
  end if;

  select p.cmd, p.roles, coalesce(p.qual, '') as qual into v_policy
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'evaluation_cycles'
     and p.policyname = 'evaluation_cycles_select_same_tenant';
  if not found then
    raise exception '[FAIL] pre-condicao: policy evaluation_cycles_select_same_tenant ausente';
  end if;
  if v_policy.cmd <> 'SELECT'
     or not ('authenticated'::name = any(v_policy.roles))
     or position('user_has_active_membership' in v_policy.qual) = 0
     or position('organization_id' in v_policy.qual) = 0 then
    raise exception '[FAIL] pre-condicao: policy fora do contrato own-tenant (% / % / %)',
      v_policy.cmd, array_to_string(v_policy.roles, ','), v_policy.qual;
  end if;
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'SELECT') is not true then
    raise exception '[FAIL] pre-condicao: authenticated sem SELECT em evaluation_cycles';
  end if;

  raise notice '[PASS] pre-condicoes: fixture presente (2 ciclos em Alfa-P5), RLS habilitada, policy SELECT own-tenant e grant minimo conforme o §9';
end $$;

-- ----------------------------------------------------------------------------
-- A) own-tenant: u_alfa le os ciclos do PROPRIO tenant
-- ----------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'ecc00000-0000-0000-0000-000000000001', false);
set role authenticated;

do $$
declare
  v_alfa  uuid := 'eca00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'eca00000-0000-0000-0000-0000000000b1';
  v_n     int;
  v_outro int;
  v_ativo int;
  v_porid int;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 2 then
    raise exception '[FAIL] A: leitor de Alfa deveria ver exatamente 2 ciclos (%)', v_n;
  end if;
  select count(*) into v_outro from public.evaluation_cycles
   where organization_id <> v_alfa;
  if v_outro <> 0 then
    raise exception '[FAIL] A: leitura retornou ciclo de OUTRO tenant (%)', v_outro;
  end if;
  select count(*) into v_n from public.evaluation_cycles where organization_id = v_alfa;
  if v_n <> 2 then
    raise exception '[FAIL] A: filtro pela propria organizacao deveria devolver 2 (%)', v_n;
  end if;
  select count(*) into v_ativo from public.evaluation_cycles where status = 'ATIVO';
  if v_ativo <> 1 then
    raise exception '[FAIL] A: o tenant deveria expor 1 ciclo ATIVO (%)', v_ativo;
  end if;
  -- Identidade canonica: o ciclo ATIVO e alcancado por UUID.
  select count(*) into v_porid from public.evaluation_cycles
   where id = 'ecd10000-0000-0000-0000-000000000001';
  if v_porid <> 1 then
    raise exception '[FAIL] A: ciclo ATIVO nao resolvido pelo proprio UUID (%)', v_porid;
  end if;
  -- O leitor de Alfa NAO ve o ciclo do Beta nem por UUID explicito (IDOR).
  select count(*) into v_porid from public.evaluation_cycles
   where id = 'ecd10000-0000-0000-0000-0000000000b1';
  if v_porid <> 0 then
    raise exception '[FAIL] A/B: IDOR — leitor de Alfa alcancou o ciclo do Beta por UUID';
  end if;
  if (select count(*) from public.evaluation_cycles where organization_id = v_beta) <> 0 then
    raise exception '[FAIL] B: filtro pelo tenant alheio deveria devolver zero linhas';
  end if;

  raise notice '[PASS] A/B: leitor de Alfa-P5 le exatamente os 2 ciclos do proprio tenant (incluindo o ATIVO por UUID) e ZERO do tenant alheio — inclusive por UUID explicito (IDOR) e por filtro direto';
end $$;

reset role;

-- ----------------------------------------------------------------------------
-- B) simetria: u_beta le apenas o proprio tenant
-- ----------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'ecc00000-0000-0000-0000-000000000002', false);
set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 1 then
    raise exception '[FAIL] B: leitor do Beta deveria ver exatamente 1 ciclo (%)', v_n;
  end if;
  if (select count(*) from public.evaluation_cycles
       where organization_id = 'eca00000-0000-0000-0000-0000000000a1') <> 0 then
    raise exception '[FAIL] B: leitor do Beta alcancou ciclos de Alfa';
  end if;
  raise notice '[PASS] B: simetria cross-tenant confirmada (leitor do Beta ve somente o ciclo do Beta)';
end $$;

reset role;

-- ----------------------------------------------------------------------------
-- C) membership inexistente => DENY (zero linhas)
-- ----------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'ecc00000-0000-0000-0000-000000000003', false);
set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 0 then
    raise exception '[FAIL] C: usuario SEM membership deveria ver zero linhas (%)', v_n;
  end if;
  raise notice '[PASS] C: usuario sem vinculo (membership inexistente) nao le nenhum ciclo (policy = tenant boundary)';
end $$;

reset role;

-- ----------------------------------------------------------------------------
-- D) membership revogada/inativa e profile inativo => DENY (fail-closed)
-- ----------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'ecc00000-0000-0000-0000-000000000004', false);
set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 0 then
    raise exception '[FAIL] D: membership DISABLED deveria ver zero linhas (%)', v_n;
  end if;
  raise notice '[PASS] D: membership revogada/inativa nao le nenhum ciclo';
end $$;

reset role;

select set_config('request.jwt.claim.sub', 'ecc00000-0000-0000-0000-000000000005', false);
set role authenticated;

do $$
declare
  v_n   int;
  v_ok  boolean;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 0 then
    raise exception '[FAIL] D: profile INATIVO (membership ativa) deveria ver zero linhas (%)', v_n;
  end if;
  select public.user_has_active_membership('eca00000-0000-0000-0000-0000000000a1') into v_ok;
  if v_ok is not false then
    raise exception '[FAIL] D: helper de tenant deveria ser false com profile inativo';
  end if;
  raise notice '[PASS] D: profile inativo + membership ativa => DENY fail-closed (o helper exige profile ATIVO)';
end $$;

reset role;

-- ----------------------------------------------------------------------------
-- E) JWT sem profile/membership (sem vinculo soberano) => DENY
-- ----------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'ecc00000-0000-0000-0000-000000000006', false);
set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 0 then
    raise exception '[FAIL] E: identidade sem profile/membership deveria ver zero linhas (%)', v_n;
  end if;
  raise notice '[PASS] E: autenticacao sem vinculo valido (profile/membership) nao le nenhum ciclo';
end $$;

reset role;

-- ----------------------------------------------------------------------------
-- F/G/H) ESCRITA direta de authenticated => negada (causa especifica 42501)
-- ----------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', 'ecc00000-0000-0000-0000-000000000001', false);
set role authenticated;

do $$
declare
  v_ok      boolean;
  v_status  text;
  v_versao  int;
  v_antes   int;
  v_depois  int;
begin
  select count(*) into v_antes from public.evaluation_cycles;

  -- (F) INSERT direto.
  v_ok := false;
  begin
    insert into public.evaluation_cycles
      (id, organization_id, ano, numero, status, data_inicio, data_fim, version)
    values ('ecd10000-0000-0000-0000-00000000ff01',
            'eca00000-0000-0000-0000-0000000000a1',
            2036, 1, 'PLANEJADO', date '2036-01-01', date '2036-03-31', 0);
    raise exception '[FAIL] F: INSERT direto de authenticated foi ACEITO';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] F: INSERT direto deveria ser negado por insufficient_privilege';
  end if;

  -- (G) UPDATE direto.
  v_ok := false;
  begin
    update public.evaluation_cycles
       set status = 'ENCERRADO'
     where id = 'ecd10000-0000-0000-0000-000000000001';
    raise exception '[FAIL] G: UPDATE direto de authenticated foi ACEITO';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] G: UPDATE direto deveria ser negado por insufficient_privilege';
  end if;

  -- (H) DELETE direto.
  v_ok := false;
  begin
    delete from public.evaluation_cycles
     where id = 'ecd10000-0000-0000-0000-000000000002';
    raise exception '[FAIL] H: DELETE direto de authenticated foi ACEITO';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] H: DELETE direto deveria ser negado por insufficient_privilege';
  end if;

  -- Nenhuma tentativa produziu efeito observavel.
  select count(*) into v_depois from public.evaluation_cycles;
  if v_depois <> v_antes then
    raise exception '[FAIL] F/G/H: tentativa de escrita alterou a populacao visivel (% -> %)', v_antes, v_depois;
  end if;
  select status, version into v_status, v_versao from public.evaluation_cycles
   where id = 'ecd10000-0000-0000-0000-000000000001';
  if v_status <> 'ATIVO' or v_versao <> 1 then
    raise exception '[FAIL] G: o ciclo ATIVO foi alterado por tentativa de escrita (%, %)', v_status, v_versao;
  end if;
  if exists (select 1 from public.evaluation_cycles where id = 'ecd10000-0000-0000-0000-00000000ff01') then
    raise exception '[FAIL] F: linha foi criada por tentativa de INSERT';
  end if;

  raise notice '[PASS] F/G/H: INSERT, UPDATE e DELETE diretos de authenticated sao negados por insufficient_privilege e nenhuma tentativa produz efeito (ciclo ATIVO intacto)';
end $$;

reset role;

-- ----------------------------------------------------------------------------
-- I/J) Catalogo efetivo: policy e grants do contrato; nenhuma escrita aberta
-- ----------------------------------------------------------------------------
do $$
declare
  v_policy     record;
  v_problemas  text[] := array[]::text[];
  v_priv       text;
  v_n          int;
begin
  -- (I) Exatamente UMA policy, de SELECT, para authenticated, com o predicado.
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'evaluation_cycles';
  if v_n <> 1 then
    v_problemas := v_problemas || ('policies em evaluation_cycles = ' || v_n || ' (esperado 1)');
  end if;
  select p.cmd, p.roles, coalesce(p.qual, '') as qual, p.permissive into v_policy
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'evaluation_cycles'
     and p.policyname = 'evaluation_cycles_select_same_tenant';
  if not found then
    v_problemas := v_problemas || 'policy evaluation_cycles_select_same_tenant ausente'::text;
  else
    if v_policy.cmd <> 'SELECT' then
      v_problemas := v_problemas || ('cmd da policy = ' || v_policy.cmd);
    end if;
    if not ('authenticated'::name = any(v_policy.roles)) then
      v_problemas := v_problemas || 'policy nao se aplica a authenticated'::text;
    end if;
    if 'anon'::name = any(v_policy.roles) then
      v_problemas := v_problemas || 'policy exposta a anon'::text;
    end if;
    if v_policy.permissive <> 'PERMISSIVE' then
      v_problemas := v_problemas || 'policy nao e PERMISSIVE'::text;
    end if;
    if v_policy.qual not like '%user_has_active_membership%'
       or v_policy.qual not like '%organization_id%' then
      v_problemas := v_problemas || ('predicado da policy fora do contrato: ' || v_policy.qual);
    end if;
  end if;

  -- (I) Grant minimo presente; (J) nenhum DML e nenhum privilegio a anon.
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'SELECT') is not true then
    v_problemas := v_problemas || 'authenticated sem SELECT'::text;
  end if;
  foreach v_priv in array array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']
  loop
    if has_table_privilege('authenticated', 'public.evaluation_cycles', v_priv) then
      v_problemas := v_problemas || ('authenticated com ' || v_priv);
    end if;
    if has_table_privilege('anon', 'public.evaluation_cycles', v_priv) then
      v_problemas := v_problemas || ('anon com ' || v_priv);
    end if;
  end loop;
  if has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT') then
    v_problemas := v_problemas || 'anon com SELECT'::text;
  end if;

  -- (J) Nenhuma policy de escrita em QUALQUER tabela de ciclo e a trilha fechada.
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_cycles' and cmd <> 'SELECT'
  ) then
    v_problemas := v_problemas || 'policy de ESCRITA aberta em evaluation_cycles'::text;
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'cycle_events') then
    v_problemas := v_problemas || 'policy em cycle_events (trilha deve ser deny-by-default)'::text;
  end if;
  if has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'trilha cycle_events legivel por cliente'::text;
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'SELECT') is not true
     or has_table_privilege('service_role', 'public.cycle_events', 'INSERT') is not true then
    v_problemas := v_problemas || 'service_role perdeu acesso a trilha'::text;
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] I/J: %', array_to_string(v_problemas, '; ');
  end if;

  raise notice '[PASS] I/J: policy SELECT own-tenant unica e conforme o §9, grant minimo de SELECT, ZERO privilegio de escrita a authenticated/anon e trilha cycle_events ainda deny-by-default';
end $$;

-- ----------------------------------------------------------------------------
-- K) Regressoes P1–P4 intactas (integridade + superficie de mutacao fechada)
-- ----------------------------------------------------------------------------
do $$
declare
  v_fn        text;
  v_rec       record;
  v_problemas text[] := array[]::text[];
begin
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_problemas := v_problemas || 'I5 ausente'::text;
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycles'::regclass
       and c.conname = 'ex_evaluation_cycles_periodo_no_overlap' and c.contype = 'x'
  ) then
    v_problemas := v_problemas || 'I6 ausente'::text;
  end if;
  foreach v_fn in array array[
    'trg_cycle_events_append_only', 'trg_cycle_events_no_delete',
    'trg_cycle_events_no_truncate']
  loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = 'public.cycle_events'::regclass
         and tgname = v_fn and not tgisinternal
    ) then
      v_problemas := v_problemas || ('trigger ausente: ' || v_fn);
    end if;
  end loop;

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
      v_problemas := v_problemas || ('RPC exposta a cliente: ' || v_fn);
    end if;
  end loop;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] K: %', array_to_string(v_problemas, '; ');
  end if;

  raise notice '[PASS] K: regressoes P1–P4 intactas (I5/I6, trilha append-only com os 3 triggers) e as 8 RPCs de mutacao seguem INVOKER com EXECUTE so service_role (a leitura nao abriu superficie de escrita)';
end $$;

-- ============================================================================
-- Resumo e cleanup explicito do contexto de sessao
-- ============================================================================
select set_config('request.jwt.claim.sub', '', false);

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-09 P5: leitura soberana de ciclos validada — own-tenant permitido, cross-tenant/IDOR negado, membership inexistente/revogada/inativa e profile inativo fail-closed, JWT sem vinculo negado, escrita direta de authenticated negada (42501) e trilha fechada.';
end $$;
