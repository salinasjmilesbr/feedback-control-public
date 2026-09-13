-- ============================================================================
-- F5-10 P2 (Issue #212): cenario da P2 - OPERACOES SOBERANAS de METAS
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md (D1-D25; §7 lifecycle, §10, §12, §19 P2)
-- e migration `20260923000000_f5_10_p2_goals_rpc.sql`.
--
-- Fixture ISOLADA (prefixo `f0`) das fixtures das fases anteriores
-- (P1 = `ee`, P5 F5-09 = `ec`, P4 = `eb`, P9 = `ed`, F5-09 P2 = `e9`):
--   - Alfa (`...a1`) e Beta (`...b1`) com atores proprios;
--   - a1 = ator Alfa com membership ATIVA (executa as operacoes soberanas);
--   - a2 = ator de OUTRO tenant (Beta) — prova de isolamento;
--   - a3 = ator Alfa com membership DISABLED — prova fail-closed;
--   - a4 = ator Alfa com perfil DISABLED (membership ativa) — prova que o PERFIL
--     ativo e exigido, nao apenas a membership (o CHECK da tabela so admite
--     `active`/`disabled`);
--   - 3 colaboradores SOBERANOS (2 em Alfa, 1 em Beta);
--   - Alfa tem DOIS ciclos: um `ATIVO` (operacoes mutaveis) e um `ENCERRADO`
--     (prova que criar/editar/progredir/finalizar exigem ciclo ATIVO, enquanto
--     revisar/excluir sao historicas e NAO o exigem — matriz do §10/D12);
--   - Beta tem apenas `NEGOCIO_PROJETO` configurado: `INDIVIDUAL` fica em quota
--     ZERO (fail-closed) e e usado no teste negativo;
--   - NAO existe NENHUMA aprovacao na fixture: a P2 nao cria, le ou exige
--     aprovacao (P3) — o validador prova que nada e criado incidentalmente.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: a trilha `evaluation_goal_events` e append-only protegida no
--     banco (DELETE/TRUNCATE negados por trigger, P1) e as FKs sao ON DELETE
--     RESTRICT — o cenario NAO pode ser apagado e recriado. Reexecucao e NO-OP
--     (guarda abaixo). Estado limpo = `db reset`.
--   - Nenhuma RPC de meta e chamada aqui: este arquivo SO cria a fixture; as
--     mutacoes soberanas sao exercitadas pelo validador 22.
--   - Somente dados ficticios; nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('f0a00000-0000-0000-0000-0000000000a1',
                'f0a00000-0000-0000-0000-0000000000b1')
) as cenario_f5_10_p2_carregado \gset

\if :cenario_f5_10_p2_carregado
do $$
begin
  raise notice '[PASS] cenario F5-10 P2 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f0a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-10 P2 Alfa'),
  ('f0a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-10 P2 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades (auth.users + perfil + membership)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f0c00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.alfa.f5-10-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f0c00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.beta.f5-10-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f0c00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.disabled.f5-10-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f0c00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfil.disabled.f5-10-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('f0c00000-0000-0000-0000-000000000001', 'active'),
  ('f0c00000-0000-0000-0000-000000000002', 'active'),
  ('f0c00000-0000-0000-0000-000000000003', 'active'),
  ('f0c00000-0000-0000-0000-000000000004', 'disabled');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('f0d00000-0000-0000-0000-000000000001', 'f0c00000-0000-0000-0000-000000000001',
   'f0a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f0d00000-0000-0000-0000-000000000002', 'f0c00000-0000-0000-0000-000000000002',
   'f0a00000-0000-0000-0000-0000000000b1', 'active'),
  ('f0d00000-0000-0000-0000-000000000003', 'f0c00000-0000-0000-0000-000000000003',
   'f0a00000-0000-0000-0000-0000000000a1', 'disabled'),
  ('f0d00000-0000-0000-0000-000000000004', 'f0c00000-0000-0000-0000-000000000004',
   'f0a00000-0000-0000-0000-0000000000a1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores SOBERANOS (UUID; nenhuma matricula como identidade)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f0b00000-0000-0000-0000-000000000001', 'f0a00000-0000-0000-0000-0000000000a1'),
  ('f0b00000-0000-0000-0000-000000000002', 'f0a00000-0000-0000-0000-0000000000a1'),
  ('f0b00000-0000-0000-0000-0000000000b1', 'f0a00000-0000-0000-0000-0000000000b1');

-- ----------------------------------------------------------------------------
-- 4) Ciclos soberanos: um ATIVO e um ENCERRADO em Alfa; um ATIVO em Beta
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim,
   data_ativacao, data_encerramento, version) values
  ('f0d10000-0000-0000-0000-0000000000a1', 'f0a00000-0000-0000-0000-0000000000a1',
   2037, 1, 'ATIVO', date '2037-01-01', date '2037-03-31', now(), null, 1),
  ('f0d10000-0000-0000-0000-0000000000a2', 'f0a00000-0000-0000-0000-0000000000a1',
   2035, 1, 'ENCERRADO', date '2035-07-01', date '2035-09-30', now(), now(), 3),
  ('f0d10000-0000-0000-0000-0000000000b1', 'f0a00000-0000-0000-0000-0000000000b1',
   2037, 1, 'ATIVO', date '2037-01-01', date '2037-03-31', now(), null, 1);

-- ----------------------------------------------------------------------------
-- 5) QUOTA soberana (D4/D20) — autoridade de limite por (ciclo, tipo)
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycle_goal_limits
  (id, organization_id, cycle_id, tipo, quantidade) values
  ('f0f00000-0000-0000-0000-0000000000a1', 'f0a00000-0000-0000-0000-0000000000a1',
   'f0d10000-0000-0000-0000-0000000000a1', 'NEGOCIO_PROJETO', 2),
  ('f0f00000-0000-0000-0000-0000000000a2', 'f0a00000-0000-0000-0000-0000000000a1',
   'f0d10000-0000-0000-0000-0000000000a1', 'INDIVIDUAL', 1),
  ('f0f00000-0000-0000-0000-0000000000a3', 'f0a00000-0000-0000-0000-0000000000a1',
   'f0d10000-0000-0000-0000-0000000000a2', 'NEGOCIO_PROJETO', 2),
  -- Beta tem APENAS NEGOCIO_PROJETO: INDIVIDUAL fica em quota ZERO (fail-closed).
  ('f0f00000-0000-0000-0000-0000000000b1', 'f0a00000-0000-0000-0000-0000000000b1',
   'f0d10000-0000-0000-0000-0000000000b1', 'NEGOCIO_PROJETO', 1);

-- ----------------------------------------------------------------------------
-- 6) Metas de FIXTURE do ciclo ENCERRADO (inseridas diretamente: a fixture nao
--    usa RPC) + a trilha correspondente. NENHUMA aprovacao e criada.
--    - `...0009`: finalizada (ATINGIDA, version 1) — prova que revisar/excluir
--      NAO exigem ciclo ATIVO;
--    - `...0008`: viva (EM_ANDAMENTO, version 0) — prova que editar/progredir/
--      finalizar EXIGEM ciclo ATIVO (recusa) e que excluir e permitido.
-- ----------------------------------------------------------------------------
insert into public.evaluation_goals
  (id, organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
   status, resultado_final, atingida, data_fechamento, version) values
  ('f0900000-0000-0000-0000-000000000009', 'f0a00000-0000-0000-0000-0000000000a1',
   'f0d10000-0000-0000-0000-0000000000a2', 'f0b00000-0000-0000-0000-000000000001',
   'NEGOCIO_PROJETO', 'Meta finalizada de fixture (P2)', 'KPI de fixture (P2)',
   '10 entregas ficticias', 'ATINGIDA', 'Fechamento ficticio de fixture (P2)',
   true, now(), 1),
  ('f0900000-0000-0000-0000-000000000008', 'f0a00000-0000-0000-0000-0000000000a1',
   'f0d10000-0000-0000-0000-0000000000a2', 'f0b00000-0000-0000-0000-000000000002',
   'NEGOCIO_PROJETO', 'Meta viva em ciclo ENCERRADO (fixture P2)',
   'KPI de fixture (P2)', '5 entregas ficticias', 'EM_ANDAMENTO', null, null, null, 0);

insert into public.evaluation_goal_events
  (id, organization_id, goal_id, entity_type, event_type, effective_date, reason,
   before_value, after_value, payload_hash, result_entity_id,
   actor_user_profile_id, actor_membership_id, operation_id) values
  ('f0600000-0000-0000-0000-000000000001', 'f0a00000-0000-0000-0000-0000000000a1',
   'f0900000-0000-0000-0000-000000000009', 'evaluation_goal', 'FINALIZADA', now(),
   'Finalizacao de fixture (P2)', null,
   jsonb_build_object('status', 'ATINGIDA', 'version', 1),
   encode(sha256(convert_to('{"fixture":"f5-10-p2","event":"FINALIZADA"}', 'UTF8')), 'hex'),
   'f0900000-0000-0000-0000-000000000009',
   'f0c00000-0000-0000-0000-000000000001', 'f0d00000-0000-0000-0000-000000000001',
   'f0700000-0000-0000-0000-000000000001');

-- ----------------------------------------------------------------------------
-- 7) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_atores   int;
  v_memb     int;
  v_ativos   int;
  v_colabs   int;
  v_ciclos   int;
  v_quota    int;
  v_metas    int;
  v_aprov    int;
  v_eventos  int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('f0a00000-0000-0000-0000-0000000000a1',
                'f0a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_atores from public.user_profiles
   where id::text like 'f0c00000%';
  select count(*) into v_memb from public.user_organization_memberships
   where id::text like 'f0d00000%';
  select count(*) into v_ativos from public.user_organization_memberships
   where id::text like 'f0d00000%' and status = 'active';
  select count(*) into v_colabs from public.collaborators
   where id::text like 'f0b00000%';
  select count(*) into v_ciclos from public.evaluation_cycles
   where id::text like 'f0d10000%';
  select count(*) into v_quota from public.evaluation_cycle_goal_limits
   where id::text like 'f0f00000%';
  select count(*) into v_metas from public.evaluation_goals
   where id::text like 'f0900000%';
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in ('f0a00000-0000-0000-0000-0000000000a1',
                             'f0a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_eventos from public.evaluation_goal_events
   where organization_id in ('f0a00000-0000-0000-0000-0000000000a1',
                             'f0a00000-0000-0000-0000-0000000000b1');

  if v_orgs <> 2 or v_atores <> 4 or v_memb <> 4 or v_ativos <> 3
     or v_colabs <> 3 or v_ciclos <> 3 or v_quota <> 4 or v_metas <> 2
     or v_aprov <> 0 or v_eventos <> 1 then
    raise exception
      '[FAIL] cenario F5-10 P2 incompleto (orgs=%, atores=%, memberships=%, ativas=%, colabs=%, ciclos=%, quotas=%, metas=%, aprovacoes=%, eventos=%)',
      v_orgs, v_atores, v_memb, v_ativos, v_colabs, v_ciclos, v_quota,
      v_metas, v_aprov, v_eventos;
  end if;

  raise notice '[PASS] cenario F5-10 P2: 2 orgs, 4 atores (1 ativo, 1 de outro tenant, 1 membership disabled, 1 perfil disabled), 3 colaboradores, 3 ciclos (Alfa ATIVO + ENCERRADO, Beta ATIVO), 4 quotas, 2 metas de fixture e 1 evento — ZERO aprovacoes';
end $$;

-- ----------------------------------------------------------------------------
-- 8) Guarda de estado limpo para o validador (uma vez por banco)
-- ----------------------------------------------------------------------------
-- O validador 22 MUTA metas (criar/editar/progresso/finalizar/revisar/excluir) e
-- a trilha e APPEND-ONLY: nao existe "reset" do dominio. O CI (e o uso local
-- correto) executa `db reset` antes de cada rodada completa; aqui a guarda falha
-- alto se as organizacoes da fixture ja tiverem mais estado que o da fixture.
do $$
declare
  v_metas int;
  v_evt   int;
begin
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in ('f0a00000-0000-0000-0000-0000000000a1',
                             'f0a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in ('f0a00000-0000-0000-0000-0000000000a1',
                             'f0a00000-0000-0000-0000-0000000000b1');
  if v_metas <> 2 or v_evt <> 1 then
    raise exception
      '[FAIL] estado sujo: as organizacoes da fixture F5-10 P2 ja possuem % meta(s) e % evento(s) — execute `supabase db reset` antes de reexecutar o cenario/validador da P2 (a trilha de metas e append-only por contrato)',
      v_metas, v_evt;
  end if;
  raise notice '[PASS] cenario F5-10 P2: estado limpo (2 metas de fixture, 1 evento, 0 aprovacoes) — pronto para o validador 22';
end $$;

\endif
