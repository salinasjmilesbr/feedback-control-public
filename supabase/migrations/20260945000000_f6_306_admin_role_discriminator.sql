-- F6-A19/#306: reassert the administrative discriminator after evaluator.
-- Administrative authority is the canonical system role `admin`, never any
-- active system role. This migration is additive and leaves D18/ASSIGNED intact.

create or replace function public.usuario_eh_administrador(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $fn$
  select exists (
    select 1
      from public.user_organization_memberships m
      join public.membership_access_role_assignments a
        on a.membership_id = m.id
       and a.status = 'active'
      join public.access_roles r
        on r.id = a.access_role_id
       and r.is_system = true
       and r.name = 'admin'
       and r.status = 'active'
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id
       and m.status = 'active'
  );
$fn$;

comment on function public.usuario_eh_administrador(uuid, uuid) is
  'F6-306: somente a role de sistema admin confere autoridade administrativa; '
  'roles de dominio, inclusive evaluator, nunca conferem essa autoridade.';

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.usuario_eh_administrador(uuid, uuid)'::regprocedure) into v_def;
  if position('r.name = ''admin''' in v_def) = 0 then
    raise exception 'F6_306_GUARD: autoridade administrativa sem discriminante nominal admin';
  end if;
  if position('r.is_system = true' in v_def) = 0 then
    raise exception 'F6_306_GUARD: autoridade administrativa sem role sistêmica';
  end if;
end $$;
