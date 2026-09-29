-- F6-414: role admin global; a precedência é avaliada por tenant afetado.
create or replace function public.company_admin_guard_d12_mutation()
returns trigger language plpgsql security invoker set search_path = public as $$
declare v_count integer;
begin
  if tg_table_name = 'access_roles' then
    if old.is_system = true and old.name = 'admin'
       and (new.status <> old.status or new.name <> old.name or new.is_system <> old.is_system) then
      if exists (
        select 1 from public.organizations o
        where (select count(*) from public.user_organization_memberships m
          join public.user_profiles p on p.id=m.user_profile_id and p.status='active'
          join public.membership_access_role_assignments a on a.membership_id=m.id and a.status='active' and a.access_role_id=old.id
          where m.organization_id=o.id and m.status='active') < 1
      ) then raise exception 'F6_414_LAST_ADMIN' using errcode='P0001'; end if;
      if exists (
        select 1 from public.organizations o
        where (select count(*) from public.user_organization_memberships m
          join public.user_profiles p on p.id=m.user_profile_id and p.status='active'
          join public.membership_access_role_assignments a on a.membership_id=m.id and a.status='active' and a.access_role_id=old.id
          where m.organization_id=o.id and m.status='active') > 4
      ) then raise exception 'F6_414_ADMIN_LIMIT' using errcode='P0001'; end if;
      raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode='42501';
    end if;
  elsif tg_table_name = 'membership_access_role_assignments' and old.status='active'
    and exists (select 1 from public.access_roles r where r.id=old.access_role_id and r.is_system and r.name='admin') then
    if public.company_admin_count_active(old.organization_id) <= 1 then raise exception 'F6_414_LAST_ADMIN' using errcode='P0001'; end if;
    raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode='42501';
  elsif tg_table_name = 'user_organization_memberships' and old.status='active'
    and exists (select 1 from public.membership_access_role_assignments a join public.access_roles r on r.id=a.access_role_id where a.membership_id=old.id and a.status='active' and r.is_system and r.name='admin') then
    if public.company_admin_count_active(old.organization_id) <= 1 then raise exception 'F6_414_LAST_ADMIN' using errcode='P0001'; end if;
    raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode='42501';
  end if;
  return old;
end;
$$;
revoke all on function public.company_admin_guard_d12_mutation() from public, anon, authenticated;
grant execute on function public.company_admin_guard_d12_mutation() to service_role;
