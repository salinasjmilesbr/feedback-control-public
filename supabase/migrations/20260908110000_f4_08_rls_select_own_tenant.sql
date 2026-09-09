-- ============================================================================
-- F4-08 (Issue #95): policies SELECT own-tenant sobre as tabelas estruturais,
-- filha indireta e snapshots (RLS de tenant boundary)
-- ----------------------------------------------------------------------------
-- Propósito (contrato F4-08 §5.2/§5.3/§5.4/§6):
--   - membership ATIVA dá visibilidade estrutural BASE do PRÓPRIO tenant;
--   - RLS NÃO implementa DIRECT_REPORTS/DESCENDANTS/ASSIGNED/scopes/
--     capabilities (continuam no Policy Engine);
--   - sem INSERT/UPDATE/DELETE direto por authenticated: mutações continuam em
--     funções/RPCs transacionais (deny-by-default);
--   - `collaborator_status_periods` (sem organization_id) usa EXISTS via
--     collaborators (fail-closed se parent inexistente/órfão);
--   - `evaluation_succession_events` (auditoria) e tabelas de segurança
--     (F4-01/F4-02) permanecem FECHADAS (sem policy nesta fase).
--
-- Policy pronta ANTES do grant correspondente (D21): cada tabela recebe a
-- policy e, em seguida, o grant SELECT a authenticated. Deny-by-default
-- intermediário é seguro.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A) Raízes de tenant estruturais (13) — SELECT own-tenant
-- ----------------------------------------------------------------------------

create policy collaborators_select_same_tenant on public.collaborators
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy collaborator_identifiers_select_same_tenant on public.collaborator_identifiers
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy job_roles_select_same_tenant on public.job_roles
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy seniority_levels_select_same_tenant on public.seniority_levels
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy organizational_units_select_same_tenant on public.organizational_units
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy organizational_unit_parent_periods_select_same_tenant on public.organizational_unit_parent_periods
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy organizational_positions_select_same_tenant on public.organizational_positions
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy position_reporting_lines_select_same_tenant on public.position_reporting_lines
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy occupations_select_same_tenant on public.occupations
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy temporary_responsibilities_select_same_tenant on public.temporary_responsibilities
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy collegiate_configurations_select_same_tenant on public.collegiate_configurations
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy collegiate_configuration_members_select_same_tenant on public.collegiate_configuration_members
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy cycle_evaluation_responsibilities_select_same_tenant on public.cycle_evaluation_responsibilities
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

-- ----------------------------------------------------------------------------
-- B) Filha indireta (sem organization_id) — EXISTS via parent tenant-rooted
-- ----------------------------------------------------------------------------

create policy collaborator_status_periods_select_same_tenant on public.collaborator_status_periods
  for select to authenticated
  using (
    exists (
      select 1
      from public.collaborators c
      where c.id = collaborator_status_periods.collaborator_id
        and public.user_has_active_membership(c.organization_id)
    )
  );

-- ----------------------------------------------------------------------------
-- E) Snapshots/histórico F3-08 (leitura own-tenant; sem UPDATE/DELETE)
-- ----------------------------------------------------------------------------

create policy collegiate_cycle_snapshots_select_same_tenant on public.collegiate_cycle_snapshots
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy collegiate_cycle_snapshot_positions_select_same_tenant on public.collegiate_cycle_snapshot_positions
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

create policy collegiate_cycle_snapshot_members_select_same_tenant on public.collegiate_cycle_snapshot_members
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

-- ----------------------------------------------------------------------------
-- Grants SELECT a authenticated (após as policies — D21/D17)
-- ----------------------------------------------------------------------------

grant select on public.collaborators to authenticated;
grant select on public.collaborator_identifiers to authenticated;
grant select on public.job_roles to authenticated;
grant select on public.seniority_levels to authenticated;
grant select on public.organizational_units to authenticated;
grant select on public.organizational_unit_parent_periods to authenticated;
grant select on public.organizational_positions to authenticated;
grant select on public.position_reporting_lines to authenticated;
grant select on public.occupations to authenticated;
grant select on public.temporary_responsibilities to authenticated;
grant select on public.collegiate_configurations to authenticated;
grant select on public.collegiate_configuration_members to authenticated;
grant select on public.cycle_evaluation_responsibilities to authenticated;
grant select on public.collaborator_status_periods to authenticated;
grant select on public.collegiate_cycle_snapshots to authenticated;
grant select on public.collegiate_cycle_snapshot_positions to authenticated;
grant select on public.collegiate_cycle_snapshot_members to authenticated;
