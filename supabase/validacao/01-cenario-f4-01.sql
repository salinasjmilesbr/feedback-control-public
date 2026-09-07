-- ============================================================================
-- F4-01 (Issue #88): cenário sintético de validação — capabilities e
-- access_roles (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f4-01.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F4-01);
--   - perfis internos sintéticos (user_profiles) ligados a auth.users locais:
--     ADMIN_A (admin de Alfa), ADMIN_B (admin de Beta), COLLAB_USER (membro de
--     Alfa sem role de sistema), SEM_ROLE (membro de Alfa sem nenhuma
--     atribuição) e ACTOR (concedente);
--   - access_roles customizadas por organização (Alfa): `ciclos` (capability
--     cycle.manage) e `relatorios` (capability report.read) — provando role
--     agrupa capability e união de múltiplas roles;
--   - atribuições via o mecanismo server-side `conceder_acesso_role`
--     (D16 = A ajustada): ADMIN_A ← admin (sistema), ADMIN_B ← admin,
--     COLLAB_USER ← ciclos + relatorios;
--   - um job_role (`Analista`) e um colaborador sintéticos em Alfa para provar
--     independência estrutural entre cargo/collaborator e autorização.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f4-01.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo d0,
--     sem colidir com os cenários de validação anteriores e sem tocar o
--     catálogo de sistema da migration, prefixo c0).
--   - Apenas dados sintéticos; nenhum dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- Ordem respeita as FKs ON DELETE RESTRICT.
-- ----------------------------------------------------------------------------
delete from public.membership_access_role_assignments
where organization_id in (
  'd0a00000-0000-0000-0000-0000000000a1',
  'd0a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_capabilities
where access_role_id in (
  'd0c00000-0000-0000-0000-0000000000c1',
  'd0c00000-0000-0000-0000-0000000000c2'
);

delete from public.access_roles
where id in (
  'd0c00000-0000-0000-0000-0000000000c1',
  'd0c00000-0000-0000-0000-0000000000c2'
);

delete from public.user_organization_memberships
where organization_id in (
  'd0a00000-0000-0000-0000-0000000000a1',
  'd0a00000-0000-0000-0000-0000000000b1'
);

delete from public.user_profiles
where id::text like 'd0b00000-0000-0000-0000-0000000000%';

delete from auth.users
where id::text like 'd0b00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id = 'd0c00000-0000-0000-0000-0000000000e1';

delete from public.job_roles
where organization_id = 'd0a00000-0000-0000-0000-0000000000a1';

delete from public.organizations
where id in (
  'd0a00000-0000-0000-0000-0000000000a1',
  'd0a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações sintéticas (F4-01)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('d0a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F4-01 Alfa'),
  ('d0a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F4-01 Beta');

-- ----------------------------------------------------------------------------
-- Identidades de autenticação sintéticas (auth.users) + perfis internos
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d0b00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin.a.f4-01@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d0b00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin.b.f4-01@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d0b00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'colab.f4-01@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d0b00000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'semrole.f4-01@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d0b00000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'actor.f4-01@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('d0b00000-0000-0000-0000-0000000000a1', 'active'),
  ('d0b00000-0000-0000-0000-0000000000a2', 'active'),
  ('d0b00000-0000-0000-0000-0000000000a3', 'active'),
  ('d0b00000-0000-0000-0000-0000000000a4', 'active'),
  ('d0b00000-0000-0000-0000-0000000000a5', 'active');

-- ----------------------------------------------------------------------------
-- Memberships sintéticas
-- ----------------------------------------------------------------------------
insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('d0d00000-0000-0000-0000-0000000000a1', 'd0b00000-0000-0000-0000-0000000000a1',
   'd0a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d0d00000-0000-0000-0000-0000000000a2', 'd0b00000-0000-0000-0000-0000000000a2',
   'd0a00000-0000-0000-0000-0000000000b1', 'active'),
  ('d0d00000-0000-0000-0000-0000000000a3', 'd0b00000-0000-0000-0000-0000000000a3',
   'd0a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d0d00000-0000-0000-0000-0000000000a4', 'd0b00000-0000-0000-0000-0000000000a4',
   'd0a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d0d00000-0000-0000-0000-0000000000a5', 'd0b00000-0000-0000-0000-0000000000a5',
   'd0a00000-0000-0000-0000-0000000000a1', 'active');

-- ----------------------------------------------------------------------------
-- job_role e colaborador sintéticos (prova de independência estrutural)
-- ----------------------------------------------------------------------------
insert into public.job_roles (organization_id, name)
values ('d0a00000-0000-0000-0000-0000000000a1', 'Analista');

insert into public.collaborators (id, organization_id)
values ('d0c00000-0000-0000-0000-0000000000e1', 'd0a00000-0000-0000-0000-0000000000a1');

-- ----------------------------------------------------------------------------
-- Access roles customizadas por organização (Alfa)
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id)
values
  ('d0c00000-0000-0000-0000-0000000000c1', 'ciclos', 'active', false, 'd0a00000-0000-0000-0000-0000000000a1'),
  ('d0c00000-0000-0000-0000-0000000000c2', 'relatorios', 'active', false, 'd0a00000-0000-0000-0000-0000000000a1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'd0c00000-0000-0000-0000-0000000000c1'
   and c.code = 'cycle.manage';

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'd0c00000-0000-0000-0000-0000000000c2'
   and c.code = 'report.read';

-- ----------------------------------------------------------------------------
-- Atribuições via mecanismo server-side (D16): ADMIN_A/A ← admin (sistema);
-- COLLAB_USER ← ciclos + relatorios (união de múltiplas roles).
-- ----------------------------------------------------------------------------
select public.conceder_acesso_role(
  'd0d00000-0000-0000-0000-0000000000a1',
  'c0000000-0000-4000-8000-0000000000f1',
  'd0b00000-0000-0000-0000-0000000000a5'
);

select public.conceder_acesso_role(
  'd0d00000-0000-0000-0000-0000000000a2',
  'c0000000-0000-4000-8000-0000000000f1',
  'd0b00000-0000-0000-0000-0000000000a2'
);

select public.conceder_acesso_role(
  'd0d00000-0000-0000-0000-0000000000a3',
  'd0c00000-0000-0000-0000-0000000000c1',
  'd0b00000-0000-0000-0000-0000000000a1'
);

select public.conceder_acesso_role(
  'd0d00000-0000-0000-0000-0000000000a3',
  'd0c00000-0000-0000-0000-0000000000c2',
  'd0b00000-0000-0000-0000-0000000000a1'
);
