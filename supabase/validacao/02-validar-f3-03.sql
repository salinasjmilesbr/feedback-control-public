-- ============================================================================
-- F3-03 (Issue #80): validação automatizada — unidades e posições da
-- estrutura formal (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-03.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-03.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-03.sql -Raw -Encoding UTF8 |
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
        'seniority_levels',
        'user_organization_memberships',
        'user_profiles'
      )
  ) then
    raise exception '[FAIL] tabela inesperada no schema public (entidade fora do escopo F3-03)';
  end if;
  raise notice '[PASS] schema public contém somente as tabelas esperadas (F2 + F3-01 + F3-02 + F3-03)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and t.tablename in (
        'occupancies', 'position_occupancies', 'occupations',
        'reporting_lines', 'position_relationships', 'direct_reports',
        'organizational_position_occupancies', 'dotted_lines', 'committees',
        'projects', 'collegiates', 'snapshots'
      )
  ) then
    raise exception '[FAIL] tabela de occupation/reporting line/colegiado/projeto antecipada';
  end if;
  raise notice '[PASS] nenhuma tabela de occupation/reporting line/colegiado/dotted line antecipada';
end $$;

-- ----------------------------------------------------------------------------
-- 1.1 Colunas exatas das tabelas F3-03
-- ----------------------------------------------------------------------------

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'organizational_units';

  if v_cols is distinct from
     array['created_at', 'id', 'name', 'organization_id', 'updated_at',
           'valid_from', 'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] organizational_units possui colunas fora do escopo';
  end if;
  raise notice '[PASS] organizational_units: colunas exatas (id/org/name/valid_from/valid_to/técnicas)';
end $$;

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'organizational_unit_parent_periods';

  if v_cols is distinct from
     array['created_at', 'id', 'organization_id', 'parent_unit_id', 'unit_id',
           'updated_at', 'valid_from', 'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] organizational_unit_parent_periods possui colunas fora do escopo';
  end if;
  raise notice '[PASS] organizational_unit_parent_periods: colunas exatas da relacao temporal de parent';
end $$;

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'organizational_positions';

  if v_cols is distinct from
     array['created_at', 'id', 'job_role_id', 'organization_id',
           'seniority_level_id', 'unit_id', 'updated_at', 'valid_from',
           'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] organizational_positions possui colunas fora do escopo (ex.: collaborator_id/name/code)';
  end if;
  raise notice '[PASS] organizational_positions: colunas exatas (sem name/code/collaborator_id/occupation)';
end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name in ('organizational_units', 'organizational_unit_parent_periods',
                           'organizational_positions')
      and (
        lower(c.column_name) like '%collaborator%' or lower(c.column_name) like '%occup%'
        or lower(c.column_name) like '%report%' or lower(c.column_name) like '%manager%'
        or lower(c.column_name) like '%gestor%' or lower(c.column_name) like '%rank%'
        or lower(c.column_name) like '%order%' or lower(c.column_name) like '%hierar%'
        or lower(c.column_name) like '%dotted%' or lower(c.column_name) like '%colegiad%'
        or lower(c.column_name) like '%substitut%'
      )
  ) then
    raise exception '[FAIL] coluna de occupation/reporting/gestor/rank antecipada nas tabelas F3-03';
  end if;
  raise notice '[PASS] nenhuma coluna de occupation/reporting line/gestor/rank/colegiado nas tabelas F3-03';
end $$;

-- ----------------------------------------------------------------------------
-- 1.2 Identidade técnica e unicidade
-- ----------------------------------------------------------------------------

do $$
declare
  v_expr text;
  v_tabela text;
  v_tabelas text[] := array['organizational_units', 'organizational_unit_parent_periods',
                            'organizational_positions'];
begin
  foreach v_tabela in array v_tabelas loop
    select pg_get_expr(d.adbin, d.adrelid)
      into v_expr
    from pg_attrdef d
    where d.adrelid = (quote_ident('public') || '.' || quote_ident(v_tabela))::regclass
      and d.adnum = (
        select a.attnum
        from pg_attribute a
        where a.attrelid = d.adrelid and a.attname = 'id'
      );

    if v_expr is null or v_expr not like '%gen_random_uuid()%' then
      raise exception '[FAIL] %: id nao possui default gen_random_uuid()', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] id das tres tabelas F3-03 possui default gen_random_uuid() (UUID tecnico)';
end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.key_column_usage k
    join information_schema.table_constraints tc
      on tc.constraint_catalog = k.constraint_catalog
     and tc.constraint_schema = k.constraint_schema
     and tc.constraint_name = k.constraint_name
     and tc.table_name = k.table_name
    where k.table_schema = 'public'
      and k.table_name in ('organizational_units', 'organizational_unit_parent_periods',
                           'organizational_positions')
      and tc.constraint_type = 'PRIMARY KEY'
      and k.column_name in ('name', 'unit_id', 'job_role_id', 'organization_id',
                            'valid_from', 'valid_to')
  ) then
    raise exception '[FAIL] alguma PK das tabelas F3-03 nao e composta apenas por id';
  end if;
  raise notice '[PASS] PKs das tabelas F3-03 sao compostas somente por id (uuid)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conrelid = 'public.organizational_positions'::regclass
    and contype = 'u';
  if v_n <> 0 then
    raise exception '[FAIL] organizational_positions nao deveria ter unique natural (ocorrencias iguais sao validas)';
  end if;
  raise notice '[PASS] organizational_positions sem unique natural (somente PK por UUID)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conrelid = 'public.organizational_units'::regclass
    and contype = 'u'
    and conname in ('uq_organizational_units_id_organization',
                    'uq_organizational_units_organization_name');
  if v_n <> 2 then
    raise exception '[FAIL] uniques esperadas de organizational_units ausentes';
  end if;
  raise notice '[PASS] organizational_units com unique por (org, name) e unique de referencia (id, org)';
end $$;

-- ----------------------------------------------------------------------------
-- 1.3 Constraints, FKs, triggers
-- ----------------------------------------------------------------------------

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'pk_organizational_units',
    'uq_organizational_units_id_organization',
    'uq_organizational_units_organization_name',
    'fk_organizational_units_organizations',
    'ck_organizational_units_name',
    'ck_organizational_units_valid_to',
    'pk_organizational_unit_parent_periods',
    'fk_organizational_unit_parent_periods_child_unit',
    'fk_organizational_unit_parent_periods_parent_unit',
    'ck_organizational_unit_parent_periods_not_self',
    'ck_organizational_unit_parent_periods_valid_to',
    'ex_organizational_unit_parent_periods_no_overlap',
    'pk_organizational_positions',
    'fk_organizational_positions_organizations',
    'fk_organizational_positions_units',
    'fk_organizational_positions_job_roles',
    'fk_organizational_positions_seniority_levels',
    'ck_organizational_positions_valid_to'
  );
  if v_n <> 18 then
    raise exception '[FAIL] constraints esperadas da F3-03 ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] constraints pk/unique/fk/check/exclusion esperadas presentes na F3-03';
end $$;

do $$
declare
  v_n int;
begin
  -- Unique de referência aditiva nos catálogos da F3-02.
  select count(*) into v_n
  from pg_constraint
  where conname in ('uq_job_roles_id_organization', 'uq_seniority_levels_id_organization');
  if v_n <> 2 then
    raise exception '[FAIL] unique de referencia aditiva em job_roles/seniority_levels ausentes';
  end if;
  raise notice '[PASS] unique de referencia (id, organization_id) adicionadas em job_roles e seniority_levels';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid in ('public.organizational_units'::regclass,
                       'public.organizational_unit_parent_periods'::regclass,
                       'public.organizational_positions'::regclass)
    and c.confdeltype <> 'r';
  if v_n <> 0 then
    raise exception '[FAIL] existe FK sem ON DELETE RESTRICT nas tabelas F3-03';
  end if;
  raise notice '[PASS] todas as FKs das tabelas F3-03 sao ON DELETE RESTRICT';
end $$;

do $$
declare
  v_n int;
begin
  -- FKs de posição apontam exclusivamente para organizations/units/job_roles/
  -- seniority_levels (nunca para collaborators/auth/etc.).
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid = 'public.organizational_positions'::regclass
    and c.confrelid not in (
      'public.organizations'::regclass,
      'public.organizational_units'::regclass,
      'public.job_roles'::regclass,
      'public.seniority_levels'::regclass
    );
  if v_n <> 0 then
    raise exception '[FAIL] posicao referencia tabela fora do escopo estrutural';
  end if;
  if exists (
    select 1
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid = 'public.organizational_positions'::regclass
  ) then
    raise exception '[FAIL] alguma tabela ja referencia organizational_positions (occupation/reporting antecipados)';
  end if;
  raise notice '[PASS] nenhuma occupation/reporting line referencia posicoes; FKs de posicao restritas ao escopo';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgrelid in ('public.organizational_units'::regclass,
                      'public.organizational_unit_parent_periods'::regclass,
                      'public.organizational_positions'::regclass)
    and t.tgname in ('trg_organizational_units_updated_at',
                     'trg_organizational_unit_parent_periods_updated_at',
                     'trg_organizational_positions_updated_at');
  if v_n <> 3 then
    raise exception '[FAIL] triggers de updated_at esperados ausentes (% encontrados)', v_n;
  end if;
  raise notice '[PASS] triggers tecnicos de updated_at presentes nas tres tabelas F3-03';
end $$;

-- ----------------------------------------------------------------------------
-- 1.4 RLS habilitado e deny-by-default (estrutura)
-- ----------------------------------------------------------------------------

do $$
declare
  v_tabela text;
  v_tabelas text[] := array['organizational_units', 'organizational_unit_parent_periods',
                            'organizational_positions'];
begin
  foreach v_tabela in array v_tabelas loop
    perform 1
    from pg_class c
    where c.oid = (quote_ident('public') || '.' || quote_ident(v_tabela))::regclass
      and c.relrowsecurity = true;
    if not found then
      raise exception '[FAIL] RLS nao habilitado em %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] RLS habilitado nas tres tabelas F3-03';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename in ('organizational_units', 'organizational_unit_parent_periods',
                          'organizational_positions')
  ) then
    raise exception '[FAIL] existe policy nas tabelas F3-03 (deny-by-default violado)';
  end if;
  raise notice '[PASS] zero policies nas tabelas F3-03 (deny-by-default estrutural)';
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
                        'job_roles', 'seniority_levels')
      and c.relrowsecurity = false
  ) then
    raise exception '[FAIL] RLS de tabelas pre-existentes (F2/F3-01/F3-02) foi enfraquecido';
  end if;
  raise notice '[PASS] RLS das tabelas pre-existentes (F2/F3-01/F3-02) permanece habilitado';
end $$;

-- ============================================================================
-- 2) Cenário: unidades, parent temporal e posições
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.organizational_units
  where organization_id = 'f5a00000-0000-0000-0000-0000000000a1';
  if v_n <> 6 then
    raise exception '[FAIL] unidades da org Alfa esperado=6, encontrado=%', v_n;
  end if;
  select count(*) into v_n
  from public.organizational_units
  where organization_id = 'f5a00000-0000-0000-0000-0000000000b1';
  if v_n <> 1 then
    raise exception '[FAIL] unidades da org Beta esperado=1, encontrado=%', v_n;
  end if;
  raise notice '[PASS] unidades pertencem a organizacao correta (Alfa=6, Beta=1)';
end $$;

do $$
declare
  v_n int;
begin
  -- Unidade existe independentemente de posições (Diretoria Nova e a unidade
  -- encerrada não possuem posições) e unidade encerrada permanece preservada.
  select count(*) into v_n
  from public.organizational_units u
  where u.id = 'f5b00000-0000-0000-0000-0000000000a5'
    and not exists (select 1 from public.organizational_positions p
                    where p.unit_id = u.id);
  if v_n <> 1 then
    raise exception '[FAIL] unidade sem posicoes deveria existir (unidade independente de ocupantes/posicoes)';
  end if;
  select count(*) into v_n
  from public.organizational_units
  where id = 'f5b00000-0000-0000-0000-0000000000a6'
    and valid_to is not null;
  if v_n <> 1 then
    raise exception '[FAIL] unidade encerrada deveria permanecer preservada com valid_to';
  end if;
  raise notice '[PASS] unidade existe sem posicoes; unidade encerrada preservada (sem exclusao fisica)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.organizational_positions
  where organization_id = 'f5a00000-0000-0000-0000-0000000000a1';
  if v_n <> 6 then
    raise exception '[FAIL] posicoes da org Alfa esperado=6, encontrado=%', v_n;
  end if;
  select count(*) into v_n
  from public.organizational_positions
  where organization_id = 'f5a00000-0000-0000-0000-0000000000b1';
  if v_n <> 2 then
    raise exception '[FAIL] posicoes da org Beta esperado=2, encontrado=%', v_n;
  end if;
  raise notice '[PASS] posicoes pertencem a organizacao correta (Alfa=6, Beta=2)';
end $$;

do $$
declare
  v_n int;
begin
  -- Posição vaga é o estado natural: nenhuma tabela/coluna de ocupante existe
  -- (verificado na secao 1); todas as posicoes do cenario existem sem
  -- qualquer vinculo de ocupacao.
  select count(*) into v_n
  from public.organizational_positions;
  if v_n <> 8 then
    raise exception '[FAIL] total de posicoes do cenario esperado=8, encontrado=%', v_n;
  end if;
  raise notice '[PASS] posicoes existem sem ocupante (8 posicoes vagas; occupation fora do escopo)';
end $$;

do $$
declare
  v_n int;
begin
  -- Posição encerrada preservada (histórico não destrutivo via valid_to).
  select count(*) into v_n
  from public.organizational_positions
  where id = 'f5c00000-0000-0000-0000-0000000000a5'
    and valid_to is not null;
  if v_n <> 1 then
    raise exception '[FAIL] posicao encerrada deveria permanecer preservada com valid_to';
  end if;
  raise notice '[PASS] posicao encerrada preservada com valid_to (historico nao destrutivo)';
end $$;

do $$
declare
  v_n int;
  v_unidades int;
begin
  -- A_GER teve mudanca de parent (A_ROOT -> A_DIR2) SEM recriar a unidade:
  -- 1 linha de unidade e 2 periodos de parent.
  select count(*) into v_n
  from public.organizational_unit_parent_periods
  where unit_id = 'f5b00000-0000-0000-0000-0000000000a2';
  if v_n <> 2 then
    raise exception '[FAIL] A_GER deveria ter 2 periodos de parent (historico de reestruturacao)';
  end if;
  select count(*) into v_n
  from public.organizational_unit_parent_periods
  where unit_id = 'f5b00000-0000-0000-0000-0000000000a2'
    and valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] A_GER deveria ter exatamente um parent vigente';
  end if;
  select count(*) into v_unidades
  from public.organizational_units
  where id = 'f5b00000-0000-0000-0000-0000000000a2';
  if v_unidades <> 1 then
    raise exception '[FAIL] A_GER nao deveria ter sido recriada (mudanca de parent sem recriacao)';
  end if;
  raise notice '[PASS] parent temporal: mudanca de parent preserva historico e nao recria a unidade (2 periodos, 1 linha)';
end $$;

do $$
declare
  v_n int;
begin
  -- Parent vigente de A_GER e A_DIR2 (expansao acima/nova diretoria) e A_CORD
  -- (nivel intermediario criado depois) e filha de A_GER.
  select count(*) into v_n
  from public.organizational_unit_parent_periods
  where unit_id = 'f5b00000-0000-0000-0000-0000000000a2'
    and valid_to is null
    and parent_unit_id = 'f5b00000-0000-0000-0000-0000000000a5';
  if v_n <> 1 then
    raise exception '[FAIL] parent vigente de A_GER deveria ser A_DIR2';
  end if;
  select count(*) into v_n
  from public.organizational_unit_parent_periods
  where unit_id = 'f5b00000-0000-0000-0000-0000000000a3'
    and valid_to is null
    and parent_unit_id = 'f5b00000-0000-0000-0000-0000000000a2';
  if v_n <> 1 then
    raise exception '[FAIL] A_CORD deveria ser filha vigente de A_GER';
  end if;
  raise notice '[PASS] expansao acima (nova diretoria) e nivel intermediario posterior representaveis na arvore';
end $$;

do $$
declare
  v_n int;
begin
  -- Raiz: A_ROOT possui periodo aberto sem parent (null).
  select count(*) into v_n
  from public.organizational_unit_parent_periods
  where unit_id = 'f5b00000-0000-0000-0000-0000000000a1'
    and parent_unit_id is null
    and valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] A_ROOT deveria ser raiz (parent null vigente)';
  end if;
  raise notice '[PASS] unidade raiz representada por parent null no periodo';
end $$;

do $$
declare
  v_n int;
begin
  -- A_ESP (Especialistas) nao possui filhos na arvore: Especialista sem equipe.
  select count(*) into v_n
  from public.organizational_unit_parent_periods
  where parent_unit_id = 'f5b00000-0000-0000-0000-0000000000a4';
  if v_n <> 0 then
    raise exception '[FAIL] A_ESP nao deveria ter unidades filhas (Especialista sem equipe)';
  end if;
  select count(*) into v_n
  from public.organizational_positions
  where unit_id = 'f5b00000-0000-0000-0000-0000000000a4';
  if v_n <> 1 then
    raise exception '[FAIL] A_ESP deveria ter exatamente 1 posicao (Especialista)';
  end if;
  raise notice '[PASS] Especialista sem equipe/subordinados e representavel (unidade sem filhos)';
end $$;

do $$
declare
  v_n int;
  v_roles text[];
begin
  -- Gerencia (A_GER) contém posições de Gerente e de Analista diretamente,
  -- sem nenhuma posição de Coordenador: gerência sem coordenação
  -- intermediária é representável.
  select array_agg(jr.name order by jr.name) into v_roles
  from public.organizational_positions p
  join public.job_roles jr
    on jr.id = p.job_role_id and jr.organization_id = p.organization_id
  where p.unit_id = 'f5b00000-0000-0000-0000-0000000000a2';

  if v_roles is distinct from array['Analista', 'Analista', 'Consultor', 'Gerente']::text[] then
    raise exception '[FAIL] posicoes da Gerencia deveriam ser Gerente + Analistas (+ Consultor encerrado), sem Coordenador';
  end if;
  raise notice '[PASS] Gerente + Analista na mesma unidade sem Coordenador intermediario (estrutura sem niveis fixos)';
end $$;

do $$
declare
  v_n int;
begin
  -- O mesmo job_role (Analista) usado em partes/alturas diferentes: unidade
  -- Gerencia e unidade Coordenacao (3 posicoes de Analista no total).
  select count(*) into v_n
  from public.organizational_positions
  where job_role_id = 'f5d00000-0000-0000-0000-000000000004';
  if v_n <> 3 then
    raise exception '[FAIL] deveria haver 3 posicoes com o job_role Analista (em alturas diferentes)';
  end if;
  raise notice '[PASS] mesmo job_role usado em posicoes estruturalmente diferentes (3 posicoes de Analista)';
end $$;

do $$
declare
  v_n int;
begin
  -- Duas posicoes EXATAMENTE iguais (mesma unidade+funcao+seniority null) sao
  -- ocorrencias distintas validas.
  select count(*) into v_n
  from public.organizational_positions
  where unit_id = 'f5b00000-0000-0000-0000-0000000000a2'
    and job_role_id = 'f5d00000-0000-0000-0000-000000000004'
    and seniority_level_id is null;
  if v_n <> 2 then
    raise exception '[FAIL] duas posicoes identicas na mesma unidade deveriam ser validas';
  end if;
  raise notice '[PASS] posicoes com combinacao identica unidade+funcao+seniority null sao ocorrencias distintas';
end $$;

do $$
declare
  v_n int;
begin
  -- seniority null e valida (posicoes sem senioridade) e seniority preenchida
  -- referencia seniority da mesma organizacao.
  select count(*) into v_n
  from public.organizational_positions
  where seniority_level_id is null;
  if v_n < 4 then
    raise exception '[FAIL] posicoes com seniority null deveriam existir (senioridade opcional)';
  end if;
  select count(*) into v_n
  from public.organizational_positions
  where id = 'f5c00000-0000-0000-0000-0000000000a3'
    and seniority_level_id = 'f5d00000-0000-0000-0000-000000000012';
  if v_n <> 1 then
    raise exception '[FAIL] posicao Analista(Pleno) deveria referenciar a senioridade Pleno da org Alfa';
  end if;
  raise notice '[PASS] seniority opcional (null valido) e referenciada corretamente quando presente';
end $$;

-- ============================================================================
-- 3) Rejeições e integridade no banco
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Posicao na org Beta referenciando unidade da org Alfa (tenant violation).
    insert into public.organizational_positions (
      organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000b1',
      'f5b00000-0000-0000-0000-0000000000a1',
      'f5d00000-0000-0000-0000-000000000021',
      null, '2026-01-01T00:00:00Z', null
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] posicao Beta com unidade Alfa NAO foi rejeitada';
  end if;
  raise notice '[PASS] tenant integrity: posicao rejeita unidade de outra organizacao (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Posicao na org Beta referenciando job_role da org Alfa.
    insert into public.organizational_positions (
      organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000b1',
      'f5b00000-0000-0000-0000-0000000000b1',
      'f5d00000-0000-0000-0000-000000000002',
      null, '2026-01-01T00:00:00Z', null
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] posicao Beta com job_role Alfa NAO foi rejeitada';
  end if;
  raise notice '[PASS] tenant integrity: posicao rejeita job_role de outra organizacao (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Posicao na org Alfa referenciando seniority da org Beta.
    insert into public.organizational_positions (
      organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      'f5b00000-0000-0000-0000-0000000000a2',
      'f5d00000-0000-0000-0000-000000000006',
      'f5d00000-0000-0000-0000-000000000031',
      '2026-01-01T00:00:00Z', null
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] posicao Alfa com seniority Beta NAO foi rejeitada';
  end if;
  raise notice '[PASS] tenant integrity: posicao rejeita seniority de outra organizacao (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Parent na org Beta com filho da org Alfa, em periodo fechado no passado
    -- (sem sobreposicao com os periodos existentes do filho) para que apenas a
    -- FK composta de organizacao seja exercitada.
    insert into public.organizational_unit_parent_periods (
      organization_id, unit_id, parent_unit_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000b1',
      'f5b00000-0000-0000-0000-0000000000a1',
      null, '2020-01-01T00:00:00Z', '2020-02-01T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] parent Beta com unidade filha Alfa NAO foi rejeitado';
  end if;
  raise notice '[PASS] tenant integrity: parent rejeita filho de outra organizacao (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Parent Alfa (filho A_ESP) com pai da org Beta, em periodo fechado no
    -- passado (sem sobreposicao com o periodo vigente do filho) para que
    -- apenas a FK composta de organizacao seja exercitada.
    insert into public.organizational_unit_parent_periods (
      organization_id, unit_id, parent_unit_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      'f5b00000-0000-0000-0000-0000000000a4',
      'f5b00000-0000-0000-0000-0000000000b1',
      '2020-01-01T00:00:00Z', '2020-02-01T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] parent Alfa com pai Beta NAO foi rejeitado';
  end if;
  raise notice '[PASS] tenant integrity: parent rejeita pai de outra organizacao (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Sobreposicao temporal de parent do mesmo filho (A_CORD ja tem parent
    -- vigente desde 2025-07-01).
    insert into public.organizational_unit_parent_periods (
      organization_id, unit_id, parent_unit_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      'f5b00000-0000-0000-0000-0000000000a3',
      'f5b00000-0000-0000-0000-0000000000a1',
      '2026-01-01T00:00:00Z', null
    );
  exception when exclusion_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] sobreposicao de parent do mesmo filho NAO foi rejeitada';
  end if;
  raise notice '[PASS] no maximo um parent vigente por unidade: sobreposicao rejeitada (exclusion constraint)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Auto-parent (A_ROOT pai de si mesma) em periodo fechado no passado
    -- (sem sobreposicao com o periodo vigente de raiz) para que apenas o
    -- check de nao-auto-parent seja exercitado.
    insert into public.organizational_unit_parent_periods (
      organization_id, unit_id, parent_unit_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      'f5b00000-0000-0000-0000-0000000000a1',
      'f5b00000-0000-0000-0000-0000000000a1',
      '2020-01-01T00:00:00Z', '2020-02-01T00:00:00Z'
    );
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] auto-parent NAO foi rejeitado';
  end if;
  raise notice '[PASS] auto-parent rejeitado por check constraint (ciclos imediatos impedidos no banco)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.organizational_units (
      organization_id, name, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      'Gerencia Alfa F3-03',
      '2026-01-01T00:00:00Z', null
    );
  exception when unique_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] duplicidade de nome de unidade na mesma organizacao NAO foi rejeitada';
  end if;
  raise notice '[PASS] nome de unidade unico por organizacao (unique (org, name))';
end $$;

do $$
declare
  v_n int;
begin
  -- Mesmo nome de unidade em outra organizacao e permitido.
  insert into public.organizational_units (
    id, organization_id, name, valid_from, valid_to
  ) values (
    'f5b00000-0000-0000-0000-0000000000b2',
    'f5a00000-0000-0000-0000-0000000000b1',
    'Gerencia Alfa F3-03',
    '2026-01-01T00:00:00Z', null
  );
  select count(*) into v_n
  from public.organizational_units
  where name = 'Gerencia Alfa F3-03';
  if v_n <> 2 then
    raise exception '[FAIL] mesmo nome de unidade deveria existir em organizacoes diferentes';
  end if;
  delete from public.organizational_units
  where id = 'f5b00000-0000-0000-0000-0000000000b2';
  raise notice '[PASS] mesmo nome de unidade permitido em organizacoes diferentes (unique por org)';
end $$;

do $$
begin
  begin
    insert into public.organizational_units (
      organization_id, name, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      ' Unidade Invalida',
      '2026-01-01T00:00:00Z', null
    );
    raise exception '[FAIL] nome de unidade com espacos nas bordas NAO foi rejeitado';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] nome de unidade com espacos nas bordas rejeitado por check constraint';
end $$;

do $$
begin
  begin
    insert into public.organizational_units (
      organization_id, name, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      'Unidade Periodo Invalido',
      '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
    );
    raise exception '[FAIL] unidade com periodo invalido NAO foi rejeitada';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] unidade com valid_to <= valid_from rejeitada por check constraint';
end $$;

do $$
begin
  begin
    insert into public.organizational_positions (
      organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      'f5b00000-0000-0000-0000-0000000000a2',
      'f5d00000-0000-0000-0000-000000000006',
      null, '2026-01-01T00:00:00Z', '2025-12-31T00:00:00Z'
    );
    raise exception '[FAIL] posicao com periodo invalido NAO foi rejeitada';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] posicao com valid_to <= valid_from rejeitada por check constraint';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    delete from public.organizations
    where id = 'f5a00000-0000-0000-0000-0000000000a1';
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] exclusao fisica de organizacao com estrutura NAO foi bloqueada';
  end if;
  raise notice '[PASS] exclusao fisica de organizacao com unidades/posicoes bloqueada (FK RESTRICT)';
end $$;

-- ============================================================================
-- 4) Timestamps e versionamento (triggers técnicos atuando)
-- ============================================================================

do $$
declare
  v_ts timestamptz;
  v_ver int;
begin
  update public.organizational_units
     set updated_at = '2020-01-01T00:00:00Z'
   where id = 'f5b00000-0000-0000-0000-0000000000a2';

  update public.organizational_units
     set version = version + 1
   where id = 'f5b00000-0000-0000-0000-0000000000a2';

  select updated_at, version into v_ts, v_ver
  from public.organizational_units
  where id = 'f5b00000-0000-0000-0000-0000000000a2';

  if v_ver <> 1 then
    raise exception '[FAIL] version de unidade deveria ser 1 apos atualizacao (encontrado %)', v_ver;
  end if;
  if v_ts is null or v_ts <= '2020-01-01T00:00:00Z' then
    raise exception '[FAIL] updated_at de unidade nao redefinido pelo trigger tecnico';
  end if;
  raise notice '[PASS] version incrementada e updated_at mantido pelo trigger (set_updated_at) em organizational_units';
end $$;

do $$
declare
  v_ver int;
begin
  select version into v_ver
  from public.organizational_positions
  where id = 'f5c00000-0000-0000-0000-0000000000b1';
  if v_ver <> 0 then
    raise exception '[FAIL] version default de posicao inserida deveria ser 0';
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
  select count(*) into v_n from public.organizational_units;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de organizational_units';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de organizational_units';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.organizational_unit_parent_periods;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de organizational_unit_parent_periods';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de organizational_unit_parent_periods';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.organizational_positions;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de organizational_positions';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de organizational_positions';
end $$;

do $$
begin
  begin
    insert into public.organizational_positions (
      organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
    ) values (
      'f5a00000-0000-0000-0000-0000000000a1',
      'f5b00000-0000-0000-0000-0000000000a2',
      'f5d00000-0000-0000-0000-000000000002',
      null, '2026-01-01T00:00:00Z', null
    );
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em organizational_positions';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated em organizational_positions negado (row-level security)';
end $$;

do $$
declare
  v_n int;
begin
  update public.organizational_units set version = version + 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu UPDATE de authenticated em organizational_units (%)', v_n;
  end if;
  raise notice '[PASS] RLS: UPDATE de authenticated em organizational_units afeta zero linhas';
end $$;

do $$
declare
  v_n int;
begin
  delete from public.organizational_unit_parent_periods;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu DELETE de authenticated em organizational_unit_parent_periods (%)', v_n;
  end if;
  raise notice '[PASS] RLS: DELETE de authenticated em organizational_unit_parent_periods afeta zero linhas';
end $$;

reset role;

-- ============================================================================
-- 6) F3-01 e F3-02 permanecem intactas
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
  where table_schema = 'public' and table_name = 'seniority_levels';
  if v_cols is distinct from
     array['created_at', 'id', 'name', 'organization_id', 'status',
           'updated_at', 'version']::text[]
  then
    raise exception '[FAIL] seniority_levels (F3-02) foi alterada indevidamente';
  end if;
  raise notice '[PASS] F3-01 e F3-02 intactas (colunas preservadas; alteracoes apenas aditivas de unique de referencia)';
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
    'uq_job_roles_organization_name',
    'uq_seniority_levels_organization_name'
  );
  if v_n <> 5 then
    raise exception '[FAIL] constraints de F3-01/F3-02 ausentes';
  end if;
  raise notice '[PASS] constraints de lifecycle/identificadores (F3-01) e de catalogos (F3-02) presentes';
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

delete from public.organizational_positions
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_unit_parent_periods
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.job_roles
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.seniority_levels
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.organizational_positions p
  where p.organization_id::text like 'f5a00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-03 incompleta (posicoes)';
  end if;
  raise notice '[PASS] cenario sintetico F3-03 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-03: todas as verificacoes passaram (schema, FKs, constraints, triggers, RLS).';
end $$;
