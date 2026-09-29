-- F6-AVALIACOES-05 / #404: bundles mutantes genéricos.
-- Capabilities vêm exclusivamente de roles; relação e scope permanecem gates
-- independentes. #306/evaluator não é alterado.

insert into public.access_roles (id, name, status, is_system, organization_id)
values
  ('c0000000-0000-4000-8000-0000000000f3', 'evaluation_manager', 'active', true, null),
  ('c0000000-0000-4000-8000-0000000000f4', 'evaluation_contributor', 'active', true, null)
on conflict (id) do nothing;

insert into public.access_role_capabilities (access_role_id, capability_id)
select 'c0000000-0000-4000-8000-0000000000f3', c.id
  from public.capabilities c
 where c.code in ('evaluation.create', 'evaluation.write')
on conflict (access_role_id, capability_id) do nothing;

insert into public.access_role_capabilities (access_role_id, capability_id)
select 'c0000000-0000-4000-8000-0000000000f4', c.id
  from public.capabilities c
 where c.code = 'evaluation.write'
on conflict (access_role_id, capability_id) do nothing;

create or replace function public.f6_404_provisionar_bundle_avaliacao(
  p_target_user_profile_id uuid,
  p_organization_id uuid,
  p_bundle text,
  p_scope_type text,
  p_cycle_id uuid,
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
  v_collaborator uuid;
  v_ano integer;
  v_numero integer;
  v_reference_date timestamptz;
  v_reference_dates integer;
  v_ok boolean := false;
begin
  if p_bundle not in ('GESTAO', 'CONTRIBUICAO') then
    raise exception 'F6_404_INVALID_BUNDLE';
  end if;
  if (p_bundle = 'GESTAO' and p_scope_type not in ('DIRECT_REPORTS', 'DESCENDANTS'))
     or (p_bundle = 'CONTRIBUICAO' and p_scope_type <> 'ASSIGNED') then
    raise exception 'F6_404_INVALID_SCOPE_FOR_BUNDLE';
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_target_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active';
  if v_membership is null then raise exception 'F6_404_TARGET_MEMBERSHIP_NOT_FOUND'; end if;

  select l.collaborator_id into v_collaborator
    from public.membership_collaborator_links l
   where l.membership_id = v_membership and l.status = 'active';
  if v_collaborator is null then raise exception 'F6_404_TARGET_COLLABORATOR_NOT_FOUND'; end if;

  select c.ano, c.numero into v_ano, v_numero
    from public.evaluation_cycles c
   where c.id = p_cycle_id and c.organization_id = p_organization_id;
  if v_ano is null then raise exception 'F6_404_CYCLE_CONTEXT_REQUIRED'; end if;

  select count(distinct s.reference_date)::integer, min(s.reference_date)
    into v_reference_dates, v_reference_date
    from public.collegiate_cycle_snapshots s
   where s.organization_id = p_organization_id
     and s.ano = v_ano
     and s.ciclo = v_numero;
  if v_reference_dates <> 1 then
    raise exception 'F6_404_CYCLE_REFERENCE_DATE_AMBIGUOUS';
  end if;

  if p_bundle = 'GESTAO' then
      select exists (
      select 1
        from public.collegiate_cycle_snapshots s
        cross join lateral public.resolver_alvos_escopo(
          p_target_user_profile_id, p_organization_id, p_scope_type, null,
          v_reference_date
        ) a
       where s.organization_id = p_organization_id
         and s.ano = v_ano and s.ciclo = v_numero
         and a.collaborator_id is not null
    ) into v_ok;
    v_role := 'c0000000-0000-4000-8000-0000000000f3';
  else
    select exists (
      select 1
        from public.evaluation_participants ep
        join public.evaluations e
          on e.id = ep.evaluation_id
         and e.organization_id = ep.organization_id
         and e.cycle_id = p_cycle_id
       where ep.organization_id = p_organization_id
         and ep.collaborator_id = v_collaborator
         and ep.role_type = 'COLEGIADO'
         and ep.status = 'active'
         and ep.valid_from <= now()
         and (ep.valid_to is null or ep.valid_to > now())
    ) into v_ok;
    v_role := 'c0000000-0000-4000-8000-0000000000f4';
  end if;
  if not v_ok then raise exception 'F6_404_RELATION_NOT_ELIGIBLE'; end if;

  perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);
  select id into v_assignment from public.membership_access_role_assignments
   where membership_id = v_membership and organization_id = p_organization_id
     and access_role_id = v_role and status = 'active';
  if v_assignment is null then raise exception 'F6_404_ASSIGNMENT_NOT_PERSISTED'; end if;
  insert into public.access_role_assignment_scopes
    (assignment_id, organization_id, scope_type, status, created_by)
  values (v_assignment, p_organization_id, p_scope_type, 'active', p_actor_user_profile_id)
  on conflict (assignment_id, scope_type) do update
    set status = 'active', created_by = excluded.created_by;
end;
$$;

create or replace function public.f6_404_reconciliar_bundle_avaliacao(
  p_target_user_profile_id uuid,
  p_organization_id uuid,
  p_bundle text,
  p_scope_type text,
  p_cycle_id uuid,
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
  v_ano integer;
  v_numero integer;
  v_reference_date timestamptz;
  v_reference_dates integer;
  v_eligible boolean := false;
begin
  if p_bundle not in ('GESTAO', 'CONTRIBUICAO') then
    raise exception 'F6_404_INVALID_BUNDLE';
  end if;
  if (p_bundle = 'GESTAO' and p_scope_type not in ('DIRECT_REPORTS', 'DESCENDANTS'))
     or (p_bundle = 'CONTRIBUICAO' and p_scope_type <> 'ASSIGNED') then
    raise exception 'F6_404_INVALID_SCOPE_FOR_BUNDLE';
  end if;

  v_role := case when p_bundle = 'GESTAO'
    then 'c0000000-0000-4000-8000-0000000000f3'::uuid
    else 'c0000000-0000-4000-8000-0000000000f4'::uuid end;
  select id into v_membership
    from public.user_organization_memberships
   where user_profile_id = p_target_user_profile_id
     and organization_id = p_organization_id;
  if v_membership is null then return; end if;

  select c.ano, c.numero into v_ano, v_numero
    from public.evaluation_cycles c
   where c.id = p_cycle_id and c.organization_id = p_organization_id;
  if v_ano is null then return; end if;

  select count(distinct s.reference_date)::integer, min(s.reference_date)
    into v_reference_dates, v_reference_date
    from public.collegiate_cycle_snapshots s
   where s.organization_id = p_organization_id
     and s.ano = v_ano
     and s.ciclo = v_numero;
  if v_reference_dates <> 1 then return; end if;

  if p_bundle = 'GESTAO' then
      select exists (
      select 1
        from public.collegiate_cycle_snapshots s
        cross join lateral public.resolver_alvos_escopo(
          p_target_user_profile_id, p_organization_id, p_scope_type, null,
          v_reference_date
        )
       where s.organization_id = p_organization_id
         and s.ano = v_ano and s.ciclo = v_numero
    ) into v_eligible;
  else
    select exists (
      select 1
        from public.membership_collaborator_links l
        join public.evaluation_participants ep
          on ep.collaborator_id = l.collaborator_id
        join public.evaluations e
          on e.id = ep.evaluation_id
         and e.organization_id = ep.organization_id
         and e.cycle_id = p_cycle_id
       where l.membership_id = v_membership and l.status = 'active'
         and ep.organization_id = p_organization_id and ep.role_type = 'COLEGIADO'
         and ep.status = 'active' and ep.valid_from <= now()
         and (ep.valid_to is null or ep.valid_to > now())
    ) into v_eligible;
  end if;

  select id into v_assignment
    from public.membership_access_role_assignments
   where membership_id = v_membership and organization_id = p_organization_id
     and access_role_id = v_role and status = 'active';
  if v_eligible then
    if v_assignment is null then
      perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);
      select id into v_assignment
        from public.membership_access_role_assignments
       where membership_id = v_membership and organization_id = p_organization_id
         and access_role_id = v_role and status = 'active';
    end if;
    insert into public.access_role_assignment_scopes
      (assignment_id, organization_id, scope_type, status, created_by)
    values (v_assignment, p_organization_id, p_scope_type, 'active', p_actor_user_profile_id)
    on conflict (assignment_id, scope_type) do update
      set status = 'active', created_by = excluded.created_by;
  elsif v_assignment is not null then
    update public.access_role_assignment_scopes
       set status = 'revoked', updated_at = now()
     where assignment_id = v_assignment and organization_id = p_organization_id
       and scope_type = p_scope_type and status = 'active';
    if not exists (
      select 1 from public.access_role_assignment_scopes
       where assignment_id = v_assignment and status = 'active'
    ) then
      perform public.revogar_acesso_role(v_membership, v_role, p_actor_user_profile_id);
    end if;
    insert into public.privilege_mutation_audit
      (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
    values (p_organization_id, v_membership, v_role, 'revoke', p_actor_user_profile_id);
  end if;
end;
$$;

revoke all on function public.f6_404_provisionar_bundle_avaliacao(uuid, uuid, text, text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.f6_404_provisionar_bundle_avaliacao(uuid, uuid, text, text, uuid, uuid)
  to service_role;
revoke all on function public.f6_404_reconciliar_bundle_avaliacao(uuid, uuid, text, text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.f6_404_reconciliar_bundle_avaliacao(uuid, uuid, text, text, uuid, uuid)
  to service_role;

do $$
begin
  if (select count(*) from public.access_role_capabilities rc
      join public.access_roles r on r.id = rc.access_role_id
      join public.capabilities c on c.id = rc.capability_id
      where r.name = 'evaluator') <> 1
     or not exists (
       select 1 from public.access_role_capabilities rc
       join public.access_roles r on r.id = rc.access_role_id
       join public.capabilities c on c.id = rc.capability_id
       where r.name = 'evaluator' and c.code = 'evaluation.read'
     ) then
    raise exception 'F6_404_GUARD: evaluator deve permanecer read-only';
  end if;
  if (select count(*) from public.access_role_capabilities rc
      join public.access_roles r on r.id = rc.access_role_id
      join public.capabilities c on c.id = rc.capability_id
      where r.name = 'admin' and c.code like 'evaluation.%') <> 0 then
    raise exception 'F6_404_GUARD: admin recebeu evaluation.*';
  end if;
end $$;
