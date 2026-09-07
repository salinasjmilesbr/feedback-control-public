-- ============================================================================
-- F3-09 (Issue #86): validação automatizada — responsabilidade avaliativa e
-- sucessão de avaliador (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-09.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-09.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-09.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; qualquer falha levanta
-- exceção e aborta com código de saída não-zero. O script NÃO toca projeto
-- remoto, NÃO altera policies e remove ao final os dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- Constantes do cenário
-- ----------------------------------------------------------------------------
-- ORG_A = fba00000-0000-0000-0000-0000000000a1; ORG_B = fba...00b1.
-- C_GER c1, C_GER2 c2, C_SUB c3, A1 c4, A2 c5, A3 c6, A4 c7, CBeta d1.
-- Posições: P_GER a1, P_A1 a2, P_A2 a3, P_A3 a4 (raiz), P_A4 a5, P_A5 a6,
-- P_BETA a9.
-- Autor (user_profile) = fbf00000-0000-0000-0000-000000000001.

-- ============================================================================
-- 1) Estrutura: tabelas, constraints, funções e RLS
-- ============================================================================

do $$
begin
  if exists (
    select 1
    from pg_tables t
    where t.schemaname = 'public'
      and t.tablename not in (
        'collaborator_identifiers',
        'collaborator_status_periods',
        'collaborators',
        'collegiate_configuration_members',
        'collegiate_configurations',
        'collegiate_cycle_snapshot_members',
        'collegiate_cycle_snapshot_positions',
        'collegiate_cycle_snapshots',
        'cycle_evaluation_responsibilities',
        'evaluation_succession_events',
        'job_roles',
        'occupations',
        'organizational_positions',
        'organizational_unit_parent_periods',
        'organizational_units',
        'organizations',
        'position_reporting_lines',
        'seniority_levels',
        'temporary_responsibilities',
        'user_organization_memberships',
        'user_profiles'
      )
  ) then
    raise exception '[FAIL] tabela inesperada no schema public (F3-09 cria apenas 2 tabelas novas)';
  end if;
  raise notice '[PASS] schema public contém as 21 tabelas esperadas (F2 + F3-01..08 + F3-09)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'pk_cycle_evaluation_responsibilities',
    'uq_cycle_evaluation_responsibilities_id_organization',
    'fk_cycle_evaluation_responsibilities_snapshots',
    'fk_cycle_evaluation_responsibilities_positions',
    'fk_cycle_evaluation_responsibilities_collaborators',
    'ck_cycle_evaluation_responsibilities_valid_to',
    'ex_cycle_evaluation_responsibilities_no_overlap',
    'pk_evaluation_succession_events',
    'uq_evaluation_succession_events_snapshot_position_date',
    'fk_evaluation_succession_events_snapshots',
    'fk_evaluation_succession_events_positions',
    'fk_evaluation_succession_events_previous_collaborators',
    'fk_evaluation_succession_events_new_collaborators',
    'fk_evaluation_succession_events_author',
    'ck_evaluation_succession_events_motive'
  );
  if v_n <> 15 then
    raise exception '[FAIL] constraints esperadas da F3-09 ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] 15 constraints esperadas presentes nas tabelas F3-09';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid in (
      'public.cycle_evaluation_responsibilities'::regclass,
      'public.evaluation_succession_events'::regclass
    )
    and c.confdeltype <> 'r';
  if v_n <> 0 then
    raise exception '[FAIL] existe FK sem ON DELETE RESTRICT nas tabelas F3-09';
  end if;
  raise notice '[PASS] todas as FKs das tabelas F3-09 sao ON DELETE RESTRICT';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('cycle_evaluation_responsibilities',
                      'evaluation_succession_events')
    and c.relrowsecurity = true;
  if v_n <> 2 then
    raise exception '[FAIL] RLS nao habilitado nas tabelas F3-09';
  end if;
  if exists (
    select 1 from pg_policies p
    where p.schemaname = 'public'
      and p.tablename in ('cycle_evaluation_responsibilities',
                          'evaluation_succession_events')
  ) then
    raise exception '[FAIL] existe policy nas tabelas F3-09';
  end if;
  raise notice '[PASS] RLS habilitado nas 2 tabelas F3-09, zero policies (deny-by-default)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('organizacao_resolver_responsavel_avaliativo_posicao',
                      'organizacao_resolver_avaliador_avaliado',
                      'materializar_responsabilidades_avaliacao',
                      'registrar_sucessao_avaliador',
                      'resolver_responsavel_avaliacao_vigente');
  if v_n <> 5 then
    raise exception '[FAIL] funcoes F3-09 ausentes (% encontradas)', v_n;
  end if;

  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('organizacao_resolver_responsavel_avaliativo_posicao',
                      'organizacao_resolver_avaliador_avaliado',
                      'materializar_responsabilidades_avaliacao',
                      'registrar_sucessao_avaliador',
                      'resolver_responsavel_avaliacao_vigente')
    and p.prosecdef = true;
  if v_n <> 0 then
    raise exception '[FAIL] funcao F3-09 deveria ser SECURITY INVOKER';
  end if;
  raise notice '[PASS] 5 funcoes F3-09 presentes (SECURITY INVOKER)';
end $$;

-- ============================================================================
-- 2) Resolução avaliativa (substituto > titular) e reversão
-- ============================================================================

do $$
declare
  v_titular uuid;
  v_sub uuid;
  v_resp uuid;
begin
  -- Substituto avaliativo ativo em 2025-03-01.
  select titular_collaborator_id, substitute_collaborator_id, responsible_collaborator_id
    into v_titular, v_sub, v_resp
  from public.organizacao_resolver_responsavel_avaliativo_posicao(
    'fbc00000-0000-0000-0000-0000000000a1', '2025-03-01T00:00:00Z');
  if v_titular is distinct from 'fbb00000-0000-0000-0000-0000000000c1'
     or v_sub is distinct from 'fbb00000-0000-0000-0000-0000000000c3'
     or v_resp is distinct from 'fbb00000-0000-0000-0000-0000000000c3' then
    raise exception '[FAIL] responsavel avaliativo deveria ser substituto > titular em 2025-03-01';
  end if;

  -- Período da substituição encerrado em 2025-06-01 → titular reassume.
  select titular_collaborator_id, substitute_collaborator_id, responsible_collaborator_id
    into v_titular, v_sub, v_resp
  from public.organizacao_resolver_responsavel_avaliativo_posicao(
    'fbc00000-0000-0000-0000-0000000000a1', '2025-06-01T00:00:00Z');
  if v_titular is distinct from 'fbb00000-0000-0000-0000-0000000000c1'
     or v_sub is not null
     or v_resp is distinct from 'fbb00000-0000-0000-0000-0000000000c1' then
    raise exception '[FAIL] responsavel avaliativo deveria voltar ao titular em 2025-06-01';
  end if;
  raise notice '[PASS] responsavel avaliativo = substituto (evaluative) > titular; titular reassume apos o periodo';
end $$;

do $$
declare
  v_n int;
  v_pos uuid[];
  v_mgr uuid[];
begin
  -- A4 ocupa duas posições (P_A4, P_A5) → duas linhas de resolução (D3).
  select count(*),
         array_agg(occupied_position_id order by occupied_position_id),
         array_agg(manager_collaborator_id order by occupied_position_id)
    into v_n, v_pos, v_mgr
  from public.organizacao_resolver_avaliador_avaliado(
    'fbb00000-0000-0000-0000-0000000000c7', '2025-03-01T00:00:00Z');
  if v_n <> 2 then
    raise exception '[FAIL] A4 deveria resolver 2 posicoes ocupadas (encontrado %)', v_n;
  end if;
  if v_pos is distinct from
     array['fbc00000-0000-0000-0000-0000000000a5',
           'fbc00000-0000-0000-0000-0000000000a6']::uuid[] then
    raise exception '[FAIL] A4 deveria resolver P_A4 e P_A5';
  end if;
  -- Substituto avaliativo ativo → manager = C_SUB em ambas.
  if v_mgr is distinct from
     array['fbb00000-0000-0000-0000-0000000000c3',
           'fbb00000-0000-0000-0000-0000000000c3']::uuid[] then
    raise exception '[FAIL] manager de A4 em 2025-03-01 deveria ser o substituto C_SUB';
  end if;
  raise notice '[PASS] multiplas posicoes resolvidas separadamente (2 linhas) com responsavel avaliativo';
end $$;

-- ============================================================================
-- 3) Materialização das responsabilidades originais
-- ============================================================================

do $$
begin
  perform public.materializar_colegiado_ciclo(
    'fba00000-0000-0000-0000-0000000000a1',
    2025, 1, '2025-03-01T00:00:00Z',
    array[
      'fbb00000-0000-0000-0000-0000000000c4',
      'fbb00000-0000-0000-0000-0000000000c5',
      'fbb00000-0000-0000-0000-0000000000c6',
      'fbb00000-0000-0000-0000-0000000000c7'
    ]::uuid[]
  );
  perform public.materializar_responsabilidades_avaliacao(
    'fba00000-0000-0000-0000-0000000000a1', 2025, 1
  );
  raise notice '[PASS] snapshots F3-08 e responsabilidades F3-09 materializadas';
end $$;

do $$
declare
  v_n int;
begin
  -- 4 responsabilidades: A1(P_A1), A2(P_A2), A4(P_A4), A4(P_A5); A3 é raiz → 0.
  select count(*) into v_n
  from public.cycle_evaluation_responsibilities cer
  join public.collegiate_cycle_snapshots s on s.id = cer.snapshot_id
  where s.organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1;
  if v_n <> 4 then
    raise exception '[FAIL] esperadas 4 responsabilidades (encontrado %)', v_n;
  end if;

  select count(*) into v_n
  from public.cycle_evaluation_responsibilities cer
  join public.collegiate_cycle_snapshots s on s.id = cer.snapshot_id
  where s.organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and s.collaborator_id = 'fbb00000-0000-0000-0000-0000000000c6';
  if v_n <> 0 then
    raise exception '[FAIL] A3 (raiz/sem superior) nao deveria gerar responsabilidade';
  end if;

  -- Responsável permanente = titular C_GER (nunca o substituto C_SUB), mesmo
  -- com a substituição ativa na data de referência (D6/5.1).
  select count(*) into v_n
  from public.cycle_evaluation_responsibilities cer
  join public.collegiate_cycle_snapshots s on s.id = cer.snapshot_id
  where s.organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and cer.responsible_collaborator_id <> 'fbb00000-0000-0000-0000-0000000000c1';
  if v_n <> 0 then
    raise exception '[FAIL] responsavel original deveria ser o titular C_GER (nao o substituto)';
  end if;
  raise notice '[PASS] 4 responsabilidades originais; raiz sem responsabilidade; titular congelado (nao substituto)';
end $$;

-- ============================================================================
-- 4) Responsável vigente (overlay de substituto por data)
-- ============================================================================

do $$
declare
  v_n int;
  v_resp uuid[];
  v_flag boolean[];
begin
  select count(*),
         array_agg(responsible_collaborator_id order by position_id),
         array_agg(is_substitute order by position_id)
    into v_n, v_resp, v_flag
  from public.resolver_responsavel_avaliacao_vigente(
    'fba00000-0000-0000-0000-0000000000a1', 2025, 1, '2025-03-01T00:00:00Z');
  if v_n <> 4 then
    raise exception '[FAIL] vigente deveria retornar 4 responsabilidades (encontrado %)', v_n;
  end if;
  if v_resp is distinct from
     array['fbb00000-0000-0000-0000-0000000000c3',
           'fbb00000-0000-0000-0000-0000000000c3',
           'fbb00000-0000-0000-0000-0000000000c3',
           'fbb00000-0000-0000-0000-0000000000c3']::uuid[]
     or v_flag is distinct from array[true, true, true, true] then
    raise exception '[FAIL] vigente em 2025-03-01 deveria ser o substituto C_SUB';
  end if;
  raise notice '[PASS] vigente em 2025-03-01 = substituto avaliativo (overlay por data)';
end $$;

do $$
declare
  v_n int;
  v_resp uuid[];
  v_flag boolean[];
begin
  select count(*),
         array_agg(responsible_collaborator_id order by position_id),
         array_agg(is_substitute order by position_id)
    into v_n, v_resp, v_flag
  from public.resolver_responsavel_avaliacao_vigente(
    'fba00000-0000-0000-0000-0000000000a1', 2025, 1, '2025-06-01T00:00:00Z');
  if v_resp is distinct from
     array['fbb00000-0000-0000-0000-0000000000c1',
           'fbb00000-0000-0000-0000-0000000000c1',
           'fbb00000-0000-0000-0000-0000000000c1',
           'fbb00000-0000-0000-0000-0000000000c1']::uuid[]
     or v_flag is distinct from array[false, false, false, false] then
    raise exception '[FAIL] vigente em 2025-06-01 deveria voltar ao titular C_GER';
  end if;
  raise notice '[PASS] vigente em 2025-06-01 = titular (substituto nao vira gestor permanente)';
end $$;

-- ============================================================================
-- 5) Sucessão de avaliador (mudança definitiva de gestor)
-- ============================================================================

do $$
declare
  v_ids uuid[];
begin
  -- Mudança definitiva: fecha occupation de C_GER em P_GER e abre C_GER2.
  update public.occupations
     set valid_to = '2025-07-01T00:00:00Z'
   where organizational_position_id = 'fbc00000-0000-0000-0000-0000000000a1'
     and collaborator_id = 'fbb00000-0000-0000-0000-0000000000c1'
     and valid_to is null;

  insert into public.occupations (
    organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
  ) values (
    'fba00000-0000-0000-0000-0000000000a1',
    'fbb00000-0000-0000-0000-0000000000c2',
    'fbc00000-0000-0000-0000-0000000000a1',
    'Sucessor do gerente', '2025-07-01T00:00:00Z', null
  );

  select array_agg(cer.id order by cer.id) into v_ids
  from public.cycle_evaluation_responsibilities cer
  join public.collegiate_cycle_snapshots s on s.id = cer.snapshot_id
  where s.organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and cer.valid_to is null;

  perform public.registrar_sucessao_avaliador(
    v_ids, '2025-07-01T00:00:00Z',
    'Mudanca definitiva de gestor',
    'fbf00000-0000-0000-0000-000000000001'
  );
  raise notice '[PASS] sucessao registrada pela RPC (4 responsabilidades abertas)';
end $$;

do $$
declare
  v_n int;
begin
  -- 4 eventos de sucessão com previous=C_GER, new=C_GER2, motivo e autor.
  select count(*) into v_n
  from public.evaluation_succession_events
  where organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and previous_responsible_collaborator_id = 'fbb00000-0000-0000-0000-0000000000c1'
    and new_responsible_collaborator_id = 'fbb00000-0000-0000-0000-0000000000c2'
    and succession_date = '2025-07-01T00:00:00Z'
    and motive = 'Mudanca definitiva de gestor'
    and author_user_profile_id = 'fbf00000-0000-0000-0000-000000000001';
  if v_n <> 4 then
    raise exception '[FAIL] esperados 4 eventos de sucessao (encontrado %)', v_n;
  end if;

  -- Responsável original preservado: 4 linhas fechadas com C_GER.
  select count(*) into v_n
  from public.cycle_evaluation_responsibilities
  where organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and responsible_collaborator_id = 'fbb00000-0000-0000-0000-0000000000c1'
    and valid_to is not null;
  if v_n <> 4 then
    raise exception '[FAIL] responsavel original (C_GER) deveria ser preservado nas 4 linhas fechadas';
  end if;

  -- 4 novas responsabilidades abertas com C_GER2.
  select count(*) into v_n
  from public.cycle_evaluation_responsibilities
  where organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and responsible_collaborator_id = 'fbb00000-0000-0000-0000-0000000000c2'
    and valid_to is null;
  if v_n <> 4 then
    raise exception '[FAIL] esperadas 4 responsabilidades abertas com C_GER2';
  end if;
  raise notice '[PASS] 4 eventos com original C_GER -> novo C_GER2; original preservado; novas abertas';
end $$;

do $$
declare
  v_n int;
begin
  -- Vigente após a sucessão (substituto encerrado) = C_GER2.
  select count(*) into v_n
  from public.resolver_responsavel_avaliacao_vigente(
    'fba00000-0000-0000-0000-0000000000a1', 2025, 1, '2025-07-15T00:00:00Z')
  where responsible_collaborator_id <> 'fbb00000-0000-0000-0000-0000000000c2'
     or is_substitute;
  if v_n <> 0 then
    raise exception '[FAIL] vigente em 2025-07-15 deveria ser C_GER2 (sem substituto)';
  end if;
  raise notice '[PASS] vigente apos sucessao = C_GER2';
end $$;

-- ============================================================================
-- 6) Idempotência e não-reabertura
-- ============================================================================

do $$
declare
  v_antes int;
  v_depois int;
  v_ids uuid[];
begin
  select count(*) into v_antes from public.evaluation_succession_events;

  select array_agg(cer.id order by cer.id) into v_ids
  from public.cycle_evaluation_responsibilities cer
  join public.collegiate_cycle_snapshots s on s.id = cer.snapshot_id
  where s.organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and cer.valid_to is null;

  perform public.registrar_sucessao_avaliador(
    v_ids, '2025-07-01T00:00:00Z',
    'Mudanca definitiva de gestor',
    'fbf00000-0000-0000-0000-000000000001'
  );

  select count(*) into v_depois from public.evaluation_succession_events;
  if v_antes <> v_depois then
    raise exception '[FAIL] repeticao da sucessao deveria ser idempotente (antes %, depois %)', v_antes, v_depois;
  end if;
  raise notice '[PASS] repeticao da mesma sucessao nao duplica eventos nem reabre responsabilidade';
end $$;

do $$
declare
  v_closed uuid;
  v_ok boolean := false;
begin
  select id into v_closed
  from public.cycle_evaluation_responsibilities
  where organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and responsible_collaborator_id = 'fbb00000-0000-0000-0000-0000000000c1'
    and valid_to is not null
  limit 1;

  begin
    perform public.registrar_sucessao_avaliador(
      array[v_closed]::uuid[], '2025-08-01T00:00:00Z', 'x',
      'fbf00000-0000-0000-0000-000000000001'
    );
  exception when others then
    if sqlerrm not like '%ja encerrada%' then
      raise;
    end if;
    v_ok := true;
  end;

  if not v_ok then
    raise exception '[FAIL] sucessao sobre responsabilidade encerrada NAO foi bloqueada';
  end if;
  raise notice '[PASS] responsabilidade encerrada nao e reaberta (RPC rejeita id fechado)';
end $$;

do $$
declare
  v_open uuid;
  v_ok boolean := false;
begin
  -- Torna P_GER vago (fecha occupation do sucessor) para o teste fail-closed.
  update public.occupations
     set valid_to = '2025-08-01T00:00:00Z'
   where organizational_position_id = 'fbc00000-0000-0000-0000-0000000000a1'
     and collaborator_id = 'fbb00000-0000-0000-0000-0000000000c2'
     and valid_to is null;

  select id into v_open
  from public.cycle_evaluation_responsibilities
  where organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and responsible_collaborator_id = 'fbb00000-0000-0000-0000-0000000000c2'
    and valid_to is null
  limit 1;

  begin
    perform public.registrar_sucessao_avaliador(
      array[v_open]::uuid[], '2025-08-15T00:00:00Z', 'vacuo',
      'fbf00000-0000-0000-0000-000000000001'
    );
  exception when others then
    if sqlerrm not like '%sem novo responsavel%' then
      raise;
    end if;
    v_ok := true;
  end;

  if not v_ok then
    raise exception '[FAIL] sucessao com superior vago NAO foi bloqueada (fail-closed)';
  end if;
  raise notice '[PASS] superior vago sem novo responsavel e rejeitado (fail-closed)';
end $$;

-- ============================================================================
-- 7) Integridade multi-organização (FKs compostas)
-- ============================================================================

do $$
declare
  v_snap uuid;
  v_ok boolean := false;
begin
  select id into v_snap
  from public.collegiate_cycle_snapshots
  where organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and ano = 2025 and ciclo = 1
  limit 1;

  begin
    insert into public.cycle_evaluation_responsibilities (
      organization_id, snapshot_id, position_id, responsible_collaborator_id, valid_from
    ) values (
      'fba00000-0000-0000-0000-0000000000a1',
      v_snap,
      'fbc00000-0000-0000-0000-0000000000a9',  -- P_BETA (outra organização)
      'fbb00000-0000-0000-0000-0000000000c1',
      '2025-03-01T00:00:00Z'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;

  if not v_ok then
    raise exception '[FAIL] responsabilidade com posicao cross-organization NAO foi bloqueada';
  end if;
  raise notice '[PASS] responsabilidade cross-organization bloqueada (FK composta posicao+org)';
end $$;

do $$
declare
  v_snap uuid;
  v_ok boolean := false;
begin
  select id into v_snap
  from public.collegiate_cycle_snapshots
  where organization_id = 'fba00000-0000-0000-0000-0000000000a1'
    and ano = 2025 and ciclo = 1
  limit 1;

  begin
    insert into public.evaluation_succession_events (
      organization_id, snapshot_id, position_id,
      previous_responsible_collaborator_id, new_responsible_collaborator_id,
      succession_date, motive, author_user_profile_id
    ) values (
      'fba00000-0000-0000-0000-0000000000a1',
      v_snap,
      'fbc00000-0000-0000-0000-0000000000a2',
      'fbb00000-0000-0000-0000-0000000000d1',  -- CBeta (outra organização)
      'fbb00000-0000-0000-0000-0000000000c1',
      '2026-01-01T00:00:00Z', 'cross-org', 'fbf00000-0000-0000-0000-000000000001'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;

  if not v_ok then
    raise exception '[FAIL] evento com responsavel cross-organization NAO foi bloqueado';
  end if;
  raise notice '[PASS] evento de sucessao cross-organization bloqueado (FK composta colaborador+org)';
end $$;

-- ============================================================================
-- 8) RLS deny-by-default em execução (como authenticated)
-- ============================================================================

set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.cycle_evaluation_responsibilities;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou cycle_evaluation_responsibilities';
  end if;
  select count(*) into v_n from public.evaluation_succession_events;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou evaluation_succession_events';
  end if;
  raise notice '[PASS] RLS: authenticated nao le as tabelas F3-09';
end $$;

do $$
begin
  begin
    insert into public.cycle_evaluation_responsibilities (
      organization_id, snapshot_id, position_id, responsible_collaborator_id, valid_from
    ) values (
      'fba00000-0000-0000-0000-0000000000a1',
      'fbc00000-0000-0000-0000-0000000000a1',
      'fbc00000-0000-0000-0000-0000000000a2',
      'fbb00000-0000-0000-0000-0000000000c1',
      '2027-01-01T00:00:00Z'
    );
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em responsabilidades';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated negado em cycle_evaluation_responsibilities';
end $$;

reset role;

-- ============================================================================
-- 9) F3-01..F3-08 permanecem intactas
-- ============================================================================

do $$
declare
  v_n int;
begin
  -- As 7 funções de resolução da F3-07 permanecem.
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('organizacao_resolver_responsavel_posicao',
                      'organizacao_resolver_gestor_direto',
                      'organizacao_resolver_subordinados_diretos',
                      'organizacao_resolver_descendentes',
                      'organizacao_resolver_cadeia',
                      'organizacao_resolver_escopo_posicoes',
                      'organizacao_resolver_escopo_unidades');
  if v_n <> 7 then
    raise exception '[FAIL] funcoes de resolucao (F3-07) deveriam permanecer (encontrado %)', v_n;
  end if;

  -- Nenhuma policy nova (as 3 de identidade F2-03/F2-07 permanecem).
  select count(*) into v_n
  from pg_policies p
  where p.schemaname = 'public';
  if v_n <> 3 then
    raise exception '[FAIL] quantidade de policies alterada (esperado 3, encontrado %)', v_n;
  end if;

  -- RPC de materialização do colegiado (F3-08) permanece presente.
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'materializar_colegiado_ciclo';
  if v_n <> 1 then
    raise exception '[FAIL] materializar_colegiado_ciclo (F3-08) deveria permanecer';
  end if;
  raise notice '[PASS] F3-07 (resolucao), policies de identidade e F3-08 intactas';
end $$;

-- ============================================================================
-- 10) Limpeza do cenário sintético (banco local permanece limpo)
-- ============================================================================

delete from public.evaluation_succession_events
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.cycle_evaluation_responsibilities
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_members
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_positions
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshots
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configuration_members
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configurations
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.temporary_responsibilities
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.occupations
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
where collaborator_id::text like 'fbb00000-0000-0000-0000-0000000000%';

delete from public.position_reporting_lines
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.organizational_positions
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.organizational_units
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id::text like 'fbb00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.organizations
where id::text like 'fba00000-0000-0000-0000-0000000000%';

delete from public.user_profiles
where id = 'fbf00000-0000-0000-0000-000000000001';

delete from auth.users
where id = 'fbf00000-0000-0000-0000-000000000001';

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.cycle_evaluation_responsibilities
  where organization_id::text like 'fba00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-09 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-09 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-09: todas as verificacoes passaram (schema, FKs, RPC, RLS).';
end $$;
