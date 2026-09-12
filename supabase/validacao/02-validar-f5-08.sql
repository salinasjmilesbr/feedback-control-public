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
-- 7) Resumo
-- ============================================================================
do $$
begin
  raise notice '[PASS] F5-08 P1: validacao concluida (structure_events, I1, I2, I3, D24, grants/RLS)';
end $$;
