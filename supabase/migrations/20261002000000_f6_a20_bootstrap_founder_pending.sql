-- F6-A20 / Issue #310: primeiro acesso do founder provisionado.
--
-- A definição anterior do bootstrap cria o perfil do founder com o default
-- `first_access_pending = false`. O convite autentica o founder por um link
-- temporário, mas ele sai sem senha permanente e não passa pelo onboarding.
--
-- A função-base é renomeada apenas para preservar integralmente a transação
-- F6-A03/F6-A11. Esta nova fronteira marca somente perfil NOVO como pendente;
-- perfil preexistente (inclusive o operador em auto-bootstrap) não é alterado.

do $guard$
begin
  if to_regprocedure('public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)') is not null
     and to_regprocedure('public.organizacao_provisionar_inicial_f6_a20_base(uuid, text, uuid, uuid, text, text, text)') is null then
    alter function public.organizacao_provisionar_inicial(
      uuid, text, uuid, uuid, text, text, text
    ) rename to organizacao_provisionar_inicial_f6_a20_base;
  end if;
end;
$guard$;

create or replace function public.organizacao_provisionar_inicial(
  p_operation_id            uuid,
  p_organization_name       text,
  p_founder_user_profile_id uuid,
  p_actor_user_profile_id   uuid,
  p_founder_full_name       text,
  p_founder_matricula       text,
  p_founder_email           text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_founder_preexisting boolean;
  v_org uuid;
begin
  select exists(
    select 1
      from public.user_profiles
     where id = p_founder_user_profile_id
  ) into v_founder_preexisting;

  v_org := public.organizacao_provisionar_inicial_f6_a20_base(
    p_operation_id,
    p_organization_name,
    p_founder_user_profile_id,
    p_actor_user_profile_id,
    p_founder_full_name,
    p_founder_matricula,
    p_founder_email
  );

  if not v_founder_preexisting then
    update public.user_profiles
       set first_access_pending = true
     where id = p_founder_user_profile_id
       and first_access_pending is distinct from true;
  end if;

  return v_org;
end;
$fn$;

comment on function public.organizacao_provisionar_inicial(
  uuid, text, uuid, uuid, text, text, text
) is
  'F6-A20/#310: delega o bootstrap F6-A03/F6-A11 e marca somente founder novo como primeiro acesso pendente.';

revoke all on function public.organizacao_provisionar_inicial(
  uuid, text, uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.organizacao_provisionar_inicial(
  uuid, text, uuid, uuid, text, text, text
) to service_role;
