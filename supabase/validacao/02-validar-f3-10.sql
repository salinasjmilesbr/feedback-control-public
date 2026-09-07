-- ============================================================================
-- F3-10 (Issue #87): validação automatizada — estrutura organizacional
-- representativa do piloto (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar o cenário 01-cenario-f3-10.sql, como superuser
-- local, com ON_ERROR_STOP ativo:
--
--   Get-Content supabase/validacao/01-cenario-f3-10.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--   Get-Content supabase/validacao/02-validar-f3-10.sql -Raw -Encoding UTF8 |
--     docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1
--
-- Saída determinística: um `[PASS]` por verificação; qualquer falha levanta
-- exceção e aborta. O script NÃO toca projeto remoto, NÃO altera policies e
-- remove ao final os dados sintéticos do cenário.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- Constantes do cenário (prefixo fc)
-- ----------------------------------------------------------------------------
-- ORG_A = fca00000-0000-0000-0000-0000000000a1; ORG_B = fca...00b1.
-- Colaboradores: D_EXEC c1, D_AREA c2, G1 c3, C1 c4, C1_SUC c5, C2 c6, C3 c7,
-- AJR c8, APL c9, ASR ca, EST1 cb, CONS1 cc, G2 cd, A_G2 ce, CONS_G2 cf,
-- EST_G2 d0, ESP1 d1, DUP d2, SUB d3, M1 d4, M2 d5, CBeta e1.
-- Posições: P_DIR_EXEC a1, P_DIR_AREA a2, P_GER1 a3, P_COORD1 a4, P_COORD2 a5,
-- P_COORD3 a6, P_AN_JR a7, P_AN_PL a8, P_AN_SR a9, P_EST1 aa, P_CONS1 ab,
-- P_VACANTE ac, P_AN_TF ad, P_GER2 ae, P_AN_G2 af, P_CONS_G2 b0, P_EST_G2 b1,
-- P_ESP1 b2, P_DUP_A b3, P_DUP_B b4, P_BETA b9.
-- Autor (user_profile) = fc900000-0000-0000-0000-000000000001.

-- ============================================================================
-- 1) Estrutura: sem campos especiais por cargo; catálogo; funções intactas
-- ============================================================================

do $$
declare
  v_n int;
begin
  -- Nenhuma tabela nova (F3-10 é validação; espera as 21 tabelas).
  select count(*) into v_n
  from pg_tables t
  where t.schemaname = 'public';
  if v_n <> 21 then
    raise exception '[FAIL] esperadas 21 tabelas no schema public (encontrado %)', v_n;
  end if;

  -- Sem colunas de rank/level/order/hierarchy nos catálogos e posições.
  select count(*) into v_n
  from information_schema.columns
  where table_schema = 'public'
    and table_name in ('job_roles', 'seniority_levels', 'organizational_positions')
    and column_name in ('rank', 'order', 'display_order', 'level', 'hierarchy', 'depth', 'sequence');
  if v_n <> 0 then
    raise exception '[FAIL] existe coluna de rank/level/order (campo especial por cargo)';
  end if;
  raise notice '[PASS] 21 tabelas e nenhum campo rank/level/order (sem campos especiais por cargo)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.job_roles
  where organization_id = 'fca00000-0000-0000-0000-0000000000a1'
    and name in ('Diretor','Gerente Senior','Gerente','Especialista','Coordenador','Consultor','Analista','Estagiario');
  if v_n <> 8 then
    raise exception '[FAIL] os oito conceitos do piloto deveriam existir no catalogo';
  end if;
  select count(*) into v_n
  from public.seniority_levels
  where organization_id = 'fca00000-0000-0000-0000-0000000000a1'
    and name in ('Junior','Pleno','Senior');
  if v_n <> 3 then
    raise exception '[FAIL] senioridades Junior/Pleno/Senior deveriam existir';
  end if;
  raise notice '[PASS] catalogo com 8 job_roles e 3 senioridades (sinteticos)';
end $$;

-- ============================================================================
-- 2) Materialização de snapshots (F3-08) e responsabilidades (F3-09)
-- ============================================================================

do $$
begin
  perform public.materializar_colegiado_ciclo(
    'fca00000-0000-0000-0000-0000000000a1', 2024, 1, '2024-03-01T00:00:00Z',
    array[
      'fcb00000-0000-0000-0000-0000000000c8',
      'fcb00000-0000-0000-0000-0000000000c9',
      'fcb00000-0000-0000-0000-0000000000ca',
      'fcb00000-0000-0000-0000-0000000000cb'
    ]::uuid[]
  );
  perform public.materializar_colegiado_ciclo(
    'fca00000-0000-0000-0000-0000000000a1', 2024, 2, '2024-08-01T00:00:00Z',
    array[
      'fcb00000-0000-0000-0000-0000000000c8',
      'fcb00000-0000-0000-0000-0000000000c9',
      'fcb00000-0000-0000-0000-0000000000ca',
      'fcb00000-0000-0000-0000-0000000000cb'
    ]::uuid[]
  );
  perform public.materializar_responsabilidades_avaliacao(
    'fca00000-0000-0000-0000-0000000000a1', 2024, 1
  );
  raise notice '[PASS] snapshots (ciclos 1 e 2) e responsabilidades materializados';
end $$;

-- ============================================================================
-- 3) Sucessão de avaliador (F3-09) — troca definitiva de ocupante C1 → C1_SUC
-- ============================================================================

do $$
declare
  v_ids uuid[];
begin
  select array_agg(cer.id order by cer.id) into v_ids
  from public.cycle_evaluation_responsibilities cer
  join public.collegiate_cycle_snapshots s on s.id = cer.snapshot_id
  where s.organization_id = 'fca00000-0000-0000-0000-0000000000a1'
    and s.ano = 2024 and s.ciclo = 1
    and cer.valid_to is null;

  perform public.registrar_sucessao_avaliador(
    v_ids, '2024-04-01T00:00:00Z', 'Troca definitiva de coordenador',
    'fc900000-0000-0000-0000-000000000001'
  );
  raise notice '[PASS] sucessao de avaliador registrada (C1 -> C1_SUC)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.evaluation_succession_events
  where organization_id = 'fca00000-0000-0000-0000-0000000000a1'
    and previous_responsible_collaborator_id = 'fcb00000-0000-0000-0000-0000000000c4'
    and new_responsible_collaborator_id = 'fcb00000-0000-0000-0000-0000000000c5'
    and succession_date = '2024-04-01T00:00:00Z'
    and author_user_profile_id = 'fc900000-0000-0000-0000-000000000001';
  if v_n <> 4 then
    raise exception '[FAIL] esperados 4 eventos de sucessao (encontrado %)', v_n;
  end if;
  raise notice '[PASS] 4 eventos de sucessao (original preservado, novo aberto)';
end $$;

-- ============================================================================
-- 4) Cenários estruturais (Issue #87)
-- ============================================================================

-- Cenário 1: Gerente com três Coordenadores.
do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.organizacao_resolver_subordinados_diretos(
    'fcb00000-0000-0000-0000-0000000000c3', '2024-02-01T00:00:00Z') sd
  join public.organizational_positions p on p.id = sd.subordinate_position_id
  join public.job_roles jr on jr.id = p.job_role_id
  where jr.name = 'Coordenador';
  if v_n <> 3 then
    raise exception '[FAIL] Gerente deveria ter 3 Coordenadores subordinados (encontrado %)', v_n;
  end if;
  raise notice '[PASS] cenario 1: Gerente com tres Coordenadores';
end $$;

-- Cenário 2: Consultor respondendo diretamente ao Gerente.
do $$
declare
  v_mgr uuid;
begin
  select manager_responsible_collaborator_id into v_mgr
  from public.organizacao_resolver_gestor_direto(
    'fcb00000-0000-0000-0000-0000000000cc', '2024-02-01T00:00:00Z')
  limit 1;
  if v_mgr is distinct from 'fcb00000-0000-0000-0000-0000000000c3' then
    raise exception '[FAIL] Consultor deveria responder diretamente ao Gerente';
  end if;
  raise notice '[PASS] cenario 2: Consultor responde diretamente ao Gerente';
end $$;

-- Cenário 3 + Refinamento 1: Analistas Jr/Pl/Sr sob o mesmo Coordenador,
-- com exatamente a mesma relação hierárquica (seniority não altera nada).
do $$
declare
  v_jr uuid; v_pl uuid; v_sr uuid;
  v_n int;
  v_depth integer[];
begin
  select manager_responsible_collaborator_id into v_jr
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000c8', '2024-02-01T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000a7';
  select manager_responsible_collaborator_id into v_pl
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000c9', '2024-02-01T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000a8';
  select manager_responsible_collaborator_id into v_sr
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000ca', '2024-02-01T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000a9';

  if v_jr is distinct from 'fcb00000-0000-0000-0000-0000000000c4'
     or v_pl is distinct from 'fcb00000-0000-0000-0000-0000000000c4'
     or v_sr is distinct from 'fcb00000-0000-0000-0000-0000000000c4' then
    raise exception '[FAIL] Jr/Pl/Sr deveriam ter o mesmo gestor direto (C1)';
  end if;

  -- Mesma reporting line (mesma posição superior P_COORD1).
  select count(*) into v_n
  from public.position_reporting_lines
  where subordinate_position_id in ('fcc00000-0000-0000-0000-0000000000a7',
                                    'fcc00000-0000-0000-0000-0000000000a8',
                                    'fcc00000-0000-0000-0000-0000000000a9')
    and manager_position_id = 'fcc00000-0000-0000-0000-0000000000a4'
    and valid_from <= '2024-02-01T00:00:00Z'
    and (valid_to is null or valid_to > '2024-02-01T00:00:00Z');
  if v_n <> 3 then
    raise exception '[FAIL] Jr/Pl/Sr deveriam reportar a mesma posicao superior (P_COORD1)';
  end if;

  -- Mesma profundidade (1) sob o Coordenador.
  select array_agg(depth order by depth) into v_depth
  from public.organizacao_resolver_descendentes('fcb00000-0000-0000-0000-0000000000c4', '2024-02-01T00:00:00Z')
  where position_id in ('fcc00000-0000-0000-0000-0000000000a7',
                        'fcc00000-0000-0000-0000-0000000000a8',
                        'fcc00000-0000-0000-0000-0000000000a9');
  if v_depth is distinct from array[1, 1, 1] then
    raise exception '[FAIL] Jr/Pl/Sr deveriam ter a mesma profundidade (1) sob o Coordenador';
  end if;
  raise notice '[PASS] cenario 3 + refinamento 1: Analistas Jr/Pl/Sr com a mesma relacao hierarquica (seniority nao altera gestor/reporting/profundidade)';
end $$;

-- Cenário 4: Estagiário sob Coordenador E sob Gerente (sem seniority).
do $$
declare
  v_mgr uuid;
  v_n int;
begin
  select manager_responsible_collaborator_id into v_mgr
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000cb', '2024-02-01T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000aa';
  if v_mgr is distinct from 'fcb00000-0000-0000-0000-0000000000c4' then
    raise exception '[FAIL] Estagiario 1 deveria estar sob o Coordenador';
  end if;

  select manager_responsible_collaborator_id into v_mgr
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000d0', '2024-02-01T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000b1';
  if v_mgr is distinct from 'fcb00000-0000-0000-0000-0000000000cd' then
    raise exception '[FAIL] Estagiario da Gerencia 2 deveria estar sob o Gerente';
  end if;

  -- Estagiário sem seniority.
  select count(*) into v_n
  from public.organizational_positions
  where id in ('fcc00000-0000-0000-0000-0000000000aa', 'fcc00000-0000-0000-0000-0000000000b1')
    and seniority_level_id is not null;
  if v_n <> 0 then
    raise exception '[FAIL] Estagiario nao deveria exigir seniority';
  end if;
  raise notice '[PASS] cenario 4: Estagiario sob Coordenador e sob Gerente (sem seniority)';
end $$;

-- Cenário 5: gerência menor sem Coordenador (Analista/Consultor/Estagiário → Gerente).
do $$
declare
  v_n int;
  v_pos uuid[];
begin
  select count(*), array_agg(subordinate_position_id order by subordinate_position_id) into v_n, v_pos
  from public.organizacao_resolver_subordinados_diretos('fcb00000-0000-0000-0000-0000000000cd', '2024-02-01T00:00:00Z');
  if v_n <> 3 then
    raise exception '[FAIL] Gerencia 2 deveria ter 3 subordinados diretos (encontrado %)', v_n;
  end if;
  if v_pos is distinct from
     array['fcc00000-0000-0000-0000-0000000000af',
           'fcc00000-0000-0000-0000-0000000000b0',
           'fcc00000-0000-0000-0000-0000000000b1']::uuid[] then
    raise exception '[FAIL] subordinados da Gerencia 2 deveriam ser Analista/Consultor/Estagiario';
  end if;
  raise notice '[PASS] cenario 5: gerencia menor sem Coordenador (3 subordinados diretos ao Gerente)';
end $$;

-- Cenário 6 + Refinamento 2: Especialista no mesmo patamar do Gerente.
do $$
declare
  v_sup uuid;
  v_n int;
begin
  -- Mesmo superior formal que o Gerente (P_DIR_AREA).
  select manager_position_id into v_sup
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000d1', '2024-02-01T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000b2';
  if v_sup is distinct from 'fcc00000-0000-0000-0000-0000000000a2' then
    raise exception '[FAIL] Especialista deveria reportar ao mesmo superior do Gerente (P_DIR_AREA)';
  end if;

  -- O Gerente (G1) reporta ao MESMO superior (P_DIR_AREA).
  select manager_position_id into v_sup
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000c3', '2024-02-01T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000a3';
  if v_sup is distinct from 'fcc00000-0000-0000-0000-0000000000a2' then
    raise exception '[FAIL] Gerente deveria reportar ao mesmo superior do Especialista (P_DIR_AREA)';
  end if;

  -- Zero subordinados diretos.
  select count(*) into v_n
  from public.organizacao_resolver_subordinados_diretos('fcb00000-0000-0000-0000-0000000000d1', '2024-02-01T00:00:00Z');
  if v_n <> 0 then
    raise exception '[FAIL] Especialista deveria ter zero subordinados';
  end if;
  raise notice '[PASS] cenario 6 + refinamento 2: Especialista no mesmo patamar do Gerente (mesmo superior, zero subordinados, sem rank/level/order)';
end $$;

-- Cenário 7: posição vaga.
do $$
declare
  v_n int;
  v_resp uuid;
begin
  select count(*) into v_n
  from public.occupations
  where organizational_position_id = 'fcc00000-0000-0000-0000-0000000000ac'
    and valid_from <= '2024-02-01T00:00:00Z'
    and (valid_to is null or valid_to > '2024-02-01T00:00:00Z');
  if v_n <> 0 then
    raise exception '[FAIL] P_VACANTE nao deveria ter occupation vigente';
  end if;

  select responsible_collaborator_id into v_resp
  from public.organizacao_resolver_responsavel_posicao('fcc00000-0000-0000-0000-0000000000ac', '2024-02-01T00:00:00Z');
  if v_resp is not null then
    raise exception '[FAIL] posicao vaga deveria resolver responsavel NULL';
  end if;
  raise notice '[PASS] cenario 7: posicao vaga (sem occupation; responsavel NULL)';
end $$;

-- Cenário 8: troca definitiva de ocupante (C1 → C1_SUC na mesma posição).
do $$
declare
  v_n int;
  v_old uuid; v_new uuid;
begin
  select count(*) into v_n
  from public.occupations
  where organizational_position_id = 'fcc00000-0000-0000-0000-0000000000a4';
  if v_n <> 2 then
    raise exception '[FAIL] P_COORD1 deveria ter 2 occupations (historico de troca)';
  end if;

  select collaborator_id into v_old
  from public.occupations
  where organizational_position_id = 'fcc00000-0000-0000-0000-0000000000a4' and valid_to is not null;
  select collaborator_id into v_new
  from public.occupations
  where organizational_position_id = 'fcc00000-0000-0000-0000-0000000000a4' and valid_to is null;
  if v_old is distinct from 'fcb00000-0000-0000-0000-0000000000c4'
     or v_new is distinct from 'fcb00000-0000-0000-0000-0000000000c5' then
    raise exception '[FAIL] troca definitiva deveria preservar C1 (fechado) e abrir C1_SUC';
  end if;
  raise notice '[PASS] cenario 8: troca definitiva de ocupante preserva historico (close+open)';
end $$;

-- Cenário 9: transferência entre coordenações (AJR move de C1 para C2).
do $$
declare
  v_mgr uuid;
  v_n int;
begin
  select manager_responsible_collaborator_id into v_mgr
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000c8', '2024-07-15T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000ad';
  if v_mgr is distinct from 'fcb00000-0000-0000-0000-0000000000c6' then
    raise exception '[FAIL] apos transferencia, AJR deveria responder ao Coordenador 2 (C2)';
  end if;

  select count(*) into v_n
  from public.occupations
  where collaborator_id = 'fcb00000-0000-0000-0000-0000000000c8'
    and organizational_position_id = 'fcc00000-0000-0000-0000-0000000000a7'
    and valid_to is not null;
  if v_n <> 1 then
    raise exception '[FAIL] occupation anterior de AJR (P_AN_JR) deveria estar fechada';
  end if;
  raise notice '[PASS] cenario 9: transferencia entre coordenacoes (historico preservado)';
end $$;

-- Cenário 10: licença mantendo occupation.
do $$
declare
  v_status text;
  v_resp uuid;
begin
  select status into v_status
  from public.collaborator_status_periods
  where collaborator_id = 'fcb00000-0000-0000-0000-0000000000ca'
    and valid_from <= '2024-09-15T00:00:00Z'
    and (valid_to is null or valid_to > '2024-09-15T00:00:00Z');
  if v_status <> 'leave' then
    raise exception '[FAIL] ASR deveria estar em licenca em 2024-09-15';
  end if;

  select responsible_collaborator_id into v_resp
  from public.organizacao_resolver_responsavel_posicao('fcc00000-0000-0000-0000-0000000000a9', '2024-09-15T00:00:00Z');
  if v_resp is distinct from 'fcb00000-0000-0000-0000-0000000000ca' then
    raise exception '[FAIL] licenca nao deveria encerrar a occupation (ASR continua responsavel)';
  end if;
  raise notice '[PASS] cenario 10: licenca mantem occupation';
end $$;

-- Cenário 11: substituição temporária.
do $$
begin
  insert into public.temporary_responsibilities (
    organization_id, organizational_position_id, substitute_collaborator_id,
    responsibility_type, reason, valid_from, valid_to
  ) values (
    'fca00000-0000-0000-0000-0000000000a1',
    'fcc00000-0000-0000-0000-0000000000a3',
    'fcb00000-0000-0000-0000-0000000000d3',
    'operational_evaluative',
    'Substituicao temporaria do Gerente', '2024-09-01T00:00:00Z', '2024-11-01T00:00:00Z'
  );
  raise notice '[PASS] cenario 11: substituicao temporaria registrada';
end $$;

do $$
declare
  v_sub uuid; v_resp uuid;
begin
  select substitute_collaborator_id, responsible_collaborator_id into v_sub, v_resp
  from public.organizacao_resolver_responsavel_posicao('fcc00000-0000-0000-0000-0000000000a3', '2024-09-15T00:00:00Z');
  if v_sub is distinct from 'fcb00000-0000-0000-0000-0000000000d3'
     or v_resp is distinct from 'fcb00000-0000-0000-0000-0000000000d3' then
    raise exception '[FAIL] substituto deveria assumir P_GER1 durante o periodo';
  end if;

  select substitute_collaborator_id, responsible_collaborator_id into v_sub, v_resp
  from public.organizacao_resolver_responsavel_posicao('fcc00000-0000-0000-0000-0000000000a3', '2024-12-01T00:00:00Z');
  if v_sub is not null or v_resp is distinct from 'fcb00000-0000-0000-0000-0000000000c3' then
    raise exception '[FAIL] apos o periodo, o titular (G1) deveria reassumir';
  end if;
  raise notice '[PASS] cenario 11: substituto assume no periodo e titular reassume no retorno';
end $$;

-- Cenário 12: pessoa ocupando duas posições simultâneas.
do $$
declare
  v_n int;
  v_pos uuid[];
begin
  select count(*), array_agg(occupied_position_id order by occupied_position_id) into v_n, v_pos
  from public.organizacao_resolver_avaliador_avaliado('fcb00000-0000-0000-0000-0000000000d2', '2024-02-01T00:00:00Z');
  if v_n <> 2 then
    raise exception '[FAIL] DUP deveria ocupar 2 posicoes (encontrado %)', v_n;
  end if;
  if v_pos is distinct from
     array['fcc00000-0000-0000-0000-0000000000b3',
           'fcc00000-0000-0000-0000-0000000000b4']::uuid[] then
    raise exception '[FAIL] DUP deveria ocupar P_DUP_A e P_DUP_B';
  end if;
  raise notice '[PASS] cenario 12: pessoa com duas posicoes simultaneas (2 linhas)';
end $$;

-- Cenário 13: Diretor reportando a Diretor (nível repetido).
do $$
declare
  v_mgr_pos uuid;
  v_n int;
begin
  select manager_position_id into v_mgr_pos
  from public.position_reporting_lines
  where subordinate_position_id = 'fcc00000-0000-0000-0000-0000000000a2'
    and valid_from <= '2024-02-01T00:00:00Z'
    and (valid_to is null or valid_to > '2024-02-01T00:00:00Z');
  if v_mgr_pos is distinct from 'fcc00000-0000-0000-0000-0000000000a1' then
    raise exception '[FAIL] P_DIR_AREA deveria reportar a P_DIR_EXEC';
  end if;

  -- Ambos com o mesmo job_role 'Diretor'.
  select count(*) into v_n
  from public.organizational_positions p
  join public.job_roles jr on jr.id = p.job_role_id
  where p.id in ('fcc00000-0000-0000-0000-0000000000a1', 'fcc00000-0000-0000-0000-0000000000a2')
    and jr.name = 'Diretor';
  if v_n <> 2 then
    raise exception '[FAIL] Diretor -> Diretor deveria usar o mesmo job_role em alturas diferentes';
  end if;
  raise notice '[PASS] cenario 13: Diretor reportando a Diretor (nivel repetido)';
end $$;

-- Cenário 14: colegiado ausente / vazio / com membros + histórico por ciclo.
do $$
declare
  v_members uuid[];
  v_snap uuid;
  v_n int;
begin
  -- Ciclo 1 (ref 2024-03-01): AJR = {M1, M2} (v1).
  select id into v_snap
  from public.collegiate_cycle_snapshots
  where organization_id = 'fca00000-0000-0000-0000-0000000000a1'
    and ano = 2024 and ciclo = 1
    and collaborator_id = 'fcb00000-0000-0000-0000-0000000000c8';
  select array_agg(member_collaborator_id order by member_collaborator_id) into v_members
  from public.collegiate_cycle_snapshot_members where snapshot_id = v_snap;
  if v_members is distinct from
     array['fcb00000-0000-0000-0000-0000000000d4',
           'fcb00000-0000-0000-0000-0000000000d5']::uuid[] then
    raise exception '[FAIL] ciclo 1 de AJR deveria congelar {M1, M2}';
  end if;

  -- Colegiado ausente (APL) e vazio (ASR) → 0 membros no snapshot.
  select count(*) into v_n
  from public.collegiate_cycle_snapshot_members sm
  join public.collegiate_cycle_snapshots s on s.id = sm.snapshot_id
  where s.ano = 2024 and s.ciclo = 1
    and s.collaborator_id in ('fcb00000-0000-0000-0000-0000000000c9', 'fcb00000-0000-0000-0000-0000000000ca');
  if v_n <> 0 then
    raise exception '[FAIL] colegiado ausente/vazio deveria ter 0 membros no snapshot';
  end if;

  -- Ciclo 2 (ref 2024-08-01): AJR = {M1} (v2) — composição histórica.
  select id into v_snap
  from public.collegiate_cycle_snapshots
  where organization_id = 'fca00000-0000-0000-0000-0000000000a1'
    and ano = 2024 and ciclo = 2
    and collaborator_id = 'fcb00000-0000-0000-0000-0000000000c8';
  select array_agg(member_collaborator_id order by member_collaborator_id) into v_members
  from public.collegiate_cycle_snapshot_members where snapshot_id = v_snap;
  if v_members is distinct from array['fcb00000-0000-0000-0000-0000000000d4']::uuid[] then
    raise exception '[FAIL] ciclo 2 de AJR deveria congelar {M1} (v2)';
  end if;
  raise notice '[PASS] cenario 14: colegiado ausente/vazio/com membros e historico por ciclo (ciclo1 {M1,M2}, ciclo2 {M1})';
end $$;

-- ============================================================================
-- 5) Reconstrução histórica por data (>= 5 datas)
-- ============================================================================

-- 2024-02-01 (base).
do $$
declare
  v_resp uuid;
begin
  select responsible_collaborator_id into v_resp
  from public.organizacao_resolver_responsavel_posicao('fcc00000-0000-0000-0000-0000000000a4', '2024-02-01T00:00:00Z');
  if v_resp is distinct from 'fcb00000-0000-0000-0000-0000000000c4' then
    raise exception '[FAIL] 2024-02-01: P_COORD1 deveria estar com C1';
  end if;
  raise notice '[PASS] reconstrucao 2024-02-01: C1 titular de P_COORD1 (base)';
end $$;

-- 2024-05-01 (após troca definitiva).
do $$
declare
  v_resp uuid;
begin
  select responsible_collaborator_id into v_resp
  from public.organizacao_resolver_responsavel_posicao('fcc00000-0000-0000-0000-0000000000a4', '2024-05-01T00:00:00Z');
  if v_resp is distinct from 'fcb00000-0000-0000-0000-0000000000c5' then
    raise exception '[FAIL] 2024-05-01: P_COORD1 deveria estar com C1_SUC';
  end if;
  raise notice '[PASS] reconstrucao 2024-05-01: C1_SUC titular apos troca definitiva';
end $$;

-- 2024-07-15 (após transferência + reporting change).
do $$
declare
  v_mgr uuid;
begin
  select manager_responsible_collaborator_id into v_mgr
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000c7', '2024-07-15T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000a6';
  if v_mgr is distinct from 'fcb00000-0000-0000-0000-0000000000cd' then
    raise exception '[FAIL] 2024-07-15: Coordenador 3 deveria reportar ao Gerente 2 (reporting line movida)';
  end if;
  raise notice '[PASS] reconstrucao 2024-07-15: reporting line movida (P_COORD3 sob G2)';
end $$;

-- 2024-09-15 (durante licença + substituição).
do $$
declare
  v_status text;
  v_resp uuid;
begin
  select status into v_status
  from public.collaborator_status_periods
  where collaborator_id = 'fcb00000-0000-0000-0000-0000000000ca'
    and valid_from <= '2024-09-15T00:00:00Z'
    and (valid_to is null or valid_to > '2024-09-15T00:00:00Z');
  if v_status <> 'leave' then
    raise exception '[FAIL] 2024-09-15: ASR deveria estar em licenca';
  end if;

  select responsible_collaborator_id into v_resp
  from public.organizacao_resolver_responsavel_posicao('fcc00000-0000-0000-0000-0000000000a3', '2024-09-15T00:00:00Z');
  if v_resp is distinct from 'fcb00000-0000-0000-0000-0000000000d3' then
    raise exception '[FAIL] 2024-09-15: P_GER1 deveria estar com o substituto';
  end if;
  raise notice '[PASS] reconstrucao 2024-09-15: licenca (ASR) e substituto (P_GER1) vigentes';
end $$;

-- 2024-12-01 (após tudo).
do $$
declare
  v_status text;
  v_resp uuid;
  v_mgr uuid;
begin
  select status into v_status
  from public.collaborator_status_periods
  where collaborator_id = 'fcb00000-0000-0000-0000-0000000000ca'
    and valid_from <= '2024-12-01T00:00:00Z'
    and (valid_to is null or valid_to > '2024-12-01T00:00:00Z');
  if v_status <> 'active' then
    raise exception '[FAIL] 2024-12-01: ASR deveria ter retornado ao status active';
  end if;

  select responsible_collaborator_id into v_resp
  from public.organizacao_resolver_responsavel_posicao('fcc00000-0000-0000-0000-0000000000a3', '2024-12-01T00:00:00Z');
  if v_resp is distinct from 'fcb00000-0000-0000-0000-0000000000c3' then
    raise exception '[FAIL] 2024-12-01: G1 deveria ter reassumido P_GER1';
  end if;

  select manager_responsible_collaborator_id into v_mgr
  from public.organizacao_resolver_gestor_direto('fcb00000-0000-0000-0000-0000000000c8', '2024-12-01T00:00:00Z')
  where occupied_position_id = 'fcc00000-0000-0000-0000-0000000000ad';
  if v_mgr is distinct from 'fcb00000-0000-0000-0000-0000000000c6' then
    raise exception '[FAIL] 2024-12-01: AJR deveria permanecer sob C2 apos transferencia';
  end if;
  raise notice '[PASS] reconstrucao 2024-12-01: licenca encerrada, titular reassumido, transferencia mantida';
end $$;

-- ============================================================================
-- 6) RLS deny-by-default (sem alterar policies)
-- ============================================================================

set role authenticated;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.collaborators;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou collaborators';
  end if;
  select count(*) into v_n from public.occupations;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou occupations';
  end if;
  select count(*) into v_n from public.cycle_evaluation_responsibilities;
  if v_n <> 0 then
    raise exception '[FAIL] authenticated enxergou cycle_evaluation_responsibilities';
  end if;
  raise notice '[PASS] RLS: authenticated nao le tabelas de dominio (deny-by-default)';
end $$;

do $$
begin
  begin
    insert into public.occupations (
      organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
    ) values (
      'fca00000-0000-0000-0000-0000000000a1',
      'fcb00000-0000-0000-0000-0000000000c3',
      'fcc00000-0000-0000-0000-0000000000ac',
      'tentativa', '2027-01-01T00:00:00Z', null
    );
    raise exception '[FAIL] RLS permitiu INSERT de authenticated em occupations';
  exception when insufficient_privilege then
    null;
  end;
  raise notice '[PASS] RLS: INSERT de authenticated negado em occupations';
end $$;

reset role;

-- ============================================================================
-- 7) F3-01..F3-09 permanecem intactas
-- ============================================================================

do $$
declare
  v_n int;
begin
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
                      'organizacao_resolver_escopo_unidades',
                      'materializar_colegiado_ciclo',
                      'materializar_responsabilidades_avaliacao',
                      'registrar_sucessao_avaliador',
                      'resolver_responsavel_avaliacao_vigente');
  if v_n <> 11 then
    raise exception '[FAIL] funcoes F3-07..F3-09 deveriam permanecer (encontrado %)', v_n;
  end if;

  select count(*) into v_n
  from pg_policies p
  where p.schemaname = 'public';
  if v_n <> 3 then
    raise exception '[FAIL] quantidade de policies alterada (esperado 3, encontrado %)', v_n;
  end if;
  raise notice '[PASS] F3-07..F3-09 (funcoes) e policies de identidade intactas';
end $$;

-- ============================================================================
-- 8) Limpeza do cenário sintético (banco local limpo)
-- ============================================================================

delete from public.evaluation_succession_events
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.cycle_evaluation_responsibilities
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_members
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshot_positions
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.collegiate_cycle_snapshots
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configuration_members
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.collegiate_configurations
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.temporary_responsibilities
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.occupations
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.collaborator_status_periods
where collaborator_id::text like 'fcb00000-0000-0000-0000-0000000000%';

delete from public.collaborator_identifiers
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.position_reporting_lines
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.organizational_positions
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.organizational_units
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.collaborators
where id::text like 'fcb00000-0000-0000-0000-0000000000%';

delete from public.seniority_levels
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.organizations
where id::text like 'fca00000-0000-0000-0000-0000000000%';

delete from public.user_profiles
where id = 'fc900000-0000-0000-0000-000000000001';

delete from auth.users
where id = 'fc900000-0000-0000-0000-000000000001';

do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.organizations
  where id::text like 'fca00000-0000-0000-0000-0000000000%';
  if v_n <> 0 then
    raise exception '[FAIL] limpeza do cenario F3-10 incompleta';
  end if;
  raise notice '[PASS] cenario sintetico F3-10 removido ao final (banco local limpo)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F3-10: todas as verificacoes passaram (14 cenarios + reconstrucao + RLS).';
end $$;
