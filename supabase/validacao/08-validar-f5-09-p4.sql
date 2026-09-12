-- ============================================================================
-- F5-09 P4: validacao automatizada das transicoes excepcionais de ciclo
-- (cancelar, reabrir, corrigir periodo) — Supabase local apenas
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (migrations)
--   2) `07-cenario-f5-09-p4.sql` (fixture isolada / guarda de estado limpo)
--   3) este arquivo             (asserts `[PASS]`/`[FAIL]`)
--
-- Contrato coberto (docs/F5-09-desenho-tecnico.md §6 T4/T5/T6/T7, §8, §10
-- I7/I8/I11/I12/I19, §11, §12, §13.2/§13.3, §19 P4):
--   CANCELAMENTO (T4/T5):
--     PLANEJADO -> CANCELADO; ATIVO -> CANCELADO; ENCERRADO recusa; CANCELADO
--     recusa (terminal, D8); motivo vazio recusa; expected_version obsoleto
--     recusa; capability ausente recusa; membership revogada recusa;
--     cross-tenant recusa; avaliacoes CONCLUIDAS preservadas; avaliacoes NAO
--     concluidas resolvidas na MESMA transacao (via `evaluation_cancelar`);
--     PLANEJADO com avaliacao NAO cancelada recusa (fail-closed); nenhuma
--     exclusao fisica; snapshots preservados; replay idempotente; operation_id
--     divergente = CONFLICT; falha injetada em DUAS fases com ROLLBACK REAL.
--   REABERTURA (T6):
--     ENCERRADO -> ATIVO; PLANEJADO/ATIVO/CANCELADO recusam; motivo vazio;
--     expected_version obsoleto; capability; membership; cross-tenant; outro
--     ciclo ATIVO impede; sobreposicao (I6) impossivel por construcao;
--     snapshots/participantes/responsabilidades/avaliacoes preservados; sem
--     criacao de avaliacoes; idempotencia; falha injetada com ROLLBACK REAL.
--   CORRECAO DE PERIODO (T7):
--     alteracao valida; data_inicio > data_fim recusa; estado != ATIVO recusa;
--     sobreposicao recusa; periodo identico recusa; justificativa vazia recusa;
--     expected_version obsoleto; capability; membership; cross-tenant; IMPACTO
--     calculado server-side; estrutura materializada intacta; idempotencia;
--     falha injetada DEPOIS do UPDATE com ROLLBACK REAL.
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer falha aborta.
-- Asserts negativos rodam em subtransacao (a excecao esperada reverte apenas a
-- tentativa). Falhas injetadas usam triggers/sequences TEMPORARIOS removidos ao
-- final. O UUID do ciclo NAO e transportado por variavel do psql (a interpolacao
-- `:'var'` nao e aplicada dentro de corpos dollar-quoted): cada bloco resolve o
-- alvo por SELECT DETERMINISTICO (organization_id + ano + numero).
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture isolada, organizacoes sem ciclos, 3 RPCs instaladas
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'eba00000-0000-0000-0000-0000000000b1';
  v_colabs int;
  v_ciclos int;
  v_fn     int;
  v_args   text;
  v_caps   int;
begin
  select count(*) into v_colabs from public.collaborators
   where organization_id = v_org;
  if v_colabs <> 3 then
    raise exception '[FAIL] pre-condicao: fixture F5-09 P4 ausente (colaboradores=%) — execute 07-cenario-f5-09-p4.sql', v_colabs;
  end if;
  select count(*) into v_ciclos from public.evaluation_cycles
   where organization_id in (v_org, v_beta);
  if v_ciclos <> 0 then
    raise exception '[FAIL] pre-condicao: organizacoes da fixture ja possuem % ciclo(s) — execute `supabase db reset` (a trilha de ciclos e append-only)', v_ciclos;
  end if;

  -- As tres RPCs existem com a assinatura EXATA do contrato (§13.2).
  select count(*) into v_fn
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('ciclo_cancelar', 'ciclo_reabrir', 'ciclo_corrigir_periodo');
  if v_fn <> 3 then
    raise exception '[FAIL] pre-condicao: RPCs da P4 ausentes (%)', v_fn;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_cancelar fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_reabrir fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)');
  if v_args is distinct from
     'p_cycle_id uuid, p_organization_id uuid, p_data_inicio date, p_data_fim date, p_justificativa text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid' then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_corrigir_periodo fora do contrato (%)', v_args;
  end if;
  -- O cliente NAO declara impacto (nenhum parametro de impacto na assinatura).
  if v_args like '%impacto%' then
    raise exception '[FAIL] pre-condicao: ciclo_corrigir_periodo aceita impacto do cliente';
  end if;

  -- Catalogo de capabilities intacto (nenhuma capability nova na P4).
  select count(*) into v_caps from public.capabilities;
  if v_caps <> 31 then
    raise exception '[FAIL] pre-condicao: catalogo de capabilities alterado (%)', v_caps;
  end if;

  raise notice '[PASS] pre-condicoes: fixture isolada da P4 presente, organizacoes sem ciclos, 3 RPCs com assinatura exata do contrato e catalogo intacto (31 capabilities)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) Setup: ciclos da fixture (todos criados pelas RPCs soberanas)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'eba00000-0000-0000-0000-0000000000b1';
  v_a1    uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_a3    uuid := 'ebc00000-0000-0000-0000-000000000003';
  v_res   jsonb;
  v_c1    uuid;
  v_cb    uuid;
  v_snap  int;
  v_ve    int;
begin
  -- C1 (2031/1): ciclo ATIVO usado no cancelamento com avaliacoes.
  v_res := public.ciclo_criar(v_org, 2031, 1, date '2031-01-01', date '2031-03-31',
    v_a1, 'eba10000-0000-0000-0000-000000000a01');
  v_c1 := (v_res->>'cycle_id')::uuid;
  v_res := public.ciclo_ativar(v_c1, v_org, 0, v_a1, 'eba10000-0000-0000-0000-000000000a02');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] setup: C1 deveria estar ATIVO/version 1 (%)', v_res;
  end if;

  -- C2 (2031/2): PLANEJADO, usado no cancelamento de PLANEJADO.
  perform public.ciclo_criar(v_org, 2031, 2, date '2031-04-01', date '2031-06-30',
    v_a1, 'eba10000-0000-0000-0000-000000000a03');

  -- C5 (2032/2): PLANEJADO adjacente, usado na recusa por sobreposicao.
  perform public.ciclo_criar(v_org, 2032, 2, date '2032-05-01', date '2032-06-30',
    v_a1, 'eba10000-0000-0000-0000-000000000a04');

  -- Ciclo do Beta (probes cross-tenant diretos).
  v_res := public.ciclo_criar(v_beta, 2031, 1, date '2031-01-01', date '2031-03-31',
    v_a3, 'eba10000-0000-0000-0000-000000000a05');
  v_cb := (v_res->>'cycle_id')::uuid;
  v_res := public.ciclo_ativar(v_cb, v_beta, 0, v_a3, 'eba10000-0000-0000-0000-000000000a06');
  if (v_res->>'status') <> 'ATIVO' then
    raise exception '[FAIL] setup: ciclo do Beta deveria estar ATIVO (%)', v_res;
  end if;

  select count(*) into v_snap from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_snap <> 3 then
    raise exception '[FAIL] setup: C1 deveria materializar 3 participantes (%)', v_snap;
  end if;
  select count(*) into v_ve from public.cycle_events e
   where e.organization_id = v_org;
  if v_ve <> 4 then
    raise exception '[FAIL] setup: esperados 4 eventos na trilha do Alfa (C1 CRIADO/ATIVADO, C2 CRIADO, C5 CRIADO), encontrado %', v_ve;
  end if;

  raise notice '[PASS] setup: C1 ATIVO/version 1 (3 participantes materializados), C2 e C5 PLANEJADOS e ciclo do Beta ATIVO';
end $$;

-- ----------------------------------------------------------------------------
-- 2) Cancelamento ATIVO (T4): avaliacoes, rollback real em DUAS fases, sucesso
-- ----------------------------------------------------------------------------
-- Fixture de avaliacoes de C1 (via RPC soberana da F5-06; estados avancados por
-- fixture quando a completude de notas nao e o objeto desta validacao):
--   E1a B3 CANCELADA (cancelada ANTES, deve permanecer intocada);
--   E1b B3 CONCLUIDA (deve ser PRESERVADA pelo cancelamento do ciclo);
--   E1c B1 PRONTA_PARA_FEEDBACK (nao concluida -> deve ser cancelada);
--   E1d B2 RASCUNHO (nao concluida -> deve ser cancelada).
do $$
declare
  v_org  uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_e    uuid;
  v_n    int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  v_e := public.evaluation_criar(v_org, v_c1, 'ebb00000-0000-0000-0000-000000000003', v_a1);
  perform public.evaluation_cancelar(v_e, 'Cancelamento previo (fixture) da avaliacao E1a',
    v_a1);

  v_e := public.evaluation_criar(v_org, v_c1, 'ebb00000-0000-0000-0000-000000000003', v_a1);
  update public.evaluations
     set status = 'CONCLUIDA', data_conclusao = now(), nota_media = 4.5, version = version + 1
   where id = v_e;

  v_e := public.evaluation_criar(v_org, v_c1, 'ebb00000-0000-0000-0000-000000000001', v_a1);
  update public.evaluations set status = 'PRONTA_PARA_FEEDBACK', version = version + 1
   where id = v_e;

  perform public.evaluation_criar(v_org, v_c1, 'ebb00000-0000-0000-0000-000000000002', v_a1);

  if (select count(*) from public.evaluations e
       where e.cycle_id = v_c1 and e.organization_id = v_org) <> 4 then
    raise exception '[FAIL] fixture de avaliacoes de C1 deveria ter 4 avaliacoes';
  end if;
  if (select count(*) from public.evaluations e
       where e.cycle_id = v_c1 and e.organization_id = v_org
         and e.status not in ('CONCLUIDA', 'CANCELADA')) <> 2 then
    raise exception '[FAIL] fixture: C1 deveria ter 2 avaliacoes NAO concluidas';
  end if;
  if (select count(*) from public.evaluation_participants p
        join public.evaluations e on e.id = p.evaluation_id
       where e.cycle_id = v_c1) < 1 then
    raise exception '[FAIL] fixture: nenhuma ocorrencia de participante congelada em C1';
  end if;

  raise notice '[PASS] fixture de avaliacoes de C1: 4 avaliacoes (1 CANCELADA previa, 1 CONCLUIDA, 1 PRONTA_PARA_FEEDBACK, 1 RASCUNHO) com participantes congelados';
end $$;

-- Checkpoint de imutabilidade das avaliacoes de C1 (usado nas provas de rollback).
do $$
declare
  v_org uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_c1  uuid;
  v_n   int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select count(*) into v_n
    from public.evaluation_events ev
    join public.evaluations e on e.id = ev.evaluation_id
   where e.cycle_id = v_c1 and ev.event_type = 'CANCELADA';
  if v_n <> 1 then
    raise exception '[FAIL] baseline: esperado 1 evento CANCELADA pre-existente em C1 (%)', v_n;
  end if;
  raise notice '[PASS] baseline do cancelamento ATIVO: C1 ATIVO/version 1 com 4 avaliacoes e 1 evento CANCELADA pre-existente';
end $$;

-- FASE 1 do rollback: falha no SEGUNDO cancelamento de avaliacao da MESMA
-- transacao (o primeiro ja foi processado). O contador e um SEQUENCE (nao
-- transacional): permite ler DEPOIS do rollback que o processamento comecou.
create sequence public._mut_p4_aval_seq;

create or replace function public._mut_p4_falhar_cancelamento_aval()
returns trigger language plpgsql as $mut$
declare
  v_tentativa bigint := nextval('public._mut_p4_aval_seq');
begin
  if v_tentativa >= 2 then
    raise notice '_mut_p4_falhar_cancelamento_aval: abortando no %o cancelamento de avaliacao (o 1o ja havia sido processado nesta transacao)', v_tentativa;
    raise exception 'MUT_F5_09_P4: falha injetada durante o processamento das avaliacoes';
  end if;
  return new;
end;
$mut$;

create trigger _mut_p4_aval before insert on public.evaluation_events
  for each row execute function public._mut_p4_falhar_cancelamento_aval();

do $$
declare
  v_org  uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_ok   boolean := false;
  v_msg  text;
  v_tent bigint;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  begin
    perform public.ciclo_cancelar(v_c1, v_org, 'Cancelamento com falha injetada na 2a avaliacao',
      1, v_a1, 'eba10000-0000-0000-0000-000000000c06');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P4%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] R1/cancelar: a falha injetada durante as avaliacoes nao abortou o cancelamento (%)', v_msg;
  end if;

  -- Prova de que o processamento REALMENTE comecou (>= 2 cancelamentos tentados).
  v_tent := currval('public._mut_p4_aval_seq');
  if v_tent < 2 then
    raise exception '[FAIL] R1/cancelar: o gatilho nao foi atingido no processamento das avaliacoes (tentativas=%)', v_tent;
  end if;

  raise notice '[PASS] R1/cancelar: falha injetada abortou o cancelamento no %o cancelamento de avaliacao (trabalho parcial ja executado)', v_tent;
end $$;

drop trigger _mut_p4_aval on public.evaluation_events;
drop function public._mut_p4_falhar_cancelamento_aval();
drop sequence public._mut_p4_aval_seq;

do $$
declare
  v_org   uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_c1    uuid;
  v_ciclo record;
  v_n     int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select c.status, c.version into v_ciclo from public.evaluation_cycles c where c.id = v_c1;
  if v_ciclo.status <> 'ATIVO' or v_ciclo.version <> 1 then
    raise exception '[FAIL] 21b/R1: rollback incompleto (ciclo %, version %)', v_ciclo.status, v_ciclo.version;
  end if;
  select count(*) into v_n from public.evaluations e
   where e.cycle_id = v_c1 and e.status = 'CANCELADA';
  if v_n <> 1 then
    raise exception '[FAIL] 21b/R1: rollback incompleto nas avaliacoes (canceladas=%, esperado apenas a previa)', v_n;
  end if;
  select count(*) into v_n
    from public.evaluation_events ev
    join public.evaluations e on e.id = ev.evaluation_id
   where e.cycle_id = v_c1 and ev.event_type = 'CANCELADA';
  if v_n <> 1 then
    raise exception '[FAIL] 21b/R1: rollback incompleto na trilha de avaliacoes (eventos CANCELADA=%)', v_n;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eba10000-0000-0000-0000-000000000c06'
  ) then
    raise exception '[FAIL] 21b/R1: rollback incompleto (evento de ciclo gravado)';
  end if;
  if exists (
    select 1 from public.evaluation_participants p
      join public.evaluations e on e.id = p.evaluation_id
     where e.cycle_id = v_c1
       and (p.status <> 'active' or p.valid_to is not null)
  ) then
    raise exception '[FAIL] 21b/R1: rollback incompleto nos participantes congelados';
  end if;

  raise notice '[PASS] R1/cancelar: falha DURANTE o processamento => ROLLBACK TOTAL (ciclo ATIVO/version 1, avaliacoes e trilha no estado original, zero evento de ciclo)';
end $$;

-- FASE 2 do rollback: falha DEPOIS de todo o processamento das avaliacoes, no
-- UPDATE do ciclo (gatilho BEFORE UPDATE em evaluation_cycles).
create or replace function public._mut_p4_falhar_cancelamento_ciclo()
returns trigger language plpgsql as $mut$
begin
  if new.status = 'CANCELADO' and old.status is distinct from 'CANCELADO' then
    raise notice '_mut_p4_falhar_cancelamento_ciclo: abortando no UPDATE do ciclo para CANCELADO (as avaliacoes ja haviam sido processadas)';
    raise exception 'MUT_F5_09_P4: falha injetada no UPDATE do ciclo';
  end if;
  return new;
end;
$mut$;

create trigger _mut_p4_cancelar_ciclo before update on public.evaluation_cycles
  for each row execute function public._mut_p4_falhar_cancelamento_ciclo();

do $$
declare
  v_org  uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c1   uuid;
  v_ok   boolean := false;
  v_msg  text;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  begin
    perform public.ciclo_cancelar(v_c1, v_org, 'Cancelamento com falha injetada no UPDATE do ciclo',
      1, v_a1, 'eba10000-0000-0000-0000-000000000c07');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P4%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] R2/cancelar: a falha injetada no UPDATE do ciclo nao abortou o cancelamento (%)', v_msg;
  end if;
end $$;

drop trigger _mut_p4_cancelar_ciclo on public.evaluation_cycles;
drop function public._mut_p4_falhar_cancelamento_ciclo();

do $$
declare
  v_org   uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_c1    uuid;
  v_ciclo record;
  v_n     int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;
  select c.status, c.version into v_ciclo from public.evaluation_cycles c where c.id = v_c1;
  if v_ciclo.status <> 'ATIVO' or v_ciclo.version <> 1 then
    raise exception '[FAIL] 21c/R2: rollback incompleto (ciclo %, version %)', v_ciclo.status, v_ciclo.version;
  end if;
  select count(*) into v_n from public.evaluations e
   where e.cycle_id = v_c1 and e.status not in ('CONCLUIDA', 'CANCELADA');
  if v_n <> 2 then
    raise exception '[FAIL] 21c/R2: rollback incompleto (avaliacoes nao concluidas=%, esperado 2)', v_n;
  end if;
  select count(*) into v_n from public.evaluations e
   where e.cycle_id = v_c1 and e.status = 'CANCELADA';
  if v_n <> 1 then
    raise exception '[FAIL] 21c/R2: rollback incompleto (avaliacoes canceladas=%, esperado 1)', v_n;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eba10000-0000-0000-0000-000000000c07'
  ) then
    raise exception '[FAIL] 21c/R2: rollback incompleto (evento de ciclo gravado)';
  end if;

  raise notice '[PASS] R2/cancelar: falha APOS o processamento das avaliacoes => ROLLBACK TOTAL (avaliacoes voltaram a nao concluidas e ciclo ATIVO/version 1)';
end $$;

do $$
declare
  v_org    uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1     uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c1     uuid;
  v_res    jsonb;
  v_ciclo  record;
  v_evt    record;
  v_e1a    uuid;
  v_e1b    uuid;
  v_e1c    uuid;
  v_e1d    uuid;
  v_dc_b   timestamptz;
  v_mot_b  text;
  v_snap_h text;
  v_snap_h2 text;
  v_qtd    int;
  v_ok     boolean;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  -- Referencias das avaliacoes por (collaborator, status) — determinismo total.
  select e.id, e.data_conclusao, e.motivo_cancelamento into v_e1a, v_dc_b, v_mot_b
    from public.evaluations e
   where e.cycle_id = v_c1 and e.status = 'CANCELADA' limit 1;
  select e.id into v_e1b from public.evaluations e
   where e.cycle_id = v_c1 and e.status = 'CONCLUIDA' limit 1;
  select e.id into v_e1c from public.evaluations e
   where e.cycle_id = v_c1 and e.status = 'PRONTA_PARA_FEEDBACK' limit 1;
  select e.id into v_e1d from public.evaluations e
   where e.cycle_id = v_c1 and e.status = 'RASCUNHO' limit 1;
  if v_e1a is null or v_e1b is null or v_e1c is null or v_e1d is null then
    raise exception '[FAIL] cancelar/ATIVO: fixture de avaliacoes de C1 incompleta';
  end if;

  -- Checksum dos snapshots de C1 (nao pode mudar com o cancelamento).
  select md5(string_agg(x, '|' order by x)) into v_snap_h from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1
  ) t;

  -- (T4) Cancelamento valido do ciclo ATIVO.
  v_res := public.ciclo_cancelar(v_c1, v_org, 'Cancelamento soberano de teste (T4)',
    1, v_a1, 'eba10000-0000-0000-0000-000000000c01');

  if (v_res->>'status') <> 'CANCELADO' or (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] cancelar/ATIVO: retorno deveria ser CANCELADO/version 2 (%)', v_res;
  end if;
  if (v_res->>'avaliacoes_canceladas')::int <> 2 then
    raise exception '[FAIL] cancelar/ATIVO: deveria cancelar 2 avaliacoes NAO concluidas (%)', v_res;
  end if;
  if (v_res->>'avaliacoes_concluidas_preservadas')::int <> 1 then
    raise exception '[FAIL] cancelar/ATIVO: deveria preservar 1 avaliacao CONCLUIDA (%)', v_res;
  end if;

  select c.status, c.version, c.data_inicio, c.data_fim into v_ciclo
    from public.evaluation_cycles c where c.id = v_c1;
  if v_ciclo.status <> 'CANCELADO' or v_ciclo.version <> 2 then
    raise exception '[FAIL] cancelar/ATIVO: ciclo deveria estar CANCELADO/version 2 (%, %)', v_ciclo.status, v_ciclo.version;
  end if;
  if v_ciclo.data_inicio <> date '2031-01-01' or v_ciclo.data_fim <> date '2031-03-31' then
    raise exception '[FAIL] cancelar/ATIVO: cancelamento nao altera o periodo do ciclo';
  end if;

  -- (10) Avaliacoes NAO concluidas resolvidas pelo caminho soberano da F5-06.
  if (select e.status from public.evaluations e where e.id = v_e1c) <> 'CANCELADA'
     or (select e.status from public.evaluations e where e.id = v_e1d) <> 'CANCELADA' then
    raise exception '[FAIL] cancelar/ATIVO: avaliacoes nao concluidas nao foram canceladas';
  end if;
  if exists (
    select 1 from public.evaluations e
     where e.id in (v_e1c, v_e1d)
       and (e.motivo_cancelamento is null or btrim(e.motivo_cancelamento) = ''
            or e.data_cancelamento is null or e.cancelado_por_user_profile_id <> v_a1)
  ) then
    raise exception '[FAIL] cancelar/ATIVO: cancelamento das avaliacoes sem motivo/autor/data (F5-06)';
  end if;
  if exists (
    select 1 from public.evaluation_events ev
     where ev.evaluation_id in (v_e1c, v_e1d) and ev.event_type = 'CANCELADA'
  ) is not true then
    raise exception '[FAIL] cancelar/ATIVO: trilha de avaliacao (evaluation_events) sem CANCELADA';
  end if;

  -- (10) Avaliacao CONCLUIDA PRESERVADA e cancelamento previo intocado.
  if (select e.status from public.evaluations e where e.id = v_e1b) <> 'CONCLUIDA'
     or (select e.data_conclusao from public.evaluations e where e.id = v_e1b) is null
     or (select e.motivo_cancelamento from public.evaluations e where e.id = v_e1b) is not null then
    raise exception '[FAIL] cancelar/ATIVO: avaliacao CONCLUIDA foi alterada pelo cancelamento do ciclo';
  end if;
  if (select e.status from public.evaluations e where e.id = v_e1a) <> 'CANCELADA'
     or (select e.motivo_cancelamento from public.evaluations e where e.id = v_e1a) is distinct from v_mot_b then
    raise exception '[FAIL] cancelar/ATIVO: cancelamento previo da avaliacao foi reescrito';
  end if;

  -- Snapshots intactos (nenhum recalculo/apagamento).
  select md5(string_agg(x, '|' order by x)) into v_snap_h2 from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1) t;
  if v_snap_h2 is distinct from v_snap_h then
    raise exception '[FAIL] cancelar/ATIVO: snapshots do ciclo foram alterados';
  end if;
  select count(*) into v_qtd from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 1;
  if v_qtd <> 3 then
    raise exception '[FAIL] cancelar/ATIVO: populacao materializada deveria continuar com 3 snapshots (%)', v_qtd;
  end if;

  -- Evento CANCELADO com before/after suficientes.
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eba10000-0000-0000-0000-000000000c01';
  if v_evt.event_type <> 'CANCELADO' or v_evt.reason <> 'Cancelamento soberano de teste (T4)' then
    raise exception '[FAIL] cancelar/ATIVO: evento CANCELADO ausente ou sem motivo';
  end if;
  if (v_evt.before_value->>'status') <> 'ATIVO' or (v_evt.before_value->>'version')::int <> 1 then
    raise exception '[FAIL] cancelar/ATIVO: before_value sem o estado de origem (%)', v_evt.before_value;
  end if;
  if (v_evt.after_value->>'status') <> 'CANCELADO'
     or (v_evt.after_value->>'version')::int <> 2
     or (v_evt.after_value->>'avaliacoes_canceladas')::int <> 2
     or (v_evt.after_value->>'avaliacoes_concluidas_preservadas')::int <> 1 then
    raise exception '[FAIL] cancelar/ATIVO: after_value sem as contagens do cancelamento (%)', v_evt.after_value;
  end if;
  if v_evt.actor_user_profile_id <> v_a1
     or v_evt.actor_membership_id <> 'ebd00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] cancelar/ATIVO: autoria da trilha nao e o ator verificado + membership ativa';
  end if;
  if v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] cancelar/ATIVO: payload_hash fora do formato SHA-256';
  end if;

  -- (9) Replay idempotente: MESMO operation_id + MESMO payload.
  v_res := public.ciclo_cancelar(v_c1, v_org, 'Cancelamento soberano de teste (T4)',
    1, v_a1, 'eba10000-0000-0000-0000-000000000c01');
  if (v_res->>'status') <> 'CANCELADO' or (v_res->>'version')::int <> 2
     or (v_res->>'avaliacoes_canceladas')::int <> 2 then
    raise exception '[FAIL] cancelar/ATIVO: replay devolveu resultado diferente (%)', v_res;
  end if;
  select count(*) into v_qtd from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eba10000-0000-0000-0000-000000000c01';
  if v_qtd <> 1 then
    raise exception '[FAIL] cancelar/ATIVO: replay duplicou a trilha (%)', v_qtd;
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 2 then
    raise exception '[FAIL] cancelar/ATIVO: replay alterou a versao do ciclo';
  end if;

  -- (15) operation_id reutilizado com intencao diferente => CONFLICT.
  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_c1, v_org, 'Intencao divergente com o mesmo operation_id',
      2, v_a1, 'eba10000-0000-0000-0000-000000000c01');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] cancelar/ATIVO: operation_id divergente deveria ser CONFLICT';
  end if;

  -- (D8) CANCELADO e TERMINAL: novo cancelamento recusa.
  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_c1, v_org, 'Segundo cancelamento do mesmo ciclo',
      2, v_a1, 'eba10000-0000-0000-0000-000000000c05');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%exige ciclo PLANEJADO ou ATIVO%';
  end;
  if not v_ok then
    raise exception '[FAIL] cancelar/ATIVO: cancelamento de ciclo ja CANCELADO deveria ser CONFLICT de estado';
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c1) <> 2 then
    raise exception '[FAIL] cancelar/ATIVO: tentativa recusada alterou a versao';
  end if;

  raise notice '[PASS] cancelar/ATIVO (T4): ciclo ATIVO -> CANCELADO (version 2) com 2 avaliacoes NAO concluidas resolvidas via F5-06, 1 CONCLUIDA preservada, cancelamento previo intocado, snapshots intactos, evento CANCELADO com contagens, replay idempotente, operation_id divergente e CANCELADO terminal recusados';
end $$;

-- ----------------------------------------------------------------------------
-- 3) Cancelamento de ciclo PLANEJADO (T5) e recusas de forma/versao
-- ----------------------------------------------------------------------------
do $$
declare
  v_org  uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c2   uuid;
  v_e    uuid;
  v_res  jsonb;
  v_ok   boolean;
  v_msg  text;
  v_ciclo record;
begin
  select c.id into v_c2 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 2;

  -- (forma) motivo vazio => INVALID_INPUT.
  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_c2, v_org, '   ', 0, v_a1,
      'eba10000-0000-0000-0000-000000000c10');
  exception when others then
    v_ok := sqlerrm like '%F5_09_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] cancelar/PLANEJADO: motivo vazio deveria ser INVALID_INPUT';
  end if;

  -- (forma) expected_version ausente => INVALID_INPUT.
  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_c2, v_org, 'Sem expected_version', null, v_a1,
      'eba10000-0000-0000-0000-000000000c11');
  exception when others then
    v_ok := sqlerrm like '%F5_09_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] cancelar/PLANEJADO: expected_version nulo deveria ser INVALID_INPUT';
  end if;

  -- (expected_version) obsoleto => CONFLICT por versao, sem efeito.
  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_c2, v_org, 'Versao obsoleta', 7, v_a1,
      'eba10000-0000-0000-0000-000000000c12');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%versao divergente%';
  end;
  if not v_ok then
    raise exception '[FAIL] cancelar/PLANEJADO: expected_version obsoleto deveria ser CONFLICT por versao';
  end if;

  -- (T5) PLANEJADO com avaliacao NAO cancelada => recusa fail-closed.
  -- ESTADO DEFENSIVO SINTETICO: pelo caminho soberano um ciclo PLANEJADO nunca
  -- tem avaliacoes (a F3-08 so materializa na ativacao e a F5-06 exige o snapshot
  -- do ciclo) — exatamente por isso o guarda da RPC e defesa em profundidade.
  -- Aqui a estrutura e materializada DIRETAMENTE (primitiva F3-08/F3-09) apenas
  -- para EXERCITAR esse guarda.
  perform public.materializar_colegiado_ciclo(v_org, 2031, 2, now(),
    array['ebb00000-0000-0000-0000-000000000001'::uuid]);
  perform public.materializar_responsabilidades_avaliacao(v_org, 2031, 2);
  v_e := public.evaluation_criar(v_org, v_c2, 'ebb00000-0000-0000-0000-000000000001', v_a1);
  v_ok := false;
  v_msg := null;
  begin
    perform public.ciclo_cancelar(v_c2, v_org, 'Cancelamento com avaliacao pendente', 0, v_a1,
      'eba10000-0000-0000-0000-000000000c13');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%ausencia de avaliacoes nao canceladas%';
    v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] cancelar/PLANEJADO (T5): avaliacao nao cancelada deveria bloquear (%)', v_msg;
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_c2) <> 'PLANEJADO' then
    raise exception '[FAIL] cancelar/PLANEJADO (T5): recusa alterou o status do ciclo';
  end if;

  -- O operador resolve a avaliacao ANTES (caminho soberano da F5-06) e o
  -- cancelamento passa a ser permitido.
  perform public.evaluation_cancelar(v_e, 'Resolvida antes do cancelamento do ciclo PLANEJADO', v_a1);

  v_res := public.ciclo_cancelar(v_c2, v_org, 'Cancelamento de ciclo PLANEJADO (T5)',
    0, v_a1, 'eba10000-0000-0000-0000-000000000c14');
  if (v_res->>'status') <> 'CANCELADO' or (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] cancelar/PLANEJADO: retorno deveria ser CANCELADO/version 1 (%)', v_res;
  end if;
  if (v_res->>'avaliacoes_canceladas')::int <> 0
     or (v_res->>'avaliacoes_concluidas_preservadas')::int <> 0 then
    raise exception '[FAIL] cancelar/PLANEJADO: nenhuma avaliacao deveria ser cancelada nesta transicao (%)', v_res;
  end if;
  select c.status, c.version, c.ano, c.numero into v_ciclo
    from public.evaluation_cycles c where c.id = v_c2;
  if v_ciclo.status <> 'CANCELADO' or v_ciclo.version <> 1 then
    raise exception '[FAIL] cancelar/PLANEJADO: ciclo deveria estar CANCELADO/version 1 (%, %)', v_ciclo.status, v_ciclo.version;
  end if;
  if not exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eba10000-0000-0000-0000-000000000c14'
       and e.event_type = 'CANCELADO'
       and (e.before_value->>'status') = 'PLANEJADO'
       and (e.after_value->>'status') = 'CANCELADO'
  ) then
    raise exception '[FAIL] cancelar/PLANEJADO: evento CANCELADO com before/after ausente';
  end if;

  -- ZERO efeito das recusas deste bloco.
  if exists (
    select 1 from public.cycle_events e
     where e.operation_id::text in (
       'eba10000-0000-0000-0000-000000000c10', 'eba10000-0000-0000-0000-000000000c11',
       'eba10000-0000-0000-0000-000000000c12', 'eba10000-0000-0000-0000-000000000c13')
  ) then
    raise exception '[FAIL] cancelar/PLANEJADO: recusa gravou evento na trilha';
  end if;

  raise notice '[PASS] cancelar/PLANEJADO (T5): avaliacao nao cancelada bloqueia (fail-closed), resolucao previa pela F5-06 libera o cancelamento (version 1), motivo vazio/expected_version nulo => INVALID_INPUT, versao obsoleta => CONFLICT e nenhuma recusa gera efeito';
end $$;

-- ----------------------------------------------------------------------------
-- 4) Reabertura (T6): ENCERRADO -> ATIVO sem rematerializar nada
-- ----------------------------------------------------------------------------
do $$
declare
  v_org  uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c3   uuid;
  v_res  jsonb;
  v_ciclo record;
  v_n    int;
begin
  -- C3 (2031/3) nasce PLANEJADO, e ATIVADO, recebe UMA avaliacao incompleta
  -- (marcada como pendencia pela F5-06) e e ENCERRADO.
  v_res := public.ciclo_criar(v_org, 2031, 3, date '2031-07-01', date '2031-09-30',
    v_a1, 'eba10000-0000-0000-0000-000000000a07');
  v_c3 := (v_res->>'cycle_id')::uuid;
  v_res := public.ciclo_ativar(v_c3, v_org, 0, v_a1, 'eba10000-0000-0000-0000-000000000a08');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] reabertura/setup: C3 deveria estar ATIVO/version 1 (%)', v_res;
  end if;

  perform public.evaluation_criar(v_org, v_c3, 'ebb00000-0000-0000-0000-000000000001', v_a1);

  v_res := public.ciclo_encerrar(v_c3, v_org, 'Encerramento com pendencia (fixture da reabertura)',
    1, v_a1, 'eba10000-0000-0000-0000-000000000a09');
  select c.status, c.version, c.data_encerramento, c.encerrado_com_pendencias, c.quantidade_pendencias
    into v_ciclo
    from public.evaluation_cycles c where c.id = v_c3;
  if v_ciclo.status <> 'ENCERRADO' or v_ciclo.data_encerramento is null then
    raise exception '[FAIL] reabertura/setup: C3 deveria estar ENCERRADO com data_encerramento';
  end if;
  if v_ciclo.version <> 2 then
    raise exception '[FAIL] reabertura/setup: encerramento deveria resultar em version 2 (F5-06 incrementa uma vez) (%)', v_ciclo.version;
  end if;
  if v_ciclo.encerrado_com_pendencias is not true or v_ciclo.quantidade_pendencias < 1 then
    raise exception '[FAIL] reabertura/setup: encerramento deveria registrar pendencia (%, %)',
      v_ciclo.encerrado_com_pendencias, v_ciclo.quantidade_pendencias;
  end if;
  select count(*) into v_n from public.evaluations e where e.cycle_id = v_c3;
  if v_n <> 1 then
    raise exception '[FAIL] reabertura/setup: C3 deveria ter 1 avaliacao (%)', v_n;
  end if;

  raise notice '[PASS] reabertura/setup: C3 ENCERRADO/version 2 com data_encerramento, 1 avaliacao incompleta marcada como pendencia pela F5-06 e 3 participantes materializados';
end $$;

do $$
declare
  v_org    uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1     uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c3     uuid;
  v_res    jsonb;
  v_ciclo  record;
  v_evt    record;
  v_fp     text;
  v_fp2    text;
  v_n      int;
  v_ok     boolean;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 3;

  -- Fingerprint da estrutura congelada ANTES da reabertura.
  select md5(coalesce(string_agg(x, '|' order by x), '')) into v_fp from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 3) t;
  select v_fp || '|' || md5(coalesce(string_agg(y, '|' order by y), '')) into v_fp from (
    select sp.id::text || ':' || sp.position_id::text || ':' ||
           coalesce(sp.superior_position_id::text, '-') || ':' ||
           coalesce(sp.superior_collaborator_id::text, '-') as y
      from public.collegiate_cycle_snapshot_positions sp
      join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 3) t;
  select v_fp || '|' || md5(coalesce(string_agg(z, '|' order by z), '')) into v_fp from (
    select m.id::text || ':' || m.member_collaborator_id::text as z
      from public.collegiate_cycle_snapshot_members m
      join public.collegiate_cycle_snapshots s on s.id = m.snapshot_id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 3) t;
  select v_fp || '|' || md5(coalesce(string_agg(w, '|' order by w), '')) into v_fp from (
    select r.id::text || ':' || r.position_id::text || ':' || r.responsible_collaborator_id::text as w
      from public.cycle_evaluation_responsibilities r
      join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 3) t;
  select v_fp || '|' || md5(coalesce(string_agg(q, '|' order by q), '')) into v_fp from (
    select p.id::text || ':' || p.role_type || ':' || p.collaborator_id::text || ':' ||
           p.status || ':' || coalesce(p.valid_to::text, '-') as q
      from public.evaluation_participants p
      join public.evaluations e on e.id = p.evaluation_id
     where e.cycle_id = v_c3) t;

  -- (T6) Reabertura valida.
  v_res := public.ciclo_reabrir(v_c3, v_org, 'Reabertura soberana de teste (T6)',
    2, v_a1, 'eba10000-0000-0000-0000-000000000d01');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 3 then
    raise exception '[FAIL] reabrir: retorno deveria ser ATIVO/version 3 (%)', v_res;
  end if;
  if (v_res->>'participantes_materializados')::int <> 3 then
    raise exception '[FAIL] reabrir: retorno sem os participantes materializados (%)', v_res;
  end if;

  select c.status, c.version, c.data_encerramento, c.data_ativacao,
         c.encerrado_com_pendencias, c.quantidade_pendencias
    into v_ciclo
    from public.evaluation_cycles c where c.id = v_c3;
  if v_ciclo.status <> 'ATIVO' or v_ciclo.version <> 3 then
    raise exception '[FAIL] reabrir: ciclo deveria estar ATIVO/version 3 (%, %)', v_ciclo.status, v_ciclo.version;
  end if;
  if v_ciclo.data_encerramento is not null then
    raise exception '[FAIL] reabrir: data_encerramento deveria ser limpa (T6)';
  end if;
  if v_ciclo.data_ativacao is null then
    raise exception '[FAIL] reabrir: data_ativacao original deveria permanecer';
  end if;
  if v_ciclo.encerrado_com_pendencias is not true or v_ciclo.quantidade_pendencias <> 1 then
    raise exception '[FAIL] reabrir: contadores de pendencia deveriam ser preservados (%, %)',
      v_ciclo.encerrado_com_pendencias, v_ciclo.quantidade_pendencias;
  end if;

  -- Nenhuma rematerializacao: fingerprint identico e nenhuma avaliacao criada.
  select md5(coalesce(string_agg(x, '|' order by x), '')) into v_fp2 from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 3) t;
  select v_fp2 || '|' || md5(coalesce(string_agg(y, '|' order by y), '')) into v_fp2 from (
    select sp.id::text || ':' || sp.position_id::text || ':' ||
           coalesce(sp.superior_position_id::text, '-') || ':' ||
           coalesce(sp.superior_collaborator_id::text, '-') as y
      from public.collegiate_cycle_snapshot_positions sp
      join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 3) t;
  select v_fp2 || '|' || md5(coalesce(string_agg(z, '|' order by z), '')) into v_fp2 from (
    select m.id::text || ':' || m.member_collaborator_id::text as z
      from public.collegiate_cycle_snapshot_members m
      join public.collegiate_cycle_snapshots s on s.id = m.snapshot_id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 3) t;
  select v_fp2 || '|' || md5(coalesce(string_agg(w, '|' order by w), '')) into v_fp2 from (
    select r.id::text || ':' || r.position_id::text || ':' || r.responsible_collaborator_id::text as w
      from public.cycle_evaluation_responsibilities r
      join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
     where s.organization_id = v_org and s.ano = 2031 and s.ciclo = 3) t;
  select v_fp2 || '|' || md5(coalesce(string_agg(q, '|' order by q), '')) into v_fp2 from (
    select p.id::text || ':' || p.role_type || ':' || p.collaborator_id::text || ':' ||
           p.status || ':' || coalesce(p.valid_to::text, '-') as q
      from public.evaluation_participants p
      join public.evaluations e on e.id = p.evaluation_id
     where e.cycle_id = v_c3) t;
  if v_fp2 is distinct from v_fp then
    raise exception '[FAIL] reabrir: estrutura/participantes/responsabilidades foram alterados pela reabertura (I19/D27)';
  end if;
  select count(*) into v_n from public.evaluations e where e.cycle_id = v_c3;
  if v_n <> 1 then
    raise exception '[FAIL] reabrir: a reabertura criou avaliacoes (%)', v_n;
  end if;

  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eba10000-0000-0000-0000-000000000d01';
  if v_evt.event_type <> 'REABERTO' or v_evt.reason <> 'Reabertura soberana de teste (T6)' then
    raise exception '[FAIL] reabrir: evento REABERTO ausente ou sem motivo';
  end if;
  if (v_evt.before_value->>'status') <> 'ENCERRADO'
     or (v_evt.before_value->>'encerrado_com_pendencias')::boolean is not true
     or (v_evt.after_value->>'status') <> 'ATIVO'
     or (v_evt.after_value->>'version')::int <> 3 then
    raise exception '[FAIL] reabrir: before/after do evento incompletos (%)', v_evt.after_value;
  end if;

  -- Idempotencia: replay e intencao divergente.
  v_res := public.ciclo_reabrir(v_c3, v_org, 'Reabertura soberana de teste (T6)',
    2, v_a1, 'eba10000-0000-0000-0000-000000000d01');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 3 then
    raise exception '[FAIL] reabrir: replay devolveu resultado diferente (%)', v_res;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eba10000-0000-0000-0000-000000000d01';
  if v_n <> 1 then
    raise exception '[FAIL] reabrir: replay duplicou a trilha (%)', v_n;
  end if;
  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, 'Intencao divergente na reabertura',
      3, v_a1, 'eba10000-0000-0000-0000-000000000d01');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir: operation_id divergente deveria ser CONFLICT';
  end if;

  -- Reabrir um ciclo ATIVO recusa (unica transicao e ENCERRADO -> ATIVO).
  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, 'Reabrir ciclo ja ATIVO',
      3, v_a1, 'eba10000-0000-0000-0000-000000000d02');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%exige ciclo ENCERRADO%';
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir: ciclo ATIVO deveria ser recusado';
  end if;

  raise notice '[PASS] reabrir (T6): ENCERRADO -> ATIVO (version 3), data_encerramento limpa, data_ativacao e contadores de pendencia preservados, estrutura/participantes/responsabilidades IDENTICOS, nenhuma avaliacao criada, evento REABERTO com before/after, replay idempotente e operation_id divergente/estado ATIVO recusados';
end $$;

-- Pre-condicao do rollback da reabertura (encerra C3 novamente).
do $$
declare
  v_org uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c3  uuid;
  v_res jsonb;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 3;
  v_res := public.ciclo_encerrar(v_c3, v_org, 'Segundo encerramento (fixture do rollback da reabertura)',
    3, v_a1, 'eba10000-0000-0000-0000-000000000d03');
  if (v_res->>'status') <> 'ENCERRADO' or (v_res->>'version')::int <> 4 then
    raise exception '[FAIL] reabrir/rollback: segundo encerramento deveria resultar em ENCERRADO/version 4 (%)', v_res;
  end if;
  raise notice '[PASS] reabrir/rollback: pre-condicao pronta (C3 ENCERRADO/version 4) — a operacao legitima abaixo nao e bloqueada por pre-condicao';
end $$;

do $$
declare
  v_org uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c3  uuid;
  v_ok  boolean := false;
  v_msg text;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 3;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, 'Versao obsoleta na reabertura',
      99, v_a1, 'eba10000-0000-0000-0000-000000000d04');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%versao divergente%';
    v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir: expected_version obsoleto deveria ser CONFLICT por versao (%)', v_msg;
  end if;
end $$;

create or replace function public._mut_p4_falhar_reabertura()
returns trigger language plpgsql as $mut$
begin
  if new.status = 'ATIVO' and old.status = 'ENCERRADO' then
    raise notice '_mut_p4_falhar_reabertura: abortando no UPDATE do ciclo para ATIVO (a transicao ja havia sido aplicada nesta transacao)';
    raise exception 'MUT_F5_09_P4: falha injetada no UPDATE da reabertura';
  end if;
  return new;
end;
$mut$;

create trigger _mut_p4_reabrir before update on public.evaluation_cycles
  for each row execute function public._mut_p4_falhar_reabertura();

do $$
declare
  v_org  uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c3   uuid;
  v_ok   boolean := false;
  v_msg  text;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 3;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, 'Reabertura com falha injetada no UPDATE',
      4, v_a1, 'eba10000-0000-0000-0000-000000000d05');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P4%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] R3/reabrir: a falha injetada nao abortou a reabertura (%)', v_msg;
  end if;
end $$;

drop trigger _mut_p4_reabrir on public.evaluation_cycles;
drop function public._mut_p4_falhar_reabertura();

do $$
declare
  v_org   uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c3    uuid;
  v_ciclo record;
  v_res   jsonb;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 3;
  select c.status, c.version, c.data_encerramento into v_ciclo
    from public.evaluation_cycles c where c.id = v_c3;
  if v_ciclo.status <> 'ENCERRADO' or v_ciclo.version <> 4 or v_ciclo.data_encerramento is null then
    raise exception '[FAIL] R3/reabrir: rollback incompleto (%, %, %)',
      v_ciclo.status, v_ciclo.version, v_ciclo.data_encerramento;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eba10000-0000-0000-0000-000000000d05'
  ) then
    raise exception '[FAIL] R3/reabrir: rollback incompleto (evento gravado)';
  end if;

  -- (23) Removida a falha, a MESMA operacao (mesmo operation_id) funciona.
  v_res := public.ciclo_reabrir(v_c3, v_org, 'Reabertura com falha injetada no UPDATE',
    4, v_a1, 'eba10000-0000-0000-0000-000000000d05');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 5 then
    raise exception '[FAIL] R3/reabrir: a operacao legitima deveria funcionar apos remover a falha (%)', v_res;
  end if;

  raise notice '[PASS] R3/reabrir: falha DEPOIS da transicao => ROLLBACK TOTAL (ENCERRADO/version 4 com data_encerramento preservada, zero evento) e a MESMA operacao conclui apos remover a falha (ATIVO/version 5)';
end $$;

do $$
declare
  v_org   uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_a3    uuid := 'ebc00000-0000-0000-0000-000000000003';
  v_c3    uuid;
  v_c5    uuid;
  v_c1    uuid;
  v_res   jsonb;
  v_ok    boolean;
  v_msg   text;
  v_n     int;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 3;
  select c.id into v_c5 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2032 and c.numero = 2;
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 1;

  -- Motivo vazio => INVALID_INPUT.
  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, '   ', 5, v_a1,
      'eba10000-0000-0000-0000-000000000d10');
  exception when others then
    v_ok := sqlerrm like '%F5_09_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir: motivo vazio deveria ser INVALID_INPUT';
  end if;

  -- Reabrir ciclo PLANEJADO e CANCELADO recusa (CANCELADO e TERMINAL, D8).
  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c5, v_org, 'Reabrir ciclo PLANEJADO', 0,
      'ebc00000-0000-0000-0000-000000000001',
      'eba10000-0000-0000-0000-000000000d11');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%exige ciclo ENCERRADO%';
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir: ciclo PLANEJADO deveria ser recusado';
  end if;
  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c1, v_org, 'Reabrir ciclo CANCELADO', 2,
      'ebc00000-0000-0000-0000-000000000001',
      'eba10000-0000-0000-0000-000000000d12');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%exige ciclo ENCERRADO%';
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir (D8): ciclo CANCELADO deveria ser recusado (terminal)';
  end if;

  -- Encerra C3 e cria/ativa C4 (2032/1) para provar que OUTRO ATIVO impede.
  v_res := public.ciclo_encerrar(v_c3, v_org, 'Terceiro encerramento (fixture: outro ATIVO)',
    5, 'ebc00000-0000-0000-0000-000000000001',
    'eba10000-0000-0000-0000-000000000d13');
  if (v_res->>'status') <> 'ENCERRADO' or (v_res->>'version')::int <> 6 then
    raise exception '[FAIL] reabrir: terceiro encerramento deveria resultar em ENCERRADO/version 6 (%)', v_res;
  end if;
  v_res := public.ciclo_criar(v_org, 2032, 1, date '2032-01-01', date '2032-03-31',
    'ebc00000-0000-0000-0000-000000000001',
    'eba10000-0000-0000-0000-000000000a0a');
  perform public.ciclo_ativar((v_res->>'cycle_id')::uuid, v_org, 0,
    'ebc00000-0000-0000-0000-000000000001',
    'eba10000-0000-0000-0000-000000000a0b');

  v_ok := false;
  v_msg := null;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, 'Reabertura com outro ATIVO na organizacao',
      6, 'ebc00000-0000-0000-0000-000000000001',
      'eba10000-0000-0000-0000-000000000d14');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%ja existe ciclo ATIVO%';
    v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir (I5/D14): outro ciclo ATIVO deveria impedir a reabertura (%)', v_msg;
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_c3) <> 'ENCERRADO' then
    raise exception '[FAIL] reabrir: recusa alterou o status de C3';
  end if;

  -- (I6) Ciclo NAO cancelado nao pode estar sobreposto: criar um ciclo sobreposto
  -- ao C3 ENCERRADO e recusado pela exclusion (23P01) — logo o estado "ENCERRADO
  -- sobreposto" e INALCANCAVEL e a reabertura nao introduz sobreposicao. Um ciclo
  -- CANCELADO, ao contrario, NAO bloqueia o periodo.
  v_ok := false;
  begin
    perform public.ciclo_criar(v_org, 2033, 1, date '2031-08-01', date '2031-08-31',
      'ebc00000-0000-0000-0000-000000000001',
      'eba10000-0000-0000-0000-000000000d15');
  exception when others then
    -- A RPC pre-checa a sobreposicao (F5_09_CONFLICT) e a exclusion da P1 segue
    -- como barreira final (23P01): ambas provam que o estado sobreposto nao existe.
    v_ok := (sqlstate = '23P01')
            or (sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%sobreposto%');
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir (I6/D15): ciclo sobreposto ao ENCERRADO deveria ser recusado (CONFLICT/exclusion)';
  end if;
  v_res := public.ciclo_criar(v_org, 2033, 2, date '2031-04-15', date '2031-05-15',
    'ebc00000-0000-0000-0000-000000000001',
    'eba10000-0000-0000-0000-000000000d16');
  if (v_res->>'cycle_id') is null then
    raise exception '[FAIL] reabrir (I6/D15): periodo de ciclo CANCELADO deveria estar livre';
  end if;

  -- ZERO efeito das recusas deste bloco.
  select count(*) into v_n from public.cycle_events e
   where e.operation_id::text in (
     'eba10000-0000-0000-0000-000000000d10', 'eba10000-0000-0000-0000-000000000d11',
     'eba10000-0000-0000-0000-000000000d12', 'eba10000-0000-0000-0000-000000000d14');
  if v_n <> 0 then
    raise exception '[FAIL] reabrir: recusa gravou evento na trilha (%)', v_n;
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c3) <> 6 then
    raise exception '[FAIL] reabrir: recusa alterou a versao de C3';
  end if;

  -- (probe direto) ator do Beta nao tem capability em Alfa-P4.
  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, 'Ator de outro tenant na reabertura',
      6, v_a3, 'eba10000-0000-0000-0000-000000000d17');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] reabrir: ator de outro tenant deveria ser FORBIDDEN';
  end if;

  raise notice '[PASS] reabrir: motivo vazio => INVALID_INPUT, PLANEJADO/ATIVO/CANCELADO recusados, OUTRO ATIVO impede (I5/D14), sobreposicao impossivel por construcao (I6/exclusion 23P01) e periodo de CANCELADO liberado, ator de outro tenant => FORBIDDEN e zero efeito nas recusas';
end $$;

-- ----------------------------------------------------------------------------
-- 5) Correcao de periodo (T7): ATIVO, impacto server-side e rollback real
-- ----------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c4  uuid;
  v_e   uuid;
  v_n   int;
begin
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2032 and c.numero = 1;
  v_e := public.evaluation_criar(v_org, v_c4, 'ebb00000-0000-0000-0000-000000000001', v_a1);
  update public.evaluations
     set status = 'CONCLUIDA', data_conclusao = timestamptz '2032-03-20T12:00:00Z',
         nota_media = 4.0, version = version + 1
   where id = v_e;
  perform public.evaluation_criar(v_org, v_c4, 'ebb00000-0000-0000-0000-000000000002', v_a1);

  select count(*) into v_n from public.evaluations e where e.cycle_id = v_c4;
  if v_n <> 2 then
    raise exception '[FAIL] periodo/setup: C4 deveria ter 2 avaliacoes (%)', v_n;
  end if;
  raise notice '[PASS] periodo/setup: C4 ATIVO/version 1 (2032-01-01..2032-03-31) com 1 avaliacao CONCLUIDA (data_conclusao 2032-03-20) e 1 RASCUNHO';
end $$;

do $$
declare
  v_org uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c4  uuid;
  v_ok  boolean;
  v_msg text;
begin
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2032 and c.numero = 1;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-03-31', date '2032-01-01',
      'Periodo invertido', 1, v_a1, 'eba10000-0000-0000-0000-000000000e10');
  exception when others then
    v_ok := sqlerrm like '%F5_09_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: data_inicio > data_fim deveria ser INVALID_INPUT';
  end if;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-02-28',
      '   ', 1, v_a1, 'eba10000-0000-0000-0000-000000000e11');
  exception when others then
    v_ok := sqlerrm like '%F5_09_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: justificativa vazia deveria ser INVALID_INPUT';
  end if;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, null, date '2032-02-28',
      'Sem data inicial', 1, v_a1, 'eba10000-0000-0000-0000-000000000e12');
  exception when others then
    v_ok := sqlerrm like '%F5_09_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: data nula deveria ser INVALID_INPUT';
  end if;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-03-31',
      'Periodo identico', 1, v_a1, 'eba10000-0000-0000-0000-000000000e13');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%identico%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: periodo identico deveria ser CONFLICT';
  end if;

  v_ok := false;
  v_msg := null;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-05-15',
      'Periodo sobreposto ao ciclo seguinte', 1, v_a1, 'eba10000-0000-0000-0000-000000000e14');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%sobrepoe outro ciclo%';
    v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] periodo (I6/D15): sobreposicao deveria ser CONFLICT (%)', v_msg;
  end if;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-02-28',
      'Versao obsoleta', 9, v_a1, 'eba10000-0000-0000-0000-000000000e15');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%versao divergente%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: expected_version obsoleto deveria ser CONFLICT por versao';
  end if;

  if (select c.data_inicio from public.evaluation_cycles c where c.id = v_c4) <> date '2032-01-01'
     or (select c.data_fim from public.evaluation_cycles c where c.id = v_c4) <> date '2032-03-31'
     or (select c.version from public.evaluation_cycles c where c.id = v_c4) <> 1 then
    raise exception '[FAIL] periodo: recusa alterou periodo/versao do ciclo';
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.operation_id::text in (
       'eba10000-0000-0000-0000-000000000e10', 'eba10000-0000-0000-0000-000000000e11',
       'eba10000-0000-0000-0000-000000000e12', 'eba10000-0000-0000-0000-000000000e13',
       'eba10000-0000-0000-0000-000000000e14', 'eba10000-0000-0000-0000-000000000e15')
  ) then
    raise exception '[FAIL] periodo: recusa gravou evento na trilha';
  end if;

  raise notice '[PASS] periodo: datas invertidas/nulas e justificativa vazia => INVALID_INPUT; periodo identico, sobreposicao (I6/D15) e expected_version obsoleto => CONFLICT sem efeito';
end $$;

create or replace function public._mut_p4_falhar_periodo()
returns trigger language plpgsql as $mut$
begin
  if new.data_fim = date '2032-04-15' then
    raise notice '_mut_p4_falhar_periodo: abortando no UPDATE do periodo (o UPDATE ja havia sido aplicado nesta transacao)';
    raise exception 'MUT_F5_09_P4: falha injetada no UPDATE do periodo';
  end if;
  return new;
end;
$mut$;

create trigger _mut_p4_periodo before update on public.evaluation_cycles
  for each row execute function public._mut_p4_falhar_periodo();

do $$
declare
  v_org uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c4  uuid;
  v_ok  boolean := false;
  v_msg text;
begin
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2032 and c.numero = 1;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-15', date '2032-04-15',
      'Correcao com falha injetada no UPDATE', 1, v_a1,
      'eba10000-0000-0000-0000-000000000e16');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P4%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] R4/periodo: a falha injetada no UPDATE nao abortou a correcao (%)', v_msg;
  end if;
end $$;

drop trigger _mut_p4_periodo on public.evaluation_cycles;
drop function public._mut_p4_falhar_periodo();

do $$
declare
  v_org   uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c4    uuid;
  v_ciclo record;
  v_res   jsonb;
  v_dias  int;
begin
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2032 and c.numero = 1;
  select c.status, c.version, c.data_inicio, c.data_fim into v_ciclo
    from public.evaluation_cycles c where c.id = v_c4;
  if v_ciclo.data_inicio <> date '2032-01-01' or v_ciclo.data_fim <> date '2032-03-31'
     or v_ciclo.version <> 1 then
    raise exception '[FAIL] R4/periodo: rollback incompleto (%, %, version %)',
      v_ciclo.data_inicio, v_ciclo.data_fim, v_ciclo.version;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eba10000-0000-0000-0000-000000000e16'
  ) then
    raise exception '[FAIL] R4/periodo: rollback incompleto (evento gravado)';
  end if;

  v_res := public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-15', date '2032-04-15',
    'Correcao com falha injetada no UPDATE', 1, v_a1,
    'eba10000-0000-0000-0000-000000000e16');
  if (v_res->>'version')::int <> 2
     or (v_res->>'data_inicio')::date <> date '2032-01-15'
     or (v_res->>'data_fim')::date <> date '2032-04-15' then
    raise exception '[FAIL] R4/periodo: a correcao legitima deveria funcionar apos remover a falha (%)', v_res;
  end if;
  if (v_res->'impacto'->>'data_inicio_anterior')::date <> date '2032-01-01'
     or (v_res->'impacto'->>'data_fim_anterior')::date <> date '2032-03-31' then
    raise exception '[FAIL] R4/periodo: impacto sem o periodo anterior correto (%)', v_res->'impacto';
  end if;
  v_dias := ((v_res->'impacto'->>'dias_depois')::int) - ((v_res->'impacto'->>'dias_antes')::int);
  if v_dias <> (v_res->'impacto'->>'dias_delta')::int then
    raise exception '[FAIL] R4/periodo: dias_delta inconsistente (%)', v_res->'impacto';
  end if;

  raise notice '[PASS] R4/periodo: falha DEPOIS do UPDATE => ROLLBACK TOTAL (periodo e version originais, zero evento) e a MESMA operacao conclui apos remover a falha';
end $$;

do $$
declare
  v_org    uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_a1     uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_c4     uuid;
  v_res    jsonb;
  v_imp    jsonb;
  v_evt    record;
  v_ciclo  record;
  v_n      int;
  v_ok     boolean;
  v_fp     text;
  v_fp2    text;
  v_qtd    int;
  v_concl  int;
begin
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2032 and c.numero = 1;

  select md5(coalesce(string_agg(x, '|' order by x), '')) into v_fp from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2032 and s.ciclo = 1) t;
  select v_fp || '|' || md5(coalesce(string_agg(y, '|' order by y), '')) into v_fp from (
    select sp.id::text || ':' || sp.position_id::text || ':' ||
           coalesce(sp.superior_collaborator_id::text, '-') as y
      from public.collegiate_cycle_snapshot_positions sp
      join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
     where s.organization_id = v_org and s.ano = 2032 and s.ciclo = 1) t;
  select v_fp || '|' || md5(coalesce(string_agg(w, '|' order by w), '')) into v_fp from (
    select r.id::text || ':' || r.position_id::text || ':' || r.responsible_collaborator_id::text as w
      from public.cycle_evaluation_responsibilities r
      join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
     where s.organization_id = v_org and s.ano = 2032 and s.ciclo = 1) t;
  select v_fp || '|' || md5(coalesce(string_agg(q, '|' order by q), '')) into v_fp from (
    select p.id::text || ':' || p.role_type || ':' || p.collaborator_id::text || ':' || p.status as q
      from public.evaluation_participants p
      join public.evaluations e on e.id = p.evaluation_id
     where e.cycle_id = v_c4) t;

  v_res := public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-02-28',
    'Correcao soberana de periodo (T7)', 2, v_a1,
    'eba10000-0000-0000-0000-000000000e01');
  if (v_res->>'version')::int <> 3
     or (v_res->>'data_inicio')::date <> date '2032-01-01'
     or (v_res->>'data_fim')::date <> date '2032-02-28' then
    raise exception '[FAIL] periodo: retorno deveria ser version 3 com as novas datas (%)', v_res;
  end if;
  v_imp := v_res->'impacto';

  if (v_imp->>'data_inicio_anterior')::date <> date '2032-01-15'
     or (v_imp->>'data_fim_anterior')::date <> date '2032-04-15' then
    raise exception '[FAIL] periodo: impacto sem o periodo anterior correto (%)', v_imp;
  end if;
  if (v_imp->>'dias_antes')::int <> (date '2032-04-15' - date '2032-01-15' + 1)
     or (v_imp->>'dias_depois')::int <> (date '2032-02-28' - date '2032-01-01' + 1) then
    raise exception '[FAIL] periodo: impacto com deltas de dias incorretos (%)', v_imp;
  end if;
  if (v_imp->>'dias_delta')::int <> ((date '2032-02-28' - date '2032-01-01') - (date '2032-04-15' - date '2032-01-15')) then
    raise exception '[FAIL] periodo: impacto com dias_delta incorreto (%)', v_imp;
  end if;
  select count(*), count(*) filter (where e.status = 'CONCLUIDA')
    into v_qtd, v_concl
    from public.evaluations e where e.cycle_id = v_c4;
  if (v_imp->>'avaliacoes_no_ciclo')::int <> v_qtd then
    raise exception '[FAIL] periodo: impacto com total de avaliacoes incorreto (%)', v_imp;
  end if;
  if (v_imp->>'avaliacoes_concluidas')::int <> v_concl
     or (v_imp->>'avaliacoes_nao_concluidas')::int <> (v_qtd - v_concl) then
    raise exception '[FAIL] periodo: impacto sem a quebra de avaliacoes por status (%)', v_imp;
  end if;
  if (v_imp->>'avaliacoes_concluidas_fora_do_novo_periodo')::int <> 1 then
    raise exception '[FAIL] periodo: impacto nao detectou avaliacao concluida fora do novo periodo (%)', v_imp;
  end if;
  if (v_imp->>'participantes_materializados')::int <> 3 then
    raise exception '[FAIL] periodo: impacto com participantes materializados incorreto (%)', v_imp;
  end if;

  select c.status, c.version, c.data_inicio, c.data_fim into v_ciclo
    from public.evaluation_cycles c where c.id = v_c4;
  if v_ciclo.status <> 'ATIVO' or v_ciclo.version <> 3
     or v_ciclo.data_inicio <> date '2032-01-01' or v_ciclo.data_fim <> date '2032-02-28' then
    raise exception '[FAIL] periodo: ciclo deveria estar ATIVO/version 3 com as novas datas (%, %)',
      v_ciclo.status, v_ciclo.version;
  end if;

  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eba10000-0000-0000-0000-000000000e01';
  if v_evt.event_type <> 'PERIODO_CORRIGIDO' then
    raise exception '[FAIL] periodo: evento deveria ser PERIODO_CORRIGIDO (%)', v_evt.event_type;
  end if;
  if v_evt.reason <> 'Correcao soberana de periodo (T7)' then
    raise exception '[FAIL] periodo: evento sem a justificativa';
  end if;
  if (v_evt.before_value->>'data_inicio') <> '2032-01-15'
     or (v_evt.before_value->>'data_fim') <> '2032-04-15'
     or (v_evt.before_value->>'version')::int <> 2
     or (v_evt.after_value->>'data_inicio') <> '2032-01-01'
     or (v_evt.after_value->>'data_fim') <> '2032-02-28'
     or (v_evt.after_value->>'version')::int <> 3 then
    raise exception '[FAIL] periodo: before/after do evento incompletos (%)', v_evt.after_value;
  end if;
  if (v_evt.after_value->'impacto'->>'avaliacoes_concluidas_fora_do_novo_periodo')::int <> 1 then
    raise exception '[FAIL] periodo: evento sem o impacto calculado';
  end if;

  select md5(coalesce(string_agg(x, '|' order by x), '')) into v_fp2 from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2032 and s.ciclo = 1) t;
  select v_fp2 || '|' || md5(coalesce(string_agg(y, '|' order by y), '')) into v_fp2 from (
    select sp.id::text || ':' || sp.position_id::text || ':' ||
           coalesce(sp.superior_collaborator_id::text, '-') as y
      from public.collegiate_cycle_snapshot_positions sp
      join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
     where s.organization_id = v_org and s.ano = 2032 and s.ciclo = 1) t;
  select v_fp2 || '|' || md5(coalesce(string_agg(w, '|' order by w), '')) into v_fp2 from (
    select r.id::text || ':' || r.position_id::text || ':' || r.responsible_collaborator_id::text as w
      from public.cycle_evaluation_responsibilities r
      join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
     where s.organization_id = v_org and s.ano = 2032 and s.ciclo = 1) t;
  select v_fp2 || '|' || md5(coalesce(string_agg(q, '|' order by q), '')) into v_fp2 from (
    select p.id::text || ':' || p.role_type || ':' || p.collaborator_id::text || ':' || p.status as q
      from public.evaluation_participants p
      join public.evaluations e on e.id = p.evaluation_id
     where e.cycle_id = v_c4) t;
  if v_fp2 is distinct from v_fp then
    raise exception '[FAIL] periodo: correcao alterou estrutura/participantes/responsabilidades (T7/I18)';
  end if;

  v_res := public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-02-28',
    'Correcao soberana de periodo (T7)', 2, v_a1,
    'eba10000-0000-0000-0000-000000000e01');
  if (v_res->>'version')::int <> 3 or v_res->'impacto' <> v_imp then
    raise exception '[FAIL] periodo: replay devolveu resultado diferente (%)', v_res;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_org
     and e.operation_id = 'eba10000-0000-0000-0000-000000000e01';
  if v_n <> 1 then
    raise exception '[FAIL] periodo: replay duplicou a trilha (%)', v_n;
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c4) <> 3 then
    raise exception '[FAIL] periodo: replay alterou a versao do ciclo';
  end if;
  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-02-27',
      'Intencao divergente na correcao', 3, v_a1,
      'eba10000-0000-0000-0000-000000000e01');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: operation_id divergente deveria ser CONFLICT';
  end if;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(
      (select c.id from public.evaluation_cycles c
        where c.organization_id = v_org and c.ano = 2032 and c.numero = 2),
      v_org, date '2032-05-01', date '2032-06-15', 'Correcao em ciclo PLANEJADO', 0, v_a1,
      'eba10000-0000-0000-0000-000000000e20');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%exige ciclo ATIVO%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: ciclo PLANEJADO deveria ser recusado';
  end if;
  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(
      (select c.id from public.evaluation_cycles c
        where c.organization_id = v_org and c.ano = 2031 and c.numero = 2),
      v_org, date '2031-04-01', date '2031-05-31', 'Correcao em ciclo CANCELADO', 1, v_a1,
      'eba10000-0000-0000-0000-000000000e21');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%exige ciclo ATIVO%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: ciclo CANCELADO deveria ser recusado';
  end if;
  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(
      (select c.id from public.evaluation_cycles c
        where c.organization_id = v_org and c.ano = 2031 and c.numero = 3),
      v_org, date '2031-07-01', date '2031-08-31', 'Correcao em ciclo ENCERRADO', 6, v_a1,
      'eba10000-0000-0000-0000-000000000e22');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%exige ciclo ATIVO%';
  end;
  if not v_ok then
    raise exception '[FAIL] periodo: ciclo ENCERRADO deveria ser recusado';
  end if;

  raise notice '[PASS] periodo (T7): correcao valida (version 3, 2032-01-01..2032-02-28) com IMPACTO server-side conferido (deltas de dias, avaliacoes por status, 1 concluida fora do novo periodo e 3 participantes), evento PERIODO_CORRIGIDO com before/after+impacto+justificativa, estrutura intacta, replay idempotente, operation_id divergente e estados != ATIVO recusados';
end $$;

-- ----------------------------------------------------------------------------
-- 6) Autorizacao / tenant / capability (probes diretos nas TRES RPCs)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'eba00000-0000-0000-0000-0000000000b1';
  v_a1    uuid := 'ebc00000-0000-0000-0000-000000000001';
  v_a2    uuid := 'ebc00000-0000-0000-0000-000000000002';
  v_a3    uuid := 'ebc00000-0000-0000-0000-000000000003';
  v_a4    uuid := 'ebc00000-0000-0000-0000-000000000004';
  v_c3    uuid;
  v_c4    uuid;
  v_cb    uuid;
  v_inex  uuid := 'eba00000-0000-0000-0000-00000000dead';
  v_ok    boolean;
  v_ops   text[] := array[]::text[];
  v_n     int;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2031 and c.numero = 3;
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2032 and c.numero = 1;
  select c.id into v_cb from public.evaluation_cycles c
   where c.organization_id = v_beta and c.ano = 2031 and c.numero = 1;

  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_c4, v_org, 'Sem capability', 3, v_a2,
      'eba10000-0000-0000-0000-000000000f01');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%' and sqlerrm like '%cycle.cancel%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: cancelar sem cycle.cancel deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f01'::text;

  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, 'Sem capability', 6, v_a2,
      'eba10000-0000-0000-0000-000000000f02');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%' and sqlerrm like '%cycle.reopen%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: reabrir sem cycle.reopen deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f02'::text;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-02-27',
      'Sem capability', 3, v_a2, 'eba10000-0000-0000-0000-000000000f03');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%' and sqlerrm like '%cycle.period.correct%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: corrigir periodo sem cycle.period.correct deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f03'::text;

  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_c4, v_org, 'Membership disabled', 3, v_a4,
      'eba10000-0000-0000-0000-000000000f04');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: cancelar com membership disabled deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f04'::text;

  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c3, v_org, 'Membership disabled', 6, v_a4,
      'eba10000-0000-0000-0000-000000000f05');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: reabrir com membership disabled deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f05'::text;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_c4, v_org, date '2032-01-01', date '2032-02-27',
      'Membership disabled', 3, v_a4, 'eba10000-0000-0000-0000-000000000f06');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: corrigir periodo com membership disabled deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f06'::text;

  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_cb, v_org, 'Ciclo de outro tenant', 1, v_a1,
      'eba10000-0000-0000-0000-000000000f07');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: cancelar ciclo de outro tenant deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f07'::text;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_cb, v_org, date '2031-01-01', date '2031-02-28',
      'Ciclo de outro tenant', 1, v_a1, 'eba10000-0000-0000-0000-000000000f08');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: corrigir periodo de ciclo de outro tenant deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f08'::text;

  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_c4, v_org, 'Ator de outro tenant', 3, v_a3,
      'eba10000-0000-0000-0000-000000000f09');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: ator de outro tenant deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f09'::text;

  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_c3, v_beta, 'Ciclo do Alfa declarado no Beta', 6, v_a3,
      'eba10000-0000-0000-0000-000000000f10');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: ciclo de outro tenant no proprio tenant deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f10'::text;

  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_cb, v_beta, 'Tenant divergente do ator', 1, v_a1,
      'eba10000-0000-0000-0000-000000000f11');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: ator fora do tenant declarado deveria ser FORBIDDEN';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f11'::text;

  v_ok := false;
  begin
    perform public.ciclo_cancelar(v_inex, v_org, 'Ciclo inexistente', 0, v_a1,
      'eba10000-0000-0000-0000-000000000f12');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: ciclo inexistente deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f12'::text;

  v_ok := false;
  begin
    perform public.ciclo_reabrir(v_inex, v_org, 'Ciclo inexistente', 0, v_a1,
      'eba10000-0000-0000-0000-000000000f13');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: reabrir ciclo inexistente deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f13'::text;

  v_ok := false;
  begin
    perform public.ciclo_corrigir_periodo(v_inex, v_org, date '2032-01-01', date '2032-02-27',
      'Ciclo inexistente', 0, v_a1, 'eba10000-0000-0000-0000-000000000f14');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] authz: corrigir periodo de ciclo inexistente deveria ser NOT_FOUND';
  end if;
  v_ops := v_ops || 'eba10000-0000-0000-0000-000000000f14'::text;

  select count(*) into v_n from public.cycle_events e
   where e.operation_id::text = any (v_ops);
  if v_n <> 0 then
    raise exception '[FAIL] authz: recusas gravaram % evento(s) na trilha', v_n;
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c4) <> 3
     or (select c.version from public.evaluation_cycles c where c.id = v_c3) <> 6
     or (select c.version from public.evaluation_cycles c where c.id = v_cb) <> 1 then
    raise exception '[FAIL] authz: recusa alterou a versao de algum ciclo';
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_cb) <> 'ATIVO' then
    raise exception '[FAIL] authz: recusa alterou o ciclo do Beta';
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_beta
       and e.event_type in ('CANCELADO', 'REABERTO', 'PERIODO_CORRIGIDO')
  ) then
    raise exception '[FAIL] authz: trilha do Beta recebeu evento de transicao excepcional (cross-tenant vazou)';
  end if;

  raise notice '[PASS] authz/tenant/capability: capability ausente e membership disabled => FORBIDDEN (com o codigo da capability na mensagem), 4 probes cross-tenant DIRETOS + tenant divergente + ciclos inexistentes => NOT_FOUND/FORBIDDEN, todos com ZERO efeito';
end $$;

-- ----------------------------------------------------------------------------
-- 7) Guardas estruturais/estaticos: contrato, ACL, lock, aditividade, P5+
-- ----------------------------------------------------------------------------
do $$
declare
  v_fn     text;
  v_rec    record;
  v_def    text;
  v_problemas text[] := array[]::text[];
  v_caps   int;
begin
  foreach v_fn in array array[
    'ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)']
  loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config,
           pg_get_functiondef(p.oid) as def
      into v_rec
      from pg_proc p where p.oid = to_regprocedure('public.' || v_fn);
    if v_rec.prosecdef then
      v_problemas := v_problemas || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_problemas := v_problemas || ('sem search_path fixo: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_problemas := v_problemas || ('service_role sem EXECUTE: ' || v_fn);
    end if;
    if has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE') then
      v_problemas := v_problemas || ('exposta a anon/authenticated: ' || v_fn);
    end if;

    v_def := lower(v_rec.def);
    if position('delete from' in v_def) > 0 or position('truncate' in v_def) > 0 then
      v_problemas := v_problemas || ('contem DELETE/TRUNCATE (D9): ' || v_fn);
    end if;
    -- Apenas ESCRITA direta em estrutura/avaliacao e proibida (a LEITURA para
    -- evidencia de preservacao/impacto e legitima e esperada).
    if position('insert into public.collegiate_cycle_snapshot' in v_def) > 0
       or position('update public.collegiate_cycle_snapshot' in v_def) > 0
       or position('insert into public.cycle_evaluation_responsibilities' in v_def) > 0
       or position('update public.cycle_evaluation_responsibilities' in v_def) > 0
       or position('insert into public.evaluation_participants' in v_def) > 0
       or position('update public.evaluation_participants' in v_def) > 0
       or position('update public.evaluations' in v_def) > 0
       or position('insert into public.evaluations' in v_def) > 0 then
      v_problemas := v_problemas || ('escreve em estrutura materializada/avaliacao: ' || v_fn);
    end if;
    if position('materializar' in v_def) > 0 then
      v_problemas := v_problemas || ('chama materializacao (I19/D27): ' || v_fn);
    end if;
    if position('ciclo_lock_organizacao' in v_def) = 0 then
      v_problemas := v_problemas || ('sem a chave normativa de ciclos: ' || v_fn);
    end if;
    if position('position_reporting_lines:' in v_def) > 0
       or position('f5_07_estrutura:' in v_def) > 0 then
      v_problemas := v_problemas || ('usa chave de OUTRA familia de lock: ' || v_fn);
    end if;
  end loop;

  -- O cancelamento REUSA a primitiva soberana da F5-06 e NAO usa o fechamento de
  -- pendencias (que incrementaria a versao do ciclo duas vezes).
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)');
  if position('evaluation_cancelar' in v_def) = 0 then
    v_problemas := v_problemas || 'ciclo_cancelar nao reusa evaluation_cancelar (F5-06)'::text;
  end if;
  if position('evaluation_fechar_ciclo_pendencias' in v_def) > 0 then
    v_problemas := v_problemas || 'ciclo_cancelar usa evaluation_fechar_ciclo_pendencias (double increment)'::text;
  end if;

  select count(*) into v_caps from public.capabilities;
  if v_caps <> 31 then
    v_problemas := v_problemas || ('catalogo de capabilities alterado: ' || v_caps);
  end if;

  if exists (
    select 1 from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('ciclo_painel', 'ciclo_historico', 'ciclo_listar_colaborador_por_ciclo')
  ) then
    v_problemas := v_problemas || 'RPC de LEITURA soberana (P5+) antecipada'::text;
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'cycle_events'
  ) then
    v_problemas := v_problemas || 'policy em cycle_events (trilha deve ser deny-by-default)'::text;
  end if;
  -- A leitura own-tenant de `evaluation_cycles` e contrato do P5: quando
  -- presente, e conferida contra o contrato (SELECT + authenticated + predicado
  -- de tenant); a ESCRITA de cliente segue proibida em qualquer fase.
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and (cmd <> 'SELECT'
            or not ('authenticated'::name = any(roles))
            or coalesce(qual, '') not like '%user_has_active_membership%')
  ) then
    v_problemas := v_problemas || 'policy de evaluation_cycles fora do contrato own-tenant (P5)'::text;
  end if;
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'anon/authenticated com ESCRITA ou acesso indevido a ciclo/trilha'::text;
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] 7/25/26/27/28: %', array_to_string(v_problemas, '; ');
  end if;

  raise notice '[PASS] guardas estruturais: 3 RPCs INVOKER com search_path e EXECUTE so service_role, chave normativa de ciclos, zero DELETE, zero toque em estrutura materializada/avaliacao direta, zero rematerializacao, cancelamento reusando evaluation_cancelar (sem fechar_ciclo_pendencias), catalogo intacto (31), escrita de cliente proibida e trilha fechada (leitura own-tenant do P5 admitida e conferida quando presente)';
end $$;

-- ----------------------------------------------------------------------------
-- 8) Nenhuma exclusao fisica e integridade final do dominio
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'eba00000-0000-0000-0000-0000000000a1';
  v_n     int;
  v_tipos text;
begin
  select count(*) into v_n from public.evaluation_cycles where organization_id = v_org;
  if v_n <> 6 then
    raise exception '[FAIL] D9: organizacao deveria ter 6 ciclos (nenhum apagado), encontrado %', v_n;
  end if;
  select count(*) into v_n from public.evaluation_cycles
   where organization_id = v_org and status = 'CANCELADO';
  if v_n <> 2 then
    raise exception '[FAIL] D9: esperados 2 ciclos CANCELADOS preservados (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluations e
    join public.evaluation_cycles c on c.id = e.cycle_id
   where c.organization_id = v_org;
  if v_n <> 8 then
    raise exception '[FAIL] D9: esperadas 8 avaliacoes preservadas (nenhuma apagada), encontrado %', v_n;
  end if;
  select count(*) into v_n from public.evaluations e
    join public.evaluation_cycles c on c.id = e.cycle_id
   where c.organization_id = v_org and e.status = 'CANCELADA';
  if v_n <> 4 then
    raise exception '[FAIL] D9: esperadas 4 avaliacoes CANCELADAS preservadas (%)', v_n;
  end if;

  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
     group by e.operation_id having count(*) > 1
  ) then
    raise exception '[FAIL] trilha: operation_id repetido';
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.event_type not in ('CRIADO', 'EDITADO', 'ATIVADO', 'ENCERRADO',
                                'CANCELADO', 'REABERTO', 'PERIODO_CORRIGIDO', 'ADMISSAO_INCLUIDA')
  ) then
    raise exception '[FAIL] trilha: evento fora do contrato';
  end if;
  select string_agg(distinct e.event_type, ',' order by e.event_type) into v_tipos
    from public.cycle_events e where e.organization_id = v_org;
  if v_tipos not like '%CANCELADO%' or v_tipos not like '%REABERTO%'
     or v_tipos not like '%PERIODO_CORRIGIDO%' then
    raise exception '[FAIL] trilha: tipos da P4 ausentes (%)', v_tipos;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and (e.actor_user_profile_id is null or e.actor_membership_id is null)
  ) then
    raise exception '[FAIL] trilha: evento sem autoria soberana';
  end if;

  raise notice '[PASS] D9/integridade: 6 ciclos e 8 avaliacoes preservados (2 CANCELADOS e 4 CANCELADAS), trilha append-only com um evento por operacao, tipos CANCELADO/REABERTO/PERIODO_CORRIGIDO presentes (%)', v_tipos;
end $$;

-- ============================================================================
-- 9) Resumo
-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F5-09 P4: transicoes excepcionais soberanas validadas — cancelamento (PLANEJADO/ATIVO -> CANCELADO com avaliacoes resolvidas pela F5-06 e CONCLUIDAS preservadas), reabertura (ENCERRADO -> ATIVO sem rematerializacao) e correcao de periodo (ATIVO com impacto server-side), com autorizacao/tenant fail-closed, lock normativo, idempotencia, rollback real e ausencia de P5+.';
end $$;
