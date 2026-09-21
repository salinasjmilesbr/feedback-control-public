-- ============================================================================
-- F6-A21 P3 (Issue #327) — FECHAMENTO DA LEITURA ESTRUTURAL ANTIGA (D16)
-- ----------------------------------------------------------------------------
-- Contrato fechado (D16 revisado em docs/F5-08-desenho-tecnico.md):
--   * membership NAO concede fotografia administrativa;
--   * leitura ADMINISTRATIVA = capability efetiva pela view
--     `estrutura_administrativa` (`org.structure.manage` para estrutura/pessoas,
--     `org.catalog.manage` para catalogos, com as secoes filtradas);
--   * leitura PESSOAL = subgrafo VIGENTE do proprio ator pela view
--     `estrutura_pessoal`;
--   * a UI apenas PROJETA `estrutura_autorizacao` (menu/rotas).
--
-- Esta migration conclui o corte iniciado no P1/P2/P2B. NAO toca nas tres views
-- aprovadas, NAO cria capability/role, NAO cria `SECURITY DEFINER`, NAO concede
-- nada em tabela autorizativa e NAO altera escrita/hierarquia/UX (#293).
--
-- O QUE FECHA — as 10 tabelas que `lerEstrutura` lia diretamente antes do P2B e
-- suas policies `*_select_same_tenant`:
--   collaborators, job_roles, seniority_levels, organizational_units,
--   organizational_unit_parent_periods, organizational_positions,
--   position_reporting_lines, occupations, collegiate_configurations,
--   collegiate_configuration_members.
--
-- CONSEQUENCIA MECANICA PROVADA — `collaborator_status_periods`:
-- a policy indireta dessa tabela (filha sem `organization_id`) e
-- `exists (select 1 from public.collaborators c ...)`. Foi comprovado no banco
-- local que uma policy que referencia tabela SEM SELECT para o ator falha com
-- `permission denied for table collaborators`. Manter a policy com o grant
-- produziria uma tabela "legivel" QUEBRADA em runtime; como sua leitura funcional
-- sempre foi server-side (RPC/Edge com `service_role`) e o cliente NAO a consome,
-- ela entra no mesmo corte (deny-by-default integral), em vez de ficar
-- meio-aberta. `temporary_responsibilities` e
-- `cycle_evaluation_responsibilities` NAO sao tocadas nesta fase.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Premissas: mecanismo de view-owner intacto e alvos no estado esperado
-- ----------------------------------------------------------------------------
do $p3_premissa$
declare
  v_tab text[] := array[
    'collaborators','job_roles','seniority_levels','organizational_units',
    'organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','collegiate_configurations',
    'collegiate_configuration_members','collaborator_status_periods'];
  v_pol text[] := array[
    'collaborators_select_same_tenant','job_roles_select_same_tenant',
    'seniority_levels_select_same_tenant','organizational_units_select_same_tenant',
    'organizational_unit_parent_periods_select_same_tenant',
    'organizational_positions_select_same_tenant',
    'position_reporting_lines_select_same_tenant','occupations_select_same_tenant',
    'collegiate_configurations_select_same_tenant',
    'collegiate_configuration_members_select_same_tenant',
    'collaborator_status_periods_select_same_tenant'];
  v_i integer;
  v_n integer;
  v_tem_policy boolean;
  v_tem_grant boolean;
  v_ja_fechadas integer := 0;
begin
  -- Mecanismo do P1/P2: nenhuma tabela com FORCE RLS (a view le como owner).
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relforcerowsecurity;
  if v_n <> 0 then
    raise exception 'F6_A21_P3: FORCE RLS em % tabela(s) — mecanismo de view-owner invalido', v_n;
  end if;

  -- As TRES views aprovadas seguem sendo a superficie legivel do cliente.
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and has_table_privilege('authenticated', c.oid, 'SELECT');
  if v_n <> 3 then
    raise exception 'F6_A21_P3: premissa P1/P2 violada — % view(s) legiveis (esperado 3)', v_n;
  end if;

  -- Cada alvo precisa estar em estado COERENTE: (a) pre-P3 (policy SELECT +
  -- SELECT efetivo) ou (b) ja fechado (sem policy e sem privilegio). Estado misto
  -- indica intervencao manual e aborta; assim a migration e RE-EXECUTAVEL.
  for v_i in 1..array_length(v_tab, 1) loop
    select count(*) into v_n
      from pg_policies p
     where p.schemaname = 'public' and p.tablename = v_tab[v_i]
       and p.policyname = v_pol[v_i] and p.cmd = 'SELECT'
       and 'authenticated'::name = any(p.roles);
    v_tem_policy := v_n = 1;
    v_tem_grant := has_table_privilege('authenticated', format('public.%I', v_tab[v_i]), 'SELECT');
    if v_tem_policy <> v_tem_grant then
      raise exception 'F6_A21_P3: estado inconsistente em public.% (policy=%, grant=%)',
        v_tab[v_i], v_tem_policy, v_tem_grant;
    end if;
    if not v_tem_policy then
      v_ja_fechadas := v_ja_fechadas + 1;
    end if;
  end loop;

  if v_ja_fechadas = array_length(v_tab, 1) then
    raise notice '[PASS] F6-A21 P3 premissa: as 11 tabelas ja estao fechadas — migration re-executavel (nada a fazer)';
  else
    raise notice '[PASS] F6-A21 P3 premissa: 3 views legiveis, sem FORCE RLS e % alvo(s) no estado pre-P3', array_length(v_tab, 1) - v_ja_fechadas;
  end if;
end $p3_premissa$;

-- ----------------------------------------------------------------------------
-- 1) Fechamento: policy SELECT own-tenant + SELECT de authenticated/anon/public
-- ----------------------------------------------------------------------------
do $p3_acoes$
declare
  v_tab text[] := array[
    'collaborators','job_roles','seniority_levels','organizational_units',
    'organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','collegiate_configurations',
    'collegiate_configuration_members','collaborator_status_periods'];
  v_pol text[] := array[
    'collaborators_select_same_tenant','job_roles_select_same_tenant',
    'seniority_levels_select_same_tenant','organizational_units_select_same_tenant',
    'organizational_unit_parent_periods_select_same_tenant',
    'organizational_positions_select_same_tenant',
    'position_reporting_lines_select_same_tenant','occupations_select_same_tenant',
    'collegiate_configurations_select_same_tenant',
    'collegiate_configuration_members_select_same_tenant',
    'collaborator_status_periods_select_same_tenant'];
  v_i integer;
begin
  for v_i in 1..array_length(v_tab, 1) loop
    -- A policy some primeiro (deny-by-default intermediario e seguro).
    execute format('drop policy if exists %I on public.%I', v_pol[v_i], v_tab[v_i]);
    -- Depois o privilegio: a leitura do cliente passa a ser SOMENTE as views.
    execute format('revoke select on public.%I from authenticated, anon, public', v_tab[v_i]);
    raise notice '[PASS] F6-A21 P3: public.% fechada (policy % dropada, SELECT revogado de authenticated/anon)',
      v_tab[v_i], v_pol[v_i];
  end loop;
end $p3_acoes$;

-- ----------------------------------------------------------------------------
-- 2) Guarda pós-corte: deny-by-default integral nos 11 alvos
-- ----------------------------------------------------------------------------
do $p3_guarda$
declare
  v_tab text[] := array[
    'collaborators','job_roles','seniority_levels','organizational_units',
    'organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','collegiate_configurations',
    'collegiate_configuration_members','collaborator_status_periods'];
  v_privs text[] := array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
  v_i integer;
  v_n integer;
begin
  for v_i in 1..array_length(v_tab, 1) loop
    -- Zero policy de QUALQUER cmd (nao basta "sem policy SELECT").
    select count(*) into v_n
      from pg_policies p
     where p.schemaname = 'public' and p.tablename = v_tab[v_i];
    if v_n <> 0 then
      raise exception 'F6_A21_P3: public.% ainda tem % policy(ies)', v_tab[v_i], v_n;
    end if;

    -- RLS continua habilitada (a tabela segue registrada no inventario D16).
    select count(*) into v_n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_tab[v_i]
       and c.relkind = 'r' and c.relrowsecurity;
    if v_n <> 1 then
      raise exception 'F6_A21_P3: public.% sem RLS habilitada', v_tab[v_i];
    end if;

    -- Privilegios EFETIVOS (inclui o pseudo-papel PUBLIC) para cliente.
    select count(*) into v_n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
     where n.nspname = 'public' and c.relname = v_tab[v_i]
       and a.privilege_type = any(v_privs)
       and (a.grantee = 0 or a.grantee = 'anon'::regrole
            or a.grantee = 'authenticated'::regrole);
    if v_n <> 0 then
      raise exception 'F6_A21_P3: public.% ainda concede % privilegio(s) a cliente/PUBLIC', v_tab[v_i], v_n;
    end if;

    -- service_role preservado (RPCs/Edge continuam lendo a estrutura).
    if not has_table_privilege('service_role', format('public.%I', v_tab[v_i]), 'SELECT') then
      raise exception 'F6_A21_P3: service_role perdeu SELECT em public.%', v_tab[v_i];
    end if;
  end loop;

  raise notice '[PASS] F6-A21 P3 guarda: 11 tabelas em DENY-BY-DEFAULT INTEGRAL (zero policy, zero privilegio de cliente/PUBLIC, RLS habilitada) com service_role preservado';
end $p3_guarda$;

-- ----------------------------------------------------------------------------
-- 3) Guarda pós-corte: o resto do contrato permanece INTACTO
-- ----------------------------------------------------------------------------
do $p3_intacto$
declare
  v_n integer;
begin
  -- As tres views continuam sendo a UNICA superficie legivel do cliente.
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and has_table_privilege('authenticated', c.oid, 'SELECT');
  if v_n <> 3 then
    raise exception 'F6_A21_P3: % view(s) legiveis (esperado exatamente as 3 aprovadas)', v_n;
  end if;
  if has_table_privilege('anon', 'public.estrutura_administrativa', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_pessoal', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_autorizacao', 'SELECT') then
    raise exception 'F6_A21_P3: anon com SELECT em view do #327';
  end if;

  -- Nenhum privilegio novo em tabela autorizativa.
  if has_table_privilege('authenticated', 'public.access_roles', 'SELECT')
     or has_table_privilege('authenticated', 'public.access_role_capabilities', 'SELECT')
     or has_table_privilege('authenticated', 'public.membership_access_role_assignments', 'SELECT')
     or has_table_privilege('authenticated', 'public.membership_collaborator_links', 'SELECT')
     or has_table_privilege('authenticated', 'public.access_role_assignment_scopes', 'SELECT') then
    raise exception 'F6_A21_P3: authenticated com SELECT em tabela autorizativa';
  end if;

  -- Nenhum DEFINER novo e nenhum resolver executavel pelo cliente.
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4 then
    raise exception 'F6_A21_P3: DEFINER esperado=4, encontrado=%', v_n;
  end if;
  if has_function_privilege('authenticated', 'public.resolver_capabilities_efetivas(uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.resolver_collaborador_vinculado(uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.resolver_capabilities_efetivas(uuid, uuid)', 'EXECUTE') then
    raise exception 'F6_A21_P3: resolver executavel por cliente';
  end if;

  -- Fora do corte desta fase: as duas tabelas explicitamente preservadas.
  if not has_table_privilege('authenticated', 'public.temporary_responsibilities', 'SELECT')
     or not has_table_privilege('authenticated', 'public.cycle_evaluation_responsibilities', 'SELECT') then
    raise exception 'F6_A21_P3: corte ampliado indevidamente (temporary/cycle_evaluation responsibilities)';
  end if;

  raise notice '[PASS] F6-A21 P3 intacto: 3 views legiveis (anon negado), zero privilegio novo em tabela autorizativa, 4 DEFINER e temporary/cycle_evaluation_responsibilities preservadas';
end $p3_intacto$;
