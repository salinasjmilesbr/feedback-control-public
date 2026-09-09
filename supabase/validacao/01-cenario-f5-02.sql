-- ============================================================================
-- F5-02 (vínculo usuário autenticado ↔ colaborador): cenário sintético
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Prepara, de forma determinística e idempotente, o cenário usado pela
-- validação 02-validar-f5-02.sql:
--   - duas organizações sintéticas (Alfa e Beta F5-02);
--   - identidades/perfis/memberships sintéticas com e sem vínculo;
--   - vínculos ativos, profile desabilitado, membership desabilitada,
--     colaboradores em leave/inactive (âncora de identidade — Q5) e
--     colaboradores não vinculados (troca Q6 / Q3).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql); nunca em remoto;
--   - insere via superuser local (equivalente a service_role) SEM alterar
--     policies;
--   - reexecutável: remove/recria somente os UUIDs fixos (prefixo d2);
--   - apenas dados sintéticos; nenhum dado real.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Limpeza do cenário anterior (ordem respeita FKs ON DELETE RESTRICT)
-- ----------------------------------------------------------------------------
delete from public.membership_collaborator_links
 where organization_id in (
   'd2a00000-0000-0000-0000-0000000000a1',
   'd2a00000-0000-0000-0000-0000000000b1'
 );

delete from public.user_organization_memberships
 where organization_id in (
   'd2a00000-0000-0000-0000-0000000000a1',
   'd2a00000-0000-0000-0000-0000000000b1'
 );

delete from public.user_profiles
 where id::text like 'd2b00000-0000-0000-0000-0000000000%';

delete from auth.users
 where id::text like 'd2b00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
 where collaborator_id::text like 'd2c00000-0000-0000-0000-0000000000%';

delete from public.collaborators
 where id::text like 'd2c00000-0000-0000-0000-0000000000%';

delete from public.organizations
 where id in (
   'd2a00000-0000-0000-0000-0000000000a1',
   'd2a00000-0000-0000-0000-0000000000b1'
 );

-- ----------------------------------------------------------------------------
-- Organizações sintéticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('d2a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-02 Alfa'),
  ('d2a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-02 Beta');

-- ----------------------------------------------------------------------------
-- Identidades + perfis (sintéticos)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d2b00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ua.f5-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d2b00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ub.f5-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d2b00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'udp.f5-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d2b00000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'udm.f5-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d2b00000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'unl.f5-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d2b00000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'uleave.f5-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d2b00000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'uinactive.f5-02@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('d2b00000-0000-0000-0000-0000000000a1', 'active'),
  ('d2b00000-0000-0000-0000-0000000000a2', 'active'),
  ('d2b00000-0000-0000-0000-0000000000a3', 'disabled'),
  ('d2b00000-0000-0000-0000-0000000000a4', 'active'),
  ('d2b00000-0000-0000-0000-0000000000a5', 'active'),
  ('d2b00000-0000-0000-0000-0000000000a6', 'active'),
  ('d2b00000-0000-0000-0000-0000000000a7', 'active');

-- ----------------------------------------------------------------------------
-- Memberships (sintéticas)
-- ----------------------------------------------------------------------------
insert into public.user_organization_memberships (id, user_profile_id, organization_id, status) values
  ('d2d00000-0000-0000-0000-000000000001', 'd2b00000-0000-0000-0000-0000000000a1', 'd2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d2d00000-0000-0000-0000-000000000002', 'd2b00000-0000-0000-0000-0000000000a2', 'd2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d2d00000-0000-0000-0000-000000000003', 'd2b00000-0000-0000-0000-0000000000a3', 'd2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d2d00000-0000-0000-0000-000000000004', 'd2b00000-0000-0000-0000-0000000000a4', 'd2a00000-0000-0000-0000-0000000000a1', 'disabled'),
  ('d2d00000-0000-0000-0000-000000000005', 'd2b00000-0000-0000-0000-0000000000a5', 'd2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d2d00000-0000-0000-0000-000000000006', 'd2b00000-0000-0000-0000-0000000000a6', 'd2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d2d00000-0000-0000-0000-000000000007', 'd2b00000-0000-0000-0000-0000000000a7', 'd2a00000-0000-0000-0000-0000000000a1', 'active');

-- ----------------------------------------------------------------------------
-- Colaboradores (sintéticos) + períodos de status (lifecycle F3-01)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('d2c00000-0000-0000-0000-0000000000c1', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000c2', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000c3', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000c4', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000c5', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000c6', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000c7', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000c8', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000c9', 'd2a00000-0000-0000-0000-0000000000a1'),
  ('d2c00000-0000-0000-0000-0000000000b1', 'd2a00000-0000-0000-0000-0000000000b1');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('d2c00000-0000-0000-0000-0000000000c1', 'active',  now() - interval '30 days'),
  ('d2c00000-0000-0000-0000-0000000000c2', 'active',  now() - interval '30 days'),
  ('d2c00000-0000-0000-0000-0000000000c3', 'active',  now() - interval '30 days'),
  ('d2c00000-0000-0000-0000-0000000000c4', 'active',  now() - interval '30 days'),
  ('d2c00000-0000-0000-0000-0000000000c5', 'leave',   now() - interval '10 days'),
  ('d2c00000-0000-0000-0000-0000000000c6', 'inactive', now() - interval '10 days'),
  ('d2c00000-0000-0000-0000-0000000000c7', 'active',  now() - interval '30 days'),
  ('d2c00000-0000-0000-0000-0000000000c8', 'active',  now() - interval '30 days'),
  ('d2c00000-0000-0000-0000-0000000000c9', 'active',  now() - interval '30 days'),
  ('d2c00000-0000-0000-0000-0000000000b1', 'active',  now() - interval '30 days');

-- ----------------------------------------------------------------------------
-- Vínculos (sintéticos) — ativos; M_NL (m5) permanece SEM vínculo
-- ----------------------------------------------------------------------------
insert into public.membership_collaborator_links (membership_id, organization_id, collaborator_id, status) values
  ('d2d00000-0000-0000-0000-000000000001', 'd2a00000-0000-0000-0000-0000000000a1', 'd2c00000-0000-0000-0000-0000000000c1', 'active'),
  ('d2d00000-0000-0000-0000-000000000002', 'd2a00000-0000-0000-0000-0000000000a1', 'd2c00000-0000-0000-0000-0000000000c2', 'active'),
  ('d2d00000-0000-0000-0000-000000000003', 'd2a00000-0000-0000-0000-0000000000a1', 'd2c00000-0000-0000-0000-0000000000c3', 'active'),
  ('d2d00000-0000-0000-0000-000000000004', 'd2a00000-0000-0000-0000-0000000000a1', 'd2c00000-0000-0000-0000-0000000000c4', 'active'),
  ('d2d00000-0000-0000-0000-000000000006', 'd2a00000-0000-0000-0000-0000000000a1', 'd2c00000-0000-0000-0000-0000000000c5', 'active'),
  ('d2d00000-0000-0000-0000-000000000007', 'd2a00000-0000-0000-0000-0000000000a1', 'd2c00000-0000-0000-0000-0000000000c6', 'active');
