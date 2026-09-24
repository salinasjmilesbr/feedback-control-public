-- ============================================================================
-- F5-11 P2 (Issue #244): cenario FOCADO das RPCs soberanas `observacao_*`
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-11-desenho-tecnico.md (D1-D16, §7, §8, §12, §13, §17.1) e
-- migration `20260931000000_f5_11_p2_observacoes_rpc.sql`.
--
-- Fixture ISOLADA (prefixo `f5b2`) das demais (f9/fd/fe): DUAS organizacoes —
-- Alfa (tenant da gestao) e Beta (tenant alheio, para cross-tenant) — com a
-- estrutura organizacional VIVA necessaria para a relacao soberana
-- DIRECT_REPORTS/DESCENDANTS (F3 + F4-02) e com o lifecycle de colaborador (F3-01)
-- cobrindo os TRES estados do D11.
--
-- Matriz de identidades (Alfa, todos com membership ATIVA e vinculo ATIVO):
--   GESTOR            -> colaborador c1 (posicao e1, raiz)      status active
--   SUB_ATIVO_ATOR    -> colaborador c2 (posicao e2 -> e1)      status active
--   OUTRO             -> colaborador c5 (posicao e5, raiz)      status active
--   SEM_CAP           -> colaborador c6 (posicao e6, raiz)      status active
--   PERFIL_INATIVO    -> colaborador c8                         perfil DISABLED
--   MEMBERSHIP_OFF    -> colaborador c9                         membership DISABLED
--   BETA (tenant B)   -> colaborador d1                         status active
--
-- Alvos de GESTOR (c1), pela relacao VIVA:
--   c2 (e2 -> e1)  status active    -> criacao PERMITIDA
--   c3 (e3 -> e1)  status leave     -> criacao PERMITIDA (D11)
--   c4 (e4 -> e1)  status inactive  -> criacao PROIBIDA (D11; ocupacao encerrada)
--   c7 (e7 -> e1)  SEM periodo de status -> fail-closed
--   c5/c6          fora da relacao  -> DENY por relacao
--
-- Ciclos (Alfa): ATIVO, PLANEJADO, ENCERRADO e CANCELADO (matriz do D12); Beta: ATIVO.
--
-- NENHUMA capability e' concedida aqui: `observation.*` continua com ZERO
-- concessao (D15) e o dominio nasce DENY em producao. O validador 39 exercita o
-- caminho ALLOW com uma concessao TRANSITORIA (begin/rollback) — fixture de
-- teste que NAO persiste.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local. Nunca remoto.
--   - INSERT-ONCE: reexecucao e NO-OP (guarda abaixo). Estado limpo = `db reset`.
--   - Nenhuma RPC deste dominio e usada para montar a fixture.
--   - Somente dados ficticios; nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

-- O guard identifica a fixture pelo NOME (nao apenas pelo id): sem isso, uma
-- COLISAO de UUID entre fases seria confundida com "ja carregado" e a fixture
-- inteira seria pulada em silencio (defeito real ocorrido com o prefixo `f2`,
-- compartilhado com a F5-10 P4). Colisao agora e' erro explicito.
select exists (
  select 1 from public.organizations
   where id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and name = 'Org Sintetica F5-11 P2 Alfa'
) as cenario_f5_11_p2_carregado \gset

\if :cenario_f5_11_p2_carregado
do $$
begin
  raise notice '[PASS] cenario F5-11 P2 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else
do $$
begin
  if exists (
    select 1 from public.organizations
     where id = 'f5b2a000-0000-0000-0000-0000000000a1'
  ) then
    raise exception
      '[FAIL] cenario F5-11 P2: COLISAO de UUID - a organizacao % ja existe com outro nome (fixture de outra fase)',
      'f5b2a000-0000-0000-0000-0000000000a1';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 1) Organizacoes: Alfa (tenant da gestao) e Beta (tenant alheio)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f5b2a000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-11 P2 Alfa'),
  ('f5b2a000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-11 P2 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades (auth.users + perfil + membership)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f5b2c000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'gestor.f5-11-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f5b2c000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'outro.f5-11-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f5b2c000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'semcap.f5-11-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f5b2c000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'perfilinativo.f5-11-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f5b2c000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membershipoff.f5-11-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f5b2c000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'subativo.f5-11-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('f5b2c000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'beta.f5-11-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

-- PERFIL_INATIVO tem perfil `disabled` (fail-closed na fronteira do ator).
insert into public.user_profiles (id, status) values
  ('f5b2c000-0000-0000-0000-0000000000a1', 'active'),
  ('f5b2c000-0000-0000-0000-0000000000a2', 'active'),
  ('f5b2c000-0000-0000-0000-0000000000a3', 'active'),
  ('f5b2c000-0000-0000-0000-0000000000a4', 'disabled'),
  ('f5b2c000-0000-0000-0000-0000000000a5', 'active'),
  ('f5b2c000-0000-0000-0000-0000000000a6', 'active'),
  ('f5b2c000-0000-0000-0000-0000000000b1', 'active');

-- MEMBERSHIP_OFF tem membership `disabled` (fail-closed no tenant).
insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('f5b2d000-0000-0000-0000-0000000000a1', 'f5b2c000-0000-0000-0000-0000000000a1',
   'f5b2a000-0000-0000-0000-0000000000a1', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a2', 'f5b2c000-0000-0000-0000-0000000000a2',
   'f5b2a000-0000-0000-0000-0000000000a1', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a3', 'f5b2c000-0000-0000-0000-0000000000a3',
   'f5b2a000-0000-0000-0000-0000000000a1', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a4', 'f5b2c000-0000-0000-0000-0000000000a4',
   'f5b2a000-0000-0000-0000-0000000000a1', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a5', 'f5b2c000-0000-0000-0000-0000000000a5',
   'f5b2a000-0000-0000-0000-0000000000a1', 'disabled'),
  ('f5b2d000-0000-0000-0000-0000000000a6', 'f5b2c000-0000-0000-0000-0000000000a6',
   'f5b2a000-0000-0000-0000-0000000000a1', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000b1', 'f5b2c000-0000-0000-0000-0000000000b1',
   'f5b2a000-0000-0000-0000-0000000000b1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores (um por identidade) + alvos da relacao
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f5b2e000-0000-0000-0000-0000000000c1', 'f5b2a000-0000-0000-0000-0000000000a1'), -- GESTOR
  ('f5b2e000-0000-0000-0000-0000000000c2', 'f5b2a000-0000-0000-0000-0000000000a1'), -- SUB_ATIVO
  ('f5b2e000-0000-0000-0000-0000000000c3', 'f5b2a000-0000-0000-0000-0000000000a1'), -- SUB_LICENCA
  ('f5b2e000-0000-0000-0000-0000000000c4', 'f5b2a000-0000-0000-0000-0000000000a1'), -- SUB_INATIVO
  ('f5b2e000-0000-0000-0000-0000000000c5', 'f5b2a000-0000-0000-0000-0000000000a1'), -- OUTRO (fora da relacao)
  ('f5b2e000-0000-0000-0000-0000000000c6', 'f5b2a000-0000-0000-0000-0000000000a1'), -- SEM_CAP (fora da relacao)
  ('f5b2e000-0000-0000-0000-0000000000c7', 'f5b2a000-0000-0000-0000-0000000000a1'), -- SEM_STATUS
  ('f5b2e000-0000-0000-0000-0000000000c8', 'f5b2a000-0000-0000-0000-0000000000a1'), -- PERFIL_INATIVO
  ('f5b2e000-0000-0000-0000-0000000000c9', 'f5b2a000-0000-0000-0000-0000000000a1'), -- MEMBERSHIP_OFF
  ('f5b2e000-0000-0000-0000-0000000000d1', 'f5b2a000-0000-0000-0000-0000000000b1'); -- BETA

-- Lifecycle (F3-01). c7 NAO tem periodo (fail-closed do D11); c4 esta
-- `inactive` desde 2020 (com a ocupacao encerrada, exigencia do F3-05).
insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('f5b2e000-0000-0000-0000-0000000000c1', 'active',   '2024-01-01T00:00:00Z'),
  ('f5b2e000-0000-0000-0000-0000000000c2', 'active',   '2024-01-01T00:00:00Z'),
  ('f5b2e000-0000-0000-0000-0000000000c3', 'leave',    '2024-01-01T00:00:00Z'),
  ('f5b2e000-0000-0000-0000-0000000000c5', 'active',   '2024-01-01T00:00:00Z'),
  ('f5b2e000-0000-0000-0000-0000000000c6', 'active',   '2024-01-01T00:00:00Z'),
  ('f5b2e000-0000-0000-0000-0000000000c8', 'active',   '2024-01-01T00:00:00Z'),
  ('f5b2e000-0000-0000-0000-0000000000c9', 'active',   '2024-01-01T00:00:00Z'),
  ('f5b2e000-0000-0000-0000-0000000000d1', 'active',   '2024-01-01T00:00:00Z'),
  ('f5b2e000-0000-0000-0000-0000000000c4', 'inactive', '2020-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 4) Estrutura VIVA (F3): unidade, cargo, posicoes, reporting lines e ocupacoes
--    GESTOR (c1) e' gestor de c2, c3, c4 e c7 — a relacao soberana que o gate usa.
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name) values
  ('f5b2f000-0000-0000-0000-0000000000b1', 'f5b2a000-0000-0000-0000-0000000000a1',
   'Analista F5-11 P2');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f5b2f000-0000-0000-0000-0000000000a1', 'f5b2a000-0000-0000-0000-0000000000a1',
   'Unidade F5-11 P2', '2018-01-01T00:00:00Z');

insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, valid_from, name
) values ('f5b2f000-0000-0000-0000-0000000000e1', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2f000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000b1', '2018-01-01T00:00:00Z', 'F6 P4.5 38-cenario-f5-11-p2 posição funcional'),
  ('f5b2f000-0000-0000-0000-0000000000e2', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2f000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000b1', '2018-01-01T00:00:00Z', 'F6 P4.5 38-cenario-f5-11-p2 posição funcional'),
  ('f5b2f000-0000-0000-0000-0000000000e3', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2f000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000b1', '2018-01-01T00:00:00Z', 'F6 P4.5 38-cenario-f5-11-p2 posição funcional'),
  ('f5b2f000-0000-0000-0000-0000000000e4', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2f000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000b1', '2018-01-01T00:00:00Z', 'F6 P4.5 38-cenario-f5-11-p2 posição funcional'),
  ('f5b2f000-0000-0000-0000-0000000000e5', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2f000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000b1', '2018-01-01T00:00:00Z', 'F6 P4.5 38-cenario-f5-11-p2 posição funcional'),
  ('f5b2f000-0000-0000-0000-0000000000e6', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2f000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000b1', '2018-01-01T00:00:00Z', 'F6 P4.5 38-cenario-f5-11-p2 posição funcional'),
  ('f5b2f000-0000-0000-0000-0000000000e7', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2f000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000b1', '2018-01-01T00:00:00Z', 'F6 P4.5 38-cenario-f5-11-p2 posição funcional');

insert into public.position_reporting_lines
  (organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000e2',
   'f5b2f000-0000-0000-0000-0000000000e1', 'estrutura sintetica F5-11 P2', '2018-01-01T00:00:00Z'),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000e3',
   'f5b2f000-0000-0000-0000-0000000000e1', 'estrutura sintetica F5-11 P2', '2018-01-01T00:00:00Z'),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000e4',
   'f5b2f000-0000-0000-0000-0000000000e1', 'estrutura sintetica F5-11 P2', '2018-01-01T00:00:00Z'),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000e7',
   'f5b2f000-0000-0000-0000-0000000000e1', 'estrutura sintetica F5-11 P2', '2018-01-01T00:00:00Z');

insert into public.occupations
  (organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to) values
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2e000-0000-0000-0000-0000000000c1',
   'f5b2f000-0000-0000-0000-0000000000e1', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2e000-0000-0000-0000-0000000000c2',
   'f5b2f000-0000-0000-0000-0000000000e2', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2e000-0000-0000-0000-0000000000c3',
   'f5b2f000-0000-0000-0000-0000000000e3', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2e000-0000-0000-0000-0000000000c4',
   'f5b2f000-0000-0000-0000-0000000000e4', 'ocupacao encerrada (desligamento)',
   '2019-01-01T00:00:00Z', '2020-01-01T00:00:00Z'),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2e000-0000-0000-0000-0000000000c5',
   'f5b2f000-0000-0000-0000-0000000000e5', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2e000-0000-0000-0000-0000000000c6',
   'f5b2f000-0000-0000-0000-0000000000e6', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null),
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b2e000-0000-0000-0000-0000000000c7',
   'f5b2f000-0000-0000-0000-0000000000e7', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- 5) Vinculos membership <-> colaborador (F4-02)
-- ----------------------------------------------------------------------------
insert into public.membership_collaborator_links
  (membership_id, organization_id, collaborator_id, status) values
  ('f5b2d000-0000-0000-0000-0000000000a1', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2e000-0000-0000-0000-0000000000c1', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a2', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2e000-0000-0000-0000-0000000000c5', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a3', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2e000-0000-0000-0000-0000000000c6', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a4', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2e000-0000-0000-0000-0000000000c8', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a5', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2e000-0000-0000-0000-0000000000c9', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000a6', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2e000-0000-0000-0000-0000000000c2', 'active'),
  ('f5b2d000-0000-0000-0000-0000000000b1', 'f5b2a000-0000-0000-0000-0000000000b1',
   'f5b2e000-0000-0000-0000-0000000000d1', 'active');

-- ----------------------------------------------------------------------------
-- 6) Ciclos soberanos (matriz do D12) — 1 ATIVO por organizacao
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim) values
  ('f5b21000-0000-0000-0000-0000000000a1', 'f5b2a000-0000-0000-0000-0000000000a1',
   2027, 1, 'ATIVO',     date '2027-01-01', date '2027-03-31'),
  ('f5b21000-0000-0000-0000-0000000000a2', 'f5b2a000-0000-0000-0000-0000000000a1',
   2027, 2, 'PLANEJADO', date '2027-04-01', date '2027-06-30'),
  ('f5b21000-0000-0000-0000-0000000000a3', 'f5b2a000-0000-0000-0000-0000000000a1',
   2026, 1, 'ENCERRADO', date '2026-01-01', date '2026-03-31'),
  ('f5b21000-0000-0000-0000-0000000000a4', 'f5b2a000-0000-0000-0000-0000000000a1',
   2027, 3, 'CANCELADO', date '2027-02-01', date '2027-02-28'),
  ('f5b21000-0000-0000-0000-0000000000b1', 'f5b2a000-0000-0000-0000-0000000000b1',
   2027, 1, 'ATIVO',     date '2027-01-01', date '2027-03-31');

-- ----------------------------------------------------------------------------
-- 7) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_perfis   int;
  v_memb     int;
  v_colabs   int;
  v_pos      int;
  v_linhas   int;
  v_ocup     int;
  v_status   int;
  v_links    int;
  v_ciclos   int;
  v_ativos   int;
  v_obs      int;
  v_ev       int;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('f5b2a000-0000-0000-0000-0000000000a1',
                'f5b2a000-0000-0000-0000-0000000000b1');
  select count(*) into v_perfis from public.user_profiles
   where id::text like 'f5b2c000-0000-0000-0000-0000000000%';
  select count(*) into v_memb from public.user_organization_memberships
   where id::text like 'f5b2d000-0000-0000-0000-0000000000%';
  select count(*) into v_colabs from public.collaborators
   where id::text like 'f5b2e000-0000-0000-0000-0000000000%';
  select count(*) into v_pos from public.organizational_positions
   where id::text like 'f5b2f000-0000-0000-0000-0000000000e%';
  select count(*) into v_linhas from public.position_reporting_lines
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and manager_position_id = 'f5b2f000-0000-0000-0000-0000000000e1';
  select count(*) into v_ocup from public.occupations
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and collaborator_id::text like 'f5b2e000-%';
  select count(*) into v_status from public.collaborator_status_periods
   where collaborator_id::text like 'f5b2e000-0000-0000-0000-0000000000%';
  select count(*) into v_links from public.membership_collaborator_links
   where organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                             'f5b2a000-0000-0000-0000-0000000000b1')
     and membership_id::text like 'f5b2d000-%';
  select count(*) into v_ciclos from public.evaluation_cycles
   where organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                             'f5b2a000-0000-0000-0000-0000000000b1')
     and id::text like 'f5b21000-%';
  select count(*) into v_ativos from public.evaluation_cycles
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1' and status = 'ATIVO'
     and id::text like 'f5b21000-%';
  select count(*) into v_obs from public.evaluation_observations
   where organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                             'f5b2a000-0000-0000-0000-0000000000b1');
  select count(*) into v_ev from public.evaluation_observation_events
   where organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                             'f5b2a000-0000-0000-0000-0000000000b1');

  if v_orgs <> 2 or v_perfis <> 7 or v_memb <> 7 or v_colabs <> 10
     or v_pos <> 7 or v_linhas <> 4 or v_ocup <> 7 or v_status <> 9
     or v_links <> 7 or v_ciclos <> 5 or v_ativos <> 1
     or v_obs <> 0 or v_ev <> 0 then
    raise exception
      '[FAIL] cenario F5-11 P2 incompleto (orgs=%, perfis=%, memberships=%, colabs=%, posicoes=%, linhas_do_gestor=%, ocupacoes=%, status=%, links=%, ciclos=%, ativos=%, obs=%, eventos=%)',
      v_orgs, v_perfis, v_memb, v_colabs, v_pos, v_linhas, v_ocup, v_status,
      v_links, v_ciclos, v_ativos, v_obs, v_ev;
  end if;

  raise notice '[PASS] cenario F5-11 P2: 2 organizacoes (Alfa e Beta), 7 identidades (GESTOR, SUB_ATIVO, OUTRO, SEM_CAP, PERFIL_INATIVO, MEMBERSHIP_OFF e BETA), 10 colaboradores, 7 posicoes com 4 subordinados diretos do GESTOR, 7 ocupacoes (1 encerrada pelo desligamento), 9 periodos de status (active/leave/inactive e 1 colaborador SEM status), 7 vinculos ativos, 5 ciclos (1 ATIVO por organizacao) e ZERO observacao/evento previos';
end $$;

\endif
