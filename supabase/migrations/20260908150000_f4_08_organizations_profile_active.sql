-- ============================================================================
-- F4-08 (Issue #95): organizations exige profile ATIVO + membership ATIVA (D1)
-- ----------------------------------------------------------------------------
-- A policy anterior `organizations_select_via_membership` (F2-03) verificava
-- somente membership ativa; um usuário com profile INATIVO ainda enxergava a
-- organização. A fronteira soberana D1 exige auth.uid() + user_profile ATIVO +
-- membership ATIVA.
--
-- Corrige substituindo (drop + create) a policy pela condição via helper
-- `user_has_active_membership` (que já valida profile ativo + membership ativa).
-- Policies permissivas combinam por OR, então NÃO se adiciona outra policy em
-- paralelo à antiga: a antiga é removida antes (sem janela permissiva).
--
-- Grafo de dependência permanece acíclico: organizations → helper →
-- user_profiles/user_organization_memberships (cujas policies usam apenas
-- auth.uid(), sem referenciar organizations nem o helper).
-- ============================================================================

drop policy organizations_select_via_membership on public.organizations;

create policy organizations_select_via_membership on public.organizations
  for select to authenticated
  using (public.user_has_active_membership(organizations.id));

comment on policy organizations_select_via_membership on public.organizations is
  'F4-08 (D1): somente organizacoes com membership ATIVA + profile ATIVO do '
  'auth.uid(). Substitui a versao F2-03 que nao validava profile ativo.';
