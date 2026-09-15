-- ============================================================================
-- F5-11 P1.1 (Issue #242): cenario FOCADO do finding MEDIUM do Codex —
-- COERENCIA perfil <-> membership NA MESMA organizacao.
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-11-desenho-tecnico.md (D1-D16) + §19 (registro da P1.1) e
-- migration corretiva `20260930000000_f5_11_p1_1_coerencia_identidade_observacoes.sql`.
--
-- Fixture ISOLADA (prefixo `fe`) das demais (34/35 usam `fd`): UMA organizacao
-- com TRES identidades distintas, cada uma com a SUA membership NA MESMA
-- organizacao e o SEU colaborador vinculado:
--
--   perfil A -> membership A -> colaborador A   (vinculo ATIVO)
--   perfil B -> membership B -> colaborador B   (vinculo ATIVO)
--   perfil C -> membership C -> colaborador C   (vinculo DISABLED: nao resolve)
--
-- E exatamente o cenario que o Codex descreveu: com dois perfis/memberships na
-- MESMA organizacao, uma escrita tecnica podia gravar o perfil de um com a
-- membership do outro sem que nenhuma constraint reclamasse. O validador 37
-- prova negativamente as 4 combinacoes e positivamente as legitimas.
--
-- A identidade C existe para provar a paridade com o resolvedor canonico
-- (`resolver_collaborator_vinculado`, F5-02 Q4=A/Q6=B): vinculo `disabled` e
-- historico e NAO resolve, portanto informar o colaborador C como
-- `author_collaborator_id` da membership C tem de ser recusado.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: reexecucao e NO-OP (guarda abaixo). Estado limpo = `db reset`.
--   - Nenhuma RPC e usada (a P1/P1.1 nao tem RPC - fronteira preservada).
--   - Somente dados ficticios; nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1 from public.organizations
   where id = 'fea00000-0000-0000-0000-0000000000a1'
) as cenario_f5_11_p1_1_carregado \gset

\if :cenario_f5_11_p1_1_carregado
do $$
begin
  raise notice '[PASS] cenario F5-11 P1.1 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacao sintetica (UMA so: o finding e INTRA-tenant)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('fea00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-11 P1.1 Gama');

-- ----------------------------------------------------------------------------
-- 2) Tres identidades (auth.users + perfil + membership) NA MESMA organizacao
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('fec00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfil.a.f5-11-p1-1@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('fec00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfil.b.f5-11-p1-1@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('fec00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfil.c.f5-11-p1-1@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('fec00000-0000-0000-0000-000000000001', 'active'),
  ('fec00000-0000-0000-0000-000000000002', 'active'),
  ('fec00000-0000-0000-0000-000000000003', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('fed00000-0000-0000-0000-000000000001', 'fec00000-0000-0000-0000-000000000001',
   'fea00000-0000-0000-0000-0000000000a1', 'active'),
  ('fed00000-0000-0000-0000-000000000002', 'fec00000-0000-0000-0000-000000000002',
   'fea00000-0000-0000-0000-0000000000a1', 'active'),
  ('fed00000-0000-0000-0000-000000000003', 'fec00000-0000-0000-0000-000000000003',
   'fea00000-0000-0000-0000-0000000000a1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores soberanos (um por identidade)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('feb00000-0000-0000-0000-000000000001', 'fea00000-0000-0000-0000-0000000000a1'),
  ('feb00000-0000-0000-0000-000000000002', 'fea00000-0000-0000-0000-0000000000a1'),
  ('feb00000-0000-0000-0000-000000000003', 'fea00000-0000-0000-0000-0000000000a1');

-- ----------------------------------------------------------------------------
-- 4) Vinculos membership <-> colaborador (F4-02): A e B ATIVOS, C DISABLED
-- ----------------------------------------------------------------------------
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status)
values
  ('fee00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001',
   'fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001', 'active'),
  ('fee00000-0000-0000-0000-000000000002', 'fed00000-0000-0000-0000-000000000002',
   'fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000002', 'active'),
  ('fee00000-0000-0000-0000-000000000003', 'fed00000-0000-0000-0000-000000000003',
   'fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000003', 'disabled');

-- ----------------------------------------------------------------------------
-- 5) Ciclo soberano ATIVO
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim,
   data_ativacao, version) values
  ('fed10000-0000-0000-0000-0000000000a1', 'fea00000-0000-0000-0000-0000000000a1',
   2038, 1, 'ATIVO', date '2038-01-01', date '2038-03-31', now(), 1);

-- ----------------------------------------------------------------------------
-- 6) Linha de base LEGITIMA (perfil A + membership A + colaborador A)
-- ----------------------------------------------------------------------------
insert into public.evaluation_observations
  (id, organization_id, collaborator_id, cycle_id, tipo, texto,
   comunicado, comunicado_em, comunicado_por_user_profile_id, comunicado_por_membership_id,
   author_user_profile_id, author_membership_id, author_collaborator_id)
values
  ('fe900000-0000-0000-0000-000000000001', 'fea00000-0000-0000-0000-0000000000a1',
   'feb00000-0000-0000-0000-000000000002', 'fed10000-0000-0000-0000-0000000000a1',
   'POSITIVA', 'Observacao ficticia coerente da P1.1',
   true, now(), 'fec00000-0000-0000-0000-000000000001',
   'fed00000-0000-0000-0000-000000000001',
   'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001',
   'feb00000-0000-0000-0000-000000000001');

insert into public.evaluation_observation_events
  (id, organization_id, observation_id, entity_type, event_type, effective_date,
   reason, after_value, payload_hash, result_entity_id,
   actor_user_profile_id, actor_membership_id, operation_id)
values
  ('fe700000-0000-0000-0000-000000000001', 'fea00000-0000-0000-0000-0000000000a1',
   'fe900000-0000-0000-0000-000000000001', 'evaluation_observation', 'CRIADA', now(),
   'Criacao de fixture (P1.1)', jsonb_build_object('tipo', 'POSITIVA'),
   encode(sha256(convert_to('{"fixture":"f5-11-p1-1","event":"CRIADA"}', 'UTF8')), 'hex'),
   'fe900000-0000-0000-0000-000000000001',
   'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001',
   'fe600000-0000-0000-0000-000000000001');

-- ----------------------------------------------------------------------------
-- 7) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org        int;
  v_perfis     int;
  v_memb       int;
  v_memb_mesma int;
  v_colabs     int;
  v_links_ok   int;
  v_links_dis  int;
  v_ciclos     int;
  v_obs        int;
  v_eventos    int;
begin
  select count(*) into v_org from public.organizations
   where id = 'fea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_perfis from public.user_profiles
   where id in ('fec00000-0000-0000-0000-000000000001',
                'fec00000-0000-0000-0000-000000000002',
                'fec00000-0000-0000-0000-000000000003') and status = 'active';
  select count(*) into v_memb from public.user_organization_memberships
   where id in ('fed00000-0000-0000-0000-000000000001',
                'fed00000-0000-0000-0000-000000000002',
                'fed00000-0000-0000-0000-000000000003') and status = 'active';
  -- O ponto do finding: as TRES memberships na MESMA organizacao.
  select count(*) into v_memb_mesma from public.user_organization_memberships
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1' and status = 'active';
  select count(*) into v_colabs from public.collaborators
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_links_ok from public.membership_collaborator_links
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1' and status = 'active';
  select count(*) into v_links_dis from public.membership_collaborator_links
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1' and status = 'disabled';
  select count(*) into v_ciclos from public.evaluation_cycles
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_obs from public.evaluation_observations
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_eventos from public.evaluation_observation_events
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';

  if v_org <> 1 or v_perfis <> 3 or v_memb <> 3 or v_memb_mesma <> 3
     or v_colabs <> 3 or v_links_ok <> 2 or v_links_dis <> 1
     or v_ciclos <> 1 or v_obs <> 1 or v_eventos <> 1 then
    raise exception
      '[FAIL] cenario F5-11 P1.1 incompleto (org=%, perfis=%, memberships=%, memberships_mesma_org=%, colabs=%, links_ativos=%, links_disabled=%, ciclos=%, obs=%, eventos=%)',
      v_org, v_perfis, v_memb, v_memb_mesma, v_colabs, v_links_ok, v_links_dis,
      v_ciclos, v_obs, v_eventos;
  end if;

  raise notice '[PASS] cenario F5-11 P1.1: 1 organizacao, 3 perfis ativos, 3 memberships ATIVAS na MESMA organizacao (A, B e C), 3 colaboradores, 2 vinculos ATIVOS + 1 DISABLED (paridade com o resolvedor), 1 ciclo ATIVO, 1 observacao coerente e 1 evento';
end $$;

\endif
