-- ============================================================================
-- F2-07 (Issue #74): profile desabilitado deixa de ser resolvido pelo usuário
-- ----------------------------------------------------------------------------
-- Propósito: reforçar no banco (RLS) que um user_profile com status
-- 'disabled' não é legível pelo próprio usuário. Assim, mesmo uma sessão/JWT
-- emitida antes da desativação não consegue resolver a identidade: a leitura do
-- próprio perfil retorna vazio e a resolução falha em acesso negado.
--
-- Justificativa (alteração mínima de RLS): sem isto, a resolução de identidade
-- dependeria apenas do frontend para bloquear um perfil desabilitado. As demais
-- policies permanecem inalteradas (memberships próprias continuam legíveis para
-- o usuário detectar o estado; organizações continuam restritas a membership
-- ativa — F2-03).
-- ============================================================================

drop policy if exists user_profiles_select_own on public.user_profiles;

create policy user_profiles_select_own on public.user_profiles
  for select to authenticated
  using (auth.uid() = id and status = 'active');
