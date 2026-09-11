-- ============================================================================
-- F5-07: cenário sintético de validação — colaboradores e histórico
-- organizacional soberanos (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Prepara, de forma determinística e idempotente:
--   - 2 organizações sintéticas (Alfa/Beta F5-07);
--   - 7 perfis/memberships de atores: ADMIN do tenant (com
--     org.structure.manage/org.catalog.manage/collaborator.*), GESTOR
--     funcional (role customizada com collaborator.read/create/edit), ator SEM
--     permissão, ator SEM autorização por cargo (ocupa posição GERENTE e não
--     possui assignment), ator de OUTRO tenant, perfil INATIVO e membership
--     revogável entre leitura e mutação;
--   - 9 colaboradores (8 em Alfa, 1 em Beta) com full_name/email/matrícula em
--     collaborator_identifiers e período de status vigente;
--   - catálogos (job_roles com code + seniority_levels), 2 unidades em Alfa,
--     7 posições, 2 reporting lines e 6 ocupações (Alfa) + 1 posição/ocupação
--     em Beta;
--   - vínculos membership → colaborador (F5-02) e autorização F4-01/F4-02
--     (role customizada + assignment de role de sistema + scope ORGANIZATION);
--   - snapshot F3-08 + responsabilidade avaliativa F3-09 abertas (sucessão) e
--     ciclo mínimo F5-06 (evaluation_cycles) para reference_cycle_id do evento.
--
-- Prefixos UUID exclusivos deste cenário (não colidem com F4-08 `d8`, F5-02
-- `d2`, F5-04 `d5` e F5-06 `d6`):
--   d7a00000 organizações        | d7b00000 auth.users/user_profiles
--   d7c00000 colaboradores       | d7d00000 user_organization_memberships
--   d7e00000 vínculos            | d7f00000 estrutura F3 + snapshot + ciclo
--   d7000000 autorização (role/assignment/scope)
--
-- Este arquivo NÃO chama nenhuma RPC da F5-07: ele apenas cria a fixture
-- (o cenário é reaplicado antes de cada validação). Todas as chamadas às RPC da
-- F5-07 estão em 02-validar-f5-07.sql e 03-validar-f5-07-cutover.sql, sempre
-- com p_actor_user_profile_id/p_operation_id válidos.
--
-- Executar como superuser local (`psql -U postgres`), ANTES de
-- 02-validar-f5-07.sql e 03-validar-f5-07-cutover.sql. Apenas dados fictícios.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- Limpeza do cenário anterior (ordem respeita FKs ON DELETE RESTRICT)
-- ----------------------------------------------------------------------------
delete from public.collaborator_events
 where organization_id::text like 'd7a00000%';

delete from public.evaluation_succession_events
 where organization_id::text like 'd7a00000%';

delete from public.cycle_evaluation_responsibilities
 where organization_id::text like 'd7a00000%';

delete from public.collegiate_cycle_snapshot_members
 where organization_id::text like 'd7a00000%';

delete from public.collegiate_cycle_snapshot_positions
 where organization_id::text like 'd7a00000%';

delete from public.collegiate_cycle_snapshots
 where organization_id::text like 'd7a00000%';

delete from public.temporary_responsibilities
 where organization_id::text like 'd7a00000%';

delete from public.occupations
 where organization_id::text like 'd7a00000%';

delete from public.position_reporting_lines
 where organization_id::text like 'd7a00000%';

delete from public.organizational_positions
 where organization_id::text like 'd7a00000%';

delete from public.organizational_unit_parent_periods
 where organization_id::text like 'd7a00000%';

delete from public.organizational_units
 where organization_id::text like 'd7a00000%';

delete from public.access_role_assignment_unit_targets
 where organization_id::text like 'd7a00000%';

delete from public.access_role_assignment_scopes
 where organization_id::text like 'd7a00000%';

delete from public.membership_access_role_assignments
 where organization_id::text like 'd7a00000%';

delete from public.membership_collaborator_links
 where organization_id::text like 'd7a00000%';

delete from public.access_role_capabilities
 where access_role_id::text like 'd7000000%';

delete from public.access_roles
 where id::text like 'd7000000%';

delete from public.collaborator_identifiers
 where organization_id::text like 'd7a00000%';

-- Períodos de status são filha indireta (sem organization_id) e precisam cobrir
-- TAMBÉM colaboradores criados por RPC (UUID aleatório) em execuções
-- anteriores — por isso a remoção é por subconsulta no tenant do cenário.
delete from public.collaborator_status_periods
 where collaborator_id in (
   select id from public.collaborators
    where organization_id::text like 'd7a00000%'
 );

delete from public.collaborators
 where organization_id::text like 'd7a00000%';

delete from public.seniority_levels
 where organization_id::text like 'd7a00000%';

delete from public.job_roles
 where organization_id::text like 'd7a00000%';

delete from public.evaluation_cycles
 where organization_id::text like 'd7a00000%';

delete from public.user_organization_memberships
 where id::text like 'd7d00000%';

delete from public.user_profiles
 where id::text like 'd7b00000%';

delete from auth.users
 where id::text like 'd7b00000%';

delete from public.organizations
 where id::text like 'd7a00000%';

-- ----------------------------------------------------------------------------
-- Organizações
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('d7a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-07 Alfa'),
  ('d7a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-07 Beta');

-- ----------------------------------------------------------------------------
-- auth.users + user_profiles
--   a1 = ADMIN do tenant Alfa (role de sistema `admin`, sem vínculo)
--   a2 = GESTOR funcional Alfa (role customizada collaborator.read/create/edit)
--   a3 = autenticado SEM permissão (membership ativa, sem assignment, sem vínculo)
--   a4 = ocupa posição GERENTE e NÃO possui autorização (prova T-22)
--   a5 = ator de OUTRO tenant (Beta)
--   a6 = perfil INATIVO com membership ativa (fail-closed)
--   a7 = membership revogável entre leitura e mutação (T-06/T-16)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d7b00000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-07.admin@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('d7b00000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-07.gestor@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('d7b00000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-07.sempermissao@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('d7b00000-0000-0000-0000-0000000000a4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-07.porcargo@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('d7b00000-0000-0000-0000-0000000000a5','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-07.beta@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('d7b00000-0000-0000-0000-0000000000a6','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-07.perfilinativo@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('d7b00000-0000-0000-0000-0000000000a7','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-07.revogavel@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now());

insert into public.user_profiles (id, status) values
  ('d7b00000-0000-0000-0000-0000000000a1','active'),
  ('d7b00000-0000-0000-0000-0000000000a2','active'),
  ('d7b00000-0000-0000-0000-0000000000a3','active'),
  ('d7b00000-0000-0000-0000-0000000000a4','active'),
  ('d7b00000-0000-0000-0000-0000000000a5','active'),
  ('d7b00000-0000-0000-0000-0000000000a6','disabled'),
  ('d7b00000-0000-0000-0000-0000000000a7','active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status) values
  ('d7d00000-0000-0000-0000-0000000000a1','d7b00000-0000-0000-0000-0000000000a1','d7a00000-0000-0000-0000-0000000000a1','active'),
  ('d7d00000-0000-0000-0000-0000000000a2','d7b00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1','active'),
  ('d7d00000-0000-0000-0000-0000000000a3','d7b00000-0000-0000-0000-0000000000a3','d7a00000-0000-0000-0000-0000000000a1','active'),
  ('d7d00000-0000-0000-0000-0000000000a4','d7b00000-0000-0000-0000-0000000000a4','d7a00000-0000-0000-0000-0000000000a1','active'),
  ('d7d00000-0000-0000-0000-0000000000b1','d7b00000-0000-0000-0000-0000000000a5','d7a00000-0000-0000-0000-0000000000b1','active'),
  ('d7d00000-0000-0000-0000-0000000000a6','d7b00000-0000-0000-0000-0000000000a6','d7a00000-0000-0000-0000-0000000000a1','active'),
  ('d7d00000-0000-0000-0000-0000000000a7','d7b00000-0000-0000-0000-0000000000a7','d7a00000-0000-0000-0000-0000000000a1','active');

-- ----------------------------------------------------------------------------
-- Catálogos da organização (job_roles com `code` — extensão aditiva F5-07)
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('d7f00000-0000-0000-0000-0000000000a1','d7a00000-0000-0000-0000-0000000000a1','Gerente Sintetico F5-07','GERENTE','active'),
  ('d7f00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1','Analista Sintetico F5-07','ANALISTA','active'),
  ('d7f00000-0000-0000-0000-0000000000a3','d7a00000-0000-0000-0000-0000000000a1','Consultor Sintetico F5-07','CONSULTOR','active'),
  ('d7f00000-0000-0000-0000-0000000000d1','d7a00000-0000-0000-0000-0000000000b1','Gerente Sintetico F5-07 Beta','GERENTE','active');

insert into public.seniority_levels (id, organization_id, name) values
  ('d7f00000-0000-0000-0000-0000000000a4','d7a00000-0000-0000-0000-0000000000a1','Pleno Sintetico F5-07');

-- ----------------------------------------------------------------------------
-- Unidades (Alfa: u1 raiz, u2 filha) + Beta
-- ----------------------------------------------------------------------------
insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('d7f00000-0000-0000-0000-0000000000b1','d7a00000-0000-0000-0000-0000000000a1','Unidade F5-07 Alfa Raiz','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000b2','d7a00000-0000-0000-0000-0000000000a1','Unidade F5-07 Alfa Filha','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000d2','d7a00000-0000-0000-0000-0000000000b1','Unidade F5-07 Beta','2024-01-01T00:00:00Z');

insert into public.organizational_unit_parent_periods
  (organization_id, unit_id, parent_unit_id, valid_from) values
  ('d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000b2','d7f00000-0000-0000-0000-0000000000b1','2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Posições
--   p1 u1/GERENTE      ← c1 (gestor inicial de c2)
--   p2 u2/ANALISTA     ← c2 (alvo de edição, gestor e histórico temporal)
--   p3 u1/CONSULTOR    ← c4 (NOVO gestor de c2)
--   p4 u2/GERENTE      ← c3 (alvo da inativação com pendência)
--   p5 u2/ANALISTA     ← c5 (origem da troca de unidade/posição)
--   p6 u1/CONSULTOR    ← vaga (destino da troca de unidade/posição)
--   p7 u1/ANALISTA     ← c6 (alvo do ciclo de status active→leave→active)
-- ----------------------------------------------------------------------------
insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from) values
  ('d7f00000-0000-0000-0000-0000000000c1','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000b1','d7f00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000a4','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000c2','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000b2','d7f00000-0000-0000-0000-0000000000a2','d7f00000-0000-0000-0000-0000000000a4','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000c3','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000b1','d7f00000-0000-0000-0000-0000000000a3','d7f00000-0000-0000-0000-0000000000a4','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000c4','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000b2','d7f00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000a4','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000c5','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000b2','d7f00000-0000-0000-0000-0000000000a2','d7f00000-0000-0000-0000-0000000000a4','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000c6','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000b1','d7f00000-0000-0000-0000-0000000000a3','d7f00000-0000-0000-0000-0000000000a4','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000c7','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000b1','d7f00000-0000-0000-0000-0000000000a2','d7f00000-0000-0000-0000-0000000000a4','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000d3','d7a00000-0000-0000-0000-0000000000b1','d7f00000-0000-0000-0000-0000000000d2','d7f00000-0000-0000-0000-0000000000d1',null,'2024-01-01T00:00:00Z');

-- Reporting lines: p2 → p1 (troca de gestor em 02) e p5 → p1 (encerramento)
insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('d7f00000-0000-0000-0000-0000000000e1','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000c2','d7f00000-0000-0000-0000-0000000000c1','estrutura sintetica f5-07','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000e2','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000c5','d7f00000-0000-0000-0000-0000000000c1','estrutura sintetica f5-07','2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Colaboradores (identidade interna = UUID; matrícula é intenção)
-- ----------------------------------------------------------------------------
insert into public.collaborators
  (id, organization_id, full_name, email, admission_date) values
  ('d7c00000-0000-0000-0000-0000000000c1','d7a00000-0000-0000-0000-0000000000a1','Colaborador Sintetico F5-07 Um','colaborador.f5-07.1@example.invalid', date '2024-01-01'),
  ('d7c00000-0000-0000-0000-0000000000c2','d7a00000-0000-0000-0000-0000000000a1','Colaborador Sintetico F5-07 Dois','colaborador.f5-07.2@example.invalid', date '2024-01-01'),
  ('d7c00000-0000-0000-0000-0000000000c3','d7a00000-0000-0000-0000-0000000000a1','Colaborador Sintetico F5-07 Tres','colaborador.f5-07.3@example.invalid', date '2024-01-01'),
  ('d7c00000-0000-0000-0000-0000000000c4','d7a00000-0000-0000-0000-0000000000a1','Colaborador Sintetico F5-07 Quatro','colaborador.f5-07.4@example.invalid', date '2024-01-01'),
  ('d7c00000-0000-0000-0000-0000000000c5','d7a00000-0000-0000-0000-0000000000a1','Colaborador Sintetico F5-07 Cinco','colaborador.f5-07.5@example.invalid', date '2024-01-01'),
  ('d7c00000-0000-0000-0000-0000000000c6','d7a00000-0000-0000-0000-0000000000a1','Colaborador Sintetico F5-07 Seis','colaborador.f5-07.6@example.invalid', date '2024-01-01'),
  ('d7c00000-0000-0000-0000-0000000000c8','d7a00000-0000-0000-0000-0000000000a1','Colaborador Sintetico F5-07 Oito','colaborador.f5-07.8@example.invalid', date '2024-01-01'),
  ('d7c00000-0000-0000-0000-0000000000c9','d7a00000-0000-0000-0000-0000000000a1','Colaborador Sintetico F5-07 Nove','colaborador.f5-07.9@example.invalid', date '2024-01-01'),
  ('d7c00000-0000-0000-0000-0000000000b1','d7a00000-0000-0000-0000-0000000000b1','Colaborador Sintetico F5-07 Beta','colaborador.f5-07.beta@example.invalid', date '2024-01-01');

insert into public.collaborator_identifiers
  (collaborator_id, organization_id, business_code, valid_from) values
  ('d7c00000-0000-0000-0000-0000000000c1','d7a00000-0000-0000-0000-0000000000a1','F507-0001','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c2','d7a00000-0000-0000-0000-0000000000a1','F507-0002','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c3','d7a00000-0000-0000-0000-0000000000a1','F507-0003','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c4','d7a00000-0000-0000-0000-0000000000a1','F507-0004','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c5','d7a00000-0000-0000-0000-0000000000a1','F507-0005','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c6','d7a00000-0000-0000-0000-0000000000a1','F507-0006','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c8','d7a00000-0000-0000-0000-0000000000a1','F507-0008','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c9','d7a00000-0000-0000-0000-0000000000a1','F507-0009','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000b1','d7a00000-0000-0000-0000-0000000000b1','F507-9001','2024-01-01T00:00:00Z');

insert into public.collaborator_status_periods
  (collaborator_id, status, valid_from) values
  ('d7c00000-0000-0000-0000-0000000000c1','active','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c2','active','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c3','active','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c4','active','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c5','active','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c6','active','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c8','active','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000c9','active','2024-01-01T00:00:00Z'),
  ('d7c00000-0000-0000-0000-0000000000b1','active','2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Ocupações vigentes (c8 e c9 ficam SEM alocação — §14.6 do desenho)
-- ----------------------------------------------------------------------------
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('d7f00000-0000-0000-0000-0000000000f1','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c1','d7f00000-0000-0000-0000-0000000000c1','ocupacao sintetica f5-07','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000f2','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c2','d7f00000-0000-0000-0000-0000000000c2','ocupacao sintetica f5-07','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000f3','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c3','d7f00000-0000-0000-0000-0000000000c4','ocupacao sintetica f5-07','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000f4','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c4','d7f00000-0000-0000-0000-0000000000c3','ocupacao sintetica f5-07','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000f5','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c5','d7f00000-0000-0000-0000-0000000000c5','ocupacao sintetica f5-07','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000f6','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c6','d7f00000-0000-0000-0000-0000000000c7','ocupacao sintetica f5-07','2024-01-01T00:00:00Z'),
  ('d7f00000-0000-0000-0000-0000000000d4','d7a00000-0000-0000-0000-0000000000b1','d7c00000-0000-0000-0000-0000000000b1','d7f00000-0000-0000-0000-0000000000d3','ocupacao sintetica f5-07','2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- Vínculos membership → colaborador (F5-02)
--   a2 → c1 (gestor funcional) | a4 → c3 (GERENTE sem autorização)
--   a7 → c6 (revogável)        | a5 → c7 (Beta)
-- ----------------------------------------------------------------------------
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status) values
  ('d7e00000-0000-0000-0000-0000000000a1','d7d00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c1','active'),
  ('d7e00000-0000-0000-0000-0000000000a2','d7d00000-0000-0000-0000-0000000000a4','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c3','active'),
  ('d7e00000-0000-0000-0000-0000000000a3','d7d00000-0000-0000-0000-0000000000a7','d7a00000-0000-0000-0000-0000000000a1','d7c00000-0000-0000-0000-0000000000c6','active'),
  ('d7e00000-0000-0000-0000-0000000000b1','d7d00000-0000-0000-0000-0000000000b1','d7a00000-0000-0000-0000-0000000000b1','d7c00000-0000-0000-0000-0000000000b1','active');

-- ----------------------------------------------------------------------------
-- Autorização (F4-01/F4-02): role customizada funcional + assignment da role de
-- sistema `admin` para a organização Alfa, ambas com scope ORGANIZATION.
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('d7000000-0000-0000-0000-0000000000f1','gestao_colaboradores_f507','active',false,'d7a00000-0000-0000-0000-0000000000a1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select 'd7000000-0000-0000-0000-0000000000f1', c.id
  from public.capabilities c
 where c.code in ('collaborator.read', 'collaborator.create', 'collaborator.edit');

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('d7000000-0000-0000-0000-0000000000a1','d7d00000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1','d7000000-0000-0000-0000-0000000000f1','active','d7b00000-0000-0000-0000-0000000000a1'),
  ('d7000000-0000-0000-0000-0000000000a2','d7d00000-0000-0000-0000-0000000000a1','d7a00000-0000-0000-0000-0000000000a1','c0000000-0000-4000-8000-0000000000f1','active','d7b00000-0000-0000-0000-0000000000a1');

insert into public.access_role_assignment_scopes
  (id, assignment_id, organization_id, scope_type, status, created_by) values
  ('d7000000-0000-0000-0000-0000000000b1','d7000000-0000-0000-0000-0000000000a1','d7a00000-0000-0000-0000-0000000000a1','ORGANIZATION','active','d7b00000-0000-0000-0000-0000000000a1'),
  ('d7000000-0000-0000-0000-0000000000b2','d7000000-0000-0000-0000-0000000000a2','d7a00000-0000-0000-0000-0000000000a1','ORGANIZATION','active','d7b00000-0000-0000-0000-0000000000a1');

-- ----------------------------------------------------------------------------
-- Snapshot F3-08 + responsabilidade avaliativa F3-09 (fixture da sucessão) e
-- ciclo mínimo F5-06 (reference_cycle_id do evento de histórico).
-- ----------------------------------------------------------------------------
insert into public.collegiate_cycle_snapshots
  (id, organization_id, ano, ciclo, collaborator_id, reference_date) values
  ('d7f00000-0000-0000-0000-0000000000a9','d7a00000-0000-0000-0000-0000000000a1',2026,1,'d7c00000-0000-0000-0000-0000000000c2','2024-01-01T00:00:00Z');

insert into public.collegiate_cycle_snapshot_positions
  (id, snapshot_id, organization_id, position_id, superior_position_id, superior_collaborator_id) values
  ('d7f00000-0000-0000-0000-0000000000b9','d7f00000-0000-0000-0000-0000000000a9','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000c2','d7f00000-0000-0000-0000-0000000000c1','d7c00000-0000-0000-0000-0000000000c1');

insert into public.cycle_evaluation_responsibilities
  (id, organization_id, snapshot_id, position_id, responsible_collaborator_id, valid_from) values
  ('d7f00000-0000-0000-0000-0000000000c9','d7a00000-0000-0000-0000-0000000000a1','d7f00000-0000-0000-0000-0000000000a9','d7f00000-0000-0000-0000-0000000000c2','d7c00000-0000-0000-0000-0000000000c6','2024-01-01T00:00:00Z');

insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim) values
  ('d7f00000-0000-0000-0000-0000000000d9','d7a00000-0000-0000-0000-0000000000a1',2026,1,'ATIVO', date '2026-01-01', date '2026-06-30');

-- ----------------------------------------------------------------------------
-- Consistência da fixture (falha cedo se o cenário ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.organizations where id::text like 'd7a00000%';
  if v_n <> 2 then
    raise exception '[FAIL] cenario F5-07: organizacoes esperadas=2, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.user_profiles where id::text like 'd7b00000%';
  if v_n <> 7 then
    raise exception '[FAIL] cenario F5-07: perfis esperados=7, encontrados=%', v_n;
  end if;

  select count(*) into v_n from public.user_organization_memberships where id::text like 'd7d00000%';
  if v_n <> 7 then
    raise exception '[FAIL] cenario F5-07: memberships esperadas=7, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.collaborators where organization_id::text like 'd7a00000%';
  if v_n <> 9 then
    raise exception '[FAIL] cenario F5-07: colaboradores esperados=9, encontrados=%', v_n;
  end if;

  select count(*) into v_n from public.collaborator_identifiers
   where organization_id::text like 'd7a00000%' and valid_to is null;
  if v_n <> 9 then
    raise exception '[FAIL] cenario F5-07: identificadores abertos esperados=9, encontrados=%', v_n;
  end if;

  select count(*) into v_n from public.collaborator_status_periods
   where collaborator_id in (select id from public.collaborators where organization_id::text like 'd7a00000%')
     and valid_to is null;
  if v_n <> 9 then
    raise exception '[FAIL] cenario F5-07: periodos de status abertos esperados=9, encontrados=%', v_n;
  end if;

  select count(*) into v_n from public.organizational_positions where organization_id::text like 'd7a00000%';
  if v_n <> 8 then
    raise exception '[FAIL] cenario F5-07: posicoes esperadas=8, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.occupations
   where organization_id::text like 'd7a00000%' and valid_to is null;
  if v_n <> 7 then
    raise exception '[FAIL] cenario F5-07: ocupacoes vigentes esperadas=7, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.position_reporting_lines
   where organization_id::text like 'd7a00000%' and valid_to is null;
  if v_n <> 2 then
    raise exception '[FAIL] cenario F5-07: reporting lines vigentes esperadas=2, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.membership_collaborator_links
   where organization_id::text like 'd7a00000%' and status = 'active';
  if v_n <> 4 then
    raise exception '[FAIL] cenario F5-07: vinculos ativos esperados=4, encontrados=%', v_n;
  end if;

  select count(*) into v_n from public.membership_access_role_assignments
   where organization_id::text like 'd7a00000%' and status = 'active';
  if v_n <> 2 then
    raise exception '[FAIL] cenario F5-07: atribuicoes ativas esperadas=2, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.access_role_assignment_scopes
   where organization_id::text like 'd7a00000%' and status = 'active';
  if v_n <> 2 then
    raise exception '[FAIL] cenario F5-07: escopos ativos esperados=2, encontrados=%', v_n;
  end if;

  select count(*) into v_n from public.cycle_evaluation_responsibilities
   where organization_id::text like 'd7a00000%' and valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] cenario F5-07: responsabilidade avaliativa aberta esperada=1, encontrada=%', v_n;
  end if;

  select count(*) into v_n from public.evaluation_cycles where organization_id::text like 'd7a00000%';
  if v_n <> 1 then
    raise exception '[FAIL] cenario F5-07: ciclos esperados=1, encontrados=%', v_n;
  end if;

  raise notice '[PASS] cenario F5-07 pronto: 2 organizacoes, 7 atores, 9 colaboradores (8 Alfa + 1 Beta), estrutura F3, vinculos, autorizacao, snapshot/ciclo';
end $$;
