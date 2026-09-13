-- ============================================================================
-- F5-10 P4 (Issue #216): cenario da P4 — AUTORIZACAO/RLS de metas
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md (§10 autorizacao, §11 RLS x Policy
-- Engine — D22, §7 lifecycle, §9 aprovacoes/legitimidade congelada, §19 P4;
-- D6-D9/D12/D14/D19/D21/D25) e as migrations REAIS da P1/P2/P3
-- (`20260922000000_f5_10_p1_goals_schema.sql`,
--  `20260923000000_f5_10_p2_goals_rpc.sql`,
--  `20260924000000_f5_10_p3_approvals_rpc.sql`).
--
-- Fixture ISOLADA (prefixo `f2`) das fases anteriores: P1 = `ee`, P2 = `f0`,
-- P3 = `f1`, F5-09 P2 = `e9`, P4 F5-09 = `eb`, P5 F5-09 = `ec`, P9 = `ed`.
-- Os preflights das fases anteriores exigem estado limpo por tenant; por isso
-- NENHUM id desta fixture e reutilizado.
--
-- Atores (perfil -> colaborador) e o que cada um PROVA na P4:
--   a1 -> c1 : DONO de metas (goal.write+goal.read via role `f2r1`) — SELF;
--   a2 -> c2 : GESTAO_CADEIA ORIGINAL da avaliacao de M1/M6 (GERENTE
--              congelado) COM `goal.approve`; tambem dono de M5;
--   a3 -> c3 : GESTAO_DIRETA ORIGINAL distinta (COORDENADOR congelado) COM
--              `goal.approve`; dono de M6;
--   a4 -> c4 : GESTOR (na estrutura viva) com `goal.write` mas que NAO e dono
--              de meta de terceiro (negativos 4/5/6) e overlay POSTERIOR de
--              GESTAO_CADEIA em M6 (positivo 9);
--   a5 -> c5 : GESTAO_CADEIA ORIGINAL congelada de M6 SEM `goal.approve`
--              (negativo 8: a relacao existe e a capability nao);
--   a6     : membership/perfil ATIVOS com `goal.approve` e SEM vinculo UNICO de
--              colaborador (negativo 9: capability sem relacao => DENY);
--   a7     : membership REVOGADA (`disabled`) — negativo 2;
--   a8     : perfil `disabled` com membership ativa — negativo 3;
--   a9 -> c6 : TERCEIRO com `goal.read` ISOLADO (sem relacao com meta alguma)
--              — negativo 15/positivo 8 (leitura devolve ZERO);
--   aa -> c7 : GESTOR da HIERARQUIA VIVA (occupation + reporting line) com
--              `goal.approve`, DIVERGENTE do participante congelado —
--              negativo 10;
--   ab -> cb : ator de OUTRO tenant (Beta) — negativo 1;
--   ac -> cc : ator de BETA com role `f2r5` (cycle.manage + goal.read) DONO da
--              meta de Beta — prova de leitura cross-tenant (0 linhas sob RLS);
--   ad     : ator de Alfa com `cycle.manage` (role `f2r3`) — positivo 10
--              (LIMITES continua operacao ADMINISTRATIVA de ciclo).
--
-- Estrutura CONGELADA de fixture (dado; a materializacao oficial e da F5-06):
--   EV1 (dono c1): GESTAO_CADEIA = c2 (2026-01-01) + GESTAO_DIRETA = c3
--                  (2026-01-01) — par ORIGINAL de M1;
--   EV2 (dono c2): SOMENTE GESTAO_CADEIA = c1 — M5 nao tem COORDENADOR;
--   EV3 (dono c3): GESTAO_CADEIA = c5 (ORIGINAL, sem goal.approve) +
--                  GESTAO_DIRETA = c2 (distinta) + OVERLAY POSTERIOR de
--                  GESTAO_CADEIA = c4 (2026-06-01) que NUNCA transfere
--                  autoridade — M6;
--   EV4 (dono c4): status CANCELADA (ignorada na resolucao).
--
-- Metas de FIXTURE (5; inseridas DIRETAMENTE como dado, como faz a P2 — a
-- fixture NAO usa RPC) + 1 evento CRIADA por meta:
--   M1 -> c1, ATIVO,   EM_ANDAMENTO, version 0 (aprovacoes vem do validador);
--   M2 -> c1, ATIVO,   EM_ANDAMENTO, version 0 (SELF: editar/progredir/
--        finalizar/ler);
--   M3 -> c1, ENCERRADO, EM_ANDAMENTO, version 0 (ciclo NAO ATIVO);
--   M4 -> c1, ENCERRADO, excluida = true (mutacao recusada);
--   M6 -> c3, ATIVO,   EM_ANDAMENTO, version 0 (dois papeis congelados +
--        overlay posterior);
--   M7 -> c4, ENCERRADO, NAO_ATINGIDA, version 1 (fechamento coerente);
--   M8 -> cc, ATIVO (Beta), EM_ANDAMENTO, version 0 (cross-tenant);
--   (M5 -> c2, ATIVO, e criada pelo VALIDADOR via RPC `meta_criar` — positivo 1).
--
-- Roles/capabilities (todas EXISTENTES no catalogo; nenhuma capability nova):
--   `f2r1` metas_dono       : goal.read + goal.write               -> a1, a4
--   `f2r2` metas_aprovador  : goal.read + goal.approve             -> a2, a3, a6
--   `f2r3` ciclo_admin      : cycle.manage                          -> ad
--   `f2r4` metas_leitor     : goal.read ISOLADO                     -> a9
--   `f2r5` beta_dono        : cycle.manage + goal.read              -> ac (Beta)
--   `f2r6` metas_aprovador_live : goal.read + goal.approve          -> aa
--   a5 (GESTAO_CADEIA congelada) e a4 (overlay) NAO recebem role alguma.
--
-- Regras: EXECUTAR SOMENTE no Supabase local; INSERT-ONCE (reexecucao NO-OP);
-- estado limpo = `supabase db reset`; somente dados ficticios.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('f2a00000-0000-0000-0000-0000000000a1',
                'f2a00000-0000-0000-0000-0000000000b1')
) as cenario_f5_10_p4_carregado \gset

\if :cenario_f5_10_p4_carregado
do $$
begin
  raise notice '[PASS] cenario F5-10 P4 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f2a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-10 P4 Alfa'),
  ('f2a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-10 P4 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades (auth.users + perfil + membership)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f2c00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dono.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gerente.congelado.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'coordenador.congelado.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.write.overlay.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gerente.sem.aprovar.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'aprovador.sem.vinculo.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.revogada.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfil.disabled.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'terceiro.leitor.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.vivo.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ator.beta.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dono.beta.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f2c00000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin.ciclo.alfa.f5-10-p4@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('f2c00000-0000-0000-0000-000000000001', 'active'),
  ('f2c00000-0000-0000-0000-000000000002', 'active'),
  ('f2c00000-0000-0000-0000-000000000003', 'active'),
  ('f2c00000-0000-0000-0000-000000000004', 'active'),
  ('f2c00000-0000-0000-0000-000000000005', 'active'),
  ('f2c00000-0000-0000-0000-000000000006', 'active'),
  ('f2c00000-0000-0000-0000-000000000007', 'active'),
  ('f2c00000-0000-0000-0000-000000000008', 'disabled'),
  ('f2c00000-0000-0000-0000-000000000009', 'active'),
  ('f2c00000-0000-0000-0000-00000000000a', 'active'),
  ('f2c00000-0000-0000-0000-0000000000b1', 'active'),
  ('f2c00000-0000-0000-0000-0000000000c1', 'active'),
  ('f2c00000-0000-0000-0000-0000000000d1', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('f2d00000-0000-0000-0000-000000000001', 'f2c00000-0000-0000-0000-000000000001',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f2d00000-0000-0000-0000-000000000002', 'f2c00000-0000-0000-0000-000000000002',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f2d00000-0000-0000-0000-000000000003', 'f2c00000-0000-0000-0000-000000000003',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f2d00000-0000-0000-0000-000000000004', 'f2c00000-0000-0000-0000-000000000004',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f2d00000-0000-0000-0000-000000000005', 'f2c00000-0000-0000-0000-000000000005',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f2d00000-0000-0000-0000-000000000006', 'f2c00000-0000-0000-0000-000000000006',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  -- a7: membership REVOGADA (negativo 2).
  ('f2d00000-0000-0000-0000-000000000007', 'f2c00000-0000-0000-0000-000000000007',
   'f2a00000-0000-0000-0000-0000000000a1', 'disabled'),
  -- a8: membership ATIVA com perfil `disabled` (negativo 3).
  ('f2d00000-0000-0000-0000-000000000008', 'f2c00000-0000-0000-0000-000000000008',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f2d00000-0000-0000-0000-000000000009', 'f2c00000-0000-0000-0000-000000000009',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f2d00000-0000-0000-0000-00000000000a', 'f2c00000-0000-0000-0000-00000000000a',
   'f2a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f2d00000-0000-0000-0000-0000000000b1', 'f2c00000-0000-0000-0000-0000000000b1',
   'f2a00000-0000-0000-0000-0000000000b1', 'active'),
  ('f2d00000-0000-0000-0000-0000000000c1', 'f2c00000-0000-0000-0000-0000000000c1',
   'f2a00000-0000-0000-0000-0000000000b1', 'active'),
  ('f2d00000-0000-0000-0000-0000000000d1', 'f2c00000-0000-0000-0000-0000000000d1',
   'f2a00000-0000-0000-0000-0000000000a1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores SOBERANOS (UUID) + status vigente
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f2b00000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2b00000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2b00000-0000-0000-0000-000000000003', 'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2b00000-0000-0000-0000-000000000004', 'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2b00000-0000-0000-0000-000000000005', 'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2b00000-0000-0000-0000-000000000006', 'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2b00000-0000-0000-0000-000000000007', 'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2b00000-0000-0000-0000-0000000000b1', 'f2a00000-0000-0000-0000-0000000000b1'),
  ('f2b00000-0000-0000-0000-0000000000c1', 'f2a00000-0000-0000-0000-0000000000b1');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('f2b00000-0000-0000-0000-000000000001', 'active', '2025-01-01T00:00:00Z'),
  ('f2b00000-0000-0000-0000-000000000002', 'active', '2025-01-01T00:00:00Z'),
  ('f2b00000-0000-0000-0000-000000000003', 'active', '2025-01-01T00:00:00Z'),
  ('f2b00000-0000-0000-0000-000000000004', 'active', '2025-01-01T00:00:00Z'),
  ('f2b00000-0000-0000-0000-000000000005', 'active', '2025-01-01T00:00:00Z'),
  ('f2b00000-0000-0000-0000-000000000006', 'active', '2025-01-01T00:00:00Z'),
  ('f2b00000-0000-0000-0000-000000000007', 'active', '2025-01-01T00:00:00Z'),
  ('f2b00000-0000-0000-0000-0000000000b1', 'active', '2025-01-01T00:00:00Z'),
  ('f2b00000-0000-0000-0000-0000000000c1', 'active', '2025-01-01T00:00:00Z');

-- Vinculo soberano membro x colaborador (F5-02): vinculo UNICO por ator onde
-- SELF/aprovacao e necessario. a6 NAO tem vinculo (fail-closed, negativo 9);
-- a7/a8 tambem nao (o ator ja e recusado antes da relacao).
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status) values
  ('f2e00000-0000-0000-0000-000000000001', 'f2d00000-0000-0000-0000-000000000001',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000001', 'active'),
  ('f2e00000-0000-0000-0000-000000000002', 'f2d00000-0000-0000-0000-000000000002',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000002', 'active'),
  ('f2e00000-0000-0000-0000-000000000003', 'f2d00000-0000-0000-0000-000000000003',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000003', 'active'),
  ('f2e00000-0000-0000-0000-000000000004', 'f2d00000-0000-0000-0000-000000000004',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000004', 'active'),
  ('f2e00000-0000-0000-0000-000000000005', 'f2d00000-0000-0000-0000-000000000005',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000005', 'active'),
  ('f2e00000-0000-0000-0000-000000000009', 'f2d00000-0000-0000-0000-000000000009',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000006', 'active'),
  ('f2e00000-0000-0000-0000-00000000000a', 'f2d00000-0000-0000-0000-00000000000a',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000007', 'active'),
  ('f2e00000-0000-0000-0000-0000000000b1', 'f2d00000-0000-0000-0000-0000000000b1',
   'f2a00000-0000-0000-0000-0000000000b1', 'f2b00000-0000-0000-0000-0000000000b1', 'active'),
  ('f2e00000-0000-0000-0000-0000000000c1', 'f2d00000-0000-0000-0000-0000000000c1',
   'f2a00000-0000-0000-0000-0000000000b1', 'f2b00000-0000-0000-0000-0000000000c1', 'active');
-- OBS.: o ator `ad` (cycle.manage; positivo 10 de LIMITES) NAO recebe vinculo: a
-- operacao de LIMITES e ADMINISTRATIVA de ciclo (`cycle.manage`) e NAO tem
-- relacao; alem disso o vinculo ativo e UNICO por colaborador (F5-02), de modo
-- que um segundo vinculo para `c1` violaria
-- `uq_membership_collaborator_links_active_collaborator`.

-- ----------------------------------------------------------------------------
-- 4) HIERARQUIA VIVA (F3-03/F3-04/F3-05) — DIVERGENTE do snapshot congelado
-- ----------------------------------------------------------------------------
-- `aa` (c7) e o GESTOR VIVO de `c1` (dono de M1) por occupation + reporting
-- line, mas o participante CONGELADO de GESTAO_CADEIA de M1 e `c2`. Nenhuma
-- decisao de aprovacao pode vir desta estrutura viva (negativo 10 / D14-D15).
insert into public.job_roles (id, organization_id, name) values
  ('f2e70000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1',
   'Funcao Sintetica F5-10 P4');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f2f00000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1',
   'Unidade Sintetica F5-10 P4 Gestao', '2025-01-01T00:00:00Z'),
  ('f2f00000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1',
   'Unidade Sintetica F5-10 P4 Time', '2025-01-01T00:00:00Z');

insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, valid_from) values
  ('f2f10000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2f00000-0000-0000-0000-000000000001', 'f2e70000-0000-0000-0000-000000000001',
   '2025-01-01T00:00:00Z'),
  ('f2f10000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2f00000-0000-0000-0000-000000000002', 'f2e70000-0000-0000-0000-000000000001',
   '2025-01-01T00:00:00Z');

-- c1 (dono de M1) responde a posicao de `c7` (aa) na estrutura VIVA.
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from) values
  ('f2f20000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2b00000-0000-0000-0000-000000000001', 'f2f10000-0000-0000-0000-000000000002',
   'ocupacao sintetica do dono (fixture P4)', '2025-01-01T00:00:00Z'),
  ('f2f20000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2b00000-0000-0000-0000-000000000007', 'f2f10000-0000-0000-0000-000000000001',
   'ocupacao sintetica do gestor vivo (fixture P4)', '2025-01-01T00:00:00Z');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('f2f30000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2f10000-0000-0000-0000-000000000002', 'f2f10000-0000-0000-0000-000000000001',
   'reporting line sintetica (fixture P4)', '2025-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 5) Roles + capabilities (SOMENTE capabilities EXISTENTES no catalogo)
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('f2f90000-0000-0000-0000-000000000001', 'metas_dono_f5_10_p4', 'active', false,
   'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2f90000-0000-0000-0000-000000000002', 'metas_aprovador_f5_10_p4', 'active', false,
   'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2f90000-0000-0000-0000-000000000003', 'ciclo_admin_f5_10_p4', 'active', false,
   'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2f90000-0000-0000-0000-000000000004', 'metas_leitor_f5_10_p4', 'active', false,
   'f2a00000-0000-0000-0000-0000000000a1'),
  ('f2f90000-0000-0000-0000-000000000005', 'beta_dono_f5_10_p4', 'active', false,
   'f2a00000-0000-0000-0000-0000000000b1'),
  ('f2f90000-0000-0000-0000-000000000006', 'metas_aprovador_live_f5_10_p4', 'active', false,
   'f2a00000-0000-0000-0000-0000000000a1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where (ar.id = 'f2f90000-0000-0000-0000-000000000001' and c.code in ('goal.read', 'goal.write'))
    or (ar.id = 'f2f90000-0000-0000-0000-000000000002' and c.code in ('goal.read', 'goal.approve'))
    or (ar.id = 'f2f90000-0000-0000-0000-000000000003' and c.code = 'cycle.manage')
    or (ar.id = 'f2f90000-0000-0000-0000-000000000004' and c.code = 'goal.read')
    or (ar.id = 'f2f90000-0000-0000-0000-000000000005' and c.code in ('cycle.manage', 'goal.read'))
    or (ar.id = 'f2f90000-0000-0000-0000-000000000006' and c.code in ('goal.read', 'goal.approve'));

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f2f80000-0000-0000-0000-000000000001', 'f2d00000-0000-0000-0000-000000000001',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000001',
   'active', 'f2c00000-0000-0000-0000-000000000001'),
  ('f2f80000-0000-0000-0000-000000000002', 'f2d00000-0000-0000-0000-000000000002',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000002',
   'active', 'f2c00000-0000-0000-0000-000000000001'),
  -- a2 (GERENTE congelado de M1 e DONO de c2) recebe TAMBEM `goal.write`: e ele
  -- quem cria a propria meta (M5) no positivo 1 (SELF).
  ('f2f80000-0000-0000-0000-00000000000e', 'f2d00000-0000-0000-0000-000000000002',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000001',
   'active', 'f2c00000-0000-0000-0000-000000000001'),
  ('f2f80000-0000-0000-0000-000000000003', 'f2d00000-0000-0000-0000-000000000003',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000002',
   'active', 'f2c00000-0000-0000-0000-000000000001'),
  -- a4: `goal.write` para quem NAO e dono (negativos 4/5/6) e overlay sem role de
  -- aprovacao (positivo 9 continua recusado pela RELACAO congelada).
  ('f2f80000-0000-0000-0000-000000000004', 'f2d00000-0000-0000-0000-000000000004',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000001',
   'active', 'f2c00000-0000-0000-0000-000000000001'),
  -- a5: GESTAO_CADEIA congelada de M6 SEM `goal.approve` (nenhuma role).
  -- a6: `goal.approve` sem vinculo UNICO de colaborador.
  ('f2f80000-0000-0000-0000-000000000006', 'f2d00000-0000-0000-0000-000000000006',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000002',
   'active', 'f2c00000-0000-0000-0000-000000000001'),
  -- a9: `goal.read` ISOLADO, sem relacao com meta alguma (negativo 15).
  ('f2f80000-0000-0000-0000-000000000009', 'f2d00000-0000-0000-0000-000000000009',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000004',
   'active', 'f2c00000-0000-0000-0000-000000000001'),
  -- aa: GESTOR VIVO com `goal.approve`, divergente do congelado (negativo 10).
  ('f2f80000-0000-0000-0000-00000000000a', 'f2d00000-0000-0000-0000-00000000000a',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000006',
   'active', 'f2c00000-0000-0000-0000-000000000001'),
  -- ac: dono da meta de Beta (leitura cross-tenant sob RLS).
  ('f2f80000-0000-0000-0000-0000000000c1', 'f2d00000-0000-0000-0000-0000000000c1',
   'f2a00000-0000-0000-0000-0000000000b1', 'f2f90000-0000-0000-0000-000000000005',
   'active', 'f2c00000-0000-0000-0000-0000000000c1'),
  -- ad: `cycle.manage` (LIMITES continua administrativo de ciclo, positivo 10).
  ('f2f80000-0000-0000-0000-0000000000d1', 'f2d00000-0000-0000-0000-0000000000d1',
   'f2a00000-0000-0000-0000-0000000000a1', 'f2f90000-0000-0000-0000-000000000003',
   'active', 'f2c00000-0000-0000-0000-000000000001');

-- ----------------------------------------------------------------------------
-- 6) Configuracao baseline versionada (F5-06 D5) + ciclos + quotas
-- ----------------------------------------------------------------------------
do $$
declare
  v_cfg_alfa uuid;
  v_cfg_beta uuid;
begin
  v_cfg_alfa := public.evaluation_config_bootstrap(
    'f2a00000-0000-0000-0000-0000000000a1',
    'f2c00000-0000-0000-0000-000000000001');
  v_cfg_beta := public.evaluation_config_bootstrap(
    'f2a00000-0000-0000-0000-0000000000b1',
    'f2c00000-0000-0000-0000-0000000000c1');
  if v_cfg_alfa is null or v_cfg_beta is null then
    raise exception '[FAIL] cenario F5-10 P4: bootstrap de configuracao nao retornou versao';
  end if;

  -- Alfa: 1 ciclo ATIVO (operacoes mutaveis) + 1 ENCERRADO (negativo 12).
  -- Beta: 1 ciclo ATIVO (cross-tenant).
  insert into public.evaluation_cycles
    (id, organization_id, ano, numero, status, data_inicio, data_fim,
     data_ativacao, data_encerramento, config_version_id, version) values
    ('f2d10000-0000-0000-0000-0000000000a1', 'f2a00000-0000-0000-0000-0000000000a1',
     2039, 1, 'ATIVO', date '2039-01-01', date '2039-06-30', now(), null, v_cfg_alfa, 1),
    ('f2d10000-0000-0000-0000-0000000000a2', 'f2a00000-0000-0000-0000-0000000000a1',
     2036, 1, 'ENCERRADO', date '2036-01-01', date '2036-06-30', now(), now(), v_cfg_alfa, 3),
    ('f2d10000-0000-0000-0000-0000000000b1', 'f2a00000-0000-0000-0000-0000000000b1',
     2039, 1, 'ATIVO', date '2039-01-01', date '2039-06-30', now(), null, v_cfg_beta, 1);

  insert into public.evaluation_cycle_goal_limits
    (id, organization_id, cycle_id, tipo, quantidade) values
    ('f2f50000-0000-0000-0000-0000000000a1', 'f2a00000-0000-0000-0000-0000000000a1',
     'f2d10000-0000-0000-0000-0000000000a1', 'NEGOCIO_PROJETO', 3),
    ('f2f50000-0000-0000-0000-0000000000a2', 'f2a00000-0000-0000-0000-0000000000a1',
     'f2d10000-0000-0000-0000-0000000000a1', 'INDIVIDUAL', 2),
    ('f2f50000-0000-0000-0000-0000000000a3', 'f2a00000-0000-0000-0000-0000000000a1',
     'f2d10000-0000-0000-0000-0000000000a2', 'NEGOCIO_PROJETO', 3),
    ('f2f50000-0000-0000-0000-0000000000a4', 'f2a00000-0000-0000-0000-0000000000a1',
     'f2d10000-0000-0000-0000-0000000000a2', 'INDIVIDUAL', 2),
    ('f2f50000-0000-0000-0000-0000000000b1', 'f2a00000-0000-0000-0000-0000000000b1',
     'f2d10000-0000-0000-0000-0000000000b1', 'NEGOCIO_PROJETO', 2);

  -- Avaliacoes do dono (a P4/P3 LEEM o snapshot congelado; a materializacao
  -- oficial e da F5-06). EV4 e CANCELADA e deve ser ignorada.
  insert into public.evaluations
    (id, organization_id, cycle_id, evaluated_collaborator_id, status,
     config_version_id, version, motivo_cancelamento, data_cancelamento) values
    ('f2200000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1',
     'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000001',
     'PRONTA_PARA_FEEDBACK', v_cfg_alfa, 0, null, null),
    ('f2200000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1',
     'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000002',
     'PRONTA_PARA_FEEDBACK', v_cfg_alfa, 0, null, null),
    ('f2200000-0000-0000-0000-000000000003', 'f2a00000-0000-0000-0000-0000000000a1',
     'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000003',
     'PRONTA_PARA_FEEDBACK', v_cfg_alfa, 0, null, null),
    ('f2200000-0000-0000-0000-000000000004', 'f2a00000-0000-0000-0000-0000000000a1',
     'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000004',
     'CANCELADA', v_cfg_alfa, 0, 'cancelamento ficticio de fixture (P4)', now());
end $$;

-- ----------------------------------------------------------------------------
-- 7) SNAPSHOT CONGELADO de participantes (dado da fixture) + OVERLAY posterior
-- ----------------------------------------------------------------------------
insert into public.evaluation_participants
  (id, organization_id, evaluation_id, role_type, collaborator_id, origem,
   valid_from, status) values
  -- EV1 (dono c1 = M1): par ORIGINAL c2 (cadeia) + c3 (direta, distinta).
  ('f2300000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2200000-0000-0000-0000-000000000001', 'GESTAO_CADEIA', 'f2b00000-0000-0000-0000-000000000002',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  ('f2300000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2200000-0000-0000-0000-000000000001', 'GESTAO_DIRETA', 'f2b00000-0000-0000-0000-000000000003',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  -- EV2 (dono c2 = M5): SOMENTE cadeia (o COORDENADOR nao existe).
  ('f2300000-0000-0000-0000-000000000003', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2200000-0000-0000-0000-000000000002', 'GESTAO_CADEIA', 'f2b00000-0000-0000-0000-000000000001',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  -- EV3 (dono c3 = M6): cadeia ORIGINAL = c5 (SEM goal.approve), direta = c2
  -- (distinta) e OVERLAY POSTERIOR de cadeia = c4 (NUNCA transfere autoridade).
  ('f2300000-0000-0000-0000-000000000004', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2200000-0000-0000-0000-000000000003', 'GESTAO_CADEIA', 'f2b00000-0000-0000-0000-000000000005',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  ('f2300000-0000-0000-0000-000000000005', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2200000-0000-0000-0000-000000000003', 'GESTAO_DIRETA', 'f2b00000-0000-0000-0000-000000000002',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  ('f2300000-0000-0000-0000-000000000006', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2200000-0000-0000-0000-000000000003', 'GESTAO_CADEIA', 'f2b00000-0000-0000-0000-000000000004',
   'SUBSTITUICAO_TEMPORARIA', '2026-06-01T00:00:00Z', 'active');

-- ----------------------------------------------------------------------------
-- 8) Metas de FIXTURE (dado; a fixture NAO usa RPC) + trilha CRIADA
-- ----------------------------------------------------------------------------
insert into public.evaluation_goals
  (id, organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
   status, resultado_final, atingida, data_fechamento, excluida, data_exclusao,
   version) values
  -- M1: dono c1, ciclo ATIVO, EM_ANDAMENTO — alvo das aprovacoes congeladas.
  ('f2000000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000001',
   'NEGOCIO_PROJETO', 'Meta de fixture com os dois papeis congelados (P4)',
   'KPI de fixture (P4)', '100 unidades (P4)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0),
  -- M2: dono c1, ciclo ATIVO — trilha SELF (editar/progredir/finalizar/ler).
  --      `INDIVIDUAL` (e nao NEGOCIO_PROJETO) porque o indice parcial unico
  --      `uq_evaluation_goals_org_cycle_collab_tipo_viva` proibe duas metas VIVAS
  --      do mesmo tipo para o mesmo dono/ciclo (M1 ja ocupa NEGOCIO_PROJETO) e
  --      porque a quota INDIVIDUAL do ciclo ATIVO (2) sustenta a criacao do
  --      positivo 1.
  ('f2000000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000001',
   'INDIVIDUAL', 'Meta SELF de fixture (P4)',
   'KPI de fixture (P4)', '50 unidades (P4)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0),
  -- M3: dono c1, ciclo ENCERRADO (negativo 12).
  ('f2000000-0000-0000-0000-000000000003', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2d10000-0000-0000-0000-0000000000a2', 'f2b00000-0000-0000-0000-000000000001',
   'NEGOCIO_PROJETO', 'Meta de fixture em ciclo ENCERRADO (P4)',
   'KPI de fixture (P4)', '30 unidades (P4)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0),
  -- M4: dono c1, ciclo ENCERRADO, EXCLUIDA (negativo 11) e `ATINGIDA` — cobre o
  --      terceiro estado do CHECK (fechamento COERENTE: resultado_final +
  --      atingida + data_fechamento).
  ('f2000000-0000-0000-0000-000000000004', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2d10000-0000-0000-0000-0000000000a2', 'f2b00000-0000-0000-0000-000000000001',
   'INDIVIDUAL', 'Meta EXCLUIDA de fixture (P4)',
   'KPI de fixture (P4)', '20 unidades (P4)', 'ATINGIDA',
   'Fechamento ficticio de fixture (P4)', true, now(),
   true, now(), 2),
  -- M6: dona c3, ciclo ATIVO — dois papeis congelados + overlay posterior.
  ('f2000000-0000-0000-0000-000000000006', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000003',
   'NEGOCIO_PROJETO', 'Meta de fixture com overlay posterior (P4)',
   'KPI de fixture (P4)', '70 unidades (P4)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0),
  -- M7: dono c4, ciclo ENCERRADO, NAO_ATINGIDA (fechamento COERENTE do CHECK).
  ('f2000000-0000-0000-0000-000000000007', 'f2a00000-0000-0000-0000-0000000000a1',
   'f2d10000-0000-0000-0000-0000000000a2', 'f2b00000-0000-0000-0000-000000000004',
   'NEGOCIO_PROJETO', 'Meta finalizada de fixture (P4)',
   'KPI de fixture (P4)', '40 unidades (P4)', 'NAO_ATINGIDA',
   'Fechamento ficticio de fixture (P4)', false, now(), false, null, 1),
  -- M8: meta do tenant Beta (cross-tenant).
  ('f2000000-0000-0000-0000-0000000000b1', 'f2a00000-0000-0000-0000-0000000000b1',
   'f2d10000-0000-0000-0000-0000000000b1', 'f2b00000-0000-0000-0000-0000000000c1',
   'NEGOCIO_PROJETO', 'Meta do tenant Beta (P4)',
   'KPI de fixture (P4)', '10 unidades (P4)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0);

insert into public.evaluation_goal_events
  (id, organization_id, goal_id, entity_type, event_type, effective_date, reason,
   before_value, after_value, payload_hash, result_entity_id,
   actor_user_profile_id, actor_membership_id, operation_id)
select
  ('f2400000-0000-0000-0000-00000000000' || lpad(g.ordem::text, 1, '0'))::uuid,
  g.organization_id, g.id, 'evaluation_goal', 'CRIADA', now(),
  'Criacao de fixture (P4)', null,
  jsonb_build_object('status', 'EM_ANDAMENTO', 'version', 0, 'tipo', g.tipo),
  encode(sha256(convert_to('{"fixture":"f5-10-p4","goal":' || g.ordem || '}', 'UTF8')), 'hex'),
  g.id,
  case when g.organization_id = 'f2a00000-0000-0000-0000-0000000000b1'
       then 'f2c00000-0000-0000-0000-0000000000c1'::uuid
       else 'f2c00000-0000-0000-0000-000000000001'::uuid end,
  case when g.organization_id = 'f2a00000-0000-0000-0000-0000000000b1'
       then 'f2d00000-0000-0000-0000-0000000000c1'::uuid
       else 'f2d00000-0000-0000-0000-000000000001'::uuid end,
  ('f2600000-0000-0000-0000-00000000000' || lpad(g.ordem::text, 1, '0'))::uuid
  from (
    select g.*, row_number() over (order by g.id) as ordem
      from public.evaluation_goals g
     where g.id::text like 'f2000000%'
  ) g;

-- ----------------------------------------------------------------------------
-- 9) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_atores   int;
  v_memb     int;
  v_memb_ok  int;
  v_colabs   int;
  v_links    int;
  v_ciclos   int;
  v_quota    int;
  v_metas    int;
  v_excl     int;
  v_estados  int;
  v_avaliac  int;
  v_partic   int;
  v_eventos  int;
  v_aprov    int;
  v_roles    int;
  v_assign   int;
  v_caps     int;
  v_dono     uuid;
  v_ger      uuid;
  v_coord    uuid;
  v_vivo     uuid;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('f2a00000-0000-0000-0000-0000000000a1',
                'f2a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_atores from public.user_profiles where id::text like 'f2c00000%';
  select count(*) into v_memb from public.user_organization_memberships
   where id::text like 'f2d00000%';
  select count(*) into v_memb_ok from public.user_organization_memberships
   where id::text like 'f2d00000%' and status = 'active';
  select count(*) into v_colabs from public.collaborators where id::text like 'f2b00000%';
  select count(*) into v_links from public.membership_collaborator_links
   where id::text like 'f2e00000%' and status = 'active';
  select count(*) into v_ciclos from public.evaluation_cycles where id::text like 'f2d10000%';
  select count(*) into v_quota from public.evaluation_cycle_goal_limits
   where id::text like 'f2f50000%';
  select count(*) into v_metas from public.evaluation_goals where id::text like 'f2000000%';
  select count(*) into v_excl from public.evaluation_goals
   where id::text like 'f2000000%' and excluida;
  select count(distinct g.status) into v_estados from public.evaluation_goals g
   where g.id::text like 'f2000000%';
  select count(*) into v_avaliac from public.evaluations where id::text like 'f2200000%';
  select count(*) into v_partic from public.evaluation_participants
   where id::text like 'f2300000%';
  select count(*) into v_eventos from public.evaluation_goal_events
   where organization_id in ('f2a00000-0000-0000-0000-0000000000a1',
                             'f2a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in ('f2a00000-0000-0000-0000-0000000000a1',
                             'f2a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_roles from public.access_roles where id::text like 'f2f90000%';
  select count(*) into v_assign from public.membership_access_role_assignments
   where id::text like 'f2f80000%' and status = 'active';
  select count(*) into v_caps from public.access_role_capabilities rc
    join public.access_roles ar on ar.id = rc.access_role_id
   where ar.id::text like 'f2f90000%';

  if v_orgs <> 2 or v_atores <> 13 or v_memb <> 13 or v_memb_ok <> 12
     or v_colabs <> 9 or v_links <> 9 or v_ciclos <> 3 or v_quota <> 5
     or v_metas <> 7 or v_excl <> 1 or v_estados <> 3 or v_avaliac <> 4
     or v_partic <> 6 or v_eventos <> 7 or v_aprov <> 0 or v_roles <> 6
     or v_assign <> 10 or v_caps <> 10 then
    raise exception
      '[FAIL] cenario F5-10 P4 incompleto (orgs=%, atores=%, memberships=%, ativas=%, colabs=%, links=%, ciclos=%, quotas=%, metas=%, excluidas=%, estados=%, avaliacoes=%, participantes=%, eventos=%, aprovacoes=%, roles=%, assignments=%, capabilities=%)',
      v_orgs, v_atores, v_memb, v_memb_ok, v_colabs, v_links, v_ciclos, v_quota,
      v_metas, v_excl, v_estados, v_avaliac, v_partic, v_eventos, v_aprov,
      v_roles, v_assign, v_caps;
  end if;

  -- A resolucao CONGELADA tem de reconhecer os papeis ORIGINAIS.
  v_ger := public.f5_10_aprovador_congelado(
    'f2000000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1', 'GERENTE');
  if v_ger <> 'f2b00000-0000-0000-0000-000000000002'::uuid then
    raise exception '[FAIL] cenario F5-10 P4: GERENTE congelado de M1 deveria ser c2 (%)', v_ger;
  end if;
  v_coord := public.f5_10_aprovador_congelado(
    'f2000000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1', 'COORDENADOR');
  if v_coord <> 'f2b00000-0000-0000-0000-000000000003'::uuid then
    raise exception '[FAIL] cenario F5-10 P4: COORDENADOR congelado de M1 deveria ser c3 (%)', v_coord;
  end if;
  v_ger := public.f5_10_aprovador_congelado(
    'f2000000-0000-0000-0000-000000000006', 'f2a00000-0000-0000-0000-0000000000a1', 'GERENTE');
  if v_ger <> 'f2b00000-0000-0000-0000-000000000005'::uuid then
    raise exception '[FAIL] cenario F5-10 P4: GERENTE congelado de M6 deveria ser c5 (%)', v_ger;
  end if;
  v_coord := public.f5_10_aprovador_congelado(
    'f2000000-0000-0000-0000-000000000006', 'f2a00000-0000-0000-0000-0000000000a1', 'COORDENADOR');
  if v_coord <> 'f2b00000-0000-0000-0000-000000000002'::uuid then
    raise exception '[FAIL] cenario F5-10 P4: COORDENADOR congelado de M6 deveria ser c2 (%)', v_coord;
  end if;

  -- O vinculo SOBERANO UNICO dos atores centrais.
  v_dono := public.f5_10_vinculo_meta_do_ator(
    'f2c00000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1');
  if v_dono <> 'f2b00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] cenario F5-10 P4: vinculo do dono a1 deveria ser c1 (%)', v_dono;
  end if;
  if public.f5_10_vinculo_meta_do_ator(
       'f2c00000-0000-0000-0000-000000000006', 'f2a00000-0000-0000-0000-0000000000a1') is not null then
    raise exception '[FAIL] cenario F5-10 P4: a6 NAO deveria ter vinculo de colaborador';
  end if;

  -- Hierarquia VIVA divergente do congelado (negativo 10).
  select r.manager_responsible_collaborator_id into v_vivo
    from public.organizacao_resolver_gestor_direto(
           'f2b00000-0000-0000-0000-000000000001', now()) r;
  if v_vivo <> 'f2b00000-0000-0000-0000-000000000007'::uuid then
    raise exception '[FAIL] cenario F5-10 P4: gestor VIVO do dono deveria ser c7 (%)', v_vivo;
  end if;

  raise notice '[PASS] cenario F5-10 P4: 2 orgs, 13 atores, 9 colaboradores, 9 vinculos (o ator de LIMITES nao tem vinculo: a operacao e administrativa de ciclo), 3 ciclos (Alfa ATIVO + ENCERRADO, Beta ATIVO), 5 quotas, 7 metas (1 excluida; EM_ANDAMENTO/ATINGIDA/NAO_ATINGIDA), 4 avaliacoes, 6 participantes congelados (par original + overlay posterior), 7 eventos CRIADA, 6 roles e 10 capabilities EXISTENTES — ZERO aprovacoes';
end $$;

-- ----------------------------------------------------------------------------
-- 10) Guarda de estado limpo para o validador (uma vez por banco)
-- ----------------------------------------------------------------------------
-- O validador 26 MUTA metas/aprovacoes e a trilha e APPEND-ONLY: nao existe
-- "reset" do dominio. O uso correto (e o CI) executa `db reset` antes de cada
-- rodada completa; aqui a guarda falha ALTO se as organizacoes da fixture ja
-- tiverem mais estado que o da fixture.
do $$
declare
  v_metas int;
  v_evt   int;
  v_aprov int;
begin
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in ('f2a00000-0000-0000-0000-0000000000a1',
                             'f2a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in ('f2a00000-0000-0000-0000-0000000000a1',
                             'f2a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in ('f2a00000-0000-0000-0000-0000000000a1',
                             'f2a00000-0000-0000-0000-0000000000b1');
  if v_metas <> 7 or v_evt <> 7 or v_aprov <> 0 then
    raise exception
      '[FAIL] estado sujo: as organizacoes da fixture F5-10 P4 ja possuem % meta(s), % evento(s) e % aprovacao(oes) — execute `supabase db reset` antes de reexecutar o cenario/validador da P4 (a trilha de metas e append-only por contrato)',
      v_metas, v_evt, v_aprov;
  end if;
  raise notice '[PASS] cenario F5-10 P4: estado limpo (7 metas de fixture, 7 eventos CRIADA, 0 aprovacoes) — pronto para o validador 26';
end $$;

\endif
