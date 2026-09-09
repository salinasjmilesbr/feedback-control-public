-- ============================================================================
-- F4-08 (Issue #95): cenário sintético de validação — RLS base e isolamento
-- real entre tenants (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f4-08.sql, com fixtures POSITIVAS em TODAS as
-- tabelas abertas (A/B/E + capabilities) e dados de fixture nas tabelas
-- FECHADAS (segurança/auditoria), para eliminar falsos PASS por tabela vazia.
--
--   - três organizações sintéticas (Alfa, Beta e Gama);
--   - identidades/perfis: USER_A (só Alfa), USER_B (só Beta), USER_AB
--     (Alfa+Beta), USER_INACTIVE (membership Alfa disabled),
--     USER_PROFILE_INACTIVE (profile disabled + membership Alfa active),
--     USER_NONE (sem membership) e AUTHOR (autor de sucessão/atribuição);
--   - estrutura F3 completa por org (job_role, seniority, 2 unidades + parent,
--     2 posições + reporting line, 3 colaboradores + identifiers + status,
--     occupations, temporary responsibility, colegiado + membro, snapshot +
--     snapshot_positions + snapshot_members + responsabilidade avaliativa);
--   - tabelas de segurança (F4-01/F4-02) com role customizada, capabilities,
--     assignment, scope, unit target e membership_collaborator_link por org.
--
-- Regras: somente Supabase local; insere via superuser (postgres) SEM alterar
-- policies; reexecutável (prefixo d8); apenas dados sintéticos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Limpeza do cenário anterior (ordem respeita FKs ON DELETE RESTRICT)
-- ----------------------------------------------------------------------------
delete from public.evaluation_succession_events
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.cycle_evaluation_responsibilities
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_members
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_positions
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshots
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configuration_members
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configurations
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.temporary_responsibilities
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.occupations
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.position_reporting_lines
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.access_role_assignment_unit_targets
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.access_role_assignment_scopes
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.membership_access_role_assignments
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.membership_collaborator_links
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.access_role_capabilities
where access_role_id::text like 'd8f00000-0000-0000-0000-0000000000f%';

delete from public.access_roles
where id::text like 'd8f00000-0000-0000-0000-0000000000f%';

delete from public.organizational_positions
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.organizational_unit_parent_periods
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.organizational_units
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collaborator_identifiers
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
where collaborator_id::text like 'd8c00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id::text like 'd8c00000-0000-0000-0000-0000000000%';

delete from public.seniority_levels
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.user_organization_memberships
where id::text like 'd8d00000-0000-0000-0000-0000000000%';

delete from public.user_profiles
where id::text like 'd8b00000-0000-0000-0000-0000000000%';

delete from auth.users
where id::text like 'd8b00000-0000-0000-0000-0000000000%';

delete from public.organizations
where id::text like 'd8a00000-0000-0000-0000-0000000000%';

-- ----------------------------------------------------------------------------
-- Organizações sintéticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('d8a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F4-08 Alfa'),
  ('d8a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F4-08 Beta'),
  ('d8a00000-0000-0000-0000-0000000000c1', 'Org Sintetica F4-08 Gama');

-- ----------------------------------------------------------------------------
-- Identidades + perfis
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d8b00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'usera.f4-08@example.invalid', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'userb.f4-08@example.invalid', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'userab.f4-08@example.invalid', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'userinactive.f4-08@example.invalid', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'usernone.f4-08@example.invalid', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'author.f4-08@example.invalid', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'profileinactive.f4-08@example.invalid', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('d8b00000-0000-0000-0000-0000000000a1', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a2', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a3', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a4', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a5', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a6', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a7', 'disabled');

-- ----------------------------------------------------------------------------
-- Memberships
-- ----------------------------------------------------------------------------
insert into public.user_organization_memberships (id, user_profile_id, organization_id, status) values
  ('d8d00000-0000-0000-0000-0000000000a1', 'd8b00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1', 'active'),  -- USER_A -> Alfa
  ('d8d00000-0000-0000-0000-0000000000a2', 'd8b00000-0000-0000-0000-0000000000a2', 'd8a00000-0000-0000-0000-0000000000b1', 'active'),  -- USER_B -> Beta
  ('d8d00000-0000-0000-0000-0000000000a3', 'd8b00000-0000-0000-0000-0000000000a3', 'd8a00000-0000-0000-0000-0000000000a1', 'active'),  -- USER_AB -> Alfa
  ('d8d00000-0000-0000-0000-0000000000a4', 'd8b00000-0000-0000-0000-0000000000a3', 'd8a00000-0000-0000-0000-0000000000b1', 'active'),  -- USER_AB -> Beta
  ('d8d00000-0000-0000-0000-0000000000a5', 'd8b00000-0000-0000-0000-0000000000a4', 'd8a00000-0000-0000-0000-0000000000a1', 'disabled'), -- USER_INACTIVE -> Alfa disabled
  ('d8d00000-0000-0000-0000-0000000000a6', 'd8b00000-0000-0000-0000-0000000000a7', 'd8a00000-0000-0000-0000-0000000000a1', 'active'),  -- USER_PROFILE_INACTIVE -> Alfa active
  ('d8d00000-0000-0000-0000-0000000000a7', 'd8b00000-0000-0000-0000-0000000000a6', 'd8a00000-0000-0000-0000-0000000000a1', 'active');  -- AUTHOR -> Alfa active

-- ----------------------------------------------------------------------------
-- Catálogos: job_roles + seniority_levels
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name) values
  ('d8e00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1', 'Analista Alfa'),
  ('d8e00000-0000-0000-0000-0000000000b1', 'd8a00000-0000-0000-0000-0000000000b1', 'Analista Beta'),
  ('d8e00000-0000-0000-0000-0000000000c1', 'd8a00000-0000-0000-0000-0000000000c1', 'Analista Gama');

insert into public.seniority_levels (id, organization_id, name) values
  ('d8e00000-0000-0000-0000-0000000000a2', 'd8a00000-0000-0000-0000-0000000000a1', 'Pleno'),
  ('d8e00000-0000-0000-0000-0000000000b2', 'd8a00000-0000-0000-0000-0000000000b1', 'Pleno'),
  ('d8e00000-0000-0000-0000-0000000000c2', 'd8a00000-0000-0000-0000-0000000000c1', 'Pleno');

-- ----------------------------------------------------------------------------
-- Unidades (2 por org) + composição pai/filho
-- ----------------------------------------------------------------------------
insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('d8f00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1', 'Unidade Alfa Raiz',  '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000a2', 'd8a00000-0000-0000-0000-0000000000a1', 'Unidade Alfa Filha', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000b1', 'd8a00000-0000-0000-0000-0000000000b1', 'Unidade Beta Raiz',  '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000b2', 'd8a00000-0000-0000-0000-0000000000b1', 'Unidade Beta Filha', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000c1', 'd8a00000-0000-0000-0000-0000000000c1', 'Unidade Gama Raiz',  '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000c2', 'd8a00000-0000-0000-0000-0000000000c1', 'Unidade Gama Filha', '2024-01-01T00:00:00Z');

insert into public.organizational_unit_parent_periods (organization_id, unit_id, parent_unit_id, valid_from) values
  ('d8a00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000a2', 'd8f00000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000b2', 'd8f00000-0000-0000-0000-0000000000b1', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000c2', 'd8f00000-0000-0000-0000-0000000000c1', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Posições (P1 = superior, P2 = avaliado) + reporting line P2 -> P1
-- ----------------------------------------------------------------------------
insert into public.organizational_positions (id, organization_id, unit_id, job_role_id, valid_from) values
  ('d8f00000-0000-0000-0000-0000000000d1', 'd8a00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000a1', 'd8e00000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000d2', 'd8a00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000a2', 'd8e00000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000d3', 'd8a00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000b1', 'd8e00000-0000-0000-0000-0000000000b1', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000d4', 'd8a00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000b2', 'd8e00000-0000-0000-0000-0000000000b1', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000d5', 'd8a00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000c1', 'd8e00000-0000-0000-0000-0000000000c1', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000d6', 'd8a00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000c2', 'd8e00000-0000-0000-0000-0000000000c1', '2024-01-01T00:00:00Z');

insert into public.position_reporting_lines (organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('d8a00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000d2', 'd8f00000-0000-0000-0000-0000000000d1', 'sintetica', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000d4', 'd8f00000-0000-0000-0000-0000000000d3', 'sintetica', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000d6', 'd8f00000-0000-0000-0000-0000000000d5', 'sintetica', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Colaboradores (C1 = titular de P1; C2 = titular de P2; C3 = avaliador antigo)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('d8c00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1'),
  ('d8c00000-0000-0000-0000-0000000000a2', 'd8a00000-0000-0000-0000-0000000000a1'),
  ('d8c00000-0000-0000-0000-0000000000a3', 'd8a00000-0000-0000-0000-0000000000a1'),
  ('d8c00000-0000-0000-0000-0000000000b1', 'd8a00000-0000-0000-0000-0000000000b1'),
  ('d8c00000-0000-0000-0000-0000000000b2', 'd8a00000-0000-0000-0000-0000000000b1'),
  ('d8c00000-0000-0000-0000-0000000000b3', 'd8a00000-0000-0000-0000-0000000000b1'),
  ('d8c00000-0000-0000-0000-0000000000c1', 'd8a00000-0000-0000-0000-0000000000c1'),
  ('d8c00000-0000-0000-0000-0000000000c2', 'd8a00000-0000-0000-0000-0000000000c1'),
  ('d8c00000-0000-0000-0000-0000000000c3', 'd8a00000-0000-0000-0000-0000000000c1');

insert into public.collaborator_identifiers (collaborator_id, organization_id, business_code, valid_from) values
  ('d8c00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1', 'A-001', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000a2', 'd8a00000-0000-0000-0000-0000000000a1', 'A-002', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000a3', 'd8a00000-0000-0000-0000-0000000000a1', 'A-003', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000b1', 'd8a00000-0000-0000-0000-0000000000b1', 'B-001', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000b2', 'd8a00000-0000-0000-0000-0000000000b1', 'B-002', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000b3', 'd8a00000-0000-0000-0000-0000000000b1', 'B-003', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000c1', 'd8a00000-0000-0000-0000-0000000000c1', 'C-001', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000c2', 'd8a00000-0000-0000-0000-0000000000c1', 'C-002', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000c3', 'd8a00000-0000-0000-0000-0000000000c1', 'C-003', '2024-01-01T00:00:00Z');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('d8c00000-0000-0000-0000-0000000000a1', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000a2', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000a3', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000b1', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000b2', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000b3', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000c1', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000c2', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000c3', 'active', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Occupations (C1 -> P1, C2 -> P2) + temporary responsibility avaliativa
-- ----------------------------------------------------------------------------
insert into public.occupations (organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('d8a00000-0000-0000-0000-0000000000a1', 'd8c00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000d1', 'sintetica', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000a1', 'd8c00000-0000-0000-0000-0000000000a2', 'd8f00000-0000-0000-0000-0000000000d2', 'sintetica', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000b1', 'd8c00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000d3', 'sintetica', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000b1', 'd8c00000-0000-0000-0000-0000000000b2', 'd8f00000-0000-0000-0000-0000000000d4', 'sintetica', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000c1', 'd8c00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000d5', 'sintetica', '2024-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000c1', 'd8c00000-0000-0000-0000-0000000000c2', 'd8f00000-0000-0000-0000-0000000000d6', 'sintetica', '2024-01-01T00:00:00Z');

insert into public.temporary_responsibilities (organization_id, organizational_position_id, substitute_collaborator_id, responsibility_type, reason, valid_from, valid_to) values
  ('d8a00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000d1', 'd8c00000-0000-0000-0000-0000000000a2', 'evaluative', 'sintetica', '2024-02-01T00:00:00Z', '2024-12-31T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000d3', 'd8c00000-0000-0000-0000-0000000000b2', 'evaluative', 'sintetica', '2024-02-01T00:00:00Z', '2024-12-31T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000d5', 'd8c00000-0000-0000-0000-0000000000c2', 'evaluative', 'sintetica', '2024-02-01T00:00:00Z', '2024-12-31T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Colegiado (config por avaliado C2) + membro (C1)
-- ----------------------------------------------------------------------------
insert into public.collegiate_configurations (id, organization_id, collaborator_id, valid_from) values
  ('d8f00000-0000-0000-0000-0000000000a4', 'd8a00000-0000-0000-0000-0000000000a1', 'd8c00000-0000-0000-0000-0000000000a2', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000b4', 'd8a00000-0000-0000-0000-0000000000b1', 'd8c00000-0000-0000-0000-0000000000b2', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000c4', 'd8a00000-0000-0000-0000-0000000000c1', 'd8c00000-0000-0000-0000-0000000000c2', '2024-01-01T00:00:00Z');

insert into public.collegiate_configuration_members (organization_id, configuration_id, member_collaborator_id) values
  ('d8a00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000a4', 'd8c00000-0000-0000-0000-0000000000a1'),
  ('d8a00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000b4', 'd8c00000-0000-0000-0000-0000000000b1'),
  ('d8a00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000c4', 'd8c00000-0000-0000-0000-0000000000c1');

-- ----------------------------------------------------------------------------
-- Snapshots + snapshot_positions + snapshot_members + responsabilidades
-- (avaliado = C2; superior = P1 ocupado por C1; responsavel antigo = C3)
-- ----------------------------------------------------------------------------
insert into public.collegiate_cycle_snapshots (id, organization_id, ano, ciclo, collaborator_id, reference_date) values
  ('d8a00000-0000-0000-0000-0000000000a9', 'd8a00000-0000-0000-0000-0000000000a1', 2099, 1, 'd8c00000-0000-0000-0000-0000000000a2', '2099-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000b9', 'd8a00000-0000-0000-0000-0000000000b1', 2099, 1, 'd8c00000-0000-0000-0000-0000000000b2', '2099-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000c9', 'd8a00000-0000-0000-0000-0000000000c1', 2099, 1, 'd8c00000-0000-0000-0000-0000000000c2', '2099-01-01T00:00:00Z');

insert into public.collegiate_cycle_snapshot_positions (snapshot_id, organization_id, position_id, superior_position_id, superior_collaborator_id) values
  ('d8a00000-0000-0000-0000-0000000000a9', 'd8a00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000d2', 'd8f00000-0000-0000-0000-0000000000d1', 'd8c00000-0000-0000-0000-0000000000a1'),
  ('d8a00000-0000-0000-0000-0000000000b9', 'd8a00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000d4', 'd8f00000-0000-0000-0000-0000000000d3', 'd8c00000-0000-0000-0000-0000000000b1'),
  ('d8a00000-0000-0000-0000-0000000000c9', 'd8a00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000d6', 'd8f00000-0000-0000-0000-0000000000d5', 'd8c00000-0000-0000-0000-0000000000c1');

insert into public.collegiate_cycle_snapshot_members (snapshot_id, organization_id, member_collaborator_id) values
  ('d8a00000-0000-0000-0000-0000000000a9', 'd8a00000-0000-0000-0000-0000000000a1', 'd8c00000-0000-0000-0000-0000000000a1'),
  ('d8a00000-0000-0000-0000-0000000000b9', 'd8a00000-0000-0000-0000-0000000000b1', 'd8c00000-0000-0000-0000-0000000000b1'),
  ('d8a00000-0000-0000-0000-0000000000c9', 'd8a00000-0000-0000-0000-0000000000c1', 'd8c00000-0000-0000-0000-0000000000c1');

insert into public.cycle_evaluation_responsibilities (id, organization_id, snapshot_id, position_id, responsible_collaborator_id, valid_from) values
  ('d8a00000-0000-0000-0000-0000000000aa', 'd8a00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a9', 'd8f00000-0000-0000-0000-0000000000d2', 'd8c00000-0000-0000-0000-0000000000a3', '2099-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000bb', 'd8a00000-0000-0000-0000-0000000000b1', 'd8a00000-0000-0000-0000-0000000000b9', 'd8f00000-0000-0000-0000-0000000000d4', 'd8c00000-0000-0000-0000-0000000000b3', '2099-01-01T00:00:00Z'),
  ('d8a00000-0000-0000-0000-0000000000cc', 'd8a00000-0000-0000-0000-0000000000c1', 'd8a00000-0000-0000-0000-0000000000c9', 'd8f00000-0000-0000-0000-0000000000d6', 'd8c00000-0000-0000-0000-0000000000c3', '2099-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Tabelas de segurança (F4-01/F4-02) — fixture fechada (deve permanecer invisível)
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('d8f00000-0000-0000-0000-0000000000f1', 'gestao_f408_alfa', 'active', false, 'd8a00000-0000-0000-0000-0000000000a1'),
  ('d8f00000-0000-0000-0000-0000000000f2', 'gestao_f408_beta', 'active', false, 'd8a00000-0000-0000-0000-0000000000b1'),
  ('d8f00000-0000-0000-0000-0000000000f3', 'gestao_f408_gama', 'active', false, 'd8a00000-0000-0000-0000-0000000000c1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id::text like 'd8f00000-0000-0000-0000-0000000000f%'
   and c.code = 'collaborator.read';

-- Atribuição de role (Alfa e Beta) + link membership->collaborator + scope + target
select public.conceder_acesso_role(
  'd8d00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000f1', 'd8b00000-0000-0000-0000-0000000000a6');  -- USER_A <- gestao_f408_alfa
select public.conceder_acesso_role(
  'd8d00000-0000-0000-0000-0000000000a2', 'd8f00000-0000-0000-0000-0000000000f2', 'd8b00000-0000-0000-0000-0000000000a6');  -- USER_B <- gestao_f408_beta

insert into public.membership_collaborator_links (membership_id, organization_id, collaborator_id, status) values
  ('d8d00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1', 'd8c00000-0000-0000-0000-0000000000a1', 'active'),  -- USER_A -> C1_A
  ('d8d00000-0000-0000-0000-0000000000a2', 'd8a00000-0000-0000-0000-0000000000b1', 'd8c00000-0000-0000-0000-0000000000b1', 'active');  -- USER_B -> C1_B

insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'ORGANIZATIONAL_UNIT', 'active', 'd8b00000-0000-0000-0000-0000000000a6'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd8d00000-0000-0000-0000-0000000000a1';

insert into public.access_role_assignment_scopes (assignment_id, organization_id, scope_type, status, created_by)
select a.id, a.organization_id, 'ORGANIZATIONAL_UNIT', 'active', 'd8b00000-0000-0000-0000-0000000000a6'
  from public.membership_access_role_assignments a
 where a.membership_id = 'd8d00000-0000-0000-0000-0000000000a2';

insert into public.access_role_assignment_unit_targets (scope_id, organization_id, organizational_unit_id)
select s.id, s.organization_id, 'd8f00000-0000-0000-0000-0000000000a1'
  from public.access_role_assignment_scopes s
 where s.assignment_id = (
   select a.id from public.membership_access_role_assignments a
   where a.membership_id = 'd8d00000-0000-0000-0000-0000000000a1'
 );

insert into public.access_role_assignment_unit_targets (scope_id, organization_id, organizational_unit_id)
select s.id, s.organization_id, 'd8f00000-0000-0000-0000-0000000000b1'
  from public.access_role_assignment_scopes s
 where s.assignment_id = (
   select a.id from public.membership_access_role_assignments a
   where a.membership_id = 'd8d00000-0000-0000-0000-0000000000a2'
 );
