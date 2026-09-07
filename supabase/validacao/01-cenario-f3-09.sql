-- ============================================================================
-- F3-09 (Issue #86): cenário sintético de validação — responsabilidade
-- avaliativa e sucessão de avaliador (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-09.sql:
--
--   - organização Alfa com catálogo, unidade, colaboradores, posições,
--     reporting lines, occupations e uma temporary responsibility avaliativa;
--   - organização Beta mínima (colaborador + posição) para testes
--     cross-organization;
--   - um autor sintético (auth.users + user_profiles) para o evento de sucessão
--     (D7: author_user_profile_id);
--   - colaboradores: C_GER (titular), C_GER2 (sucessor), C_SUB (substituto
--     avaliativo), A1/A2 (avaliados com superior), A3 (raiz/sem superior) e A4
--     (duas posições ocupadas).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-09.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo fb).
--   - Apenas dados sintéticos; nenhum nome/estrutura/dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.evaluation_succession_events
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.cycle_evaluation_responsibilities
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_members
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_positions
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshots
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configuration_members
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configurations
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.temporary_responsibilities
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.occupations
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
where collaborator_id::text like 'fbb00000-0000-0000-0000-0000000000%';

delete from public.position_reporting_lines
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.organizational_positions
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.organizational_units
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id::text like 'fbb00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.organizations
where id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.user_profiles
where id = 'fbf00000-0000-0000-0000-000000000001';

delete from auth.users
where id = 'fbf00000-0000-0000-0000-000000000001';

-- ----------------------------------------------------------------------------
-- Organizações, catálogo, unidade e posições
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('fba00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-09 Alfa'),
  ('fba00000-0000-0000-0000-0000000000b1', 'Org Sintetica F3-09 Beta');

insert into public.job_roles (id, organization_id, name) values
  ('fbd00000-0000-0000-0000-000000000001', 'fba00000-0000-0000-0000-0000000000a1', 'Gerente'),
  ('fbd00000-0000-0000-0000-000000000002', 'fba00000-0000-0000-0000-0000000000a1', 'Analista'),
  ('fbd00000-0000-0000-0000-000000000011', 'fba00000-0000-0000-0000-0000000000b1', 'Analista');

insert into public.organizational_units (id, organization_id, name, valid_from, valid_to) values
  ('fbe00000-0000-0000-0000-000000000001', 'fba00000-0000-0000-0000-0000000000a1',
   'Unidade F3-09', '2025-01-01T00:00:00Z', null),
  ('fbe00000-0000-0000-0000-000000000002', 'fba00000-0000-0000-0000-0000000000b1',
   'Unidade F3-09 Beta', '2025-01-01T00:00:00Z', null);

insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('fbc00000-0000-0000-0000-0000000000a1', 'fba00000-0000-0000-0000-0000000000a1',
   'fbe00000-0000-0000-0000-000000000001', 'fbd00000-0000-0000-0000-000000000001', null,
   '2025-01-01T00:00:00Z', null),  -- P_GER
  ('fbc00000-0000-0000-0000-0000000000a2', 'fba00000-0000-0000-0000-0000000000a1',
   'fbe00000-0000-0000-0000-000000000001', 'fbd00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),  -- P_A1
  ('fbc00000-0000-0000-0000-0000000000a3', 'fba00000-0000-0000-0000-0000000000a1',
   'fbe00000-0000-0000-0000-000000000001', 'fbd00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),  -- P_A2
  ('fbc00000-0000-0000-0000-0000000000a4', 'fba00000-0000-0000-0000-0000000000a1',
   'fbe00000-0000-0000-0000-000000000001', 'fbd00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),  -- P_A3 (raiz)
  ('fbc00000-0000-0000-0000-0000000000a5', 'fba00000-0000-0000-0000-0000000000a1',
   'fbe00000-0000-0000-0000-000000000001', 'fbd00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),  -- P_A4
  ('fbc00000-0000-0000-0000-0000000000a6', 'fba00000-0000-0000-0000-0000000000a1',
   'fbe00000-0000-0000-0000-000000000001', 'fbd00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),  -- P_A5
  ('fbc00000-0000-0000-0000-0000000000a9', 'fba00000-0000-0000-0000-0000000000b1',
   'fbe00000-0000-0000-0000-000000000002', 'fbd00000-0000-0000-0000-000000000011', null,
   '2025-01-01T00:00:00Z', null);  -- P_BETA

-- ----------------------------------------------------------------------------
-- Colaboradores e status
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('fbb00000-0000-0000-0000-0000000000c1', 'fba00000-0000-0000-0000-0000000000a1'), -- C_GER
  ('fbb00000-0000-0000-0000-0000000000c2', 'fba00000-0000-0000-0000-0000000000a1'), -- C_GER2
  ('fbb00000-0000-0000-0000-0000000000c3', 'fba00000-0000-0000-0000-0000000000a1'), -- C_SUB
  ('fbb00000-0000-0000-0000-0000000000c4', 'fba00000-0000-0000-0000-0000000000a1'), -- A1
  ('fbb00000-0000-0000-0000-0000000000c5', 'fba00000-0000-0000-0000-0000000000a1'), -- A2
  ('fbb00000-0000-0000-0000-0000000000c6', 'fba00000-0000-0000-0000-0000000000a1'), -- A3
  ('fbb00000-0000-0000-0000-0000000000c7', 'fba00000-0000-0000-0000-0000000000a1'), -- A4
  ('fbb00000-0000-0000-0000-0000000000d1', 'fba00000-0000-0000-0000-0000000000b1'); -- CBeta

insert into public.collaborator_status_periods (collaborator_id, status, valid_from, valid_to) values
  ('fbb00000-0000-0000-0000-0000000000c1', 'active', '2025-01-01T00:00:00Z', null),
  ('fbb00000-0000-0000-0000-0000000000c2', 'active', '2025-01-01T00:00:00Z', null),
  ('fbb00000-0000-0000-0000-0000000000c3', 'active', '2025-01-01T00:00:00Z', null),
  ('fbb00000-0000-0000-0000-0000000000c4', 'active', '2025-01-01T00:00:00Z', null),
  ('fbb00000-0000-0000-0000-0000000000c5', 'active', '2025-01-01T00:00:00Z', null),
  ('fbb00000-0000-0000-0000-0000000000c6', 'active', '2025-01-01T00:00:00Z', null),
  ('fbb00000-0000-0000-0000-0000000000c7', 'active', '2025-01-01T00:00:00Z', null),
  ('fbb00000-0000-0000-0000-0000000000d1', 'active', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Reporting lines (P_GER é o topo; P_A3 é raiz/sem superior)
-- ----------------------------------------------------------------------------
insert into public.position_reporting_lines (
  organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
) values
  ('fba00000-0000-0000-0000-0000000000a1', 'fbc00000-0000-0000-0000-0000000000a2',
   'fbc00000-0000-0000-0000-0000000000a1', 'A1 sob Gerente', '2025-01-01T00:00:00Z', null),
  ('fba00000-0000-0000-0000-0000000000a1', 'fbc00000-0000-0000-0000-0000000000a3',
   'fbc00000-0000-0000-0000-0000000000a1', 'A2 sob Gerente', '2025-01-01T00:00:00Z', null),
  ('fba00000-0000-0000-0000-0000000000a1', 'fbc00000-0000-0000-0000-0000000000a5',
   'fbc00000-0000-0000-0000-0000000000a1', 'A4-P_A4 sob Gerente', '2025-01-01T00:00:00Z', null),
  ('fba00000-0000-0000-0000-0000000000a1', 'fbc00000-0000-0000-0000-0000000000a6',
   'fbc00000-0000-0000-0000-0000000000a1', 'A4-P_A5 sob Gerente', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Occupations (titulares)
-- ----------------------------------------------------------------------------
insert into public.occupations (
  organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
) values
  ('fba00000-0000-0000-0000-0000000000a1', 'fbb00000-0000-0000-0000-0000000000c1',
   'fbc00000-0000-0000-0000-0000000000a1', 'Gerente titular', '2025-01-01T00:00:00Z', null),
  ('fba00000-0000-0000-0000-0000000000a1', 'fbb00000-0000-0000-0000-0000000000c4',
   'fbc00000-0000-0000-0000-0000000000a2', 'A1 ocupado', '2025-01-01T00:00:00Z', null),
  ('fba00000-0000-0000-0000-0000000000a1', 'fbb00000-0000-0000-0000-0000000000c5',
   'fbc00000-0000-0000-0000-0000000000a3', 'A2 ocupado', '2025-01-01T00:00:00Z', null),
  ('fba00000-0000-0000-0000-0000000000a1', 'fbb00000-0000-0000-0000-0000000000c6',
   'fbc00000-0000-0000-0000-0000000000a4', 'A3 ocupado (raiz)', '2025-01-01T00:00:00Z', null),
  ('fba00000-0000-0000-0000-0000000000a1', 'fbb00000-0000-0000-0000-0000000000c7',
   'fbc00000-0000-0000-0000-0000000000a5', 'A4 ocupado P_A4', '2025-01-01T00:00:00Z', null),
  ('fba00000-0000-0000-0000-0000000000a1', 'fbb00000-0000-0000-0000-0000000000c7',
   'fbc00000-0000-0000-0000-0000000000a6', 'A4 ocupado P_A5', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Temporary responsibility avaliativa (substituto avalia no período)
-- ----------------------------------------------------------------------------
insert into public.temporary_responsibilities (
  organization_id, organizational_position_id, substitute_collaborator_id,
  responsibility_type, reason, valid_from, valid_to
) values (
  'fba00000-0000-0000-0000-0000000000a1',
  'fbc00000-0000-0000-0000-0000000000a1',
  'fbb00000-0000-0000-0000-0000000000c3',
  'evaluative',
  'Substituto avaliativo no periodo', '2025-02-01T00:00:00Z', '2025-05-01T00:00:00Z'
);

-- ----------------------------------------------------------------------------
-- Autor sintético do evento de sucessão (auth.users + user_profiles — D7)
-- ----------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token,
  reauthentication_token, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  'fbf00000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'autor.f3-09@example.invalid',
  crypt('virtus-senha-f3-09-local', gen_salt('bf')), now(),
  '', '', '', '', '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.user_profiles (id, status) values
  ('fbf00000-0000-0000-0000-000000000001', 'active');
