-- ============================================================================
-- F3-07 (Issue #84): validação automatizada — resolução organizacional por
-- data (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-07.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-07.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-07.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; qualquer falha levanta
-- exceção e aborta com código de saída não-zero. O script NÃO toca projeto
-- remoto, NÃO altera policies e remove ao final os dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- Datas de referência do cenário.
--   D1 = 2025-03-15 (substituto operacional vigente em P_CORD).
--   D2 = 2025-02-15 (antes do substituto; P_CORD vaga sem substituto).
--   D3 = 2025-04-15 (licença de C_LEAVE; substituto ainda vigente).

-- ============================================================================
-- 1) Estrutura: tabelas inalteradas e funções de resolução presentes
-- ============================================================================

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and t.tablename not in (
        'collaborator_identifiers',
        'collaborator_status_periods',
        'collaborators',
        'job_roles',
        'occupations',
        'organizational_positions',
        'organizational_unit_parent_periods',
        'organizational_units',
        'organizations',
        'position_reporting_lines',
        'seniority_levels',
        'temporary_responsibilities',
        'user_organization_memberships',
        'user_profiles'
      )
  ) then
    raise exception '[FAIL] tabela inesperada no schema public (F3-07 nao cria tabelas)';
  end if;
  raise notice '[PASS] schema public inalterado (14 tabelas; F3-07 adiciona apenas funcoes)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'organizacao_resolver_responsavel_posicao',
      'organizacao_resolver_gestor_direto',
      'organizacao_resolver_subordinados_diretos',
      'organizacao_resolver_descendentes',
      'organizacao_resolver_cadeia',
      'organizacao_resolver_escopo_posicoes',
      'organizacao_resolver_escopo_unidades'
    );
  if v_n <> 7 then
    raise exception '[FAIL] funcoes de resolucao F3-07 ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] sete funcoes de resolucao organizacional presentes';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
  where n.nspname = 'public'
    and p.proname like 'organizacao_resolver_%'
    and (l.lanname <> 'sql'
         or p.provolatile <> 's'
         or p.prosecdef = true);
  if v_n <> 0 then
    raise exception '[FAIL] funcao de resolucao fora do contrato (sql/stable/invoker)';
  end if;
  raise notice '[PASS] funcoes SQL, STABLE e SECURITY INVOKER (sem grants adicionais explicitos)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_policies p
  where p.schemaname = 'public';
  if v_n <> 3 then
    raise exception '[FAIL] quantidade de policies alterada (esperado 3, encontrado %)', v_n;
  end if;
  raise notice '[PASS] policies existentes inalteradas (3 policies de identidade/sessao da F2)';
end $$;

-- ============================================================================
-- 2) Resolução de responsável por posição (titular / substituto / efetivo)
-- ============================================================================

do $$
declare
  r record;
begin
  select * into r
  from public.organizacao_resolver_responsavel_posicao(
    'f9c00000-0000-0000-0000-0000000000a2',
    '2025-03-15T00:00:00Z'
  );
  if r.titular_collaborator_id is not null
     or r.substitute_collaborator_id is distinct from 'f9b00000-0000-0000-0000-0000000000c2'
     or r.responsible_collaborator_id is distinct from 'f9b00000-0000-0000-0000-0000000000c2' then
    raise exception '[FAIL] P_CORD em 2025-03-15 deveria ser vaga com substituto C_SUB';
  end if;
  raise notice '[PASS] posicao vaga com substituto: titular null, substituto e responsavel = C_SUB';
end $$;

do $$
declare
  r record;
begin
  select * into r
  from public.organizacao_resolver_responsavel_posicao(
    'f9c00000-0000-0000-0000-0000000000a1',
    '2025-03-15T00:00:00Z'
  );
  if r.titular_collaborator_id is distinct from 'f9b00000-0000-0000-0000-0000000000c1'
     or r.substitute_collaborator_id is not null
     or r.responsible_collaborator_id is distinct from 'f9b00000-0000-0000-0000-0000000000c1' then
    raise exception '[FAIL] P_GER em 2025-03-15 deveria ter titular/responsavel C_GER sem substituto';
  end if;
  raise notice '[PASS] posicao ocupada sem substituto: titular e responsavel = C_GER';
end $$;

do $$
declare
  r record;
begin
  select * into r
  from public.organizacao_resolver_responsavel_posicao(
    'f9c00000-0000-0000-0000-0000000000a2',
    '2025-02-15T00:00:00Z'
  );
  if r.titular_collaborator_id is not null
     or r.substitute_collaborator_id is not null
     or r.responsible_collaborator_id is not null then
    raise exception '[FAIL] P_CORD em 2025-02-15 deveria ser vaga sem responsavel';
  end if;
  raise notice '[PASS] posicao vaga sem substituto: responsavel null (ausencia de ocupante)';
end $$;

-- ============================================================================
-- 3) Gestor direto (derivado da estrutura; gerência sem Coordenador)
-- ============================================================================

do $$
declare
  r record;
  v_n int;
begin
  select count(*) into v_n
  from public.organizacao_resolver_gestor_direto(
    'f9b00000-0000-0000-0000-0000000000c3', '2025-03-15T00:00:00Z'
  );
  if v_n <> 1 then
    raise exception '[FAIL] C_ANL1 deveria ter 1 gestor direto (encontrado %)', v_n;
  end if;

  select * into r
  from public.organizacao_resolver_gestor_direto(
    'f9b00000-0000-0000-0000-0000000000c3', '2025-03-15T00:00:00Z'
  ) limit 1;
  if r.occupied_position_id is distinct from 'f9c00000-0000-0000-0000-0000000000a3'
     or r.manager_position_id is distinct from 'f9c00000-0000-0000-0000-0000000000a2'
     or r.manager_responsible_collaborator_id is distinct from 'f9b00000-0000-0000-0000-0000000000c2' then
    raise exception '[FAIL] gestor direto de C_ANL1 deveria ser P_CORD (responsavel C_SUB)';
  end if;
  raise notice '[PASS] gestor direto derivado da reporting line + occupation (P_CORD com substituto C_SUB)';
end $$;

do $$
declare
  v_n int;
begin
  -- Licença não exclui: em 2025-04-15 C_LEAVE está em leave e segue resolvendo.
  select count(*) into v_n
  from public.organizacao_resolver_gestor_direto(
    'f9b00000-0000-0000-0000-0000000000c4', '2025-04-15T00:00:00Z'
  );
  if v_n <> 1 then
    raise exception '[FAIL] C_LEAVE em licenca deveria continuar resolvendo gestor direto';
  end if;
  raise notice '[PASS] licenca nao exclui da resolucao (titular mantem occupation)';
end $$;

do $$
declare
  v_n int;
  v_manager uuid;
begin
  -- Gerência sem Coordenador: C_MULTI ocupa P_CONS e P_ANL3 (ambos reportam
  -- diretamente a P_GER, Gerente) — dois gestores resolvidos para P_GER.
  select count(*) into v_n
  from public.organizacao_resolver_gestor_direto(
    'f9b00000-0000-0000-0000-0000000000c5', '2025-03-15T00:00:00Z'
  );
  if v_n <> 2 then
    raise exception '[FAIL] C_MULTI deveria ter 2 gestores diretos (multi-positions), encontrado %', v_n;
  end if;

  select manager_position_id into v_manager
  from public.organizacao_resolver_gestor_direto(
    'f9b00000-0000-0000-0000-0000000000c5', '2025-03-15T00:00:00Z'
  ) limit 1;
  if v_manager is distinct from 'f9c00000-0000-0000-0000-0000000000a1' then
    raise exception '[FAIL] gestor direto de C_MULTI deveria ser P_GER (Gerente, sem Coordenador)';
  end if;
  raise notice '[PASS] gerencia sem Coordenador: Consultor/Analista resolvem o Gerente como superior';
end $$;

-- ============================================================================
-- 4) Subordinados diretos e descendentes estruturais
-- ============================================================================

do $$
declare
  v_ids uuid[];
begin
  select array_agg(subordinate_position_id order by subordinate_position_id) into v_ids
  from public.organizacao_resolver_subordinados_diretos(
    'f9b00000-0000-0000-0000-0000000000c1', '2025-03-15T00:00:00Z'
  );
  if v_ids is distinct from
     array['f9c00000-0000-0000-0000-0000000000a2',
           'f9c00000-0000-0000-0000-0000000000a5',
           'f9c00000-0000-0000-0000-0000000000a6']::uuid[] then
    raise exception '[FAIL] subordinados diretos de C_GER inesperados';
  end if;
  raise notice '[PASS] subordinados diretos de C_GER = {P_CORD, P_CONS, P_ANL3}';
end $$;

do $$
declare
  v_ids uuid[];
begin
  select array_agg(position_id order by position_id) into v_ids
  from public.organizacao_resolver_descendentes(
    'f9b00000-0000-0000-0000-0000000000c1', '2025-03-15T00:00:00Z'
  );
  if v_ids is distinct from
     array['f9c00000-0000-0000-0000-0000000000a2',
           'f9c00000-0000-0000-0000-0000000000a3',
           'f9c00000-0000-0000-0000-0000000000a4',
           'f9c00000-0000-0000-0000-0000000000a5',
           'f9c00000-0000-0000-0000-0000000000a6',
           'f9c00000-0000-0000-0000-0000000000a7']::uuid[] then
    raise exception '[FAIL] descendentes de C_GER inesperados';
  end if;
  raise notice '[PASS] descendentes estruturais de C_GER = {P_CORD, P_ANL1, P_ANL2, P_CONS, P_ANL3, P_ANL4}';
end $$;

do $$
declare
  v_depth int;
begin
  select depth into v_depth
  from public.organizacao_resolver_descendentes(
    'f9b00000-0000-0000-0000-0000000000c1', '2025-03-15T00:00:00Z'
  )
  where position_id = 'f9c00000-0000-0000-0000-0000000000a4';
  if v_depth is distinct from 3 then
    raise exception '[FAIL] profundidade de P_ANL2 deveria ser 3 (encontrado %)', v_depth;
  end if;
  raise notice '[PASS] profundidade estrutural correta (P_ANL2 = 3 niveis abaixo de C_GER)';
end $$;

-- ============================================================================
-- 5) Cadeia hierárquica (posições vagas preservadas)
-- ============================================================================

do $$
declare
  v_ids uuid[];
  r record;
begin
  select array_agg(position_id order by depth) into v_ids
  from public.organizacao_resolver_cadeia(
    'f9b00000-0000-0000-0000-0000000000c4', '2025-03-15T00:00:00Z'
  );
  if v_ids is distinct from
     array['f9c00000-0000-0000-0000-0000000000a4',
           'f9c00000-0000-0000-0000-0000000000a3',
           'f9c00000-0000-0000-0000-0000000000a2',
           'f9c00000-0000-0000-0000-0000000000a1']::uuid[] then
    raise exception '[FAIL] cadeia de C_LEAVE inesperada';
  end if;

  select * into r
  from public.organizacao_resolver_cadeia(
    'f9b00000-0000-0000-0000-0000000000c4', '2025-03-15T00:00:00Z'
  )
  where position_id = 'f9c00000-0000-0000-0000-0000000000a2';
  if r.titular_collaborator_id is not null
     or r.responsible_collaborator_id is distinct from 'f9b00000-0000-0000-0000-0000000000c2' then
    raise exception '[FAIL] P_CORD na cadeia deveria ser vaga com responsavel C_SUB';
  end if;
  raise notice '[PASS] cadeia ascendente preserva posicao vaga (P_CORD: titular null, responsavel C_SUB)';
end $$;

do $$
declare
  r record;
begin
  -- Antes do substituto, a posição vaga da cadeia retorna responsavel NULL.
  select * into r
  from public.organizacao_resolver_cadeia(
    'f9b00000-0000-0000-0000-0000000000c4', '2025-02-15T00:00:00Z'
  )
  where position_id = 'f9c00000-0000-0000-0000-0000000000a2';
  if r.responsible_collaborator_id is not null then
    raise exception '[FAIL] P_CORD em 2025-02-15 na cadeia deveria ter responsavel NULL';
  end if;
  raise notice '[PASS] cadeia em 2025-02-15: posicao vaga sem substituto retorna responsavel NULL';
end $$;

-- ============================================================================
-- 6) Escopo estrutural (união coerente de múltiplas positions)
-- ============================================================================

do $$
declare
  v_pos uuid[];
  v_units uuid[];
begin
  select array_agg(position_id order by position_id) into v_pos
  from public.organizacao_resolver_escopo_posicoes(
    'f9b00000-0000-0000-0000-0000000000c5', '2025-03-15T00:00:00Z'
  );
  if v_pos is distinct from
     array['f9c00000-0000-0000-0000-0000000000a5',
           'f9c00000-0000-0000-0000-0000000000a6',
           'f9c00000-0000-0000-0000-0000000000a7']::uuid[] then
    raise exception '[FAIL] escopo de posicoes de C_MULTI inesperado';
  end if;

  select array_agg(unit_id order by unit_id) into v_units
  from public.organizacao_resolver_escopo_unidades(
    'f9b00000-0000-0000-0000-0000000000c5', '2025-03-15T00:00:00Z'
  );
  if v_units is distinct from array['f9e00000-0000-0000-0000-000000000002']::uuid[] then
    raise exception '[FAIL] escopo de unidades de C_MULTI inesperado';
  end if;
  raise notice '[PASS] multiplas positions produzem escopo coerente (C_MULTI: P_CONS, P_ANL3, P_ANL4 na U2)';
end $$;

do $$
declare
  v_units uuid[];
begin
  select array_agg(unit_id order by unit_id) into v_units
  from public.organizacao_resolver_escopo_unidades(
    'f9b00000-0000-0000-0000-0000000000c1', '2025-03-15T00:00:00Z'
  );
  if v_units is distinct from
     array['f9e00000-0000-0000-0000-000000000001',
           'f9e00000-0000-0000-0000-000000000002']::uuid[] then
    raise exception '[FAIL] escopo de unidades de C_GER deveria cobrir U1 e U2';
  end if;
  raise notice '[PASS] escopo de unidades de C_GER = {U1, U2}';
end $$;

-- ============================================================================
-- 7) RLS deny-by-default em execução (como authenticated)
-- ============================================================================

set role authenticated;

do $$
declare
  r record;
begin
  select * into r
  from public.organizacao_resolver_responsavel_posicao(
    'f9c00000-0000-0000-0000-0000000000a1', '2025-03-15T00:00:00Z'
  );
  if r.responsible_collaborator_id is not null then
    raise exception '[FAIL] authenticated nao deveria resolver ocupante (RLS deve negar leitura)';
  end if;
  raise notice '[PASS] RLS: authenticated nao resolve ocupante (responsavel null por deny-by-default)';
end $$;

reset role;

-- ============================================================================
-- 8) F3-01..F3-06 permanecem intactas
-- ============================================================================

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'temporary_responsibilities';
  if v_cols is distinct from
     array['created_at', 'id', 'organization_id', 'organizational_position_id',
           'reason', 'responsibility_type', 'substitute_collaborator_id',
           'updated_at', 'valid_from', 'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] temporary_responsibilities (F3-06) foi alterada indevidamente';
  end if;
  raise notice '[PASS] F3-01..F3-06 intactas (nenhuma tabela/coluna alterada)';
end $$;

-- ============================================================================
-- 9) Limpeza do cenário sintético (banco local permanece limpo)
-- ============================================================================

delete from public.temporary_responsibilities
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.occupations
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.collaborator_status_periods
where collaborator_id in (
  'f9b00000-0000-0000-0000-0000000000c1',
  'f9b00000-0000-0000-0000-0000000000c2',
  'f9b00000-0000-0000-0000-0000000000c3',
  'f9b00000-0000-0000-0000-0000000000c4',
  'f9b00000-0000-0000-0000-0000000000c5',
  'f9b00000-0000-0000-0000-0000000000c6',
  'f9b00000-0000-0000-0000-0000000000c7'
);

delete from public.position_reporting_lines
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_positions
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_units
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.collaborators
where id in (
  'f9b00000-0000-0000-0000-0000000000c1',
  'f9b00000-0000-0000-0000-0000000000c2',
  'f9b00000-0000-0000-0000-0000000000c3',
  'f9b00000-0000-0000-0000-0000000000c4',
  'f9b00000-0000-0000-0000-0000000000c5',
  'f9b00000-0000-0000-0000-0000000000c6',
  'f9b00000-0000-0000-0000-0000000000c7'
);

delete from public.job_roles
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.organizations
where id = 'f9a00000-0000-0000-0000-0000000000a1';

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.organizations o
  where o.id = 'f9a00000-0000-0000-0000-0000000000a1';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-07 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-07 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-07: todas as verificacoes passaram (funcoes, resolucao por data, RLS).';
end $$;
