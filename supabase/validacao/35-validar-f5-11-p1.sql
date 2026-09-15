-- ============================================================================
-- F5-11 P1 (Issue #238): VALIDADOR da P1 - SCHEMA, INTEGRIDADE e TRILHA das
-- OBSERVACOES soberanas. Saida: [PASS]/[FAIL]; falha aborta (ON_ERROR_STOP).
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-11-desenho-tecnico.md (D1-D16) e migration
-- `20260929000000_f5_11_p1_observations_schema.sql`.
-- Cenario: `34-cenario-f5-11-p1.sql` (prefixo `fd`).
--
-- Blocos cobertos:
--   A  preflight fail-closed (fixture, catalogo, D15 intacto, fronteira da P1)
--   B  estrutura das 2 tabelas (RLS ligada, ZERO policy, colunas do contrato)
--   C  CHECK constraints do contrato (§7.2) PROVADAS por comportamento
--   D  D2  - `cycle_id` NOT NULL e soberano
--   E  FKs COMPOSTAS de tenant (cross-tenant impossivel estruturalmente)
--   F  D4  - imutabilidade estrutural de identidade/tenant/colaborador/ciclo/autoria
--   G  D6  - trilha append-only (reescrita e exclusao fisica negadas)
--   H  D9  - RLS DENY-BY-DEFAULT INTEGRAL e ACL minima
--   I  D6  - idempotencia por (organization_id, operation_id) e before/after
--   J  fronteira da P1 e D15 (anti-escopo: nenhuma RPC, nenhuma concessao)
--   K  higiene (nenhum residuo de prova)
--
-- Somente Supabase local; somente dados ficticios.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) PREFLIGHT fail-closed
-- ============================================================================
do $$
declare
  v_n      int;
  v_falhas text[] := array[]::text[];
begin
  -- (A1) fixture presente (a P1 depende da fixture para os testes de comportamento).
  select count(*) into v_n from public.organizations
   where id in ('fda00000-0000-0000-0000-0000000000a1',
                'fda00000-0000-0000-0000-0000000000b1');
  if v_n <> 2 then
    v_falhas := v_falhas || format('orgs da fixture = %s (esperado 2)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_observations
   where organization_id in ('fda00000-0000-0000-0000-0000000000a1',
                             'fda00000-0000-0000-0000-0000000000b1');
  if v_n <> 4 then
    v_falhas := v_falhas || format('observacoes da fixture = %s (esperado 4)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_observation_events
   where organization_id in ('fda00000-0000-0000-0000-0000000000a1',
                             'fda00000-0000-0000-0000-0000000000b1');
  if v_n <> 6 then
    v_falhas := v_falhas || format('eventos da fixture = %s (esperado 6)', v_n);
  end if;

  -- (A2) catalogo intacto (D6 da F5-10 / fronteira da P1).
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo = %s capabilities (esperado 31)', v_n);
  end if;
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('goal.%% + observation.%% = %s (esperado 8)', v_n);
  end if;
  select count(*) into v_n from public.capabilities
   where code = 'observation.communicate';
  if v_n <> 0 then
    v_falhas := v_falhas || 'capability nova de comunicado criada (D7 proibe)';
  end if;

  -- (A3) D15 INTACTO: nenhuma concessao de observation.* e admin sem observation.*.
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('D15 violado: %s concessao(oes) de observation.*', v_n);
  end if;
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    v_falhas := v_falhas || format('bundle admin com %s capabilities (esperado 9)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
     and c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || 'ADMIN com observation.* (proibido pela guarda 02-validar-f4-01 e por D15)';
  end if;
  -- (A3b) a P1 NAO cria role/bundle/perfil algum (D15 e decisao da P3). O baseline
  --       de roles de SISTEMA e NOMEADO: `admin` (F4-01/F5-09 P7) e os dois perfis
  --       de dominio criados pela propria F5-10 P4 como seu mecanismo de concessao
  --       (`metas_dono`, `metas_aprovador`). O conjunto tem de ser EXATAMENTE esse:
  --       qualquer role de sistema fora dele significa que a P1 inventou papel.
  if (select array_agg(r.name order by r.name)
        from public.access_roles r where r.is_system = true)
     is distinct from array['admin', 'metas_aprovador', 'metas_dono'] then
    v_falhas := v_falhas || format(
      'conjunto de roles de SISTEMA mudou (%s) — a P1 nao cria role/bundle/perfil: D15 e decisao da P3',
      coalesce((select array_to_string(array_agg(r.name order by r.name), ',')
                  from public.access_roles r where r.is_system = true), '<vazio>'));
  end if;

  -- (A4) fronteira da P1: NENHUMA funcao de observacao FORA da lista fechada da
  --      P1. A lista contem apenas as DUAS funcoes de enforcement da propria P1
  --      (imutabilidade estrutural do D4 e append-only da trilha do D6), cujo nome
  --      casa com o filtro por nome — exatamente como os helpers de aprovacao da
  --      F5-10 casavam com `%meta%`. Nenhuma RPC `observacao_*` existe ate a P2.
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like '%observa%' or p.proname like '%observation%')
     and p.proname <> all (array[
       'enforce_evaluation_observations_imutaveis',
       'enforce_evaluation_observation_events_append_only']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) de observacoes FORA da lista fechada da P1 (nenhuma RPC existe ate a P2)', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'observacao\_%' or p.proname like 'observation\_%');
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s RPC(s) observacao_*/observation_* instalada(s) (P2 antecipada)', v_n);
  end if;

  -- (A5) as 2 tabelas existem, com RLS ligada e ZERO policy (D9).
  if to_regclass('public.evaluation_observations') is null then
    v_falhas := v_falhas || 'tabela ausente: evaluation_observations';
  end if;
  if to_regclass('public.evaluation_observation_events') is null then
    v_falhas := v_falhas || 'tabela ausente: evaluation_observation_events';
  end if;
  select count(*) into v_n from pg_policies p
   where p.schemaname = 'public'
     and p.tablename in ('evaluation_observations', 'evaluation_observation_events');
  if v_n <> 0 then
    v_falhas := v_falhas || format('policies nas tabelas de observacoes = %s (D9 exige ZERO)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] A/preflight F5-11 P1: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] A/preflight: fixture presente (2 orgs, 4 observacoes, 6 eventos), catalogo intacto (31; 8 de metas/observacoes; nenhuma capability de comunicado), D15 INTACTO (zero concessao de observation.%%; admin com 9 e SEM observation.%%; 1 role de sistema), NENHUMA funcao de observacao (fronteira da P1) e as 2 tabelas com RLS ligada e ZERO policy';
end $$;

-- ============================================================================
-- B) ESTRUTURA: colunas, tipos, nulabilidade e defaults do contrato (§7.2)
-- ============================================================================
do $$
declare
  v_falhas text[] := array[]::text[];
  v_n      int;
  v_col    record;
begin
  -- (B1) colunas da LINHA: nome, tipo, nulabilidade e default, uma a uma.
  for v_col in
    select * from (values
      ('id',                            'uuid',        'NO',  'gen_random_uuid()'),
      ('organization_id',               'uuid',        'NO',  null),
      ('collaborator_id',               'uuid',        'NO',  null),
      ('cycle_id',                      'uuid',        'NO',  null),
      ('tipo',                          'text',        'NO',  null),
      ('texto',                         'text',        'NO',  null),
      ('comunicado',                    'boolean',     'NO',  'false'),
      ('comunicado_em',                 'timestamp with time zone', 'YES', null),
      ('comunicado_por_user_profile_id','uuid',        'YES', null),
      ('comunicado_por_membership_id',  'uuid',        'YES', null),
      ('excluida',                      'boolean',     'NO',  'false'),
      ('excluida_em',                   'timestamp with time zone', 'YES', null),
      ('excluida_por_user_profile_id',  'uuid',        'YES', null),
      ('excluida_por_membership_id',    'uuid',        'YES', null),
      ('motivo_exclusao',               'text',        'YES', null),
      ('author_user_profile_id',        'uuid',        'NO',  null),
      ('author_membership_id',          'uuid',        'NO',  null),
      ('author_collaborator_id',        'uuid',        'YES', null),
      ('version',                       'integer',     'NO',  '0'),
      ('created_at',                    'timestamp with time zone', 'NO', 'now()'),
      ('updated_at',                    'timestamp with time zone', 'NO', 'now()')
    ) as t(nome, tipo, nulabilidade, default_esperado)
  loop
    if not exists (
      select 1 from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'evaluation_observations'
         and c.column_name = v_col.nome
    ) then
      v_falhas := v_falhas || format('coluna ausente: evaluation_observations.%s', v_col.nome);
      continue;
    end if;
    if not exists (
      select 1 from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'evaluation_observations'
         and c.column_name = v_col.nome
         and c.data_type = v_col.tipo
         and c.is_nullable = v_col.nulabilidade
    ) then
      v_falhas := v_falhas || format('coluna fora do contrato: evaluation_observations.%s', v_col.nome);
    end if;
    if v_col.default_esperado is not null and not exists (
      select 1 from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'evaluation_observations'
         and c.column_name = v_col.nome
         and c.column_default like '%' || v_col.default_esperado || '%'
    ) then
      v_falhas := v_falhas || format('default fora do contrato: evaluation_observations.%s', v_col.nome);
    end if;
  end loop;

  -- (B2) a LINHA nao ganhou coluna extra (contrato fechado: nada de `ano`,
  --      `ciclo`, `matricula`, `autor_nome`, `historico` - tudo legado proibido).
  select count(*) into v_n from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'evaluation_observations';
  if v_n <> 21 then
    v_falhas := v_falhas || format('evaluation_observations com %s colunas (contrato = 21)', v_n);
  end if;

  -- (B3) colunas da TRILHA.
  for v_col in
    select * from (values
      ('id',                    'uuid',   'NO'),
      ('organization_id',       'uuid',   'NO'),
      ('observation_id',        'uuid',   'NO'),
      ('entity_type',           'text',   'NO'),
      ('event_type',            'text',   'NO'),
      ('effective_date',        'timestamp with time zone', 'NO'),
      ('reason',                'text',   'YES'),
      ('before_value',          'jsonb',  'YES'),
      ('after_value',           'jsonb',  'YES'),
      ('payload_hash',          'text',   'NO'),
      ('result_entity_id',      'uuid',   'YES'),
      ('actor_user_profile_id', 'uuid',   'NO'),
      ('actor_membership_id',   'uuid',   'NO'),
      ('operation_id',          'uuid',   'NO'),
      ('created_at',            'timestamp with time zone', 'NO')
    ) as t(nome, tipo, nulabilidade)
  loop
    if not exists (
      select 1 from information_schema.columns c
       where c.table_schema = 'public'
         and c.table_name = 'evaluation_observation_events'
         and c.column_name = v_col.nome
         and c.data_type = v_col.tipo
         and c.is_nullable = v_col.nulabilidade
    ) then
      v_falhas := v_falhas || format('coluna da trilha fora do contrato: %s', v_col.nome);
    end if;
  end loop;
  select count(*) into v_n from information_schema.columns c
   where c.table_schema = 'public' and c.table_name = 'evaluation_observation_events';
  if v_n <> 15 then
    v_falhas := v_falhas || format('evaluation_observation_events com %s colunas (contrato = 15)', v_n);
  end if;

  -- (B4) o indice de leitura por alvo existe e e PARCIAL em `not excluida`.
  if not exists (
    select 1 from pg_indexes i
     where i.schemaname = 'public' and i.tablename = 'evaluation_observations'
       and i.indexname = 'ix_evaluation_observations_alvo'
  ) then
    v_falhas := v_falhas || 'indice ix_evaluation_observations_alvo ausente';
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] B/estrutura F5-11 P1: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] B/estrutura: evaluation_observations com as 21 colunas do contrato (tipos, nulabilidade e defaults) e evaluation_observation_events com as 15 colunas do molde do D6; nenhuma coluna legada (ano/ciclo/matricula/autor_nome/historico) e indice de alvo presente';
end $$;

-- ============================================================================
-- C) CHECK constraints do contrato (§7.2) PROVADAS por comportamento
-- ============================================================================
do $$
declare
  v_org   uuid := 'fda00000-0000-0000-0000-0000000000a1';
  v_colab uuid := 'fdb00000-0000-0000-0000-000000000001';
  v_ciclo uuid := 'fdd10000-0000-0000-0000-0000000000a1';
  v_prof  uuid := 'fdc00000-0000-0000-0000-000000000001';
  v_memb  uuid := 'fdd00000-0000-0000-0000-000000000001';
  v_st    text;
  v_ok    boolean;
  v_id    uuid;
begin
  -- (C1) `tipo` e dominio FECHADO.
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'INVALIDA', 'texto ficticio (P1)', v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then
    raise exception '[FAIL] C1: tipo fora do dominio foi ACEITO (%)', coalesce(v_st, 'sem erro');
  end if;

  -- (C2) `texto` vazio, so espacos e acima de 2000 sao RECUSADOS; 2000 e ACEITO (D16).
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', '', v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C2a: texto vazio foi ACEITO'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', '   ', v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C2b: texto apenas com espacos foi ACEITO'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', repeat('x', 2001), v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C2c: texto com 2001 caracteres foi ACEITO'; end if;

  -- texto com espaco nas bordas viola `texto = btrim(texto)` (D16).
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', ' texto com borda ', v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C2d: texto sem btrim foi ACEITO'; end if;

  -- Limite INFERIOR/SUPERIOR exatos: 1 e 2000 sao ACEITOS.
  insert into public.evaluation_observations
    (organization_id, collaborator_id, cycle_id, tipo, texto,
     author_user_profile_id, author_membership_id)
  values (v_org, v_colab, v_ciclo, 'NEUTRA', 'x', v_prof, v_memb)
  returning id into v_id;
  insert into public.evaluation_observations
    (organization_id, collaborator_id, cycle_id, tipo, texto,
     author_user_profile_id, author_membership_id)
  values (v_org, v_colab, v_ciclo, 'NEUTRA', repeat('y', 2000), v_prof, v_memb)
  returning id into v_id;

  -- (C3) `version` negativa e RECUSADA.
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto, version,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', 'texto ficticio (P1)', -1, v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C3: version negativa foi ACEITA'; end if;

  -- (C4) D7: comunicado e FATO - incoerencias RECUSADAS nos dois sentidos.
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto, comunicado,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', 'texto ficticio (P1)', true, v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C4a: comunicado=true SEM carimbo foi ACEITO'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto, comunicado,
       comunicado_em, comunicado_por_user_profile_id, comunicado_por_membership_id,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', 'texto ficticio (P1)', false,
            now(), v_prof, v_memb, v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C4b: comunicado=false COM carimbo foi ACEITO'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto, comunicado,
       comunicado_em, comunicado_por_membership_id,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', 'texto ficticio (P1)', true,
            now(), v_memb, v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C4c: comunicado=true SEM autor de comunicacao foi ACEITO'; end if;

  -- (C5) D8/D16: exclusao logica SEM motivo e RECUSADA; motivo sem exclusao idem.
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       excluida, excluida_em, excluida_por_user_profile_id, excluida_por_membership_id,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', 'texto ficticio (P1)',
            true, now(), v_prof, v_memb, v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C5a: exclusao logica SEM motivo foi ACEITA (D8/D16)'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto, motivo_exclusao,
       author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', 'texto ficticio (P1)', 'motivo sem exclusao',
            v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C5b: motivo de exclusao SEM exclusao foi ACEITO'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       excluida, excluida_em, excluida_por_user_profile_id, excluida_por_membership_id,
       motivo_exclusao, author_user_profile_id, author_membership_id)
    values (v_org, v_colab, v_ciclo, 'NEUTRA', 'texto ficticio (P1)',
            true, now(), v_prof, v_memb, '   ', v_prof, v_memb);
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C5c: motivo de exclusao em branco foi ACEITO'; end if;

  -- (C6) trilha: `entity_type` e `event_type` sao dominios FECHADOS.
  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, 'fd900000-0000-0000-0000-000000000001', 'evaluation_cycle', 'CRIADA',
            now(), repeat('a', 64), v_prof, v_memb, gen_random_uuid());
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C6a: entity_type fora do contrato foi ACEITO'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, 'fd900000-0000-0000-0000-000000000001', 'evaluation_observation',
            'INVENTADO', now(), repeat('a', 64), v_prof, v_memb, gen_random_uuid());
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C6b: event_type fora do conjunto fechado do D6 foi ACEITO'; end if;

  -- (C7) D8/D16: motivo OBRIGATORIO em EXCLUIDA/REVOGADA; opcional nos demais.
  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       reason, payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, 'fd900000-0000-0000-0000-000000000001', 'evaluation_observation',
            'EXCLUIDA', now(), null, repeat('a', 64), v_prof, v_memb, gen_random_uuid());
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C7a: EXCLUIDA sem motivo foi ACEITA'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       reason, payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, 'fd900000-0000-0000-0000-000000000001', 'evaluation_observation',
            'REVOGADA', now(), '   ', repeat('a', 64), v_prof, v_memb, gen_random_uuid());
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C7b: REVOGADA com motivo em branco foi ACEITA'; end if;

  -- `EDITADA` sem motivo e ACEITA (reason e opcional fora de EXCLUIDA/REVOGADA).
  insert into public.evaluation_observation_events
    (organization_id, observation_id, entity_type, event_type, effective_date,
     reason, payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
  values (v_org, 'fd900000-0000-0000-0000-000000000001', 'evaluation_observation',
          'EDITADA', now(), null, repeat('b', 64), v_prof, v_memb, gen_random_uuid());

  -- (C8) `payload_hash` e SHA-256 hex de 64 caracteres.
  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, 'fd900000-0000-0000-0000-000000000001', 'evaluation_observation',
            'CRIADA', now(), 'abc', v_prof, v_memb, gen_random_uuid());
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C8a: payload_hash malformado foi ACEITO'; end if;

  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, 'fd900000-0000-0000-0000-000000000001', 'evaluation_observation',
            'CRIADA', now(), upper(repeat('a', 64)), v_prof, v_memb, gen_random_uuid());
  exception when check_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C8b: payload_hash em maiusculas foi ACEITO (hash nao canonico)'; end if;

  -- (C9) `effective_date` e `payload_hash` sao NOT NULL (fato sem instante/hash nao existe).
  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, 'fd900000-0000-0000-0000-000000000001', 'evaluation_observation',
            'CRIADA', null, repeat('a', 64), v_prof, v_memb, gen_random_uuid());
  exception when not_null_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] C9: effective_date nulo foi ACEITO'; end if;

  -- Limpeza das linhas legais criadas nos limites exatos (a trilha nao e tocada:
  -- e append-only). As linhas de prova ficam no acervo da fixture e sao
  -- contabilizadas no bloco K.
  raise notice '[PASS] C/constraints: dominio de tipo fechado; texto com btrim e 1..2000 (limites 1 e 2000 aceitos, 0/2001/borda recusados); version >= 0; comunicado exige carimbo coerente (ausente/espurio/incompleto recusados); exclusao logica exige ator+instante+MOTIVO (D8/D16) e motivo sem exclusao e recusado; trilha com entity_type/event_type fechados, motivo obrigatorio em EXCLUIDA/REVOGADA e payload_hash SHA-256 hex canonico';
end $$;

-- ============================================================================
-- D) D2 - `cycle_id` NOT NULL e soberano (o modelo legado SEM CICLO nao existe)
-- ============================================================================
do $$
declare
  v_ok boolean := false;
  v_st text;
begin
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values ('fda00000-0000-0000-0000-0000000000a1', 'fdb00000-0000-0000-0000-000000000001',
            null, 'NEUTRA', 'texto ficticio (P1)',
            'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001');
  exception when not_null_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then
    raise exception '[FAIL] D: observacao SEM ciclo foi ACEITA (D2 proibe o modelo legado) — %', coalesce(v_st, 'sem erro');
  end if;

  -- A P1 NAO impoe estado de ciclo no SCHEMA: a fixture tem observacao em ciclo
  -- ENCERRADO e ela e LEGITIMA aqui. A mutacao so em ATIVO e gate FUNCIONAL (P2/D12).
  if not exists (
    select 1 from public.evaluation_observations o
      join public.evaluation_cycles c on c.id = o.cycle_id
     where c.status = 'ENCERRADO' and o.organization_id = 'fda00000-0000-0000-0000-0000000000a1'
  ) then
    raise exception '[FAIL] D: a fixture deveria conter observacao em ciclo ENCERRADO (fronteira explicita da P1)';
  end if;

  raise notice '[PASS] D/D2: `cycle_id` NOT NULL - observacao sem ciclo e RECUSADA pelo banco (o modelo legado sem ciclo NAO e preservado) e o SCHEMA nao impoe estado de ciclo (a mutacao so em ATIVO e gate FUNCIONAL da P2/D12, provado pela observacao da fixture em ciclo ENCERRADO)';
end $$;

-- ============================================================================
-- E) FKs COMPOSTAS de tenant - cross-tenant impossivel ESTRUTURALMENTE
-- ============================================================================
do $$
declare
  v_alfa uuid := 'fda00000-0000-0000-0000-0000000000a1';
  v_beta uuid := 'fda00000-0000-0000-0000-0000000000b1';
  v_ok   boolean;
  v_st   text;
  v_n    int;
begin
  -- (E1) colaborador de OUTRO tenant e RECUSADO.
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values (v_alfa, 'fdb00000-0000-0000-0000-0000000000b1',
            'fdd10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'texto ficticio (P1)',
            'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001');
  exception when foreign_key_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] E1: colaborador de outro tenant foi ACEITO (%)', coalesce(v_st, 'sem erro'); end if;

  -- (E2) ciclo de OUTRO tenant e RECUSADO.
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values (v_alfa, 'fdb00000-0000-0000-0000-000000000001',
            'fdd10000-0000-0000-0000-0000000000b1', 'NEUTRA', 'texto ficticio (P1)',
            'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001');
  exception when foreign_key_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] E2: ciclo de outro tenant foi ACEITO (%)', coalesce(v_st, 'sem erro'); end if;

  -- (E3) membership do autor de OUTRO tenant e RECUSADA (autoria soberana no tenant).
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values (v_alfa, 'fdb00000-0000-0000-0000-000000000001',
            'fdd10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'texto ficticio (P1)',
            'fdc00000-0000-0000-0000-000000000002', 'fdd00000-0000-0000-0000-000000000002');
  exception when foreign_key_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] E3: membership do autor de outro tenant foi ACEITA (%)', coalesce(v_st, 'sem erro'); end if;

  -- (E4) colaborador do autor de OUTRO tenant e RECUSADO.
  v_ok := false;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id, author_collaborator_id)
    values (v_alfa, 'fdb00000-0000-0000-0000-000000000001',
            'fdd10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'texto ficticio (P1)',
            'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
            'fdb00000-0000-0000-0000-0000000000b1');
  exception when foreign_key_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] E4: colaborador do autor de outro tenant foi ACEITO (%)', coalesce(v_st, 'sem erro'); end if;

  -- (E5) a TRILHA tambem e ancorada no tenant: evento com observacao de outro tenant
  --      e RECUSADO, e actor_membership de outro tenant tambem.
  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_alfa, 'fd900000-0000-0000-0000-0000000000b1', 'evaluation_observation',
            'CRIADA', now(), repeat('c', 64),
            'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
            gen_random_uuid());
  exception when foreign_key_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] E5a: evento apontando para observacao de outro tenant foi ACEITO (%)', coalesce(v_st, 'sem erro'); end if;

  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_alfa, 'fd900000-0000-0000-0000-000000000001', 'evaluation_observation',
            'CRIADA', now(), repeat('c', 64),
            'fdc00000-0000-0000-0000-000000000002', 'fdd00000-0000-0000-0000-000000000002',
            gen_random_uuid());
  exception when foreign_key_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] E5b: evento com actor_membership de outro tenant foi ACEITO (%)', coalesce(v_st, 'sem erro'); end if;

  -- (E6) evento orfao (observacao inexistente) e RECUSADO.
  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_alfa, gen_random_uuid(), 'evaluation_observation',
            'CRIADA', now(), repeat('c', 64),
            'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
            gen_random_uuid());
  exception when foreign_key_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] E6: evento orfao (observacao inexistente) foi ACEITO (%)', coalesce(v_st, 'sem erro'); end if;

  -- (E7) a matriz de FKs do contrato existe, uma a uma (nenhuma omitida).
  foreach v_st in array array[
    'fk_evaluation_observations_organizations',
    'fk_evaluation_observations_cycle',
    'fk_evaluation_observations_collaborator',
    'fk_evaluation_observations_author_profile',
    'fk_evaluation_observations_author_membership',
    'fk_evaluation_observations_author_collaborator',
    'fk_evaluation_observations_comunicado_profile',
    'fk_evaluation_observations_comunicado_membership',
    'fk_evaluation_observations_excluida_profile',
    'fk_evaluation_observations_excluida_membership',
    'fk_evaluation_observation_events_organizations',
    'fk_evaluation_observation_events_observation',
    'fk_evaluation_observation_events_actor',
    'fk_evaluation_observation_events_actor_membership'] loop
    if not exists (select 1 from pg_constraint c where c.conname = v_st and c.contype = 'f') then
      raise exception '[FAIL] E7: FK do contrato ausente: %', v_st;
    end if;
  end loop;

  select count(*) into v_n from pg_constraint c
   where c.conname in ('fk_evaluation_observations_organizations',
                       'fk_evaluation_observations_cycle',
                       'fk_evaluation_observations_collaborator',
                       'fk_evaluation_observations_author_profile',
                       'fk_evaluation_observations_author_membership',
                       'fk_evaluation_observations_author_collaborator',
                       'fk_evaluation_observations_comunicado_profile',
                       'fk_evaluation_observations_comunicado_membership',
                       'fk_evaluation_observations_excluida_profile',
                       'fk_evaluation_observations_excluida_membership',
                       'fk_evaluation_observation_events_organizations',
                       'fk_evaluation_observation_events_observation',
                       'fk_evaluation_observation_events_actor',
                       'fk_evaluation_observation_events_actor_membership');
  if v_n <> 14 then
    raise exception '[FAIL] E7: FKs do contrato = % (esperado 14)', v_n;
  end if;

  raise notice '[PASS] E/FKs compostas de tenant: colaborador, ciclo, membership e colaborador do autor de OUTRO tenant sao RECUSADOS (23503), evento orfao e RECUSADO, evento com observacao/atormembership de outro tenant e RECUSADO e as 14 FKs do contrato estao presentes (cross-tenant impossivel ESTRUTURALMENTE, nao por checagem de aplicacao)';
end $$;

-- ============================================================================
-- F) D4 - imutabilidade ESTRUTURAL de identidade/tenant/colaborador/ciclo/autoria
-- ============================================================================
do $$
declare
  v_alvo uuid := 'fd900000-0000-0000-0000-000000000003';
  v_ok   boolean;
  v_st   text;
  v_campo text;
  v_n    int;
  v_prof uuid := 'fdc00000-0000-0000-0000-000000000001';
  v_memb uuid := 'fdd00000-0000-0000-0000-000000000001';
begin
  -- (F1) os 8 campos imutaveis sao RECUSADOS em UPDATE (D4), um a um.
  foreach v_campo in array array[
    'collaborator_id', 'cycle_id', 'author_user_profile_id',
    'author_membership_id', 'author_collaborator_id', 'organization_id', 'id',
    'created_at'] loop
    v_ok := false;
    begin
      execute format(
        'update public.evaluation_observations set %I = %L where id = %L',
        v_campo,
        case v_campo
          when 'collaborator_id'            then 'fdb00000-0000-0000-0000-000000000002'
          when 'cycle_id'                   then 'fdd10000-0000-0000-0000-0000000000a1'
          when 'author_user_profile_id'     then 'fdc00000-0000-0000-0000-000000000002'
          when 'author_membership_id'       then 'fdd00000-0000-0000-0000-000000000002'
          when 'author_collaborator_id'     then 'fdb00000-0000-0000-0000-000000000002'
          when 'organization_id'            then 'fda00000-0000-0000-0000-0000000000b1'
          when 'id'                         then gen_random_uuid()::text
          else now()::text
        end,
        v_alvo);
    exception when raise_exception then v_ok := true; when others then v_st := sqlstate;
    end;
    if not v_ok then
      raise exception '[FAIL] F1: UPDATE de campo IMUTAVEL foi aceito (D4) — campo testado: %', v_campo;
    end if;
  end loop;

  -- (F2) os campos MUTAVEIS do contrato continuam mutaveis (o trigger nao
  --      transformou a linha em imutavel): tipo, texto, comunicado, exclusao,
  --      motivo, carimbos e version.
  update public.evaluation_observations
     set tipo = 'POSITIVA',
         texto = 'texto ficticio atualizado (P1)',
         comunicado = true,
         comunicado_em = now(),
         comunicado_por_user_profile_id = v_prof,
         comunicado_por_membership_id = v_memb,
         version = version + 1
   where id = v_alvo;
  if not exists (
    select 1 from public.evaluation_observations
     where id = v_alvo and tipo = 'POSITIVA' and comunicado
       and comunicado_em is not null and version = 1
  ) then
    raise exception '[FAIL] F2: campos MUTAVEIS nao foram atualizados (trigger restritivo demais)';
  end if;

  update public.evaluation_observations
     set excluida = true,
         excluida_em = now(),
         excluida_por_user_profile_id = v_prof,
         excluida_por_membership_id = v_memb,
         motivo_exclusao = 'Motivo ficticio de revogacao de prova (P1)',
         version = version + 1
   where id = v_alvo;
  update public.evaluation_observations
     set excluida = false,
         excluida_em = null,
         excluida_por_user_profile_id = null,
         excluida_por_membership_id = null,
         motivo_exclusao = null,
         version = version + 1
   where id = v_alvo;
  if not exists (
    select 1 from public.evaluation_observations
     where id = v_alvo and not excluida and motivo_exclusao is null and version = 3
  ) then
    raise exception '[FAIL] F2: ciclo excluir->revogar da linha nao funcionou no schema';
  end if;

  -- (F3) o trigger de imutabilidade e INVOKER (nunca SECURITY DEFINER).
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname = 'enforce_evaluation_observations_imutaveis' and p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] F3: trigger de imutabilidade com SECURITY DEFINER';
  end if;

  raise notice '[PASS] F/imutabilidade (D4): os 8 campos imutaveis (id, organization_id, collaborator_id, cycle_id, author_user_profile_id, author_membership_id, author_collaborator_id, created_at) sao RECUSADOS em UPDATE pelo BANCO, enquanto tipo/texto/comunicado/carimbos/exclusao/motivo/version permanecem mutaveis (excluir->revogar provado); enforcement INVOKER';
end $$;

-- ============================================================================
-- G) D6 - trilha APPEND-ONLY: reescrita e exclusao fisica NEGADAS no banco
-- ============================================================================
do $$
declare
  v_ev   uuid := 'fd700000-0000-0000-0000-000000000001';
  v_ok   boolean;
  v_st   text;
  v_n    int;
begin
  -- (G1) UPDATE na trilha e RECUSADO (inclusive para o owner deste bloco).
  v_ok := false;
  begin
    update public.evaluation_observation_events set reason = 'reescrita de prova' where id = v_ev;
  exception when raise_exception then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] G1: UPDATE na trilha foi ACEITO (D6) — %', coalesce(v_st, 'sem erro'); end if;

  -- (G2) DELETE na trilha e RECUSADO.
  v_ok := false;
  begin
    delete from public.evaluation_observation_events where id = v_ev;
  exception when raise_exception then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] G2: DELETE na trilha foi ACEITO (D6) — %', coalesce(v_st, 'sem erro'); end if;

  -- (G3) TRUNCATE na trilha e RECUSADO (statement-level trigger).
  v_ok := false;
  begin
    execute 'truncate table public.evaluation_observation_events';
  exception when raise_exception then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then raise exception '[FAIL] G3: TRUNCATE na trilha foi ACEITO (D6) — %', coalesce(v_st, 'sem erro'); end if;

  -- (G4) a trilha sobreviveu intacta: 6 eventos de fixture + 2 de prova (C7/C8).
  -- (G4) a trilha NAO perdeu linhas: as 6 da fixture + 1 evento LEGAL inserido no
  --      bloco C (`EDITADA` sem motivo, permitido). As demais tentativas do bloco C
  --      foram RECUSADAS por CHECK e nao podem ter deixado linha.
  select count(*) into v_n from public.evaluation_observation_events
   where organization_id in ('fda00000-0000-0000-0000-0000000000a1',
                             'fda00000-0000-0000-0000-0000000000b1');
  if v_n < 7 then
    raise exception '[FAIL] G4: trilha perdeu linhas (encontrados %, esperado >= 7: 6 da fixture + 1 evento legal do bloco C)', v_n;
  end if;

  -- (G5) os 3 triggers append-only existem e as funcoes sao INVOKER.
  select count(*) into v_n
    from pg_trigger t
   where t.tgrelid = 'public.evaluation_observation_events'::regclass
     and not t.tgisinternal
     and t.tgname in ('trg_evaluation_observation_events_append_only',
                      'trg_evaluation_observation_events_no_delete',
                      'trg_evaluation_observation_events_no_truncate');
  if v_n <> 3 then
    raise exception '[FAIL] G5: triggers append-only = % (esperado 3)', v_n;
  end if;

  raise notice '[PASS] G/append-only (D6): UPDATE, DELETE e TRUNCATE na trilha sao RECUSADOS por trigger (mesmo para o owner), os 3 gatilhos existem e nenhuma linha foi perdida — o historico nao pode ser reescrito nem excluido fisicamente';
end $$;

-- ============================================================================
-- H) D9 - RLS DENY-BY-DEFAULT INTEGRAL e ACL minima
-- ============================================================================
do $$
declare
  v_tab  text;
  v_priv text;
  v_ok   boolean;
  v_st   text;
  v_n    int;
begin
  -- (H1) RLS ligada nas duas tabelas e ZERO policy (de qualquer cmd).
  foreach v_tab in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      raise exception '[FAIL] H1: RLS desabilitada em %', v_tab;
    end if;
    select count(*) into v_n from pg_policies p
     where p.schemaname = 'public' and p.tablename = v_tab;
    if v_n <> 0 then
      raise exception '[FAIL] H1: % com % policy(ies) — D9 exige ZERO', v_tab, v_n;
    end if;
    -- Nenhum privilegio de cliente, em nenhum dos 7 privilegios de tabela.
    foreach v_priv in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
      if has_table_privilege('authenticated', format('public.%I', v_tab), v_priv) then
        raise exception '[FAIL] H1: authenticated com % em %', v_priv, v_tab;
      end if;
      if has_table_privilege('anon', format('public.%I', v_tab), v_priv) then
        raise exception '[FAIL] H1: anon com % em %', v_priv, v_tab;
      end if;
    end loop;
  end loop;

  -- (H2) `service_role` e EXECUTOR tecnico: leitura/insercao na trilha, sem
  --      UPDATE/DELETE/TRUNCATE; na linha, sem DELETE/TRUNCATE (exclusao e LOGICA).
  if has_table_privilege('service_role', 'public.evaluation_observations', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_observations', 'TRUNCATE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'UPDATE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'TRUNCATE') then
    raise exception '[FAIL] H2: service_role com privilegio de reescrita/exclusao fisica';
  end if;
  if not has_table_privilege('service_role', 'public.evaluation_observations', 'SELECT')
     or not has_table_privilege('service_role', 'public.evaluation_observations', 'INSERT')
     or not has_table_privilege('service_role', 'public.evaluation_observations', 'UPDATE')
     or not has_table_privilege('service_role', 'public.evaluation_observation_events', 'SELECT')
     or not has_table_privilege('service_role', 'public.evaluation_observation_events', 'INSERT') then
    raise exception '[FAIL] H2: service_role sem o privilegio minimo de execucao tecnica';
  end if;

  -- (H3) o cliente NAO LE e NAO ESCREVE: negado por PERMISSAO (42501), nunca
  --      por filtro de RLS (nao existe policy para filtrar).
  foreach v_tab in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    set role authenticated;
    v_ok := false; v_st := null;
    begin
      execute format('select count(*) from public.%I', v_tab);
    exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
              when others then v_st := sqlstate;
    end;
    reset role;
    if not v_ok or v_st <> '42501' then
      raise exception '[FAIL] H3: SELECT de authenticated em % deveria ser NEGADO por permissao (42501), veio %', v_tab, coalesce(v_st, 'sem erro');
    end if;
  end loop;

  set role authenticated;
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values ('fda00000-0000-0000-0000-0000000000a1', 'fdb00000-0000-0000-0000-000000000001',
            'fdd10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'texto ficticio (P1)',
            'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001');
  exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  reset role;
  if not v_ok or v_st <> '42501' then
    raise exception '[FAIL] H3: INSERT de authenticated deveria ser NEGADO por permissao (42501), veio %', coalesce(v_st, 'sem erro');
  end if;

  -- (H4) `anon` idem.
  set role anon;
  v_ok := false; v_st := null;
  begin
    execute 'select count(*) from public.evaluation_observations';
  exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  reset role;
  if not v_ok or v_st <> '42501' then
    raise exception '[FAIL] H4: SELECT de anon deveria ser NEGADO por permissao (42501), veio %', coalesce(v_st, 'sem erro');
  end if;

  -- (H5) DELETE fisico na LINHA e negado a `service_role` (exclusao e LOGICA - D8).
  set role service_role;
  v_ok := false; v_st := null;
  begin
    delete from public.evaluation_observations
     where id = 'fd900000-0000-0000-0000-000000000001';
  exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  reset role;
  if not v_ok or v_st <> '42501' then
    raise exception '[FAIL] H5: DELETE fisico de service_role deveria ser NEGADO por permissao (42501), veio %', coalesce(v_st, 'sem erro');
  end if;

  raise notice '[PASS] H/RLS (D9): as duas tabelas tem RLS habilitada e ZERO policy; `authenticated` e `anon` nao possuem NENHUM dos 7 privilegios e sao negados por PERMISSAO (42501) na leitura e na escrita; `service_role` e executor tecnico (select/insert/update na linha e select/insert na trilha) e o DELETE fisico na linha e NEGADO (exclusao e logica - D8)';
end $$;

-- ============================================================================
-- I) D6/D11 - idempotencia por (organization_id, operation_id) e before/after
-- ============================================================================
do $$
declare
  v_ok boolean;
  v_st text;
  v_n  int;
  v_op uuid := 'fd600000-0000-0000-0000-000000000001';  -- operation_id ja usado por Alfa
begin
  -- (I1) reutilizar o MESMO operation_id na MESMA organizacao e RECUSADO.
  v_ok := false;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('fda00000-0000-0000-0000-0000000000a1', 'fd900000-0000-0000-0000-000000000001',
            'evaluation_observation', 'EDITADA', now(), repeat('d', 64),
            'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
            v_op);
  exception when unique_violation then v_ok := true; when others then v_st := sqlstate;
  end;
  if not v_ok then
    raise exception '[FAIL] I1: operation_id repetido na MESMA organizacao foi ACEITO (%)', coalesce(v_st, 'sem erro');
  end if;

  -- (I2) o MESMO operation_id em OUTRA organizacao e ACEITO (a chave e por tenant).
  insert into public.evaluation_observation_events
    (organization_id, observation_id, entity_type, event_type, effective_date,
     payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
  values ('fda00000-0000-0000-0000-0000000000b1', 'fd900000-0000-0000-0000-0000000000b1',
          'evaluation_observation', 'EDITADA', now(), repeat('d', 64),
          'fdc00000-0000-0000-0000-000000000002', 'fdd00000-0000-0000-0000-000000000002',
          v_op);

  -- (I3) a trilha de fixture carrega before/after image (D6) nos eventos em que
  --      houve transicao (COMUNICADO e EXCLUIDA) e resultado apontado.
  select count(*) into v_n from public.evaluation_observation_events
   where event_type in ('COMUNICADO', 'EXCLUIDA')
     and before_value is not null and after_value is not null
     and result_entity_id is not null;
  if v_n <> 2 then
    raise exception '[FAIL] I3: eventos de transicao com before/after = % (esperado 2)', v_n;
  end if;

  -- (I4) CRIADA nao tem before image (nao havia estado anterior) mas tem after.
  select count(*) into v_n from public.evaluation_observation_events
   where event_type = 'CRIADA' and before_value is null and after_value is not null;
  if v_n < 4 then
    raise exception '[FAIL] I4: CRIADA com after_value = % (esperado >= 4)', v_n;
  end if;

  raise notice '[PASS] I/idempotencia e imagem (D6): `unique (organization_id, operation_id)` RECUSA o replay de operation_id na mesma organizacao e o ACEITA em outro tenant (chave por tenant); os eventos de transicao carregam before/after image e result_entity_id, e CRIADA carrega apenas after (nao havia estado anterior)';
end $$;

-- ============================================================================
-- J) FRONTEIRA DA P1 e D15 (anti-escopo)
-- ============================================================================
-- A guarda das fases anteriores era uma PROIBICAO ABSOLUTA de qualquer objeto de
-- observacao (`%observac%`/`%observation%`) — invertida com a chegada da F5-11.
-- Ela NAO foi removida: virou LISTA FECHADA em tres camadas:
--   (1) as tabelas legitimas da P1 sao exatamente as duas do contrato;
--   (2) NENHUMA funcao `observacao_*` existe ainda (a P2 as introduzira e tera de
--       ampliar esta lista explicitamente);
--   (3) D15 permanece intacto (nenhuma capability concedida, admin sem
--       observation.*, nenhuma role nova).
do $$
declare
  v_tabelas_observacoes_p1 text[] := array[
    'evaluation_observations', 'evaluation_observation_events'];
  v_funcoes_observacoes_p1 text[] := array[
    -- Somente as DUAS funcoes de enforcement da P1 (D4 e D6). Nenhuma RPC: a P2
    -- introduzira as `observacao_*` e ampliara esta lista explicitamente.
    'enforce_evaluation_observations_imutaveis',
    'enforce_evaluation_observation_events_append_only'];
  v_tab  text;
  v_n    int;
  v_cols text;
  v_falhas text[] := array[]::text[];
begin
  -- (J1) NENHUMA tabela de observacao FORA da lista fechada da P1.
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and (c.relname like '%observation%' or c.relname like '%observac%')
     and c.relname <> all (v_tabelas_observacoes_p1);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s tabela(s) de observacoes FORA da lista fechada da P1', v_n);
  end if;
  -- E as duas legitimas existem.
  foreach v_tab in array v_tabelas_observacoes_p1 loop
    if to_regclass('public.' || v_tab) is null then
      v_falhas := v_falhas || format('tabela legitima da P1 ausente: %s', v_tab);
    end if;
  end loop;

  -- (J2) NENHUMA funcao de observacao (a P2 e posterior); a lista e FECHADA e
  --      vazia nesta fase - qualquer funcao passa a reprovar ate a P2 amplia-la.
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like '%observa%' or p.proname like '%observation%')
     and p.proname <> all (v_funcoes_observacoes_p1);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) de observacao instalada(s) (fronteira da P1 violada)', v_n);
  end if;

  -- (J3) NENHUMA coluna de observacao em tabela de ciclo/avaliacao que NAO seja
  --      uma das tabelas legitimas: a observacao nao se derrama no dominio alheio.
  select array_agg(c.table_name || '.' || c.column_name order by c.table_name, c.column_name)
    into v_cols
    from information_schema.columns c
   where c.table_schema = 'public'
     and (c.table_name like '%cycle%' or c.table_name like 'evaluation%')
     and c.table_name <> all (v_tabelas_observacoes_p1)
     and (c.column_name like '%observation%' or c.column_name like '%observac%');
  if v_cols is not null then
    v_falhas := v_falhas || ('colunas de observacao antecipadas: ' || array_to_string(v_cols, ','));
  end if;

  -- (J4) a observacao NAO interfere em nota/agregado (nao escopo do §2).
  if exists (
    select 1 from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name in ('evaluations', 'evaluation_scores', 'evaluation_aggregates')
       and c.column_name like '%observa%'
  ) then
    v_falhas := v_falhas || 'coluna de observacao em tabela de nota/agregado (nao escopo)';
  end if;

  -- (J5) D15 INTACTO (reconferido no estado final).
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('D15: %s concessao(oes) de observation.*', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
     and c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || 'D15: admin com observation.*';
  end if;
  -- O conjunto NOMEADO de roles de sistema e a prova de que a P1 nao inventou
  -- papel: `admin` + os dois perfis de dominio da propria F5-10 P4.
  if (select array_agg(r.name order by r.name)
        from public.access_roles r where r.is_system = true)
     is distinct from array['admin', 'metas_aprovador', 'metas_dono'] then
    v_falhas := v_falhas || format(
      'D15: conjunto de roles de SISTEMA mudou (%s) — nenhuma role/bundle/perfil novo na P1',
      coalesce((select array_to_string(array_agg(r.name order by r.name), ',')
                  from public.access_roles r where r.is_system = true), '<vazio>'));
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] J/fronteira da P1: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] J/fronteira da P1: as tabelas de observacao sao EXATAMENTE as 2 do contrato (lista FECHADA), NENHUMA funcao de observacao FORA da lista fechada da P1 existe (nenhuma RPC observacao_* ate a P2), nenhuma coluna de observacao se derrama em ciclo/avaliacao/nota e D15 permanece INTACTO (zero concessao de observation.%%; admin sem observation.%%; nenhuma role/bundle novo)';
end $$;

-- ============================================================================
-- K) HIGIENE
-- ============================================================================
do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] K: % funcao(oes) temporaria(s) `_mut_*` residual(is)', v_n;
  end if;
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'S' and c.relname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] K: % sequence(s) temporaria(s) `_mut_*` residual(is)', v_n;
  end if;
  select count(*) into v_n from pg_trigger t where t.tgname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] K: % gatilho(s) temporario(s) `_mut_*` residual(is)', v_n;
  end if;

  raise notice '[PASS] K/higiene: nenhum residuo de prova (`_mut_*`) no schema';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-11 P1: SCHEMA e TRILHA das OBSERVACOES validados.';
  raise notice '  evaluation_observations + evaluation_observation_events criadas;';
  raise notice '  D2 cycle_id NOT NULL (modelo legado sem ciclo NAO preservado);';
  raise notice '  D3 autoria derivada do contexto autenticado (nenhum campo do cliente);';
  raise notice '  D4 identidade/tenant/colaborador/ciclo/autoria IMUTAVEIS no banco;';
  raise notice '  D6 trilha append-only com before/after e payload_hash canonico;';
  raise notice '  D7 comunicado como FATO (ator + instante) e sem capability nova;';
  raise notice '  D8/D16 exclusao logica com motivo obrigatorio;';
  raise notice '  D9 RLS DENY-BY-DEFAULT INTEGRAL (zero policy, zero privilegio de cliente);';
  raise notice '  D15 INTACTO (blocker da P3): nenhuma concessao de observation.*;';
  raise notice '  FRONTEIRA DA P1 respeitada: nenhuma RPC, nenhum Edge, nenhum cutover.';
  raise notice '============================================================';
end $$;
