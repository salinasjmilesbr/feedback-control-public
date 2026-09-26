-- F6 / Issue #375 — troca atômica de posição.
-- Fechar A e abrir B são um único fato transacional; falha em qualquer guarda
-- desfaz integralmente a mutação e os eventos.

create or replace function public.estrutura_ocupacao_trocar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_current_position_id uuid,
  p_new_position_id uuid,
  p_vigencia timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_vigencia timestamptz;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_hash text;
  v_evento record;
  v_org uuid;
  v_membership uuid;
  v_old record;
  v_new_id uuid;
  v_op_close uuid;
begin
  if p_operation_id is null or p_collaborator_id is null
     or p_current_position_id is null or p_new_position_id is null then
    raise exception 'F5_07_INVALID_INPUT: ids obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if p_current_position_id = p_new_position_id then
    raise exception 'F5_07_INVALID_INPUT: posicao atual e nova devem ser diferentes';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_vigencia := public.f6_vigencia_civil_utc(p_vigencia);
  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_ocupacao_trocar',
    'organization_id', p_organization_id,
    'collaborator_id', p_collaborator_id,
    'current_position_id', p_current_position_id,
    'new_position_id', p_new_position_id,
    'vigencia', v_vigencia,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || p_organization_id::text));

  if exists (
    select 1 from public.collaborator_events e
     where e.organization_id = p_organization_id
       and e.collaborator_id = p_collaborator_id
  and e.position_id in (p_current_position_id, p_new_position_id)
       and e.event_type in ('OCUPACAO_INICIADA', 'OCUPACAO_ENCERRADA')
       and e.effective_date = v_vigencia
  ) then
    raise exception 'F5_07_CONFLICT: segunda transicao de ocupacao na mesma relacao e data civil';
  end if;

  select c.organization_id into v_org from public.collaborators c
   where c.id = p_collaborator_id for update;
  if not found or v_org is distinct from p_organization_id then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  select o.id, o.organizational_position_id, o.valid_from, o.valid_to
    into v_old from public.occupations o
   where o.organization_id = v_org
     and o.collaborator_id = p_collaborator_id
     and o.organizational_position_id = p_current_position_id
     and o.valid_from < v_vigencia
     and (o.valid_to is null or o.valid_to > v_vigencia);
  if not found then
    raise exception 'F5_07_NOT_FOUND: ocupacao atual inexistente ou nao vigente na data';
  end if;

  if not exists (
    select 1 from public.organizational_positions p
     where p.id = p_new_position_id and p.organization_id = v_org
       and p.valid_from <= v_vigencia
       and (p.valid_to is null or p.valid_to > v_vigencia)
  ) then
    raise exception 'F5_07_CONFLICT: nova posicao inexistente ou nao vigente na data';
  end if;
  if exists (
    select 1 from public.occupations o
     where o.organization_id = v_org
       and o.organizational_position_id = p_new_position_id
       and o.valid_from <= v_vigencia
       and (o.valid_to is null or o.valid_to > v_vigencia)
  ) then
    raise exception 'F5_07_CONFLICT: nova posicao ja possui ocupante vigente nessa data';
  end if;

  update public.occupations set valid_to = v_vigencia, version = version + 1
   where id = v_old.id;
  insert into public.occupations
    (organization_id, collaborator_id, organizational_position_id, reason, valid_from)
  values (v_org, p_collaborator_id, p_new_position_id, v_motivo, v_vigencia)
  returning id into v_new_id;

  select m.id into v_membership from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_collaborator_id, p_new_position_id, 'OCUPACAO_INICIADA', v_vigencia,
    'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    jsonb_build_object('occupation_id', v_old.id, 'position_id', p_current_position_id,
                       'valid_to', v_vigencia),
    jsonb_build_object('occupation_id', v_new_id, 'position_id', p_new_position_id,
                       'valid_from', v_vigencia), v_hash, v_new_id,
    p_actor_user_profile_id, v_membership, p_operation_id
  );

  v_op_close := md5(p_operation_id::text || ':OCUPACAO_ENCERRADA')::uuid;
  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_collaborator_id, p_current_position_id, 'OCUPACAO_ENCERRADA', v_vigencia,
    'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    jsonb_build_object('occupation_id', v_old.id, 'position_id', p_current_position_id,
                       'valid_from', v_old.valid_from),
    jsonb_build_object('valid_to', v_vigencia, 'replaced_by', v_new_id), v_hash, v_old.id,
    p_actor_user_profile_id, v_membership, v_op_close
  );
  return v_new_id;
end;
$$;

revoke all on function public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text) from public, anon, authenticated;
grant execute on function public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text) to service_role;
