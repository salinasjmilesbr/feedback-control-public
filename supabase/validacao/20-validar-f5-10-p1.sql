-- ============================================================================
-- F5-10 P1 (Issue #210): validacao automatizada do SCHEMA/INTEGRIDADE/LIMITES
-- das metas soberanas (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (migrations)
--   2) `19-cenario-f5-10-p1.sql` (fixture isolada `ee`)
--   3) este arquivo             (asserts `[PASS]`/`[FAIL]`)
--
-- Contrato coberto (docs/F5-10-desenho-tecnico.md D1-D25):
--   A  pre-condicoes: fixture, 4 tabelas, RLS ligada, ZERO policy (deny-by-default);
--   B  shape das tabelas (colunas do contrato, defaults, `version`, timestamps);
--   C  isolamento cross-tenant ESTRUTURAL (FKs compostas) - 4 probes negativos;
--   D  constraints de dominio (progresso 0..100, tipo, status, fechamento
--      COERENTE - aceite dos dois estados finais e negativos de todas as
--      combinacoes contraditorias -, textos, exclusao logica, version) e
--      AUTORIA da aprovacao (ausente 23502, inexistente 23503, incoerente P0001);
--   E  quota soberana (D20/D21): limite respeitado, tipo sem quota recusado,
--      reducao abaixo das vivas recusada, DELETE de quota recusado,
--      reativacao de meta excluida que estouraria a quota recusada;
--   F  unicidade parcial (meta viva por ciclo/dono/tipo; aprovacao vigente por papel)
--      e idempotencia por (organization_id, operation_id) na trilha;
--   G  soft delete NAO e DELETE fisico (ACL nega DELETE; a linha permanece);
--   H  trilha APPEND-ONLY: UPDATE/DELETE/TRUNCATE negados inclusive ao owner;
--   I  payload_hash/event_type/entity_type e FK composta da trilha - negativos;
--   J  RLS/ACL: nenhum privilegio a authenticated/anon, service_role sem
--      DELETE/TRUNCATE, e SELECT do cliente NEGADO por permissao;
--   K  anti-escopo da P1: nenhuma RPC `meta_*`/`goal_*` e nenhuma capability nova;
--   L  estado final coerente (nenhum residuo dos testes negativos).
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer falha aborta.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- A) Pre-condicoes
-- ----------------------------------------------------------------------------
do $$
declare
  v_tab text;
  v_n   int;
begin
  select count(*) into v_n from public.evaluation_cycles
   where id in ('eed10000-0000-0000-0000-0000000000a1',
                'eed10000-0000-0000-0000-0000000000b1');
  if v_n <> 2 then
    raise exception '[FAIL] pre-condicao: fixture F5-10 P1 ausente (ciclos=%) — execute 19-cenario-f5-10-p1.sql', v_n;
  end if;

  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relkind = 'r' and c.relrowsecurity
    ) then
      raise exception '[FAIL] pre-condicao: tabela % ausente ou sem RLS', v_tab;
    end if;
  end loop;

  select count(*) into v_n from pg_policies p
   where p.schemaname = 'public'
     and p.tablename in ('evaluation_goals', 'evaluation_goal_approvals',
                         'evaluation_goal_events', 'evaluation_cycle_goal_limits');
  if v_n <> 0 then
    raise exception '[FAIL] pre-condicao: P1 exige ZERO policy nas tabelas de metas (encontradas %)', v_n;
  end if;

  raise notice '[PASS] A: fixture presente, 4 tabelas com RLS ligada e ZERO policy (deny-by-default integral)';
end $$;

-- ----------------------------------------------------------------------------
-- B) Shape das tabelas (colunas do contrato)
-- ----------------------------------------------------------------------------
do $$
declare
  v_falta text[] := array[]::text[];
  v_par   record;
begin
  for v_par in
    select * from (values
      ('evaluation_goals', array['id','organization_id','cycle_id','collaborator_id',
        'tipo','descricao','kpi','valor_alvo','status','resultado_atual',
        'progresso_percentual','data_ultimo_acompanhamento','resultado_final',
        'atingida','data_fechamento','excluida','data_exclusao','version',
        'created_at','updated_at']),
      ('evaluation_cycle_goal_limits', array['id','organization_id','cycle_id','tipo',
        'quantidade','version','created_at','updated_at']),
      ('evaluation_goal_approvals', array['id','organization_id','goal_id','papel',
        'actor_user_profile_id','actor_membership_id','decidido_em','motivo',
        'revogado_em','revogado_motivo',
        'version','created_at','updated_at']),
      ('evaluation_goal_events', array['id','organization_id','goal_id','entity_type',
        'event_type','effective_date','reason','before_value','after_value',
        'payload_hash','result_entity_id','actor_user_profile_id','actor_membership_id',
        'operation_id','created_at'])
    ) as t(tabela, colunas)
  loop
    declare v_col text;
    begin
      foreach v_col in array v_par.colunas loop
        if not exists (
          select 1 from information_schema.columns c
           where c.table_schema = 'public' and c.table_name = v_par.tabela
             and c.column_name = v_col
        ) then
          v_falta := v_falta || format('%s.%s', v_par.tabela, v_col);
        end if;
      end loop;
    end;
  end loop;

  if array_length(v_falta, 1) is not null then
    raise exception '[FAIL] B: colunas do contrato ausentes: %', array_to_string(v_falta, ', ');
  end if;

  -- `id` e uuid com default soberano; `version` inteiro com default 0.
  if not exists (
    select 1 from information_schema.columns c
     where c.table_schema='public' and c.table_name='evaluation_goals'
       and c.column_name='id' and c.data_type='uuid' and c.column_default is not null
  ) then
    raise exception '[FAIL] B: evaluation_goals.id deveria ser uuid com default do banco';
  end if;
  if not exists (
    select 1 from information_schema.columns c
     where c.table_schema='public' and c.table_name='evaluation_goals'
       and c.column_name='version' and c.data_type='integer' and c.column_default = '0'
  ) then
    raise exception '[FAIL] B: evaluation_goals.version deveria ser integer default 0';
  end if;
  -- progresso e INTEIRO (D16), nunca numeric.
  if not exists (
    select 1 from information_schema.columns c
     where c.table_schema='public' and c.table_name='evaluation_goals'
       and c.column_name='progresso_percentual' and c.data_type='integer'
  ) then
    raise exception '[FAIL] B: progresso_percentual deveria ser integer (D16)';
  end if;

  raise notice '[PASS] B: shape conforme o contrato (20+8+13+15 colunas, autoria da aprovacao com perfil E membership), id uuid com default soberano, version default 0 e progresso integer';
end $$;

-- ----------------------------------------------------------------------------
-- C) Isolamento cross-tenant ESTRUTURAL (FKs compostas) - probes negativos
-- ----------------------------------------------------------------------------
do $$
declare
  v_ok boolean;
  v_st text;
begin
  -- (1)+(2) metas cross-tenant. O trigger de QUOTA e BEFORE INSERT e dispara
  -- antes das FKs (prova fail-closed por outro motivo). Para provar a FK
  -- COMPOSTA em si, o trigger de quota e desabilitado APENAS durante os dois
  -- probes e reabilitado em seguida (com verificacao de que voltou).
  alter table public.evaluation_goals disable trigger trg_evaluation_goals_quota;

  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values ('eea00000-0000-0000-0000-0000000000b1',
            'eed10000-0000-0000-0000-0000000000a1',
            'eeb00000-0000-0000-0000-0000000000b1',
            'NEGOCIO_PROJETO', 'probe cross-tenant', 'kpi', 'alvo');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23503' then
    raise exception '[FAIL] C1: meta com ciclo de outro tenant deveria violar FK composta (23503), veio %', v_st;
  end if;

  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values ('eea00000-0000-0000-0000-0000000000a1',
            'eed10000-0000-0000-0000-0000000000a1',
            'eeb00000-0000-0000-0000-0000000000b1',
            'NEGOCIO_PROJETO', 'probe cross-tenant', 'kpi', 'alvo');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23503' then
    raise exception '[FAIL] C2: meta com colaborador de outro tenant deveria violar FK composta (23503), veio %', v_st;
  end if;

  alter table public.evaluation_goals enable trigger trg_evaluation_goals_quota;

  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_goals'::regclass
       and t.tgname = 'trg_evaluation_goals_quota' and t.tgenabled <> 'D'
  ) then
    raise exception '[FAIL] C2: o trigger de quota nao foi reabilitado apos os probes';
  end if;

  -- (3) aprovacao de meta de OUTRO tenant.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goal_approvals
      (organization_id, goal_id, papel, actor_user_profile_id, actor_membership_id)
    values ('eea00000-0000-0000-0000-0000000000b1',
            'ee900000-0000-0000-0000-000000000001', 'GERENTE',
            'eec00000-0000-0000-0000-000000000002',
            'eed00000-0000-0000-0000-000000000002');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23503' then
    raise exception '[FAIL] C3: aprovacao com tenant divergente da meta deveria violar FK composta (23503), veio %', v_st;
  end if;

  -- (4) evento de meta de OUTRO tenant.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goal_events
      (organization_id, goal_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('eea00000-0000-0000-0000-0000000000b1',
            'ee900000-0000-0000-0000-000000000001', 'evaluation_goal', 'EDITADA', now(),
            repeat('a', 64), 'eec00000-0000-0000-0000-000000000002',
            'eed00000-0000-0000-0000-000000000002',
            'ee600000-0000-0000-0000-0000000000c1');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23503' then
    raise exception '[FAIL] C4: evento com tenant divergente da meta deveria violar FK composta (23503), veio %', v_st;
  end if;

  -- (5) quota com ciclo de OUTRO tenant. Usa uma combinacao (cycle_id, tipo)
  --     ainda LIVRE para que a recusa venha da FK composta (e nao da unicidade).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_cycle_goal_limits
      (organization_id, cycle_id, tipo, quantidade)
    values ('eea00000-0000-0000-0000-0000000000a1',
            'eed10000-0000-0000-0000-0000000000b1', 'INDIVIDUAL', 1);
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23503' then
    raise exception '[FAIL] C5: quota com ciclo de outro tenant deveria violar FK composta (23503), veio %', v_st;
  end if;

  raise notice '[PASS] C: 5 probes cross-tenant recusados por FK COMPOSTA (isolamento estrutural, nao apenas de aplicacao)';
end $$;

-- ----------------------------------------------------------------------------
-- D) Constraints de dominio - negativos
-- ----------------------------------------------------------------------------
do $$
declare
  v_ok boolean;
  v_st text;
  v_org uuid := 'eea00000-0000-0000-0000-0000000000a1';
  v_cyc uuid := 'eed10000-0000-0000-0000-0000000000a1';
  v_col uuid := 'eeb00000-0000-0000-0000-000000000002';
  v_tipo text := 'INDIVIDUAL';
begin
  -- O trigger de QUOTA e BEFORE INSERT e dispara antes dos CHECKs de dominio
  -- (fail-closed por outro motivo). Ele e desabilitado APENAS neste bloco, que
  -- prova o DOMINIO, e reabilitado ao final com verificacao.
  alter table public.evaluation_goals disable trigger trg_evaluation_goals_quota;

  -- (D1) progresso negativo e acima de 100.
  foreach v_st in array array['-1', '101', '999'] loop
    v_ok := false;
    begin
      execute format(
        'insert into public.evaluation_goals (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo, progresso_percentual) values (%L, %L, %L, %L, %L, %L, %L, %s)',
        v_org, v_cyc, v_col, v_tipo, 'probe progresso', 'kpi', 'alvo', v_st);
    exception when others then v_ok := true;
    end;
    if not v_ok then
      raise exception '[FAIL] D1: progresso % deveria ser recusado (0..100)', v_st;
    end if;
  end loop;

  -- (D2) tipo invalido.
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_org, v_cyc, v_col, 'EQUIPE', 'probe tipo', 'kpi', 'alvo');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D2: tipo invalido deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D3) status invalido.
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo, status)
    values (v_org, v_cyc, v_col, v_tipo, 'probe status', 'kpi', 'alvo', 'PENDENTE');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D3: status invalido deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D4) fechamento incoerente: status final sem resultado_final/atingida/data.
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo, status)
    values (v_org, v_cyc, v_col, v_tipo, 'probe fechamento', 'kpi', 'alvo', 'ATINGIDA');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D4: status final sem fechamento completo deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D5) textos vazios/brancos.
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_org, v_cyc, v_col, v_tipo, '   ', 'kpi', 'alvo');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D5: descricao em branco deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D6) exclusao logica incoerente (excluida sem data_exclusao).
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo, excluida)
    values (v_org, v_cyc, v_col, v_tipo, 'probe exclusao', 'kpi', 'alvo', true);
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D6: excluida=true sem data_exclusao deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D7) version negativa.
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo, version)
    values (v_org, v_cyc, v_col, v_tipo, 'probe version', 'kpi', 'alvo', -1);
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D7: version negativa deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D8) papel de aprovacao invalido.
  v_ok := false;
  begin
    insert into public.evaluation_goal_approvals
      (organization_id, goal_id, papel, actor_user_profile_id, actor_membership_id)
    values (v_org, 'ee900000-0000-0000-0000-000000000001', 'DIRETOR',
            'eec00000-0000-0000-0000-000000000001',
            'eed00000-0000-0000-0000-000000000001');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D8: papel de aprovacao invalido deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- --------------------------------------------------------------------------
  -- D-DEZ) FECHAMENTO COERENTE (D17 endurecido na correcao pos-auditoria).
  -- Negativos explicitos de TODAS as combinacoes contraditorias e aceite dos
  -- dois estados finais legitimos.
  -- --------------------------------------------------------------------------

  -- (D10) Aceite: fechamento COERENTE e valido. O probe e desfeito por excecao
  -- sentinela dentro da propria subtransacao, para nao deixar residuo (o bloco L
  -- valida o estado final do cenario).
  declare
    v_fech text;
    v_msg  text;
  begin
    foreach v_fech in array array['ATINGIDA', 'NAO_ATINGIDA'] loop
      v_ok := false;
      v_msg := null;
      begin
        insert into public.evaluation_goals
          (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi,
           valor_alvo, status, resultado_final, atingida, data_fechamento)
        values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe aceite ' || v_fech,
                'kpi', 'alvo', v_fech, 'resultado final do probe',
                v_fech = 'ATINGIDA', now());
        raise exception 'f5-10-probe-rollback';
      exception when others then
        if sqlerrm = 'f5-10-probe-rollback' then
          v_ok := true;
        else
          v_msg := sqlstate;
        end if;
      end;
      if not v_ok then
        raise exception '[FAIL] D10: fechamento coerente (%) deveria ser aceito, veio %',
          v_fech, coalesce(v_msg, 'sem erro');
      end if;
    end loop;
  end;

  -- (D11) EM_ANDAMENTO com resultado_final preenchido.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe andamento resultado', 'kpi',
            'alvo', 'EM_ANDAMENTO', 'resultado indevido');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D11: EM_ANDAMENTO com resultado_final deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D12) EM_ANDAMENTO com atingida preenchido.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, atingida)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe andamento atingida', 'kpi',
            'alvo', 'EM_ANDAMENTO', true);
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D12: EM_ANDAMENTO com atingida deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D13) EM_ANDAMENTO com data_fechamento preenchida.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe andamento data', 'kpi',
            'alvo', 'EM_ANDAMENTO', now());
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D13: EM_ANDAMENTO com data_fechamento deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D14) ATINGIDA com atingida = false (contradicao direta).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final, atingida, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe atingida falsa', 'kpi',
            'alvo', 'ATINGIDA', 'resultado final', false, now());
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D14: ATINGIDA com atingida=false deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D15) ATINGIDA sem resultado_final.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final, atingida, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe atingida sem resultado',
            'kpi', 'alvo', 'ATINGIDA', null, true, now());
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D15: ATINGIDA sem resultado_final deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D16) ATINGIDA sem data_fechamento.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final, atingida, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe atingida sem data', 'kpi',
            'alvo', 'ATINGIDA', 'resultado final', true, null);
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D16: ATINGIDA sem data_fechamento deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D17) ATINGIDA com resultado_final em branco.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final, atingida, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe atingida branco', 'kpi',
            'alvo', 'ATINGIDA', '   ', true, now());
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D17: ATINGIDA com resultado_final em branco deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D18) ATINGIDA com resultado_final com espacos nas bordas (tem de ser = btrim()).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final, atingida, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe atingida bordas', 'kpi',
            'alvo', 'ATINGIDA', '  resultado com bordas  ', true, now());
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D18: resultado_final com bordas deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D19) NAO_ATINGIDA com atingida = true (contradicao direta).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final, atingida, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe nao atingida verdadeira',
            'kpi', 'alvo', 'NAO_ATINGIDA', 'resultado final', true, now());
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D19: NAO_ATINGIDA com atingida=true deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D20) NAO_ATINGIDA sem resultado_final.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final, atingida, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe nao atingida sem res',
            'kpi', 'alvo', 'NAO_ATINGIDA', null, false, now());
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D20: NAO_ATINGIDA sem resultado_final deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D21) NAO_ATINGIDA sem data_fechamento.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, resultado_final, atingida, data_fechamento)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe nao atingida sem data',
            'kpi', 'alvo', 'NAO_ATINGIDA', 'resultado final', false, null);
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D21: NAO_ATINGIDA sem data_fechamento deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (D22) status final com o fechamento INTEIRO ausente (completude, D4 acima) e
  -- ainda com `excluida` coerente: garante que o CHECK unico cobre os dois eixos.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
       status, excluida, data_exclusao)
    values (v_org, v_cyc, v_col, 'NEGOCIO_PROJETO', 'probe nao atingida incompleta',
            'kpi', 'alvo', 'NAO_ATINGIDA', false, null);
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] D22: NAO_ATINGIDA sem fechamento deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- --------------------------------------------------------------------------
  -- D-AUTORIA) AUTORIA SOBERANA da aprovacao (D2/§9.3, correcao pos-auditoria):
  -- actor_user_profile_id + actor_membership_id, com codigos de erro distintos
  -- por classe de defeito (23502 ausente, 23503 inexistente, P0001 incoerente).
  -- --------------------------------------------------------------------------

  -- (D23) aprovacao SEM actor_user_profile_id: NOT NULL (23502).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goal_approvals
      (organization_id, goal_id, papel, actor_membership_id)
    values (v_org, 'ee900000-0000-0000-0000-000000000001', 'GERENTE',
            'eed00000-0000-0000-0000-000000000001');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23502' then
    raise exception '[FAIL] D23: aprovacao sem actor_user_profile_id deveria violar NOT NULL (23502), veio %', v_st;
  end if;

  -- (D24) aprovacao com perfil INEXISTENTE: FK de perfil (23503).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goal_approvals
      (organization_id, goal_id, papel, actor_user_profile_id, actor_membership_id)
    values (v_org, 'ee900000-0000-0000-0000-000000000001', 'GERENTE',
            'ee000000-0000-0000-0000-0000000000ff',
            'eed00000-0000-0000-0000-000000000001');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23503' then
    raise exception '[FAIL] D24: perfil inexistente deveria violar FK (23503), veio %', v_st;
  end if;

  -- (D25) aprovacao com perfil EXISTENTE, porem de outra membership/tenant:
  -- invariante de coerencia fail-closed (P0001).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_goal_approvals
      (organization_id, goal_id, papel, actor_user_profile_id, actor_membership_id)
    values (v_org, 'ee900000-0000-0000-0000-000000000001', 'GERENTE',
            'eec00000-0000-0000-0000-000000000002',
            'eed00000-0000-0000-0000-000000000001');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> 'P0001' then
    raise exception '[FAIL] D25: perfil incoerente com a membership deveria violar a coerencia de autoria (P0001), veio %', v_st;
  end if;

  alter table public.evaluation_goals enable trigger trg_evaluation_goals_quota;

  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_goals'::regclass
       and t.tgname = 'trg_evaluation_goals_quota' and t.tgenabled <> 'D'
  ) then
    raise exception '[FAIL] D9: o trigger de quota nao foi reabilitado apos os probes de dominio';
  end if;

  raise notice '[PASS] D: dominio recusado no banco (progresso <0/>100/999, tipo, status, texto branco, exclusao incoerente, version negativa, papel de aprovacao, 13 estados de fechamento invalidos recusados e os dois fechamentos coerentes aceitos, autoria da aprovacao: ausente 23502 / inexistente 23503 / incoerente P0001)';
end $$;

-- ----------------------------------------------------------------------------
-- E) QUOTA soberana (D20/D21) - positivos e negativos
-- ----------------------------------------------------------------------------
do $$
declare
  v_ok boolean;
  v_st text;
  v_org uuid := 'eea00000-0000-0000-0000-0000000000a1';
  v_cyc uuid := 'eed10000-0000-0000-0000-0000000000a1';
  v_novo uuid := 'eeb00000-0000-0000-0000-000000000003';
  v_n int;
begin
  -- Colaborador adicional (fixture do teste de quota: precisa de uma terceira
  -- tupla (ciclo, dono, tipo) para exceder o limite sem colidir na unicidade).
  insert into public.collaborators (id, organization_id) values (v_novo, v_org)
  on conflict (id) do nothing;

  -- (E1) dentro do limite: 2a meta NEGOCIO_PROJETO em Alfa (limite 2) => aceita.
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_org, v_cyc, 'eeb00000-0000-0000-0000-000000000002',
            'NEGOCIO_PROJETO', '2a meta de negocio (quota)', 'kpi', 'alvo');
    v_ok := true;
  exception when others then v_ok := false; v_st := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] E1: meta dentro do limite deveria ser aceita (%)', v_st;
  end if;

  -- (E2) acima do limite: 3a meta NEGOCIO_PROJETO em Alfa => recusada.
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_org, v_cyc, v_novo, 'NEGOCIO_PROJETO', '3a meta (estoura quota)', 'kpi', 'alvo');
  exception when others then v_ok := true; v_st := sqlerrm;
  end;
  if not v_ok or v_st not like '%quota de metas%' then
    raise exception '[FAIL] E2: meta acima do limite deveria ser recusada pela quota (%)', v_st;
  end if;

  -- (E3) tipo SEM quota configurada (fail-closed) => recusada.
  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values ('eea00000-0000-0000-0000-0000000000b1',
            'eed10000-0000-0000-0000-0000000000b1',
            'eeb00000-0000-0000-0000-0000000000b1',
            'INDIVIDUAL', 'INDIVIDUAL sem quota no Beta', 'kpi', 'alvo');
  exception when others then v_ok := true; v_st := sqlerrm;
  end;
  if not v_ok or v_st not like '%nao configurada%' then
    raise exception '[FAIL] E3: tipo sem quota deveria ser recusado fail-closed (%)', v_st;
  end if;

  -- (E4) reduzir a quota abaixo das vivas => recusado.
  v_ok := false;
  begin
    update public.evaluation_cycle_goal_limits
       set quantidade = 1
     where organization_id = v_org and cycle_id = v_cyc and tipo = 'NEGOCIO_PROJETO';
  exception when others then v_ok := true; v_st := sqlerrm;
  end;
  if not v_ok or v_st not like '%nao pode ser reduzida%' then
    raise exception '[FAIL] E4: quota abaixo das metas vivas deveria ser recusada (%)', v_st;
  end if;

  -- (E5) DELETE da linha de quota => recusado (zeraria a quota em silencio).
  v_ok := false;
  begin
    delete from public.evaluation_cycle_goal_limits
     where organization_id = v_org and cycle_id = v_cyc and tipo = 'INDIVIDUAL';
  exception when others then v_ok := true; v_st := sqlerrm;
  end;
  if not v_ok or v_st not like '%nao aceita DELETE%' then
    raise exception '[FAIL] E5: DELETE de quota deveria ser recusado (%)', v_st;
  end if;

  -- (E6) soft delete libera slot; reativar a meta antiga estourando a quota => recusado.
  update public.evaluation_goals
     set excluida = true, data_exclusao = now()
   where organization_id = v_org and cycle_id = v_cyc
     and collaborator_id = 'eeb00000-0000-0000-0000-000000000002'
     and tipo = 'NEGOCIO_PROJETO';
  insert into public.evaluation_goals
    (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
  values (v_org, v_cyc, 'eeb00000-0000-0000-0000-000000000002',
          'NEGOCIO_PROJETO', 'meta substituta apos soft delete', 'kpi', 'alvo');

  v_ok := false;
  begin
    update public.evaluation_goals
       set excluida = false, data_exclusao = null
     where organization_id = v_org and cycle_id = v_cyc
       and collaborator_id = 'eeb00000-0000-0000-0000-000000000002'
       and tipo = 'NEGOCIO_PROJETO' and excluida = true;
  exception when others then v_ok := true; v_st := sqlerrm;
  end;
  if not v_ok or v_st not like '%quota de metas%' then
    raise exception '[FAIL] E6: reativacao que estoura a quota deveria ser recusada (%)', v_st;
  end if;

  select count(*) into v_n from public.evaluation_goals
   where organization_id = v_org and cycle_id = v_cyc and tipo = 'NEGOCIO_PROJETO' and excluida = false;
  if v_n <> 2 then
    raise exception '[FAIL] E6: Alfa deveria ter 2 metas de negocio VIVAS apos o soft delete (encontradas %)', v_n;
  end if;

  raise notice '[PASS] E: quota soberana ativa — limite respeitado, tipo sem quota recusado (fail-closed), reducao abaixo das vivas recusada, DELETE de quota recusado e reativacao que estoura a quota recusada';
end $$;

-- ----------------------------------------------------------------------------
-- F) Unicidade parcial e idempotencia
-- ----------------------------------------------------------------------------
do $$
declare
  v_ok boolean;
  v_st text;
  v_org uuid := 'eea00000-0000-0000-0000-0000000000a1';
  v_cyc uuid := 'eed10000-0000-0000-0000-0000000000a1';
begin
  -- (F1) segunda meta VIVA com a mesma tupla => 23505.
  -- O trigger de quota e BEFORE INSERT e mascararia a unicidade parcial; ele e
  -- desabilitado APENAS neste probe e reabilitado em seguida com verificacao.
  alter table public.evaluation_goals disable trigger trg_evaluation_goals_quota;

  v_ok := false;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_org, v_cyc, 'eeb00000-0000-0000-0000-000000000001',
            'NEGOCIO_PROJETO', 'duplicata viva', 'kpi', 'alvo');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23505' then
    raise exception '[FAIL] F1: meta viva duplicada deveria violar unicidade parcial (23505), veio %', v_st;
  end if;

  alter table public.evaluation_goals enable trigger trg_evaluation_goals_quota;

  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_goals'::regclass
       and t.tgname = 'trg_evaluation_goals_quota' and t.tgenabled <> 'D'
  ) then
    raise exception '[FAIL] F1b: o trigger de quota nao foi reabilitado apos o probe de unicidade';
  end if;

  -- (F2) segunda aprovacao VIGENTE do mesmo papel => 23505.
  v_ok := false;
  begin
    insert into public.evaluation_goal_approvals
      (organization_id, goal_id, papel, actor_user_profile_id, actor_membership_id)
    values (v_org, 'ee900000-0000-0000-0000-000000000001', 'COORDENADOR',
            'eec00000-0000-0000-0000-000000000001',
            'eed00000-0000-0000-0000-000000000001');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23505' then
    raise exception '[FAIL] F2: aprovacao vigente duplicada deveria violar unicidade parcial (23505), veio %', v_st;
  end if;

  -- (F3) idempotencia: mesmo (organization_id, operation_id) na trilha => 23505.
  v_ok := false;
  begin
    insert into public.evaluation_goal_events
      (organization_id, goal_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, 'ee900000-0000-0000-0000-000000000001', 'evaluation_goal', 'EDITADA', now(),
            repeat('b', 64), 'eec00000-0000-0000-0000-000000000001',
            'eed00000-0000-0000-0000-000000000001',
            'ee600000-0000-0000-0000-000000000001');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23505' then
    raise exception '[FAIL] F3: operation_id repetido na trilha deveria violar unicidade (23505), veio %', v_st;
  end if;

  raise notice '[PASS] F: unicidade parcial da meta viva, da aprovacao vigente por papel e idempotencia (organization_id, operation_id) da trilha ativas';
end $$;

-- ----------------------------------------------------------------------------
-- G) Soft delete NAO e DELETE fisico
-- ----------------------------------------------------------------------------
do $$
declare
  v_antes int;
  v_depois int;
  v_ok boolean := false;
  v_st text;
begin
  select count(*) into v_antes from public.evaluation_goals
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1';

  -- (G1) `authenticated`/`anon` nao conseguem apagar (ACL) — provado em J.
  --      Aqui: DELETE direto NAO e o caminho: a linha excluida PERMANECE.
  select count(*) into v_depois from public.evaluation_goals
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1' and excluida = true;
  if v_depois < 1 then
    raise exception '[FAIL] G1: o soft delete deveria preservar a linha (nenhuma linha excluida encontrada)';
  end if;
  if v_antes <> 4 then
    raise exception '[FAIL] G1: contagem inesperada de metas em Alfa (%) apos os testes de quota', v_antes;
  end if;

  -- (G2) `service_role` NAO tem DELETE em evaluation_goals (ACL de primeira camada).
  set role service_role;
  begin
    delete from public.evaluation_goals
     where organization_id = 'eea00000-0000-0000-0000-0000000000a1' and excluida = true;
  exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  reset role;
  if not v_ok then
    raise exception '[FAIL] G2: service_role NAO deveria poder apagar meta (DELETE fisico), veio %', v_st;
  end if;

  select count(*) into v_depois from public.evaluation_goals
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1';
  if v_depois <> v_antes then
    raise exception '[FAIL] G2: DELETE negado alterou a contagem (% -> %)', v_antes, v_depois;
  end if;

  raise notice '[PASS] G: soft delete preserva a linha e DELETE fisico e negado por ACL — excluir meta nao e apagar';
end $$;

-- ----------------------------------------------------------------------------
-- H) Trilha APPEND-ONLY (inclusive para o owner)
-- ----------------------------------------------------------------------------
do $$
declare
  v_ok boolean;
  v_st text;
  v_evt uuid := 'ee700000-0000-0000-0000-000000000001';
begin
  -- (H1) UPDATE negado por trigger (o validador roda como owner).
  v_ok := false;
  begin
    update public.evaluation_goal_events set reason = 'tentativa' where id = v_evt;
  exception when others then v_ok := true; v_st := sqlerrm;
  end;
  if not v_ok or v_st not like '%append-only%' then
    raise exception '[FAIL] H1: UPDATE da trilha deveria ser negado pelo trigger (%)', v_st;
  end if;

  -- (H2) DELETE negado por trigger.
  v_ok := false;
  begin
    delete from public.evaluation_goal_events where id = v_evt;
  exception when others then v_ok := true; v_st := sqlerrm;
  end;
  if not v_ok or v_st not like '%append-only%' then
    raise exception '[FAIL] H2: DELETE da trilha deveria ser negado pelo trigger (%)', v_st;
  end if;

  -- (H3) TRUNCATE negado por trigger (statement-level).
  v_ok := false;
  begin
    truncate table public.evaluation_goal_events;
  exception when others then v_ok := true; v_st := sqlerrm;
  end;
  if not v_ok or v_st not like '%append-only%' then
    raise exception '[FAIL] H3: TRUNCATE da trilha deveria ser negado pelo trigger (%)', v_st;
  end if;

  if (select count(*) from public.evaluation_goal_events) <> 1 then
    raise exception '[FAIL] H3: a trilha deveria continuar com exatamente 1 evento';
  end if;

  raise notice '[PASS] H: trilha append-only — UPDATE, DELETE e TRUNCATE negados inclusive para o owner (2a camada, resistente a privilege drift)';
end $$;

-- ----------------------------------------------------------------------------
-- I) Trilha: dominio do contrato - negativos
-- ----------------------------------------------------------------------------
do $$
declare
  v_ok boolean;
  v_st text;
  v_org uuid := 'eea00000-0000-0000-0000-0000000000a1';
  v_goal uuid := 'ee900000-0000-0000-0000-000000000001';
begin
  -- (I1) payload_hash invalido.
  v_ok := false;
  begin
    insert into public.evaluation_goal_events
      (organization_id, goal_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, v_goal, 'evaluation_goal', 'EDITADA', now(), 'NAO-E-HEX',
            'eec00000-0000-0000-0000-000000000001',
            'eed00000-0000-0000-0000-000000000001',
            'ee600000-0000-0000-0000-0000000000c2');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] I1: payload_hash invalido deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (I2) event_type fora do contrato.
  v_ok := false;
  begin
    insert into public.evaluation_goal_events
      (organization_id, goal_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, v_goal, 'evaluation_goal', 'ARQUIVADA', now(), repeat('c', 64),
            'eec00000-0000-0000-0000-000000000001',
            'eed00000-0000-0000-0000-000000000001',
            'ee600000-0000-0000-0000-0000000000c3');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] I2: event_type fora do contrato deveria violar CHECK (23514), veio %', v_st;
  end if;

  -- (I3) entity_type diferente de evaluation_goal.
  v_ok := false;
  begin
    insert into public.evaluation_goal_events
      (organization_id, goal_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values (v_org, v_goal, 'evaluation_cycle', 'EDITADA', now(), repeat('d', 64),
            'eec00000-0000-0000-0000-000000000001',
            'eed00000-0000-0000-0000-000000000001',
            'ee600000-0000-0000-0000-0000000000c4');
  exception when others then v_ok := true; v_st := sqlstate;
  end;
  if not v_ok or v_st <> '23514' then
    raise exception '[FAIL] I3: entity_type deveria ser evaluation_goal (23514), veio %', v_st;
  end if;

  raise notice '[PASS] I: trilha recusa payload_hash fora do padrao, event_type fora do contrato e entity_type alheio ao dominio';
end $$;

-- ----------------------------------------------------------------------------
-- J) RLS e ACL (deny-by-default; service_role executor tecnico)
-- ----------------------------------------------------------------------------
do $$
declare
  v_tab text;
  v_ok  boolean;
  v_st  text;
begin
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('anon', format('public.%I', v_tab), 'SELECT') then
      raise exception '[FAIL] J1: % concede privilegio a authenticated/anon', v_tab;
    end if;
    if has_table_privilege('service_role', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('service_role', format('public.%I', v_tab), 'TRUNCATE') then
      raise exception '[FAIL] J1: % concede DELETE/TRUNCATE a service_role', v_tab;
    end if;
  end loop;

  -- (J2) cliente autenticado tentando ler metas: NEGADO por permissao (nao "zero linhas").
  v_ok := false;
  set role authenticated;
  begin
    perform count(*) from public.evaluation_goals;
  exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  reset role;
  if not v_ok then
    raise exception '[FAIL] J2: SELECT de authenticated em evaluation_goals deveria ser NEGADO (%), veio %', '42501', v_st;
  end if;

  raise notice '[PASS] J: RLS deny-by-default — nenhum privilegio a authenticated/anon, service_role sem DELETE/TRUNCATE e leitura do cliente NEGADA por permissao';
end $$;

-- ----------------------------------------------------------------------------
-- K) Anti-escopo da P1 (nenhuma RPC funcional ALEM do contrato das fases, nenhuma
--    capability nova)
-- ----------------------------------------------------------------------------
-- CORRECAO DE REGRESSAO (Issues #212 e #214, F5-10 P2/P3): a P1 nao implementa
-- NENHUMA RPC funcional de meta; as P2 e P3 rodam no MESMO `db reset` e
-- introduzem EXATAMENTE as 9 RPCs soberanas do contrato (§13/§19 P2 + P3,
-- incluindo D21). A guarda NAO foi enfraquecida: virou LISTA FECHADA — qualquer
-- outra funcao `meta_*`/`goal_*` (inclusive de fase futura: leitura com gate)
-- continua reprovando.
do $$
declare
  v_n int;
  v_caps int;
  v_rpcs text[] := array[
    'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
    'meta_revisar_finalizacao', 'meta_excluir', 'meta_definir_limites_do_ciclo',
    'meta_aprovar', 'meta_invalidar_aprovacoes'];
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%')
     and p.proname <> all (v_rpcs);
  if v_n <> 0 then
    raise exception '[FAIL] K1: RPC funcional de meta FORA do contrato das fases P1/P2/P3 (encontradas %)', v_n;
  end if;

  -- As 9 RPCs da P2+P3 existem de fato (a lista nao pode passar por vacuidade).
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = any (v_rpcs);
  if v_n <> 9 then
    raise exception '[FAIL] K1: as 9 RPCs soberanas da P2/P3 deveriam existir (encontradas %)', v_n;
  end if;

  select count(*) into v_caps from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_caps <> 8 then
    raise exception '[FAIL] K2: capabilities de metas/observacoes deveriam continuar 8 (nenhuma fase cria capability), encontradas %', v_caps;
  end if;

  -- As 5 funcoes introduzidas pela P1 sao apenas de INVARIANTE/append-only.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('f5_10_validar_quota_da_meta', 'f5_10_validar_quota_do_limite',
                       'f5_10_proteger_limite_do_ciclo',
                       'f5_10_validar_autoria_da_aprovacao',
                       'enforce_evaluation_goal_events_append_only');
  if v_n <> 5 then
    raise exception '[FAIL] K3: funcoes de integridade da P1 ausentes (encontradas %)', v_n;
  end if;

  raise notice '[PASS] K: anti-escopo respeitado — superficie de RPC de meta restrita a lista FECHADA das 9 operacoes das P2/P3 (incluindo D21/limites do ciclo e aprovacao/invalidacao), nenhuma capability nova e as 5 funcoes da P1 apenas de integridade/append-only';
end $$;

-- ----------------------------------------------------------------------------
-- L) Estado final coerente (nenhum residuo dos testes negativos)
-- ----------------------------------------------------------------------------
do $$
declare
  v_metas   int;
  v_vivas_a int;
  v_aprov   int;
  v_evt     int;
  v_quota   int;
begin
  select count(*) into v_metas from public.evaluation_goals
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_vivas_a from public.evaluation_goals
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1'
     and tipo = 'NEGOCIO_PROJETO' and excluida = false;
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_evt from public.evaluation_goal_events;
  select count(*) into v_quota from public.evaluation_cycle_goal_limits
   where organization_id = 'eea00000-0000-0000-0000-0000000000a1';

  if v_metas <> 4 or v_vivas_a <> 2 or v_aprov <> 1 or v_evt <> 1 or v_quota <> 2 then
    raise exception
      '[FAIL] L: estado final inesperado (metas=%, vivas NEGOCIO_PROJETO=%, aprovacoes=%, eventos=%, quotas=%)',
      v_metas, v_vivas_a, v_aprov, v_evt, v_quota;
  end if;

  raise notice '[PASS] L: estado final coerente (4 metas em Alfa com 2 vivas de negocio, 1 aprovacao, 1 evento, 2 quotas) — nenhum teste negativo deixou residuo';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-10 P1: schema/integridade/limites validados — identidade UUID, FKs compostas cross-tenant, dominio de progresso/tipo/status/fechamento, quota soberana (limite, reducao, DELETE, reativacao), unicidade parcial e idempotencia, soft delete sem DELETE fisico, trilha append-only e RLS deny-by-default.';
  raise notice '============================================================';
end $$;
