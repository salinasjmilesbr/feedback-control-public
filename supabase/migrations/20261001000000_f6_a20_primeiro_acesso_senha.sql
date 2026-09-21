-- F6-A20 / Issue #321: estado soberano de primeiro acesso.
-- A senha continua exclusivamente no Supabase Auth; esta coluna registra apenas
-- se o convite ainda exige a definição inicial.

alter table public.user_profiles
  add column if not exists first_access_pending boolean not null default false;

comment on column public.user_profiles.first_access_pending is
  'F6-A20: estado server-side do onboarding de convite; não contém credencial.';

-- A assinatura antiga não pode permanecer como sobrecarga: a guarda F4-08
-- exige uma única primitive SECURITY DEFINER com este nome.
drop function if exists public.criar_perfil_membership(uuid, uuid);

create or replace function public.criar_perfil_membership(
  p_user_id uuid,
  p_organization_id uuid,
  p_first_access_pending boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (id, first_access_pending)
  values (p_user_id, p_first_access_pending);

  insert into public.user_organization_memberships (user_profile_id, organization_id)
  values (p_user_id, p_organization_id);
end;
$$;

comment on function public.criar_perfil_membership(uuid, uuid, boolean) is
  'F2-06/F6-A20: cria perfil + membership atomicamente; convite pode marcar primeiro acesso pendente.';

revoke all on function public.criar_perfil_membership(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.criar_perfil_membership(uuid, uuid, boolean)
  to service_role;

create or replace function public.convidado_acesso_criar(
  p_user_id uuid,
  p_organization_id uuid,
  p_collaborator_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_membership uuid;
begin
  if p_user_id is null or p_organization_id is null or p_collaborator_id is null then
    raise exception 'F6_A19_INVALID_INPUT: parametros obrigatorios' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.collaborators c
    where c.id = p_collaborator_id and c.organization_id = p_organization_id
  ) then
    raise exception 'F6_A19_INVALID_COLLABORATOR: colaborador inexistente no tenant'
      using errcode = 'P0002';
  end if;

  perform public.criar_perfil_membership(p_user_id, p_organization_id, true);

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_user_id
     and m.organization_id = p_organization_id
     and m.status = 'active';

  if v_membership is null then
    raise exception 'F6_A19_INTERNAL: membership nao criada' using errcode = 'P0001';
  end if;

  perform public.vincular_colaborador(v_membership, p_collaborator_id);
  return v_membership;
end;
$fn$;

revoke all on function public.convidado_acesso_criar(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.convidado_acesso_criar(uuid, uuid, uuid)
  to service_role;
