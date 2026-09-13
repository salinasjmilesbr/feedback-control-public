-- ============================================================================
-- F5-09 P9: cenario sintetico da VALIDACAO INTEGRADA de ciclos soberanos
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§6 maquina de estados, §8 autorizacao,
-- §9 RLS de leitura, §10 integridade, §11 concorrencia/idempotencia, §12
-- auditoria, §13.2 assinaturas, §19 P9) + migrations P1..P7 da F5-09.
--
-- Fixture para `15-validar-f5-09-p9.sql` — ISOLADA (prefixo `ed`) de TODAS as
-- demais fixtures das fases P1..P8 e das Fases F2..F5, com tres organizacoes:
--
--   eda...a1 Alfa-P9  — tenant principal: gestor, leitor e ator revogavel;
--   eda...b1 Beta-P9  — tenant alheio: permite as provas de cross-tenant/IDOR
--                       (leitura por RLS E mutacao pela RPC);
--   eda...c1 Gama-P9  — tenant RESERVADO aos validadores de CONCORRENCIA REAL de
--                       outro agente (arquivos 16/17/18). Aqui apenas a org e o
--                       ator gestor-gama sao criados: NENHUM ciclo, nenhum
--                       colaborador, nenhum dado mutavel.
--
-- Identidades (auth.users.id = user_profiles.id) e memberships ATIVAS:
--   edc...0001 gestor-alfa    — Alfa, cycle.read + cycle.manage + cycle.cancel +
--                               cycle.reopen + cycle.period.correct
--                               (+ org.structure.manage, ver nota abaixo);
--   edc...0002 leitor-alfa    — Alfa, SOMENTE cycle.read (prova de que leitura e
--                               mutacao sao decisões separadas);
--   edc...0003 revogavel-alfa — Alfa, as 5 capabilities de ciclo (usado na prova
--                               de REVOGAÇÃO TEMPORAL DE MEMBERSHIP da P9);
--   edc...0004 gestor-beta    — Beta, cycle.read + cycle.manage;
--   edc...0005 fantasma       — JWT valido SEM profile e SEM membership;
--   edc...0006 gestor-gama    — Gama, cycle.read + cycle.manage.
--
-- NOTA sobre `org.structure.manage` no ator gestor-alfa: essa capability NAO e
-- usada por nenhuma RPC `ciclo_*`. Ela existe para a prova A3 (§12) exigida pela
-- P9 — "movimentacao posterior de posicao/gestor NAO altera o snapshot do ciclo e
-- NAO gera trilha nova" — que precisa executar uma movimentacao de estrutura pelo
-- caminho SOBERANO (`estrutura_ocupacao_definir` / `estrutura_reporting_definir`,
-- F5-07) no MESMO ator das operacoes de ciclo. Sem ela a prova A3 so poderia ser
-- simulada por escrita direta (o que nao provaria nada).
--
-- A fixture NAO cria CICLOS: os ciclos sao criados pelos VALIDADORES pelo caminho
-- legitimo (`ciclo_criar` / `ciclo_ativar`), como em `08-validar-f5-09-p4.sql`.
-- Ela cria apenas a ESTRUTURA SOBERANA (unidade, funcao, senioridade, posicoes,
-- reporting lines P2->P1 e P3->P1, colaboradores ativos com ocupacao vigente e
-- colegiado F3-08 de cada avaliado) suficiente para que `ciclo_ativar`
-- materialize a populacao inicial (F3-08/F3-09) e para que `evaluation_criar`
-- (F5-06) resolva participantes pelo caminho soberano.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: a trilha `cycle_events` e append-only protegida (P1) e as FKs
--     sao ON DELETE RESTRICT. Reexecucao e NO-OP (guarda abaixo). Para estado
--     limpo use `db reset` (como no CI): o validador 15 REVOGA membership e
--     capability de forma irreversivel de proposito, portanto ele so pode rodar
--     UMA vez por banco recem-resetado. Os validadores de concorrencia 16/17/18
--     usam SOMENTE a organizacao reservada Gama-P9 + o ator gestor-gama (nunca
--     tocados pelo validador 15): por isso o validador 15 deve rodar DEPOIS
--     deles, ou em um banco recem-resetado.
--   - Somente dados ficticios (`@example.invalid`); nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('eda00000-0000-0000-0000-0000000000a1',
                'eda00000-0000-0000-0000-0000000000b1',
                'eda00000-0000-0000-0000-0000000000c1')
) as cenario_f5_09_p9_carregado \gset

\if :cenario_f5_09_p9_carregado
do $$
begin
  raise notice '[PASS] cenario F5-09 P9 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('eda00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-09 P9 Alfa'),
  ('eda00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-09 P9 Beta'),
  ('eda00000-0000-0000-0000-0000000000c1', 'Org Sintetica F5-09 P9 Gama');

-- ----------------------------------------------------------------------------
-- 2) Identidades sinteticas (auth.users) + perfis internos
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('edc00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.alfa.f5-09-p9@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('edc00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'leitor.alfa.f5-09-p9@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('edc00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'revogavel.alfa.f5-09-p9@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('edc00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.beta.f5-09-p9@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('edc00000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.gama.f5-09-p9@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

-- fantasma: JWT VALIDO sem profile e sem membership (nenhum vinculo soberano).
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('edc00000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'fantasma.f5-09-p9@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('edc00000-0000-0000-0000-000000000001', 'active'),
  ('edc00000-0000-0000-0000-000000000002', 'active'),
  ('edc00000-0000-0000-0000-000000000003', 'active'),
  ('edc00000-0000-0000-0000-000000000004', 'active'),
  ('edc00000-0000-0000-0000-000000000006', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('edd00000-0000-0000-0000-000000000001', 'edc00000-0000-0000-0000-000000000001',
   'eda00000-0000-0000-0000-0000000000a1', 'active'),
  ('edd00000-0000-0000-0000-000000000002', 'edc00000-0000-0000-0000-000000000002',
   'eda00000-0000-0000-0000-0000000000a1', 'active'),
  ('edd00000-0000-0000-0000-000000000003', 'edc00000-0000-0000-0000-000000000003',
   'eda00000-0000-0000-0000-0000000000a1', 'active'),
  ('edd00000-0000-0000-0000-000000000004', 'edc00000-0000-0000-0000-000000000004',
   'eda00000-0000-0000-0000-0000000000b1', 'active'),
  ('edd00000-0000-0000-0000-000000000006', 'edc00000-0000-0000-0000-000000000006',
   'eda00000-0000-0000-0000-0000000000c1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Autorizacao das identidades: roles CUSTOMIZADAS (nenhuma capability nova,
--    nenhuma role de sistema alterada) com as capabilities EXISTENTES do catalogo
--    F5-04 usadas pela F5-09: cycle.read, cycle.manage, cycle.cancel,
--    cycle.reopen, cycle.period.correct (+ org.structure.manage apenas no
--    gestor-alfa, exclusivamente para a prova A3 de movimentacao — ver header).
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('edf90000-0000-0000-0000-0000000000a1', 'ciclos-p9-alfa-gestor', 'active', false,
   'eda00000-0000-0000-0000-0000000000a1'),
  ('edf90000-0000-0000-0000-0000000000a2', 'ciclos-p9-alfa-leitor', 'active', false,
   'eda00000-0000-0000-0000-0000000000a1'),
  ('edf90000-0000-0000-0000-0000000000a3', 'ciclos-p9-alfa-revogavel', 'active', false,
   'eda00000-0000-0000-0000-0000000000a1'),
  ('edf90000-0000-0000-0000-0000000000b1', 'ciclos-p9-beta-gestor', 'active', false,
   'eda00000-0000-0000-0000-0000000000b1'),
  ('edf90000-0000-0000-0000-0000000000c1', 'ciclos-p9-gama-gestor', 'active', false,
   'eda00000-0000-0000-0000-0000000000c1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id in ('edf90000-0000-0000-0000-0000000000a1',
                 'edf90000-0000-0000-0000-0000000000a3',
                 'edf90000-0000-0000-0000-0000000000b1',
                 'edf90000-0000-0000-0000-0000000000c1')
   and c.code in ('cycle.read', 'cycle.manage', 'cycle.cancel', 'cycle.reopen',
                  'cycle.period.correct');

-- Somente o gestor-alfa recebe `org.structure.manage` (prova A3 da P9).
insert into public.access_role_capabilities (access_role_id, capability_id)
select 'edf90000-0000-0000-0000-0000000000a1', c.id
  from public.capabilities c
 where c.code = 'org.structure.manage';

-- O leitor-alfa tem SOMENTE `cycle.read` (leitura e mutacao sao decisões separadas).
insert into public.access_role_capabilities (access_role_id, capability_id)
select 'edf90000-0000-0000-0000-0000000000a2', c.id
  from public.capabilities c
 where c.code = 'cycle.read';

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('edf80000-0000-0000-0000-000000000001', 'edd00000-0000-0000-0000-000000000001',
   'eda00000-0000-0000-0000-0000000000a1', 'edf90000-0000-0000-0000-0000000000a1',
   'active', 'edc00000-0000-0000-0000-000000000001'),
  ('edf80000-0000-0000-0000-000000000002', 'edd00000-0000-0000-0000-000000000002',
   'eda00000-0000-0000-0000-0000000000a1', 'edf90000-0000-0000-0000-0000000000a2',
   'active', 'edc00000-0000-0000-0000-000000000001'),
  ('edf80000-0000-0000-0000-000000000003', 'edd00000-0000-0000-0000-000000000003',
   'eda00000-0000-0000-0000-0000000000a1', 'edf90000-0000-0000-0000-0000000000a3',
   'active', 'edc00000-0000-0000-0000-000000000001'),
  ('edf80000-0000-0000-0000-000000000004', 'edd00000-0000-0000-0000-000000000004',
   'eda00000-0000-0000-0000-0000000000b1', 'edf90000-0000-0000-0000-0000000000b1',
   'active', 'edc00000-0000-0000-0000-000000000004'),
  ('edf80000-0000-0000-0000-000000000006', 'edd00000-0000-0000-0000-000000000006',
   'eda00000-0000-0000-0000-0000000000c1', 'edf90000-0000-0000-0000-0000000000c1',
   'active', 'edc00000-0000-0000-0000-000000000006');

-- ----------------------------------------------------------------------------
-- 4) Estrutura soberana (F3-02/F3-03/F3-04) — hierarquia RELACIONAL
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('ede00000-0000-0000-0000-0000000000a1', 'eda00000-0000-0000-0000-0000000000a1',
   'Analista F5-09 P9', 'ANL-F5-09-P9', 'active'),
  ('ede00000-0000-0000-0000-0000000000b1', 'eda00000-0000-0000-0000-0000000000b1',
   'Analista F5-09 P9 Beta', 'ANL-F5-09-P9-B', 'active');

insert into public.seniority_levels (id, organization_id, name, status) values
  ('ede70000-0000-0000-0000-0000000000a1', 'eda00000-0000-0000-0000-0000000000a1',
   'Senior F5-09 P9', 'active'),
  ('ede70000-0000-0000-0000-0000000000b1', 'eda00000-0000-0000-0000-0000000000b1',
   'Senior F5-09 P9 Beta', 'active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('edf00000-0000-0000-0000-0000000000a1', 'eda00000-0000-0000-0000-0000000000a1',
   'F5-09 P9 Unidade Alfa', '2024-01-01T00:00:00Z'),
  ('edf00000-0000-0000-0000-0000000000b1', 'eda00000-0000-0000-0000-0000000000b1',
   'F5-09 P9 Unidade Beta', '2024-01-01T00:00:00Z');

insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from) values
  ('ede10000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1',
   'edf00000-0000-0000-0000-0000000000a1', 'ede00000-0000-0000-0000-0000000000a1',
   'ede70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('ede10000-0000-0000-0000-000000000002', 'eda00000-0000-0000-0000-0000000000a1',
   'edf00000-0000-0000-0000-0000000000a1', 'ede00000-0000-0000-0000-0000000000a1',
   'ede70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('ede10000-0000-0000-0000-000000000003', 'eda00000-0000-0000-0000-0000000000a1',
   'edf00000-0000-0000-0000-0000000000a1', 'ede00000-0000-0000-0000-0000000000a1',
   'ede70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('ede10000-0000-0000-0000-000000000004', 'eda00000-0000-0000-0000-0000000000a1',
   'edf00000-0000-0000-0000-0000000000a1', 'ede00000-0000-0000-0000-0000000000a1',
   'ede70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  -- P5 (Alfa): posicao do colaborador ADMITIDO pela prova de admissao da P9. Ela
  -- existe para que P4 permaneca LIVRE para a prova A3 (movimentacao de B2 P2->P4)
  -- sem conflito de ocupante vigente da F5-07.
  ('ede10000-0000-0000-0000-000000000005', 'eda00000-0000-0000-0000-0000000000a1',
   'edf00000-0000-0000-0000-0000000000a1', 'ede00000-0000-0000-0000-0000000000a1',
   'ede70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('ede10000-0000-0000-0000-0000000000b1', 'eda00000-0000-0000-0000-0000000000b1',
   'edf00000-0000-0000-0000-0000000000b1', 'ede00000-0000-0000-0000-0000000000b1',
   'ede70000-0000-0000-0000-0000000000b1', '2024-01-01T00:00:00Z');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('ede30000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1',
   'ede10000-0000-0000-0000-000000000002', 'ede10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P9 (P2 -> P1)', '2024-01-01T00:00:00Z'),
  ('ede30000-0000-0000-0000-000000000002', 'eda00000-0000-0000-0000-0000000000a1',
   'ede10000-0000-0000-0000-000000000003', 'ede10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P9 (P3 -> P1)', '2024-01-01T00:00:00Z'),
  -- P4 -> P1: a prova de admissao do §13 exige evidencia RELACIONAL de superior
  -- (D18 — hierarquia nunca textual); sem esta linha o helper de elegibilidade
  -- devolve `superior_position_id = null` e a prova A1 nao teria como passar.
  ('ede30000-0000-0000-0000-000000000003', 'eda00000-0000-0000-0000-0000000000a1',
   'ede10000-0000-0000-0000-000000000004', 'ede10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P9 (P4 -> P1)', '2024-01-01T00:00:00Z'),
  ('ede30000-0000-0000-0000-000000000004', 'eda00000-0000-0000-0000-0000000000a1',
   'ede10000-0000-0000-0000-000000000005', 'ede10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P9 (P5 -> P1)', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 5) Colaboradores de base (populacao materializada na ativacao)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id, full_name, email, admission_date) values
  ('edb00000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1',
   'Colaborador P9 B1', 'base.b1.f5-09-p9@example.invalid', date '2024-01-01'),
  ('edb00000-0000-0000-0000-000000000002', 'eda00000-0000-0000-0000-0000000000a1',
   'Colaborador P9 B2', 'base.b2.f5-09-p9@example.invalid', date '2024-01-01'),
  ('edb00000-0000-0000-0000-000000000003', 'eda00000-0000-0000-0000-0000000000a1',
   'Colaborador P9 B3', 'base.b3.f5-09-p9@example.invalid', date '2024-01-01'),
  ('edb00000-0000-0000-0000-0000000000b1', 'eda00000-0000-0000-0000-0000000000b1',
   'Colaborador P9 Beta BB1', 'base.bb1.f5-09-p9@example.invalid', date '2024-01-01');

insert into public.collaborator_identifiers
  (collaborator_id, organization_id, business_code, valid_from) values
  ('edb00000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1', 'P9-B1', '2024-01-01T00:00:00Z'),
  ('edb00000-0000-0000-0000-000000000002', 'eda00000-0000-0000-0000-0000000000a1', 'P9-B2', '2024-01-01T00:00:00Z'),
  ('edb00000-0000-0000-0000-000000000003', 'eda00000-0000-0000-0000-0000000000a1', 'P9-B3', '2024-01-01T00:00:00Z'),
  ('edb00000-0000-0000-0000-0000000000b1', 'eda00000-0000-0000-0000-0000000000b1', 'P9-BB1', '2024-01-01T00:00:00Z');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('edb00000-0000-0000-0000-000000000001', 'active', '2024-01-01T00:00:00Z'),
  ('edb00000-0000-0000-0000-000000000002', 'active', '2024-01-01T00:00:00Z'),
  ('edb00000-0000-0000-0000-000000000003', 'active', '2024-01-01T00:00:00Z'),
  ('edb00000-0000-0000-0000-0000000000b1', 'active', '2024-01-01T00:00:00Z');

insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('ede20000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1',
   'edb00000-0000-0000-0000-000000000001', 'ede10000-0000-0000-0000-000000000001',
   'ocupacao F5-09 P9 B1', '2024-01-01T00:00:00Z'),
  ('ede20000-0000-0000-0000-000000000002', 'eda00000-0000-0000-0000-0000000000a1',
   'edb00000-0000-0000-0000-000000000002', 'ede10000-0000-0000-0000-000000000002',
   'ocupacao F5-09 P9 B2', '2024-01-01T00:00:00Z'),
  ('ede20000-0000-0000-0000-000000000003', 'eda00000-0000-0000-0000-0000000000a1',
   'edb00000-0000-0000-0000-000000000003', 'ede10000-0000-0000-0000-000000000003',
   'ocupacao F5-09 P9 B3', '2024-01-01T00:00:00Z'),
  ('ede20000-0000-0000-0000-0000000000b1', 'eda00000-0000-0000-0000-0000000000b1',
   'edb00000-0000-0000-0000-0000000000b1', 'ede10000-0000-0000-0000-0000000000b1',
   'ocupacao F5-09 P9 BB1', '2024-01-01T00:00:00Z');

-- Colegiado (F3-08) de CADA colaborador avaliado do Alfa: e a fonte relacional
-- dos participantes congelados usados por `evaluation_criar` (F5-06).
insert into public.collegiate_configurations
  (id, organization_id, collaborator_id, valid_from) values
  ('ede40000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1',
   'edb00000-0000-0000-0000-000000000001', '2024-01-01T00:00:00Z'),
  ('ede40000-0000-0000-0000-000000000002', 'eda00000-0000-0000-0000-0000000000a1',
   'edb00000-0000-0000-0000-000000000002', '2024-01-01T00:00:00Z'),
  ('ede40000-0000-0000-0000-000000000003', 'eda00000-0000-0000-0000-0000000000a1',
   'edb00000-0000-0000-0000-000000000003', '2024-01-01T00:00:00Z');

insert into public.collegiate_configuration_members
  (id, organization_id, configuration_id, member_collaborator_id) values
  ('ede80000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1',
   'ede40000-0000-0000-0000-000000000001', 'edb00000-0000-0000-0000-000000000002'),
  ('ede80000-0000-0000-0000-000000000002', 'eda00000-0000-0000-0000-0000000000a1',
   'ede40000-0000-0000-0000-000000000002', 'edb00000-0000-0000-0000-000000000001'),
  ('ede80000-0000-0000-0000-000000000003', 'eda00000-0000-0000-0000-0000000000a1',
   'ede40000-0000-0000-0000-000000000003', 'edb00000-0000-0000-0000-000000000001');

-- ----------------------------------------------------------------------------
-- 6) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_atores   int;
  v_memb     int;
  v_roles    int;
  v_rcaps    int;
  v_assign   int;
  v_colabs   int;
  v_status   int;
  v_pos      int;
  v_ocup     int;
  v_linhas   int;
  v_coleg    int;
  v_membros  int;
  v_gestor   uuid;
  v_cap_a1   int;
  v_cap_le   int;
  v_cap_gama int;
  v_struct   int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('eda00000-0000-0000-0000-0000000000a1',
                'eda00000-0000-0000-0000-0000000000b1',
                'eda00000-0000-0000-0000-0000000000c1');
  select count(*) into v_atores from public.user_profiles
   where id::text like 'edc00000-0000-0000-0000-0000000000%';
  select count(*) into v_memb from public.user_organization_memberships
   where id::text like 'edd00000-0000-0000-0000-0000000000%';
  select count(*) into v_roles from public.access_roles
   where id::text like 'edf90000-0000-0000-0000-0000000000%';
  select count(*) into v_rcaps from public.access_role_capabilities
   where access_role_id::text like 'edf90000-0000-0000-0000-0000000000%';
  select count(*) into v_assign from public.membership_access_role_assignments
   where id::text like 'edf80000-0000-0000-0000-0000000000%';
  select count(*) into v_colabs from public.collaborators
   where organization_id = 'eda00000-0000-0000-0000-0000000000a1';
  select count(*) into v_status from public.collaborator_status_periods sp
    join public.collaborators c on c.id = sp.collaborator_id
   where c.organization_id = 'eda00000-0000-0000-0000-0000000000a1'
     and sp.status = 'active';
  select count(*) into v_pos from public.organizational_positions
   where organization_id = 'eda00000-0000-0000-0000-0000000000a1';
  select count(*) into v_ocup from public.occupations
   where organization_id = 'eda00000-0000-0000-0000-0000000000a1';
  select count(*) into v_linhas from public.position_reporting_lines
   where organization_id = 'eda00000-0000-0000-0000-0000000000a1';
  select count(*) into v_coleg from public.collegiate_configurations
   where organization_id = 'eda00000-0000-0000-0000-0000000000a1';
  select count(*) into v_membros from public.collegiate_configuration_members
   where organization_id = 'eda00000-0000-0000-0000-0000000000a1';

  -- 4 roles de ciclo (5 capabilities cada = 20) + org.structure.manage no
  -- gestor-alfa + a role somente-leitura do leitor-alfa = 22 relacoes role x capability.
  if v_orgs <> 3 or v_atores <> 5 or v_memb <> 5 or v_roles <> 5
     or v_rcaps <> 22 or v_assign <> 5
     or v_colabs <> 3 or v_status <> 3 or v_pos <> 5 or v_ocup <> 3
     or v_linhas <> 4 or v_coleg <> 3 or v_membros <> 3 then
    raise exception
      '[FAIL] cenario F5-09 P9 incompleto (orgs=%, perfis=%, memberships=%, roles=%, role_caps=%, atribuicoes=%, colabs=%, status=%, pos=%, ocup=%, linhas=%, coleg=%, membros=%)',
      v_orgs, v_atores, v_memb, v_roles, v_rcaps, v_assign,
      v_colabs, v_status, v_pos, v_ocup, v_linhas, v_coleg, v_membros;
  end if;

  -- O ator fantasma NAO tem profile nem membership (prova de JWT sem vinculo).
  if exists (select 1 from public.user_profiles
              where id = 'edc00000-0000-0000-0000-000000000005')
     or exists (select 1 from public.user_organization_memberships
                 where user_profile_id = 'edc00000-0000-0000-0000-000000000005') then
    raise exception '[FAIL] cenario F5-09 P9: fantasma nao deveria ter profile/membership';
  end if;

  -- A hierarquia existe de fato nas fontes RELACIONAIS: gestor direto de B2 = B1.
  select r.manager_responsible_collaborator_id into v_gestor
    from public.organizacao_resolver_gestor_direto(
      'edb00000-0000-0000-0000-000000000002', '2025-01-01T00:00:00Z') r
   limit 1;
  if v_gestor is distinct from 'edb00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] cenario F5-09 P9: gestor direto de B2 deveria ser B1 (recebido %)', v_gestor;
  end if;

  -- Capabilities resolvidas: gestor-alfa com as 5 de ciclo + org.structure.manage,
  -- leitor-alfa com 1 (somente leitura), gestor-gama com as 5.
  select count(*) into v_cap_a1 from public.resolver_capabilities_efetivas(
    'edc00000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1')
   where capability_code in ('cycle.read', 'cycle.manage', 'cycle.cancel',
                             'cycle.reopen', 'cycle.period.correct');
  select count(*) into v_struct from public.resolver_capabilities_efetivas(
    'edc00000-0000-0000-0000-000000000001', 'eda00000-0000-0000-0000-0000000000a1')
   where capability_code = 'org.structure.manage';
  select count(*) into v_cap_le from public.resolver_capabilities_efetivas(
    'edc00000-0000-0000-0000-000000000002', 'eda00000-0000-0000-0000-0000000000a1')
   where capability_code like 'cycle.%';
  select count(*) into v_cap_gama from public.resolver_capabilities_efetivas(
    'edc00000-0000-0000-0000-000000000006', 'eda00000-0000-0000-0000-0000000000c1')
   where capability_code in ('cycle.read', 'cycle.manage');
  if v_cap_a1 <> 5 or v_struct <> 1 or v_cap_le <> 1 or v_cap_gama <> 2 then
    raise exception '[FAIL] cenario F5-09 P9: fixture de capability incorreta (a1=%, estrutura=%, leitor=%, gama=%)',
      v_cap_a1, v_struct, v_cap_le, v_cap_gama;
  end if;
  if public.ciclo_ator_valido('edc00000-0000-0000-0000-000000000002',
                              'eda00000-0000-0000-0000-0000000000a1', 'cycle.manage') is not false then
    raise exception '[FAIL] cenario F5-09 P9: leitor-alfa nao deveria ter cycle.manage';
  end if;
  if public.ciclo_ator_valido('edc00000-0000-0000-0000-000000000001',
                              'eda00000-0000-0000-0000-0000000000b1', 'cycle.manage') is not false then
    raise exception '[FAIL] cenario F5-09 P9: gestor-alfa nao deveria ter capability em Beta';
  end if;

  raise notice '[PASS] cenario F5-09 P9: 3 orgs (Alfa/Beta/Gama), 5 perfis, 5 memberships ativas, 3 colaboradores ativos com estrutura e colegiado, capabilities apenas nos atores designados e fantasma sem vinculo';
end $$;

\endif

-- ----------------------------------------------------------------------------
-- 7) Guarda de estado limpo para o validador (uma vez por banco)
-- ----------------------------------------------------------------------------
do $$
declare
  v_ciclos int;
  v_gama   int;
begin
  select count(*) into v_ciclos from public.evaluation_cycles
   where organization_id in ('eda00000-0000-0000-0000-0000000000a1',
                             'eda00000-0000-0000-0000-0000000000b1');
  if v_ciclos <> 0 then
    raise exception
      '[FAIL] estado sujo: as organizacoes Alfa/Beta da fixture F5-09 P9 ja possuem % ciclo(s) — execute `supabase db reset` antes de reexecutar o cenario/validador da P9 (a trilha de ciclos e append-only por contrato e o validador 15 revoga membership/capability de forma irreversivel)',
      v_ciclos;
  end if;

  -- Gama permanece intocada (reservada aos validadores de concorrencia 16/17/18).
  select count(*) into v_gama from public.evaluation_cycles
   where organization_id = 'eda00000-0000-0000-0000-0000000000c1';
  if v_gama <> 0 then
    raise exception '[FAIL] estado sujo: a organizacao Gama-P9 (reservada) ja possui % ciclo(s)', v_gama;
  end if;

  -- O validador 15 desabilita a membership do revogavel-alfa e remove o grant de
  -- cycle.manage do gestor-alfa: se qualquer um dos dois ja estiver alterado, o
  -- banco esta no estado pos-validador e exige `db reset`.
  if not exists (
    select 1 from public.user_organization_memberships
     where id = 'edd00000-0000-0000-0000-000000000003' and status = 'active'
  ) then
    raise exception '[FAIL] estado sujo: membership do revogavel-alfa nao esta ATIVA — execute `supabase db reset` (o validador 15 desabilita essa membership de proposito)';
  end if;
  if not exists (
    select 1
      from public.access_role_capabilities rc
      join public.capabilities c on c.id = rc.capability_id
     where rc.access_role_id = 'edf90000-0000-0000-0000-0000000000a1'
       and c.code = 'cycle.manage'
  ) then
    raise exception '[FAIL] estado sujo: o grant de cycle.manage do gestor-alfa nao existe mais — execute `supabase db reset` (o validador 15 revoga esse grant de proposito)';
  end if;

  raise notice '[PASS] cenario F5-09 P9: organizacoes Alfa/Beta/Gama sem ciclos, membership e capability do cenario intactas (prontas para o validador 15)';
end $$;
