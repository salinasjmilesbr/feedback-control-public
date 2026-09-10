-- ============================================================================
-- F5-04 (Issue #165): operações administrativas server-side/transacionais (D16)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-04-desenho-tecnico.md (D16/D18 FECHADAS; Q3).
--
-- MODELO DE PRODUÇÃO (identidade × execução privilegiada SEPARADAS):
--
--   usuário autenticado (JWT no header `Authorization`)
--   → Edge Function (supabase/functions/gerenciar-access-role): resolve a
--     identidade de forma SOBERANA via `auth.getUser(JWT)` (Gotrue) e NUNCA
--     aceita actor_id do corpo;
--   → executa o RPC com a credencial service_role (apikey), SEM o JWT do
--     usuário no `Authorization` — se o JWT do usuário fosse mantido no
--     Authorization, o PostgREST assumiria a role `authenticated` e perderia o
--     EXECUTE de service_role (por isso a identidade é SEPARADA da execução);
--   → o ator verificado (user.id) chega ao RPC como `p_actor_user_profile_id`,
--     parâmetro derivado EXCLUSIVAMENTE de identidade autenticada verificada
--     server-side — jamais de payload do cliente (o core da Edge Function
--     rejeita `actor_id` no corpo).
--
-- O RPC (SECURITY INVOKER, EXECUTE somente service_role) revalida o ator contra
-- o banco (perfil/membership ativos, tenant) e EXIGE a AUTORIDADE
-- ADMINISTRATIVA (role de sistema `admin` ativa no tenant alvo — Q3/D16). A
-- autoria soberana gravada na trilha D18 é o user.id verificado.
--
-- service_role NÃO permite falsificar o ator: ela apenas ELEVA privilégios
-- (BYPASSRLS) e é detida somente pela Edge Function; a identidade vem do JWT
-- verificado, e o RPC revalida o ator server-side (administrador do tenant).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Regra explícita de autorização administrativa (D16/Q3, coerente com D15):
-- o ator é ADMINISTRADOR do tenant se possui membership ATIVA com atribuição
-- ATIVA de uma access_role de SISTEMA (is_system = true — a role `admin`,
-- bootstrap por migration). membership.manage/access_role.manage continuam
-- FORA do catálogo concedível por role (D15): a autoridade administrativa é
-- validada por esta regra server-side, nunca por capability auto-servida.
-- ----------------------------------------------------------------------------
create or replace function public.usuario_eh_administrador(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
      from public.user_organization_memberships m
      join public.membership_access_role_assignments a
        on a.membership_id = m.id
       and a.status = 'active'
      join public.access_roles r
        on r.id = a.access_role_id
       and r.is_system = true
       and r.status = 'active'
     where m.user_profile_id = p_user_profile_id
       and m.organization_id = p_organization_id
       and m.status = 'active'
  );
$$;

comment on function public.usuario_eh_administrador(uuid, uuid) is
  'F5-04 (D16/Q3): autoridade administrativa restrita, validada server-side — '
  'o ator possui membership ativa com atribuicao ativa de access_role de SISTEMA '
  '(admin) na organizacao. membership.manage/access_role.manage NAO sao '
  'concediveis por role (D15); a autoridade administrativa nao e capability '
  'auto-servida. SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- conceder_acesso_role_rpc: concessão/reativação (ator verificado server-side)
-- ----------------------------------------------------------------------------
create or replace function public.conceder_acesso_role_rpc(
  p_membership_id uuid,
  p_access_role_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_target_org  uuid;
  v_target_user uuid;
begin
  if p_actor_user_profile_id is null then
    raise exception 'F5-04: ator ausente (identidade verificada obrigatoria)';
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
  if v_target_user = p_actor_user_profile_id then
    raise exception 'F5-04: self-escalation negada (ator nao pode conceder a propria membership)';
  end if;

  -- Tenant revalidado (D16): ator com perfil ativo + membership ativa na org
  -- alvo. Cross-tenant = DENY.
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

  -- AUTORIZAÇÃO ADMINISTRATIVA (D16/Q3): somente administrador do tenant.
  if not public.usuario_eh_administrador(p_actor_user_profile_id, v_target_org) then
    raise exception 'F5-04: ator sem autoridade administrativa (nao e administrador do tenant)';
  end if;

  -- Delega ao primitivo DEFINER (valida membership ativa, perfil ativo, role
  -- ativa e tenant da role).
  perform public.conceder_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);

  -- Trilha append-only (D18) com autoria soberana (user.id verificado).
  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values
    (v_target_org, p_membership_id, p_access_role_id, 'grant', p_actor_user_profile_id);
end;
$$;

comment on function public.conceder_acesso_role_rpc(uuid, uuid, uuid) is
  'F5-04 (D16): concessao/reativacao de access_role a membership por caminho '
  'server-side/transacional. Ator = identidade autenticada verificada server-side '
  '(auth.getUser na Edge Function), jamais do cliente; tenant revalidado '
  '(cross-tenant DENY); anti-self-escalation; AUTORIZACAO ADMINISTRATIVA '
  '(administrador do tenant via usuario_eh_administrador); grava trilha D18. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- revogar_acesso_role_rpc: revogação (ator verificado server-side)
-- ----------------------------------------------------------------------------
create or replace function public.revogar_acesso_role_rpc(
  p_membership_id uuid,
  p_access_role_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_target_org uuid;
begin
  if p_actor_user_profile_id is null then
    raise exception 'F5-04: ator ausente (identidade verificada obrigatoria)';
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
     where m.user_profile_id = p_actor_user_profile_id
       and m.organization_id = v_target_org
       and m.status = 'active'
       and up.status = 'active'
  ) then
    raise exception 'F5-04: ator sem membership ativa na organizacao alvo (cross-tenant negado)';
  end if;

  -- AUTORIZAÇÃO ADMINISTRATIVA (D16/Q3): somente administrador do tenant.
  if not public.usuario_eh_administrador(p_actor_user_profile_id, v_target_org) then
    raise exception 'F5-04: ator sem autoridade administrativa (nao e administrador do tenant)';
  end if;

  perform public.revogar_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);

  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values
    (v_target_org, p_membership_id, p_access_role_id, 'revoke', p_actor_user_profile_id);
end;
$$;

comment on function public.revogar_acesso_role_rpc(uuid, uuid, uuid) is
  'F5-04 (D16): revogacao de access_role de membership por caminho '
  'server-side/transacional. Ator = identidade verificada server-side; tenant '
  'revalidado (cross-tenant DENY); AUTORIZACAO ADMINISTRATIVA (administrador do '
  'tenant); grava trilha D18. SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- Grants: EXECUTE somente service_role (sem superfície para authenticated/anon)
-- ----------------------------------------------------------------------------
revoke all on function public.usuario_eh_administrador(uuid, uuid) from public, anon, authenticated;
revoke all on function public.conceder_acesso_role_rpc(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.revogar_acesso_role_rpc(uuid, uuid, uuid) from public, anon, authenticated;

grant execute on function public.usuario_eh_administrador(uuid, uuid) to service_role;
grant execute on function public.conceder_acesso_role_rpc(uuid, uuid, uuid) to service_role;
grant execute on function public.revogar_acesso_role_rpc(uuid, uuid, uuid) to service_role;
