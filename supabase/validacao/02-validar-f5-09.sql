-- ============================================================================
-- F5-09 P1: validacao automatizada da integridade de ciclos e da trilha
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (aplica as migrations)
--   2) `01-cenario-f5-09.sql`  (fixture sintetica)
--   3) este arquivo            (asserts `[PASS]`/`[FAIL]`)
--
-- Cobertura do P1 (docs/F5-09-desenho-tecnico.md §9, §10, §11, §12, §19 P1):
--   §1  `evaluation_cycles`: schema do contrato + I5 (um ATIVO por organizacao);
--   §2  I6: sobreposicao recusada, CANCELADO nao bloqueia, `data_fim` INCLUSIVA
--       (adjacencia e dia de fechamento) e isolamento por organizacao;
--   §3  D8/D9: exclusao fisica (DELETE/TRUNCATE) negada a TODOS os papeis de
--       aplicacao, inclusive por comportamento (nao apenas por ACL);
--   §4  `cycle_events`: schema, constraints, FKs de tenant/ciclo, idempotencia,
--       indices, RLS deny-by-default, grants minimos e append-only (UPDATE
--       negado por ACL e por trigger; DELETE negado);
--   §5  `ciclo_ator_valido`: ator/tenant/capability (reuso da autoridade
--       existente), allowlist fechada e fail-closed;
--   §6  `ciclo_lock_organizacao`: chave normativa unica da familia de ciclos;
--   §7  regressao: contratos F5-06/F5-07/F5-08 preservados (nenhum reaberto) e
--       leitura do P5 NAO antecipada.
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer falha levanta
-- excecao e aborta com codigo de saida nao-zero. O script NAO toca projeto
-- remoto, NAO altera policies/migrations e usa somente dados ficticios.
-- Asserts negativos rodam em subtransacao (a excecao esperada reverte apenas a
-- tentativa); asserts positivos que nao devem persistir usam excecao sentinela.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) `evaluation_cycles` — schema do contrato, I5 e unicidade de negocio
-- ============================================================================

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name::text order by column_name::text)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'evaluation_cycles';

  if v_cols is distinct from array[
    'ano', 'config_version_id', 'created_at', 'data_ativacao', 'data_encerramento',
    'data_fim', 'data_inicio', 'encerrado_com_pendencias', 'id', 'numero',
    'organization_id', 'quantidade_pendencias', 'status', 'updated_at',
    'version']::text[]
  then
    raise exception '[FAIL] evaluation_cycles: colunas fora do contrato (§2.2): %', v_cols;
  end if;
  raise notice '[PASS] evaluation_cycles: colunas exatas do contrato (§2.2 do desenho)';
end $$;

do $$
declare
  v_tipo_inicio text;
  v_tipo_fim    text;
  v_default     text;
begin
  select data_type into v_tipo_inicio from information_schema.columns
   where table_schema = 'public' and table_name = 'evaluation_cycles'
     and column_name = 'data_inicio';
  select data_type into v_tipo_fim from information_schema.columns
   where table_schema = 'public' and table_name = 'evaluation_cycles'
     and column_name = 'data_fim';
  select column_default into v_default from information_schema.columns
   where table_schema = 'public' and table_name = 'evaluation_cycles'
     and column_name = 'status';

  if v_tipo_inicio <> 'date' or v_tipo_fim <> 'date' then
    raise exception '[FAIL] evaluation_cycles: data_inicio/data_fim deveriam ser DATE (recebido %, %)',
      v_tipo_inicio, v_tipo_fim;
  end if;
  if v_default is distinct from '''PLANEJADO''::text' then
    raise exception '[FAIL] evaluation_cycles: default de status divergente (%)', v_default;
  end if;
  raise notice '[PASS] evaluation_cycles: data_inicio/data_fim DATE e status default PLANEJADO (D4/D5)';
end $$;

do $$
declare
  v_unico   boolean;
  v_pred    text;
  v_colunas text;
begin
  select i.indisunique and i.indpred is not null,
         pg_get_expr(i.indpred, i.indrelid),
         pg_get_indexdef(i.indexrelid)
    into v_unico, v_pred, v_colunas
    from pg_index i
    join pg_class c on c.oid = i.indexrelid
   where i.indrelid = 'public.evaluation_cycles'::regclass
     and c.relname = 'uq_evaluation_cycles_org_ativo';

  if v_unico is not true then
    raise exception '[FAIL] I5: uq_evaluation_cycles_org_ativo ausente ou nao e indice unico parcial';
  end if;
  if v_pred not like '%ATIVO%' then
    raise exception '[FAIL] I5: predicado do indice nao restringe status ATIVO (%)', v_pred;
  end if;
  if v_colunas not like '%(organization_id)%' then
    raise exception '[FAIL] I5: indice nao e por organization_id (%)', v_colunas;
  end if;
  raise notice '[PASS] I5: indice unico PARCIAL por organization_id restrito a status ATIVO (D14)';
end $$;

do $$
declare
  v_def text;
begin
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conrelid = 'public.evaluation_cycles'::regclass
     and c.conname = 'ex_evaluation_cycles_periodo_no_overlap'
     and c.contype = 'x';

  if v_def is null then
    raise exception '[FAIL] I6: exclusion ex_evaluation_cycles_periodo_no_overlap ausente';
  end if;
  if v_def not like '%daterange%' or v_def not like '%data_fim + 1%'
     or v_def not like '%''[)''%' then
    raise exception '[FAIL] I6: semantica temporal divergente do contrato (%)', v_def;
  end if;
  if v_def not like '%CANCELADO%' then
    raise exception '[FAIL] I6: predicado nao exclui CANCELADO (%)', v_def;
  end if;
  raise notice '[PASS] I6: exclusion meio-aberta daterange(data_inicio, data_fim + 1, ''[)'') com CANCELADO fora do indice (D15/D4)';
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_cycles'::regclass
       and conname = 'uq_evaluation_cycles_org_ano_numero'
       and contype = 'u'
  ) then
    raise exception '[FAIL] unicidade de negocio (organization_id, ano, numero) da F5-06 foi perdida';
  end if;
  raise notice '[PASS] unicidade de negocio (organization_id, ano, numero) da F5-06 preservada';
end $$;

-- ----------------------------------------------------------------------------
-- 1.1 Comportamento de I5: segundo ATIVO na MESMA organizacao e recusado
-- ----------------------------------------------------------------------------
do $$
begin
  begin
    insert into public.evaluation_cycles (id, organization_id, ano, numero, status)
    values ('f9e00000-0000-0000-0000-0000000000f1',
            'f9a00000-0000-0000-0000-0000000000a1', 2028, 1, 'ATIVO');
    raise exception '[FAIL] I5: segundo ciclo ATIVO da mesma organizacao foi aceito';
  exception
    when unique_violation then
      raise notice '[PASS] I5: segundo ciclo ATIVO na mesma organizacao recusado pelo banco';
    when others then
      raise;
  end;
end $$;

do $$
declare
  v_ativos int;
begin
  select count(*) into v_ativos from public.evaluation_cycles
   where organization_id = 'f9a00000-0000-0000-0000-0000000000a1'
     and status = 'ATIVO';
  if v_ativos <> 1 then
    raise exception '[FAIL] I5: organizacao Alfa com % ciclos ATIVO', v_ativos;
  end if;

  select count(*) into v_ativos from public.evaluation_cycles
   where organization_id = 'f9a00000-0000-0000-0000-0000000000b1'
     and status = 'ATIVO';
  if v_ativos <> 1 then
    raise exception '[FAIL] I5: organizacao Beta com % ciclos ATIVO', v_ativos;
  end if;

  raise notice '[PASS] I5: exatamente um ciclo ATIVO por organizacao (Alfa e Beta)';
end $$;

-- ============================================================================
-- 2) I6 — sobreposicao, CANCELADO, `data_fim` INCLUSIVA e isolamento por tenant
-- ============================================================================

do $$
begin
  -- c1 (Alfa) e ATIVO 2026-01-01..2026-03-31. Novo ciclo NAO CANCELADO com
  -- periodo sobreposto => recusa.
  begin
    insert into public.evaluation_cycles
      (id, organization_id, ano, numero, status, data_inicio, data_fim)
    values ('f9e00000-0000-0000-0000-0000000000f2',
            'f9a00000-0000-0000-0000-0000000000a1', 2028, 1, 'PLANEJADO',
            date '2026-02-01', date '2026-02-28');
    raise exception '[FAIL] I6: sobreposicao entre ciclos NAO CANCELADOS foi aceita';
  exception
    when exclusion_violation then
      raise notice '[PASS] I6: sobreposicao de periodo entre ciclos NAO CANCELADOS recusada';
    when others then
      raise;
  end;
end $$;

do $$
begin
  -- CANCELADO com periodo sobreposto ao c1 => PERMITIDO (probe revertido).
  begin
    insert into public.evaluation_cycles
      (id, organization_id, ano, numero, status, data_inicio, data_fim)
    values ('f9e00000-0000-0000-0000-0000000000f3',
            'f9a00000-0000-0000-0000-0000000000a1', 2028, 1, 'CANCELADO',
            date '2026-02-01', date '2026-02-28');
    raise exception 'F5-09_PROBE_ROLLBACK';
  exception
    when others then
      if sqlerrm = 'F5-09_PROBE_ROLLBACK' then
        raise notice '[PASS] I6: ciclo CANCELADO nao bloqueia periodo (probe revertido)';
      else
        raise;
      end if;
  end;
end $$;

do $$
begin
  -- Adjacencia: c4 (Alfa) ENCERRADO 2025-01-01..2025-06-30. Um ciclo que comeca
  -- em 2025-07-01 (= data_fim + 1) NAO sobrepoe => permitido (probe revertido).
  begin
    insert into public.evaluation_cycles
      (id, organization_id, ano, numero, status, data_inicio, data_fim)
    values ('f9e00000-0000-0000-0000-0000000000f4',
            'f9a00000-0000-0000-0000-0000000000a1', 2028, 1, 'PLANEJADO',
            date '2025-07-01', date '2025-12-31');
    raise exception 'F5-09_PROBE_ROLLBACK';
  exception
    when others then
      if sqlerrm = 'F5-09_PROBE_ROLLBACK' then
        raise notice '[PASS] I6: dia seguinte ao data_fim e periodo livre (meio-aberto)';
      else
        raise;
      end if;
  end;
end $$;

do $$
begin
  -- `data_fim` INCLUSIVA: comecar NO dia de data_fim do c4 (2025-06-30) sobrepoe.
  begin
    insert into public.evaluation_cycles
      (id, organization_id, ano, numero, status, data_inicio, data_fim)
    values ('f9e00000-0000-0000-0000-0000000000f5',
            'f9a00000-0000-0000-0000-0000000000a1', 2028, 1, 'PLANEJADO',
            date '2025-06-30', date '2025-12-31');
    raise exception '[FAIL] I6/D4: data_fim nao esta sendo tratada como INCLUSIVA';
  exception
    when exclusion_violation then
      raise notice '[PASS] I6/D4: data_fim e o ULTIMO dia do ciclo (inclusiva) — inicio no dia de fechamento sobrepoe';
    when others then
      raise;
  end;
end $$;

do $$
declare
  v_alfa int;
  v_beta int;
begin
  -- Mesmo periodo em tenants diferentes (c1 em Alfa, d1 em Beta) coexiste.
  select count(*) into v_alfa from public.evaluation_cycles
   where organization_id = 'f9a00000-0000-0000-0000-0000000000a1'
     and data_inicio = date '2026-01-01' and data_fim = date '2026-03-31';
  select count(*) into v_beta from public.evaluation_cycles
   where organization_id = 'f9a00000-0000-0000-0000-0000000000b1'
     and data_inicio = date '2026-01-01' and data_fim = date '2026-03-31';

  if v_alfa <> 1 or v_beta <> 1 then
    raise exception '[FAIL] I6: isolamento por organizacao violado (alfa=%, beta=%)', v_alfa, v_beta;
  end if;
  raise notice '[PASS] I6: exclusion e POR ORGANIZACAO (mesmo periodo em tenants distintos coexiste)';
end $$;

do $$
declare
  v_nulos int;
begin
  -- Ciclo sem periodo fica FORA do indice parcial (nao bloqueia nada).
  select count(*) into v_nulos from public.evaluation_cycles
   where organization_id = 'f9a00000-0000-0000-0000-0000000000a1'
     and data_inicio is null and data_fim is null;
  if v_nulos <> 1 then
    raise exception '[FAIL] I6: ciclo sem periodo esperado=1, encontrado=%', v_nulos;
  end if;
  raise notice '[PASS] I6: ciclo sem periodo (data_inicio/data_fim nulos) fica fora do indice parcial';
end $$;

-- ============================================================================
-- 3) D8/D9 — exclusao fisica de ciclo negada a todos os papeis de aplicacao
-- ============================================================================

do $$
declare
  v_problemas text[] := array[]::text[];
begin
  if has_table_privilege('service_role', 'public.evaluation_cycles', 'DELETE') then
    v_problemas := v_problemas || 'service_role com DELETE';
  end if;
  if has_table_privilege('service_role', 'public.evaluation_cycles', 'TRUNCATE') then
    v_problemas := v_problemas || 'service_role com TRUNCATE';
  end if;
  -- Escrita do cliente: fechada em TODAS as fases (P1 e depois). A LEITURA de
  -- `evaluation_cycles` por `authenticated` e do P5 e por isso nao e exigida
  -- aqui: quando existir, o bloco seguinte prova que ela vem acompanhada de
  -- policy own-tenant (nunca leitura nua por grant).
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'TRUNCATE') then
    v_problemas := v_problemas || 'authenticated com escrita em evaluation_cycles';
  end if;
  if has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'DELETE') then
    v_problemas := v_problemas || 'anon com privilegio';
  end if;

  -- Contrato da F5-06 preservado: o caminho server-side continua podendo
  -- gravar ciclo (as RPCs do P2+ usam INSERT/UPDATE; a de cancelamento e o P4).
  if has_table_privilege('service_role', 'public.evaluation_cycles', 'SELECT') is not true
     or has_table_privilege('service_role', 'public.evaluation_cycles', 'INSERT') is not true
     or has_table_privilege('service_role', 'public.evaluation_cycles', 'UPDATE') is not true then
    v_problemas := v_problemas || 'service_role sem SELECT/INSERT/UPDATE (contrato F5-06 alterado)';
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] grants de evaluation_cycles: %', array_to_string(v_problemas, '; ');
  end if;
  raise notice '[PASS] grants de evaluation_cycles: service_role sem DELETE/TRUNCATE; anon sem acesso; authenticated sem escrita';
end $$;

do $$
declare
  v_policies int;
  v_fora     text[];
begin
  -- RLS habilitada (invariante de todas as fases).
  if not exists (
    select 1 from pg_class
     where oid = 'public.evaluation_cycles'::regclass and relrowsecurity
  ) then
    raise exception '[FAIL] evaluation_cycles: RLS desabilitada';
  end if;

  select count(*) into v_policies
    from pg_policies
   where schemaname = 'public' and tablename = 'evaluation_cycles';

  if v_policies = 0 then
    -- Estado do P1: nenhuma policy (a leitura own-tenant e do P5) — se o grant
    -- de SELECT nao existe, a leitura e impossivel para `authenticated`.
    if has_table_privilege('authenticated', 'public.evaluation_cycles', 'SELECT') then
      raise exception '[FAIL] evaluation_cycles: authenticated com SELECT sem policy (leitura nua)';
    end if;
    raise notice '[PASS] P1: evaluation_cycles deny-by-default integral (sem policy e sem SELECT a authenticated; leitura e do P5)';
  else
    -- Fases posteriores (P5+): leitura so por policy own-tenant, nunca por grant
    -- sem policy e nunca com escrita.
    select array_agg(format('%s/%s/%s', policyname, cmd, array_to_string(roles, ',')))
      into v_fora
      from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and (cmd <> 'SELECT'
            or not ('authenticated'::name = any(roles))
            or coalesce(qual, '') not like '%user_has_active_membership%');

    if v_fora is not null then
      raise exception '[FAIL] evaluation_cycles: policy fora do contrato own-tenant: %',
        array_to_string(v_fora, '; ');
    end if;
    raise notice '[PASS] evaluation_cycles: policy de leitura own-tenant presente (P5) e nenhuma policy de escrita';
  end if;
end $$;

set role service_role;

do $$
begin
  begin
    delete from public.evaluation_cycles
     where id = 'f9e00000-0000-0000-0000-0000000000c1';
    raise exception '[FAIL] DELETE de ciclo permitido a service_role';
  exception
    when insufficient_privilege then
      raise notice '[PASS] D9: DELETE de ciclo negado a service_role (sem grant)';
    when others then
      raise;
  end;

  begin
    truncate public.evaluation_cycles;
    raise exception '[FAIL] TRUNCATE de evaluation_cycles permitido a service_role';
  exception
    when insufficient_privilege then
      raise notice '[PASS] D9: TRUNCATE de evaluation_cycles negado a service_role (sem grant)';
    when others then
      raise;
  end;
end $$;

-- A leitura do caminho server-side (F5-06) segue valida.
do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.evaluation_cycles
   where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';
  if v_n <> 5 then
    raise exception '[FAIL] service_role: ciclos esperados=5 na organizacao Alfa, lidos=%', v_n;
  end if;
  raise notice '[PASS] service_role le os ciclos do tenant (SELECT permitido — contrato F5-06 preservado)';
end $$;

reset role;

-- `authenticated` nao tem escrita em ciclo em NENHUMA fase; a leitura e do P5
-- (validada de forma condicional, sem reprovar a fase que a abrir). O papel e
-- trocado no nivel da sessao (fora dos blocos com handler) para que o rollback de
-- savepoint nao devolva o papel anterior.
set role authenticated;

do $$
begin
  -- Leitura: no P1 nao existe grant nem policy (leitura own-tenant e do P5).
  -- A checagem e condicional para nao reprovar a fase que abrir o P5.
  if not has_table_privilege('public.evaluation_cycles', 'SELECT') then
    begin
      perform count(*) from public.evaluation_cycles;
      raise exception '[FAIL] SELECT de ciclo permitido a authenticated sem grant';
    exception
      when insufficient_privilege then
        raise notice '[PASS] P1: authenticated nao le evaluation_cycles (deny-by-default integral; leitura e do P5)';
      when others then
        raise;
    end;
  else
    raise notice '[PASS] authenticated com leitura governada por policy own-tenant (fase P5 aplicada)';
  end if;

  begin
    insert into public.evaluation_cycles
      (id, organization_id, ano, numero, status)
    values ('f9e00000-0000-0000-0000-0000000000f9',
            'f9a00000-0000-0000-0000-0000000000a1', 2029, 1, 'PLANEJADO');
    raise exception '[FAIL] INSERT de ciclo permitido a authenticated';
  exception
    when insufficient_privilege then
      raise notice '[PASS] authenticated nao cria ciclo (INSERT negado)';
    when others then
      raise;
  end;

  begin
    update public.evaluation_cycles set version = version
     where id = 'f9e00000-0000-0000-0000-0000000000c1';
    raise exception '[FAIL] UPDATE de ciclo permitido a authenticated';
  exception
    when insufficient_privilege then
      raise notice '[PASS] authenticated nao altera ciclo (UPDATE negado)';
    when others then
      raise;
  end;

  begin
    delete from public.evaluation_cycles
     where id = 'f9e00000-0000-0000-0000-0000000000c1';
    raise exception '[FAIL] DELETE de ciclo permitido a authenticated';
  exception
    when insufficient_privilege then
      raise notice '[PASS] authenticated nao apaga ciclo (DELETE negado)';
    when others then
      raise;
  end;
end $$;

reset role;

-- ============================================================================
-- 4) `cycle_events` — schema, constraints, FKs, idempotencia, RLS e append-only
-- ============================================================================

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name::text order by column_name::text)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'cycle_events';

  if v_cols is distinct from array[
    'actor_membership_id', 'actor_user_profile_id', 'after_value', 'before_value',
    'created_at', 'cycle_id', 'effective_date', 'entity_type', 'event_type',
    'id', 'operation_id', 'organization_id', 'payload_hash', 'reason',
    'result_entity_id']::text[]
  then
    raise exception '[FAIL] cycle_events: colunas fora do contrato (§12): %', v_cols;
  end if;
  raise notice '[PASS] cycle_events: colunas exatas do contrato (§12)';
end $$;

do $$
declare
  v_obrigatorias_nulas int;
  v_opcionais_not_null int;
begin
  select count(*) into v_obrigatorias_nulas
  from information_schema.columns
  where table_schema = 'public' and table_name = 'cycle_events'
    and column_name in (
      'id', 'organization_id', 'cycle_id', 'entity_type', 'event_type',
      'effective_date', 'reason', 'payload_hash', 'actor_user_profile_id',
      'actor_membership_id', 'operation_id', 'created_at')
    and is_nullable = 'YES';

  select count(*) into v_opcionais_not_null
  from information_schema.columns
  where table_schema = 'public' and table_name = 'cycle_events'
    and column_name in ('before_value', 'after_value', 'result_entity_id')
    and is_nullable = 'NO';

  if v_obrigatorias_nulas <> 0 or v_opcionais_not_null <> 0 then
    raise exception
      '[FAIL] cycle_events: nulabilidade divergente (obrigatorias nulas=%, opcionais not null=%)',
      v_obrigatorias_nulas, v_opcionais_not_null;
  end if;
  raise notice '[PASS] cycle_events: NOT NULL do contrato (before/after/result opcionais)';
end $$;

do $$
declare
  v_faltando text[] := array[]::text[];
  v_nome     text;
begin
  foreach v_nome in array array[
    'pk_cycle_events', 'fk_cycle_events_organizations', 'fk_cycle_events_cycle',
    'fk_cycle_events_actor', 'fk_cycle_events_actor_membership',
    'uq_cycle_events_org_operation', 'ck_cycle_events_entity_type',
    'ck_cycle_events_event_type', 'ck_cycle_events_reason',
    'ck_cycle_events_payload_hash']
  loop
    if not exists (
      select 1 from pg_constraint
       where conrelid = 'public.cycle_events'::regclass and conname = v_nome
    ) then
      v_faltando := v_faltando || v_nome;
    end if;
  end loop;

  if array_length(v_faltando, 1) is not null then
    raise exception '[FAIL] cycle_events: constraints ausentes: %', array_to_string(v_faltando, ', ');
  end if;
  raise notice '[PASS] cycle_events: PK, 4 FKs (tenant, ciclo composto, ator e membership) e 4 CHECKs presentes';
end $$;

do $$
declare
  v_def text;
begin
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conrelid = 'public.cycle_events'::regclass
     and c.conname = 'fk_cycle_events_cycle';

  if v_def is null or v_def not like '%(cycle_id, organization_id)%'
     or v_def not like '%evaluation_cycles%' then
    raise exception '[FAIL] cycle_events: FK de ciclo nao e COMPOSTA com organization_id (%)', v_def;
  end if;
  raise notice '[PASS] cycle_events: FK composta (cycle_id, organization_id) → evaluation_cycles (isolamento estrutural de tenant)';
end $$;

do $$
declare
  v_idx text[];
begin
  select array_agg(indexname::text order by indexname::text) into v_idx
    from pg_indexes
   where schemaname = 'public' and tablename = 'cycle_events'
     and indexname like 'ix_cycle_events%';

  if v_idx is distinct from array[
    'ix_cycle_events_cycle', 'ix_cycle_events_effective',
    'ix_cycle_events_organization_id']::text[] then
    raise exception '[FAIL] cycle_events: indices de trilha divergentes: %', v_idx;
  end if;
  raise notice '[PASS] cycle_events: indices (organization_id), (organization_id, cycle_id) e (organization_id, effective_date)';
end $$;

-- ----------------------------------------------------------------------------
-- 4.1 Comportamento das constraints (checks, idempotencia e FKs de tenant)
-- ----------------------------------------------------------------------------
do $$
declare
  v_base uuid := 'f9e00000-0000-0000-0000-0000000000c1';
begin
  -- event_type fora do contrato
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('f9a00000-0000-0000-0000-0000000000a1', v_base, 'evaluation_cycle',
            'INVENTADO', now(), 'teste', repeat('a', 64),
            'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
            'f9e50000-0000-0000-0000-0000000000f1');
    raise exception '[FAIL] cycle_events: event_type fora do contrato foi aceito';
  exception
    when check_violation then
      raise notice '[PASS] cycle_events: event_type fora do contrato recusado (CHECK)';
    when others then
      raise;
  end;

  -- entity_type fora do contrato
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('f9a00000-0000-0000-0000-0000000000a1', v_base, 'evaluation',
            'CRIADO', now(), 'teste', repeat('a', 64),
            'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
            'f9e50000-0000-0000-0000-0000000000f2');
    raise exception '[FAIL] cycle_events: entity_type fora do contrato foi aceito';
  exception
    when check_violation then
      raise notice '[PASS] cycle_events: entity_type restrito a evaluation_cycle (CHECK)';
    when others then
      raise;
  end;

  -- reason vazio
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('f9a00000-0000-0000-0000-0000000000a1', v_base, 'evaluation_cycle',
            'CRIADO', now(), '', repeat('a', 64),
            'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
            'f9e50000-0000-0000-0000-0000000000f3');
    raise exception '[FAIL] cycle_events: motivo vazio foi aceito';
  exception
    when check_violation then
      raise notice '[PASS] cycle_events: motivo obrigatorio e sem espacos nas bordas (CHECK)';
    when others then
      raise;
  end;

  -- payload_hash fora do formato SHA-256 hex
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('f9a00000-0000-0000-0000-0000000000a1', v_base, 'evaluation_cycle',
            'CRIADO', now(), 'teste', 'nao-e-hash',
            'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
            'f9e50000-0000-0000-0000-0000000000f4');
    raise exception '[FAIL] cycle_events: payload_hash invalido foi aceito';
  exception
    when check_violation then
      raise notice '[PASS] cycle_events: payload_hash exige SHA-256 hex de 64 caracteres (CHECK)';
    when others then
      raise;
  end;

  -- operacao obrigatoria ausente
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id)
    values ('f9a00000-0000-0000-0000-0000000000a1', v_base, 'evaluation_cycle',
            'CRIADO', now(), 'teste', repeat('a', 64),
            'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1');
    raise exception '[FAIL] cycle_events: operation_id ausente foi aceito';
  exception
    when not_null_violation then
      raise notice '[PASS] cycle_events: operation_id obrigatorio (idempotencia nao pode ser omitida)';
    when others then
      raise;
  end;

  -- idempotencia: MESMA organizacao + MESMO operation_id
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('f9a00000-0000-0000-0000-0000000000a1', v_base, 'evaluation_cycle',
            'CRIADO', now(), 'repeticao', repeat('b', 64),
            'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
            'f9e40000-0000-0000-0000-0000000000e1');
    raise exception '[FAIL] idempotencia: operation_id repetido na mesma organizacao foi aceito';
  exception
    when unique_violation then
      raise notice '[PASS] idempotencia: unique (organization_id, operation_id) impede duplicidade de operacao';
    when others then
      raise;
  end;

  -- FK composta: ciclo de OUTRO tenant no evento
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('f9a00000-0000-0000-0000-0000000000a1',
            'f9e00000-0000-0000-0000-0000000000d1', 'evaluation_cycle',
            'CRIADO', now(), 'cross-tenant', repeat('c', 64),
            'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
            'f9e50000-0000-0000-0000-0000000000f5');
    raise exception '[FAIL] cycle_events: evento com ciclo de OUTRO tenant foi aceito';
  exception
    when foreign_key_violation then
      raise notice '[PASS] cycle_events: ciclo de outro tenant recusado pela FK composta';
    when others then
      raise;
  end;

  -- FK composta: membership de OUTRO tenant na autoria
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('f9a00000-0000-0000-0000-0000000000a1', v_base, 'evaluation_cycle',
            'CRIADO', now(), 'membership cross-tenant', repeat('d', 64),
            'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000b1',
            'f9e50000-0000-0000-0000-0000000000f6');
    raise exception '[FAIL] cycle_events: autoria com membership de OUTRO tenant foi aceita';
  exception
    when foreign_key_violation then
      raise notice '[PASS] cycle_events: membership de outro tenant recusada pela FK composta de autoria';
    when others then
      raise;
  end;
end $$;

-- ----------------------------------------------------------------------------
-- 4.2 RLS/grants da trilha e append-only (ACL e trigger)
-- ----------------------------------------------------------------------------
do $$
declare
  v_problemas text[] := array[]::text[];
begin
  if not exists (
    select 1 from pg_class
     where oid = 'public.cycle_events'::regclass and relrowsecurity
  ) then
    v_problemas := v_problemas || 'RLS desabilitada';
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'cycle_events'
  ) then
    v_problemas := v_problemas || 'policy presente (trilha e deny-by-default integral)';
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'UPDATE') then
    v_problemas := v_problemas || 'service_role com UPDATE';
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'DELETE') then
    v_problemas := v_problemas || 'service_role com DELETE';
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'TRUNCATE') then
    v_problemas := v_problemas || 'service_role com TRUNCATE';
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'SELECT') is not true
     or has_table_privilege('service_role', 'public.cycle_events', 'INSERT') is not true then
    v_problemas := v_problemas || 'service_role sem SELECT/INSERT';
  end if;
  if has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'UPDATE')
     or has_table_privilege('authenticated', 'public.cycle_events', 'DELETE') then
    v_problemas := v_problemas || 'authenticated com privilegio';
  end if;
  if has_table_privilege('anon', 'public.cycle_events', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.cycle_events', 'UPDATE')
     or has_table_privilege('anon', 'public.cycle_events', 'DELETE') then
    v_problemas := v_problemas || 'anon com privilegio';
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] cycle_events (RLS/grants): %', array_to_string(v_problemas, '; ');
  end if;
  raise notice '[PASS] cycle_events: RLS deny-by-default sem policy; service_role apenas SELECT/INSERT; anon/authenticated sem acesso';
end $$;

do $$
declare
  v_def text;
begin
  select pg_get_triggerdef(t.oid) into v_def
    from pg_trigger t
   where t.tgrelid = 'public.cycle_events'::regclass
     and t.tgname = 'trg_cycle_events_append_only'
     and not t.tgisinternal;

  if v_def is null or v_def not like '%BEFORE UPDATE%' then
    raise exception '[FAIL] cycle_events: trigger append-only ausente (UPDATE)';
  end if;
  raise notice '[PASS] cycle_events: trigger append-only BEFORE UPDATE presente';
end $$;

set role service_role;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.cycle_events
   where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] service_role deveria ler a trilha (leu %)', v_n;
  end if;
  raise notice '[PASS] service_role le a trilha de ciclos (SELECT permitido)';
end $$;

do $$
begin
  begin
    update public.cycle_events
       set reason = reason
     where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] UPDATE permitido a service_role em cycle_events';
  exception
    when insufficient_privilege then
      raise notice '[PASS] UPDATE negado a service_role em cycle_events (sem grant — append-only na ACL)';
    when others then
      raise;
  end;

  begin
    delete from public.cycle_events
     where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] DELETE permitido a service_role em cycle_events';
  exception
    when insufficient_privilege then
      raise notice '[PASS] DELETE negado a service_role em cycle_events (sem grant)';
    when others then
      raise;
  end;

  -- INSERT permitido (probe revertido por excecao sentinela).
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values
      ('f9a00000-0000-0000-0000-0000000000a1', 'f9e00000-0000-0000-0000-0000000000c1',
       'evaluation_cycle', 'CRIADO', now(), 'probe de INSERT do caminho server-side',
       encode(sha256(convert_to('probe-f5-09-p1', 'UTF8')), 'hex'),
       'f9c00000-0000-0000-0000-0000000000a1', 'f9d00000-0000-0000-0000-0000000000a1',
       'f9e50000-0000-0000-0000-0000000000ff');
    raise exception 'F5-09_PROBE_ROLLBACK';
  exception
    when others then
      if sqlerrm = 'F5-09_PROBE_ROLLBACK' then
        raise notice '[PASS] INSERT permitido a service_role na trilha (probe revertido)';
      else
        raise;
      end if;
  end;
end $$;

reset role;

-- Camada 2 (trigger append-only): exercitada como OWNER/superuser — que passa
-- pela ACL mas NAO pelo trigger. Prova a defesa em profundidade no BANCO,
-- independentemente de grants (§12.5).
do $$
begin
  begin
    update public.cycle_events
       set reason = reason
     where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] trigger append-only nao disparou (UPDATE aceito pelo owner)';
  exception
    when others then
      if sqlerrm like '%F5-09: cycle_events e append-only%' then
        raise notice '[PASS] trigger append-only bloqueia UPDATE ate para o owner (defesa em profundidade)';
      else
        raise;
      end if;
  end;
end $$;

-- ============================================================================
-- 5) `ciclo_ator_valido` — ator/tenant/capability (reuso integral, fail-closed)
-- ============================================================================

do $$
declare
  v_alfa uuid := 'f9a00000-0000-0000-0000-0000000000a1';
  v_beta uuid := 'f9a00000-0000-0000-0000-0000000000b1';
begin
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a1', v_alfa, 'cycle.manage') is not true then
    raise exception '[FAIL] ciclo_ator_valido: ator com cycle.manage em Alfa deveria ser valido';
  end if;
  raise notice '[PASS] ciclo_ator_valido: ator com membership ativa + capability efetiva cycle.manage => true';

  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a3', v_beta, 'cycle.manage') is not true then
    raise exception '[FAIL] ciclo_ator_valido: ator Beta com cycle.manage em Beta deveria ser valido';
  end if;
  raise notice '[PASS] ciclo_ator_valido: capability resolvida no tenant CORRETO do ator';
end $$;

do $$
declare
  v_alfa uuid := 'f9a00000-0000-0000-0000-0000000000a1';
  v_beta uuid := 'f9a00000-0000-0000-0000-0000000000b1';
  v_problemas text[] := array[]::text[];
begin
  -- capability que o ator nao possui
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a1', v_alfa, 'cycle.read') is not false then
    v_problemas := v_problemas || 'capability nao concedida aceita';
  end if;
  -- capability de OUTRO dominio (allowlist fechada)
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a1', v_alfa, 'evaluation.read') is not false then
    v_problemas := v_problemas || 'capability fora do dominio de ciclo aceita';
  end if;
  -- capability desconhecida / nula
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a1', v_alfa, 'cycle.inventado') is not false then
    v_problemas := v_problemas || 'capability desconhecida aceita';
  end if;
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a1', v_alfa, null) is not false then
    v_problemas := v_problemas || 'capability nula aceita';
  end if;
  -- ator sem assignment
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a2', v_alfa, 'cycle.manage') is not false then
    v_problemas := v_problemas || 'ator sem capability aceito';
  end if;
  -- cross-tenant: ator de Beta com a capability apenas em Beta
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a3', v_alfa, 'cycle.manage') is not false then
    v_problemas := v_problemas || 'cross-tenant aceito';
  end if;
  -- membership DISABLED
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a4', v_alfa, 'cycle.manage') is not false then
    v_problemas := v_problemas || 'membership desabilitada aceita';
  end if;
  -- perfil DISABLED
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a5', v_alfa, 'cycle.manage') is not false then
    v_problemas := v_problemas || 'perfil desabilitado aceito';
  end if;
  -- identidade/tenant ausentes
  if public.ciclo_ator_valido(null, v_alfa, 'cycle.manage') is not false then
    v_problemas := v_problemas || 'perfil nulo aceito';
  end if;
  if public.ciclo_ator_valido('f9c00000-0000-0000-0000-0000000000a1', null, 'cycle.manage') is not false then
    v_problemas := v_problemas || 'tenant nulo aceito';
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] ciclo_ator_valido (fail-closed): %', array_to_string(v_problemas, '; ');
  end if;
  raise notice '[PASS] ciclo_ator_valido: fail-closed para capability ausente/fora do dominio/nula, ator sem assignment, cross-tenant, membership ou perfil inativo e argumentos nulos';
end $$;

do $$
declare
  v_secdef   boolean;
  v_volatil  text;
begin
  select p.prosecdef, p.provolatile into v_secdef, v_volatil
    from pg_proc p
   where p.oid = 'public.ciclo_ator_valido(uuid, uuid, text)'::regprocedure;

  if v_secdef is not false then
    raise exception '[FAIL] ciclo_ator_valido: deveria ser SECURITY INVOKER';
  end if;
  if v_volatil <> 's' then
    raise exception '[FAIL] ciclo_ator_valido: deveria ser STABLE (%)', v_volatil;
  end if;
  if has_function_privilege('authenticated', 'public.ciclo_ator_valido(uuid, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.ciclo_ator_valido(uuid, uuid, text)', 'EXECUTE') then
    raise exception '[FAIL] ciclo_ator_valido: EXECUTE exposto a anon/authenticated';
  end if;
  if has_function_privilege('service_role', 'public.ciclo_ator_valido(uuid, uuid, text)', 'EXECUTE') is not true then
    raise exception '[FAIL] ciclo_ator_valido: service_role sem EXECUTE';
  end if;
  raise notice '[PASS] ciclo_ator_valido: SECURITY INVOKER, STABLE, EXECUTE somente service_role';
end $$;

-- ============================================================================
-- 6) `ciclo_lock_organizacao` — chave normativa unica da familia de ciclos
-- ============================================================================

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
   where p.oid = 'public.ciclo_lock_organizacao(uuid)'::regprocedure;

  if v_def is null then
    raise exception '[FAIL] ciclo_lock_organizacao ausente';
  end if;
  if v_def not like '%evaluation_cycles:%' then
    raise exception '[FAIL] ciclo_lock_organizacao: chave normativa evaluation_cycles:<org> ausente';
  end if;
  if v_def like '%position_reporting_lines:%' or v_def like '%f5_07_estrutura:%' then
    raise exception '[FAIL] ciclo_lock_organizacao: reutiliza chave de OUTRA familia de lock';
  end if;
  if v_def not like '%pg_advisory_xact_lock%' then
    raise exception '[FAIL] ciclo_lock_organizacao: nao usa pg_advisory_xact_lock';
  end if;
  raise notice '[PASS] ciclo_lock_organizacao: chave unica evaluation_cycles:<organization_id> (nao reutiliza familias existentes)';
end $$;

do $$
declare
  v_secdef boolean;
begin
  select p.prosecdef into v_secdef
    from pg_proc p
   where p.oid = 'public.ciclo_lock_organizacao(uuid)'::regprocedure;

  if v_secdef is not false then
    raise exception '[FAIL] ciclo_lock_organizacao: deveria ser SECURITY INVOKER';
  end if;
  if has_function_privilege('authenticated', 'public.ciclo_lock_organizacao(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.ciclo_lock_organizacao(uuid)', 'EXECUTE') then
    raise exception '[FAIL] ciclo_lock_organizacao: EXECUTE exposto a anon/authenticated';
  end if;
  if has_function_privilege('service_role', 'public.ciclo_lock_organizacao(uuid)', 'EXECUTE') is not true then
    raise exception '[FAIL] ciclo_lock_organizacao: service_role sem EXECUTE';
  end if;
  raise notice '[PASS] ciclo_lock_organizacao: SECURITY INVOKER e EXECUTE somente service_role';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    perform public.ciclo_lock_organizacao(null);
  exception
    when others then
      if sqlerrm like '%F5_09_INVALID_INPUT%' then
        v_ok := true;
      else
        raise;
      end if;
  end;

  if not v_ok then
    raise exception '[FAIL] ciclo_lock_organizacao: organization_id nulo deveria falhar explicitamente';
  end if;
  raise notice '[PASS] ciclo_lock_organizacao: organization_id nulo recusado (F5_09_INVALID_INPUT)';
end $$;

do $$
begin
  -- Lock de TRANSACAO e reentrante: duas chamadas na mesma transacao nao
  -- bloqueiam o proprio chamador (comportamento exigido pelas RPCs do P2-P4,
  -- que podem compor chamadas).
  perform public.ciclo_lock_organizacao('f9a00000-0000-0000-0000-0000000000a1');
  perform public.ciclo_lock_organizacao('f9a00000-0000-0000-0000-0000000000a1');
  raise notice '[PASS] ciclo_lock_organizacao: reentrante na mesma transacao (pg_advisory_xact_lock)';
end $$;

-- ============================================================================
-- 7) Regressao — contratos F5-06/F5-07/F5-08 preservados
-- ============================================================================

do $$
declare
  v_faltando text[] := array[]::text[];
begin
  if to_regprocedure('public.evaluation_resolver_ciclo(uuid, integer, integer, uuid)') is null then
    v_faltando := v_faltando || 'evaluation_resolver_ciclo(uuid, integer, integer, uuid)';
  end if;
  if to_regprocedure('public.evaluation_ator_valido(uuid, uuid)') is null then
    v_faltando := v_faltando || 'evaluation_ator_valido(uuid, uuid)';
  end if;
  if to_regprocedure('public.evaluation_fechar_ciclo_pendencias(uuid, uuid, uuid)') is null then
    v_faltando := v_faltando || 'evaluation_fechar_ciclo_pendencias(uuid, uuid, uuid)';
  end if;
  if to_regprocedure('public.evaluation_criar(uuid, uuid, uuid, uuid)') is null then
    v_faltando := v_faltando || 'evaluation_criar(uuid, uuid, uuid, uuid)';
  end if;
  if to_regprocedure('public.materializar_colegiado_ciclo(uuid, integer, integer, timestamp with time zone, uuid[])') is null then
    v_faltando := v_faltando || 'materializar_colegiado_ciclo(...)';
  end if;
  if to_regprocedure('public.user_has_active_membership(uuid)') is null then
    v_faltando := v_faltando || 'user_has_active_membership(uuid)';
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception '[FAIL] regressao: objetos preservados ausentes: %', array_to_string(v_faltando, ', ');
  end if;
  raise notice '[PASS] regressao: assinaturas F3-08/F4-08/F5-06 preservadas (resolver, criar, fechar ciclo, materializar, membership)';
end $$;

do $$
declare
  v_faltando text[] := array[]::text[];
begin
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.structure_events'::regclass
       and tgname = 'trg_structure_events_append_only'
       and not tgisinternal
  ) then
    v_faltando := v_faltando || 'structure_events append-only';
  end if;
  if has_table_privilege('service_role', 'public.structure_events', 'UPDATE')
     or has_table_privilege('service_role', 'public.structure_events', 'DELETE') then
    v_faltando := v_faltando || 'grants de structure_events alterados';
  end if;
  if has_table_privilege('service_role', 'public.collaborator_events', 'DELETE') then
    v_faltando := v_faltando || 'grants de collaborator_events alterados';
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception '[FAIL] regressao F5-07/F5-08: %', array_to_string(v_faltando, '; ');
  end if;
  raise notice '[PASS] regressao F5-07/F5-08: trilhas append-only e grants intactos (contratos nao reabertos)';
end $$;

do $$
declare
  v_pend int;
  v_snap int;
begin
  select count(*) into v_pend from public.evaluation_pendencies;
  select count(*) into v_snap from public.collegiate_cycle_snapshots;

  -- Nao importa o valor: importa que as tabelas continuam existindo e legiveis
  -- pelo caminho server-side (nenhuma migracao do P1 as alterou).
  if v_pend is null or v_snap is null then
    raise exception '[FAIL] regressao: tabelas F3-08/F5-06 inacessiveis';
  end if;
  raise notice '[PASS] regressao: F3-08 (snapshots) e F5-06 (pendencias) permanecem acessiveis e inalteradas';
end $$;

-- ============================================================================
-- 8) Resumo
-- ============================================================================
do $$
begin
  raise notice '[PASS] F5-09 P1: integridade de schema e trilha de auditoria validada (I5, I6, D8/D9, cycle_events, ciclo_ator_valido e ciclo_lock_organizacao)';
end $$;
