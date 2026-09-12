-- ============================================================================
-- F5-08 P1 (Etapa 5): cenario sintetico de validacao — integridade estrutural
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-08-desenho-tecnico.md (§23.1/§23.2 — grupos A, B, C, D, E,
-- F do P1: `structure_events`, I1, I2, I3, D24 e grants).
--
-- Este arquivo prepara, de forma DETERMINISTICA e REEXECUTAVEL, a fixture usada
-- por `02-validar-f5-08.sql`:
--
--   - duas organizacoes sinteticas (Alfa e Beta F5-08), com catalogos, ator e
--     membership do ator (necessarios as FKs de autoria de `structure_events`);
--   - unidades que exercitam: cadeia valida, ciclo direto, ciclo multinivel,
--     janelas temporais DISJUNTAS (nao ciclo) e SOBREPOSTAS (ciclo), unidade
--     com posicao vigente, unidade como FILHA, unidade como PAI e unidade
--     encerravel (sem dependencia);
--   - posicoes (uma com ocupacao vigente, uma com reporting line vigente, uma
--     livre) e um colaborador sintetico ocupante;
--   - uma linha de trilha `structure_events` para os testes de append-only.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca em projeto
--     remoto; nenhum dado real e utilizado (apenas ficticio).
--   - Insere via superuser local (equivalente a service_role): a RLS e as
--     policies NAO sao alteradas — o deny-by-default e validado na etapa 02.
--   - Nenhuma RPC e chamada aqui: o P1 nao possui RPCs novas (P2).
--   - REEXECUTAVEL: remove e recria somente os UUIDs fixos abaixo (prefixo f8).
--
-- Janelas temporais usadas (UTC):
--   T0 = 2026-01-01  T1 = 2026-02-01  T2 = 2026-03-01  T3 = 2026-04-01
--   TC = 2026-05-01 (instante de encerramento dos testes de I2/I3)
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Limpeza do cenario anterior (somente UUIDs fixos desta validacao)
-- ----------------------------------------------------------------------------
delete from public.structure_events
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.collegiate_configuration_members
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.collegiate_configurations
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.occupations
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.position_reporting_lines
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_positions
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_unit_parent_periods
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborators
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.job_roles
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.seniority_levels
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_assignment_scopes
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.membership_access_role_assignments
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.user_organization_memberships
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.user_profiles
where id in (
  'f8c00000-0000-0000-0000-0000000000a1',
  'f8c00000-0000-0000-0000-0000000000a2',
  'f8c00000-0000-0000-0000-0000000000b1'
);

-- Atores sinteticos em `auth.users` (FK `fk_user_profiles_auth_users`).
delete from auth.users
where id::text like 'f8c00000%';

delete from public.organizations
where id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- 1) Organizacoes, atores e catalogos
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f8a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-08 Alfa'),
  ('f8a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-08 Beta');

-- Atores da fixture: `user_profiles` espelha `auth.users` (FK obrigatoria).
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f8c00000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-08.alfa@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('f8c00000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-08.beta@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('f8c00000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f5-08.semcap@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now());

insert into public.user_profiles (id, status) values
  ('f8c00000-0000-0000-0000-0000000000a1', 'active'),
  ('f8c00000-0000-0000-0000-0000000000b1', 'active'),
  ('f8c00000-0000-0000-0000-0000000000a2', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status) values
  ('f8d00000-0000-0000-0000-0000000000a1',
   'f8c00000-0000-0000-0000-0000000000a1',
   'f8a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f8d00000-0000-0000-0000-0000000000b1',
   'f8c00000-0000-0000-0000-0000000000b1',
   'f8a00000-0000-0000-0000-0000000000b1', 'active'),
  ('f8d00000-0000-0000-0000-0000000000a2',
   'f8c00000-0000-0000-0000-0000000000a2',
   'f8a00000-0000-0000-0000-0000000000a1', 'active');

insert into public.job_roles (id, organization_id, name, code, status) values
  ('f8e00000-0000-0000-0000-0000000000a1',
   'f8a00000-0000-0000-0000-0000000000a1', 'Analista F5-08', 'ANL-F5-08', 'active'),
  ('f8e00000-0000-0000-0000-0000000000b1',
   'f8a00000-0000-0000-0000-0000000000b1', 'Analista F5-08 Beta', 'ANL-F5-08-B', 'active'),
  ('f8e00000-0000-0000-0000-0000000000a2',
   'f8a00000-0000-0000-0000-0000000000a1', 'Cargo F5-08 Desativado', 'CARGO-OFF-F5-08', 'disabled');

insert into public.seniority_levels (id, organization_id, name, status) values
  ('f8f00000-0000-0000-0000-0000000000a1',
   'f8a00000-0000-0000-0000-0000000000a1', 'Senior F5-08', 'active'),
  ('f8f00000-0000-0000-0000-0000000000b1',
   'f8a00000-0000-0000-0000-0000000000b1', 'Senior F5-08 Beta', 'active'),
  ('f8f00000-0000-0000-0000-0000000000a2',
   'f8a00000-0000-0000-0000-0000000000a1', 'Senior F5-08 Desativada', 'disabled');

insert into public.collaborators (id, organization_id, full_name) values
  ('f8500000-0000-0000-0000-0000000000a1',
   'f8a00000-0000-0000-0000-0000000000a1', 'Colaborador Sintetico F5-08'),
  ('f8500000-0000-0000-0000-0000000000a2',
   'f8a00000-0000-0000-0000-0000000000a1', 'Membro Colegiado F5-08 A'),
  ('f8500000-0000-0000-0000-0000000000a3',
   'f8a00000-0000-0000-0000-0000000000a1', 'Membro Colegiado F5-08 B'),
  ('f8500000-0000-0000-0000-0000000000b1',
   'f8a00000-0000-0000-0000-0000000000b1', 'Colaborador Sintetico F5-08 Beta');

-- ----------------------------------------------------------------------------
-- 2) Unidades (Alfa) — todas vigentes desde T0 (valid_to null)
-- ----------------------------------------------------------------------------
insert into public.organizational_units (id, organization_id, name, valid_from)
values
  ('f8110000-0000-0000-0000-000000000001', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Raiz',        '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000002', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Filha',       '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000003', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Neta',        '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000004', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Com Posicao', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000005', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Livre',       '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000006', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Pai Encerravel',   '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000007', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Filha Encerravel', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000008', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Temporal Encerravel', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000009', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Ciclo Direto 1', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-00000000000a', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Ciclo Direto 2', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-00000000000b', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Ciclo Multi 1', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-00000000000c', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Ciclo Multi 2', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-00000000000d', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Ciclo Multi 3', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-00000000000e', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Temporal A', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-00000000000f', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Temporal B', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000010', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Temporal C', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000011', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 FP Nova',  '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000012', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 FP A',     '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000013', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 FP B',     '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000014', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Int Nova', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000015', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Int E',    '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000016', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 Int F',    '2026-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 3) Unidades (Beta) — cadeia valida, para o teste de isolamento por tenant
-- ----------------------------------------------------------------------------
insert into public.organizational_units (id, organization_id, name, valid_from)
values
  ('f8210000-0000-0000-0000-000000000001', 'f8a00000-0000-0000-0000-0000000000b1', 'F5-08 Beta Raiz',  '2026-01-01T00:00:00Z'),
  ('f8210000-0000-0000-0000-000000000002', 'f8a00000-0000-0000-0000-0000000000b1', 'F5-08 Beta Filha', '2026-01-01T00:00:00Z'),
  ('f8210000-0000-0000-0000-000000000003', 'f8a00000-0000-0000-0000-0000000000b1', 'F5-08 Beta Neta',  '2026-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 4) Parent periods (Alfa)
-- ----------------------------------------------------------------------------
--  01-02 cadeia valida (filha -> raiz, neta -> filha)
--  03    ciclo direto: d1 -> d2 (o teste tenta d2 -> d1 e deve ser recusado)
--  04-05 ciclo multinivel: m1 -> m2 -> m3 (o teste tenta m3 -> m1 e deve ser recusado)
--  06    unidade FILHA de relacao vigente (filha-encerravel -> pai-encerravel)
--  07    unidade encerravel por tempo (temporal-encerravel -> raiz)
--  08-09 janelas DISJUNTAS [T0,T1) — base do teste temporal de I1
--  0a-0b FALSO POSITIVO do anti-ciclo: A->B em [01-10,01-20) e B->C em
--        [02-10,02-20) — ambos sobrepostos a janela ampla de NEW, mas SEM
--        instante comum ⇒ nao existe ciclo temporal real (deve ser ACEITO)
--  0c-0d controle positivo: E->F em [01-10,01-25) e F->D em [01-20,02-05)
--        com interseccao NAO vazia [01-20,01-25) ⇒ ciclo real (RECUSADO)
insert into public.organizational_unit_parent_periods
  (id, organization_id, unit_id, parent_unit_id, valid_from, valid_to) values
  ('f8710000-0000-0000-0000-000000000001', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000002', 'f8110000-0000-0000-0000-000000000001',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-000000000002', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000003', 'f8110000-0000-0000-0000-000000000002',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-000000000003', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000009', 'f8110000-0000-0000-0000-00000000000a',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-000000000004', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-00000000000b', 'f8110000-0000-0000-0000-00000000000c',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-000000000005', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-00000000000c', 'f8110000-0000-0000-0000-00000000000d',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-000000000006', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000007', 'f8110000-0000-0000-0000-000000000006',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-000000000007', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000008', 'f8110000-0000-0000-0000-000000000001',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-000000000008', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-00000000000e', 'f8110000-0000-0000-0000-00000000000f',
   '2026-01-01T00:00:00Z', '2026-02-01T00:00:00Z'),
  ('f8710000-0000-0000-0000-000000000009', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-00000000000f', 'f8110000-0000-0000-0000-000000000010',
   '2026-01-01T00:00:00Z', '2026-02-01T00:00:00Z'),
  ('f8710000-0000-0000-0000-00000000000a', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000012', 'f8110000-0000-0000-0000-000000000013',
   '2026-01-10T00:00:00Z', '2026-01-20T00:00:00Z'),
  ('f8710000-0000-0000-0000-00000000000b', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000013', 'f8110000-0000-0000-0000-000000000011',
   '2026-02-10T00:00:00Z', '2026-02-20T00:00:00Z'),
  ('f8710000-0000-0000-0000-00000000000c', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000015', 'f8110000-0000-0000-0000-000000000016',
   '2026-01-10T00:00:00Z', '2026-01-25T00:00:00Z'),
  ('f8710000-0000-0000-0000-00000000000d', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000016', 'f8110000-0000-0000-0000-000000000014',
   '2026-01-20T00:00:00Z', '2026-02-05T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 5) Parent periods (Beta) — cadeia valida no outro tenant
-- ----------------------------------------------------------------------------
insert into public.organizational_unit_parent_periods
  (id, organization_id, unit_id, parent_unit_id, valid_from, valid_to) values
  ('f8710000-0000-0000-0000-0000000000b1', 'f8a00000-0000-0000-0000-0000000000b1',
   'f8210000-0000-0000-0000-000000000002', 'f8210000-0000-0000-0000-000000000001',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-0000000000b2', 'f8a00000-0000-0000-0000-0000000000b1',
   'f8210000-0000-0000-0000-000000000003', 'f8210000-0000-0000-0000-000000000002',
   '2026-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- 6) Posicoes (Alfa)
-- ----------------------------------------------------------------------------
--  P-OCUP na "Com Posicao" (com ocupacao vigente)
--  P-MGR / P-SUB na "Livre" (com reporting line vigente)
--  P-FREE na "Livre" (ocupacao encerravel no instante TC)
insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from) values
  ('f8310000-0000-0000-0000-000000000001', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000004', 'f8e00000-0000-0000-0000-0000000000a1',
   'f8f00000-0000-0000-0000-0000000000a1', '2026-01-01T00:00:00Z'),
  ('f8310000-0000-0000-0000-000000000002', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000005', 'f8e00000-0000-0000-0000-0000000000a1',
   'f8f00000-0000-0000-0000-0000000000a1', '2026-01-01T00:00:00Z'),
  ('f8310000-0000-0000-0000-000000000003', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000005', 'f8e00000-0000-0000-0000-0000000000a1',
   'f8f00000-0000-0000-0000-0000000000a1', '2026-01-01T00:00:00Z'),
  ('f8310000-0000-0000-0000-000000000004', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000005', 'f8e00000-0000-0000-0000-0000000000a1',
   'f8f00000-0000-0000-0000-0000000000a1', '2026-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 7) Ocupacoes e reporting line (Alfa)
-- ----------------------------------------------------------------------------
--  O-OCUP: ocupacao vigente em P-OCUP         (teste de recusa de I3)
--  O-FREE: ocupacao vigente em P-FREE         (teste de encerramento em TC)
--  R-1:    P-SUB reporta a P-MGR              (guarda F3-04 preservada)
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('f8410000-0000-0000-0000-000000000001', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8500000-0000-0000-0000-0000000000a1', 'f8310000-0000-0000-0000-000000000001',
   'ocupacao vigente F5-08', '2026-01-01T00:00:00Z'),
  ('f8410000-0000-0000-0000-000000000002', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8500000-0000-0000-0000-0000000000a1', 'f8310000-0000-0000-0000-000000000004',
   'ocupacao encerravel F5-08', '2026-01-01T00:00:00Z');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('f8610000-0000-0000-0000-000000000001', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8310000-0000-0000-0000-000000000003', 'f8310000-0000-0000-0000-000000000002',
   'reporting line vigente F5-08', '2026-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 8) Trilha `structure_events` — uma linha para os testes de append-only
-- ----------------------------------------------------------------------------
insert into public.structure_events
  (id, organization_id, entity_type, entity_id, event_type, effective_date,
   reason, after_value, payload_hash, actor_user_profile_id, actor_membership_id,
   operation_id) values
  ('f8810000-0000-0000-0000-000000000001', 'f8a00000-0000-0000-0000-0000000000a1',
   'organizational_unit', 'f8110000-0000-0000-0000-000000000001', 'CRIADO',
   '2026-01-01T00:00:00Z', 'fixture F5-08 P1',
   '{"name": "F5-08 Raiz"}'::jsonb,
   encode(sha256(convert_to('fixture-f5-08-p1', 'UTF8')), 'hex'),
   'f8c00000-0000-0000-0000-0000000000a1', 'f8d00000-0000-0000-0000-0000000000a1',
   'f8900000-0000-0000-0000-000000000001');

-- ----------------------------------------------------------------------------
-- 10) Fixture do P2 — RPCs soberanas (autorizacao + estrutura dedicada)
-- ----------------------------------------------------------------------------
-- Autorizacao: role de SISTEMA `admin` (bundle com org.structure.manage e
-- org.catalog.manage — 20260908000001) atribuida a membership do ator Alfa com
-- scope ORGANIZATION, exatamente o que `resolver_capabilities_escopos_efetivas`
-- exige (assignment ativo + scope ativo). O ator `f8c00000-...a2` fica SEM
-- assignment (fixture de "ator sem capability") e o ator Beta serve ao teste
-- cross-tenant.
insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f8a10000-0000-0000-0000-000000000001', 'f8d00000-0000-0000-0000-0000000000a1',
   'f8a00000-0000-0000-0000-0000000000a1', 'c0000000-0000-4000-8000-0000000000f1',
   'active', 'f8c00000-0000-0000-0000-0000000000a1');

insert into public.access_role_assignment_scopes
  (id, assignment_id, organization_id, scope_type, status, created_by) values
  ('f8a20000-0000-0000-0000-000000000001', 'f8a10000-0000-0000-0000-000000000001',
   'f8a00000-0000-0000-0000-0000000000a1', 'ORGANIZATION', 'active',
   'f8c00000-0000-0000-0000-0000000000a1');

-- Unidades dedicadas aos testes de RPC (a validacao do P1 NAO as toca; ela roda
-- antes e consome as unidades 0006/0007/0008 do cenario base):
--   0017 U-POS          — recebe posicao vigente (I2 caso i e I3 ocupacao)
--   0018 U-FILHA        — e FILHA em relacao vigente (I2 caso ii)
--   0019 U-PAI          — e PAI de relacao vigente (I2 caso iii)
--   001a U-FILHA-DE-PAI — filha de U-PAI
--   001b U-LIVRE        — sem dependencia (encerramento permitido)
insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f8110000-0000-0000-0000-000000000017', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 P2 U-POS',          '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000018', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 P2 U-FILHA',        '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-000000000019', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 P2 U-PAI',          '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-00000000001a', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 P2 U-FILHA-DE-PAI', '2026-01-01T00:00:00Z'),
  ('f8110000-0000-0000-0000-00000000001b', 'f8a00000-0000-0000-0000-0000000000a1', 'F5-08 P2 U-LIVRE',        '2026-01-01T00:00:00Z');

insert into public.organizational_unit_parent_periods
  (id, organization_id, unit_id, parent_unit_id, valid_from, valid_to) values
  ('f8710000-0000-0000-0000-00000000000e', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000018', 'f8110000-0000-0000-0000-000000000001',
   '2026-01-01T00:00:00Z', null),
  ('f8710000-0000-0000-0000-00000000000f', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-00000000001a', 'f8110000-0000-0000-0000-000000000019',
   '2026-01-01T00:00:00Z', null);

-- Posicoes dedicadas:
--   05 P2-P-OCUP    — com ocupacao vigente (I3) e bloqueio de I2 caso (i)
--   06 P2-P-REP-SUB — com reporting line vigente (guarda F3-04)
--   07 P2-P-REP-MGR — superior da reporting line acima
--   08 P2-P-LIVRE   — sem ocupacao/reporting line (encerramento permitido)
insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from) values
  ('f8310000-0000-0000-0000-000000000005', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-000000000017', 'f8e00000-0000-0000-0000-0000000000a1',
   'f8f00000-0000-0000-0000-0000000000a1', '2026-01-01T00:00:00Z'),
  ('f8310000-0000-0000-0000-000000000006', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-00000000001b', 'f8e00000-0000-0000-0000-0000000000a1',
   'f8f00000-0000-0000-0000-0000000000a1', '2026-01-01T00:00:00Z'),
  ('f8310000-0000-0000-0000-000000000007', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-00000000001b', 'f8e00000-0000-0000-0000-0000000000a1',
   'f8f00000-0000-0000-0000-0000000000a1', '2026-01-01T00:00:00Z'),
  ('f8310000-0000-0000-0000-000000000008', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8110000-0000-0000-0000-00000000001b', 'f8e00000-0000-0000-0000-0000000000a1',
   'f8f00000-0000-0000-0000-0000000000a1', '2026-01-01T00:00:00Z');

insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('f8410000-0000-0000-0000-000000000003', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8500000-0000-0000-0000-0000000000a1', 'f8310000-0000-0000-0000-000000000005',
   'ocupacao vigente P2', '2026-01-01T00:00:00Z');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('f8610000-0000-0000-0000-000000000002', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8310000-0000-0000-0000-000000000006', 'f8310000-0000-0000-0000-000000000007',
   'reporting line vigente P2', '2026-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 11) Resumo do cenario
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs    int;
  v_units   int;
  v_per     int;
  v_pos     int;
  v_evt     int;
  v_colab   int;
  v_cargos  int;
  v_senior  int;
  v_caps    int;
  v_caps_no int;
begin
  select count(*) into v_orgs  from public.organizations
   where id in ('f8a00000-0000-0000-0000-0000000000a1', 'f8a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_units from public.organizational_units
   where organization_id in ('f8a00000-0000-0000-0000-0000000000a1', 'f8a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_per   from public.organizational_unit_parent_periods
   where organization_id in ('f8a00000-0000-0000-0000-0000000000a1', 'f8a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_pos   from public.organizational_positions
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
  select count(*) into v_evt   from public.structure_events
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';

  select count(*) into v_colab from public.collaborators
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
  select count(*) into v_cargos from public.job_roles
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
  select count(*) into v_senior from public.seniority_levels
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';

  -- O ator admin resolve AMBAS as capabilities; o ator sem assignment, nenhuma.
  select count(*) into v_caps
    from public.resolver_capabilities_escopos_efetivas(
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8a00000-0000-0000-0000-0000000000a1')
   where capability_code in ('org.structure.manage', 'org.catalog.manage');
  select count(*) into v_caps_no
    from public.resolver_capabilities_escopos_efetivas(
      'f8c00000-0000-0000-0000-0000000000a2',
      'f8a00000-0000-0000-0000-0000000000a1');

  if v_orgs <> 2 or v_units <> 30 or v_per <> 17 or v_pos <> 8 or v_evt <> 1 then
    raise exception
      '[FAIL] cenario F5-08 incompleto (orgs=%, units=%, periods=%, positions=%, events=%)',
      v_orgs, v_units, v_per, v_pos, v_evt;
  end if;
  if v_colab <> 3 or v_cargos <> 2 or v_senior <> 2 then
    raise exception
      '[FAIL] cenario F5-08 P2 incompleto (colaboradores=%, cargos=%, senioridades=%)',
      v_colab, v_cargos, v_senior;
  end if;
  if v_caps <> 2 or v_caps_no <> 0 then
    raise exception
      '[FAIL] fixture de autorizacao incorreta (caps admin=%, caps sem capability=%)',
      v_caps, v_caps_no;
  end if;

  raise notice '[PASS] cenario F5-08 P1+P2 aplicado (2 orgs, 30 unidades, 17 periodos, 8 posicoes, 3 colaboradores, 1 evento, capabilities resolvidas)';
end $$;
