-- ============================================================================
-- F6-A21 P1 (Issue #327): cenário sintético das VIEWS de leitura estrutural
-- ----------------------------------------------------------------------------
-- Identidades (@example.invalid):
--   ADMIN_A     auth + perfil ATIVO + membership ativa em ALFA + role `admin`
--   CAROLINA    auth + perfil ATIVO + membership ativa em ALFA + NENHUMA role
--               (membership-only — o caso da Issue)
--   PESSOA_A    auth + perfil ATIVO + membership ativa em ALFA + NENHUMA role
--               + VÍNCULO soberano com COLAB_ATOR (projeção pessoal)
--   ADMIN_B     auth + perfil ATIVO + membership ativa em BETA + role `admin`
--
-- Estrutura (ALFA), com o subgrafo de COLAB_ATOR = {ATOR, CHEFE (acima), SUB
-- (abaixo)} e FORA deliberadamente FORA do subgrafo:
--   P_ATOR  <- COLAB_ATOR ; P_CHEFE <- COLAB_CHEFE ; P_SUB <- COLAB_SUB ; P_FORA <- COLAB_FORA
--   reporting: P_ATOR -> P_CHEFE ; P_SUB -> P_ATOR
--   colegiado de COLAB_ATOR com membro COLAB_CHEFE
-- BETA tem estrutura própria (prova de cross-tenant).
-- ============================================================================

\set ON_ERROR_STOP on

delete from public.membership_collaborator_links l
 where l.organization_id::text like 'f6a21000-%'
    or l.membership_id in (select m.id from public.user_organization_memberships m
                            where m.user_profile_id::text like 'f6a21000-%');
delete from public.collegiate_configuration_members
 where organization_id::text like 'f6a21000-%';
delete from public.collegiate_configurations where organization_id::text like 'f6a21000-%';
delete from public.position_reporting_lines where organization_id::text like 'f6a21000-%';
delete from public.occupations where organization_id::text like 'f6a21000-%';
delete from public.organizational_positions where organization_id::text like 'f6a21000-%';
delete from public.organizational_unit_parent_periods where organization_id::text like 'f6a21000-%';
delete from public.organizational_units where organization_id::text like 'f6a21000-%';
delete from public.collaborator_status_periods
 where collaborator_id in (select id from public.collaborators
                            where organization_id::text like 'f6a21000-%');
delete from public.collaborator_identifiers where organization_id::text like 'f6a21000-%';
delete from public.collaborators where organization_id::text like 'f6a21000-%';
delete from public.seniority_levels where organization_id::text like 'f6a21000-%';
delete from public.job_roles where organization_id::text like 'f6a21000-%';
delete from public.membership_access_role_assignments
 where organization_id::text like 'f6a21000-%'
    or membership_id in (select m.id from public.user_organization_memberships m
                          where m.user_profile_id::text like 'f6a21000-%');
delete from public.user_organization_memberships
 where organization_id::text like 'f6a21000-%' or user_profile_id::text like 'f6a21000-%';
delete from public.user_profiles where id::text like 'f6a21000-%';
delete from public.organizations where id::text like 'f6a21000-%';
delete from auth.users where id::text like 'f6a21000-%';

insert into public.organizations (id, name) values
  ('f6a21000-0000-4000-8000-0000000000a1', 'F6-A21 Alfa'),
  ('f6a21000-0000-4000-8000-0000000000a2', 'F6-A21 Beta');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token,
  reauthentication_token, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'f6a21000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'admin.alfa.f6a21@example.invalid',
   crypt('virtus-senha-f6a21-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a21000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'carolina.f6a21@example.invalid',
   crypt('virtus-senha-f6a21-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a21000-0000-4000-8000-000000000003',
   'authenticated', 'authenticated', 'pessoa.alfa.f6a21@example.invalid',
   crypt('virtus-senha-f6a21-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a21000-0000-4000-8000-000000000004',
   'authenticated', 'authenticated', 'admin.beta.f6a21@example.invalid',
   crypt('virtus-senha-f6a21-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.user_profiles (id, status) values
  ('f6a21000-0000-4000-8000-000000000001', 'active'),
  ('f6a21000-0000-4000-8000-000000000002', 'active'),
  ('f6a21000-0000-4000-8000-000000000003', 'active'),
  ('f6a21000-0000-4000-8000-000000000004', 'active');

insert into public.user_organization_memberships (user_profile_id, organization_id, status) values
  ('f6a21000-0000-4000-8000-000000000001', 'f6a21000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a21000-0000-4000-8000-000000000002', 'f6a21000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a21000-0000-4000-8000-000000000003', 'f6a21000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a21000-0000-4000-8000-000000000004', 'f6a21000-0000-4000-8000-0000000000a2', 'active');

-- role `admin` SOMENTE para ADMIN_A (ALFA) e ADMIN_B (BETA); CAROLINA e PESSOA_A
-- ficam sem NENHUMA atribuição (membership-only).
insert into public.membership_access_role_assignments
  (membership_id, organization_id, access_role_id, status, created_by)
select m.id, m.organization_id, r.id, 'active', m.user_profile_id
  from public.user_organization_memberships m
  join public.access_roles r
    on r.is_system = true and r.status = 'active' and r.organization_id is null and r.name = 'admin'
 where m.user_profile_id in ('f6a21000-0000-4000-8000-000000000001',
                             'f6a21000-0000-4000-8000-000000000004');

insert into public.job_roles (id, organization_id, name, code, status) values
  ('f6a21000-0000-4000-8000-000000000b01', 'f6a21000-0000-4000-8000-0000000000a1',
   'Cargo Fictício Alfa', 'F6A21A', 'active'),
  ('f6a21000-0000-4000-8000-000000000b02', 'f6a21000-0000-4000-8000-0000000000a2',
   'Cargo Fictício Beta', 'F6A21B', 'active');

insert into public.seniority_levels (id, organization_id, name, status) values
  ('f6a21000-0000-4000-8000-000000000b11', 'f6a21000-0000-4000-8000-0000000000a1',
   'Senioridade Fictícia Alfa', 'active'),
  ('f6a21000-0000-4000-8000-000000000b12', 'f6a21000-0000-4000-8000-0000000000a2',
   'Senioridade Fictícia Beta', 'active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f6a21000-0000-4000-8000-000000000c01', 'f6a21000-0000-4000-8000-0000000000a1',
   'Unidade Alfa 1', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000c02', 'f6a21000-0000-4000-8000-0000000000a1',
   'Unidade Alfa 2', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000c03', 'f6a21000-0000-4000-8000-0000000000a2',
   'Unidade Beta 1', '2026-01-01T00:00:00Z');

insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from) values
  ('f6a21000-0000-4000-8000-000000000d01', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000c01', 'f6a21000-0000-4000-8000-000000000b01',
   'f6a21000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000d02', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000c01', 'f6a21000-0000-4000-8000-000000000b01',
   'f6a21000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000d03', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000c02', 'f6a21000-0000-4000-8000-000000000b01',
   'f6a21000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000d04', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000c02', 'f6a21000-0000-4000-8000-000000000b01',
   'f6a21000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000d05', 'f6a21000-0000-4000-8000-0000000000a2',
   'f6a21000-0000-4000-8000-000000000c03', 'f6a21000-0000-4000-8000-000000000b02',
   'f6a21000-0000-4000-8000-000000000b12', '2026-01-01T00:00:00Z');

insert into public.collaborators (id, organization_id) values
  ('f6a21000-0000-4000-8000-000000000e01', 'f6a21000-0000-4000-8000-0000000000a1'),
  ('f6a21000-0000-4000-8000-000000000e02', 'f6a21000-0000-4000-8000-0000000000a1'),
  ('f6a21000-0000-4000-8000-000000000e03', 'f6a21000-0000-4000-8000-0000000000a1'),
  ('f6a21000-0000-4000-8000-000000000e04', 'f6a21000-0000-4000-8000-0000000000a1'),
  ('f6a21000-0000-4000-8000-000000000e05', 'f6a21000-0000-4000-8000-0000000000a2');

insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('f6a21000-0000-4000-8000-000000000f01', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000e01', 'f6a21000-0000-4000-8000-000000000d01',
   'ocupacao ator f6a21', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000f02', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000e02', 'f6a21000-0000-4000-8000-000000000d02',
   'ocupacao chefe f6a21', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000f03', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000e03', 'f6a21000-0000-4000-8000-000000000d03',
   'ocupacao sub f6a21', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000f04', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000e04', 'f6a21000-0000-4000-8000-000000000d04',
   'ocupacao fora f6a21', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000f05', 'f6a21000-0000-4000-8000-0000000000a2',
   'f6a21000-0000-4000-8000-000000000e05', 'f6a21000-0000-4000-8000-000000000d05',
   'ocupacao beta f6a21', '2026-01-01T00:00:00Z');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('f6a21000-0000-4000-8000-000000000101', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000d01', 'f6a21000-0000-4000-8000-000000000d02',
   'ator reporta ao chefe', '2026-01-01T00:00:00Z'),
  ('f6a21000-0000-4000-8000-000000000102', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000d03', 'f6a21000-0000-4000-8000-000000000d01',
   'sub reporta ao ator', '2026-01-01T00:00:00Z');

insert into public.collegiate_configurations
  (id, organization_id, collaborator_id, valid_from) values
  ('f6a21000-0000-4000-8000-000000000201', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000e01', '2026-01-01T00:00:00Z');

insert into public.collegiate_configuration_members
  (configuration_id, organization_id, member_collaborator_id) values
  ('f6a21000-0000-4000-8000-000000000201', 'f6a21000-0000-4000-8000-0000000000a1',
   'f6a21000-0000-4000-8000-000000000e02');

-- Vínculo soberano SOMENTE para PESSOA_A (projeção pessoal).
insert into public.membership_collaborator_links
  (membership_id, organization_id, collaborator_id, status)
select m.id, m.organization_id, 'f6a21000-0000-4000-8000-000000000e01', 'active'
  from public.user_organization_memberships m
 where m.user_profile_id = 'f6a21000-0000-4000-8000-000000000003'
   and m.organization_id = 'f6a21000-0000-4000-8000-0000000000a1';

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.user_organization_memberships
   where user_profile_id::text like 'f6a21000-%';
  if v_n <> 4 then
    raise exception '[FAIL] F6-A21 P1 cenario: memberships=% (esperado 4)', v_n;
  end if;
  -- CAROLINA nao tem NENHUMA atribuicao (membership-only puro).
  select count(*) into v_n from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
   where m.user_profile_id = 'f6a21000-0000-4000-8000-000000000002';
  if v_n <> 0 then
    raise exception '[FAIL] F6-A21 P1 cenario: CAROLINA com role (%) — deve ser membership-only', v_n;
  end if;

  -- NENHUM dos dois pode ter capability ADMINISTRATIVA: o trigger certificado
  -- da F5-11 P5.1 concede a role de DOMINIO observacoes_avaliado quando o
  -- VINCULO existe (PESSOA_A), e isso nao e autoridade administrativa.
  select count(*) into v_n
    from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
    join public.access_role_capabilities rc on rc.access_role_id = a.access_role_id
    join public.capabilities c on c.id = rc.capability_id
   where m.user_profile_id in ('f6a21000-0000-4000-8000-000000000002',
                               'f6a21000-0000-4000-8000-000000000003')
     and a.status = 'active'
     and c.code in ('org.structure.manage', 'org.catalog.manage');
  if v_n <> 0 then
    raise exception '[FAIL] F6-A21 P1 cenario: CAROLINA/PESSOA_A com capability administrativa (%)', v_n;
  end if;
  raise notice '[PASS] F6-A21 P1 cenario: 2 admins (ALFA/BETA), CAROLINA membership-only, PESSOA_A com vinculo e estrutura/subgrafo prontos';
end $$;
