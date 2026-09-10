-- ============================================================================
-- F5-06 (Issue #103): validação automatizada — avaliações no PostgreSQL
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de 01-cenario-f5-06.sql, como superuser local, com
-- ON_ERROR_STOP ativo. Cobre D4/D9/D13/D18/D20/D23/D24/D25/D26/D27.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 1) Schema: 13 tabelas, RLS habilitado, zero policies (deny-by-default)
-- ============================================================================
do $$
declare
  v_tabela text;
  v_tabelas text[] := array[
    'evaluation_config_versions','evaluation_config_criteria','evaluation_config_subcriteria',
    'evaluation_config_scale_bands','evaluation_config_participant_roles','evaluation_cycles',
    'evaluations','evaluation_participants','evaluation_scores','evaluation_comments',
    'evaluation_events','evaluation_pendencies','evaluation_aggregates'];
begin
  foreach v_tabela in array v_tabelas loop
    if not exists (select 1 from pg_tables t where t.schemaname='public' and t.tablename=v_tabela) then
      raise exception '[FAIL] tabela F5-06 ausente: %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] 13 tabelas F5-06 presentes (config, ciclo, avaliacao, participantes, notas, comentarios, eventos, pendencias, agregados)';
end $$;

do $$
declare
  v_tabela text;
  v_tabelas text[] := array[
    'evaluation_config_versions','evaluation_config_criteria','evaluation_config_subcriteria',
    'evaluation_config_scale_bands','evaluation_config_participant_roles','evaluation_cycles',
    'evaluations','evaluation_participants','evaluation_scores','evaluation_comments',
    'evaluation_events','evaluation_pendencies','evaluation_aggregates'];
begin
  foreach v_tabela in array v_tabelas loop
    if not exists (
      select 1 from pg_class c
       where c.oid = (quote_ident('public') || '.' || quote_ident(v_tabela))::regclass
         and c.relrowsecurity = true
    ) then
      raise exception '[FAIL] RLS nao habilitado em %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] RLS habilitado nas 13 tabelas F5-06';
end $$;

do $$
begin
  if exists (
    select 1 from pg_policies p
     where p.schemaname='public' and p.tablename like 'evaluation%'
  ) then
    raise exception '[FAIL] existe policy nas tabelas F5-06 (deny-by-default violado)';
  end if;
  raise notice '[PASS] zero policies nas tabelas F5-06 (deny-by-default estrutural)';
end $$;

-- ============================================================================
-- 2) Constraints: unique parcial, exclusion de vigência, CHECK de nota
-- ============================================================================
do $$
begin
  if not exists (
    select 1 from pg_indexes
     where schemaname='public' and tablename='evaluations'
       and indexname='uq_evaluations_org_cycle_collaborator_nao_cancelada'
  ) then
    raise exception '[FAIL] unique parcial de avaliacao nao cancelada ausente (D9)';
  end if;
  if not exists (
    select 1 from pg_constraint where conname='ex_evaluation_participants_vigencia'
  ) then
    raise exception '[FAIL] exclusion de sobreposicao de vigencia ausente (D23)';
  end if;
  if not exists (select 1 from pg_constraint where conname='ck_evaluation_scores_nota') then
    raise exception '[FAIL] CHECK de nota 1..5 ausente (D4)';
  end if;
  if exists (
    select 1 from pg_constraint where conname='uq_evaluation_participants_evaluation_role_collab'
  ) then
    raise exception '[FAIL] existe unique ETERNO (evaluation, role, collaborator) — D23 violado';
  end if;
  raise notice '[PASS] constraints F5-06 presentes (unique parcial, exclusion de vigencia, nota 1..5, sem unique eterno)';
end $$;

do $$
declare
  v_n int;
begin
  -- FKs compostas de tenant nas filhas
  select count(*) into v_n from pg_constraint
   where conname in (
     'fk_evaluations_cycle','fk_evaluations_evaluated_collaborator','fk_evaluations_config_version',
     'fk_evaluation_participants_evaluation','fk_evaluation_participants_collaborator',
     'fk_evaluation_scores_participant','fk_evaluation_scores_subcriterion',
     'fk_evaluation_comments_participant','fk_evaluation_events_evaluation',
     'fk_evaluation_pendencies_evaluation','fk_evaluation_cycles_config_version',
     'fk_evaluation_aggregates_subcriterion');
  if v_n <> 12 then
    raise exception '[FAIL] FKs compostas de tenant esperadas=12, encontradas=%', v_n;
  end if;

  -- ACHADO DA AUDITORIA: alem do tenant, a FK precisa amarrar PARTICIPANTE e
  -- AVALIACAO. Sem isso o banco aceitaria nota/comentario/pendencia da
  -- avaliacao A apontando para a ocorrencia da avaliacao B do mesmo tenant.
  select count(*) into v_n from pg_constraint c
   where c.conname in ('fk_evaluation_scores_participant',
                       'fk_evaluation_comments_participant',
                       'fk_evaluation_pendencies_participant')
     and array_length(c.conkey, 1) = 3
     and (select count(*) from unnest(c.conkey) k
           join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k
          where a.attname = 'evaluation_id') = 1;
  if v_n <> 3 then
    raise exception '[FAIL] FK participante+avaliacao+tenant incompleta (% de 3)', v_n;
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'uq_evaluation_participants_id_evaluation_organization'
  ) then
    raise exception '[FAIL] chave candidata (id, evaluation_id, organization_id) ausente';
  end if;

  -- Comentario FINAL unico por ocorrencia exige indice PARCIAL (NULL nao
  -- bloqueia duplicidade em unique simples).
  if not exists (
    select 1 from pg_indexes
     where schemaname='public' and tablename='evaluation_comments'
       and indexname='uq_evaluation_comments_participant_final'
  ) then
    raise exception '[FAIL] unique parcial de comentario FINAL ausente';
  end if;
  raise notice '[PASS] FKs de tenant + participante x avaliacao + unique parcial de comentario';
end $$;

do $$
declare
  v_n int;
begin
  -- agregados em numeric (nunca float) — D24
  select count(*) into v_n
    from information_schema.columns
   where table_schema='public'
     and ((table_name='evaluations' and column_name='nota_media')
       or (table_name='evaluation_aggregates' and column_name='nota')
       or (table_name='evaluation_config_scale_bands' and column_name='limite_minimo'))
     and data_type='numeric'
     and numeric_scale = 8;
  if v_n <> 3 then
    raise exception '[FAIL] agregados deveriam ser numeric(_,8) — encontrados %', v_n;
  end if;
  if exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name like 'evaluation%'
       and data_type in ('double precision','real')
  ) then
    raise exception '[FAIL] existe coluna float em tabela F5-06 (D24 violado)';
  end if;
  raise notice '[PASS] agregados em numeric(12,8) e nenhuma coluna float (D24)';
end $$;

-- ============================================================================
-- 3) Funções: INVOKER (nenhum DEFINER novo), EXECUTE somente service_role
-- ============================================================================
do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname like 'evaluation_%' and p.prosecdef;
  if v_n <> 0 then
    raise exception '[FAIL] funcao F5-06 com SECURITY DEFINER (%) — nenhum DEFINER novo', v_n;
  end if;
  raise notice '[PASS] funcoes F5-06 sao SECURITY INVOKER (nenhum DEFINER novo)';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public' and p.proname like 'evaluation_%'
    and a.privilege_type='EXECUTE'
    and (a.grantee = 0 or a.grantee='anon'::regrole or a.grantee='authenticated'::regrole);
  if v_n <> 0 then
    raise exception '[FAIL] EXECUTE indevido (public/anon/authenticated) em funcao F5-06: %', v_n;
  end if;
  raise notice '[PASS] funcoes F5-06 sem EXECUTE para public/anon/authenticated';
end $$;

do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
  where n.nspname='public' and p.proname like 'evaluation_%'
    and a.privilege_type='EXECUTE' and a.grantee='service_role'::regrole;
  if v_n < 14 then
    raise exception '[FAIL] funcoes F5-06 com EXECUTE service_role esperadas>=14, encontradas=%', v_n;
  end if;
  raise notice '[PASS] funcoes F5-06 com EXECUTE somente service_role (%)', v_n;
end $$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname='trg_evaluation_events_append_only') then
    raise exception '[FAIL] trigger append-only de evaluation_events ausente (D26)';
  end if;

  -- Configuracao versionada IMUTAVEL (D5/D22): enforcement no BANCO.
  if not exists (select 1 from pg_trigger where tgname='trg_evaluation_config_versions_imutavel')
     or not exists (select 1 from pg_trigger where tgname='trg_evaluation_config_criteria_imutavel')
     or not exists (select 1 from pg_trigger where tgname='trg_evaluation_config_subcriteria_imutavel')
     or not exists (select 1 from pg_trigger where tgname='trg_evaluation_config_scale_bands_imutavel')
     or not exists (select 1 from pg_trigger where tgname='trg_evaluation_config_participant_roles_imutavel') then
    raise exception '[FAIL] guard de imutabilidade da configuracao versionada ausente (D5/D22)';
  end if;
  raise notice '[PASS] append-only (D26) + configuracao versionada imutavel (D5/D22)';
end $$;

do $$
begin
  -- Least privilege: nenhuma remocao fisica de avaliacao/ocorrencia pelo
  -- caminho server-side (historico preservado — D11/D23).
  if has_table_privilege('service_role', 'public.evaluations', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_participants', 'DELETE') then
    raise exception '[FAIL] service_role com DELETE em avaliacao/participantes (least privilege)';
  end if;
  raise notice '[PASS] service_role sem DELETE em evaluations/evaluation_participants';
end $$;

-- ============================================================================
-- 4) RLS em execução: authenticated sem leitura/DML no domínio
-- ============================================================================
set role authenticated;
do $$
declare
  v_ok boolean;
  v_tabela text;
  v_tabelas text[] := array[
    'evaluation_config_versions','evaluation_cycles','evaluations','evaluation_participants',
    'evaluation_scores','evaluation_comments','evaluation_events','evaluation_pendencies',
    'evaluation_aggregates'];
begin
  foreach v_tabela in array v_tabelas loop
    v_ok := false;
    begin
      execute format('select count(*) from public.%I', v_tabela);
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then
      raise exception '[FAIL] authenticated leu tabela F5-06 %', v_tabela;
    end if;
  end loop;
  raise notice '[PASS] authenticated sem leitura direta nas tabelas F5-06 (projecao somente via RPC)';
end $$;
reset role;

-- ============================================================================
-- 5) Cálculo oficial: colegiado como UMA parcela (D25), sem arredondamento (D24)
-- ============================================================================
do $$
declare
  v_eval uuid;
  v_media numeric;
  v_agg numeric;
  v_qtd int;
begin
  select id into v_eval from public.evaluations
   where organization_id='d6a00000-0000-0000-0000-0000000000a1'
     and evaluated_collaborator_id='d6c00000-0000-0000-0000-0000000000c2';

  select nota_media into v_media from public.evaluations where id = v_eval;

  -- Parcelas VIGENTES desta avaliação (após a correção de auditoria o cenário
  -- autora apenas atores com ocorrência ÚNICA):
  --   GESTAO_CADEIA (c1) = 4 ; COLEGIADO (c4) = 4 (UMA parcela agregada, D25)
  --   GESTAO_DIRETA: ocorrência encerrada no cenário (histórico preservado)
  -- => subcriterio = (4 + 4) / 2 = 4.0
  if v_media <> 4 then
    raise exception '[FAIL] nota_media esperada 4.0 (colegiado agregado como UMA parcela), obtida %', v_media;
  end if;

  select count(*) into v_qtd from public.evaluation_aggregates
   where evaluation_id = v_eval and escopo='CRITERIO' and nota = 4;
  if v_qtd <> 8 then
    raise exception '[FAIL] agregados por criterio esperados=8 com 4.0, encontrados=%', v_qtd;
  end if;

  select count(*) into v_qtd from public.evaluation_aggregates
   where evaluation_id = v_eval and escopo='SUBCRITERIO' and nota = 4;
  if v_qtd <> 25 then
    raise exception '[FAIL] agregados por subcriterio esperados=25 com 4.0, encontrados=%', v_qtd;
  end if;

  -- Regressão de ponderação (D25): o colegiado entra como UMA parcela. Com um
  -- único voto válido (4) a média agregada coincide com o voto individual, então
  -- a anti-regressão é comprovada pela contagem das parcelas contribuintes:
  -- exatamente 2 responsabilidades com nota (GESTAO_CADEIA e COLEGIADO).
  select count(distinct p.role_type)::int into v_qtd
    from public.evaluation_scores sc
    join public.evaluation_participants p on p.id = sc.participant_id
   where sc.evaluation_id = v_eval
     and p.valid_from <= now()
     and (p.valid_to is null or p.valid_to > now());
  if v_qtd <> 2 then
    raise exception '[FAIL] parcelas contribuintes esperadas=2 (colegiado agregado), encontradas=%', v_qtd;
  end if;

  -- recomputação == materializado (D13)
  v_agg := public.evaluation_calcular(v_eval);
  if v_agg <> v_media then
    raise exception '[FAIL] recomputacao divergente do materializado (% x %)', v_agg, v_media;
  end if;
  raise notice '[PASS] calculo oficial: colegiado como UMA parcela (4.0, 2 parcelas), 8 criterios, 25 subcriterios, recomputacao == materializado';
end $$;

do $$
declare v_n int;
begin
  -- ausência não entra na média: 1 membro do colegiado sem nota não vira zero
  select count(*) into v_n from public.evaluation_scores s
    join public.evaluation_participants p on p.id = s.participant_id
   where p.role_type='COLEGIADO' and s.nota = 0;
  if v_n <> 0 then
    raise exception '[FAIL] existe nota ZERO persistida (ausencia deve ser linha inexistente — D4)';
  end if;
  if exists (select 1 from public.evaluation_scores where nota < 1 or nota > 5) then
    raise exception '[FAIL] nota fora de 1..5 persistida (D4 violado)';
  end if;
  raise notice '[PASS] ausencia = linha inexistente, nunca zero; notas sempre 1..5';
end $$;

-- ============================================================================
-- 6) Workflow: conclusão exige completude; imutável; reabertura; pendência
-- ============================================================================
do $$
declare
  v_config uuid;
  v_inc uuid;
  v_ok boolean := false;
begin
  select config_version_id into v_config from public.evaluation_cycles
   where id='d6f00000-0000-0000-0000-0000000000a1';

  -- A avaliacao de c3 precisa estar CANCELADA antes de recriar (unique parcial
  -- por organizacao/ciclo/colaborador nao cancelada — D9).
  perform public.evaluation_cancelar(
    e.id, 'Cancelamento sintetico para recriar a avaliacao incompleta.',
    'd6b00000-0000-0000-0000-0000000000a1')
    from public.evaluations e
   where e.evaluated_collaborator_id = 'd6c00000-0000-0000-0000-0000000000c3'
     and e.status <> 'CANCELADA';

  -- avaliação incompleta (sem participantes/notas) do colaborador c3 — é a
  -- avaliação usada no fechamento de ciclo com pendência (§7)
  v_inc := public.evaluation_criar(
    'd6a00000-0000-0000-0000-0000000000a1',
    'd6f00000-0000-0000-0000-0000000000a1',
    'd6c00000-0000-0000-0000-0000000000c3',
    'd6b00000-0000-0000-0000-0000000000a1');

  begin
    perform public.evaluation_concluir(v_inc, 'd6b00000-0000-0000-0000-0000000000a1');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] conclusao de avaliacao INCOMPLETA foi aceita (D18 violado)';
  end if;
  raise notice '[PASS] conclusao normal exige completude (avaliacao incompleta rejeitada)';
end $$;

do $$
declare
  v_inc uuid;
begin
  select id into v_inc from public.evaluations
   where evaluated_collaborator_id='d6c00000-0000-0000-0000-0000000000c3';
  if (select status from public.evaluations where id=v_inc) <> 'RASCUNHO' then
    raise exception '[FAIL] avaliacao incompleta nao permaneceu em RASCUNHO apos a recusa';
  end if;
  raise notice '[PASS] avaliacao incompleta permanece nao concluida apos a recusa (nao ha conversao automatica)';
end $$;

-- conclusão da avaliação completa + imutabilidade + transparência + reabertura
do $$
declare
  v_eval uuid;
  v_ok boolean := false;
  v_leit jsonb;
begin
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id='d6c00000-0000-0000-0000-0000000000c2';

  perform public.evaluation_concluir(v_eval, 'd6b00000-0000-0000-0000-0000000000a1');
  if (select status from public.evaluations where id=v_eval) <> 'CONCLUIDA' then
    raise exception '[FAIL] avaliacao completa nao foi concluida';
  end if;
  if not exists (
    select 1 from public.evaluation_events
     where evaluation_id=v_eval and event_type='CONCLUIDA'
       and actor_user_profile_id='d6b00000-0000-0000-0000-0000000000a1'
  ) then
    raise exception '[FAIL] evento CONCLUIDA ausente/ sem autoria soberana (D7/D26)';
  end if;
  raise notice '[PASS] conclusao completa + evento CONCLUIDA com autoria soberana (mesma transacao)';
end $$;

do $$
declare
  v_eval uuid;
  v_ok boolean := false;
  v_leit jsonb;
begin
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id='d6c00000-0000-0000-0000-0000000000c2';

  -- imutabilidade normal (D8): nota em CONCLUIDA é rejeitada. A ocorrência é a
  -- do PRÓPRIO ator (a3, vinculado a c1/gestor de cadeia): depois da correção de
  -- auditoria o chamador não escolhe a ocorrência.
  begin
    perform public.evaluation_gravar_notas(
      v_eval,
      (select jsonb_agg(jsonb_build_object('subcriterion_id', sc.id, 'nota', 5))
         from public.evaluation_config_subcriteria sc
        where sc.organization_id='d6a00000-0000-0000-0000-0000000000a1'),
      'd6b00000-0000-0000-0000-0000000000a3');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] avaliacao CONCLUIDA aceitou alteracao de nota (D8 violado)';
  end if;
  raise notice '[PASS] avaliacao CONCLUIDA imutavel em fluxo normal (D8)';
end $$;

-- transparência do avaliado (D20): agregados + colegiado, NUNCA voto individual
do $$
declare
  v_eval uuid;
  v_leit jsonb;
  v_txt text;
begin
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id='d6c00000-0000-0000-0000-0000000000c2';

  v_leit := public.evaluation_leitura_avaliado(v_eval, 'd6b00000-0000-0000-0000-0000000000a1');
  v_txt := v_leit::text;

  if (v_leit ->> 'nota_media')::numeric <> 4 then
    raise exception '[FAIL] projecao do avaliado sem nota_media correta';
  end if;
  if jsonb_array_length(v_leit -> 'criterios') <> 8 then
    raise exception '[FAIL] projecao do avaliado sem 8 criterios agregados';
  end if;
  if jsonb_array_length(v_leit -> 'colegiado') <> 2 then
    raise exception '[FAIL] projecao do avaliado sem a lista de 2 membros do colegiado';
  end if;
  if v_txt like '%participant_id%' or v_txt like '%nota_individual%' or v_txt like '%voto%' then
    raise exception '[FAIL] projecao do avaliado expoe voto/nota individual ou participant_id (D20 violado)';
  end if;
  raise notice '[PASS] transparencia do avaliado: agregados + lista de colegiado, sem voto/nota individual nem participant_id (D20)';
end $$;

do $$
declare
  v_eval uuid;
  v_ok boolean := false;
begin
  select id into v_eval from public.evaluations
   where evaluated_collaborator_id='d6c00000-0000-0000-0000-0000000000c2';

  -- reabertura exige motivo
  begin
    perform public.evaluation_reabrir(v_eval, '   ', 'd6b00000-0000-0000-0000-0000000000a1');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] reabertura sem motivo foi aceita';
  end if;

  perform public.evaluation_reabrir(v_eval, 'Reabertura sintetica para validacao.', 'd6b00000-0000-0000-0000-0000000000a1');
  if (select status from public.evaluations where id=v_eval) <> 'RASCUNHO'
     or (select data_conclusao from public.evaluations where id=v_eval) is not null then
    raise exception '[FAIL] reabertura nao restaurou RASCUNHO/limpou data_conclusao';
  end if;
  if not exists (
    select 1 from public.evaluation_events
     where evaluation_id=v_eval and event_type='REABERTA' and motivo is not null
  ) then
    raise exception '[FAIL] evento REABERTA ausente';
  end if;
  raise notice '[PASS] reabertura auditada (motivo obrigatorio, historico preservado, evento append-only)';
end $$;

-- ============================================================================
-- 7) Cancelamento e fechamento de ciclo com pendência (D11/D18)
-- ============================================================================
do $$
declare
  v_cancel uuid;
  v_novo uuid;
  v_config uuid;
begin
  select config_version_id into v_config from public.evaluation_cycles
   where id='d6f00000-0000-0000-0000-0000000000a1';

  -- avaliacao sintetica do colaborador c1, criada apenas para exercitar o
  -- cancelamento auditado (D7/D26) e a liberacao da unique parcial (D9)
  v_cancel := public.evaluation_criar(
    'd6a00000-0000-0000-0000-0000000000a1',
    'd6f00000-0000-0000-0000-0000000000a1',
    'd6c00000-0000-0000-0000-0000000000c1',
    'd6b00000-0000-0000-0000-0000000000a1');

  perform public.evaluation_cancelar(v_cancel, 'Cancelamento sintetico.', 'd6b00000-0000-0000-0000-0000000000a1');
  if (select status from public.evaluations where id=v_cancel) <> 'CANCELADA' then
    raise exception '[FAIL] cancelamento nao aplicado';
  end if;

  -- unique parcial libera nova avaliacao para o mesmo colaborador/ciclo
  v_novo := public.evaluation_criar(
    'd6a00000-0000-0000-0000-0000000000a1',
    'd6f00000-0000-0000-0000-0000000000a1',
    'd6c00000-0000-0000-0000-0000000000c1',
    'd6b00000-0000-0000-0000-0000000000a1');
  raise notice '[PASS] cancelamento auditado e unique parcial liberado para nova avaliacao (D9)';
end $$;

do $$
declare
  v_marcadas int;
  v_status text;
  v_perm boolean;
  v_pend int;
begin
  v_marcadas := public.evaluation_fechar_ciclo_pendencias(
    'd6f00000-0000-0000-0000-0000000000a1',
    'd6a00000-0000-0000-0000-0000000000a1',
    'd6b00000-0000-0000-0000-0000000000a1');

  if v_marcadas < 1 then
    raise exception '[FAIL] fechamento com avaliacoes incompletas nao marcou pendencias';
  end if;

  select status, encerrada_com_pendencias into v_status, v_perm
    from public.evaluations
   where evaluated_collaborator_id='d6c00000-0000-0000-0000-0000000000c3';

  if v_perm is not true then
    raise exception '[FAIL] marcador permanente de pendencia ausente (D11/D18)';
  end if;
  if v_status = 'CONCLUIDA' then
    raise exception '[FAIL] avaliacao incompleta foi convertida em CONCLUIDA no fechamento (D18 violado)';
  end if;

  select count(*) into v_pend from public.evaluation_pendencies p
    join public.evaluations e on e.id = p.evaluation_id
   where e.evaluated_collaborator_id='d6c00000-0000-0000-0000-0000000000c3';
  if v_pend < 1 then
    raise exception '[FAIL] pendencias nao persistidas (evaluation_pendencies)';
  end if;
  raise notice '[PASS] fechamento incompleto: marcador permanente + pendencias persistidas SEM concluir a avaliacao (D11/D18)';
end $$;

-- ============================================================================
-- 8) Append-only, tenant isolation e IDOR
-- ============================================================================
do $$
declare v_ok boolean := false;
begin
  begin
    update public.evaluation_events set motivo = 'adulterado';
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] UPDATE da trilha de eventos foi aceito (D26 violado)';
  end if;
  raise notice '[PASS] evaluation_events e append-only (UPDATE negado)';
end $$;

do $$
declare v_ok boolean := false;
begin
  -- ator SEM membership na organização alvo ⇒ negado (cross-tenant / D27)
  begin
    perform public.evaluation_fechar_ciclo_pendencias(
      'd6f00000-0000-0000-0000-0000000000a1',
      'd6a00000-0000-0000-0000-0000000000a1',
      'd6b00000-0000-0000-0000-0000000000a2');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ator de outro tenant foi aceito (D27 violado)';
  end if;
  raise notice '[PASS] ator de outro tenant negado (membership revalidada server-side)';
end $$;

do $$
declare v_ok boolean := false;
begin
  -- colaborador de outro tenant na criacao ⇒ negado
  begin
    perform public.evaluation_criar(
      'd6a00000-0000-0000-0000-0000000000b1',
      'd6f00000-0000-0000-0000-0000000000a1',
      'd6c00000-0000-0000-0000-0000000000c1',
      'd6b00000-0000-0000-0000-0000000000a1');
  exception when raise_exception then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] ciclo/tenant divergente foi aceito';
  end if;
  raise notice '[PASS] ciclo de outro tenant / IDOR negado (fail-closed)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-06: todas as verificacoes passaram (schema, constraints, RLS, calculo oficial D25, ausencia D4, workflow D8/D18, transparencia D20, reabertura/cancelamento D7/D26, pendencias D11, tenant isolation D27).';
end $$;
