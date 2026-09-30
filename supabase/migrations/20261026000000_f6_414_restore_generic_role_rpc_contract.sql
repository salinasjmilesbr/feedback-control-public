-- #414: restaura os guards F5-04/F5-11 e a trilha D18 perdidos no
-- create or replace das RPCs genericas, mantendo admin no lifecycle dedicado.
create or replace function public.conceder_acesso_role_rpc(
  p_membership_id uuid,
  p_access_role_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_target_org uuid;
  v_target_user uuid;
begin
  if p_actor_user_profile_id is null then
    raise exception 'F5-04: ator ausente (identidade verificada obrigatoria)';
  end if;

  if exists (
    select 1 from public.access_roles r
     where r.id = p_access_role_id
       and r.is_system = true
       and r.name = 'observacoes_avaliado'
  ) then
    raise exception 'F5-04: a role observacoes_avaliado e AUTOMATICA (provisionada por elegibilidade) e nao pode ser concedida por caminho administrativo';
  end if;

  select m.organization_id, m.user_profile_id
    into v_target_org, v_target_user
    from public.user_organization_memberships m
   where m.id = p_membership_id
     and m.status = 'active';
  if not found then
    raise exception 'F5-04: membership alvo inexistente ou inativa';
  end if;

  if v_target_user = p_actor_user_profile_id then
    raise exception 'F5-04: self-escalation negada (ator nao pode conceder a propria membership)';
  end if;

  if not exists (
    select 1
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id
     where m.user_profile_id = p_actor_user_profile_id
       and m.organization_id = v_target_org
       and m.status = 'active'
       and up.status = 'active'
  ) then
    raise exception 'F5-04: ator sem membership ativa na organizacao alvo (cross-tenant negado)';
  end if;

  if not public.usuario_eh_administrador(p_actor_user_profile_id, v_target_org) then
    raise exception 'F5_04_NOT_AUTHORIZED' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.access_roles r
     where r.id = p_access_role_id
       and r.is_system = true
       and r.name = 'admin'
  ) then
    raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode = '42501';
  end if;

  perform public.conceder_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);

  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values
    (v_target_org, p_membership_id, p_access_role_id, 'grant', p_actor_user_profile_id);
end;
$fn$;

create or replace function public.revogar_acesso_role_rpc(
  p_membership_id uuid,
  p_access_role_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_target_org uuid;
begin
  if p_actor_user_profile_id is null then
    raise exception 'F5-04: ator ausente (identidade verificada obrigatoria)';
  end if;

  if exists (
    select 1 from public.access_roles r
     where r.id = p_access_role_id
       and r.is_system = true
       and r.name = 'observacoes_avaliado'
  ) then
    raise exception 'F5-04: a role observacoes_avaliado e AUTOMATICA (revogada por elegibilidade) e nao pode ser revogada por caminho administrativo';
  end if;

  select m.organization_id
    into v_target_org
    from public.user_organization_memberships m
   where m.id = p_membership_id
     and m.status = 'active';
  if not found then
    raise exception 'F5-04: membership alvo inexistente ou inativa';
  end if;

  if not exists (
    select 1
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id
     where m.user_profile_id = p_actor_user_profile_id
       and m.organization_id = v_target_org
       and m.status = 'active'
       and up.status = 'active'
  ) then
    raise exception 'F5-04: ator sem membership ativa na organizacao alvo (cross-tenant negado)';
  end if;

  if not public.usuario_eh_administrador(p_actor_user_profile_id, v_target_org) then
    raise exception 'F5_04_NOT_AUTHORIZED' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.access_roles r
     where r.id = p_access_role_id
       and r.is_system = true
       and r.name = 'admin'
  ) then
    raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode = '42501';
  end if;

  perform public.revogar_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);

  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values
    (v_target_org, p_membership_id, p_access_role_id, 'revoke', p_actor_user_profile_id);
end;
$fn$;

comment on function public.conceder_acesso_role_rpc(uuid, uuid, uuid) is
  'F5-04/F5-11/#414: grant funcional por admin do tenant; self-escalation e role automatica bloqueadas; admin exige company_admin_*; trilha D18 na mesma transacao.';
comment on function public.revogar_acesso_role_rpc(uuid, uuid, uuid) is
  'F5-04/F5-11/#414: revoke funcional por admin do tenant; role automatica bloqueada; admin exige company_admin_*; trilha D18 na mesma transacao.';

revoke all on function public.conceder_acesso_role_rpc(uuid, uuid, uuid),
                       public.revogar_acesso_role_rpc(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.conceder_acesso_role_rpc(uuid, uuid, uuid),
                          public.revogar_acesso_role_rpc(uuid, uuid, uuid)
  to service_role;
