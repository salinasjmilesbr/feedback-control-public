-- F6-414: Auth pode materializar user_profiles antes da concessão administrativa.
create or replace function public.company_admin_invite_grant(
  p_operation_id uuid, p_organization_id uuid, p_target_user_profile_id uuid, p_actor_user_profile_id uuid, p_payload_hash text
) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_membership uuid; v_role uuid; v_existing public.company_admin_operations%rowtype;
begin
  perform public.company_admin_lock_organization(p_organization_id);
  select * into v_existing from public.company_admin_operations where organization_id=p_organization_id and operation_id=p_operation_id;
  if found then if v_existing.payload_hash <> p_payload_hash then raise exception 'F6_414_OPERATION_CONFLICT' using errcode='P0001'; end if; return coalesce(v_existing.result_membership_id,v_existing.target_membership_id); end if;
  if not public.usuario_eh_administrador(p_actor_user_profile_id,p_organization_id) then raise exception 'F6_414_FORBIDDEN' using errcode='42501'; end if;
  if public.company_admin_count_active(p_organization_id)>=4 then raise exception 'F6_414_ADMIN_LIMIT' using errcode='P0001'; end if;
  select id into v_role from public.access_roles where is_system and name='admin' and status='active';
  if v_role is null then raise exception 'F6_414_ADMIN_ROLE_MISSING' using errcode='P0001'; end if;
  if not exists (select 1 from public.user_profiles where id=p_target_user_profile_id) then
    perform public.criar_perfil_membership(p_target_user_profile_id,p_organization_id,true);
  elsif not exists (select 1 from public.user_organization_memberships where user_profile_id=p_target_user_profile_id and organization_id=p_organization_id) then
    insert into public.user_organization_memberships(user_profile_id,organization_id) values(p_target_user_profile_id,p_organization_id);
  end if;
  select id into v_membership from public.user_organization_memberships where user_profile_id=p_target_user_profile_id and organization_id=p_organization_id and status='active';
  if v_membership is null then raise exception 'F6_414_MEMBERSHIP_UNAVAILABLE' using errcode='P0001'; end if;
  perform public.conceder_acesso_role(v_membership,v_role,p_actor_user_profile_id);
  insert into public.company_admin_operations(operation_id,organization_id,action,target_user_profile_id,target_membership_id,actor_user_profile_id,payload_hash,result_membership_id) values(p_operation_id,p_organization_id,'INVITE_GRANT',p_target_user_profile_id,v_membership,p_actor_user_profile_id,p_payload_hash,v_membership);
  insert into public.privilege_mutation_audit(organization_id,membership_id,access_role_id,action,actor_user_profile_id) values(p_organization_id,v_membership,v_role,'grant',p_actor_user_profile_id);
  perform public.company_admin_validate_cardinality(p_organization_id);
  return v_membership;
end;
$$;
revoke all on function public.company_admin_invite_grant(uuid,uuid,uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.company_admin_invite_grant(uuid,uuid,uuid,uuid,text) to service_role;
