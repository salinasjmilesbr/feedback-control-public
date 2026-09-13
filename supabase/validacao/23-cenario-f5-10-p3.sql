-- ============================================================================
-- F5-10 P3 (Issue #214): cenario da P3 — APROVACOES e INVALIDACAO de metas
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md (D1-D25; §7 lifecycle, §9 aprovacoes/
-- legitimidade/matriz D19, §12 concorrencia, §19 P3) e migration
-- `20260924000000_f5_10_p3_approvals_rpc.sql`.
--
-- Fixture ISOLADA (prefixo `f1`) das demais (P1 = `ee`, P2 = `f0`, F5-09 P2 =
-- `e9`, P9 = `ed`): 2 organizacoes, 8 identidades, 7 colaboradores, 5 metas e o
-- SNAPSHOT CONGELADO de participantes (F5-06) que a P3 CONSOME.
--
-- DECISAO DE FIXTURE (declarada): o snapshot congelado e inserido DIRETAMENTE como
-- DADO (as tabelas `evaluations`/`evaluation_participants` sao a estrutura
-- congelada que a P3 le). A MATERIALIZACAO oficial do snapshot e da F5-06
-- (`evaluation_criar` + `evaluation_snapshot_participantes`, que exigem a
-- estrutura F3 viva + F3-08) e NAO e reimplementada nem simulada aqui — a P3 nao
-- decide nem produz o snapshot, apenas o consome.
--
-- Atores (perfil -> colaborador):
--   a1 -> c1 : GESTAO_CADEIA ORIGINAL da avaliacao do dono (GERENTE)
--   a2 -> c3 : GESTAO_DIRETA ORIGINAL distinta (COORDENADOR)
--   a3 -> c2 : OWNER da meta (dono) — NAO ocupa papel congelado
--   a4 -> c5 : fora do snapshot original (tem apenas ocorrencia POSTERIOR de
--              GESTAO_CADEIA em EV1 — prova que overlays nao transferem autoridade)
--   a5       : membership ativa SEM vinculo de colaborador (fail-closed)
--   a6       : membership DISABLED
--   a7       : perfil DISABLED (membership ativa)
--   ab -> cb : ator de OUTRO tenant (Beta)
--
-- Avaliacoes congeladas:
--   EV1 (dono c2): GESTAO_CADEIA = c1 (2026-01-01) + GESTAO_DIRETA = c3 (2026-01-01)
--                  + overlay POSTERIOR de GESTAO_CADEIA = c5 (2026-06-01)
--   EV2 (dono c4): SOMENTE GESTAO_CADEIA = c1 (nao existe GESTAO_DIRETA distinta)
--   EV3 (dono c4): CANCELADA (deve ser IGNORADA na resolucao)
--   EV4 (dono c6): SEM participantes
--
-- Metas (todas EM_ANDAMENTO, version 0, com evento CRIADA de fixture):
--   G1 -> c2 (EV1: os dois papeis)      G2 -> c4 (EV2: so cadeia)
--   G3 -> c5 (sem avaliacao)            G4 -> c6 (avaliacao sem participantes)
--   G5 -> colaborador de Beta (cross-tenant)
--
-- Regras: EXECUTAR SOMENTE no Supabase local; INSERT-ONCE (reexecucao NO-OP);
-- estado limpo = `db reset`; somente dados ficticios.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('f1a00000-0000-0000-0000-0000000000a1',
                'f1a00000-0000-0000-0000-0000000000b1')
) as cenario_f5_10_p3_carregado \gset

\if :cenario_f5_10_p3_carregado
do $$
begin
  raise notice '[PASS] cenario F5-10 P3 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f1a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-10 P3 Alfa'),
  ('f1a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-10 P3 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades (auth.users + perfil + membership)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f1c00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gerente.alfa.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f1c00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'coordenador.alfa.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f1c00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'owner.alfa.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f1c00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'fora.do.snapshot.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f1c00000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sem.vinculo.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f1c00000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.disabled.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f1c00000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfil.disabled.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f1c00000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'owner.c4.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f1c00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.beta.f5-10-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('f1c00000-0000-0000-0000-000000000001', 'active'),
  ('f1c00000-0000-0000-0000-000000000002', 'active'),
  ('f1c00000-0000-0000-0000-000000000003', 'active'),
  ('f1c00000-0000-0000-0000-000000000004', 'active'),
  ('f1c00000-0000-0000-0000-000000000005', 'active'),
  ('f1c00000-0000-0000-0000-000000000006', 'active'),
  ('f1c00000-0000-0000-0000-000000000007', 'disabled'),
  ('f1c00000-0000-0000-0000-000000000008', 'active'),
  ('f1c00000-0000-0000-0000-0000000000b1', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('f1d00000-0000-0000-0000-000000000001', 'f1c00000-0000-0000-0000-000000000001',
   'f1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f1d00000-0000-0000-0000-000000000002', 'f1c00000-0000-0000-0000-000000000002',
   'f1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f1d00000-0000-0000-0000-000000000003', 'f1c00000-0000-0000-0000-000000000003',
   'f1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f1d00000-0000-0000-0000-000000000004', 'f1c00000-0000-0000-0000-000000000004',
   'f1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f1d00000-0000-0000-0000-000000000005', 'f1c00000-0000-0000-0000-000000000005',
   'f1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f1d00000-0000-0000-0000-000000000006', 'f1c00000-0000-0000-0000-000000000006',
   'f1a00000-0000-0000-0000-0000000000a1', 'disabled'),
  ('f1d00000-0000-0000-0000-000000000007', 'f1c00000-0000-0000-0000-000000000007',
   'f1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f1d00000-0000-0000-0000-000000000008', 'f1c00000-0000-0000-0000-000000000008',
   'f1a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f1d00000-0000-0000-0000-0000000000b1', 'f1c00000-0000-0000-0000-0000000000b1',
   'f1a00000-0000-0000-0000-0000000000b1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores SOBERANOS (UUID) + status vigente
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f1b00000-0000-0000-0000-000000000001', 'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1b00000-0000-0000-0000-000000000002', 'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1b00000-0000-0000-0000-000000000003', 'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1b00000-0000-0000-0000-000000000004', 'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1b00000-0000-0000-0000-000000000005', 'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1b00000-0000-0000-0000-000000000006', 'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1b00000-0000-0000-0000-0000000000b1', 'f1a00000-0000-0000-0000-0000000000b1');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('f1b00000-0000-0000-0000-000000000001', 'active', '2025-01-01T00:00:00Z'),
  ('f1b00000-0000-0000-0000-000000000002', 'active', '2025-01-01T00:00:00Z'),
  ('f1b00000-0000-0000-0000-000000000003', 'active', '2025-01-01T00:00:00Z'),
  ('f1b00000-0000-0000-0000-000000000004', 'active', '2025-01-01T00:00:00Z'),
  ('f1b00000-0000-0000-0000-000000000005', 'active', '2025-01-01T00:00:00Z'),
  ('f1b00000-0000-0000-0000-000000000006', 'active', '2025-01-01T00:00:00Z'),
  ('f1b00000-0000-0000-0000-0000000000b1', 'active', '2025-01-01T00:00:00Z');

-- Vinculo soberano membro x colaborador (F5-02): a5 SEM vinculo (fail-closed);
-- a7 (perfil disabled) tambem sem vinculo — o perfil ja e revalidado antes.
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status) values
  ('f1e00000-0000-0000-0000-000000000001', 'f1d00000-0000-0000-0000-000000000001',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000001', 'active'),
  ('f1e00000-0000-0000-0000-000000000002', 'f1d00000-0000-0000-0000-000000000002',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000003', 'active'),
  ('f1e00000-0000-0000-0000-000000000003', 'f1d00000-0000-0000-0000-000000000003',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000002', 'active'),
  ('f1e00000-0000-0000-0000-000000000004', 'f1d00000-0000-0000-0000-000000000004',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000005', 'active'),
  ('f1e00000-0000-0000-0000-0000000000b1', 'f1d00000-0000-0000-0000-0000000000b1',
   'f1a00000-0000-0000-0000-0000000000b1', 'f1b00000-0000-0000-0000-0000000000b1', 'active'),
  -- a8 (novo, F5-10 P4) -> colaborador `...0004`: e o DONO da meta
  -- `f1000000-...0002`, que o validador 24 muta; sem este vinculo UNICO o gate
  -- funcional da P4 negaria a operacao (SELF).
  ('f1e00000-0000-0000-0000-000000000008', 'f1d00000-0000-0000-0000-000000000008',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000004', 'active');

-- ----------------------------------------------------------------------------
-- 3-bis) AUTORIZACAO da fixture (F5-10 P4 / D6/D7): roles customizadas por
--        tenant com capabilities JA EXISTENTES do catalogo (`goal.read`,
--        `goal.write`, `goal.approve`, `cycle.manage`) — nenhuma capability
--        nova. Insercao DIRETA (dado da fixture, sem RPC), no mesmo padrao da
--        fixture da P2 (o gate funcional da P4 exige a concessao EXPLICITA):
--          - `metas-dono-p3-alfa`: goal.read + goal.write -> DONOS das metas que
--            o validador muta (a3 -> colaborador `...0002`, a4 -> `...0005`,
--            a8 -> `...0004`);
--          - `metas-dono-p3-beta`: goal.read + goal.write -> ator de Beta (a
--            integridade cross-tenant da F4-01 exige role do MESMO tenant);
--          - `metas-aprovador-p3`: goal.read + goal.approve -> a1 (GERENTE
--            congelado) e a2 (COORDENADOR congelado) e TAMBEM a3/a5, que sao os
--            atores dos testes NEGATIVOS de aprovacao: sem a capability o gate
--            da P4 negaria ANTES da resolucao do papel congelado e a mensagem
--            provada deixaria de ser a da relacao/vínculo;
--          - `ciclo-admin-p3`: cycle.manage -> a1 (D21: `meta_definir_limites_do_
--            ciclo` continua operacao ADMINISTRATIVA de ciclo).
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('f1c90000-0000-0000-0000-0000000000a1', 'metas-dono-p3-alfa', 'active', false,
   'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1c90000-0000-0000-0000-0000000000a2', 'metas-aprovador-p3', 'active', false,
   'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1c90000-0000-0000-0000-0000000000a3', 'ciclo-admin-p3', 'active', false,
   'f1a00000-0000-0000-0000-0000000000a1'),
  ('f1c90000-0000-0000-0000-0000000000b1', 'metas-dono-p3-beta', 'active', false,
   'f1a00000-0000-0000-0000-0000000000b1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id in ('f1c90000-0000-0000-0000-0000000000a1',
                 'f1c90000-0000-0000-0000-0000000000b1')
   and c.code in ('goal.read', 'goal.write')
union all
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'f1c90000-0000-0000-0000-0000000000a2'
   and c.code in ('goal.read', 'goal.approve')
union all
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'f1c90000-0000-0000-0000-0000000000a3'
   and c.code = 'cycle.manage';

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f1ca0000-0000-0000-0000-000000000003', 'f1d00000-0000-0000-0000-000000000003',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a1',
   'active', 'f1c00000-0000-0000-0000-000000000003'),
  ('f1ca0000-0000-0000-0000-000000000004', 'f1d00000-0000-0000-0000-000000000004',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a1',
   'active', 'f1c00000-0000-0000-0000-000000000003'),
  ('f1ca0000-0000-0000-0000-000000000008', 'f1d00000-0000-0000-0000-000000000008',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a1',
   'active', 'f1c00000-0000-0000-0000-000000000003'),
  ('f1ca0000-0000-0000-0000-0000000000b1', 'f1d00000-0000-0000-0000-0000000000b1',
   'f1a00000-0000-0000-0000-0000000000b1', 'f1c90000-0000-0000-0000-0000000000b1',
   'active', 'f1c00000-0000-0000-0000-0000000000b1'),
  ('f1ca0000-0000-0000-0000-000000000001', 'f1d00000-0000-0000-0000-000000000001',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a2',
   'active', 'f1c00000-0000-0000-0000-000000000003'),
  ('f1ca0000-0000-0000-0000-000000000002', 'f1d00000-0000-0000-0000-000000000002',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a2',
   'active', 'f1c00000-0000-0000-0000-000000000003'),
  ('f1ca0000-0000-0000-0000-000000000013', 'f1d00000-0000-0000-0000-000000000003',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a2',
   'active', 'f1c00000-0000-0000-0000-000000000003'),
  -- a4 (OVERLAY POSTERIOR de GESTAO_CADEIA em M6) tambem recebe `goal.approve`:
  -- assim o teste NEGATIVO do bloco I do validador 24 prova a recusa pela
  -- RELACAO CONGELADA (`F5_10_CONFLICT`) e nao pela ausencia de capability.
  ('f1ca0000-0000-0000-0000-000000000014', 'f1d00000-0000-0000-0000-000000000004',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a2',
   'active', 'f1c00000-0000-0000-0000-000000000003'),
  ('f1ca0000-0000-0000-0000-000000000015', 'f1d00000-0000-0000-0000-000000000005',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a2',
   'active', 'f1c00000-0000-0000-0000-000000000003'),
  ('f1ca0000-0000-0000-0000-000000000021', 'f1d00000-0000-0000-0000-000000000001',
   'f1a00000-0000-0000-0000-0000000000a1', 'f1c90000-0000-0000-0000-0000000000a3',
   'active', 'f1c00000-0000-0000-0000-000000000003');

-- ----------------------------------------------------------------------------
-- 4) Configuracao baseline versionada (F5-06 D5) + ciclos ATIVOS
-- ----------------------------------------------------------------------------
do $$
declare
  v_cfg_alfa uuid;
  v_cfg_beta uuid;
begin
  v_cfg_alfa := public.evaluation_config_bootstrap(
    'f1a00000-0000-0000-0000-0000000000a1',
    'f1c00000-0000-0000-0000-000000000001');
  v_cfg_beta := public.evaluation_config_bootstrap(
    'f1a00000-0000-0000-0000-0000000000b1',
    'f1c00000-0000-0000-0000-0000000000b1');
  if v_cfg_alfa is null or v_cfg_beta is null then
    raise exception '[FAIL] cenario F5-10 P3: bootstrap de configuracao nao retornou versao';
  end if;

  insert into public.evaluation_cycles
    (id, organization_id, ano, numero, status, data_inicio, data_fim,
     data_ativacao, config_version_id, version) values
    ('f1f00000-0000-0000-0000-0000000000a1', 'f1a00000-0000-0000-0000-0000000000a1',
     2038, 1, 'ATIVO', date '2038-01-01', date '2038-06-30', now(), v_cfg_alfa, 1),
    ('f1f00000-0000-0000-0000-0000000000b1', 'f1a00000-0000-0000-0000-0000000000b1',
     2038, 1, 'ATIVO', date '2038-01-01', date '2038-06-30', now(), v_cfg_beta, 1);

  -- Avaliacoes do dono (a P3 le o snapshot; a materializacao oficial e da F5-06).
  insert into public.evaluations
    (id, organization_id, cycle_id, evaluated_collaborator_id, status,
     config_version_id, version, motivo_cancelamento, data_cancelamento) values
    ('f1200000-0000-0000-0000-000000000001', 'f1a00000-0000-0000-0000-0000000000a1',
     'f1f00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000002',
     'PRONTA_PARA_FEEDBACK', v_cfg_alfa, 0, null, null),
    ('f1200000-0000-0000-0000-000000000002', 'f1a00000-0000-0000-0000-0000000000a1',
     'f1f00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000004',
     'PRONTA_PARA_FEEDBACK', v_cfg_alfa, 0, null, null),
    -- CANCELADA do MESMO dono de EV2: deve ser IGNORADA pela resolucao (D9).
    ('f1200000-0000-0000-0000-000000000003', 'f1a00000-0000-0000-0000-0000000000a1',
     'f1f00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000004',
     'CANCELADA', v_cfg_alfa, 0, 'cancelamento ficticio de fixture (P3)', now()),
    -- Avaliacao SEM participantes (fail-closed na derivacao).
    ('f1200000-0000-0000-0000-000000000004', 'f1a00000-0000-0000-0000-0000000000a1',
     'f1f00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000006',
     'PRONTA_PARA_FEEDBACK', v_cfg_alfa, 0, null, null);
end $$;

-- ----------------------------------------------------------------------------
-- 5) SNAPSHOT CONGELADO de participantes (dado da fixture; ver cabecalho)
-- ----------------------------------------------------------------------------
insert into public.evaluation_participants
  (id, organization_id, evaluation_id, role_type, collaborator_id, origem,
   valid_from, status) values
  -- EV1 (dono c2): cadeia = c1, direta = c3 (distinta) — par ORIGINAL.
  ('f1300000-0000-0000-0000-000000000001', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1200000-0000-0000-0000-000000000001', 'GESTAO_CADEIA', 'f1b00000-0000-0000-0000-000000000001',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  ('f1300000-0000-0000-0000-000000000002', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1200000-0000-0000-0000-000000000001', 'GESTAO_DIRETA', 'f1b00000-0000-0000-0000-000000000003',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  -- OVERLAY POSTERIOR de GESTAO_CADEIA (c5) em EV1: NAO transfere autoridade
  -- (a ocorrencia original continua sendo c1 pela regra 4 do §9.1).
  ('f1300000-0000-0000-0000-000000000003', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1200000-0000-0000-0000-000000000001', 'GESTAO_CADEIA', 'f1b00000-0000-0000-0000-000000000005',
   'SUBSTITUICAO_TEMPORARIA', '2026-06-01T00:00:00Z', 'active'),
  -- EV2 (dono c4): SOMENTE cadeia (nao existe GESTAO_DIRETA distinta).
  ('f1300000-0000-0000-0000-000000000004', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1200000-0000-0000-0000-000000000002', 'GESTAO_CADEIA', 'f1b00000-0000-0000-0000-000000000001',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active');

-- ----------------------------------------------------------------------------
-- 6) QUOTA soberana + metas de fixture + trilha de criacao
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycle_goal_limits
  (id, organization_id, cycle_id, tipo, quantidade) values
  -- Dominio do contrato: 0..3 (CHECK da P1). Alfa usa 3 de negocio + 1 individual.
  ('f1500000-0000-0000-0000-0000000000a1', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1f00000-0000-0000-0000-0000000000a1', 'NEGOCIO_PROJETO', 3),
  ('f1500000-0000-0000-0000-0000000000a2', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1f00000-0000-0000-0000-0000000000a1', 'INDIVIDUAL', 1),
  ('f1500000-0000-0000-0000-0000000000b1', 'f1a00000-0000-0000-0000-0000000000b1',
   'f1f00000-0000-0000-0000-0000000000b1', 'NEGOCIO_PROJETO', 1);

insert into public.evaluation_goals
  (id, organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
   status, version) values
  ('f1000000-0000-0000-0000-000000000001', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1f00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000002',
   'NEGOCIO_PROJETO', 'Meta do dono com os DOIS papeis congelados (P3)',
   'KPI de fixture (P3)', '100 unidades (P3)', 'EM_ANDAMENTO', 0),
  ('f1000000-0000-0000-0000-000000000002', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1f00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000004',
   'NEGOCIO_PROJETO', 'Meta com SOMENTE papel de cadeia (P3)',
   'KPI de fixture (P3)', '50 unidades (P3)', 'EM_ANDAMENTO', 0),
  ('f1000000-0000-0000-0000-000000000003', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1f00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000005',
   'NEGOCIO_PROJETO', 'Meta sem avaliacao do dono (P3)',
   'KPI de fixture (P3)', '30 unidades (P3)', 'EM_ANDAMENTO', 0),
  ('f1000000-0000-0000-0000-000000000004', 'f1a00000-0000-0000-0000-0000000000a1',
   'f1f00000-0000-0000-0000-0000000000a1', 'f1b00000-0000-0000-0000-000000000006',
   'INDIVIDUAL', 'Meta com avaliacao sem participantes (P3)',
   'KPI de fixture (P3)', '20 unidades (P3)', 'EM_ANDAMENTO', 0),
  ('f1000000-0000-0000-0000-0000000000b1', 'f1a00000-0000-0000-0000-0000000000b1',
   'f1f00000-0000-0000-0000-0000000000b1', 'f1b00000-0000-0000-0000-0000000000b1',
   'NEGOCIO_PROJETO', 'Meta do tenant Beta (P3)',
   'KPI de fixture (P3)', '10 unidades (P3)', 'EM_ANDAMENTO', 0);

insert into public.evaluation_goal_events
  (id, organization_id, goal_id, entity_type, event_type, effective_date, reason,
   before_value, after_value, payload_hash, result_entity_id,
   actor_user_profile_id, actor_membership_id, operation_id)
select
  ('f1400000-0000-0000-0000-00000000000' || lpad(v_ord::text, 1, '0'))::uuid,
  g.organization_id, g.id, 'evaluation_goal', 'CRIADA', now(),
  'Criacao de fixture (P3)', null,
  jsonb_build_object('status', 'EM_ANDAMENTO', 'version', 0),
  encode(sha256(convert_to('{"fixture":"f5-10-p3","goal":' || v_ord || '}', 'UTF8')), 'hex'),
  g.id,
  case when g.organization_id = 'f1a00000-0000-0000-0000-0000000000b1'
       then 'f1c00000-0000-0000-0000-0000000000b1'::uuid
       else 'f1c00000-0000-0000-0000-000000000001'::uuid end,
  case when g.organization_id = 'f1a00000-0000-0000-0000-0000000000b1'
       then 'f1d00000-0000-0000-0000-0000000000b1'::uuid
       else 'f1d00000-0000-0000-0000-000000000001'::uuid end,
  ('f1600000-0000-0000-0000-00000000000' || lpad(v_ord::text, 1, '0'))::uuid
  from (
    select g.*, row_number() over (order by g.id) as v_ord
      from public.evaluation_goals g
     where g.id::text like 'f1000000%'
  ) g;

-- ----------------------------------------------------------------------------
-- 7) Consistencia da fixture
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_atores   int;
  v_memb     int;
  v_colabs   int;
  v_ciclos   int;
  v_quota    int;
  v_metas    int;
  v_avaliac  int;
  v_partic   int;
  v_eventos  int;
  v_aprov    int;
  v_links    int;
  v_roles    int;
  v_assign   int;
  v_vinculo  uuid;
begin
  select count(*) into v_orgs from public.organizations
   where id::text like 'f1a00000%';
  select count(*) into v_atores from public.user_profiles where id::text like 'f1c00000%';
  select count(*) into v_memb from public.user_organization_memberships
   where id::text like 'f1d00000%';
  select count(*) into v_colabs from public.collaborators where id::text like 'f1b00000%';
  select count(*) into v_links from public.membership_collaborator_links
   where id::text like 'f1e00000%' and status = 'active';
  select count(*) into v_roles from public.access_roles where id::text like 'f1c90000%';
  select count(*) into v_assign from public.membership_access_role_assignments
   where id::text like 'f1ca0000%' and status = 'active';
  select count(*) into v_ciclos from public.evaluation_cycles where id::text like 'f1f00000%';
  select count(*) into v_quota from public.evaluation_cycle_goal_limits
   where id::text like 'f1500000%';
  select count(*) into v_metas from public.evaluation_goals where id::text like 'f1000000%';
  select count(*) into v_avaliac from public.evaluations where id::text like 'f1200000%';
  select count(*) into v_partic from public.evaluation_participants
   where id::text like 'f1300000%';
  select count(*) into v_eventos from public.evaluation_goal_events
   where organization_id in ('f1a00000-0000-0000-0000-0000000000a1',
                             'f1a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in ('f1a00000-0000-0000-0000-0000000000a1',
                             'f1a00000-0000-0000-0000-0000000000b1');

  -- O gate da P4 (F5-10 P4 §10) exige CAPABILITY EFETIVA + relacao SELF: a
  -- fixture prova que os atores de MUTACAO resolvem o dono da meta manipulada.
  if public.f5_10_vinculo_meta_do_ator(
       'f1c00000-0000-0000-0000-000000000003', 'f1a00000-0000-0000-0000-0000000000a1')
       is distinct from 'f1b00000-0000-0000-0000-000000000002'::uuid
     or public.f5_10_vinculo_meta_do_ator(
       'f1c00000-0000-0000-0000-000000000008', 'f1a00000-0000-0000-0000-0000000000a1')
       is distinct from 'f1b00000-0000-0000-0000-000000000004'::uuid then
    raise exception '[FAIL] cenario F5-10 P3: vinculo soberano UNICO nao resolve o dono esperado (a3 -> ...0002; a8 -> ...0004)';
  end if;
  if not public.f5_10_ator_valido_meta(
       'f1c00000-0000-0000-0000-000000000001', 'f1a00000-0000-0000-0000-0000000000a1',
       'goal.approve')
     or not public.f5_10_ator_valido_meta(
       'f1c00000-0000-0000-0000-000000000003', 'f1a00000-0000-0000-0000-0000000000a1',
       'goal.write') then
    raise exception '[FAIL] cenario F5-10 P3: capability efetiva ausente (a1 goal.approve / a3 goal.write)';
  end if;

  if v_orgs <> 2 or v_atores <> 9 or v_memb <> 9 or v_colabs <> 7 or v_links <> 6
     or v_roles <> 4 or v_assign <> 10
     or v_ciclos <> 2 or v_quota <> 3 or v_metas <> 5 or v_avaliac <> 4
     or v_partic <> 4 or v_eventos <> 5 or v_aprov <> 0 then
    raise exception
      '[FAIL] cenario F5-10 P3 incompleto (orgs=%, atores=%, memberships=%, colabs=%, links=%, ciclos=%, quota=%, metas=%, avaliacoes=%, participantes=%, eventos=%, aprovacoes=%)',
      v_orgs, v_atores, v_memb, v_colabs, v_links, v_ciclos, v_quota, v_metas,
      v_avaliac, v_partic, v_eventos, v_aprov;
  end if;

  raise notice '[PASS] cenario F5-10 P3: 2 orgs, 9 atores (a8 novo: dono do colaborador ...0004), 7 colaboradores, 6 vinculos, 4 roles com capabilities EXISTENTES (goal.read/write/approve + cycle.manage) e 9 atribuicoes, 2 ciclos ATIVO, 3 quotas (Alfa 3 negocio + 1 individual, Beta 1), 5 metas, 4 avaliacoes (1 CANCELADA, 1 sem participantes), 4 participantes congelados (2 papeis + 1 overlay), 5 eventos de criacao e ZERO aprovacoes';
end $$;

\endif
