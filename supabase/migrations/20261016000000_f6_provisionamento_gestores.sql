-- Provisionamento funcional de gestores: role + alcance estrutural atomicos.
-- A migration e aditiva: assignments, scopes e trilha soberana existentes sao
-- reutilizados; nenhuma identidade ou fonte estrutural e alterada.

alter table public.privilege_mutation_audit
  add column if not exists operation_id uuid,
  add column if not exists payload_hash text,
  add column if not exists scope_type text,
  add column if not exists reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.privilege_mutation_audit'::regclass
       and conname = 'ck_privilege_mutation_audit_scope_type'
  ) then
    alter table public.privilege_mutation_audit
      add constraint ck_privilege_mutation_audit_scope_type
      check (scope_type is null or scope_type in ('DIRECT_REPORTS', 'DESCENDANTS'));
  end if;
end
$$;

create unique index if not exists uq_privilege_mutation_audit_operation_id
  on public.privilege_mutation_audit (operation_id)
  where operation_id is not null;

create or replace function public.gerenciar_acesso_funcional_rpc(
  p_operation_id uuid,
  p_action text,
  p_membership_id uuid,
  p_access_role_id uuid,
  p_scope_type text,
  p_reason text,
  p_actor_user_profile_id uuid
)
returns table (assignment_id uuid, scope_id uuid, replay boolean)
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org uuid;
  v_target_user uuid;
  v_target_profile_status text;
  v_role_org uuid;
  v_role_status text;
  v_assignment uuid;
  v_scope uuid;
  v_hash text;
  v_old_hash text;
begin
  if p_operation_id is null or p_actor_user_profile_id is null
     or p_membership_id is null or p_access_role_id is null
     or p_action not in ('grant', 'revoke')
     or p_scope_type not in ('DIRECT_REPORTS', 'DESCENDANTS')
     or nullif(btrim(p_reason), '') is null then
    raise exception 'F6_GESTORES_INVALID_INPUT: parametros obrigatorios invalidos';
  end if;

  select m.organization_id, m.user_profile_id, up.status
    into v_org, v_target_user, v_target_profile_status
    from public.user_organization_memberships m
    join public.user_profiles up on up.id = m.user_profile_id
   where m.id = p_membership_id
     and m.status = 'active';
  if not found then
    raise exception 'F6_GESTORES_NOT_FOUND: membership alvo inexistente ou inativa';
  end if;
  if v_target_profile_status <> 'active' then
    raise exception 'F6_GESTORES_FORBIDDEN: perfil da membership alvo nao esta ativo';
  end if;

  if v_target_user = p_actor_user_profile_id then
    raise exception 'F6_GESTORES_FORBIDDEN: self-escalation negada';
  end if;

  select r.organization_id, r.status
    into v_role_org, v_role_status
    from public.access_roles r
   where r.id = p_access_role_id;
  if not found or v_role_status <> 'active' then
    raise exception 'F6_GESTORES_FORBIDDEN: role inexistente, desabilitada ou inativa';
  end if;
  if v_role_org is not null and v_role_org <> v_org then
    raise exception 'F6_GESTORES_FORBIDDEN: role de outro tenant';
  end if;
  if exists (
    select 1 from public.access_roles r
     where r.id = p_access_role_id and r.is_system = true and r.name = 'admin'
  ) or exists (
    select 1
      from public.access_role_capabilities rc
      join public.capabilities c on c.id = rc.capability_id
     where rc.access_role_id = p_access_role_id
       and c.code in ('access_role.manage', 'membership.manage')
  ) then
    raise exception 'F6_GESTORES_FORBIDDEN: role administrativa nao e acesso funcional';
  end if;

  if not public.usuario_eh_administrador(p_actor_user_profile_id, v_org) then
    raise exception 'F6_GESTORES_FORBIDDEN: ator sem autoridade administrativa';
  end if;

  if not exists (
    select 1 from public.membership_collaborator_links l
     where l.membership_id = p_membership_id and l.status = 'active'
  ) then
    raise exception 'F6_GESTORES_FORBIDDEN: membership sem vinculo ativo';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'action', p_action,
    'membership_id', p_membership_id,
    'access_role_id', p_access_role_id,
    'scope_type', p_scope_type,
    'reason', btrim(p_reason)
  )::text, 'UTF8')), 'hex');

  perform pg_advisory_xact_lock(
    hashtextextended('functional-access:' || v_org::text || ':' || p_membership_id::text, 0)
  );

  select a.payload_hash
    into v_old_hash
    from public.privilege_mutation_audit a
   where a.operation_id = p_operation_id
   limit 1;
  if v_old_hash is not null then
    if v_old_hash <> v_hash then
      raise exception 'F6_GESTORES_CONFLICT: operation_id reutilizado com payload divergente';
    end if;
    select ar.id, s.id
      into assignment_id, scope_id
      from public.privilege_mutation_audit a
      join public.membership_access_role_assignments ar
        on ar.membership_id = a.membership_id
       and ar.access_role_id = a.access_role_id
      left join public.access_role_assignment_scopes s
        on s.assignment_id = ar.id
       and s.scope_type = a.scope_type
     where a.operation_id = p_operation_id;
    replay := true;
    return next;
    return;
  end if;

  if p_action = 'grant' then
    perform public.conceder_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);
    select a.id into v_assignment
      from public.membership_access_role_assignments a
     where a.membership_id = p_membership_id
       and a.access_role_id = p_access_role_id
       and a.status = 'active';
    if v_assignment is null then
      raise exception 'F6_GESTORES_INTERNAL: assignment nao criada';
    end if;
    insert into public.access_role_assignment_scopes
      (assignment_id, organization_id, scope_type, status, created_by)
    values
      (v_assignment, v_org, p_scope_type, 'active', p_actor_user_profile_id)
    on conflict on constraint uq_access_role_assignment_scopes_assignment_type do update
      set status = 'active', updated_at = now(), version =
        public.access_role_assignment_scopes.version + 1
    returning id into v_scope;
  else
    select a.id into v_assignment
      from public.membership_access_role_assignments a
     where a.membership_id = p_membership_id
       and a.access_role_id = p_access_role_id;
    if v_assignment is null then
      raise exception 'F6_GESTORES_NOT_FOUND: assignment inexistente';
    end if;
    update public.access_role_assignment_scopes
       set status = 'revoked', updated_at = now(), version = version + 1
     where public.access_role_assignment_scopes.assignment_id = v_assignment
       and public.access_role_assignment_scopes.scope_type = p_scope_type
     returning id into v_scope;
    if v_scope is null then
      raise exception 'F6_GESTORES_NOT_FOUND: scope inexistente';
    end if;
    perform public.revogar_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);
  end if;

  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id,
     operation_id, payload_hash, scope_type, reason)
  values
    (v_org, p_membership_id, p_access_role_id, p_action, p_actor_user_profile_id,
     p_operation_id, v_hash, p_scope_type, btrim(p_reason));

  assignment_id := v_assignment;
  scope_id := v_scope;
  replay := false;
  return next;
end;
$$;

revoke all on function public.gerenciar_acesso_funcional_rpc(uuid, text, uuid, uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.gerenciar_acesso_funcional_rpc(uuid, text, uuid, uuid, text, text, uuid)
  to service_role;

comment on function public.gerenciar_acesso_funcional_rpc(uuid, text, uuid, uuid, text, text, uuid) is
  'Provisionamento funcional multi-tenant: role + scope estrutural e trilha '
  'append-only na mesma transacao; auth/profile/membership/link e estrutura '
  'organizacional permanecem intocados.';
