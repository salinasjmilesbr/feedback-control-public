-- ============================================================================
-- F5-09 P9: CONCORRENCIA REAL entre DUAS sessoes PostgreSQL — SESSAO B
-- (segundo processo psql; roda em FOREGROUND, comeca DEPOIS e e BLOQUEADA pelo
-- lock da organizacao detido pela sessao A, terminando em CONFLICT)
-- ----------------------------------------------------------------------------
-- Papel desta sessao (processo psql 2 de 3):
--   (a) aguarda de forma DETERMINISTICA o ciclo criado pela sessao A
--       (`16-sessao-a-f5-09-p9-concorrencia.sql`, processo separado) COM um
--       laco de tentativas (`for i in 1..120 loop ... pg_sleep(0.25) ... end
--       loop`) que aborta com `[FAIL]` se o ciclo nao aparecer;
--   (b) mede `clock_timestamp()` ANTES da tentativa;
--   (c) tenta `ciclo_editar` com o MESMO alvo e o MESMO `expected_version = 0`
--       da sessao A, com INTENCAO DIFERENTE (outras datas, outro
--       `operation_id`);
--   (d) captura a excecao esperada de conflito e mede o tempo decorrido.
--   `[PASS]` apenas se: o erro for o CONFLITO do contrato
--   (`F5_09_CONFLICT` / "versao divergente") E o tempo decorrido for >= ~2s.
--
-- Ordem REAL de execucao (tres processos psql INDEPENDENTES; sem `dblink`, sem
-- `postgres_fdw`, sem extensao nova — a prova e entre dois backends reais):
--   1) `16-sessao-a-f5-09-p9-concorrencia.sql` -> BACKGROUND, iniciado primeiro;
--   2) `17-sessao-b-f5-09-p9-concorrencia.sql` (ESTE arquivo) -> FOREGROUND;
--   3) `18-validar-f5-09-p9-concorrencia.sql` -> single-session, ao final.
--
-- Evidencia de contencao esperada (e POR QUE ela existe):
--   - a sessao A esta DENTRO do UPDATE de `ciclo_editar` ha ~8s (`pg_sleep`
--     injetado por gatilho temporario) com o advisory lock normativo da familia
--     de ciclos adquirido — chave `evaluation_cycles:<organization_id>`
--     (`ciclo_lock_organizacao`, adquirida ANTES de resolver a linha e ANTES da
--     checagem de `expected_version`);
--   - B bate no MESMO lock e fica BLOQUEADA no servidor ate A commitar; o tempo
--     de espera medido aqui (>= ~2s) e a evidencia de contencao SERVER-SIDE
--     entre dois backends;
--   - a marca NAO transacional do gatilho de A (`public._mut_p9_contencao_seq`,
--     uma SEQUENCE) e lida por ESTA sessao apenas para tornar a prova
--     DETERMINISTICA: garante que B tenta a escrita DEPOIS de A ja ter o lock,
--     eliminando a corrida de "quem pega o lock primeiro" (sem essa leitura, o
--     resultado dependeria de quem chegasse antes, o que e cronometragem, nao
--     prova);
--   - apos o bloqueio, B observa a versao commitada por A (1, nunca 0) e o
--     estado de A (periodo 2041-01-10..2041-04-10) — nenhum lost update.
--
-- DIFERENCA EXPLICITA em relacao a P8 (concorrencia client-side):
--   a P8 (`src/services/ciclosSoberanos/controladorGestaoCiclos.test.ts`) prova,
--   em UM unico processo node, que o controlador recusa uma segunda mutation
--   concorrente SEM chamar a Edge ("uma unica operacao por vez"). Ali a
--   serializacao e de INTERFACE (memoria do processo) e nada e bloqueado no
--   banco. Aqui sao DOIS processos `psql` reais: a espera medida no relogio de
--   B so existe porque o PostgreSQL serializa as duas sessoes no advisory lock
--   da organizacao e porque `expected_version` e reavaliado sob o lock.
--
-- operation_id desta sessao (UUIDs sinteticos fixos, NUNCA reutilizados em
-- relacao a sessao A):
--   ciclo_editar 2041/1 (intencao PERDEDORA) -> ed920000-0000-0000-0000-0000000000b1
--   (a sessao A usa ed910000-0000-0000-0000-0000000000a1 na criacao e
--    ed910000-0000-0000-0000-0000000000a2 na edicao vencedora)
--
-- Alvo fixo do contrato P9 (mesmo da sessao A):
--   organizacao Gama-P9 : eda00000-0000-0000-0000-0000000000c1
--   ator gestor-gama    : edc00000-0000-0000-0000-000000000006
--   ciclo 2041/1; intencao de B: 2041-02-01..2041-05-01 (NUNCA aplicada);
--   periodo vencedor de A      : 2041-01-10..2041-04-10.
--
-- Isolamento: READ COMMITTED explicito (nivel default do Supabase/Postgres).
-- A prova depende de snapshot POR COMANDO: e a reavaliacao de
-- `expected_version` sob o lock, depois do commit de A, que produz o CONFLICT.
--
-- LIMITACAO CONHECIDA: a janela de contencao de A e o `pg_sleep(8)` dentro do
-- UPDATE. Se este processo for iniciado DEPOIS de A ter commitado, o laco de
-- espera aborta com `[FAIL]` explicito (o artefato de contencao desaparece) e,
-- se B chegar ao lock com menos de ~2s de A, a prova falha em vez de fingir
-- sucesso. Nesses casos, reinicie A em background e B em foreground dentro da
-- janela (ou aumente o `pg_sleep` de A e o teto do laco abaixo, nos dois
-- arquivos, de forma coerente).
--
-- Como executar (Supabase local; NUNCA remoto) — A ja rodando em BACKGROUND:
--   Get-Content supabase/validacao/17-sessao-b-f5-09-p9-concorrencia.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
-- ============================================================================

\set ON_ERROR_STOP on

-- Isolamento explicito: a reavaliacao sob o lock depende de snapshot por
-- comando (READ COMMITTED). Nao altera nenhum objeto do banco.
set default_transaction_isolation = 'read committed';

-- A prova tem duas esperas LEGITIMAS dentro de UMA instrucao: o laco de
-- tentativas (ate 120 x 0.25s = 30s) e o proprio bloqueio no lock de A (~8s). Um
-- `statement_timeout` herdado do papel de conexao (ex.: 8s de `service_role` no
-- Supabase local) nao pode transformar isso em falha espuria: o timeout e
-- desligado APENAS nesta sessao de validacao (nenhum objeto do banco e
-- alterado, nenhum controle do produto e relaxado).
set statement_timeout = 0;
-- O bloqueio contratado no lock da organizacao (~8s) e a EVIDENCIA da prova:
-- nenhum `lock_timeout` herdado do papel de conexao pode aborta-lo.
set lock_timeout = 0;

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture P9 presente, ator soberano e isolamento correto
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama   uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_gestor uuid := 'edc00000-0000-0000-0000-000000000006';
  v_memb   uuid;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception '[FAIL] pre-condicao B: isolamento % — a prova exige READ COMMITTED (snapshot por comando) para que a releitura sob o lock enxergue o commit de A',
      current_setting('transaction_isolation');
  end if;
  if not exists (select 1 from public.organizations o where o.id = v_gama) then
    raise exception '[FAIL] pre-condicao B: organizacao Gama-P9 (%) ausente — execute 14-cenario-f5-09-p9.sql', v_gama;
  end if;
  if not exists (
    select 1 from public.user_profiles p where p.id = v_gestor and p.status = 'active'
  ) then
    raise exception '[FAIL] pre-condicao B: perfil ATIVO do gestor-gama (%) ausente na fixture P9', v_gestor;
  end if;
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_gestor
     and m.organization_id = v_gama
     and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] pre-condicao B: membership ATIVA do gestor-gama em Gama-P9 ausente';
  end if;
  if not public.ciclo_ator_valido(v_gestor, v_gama, 'cycle.manage') then
    raise exception '[FAIL] pre-condicao B: gestor-gama sem capability efetiva cycle.manage em Gama-P9';
  end if;
  if to_regprocedure('public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)') is null then
    raise exception '[FAIL] pre-condicao B: RPC ciclo_editar ausente na assinatura do contrato';
  end if;

  raise notice '[PASS] pre-condicoes da sessao B: READ COMMITTED, Gama-P9 presente, gestor-gama % com membership ativa % e ciclo.manage efetiva (a corrida comeca no passo seguinte)', v_gestor, v_memb;
end $$;

-- ----------------------------------------------------------------------------
-- 1) Passos (a)-(d): espera deterministica, tentativa concorrente, medicao do
--    bloqueio e captura do CONFLITO do contrato
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama     uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_gestor   uuid := 'edc00000-0000-0000-0000-000000000006';
  v_ciclo    uuid;
  v_pronto   boolean := false;
  v_i        int;
  v_last     bigint;
  v_called   boolean;
  v_ini      timestamptz;
  v_fim      timestamptz;
  v_seg      numeric;
  v_conflito boolean := false;
  v_msg      text;
  v_state    text;
  v_row      record;
  v_n        int;
begin
  -- (a) Espera DETERMINISTICA: (i) o ciclo 2041/1 criado por A existe e (ii) a
  -- sessao A JA esta DENTRO do UPDATE (marca nao transacional do gatilho
  -- temporario, lida de OUTRA sessao). A condicao (ii) e o que garante que a
  -- tentativa de B acontece com o lock da organizacao ja em maos de A.
  for v_i in 1..120 loop
    select c.id into v_ciclo
      from public.evaluation_cycles c
     where c.organization_id = v_gama and c.ano = 2041 and c.numero = 1;
    v_pronto := false;
    if v_ciclo is not null and to_regclass('public._mut_p9_contencao_seq') is not null then
      select s.last_value, s.is_called into v_last, v_called
        from public._mut_p9_contencao_seq s;
      if v_called is true and v_last >= 1 then
        v_pronto := true;
      end if;
    end if;
    exit when v_pronto;
    perform pg_sleep(0.25);
  end loop;

  if not v_pronto then
    if v_ciclo is null then
      raise exception '[FAIL] sessao B (a): o ciclo 2041/1 criado pela sessao A nao apareceu em 30s — inicie 16-...sql em BACKGROUND e este arquivo em FOREGROUND';
    end if;
    raise exception '[FAIL] sessao B (a): a marca de contencao da sessao A (public._mut_p9_contencao_seq) nao foi observada em 30s — a sessao B precisa tentar a escrita ENQUANTO A dorme ~8s dentro do UPDATE (A ja terminou e removeu o artefato?)';
  end if;

  raise notice 'sessao B: ciclo de A visivel (id=%) e sessao A DENTRO do UPDATE (marca nao transacional lida de OUTRA sessao) — tentando a escrita concorrente com expected_version = 0', v_ciclo;

  -- (b)+(c) Medicao ANTES e tentativa com a MESMA versao declarada e INTENCAO
  -- DIFERENTE (outras datas, outro operation_id).
  v_ini := clock_timestamp();
  begin
    perform public.ciclo_editar(v_ciclo, v_gama, 2041, 1,
      date '2041-02-01', date '2041-05-01', 0, v_gestor,
      'ed920000-0000-0000-0000-0000000000b1');
  exception when others then
    v_msg  := sqlerrm;
    v_state := sqlstate;
    v_conflito := (sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%versao divergente%');
  end;
  -- (d) Medicao DEPOIS (clock_timestamp, nao `now()`: o bloco todo e um unico
  -- comando e `now()` seria o MESMO instante no inicio e no fim).
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  -- A edicao de B NAO pode ter sido aplicada: o desfecho exigido e CONFLICT.
  if v_msg is null then
    raise exception '[FAIL] sessao B (c): a edicao da sessao B foi APLICADA — o contrato exige CONFLICT (nenhuma escrita concorrente pode vencer o lock/versao)';
  end if;
  if not v_conflito then
    raise exception '[FAIL] sessao B (c): erro inesperado (sqlstate %, mensagem %) — esperado o CONFLITO do contrato (F5_09_CONFLICT com "versao divergente")',
      v_state, v_msg;
  end if;
  -- A espera e a EVIDENCIA de contencao server-side (diferente da concorrencia
  -- client-side da P8, onde a segunda mutation nem chega ao servidor).
  if v_seg < 2.0 then
    raise exception '[FAIL] sessao B (d): B NAO ficou bloqueada (% segundos < 2s) — sem espera nao ha prova de contencao server-side; reinicie A em BACKGROUND e B em FOREGROUND dentro da janela de ~8s do pg_sleep de A',
      round(v_seg, 3);
  end if;

  raise notice '[PASS] sessao B (c): escrita concorrente recusada pelo contrato — sqlstate % / %', v_state, v_msg;
  raise notice '[PASS] sessao B (d): B ficou BLOQUEADA no advisory lock da organizacao (evaluation_cycles:%) por ~% segundos antes do CONFLITO — contencao SERVER-SIDE real entre dois backends, diferente da concorrencia client-side da P8',
    v_gama, round(v_seg, 3);

  -- (5) Nenhum lost update: o estado lido APOS a falha e o de A, e a versao
  -- observada sob o lock foi a de A (1) — nunca 0.
  select c.ano, c.numero, c.status, c.version, c.data_inicio, c.data_fim, c.updated_at
    into v_row
    from public.evaluation_cycles c
   where c.organization_id = v_gama and c.id = v_ciclo;
  if not found then
    raise exception '[FAIL] sessao B (5): o ciclo alvo desapareceu apos a falha';
  end if;
  if v_row.version <> 1 then
    raise exception '[FAIL] sessao B (5): versao observada apos o bloqueio = % (esperado 1, a versao commitada por A; 0 significaria que B leu o estado anterior a A e nao houve contencao)',
      v_row.version;
  end if;
  if v_row.status <> 'PLANEJADO'
     or v_row.data_inicio <> date '2041-01-10' or v_row.data_fim <> date '2041-04-10' then
    raise exception '[FAIL] sessao B (5): o estado apos a falha nao e o de A (%, %..%) — lost update; o periodo de B (2041-02-01..2041-05-01) nunca pode ser gravado',
      v_row.status, v_row.data_inicio, v_row.data_fim;
  end if;

  -- A trilha prova que a UNICA edicao aplicada foi a de A: nenhum evento da
  -- intencao de B, exatamente 1 EDITADO e com o after_value de A.
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_gama
     and e.operation_id = 'ed920000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] sessao B (5): a intencao perdedora gravou % evento(s) na trilha', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_gama and e.cycle_id = v_ciclo and e.event_type = 'EDITADO';
  if v_n <> 1 then
    raise exception '[FAIL] sessao B (5): esperado exatamente 1 evento EDITADO no ciclo (encontrados %)', v_n;
  end if;
  if not exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_gama
       and e.cycle_id = v_ciclo
       and e.event_type = 'EDITADO'
       and e.operation_id = 'ed910000-0000-0000-0000-0000000000a2'
       and (e.after_value->>'data_inicio') = '2041-01-10'
       and (e.after_value->>'data_fim') = '2041-04-10'
       and (e.after_value->>'version')::int = 1
  ) then
    raise exception '[FAIL] sessao B (5): o EDITADO aplicado nao e o da edicao vencedora de A (2041-01-10..2041-04-10, version 1)';
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_gama and e.cycle_id = v_ciclo;
  if v_n <> 2 then
    raise exception '[FAIL] sessao B (5): a trilha do ciclo deveria ter exatamente CRIADO + EDITADO (encontrados %)', v_n;
  end if;

  raise notice '[PASS] sessao B (5): nenhum lost update — o estado lido apos o bloqueio e o de A (version=1, PLANEJADO, 2041-01-10..2041-04-10) e a versao observada sob o lock foi 1, nunca 0';
  raise notice '[PASS] sessao B (5): a intencao perdedora de B (operation_id ed920000-0000-0000-0000-0000000000b1) nao gravou evento nem estado — a unica edicao aplicada e a de A';
  raise notice 'sessao B: a espera de ~% segundos no lock da organizacao e a evidencia de contencao REAL no banco; a evidencia client-side da P8 (controlador sem chamar a Edge) NAO substitui esta prova', round(v_seg, 3);
end $$;
