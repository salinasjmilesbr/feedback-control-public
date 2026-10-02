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
-- F6 / #429: o inventário EXATO de tabelas era válido quando a F3-05 era a última
-- fase entregue. Com as fases seguintes em `main`, `public` tem dezenas de
-- tabelas legítimas e o inventário corrente é guardado por `02-validar-f4-08.sql`.
-- A prova passa a exigir a PRESENÇA das tabelas esperadas: continua reprovando
-- remoção/renomeação, sem transformar a evolução legítima do schema em falha
-- (asserção estrutural stale atualizada — nenhuma prova material foi relaxada).

do $$
declare
  v_tabela text;
  v_tabelas text[] := array[
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
  ];
begin
  foreach v_tabela in array v_tabelas loop
    if not exists (
      select 1
      from pg_tables t
      where t.schemaname = 'public'
        and t.tablename = v_tabela
    ) then
      raise exception '[FAIL] tabela esperada da F3-05 ausente no schema public: %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] tabelas esperadas da F3-05 presentes (F2 + F3-01/02/03/04 + F3-05)';
end $$;

-- F6 / #429: das entidades "antecipadas" originais, `temporary_responsibilities`
-- (F3-06) e `evaluations`/`collegiate_*` (F3-08/F5) passaram a existir
-- legitimamente nas fases seguintes. Os nomes especulativos/legados continuam
-- PROIBIDOS (guardam contra tabela homônima/duplicada) e são verificados como
-- negação — preservando o que segue verificável.
do $$
declare
  v_intrusas text[];
begin
  select array_agg(t.tablename order by t.tablename)
    into v_intrusas
  from pg_tables t
  where t.schemaname = 'public'
    and t.tablename in (
      'substitutions', 'collegiates', 'evaluation_panels',
      'snapshots', 'dotted_lines'
    );
  if v_intrusas is not null then
    raise exception '[FAIL] tabela especulativa/homonima presente no schema public: %', v_intrusas;
  end if;
  raise notice '[PASS] nenhuma tabela especulativa/homonima (substitutions/collegiates/evaluation_panels/snapshots/dotted_lines)';
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
    'ex_occupations_position_no_overlap',
    'ex_occupations_collaborator_no_overlap'
  );
  if v_n <> 8 then
    raise exception '[FAIL] constraints esperadas de occupations ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] constraints pk/fk/check/exclusion esperadas presentes em occupations (posicao + cardinalidade por colaborador)';
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
-- 2) Cenário: ocupação, vacância, origem única por colaborador,
--    transferência, licença
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
  v_pos uuid;
begin
  -- Invariante #427: o colaborador tem NO MÁXIMO uma ocupação por instante.
  -- C1 (titular de P1 até 2025-06-30) tem origem única em 2025-03-01 — a
  -- antiga prova de "duas posições simultâneas" foi substituída por esta.
  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c1'
    and valid_from <= '2025-03-01T00:00:00Z'
    and (valid_to is null or valid_to > '2025-03-01T00:00:00Z');
  if v_n <> 1 then
    raise exception '[FAIL] C1 deveria ter exatamente 1 posicao em 2025-03-01 (encontrado %)', v_n;
  end if;

  select organizational_position_id into v_pos
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c1'
    and valid_from <= '2025-03-01T00:00:00Z'
    and (valid_to is null or valid_to > '2025-03-01T00:00:00Z');
  if v_pos is distinct from 'f7c00000-0000-0000-0000-0000000000a1' then
    raise exception '[FAIL] origem unica de C1 em 2025-03-01 deveria ser P1 (Gerente)';
  end if;
  raise notice '[PASS] colaborador tem origem unica por instante (C1 = P1 em 2025-03-01; sem acumulo de posicoes)';
end $$;

do $$
declare
  v_n int;
  v_ok boolean := false;
begin
  -- Duas occupations simultâneas do MESMO colaborador (C1 já ocupa P1 em
  -- 2025-01-01): devem ser recusadas pela exclusion por colaborador, e nada
  -- pode ser persistido.
  begin
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c1',
      'f7c00000-0000-0000-0000-0000000000a4',
      'Acumulo invalido de posicao',
      '2025-01-01T00:00:00Z', null
    );
  exception when exclusion_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] duas occupations simultaneas do mesmo colaborador NAO foram rejeitadas';
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c1'
    and organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a4';
  if v_n <> 0 then
    raise exception '[FAIL] insercao recusada nao deveria ter persistido occupation para C1';
  end if;
  raise notice '[PASS] no maximo uma occupation por colaborador por instante (exclusion por collaborator; nada persistido)';
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
  v_state text := null;
  v_msg text := null;
begin
  begin
    -- Segundo ocupante simultaneo na mesma posicao (P1 ja ocupada por C2 desde
    -- 2025-07-01). F6 / #427 — a linha e atribuida a C1, cuja UNICA ocupacao (P1)
    -- encerrou em 2025-06-30: em 2026-01-01 C1 NAO tem ocupacao vigente, logo a
    -- exclusion por `collaborator_id` NAO pode disparar. O UNICO veredito
    -- possivel e a exclusion por POSICAO — exatamente o discriminador desta
    -- prova (a cardinalidade por colaborador nao pode "roubar" o motivo aqui).
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c1',
      'f7c00000-0000-0000-0000-0000000000a1',
      'Segundo ocupante invalido',
      '2026-01-01T00:00:00Z', null
    );
  exception when exclusion_violation then
    v_state := sqlstate; v_msg := sqlerrm;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] dois ocupantes simultaneos na mesma posicao NAO foram rejeitados';
  end if;
  -- Discriminador explicito: a recusa TEM de vir da exclusion por POSICAO.
  if v_msg is null
     or position('ex_occupations_position_no_overlap' in v_msg) = 0 then
    raise exception '[FAIL] a recusa do segundo ocupante nao veio da exclusion por POSICAO (msg=%)', v_msg;
  end if;
  if v_state <> '23P01' then
    raise exception '[FAIL] recusa do segundo ocupante com SQLSTATE inesperado (%)', v_state;
  end if;
  raise notice '[PASS] um ocupante por posicao por instante (exclusion por POSICAO; C1 sem ocupacao vigente na janela)';
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
    -- F6 / #427 — JULGAMENTO: a linha é atribuída a C1, cuja única ocupação
    -- terminou exatamente em 2025-06-30. O período abaixo começa em 2025-07-01
    -- (consecutivo — a exclusion por `collaborator_id` não dispara) e P5 já está
    -- encerrada desde 2025-06-30: o único veredito possível é o trigger de
    -- validade da posição, exatamente o discriminador original.
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c1',
      'f7c00000-0000-0000-0000-0000000000a5',
      'Ocupacao alem do encerramento',
      '2025-07-01T00:00:00Z', null
    );
  exception when others then
    if sqlerrm not like '%encerramento da posicao%' then
      raise;
    end if;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] occupation aberta alem do encerramento da posicao NAO foi rejeitada';
  end if;
  raise notice '[PASS] occupation alem do encerramento da posicao rejeitada (trigger de validade)';
end $$;

-- F6 / #427: as duas provas de integridade cross-org abaixo precisam de um
-- colaborador de OUTRA organizacao que NAO tenha ocupacao alguma. O Cb (d1) da
-- fixture ocupa BP1 de forma aberta e a nova exclusion por `collaborator_id`
-- dispararia ANTES da FK composta, mascarando o veredito que estas provas
-- discriminam. d2 nasce SEM ocupacao (e sem periodo de status) apenas para isso.
do $$
begin
  insert into public.collaborators (id, organization_id) values
    ('f7b00000-0000-0000-0000-0000000000d2', 'f7a00000-0000-0000-0000-0000000000b1');
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    -- Cross-organization (collaborator de outra org): occupation Alfa com d2
    -- (Beta, SEM ocupacao), posicao vaga P4 (Alfa). O UNICO veredito possivel e a
    -- FK composta (collaborator_id, organization_id).
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000d2',
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
    -- P4 (Alfa) e colaborador d2 (Beta, SEM ocupacao) — o UNICO veredito
    -- possivel e a FK composta (organizational_position_id, organization_id).
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000b1',
      'f7b00000-0000-0000-0000-0000000000d2',
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
  v_state text := null;
begin
  begin
    -- Motivo vazio. F6 / #427 — a linha e atribuida a C1, cuja UNICA ocupacao
    -- (P1) encerrou em 2025-06-30: NAO ha ocupacao vigente em 2027-01-01, logo a
    -- exclusion por `collaborator_id` nao pode disputar o veredito. A posicao P4
    -- esta vaga. O UNICO veredito possivel e o check de `reason`, e o SQLSTATE e
    -- conferido explicitamente.
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c1',
      'f7c00000-0000-0000-0000-0000000000a4',
      '   ', '2027-01-01T00:00:00Z', null
    );
  exception when check_violation then
    v_state := sqlstate;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] reason vazio NAO foi rejeitado';
  end if;
  if v_state <> '23514' then
    raise exception '[FAIL] reason vazio nao foi rejeitado por check constraint (sqlstate=%)', v_state;
  end if;
  raise notice '[PASS] reason vazio/espacos rejeitado por check constraint';
end $$;

do $$
declare
  v_ok boolean := false;
  v_state text := null;
begin
  begin
    -- Periodo invalido (valid_to <= valid_from). F6 / #427: a janela é vazia
    -- (`[2027-01-01, 2027-01-01)`), portanto NÃO pode colidir com a exclusion por
    -- colaborador; o único veredito possível é o check de período.
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'f7a00000-0000-0000-0000-0000000000a1',
      'f7b00000-0000-0000-0000-0000000000c3',
      'f7c00000-0000-0000-0000-0000000000a4',
      'Periodo invalido',
      '2027-01-01T00:00:00Z', '2027-01-01T00:00:00Z'
    );
  exception when check_violation then
    v_state := sqlstate;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] occupation com periodo invalido NAO foi rejeitada';
  end if;
  if v_state <> '23514' then
    raise exception '[FAIL] periodo invalido nao foi rejeitado por check constraint (sqlstate=%)', v_state;
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
  v_id uuid;
  v_occ_id uuid;
begin
  -- Desligamento coerente: C4 (titular de P2) pode ser desligado após encerrar
  -- explicitamente sua occupation e o período active. Executa e reverte para
  -- manter o cenário intacto.
  select id into v_id
  from public.collaborator_status_periods
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c4'
    and status = 'active'
    and valid_to is null;

  select id into v_occ_id
  from public.occupations
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c4'
    and organizational_position_id = 'f7c00000-0000-0000-0000-0000000000a2'
    and valid_to is null;

  begin
    update public.occupations
       set valid_to = '2026-01-01T00:00:00Z'
     where id = v_occ_id;
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
    raise exception '[FAIL] desligamento apos fechamento explicito das occupations NAO foi permitido';
  end if;
  raise notice '[PASS] desligamento permitido apos fechamento explicito da occupation vigente do titular';

  -- Reverter: remove o periodo inactive, reabre o active e reabre a occupation.
  delete from public.collaborator_status_periods
  where collaborator_id = 'f7b00000-0000-0000-0000-0000000000c4'
    and status = 'inactive';
  update public.collaborator_status_periods
     set valid_to = null
   where id = v_id;
  update public.occupations
     set valid_to = null
   where id = v_occ_id;
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
-- 5) Negação efetiva ao cliente (ACL/RLS) em execução (como authenticated)
-- ============================================================================
-- ESTRUTURA corrente do deny em `occupations`: `authenticated` NÃO possui
-- privilégio de tabela (`revoke all on all tables ... from anon, authenticated`
-- em `20260908140000`, sem re-concessão) — por isso a negação de leitura vem da
-- ACL. Os blocos de runtime abaixo provam a NEGACAO EFETIVA ao cliente (ACL ou
-- RLS), sem afirmar qual mecanismo a produziu isoladamente; a estrutura é
-- verificada aqui e nas assertions de constraints/policies da seção 1.

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from (values ('occupations', false)) as e(tabela, esperado)
  where has_table_privilege('authenticated', ('public.' || e.tabela)::regclass, 'SELECT')
        is distinct from e.esperado;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated com privilegio de tabela em occupations (contrato de negacao alterado; exige policy own-tenant + atualizacao desta prova)';
  end if;
  raise notice '[PASS] estrutura de ACL: authenticated sem privilegio de tabela em occupations (deny corrente)';
end $$;

set role authenticated;

do $$
declare
  v_n int := 0;
begin
  -- F6 / #429: em `main` a negação de leitura de `occupations` a `authenticated`
  -- vem da AUSÊNCIA de GRANT (deny-by-default por privilégio), não mais de uma
  -- policy que filtra linhas. Ambos são fail-closed: aceita-se a negação por
  -- privilégio OU zero linhas (RLS).
  begin
    select count(*) into v_n from public.occupations;
  exception when insufficient_privilege then
    v_n := 0;
  end;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou linhas de occupations';
  end if;
  raise notice '[PASS] negacao efetiva ao cliente (ACL ou RLS): authenticated nao le linhas de occupations';
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
  v_n int := 0;
begin
  -- F6 / #429: negação por AUSÊNCIA de GRANT (privilégio) ou por RLS (0 linhas).
  begin
    update public.occupations set version = version + 1;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then
    v_n := 0;
  end;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu UPDATE de authenticated em occupations (%)', v_n;
  end if;
  raise notice '[PASS] negacao efetiva ao cliente (ACL ou RLS): UPDATE de authenticated em occupations nao afeta linhas';
end $$;

do $$
declare
  v_n int := 0;
begin
  -- F6 / #429: negação por AUSÊNCIA de GRANT (privilégio) ou por RLS (0 linhas).
  begin
    delete from public.occupations;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then
    v_n := 0;
  end;
  if v_n <> 0 then
    raise exception '[FAIL] RLS permitiu DELETE de authenticated em occupations (%)', v_n;
  end if;
  raise notice '[PASS] negacao efetiva ao cliente (ACL ou RLS): DELETE de authenticated em occupations nao afeta linhas';
end $$;

reset role;

-- ============================================================================
-- 6) F3-01/F3-02/F3-03/F3-04 permanecem intactas
-- ============================================================================

-- F6 / #429: as colunas esperadas da era F3-01/F3-03/F3-04 precisam de PRESENÇA
-- (reprova remoção/renomeação); colunas acrescentadas por fases posteriores são
-- legítimas e o inventário corrente é guardado por `02-validar-f4-08.sql`.
do $$
declare
  v_faltando text[];
begin
  select array_agg(e.c order by e.c) into v_faltando
  from unnest(array['created_at','id','organization_id','updated_at','version']) as e(c)
  where not exists (
    select 1 from information_schema.columns ic
    where ic.table_schema = 'public' and ic.table_name = 'collaborators'
      and ic.column_name = e.c);
  if v_faltando is not null then
    raise exception '[FAIL] collaborators (F3-01) perdeu colunas esperadas: %', v_faltando;
  end if;

  select array_agg(e.c order by e.c) into v_faltando
  from unnest(array['created_at','id','job_role_id','organization_id',
                    'seniority_level_id','unit_id','updated_at','valid_from',
                    'valid_to','version']) as e(c)
  where not exists (
    select 1 from information_schema.columns ic
    where ic.table_schema = 'public' and ic.table_name = 'organizational_positions'
      and ic.column_name = e.c);
  if v_faltando is not null then
    raise exception '[FAIL] organizational_positions (F3-03) perdeu colunas esperadas: %', v_faltando;
  end if;

  select array_agg(e.c order by e.c) into v_faltando
  from unnest(array['created_at','id','manager_position_id','organization_id',
                    'reason','subordinate_position_id','updated_at','valid_from',
                    'valid_to','version']) as e(c)
  where not exists (
    select 1 from information_schema.columns ic
    where ic.table_schema = 'public' and ic.table_name = 'position_reporting_lines'
      and ic.column_name = e.c);
  if v_faltando is not null then
    raise exception '[FAIL] position_reporting_lines (F3-04) perdeu colunas esperadas: %', v_faltando;
  end if;
  raise notice '[PASS] F3-01/F3-02/F3-03/F3-04 intactas (colunas esperadas presentes)';
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

-- F6 / #429: o total de policies cresceu legitimamente com F4-08/F5/F6; a prova
-- passa a exigir a PRESENÇA das 3 policies de identidade/sessão da F2 (mesmo
-- padrão de 02-validar-f4-02.sql), reprovando remoção sem reprovar evolução.
do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_policies p
  where p.schemaname = 'public'
    and p.policyname in (
      'organizations_select_via_membership',
      'user_profiles_select_own',
      'user_organization_memberships_select_own'
    );
  if v_n <> 3 then
    raise exception '[FAIL] policies de identidade/sessao da F2 ausentes (esperado 3, encontrado %)', v_n;
  end if;
  raise notice '[PASS] policies de identidade/sessao da F2 inalteradas (3 presentes)';
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
  'f7b00000-0000-0000-0000-0000000000d1',
  'f7b00000-0000-0000-0000-0000000000d2'
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
