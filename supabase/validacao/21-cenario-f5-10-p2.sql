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
--   - a1 = ator Alfa com membership ATIVA e vinculo soberano ao colaborador
--     `...0001` (dono das metas de fixture do ciclo ENCERRADO);
--   - a2 = ator de OUTRO tenant (Beta) — prova de isolamento;
--   - a3 = ator Alfa com membership DISABLED — prova fail-closed;
--   - a4 = ator Alfa com perfil DISABLED (membership ativa) — prova que o PERFIL
--     ativo e exigido, nao apenas a membership (o CHECK da tabela so admite
--     `active`/`disabled`);
--   - a5 = ator Alfa ADICIONADO na adaptacao ao gate da P4: membership ATIVA e
--     vinculo soberano ao colaborador `...0002` (dono da meta viva de fixture
--     `...0008`). A partir da F5-10 P4 toda operacao de escrita exige `goal.write`
--     + SELF, e SELF e o vinculo UNICO ator -> colaborador DONO da meta (D9): por
--     isso as criacoes/mutacoes da meta do colaborador `...0002` sao executadas
--     por a5 no validador 22 (a1 so tem vinculo com `...0001`);
--   - 3 colaboradores SOBERANOS (2 em Alfa, 1 em Beta);
--   - VINCULOS soberanos (F5-02, `membership_collaborator_links`, status ativo)
--     exigidos pelo gate funcional da P4: a1 -> c1 (`...0001`), a5 -> c2
--     (`...0002`) e o ator de Beta -> colaborador de Beta (`...b1`). a3
--     (membership disabled) e a4 (perfil disabled) NAO recebem vinculo: o ator
--     soberano ja e recusado ANTES do gate (`evaluation_ator_valido`);
--   - AUTORIZACAO da fixture (P4/D6/D7): roles customizadas por tenant com
--     capabilities JA EXISTENTES do catalogo (`goal.read`, `goal.write` e
--     `cycle.manage` — nenhuma capability nova) e atribuicoes DIRETAS (dado da
--     fixture, mesmo padrao de `03-cenario-f5-09-p2.sql`; nenhuma RPC de
--     autorizacao e chamada aqui);
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
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  -- a5 (adaptacao P4): ator Alfa com vinculo soberano ao colaborador `...0002`.
  ('f0c00000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'dono.c2.f5-10-p2@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('f0c00000-0000-0000-0000-000000000001', 'active'),
  ('f0c00000-0000-0000-0000-000000000002', 'active'),
  ('f0c00000-0000-0000-0000-000000000003', 'active'),
  ('f0c00000-0000-0000-0000-000000000004', 'disabled'),
  ('f0c00000-0000-0000-0000-000000000005', 'active');

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
   'f0a00000-0000-0000-0000-0000000000a1', 'active'),
  ('f0d00000-0000-0000-0000-000000000005', 'f0c00000-0000-0000-0000-000000000005',
   'f0a00000-0000-0000-0000-0000000000a1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Colaboradores SOBERANOS (UUID; nenhuma matricula como identidade)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f0b00000-0000-0000-0000-000000000001', 'f0a00000-0000-0000-0000-0000000000a1'),
  ('f0b00000-0000-0000-0000-000000000002', 'f0a00000-0000-0000-0000-0000000000a1'),
  ('f0b00000-0000-0000-0000-0000000000b1', 'f0a00000-0000-0000-0000-0000000000b1');

-- ----------------------------------------------------------------------------
-- 3-bis) VINCULOS soberanos membro x colaborador (F5-02) — exigidos pelo gate
--        funcional da P4 (`f5_10_vinculo_meta_do_ator`: 0 ou >1 vinculo => DENY).
--        Cada ator de escrita tem EXATAMENTE UM vinculo ativo, apontando o
--        colaborador DONO das metas que aquele ator manipula (SELF, D9).
--        a3 (membership disabled) e a4 (perfil disabled) ficam SEM vinculo: sao
--        recusados por `evaluation_ator_valido` ANTES do gate.
-- ----------------------------------------------------------------------------
insert into public.membership_collaborator_links
  (id, membership_id, organization_id, collaborator_id, status) values
  -- a1 -> c1 (dono das metas de fixture do ciclo ENCERRADO).
  ('f0e00000-0000-0000-0000-000000000001', 'f0d00000-0000-0000-0000-000000000001',
   'f0a00000-0000-0000-0000-0000000000a1', 'f0b00000-0000-0000-0000-000000000001', 'active'),
  -- ator de Beta -> colaborador de Beta (tenant proprio).
  ('f0e00000-0000-0000-0000-0000000000b1', 'f0d00000-0000-0000-0000-000000000002',
   'f0a00000-0000-0000-0000-0000000000b1', 'f0b00000-0000-0000-0000-0000000000b1', 'active'),
  -- a5 (novo) -> c2 (dono da meta viva de fixture `...0008`).
  ('f0e00000-0000-0000-0000-000000000005', 'f0d00000-0000-0000-0000-000000000005',
   'f0a00000-0000-0000-0000-0000000000a1', 'f0b00000-0000-0000-0000-000000000002', 'active');

-- ----------------------------------------------------------------------------
-- 3-ter) AUTORIZACAO da fixture (P4/D6/D7): roles customizadas por tenant com
--        capabilities JA EXISTENTES do catalogo (`goal.read`, `goal.write`,
--        `cycle.manage` — nenhuma capability nova). Insercao DIRETA (dado da
--        fixture, sem RPC), no mesmo padrao de `03-cenario-f5-09-p2.sql`.
--          - `metas-dono-p2-alfa`: goal.read + goal.write, atribuida a a1 e a5;
--          - `metas-dono-p2-beta`: idem, atribuida ao ator de Beta (a integridade
--            cross-tenant da F4-01 exige role do MESMO tenant da membership);
--          - `ciclo-admin-p2-alfa`: cycle.manage (D21: `meta_definir_limites_do_
--            ciclo` continua operacao ADMINISTRATIVA de ciclo), atribuida a a1.
--        Nenhuma role e atribuida a a3/a4: o ator ja e recusado antes do gate.
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('f0a50000-0000-0000-0000-0000000000a1', 'metas-dono-p2-alfa', 'active', false,
   'f0a00000-0000-0000-0000-0000000000a1'),
  ('f0a50000-0000-0000-0000-0000000000a2', 'ciclo-admin-p2-alfa', 'active', false,
   'f0a00000-0000-0000-0000-0000000000a1'),
  ('f0a50000-0000-0000-0000-0000000000b1', 'metas-dono-p2-beta', 'active', false,
   'f0a00000-0000-0000-0000-0000000000b1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id in ('f0a50000-0000-0000-0000-0000000000a1',
                 'f0a50000-0000-0000-0000-0000000000b1')
   and c.code in ('goal.read', 'goal.write')
union all
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'f0a50000-0000-0000-0000-0000000000a2'
   and c.code = 'cycle.manage';

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f0a60000-0000-0000-0000-000000000001', 'f0d00000-0000-0000-0000-000000000001',
   'f0a00000-0000-0000-0000-0000000000a1', 'f0a50000-0000-0000-0000-0000000000a1',
   'active', 'f0c00000-0000-0000-0000-000000000001'),
  ('f0a60000-0000-0000-0000-000000000005', 'f0d00000-0000-0000-0000-000000000005',
   'f0a00000-0000-0000-0000-0000000000a1', 'f0a50000-0000-0000-0000-0000000000a1',
   'active', 'f0c00000-0000-0000-0000-000000000001'),
  ('f0a60000-0000-0000-0000-0000000000b1', 'f0d00000-0000-0000-0000-000000000002',
   'f0a00000-0000-0000-0000-0000000000b1', 'f0a50000-0000-0000-0000-0000000000b1',
   'active', 'f0c00000-0000-0000-0000-000000000002'),
  ('f0a60000-0000-0000-0000-0000000000a2', 'f0d00000-0000-0000-0000-000000000001',
   'f0a00000-0000-0000-0000-0000000000a1', 'f0a50000-0000-0000-0000-0000000000a2',
   'active', 'f0c00000-0000-0000-0000-000000000001');

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
  v_links    int;
  v_roles    int;
  v_assign   int;
  v_cap_a1w  int;
  v_cap_a1c  int;
  v_cap_a5w  int;
  v_cap_abw  int;
  v_cap_a3w  int;
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
  -- Vinculos e autorizacao da adaptacao P4 (aditivos; a guarda NAO conta nada
  -- que o validador 22 altere — metas/eventos sao contados separadamente).
  select count(*) into v_links from public.membership_collaborator_links
   where id::text like 'f0e00000%' and status = 'active';
  select count(*) into v_roles from public.access_roles
   where id::text like 'f0a50000%';
  select count(*) into v_assign from public.membership_access_role_assignments
   where id::text like 'f0a60000%' and status = 'active';

  if v_orgs <> 2 or v_atores <> 5 or v_memb <> 5 or v_ativos <> 4
     or v_colabs <> 3 or v_ciclos <> 3 or v_quota <> 4 or v_metas <> 2
     or v_aprov <> 0 or v_eventos <> 1
     or v_links <> 3 or v_roles <> 3 or v_assign <> 4 then
    raise exception
      '[FAIL] cenario F5-10 P2 incompleto (orgs=%, atores=%, memberships=%, ativas=%, colabs=%, ciclos=%, quotas=%, metas=%, aprovacoes=%, eventos=%, vinculos=%, roles=%, atribuicoes=%)',
      v_orgs, v_atores, v_memb, v_ativos, v_colabs, v_ciclos, v_quota,
      v_metas, v_aprov, v_eventos, v_links, v_roles, v_assign;
  end if;

  -- O gate da P4 exige CAPABILITY EFETIVA por tenant: a fixture prova que ela
  -- resolve exatamente para os atores designados (nenhum ator ganha goal.write
  -- por cargo/vinculo implicito).
  select count(*) into v_cap_a1w from public.resolver_capabilities_efetivas(
    'f0c00000-0000-0000-0000-000000000001', 'f0a00000-0000-0000-0000-0000000000a1')
   where capability_code = 'goal.write';
  select count(*) into v_cap_a1c from public.resolver_capabilities_efetivas(
    'f0c00000-0000-0000-0000-000000000001', 'f0a00000-0000-0000-0000-0000000000a1')
   where capability_code = 'cycle.manage';
  select count(*) into v_cap_a5w from public.resolver_capabilities_efetivas(
    'f0c00000-0000-0000-0000-000000000005', 'f0a00000-0000-0000-0000-0000000000a1')
   where capability_code = 'goal.write';
  select count(*) into v_cap_abw from public.resolver_capabilities_efetivas(
    'f0c00000-0000-0000-0000-000000000002', 'f0a00000-0000-0000-0000-0000000000b1')
   where capability_code = 'goal.write';
  select count(*) into v_cap_a3w from public.resolver_capabilities_efetivas(
    'f0c00000-0000-0000-0000-000000000003', 'f0a00000-0000-0000-0000-0000000000a1')
   where capability_code = 'goal.write';
  if v_cap_a1w <> 1 or v_cap_a1c <> 1 or v_cap_a5w <> 1
     or v_cap_abw <> 1 or v_cap_a3w <> 0 then
    raise exception '[FAIL] cenario F5-10 P2: fixture de autorizacao incorreta (a1 goal.write=%, a1 cycle.manage=%, a5 goal.write=%, beta goal.write=%, a3 membership disabled goal.write=%)',
      v_cap_a1w, v_cap_a1c, v_cap_a5w, v_cap_abw, v_cap_a3w;
  end if;

  -- Cada ator de escrita tem EXATAMENTE um vinculo soberano, apontando o
  -- colaborador dono das metas que ele manipula no validador 22 (SELF).
  if public.f5_10_vinculo_meta_do_ator(
       'f0c00000-0000-0000-0000-000000000001', 'f0a00000-0000-0000-0000-0000000000a1')
       is distinct from 'f0b00000-0000-0000-0000-000000000001'::uuid
     or public.f5_10_vinculo_meta_do_ator(
       'f0c00000-0000-0000-0000-000000000005', 'f0a00000-0000-0000-0000-0000000000a1')
       is distinct from 'f0b00000-0000-0000-0000-000000000002'::uuid
     or public.f5_10_vinculo_meta_do_ator(
       'f0c00000-0000-0000-0000-000000000002', 'f0a00000-0000-0000-0000-0000000000b1')
       is distinct from 'f0b00000-0000-0000-0000-0000000000b1'::uuid then
    raise exception '[FAIL] cenario F5-10 P2: vinculo soberano UNICO nao resolve o colaborador dono esperado para os atores de escrita da fixture';
  end if;

  raise notice '[PASS] cenario F5-10 P2: 2 orgs, 5 atores (a1 e a5 ativos com vinculo soberano unico, 1 de outro tenant, 1 membership disabled, 1 perfil disabled), 3 colaboradores, 3 vinculos, 3 roles com capabilities existentes do catalogo (goal.read/goal.write/cycle.manage), 3 ciclos (Alfa ATIVO + ENCERRADO, Beta ATIVO), 4 quotas, 2 metas de fixture e 1 evento — ZERO aprovacoes';
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
