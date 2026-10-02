-- ============================================================================
-- F6 / Issue #427: CONCORRENCIA REAL entre DUAS sessoes — VALIDADOR CONSOLIDADO
-- (59) — single-session; roda SOMENTE depois de A e B terminarem
-- ----------------------------------------------------------------------------
-- Papel deste arquivo (processo psql 3 de 3):
--   conferir o ESTADO FINAL CONSOLIDADO da corrida de
--   `57-sessao-a-f6-427-concorrencia.sql` x `58-sessao-b-f6-427-concorrencia.sql`
--   na organizacao EXCLUSIVA `f427a000-0000-0000-0000-0000000000a1`, sem
--   depender de nenhum artefato temporario (que ja foi removido pela sessao A):
--     - X, Y e Z com EXATAMENTE UMA ocupacao ABERTA cada;
--     - ZERO par de ocupacoes sobrepostas do mesmo colaborador em TODA a
--       organizacao da corrida (consulta set-based meio-aberta);
--     - os intervalos FECHADOS esperados: XP1 fechada EXATAMENTE em 2035-01-01Z
--       (janela 1) e YQ1 fechada EXATAMENTE em 2036-02-01Z (janela 2, transicao
--       consecutiva aplicada pela sessao B);
--     - a trilha `collaborator_events` com os eventos das operacoes APLICADAS
--       (A nas tres janelas + B na janela 2) e SEM NENHUM evento da intencao
--       PERDEDORA (janela 1) nem da insercao CRUA da janela 3;
--     - Z com exatamente UMA ocupacao (a de A) e nenhuma linha da insercao crua;
--     - o artefato TEMPORARIO de contencao da sessao A COMPLETAMENTE removido
--       (`to_regclass` da sequence, `to_regprocedure` da funcao e `pg_trigger`);
--     - a barreira nova intacta: `ex_occupations_collaborator_no_overlap`
--       presente na forma MEIO-ABERTA (`pg_get_constraintdef` contendo `[)`) ao
--       lado da exclusao por POSICAO, e a ORDEM CANONICA DE LOCKS (linha do
--       colaborador ANTES do advisory lock da organizacao) presente no texto das
--       TRES RPCs de ocupacao.
--   Qualquer divergencia aborta com `raise exception '[FAIL] ...'`.
--
-- Ordem REAL de execucao (tres processos psql INDEPENDENTES; sem `dblink`, sem
-- `postgres_fdw`, sem extensao nova):
--   1) `56-cenario-f6-427-concorrencia.sql` -> fixture EXCLUSIVA, single-session;
--   2) `57-sessao-a-f6-427-concorrencia.sql` -> BACKGROUND (vence as tres janelas);
--   3) `58-sessao-b-f6-427-concorrencia.sql` -> FOREGROUND (bloqueada pelos locks
--      de A; termina com F5_07_CONFLICT na janela 1, SUCESSO serializado na
--      janela 2 e 23P01 na janela 3);
--   4) `59-validar-f6-427-concorrencia.sql` (ESTE arquivo) -> single-session.
--   No CI: A em background (`&`), `sleep 1`, B em foreground, `wait` em A e, por
--   ultimo, este validador.
--
-- Evidencia de contencao (produzida por 57/58 e CONFERIDA aqui):
--   a espera >= 2s medida pela sessao B em CADA janela — bloqueio na linha do
--   colaborador (janelas 1 e 2) e espera da propria exclusion GiST (janela 3) —
--   enquanto A dormia ~8s DENTRO da escrita com a linha do colaborador travada
--   (`for update`) e o advisory lock da organizacao em maos. O invariante desta
--   Issue (no maximo UMA ocupacao por colaborador em qualquer instante) e a
--   barreira final do banco (`ex_occupations_collaborator_no_overlap`).
--
-- operation_id da corrida (UUIDs sinteticos fixos; documentados nos headers das
-- duas sessoes; nenhum e reaproveitado entre elas):
--   A janela 1 definir X -> XP2 (2035-01-01Z) -> f4279000-0000-0000-0000-0000000000a1
--     (+ derivado md5(op || ':OCUPACAO_ENCERRADA') para o encerramento de XP1)
--   A janela 2 definir Y -> YQ1 (2036-01-01Z) -> f4279000-0000-0000-0000-0000000000a2
--   A janela 3 definir Z -> ZR1 (2037-01-01Z) -> f4279000-0000-0000-0000-0000000000a3
--   B janela 1 trocar X (PERDEDORA)         -> f4279100-0000-0000-0000-0000000000b1
--     (NAO pode ter evento nenhum; conferido em TODA a tabela)
--   B janela 2 definir Y -> YQ2 (2036-02-01Z) -> f4279100-0000-0000-0000-0000000000b2
--     (+ derivado md5(op || ':OCUPACAO_ENCERRADA') para o encerramento de YQ1)
--   B janela 3 insercao CRUA de Z em ZR2 (id reservado
--     f4278000-0000-0000-0000-0000000003f1) — NAO pode existir nenhuma linha.
--
-- Alvo fixo do contrato (fixture EXCLUSIVA `56-cenario-f6-427-concorrencia.sql`;
-- nenhum outro validador escreve nesta organizacao):
--   organizacao          : f427a000-0000-0000-0000-0000000000a1
--   ator soberano        : f427b000-0000-0000-0000-0000000000a1
--                          (membership ativa f427d000-0000-0000-0000-0000000000a1)
--   colaborador X        : f427c000-0000-0000-0000-0000000000a1
--   colaborador Y        : f427c000-0000-0000-0000-0000000000a2
--   colaborador Z        : f427c000-0000-0000-0000-0000000000a3
--   posicoes             : XP1 ...c1, XP2 ...c2, XP3 ...c3, YQ1 ...c4,
--                          YQ2 ...c5, ZR1 ...c6, ZR2 ...c7
--
-- Estado mutado e reaplicabilidade: a corrida FECHA ocupacoes, ABRE ocupacoes e
-- grava eventos. `collaborator_events` e append-only (UPDATE negado por gatilho,
-- DELETE sem grant) e as ocupacoes sao historicas: reexecutar 56+57+58+59 sem
-- `supabase db reset --local` NAO e suportado (o caminho correto e o do CI:
-- reset -> fixtures -> 57 em background -> 58 em foreground -> 59).
--
-- Este arquivo NAO desabilita constraint/trigger, NAO relaxa RLS/grants e NAO
-- cria `SECURITY DEFINER`; somente dados ficticios (prefixo `f427`).
-- Todos os negativos rodam em subtransacao (`begin ... exception ... end;`).
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture EXCLUSIVA presente, superficie fechada, barreira
--    nova na forma meio-aberta `[)` e ORDEM CANONICA DE LOCKS nas tres RPCs
-- ----------------------------------------------------------------------------
do $$
declare
  v_org        uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator       uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_memb       uuid;
  v_n          int;
  v_args       text;
  v_def        text;
  v_fn         text;
  v_pos_linha  int;
  v_pos_advis  int;
begin
  if not exists (select 1 from public.organizations o where o.id = v_org) then
    raise exception '[FAIL] 59: organizacao EXCLUSIVA da corrida (%) ausente — execute 56-cenario-f6-427-concorrencia.sql', v_org;
  end if;
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator and m.organization_id = v_org and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] 59: membership ATIVA do ator da corrida (%) na organizacao da corrida ausente', v_ator;
  end if;

  select count(*) into v_n from public.collaborators c where c.organization_id = v_org;
  if v_n <> 3 then
    raise exception '[FAIL] 59: a organizacao EXCLUSIVA da corrida deveria ter exatamente 3 colaboradores (X/Y/Z), encontrados % — outro validador escreveu nesta organizacao e a prova precisa ser REATRIBUIDA, nunca afrouxada', v_n;
  end if;
  select count(*) into v_n from public.organizational_positions p where p.organization_id = v_org;
  if v_n <> 7 then
    raise exception '[FAIL] 59: posicoes esperadas=7 na organizacao da corrida, encontradas %', v_n;
  end if;

  -- Barreira final: as DUAS exclusoes (posicao + colaborador) e a forma
  -- MEIO-ABERTA `[)` explicitamente no texto da constraint nova.
  select count(*) into v_n from pg_constraint
   where conrelid = 'public.occupations'::regclass
     and conname in ('ex_occupations_position_no_overlap','ex_occupations_collaborator_no_overlap')
     and contype = 'x';
  if v_n <> 2 then
    raise exception '[FAIL] 59: exclusoes de occupations esperadas=2, encontradas=% — a fundacao F3-05/F6-427 foi alterada', v_n;
  end if;
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'public.occupations'::regclass and c.conname = 'ex_occupations_collaborator_no_overlap';
  if v_def is null then
    raise exception '[FAIL] 59: constraint ex_occupations_collaborator_no_overlap ausente em public.occupations';
  end if;
  if position('[)' in v_def) = 0 then
    raise exception '[FAIL] 59: ex_occupations_collaborator_no_overlap fora da forma MEIO-ABERTA [) — definicao: %', v_def;
  end if;
  if position('collaborator_id' in v_def) = 0 then
    raise exception '[FAIL] 59: ex_occupations_collaborator_no_overlap nao e a exclusao POR COLABORADOR — definicao: %', v_def;
  end if;

  -- Assinaturas EXATAS e SECURITY INVOKER (nenhum DEFINER novo) + superficie
  -- fechada ao cliente (EXECUTE somente service_role).
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)');
  if v_args is distinct from
     'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_position_id uuid, p_vigencia timestamp with time zone, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid' then
    raise exception '[FAIL] 59: assinatura de estrutura_ocupacao_definir fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p
   where p.oid = to_regprocedure('public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)');
  if v_args is distinct from
     'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_current_position_id uuid, p_new_position_id uuid, p_vigencia timestamp with time zone, p_motivo text' then
    raise exception '[FAIL] 59: assinatura de estrutura_ocupacao_trocar fora do contrato (%)', coalesce(v_args, 'ausente');
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and p.proname in ('estrutura_ocupacao_definir','estrutura_ocupacao_trocar'))
  then
    raise exception '[FAIL] 59: RPC de ocupacao virou SECURITY DEFINER (proibido)';
  end if;
  if has_function_privilege('authenticated',
       'public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)', 'EXECUTE')
     or not has_function_privilege('service_role',
       'public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid)', 'EXECUTE')
     or not has_function_privilege('service_role',
       'public.estrutura_ocupacao_trocar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text)', 'EXECUTE') then
    raise exception '[FAIL] 59: EXECUTE das RPCs de ocupacao fora do contrato (service_role apenas)';
  end if;

  -- Append-only da trilha ESTRUTURAL (o log da corrida tem de seguir append-only).
  select count(*) into v_n from pg_trigger t
   where t.tgrelid = 'public.collaborator_events'::regclass
     and not t.tgisinternal
     and t.tgname = 'trg_collaborator_events_append_only';
  if v_n <> 1 then
    raise exception '[FAIL] 59: gatilho append-only de collaborator_events ausente (encontrados %)', v_n;
  end if;

  -- ORDEM CANONICA DE LOCKS: (1) linha do colaborador ANTES de (2) advisory lock
  -- da organizacao, nas TRES RPCs de ocupacao. Checagem ESTATICA e DETERMINISTICA
  -- — e ela que denuncia a regressao de ordem mesmo quando o escalonamento das
  -- duas sessoes nao chega a formar o ciclo de espera (40P01).
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
      raise exception '[FAIL] 59: RPC public.% ausente', v_fn;
    end if;
    v_pos_linha := position('public.collaborators' in v_def);
    v_pos_advis := position('pg_advisory_xact_lock' in v_def);
    if v_pos_linha = 0 or v_pos_advis = 0 then
      raise exception '[FAIL] 59: nao foi possivel localizar o travamento da linha do colaborador e/ou o advisory lock da organizacao no corpo de public.%', v_fn;
    end if;
    if not (v_pos_linha < v_pos_advis) then
      raise exception '[FAIL] 59: ORDEM CANONICA DE LOCKS REGREDIU em public.% — o advisory lock da organizacao aparece ANTES do travamento da linha do colaborador (posicoes % e %). Com a ordem invertida uma corrida definir x trocar sobre o MESMO colaborador forma ciclo de espera (SQLSTATE 40P01 / "deadlock detected") em vez do F5_07_CONFLICT publico',
        v_fn, v_pos_advis, v_pos_linha;
    end if;
  end loop;

  raise notice '[PASS] 59: organizacao EXCLUSIVA % presente (3 colaboradores, 7 posicoes), ator % com membership ativa %, exclusoes por POSICAO e por COLABORADOR instaladas na forma meio-aberta [), RPCs na assinatura do contrato e SECURITY INVOKER com EXECUTE somente service_role, trilha append-only ativa e ORDEM CANONICA DE LOCKS (linha do colaborador antes do advisory lock da organizacao) presente em definir/trocar/encerrar',
    v_org, v_ator, v_memb;
end $$;

-- ----------------------------------------------------------------------------
-- 1) Estado CONSOLIDADO por colaborador + invariante set-based na organizacao
--    EXCLUSIVA da corrida
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_x      uuid := 'f427c000-0000-0000-0000-0000000000a1';
  v_y      uuid := 'f427c000-0000-0000-0000-0000000000a2';
  v_z      uuid := 'f427c000-0000-0000-0000-0000000000a3';
  v_xp1    uuid := 'f4278000-0000-0000-0000-0000000000c1';
  v_xp2    uuid := 'f4278000-0000-0000-0000-0000000000c2';
  v_xp3    uuid := 'f4278000-0000-0000-0000-0000000000c3';
  v_yq1    uuid := 'f4278000-0000-0000-0000-0000000000c4';
  v_yq2    uuid := 'f4278000-0000-0000-0000-0000000000c5';
  v_zr1    uuid := 'f4278000-0000-0000-0000-0000000000c6';
  v_zr2    uuid := 'f4278000-0000-0000-0000-0000000000c7';
  v_raw_id uuid := 'f4278000-0000-0000-0000-0000000003f1';
  v_n      int;
  v_card   int;
  v_pos    uuid;
begin
  -- (a) X — janela 1 APLICADA por A: XP1 [2024-01-01Z, 2035-01-01Z) e XP2 ABERTA
  -- desde 2035-01-01Z. Exatamente UMA ABERTA e nenhuma linha em XP3.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x;
  if v_n <> 2 then
    raise exception '[FAIL] 59/X: X deveria ter 2 ocupacoes (XP1 fechada + XP2 aberta), tem %', v_n;
  end if;
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_x and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] 59/X: X deveria ter exatamente 1 ocupacao ABERTA, tem %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp2
       and o.valid_from = '2035-01-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] 59/X: a ocupacao ABERTA de X deveria ser XP2 desde 2035-01-01Z';
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp1
       and o.valid_from = '2024-01-01T00:00:00Z'
       and o.valid_to = '2035-01-01T00:00:00Z'
  ) then
    raise exception '[FAIL] 59/X: XP1 deveria estar FECHADA exatamente em 2035-01-01Z (intervalo esperado [2024-01-01Z, 2035-01-01Z))';
  end if;
  if exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_x
       and o.organizational_position_id = v_xp3
  ) then
    raise exception '[FAIL] 59/X: existe ocupacao de X na posicao XP3 — efeito da intencao PERDEDORA da sessao B';
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_x,'2034-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] 59/X: cardinalidade de X em 2034-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_x,'2035-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] 59/X: cardinalidade de X em 2035-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_x,'2035-01-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] 59/X: cardinalidade de X no INSTANTE da transicao (2035-01-01Z) deveria ser 1 (meio-aberto: em 2035-01-01Z vale XP2) — recebido %', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_x,'2035-01-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_xp2 then
    raise exception '[FAIL] 59/X: posicao soberana de X em 2035-01-01Z deveria ser XP2 (%)', v_pos;
  end if;
  select public.colaborador_posicao_soberana(v_x,'2034-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_xp1 then
    raise exception '[FAIL] 59/X: posicao soberana de X em 2034-06 deveria ser XP1 (%)', v_pos;
  end if;

  -- (b) Y — janelas 2 APLICADAS por A e por B, SERIALIZADAS: YQ1
  -- [2036-01-01Z, 2036-02-01Z) e YQ2 ABERTA desde 2036-02-01Z.
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_y;
  if v_n <> 2 then
    raise exception '[FAIL] 59/Y: Y deveria ter 2 ocupacoes (YQ1 fechada + YQ2 aberta), tem % — a serializacao pelo travamento da linha do colaborador nao ocorreu como contratado', v_n;
  end if;
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_y and o.valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] 59/Y: Y deveria ter exatamente 1 ocupacao ABERTA, tem %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_y
       and o.organizational_position_id = v_yq1
       and o.valid_from = '2036-01-01T00:00:00Z'
       and o.valid_to = '2036-02-01T00:00:00Z'
  ) then
    raise exception '[FAIL] 59/Y: YQ1 deveria estar FECHADA exatamente em 2036-02-01Z (intervalo esperado [2036-01-01Z, 2036-02-01Z)) — a janela 2 da sessao B nao foi aplicada';
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_y
       and o.organizational_position_id = v_yq2
       and o.valid_from = '2036-02-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] 59/Y: a ocupacao ABERTA de Y deveria ser YQ2 desde 2036-02-01Z';
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_y,'2035-06-01T00:00:00Z') into v_card;
  if v_card <> 0 then
    raise exception '[FAIL] 59/Y: cardinalidade de Y ANTES da janela 2 (2035-06) deveria ser 0 (recebido %)', v_card;
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_y,'2036-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] 59/Y: cardinalidade de Y em 2036-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_y,'2036-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_yq2 then
    raise exception '[FAIL] 59/Y: posicao soberana de Y em 2036-06 deveria ser YQ2 (%)', v_pos;
  end if;

  -- (c) Z — janela 3: A APLICOU (ZR1 aberta desde 2037-01-01Z) e a insercao CRUA
  -- da sessao B NAO existe (nem a linha reservada, nem qualquer outra em ZR2).
  select count(*) into v_n from public.occupations o
   where o.organization_id = v_org and o.collaborator_id = v_z;
  if v_n <> 1 then
    raise exception '[FAIL] 59/Z: Z deveria ter exatamente 1 ocupacao (a de A), tem %', v_n;
  end if;
  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_z
       and o.organizational_position_id = v_zr1
       and o.valid_from = '2037-01-01T00:00:00Z' and o.valid_to is null
  ) then
    raise exception '[FAIL] 59/Z: a ocupacao ABERTA de Z deveria ser ZR1 desde 2037-01-01Z';
  end if;
  if exists (select 1 from public.occupations o where o.id = v_raw_id) then
    raise exception '[FAIL] 59/Z: a linha da insercao CRUA sobreposta da sessao B (%) persistiu — a exclusion por colaborador nao barrou', v_raw_id;
  end if;
  if exists (
    select 1 from public.occupations o
     where o.organization_id = v_org and o.collaborator_id = v_z
       and o.organizational_position_id = v_zr2
  ) then
    raise exception '[FAIL] 59/Z: existe ocupacao de Z na posicao ZR2 (alvo da insercao crua da sessao B)';
  end if;
  select public.colaborador_ocupacoes_cardinalidade(v_z,'2037-06-01T00:00:00Z') into v_card;
  if v_card <> 1 then
    raise exception '[FAIL] 59/Z: cardinalidade de Z em 2037-06 deveria ser 1 (recebido %)', v_card;
  end if;
  select public.colaborador_posicao_soberana(v_z,'2037-06-01T00:00:00Z') into v_pos;
  if v_pos is distinct from v_zr1 then
    raise exception '[FAIL] 59/Z: posicao soberana de Z em 2037-06 deveria ser ZR1 (%)', v_pos;
  end if;

  -- (d) Volume EXATO da organizacao EXCLUSIVA: 5 ocupacoes (X 2 + Y 2 + Z 1).
  select count(*) into v_n from public.occupations o where o.organization_id = v_org;
  if v_n <> 5 then
    raise exception '[FAIL] 59: a organizacao da corrida deveria ter exatamente 5 ocupacoes (X 2 + Y 2 + Z 1), tem % — estado extra significa escrita nao contratada ou outro validador na organizacao EXCLUSIVA da prova', v_n;
  end if;

  -- (e) INVARIANTE set-based (a prova do invariante da #427): ZERO par de
  -- ocupacoes do MESMO colaborador com intervalos meio-abertos intersectando, em
  -- TODA a organizacao da corrida.
  select count(*) into v_n
    from public.occupations a
    join public.occupations b
      on b.collaborator_id = a.collaborator_id
     and b.id > a.id
     and tstzrange(a.valid_from, coalesce(a.valid_to,'infinity'::timestamptz), '[)')
      && tstzrange(b.valid_from, coalesce(b.valid_to,'infinity'::timestamptz), '[)')
   where a.organization_id = v_org;
  if v_n <> 0 then
    raise exception '[FAIL] 59: existem % par(es) de ocupacoes SOBREPOSTAS do mesmo colaborador na organizacao da corrida — o invariante da #427 (no maximo UMA ocupacao por colaborador em qualquer instante) foi violado', v_n;
  end if;

  -- (f) Nenhum colaborador da organizacao com mais de UMA ocupacao ABERTA.
  select count(*) into v_n from (
    select o.collaborator_id
      from public.occupations o
     where o.organization_id = v_org and o.valid_to is null
     group by o.collaborator_id
    having count(*) > 1
  ) t;
  if v_n <> 0 then
    raise exception '[FAIL] 59: % colaborador(es) com mais de UMA ocupacao ABERTA na organizacao da corrida', v_n;
  end if;

  raise notice '[PASS] 59: estado consolidado da corrida — X com XP1 [2024-01-01Z, 2035-01-01Z) + XP2 ABERTA; Y com YQ1 [2036-01-01Z, 2036-02-01Z) + YQ2 ABERTA; Z com ZR1 ABERTA desde 2037-01-01Z; exatamente UMA ocupacao ABERTA por colaborador, 5 ocupacoes na organizacao e ZERO par sobreposto (consulta set-based meio-aberta)';
end $$;

-- ----------------------------------------------------------------------------
-- 2) Trilha `collaborator_events` da corrida: operacoes APLICADAS presentes e
--    intencoes PERDEDORAS sem nenhum evento (nem estado)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'f427a000-0000-0000-0000-0000000000a1';
  v_ator   uuid := 'f427b000-0000-0000-0000-0000000000a1';
  v_memb   uuid;
  v_x      uuid := 'f427c000-0000-0000-0000-0000000000a1';
  v_y      uuid := 'f427c000-0000-0000-0000-0000000000a2';
  v_z      uuid := 'f427c000-0000-0000-0000-0000000000a3';
  v_a1     uuid := 'f4279000-0000-0000-0000-0000000000a1';
  v_a2     uuid := 'f4279000-0000-0000-0000-0000000000a2';
  v_a3     uuid := 'f4279000-0000-0000-0000-0000000000a3';
  v_b1     uuid := 'f4279100-0000-0000-0000-0000000000b1';
  v_b2     uuid := 'f4279100-0000-0000-0000-0000000000b2';
  v_n      int;
begin
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator and m.organization_id = v_org and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] 59/trilha: membership ATIVA do ator da corrida nao resolvida (a autoria da trilha nao pode ser conferida)';
  end if;

  -- Volume EXATO: 6 eventos — A/janela 1 (iniciada + encerrada), A/janela 2
  -- (iniciada), A/janela 3 (iniciada), B/janela 2 (iniciada + encerrada).
  select count(*) into v_n from public.collaborator_events e where e.organization_id = v_org;
  if v_n <> 6 then
    raise exception '[FAIL] 59/trilha: a organizacao da corrida deveria ter exatamente 6 eventos (A: XP2, encerramento de XP1, YQ1, ZR1; B: YQ2 e encerramento de YQ1), encontrados % — a intencao perdedora da janela 1 nao pode gravar evento, e a insercao crua da janela 3 nao grava nenhum', v_n;
  end if;

  -- A/janela 1: OCUPACAO_INICIADA (XP2) + OCUPACAO_ENCERRADA de XP1 (DERIVADO).
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_x
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_a1
     and e.position_id = 'f4278000-0000-0000-0000-0000000000c2'
     and e.effective_date = '2035-01-01T00:00:00Z';
  if v_n <> 1 then
    raise exception '[FAIL] 59/trilha: esperado 1 evento OCUPACAO_INICIADA de A na janela 1 (X/XP2 em 2035-01-01Z), encontrados %', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_x
     and e.event_type = 'OCUPACAO_ENCERRADA'
     and e.operation_id = md5(v_a1::text || ':OCUPACAO_ENCERRADA')::uuid
     and e.position_id = 'f4278000-0000-0000-0000-0000000000c1'
     and e.effective_date = '2035-01-01T00:00:00Z';
  if v_n <> 1 then
    raise exception '[FAIL] 59/trilha: esperado 1 evento OCUPACAO_ENCERRADA de A (operation_id DERIVADO) fechando XP1 em 2035-01-01Z, encontrados %', v_n;
  end if;

  -- A/janela 2: OCUPACAO_INICIADA (YQ1) — sem encerramento (Y nasceu sem ocupacao).
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_a2
     and e.position_id = 'f4278000-0000-0000-0000-0000000000c4'
     and e.effective_date = '2036-01-01T00:00:00Z';
  if v_n <> 1 then
    raise exception '[FAIL] 59/trilha: esperado 1 evento OCUPACAO_INICIADA de A na janela 2 (Y/YQ1 em 2036-01-01Z), encontrados %', v_n;
  end if;

  -- A/janela 3: OCUPACAO_INICIADA (ZR1).
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_z
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_a3
     and e.position_id = 'f4278000-0000-0000-0000-0000000000c6'
     and e.effective_date = '2037-01-01T00:00:00Z';
  if v_n <> 1 then
    raise exception '[FAIL] 59/trilha: esperado 1 evento OCUPACAO_INICIADA de A na janela 3 (Z/ZR1 em 2037-01-01Z), encontrados %', v_n;
  end if;

  -- B/janela 2 (SERIALIZADA, APLICADA): OCUPACAO_INICIADA (YQ2) + OCUPACAO_ENCERRADA
  -- de YQ1 com o operation_id DERIVADO.
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y
     and e.event_type = 'OCUPACAO_INICIADA' and e.operation_id = v_b2
     and e.position_id = 'f4278000-0000-0000-0000-0000000000c5'
     and e.effective_date = '2036-02-01T00:00:00Z';
  if v_n <> 1 then
    raise exception '[FAIL] 59/trilha: esperado 1 evento OCUPACAO_INICIADA de B na janela 2 (Y/YQ2 em 2036-02-01Z), encontrados % — a operacao serializada de B tem de estar auditada', v_n;
  end if;
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org and e.collaborator_id = v_y
     and e.event_type = 'OCUPACAO_ENCERRADA'
     and e.operation_id = md5(v_b2::text || ':OCUPACAO_ENCERRADA')::uuid
     and e.position_id = 'f4278000-0000-0000-0000-0000000000c4'
     and e.effective_date = '2036-02-01T00:00:00Z';
  if v_n <> 1 then
    raise exception '[FAIL] 59/trilha: esperado 1 evento OCUPACAO_ENCERRADA de B (operation_id DERIVADO) fechando YQ1 em 2036-02-01Z, encontrados %', v_n;
  end if;

  -- INTENCAO PERDEDORA da janela 1: NENHUM evento em NENHUMA organizacao (nem com
  -- o operation_id principal, nem com o derivado de encerramento).
  select count(*) into v_n from public.collaborator_events e
   where e.operation_id in (v_b1, md5(v_b1::text || ':OCUPACAO_ENCERRADA')::uuid);
  if v_n <> 0 then
    raise exception '[FAIL] 59/trilha: a intencao PERDEDORA da sessao B na janela 1 (%) gravou % evento(s) em collaborator_events', v_b1, v_n;
  end if;

  -- Autoria/tenant soberanos em 100% dos eventos da organizacao da corrida.
  select count(*) into v_n from public.collaborator_events e
   where e.organization_id = v_org
     and (e.collaborator_id is null
       or e.collaborator_id not in (v_x, v_y, v_z)
       or e.position_id is null
       or e.actor_user_profile_id <> v_ator
       or e.actor_membership_id is distinct from v_memb
       or e.reason is null or btrim(e.reason) = ''
       or e.effective_date is null
       or e.payload_hash is null
       or e.event_type not in ('OCUPACAO_INICIADA','OCUPACAO_ENCERRADA'));
  if v_n <> 0 then
    raise exception '[FAIL] 59/trilha: % evento(s) sem tenant/alvo/autoria/motivo/vigencia/hash soberanos na organizacao da corrida', v_n;
  end if;

  raise notice '[PASS] 59/trilha: exatamente 6 eventos (A: XP2, encerramento de XP1, YQ1, ZR1; B: YQ2 e encerramento de YQ1), a intencao PERDEDORA da janela 1 (f4279100-...-b1) nao gravou NENHUM evento em nenhuma organizacao e a insercao crua da janela 3 nao gravou linha nem trilha — autoria/membership do ator % em 100%% dos eventos', v_memb;
end $$;

-- ----------------------------------------------------------------------------
-- 3) Higiene do artefato temporario da sessao A e fechamento da prova
-- ----------------------------------------------------------------------------
do $$
declare
  v_n int;
begin
  if to_regclass('public._mut_f6_427_contencao_seq') is not null then
    raise exception '[FAIL] 59/higiene: sequence temporaria de contencao da sessao A (public._mut_f6_427_contencao_seq) NAO foi removida';
  end if;
  if to_regprocedure('public._mut_f6_427_contencao_marca()') is not null then
    raise exception '[FAIL] 59/higiene: funcao temporaria de contencao da sessao A (public._mut_f6_427_contencao_marca()) NAO foi removida';
  end if;
  select count(*) into v_n from pg_trigger t
   where t.tgrelid = 'public.occupations'::regclass
     and t.tgname = '_mut_f6_427_contencao';
  if v_n <> 0 then
    raise exception '[FAIL] 59/higiene: gatilho temporario de contencao da sessao A (public.occupations._mut_f6_427_contencao) NAO foi removido';
  end if;

  raise notice '[PASS] 59/higiene: nenhum residuo do artefato temporario de contencao da sessao A (sequence, funcao e gatilho)';
  raise notice '[PASS] validacao consolidada (59) da corrida F6-427: as tres janelas tiveram o veredito contratado (A vence a janela 1 com F5_07_CONFLICT para B; janela 2 SERIALIZADA pelo travamento da linha do colaborador com periodo consecutivo; janela 3 recusada pela exclusion POR COLABORADOR com 23P01), nenhum deadlock, zero par de ocupacoes sobrepostas por colaborador, exatamente UMA ocupacao ABERTA por colaborador (X em XP2, Y em YQ2, Z em ZR1), a intencao perdedora sem estado e sem trilha, o artefato temporario removido e a ORDEM CANONICA DE LOCKS intacta nas tres RPCs de ocupacao';
  raise notice 'Para reexecutar a prova e obrigatorio `supabase db reset --local` + fixtures + 57 (BACKGROUND) + `sleep 1` + 58 (FOREGROUND) + `wait` + 59 (as trilhas sao append-only e as ocupacoes sao historicas)';
end $$;
