-- ============================================================================
-- F6 / Issue #427: CARDINALIDADE SOBERANA DE OCUPACOES — validacao automatizada
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (migrations)
--   2) `55-cenario-f6-427.sql` (fixture isolada)
--   3) este arquivo            (asserts `[PASS]` / `[FAIL]`)
--
-- CONCORRENCIA REAL (auditoria da #427): este arquivo e de SESSAO UNICA e prova a
-- BARREIRA, nao paralelismo. A disputa entre duas sessoes PostgreSQL — `definir`
-- x `trocar` sobre o mesmo colaborador, duas tentativas de ocupacao sobreposta,
-- ausencia de deadlock nao tratado e ausencia de efeito parcial — e provada por
-- `56-cenario-f6-427-concorrencia.sql`, `57-sessao-a-f6-427-concorrencia.sql`,
-- `58-sessao-b-f6-427-concorrencia.sql` e `59-validar-f6-427-concorrencia.sql`.
--
-- Contrato coberto: Issue #427 (comentario "Desenho tecnico fechado para
-- implementacao") + migration
-- `20261028000000_f6_issue427_cardinalidade_ocupacoes.sql`.
--
-- MATRIZ DE PROVAS DESTE ARQUIVO (cada linha isolada por colaborador/posicao):
--   1  mesma pessoa com periodos SOBREPOSTOS em posicoes DIFERENTES: o banco
--      recusa (23P01) e persiste UMA linha;
--   2  duas tentativas SEQUENCIAIS na MESMA sessao criando a sobreposicao:
--      nunca duas ocupacoes validas (prova da BARREIRA, nao de paralelismo real
--      — o psql aqui nao abre segunda sessao);
--   3  A [t0,t1) seguida de B [t1,t2) do MESMO colaborador: PERMITIDO, ambas
--      persistem e a cardinalidade e 0 antes, 1 em A, 1 em B;
--   4  `estrutura_ocupacao_definir` com 0 / 1 ocupacao atravessando a data:
--      contrato preservado; a guarda de `>1` e provada por texto + ausencia de
--      efeito parcial (a barreira temporal impede CONSTRUIR o estado >1);
--   5  `estrutura_ocupacao_trocar` com posicao atual ERRADA: recusa sem efeito;
--   6  `trocar` A->B + replay com o MESMO operation_id: idempotente (mesmo id,
--      exatamente um par OCUPACAO_INICIADA/OCUPACAO_ENCERRADA);
--   7  falha ao ABRIR B (posicao destino ocupada) desfaz o fechamento de A e nao
--      grava evento;
--   8  ator sem membership ativa / membership disabled / ator de outro tenant:
--      DENY sem mutacao;
--   9  escopo estrutural com origem UNICA: alcance correto (nao vazio);
--  10  PROVA PARCIAL: o DENY de origem ambigua e provado pelo predicado
--      fail-closed (`colaborador_posicao_soberana` NULL), pelas guardas
--      `c.qtd <= 1` no corpo das funcoes (`pg_get_functiondef`) e pela
--      constraint `ex_occupations_collaborator_no_overlap` (`pg_get_constraintdef`);
--  11  admissao/ativacao/avaliacao: `ESTRUTURA_IRRESOLVEL` para 0 (comportamental)
--      e `ESTRUTURA_AMBIGUA` (>1) por guarda textual; `materializar_colegiado_ciclo`
--      com 0 ocupacao persiste o snapshot (semantica preservada);
--  12  substituto temporario cobrindo DUAS posicoes: PERMITIDO.
--
-- ESTADO MUTADO E REAPLICABILIDADE: esta rodada FECHA ocupacoes (provas 4, 4b,
-- 6), ABRE ocupacoes (provas 4b, 6, 7, 8 e a fixture da prova 11) e grava
-- eventos. `collaborator_events` e append-only por contrato e as ocupacoes sao
-- historicas: reexecutar o par cenario+validador NAO e suportado sem
-- `supabase db reset` (o caminho correto e o do CI: reset -> cenario -> validador).
-- A prova 11 apenas ABRE a ocupacao de c9 quando ela ainda nao existe.
--
-- PROVA PARCIAL (declarada, nao escondida): as linhas 4(>1), 10 e 11(>1) NAO
-- constroem o estado `>1 ocupacao vigente do mesmo colaborador` porque a propria
-- barreira nova (`ex_occupations_collaborator_no_overlap`, exclusion GIST) o
-- impede — e o contrato desta Issue PROIBE desabilitar constraint/trigger para
-- fabricar o estado. A prova e feita pela via legitima: assercao textual das
-- guardas + prova comportamental do predicado fail-closed + prova de que a
-- barreira existe e recusa.
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer divergencia aborta.
-- Todos os negativos rodam em subtransacao (`begin ... exception ... end;`) para
-- que a falha de um nao aborte o arquivo, e cada um compara CONTAGENS antes/depois
-- ("falha nao pode deixar efeito parcial").
--
-- Este arquivo NAO desabilita constraint/trigger, NAO relaxa RLS/grants e NAO
-- cria `SECURITY DEFINER`. Dados exclusivamente ficticios (prefixo `f9`).
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture presente, barreira instalada, superficies fechadas
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_n     int;
  v_fn    text;
begin
  select count(*) into v_n from public.organizations
   where id in ('f9a42700-0000-0000-0000-0000000000a1',
                'f9a42700-0000-0000-0000-0000000000b1');
  if v_n <> 2 then
    raise exception '[FAIL] pre-condicao: fixture F6-427 ausente (orgs=%) — execute 55-cenario-f6-427.sql', v_n;
  end if;

  select count(*) into v_n from public.collaborators where organization_id = v_org;
  if v_n <> 9 then
    raise exception '[FAIL] pre-condicao: colaboradores Alfa esperados=9, encontrados=%', v_n;
  end if;

  -- A exclusao por POSICAO (historica) permanece; a exclusao por COLABORADOR e
  -- a barreira nova desta Issue.
  select count(*) into v_n from pg_constraint
   where conrelid = 'public.occupations'::regclass
     and conname in ('ex_occupations_position_no_overlap',
                     'ex_occupations_collaborator_no_overlap');
  if v_n <> 2 then
    raise exception '[FAIL] pre-condicao: exclusoes de ocupacao esperadas=2, encontradas=%', v_n;
  end if;

  -- As primitivas de cardinalidade e os dois caminhos de escrita existem, com a
  -- assinatura congelada, e continuam SECURITY INVOKER (nenhum DEFINER novo).
  foreach v_fn in array array[
    'colaborador_ocupacoes_cardinalidade', 'colaborador_posicao_soberana',
    'estrutura_ocupacao_definir', 'estrutura_ocupacao_trocar',
    'organizacao_resolver_gestor_direto', 'organizacao_resolver_subordinados_diretos',
    'organizacao_resolver_descendentes', 'organizacao_resolver_cadeia',
    'organizacao_resolver_escopo_posicoes', 'organizacao_resolver_avaliador_avaliado',
    'materializar_colegiado_ciclo', 'evaluation_snapshot_participantes',
    'ciclo_admissao_pos_ativacao_elegivel'] loop
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn and not p.prosecdef;
    if v_n < 1 then
      raise exception '[FAIL] pre-condicao: funcao public.% ausente ou SECURITY DEFINER (proibido)', v_fn;
    end if;
  end loop;

  -- Primitivas fechadas ao cliente (EXECUTE somente service_role).
  if has_function_privilege('authenticated',
       'public.colaborador_ocupacoes_cardinalidade(uuid, timestamptz)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.colaborador_ocupacoes_cardinalidade(uuid, timestamptz)', 'EXECUTE')
     or not has_function_privilege('service_role',
       'public.colaborador_ocupacoes_cardinalidade(uuid, timestamptz)', 'EXECUTE') then
    raise exception '[FAIL] pre-condicao: EXECUTE de colaborador_ocupacoes_cardinalidade fora do contrato (service_role apenas)';
  end if;
  if has_function_privilege('authenticated',
       'public.colaborador_posicao_soberana(uuid, timestamptz)', 'EXECUTE')
     or not has_function_privilege('service_role',
       'public.colaborador_posicao_soberana(uuid, timestamptz)', 'EXECUTE') then
    raise exception '[FAIL] pre-condicao: EXECUTE de colaborador_posicao_soberana fora do contrato (service_role apenas)';
  end if;

  -- A RPC de leitura/escrita estrutural continua fechada ao cliente.
  if has_function_privilege('authenticated',
       'public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)',
       'EXECUTE')
     or has_function_privilege('anon',
       'public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)',
       'EXECUTE') then
    raise exception '[FAIL] pre-condicao: superficie estrutural exposta a cliente (EXECUTE)';
  end if;

  raise notice '[PASS] pre-condicoes F6-427: fixture presente, exclusoes por posicao e por colaborador instaladas, 13 funcoes INVOKER presentes e primitivas de cardinalidade fechadas ao service_role';
end $$;

-- ----------------------------------------------------------------------------
-- 1) Sobreposicao em posicoes DIFERENTES do MESMO colaborador => 23P01
-- ----------------------------------------------------------------------------
do $$
declare
  v_org      uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c6       uuid := 'f9c00000-0000-0000-0000-0000000000c6';
  v_antes    int;
  v_depois   int;
  v_state    text := null;
  v_msg      text := null;
  v_ok       boolean := false;
begin
  -- c6 NAO possui ocupacao: a primeira insercao cria a origem unica.
  insert into public.occupations
    (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
  values ('f9f00000-0000-0000-0000-000000000201', v_org, v_c6,
          'f9800000-0000-0000-0000-0000000000c6','ocupacao F6-427 prova 1 (A)',
          '2040-01-01T00:00:00Z','2040-06-01T00:00:00Z');

  select count(*) into v_antes from public.occupations
   where collaborator_id = v_c6 and organization_id = v_org;
  if v_antes <> 1 then
    raise exception '[FAIL] 1: pre-condicao da prova deveria ter 1 ocupacao (tem %)', v_antes;
  end if;

  -- Sobreposicao REAL em posicao DIFERENTE: a posicao alvo e uma posicao NOVA
  -- (criada aqui) VAGA, de modo que a unica barreira capaz de recusar e a
  -- exclusion por COLABORADOR (a exclusion por POSICAO nao teria o que barrar).
  insert into public.organizational_positions
    (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, name)
  values ('f9800000-0000-0000-0000-0000000000cc', v_org,
          'f9800000-0000-0000-0000-0000000000b1',
          'f9800000-0000-0000-0000-0000000000e1',
          'f9800000-0000-0000-0000-0000000000e3',
          '2024-01-01T00:00:00Z','F6-427 posicao P1b (vaga, prova 1)');

  begin
    insert into public.occupations
      (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
    values ('f9f00000-0000-0000-0000-000000000202', v_org, v_c6,
            'f9800000-0000-0000-0000-0000000000cc','ocupacao F6-427 prova 1 (B)',
            '2040-03-01T00:00:00Z','2040-09-01T00:00:00Z');
  exception when others then
    v_state := SQLSTATE; v_msg := SQLERRM;
    if v_state = '23P01' then v_ok := true; end if;
  end;

  if not v_ok then
    raise exception '[FAIL] 1: sobreposicao por colaborador em posicoes diferentes NAO foi barrada (sqlstate=% msg=%)',
      v_state, v_msg;
  end if;
  if v_msg is null or position('ex_occupations_collaborator_no_overlap' in v_msg) = 0 then
    raise exception '[FAIL] 1: recusa 23P01 nao veio da exclusion por colaborador (msg=%)', v_msg;
  end if;

  -- "Falha nao pode deixar efeito parcial": somente a linha A persiste.
  select count(*) into v_depois from public.occupations
   where collaborator_id = v_c6 and organization_id = v_org;
  if v_depois <> 1 then
    raise exception '[FAIL] 1: apos a recusa deveria persistir 1 ocupacao (tem %)', v_depois;
  end if;

  raise notice '[PASS] 1: sobreposicao do MESMO colaborador em posicoes DIFERENTES recusada pelo banco (23P01, ex_occupations_collaborator_no_overlap) e apenas UMA linha persistiu';
end $$;

-- ----------------------------------------------------------------------------
-- 2) Duas tentativas SEQUENCIAIS da sobreposicao => nunca duas validas
-- ----------------------------------------------------------------------------
-- O ambiente disponivel e `psql` SEM segunda sessao: esta prova exercita a
-- BARREIRA (a constraint), nao o paralelismo verdadeiro entre transacoes. Duas
-- tentativas sequenciais de criar a sobreposicao (a segunda com outro
-- collaborator/posicao e outra janela) provam que o banco jamais aceita duas
-- ocupacoes validas simultaneas para a mesma pessoa.
do $$
declare
  v_org     uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c8      uuid := 'f9c00000-0000-0000-0000-0000000000c8';
  v_state1  text := null;
  v_state2  text := null;
  v_msg1    text := null;
  v_msg2    text := null;
  v_n       int;
  v_ok1     boolean := false;
  v_ok2     boolean := false;
begin
  -- Duas posicoes NOVAS e VAGAS (nos periodos usados): a unica barreira capaz de
  -- recusar as duas tentativas e a exclusion por COLABORADOR.
  insert into public.organizational_positions
    (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, name)
  values
    ('f9800000-0000-0000-0000-0000000000cd', v_org,
     'f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1',
     'f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P1c (vaga, prova 2)'),
    ('f9800000-0000-0000-0000-0000000000ce', v_org,
     'f9800000-0000-0000-0000-0000000000b1','f9800000-0000-0000-0000-0000000000e1',
     'f9800000-0000-0000-0000-0000000000e3','2024-01-01T00:00:00Z','F6-427 posicao P1d (vaga, prova 2)');

  insert into public.occupations
    (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
  values ('f9f00000-0000-0000-0000-000000000211', v_org, v_c8,
          'f9800000-0000-0000-0000-0000000000c5','ocupacao F6-427 prova 2 (A)',
          '2041-01-01T00:00:00Z', null);

  -- Tentativa 1 (concorrente imaginaria): mesmo colaborador, posicao diferente,
  -- janela sobreposta.
  begin
    insert into public.occupations
      (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
    values ('f9f00000-0000-0000-0000-000000000212', v_org, v_c8,
            'f9800000-0000-0000-0000-0000000000cd','ocupacao F6-427 prova 2 (B)',
            '2041-02-01T00:00:00Z','2041-12-01T00:00:00Z');
  exception when others then
    v_state1 := SQLSTATE; v_msg1 := SQLERRM;
    if v_state1 = '23P01'
       and position('ex_occupations_collaborator_no_overlap' in SQLERRM) > 0 then
      v_ok1 := true;
    end if;
  end;

  -- Tentativa 2 (a "outra sessao" que insistiria): janela que CONTEM a primeira.
  begin
    insert into public.occupations
      (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
    values ('f9f00000-0000-0000-0000-000000000213', v_org, v_c8,
            'f9800000-0000-0000-0000-0000000000ce','ocupacao F6-427 prova 2 (C)',
            '2040-12-01T00:00:00Z','2041-06-01T00:00:00Z');
  exception when others then
    v_state2 := SQLSTATE; v_msg2 := SQLERRM;
    if v_state2 = '23P01'
       and position('ex_occupations_collaborator_no_overlap' in SQLERRM) > 0 then
      v_ok2 := true;
    end if;
  end;

  if not v_ok1 or not v_ok2 then
    raise exception '[FAIL] 2: as duas tentativas sequenciais deveriam ser barradas (%, % / % / %)',
      v_state1, v_state2, v_msg1, v_msg2;
  end if;

  select count(*) into v_n from public.occupations
   where collaborator_id = v_c8 and organization_id = v_org;
  if v_n <> 1 then
    raise exception '[FAIL] 2: deveria persistir exatamente 1 ocupacao (tem %)', v_n;
  end if;

  -- Prova direta de que nao existe NENHUM par de ocupacoes validas sobrepostas
  -- por colaborador em todo o tenant.
  select count(*) into v_n
    from public.occupations a
    join public.occupations b
      on b.collaborator_id = a.collaborator_id
     and b.id > a.id
     and tstzrange(a.valid_from, coalesce(a.valid_to, 'infinity'::timestamptz), '[)')
      && tstzrange(b.valid_from, coalesce(b.valid_to, 'infinity'::timestamptz), '[)')
   where a.organization_id = v_org;
  if v_n <> 0 then
    raise exception '[FAIL] 2: existem % par(es) de ocupacoes sobrepostas do mesmo colaborador', v_n;
  end if;

  raise notice '[PASS] 2: duas tentativas SEQUENCIAIS de criar a sobreposicao foram barradas (23P01) e a tabela segue com exatamente 1 ocupacao valida — prova da BARREIRA de banco, nao de paralelismo real (psql sem segunda sessao)';
end $$;

-- ----------------------------------------------------------------------------
-- 3) Periodos CONSECUTIVOS [t0,t1) + [t1,t2) => PERMITIDO + cardinalidade
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c1     uuid := 'f9c00000-0000-0000-0000-0000000000c1';
  v_p1     uuid := 'f9800000-0000-0000-0000-0000000000c1';
  v_p3     uuid := 'f9800000-0000-0000-0000-0000000000c3';
  v_n      int;
  v_card   int;
  v_pos    uuid;
begin
  -- Sequencia CONSECUTIVA ja existente no cenario (c1: P1 [2024,2033) e
  -- P3 [2033,inf)). Nao ha exclusion violation porque o modelo e meio-aberto.
  select count(*) into v_n from public.occupations
   where collaborator_id = v_c1 and organization_id = v_org;
  if v_n <> 2 then
    raise exception '[FAIL] 3: c1 deveria ter 2 ocupacoes consecutivas (tem %)', v_n;
  end if;
  if exists (
    select 1 from public.occupations o
     where o.collaborator_id = v_c1 and o.organization_id = v_org
       and o.organizational_position_id = v_p1
       and o.valid_to is distinct from '2033-01-01T00:00:00Z'::timestamptz
  ) then
    raise exception '[FAIL] 3: o fim do periodo A deveria ser exatamente o inicio de B (2033-01-01Z)';
  end if;

  -- Cardinalidade: 0 antes de t0, 1 dentro de A, 1 dentro de B.
  select public.colaborador_ocupacoes_cardinalidade(v_c1,'2023-12-31T23:59:59Z') into v_card;
  if v_card <> 0 then
    raise exception '[FAIL] 3: cardinalidade ANTES de t0 deveria ser 0 (recebido %)', v_card;
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_c1,'2032-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] 3: cardinalidade DENTRO de A deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_c1,'2033-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] 3: cardinalidade DENTRO de B deveria ser 1 (recebido %)', v_card;
  end if;

  -- Limites do meio-aberto: em t1 exatamente, so B esta vigente.
  select public.colaborador_ocupacoes_cardinalidade(v_c1,'2033-01-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] 3: cardinalidade no INSTANTE da transicao deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_c1,'2033-01-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_p3 then
    raise exception '[FAIL] 3: posicao soberana no instante da transicao deveria ser B (%)', v_pos;
  end if;
  select public.colaborador_posicao_soberana(v_c1,'2032-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_p1 then
    raise exception '[FAIL] 3: posicao soberana dentro de A deveria ser A (%)', v_pos;
  end if;

  raise notice '[PASS] 3: periodos CONSECUTIVOS do mesmo colaborador sao validos (ambos persistem) e a cardinalidade e 0 antes de t0, 1 dentro de A, 1 dentro de B (meio-aberto: em t1 vale B)';
end $$;

-- ----------------------------------------------------------------------------
-- 4) estrutura_ocupacao_definir: 0 / 1 ocupacao atravessando a data
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_ator   uuid := 'f9b00000-0000-0000-0000-0000000000a1';
  v_c11    uuid := 'f9c00000-0000-0000-0000-0000000000c1';
  v_p11    uuid := 'f9800000-0000-0000-0000-0000000000c1';
  v_p12    uuid := 'f9800000-0000-0000-0000-0000000000c3';
  v_id1    uuid;
  v_id2    uuid;
  v_n      int;
begin
  -- Renomeia a fixture: c1 tem UMA ocupacao vigente em 2032 (P1) e nenhuma em
  -- 2031 (antes do inicio) — sao exatamente os casos "1" e "0" atravessando.
  select count(*) into v_n from public.occupations
   where collaborator_id = v_c11
     and organization_id = v_org
     and valid_from <= '2032-06-01T00:00:00Z'
     and (valid_to is null or valid_to > '2032-06-01T00:00:00Z');
  if v_n <> 1 then
    raise exception '[FAIL] 4: pre-condicao de c1 em 2032 deveria ter 1 ocupacao (tem %)', v_n;
  end if;
  select count(*) into v_n from public.occupations
   where collaborator_id = v_c11
     and organization_id = v_org
     and valid_from <= '2031-01-01T00:00:00Z'
     and (valid_to is null or valid_to > '2031-01-01T00:00:00Z');
  if v_n <> 0 then
    raise exception '[FAIL] 4: pre-condicao de c1 em 2031 deveria ter 0 ocupacao (tem %)', v_n;
  end if;

  -- (a) ZERO ocupacao atravessando a data: abre a PRIMEIRA ocupacao.
  v_id1 := public.estrutura_ocupacao_definir(
    v_org, v_ator, 'f9f00000-0000-0000-0000-000000000401'::uuid, v_c11, v_p11,
    '2031-01-01T00:00:00Z','Primeira ocupacao F6-427 (0 atravessando)',
    'CICLO_ATUAL_E_POSTERIORES', null);
  if v_id1 is null then
    raise exception '[FAIL] 4a: definir com 0 ocupacao atravessando deveria criar a ocupacao';
  end if;
  select count(*) into v_n from public.occupations
   where id = v_id1 and collaborator_id = v_c11 and organizational_position_id = v_p11
     and valid_from = '2031-01-01T00:00:00Z' and valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] 4a: ocupacao criada ausente/divergente (%)', v_n;
  end if;
  if (select count(*) from public.collaborator_events
       where organization_id = v_org and collaborator_id = v_c11
         and event_type = 'OCUPACAO_INICIADA'
         and effective_date = '2031-01-01T00:00:00Z') <> 1 then
    raise exception '[FAIL] 4a: evento OCUPACAO_INICIADA ausente para a primeira ocupacao';
  end if;

  -- (b) UMA ocupacao atravessando: fecha A em [t0,t1) e abre B em [t1,inf) —
  -- transicao CONSECUTIVA pelo caminho soberano (sem exclusion violation).
  v_id2 := public.estrutura_ocupacao_definir(
    v_org, v_ator, 'f9f00000-0000-0000-0000-000000000402'::uuid, v_c11, v_p12,
    '2032-06-01T00:00:00Z','Troca de posicao F6-427 (1 atravessando)',
    'CICLO_ATUAL_E_POSTERIORES', null);
  if v_id2 is null or v_id2 = v_id1 then
    raise exception '[FAIL] 4b: definir com 1 ocupacao atravessando deveria abrir NOVA ocupacao (%)', v_id2;
  end if;
  if not exists (select 1 from public.occupations where id = v_id1
                  and valid_to = '2032-06-01T00:00:00Z' and valid_to > valid_from) then
    raise exception '[FAIL] 4b: a ocupacao anterior deveria ter sido FECHADA em 2032-06-01Z';
  end if;
  if not exists (select 1 from public.occupations where id = v_id2
                  and valid_from = '2032-06-01T00:00:00Z' and valid_to is null) then
    raise exception '[FAIL] 4b: a nova ocupacao deveria nascer aberta em 2032-06-01Z';
  end if;

  -- Sem sobreposicao e com cardinalidade 1 nas duas datas.
  if (select public.colaborador_ocupacoes_cardinalidade(v_c11,'2031-06-01T00:00:00Z')) <> 1
     or (select public.colaborador_ocupacoes_cardinalidade(v_c11,'2033-01-01T00:00:00Z')) <> 1 then
    raise exception '[FAIL] 4b: cardinalidade deveria ser 1 nas duas datas';
  end if;

  -- A guarda de `>1` atravessando a data existe no corpo da funcao e a barreira
  -- de banco impede CONSTRUIR esse estado (prova textual declarada — ver bloco 10).
  if position('cardinalidade de ocupacao ambigua' in
       pg_get_functiondef('public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)'::regprocedure)) = 0 then
    raise exception '[FAIL] 4: guarda de cardinalidade ambigua ausente em estrutura_ocupacao_definir';
  end if;

  raise notice '[PASS] 4: estrutura_ocupacao_definir preserva o contrato com 0 (abre a primeira) e com 1 (fecha A e abre B na mesma transacao, sem sobreposicao); a recusa de >1 e CONFLICT textual + barreira de banco (PROVA PARCIAL do estado >1: nao e construivel pela via normal)';
end $$;

-- ----------------------------------------------------------------------------
-- 4b) Ausencia de efeito parcial nas recusas (contagens antes/depois)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org     uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c7      uuid := 'f9c00000-0000-0000-0000-0000000000c7';
  v_p6      uuid := 'f9800000-0000-0000-0000-0000000000c6';
  v_antes_oc int;
  v_antes_ev int;
  v_dep_oc   int;
  v_dep_ev   int;
  v_msg      text := null;
  v_state    text := null;
begin
  select count(*) into v_antes_oc from public.occupations where organization_id = v_org;
  select count(*) into v_antes_ev from public.collaborator_events where organization_id = v_org;

  -- c7 ja ocupa P9 desde 2024 (aberta). Definir P6 em data ANTERIOR ao inicio da
  -- ocupacao vigente deixaria uma janela futura sobreposta: a guarda da propria
  -- RPC recusa (>0 ocupacoes iniciando na vigencia ou depois dela) ou a exclusion
  -- barra — em QUALQUER caso, sem efeito parcial.
  begin
    perform public.estrutura_ocupacao_definir(
      v_org, 'f9b00000-0000-0000-0000-0000000000a1',
      'f9f00000-0000-0000-0000-000000000411'::uuid, v_c7, v_p6,
      '2024-06-01T00:00:00Z','Tentativa F6-427 com janela sobreposta',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
  end;

  if v_msg is null then
    raise exception '[FAIL] 4b: a tentativa sobreposta deveria ser recusada';
  end if;
  if v_state in ('42883','42703','42P01','42601','42804') then
    raise exception '[FAIL] 4b: chamada invalida a estrutura_ocupacao_definir (sqlstate=% msg=%)', v_state, v_msg;
  end if;
  if v_msg not like 'F5_07_%' and v_state <> '23P01' then
    raise exception '[FAIL] 4b: recusa fora do contrato (sqlstate=% msg=%)', v_state, v_msg;
  end if;

  select count(*) into v_dep_oc from public.occupations where organization_id = v_org;
  select count(*) into v_dep_ev from public.collaborator_events where organization_id = v_org;
  if v_dep_oc <> v_antes_oc or v_dep_ev <> v_antes_ev then
    raise exception '[FAIL] 4b: recusa deixou efeito parcial (ocupacoes % -> %, eventos % -> %)',
      v_antes_oc, v_dep_oc, v_antes_ev, v_dep_ev;
  end if;

  raise notice '[PASS] 4b: recusa de definicao com janela sobreposta nao alterou ocupacoes nem collaborator_events (nenhum efeito parcial)';
end $$;

-- ----------------------------------------------------------------------------
-- 5) estrutura_ocupacao_trocar com posicao atual ERRADA => sem efeito
-- ----------------------------------------------------------------------------
do $$
declare
  v_org      uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c2       uuid := 'f9c00000-0000-0000-0000-0000000000c2';
  v_p2       uuid := 'f9800000-0000-0000-0000-0000000000c2';
  v_p3       uuid := 'f9800000-0000-0000-0000-0000000000c3';
  v_antes_oc int;
  v_antes_ev int;
  v_msg      text := null;
  v_state    text := null;
  v_ok       boolean := false;
begin
  select count(*) into v_antes_oc from public.occupations where organization_id = v_org;
  select count(*) into v_antes_ev from public.collaborator_events where organization_id = v_org;

  -- c2 ocupa P2 (nao P3): informar P3 como "posicao atual" e divergencia de
  -- contrato => F5_07_CONFLICT, antes de qualquer DML.
  begin
    perform public.estrutura_ocupacao_trocar(
      v_org, 'f9b00000-0000-0000-0000-0000000000a1',
      'f9f00000-0000-0000-0000-000000000501'::uuid, v_c2, v_p3, v_p3,
      '2034-01-01T00:00:00Z','Troca F6-427 com posicao atual errada');
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if position('F5_07_CONFLICT' in SQLERRM) > 0
       and (position('posicao atual e nova devem ser diferentes' in SQLERRM) > 0
            or position('ocupacao vigente nao corresponde a posicao atual informada' in SQLERRM) > 0) then
      v_ok := true;
    end if;
  end;

  if not v_ok then
    raise exception '[FAIL] 5: trocar com posicao atual errada deveria recusar com F5_07_CONFLICT (sqlstate=% msg=%)',
      v_state, v_msg;
  end if;

  -- Prova com posicoes DISTINTAS (current errada != new): mesma recusa.
  v_msg := null; v_state := null; v_ok := false;
  begin
    perform public.estrutura_ocupacao_trocar(
      v_org, 'f9b00000-0000-0000-0000-0000000000a1',
      'f9f00000-0000-0000-0000-000000000502'::uuid, v_c2, v_p3, v_p2,
      '2034-01-01T00:00:00Z','Troca F6-427 com posicao atual errada (distinta)');
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if position('F5_07_CONFLICT' in SQLERRM) > 0
       and position('ocupacao vigente nao corresponde a posicao atual informada' in SQLERRM) > 0 then
      v_ok := true;
    end if;
  end;
  if not v_ok then
    raise exception '[FAIL] 5: trocar com current != ocupacao vigente deveria recusar (sqlstate=% msg=%)', v_state, v_msg;
  end if;

  -- A ocupacao de c2 continua ABERTA e intacta; nenhum evento foi gravado.
  if not exists (select 1 from public.occupations
                  where collaborator_id = v_c2 and organizational_position_id = v_p2
                    and valid_from = '2024-01-01T00:00:00Z' and valid_to is null) then
    raise exception '[FAIL] 5: a ocupacao vigente de c2 foi alterada pela tentativa recusada';
  end if;
  if (select count(*) from public.occupations where organization_id = v_org) <> v_antes_oc
     or (select count(*) from public.collaborator_events where organization_id = v_org) <> v_antes_ev then
    raise exception '[FAIL] 5: tentativa recusada deixou efeito parcial';
  end if;

  raise notice '[PASS] 5: estrutura_ocupacao_trocar com posicao atual ERRADA recusa com F5_07_CONFLICT, mantem a ocupacao vigente aberta e nao grava evento';
end $$;

-- ----------------------------------------------------------------------------
-- 6) trocar c3 A->B + replay com o MESMO operation_id => idempotente e auditado
-- ----------------------------------------------------------------------------
do $$
declare
  v_org      uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c3       uuid := 'f9c00000-0000-0000-0000-0000000000c3';
  v_p5       uuid := 'f9800000-0000-0000-0000-0000000000c5';
  v_p6       uuid := 'f9800000-0000-0000-0000-0000000000c6';
  v_op       uuid := 'f9f00000-0000-0000-0000-000000000601'::uuid;
  v_id1      uuid;
  v_id2      uuid;
  v_n        int;
  v_ini      int;
  v_enc      int;
begin
  -- Pre-condicao: c3 tem origem UNICA em P5 aberta desde 2024.
  if (select public.colaborador_ocupacoes_cardinalidade(v_c3,'2033-12-01T00:00:00Z')) <> 1 then
    raise exception '[FAIL] 6: pre-condicao: c3 deveria ter exatamente 1 ocupacao vigente';
  end if;

  v_id1 := public.estrutura_ocupacao_trocar(
    v_org, 'f9b00000-0000-0000-0000-0000000000a1', v_op, v_c3, v_p5, v_p6,
    '2033-01-01T00:00:00Z','Troca atomica F6-427 c3 P5->P6');
  if v_id1 is null then
    raise exception '[FAIL] 6: trocar deveria devolver o id da nova ocupacao';
  end if;

  -- Efeito: A fechada em t1, B aberta em t1, sem sobreposicao.
  if not exists (select 1 from public.occupations
                  where collaborator_id = v_c3 and organizational_position_id = v_p5
                    and valid_to = '2033-01-01T00:00:00Z') then
    raise exception '[FAIL] 6: a ocupacao de origem deveria ter sido fechada em 2033-01-01Z';
  end if;
  if not exists (select 1 from public.occupations
                  where id = v_id1 and collaborator_id = v_c3
                    and organizational_position_id = v_p6
                    and valid_from = '2033-01-01T00:00:00Z' and valid_to is null) then
    raise exception '[FAIL] 6: a nova ocupacao (B) nao foi aberta corretamente';
  end if;

  -- Auditoria: UM par OCUPACAO_INICIADA / OCUPACAO_ENCERRADA, ambos com o
  -- operation_id principal e o derivado deterministico.
  select count(*) into v_ini from public.collaborator_events
   where organization_id = v_org and collaborator_id = v_c3
     and event_type = 'OCUPACAO_INICIADA' and operation_id = v_op;
  select count(*) into v_enc from public.collaborator_events
   where organization_id = v_org and collaborator_id = v_c3
     and event_type = 'OCUPACAO_ENCERRADA'
     and operation_id = md5(v_op::text || ':OCUPACAO_ENCERRADA')::uuid;
  if v_ini <> 1 or v_enc <> 1 then
    raise exception '[FAIL] 6: esperado 1 par de eventos por operacao (iniciada=%, encerrada=%)', v_ini, v_enc;
  end if;
  if (select count(*) from public.occupations where organization_id = v_org) <> 8 then
    raise exception '[FAIL] 6: a troca deveria produzir 8 ocupacoes no tenant (A fechada + B aberta)';
  end if;

  -- REPLAY: mesmo operation_id, mesmo payload => MESMO id, nada novo.
  v_id2 := public.estrutura_ocupacao_trocar(
    v_org, 'f9b00000-0000-0000-0000-0000000000a1', v_op, v_c3, v_p5, v_p6,
    '2033-01-01T00:00:00Z','Troca atomica F6-427 c3 P5->P6');
  if v_id2 is distinct from v_id1 then
    raise exception '[FAIL] 6: replay devolveu id diferente (% / %)',
      coalesce(v_id1::text,'NULL'), coalesce(v_id2::text,'NULL');
  end if;

  select count(*) into v_n from public.collaborator_events
   where organization_id = v_org and collaborator_id = v_c3
     and event_type = 'OCUPACAO_INICIADA' and operation_id = v_op;
  if v_n <> 1 then
    raise exception '[FAIL] 6: replay duplicou OCUPACAO_INICIADA (%)', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events
   where organization_id = v_org and collaborator_id = v_c3
     and event_type = 'OCUPACAO_ENCERRADA'
     and operation_id = md5(v_op::text || ':OCUPACAO_ENCERRADA')::uuid;
  if v_n <> 1 then
    raise exception '[FAIL] 6: replay duplicou OCUPACAO_ENCERRADA (%)', v_n;
  end if;
  if (select count(*) from public.occupations where organization_id = v_org) <> 8 then
    raise exception '[FAIL] 6: replay criou/removeu ocupacao';
  end if;
  if (select public.colaborador_ocupacoes_cardinalidade(v_c3,'2033-06-01T00:00:00Z')) <> 1 then
    raise exception '[FAIL] 6: replay deixou cardinalidade diferente de 1';
  end if;

  -- operation_id repetido com INTENCAO DIVERGENTE => F5_07_CONFLICT sem efeito.
  begin
    perform public.estrutura_ocupacao_trocar(
      v_org, 'f9b00000-0000-0000-0000-0000000000a1', v_op, v_c3, v_p6, v_p5,
      '2033-01-01T00:00:00Z','Intencao divergente F6-427');
    raise exception '[FAIL] 6: operation_id repetido com payload divergente foi aceito';
  exception when others then
    if position('F5_07_CONFLICT' in SQLERRM) = 0 then
      raise exception '[FAIL] 6: divergencia deveria ser F5_07_CONFLICT (msg=%)', SQLERRM;
    end if;
  end;
  if (select count(*) from public.occupations where organization_id = v_org) <> 8 then
    raise exception '[FAIL] 6: a divergencia alterou as ocupacoes';
  end if;

  raise notice '[PASS] 6: trocar A->B cria exatamente um par OCUPACAO_INICIADA/OCUPACAO_ENCERRADA (operation_id principal + derivado) e o REPLAY com o mesmo operation_id devolve o MESMO id sem duplicar nada; divergencia de payload => F5_07_CONFLICT';
end $$;

-- ----------------------------------------------------------------------------
-- 7) Falha ao ABRIR B desfaz o fechamento de A e nao grava evento
-- ----------------------------------------------------------------------------
-- Caminho real de rollback: no corpo da RPC, o `update public.occupations`
-- (fechamento de A) vem ANTES da recusa "posicao destino ja possui ocupante"
-- — ou seja, a falha acontece DEPOIS do DML de fechamento. Como tudo roda numa
-- unica transacao, o erro desfaz o fechamento: A permanece ABERTA e nenhuma
-- trilha e gravada. Nenhuma constraint/trigger e desabilitado.
do $$
declare
  v_org      uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c8       uuid := 'f9c00000-0000-0000-0000-0000000000c8';
  v_p5       uuid := 'f9800000-0000-0000-0000-0000000000c5';
  v_p9       uuid := 'f9800000-0000-0000-0000-0000000000c9';
  v_antes_oc int;
  v_antes_ev int;
  v_dep_ev   int;
  v_msg      text := null;
  v_state    text := null;
  v_ok       boolean := false;
begin
  -- Fixture dedicada: A ABERTA (P5) e destino P9 JA ocupado por c7 (desde 2024,
  -- aberto). A origem de c8 e UNICA na data, portanto os guardas de
  -- cardinalidade passam e a recusa vem do destino ocupado — depois do UPDATE.
  insert into public.occupations
    (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
  values ('f9f00000-0000-0000-0000-000000000701', v_org, v_c8, v_p5,
          'ocupacao F6-427 prova 7 (A aberta)','2024-01-01T00:00:00Z', null);

  select count(*) into v_antes_oc from public.occupations where organization_id = v_org;
  select count(*) into v_antes_ev from public.collaborator_events where organization_id = v_org;

  begin
    perform public.estrutura_ocupacao_trocar(
      v_org, 'f9b00000-0000-0000-0000-0000000000a1',
      'f9f00000-0000-0000-0000-000000000711'::uuid, v_c8, v_p5, v_p9,
      '2042-01-01T00:00:00Z','Troca F6-427 com destino ja ocupado');
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if v_state = '23P01'
       or (v_msg like 'F5_07_CONFLICT%' and v_msg like '%ja possui ocupante vigente%') then
      v_ok := true;
    end if;
  end;

  if not v_ok then
    raise exception '[FAIL] 7: a troca para posicao ja ocupada deveria recusar (sqlstate=% msg=%)', v_state, v_msg;
  end if;

  -- ROLLBACK integral: A continua ABERTA (o fechamento foi desfeito) e B nao existe.
  if not exists (select 1 from public.occupations
                  where collaborator_id = v_c8 and organizational_position_id = v_p5
                    and valid_from = '2024-01-01T00:00:00Z' and valid_to is null) then
    raise exception '[FAIL] 7: a ocupacao de origem (A) foi fechada por uma operacao que falhou — efeito parcial';
  end if;
  if exists (select 1 from public.occupations
              where collaborator_id = v_c8 and organizational_position_id = v_p9) then
    raise exception '[FAIL] 7: a operacao que falhou criou a ocupacao de destino (B)';
  end if;
  if (select count(*) from public.occupations where organization_id = v_org) <> v_antes_oc then
    raise exception '[FAIL] 7: a contagem de ocupacoes mudou apos a falha';
  end if;

  select count(*) into v_dep_ev from public.collaborator_events
   where organization_id = v_org and collaborator_id = v_c8;
  if v_dep_ev <> 0 then
    raise exception '[FAIL] 7: a operacao que falhou gravou evento (%)', v_dep_ev;
  end if;
  if exists (select 1 from public.collaborator_events
              where organization_id = v_org
                and operation_id = 'f9f00000-0000-0000-0000-000000000711'::uuid) then
    raise exception '[FAIL] 7: a operacao que falhou deixou trilha com o proprio operation_id';
  end if;

  select count(*) into v_dep_ev from public.collaborator_events
   where organization_id = v_org;
  if v_dep_ev <> v_antes_ev then
    raise exception '[FAIL] 7: a contagem de eventos do tenant mudou apos a falha (% -> %)', v_antes_ev, v_dep_ev;
  end if;
  if public.colaborador_ocupacoes_cardinalidade(v_c8, now()) <> 1 then
    raise exception '[FAIL] 7: a origem de c8 deveria continuar unica e vigente apos a falha';
  end if;

  raise notice '[PASS] 7: falha ao ABRIR B (destino ja ocupado, depois do UPDATE de fechamento) desfaz o fechamento de A e nao grava evento — A permanece ABERTA, B nao existe e as contagens de ocupacoes/eventos sao identicas';
end $$;

-- ----------------------------------------------------------------------------
-- 8) Ator nao autorizado / cross-tenant => DENY sem mutacao
-- ----------------------------------------------------------------------------
do $$
declare
  v_alfa     uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_beta     uuid := 'f9a42700-0000-0000-0000-0000000000b1';
  v_ator_no  uuid := 'f9b00000-0000-0000-0000-0000000000a2';  -- membership ativa, sem assignment
  v_ator_dis uuid := 'f9b00000-0000-0000-0000-0000000000a4';  -- membership disabled
  v_ator_bet uuid := 'f9b00000-0000-0000-0000-0000000000a3';  -- ator do outro tenant
  v_c1       uuid := 'f9c00000-0000-0000-0000-0000000000c1';
  v_cb       uuid := 'f9c00000-0000-0000-0000-0000000000b1';
  v_p2       uuid := 'f9800000-0000-0000-0000-0000000000c2';
  v_pb       uuid := 'f9800000-0000-0000-0000-0000000000d1';
  v_antes_oc int;
  v_antes_ev int;
  v_msg      text := null;
  v_state    text := null;
  v_ok       boolean := false;
begin
  select count(*) into v_antes_oc from public.occupations;
  select count(*) into v_antes_ev from public.collaborator_events;

  -- (a) operacao NOVA (operation_id inedito) com ator sem membership ativa:
  -- cai na revalidacao de ator (perfil ativo + membership ativa) => FORBIDDEN.
  begin
    perform public.estrutura_ocupacao_definir(
      v_alfa, v_ator_no, 'f9f00000-0000-0000-0000-000000000801'::uuid, v_c1, v_p2,
      '2044-01-01T00:00:00Z','Ator sem assignment F6-427',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if v_msg like 'F5_07_FORBIDDEN%' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] 8a: ator sem membership ativa deveria ser F5_07_FORBIDDEN (sqlstate=% msg=%)',
      v_state, v_msg;
  end if;

  -- (b) membership DISABLED no tenant => FORBIDDEN.
  v_msg := null; v_state := null; v_ok := false;
  begin
    perform public.estrutura_ocupacao_definir(
      v_alfa, v_ator_dis, 'f9f00000-0000-0000-0000-000000000802'::uuid, v_c1, v_p2,
      '2044-01-01T00:00:00Z','Ator com membership disabled F6-427',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if v_msg like 'F5_07_FORBIDDEN%' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] 8b: ator com membership disabled deveria ser F5_07_FORBIDDEN (sqlstate=% msg=%)',
      v_state, v_msg;
  end if;

  -- (c) cross-tenant: ator de Beta operando colaborador de Alfa no tenant Alfa.
  v_msg := null; v_state := null; v_ok := false;
  begin
    perform public.estrutura_ocupacao_definir(
      v_alfa, v_ator_bet, 'f9f00000-0000-0000-0000-000000000803'::uuid, v_c1, v_p2,
      '2044-01-01T00:00:00Z','Ator cross-tenant F6-427',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if v_msg like 'F5_07_FORBIDDEN%' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] 8c: ator de outro tenant deveria ser F5_07_FORBIDDEN (sqlstate=% msg=%)',
      v_state, v_msg;
  end if;

  -- (d) colaborador de OUTRO tenant declarado no proprio tenant (recurso
  -- cross-tenant): NOT_FOUND, indistinguivel de inexistente, sem vazar tenant.
  v_msg := null; v_state := null; v_ok := false;
  begin
    perform public.estrutura_ocupacao_definir(
      v_alfa, 'f9b00000-0000-0000-0000-0000000000a1',
      'f9f00000-0000-0000-0000-000000000804'::uuid, v_cb, v_p2,
      '2044-01-01T00:00:00Z','Colaborador cross-tenant F6-427',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if v_msg like 'F5_07_NOT_FOUND%' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] 8d: colaborador de outro tenant deveria ser F5_07_NOT_FOUND (sqlstate=% msg=%)',
      v_state, v_msg;
  end if;
  if v_msg is not null and position('Beta' in v_msg) > 0 then
    raise exception '[FAIL] 8d: a recusa cross-tenant vazou o tenant do recurso (%)', v_msg;
  end if;

  -- Posicao de OUTRO tenant declarada no proprio tenant: NOT_FOUND.
  v_msg := null; v_state := null; v_ok := false;
  begin
    perform public.estrutura_ocupacao_definir(
      v_alfa, 'f9b00000-0000-0000-0000-0000000000a1',
      'f9f00000-0000-0000-0000-000000000805'::uuid, v_c1, v_pb,
      '2044-01-01T00:00:00Z','Posicao cross-tenant F6-427',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    v_msg := SQLERRM; v_state := SQLSTATE;
    if v_msg like 'F5_07_NOT_FOUND%' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] 8e: posicao de outro tenant deveria ser F5_07_NOT_FOUND (sqlstate=% msg=%)',
      v_state, v_msg;
  end if;

  -- ZERO efeito de TODAS as recusas: ocupacoes, eventos e o tenant Beta intactos.
  if (select count(*) from public.occupations) <> v_antes_oc
     or (select count(*) from public.collaborator_events) <> v_antes_ev then
    raise exception '[FAIL] 8: as recusas deixaram efeito parcial (ocupacoes % -> %, eventos % -> %)',
      v_antes_oc, (select count(*) from public.occupations),
      v_antes_ev, (select count(*) from public.collaborator_events);
  end if;
  if (select count(*) from public.occupations where organization_id = v_beta) <> 1 then
    raise exception '[FAIL] 8: o tenant Beta foi alterado';
  end if;

  raise notice '[PASS] 8: ator sem membership ativa, membership disabled, ator cross-tenant, colaborador cross-tenant e posicao cross-tenant => DENY (F5_07_FORBIDDEN/F5_07_NOT_FOUND) sem nenhuma mutacao e sem vazamento do tenant do recurso';
end $$;

-- ----------------------------------------------------------------------------
-- 9) Escopo estrutural com origem UNICA => alcance correto
-- ----------------------------------------------------------------------------
do $$
declare
  v_c2      uuid := 'f9c00000-0000-0000-0000-0000000000c2';
  v_p1      uuid := 'f9800000-0000-0000-0000-0000000000c1';
  v_p2      uuid := 'f9800000-0000-0000-0000-0000000000c2';
  v_c1      uuid := 'f9c00000-0000-0000-0000-0000000000c1';
  v_data    timestamptz := '2035-06-01T00:00:00Z';
  v_n       int;
  v_propria int;
  v_desce   int;
  v_gestor  uuid;
  v_sub     int;
  v_cadeia  int;
begin
  -- Pre-condicao: origem UNICA (1 ocupacao vigente na data).
  if public.colaborador_ocupacoes_cardinalidade(v_c2, v_data) <> 1 then
    raise exception '[FAIL] 9: pre-condicao: c2 deveria ter origem unica na data';
  end if;

  select count(*) into v_n
    from public.organizacao_resolver_escopo_posicoes(v_c2, v_data) e;
  if v_n < 2 then
    raise exception '[FAIL] 9: escopo de c2 deveria ter ao menos a propria posicao e um descendente (%)', v_n;
  end if;

  select count(*) into v_propria
    from public.organizacao_resolver_escopo_posicoes(v_c2, v_data) e
   where e.position_id = v_p2 and e.is_own_position is true;
  if v_propria <> 1 then
    raise exception '[FAIL] 9: a propria posicao (P2) deveria aparecer com is_own_position=true (%)', v_propria;
  end if;

  select count(*) into v_desce
    from public.organizacao_resolver_escopo_posicoes(v_c2, v_data) e
   where e.position_id = v_p2 and e.is_own_position is false;
  if v_desce <> 0 then
    raise exception '[FAIL] 9: P2 nao pode aparecer como descendente de si mesma (%)', v_desce;
  end if;

  -- Gestor direto: derivado da reporting line + ocupacao (c1 ocupa P1).
  select r.manager_position_id, r.manager_responsible_collaborator_id
    into v_n, v_gestor
    from public.organizacao_resolver_gestor_direto(v_c2, v_data) r;
  if v_gestor is distinct from v_c1 then
    raise exception '[FAIL] 9: gestor direto de c2 deveria ser c1 (recebido %)', v_gestor;
  end if;

  -- Subordinados diretos de c1 (ocupante de P1): P2 esta entre eles.
  select count(*) into v_sub
    from public.organizacao_resolver_subordinados_diretos(v_c1, v_data) s
   where s.subordinate_position_id = v_p2;
  if v_sub <> 1 then
    raise exception '[FAIL] 9: P2 deveria ser subordinada direta de P1 (%)', v_sub;
  end if;

  -- Cadeia ascendente de c2: inclui a propria posicao e o ancestral P1.
  select count(*) into v_cadeia
    from public.organizacao_resolver_cadeia(v_c2, v_data) ch
   where ch.position_id in (v_p1, v_p2);
  if v_cadeia < 2 then
    raise exception '[FAIL] 9: cadeia de c2 deveria conter P2 e P1 (%)', v_cadeia;
  end if;

  -- O resolver avaliativo (F3-09) tambem exige origem unica e resolve o superior.
  select count(*) into v_n
    from public.organizacao_resolver_avaliador_avaliado(v_c2, v_data) a
   where a.occupied_position_id = v_p2;
  if v_n <> 1 then
    raise exception '[FAIL] 9: resolver avaliativo de c2 deveria devolver 1 linha para P2 (%)', v_n;
  end if;

  raise notice '[PASS] 9: com origem UNICA o escopo estrutural e correto (propria posicao + descendentes), gestor/subordinados/cadeia/avaliativo resolvem pelas fontes F3-04/F3-07/F3-09';
end $$;

-- ----------------------------------------------------------------------------
-- 10) PROVA PARCIAL: DENY de origem ambigua por predicado + guarda textual
-- ----------------------------------------------------------------------------
-- Tentativa de construir o estado `>1 ocupacao vigente do mesmo colaborador`:
-- IMPOSSIVEL pela via normal, porque a propria barreira nova
-- (`ex_occupations_collaborator_no_overlap`) recusa. `set constraints all
-- deferred` NAO se aplica a exclusion constraints (nao diferiveis) e
-- desabilitar o trigger da constraint e PROIBIDO pelo contrato da Issue. A prova
-- segue pela via legitima: (i) o predicado fail-closed devolve NULL; (ii) o corpo
-- das funcoes contem a guarda `c.qtd <= 1`; (iii) a barreira existe e recusa.
do $$
declare
  v_n        int;
  v_null_pos uuid;
  v_card     int;
  v_def      text;
  v_bar      text;
  v_fn       text;
begin
  -- (i) Fail-closed de `colaborador_posicao_soberana`: com UMA origem devolve a
  -- posicao; quando a origem NAO e unica devolve NULL. O caso exercitado aqui e o
  -- de 0 ocupacoes (o mesmo `else null` do corpo cobre o caso `>1`).
  begin
    select public.colaborador_posicao_soberana('f9c00000-0000-0000-0000-0000000000c6','2033-06-01T00:00:00Z')
      into v_null_pos;
    select public.colaborador_ocupacoes_cardinalidade('f9c00000-0000-0000-0000-0000000000c6','2033-06-01T00:00:00Z')
      into v_card;
    if v_card <> 0 or v_null_pos is not null then
      raise exception '[FAIL] 10: predicado fail-closed divergente para 0 ocupacoes (card=%, posicao=%)',
        v_card, coalesce(v_null_pos::text,'NULL');
    end if;
  end;

  -- A posicao soberana e a posicao quando a cardinalidade e EXATAMENTE 1.
  if public.colaborador_posicao_soberana('f9c00000-0000-0000-0000-0000000000c2','2033-06-01T00:00:00Z')
     is distinct from 'f9800000-0000-0000-0000-0000000000c2'::uuid then
    raise exception '[FAIL] 10: posicao soberana deveria ser a origem unica';
  end if;

  -- (ii) Os SEIS resolvers estruturais carregam a guarda de origem unica.
  foreach v_fn in array array[
    'organizacao_resolver_gestor_direto', 'organizacao_resolver_subordinados_diretos',
    'organizacao_resolver_descendentes', 'organizacao_resolver_cadeia',
    'organizacao_resolver_escopo_posicoes', 'organizacao_resolver_avaliador_avaliado'] loop
    v_def := null;
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn and not p.prosecdef
     order by p.oid desc
     limit 1;
    if v_def is null then
      raise exception '[FAIL] 10: funcao % ausente', v_fn;
    end if;
    if position('c.qtd <= 1' in v_def) = 0 then
      raise exception '[FAIL] 10: guarda de origem unica (c.qtd <= 1) ausente em %', v_fn;
    end if;
    if position('cardinalidade' in v_def) = 0 then
      raise exception '[FAIL] 10: % sem a CTE/documentacao de cardinalidade', v_fn;
    end if;
  end loop;

  -- Os dois caminhos de snapshot/materializacao comprovam a cardinalidade ANTES
  -- de qualquer escrita.
  v_def := pg_get_functiondef('public.materializar_colegiado_ciclo(uuid, integer, integer, timestamptz, uuid[])'::regprocedure);
  if position('colaborador_ocupacoes_cardinalidade' in v_def) = 0
     or position('> 1' in v_def) = 0
     or position('recusada' in v_def) = 0 then
    raise exception '[FAIL] 10: materializar_colegiado_ciclo sem a prova de cardinalidade fail-closed';
  end if;
  v_def := pg_get_functiondef('public.evaluation_snapshot_participantes(uuid, uuid, uuid, uuid, timestamptz, uuid)'::regprocedure);
  if position('colaborador_ocupacoes_cardinalidade' in v_def) = 0
     or position('> 1' in v_def) = 0 then
    raise exception '[FAIL] 10: evaluation_snapshot_participantes sem a prova de cardinalidade fail-closed';
  end if;

  -- (iii) A barreira existe de fato, sobre colaborador + intervalo MEIO-ABERTO.
  select pg_get_constraintdef(c.oid) into v_bar
    from pg_constraint c
   where c.conrelid = 'public.occupations'::regclass
     and c.conname = 'ex_occupations_collaborator_no_overlap';
  if v_bar is null then
    raise exception '[FAIL] 10: constraint ex_occupations_collaborator_no_overlap ausente';
  end if;
  if position('collaborator_id' in v_bar) = 0
     or position('&&' in v_bar) = 0
     or v_bar not like '%''[)''%' then
    raise exception '[FAIL] 10: constraint por colaborador fora do contrato (%)', v_bar;
  end if;
  select pg_get_constraintdef(c.oid) into v_bar
    from pg_constraint c
   where c.conrelid = 'public.occupations'::regclass
     and c.conname = 'ex_occupations_position_no_overlap';
  if v_bar is null or position('organizational_position_id' in v_bar) = 0 then
    raise exception '[FAIL] 10: exclusao por POSICAO (historica) foi perdida';
  end if;

  raise notice '[PASS] 10 (PROVA PARCIAL): DENY de origem ambigua provado pelo predicado fail-closed (posicao soberana NULL quando a origem nao e unica e posicao correta quando e 1), pelas guardas c.qtd <= 1 nos SEIS resolvers e pela constraint ex_occupations_collaborator_no_overlap (meio-aberta) — o estado >1 nao e construivel sem desabilitar constraint (proibido)';
end $$;

-- ----------------------------------------------------------------------------
-- 11) Admissao/ativacao/avaliacao com 0 e (guarda) >1 ocupacoes
-- ----------------------------------------------------------------------------
-- Setup: Alfa ganha o ciclo 2036/1 ATIVO com ativacao ANTERIOR aos eventos
-- ADMISSAO da fixture (para que a prova isole a ESTRUTURA, nao a admissao).
-- c9 e ABERTO como origem UNICA e vigente (o estado nao-ambiguo do caminho
-- ELEGIVEL); a prova `>1` permanece textual (PROVA PARCIAL).
do $$
declare
  v_org uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_ano int := 2036;
  v_n   int;
begin
  insert into public.evaluation_cycles
    (id, organization_id, ano, numero, status, data_inicio, data_fim, data_ativacao, version)
  values ('f9f00000-0000-0000-0000-000000000901', v_org, v_ano, 1, 'ATIVO',
          date '2036-01-01', date '2036-06-30', '2020-01-01T00:00:00Z', 1);

  select count(*) into v_n from public.collaborators
   where organization_id = v_org and id = 'f9c00000-0000-0000-0000-0000000000c9';
  if v_n <> 1 then
    raise exception '[FAIL] 11: colaborador c9 da fixture ausente';
  end if;

  -- Origem UNICA e VIGENTE de c9 (guarda de reexecucao): a ocupacao e aberta
  -- AGORA, portanto atravessa `now()` do helper de admissao.
  if not exists (select 1 from public.occupations
                  where collaborator_id = 'f9c00000-0000-0000-0000-0000000000c9'
                    and valid_to is null) then
    insert into public.occupations
      (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from)
    values ('f9f00000-0000-0000-0000-000000000920', v_org,
            'f9c00000-0000-0000-0000-0000000000c9',
            'f9800000-0000-0000-0000-0000000000c2',
            'ocupacao F6-427 c9 (origem unica vigente)',
            now() - interval '30 days');
  end if;
  select count(*) into v_n from public.occupations
   where collaborator_id = 'f9c00000-0000-0000-0000-0000000000c9';
  if v_n <> 1 then
    raise exception '[FAIL] 11: c9 deveria ter EXATAMENTE 1 ocupacao (tem %)', v_n;
  end if;

  -- A guarda de ambiguidade existe no helper (via textual; o estado >1 nao e
  -- construivel pela via normal).
  if position('ESTRUTURA_AMBIGUA' in
       pg_get_functiondef('public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)'::regprocedure)) = 0 then
    raise exception '[FAIL] 11: ramo ESTRUTURA_AMBIGUA ausente em ciclo_admissao_pos_ativacao_elegivel';
  end if;
  if position('ESTRUTURA_IRRESOLVEL' in
       pg_get_functiondef('public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)'::regprocedure)) = 0 then
    raise exception '[FAIL] 11: ramo ESTRUTURA_IRRESOLVEL ausente em ciclo_admissao_pos_ativacao_elegivel';
  end if;
  if position('order by o.valid_from desc' in
       pg_get_functiondef('public.ciclo_admissao_pos_ativacao_elegivel(uuid, uuid, uuid)'::regprocedure)) > 0 then
    raise exception '[FAIL] 11: o helper voltou a ESCOLHER ocupacao por ordenacao';
  end if;

  raise notice '[PASS] 11 (setup): ciclo 2036/1 ATIVO criado, c9 com origem UNICA vigente e a guarda ESTRUTURA_AMBIGUA (sem escolha por ordenacao) presente no helper de admissao pos-ativacao';
end $$;

do $$
declare
  v_org   uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c3    uuid := 'f9c00000-0000-0000-0000-0000000000c3';
  v_p6    uuid := 'f9800000-0000-0000-0000-0000000000c6';
  v_c8    uuid := 'f9c00000-0000-0000-0000-0000000000c8';
  v_c9    uuid := 'f9c00000-0000-0000-0000-0000000000c9';
  v_cyc   uuid := 'f9f00000-0000-0000-0000-000000000901';
  v_res   jsonb;
  v_n     int;
begin
  -- (1) UMA ocupacao vigente agora (c3 em P6, aberta pela prova 6) => ELEGIVEL
  -- com posicao resolvida pela fonte relacional (occupations), nunca por ordenacao.
  if public.colaborador_ocupacoes_cardinalidade(v_c3, now()) <> 1 then
    raise exception '[FAIL] 11: pre-condicao: c3 deveria ter 1 ocupacao vigente agora';
  end if;
  v_res := public.ciclo_admissao_pos_ativacao_elegivel(v_org, v_cyc, v_c3);
  if coalesce(v_res->>'motivo','') <> 'ELEGIVEL'
     or coalesce((v_res->>'elegivel')::boolean, false) is not true then
    raise exception '[FAIL] 11: c3 (1 ocupacao) deveria ser ELEGIVEL (%)', v_res;
  end if;
  if (v_res->>'posicao_id')::uuid is distinct from v_p6 then
    raise exception '[FAIL] 11: posicao resolvida deveria ser P6 (%)', v_res->>'posicao_id';
  end if;

  -- (2) Segunda origem UNICA (c9, ocupacao aberta pela fixture desta prova) =>
  -- tambem ELEGIVEL: prova que o caminho nao-ambiguo nao depende de ordenacao.
  if public.colaborador_ocupacoes_cardinalidade(v_c9, now()) <> 1 then
    raise exception '[FAIL] 11: pre-condicao: c9 deveria ter 1 ocupacao vigente agora';
  end if;
  v_res := public.ciclo_admissao_pos_ativacao_elegivel(v_org, v_cyc, v_c9);
  if coalesce(v_res->>'motivo','') <> 'ELEGIVEL'
     or coalesce((v_res->>'elegivel')::boolean, false) is not true then
    raise exception '[FAIL] 11: c9 (1 ocupacao) deveria ser ELEGIVEL (%)', v_res;
  end if;

  -- (3) ZERO ocupacoes (c8: ativo, admissao soberana posterior a ativacao e SEM
  -- ocupacao) => ESTRUTURA_IRRESOLVEL, elegivel=false.
  if public.colaborador_ocupacoes_cardinalidade(v_c8, now()) <> 0 then
    raise exception '[FAIL] 11: pre-condicao: c8 deveria ter 0 ocupacao vigente';
  end if;
  v_res := public.ciclo_admissao_pos_ativacao_elegivel(v_org, v_cyc, v_c8);
  if coalesce(v_res->>'motivo','') <> 'ESTRUTURA_IRRESOLVEL'
     or coalesce((v_res->>'elegivel')::boolean, false) is not false then
    raise exception '[FAIL] 11: c8 (0 ocupacoes) deveria ser ESTRUTURA_IRRESOLVEL/elegivel=false (%)', v_res;
  end if;

  -- (4) `materializar_colegiado_ciclo` com 0 ocupacao: a semantica de "posicao
  -- vaga = ausencia de ocupacao" e PRESERVADA (snapshot existe, 0 posicoes) e a
  -- prova de cardinalidade roda ANTES da escrita (c8 e legado sem ocupacao).
  perform public.materializar_colegiado_ciclo(v_org, 2036, 2, '2020-06-01T00:00:00Z', array[v_c8]);
  select count(*) into v_n from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2036 and s.ciclo = 2 and s.collaborator_id = v_c8;
  if v_n <> 1 then
    raise exception '[FAIL] 11: materializacao de c8 (0 ocupacao) deveria criar 1 snapshot (%)', v_n;
  end if;
  select count(*) into v_n
    from public.collegiate_cycle_snapshot_positions sp
    join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
   where s.organization_id = v_org and s.ano = 2036 and s.ciclo = 2
     and s.collaborator_id = v_c8;
  if v_n <> 0 then
    raise exception '[FAIL] 11: snapshot de c8 (0 ocupacao) nao deveria ter posicao (%)', v_n;
  end if;

  -- Reexecucao idempotente: nao duplica snapshot nem posicao.
  perform public.materializar_colegiado_ciclo(v_org, 2036, 2, '2020-06-01T00:00:00Z', array[v_c8]);
  select count(*) into v_n from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2036 and s.ciclo = 2 and s.collaborator_id = v_c8;
  if v_n <> 1 then
    raise exception '[FAIL] 11: reexecucao duplicou snapshot (%)', v_n;
  end if;

  -- (5) `materializar_colegiado_ciclo` com 1 ocupacao vigente NA referencia:
  -- congela a posicao ocupada (prova de que o caminho nao-ambiguo materializa).
  perform public.materializar_colegiado_ciclo(v_org, 2036, 3, '2033-06-01T00:00:00Z', array[v_c3]);
  select count(*) into v_n
    from public.collegiate_cycle_snapshot_positions sp
    join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
   where s.organization_id = v_org and s.ano = 2036 and s.ciclo = 3
     and s.collaborator_id = v_c3 and sp.position_id = v_p6;
  if v_n <> 1 then
    raise exception '[FAIL] 11: snapshot de c3 deveria congelar a posicao P6 (%)', v_n;
  end if;

  -- (6) A recusa por `>1` e textual (PROVA PARCIAL declarada) e o caminho de
  -- admissao NAO escolhe ocupacao por ordenacao.
  if position('cardinalidade de ocupacao ambigua' in
       pg_get_functiondef('public.materializar_colegiado_ciclo(uuid, integer, integer, timestamptz, uuid[])'::regprocedure)) = 0 then
    raise exception '[FAIL] 11: materializar_colegiado_ciclo sem a recusa por cardinalidade ambigua';
  end if;

  raise notice '[PASS] 11: admissao pos-ativacao com 1 ocupacao (c3 e c9) => ELEGIVEL com a posicao da fonte ocupacao e com 0 (c8) => ESTRUTURA_IRRESOLVEL/elegivel=false; materializar_colegiado_ciclo persiste o snapshot sem posicao para 0 e congela a posicao para 1 (idempotente); a recusa de >1 e guarda textual (PROVA PARCIAL)';
end $$;

-- ----------------------------------------------------------------------------
-- 12) Substituto cobrindo DUAS posicoes => PERMITIDO (temporary_responsibilities)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org     uuid := 'f9a42700-0000-0000-0000-0000000000a1';
  v_c15     uuid := 'f9c00000-0000-0000-0000-0000000000c6';
  v_p1      uuid := 'f9800000-0000-0000-0000-0000000000c1';
  v_p3      uuid := 'f9800000-0000-0000-0000-0000000000c3';
  v_n       int;
  v_antes   int;
begin
  select count(*) into v_antes from public.temporary_responsibilities
   where organization_id = v_org;

  -- c6 NAO tem ocupacao (nenhuma occupation e criada por esta prova) e assume DUAS
  -- posicoes simultaneas: a exclusion de temporary_responsibilities e por POSICAO,
  -- nunca por substituto — substituicao nao e ocupacao (F3-06 / secao 7 da #427).
  insert into public.temporary_responsibilities
    (id, organization_id, organizational_position_id, substitute_collaborator_id,
     responsibility_type, reason, valid_from, valid_to)
  values
    ('f9f00000-0000-0000-0000-000000000a01', v_org, v_p1, v_c15,
     'operational','Substituicao temporaria F6-427 em P1',
     '2036-01-01T00:00:00Z','2036-03-01T00:00:00Z'),
    ('f9f00000-0000-0000-0000-000000000a02', v_org, v_p3, v_c15,
     'operational_evaluative','Substituicao temporaria F6-427 em P3',
     '2036-01-01T00:00:00Z','2036-03-01T00:00:00Z');

  select count(*) into v_n from public.temporary_responsibilities
   where organization_id = v_org and substitute_collaborator_id = v_c15
     and valid_from <= '2036-02-01T00:00:00Z' and valid_to > '2036-02-01T00:00:00Z';
  if v_n <> 2 then
    raise exception '[FAIL] 12: o substituto deveria cobrir 2 posicoes simultaneas (%)', v_n;
  end if;
  if (select count(*) from public.temporary_responsibilities where organization_id = v_org) <> v_antes + 2 then
    raise exception '[FAIL] 12: as duas substituicoes nao persistiram';
  end if;

  -- As DUAS posicoes resolvem o substituto (responsavel) na mesma data.
  if (select count(*) from public.organizacao_resolver_responsavel_posicao(v_p1,'2036-02-01T00:00:00Z') r
       where r.responsible_collaborator_id = v_c15) <> 1
     or (select count(*) from public.organizacao_resolver_responsavel_posicao(v_p3,'2036-02-01T00:00:00Z') r
       where r.responsible_collaborator_id = v_c15) <> 1 then
    raise exception '[FAIL] 12: as duas posicoes deveriam resolver o mesmo substituto';
  end if;

  -- A substituicao NAO e ocupacao: c15 tem DUAS linhas de responsabilidade
  -- temporaria e ZERO ocupacao no periodo (a ocupacao de c15, prova 1, so comeca
  -- em 2040) — a barreira nova nao e consumida por substituicao.
  if public.colaborador_ocupacoes_cardinalidade(v_c15,'2036-01-01T00:00:00Z') <> 0
     or public.colaborador_ocupacoes_cardinalidade(v_c15,'2036-02-01T00:00:00Z') <> 0
     or public.colaborador_ocupacoes_cardinalidade(v_c15,'2036-03-01T00:00:00Z') <> 0 then
    raise exception '[FAIL] 12: substituicao temporaria nao pode virar ocupacao';
  end if;
  if (select count(*) from public.occupations where collaborator_id = v_c15) <> 1 then
    raise exception '[FAIL] 12: a prova de substituicao criou/removeu ocupacao de c15';
  end if;

  raise notice '[PASS] 12: o MESMO colaborador como substituto de DUAS posicoes simultaneas e PERMITIDO (exclusion por posicao, nunca por substituto), sem criar occupation e sem afetar a cardinalidade de ocupacoes';
end $$;

-- ----------------------------------------------------------------------------
-- 13) Resumo final
-- ----------------------------------------------------------------------------
do $$
begin
  raise notice '[PASS] F6-427 resumo: barreira por colaborador (23P01), consecutividade meio-aberta, definir/trocar (0 e 1 atravessando, sem efeito parcial), idempotencia por operation_id, rollback de falha DEPOIS do DML, DENY por ator/cross-tenant, escopo de origem unica, admissao pos-ativacao (ELEGIVEL/ESTRUTURA_IRRESOLVEL), materializacao de colegiado e substituicao dupla permitida; linhas 4(>1), 10 e 11(>1) validadas por guarda textual + predicado fail-closed (PROVA PARCIAL: o estado >1 nao e construivel sem desabilitar constraint)';
end $$;
