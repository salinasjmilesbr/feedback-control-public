-- ============================================================================
-- F6 / Issue #427: CARDINALIDADE SOBERANA DE OCUPACOES — CENARIO EXCLUSIVO DA
-- PROVA DE CONCORRENCIA (fixture 56)
-- (Supabase local apenas; NUNCA remoto)
-- ----------------------------------------------------------------------------
-- Contrato: Issue #427 + comentario "Desenho tecnico fechado para implementacao"
-- e a migration
-- `supabase/migrations/20261028000000_f6_issue427_cardinalidade_ocupacoes.sql`.
--
-- PAPEL DESTE ARQUIVO: criar a organizacao EXCLUSIVA da corrida de duas sessoes
-- PostgreSQL (`57-sessao-a-f6-427-concorrencia.sql` em BACKGROUND x
-- `58-sessao-b-f6-427-concorrencia.sql` em FOREGROUND) e o estado inicial
-- DETERMINISTICO que as duas disputam. O validador consolidado
-- `59-validar-f6-427-concorrencia.sql` confere o resultado depois das duas.
--
-- CONTRATO DE EXCLUSIVIDADE DESTA FIXTURE: a organizacao
--   `f427a000-0000-0000-0000-0000000000a1` (Org Sintetica F6-427 Concorrencia)
-- nasce AQUI e NAO e usada por nenhum outro validador (o cenario `55-cenario-
-- f6-427.sql` usa as organizacoes `f9a42700...a1/b1`). Se outro validador passar
-- a escrever nesta organizacao, os asserts da corrida e do validador 59 falham
-- com mensagem explicita — e a correcao e REATRIBUIR a organizacao, nunca
-- afrouxar a prova.
--
-- Prefixo UUID desta fixture: `f427` (issue #427). Nao colide com os prefixos
-- historicos (`d8`/`d2`/`d5`/`d6`/`d7`/`f8`/`f9`/`ea`/`ec`/`f6a2`/`f7`/`fc`...):
--   f427a000 organizacoes                | f427b000 auth.users/user_profiles
--   f427d000 memberships                 | f427c000 colaboradores
--   f4278000 estrutura (units/positions/occupations) e o id da insercao crua
--   f427f000 autorizacao (assignment + scope da role de sistema `admin`)
--   f4279000 operation_id da SESSAO A     | f4279100 operation_id da SESSAO B
--
-- ESTADO INICIAL SEMEADO (o alvo da corrida e IMUTAVEL):
--   colaborador X  f427c000-...-a1  OCUPA  XP1 f4278000-...-c1 desde 2024-01-01,
--                                   ABERTA (valid_to null). Vetor da JANELA 1.
--   colaborador Y  f427c000-...-a2  SEM ocupacao. Vetor da JANELA 2.
--   colaborador Z  f427c000-...-a3  SEM ocupacao. Vetor da JANELA 3.
--   posicoes (todas com valid_from 2024-01-01 e valid_to null, ou seja, abertas
--   e capazes de receber ocupacao em 2035/2036/2037/2038):
--     XP1 f4278000-...-c1 (ocupada por X)   XP2 f4278000-...-c2 (VAGA)
--     XP3 f4278000-...-c3 (VAGA)            YQ1 f4278000-...-c4 (VAGA)
--     YQ2 f4278000-...-c5 (VAGA)            ZR1 f4278000-...-c6 (VAGA)
--     ZR2 f4278000-...-c7 (VAGA — alvo da insercao CRUA da sessao B na janela 3)
--   ator soberano  f427b000-...-a1 (user_profile active) + membership ATIVA
--                  f427d000-...-a1 na organizacao da fixture; atende
--                  `public.colaborador_ator_valido` (perfil ativo + membership
--                  ativa no tenant), que e a UNICA revalidacao de ator das duas
--                  RPCs de ocupacao.
--
-- DIAS CIVIS RESERVADOS (normalizados para 00:00:00Z por `f6_vigencia_civil_utc`):
--   janela 1: A usa 2035-01-01Z e B usa 2035-01-02Z (dias DIFERENTES de
--             proposito: o veredito de B e a recusa DETERMINISTICA por posicao
--             atual divergente, nunca a guarda de "segunda transicao");
--   janela 2: A usa 2036-01-01Z e B usa 2036-02-01Z (mais tarde, para que a
--             intencao de B seja a SEGUNDA transicao serializada pelo banco);
--   janela 3: A usa 2037-01-01Z; a insercao crua de B usa
--             [2037-06-01Z, 2038-01-01Z), que SOBREPOE [2037-01-01Z, infinity).
--
-- INVARIANTE DA FIXTURE: nenhuma ocupacao sobreposta para o MESMO colaborador
-- (a exclusion nova `ex_occupations_collaborator_no_overlap` torna esse estado
-- impossivel de semear; aqui ele e simplesmente inexistente e conferido).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (`docker exec -i ... psql`). Nunca remoto.
--   - INSERT-ONCE / idempotente: reexecucao e NO-OP (guarda `\gset` + `\if`).
--     A limpeza da corrida e `supabase db reset` (as trilhas sao append-only por
--     contrato: `collaborator_events` nao aceita UPDATE/DELETE e as ocupacoes sao
--     historicas — reexecutar 56+57+58+59 sem reset NAO e suportado).
--   - Somente dados ficticios; nenhum dado real e pessoal.
--   - Nenhuma constraint/trigger e desabilitada; nenhum RLS/grant e alterado;
--     nenhum `SECURITY DEFINER` e criado.
--   - Ordem do CI: `db reset --local` -> fixtures -> `57` (BACKGROUND) ->
--     `sleep 1` -> `58` (FOREGROUND) -> `wait` -> `59`.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id = 'f427a000-0000-0000-0000-0000000000a1'
) as cenario_f6_427_conc_carregado \gset

\if :cenario_f6_427_conc_carregado
do $$
declare
  v_org uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_n   int;
begin
  -- O marcador e EXCLUSIVO desta fixture (organizacao `f427a000...a1`, usada por
  -- NENHUM outro arquivo do repositorio). Ainda assim, marcador presente com
  -- fixture INCOMPLETA e FALHA ALTA: nunca um no-op silencioso que deixaria as
  -- sessoes 57/58/59 reprovar por pre-condicao (mesma classe do defeito do CI
  -- #570, onde o marcador do 55-cenario ja existia por efeito de outro cenario).
  -- Nao se confere a contagem de OCUPACOES aqui: a corrida (57/58/59) as altera
  -- de proposito; a completude que importa e a estrutura fixa da fixture.
  select count(*) into v_n from public.collaborators where organization_id = v_org;
  if v_n <> 3 then
    raise exception '[FAIL] cenario F6-427 conc: marcador presente mas colaboradores=% (esperado 3) — fixture INCOMPLETA; reexecute apos `supabase db reset`', v_n;
  end if;
  select count(*) into v_n from public.organizational_positions where organization_id = v_org;
  if v_n <> 7 then
    raise exception '[FAIL] cenario F6-427 conc: marcador presente mas posicoes=% (esperado 7) — fixture INCOMPLETA; reexecute apos `supabase db reset`', v_n;
  end if;

  raise notice '[PASS] cenario F6-427 concorrencia ja carregado — reexecucao no-op (fixture insert-once COMPLETA: 3 colaboradores e 7 posicoes na organizacao exclusiva da corrida)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacao EXCLUSIVA da corrida
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f427a000-0000-0000-0000-0000000000a1','Org Sintetica F6-427 Concorrencia');

-- ----------------------------------------------------------------------------
-- 2) Ator soberano: auth.users + user_profiles + membership ATIVA + role de
--    sistema `admin` com scope ORGANIZATION (mesmo desenho do cenario 55). As
--    duas RPCs de ocupacao revalidam apenas `colaborador_ator_valido` (perfil
--    ativo + membership ativa); a autorizacao do plano administrativo e semeada
--    porque o contrato da fronteira confiavel a exige.
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f427b000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','f6-427.conc.ator@example.invalid','x',now(),'{}'::jsonb,'{}'::jsonb,now(),now());

insert into public.user_profiles (id, status) values
  ('f427b000-0000-0000-0000-0000000000a1','active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status) values
  ('f427d000-0000-0000-0000-0000000000a1','f427b000-0000-0000-0000-0000000000a1','f427a000-0000-0000-0000-0000000000a1','active');

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f427f000-0000-0000-0000-0000000000a1','f427d000-0000-0000-0000-0000000000a1',
   'f427a000-0000-0000-0000-0000000000a1','c0000000-0000-4000-8000-0000000000f1',
   'active','f427b000-0000-0000-0000-0000000000a1');

insert into public.access_role_assignment_scopes
  (id, assignment_id, organization_id, scope_type, status, created_by) values
  ('f427f000-0000-0000-0000-0000000000b1','f427f000-0000-0000-0000-0000000000a1',
   'f427a000-0000-0000-0000-0000000000a1','ORGANIZATION','active',
   'f427b000-0000-0000-0000-0000000000a1');

-- ----------------------------------------------------------------------------
-- 3) Catalogos e estrutura formal (1 unidade, 1 cargo, 1 senioridade, 7 posicoes
--    abertas). NAO ha reporting lines: as RPCs de ocupacao usam apenas a CHAVE
--    textual `position_reporting_lines:<organization_id>` no advisory lock — a
--    tabela `position_reporting_lines` nao e consultada por elas.
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name, code, status) values
  ('f4278000-0000-0000-0000-0000000000e1','f427a000-0000-0000-0000-0000000000a1','Analista F6-427 Conc','ANL-F6-427C','active');

insert into public.seniority_levels (id, organization_id, name) values
  ('f4278000-0000-0000-0000-0000000000e3','f427a000-0000-0000-0000-0000000000a1','Pleno F6-427 Conc');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f4278000-0000-0000-0000-0000000000b1','f427a000-0000-0000-0000-0000000000a1','Unidade F6-427 Conc','2024-01-01T00:00:00Z');

insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, name
) values
  ('f4278000-0000-0000-0000-0000000000c1','f427a000-0000-0000-0000-0000000000a1','f4278000-0000-0000-0000-0000000000b1','f4278000-0000-0000-0000-0000000000e1','f4278000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 conc posicao XP1 (origem de X)'),
  ('f4278000-0000-0000-0000-0000000000c2','f427a000-0000-0000-0000-0000000000a1','f4278000-0000-0000-0000-0000000000b1','f4278000-0000-0000-0000-0000000000e1','f4278000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 conc posicao XP2 (destino de A na janela 1)'),
  ('f4278000-0000-0000-0000-0000000000c3','f427a000-0000-0000-0000-0000000000a1','f4278000-0000-0000-0000-0000000000b1','f4278000-0000-0000-0000-0000000000e1','f4278000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 conc posicao XP3 (destino da intencao perdedora de B)'),
  ('f4278000-0000-0000-0000-0000000000c4','f427a000-0000-0000-0000-0000000000a1','f4278000-0000-0000-0000-0000000000b1','f4278000-0000-0000-0000-0000000000e1','f4278000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 conc posicao YQ1 (destino de A na janela 2)'),
  ('f4278000-0000-0000-0000-0000000000c5','f427a000-0000-0000-0000-0000000000a1','f4278000-0000-0000-0000-0000000000b1','f4278000-0000-0000-0000-0000000000e1','f4278000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 conc posicao YQ2 (destino de B na janela 2)'),
  ('f4278000-0000-0000-0000-0000000000c6','f427a000-0000-0000-0000-0000000000a1','f4278000-0000-0000-0000-0000000000b1','f4278000-0000-0000-0000-0000000000e1','f4278000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 conc posicao ZR1 (destino de A na janela 3)'),
  ('f4278000-0000-0000-0000-0000000000c7','f427a000-0000-0000-0000-0000000000a1','f4278000-0000-0000-0000-0000000000b1','f4278000-0000-0000-0000-0000000000e1','f4278000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 conc posicao ZR2 (VAGA; alvo da insercao crua de B na janela 3)');

-- ----------------------------------------------------------------------------
-- 4) Colaboradores X/Y/Z, identificadores e periodos de status `active`
-- ----------------------------------------------------------------------------
insert into public.collaborators
  (id, organization_id, full_name, email, admission_date) values
  ('f427c000-0000-0000-0000-0000000000a1','f427a000-0000-0000-0000-0000000000a1','Colaborador F6-427 Conc X','colaborador.f6-427.conc.x@example.invalid', date '2024-01-01'),
  ('f427c000-0000-0000-0000-0000000000a2','f427a000-0000-0000-0000-0000000000a1','Colaborador F6-427 Conc Y','colaborador.f6-427.conc.y@example.invalid', date '2024-01-01'),
  ('f427c000-0000-0000-0000-0000000000a3','f427a000-0000-0000-0000-0000000000a1','Colaborador F6-427 Conc Z','colaborador.f6-427.conc.z@example.invalid', date '2024-01-01');

insert into public.collaborator_identifiers
  (collaborator_id, organization_id, business_code, valid_from) values
  ('f427c000-0000-0000-0000-0000000000a1','f427a000-0000-0000-0000-0000000000a1','F6427C-X','2024-01-01T00:00:00Z'),
  ('f427c000-0000-0000-0000-0000000000a2','f427a000-0000-0000-0000-0000000000a1','F6427C-Y','2024-01-01T00:00:00Z'),
  ('f427c000-0000-0000-0000-0000000000a3','f427a000-0000-0000-0000-0000000000a1','F6427C-Z','2024-01-01T00:00:00Z');

insert into public.collaborator_status_periods
  (collaborator_id, status, valid_from, valid_to) values
  ('f427c000-0000-0000-0000-0000000000a1','active','2024-01-01T00:00:00Z',null),
  ('f427c000-0000-0000-0000-0000000000a2','active','2024-01-01T00:00:00Z',null),
  ('f427c000-0000-0000-0000-0000000000a3','active','2024-01-01T00:00:00Z',null);

-- ----------------------------------------------------------------------------
-- 5) Ocupacao inicial: SOMENTE X, em XP1, ABERTA desde 2024-01-01. Y e Z nascem
--    SEM ocupacao (os dois "0 vigentes" que as janelas 2 e 3 exercitam).
-- ----------------------------------------------------------------------------
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
values
  ('f4278000-0000-0000-0000-000000000101','f427a000-0000-0000-0000-0000000000a1','f427c000-0000-0000-0000-0000000000a1','f4278000-0000-0000-0000-0000000000c1','Ocupacao inicial F6-427 conc (X em XP1)','2024-01-01T00:00:00Z',null);

-- ----------------------------------------------------------------------------
-- 6) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org       uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator      uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_memb      uuid;
  v_x         uuid := 'f427c000-0000-0000-0000-0000000000a1';
  v_y         uuid := 'f427c000-0000-0000-0000-0000000000a2';
  v_z         uuid := 'f427c000-0000-0000-0000-0000000000a3';
  v_n         int;
  v_card      int;
  v_pos       uuid;
  v_args      text;
  v_def       text;
begin
  if not exists (select 1 from public.organizations o where o.id = v_org) then
    raise exception '[FAIL] cenario F6-427 conc: organizacao exclusiva da corrida (%) ausente', v_org;
  end if;

  select count(*) into v_n from public.collaborators c where c.organization_id = v_org;
  if v_n <> 3 then
    raise exception '[FAIL] cenario F6-427 conc: colaboradores esperados=3 (X/Y/Z), encontrados=% — a organizacao e EXCLUSIVA desta prova, nenhum outro validador pode escrever nela', v_n;
  end if;

  select count(*) into v_n from public.organizational_positions p where p.organization_id = v_org;
  if v_n <> 7 then
    raise exception '[FAIL] cenario F6-427 conc: posicoes esperadas=7, encontradas=%', v_n;
  end if;

  select count(*) into v_n from public.occupations o where o.organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] cenario F6-427 conc: ocupacoes esperadas=1 (somente X em XP1), encontradas=%', v_n;
  end if;

  -- X tem ORIGEM UNICA e ABERTA; Y e Z nao tem ocupacao alguma.
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = 'f4278000-0000-0000-0000-0000000000c1'
       and o.valid_from = '2024-01-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] cenario F6-427 conc: ocupacao inicial de X em XP1 (aberta desde 2024-01-01) ausente';
  end if;
  select count(*) into v_n from public.occupations o where o.organization_id = v_org and o.collaborator_id in (v_y, v_z);
  if v_n <> 0 then
    raise exception '[FAIL] cenario F6-427 conc: Y e Z deveriam nascer SEM ocupacao (encontradas %)', v_n;
  end if;

  -- Dias civis reservados ainda livres (protege contra reuso da fixture).
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.valid_from >= '2035-01-01T00:00:00Z';
  if v_n <> 0 then
    raise exception '[FAIL] cenario F6-427 conc: existem % ocupacao(oes) iniciando em 2035 ou depois — a trilha e append-only: reexecute a prova apos `supabase db reset --local`', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e where e.organization_id = v_org;
  if v_n <> 0 then
    raise exception '[FAIL] cenario F6-427 conc: a organizacao da corrida ja tem % evento(s) — a trilha e append-only: reexecute a prova apos `supabase db reset --local`', v_n;
  end if;

  -- INVARIANTE: nenhum par de ocupacoes sobrepostas do MESMO colaborador na
  -- organizacao exclusiva (estado semeado coerente com a barreira nova).
  select count(*) into v_n
    from public.occupations a
    join public.occupations b
      on b.collaborator_id = a.collaborator_id
     and b.id > a.id
     and tstzrange(a.valid_from, coalesce(a.valid_to,'infinity'::timestamptz), '[)')
      && tstzrange(b.valid_from, coalesce(b.valid_to,'infinity'::timestamptz), '[)')
   where a.organization_id = v_org;
  if v_n <> 0 then
    raise exception '[FAIL] cenario F6-427 conc: fixture com % sobreposicao(oes) por colaborador', v_n;
  end if;

  -- Cardinalidade inicial nas datas das janelas.
  select public.colaborador_ocupacoes_cardinalidade(v_x,'2034-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] cenario F6-427 conc: cardinalidade de X em 2034-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_x,'2034-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from 'f4278000-0000-0000-0000-0000000000c1'::uuid then
    raise exception '[FAIL] cenario F6-427 conc: posicao soberana de X em 2034-06 divergente (%)', v_pos;
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_y,'2034-06-01T00:00:00Z') into v_card;
  if v_card <> 0 then
    raise exception '[FAIL] cenario F6-427 conc: cardinalidade de Y em 2034-06 deveria ser 0 (recebido %)', v_card;
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_z,'2034-06-01T00:00:00Z') into v_card;
  if v_card <> 0 then
    raise exception '[FAIL] cenario F6-427 conc: cardinalidade de Z em 2034-06 deveria ser 0 (recebido %)', v_card;
  end if;

  -- Ator soberano: perfil ativo + membership ATIVA no tenant.
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator and m.organization_id = v_org and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] cenario F6-427 conc: membership ATIVA do ator da corrida ausente';
  end if;
  if not public.colaborador_ator_valido(v_ator, v_org) then
    raise exception '[FAIL] cenario F6-427 conc: colaborador_ator_valido falso para o ator da corrida (%)', v_ator;
  end if;

  -- Assinaturas EXATAS do contrato para as duas RPCs da corrida.
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)');
  if v_args is distinct from
     'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_position_id uuid, p_vigencia timestamp with time zone, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid' then
    raise exception '[FAIL] cenario F6-427 conc: assinatura de estrutura_ocupacao_definir fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)');
  if v_args is distinct from
     'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_current_position_id uuid, p_new_position_id uuid, p_vigencia timestamp with time zone, p_motivo text' then
    raise exception '[FAIL] cenario F6-427 conc: assinatura de estrutura_ocupacao_trocar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;

  -- Barreira final instalada: as DUAS exclusoes (posicao + colaborador) e a
  -- forma meio-aberta `[)` no texto da constraint nova.
  select count(*) into v_n from pg_constraint
   where conrelid = 'public.occupations'::regclass
     and conname in ('ex_occupations_position_no_overlap','ex_occupations_collaborator_no_overlap');
  if v_n <> 2 then
    raise exception '[FAIL] cenario F6-427 conc: exclusoes de occupations esperadas=2, encontradas=%', v_n;
  end if;
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'public.occupations'::regclass and c.conname = 'ex_occupations_collaborator_no_overlap';
  if v_def is null or position('[)' in v_def) = 0 or position('collaborator_id' in v_def) = 0 then
    raise exception '[FAIL] cenario F6-427 conc: constraint ex_occupations_collaborator_no_overlap ausente ou fora da forma meio-aberta [) (%)', coalesce(v_def,'ausente');
  end if;

  raise notice '[PASS] cenario F6-427 concorrencia pronto: organizacao EXCLUSIVA %, ator % (membership ativa %), X/Y/Z com 1/0/0 ocupacoes, 7 posicoes abertas, sem sobreposicao por colaborador, RPCs na assinatura do contrato e as duas exclusoes instaladas', v_org, v_ator, v_memb;
end $$;

\endif
