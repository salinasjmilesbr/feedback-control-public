-- ============================================================================
-- F6 / Issue #427: CARDINALIDADE SOBERANA DE OCUPACOES — cenario sintetico
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: Issue #427 + comentario "Desenho tecnico fechado para
-- implementacao" (registrado na propria Issue) e a migration
-- `supabase/migrations/20261028000000_f6_issue427_cardinalidade_ocupacoes.sql`.
--
-- Fixture para `55-validar-f6-427.sql`. Este arquivo semeia SOMENTE o que as
-- provas precisam, com prefixos UUID EXCLUSIVOS desta Issue (verificados contra
-- TODOS os arquivos do repositorio): `f9a42700` organizacoes e `f9d42700`
-- memberships. A familia anterior (`f9a00000`/`f9d00000`) COLIDIA com
-- `01-cenario-f5-09.sql`, que o CI executa ANTES: o marcador insert-once ja
-- existia e o cenario virava no-op sem carregar a fixture (defeito do CI #570).
--   f9a42700 organizacoes        | f9b00000 auth.users/user_profiles
--   f9d42700 memberships         | f9c00000 colaboradores
--   f9800000 estrutura (units/positions/reporting/occupations/temporarias)
--   f9f00000 autorizacao (role customizada + scope) e ciclos/cenarios
--
-- INVARIANTE CENTRAL DESTA FIXTURE: NENHUMA ocupacao sobreposta para o MESMO
-- colaborador. A exclusion nova `ex_occupations_collaborator_no_overlap` torna
-- esse estado impossivel de semear; aqui ele e simplesmente inexistente. Os
-- unicos pares `[t0,t1)` seguidos de `[t1,t2)` do MESMO colaborador sao
-- CONSECUTIVOS (meio-aberto, sem sobreposicao) e por isso sao VALIDOS.
--
-- Cobertura semeada (card = `colaborador_ocupacoes_cardinalidade` na data):
--   c1  Alfa  2 linhas CONSECUTIVAS (P1 [2024,2033) e P3 [2033,inf)); card=1
--            em qualquer data — a fixture NAO contem estado ambiguo. As provas
--            usam a linha 1 (P1, fechada na prova 4b) e a linha 2 (P3);
--   c2  Alfa  ocupacao unica em P2 (aberta desde 2024) .................... 1
--   c3  Alfa  ocupacao unica em P5 (aberta); o validador a troca para P6 .. 1
--   c4  Alfa  P4 aberta; periodo `inactive` so em 2099 (fora do uso) ...... 1
--   c5  Beta  ocupacao unica em PB1 (aberta) .............................. 1
--   c6  Alfa  NENHUMA ocupacao (vaga e sem substituto) .................... 0
--   c7  Alfa  P9 aberta desde 2024 (destino OCUPADO da prova 7) ........... 1
--   c8/c9 Alfa  NENHUMA ocupacao: casos 0/>1 da prova de admissao pos-ativacao
--
-- O estado `cardinalidade > 1` NAO e semeado nem construido por este cenario:
-- a exclusion por colaborador o impede (ver "PROVA PARCIAL" no validador).
--
-- IDs reservados para o validador (semeados la, nunca aqui): uso das fixtures
-- c1..c9 como origem/destino das provas de `definir`/`trocar` e c6 como
-- substituto temporario de DUAS posicoes.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE / idempotente: reexecucao e NO-OP (guarda abaixo). A limpeza
--     usa `supabase db reset` (como no CI), pois `collaborator_events` e
--     append-only por contrato.
--   - Somente dados ficticios; nenhum dado real e pessoal.
--   - Nenhuma constraint/trigger e desabilitada; nenhum RLS/grant e alterado.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('f9a42700-0000-0000-0000-0000000000a1',
                'f9a42700-0000-0000-0000-0000000000b1')
) as cenario_f6_427_carregado \gset

\if :cenario_f6_427_carregado
do $$
declare
  v_org  uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_orgb uuid := 'f9a42700-0000-0000-0000-0000000000b1';
  v_n    int;
begin
  -- O marcador e EXCLUSIVO desta fixture (namespace `f9X42700`, verificado
  -- contra TODOS os arquivos do repositorio). Ainda assim, marcador presente com
  -- fixture INCOMPLETA e FALHA ALTA: nunca um no-op silencioso que deixaria o
  -- validador reprovar por pre-condicao (defeito observado no CI #570, quando o
  -- marcador era `f9a00000...a1/b1`, organizacoes ja criadas pelo
  -- `01-cenario-f5-09.sql`, e o cenario virava no-op sem carregar a fixture).
  select count(*) into v_n from public.organizations where id in (v_org, v_orgb);
  if v_n <> 2 then
    raise exception '[FAIL] cenario F6-427: marcador presente mas organizacoes=% (esperado 2) — estado parcial; reexecute apos `supabase db reset`', v_n;
  end if;
  select count(*) into v_n from public.collaborators where organization_id = v_org;
  if v_n <> 9 then
    raise exception '[FAIL] cenario F6-427: marcador presente mas colaboradores Alfa=% (esperado 9) — fixture INCOMPLETA; reexecute apos `supabase db reset`', v_n;
  end if;
  select count(*) into v_n from public.collaborators where organization_id = v_orgb;
  if v_n <> 1 then
    raise exception '[FAIL] cenario F6-427: marcador presente mas colaboradores Beta=% (esperado 1) — fixture INCOMPLETA; reexecute apos `supabase db reset`', v_n;
  end if;

  raise notice '[PASS] cenario F6-427 ja carregado — reexecucao no-op (fixture insert-once COMPLETA: 2 organizacoes, 9 colaboradores Alfa, 1 Beta)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f9a42700-0000-0000-0000-0000000000a1', 'Org Sintetica F6-427 Alfa'),
  ('f9a42700-0000-0000-0000-0000000000b1', 'Org Sintetica F6-427 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades sinteticas (auth.users) + perfis internos + memberships
--    a1 = ator ADMIN do tenant Alfa (role de sistema `admin`, sem vinculo)
--    a2 = ator Alfa COM membership ativa e SEM assignment (sem capability)
--    a3 = ator do tenant Beta (provas cross-tenant)
--    a4 = ator Alfa com membership DISABLED (fail-closed de ator)
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f9b00000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f6-427.admin@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('f9b00000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f6-427.semcap@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('f9b00000-0000-0000-0000-0000000000a3','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f6-427.beta@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now()),
  ('f9b00000-0000-0000-0000-0000000000a4','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f6-427.membdisabled@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now());

insert into public.user_profiles (id, status) values
  ('f9b00000-0000-0000-0000-0000000000a1','active'),
  ('f9b00000-0000-0000-0000-0000000000a2','active'),
  ('f9b00000-0000-0000-0000-0000000000a3','active'),
  ('f9b00000-0000-0000-0000-0000000000a4','active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status) values
  ('f9d42700-0000-0000-0000-0000000000a1','f9b00000-0000-0000-0000-0000000000a1','f9a42700-0000-0000-0000-0000000000a1','active'),
  ('f9d42700-0000-0000-0000-0000000000a2','f9b00000-0000-0000-0000-0000000000a2','f9a42700-0000-0000-0000-0000000000a1','active'),
  ('f9d42700-0000-0000-0000-0000000000b1','f9b00000-0000-0000-0000-0000000000a3','f9a42700-0000-0000-0000-0000000000b1','active'),
  ('f9d42700-0000-0000-0000-0000000000a4','f9b00000-0000-0000-0000-0000000000a4','f9a42700-0000-0000-0000-0000000000a1','disabled');

-- ----------------------------------------------------------------------------
-- 3) Autorizacao: role de SISTEMA `admin` (bundle com org.structure.manage,
--    org.catalog.manage, collaborator.*) atribuida a membership do ator Alfa com
--    scope ORGANIZATION — exatamente o que `resolver_capabilities_escopos_efetivas`
--    exige (assignment ativo + scope ativo). As RPC estruturais da F5-07/F5-08
--    revalidam no banco o ATOR (perfil ativo + membership ativa); a capability
--    `org.structure.manage` e a autorizacao do plano administrativo que a
--    fronteira confiavel exige — por isso ela e semeada ATIVA aqui.
-- ----------------------------------------------------------------------------
insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f9f00000-0000-0000-0000-0000000000a1','f9d42700-0000-0000-0000-0000000000a1',
   'f9a42700-0000-0000-0000-0000000000a1','c0000000-0000-4000-8000-0000000000f1',
   'active','f9b00000-0000-0000-0000-0000000000a1');

insert into public.access_role_assignment_scopes
  (id, assignment_id, organization_id, scope_type, status, created_by) values
  ('f9f00000-0000-0000-0000-0000000000b1','f9f00000-0000-0000-0000-0000000000a1',
   'f9a42700-0000-0000-0000-0000000000a1','ORGANIZATION','active',
   'f9b00000-0000-0000-0000-0000000000a1');

-- ----------------------------------------------------------------------------
-- 4) Catalogos e estrutura formal (unidades, posicoes, reporting lines)
--    Hierarquia: P2 -> P1, P3 -> P1, P4 -> P1, P6 -> P1.
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('f9800000-0000-0000-0000-0000000000e1','f9a42700-0000-0000-0000-0000000000a1','Analista F6-427','ANL-F6-427','active'),
  ('f9800000-0000-0000-0000-0000000000e2','f9a42700-0000-0000-0000-0000000000b1','Analista F6-427 Beta','ANL-F6-427-B','active');

insert into public.seniority_levels (id, organization_id, name) values
  ('f9800000-0000-0000-0000-0000000000e3','f9a42700-0000-0000-0000-0000000000a1','Pleno F6-427'),
  ('f9800000-0000-0000-0000-0000000000e4','f9a42700-0000-0000-0000-0000000000b1','Pleno F6-427 Beta');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f9800000-0000-0000-0000-0000000000b1','f9a42700-0000-0000-0000-0000000000a1','Unidade F6-427 Alfa','2024-01-01T00:00:00Z'),
  ('f9800000-0000-0000-0000-0000000000b2','f9a42700-0000-0000-0000-0000000000b1','Unidade F6-427 Beta','2024-01-01T00:00:00Z');

insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, name
) values
  ('f9800000-0000-0000-0000-0000000000c1','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1','f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P1'),
  ('f9800000-0000-0000-0000-0000000000c2','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1','f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P2'),
  ('f9800000-0000-0000-0000-0000000000c3','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1','f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P3'),
  ('f9800000-0000-0000-0000-0000000000c4','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1','f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P4'),
  ('f9800000-0000-0000-0000-0000000000c5','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1','f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P5'),
  ('f9800000-0000-0000-0000-0000000000c6','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1','f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P6'),
  ('f9800000-0000-0000-0000-0000000000c9','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1','f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P9'),
  ('f9800000-0000-0000-0000-0000000000d1','f9a42700-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000b2','f9800000-0000-0000-0000-0000000000e2','f9800000-0000-0000-0000-0000000000e4','2024-01-01T00:00:00Z','F6-427 posicao PB1');

insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('f9800000-0000-0000-0000-0000000000f1','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000c2','f9800000-0000-0000-0000-0000000000c1','reporting line F6-427 P2->P1','2024-01-01T00:00:00Z'),
  ('f9800000-0000-0000-0000-0000000000f2','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000c3','f9800000-0000-0000-0000-0000000000c1','reporting line F6-427 P3->P1','2024-01-01T00:00:00Z'),
  ('f9800000-0000-0000-0000-0000000000f3','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000c4','f9800000-0000-0000-0000-0000000000c1','reporting line F6-427 P4->P1','2024-01-01T00:00:00Z'),
  ('f9800000-0000-0000-0000-0000000000f4','f9a42700-0000-0000-0000-0000000000a1','f9800000-0000-0000-0000-0000000000c6','f9800000-0000-0000-0000-0000000000c1','reporting line F6-427 P6->P1','2024-01-01T00:00:00Z');

-- ----------------------------------------------------------------------------
-- 5) Colaboradores, identificadores, periodos de status e ocupacoes
-- ----------------------------------------------------------------------------
insert into public.collaborators
  (id, organization_id, full_name, email, admission_date) values
  ('f9c00000-0000-0000-0000-0000000000c1','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Um','colaborador.f6-427.1@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000c2','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Dois','colaborador.f6-427.2@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000c3','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Tres','colaborador.f6-427.3@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000c4','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Quatro','colaborador.f6-427.4@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000c5','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Cinco','colaborador.f6-427.5@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000c6','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Seis','colaborador.f6-427.6@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000c7','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Sete','colaborador.f6-427.7@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000c8','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Oito','colaborador.f6-427.8@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000c9','f9a42700-0000-0000-0000-0000000000a1','Colaborador F6-427 Nove','colaborador.f6-427.9@example.invalid', date '2024-01-01'),
  ('f9c00000-0000-0000-0000-0000000000b1','f9a42700-0000-0000-0000-0000000000b1','Colaborador F6-427 Beta','colaborador.f6-427.beta@example.invalid', date '2024-01-01');

insert into public.collaborator_identifiers
  (collaborator_id, organization_id, business_code, valid_from) values
  ('f9c00000-0000-0000-0000-0000000000c1','f9a42700-0000-0000-0000-0000000000a1','F6427-0001','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c2','f9a42700-0000-0000-0000-0000000000a1','F6427-0002','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c3','f9a42700-0000-0000-0000-0000000000a1','F6427-0003','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c4','f9a42700-0000-0000-0000-0000000000a1','F6427-0004','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c5','f9a42700-0000-0000-0000-0000000000a1','F6427-0005','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c6','f9a42700-0000-0000-0000-0000000000a1','F6427-0006','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c7','f9a42700-0000-0000-0000-0000000000a1','F6427-0007','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c8','f9a42700-0000-0000-0000-0000000000a1','F6427-0008','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c9','f9a42700-0000-0000-0000-0000000000a1','F6427-0009','2024-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000b1','f9a42700-0000-0000-0000-0000000000b1','F6427-9001','2024-01-01T00:00:00Z');

insert into public.collaborator_status_periods
  (collaborator_id, status, valid_from, valid_to) values
  ('f9c00000-0000-0000-0000-0000000000c1','active','2024-01-01T00:00:00Z',null),
  ('f9c00000-0000-0000-0000-0000000000c2','active','2024-01-01T00:00:00Z',null),
  ('f9c00000-0000-0000-0000-0000000000c3','active','2024-01-01T00:00:00Z',null),
  -- c4: o desligamento e FUTURO (2099) — nao interfere nas provas de ocupacao,
  -- que usam datas de 2032/2033; permanece como fixture de status fechado valido.
  ('f9c00000-0000-0000-0000-0000000000c4','active','2024-01-01T00:00:00Z','2099-01-01T00:00:00Z'),
  ('f9c00000-0000-0000-0000-0000000000c4','inactive','2099-01-01T00:00:00Z',null),
  ('f9c00000-0000-0000-0000-0000000000c5','active','2024-01-01T00:00:00Z',null),
  ('f9c00000-0000-0000-0000-0000000000c6','active','2024-01-01T00:00:00Z',null),
  ('f9c00000-0000-0000-0000-0000000000c7','active','2024-01-01T00:00:00Z',null),
  ('f9c00000-0000-0000-0000-0000000000c8','active','2024-01-01T00:00:00Z',null),
  ('f9c00000-0000-0000-0000-0000000000c9','active','2024-01-01T00:00:00Z',null),
  ('f9c00000-0000-0000-0000-0000000000b1','active','2024-01-01T00:00:00Z',null);

-- Ocupacoes: nenhuma sobreposicao por colaborador. O unico par consecutivo do
-- MESMO colaborador (c1 em P1 e c1 em P3) usa [2033-01-01, ...) exatamente no
-- fim do periodo anterior — VALIDO pela semantica meio-aberta.
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to) values
  ('f9800000-0000-0000-0000-000000000101','f9a42700-0000-0000-0000-0000000000a1','f9c00000-0000-0000-0000-0000000000c1','f9800000-0000-0000-0000-0000000000c1','ocupacao F6-427 c1 em P1','2024-01-01T00:00:00Z','2033-01-01T00:00:00Z'),
  ('f9800000-0000-0000-0000-000000000102','f9a42700-0000-0000-0000-0000000000a1','f9c00000-0000-0000-0000-0000000000c1','f9800000-0000-0000-0000-0000000000c3','ocupacao F6-427 c1 em P3 (consecutiva, meio-aberta)','2033-01-01T00:00:00Z',null),
  ('f9800000-0000-0000-0000-000000000103','f9a42700-0000-0000-0000-0000000000a1','f9c00000-0000-0000-0000-0000000000c2','f9800000-0000-0000-0000-0000000000c2','ocupacao F6-427 c2 em P2','2024-01-01T00:00:00Z',null),
  ('f9800000-0000-0000-0000-000000000104','f9a42700-0000-0000-0000-0000000000a1','f9c00000-0000-0000-0000-0000000000c3','f9800000-0000-0000-0000-0000000000c5','ocupacao F6-427 c3 em P5','2024-01-01T00:00:00Z',null),
  ('f9800000-0000-0000-0000-000000000105','f9a42700-0000-0000-0000-0000000000a1','f9c00000-0000-0000-0000-0000000000c4','f9800000-0000-0000-0000-0000000000c4','ocupacao F6-427 c4 em P4','2024-01-01T00:00:00Z',null),
  ('f9800000-0000-0000-0000-000000000106','f9a42700-0000-0000-0000-0000000000a1','f9c00000-0000-0000-0000-0000000000c7','f9800000-0000-0000-0000-0000000000c9','ocupacao F6-427 c7 em P9 (destino do definir)','2024-01-01T00:00:00Z',null),
  ('f9800000-0000-0000-0000-0000000001b1','f9a42700-0000-0000-0000-0000000000b1','f9c00000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000d1','ocupacao F6-427 cB em PB1','2024-01-01T00:00:00Z',null);

-- ----------------------------------------------------------------------------
-- 6) Evento soberano ADMISSAO — ator ADMIN do tenant, effective_date POSTERIOR a
--    ativacao do ciclo 2036 (semeado pelo validador) para que a prova
--    `ciclo_admissao_pos_ativacao_elegivel` isole a ESTRUTURA (P5), não a
--    admissao (P1/P7). c8 e c9 NAO possuem ocupacao (casos 0 e >1 da prova).
-- ----------------------------------------------------------------------------
insert into public.collaborator_events
  (organization_id, collaborator_id, position_id, event_type, effective_date,
   cycle_scope, reason, before_value, after_value, payload_hash,
   result_entity_id, actor_user_profile_id, actor_membership_id, operation_id)
values
  ('f9a42700-0000-0000-0000-0000000000a1','f9c00000-0000-0000-0000-0000000000c8',null,
   'ADMISSAO', now() - interval '30 days','CICLO_ATUAL_E_POSTERIORES',
   'Admissao soberana F6-427 c8', null, jsonb_build_object('origem','fixture'),
   repeat('c', 64),'f9c00000-0000-0000-0000-0000000000c8',
   'f9b00000-0000-0000-0000-0000000000a1','f9d42700-0000-0000-0000-0000000000a1',
   'f9f00000-0000-0000-0000-0000000000c1'),
  ('f9a42700-0000-0000-0000-0000000000a1','f9c00000-0000-0000-0000-0000000000c9',null,
   'ADMISSAO', now() - interval '30 days','CICLO_ATUAL_E_POSTERIORES',
   'Admissao soberana F6-427 c9', null, jsonb_build_object('origem','fixture'),
   repeat('d', 64),'f9c00000-0000-0000-0000-0000000000c9',
   'f9b00000-0000-0000-0000-0000000000a1','f9d42700-0000-0000-0000-0000000000a1',
   'f9f00000-0000-0000-0000-0000000000c2');

-- ----------------------------------------------------------------------------
-- 7) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_n        int;
  v_cap      int;
  v_sobrep   int;
  v_card_c1  int;
  v_card_c2  int;
  v_card_c6  int;
  v_pos_c2   uuid;
  v_gestor   uuid;
  v_escopo   int;
begin
  select count(*) into v_n from public.organizations
   where id in ('f9a42700-0000-0000-0000-0000000000a1',
                'f9a42700-0000-0000-0000-0000000000b1');
  if v_n <> 2 then
    raise exception '[FAIL] cenario F6-427: organizacoes esperadas=2, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.user_organization_memberships
   where id in ('f9d42700-0000-0000-0000-0000000000a1',
                'f9d42700-0000-0000-0000-0000000000a2',
                'f9d42700-0000-0000-0000-0000000000b1',
                'f9d42700-0000-0000-0000-0000000000a4');
  if v_n <> 4 then
    raise exception '[FAIL] cenario F6-427: memberships esperadas=4, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.collaborators where organization_id = 'f9a42700-0000-0000-0000-0000000000a1';
  if v_n <> 9 then
    raise exception '[FAIL] cenario F6-427: colaboradores Alfa esperados=9, encontrados=%', v_n;
  end if;

  select count(*) into v_n from public.occupations where organization_id = 'f9a42700-0000-0000-0000-0000000000a1';
  if v_n <> 6 then
    raise exception '[FAIL] cenario F6-427: ocupacoes Alfa esperadas=6, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.collaborator_events where organization_id = 'f9a42700-0000-0000-0000-0000000000a1';
  if v_n <> 2 then
    raise exception '[FAIL] cenario F6-427: eventos ADMISSAO esperados=2, encontrados=%', v_n;
  end if;

  -- A fixture NAO pode conter sobreposicao por colaborador (invariante da
  -- migration): se contivesse, o INSERT acima ja teria falhado; a consulta abaixo
  -- e a prova explicita de que o estado semeado e coerente com a barreira nova.
  select count(*) into v_sobrep
    from public.occupations a
    join public.occupations b
      on b.collaborator_id = a.collaborator_id
     and b.id > a.id
     and tstzrange(a.valid_from, coalesce(a.valid_to, 'infinity'::timestamptz), '[)')
      && tstzrange(b.valid_from, coalesce(b.valid_to, 'infinity'::timestamptz), '[)')
   where a.organization_id = 'f9a42700-0000-0000-0000-0000000000a1';
  if v_sobrep <> 0 then
    raise exception '[FAIL] cenario F6-427: fixture com % sobreposicao(oes) por colaborador', v_sobrep;
  end if;

  -- Cardinalidade esperada nas datas das provas.
  select public.colaborador_ocupacoes_cardinalidade('f9c00000-0000-0000-0000-0000000000c1','2033-06-01T00:00:00Z') into v_card_c1;
  if v_card_c1 <> 1 then
    raise exception '[FAIL] cenario F6-427: cardinalidade de c1 em 2033-06 deveria ser 1 (recebido %)', v_card_c1;
  end if;
  select public.colaborador_ocupacoes_cardinalidade('f9c00000-0000-0000-0000-0000000000c2','2033-06-01T00:00:00Z') into v_card_c2;
  if v_card_c2 <> 1 then
    raise exception '[FAIL] cenario F6-427: cardinalidade de c2 deveria ser 1 (recebido %)', v_card_c2;
  end if;
  select public.colaborador_ocupacoes_cardinalidade('f9c00000-0000-0000-0000-0000000000c6','2033-06-01T00:00:00Z') into v_card_c6;
  if v_card_c6 <> 0 then
    raise exception '[FAIL] cenario F6-427: c6 deveria estar SEM ocupacao (recebido %)', v_card_c6;
  end if;
  select public.colaborador_posicao_soberana('f9c00000-0000-0000-0000-0000000000c2','2033-06-01T00:00:00Z') into v_pos_c2;
  if v_pos_c2 is distinct from 'f9800000-0000-0000-0000-0000000000c2'::uuid then
    raise exception '[FAIL] cenario F6-427: posicao soberana de c2 divergente (%)', v_pos_c2;
  end if;

  -- Estrutura de escopo (origem unica) e hierarquia resolvem nas fontes F3.
  select r.manager_responsible_collaborator_id into v_gestor
    from public.organizacao_resolver_gestor_direto(
      'f9c00000-0000-0000-0000-0000000000c2','2033-06-01T00:00:00Z') r;
  if v_gestor is distinct from 'f9c00000-0000-0000-0000-0000000000c1'::uuid then
    raise exception '[FAIL] cenario F6-427: gestor direto de c2 deveria ser c1 (recebido %)', v_gestor;
  end if;
  select count(*) into v_escopo
    from public.organizacao_resolver_escopo_posicoes(
      'f9c00000-0000-0000-0000-0000000000c2','2033-06-01T00:00:00Z') e;
  if v_escopo < 2 then
    raise exception '[FAIL] cenario F6-427: escopo de c2 deveria ter >=2 posicoes (recebido %)', v_escopo;
  end if;

  -- A capability do plano estrutural resolve para o ator ADMIN e nao para o
  -- ator sem assignment.
  select count(*) into v_cap
    from public.resolver_capabilities_escopos_efetivas(
      'f9b00000-0000-0000-0000-0000000000a1','f9a42700-0000-0000-0000-0000000000a1') x
   where x.capability_code = 'org.structure.manage';
  if v_cap <> 1 then
    raise exception '[FAIL] cenario F6-427: ator ADMIN sem org.structure.manage (%)', v_cap;
  end if;
  select count(*) into v_cap
    from public.resolver_capabilities_escopos_efetivas(
      'f9b00000-0000-0000-0000-0000000000a2','f9a42700-0000-0000-0000-0000000000a1') x
   where x.capability_code = 'org.structure.manage';
  if v_cap <> 0 then
    raise exception '[FAIL] cenario F6-427: ator sem assignment resolveu org.structure.manage';
  end if;

  raise notice '[PASS] cenario F6-427 pronto: 2 organizacoes, 4 atores (admin/sem capability/Beta/membership disabled), 10 colaboradores, 7 posicoes, 4 reporting lines, 7 ocupacoes SEM sobreposicao por colaborador (c1 com par CONSECUTIVO) e 2 eventos ADMISSAO';
end $$;

\endif
