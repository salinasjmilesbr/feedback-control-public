-- ============================================================================
-- F2-06 (Issue #73): RPC server-side para criação atômica de perfil+membership
-- ----------------------------------------------------------------------------
-- Propósito: dar à Edge Function de convite uma única chamada transacional que
-- cria o perfil interno e a membership (ou nada), evitando estado parcial caso
-- a segunda inserção falhe. A criação do usuário no Auth é feita pelo Auth
-- Admin na Edge Function; em falha aqui, a função compensa removendo o usuário
-- recém-criado.
--
-- Segurança:
--   - SECURITY DEFINER, `set search_path = public` (sem hijack de search_path);
--   - EXECUTE concedido SOMENTE a `service_role`: o frontend (`authenticated`)
--     não consegue executar esta RPC via PostgREST — é a fronteira server-side.
--
-- Fora do escopo (não antecipar): roles/capabilities (Fase 4), auditoria
-- (contrato pendente da etapa de auditoria), gestão ampla de usuários.
-- ============================================================================

create or replace function public.criar_perfil_membership(
  p_user_id uuid,
  p_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (id)
  values (p_user_id);

  insert into public.user_organization_memberships (user_profile_id, organization_id)
  values (p_user_id, p_organization_id);
end;
$$;

comment on function public.criar_perfil_membership(uuid, uuid) is
  'F2-06: cria user_profile (1:1 com auth.users) e a membership em uma unica '
  'transacao. Em violacao de FK/unique, toda a transacao e revertida.';

revoke all on function public.criar_perfil_membership(uuid, uuid) from public, anon, authenticated;
grant execute on function public.criar_perfil_membership(uuid, uuid) to service_role;
