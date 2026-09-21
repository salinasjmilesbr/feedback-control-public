-- ============================================================================
-- F6-A21 P3 (Issue #327): validação do FECHAMENTO da leitura estrutural antiga
-- ----------------------------------------------------------------------------
-- Executar depois de `49-cenario-f6-a21-p3.sql`, como superuser local, com
-- ON_ERROR_STOP. Prova, NO BANCO:
--   1) membership-only NÃO faz SELECT direto nas 10 tabelas (e na 11ª fechada
--      por consequência mecânica) — nem em nenhum tenant;
--   2) `org.structure.manage` lê SOMENTE as seções estruturais pela view;
--   3) `org.catalog.manage` lê SOMENTE o catálogo pela view;
--   4) Admin preserva o snapshot administrativo completo;
--   5) usuário vinculado preserva `estrutura_pessoal` VIGENTE (histórico fora);
--   6) cross-tenant ZERO nas três views e nas tentativas diretas;
--   +) as duas tabelas fora do corte desta fase seguem legíveis pela RLS.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) O corte, no catálogo do banco
-- ============================================================================
do $$
declare
  v_tab text[] := array[
    'collaborators','job_roles','seniority_levels','organizational_units',
    'organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','collegiate_configurations',
    'collegiate_configuration_members','collaborator_status_periods'];
  v_privs text[] := array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'];
  v_i integer; v_n integer; v_priv text;
begin
  for v_i in 1..array_length(v_tab, 1) loop
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = v_tab[v_i];
    if v_n <> 0 then
      raise exception '[FAIL] A1: public.% ainda tem % policy(ies)', v_tab[v_i], v_n;
    end if;

    select count(*) into v_n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
     where n.nspname = 'public' and c.relname = v_tab[v_i]
       and a.privilege_type = any(v_privs)
       and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
    if v_n <> 0 then
      raise exception '[FAIL] A2: public.% ainda concede privilegio a cliente/PUBLIC (%)', v_tab[v_i], v_n;
    end if;

    select count(*) into v_n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_tab[v_i] and c.relkind = 'r' and c.relrowsecurity;
    if v_n <> 1 then
      raise exception '[FAIL] A3: public.% sem RLS habilitada', v_tab[v_i];
    end if;

    if not has_table_privilege('service_role', format('public.%I', v_tab[v_i]), 'SELECT') then
      raise exception '[FAIL] A4: service_role sem SELECT em public.%', v_tab[v_i];
    end if;
  end loop;

  -- As três views seguem a ÚNICA superfície legível do cliente.
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and has_table_privilege('authenticated', c.oid, 'SELECT');
  if v_n <> 3 then
    raise exception '[FAIL] A5: % view(s) legiveis (esperado as 3 aprovadas)', v_n;
  end if;
  if has_table_privilege('anon', 'public.estrutura_administrativa', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_pessoal', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_autorizacao', 'SELECT') then
    raise exception '[FAIL] A6: anon com SELECT em view do #327';
  end if;

  -- Nenhum privilégio novo em tabela autorizativa e nenhum resolver executável.
  foreach v_priv in array array['access_roles','access_role_capabilities',
                                'membership_access_role_assignments','membership_collaborator_links',
                                'access_role_assignment_scopes','access_role_assignment_unit_targets'] loop
    if has_table_privilege('authenticated', format('public.%I', v_priv), 'SELECT')
       or has_table_privilege('anon', format('public.%I', v_priv), 'SELECT') then
      raise exception '[FAIL] A7: cliente com SELECT em tabela autorizativa public.%', v_priv;
    end if;
  end loop;

  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4 then
    raise exception '[FAIL] A8: DEFINER esperado=4, encontrado=%', v_n;
  end if;
  if has_function_privilege('authenticated', 'public.resolver_capabilities_efetivas(uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.resolver_collaborador_vinculado(uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.resolver_capabilities_efetivas(uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] A9: resolver executavel por cliente';
  end if;

  -- FORA DO CORTE desta fase: as duas tabelas preservadas continuam legíveis.
  foreach v_priv in array array['temporary_responsibilities','cycle_evaluation_responsibilities'] loop
    if not has_table_privilege('authenticated', format('public.%I', v_priv), 'SELECT') then
      raise exception '[FAIL] A10: corte ampliado — authenticated sem SELECT em public.%', v_priv;
    end if;
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = v_priv
       and cmd = 'SELECT' and 'authenticated'::name = any(roles);
    if v_n <> 1 then
      raise exception '[FAIL] A11: public.% sem policy SELECT own-tenant preservada', v_priv;
    end if;
  end loop;

  raise notice '[PASS] A: 11 tabelas em deny-by-default integral (zero policy, zero privilegio de cliente/PUBLIC, RLS habilitada, service_role preservado), 3 views como unica superficie legivel, 4 DEFINER e temporary/cycle_evaluation_responsibilities fora do corte';
end $$;

-- ============================================================================
-- B) MEMBRO_G (membership-only): zero leitura direta e zero projeção
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a23000-0000-4000-8000-000000000004', false);
set local role authenticated;
do $$
declare
  v_tab text[] := array[
    'collaborators','job_roles','seniority_levels','organizational_units',
    'organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','collegiate_configurations',
    'collegiate_configuration_members','collaborator_status_periods'];
  v_i integer; v_n integer; v_ok boolean;
  v_flags text;
begin
  -- PROVA 1: nenhum SELECT direto, tabela por tabela.
  for v_i in 1..array_length(v_tab, 1) loop
    v_ok := false;
    begin
      execute format('select count(*) from public.%I', v_tab[v_i]) into v_n;
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then
      raise exception '[FAIL] B1: membership-only leu public.% (%)', v_tab[v_i], v_n;
    end if;
  end loop;

  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then
    raise exception '[FAIL] B2: membership-only recebeu % linha(s) administrativa(s)', v_n;
  end if;

  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 0 then
    raise exception '[FAIL] B3: membership-only sem vinculo recebeu projecao pessoal (%)', v_n;
  end if;

  select pode_estrutura::text || '/' || pode_catalogo::text || '/' || coalesce(collaborator_id::text, 'sem-vinculo')
    into v_flags from public.estrutura_autorizacao;
  if v_flags is distinct from 'false/false/sem-vinculo' then
    raise exception '[FAIL] B4: projecao de autorizacao = %', v_flags;
  end if;

  raise notice '[PASS] B: membership-only nao le NENHUMA das 11 tabelas fechadas, recebe 0 linhas administrativas, 0 projecao pessoal e flags false/false';
end $$;
rollback;

-- ============================================================================
-- C) ESTRUTURA_G (só `org.structure.manage`): SOMENTE seções estruturais
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a23000-0000-4000-8000-000000000002', false);
set local role authenticated;
do $$
declare
  v_u integer; v_pp integer; v_po integer; v_rl integer; v_oc integer;
  v_co integer; v_mc integer; v_cl integer; v_ca integer; v_se integer;
  v_flags text; v_n integer; v_ok boolean;
begin
  select pode_estrutura::text || '/' || pode_catalogo::text into v_flags
    from public.estrutura_administrativa;
  if v_flags is distinct from 'true/false' then
    raise exception '[FAIL] C1: flags do ator estrutura-only = % (esperado true/false)', v_flags;
  end if;
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 1 then
    raise exception '[FAIL] C2: linhas administrativas = % (esperado 1)', v_n;
  end if;

  select jsonb_array_length(unidades), jsonb_array_length(periodos_parent),
         jsonb_array_length(posicoes), jsonb_array_length(reporting_lines),
         jsonb_array_length(ocupacoes), jsonb_array_length(colegiados),
         jsonb_array_length(membros_colegiado), jsonb_array_length(colaboradores),
         jsonb_array_length(cargos), jsonb_array_length(senioridades)
    into v_u, v_pp, v_po, v_rl, v_oc, v_co, v_mc, v_cl, v_ca, v_se
    from public.estrutura_administrativa;
  if v_po is null then
    raise exception '[FAIL] C3: estrutura-only sem linha administrativa';
  end if;

  -- PROVA 2: as 8 seções estruturais vêm completas e o CATÁLOGO fica VAZIO.
  if v_u <> 2 or v_pp <> 1 or v_po <> 4 or v_rl <> 3 or v_oc <> 4
     or v_co <> 1 or v_mc <> 1 or v_cl <> 4 then
    raise exception '[FAIL] C4: secoes estruturais = %/%/%/%/%/%/%/% (esperado 2/1/4/3/4/1/1/4)',
      v_u, v_pp, v_po, v_rl, v_oc, v_co, v_mc, v_cl;
  end if;
  if v_ca <> 0 or v_se <> 0 then
    raise exception '[FAIL] C5: estrutura-only recebeu catalogo (cargos=%, senioridades=%)', v_ca, v_se;
  end if;

  -- E continua sem NENHUM acesso direto às tabelas.
  begin
    perform count(*) from public.organizational_units;
    raise exception '[FAIL] C6: estrutura-only leu tabela direta';
  exception when insufficient_privilege then null;
  end;

  raise notice '[PASS] C: org.structure.manage => secoes estruturais completas (2 unidades, 4 posicoes, 3 linhas, 4 ocupacoes, 1 colegiado, 4 colaboradores), catalogo VAZIO e nenhum acesso direto a tabela';
end $$;
rollback;

-- ============================================================================
-- D) CATALOGO_G (só `org.catalog.manage`): SOMENTE catálogo
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a23000-0000-4000-8000-000000000003', false);
set local role authenticated;
do $$
declare
  v_u integer; v_pp integer; v_po integer; v_rl integer; v_oc integer;
  v_co integer; v_mc integer; v_cl integer; v_ca integer; v_se integer;
  v_flags text;
begin
  select pode_estrutura::text || '/' || pode_catalogo::text into v_flags
    from public.estrutura_administrativa;
  if v_flags is distinct from 'false/true' then
    raise exception '[FAIL] D1: flags do ator catalogo-only = % (esperado false/true)', v_flags;
  end if;

  select jsonb_array_length(unidades), jsonb_array_length(periodos_parent),
         jsonb_array_length(posicoes), jsonb_array_length(reporting_lines),
         jsonb_array_length(ocupacoes), jsonb_array_length(colegiados),
         jsonb_array_length(membros_colegiado), jsonb_array_length(colaboradores),
         jsonb_array_length(cargos), jsonb_array_length(senioridades)
    into v_u, v_pp, v_po, v_rl, v_oc, v_co, v_mc, v_cl, v_ca, v_se
    from public.estrutura_administrativa;
  if v_u is null then
    raise exception '[FAIL] D2: catalogo-only sem linha administrativa';
  end if;

  -- PROVA 3: só catálogo; NENHUMA seção estrutural.
  if v_ca <> 2 or v_se <> 2 then
    raise exception '[FAIL] D3: catalogo do ator catalogo-only = cargos % / senioridades % (esperado 2/2)', v_ca, v_se;
  end if;
  if v_u <> 0 or v_pp <> 0 or v_po <> 0 or v_rl <> 0 or v_oc <> 0
     or v_co <> 0 or v_mc <> 0 or v_cl <> 0 then
    raise exception '[FAIL] D4: catalogo-only recebeu estrutura (%/%/%/%/%/%/%/%)',
      v_u, v_pp, v_po, v_rl, v_oc, v_co, v_mc, v_cl;
  end if;

  begin
    perform count(*) from public.job_roles;
    raise exception '[FAIL] D5: catalogo-only leu tabela direta';
  exception when insufficient_privilege then null;
  end;

  raise notice '[PASS] D: org.catalog.manage => somente cargos (2) e senioridades (2); ZERO secao estrutural e nenhum acesso direto a tabela';
end $$;
rollback;

-- ============================================================================
-- E) ADMIN: snapshot administrativo PRESERVADO + cross-tenant zero
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a23000-0000-4000-8000-000000000001', false);
set local role authenticated;
do $$
declare
  v_u integer; v_pp integer; v_po integer; v_rl integer; v_oc integer;
  v_co integer; v_mc integer; v_cl integer; v_ca integer; v_se integer;
  v_flags text; v_n integer; v_org uuid;
begin
  select organization_id, pode_estrutura::text || '/' || pode_catalogo::text
    into v_org, v_flags from public.estrutura_administrativa;
  if v_org <> 'f6a23000-0000-4000-8000-0000000000a1' or v_flags <> 'true/true' then
    raise exception '[FAIL] E1: admin de GAMA viu organizacao % com flags %', v_org, v_flags;
  end if;
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 1 then
    raise exception '[FAIL] E2: admin de GAMA viu % organizacao(oes) (esperado 1)', v_n;
  end if;

  select jsonb_array_length(unidades), jsonb_array_length(periodos_parent),
         jsonb_array_length(posicoes), jsonb_array_length(reporting_lines),
         jsonb_array_length(ocupacoes), jsonb_array_length(colegiados),
         jsonb_array_length(membros_colegiado), jsonb_array_length(colaboradores),
         jsonb_array_length(cargos), jsonb_array_length(senioridades)
    into v_u, v_pp, v_po, v_rl, v_oc, v_co, v_mc, v_cl, v_ca, v_se
    from public.estrutura_administrativa;
  if v_u is null then
    raise exception '[FAIL] E3: admin sem linha administrativa';
  end if;

  -- PROVA 4: a fotografia administrativa segue COMPLETA (inclusive histórico).
  if v_u <> 2 or v_pp <> 1 or v_po <> 4 or v_rl <> 3 or v_oc <> 4
     or v_co <> 1 or v_mc <> 1 or v_cl <> 4 or v_ca <> 2 or v_se <> 2 then
    raise exception '[FAIL] E4: snapshot do admin = %/%/%/%/%/%/%/%/%/% (esperado 2/1/4/3/4/1/1/4/2/2)',
      v_u, v_pp, v_po, v_rl, v_oc, v_co, v_mc, v_cl, v_ca, v_se;
  end if;

  -- PROVA 6: cross-tenant ZERO nas três views.
  select count(*) into v_n from public.estrutura_administrativa
   where organization_id = 'f6a23000-0000-4000-8000-0000000000a2';
  if v_n <> 0 then
    raise exception '[FAIL] E5: admin de GAMA leu a fotografia de DELTA (%)', v_n;
  end if;
  select count(*) into v_n from public.estrutura_pessoal
   where organization_id = 'f6a23000-0000-4000-8000-0000000000a2';
  if v_n <> 0 then
    raise exception '[FAIL] E6: projecao pessoal vazou para DELTA (%)', v_n;
  end if;
  select count(*) into v_n from public.estrutura_autorizacao
   where organization_id = 'f6a23000-0000-4000-8000-0000000000a2';
  if v_n <> 0 then
    raise exception '[FAIL] E7: autorizacao vazou para DELTA (%)', v_n;
  end if;

  raise notice '[PASS] E: Admin preserva o snapshot administrativo COMPLETO (24 itens incluindo historico) e cross-tenant e ZERO nas 3 views';
end $$;
rollback;

-- Simetria: o admin de DELTA lê DELTA e nada de GAMA.
begin;
select set_config('request.jwt.claim.sub', 'f6a23000-0000-4000-8000-000000000006', false);
set local role authenticated;
do $$
declare v_org uuid; v_n integer;
begin
  select organization_id into v_org from public.estrutura_administrativa;
  if v_org <> 'f6a23000-0000-4000-8000-0000000000a2' then
    raise exception '[FAIL] E8: admin de DELTA viu organizacao %', coalesce(v_org::text, 'nada');
  end if;
  select count(*) into v_n from public.estrutura_administrativa
   where organization_id = 'f6a23000-0000-4000-8000-0000000000a1';
  if v_n <> 0 then
    raise exception '[FAIL] E9: admin de DELTA leu GAMA (%)', v_n;
  end if;
  raise notice '[PASS] E: simetria do isolamento — admin de DELTA le apenas DELTA';
end $$;
rollback;

-- ============================================================================
-- F) VINCULADO_G: `estrutura_pessoal` VIGENTE preservada
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a23000-0000-4000-8000-000000000005', false);
set local role authenticated;
do $$
declare
  v_u integer; v_pp integer; v_po integer; v_rl integer; v_oc integer;
  v_co integer; v_mc integer; v_cl integer; v_ca integer; v_se integer;
  v_n integer; v_org uuid; v_flags text;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then
    raise exception '[FAIL] F1: usuario vinculado sem capability recebeu leitura administrativa (%)', v_n;
  end if;

  select pode_estrutura::text || '/' || pode_catalogo::text || '/' || coalesce(collaborator_id::text, 'sem-vinculo')
    into v_flags from public.estrutura_autorizacao;
  if v_flags <> 'false/false/f6a2e200-0000-4000-8000-000000000001' then
    raise exception '[FAIL] F2: projecao de autorizacao = % (esperado vinculo do ator)', v_flags;
  end if;

  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 1 then
    raise exception '[FAIL] F3: linhas de projecao pessoal = % (esperado 1)', v_n;
  end if;

  select organization_id,
         jsonb_array_length(unidades), jsonb_array_length(periodos_parent),
         jsonb_array_length(posicoes), jsonb_array_length(reporting_lines),
         jsonb_array_length(ocupacoes), jsonb_array_length(colegiados),
         jsonb_array_length(membros_colegiado), jsonb_array_length(colaboradores),
         jsonb_array_length(cargos), jsonb_array_length(senioridades)
    into v_org, v_u, v_pp, v_po, v_rl, v_oc, v_co, v_mc, v_cl, v_ca, v_se
    from public.estrutura_pessoal;

  -- Anti-passe-vacuoso: sem linha, as comparações seguintes seriam NULL.
  if v_po is null then
    raise exception '[FAIL] F4: estrutura_pessoal sem linha para o ator vinculado';
  end if;
  if v_org <> 'f6a23000-0000-4000-8000-0000000000a1' then
    raise exception '[FAIL] F5: projecao pessoal de outra organizacao (%)', v_org;
  end if;

  -- PROVA 5: subgrafo VIGENTE exato (o histórico encerrado fica FORA).
  if v_u <> 2 or v_pp <> 1 or v_po <> 3 or v_rl <> 2 or v_oc <> 3
     or v_co <> 1 or v_mc <> 1 or v_cl <> 3 or v_ca <> 2 or v_se <> 2 then
    raise exception '[FAIL] F6: subgrafo vigente = %/%/%/%/%/%/%/%/%/% (esperado 2/1/3/2/3/1/1/3/2/2)',
      v_u, v_pp, v_po, v_rl, v_oc, v_co, v_mc, v_cl, v_ca, v_se;
  end if;

  -- Posição e ocupação ENCERRADAS não podem aparecer no alcance atual.
  select count(*) into v_n from public.estrutura_pessoal p, jsonb_array_elements(p.posicoes) e
   where e->>'id' = 'f6a2d100-0000-4000-8000-000000000004';
  if v_n <> 0 then
    raise exception '[FAIL] F7: posicao ENCERRADA exposta no subgrafo atual';
  end if;
  select count(*) into v_n from public.estrutura_pessoal p, jsonb_array_elements(p.colaboradores) e
   where e->>'id' = 'f6a2e200-0000-4000-8000-000000000004';
  if v_n <> 0 then
    raise exception '[FAIL] F8: colaborador alcancado so por historico encerrado foi exposto';
  end if;

  -- E o ator vinculado também não tem acesso direto às tabelas.
  begin
    perform count(*) from public.occupations;
    raise exception '[FAIL] F9: ator vinculado leu tabela direta';
  exception when insufficient_privilege then null;
  end;

  raise notice '[PASS] F: ator vinculado sem capability => 0 leitura administrativa e estrutura_pessoal VIGENTE exata (3 posicoes, 3 colaboradores, 2 linhas, 3 ocupacoes, 1 colegiado), sem historico encerrado';
end $$;
rollback;

-- ============================================================================
-- G) MEMBRO_D (membership-only em DELTA): fail-closed e cross-tenant zero
-- ============================================================================
begin;
select set_config('request.jwt.claim.sub', 'f6a23000-0000-4000-8000-000000000007', false);
set local role authenticated;
do $$
declare v_n integer;
begin
  select count(*) into v_n from public.estrutura_administrativa;
  if v_n <> 0 then
    raise exception '[FAIL] G1: membership-only de DELTA recebeu leitura administrativa (%)', v_n;
  end if;
  select count(*) into v_n from public.estrutura_pessoal;
  if v_n <> 0 then
    raise exception '[FAIL] G2: membership-only de DELTA recebeu projecao pessoal (%)', v_n;
  end if;
  select count(*) into v_n from public.estrutura_autorizacao
   where organization_id = 'f6a23000-0000-4000-8000-0000000000a1';
  if v_n <> 0 then
    raise exception '[FAIL] G3: autorizacao de GAMA visivel para DELTA (%)', v_n;
  end if;
  raise notice '[PASS] G: membership-only de DELTA => zero leitura administrativa/pessoal e nenhuma autorizacao de GAMA';
end $$;
rollback;

-- ============================================================================
-- H) anon: nenhuma das 11 tabelas e nenhuma view
-- ============================================================================
set role anon;
do $$
declare
  v_tab text[] := array[
    'collaborators','job_roles','seniority_levels','organizational_units',
    'organizational_unit_parent_periods','organizational_positions',
    'position_reporting_lines','occupations','collegiate_configurations',
    'collegiate_configuration_members','collaborator_status_periods'];
  v_i integer; v_ok boolean;
begin
  for v_i in 1..array_length(v_tab, 1) loop
    v_ok := false;
    begin
      execute format('select count(*) from public.%I', v_tab[v_i]);
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then
      raise exception '[FAIL] H1: anon leu public.%', v_tab[v_i];
    end if;
  end loop;

  for v_i in 1..3 loop
    v_ok := false;
    begin
      execute format('select count(*) from public.%I',
                     (array['estrutura_administrativa','estrutura_pessoal','estrutura_autorizacao'])[v_i]);
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then
      raise exception '[FAIL] H2: anon leu view do #327 (%)', v_i;
    end if;
  end loop;

  raise notice '[PASS] H: anon sem acesso as 11 tabelas fechadas e as 3 views';
end $$;
reset role;

-- ============================================================================
-- I) Resumo
-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F6-A21 P3: fechamento validado — leitura administrativa por capability, leitura pessoal vigente pelo subgrafo, membership-only sem leitura direta, cross-tenant zero e as duas tabelas fora do corte preservadas.';
end $$;
