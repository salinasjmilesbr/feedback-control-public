-- F6-A22 P3 (Issue #338)
-- Configuracao administrativa soberana de PEOPLE_MANAGEMENT por posicao.
-- SECURITY INVOKER; a fronteira privilegiada e a Edge existente/service_role.

alter table public.organizational_position_responsibility_events
  add column operation_id uuid,
  add column payload_hash text;

alter table public.organizational_position_responsibility_events
  add constraint ck_opr_events_payload_hash
  check (payload_hash is null or payload_hash ~ '^[0-9a-f]{64}$');

create unique index uq_opr_events_operation
  on public.organizational_position_responsibility_events (organization_id, operation_id)
  where operation_id is not null;

create or replace function public.audit_opr_change()
returns trigger language plpgsql set search_path = public as $$
declare
  v_actor uuid;
  v_operation uuid;
  v_hash text;
begin
  v_actor := coalesce(
    nullif(current_setting('f6_a22.actor_user_profile_id', true), '')::uuid,
    nullif(current_setting('request.jwt.claim.sub', true), '')::uuid,
    new.created_by
  );
  v_operation := nullif(current_setting('f6_a22.operation_id', true), '')::uuid;
  v_hash := nullif(current_setting('f6_a22.payload_hash', true), '');
  insert into public.organizational_position_responsibility_events
    (organization_id, responsibility_id, event_type, actor_user_profile_id,
     operation_id, payload_hash, payload)
  values (
    new.organization_id, new.id,
    case when tg_op = 'INSERT' then 'CREATED'
         when new.status = 'revoked' then 'REVOKED' else 'UPDATED' end,
    v_actor, v_operation, v_hash,
    jsonb_build_object('version', new.version, 'status', new.status,
                       'valid_from', new.valid_from, 'valid_to', new.valid_to)
  );
  return new;
end;
$$;

create or replace function public.estrutura_responsabilidade_criar(
  p_organization_id uuid,
  p_position_id uuid,
  p_responsibility_code text,
  p_valid_from timestamptz,
  p_valid_to timestamptz,
  p_operation_id uuid,
  p_actor_user_profile_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_hash text;
  v_event record;
  v_id uuid;
begin
  if p_organization_id is null or p_position_id is null
     or p_operation_id is null or p_actor_user_profile_id is null
     or p_valid_from is null or p_responsibility_code is null then
    raise exception 'F6_A22_INVALID_INPUT: campos obrigatorios ausentes';
  end if;
  if p_responsibility_code <> 'PEOPLE_MANAGEMENT' then
    raise exception 'F6_A22_INVALID_INPUT: responsabilidade nao catalogada';
  end if;
  if p_valid_to is not null and p_valid_to <= p_valid_from then
    raise exception 'F6_A22_INVALID_INPUT: valid_to deve ser posterior a valid_from';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'estrutura_responsabilidade_criar',
    'organization_id', p_organization_id, 'position_id', p_position_id,
    'responsibility_code', p_responsibility_code, 'valid_from', p_valid_from,
    'valid_to', p_valid_to
  )::text, 'UTF8')), 'hex');

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F6_A22_FORBIDDEN: ator sem membership ativa na organizacao';
  end if;
  if not exists (
    select 1 from public.resolver_capabilities_escopos_efetivas(
      p_actor_user_profile_id, p_organization_id)
    where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F6_A22_FORBIDDEN: ator sem org.structure.manage';
  end if;
  if not exists (
    select 1 from public.organizational_positions p
     where p.id = p_position_id and p.organization_id = p_organization_id
  ) then
    raise exception 'F6_A22_NOT_FOUND: posicao inexistente no tenant';
  end if;

  perform pg_advisory_xact_lock(hashtext('position_responsibilities:' || p_organization_id::text));

  select e.responsibility_id, e.payload_hash into v_event
    from public.organizational_position_responsibility_events e
   where e.organization_id = p_organization_id and e.operation_id = p_operation_id;
  if found then
    if v_event.payload_hash is distinct from v_hash then
      raise exception 'F6_A22_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_event.responsibility_id;
  end if;

  perform set_config('f6_a22.actor_user_profile_id', p_actor_user_profile_id::text, true);
  perform set_config('f6_a22.operation_id', p_operation_id::text, true);
  perform set_config('f6_a22.payload_hash', v_hash, true);
  insert into public.organizational_position_responsibilities
    (organization_id, position_id, responsibility_code, valid_from, valid_to, created_by)
  values
    (p_organization_id, p_position_id, p_responsibility_code, p_valid_from, p_valid_to,
     p_actor_user_profile_id)
  returning id into v_id;
  return v_id;
exception when exclusion_violation then
  raise exception 'F6_A22_CONFLICT: responsabilidade sobreposta';
end;
$$;

create or replace function public.estrutura_responsabilidade_revogar(
  p_responsibility_id uuid,
  p_valid_to timestamptz,
  p_expected_version integer,
  p_operation_id uuid,
  p_actor_user_profile_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_atual record;
  v_event record;
  v_hash text;
begin
  if p_responsibility_id is null or p_valid_to is null or p_expected_version is null
     or p_operation_id is null or p_actor_user_profile_id is null then
    raise exception 'F6_A22_INVALID_INPUT: campos obrigatorios ausentes';
  end if;
  select r.* into v_atual
    from public.organizational_position_responsibilities r
   where r.id = p_responsibility_id
   for update;
  if not found then
    raise exception 'F6_A22_NOT_FOUND: responsabilidade inexistente';
  end if;
  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_atual.organization_id) then
    raise exception 'F6_A22_FORBIDDEN: ator sem membership ativa na organizacao';
  end if;
  if not exists (
    select 1 from public.resolver_capabilities_escopos_efetivas(
      p_actor_user_profile_id, v_atual.organization_id)
    where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F6_A22_FORBIDDEN: ator sem org.structure.manage';
  end if;
  perform pg_advisory_xact_lock(hashtext('position_responsibilities:' || v_atual.organization_id::text));

  select e.responsibility_id, e.payload_hash into v_event
    from public.organizational_position_responsibility_events e
   where e.organization_id = v_atual.organization_id and e.operation_id = p_operation_id;
  if found then
    v_hash := encode(sha256(convert_to(jsonb_build_object(
      'operacao', 'estrutura_responsabilidade_revogar', 'responsibility_id', p_responsibility_id,
      'valid_to', p_valid_to, 'expected_version', p_expected_version
    )::text, 'UTF8')), 'hex');
    if v_event.payload_hash is distinct from v_hash then
      raise exception 'F6_A22_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_event.responsibility_id;
  end if;
  if v_atual.version <> p_expected_version then
    raise exception 'F6_A22_CONFLICT: expected_version divergente';
  end if;
  if p_valid_to <= v_atual.valid_from
     or (v_atual.valid_to is not null and p_valid_to > v_atual.valid_to) then
    raise exception 'F6_A22_INVALID_INPUT: encerramento fora da vigencia';
  end if;
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'estrutura_responsabilidade_revogar', 'responsibility_id', p_responsibility_id,
    'valid_to', p_valid_to, 'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');
  perform set_config('f6_a22.actor_user_profile_id', p_actor_user_profile_id::text, true);
  perform set_config('f6_a22.operation_id', p_operation_id::text, true);
  perform set_config('f6_a22.payload_hash', v_hash, true);
  update public.organizational_position_responsibilities
     set valid_to = p_valid_to, status = 'revoked', version = version + 1
   where id = p_responsibility_id and version = p_expected_version;
  if not found then
    raise exception 'F6_A22_CONFLICT: responsabilidade alterada concorrentemente';
  end if;
  return p_responsibility_id;
end;
$$;

create or replace function public.estrutura_responsabilidades_consultar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid
)
returns table (
  id uuid, organization_id uuid, position_id uuid, responsibility_code text,
  valid_from timestamptz, valid_to timestamptz, status text, version integer,
  created_by uuid, created_at timestamptz, updated_at timestamptz
)
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F6_A22_FORBIDDEN: ator sem membership ativa na organizacao';
  end if;
  if not exists (
    select 1 from public.resolver_capabilities_escopos_efetivas(
      p_actor_user_profile_id, p_organization_id)
    where capability_code = 'org.structure.manage'
  ) then
    raise exception 'F6_A22_FORBIDDEN: ator sem org.structure.manage';
  end if;
  return query
    select r.id, r.organization_id, r.position_id, r.responsibility_code,
           r.valid_from, r.valid_to, r.status, r.version, r.created_by,
           r.created_at, r.updated_at
      from public.organizational_position_responsibilities r
     where r.organization_id = p_organization_id
     order by r.valid_from, r.id;
end;
$$;

revoke all on function public.estrutura_responsabilidade_criar(uuid, uuid, text, timestamptz, timestamptz, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.estrutura_responsabilidade_revogar(uuid, timestamptz, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.estrutura_responsabilidades_consultar(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.estrutura_responsabilidade_criar(uuid, uuid, text, timestamptz, timestamptz, uuid, uuid) to service_role;
grant execute on function public.estrutura_responsabilidade_revogar(uuid, timestamptz, integer, uuid, uuid) to service_role;
grant execute on function public.estrutura_responsabilidades_consultar(uuid, uuid) to service_role;
