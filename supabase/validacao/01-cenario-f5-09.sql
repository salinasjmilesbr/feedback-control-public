-- ============================================================================
-- F5-09 P1: cenario sintetico de validacao — integridade de ciclos e trilha
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§9, §10, §11, §12, §19 P1) e
-- docs/F5-09-duvidas.md (Q-F5-09-1..3 ratificadas).
--
-- Este arquivo prepara, de forma DETERMINISTICA e REEXECUTAVEL, a fixture usada
-- por `02-validar-f5-09.sql`:
--
--   - duas organizacoes sinteticas (Alfa e Beta F5-09), perfis, memberships e
--     assignments suficientes para os guards de ator/tenant/capability;
--   - ciclos que exercitam: ATIVO unico por organizacao, adjacencia de periodo
--     (data_fim INCLUSIVA), CANCELADO sobreposto (nao bloqueia), ciclo sem
--     periodo (fora do indice parcial) e o MESMO periodo em tenants diferentes
--     (isolamento por organizacao);
--   - uma linha da trilha `cycle_events` para os testes de append-only.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca em projeto
--     remoto; nenhum dado real e utilizado (apenas ficticio).
--   - Insere via superuser local: a RLS e as policies NAO sao alteradas — o
--     deny-by-default e validado na etapa 02.
--   - Nenhuma RPC `ciclo_*` e chamada aqui: o P1 nao possui RPCs (P2+).
--   - REEXECUTAVEL: remove e recria somente os UUIDs fixos abaixo (prefixo f9).
--
-- Janelas (DATE, UTC):
--   2025-01-01..2025-06-30  ciclo ENCERRADO (Alfa)
--   2026-01-01..2026-03-31  Q1 — ATIVO em Alfa e ATIVO em Beta (mesmo periodo)
--   2026-04-01..2026-06-30  Q2 — PLANEJADO adjacente (prova data_fim inclusiva)
--   2026-02-01..2026-02-28  periodo SOBREPOSTO ao Q1 — usado pelo CANCELADO
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Guarda de reexecucao — fixture INSERT-ONCE
-- ----------------------------------------------------------------------------
-- A trilha `cycle_events` e APPEND-ONLY PROTEGIDA NO BANCO: DELETE e TRUNCATE
-- levantam excecao por trigger (inclusive para o owner/superuser) e as FKs da
-- trilha sao ON DELETE RESTRICT (organizacao, ciclo, ator, membership). Logo o
-- cenario NAO pode ser apagado e recriado: ele e inserido UMA vez e a
-- reexecucao e NO-OP. Execucao anterior abortada deixa estado parcial, e a
-- checagem de consistencia do §7 falha alto — nunca passa silenciosamente.
select exists (
  select 1
    from public.cycle_events
   where organization_id in (
     'f9a00000-0000-0000-0000-0000000000a1',
     'f9a00000-0000-0000-0000-0000000000b1')
) as cenario_f5_09_carregado \gset

\if :cenario_f5_09_carregado
do $$
begin
  raise notice '[PASS] cenario F5-09 P1 ja carregado — reexecucao no-op (trilha append-only protegida no banco)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f9a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-09 Alfa'),
  ('f9a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-09 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades sinteticas (auth.users) + perfis internos
--    a1 — ator Alfa com a capability cycle.manage (assignment ativo)
--    a2 — ator Alfa SEM assignment (fixture de "sem capability")
--    a3 — ator Beta com a capability cycle.manage EM BETA (cross-tenant)
--    a4 — ator Alfa com membership DISABLED
--    a5 — perfil DISABLED com membership ativa
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f9c00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.a.f5-09@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f9c00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sem.cap.f5-09@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f9c00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.b.f5-09@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f9c00000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.disabled.f5-09@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f9c00000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfil.disabled.f5-09@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('f9c00000-0000-0000-0000-0000000000a1', 'active'),
  ('f9c00000-0000-0000-0000-0000000000a2', 'active'),
  ('f9c00000-0000-0000-0000-0000000000a3', 'active'),
  ('f9c00000-0000-0000-0000-0000000000a4', 'active'),
  ('f9c00000-0000-0000-0000-0000000000a5', 'disabled');

-- ----------------------------------------------------------------------------
-- 3) Memberships sinteticas
-- ----------------------------------------------------------------------------
insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('f9d00000-0000-0000-0000-0000000000a1', 'f9c00000-0000-0000-0000-0000000000a1',
   'f9a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f9d00000-0000-0000-0000-0000000000a2', 'f9c00000-0000-0000-0000-0000000000a2',
   'f9a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f9d00000-0000-0000-0000-0000000000b1', 'f9c00000-0000-0000-0000-0000000000a3',
   'f9a00000-0000-0000-0000-0000000000b1', 'active'),
  ('f9d00000-0000-0000-0000-0000000000a4', 'f9c00000-0000-0000-0000-0000000000a4',
   'f9a00000-0000-0000-0000-0000000000a1', 'disabled'),
  ('f9d00000-0000-0000-0000-0000000000a5', 'f9c00000-0000-0000-0000-0000000000a5',
   'f9a00000-0000-0000-0000-0000000000a1', 'active');

-- ----------------------------------------------------------------------------
-- 4) Roles customizadas com `cycle.manage` (uma por organizacao) + assignments
-- ----------------------------------------------------------------------------
-- A capability `cycle.manage` ja existe no catalogo (F4-01) e e `grantable_via_role`.
-- `ciclo_ator_valido` usa `resolver_capabilities_efetivas` (SEM escopo), que
-- exige apenas: assignment ATIVO + role ATIVA + capability ATIVA nao deprecada.
-- Nenhum scope e criado aqui de proposito: escopo funcional e decisao do Policy
-- Engine na fronteira (Edge), nao do helper de tenant.
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('f9f90000-0000-0000-0000-0000000000a1', 'ciclos-alfa', 'active', false,
   'f9a00000-0000-0000-0000-0000000000a1'),
  ('f9f90000-0000-0000-0000-0000000000b1', 'ciclos-beta', 'active', false,
   'f9a00000-0000-0000-0000-0000000000b1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id in (
         'f9f90000-0000-0000-0000-0000000000a1',
         'f9f90000-0000-0000-0000-0000000000b1')
   and c.code = 'cycle.manage';

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f9e20000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
   'f9a00000-0000-0000-0000-0000000000a1', 'f9f90000-0000-0000-0000-0000000000a1',
   'active', 'f9c00000-0000-0000-0000-0000000000a1'),
  ('f9e20000-0000-0000-0000-0000000000b1', 'f9d00000-0000-0000-0000-0000000000b1',
   'f9a00000-0000-0000-0000-0000000000b1', 'f9f90000-0000-0000-0000-0000000000b1',
   'active', 'f9c00000-0000-0000-0000-0000000000a3');

-- ----------------------------------------------------------------------------
-- 5) Ciclos — integridade I5/I6 e semantica temporal (data_fim INCLUSIVA)
-- ----------------------------------------------------------------------------
-- Alfa:
--   c1 ATIVO     2026-01-01..2026-03-31  (Q1)
--   c2 PLANEJADO 2026-04-01..2026-06-30  (adjacente: [01-01,04-01) e [04-01,07-01))
--   c3 CANCELADO 2026-02-01..2026-02-28  (sobreposto ao c1 — CANCELADO nao bloqueia)
--   c4 ENCERRADO 2025-01-01..2025-06-30  (periodo passado)
--   c5 PLANEJADO sem periodo             (fora do indice parcial)
-- Beta:
--   d1 ATIVO     2026-01-01..2026-03-31  (MESMO periodo do c1, outro tenant)
--   d2 PLANEJADO 2026-04-01..2026-06-30
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim)
values
  ('f9e00000-0000-0000-0000-0000000000c1', 'f9a00000-0000-0000-0000-0000000000a1',
   2026, 1, 'ATIVO',     date '2026-01-01', date '2026-03-31'),
  ('f9e00000-0000-0000-0000-0000000000c2', 'f9a00000-0000-0000-0000-0000000000a1',
   2026, 2, 'PLANEJADO', date '2026-04-01', date '2026-06-30'),
  ('f9e00000-0000-0000-0000-0000000000c3', 'f9a00000-0000-0000-0000-0000000000a1',
   2026, 3, 'CANCELADO', date '2026-02-01', date '2026-02-28'),
  ('f9e00000-0000-0000-0000-0000000000c4', 'f9a00000-0000-0000-0000-0000000000a1',
   2025, 1, 'ENCERRADO', date '2025-01-01', date '2025-06-30'),
  ('f9e00000-0000-0000-0000-0000000000c5', 'f9a00000-0000-0000-0000-0000000000a1',
   2027, 1, 'PLANEJADO', null, null),
  ('f9e00000-0000-0000-0000-0000000000d1', 'f9a00000-0000-0000-0000-0000000000b1',
   2026, 1, 'ATIVO',     date '2026-01-01', date '2026-03-31'),
  ('f9e00000-0000-0000-0000-0000000000d2', 'f9a00000-0000-0000-0000-0000000000b1',
   2026, 2, 'PLANEJADO', date '2026-04-01', date '2026-06-30');

-- ----------------------------------------------------------------------------
-- 6) Trilha `cycle_events` — uma linha para os testes de append-only
-- ----------------------------------------------------------------------------
insert into public.cycle_events
  (id, organization_id, cycle_id, entity_type, event_type, effective_date,
   reason, after_value, payload_hash, result_entity_id,
   actor_user_profile_id, actor_membership_id, operation_id)
values
  ('f9e30000-0000-0000-0000-0000000000e1', 'f9a00000-0000-0000-0000-0000000000a1',
   'f9e00000-0000-0000-0000-0000000000c1', 'evaluation_cycle', 'CRIADO',
   '2026-01-01T00:00:00Z', 'fixture F5-09 P1',
   '{"status": "PLANEJADO", "ano": 2026, "numero": 1}'::jsonb,
   encode(sha256(convert_to('fixture-f5-09-p1', 'UTF8')), 'hex'),
   'f9e00000-0000-0000-0000-0000000000c1',
   'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
   'f9e40000-0000-0000-0000-0000000000e1');

\endif

-- ----------------------------------------------------------------------------
-- 7) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_ciclos   int;
  v_alfa     int;
  v_beta     int;
  v_ativos   int;
  v_eventos  int;
  v_cap_a1   int;
  v_cap_a2   int;
  v_cap_b1   int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('f9a00000-0000-0000-0000-0000000000a1',
                'f9a00000-0000-0000-0000-0000000000b1');

  select count(*) into v_ciclos from public.evaluation_cycles
   where organization_id in ('f9a00000-0000-0000-0000-0000000000a1',
                             'f9a00000-0000-0000-0000-0000000000b1');

  select count(*) into v_alfa from public.evaluation_cycles
   where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

  select count(*) into v_beta from public.evaluation_cycles
   where organization_id = 'f9a00000-0000-0000-0000-0000000000b1';

  select count(*) into v_ativos from public.evaluation_cycles
   where organization_id in ('f9a00000-0000-0000-0000-0000000000a1',
                             'f9a00000-0000-0000-0000-0000000000b1')
     and status = 'ATIVO';

  select count(*) into v_eventos from public.cycle_events
   where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

  select count(*) into v_cap_a1 from public.resolver_capabilities_efetivas(
    'f9c00000-0000-0000-0000-0000000000a1', 'f9a00000-0000-0000-0000-0000000000a1')
   where capability_code = 'cycle.manage';

  select count(*) into v_cap_a2 from public.resolver_capabilities_efetivas(
    'f9c00000-0000-0000-0000-0000000000a2', 'f9a00000-0000-0000-0000-0000000000a1')
   where capability_code = 'cycle.manage';

  select count(*) into v_cap_b1 from public.resolver_capabilities_efetivas(
    'f9c00000-0000-0000-0000-0000000000a3', 'f9a00000-0000-0000-0000-0000000000b1')
   where capability_code = 'cycle.manage';

  if v_orgs <> 2 or v_ciclos <> 7 or v_alfa <> 5 or v_beta <> 2 then
    raise exception
      '[FAIL] cenario F5-09 incompleto (orgs=%, ciclos=%, alfa=%, beta=%)',
      v_orgs, v_ciclos, v_alfa, v_beta;
  end if;

  if v_ativos <> 2 then
    raise exception '[FAIL] cenario F5-09: ATIVO esperado=2 (um por org), encontrado=%', v_ativos;
  end if;

  if v_eventos <> 1 then
    raise exception '[FAIL] cenario F5-09: eventos esperados=1, encontrados=%', v_eventos;
  end if;

  if v_cap_a1 <> 1 or v_cap_b1 <> 1 or v_cap_a2 <> 0 then
    raise exception
      '[FAIL] fixture de autorizacao incorreta (a1=%, b1=%, a2=%)',
      v_cap_a1, v_cap_b1, v_cap_a2;
  end if;

  raise notice '[PASS] cenario F5-09 P1: 2 orgs, 7 ciclos (2 ATIVO — um por org), 1 evento, capability resolvida apenas para os atores designados';
end $$;
