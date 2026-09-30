-- Bootstrap tecnico #414 para fixtures executadas em runner descartavel.
-- Deve ser incluido explicitamente pela fixture, dentro da mesma transacao que
-- cria as organizations. Nao concede capability funcional nem cria vinculo
-- estrutural: apenas profile, membership e assignment ativo de admin.
do $f6_414_fixture_admin$
declare
  v_org record;
  v_profile uuid;
  v_membership uuid;
  v_admin_role uuid;
begin
  select id into v_admin_role
    from public.access_roles
   where name = 'admin'
     and is_system = true
     and organization_id is null
     and status = 'active';

  if v_admin_role is null then
    raise exception 'F6_414_FIXTURE_ADMIN_ROLE_MISSING';
  end if;

  for v_org in
    select o.id
      from public.organizations o
     where not exists (
       select 1
         from public.membership_access_role_assignments a
         join public.user_organization_memberships m on m.id = a.membership_id
         join public.user_profiles p on p.id = m.user_profile_id
         join public.access_roles r on r.id = a.access_role_id
        where m.organization_id = o.id
          and m.status = 'active'
          and p.status = 'active'
          and a.status = 'active'
          and r.name = 'admin'
          and r.is_system = true
     )
  loop
    v_profile := gen_random_uuid();
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
       raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values
      (v_profile, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', 'fixture-admin-' || v_profile::text || '@example.invalid',
       'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

    insert into public.user_profiles (id, status) values (v_profile, 'active');
    insert into public.user_organization_memberships
      (user_profile_id, organization_id, status)
    values (v_profile, v_org.id, 'active')
    returning id into v_membership;

    insert into public.membership_access_role_assignments
      (membership_id, organization_id, access_role_id, status, created_by)
    values (v_membership, v_org.id, v_admin_role, 'active', v_profile);
  end loop;
end
$f6_414_fixture_admin$;
