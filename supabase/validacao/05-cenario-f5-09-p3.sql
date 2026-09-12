-- ============================================================================
-- F5-09 P3: cenario sintetico de validacao — inclusao aditiva de nova admissao
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§7.2 provas P1–P7, §7.3 contrato
-- restrito, §10 I17–I19, §11, §12, §13.2/§13.3, §15.1 A1–A12, §19 P3) + migration
-- `20260917000000_f5_09_cycle_admission.sql`.
--
-- Fixture para `06-validar-f5-09-p3.sql` — ISOLADA do estado mutado pela P2
-- (prefixo proprio `ea`; organizacoes, atores, estrutura e colaboradores novos):
--   - duas organizacoes (Alfa-P3 e Beta-P3) com atores distintos:
--     a1 = ator Alfa-P3 COM `cycle.manage`; a2 = ator Alfa-P3 SEM assignment
--     (sem capability); a3 = ator Beta-P3 (COM `cycle.manage` no PRÓPRIO tenant,
--     para que o validador possa montar o probe cross-tenant direto);
--     a4 = ator Alfa-P3 com membership DISABLED;
--   - estrutura SOBERANA relacional em Alfa-P3 (unidade, cargo, senioridade,
--     QUATRO posicoes e reporting lines P2->P1 e P3->P1) — a hierarquia da
--     inclusao vem SEMPRE de F3-04/F3-07/F3-08, nunca de cargo/texto;
--   - colaboradores de base B1 (ocupando P1) e B2 (ocupando P2), ambos com status
--     `active` DESDE ANTES da ativacao e SEM evento soberano de admissao: sao a
--     populacao inicial materializada na ativacao e, ao mesmo tempo, o caso
--     LEGADO/IMPORTADO (sem prova soberana) que a P3 deve RECUSAR (P7). O
--     colaborador BB1 (Beta-P3) existe para o probe cross-tenant direto;
--   - NENHUM ciclo e criado aqui: as mutacoes de ciclo (criar/ativar/incluir) sao
--     exercitadas pelo validador 06, que tambem monta os casos sinteticos de
--     importacao/legado DEPOIS da ativacao (quando a ausencia de prova e o que
--     esta sob teste).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: a trilha `cycle_events` e append-only protegida (P1) e as FKs
--     da trilha sao ON DELETE RESTRICT. Reexecucao e NO-OP (guarda abaixo). Para
--     estado limpo use `db reset` (como no CI).
--   - Somente dados ficticios; nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('eaa00000-0000-0000-0000-0000000000a1',
                'eaa00000-0000-0000-0000-0000000000b1')
) as cenario_f5_09_p3_carregado \gset

\if :cenario_f5_09_p3_carregado
do $$
begin
  raise notice '[PASS] cenario F5-09 P3 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('eaa00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-09 P3 Alfa'),
  ('eaa00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-09 P3 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades sinteticas (auth.users) + perfis internos
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('eac00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.alfa.f5-09-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('eac00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sem.cap.f5-09-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('eac00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.beta.f5-09-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('eac00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.disabled.f5-09-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('eac00000-0000-0000-0000-000000000001', 'active'),
  ('eac00000-0000-0000-0000-000000000002', 'active'),
  ('eac00000-0000-0000-0000-000000000003', 'active'),
  ('eac00000-0000-0000-0000-000000000004', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('ead00000-0000-0000-0000-000000000001', 'eac00000-0000-0000-0000-000000000001',
   'eaa00000-0000-0000-0000-0000000000a1', 'active'),
  ('ead00000-0000-0000-0000-000000000002', 'eac00000-0000-0000-0000-000000000002',
   'eaa00000-0000-0000-0000-0000000000a1', 'active'),
  ('ead00000-0000-0000-0000-000000000003', 'eac00000-0000-0000-0000-000000000003',
   'eaa00000-0000-0000-0000-0000000000b1', 'active'),
  ('ead00000-0000-0000-0000-000000000004', 'eac00000-0000-0000-0000-000000000004',
   'eaa00000-0000-0000-0000-0000000000a1', 'disabled');

-- Roles customizadas com `cycle.manage` (capability EXISTENTE do catalogo; a P3
-- reusa `cycle.manage` e NAO cria capability nova — D26/D20) + assignments ativos.
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('eaf90000-0000-0000-0000-0000000000a1', 'ciclos-p3-alfa', 'active', false,
   'eaa00000-0000-0000-0000-0000000000a1'),
  ('eaf90000-0000-0000-0000-0000000000b1', 'ciclos-p3-beta', 'active', false,
   'eaa00000-0000-0000-0000-0000000000b1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id in ('eaf90000-0000-0000-0000-0000000000a1',
                 'eaf90000-0000-0000-0000-0000000000b1')
   and c.code = 'cycle.manage';

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('eaf80000-0000-0000-0000-000000000001', 'ead00000-0000-0000-0000-000000000001',
   'eaa00000-0000-0000-0000-0000000000a1', 'eaf90000-0000-0000-0000-0000000000a1',
   'active', 'eac00000-0000-0000-0000-000000000001'),
  ('eaf80000-0000-0000-0000-000000000003', 'ead00000-0000-0000-0000-000000000003',
   'eaa00000-0000-0000-0000-0000000000b1', 'eaf90000-0000-0000-0000-0000000000b1',
   'active', 'eac00000-0000-0000-0000-000000000003');

-- ----------------------------------------------------------------------------
-- 3) Estrutura soberana (F3-02/F3-03/F3-04) — hierarquia RELACIONAL
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('eae00000-0000-0000-0000-0000000000a1', 'eaa00000-0000-0000-0000-0000000000a1',
   'Analista F5-09 P3', 'ANL-F5-09-P3', 'active'),
  ('eae00000-0000-0000-0000-0000000000b1', 'eaa00000-0000-0000-0000-0000000000b1',
   'Analista F5-09 P3 Beta', 'ANL-F5-09-P3-B', 'active');

insert into public.seniority_levels (id, organization_id, name, status) values
  ('eae70000-0000-0000-0000-0000000000a1', 'eaa00000-0000-0000-0000-0000000000a1',
   'Senior F5-09 P3', 'active'),
  ('eae70000-0000-0000-0000-0000000000b1', 'eaa00000-0000-0000-0000-0000000000b1',
   'Senior F5-09 P3 Beta', 'active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('eaf00000-0000-0000-0000-0000000000a1', 'eaa00000-0000-0000-0000-0000000000a1',
   'F5-09 P3 Unidade Alfa', '2024-01-01T00:00:00Z'),
  ('eaf00000-0000-0000-0000-0000000000b1', 'eaa00000-0000-0000-0000-0000000000b1',
   'F5-09 P3 Unidade Beta', '2024-01-01T00:00:00Z');

-- P1 = posicao do gestor (ocupada por B1); P2 = posicao subordinada da base
-- (ocupada por B2) com reporting line P2->P1; P3 = posicao de destino da PRIMEIRA
-- nova admissao; P5 = destino da SEGUNDA nova admissao; P6 = destino do
-- colaborador usado nas provas de ROLLBACK; P4 = posicao de destino da
-- MOVIMENTACAO posterior de B2 (que NAO pode rematerializar o ciclo — D27).
-- As posicoes P3/P5/P6 tem reporting line para P1 para que o snapshot novo
-- tenham superior resolvido de forma RELACIONAL (nunca por cargo/texto).
insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from) values
  ('eae10000-0000-0000-0000-000000000001', 'eaa00000-0000-0000-0000-0000000000a1',
   'eaf00000-0000-0000-0000-0000000000a1', 'eae00000-0000-0000-0000-0000000000a1',
   'eae70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('eae10000-0000-0000-0000-000000000002', 'eaa00000-0000-0000-0000-0000000000a1',
   'eaf00000-0000-0000-0000-0000000000a1', 'eae00000-0000-0000-0000-0000000000a1',
   'eae70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('eae10000-0000-0000-0000-000000000003', 'eaa00000-0000-0000-0000-0000000000a1',
   'eaf00000-0000-0000-0000-0000000000a1', 'eae00000-0000-0000-0000-0000000000a1',
   'eae70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('eae10000-0000-0000-0000-000000000004', 'eaa00000-0000-0000-0000-0000000000a1',
   'eaf00000-0000-0000-0000-0000000000a1', 'eae00000-0000-0000-0000-0000000000a1',
   'eae70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('eae10000-0000-0000-0000-000000000005', 'eaa00000-0000-0000-0000-0000000000a1',
   'eaf00000-0000-0000-0000-0000000000a1', 'eae00000-0000-0000-0000-0000000000a1',
   'eae70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('eae10000-0000-0000-0000-000000000006', 'eaa00000-0000-0000-0000-0000000000a1',
   'eaf00000-0000-0000-0000-0000000000a1', 'eae00000-0000-0000-0000-0000000000a1',
   'eae70000-0000-0000-0000-0000000000a1', '2024-01-01T00:00:00Z'),
  ('eae10000-0000-0000-0000-0000000000b1', 'eaa00000-0000-0000-0000-0000000000b1',
   'eaf00000-0000-0000-0000-0000000000b1', 'eae00000-0000-0000-0000-0000000000b1',
   'eae70000-0000-0000-0000-0000000000b1', '2024-01-01T00:00:00Z');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('eae30000-0000-0000-0000-000000000001', 'eaa00000-0000-0000-0000-0000000000a1',
   'eae10000-0000-0000-0000-000000000002', 'eae10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P3 (base)', '2024-01-01T00:00:00Z'),
  ('eae30000-0000-0000-0000-000000000002', 'eaa00000-0000-0000-0000-0000000000a1',
   'eae10000-0000-0000-0000-000000000003', 'eae10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P3 (nova admissao 1)', '2024-01-01T00:00:00Z'),
  ('eae30000-0000-0000-0000-000000000003', 'eaa00000-0000-0000-0000-0000000000a1',
   'eae10000-0000-0000-0000-000000000005', 'eae10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P3 (nova admissao 2)', '2024-01-01T00:00:00Z'),
  ('eae30000-0000-0000-0000-000000000004', 'eaa00000-0000-0000-0000-0000000000a1',
   'eae10000-0000-0000-0000-000000000006', 'eae10000-0000-0000-0000-000000000001',
   'reporting line F5-09 P3 (rollback)', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 4) Colaboradores de BASE da populacao inicial (materializados na ativacao)
-- ----------------------------------------------------------------------------
-- Inseridos DIRETAMENTE (caminho sintetico de importacao/legado): NAO existe
-- evento soberano `ADMISSAO` para eles. Isso e deliberado e cobre dois casos:
--   (i) sao a populacao inicial materializada na ativacao (D26);
--   (ii) sao o caso "colaborador sem prova soberana de admissao" que a P3 deve
--        RECUSAR (P7) — a solucao correta e o caminho de importacao gravar o
--        evento, nunca relaxar a prova.
insert into public.collaborators (id, organization_id, full_name, email, admission_date) values
  ('eab00000-0000-0000-0000-000000000001', 'eaa00000-0000-0000-0000-0000000000a1',
   'Colaborador Base P3 B1', 'base.b1.f5-09-p3@example.invalid', date '2024-01-01'),
  ('eab00000-0000-0000-0000-000000000002', 'eaa00000-0000-0000-0000-0000000000a1',
   'Colaborador Base P3 B2', 'base.b2.f5-09-p3@example.invalid', date '2024-01-01'),
  ('eab00000-0000-0000-0000-0000000000b1', 'eaa00000-0000-0000-0000-0000000000b1',
   'Colaborador Beta P3 BB1', 'base.bb1.f5-09-p3@example.invalid', date '2024-01-01');

insert into public.collaborator_identifiers
  (collaborator_id, organization_id, business_code, valid_from) values
  ('eab00000-0000-0000-0000-000000000001', 'eaa00000-0000-0000-0000-0000000000a1', 92001, '2024-01-01T00:00:00Z'),
  ('eab00000-0000-0000-0000-000000000002', 'eaa00000-0000-0000-0000-0000000000a1', 92002, '2024-01-01T00:00:00Z'),
  ('eab00000-0000-0000-0000-0000000000b1', 'eaa00000-0000-0000-0000-0000000000b1', 92901, '2024-01-01T00:00:00Z');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('eab00000-0000-0000-0000-000000000001', 'active', '2024-01-01T00:00:00Z'),
  ('eab00000-0000-0000-0000-000000000002', 'active', '2024-01-01T00:00:00Z'),
  ('eab00000-0000-0000-0000-0000000000b1', 'active', '2024-01-01T00:00:00Z');

insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('eae20000-0000-0000-0000-000000000001', 'eaa00000-0000-0000-0000-0000000000a1',
   'eab00000-0000-0000-0000-000000000001', 'eae10000-0000-0000-0000-000000000001',
   'ocupacao F5-09 P3 base B1', '2024-01-01T00:00:00Z'),
  ('eae20000-0000-0000-0000-000000000002', 'eaa00000-0000-0000-0000-0000000000a1',
   'eab00000-0000-0000-0000-000000000002', 'eae10000-0000-0000-0000-000000000002',
   'ocupacao F5-09 P3 base B2', '2024-01-01T00:00:00Z'),
  ('eae20000-0000-0000-0000-0000000000b1', 'eaa00000-0000-0000-0000-0000000000b1',
   'eab00000-0000-0000-0000-0000000000b1', 'eae10000-0000-0000-0000-0000000000b1',
   'ocupacao F5-09 P3 base BB1', '2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 5) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs    int;
  v_atores  int;
  v_colabs  int;
  v_status  int;
  v_pos     int;
  v_ocup    int;
  v_linhas  int;
  v_gestor  uuid;
  v_cap     int;
  v_cap_sem int;
  v_cap_beta int;
  v_eventos int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('eaa00000-0000-0000-0000-0000000000a1',
                'eaa00000-0000-0000-0000-0000000000b1');
  select count(*) into v_atores from public.user_profiles
   where id::text like 'eac00000-0000-0000-0000-0000000000%';
  select count(*) into v_colabs from public.collaborators
   where organization_id = 'eaa00000-0000-0000-0000-0000000000a1';
  select count(*) into v_status from public.collaborator_status_periods sp
    join public.collaborators c on c.id = sp.collaborator_id
   where c.organization_id = 'eaa00000-0000-0000-0000-0000000000a1'
     and sp.status = 'active';
  select count(*) into v_pos from public.organizational_positions
   where organization_id = 'eaa00000-0000-0000-0000-0000000000a1';
  select count(*) into v_ocup from public.occupations
   where organization_id = 'eaa00000-0000-0000-0000-0000000000a1';
  select count(*) into v_linhas from public.position_reporting_lines
   where organization_id = 'eaa00000-0000-0000-0000-0000000000a1';
  -- A fixture de BASE nao tem evento soberano algum (importacao/legado): e o
  -- insumo do caso P7 (fail-closed) e NAO pode ser "corrigido" aqui.
  select count(*) into v_eventos from public.collaborator_events
   where organization_id in ('eaa00000-0000-0000-0000-0000000000a1',
                             'eaa00000-0000-0000-0000-0000000000b1');

  if v_orgs <> 2 or v_atores <> 4 or v_colabs <> 2 or v_status <> 2
     or v_pos <> 6 or v_ocup <> 2 or v_linhas <> 4 then
    raise exception
      '[FAIL] cenario F5-09 P3 incompleto (orgs=%, atores=%, colabs=%, status=%, pos=%, ocup=%, linhas=%)',
      v_orgs, v_atores, v_colabs, v_status, v_pos, v_ocup, v_linhas;
  end if;
  if v_eventos <> 0 then
    raise exception '[FAIL] cenario F5-09 P3: fixture de base deveria estar SEM eventos soberanos (encontrados %)',
      v_eventos;
  end if;

  -- A hierarquia de base existe de fato nas fontes RELACIONAIS:
  -- gestor direto de B2 (ocupante de P2) = B1 (ocupante de P1).
  select r.manager_responsible_collaborator_id into v_gestor
    from public.organizacao_resolver_gestor_direto(
      'eab00000-0000-0000-0000-000000000002', '2025-01-01T00:00:00Z') r
   limit 1;
  if v_gestor is distinct from 'eab00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] cenario F5-09 P3: gestor direto de B2 deveria ser B1 (recebido %)', v_gestor;
  end if;

  -- Capability resolvida apenas para os atores designados.
  select count(*) into v_cap from public.resolver_capabilities_efetivas(
    'eac00000-0000-0000-0000-000000000001', 'eaa00000-0000-0000-0000-0000000000a1')
   where capability_code = 'cycle.manage';
  select count(*) into v_cap_sem from public.resolver_capabilities_efetivas(
    'eac00000-0000-0000-0000-000000000002', 'eaa00000-0000-0000-0000-0000000000a1')
   where capability_code = 'cycle.manage';
  select count(*) into v_cap_beta from public.resolver_capabilities_efetivas(
    'eac00000-0000-0000-0000-000000000003', 'eaa00000-0000-0000-0000-0000000000b1')
   where capability_code = 'cycle.manage';
  if v_cap <> 1 or v_cap_sem <> 0 or v_cap_beta <> 1 then
    raise exception '[FAIL] cenario F5-09 P3: fixture de capability incorreta (a1=%, a2=%, a3/beta=%)',
      v_cap, v_cap_sem, v_cap_beta;
  end if;

  -- O ator Beta NAO tem capability em Alfa-P3 (insumo do probe cross-tenant).
  if public.ciclo_ator_valido('eac00000-0000-0000-0000-000000000003',
                              'eaa00000-0000-0000-0000-0000000000a1', 'cycle.manage') is not false then
    raise exception '[FAIL] cenario F5-09 P3: ator Beta nao deveria ter cycle.manage em Alfa-P3';
  end if;

  raise notice '[PASS] cenario F5-09 P3: 2 orgs, 4 atores, 2 colaboradores de base ativos SEM evento soberano (caso P7), estrutura relacional (gestor de B2 = B1), 6 posicoes e 4 reporting lines';
end $$;

\endif

-- ----------------------------------------------------------------------------
-- 6) Guarda de estado limpo para o validador (uma vez por banco)
-- ----------------------------------------------------------------------------
-- O validador 06 MUTA ciclos (criar/ativar/incluir) e a trilha e APPEND-ONLY:
-- nao existe "reset" do dominio. O CI (e o uso local correto) executa `db reset`
-- antes de cada rodada completa; aqui a guarda falha alto se a organizacao da
-- fixture ja tiver ciclo (execucao anterior sem reset).
do $$
declare
  v_ciclos int;
begin
  select count(*) into v_ciclos
    from public.evaluation_cycles
   where organization_id in ('eaa00000-0000-0000-0000-0000000000a1',
                             'eaa00000-0000-0000-0000-0000000000b1');
  if v_ciclos <> 0 then
    raise exception
      '[FAIL] estado sujo: as organizacoes da fixture F5-09 P3 ja possuem % ciclo(s) — execute `supabase db reset` antes de reexecutar o cenario/validador da P3 (a trilha de ciclos e append-only por contrato)',
      v_ciclos;
  end if;
  raise notice '[PASS] cenario F5-09 P3: organizacoes da fixture sem ciclos (prontas para o validador 06)';
end $$;
