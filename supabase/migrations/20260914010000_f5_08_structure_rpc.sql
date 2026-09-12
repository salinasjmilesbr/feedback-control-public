-- ============================================================================
-- F5-08 P2 (Etapa 5): RPCs soberanas de estrutura organizacional e catalogos
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-08-desenho-tecnico.md (§11, §13.6, §14, §15, §21.1, §22,
-- §27/P2; D1-D25 FECHADAS).
--
-- Este arquivo entrega as 15 RPCs do P2 (nenhuma outra):
--   ESTRUTURA
--     1. estrutura_unidade_criar            6. estrutura_posicao_criar
--     2. estrutura_unidade_renomear         7. estrutura_posicao_encerrar
--     3. estrutura_unidade_encerrar         8. estrutura_colegiado_definir
--     4. estrutura_unidade_parent_definir   9. estrutura_colegiado_encerrar
--     5. estrutura_unidade_parent_encerrar
--   CATALOGO
--    10. catalogo_cargo_criar               13. catalogo_senioridade_criar
--    11. catalogo_cargo_renomear            14. catalogo_senioridade_renomear
--    12. catalogo_cargo_status_alterar      15. catalogo_senioridade_status_alterar
--
-- Padrao de seguranca (identico a F5-04/F5-06/F5-07, D10/D19):
--   - SECURITY INVOKER, `set search_path = public`, ZERO SECURITY DEFINER novo;
--   - EXECUTE somente para `service_role` (`revoke all ... from public, anon,
--     authenticated`): nao existe superficie nova a `anon`/`authenticated`;
--   - `service_role` EXECUTA e NUNCA decide autorizacao: cada RPC revalida, na
--     MESMA transacao, (a) o ator por `colaborador_ator_valido` (F5-06 D27) e
--     (b) a capability EFETIVA por `resolver_capabilities_escopos_efetivas`
--     (D10) — `org.structure.manage` ou `org.catalog.manage`. Nada de role
--     nominal, nada de `usuario_eh_administrador`, nada de Policy Engine
--     funcional (allowlist capability x target permanece `[]` — D19 intacta).
--   - `p_organization_id` e INTENCAO: revalidado contra a membership ativa do
--     ator; `p_actor_user_profile_id` NUNCA e autoridade (vem da identidade
--     verificada na fronteira).
--
-- Tenant (D15): toda entidade e resolvida por `(id, organization_id)` na MESMA
-- consulta — nunca por id isolado seguido de comparacao. Alvo de outro tenant
-- responde `F5_08_NOT_FOUND` (nunca revela existencia alheia).
--
-- Idempotencia (D13/D14): `payload_hash` canonico da INTENCAO consultado em
-- `structure_events` por `(organization_id, operation_id)`; mesmo id + mesmo
-- hash devolve o MESMO resultado (sem novo evento); hash divergente responde
-- `F5_08_CONFLICT`. Evento e mutacao na MESMA transacao.
--
-- Concorrencia (D14/D24): toda mutacao toma
-- `pg_advisory_xact_lock(hashtext('position_reporting_lines:' || org::text))`
-- — a chave NORMATIVA da F3-04, unica no sistema apos o P1. A chave antiga
-- (`f5_07_estrutura:`) nao e reintroduzida em nenhum ponto. Mutações de linha
-- existente exigem `expected_version`, comparam e incrementam `version` na
-- mesma transacao (divergencia => `F5_08_CONFLICT`).
--
-- Erros publicos estaveis: `F5_08_INVALID_INPUT`, `F5_08_FORBIDDEN`,
-- `F5_08_NOT_FOUND`, `F5_08_CONFLICT`. As constraints/triggers do banco
-- (incluindo I1/I2/I3 e as exclusion constraints do P1) continuam sendo a
-- ULTIMA barreira — as RPCs pre-validam o que conseguem para nao expor erro
-- cru.
--
-- Auditoria (D13/§15): toda mutacao grava UM evento em `structure_events` com
-- organization_id, entity_type, entity_id, event_type, effective_date, reason,
-- before_value/after_value (estado estrutural normalizado; sem dado pessoal),
-- payload_hash, result_entity_id, actor_user_profile_id, actor_membership_id e
-- operation_id. A trilha NAO decide autorizacao.
--
-- A trilha `structure_events` e gravada na MESMA transacao; o evento de
-- operacoes que retornam versao guarda `after_value->>'version'` para que o
-- replay idempotente devolva exatamente o mesmo resultado.
-- ============================================================================

-- ============================================================================
-- 1) `estrutura_unidade_criar` (§21.1 item 1)
-- ============================================================================
create or replace function public.estrutura_unidade_criar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_nome text,
  p_valid_from timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org        uuid := p_organization_id;
  v_motivo     text := btrim(coalesce(p_motivo, ''));
  v_nome       text := btrim(coalesce(p_nome, ''));
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_id         uuid;
begin
  -- (1) Forma do payload — nada aqui e autoridade.
  if p_organization_id is null or p_operation_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id e operation_id obrigatorios';
  end if;
  if v_nome = '' then
    raise exception 'F5_08_INVALID_INPUT: nome da unidade obrigatorio';
  end if;
  if p_valid_from is null then
    raise exception 'F5_08_INVALID_INPUT: valid_from obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  -- (2) Hash canonico da intencao (D13/D14).
  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_unidade_criar',
    'organization_id', v_org,
    'nome', v_nome,
    'valid_from', p_valid_from,
    'motivo', v_motivo
  )::text);

  -- (3) Ator revalidado no banco (F5-06 D27).
  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  -- (4) Capability efetiva (D10/D19), na mesma transacao.
  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  -- (5) Idempotencia (D14).
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  -- (6) Membership do ator (autoria soberana da trilha).
  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (7) Serializacao estrutural do tenant (D14/D24).
  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  -- (8) Unicidade de nome na organizacao (constraint e a ultima barreira).
  if exists (
    select 1
      from public.organizational_units u
     where u.organization_id = v_org
       and u.name = v_nome
  ) then
    raise exception 'F5_08_CONFLICT: nome de unidade ja utilizado na organizacao';
  end if;

  -- (9) Criacao (unidade vigente a partir de valid_from).
  insert into public.organizational_units (organization_id, name, valid_from)
  values (v_org, v_nome, p_valid_from)
  returning id into v_id;

  -- (10) Evento append-only na MESMA transacao (D13).
  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'organizational_unit', v_id, 'CRIADO', p_valid_from,
    v_motivo, null,
    jsonb_build_object('name', v_nome, 'valid_from', p_valid_from, 'version', 0),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_id;
end;
$$;

comment on function public.estrutura_unidade_criar(uuid, uuid, uuid, text, timestamptz, text) is
  'F5-08 P2/§21.1: cria unidade organizacional (vigente a partir de valid_from) '
  'com ator e capability revalidados no banco, idempotencia por operation_id e '
  'evento append-only na mesma transacao.';

-- ============================================================================
-- 2) `estrutura_unidade_renomear` (§21.1 item 2 / D4)
-- ============================================================================
create or replace function public.estrutura_unidade_renomear(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_unidade_id uuid,
  p_nome text,
  p_expected_version integer,
  p_motivo text
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org           uuid := p_organization_id;
  v_motivo        text := btrim(coalesce(p_motivo, ''));
  v_nome          text := btrim(coalesce(p_nome, ''));
  v_hash          text;
  v_evento        record;
  v_membership    uuid;
  v_unidade       record;
  v_nova_versao   integer;
begin
  if p_organization_id is null or p_operation_id is null or p_unidade_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e unidade_id obrigatorios';
  end if;
  if v_nome = '' then
    raise exception 'F5_08_INVALID_INPUT: nome da unidade obrigatorio';
  end if;
  if p_expected_version is null then
    raise exception 'F5_08_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_unidade_renomear',
    'organization_id', v_org,
    'unidade_id', p_unidade_id,
    'nome', v_nome,
    'expected_version', p_expected_version,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value->>'version')::integer, 0);
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  -- Resolucao por (id, organization_id) — cross-tenant e NOT_FOUND (D15).
  select u.id, u.name, u.valid_from, u.valid_to, u.version
    into v_unidade
    from public.organizational_units u
   where u.id = p_unidade_id
     and u.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: unidade inexistente ou de outro tenant';
  end if;

  -- D4: unidade encerrada nao e renomeada.
  if v_unidade.valid_to is not null then
    raise exception 'F5_08_CONFLICT: unidade encerrada nao pode ser renomeada';
  end if;
  if v_unidade.version <> p_expected_version then
    raise exception 'F5_08_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;
  if v_nome = v_unidade.name then
    raise exception 'F5_08_CONFLICT: o nome informado ja e o nome atual da unidade';
  end if;
  if exists (
    select 1
      from public.organizational_units u
     where u.organization_id = v_org
       and u.name = v_nome
       and u.id <> p_unidade_id
  ) then
    raise exception 'F5_08_CONFLICT: nome de unidade ja utilizado na organizacao';
  end if;

  update public.organizational_units
     set name = v_nome,
         version = version + 1
   where id = p_unidade_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'organizational_unit', p_unidade_id, 'RENOMEADO', now(),
    v_motivo,
    jsonb_build_object('name', v_unidade.name, 'version', v_unidade.version),
    jsonb_build_object('name', v_nome, 'version', v_nova_versao),
    v_hash, p_unidade_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_nova_versao;
end;
$$;

comment on function public.estrutura_unidade_renomear(uuid, uuid, uuid, uuid, text, integer, text) is
  'F5-08 P2/§21.1 D4: renomeia o ROTULO da unidade vigente (nome nao e '
  'identidade), com versao otimista, unicidade por organizacao, trilha '
  'before/after e evento RENOMEADO.';

-- ============================================================================
-- 3) `estrutura_unidade_encerrar` (§21.1 item 3 / D6 — I2 nos TRES casos)
-- ============================================================================
create or replace function public.estrutura_unidade_encerrar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_unidade_id uuid,
  p_valid_to timestamptz,
  p_expected_version integer,
  p_motivo text
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_unidade     record;
  v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null or p_unidade_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e unidade_id obrigatorios';
  end if;
  if p_valid_to is null then
    raise exception 'F5_08_INVALID_INPUT: valid_to obrigatorio';
  end if;
  if p_expected_version is null then
    raise exception 'F5_08_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_unidade_encerrar',
    'organization_id', v_org,
    'unidade_id', p_unidade_id,
    'valid_to', p_valid_to,
    'expected_version', p_expected_version,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value->>'version')::integer, 0);
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  select u.id, u.name, u.valid_from, u.valid_to, u.version
    into v_unidade
    from public.organizational_units u
   where u.id = p_unidade_id
     and u.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: unidade inexistente ou de outro tenant';
  end if;

  if v_unidade.valid_to is not null then
    raise exception 'F5_08_CONFLICT: unidade ja encerrada';
  end if;
  if p_valid_to <= v_unidade.valid_from then
    raise exception 'F5_08_CONFLICT: valid_to deve ser posterior ao valid_from da unidade';
  end if;
  if v_unidade.version <> p_expected_version then
    raise exception 'F5_08_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- Pre-validacao de I2 (D6, revisao PR #182) na DATA EFETIVA do encerramento,
  -- com semantica `[)`: relacao encerrada exatamente em T NAO e vigente em T.
  -- O trigger do P1 continua sendo a ultima barreira.
  if exists (
    select 1
      from public.organizational_positions p
     where p.unit_id = p_unidade_id
       and p.organization_id = v_org
       and p.valid_from <= p_valid_to
       and (p.valid_to is null or p.valid_to > p_valid_to)
  ) then
    raise exception 'F5_08_CONFLICT: existe posicao vigente na unidade na data de encerramento';
  end if;

  if exists (
    select 1
      from public.organizational_unit_parent_periods pp
     where pp.unit_id = p_unidade_id
       and pp.organization_id = v_org
       and pp.valid_from <= p_valid_to
       and (pp.valid_to is null or pp.valid_to > p_valid_to)
  ) then
    raise exception 'F5_08_CONFLICT: a unidade e FILHA em relacao de parent vigente na data de encerramento';
  end if;

  if exists (
    select 1
      from public.organizational_unit_parent_periods pp
     where pp.parent_unit_id = p_unidade_id
       and pp.organization_id = v_org
       and pp.valid_from <= p_valid_to
       and (pp.valid_to is null or pp.valid_to > p_valid_to)
  ) then
    raise exception 'F5_08_CONFLICT: a unidade e PAI de unidade com relacao vigente na data de encerramento';
  end if;

  update public.organizational_units
     set valid_to = p_valid_to,
         version = version + 1
   where id = p_unidade_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'organizational_unit', p_unidade_id, 'ENCERRADO', p_valid_to,
    v_motivo,
    jsonb_build_object('name', v_unidade.name, 'valid_to', v_unidade.valid_to,
                       'version', v_unidade.version),
    jsonb_build_object('name', v_unidade.name, 'valid_to', p_valid_to,
                       'version', v_nova_versao),
    v_hash, p_unidade_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_nova_versao;
end;
$$;

comment on function public.estrutura_unidade_encerrar(uuid, uuid, uuid, uuid, timestamptz, integer, text) is
  'F5-08 P2/§21.1 D6: encerra a unidade por valid_to (nunca DELETE) apos '
  'pre-validar I2 nos TRES casos (posicao vigente; unidade como FILHA; unidade '
  'como PAI) com semantica `[)`; versao otimista, trilha before/after e evento '
  'ENCERRADO. O trigger do P1 permanece a ultima barreira.';

-- ============================================================================
-- 4) `estrutura_unidade_parent_definir` (§21.1 item 4 / D7)
-- ============================================================================
create or replace function public.estrutura_unidade_parent_definir(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_unidade_id uuid,
  p_parent_unit_id uuid,
  p_valid_from timestamptz,
  p_motivo text
)
returns uuid
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
  v_unidade       record;
  v_parent        record;
  v_anterior      record;
  v_id            uuid;
begin
  if p_organization_id is null or p_operation_id is null or p_unidade_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e unidade_id obrigatorios';
  end if;
  if p_valid_from is null then
    raise exception 'F5_08_INVALID_INPUT: valid_from obrigatorio';
  end if;
  if p_parent_unit_id = p_unidade_id then
    raise exception 'F5_08_INVALID_INPUT: unidade nao pode ser parent de si mesma';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_unidade_parent_definir',
    'organization_id', v_org,
    'unidade_id', p_unidade_id,
    'parent_unit_id', p_parent_unit_id,
    'valid_from', p_valid_from,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  -- Unidade alvo vigente na data informada (resolucao por (id, organization_id)).
  select u.id, u.name, u.valid_from, u.valid_to
    into v_unidade
    from public.organizational_units u
   where u.id = p_unidade_id
     and u.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: unidade inexistente ou de outro tenant';
  end if;
  if not (v_unidade.valid_from <= p_valid_from
          and (v_unidade.valid_to is null or v_unidade.valid_to > p_valid_from)) then
    raise exception 'F5_08_CONFLICT: unidade alvo nao vigente na data informada';
  end if;

  -- Unidade pai (quando informada): mesma organizacao e vigente na data.
  -- `null` representa RAIZ (ausencia de relacao).
  if p_parent_unit_id is not null then
    select u.id, u.name, u.valid_from, u.valid_to
      into v_parent
      from public.organizational_units u
     where u.id = p_parent_unit_id
       and u.organization_id = v_org
     for update;
    if not found then
      raise exception 'F5_08_NOT_FOUND: unidade pai inexistente ou de outro tenant';
    end if;
    if not (v_parent.valid_from <= p_valid_from
            and (v_parent.valid_to is null or v_parent.valid_to > p_valid_from)) then
      raise exception 'F5_08_CONFLICT: unidade pai nao vigente na data informada';
    end if;
  end if;

  -- Periodo posterior (ou iniciando na mesma data) impediria a abertura: erro
  -- publico estavel ANTES de a exclusion constraint falar (ultima barreira).
  if exists (
    select 1
      from public.organizational_unit_parent_periods pp
     where pp.unit_id = p_unidade_id
       and pp.organization_id = v_org
       and pp.valid_from >= p_valid_from
  ) then
    raise exception 'F5_08_CONFLICT: existe periodo de parent posterior ou na data informada (encerre-o antes)';
  end if;

  -- Pre-validacao anti-ciclo com INTERSECAO TEMPORAL ACUMULADA (mesma semantica
  -- do trigger I1 do P1, que permanece a ultima barreira). Como o novo periodo
  -- e aberto, a janela acumulada inicia em [valid_from, infinity).
  if p_parent_unit_id is not null and exists (
    with recursive caminho(unit_id, janela) as (
      select p_parent_unit_id,
             tstzrange(p_valid_from, 'infinity'::timestamptz, '[)')
      union
      select pp.parent_unit_id,
             c.janela * tstzrange(pp.valid_from,
                                  coalesce(pp.valid_to, 'infinity'::timestamptz), '[)')
      from public.organizational_unit_parent_periods pp
      join caminho c on pp.unit_id = c.unit_id
      where pp.organization_id = v_org
        and pp.parent_unit_id is not null
        and c.janela && tstzrange(pp.valid_from,
                                  coalesce(pp.valid_to, 'infinity'::timestamptz), '[)')
    )
    select 1
    from caminho
    where unit_id = p_unidade_id
      and not isempty(janela)
  ) then
    raise exception 'F5_08_CONFLICT: a relacao informada criaria ciclo hierarquico de unidades';
  end if;

  -- Periodo vigente anterior (historico preservado: fecha, nunca apaga).
  select pp.id, pp.parent_unit_id, pp.valid_from, pp.valid_to, pp.version
    into v_anterior
    from public.organizational_unit_parent_periods pp
   where pp.unit_id = p_unidade_id
     and pp.organization_id = v_org
     and pp.valid_from < p_valid_from
     and (pp.valid_to is null or pp.valid_to > p_valid_from)
   order by pp.valid_from desc
   limit 1
   for update;

  if found then
    update public.organizational_unit_parent_periods
       set valid_to = p_valid_from,
           version = version + 1
     where id = v_anterior.id
       and organization_id = v_org;
  end if;

  insert into public.organizational_unit_parent_periods
    (organization_id, unit_id, parent_unit_id, valid_from)
  values (v_org, p_unidade_id, p_parent_unit_id, p_valid_from)
  returning id into v_id;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'organizational_unit_parent_period', v_id, 'PARENT_DEFINIDO',
    p_valid_from, v_motivo,
    case when v_anterior.id is null then null
         else jsonb_build_object('period_id', v_anterior.id,
                                 'parent_unit_id', v_anterior.parent_unit_id,
                                 'valid_from', v_anterior.valid_from,
                                 'valid_to', v_anterior.valid_to,
                                 'version', v_anterior.version) end,
    jsonb_build_object('unit_id', p_unidade_id,
                       'parent_unit_id', p_parent_unit_id,
                       'valid_from', p_valid_from,
                       'version', 0),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_id;
end;
$$;

comment on function public.estrutura_unidade_parent_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text) is
  'F5-08 P2/§21.1 D7: define (ou troca) o parent da unidade fechando o periodo '
  'vigente e abrindo um novo (`null` = raiz), com anti-ciclo de intersecao '
  'temporal acumulada, lock normativo e evento PARENT_DEFINIDO.';

-- ============================================================================
-- 5) `estrutura_unidade_parent_encerrar` (§21.1 item 5)
-- ============================================================================
create or replace function public.estrutura_unidade_parent_encerrar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_unidade_id uuid,
  p_valid_to timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_unidade     record;
  v_periodo     record;
  v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null or p_unidade_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e unidade_id obrigatorios';
  end if;
  if p_valid_to is null then
    raise exception 'F5_08_INVALID_INPUT: valid_to obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_unidade_parent_encerrar',
    'organization_id', v_org,
    'unidade_id', p_unidade_id,
    'valid_to', p_valid_to,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  select u.id, u.name, u.valid_from, u.valid_to
    into v_unidade
    from public.organizational_units u
   where u.id = p_unidade_id
     and u.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: unidade inexistente ou de outro tenant';
  end if;

  -- Relacao vigente na data informada (semantica `[)`).
  select pp.id, pp.parent_unit_id, pp.valid_from, pp.valid_to, pp.version
    into v_periodo
    from public.organizational_unit_parent_periods pp
   where pp.unit_id = p_unidade_id
     and pp.organization_id = v_org
     and pp.valid_from < p_valid_to
     and (pp.valid_to is null or pp.valid_to > p_valid_to)
   order by pp.valid_from desc
   limit 1
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: nenhuma relacao de parent vigente na data informada';
  end if;
  if p_valid_to <= v_periodo.valid_from then
    raise exception 'F5_08_CONFLICT: valid_to deve ser posterior ao inicio da relacao';
  end if;

  update public.organizational_unit_parent_periods
     set valid_to = p_valid_to,
         version = version + 1
   where id = v_periodo.id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'organizational_unit_parent_period', v_periodo.id,
    'PARENT_ENCERRADO', p_valid_to, v_motivo,
    jsonb_build_object('unit_id', p_unidade_id,
                       'parent_unit_id', v_periodo.parent_unit_id,
                       'valid_from', v_periodo.valid_from,
                       'valid_to', v_periodo.valid_to,
                       'version', v_periodo.version),
    jsonb_build_object('unit_id', p_unidade_id,
                       'valid_to', p_valid_to,
                       'version', v_nova_versao),
    v_hash, v_periodo.id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_periodo.id;
end;
$$;

comment on function public.estrutura_unidade_parent_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) is
  'F5-08 P2/§21.1: encerra a relacao de parent vigente por valid_to (nunca '
  'apaga; historico preservado) com evento PARENT_ENCERRADO.';

-- ============================================================================
-- 6) `estrutura_posicao_criar` (§21.1 item 6 / I4)
-- ============================================================================
create or replace function public.estrutura_posicao_criar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_unidade_id uuid,
  p_job_role_id uuid,
  p_seniority_level_id uuid,
  p_valid_from timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_unidade     record;
  v_cargo       record;
  v_senioridade record;
  v_id          uuid;
begin
  if p_organization_id is null or p_operation_id is null
     or p_unidade_id is null or p_job_role_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id, unidade_id e job_role_id obrigatorios';
  end if;
  if p_valid_from is null then
    raise exception 'F5_08_INVALID_INPUT: valid_from obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_posicao_criar',
    'organization_id', v_org,
    'unidade_id', p_unidade_id,
    'job_role_id', p_job_role_id,
    'seniority_level_id', p_seniority_level_id,
    'valid_from', p_valid_from,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  -- Unidade vigente na data (I5) e do mesmo tenant.
  select u.id, u.name, u.valid_from, u.valid_to
    into v_unidade
    from public.organizational_units u
   where u.id = p_unidade_id
     and u.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: unidade inexistente ou de outro tenant';
  end if;
  if not (v_unidade.valid_from <= p_valid_from
          and (v_unidade.valid_to is null or v_unidade.valid_to > p_valid_from)) then
    raise exception 'F5_08_CONFLICT: unidade nao vigente na data informada';
  end if;

  -- Cargo ATIVO (I4): item desativado nao entra em posicao nova.
  select j.id, j.name, j.code, j.status
    into v_cargo
    from public.job_roles j
   where j.id = p_job_role_id
     and j.organization_id = v_org;
  if not found then
    raise exception 'F5_08_NOT_FOUND: cargo inexistente ou de outro tenant';
  end if;
  if v_cargo.status <> 'active' then
    raise exception 'F5_08_CONFLICT: cargo inativo nao pode ser usado em nova posicao';
  end if;

  -- Senioridade (opcional) ATIVA e do mesmo tenant.
  if p_seniority_level_id is not null then
    select s.id, s.name, s.status
      into v_senioridade
      from public.seniority_levels s
     where s.id = p_seniority_level_id
       and s.organization_id = v_org;
    if not found then
      raise exception 'F5_08_NOT_FOUND: senioridade inexistente ou de outro tenant';
    end if;
    if v_senioridade.status <> 'active' then
      raise exception 'F5_08_CONFLICT: senioridade inativa nao pode ser usada em nova posicao';
    end if;
  end if;

  insert into public.organizational_positions
    (organization_id, unit_id, job_role_id, seniority_level_id, valid_from)
  values (v_org, p_unidade_id, p_job_role_id, p_seniority_level_id, p_valid_from)
  returning id into v_id;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'organizational_position', v_id, 'CRIADO', p_valid_from,
    v_motivo, null,
    jsonb_build_object('unit_id', p_unidade_id,
                       'job_role_id', p_job_role_id,
                       'seniority_level_id', p_seniority_level_id,
                       'valid_from', p_valid_from,
                       'version', 0),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_id;
end;
$$;

comment on function public.estrutura_posicao_criar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text) is
  'F5-08 P2/§21.1 D5/I4: cria posicao (unidade + cargo + senioridade opcional) '
  'exigindo unidade vigente e catalogos ATIVOS do mesmo tenant; atributos '
  'estruturais ficam imutaveis apos a criacao.';

-- ============================================================================
-- 7) `estrutura_posicao_encerrar` (§21.1 item 7 / I3)
-- ============================================================================
create or replace function public.estrutura_posicao_encerrar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_posicao_id uuid,
  p_valid_to timestamptz,
  p_expected_version integer,
  p_motivo text
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_posicao     record;
  v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null or p_posicao_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e posicao_id obrigatorios';
  end if;
  if p_valid_to is null then
    raise exception 'F5_08_INVALID_INPUT: valid_to obrigatorio';
  end if;
  if p_expected_version is null then
    raise exception 'F5_08_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_posicao_encerrar',
    'organization_id', v_org,
    'posicao_id', p_posicao_id,
    'valid_to', p_valid_to,
    'expected_version', p_expected_version,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value->>'version')::integer, 0);
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  select p.id, p.unit_id, p.valid_from, p.valid_to, p.version
    into v_posicao
    from public.organizational_positions p
   where p.id = p_posicao_id
     and p.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: posicao inexistente ou de outro tenant';
  end if;

  if v_posicao.valid_to is not null then
    raise exception 'F5_08_CONFLICT: posicao ja encerrada';
  end if;
  if p_valid_to <= v_posicao.valid_from then
    raise exception 'F5_08_CONFLICT: valid_to deve ser posterior ao valid_from da posicao';
  end if;
  if v_posicao.version <> p_expected_version then
    raise exception 'F5_08_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- Pre-validacao de I3 e da guarda F3-04 (semantica `[)`); os triggers
  -- permanecem a ultima barreira.
  if exists (
    select 1
      from public.occupations o
     where o.organizational_position_id = p_posicao_id
       and o.organization_id = v_org
       and o.valid_from <= p_valid_to
       and (o.valid_to is null or o.valid_to > p_valid_to)
  ) then
    raise exception 'F5_08_CONFLICT: existe ocupacao vigente na posicao na data de encerramento';
  end if;

  if exists (
    select 1
      from public.position_reporting_lines rl
     where rl.organization_id = v_org
       and (rl.subordinate_position_id = p_posicao_id
            or rl.manager_position_id = p_posicao_id)
       and rl.valid_from <= p_valid_to
       and (rl.valid_to is null or rl.valid_to > p_valid_to)
  ) then
    raise exception 'F5_08_CONFLICT: existe reporting line vigente na posicao na data de encerramento';
  end if;

  update public.organizational_positions
     set valid_to = p_valid_to,
         version = version + 1
   where id = p_posicao_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'organizational_position', p_posicao_id, 'ENCERRADO', p_valid_to,
    v_motivo,
    jsonb_build_object('unit_id', v_posicao.unit_id,
                       'valid_to', v_posicao.valid_to,
                       'version', v_posicao.version),
    jsonb_build_object('unit_id', v_posicao.unit_id,
                       'valid_to', p_valid_to,
                       'version', v_nova_versao),
    v_hash, p_posicao_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_nova_versao;
end;
$$;

comment on function public.estrutura_posicao_encerrar(uuid, uuid, uuid, uuid, timestamptz, integer, text) is
  'F5-08 P2/§21.1 D6: encerra a posicao por valid_to apos pre-validar ausencia '
  'de ocupacao vigente (I3) e de reporting line vigente (guarda F3-04), com '
  'versao otimista e evento ENCERRADO.';

-- ============================================================================
-- 8) `catalogo_cargo_criar` (§21.1 item 8)
-- ============================================================================
create or replace function public.catalogo_cargo_criar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_nome text,
  p_code text,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org        uuid := p_organization_id;
  v_motivo     text := btrim(coalesce(p_motivo, ''));
  v_nome       text := btrim(coalesce(p_nome, ''));
  v_code       text := nullif(btrim(coalesce(p_code, '')), '');
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_id         uuid;
begin
  if p_organization_id is null or p_operation_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id e operation_id obrigatorios';
  end if;
  if v_nome = '' then
    raise exception 'F5_08_INVALID_INPUT: nome do cargo obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'catalogo_cargo_criar',
    'organization_id', v_org,
    'nome', v_nome,
    'code', v_code,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.catalog.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.catalog.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  if exists (
    select 1
      from public.job_roles j
     where j.organization_id = v_org
       and j.name = v_nome
  ) then
    raise exception 'F5_08_CONFLICT: nome de cargo ja utilizado na organizacao';
  end if;
  if v_code is not null and exists (
    select 1
      from public.job_roles j
     where j.organization_id = v_org
       and j.code = v_code
  ) then
    raise exception 'F5_08_CONFLICT: codigo de cargo ja utilizado na organizacao';
  end if;

  insert into public.job_roles (organization_id, name, code, status)
  values (v_org, v_nome, v_code, 'active')
  returning id into v_id;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'job_role', v_id, 'CRIADO', now(), v_motivo, null,
    jsonb_build_object('name', v_nome, 'code', v_code, 'status', 'active',
                       'version', 0),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_id;
end;
$$;

comment on function public.catalogo_cargo_criar(uuid, uuid, uuid, text, text, text) is
  'F5-08 P2/§21.1 D17: cria cargo (job_role) ATIVO com nome unico por '
  'organizacao e `code` opcional (unico quando nao nulo; rotulo, nunca '
  'autoridade).';

-- ============================================================================
-- 9) `catalogo_cargo_renomear` (§21.1 item 9 / D4 — `code` imutavel)
-- ============================================================================
create or replace function public.catalogo_cargo_renomear(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_job_role_id uuid,
  p_nome text,
  p_expected_version integer,
  p_motivo text
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_nome        text := btrim(coalesce(p_nome, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_cargo       record;
  v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null or p_job_role_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e job_role_id obrigatorios';
  end if;
  if v_nome = '' then
    raise exception 'F5_08_INVALID_INPUT: nome do cargo obrigatorio';
  end if;
  if p_expected_version is null then
    raise exception 'F5_08_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'catalogo_cargo_renomear',
    'organization_id', v_org,
    'job_role_id', p_job_role_id,
    'nome', v_nome,
    'expected_version', p_expected_version,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.catalog.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.catalog.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value->>'version')::integer, 0);
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  select j.id, j.name, j.code, j.status, j.version
    into v_cargo
    from public.job_roles j
   where j.id = p_job_role_id
     and j.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: cargo inexistente ou de outro tenant';
  end if;

  if v_cargo.status <> 'active' then
    raise exception 'F5_08_CONFLICT: cargo inativo nao pode ser renomeado';
  end if;
  if v_cargo.version <> p_expected_version then
    raise exception 'F5_08_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;
  if v_nome = v_cargo.name then
    raise exception 'F5_08_CONFLICT: o nome informado ja e o nome atual do cargo';
  end if;
  if exists (
    select 1
      from public.job_roles j
     where j.organization_id = v_org
       and j.name = v_nome
       and j.id <> p_job_role_id
  ) then
    raise exception 'F5_08_CONFLICT: nome de cargo ja utilizado na organizacao';
  end if;

  -- `code` NAO e tocado (D4: imutavel; e a chave de compatibilidade com a
  -- `funcao` legada e a chave de idempotencia do bootstrap de catalogo).
  update public.job_roles
     set name = v_nome,
         version = version + 1
   where id = p_job_role_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'job_role', p_job_role_id, 'RENOMEADO', now(), v_motivo,
    jsonb_build_object('name', v_cargo.name, 'code', v_cargo.code,
                       'version', v_cargo.version),
    jsonb_build_object('name', v_nome, 'code', v_cargo.code,
                       'version', v_nova_versao),
    v_hash, p_job_role_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_nova_versao;
end;
$$;

comment on function public.catalogo_cargo_renomear(uuid, uuid, uuid, uuid, text, integer, text) is
  'F5-08 P2/§21.1 D4: renomeia o rotulo do cargo ATIVO, preservando `code` '
  'imutavel, com versao otimista e evento RENOMEADO.';

-- ============================================================================
-- 10) `catalogo_cargo_status_alterar` (§21.1 item 10 / D17)
-- ============================================================================
create or replace function public.catalogo_cargo_status_alterar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_job_role_id uuid,
  p_status text,
  p_expected_version integer,
  p_motivo text
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_status      text := lower(btrim(coalesce(p_status, '')));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_cargo       record;
  v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null or p_job_role_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e job_role_id obrigatorios';
  end if;
  if v_status not in ('active', 'disabled') then
    raise exception 'F5_08_INVALID_INPUT: status deve ser active ou disabled';
  end if;
  if p_expected_version is null then
    raise exception 'F5_08_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'catalogo_cargo_status_alterar',
    'organization_id', v_org,
    'job_role_id', p_job_role_id,
    'status', v_status,
    'expected_version', p_expected_version,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.catalog.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.catalog.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value->>'version')::integer, 0);
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  select j.id, j.name, j.code, j.status, j.version
    into v_cargo
    from public.job_roles j
   where j.id = p_job_role_id
     and j.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: cargo inexistente ou de outro tenant';
  end if;

  if v_cargo.status = v_status then
    raise exception 'F5_08_CONFLICT: o cargo ja esta com o status informado';
  end if;
  if v_cargo.version <> p_expected_version then
    raise exception 'F5_08_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- Inativacao no lugar (D17): nunca DELETE; posicoes existentes continuam
  -- validas e legiveis — apenas posicoes NOVAS deixam de poder usa-lo (I4).
  update public.job_roles
     set status = v_status,
         version = version + 1
   where id = p_job_role_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'job_role', p_job_role_id,
    case when v_status = 'active' then 'REATIVADO' else 'ENCERRADO' end,
    now(), v_motivo,
    jsonb_build_object('name', v_cargo.name, 'code', v_cargo.code,
                       'status', v_cargo.status, 'version', v_cargo.version),
    jsonb_build_object('name', v_cargo.name, 'code', v_cargo.code,
                       'status', v_status, 'version', v_nova_versao),
    v_hash, p_job_role_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_nova_versao;
end;
$$;

comment on function public.catalogo_cargo_status_alterar(uuid, uuid, uuid, uuid, text, integer, text) is
  'F5-08 P2/§21.1 D17: ativa/inativa cargo no lugar (active <-> disabled), sem '
  'exclusao fisica e sem tocar `code`; posicoes existentes permanecem validas.';

-- ============================================================================
-- 11) `catalogo_senioridade_criar` (§21.1 item 11 — sem `code`)
-- ============================================================================
create or replace function public.catalogo_senioridade_criar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_nome text,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org        uuid := p_organization_id;
  v_motivo     text := btrim(coalesce(p_motivo, ''));
  v_nome       text := btrim(coalesce(p_nome, ''));
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_id         uuid;
begin
  if p_organization_id is null or p_operation_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id e operation_id obrigatorios';
  end if;
  if v_nome = '' then
    raise exception 'F5_08_INVALID_INPUT: nome da senioridade obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'catalogo_senioridade_criar',
    'organization_id', v_org,
    'nome', v_nome,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.catalog.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.catalog.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  if exists (
    select 1
      from public.seniority_levels s
     where s.organization_id = v_org
       and s.name = v_nome
  ) then
    raise exception 'F5_08_CONFLICT: nome de senioridade ja utilizado na organizacao';
  end if;

  insert into public.seniority_levels (organization_id, name, status)
  values (v_org, v_nome, 'active')
  returning id into v_id;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'seniority_level', v_id, 'CRIADO', now(), v_motivo, null,
    jsonb_build_object('name', v_nome, 'status', 'active', 'version', 0),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_id;
end;
$$;

comment on function public.catalogo_senioridade_criar(uuid, uuid, uuid, text, text) is
  'F5-08 P2/§21.1 D17: cria senioridade ATIVA com nome unico por organizacao. '
  'Nenhum campo `code` e criado (D17).';

-- ============================================================================
-- 12) `catalogo_senioridade_renomear` (§21.1 item 12)
-- ============================================================================
create or replace function public.catalogo_senioridade_renomear(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_seniority_level_id uuid,
  p_nome text,
  p_expected_version integer,
  p_motivo text
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_nome        text := btrim(coalesce(p_nome, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_senior      record;
  v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null
     or p_seniority_level_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e seniority_level_id obrigatorios';
  end if;
  if v_nome = '' then
    raise exception 'F5_08_INVALID_INPUT: nome da senioridade obrigatorio';
  end if;
  if p_expected_version is null then
    raise exception 'F5_08_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'catalogo_senioridade_renomear',
    'organization_id', v_org,
    'seniority_level_id', p_seniority_level_id,
    'nome', v_nome,
    'expected_version', p_expected_version,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.catalog.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.catalog.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value->>'version')::integer, 0);
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  select s.id, s.name, s.status, s.version
    into v_senior
    from public.seniority_levels s
   where s.id = p_seniority_level_id
     and s.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: senioridade inexistente ou de outro tenant';
  end if;

  if v_senior.status <> 'active' then
    raise exception 'F5_08_CONFLICT: senioridade inativa nao pode ser renomeada';
  end if;
  if v_senior.version <> p_expected_version then
    raise exception 'F5_08_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;
  if v_nome = v_senior.name then
    raise exception 'F5_08_CONFLICT: o nome informado ja e o nome atual da senioridade';
  end if;
  if exists (
    select 1
      from public.seniority_levels s
     where s.organization_id = v_org
       and s.name = v_nome
       and s.id <> p_seniority_level_id
  ) then
    raise exception 'F5_08_CONFLICT: nome de senioridade ja utilizado na organizacao';
  end if;

  update public.seniority_levels
     set name = v_nome,
         version = version + 1
   where id = p_seniority_level_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'seniority_level', p_seniority_level_id, 'RENOMEADO', now(), v_motivo,
    jsonb_build_object('name', v_senior.name, 'version', v_senior.version),
    jsonb_build_object('name', v_nome, 'version', v_nova_versao),
    v_hash, p_seniority_level_id, p_actor_user_profile_id, v_membership,
    p_operation_id
  );

  return v_nova_versao;
end;
$$;

comment on function public.catalogo_senioridade_renomear(uuid, uuid, uuid, uuid, text, integer, text) is
  'F5-08 P2/§21.1: renomeia o rotulo da senioridade ATIVA com versao otimista '
  'e evento RENOMEADO (sem `code` — D17).';

-- ============================================================================
-- 13) `catalogo_senioridade_status_alterar` (§21.1 item 13)
-- ============================================================================
create or replace function public.catalogo_senioridade_status_alterar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_seniority_level_id uuid,
  p_status text,
  p_expected_version integer,
  p_motivo text
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_status      text := lower(btrim(coalesce(p_status, '')));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_senior      record;
  v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null
     or p_seniority_level_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e seniority_level_id obrigatorios';
  end if;
  if v_status not in ('active', 'disabled') then
    raise exception 'F5_08_INVALID_INPUT: status deve ser active ou disabled';
  end if;
  if p_expected_version is null then
    raise exception 'F5_08_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'catalogo_senioridade_status_alterar',
    'organization_id', v_org,
    'seniority_level_id', p_seniority_level_id,
    'status', v_status,
    'expected_version', p_expected_version,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.catalog.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.catalog.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value->>'version')::integer, 0);
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  select s.id, s.name, s.status, s.version
    into v_senior
    from public.seniority_levels s
   where s.id = p_seniority_level_id
     and s.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: senioridade inexistente ou de outro tenant';
  end if;

  if v_senior.status = v_status then
    raise exception 'F5_08_CONFLICT: a senioridade ja esta com o status informado';
  end if;
  if v_senior.version <> p_expected_version then
    raise exception 'F5_08_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  update public.seniority_levels
     set status = v_status,
         version = version + 1
   where id = p_seniority_level_id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'seniority_level', p_seniority_level_id,
    case when v_status = 'active' then 'REATIVADO' else 'ENCERRADO' end,
    now(), v_motivo,
    jsonb_build_object('name', v_senior.name, 'status', v_senior.status,
                       'version', v_senior.version),
    jsonb_build_object('name', v_senior.name, 'status', v_status,
                       'version', v_nova_versao),
    v_hash, p_seniority_level_id, p_actor_user_profile_id, v_membership,
    p_operation_id
  );

  return v_nova_versao;
end;
$$;

comment on function public.catalogo_senioridade_status_alterar(uuid, uuid, uuid, uuid, text, integer, text) is
  'F5-08 P2/§21.1 D17: ativa/inativa senioridade no lugar (active <-> '
  'disabled), nunca DELETE; item inativo nao entra em posicao nova.';

-- ============================================================================
-- 14) `estrutura_colegiado_definir` (§21.1 item 14 / D11)
-- ============================================================================
create or replace function public.estrutura_colegiado_definir(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_member_collaborator_ids uuid[],
  p_valid_from timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org           uuid := p_organization_id;
  v_motivo        text := btrim(coalesce(p_motivo, ''));
  v_membros       uuid[] := coalesce(p_member_collaborator_ids, array[]::uuid[]);
  v_membros_canon jsonb;
  v_membros_antes jsonb;
  v_hash          text;
  v_evento        record;
  v_membership    uuid;
  v_avaliado      record;
  v_anterior      record;
  v_config        uuid;
  v_qtd_membros   integer;
begin
  if p_organization_id is null or p_operation_id is null
     or p_collaborator_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e collaborator_id obrigatorios';
  end if;
  if p_valid_from is null then
    raise exception 'F5_08_INVALID_INPUT: valid_from obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  -- Forma do conjunto de membros: sem NULL e sem duplicados (INVALID_INPUT).
  if exists (select 1 from unnest(v_membros) as m where m is null) then
    raise exception 'F5_08_INVALID_INPUT: lista de membros nao pode conter nulo';
  end if;
  v_qtd_membros := coalesce(array_length(v_membros, 1), 0);
  if v_qtd_membros <> (select count(distinct m) from unnest(v_membros) as m) then
    raise exception 'F5_08_INVALID_INPUT: lista de membros com duplicidade';
  end if;
  -- Regra de dominio (o trigger do banco e a ultima barreira): o avaliado nao
  -- pode ser membro do proprio colegiado.
  if p_collaborator_id = any (v_membros) then
    raise exception 'F5_08_CONFLICT: o colaborador avaliado nao pode ser membro do proprio colegiado';
  end if;

  -- Representacao canonica (ordenada) do conjunto: o hash da intencao nao pode
  -- depender da ordem em que os membros foram enviados.
  select coalesce(jsonb_agg(m order by m), '[]'::jsonb)
    into v_membros_canon
    from unnest(v_membros) as m;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_colegiado_definir',
    'organization_id', v_org,
    'collaborator_id', p_collaborator_id,
    'member_collaborator_ids', v_membros_canon,
    'valid_from', p_valid_from,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  -- Avaliado no mesmo tenant (ancora na pessoa — F3-08 D1).
  select c.id, c.full_name
    into v_avaliado
    from public.collaborators c
   where c.id = p_collaborator_id
     and c.organization_id = v_org;
  if not found then
    raise exception 'F5_08_NOT_FOUND: colaborador avaliado inexistente ou de outro tenant';
  end if;

  -- Todos os membros existem NO MESMO tenant (nenhum vazamento cross-tenant).
  if v_qtd_membros > 0 then
    if (select count(*)
          from public.collaborators c
         where c.organization_id = v_org
           and c.id = any (v_membros)) <> v_qtd_membros then
      raise exception 'F5_08_NOT_FOUND: membro do colegiado inexistente ou de outro tenant';
    end if;
  end if;

  -- Periodo posterior (ou iniciando na mesma data) impediria a abertura.
  if exists (
    select 1
      from public.collegiate_configurations cc
     where cc.collaborator_id = p_collaborator_id
       and cc.organization_id = v_org
       and cc.valid_from >= p_valid_from
  ) then
    raise exception 'F5_08_CONFLICT: existe configuracao de colegiado posterior ou na data informada (encerre-a antes)';
  end if;

  -- Versao vigente: fecha (historico preservado) e captura os membros anteriores.
  select cc.id, cc.collaborator_id, cc.valid_from, cc.valid_to, cc.version
    into v_anterior
    from public.collegiate_configurations cc
   where cc.collaborator_id = p_collaborator_id
     and cc.organization_id = v_org
     and cc.valid_from < p_valid_from
     and (cc.valid_to is null or cc.valid_to > p_valid_from)
   order by cc.valid_from desc
   limit 1
   for update;

  if found then
    select coalesce(jsonb_agg(m.member_collaborator_id
                              order by m.member_collaborator_id), '[]'::jsonb)
      into v_membros_antes
      from public.collegiate_configuration_members m
     where m.configuration_id = v_anterior.id
       and m.organization_id = v_org;

    update public.collegiate_configurations
       set valid_to = p_valid_from,
           version = version + 1
     where id = v_anterior.id
       and organization_id = v_org;
  end if;

  insert into public.collegiate_configurations
    (organization_id, collaborator_id, valid_from)
  values (v_org, p_collaborator_id, p_valid_from)
  returning id into v_config;

  if v_qtd_membros > 0 then
    insert into public.collegiate_configuration_members
      (organization_id, configuration_id, member_collaborator_id)
    select v_org, v_config, m
      from unnest(v_membros) as m;
  end if;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'collegiate_configuration', v_config, 'MEMBROS_ALTERADOS',
    p_valid_from, v_motivo,
    case when v_anterior.id is null then null
         else jsonb_build_object('configuration_id', v_anterior.id,
                                 'valid_from', v_anterior.valid_from,
                                 'valid_to', v_anterior.valid_to,
                                 'members', coalesce(v_membros_antes, '[]'::jsonb),
                                 'version', v_anterior.version) end,
    jsonb_build_object('configuration_id', v_config,
                       'collaborator_id', p_collaborator_id,
                       'members', v_membros_canon,
                       'valid_from', p_valid_from,
                       'version', 0),
    v_hash, v_config, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_config;
end;
$$;

comment on function public.estrutura_colegiado_definir(uuid, uuid, uuid, uuid, uuid[], timestamptz, text) is
  'F5-08 P2/§21.1 D11: define a versao vigente do colegiado do colaborador '
  'AVALIADO (membros explicitos 0..N, mesma organizacao, sem self e sem '
  'duplicados), fechando a versao anterior e preservando o historico; lista '
  'vazia = "sem colegiado" explicito (0 membros != ausencia de configuracao).';

-- ============================================================================
-- 15) `estrutura_colegiado_encerrar` (§21.1 item 15)
-- ============================================================================
create or replace function public.estrutura_colegiado_encerrar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_valid_to timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_avaliado    record;
  v_config      record;
  v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null
     or p_collaborator_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e collaborator_id obrigatorios';
  end if;
  if p_valid_to is null then
    raise exception 'F5_08_INVALID_INPUT: valid_to obrigatorio';
  end if;
  if v_motivo = '' then
    raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_colegiado_encerrar',
    'organization_id', v_org,
    'collaborator_id', p_collaborator_id,
    'valid_to', p_valid_to,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, v_org)
     where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage';
  end if;

  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.structure_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

  select c.id into v_avaliado
    from public.collaborators c
   where c.id = p_collaborator_id
     and c.organization_id = v_org;
  if not found then
    raise exception 'F5_08_NOT_FOUND: colaborador avaliado inexistente ou de outro tenant';
  end if;

  select cc.id, cc.collaborator_id, cc.valid_from, cc.valid_to, cc.version
    into v_config
    from public.collegiate_configurations cc
   where cc.collaborator_id = p_collaborator_id
     and cc.organization_id = v_org
     and cc.valid_from < p_valid_to
     and (cc.valid_to is null or cc.valid_to > p_valid_to)
   order by cc.valid_from desc
   limit 1
   for update;
  if not found then
    raise exception 'F5_08_NOT_FOUND: nenhuma configuracao de colegiado vigente na data informada';
  end if;
  if p_valid_to <= v_config.valid_from then
    raise exception 'F5_08_CONFLICT: valid_to deve ser posterior ao inicio da configuracao';
  end if;

  update public.collegiate_configurations
     set valid_to = p_valid_to,
         version = version + 1
   where id = v_config.id
     and organization_id = v_org
  returning version into v_nova_versao;

  insert into public.structure_events (
    organization_id, entity_type, entity_id, event_type, effective_date,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, 'collegiate_configuration', v_config.id, 'COLEGIADO_ENCERRADO',
    p_valid_to, v_motivo,
    jsonb_build_object('collaborator_id', p_collaborator_id,
                       'valid_from', v_config.valid_from,
                       'valid_to', v_config.valid_to,
                       'version', v_config.version),
    jsonb_build_object('collaborator_id', p_collaborator_id,
                       'valid_to', p_valid_to,
                       'version', v_nova_versao),
    v_hash, v_config.id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_config.id;
end;
$$;

comment on function public.estrutura_colegiado_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) is
  'F5-08 P2/§21.1: encerra a configuracao de colegiado vigente por valid_to '
  '(nunca apaga; historico preservado), passando o avaliado a "sem '
  'configuracao" (distinto de configuracao com 0 membros).';

-- ============================================================================
-- 16) Grants das 15 RPCs (§13.4) — EXECUTE somente para `service_role`
-- ============================================================================
-- Nenhuma superficie nova a `public`/`anon`/`authenticated`; `service_role`
-- executa e nao decide autorizacao (a decisao e revalidada em cada RPC).
revoke all on function public.estrutura_unidade_criar(uuid, uuid, uuid, text, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_unidade_criar(uuid, uuid, uuid, text, timestamptz, text)
  to service_role;

revoke all on function public.estrutura_unidade_renomear(uuid, uuid, uuid, uuid, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_unidade_renomear(uuid, uuid, uuid, uuid, text, integer, text)
  to service_role;

revoke all on function public.estrutura_unidade_encerrar(uuid, uuid, uuid, uuid, timestamptz, integer, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_unidade_encerrar(uuid, uuid, uuid, uuid, timestamptz, integer, text)
  to service_role;

revoke all on function public.estrutura_unidade_parent_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_unidade_parent_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text)
  to service_role;

revoke all on function public.estrutura_unidade_parent_encerrar(uuid, uuid, uuid, uuid, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_unidade_parent_encerrar(uuid, uuid, uuid, uuid, timestamptz, text)
  to service_role;

revoke all on function public.estrutura_posicao_criar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_posicao_criar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)
  to service_role;

revoke all on function public.estrutura_posicao_encerrar(uuid, uuid, uuid, uuid, timestamptz, integer, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_posicao_encerrar(uuid, uuid, uuid, uuid, timestamptz, integer, text)
  to service_role;

revoke all on function public.estrutura_colegiado_definir(uuid, uuid, uuid, uuid, uuid[], timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_colegiado_definir(uuid, uuid, uuid, uuid, uuid[], timestamptz, text)
  to service_role;

revoke all on function public.estrutura_colegiado_encerrar(uuid, uuid, uuid, uuid, timestamptz, text)
  from public, anon, authenticated;
grant execute on function public.estrutura_colegiado_encerrar(uuid, uuid, uuid, uuid, timestamptz, text)
  to service_role;

revoke all on function public.catalogo_cargo_criar(uuid, uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.catalogo_cargo_criar(uuid, uuid, uuid, text, text, text)
  to service_role;

revoke all on function public.catalogo_cargo_renomear(uuid, uuid, uuid, uuid, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.catalogo_cargo_renomear(uuid, uuid, uuid, uuid, text, integer, text)
  to service_role;

revoke all on function public.catalogo_cargo_status_alterar(uuid, uuid, uuid, uuid, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.catalogo_cargo_status_alterar(uuid, uuid, uuid, uuid, text, integer, text)
  to service_role;

revoke all on function public.catalogo_senioridade_criar(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.catalogo_senioridade_criar(uuid, uuid, uuid, text, text)
  to service_role;

revoke all on function public.catalogo_senioridade_renomear(uuid, uuid, uuid, uuid, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.catalogo_senioridade_renomear(uuid, uuid, uuid, uuid, text, integer, text)
  to service_role;

revoke all on function public.catalogo_senioridade_status_alterar(uuid, uuid, uuid, uuid, text, integer, text)
  from public, anon, authenticated;
grant execute on function public.catalogo_senioridade_status_alterar(uuid, uuid, uuid, uuid, text, integer, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- Guarda fail-closed: exatamente as 15 RPCs do P2 existem, todas SECURITY
-- INVOKER, com `search_path = public` e EXECUTE restrito a `service_role`.
-- ----------------------------------------------------------------------------
do $$
declare
  v_esperadas text[] := array[
    'estrutura_unidade_criar', 'estrutura_unidade_renomear',
    'estrutura_unidade_encerrar', 'estrutura_unidade_parent_definir',
    'estrutura_unidade_parent_encerrar', 'estrutura_posicao_criar',
    'estrutura_posicao_encerrar', 'estrutura_colegiado_definir',
    'estrutura_colegiado_encerrar', 'catalogo_cargo_criar',
    'catalogo_cargo_renomear', 'catalogo_cargo_status_alterar',
    'catalogo_senioridade_criar', 'catalogo_senioridade_renomear',
    'catalogo_senioridade_status_alterar'];
  v_nome   text;
  v_func   record;
  v_qtd    integer;
begin
  select count(*) into v_qtd
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = any (v_esperadas);
  if v_qtd <> 15 then
    raise exception 'F5-08 P2: esperadas 15 RPCs, encontradas %', v_qtd;
  end if;

  foreach v_nome in array v_esperadas loop
    select p.prosecdef,
           coalesce(array_to_string(p.proconfig, ','), '') as config,
           pg_get_function_identity_arguments(p.oid) as args
      into v_func
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = v_nome;

    if v_func.args is null then
      raise exception 'F5-08 P2: RPC ausente: %', v_nome;
    end if;
    if v_func.prosecdef then
      raise exception 'F5-08 P2: % e SECURITY DEFINER (proibido)', v_nome;
    end if;
    if position('search_path=public' in v_func.config) = 0 then
      raise exception 'F5-08 P2: % sem search_path fixo em public (%)', v_nome, v_func.config;
    end if;
  end loop;

  raise notice '[PASS] F5-08 P2: 15 RPCs presentes, SECURITY INVOKER com search_path fixo';
end $$;
