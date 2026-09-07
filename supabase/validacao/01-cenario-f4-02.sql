-- ============================================================================
-- F4-02 (Issue #89): cenário sintético de validação — escopos de autorização
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f4-02.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F4-02);
--   - identidades/perfis/memberships sintéticas + vínculo membership →
--     collaborator (D1): MANAGER→GER, MULTI_USER→MULTI; NO_LINK/ADMIN sem
--     vínculo;
--   - estrutura F3 mínima (units + parent, positions, reporting lines,
--     occupations) para provar DIRECT_REPORTS/DESCENDANTS/UNIT/vaga/histórico/
--     multi-position;
--   - role customizada `gestao_equipe` (collaborator.read + evaluation.read)
--     atribuída com múltiplos scopes (DIRECT_REPORTS + DESCENDANTS +
--     ORGANIZATIONAL_UNIT sobre U_ROOT);
--   - `admin` (sistema) com scope ORGANIZATION EXPLÍCITO (D14), em Alfa e Beta;
--   - MULTI_USER com role+DESCENDANTS (união de múltiplas positions);
--   - NO_LINK com role+DESCENDANTS mas SEM vínculo (fail-closed).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql); nunca em remoto;
--   - insere via superuser local (service_role) SEM alterar policies;
--   - reexecutável: remove/recria somente os UUIDs fixos (prefixo d1);
--   - apenas dados sintéticos; nenhum dado real.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Limpeza do cenário anterior (ordem respeita FKs ON DELETE RESTRICT)
-- ----------------------------------------------------------------------------
delete from public.access_role_assignment_unit_targets
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_assignment_scopes
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.membership_access_role_assignments
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.membership_collaborator_links
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_capabilities
where access_role_id = 'd1f00000-0000-0000-0000-0000000000f1';

delete from public.access_roles
where id = 'd1f00000-0000-0000-0000-0000000000f1';

delete from public.user_organization_memberships
where organization_id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

delete from public.user_profiles
where id::text like 'd1b00000-0000-0000-0000-0000000000%';

delete from auth.users
where id::text like 'd1b00000-0000-0000-0000-0000000000%';

delete from public.occupations
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.position_reporting_lines
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_positions
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_unit_parent_periods
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_units
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.collaborators
where id::text like 'd1c00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id = 'd1a00000-0000-0000-0000-0000000000a1';

delete from public.organizations
where id in (
  'd1a00000-0000-0000-0000-0000000000a1',
  'd1a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações sintéticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('d1a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F4-02 Alfa'),
  ('d1a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F4-02 Beta');

-- ----------------------------------------------------------------------------
-- Identidades + perfis (sintéticos)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d1b00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin.a.f4-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d1b00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'manager.f4-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d1b00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'nolink.f4-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d1b00000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'multi.f4-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d1b00000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'actor.f4-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d1b00000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin.b.f4-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('d1b00000-0000-0000-0000-0000000000a1', 'active'),
  ('d1b00000-0000-0000-0000-0000000000a2', 'active'),
  ('d1b00000-0000-0000-0000-0000000000a3', 'active'),
  ('d1b00000-0000-0000-0000-0000000000a4', 'active'),
  ('d1b00000-0000-0000-0000-0000000000a5', 'active'),
  ('d1b00000-0000-0000-0000-0000000000a6', 'active');

-- ----------------------------------------------------------------------------
-- Memberships sintéticas
-- ----------------------------------------------------------------------------
insert into public.user_organization_memberships (id, user_profile_id, organization_id, status) values
  ('d1d00000-0000-0000-0000-0000000000a1', 'd1b00000-0000-0000-0000-0000000000a1', 'd1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d1d00000-0000-0000-0000-0000000000a2', 'd1b00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d1d00000-0000-0000-0000-0000000000a3', 'd1b00000-0000-0000-0000-0000000000a3', 'd1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d1d00000-0000-0000-0000-0000000000a4', 'd1b00000-0000-0000-0000-0000000000a4', 'd1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d1d00000-0000-0000-0000-0000000000a5', 'd1b00000-0000-0000-0000-0000000000a5', 'd1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d1d00000-0000-0000-0000-0000000000b1', 'd1b00000-0000-0000-0000-0000000000a6', 'd1a00000-0000-0000-0000-0000000000b1', 'active');

-- ----------------------------------------------------------------------------
-- job_role e colaboradores sintéticos (F3)
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name) values
  ('d1c00000-0000-0000-0000-0000000000e1', 'd1a00000-0000-0000-0000-0000000000a1', 'Analista');

insert into public.collaborators (id, organization_id) values
  ('d1c00000-0000-0000-0000-0000000000c1', 'd1a00000-0000-0000-0000-0000000000a1'),  -- DIR
  ('d1c00000-0000-0000-0000-0000000000c2', 'd1a00000-0000-0000-0000-0000000000a1'),  -- GER
  ('d1c00000-0000-0000-0000-0000000000c3', 'd1a00000-0000-0000-0000-0000000000a1'),  -- COORD
  ('d1c00000-0000-0000-0000-0000000000c4', 'd1a00000-0000-0000-0000-0000000000a1'),  -- AN1 (sai em 2024-06)
  ('d1c00000-0000-0000-0000-0000000000c7', 'd1a00000-0000-0000-0000-0000000000a1'),  -- SUCCESSOR
  ('d1c00000-0000-0000-0000-0000000000c6', 'd1a00000-0000-0000-0000-0000000000a1'),  -- MULTI (2 positions)
  ('d1c00000-0000-0000-0000-0000000000c8', 'd1a00000-0000-0000-0000-0000000000a1'),  -- MULTI_CHILD
  ('d1c00000-0000-0000-0000-0000000000d1', 'd1a00000-0000-0000-0000-0000000000b1');  -- BETA collab

-- ----------------------------------------------------------------------------
-- Unidades (F3): U_ROOT (pai) e U_CHILD (subunidade)
-- ----------------------------------------------------------------------------
insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('d1e00000-0000-0000-0000-0000000000c1', 'd1a00000-0000-0000-0000-0000000000a1', 'Unidade Raiz', '2024-01-01T00:00:00Z'),
  ('d1e00000-0000-0000-0000-0000000000c2', 'd1a00000-0000-0000-0000-0000000000a1', 'Unidade Filha', '2024-01-01T00:00:00Z');

insert into public.organizational_unit_parent_periods (organization_id, unit_id, parent_unit_id, valid_from) values
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c2', 'd1e00000-0000-0000-0000-0000000000c1', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Posições (F3) — todas com a função sintética 'Analista'
-- ----------------------------------------------------------------------------
insert into public.organizational_positions (id, organization_id, unit_id, job_role_id, valid_from) values
  ('d1e00000-0000-0000-0000-0000000000e0', 'd1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c1', 'd1c00000-0000-0000-0000-0000000000e1', '2024-01-01T00:00:00Z'),  -- P_DIR
  ('d1e00000-0000-0000-0000-0000000000e1', 'd1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c1', 'd1c00000-0000-0000-0000-0000000000e1', '2024-01-01T00:00:00Z'),  -- P_GER
  ('d1e00000-0000-0000-0000-0000000000e2', 'd1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c2', 'd1c00000-0000-0000-0000-0000000000e1', '2024-01-01T00:00:00Z'),  -- P_COORD
  ('d1e00000-0000-0000-0000-0000000000e3', 'd1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c2', 'd1c00000-0000-0000-0000-0000000000e1', '2024-01-01T00:00:00Z'),  -- P_AN1
  ('d1e00000-0000-0000-0000-0000000000e4', 'd1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c2', 'd1c00000-0000-0000-0000-0000000000e1', '2024-01-01T00:00:00Z'),  -- P_AN2
  ('d1e00000-0000-0000-0000-0000000000e5', 'd1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c2', 'd1c00000-0000-0000-0000-0000000000e1', '2024-01-01T00:00:00Z'),  -- P_MULTI2
  ('d1e00000-0000-0000-0000-0000000000e8', 'd1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c2', 'd1c00000-0000-0000-0000-0000000000e1', '2024-01-01T00:00:00Z'),  -- P_MULTI_CHILD
  ('d1e00000-0000-0000-0000-0000000000e6', 'd1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000c2', 'd1c00000-0000-0000-0000-0000000000e1', '2024-01-01T00:00:00Z');  -- P_VACANT

-- ----------------------------------------------------------------------------
-- Reporting lines (F3): P_DIR é raiz (sem linha)
-- ----------------------------------------------------------------------------
insert into public.position_reporting_lines (organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000e1', 'd1e00000-0000-0000-0000-0000000000e0', 'estrutura sintetica', '2024-01-01T00:00:00Z'),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000e2', 'd1e00000-0000-0000-0000-0000000000e1', 'estrutura sintetica', '2024-01-01T00:00:00Z'),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000e3', 'd1e00000-0000-0000-0000-0000000000e2', 'estrutura sintetica', '2024-01-01T00:00:00Z'),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000e4', 'd1e00000-0000-0000-0000-0000000000e2', 'estrutura sintetica', '2024-01-01T00:00:00Z'),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000e5', 'd1e00000-0000-0000-0000-0000000000e2', 'estrutura sintetica', '2024-01-01T00:00:00Z'),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000e8', 'd1e00000-0000-0000-0000-0000000000e5', 'estrutura sintetica', '2024-01-01T00:00:00Z'),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1e00000-0000-0000-0000-0000000000e6', 'd1e00000-0000-0000-0000-0000000000e2', 'estrutura sintetica', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Occupations (F3): troca em P_AN1 (histórico); MULTI em 2 positions; P_VACANT vazia
-- ----------------------------------------------------------------------------
insert into public.occupations (organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to) values
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c1', 'd1e00000-0000-0000-0000-0000000000e0', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c2', 'd1e00000-0000-0000-0000-0000000000e1', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c3', 'd1e00000-0000-0000-0000-0000000000e2', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c4', 'd1e00000-0000-0000-0000-0000000000e3', 'ocupacao sintetica', '2024-01-01T00:00:00Z', '2024-06-01T00:00:00Z'),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c7', 'd1e00000-0000-0000-0000-0000000000e3', 'sucessao sintetica', '2024-06-01T00:00:00Z', null),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c6', 'd1e00000-0000-0000-0000-0000000000e4', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c6', 'd1e00000-0000-0000-0000-0000000000e5', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('d1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c8', 'd1e00000-0000-0000-0000-0000000000e8', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Vínculo membership → collaborator (F4-02, D1)
-- ----------------------------------------------------------------------------
insert into public.membership_collaborator_links (membership_id, organization_id, collaborator_id, status) values
  ('d1d00000-0000-0000-0000-0000000000a2', 'd1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c2', 'active'),  -- MANAGER -> GER
  ('d1d00000-0000-0000-0000-0000000000a4', 'd1a00000-0000-0000-0000-0000000000a1', 'd1c00000-0000-0000-0000-0000000000c6', 'active');  -- MULTI_USER -> MULTI

-- ----------------------------------------------------------------------------
-- Role customizada `gestao_equipe` (Alfa): collaborator.read + evaluation.read
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('d1f00000-0000-0000-0000-0000000000f1', 'gestao_equipe', 'active', false, 'd1a00000-0000-0000-0000-0000000000a1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'd1f00000-0000-0000-0000-0000000000f1'
   and c.code in ('collaborator.read', 'evaluation.read');

-- ----------------------------------------------------------------------------
-- Atribuições (F4-01 conceder) + scopes (F4-02)
-- ----------------------------------------------------------------------------
select public.conceder_acesso_role(
  'd1d00000-0000-0000-0000-0000000000a1', 'c0000000-0000-4000-8000-0000000000f1', 'd1b00000-0000-0000-0000-0000000000a5');  -- ADMIN_A <- admin
select public.conceder_acesso_role(
  'd1d00000-0000-0000-0000-0000000000a2', 'd1f00000-0000-0000-0000-0000000000f1', 'd1b00000-0000-0000-0000-0000000000a5');  -- MANAGER <- gestao_equipe
select public.conceder_acesso_role(
  'd1d00000-0000-0000-0000-0000000000a3', 'd1f00000-0000-0000-0000-0000000000f1', 'd1b00000-0000-0000-0000-0000000000a5');  -- NO_LINK <- gestao_equipe
select public.conceder_acesso_role(
  'd1d00000-0000-0000-0000-0000000000a4', 'd1f00000-0000-0000-0000-0000000000f1', 'd1b00000-0000-0000-0000-0000000000a5');  -- MULTI_USER <- gestao_equipe
select public.conceder_acesso_role(
  'd1d00000-0000-0000-0000-0000000000b1', 'c0000000-0000-4000-8000-0000000000f1', 'd1b00000-0000-0000-0000-0000000000a6');  -- ADMIN_B <- admin

-- ADMIN_A <- ORGANIZATION (scope EXPLÍCITO — D14)
insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'ORGANIZATION', 'active', 'd1b00000-0000-0000-0000-0000000000a5'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a1'
   and a.access_role_id = 'c0000000-0000-4000-8000-0000000000f1';

-- ADMIN_B <- ORGANIZATION (scope EXPLÍCITO)
insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'ORGANIZATION', 'active', 'd1b00000-0000-0000-0000-0000000000a6'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd1d00000-0000-0000-0000-0000000000b1'
   and a.access_role_id = 'c0000000-0000-4000-8000-0000000000f1';

-- MANAGER <- DIRECT_REPORTS + DESCENDANTS (mesma role, múltiplos scopes — D4)
insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'DIRECT_REPORTS', 'active', 'd1b00000-0000-0000-0000-0000000000a5'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a2';

insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'DESCENDANTS', 'active', 'd1b00000-0000-0000-0000-0000000000a5'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a2';

-- MANAGER <- ORGANIZATIONAL_UNIT sobre U_ROOT (target tipado; sem subunidades)
insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'ORGANIZATIONAL_UNIT', 'active', 'd1b00000-0000-0000-0000-0000000000a5'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a2';

insert into public.access_role_assignment_unit_targets (scope_id, organization_id, organizational_unit_id)
select s.id, s.organization_id, 'd1e00000-0000-0000-0000-0000000000c1'
  from public.access_role_assignment_scopes s
 where s.assignment_id = (
   select a.id from public.membership_access_role_assignments a
   where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a2'
 )
   and s.scope_type = 'ORGANIZATIONAL_UNIT';

-- NO_LINK <- DESCENDANTS (sem vínculo -> fail-closed)
insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'DESCENDANTS', 'active', 'd1b00000-0000-0000-0000-0000000000a5'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a3';

-- MULTI_USER <- DESCENDANTS (união de múltiplas positions)
insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'DESCENDANTS', 'active', 'd1b00000-0000-0000-0000-0000000000a5'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd1d00000-0000-0000-0000-0000000000a4';
