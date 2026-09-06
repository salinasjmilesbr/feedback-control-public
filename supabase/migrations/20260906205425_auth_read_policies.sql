-- ============================================================================
-- F2-03 (Issue #70): policies mínimas de leitura para identidade/sessão
-- ----------------------------------------------------------------------------
-- Propósito: permitir que o usuário autenticado resolva a própria identidade
-- (auth.uid() -> user_profiles -> memberships ativas -> organizations), somente
-- na extensão estritamente necessária, preservando tenant isolation e o
-- deny-by-default das F2-01/F2-02.
--
-- Fora do escopo desta migration (não antecipar — Issue #70):
--   - policies de INSERT/UPDATE/DELETE para o frontend (nenhuma nesta etapa);
--   - SELECT amplo por `authenticated`;
--   - authorization por capability, roles, colaboradores ou estrutura
--     organizacional;
--   - recuperação de senha, convites ou administração.
--
-- Fronteira de segurança desta etapa: a RLS. O Supabase já concede por padrão
-- privilégios de DML a `authenticated`/`anon`/`service_role` sobre `public`;
-- por isso a ausência de policies de escrita é o que mantém INSERT/UPDATE/
-- DELETE negados para o frontend (INSERT é rejeitado e UPDATE/DELETE afetam
-- zero linhas). O grant de SELECT abaixo é explícito e documenta a intenção de
-- leitura. `service_role` ignora RLS por definição e é de uso exclusivo
-- server-side — nunca no frontend.
-- ============================================================================

grant select on public.user_profiles to authenticated;
grant select on public.user_organization_memberships to authenticated;
grant select on public.organizations to authenticated;

-- Perfil interno: cada usuário lê somente o próprio perfil.
create policy user_profiles_select_own on public.user_profiles
  for select to authenticated
  using (auth.uid() = id);

-- Memberships: cada usuário lê somente as próprias memberships.
create policy user_organization_memberships_select_own on public.user_organization_memberships
  for select to authenticated
  using (user_profile_id = auth.uid());

-- Organizações: somente aquelas às quais o usuário possui membership ativa.
create policy organizations_select_via_membership on public.organizations
  for select to authenticated
  using (
    exists (
      select 1
      from public.user_organization_memberships as m
      where m.organization_id = organizations.id
        and m.user_profile_id = auth.uid()
        and m.status = 'active'
    )
  );
