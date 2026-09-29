-- F6-414: corrige avaliação de OLD/NEW por row type no guard D12.
create or replace function public.company_admin_guard_d12_mutation()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
  if tg_table_name = 'access_roles' then
    if old.is_system = true and old.name = 'admin'
       and (new.status <> old.status or new.name <> old.name or new.is_system <> old.is_system) then
      raise exception 'F6_414_ADMIN_ROLE_IMMUTABLE' using errcode = '42501';
    end if;
  elsif tg_table_name = 'membership_access_role_assignments' then
    if old.status = 'active' and exists (
      select 1 from public.access_roles r
       where r.id = old.access_role_id and r.is_system and r.name = 'admin'
    ) then
      raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode = '42501';
    end if;
  elsif tg_table_name = 'user_organization_memberships' then
    if old.status = 'active' and exists (
      select 1
        from public.membership_access_role_assignments a
        join public.access_roles r on r.id = a.access_role_id
       where a.membership_id = old.id and a.status = 'active'
         and r.is_system and r.name = 'admin'
    ) then
      raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode = '42501';
    end if;
  end if;
  return old;
end;
$$;

revoke all on function public.company_admin_guard_d12_mutation() from public, anon, authenticated;
grant execute on function public.company_admin_guard_d12_mutation() to service_role;
