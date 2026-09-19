-- F6-A19/#306: role avaliativa mínima, sem alterar o bundle admin.
-- A role concede somente evaluation.read e o RPC fixa ASSIGNED.

insert into public.access_roles (id, name, status, is_system, organization_id)
values ('c0000000-0000-4000-8000-0000000000f2', 'evaluator', 'active', true, null)
on conflict (id) do nothing;

insert into public.access_role_capabilities (access_role_id, capability_id)
select 'c0000000-0000-4000-8000-0000000000f2', c.id
  from public.capabilities c
 where c.code = 'evaluation.read'
on conflict (access_role_id, capability_id) do nothing;

create or replace function public.f6_306_conceder_evaluator(
  p_target_user_profile_id uuid,
  p_organization_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_membership uuid;
  v_role uuid;
  v_assignment uuid;
  v_scope_ativo boolean;
begin
  if p_target_user_profile_id is null or p_organization_id is null or p_actor_user_profile_id is null then
    raise exception 'F6_306_INVALID_INPUT';
  end if;
  if p_target_user_profile_id = p_actor_user_profile_id then
    raise exception 'F6_306_SELF_ESCALATION';
  end if;
  if not public.usuario_eh_administrador(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F6_306_FORBIDDEN';
  end if;

  select id into v_membership
    from public.user_organization_memberships
   where user_profile_id = p_target_user_profile_id
     and organization_id = p_organization_id
     and status = 'active';
  if v_membership is null then raise exception 'F6_306_TARGET_MEMBERSHIP_NOT_FOUND'; end if;

  select id into v_role
    from public.access_roles
   where name = 'evaluator' and is_system = true and status = 'active' and organization_id is null;
  if v_role is null then raise exception 'F6_306_ROLE_NOT_FOUND'; end if;

  perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);
  select id into v_assignment
    from public.membership_access_role_assignments
   where membership_id = v_membership and organization_id = p_organization_id
     and access_role_id = v_role and status = 'active';
  if v_assignment is null then raise exception 'F6_306_ASSIGNMENT_NOT_PERSISTED'; end if;
  select exists (select 1 from public.access_role_assignment_scopes where assignment_id = v_assignment and scope_type = 'ASSIGNED' and status = 'active') into v_scope_ativo;

  insert into public.access_role_assignment_scopes
    (assignment_id, organization_id, scope_type, status, created_by)
  values (v_assignment, p_organization_id, 'ASSIGNED', 'active', p_actor_user_profile_id)
  on conflict (assignment_id, scope_type) do update
    set status = 'active', created_by = excluded.created_by;
  if not coalesce(v_scope_ativo, false) then
    insert into public.privilege_mutation_audit
      (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
    values (p_organization_id, v_membership, v_role, 'grant', p_actor_user_profile_id);
  end if;
end;
$$;

create or replace function public.f6_306_revogar_evaluator(
  p_target_user_profile_id uuid,
  p_organization_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_membership uuid;
  v_role uuid;
  v_assignment uuid;
  v_scope_ativo boolean;
begin
  if p_target_user_profile_id is null or p_organization_id is null or p_actor_user_profile_id is null then
    raise exception 'F6_306_INVALID_INPUT';
  end if;
  if p_target_user_profile_id = p_actor_user_profile_id then
    raise exception 'F6_306_SELF_ESCALATION';
  end if;
  if not public.usuario_eh_administrador(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F6_306_FORBIDDEN';
  end if;
  select id into v_membership from public.user_organization_memberships
   where user_profile_id = p_target_user_profile_id and organization_id = p_organization_id and status = 'active';
  select id into v_role from public.access_roles
   where name = 'evaluator' and is_system = true and status = 'active' and organization_id is null;
  if v_membership is null or v_role is null then raise exception 'F6_306_NOT_FOUND'; end if;
  select id into v_assignment from public.membership_access_role_assignments
   where membership_id = v_membership and organization_id = p_organization_id and access_role_id = v_role;
  if v_assignment is null then return; end if;
  select exists (select 1 from public.access_role_assignment_scopes where assignment_id = v_assignment and scope_type = 'ASSIGNED' and status = 'active') into v_scope_ativo;

  update public.access_role_assignment_scopes
     set status = 'revoked', updated_at = now()
   where assignment_id = v_assignment and organization_id = p_organization_id and scope_type = 'ASSIGNED' and status = 'active';
  perform public.revogar_acesso_role(v_membership, v_role, p_actor_user_profile_id);
  if coalesce(v_scope_ativo, false) then
    insert into public.privilege_mutation_audit
      (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
    values (p_organization_id, v_membership, v_role, 'revoke', p_actor_user_profile_id);
  end if;
end;
$$;

revoke all on function public.f6_306_conceder_evaluator(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.f6_306_revogar_evaluator(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.f6_306_conceder_evaluator(uuid, uuid, uuid) to service_role;
grant execute on function public.f6_306_revogar_evaluator(uuid, uuid, uuid) to service_role;

do $$
begin
  if (select count(*) from public.access_role_capabilities rc join public.access_roles r on r.id=rc.access_role_id join public.capabilities c on c.id=rc.capability_id where r.name='admin' and c.code like 'evaluation.%') <> 0 then
    raise exception 'F6_306_GUARD: admin recebeu evaluation.*';
  end if;
  if (select count(*) from public.access_role_capabilities rc join public.access_roles r on r.id=rc.access_role_id join public.capabilities c on c.id=rc.capability_id where r.name='evaluator') <> 1 then
    raise exception 'F6_306_GUARD: evaluator deve conter exatamente evaluation.read';
  end if;
end $$;
