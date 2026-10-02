-- ============================================================================
-- F6 / Issue #427: CONCORRENCIA REAL entre DUAS sessoes PostgreSQL — SESSAO B
-- (segundo processo psql; roda em FOREGROUND, comeca ~1s DEPOIS e CORRE contra
--  as tres janelas de contencao da sessao A, MEDINDO cada espera)
-- ----------------------------------------------------------------------------
-- Papel desta sessao (processo psql 2 de 3):
--   (0) confere as pre-condicoes (fixture EXCLUSIVA, ator soberano,
--       `colaborador_ator_valido` verdadeiro, assinaturas das RPCs, barreira
--       nova instalada, READ COMMITTED explicito e a ORDEM CANONICA DE LOCKS
--       presente no corpo das TRES RPCs de ocupacao);
--   (1) em CADA janela: espera de forma DETERMINISTICA a MARCA da sessao A
--       (sequence NAO transacional do artefato temporario: marcas 1, 2 e 3) com
--       um laco de tentativas (`for i in 1..120 loop ... pg_sleep(0.25) ... end
--       loop`) que aborta com `[FAIL]` acionavel se a marca nao aparecer;
--   (2) mede `clock_timestamp()` ANTES e DEPOIS da tentativa concorrente;
--   (3) exige o veredito CONTRATADO de cada janela e exige tempo decorrido
--       >= 2s como EVIDENCIA de contencao SERVER-SIDE entre dois backends;
--   (4) confere, em cada janela, que NAO houve efeito parcial e que nenhuma
--       intencao perdedora deixou estado ou trilha.
--   `[PASS]` apenas com o veredito contratado + espera >= 2s; qualquer
--   divergencia aborta com `raise exception '[FAIL] ...'`.
--
-- Ordem REAL de execucao (tres processos psql INDEPENDENTES; sem `dblink`, sem
-- `postgres_fdw`, sem extensao nova — a prova e entre dois backends reais):
--   1) `56-cenario-f6-427-concorrencia.sql` -> fixture EXCLUSIVA, single-session;
--   2) `57-sessao-a-f6-427-concorrencia.sql` -> BACKGROUND, iniciado PRIMEIRO;
--   3) `58-sessao-b-f6-427-concorrencia.sql` (ESTE arquivo) -> FOREGROUND;
--   4) `59-validar-f6-427-concorrencia.sql` -> single-session, ao final.
--   No CI: A em background (`&`), `sleep 1`, B em foreground, `wait` em A e, por
--   ultimo, o validador 59.
--
-- AS TRES JANELAS, OS VEREDITOS E A EVIDENCIA EXIGIDA:
--   JANELA 1 — `definir` (A) x `trocar` (B), colaborador X (mesmo alvo):
--     A chama `estrutura_ocupacao_definir(X, XP2, 2035-01-01Z)` e VENCE: XP1 e
--     fechada EXATAMENTE em 2035-01-01Z e XP2 nasce ABERTA. B chama
--     `estrutura_ocupacao_trocar(X, atual=XP1, nova=XP3, 2035-01-02Z)` com
--     INTENCAO DIFERENTE e dia civil DIFERENTE do de A (2035-01-02Z): o veredito
--     e DETERMINISTICO — `F5_07_CONFLICT: ocupacao vigente nao corresponde a
--     posicao atual informada` (a ocupacao vigente de X passou a ser XP2). O dia
--     civil diferente torna IMPOSSIVEL a variante "segunda transicao de ocupacao
--     na mesma relacao e data civil" (os eventos de A sao de 2035-01-01Z).
--     Exigencias: sqlstate = P0001 com F5_07_CONFLICT, `sqlstate <> '40P01'`,
--     mensagem SEM "deadlock", espera >= 2s, NENHUM efeito parcial (X continua
--     com exatamente 1 ocupacao ABERTA em XP2, nenhuma ocupacao de X em XP3 e
--     nenhum evento com o operation_id de B).
--   JANELA 2 — `definir` (A) x `definir` (B), colaborador Y (mesmo alvo):
--     A abre a PRIMEIRA ocupacao de Y (YQ1, 2036-01-01Z). B chama
--     `definir(Y, YQ2, 2036-02-01Z)` (dia civil POSTERIOR) como intencao
--     concorrente; a espera >= 2s e a SERIALIZACAO pelo travamento da LINHA do
--     colaborador, e o resultado e a sequencia CONSECUTIVA
--     YQ1 [2036-01-01, 2036-02-01) + YQ2 [2036-02-01, infinity): EXATAMENTE UMA
--     ocupacao ABERTA, ZERO sobreposicao, e as DUAS operacoes auditadas.
--     Exigencias: sucesso, espera >= 2s, nenhum 40P01/"deadlock", zero par
--     sobreposto de Y, 1 OCUPACAO_INICIADA de A (YQ1) + 1 OCUPACAO_INICIADA de B
--     (YQ2) + 1 OCUPACAO_ENCERRADA de B (YQ1, operation_id DERIVADO).
--   JANELA 3 — `definir` (A) x INSERCAO CRUA (B), colaborador Z (mesmo alvo):
--     A abre a PRIMEIRA ocupacao de Z (ZR1, [2037-01-01Z, infinity)) e a deixa JA
--     inserida no indice GiST e NAO commitada durante a janela. B insere
--     CRUAMENTE para Z, na posicao VAGA ZR2, o intervalo
--     [2037-06-01Z, 2038-01-01Z) — SOBREPOSTO ao de A. A exclusion
--     `ex_occupations_collaborator_no_overlap` obriga B a ESPERAR pela transacao
--     de A e, depois do commit de A, recusa B com SQLSTATE `23P01` nomeando a
--     constraint POR COLABORADOR. Exigencias: 23P01 nomeando
--     `ex_occupations_collaborator_no_overlap`, mensagem SEM
--     `ex_occupations_position_no_overlap` (ZR2 esta VAGA — so a barreira POR
--     COLABORADOR pode disparar), `sqlstate <> '40P01'`, espera >= 2s e NADA
--     extra persistido para Z (continua com exatamente 1 ocupacao, a de A).
--
-- ORDEM CANONICA DE LOCKS (regressao = deadlock): as tres RPCs de ocupacao
-- travam a LINHA do colaborador (`select ... from public.collaborators ...
-- for update`) ANTES do advisory lock da organizacao
-- (`pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text))`).
-- Com a ordem invertida (advisory primeiro, como `trocar` tinha antes da
-- correcao) a corrida `definir` x `trocar` da JANELA 1 forma CICLO DE ESPERA e o
-- PostgreSQL aborta um backend com SQLSTATE `40P01` / "deadlock detected" — o
-- F5_07_CONFLICT publico contratado nunca acontece. Esta sessao FALHA ALTO nesse
-- caso: (i) detecta 40P01/"deadlock" em QUALQUER janela e levanta `[FAIL] ...
-- DEADLOCK DETECTADO ...`; (ii) confere, de forma ESTATICA e DETERMINISTICA, as
-- posicoes de `public.collaborators` e `pg_advisory_xact_lock` no texto das tres
-- RPCs (`pg_get_functiondef`) — a marca de contencao so pode ser observada por B
-- DEPOIS de A ter os DOIS locks em maos, portanto a deteccao dinamica de 40P01 e
-- a segunda linha de defesa, e a conferencia de ordem no texto da RPC e a
-- primeira (JULGAMENTO declarado tambem no cabecalho do 57).
--
-- operation_id desta sessao (UUIDs sinteticos fixos, NUNCA reutilizados em
-- relacao a sessao A; o encerramento usa o operation_id DERIVADO
-- `md5(<operation_id> || ':OCUPACAO_ENCERRADA')::uuid`, como na RPC):
--   janela 1 `trocar` X (intencao PERDEDORA, XP1 -> XP3, 2035-01-02Z)
--                                                     -> f4279100-0000-0000-0000-0000000000b1
--   janela 2 `definir` Y -> YQ2 (2036-02-01Z)         -> f4279100-0000-0000-0000-0000000000b2
--   janela 3 INSERCAO CRUA de Z em ZR2 [2037-06-01Z, 2038-01-01Z)
--                                             -> SEM operation_id (nao e RPC);
--                                                id reservado da linha:
--                                                f4278000-0000-0000-0000-0000000003f1
--   (a sessao A usa f4279000-...-a1/a2/a3 nas tres janelas)
--
-- Isolamento: READ COMMITTED explicito (nivel default do Supabase/Postgres). A
-- prova depende de snapshot POR COMANDO: e a reavaliacao do estado DEPOIS de
-- adquirir o lock (ja com o commit de A) que produz o F5_07_CONFLICT da janela 1
-- e a transicao consecutiva da janela 2.
--
-- LIMITACOES CONHECIDAS (declaradas, nao presumidas):
--   - a janela de contencao de A e o `pg_sleep(8)` DENTRO da escrita. Se este
--     processo for iniciado DEPOIS de A ter terminado, o laco de espera aborta
--     com `[FAIL]` explicito (a marca nao existe mais) e, se B chegar ao lock com
--     menos de 2s de espera, a prova FALHA em vez de fingir sucesso. Nesses
--     casos, reinicie A em background e B em foreground dentro da janela (ou
--     amplie o `pg_sleep` de A e o teto do laco abaixo — 120 x 0.25s = 30s por
--     janela — de forma coerente nos DOIS arquivos);
--   - a espera da janela 3 NAO vem do lock da linha do colaborador: vem da
--     propria exclusion GiST (a sessao A ja deixou o intervalo dela no indice) e
--     e justamente por isso que o veredito final e `23P01` nomeando a constraint
--     POR COLABORADOR — nao `F5_07_CONFLICT` (nao ha RPC envolvida) e nao a
--     exclusion POR POSICAO (ZR2 esta vaga);
--   - esta sessao NAO declara o GUC `virtus.f6_427_janela`: o artefato de A nao
--     atrasa NENHUMA escrita de B, e por isso as esperas medidas aqui sao
--     esperas REAIS de lock/exclusion, nao de gatilho;
--   - `collaborator_events` e append-only e as FKs sao RESTRICT: a prova NAO tem
--     reset parcial. Para reexecutar: `supabase db reset --local` + fixtures +
--     57 (background) + 58 (foreground) + 59 (mesma doutrina dos validadores P9).
--
-- Como executar (Supabase local; NUNCA remoto) — A ja rodando em BACKGROUND:
--   Get-Content supabase/validacao/58-sessao-b-f6-427-concorrencia.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
-- ============================================================================

\set ON_ERROR_STOP on

-- Isolamento explicito: a reavaliacao sob o lock depende de snapshot por comando
-- (READ COMMITTED). Nao altera nenhum objeto do banco.
set default_transaction_isolation = 'read committed';

-- A prova tem esperas LEGITIMAS dentro de UMA instrucao: o laco de tentativas
-- (ate 120 x 0.25s = 30s por janela) e os proprios bloqueios contratados (~8s por
-- janela). Um `statement_timeout`/`lock_timeout` herdado do papel de conexao
-- (ex.: 8s de `service_role` no Supabase local) nao pode transformar isso em
-- falha espuria: os timeouts sao desligados APENAS nesta sessao de validacao
-- (nenhum objeto do banco e alterado, nenhum controle do produto e relaxado).
set statement_timeout = 0;
set lock_timeout = 0;

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture EXCLUSIVA, ator soberano, READ COMMITTED, RPCs na
--    assinatura do contrato e ORDEM CANONICA DE LOCKS nas tres RPCs
-- ----------------------------------------------------------------------------
do $$
declare
  v_org        uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator       uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_x          uuid := 'f427c000-0000-0000-0000-0000000000a1';
  v_memb       uuid;
  v_n          int;
  v_args       text;
  v_def        text;
  v_fn         text;
  v_pos_linha  int;
  v_pos_advis  int;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception '[FAIL] pre-condicao B: isolamento % — a prova exige READ COMMITTED (snapshot por comando) para que a releitura sob o lock enxergue o commit de A',
      current_setting('transaction_isolation');
  end if;
  if not exists (select 1 from public.organizations o where o.id = v_org) then
    raise exception '[FAIL] pre-condicao B: organizacao EXCLUSIVA da corrida (%) ausente — execute 56-cenario-f6-427-concorrencia.sql', v_org;
  end if;
  if not exists (select 1 from public.user_profiles p where p.id = v_ator and p.status = 'active') then
    raise exception '[FAIL] pre-condicao B: perfil ATIVO do ator da corrida (%) ausente na fixture', v_ator;
  end if;
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator and m.organization_id = v_org and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] pre-condicao B: membership ATIVA do ator da corrida na organizacao % ausente', v_org;
  end if;
  if not public.colaborador_ator_valido(v_ator, v_org) then
    raise exception '[FAIL] pre-condicao B: colaborador_ator_valido falso para o ator da corrida (%)', v_ator;
  end if;

  -- Fixture EXCLUSIVA intacta (asserts MONOTONOS: valem antes e depois de A
  -- commitar cada janela — este arquivo pode comecar com A ja dentro da escrita).
  select count(*) into v_n from public.collaborators c where c.organization_id = v_org;
  if v_n <> 3 then
    raise exception '[FAIL] pre-condicao B: a organizacao EXCLUSIVA da corrida deveria ter exatamente 3 colaboradores (X/Y/Z), encontrados % — outro validador escreveu nesta organizacao?', v_n;
  end if;
  select count(*) into v_n from public.organizational_positions p where p.organization_id = v_org;
  if v_n <> 7 then
    raise exception '[FAIL] pre-condicao B: posicoes esperadas=7 na organizacao da corrida, encontradas %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = 'f4278000-0000-0000-0000-0000000000c1'
       and o.valid_from = '2024-01-01T00:00:00Z'
  ) then
    raise exception '[FAIL] pre-condicao B: a ocupacao inicial de X em XP1 (2024-01-01Z) nao existe — execute 56-cenario-f6-427-concorrencia.sql';
  end if;

  -- Assinaturas EXATAS do contrato.
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)');
  if v_args is distinct from
     'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_position_id uuid, p_vigencia timestamp with time zone, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid' then
    raise exception '[FAIL] pre-condicao B: assinatura de estrutura_ocupacao_definir fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)');
  if v_args is distinct from
     'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_current_position_id uuid, p_new_position_id uuid, p_vigencia timestamp with time zone, p_motivo text' then
    raise exception '[FAIL] pre-condicao B: assinatura de estrutura_ocupacao_trocar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;

  -- Barreira final instalada (posicao + colaborador) na forma meio-aberta `[)`.
  select count(*) into v_n from pg_constraint
   where conrelid = 'public.occupations'::regclass
     and conname in ('ex_occupations_position_no_overlap','ex_occupations_collaborator_no_overlap');
  if v_n <> 2 then
    raise exception '[FAIL] pre-condicao B: exclusoes de occupations esperadas=2, encontradas=%', v_n;
  end if;
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'public.occupations'::regclass and c.conname = 'ex_occupations_collaborator_no_overlap';
  if v_def is null or position('[)' in v_def) = 0 then
    raise exception '[FAIL] pre-condicao B: ex_occupations_collaborator_no_overlap ausente ou fora da forma meio-aberta [) (%)', coalesce(v_def,'ausente');
  end if;

  -- ORDEM CANONICA DE LOCKS (checagem ESTATICA): linha do colaborador ANTES do
  -- advisory lock da organizacao, nas TRES RPCs de ocupacao. E o detector
  -- DETERMINISTICO da regressao que produziria o deadlock 40P01 na janela 1.
  foreach v_fn in array array[
    'estrutura_ocupacao_definir', 'estrutura_ocupacao_trocar', 'estrutura_ocupacao_encerrar'
  ] loop
    v_def := null;
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn
     order by p.oid desc
     limit 1;
    if v_def is null then
      raise exception '[FAIL] pre-condicao B: RPC public.% ausente', v_fn;
    end if;
    v_pos_linha := position('public.collaborators' in v_def);
    v_pos_advis := position('pg_advisory_xact_lock' in v_def);
    if v_pos_linha = 0 or v_pos_advis = 0 then
      raise exception '[FAIL] pre-condicao B: nao foi possivel localizar o travamento da linha do colaborador e/ou o advisory lock da organizacao no corpo de public.%', v_fn;
    end if;
    if not (v_pos_linha < v_pos_advis) then
      raise exception '[FAIL] pre-condicao B: ORDEM CANONICA DE LOCKS REGREDIU em public.% — o advisory lock da organizacao aparece ANTES do travamento da linha do colaborador (posicoes % e %): a janela 1 formaria ciclo de espera (40P01) em vez do F5_07_CONFLICT publico',
        v_fn, v_pos_advis, v_pos_linha;
    end if;
  end loop;

  raise notice '[PASS] pre-condicoes da sessao B: READ COMMITTED, organizacao EXCLUSIVA % presente, ator % com membership ativa % e colaborador_ator_valido verdadeiro, RPCs na assinatura do contrato, as duas exclusoes instaladas e ORDEM CANONICA DE LOCKS (linha do colaborador antes do advisory lock da organizacao) presente em definir/trocar/encerrar',
    v_org, v_ator, v_memb;
end $$;

-- ----------------------------------------------------------------------------
-- 1) JANELA 1 — espera pela MARCA 1, `trocar` concorrente (PERDEDORA) e medicao
--    Veredito exigido: F5_07_CONFLICT publico (posicao atual divergente) apos
--    espera >= 2s, NUNCA 40P01/deadlock, sem NENHUM efeito parcial.
-- ----------------------------------------------------------------------------
do $$
declare
  v_org     uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator    uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_x       uuid := 'f427c000-0000-0000-0000-0000000000a1';
  v_xp1     uuid := 'f4278000-0000-0000-0000-0000000000c1';
  v_xp2     uuid := 'f4278000-0000-0000-0000-0000000000c2';
  v_xp3     uuid := 'f4278000-0000-0000-0000-0000000000c3';
  v_op      uuid := 'f4279100-0000-0000-0000-0000000000b1';
  v_op_enc  uuid := md5('f4279100-0000-0000-0000-0000000000b1' || ':OCUPACAO_ENCERRADA')::uuid;
  v_vig     timestamptz := '2035-01-02T00:00:00Z';
  v_pronto  boolean := false;
  v_i       int;
  v_last    bigint;
  v_called  boolean;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_seg     numeric;
  v_msg     text := null;
  v_state   text := null;
  v_n       int;
  v_ok      boolean := false;
begin
  -- (a) Espera DETERMINISTICA: a sessao A so grava a MARCA 1 DENTRO da escrita
  -- (com a linha de X travada e o advisory lock da organizacao em maos). A marca
  -- e uma sequence NAO transacional, lida de OUTRA sessao.
  for v_i in 1..120 loop
    v_pronto := false;
    if to_regclass('public._mut_f6_427_contencao_seq') is not null then
      select s.last_value, s.is_called into v_last, v_called
        from public._mut_f6_427_contencao_seq s;
      if v_called is true and v_last >= 1 then
        v_pronto := true;
      end if;
    end if;
    exit when v_pronto;
    perform pg_sleep(0.25);
  end loop;
  if not v_pronto then
    raise exception '[FAIL] sessao B/janela 1: a MARCA 1 de contencao da sessao A (public._mut_f6_427_contencao_seq) nao foi observada em 30s — inicie 57-sessao-a-f6-427-concorrencia.sql em BACKGROUND e este arquivo em FOREGROUND dentro da janela de ~8s do pg_sleep de A';
  end if;

  raise notice 'sessao B/janela 1: sessao A DENTRO da escrita de X (marca %, sequence nao transacional lida de OUTRA sessao) — tentando trocar X de XP1 para XP3 na vigencia 2035-01-02Z (dia civil DIFERENTE do de A: veredito deterministico por posicao atual divergente)',
    v_last;

  -- (b)+(c) Medicao ANTES e tentativa concorrente com OUTRO operation_id.
  v_ini := clock_timestamp();
  begin
    perform public.estrutura_ocupacao_trocar(
      v_org, v_ator, v_op, v_x, v_xp1, v_xp3, v_vig,
      'Intencao perdedora concorrente F6-427 janela 1');
  exception when others then
    v_msg := sqlerrm;
    v_state := sqlstate;
  end;
  -- (d) Medicao DEPOIS (clock_timestamp, nao `now()`: o bloco todo e um unico
  -- comando e `now()` seria o MESMO instante no inicio e no fim).
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  -- DEADLOCK e a assinatura da REGRESSAO da ordem canonica de locks: falha ALTA.
  if v_state = '40P01' or (v_msg is not null and v_msg ilike '%deadlock%') then
    raise exception '[FAIL] sessao B/janela 1: DEADLOCK DETECTADO (sqlstate %, mensagem %) — a ORDEM CANONICA DE LOCKS regrediu: o desfecho contratado e o F5_07_CONFLICT publico, NUNCA 40P01', v_state, v_msg;
  end if;
  if v_msg is null then
    raise exception '[FAIL] sessao B/janela 1: a troca concorrente de B foi APLICADA — o contrato exige F5_07_CONFLICT (nenhuma intencao concorrente pode vencer o estado commitado de A)';
  end if;
  v_ok := (position('F5_07_CONFLICT' in v_msg) > 0
           and position('ocupacao vigente nao corresponde a posicao atual informada' in v_msg) > 0);
  if not v_ok then
    raise exception '[FAIL] sessao B/janela 1: recusa FORA do contrato (sqlstate %, mensagem %) — esperado F5_07_CONFLICT com "ocupacao vigente nao corresponde a posicao atual informada"',
      v_state, v_msg;
  end if;
  if v_seg < 2.0 then
    raise exception '[FAIL] sessao B/janela 1: B NAO ficou bloqueada (% segundos < 2s) — sem espera nao ha prova de contencao SERVER-SIDE; reinicie A em BACKGROUND e B em FOREGROUND dentro da janela de ~8s do pg_sleep de A',
      round(v_seg, 3);
  end if;

  raise notice '[PASS] sessao B/janela 1: escrita concorrente recusada pelo contrato — sqlstate % / %', v_state, v_msg;
  raise notice '[PASS] sessao B/janela 1: B ficou BLOQUEADA na LINHA do colaborador X (for update da RPC `trocar`) por ~%s antes do F5_07_CONFLICT — contencao SERVER-SIDE real entre dois backends',
    round(v_seg, 3);

  -- (e) NENHUM efeito parcial: X continua com o estado de A (1 ABERTA em XP2),
  -- nenhuma ocupacao de X em XP3 e nenhum evento com o operation_id de B.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x;
  if v_n <> 2 then
    raise exception '[FAIL] sessao B/janela 1: X deveria continuar com 2 ocupacoes (XP1 fechada + XP2 aberta), tem % — efeito parcial da intencao perdedora', v_n;
  end if;
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] sessao B/janela 1: X deveria ter exatamente 1 ocupacao ABERTA, tem %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp2
       and o.valid_from = '2035-01-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] sessao B/janela 1: a ocupacao ABERTA de X deveria ser a de A (XP2 desde 2035-01-01Z) — lost update';
  end if;
  if exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp3
  ) then
    raise exception '[FAIL] sessao B/janela 1: a intencao PERDEDORA criou ocupacao de X na posicao XP3 — efeito parcial';
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.operation_id = v_op;
  if v_n <> 0 then
    raise exception '[FAIL] sessao B/janela 1: a intencao perdedora gravou % evento(s) com o proprio operation_id', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.operation_id = v_op_enc;
  if v_n <> 0 then
    raise exception '[FAIL] sessao B/janela 1: a intencao perdedora gravou % evento(s) com o operation_id DERIVADO de encerramento', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_x
     and e.operation_id in ('f4279000-0000-0000-0000-0000000000a1',
                            md5('f4279000-0000-0000-0000-0000000000a1' || ':OCUPACAO_ENCERRADA')::uuid);
  if v_n <> 2 then
    raise exception '[FAIL] sessao B/janela 1: a trilha de X deveria ter exatamente os 2 eventos de A, encontrados %', v_n;
  end if;

  raise notice '[PASS] sessao B/janela 1: NENHUM efeito parcial — X permanece com exatamente 1 ocupacao ABERTA em XP2 (a de A), nenhuma ocupacao em XP3 e nenhum evento com os operation_id de B; a intencao perdedora foi recusada pelo contrato publico F5_07_CONFLICT';
end $$;

-- ----------------------------------------------------------------------------
-- 2) JANELA 2 — espera pela MARCA 2, `definir` concorrente SERIALIZADA
--    Veredito exigido: SUCESSO depois de espera >= 2s; final de Y = sequencia
--    consecutiva YQ1 [2036-01-01, 2036-02-01) + YQ2 [2036-02-01, infinity),
--    exatamente UMA ABERTA, ZERO sobreposicao e as DUAS operacoes auditadas.
-- ----------------------------------------------------------------------------
do $$
declare
  v_org     uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator    uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_y       uuid := 'f427c000-0000-0000-0000-0000000000a2';
  v_yq1     uuid := 'f4278000-0000-0000-0000-0000000000c4';
  v_yq2     uuid := 'f4278000-0000-0000-0000-0000000000c5';
  v_op_a    uuid := 'f4279000-0000-0000-0000-0000000000a2';
  v_op_b    uuid := 'f4279100-0000-0000-0000-0000000000b2';
  v_op_b_e  uuid := md5('f4279100-0000-0000-0000-0000000000b2' || ':OCUPACAO_ENCERRADA')::uuid;
  v_vig_a   timestamptz := '2036-01-01T00:00:00Z';
  v_vig_b   timestamptz := '2036-02-01T00:00:00Z';
  v_pronto  boolean := false;
  v_i       int;
  v_last    bigint;
  v_called  boolean;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_seg     numeric;
  v_msg     text := null;
  v_state   text := null;
  v_id      uuid;
  v_n       int;
  v_card    int;
  v_pos     uuid;
begin
  for v_i in 1..120 loop
    v_pronto := false;
    if to_regclass('public._mut_f6_427_contencao_seq') is not null then
      select s.last_value, s.is_called into v_last, v_called
        from public._mut_f6_427_contencao_seq s;
      if v_called is true and v_last >= 2 then
        v_pronto := true;
      end if;
    end if;
    exit when v_pronto;
    perform pg_sleep(0.25);
  end loop;
  if not v_pronto then
    raise exception '[FAIL] sessao B/janela 2: a MARCA 2 de contencao da sessao A nao foi observada em 30s — a sessao A precisa estar DENTRO da escrita da janela 2 (Y -> YQ1) enquanto B tenta a sua';
  end if;

  raise notice 'sessao B/janela 2: sessao A DENTRO da escrita de Y (marca %) — tentando definir Y em YQ2 na vigencia 2036-02-01Z (dia civil POSTERIOR: a intencao de B tem de ser SERIALIZADA pelo travamento da linha do colaborador)',
    v_last;

  v_ini := clock_timestamp();
  begin
    v_id := public.estrutura_ocupacao_definir(
      v_org, v_ator, v_op_b, v_y, v_yq2, v_vig_b,
      'Intencao concorrente serializada F6-427 janela 2',
      'CICLO_ATUAL_E_POSTERIORES', null);
  exception when others then
    v_msg := sqlerrm;
    v_state := sqlstate;
  end;
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  if v_state = '40P01' or (v_msg is not null and v_msg ilike '%deadlock%') then
    raise exception '[FAIL] sessao B/janela 2: DEADLOCK DETECTADO (sqlstate %, mensagem %) — a ORDEM CANONICA DE LOCKS regrediu: as DUAS chamadas sao `definir` (mesma ordem) e nao podem formar ciclo de espera', v_state, v_msg;
  end if;
  if v_msg is not null then
    raise exception '[FAIL] sessao B/janela 2: a definicao concorrente de B FALHOU (sqlstate %, mensagem %) — a serializacao pela linha do colaborador deveria APLICAR a intencao de B (dia civil posterior) depois do commit de A, sem sobreposicao e sem efeito parcial',
      v_state, v_msg;
  end if;
  if v_id is null then
    raise exception '[FAIL] sessao B/janela 2: definir nao devolveu o id da nova ocupacao de Y';
  end if;
  if v_seg < 2.0 then
    raise exception '[FAIL] sessao B/janela 2: B NAO ficou bloqueada (% segundos < 2s) — sem espera nao ha prova de contencao SERVER-SIDE',
      round(v_seg, 3);
  end if;

  raise notice '[PASS] sessao B/janela 2: a definicao concorrente de B foi APLICADA depois de ~%s de espera no travamento da LINHA do colaborador Y — serializacao REAL no banco, sem deadlock',
    round(v_seg, 3);

  -- INVARIANTE FINAL de Y: exatamente 2 ocupacoes, UMA ABERTA (YQ2 desde
  -- 2036-02-01Z), YQ1 fechada EXATAMENTE em 2036-02-01Z (meio-aberto: em
  -- 2036-02-01Z vale YQ2) e ZERO par sobreposto.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_y;
  if v_n <> 2 then
    raise exception '[FAIL] sessao B/janela 2: Y deveria terminar com exatamente 2 ocupacoes (YQ1 fechada + YQ2 aberta), tem % — duas transicoes concorrentes nunca podem produzir 3 linhas nem perder uma', v_n;
  end if;
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_y and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] sessao B/janela 2: Y deveria ter exatamente 1 ocupacao ABERTA, tem %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.id = v_id and o.organization_id = v_org and o.collaborator_id = v_y
       and o.organizational_position_id = v_yq2
       and o.valid_from = v_vig_b and o.valid_to is null
  ) then
    raise exception '[FAIL] sessao B/janela 2: a ocupacao devolvida por B nao e a ABERTA em YQ2 desde 2036-02-01Z';
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_y
       and o.organizational_position_id = v_yq1
       and o.valid_from = v_vig_a and o.valid_to = v_vig_b
  ) then
    raise exception '[FAIL] sessao B/janela 2: YQ1 deveria ter sido FECHADA exatamente em 2036-02-01Z (a transicao de A foi reavaliada sob o lock e virou periodo consecutivo)';
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_y,'2036-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] sessao B/janela 2: cardinalidade de Y em 2036-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_y,'2036-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_yq2 then
    raise exception '[FAIL] sessao B/janela 2: posicao soberana de Y em 2036-06 deveria ser YQ2 (%)', v_pos;
  end if;

  -- ZERO sobreposicao para Y, calculado EXPLICITAMENTE (par meio-aberto).
  select count(*) into v_n
    from public.occupations a
    join public.occupations b
      on b.collaborator_id = a.collaborator_id
     and b.id > a.id
     and tstzrange(a.valid_from, coalesce(a.valid_to,'infinity'::timestamptz), '[)')
      && tstzrange(b.valid_from, coalesce(b.valid_to,'infinity'::timestamptz), '[)')
   where a.organization_id = v_org and a.collaborator_id = v_y;
  if v_n <> 0 then
    raise exception '[FAIL] sessao B/janela 2: existem % par(es) de ocupacoes SOBREPOSTAS de Y — o invariante da #427 foi violado pela corrida', v_n;
  end if;

  -- TRILHA: A (YQ1, sem encerramento porque Y nasceu sem ocupacao) e B
  -- (OCUPACAO_INICIADA em YQ2 + OCUPACAO_ENCERRADA em YQ1 com operation_id
  -- DERIVADO) — exatamente 3 eventos para Y.
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_op_a
     and e.position_id = v_yq1 and e.effective_date = v_vig_a;
  if v_n <> 1 then
    raise exception '[FAIL] sessao B/janela 2: esperado 1 evento OCUPACAO_INICIADA de A para Y/YQ1 (encontrados %)', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_op_b
     and e.position_id = v_yq2 and e.effective_date = v_vig_b and e.result_entity_id = v_id;
  if v_n <> 1 then
    raise exception '[FAIL] sessao B/janela 2: esperado 1 evento OCUPACAO_INICIADA de B para Y/YQ2 (encontrados %)', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y
     and e.event_type = 'OCUPACAO_ENCERRADA' and e.operation_id = v_op_b_e
     and e.position_id = v_yq1 and e.effective_date = v_vig_b;
  if v_n <> 1 then
    raise exception '[FAIL] sessao B/janela 2: esperado 1 evento OCUPACAO_ENCERRADA de B (operation_id DERIVADO) para Y/YQ1 em 2036-02-01Z (encontrados %)', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y;
  if v_n <> 3 then
    raise exception '[FAIL] sessao B/janela 2: a trilha de Y deveria ter exatamente 3 eventos (A/YQ1 + B/YQ2 + B encerramento de YQ1), encontrados %', v_n;
  end if;

  raise notice '[PASS] sessao B/janela 2: Y terminou com o periodo CONSECUTIVO YQ1 [2036-01-01, 2036-02-01) + YQ2 [2036-02-01, infinity) — exatamente UMA ocupacao ABERTA, cardinalidade 1, ZERO par sobreposto e as DUAS operacoes auditadas (1 OCUPACAO_INICIADA para cada lado + o encerramento de YQ1 por B)';
end $$;

-- ----------------------------------------------------------------------------
-- 3) JANELA 3 — espera pela MARCA 3 e INSERCAO CRUA sobreposta
--    Veredito exigido: SQLSTATE 23P01 nomeando ex_occupations_collaborator_no_overlap
--    apos espera >= 2s, SEM nomear a exclusion por POSICAO e sem NADA extra para Z.
-- ----------------------------------------------------------------------------
do $$
declare
  v_org     uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_z       uuid := 'f427c000-0000-0000-0000-0000000000a3';
  v_zr1     uuid := 'f4278000-0000-0000-0000-0000000000c6';
  v_zr2     uuid := 'f4278000-0000-0000-0000-0000000000c7';
  v_raw_id  uuid := 'f4278000-0000-0000-0000-0000000003f1';
  v_pronto  boolean := false;
  v_i       int;
  v_last    bigint;
  v_called  boolean;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_seg     numeric;
  v_msg     text := null;
  v_state   text := null;
  v_n       int;
  v_card    int;
  v_pos     uuid;
begin
  for v_i in 1..120 loop
    v_pronto := false;
    if to_regclass('public._mut_f6_427_contencao_seq') is not null then
      select s.last_value, s.is_called into v_last, v_called
        from public._mut_f6_427_contencao_seq s;
      if v_called is true and v_last >= 3 then
        v_pronto := true;
      end if;
    end if;
    exit when v_pronto;
    perform pg_sleep(0.25);
  end loop;
  if not v_pronto then
    raise exception '[FAIL] sessao B/janela 3: a MARCA 3 de contencao da sessao A nao foi observada em 30s — a sessao A precisa estar DENTRO da escrita de Z (com a linha [2037-01-01Z, infinity) JA no indice GiST e NAO commitada) enquanto B insere cruamente';
  end if;

  raise notice 'sessao B/janela 3: sessao A DENTRO da escrita de Z (marca %) — inserindo CRUAMENTE em public.occupations para Z na posicao VAGA ZR2 o intervalo [2037-06-01Z, 2038-01-01Z), que SOBREPOE o de A; a espera aqui e a da propria exclusion GiST',
    v_last;

  -- ZR2 precisa estar VAGA: se estivesse ocupada, a exclusion por POSICAO seria
  -- a barreira capaz de recusar e a prova nao estaria medindo a barreira nova.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org
     and o.organizational_position_id = v_zr2
     and o.valid_from <= '2037-06-01T00:00:00Z'
     and (o.valid_to is null or o.valid_to > '2037-06-01T00:00:00Z');
  if v_n <> 0 then
    raise exception '[FAIL] sessao B/janela 3: a posicao alvo ZR2 deveria estar VAGA na data da insercao crua (tem % ocupante vigente) — sem isso a recusa poderia vir da exclusion por POSICAO', v_n;
  end if;

  v_ini := clock_timestamp();
  begin
    insert into public.occupations
      (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to)
    values
      (v_raw_id, v_org, v_z, v_zr2, 'Tentativa crua concorrente F6-427 janela 3',
       '2037-06-01T00:00:00Z', '2038-01-01T00:00:00Z');
  exception when others then
    v_msg := sqlerrm;
    v_state := sqlstate;
  end;
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  if v_state = '40P01' or (v_msg is not null and v_msg ilike '%deadlock%') then
    raise exception '[FAIL] sessao B/janela 3: DEADLOCK DETECTADO (sqlstate %, mensagem %) — a insercao CRUA nao pode formar ciclo de espera; o desfecho contratado e 23P01 nomeando ex_occupations_collaborator_no_overlap', v_state, v_msg;
  end if;
  if v_msg is null then
    raise exception '[FAIL] sessao B/janela 3: a insercao CRUA sobreposta foi ACEITA — a exclusion por COLABORADOR (barreira final da #427) nao bloqueou/recusou; duas ocupacoes sobrepostas de Z seriam possiveis';
  end if;
  if v_state <> '23P01' then
    raise exception '[FAIL] sessao B/janela 3: sqlstate % (esperado 23P01 / exclusion_violation) — mensagem %', v_state, v_msg;
  end if;
  if position('ex_occupations_collaborator_no_overlap' in v_msg) = 0 then
    raise exception '[FAIL] sessao B/janela 3: a recusa 23P01 nao nomeou a exclusion POR COLABORADOR (mensagem %)', v_msg;
  end if;
  if position('ex_occupations_position_no_overlap' in v_msg) > 0 then
    raise exception '[FAIL] sessao B/janela 3: a recusa nomeou a exclusion POR POSICAO (mensagem %) — a posicao alvo ZR2 deveria estar VAGA; a prova nao mediu a barreira nova', v_msg;
  end if;
  if v_seg < 2.0 then
    raise exception '[FAIL] sessao B/janela 3: a insercao crua NAO esperou (% segundos < 2s) — a exclusion GiST tinha de fazer B esperar pela transacao de A (que ja deixou o intervalo dela no indice); sem espera nao ha prova de contencao SERVER-SIDE',
      round(v_seg, 3);
  end if;

  raise notice '[PASS] sessao B/janela 3: insercao CRUA recusada pela EXCLUSION POR COLABORADOR — sqlstate % / %', v_state, v_msg;
  raise notice '[PASS] sessao B/janela 3: B esperou ~%s na propria exclusion GiST (a transacao de A ja tinha o intervalo no indice e ainda NAO havia commitado) — contencao SERVER-SIDE real, sem 40P01 e sem nomear a exclusion por POSICAO',
    round(v_seg, 3);

  -- NADA extra persistido para Z: exatamente 1 ocupacao, a de A (ZR1, aberta
  -- desde 2037-01-01Z); nenhuma linha com o id reservado a insercao crua;
  -- cardinalidade 1; posicao soberana ZR1; nenhum par sobreposto.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_z;
  if v_n <> 1 then
    raise exception '[FAIL] sessao B/janela 3: Z deveria ter exatamente 1 ocupacao (a de A), tem % — a insercao crua deixou efeito parcial', v_n;
  end if;
  if exists (select 1 from public.occupations o where o.id = v_raw_id) then
    raise exception '[FAIL] sessao B/janela 3: a linha da insercao crua (%) persistiu em public.occupations', v_raw_id;
  end if;
  if exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_z
       and o.organizational_position_id = v_zr2
  ) then
    raise exception '[FAIL] sessao B/janela 3: a intencao crua criou ocupacao de Z na posicao ZR2';
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_z
       and o.organizational_position_id = v_zr1
       and o.valid_from = '2037-01-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] sessao B/janela 3: a ocupacao ABERTA de Z (ZR1 desde 2037-01-01Z), criada por A, nao esta intacta';
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_z,'2037-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] sessao B/janela 3: cardinalidade de Z em 2037-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_z,'2037-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_zr1 then
    raise exception '[FAIL] sessao B/janela 3: posicao soberana de Z em 2037-06 deveria ser ZR1 (%)', v_pos;
  end if;

  raise notice '[PASS] sessao B/janela 3: NADA extra persistido para Z — continua com exatamente 1 ocupacao (ZR1, aberta desde 2037-01-01Z), cardinalidade 1 e posicao soberana ZR1; a linha da insercao crua nao existe';
end $$;

-- ----------------------------------------------------------------------------
-- 4) Fechamento: resumo deterministico da corrida vista pela sessao B
-- ----------------------------------------------------------------------------
do $$
begin
  raise notice '[PASS] sessao B: NENHUM deadlock (0 ocorrencias de 40P01/"deadlock detected" em qualquer janela) e a ordem canonica de locks (linha do colaborador antes do advisory lock da organizacao) foi conferida no texto das TRES RPCs de ocupacao';
  raise notice '[PASS] sessao B: contencao SERVER-SIDE REAL — cada janela produziu espera medida com clock_timestamp() >= 2s (bloqueio na linha do colaborador nas janelas 1 e 2; espera da propria exclusion GiST na janela 3)';
  raise notice '[PASS] sessao B: no maximo UM resultado valido por janela — janela 1 PERDEDORA recusada com F5_07_CONFLICT, janela 2 SERIALIZADA com a intencao de B aplicada depois da de A (periodo consecutivo, UMA ABERTA, zero sobreposicao) e janela 3 recusada com 23P01 nomeando ex_occupations_collaborator_no_overlap';
  raise notice '[PASS] sessao B: NENHUM efeito parcial — o estado commitado e sempre o das operacoes legitimas (X em XP2, Y em YQ2, Z em ZR1), nenhuma trilha da intencao perdedora e nenhuma linha da insercao crua';
  raise notice 'sessao B: o validador consolidado 59 confere o estado final da organizacao EXCLUSIVA e a higiene do artefato temporario da sessao A';
end $$;
