-- ============================================================================
-- F5-08 P6 — validação de CUTOVER ESTRUTURAL (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (migrations)
--   2) `01-cenario-f5-08.sql`  (fixture sintética, prefixo `f8`)
--   3) `02-validar-f5-08.sql`  (schema/RLS/grants/RPCs + comportamento A–L)
--   4) este arquivo            (cutover: PostgreSQL é a ÚNICA autoridade)
--
-- Contrato: docs/F5-08-desenho-tecnico.md §19 (arquitetura final do P6),
-- §23.1 (`03-validar-f5-08-cutover.sql`) e §23.2 grupo H (frontend/cutover).
--
-- O que ESTE arquivo prova (§23.1: cross-tenant, capability negada,
-- concorrência, idempotência, ciclo, encerramento com estrutura vigente,
-- histórico preservado) e por que não é redundante com o `02`:
--
--   §1 leitura estrutural do cliente é RLS own-tenant — exercita o caminho REAL
--      de leitura nas 17 tabelas estruturais, com prova POSITIVA (membro ativo
--      lê o próprio tenant) e NEGATIVA (zero linhas de outro tenant). O `02`
--      verifica policies e grants; aqui a LEITURA é executada como
--      `authenticated`, que é a autoridade de leitura de produção;
--   §2 fail-closed na leitura: sem membership ATIVA — e para ator desconhecido —
--      não existe NENHUMA fonte alternativa de estrutura (nenhum fallback);
--   §3 a superfície de ESCRITA do cliente é fechada nas tabelas estruturais
--      (varredura das 17 + `structure_events`), de modo que uma tabela nova mal
--      configurada não passe: nenhum INSERT/UPDATE/DELETE/TRUNCATE, nenhuma
--      policy de escrita, `anon` sem leitura;
--   §4 capability negada: ator sem `org.structure.manage` é FORBIDDEN e nada é
--      escrito (cross-tenant, concorrência e idempotência comportamentais estão
--      no `02`, grupos B/C/D/E; ciclo e encerramento com estrutura vigente nos
--      grupos E/F/G do `02` e no `01` I1/I2/I3);
--   §5 a ÚNICA autoridade de mutação é a RPC transacional: EXECUTE somente
--      `service_role`, nenhuma superfície para `authenticated` (probe real) e
--      zero `SECURITY DEFINER`;
--   §6 concorrência: TODAS as funções que serializam mutação estrutural usam
--      UMA única chave normativa por organização (D24) — varredura GLOBAL, não
--      apenas nas 4 RPCs verificadas pelo `02`;
--   §7 idempotência e histórico: unicidade `(organization_id, operation_id)`,
--      encerramento temporal (nunca DELETE) e histórico de vigências preservado.
--
-- Saída determinística: um `[PASS]` por verificação; qualquer falha levanta
-- exceção e aborta com código de saída não-zero. Nenhum projeto remoto é usado e
-- somente dados fictícios. O único estado alterado (status da membership
-- sintética do ator sem capability) é restaurado no fim do arquivo.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) LEITURA ESTRUTURAL FECHADA — a superficie do cliente sao as views (#327 P3)
-- ============================================================================
-- D16 REVISADO (#327 P3): a leitura own-tenant por RLS foi FECHADA. O ator
-- autenticado NAO le mais as tabelas estruturais; a leitura soberana passa a
-- existir SOMENTE pelas views aprovadas no P1/P2 — estrutura_administrativa
-- (capability efetiva), estrutura_pessoal (subgrafo vigente do proprio ator) e
-- estrutura_autorizacao (projecao de menu/rotas).

-- Ator de Alfa COM capability (role de sistema admin + scope ORGANIZATION).
select set_config('request.jwt.claim.sub', 'f8c00000-0000-0000-0000-0000000000a1', false);
set role authenticated;

do $$
declare
  v_fechadas text[] := array[
    'collaborators','job_roles','seniority_levels','organizational_units',
    'organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','collegiate_configurations',
    'organizational_position_responsibilities',
    'organizational_position_responsibilities_catalog',
    'organizational_position_responsibility_bundle',
    'organizational_position_responsibility_events',
    'collegiate_configuration_members','collaborator_status_periods'];
  v_tab text;
  v_ok boolean;
  v_n int;
  v_orgs int;
  v_unidades int;
begin
  -- (a) acesso DIRETO as tabelas estruturais: NEGADO (nao ha grant).
  foreach v_tab in array v_fechadas loop
    v_ok := false;
    begin
      execute format('select count(*) from public.%I', v_tab) into v_n;
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then
      raise exception '[FAIL] P6-1: ator autenticado leu public.% (%) — leitura direta deveria estar FECHADA (#327 P3)', v_tab, v_n;
    end if;
  end loop;

  -- (b) a leitura soberana vem da VIEW, do PROPRIO tenant (cross-tenant zero).
  select count(*) into v_orgs from public.estrutura_administrativa;
  if v_orgs <> 1 then
    raise exception '[FAIL] P6-1: linhas administrativas = % (esperado 1)', v_orgs;
  end if;
  select count(*) into v_n from public.estrutura_administrativa
   where organization_id = 'f8a00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] P6-1 (cross-tenant): membro de Alfa leu % fotografia(s) de Beta', v_n;
  end if;

  -- Nao vacuidade: a view devolve dados REAIS do proprio tenant.
  select jsonb_array_length(unidades) into v_unidades
    from public.estrutura_administrativa;
  if coalesce(v_unidades, 0) < 20 then
    raise exception '[FAIL] P6-1: leitura own-tenant vazia ou parcial (unidades=%) — prova vacuamente verde', v_unidades;
  end if;

  raise notice '[PASS] P6-1: leitura direta FECHADA nas 15 tabelas estruturais e leitura soberana pela view administrativa do PROPRIO tenant (% unidades, zero de Beta)', v_unidades;
end $$;

reset role;

-- Prova NEGATIVA simetrica: o ator de BETA e membership-only (sem capability) e
-- portanto nao recebe NENHUMA linha das views — nem do proprio tenant.
select set_config('request.jwt.claim.sub', 'f8c00000-0000-0000-0000-0000000000b1', false);
set role authenticated;

do $$
declare
  v_admin int;
  v_pessoal int;
  v_auth int;
  v_ok boolean;
begin
  select count(*) into v_admin from public.estrutura_administrativa;
  if v_admin <> 0 then
    raise exception '[FAIL] P6-1: membership-only recebeu % linha(s) administrativa(s)', v_admin;
  end if;
  select count(*) into v_pessoal from public.estrutura_pessoal;
  if v_pessoal <> 0 then
    raise exception '[FAIL] P6-1: membership-only sem vinculo recebeu projecao pessoal (%)', v_pessoal;
  end if;
  select count(*) into v_auth from public.estrutura_autorizacao;
  if v_auth <> 1 then
    raise exception '[FAIL] P6-1: projecao de autorizacao esperada=1, encontrada=%', v_auth;
  end if;

  v_ok := false;
  begin perform count(*) from public.organizational_units;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then
    raise exception '[FAIL] P6-1: membership-only leu tabela estrutural direta';
  end if;

  raise notice '[PASS] P6-1: prova simetrica — membership-only de Beta recebe ZERO leitura administrativa/pessoal e nao le tabela direta';
end $$;

reset role;

-- ============================================================================
-- 2) FAIL-CLOSED — sem capability/vinculo nao ha fotografia; sem membership, nada
-- ============================================================================
-- (a) Controle NEGATIVO: o ator a2 tem membership ATIVA em Alfa e NAO tem
--     capability — logo nao recebe fotografia administrativa.
select set_config('request.jwt.claim.sub', 'f8c00000-0000-0000-0000-0000000000a2', false);
set role authenticated;

do $$
declare
  v_admin int;
  v_flags text;
begin
  select count(*) into v_admin from public.estrutura_administrativa;
  if v_admin <> 0 then
    raise exception '[FAIL] P6-2: ator sem capability recebeu % leitura(s) administrativa(s)', v_admin;
  end if;
  select pode_estrutura::text || '/' || pode_catalogo::text into v_flags
    from public.estrutura_autorizacao;
  if v_flags is distinct from 'false/false' then
    raise exception '[FAIL] P6-2: projecao de autorizacao = % (esperado false/false)', v_flags;
  end if;
  raise notice '[PASS] P6-2: ator com membership ATIVA e SEM capability => zero fotografia administrativa (fail-closed)';
end $$;

reset role;

-- (b) Membership DESATIVADA: nenhuma linha nas tres views.
update public.user_organization_memberships
   set status = 'disabled'
 where id = 'f8d00000-0000-0000-0000-0000000000a2';

set role authenticated;

do $$
declare v_n int;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then raise exception '[FAIL] P6-2: membership inativa recebeu % linha(s) administrativa(s)', v_n; end if;
  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 0 then raise exception '[FAIL] P6-2: membership inativa recebeu projecao pessoal (%)', v_n; end if;
  select count(*) into v_n from public.estrutura_autorizacao;
  if v_n <> 0 then raise exception '[FAIL] P6-2: membership inativa apareceu na projecao de autorizacao (%)', v_n; end if;
  raise notice '[PASS] P6-2: membership INATIVA => ZERO linha nas tres views (nenhum fallback local ou de outro tenant)';
end $$;

reset role;

update public.user_organization_memberships
   set status = 'active'
 where id = 'f8d00000-0000-0000-0000-0000000000a2';

-- (c) Ator DESCONHECIDO (sem membership em nenhuma organizacao): mesmo resultado.
select set_config('request.jwt.claim.sub', 'f8c00000-0000-0000-0000-0000000000a9', false);
set role authenticated;

do $$
declare
  v_n int;
  v_ok boolean;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then raise exception '[FAIL] P6-2: ator sem membership recebeu leitura administrativa (%)', v_n; end if;
  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 0 then raise exception '[FAIL] P6-2: ator sem membership recebeu projecao pessoal (%)', v_n; end if;
  select count(*) into v_n from public.estrutura_autorizacao;
  if v_n <> 0 then raise exception '[FAIL] P6-2: ator sem membership apareceu na autorizacao (%)', v_n; end if;

  v_ok := false;
  begin perform count(*) from public.organizational_units;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception '[FAIL] P6-2: ator sem membership leu tabela estrutural direta'; end if;

  raise notice '[PASS] P6-2: ator SEM membership => ZERO linha nas views e nenhum acesso direto (fail-closed, nunca dados de terceiros)';
end $$;

reset role;

-- Restaura a identidade da fixture para o restante do arquivo.
select set_config('request.jwt.claim.sub', '', false);

-- ============================================================================
-- 3) SUPERFICIE DO CLIENTE — 3 views legiveis; estruturais FECHADAS
-- ============================================================================

do $$
declare
  v_fechadas text[] := array[
    'collaborators','job_roles','seniority_levels','organizational_units',
    'organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','collegiate_configurations',
    'organizational_position_responsibilities',
    'organizational_position_responsibilities_catalog',
    'organizational_position_responsibility_bundle',
    'organizational_position_responsibility_events',
    'collegiate_configuration_members','collaborator_status_periods'];
  v_legiveis text[] := array[
    'collaborator_identifiers','temporary_responsibilities',
    'cycle_evaluation_responsibilities','collegiate_cycle_snapshots',
    'collegiate_cycle_snapshot_positions','collegiate_cycle_snapshot_members'];
  v_escrita text[] := array['INSERT','UPDATE','DELETE','TRUNCATE'];
  v_tab text;
  v_priv text;
  v_n int;
  v_lista text;
  v_def text;
begin
  -- P1: as tabelas FECHADAS pelo #327 P3 nao tem policy de NENHUM cmd e nao
  -- concedem privilegio algum ao cliente (RLS segue habilitada).
  foreach v_tab in array v_fechadas loop
    select count(*) into v_n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_tab and c.relkind = 'r'
       and c.relrowsecurity;
    if v_n <> 1 then
      raise exception '[FAIL] P6-3: public.% sem RLS habilitada', v_tab;
    end if;

    select count(*) into v_n
      from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_n <> 0 then
      raise exception '[FAIL] P6-3: public.% ainda tem % policy(ies) — deveria ser deny-by-default integral', v_tab, v_n;
    end if;

    if has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT') then
      raise exception '[FAIL] P6-3: authenticated com SELECT em public.% (tabela fechada)', v_tab;
    end if;
  end loop;

  -- P2: as tabelas LEGIVEIS remanescentes seguem com policy SELECT own-tenant e
  -- SELECT efetivo para authenticated.
  foreach v_tab in array v_legiveis loop
    select count(*) into v_n
      from pg_policies
     where schemaname = 'public' and tablename = v_tab
       and cmd = 'SELECT' and 'authenticated'::name = any(roles);
    if v_n < 1 then
      raise exception '[FAIL] P6-3: public.% sem policy SELECT own-tenant para authenticated', v_tab;
    end if;

    if not has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT') then
      raise exception '[FAIL] P6-3: authenticated sem SELECT em public.%', v_tab;
    end if;
  end loop;

  -- P3: nenhum privilegio de escrita para o cliente e anon sem leitura.
  foreach v_tab in array (v_fechadas || v_legiveis) loop
    foreach v_priv in array v_escrita loop
      if has_table_privilege('authenticated', format('public.%I', v_tab), v_priv) then
        raise exception '[FAIL] P6-3: authenticated tem % em public.% — superficie de escrita estrutural aberta', v_priv, v_tab;
      end if;
      if has_table_privilege('anon', format('public.%I', v_tab), v_priv) then
        raise exception '[FAIL] P6-3: anon tem % em public.%', v_priv, v_tab;
      end if;
    end loop;

    if has_table_privilege('anon', format('public.%I', v_tab), 'SELECT') then
      raise exception '[FAIL] P6-3: anon le public.%', v_tab;
    end if;
  end loop;

  -- P4: nenhuma policy de escrita nas tabelas estruturais em questao.
  select count(*), string_agg(tablename || ':' || cmd, ', ' order by tablename, cmd)
    into v_n, v_lista
    from pg_policies
   where schemaname = 'public' and tablename = any(v_fechadas || v_legiveis) and cmd <> 'SELECT';
  if v_n <> 0 then
    raise exception '[FAIL] P6-3: policy de escrita em tabela estrutural: %', v_lista;
  end if;

  -- P5: as TRES views do #327 sao a superficie estrutural legivel do cliente.
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and c.relname in ('estrutura_administrativa','estrutura_pessoal','estrutura_autorizacao')
     and has_table_privilege('authenticated', c.oid, 'SELECT');
  if v_n <> 3 then
    raise exception '[FAIL] P6-3: % das 3 views aprovadas legiveis', v_n;
  end if;

  -- P6: structure_events e 100% fechada ao cliente (trilha de auditoria) e
  -- append-only mesmo para quem tem escrita.
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'structure_events'
     and c.relkind = 'r' and c.relrowsecurity;
  if v_n <> 1 then
    raise exception '[FAIL] P6-3: structure_events sem RLS habilitada';
  end if;

  select count(*) into v_n
    from pg_policies where schemaname = 'public' and tablename = 'structure_events';
  if v_n <> 0 then
    raise exception '[FAIL] P6-3: structure_events com % policy(ies) — deveria ser deny-by-default integral', v_n;
  end if;

  foreach v_priv in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE'] loop
    if has_table_privilege('authenticated', 'public.structure_events', v_priv) then
      raise exception '[FAIL] P6-3: authenticated tem % em structure_events (trilha exposta ao cliente)', v_priv;
    end if;
    if has_table_privilege('anon', 'public.structure_events', v_priv) then
      raise exception '[FAIL] P6-3: anon tem % em structure_events', v_priv;
    end if;
  end loop;

  select pg_get_triggerdef(t.oid) into v_def
    from pg_trigger t
   where t.tgrelid = 'public.structure_events'::regclass
     and t.tgname = 'trg_structure_events_append_only'
     and not t.tgisinternal;
  if v_def is null or v_def not like '%BEFORE UPDATE%' then
    raise exception '[FAIL] P6-3: structure_events sem trigger append-only BEFORE UPDATE';
  end if;

  raise notice '[PASS] P6-3: 15 tabelas estruturais FECHADAS (zero policy, zero privilegio), 6 legiveis remanescentes com policy own-tenant, 3 views como superficie de leitura, zero DML para anon/authenticated e trilha structure_events fechada/append-only';
end $$;

-- ============================================================================
-- 4) CAPABILITY NEGADA — a estrutura não é autorizada pelo cliente
-- ============================================================================

do $$
declare
  v_caps int;
  v_msg text;
  v_res uuid;
begin
  -- Pre-condição: o ator a2 NÃO resolve nenhuma capability efetiva (nem a de
  -- estrutura nem a de catálogo) — a decisão é sempre server-side (D19).
  select count(*) into v_caps
    from public.resolver_capabilities_escopos_efetivas(
      'f8c00000-0000-0000-0000-0000000000a2',
      'f8a00000-0000-0000-0000-0000000000a1');
  if v_caps <> 0 then
    raise exception '[FAIL] P6-4: pre-condicao — ator sem capability resolveu % capability(ies)', v_caps;
  end if;

  v_msg := null;
  begin
    v_res := public.estrutura_unidade_criar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a2',
      'f8930000-0000-0000-0000-0000000000d1',
      'F5-08 P6 Sem Capability', '2026-06-01T00:00:00Z', 'teste P6-4');
  exception when others then v_msg := sqlerrm;
  end;

  if v_msg is null or v_msg not like 'F5_08_FORBIDDEN%' then
    raise exception '[FAIL] P6-4: ator sem org.structure.manage deveria ser FORBIDDEN (msg=%)', v_msg;
  end if;
  if exists (
    select 1 from public.structure_events
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'f8930000-0000-0000-0000-0000000000d1'
  ) then
    raise exception '[FAIL] P6-4: operacao negada gravou evento na trilha';
  end if;
  if exists (
    select 1 from public.organizational_units
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
       and name = 'F5-08 P6 Sem Capability'
  ) then
    raise exception '[FAIL] P6-4: operacao negada criou a unidade';
  end if;

  raise notice '[PASS] P6-4: capability negada — FORBIDDEN com prefixo padronizado, nenhuma escrita e nenhum evento';
end $$;

-- ============================================================================
-- 5) A ÚNICA AUTORIDADE DE MUTAÇÃO É A RPC TRANSACIONAL
-- ============================================================================

do $$
declare
  v_funcs text[] := array[
    'estrutura_unidade_criar','estrutura_unidade_renomear',
    'estrutura_unidade_encerrar','estrutura_unidade_parent_definir',
    'estrutura_unidade_parent_encerrar','estrutura_posicao_criar',
    'estrutura_posicao_renomear','estrutura_posicao_encerrar','estrutura_colegiado_definir',
    'estrutura_colegiado_encerrar','catalogo_cargo_criar',
    'catalogo_cargo_renomear','catalogo_cargo_status_alterar',
    'catalogo_senioridade_criar','catalogo_senioridade_renomear',
    'catalogo_senioridade_status_alterar'];
  v_fn text;
  v_oid oid;
  v_definer text;
  v_n int;
begin
  foreach v_fn in array v_funcs loop
    select p.oid into v_oid
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;

    if v_oid is null then
      raise exception '[FAIL] P6-5: RPC public.% ausente', v_fn;
    end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') then
      raise exception '[FAIL] P6-5: anon executa public.%', v_fn;
    end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') then
      raise exception '[FAIL] P6-5: authenticated executa public.% (superficie direta aberta)', v_fn;
    end if;
    if not has_function_privilege('service_role', v_oid, 'EXECUTE') then
      raise exception '[FAIL] P6-5: service_role NAO executa public.%', v_fn;
    end if;
  end loop;

  -- Zero SECURITY DEFINER na superfície estrutural (a autoridade é a transação
  -- da RPC com o ator revalidado, nunca um bypass de RLS).
  select count(*), string_agg(p.proname, ', ' order by p.proname)
    into v_n, v_definer
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and (p.proname = any(v_funcs)
          or p.proname in ('enforce_structure_events_append_only',
                           'enforce_organizational_unit_parent_periods_no_cycle',
                           'enforce_organizational_unit_close_requires_no_open_structure',
                           'enforce_organizational_position_close_requires_no_open_occupations'));
  if v_n <> 0 then
    raise exception '[FAIL] P6-5: SECURITY DEFINER na superficie estrutural: %', v_definer;
  end if;

  raise notice '[PASS] P6-5: as 15 RPCs estruturais sao SECURITY INVOKER com EXECUTE somente service_role (anon/authenticated negados)';
end $$;

-- Probe REAL: `authenticated` não consegue chamar a RPC nem com payload válido.
select set_config('request.jwt.claim.sub', 'f8c00000-0000-0000-0000-0000000000a1', false);
set role authenticated;

do $$
declare
  v_ok boolean := false;
  v_n int;
begin
  begin
    perform public.estrutura_unidade_criar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8930000-0000-0000-0000-0000000000d2',
      'F5-08 P6 Intrusao Direta', '2026-06-01T00:00:00Z', 'teste P6-5');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] P6-5: authenticated executou estrutura_unidade_criar';
  end if;

  -- Reseta o marcador: cada probe precisa provar a SUA propria negacao (um
  -- `v_ok` herdado tornaria a segunda verificacao vacuamente verde).
  v_ok := false;
  begin
    perform public.estrutura_unidade_renomear(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8930000-0000-0000-0000-0000000000d3',
      'f8110000-0000-0000-0000-000000000001',
      'F5-08 P6 Intrusao Renomear', 0, 'teste P6-5');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] P6-5: authenticated executou estrutura_unidade_renomear';
  end if;

  -- A trilha continua invisível e sem evento novo (nada foi produzido).
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'structure_events';
  if v_n <> 0 then
    raise exception '[FAIL] P6-5: structure_events ganhou policy (%)', v_n;
  end if;

  raise notice '[PASS] P6-5: authenticated NAO executa as RPC estruturais (insufficient_privilege real, sem escrita)';
end $$;

reset role;

do $$
begin
  if exists (
    select 1 from public.structure_events
     where operation_id in ('f8930000-0000-0000-0000-0000000000d2',
                            'f8930000-0000-0000-0000-0000000000d3')
  ) then
    raise exception '[FAIL] P6-5: intrusao direta gravou evento na trilha';
  end if;
  if exists (
    select 1 from public.organizational_units
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
       and name = 'F5-08 P6 Intrusao Direta'
  ) then
    raise exception '[FAIL] P6-5: intrusao direta criou unidade';
  end if;
  if exists (
    select 1 from public.organizational_units
     where id = 'f8110000-0000-0000-0000-000000000001'
       and name <> 'F5-08 Raiz'
  ) then
    raise exception '[FAIL] P6-5: intrusao direta renomeou a unidade raiz';
  end if;

  raise notice '[PASS] P6-5: nenhum efeito colateral das tentativas diretas do cliente (trilha e estrutura intactas)';
end $$;

-- ============================================================================
-- 6) CONCORRÊNCIA — UMA única chave normativa POR FAMÍLIA e por organização (D24)
--    (família estrutural: `position_reporting_lines:<org>`; demais famílias
--    catalogadas explicitamente com a sua própria chave)
-- ============================================================================

do $$
declare
  -- CATÁLOGO EXPLÍCITO da família ESTRUTURAL (D24): as 15 RPCs da F5-08 (P2),
  -- as 4 RPCs estruturais da F5-07 alinhadas a esta chave por
  -- `20260914020000_f5_08_lock_key_alignment.sql` e as 2 funcoes de trigger
  -- anti-ciclo (F3-04 e F5-08 P1). TODAS devem serializar com a chave normativa
  -- estrutural E com nenhuma outra — a prova e POR FUNCAO (fail-closed), nao por
  -- varredura textual que uma funcao estrutural poderia escapar.
  v_estruturais text[] := array[
    'estrutura_unidade_criar','estrutura_unidade_renomear',
    'estrutura_unidade_encerrar','estrutura_unidade_parent_definir',
    'estrutura_unidade_parent_encerrar','estrutura_posicao_criar',
    'estrutura_posicao_renomear','estrutura_posicao_encerrar','estrutura_colegiado_definir',
    'estrutura_colegiado_encerrar','catalogo_cargo_criar',
    'catalogo_cargo_renomear','catalogo_cargo_status_alterar',
    'catalogo_senioridade_criar','catalogo_senioridade_renomear',
    'catalogo_senioridade_status_alterar',
    'estrutura_ocupacao_definir','estrutura_ocupacao_encerrar',
    'estrutura_ocupacao_trocar',
    'estrutura_reporting_definir','estrutura_reporting_encerrar',
    'enforce_position_reporting_lines_no_cycle',
    'enforce_organizational_unit_parent_periods_no_cycle'];
  -- CATÁLOGO EXPLÍCITO das famílias NÃO estruturais que tambem serializam:
  -- função -> SUA chave normativa. F5-09 (família de CICLOS) usa
  -- `evaluation_cycles:<organization_id>`, deliberadamente DIFERENTE da chave
  -- estrutural (famílias distintas exigem chaves distintas; contrato F5-09 §11).
  -- Família nova exige catalogação explícita aqui: o fechamento em (3) reprova
  -- qualquer função com advisory lock fora dos dois catálogos.
  v_outras_fn  text[] := array['ciclo_lock_organizacao'];
  v_outras_key text[] := array['evaluation_cycles:'];
  v_responsabilidade_fn text[] := array[
    'estrutura_responsabilidade_criar','estrutura_responsabilidade_revogar'];
  v_responsabilidade_key text[] := array['position_responsibilities:','position_responsibilities:'];
  v_i int;
  v_n int;
  v_lista text;
begin
  -- (1) Família ESTRUTURAL: cada função catalogada existe, serializa e usa
  --     SOMENTE a chave normativa D24 (`position_reporting_lines:<org>`).
  for v_i in 1..array_length(v_estruturais, 1) loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_estruturais[v_i]
       and p.prosrc like '%pg_advisory_xact_lock%'
       and position('position_reporting_lines:' in p.prosrc) > 0;
    if v_n <> 1 then
      raise exception
        '[FAIL] P6-6: funcao estrutural % nao serializa com a chave normativa D24 (position_reporting_lines:<org>)',
        v_estruturais[v_i];
    end if;

    if exists (
      select 1
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_estruturais[v_i]
         and (position('evaluation_cycles:' in p.prosrc) > 0
              or position('f5_07_estrutura:' in p.prosrc) > 0)
    ) then
      raise exception
        '[FAIL] P6-6: funcao estrutural % usa chave de OUTRA familia', v_estruturais[v_i];
    end if;
  end loop;

  -- (2b) Família P3 de responsabilidades: chave própria, distinta da família
  --      estrutural de reporting e das demais famílias catalogadas.
  for v_i in 1..array_length(v_responsabilidade_fn, 1) loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_responsabilidade_fn[v_i]
       and p.prosrc like '%pg_advisory_xact_lock%'
       and position(v_responsabilidade_key[v_i] in p.prosrc) > 0;
    if v_n <> 1 then
      raise exception
        '[FAIL] P6-6: funcao P3 % nao usa a chave normativa declarada (%)',
        v_responsabilidade_fn[v_i], v_responsabilidade_key[v_i];
    end if;

    if exists (
      select 1
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_responsabilidade_fn[v_i]
         and (position('position_reporting_lines:' in p.prosrc) > 0
              or position('evaluation_cycles:' in p.prosrc) > 0
              or position('f5_07_estrutura:' in p.prosrc) > 0)
    ) then
      raise exception
        '[FAIL] P6-6: funcao P3 % reutiliza chave de outra familia',
        v_responsabilidade_fn[v_i];
    end if;
  end loop;

  -- (3) FAMÍLIAS NÃO ESTRUTURAIS catalogadas: usam a PRÓPRIA chave normativa e
  --     NUNCA a chave estrutural (reuso cruzado quebraria a serializacao).
  for v_i in 1..array_length(v_outras_fn, 1) loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_outras_fn[v_i]
       and p.prosrc like '%pg_advisory_xact_lock%'
       and position(v_outras_key[v_i] in p.prosrc) > 0;
    if v_n <> 1 then
      raise exception
        '[FAIL] P6-6: funcao de outra familia % nao usa a chave normativa declarada (%)',
        v_outras_fn[v_i], v_outras_key[v_i];
    end if;

    if exists (
      select 1
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_outras_fn[v_i]
         and position('position_reporting_lines:' in p.prosrc) > 0
    ) then
      raise exception
        '[FAIL] P6-6: funcao de outra familia % reutiliza a chave estrutural (familias distintas exigem chaves distintas)',
        v_outras_fn[v_i];
    end if;
  end loop;

  -- (4) FECHAMENTO: nenhuma função com advisory lock pode ficar fora dos
  --     catálogos. Uma função nova (de qualquer família) só passa se a sua
  --     família e a sua chave normativa forem catalogadas EXPLICITAMENTE aqui.
  select count(*), string_agg(p.proname, ', ' order by p.proname)
    into v_n, v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosrc like '%pg_advisory_xact_lock%'
      and not (p.proname = any(v_estruturais)
               or p.proname = any(v_responsabilidade_fn)
               or p.proname = any(v_outras_fn));
  if v_n <> 0 then
    raise exception
      '[FAIL] P6-6: funcao com advisory lock sem familia/chave catalogada: % (catalogue a familia e a chave normativa)',
      v_lista;
  end if;

  -- (5) Serialização não pode viver em função SECURITY DEFINER (bypass de RLS)
  --     — vale para TODAS as funções com lock, de qualquer família.
  select count(*), string_agg(p.proname, ', ' order by p.proname)
    into v_n, v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosrc like '%pg_advisory_xact_lock%'
     and p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] P6-6: serializacao em funcao SECURITY DEFINER: %', v_lista;
  end if;

  -- (6) Não vacuidade: a família estrutural realmente serializa com a chave
  --     normativa (RPCs + triggers) — a prova não pode passar vazia.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = any(v_estruturais)
     and position('position_reporting_lines:' in p.prosrc) > 0;
  if v_n < 15 then
    raise exception
      '[FAIL] P6-6: apenas % funcoes ESTRUTURAIS serializam com a chave D24 (esperado >= 15)', v_n;
  end if;

  raise notice '[PASS] P6-6: % funcoes ESTRUTURAIS com a chave unica D24 (position_reporting_lines:<org>), % funcoes P3 e % funcao(oes) de outra familia com chave normativa propria catalogada, todas SECURITY INVOKER',
    v_n, array_length(v_responsabilidade_fn, 1), array_length(v_outras_fn, 1);
end $$;

-- ============================================================================
-- 7) IDEMPOTÊNCIA E HISTÓRICO PRESERVADO
-- ============================================================================

do $$
declare
  v_n int;
  v_lista text;
begin
  -- P1: idempotência por `(organization_id, operation_id)` na trilha.
  select count(*) into v_n
    from pg_index i join pg_class c on c.oid = i.indrelid
   where c.relname = 'structure_events' and i.indisunique
     and pg_get_indexdef(i.indexrelid) like '%(organization_id, operation_id)%';
  if v_n < 1 then
    raise exception '[FAIL] P6-7: unique (organization_id, operation_id) ausente em structure_events';
  end if;

  -- P2: a superfície estrutural NÃO tem operação de exclusão física —
  -- encerramento é sempre temporal (`valid_to`/`status`).
  select count(*), string_agg(p.proname, ', ' order by p.proname)
    into v_n, v_lista
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'estrutura\_%' or p.proname like 'catalogo\_%'
          or p.proname like 'colaborador\_%')
     and (p.proname like '%excluir%' or p.proname like '%deletar%'
          or p.proname like '%remover%' or p.proname like '%apagar%');
  if v_n <> 0 then
    raise exception '[FAIL] P6-7: operacao de exclusao fisica na superficie estrutural: %', v_lista;
  end if;

  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('estrutura_unidade_encerrar','estrutura_posicao_encerrar',
                       'estrutura_colegiado_encerrar','estrutura_unidade_parent_encerrar',
                       'catalogo_cargo_status_alterar','catalogo_senioridade_status_alterar');
  if v_n <> 6 then
    raise exception '[FAIL] P6-7: encerramento/desativacao temporal incompleto (% de 6 funcoes)', v_n;
  end if;

  -- P3: o histórico de vigências encerradas continua existindo e legível
  -- (encerrar hoje não apaga nem reescreve o passado).
  select count(*) into v_n
    from public.organizational_unit_parent_periods
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
     and valid_to is not null;
  if v_n < 1 then
    raise exception '[FAIL] P6-7: nenhuma vigencia encerrada preservada (historico apagado?)';
  end if;

  raise notice '[PASS] P6-7: idempotencia por operation_id na trilha, encerramento temporal (sem DELETE) e historico de vigencias preservado';
end $$;

-- ============================================================================
-- 8) RESUMO
-- ============================================================================

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-08 P6 (cutover): todas as verificacoes passaram — a leitura estrutural do cliente e RLS own-tenant e fail-closed, a superficie de escrita do cliente e fechada, a mutacao e exclusivamente por RPC transacional autorizada server-side, a serializacao usa uma unica chave normativa por familia e por organizacao (D24) e o historico permanece preservado.';
end $$;
