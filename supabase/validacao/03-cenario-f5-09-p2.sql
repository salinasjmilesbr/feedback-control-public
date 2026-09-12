-- ============================================================================
-- F5-09 P2: cenario sintetico de validacao — RPCs de gestao de ciclo
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§6 T0–T3, §8, §10, §11, §12, §13.2,
-- §13.3, §19 P2) + migration `20260916000000_f5_09_cycle_rpc.sql`.
--
-- Fixture para `04-validar-f5-09-p2.sql`:
--   - duas organizacoes (Alfa e Beta F5-09 P2) com atores distintos:
--     a1 = ator Alfa COM `cycle.manage`; a2 = ator Alfa SEM assignment (sem
--     capability); a3 = ator Beta (cross-tenant); a4 = ator Alfa com membership
--     DISABLED;
--   - estrutura SOBERANA relacional em Alfa (unidade, cargo, posicoes,
--     reporting line e ocupacoes) para provar que a hierarquia da materializacao
--     vem de F3-04/F3-07/F3-08 — nunca de cargo/texto/payload;
--   - colaboradores com identificador humano e periodo de status `active`
--     (F3-01/F5-07), incluindo um colaborador SEM ocupacao (tolerado pela F3-08);
--   - colegiado (F3-08) do colaborador AVALIADO c3 com o membro c2.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: a trilha `cycle_events` e append-only protegida no banco
--     (DELETE/TRUNCATE negados por trigger, P1) e as FKs da trilha sao ON DELETE
--     RESTRICT — o cenario NAO pode ser apagado e recriado. Reexecucao e NO-OP
--     (guarda abaixo). Para um estado limpo use `db reset` (como no CI).
--   - Nenhuma RPC de ciclo e chamada aqui: este arquivo so cria a FIXTURE; as
--     mutacoes de ciclo sao exercitadas pelo validador 04.
--   - Somente dados ficticios; nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('e9a00000-0000-0000-0000-0000000000a1',
                'e9a00000-0000-0000-0000-0000000000b1')
) as cenario_f5_09_p2_carregado \gset

\if :cenario_f5_09_p2_carregado
do $$
begin
  raise notice '[PASS] cenario F5-09 P2 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('e9a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-09 P2 Alfa'),
  ('e9a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-09 P2 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades sinteticas (auth.users) + perfis internos
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('e9c00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.alfa.f5-09-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e9c00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sem.cap.f5-09-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e9c00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.beta.f5-09-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e9c00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.disabled.f5-09-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('e9c00000-0000-0000-0000-000000000001', 'active'),
  ('e9c00000-0000-0000-0000-000000000002', 'active'),
  ('e9c00000-0000-0000-0000-000000000003', 'active'),
  ('e9c00000-0000-0000-0000-000000000004', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('e9d00000-0000-0000-0000-000000000001', 'e9c00000-0000-0000-0000-000000000001',
   'e9a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e9d00000-0000-0000-0000-000000000002', 'e9c00000-0000-0000-0000-000000000002',
   'e9a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e9d00000-0000-0000-0000-0000000000b1', 'e9c00000-0000-0000-0000-000000000003',
   'e9a00000-0000-0000-0000-0000000000b1', 'active'),
  ('e9d00000-0000-0000-0000-000000000004', 'e9c00000-0000-0000-0000-000000000004',
   'e9a00000-0000-0000-0000-0000000000a1', 'disabled');

-- Role customizada de Alfa com `cycle.manage` (capability existente do catalogo;
-- nenhuma capability nova) + assignment ativo para o ator a1.
insert into public.access_roles (id, name, status, is_system, organization_id)
values ('e9f90000-0000-0000-0000-0000000000a1', 'ciclos-p2-alfa', 'active', false,
        'e9a00000-0000-0000-0000-0000000000a1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'e9f90000-0000-0000-0000-0000000000a1'
   and c.code = 'cycle.manage';

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('e9f80000-0000-0000-0000-000000000001', 'e9d00000-0000-0000-0000-000000000001',
   'e9a00000-0000-0000-0000-0000000000a1', 'e9f90000-0000-0000-0000-0000000000a1',
   'active', 'e9c00000-0000-0000-0000-000000000001');

-- ----------------------------------------------------------------------------
-- 3) Estrutura soberana (F3-02/F3-03/F3-04) — hierarquia RELACIONAL
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('e9e00000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1',
   'Analista F5-09 P2', 'ANL-F5-09-P2', 'active');

insert into public.seniority_levels (id, organization_id, name, status) values
  ('e9e70000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1',
   'Senior F5-09 P2', 'active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('e9f00000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1',
   'F5-09 P2 Unidade', '2024-01-01T00:00:00Z');

insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from) values
  ('e9e10000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9f00000-0000-0000-0000-000000000001', 'e9e00000-0000-0000-0000-000000000001',
   'e9e70000-0000-0000-0000-000000000001', '2024-01-01T00:00:00Z'),
  ('e9e10000-0000-0000-0000-000000000002', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9f00000-0000-0000-0000-000000000001', 'e9e00000-0000-0000-0000-000000000001',
   'e9e70000-0000-0000-0000-000000000001', '2024-01-01T00:00:00Z'),
  ('e9e10000-0000-0000-0000-000000000003', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9f00000-0000-0000-0000-000000000001', 'e9e00000-0000-0000-0000-000000000001',
   'e9e70000-0000-0000-0000-000000000001', '2024-01-01T00:00:00Z');

-- P1 (subordinada) -> P2 (gestor). P3 fica SEM superior (prova que a hierarquia
-- nao e inventada por cargo/texto).
insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('e9e30000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9e10000-0000-0000-0000-000000000001', 'e9e10000-0000-0000-0000-000000000002',
   'reporting line F5-09 P2', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 4) Colaboradores (UUID canonico) — identificador humano + status `active`
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('e9b00000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1'),
  ('e9b00000-0000-0000-0000-000000000002', 'e9a00000-0000-0000-0000-0000000000a1'),
  ('e9b00000-0000-0000-0000-000000000003', 'e9a00000-0000-0000-0000-0000000000a1'),
  ('e9b00000-0000-0000-0000-000000000004', 'e9a00000-0000-0000-0000-0000000000a1');

insert into public.collaborator_identifiers
  (collaborator_id, organization_id, business_code, valid_from) values
  ('e9b00000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1', 91001, '2024-01-01T00:00:00Z'),
  ('e9b00000-0000-0000-0000-000000000002', 'e9a00000-0000-0000-0000-0000000000a1', 91002, '2024-01-01T00:00:00Z'),
  ('e9b00000-0000-0000-0000-000000000003', 'e9a00000-0000-0000-0000-0000000000a1', 91003, '2024-01-01T00:00:00Z'),
  ('e9b00000-0000-0000-0000-000000000004', 'e9a00000-0000-0000-0000-0000000000a1', 91004, '2024-01-01T00:00:00Z');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('e9b00000-0000-0000-0000-000000000001', 'active', '2024-01-01T00:00:00Z'),
  ('e9b00000-0000-0000-0000-000000000002', 'active', '2024-01-01T00:00:00Z'),
  ('e9b00000-0000-0000-0000-000000000003', 'active', '2024-01-01T00:00:00Z'),
  ('e9b00000-0000-0000-0000-000000000004', 'active', '2024-01-01T00:00:00Z');

-- Ocupacoes: c1 em P1, c2 em P2, c3 em P3. c4 fica SEM ocupacao (a F3-08 tolera:
-- o snapshot existe, sem posicao — prova que a materializacao nao inventa dado).
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('e9e20000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9b00000-0000-0000-0000-000000000001', 'e9e10000-0000-0000-0000-000000000001',
   'ocupacao F5-09 P2', '2024-01-01T00:00:00Z'),
  ('e9e20000-0000-0000-0000-000000000002', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9b00000-0000-0000-0000-000000000002', 'e9e10000-0000-0000-0000-000000000002',
   'ocupacao F5-09 P2', '2024-01-01T00:00:00Z'),
  ('e9e20000-0000-0000-0000-000000000003', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9b00000-0000-0000-0000-000000000003', 'e9e10000-0000-0000-0000-000000000003',
   'ocupacao F5-09 P2', '2024-01-01T00:00:00Z');

-- Colegiado (F3-08) do AVALIADO c3: membro c2. E a fonte relacional do
-- participante COLEGIADO congelado no ciclo.
insert into public.collegiate_configurations
  (id, organization_id, collaborator_id, valid_from) values
  ('e9e40000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9b00000-0000-0000-0000-000000000003', '2024-01-01T00:00:00Z');

insert into public.collegiate_configuration_members
  (id, organization_id, configuration_id, member_collaborator_id) values
  ('e9e80000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1',
   'e9e40000-0000-0000-0000-000000000001', 'e9b00000-0000-0000-0000-000000000002');

-- ----------------------------------------------------------------------------
-- 5) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs      int;
  v_atores    int;
  v_colabs    int;
  v_status    int;
  v_pos       int;
  v_ocup      int;
  v_coleg     int;
  v_gestor    uuid;
  v_cap       int;
  v_cap_sem   int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('e9a00000-0000-0000-0000-0000000000a1',
                'e9a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_atores from public.user_profiles
   where id::text like 'e9c00000-0000-0000-0000-0000000000%';
  select count(*) into v_colabs from public.collaborators
   where organization_id = 'e9a00000-0000-0000-0000-0000000000a1';
  select count(*) into v_status from public.collaborator_status_periods sp
    join public.collaborators c on c.id = sp.collaborator_id
   where c.organization_id = 'e9a00000-0000-0000-0000-0000000000a1'
     and sp.status = 'active';
  select count(*) into v_pos from public.organizational_positions
   where organization_id = 'e9a00000-0000-0000-0000-0000000000a1';
  select count(*) into v_ocup from public.occupations
   where organization_id = 'e9a00000-0000-0000-0000-0000000000a1';
  select count(*) into v_coleg from public.collegiate_configuration_members
   where organization_id = 'e9a00000-0000-0000-0000-0000000000a1';

  if v_orgs <> 2 or v_atores <> 4 or v_colabs <> 4 or v_status <> 4
     or v_pos <> 3 or v_ocup <> 3 or v_coleg <> 1 then
    raise exception
      '[FAIL] cenario F5-09 P2 incompleto (orgs=%, atores=%, colabs=%, status=%, pos=%, ocup=%, colegiado=%)',
      v_orgs, v_atores, v_colabs, v_status, v_pos, v_ocup, v_coleg;
  end if;

  -- A hierarquia existe de fato nas fontes RELACIONAIS: gestor direto de c1 = c2.
  select r.manager_responsible_collaborator_id into v_gestor
    from public.organizacao_resolver_gestor_direto(
      'e9b00000-0000-0000-0000-000000000001', '2025-01-01T00:00:00Z') r
   limit 1;
  if v_gestor is distinct from 'e9b00000-0000-0000-0000-000000000002'::uuid then
    raise exception '[FAIL] cenario F5-09 P2: gestor direto de c1 deveria ser c2 (recebido %)', v_gestor;
  end if;

  -- Capability resolvida apenas para o ator designado.
  select count(*) into v_cap from public.resolver_capabilities_efetivas(
    'e9c00000-0000-0000-0000-000000000001', 'e9a00000-0000-0000-0000-0000000000a1')
   where capability_code = 'cycle.manage';
  select count(*) into v_cap_sem from public.resolver_capabilities_efetivas(
    'e9c00000-0000-0000-0000-000000000002', 'e9a00000-0000-0000-0000-0000000000a1')
   where capability_code = 'cycle.manage';
  if v_cap <> 1 or v_cap_sem <> 0 then
    raise exception '[FAIL] cenario F5-09 P2: fixture de capability incorreta (a1=%, a2=%)',
      v_cap, v_cap_sem;
  end if;

  raise notice '[PASS] cenario F5-09 P2: 2 orgs, 4 atores, 4 colaboradores ativos, estrutura relacional (gestor de c1 = c2), colegiado do avaliado c3 com membro c2';
end $$;

\endif

-- ----------------------------------------------------------------------------
-- 6) Guarda de estado limpo para o validador (uma vez por banco)
-- ----------------------------------------------------------------------------
-- O validador 04 MUTA ciclos (criar/editar/ativar/encerrar) e a trilha e
-- APPEND-ONLY: nao existe "reset" do dominio. O CI (e o uso local correto)
-- executa `db reset` antes de cada rodada completa; aqui a guarda falha alto se
-- a organizacao da fixture ja tiver ciclo (execucao anterior sem reset).
do $$
declare
  v_ciclos int;
begin
  select count(*) into v_ciclos
    from public.evaluation_cycles
   where organization_id = 'e9a00000-0000-0000-0000-0000000000a1';
  if v_ciclos <> 0 then
    raise exception
      '[FAIL] estado sujo: a organizacao da fixture F5-09 P2 ja possui % ciclo(s) — execute `supabase db reset` antes de reexecutar o cenario/validador da P2 (a trilha de ciclos e append-only por contrato)',
      v_ciclos;
  end if;
  raise notice '[PASS] cenario F5-09 P2: organizacao da fixture sem ciclos (pronta para o validador 04)';
end $$;
