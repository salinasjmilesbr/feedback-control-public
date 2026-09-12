-- ============================================================================
-- F5-08 P1 (Etapa 5): validacao automatizada da integridade estrutural
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes` (aplica as migrations)
--   2) `01-cenario-f5-08.sql`  (fixture sintetica)
--   3) este arquivo            (asserts `[PASS]`/`[FAIL]`)
--
-- Cobertura do P1 (docs/F5-08-desenho-tecnico.md §23.1/§23.2 — grupos A, C, D,
-- E, F aplicaveis ao P1; §13.7):
--   §1  `structure_events`: colunas, NOT NULL, constraints, indices, RLS
--       deny-by-default, grants minimos, append-only e DELETE negado;
--   §2  I1: anti-ciclo de unidades (direto, multinivel, temporal, tenant);
--   §3  I2: encerramento de unidade nos TRES casos + semantica `[)`;
--   §4  I3: encerramento de posicao com ocupacao vigente + guarda F3-04;
--   §5  D24: as 4 RPCs estruturais da F5-07 com a chave normativa, assinatura,
--       retorno, ACL e SECURITY INVOKER preservados;
--   §6  grants/RLS: anon/authenticated sem DML, service_role sem DELETE,
--       nenhuma policy de escrita, nenhum SECURITY DEFINER novo.
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer falha levanta
-- excecao e aborta com codigo de saida nao-zero. O script NAO toca projeto
-- remoto, NAO altera policies/migrations e usa somente dados ficticios.
-- Asserts negativos rodam em subtransacao (a excecao esperada reverte apenas a
-- tentativa).
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) `structure_events` — estrutura, constraints, indices, RLS, grants
-- ============================================================================

do $$
declare
  v_cols text[];
begin
  select array_agg(column_name::text order by column_name::text)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'structure_events';

  if v_cols is distinct from array[
    'actor_membership_id', 'actor_user_profile_id', 'after_value', 'before_value',
    'created_at', 'effective_date', 'entity_id', 'entity_type', 'event_type',
    'id', 'operation_id', 'organization_id', 'payload_hash', 'reason',
    'result_entity_id']::text[]
  then
    raise exception '[FAIL] structure_events: colunas fora do contrato (§8.3): %', v_cols;
  end if;
  raise notice '[PASS] structure_events: colunas exatas do contrato (§8.3)';
end $$;

do $$
declare
  v_obrigatorias_nulas int;
  v_opcionais_not_null int;
begin
  select count(*) into v_obrigatorias_nulas
  from information_schema.columns
  where table_schema = 'public' and table_name = 'structure_events'
    and column_name in (
      'id', 'organization_id', 'entity_type', 'event_type', 'effective_date',
      'reason', 'payload_hash', 'actor_user_profile_id', 'actor_membership_id',
      'operation_id', 'created_at')
    and is_nullable = 'YES';

  select count(*) into v_opcionais_not_null
  from information_schema.columns
  where table_schema = 'public' and table_name = 'structure_events'
    and column_name in ('entity_id', 'before_value', 'after_value', 'result_entity_id')
    and is_nullable = 'NO';

  if v_obrigatorias_nulas <> 0 or v_opcionais_not_null <> 0 then
    raise exception
      '[FAIL] structure_events: nulabilidade divergente (obrigatorias nulas=%, opcionais not null=%)',
      v_obrigatorias_nulas, v_opcionais_not_null;
  end if;
  raise notice '[PASS] structure_events: NOT NULL do contrato (entity_id/before/after/result opcionais)';
end $$;

do $$
declare
  v_faltando text[];
begin
  select array_agg(c.conname order by c.conname)
    into v_faltando
  from pg_constraint c
  where c.conrelid = 'public.structure_events'::regclass
    and c.conname in (
      'pk_structure_events',
      'uq_structure_events_org_operation',
      'fk_structure_events_organizations',
      'fk_structure_events_actor',
      'fk_structure_events_actor_membership',
      'ck_structure_events_entity_type',
      'ck_structure_events_event_type',
      'ck_structure_events_reason');

  if v_faltando is null or array_length(v_faltando, 1) <> 8 then
    raise exception '[FAIL] structure_events: constraints ausentes (%)', v_faltando;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'uq_structure_events_org_operation'
      and conrelid = 'public.structure_events'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) like '%(organization_id, operation_id)%'
  ) then
    raise exception '[FAIL] Idempotencia: unique (organization_id, operation_id) ausente/incorreta';
  end if;

  raise notice '[PASS] structure_events: PK, unique de idempotencia, 3 FKs e 3 CHECKs presentes';
end $$;

do $$
declare
  v_faltando text[];
begin
  select array_agg(i.indexname order by i.indexname)
    into v_faltando
  from pg_indexes i
  where i.schemaname = 'public' and i.tablename = 'structure_events'
    and i.indexname in (
      'ix_structure_events_organization_id',
      'ix_structure_events_entity',
      'ix_structure_events_effective');

  if v_faltando is null or array_length(v_faltando, 1) <> 3 then
    raise exception '[FAIL] structure_events: indices do contrato ausentes (%)', v_faltando;
  end if;
  raise notice '[PASS] structure_events: 3 indices do contrato presentes';
end $$;

do $$
declare
  v_rls boolean;
begin
  select c.relrowsecurity into v_rls
  from pg_class c
  where c.oid = 'public.structure_events'::regclass;

  if v_rls is not true then
    raise exception '[FAIL] structure_events: RLS nao habilitada';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'structure_events'
  ) then
    raise exception '[FAIL] structure_events: policy criada (deve ser deny-by-default integral)';
  end if;
  raise notice '[PASS] structure_events: RLS habilitada e SEM policies (deny-by-default integral)';
end $$;

do $$
declare
  v_def text;
begin
  select pg_get_triggerdef(t.oid) into v_def
  from pg_trigger t
  where t.tgrelid = 'public.structure_events'::regclass
    and t.tgname = 'trg_structure_events_append_only'
    and not t.tgisinternal;

  if v_def is null or v_def not like '%BEFORE UPDATE%' then
    raise exception '[FAIL] structure_events: trigger append-only ausente (UPDATE)';
  end if;
  raise notice '[PASS] structure_events: trigger append-only BEFORE UPDATE presente';
end $$;

-- ----------------------------------------------------------------------------
-- 1.1 Grants de `structure_events`: somente service_role (SELECT, INSERT)
-- ----------------------------------------------------------------------------
do $$
declare
  v_problemas text[] := array[]::text[];
begin
  if has_table_privilege('service_role', 'public.structure_events', 'SELECT') is not true then
    v_problemas := v_problemas || 'service_role sem SELECT';
  end if;
  if has_table_privilege('service_role', 'public.structure_events', 'INSERT') is not true then
    v_problemas := v_problemas || 'service_role sem INSERT';
  end if;
  if has_table_privilege('service_role', 'public.structure_events', 'UPDATE') then
    v_problemas := v_problemas || 'service_role com UPDATE';
  end if;
  if has_table_privilege('service_role', 'public.structure_events', 'DELETE') then
    v_problemas := v_problemas || 'service_role com DELETE';
  end if;
  if has_table_privilege('authenticated', 'public.structure_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.structure_events', 'INSERT')
     or has_table_privilege('authenticated', 'public.structure_events', 'UPDATE')
     or has_table_privilege('authenticated', 'public.structure_events', 'DELETE') then
    v_problemas := v_problemas || 'authenticated com privilegio';
  end if;
  if has_table_privilege('anon', 'public.structure_events', 'SELECT')
     or has_table_privilege('anon', 'public.structure_events', 'INSERT')
     or has_table_privilege('anon', 'public.structure_events', 'UPDATE')
     or has_table_privilege('anon', 'public.structure_events', 'DELETE') then
    v_problemas := v_problemas || 'anon com privilegio';
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] grants de structure_events: %', array_to_string(v_problemas, '; ');
  end if;
  raise notice '[PASS] grants de structure_events: service_role apenas SELECT/INSERT; anon/authenticated sem acesso';
end $$;

-- ----------------------------------------------------------------------------
-- 1.2 Comportamento: SELECT/INSERT permitidos a service_role; UPDATE e DELETE
--     negados (append-only no banco + ausencia de grant)
-- ----------------------------------------------------------------------------
set role service_role;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.structure_events
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] service_role deveria ler a trilha do tenant (leu %)', v_n;
  end if;
  raise notice '[PASS] service_role le a trilha (SELECT permitido)';
end $$;

do $$
begin
  -- Camada 1 (grants): service_role NAO tem UPDATE na trilha — o PostgreSQL
  -- recusa por privilegio ANTES de qualquer trigger (D8/§13.3).
  begin
    update public.structure_events
       set reason = reason
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] UPDATE permitido a service_role em structure_events';
  exception
    when insufficient_privilege then
      raise notice '[PASS] UPDATE negado a service_role em structure_events (sem grant — D8)';
    when others then
      raise;
  end;

  begin
    delete from public.structure_events
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] DELETE permitido a service_role em structure_events';
  exception
    when insufficient_privilege then
      raise notice '[PASS] DELETE negado a service_role em structure_events (sem grant)';
    when others then
      raise;
  end;

  -- INSERT permitido (probe revertido por excecao sentinela).
  begin
    insert into public.structure_events
      (organization_id, entity_type, entity_id, event_type, effective_date,
       reason, after_value, payload_hash, actor_user_profile_id,
       actor_membership_id, operation_id)
    values
      ('f8a00000-0000-0000-0000-0000000000a1', 'organizational_unit',
       'f8110000-0000-0000-0000-000000000001', 'CRIADO',
       '2026-01-01T00:00:00Z', 'probe de INSERT do caminho server-side',
       '{"probe": true}'::jsonb, 'probe-hash-f5-08',
       'f8c00000-0000-0000-0000-0000000000a1',
       'f8d00000-0000-0000-0000-0000000000a1',
       'f8900000-0000-0000-0000-0000000000ff');
    raise exception 'F5-08_PROBE_ROLLBACK';
  exception
    when others then
      if sqlerrm = 'F5-08_PROBE_ROLLBACK' then
        raise notice '[PASS] INSERT permitido a service_role na trilha (probe revertido)';
      else
        raise;
      end if;
  end;
end $$;

reset role;

-- Camada 2 (trigger append-only): exercitada como OWNER/superuser — que passa
-- pela ACL mas NAO pelo trigger. Prova a defesa em profundidade no BANCO
-- (D13/§8.3), independentemente de grants.
do $$
begin
  begin
    update public.structure_events
       set reason = reason
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] trigger append-only nao disparou (UPDATE aceito pelo owner)';
  exception
    when others then
      if sqlerrm like '%F5-08: structure_events e append-only%' then
        raise notice '[PASS] trigger append-only bloqueia UPDATE ate para o owner (defesa em profundidade)';
      else
        raise;
      end if;
  end;
end $$;

-- `authenticated` nao escreve nem na trilha nem nas tabelas de estrutura.
set role authenticated;

do $$
begin
  begin
    insert into public.structure_events
      (organization_id, entity_type, entity_id, event_type, effective_date,
       reason, payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values
      ('f8a00000-0000-0000-0000-0000000000a1', 'organizational_unit',
       'f8110000-0000-0000-0000-000000000001', 'CRIADO',
       '2026-01-01T00:00:00Z', 'tentativa authenticated', 'hash-auth',
       'f8c00000-0000-0000-0000-0000000000a1',
       'f8d00000-0000-0000-0000-0000000000a1',
       'f8900000-0000-0000-0000-0000000000fe');
    raise exception '[FAIL] authenticated conseguiu inserir em structure_events';
  exception
    when insufficient_privilege then
      raise notice '[PASS] authenticated NAO insere em structure_events (permission denied)';
    when others then
      raise;
  end;

  begin
    update public.organizational_units set name = name
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] authenticated conseguiu atualizar organizational_units';
  exception
    when insufficient_privilege then
      raise notice '[PASS] authenticated NAO atualiza organizational_units (permission denied)';
    when others then
      raise;
  end;

  begin
    delete from public.organizational_positions
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] authenticated conseguiu deletar organizational_positions';
  exception
    when insufficient_privilege then
      raise notice '[PASS] authenticated NAO deleta organizational_positions (permission denied)';
    when others then
      raise;
  end;
end $$;

reset role;

-- ============================================================================
-- 2) I1 — anti-ciclo de unidades (D7/§10.2 I1)
-- ============================================================================

do $$
declare
  v_def text;
begin
  select pg_get_triggerdef(t.oid) into v_def
  from pg_trigger t
  where t.tgrelid = 'public.organizational_unit_parent_periods'::regclass
    and t.tgname = 'trg_organizational_unit_parent_periods_no_cycle'
    and not t.tgisinternal;

  if v_def is null or v_def not like '%BEFORE INSERT OR UPDATE%' then
    raise exception '[FAIL] I1: trigger anti-ciclo de unidades ausente ou fora de BEFORE INSERT OR UPDATE';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'enforce_organizational_unit_parent_periods_no_cycle'
      and p.prosrc like '%position_reporting_lines:%'
      and p.prosrc like '%organization_id%'
      and p.prosecdef = false
  ) then
    raise exception '[FAIL] I1: funcao sem chave normativa de lock, sem escopo de tenant ou com SECURITY DEFINER';
  end if;
  raise notice '[PASS] I1: trigger temporal BEFORE INSERT OR UPDATE + lock normativo por organizacao';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.organizational_unit_parent_periods
  where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
    and unit_id in ('f8110000-0000-0000-0000-000000000002',
                    'f8110000-0000-0000-0000-000000000003',
                    'f8110000-0000-0000-0000-00000000000b',
                    'f8110000-0000-0000-0000-00000000000c');
  if v_n <> 4 then
    raise exception '[FAIL] I1: cadeia valida do cenario ausente (esperado 4 periodos, achou %)', v_n;
  end if;
  raise notice '[PASS] I1: cadeia valida de unidades aceita na gravacao (filha->raiz, neta->filha, m1->m2->m3)';
end $$;

do $$
begin
  -- Ciclo DIRETO: d1 -> d2 ja existe; d2 -> d1 deve ser recusado.
  begin
    insert into public.organizational_unit_parent_periods
      (organization_id, unit_id, parent_unit_id, valid_from)
    values
      ('f8a00000-0000-0000-0000-0000000000a1',
       'f8110000-0000-0000-0000-00000000000a',
       'f8110000-0000-0000-0000-000000000009',
       '2026-01-01T00:00:00Z');
    raise exception '[FAIL] I1: ciclo direto entre unidades foi aceito';
  exception
    when others then
      if sqlerrm like '%ciclo hierarquico de unidades%' then
        raise notice '[PASS] I1: ciclo DIRETO entre unidades recusado';
      else
        raise;
      end if;
  end;

  -- Ciclo MULTINIVEL: m1 -> m2 -> m3 ja existe; m3 -> m1 deve ser recusado.
  begin
    insert into public.organizational_unit_parent_periods
      (organization_id, unit_id, parent_unit_id, valid_from)
    values
      ('f8a00000-0000-0000-0000-0000000000a1',
       'f8110000-0000-0000-0000-00000000000d',
       'f8110000-0000-0000-0000-00000000000b',
       '2026-01-01T00:00:00Z');
    raise exception '[FAIL] I1: ciclo MULTINIVEL (3 niveis) entre unidades foi aceito';
  exception
    when others then
      if sqlerrm like '%ciclo hierarquico de unidades%' then
        raise notice '[PASS] I1: ciclo MULTINIVEL (3 niveis) recusado';
      else
        raise;
      end if;
  end;
end $$;

do $$
begin
  -- Caso VALIDO por temporalidade: t1 -> t2 e t2 -> t3 valem em [T0,T1);
  -- t3 -> t1 em [T2,T3) (disjunto) NAO forma ciclo simultaneo e deve ser aceito.
  begin
    insert into public.organizational_unit_parent_periods
      (organization_id, unit_id, parent_unit_id, valid_from, valid_to)
    values
      ('f8a00000-0000-0000-0000-0000000000a1',
       'f8110000-0000-0000-0000-000000000010',
       'f8110000-0000-0000-0000-00000000000e',
       '2026-03-01T00:00:00Z', '2026-04-01T00:00:00Z');
  exception
    when others then
      raise exception '[FAIL] I1: janela temporal DISJUNTA recusada indevidamente (%)', sqlerrm;
  end;
  raise notice '[PASS] I1: janela temporal DISJUNTA aceita (analise restrita a estrutura vigente na janela)';

  -- Mesmo par, janela SOBREPOSTA a cadeia: agora e ciclo e deve ser recusado.
  begin
    insert into public.organizational_unit_parent_periods
      (organization_id, unit_id, parent_unit_id, valid_from, valid_to)
    values
      ('f8a00000-0000-0000-0000-0000000000a1',
       'f8110000-0000-0000-0000-000000000010',
       'f8110000-0000-0000-0000-00000000000e',
       '2026-01-01T00:00:00Z', '2026-02-01T00:00:00Z');
    raise exception '[FAIL] I1: ciclo em janela SOBREPOSTA foi aceito';
  exception
    when others then
      if sqlerrm like '%ciclo hierarquico de unidades%' then
        raise notice '[PASS] I1: ciclo em janela SOBREPOSTA recusado (semantica [valid_from, valid_to))';
      else
        raise;
      end if;
  end;
end $$;

do $$
begin
  -- FALSO POSITIVO (corrigido na auditoria do PR #183): a linha nova tem
  -- janela AMPLA [2026-01-01, 2026-12-31) e as arestas do caminho existem em
  -- SUBPERIODOS DISJUNTOS — A->B em [01-10,01-20) e B->C em [02-10,02-20).
  -- Cada aresta se sobrepoe individualmente a janela de NEW, mas NAO existe
  -- instante com todas as arestas vigentes ao mesmo tempo ⇒ NAO ha ciclo
  -- temporal real ⇒ a operacao deve ser ACEITA (intersecao acumulada vazia).
  begin
    insert into public.organizational_unit_parent_periods
      (organization_id, unit_id, parent_unit_id, valid_from, valid_to)
    values
      ('f8a00000-0000-0000-0000-0000000000a1',
       'f8110000-0000-0000-0000-000000000011',
       'f8110000-0000-0000-0000-000000000012',
       '2026-01-01T00:00:00Z', '2026-12-31T00:00:00Z');
  exception
    when others then
      raise exception '[FAIL] I1: FALSO POSITIVO — estrutura temporal VALIDA recusada (%)', sqlerrm;
  end;
  raise notice '[PASS] I1: sem falso positivo — arestas em subperiodos disjuntos NAO formam ciclo temporal';

  -- CONTROLE POSITIVO do mesmo formato: agora as arestas tem INTERSECCAO NAO
  -- VAZIA ([01-20,01-25)) ⇒ existe ciclo temporal REAL ⇒ recusa obrigatoria.
  begin
    insert into public.organizational_unit_parent_periods
      (organization_id, unit_id, parent_unit_id, valid_from, valid_to)
    values
      ('f8a00000-0000-0000-0000-0000000000a1',
       'f8110000-0000-0000-0000-000000000014',
       'f8110000-0000-0000-0000-000000000015',
       '2026-01-01T00:00:00Z', '2026-12-31T00:00:00Z');
    raise exception '[FAIL] I1: ciclo temporal REAL com intersecao estreita foi aceito';
  exception
    when others then
      if sqlerrm like '%ciclo hierarquico de unidades%' then
        raise notice '[PASS] I1: ciclo temporal REAL (intersecao nao vazia) continua recusado';
      else
        raise;
      end if;
  end;
end $$;

do $$
declare
  v_n int;
begin
  -- Isolamento por tenant: a cadeia valida de Beta permanece intacta e o
  -- anti-ciclo tambem vale para Beta (recusando b-raiz -> b-neta).
  select count(*) into v_n
  from public.organizational_unit_parent_periods
  where organization_id = 'f8a00000-0000-0000-0000-0000000000b1';
  if v_n <> 2 then
    raise exception '[FAIL] I1: cadeia valida de Beta ausente (esperado 2, achou %)', v_n;
  end if;

  begin
    insert into public.organizational_unit_parent_periods
      (organization_id, unit_id, parent_unit_id, valid_from)
    values
      ('f8a00000-0000-0000-0000-0000000000b1',
       'f8210000-0000-0000-0000-000000000001',
       'f8210000-0000-0000-0000-000000000003',
       '2026-01-01T00:00:00Z');
    raise exception '[FAIL] I1: ciclo entre unidades de Beta foi aceito';
  exception
    when others then
      if sqlerrm like '%ciclo hierarquico de unidades%' then
        raise notice '[PASS] I1: anti-ciclo aplicado por tenant (ciclo em Beta recusado; cadeia de Alfa intacta)';
      else
        raise;
      end if;
  end;
end $$;

-- ============================================================================
-- 3) I2 — encerramento de UNIDADE: os TRES casos (D6, revisao PR #182)
-- ============================================================================

do $$
declare
  v_def text;
begin
  select pg_get_triggerdef(t.oid) into v_def
  from pg_trigger t
  where t.tgrelid = 'public.organizational_units'::regclass
    and t.tgname = 'trg_organizational_units_close_structure'
    and not t.tgisinternal;

  if v_def is null or v_def not like '%BEFORE UPDATE OF valid_from, valid_to%' then
    raise exception '[FAIL] I2: trigger de encerramento de unidade ausente ou fora de BEFORE UPDATE OF valid_from, valid_to';
  end if;
  raise notice '[PASS] I2: trigger BEFORE UPDATE OF valid_from, valid_to presente';
end $$;

do $$
begin
  -- Caso (i): posicao vigente na unidade.
  begin
    update public.organizational_units
       set valid_to = '2026-05-01T00:00:00Z'
     where id = 'f8110000-0000-0000-0000-000000000004';
    raise exception '[FAIL] I2(i): encerrar unidade com POSICAO vigente foi aceito';
  exception
    when others then
      if sqlerrm like '%posicao vigente na data de encerramento%' then
        raise notice '[PASS] I2(i): encerrar unidade com POSICAO vigente recusado';
      else
        raise;
      end if;
  end;

  -- Caso (ii): unidade como FILHA em parent-period vigente.
  begin
    update public.organizational_units
       set valid_to = '2026-05-01T00:00:00Z'
     where id = 'f8110000-0000-0000-0000-000000000007';
    raise exception '[FAIL] I2(ii): encerrar unidade como FILHA de relacao vigente foi aceito';
  exception
    when others then
      if sqlerrm like '%unidade como filha%' then
        raise notice '[PASS] I2(ii): encerrar unidade como FILHA de relacao vigente recusado';
      else
        raise;
      end if;
  end;

  -- Caso (iii): unidade como PAI de relacao vigente (unidade filha ativa
  -- apontando para pai encerrado seria estrutura impossivel).
  begin
    update public.organizational_units
       set valid_to = '2026-05-01T00:00:00Z'
     where id = 'f8110000-0000-0000-0000-000000000006';
    raise exception '[FAIL] I2(iii): encerrar unidade como PAI de relacao vigente foi aceito';
  exception
    when others then
      if sqlerrm like '%unidade como pai%' then
        raise notice '[PASS] I2(iii): encerrar unidade como PAI de relacao vigente recusado';
      else
        raise;
      end if;
  end;
end $$;

do $$
declare
  v_unidade record;
  v_periodo record;
begin
  -- Semantica `[)`: encerrar a relacao dependente EXATAMENTE em TC libera o
  -- encerramento da unidade em TC (a relacao nao e vigente em TC).
  update public.organizational_unit_parent_periods
     set valid_to = '2026-05-01T00:00:00Z'
   where id = 'f8710000-0000-0000-0000-000000000006';

  update public.organizational_units
     set valid_to = '2026-05-01T00:00:00Z'
   where id = 'f8110000-0000-0000-0000-000000000007';

  update public.organizational_units
     set valid_to = '2026-05-01T00:00:00Z'
   where id = 'f8110000-0000-0000-0000-000000000006';

  raise notice '[PASS] I2: relacao encerrada em T e unidade encerrada em T => permitido (filha e pai)';

  -- Historico preservado: a linha encerrada continua existindo (nunca DELETE).
  select valid_to into v_unidade
  from public.organizational_units
  where id = 'f8110000-0000-0000-0000-000000000006';
  if v_unidade.valid_to is distinct from '2026-05-01T00:00:00Z'::timestamptz then
    raise exception '[FAIL] I2: unidade encerrada perdeu o fato registrado (valid_to=%)', v_unidade.valid_to;
  end if;

  select valid_to into v_periodo
  from public.organizational_unit_parent_periods
  where id = 'f8710000-0000-0000-0000-000000000006';
  if v_periodo.valid_to is distinct from '2026-05-01T00:00:00Z'::timestamptz then
    raise exception '[FAIL] I2: periodo parent encerrado perdeu o fato registrado (valid_to=%)', v_periodo.valid_to;
  end if;

  -- E nao existe estrutura "vigente" em TC depois do encerramento.
  if exists (
    select 1
    from public.organizational_unit_parent_periods pp
    where pp.id = 'f8710000-0000-0000-0000-000000000006'
      and pp.valid_from <= '2026-05-01T00:00:00Z'
      and (pp.valid_to is null or pp.valid_to > '2026-05-01T00:00:00Z')
  ) then
    raise exception '[FAIL] I2: relacao encerrada em TC ainda considerada vigente em TC';
  end if;
  raise notice '[PASS] I2: historico preservado e relacao encerrada em TC nao e vigente em TC';
end $$;

do $$
begin
  -- Unidade sem dependencia (apenas relacao como filha) encerrada em TC.
  update public.organizational_unit_parent_periods
     set valid_to = '2026-05-01T00:00:00Z'
   where id = 'f8710000-0000-0000-0000-000000000007';

  update public.organizational_units
     set valid_to = '2026-05-01T00:00:00Z'
   where id = 'f8110000-0000-0000-0000-000000000008';

  raise notice '[PASS] I2: encerramento de unidade sem estrutura vigente permitido (historico mantido)';
end $$;

-- ============================================================================
-- 4) I3 — encerramento de POSICAO com ocupacao vigente (D6)
-- ============================================================================

do $$
declare
  v_def_ocup text;
  v_def_rl text;
begin
  select pg_get_triggerdef(t.oid) into v_def_ocup
  from pg_trigger t
  where t.tgrelid = 'public.organizational_positions'::regclass
    and t.tgname = 'trg_organizational_positions_close_occupations'
    and not t.tgisinternal;

  select pg_get_triggerdef(t.oid) into v_def_rl
  from pg_trigger t
  where t.tgrelid = 'public.organizational_positions'::regclass
    and t.tgname = 'trg_organizational_positions_close_reporting_lines'
    and not t.tgisinternal;

  if v_def_ocup is null or v_def_ocup not like '%BEFORE UPDATE OF valid_from, valid_to%' then
    raise exception '[FAIL] I3: trigger de encerramento de posicao (ocupacao) ausente';
  end if;

  if v_def_rl is null then
    raise exception '[FAIL] I3: trigger F3-04 de reporting line foi removido (regressao)';
  end if;
  raise notice '[PASS] I3: trigger de ocupacao presente e trigger F3-04 de reporting line preservado';
end $$;

do $$
begin
  -- Posicao com ocupacao vigente.
  begin
    update public.organizational_positions
       set valid_to = '2026-05-01T00:00:00Z'
     where id = 'f8310000-0000-0000-0000-000000000001';
    raise exception '[FAIL] I3: encerrar posicao com OCUPACAO vigente foi aceito';
  exception
    when others then
      if sqlerrm like '%ocupacao vigente na data de encerramento%' then
        raise notice '[PASS] I3: encerrar posicao com OCUPACAO vigente recusado';
      else
        raise;
      end if;
  end;

  -- Guarda da F3-04 continua ativa (reporting line vigente).
  begin
    update public.organizational_positions
       set valid_to = '2026-05-01T00:00:00Z'
     where id = 'f8310000-0000-0000-0000-000000000002';
    raise exception '[FAIL] I3: encerrar posicao com REPORTING LINE vigente foi aceito';
  exception
    when others then
      if sqlerrm like '%reporting lines fora da nova validade%' then
        raise notice '[PASS] I3: encerrar posicao com REPORTING LINE vigente recusado (guarda F3-04 intacta)';
      else
        raise;
      end if;
  end;
end $$;

do $$
declare
  v_to timestamptz;
begin
  -- Ocupacao encerrada exatamente em TC libera o encerramento da posicao em TC.
  update public.occupations
     set valid_to = '2026-05-01T00:00:00Z'
   where id = 'f8410000-0000-0000-0000-000000000002';

  update public.organizational_positions
     set valid_to = '2026-05-01T00:00:00Z'
   where id = 'f8310000-0000-0000-0000-000000000004';

  select valid_to into v_to
  from public.organizational_positions
  where id = 'f8310000-0000-0000-0000-000000000004';

  if v_to is distinct from '2026-05-01T00:00:00Z'::timestamptz then
    raise exception '[FAIL] I3: encerramento permitido nao foi gravado (valid_to=%)', v_to;
  end if;
  raise notice '[PASS] I3: ocupacao encerrada em T e posicao encerrada em T => permitido; historico preservado';
end $$;

-- ============================================================================
-- 5) D24 — as 4 RPCs estruturais da F5-07 com a chave normativa
-- ============================================================================

do $$
declare
  v_esperado text[] := array[
    'estrutura_ocupacao_definir',
    'estrutura_ocupacao_encerrar',
    'estrutura_reporting_definir',
    'estrutura_reporting_encerrar'];
  v_nome text;
  v_args text;
  v_retorno text;
  v_definer boolean;
  v_prosrc text;
  v_esperado_args text[];
  v_esperado_retorno text[];
  v_i int := 0;
begin
  v_esperado_args := array[
    'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_position_id uuid, p_vigencia timestamp with time zone, p_motivo text, p_cycle_scope text, p_reference_cycle_id uuid',
    'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_collaborator_id uuid, p_vigencia timestamp with time zone, p_motivo text',
    'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_subordinate_position_id uuid, p_manager_position_id uuid, p_vigencia timestamp with time zone, p_motivo text',
    'p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid, p_subordinate_position_id uuid, p_vigencia timestamp with time zone, p_motivo text'];
  v_esperado_retorno := array['uuid', 'void', 'uuid', 'void'];

  foreach v_nome in array v_esperado loop
    v_i := v_i + 1;

    select pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid),
           p.prosecdef, p.prosrc
      into v_args, v_retorno, v_definer, v_prosrc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = v_nome;

    if v_args is null then
      raise exception '[FAIL] D24: funcao % ausente', v_nome;
    end if;

    if v_args <> v_esperado_args[v_i] then
      raise exception '[FAIL] D24: assinatura de % mudou (%)', v_nome, v_args;
    end if;

    if v_retorno <> v_esperado_retorno[v_i] then
      raise exception '[FAIL] D24: retorno de % mudou (%)', v_nome, v_retorno;
    end if;

    if v_definer then
      raise exception '[FAIL] D24: % virou SECURITY DEFINER', v_nome;
    end if;

    if position('position_reporting_lines:' in v_prosrc) = 0 then
      raise exception '[FAIL] D24: % nao usa a chave normativa de advisory lock', v_nome;
    end if;

    if position('f5_07_estrutura:' in v_prosrc) > 0 then
      raise exception '[FAIL] D24: % ainda usa a chave antiga f5_07_estrutura:', v_nome;
    end if;
  end loop;

  raise notice '[PASS] D24: as 4 RPCs usam a chave normativa, com assinatura/retorno/INVOKER preservados';
end $$;

do $$
declare
  v_pendentes text[];
begin
  select array_agg(p.proname order by p.proname) into v_pendentes
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'estrutura\_%'
    and p.prosrc like '%f5_07_estrutura:%';

  if v_pendentes is not null then
    raise exception '[FAIL] D24: funcoes estruturais com a chave antiga: %', v_pendentes;
  end if;
  raise notice '[PASS] D24: nenhuma funcao estrutural ativa usa f5_07_estrutura:';
end $$;

do $$
declare
  v_assinaturas text[] := array[
    'public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamp with time zone, text, text, uuid)',
    'public.estrutura_ocupacao_encerrar(uuid, uuid, uuid, uuid, timestamp with time zone, text)',
    'public.estrutura_reporting_definir(uuid, uuid, uuid, uuid, uuid, timestamp with time zone, text)',
    'public.estrutura_reporting_encerrar(uuid, uuid, uuid, uuid, timestamp with time zone, text)'];
  v_assinatura text;
  v_problemas text[] := array[]::text[];
begin
  foreach v_assinatura in array v_assinaturas loop
    -- ACLs preservadas pelo `create or replace`: service_role mantem EXECUTE...
    if has_function_privilege('service_role', v_assinatura, 'EXECUTE') is not true then
      v_problemas := v_problemas || ('service_role sem EXECUTE em ' || v_assinatura);
    end if;
    -- ...e anon/authenticated continuam sem qualquer superficie (D10/§13.4).
    if has_function_privilege('anon', v_assinatura, 'EXECUTE')
       or has_function_privilege('authenticated', v_assinatura, 'EXECUTE') then
      v_problemas := v_problemas || ('EXECUTE exposto a anon/authenticated em ' || v_assinatura);
    end if;
  end loop;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] D24: ACLs das RPCs estruturais: %', array_to_string(v_problemas, '; ');
  end if;
  raise notice '[PASS] D24: ACLs preservadas (service_role com EXECUTE; nada exposto a anon/authenticated)';
end $$;

-- ============================================================================
-- 6) Grants/RLS das tabelas administradas e ausencia de SECURITY DEFINER novo
-- ============================================================================

do $$
declare
  v_tabelas text[] := array[
    'organizational_units',
    'organizational_unit_parent_periods',
    'organizational_positions',
    'position_reporting_lines',
    'job_roles',
    'seniority_levels',
    'collegiate_configurations',
    'collegiate_configuration_members'];
  v_tab text;
  v_problemas text[] := array[]::text[];
begin
  foreach v_tab in array v_tabelas loop
    -- service_role: SELECT/INSERT/UPDATE sim, DELETE nao (D8).
    if has_table_privilege('service_role', format('public.%I', v_tab), 'SELECT') is not true
       or has_table_privilege('service_role', format('public.%I', v_tab), 'INSERT') is not true
       or has_table_privilege('service_role', format('public.%I', v_tab), 'UPDATE') is not true then
      v_problemas := v_problemas || (v_tab || ': service_role sem SELECT/INSERT/UPDATE');
    end if;
    if has_table_privilege('service_role', format('public.%I', v_tab), 'DELETE') then
      v_problemas := v_problemas || (v_tab || ': service_role com DELETE');
    end if;

    -- authenticated: somente SELECT (contrato F4-08).
    if has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT') is not true then
      v_problemas := v_problemas || (v_tab || ': authenticated sem SELECT (regressao F4-08)');
    end if;
    if has_table_privilege('authenticated', format('public.%I', v_tab), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'DELETE') then
      v_problemas := v_problemas || (v_tab || ': authenticated com DML');
    end if;

    -- anon: nada.
    if has_table_privilege('anon', format('public.%I', v_tab), 'SELECT')
       or has_table_privilege('anon', format('public.%I', v_tab), 'INSERT')
       or has_table_privilege('anon', format('public.%I', v_tab), 'UPDATE')
       or has_table_privilege('anon', format('public.%I', v_tab), 'DELETE') then
      v_problemas := v_problemas || (v_tab || ': anon com privilegio');
    end if;

    -- nenhuma policy de escrita (somente SELECT own-tenant da F4-08).
    if exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = v_tab
        and cmd <> 'SELECT'
    ) then
      v_problemas := v_problemas || (v_tab || ': policy de escrita criada');
    end if;
  end loop;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] grants/policies das tabelas administradas: %', array_to_string(v_problemas, '; ');
  end if;
  raise notice '[PASS] grants: service_role sem DELETE, authenticated so SELECT, anon sem acesso, nenhuma policy de escrita';
end $$;

do $$
declare
  v_definer text[];
begin
  select array_agg(p.proname order by p.proname) into v_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'enforce_structure_events_append_only',
      'enforce_organizational_unit_parent_periods_no_cycle',
      'enforce_organizational_unit_close_requires_no_open_structure',
      'enforce_organizational_position_close_requires_no_open_occupations')
    and p.prosecdef;

  if v_definer is not null then
    raise exception '[FAIL] SECURITY DEFINER novo nas funcoes de trigger: %', v_definer;
  end if;

  if has_function_privilege('authenticated', 'public.enforce_structure_events_append_only()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.enforce_organizational_unit_parent_periods_no_cycle()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.enforce_organizational_unit_close_requires_no_open_structure()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.enforce_organizational_position_close_requires_no_open_occupations()', 'EXECUTE') then
    raise exception '[FAIL] funcao de trigger exposta a authenticated (EXECUTE)';
  end if;

  raise notice '[PASS] funcoes de trigger: SECURITY INVOKER e sem EXECUTE para anon/authenticated';
end $$;


-- ============================================================================
-- 8) P2 — RPCs soberanas: catalogo de seguranca, autorizacao, tenant,
--    idempotencia, versionamento e unidades
-- ============================================================================
-- As chamadas usam o MESMO caminho do produto: sessao como `service_role`
-- (a fronteira executa a RPC e NUNCA decide autorizacao — a decisao e
-- revalidada dentro de cada funcao por ator + capability efetiva).
set role service_role;

-- ----------------------------------------------------------------------------
-- 8.1 Catalogo das 15 RPCs: assinatura, SECURITY INVOKER, search_path e EXECUTE
-- ----------------------------------------------------------------------------
do $$
declare
  v_assinaturas text[] := array[
    'public.estrutura_unidade_criar(uuid, uuid, uuid, text, timestamp with time zone, text)',
    'public.estrutura_unidade_renomear(uuid, uuid, uuid, uuid, text, integer, text)',
    'public.estrutura_unidade_encerrar(uuid, uuid, uuid, uuid, timestamp with time zone, integer, text)',
    'public.estrutura_unidade_parent_definir(uuid, uuid, uuid, uuid, uuid, timestamp with time zone, text)',
    'public.estrutura_unidade_parent_encerrar(uuid, uuid, uuid, uuid, timestamp with time zone, text)',
    'public.estrutura_posicao_criar(uuid, uuid, uuid, uuid, uuid, uuid, timestamp with time zone, text)',
    'public.estrutura_posicao_encerrar(uuid, uuid, uuid, uuid, timestamp with time zone, integer, text)',
    'public.estrutura_colegiado_definir(uuid, uuid, uuid, uuid, uuid[], timestamp with time zone, text)',
    'public.estrutura_colegiado_encerrar(uuid, uuid, uuid, uuid, timestamp with time zone, text)',
    'public.catalogo_cargo_criar(uuid, uuid, uuid, text, text, text)',
    'public.catalogo_cargo_renomear(uuid, uuid, uuid, uuid, text, integer, text)',
    'public.catalogo_cargo_status_alterar(uuid, uuid, uuid, uuid, text, integer, text)',
    'public.catalogo_senioridade_criar(uuid, uuid, uuid, text, text)',
    'public.catalogo_senioridade_renomear(uuid, uuid, uuid, uuid, text, integer, text)',
    'public.catalogo_senioridade_status_alterar(uuid, uuid, uuid, uuid, text, integer, text)'];
  v_sig   text;
  v_f     record;
  v_nomes text[] := array[]::text[];
begin
  if array_length(v_assinaturas, 1) <> 15 then
    raise exception '[FAIL] K: lista de assinaturas do P2 deveria ter 15 itens';
  end if;

  foreach v_sig in array v_assinaturas loop
    select p.proname, p.prosecdef,
           coalesce(array_to_string(p.proconfig, ','), '') as config
      into v_f
      from pg_proc p
     where p.oid = v_sig::regprocedure;

    if v_f.proname is null then
      raise exception '[FAIL] K: RPC ausente: %', v_sig;
    end if;
    if v_f.prosecdef then
      raise exception '[FAIL] K: % e SECURITY DEFINER (proibido)', v_f.proname;
    end if;
    if position('search_path=public' in v_f.config) = 0 then
      raise exception '[FAIL] K: % sem search_path fixo em public (%)', v_f.proname, v_f.config;
    end if;
    if not has_function_privilege('service_role', v_sig, 'EXECUTE') then
      raise exception '[FAIL] K: service_role sem EXECUTE em %', v_f.proname;
    end if;
    if has_function_privilege('anon', v_sig, 'EXECUTE')
       or has_function_privilege('authenticated', v_sig, 'EXECUTE') then
      raise exception '[FAIL] K: % exposta a anon/authenticated', v_f.proname;
    end if;
    v_nomes := v_nomes || v_f.proname;
  end loop;

  -- Nenhuma outra RPC das 15 e nenhum SECURITY DEFINER novo em public.
  if exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = any (array[
         'estrutura_unidade_criar','estrutura_unidade_renomear',
         'estrutura_unidade_encerrar','estrutura_unidade_parent_definir',
         'estrutura_unidade_parent_encerrar','estrutura_posicao_criar',
         'estrutura_posicao_encerrar','estrutura_colegiado_definir',
         'estrutura_colegiado_encerrar','catalogo_cargo_criar',
         'catalogo_cargo_renomear','catalogo_cargo_status_alterar',
         'catalogo_senioridade_criar','catalogo_senioridade_renomear',
         'catalogo_senioridade_status_alterar'])
       and p.prosecdef
  ) then
    raise exception '[FAIL] K: RPC do P2 com SECURITY DEFINER';
  end if;

  raise notice '[PASS] K: 15 RPCs INVOKER, search_path fixo, EXECUTE somente service_role';
end $$;

do $$
declare
  v_definer text[];
begin
  -- Funcoes da F5-08 (P1 + P2) que sejam SECURITY DEFINER: deve ser vazio.
  select array_agg(p.proname order by p.proname) into v_definer
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosecdef
     and p.proname in (
       'enforce_structure_events_append_only',
       'enforce_organizational_unit_parent_periods_no_cycle',
       'enforce_organizational_unit_close_requires_no_open_structure',
       'enforce_organizational_position_close_requires_no_open_occupations',
       'estrutura_unidade_criar','estrutura_unidade_renomear',
       'estrutura_unidade_encerrar','estrutura_unidade_parent_definir',
       'estrutura_unidade_parent_encerrar','estrutura_posicao_criar',
       'estrutura_posicao_encerrar','estrutura_colegiado_definir',
       'estrutura_colegiado_encerrar','catalogo_cargo_criar',
       'catalogo_cargo_renomear','catalogo_cargo_status_alterar',
       'catalogo_senioridade_criar','catalogo_senioridade_renomear',
       'catalogo_senioridade_status_alterar');

  if v_definer is not null then
    raise exception '[FAIL] K: SECURITY DEFINER novo na F5-08: %', v_definer;
  end if;

  -- Nenhuma capability nova no plano administrativo da F5-08 (D19): nao pode
  -- existir capability de estrutura/catalogo alem das duas previstas.
  if exists (
    select 1 from public.capabilities
     where code like 'org.structure.%' and code <> 'org.structure.manage'
  ) or exists (
    select 1 from public.capabilities
     where code like 'org.catalog.%' and code <> 'org.catalog.manage'
  ) then
    raise exception '[FAIL] K: capability nova de estrutura/catalogo criada pela F5-08';
  end if;
  if not exists (
    select 1 from public.capabilities
     where code = 'org.structure.manage' and status = 'active' and deprecated = false
  ) or not exists (
    select 1 from public.capabilities
     where code = 'org.catalog.manage' and status = 'active' and deprecated = false
  ) then
    raise exception '[FAIL] K: capabilities do plano administrativo ausentes/inativas';
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in (
         'organizational_units','organizational_unit_parent_periods',
         'organizational_positions','position_reporting_lines','job_roles',
         'seniority_levels','collegiate_configurations',
         'collegiate_configuration_members','structure_events')
       and cmd <> 'SELECT'
  ) then
    raise exception '[FAIL] K: policy de escrita criada nas tabelas da F5-08';
  end if;

  raise notice '[PASS] K: zero SECURITY DEFINER novo, nenhuma capability nova, nenhuma policy de escrita';
end $$;

-- ----------------------------------------------------------------------------
-- 8.2 A — Autorizacao (ator, capability e revogacao na operacao seguinte)
-- ----------------------------------------------------------------------------
do $$
declare
  v_msg   text;
  v_res   uuid;
begin
  -- A1: ator sem perfil/membership.
  v_msg := null;
  begin
    v_res := public.estrutura_unidade_criar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000ff',
      'f8920000-0000-0000-0000-0000000000a1',
      'F5-08 P2 A1', '2026-06-01T00:00:00Z', 'teste A1');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_FORBIDDEN%' then
    raise exception '[FAIL] A1: ator sem membership deveria ser FORBIDDEN (msg=%)', v_msg;
  end if;

  -- A2: ator com membership ativa mas SEM capability.
  v_msg := null;
  begin
    v_res := public.estrutura_unidade_criar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a2',
      'f8920000-0000-0000-0000-0000000000a2',
      'F5-08 P2 A2', '2026-06-01T00:00:00Z', 'teste A2');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_FORBIDDEN%' then
    raise exception '[FAIL] A2: ator sem capability deveria ser FORBIDDEN (msg=%)', v_msg;
  end if;

  -- A3: ator com a capability correta.
  v_res := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000a3',
    'F5-08 P2 A3 Unidade', '2026-06-01T00:00:00Z', 'teste A3');
  if v_res is null then
    raise exception '[FAIL] A3: ator com capability deveria criar a unidade';
  end if;

  raise notice '[PASS] A: ator sem membership e ator sem capability negados; ator com capability permitido';
end $$;

do $$
declare
  v_msg text;
  v_res uuid;
begin
  -- A4: revogacao vale na OPERACAO SEGUINTE (scope revogado).
  update public.access_role_assignment_scopes
     set status = 'revoked'
   where id = 'f8a20000-0000-0000-0000-000000000001'
     and organization_id = 'f8a00000-0000-0000-0000-0000000000a1';

  v_msg := null;
  begin
    v_res := public.estrutura_unidade_criar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000a4',
      'F5-08 P2 A4 Revogado', '2026-06-01T00:00:00Z', 'teste A4');
  exception when others then v_msg := sqlerrm;
  end;

  update public.access_role_assignment_scopes
     set status = 'active'
   where id = 'f8a20000-0000-0000-0000-000000000001'
     and organization_id = 'f8a00000-0000-0000-0000-0000000000a1';

  if v_msg is null or v_msg not like 'F5_08_FORBIDDEN%' then
    raise exception '[FAIL] A4: capability revogada deveria valer na operacao seguinte (msg=%)', v_msg;
  end if;
  if exists (
    select 1 from public.structure_events
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
       and operation_id = 'f8920000-0000-0000-0000-0000000000a4'
  ) then
    raise exception '[FAIL] A4: operacao negada gravou evento';
  end if;

  raise notice '[PASS] A4: revogacao de capability vale na operacao seguinte (fail-closed, sem evento)';
end $$;

-- ----------------------------------------------------------------------------
-- 8.3 B — Tenant (org adulterada e alvo de outro tenant)
-- ----------------------------------------------------------------------------
do $$
declare
  v_msg text;
  v_res uuid;
begin
  -- B1: organizacao adulterada (ator sem membership no tenant informado).
  v_msg := null;
  begin
    v_res := public.estrutura_unidade_criar(
      'f8a00000-0000-0000-0000-0000000000b1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000b1',
      'F5-08 P2 B1', '2026-06-01T00:00:00Z', 'teste B1');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_FORBIDDEN%' then
    raise exception '[FAIL] B1: organization_id adulterado deveria ser FORBIDDEN (msg=%)', v_msg;
  end if;

  -- B2: entidade de OUTRO tenant => NOT_FOUND (nunca vaza existencia).
  v_msg := null;
  begin
    v_res := public.estrutura_unidade_renomear(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000b2',
      'f8210000-0000-0000-0000-000000000001',
      'F5-08 P2 B2', 0, 'teste B2');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_NOT_FOUND%' then
    raise exception '[FAIL] B2: alvo de outro tenant deveria ser NOT_FOUND (msg=%)', v_msg;
  end if;

  -- B3: nada foi escrito (nem evento, nem alteracao no tenant alheio).
  if exists (
    select 1 from public.structure_events
     where operation_id in ('f8920000-0000-0000-0000-0000000000b1',
                            'f8920000-0000-0000-0000-0000000000b2')
  ) then
    raise exception '[FAIL] B3: operacao cross-tenant gravou evento';
  end if;
  if (select name from public.organizational_units
       where id = 'f8210000-0000-0000-0000-000000000001') <> 'F5-08 Beta Raiz' then
    raise exception '[FAIL] B3: unidade de outro tenant foi alterada';
  end if;

  raise notice '[PASS] B: org adulterada => FORBIDDEN; alvo de outro tenant => NOT_FOUND sem escrita';
end $$;

-- ----------------------------------------------------------------------------
-- 8.4 C/D — Idempotencia e versionamento
-- ----------------------------------------------------------------------------
do $$
declare
  v_id1 uuid;
  v_id2 uuid;
  v_msg text;
  v_n   int;
begin
  v_id1 := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000c1',
    'F5-08 P2 C1 Idempotente', '2026-06-15T00:00:00Z', 'teste C1');

  -- Mesmo operation_id + MESMO payload => mesmo resultado, sem novo evento.
  v_id2 := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000c1',
    'F5-08 P2 C1 Idempotente', '2026-06-15T00:00:00Z', 'teste C1');

  if v_id1 is distinct from v_id2 then
    raise exception '[FAIL] C1: replay deveria devolver o mesmo resultado (% x %)', v_id1, v_id2;
  end if;
  select count(*) into v_n from public.structure_events
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
     and operation_id = 'f8920000-0000-0000-0000-0000000000c1';
  if v_n <> 1 then
    raise exception '[FAIL] C1: replay duplicou evento (%)', v_n;
  end if;
  if (select count(*) from public.organizational_units
       where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
         and name = 'F5-08 P2 C1 Idempotente') <> 1 then
    raise exception '[FAIL] C1: replay duplicou a entidade';
  end if;

  -- Mesmo operation_id + payload DIFERENTE => CONFLICT.
  v_msg := null;
  begin
    perform public.estrutura_unidade_criar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000c1',
      'F5-08 P2 C1 Outra Intencao', '2026-06-15T00:00:00Z', 'teste C1');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%' then
    raise exception '[FAIL] C2: operation_id reaproveitado com outro payload deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  raise notice '[PASS] C: mesmo operation_id+payload => mesmo resultado (1 evento); payload diferente => CONFLICT';
end $$;

do $$
declare
  v_msg    text;
  v_versao integer;
begin
  -- D1: versionamento correto (criada em C1 com version 0).
  v_versao := public.estrutura_unidade_renomear(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000d1',
    (select id from public.organizational_units
      where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
        and name = 'F5-08 P2 C1 Idempotente'),
    'F5-08 P2 D1 Renomeada', 0, 'teste D1');
  if v_versao <> 1 then
    raise exception '[FAIL] D1: versao esperada 1, obtida %', v_versao;
  end if;

  -- D2: versao stale => CONFLICT.
  v_msg := null;
  begin
    perform public.estrutura_unidade_renomear(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000d2',
      (select id from public.organizational_units
        where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
          and name = 'F5-08 P2 D1 Renomeada'),
      'F5-08 P2 D2 Invalida', 0, 'teste D2');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%' then
    raise exception '[FAIL] D2: expected_version stale deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  raise notice '[PASS] D: expected_version correto avanca a versao; versao stale => CONFLICT';
end $$;

-- ----------------------------------------------------------------------------
-- 8.5 E — Unidades: criar, renomear, encerrar, I2 nos TRES casos e `[)`
-- ----------------------------------------------------------------------------
do $$
declare
  v_id  uuid;
  v_msg text;
  v_ver integer;
begin
  -- E1: criar unidade dedicada (sem dependencia).
  v_id := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000e1',
    'F5-08 P2 E1 Unidade', '2026-06-01T00:00:00Z', 'teste E1');
  if v_id is null then
    raise exception '[FAIL] E1: unidade nao criada';
  end if;

  -- E2: renomear (rotulo) com a versao correta.
  v_ver := public.estrutura_unidade_renomear(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000e2',
    v_id, 'F5-08 P2 E2 Unidade', 0, 'teste E2');
  if v_ver <> 1 then
    raise exception '[FAIL] E2: versao esperada 1, obtida %', v_ver;
  end if;

  -- E3: nome duplicado => CONFLICT.
  v_msg := null;
  begin
    perform public.estrutura_unidade_criar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000e3',
      'F5-08 P2 E2 Unidade', '2026-06-02T00:00:00Z', 'teste E3');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%' then
    raise exception '[FAIL] E3: nome duplicado deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- E4 (I2 caso i): unidade com POSICAO vigente.
  v_msg := null;
  begin
    perform public.estrutura_unidade_encerrar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000e4',
      'f8110000-0000-0000-0000-000000000017', '2026-06-01T00:00:00Z', 0, 'teste E4');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%posicao vigente%' then
    raise exception '[FAIL] E4/I2(i): unidade com posicao vigente deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- E5 (I2 caso ii): unidade como FILHA em relacao vigente.
  v_msg := null;
  begin
    perform public.estrutura_unidade_encerrar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000e5',
      'f8110000-0000-0000-0000-000000000018', '2026-06-01T00:00:00Z', 0, 'teste E5');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%FILHA%' then
    raise exception '[FAIL] E5/I2(ii): unidade como FILHA deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- E6 (I2 caso iii): unidade como PAI de relacao vigente.
  v_msg := null;
  begin
    perform public.estrutura_unidade_encerrar(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000e6',
      'f8110000-0000-0000-0000-000000000019', '2026-06-01T00:00:00Z', 0, 'teste E6');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%PAI%' then
    raise exception '[FAIL] E6/I2(iii): unidade como PAI deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- E7: `[)` — encerrar a relacao EXATAMENTE em T e depois a unidade em T.
  perform public.estrutura_unidade_parent_encerrar(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000ea',
    'f8110000-0000-0000-0000-000000000018', '2026-06-01T00:00:00Z', 'teste E7');

  v_ver := public.estrutura_unidade_encerrar(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000eb',
    'f8110000-0000-0000-0000-000000000018', '2026-06-01T00:00:00Z', 0, 'teste E7');
  if v_ver <> 1 then
    raise exception '[FAIL] E7: encerramento com `[)` deveria avancar a versao (obtido %)', v_ver;
  end if;
  if (select valid_to from public.organizational_units
       where id = 'f8110000-0000-0000-0000-000000000018')
     is distinct from '2026-06-01T00:00:00Z'::timestamptz then
    raise exception '[FAIL] E7: valid_to nao gravado na unidade';
  end if;

  -- E8: encerrar unidade sem dependencia (criada em E1).
  v_ver := public.estrutura_unidade_encerrar(
    'f8a00000-0000-0000-0000-0000000000a1',
    'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000e8',
    v_id, '2026-07-01T00:00:00Z', 1, 'teste E8');
  if v_ver <> 2 then
    raise exception '[FAIL] E8: versao esperada 2, obtida %', v_ver;
  end if;

  -- E9 (D4): unidade encerrada nao pode ser renomeada.
  v_msg := null;
  begin
    perform public.estrutura_unidade_renomear(
      'f8a00000-0000-0000-0000-0000000000a1',
      'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000e9',
      v_id, 'F5-08 P2 E9 Unidade', 2, 'teste E9');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%encerrada%' then
    raise exception '[FAIL] E9/D4: unidade encerrada deveria recusar rename (msg=%)', v_msg;
  end if;

  raise notice '[PASS] E: criar/renomear/encerrar unidade; I2 nos TRES casos; `[)` permitido; encerrada nao renomeia';
end $$;

-- ----------------------------------------------------------------------------
-- 8.6 F — Parent de unidade: definir, trocar, raiz, ciclo real e historico
-- ----------------------------------------------------------------------------
do $$
declare
  v_a   uuid;
  v_b   uuid;
  v_c   uuid;
  v_x   uuid;
  v_y   uuid;
  v_per uuid;
  v_msg text;
  v_n   int;
begin
  v_a := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000f0',
    'F5-08 P2 Parent A', '2026-06-01T00:00:00Z', 'fixture F');
  v_b := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000fb',
    'F5-08 P2 Parent B', '2026-06-01T00:00:00Z', 'fixture F');
  v_c := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000fc',
    'F5-08 P2 Parent C', '2026-06-01T00:00:00Z', 'fixture F');
  v_x := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000fd',
    'F5-08 P2 Ciclo X', '2026-06-01T00:00:00Z', 'fixture F');
  v_y := public.estrutura_unidade_criar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000fe',
    'F5-08 P2 Ciclo Y', '2026-06-01T00:00:00Z', 'fixture F');

  -- F1: definir A -> B.
  v_per := public.estrutura_unidade_parent_definir(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000f1', v_a, v_b,
    '2026-06-01T00:00:00Z', 'teste F1');
  if (select parent_unit_id from public.organizational_unit_parent_periods
       where id = v_per) is distinct from v_b then
    raise exception '[FAIL] F1: periodo criado com parent incorreto';
  end if;

  -- F2: TROCAR A -> C (fecha o periodo anterior em 2026-07-01, abre novo).
  v_per := public.estrutura_unidade_parent_definir(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000f2', v_a, v_c,
    '2026-07-01T00:00:00Z', 'teste F2');
  select count(*) into v_n
    from public.organizational_unit_parent_periods
   where unit_id = v_a
     and organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
  if v_n <> 2 then
    raise exception '[FAIL] F2: historico deveria ter 2 periodos, tem %', v_n;
  end if;
  if (select valid_to from public.organizational_unit_parent_periods
       where unit_id = v_a and parent_unit_id = v_b
         and organization_id = 'f8a00000-0000-0000-0000-0000000000a1')
     is distinct from '2026-07-01T00:00:00Z'::timestamptz then
    raise exception '[FAIL] F2: periodo anterior nao foi fechado na data da troca';
  end if;
  if (select parent_unit_id from public.organizational_unit_parent_periods
       where id = v_per) is distinct from v_c then
    raise exception '[FAIL] F2: novo periodo com parent incorreto';
  end if;

  -- F3: RAIZ (parent null).
  v_per := public.estrutura_unidade_parent_definir(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000f3', v_a, null,
    '2026-08-01T00:00:00Z', 'teste F3');
  if (select parent_unit_id from public.organizational_unit_parent_periods
       where id = v_per) is not null then
    raise exception '[FAIL] F3: periodo de RAIZ deveria ter parent_unit_id nulo';
  end if;

  -- F4: encerrar a relacao vigente.
  perform public.estrutura_unidade_parent_encerrar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000f4', v_a,
    '2026-09-01T00:00:00Z', 'teste F4');
  if (select valid_to from public.organizational_unit_parent_periods where id = v_per)
     is distinct from '2026-09-01T00:00:00Z'::timestamptz then
    raise exception '[FAIL] F4: periodo vigente nao foi encerrado';
  end if;

  -- F5: ciclo REAL negado (X -> Y e depois Y -> X).
  perform public.estrutura_unidade_parent_definir(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000f7', v_x, v_y,
    '2026-06-01T00:00:00Z', 'teste F5');
  v_msg := null;
  begin
    perform public.estrutura_unidade_parent_definir(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000f8', v_y, v_x,
      '2026-06-02T00:00:00Z', 'teste F5');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%ciclo%' then
    raise exception '[FAIL] F5: ciclo real deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- F6: unidade nao vigente na data informada => CONFLICT.
  v_msg := null;
  begin
    perform public.estrutura_unidade_parent_definir(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000f6', v_a, v_b,
      '2026-05-01T00:00:00Z', 'teste F6');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%nao vigente%' then
    raise exception '[FAIL] F6: unidade fora de vigencia deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  raise notice '[PASS] F: parent definido/trocado/raiz/encerrado, ciclo real negado e historico preservado';
end $$;

-- ----------------------------------------------------------------------------
-- 8.7 G — Posicoes: criar, catalogos ativos, encerrar, ocupacao e reporting line
-- ----------------------------------------------------------------------------
do $$
declare
  v_pos uuid;
  v_msg text;
  v_ver integer;
begin
  -- G1: criar com catalogos ATIVOS.
  v_pos := public.estrutura_posicao_criar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-000000000091',
    'f8110000-0000-0000-0000-00000000001b', 'f8e00000-0000-0000-0000-0000000000a1',
    'f8f00000-0000-0000-0000-0000000000a1', '2026-06-01T00:00:00Z', 'teste G1');
  if v_pos is null then
    raise exception '[FAIL] G1: posicao nao criada';
  end if;

  -- G2: cargo DESATIVADO => CONFLICT (I4).
  v_msg := null;
  begin
    perform public.estrutura_posicao_criar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-000000000092',
      'f8110000-0000-0000-0000-00000000001b', 'f8e00000-0000-0000-0000-0000000000a2',
      'f8f00000-0000-0000-0000-0000000000a1', '2026-06-01T00:00:00Z', 'teste G2');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%cargo inativo%' then
    raise exception '[FAIL] G2/I4: cargo inativo deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- G3: senioridade DESATIVADA => CONFLICT (I4).
  v_msg := null;
  begin
    perform public.estrutura_posicao_criar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-000000000093',
      'f8110000-0000-0000-0000-00000000001b', 'f8e00000-0000-0000-0000-0000000000a1',
      'f8f00000-0000-0000-0000-0000000000a2', '2026-06-01T00:00:00Z', 'teste G3');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%senioridade inativa%' then
    raise exception '[FAIL] G3/I4: senioridade inativa deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- G4: encerrar posicao com OCUPACAO vigente => CONFLICT.
  v_msg := null;
  begin
    perform public.estrutura_posicao_encerrar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-000000000094',
      'f8310000-0000-0000-0000-000000000005', '2026-06-01T00:00:00Z', 0, 'teste G4');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%ocupacao vigente%' then
    raise exception '[FAIL] G4: ocupacao vigente deveria bloquear (msg=%)', v_msg;
  end if;

  -- G5: encerrar posicao com REPORTING LINE vigente => CONFLICT (guarda F3-04).
  v_msg := null;
  begin
    perform public.estrutura_posicao_encerrar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-000000000095',
      'f8310000-0000-0000-0000-000000000006', '2026-06-01T00:00:00Z', 0, 'teste G5');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%reporting line vigente%' then
    raise exception '[FAIL] G5: reporting line vigente deveria bloquear (msg=%)', v_msg;
  end if;

  -- G6: encerrar posicao SEM dependencia (08).
  v_ver := public.estrutura_posicao_encerrar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-000000000096',
    'f8310000-0000-0000-0000-000000000008', '2026-06-01T00:00:00Z', 0, 'teste G6');
  if v_ver <> 1 then
    raise exception '[FAIL] G6: versao esperada 1, obtida %', v_ver;
  end if;

  -- G7: encerrar de novo => CONFLICT.
  v_msg := null;
  begin
    perform public.estrutura_posicao_encerrar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-000000000097',
      'f8310000-0000-0000-0000-000000000008', '2026-06-02T00:00:00Z', 1, 'teste G7');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%ja encerrada%' then
    raise exception '[FAIL] G7: posicao ja encerrada deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- G8: cargo de OUTRO tenant => NOT_FOUND.
  v_msg := null;
  begin
    perform public.estrutura_posicao_criar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-000000000098',
      'f8110000-0000-0000-0000-00000000001b', 'f8e00000-0000-0000-0000-0000000000b1',
      null, '2026-06-01T00:00:00Z', 'teste G8');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_NOT_FOUND%' then
    raise exception '[FAIL] G8: catalogo de outro tenant deveria ser NOT_FOUND (msg=%)', v_msg;
  end if;

  raise notice '[PASS] G: posicao criada com catalogo ativo; inativos recusados; encerramento bloqueado por ocupacao/reporting line';
end $$;

-- ----------------------------------------------------------------------------
-- 8.8 H — Catalogos: criar, renomear, status, `code` imutavel e sem `code`
-- ----------------------------------------------------------------------------
do $$
declare
  v_cargo uuid;
  v_sen   uuid;
  v_msg   text;
  v_ver   integer;
  v_row   record;
begin
  -- H1: criar cargo com code.
  v_cargo := public.catalogo_cargo_criar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000c2',
    'F5-08 P2 Cargo', 'P2-CARGO-1', 'teste H1');
  select name, code, status, version into v_row from public.job_roles where id = v_cargo;
  if v_row.code <> 'P2-CARGO-1' or v_row.status <> 'active' or v_row.version <> 0 then
    raise exception '[FAIL] H1: cargo criado com estado inesperado (%)', v_row;
  end if;

  -- H2: renomear preservando `code` (D4: imutavel).
  v_ver := public.catalogo_cargo_renomear(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000c3',
    v_cargo, 'F5-08 P2 Cargo Renomeado', 0, 'teste H2');
  select name, code, version into v_row from public.job_roles where id = v_cargo;
  if v_ver <> 1 or v_row.code <> 'P2-CARGO-1' or v_row.name <> 'F5-08 P2 Cargo Renomeado' then
    raise exception '[FAIL] H2: rename alterou `code` ou nao avancou versao (%)', v_row;
  end if;

  -- H3: status disabled -> active (nunca DELETE).
  v_ver := public.catalogo_cargo_status_alterar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000c4',
    v_cargo, 'disabled', 1, 'teste H3');
  if v_ver <> 2 or (select status from public.job_roles where id = v_cargo) <> 'disabled' then
    raise exception '[FAIL] H3: inativacao de cargo nao aplicada';
  end if;
  v_ver := public.catalogo_cargo_status_alterar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000c5',
    v_cargo, 'active', 2, 'teste H3');
  if v_ver <> 3 or (select status from public.job_roles where id = v_cargo) <> 'active' then
    raise exception '[FAIL] H3: reativacao de cargo nao aplicada';
  end if;

  -- H4: nome/codigo duplicados => CONFLICT.
  v_msg := null;
  begin
    perform public.catalogo_cargo_criar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000c6',
      'F5-08 P2 Cargo Renomeado', null, 'teste H4');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%nome%' then
    raise exception '[FAIL] H4: nome duplicado deveria ser CONFLICT (msg=%)', v_msg;
  end if;
  v_msg := null;
  begin
    perform public.catalogo_cargo_criar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000c7',
      'F5-08 P2 Cargo Novo', 'P2-CARGO-1', 'teste H4');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%codigo%' then
    raise exception '[FAIL] H4: code duplicado deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- H5: renomear cargo DESATIVADO => CONFLICT.
  v_msg := null;
  begin
    perform public.catalogo_cargo_renomear(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000c8',
      'f8e00000-0000-0000-0000-0000000000a2', 'F5-08 P2 Cargo Off', 0, 'teste H5');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%inativo%' then
    raise exception '[FAIL] H5: cargo inativo nao deveria ser renomeado (msg=%)', v_msg;
  end if;

  -- H6: senioridade — criar/renomear/status, sem `code`.
  v_sen := public.catalogo_senioridade_criar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000c9',
    'F5-08 P2 Senioridade', 'teste H6');
  v_ver := public.catalogo_senioridade_renomear(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000ca',
    v_sen, 'F5-08 P2 Senioridade Renomeada', 0, 'teste H6');
  if v_ver <> 1 then
    raise exception '[FAIL] H6: rename de senioridade nao avancou versao';
  end if;
  v_ver := public.catalogo_senioridade_status_alterar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000cb',
    v_sen, 'disabled', 1, 'teste H6');
  if v_ver <> 2 or (select status from public.seniority_levels where id = v_sen) <> 'disabled' then
    raise exception '[FAIL] H6: inativacao de senioridade nao aplicada';
  end if;
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'seniority_levels'
       and column_name = 'code'
  ) then
    raise exception '[FAIL] H6/D17: seniority_levels nao pode ter coluna `code`';
  end if;

  -- H7: senioridade desativada nao renomeia.
  v_msg := null;
  begin
    perform public.catalogo_senioridade_renomear(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000cc',
      'f8f00000-0000-0000-0000-0000000000a2', 'F5-08 P2 Senior Off', 0, 'teste H7');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%inativa%' then
    raise exception '[FAIL] H7: senioridade inativa nao deveria ser renomeada (msg=%)', v_msg;
  end if;

  -- H8: cargo de OUTRO tenant => NOT_FOUND.
  v_msg := null;
  begin
    perform public.catalogo_cargo_renomear(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000cd',
      'f8e00000-0000-0000-0000-0000000000b1', 'F5-08 P2 Beta', 0, 'teste H8');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_NOT_FOUND%' then
    raise exception '[FAIL] H8: catalogo de outro tenant deveria ser NOT_FOUND (msg=%)', v_msg;
  end if;

  raise notice '[PASS] H: catalogo de cargo e senioridade (criar/renomear/status), `code` imutavel e senioridade sem `code`';
end $$;

-- ----------------------------------------------------------------------------
-- 8.9 I — Colegiado: definir, alterar versao, encerrar e validacoes
-- ----------------------------------------------------------------------------
do $$
declare
  v_config1 uuid;
  v_config2 uuid;
  v_config3 uuid;
  v_msg     text;
  v_n       int;
begin
  -- I1: definir colegiado com 2 membros.
  v_config1 := public.estrutura_colegiado_definir(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000b3',
    'f8500000-0000-0000-0000-0000000000a1',
    array['f8500000-0000-0000-0000-0000000000a2',
          'f8500000-0000-0000-0000-0000000000a3']::uuid[],
    '2026-06-01T00:00:00Z', 'teste I1');
  select count(*) into v_n from public.collegiate_configuration_members
   where configuration_id = v_config1;
  if v_n <> 2 then
    raise exception '[FAIL] I1: colegiado deveria ter 2 membros, tem %', v_n;
  end if;

  -- I2: alterar a versao (fecha a anterior em 2026-07-01 e abre nova com 1 membro).
  v_config2 := public.estrutura_colegiado_definir(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000b4',
    'f8500000-0000-0000-0000-0000000000a1',
    array['f8500000-0000-0000-0000-0000000000a3']::uuid[],
    '2026-07-01T00:00:00Z', 'teste I2');
  if (select valid_to from public.collegiate_configurations where id = v_config1)
     is distinct from '2026-07-01T00:00:00Z'::timestamptz then
    raise exception '[FAIL] I2: versao anterior nao foi fechada na data da nova';
  end if;
  select count(*) into v_n from public.collegiate_configuration_members
   where configuration_id = v_config2;
  if v_n <> 1 then
    raise exception '[FAIL] I2: nova versao deveria ter 1 membro, tem %', v_n;
  end if;
  select count(*) into v_n from public.collegiate_configurations
   where collaborator_id = 'f8500000-0000-0000-0000-0000000000a1'
     and organization_id = 'f8a00000-0000-0000-0000-0000000000a1';
  if v_n <> 2 then
    raise exception '[FAIL] I2: historico deveria ter 2 configuracoes, tem %', v_n;
  end if;

  -- I3: self-member => CONFLICT.
  v_msg := null;
  begin
    perform public.estrutura_colegiado_definir(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000b5',
      'f8500000-0000-0000-0000-0000000000a1',
      array['f8500000-0000-0000-0000-0000000000a1',
            'f8500000-0000-0000-0000-0000000000a2']::uuid[],
      '2026-08-01T00:00:00Z', 'teste I3');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_CONFLICT%avaliado%' then
    raise exception '[FAIL] I3: self-member deveria ser CONFLICT (msg=%)', v_msg;
  end if;

  -- I4: membro duplicado => INVALID_INPUT.
  v_msg := null;
  begin
    perform public.estrutura_colegiado_definir(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000b6',
      'f8500000-0000-0000-0000-0000000000a1',
      array['f8500000-0000-0000-0000-0000000000a2',
            'f8500000-0000-0000-0000-0000000000a2']::uuid[],
      '2026-08-01T00:00:00Z', 'teste I4');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_INVALID_INPUT%duplicidade%' then
    raise exception '[FAIL] I4: duplicidade deveria ser INVALID_INPUT (msg=%)', v_msg;
  end if;

  -- I5: membro de OUTRO tenant => NOT_FOUND.
  v_msg := null;
  begin
    perform public.estrutura_colegiado_definir(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000b7',
      'f8500000-0000-0000-0000-0000000000a1',
      array['f8500000-0000-0000-0000-0000000000b1']::uuid[],
      '2026-08-01T00:00:00Z', 'teste I5');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_NOT_FOUND%membro%' then
    raise exception '[FAIL] I5: membro de outro tenant deveria ser NOT_FOUND (msg=%)', v_msg;
  end if;

  -- I6: encerrar a configuracao vigente.
  perform public.estrutura_colegiado_encerrar(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000b8',
    'f8500000-0000-0000-0000-0000000000a1', '2026-08-01T00:00:00Z', 'teste I6');
  if (select valid_to from public.collegiate_configurations where id = v_config2)
     is distinct from '2026-08-01T00:00:00Z'::timestamptz then
    raise exception '[FAIL] I6: configuracao vigente nao foi encerrada';
  end if;

  -- I7: definir com lista VAZIA = "sem colegiado" explicito (0 membros).
  v_config3 := public.estrutura_colegiado_definir(
    'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
    'f8920000-0000-0000-0000-0000000000b9',
    'f8500000-0000-0000-0000-0000000000a1', array[]::uuid[],
    '2026-09-01T00:00:00Z', 'teste I7');
  select count(*) into v_n from public.collegiate_configuration_members
   where configuration_id = v_config3;
  if v_n <> 0 then
    raise exception '[FAIL] I7: configuracao com lista vazia deveria ter 0 membros (tem %)', v_n;
  end if;

  -- I8: encerrar sem configuracao vigente na data => NOT_FOUND.
  v_msg := null;
  begin
    perform public.estrutura_colegiado_encerrar(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000ba',
      'f8500000-0000-0000-0000-0000000000a1', '2026-08-15T00:00:00Z', 'teste I8');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_NOT_FOUND%' then
    raise exception '[FAIL] I8: data sem configuracao vigente deveria ser NOT_FOUND (msg=%)', v_msg;
  end if;

  -- I9: elemento nulo na lista => INVALID_INPUT.
  v_msg := null;
  begin
    perform public.estrutura_colegiado_definir(
      'f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
      'f8920000-0000-0000-0000-0000000000bb',
      'f8500000-0000-0000-0000-0000000000a1',
      array['f8500000-0000-0000-0000-0000000000a2', null]::uuid[],
      '2026-10-01T00:00:00Z', 'teste I9');
  exception when others then v_msg := sqlerrm;
  end;
  if v_msg is null or v_msg not like 'F5_08_INVALID_INPUT%nulo%' then
    raise exception '[FAIL] I9: elemento nulo deveria ser INVALID_INPUT (msg=%)', v_msg;
  end if;

  raise notice '[PASS] I: colegiado definido/alterado/encerrado; self, duplicidade, nulo e cross-tenant recusados';
end $$;

-- ----------------------------------------------------------------------------
-- 8.10 J — Auditoria: 1 mutacao = 1 evento, com autoria e delta corretos
-- ----------------------------------------------------------------------------
do $$
declare
  v_n   int;
  v_evt record;
  v_bad text[];
begin
  -- Todo evento da organizacao tem ator/membership/hash/motivo coerentes.
  select array_agg(operation_id::text) into v_bad
    from public.structure_events
   where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
     and (actor_user_profile_id is distinct from 'f8c00000-0000-0000-0000-0000000000a1'
          or actor_membership_id is distinct from 'f8d00000-0000-0000-0000-0000000000a1'
          or payload_hash is null
          or reason = '');
  if v_bad is not null then
    raise exception '[FAIL] J: eventos sem autoria/hash/motivo: %', v_bad;
  end if;

  -- Nenhum evento carrega dado pessoal desnecessario.
  if exists (
    select 1 from public.structure_events
     where organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
       and (coalesce(after_value::text, '') like '%full_name%'
            or coalesce(before_value::text, '') like '%full_name%'
            or coalesce(after_value::text, '') like '%email%'
            or coalesce(before_value::text, '') like '%email%')
  ) then
    raise exception '[FAIL] J: trilha estrutural com dado pessoal desnecessario';
  end if;

  -- Pares (operation_id -> entity_type/event_type/effective_date) esperados.
  for v_evt in
    select * from (values
      ('f8920000-0000-0000-0000-0000000000e1', 'organizational_unit', 'CRIADO', '2026-06-01T00:00:00Z'::timestamptz),
      ('f8920000-0000-0000-0000-0000000000e2', 'organizational_unit', 'RENOMEADO', null),
      ('f8920000-0000-0000-0000-0000000000e8', 'organizational_unit', 'ENCERRADO', '2026-07-01T00:00:00Z'::timestamptz),
      ('f8920000-0000-0000-0000-0000000000f1', 'organizational_unit_parent_period', 'PARENT_DEFINIDO', '2026-06-01T00:00:00Z'::timestamptz),
      ('f8920000-0000-0000-0000-0000000000f4', 'organizational_unit_parent_period', 'PARENT_ENCERRADO', '2026-09-01T00:00:00Z'::timestamptz),
      ('f8920000-0000-0000-0000-000000000091', 'organizational_position', 'CRIADO', '2026-06-01T00:00:00Z'::timestamptz),
      ('f8920000-0000-0000-0000-000000000096', 'organizational_position', 'ENCERRADO', '2026-06-01T00:00:00Z'::timestamptz),
      ('f8920000-0000-0000-0000-0000000000c2', 'job_role', 'CRIADO', null),
      ('f8920000-0000-0000-0000-0000000000c4', 'job_role', 'ENCERRADO', null),
      ('f8920000-0000-0000-0000-0000000000c9', 'seniority_level', 'CRIADO', null),
      ('f8920000-0000-0000-0000-0000000000b3', 'collegiate_configuration', 'MEMBROS_ALTERADOS', '2026-06-01T00:00:00Z'::timestamptz),
      ('f8920000-0000-0000-0000-0000000000b8', 'collegiate_configuration', 'COLEGIADO_ENCERRADO', '2026-08-01T00:00:00Z'::timestamptz)
    ) as t(operation_id, entity_type, event_type, effective_date)
  loop
    select count(*) into v_n
      from public.structure_events e
     where e.organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
       and e.operation_id = v_evt.operation_id::uuid;
    if v_n <> 1 then
      raise exception '[FAIL] J: operation_id % deveria ter exatamente 1 evento (tem %)',
        v_evt.operation_id, v_n;
    end if;
    if not exists (
      select 1 from public.structure_events e
       where e.organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
         and e.operation_id = v_evt.operation_id::uuid
         and e.entity_type = v_evt.entity_type
         and e.event_type = v_evt.event_type
         and (v_evt.effective_date is null or e.effective_date = v_evt.effective_date)
    ) then
      raise exception '[FAIL] J: evento % com entity_type/event_type/effective_date divergentes',
        v_evt.operation_id;
    end if;
  end loop;

  -- before/after do rename de unidade refletem o delta real.
  if not exists (
    select 1 from public.structure_events e
     where e.organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
       and e.operation_id = 'f8920000-0000-0000-0000-0000000000e2'
       and e.before_value->>'name' = 'F5-08 P2 E1 Unidade'
       and e.after_value->>'name' = 'F5-08 P2 E2 Unidade'
       and (e.after_value->>'version')::int = 1
  ) then
    raise exception '[FAIL] J: before/after do rename de unidade incorretos';
  end if;

  -- O colegiado registra o conjunto de membros normalizado no after_value.
  if not exists (
    select 1 from public.structure_events e
     where e.organization_id = 'f8a00000-0000-0000-0000-0000000000a1'
       and e.operation_id = 'f8920000-0000-0000-0000-0000000000b3'
       and jsonb_array_length(e.after_value->'members') = 2
  ) then
    raise exception '[FAIL] J: evento de colegiado nao registrou os 2 membros';
  end if;

  raise notice '[PASS] J: 1 mutacao = 1 evento, autoria/motivo/hash/effective_date e delta before/after corretos';
end $$;

reset role;

-- ============================================================================
-- 9) Resumo
-- ============================================================================
do $$
begin
  raise notice '[PASS] F5-08 P1+P2: validacao concluida (structure_events, I1, I2, I3, D24, grants/RLS e as 15 RPCs do P2)';
end $$;
