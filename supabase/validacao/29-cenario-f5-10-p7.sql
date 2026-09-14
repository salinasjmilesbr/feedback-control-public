-- ============================================================================
-- F5-10 P7 (Issue #232): cenario da P7 — VALIDACAO INTEGRADA do dominio de metas
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md (§7 lifecycle, §9 aprovacoes e matriz
-- D19, §10 autorizacao, §11 RLS x Policy Engine — D22, §12 concorrencia/versao/
-- idempotencia — D10/D11/D12, §15 testes e validacao integrada, §19 P7, §20 DoD),
-- `docs/F5-10-P5.2-contrato-leitura-soberana-metas.md` e
-- `docs/F5-10-P5.3-autoridade-painel-ciclo.md`.
--
-- Fixture ISOLADA (prefixo `e8`). Prefixos JA usados pelas fases anteriores e NAO
-- reutilizados aqui: P1 = `ee`, P2 = `f0`, P3 = `f1`, P4/P4b = `f2`, F5-09 P2 =
-- `e9`, F5-09 P4 = `eb`, F5-09 P5 = `ec`, F5-09 P9 = `ed`, F5-09 P7/D28 = `e7`,
-- F3-01 = `f3`, F4-08 = `d8`, F4-01/F4-02/F5-02 = `d0`/`d1`/`d2`, F5-06 = `d6`,
-- F5-07 = `d7`.
--
-- TRES organizacoes, com papeis distintos e NAO sobrepostos:
--
--   * Alfa-P7  (e8a00000-…-a1) — organizacao da MATRIZ INTEGRADA (validador 30).
--     Nasce com 4 metas de fixture e ZERO aprovacoes; a meta da sequencia
--     historica integrada e criada pelo proprio validador via `meta_criar`.
--   * Beta-P7  (e8a00000-…-b1) — organizacao EXCLUSIVA das provas cross-tenant /
--     IDOR (nenhuma outra prova escreve aqui).
--   * Gama-P7  (e8a00000-…-c1) — organizacao EXCLUSIVA da CONCORRENCIA REAL entre
--     duas sessoes (arquivos 31/32/33). Nasce com ciclo ATIVO, quota, snapshot
--     congelado e dono/aprovadores, mas SEM NENHUMA meta: as metas da corrida sao
--     criadas por `meta_criar` na sessao A. Se qualquer outro arquivo escrever em
--     Gama-P7, os asserts de 31/33 falham com mensagem explicita — e a correcao e
--     reatribuir a organizacao, NUNCA afrouxar a prova.
--
-- Atores de Alfa-P7 (perfil -> colaborador) e o que cada um PROVA na P7:
--   a1 -> c1 : DONO da meta da sequencia integrada (goal.read + goal.write) — SELF;
--   a2 -> c2 : GERENTE congelado ORIGINAL (GESTAO_CADEIA de EV1) COM
--              `goal.approve` e SEM `goal.write` (item 9: aprovador nao escreve);
--   a3 -> c3 : COORDENADOR congelado ORIGINAL distinto (GESTAO_DIRETA de EV1) COM
--              `goal.approve`;
--   a4 -> c4 : DONO da meta de terceiro G3 (goal.read + goal.write) — item 8
--              (SELF tentando escrever meta de TERCEIRO);
--   a5 -> c5 : GESTAO_CADEIA congelada ORIGINAL de EV2 SEM NENHUMA role — item 7
--              (RELACAO sem CAPABILITY);
--   a6 -> c6 : tem `goal.read` + `goal.approve` e NAO e participante congelado de
--              EV1 — item 6 (CAPABILITY sem RELACAO);
--   a7 -> c8 : membership `disabled` com role de dono e vinculo ATIVO — item 5a
--              (a recusa e da MEMBERSHIP, nao da relacao);
--   a8 -> c7 : perfil `disabled` com membership ATIVA e vinculo ATIVO — item 5b;
--   a9 -> c9 : `goal.read` ISOLADO, sem relacao com meta alguma — item 4/IDOR
--              (leitura de terceiro devolve ZERO e nao revela meta alheia).
--
-- Atores de Gama-P7 (exclusivos da corrida):
--   ag  -> cg1 : DONO (goal.read + goal.write);
--   ager-> cg2 : GERENTE congelado ORIGINAL de EVG (goal.read + goal.approve);
--   acoo-> cg3 : COORDENADOR congelado ORIGINAL distinto de EVG (goal.read +
--                goal.approve).
--
-- Estrutura CONGELADA de fixture (DADO; a materializacao oficial e da F5-06):
--   EV1 (dono c1): GESTAO_CADEIA = c2 (2026-01-01) + GESTAO_DIRETA = c3
--                  (2026-01-01) — par ORIGINAL da meta da sequencia;
--   EV2 (dono c4): SOMENTE GESTAO_CADEIA = c5 (o COORDENADOR nao existe);
--   EVG (dono cg1): GESTAO_CADEIA = cg2 + GESTAO_DIRETA = cg3.
--
-- Metas de FIXTURE (5; inseridas DIRETAMENTE como dado — a fixture NAO usa RPC,
-- mesma doutrina das P2/P4) + 1 evento CRIADA por meta:
--   G3 -> c4, Alfa C1 ATIVO,  NEGOCIO_PROJETO, EM_ANDAMENTO, v0 (item 7);
--   G4 -> c8, Alfa C1 ATIVO,  INDIVIDUAL,      EM_ANDAMENTO, v0 (item 5a);
--   G5 -> c7, Alfa C1 ATIVO,  INDIVIDUAL,      EM_ANDAMENTO, v0 (item 5b);
--   G6 -> c1, Alfa C2 ENCERRADO, NEGOCIO_PROJETO, EM_ANDAMENTO, v0 (item 10);
--   GB -> cb, Beta ATIVO,     NEGOCIO_PROJETO, EM_ANDAMENTO, v0 (item 4).
--   (A meta da SEQUENCIA (G1) e criada pelo VALIDADOR 30 via `meta_criar`.)
--
-- QUOTA (D4/D20/D21 — autoridade de limite por (ciclo, tipo); ausencia = ZERO):
--   Alfa C1 ATIVO     : NEGOCIO_PROJETO = 3, INDIVIDUAL = 2
--                       => INDIVIDUAL ja nasce ESGOTADO (G4 + G5 vivas) e prova o
--                          item 12 (quota excedida) sem criar estado artificial;
--                       => NEGOCIO_PROJETO tem 1 viva (G3) e comporta a meta da
--                          sequencia integrada (total 2 de 3).
--   Alfa C2 ENCERRADO : NEGOCIO_PROJETO = 3, INDIVIDUAL = 2 (item 10);
--   Beta ATIVO        : NEGOCIO_PROJETO = 2, INDIVIDUAL = 2 (item 4);
--   Gama ATIVO        : NEGOCIO_PROJETO = 3, INDIVIDUAL = 2 (corrida: 1 + 1).
--
-- Roles/capabilities (TODAS existentes no catalogo F4; NENHUMA capability nova):
--   `e8f9…01` p7_dono        : goal.read + goal.write      -> a1, a4, a7, a8
--   `e8f9…02` p7_aprovador   : goal.read + goal.approve    -> a2, a3, a6
--   `e8f9…03` p7_leitor      : goal.read                   -> a9
--   `e8f9…04` p7_beta_dono   : goal.read + goal.write      -> ab (Beta)
--   `e8f9…05` p7_gama_dono   : goal.read + goal.write      -> ag (Gama)
--   `e8f9…06` p7_gama_aprov  : goal.read + goal.approve    -> ager, acoo (Gama)
--   a5 (GESTAO_CADEIA congelada de EV2) NAO recebe role alguma (item 7).
--
-- Regras: EXECUTAR SOMENTE no Supabase local; INSERT-ONCE (reexecucao NO-OP);
-- estado limpo = `supabase db reset`; somente dados ficticios; nenhuma credencial.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('e8a00000-0000-0000-0000-0000000000a1',
                'e8a00000-0000-0000-0000-0000000000b1',
                'e8a00000-0000-0000-0000-0000000000c1')
) as cenario_f5_10_p7_carregado \gset

\if :cenario_f5_10_p7_carregado
do $$
begin
  raise notice '[PASS] cenario F5-10 P7 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('e8a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-10 P7 Alfa (matriz integrada)'),
  ('e8a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-10 P7 Beta (cross-tenant)'),
  ('e8a00000-0000-0000-0000-0000000000c1', 'Org Sintetica F5-10 P7 Gama (concorrencia)');

-- ----------------------------------------------------------------------------
-- 2) Identidades (auth.users + perfil + membership)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  -- Alfa-P7
  ('e8c00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dono.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gerente.congelado.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'coordenador.congelado.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dono.terceiro.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'relacao.sem.capability.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'capability.sem.relacao.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.revogada.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-000000000008', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfil.disabled.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'leitor.isolado.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  -- Beta-P7
  ('e8c00000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dono.beta.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  -- Gama-P7 (corrida)
  ('e8c00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dono.gama.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gerente.gama.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e8c00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'coordenador.gama.p7@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

-- a8 tem perfil `disabled`; todos os demais nascem `active`.
insert into public.user_profiles (id, status) values
  ('e8c00000-0000-0000-0000-000000000001', 'active'),
  ('e8c00000-0000-0000-0000-000000000002', 'active'),
  ('e8c00000-0000-0000-0000-000000000003', 'active'),
  ('e8c00000-0000-0000-0000-000000000004', 'active'),
  ('e8c00000-0000-0000-0000-000000000005', 'active'),
  ('e8c00000-0000-0000-0000-000000000006', 'active'),
  ('e8c00000-0000-0000-0000-000000000007', 'active'),
  ('e8c00000-0000-0000-0000-000000000008', 'disabled'),
  ('e8c00000-0000-0000-0000-000000000009', 'active'),
  ('e8c00000-0000-0000-0000-0000000000b1', 'active'),
  ('e8c00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8c00000-0000-0000-0000-0000000000a2', 'active'),
  ('e8c00000-0000-0000-0000-0000000000a3', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  -- Alfa-P7 (a7 = membership REVOGADA — item 5a; a8 = membership ativa/perfil disabled)
  ('e8d00000-0000-0000-0000-000000000001', 'e8c00000-0000-0000-0000-000000000001',
   'e8a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8d00000-0000-0000-0000-000000000002', 'e8c00000-0000-0000-0000-000000000002',
   'e8a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8d00000-0000-0000-0000-000000000003', 'e8c00000-0000-0000-0000-000000000003',
   'e8a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8d00000-0000-0000-0000-000000000004', 'e8c00000-0000-0000-0000-000000000004',
   'e8a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8d00000-0000-0000-0000-000000000005', 'e8c00000-0000-0000-0000-000000000005',
   'e8a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8d00000-0000-0000-0000-000000000006', 'e8c00000-0000-0000-0000-000000000006',
   'e8a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8d00000-0000-0000-0000-000000000007', 'e8c00000-0000-0000-0000-000000000007',
   'e8a00000-0000-0000-0000-0000000000a1', 'disabled'),
  ('e8d00000-0000-0000-0000-000000000008', 'e8c00000-0000-0000-0000-000000000008',
   'e8a00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8d00000-0000-0000-0000-000000000009', 'e8c00000-0000-0000-0000-000000000009',
   'e8a00000-0000-0000-0000-0000000000a1', 'active'),
  -- Beta-P7
  ('e8d00000-0000-0000-0000-0000000000b1', 'e8c00000-0000-0000-0000-0000000000b1',
   'e8a00000-0000-0000-0000-0000000000b1', 'active'),
  -- Gama-P7 (corrida)
  ('e8d00000-0000-0000-0000-0000000000a1', 'e8c00000-0000-0000-0000-0000000000a1',
   'e8a00000-0000-0000-0000-0000000000c1', 'active'),
  ('e8d00000-0000-0000-0000-0000000000a2', 'e8c00000-0000-0000-0000-0000000000a2',
   'e8a00000-0000-0000-0000-0000000000c1', 'active'),
  ('e8d00000-0000-0000-0000-0000000000a3', 'e8c00000-0000-0000-0000-0000000000a3',
   'e8a00000-0000-0000-0000-0000000000c1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores SOBERANOS (UUID) + status vigente + vinculo soberano (F5-02)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('e8b00000-0000-0000-0000-000000000001', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-000000000002', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-000000000003', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-000000000004', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-000000000005', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-000000000006', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-000000000007', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-000000000008', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-000000000009', 'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8b00000-0000-0000-0000-0000000000b1', 'e8a00000-0000-0000-0000-0000000000b1'),
  ('e8b00000-0000-0000-0000-0000000000a1', 'e8a00000-0000-0000-0000-0000000000c1'),
  ('e8b00000-0000-0000-0000-0000000000a2', 'e8a00000-0000-0000-0000-0000000000c1'),
  ('e8b00000-0000-0000-0000-0000000000a3', 'e8a00000-0000-0000-0000-0000000000c1');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('e8b00000-0000-0000-0000-000000000001', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-000000000002', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-000000000003', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-000000000004', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-000000000005', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-000000000006', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-000000000007', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-000000000008', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-000000000009', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-0000000000b1', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-0000000000a1', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-0000000000a2', 'active', '2025-01-01T00:00:00Z'),
  ('e8b00000-0000-0000-0000-0000000000a3', 'active', '2025-01-01T00:00:00Z');

-- Vinculo soberano UNICO membro x colaborador. a7/a8 TAMBEM recebem vinculo
-- ATIVO de proposito: assim a recusa dos itens 5a/5b e atribuivel EXCLUSIVAMENTE
-- ao estado da membership / do perfil, e nao a ausencia de vinculo.
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status) values
  ('e8e00000-0000-0000-0000-000000000001', 'e8d00000-0000-0000-0000-000000000001',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000001', 'active'),
  ('e8e00000-0000-0000-0000-000000000002', 'e8d00000-0000-0000-0000-000000000002',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000002', 'active'),
  ('e8e00000-0000-0000-0000-000000000003', 'e8d00000-0000-0000-0000-000000000003',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000003', 'active'),
  ('e8e00000-0000-0000-0000-000000000004', 'e8d00000-0000-0000-0000-000000000004',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000004', 'active'),
  ('e8e00000-0000-0000-0000-000000000005', 'e8d00000-0000-0000-0000-000000000005',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000005', 'active'),
  ('e8e00000-0000-0000-0000-000000000006', 'e8d00000-0000-0000-0000-000000000006',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000006', 'active'),
  ('e8e00000-0000-0000-0000-000000000007', 'e8d00000-0000-0000-0000-000000000008',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000007', 'active'),
  ('e8e00000-0000-0000-0000-000000000008', 'e8d00000-0000-0000-0000-000000000007',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000008', 'active'),
  ('e8e00000-0000-0000-0000-000000000009', 'e8d00000-0000-0000-0000-000000000009',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000009', 'active'),
  ('e8e00000-0000-0000-0000-0000000000b1', 'e8d00000-0000-0000-0000-0000000000b1',
   'e8a00000-0000-0000-0000-0000000000b1', 'e8b00000-0000-0000-0000-0000000000b1', 'active'),
  ('e8e00000-0000-0000-0000-0000000000a1', 'e8d00000-0000-0000-0000-0000000000a1',
   'e8a00000-0000-0000-0000-0000000000c1', 'e8b00000-0000-0000-0000-0000000000a1', 'active'),
  ('e8e00000-0000-0000-0000-0000000000a2', 'e8d00000-0000-0000-0000-0000000000a2',
   'e8a00000-0000-0000-0000-0000000000c1', 'e8b00000-0000-0000-0000-0000000000a2', 'active'),
  ('e8e00000-0000-0000-0000-0000000000a3', 'e8d00000-0000-0000-0000-0000000000a3',
   'e8a00000-0000-0000-0000-0000000000c1', 'e8b00000-0000-0000-0000-0000000000a3', 'active');

-- ----------------------------------------------------------------------------
-- 4) Roles + capabilities (SOMENTE capabilities EXISTENTES no catalogo F4)
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('e8f90000-0000-0000-0000-000000000001', 'p7_dono_f5_10', 'active', false,
   'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8f90000-0000-0000-0000-000000000002', 'p7_aprovador_f5_10', 'active', false,
   'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8f90000-0000-0000-0000-000000000003', 'p7_leitor_f5_10', 'active', false,
   'e8a00000-0000-0000-0000-0000000000a1'),
  ('e8f90000-0000-0000-0000-000000000004', 'p7_beta_dono_f5_10', 'active', false,
   'e8a00000-0000-0000-0000-0000000000b1'),
  ('e8f90000-0000-0000-0000-000000000005', 'p7_gama_dono_f5_10', 'active', false,
   'e8a00000-0000-0000-0000-0000000000c1'),
  ('e8f90000-0000-0000-0000-000000000006', 'p7_gama_aprovador_f5_10', 'active', false,
   'e8a00000-0000-0000-0000-0000000000c1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where (ar.id = 'e8f90000-0000-0000-0000-000000000001' and c.code in ('goal.read', 'goal.write'))
    or (ar.id = 'e8f90000-0000-0000-0000-000000000002' and c.code in ('goal.read', 'goal.approve'))
    or (ar.id = 'e8f90000-0000-0000-0000-000000000003' and c.code = 'goal.read')
    or (ar.id = 'e8f90000-0000-0000-0000-000000000004' and c.code in ('goal.read', 'goal.write'))
    or (ar.id = 'e8f90000-0000-0000-0000-000000000005' and c.code in ('goal.read', 'goal.write'))
    or (ar.id = 'e8f90000-0000-0000-0000-000000000006' and c.code in ('goal.read', 'goal.approve'));

-- a5 (GESTAO_CADEIA congelada de EV2) NAO aparece aqui: item 7 exige RELACAO
-- congelada SEM capability.
insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('e8f80000-0000-0000-0000-000000000001', 'e8d00000-0000-0000-0000-000000000001',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8f90000-0000-0000-0000-000000000001',
   'active', 'e8c00000-0000-0000-0000-000000000001'),
  ('e8f80000-0000-0000-0000-000000000002', 'e8d00000-0000-0000-0000-000000000002',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8f90000-0000-0000-0000-000000000002',
   'active', 'e8c00000-0000-0000-0000-000000000001'),
  ('e8f80000-0000-0000-0000-000000000003', 'e8d00000-0000-0000-0000-000000000003',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8f90000-0000-0000-0000-000000000002',
   'active', 'e8c00000-0000-0000-0000-000000000001'),
  ('e8f80000-0000-0000-0000-000000000004', 'e8d00000-0000-0000-0000-000000000004',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8f90000-0000-0000-0000-000000000001',
   'active', 'e8c00000-0000-0000-0000-000000000001'),
  ('e8f80000-0000-0000-0000-000000000006', 'e8d00000-0000-0000-0000-000000000006',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8f90000-0000-0000-0000-000000000002',
   'active', 'e8c00000-0000-0000-0000-000000000001'),
  -- a7: role de DONO atribuida, mas membership `disabled` (item 5a).
  ('e8f80000-0000-0000-0000-000000000007', 'e8d00000-0000-0000-0000-000000000007',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8f90000-0000-0000-0000-000000000001',
   'active', 'e8c00000-0000-0000-0000-000000000001'),
  -- a8: role de DONO atribuida, membership ativa, perfil `disabled` (item 5b).
  ('e8f80000-0000-0000-0000-000000000008', 'e8d00000-0000-0000-0000-000000000008',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8f90000-0000-0000-0000-000000000001',
   'active', 'e8c00000-0000-0000-0000-000000000001'),
  ('e8f80000-0000-0000-0000-000000000009', 'e8d00000-0000-0000-0000-000000000009',
   'e8a00000-0000-0000-0000-0000000000a1', 'e8f90000-0000-0000-0000-000000000003',
   'active', 'e8c00000-0000-0000-0000-000000000001'),
  ('e8f80000-0000-0000-0000-0000000000b1', 'e8d00000-0000-0000-0000-0000000000b1',
   'e8a00000-0000-0000-0000-0000000000b1', 'e8f90000-0000-0000-0000-000000000004',
   'active', 'e8c00000-0000-0000-0000-0000000000b1'),
  ('e8f80000-0000-0000-0000-0000000000a1', 'e8d00000-0000-0000-0000-0000000000a1',
   'e8a00000-0000-0000-0000-0000000000c1', 'e8f90000-0000-0000-0000-000000000005',
   'active', 'e8c00000-0000-0000-0000-0000000000a1'),
  ('e8f80000-0000-0000-0000-0000000000a2', 'e8d00000-0000-0000-0000-0000000000a2',
   'e8a00000-0000-0000-0000-0000000000c1', 'e8f90000-0000-0000-0000-000000000006',
   'active', 'e8c00000-0000-0000-0000-0000000000a1'),
  ('e8f80000-0000-0000-0000-0000000000a3', 'e8d00000-0000-0000-0000-0000000000a3',
   'e8a00000-0000-0000-0000-0000000000c1', 'e8f90000-0000-0000-0000-000000000006',
   'active', 'e8c00000-0000-0000-0000-0000000000a1');

-- ----------------------------------------------------------------------------
-- 5) Configuracao baseline versionada (F5-06 D5) + ciclos + quotas
-- ----------------------------------------------------------------------------
do $$
declare
  v_cfg_alfa uuid;
  v_cfg_beta uuid;
  v_cfg_gama uuid;
begin
  v_cfg_alfa := public.evaluation_config_bootstrap(
    'e8a00000-0000-0000-0000-0000000000a1', 'e8c00000-0000-0000-0000-000000000001');
  v_cfg_beta := public.evaluation_config_bootstrap(
    'e8a00000-0000-0000-0000-0000000000b1', 'e8c00000-0000-0000-0000-0000000000b1');
  v_cfg_gama := public.evaluation_config_bootstrap(
    'e8a00000-0000-0000-0000-0000000000c1', 'e8c00000-0000-0000-0000-0000000000a1');
  if v_cfg_alfa is null or v_cfg_beta is null or v_cfg_gama is null then
    raise exception '[FAIL] cenario F5-10 P7: bootstrap de configuracao nao retornou versao';
  end if;

  -- Uma unica organizacao ATIVA por tenant (I5): Alfa tem 1 ATIVO + 1 ENCERRADO.
  insert into public.evaluation_cycles
    (id, organization_id, ano, numero, status, data_inicio, data_fim,
     data_ativacao, data_encerramento, config_version_id, version) values
    ('e8d10000-0000-0000-0000-0000000000a1', 'e8a00000-0000-0000-0000-0000000000a1',
     2039, 1, 'ATIVO', date '2039-01-01', date '2039-06-30', now(), null, v_cfg_alfa, 1),
    ('e8d10000-0000-0000-0000-0000000000a2', 'e8a00000-0000-0000-0000-0000000000a1',
     2036, 1, 'ENCERRADO', date '2036-01-01', date '2036-06-30', now(), now(), v_cfg_alfa, 3),
    ('e8d10000-0000-0000-0000-0000000000b1', 'e8a00000-0000-0000-0000-0000000000b1',
     2039, 1, 'ATIVO', date '2039-01-01', date '2039-06-30', now(), null, v_cfg_beta, 1),
    -- Gama-P7: ano 2041 EXCLUSIVO da corrida (nenhum outro cenario usa 2041 em Gama).
    ('e8d10000-0000-0000-0000-0000000000c1', 'e8a00000-0000-0000-0000-0000000000c1',
     2041, 1, 'ATIVO', date '2041-01-01', date '2041-06-30', now(), null, v_cfg_gama, 1);

  insert into public.evaluation_cycle_goal_limits
    (id, organization_id, cycle_id, tipo, quantidade) values
    -- Alfa C1 ATIVO: INDIVIDUAL nasce ESGOTADO (G4 + G5) => prova o item 12.
    ('e8f50000-0000-0000-0000-0000000000a1', 'e8a00000-0000-0000-0000-0000000000a1',
     'e8d10000-0000-0000-0000-0000000000a1', 'NEGOCIO_PROJETO', 3),
    ('e8f50000-0000-0000-0000-0000000000a2', 'e8a00000-0000-0000-0000-0000000000a1',
     'e8d10000-0000-0000-0000-0000000000a1', 'INDIVIDUAL', 2),
    ('e8f50000-0000-0000-0000-0000000000a3', 'e8a00000-0000-0000-0000-0000000000a1',
     'e8d10000-0000-0000-0000-0000000000a2', 'NEGOCIO_PROJETO', 3),
    ('e8f50000-0000-0000-0000-0000000000a4', 'e8a00000-0000-0000-0000-0000000000a1',
     'e8d10000-0000-0000-0000-0000000000a2', 'INDIVIDUAL', 2),
    ('e8f50000-0000-0000-0000-0000000000b1', 'e8a00000-0000-0000-0000-0000000000b1',
     'e8d10000-0000-0000-0000-0000000000b1', 'NEGOCIO_PROJETO', 2),
    ('e8f50000-0000-0000-0000-0000000000b2', 'e8a00000-0000-0000-0000-0000000000b1',
     'e8d10000-0000-0000-0000-0000000000b1', 'INDIVIDUAL', 2),
    ('e8f50000-0000-0000-0000-0000000000c1', 'e8a00000-0000-0000-0000-0000000000c1',
     'e8d10000-0000-0000-0000-0000000000c1', 'NEGOCIO_PROJETO', 3),
    ('e8f50000-0000-0000-0000-0000000000c2', 'e8a00000-0000-0000-0000-0000000000c1',
     'e8d10000-0000-0000-0000-0000000000c1', 'INDIVIDUAL', 2);

  -- Avaliacoes do dono (a resolucao de aprovador le o snapshot CONGELADO).
  insert into public.evaluations
    (id, organization_id, cycle_id, evaluated_collaborator_id, status,
     config_version_id, version, motivo_cancelamento, data_cancelamento) values
    ('e8200000-0000-0000-0000-000000000001', 'e8a00000-0000-0000-0000-0000000000a1',
     'e8d10000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000001',
     'PRONTA_PARA_FEEDBACK', v_cfg_alfa, 0, null, null),
    ('e8200000-0000-0000-0000-000000000002', 'e8a00000-0000-0000-0000-0000000000a1',
     'e8d10000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000004',
     'PRONTA_PARA_FEEDBACK', v_cfg_alfa, 0, null, null),
    ('e8200000-0000-0000-0000-0000000000c1', 'e8a00000-0000-0000-0000-0000000000c1',
     'e8d10000-0000-0000-0000-0000000000c1', 'e8b00000-0000-0000-0000-0000000000a1',
     'PRONTA_PARA_FEEDBACK', v_cfg_gama, 0, null, null);
end $$;

-- ----------------------------------------------------------------------------
-- 6) SNAPSHOT CONGELADO de participantes (dado da fixture)
-- ----------------------------------------------------------------------------
insert into public.evaluation_participants
  (id, organization_id, evaluation_id, role_type, collaborator_id, origem,
   valid_from, status) values
  -- EV1 (dono c1 = meta da sequencia): par ORIGINAL c2 (cadeia) + c3 (direta).
  ('e8300000-0000-0000-0000-000000000001', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8200000-0000-0000-0000-000000000001', 'GESTAO_CADEIA', 'e8b00000-0000-0000-0000-000000000002',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  ('e8300000-0000-0000-0000-000000000002', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8200000-0000-0000-0000-000000000001', 'GESTAO_DIRETA', 'e8b00000-0000-0000-0000-000000000003',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  -- EV2 (dono c4 = meta de terceiro G3): SOMENTE cadeia = c5 (SEM role — item 7).
  ('e8300000-0000-0000-0000-000000000003', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8200000-0000-0000-0000-000000000002', 'GESTAO_CADEIA', 'e8b00000-0000-0000-0000-000000000005',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  -- EVG (dono cg1) — par congelado usado pela corrida de aprovacao.
  ('e8300000-0000-0000-0000-0000000000c1', 'e8a00000-0000-0000-0000-0000000000c1',
   'e8200000-0000-0000-0000-0000000000c1', 'GESTAO_CADEIA', 'e8b00000-0000-0000-0000-0000000000a2',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active'),
  ('e8300000-0000-0000-0000-0000000000c2', 'e8a00000-0000-0000-0000-0000000000c1',
   'e8200000-0000-0000-0000-0000000000c1', 'GESTAO_DIRETA', 'e8b00000-0000-0000-0000-0000000000a3',
   'ESTRUTURA', '2026-01-01T00:00:00Z', 'active');

-- ----------------------------------------------------------------------------
-- 7) Metas de FIXTURE (dado; a fixture NAO usa RPC) + trilha CRIADA
-- ----------------------------------------------------------------------------
insert into public.evaluation_goals
  (id, organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
   status, resultado_final, atingida, data_fechamento, excluida, data_exclusao,
   version) values
  -- G3: dono c4, Alfa C1 ATIVO — RELACAO congelada de a5 (sem role) e alvo do
  --     negativo "SELF de terceiro" (a4 NAO pode editar a meta da sequencia).
  ('e8000000-0000-0000-0000-000000000003', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8d10000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000004',
   'NEGOCIO_PROJETO', 'Meta de fixture do terceiro (P7)',
   'KPI de fixture (P7)', '30 unidades (P7)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0),
  -- G4: dona c8 (a7, membership REVOGADA) — ocupa a 1a vaga de INDIVIDUAL.
  ('e8000000-0000-0000-0000-000000000004', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8d10000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000008',
   'INDIVIDUAL', 'Meta de fixture de membership revogada (P7)',
   'KPI de fixture (P7)', '20 unidades (P7)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0),
  -- G5: dono c7 (a8, perfil DISABLED) — ocupa a 2a vaga de INDIVIDUAL.
  ('e8000000-0000-0000-0000-000000000005', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8d10000-0000-0000-0000-0000000000a1', 'e8b00000-0000-0000-0000-000000000007',
   'INDIVIDUAL', 'Meta de fixture de perfil desabilitado (P7)',
   'KPI de fixture (P7)', '20 unidades (P7)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0),
  -- G6: dono c1, Alfa C2 ENCERRADO (item 10: ciclo NAO ATIVO).
  ('e8000000-0000-0000-0000-000000000006', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8d10000-0000-0000-0000-0000000000a2', 'e8b00000-0000-0000-0000-000000000001',
   'NEGOCIO_PROJETO', 'Meta de fixture em ciclo ENCERRADO (P7)',
   'KPI de fixture (P7)', '40 unidades (P7)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0),
  -- GB: meta do tenant Beta (item 4: cross-tenant / IDOR).
  ('e8000000-0000-0000-0000-0000000000b1', 'e8a00000-0000-0000-0000-0000000000b1',
   'e8d10000-0000-0000-0000-0000000000b1', 'e8b00000-0000-0000-0000-0000000000b1',
   'NEGOCIO_PROJETO', 'Meta do tenant Beta (P7)',
   'KPI de fixture (P7)', '10 unidades (P7)', 'EM_ANDAMENTO', null, null, null,
   false, null, 0);

insert into public.evaluation_goal_events
  (id, organization_id, goal_id, entity_type, event_type, effective_date, reason,
   before_value, after_value, payload_hash, result_entity_id,
   actor_user_profile_id, actor_membership_id, operation_id) values
  ('e8400000-0000-0000-0000-000000000003', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8000000-0000-0000-0000-000000000003', 'evaluation_goal', 'CRIADA', now(),
   'Criacao de fixture (P7)', null,
   jsonb_build_object('status', 'EM_ANDAMENTO', 'version', 0, 'tipo', 'NEGOCIO_PROJETO'),
   encode(sha256(convert_to('{"fixture":"f5-10-p7","goal":3}', 'UTF8')), 'hex'),
   'e8000000-0000-0000-0000-000000000003',
   'e8c00000-0000-0000-0000-000000000004', 'e8d00000-0000-0000-0000-000000000004',
   'e8700000-0000-0000-0000-000000000003'),
  ('e8400000-0000-0000-0000-000000000004', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8000000-0000-0000-0000-000000000004', 'evaluation_goal', 'CRIADA', now(),
   'Criacao de fixture (P7)', null,
   jsonb_build_object('status', 'EM_ANDAMENTO', 'version', 0, 'tipo', 'INDIVIDUAL'),
   encode(sha256(convert_to('{"fixture":"f5-10-p7","goal":4}', 'UTF8')), 'hex'),
   'e8000000-0000-0000-0000-000000000004',
   'e8c00000-0000-0000-0000-000000000001', 'e8d00000-0000-0000-0000-000000000001',
   'e8700000-0000-0000-0000-000000000004'),
  ('e8400000-0000-0000-0000-000000000005', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8000000-0000-0000-0000-000000000005', 'evaluation_goal', 'CRIADA', now(),
   'Criacao de fixture (P7)', null,
   jsonb_build_object('status', 'EM_ANDAMENTO', 'version', 0, 'tipo', 'INDIVIDUAL'),
   encode(sha256(convert_to('{"fixture":"f5-10-p7","goal":5}', 'UTF8')), 'hex'),
   'e8000000-0000-0000-0000-000000000005',
   'e8c00000-0000-0000-0000-000000000001', 'e8d00000-0000-0000-0000-000000000001',
   'e8700000-0000-0000-0000-000000000005'),
  ('e8400000-0000-0000-0000-000000000006', 'e8a00000-0000-0000-0000-0000000000a1',
   'e8000000-0000-0000-0000-000000000006', 'evaluation_goal', 'CRIADA', now(),
   'Criacao de fixture (P7)', null,
   jsonb_build_object('status', 'EM_ANDAMENTO', 'version', 0, 'tipo', 'NEGOCIO_PROJETO'),
   encode(sha256(convert_to('{"fixture":"f5-10-p7","goal":6}', 'UTF8')), 'hex'),
   'e8000000-0000-0000-0000-000000000006',
   'e8c00000-0000-0000-0000-000000000001', 'e8d00000-0000-0000-0000-000000000001',
   'e8700000-0000-0000-0000-000000000006'),
  ('e8400000-0000-0000-0000-0000000000b1', 'e8a00000-0000-0000-0000-0000000000b1',
   'e8000000-0000-0000-0000-0000000000b1', 'evaluation_goal', 'CRIADA', now(),
   'Criacao de fixture (P7)', null,
   jsonb_build_object('status', 'EM_ANDAMENTO', 'version', 0, 'tipo', 'NEGOCIO_PROJETO'),
   encode(sha256(convert_to('{"fixture":"f5-10-p7","goal":"beta"}', 'UTF8')), 'hex'),
   'e8000000-0000-0000-0000-0000000000b1',
   'e8c00000-0000-0000-0000-0000000000b1', 'e8d00000-0000-0000-0000-0000000000b1',
   'e8700000-0000-0000-0000-0000000000b1');

-- ----------------------------------------------------------------------------
-- 8) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
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
  v_avaliac  int;
  v_partic   int;
  v_eventos  int;
  v_aprov    int;
  v_roles    int;
  v_assign   int;
  v_caps     int;
  v_ger      uuid;
  v_coord    uuid;
  v_dono     uuid;
  v_n        int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('e8a00000-0000-0000-0000-0000000000a1',
                'e8a00000-0000-0000-0000-0000000000b1',
                'e8a00000-0000-0000-0000-0000000000c1');
  select count(*) into v_atores from public.user_profiles where id::text like 'e8c00000%';
  select count(*) into v_memb from public.user_organization_memberships
   where id::text like 'e8d00000%';
  select count(*) into v_memb_ok from public.user_organization_memberships
   where id::text like 'e8d00000%' and status = 'active';
  select count(*) into v_colabs from public.collaborators where id::text like 'e8b00000%';
  select count(*) into v_links from public.membership_collaborator_links
   where id::text like 'e8e00000%' and status = 'active';
  select count(*) into v_ciclos from public.evaluation_cycles where id::text like 'e8d10000%';
  select count(*) into v_quota from public.evaluation_cycle_goal_limits
   where id::text like 'e8f50000%';
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in ('e8a00000-0000-0000-0000-0000000000a1',
                             'e8a00000-0000-0000-0000-0000000000b1',
                             'e8a00000-0000-0000-0000-0000000000c1');
  select count(*) into v_avaliac from public.evaluations where id::text like 'e8200000%';
  select count(*) into v_partic from public.evaluation_participants
   where id::text like 'e8300000%';
  select count(*) into v_eventos from public.evaluation_goal_events
   where organization_id in ('e8a00000-0000-0000-0000-0000000000a1',
                             'e8a00000-0000-0000-0000-0000000000b1',
                             'e8a00000-0000-0000-0000-0000000000c1');
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in ('e8a00000-0000-0000-0000-0000000000a1',
                             'e8a00000-0000-0000-0000-0000000000b1',
                             'e8a00000-0000-0000-0000-0000000000c1');
  select count(*) into v_roles from public.access_roles where id::text like 'e8f90000%';
  select count(*) into v_assign from public.membership_access_role_assignments
   where id::text like 'e8f80000%' and status = 'active';
  select count(*) into v_caps from public.access_role_capabilities rc
    join public.access_roles ar on ar.id = rc.access_role_id
   where ar.id::text like 'e8f90000%';

  if v_orgs <> 3 or v_atores <> 13 or v_memb <> 13 or v_memb_ok <> 12
     or v_colabs <> 13 or v_links <> 13 or v_ciclos <> 4 or v_quota <> 8
     or v_metas <> 5 or v_avaliac <> 3 or v_partic <> 5 or v_eventos <> 5
     or v_aprov <> 0 or v_roles <> 6 or v_assign <> 12 or v_caps <> 11 then
    raise exception
      '[FAIL] cenario F5-10 P7 incompleto (orgs=%, atores=%, memberships=%, ativas=%, colabs=%, links=%, ciclos=%, quotas=%, metas=%, avaliacoes=%, participantes=%, eventos=%, aprovacoes=%, roles=%, assignments=%, capabilities=%)',
      v_orgs, v_atores, v_memb, v_memb_ok, v_colabs, v_links, v_ciclos, v_quota,
      v_metas, v_avaliac, v_partic, v_eventos, v_aprov, v_roles, v_assign, v_caps;
  end if;

  -- A resolucao CONGELADA tem de reconhecer os papeis ORIGINAIS.
  v_ger := public.f5_10_aprovador_congelado(
    'e8000000-0000-0000-0000-000000000003', 'e8a00000-0000-0000-0000-0000000000a1', 'GERENTE');
  if v_ger <> 'e8b00000-0000-0000-0000-000000000005'::uuid then
    raise exception '[FAIL] cenario F5-10 P7: GERENTE congelado de G3 deveria ser c5 (%)', v_ger;
  end if;
  if public.f5_10_aprovador_congelado(
       'e8000000-0000-0000-0000-000000000003', 'e8a00000-0000-0000-0000-0000000000a1', 'COORDENADOR') is not null then
    raise exception '[FAIL] cenario F5-10 P7: G3 NAO deveria ter COORDENADOR congelado';
  end if;
  -- EVG (Gama-P7): a resolucao funcional do papel e por (org, ciclo, colaborador)
  -- da avaliacao do DONO da meta. Gama-P7 nasce SEM meta alguma (organizacao
  -- EXCLUSIVA da corrida), portanto aqui se confere apenas o DADO congelado: a
  -- resolucao funcional so pode ser exercitada quando a sessao A criar a meta.
  select count(*) into v_n
    from public.evaluation_participants p
   where p.organization_id = 'e8a00000-0000-0000-0000-0000000000c1'
     and p.evaluation_id = 'e8200000-0000-0000-0000-0000000000c1'
     and p.status = 'active'
     and ((p.role_type = 'GESTAO_CADEIA' and p.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a2')
       or (p.role_type = 'GESTAO_DIRETA' and p.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a3'));
  if v_n <> 2 then
    raise exception '[FAIL] cenario F5-10 P7: par congelado de EVG (cg2 cadeia + cg3 direta) incompleto (%)', v_n;
  end if;

  -- Os papeis congelados da meta da SEQUENCIA (dono c1) existem ANTES de a meta
  -- ser criada: a resolucao e por (org, ciclo, colaborador) da avaliacao do dono.
  if not exists (
    select 1 from public.evaluations e
     where e.organization_id = 'e8a00000-0000-0000-0000-0000000000a1'
       and e.cycle_id = 'e8d10000-0000-0000-0000-0000000000a1'
       and e.evaluated_collaborator_id = 'e8b00000-0000-0000-0000-000000000001'
       and e.status <> 'CANCELADA'
  ) then
    raise exception '[FAIL] cenario F5-10 P7: avaliacao congelada do dono c1 em Alfa C1 ausente';
  end if;

  -- Vinculo soberano UNICO dos atores centrais.
  v_dono := public.f5_10_vinculo_meta_do_ator(
    'e8c00000-0000-0000-0000-000000000001', 'e8a00000-0000-0000-0000-0000000000a1');
  if v_dono <> 'e8b00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] cenario F5-10 P7: vinculo do dono a1 deveria ser c1 (%)', v_dono;
  end if;
  if public.f5_10_vinculo_meta_do_ator(
       'e8c00000-0000-0000-0000-000000000007', 'e8a00000-0000-0000-0000-0000000000a1') is not null then
    raise exception '[FAIL] cenario F5-10 P7: a7 (membership revogada) NAO pode resolver vinculo soberano';
  end if;
  if public.f5_10_vinculo_meta_do_ator(
       'e8c00000-0000-0000-0000-000000000008', 'e8a00000-0000-0000-0000-0000000000a1') is not null then
    raise exception '[FAIL] cenario F5-10 P7: a8 (perfil disabled) NAO pode resolver vinculo soberano';
  end if;

  -- Gama-P7 nasce SEM metas: a organizacao e EXCLUSIVA da corrida.
  if (select count(*) from public.evaluation_goals
       where organization_id = 'e8a00000-0000-0000-0000-0000000000c1') <> 0 then
    raise exception '[FAIL] cenario F5-10 P7: Gama-P7 deve nascer SEM metas (organizacao exclusiva da corrida)';
  end if;
  if (select count(*) from public.evaluation_goal_events
       where organization_id = 'e8a00000-0000-0000-0000-0000000000c1') <> 0 then
    raise exception '[FAIL] cenario F5-10 P7: Gama-P7 deve nascer SEM eventos de meta';
  end if;

  raise notice '[PASS] cenario F5-10 P7: 3 organizacoes (Alfa = matriz integrada, Beta = cross-tenant, Gama = corrida exclusiva), 13 atores (1 membership revogada, 1 perfil disabled), 13 colaboradores, 13 vinculos ativos, 4 ciclos (Alfa ATIVO 2039/1 + ENCERRADO 2036/1, Beta ATIVO, Gama ATIVO 2041/1), 8 quotas (Alfa C1 com INDIVIDUAL ESGOTADO: 2 de 2), 5 metas de fixture, 3 avaliacoes, 5 participantes congelados, 5 eventos CRIADA, 6 roles e 11 capabilities EXISTENTES — ZERO aprovacoes e Gama-P7 sem metas';
end $$;

-- ----------------------------------------------------------------------------
-- 9) Guarda de estado limpo para o validador (uma vez por banco)
-- ----------------------------------------------------------------------------
-- O validador 30 MUTA metas/aprovacoes e a trilha e APPEND-ONLY: nao existe
-- "reset" do dominio de metas. O uso correto (e o CI) executa `db reset` antes de
-- cada rodada completa; aqui a guarda falha ALTO se as organizacoes da fixture ja
-- tiverem mais estado que o da fixture.
do $$
declare
  v_metas int;
  v_evt   int;
  v_aprov int;
  v_gama  int;
begin
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in ('e8a00000-0000-0000-0000-0000000000a1',
                             'e8a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in ('e8a00000-0000-0000-0000-0000000000a1',
                             'e8a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in ('e8a00000-0000-0000-0000-0000000000a1',
                             'e8a00000-0000-0000-0000-0000000000b1');
  select count(*) into v_gama from public.evaluation_goal_events
   where organization_id = 'e8a00000-0000-0000-0000-0000000000c1';
  if v_metas <> 5 or v_evt <> 5 or v_aprov <> 0 or v_gama <> 0 then
    raise exception
      '[FAIL] estado sujo: Alfa/Beta ja possuem % meta(s), % evento(s) e % aprovacao(oes), e Gama-P7 possui % evento(s) — execute `supabase db reset` antes de reexecutar o cenario/validador da P7 (a trilha de metas e append-only por contrato)',
      v_metas, v_evt, v_aprov, v_gama;
  end if;
  raise notice '[PASS] cenario F5-10 P7: estado limpo (5 metas de fixture em Alfa/Beta, 5 eventos CRIADA, 0 aprovacoes, Gama-P7 intocada) — pronto para o validador 30 e para a corrida 31/32/33';
end $$;

\endif
