-- ============================================================================
-- F5-02 (vínculo usuário autenticado ↔ colaborador): cardinalidade e histórico
-- ----------------------------------------------------------------------------
-- Q6 = B (fechada): múltiplas linhas históricas por membership, mantendo no
-- máximo 1 linha `status='active'` por membership_id.
-- Q3 = B (fechada): no máximo 1 vínculo `status='active'` por
-- (collaborator_id, organization_id) — impede duas contas/memberships ativas
-- representando simultaneamente o mesmo colaborador no mesmo tenant.
--
-- Mudanças:
--   1) remove a unicidade TOTAL atual de membership_id
--      (uq_membership_collaborator_links_membership);
--   2) cria unique index PARCIAL (1 active por membership_id);
--   3) cria unique index PARCIAL (1 active por collaborator+organization).
--
-- Nota (exceção documentada à convenção F1-02 "unicidade exige constraint
-- unique própria"): o PostgreSQL não permite predicado (WHERE) em `UNIQUE`
-- constraint; unicidade parcial é expressa por **unique index com predicado**
-- — exceção aprovada no contrato F5-02 (§15). Linhas `disabled` permanecem
-- como histórico e NÃO participam da unicidade parcial.
--
-- FKs compostas existentes (tenant correlation) são preservadas: cross-tenant
-- continua impossível no banco. Sem novas colunas/tabelas e sem
-- valid_from/valid_to (Q6=B, item 5).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Drop da unicidade total por membership (contrato anterior F4-02)
-- ----------------------------------------------------------------------------
alter table public.membership_collaborator_links
  drop constraint if exists uq_membership_collaborator_links_membership;

-- ----------------------------------------------------------------------------
-- 2) Q6 = B: no máximo 1 link ACTIVE por membership
-- ----------------------------------------------------------------------------
create unique index uq_membership_collaborator_links_active_membership
  on public.membership_collaborator_links (membership_id)
  where status = 'active';

comment on index public.uq_membership_collaborator_links_active_membership is
  'F5-02 (Q6=B): no maximo 1 vinculo status=active por membership_id '
  '(unicidade parcial — excecao documentada da F1-02). Linhas disabled '
  'historicas sao permitidas.';

-- ----------------------------------------------------------------------------
-- 3) Q3 = B: no máximo 1 link ACTIVE por (collaborator_id, organization_id)
-- ----------------------------------------------------------------------------
create unique index uq_membership_collaborator_links_active_collaborator
  on public.membership_collaborator_links (collaborator_id, organization_id)
  where status = 'active';

comment on index public.uq_membership_collaborator_links_active_collaborator is
  'F5-02 (Q3=B): no maximo 1 vinculo status=active por '
  '(collaborator_id, organization_id) — impede duas contas/memberships ativas '
  'representando o mesmo colaborador no mesmo tenant.';
