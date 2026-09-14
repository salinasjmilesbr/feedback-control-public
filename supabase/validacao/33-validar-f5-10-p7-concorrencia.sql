-- ============================================================================
-- F5-10 P7 (Issue #232): CONCORRENCIA REAL entre DUAS sessoes PostgreSQL
-- CONSOLIDACAO (terceiro processo psql; roda SOMENTE depois de A e B terminarem)
-- ----------------------------------------------------------------------------
-- Papel desta sessao (processo psql 3 de 3): provar, no estado CONSOLIDADO e em
-- UMA unica sessao, que
--   (1) o estado final de Gama-P7 e o das intencoes VENCEDORAS (sessao A) mais a
--       contraparte POSITIVA de papeis distintos (sessao B) — nenhum lost update;
--   (2) NENHUMA intencao PERDEDORA da sessao B deixou fato ou evento;
--   (3) os DOIS fatos de aprovacao coexistem, com UM vigente por papel;
--   (4) os artefatos TEMPORARIOS da prova existiam de fato e sao REMOVIDOS, sem
--       residuo no schema (higiene).
--
-- A prova de CONTENCAO (o bloqueio medido) vive no stdout da sessao B (arquivo 32):
-- a tentativa perdedora NAO deixa estado. Aqui se prova o estado consolidado e a
-- AUSENCIA de qualquer efeito dela. Os dois artefatos sao registrados juntos em
-- docs/F5-10-p7-matriz-integrada.md.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Os artefatos temporarios da prova EXISTIRAM (o mecanismo de contencao rodou)
-- ----------------------------------------------------------------------------
do $$
declare
  v_n int;
begin
  if to_regclass('public._mut_p7_seq_edit') is null then
    raise exception '[FAIL] consolidacao: a sequence de contencao da EDICAO nao existe — a prova de concorrencia nao chegou a rodar (execute 31 em BACKGROUND e 32 em FOREGROUND)';
  end if;
  if to_regclass('public._mut_p7_seq_apr') is null then
    raise exception '[FAIL] consolidacao: a sequence de contencao da APROVACAO nao existe — a FASE 2 da corrida nao rodou';
  end if;
  -- As duas marcas foram consumidas exatamente uma vez: prova de que A entrou na
  -- janela de contencao UMA vez por fase (e nao repetiu a escrita).
  select s.last_value into v_n from public._mut_p7_seq_edit s;
  if v_n <> 1 then
    raise exception '[FAIL] consolidacao: a marca da EDICAO foi consumida % vez(es) (esperado exatamente 1: uma unica escrita vencedora)', v_n;
  end if;
  select s.last_value into v_n from public._mut_p7_seq_apr s;
  if v_n <> 1 then
    raise exception '[FAIL] consolidacao: a marca da APROVACAO foi consumida % vez(es) (esperado exatamente 1)', v_n;
  end if;
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.evaluation_goals'::regclass
                    and t.tgname = '_mut_p7_contencao_edicao' and not t.tgisinternal) then
    raise exception '[FAIL] consolidacao: o gatilho temporario da EDICAO nao existe';
  end if;
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.evaluation_goal_approvals'::regclass
                    and t.tgname = '_mut_p7_contencao_aprovacao' and not t.tgisinternal) then
    raise exception '[FAIL] consolidacao: o gatilho temporario da APROVACAO nao existe';
  end if;

  raise notice '[PASS] consolidacao: os 2 artefatos temporarios de contencao existem e cada marca foi consumida EXATAMENTE 1 vez (uma escrita vencedora por fase)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) Estado consolidado das DUAS metas da corrida
-- ----------------------------------------------------------------------------
do $$
declare
  v_gama   uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_cg     uuid := 'e8d10000-0000-0000-0000-0000000000c1';
  v_dono   uuid := 'e8b00000-0000-0000-0000-0000000000a1';
  v_ger    uuid := 'e8c00000-0000-0000-0000-0000000000a2';
  v_coo    uuid := 'e8c00000-0000-0000-0000-0000000000a3';
  v_edit   uuid;
  v_apr    uuid;
  v_row    record;
  v_n      int;
begin
  select g.id into v_edit from public.evaluation_goals g
   where g.organization_id = v_gama and g.cycle_id = v_cg
     and g.collaborator_id = v_dono and g.tipo = 'NEGOCIO_PROJETO';
  select g.id into v_apr from public.evaluation_goals g
   where g.organization_id = v_gama and g.cycle_id = v_cg
     and g.collaborator_id = v_dono and g.tipo = 'INDIVIDUAL';
  if v_edit is null or v_apr is null then
    raise exception '[FAIL] consolidacao: as 2 metas da corrida nao foram resolvidas';
  end if;

  -- --- meta da EDICAO: o estado final e o de A (nenhum lost update) ----------
  select g.descricao, g.kpi, g.valor_alvo, g.version, g.status, g.excluida
    into v_row from public.evaluation_goals g where g.id = v_edit;
  if v_row.descricao <> 'Descricao VENCEDORA da corrida de edicao (P7)'
     or v_row.kpi <> 'KPI VENCEDOR da corrida de edicao (P7)'
     or v_row.valor_alvo <> '111 unidades (P7)'
     or v_row.version <> 1 or v_row.status <> 'EM_ANDAMENTO' or v_row.excluida then
    raise exception '[FAIL] consolidacao/EDICAO: LOST UPDATE ou estado divergente — a meta deveria manter integralmente a intencao de A (descricao=%, kpi=%, alvo=%, version=%, status=%, excluida=%)',
      v_row.descricao, v_row.kpi, v_row.valor_alvo, v_row.version, v_row.status, v_row.excluida;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_edit;
  if v_n <> 2 then
    raise exception '[FAIL] consolidacao/EDICAO: esperados 2 eventos (CRIADA + EDITADA), encontrados %', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_edit
     and e.event_type = 'CRIADA' and e.operation_id = 'e8a10000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] consolidacao/EDICAO: evento CRIADA da intencao de A (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_edit
     and e.event_type = 'EDITADA' and e.operation_id = 'e8a10000-0000-0000-0000-0000000000a3'
     and e.actor_user_profile_id = 'e8c00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] consolidacao/EDICAO: evento EDITADA da intencao VENCEDORA de A com autoria soberana (%)', v_n;
  end if;
  -- Nenhum vestigio da intencao perdedora.
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama
     and e.operation_id = 'e8b10000-0000-0000-0000-0000000000b1';
  if v_n <> 0 then
    raise exception '[FAIL] consolidacao/EDICAO: a intencao PERDEDORA de B deixou evento na trilha (%)', v_n;
  end if;

  -- --- meta da APROVACAO: version da meta INTACTA + 2 fatos coexistentes -----
  select g.version, g.status, g.excluida into v_row
    from public.evaluation_goals g where g.id = v_apr;
  if v_row.version <> 0 or v_row.status <> 'EM_ANDAMENTO' or v_row.excluida then
    raise exception '[FAIL] consolidacao/APROVACAO: aprovacao NAO pode alterar a meta (version=%, status=%, excluida=%)',
      v_row.version, v_row.status, v_row.excluida;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_apr;
  if v_n <> 2 then
    raise exception '[FAIL] consolidacao/APROVACAO: esperados exatamente 2 FATOS (GERENTE + COORDENADOR), encontrados %', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_apr and a.revogado_em is null;
  if v_n <> 2 then
    raise exception '[FAIL] consolidacao/APROVACAO: os 2 fatos deveriam estar VIGENTES (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_apr
     and a.papel = 'GERENTE' and a.revogado_em is null
     and a.actor_user_profile_id = v_ger;
  if v_n <> 1 then
    raise exception '[FAIL] consolidacao/APROVACAO: o fato de A (GERENTE, autoria do gerente congelado) deveria estar vigente (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_gama and a.goal_id = v_apr
     and a.papel = 'COORDENADOR' and a.revogado_em is null
     and a.actor_user_profile_id = v_coo;
  if v_n <> 1 then
    raise exception '[FAIL] consolidacao/APROVACAO: o fato da contraparte (COORDENADOR congelado) deveria estar vigente (%)', v_n;
  end if;
  -- Um vigente por papel (invariante do contrato).
  select count(*) into v_n from (
    select a.papel from public.evaluation_goal_approvals a
     where a.organization_id = v_gama and a.goal_id = v_apr and a.revogado_em is null
     group by a.papel having count(*) > 1) t;
  if v_n <> 0 then
    raise exception '[FAIL] consolidacao/APROVACAO: mais de uma aprovacao vigente para o mesmo papel (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_apr;
  if v_n <> 3 then
    raise exception '[FAIL] consolidacao/APROVACAO: esperados 3 eventos (CRIADA + APROVACAO_GERENTE + APROVACAO_COORDENADOR), encontrados %', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_apr
     and e.event_type = 'APROVACAO_GERENTE'
     and e.operation_id = 'e8a10000-0000-0000-0000-0000000000a4';
  if v_n <> 1 then
    raise exception '[FAIL] consolidacao/APROVACAO: evento APROVACAO_GERENTE da intencao VENCEDORA (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama and e.goal_id = v_apr
     and e.event_type = 'APROVACAO_COORDENADOR'
     and e.operation_id = 'e8b10000-0000-0000-0000-0000000000b3';
  if v_n <> 1 then
    raise exception '[FAIL] consolidacao/APROVACAO: evento APROVACAO_COORDENADOR da contraparte positiva (%)', v_n;
  end if;
  -- Nenhum vestigio da intencao perdedora (MESMO papel).
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama
     and e.operation_id = 'e8b10000-0000-0000-0000-0000000000b2';
  if v_n <> 0 then
    raise exception '[FAIL] consolidacao/APROVACAO: a intencao PERDEDORA de B deixou evento na trilha (%)', v_n;
  end if;

  -- --- trilha total de Gama-P7 -------------------------------------------------
  select count(*) into v_n from public.evaluation_goal_events where organization_id = v_gama;
  if v_n <> 5 then
    raise exception '[FAIL] consolidacao: esperados 5 eventos em Gama-P7 (2 CRIADA + 1 EDITADA + 2 APROVACAO), encontrados %', v_n;
  end if;
  select count(*) into v_n from (
    select e.operation_id from public.evaluation_goal_events e
     where e.organization_id = v_gama
     group by e.operation_id having count(*) > 1) t;
  if v_n <> 0 then
    raise exception '[FAIL] consolidacao: operation_id duplicado na trilha da corrida (%)', v_n;
  end if;
  -- Autoria soberana em toda a trilha (resolvida no banco).
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_gama
     and (e.actor_user_profile_id is null or e.actor_membership_id is null or e.payload_hash !~ '^[0-9a-f]{64}$');
  if v_n <> 0 then
    raise exception '[FAIL] consolidacao: % evento(s) sem autoria soberana/payload_hash canonico', v_n;
  end if;

  raise notice '[PASS] consolidacao: estado final = intencoes VENCEDORAS de A + contraparte positiva de papeis distintos — EDICAO em version 1 com a descricao de A (nenhum lost update), APROVACAO com a version da meta INTACTA e 2 fatos vigentes (1 por papel, autorias congeladas), 5 eventos com autoria soberana e operation_id unico, ZERO efeito das 2 intencoes perdedoras';
end $$;

-- ----------------------------------------------------------------------------
-- 2) HIGIENE: remocao dos artefatos temporarios e ausencia de residuo
-- ----------------------------------------------------------------------------
drop trigger if exists _mut_p7_contencao_edicao on public.evaluation_goals;
drop function if exists public._mut_p7_contencao_edicao_fn();
drop sequence if exists public._mut_p7_seq_edit;
drop trigger if exists _mut_p7_contencao_aprovacao on public.evaluation_goal_approvals;
drop function if exists public._mut_p7_contencao_aprovacao_fn();
drop sequence if exists public._mut_p7_seq_apr;

do $$
declare
  v_n int;
begin
  if to_regclass('public._mut_p7_seq_edit') is not null
     or to_regclass('public._mut_p7_seq_apr') is not null then
    raise exception '[FAIL] higiene: sequence temporaria de contencao NAO foi removida';
  end if;
  if to_regprocedure('public._mut_p7_contencao_edicao_fn()') is not null
     or to_regprocedure('public._mut_p7_contencao_aprovacao_fn()') is not null then
    raise exception '[FAIL] higiene: funcao temporaria de contencao NAO foi removida';
  end if;
  select count(*) into v_n from pg_trigger t
   where t.tgname in ('_mut_p7_contencao_edicao', '_mut_p7_contencao_aprovacao')
     and not t.tgisinternal;
  if v_n <> 0 then
    raise exception '[FAIL] higiene: gatilho temporario de contencao NAO foi removido (%)', v_n;
  end if;
  -- Nenhum residuo `_mut_%` de qualquer prova (a mesma convencao das fases P4/P9).
  select count(*) into v_n from pg_trigger t where t.tgname like '\_mut\_%' and not t.tgisinternal;
  if v_n <> 0 then
    raise exception '[FAIL] higiene: % gatilho(s) `_mut_%%` residual(is) no schema', v_n;
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] higiene: % funcao(oes) `_mut_%%` residual(is) no schema', v_n;
  end if;
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'S' and c.relname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] higiene: % sequence(s) `_mut_%%` residual(is) no schema', v_n;
  end if;

  raise notice '[PASS] higiene: os 2 gatilhos, as 2 funcoes e as 2 sequences temporarias de contencao foram REMOVIDOS; nenhum residuo `_mut_*` no schema';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-10 P7: CONCORRENCIA REAL (bloco 6) — provada entre DOIS backends PostgreSQL reais, em duas fases, com o lock normativo `evaluation_cycles:<org>` (D10/D12).';
  raise notice '  FASE 1 (EDICAO, mesma versao): A venceu dormindo ~8s DENTRO do UPDATE com o lock em maos; B bloqueou no MESMO lock, releu a versao (1) e terminou em F5_10_CONFLICT de versao divergente — NENHUM lost update.';
  raise notice '  FASE 2 (APROVACAO, MESMO papel): A venceu dormindo ~8s DENTRO do INSERT; B bloqueou e terminou em F5_10_CONFLICT de "ja existe aprovacao vigente" — a serializacao pelo lock e o que impede duas vigentes do mesmo papel.';
  raise notice '  FASE 3 (PAPEIS DISTINTOS, contraparte positiva): o COORDENADOR congelado aprovou a MESMA meta; os 2 fatos coexistem (1 vigente por papel) e o fato de A permanece intacto.';
  raise notice '  A prova de CONTENCAO (tempo de espera medido) vive no stdout da sessao B; este consolidador prova o estado final e a AUSENCIA de efeito das intencoes perdedoras.';
  raise notice '============================================================';
end $$;
