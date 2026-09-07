-- ============================================================================
-- F3-01 (Issue #78): validação automatizada — colaboradores, identificadores
-- e períodos de status (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-01.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-01.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-01.sql -Raw -Encoding UTF8 |
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
        'organizations',
        'user_organization_memberships',
        'user_profiles'
      )
  ) then
    raise exception '[FAIL] tabela inesperada no schema public (entidade fora do escopo F3-01)';
  end if;
  raise notice '[PASS] schema public contém somente as tabelas esperadas (identidade/membership + F3-01)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and (
        t.tablename like '%position%' or t.tablename like '%occup%'
        or t.tablename like '%manager%' or t.tablename like '%hierarch%'
        or t.tablename like '%reporting%' or t.tablename like '%unit%'
        or t.tablename like '%role%' or t.tablename like '%funcao%'
        or t.tablename like '%seniority%' or t.tablename like '%area%'
        or t.tablename in (
          'organizational_positions', 'organizational_units', 'job_roles',
          'seniority_levels', 'direct_reports', 'reporting_lines'
        )
      )
  ) then
    raise exception '[FAIL] tabela de posicao/ocupacao/gestor/area/hierarquia antecipada';
  end if;
  raise notice '[PASS] nenhuma tabela de posicao/ocupacao/gestor/area/hierarquia antecipada';
end $$;

-- ----------------------------------------------------------------------------
-- 1.1 Colunas exatas das tabelas F3-01 (núcleo mínimo, sem atributos de
--     pessoa/estrutura antecipados)
-- ----------------------------------------------------------------------------

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
    raise exception '[FAIL] collaborators possui colunas fora do nucleo minimo (sem nome/email/gestor/area/posicao)';
  end if;
  raise notice '[PASS] collaborators: colunas exatamente id/organization_id/created_at/updated_at/version';
end $$;

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'collaborator_identifiers';

  if v_cols is distinct from
     array['business_code', 'collaborator_id', 'created_at', 'id',
           'organization_id', 'updated_at', 'valid_from', 'valid_to',
           'version']::text[]
  then
    raise exception '[FAIL] collaborator_identifiers possui colunas fora do escopo';
  end if;
  raise notice '[PASS] collaborator_identifiers: colunas exatas do identificador com validade';
end $$;

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'collaborator_status_periods';

  if v_cols is distinct from
     array['collaborator_id', 'created_at', 'id', 'status', 'updated_at',
           'valid_from', 'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] collaborator_status_periods possui colunas fora do escopo';
  end if;
  raise notice '[PASS] collaborator_status_periods: colunas exatas do periodo de status';
end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name in (
        'collaborators', 'collaborator_identifiers', 'collaborator_status_periods'
      )
      and (
        lower(c.column_name) like '%gestor%' or lower(c.column_name) like '%manager%'
        or lower(c.column_name) like '%area%' or lower(c.column_name) like '%unit%'
        or lower(c.column_name) like '%position%' or lower(c.column_name) like '%occup%'
        or lower(c.column_name) like '%hierarch%' or lower(c.column_name) like '%reporting%'
        or lower(c.column_name) like '%funcao%' or lower(c.column_name) like '%senioridade%'
        or lower(c.column_name) like '%seniority%' or lower(c.column_name) like '%cargo%'
        or lower(c.column_name) like '%direct%' or lower(c.column_name) like '%colegiad%'
      )
  ) then
    raise exception '[FAIL] coluna de gestor/area/posicao/hierarquia/funcao antecipada nas tabelas F3-01';
  end if;
  raise notice '[PASS] nenhuma coluna de gestor/area/posicao/hierarquia/funcao nas tabelas F3-01';
end $$;

-- ----------------------------------------------------------------------------
-- 1.2 Identidade técnica: UUID interno gerado, imutável e única PK
-- ----------------------------------------------------------------------------

do $$
declare
  v_expr text;
  v_tabela text;
  v_tabelas text[] := array['collaborators', 'collaborator_identifiers', 'collaborator_status_periods'];
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
  raise notice '[PASS] id das tres tabelas F3-01 possui default gen_random_uuid() (UUID tecnico interno)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_constraint c
    where c.contype = 'p'
      and c.conrelid in (
        'public.collaborators'::regclass,
        'public.collaborator_identifiers'::regclass,
        'public.collaborator_status_periods'::regclass
      )
      and (
        select count(*) from unnest(c.conkey) as k(coluna)
      ) <> 1
  ) then
    raise exception '[FAIL] alguma PK das tabelas F3-01 nao e composta apenas por id';
  end if;
  raise notice '[PASS] PKs das tabelas F3-01 sao compostas somente por id (uuid)';
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
      and k.table_name in (
        'collaborators', 'collaborator_identifiers', 'collaborator_status_periods'
      )
      and tc.constraint_type = 'PRIMARY KEY'
      and k.column_name in ('business_code', 'collaborator_id', 'organization_id',
                            'valid_from', 'valid_to', 'status')
  ) then
    raise exception '[FAIL] matricula/codigo (business_code) ou outra coluna de negocio compoe alguma PK';
  end if;
  raise notice '[PASS] business_code (matricula/codigo) NAO compoe PK em nenhuma tabela F3-01';
end $$;

-- ----------------------------------------------------------------------------
-- 1.3 Constraints esperadas (unique/check/exclusion/FK RESTRICT) e triggers
-- ----------------------------------------------------------------------------

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'pk_collaborators',
    'uq_collaborators_id_organization',
    'pk_collaborator_identifiers',
    'uq_collaborator_identifiers_organization_code',
    'pk_collaborator_status_periods'
  );
  if v_n <> 5 then
    raise exception '[FAIL] constraints unique/pk esperadas ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] PKs e constraints unique esperadas presentes (incl. unique por organization_id + business_code)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'ck_collaborator_identifiers_business_code',
    'ck_collaborator_identifiers_valid_to',
    'ck_collaborator_status_periods_status',
    'ck_collaborator_status_periods_valid_to'
  );
  if v_n <> 4 then
    raise exception '[FAIL] check constraints esperadas ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] check constraints de dominio/validade temporal presentes';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public'
    and t.relname in ('collaborator_identifiers', 'collaborator_status_periods')
    and c.contype = 'x'
    and c.conname in (
      'ex_collaborator_identifiers_no_overlap',
      'ex_collaborator_status_periods_no_overlap'
    );
  if v_n <> 2 then
    raise exception '[FAIL] exclusion constraints de nao-sobreposicao ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] exclusion constraints de nao-sobreposicao presentes (btree_gist/tstzrange)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  join pg_class t on t.oid = c.conrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public'
    and t.relname in ('collaborators', 'collaborator_identifiers', 'collaborator_status_periods')
    and c.contype = 'f'
    and c.confdeltype <> 'r';
  if v_n <> 0 then
    raise exception '[FAIL] existe FK sem ON DELETE RESTRICT nas tabelas F3-01';
  end if;
  raise notice '[PASS] todas as FKs das tabelas F3-01 sao ON DELETE RESTRICT';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgrelid in (
      'public.collaborators'::regclass,
      'public.collaborator_identifiers'::regclass,
      'public.collaborator_status_periods'::regclass
    )
    and t.tgname in (
      'trg_collaborators_updated_at',
      'trg_collaborator_identifiers_updated_at',
      'trg_collaborator_status_periods_updated_at'
    );
  if v_n <> 3 then
    raise exception '[FAIL] triggers de updated_at esperados ausentes (% encontrados)', v_n;
  end if;
  raise notice '[PASS] triggers tecnicos de updated_at presentes nas tres tabelas F3-01';
end $$;

-- ----------------------------------------------------------------------------
-- 1.4 RLS habilitado e deny-by-default (estrutura)
-- ----------------------------------------------------------------------------

do $$
declare
  v_tabela text;
  v_tabelas text[] := array['collaborators', 'collaborator_identifiers', 'collaborator_status_periods'];
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
  raise notice '[PASS] RLS habilitado nas tres tabelas F3-01';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename in ('collaborators', 'collaborator_identifiers', 'collaborator_status_periods')
  ) then
    raise exception '[FAIL] existe policy nas tabelas F3-01 (deny-by-default violado)';
  end if;
  raise notice '[PASS] zero policies nas tabelas F3-01 (deny-by-default estrutural)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in ('organizations', 'user_profiles', 'user_organization_memberships')
      and c.relrowsecurity = false
  ) then
    raise exception '[FAIL] RLS de tabelas pre-existentes (F2) foi enfraquecido';
  end if;
  raise notice '[PASS] RLS das tabelas pre-existentes (organizations/user_profiles/memberships) permanece habilitado';
end $$;

-- ============================================================================
-- 2) Dados do cenário: identidade, identificadores e isolamento por org
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.collaborators
  where organization_id = 'f3a00000-0000-0000-0000-0000000000a1';
  if v_n <> 3 then
    raise exception '[FAIL] colaboradores da org Alfa esperado=3, encontrado=%', v_n;
  end if;
  select count(*) into v_n
  from public.collaborators
  where organization_id = 'f3a00000-0000-0000-0000-0000000000b1';
  if v_n <> 1 then
    raise exception '[FAIL] colaboradores da org Beta esperado=1, encontrado=%', v_n;
  end if;
  raise notice '[PASS] isolamento estrutural por organization_id (Alfa=3, Beta=1)';
end $$;

do $$
begin
  if exists (
    select 1
    from public.collaborator_identifiers a
    join public.collaborator_identifiers b
      on a.business_code = b.business_code
     and a.organization_id = b.organization_id
     and a.id <> b.id
  ) then
    raise exception '[FAIL] duplicidade de business_code na MESMA organizacao presente no cenario';
  end if;
  raise notice '[PASS] sem duplicidade de business_code dentro da mesma organizacao';
end $$;

do $$
declare
  v_n int;
begin
  -- Ana (Alfa) e Bruno (Beta) compartilham o codigo MAT-1001 em organizacoes
  -- diferentes: reuso entre organizacoes e permitido pela unique com org.
  select count(*) into v_n
  from public.collaborator_identifiers
  where business_code = 'MAT-1001';
  if v_n <> 2 then
    raise exception '[FAIL] reuso do mesmo codigo entre organizacoes diferentes deveria ser permitido';
  end if;
  raise notice '[PASS] mesmo business_code permitido em organizacoes diferentes (multi-organizacao)';
end $$;

do $$
declare
  v_n int;
  v_codigo text;
begin
  -- Carlos trocou o codigo (MAT-2001 fechado -> MAT-3001 vigente) sem trocar o id.
  select count(*) into v_n
  from public.collaborators
  where id = 'f3b00000-0000-0000-0000-0000000000c1';
  if v_n <> 1 then
    raise exception '[FAIL] Carlos nao deveria existir como um unico collaborator';
  end if;

  select count(*) into v_n
  from public.collaborator_identifiers
  where collaborator_id = 'f3b00000-0000-0000-0000-0000000000c1';
  if v_n <> 2 then
    raise exception '[FAIL] Carlos deveria ter 2 linhas de identificador (historico + vigente)';
  end if;

  select business_code into v_codigo
  from public.collaborator_identifiers
  where collaborator_id = 'f3b00000-0000-0000-0000-0000000000c1'
    and valid_to is null;
  if v_codigo is distinct from 'MAT-3001' then
    raise exception '[FAIL] codigo vigente de Carlos deveria ser MAT-3001';
  end if;
  raise notice '[PASS] alteracao historica de identificador nao troca collaborator.id (2 linhas; vigente MAT-3001)';
end $$;

-- ============================================================================
-- 3) Lifecycle: histórico ACTIVE → LEAVE → ACTIVE e licença sem ocupação
-- ============================================================================

do $$
declare
  v_status text[];
begin
  select array_agg(status order by valid_from)
    into v_status
  from public.collaborator_status_periods
  where collaborator_id = 'f3b00000-0000-0000-0000-0000000000a1';

  if v_status is distinct from array['active', 'leave', 'active']::text[] then
    raise exception '[FAIL] historico de Ana deveria ser ACTIVE -> LEAVE -> ACTIVE (encontrado: %)',
      coalesce(array_to_string(v_status, ','), 'vazio');
  end if;
  raise notice '[PASS] historico ACTIVE -> LEAVE -> ACTIVE preservado (3 periodos, nao destrutivo)';
end $$;

do $$
declare
  v_status text;
  v_abertos int;
begin
  select status into v_status
  from public.collaborator_status_periods
  where collaborator_id = 'f3b00000-0000-0000-0000-0000000000a1'
    and valid_to is null;

  if v_status is distinct from 'active' then
    raise exception '[FAIL] periodo vigente de Ana deveria ser active';
  end if;

  select count(*) into v_abertos
  from public.collaborator_status_periods
  where collaborator_id = 'f3b00000-0000-0000-0000-0000000000a1'
    and valid_to is null;
  if v_abertos <> 1 then
    raise exception '[FAIL] Ana deveria ter exatamente um periodo aberto (encontrados %)', v_abertos;
  end if;
  raise notice '[PASS] no maximo um periodo aberto vigente por colaborador (Ana = active)';
end $$;

do $$
declare
  v_status text;
  v_colaborador int;
  v_identificador int;
begin
  -- Diana esta em LEAVE vigente; a licenca NAO remove o vinculo organizacional
  -- nem o identificador e nao cria/encerra ocupacao (nao ha tabelas de
  -- posicao/ocupacao — verificado na secao 1).
  select status into v_status
  from public.collaborator_status_periods
  where collaborator_id = 'f3b00000-0000-0000-0000-0000000000d1'
    and valid_to is null;
  if v_status is distinct from 'leave' then
    raise exception '[FAIL] Diana deveria estar em leave vigente';
  end if;

  select count(*) into v_colaborador
  from public.collaborators
  where id = 'f3b00000-0000-0000-0000-0000000000d1';
  if v_colaborador <> 1 then
    raise exception '[FAIL] Diana deveria permanecer em collaborators durante a licenca';
  end if;

  select count(*) into v_identificador
  from public.collaborator_identifiers
  where collaborator_id = 'f3b00000-0000-0000-0000-0000000000d1'
    and valid_to is null;
  if v_identificador <> 1 then
    raise exception '[FAIL] identificador de Diana deveria permanecer vigente durante a licenca';
  end if;
  raise notice '[PASS] licenca (leave) e estado do colaborador: nao remove vinculo nem identificador; sem posicao/ocupacao';
end $$;

-- ============================================================================
-- 4) Rejeições de períodos inválidos e sobreposições (integridade no banco)
-- ============================================================================
-- Blocos de rejeição usam colaboradores temporarios com UUIDs fixos
-- (f3c00000-…) criados e revertidos dentro do proprio bloco (rollback de
-- subtransacao), garantindo determinismo sem poluir o cenario.

do $$
begin
  begin
    insert into public.collaborator_status_periods (
      collaborator_id, status, valid_from, valid_to
    ) values (
      'f3b00000-0000-0000-0000-0000000000b1',
      'active',
      '2026-01-01T00:00:00Z',
      '2026-01-01T00:00:00Z'
    );
    raise exception '[FAIL] periodo de status invalido (valid_to <= valid_from) NAO foi rejeitado';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] periodo invalido (valid_to = valid_from) rejeitado por check constraint';
end $$;

do $$
begin
  begin
    insert into public.collaborators (id, organization_id)
    values (
      'f3c00000-0000-0000-0000-0000000000e2',
      'f3a00000-0000-0000-0000-0000000000a1'
    );
    insert into public.collaborator_status_periods (
      collaborator_id, status, valid_from, valid_to
    ) values (
      'f3c00000-0000-0000-0000-0000000000e2',
      'terminated',
      '2030-01-01T00:00:00Z',
      null
    );
    raise exception '[FAIL] status fora do dominio NAO foi rejeitado';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] status fora do dominio (active/leave/inactive, ex.: terminated) rejeitado por check constraint';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.collaborator_status_periods (
      collaborator_id, status, valid_from, valid_to
    ) values (
      'f3b00000-0000-0000-0000-0000000000b1',
      'leave',
      '2025-03-01T00:00:00Z',
      null
    );
  exception when exclusion_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] sobreposicao de periodo (active vigente + leave sobreposto) NAO foi rejeitada';
  end if;
  raise notice '[PASS] sobreposicao temporal de status do mesmo colaborador rejeitada por exclusion constraint';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Duplicidade do codigo MAT-1001 (ja usado por Ana) na org Alfa, em
    -- periodo fechado passado (sem sobreposicao com Diana) para que apenas a
    -- unique (organization_id, business_code) seja exercitada.
    insert into public.collaborator_identifiers (
      collaborator_id, organization_id, business_code, valid_from, valid_to
    ) values (
      'f3b00000-0000-0000-0000-0000000000d1',
      'f3a00000-0000-0000-0000-0000000000a1',
      'MAT-1001',
      '2020-01-01T00:00:00Z',
      '2020-02-01T00:00:00Z'
    );
  exception when unique_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] codigo duplicado na mesma organizacao NAO foi rejeitado';
  end if;
  raise notice '[PASS] business_code duplicado na mesma organizacao rejeitado por unique constraint';
end $$;

do $$
begin
  begin
    insert into public.collaborators (id, organization_id)
    values (
      'f3c00000-0000-0000-0000-0000000000e3',
      'f3a00000-0000-0000-0000-0000000000a1'
    );
    insert into public.collaborator_identifiers (
      collaborator_id, organization_id, business_code, valid_from, valid_to
    ) values (
      'f3c00000-0000-0000-0000-0000000000e3',
      'f3a00000-0000-0000-0000-0000000000a1',
      'MAT-7000',
      '2026-01-01T00:00:00Z',
      '2026-01-01T00:00:00Z'
    );
    raise exception '[FAIL] periodo de identificador invalido NAO foi rejeitado';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] periodo de identificador invalido (valid_to <= valid_from) rejeitado por check constraint';
end $$;

do $$
begin
  begin
    insert into public.collaborators (id, organization_id)
    values (
      'f3c00000-0000-0000-0000-0000000000e4',
      'f3a00000-0000-0000-0000-0000000000a1'
    );
    insert into public.collaborator_identifiers (
      collaborator_id, organization_id, business_code, valid_from, valid_to
    ) values (
      'f3c00000-0000-0000-0000-0000000000e4',
      'f3a00000-0000-0000-0000-0000000000a1',
      ' MAT-9003',
      '2026-01-01T00:00:00Z',
      null
    );
    raise exception '[FAIL] codigo com espacos nas bordas NAO foi rejeitado';
  exception when check_violation then
    null;
  end;
  raise notice '[PASS] business_code com espacos nas bordas rejeitado (normalizacao por check constraint)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Identificador com organization_id diferente da organizacao do colaborador
    -- (Ana pertence a Alfa): a FK composta deve rejeitar. Periodo fechado
    -- passado evita exercitar tambem a exclusion constraint.
    insert into public.collaborator_identifiers (
      collaborator_id, organization_id, business_code, valid_from, valid_to
    ) values (
      'f3b00000-0000-0000-0000-0000000000a1',
      'f3a00000-0000-0000-0000-0000000000b1',
      'MAT-4001',
      '2020-01-01T00:00:00Z',
      '2020-02-01T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] inconsistencia de organization_id entre identificador e colaborador NAO foi rejeitada';
  end if;
  raise notice '[PASS] FK composta rejeita identificador com organization_id diferente do colaborador';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    delete from public.organizations
    where id = 'f3a00000-0000-0000-0000-0000000000a1';
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] exclusao fisica de organizacao com colaboradores NAO foi bloqueada';
  end if;
  raise notice '[PASS] exclusao fisica de organizacao com colaboradores bloqueada (FK RESTRICT)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    delete from public.collaborators
    where id = 'f3b00000-0000-0000-0000-0000000000b1';
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] exclusao fisica de colaborador com identificador/status NAO foi bloqueada';
  end if;
  raise notice '[PASS] exclusao fisica de colaborador com historico bloqueada (FK RESTRICT)';
end $$;

-- ============================================================================
-- 5) Timestamps e versionamento (triggers técnicos atuando)
-- ============================================================================

do $$
declare
  v_ts timestamptz;
  v_ver int;
begin
  -- Carlos: retrocede updated_at e atualiza version; o trigger tecnico deve
  -- redefinir updated_at e a version deve ser incrementada pela aplicacao.
  update public.collaborators
     set updated_at = '2020-01-01T00:00:00Z'
   where id = 'f3b00000-0000-0000-0000-0000000000c1';

  update public.collaborators
     set version = version + 1
   where id = 'f3b00000-0000-0000-0000-0000000000c1';

  select updated_at, version into v_ts, v_ver
  from public.collaborators
  where id = 'f3b00000-0000-0000-0000-0000000000c1';

  if v_ver <> 1 then
    raise exception '[FAIL] version deveria ser 1 apos uma atualizacao (encontrado %)', v_ver;
  end if;
  if v_ts is null or v_ts <= '2020-01-01T00:00:00Z' then
    raise exception '[FAIL] updated_at nao foi redefinido pelo trigger tecnico';
  end if;
  raise notice '[PASS] version incrementada e updated_at mantido pelo trigger (set_updated_at) em collaborators';
end $$;

do $$
declare
  v_ver int;
begin
  select version into v_ver
  from public.collaborator_status_periods
  where collaborator_id = 'f3b00000-0000-0000-0000-0000000000b1'
    and valid_to is null;
  if v_ver <> 0 then
    raise exception '[FAIL] version default de periodo inserido deveria ser 0';
  end if;
  raise notice '[PASS] version default 0 nas linhas inseridas (convencao F1-02)';
end $$;

-- ============================================================================
-- 6) RLS deny-by-default em execução (como authenticated)
-- ============================================================================

set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de collaborators (deny-by-default violado)';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de collaborators';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.collaborator_identifiers;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de collaborator_identifiers';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de collaborator_identifiers';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.collaborator_status_periods;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de collaborator_status_periods';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de collaborator_status_periods';
end $$;

do $$
begin
  begin
    insert into public.collaborators (id, organization_id)
    values (
      'f3c00000-0000-0000-0000-0000000000e1',
      'f3a00000-0000-0000-0000-0000000000a1'
    );
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em collaborators';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated em collaborators negado (row-level security)';
end $$;

do $$
declare
  v_n int;
begin
  -- Sem policy de escrita, UPDATE/DELETE afetam zero linhas (nao ha USING);
  -- o deny-by-default e comprovado pelo ROW_COUNT = 0.
  update public.collaborators
     set version = version + 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu UPDATE de authenticated em collaborators (%)', v_n;
  end if;
  raise notice '[PASS] RLS: UPDATE de authenticated em collaborators afeta zero linhas';
end $$;

do $$
declare
  v_n int;
begin
  delete from public.collaborators;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu DELETE de authenticated em collaborators (%)', v_n;
  end if;
  raise notice '[PASS] RLS: DELETE de authenticated em collaborators afeta zero linhas';
end $$;

reset role;

-- ============================================================================
-- 7) Limpeza do cenário sintético (banco local permanece limpo)
-- ============================================================================

delete from public.collaborator_status_periods
where collaborator_id in (
  'f3b00000-0000-0000-0000-0000000000a1',
  'f3b00000-0000-0000-0000-0000000000b1',
  'f3b00000-0000-0000-0000-0000000000c1',
  'f3b00000-0000-0000-0000-0000000000d1'
);

delete from public.collaborator_identifiers
where collaborator_id in (
  'f3b00000-0000-0000-0000-0000000000a1',
  'f3b00000-0000-0000-0000-0000000000b1',
  'f3b00000-0000-0000-0000-0000000000c1',
  'f3b00000-0000-0000-0000-0000000000d1'
);

delete from public.collaborators
where id in (
  'f3b00000-0000-0000-0000-0000000000a1',
  'f3b00000-0000-0000-0000-0000000000b1',
  'f3b00000-0000-0000-0000-0000000000c1',
  'f3b00000-0000-0000-0000-0000000000d1'
);

delete from public.organizations
where id in (
  'f3a00000-0000-0000-0000-0000000000a1',
  'f3a00000-0000-0000-0000-0000000000b1'
);

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.collaborators c
  where c.id::text like 'f3b00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-01 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-01 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-01: todas as verificacoes passaram (schema, FKs, constraints, triggers, RLS).';
end $$;
