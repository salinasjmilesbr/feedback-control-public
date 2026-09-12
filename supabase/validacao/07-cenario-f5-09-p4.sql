-- ============================================================================
-- F5-09 P4: cenario sintetico de validacao — transicoes excepcionais de ciclo
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§6 T4/T5/T6/T7, §8 autorizacao,
-- §10 I7/I8/I11/I12/I19, §11, §12, §13.2/§13.3, §19 P4) + migration
-- `20260918000000_f5_09_cycle_exceptional_transitions.sql`.
--
-- Fixture para `08-validar-f5-09-p4.sql` — ISOLADA dos estados mutados pelos
-- validadores P1/P2/P3 (prefixo proprio `eb`):
--   - duas organizacoes (Alfa-P4 e Beta-P4) com atores distintos:
--     a1 = ator Alfa-P4 com `cycle.manage` + `cycle.cancel` + `cycle.reopen` +
--     `cycle.period.correct`; a2 = ator Alfa-P4 SEM nenhuma capability;
--     a3 = ator Beta-P4 com as MESMAS capabilities no PROPRIO tenant (permite o
--     probe cross-tenant direto); a4 = ator Alfa-P4 com membership DISABLED;
--   - estrutura SOBERANA relacional em Alfa-P4 (unidade, cargo, senioridade, 3
--     posicoes, reporting lines P2->P1 e P3->P1) e 3 colaboradores de base
--     ativos com ocupacao vigente — populacao materializada na ativacao;
--   - colegiado (F3-08) de CADA colaborador avaliado, para que a criacao de
--     avaliacoes pela F5-06 resolva participantes pelo caminho soberano;
--   - colaborador BB1 em Beta-P4 (para os probes cross-tenant);
--   - NENHUM ciclo e criado aqui: todas as transicoes (criar/ativar/encerrar/
--     cancelar/reabrir/corrigir periodo) sao exercitadas pelo validador 08, que
--     tambem injeta as falhas de rollback.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: a trilha `cycle_events` e append-only protegida (P1) e as FKs
--     sao ON DELETE RESTRICT. Reexecucao e NO-OP (guarda abaixo). Para estado
--     limpo use `db reset` (como no CI).
--   - Somente dados ficticios; nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('eba00000-0000-0000-0000-0000000000a1',
                'eba00000-0000-0000-0000-0000000000b1')
) as cenario_f5_09_p4_carregado \gset

\if :cenario_f5_09_p4_carregado
do $$
begin
  raise notice '[PASS] cenario F5-09 P4 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('eba00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-09 P4 Alfa'),
  ('eba00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-09 P4 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades sinteticas (auth.users) + perfis internos
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ebc00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.alfa.f5-09-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('ebc00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sem.cap.f5-09-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('ebc00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.beta.f5-09-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('ebc00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.disabled.f5-09-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('ebc00000-0000-0000-0000-000000000001', 'active'),
  ('ebc00000-0000-0000-0000-000000000002', 'active'),
  ('ebc00000-0000-0000-0000-000000000003', 'active'),
  ('ebc00000-0000-0000-0000-000000000004', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('ebd00000-0000-0000-0000-000000000001', 'ebc00000-0000-0000-0000-000000000001',
   'eba00000-0000-0000-0000-0000000000a1', 'active'),
  ('ebd00000-0000-0000-0000-000000000002', 'ebc00000-0000-0000-0000-000000000002',
   'eba00000-0000-0000-0000-0000000000a1', 'active'),
  ('ebd00000-0000-0000-0000-000000000003', 'ebc00000-0000-0000-0000-000000000003',
   'eba00000-0000-0000-0000-0000000000b1', 'active'),
  ('ebd00000-0000-0000-0000-000000000004', 'ebc00000-0000-0000-0000-000000000004',
   'eba00000-0000-0000-0000-0000000000a1', 'disabled');

-- Roles customizadas com as capabilities EXISTENTES do catalogo usadas pela P4
-- (nenhuma capability nova): `cycle.manage`, `cycle.cancel`, `cycle.reopen` e
-- `cycle.period.correct`.
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('ebf90000-0000-0000-0000-0000000000a1', 'ciclos-p4-alfa', 'active', false,
   'eba00000-0000-0000-0000-0000000000a1'),
  ('ebf90000-0000-0000-0000-0000000000b1', 'ciclos-p4-beta', 'active', false,
   'eba00000-0000-0000-0000-0000000000b1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id in ('ebf90000-0000-0000-0000-0000000000a1',
                 'ebf90000-0000-0000-0000-0000000000b1')
   and c.code in ('cycle.manage', 'cycle.cancel', 'cycle.reopen', 'cycle.period.correct');

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('ebf80000-0000-0000-0000-000000000001', 'ebd00000-0000-0000-0000-000000000001',
   'eba00000-0000-0000-0000-0000000000a1', 'ebf90000-0000-0000-0000-0000000000a1',
   'active', 'ebc00000-0000-0000-0000-000000000001'),
  ('ebf80000-0000-0000-0000-000000000003', 'ebd00000-0000-0000-0000-000000000003',
   'eba00000-0000-0000-0000-0000000000b1', 'ebf90000-0000-0000-0000-0000000000b1',
   'active', 'ebc00000-0000-0000-0000-000000000003');

-- ----------------------------------------------------------------------------
-- 3) Estrutura soberana (F3-02/F3-03/F3-04) — hierarquia RELACIONAL
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('ebe00000-0000-0000-0000-0000000000a1', 'eba00000-0000-0000-0000-0000000000a1',
   'Analista F5-09 P4', 'ANL-F5-09-P4', 'active'),
  ('ebe00000-0000-0000-0000-0000000000b1', 'eba00000-0000-0000-0000-0000000000b1',
   'Analista F5-09 P4 Beta', 'ANL-F5-09-P4-B', 'active');

insert into public.seniority_levels (id, organization_id, name, status) values
  ('ebe70000-0000-0000-0000-0000000000a1', 'eba00000-0000-0000-0000-0000000000a1',
   'Senior F5-09 P4', 'active'),
  ('ebe70000-0000-0000-0000-0000000000b1', 'eba00000-0000-0000-0000-0000000000b1',
   'Senior F5-09 P4 Beta', 'active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('ebf00000-0000-0000-0000-0000000000a1', 'eba00000-0000-0000-0000-0000000000a1',
   'F5-09 P4 Unidade Alfa', '2024-01-01T00:00:00Z'),
  ('ebf00000-0000-0000-0000-0000000000b1', 'eba00000-0000-0000-0000-0000000000b1',
   'F5-09 P4 Unidade Beta', '2024-01-01T00:00:00Z');

insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from) values
  ('ebe10000-0000-0000-0000-000000000001', 'eba00000-0000-0000-0000-0000000000a1',
   'ebf00000-0000-0000-0000-0000000000a1', 'ebe00000-0000-0000-0000-0000000000a1',
   'ebe70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('ebe10000-0000-0000-0000-000000000002', 'eba00000-0000-0000-0000-0000000000a1',
   'ebf00000-0000-0000-0000-0000000000a1', 'ebe00000-0000-0000-0000-0000000000a1',
   'ebe70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('ebe10000-0000-0000-0000-000000000003', 'eba00000-0000-0000-0000-0000000000a1',
   'ebf00000-0000-0000-0000-0000000000a1', 'ebe00000-0000-0000-0000-0000000000a1',
   'ebe70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('ebe10000-0000-0000-0000-0000000000b1', 'eba00000-0000-0000-0000-0000000000b1',
   'ebf00000-0000-0000-0000-0000000000b1', 'ebe00000-0000-0000-0000-0000000000b1',
   'ebe70000-0000-0000-0000-0000000000b1', '2024-01-01T00:00:00Z');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('ebe30000-0000-0000-0000-000000000001', 'eba00000-0000-0000-0000-0000000000a1',
   'ebe10000-0000-0000-0000-000000000002', 'ebe10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P4 (B2 -> B1)', '2024-01-01T00:00:00Z'),
  ('ebe30000-0000-0000-0000-000000000002', 'eba00000-0000-0000-0000-0000000000a1',
   'ebe10000-0000-0000-0000-000000000003', 'ebe10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P4 (B3 -> B1)', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 4) Colaboradores de base (populacao materializada na ativacao)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id, full_name, email, admission_date) values
  ('ebb00000-0000-0000-0000-000000000001', 'eba00000-0000-0000-0000-0000000000a1',
   'Colaborador P4 B1', 'base.b1.f5-09-p4@example.invalid', date '2024-01-01'),
  ('ebb00000-0000-0000-0000-000000000002', 'eba00000-0000-0000-0000-0000000000a1',
   'Colaborador P4 B2', 'base.b2.f5-09-p4@example.invalid', date '2024-01-01'),
  ('ebb00000-0000-0000-0000-000000000003', 'eba00000-0000-0000-0000-0000000000a1',
   'Colaborador P4 B3', 'base.b3.f5-09-p4@example.invalid', date '2024-01-01'),
  ('ebb00000-0000-0000-0000-0000000000b1', 'eba00000-0000-0000-0000-0000000000b1',
   'Colaborador P4 Beta BB1', 'base.bb1.f5-09-p4@example.invalid', date '2024-01-01');

insert into public.collaborator_identifiers
  (collaborator_id, organization_id, business_code, valid_from) values
  ('ebb00000-0000-0000-0000-000000000001', 'eba00000-0000-0000-0000-0000000000a1', 'P4-B1', '2024-01-01T00:00:00Z'),
  ('ebb00000-0000-0000-0000-000000000002', 'eba00000-0000-0000-0000-0000000000a1', 'P4-B2', '2024-01-01T00:00:00Z'),
  ('ebb00000-0000-0000-0000-000000000003', 'eba00000-0000-0000-0000-0000000000a1', 'P4-B3', '2024-01-01T00:00:00Z'),
  ('ebb00000-0000-0000-0000-0000000000b1', 'eba00000-0000-0000-0000-0000000000b1', 'P4-BB1', '2024-01-01T00:00:00Z');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('ebb00000-0000-0000-0000-000000000001', 'active', '2024-01-01T00:00:00Z'),
  ('ebb00000-0000-0000-0000-000000000002', 'active', '2024-01-01T00:00:00Z'),
  ('ebb00000-0000-0000-0000-000000000003', 'active', '2024-01-01T00:00:00Z'),
  ('ebb00000-0000-0000-0000-0000000000b1', 'active', '2024-01-01T00:00:00Z');

insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('ebe20000-0000-0000-0000-000000000001', 'eba00000-0000-0000-0000-0000000000a1',
   'ebb00000-0000-0000-0000-000000000001', 'ebe10000-0000-0000-0000-000000000001',
   'ocupacao F5-09 P4 B1', '2024-01-01T00:00:00Z'),
  ('ebe20000-0000-0000-0000-000000000002', 'eba00000-0000-0000-0000-0000000000a1',
   'ebb00000-0000-0000-0000-000000000002', 'ebe10000-0000-0000-0000-000000000002',
   'ocupacao F5-09 P4 B2', '2024-01-01T00:00:00Z'),
  ('ebe20000-0000-0000-0000-000000000003', 'eba00000-0000-0000-0000-0000000000a1',
   'ebb00000-0000-0000-0000-000000000003', 'ebe10000-0000-0000-0000-000000000003',
   'ocupacao F5-09 P4 B3', '2024-01-01T00:00:00Z'),
  ('ebe20000-0000-0000-0000-0000000000b1', 'eba00000-0000-0000-0000-0000000000b1',
   'ebb00000-0000-0000-0000-0000000000b1', 'ebe10000-0000-0000-0000-0000000000b1',
   'ocupacao F5-09 P4 BB1', '2024-01-01T00:00:00Z');

-- Colegiado (F3-08) de CADA colaborador avaliado em Alfa-P4: e a fonte relacional
-- dos participantes congelados usados por `evaluation_criar` (F5-06).
insert into public.collegiate_configurations
  (id, organization_id, collaborator_id, valid_from) values
  ('ebe40000-0000-0000-0000-000000000001', 'eba00000-0000-0000-0000-0000000000a1',
   'ebb00000-0000-0000-0000-000000000001', '2024-01-01T00:00:00Z'),
  ('ebe40000-0000-0000-0000-000000000002', 'eba00000-0000-0000-0000-0000000000a1',
   'ebb00000-0000-0000-0000-000000000002', '2024-01-01T00:00:00Z'),
  ('ebe40000-0000-0000-0000-000000000003', 'eba00000-0000-0000-0000-0000000000a1',
   'ebb00000-0000-0000-0000-000000000003', '2024-01-01T00:00:00Z');

insert into public.collegiate_configuration_members
  (id, organization_id, configuration_id, member_collaborator_id) values
  ('ebe80000-0000-0000-0000-000000000001', 'eba00000-0000-0000-0000-0000000000a1',
   'ebe40000-0000-0000-0000-000000000001', 'ebb00000-0000-0000-0000-000000000002'),
  ('ebe80000-0000-0000-0000-000000000002', 'eba00000-0000-0000-0000-0000000000a1',
   'ebe40000-0000-0000-0000-000000000002', 'ebb00000-0000-0000-0000-000000000001'),
  ('ebe80000-0000-0000-0000-000000000003', 'eba00000-0000-0000-0000-0000000000a1',
   'ebe40000-0000-0000-0000-000000000003', 'ebb00000-0000-0000-0000-000000000001');

-- ----------------------------------------------------------------------------
-- 5) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_atores   int;
  v_colabs   int;
  v_status   int;
  v_pos      int;
  v_ocup     int;
  v_linhas   int;
  v_coleg    int;
  v_membros  int;
  v_gestor   uuid;
  v_cap      int;
  v_cap_sem  int;
  v_cap_beta int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('eba00000-0000-0000-0000-0000000000a1',
                'eba00000-0000-0000-0000-0000000000b1');
  select count(*) into v_atores from public.user_profiles
   where id::text like 'ebc00000-0000-0000-0000-0000000000%';
  select count(*) into v_colabs from public.collaborators
   where organization_id = 'eba00000-0000-0000-0000-0000000000a1';
  select count(*) into v_status from public.collaborator_status_periods sp
    join public.collaborators c on c.id = sp.collaborator_id
   where c.organization_id = 'eba00000-0000-0000-0000-0000000000a1'
     and sp.status = 'active';
  select count(*) into v_pos from public.organizational_positions
   where organization_id = 'eba00000-0000-0000-0000-0000000000a1';
  select count(*) into v_ocup from public.occupations
   where organization_id = 'eba00000-0000-0000-0000-0000000000a1';
  select count(*) into v_linhas from public.position_reporting_lines
   where organization_id = 'eba00000-0000-0000-0000-0000000000a1';
  select count(*) into v_coleg from public.collegiate_configurations
   where organization_id = 'eba00000-0000-0000-0000-0000000000a1';
  select count(*) into v_membros from public.collegiate_configuration_members
   where organization_id = 'eba00000-0000-0000-0000-0000000000a1';

  if v_orgs <> 2 or v_atores <> 4 or v_colabs <> 3 or v_status <> 3
     or v_pos <> 3 or v_ocup <> 3 or v_linhas <> 2 or v_coleg <> 3 or v_membros <> 3 then
    raise exception
      '[FAIL] cenario F5-09 P4 incompleto (orgs=%, atores=%, colabs=%, status=%, pos=%, ocup=%, linhas=%, coleg=%, membros=%)',
      v_orgs, v_atores, v_colabs, v_status, v_pos, v_ocup, v_linhas, v_coleg, v_membros;
  end if;

  -- A hierarquia existe de fato nas fontes RELACIONAIS: gestor direto de B2 = B1.
  select r.manager_responsible_collaborator_id into v_gestor
    from public.organizacao_resolver_gestor_direto(
      'ebb00000-0000-0000-0000-000000000002', '2025-01-01T00:00:00Z') r
   limit 1;
  if v_gestor is distinct from 'ebb00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] cenario F5-09 P4: gestor direto de B2 deveria ser B1 (recebido %)', v_gestor;
  end if;

  -- Capabilities resolvidas apenas para os atores designados (4 no Alfa, 0 no a2).
  select count(*) into v_cap from public.resolver_capabilities_efetivas(
    'ebc00000-0000-0000-0000-000000000001', 'eba00000-0000-0000-0000-0000000000a1')
   where capability_code in ('cycle.manage', 'cycle.cancel', 'cycle.reopen', 'cycle.period.correct');
  select count(*) into v_cap_sem from public.resolver_capabilities_efetivas(
    'ebc00000-0000-0000-0000-000000000002', 'eba00000-0000-0000-0000-0000000000a1')
   where capability_code in ('cycle.manage', 'cycle.cancel', 'cycle.reopen', 'cycle.period.correct');
  select count(*) into v_cap_beta from public.resolver_capabilities_efetivas(
    'ebc00000-0000-0000-0000-000000000003', 'eba00000-0000-0000-0000-0000000000b1')
   where capability_code in ('cycle.manage', 'cycle.cancel', 'cycle.reopen', 'cycle.period.correct');
  if v_cap <> 4 or v_cap_sem <> 0 or v_cap_beta <> 4 then
    raise exception '[FAIL] cenario F5-09 P4: fixture de capability incorreta (a1=%, a2=%, a3/beta=%)',
      v_cap, v_cap_sem, v_cap_beta;
  end if;

  -- O ator Beta NAO tem capability em Alfa-P4 (insumo dos probes cross-tenant).
  if public.ciclo_ator_valido('ebc00000-0000-0000-0000-000000000003',
                              'eba00000-0000-0000-0000-0000000000a1', 'cycle.cancel') is not false then
    raise exception '[FAIL] cenario F5-09 P4: ator Beta nao deveria ter cycle.cancel em Alfa-P4';
  end if;

  raise notice '[PASS] cenario F5-09 P4: 2 orgs, 4 atores, 3 colaboradores ativos com estrutura e colegiado, capabilities excepcionais apenas nos atores designados';
end $$;

\endif

-- ----------------------------------------------------------------------------
-- 6) Guarda de estado limpo para o validador (uma vez por banco)
-- ----------------------------------------------------------------------------
do $$
declare
  v_ciclos int;
begin
  select count(*) into v_ciclos
    from public.evaluation_cycles
   where organization_id in ('eba00000-0000-0000-0000-0000000000a1',
                             'eba00000-0000-0000-0000-0000000000b1');
  if v_ciclos <> 0 then
    raise exception
      '[FAIL] estado sujo: as organizacoes da fixture F5-09 P4 ja possuem % ciclo(s) — execute `supabase db reset` antes de reexecutar o cenario/validador da P4 (a trilha de ciclos e append-only por contrato)',
      v_ciclos;
  end if;
  raise notice '[PASS] cenario F5-09 P4: organizacoes da fixture sem ciclos (prontas para o validador 08)';
end $$;
