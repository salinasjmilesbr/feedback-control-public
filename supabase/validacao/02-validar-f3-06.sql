-- ============================================================================
-- F3-06 (Issue #83): validação automatizada — responsabilidades temporárias e
-- substituições (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-06.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-06.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-06.sql -Raw -Encoding UTF8 |
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
    raise exception '[FAIL] tabela inesperada no schema public (entidade fora do escopo F3-06)';
  end if;
  raise notice '[PASS] schema public contém somente as tabelas esperadas (F2 + F3-01/02/03/04/05 + F3-06)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and t.tablename in (
        'collegiates', 'evaluation_panels', 'evaluations', 'snapshots',
        'dotted_lines', 'capabilities', 'permissions', 'rbac_roles'
      )
  ) then
    raise exception '[FAIL] tabela de colegiado/avaliacao/capability/snapshot antecipada';
  end if;
  raise notice '[PASS] nenhuma tabela de colegiado/avaliacao/capability/snapshot antecipada';
end $$;

-- ----------------------------------------------------------------------------
-- 1.1 Colunas exatas de temporary_responsibilities
-- ----------------------------------------------------------------------------

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
    raise exception '[FAIL] temporary_responsibilities possui colunas fora do escopo';
  end if;
  raise notice '[PASS] temporary_responsibilities: colunas exatas (posicao/substituto/tipo/reason/validade)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'temporary_responsibilities'
    and lower(c.column_name) in ('incumbent_collaborator_id', 'changed_by',
                                 'author', 'reporting_line_id', 'unit_id');
  if v_n <> 0 then
    raise exception '[FAIL] coluna de titular/autor/reporting/unit antecipada em temporary_responsibilities';
  end if;
  raise notice '[PASS] sem coluna de titular explícito/autor/reporting/unit (titular derivado de occupation)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'temporary_responsibilities'
    and c.column_name in ('organizational_position_id', 'substitute_collaborator_id',
                          'responsibility_type', 'reason', 'valid_from', 'valid_to')
    and c.is_nullable = 'YES';
  if v_n <> 0 then
    raise exception '[FAIL] colunas obrigatorias de temporary_responsibilities permitem NULL';
  end if;
  raise notice '[PASS] posicao/substituto/tipo/reason/valid_from/valid_to NOT NULL (periodo fechado)';
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
  where d.adrelid = 'public.temporary_responsibilities'::regclass
    and d.adnum = (
      select a.attnum
      from pg_attribute a
      where a.attrelid = d.adrelid and a.attname = 'id'
    );
  if v_expr is null or v_expr not like '%gen_random_uuid()%' then
    raise exception '[FAIL] id de temporary_responsibilities sem default gen_random_uuid()';
  end if;
  raise notice '[PASS] id de temporary_responsibilities com default gen_random_uuid() (UUID tecnico)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'pk_temporary_responsibilities',
    'fk_temporary_responsibilities_organizations',
    'fk_temporary_responsibilities_positions',
    'fk_temporary_responsibilities_substitute',
    'ck_temporary_responsibilities_type',
    'ck_temporary_responsibilities_reason',
    'ck_temporary_responsibilities_valid_to',
    'ex_temporary_responsibilities_position_no_overlap'
  );
  if v_n <> 8 then
    raise exception '[FAIL] constraints esperadas de temporary_responsibilities ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] constraints pk/fk/check/exclusion esperadas presentes em temporary_responsibilities';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid = 'public.temporary_responsibilities'::regclass
    and c.confdeltype <> 'r';
  if v_n <> 0 then
    raise exception '[FAIL] existe FK sem ON DELETE RESTRICT em temporary_responsibilities';
  end if;
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid = 'public.temporary_responsibilities'::regclass
    and c.confrelid not in (
      'public.organizations'::regclass,
      'public.organizational_positions'::regclass,
      'public.collaborators'::regclass
    );
  if v_n <> 0 then
    raise exception '[FAIL] FK de temporary_responsibilities aponta para tabela fora do escopo';
  end if;
  if exists (
    select 1
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid = 'public.temporary_responsibilities'::regclass
  ) then
    raise exception '[FAIL] alguma tabela ja referencia temporary_responsibilities (antecipacao)';
  end if;
  raise notice '[PASS] FKs RESTRICT restritas a organizations/positions/collaborators; nada referencia temporary_responsibilities';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgrelid = 'public.temporary_responsibilities'::regclass
    and t.tgname in ('trg_temporary_responsibilities_updated_at',
                     'trg_temporary_responsibilities_within_position',
                     'trg_temporary_responsibilities_not_self');
  if v_n <> 3 then
    raise exception '[FAIL] triggers de temporary_responsibilities ausentes (% encontrados)', v_n;
  end if;
  raise notice '[PASS] triggers de updated_at/validade/anti-auto-substituicao presentes';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('enforce_temporary_responsibility_within_position',
                      'enforce_temporary_responsibility_not_self');
  if v_n <> 2 then
    raise exception '[FAIL] funcoes de integridade F3-06 ausentes';
  end if;
  raise notice '[PASS] funcoes de integridade (validade na posicao; anti-auto-substituicao) presentes';
end $$;

-- ----------------------------------------------------------------------------
-- 1.3 RLS habilitado e deny-by-default (estrutura)
-- ----------------------------------------------------------------------------

do $$
begin
  perform 1
  from pg_class c
  where c.oid = 'public.temporary_responsibilities'::regclass
    and c.relrowsecurity = true;
  if not found then
    raise exception '[FAIL] RLS nao habilitado em temporary_responsibilities';
  end if;
  raise notice '[PASS] RLS habilitado em temporary_responsibilities';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'temporary_responsibilities'
  ) then
    raise exception '[FAIL] existe policy em temporary_responsibilities (deny-by-default violado)';
  end if;
  raise notice '[PASS] zero policies em temporary_responsibilities (deny-by-default estrutural)';
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
                        'organizational_unit_parent_periods', 'organizational_positions',
                        'position_reporting_lines', 'occupations')
      and c.relrowsecurity = false
  ) then
    raise exception '[FAIL] RLS de tabelas pre-existentes foi enfraquecido';
  end if;
  raise notice '[PASS] RLS das tabelas pre-existentes (F2/F3-01..05) permanece habilitado';
end $$;

-- ============================================================================
-- 2) Cenário: titular, substituto, temporalidade e tipos
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.temporary_responsibilities
  where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
  if v_n <> 3 then
    raise exception '[FAIL] temporary responsibilities da org Alfa esperado=3, encontrado=%', v_n;
  end if;
  raise notice '[PASS] temporary responsibilities pertencem a organizacao correta (Alfa=3)';
end $$;

do $$
declare
  v_n int;
  v_sub uuid;
begin
  -- Titular mantém a occupation e substituto é resolvido como responsável
  -- vigente no período (ambos coexistem; substituto não recebe occupation).
  select count(*) into v_n
  from public.occupations
  where organizational_position_id = 'f8c00000-0000-0000-0000-0000000000a1'
    and collaborator_id = 'f8b00000-0000-0000-0000-0000000000c1'
    and valid_from <= '2025-03-15T00:00:00Z'
    and (valid_to is null or valid_to > '2025-03-15T00:00:00Z');
  if v_n <> 1 then
    raise exception '[FAIL] titular C1 deveria manter a occupation de P1 durante a substituicao';
  end if;

  select substitute_collaborator_id into v_sub
  from public.temporary_responsibilities
  where organizational_position_id = 'f8c00000-0000-0000-0000-0000000000a1'
    and valid_from <= '2025-03-15T00:00:00Z'
    and valid_to > '2025-03-15T00:00:00Z';
  if v_sub is distinct from 'f8b00000-0000-0000-0000-0000000000c2' then
    raise exception '[FAIL] substituto vigente de P1 em 2025-03-15 deveria ser C2';
  end if;

  select count(*) into v_n
  from public.occupations
  where organizational_position_id = 'f8c00000-0000-0000-0000-0000000000a1'
    and collaborator_id = 'f8b00000-0000-0000-0000-0000000000c2';
  if v_n <> 0 then
    raise exception '[FAIL] substituto C2 nao deveria ter recebido occupation em P1';
  end if;
  raise notice '[PASS] titular mantem occupation; substituto e resolvido sem occupation artificial';
end $$;

do $$
declare
  v_n int;
  v_sub uuid;
  v_man uuid;
begin
  -- Reporting line permanece inalterada (P2 → P1).
  select count(*) into v_n
  from public.position_reporting_lines
  where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] reporting line de Alfa deveria permanecer unica';
  end if;
  select subordinate_position_id, manager_position_id into v_sub, v_man
  from public.position_reporting_lines
  where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
    and valid_to is null;
  if v_sub is distinct from 'f8c00000-0000-0000-0000-0000000000a2'
     or v_man is distinct from 'f8c00000-0000-0000-0000-0000000000a1' then
    raise exception '[FAIL] reporting line P2 → P1 deveria permanecer inalterada';
  end if;
  raise notice '[PASS] reporting line permanece inalterada pela substituicao';
end $$;

do $$
declare
  v_n int;
begin
  -- Reconstrução antes/durante/depois: sem substituição antes e depois; titular
  -- reassume ao término sem recriação de occupation.
  select count(*) into v_n
  from public.temporary_responsibilities
  where organizational_position_id = 'f8c00000-0000-0000-0000-0000000000a1'
    and valid_from <= '2025-02-15T00:00:00Z'
    and valid_to > '2025-02-15T00:00:00Z';
  if v_n <> 0 then
    raise exception '[FAIL] nao deveria haver substituicao vigente de P1 antes do inicio';
  end if;

  select count(*) into v_n
  from public.temporary_responsibilities
  where organizational_position_id = 'f8c00000-0000-0000-0000-0000000000a1'
    and valid_from <= '2025-05-15T00:00:00Z'
    and valid_to > '2025-05-15T00:00:00Z';
  if v_n <> 0 then
    raise exception '[FAIL] nao deveria haver substituicao vigente de P1 apos o fim';
  end if;

  select count(*) into v_n
  from public.occupations
  where organizational_position_id = 'f8c00000-0000-0000-0000-0000000000a1'
    and collaborator_id = 'f8b00000-0000-0000-0000-0000000000c1'
    and valid_from <= '2025-05-15T00:00:00Z'
    and (valid_to is null or valid_to > '2025-05-15T00:00:00Z');
  if v_n <> 1 then
    raise exception '[FAIL] titular deveria reassumir ao fim da substituicao (sem recriacao de occupation)';
  end if;
  raise notice '[PASS] reconstrucao antes/durante/depois; titular reassume sem recriar occupation';
end $$;

do $$
declare
  v_n int;
begin
  -- Mesmo substituto cobre duas posições simultaneamente (P1 e P2).
  select count(*) into v_n
  from public.temporary_responsibilities
  where substitute_collaborator_id = 'f8b00000-0000-0000-0000-0000000000c2'
    and valid_from <= '2025-03-15T00:00:00Z'
    and valid_to > '2025-03-15T00:00:00Z';
  if v_n <> 2 then
    raise exception '[FAIL] C2 deveria cobrir 2 posicoes simultaneamente em 2025-03-15 (encontrado %)', v_n;
  end if;
  raise notice '[PASS] um colaborador pode assumir responsabilidades temporarias em multiplas posicoes';
end $$;

do $$
declare
  v_n int;
begin
  -- Tipo evaluative presente (preparação para resolução futura) e período
  -- fechado em todas as linhas.
  select count(*) into v_n
  from public.temporary_responsibilities
  where responsibility_type = 'evaluative';
  if v_n <> 1 then
    raise exception '[FAIL] deveria haver 1 temporary responsibility do tipo evaluative';
  end if;
  select count(*) into v_n
  from public.temporary_responsibilities
  where valid_to is null;
  if v_n <> 0 then
    raise exception '[FAIL] nao deveria haver temporary responsibility com fim indefinido';
  end if;
  select count(*) into v_n
  from public.temporary_responsibilities
  where btrim(reason) = '';
  if v_n <> 0 then
    raise exception '[FAIL] existe temporary responsibility com reason vazio';
  end if;
  raise notice '[PASS] tipo evaluative presente; periodo fechado; reason nao vazio';
end $$;

-- ============================================================================
-- 3) Rejeições e integridade no banco
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Sobreposição na mesma posição (P1 já tem substituição em 2025-03/04).
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8b00000-0000-0000-0000-0000000000c3',
      'operational', 'Segundo substituto invalido',
      '2025-04-01T00:00:00Z', '2025-04-15T00:00:00Z'
    );
  exception when exclusion_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] sobreposicao de substituicoes na mesma posicao NAO foi rejeitada';
  end if;
  raise notice '[PASS] no maximo uma temporary responsibility por posicao por instante (exclusion)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Período sem fim (valid_to NULL) deve ser rejeitado (NOT NULL).
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a4',
      'f8b00000-0000-0000-0000-0000000000c2',
      'operational', 'Sem fim definido', '2025-05-01T00:00:00Z', null
    );
  exception when not_null_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] periodo sem fim (valid_to NULL) NAO foi rejeitado';
  end if;
  raise notice '[PASS] periodo obrigatoriamente fechado (valid_to NOT NULL)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Auto-substituição: C1 é o ocupante formal de P1 e tenta ser substituto.
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8b00000-0000-0000-0000-0000000000c1',
      'operational', 'Auto-substituicao invalida',
      '2025-05-01T00:00:00Z', '2025-05-31T00:00:00Z'
    );
  exception when others then
    if sqlerrm not like '%ocupante formal%' then
      raise;
    end if;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] auto-substituicao NAO foi rejeitada';
  end if;
  raise notice '[PASS] auto-substituicao rejeitada (substituto nao pode ser o ocupante formal)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Cross-organization (substituto de outra org): P4 (Alfa) com Cb (Beta).
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a4',
      'f8b00000-0000-0000-0000-0000000000d1',
      'operational', 'Cross-org substitute',
      '2025-05-01T00:00:00Z', '2025-05-31T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] substituto de outra organizacao NAO foi rejeitado';
  end if;
  raise notice '[PASS] tenant integrity: substituto de outra organizacao rejeitado (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Cross-organization (posicao de outra org): BP1 (Beta) com C2 (Alfa), org Alfa.
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000b1',
      'f8b00000-0000-0000-0000-0000000000c2',
      'operational', 'Cross-org position',
      '2025-05-01T00:00:00Z', '2025-05-31T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] posicao de outra organizacao NAO foi rejeitada';
  end if;
  raise notice '[PASS] tenant integrity: posicao de outra organizacao rejeitada (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Período além do encerramento da posição (P5 encerrada em 2025-06-30).
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a5',
      'f8b00000-0000-0000-0000-0000000000c2',
      'operational', 'Periodo alem da posicao',
      '2025-03-01T00:00:00Z', '2025-07-15T00:00:00Z'
    );
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] periodo alem do encerramento da posicao NAO foi rejeitado';
  end if;
  raise notice '[PASS] periodo alem do encerramento da posicao rejeitado (trigger de validade)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Tipo fora do domínio.
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a4',
      'f8b00000-0000-0000-0000-0000000000c2',
      'operational_x', 'Tipo invalido', '2025-05-01T00:00:00Z', '2025-05-31T00:00:00Z'
    );
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] responsibility_type fora do dominio NAO foi rejeitado';
  end if;
  raise notice '[PASS] responsibility_type fora do dominio rejeitado (check constraint)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Motivo vazio.
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a4',
      'f8b00000-0000-0000-0000-0000000000c2',
      'operational', '   ', '2025-05-01T00:00:00Z', '2025-05-31T00:00:00Z'
    );
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] reason vazio NAO foi rejeitado';
  end if;
  raise notice '[PASS] reason vazio/espacos rejeitado por check constraint';
end $$;

-- ============================================================================
-- 4) Timestamps e versionamento
-- ============================================================================

do $$
declare
  v_ts timestamptz;
  v_ver int;
  v_id uuid;
begin
  select id into v_id
  from public.temporary_responsibilities
  where organizational_position_id = 'f8c00000-0000-0000-0000-0000000000a3'
    and responsibility_type = 'evaluative';

  update public.temporary_responsibilities
     set updated_at = '2020-01-01T00:00:00Z'
   where id = v_id;

  update public.temporary_responsibilities
     set version = version + 1
   where id = v_id;

  select updated_at, version into v_ts, v_ver
  from public.temporary_responsibilities
  where id = v_id;

  if v_ver <> 1 then
    raise exception '[FAIL] version de temporary responsibility deveria ser 1 apos atualizacao (encontrado %)', v_ver;
  end if;
  if v_ts is null or v_ts <= '2020-01-01T00:00:00Z' then
    raise exception '[FAIL] updated_at nao redefinido pelo trigger tecnico';
  end if;
  raise notice '[PASS] version incrementada e updated_at mantido pelo trigger (set_updated_at)';
end $$;

-- ============================================================================
-- 5) RLS deny-by-default em execução (como authenticated)
-- ============================================================================

set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.temporary_responsibilities;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de temporary_responsibilities';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de temporary_responsibilities';
end $$;

do $$
begin
  begin
    insert into public.temporary_responsibilities (
      organization_id, organizational_position_id, substitute_collaborator_id,
      responsibility_type, reason, valid_from, valid_to
    ) values (
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a4',
      'f8b00000-0000-0000-0000-0000000000c2',
      'operational', 'Teste RLS', '2026-01-01T00:00:00Z', '2026-02-01T00:00:00Z'
    );
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em temporary_responsibilities';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated em temporary_responsibilities negado';
end $$;

do $$
declare
  v_n int;
begin
  update public.temporary_responsibilities set version = version + 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu UPDATE de authenticated em temporary_responsibilities (%)', v_n;
  end if;
  raise notice '[PASS] RLS: UPDATE de authenticated em temporary_responsibilities afeta zero linhas';
end $$;

do $$
declare
  v_n int;
begin
  delete from public.temporary_responsibilities;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu DELETE de authenticated em temporary_responsibilities (%)', v_n;
  end if;
  raise notice '[PASS] RLS: DELETE de authenticated em temporary_responsibilities afeta zero linhas';
end $$;

reset role;

-- ============================================================================
-- 6) F3-01..F3-05 permanecem intactas
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
  where table_schema = 'public' and table_name = 'occupations';
  if v_cols is distinct from
     array['collaborator_id', 'created_at', 'id', 'organization_id',
           'organizational_position_id', 'reason', 'updated_at', 'valid_from',
           'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] occupations (F3-05) foi alterada indevidamente';
  end if;

  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'position_reporting_lines';
  if v_cols is distinct from
     array['created_at', 'id', 'manager_position_id', 'organization_id',
           'reason', 'subordinate_position_id', 'updated_at', 'valid_from',
           'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] position_reporting_lines (F3-04) foi alterada indevidamente';
  end if;
  raise notice '[PASS] F3-01/F3-02/F3-03/F3-04/F3-05 intactas (colunas preservadas)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'ex_collaborator_status_periods_no_overlap',
    'ex_occupations_position_no_overlap',
    'ex_position_reporting_lines_no_overlap',
    'ex_organizational_unit_parent_periods_no_overlap',
    'uq_organizational_positions_id_organization'
  );
  if v_n <> 5 then
    raise exception '[FAIL] constraints de F3-01/F3-03/F3-04/F3-05 ausentes';
  end if;
  raise notice '[PASS] constraints temporais/uniques de F3-01/F3-03/F3-04/F3-05 presentes';
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

delete from public.temporary_responsibilities
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.occupations
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborator_status_periods
where collaborator_id in (
  'f8b00000-0000-0000-0000-0000000000c1',
  'f8b00000-0000-0000-0000-0000000000c2',
  'f8b00000-0000-0000-0000-0000000000c3',
  'f8b00000-0000-0000-0000-0000000000c4',
  'f8b00000-0000-0000-0000-0000000000d1'
);

delete from public.position_reporting_lines
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_positions
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborators
where id in (
  'f8b00000-0000-0000-0000-0000000000c1',
  'f8b00000-0000-0000-0000-0000000000c2',
  'f8b00000-0000-0000-0000-0000000000c3',
  'f8b00000-0000-0000-0000-0000000000c4',
  'f8b00000-0000-0000-0000-0000000000d1'
);

delete from public.job_roles
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.temporary_responsibilities t
  where t.organization_id::text like 'f8a00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-06 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-06 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-06: todas as verificacoes passaram (schema, FKs, constraints, triggers, RLS).';
end $$;
