-- ============================================================================
-- F5-09 P4: transicoes excepcionais soberanas de ciclo — cancelar, reabrir e
-- corrigir periodo
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§6 T4/T5/T6/T7 + nota da inclusao
-- aditiva, §7.1 (movimentacao NAO rematerializa), §8 autorizacao, §10 integridade
-- I7/I8/I11/I12/I13/I14/I19, §11 concorrencia/idempotencia, §12 auditoria,
-- §13.2 RPCs, §13.3 reuso obrigatorio, §15, §19 P4) e docs/F5-09-duvidas.md
-- (D1–D28 ratificadas; D8/D9, D10–D15, D20/D21 em especial).
-- Pre-requisitos: P1 (`20260915000000`), P2 (`20260916000000`), P3
-- (`20260917000000`) e F5-06 (`evaluation_cancelar`).
--
-- Entregue AQUI (e somente isto):
--   1) `ciclo_cancelar`         — T4/T5: PLANEJADO|ATIVO -> CANCELADO (terminal),
--                                 resolvendo as avaliacoes NAO concluidas na
--                                 MESMA transacao pelo caminho soberano da F5-06;
--   2) `ciclo_reabrir`          — T6: ENCERRADO -> ATIVO sem rematerializar nada;
--   3) `ciclo_corrigir_periodo` — T7: ATIVO -> ATIVO, corrige o periodo com
--                                 justificativa e impacto calculado server-side.
--
-- Fora do escopo (P5+), deliberadamente NAO implementado aqui: policy de LEITURA
-- para `authenticated` (P5), porta de leitura do cliente/CycleRepository,
-- Policy Engine cycle.read/cycle.manage, Edge `ciclos` + bundle `admin` (P7),
-- cutover do frontend (P8) e validacao integrada (P9). Nenhuma capability nova,
-- nenhum bundle alterado, nenhuma tabela/coluna nova, nenhum DELETE fisico.
--
-- Invariantes preservadas (D1–D28), em especial:
--   - `CANCELADO` e TERMINAL (D8): reabertura/correcao de ciclo CANCELADO sao
--     recusadas; exclusao fisica e PROIBIDA em todos os estados (D9) — nenhuma
--     das tres RPCs contem `DELETE` (prova estatica na guarda final);
--   - cancelamento de ciclo ATIVO resolve as avaliacoes NAO concluidas na MESMA
--     transacao REUSANDO `evaluation_cancelar` (F5-06) e PRESERVA as CONCLUIDAS
--     (T4/I7); nada de logica de avaliacao reimplementada;
--   - cancelamento de ciclo PLANEJADO exige ausencia de avaliacoes (T5,
--     fail-closed — o operador cancela as avaliacoes antes);
--   - reabertura NAO rematerializa estrutura (I19/D27): nenhuma escrita em
--     `collegiate_cycle_snapshots`, `_positions`, `_members`,
--     `cycle_evaluation_responsibilities` ou `evaluation_participants`, e nenhuma
--     chamada a F3-08/F3-09 (prova estatica na guarda final). Nao cria avaliacoes;
--   - correcao de periodo NAO altera estrutura, gestores, colegiado,
--     participantes nem responsabilidades: so `data_inicio`/`data_fim`/`version`
--     do ciclo (T7);
--   - `version` incrementa EXATAMENTE UMA VEZ por operacao. AUDITORIA EXPLICITA
--     do ponto critico (evitar double increment): `evaluation_cancelar` (F5-06)
--     incrementa apenas `evaluations.version` e NAO toca
--     `evaluation_cycles.version`; `evaluation_fechar_ciclo_pendencias` (que SIM
--     incrementa a versao do ciclo) NAO e usada por nenhuma RPC desta migration;
--     logo as tres RPCs incrementam a versao do ciclo uma unica vez, por conta
--     propria (resultado = expected_version + 1, mesma convencao da P2/P3);
--   - tenant, ator, membership e capability vem SEMPRE do ator verificado:
--     `service_role` executa e NUNCA decide;
--   - serializacao pela chave normativa da familia de ciclos
--     (`ciclo_lock_organizacao`, P1) e idempotencia por
--     `(organization_id, operation_id)` com hash canonico DERIVADO server-side;
--   - UM evento append-only por mutacao (`CANCELADO`, `REABERTO`,
--     `PERIODO_CORRIGIDO`), na MESMA transacao, com autoria soberana e sem dados
--     pessoais;
--   - atomicidade total: qualquer falha (inclusive middleware das avaliacoes)
--     produz ROLLBACK TOTAL (ciclo no estado original, version original, zero
--     evento).
--
-- DESVIOS MINIMOS E EXPLICITOS em relacao ao §13.2 (documentados para auditoria):
--   (a) `p_payload_hash` NAO e parametro — MESMO desvio ja declarado e aceito na
--       P2/P3: o hash do payload canonico da INTENCAO e DERIVADO server-side dos
--       parametros validados (aceita-lo do cliente permitiria replay com hash
--       forjado). Continua gravado em `cycle_events.payload_hash` (SHA-256 hex),
--       preservando `unique (organization_id, operation_id)`.
--   (b) o evento da correcao de periodo e `PERIODO_CORRIGIDO` (e nao
--       `CORRECAO_PERIODO`): o §12 fixa `PERIODO_CORRIGIDO` e o CHECK FECHADO de
--       `cycle_events.event_type` (P1) so aceita esse tipo — usar outro nome
--       exigiria reabrir contrato congelado (proibido).
--   (c) `ciclo_reabrir` limpa `data_encerramento` (T6) e PRESERVA
--       `encerrado_com_pendencias`/`quantidade_pendencias`: o historico do
--       encerramento permanece integral na trilha (`cycle_events`), que e a fonte
--       unica; nenhum dado e apagado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
do $$
declare
  v_faltando text[] := array[]::text[];
  v_fn       text;
begin
  -- P1/P2/P3 e F5-06: primitivas reusadas.
  foreach v_fn in array array[
    'public.ciclo_ator_valido(uuid, uuid, text)',
    'public.ciclo_lock_organizacao(uuid)',
    'public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'public.ciclo_ativar(uuid, uuid, integer, uuid, uuid)',
    'public.ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)',
    'public.evaluation_cancelar(uuid, text, uuid)',
    'public.evaluation_ator_valido(uuid, uuid)']
  loop
    if to_regprocedure(v_fn) is null then
      v_faltando := v_faltando || ('ausente: ' || v_fn);
    end if;
  end loop;

  -- P1: a trilha precisa aceitar os tres tipos desta fase (CHECK FECHADO).
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.cycle_events'::regclass
       and c.contype = 'c'
       and position('CANCELADO' in pg_get_constraintdef(c.oid)) > 0
       and position('REABERTO' in pg_get_constraintdef(c.oid)) > 0
       and position('PERIODO_CORRIGIDO' in pg_get_constraintdef(c.oid)) > 0
  ) then
    v_faltando := v_faltando || 'cycle_events sem CHECK aceitando CANCELADO/REABERTO/PERIODO_CORRIGIDO'::text;
  end if;

  -- F5-04: as capabilities desta fase EXISTEM no catalogo (nenhuma nova).
  foreach v_fn in array array['cycle.cancel', 'cycle.reopen', 'cycle.period.correct']
  loop
    if not exists (
      select 1 from public.capabilities c
       where c.code = v_fn and c.status = 'active' and c.deprecated = false
    ) then
      v_faltando := v_faltando || ('capability ausente no catalogo: ' || v_fn);
    end if;
  end loop;

  -- P1: I5 (um ATIVO por organizacao) e I6 (sem sobreposicao de nao cancelados).
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_faltando := v_faltando || 'I5 (uq_evaluation_cycles_org_ativo) ausente'::text;
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycles'::regclass
       and c.conname = 'ex_evaluation_cycles_periodo_no_overlap' and c.contype = 'x'
  ) then
    v_faltando := v_faltando || 'I6 (ex_evaluation_cycles_periodo_no_overlap) ausente'::text;
  end if;

  -- P1: trilha append-only completa + idempotencia.
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.cycle_events'::regclass
       and c.conname = 'uq_cycle_events_org_operation' and c.contype = 'u'
  ) then
    v_faltando := v_faltando || 'cycle_events.uq_cycle_events_org_operation ausente'::text;
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
      v_faltando := v_faltando || ('trigger ' || v_fn || ' ausente');
    end if;
  end loop;

  -- F5-06: `evaluation_cancelar` acessivel a service_role (sem grant novo).
  if has_function_privilege('service_role', 'public.evaluation_cancelar(uuid, text, uuid)', 'EXECUTE') is not true then
    v_faltando := v_faltando || 'service_role sem EXECUTE em evaluation_cancelar'::text;
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception 'F5_09_P4_PREFLIGHT: baseline incompativel: %', array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-09 P4: preflight OK (P1/P2/P3 + F5-06 presentes; trilha ja aceita CANCELADO/REABERTO/PERIODO_CORRIGIDO e as 3 capabilities existem no catalogo)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) `ciclo_cancelar` — T4/T5: PLANEJADO|ATIVO -> CANCELADO (terminal, D8)
-- ----------------------------------------------------------------------------
-- Nota de auditoria (double increment): `evaluation_cancelar` incrementa
-- `evaluations.version` (nao a versao do ciclo), portanto esta RPC incrementa
-- `evaluation_cycles.version` exatamente UMA vez, por conta propria.
create or replace function public.ciclo_cancelar(
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
  v_instante      timestamptz := now();
  v_aval          record;
  v_qtd_aval      integer := 0;
  v_qtd_concl     integer := 0;
  v_qtd_cancel    integer := 0;
  v_qtd_ativas    integer := 0;
  v_nova_versao   integer;
begin
  -- (1) Forma: nada aqui e autoridade.
  if p_cycle_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_09_INVALID_INPUT: cycle_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_09_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_09_INVALID_INPUT: motivo do cancelamento obrigatorio';
  end if;

  -- (2) Hash canonico DERIVADO server-side (desvio (a) no header).
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'ciclo_cancelar',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'motivo', v_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (3) Ator soberano: membership ativa + capability efetiva `cycle.cancel`.
  if not public.ciclo_ator_valido(p_actor_user_profile_id, v_org, 'cycle.cancel') then
    raise exception 'F5_09_FORBIDDEN: ator sem perfil/membership ativa e capability cycle.cancel na organizacao';
  end if;

  -- (4) Idempotencia ANTES do lock.
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
      'cycle_id', p_cycle_id,
      'status', v_evento.after_value->>'status',
      'version', (v_evento.after_value->>'version')::integer,
      'avaliacoes_canceladas', coalesce((v_evento.after_value->>'avaliacoes_canceladas')::integer, 0),
      'avaliacoes_concluidas_preservadas', coalesce((v_evento.after_value->>'avaliacoes_concluidas_preservadas')::integer, 0));
  end if;

  -- (5) Membership ativa do ator (autoria soberana).
  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_09_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (6) Lock normativo da familia de CICLOS (§11).
  perform public.ciclo_lock_organizacao(v_org);

  -- (7) Idempotencia DEPOIS do lock.
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
      'cycle_id', p_cycle_id,
      'status', v_evento.after_value->>'status',
      'version', (v_evento.after_value->>'version')::integer,
      'avaliacoes_canceladas', coalesce((v_evento.after_value->>'avaliacoes_canceladas')::integer, 0),
      'avaliacoes_concluidas_preservadas', coalesce((v_evento.after_value->>'avaliacoes_concluidas_preservadas')::integer, 0));
  end if;

  -- (8) Ciclo do tenant, travado.
  select c.id, c.ano, c.numero, c.status, c.version, c.data_inicio, c.data_fim
    into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_09_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- (9) T4/T5: apenas PLANEJADO e ATIVO; CANCELADO e TERMINAL (D8) e ENCERRADO
  -- nao e cancelavel (reabra antes, se for o caso).
  if v_ciclo.status not in ('PLANEJADO', 'ATIVO') then
    raise exception 'F5_09_CONFLICT: cancelamento exige ciclo PLANEJADO ou ATIVO (status atual %)',
      v_ciclo.status;
  end if;
  if v_ciclo.version <> p_expected_version then
    raise exception 'F5_09_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  select count(*),
         count(*) filter (where e.status = 'CONCLUIDA'),
         count(*) filter (where e.status <> 'CANCELADA')
    into v_qtd_aval, v_qtd_concl, v_qtd_ativas
    from public.evaluations e
   where e.cycle_id = p_cycle_id
     and e.organization_id = v_org;

  if v_ciclo.status = 'PLANEJADO' then
    -- (T5) fail-closed: o contrato exige que o operador resolva ANTES as
    -- avaliacoes do ciclo ("o operador cancela as avaliacoes antes"), portanto o
    -- que bloqueia e a existencia de avaliacao NAO CANCELADA — avaliacoes ja
    -- canceladas nao impedem o cancelamento do ciclo PLANEJADO.
    if v_qtd_ativas > 0 then
      raise exception 'F5_09_CONFLICT: cancelamento de ciclo PLANEJADO exige ausencia de avaliacoes nao canceladas (encontradas %)',
        v_qtd_ativas;
    end if;
  else
    -- (T4) NA MESMA TRANSACAO resolve as avaliacoes NAO concluidas reusando a
    -- primitiva soberana da F5-06; as CONCLUIDAS sao PRESERVADAS (I7) e as ja
    -- CANCELADAS nao sao tocadas. Nenhuma logica de avaliacao e reimplementada.
    for v_aval in
      select e.id
        from public.evaluations e
       where e.cycle_id = p_cycle_id
         and e.organization_id = v_org
         and e.status not in ('CONCLUIDA', 'CANCELADA')
       order by e.id
    loop
      perform public.evaluation_cancelar(v_aval.id, v_motivo, p_actor_user_profile_id);
      v_qtd_cancel := v_qtd_cancel + 1;
    end loop;
  end if;

  -- (10) Transicao terminal: version incrementa UMA vez (auditoria no header).
  update public.evaluation_cycles
     set status = 'CANCELADO',
         version = version + 1
   where id = p_cycle_id
     and organization_id = v_org
  returning version into v_nova_versao;

  -- (11) Trilha: UM evento append-only, mesma transacao, com contagens.
  insert into public.cycle_events (
    organization_id, cycle_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_cycle_id, 'evaluation_cycle', 'CANCELADO', v_instante,
    v_motivo,
    jsonb_build_object(
      'status', v_ciclo.status, 'ano', v_ciclo.ano, 'numero', v_ciclo.numero,
      'data_inicio', v_ciclo.data_inicio, 'data_fim', v_ciclo.data_fim,
      'version', v_ciclo.version),
    jsonb_build_object(
      'status', 'CANCELADO', 'version', v_nova_versao,
      'avaliacoes_no_ciclo', v_qtd_aval,
      'avaliacoes_canceladas', v_qtd_cancel,
      'avaliacoes_concluidas_preservadas', v_qtd_concl),
    v_hash, p_cycle_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'cycle_id', p_cycle_id,
    'status', 'CANCELADO',
    'version', v_nova_versao,
    'avaliacoes_canceladas', v_qtd_cancel,
    'avaliacoes_concluidas_preservadas', v_qtd_concl);
end;
$$;

comment on function public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid) is
  'F5-09 P4 (T4/T5, D8/D9/D11): cancela ciclo PLANEJADO ou ATIVO com motivo '
  'obrigatorio e expected_version. Em ciclo ATIVO resolve, NA MESMA TRANSACAO, as '
  'avaliacoes NAO concluidas reusando `evaluation_cancelar` (F5-06) e PRESERVA as '
  'CONCLUIDAS; em ciclo PLANEJADO exige ausencia de avaliacoes (fail-closed). '
  'CANCELADO e TERMINAL e nenhuma linha e apagada fisicamente (D9). Incrementa '
  '`version` uma unica vez e grava UM evento append-only CANCELADO com as '
  'contagens. Serializada por ciclo_lock_organizacao; idempotente por '
  '(organization_id, operation_id) com hash canonico derivado server-side. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 2) `ciclo_reabrir` — T6: ENCERRADO -> ATIVO (sem rematerializar nada)
-- ----------------------------------------------------------------------------
create or replace function public.ciclo_reabrir(
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
  v_org          uuid := p_organization_id;
  v_motivo       text := btrim(coalesce(p_motivo, ''));
  v_hash         text;
  v_evento       record;
  v_membership   uuid;
  v_ciclo        record;
  v_instante     timestamptz := now();
  v_qtd_partic   integer := 0;
  v_qtd_aval     integer := 0;
  v_nova_versao  integer;
begin
  if p_cycle_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_09_INVALID_INPUT: cycle_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_09_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_09_INVALID_INPUT: motivo da reabertura obrigatorio';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'ciclo_reabrir',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'motivo', v_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.ciclo_ator_valido(p_actor_user_profile_id, v_org, 'cycle.reopen') then
    raise exception 'F5_09_FORBIDDEN: ator sem perfil/membership ativa e capability cycle.reopen na organizacao';
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
      'cycle_id', p_cycle_id,
      'status', v_evento.after_value->>'status',
      'version', (v_evento.after_value->>'version')::integer,
      'participantes_materializados', coalesce((v_evento.after_value->>'participantes_materializados')::integer, 0),
      'avaliacoes_no_ciclo', coalesce((v_evento.after_value->>'avaliacoes_no_ciclo')::integer, 0));
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
      'cycle_id', p_cycle_id,
      'status', v_evento.after_value->>'status',
      'version', (v_evento.after_value->>'version')::integer,
      'participantes_materializados', coalesce((v_evento.after_value->>'participantes_materializados')::integer, 0),
      'avaliacoes_no_ciclo', coalesce((v_evento.after_value->>'avaliacoes_no_ciclo')::integer, 0));
  end if;

  select c.id, c.ano, c.numero, c.status, c.version, c.data_inicio, c.data_fim,
         c.data_encerramento, c.encerrado_com_pendencias, c.quantidade_pendencias
    into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_09_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- (T6) Unica transicao: ENCERRADO -> ATIVO. CANCELADO e TERMINAL (D8).
  if v_ciclo.status <> 'ENCERRADO' then
    raise exception 'F5_09_CONFLICT: reabertura exige ciclo ENCERRADO (status atual %)',
      v_ciclo.status;
  end if;
  if v_ciclo.version <> p_expected_version then
    raise exception 'F5_09_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- (T6/I5/D14) Um unico ATIVO por organizacao (o indice parcial e a barreira).
  if exists (
    select 1 from public.evaluation_cycles c
     where c.organization_id = v_org
       and c.id <> p_cycle_id
       and c.status = 'ATIVO'
  ) then
    raise exception 'F5_09_CONFLICT: ja existe ciclo ATIVO nesta organizacao (reabertura recusada)';
  end if;

  -- (I6/D15) Sem sobreposicao com ciclos NAO cancelados. Um ciclo ENCERRADO ja
  -- participa da exclusion da P1 (o indice so exclui CANCELADO), portanto o
  -- estado "ENCERRADO sobreposto" e inalcancavel; a checagem abaixo da mensagem
  -- propria de contrato e a exclusion permanece a barreira final.
  if v_ciclo.data_inicio is not null and v_ciclo.data_fim is not null then
    if exists (
      select 1 from public.evaluation_cycles c
       where c.organization_id = v_org
         and c.id <> p_cycle_id
         and c.status <> 'CANCELADO'
         and c.data_inicio is not null and c.data_fim is not null
         and daterange(c.data_inicio, c.data_fim + 1, '[)')
             && daterange(v_ciclo.data_inicio, v_ciclo.data_fim + 1, '[)')
    ) then
      raise exception 'F5_09_CONFLICT: periodo do ciclo sobrepoe outro ciclo nao cancelado da organizacao (I6/D15)';
    end if;
  end if;

  -- Evidencias de PRESERVACAO (nenhuma estrutura e tocada por esta RPC).
  select count(*) into v_qtd_partic
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org
     and s.ano = v_ciclo.ano
     and s.ciclo = v_ciclo.numero;
  select count(*) into v_qtd_aval
    from public.evaluations e
   where e.cycle_id = p_cycle_id
     and e.organization_id = v_org;

  -- (T6) Reabertura: status volta a ATIVO, `data_encerramento` limpo (o historico
  -- do encerramento PERMANECE na trilha append-only) e version+1. As contagens de
  -- pendencia sao historicas e NAO sao apagadas (desvio (c) no header).
  update public.evaluation_cycles
     set status = 'ATIVO',
         data_encerramento = null,
         version = version + 1
   where id = p_cycle_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.cycle_events (
    organization_id, cycle_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_cycle_id, 'evaluation_cycle', 'REABERTO', v_instante,
    v_motivo,
    jsonb_build_object(
      'status', v_ciclo.status, 'ano', v_ciclo.ano, 'numero', v_ciclo.numero,
      'data_encerramento', v_ciclo.data_encerramento,
      'encerrado_com_pendencias', v_ciclo.encerrado_com_pendencias,
      'quantidade_pendencias', v_ciclo.quantidade_pendencias,
      'version', v_ciclo.version),
    jsonb_build_object(
      'status', 'ATIVO', 'version', v_nova_versao,
      'data_encerramento', null,
      'participantes_materializados', v_qtd_partic,
      'avaliacoes_no_ciclo', v_qtd_aval),
    v_hash, p_cycle_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'cycle_id', p_cycle_id,
    'status', 'ATIVO',
    'version', v_nova_versao,
    'participantes_materializados', v_qtd_partic,
    'avaliacoes_no_ciclo', v_qtd_aval);
end;
$$;

comment on function public.ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid) is
  'F5-09 P4 (T6, D7/D8/D14/D15): reabre ciclo ENCERRADO (unicamente) para ATIVO, '
  'com motivo obrigatorio, expected_version, nenhum outro ATIVO na organizacao e '
  'sem sobreposicao com ciclos nao cancelados. NAO rematerializa estrutura '
  '(nenhuma escrita em snapshots/posicoes/membros/responsabilidades/participantes '
  'e nenhuma chamada a F3-08/F3-09) e NAO cria avaliacoes: apenas status, '
  'data_encerramento=null e version+1; o historico do encerramento permanece na '
  'trilha. Grava UM evento append-only REABERTO. SECURITY INVOKER; EXECUTE '
  'somente service_role.';

-- ----------------------------------------------------------------------------
-- 3) `ciclo_corrigir_periodo` — T7: ATIVO -> ATIVO com impacto server-side
-- ----------------------------------------------------------------------------
create or replace function public.ciclo_corrigir_periodo(
  p_cycle_id uuid,
  p_organization_id uuid,
  p_data_inicio date,
  p_data_fim date,
  p_justificativa text,
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
  v_org            uuid := p_organization_id;
  v_justificativa  text := btrim(coalesce(p_justificativa, ''));
  v_hash           text;
  v_evento         record;
  v_membership     uuid;
  v_ciclo          record;
  v_instante       timestamptz := now();
  v_qtd_aval       integer := 0;
  v_qtd_concl      integer := 0;
  v_qtd_nao_concl  integer := 0;
  v_qtd_fora       integer := 0;
  v_qtd_partic     integer := 0;
  v_impacto        jsonb;
  v_nova_versao    integer;
begin
  if p_cycle_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_09_INVALID_INPUT: cycle_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_09_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_data_inicio is null or p_data_fim is null then
    raise exception 'F5_09_INVALID_INPUT: data_inicio e data_fim obrigatorias na correcao de periodo';
  end if;
  if p_data_inicio > p_data_fim then
    raise exception 'F5_09_INVALID_INPUT: data_inicio deve ser menor ou igual a data_fim';
  end if;
  if v_justificativa = '' then
    raise exception 'F5_09_INVALID_INPUT: justificativa da correcao de periodo obrigatoria';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'ciclo_corrigir_periodo',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'data_inicio', p_data_inicio,
    'data_fim', p_data_fim,
    'justificativa', v_justificativa,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.ciclo_ator_valido(p_actor_user_profile_id, v_org, 'cycle.period.correct') then
    raise exception 'F5_09_FORBIDDEN: ator sem perfil/membership ativa e capability cycle.period.correct na organizacao';
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
      'cycle_id', p_cycle_id,
      'version', (v_evento.after_value->>'version')::integer,
      'data_inicio', (v_evento.after_value->>'data_inicio')::date,
      'data_fim', (v_evento.after_value->>'data_fim')::date,
      'impacto', v_evento.after_value->'impacto');
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
      'cycle_id', p_cycle_id,
      'version', (v_evento.after_value->>'version')::integer,
      'data_inicio', (v_evento.after_value->>'data_inicio')::date,
      'data_fim', (v_evento.after_value->>'data_fim')::date,
      'impacto', v_evento.after_value->'impacto');
  end if;

  select c.id, c.ano, c.numero, c.status, c.version, c.data_inicio, c.data_fim
    into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_09_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- (T7/D13) Correcao auditada e exclusiva de ciclo ATIVO; ciclo PLANEJADO usa a
  -- edicao comum (T1/`ciclo_editar`).
  if v_ciclo.status <> 'ATIVO' then
    raise exception 'F5_09_CONFLICT: correcao de periodo exige ciclo ATIVO (status atual %)',
      v_ciclo.status;
  end if;
  if v_ciclo.version <> p_expected_version then
    raise exception 'F5_09_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;
  if v_ciclo.data_inicio is not distinct from p_data_inicio
     and v_ciclo.data_fim is not distinct from p_data_fim then
    raise exception 'F5_09_CONFLICT: periodo informado e identico ao atual (nada a corrigir)';
  end if;

  -- (I6/D15) Sem sobreposicao com outros ciclos NAO cancelados do tenant; a
  -- exclusion da P1 e reavaliada no UPDATE e permanece a barreira final.
  if exists (
    select 1 from public.evaluation_cycles c
     where c.organization_id = v_org
       and c.id <> p_cycle_id
       and c.status <> 'CANCELADO'
       and c.data_inicio is not null and c.data_fim is not null
       and daterange(c.data_inicio, c.data_fim + 1, '[)')
           && daterange(p_data_inicio, p_data_fim + 1, '[)')
  ) then
    raise exception 'F5_09_CONFLICT: novo periodo sobrepoe outro ciclo nao cancelado da organizacao (I6/D15)';
  end if;

  -- (T7) Impacto calculado SERVER-SIDE, exclusivamente de dados soberanos; o
  -- cliente NAO declara impacto (nao existe parametro para isso).
  select count(*),
         count(*) filter (where e.status = 'CONCLUIDA'),
         count(*) filter (where e.status not in ('CONCLUIDA', 'CANCELADA')),
         count(*) filter (
           where e.status = 'CONCLUIDA' and e.data_conclusao is not null
             and (e.data_conclusao::date < p_data_inicio or e.data_conclusao::date > p_data_fim))
    into v_qtd_aval, v_qtd_concl, v_qtd_nao_concl, v_qtd_fora
    from public.evaluations e
   where e.cycle_id = p_cycle_id
     and e.organization_id = v_org;
  select count(*) into v_qtd_partic
    from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org
     and s.ano = v_ciclo.ano
     and s.ciclo = v_ciclo.numero;

  v_impacto := jsonb_build_object(
    'data_inicio_anterior', v_ciclo.data_inicio,
    'data_fim_anterior', v_ciclo.data_fim,
    'data_inicio_nova', p_data_inicio,
    'data_fim_nova', p_data_fim,
    'dias_antes', (v_ciclo.data_fim - v_ciclo.data_inicio + 1),
    'dias_depois', (p_data_fim - p_data_inicio + 1),
    'dias_delta', ((p_data_fim - p_data_inicio + 1) - (v_ciclo.data_fim - v_ciclo.data_inicio + 1)),
    'avaliacoes_no_ciclo', v_qtd_aval,
    'avaliacoes_concluidas', v_qtd_concl,
    'avaliacoes_nao_concluidas', v_qtd_nao_concl,
    'avaliacoes_concluidas_fora_do_novo_periodo', v_qtd_fora,
    'participantes_materializados', v_qtd_partic);

  update public.evaluation_cycles
     set data_inicio = p_data_inicio,
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
    v_org, p_cycle_id, 'evaluation_cycle', 'PERIODO_CORRIGIDO', v_instante,
    v_justificativa,
    jsonb_build_object(
      'status', v_ciclo.status, 'ano', v_ciclo.ano, 'numero', v_ciclo.numero,
      'data_inicio', v_ciclo.data_inicio, 'data_fim', v_ciclo.data_fim,
      'version', v_ciclo.version),
    jsonb_build_object(
      'status', 'ATIVO', 'version', v_nova_versao,
      'data_inicio', p_data_inicio, 'data_fim', p_data_fim,
      'impacto', v_impacto),
    v_hash, p_cycle_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'cycle_id', p_cycle_id,
    'version', v_nova_versao,
    'data_inicio', p_data_inicio,
    'data_fim', p_data_fim,
    'impacto', v_impacto);
end;
$$;

comment on function public.ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid) is
  'F5-09 P4 (T7, D13/D15): corrige o periodo de ciclo ATIVO com justificativa '
  'obrigatoria, expected_version, data_inicio <= data_fim e sem sobreposicao com '
  'outros ciclos nao cancelados (a exclusion da P1 e a barreira final). NAO '
  'altera estrutura: nenhuma escrita em snapshots/posicoes/membros/'
  'responsabilidades/participantes, nenhum recalculo de gestor ou colegiado. O '
  'IMPACTO e calculado SERVER-SIDE (deltas de dias, avaliacoes por status, '
  'avaliacoes concluidas fora do novo periodo e participantes materializados) e '
  'gravado no evento PERIODO_CORRIGIDO junto de before/after; o cliente nao '
  'declara impacto. version+1 uma unica vez. SECURITY INVOKER; EXECUTE somente '
  'service_role.';

-- ----------------------------------------------------------------------------
-- 4) ACL: EXECUTE somente service_role (nenhuma superficie nova ao cliente)
-- ----------------------------------------------------------------------------
revoke all on function public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 5) Guarda final FAIL-CLOSED (§19 P4)
-- ----------------------------------------------------------------------------
-- A migration so termina se: as tres RPCs existirem com a assinatura do contrato,
-- SECURITY INVOKER, search_path fixo e EXECUTE restrito; todas adquirirem a chave
-- normativa da familia de ciclos e NAO usarem chave de outra familia; NENHUMA
-- contiver `DELETE` (D9: exclusao fisica proibida), escrita em tabelas de
-- snapshot/responsabilidade/participantes nem chamada de materializacao
-- (I19/D27: sem rematerializacao); e as fundacoes P1/P2/P3 e o deny-by-default
-- continuarem intactos.
do $$
declare
  v_rpcs text[] := array[
    'ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)'];
  v_fn      text;
  v_rec     record;
  v_def     text;
  v_args    text;
  v_problemas text[] := array[]::text[];
begin
  foreach v_fn in array v_rpcs loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config,
           pg_get_functiondef(p.oid) as def,
           pg_get_function_arguments(p.oid) as args
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

    v_def := lower(v_rec.def);
    if position('ciclo_lock_organizacao' in v_def) = 0 then
      v_problemas := v_problemas || ('sem a chave normativa de ciclos: ' || v_fn);
    end if;
    if position('position_reporting_lines:' in v_def) > 0
       or position('f5_07_estrutura:' in v_def) > 0 then
      v_problemas := v_problemas || ('usa chave de OUTRA familia de lock: ' || v_fn);
    end if;
    -- D9: nenhuma exclusao fisica em nenhum estado.
    if position('delete from' in v_def) > 0 or position('truncate' in v_def) > 0 then
      v_problemas := v_problemas || ('contem DELETE/TRUNCATE (D9): ' || v_fn);
    end if;
    -- I19/D27/I18: nenhuma escrita em estrutura materializada.
    if position('insert into public.collegiate_cycle_snapshot' in v_def) > 0
       or position('update public.collegiate_cycle_snapshot' in v_def) > 0
       or position('insert into public.cycle_evaluation_responsibilities' in v_def) > 0
       or position('update public.cycle_evaluation_responsibilities' in v_def) > 0
       or position('insert into public.evaluation_participants' in v_def) > 0
       or position('update public.evaluation_participants' in v_def) > 0
       or position('update public.evaluations' in v_def) > 0
       or position('insert into public.evaluations' in v_def) > 0 then
      v_problemas := v_problemas || ('escreve em estrutura/avaliacao (deveria delegar): ' || v_fn);
    end if;
    -- I19/D27: nenhuma rematerializacao (nenhuma chamada a F3-08/F3-09).
    if position('materializar_colegiado_ciclo' in v_def) > 0
       or position('materializar_responsabilidades_avaliacao' in v_def) > 0 then
      v_problemas := v_problemas || ('rematerializa estrutura (I19/D27): ' || v_fn);
    end if;
  end loop;

  -- Assinaturas congeladas do contrato (§13.2), sem parametro fora do contrato.
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    v_problemas := v_problemas || ('assinatura de ciclo_cancelar fora do contrato: ' || coalesce(v_args, 'nula'));
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    v_problemas := v_problemas || ('assinatura de ciclo_reabrir fora do contrato: ' || coalesce(v_args, 'nula'));
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_data_inicio date, p_data_fim date, p_justificativa text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    v_problemas := v_problemas || ('assinatura de ciclo_corrigir_periodo fora do contrato: ' || coalesce(v_args, 'nula'));
  end if;

  -- P1/P2/P3 intactas: I5, I6, trilha append-only, idempotencia e deny-by-default.
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_problemas := v_problemas || 'I5 ausente'::text;
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycles'::regclass
       and c.conname = 'ex_evaluation_cycles_periodo_no_overlap' and c.contype = 'x'
  ) then
    v_problemas := v_problemas || 'I6 ausente'::text;
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
  if to_regprocedure('public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)') is null then
    v_problemas := v_problemas || 'P3 ausente (ciclo_incluir_admissao)'::text;
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename in ('evaluation_cycles', 'cycle_events')
  ) then
    v_problemas := v_problemas || 'policy antecipada (leitura de ciclo e do P5)'::text;
  end if;
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'anon/authenticated com acesso antecipado'::text;
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception 'F5_09_P4_GUARD: fundacao da P4 inconsistente: %',
      array_to_string(v_problemas, '; ');
  end if;

  raise notice 'F5-09 P4: guarda final OK (3 RPCs INVOKER com EXECUTE so service_role, chave normativa de ciclos, zero DELETE, zero escrita em estrutura materializada e zero rematerializacao; P1/P2/P3 e deny-by-default intactos)';
end $$;
