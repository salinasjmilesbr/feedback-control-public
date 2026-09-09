-- ============================================================================
-- F4-08 (Issue #95): cenário sintético de validação — RLS base e isolamento
-- real entre tenants (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f4-08.sql:
--
--   - três organizações sintéticas (Alfa, Beta e Gama F4-08);
--   - identidades/perfis sintéticos: USER_A (só Alfa), USER_B (só Beta),
--     USER_AB (Alfa + Beta — multi-tenant), USER_INACTIVE (membership Alfa
--     disabled), USER_NONE (sem membership) e AUTHOR (autor do evento de
--     sucessão);
--   - estrutura F3 mínima por org (job_role, unidade, posição, colaborador,
--     status) para provar leitura own-tenant e deny cross-tenant;
--   - snapshot + responsabilidade avaliativa em Alfa e Beta + evento de
--     sucessão em Alfa (idempotência) para provar que
--     `registrar_sucessao_avaliador` NEGA sucessão cross-tenant.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql); nunca em remoto;
--   - insere via superuser local (postgres) SEM alterar policies;
--   - reexecutável: remove/recria somente os UUIDs fixos (prefixo d8);
--   - apenas dados sintéticos; nenhum dado real.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Limpeza do cenário anterior (ordem respeita FKs ON DELETE RESTRICT)
-- ----------------------------------------------------------------------------
delete from public.evaluation_succession_events
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.cycle_evaluation_responsibilities
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshots
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
where collaborator_id::text like 'd8c00000-0000-0000-0000-0000000000%';

delete from public.organizational_positions
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.organizational_units
where organization_id::text like 'd8a00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id::text like 'd8c00000-0000-0000-0000-0000000000%';

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
-- Identidades + perfis (sintéticos)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d8b00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'usera.f4-08@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'userb.f4-08@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'userab.f4-08@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'userinactive.f4-08@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'usernone.f4-08@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d8b00000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'author.f4-08@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('d8b00000-0000-0000-0000-0000000000a1', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a2', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a3', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a4', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a5', 'active'),
  ('d8b00000-0000-0000-0000-0000000000a6', 'active');

-- ----------------------------------------------------------------------------
-- Memberships sintéticas
-- ----------------------------------------------------------------------------
insert into public.user_organization_memberships (id, user_profile_id, organization_id, status) values
  ('d8d00000-0000-0000-0000-0000000000a1', 'd8b00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1', 'active'),  -- USER_A -> Alfa
  ('d8d00000-0000-0000-0000-0000000000a2', 'd8b00000-0000-0000-0000-0000000000a2', 'd8a00000-0000-0000-0000-0000000000b1', 'active'),  -- USER_B -> Beta
  ('d8d00000-0000-0000-0000-0000000000a3', 'd8b00000-0000-0000-0000-0000000000a3', 'd8a00000-0000-0000-0000-0000000000a1', 'active'),  -- USER_AB -> Alfa
  ('d8d00000-0000-0000-0000-0000000000a4', 'd8b00000-0000-0000-0000-0000000000a3', 'd8a00000-0000-0000-0000-0000000000b1', 'active'),  -- USER_AB -> Beta
  ('d8d00000-0000-0000-0000-0000000000a5', 'd8b00000-0000-0000-0000-0000000000a4', 'd8a00000-0000-0000-0000-0000000000a1', 'disabled'); -- USER_INACTIVE -> Alfa (disabled)

-- ----------------------------------------------------------------------------
-- job_roles, unidades, posições e colaboradores sintéticos (F3)
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name) values
  ('d8e00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1', 'Analista Alfa'),
  ('d8e00000-0000-0000-0000-0000000000b1', 'd8a00000-0000-0000-0000-0000000000b1', 'Analista Beta'),
  ('d8e00000-0000-0000-0000-0000000000c1', 'd8a00000-0000-0000-0000-0000000000c1', 'Analista Gama');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('d8f00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1', 'Unidade Alfa', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000b1', 'd8a00000-0000-0000-0000-0000000000b1', 'Unidade Beta', '2024-01-01T00:00:00Z'),
  ('d8f00000-0000-0000-0000-0000000000c1', 'd8a00000-0000-0000-0000-0000000000c1', 'Unidade Gama', '2024-01-01T00:00:00Z');

insert into public.organizational_positions (id, organization_id, unit_id, job_role_id, valid_from) values
  ('d8f00000-0000-0000-0000-0000000000d1', 'd8a00000-0000-0000-0000-0000000000a1', 'd8f00000-0000-0000-0000-0000000000a1', 'd8e00000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),  -- P_A
  ('d8f00000-0000-0000-0000-0000000000d2', 'd8a00000-0000-0000-0000-0000000000b1', 'd8f00000-0000-0000-0000-0000000000b1', 'd8e00000-0000-0000-0000-0000000000b1', '2024-01-01T00:00:00Z'),  -- P_B
  ('d8f00000-0000-0000-0000-0000000000d3', 'd8a00000-0000-0000-0000-0000000000c1', 'd8f00000-0000-0000-0000-0000000000c1', 'd8e00000-0000-0000-0000-0000000000c1', '2024-01-01T00:00:00Z');  -- P_C

insert into public.collaborators (id, organization_id) values
  ('d8c00000-0000-0000-0000-0000000000a1', 'd8a00000-0000-0000-0000-0000000000a1'),  -- COLLAB_A (Alfa)
  ('d8c00000-0000-0000-0000-0000000000b1', 'd8a00000-0000-0000-0000-0000000000b1'),  -- COLLAB_B (Beta)
  ('d8c00000-0000-0000-0000-0000000000c1', 'd8a00000-0000-0000-0000-0000000000c1');  -- COLLAB_C (Gama)

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('d8c00000-0000-0000-0000-0000000000a1', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000b1', 'active', '2024-01-01T00:00:00Z'),
  ('d8c00000-0000-0000-0000-0000000000c1', 'active', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Snapshots + responsabilidades avaliativas (Alfa e Beta) para o teste
-- cross-tenant de `registrar_sucessao_avaliador`.
-- ----------------------------------------------------------------------------
insert into public.collegiate_cycle_snapshots (id, organization_id, ano, ciclo, collaborator_id, reference_date) values
  ('d8a00000-0000-0000-0000-0000000000a9', 'd8a00000-0000-0000-0000-0000000000a1', 2099, 1, 'd8c00000-0000-0000-0000-0000000000a1', '2099-01-01T00:00:00Z'),  -- S_A
  ('d8a00000-0000-0000-0000-0000000000b9', 'd8a00000-0000-0000-0000-0000000000b1', 2099, 1, 'd8c00000-0000-0000-0000-0000000000b1', '2099-01-01T00:00:00Z');  -- S_B

insert into public.cycle_evaluation_responsibilities (
  id, organization_id, snapshot_id, position_id, responsible_collaborator_id, valid_from
) values
  ('d8a00000-0000-0000-0000-0000000000aa', 'd8a00000-0000-0000-0000-0000000000a1',
   'd8a00000-0000-0000-0000-0000000000a9', 'd8f00000-0000-0000-0000-0000000000d1',
   'd8c00000-0000-0000-0000-0000000000a1', '2099-01-01T00:00:00Z'),  -- R_A
  ('d8a00000-0000-0000-0000-0000000000bb', 'd8a00000-0000-0000-0000-0000000000b1',
   'd8a00000-0000-0000-0000-0000000000b9', 'd8f00000-0000-0000-0000-0000000000d2',
   'd8c00000-0000-0000-0000-0000000000b1', '2099-01-01T00:00:00Z');  -- R_B

-- Evento de sucessão em Alfa (idempotência): faz a iteração de R_A `continue`
-- sem resolver estrutura, para que o guard de tenant falhe na iteração de R_B.
insert into public.evaluation_succession_events (
  id, organization_id, snapshot_id, position_id,
  previous_responsible_collaborator_id, new_responsible_collaborator_id,
  succession_date, motive, author_user_profile_id
) values (
  'd8a00000-0000-0000-0000-0000000000ac', 'd8a00000-0000-0000-0000-0000000000a1',
  'd8a00000-0000-0000-0000-0000000000a9', 'd8f00000-0000-0000-0000-0000000000d1',
  'd8c00000-0000-0000-0000-0000000000a1', 'd8c00000-0000-0000-0000-0000000000a1',
  '2099-06-01T00:00:00Z', 'teste idempotencia', 'd8b00000-0000-0000-0000-0000000000a6'
);
