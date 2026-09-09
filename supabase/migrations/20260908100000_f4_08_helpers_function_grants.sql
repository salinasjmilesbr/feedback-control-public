-- ============================================================================
-- F4-08 (Issue #95): helper de tenant boundary + endurecimento de grants das
-- funções INVOKER (resolvers/RPC)
-- ----------------------------------------------------------------------------
-- Propósito (contrato F4-08 §9/§11/§12.3):
--   - criar o ÚNICO helper conceitual `user_has_active_membership(org_id)`,
--     SECURITY INVOKER, STABLE, search_path=public, sem DEFINER e sem recursão
--     (raiz do grafo acíclico de policies: consulta somente
--     user_organization_memberships, cuja policy usa apenas auth.uid());
--   - REVOKE EXECUTE FROM PUBLIC nas 16 funções INVOKER de resolução/RPC e
--     GRANT EXECUTE somente a service_role (uso interno/futuro server-side);
--     não confiar no "RLS bloqueia tudo" atual.
--
-- A ordem respeita D21: helper (fundação) primeiro, grants/revokes em seguida,
-- e "policy pronta antes de conceder acesso" — o helper só é usado pelas
-- policies criadas nas migrations seguintes.
--
-- Fora de escopo: nenhum novo SECURITY DEFINER; nenhuma ampliação de EXECUTE
-- dos 4 DEFINER existentes; nenhum grant a authenticated/anon para as funções
-- revogadas (authenticated não chama resolvers/RPC — §11).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Helper único de tenant boundary (D4)
-- ----------------------------------------------------------------------------
create or replace function public.user_has_active_membership(
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
    where m.organization_id = p_organization_id
      and m.user_profile_id = auth.uid()
      and m.status = 'active'
  );
$$;

comment on function public.user_has_active_membership(uuid) is
  'F4-08 (Issue #95): responde se o usuario autenticado (auth.uid()) possui '
  'membership ATIVA na organizacao informada. SECURITY INVOKER, STABLE, '
  'search_path=public; raiz do grafo aciclico de policies (consulta somente '
  'user_organization_memberships, cuja policy usa apenas auth.uid()). Nunca '
  'aceita organizacao vinda do frontend como prova — apenas correlaciona o id '
  'da linha com a membership soberana do banco.';

revoke execute on function public.user_has_active_membership(uuid) from public, anon;
grant execute on function public.user_has_active_membership(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 2) REVOKE EXECUTE FROM PUBLIC + GRANT EXECUTE TO service_role (16 INVOKER)
-- ----------------------------------------------------------------------------
-- F3-07 (resolvers estruturais operacionais):
revoke execute on function public.organizacao_resolver_responsavel_posicao(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.organizacao_resolver_gestor_direto(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.organizacao_resolver_subordinados_diretos(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.organizacao_resolver_descendentes(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.organizacao_resolver_cadeia(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.organizacao_resolver_escopo_posicoes(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.organizacao_resolver_escopo_unidades(uuid, timestamptz) from public, anon, authenticated;

-- F3-09 (resolvers avaliativos + RPCs de materialização/sucessão):
revoke execute on function public.organizacao_resolver_responsavel_avaliativo_posicao(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.organizacao_resolver_avaliador_avaliado(uuid, timestamptz) from public, anon, authenticated;
revoke execute on function public.resolver_responsavel_avaliacao_vigente(uuid, integer, integer, timestamptz) from public, anon, authenticated;
revoke execute on function public.materializar_colegiado_ciclo(uuid, integer, integer, timestamptz, uuid[]) from public, anon, authenticated;
revoke execute on function public.materializar_responsabilidades_avaliacao(uuid, integer, integer) from public, anon, authenticated;
revoke execute on function public.registrar_sucessao_avaliador(uuid[], timestamptz, text, uuid) from public, anon, authenticated;

-- F4-02 (resolvers de escopo/autorização):
revoke execute on function public.resolver_collaborador_vinculado(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.resolver_capabilities_escopos_efetivas(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.resolver_alvos_escopo(uuid, uuid, text, uuid, timestamptz) from public, anon, authenticated;

-- GRANT explícito somente a service_role (caminho interno/futuro server-side).
grant execute on function public.organizacao_resolver_responsavel_posicao(uuid, timestamptz) to service_role;
grant execute on function public.organizacao_resolver_gestor_direto(uuid, timestamptz) to service_role;
grant execute on function public.organizacao_resolver_subordinados_diretos(uuid, timestamptz) to service_role;
grant execute on function public.organizacao_resolver_descendentes(uuid, timestamptz) to service_role;
grant execute on function public.organizacao_resolver_cadeia(uuid, timestamptz) to service_role;
grant execute on function public.organizacao_resolver_escopo_posicoes(uuid, timestamptz) to service_role;
grant execute on function public.organizacao_resolver_escopo_unidades(uuid, timestamptz) to service_role;
grant execute on function public.organizacao_resolver_responsavel_avaliativo_posicao(uuid, timestamptz) to service_role;
grant execute on function public.organizacao_resolver_avaliador_avaliado(uuid, timestamptz) to service_role;
grant execute on function public.resolver_responsavel_avaliacao_vigente(uuid, integer, integer, timestamptz) to service_role;
grant execute on function public.materializar_colegiado_ciclo(uuid, integer, integer, timestamptz, uuid[]) to service_role;
grant execute on function public.materializar_responsabilidades_avaliacao(uuid, integer, integer) to service_role;
grant execute on function public.registrar_sucessao_avaliador(uuid[], timestamptz, text, uuid) to service_role;
grant execute on function public.resolver_collaborador_vinculado(uuid, uuid) to service_role;
grant execute on function public.resolver_capabilities_escopos_efetivas(uuid, uuid) to service_role;
grant execute on function public.resolver_alvos_escopo(uuid, uuid, text, uuid, timestamptz) to service_role;
