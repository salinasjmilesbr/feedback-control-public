-- ============================================================================
-- F5-04 (Issue #165): operações administrativas server-side/transacionais (D16)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-04-desenho-tecnico.md (D16 FECHADA).
--
-- Conceder/revogar access_role de membership SOMENTE por caminho
-- server-side/transacional com ATOR SOBERANO derivado de auth.uid() (nunca
-- informado pelo cliente), tenant REVALIDADO contra membership ativa do ator e
-- PREVENÇÃO DE SELF-ESCALATION (o ator não pode conceder à própria membership).
--
-- Padrão de segurança (mesma fronteira da F5-02 D9 / F4-01 D16):
--   - SECURITY INVOKER (nenhum SECURITY DEFINER novo — §7/AC7);
--   - EXECUTE concedido SOMENTE a service_role (revogado de public/anon/
--     authenticated) — fronteira confiável usada por Edge Functions/tooling,
--     nunca pelo cliente;
--   - cada mutação grava registro APPEND-ONLY na trilha D18 com autoria
--     soberana (auth.uid()).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- conceder_acesso_role_rpc: concessão/reativação com ator soberano
-- ----------------------------------------------------------------------------
create or replace function public.conceder_acesso_role_rpc(
  p_membership_id uuid,
  p_access_role_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_actor         uuid := auth.uid();
  v_target_org    uuid;
  v_target_user   uuid;
begin
  if v_actor is null then
    raise exception 'F5-04: ator soberano (auth.uid()) ausente na concessao';
  end if;

  select m.organization_id, m.user_profile_id
    into v_target_org, v_target_user
    from public.user_organization_memberships m
   where m.id = p_membership_id
     and m.status = 'active';

  if not found then
    raise exception 'F5-04: membership alvo inexistente ou inativa';
  end if;

  -- Prevenção de self-escalation (D15/D16): quem concede não se auto-concede.
  if v_target_user = v_actor then
    raise exception 'F5-04: self-escalation negada (ator nao pode conceder a propria membership)';
  end if;

  -- Tenant revalidado (D16): ator deve ter profile ativo + membership ativa na
  -- organização alvo. Cross-tenant = DENY.
  if not exists (
    select 1
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id
     where m.user_profile_id = v_actor
       and m.organization_id = v_target_org
       and m.status = 'active'
       and up.status = 'active'
  ) then
    raise exception 'F5-04: ator sem membership ativa na organizacao alvo (cross-tenant negado)';
  end if;

  -- Delega ao primitivo DEFINER (valida membership ativa, perfil ativo, role
  -- ativa e tenant da role).
  perform public.conceder_acesso_role(p_membership_id, p_access_role_id, v_actor);

  -- Trilha append-only (D18) com autoria soberana.
  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values
    (v_target_org, p_membership_id, p_access_role_id, 'grant', v_actor);
end;
$$;

comment on function public.conceder_acesso_role_rpc(uuid, uuid) is
  'F5-04 (D16): concessao/reativacao de access_role a membership por caminho '
  'server-side/transacional. Ator soberano = auth.uid() (nunca do cliente); '
  'prevencao de self-escalation; tenant revalidado (cross-tenant DENY); grava '
  'trilha append-only (D18). SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- revogar_acesso_role_rpc: revogação com ator soberano
-- ----------------------------------------------------------------------------
create or replace function public.revogar_acesso_role_rpc(
  p_membership_id uuid,
  p_access_role_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_actor       uuid := auth.uid();
  v_target_org  uuid;
begin
  if v_actor is null then
    raise exception 'F5-04: ator soberano (auth.uid()) ausente na revogacao';
  end if;

  select m.organization_id
    into v_target_org
    from public.user_organization_memberships m
   where m.id = p_membership_id
     and m.status = 'active';

  if not found then
    raise exception 'F5-04: membership alvo inexistente ou inativa';
  end if;

  -- Tenant revalidado (D16): cross-tenant = DENY.
  if not exists (
    select 1
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id
     where m.user_profile_id = v_actor
       and m.organization_id = v_target_org
       and m.status = 'active'
       and up.status = 'active'
  ) then
    raise exception 'F5-04: ator sem membership ativa na organizacao alvo (cross-tenant negado)';
  end if;

  perform public.revogar_acesso_role(p_membership_id, p_access_role_id, v_actor);

  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values
    (v_target_org, p_membership_id, p_access_role_id, 'revoke', v_actor);
end;
$$;

comment on function public.revogar_acesso_role_rpc(uuid, uuid) is
  'F5-04 (D16): revogacao de access_role de membership por caminho '
  'server-side/transacional. Ator soberano = auth.uid(); tenant revalidado '
  '(cross-tenant DENY); grava trilha append-only (D18). SECURITY INVOKER; '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- Grants: EXECUTE somente service_role (sem superfície para authenticated/anon)
-- ----------------------------------------------------------------------------
revoke all on function public.conceder_acesso_role_rpc(uuid, uuid) from public, anon, authenticated;
revoke all on function public.revogar_acesso_role_rpc(uuid, uuid) from public, anon, authenticated;

grant execute on function public.conceder_acesso_role_rpc(uuid, uuid) to service_role;
grant execute on function public.revogar_acesso_role_rpc(uuid, uuid) to service_role;
