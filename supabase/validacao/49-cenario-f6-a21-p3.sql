-- ============================================================================
-- F6-A21 P3 (Issue #327): cenário sintético do FECHAMENTO da leitura estrutural
-- ----------------------------------------------------------------------------
-- IDEMPOTENTE e AUTO-CONTIDO (não depende dos cenários 47/48). Prefixo de
-- limpeza: ids que casam com `^f6a2[3-9a-f]` (o P1 usa `f6a21...` e o P2 usa
-- `f6a22...`, que NÃO casam).
--
-- Organizações: GAMA (`...00a1`) com estrutura completa e DELTA (`...00a2`) com
-- estrutura mínima (prova de cross-tenant).
--
-- Identidades (@example.invalid), todas com perfil ativo e membership ativa:
--   ADMIN_G      role de sistema `admin`  → pode_estrutura + pode_catalogo (GAMA)
--   ESTRUTURA_G  role própria GAMA só com `org.structure.manage`
--   CATALOGO_G   role própria GAMA só com `org.catalog.manage`
--   MEMBRO_G     membership-only (NENHUMA role) — o caso da Issue
--   VINCULADO_G  membership-only + VÍNCULO soberano com COLAB_ATOR
--   ADMIN_D      role de sistema `admin` (DELTA)
--   MEMBRO_D     membership-only (DELTA)
--
-- Estrutura GAMA (referência `now()` do banco):
--   U1 (raiz) / U2 (filha de U1)
--   P_ATOR(P_CHEFE) em U1 ; P_SUB em U2 ; P_ENCERRADA em U2 (ENCERRADA)
--   linhas: P_ATOR→P_CHEFE e P_SUB→P_ATOR (vigentes) ; P_ENCERRADA→P_SUB (encerrada)
--   ocupações: ATOR/CHEFE/SUB vigentes ; EXTRA encerrada em P_ENCERRADA
--   colegiado vigente de COLAB_ATOR com membro COLAB_CHEFE
--   catálogo: 2 cargos e 2 senioridades ativos
-- Subgrafo VIGENTE esperado de VINCULADO_G (COLAB_ATOR): 2 unidades, 1 período
-- pai/filho, 3 posições, 2 linhas, 3 ocupações, 1 colegiado, 1 membro,
-- 3 colaboradores, 2 cargos e 2 senioridades — o histórico encerrado fica FORA.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Limpeza idempotente (filhos antes dos pais)
-- ----------------------------------------------------------------------------
delete from public.membership_collaborator_links where id::text ~ '^f6a2[3-9a-f]'
   or membership_id in (select m.id from public.user_organization_memberships m
                         where m.user_profile_id::text ~ '^f6a2[3-9a-f]');
delete from public.collegiate_configuration_members where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.collegiate_configurations where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.position_reporting_lines where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.occupations where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.organizational_positions where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.organizational_unit_parent_periods where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.organizational_units where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.collaborator_status_periods
 where collaborator_id in (select id from public.collaborators
                            where organization_id::text ~ '^f6a2[3-9a-f]');
delete from public.collaborator_identifiers where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.collaborators where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.seniority_levels where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.job_roles where organization_id::text ~ '^f6a2[3-9a-f]';
delete from public.access_role_assignment_scopes where organization_id::text ~ '^f6a2[3-9a-f]'
   or assignment_id in (select a.id from public.membership_access_role_assignments a
                         where a.id::text ~ '^f6a2[3-9a-f]');
delete from public.membership_access_role_assignments where organization_id::text ~ '^f6a2[3-9a-f]'
   or membership_id in (select m.id from public.user_organization_memberships m
                         where m.user_profile_id::text ~ '^f6a2[3-9a-f]');
delete from public.access_role_capabilities where access_role_id::text ~ '^f6a2[3-9a-f]';
delete from public.access_roles where id::text ~ '^f6a2[3-9a-f]';
delete from public.user_organization_memberships where organization_id::text ~ '^f6a2[3-9a-f]'
   or user_profile_id::text ~ '^f6a2[3-9a-f]';
delete from public.user_profiles where id::text ~ '^f6a2[3-9a-f]';
delete from public.organizations where id::text ~ '^f6a2[3-9a-f]';
delete from auth.users where id::text ~ '^f6a2[3-9a-f]';

-- ----------------------------------------------------------------------------
-- 1) Organizações e identidades
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f6a23000-0000-4000-8000-0000000000a1', 'F6-A21 P3 Gama'),
  ('f6a23000-0000-4000-8000-0000000000a2', 'F6-A21 P3 Delta');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token,
  reauthentication_token, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'f6a23000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'admin.gama.f6a21p3@example.invalid',
   crypt('virtus-senha-f6a21p3-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a23000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'estrutura.gama.f6a21p3@example.invalid',
   crypt('virtus-senha-f6a21p3-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a23000-0000-4000-8000-000000000003',
   'authenticated', 'authenticated', 'catalogo.gama.f6a21p3@example.invalid',
   crypt('virtus-senha-f6a21p3-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a23000-0000-4000-8000-000000000004',
   'authenticated', 'authenticated', 'membro.gama.f6a21p3@example.invalid',
   crypt('virtus-senha-f6a21p3-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a23000-0000-4000-8000-000000000005',
   'authenticated', 'authenticated', 'vinculado.gama.f6a21p3@example.invalid',
   crypt('virtus-senha-f6a21p3-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a23000-0000-4000-8000-000000000006',
   'authenticated', 'authenticated', 'admin.delta.f6a21p3@example.invalid',
   crypt('virtus-senha-f6a21p3-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a23000-0000-4000-8000-000000000007',
   'authenticated', 'authenticated', 'membro.delta.f6a21p3@example.invalid',
   crypt('virtus-senha-f6a21p3-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.user_profiles (id, status) values
  ('f6a23000-0000-4000-8000-000000000001', 'active'),
  ('f6a23000-0000-4000-8000-000000000002', 'active'),
  ('f6a23000-0000-4000-8000-000000000003', 'active'),
  ('f6a23000-0000-4000-8000-000000000004', 'active'),
  ('f6a23000-0000-4000-8000-000000000005', 'active'),
  ('f6a23000-0000-4000-8000-000000000006', 'active'),
  ('f6a23000-0000-4000-8000-000000000007', 'active');

insert into public.user_organization_memberships (id, user_profile_id, organization_id, status) values
  ('f6a2d000-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a2d000-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a2d000-0000-4000-8000-000000000003', 'f6a23000-0000-4000-8000-000000000003', 'f6a23000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a2d000-0000-4000-8000-000000000004', 'f6a23000-0000-4000-8000-000000000004', 'f6a23000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a2d000-0000-4000-8000-000000000005', 'f6a23000-0000-4000-8000-000000000005', 'f6a23000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a2d000-0000-4000-8000-000000000006', 'f6a23000-0000-4000-8000-000000000006', 'f6a23000-0000-4000-8000-0000000000a2', 'active'),
  ('f6a2d000-0000-4000-8000-000000000007', 'f6a23000-0000-4000-8000-000000000007', 'f6a23000-0000-4000-8000-0000000000a2', 'active');

-- ----------------------------------------------------------------------------
-- 2) Autorização: role de sistema `admin` para os dois admins e duas roles
--    PRÓPRIAS de GAMA (uma por capability) para separar estrutura de catálogo.
--    NENHUMA capability/role nova do produto: as roles próprias apenas
--    ATRIBUEM capabilities já existentes (grantable_via_role = true).
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('f6a2e000-0000-4000-8000-000000000001', 'P3 Somente Estrutura', 'active', false,
   'f6a23000-0000-4000-8000-0000000000a1'),
  ('f6a2e000-0000-4000-8000-000000000002', 'P3 Somente Catalogo', 'active', false,
   'f6a23000-0000-4000-8000-0000000000a1');

insert into public.access_role_capabilities (id, access_role_id, capability_id)
select 'f6a2e100-0000-4000-8000-000000000001', 'f6a2e000-0000-4000-8000-000000000001', c.id
  from public.capabilities c where c.code = 'org.structure.manage';

insert into public.access_role_capabilities (id, access_role_id, capability_id)
select 'f6a2e100-0000-4000-8000-000000000002', 'f6a2e000-0000-4000-8000-000000000002', c.id
  from public.capabilities c where c.code = 'org.catalog.manage';

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f6a2a000-0000-4000-8000-000000000001', 'f6a2d000-0000-4000-8000-000000000001',
   'f6a23000-0000-4000-8000-0000000000a1', 'c0000000-0000-4000-8000-0000000000f1',
   'active', 'f6a23000-0000-4000-8000-000000000001'),
  ('f6a2a000-0000-4000-8000-000000000002', 'f6a2d000-0000-4000-8000-000000000002',
   'f6a23000-0000-4000-8000-0000000000a1', 'f6a2e000-0000-4000-8000-000000000001',
   'active', 'f6a23000-0000-4000-8000-000000000001'),
  ('f6a2a000-0000-4000-8000-000000000003', 'f6a2d000-0000-4000-8000-000000000003',
   'f6a23000-0000-4000-8000-0000000000a1', 'f6a2e000-0000-4000-8000-000000000002',
   'active', 'f6a23000-0000-4000-8000-000000000001'),
  ('f6a2a000-0000-4000-8000-000000000004', 'f6a2d000-0000-4000-8000-000000000006',
   'f6a23000-0000-4000-8000-0000000000a2', 'c0000000-0000-4000-8000-0000000000f1',
   'active', 'f6a23000-0000-4000-8000-000000000006');

insert into public.access_role_assignment_scopes
  (id, assignment_id, organization_id, scope_type, status, created_by) values
  ('f6a2a100-0000-4000-8000-000000000001', 'f6a2a000-0000-4000-8000-000000000001',
   'f6a23000-0000-4000-8000-0000000000a1', 'ORGANIZATION', 'active', 'f6a23000-0000-4000-8000-000000000001'),
  ('f6a2a100-0000-4000-8000-000000000002', 'f6a2a000-0000-4000-8000-000000000002',
   'f6a23000-0000-4000-8000-0000000000a1', 'ORGANIZATION', 'active', 'f6a23000-0000-4000-8000-000000000001'),
  ('f6a2a100-0000-4000-8000-000000000003', 'f6a2a000-0000-4000-8000-000000000003',
   'f6a23000-0000-4000-8000-0000000000a1', 'ORGANIZATION', 'active', 'f6a23000-0000-4000-8000-000000000001'),
  ('f6a2a100-0000-4000-8000-000000000004', 'f6a2a000-0000-4000-8000-000000000004',
   'f6a23000-0000-4000-8000-0000000000a2', 'ORGANIZATION', 'active', 'f6a23000-0000-4000-8000-000000000006');

-- ----------------------------------------------------------------------------
-- 3) Estrutura GAMA (com histórico ENCERRADO de propósito)
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('f6a2b000-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'Cargo Fictício P3 A', 'F6A21P3A', 'active'),
  ('f6a2b000-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a1',
   'Cargo Fictício P3 B', 'F6A21P3B', 'active');

insert into public.seniority_levels (id, organization_id, name, status) values
  ('f6a2b100-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'Senioridade Fictícia P3 A', 'active'),
  ('f6a2b100-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a1',
   'Senioridade Fictícia P3 B', 'active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f6a2c000-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'P3 Unidade Raiz', '2025-01-01T00:00:00Z'),
  ('f6a2c000-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a1',
   'P3 Unidade Filha', '2025-01-01T00:00:00Z');

insert into public.organizational_unit_parent_periods
  (id, organization_id, unit_id, parent_unit_id, valid_from) values
  ('f6a2c100-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2c000-0000-4000-8000-000000000002', 'f6a2c000-0000-4000-8000-000000000001',
   '2025-01-01T00:00:00Z');

insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to, name
) values ('f6a2d100-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2c000-0000-4000-8000-000000000001', 'f6a2b000-0000-4000-8000-000000000001',
   'f6a2b100-0000-4000-8000-000000000001', '2025-01-01T00:00:00Z', null, 'F6 P4.5 49-cenario-f6-a21-p3 posição funcional'),
  ('f6a2d100-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2c000-0000-4000-8000-000000000001', 'f6a2b000-0000-4000-8000-000000000001',
   'f6a2b100-0000-4000-8000-000000000001', '2025-01-01T00:00:00Z', null, 'F6 P4.5 49-cenario-f6-a21-p3 posição funcional'),
  ('f6a2d100-0000-4000-8000-000000000003', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2c000-0000-4000-8000-000000000002', 'f6a2b000-0000-4000-8000-000000000002',
   'f6a2b100-0000-4000-8000-000000000002', '2025-01-01T00:00:00Z', null, 'F6 P4.5 49-cenario-f6-a21-p3 posição funcional'),
  ('f6a2d100-0000-4000-8000-000000000004', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2c000-0000-4000-8000-000000000002', 'f6a2b000-0000-4000-8000-000000000002',
   'f6a2b100-0000-4000-8000-000000000002', '2025-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 'F6 P4.5 49-cenario-f6-a21-p3 posição funcional');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to) values
  ('f6a2d200-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2d100-0000-4000-8000-000000000001', 'f6a2d100-0000-4000-8000-000000000002',
   'ator reporta ao chefe (p3)', '2025-01-01T00:00:00Z', null),
  ('f6a2d200-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2d100-0000-4000-8000-000000000003', 'f6a2d100-0000-4000-8000-000000000001',
   'sub reporta ao ator (p3)', '2025-01-01T00:00:00Z', null),
  ('f6a2d200-0000-4000-8000-000000000003', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2d100-0000-4000-8000-000000000004', 'f6a2d100-0000-4000-8000-000000000003',
   'historico encerrado (p3)', '2025-01-01T00:00:00Z', '2026-01-01T00:00:00Z');

insert into public.collaborators (id, organization_id, full_name) values
  ('f6a2e200-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1', 'Pessoa Fictícia P3 Ator'),
  ('f6a2e200-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a1', 'Pessoa Fictícia P3 Chefe'),
  ('f6a2e200-0000-4000-8000-000000000003', 'f6a23000-0000-4000-8000-0000000000a1', 'Pessoa Fictícia P3 Sub'),
  ('f6a2e200-0000-4000-8000-000000000004', 'f6a23000-0000-4000-8000-0000000000a1', 'Pessoa Fictícia P3 Extra'),
  ('f6a24000-0000-4000-8000-000000000005', 'f6a23000-0000-4000-8000-0000000000a2', 'Pessoa Fictícia P3 Delta');

insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to) values
  ('f6a2e300-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2e200-0000-4000-8000-000000000001', 'f6a2d100-0000-4000-8000-000000000001',
   'ocupacao ator (p3)', '2025-01-01T00:00:00Z', null),
  ('f6a2e300-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2e200-0000-4000-8000-000000000002', 'f6a2d100-0000-4000-8000-000000000002',
   'ocupacao chefe (p3)', '2025-01-01T00:00:00Z', null),
  ('f6a2e300-0000-4000-8000-000000000003', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2e200-0000-4000-8000-000000000003', 'f6a2d100-0000-4000-8000-000000000003',
   'ocupacao sub (p3)', '2025-01-01T00:00:00Z', null),
  ('f6a2e300-0000-4000-8000-000000000004', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2e200-0000-4000-8000-000000000004', 'f6a2d100-0000-4000-8000-000000000004',
   'ocupacao encerrada (p3)', '2025-01-01T00:00:00Z', '2026-01-01T00:00:00Z');

insert into public.collegiate_configurations
  (id, organization_id, collaborator_id, valid_from) values
  ('f6a2f000-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2e200-0000-4000-8000-000000000001', '2026-01-01T00:00:00Z');

insert into public.collegiate_configuration_members
  (configuration_id, organization_id, member_collaborator_id) values
  ('f6a2f000-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a1',
   'f6a2e200-0000-4000-8000-000000000002');

-- Dado REAL na tabela fechada por consequência: prova não-vacuosa do corte.
insert into public.collaborator_status_periods (id, collaborator_id, status, valid_from) values
  ('f6a2f100-0000-4000-8000-000000000001', 'f6a2e200-0000-4000-8000-000000000001',
   'active', '2025-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 4) Estrutura DELTA (mínima, para cross-tenant) + vínculo do VINCULADO_G
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('f6a24000-0000-4000-8000-000000000002', 'f6a23000-0000-4000-8000-0000000000a2',
   'Cargo Fictício P3 Delta', 'F6A21P3D', 'active');

insert into public.seniority_levels (id, organization_id, name, status) values
  ('f6a24000-0000-4000-8000-000000000003', 'f6a23000-0000-4000-8000-0000000000a2',
   'Senioridade Fictícia P3 Delta', 'active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f6a24000-0000-4000-8000-000000000001', 'f6a23000-0000-4000-8000-0000000000a2',
   'P3 Unidade Delta', '2025-01-01T00:00:00Z');

insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, name
) values ('f6a24000-0000-4000-8000-000000000004', 'f6a23000-0000-4000-8000-0000000000a2',
   'f6a24000-0000-4000-8000-000000000001', 'f6a24000-0000-4000-8000-000000000002',
   'f6a24000-0000-4000-8000-000000000003', '2025-01-01T00:00:00Z', 'F6 P4.5 49-cenario-f6-a21-p3 posição funcional');

insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('f6a24000-0000-4000-8000-000000000006', 'f6a23000-0000-4000-8000-0000000000a2',
   'f6a24000-0000-4000-8000-000000000005', 'f6a24000-0000-4000-8000-000000000004',
   'ocupacao delta (p3)', '2025-01-01T00:00:00Z');

insert into public.membership_collaborator_links
  (membership_id, organization_id, collaborator_id, status)
values ('f6a2d000-0000-4000-8000-000000000005', 'f6a23000-0000-4000-8000-0000000000a1',
        'f6a2e200-0000-4000-8000-000000000001', 'active');

-- ----------------------------------------------------------------------------
-- 5) Sanidade do cenário (fixture não-vacuosa e sem autoridade acidental)
-- ----------------------------------------------------------------------------
do $$
declare
  v_n integer;
begin
  select count(*) into v_n from public.user_organization_memberships
   where user_profile_id::text ~ '^f6a2[3-9a-f]';
  if v_n <> 7 then
    raise exception '[FAIL] F6-A21 P3 cenario: memberships=% (esperado 7)', v_n;
  end if;

  -- MEMBRO_G e MEMBRO_D sao membership-only PUROS (nenhuma atribuicao).
  select count(*) into v_n
    from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
   where m.user_profile_id in ('f6a23000-0000-4000-8000-000000000004',
                               'f6a23000-0000-4000-8000-000000000007');
  if v_n <> 0 then
    raise exception '[FAIL] F6-A21 P3 cenario: membership-only com role (%)', v_n;
  end if;

  -- VINCULADO_G: o VINCULO pode conceder role de DOMINIO pelo trigger da F5-11
  -- P5.1 — o que NAO pode existir e autoridade administrativa.
  select count(*) into v_n
    from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
    join public.access_role_capabilities rc on rc.access_role_id = a.access_role_id
    join public.capabilities c on c.id = rc.capability_id
   where m.user_profile_id = 'f6a23000-0000-4000-8000-000000000005'
     and a.status = 'active'
     and c.code in ('org.structure.manage','org.catalog.manage');
  if v_n <> 0 then
    raise exception '[FAIL] F6-A21 P3 cenario: VINCULADO_G com capability administrativa (%)', v_n;
  end if;

  -- Separacao EXATA das capabilities administrativas por ator.
  select count(*) into v_n
    from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
    join public.access_role_capabilities rc on rc.access_role_id = a.access_role_id
    join public.capabilities c on c.id = rc.capability_id
   where m.user_profile_id = 'f6a23000-0000-4000-8000-000000000002'
     and a.status = 'active' and c.code = 'org.structure.manage';
  if v_n <> 1 then
    raise exception '[FAIL] F6-A21 P3 cenario: ESTRUTURA_G sem org.structure.manage (%)', v_n;
  end if;
  select count(*) into v_n
    from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
    join public.access_role_capabilities rc on rc.access_role_id = a.access_role_id
    join public.capabilities c on c.id = rc.capability_id
   where m.user_profile_id = 'f6a23000-0000-4000-8000-000000000002'
     and a.status = 'active' and c.code <> 'org.structure.manage';
  if v_n <> 0 then
    raise exception '[FAIL] F6-A21 P3 cenario: ESTRUTURA_G com capability extra (%)', v_n;
  end if;
  select count(*) into v_n
    from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
    join public.access_role_capabilities rc on rc.access_role_id = a.access_role_id
    join public.capabilities c on c.id = rc.capability_id
   where m.user_profile_id = 'f6a23000-0000-4000-8000-000000000003'
     and a.status = 'active' and c.code = 'org.catalog.manage';
  if v_n <> 1 then
    raise exception '[FAIL] F6-A21 P3 cenario: CATALOGO_G sem org.catalog.manage (%)', v_n;
  end if;
  select count(*) into v_n
    from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
    join public.access_role_capabilities rc on rc.access_role_id = a.access_role_id
    join public.capabilities c on c.id = rc.capability_id
   where m.user_profile_id = 'f6a23000-0000-4000-8000-000000000003'
     and a.status = 'active' and c.code <> 'org.catalog.manage';
  if v_n <> 0 then
    raise exception '[FAIL] F6-A21 P3 cenario: CATALOGO_G com capability extra (%)', v_n;
  end if;

  -- Historico encerrado presente (prova nao-vacuosa da vigencia preservada).
  select count(*) into v_n from public.organizational_positions
   where id = 'f6a2d100-0000-4000-8000-000000000004' and valid_to is not null;
  if v_n <> 1 then
    raise exception '[FAIL] F6-A21 P3 cenario: posicao encerrada ausente';
  end if;

  raise notice '[PASS] F6-A21 P3 cenario: GAMA (admin, estrutura-only, catalogo-only, membership-only, vinculado) + DELTA (admin, membership-only) prontos';
end $$;
