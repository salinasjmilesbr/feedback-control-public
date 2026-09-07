-- ============================================================================
-- F3-04 (Issue #81): validação automatizada — reporting lines temporais entre
-- posições (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-04.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-04.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-04.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; qualquer falha levanta
-- exceção e aborta com código de saída não-zero. O script NÃO toca projeto
-- remoto, NÃO altera policies e remove ao final os dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Estrutura: tabelas esperadas e ausência de entidades antecipadas
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
        'organizational_positions',
        'organizational_unit_parent_periods',
        'organizational_units',
        'organizations',
        'position_reporting_lines',
        'seniority_levels',
        'user_organization_memberships',
        'user_profiles'
      )
  ) then
    raise exception '[FAIL] tabela inesperada no schema public (entidade fora do escopo F3-04)';
  end if;
  raise notice '[PASS] schema public contém somente as tabelas esperadas (F2 + F3-01/02/03 + F3-04)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and t.tablename in (
        'occupancies', 'position_occupancies', 'occupations', 'dotted_lines',
        'committees', 'collegiates', 'snapshots', 'substitutions',
        'position_managers', 'direct_reports'
      )
  ) then
    raise exception '[FAIL] tabela de occupation/dotted line/colegiado/substituicao antecipada';
  end if;
  raise notice '[PASS] nenhuma tabela de occupation/dotted line/colegiado/substituicao antecipada';
end $$;

-- ----------------------------------------------------------------------------
-- 1.1 Colunas exatas de position_reporting_lines
-- ----------------------------------------------------------------------------

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'position_reporting_lines';

  if v_cols is distinct from
     array['created_at', 'id', 'manager_position_id', 'organization_id',
           'reason', 'subordinate_position_id', 'updated_at', 'valid_from',
           'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] position_reporting_lines possui colunas fora do escopo';
  end if;
  raise notice '[PASS] position_reporting_lines: colunas exatas (sem collaborator_id/occupation/autor)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'position_reporting_lines'
    and lower(c.column_name) in ('collaborator_id', 'occupant_id', 'changed_by',
                                 'author', 'dotted_line', 'collegiate');
  if v_n <> 0 then
    raise exception '[FAIL] coluna de occupation/autor/dotted line antecipada em position_reporting_lines';
  end if;
  raise notice '[PASS] sem coluna de occupation/autor/dotted line em position_reporting_lines';
end $$;

do $$
declare
  v_n int;
begin
  -- manager_position_id e reason são NOT NULL (raiz = ausência de linha).
  select count(*) into v_n
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'position_reporting_lines'
    and c.column_name in ('manager_position_id', 'reason', 'valid_from')
    and c.is_nullable = 'YES';
  if v_n <> 0 then
    raise exception '[FAIL] manager_position_id/reason/valid_from deveriam ser NOT NULL';
  end if;
  raise notice '[PASS] manager_position_id/reason/valid_from NOT NULL (raiz = ausência de linha)';
end $$;

-- ----------------------------------------------------------------------------
-- 1.2 Identidade técnica e constraints
-- ----------------------------------------------------------------------------

do $$
declare
  v_expr text;
begin
  select pg_get_expr(d.adbin, d.adrelid)
    into v_expr
  from pg_attrdef d
  where d.adrelid = 'public.position_reporting_lines'::regclass
    and d.adnum = (
      select a.attnum
      from pg_attribute a
      where a.attrelid = d.adrelid and a.attname = 'id'
    );

  if v_expr is null or v_expr not like '%gen_random_uuid()%' then
    raise exception '[FAIL] id de position_reporting_lines sem default gen_random_uuid()';
  end if;
  raise notice '[PASS] id de position_reporting_lines com default gen_random_uuid() (UUID tecnico)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'pk_position_reporting_lines',
    'fk_position_reporting_lines_organizations',
    'fk_position_reporting_lines_subordinate',
    'fk_position_reporting_lines_manager',
    'ck_position_reporting_lines_reason',
    'ck_position_reporting_lines_valid_to',
    'ck_position_reporting_lines_not_self',
    'ex_position_reporting_lines_no_overlap'
  );
  if v_n <> 8 then
    raise exception '[FAIL] constraints esperadas de position_reporting_lines ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] constraints pk/fk/check/exclusion esperadas presentes em position_reporting_lines';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname = 'uq_organizational_positions_id_organization';
  if v_n <> 1 then
    raise exception '[FAIL] unique de referencia em organizational_positions ausente';
  end if;
  raise notice '[PASS] unique de referencia (id, organization_id) adicionada em organizational_positions';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid = 'public.position_reporting_lines'::regclass
    and c.confdeltype <> 'r';
  if v_n <> 0 then
    raise exception '[FAIL] existe FK sem ON DELETE RESTRICT em position_reporting_lines';
  end if;
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid = 'public.position_reporting_lines'::regclass
    and c.confrelid not in (
      'public.organizations'::regclass,
      'public.organizational_positions'::regclass
    );
  if v_n <> 0 then
    raise exception '[FAIL] FK de position_reporting_lines aponta para tabela fora do escopo';
  end if;
  if exists (
    select 1
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid = 'public.position_reporting_lines'::regclass
  ) then
    raise exception '[FAIL] alguma tabela ja referencia position_reporting_lines (occupation/reporting futuro antecipado)';
  end if;
  raise notice '[PASS] FKs RESTRICT restritas a organizations/organizational_positions; nada referencia reporting lines';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgrelid = 'public.position_reporting_lines'::regclass
    and t.tgname in ('trg_position_reporting_lines_updated_at',
                     'trg_position_reporting_lines_within_positions',
                     'trg_position_reporting_lines_no_cycle');
  if v_n <> 3 then
    raise exception '[FAIL] triggers de position_reporting_lines ausentes (% encontrados)', v_n;
  end if;
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgrelid = 'public.organizational_positions'::regclass
    and t.tgname = 'trg_organizational_positions_close_reporting_lines';
  if v_n <> 1 then
    raise exception '[FAIL] trigger de fechamento de posicao ausente';
  end if;
  raise notice '[PASS] triggers de updated_at/validade/ciclos/fechamento presentes';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('enforce_position_reporting_lines_within_positions',
                      'enforce_position_reporting_lines_no_cycle',
                      'enforce_positions_close_without_open_reporting_lines');
  if v_n <> 3 then
    raise exception '[FAIL] funcoes de integridade F3-04 ausentes';
  end if;
  raise notice '[PASS] funcoes de integridade (validade/ciclos/fechamento) presentes';
end $$;

-- ----------------------------------------------------------------------------
-- 1.3 RLS habilitado e deny-by-default (estrutura)
-- ----------------------------------------------------------------------------

do $$
begin
  perform 1
  from pg_class c
  where c.oid = 'public.position_reporting_lines'::regclass
    and c.relrowsecurity = true;
  if not found then
    raise exception '[FAIL] RLS nao habilitado em position_reporting_lines';
  end if;
  raise notice '[PASS] RLS habilitado em position_reporting_lines';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'position_reporting_lines'
  ) then
    raise exception '[FAIL] existe policy em position_reporting_lines (deny-by-default violado)';
  end if;
  raise notice '[PASS] zero policies em position_reporting_lines (deny-by-default estrutural)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('organizations', 'user_profiles', 'user_organization_memberships',
                        'collaborators', 'collaborator_identifiers', 'collaborator_status_periods',
                        'job_roles', 'seniority_levels', 'organizational_units',
                        'organizational_unit_parent_periods', 'organizational_positions')
      and c.relrowsecurity = false
  ) then
    raise exception '[FAIL] RLS de tabelas pre-existentes foi enfraquecido';
  end if;
  raise notice '[PASS] RLS das tabelas pre-existentes (F2/F3-01/02/03) permanece habilitado';
end $$;

-- ============================================================================
-- 2) Cenário: cadeia formal e temporalidade
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.position_reporting_lines
  where organization_id = 'f6a00000-0000-0000-0000-0000000000a1';
  if v_n <> 10 then
    raise exception '[FAIL] reporting lines da org Alfa esperado=10, encontrado=%', v_n;
  end if;
  select count(*) into v_n
  from public.position_reporting_lines
  where organization_id = 'f6a00000-0000-0000-0000-0000000000b1';
  if v_n <> 1 then
    raise exception '[FAIL] reporting lines da org Beta esperado=1, encontrado=%', v_n;
  end if;
  raise notice '[PASS] reporting lines pertencem a organizacao correta (Alfa=10, Beta=1)';
end $$;

do $$
declare
  v_n int;
begin
  -- Raiz por ausência de linha: P_DIR1 e B_GER não possuem linha como
  -- subordinate (nenhum manager artificial null).
  select count(*) into v_n
  from public.position_reporting_lines
  where subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a1';
  if v_n <> 0 then
    raise exception '[FAIL] P_DIR1 (raiz) nao deveria ter linha como subordinate';
  end if;
  select count(*) into v_n
  from public.position_reporting_lines
  where subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] B_GER (raiz) nao deveria ter linha como subordinate';
  end if;
  if exists (
    select 1 from public.position_reporting_lines where manager_position_id is null
  ) then
    raise exception '[FAIL] nao deveria existir linha com manager_position_id null';
  end if;
  raise notice '[PASS] posicao sem superior formal valida por AUSENCIA de linha (manager nunca null)';
end $$;

do $$
declare
  v_n int;
begin
  -- No máximo um superior vigente por subordinado (exclusion): nenhum
  -- subordinado com mais de uma linha aberta.
  select count(*) into v_n
  from (
    select subordinate_position_id
    from public.position_reporting_lines
    where valid_to is null
    group by subordinate_position_id
    having count(*) > 1
  ) s;
  if v_n <> 0 then
    raise exception '[FAIL] subordinado com mais de um superior vigente';
  end if;
  raise notice '[PASS] no maximo um superior formal vigente por posicao (sem superiores simultaneos)';
end $$;

do $$
declare
  v_n int;
  v_man uuid;
begin
  -- Troca de superior: P_ANL3 fecha a linha anterior (P_DIR1) e abre outra
  -- (P_GERSR), preservando o histórico.
  select count(*) into v_n
  from public.position_reporting_lines
  where subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a8';
  if v_n <> 2 then
    raise exception '[FAIL] P_ANL3 deveria ter 2 linhas (historica + vigente)';
  end if;
  select count(*) into v_n
  from public.position_reporting_lines
  where subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a8'
    and valid_to is not null
    and manager_position_id = 'f6c00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] linha anterior de P_ANL3 (superior P_DIR1) deveria permanecer preservada';
  end if;
  select manager_position_id into v_man
  from public.position_reporting_lines
  where subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a8'
    and valid_to is null;
  if v_man is distinct from 'f6c00000-0000-0000-0000-0000000000a3' then
    raise exception '[FAIL] superior vigente de P_ANL3 deveria ser P_GERSR';
  end if;
  raise notice '[PASS] troca de superior fecha periodo anterior e cria novo (historico preservado)';
end $$;

do $$
declare
  v_chain uuid[];
  v_date timestamptz;
begin
  -- Reconstrução histórica por data: em 2025-03-01 P_ANL3 reporta a P_DIR1;
  -- em 2025-08-01 reporta a P_GERSR → P_DIR2 → P_DIR1.
  v_date := '2025-03-01T00:00:00Z';
  with recursive chain(mgr, lvl) as (
    select manager_position_id, 1
    from public.position_reporting_lines
    where subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a8'
      and valid_from <= v_date
      and (valid_to is null or valid_to > v_date)
    union all
    select rl.manager_position_id, c.lvl + 1
    from public.position_reporting_lines rl
    join chain c on rl.subordinate_position_id = c.mgr
    where rl.valid_from <= v_date
      and (rl.valid_to is null or rl.valid_to > v_date)
  )
  select array_agg(mgr order by lvl) into v_chain from chain;

  if v_chain is distinct from array['f6c00000-0000-0000-0000-0000000000a1']::uuid[] then
    raise exception '[FAIL] cadeia em 2025-03-01 de P_ANL3 deveria ser [P_DIR1]';
  end if;

  v_date := '2025-08-01T00:00:00Z';
  with recursive chain(mgr, lvl) as (
    select manager_position_id, 1
    from public.position_reporting_lines
    where subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a8'
      and valid_from <= v_date
      and (valid_to is null or valid_to > v_date)
    union all
    select rl.manager_position_id, c.lvl + 1
    from public.position_reporting_lines rl
    join chain c on rl.subordinate_position_id = c.mgr
    where rl.valid_from <= v_date
      and (rl.valid_to is null or rl.valid_to > v_date)
  )
  select array_agg(mgr order by lvl) into v_chain from chain;

  if v_chain is distinct from
     array['f6c00000-0000-0000-0000-0000000000a3',
           'f6c00000-0000-0000-0000-0000000000a2',
           'f6c00000-0000-0000-0000-0000000000a1']::uuid[] then
    raise exception '[FAIL] cadeia em 2025-08-01 de P_ANL3 deveria ser [P_GERSR, P_DIR2, P_DIR1]';
  end if;
  raise notice '[PASS] cadeia hierarquica reconstruida corretamente para datas historicas diferentes';
end $$;

do $$
declare
  v_n int;
  v_role text;
begin
  -- Analista → Gerente direto (sem Coordenador): P_ANL1 reporta a P_GER2.
  select jr.name into v_role
  from public.position_reporting_lines rl
  join public.organizational_positions p on p.id = rl.manager_position_id
  join public.job_roles jr on jr.id = p.job_role_id and jr.organization_id = p.organization_id
  where rl.subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a6'
    and rl.valid_to is null;
  if v_role is distinct from 'Gerente' then
    raise exception '[FAIL] superior de P_ANL1 deveria ser um Gerente (Analista → Gerente direto)';
  end if;

  -- A organização sintética Alfa não possui função Coordenador: a gerência sem
  -- coordenação intermediária funciona naturalmente.
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'f6a00000-0000-0000-0000-0000000000a1'
    and name = 'Coordenador';
  if v_n <> 0 then
    raise exception '[FAIL] Alfa nao deveria ter Coordenador (estrutura sem coordenacao)';
  end if;
  raise notice '[PASS] Analista reporta diretamente a Gerente (sem Coordenador intermediario)';
end $$;

do $$
declare
  v_role text;
begin
  -- Gerente → Gerente e Gerente → Gerente Sênior e Diretor → Diretor.
  select jr.name into v_role
  from public.position_reporting_lines rl
  join public.organizational_positions p on p.id = rl.manager_position_id
  join public.job_roles jr on jr.id = p.job_role_id and jr.organization_id = p.organization_id
  where rl.subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a5'
    and rl.valid_to is null;
  if v_role is distinct from 'Gerente' then
    raise exception '[FAIL] Gerente → Gerente deveria ser valido';
  end if;

  select jr.name into v_role
  from public.position_reporting_lines rl
  join public.organizational_positions p on p.id = rl.manager_position_id
  join public.job_roles jr on jr.id = p.job_role_id and jr.organization_id = p.organization_id
  where rl.subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a4'
    and rl.valid_to is null;
  if v_role is distinct from 'Gerente Senior' then
    raise exception '[FAIL] Gerente → Gerente Senior deveria ser valido';
  end if;

  select jr.name into v_role
  from public.position_reporting_lines rl
  join public.organizational_positions p on p.id = rl.manager_position_id
  join public.job_roles jr on jr.id = p.job_role_id and jr.organization_id = p.organization_id
  where rl.subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000a2'
    and rl.valid_to is null;
  if v_role is distinct from 'Diretor' then
    raise exception '[FAIL] Diretor → Diretor deveria ser valido';
  end if;
  raise notice '[PASS] Gerente→Gerente, Gerente→Gerente Senior e Diretor→Diretor sao validos (sem hierarquia por cargo)';
end $$;

do $$
declare
  v_n int;
begin
  -- Mesmo job_role (Analista) em alturas hierarquicas diferentes (reporta a
  -- Gerente vs reporta a Gerente Senior), sem qualquer regra por senioridade.
  select count(*) into v_n
  from public.position_reporting_lines rl
  join public.organizational_positions p on p.id = rl.subordinate_position_id
  where p.job_role_id = 'f6d00000-0000-0000-0000-000000000004'
    and rl.valid_to is null;
  if v_n < 3 then
    raise exception '[FAIL] deveria haver pelo menos 3 posicoes Analista com superior vigente';
  end if;

  if exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.position_reporting_lines'::regclass
      and (
        'seniority_level_id' in (
          select a.attname
          from pg_attribute a
          where a.attrelid = c.conrelid
            and a.attnum = any (c.conkey)
        )
      )
  ) then
    raise exception '[FAIL] seniority nao deveria participar da reporting line';
  end if;
  raise notice '[PASS] mesmo job_role em alturas diferentes; seniority nao interfere na hierarquia';
end $$;

do $$
declare
  v_n int;
begin
  -- Especialista sem subordinados (ninguém reporta a P_ESP).
  select count(*) into v_n
  from public.position_reporting_lines
  where manager_position_id = 'f6c00000-0000-0000-0000-0000000000a9';
  if v_n <> 0 then
    raise exception '[FAIL] Especialista nao deveria ter subordinados neste cenario';
  end if;
  raise notice '[PASS] Especialista sem subordinados e valido (com superior formal)';
end $$;

do $$
declare
  v_n int;
begin
  -- reason obrigatório e não vazio em todas as linhas.
  select count(*) into v_n
  from public.position_reporting_lines
  where btrim(reason) = '';
  if v_n <> 0 then
    raise exception '[FAIL] existe reporting line com reason vazio';
  end if;
  raise notice '[PASS] reason obrigatorio e nao vazio em todas as reporting lines';
end $$;

-- ============================================================================
-- 3) Rejeições (integridade no banco)
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Dois superiores simultâneos: P_ANL1 já tem P_GER2 vigente; adicionar
    -- P_ESP como segundo superior no mesmo período deve ser rejeitado.
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000a6',
      'f6c00000-0000-0000-0000-0000000000a9',
      'Tentativa de segundo superior',
      '2026-01-01T00:00:00Z', null
    );
  exception when exclusion_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] dois superiores simultaneos NAO foram rejeitados';
  end if;
  raise notice '[PASS] dois superiores simultaneos para a mesma posicao rejeitados (exclusion constraint)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000a1',
      'Self-reporting invalido',
      '2030-01-01T00:00:00Z', null
    );
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] self-reporting NAO foi rejeitado';
  end if;
  raise notice '[PASS] self-reporting rejeitado (check constraint not_self)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Ciclo multi-nível: P_DIR1 reportando a P_ANL3 (P_DIR1 é ancestral de
    -- P_ANL3 no período vigente) deve ser rejeitado pelo trigger recursivo.
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000a8',
      'Ciclo hierarquico invalido',
      '2025-07-01T00:00:00Z', null
    );
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ciclo multi-nivel NAO foi rejeitado';
  end if;
  raise notice '[PASS] ciclo multi-nivel rejeitado pelo trigger recursivo (temporal)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Cross-organization (subordinate de outra org): subordinado Beta com
    -- superior Alfa, org Alfa.
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000b1',
      'f6c00000-0000-0000-0000-0000000000a1',
      'Cross-org subordinate',
      '2025-06-01T00:00:00Z', '2025-06-30T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] subordinate cross-organization NAO foi rejeitado';
  end if;
  raise notice '[PASS] tenant integrity: subordinate de outra organizacao rejeitado (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Cross-organization (manager de outra org): subordinado Alfa com superior
    -- Beta, org Alfa.
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000b1',
      'Cross-org manager',
      '2025-06-01T00:00:00Z', '2025-06-30T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] manager cross-organization NAO foi rejeitado';
  end if;
  raise notice '[PASS] tenant integrity: manager de outra organizacao rejeitado (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Motivo vazio deve ser rejeitado (check). Usa posição temporária sem
    -- linhas para isolar a checagem de reason.
    insert into public.organizational_positions (
      id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
    ) values (
      'f6c00000-0000-0000-0000-0000000000cc',
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6b00000-0000-0000-0000-0000000000a1',
      'f6d00000-0000-0000-0000-000000000004', null,
      '2025-01-01T00:00:00Z', null
    );
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000cc',
      'f6c00000-0000-0000-0000-0000000000a1',
      '   ', '2025-01-01T00:00:00Z', null
    );
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] reason vazio NAO foi rejeitado';
  end if;
  raise notice '[PASS] reason vazio/espacos rejeitado por check constraint';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Reporting line iniciando antes da existência das posições deve ser
    -- rejeitada pelo trigger de validade.
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000b1',
      'f6c00000-0000-0000-0000-0000000000b2',
      'f6c00000-0000-0000-0000-0000000000b1',
      'Periodo anterior a existencia',
      '2024-01-01T00:00:00Z', '2024-06-30T00:00:00Z'
    );
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] periodo anterior a existencia das posicoes NAO foi rejeitado';
  end if;
  raise notice '[PASS] reporting line antes da existencia das posicoes rejeitada (trigger de validade)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Reporting line aberta além do encerramento de uma posição (P_FECH
    -- encerrada em 2025-06-30) deve ser rejeitada.
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000aa',
      'f6c00000-0000-0000-0000-0000000000a1',
      'Relacao alem do encerramento',
      '2026-01-01T00:00:00Z', null
    );
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] relacao aberta alem do encerramento da posicao NAO foi rejeitada';
  end if;
  raise notice '[PASS] reporting line aberta alem do encerramento da posicao rejeitada (trigger de validade)';
end $$;

do $$
declare
  v_ok boolean := false;
  v_to timestamptz;
begin
  begin
    -- Encerrar posição com reporting lines abertas deve FALHAR (fail-closed,
    -- sem correção automática): P_GER2 tem linhas abertas como subordinate e
    -- como manager.
    update public.organizational_positions
       set valid_to = '2025-03-01T00:00:00Z'
     where id = 'f6c00000-0000-0000-0000-0000000000a5';
  exception when others then
    v_ok := true;
  end;

  select valid_to into v_to
  from public.organizational_positions
  where id = 'f6c00000-0000-0000-0000-0000000000a5';
  if v_to is not null then
    raise exception '[FAIL] encerramento de posicao com linhas abertas nao deveria ter sido aplicado';
  end if;
  if not v_ok then
    raise exception '[FAIL] encerramento de posicao com linhas abertas NAO falhou';
  end if;
  raise notice '[PASS] encerramento de posicao com reporting lines abertas falha (fail-closed, sem auto-correcao)';
end $$;

-- ============================================================================
-- 4) Timestamps/version e triggers técnicos
-- ============================================================================

do $$
declare
  v_ver int;
begin
  select version into v_ver
  from public.position_reporting_lines
  where subordinate_position_id = 'f6c00000-0000-0000-0000-0000000000b2';
  if v_ver <> 0 then
    raise exception '[FAIL] version default de reporting line inserida deveria ser 0';
  end if;
  raise notice '[PASS] version default 0 nas linhas inseridas (convencao F1-02)';
end $$;

-- ============================================================================
-- 5) RLS deny-by-default em execução (como authenticated)
-- ============================================================================

set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.position_reporting_lines;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de position_reporting_lines';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de position_reporting_lines';
end $$;

do $$
begin
  begin
    insert into public.position_reporting_lines (
      organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
    ) values (
      'f6a00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000a1',
      'f6c00000-0000-0000-0000-0000000000a2',
      'Teste RLS', '2026-01-01T00:00:00Z', null
    );
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em position_reporting_lines';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated em position_reporting_lines negado';
end $$;

do $$
declare
  v_n int;
begin
  update public.position_reporting_lines set version = version + 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu UPDATE de authenticated em position_reporting_lines (%)', v_n;
  end if;
  raise notice '[PASS] RLS: UPDATE de authenticated em position_reporting_lines afeta zero linhas';
end $$;

do $$
declare
  v_n int;
begin
  delete from public.position_reporting_lines;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu DELETE de authenticated em position_reporting_lines (%)', v_n;
  end if;
  raise notice '[PASS] RLS: DELETE de authenticated em position_reporting_lines afeta zero linhas';
end $$;

reset role;

-- ============================================================================
-- 6) F3-01/F3-02/F3-03 permanecem intactas
-- ============================================================================

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'collaborators';
  if v_cols is distinct from
     array['created_at', 'id', 'organization_id', 'updated_at', 'version']::text[]
  then
    raise exception '[FAIL] collaborators (F3-01) foi alterada indevidamente';
  end if;

  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'job_roles';
  if v_cols is distinct from
     array['created_at', 'id', 'name', 'organization_id', 'status',
           'updated_at', 'version']::text[]
  then
    raise exception '[FAIL] job_roles (F3-02) foi alterada indevidamente';
  end if;

  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'organizational_positions';
  if v_cols is distinct from
     array['created_at', 'id', 'job_role_id', 'organization_id',
           'seniority_level_id', 'unit_id', 'updated_at', 'valid_from',
           'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] organizational_positions (F3-03) foi alterada indevidamente';
  end if;
  raise notice '[PASS] F3-01/F3-02/F3-03 intactas (colunas preservadas; apenas unique de referencia aditiva)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'ex_collaborator_status_periods_no_overlap',
    'ex_collaborator_identifiers_no_overlap',
    'uq_collaborator_identifiers_organization_code',
    'ex_organizational_unit_parent_periods_no_overlap',
    'uq_job_roles_organization_name',
    'uq_seniority_levels_organization_name'
  );
  if v_n <> 6 then
    raise exception '[FAIL] constraints de F3-01/F3-02/F3-03 ausentes';
  end if;
  raise notice '[PASS] constraints temporais/uniques de F3-01/F3-02/F3-03 presentes';
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
-- 7) Limpeza do cenário sintético (banco local permanece limpo)
-- ============================================================================

delete from public.position_reporting_lines
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_positions
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.job_roles
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.seniority_levels
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.position_reporting_lines rl
  where rl.organization_id::text like 'f6a00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-04 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-04 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-04: todas as verificacoes passaram (schema, FKs, constraints, triggers, RLS).';
end $$;
