-- ============================================================================
-- F5-10 P7 (Issue #232): CONCORRENCIA REAL entre DUAS sessoes PostgreSQL
-- SESSAO B (segundo processo psql; roda em FOREGROUND e PERDE as duas corridas)
-- ----------------------------------------------------------------------------
-- Papel desta sessao (processo psql 2 de 3):
--   FASE 1 — EDICAO: espera DETERMINISTICAMENTE a MARCA publicada pelo gatilho da
--     sessao A (sequence NAO transacional `_mut_p7_seq_edit`) e entao tenta a
--     MESMA edicao, no MESMO alvo, com o MESMO `expected_version = 0`, porem com
--     intencao DIVERGENTE (outra descricao e outro `operation_id`). B fica
--     BLOQUEADA no advisory lock normativo que A detem; quando A commita, B
--     adquire o lock, RELÊ a versao da meta (agora 1) e termina em
--     `F5_10_CONFLICT: versao divergente`. B exige tempo decorrido >= 2s: sem a
--     espera medida nao haveria contencao demonstrada.
--   FASE 2 — APROVACAO: espera a MARCA de `_mut_p7_seq_apr` e tenta aprovar o
--     MESMO papel (GERENTE) da meta de aprovacao, com outro `operation_id`. Como a
--     aprovacao NAO altera `version` da meta (D2/D3), o `expected_version` de B
--     continua valido: o que reprova B e a regra "uma unica aprovacao VIGENTE por
--     (meta, papel)", avaliada SO depois do lock — B termina em
--     `F5_10_CONFLICT: ja existe aprovacao vigente do papel GERENTE para a meta`.
--   FASE 3 — PAPEIS DISTINTOS (contraparte POSITIVA): com o lock ja livre, o
--     COORDENADOR congelado aprova a MESMA meta. Os dois fatos coexistem (um
--     vigente por papel) e o fato de A NAO se perde.
--
-- O que esta sessao NAO faz: nao usa `dblink`/`postgres_fdw`, nao cria objeto de
-- produto, nao remove os artefatos temporarios (higiene e do consolidador 33) e
-- nao "afrouxa" a prova (se a marca nao aparecer em ~30s, falha ALTO).
--
-- `operation_id` desta sessao (distintos dos de A e entre si):
--   meta_editar   -> e8b10000-0000-0000-0000-0000000000b1  (perdedora)
--   meta_aprovar  -> e8b10000-0000-0000-0000-0000000000b2  (perdedora)
--   meta_aprovar  -> e8b10000-0000-0000-0000-0000000000b3  (COORDENADOR, positiva)
-- ============================================================================

\set ON_ERROR_STOP on

set statement_timeout = 0;
set lock_timeout = 0;
-- Sessao B depende de um snapshot POR COMANDO para reler a versao commitada por A
-- depois de adquirir o lock: READ COMMITTED (nivel default do Supabase).
set default_transaction_isolation = 'read committed';

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg   uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_ger  uuid := 'e8c00000-0000-0000-0000-0000000000a2';
  v_coo  uuid := 'e8c00000-0000-0000-0000-0000000000a3';
begin
  if not exists (select 1 from public.organizations o where o.id = v_gama) then
    raise exception '[FAIL] pre-condicao B: organizacao Gama-P7 ausente — execute 29-cenario-f5-10-p7.sql';
  end if;
  if not exists (select 1 from public.evaluation_cycles c
                  where c.id = v_cg and c.organization_id = v_gama and c.status = 'ATIVO') then
    raise exception '[FAIL] pre-condicao B: ciclo ATIVO 2041/1 de Gama-P7 ausente';
  end if;
  if not public.f5_10_ator_valido_meta(v_ger, v_gama, 'goal.approve') then
    raise exception '[FAIL] pre-condicao B: gerente-gama sem goal.approve efetivo';
  end if;
  if not public.f5_10_ator_valido_meta(v_coo, v_gama, 'goal.approve') then
    raise exception '[FAIL] pre-condicao B: coordenador-gama sem goal.approve efetivo';
  end if;
  raise notice '[PASS] pre-condicoes da sessao B: Gama-P7, ciclo ATIVO 2041/1 e os dois papeis congelados com goal.approve';
end $$;

-- ----------------------------------------------------------------------------
-- 1) FASE 1 — espera DETERMINISTICA + EDICAO perdedora
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama    uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg      uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_ator    uuid := 'e8c00000-0000-0000-0000-0000000000a1';
  v_alvo    uuid;
  v_pronto  boolean := false;
  v_called  boolean;
  v_i       int;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_seg     numeric;
  v_ok      boolean;
  v_msg     text;
  v_desc    text;
  v_versao  int;
begin
  -- A UNICA coordenacao entre as sessoes: o alvo tem de existir E a MARCA do
  -- gatilho de A tem de estar publicada (marca = A ja esta DENTRO do UPDATE, com o
  -- lock da organizacao em maos). Isso elimina a corrida de "quem pega o lock
  -- primeiro" e torna a prova deterministica.
  for v_i in 1..120 loop
    v_pronto := false;
    if to_regclass('public._mut_p7_seq_edit') is not null then
      begin
        execute 'select s.is_called from public._mut_p7_seq_edit s' into v_called;
      exception when others then v_called := false;
      end;
      if v_called then
        select g.id into v_alvo
          from public.evaluation_goals g
         where g.organization_id = v_gama and g.cycle_id = v_cg
           and g.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a1'
           and g.tipo = 'NEGOCIO_PROJETO';
        if v_alvo is not null then
          v_pronto := true;
        end if;
      end if;
    end if;
    exit when v_pronto;
    perform pg_sleep(0.25);
  end loop;
  if not v_pronto then
    raise exception '[FAIL] sessoes A/B: a marca de contencao da EDICAO nao foi publicada em ~30s — a corrida nao chegou a ocorrer (a sessao A precisa estar rodando em BACKGROUND e ter criado a meta da corrida)';
  end if;

  raise notice 'sessao B: marca da EDICAO publicada — tentando meta_editar com expected_version = 0 (MESMO alvo e MESMA versao de A, intencao DIVERGENTE); o bloqueio no lock da organizacao comeca aqui';
  v_ini := clock_timestamp();
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_alvo, v_gama,
      'Descricao PERDEDORA da corrida de edicao (P7)',
      'KPI PERDEDOR da corrida de edicao (P7)',
      '999 unidades (P7)', 0, v_ator,
      'e8b10000-0000-0000-0000-0000000000b1');
  exception when others then v_ok := true; v_msg := sqlerrm;
  end;
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  if not v_ok then
    raise exception '[FAIL] B/edicao: a intencao perdedora deveria ter sido RECUSADA (nenhum erro recebido)';
  end if;
  if v_msg not like '%F5_10_CONFLICT%' or v_msg not like '%versao divergente%' then
    raise exception '[FAIL] B/edicao: esperado F5_10_CONFLICT de versao divergente, recebido: %', v_msg;
  end if;
  -- PROVA DE CONTENCAO: sem a espera no lock nao haveria contencao demonstrada.
  if v_seg < 2.0 then
    raise exception '[FAIL] B/edicao: a tentativa perdedora durou apenas % segundos (< 2s) — isso NAO prova contencao server-side; verifique a janela do pg_sleep da sessao A',
      round(v_seg, 3);
  end if;

  -- Nenhum efeito da intencao perdedora.
  select g.descricao, g.version into v_desc, v_versao
    from public.evaluation_goals g where g.id = v_alvo;
  if v_desc <> 'Descricao VENCEDORA da corrida de edicao (P7)' or v_versao <> 1 then
    raise exception '[FAIL] B/edicao: LOST UPDATE detectado — a meta deveria manter a intencao de A (descricao=%, version=%)',
      v_desc, v_versao;
  end if;
  if exists (select 1 from public.evaluation_goal_events e
              where e.organization_id = v_gama
                and e.operation_id = 'e8b10000-0000-0000-0000-0000000000b1') then
    raise exception '[FAIL] B/edicao: a intencao perdedora NAO pode gravar evento na trilha';
  end if;

  raise notice '[PASS] sessao B: FASE 1 (EDICAO) — a tentativa perdedora BLOQUEOU no lock da organizacao por ~% segundos e terminou em F5_10_CONFLICT de versao divergente; o estado final e o de A (descricao de A, version 1) e ZERO efeito de B',
    round(v_seg, 3);
end $$;

-- ----------------------------------------------------------------------------
-- 2) FASE 2 — espera DETERMINISTICA + APROVACAO perdedora (MESMO papel)
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama    uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg      uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_ger     uuid := 'e8c00000-0000-0000-0000-0000000000a2';
  v_alvo    uuid;
  v_pronto  boolean := false;
  v_called  boolean;
  v_i       int;
  v_ini     timestamptz;
  v_fim     timestamptz;
  v_seg     numeric;
  v_ok      boolean;
  v_msg     text;
  v_n       int;
begin
  for v_i in 1..120 loop
    v_pronto := false;
    if to_regclass('public._mut_p7_seq_apr') is not null then
      begin
        execute 'select s.is_called from public._mut_p7_seq_apr s' into v_called;
      exception when others then v_called := false;
      end;
      if v_called then
        select g.id into v_alvo
          from public.evaluation_goals g
         where g.organization_id = v_gama and g.cycle_id = v_cg
           and g.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a1'
           and g.tipo = 'INDIVIDUAL';
        if v_alvo is not null then
          v_pronto := true;
        end if;
      end if;
    end if;
    exit when v_pronto;
    perform pg_sleep(0.25);
  end loop;
  if not v_pronto then
    raise exception '[FAIL] sessoes A/B: a marca de contencao da APROVACAO nao foi publicada em ~30s — verifique se a FASE 2 da sessao A executou';
  end if;

  raise notice 'sessao B: marca da APROVACAO publicada — tentando meta_aprovar (GERENTE) com expected_version = 0; a aprovacao NAO altera a version da meta, entao o que reprova B e a regra de UMA vigente por papel, avaliada APOS o lock';
  v_ini := clock_timestamp();
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_alvo, v_gama, 'GERENTE',
      'Aprovacao PERDEDORA da corrida (P7)', 0, v_ger,
      'e8b10000-0000-0000-0000-0000000000b2');
  exception when others then v_ok := true; v_msg := sqlerrm;
  end;
  v_fim := clock_timestamp();
  v_seg := extract(epoch from (v_fim - v_ini));

  if not v_ok then
    raise exception '[FAIL] B/aprovacao: a intencao perdedora deveria ter sido RECUSADA (nenhum erro recebido)';
  end if;
  if v_msg not like '%F5_10_CONFLICT%' or v_msg not like '%ja existe aprovacao vigente%' then
    raise exception '[FAIL] B/aprovacao: esperado F5_10_CONFLICT de "ja existe aprovacao vigente", recebido: %', v_msg;
  end if;
  if v_seg < 2.0 then
    raise exception '[FAIL] B/aprovacao: a tentativa perdedora durou apenas % segundos (< 2s) — isso NAO prova contencao server-side',
      round(v_seg, 3);
  end if;

  -- Exatamente UM fato vigente de GERENTE (o de A) e nenhum evento de B.
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_alvo
     and a.papel = 'GERENTE' and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] B/aprovacao: deveria existir exatamente 1 GERENTE vigente (o de A) (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_alvo;
  if v_n <> 1 then
    raise exception '[FAIL] B/aprovacao: a tentativa perdedora NAO pode criar FATO de aprovacao (%)', v_n;
  end if;
  if exists (select 1 from public.evaluation_goal_events e
              where e.organization_id = v_gama
                and e.operation_id = 'e8b10000-0000-0000-0000-0000000000b2') then
    raise exception '[FAIL] B/aprovacao: a intencao perdedora NAO pode gravar evento na trilha';
  end if;

  raise notice '[PASS] sessao B: FASE 2 (APROVACAO, MESMO papel) — a tentativa perdedora BLOQUEOU no lock da organizacao por ~% segundos e terminou em F5_10_CONFLICT de "ja existe aprovacao vigente"; ZERO fato e ZERO evento de B',
    round(v_seg, 3);
end $$;

-- ----------------------------------------------------------------------------
-- 3) FASE 3 — PAPEIS DISTINTOS: os DOIS fatos coexistem (contraparte positiva)
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg   uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_coo  uuid := 'e8c00000-0000-0000-0000-0000000000a3';
  v_alvo uuid;
  v_res  jsonb;
  v_n    int;
begin
  select g.id into v_alvo
    from public.evaluation_goals g
   where g.organization_id = v_gama and g.cycle_id = v_cg
     and g.collaborator_id = 'e8b00000-0000-0000-0000-0000000000a1'
     and g.tipo = 'INDIVIDUAL';
  if v_alvo is null then
    raise exception '[FAIL] B/papeis distintos: meta da corrida de APROVACAO ausente';
  end if;

  v_res := public.meta_aprovar(v_alvo, v_gama, 'COORDENADOR',
    'Aprovacao do COORDENADOR congelado (P7)', 0, v_coo,
    'e8b10000-0000-0000-0000-0000000000b3');
  if (v_res->>'aprovado')::boolean is not true or (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] B/papeis distintos: a aprovacao do COORDENADOR deveria ser efetiva com a version da meta INTACTA (%)', v_res;
  end if;

  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_alvo and a.revogado_em is null;
  if v_n <> 2 then
    raise exception '[FAIL] B/papeis distintos: esperados 2 fatos VIGENTES (GERENTE de A + COORDENADOR de B), encontrados %', v_n;
  end if;
  select count(*) into v_n from (
    select a.papel from public.evaluation_goal_approvals a
     where a.organization_id = v_gama and a.goal_id = v_alvo and a.revogado_em is null
     group by a.papel having count(*) > 1) t;
  if v_n <> 0 then
    raise exception '[FAIL] B/papeis distintos: mais de uma vigente para o mesmo papel (%)', v_n;
  end if;
  -- O fato de A permanece intacto (nenhum lost update na aprovacao).
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_alvo
     and a.papel = 'GERENTE' and a.revogado_em is null
     and a.actor_user_profile_id = 'e8c00000-0000-0000-0000-0000000000a2';
  if v_n <> 1 then
    raise exception '[FAIL] B/papeis distintos: o fato de A (GERENTE) deveria permanecer vigente e com a MESMA autoria (%)', v_n;
  end if;

  raise notice '[PASS] sessao B: FASE 3 (PAPEIS DISTINTOS) — o COORDENADOR congelado aprovou a MESMA meta apos o lock ser liberado; os 2 fatos coexistem (1 vigente por papel), o fato de A permanece com a mesma autoria e nenhuma escrita se perdeu';
end $$;
