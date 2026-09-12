-- ============================================================================
-- F5-09 P2: RPCs soberanas de gestao de ciclo — criar, editar, ativar, encerrar
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§6 T0–T3/T8/T9, §8 autorizacao,
-- §10 integridade, §11 concorrencia/idempotencia, §12 auditoria, §13.2 RPCs,
-- §13.3 reuso obrigatorio, §19 P2) e docs/F5-09-duvidas.md (D1–D28 ratificadas).
-- Pre-requisito: P1 (`20260915000000_f5_09_cycle_sovereign.sql`).
--
-- Entregue AQUI (e somente isto):
--   1) `ciclo_criar`   — T0: cria ciclo PLANEJADO do tenant do ator;
--   2) `ciclo_editar`  — T1: edita ciclo PLANEJADO (ano/numero/periodo);
--   3) `ciclo_ativar`  — T2: PLANEJADO -> ATIVO materializando a estrutura
--                        inicial (F3-08 + F3-09) na MESMA transacao;
--   4) `ciclo_encerrar`— T3: ATIVO -> ENCERRADO reusando
--                        `evaluation_fechar_ciclo_pendencias` (F5-06).
--
-- Fora do escopo (P3+), deliberadamente NAO implementado aqui: cancelar/reabrir/
-- corrigir periodo (P4), inclusao aditiva de nova admissao e helper de
-- elegibilidade da admissao (P3), policy de LEITURA para `authenticated` (P5),
-- Policy Engine cycle.read/manage (P6), Edge `ciclos` e reconciliacao do bundle
-- (P7), cutover do cliente (P8) e validacao integrada (P9). Nenhuma capability
-- nova, nenhum bundle alterado, nenhuma representacao nova de hierarquia.
--
-- Invariantes preservadas (D1–D28):
--   - PostgreSQL e a autoridade: nenhum dado do corpo decide tenant, autoria,
--     status, version, estrutura ou autorizacao;
--   - `organization_id` e o tenant do ATOR verificado; `auth.uid()` e a raiz de
--     identidade (recebida ja resolvida server-side, nunca do corpo);
--   - membership ativa + capability efetiva revalidadas no banco em TODA RPC
--     (`ciclo_ator_valido`, P1) — `service_role` executa, nunca decide;
--   - `cycle_events` e append-only (P1) e recebe UM evento por mutacao, na MESMA
--     transacao, com autoria soberana (`auth.uid()` + membership) e
--     `operation_id`/`payload_hash` para idempotencia;
--   - hierarquia e SEMPRE relacional (F3-04/F3-07/F3-08/F3-09); cargo, funcao ou
--     texto NUNCA determinam hierarquia;
--   - operacoes atomicas: falha parcial (inclusive dentro da materializacao ou do
--     fechamento F5-06) produz ROLLBACK TOTAL;
--   - concorrencia serializada pela chave normativa da familia de CICLOS
--     (`ciclo_lock_organizacao`, P1) + `expected_version` (CONFLICT);
--   - nenhum localStorage/legado se torna autoridade.
--
-- DESVIOS MINIMOS E EXPLICITOS em relacao ao §13.2 (documentados para auditoria):
--   (a) `p_payload_hash` NAO e parametro das RPCs. O §13.2 listava esse parametro,
--       mas o §11/§12 definem o hash como o do PAYLOAD CANONICO DA INTENCAO e o
--       padrao soberano ja existente no projeto (F5-06/F5-07/F5-08) DERIVA o hash
--       dos parametros ja validados e nunca o aceita do cliente — aceita-lo
--       permitiria replay com hash forjado. O hash continua gravado em
--       `cycle_events.payload_hash` (SHA-256 hex do payload canonico derivado
--       server-side), preservando `unique (organization_id, operation_id)`.
--   (b) `ciclo_encerrar` incrementa `version` UMA vez. `evaluation_fechar_ciclo_
--       pendencias` (F5-06) ja incrementa `evaluation_cycles.version` ao gravar as
--       pendencias; o encerramento NAO incrementa de novo, mantendo a convencao
--       "uma operacao oficial = um incremento" (resultado = expected_version + 1).
--   (c) `ciclo_ativar` usa como `reference_date` o INSTANTE da ativacao (o
--       parametro da F3-08 e `timestamptz`); o §6/T2 escrevia `data_ativacao::date`
--       — o instante e o mesmo dia e e o valor exato que "vigente no instante da
--       ativacao" exige (§7.1/D17), sem ambiguidade intradiaria.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
-- A P2 depende de primitivas da P1 e dos contratos F3-08/F3-09/F5-06. Se o
-- baseline nao for exatamente o esperado, a migration ABORTA (nada e acomodado).
do $$
declare
  v_faltando text[] := array[]::text[];
  v_fn       text;
  v_prims    text[] := array[
    'ciclo_ator_valido(uuid, uuid, text)',
    'ciclo_lock_organizacao(uuid)',
    'materializar_colegiado_ciclo(uuid, integer, integer, timestamp with time zone, uuid[])',
    'materializar_responsabilidades_avaliacao(uuid, integer, integer)',
    'evaluation_fechar_ciclo_pendencias(uuid, uuid, uuid)',
    'evaluation_config_bootstrap(uuid, uuid)',
    'evaluation_ator_valido(uuid, uuid)',
    'evaluation_criar(uuid, uuid, uuid, uuid)'];
begin
  -- P1: integridade de evaluation_cycles
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_faltando := v_faltando || 'I5 (uq_evaluation_cycles_org_ativo)';
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_cycles'::regclass
       and conname = 'ex_evaluation_cycles_periodo_no_overlap' and contype = 'x'
  ) then
    v_faltando := v_faltando || 'I6 (ex_evaluation_cycles_periodo_no_overlap)';
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_cycles'::regclass
       and conname = 'uq_evaluation_cycles_org_ano_numero' and contype = 'u'
  ) then
    v_faltando := v_faltando || 'I3 (uq_evaluation_cycles_org_ano_numero)';
  end if;

  -- P1: trilha append-only completa (UPDATE/DELETE/TRUNCATE) + idempotencia
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.cycle_events'::regclass
       and conname = 'uq_cycle_events_org_operation' and contype = 'u'
  ) then
    v_faltando := v_faltando || 'cycle_events.uq_cycle_events_org_operation';
  end if;
  foreach v_fn in array array[
    'trg_cycle_events_append_only', 'trg_cycle_events_no_delete',
    'trg_cycle_events_no_truncate']
  loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = 'public.cycle_events'::regclass
         and tgname = v_fn and not tgisinternal
    ) then
      v_faltando := v_faltando || ('trigger ' || v_fn);
    end if;
  end loop;

  -- Primitivas reutilizadas: existem e sao executaveis pelo caminho server-side.
  foreach v_fn in array v_prims loop
    if to_regprocedure('public.' || v_fn) is null then
      v_faltando := v_faltando || ('funcao ' || v_fn);
    elsif has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_faltando := v_faltando || ('EXECUTE de service_role em ' || v_fn);
    end if;
  end loop;

  -- Fonte soberana da populacao inicial (F3-01/F5-07).
  if to_regclass('public.collaborator_status_periods') is null then
    v_faltando := v_faltando || 'collaborator_status_periods';
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception
      'F5_09_P2_INCOMPATIBLE_BASELINE: baseline incompativel com o contrato da P2: %',
      array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-09 P2: preflight OK (P1 + primitivas F3-08/F3-09/F5-06 disponiveis)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) `ciclo_criar` — T0 (D21: operacao ADMINISTRATIVA, capability cycle.manage)
-- ----------------------------------------------------------------------------
-- Idempotente por `(organization_id, operation_id)` + hash canonico; cria SEMPRE
-- em `PLANEJADO` com `version = 0`; resolve a versao de configuracao pelo
-- bootstrap soberano (D19) e grava o evento `CRIADO` na mesma transacao.
create or replace function public.ciclo_criar(
  p_organization_id uuid,
  p_ano integer,
  p_numero integer,
  p_data_inicio date,
  p_data_fim date,
  p_actor_user_profile_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org        uuid := p_organization_id;
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_id         uuid;
  v_config     uuid;
  v_instante   timestamptz := now();
begin
  -- (1) Forma do payload — nada aqui e autoridade.
  if p_organization_id is null or p_actor_user_profile_id is null
     or p_operation_id is null then
    raise exception 'F5_09_INVALID_INPUT: organization_id, ator e operation_id obrigatorios';
  end if;
  if p_ano is null or p_ano < 2000 or p_ano > 2100 then
    raise exception 'F5_09_INVALID_INPUT: ano deve estar entre 2000 e 2100';
  end if;
  if p_numero is null or p_numero not in (1, 2, 3) then
    raise exception 'F5_09_INVALID_INPUT: numero do ciclo deve ser 1, 2 ou 3';
  end if;
  -- I4/D4: a F5-09 exige periodo explicito (o CHECK da F5-06 admite nulos para o
  -- ciclo "minimo"; a exigencia vive na RPC, sem alterar o CHECK da F5-06).
  if p_data_inicio is null or p_data_fim is null then
    raise exception 'F5_09_INVALID_INPUT: data_inicio e data_fim obrigatorias';
  end if;
  if p_data_fim < p_data_inicio then
    raise exception 'F5_09_INVALID_INPUT: data_fim nao pode ser anterior a data_inicio';
  end if;

  -- (2) Hash canonico da INTENCAO (derivado server-side — desvio (a) do header).
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'ciclo_criar',
    'organization_id', v_org,
    'ano', p_ano,
    'numero', p_numero,
    'data_inicio', p_data_inicio,
    'data_fim', p_data_fim
  )::text, 'UTF8')), 'hex');

  -- (3) Ator + tenant + capability efetiva (D20/D21/D23), na mesma transacao.
  if not public.ciclo_ator_valido(p_actor_user_profile_id, v_org, 'cycle.manage') then
    raise exception 'F5_09_FORBIDDEN: ator sem perfil/membership ativa e capability cycle.manage na organizacao';
  end if;

  -- (4) Idempotencia — caminho rapido (revalidado sob o lock em (7)).
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status');
  end if;

  -- (5) Membership do ator (autoria soberana da trilha — §12/D23).
  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_09_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (6) Serializacao da familia de CICLOS por organizacao (§11).
  perform public.ciclo_lock_organizacao(v_org);

  -- (7) Idempotencia sob o lock: retry concorrente identico devolve o MESMO
  --     resultado em vez de colidir nas constraints.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status');
  end if;

  -- (8) Pre-checagens de negocio (as constraints I3/I5/I6 da P1 sao a ULTIMA
  --     barreira; aqui a mensagem fica estavel).
  if exists (
    select 1 from public.evaluation_cycles c
     where c.organization_id = v_org and c.ano = p_ano and c.numero = p_numero
  ) then
    raise exception 'F5_09_CONFLICT: ja existe ciclo para o ano/numero nesta organizacao';
  end if;
  if exists (
    select 1 from public.evaluation_cycles c
     where c.organization_id = v_org
       and c.status <> 'CANCELADO'
       and c.data_inicio is not null and c.data_fim is not null
       and daterange(c.data_inicio, c.data_fim + 1, '[)')
           && daterange(p_data_inicio, p_data_fim + 1, '[)')
  ) then
    raise exception 'F5_09_CONFLICT: periodo sobreposto a ciclo nao cancelado da organizacao';
  end if;

  -- (9) Versao de configuracao SOBERANA (D19) — resolvida pelo bootstrap
  --     existente, nunca informada pelo cliente.
  v_config := public.evaluation_config_bootstrap(v_org, p_actor_user_profile_id);
  if v_config is null then
    raise exception 'F5_09_INTERNAL: bootstrap de configuracao nao retornou versao';
  end if;

  -- (10) Criacao: PLANEJADO, version 0, identidade UUID soberana.
  insert into public.evaluation_cycles (
    organization_id, ano, numero, status, data_inicio, data_fim,
    config_version_id, version
  ) values (
    v_org, p_ano, p_numero, 'PLANEJADO', p_data_inicio, p_data_fim, v_config, 0
  )
  returning id into v_id;

  -- (11) Trilha append-only na MESMA transacao (§12/D12).
  insert into public.cycle_events (
    organization_id, cycle_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, v_id, 'evaluation_cycle', 'CRIADO', v_instante,
    'Criacao de ciclo (PLANEJADO)',
    null,
    jsonb_build_object(
      'status', 'PLANEJADO', 'ano', p_ano, 'numero', p_numero,
      'data_inicio', p_data_inicio, 'data_fim', p_data_fim,
      'config_version_id', v_config, 'version', 0),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object('cycle_id', v_id, 'version', 0, 'status', 'PLANEJADO');
end;
$$;

comment on function public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid) is
  'F5-09 P2 (T0/D21/D19): cria ciclo PLANEJADO do tenant do ator verificado, com '
  'capability efetiva cycle.manage, periodo explicito, version=0 e versao de '
  'configuracao do bootstrap soberano. Idempotente por (organization_id, '
  'operation_id) + hash canonico da intencao; evento CRIADO na mesma transacao. '
  'Nunca aceita tenant, autoria, status, version ou estrutura do corpo.';

-- ----------------------------------------------------------------------------
-- 2) `ciclo_editar` — T1 (somente PLANEJADO)
-- ----------------------------------------------------------------------------
-- Edicao NORMAL (ano/numero/periodo) com `expected_version`. NAO altera
-- `status` (ativar/encerrar/cancelar/reabrir/corrigir periodo sao operacoes de
-- dominio proprias) e NAO aceita `config_version_id` do cliente (D19).
create or replace function public.ciclo_editar(
  p_cycle_id uuid,
  p_organization_id uuid,
  p_ano integer,
  p_numero integer,
  p_data_inicio date,
  p_data_fim date,
  p_expected_version integer,
  p_actor_user_profile_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_ciclo       record;
  v_nova_versao integer;
  v_instante    timestamptz := now();
begin
  if p_cycle_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_09_INVALID_INPUT: cycle_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_09_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_ano is null or p_ano < 2000 or p_ano > 2100 then
    raise exception 'F5_09_INVALID_INPUT: ano deve estar entre 2000 e 2100';
  end if;
  if p_numero is null or p_numero not in (1, 2, 3) then
    raise exception 'F5_09_INVALID_INPUT: numero do ciclo deve ser 1, 2 ou 3';
  end if;
  if p_data_inicio is null or p_data_fim is null then
    raise exception 'F5_09_INVALID_INPUT: data_inicio e data_fim obrigatorias';
  end if;
  if p_data_fim < p_data_inicio then
    raise exception 'F5_09_INVALID_INPUT: data_fim nao pode ser anterior a data_inicio';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'ciclo_editar',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'ano', p_ano,
    'numero', p_numero,
    'data_inicio', p_data_inicio,
    'data_fim', p_data_fim,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.ciclo_ator_valido(p_actor_user_profile_id, v_org, 'cycle.manage') then
    raise exception 'F5_09_FORBIDDEN: ator sem perfil/membership ativa e capability cycle.manage na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status');
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_09_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform public.ciclo_lock_organizacao(v_org);

  -- Replay concorrente identico (mesmo operation_id + mesmo hash).
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status');
  end if;

  -- Resolucao por (id, organization_id): cross-tenant e NOT_FOUND (D16/I16).
  select c.id, c.ano, c.numero, c.status, c.data_inicio, c.data_fim, c.version
    into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_09_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- T1: edicao normal SOMENTE em PLANEJADO (as demais transicoes sao proprias).
  if v_ciclo.status <> 'PLANEJADO' then
    raise exception 'F5_09_CONFLICT: edicao comum exige ciclo PLANEJADO (status atual %)',
      v_ciclo.status;
  end if;
  if v_ciclo.version <> p_expected_version then
    raise exception 'F5_09_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- I3/I6 da P1 sao a ultima barreira; aqui as mensagens ficam estaveis.
  if exists (
    select 1 from public.evaluation_cycles c
     where c.organization_id = v_org
       and c.ano = p_ano and c.numero = p_numero
       and c.id <> p_cycle_id
  ) then
    raise exception 'F5_09_CONFLICT: ja existe ciclo para o ano/numero nesta organizacao';
  end if;
  if exists (
    select 1 from public.evaluation_cycles c
     where c.organization_id = v_org
       and c.id <> p_cycle_id
       and c.status <> 'CANCELADO'
       and c.data_inicio is not null and c.data_fim is not null
       and daterange(c.data_inicio, c.data_fim + 1, '[)')
           && daterange(p_data_inicio, p_data_fim + 1, '[)')
  ) then
    raise exception 'F5_09_CONFLICT: periodo sobreposto a ciclo nao cancelado da organizacao';
  end if;

  update public.evaluation_cycles
     set ano = p_ano,
         numero = p_numero,
         data_inicio = p_data_inicio,
         data_fim = p_data_fim,
         version = version + 1
   where id = p_cycle_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.cycle_events (
    organization_id, cycle_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_cycle_id, 'evaluation_cycle', 'EDITADO', v_instante,
    'Edicao de ciclo PLANEJADO',
    jsonb_build_object(
      'status', v_ciclo.status, 'ano', v_ciclo.ano, 'numero', v_ciclo.numero,
      'data_inicio', v_ciclo.data_inicio, 'data_fim', v_ciclo.data_fim,
      'version', v_ciclo.version),
    jsonb_build_object(
      'status', 'PLANEJADO', 'ano', p_ano, 'numero', p_numero,
      'data_inicio', p_data_inicio, 'data_fim', p_data_fim,
      'version', v_nova_versao),
    v_hash, p_cycle_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'cycle_id', p_cycle_id, 'version', v_nova_versao, 'status', 'PLANEJADO');
end;
$$;

comment on function public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid) is
  'F5-09 P2 (T1): edita ciclo PLANEJADO (ano/numero/periodo) com '
  'expected_version, unicidade (I3) e nao sobreposicao (I6) revalidadas. Nao '
  'altera status e nao aceita config_version_id do cliente (D19). Idempotente por '
  'operation_id + hash canonico; evento EDITADO com before/after normalizados.';

-- ----------------------------------------------------------------------------
-- 3) `ciclo_ativar` — T2 (PLANEJADO -> ATIVO) + materializacao inicial
-- ----------------------------------------------------------------------------
-- A estrutura inicial e materializada pela F3-08 (snapshot de colegiado da
-- populacao elegivel) e pela F3-09 (responsabilidades de avaliacao), AMBAS
-- idempotentes e na MESMA transacao: falha em qualquer parte => ROLLBACK TOTAL
-- (o ciclo permanece PLANEJADO, sem snapshot).
--
-- Populacao elegivel (D26/D27): colaboradores do tenant com status `active`
-- vigente no INSTANTE da ativacao (`collaborator_status_periods`, meio-aberto).
-- Nenhuma inferencia por cargo/texto/payload; a identidade e o UUID. Quem for
-- admitido DEPOIS da ativacao e assunto da P3 (`ciclo_incluir_admissao`).
create or replace function public.ciclo_ativar(
  p_cycle_id uuid,
  p_organization_id uuid,
  p_expected_version integer,
  p_actor_user_profile_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org          uuid := p_organization_id;
  v_hash         text;
  v_evento       record;
  v_membership   uuid;
  v_ciclo        record;
  v_populacao    uuid[];
  v_qtd_pop      integer;
  v_qtd_snap     integer;
  v_qtd_resp     integer;
  v_nova_versao  integer;
  v_instante     timestamptz := now();
begin
  if p_cycle_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_09_INVALID_INPUT: cycle_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_09_INVALID_INPUT: expected_version obrigatorio';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'ciclo_ativar',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.ciclo_ator_valido(p_actor_user_profile_id, v_org, 'cycle.manage') then
    raise exception 'F5_09_FORBIDDEN: ator sem perfil/membership ativa e capability cycle.manage na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status',
      'snapshot_materializado', coalesce((v_evento.after_value->>'snapshot_materializado')::integer, 0),
      'responsabilidades_materializadas', coalesce((v_evento.after_value->>'responsabilidades_materializadas')::integer, 0));
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_09_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform public.ciclo_lock_organizacao(v_org);

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status',
      'snapshot_materializado', coalesce((v_evento.after_value->>'snapshot_materializado')::integer, 0),
      'responsabilidades_materializadas', coalesce((v_evento.after_value->>'responsabilidades_materializadas')::integer, 0));
  end if;

  select c.id, c.ano, c.numero, c.status, c.data_inicio, c.data_fim,
         c.version, c.config_version_id
    into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_09_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- T2: somente PLANEJADO -> ATIVO.
  if v_ciclo.status <> 'PLANEJADO' then
    raise exception 'F5_09_CONFLICT: ativacao exige ciclo PLANEJADO (status atual %)',
      v_ciclo.status;
  end if;
  if v_ciclo.version <> p_expected_version then
    raise exception 'F5_09_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;
  -- I9/D19: a versao de configuracao do ciclo e obrigatoria na ativacao.
  if v_ciclo.config_version_id is null then
    raise exception 'F5_09_CONFLICT: ciclo sem versao de configuracao soberana (D19)';
  end if;
  -- I4: periodo explicito (fail-closed antes de qualquer escrita).
  if v_ciclo.data_inicio is null or v_ciclo.data_fim is null then
    raise exception 'F5_09_CONFLICT: ciclo sem periodo definido nao pode ser ativado';
  end if;
  -- I5/D14: um unico ATIVO por organizacao (indice parcial da P1 e a barreira).
  if exists (
    select 1 from public.evaluation_cycles c
     where c.organization_id = v_org
       and c.id <> p_cycle_id
       and c.status = 'ATIVO'
  ) then
    raise exception 'F5_09_CONFLICT: ja existe ciclo ATIVO nesta organizacao';
  end if;
  -- I6/D15: a nao sobreposicao de periodos e garantida pela exclusion da P1 em
  -- TODA escrita (inclusive nesta linha); nada a recalcular aqui.

  -- Populacao elegivel: status `active` vigente no instante da ativacao.
  select array_agg(c.id order by c.id)
    into v_populacao
    from public.collaborators c
   where c.organization_id = v_org
     and exists (
       select 1
         from public.collaborator_status_periods sp
        where sp.collaborator_id = c.id
          and sp.status = 'active'
          and sp.valid_from <= v_instante
          and (sp.valid_to is null or sp.valid_to > v_instante)
     );
  v_populacao := coalesce(v_populacao, array[]::uuid[]);
  v_qtd_pop := coalesce(array_length(v_populacao, 1), 0);

  -- Materializacao inicial da ESTRUTURA do ciclo (F3-08 + F3-09), na MESMA
  -- transacao. Ambas sao idempotentes e nunca sobrescrevem snapshot existente.
  perform public.materializar_colegiado_ciclo(
    v_org, v_ciclo.ano, v_ciclo.numero, v_instante, v_populacao);
  perform public.materializar_responsabilidades_avaliacao(
    v_org, v_ciclo.ano, v_ciclo.numero);

  select count(*) into v_qtd_snap
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org
     and s.ano = v_ciclo.ano
     and s.ciclo = v_ciclo.numero;
  select count(*) into v_qtd_resp
    from public.cycle_evaluation_responsibilities r
    join public.collegiate_cycle_snapshots s
      on s.id = r.snapshot_id
   where s.organization_id = v_org
     and s.ano = v_ciclo.ano
     and s.ciclo = v_ciclo.numero;

  update public.evaluation_cycles
     set status = 'ATIVO',
         data_ativacao = v_instante,
         version = version + 1
   where id = p_cycle_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.cycle_events (
    organization_id, cycle_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_cycle_id, 'evaluation_cycle', 'ATIVADO', v_instante,
    'Ativacao de ciclo com materializacao inicial da estrutura',
    jsonb_build_object(
      'status', v_ciclo.status, 'ano', v_ciclo.ano, 'numero', v_ciclo.numero,
      'data_inicio', v_ciclo.data_inicio, 'data_fim', v_ciclo.data_fim,
      'version', v_ciclo.version),
    jsonb_build_object(
      'status', 'ATIVO', 'data_ativacao', v_instante,
      'colaboradores_elegiveis', v_qtd_pop,
      'snapshot_materializado', v_qtd_snap,
      'responsabilidades_materializadas', v_qtd_resp,
      'version', v_nova_versao),
    v_hash, p_cycle_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'cycle_id', p_cycle_id,
    'version', v_nova_versao,
    'status', 'ATIVO',
    'snapshot_materializado', v_qtd_snap,
    'responsabilidades_materializadas', v_qtd_resp);
end;
$$;

comment on function public.ciclo_ativar(uuid, uuid, integer, uuid, uuid) is
  'F5-09 P2 (T2/D14/D15/D17/D19): ativa ciclo PLANEJADO, materializando na MESMA '
  'transacao o snapshot de colegiado da populacao elegivel (F3-08, status active '
  'vigente no instante) e as responsabilidades de avaliacao (F3-09). Exige '
  'expected_version e versao de configuracao soberana; respeita um unico ATIVO por '
  'organizacao e a exclusion de periodos da P1. Falha parcial => rollback total. '
  'Nao implementa admissao posterior (P3).';

-- ----------------------------------------------------------------------------
-- 4) `ciclo_encerrar` — T3 (ATIVO -> ENCERRADO) reusando a F5-06
-- ----------------------------------------------------------------------------
-- O fechamento de pendencias e o da F5-06 (`evaluation_fechar_ciclo_pendencias`),
-- reusado sem duplicar logica: ele marca pendencias PERMANENTES nas avaliacoes
-- incompletas e grava `encerrado_com_pendencias`/`quantidade_pendencias`/`version`
-- no ciclo. Este RPC apenas muda `status`/`data_encerramento` na mesma transacao
-- e NAO incrementa `version` de novo (desvio (b) do header).
create or replace function public.ciclo_encerrar(
  p_cycle_id uuid,
  p_organization_id uuid,
  p_motivo text,
  p_expected_version integer,
  p_actor_user_profile_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org           uuid := p_organization_id;
  v_motivo        text := btrim(coalesce(p_motivo, ''));
  v_hash          text;
  v_evento        record;
  v_membership    uuid;
  v_ciclo         record;
  v_encerrado     boolean;
  v_qtd_pend      integer;
  v_nova_versao   integer;
  v_instante      timestamptz := now();
begin
  if p_cycle_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_09_INVALID_INPUT: cycle_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_09_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_09_INVALID_INPUT: motivo do encerramento obrigatorio';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'ciclo_encerrar',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'motivo', v_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.ciclo_ator_valido(p_actor_user_profile_id, v_org, 'cycle.manage') then
    raise exception 'F5_09_FORBIDDEN: ator sem perfil/membership ativa e capability cycle.manage na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status',
      'quantidade_pendencias', coalesce((v_evento.after_value->>'quantidade_pendencias')::integer, 0));
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_09_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform public.ciclo_lock_organizacao(v_org);

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_09_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status',
      'quantidade_pendencias', coalesce((v_evento.after_value->>'quantidade_pendencias')::integer, 0));
  end if;

  select c.id, c.ano, c.numero, c.status, c.version
    into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_09_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- T3: somente ATIVO -> ENCERRADO (ENCERRADO->ATIVO e reabertura, propria do P4).
  if v_ciclo.status <> 'ATIVO' then
    raise exception 'F5_09_CONFLICT: encerramento exige ciclo ATIVO (status atual %)',
      v_ciclo.status;
  end if;
  if v_ciclo.version <> p_expected_version then
    raise exception 'F5_09_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- Fechamento F5-06 REUSADO: marca pendencias permanentes nas avaliacoes
  -- incompletas e grava os contadores no ciclo (com `version = version + 1`).
  -- Qualquer falha aqui aborta a transacao inteira (rollback total).
  perform public.evaluation_fechar_ciclo_pendencias(
    p_cycle_id, v_org, p_actor_user_profile_id);

  select c.encerrado_com_pendencias, c.quantidade_pendencias, c.version
    into v_encerrado, v_qtd_pend, v_nova_versao
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org;

  update public.evaluation_cycles
     set status = 'ENCERRADO',
         data_encerramento = v_instante
   where id = p_cycle_id
     and organization_id = v_org;

  insert into public.cycle_events (
    organization_id, cycle_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_cycle_id, 'evaluation_cycle', 'ENCERRADO', v_instante,
    v_motivo,
    jsonb_build_object(
      'status', v_ciclo.status, 'ano', v_ciclo.ano, 'numero', v_ciclo.numero,
      'version', v_ciclo.version),
    jsonb_build_object(
      'status', 'ENCERRADO', 'data_encerramento', v_instante,
      'encerrado_com_pendencias', v_encerrado,
      'quantidade_pendencias', v_qtd_pend,
      'version', v_nova_versao),
    v_hash, p_cycle_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'cycle_id', p_cycle_id,
    'version', v_nova_versao,
    'status', 'ENCERRADO',
    'quantidade_pendencias', v_qtd_pend);
end;
$$;

comment on function public.ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid) is
  'F5-09 P2 (T3/D10): encerra ciclo ATIVO com motivo obrigatorio, reusando '
  '`evaluation_fechar_ciclo_pendencias` (F5-06) para marcar pendencias permanentes '
  'e gravar os contadores no ciclo; o status passa a ENCERRADO na MESMA transacao '
  '(falha => rollback total). Nao incrementa version duas vezes: o resultado e '
  'expected_version + 1. Reabertura/cancelamento sao do P4.';

-- ----------------------------------------------------------------------------
-- 5) ACL das RPCs (EXECUTE somente service_role)
-- ----------------------------------------------------------------------------
-- SECURITY INVOKER + search_path fixo; nenhuma superficie a public/anon/
-- authenticated (o cliente nunca chama RPC privilegiada direto — a fronteira
-- confiavel e a Edge, P7).
revoke all on function public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ciclo_ativar(uuid, uuid, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)
  to service_role;
grant execute on function public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)
  to service_role;
grant execute on function public.ciclo_ativar(uuid, uuid, integer, uuid, uuid)
  to service_role;
grant execute on function public.ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 6) Guarda final FAIL-CLOSED (§19 P2)
-- ----------------------------------------------------------------------------
-- A migration so termina se: as 4 RPCs existirem com a assinatura do contrato,
-- SECURITY INVOKER, search_path fixo e EXECUTE restrito; o deny-by-default da P1
-- continuar intacto (nenhuma policy nova, `authenticated` sem leitura de ciclo e
-- trilha — o SELECT own-tenant e do P5) e as constraints/triggers da P1
-- continuarem presentes.
do $$
declare
  v_rpcs text[] := array[
    'ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)',
    'ciclo_ativar(uuid, uuid, integer, uuid, uuid)',
    'ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)'];
  v_fn      text;
  v_rec     record;
  v_problemas text[] := array[]::text[];
begin
  foreach v_fn in array v_rpcs loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config
      into v_rec
      from pg_proc p
     where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      v_problemas := v_problemas || ('ausente: ' || v_fn);
      continue;
    end if;
    if v_rec.prosecdef then
      v_problemas := v_problemas || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_problemas := v_problemas || ('sem search_path fixo: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_problemas := v_problemas || ('service_role sem EXECUTE: ' || v_fn);
    end if;
    if has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE') then
      v_problemas := v_problemas || ('exposta a anon/authenticated: ' || v_fn);
    end if;
  end loop;

  -- P1 intacta: constraints, triggers e deny-by-default.
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_problemas := v_problemas || 'I5 ausente';
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_cycles'::regclass
       and conname = 'ex_evaluation_cycles_periodo_no_overlap' and contype = 'x'
  ) then
    v_problemas := v_problemas || 'I6 ausente';
  end if;
  foreach v_fn in array array[
    'trg_cycle_events_append_only', 'trg_cycle_events_no_delete',
    'trg_cycle_events_no_truncate']
  loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = 'public.cycle_events'::regclass
         and tgname = v_fn and not tgisinternal
    ) then
      v_problemas := v_problemas || ('trigger ausente: ' || v_fn);
    end if;
  end loop;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('evaluation_cycles', 'cycle_events')
  ) then
    v_problemas := v_problemas || 'policy antecipada (leitura de ciclo e do P5)';
  end if;
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'anon/authenticated com acesso antecipado';
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception 'F5_09_P2_GUARD: fundacao da P2 inconsistente: %',
      array_to_string(v_problemas, '; ');
  end if;

  raise notice 'F5-09 P2: guarda final OK (4 RPCs INVOKER com EXECUTE so service_role; P1 e deny-by-default intactos)';
end $$;
