-- ============================================================================
-- F3-05 (Issue #82): validação automatizada — ocupações temporais de
-- colaboradores em posições (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-05.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-05.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-05.sql -Raw -Encoding UTF8 |
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
        'user_organization_memberships',
        'user_profiles'
      )
  ) then
    raise exception '[FAIL] tabela inesperada no schema public (entidade fora do escopo F3-05)';
  end if;
  raise notice '[PASS] schema public contém somente as tabelas esperadas (F2 + F3-01/02/03/04 + F3-05)';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and t.tablename in (
        'temporary_responsibilities', 'substitutions', 'collegiates',
        'evaluation_panels', 'evaluations', 'snapshots', 'dotted_lines'
      )
  ) then
    raise exception '[FAIL] tabela de substituicao/colegiado/avaliacao/snapshot antecipada';
  end if;
  raise notice '[PASS] nenhuma tabela de substituicao/colegiado/avaliacao/snapshot antecipada';
end $$;

-- ----------------------------------------------------------------------------
-- 1.1 Colunas exatas de occupations
-- ----------------------------------------------------------------------------

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name order by column_name)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'occupations';

  if v_cols is distinct from
     array['collaborator_id', 'created_at', 'id', 'organization_id',
           'organizational_position_id', 'reason', 'updated_at', 'valid_from',
           'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] occupations possui colunas fora do escopo';
  end if;
  raise notice '[PASS] occupations: colunas exatas (collaborator/posicao/org/reason/validade/tecnicas)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'occupations'
    and c.column_name in ('changed_by', 'author', 'temporary', 'substitute',
                          'reporting_line_id');
  if v_n <> 0 then
    raise exception '[FAIL] coluna de autor/substituicao/reporting antecipada em occupations';
  end if;
  raise notice '[PASS] sem coluna de autor/substituicao/reporting em occupations';
end $$;

do $$
declare
  v_n int;
begin
  -- Collaborator e posicao NOT NULL (sem occupation artificial com NULL).
  select count(*) into v_n
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'occupations'
    and c.column_name in ('collaborator_id', 'organizational_position_id', 'reason', 'valid_from')
    and c.is_nullable = 'YES';
  if v_n <> 0 then
    raise exception '[FAIL] collaborator_id/position_id/reason/valid_from deveriam ser NOT NULL';
  end if;
  raise notice '[PASS] collaborator_id/position_id NOT NULL (vacancia = ausencia; sem occupation artificial)';
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
  where d.adrelid = 'public.occupations'::regclass
    and d.adnum = (
      select a.attnum
      from pg_attribute a
      where a.attrelid = d.adrelid and a.attname = 'id'
    );
  if v_expr is null or v_expr not like '%gen_random_uuid()%' then
    raise exception '[FAIL] id de occupations sem default gen_random_uuid()';
  end if;
  raise notice '[PASS] id de occupations com default gen_random_uuid() (UUID tecnico)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'pk_occupations',
    'fk_occupations_organizations',
    'fk_occupations_collaborators',
    'fk_occupations_positions',
    'ck_occupations_reason',
    'ck_occupations_valid_to',
    'ex_occupations_position_no_overlap'
  );
  if v_n <> 7 then
    raise exception '[FAIL] constraints esperadas de occupations ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] constraints pk/fk/check/exclusion esperadas presentes em occupations';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in ('uq_collaborators_id_organization',
                    'uq_organizational_positions_id_organization');
  if v_n <> 2 then
    raise exception '[FAIL] unique de referencia de collaborators/positions ausentes';
  end if;
  raise notice '[PASS] unique de referencia (id, organization_id) de collaborators e positions presentes';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid = 'public.occupations'::regclass
    and c.confdeltype <> 'r';
  if v_n <> 0 then
    raise exception '[FAIL] existe FK sem ON DELETE RESTRICT em occupations';
  end if;
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid = 'public.occupations'::regclass
    and c.confrelid not in (
      'public.organizations'::regclass,
      'public.collaborators'::regclass,
      'public.organizational_positions'::regclass
    );
  if v_n <> 0 then
    raise exception '[FAIL] FK de occupations aponta para tabela fora do escopo';
  end if;
  if exists (
    select 1
    from pg_constraint c
    where c.contype = 'f'
      and c.confrelid = 'public.occupations'::regclass
  ) then
    raise exception '[FAIL] alguma tabela ja referencia occupations (antecipacao)';
  end if;
  raise notice '[PASS] FKs RESTRICT restritas a organizations/collaborators/positions; nada referencia occupations';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgrelid = 'public.occupations'::regclass
    and t.tgname in ('trg_occupations_updated_at',
                     'trg_occupations_within_position');
  if v_n <> 2 then
    raise exception '[FAIL] triggers de occupations ausentes (% encontrados)', v_n;
  end if;
  select count(*) into v_n
  from pg_trigger t
  where not t.tgisinternal
    and t.tgrelid = 'public.collaborator_status_periods'::regclass
    and t.tgname = 'trg_collaborator_status_periods_inactive_occupations';
  if v_n <> 1 then
    raise exception '[FAIL] trigger de desligamento ausente';
  end if;
  raise notice '[PASS] triggers de updated_at/validade (occupations) e de desligamento presentes';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('enforce_occupation_within_position',
                      'enforce_collaborator_inactive_requires_closed_occupations');
  if v_n <> 2 then
    raise exception '[FAIL] funcoes de integridade F3-05 ausentes';
  end if;
  raise notice '[PASS] funcoes de integridade (validade na posicao; desligamento) presentes';
end $$;

-- ----------------------------------------------------------------------------
-- 1.3 RLS habilitado e deny-by-default (estrutura)
-- ----------------------------------------------------------------------------

do $$
begin
  perform 1
  from pg_class c
  where c.oid = 'public.occupations'::regclass
    and c.relrowsecurity = true;
  if not found then
    raise exception '[FAIL] RLS nao habilitado em occupations';
  end if;
  raise notice '[PASS] RLS habilitado em occupations';
end $$;

do $$
begin
  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'occupations'
  ) then
    raise exception '[FAIL] existe policy em occupations (deny-by-default violado)';
  end if;
  raise notice '[PASS] zero policies em occupations (deny-by-default estrutural)';
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
                        'position_reporting_lines')
      and c.relrowsecurity = false
  ) then
    raise exception '[FAIL] RLS de tabelas pre-existentes foi enfraquecido';
  end if;
  raise notice '[PASS] RLS das tabelas pre-existentes (F2/F3-01/02/03/04) permanece habilitado';
end $$;

-- ============================================================================
-- 2) Cenário: ocupação, vacância, multi-posições, transferência, licença
-- ============================================================================

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.occupations
  where organization_id = 'f7a00000-0000-0000-0000-0000000000a1';
  if v_n <> 4 then
    raise exception '[FAIL] occupations da org Alfa esperado=4, encontrado=%', v_n;
  end if;
  select count(*) into v_n
  from public.occupations
  where organization_id = 'f7a00000-0000-0000-0000-0000000000b1';
  if v_n <> 1 then
    raise exception '[FAIL] occupations da org Beta esperado=1, encontrado=%', v_n;
  end if;
  raise notice '[PASS] occupations pertencem a organizacao correta (Alfa=4, Beta=1)';
end $$;

do $$
declare
  v_col uuid;
begin
  -- Posição ocupada em cada data e posição vaga (P4 nunca ocupada).
  select collaborator_id into v_col
  from public.occupations
  where organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a1'
    and valid_from <= '2025-03-01T00:00:00Z'
    and (valid_to is null or valid_to > '2025-03-01T00:00:00Z');
  if v_col is distinct from 'f7b00000-0000-0000-0000-0000000000c1' then
    raise exception '[FAIL] P1 em 2025-03-01 deveria ser ocupada por C1';
  end if;

  select collaborator_id into v_col
  from public.occupations
  where organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a4'
    and valid_from <= '2025-03-01T00:00:00Z'
    and (valid_to is null or valid_to > '2025-03-01T00:00:00Z');
  if v_col is not null then
    raise exception '[FAIL] P4 deveria estar vaga em 2025-03-01';
  end if;
  raise notice '[PASS] posicao ocupada e posicao vaga (ausencia de occupation) validas';
end $$;

do $$
declare
  v_col uuid;
  v_n int;
begin
  -- Troca de ocupante na MESMA posição P1 (C1 até 2025-06-30; C2 desde
  -- 2025-07-01), sem recriar a posição.
  select collaborator_id into v_col
  from public.occupations
  where organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a1'
    and valid_from <= '2025-08-01T00:00:00Z'
    and (valid_to is null or valid_to > '2025-08-01T00:00:00Z');
  if v_col is distinct from 'f7b00000-0000-0000-0000-0000000000c2' then
    raise exception '[FAIL] P1 em 2025-08-01 deveria ser ocupada por C2';
  end if;

  select count(*) into v_n
  from public.occupations
  where organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a1';
  if v_n <> 2 then
    raise exception '[FAIL] P1 deveria ter 2 occupations (C1 encerrada + C2 vigente)';
  end if;

  select count(*) into v_n
  from public.organizational_positions
  where id = 'f7c00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] posicao P1 nao deveria ter sido recriada';
  end if;
  raise notice '[PASS] troca de ocupante preserva a posicao (2 occupations historico; posicao unica)';
end $$;

do $$
declare
  v_n int;
begin
  -- Colaborador ocupando DUAS posições simultaneamente (C1 em P1 e P2).
  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c1'
    and valid_from <= '2025-03-01T00:00:00Z'
    and (valid_to is null or valid_to > '2025-03-01T00:00:00Z');
  if v_n <> 2 then
    raise exception '[FAIL] C1 deveria ocupar 2 posicoes simultaneamente em 2025-03-01 (encontrado %)', v_n;
  end if;
  raise notice '[PASS] colaborador ocupa duas posicoes simultaneamente (sem exclusion por collaborator)';
end $$;

do $$
declare
  v_n int;
  v_status text;
begin
  -- Licença independente: em 2025-04-15 C3 está em leave e sua occupation em
  -- P3 permanece vigente; após o retorno (2025-08-01) a mesma occupation segue
  -- única e aberta (sem recriação).
  select status into v_status
  from public.collaborator_status_periods
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c3'
    and valid_from <= '2025-04-15T00:00:00Z'
    and (valid_to is null or valid_to > '2025-04-15T00:00:00Z');
  if v_status is distinct from 'leave' then
    raise exception '[FAIL] C3 deveria estar em leave em 2025-04-15';
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c3'
    and organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a3'
    and valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] occupation de C3 em P3 deveria permanecer vigente durante a licenca';
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c3';
  if v_n <> 1 then
    raise exception '[FAIL] C3 deveria ter exatamente 1 occupation (licenca nao recria occupation)';
  end if;
  raise notice '[PASS] licenca (leave) nao encerra nem recria occupation (conceitos independentes)';
end $$;

do $$
declare
  v_n int;
begin
  -- Histórico consultável por data: occupation encerrada de C1 em P1 preservada
  -- e consultável em 2025-03-01; transferência mantém histórico das duas.
  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c1'
    and organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a1'
    and valid_to = '2025-06-30T00:00:00Z';
  if v_n <> 1 then
    raise exception '[FAIL] occupation encerrada de C1 em P1 deveria estar preservada';
  end if;
  raise notice '[PASS] historico consultavel por data (encerramento preserva linhas e UUIDs)';
end $$;

do $$
declare
  v_n int;
  v_sub uuid;
  v_man uuid;
begin
  -- Reporting line independente do ocupante: permanece P2 → P1 inalterada.
  select count(*) into v_n
  from public.position_reporting_lines
  where organization_id = 'f7a00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] reporting line de Alfa deveria permanecer unica';
  end if;
  select subordinate_position_id, manager_position_id into v_sub, v_man
  from public.position_reporting_lines
  where organization_id = 'f7a00000-0000-0000-0000-0000000000a1'
    and valid_to is null;
  if v_sub is distinct from 'f7c00000-0000-0000-0000-0000000000a2'
     or v_man is distinct from 'f7c00000-0000-0000-0000-0000000000a1' then
    raise exception '[FAIL] reporting line P2 → P1 deveria permanecer inalterada';
  end if;
  raise notice '[PASS] reporting line permanece independente do ocupante (troca de ocupante nao a altera)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.occupations
  where btrim(reason) = '';
  if v_n <> 0 then
    raise exception '[FAIL] existe occupation com reason vazio';
  end if;
  raise notice '[PASS] reason obrigatorio e nao vazio em todas as occupations';
end $$;

-- ============================================================================
-- 3) Rejeições e integridade no banco
-- ============================================================================

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Segundo ocupante simultaneo na mesma posicao (P1 ja ocupada por C2).
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c3',
      'f7c00000-0000-0000-0000-0000000000a1',
      'Segundo ocupante invalido',
      '2026-01-01T00:00:00Z', null
    );
  exception when exclusion_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] dois ocupantes simultaneos na mesma posicao NAO foram rejeitados';
  end if;
  raise notice '[PASS] um ocupante por posicao por instante (exclusion por position)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Occupation iniciando antes da existencia da posicao (P4 existe desde
    -- 2025-01-01): deve ser rejeitada pelo trigger de validade.
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c4',
      'f7c00000-0000-0000-0000-0000000000a4',
      'Periodo anterior a posicao',
      '2024-01-01T00:00:00Z', '2024-06-30T00:00:00Z'
    );
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] occupation anterior a existencia da posicao NAO foi rejeitada';
  end if;
  raise notice '[PASS] occupation antes da existencia da posicao rejeitada (trigger de validade)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Occupation aberta alem do encerramento da posicao (P5 encerrada em
    -- 2025-06-30): deve ser rejeitada.
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c4',
      'f7c00000-0000-0000-0000-0000000000a5',
      'Ocupacao alem do encerramento',
      '2025-03-01T00:00:00Z', null
    );
  exception when others then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] occupation aberta alem do encerramento da posicao NAO foi rejeitada';
  end if;
  raise notice '[PASS] occupation alem do encerramento da posicao rejeitada (trigger de validade)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Cross-organization (collaborator de outra org): occupation Alfa com Cb
    -- (Beta), posicao vaga P4 (Alfa).
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000d1',
      'f7c00000-0000-0000-0000-0000000000a4',
      'Cross-org collaborator',
      '2025-06-01T00:00:00Z', '2025-06-30T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] occupation com collaborator de outra organizacao NAO foi rejeitada';
  end if;
  raise notice '[PASS] tenant integrity: collaborator de outra organizacao rejeitado (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Cross-organization (posicao de outra org): occupation Beta com posicao
    -- P4 (Alfa), colaborador Cb (Beta).
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000b1',
      'f7b00000-0000-0000-0000-0000000000d1',
      'f7c00000-0000-0000-0000-0000000000a4',
      'Cross-org position',
      '2025-06-01T00:00:00Z', '2025-06-30T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] occupation com posicao de outra organizacao NAO foi rejeitada';
  end if;
  raise notice '[PASS] tenant integrity: posicao de outra organizacao rejeitada (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Motivo vazio (posicao vaga P4, colaborador C4 sem occupations).
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c4',
      'f7c00000-0000-0000-0000-0000000000a4',
      '   ', '2026-01-01T00:00:00Z', null
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
    -- Periodo invalido (valid_to <= valid_from).
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c4',
      'f7c00000-0000-0000-0000-0000000000a4',
      'Periodo invalido',
      '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
    );
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] occupation com periodo invalido NAO foi rejeitada';
  end if;
  raise notice '[PASS] occupation com valid_to <= valid_from rejeitada por check constraint';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Desligamento (inactive) com occupation vigente (C2 em P1) deve ser
    -- BLOQUEADO pelo trigger fail-closed (mensagem específica).
    insert into public.collaborator_status_periods (
      collaborator_id, status, valid_from, valid_to
    ) values (
      'f7b00000-0000-0000-0000-0000000000c2',
      'inactive',
      '2026-01-01T00:00:00Z', null
    );
  exception when others then
    if sqlerrm not like '%occupations%' then
      raise;
    end if;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] desligamento com occupation vigente NAO foi bloqueado';
  end if;
  raise notice '[PASS] desligamento com occupation vigente bloqueado (fail-closed; encerrar occupations antes)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.collaborator_status_periods
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c2'
    and status = 'inactive';
  if v_n <> 0 then
    raise exception '[FAIL] tentativa bloqueada nao deveria ter persistido periodo inactive';
  end if;
  raise notice '[PASS] bloqueio nao persiste estado (nenhum periodo inactive para C2)';
end $$;

do $$
declare
  v_ok boolean := false;
  v_n int;
  v_id uuid;
begin
  -- Desligamento coerente: C4 (sem occupations) pode ser desligado após
  -- encerrar o período active. Executa e reverte para manter o cenário.
  select id into v_id
  from public.collaborator_status_periods
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c4'
    and status = 'active'
    and valid_to is null;

  begin
    update public.collaborator_status_periods
       set valid_to = '2026-01-01T00:00:00Z'
     where id = v_id;
    insert into public.collaborator_status_periods (
      collaborator_id, status, valid_from, valid_to
    ) values (
      'f7b00000-0000-0000-0000-0000000000c4',
      'inactive', '2026-01-01T00:00:00Z', null
    );
    v_ok := true;
  exception when others then
    raise;
  end;

  if not v_ok then
    raise exception '[FAIL] desligamento sem occupations vigentes NAO foi permitido';
  end if;
  raise notice '[PASS] desligamento permitido apos fechamento explicito das occupations (nonexistentes)';

  -- Reverter: remove o periodo inactive e reabre o active.
  delete from public.collaborator_status_periods
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c4'
    and status = 'inactive';
  update public.collaborator_status_periods
     set valid_to = null
   where id = v_id;
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
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c1'
    and organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a1'
    and valid_to = '2025-06-30T00:00:00Z';

  update public.occupations
     set updated_at = '2020-01-01T00:00:00Z'
   where id = v_id;

  update public.occupations
     set version = version + 1
   where id = v_id;

  select updated_at, version into v_ts, v_ver
  from public.occupations
  where id = v_id;

  if v_ver <> 1 then
    raise exception '[FAIL] version de occupation deveria ser 1 apos atualizacao (encontrado %)', v_ver;
  end if;
  if v_ts is null or v_ts <= '2020-01-01T00:00:00Z' then
    raise exception '[FAIL] updated_at nao redefinido pelo trigger tecnico';
  end if;
  raise notice '[PASS] version incrementada e updated_at mantido pelo trigger (set_updated_at) em occupations';
end $$;

do $$
declare
  v_ver int;
begin
  select version into v_ver
  from public.occupations
  where organizational_position_id = 'f7c00000-0000-0000-0000-0000000000b1'
    and valid_to is null;
  if v_ver <> 0 then
    raise exception '[FAIL] version default de occupation inserida deveria ser 0';
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
  select count(*) into v_n from public.occupations;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de occupations';
  end if;
  raise notice '[PASS] RLS: authenticated nao le linhas de occupations';
end $$;

do $$
begin
  begin
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c1',
      'f7c00000-0000-0000-0000-0000000000a4',
      'Teste RLS', '2026-01-01T00:00:00Z', null
    );
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em occupations';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated em occupations negado';
end $$;

do $$
declare
  v_n int;
begin
  update public.occupations set version = version + 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu UPDATE de authenticated em occupations (%)', v_n;
  end if;
  raise notice '[PASS] RLS: UPDATE de authenticated em occupations afeta zero linhas';
end $$;

do $$
declare
  v_n int;
begin
  delete from public.occupations;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu DELETE de authenticated em occupations (%)', v_n;
  end if;
  raise notice '[PASS] RLS: DELETE de authenticated em occupations afeta zero linhas';
end $$;

reset role;

-- ============================================================================
-- 6) F3-01/F3-02/F3-03/F3-04 permanecem intactas
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
  where table_schema = 'public' and table_name = 'organizational_positions';
  if v_cols is distinct from
     array['created_at', 'id', 'job_role_id', 'organization_id',
           'seniority_level_id', 'unit_id', 'updated_at', 'valid_from',
           'valid_to', 'version']::text[]
  then
    raise exception '[FAIL] organizational_positions (F3-03) foi alterada indevidamente';
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
  raise notice '[PASS] F3-01/F3-02/F3-03/F3-04 intactas (colunas preservadas)';
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
    'ex_organizational_unit_parent_periods_no_overlap',
    'ex_position_reporting_lines_no_overlap',
    'uq_collaborator_identifiers_organization_code',
    'uq_organizational_positions_id_organization'
  );
  if v_n <> 6 then
    raise exception '[FAIL] constraints de F3-01/F3-03/F3-04 ausentes';
  end if;
  raise notice '[PASS] constraints temporais/uniques de F3-01/F3-03/F3-04 presentes';
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

delete from public.occupations
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborator_status_periods
where collaborator_id in (
  'f7b00000-0000-0000-0000-0000000000c1',
  'f7b00000-0000-0000-0000-0000000000c2',
  'f7b00000-0000-0000-0000-0000000000c3',
  'f7b00000-0000-0000-0000-0000000000c4',
  'f7b00000-0000-0000-0000-0000000000d1'
);

delete from public.position_reporting_lines
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_positions
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborators
where id in (
  'f7b00000-0000-0000-0000-0000000000c1',
  'f7b00000-0000-0000-0000-0000000000c2',
  'f7b00000-0000-0000-0000-0000000000c3',
  'f7b00000-0000-0000-0000-0000000000c4',
  'f7b00000-0000-0000-0000-0000000000d1'
);

delete from public.job_roles
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.occupations o
  where o.organization_id::text like 'f7a00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-05 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-05 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-05: todas as verificacoes passaram (schema, FKs, constraints, triggers, RLS).';
end $$;
