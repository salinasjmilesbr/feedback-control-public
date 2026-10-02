-- ============================================================================
-- F3-08 (Issue #85): validação automatizada — configuração padrão do colegiado
-- e snapshot por ciclo (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-08.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-08.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-08.sql -Raw -Encoding UTF8 |
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
-- ORG_A = faa00000-0000-0000-0000-0000000000a1; ORG_B = faa...00b1.
-- C_GER c1, EVAL1 c2, EVAL2 c3, EVAL3 c4, EVAL4 c5, EVAL5 c6, M1 c7, M2 c8,
-- CBeta d1.
-- Posições: P_GER a1, P_GER2 a7, P_E1 a2, P_E2 a3, P_E3 a4, P_X a5, P_Y a6,
-- P_Z a8.
-- Config EVAL1 v1 = fa100000-...-001; (v2 criada na validação).

-- ============================================================================
-- 1) Estrutura: tabelas esperadas, constraints, funções e RLS
-- ============================================================================

-- F6 / #429: com as fases seguintes entregues, o inventário exato de tabelas
-- deixou de valer (o inventário corrente é guardado por `02-validar-f4-08.sql`).
-- A prova passa a exigir a PRESENÇA das 19 tabelas esperadas da F3-08 —
-- reprova remoção/renomeação sem transformar evolução legítima em falha.
do $$
declare
  v_tabela text;
  v_tabelas text[] := array[
    'collaborator_identifiers',
    'collaborator_status_periods',
    'collaborators',
    'collegiate_configuration_members',
    'collegiate_configurations',
    'collegiate_cycle_snapshot_members',
    'collegiate_cycle_snapshot_positions',
    'collegiate_cycle_snapshots',
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
  ];
begin
  foreach v_tabela in array v_tabelas loop
    if not exists (
      select 1 from pg_tables t
      where t.schemaname = 'public' and t.tablename = v_tabela
    ) then
      raise exception '[FAIL] tabela esperada da F3-08 ausente no schema public: %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] as 19 tabelas esperadas da F3-08 estao presentes (F2 + F3-01..07 + F3-08)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_constraint
  where conname in (
    'pk_collegiate_configurations',
    'uq_collegiate_configurations_id_organization',
    'fk_collegiate_configurations_organizations',
    'fk_collegiate_configurations_collaborators',
    'ck_collegiate_configurations_valid_to',
    'ex_collegiate_configurations_no_overlap',
    'pk_collegiate_configuration_members',
    'uq_collegiate_configuration_members_config_member',
    'fk_collegiate_configuration_members_configurations',
    'fk_collegiate_configuration_members_collaborators',
    'pk_collegiate_cycle_snapshots',
    'uq_collegiate_cycle_snapshots_id_organization',
    'uq_collegiate_cycle_snapshots_org_ano_ciclo_avaliado',
    'fk_collegiate_cycle_snapshots_organizations',
    'fk_collegiate_cycle_snapshots_collaborators',
    'ck_collegiate_cycle_snapshots_ano',
    'ck_collegiate_cycle_snapshots_ciclo',
    'pk_collegiate_cycle_snapshot_positions',
    'uq_collegiate_cycle_snapshot_positions_snapshot_position',
    'fk_collegiate_cycle_snapshot_positions_snapshots',
    'fk_collegiate_cycle_snapshot_positions_positions',
    'fk_collegiate_cycle_snapshot_positions_superior_position',
    'fk_collegiate_cycle_snapshot_positions_superior_collaborator',
    'ck_collegiate_cycle_snapshot_positions_superior_pair',
    'pk_collegiate_cycle_snapshot_members',
    'uq_collegiate_cycle_snapshot_members_snapshot_member',
    'fk_collegiate_cycle_snapshot_members_snapshots',
    'fk_collegiate_cycle_snapshot_members_collaborators'
  );
  if v_n <> 28 then
    raise exception '[FAIL] constraints esperadas da F3-08 ausentes (% encontradas)', v_n;
  end if;
  raise notice '[PASS] 28 constraints esperadas presentes nas tabelas de colegiado/snapshot';
end $$;

do $$
declare
  v_n int;
begin
  -- FKs das novas tabelas todas ON DELETE RESTRICT.
  select count(*) into v_n
  from pg_constraint c
  where c.contype = 'f'
    and c.conrelid in (
      'public.collegiate_configurations'::regclass,
      'public.collegiate_configuration_members'::regclass,
      'public.collegiate_cycle_snapshots'::regclass,
      'public.collegiate_cycle_snapshot_positions'::regclass,
      'public.collegiate_cycle_snapshot_members'::regclass
    )
    and c.confdeltype <> 'r';
  if v_n <> 0 then
    raise exception '[FAIL] existe FK sem ON DELETE RESTRICT nas tabelas F3-08';
  end if;
  raise notice '[PASS] todas as FKs das tabelas F3-08 sao ON DELETE RESTRICT';
end $$;

do $$
declare
  v_n int;
  v_extras text;
begin
  select count(*) into v_n
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('collegiate_configurations',
                      'collegiate_configuration_members',
                      'collegiate_cycle_snapshots',
                      'collegiate_cycle_snapshot_positions',
                      'collegiate_cycle_snapshot_members')
    and c.relrowsecurity = true;
  if v_n <> 5 then
    raise exception '[FAIL] RLS nao habilitado em todas as tabelas F3-08';
  end if;
  -- F6 / #429 + #430: prova ESTRUTURAL completa e AUTOSSUFICIENTE das policies de
  -- `collegiate_*` (não delega à guarda da F4-08). Para o conjunto inteiro de
  -- tabelas `collegiate_%` o guard exige: (i) NENHUMA policy extra; (ii) as três
  -- policies esperadas presentes com identidade (tabela + nome), COMANDO `SELECT`,
  -- PAPEL `authenticated` e EXPRESSÃO own-tenant exata.
  select coalesce(string_agg(p.tablename || '.' || p.policyname, ', '
                             order by p.tablename, p.policyname), '')
    into v_extras
  from pg_policies p
  where p.schemaname = 'public'
    and p.tablename like 'collegiate_%'
    and (p.tablename, p.policyname) not in (
      ('collegiate_cycle_snapshots',          'collegiate_cycle_snapshots_select_same_tenant'),
      ('collegiate_cycle_snapshot_positions', 'collegiate_cycle_snapshot_positions_select_same_tenant'),
      ('collegiate_cycle_snapshot_members',   'collegiate_cycle_snapshot_members_select_same_tenant')
    );
  if v_extras <> '' then
    raise exception '[FAIL] policy EXTRA em tabela de colegiado/snapshot: %', v_extras;
  end if;

  select count(*) into v_n
  from (values
    ('collegiate_cycle_snapshots',          'collegiate_cycle_snapshots_select_same_tenant'),
    ('collegiate_cycle_snapshot_positions', 'collegiate_cycle_snapshot_positions_select_same_tenant'),
    ('collegiate_cycle_snapshot_members',   'collegiate_cycle_snapshot_members_select_same_tenant')
  ) as e(tabela, politica)
  join pg_policies p
    on p.schemaname = 'public'
   and p.tablename = e.tabela
   and p.policyname = e.politica
   and p.cmd = 'SELECT'
   and p.roles = array['authenticated']::name[]
   and regexp_replace(lower(coalesce(p.qual, '')), '\s+', '', 'g')
       = 'user_has_active_membership(organization_id)';
  if v_n <> 3 then
    raise exception '[FAIL] policies SELECT own-tenant de collegiate_* divergentes da identidade/tabela/comando/papel/expressao esperados (esperado 3 exatas, encontrado %)', v_n;
  end if;
  raise notice '[PASS] RLS habilitado nas 5 tabelas F3-08; exatamente as 3 policies SELECT own-tenant esperadas (identidade/tabela/comando/papel/expressao) e nenhuma extra';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('materializar_colegiado_ciclo',
                      'enforce_collegiate_configuration_member_not_self');
  if v_n <> 2 then
    raise exception '[FAIL] funcoes F3-08 ausentes (% encontradas)', v_n;
  end if;

  select count(*) into v_n
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('materializar_colegiado_ciclo',
                      'enforce_collegiate_configuration_member_not_self')
    and p.prosecdef = true;
  if v_n <> 0 then
    raise exception '[FAIL] funcao F3-08 deveria ser SECURITY INVOKER';
  end if;
  raise notice '[PASS] materializar_colegiado_ciclo e trigger de self presentes (SECURITY INVOKER)';
end $$;

-- ============================================================================
-- 2) Configuração padrão do colegiado
-- ============================================================================

do $$
declare
  v_members uuid[];
  v_n int;
begin
  select array_agg(member_collaborator_id order by member_collaborator_id) into v_members
  from public.collegiate_configuration_members
  where configuration_id = 'fa100000-0000-0000-0000-000000000001';
  if v_members is distinct from
     array['fab00000-0000-0000-0000-0000000000c7',
           'fab00000-0000-0000-0000-0000000000c8']::uuid[] then
    raise exception '[FAIL] membros de EVAL1 (v1) deveriam ser {M1, M2}';
  end if;

  -- Configuração explicitamente vazia (EVAL3) existe com 0 membros.
  select count(*) into v_n
  from public.collegiate_configuration_members
  where configuration_id = 'fa100000-0000-0000-0000-000000000004';
  if v_n <> 0 then
    raise exception '[FAIL] configuracao de EVAL3 deveria ser explicitamente vazia';
  end if;
  select count(*) into v_n
  from public.collegiate_configurations
  where id = 'fa100000-0000-0000-0000-000000000004'
    and valid_to is null;
  if v_n <> 1 then
    raise exception '[FAIL] configuracao vazia vigente de EVAL3 ausente';
  end if;
  raise notice '[PASS] config: multi-membros (EVAL1) e explicitamente vazia (EVAL3) validas';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.collegiate_configuration_members (
      organization_id, configuration_id, member_collaborator_id
    ) values (
      'faa00000-0000-0000-0000-0000000000a1',
      'fa100000-0000-0000-0000-000000000001',
      'fab00000-0000-0000-0000-0000000000c2'
    );
  exception when others then
    if sqlerrm not like '%proprio colegiado%' then
      raise;
    end if;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] self (avaliado como membro) NAO foi bloqueado';
  end if;
  raise notice '[PASS] self bloqueado: avaliado nao pode ser membro do proprio colegiado';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.collegiate_configuration_members (
      organization_id, configuration_id, member_collaborator_id
    ) values (
      'faa00000-0000-0000-0000-0000000000a1',
      'fa100000-0000-0000-0000-000000000001',
      'fab00000-0000-0000-0000-0000000000c7'
    );
  exception when unique_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] membro duplicado NAO foi bloqueado';
  end if;
  raise notice '[PASS] membro duplicado na mesma configuracao bloqueado (unique)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.collegiate_configuration_members (
      organization_id, configuration_id, member_collaborator_id
    ) values (
      'faa00000-0000-0000-0000-0000000000a1',
      'fa100000-0000-0000-0000-000000000001',
      'fab00000-0000-0000-0000-0000000000d1'
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] membro cross-organization NAO foi bloqueado';
  end if;
  raise notice '[PASS] membro de outra organizacao bloqueado (FK composta)';
end $$;

do $$
declare
  v_ok boolean := false;
begin
  begin
    insert into public.collegiate_configurations (
      organization_id, collaborator_id, valid_from, valid_to
    ) values (
      'faa00000-0000-0000-0000-0000000000a1',
      'fab00000-0000-0000-0000-0000000000d1',
      '2025-01-01T00:00:00Z', null
    );
  exception when foreign_key_violation then
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] configuracao cross-organization NAO foi bloqueada';
  end if;
  raise notice '[PASS] configuracao de avaliado de outra organizacao bloqueada (FK composta)';
end $$;

do $$
declare
  v_n int;
  v_members uuid[];
begin
  -- Mudança de configuração preservando histórico: fecha v1 em 2025-06-30 e
  -- abre v2 de 2025-07-01 com membro {M1}.
  update public.collegiate_configurations
     set valid_to = '2025-06-30T00:00:00Z'
   where id = 'fa100000-0000-0000-0000-000000000001';

  insert into public.collegiate_configurations (
    id, organization_id, collaborator_id, valid_from, valid_to
  ) values (
    'fa100000-0000-0000-0000-000000000002',
    'faa00000-0000-0000-0000-0000000000a1',
    'fab00000-0000-0000-0000-0000000000c2',
    '2025-07-01T00:00:00Z', null
  );

  insert into public.collegiate_configuration_members (
    organization_id, configuration_id, member_collaborator_id
  ) values (
    'faa00000-0000-0000-0000-0000000000a1',
    'fa100000-0000-0000-0000-000000000002',
    'fab00000-0000-0000-0000-0000000000c7'
  );

  select count(*) into v_n
  from public.collegiate_configurations
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000c2';
  if v_n <> 2 then
    raise exception '[FAIL] EVAL1 deveria ter 2 versoes de configuracao (historico preservado)';
  end if;

  select array_agg(member_collaborator_id order by member_collaborator_id) into v_members
  from public.collegiate_configuration_members
  where configuration_id = 'fa100000-0000-0000-0000-000000000001';
  if v_members is distinct from
     array['fab00000-0000-0000-0000-0000000000c7',
           'fab00000-0000-0000-0000-0000000000c8']::uuid[] then
    raise exception '[FAIL] v1 de EVAL1 deveria preservar {M1, M2}';
  end if;

  select count(*) into v_n
  from public.collegiate_configuration_members
  where configuration_id = 'fa100000-0000-0000-0000-000000000002';
  if v_n <> 1 then
    raise exception '[FAIL] v2 de EVAL1 deveria ter 1 membro';
  end if;
  raise notice '[PASS] mudanca de configuracao fecha v1 e abre v2, preservando historico';
end $$;

-- ============================================================================
-- 3) Snapshot por ciclo (ativação)
-- ============================================================================

do $$
begin
  -- Ciclo 1 (2025, ciclo 1) referência 2025-03-01 (config v1 de EVAL1 vigente).
  perform public.materializar_colegiado_ciclo(
    'faa00000-0000-0000-0000-0000000000a1',
    2025, 1, '2025-03-01T00:00:00Z',
    array[
      'fab00000-0000-0000-0000-0000000000c2',
      'fab00000-0000-0000-0000-0000000000c3',
      'fab00000-0000-0000-0000-0000000000c4',
      'fab00000-0000-0000-0000-0000000000c5',
      'fab00000-0000-0000-0000-0000000000c6'
    ]::uuid[]
  );
  raise notice '[PASS] materializacao do ciclo 1 executada sem erros';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.collegiate_cycle_snapshots
  where organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and ano = 2025 and ciclo = 1;
  if v_n <> 5 then
    raise exception '[FAIL] ciclo 1 deveria ter 5 snapshots (um por avaliado), encontrado %', v_n;
  end if;
  raise notice '[PASS] um snapshot por avaliado informado (5)';
end $$;

do $$
declare
  v_members uuid[];
  v_n int;
  v_snap uuid;
  v_sup_pos uuid;
  v_sup_col uuid;
begin
  select id into v_snap
  from public.collegiate_cycle_snapshots
  where organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and ano = 2025 and ciclo = 1
    and collaborator_id = 'fab00000-0000-0000-0000-0000000000c2';

  select array_agg(member_collaborator_id order by member_collaborator_id) into v_members
  from public.collegiate_cycle_snapshot_members
  where snapshot_id = v_snap;
  if v_members is distinct from
     array['fab00000-0000-0000-0000-0000000000c7',
           'fab00000-0000-0000-0000-0000000000c8']::uuid[] then
    raise exception '[FAIL] snapshot ciclo 1 de EVAL1 deveria congelar {M1, M2}';
  end if;

  select count(*) into v_n
  from public.collegiate_cycle_snapshot_positions
  where snapshot_id = v_snap;
  if v_n <> 1 then
    raise exception '[FAIL] EVAL1 deveria ter 1 posicao no snapshot';
  end if;

  select superior_position_id, superior_collaborator_id into v_sup_pos, v_sup_col
  from public.collegiate_cycle_snapshot_positions
  where snapshot_id = v_snap
    and position_id = 'fac00000-0000-0000-0000-0000000000a2';
  if v_sup_pos is distinct from 'fac00000-0000-0000-0000-0000000000a1'
     or v_sup_col is distinct from 'fab00000-0000-0000-0000-0000000000c1' then
    raise exception '[FAIL] superior de EVAL1 no snapshot deveria ser P_GER/C_GER';
  end if;
  raise notice '[PASS] snapshot de EVAL1 congela membros {M1,M2} e superior C_GER';
end $$;

do $$
declare
  v_n int;
begin
  -- EVAL2 sem configuração → snapshot com 0 membros; EVAL3 config vazia →
  -- 0 membros; EVAL4 sem posição → 0 posições; EVAL5 posição ÚNICA (F6/#427:
  -- a união de múltiplas positions foi abolida).
  select count(*) into v_n
  from public.collegiate_cycle_snapshot_members sm
  join public.collegiate_cycle_snapshots s on s.id = sm.snapshot_id
  where s.organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and s.collaborator_id = 'fab00000-0000-0000-0000-0000000000c3';
  if v_n <> 0 then
    raise exception '[FAIL] EVAL2 (sem config) deveria ter snapshot com 0 membros';
  end if;

  select count(*) into v_n
  from public.collegiate_cycle_snapshot_members sm
  join public.collegiate_cycle_snapshots s on s.id = sm.snapshot_id
  where s.organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and s.collaborator_id = 'fab00000-0000-0000-0000-0000000000c4';
  if v_n <> 0 then
    raise exception '[FAIL] EVAL3 (config vazia) deveria ter snapshot com 0 membros';
  end if;

  select count(*) into v_n
  from public.collegiate_cycle_snapshot_positions sp
  join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
  where s.organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and s.collaborator_id = 'fab00000-0000-0000-0000-0000000000c5';
  if v_n <> 0 then
    raise exception '[FAIL] EVAL4 (sem posicao) deveria ter snapshot com 0 posicoes';
  end if;
  raise notice '[PASS] sem config / config vazia → 0 membros; avaliado sem posicao → 0 posicoes';
end $$;

do $$
declare
  v_pos uuid[];
  v_n int;
begin
  -- F6 / #427 §5: origem de ocupação ÚNICA. O avaliado EVAL5 possui somente
  -- P_X a5; o snapshot congela exatamente essa posição — NUNCA a união das
  -- múltiplas posições que o contrato anterior admitia.
  select array_agg(position_id order by position_id) into v_pos
  from public.collegiate_cycle_snapshot_positions sp
  join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
  where s.organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and s.collaborator_id = 'fab00000-0000-0000-0000-0000000000c6';
  if v_pos is distinct from
     array['fac00000-0000-0000-0000-0000000000a5']::uuid[] then
    raise exception '[FAIL] EVAL5 deveria ter snapshot com 1 posicao (P_X) — sem uniao de posicoes';
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000c6'
    and valid_from <= '2025-03-01T00:00:00Z'
    and (valid_to is null or valid_to > '2025-03-01T00:00:00Z');
  if v_n <> 1 then
    raise exception '[FAIL] EVAL5 deveria ter cardinalidade de ocupacao = 1 (encontrado %)', v_n;
  end if;
  raise notice '[PASS] avaliado com origem unica congelado com 1 posicao (sem uniao de posicoes)';
end $$;

do $$
declare
  v_ok boolean := false;
  v_state text := null;
  v_msg text := null;
  v_n int;
begin
  -- F6 / #427: a segunda ocupação SIMULTÂNEA do mesmo colaborador deixou de ser
  -- representável. A barreira final do banco (exclusion por collaborator_id)
  -- recusa a inserção com 23P01 e nada é persistido.
  begin
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'faa00000-0000-0000-0000-0000000000a1',
      'fab00000-0000-0000-0000-0000000000c6',
      'fac00000-0000-0000-0000-0000000000a6',
      'segunda ocupacao simultanea (sintetica)', '2025-01-01T00:00:00Z', null
    );
  exception when others then
    v_state := sqlstate; v_msg := sqlerrm;
    if v_state = '23P01'
       and v_msg like '%ex_occupations_collaborator_no_overlap%' then
      v_ok := true;
    end if;
  end;

  if not v_ok then
    raise exception '[FAIL] sobreposicao de ocupacao do MESMO colaborador NAO foi barrada pela exclusion por colaborador (sqlstate=% msg=%)',
      coalesce(v_state, 'sem erro'), coalesce(v_msg, 'sem mensagem');
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000c6';
  if v_n <> 1 then
    raise exception '[FAIL] tentativa recusada deixou ocupacao persistida (encontrado %)', v_n;
  end if;
  raise notice '[PASS] segunda ocupacao simultanea do mesmo colaborador recusada (23P01) sem persistir nada';
end $$;

do $$
declare
  v_sup_col uuid;
begin
  -- Posição sem superior (P_E3 raiz): registro de posição com superior null.
  select superior_collaborator_id into v_sup_col
  from public.collegiate_cycle_snapshot_positions sp
  join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
  where s.organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 1
    and s.collaborator_id = 'fab00000-0000-0000-0000-0000000000c4'
    and sp.position_id = 'fac00000-0000-0000-0000-0000000000a4';
  if v_sup_col is not null then
    raise exception '[FAIL] posicao raiz (sem superior) deveria registrar superior null';
  end if;
  raise notice '[PASS] posicao sem superior registrada com superior null (nao corrompe)';
end $$;

-- ============================================================================
-- 4) Idempotência da materialização
-- ============================================================================

do $$
declare
  v_antes int;
  v_depois int;
begin
  select count(*) into v_antes
  from public.collegiate_cycle_snapshots
  where organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and ano = 2025 and ciclo = 1;

  perform public.materializar_colegiado_ciclo(
    'faa00000-0000-0000-0000-0000000000a1',
    2025, 1, '2025-03-01T00:00:00Z',
    array[
      'fab00000-0000-0000-0000-0000000000c2',
      'fab00000-0000-0000-0000-0000000000c3',
      'fab00000-0000-0000-0000-0000000000c4',
      'fab00000-0000-0000-0000-0000000000c5',
      'fab00000-0000-0000-0000-0000000000c6'
    ]::uuid[]
  );

  select count(*) into v_depois
  from public.collegiate_cycle_snapshots
  where organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and ano = 2025 and ciclo = 1;

  if v_antes <> v_depois then
    raise exception '[FAIL] repeticao da materializacao deveria ser idempotente (antes %, depois %)', v_antes, v_depois;
  end if;
  raise notice '[PASS] repeticao da mesma materializacao nao duplica snapshots';
end $$;

-- ============================================================================
-- 5) Snapshot com configuração vigente na data (ciclo 2 usa v2 de EVAL1)
-- ============================================================================

do $$
begin
  perform public.materializar_colegiado_ciclo(
    'faa00000-0000-0000-0000-0000000000a1',
    2025, 2, '2025-08-01T00:00:00Z',
    array[
      'fab00000-0000-0000-0000-0000000000c2',
      'fab00000-0000-0000-0000-0000000000c3',
      'fab00000-0000-0000-0000-0000000000c4',
      'fab00000-0000-0000-0000-0000000000c5',
      'fab00000-0000-0000-0000-0000000000c6'
    ]::uuid[]
  );
  raise notice '[PASS] materializacao do ciclo 2 executada';
end $$;

do $$
declare
  v_members uuid[];
begin
  select array_agg(member_collaborator_id order by member_collaborator_id) into v_members
  from public.collegiate_cycle_snapshot_members sm
  join public.collegiate_cycle_snapshots s on s.id = sm.snapshot_id
  where s.organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 2
    and s.collaborator_id = 'fab00000-0000-0000-0000-0000000000c2';
  if v_members is distinct from array['fab00000-0000-0000-0000-0000000000c7']::uuid[] then
    raise exception '[FAIL] ciclo 2 (v2 vigente) de EVAL1 deveria congelar {M1}';
  end if;
  raise notice '[PASS] snapshot usa a configuracao vigente na data (ciclo1 {M1,M2} vs ciclo2 {M1})';
end $$;

-- ============================================================================
-- 6) Mudanças posteriores não alteram snapshots
-- ============================================================================
-- F6 / #427: a transferência de EVAL1 (c2) de P_E1 (a2) para P_Z (a8) em
-- 2026-01-01 é SEQUENCIAL — fecha A e abre B no MESMO instante, períodos
-- consecutivos meio-abertos `[2025-01-01, 2026-01-01)` + `[2026-01-01, inf)`,
-- portanto VÁLIDA sob a nova invariante (não há sobreposição do mesmo
-- colaborador). A mudança VÁLIDA é executada e o snapshot JÁ CONGELADO tem de
-- permanecer IMUTÁVEL; em seguida, uma SEGUNDA ocupação simultânea é recusada
-- pelo banco (23P01) sem persistir nada.

do $$
declare
  v_n int;
  v_members uuid[];
  v_snap uuid;
  v_pos uuid[];
begin
  -- (1) Transferência SEQUENCIAL válida: fecha P_E1 e abre P_Z no mesmo instante.
  update public.occupations
     set valid_to = '2026-01-01T00:00:00Z'
   where collaborator_id = 'fab00000-0000-0000-0000-0000000000c2'
     and organizational_position_id = 'fac00000-0000-0000-0000-0000000000a2'
     and valid_to is null;
  if not found then
    raise exception '[FAIL] EVAL1 deveria ter ocupacao ABERTA em P_E1 antes da transferencia sequencial';
  end if;

  insert into public.occupations (
    organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
  ) values (
    'faa00000-0000-0000-0000-0000000000a1',
    'fab00000-0000-0000-0000-0000000000c2',
    'fac00000-0000-0000-0000-0000000000a8',
    'Movido apos ciclos (transferencia sequencial)', '2026-01-01T00:00:00Z', null
  );

  -- A transferência é VÁLIDA e CONSECUTIVA: origem ÚNICA dos dois lados da
  -- fronteira (cardinalidade = 1) e histórico com exatamente 2 períodos.
  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000c2'
    and valid_from <= '2025-12-31T00:00:00Z'
    and (valid_to is null or valid_to > '2025-12-31T00:00:00Z');
  if v_n <> 1 then
    raise exception '[FAIL] antes de 2026-01-01 EVAL1 deveria ter 1 ocupacao vigente (P_E1), encontrado %', v_n;
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000c2'
    and valid_from <= '2026-01-01T00:00:00Z'
    and (valid_to is null or valid_to > '2026-01-01T00:00:00Z');
  if v_n <> 1 then
    raise exception '[FAIL] em 2026-01-01 EVAL1 deveria ter 1 ocupacao vigente (P_Z), encontrado %', v_n;
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000c2'
    and valid_from <= '2026-01-01T00:00:00Z'
    and (valid_to is null or valid_to > '2026-01-01T00:00:00Z')
    and organizational_position_id = 'fac00000-0000-0000-0000-0000000000a8';
  if v_n <> 1 then
    raise exception '[FAIL] a ocupacao vigente de EVAL1 em 2026-01-01 deveria ser P_Z (a8), encontrado %', v_n;
  end if;

  select array_agg(organizational_position_id order by valid_from) into v_pos
  from public.occupations
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000c2';
  if v_pos is distinct from array['fac00000-0000-0000-0000-0000000000a2',
                                 'fac00000-0000-0000-0000-0000000000a8']::uuid[] then
    raise exception '[FAIL] historico de EVAL1 deveria ser P_E1 -> P_Z (sequencial), encontrado %', v_pos;
  end if;

  -- (2) SNAPSHOT CONGELADO (ciclo 1) permanece IMUTÁVEL após a mudança VÁLIDA.
  select id into v_snap
  from public.collegiate_cycle_snapshots
  where organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and ano = 2025 and ciclo = 1
    and collaborator_id = 'fab00000-0000-0000-0000-0000000000c2';

  select count(*) into v_n
  from public.collegiate_cycle_snapshot_positions
  where snapshot_id = v_snap
    and position_id = 'fac00000-0000-0000-0000-0000000000a2';
  if v_n <> 1 then
    raise exception '[FAIL] snapshot ciclo 1 de EVAL1 deveria manter P_E1 apos a movimentacao';
  end if;

  select count(*) into v_n
  from public.collegiate_cycle_snapshot_positions
  where snapshot_id = v_snap
    and position_id = 'fac00000-0000-0000-0000-0000000000a8';
  if v_n <> 0 then
    raise exception '[FAIL] snapshot ciclo 1 de EVAL1 nao pode conter P_Z (snapshot congelado nao recalcula)';
  end if;

  select array_agg(member_collaborator_id order by member_collaborator_id) into v_members
  from public.collegiate_cycle_snapshot_members
  where snapshot_id = v_snap;
  if v_members is distinct from
     array['fab00000-0000-0000-0000-0000000000c7',
           'fab00000-0000-0000-0000-0000000000c8']::uuid[] then
    raise exception '[FAIL] membros do snapshot ciclo 1 deveriam permanecer {M1, M2}';
  end if;
  raise notice '[PASS] mudanca posterior VALIDA de occupation (transferencia sequencial P_E1 -> P_Z) nao altera snapshots materializados';
end $$;

do $$
declare
  v_ok boolean := false;
  v_state text := null;
  v_msg text := null;
  v_n int;
begin
  -- F6 / #427 — prova NEGATIVA: depois da transferência sequencial, EVAL1 (c2)
  -- tem P_Z ABERTA em `[2026-01-01, inf)`. Tentar manter uma SEGUNDA ocupação
  -- simultânea (reocupar P_E1 sem fechar P_Z) é recusado pela exclusion por
  -- `collaborator_id` (SQLSTATE 23P01) e NADA é persistido.
  begin
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'faa00000-0000-0000-0000-0000000000a1',
      'fab00000-0000-0000-0000-0000000000c2',
      'fac00000-0000-0000-0000-0000000000a2',
      'segunda ocupacao simultanea de EVAL1 (recusada)', '2026-06-01T00:00:00Z', null
    );
  exception when exclusion_violation then
    v_state := sqlstate; v_msg := sqlerrm;
    v_ok := true;
  end;

  if not v_ok then
    raise exception '[FAIL] segunda ocupacao simultanea de EVAL1 NAO foi recusada pela exclusion por colaborador (sqlstate=% msg=%)',
      coalesce(v_state, 'sem erro'), coalesce(v_msg, 'sem mensagem');
  end if;
  if v_msg is null
     or position('ex_occupations_collaborator_no_overlap' in v_msg) = 0 then
    raise exception '[FAIL] recusa de EVAL1 nao veio da exclusion por colaborador (msg=%)', v_msg;
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000c2';
  if v_n <> 2 then
    raise exception '[FAIL] tentativa recusada deixou ocupacao persistida para EVAL1 (esperado 2: P_E1 fechada + P_Z aberta; encontrado %)', v_n;
  end if;
  raise notice '[PASS] P_E1 nao pode voltar como segunda ocupacao simultanea de EVAL1 (23P01, nada persistido)';
end $$;

do $$
declare
  v_n int;
begin
  -- Repetir a materialização do ciclo 2 com a mesma solicitação não altera o
  -- snapshot existente (continua P_E1, sem re-materialização).
  perform public.materializar_colegiado_ciclo(
    'faa00000-0000-0000-0000-0000000000a1',
    2025, 2, '2025-08-01T00:00:00Z',
    array['fab00000-0000-0000-0000-0000000000c2']::uuid[]
  );

  select count(*) into v_n
  from public.collegiate_cycle_snapshot_positions sp
  join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
  where s.organization_id = 'faa00000-0000-0000-0000-0000000000a1'
    and s.ano = 2025 and s.ciclo = 2
    and s.collaborator_id = 'fab00000-0000-0000-0000-0000000000c2'
    and sp.position_id = 'fac00000-0000-0000-0000-0000000000a2';
  if v_n <> 1 then
    raise exception '[FAIL] reexecucao do ciclo 2 nao deveria re-materializar (P_E1 preservada)';
  end if;
  raise notice '[PASS] snapshots imutaveis (reexecucao idempotente nao substitui)';
end $$;

-- ============================================================================
-- 7) RPC rejeita avaliado de outra organização
-- ============================================================================

do $$
declare
  v_ok boolean := false;
  v_n int;
begin
  begin
    perform public.materializar_colegiado_ciclo(
      'faa00000-0000-0000-0000-0000000000a1',
      2025, 1, '2025-03-01T00:00:00Z',
      array['fab00000-0000-0000-0000-0000000000d1']::uuid[]
    );
  exception when others then
    if sqlerrm not like '%outra organizacao%' then
      raise;
    end if;
    v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] RPC aceitou avaliado de outra organizacao';
  end if;

  select count(*) into v_n
  from public.collegiate_cycle_snapshots
  where collaborator_id = 'fab00000-0000-0000-0000-0000000000d1';
  if v_n <> 0 then
    raise exception '[FAIL] RPC nao deveria ter criado snapshot para avaliado cross-org';
  end if;
  raise notice '[PASS] RPC rejeita avaliado de outra organizacao (sem snapshot)';
end $$;

-- ============================================================================
-- 8) Negação efetiva ao cliente (ACL/RLS) em execução (como authenticated)
-- ============================================================================
-- A ESTRUTURA que produz a negação (GRANT ausente nas tabelas de configuração,
-- GRANT + policy own-tenant nas 3 de snapshot) é provada acima e na seção 1; os
-- blocos de runtime abaixo provam a NEGACAO EFETIVA ao cliente (ACL ou RLS), sem
-- afirmar qual dos dois mecanismos a produziu isoladamente.

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from (values
    ('collegiate_cycle_snapshots',          true),
    ('collegiate_cycle_snapshot_positions', true),
    ('collegiate_cycle_snapshot_members',   true),
    ('collegiate_configurations',           false),
    ('collegiate_configuration_members',    false)
  ) as e(tabela, esperado)
  where has_table_privilege('authenticated', ('public.' || e.tabela)::regclass, 'SELECT')
        is distinct from e.esperado;
  if v_n <> 0 then
    raise exception '[FAIL] GRANT SELECT de authenticated divergente em collegiate_* (% tabelas; contrato: apenas as 3 de snapshot, com policy own-tenant)', v_n;
  end if;
  raise notice '[PASS] estrutura de grants: authenticated com SELECT somente nas 3 tabelas de snapshot (own-tenant)';
end $$;

set role authenticated;

do $$
declare
  v_n int := 0;
begin
  -- F6 / #429: a negação pode vir da AUSÊNCIA de GRANT (privilégio) ou de RLS
  -- own-tenant filtrando as linhas (0). Ambos são fail-closed.
  begin
    select count(*) into v_n from public.collegiate_configurations;
  exception when insufficient_privilege then
    v_n := 0;
  end;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou collegiate_configurations';
  end if;
  begin
    select count(*) into v_n from public.collegiate_cycle_snapshots;
  exception when insufficient_privilege then
    v_n := 0;
  end;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou collegiate_cycle_snapshots';
  end if;
  begin
    select count(*) into v_n from public.collegiate_cycle_snapshot_members;
  exception when insufficient_privilege then
    v_n := 0;
  end;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou collegiate_cycle_snapshot_members';
  end if;
  raise notice '[PASS] negacao efetiva ao cliente (ACL ou RLS): authenticated nao le tabelas de colegiado/snapshot';
end $$;

do $$
begin
  begin
    insert into public.collegiate_configurations (
      organization_id, collaborator_id, valid_from, valid_to
    ) values (
      'faa00000-0000-0000-0000-0000000000a1',
      'fab00000-0000-0000-0000-0000000000c2',
      '2027-01-01T00:00:00Z', null
    );
    raise exception '[FAIL] negacao efetiva ao cliente (ACL ou RLS) permitiu INSERT de authenticated em collegiate_configurations';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] negacao efetiva ao cliente (ACL ou RLS): INSERT de authenticated negado em collegiate_configurations';
end $$;

do $$
declare
  v_n int := 0;
begin
  -- F6 / #429: a negação de escrita pode vir da AUSÊNCIA de GRANT (privilégio)
  -- ou de RLS (0 linhas) — ambas fail-closed.
  begin
    update public.collegiate_cycle_snapshots set reference_date = reference_date;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then
    v_n := 0;
  end;
  if v_n <> 0 then
    raise exception '[FAIL] negacao efetiva ao cliente (ACL ou RLS) permitiu UPDATE de authenticated em snapshots (%)', v_n;
  end if;
  raise notice '[PASS] negacao efetiva ao cliente (ACL ou RLS): UPDATE de authenticated em snapshots nao afeta linhas';
end $$;

do $$
declare
  v_n int := 0;
begin
  begin
    delete from public.collegiate_configuration_members;
    get diagnostics v_n = row_count;
  exception when insufficient_privilege then
    v_n := 0;
  end;
  if v_n <> 0 then
    raise exception '[FAIL] negacao efetiva ao cliente (ACL ou RLS) permitiu DELETE de authenticated em members (%)', v_n;
  end if;
  raise notice '[PASS] negacao efetiva ao cliente (ACL ou RLS): DELETE de authenticated em members nao afeta linhas';
end $$;

reset role;

-- ============================================================================
-- 9) F3-01..F3-07 permanecem intactas
-- ============================================================================

-- F6 / #429: a contagem FIXA dos resolvers (7) deixou de ser expansível quando as
-- fases seguintes (F3-09 etc.) acrescentaram resolvers legítimos. A prova passa a
-- exigir a PRESENÇA das funções F3-07 esperadas — reprova remoção/renomeação sem
-- transformar adição legítima em falha. As policies de identidade/sessão da F2
-- passam ao mesmo padrão (presença das 3 esperadas), como em 02-validar-f4-02.sql.
do $$
declare
  v_fn text;
  v_fns text[] := array[
    'organizacao_resolver_cadeia',
    'organizacao_resolver_descendentes',
    'organizacao_resolver_escopo_posicoes',
    'organizacao_resolver_escopo_unidades',
    'organizacao_resolver_gestor_direto',
    'organizacao_resolver_responsavel_posicao',
    'organizacao_resolver_subordinados_diretos'
  ];
  v_n int;
begin
  foreach v_fn in array v_fns loop
    if not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_fn
    ) then
      raise exception '[FAIL] funcao de resolucao F3-07 ausente: %', v_fn;
    end if;
  end loop;

  select count(*) into v_n
  from pg_policies p
  where p.schemaname = 'public'
    and p.policyname in (
      'organizations_select_via_membership',
      'user_profiles_select_own',
      'user_organization_memberships_select_own'
    );
  if v_n <> 3 then
    raise exception '[FAIL] policies de identidade/sessao da F2 ausentes (esperado 3, encontrado %)', v_n;
  end if;
  raise notice '[PASS] funcoes F3-07 esperadas presentes e policies de identidade/sessao da F2 intactas';
end $$;

-- ============================================================================
-- 10) Limpeza do cenário sintético (banco local permanece limpo)
-- ============================================================================

delete from public.collegiate_cycle_snapshot_members
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_positions
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshots
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configuration_members
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configurations
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.occupations
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
where collaborator_id::text like 'fab00000-0000-0000-0000-0000000000%';

delete from public.position_reporting_lines
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.organizational_positions
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.organizational_units
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id::text like 'fab00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id::text like 'faa00000-0000-0000-0000-0000000000%';

delete from public.organizations
where id::text like 'faa00000-0000-0000-0000-0000000000%';

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.collegiate_cycle_snapshots s
  where s.organization_id::text like 'faa00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-08 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-08 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-08: todas as verificacoes passaram (schema, FKs, triggers, RPC, RLS).';
end $$;
