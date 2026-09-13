-- ============================================================================
-- F5-09 P9: CONCORRENCIA REAL entre DUAS sessoes PostgreSQL — SESSAO A
-- (primeiro processo psql; roda em BACKGROUND e VENCE a corrida)
-- ----------------------------------------------------------------------------
-- Papel desta sessao (processo psql 1 de 3):
--   (1) cria, pelo caminho LEGITIMO (`ciclo_criar`), o ciclo PROPRIO 2041/1 da
--       organizacao Gama-P9 (a fixture `14-cenario-f5-09-p9.sql` cria Gama-P9
--       SEM ciclos);
--   (2) instala um artefato TEMPORARIO em `public` (sequence NAO transacional +
--       funcao/gatilho BEFORE UPDATE em `evaluation_cycles`) que faz a ESCRITA
--       do ciclo DEMORAR ~8s (`pg_sleep`), e chama `ciclo_editar` com
--       `expected_version = 0` (mesmo alvo e mesma versao declarada que a
--       sessao B tentara);
--   (3) durante TODO esse UPDATE a sessao A esta com o advisory lock normativo
--       da familia de ciclos em maos — `ciclo_lock_organizacao` =
--       chave `evaluation_cycles:<organization_id>` (adquirida dentro de
--       `ciclo_editar`, ANTES da resolucao da linha e da checagem de versao);
--   (4) ao commitar, REMOVE o artefato temporario e informa, de forma
--       explicita, que VENCEU a corrida (version = 1, periodo novo).
--
-- Ordem REAL de execucao (tres processos psql INDEPENDENTES; sem `dblink`, sem
-- `postgres_fdw`, sem extensao nova — a prova e entre dois backends reais):
--   1) `16-sessao-a-f5-09-p9-concorrencia.sql` (ESTE arquivo) -> BACKGROUND,
--      iniciado PRIMEIRO;
--   2) `17-sessao-b-f5-09-p9-concorrencia.sql`                -> FOREGROUND,
--      iniciado DEPOIS e BLOQUEADO pelo lock da sessao A;
--   3) `18-validar-f5-09-p9-concorrencia.sql`                 -> single-session,
--      SOMENTE depois de A e B terminarem (estado consolidado).
--   Nao existe ordem interna pressuposta entre A e B: a UNICA coordenacao e o
--   laco de espera DETERMINISTICO da sessao B (existencia do ciclo + marca nao
--   transacional do gatilho temporario de A).
--   No CI (`.github/workflows/ci.yml`) a corrida e exatamente: A em background
--   (`&`), `sleep 1`, B em foreground e `wait` em A — a latencia de ~1s mais o
--   start do psql cabem com folga na janela de ~8s do `pg_sleep`.
--
-- CONTRATO DE EXCLUSIVIDADE DESTA PROVA: Gama-P9 e a organizacao EXCLUSIVA da
-- corrida. A fixture `14-cenario-f5-09-p9.sql` cria Gama-P9 SEM ciclos e o
-- validador `15-validar-f5-09-p9.sql` NAO pode criar ciclo/evento em Gama-P9
-- (os atores Alfa-P9 existem para os validadores integrados). Se outro validador
-- escrever em Gama-P9, os asserts daqui e do 18 falham com mensagem explicita —
-- e a correcao e reatribuir a organizacao, nunca afrouxar a prova.
--
-- Evidencia de contencao esperada (server-side):
--   - A dorme ~8s DENTRO da transacao de `ciclo_editar`, com o lock da
--     organizacao ja adquirido;
--   - B tenta `ciclo_editar` com o MESMO `expected_version = 0` e fica
--     BLOQUEADA no MESMO advisory lock ate A commitar; B mede o tempo com
--     `clock_timestamp()` e so aceita a prova com tempo decorrido >= ~2s;
--   - apos o bloqueio B observa a versao commitada por A (1, nunca 0) e o erro
--     do contrato (`F5_09_CONFLICT: versao divergente`);
--   - a linha commitada por A e a UNICA fonte do estado final (version = 1,
--     periodo 2041-01-10..2041-04-10) — nunca o periodo da intencao de B.
--
-- DIFERENCA EXPLICITA em relacao a P8 (concorrencia client-side):
--   a P8 prova, em UM unico processo node, que o controlador da UI recusa uma
--   segunda mutation concorrente SEM chamar a Edge
--   (`src/services/ciclosSoberanos/controladorGestaoCiclos.test.ts`;
--   `operacaoEmAndamento` — "uma unica operacao por vez"). Isso e serializacao
--   de INTERFACE, nao contencao de banco: nada ali prova que duas sessoes
--   PostgreSQL disputam um lock. Aqui a prova e entre DOIS BACKENDS reais
--   disputando `pg_advisory_xact_lock` + `expected_version`; a espera medida no
--   relogio da sessao B so existe porque o BANCO serializa as duas sessoes.
--
-- operation_id desta sessao (UUIDs sinteticos fixos, NUNCA reutilizados entre
-- as duas sessoes):
--   ciclo_criar  2041/1 -> ed910000-0000-0000-0000-0000000000a1
--   ciclo_editar 2041/1 -> ed910000-0000-0000-0000-0000000000a2
--   (a sessao B usa ed920000-0000-0000-0000-0000000000b1 — distinto)
--
-- Alvo fixo do contrato P9:
--   organizacao Gama-P9 : eda00000-0000-0000-0000-0000000000c1
--   ator gestor-gama    : edc00000-0000-0000-0000-000000000006
--                         (membership ATIVA com `cycle.read` + `cycle.manage`)
--   ciclo 2041/1        : 2041-01-01..2041-03-31 (criacao)
--                         2041-01-10..2041-04-10 (apos a edicao vencedora de A)
--
-- LIMITACOES CONHECIDAS (declaradas, nao presumidas):
--   - a janela de contencao e o `pg_sleep(8)` dentro do UPDATE (topo do
--     intervalo 3..5s do desenho, AMPLIADO para 8s por robustez do runner do
--     CI (a janela maior cobre start mais lento da sessao B sem afrouxar o
--     limiar de contencao de 2s exigido por B). A sessao B precisa TENTAR a
--     A dorme; se o runner demorar mais que ~8s para subir o segundo psql,
--     aumente o `pg_sleep` aqui E o teto do laco de espera de B (60 x 0.25s)
--     de forma coerente nos dois arquivos;
--   - a marca do gatilho e uma SEQUENCE (nao transacional) de proposito: e ela
--     que permite a B provar que A JA esta DENTRO do UPDATE (com o lock em
--     maos) no instante da tentativa, eliminando a corrida de "quem pega o
--     lock primeiro" e tornando a prova deterministica;
--   - `cycle_events` e append-only e as FKs sao RESTRICT: a prova NAO tem
--     reset parcial. Para reexecutar, `supabase db reset --local` + fixtures
--     (`14-...`) + 16/17/18 (mesma doutrina dos validadores P2/P4).
--
-- Como executar (Supabase local; NUNCA remoto). A em BACKGROUND e B em
-- FOREGROUND, quase ao mesmo tempo:
--   A) Get-Content supabase/validacao/16-sessao-a-f5-09-p9-concorrencia.sql -Raw -Encoding UTF8 |
--        docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   B) idem para 17-...sql (foreground) e, ao final dos dois, 18-...sql.
-- ============================================================================

\set ON_ERROR_STOP on

-- A prova tem uma janela LEGITIMA de ~8s dentro de UMA instrucao (o pg_sleep do
-- artefato temporario). Um `statement_timeout` herdado do papel de conexao
-- (ex.: 8s de `service_role` no Supabase local) nao pode transformar essa janela
-- contratada em falha espuria: o timeout e desligado APENAS nesta sessao de
-- validacao (nenhum objeto do banco e alterado, nenhum controle do produto e
-- relaxado).
set statement_timeout = 0;
set lock_timeout = 0;

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture P9 presente, ator soberano, alvo 2041/1 livre e
--    RPCs na assinatura EXATA do contrato
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama   uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_gestor uuid := 'edc00000-0000-0000-0000-000000000006';
  v_memb   uuid;
  v_n      int;
  v_args   text;
begin
  if not exists (select 1 from public.organizations o where o.id = v_gama) then
    raise exception '[FAIL] pre-condicao A: organizacao Gama-P9 (%) ausente — execute 14-cenario-f5-09-p9.sql', v_gama;
  end if;
  if not exists (
    select 1 from public.user_profiles p where p.id = v_gestor and p.status = 'active'
  ) then
    raise exception '[FAIL] pre-condicao A: perfil ATIVO do gestor-gama (%) ausente na fixture P9', v_gestor;
  end if;
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_gestor
     and m.organization_id = v_gama
     and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] pre-condicao A: membership ATIVA do gestor-gama em Gama-P9 ausente';
  end if;
  if not public.ciclo_ator_valido(v_gestor, v_gama, 'cycle.read') then
    raise exception '[FAIL] pre-condicao A: gestor-gama sem capability efetiva cycle.read em Gama-P9';
  end if;
  if not public.ciclo_ator_valido(v_gestor, v_gama, 'cycle.manage') then
    raise exception '[FAIL] pre-condicao A: gestor-gama sem capability efetiva cycle.manage em Gama-P9';
  end if;

  -- Alvo EXCLUSIVO e deterministico: nenhum ciclo do ano 2041 em Gama-P9 ainda
  -- (o contrato fixo reserva este ano para a corrida; validadores 14/15 nao o
  -- usam em Gama-P9).
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_gama and c.ano = 2041;
  if v_n <> 0 then
    raise exception '[FAIL] pre-condicao A: Gama-P9 ja possui % ciclo(s) do ano 2041 — a trilha e append-only: reexecute a prova apos `supabase db reset --local`', v_n;
  end if;
  -- Periodo alvo livre (I6): nenhum ciclo NAO CANCELADO de Gama-P9 sobrepoe 2041.
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_gama
     and c.status <> 'CANCELADO'
     and c.data_inicio is not null and c.data_fim is not null
     and daterange(c.data_inicio, c.data_fim + 1, '[)')
         && daterange(date '2041-01-01', date '2041-04-10' + 1, '[)');
  if v_n <> 0 then
    raise exception '[FAIL] pre-condicao A: Gama-P9 ja possui % ciclo(s) NAO CANCELADO(s) com periodo sobreposto a 2041', v_n;
  end if;

  -- Assinaturas EXATAS do contrato para as duas RPCs usadas pela corrida.
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)');
  if v_args is distinct from
     'p_organization_id uuid, p_ano integer, p_numero integer, p_data_inicio date, p_data_fim date, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao A: assinatura de ciclo_criar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_ano integer, p_numero integer, p_data_inicio date, p_data_fim date, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao A: assinatura de ciclo_editar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;

  raise notice '[PASS] pre-condicoes da sessao A: Gama-P9 sem ciclo em 2041, gestor-gama % com membership ativa % (cycle.read + cycle.manage), periodo livre e RPCs na assinatura do contrato',
    v_gestor, v_memb;
end $$;

-- Higiene fail-safe: remove artefato temporario de uma execucao ANTERIOR
-- interrompida (idempotente; nao altera nada quando nao existe).
drop trigger if exists _mut_p9_contencao on public.evaluation_cycles;
drop function if exists public._mut_p9_contencao_edicao();
drop sequence if exists public._mut_p9_contencao_seq;

-- ----------------------------------------------------------------------------
-- 1) Passo 1 do desenho: criacao do ciclo PROPRIO da corrida (caminho legitimo)
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama   uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_gestor uuid := 'edc00000-0000-0000-0000-000000000006';
  v_res    jsonb;
  v_ciclo  uuid;
  v_row    record;
  v_n      int;
begin
  v_res := public.ciclo_criar(v_gama, 2041, 1, date '2041-01-01', date '2041-03-31',
    v_gestor, 'ed910000-0000-0000-0000-0000000000a1');
  v_ciclo := (v_res->>'cycle_id')::uuid;

  if v_ciclo is null then
    raise exception '[FAIL] A/criacao: ciclo_criar nao devolveu cycle_id (%)', v_res;
  end if;
  if (v_res->>'status') <> 'PLANEJADO' or (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] A/criacao: retorno deveria ser PLANEJADO/version 0 (%)', v_res;
  end if;

  select c.ano, c.numero, c.status, c.version, c.data_inicio, c.data_fim, c.config_version_id
    into v_row
    from public.evaluation_cycles c
   where c.id = v_ciclo
     and c.organization_id = v_gama;
  if not found then
    raise exception '[FAIL] A/criacao: ciclo nao encontrado apos ciclo_criar';
  end if;
  if v_row.status <> 'PLANEJADO' or v_row.version <> 0
     or v_row.ano <> 2041 or v_row.numero <> 1
     or v_row.data_inicio <> date '2041-01-01' or v_row.data_fim <> date '2041-03-31'
     or v_row.config_version_id is null then
    raise exception '[FAIL] A/criacao: linha divergente do contrato (%, version %, ano %, numero %, %..%, config %)',
      v_row.status, v_row.version, v_row.ano, v_row.numero,
      v_row.data_inicio, v_row.data_fim, v_row.config_version_id;
  end if;

  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_gama
     and e.cycle_id = v_ciclo
     and e.event_type = 'CRIADO'
     and e.operation_id = 'ed910000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] A/criacao: evento CRIADO esperado 1 vez com o operation_id da criacao (encontrado %)', v_n;
  end if;

  raise notice '[PASS] sessao A: ciclo 2041/1 de Gama-P9 criado por ciclo_criar (PLANEJADO/version 0, id=%)', v_ciclo;
  raise notice 'sessao A: alvo da corrida resolvido por SELECT deterministico (organization_id + ano 2041 + numero 1) — nenhum UUID transportado por variavel psql';
end $$;

-- ----------------------------------------------------------------------------
-- 2) Passo 2 do desenho: artefato TEMPORARIO que atrasa a escrita do ciclo
-- ----------------------------------------------------------------------------
-- Duas partes, ambas TEMPORARIAS e removidas no passo 3:
--   (a) `_mut_p9_contencao_seq` — SEQUENCE (nao transacional) usada como MARCA
--       de que a sessao A ja esta DENTRO do UPDATE com o lock da organizacao em
--       maos. E lida por OUTRA sessao (a sessao B) e e o que torna a prova
--       deterministica: B so tenta a escrita quando A ja dorme;
--   (b) `_mut_p9_contencao_edicao()` + gatilho BEFORE UPDATE — grava a marca e
--       executa `pg_sleep(8)`, simulando uma escrita custosa DENTRO da
--       transacao que detem `evaluation_cycles:<organization_id>`.
create sequence public._mut_p9_contencao_seq;

create or replace function public._mut_p9_contencao_edicao()
returns trigger
language plpgsql
as $mut$
declare
  v_gama  uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_ciclo uuid;
  v_marca bigint;
begin
  select c.id into v_ciclo
    from public.evaluation_cycles c
   where c.organization_id = v_gama and c.ano = 2041 and c.numero = 1;
  if v_ciclo is not null and new.id = v_ciclo and new.organization_id = v_gama then
    v_marca := nextval('public._mut_p9_contencao_seq');
    raise notice 'sessao A: DENTRO do UPDATE de evaluation_cycles (2041/1) com o lock evaluation_cycles:% em maos — dormindo 8s antes do commit (marca=%)',
      v_gama, v_marca;
    perform pg_sleep(8);
  end if;
  return new;
end;
$mut$;

create trigger _mut_p9_contencao
  before update on public.evaluation_cycles
  for each row execute function public._mut_p9_contencao_edicao();

-- ----------------------------------------------------------------------------
-- 3) Passos 2 e 3: edicao que VENCE a corrida (expected_version = 0), remocao
--    do artefato, [PASS] e declaracao explicita de vitoria
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama   uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_gestor uuid := 'edc00000-0000-0000-0000-000000000006';
  v_ciclo  uuid;
  v_res    jsonb;
  v_ini    timestamptz;
  v_fim    timestamptz;
  v_seg    numeric;
  v_marca  bigint;
  v_called boolean;
  v_before jsonb;
  v_after  jsonb;
begin
  select c.id into v_ciclo
    from public.evaluation_cycles c
   where c.organization_id = v_gama and c.ano = 2041 and c.numero = 1;
  if v_ciclo is null then
    raise exception '[FAIL] A/edicao: ciclo 2041/1 ausente antes da edicao (o passo de criacao falhou?)';
  end if;

  raise notice 'sessao A: chamando ciclo_editar com expected_version = 0 (mesmo alvo e mesma versao que a sessao B tentara); o lock da organizacao fica em maos ate o commit';
  v_ini := clock_timestamp();
  v_res := public.ciclo_editar(v_ciclo, v_gama, 2041, 1,
    date '2041-01-10', date '2041-04-10', 0, v_gestor,
    'ed910000-0000-0000-0000-0000000000a2');
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  -- Prova de que o gatilho temporario REALMENTE disparou nesta transacao: a
  -- marca e uma sequence NAO transacional, portanto visivel a qualquer sessao.
  select s.last_value, s.is_called into v_marca, v_called
    from public._mut_p9_contencao_seq s;
  if v_called is not true or v_marca < 1 then
    raise exception '[FAIL] A/edicao: o gatilho temporario nao registrou a marca de contencao (is_called=%, last_value=%)',
      v_called, v_marca;
  end if;
  if v_seg < 4.0 then
    raise exception '[FAIL] A/edicao: a escrita durou % segundos (esperado >= 6s: o pg_sleep(8) dentro do UPDATE e a janela de contencao que a sessao B deve sentir)',
      round(v_seg, 3);
  end if;

  if (v_res->>'status') <> 'PLANEJADO' or (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] A/edicao: retorno deveria ser PLANEJADO/version 1 (%)', v_res;
  end if;

  select e.before_value, e.after_value into v_before, v_after
    from public.cycle_events e
   where e.organization_id = v_gama
     and e.cycle_id = v_ciclo
     and e.operation_id = 'ed910000-0000-0000-0000-0000000000a2';
  if v_before is null or v_after is null then
    raise exception '[FAIL] A/edicao: evento EDITADO da edicao vencedora ausente';
  end if;
  if (v_before->>'data_inicio') <> '2041-01-01' or (v_before->>'data_fim') <> '2041-03-31'
     or (v_before->>'version')::int <> 0 or (v_before->>'status') <> 'PLANEJADO' then
    raise exception '[FAIL] A/edicao: before_value deveria ser o estado CRIADO (PLANEJADO, 2041-01-01..2041-03-31, version 0) (%)', v_before;
  end if;
  if (v_after->>'data_inicio') <> '2041-01-10' or (v_after->>'data_fim') <> '2041-04-10'
     or (v_after->>'version')::int <> 1 or (v_after->>'status') <> 'PLANEJADO' then
    raise exception '[FAIL] A/edicao: after_value divergente do contrato (%)', v_after;
  end if;

  raise notice '[PASS] sessao A: edicao aplicada com o lock evaluation_cycles:% em maos por ~% segundos (janela de contencao da sessao B)',
    v_gama, round(v_seg, 3);
end $$;

drop trigger if exists _mut_p9_contencao on public.evaluation_cycles;
drop function if exists public._mut_p9_contencao_edicao();
drop sequence if exists public._mut_p9_contencao_seq;

-- ----------------------------------------------------------------------------
-- 3b) Estado consolidado POS-COMMIT da sessao A (o lock ja foi liberado)
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama   uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_gestor uuid := 'edc00000-0000-0000-0000-000000000006';
  v_memb   uuid;
  v_ciclo  uuid;
  v_row    record;
  v_n      int;
begin
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_gestor
     and m.organization_id = v_gama
     and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] A/estado final: membership ativa do gestor-gama nao resolvida (autoria da trilha nao pode ser conferida)';
  end if;

  select c.id into v_ciclo from public.evaluation_cycles c
   where c.organization_id = v_gama and c.ano = 2041 and c.numero = 1;
  if v_ciclo is null then
    raise exception '[FAIL] A/estado final: ciclo 2041/1 ausente apos o commit da edicao';
  end if;

  select c.ano, c.numero, c.status, c.version, c.data_inicio, c.data_fim,
         c.data_ativacao, c.data_encerramento, c.encerrado_com_pendencias,
         c.quantidade_pendencias, c.config_version_id
    into v_row
    from public.evaluation_cycles c
   where c.id = v_ciclo;
  if not found then
    raise exception '[FAIL] A/estado final: ciclo nao lido';
  end if;
  if v_row.status <> 'PLANEJADO' or v_row.version <> 1
     or v_row.ano <> 2041 or v_row.numero <> 1
     or v_row.data_inicio <> date '2041-01-10' or v_row.data_fim <> date '2041-04-10'
     or v_row.data_ativacao is not null or v_row.data_encerramento is not null
     or v_row.encerrado_com_pendencias is not false or v_row.quantidade_pendencias <> 0
     or v_row.config_version_id is null then
    raise exception '[FAIL] A/estado final: linha divergente do contrato (%, version %, %..%, ativacao %, encerramento %, pendencias %)',
      v_row.status, v_row.version, v_row.data_inicio, v_row.data_fim,
      v_row.data_ativacao, v_row.data_encerramento, v_row.quantidade_pendencias;
  end if;

  -- Trilha da corrida, ate aqui: exatamente CRIADO + EDITADO, no ciclo e com
  -- autoria soberana do gestor-gama (membership ativa resolvida server-side).
  -- CONTRATO: Gama-P9 e a organizacao EXCLUSIVA desta prova (nasce sem ciclos na
  -- fixture 14; os validadores 14/15 operam Alfa-P9).
  select count(*) into v_n from public.cycle_events e where e.organization_id = v_gama;
  if v_n <> 2 then
    raise exception '[FAIL] A/trilha: esperados 2 eventos em Gama-P9 (CRIADO + EDITADO da corrida), encontrados % — verifique se outro validador passou a escrever em Gama-P9', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_gama and e.cycle_id = v_ciclo
     and e.event_type = 'CRIADO'
     and e.operation_id = 'ed910000-0000-0000-0000-0000000000a1'
     and e.result_entity_id = v_ciclo;
  if v_n <> 1 then
    raise exception '[FAIL] A/trilha: evento CRIADO esperado 1 vez com result_entity_id do ciclo (%)', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_gama and e.cycle_id = v_ciclo
     and e.event_type = 'EDITADO'
     and e.operation_id = 'ed910000-0000-0000-0000-0000000000a2'
     and e.result_entity_id = v_ciclo;
  if v_n <> 1 then
    raise exception '[FAIL] A/trilha: evento EDITADO esperado 1 vez com result_entity_id do ciclo (%)', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_gama
     and e.cycle_id = v_ciclo
     and (e.actor_user_profile_id <> v_gestor or e.actor_membership_id <> v_memb);
  if v_n <> 0 then
    raise exception '[FAIL] A/trilha: % evento(s) com autoria diferente do gestor-gama/membership ativa', v_n;
  end if;

  -- Higiene: nenhum residuo do artefato temporario.
  if to_regclass('public._mut_p9_contencao_seq') is not null then
    raise exception '[FAIL] A/higiene: sequence temporaria de contencao NAO foi removida';
  end if;
  if to_regprocedure('public._mut_p9_contencao_edicao()') is not null then
    raise exception '[FAIL] A/higiene: funcao temporaria de contencao NAO foi removida';
  end if;
  if exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_cycles'::regclass
       and t.tgname = '_mut_p9_contencao'
  ) then
    raise exception '[FAIL] A/higiene: gatilho temporario de contencao NAO foi removido';
  end if;

  raise notice '[PASS] sessao A: edicao aplicada e lock liberado (version=1) — a sessao A VENCEU a corrida; periodo consolidado 2041-01-10..2041-04-10';
  raise notice '[PASS] sessao A: trilha do ciclo com exatamente CRIADO + EDITADO, autoria gestor-gama (membership %), result_entity_id do ciclo e artefato temporario removido', v_memb;
  raise notice 'sessao A: a contencao server-side sera provada pelo tempo de espera medido pela sessao B (arquivo 17) e o estado final sera conferido pelo validador 18';
end $$;
