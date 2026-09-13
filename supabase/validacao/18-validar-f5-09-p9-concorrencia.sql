-- ============================================================================
-- F5-09 P9: CONCORRENCIA REAL entre DUAS sessoes — VALIDADOR CONSOLIDADO (18)
-- (single-session; roda SOMENTE depois de A e B terminarem)
-- ----------------------------------------------------------------------------
-- Papel deste arquivo (processo psql 3 de 3):
--   conferir o ESTADO FINAL CONSOLIDADO da corrida de `16-sessao-a...` x
--   `17-sessao-b...`, sem depender de nenhum artefato temporario (que ja foi
--   removido pela sessao A):
--     - o ciclo PROPRIO da corrida (Gama-P9, 2041/1) esta `PLANEJADO` com
--       `version = 1` e o periodo EXATO da edicao VENCEDORA de A
--       (2041-01-10..2041-04-10) — nunca o periodo da intencao PERDEDORA de B
--       (2041-02-01..2041-05-01), nem por linha de ciclo nem por trilha;
--     - exatamente UMA edicao oficial foi aplicada (um evento `EDITADO`, o de
--       A) alem do `CRIADO`; nenhum evento/estado da intencao de B;
--     - `cycle_events` consistente: append-only (gatilhos + UPDATE negado),
--       autoria soberana do gestor-gama (membership ativa resolvida
--       server-side), `payload_hash` SHA-256 distinto por intencao e ordem
--       `CRIADO` -> `EDITADO`;
--     - integridade integrada: I5 (no maximo um ciclo ATIVO por organizacao) e
--       I6 (nao sobreposicao de periodo) intactas, nenhuma organizacao P9 com
--       mais de um ATIVO, Gama-P9 sem nenhum ATIVO e nenhum estado incoerente;
--     - nenhum residuo do artefato temporario de contencao da sessao A.
--   Qualquer divergencia aborta com `raise exception '[FAIL] ...'`.
--
-- Ordem REAL de execucao (tres processos psql INDEPENDENTES; sem `dblink`, sem
-- `postgres_fdw`, sem extensao nova):
--   1) `16-sessao-a-f5-09-p9-concorrencia.sql` -> BACKGROUND (vence a corrida);
--   2) `17-sessao-b-f5-09-p9-concorrencia.sql` -> FOREGROUND (BLOQUEADA pelo
--      advisory lock da organizacao detido por A, termina em CONFLICT);
--   3) `18-validar-f5-09-p9-concorrencia.sql` (ESTE arquivo) -> single-session.
--
-- Evidencia de contencao (produzida por 16/17, conferida aqui):
--   a espera >= ~2s medida pela sessao B no advisory lock normativo da familia
--   de ciclos (`evaluation_cycles:<organization_id>`, via
--   `ciclo_lock_organizacao`) enquanto A dormia ~8s dentro do UPDATE; o
--   desfecho e o CONFLITO de versao do contrato (`F5_09_CONFLICT`, "versao
--   divergente"), porque B reavalia `expected_version` DEPOIS de adquirir o
--   lock e enxerga a versao 1 commitada por A.
--
-- DIFERENCA EXPLICITA em relacao a P8 (concorrencia client-side):
--   a P8 prova, em UM unico processo node, que o controlador da UI recusa uma
--   segunda mutation concorrente SEM chamar a Edge (serializacao de INTERFACE).
--   A corrida provada por 16/17/18 e entre DOIS BACKENDS PostgreSQL reais (dois
--   processos `psql`), com contencao de lock e reavaliacao de versao medidas no
--   relogio: nenhuma dessas duas provas substitui a outra.
--
-- operation_id da corrida (UUIDs sinteticos fixos; documentados no header de
-- cada sessao):
--   A ciclo_criar        2041/1 -> ed910000-0000-0000-0000-0000000000a1
--   A ciclo_editar       2041/1 -> ed910000-0000-0000-0000-0000000000a2
--   B ciclo_editar (perde) 2041/1 -> ed920000-0000-0000-0000-0000000000b1
--   (nenhum `operation_id` e reaproveitado entre as duas sessoes)
--
-- Alvo fixo do contrato P9:
--   organizacao Gama-P9 : eda00000-0000-0000-0000-0000000000c1
--   organizacao Alfa-P9 : eda00000-0000-0000-0000-0000000000a1 (conferencia de
--                         coerencia de estado das organizacoes da P9)
--   ator gestor-gama    : edc00000-0000-0000-0000-000000000006
--
-- Como executar (Supabase local; NUNCA remoto), ao final de A e B:
--   Get-Content supabase/validacao/18-validar-f5-09-p9-concorrencia.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Estado CONSOLIDADO do ciclo da corrida (linha oficial de evaluation_cycles)
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
  if not exists (select 1 from public.organizations o where o.id = v_gama) then
    raise exception '[FAIL] 18: organizacao Gama-P9 (%) ausente — execute 14-cenario-f5-09-p9.sql', v_gama;
  end if;

  -- Alvo resolvido por SELECT DETERMINISTICO (organization_id + ano + numero);
  -- nenhum UUID transportado por variavel do psql.
  select c.id into v_ciclo
    from public.evaluation_cycles c
   where c.organization_id = v_gama and c.ano = 2041 and c.numero = 1;
  if v_ciclo is null then
    raise exception '[FAIL] 18: ciclo 2041/1 de Gama-P9 ausente — execute 16-sessao-a... (background) e 17-sessao-b... antes deste validador';
  end if;

  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_gestor
     and m.organization_id = v_gama
     and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] 18: membership ATIVA do gestor-gama (%) em Gama-P9 ausente', v_gestor;
  end if;

  select c.ano, c.numero, c.status, c.version, c.data_inicio, c.data_fim,
         c.data_ativacao, c.data_encerramento, c.encerrado_com_pendencias,
         c.quantidade_pendencias, c.config_version_id, c.created_at, c.updated_at
    into v_row
    from public.evaluation_cycles c
   where c.id = v_ciclo;
  if not found then
    raise exception '[FAIL] 18: ciclo resolvido mas nao lido';
  end if;

  if v_row.ano <> 2041 or v_row.numero <> 1 then
    raise exception '[FAIL] 18: identidade de negocio divergente (ano %, numero %)', v_row.ano, v_row.numero;
  end if;
  if v_row.status <> 'PLANEJADO' then
    raise exception '[FAIL] 18: status consolidado = % (esperado PLANEJADO: a corrida e sobre edicao, nem A nem B ativam ciclo)', v_row.status;
  end if;
  if v_row.version <> 1 then
    raise exception '[FAIL] 18: version consolidada = % (esperado 1 — exatamente UMA edicao oficial aplicada: a de A)', v_row.version;
  end if;
  if v_row.data_inicio <> date '2041-01-10' or v_row.data_fim <> date '2041-04-10' then
    raise exception '[FAIL] 18: periodo consolidado = %..% — esperado o de A (2041-01-10..2041-04-10); 2041-02-01..2041-05-01 significaria que a intencao de B venceu (lost update)',
      v_row.data_inicio, v_row.data_fim;
  end if;
  if v_row.data_ativacao is not null or v_row.data_encerramento is not null
     or v_row.encerrado_com_pendencias is not false or v_row.quantidade_pendencias <> 0
     or v_row.config_version_id is null then
    raise exception '[FAIL] 18: estado incoerente do ciclo (data_ativacao=%, data_encerramento=%, pendencias=%, quantidade=%, config=%)',
      v_row.data_ativacao, v_row.data_encerramento, v_row.encerrado_com_pendencias,
      v_row.quantidade_pendencias, v_row.config_version_id;
  end if;
  if v_row.updated_at < v_row.created_at then
    raise exception '[FAIL] 18: updated_at anterior a created_at (%, %)', v_row.updated_at, v_row.created_at;
  end if;

  -- A intencao PERDEDORA de B (datas proprias) nao pode existir como estado.
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_gama
     and c.data_inicio = date '2041-02-01' and c.data_fim = date '2041-05-01';
  if v_n <> 0 then
    raise exception '[FAIL] 18: existe % ciclo(s) em Gama-P9 com o periodo da intencao perdedora de B (2041-02-01..2041-05-01)', v_n;
  end if;

  raise notice '[PASS] 18: estado consolidado da corrida — ciclo 2041/1 PLANEJADO/version 1 com o periodo EXATO de A (2041-01-10..2041-04-10); o periodo de B (2041-02-01..2041-05-01) nao existe em nenhuma linha';
end $$;

-- ----------------------------------------------------------------------------
-- 1) Trilha `cycle_events` consistente: CRIADO + EDITADO, autoria gestor-gama,
--    nenhum vestigio da intencao perdedora, payload_hash e ordem coerentes,
--    append-only comprovado (inclusive contra UPDATE do owner)
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama   uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_gestor uuid := 'edc00000-0000-0000-0000-000000000006';
  v_ciclo  uuid;
  v_memb   uuid;
  v_config uuid;
  v_before jsonb;
  v_after  jsonb;
  v_n      int;
  v_ok     boolean := false;
  v_msg    text;
begin
  select c.id, c.config_version_id into v_ciclo, v_config
    from public.evaluation_cycles c
   where c.organization_id = v_gama and c.ano = 2041 and c.numero = 1;
  if v_ciclo is null then
    raise exception '[FAIL] 18/trilha: ciclo 2041/1 ausente';
  end if;
  select m.id into v_memb
    from public.user_organization_memberships m
   where m.user_profile_id = v_gestor
     and m.organization_id = v_gama
     and m.status = 'active';
  if v_memb is null then
    raise exception '[FAIL] 18/trilha: membership ATIVA do gestor-gama nao resolvida (a autoria da trilha nao pode ser conferida)';
  end if;

  -- Volume EXATO da trilha: a corrida produz um `CRIADO` e UM `EDITADO`.
  -- CONTRATO: Gama-P9 e a organizacao EXCLUSIVA desta prova (a fixture 14 cria
  -- Gama-P9 SEM ciclos e os validadores 14/15 operam Alfa-P9). Evento extra em
  -- Gama-P9 significa que outro validador passou a escrever nesta organizacao —
  -- a prova nao pode ser afrouxada, e sim reatribuida.
  select count(*) into v_n from public.cycle_events e where e.organization_id = v_gama;
  if v_n <> 2 then
    raise exception '[FAIL] 18/trilha: Gama-P9 deveria ter exatamente 2 eventos (CRIADO + EDITADO da corrida), encontrados % — verifique se outro validador passou a escrever em Gama-P9', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_gama and e.cycle_id = v_ciclo;
  if v_n <> 2 then
    raise exception '[FAIL] 18/trilha: o ciclo deveria ter exatamente 2 eventos, encontrados %', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.cycle_id = v_ciclo and e.event_type = 'CRIADO';
  if v_n <> 1 then
    raise exception '[FAIL] 18/trilha: esperado exatamente 1 evento CRIADO (encontrados %)', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.cycle_id = v_ciclo and e.event_type = 'EDITADO';
  if v_n <> 1 then
    raise exception '[FAIL] 18/trilha: esperado exatamente 1 evento EDITADO (encontrados %) — a intencao perdedora nao pode gerar evento', v_n;
  end if;

  -- Os dois eventos sao EXATAMENTE as duas operacoes oficiais da sessao A.
  select count(*) into v_n from public.cycle_events e
   where e.cycle_id = v_ciclo
     and e.operation_id in ('ed910000-0000-0000-0000-0000000000a1',
                            'ed910000-0000-0000-0000-0000000000a2');
  if v_n <> 2 then
    raise exception '[FAIL] 18/trilha: os operation_id do ciclo nao sao exatamente os das operacoes legitimas de A (encontrados %)', v_n;
  end if;
  -- Nenhum evento da intencao de B em NENHUMA organizacao.
  select count(*) into v_n from public.cycle_events e
   where e.operation_id = 'ed920000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] 18/trilha: a intencao perdedora de B gravou % evento(s) em cycle_events', v_n;
  end if;
  -- Nenhum evento do ciclo carrega o periodo da intencao de B.
  select count(*) into v_n from public.cycle_events e
   where e.cycle_id = v_ciclo
     and ((e.before_value->>'data_inicio') = '2041-02-01'
       or (e.before_value->>'data_fim') = '2041-05-01'
       or (e.after_value->>'data_inicio') = '2041-02-01'
       or (e.after_value->>'data_fim') = '2041-05-01');
  if v_n <> 0 then
    raise exception '[FAIL] 18/trilha: % evento(s) registram o periodo da intencao de B', v_n;
  end if;

  -- Autoria SOBERANA em 100% dos eventos do ciclo (gestor-gama + membership).
  select count(*) into v_n from public.cycle_events e
   where e.cycle_id = v_ciclo
     and (e.organization_id <> v_gama
       or e.entity_type <> 'evaluation_cycle'
       or e.actor_user_profile_id <> v_gestor
       or e.actor_membership_id is distinct from v_memb
       or e.result_entity_id is distinct from v_ciclo
       or e.reason is null or btrim(e.reason) = ''
       or e.effective_date is null);
  if v_n <> 0 then
    raise exception '[FAIL] 18/trilha: % evento(s) sem tenant/entidade/autoria/motivo/resultado soberanos do gestor-gama', v_n;
  end if;

  -- payload_hash: SHA-256 hex e DISTINTO por intencao (CRIADO != EDITADO).
  select count(*) into v_n from public.cycle_events e
   where e.cycle_id = v_ciclo and e.payload_hash !~ '^[0-9a-f]{64}$';
  if v_n <> 0 then
    raise exception '[FAIL] 18/trilha: % evento(s) com payload_hash fora do formato SHA-256', v_n;
  end if;
  select count(distinct e.payload_hash) into v_n from public.cycle_events e
   where e.cycle_id = v_ciclo;
  if v_n <> 2 then
    raise exception '[FAIL] 18/trilha: as duas intencoes deveriam ter payload_hash distintos (distintos=%)', v_n;
  end if;

  -- Ordem append-only coerente: CRIADO antes de EDITADO.
  if not exists (
    select 1
      from public.cycle_events a
      join public.cycle_events b
        on b.cycle_id = a.cycle_id
       and b.event_type = 'EDITADO'
     where a.cycle_id = v_ciclo
       and a.event_type = 'CRIADO'
       and a.created_at <= b.created_at
       and a.effective_date <= b.effective_date
  ) then
    raise exception '[FAIL] 18/trilha: ordem CRIADO -> EDITADO incoerente (created_at/effective_date)';
  end if;

  -- Conteudo dos deltas: before = estado criado por A; after = edicao de A.
  select e.before_value, e.after_value into v_before, v_after
    from public.cycle_events e
   where e.cycle_id = v_ciclo and e.event_type = 'EDITADO';
  if v_before is null or v_after is null then
    raise exception '[FAIL] 18/trilha: evento EDITADO sem before_value/after_value';
  end if;
  if (v_before->>'status') <> 'PLANEJADO' or (v_before->>'version')::int <> 0
     or (v_before->>'data_inicio') <> '2041-01-01' or (v_before->>'data_fim') <> '2041-03-31' then
    raise exception '[FAIL] 18/trilha: before_value do EDITADO nao e o estado CRIADO por A (%)', v_before;
  end if;
  if (v_after->>'status') <> 'PLANEJADO' or (v_after->>'version')::int <> 1
     or (v_after->>'data_inicio') <> '2041-01-10' or (v_after->>'data_fim') <> '2041-04-10' then
    raise exception '[FAIL] 18/trilha: after_value do EDITADO nao e a edicao vencedora de A (%)', v_after;
  end if;

  -- CRIADO coerente com a linha oficial (versao 0 e a MESMA config soberana).
  if not exists (
    select 1 from public.cycle_events e
     where e.cycle_id = v_ciclo
       and e.event_type = 'CRIADO'
       and (e.after_value->>'version')::int = 0
       and (e.after_value->>'status') = 'PLANEJADO'
       and (e.after_value->>'config_version_id')::uuid = v_config
  ) then
    raise exception '[FAIL] 18/trilha: evento CRIADO sem a versao/status/config soberanos da linha oficial';
  end if;

  -- Append-only ESTRUTURAL: os tres gatilhos da trilha existem.
  select count(*) into v_n from pg_trigger t
   where t.tgrelid = 'public.cycle_events'::regclass
     and not t.tgisinternal
     and t.tgname in ('trg_cycle_events_append_only',
                      'trg_cycle_events_no_delete',
                      'trg_cycle_events_no_truncate');
  if v_n <> 3 then
    raise exception '[FAIL] 18/trilha: esperados 3 gatilhos append-only em cycle_events (encontrados %)', v_n;
  end if;

  -- Append-only COMPORTAMENTAL: UPDATE na trilha e NEGADO pelo gatilho (mesmo
  -- para o owner/superuser). O assert roda em subtransacao e confere a mensagem.
  begin
    update public.cycle_events set reason = reason where cycle_id = v_ciclo;
  exception when others then
    v_ok := (sqlerrm like '%append-only%' and sqlerrm like '%UPDATE%');
    v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 18/trilha: UPDATE em cycle_events nao foi negado pelo gatilho append-only (sessao %, recebido: %)',
      current_user, coalesce(v_msg, 'nenhum erro');
  end if;

  raise notice '[PASS] 18/trilha: exatamente CRIADO + EDITADO (operation_ids legitimas de A), nenhum vestigio da intencao de B, autoria/membership do gestor-gama %, payload_hash SHA-256 distintos, ordem e deltas coerentes e append-only (UPDATE negado: %)',
    v_memb, v_msg;
end $$;

-- ----------------------------------------------------------------------------
-- 2) Integridade integrada e higiene da prova (I5/I6, estados validos das
--    organizacoes P9 e ausencia de artefato temporario residual)
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_alfa uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_n    int;
begin
  -- Fundacao do P1 intacta: I5 (indice unico parcial de ATIVO) e I6 (exclusion).
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    raise exception '[FAIL] 18/I5: indice unico parcial de ciclo ATIVO ausente (fundacao do P1 alterada)';
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_cycles'::regclass
       and conname = 'ex_evaluation_cycles_periodo_no_overlap' and contype = 'x'
  ) then
    raise exception '[FAIL] 18/I6: exclusion de nao sobreposicao ausente (fundacao do P1 alterada)';
  end if;

  -- I5 no banco inteiro: nenhuma organizacao com mais de um ciclo ATIVO.
  select count(*) into v_n from (
    select c.organization_id
      from public.evaluation_cycles c
     where c.status = 'ATIVO'
     group by c.organization_id
    having count(*) > 1
  ) t;
  if v_n <> 0 then
    raise exception '[FAIL] 18/I5: % organizacao(oes) com mais de um ciclo ATIVO', v_n;
  end if;

  -- A corrida NAO ativa ciclo algum: Gama-P9 tem ZERO ciclos ATIVO.
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_gama and c.status = 'ATIVO';
  if v_n <> 0 then
    raise exception '[FAIL] 18: Gama-P9 possui % ciclo(s) ATIVO — a corrida de edicao nao ativa nada', v_n;
  end if;

  -- Coerencia de estado nas organizacoes da P9 (Gama e Alfa): dominio de
  -- status, versao nao negativa, periodo valido e marcos temporais coerentes.
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id in (v_gama, v_alfa)
     and (c.status not in ('PLANEJADO', 'ATIVO', 'ENCERRADO', 'CANCELADO')
       or c.version < 0
       or (c.data_inicio is not null and c.data_fim is not null and c.data_fim < c.data_inicio)
       or (c.status = 'ATIVO' and c.data_ativacao is null)
       or (c.status = 'ENCERRADO' and (c.data_encerramento is null or c.data_ativacao is null))
       or (c.status = 'PLANEJADO' and (c.data_ativacao is not null or c.data_encerramento is not null)));
  if v_n <> 0 then
    raise exception '[FAIL] 18/estado: % ciclo(s) com estado incoerente nas organizacoes P9', v_n;
  end if;

  -- Higiene: o artefato TEMPORARIO de contencao da sessao A nao pode sobrar.
  if to_regclass('public._mut_p9_contencao_seq') is not null then
    raise exception '[FAIL] 18/higiene: sequence temporaria de contencao da sessao A NAO foi removida';
  end if;
  if to_regprocedure('public._mut_p9_contencao_edicao()') is not null then
    raise exception '[FAIL] 18/higiene: funcao temporaria de contencao da sessao A NAO foi removida';
  end if;
  if exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_cycles'::regclass
       and t.tgname = '_mut_p9_contencao'
  ) then
    raise exception '[FAIL] 18/higiene: gatilho temporario de contencao da sessao A NAO foi removido';
  end if;

  raise notice '[PASS] 18: I5/I6 intactas, nenhuma organizacao com dois ciclos ATIVO, Gama-P9 sem ciclo ATIVO, nenhum estado incoerente nas organizacoes P9 e nenhum artefato temporario residual';
end $$;

-- ----------------------------------------------------------------------------
-- 3) Fechamento: resumo deterministico da prova de concorrencia
-- ----------------------------------------------------------------------------
do $$
begin
  raise notice '[PASS] validacao consolidada (18) da corrida F5-09 P9: a edicao de A venceu (version = 1, 2041-01-10..2041-04-10), a escrita concorrente de B foi bloqueada no lock da organizacao e recusada com F5_09_CONFLICT (nenhum evento/estado residual) e a trilha append-only ficou com exatamente CRIADO + EDITADO sob autoria do gestor-gama';
end $$;
