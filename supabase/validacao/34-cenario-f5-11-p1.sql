-- ============================================================================
-- F5-11 P1 (Issue #238): cenario da P1 - SCHEMA e TRILHA das OBSERVACOES
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-11-desenho-tecnico.md (D1-D16; §7.2 tabelas, §7.3 semantica)
-- e migration `20260929000000_f5_11_p1_observations_schema.sql`.
--
-- Fixture ISOLADA (prefixo `fd`) das fixtures das fases anteriores
-- (`ee` = F5-10 P1, `e8` = F5-10 P7, `ed` = F5-09 P9, ...): 2 organizacoes,
-- 2 identidades com membership ativa, 3 colaboradores SOBERANOS (2 em Alfa,
-- 1 no Beta), 3 ciclos (Alfa ATIVO + Alfa ENCERRADO + Beta ATIVO) e 4
-- observacoes com trilha.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: reexecucao e NO-OP (guarda abaixo). Estado limpo = `db reset`.
--   - Nenhuma RPC e usada (a P1 NAO tem RPC - fronteira da P1): os dados sao
--     inseridos DIRETAMENTE, como fixture, inclusive a trilha.
--   - Somente dados ficticios; nenhum dado real e pessoal.
--
-- O que a fixture precisa provar (e o validador 35 cobra):
--   - o schema ACEITA observacao em ciclo NAO-ATIVO (a matriz de estado do D12 e
--     gate FUNCIONAL da P2, NAO constraint de schema da P1 - fronteira explicita);
--   - o CHECK de comunicado (D7) aceita o fato COM carimbo;
--   - o CHECK de exclusao (D8/D16) aceita a exclusao logica COM motivo;
--   - a trilha aceita before/after image com payload_hash canonico;
--   - Beta existe para o teste cross-tenant estrutural (FK composta).
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('fda00000-0000-0000-0000-0000000000a1',
                'fda00000-0000-0000-0000-0000000000b1')
) as cenario_f5_11_p1_carregado \gset

\if :cenario_f5_11_p1_carregado
do $$
begin
  raise notice '[PASS] cenario F5-11 P1 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('fda00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-11 P1 Alfa'),
  ('fda00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-11 P1 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades (auth.users + perfil + membership ativa)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('fdc00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'autor.alfa.f5-11-p1@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('fdc00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'autor.beta.f5-11-p1@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('fdc00000-0000-0000-0000-000000000001', 'active'),
  ('fdc00000-0000-0000-0000-000000000002', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('fdd00000-0000-0000-0000-000000000001', 'fdc00000-0000-0000-0000-000000000001',
   'fda00000-0000-0000-0000-0000000000a1', 'active'),
  ('fdd00000-0000-0000-0000-000000000002', 'fdc00000-0000-0000-0000-000000000002',
   'fda00000-0000-0000-0000-0000000000b1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores SOBERANOS (UUID; nenhuma matricula como identidade)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('fdb00000-0000-0000-0000-000000000001', 'fda00000-0000-0000-0000-0000000000a1'),
  ('fdb00000-0000-0000-0000-000000000002', 'fda00000-0000-0000-0000-0000000000a1'),
  ('fdb00000-0000-0000-0000-0000000000b1', 'fda00000-0000-0000-0000-0000000000b1');

-- ----------------------------------------------------------------------------
-- 4) Ciclos soberanos (Alfa ATIVO + Alfa ENCERRADO + Beta ATIVO)
--    O ciclo ENCERRADO existe para provar que a P1 NAO impoe estado de ciclo no
--    schema (D12 e gate funcional da P2); Beta existe para o cross-tenant.
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim,
   data_ativacao, data_encerramento, version) values
  ('fdd10000-0000-0000-0000-0000000000a1', 'fda00000-0000-0000-0000-0000000000a1',
   2037, 1, 'ATIVO', date '2037-01-01', date '2037-03-31', now(), null, 1),
  ('fdd10000-0000-0000-0000-0000000000a2', 'fda00000-0000-0000-0000-0000000000a1',
   2036, 3, 'ENCERRADO', date '2036-09-01', date '2036-12-31', now() - interval '400 days',
   now() - interval '300 days', 3),
  ('fdd10000-0000-0000-0000-0000000000b1', 'fda00000-0000-0000-0000-0000000000b1',
   2037, 1, 'ATIVO', date '2037-01-01', date '2037-03-31', now(), null, 1);

-- ----------------------------------------------------------------------------
-- 4.1) Vinculo membership <-> colaborador (F4-02)
-- ----------------------------------------------------------------------------
-- Necessario desde a F5-11 P1.1 (Issue #242): `author_collaborator_id` e DERIVADO
-- do vinculo e a coerencia estrutural passou a ser exigida no banco (paridade com
-- `resolver_collaborator_vinculado`, que resolve membership ATIVA -> link
-- `status = 'active'`). Sem estas duas linhas, as observacoes desta fixture
-- informariam um colaborador que NAO e o vinculado da membership e passariam a
-- ser corretamente recusadas.
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status)
values
  ('fde00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fda00000-0000-0000-0000-0000000000a1', 'fdb00000-0000-0000-0000-000000000001', 'active'),
  ('fde00000-0000-0000-0000-000000000002', 'fdd00000-0000-0000-0000-000000000002',
   'fda00000-0000-0000-0000-0000000000b1', 'fdb00000-0000-0000-0000-0000000000b1', 'active');

-- ----------------------------------------------------------------------------
-- 5) Observacoes (a LINHA) - 4 fatos, incluindo comunicado e exclusao logica
-- ----------------------------------------------------------------------------
-- obs 1: Alfa, colaborador 1, ciclo ATIVO, POSITIVA e COMUNICADA (fato com carimbo).
insert into public.evaluation_observations
  (id, organization_id, collaborator_id, cycle_id, tipo, texto,
   comunicado, comunicado_em, comunicado_por_user_profile_id, comunicado_por_membership_id,
   author_user_profile_id, author_membership_id, author_collaborator_id, version)
values
  ('fd900000-0000-0000-0000-000000000001', 'fda00000-0000-0000-0000-0000000000a1',
   'fdb00000-0000-0000-0000-000000000001', 'fdd10000-0000-0000-0000-0000000000a1',
   'POSITIVA', 'Observacao positiva ficticia comunicada (P1)',
   true, now(), 'fdc00000-0000-0000-0000-000000000001',
   'fdd00000-0000-0000-0000-000000000001',
   'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fdb00000-0000-0000-0000-000000000001', 1);

-- obs 2: Alfa, colaborador 2, ciclo ATIVO, NEUTRA e EXCLUIDA logicamente (com motivo).
insert into public.evaluation_observations
  (id, organization_id, collaborator_id, cycle_id, tipo, texto,
   excluida, excluida_em, excluida_por_user_profile_id, excluida_por_membership_id,
   motivo_exclusao, author_user_profile_id, author_membership_id, author_collaborator_id,
   version)
values
  ('fd900000-0000-0000-0000-000000000002', 'fda00000-0000-0000-0000-0000000000a1',
   'fdb00000-0000-0000-0000-000000000002', 'fdd10000-0000-0000-0000-0000000000a1',
   'NEUTRA', 'Observacao neutra ficticia excluida logicamente (P1)',
   true, now(), 'fdc00000-0000-0000-0000-000000000001',
   'fdd00000-0000-0000-0000-000000000001',
   'Motivo ficticio de exclusao (P1)',
   'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fdb00000-0000-0000-0000-000000000001', 2);

-- obs 3: Alfa, colaborador 1, ciclo ENCERRADO - prova que a P1 NAO impoe estado
--        de ciclo no SCHEMA (a mutacao so em ATIVO e gate FUNCIONAL da P2/D12).
insert into public.evaluation_observations
  (id, organization_id, collaborator_id, cycle_id, tipo, texto,
   author_user_profile_id, author_membership_id, author_collaborator_id)
values
  ('fd900000-0000-0000-0000-000000000003', 'fda00000-0000-0000-0000-0000000000a1',
   'fdb00000-0000-0000-0000-000000000001', 'fdd10000-0000-0000-0000-0000000000a2',
   'NEGATIVA', 'Observacao negativa ficticia em ciclo encerrado (P1)',
   'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fdb00000-0000-0000-0000-000000000001');

-- obs 4: Beta (outro tenant) - alvo do teste cross-tenant estrutural.
insert into public.evaluation_observations
  (id, organization_id, collaborator_id, cycle_id, tipo, texto,
   author_user_profile_id, author_membership_id, author_collaborator_id)
values
  ('fd900000-0000-0000-0000-0000000000b1', 'fda00000-0000-0000-0000-0000000000b1',
   'fdb00000-0000-0000-0000-0000000000b1', 'fdd10000-0000-0000-0000-0000000000b1',
   'POSITIVA', 'Observacao ficticia da Beta (P1)',
   'fdc00000-0000-0000-0000-000000000002', 'fdd00000-0000-0000-0000-000000000002',
   'fdb00000-0000-0000-0000-0000000000b1');

-- ----------------------------------------------------------------------------
-- 6) Trilha APPEND-ONLY (D6) - 6 eventos, operation_id unico por organizacao
-- ----------------------------------------------------------------------------
insert into public.evaluation_observation_events
  (id, organization_id, observation_id, entity_type, event_type, effective_date,
   reason, before_value, after_value, payload_hash, result_entity_id,
   actor_user_profile_id, actor_membership_id, operation_id) values
  ('fd700000-0000-0000-0000-000000000001', 'fda00000-0000-0000-0000-0000000000a1',
   'fd900000-0000-0000-0000-000000000001', 'evaluation_observation', 'CRIADA', now(),
   'Criacao de fixture (P1)', null,
   jsonb_build_object('tipo', 'POSITIVA', 'comunicado', false, 'version', 0),
   encode(sha256(convert_to('{"fixture":"f5-11-p1","event":"CRIADA","obs":"1"}', 'UTF8')), 'hex'),
   'fd900000-0000-0000-0000-000000000001',
   'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fd600000-0000-0000-0000-000000000001'),

  ('fd700000-0000-0000-0000-000000000002', 'fda00000-0000-0000-0000-0000000000a1',
   'fd900000-0000-0000-0000-000000000001', 'evaluation_observation', 'COMUNICADO', now(),
   'Comunicacao de fixture (P1)',
   jsonb_build_object('comunicado', false),
   jsonb_build_object('comunicado', true, 'version', 1),
   encode(sha256(convert_to('{"fixture":"f5-11-p1","event":"COMUNICADO","obs":"1"}', 'UTF8')), 'hex'),
   'fd900000-0000-0000-0000-000000000001',
   'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fd600000-0000-0000-0000-000000000002'),

  ('fd700000-0000-0000-0000-000000000003', 'fda00000-0000-0000-0000-0000000000a1',
   'fd900000-0000-0000-0000-000000000002', 'evaluation_observation', 'CRIADA', now(),
   'Criacao de fixture (P1)', null,
   jsonb_build_object('tipo', 'NEUTRA', 'comunicado', false, 'version', 0),
   encode(sha256(convert_to('{"fixture":"f5-11-p1","event":"CRIADA","obs":"2"}', 'UTF8')), 'hex'),
   'fd900000-0000-0000-0000-000000000002',
   'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fd600000-0000-0000-0000-000000000003'),

  ('fd700000-0000-0000-0000-000000000004', 'fda00000-0000-0000-0000-0000000000a1',
   'fd900000-0000-0000-0000-000000000002', 'evaluation_observation', 'EXCLUIDA', now(),
   'Exclusao logica de fixture (P1)',
   jsonb_build_object('excluida', false),
   jsonb_build_object('excluida', true, 'version', 2),
   encode(sha256(convert_to('{"fixture":"f5-11-p1","event":"EXCLUIDA","obs":"2"}', 'UTF8')), 'hex'),
   'fd900000-0000-0000-0000-000000000002',
   'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fd600000-0000-0000-0000-000000000004'),

  ('fd700000-0000-0000-0000-000000000005', 'fda00000-0000-0000-0000-0000000000a1',
   'fd900000-0000-0000-0000-000000000003', 'evaluation_observation', 'CRIADA', now(),
   'Criacao de fixture em ciclo encerrado (P1)', null,
   jsonb_build_object('tipo', 'NEGATIVA', 'comunicado', false, 'version', 0),
   encode(sha256(convert_to('{"fixture":"f5-11-p1","event":"CRIADA","obs":"3"}', 'UTF8')), 'hex'),
   'fd900000-0000-0000-0000-000000000003',
   'fdc00000-0000-0000-0000-000000000001', 'fdd00000-0000-0000-0000-000000000001',
   'fd600000-0000-0000-0000-000000000005'),

  ('fd700000-0000-0000-0000-0000000000b1', 'fda00000-0000-0000-0000-0000000000b1',
   'fd900000-0000-0000-0000-0000000000b1', 'evaluation_observation', 'CRIADA', now(),
   'Criacao de fixture da Beta (P1)', null,
   jsonb_build_object('tipo', 'POSITIVA', 'comunicado', false, 'version', 0),
   encode(sha256(convert_to('{"fixture":"f5-11-p1","event":"CRIADA","obs":"b1"}', 'UTF8')), 'hex'),
   'fd900000-0000-0000-0000-0000000000b1',
   'fdc00000-0000-0000-0000-000000000002', 'fdd00000-0000-0000-0000-000000000002',
   'fd600000-0000-0000-0000-0000000000b1');

-- ----------------------------------------------------------------------------
-- 7) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs       int;
  v_memb       int;
  v_colabs     int;
  v_ciclos     int;
  v_links      int;
  v_obs        int;
  v_obs_alfa   int;
  v_obs_beta   int;
  v_comunic    int;
  v_excluidas  int;
  v_eventos    int;
  v_criadas    int;
  v_encerradas int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('fda00000-0000-0000-0000-0000000000a1',
                'fda00000-0000-0000-0000-0000000000b1');
  select count(*) into v_memb from public.user_organization_memberships
   where id in ('fdd00000-0000-0000-0000-000000000001',
                'fdd00000-0000-0000-0000-000000000002') and status = 'active';
  select count(*) into v_colabs from public.collaborators
   where id in ('fdb00000-0000-0000-0000-000000000001',
                'fdb00000-0000-0000-0000-000000000002',
                'fdb00000-0000-0000-0000-0000000000b1');
  select count(*) into v_ciclos from public.evaluation_cycles
   where id in ('fdd10000-0000-0000-0000-0000000000a1',
                'fdd10000-0000-0000-0000-0000000000a2',
                'fdd10000-0000-0000-0000-0000000000b1');
  select count(*) into v_links from public.membership_collaborator_links
   where id in ('fde00000-0000-0000-0000-000000000001',
                'fde00000-0000-0000-0000-000000000002') and status = 'active';
  select count(*) into v_obs from public.evaluation_observations
   where organization_id in ('fda00000-0000-0000-0000-0000000000a1',
                             'fda00000-0000-0000-0000-0000000000b1');
  select count(*) into v_obs_alfa from public.evaluation_observations
   where organization_id = 'fda00000-0000-0000-0000-0000000000a1';
  select count(*) into v_obs_beta from public.evaluation_observations
   where organization_id = 'fda00000-0000-0000-0000-0000000000b1';
  select count(*) into v_comunic from public.evaluation_observations
   where comunicado and organization_id = 'fda00000-0000-0000-0000-0000000000a1';
  select count(*) into v_excluidas from public.evaluation_observations
   where excluida and organization_id = 'fda00000-0000-0000-0000-0000000000a1';
  select count(*) into v_eventos from public.evaluation_observation_events
   where organization_id in ('fda00000-0000-0000-0000-0000000000a1',
                             'fda00000-0000-0000-0000-0000000000b1');
  select count(*) into v_criadas from public.evaluation_observation_events
   where event_type = 'CRIADA';
  select count(*) into v_encerradas from public.evaluation_observations o
    join public.evaluation_cycles c on c.id = o.cycle_id
   where c.status = 'ENCERRADO';

  if v_orgs <> 2 or v_memb <> 2 or v_colabs <> 3 or v_ciclos <> 3 or v_links <> 2
     or v_obs <> 4 or v_obs_alfa <> 3 or v_obs_beta <> 1
     or v_comunic <> 1 or v_excluidas <> 1 or v_eventos <> 6
     or v_criadas <> 4 or v_encerradas <> 1 then
    raise exception
      '[FAIL] cenario F5-11 P1 incompleto (orgs=%, memberships=%, colabs=%, ciclos=%, links=%, obs=%, obs_alfa=%, obs_beta=%, comunicadas=%, excluidas=%, eventos=%, criadas=%, em_ciclo_encerrado=%)',
      v_orgs, v_memb, v_colabs, v_ciclos, v_links, v_obs, v_obs_alfa, v_obs_beta,
      v_comunic, v_excluidas, v_eventos, v_criadas, v_encerradas;
  end if;

  raise notice '[PASS] cenario F5-11 P1: 2 orgs, 2 memberships ativas, 3 colaboradores soberanos, 3 ciclos (Alfa ATIVO, Alfa ENCERRADO, Beta ATIVO), 2 vinculos membership<->colaborador, 4 observacoes (1 comunicada, 1 excluida logicamente, 1 em ciclo encerrado), 6 eventos na trilha (4 CRIADA)';
end $$;

\endif
