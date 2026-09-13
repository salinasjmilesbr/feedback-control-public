-- ============================================================================
-- F5-10 P1 (Issue #210): cenario da P1 - schema/integridade/limites de METAS
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md (D1-D25) e migration
-- `20260922000000_f5_10_p1_goals_schema.sql`.
--
-- Fixture ISOLADA (prefixo `ee`) das fixtures das fases anteriores (P5 = `ec`,
-- P4 = `eb`, P9 = `ed`): 2 organizacoes, 2 identidades com membership ativa,
-- 3 colaboradores SOBERANOS (2 em Alfa, 1 no Beta), 1 ciclo por organizacao e a
-- QUOTA soberana por tipo. Inclui o minimo de dados funcionais que o schema da
-- P1 precisa para provar invariantes (1 meta + 1 aprovacao + 1 evento).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: reexecucao e NO-OP (guarda abaixo). Estado limpo = `db reset`.
--   - Nenhuma RPC funcional e usada (a P1 nao tem RPC): os dados sao inseridos
--     DIRETAMENTE, como fixture, inclusive a trilha.
--   - Somente dados ficticios; nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('eea00000-0000-0000-0000-0000000000a1',
                'eea00000-0000-0000-0000-0000000000b1')
) as cenario_f5_10_p1_carregado \gset

\if :cenario_f5_10_p1_carregado
do $$
begin
  raise notice '[PASS] cenario F5-10 P1 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('eea00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-10 P1 Alfa'),
  ('eea00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-10 P1 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades (auth.users + perfil + membership ativa)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('eec00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.alfa.f5-10-p1@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('eec00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.beta.f5-10-p1@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('eec00000-0000-0000-0000-000000000001', 'active'),
  ('eec00000-0000-0000-0000-000000000002', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('eed00000-0000-0000-0000-000000000001', 'eec00000-0000-0000-0000-000000000001',
   'eea00000-0000-0000-0000-0000000000a1', 'active'),
  ('eed00000-0000-0000-0000-000000000002', 'eec00000-0000-0000-0000-000000000002',
   'eea00000-0000-0000-0000-0000000000b1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores SOBERANOS (UUID; nenhuma matricula como identidade)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('eeb00000-0000-0000-0000-000000000001', 'eea00000-0000-0000-0000-0000000000a1'),
  ('eeb00000-0000-0000-0000-000000000002', 'eea00000-0000-0000-0000-0000000000a1'),
  ('eeb00000-0000-0000-0000-0000000000b1', 'eea00000-0000-0000-0000-0000000000b1');

-- ----------------------------------------------------------------------------
-- 4) Ciclos soberanos (1 por organizacao)
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim,
   data_ativacao, version) values
  ('eed10000-0000-0000-0000-0000000000a1', 'eea00000-0000-0000-0000-0000000000a1',
   2036, 1, 'ATIVO', date '2036-01-01', date '2036-03-31', now(), 1),
  ('eed10000-0000-0000-0000-0000000000b1', 'eea00000-0000-0000-0000-0000000000b1',
   2036, 1, 'ATIVO', date '2036-01-01', date '2036-03-31', now(), 1);

-- ----------------------------------------------------------------------------
-- 5) QUOTA soberana (D4/D20): autoridade de limite por (ciclo, tipo)
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycle_goal_limits
  (id, organization_id, cycle_id, tipo, quantidade) values
  ('eef00000-0000-0000-0000-0000000000a1', 'eea00000-0000-0000-0000-0000000000a1',
   'eed10000-0000-0000-0000-0000000000a1', 'NEGOCIO_PROJETO', 2),
  ('eef00000-0000-0000-0000-0000000000a2', 'eea00000-0000-0000-0000-0000000000a1',
   'eed10000-0000-0000-0000-0000000000a1', 'INDIVIDUAL', 1),
  -- Beta tem APENAS NEGOCIO_PROJETO configurado: INDIVIDUAL fica em quota ZERO
  -- (fail-closed) e e usado no teste negativo do validador.
  ('eef00000-0000-0000-0000-0000000000b1', 'eea00000-0000-0000-0000-0000000000b1',
   'eed10000-0000-0000-0000-0000000000b1', 'NEGOCIO_PROJETO', 1);

-- ----------------------------------------------------------------------------
-- 6) Metas, aprovacao e trilha (minimo funcional para provar o schema)
-- ----------------------------------------------------------------------------
insert into public.evaluation_goals
  (id, organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
   status, progresso_percentual, resultado_atual) values
  ('ee900000-0000-0000-0000-000000000001', 'eea00000-0000-0000-0000-0000000000a1',
   'eed10000-0000-0000-0000-0000000000a1', 'eeb00000-0000-0000-0000-000000000001',
   'NEGOCIO_PROJETO', 'Meta de negocio ficticia (P1)', 'KPI ficticio', '100 unidades',
   'EM_ANDAMENTO', 40, '40 unidades'),
  ('ee900000-0000-0000-0000-000000000002', 'eea00000-0000-0000-0000-0000000000a1',
   'eed10000-0000-0000-0000-0000000000a1', 'eeb00000-0000-0000-0000-000000000002',
   'INDIVIDUAL', 'Meta individual ficticia (P1)', 'KPI individual', '10 entregas',
   'EM_ANDAMENTO', 0, null);

insert into public.evaluation_goal_approvals
  (id, organization_id, goal_id, papel, actor_membership_id, motivo) values
  ('ee800000-0000-0000-0000-000000000001', 'eea00000-0000-0000-0000-0000000000a1',
   'ee900000-0000-0000-0000-000000000001', 'COORDENADOR',
   'eed00000-0000-0000-0000-000000000001', 'Aprovacao de fixture (P1)');

insert into public.evaluation_goal_events
  (id, organization_id, goal_id, entity_type, event_type, effective_date, reason,
   before_value, after_value, payload_hash, result_entity_id,
   actor_user_profile_id, actor_membership_id, operation_id) values
  ('ee700000-0000-0000-0000-000000000001', 'eea00000-0000-0000-0000-0000000000a1',
   'ee900000-0000-0000-0000-000000000001', 'evaluation_goal', 'CRIADA', now(),
   'Criacao de fixture (P1)', null,
   jsonb_build_object('status', 'EM_ANDAMENTO', 'version', 0),
   encode(sha256(convert_to('{"fixture":"f5-10-p1","event":"CRIADA"}', 'UTF8')), 'hex'),
   'ee900000-0000-0000-0000-000000000001',
   'eec00000-0000-0000-0000-000000000001', 'eed00000-0000-0000-0000-000000000001',
   'ee600000-0000-0000-0000-000000000001');

-- ----------------------------------------------------------------------------
-- 7) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_memb     int;
  v_colabs   int;
  v_ciclos   int;
  v_quota    int;
  v_metas    int;
  v_aprov    int;
  v_eventos  int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('eea00000-0000-0000-0000-0000000000a1',
                'eea00000-0000-0000-0000-0000000000b1');
  select count(*) into v_memb from public.user_organization_memberships
   where id in ('eed00000-0000-0000-0000-000000000001',
                'eed00000-0000-0000-0000-000000000002') and status = 'active';
  select count(*) into v_colabs from public.collaborators
   where id in ('eeb00000-0000-0000-0000-000000000001',
                'eeb00000-0000-0000-0000-000000000002',
                'eeb00000-0000-0000-0000-0000000000b1');
  select count(*) into v_ciclos from public.evaluation_cycles
   where id in ('eed10000-0000-0000-0000-0000000000a1',
                'eed10000-0000-0000-0000-0000000000b1');
  select count(*) into v_quota from public.evaluation_cycle_goal_limits
   where organization_id in ('eea00000-0000-0000-0000-0000000000a1',
                             'eea00000-0000-0000-0000-0000000000b1');
  select count(*) into v_metas from public.evaluation_goals
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_eventos from public.evaluation_goal_events
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1';

  if v_orgs <> 2 or v_memb <> 2 or v_colabs <> 3 or v_ciclos <> 2
     or v_quota <> 3 or v_metas <> 2 or v_aprov <> 1 or v_eventos <> 1 then
    raise exception
      '[FAIL] cenario F5-10 P1 incompleto (orgs=%, memberships=%, colabs=%, ciclos=%, quota=%, metas=%, aprovacoes=%, eventos=%)',
      v_orgs, v_memb, v_colabs, v_ciclos, v_quota, v_metas, v_aprov, v_eventos;
  end if;

  raise notice '[PASS] cenario F5-10 P1: 2 orgs, 2 memberships ativas, 3 colaboradores soberanos, 2 ciclos, 3 quotas (Alfa 2+1, Beta 1), 2 metas, 1 aprovacao e 1 evento na trilha';
end $$;

\endif
