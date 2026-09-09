-- ============================================================================
-- F5-02 (vínculo usuário autenticado ↔ colaborador): endurecer o resolver
-- ----------------------------------------------------------------------------
-- Q4 = A (fechada): `resolver_collaborador_vinculado` passa a exigir
-- `user_profiles.status = 'active'` (paridade com
-- `resolver_capabilities_escopos_efetivas` e com a fronteira D1/F4-08).
--
--   - profile ausente/inativo/desconhecido ⇒ resolução VAZIA (fail-closed);
--   - apenas o link `status='active'` resolve (linhas `disabled` são histórico
--     — Q6 = B); a unicidade parcial (migration seguinte) garante no máx. 1 ativo
--     por membership;
--   - mantém `SECURITY INVOKER`, `STABLE` e `search_path = public`;
--   - mantém fechado para `authenticated` (Q1 = A): sem nova superfície de
--     leitura, sem `EXECUTE` para `authenticated`, sem novo `SECURITY DEFINER`
--     (Q2 N/A → F5-05); F4-02 D18 inalterado.
--
-- Aditiva: `create or replace` preserva o contrato e os grants já aplicados na
-- F4-08 (sem EXECUTE para `public`/`anon`/`authenticated`; EXECUTE só
-- `service_role`).
-- ============================================================================

create or replace function public.resolver_collaborador_vinculado(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns table (collaborator_id uuid)
language sql
stable
security invoker
set search_path = public
as $$
  select l.collaborator_id
    from public.user_organization_memberships m
    join public.user_profiles up
      on up.id = m.user_profile_id
     and up.status = 'active'
    join public.membership_collaborator_links l
      on l.membership_id = m.id
     and l.status = 'active'
   where m.user_profile_id = p_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active'
$$;

comment on function public.resolver_collaborador_vinculado(uuid, uuid) is
  'F5-02 (Q4=A): colaborador vinculado a membership ATIVA do usuario, exigindo '
  'tambem user_profile ATIVO (fronteira D1/F4-08). Profile ausente/inativo/ '
  'desconhecido => vazio (fail-closed). Somente o link status=active resolve '
  '(linhas disabled sao historico — Q6=B). SECURITY INVOKER, STABLE, '
  'search_path=public; sem EXECUTE para authenticated (Q1=A).';
