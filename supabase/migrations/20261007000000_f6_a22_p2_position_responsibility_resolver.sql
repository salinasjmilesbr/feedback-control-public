-- F6-A22 P2 (Issue #338)
-- Integra PEOPLE_MANAGEMENT ao resolver soberano existente.
-- Nenhuma role, capability, RPC, Edge ou superfície de cliente é criada.

-- A forma escopada ganha a origem explícita do grant. Os consumidores existentes
-- selecionam somente os campos que usam e permanecem compatíveis.
drop function public.resolver_capabilities_escopos_efetivas(uuid, uuid);

create or replace function public.resolver_capabilities_efetivas(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns table (capability_code text)
language sql stable security definer set search_path = public
as $$
  with role_grants as (
    select c.code
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
      join public.membership_access_role_assignments a on a.membership_id = m.id and a.status = 'active'
      join public.access_roles r on r.id = a.access_role_id and r.status = 'active'
      join public.access_role_capabilities rc on rc.access_role_id = r.id
      join public.capabilities c on c.id = rc.capability_id
       and c.status = 'active' and c.deprecated = false
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id
       and m.status = 'active'
  ), actor_occupations as (
    select m.user_profile_id, m.organization_id, l.collaborator_id, count(*) as occupation_count
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
      join public.membership_collaborator_links l
        on l.membership_id = m.id and l.organization_id = m.organization_id and l.status = 'active'
      join public.occupations o
        on o.organization_id = m.organization_id and o.collaborator_id = l.collaborator_id
       and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id and m.status = 'active'
     group by m.user_profile_id, m.organization_id, l.collaborator_id
  ), responsibility_grants as (
    select b.capability_code as code
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
      join public.membership_collaborator_links l
        on l.membership_id = m.id and l.organization_id = m.organization_id and l.status = 'active'
      join public.occupations o
        on o.organization_id = m.organization_id and o.collaborator_id = l.collaborator_id
       and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
      join actor_occupations ao
        on ao.user_profile_id = m.user_profile_id
       and ao.organization_id = m.organization_id
       and ao.collaborator_id = l.collaborator_id
       and ao.occupation_count = 1
      join public.organizational_positions p
        on p.organization_id = m.organization_id and p.id = o.organizational_position_id
       and p.valid_from <= now() and (p.valid_to is null or p.valid_to > now())
      join public.organizational_position_responsibilities pr
        on pr.organization_id = m.organization_id and pr.position_id = p.id
       and pr.status = 'active' and pr.valid_from <= now()
       and (pr.valid_to is null or pr.valid_to > now())
      join public.organizational_position_responsibility_bundle b
        on b.responsibility_code = pr.responsibility_code
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id
       and m.status = 'active'
  )
  select distinct code from (select code from role_grants union all select code from responsibility_grants) x
  order by code
$$;

create or replace function public.resolver_capabilities_escopos_efetivas(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns table (
  access_role_id uuid,
  capability_code text,
  scope_type text,
  organizational_unit_id uuid,
  grant_origin text
)
language sql stable set search_path = public
as $$
  with role_grants as (
    select distinct r.id as access_role_id, c.code as capability_code,
           s.scope_type, ut.organizational_unit_id,
           ('access_role:' || r.id::text) as grant_origin
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
      join public.membership_access_role_assignments a on a.membership_id = m.id and a.status = 'active'
      join public.access_roles r on r.id = a.access_role_id and r.status = 'active'
      join public.access_role_capabilities rc on rc.access_role_id = r.id
      join public.capabilities c on c.id = rc.capability_id
       and c.status = 'active' and c.deprecated = false
      join public.access_role_assignment_scopes s on s.assignment_id = a.id and s.status = 'active'
      left join public.access_role_assignment_unit_targets ut on ut.scope_id = s.id
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id and m.status = 'active'
  ),
  actor_occupations as (
    select m.user_profile_id, m.organization_id, l.collaborator_id, count(*) as occupation_count
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
      join public.membership_collaborator_links l
        on l.membership_id = m.id and l.organization_id = m.organization_id and l.status = 'active'
      join public.occupations o
        on o.organization_id = m.organization_id and o.collaborator_id = l.collaborator_id
       and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id and m.status = 'active'
     group by m.user_profile_id, m.organization_id, l.collaborator_id
  ),
  responsibility_positions as (
    select pr.id as responsibility_id, p.id as position_id
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
      join public.membership_collaborator_links l
        on l.membership_id = m.id and l.organization_id = m.organization_id and l.status = 'active'
      join public.occupations o
        on o.organization_id = m.organization_id and o.collaborator_id = l.collaborator_id
       and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
      join actor_occupations ao
        on ao.user_profile_id = m.user_profile_id
       and ao.organization_id = m.organization_id
       and ao.collaborator_id = l.collaborator_id
       and ao.occupation_count = 1
      join public.organizational_positions p
        on p.organization_id = m.organization_id and p.id = o.organizational_position_id
       and p.valid_from <= now() and (p.valid_to is null or p.valid_to > now())
      join public.organizational_position_responsibilities pr
        on pr.organization_id = m.organization_id and pr.position_id = p.id
       and pr.status = 'active' and pr.valid_from <= now()
       and (pr.valid_to is null or pr.valid_to > now())
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id and m.status = 'active'
  ),
  responsibility_grants as (
    select distinct null::uuid as access_role_id, b.capability_code,
           scopes.scope_type, null::uuid as organizational_unit_id,
           ('position_responsibility:' || rp.responsibility_id::text) as grant_origin
      from responsibility_positions rp
      join public.organizational_position_responsibility_bundle b
        on b.responsibility_code = 'PEOPLE_MANAGEMENT'
      cross join (values ('DIRECT_REPORTS'::text), ('DESCENDANTS'::text)) scopes(scope_type)
  )
  select access_role_id, capability_code, scope_type, organizational_unit_id, grant_origin from role_grants
  union
  select access_role_id, capability_code, scope_type, organizational_unit_id, grant_origin from responsibility_grants
$$;

comment on function public.resolver_capabilities_efetivas(uuid, uuid) is
  'F6-A22 P2: capabilities de roles e da responsabilidade PEOPLE_MANAGEMENT, '
  'somente para ocupacao/posicao/responsabilidade vigentes; fail-closed.';
comment on function public.resolver_capabilities_escopos_efetivas(uuid, uuid) is
  'F6-A22 P2: uniao do resolver de roles com grants de posicao, com origem '
  'position_responsibility:<id> e scopes DIRECT_REPORTS/DESCENDANTS.';

revoke all on function public.resolver_capabilities_efetivas(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.resolver_capabilities_escopos_efetivas(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.resolver_capabilities_efetivas(uuid, uuid) to service_role;
grant execute on function public.resolver_capabilities_escopos_efetivas(uuid, uuid) to service_role;
