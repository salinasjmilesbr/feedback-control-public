-- ============================================================================
-- F5-10 P2 (Issue #212): validacao automatizada das OPERACOES SOBERANAS de metas
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   supabase/validacao/21-cenario-f5-10-p2.sql   (fixture)
--   supabase/validacao/22-validar-f5-10-p2.sql   (este arquivo)
--
-- Contrato coberto (docs/F5-10-desenho-tecnico.md; D1-D25):
--   A  recusas de ator/tenant/ciclo/quota/tipo/texto SEM efeito;
--   H  atomicidade: falha injetada na trilha => ROLLBACK TOTAL (meta + evento);
--   B  criacao valida (UUID soberano do banco, version 0, evento CRIADA);
--   V  idempotencia por (organization_id, operation_id) + hash canonico;
--   C  progresso: 0 e 100 aceitos; fora de 0..100, stale e intencao divergente
--      recusados;
--   D  edicao do conteudo permitido; ciclo nao-ATIVO e version obsoleta recusados;
--   E  finalizacao coerente (ATINGIDA/NAO_ATINGIDA), fechamento incoerente
--      recusado e re-finalizacao silenciosa inexistente;
--   F  revisao de fechamento com fechamento anterior recuperavel na trilha;
--   G  exclusao logica (linha preservada) e meta excluida sem mutacao;
--   I  a quota continua autoridade do BANCO (trigger da P1) alem da RPC;
--   J  ACL/anti-escopo: 7 RPCs INVOKER com lock normativo, EXECUTE so
--      service_role, zero policy, DELETE fisico negado e P3/P4/P5 nao
--      antecipadas;
--   K  nenhuma aprovacao criada incidentalmente (P3 nao antecipada);
--   L  estado final deterministico (nenhum residuo dos testes negativos);
--   M  D21 — limites do ciclo: alteracao valida com version do CICLO +1 e evento
--      `LIMITES_DO_CICLO_ALTERADOS` em **`cycle_events`** (before/after completos),
--      replay identico, operation_id divergente, stale, ciclo nao ATIVO,
--      cross-tenant, perfil/membership invalidos, quantidade fora de 0..3,
--      reducao ate/abaixo das metas vivas, invariante do banco, ROLLBACK por
--      falha injetada na trilha do ciclo e ZERO vazamento para a trilha de metas.
--
-- Saida deterministica: um `[PASS]` por bloco; qualquer falha aborta.
-- Asserts negativos rodam em subtransacao (a excecao esperada reverte apenas a
--quele bloco, nunca o cenario) e o efeito NULO e SEMPRE verificado no estado.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture presente e ESTADO LIMPO (sem execucao anterior)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org   uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_cols  int;
  v_metas int;
  v_evt   int;
  v_aprov int;
begin
  select count(*) into v_cols from public.collaborators
   where id::text like 'f0b00000%';
  if v_cols <> 3 then
    raise exception '[FAIL] pre-condicao: fixture F5-10 P2 ausente (colaboradores=%) — execute 21-cenario-f5-10-p2.sql', v_cols;
  end if;
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in (v_org, v_beta);
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in (v_org, v_beta);
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in (v_org, v_beta);
  if v_metas <> 2 or v_evt <> 1 or v_aprov <> 0 then
    raise exception
      '[FAIL] pre-condicao: estado sujo (metas=%, eventos=%, aprovacoes=%) — execute `supabase db reset` (o dominio de metas e append-only e nao tem reset parcial)',
      v_metas, v_evt, v_aprov;
  end if;
  raise notice '[PASS] pre-condicoes: fixture presente e estado limpo (2 metas, 1 evento, 0 aprovacoes)';
end $$;

-- ============================================================================
-- 1) A) Recusas de criacao SEM efeito (ator/tenant/ciclo/quota/tipo/texto)
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_ciclo  uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_encer  uuid := 'f0d10000-0000-0000-0000-0000000000a2';
  v_cicb   uuid := 'f0d10000-0000-0000-0000-0000000000b1';
  v_col1   uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_colb   uuid := 'f0b00000-0000-0000-0000-0000000000b1';
  v_a1     uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_abeta  uuid := 'f0c00000-0000-0000-0000-000000000002';
  v_adis   uuid := 'f0c00000-0000-0000-0000-000000000003';
  v_ainat  uuid := 'f0c00000-0000-0000-0000-000000000004';
  v_ok     boolean;
  v_msg    text;
  v_n      int;
begin
  -- (A1) ator com membership DISABLED.
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
      'probe membership disabled', 'kpi', 'alvo', v_adis,
      'f0700000-0000-0000-0000-000000000010');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] A1: ator com membership disabled deveria ser FORBIDDEN';
  end if;

  -- (A2) ator com PERFIL disabled (membership ativa): o perfil ativo e exigido
  --      (o CHECK de `user_profiles.status` admite apenas active/disabled).
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
      'probe perfil disabled', 'kpi', 'alvo', v_ainat,
      'f0700000-0000-0000-0000-000000000011');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] A2: ator com perfil disabled deveria ser FORBIDDEN';
  end if;

  -- (A3) ator de OUTRO tenant operando na organizacao Alfa.
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
      'probe cross-tenant', 'kpi', 'alvo', v_abeta,
      'f0700000-0000-0000-0000-000000000012');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] A3: ator de outro tenant deveria ser FORBIDDEN';
  end if;

  -- (A4) ciclo de OUTRO tenant => NOT_FOUND (nunca "meia" operacao).
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_cicb, v_col1, 'NEGOCIO_PROJETO',
      'probe ciclo de outro tenant', 'kpi', 'alvo', v_a1,
      'f0700000-0000-0000-0000-000000000013');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] A4: ciclo de outro tenant deveria ser NOT_FOUND';
  end if;

  -- (A5) colaborador de OUTRO tenant => NOT_FOUND.
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_colb, 'NEGOCIO_PROJETO',
      'probe colaborador de outro tenant', 'kpi', 'alvo', v_a1,
      'f0700000-0000-0000-0000-000000000014');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] A5: colaborador de outro tenant deveria ser NOT_FOUND';
  end if;

  -- (A6) ciclo NAO-ATIVO (ENCERRADO) => CONFLICT.
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_encer, v_col1, 'NEGOCIO_PROJETO',
      'probe ciclo encerrado', 'kpi', 'alvo', v_a1,
      'f0700000-0000-0000-0000-000000000015');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] A6: criacao em ciclo ENCERRADO deveria ser CONFLICT';
  end if;

  -- (A7) tipo SEM quota configurada (Beta/INDIVIDUAL) => CONFLICT fail-closed.
  v_ok := false;
  begin
    perform public.meta_criar(v_beta, v_cicb, v_colb, 'INDIVIDUAL',
      'probe quota zero', 'kpi', 'alvo', v_abeta,
      'f0700000-0000-0000-0000-000000000016');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] A7: tipo sem quota deveria ser CONFLICT (fail-closed)';
  end if;

  -- (A8) tipo invalido e textos em branco => INVALID_INPUT.
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'EQUIPE',
      'probe tipo invalido', 'kpi', 'alvo', v_a1,
      'f0700000-0000-0000-0000-000000000017');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] A8: tipo invalido deveria ser INVALID_INPUT';
  end if;

  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
      '   ', 'kpi', 'alvo', v_a1,
      'f0700000-0000-0000-0000-000000000018');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] A8: descricao em branco deveria ser INVALID_INPUT';
  end if;

  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
      'probe kpi com bordas', ' kpi ', 'alvo', v_a1,
      'f0700000-0000-0000-0000-000000000019');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] A8: kpi com espacos nas bordas deveria ser INVALID_INPUT (nunca ajuste silencioso)';
  end if;

  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
      'probe sem expected_version', 'kpi', 'alvo', v_a1, null);
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] A8: operation_id ausente deveria ser INVALID_INPUT';
  end if;

  -- NENHUMA tentativa recusada criou meta ou evento, em nenhum tenant.
  select count(*) into v_n from (
    select 1 from public.evaluation_goals
     where organization_id in (v_alfa, v_beta)
    union all
    select 1 from public.evaluation_goal_events
     where organization_id in (v_alfa, v_beta)
  ) t;
  if v_n <> 3 then
    raise exception '[FAIL] A: tentativa recusada criou estado (metas+eventos=%, esperado 2+1)', v_n;
  end if;

  raise notice '[PASS] A: 10 recusas sem efeito (membership disabled, perfil inativo, cross-tenant de ator/ciclo/colaborador, ciclo ENCERRADO, quota zero, tipo, textos e operation_id)';
end $$;

-- ============================================================================
-- 2) H) ATOMICIDADE: falha injetada na trilha => ROLLBACK TOTAL
-- ============================================================================
-- A falha e injetada APENAS no INSERT da trilha (`evaluation_goal_events`), que
-- acontece DEPOIS da mutacao da meta dentro da RPC: se a transacao nao fosse
-- atomica, a meta ficaria mutada sem evento. DDL no nivel SQL (fora de bloco),
-- removida ao final deste bloco.
create or replace function public._mut_f5_10_p2_falhar_trilha()
returns trigger
language plpgsql
as $mut$
begin
  raise exception 'MUT_F5_10_P2: falha injetada na gravacao da trilha de metas';
end;
$mut$;

create trigger _mut_f5_10_p2_trilha before insert on public.evaluation_goal_events
  for each row execute function public._mut_f5_10_p2_falhar_trilha();

do $$
declare
  v_alfa   uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_cicb   uuid := 'f0d10000-0000-0000-0000-0000000000b1';
  v_colb   uuid := 'f0b00000-0000-0000-0000-0000000000b1';
  v_a1     uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_abeta  uuid := 'f0c00000-0000-0000-0000-000000000002';
  v_fixfin uuid := 'f0900000-0000-0000-0000-000000000009';
  v_ok     boolean;
  v_meta   record;
  v_n      int;
begin
  -- (H1) meta_criar: a meta e o evento caem JUNTOS.
  v_ok := false;
  begin
    perform public.meta_criar(v_beta, v_cicb, v_colb, 'NEGOCIO_PROJETO',
      'probe rollback de criacao', 'kpi de probe', 'alvo de probe', v_abeta,
      'f0700000-0000-0000-0000-000000000020');
  exception when others then v_ok := sqlerrm like '%MUT_F5_10_P2%';
  end;
  if not v_ok then
    raise exception '[FAIL] H1: a falha injetada na trilha nao abortou a criacao';
  end if;
  select count(*) into v_n from public.evaluation_goals where organization_id = v_beta;
  if v_n <> 0 then
    raise exception '[FAIL] H1: rollback incompleto — meta parcial em Beta (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events where organization_id = v_beta;
  if v_n <> 0 then
    raise exception '[FAIL] H1: rollback incompleto — evento parcial em Beta (%)', v_n;
  end if;
  if exists (
    select 1 from public.evaluation_goal_events
     where organization_id = v_beta
       and operation_id = 'f0700000-0000-0000-0000-000000000020'
  ) then
    raise exception '[FAIL] H1: operation_id do probe de rollback ficou na trilha';
  end if;

  -- (H2) meta_revisar_finalizacao: a meta finalizada de fixture permanece
  --      INTOCADA (status, fechamento e version) e nenhum evento e gravado.
  select g.status, g.resultado_final, g.atingida, g.data_fechamento, g.version
    into v_meta
    from public.evaluation_goals g where g.id = v_fixfin;

  v_ok := false;
  begin
    perform public.meta_revisar_finalizacao(v_fixfin, v_alfa,
      'resultado que NAO deve persistir', false, 'probe de rollback', 1, v_a1,
      'f0700000-0000-0000-0000-000000000021');
  exception when others then v_ok := sqlerrm like '%MUT_F5_10_P2%';
  end;
  if not v_ok then
    raise exception '[FAIL] H2: a falha injetada na trilha nao abortou a revisao';
  end if;

  if exists (
    select 1 from public.evaluation_goals g
     where g.id = v_fixfin
       and (g.status is distinct from v_meta.status
            or g.resultado_final is distinct from v_meta.resultado_final
            or g.atingida is distinct from v_meta.atingida
            or g.data_fechamento is distinct from v_meta.data_fechamento
            or g.version <> v_meta.version)
  ) then
    raise exception '[FAIL] H2: rollback incompleto — a meta foi mutada sem evento';
  end if;
  select count(*) into v_n from public.evaluation_goal_events
   where organization_id = v_alfa and operation_id = 'f0700000-0000-0000-0000-000000000021';
  if v_n <> 0 then
    raise exception '[FAIL] H2: evento gravado apesar da falha injetada (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events where organization_id = v_alfa;
  if v_n <> 1 then
    raise exception '[FAIL] H2: a trilha de Alfa deixou de ter exatamente o evento de fixture (%)', v_n;
  end if;

  raise notice '[PASS] H: falha injetada na trilha => ROLLBACK TOTAL (nem meta nem evento parciais; fixture finalizada intocada)';
end $$;

drop trigger _mut_f5_10_p2_trilha on public.evaluation_goal_events;
drop function public._mut_f5_10_p2_falhar_trilha();

-- ============================================================================
-- 3) B) Criacao valida: UUID soberano, version 0 e evento CRIADA
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_ciclo  uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_cicb   uuid := 'f0d10000-0000-0000-0000-0000000000b1';
  v_col1   uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_col2   uuid := 'f0b00000-0000-0000-0000-000000000002';
  v_colb   uuid := 'f0b00000-0000-0000-0000-0000000000b1';
  v_a1     uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_abeta  uuid := 'f0c00000-0000-0000-0000-000000000002';
  v_res    jsonb;
  v_id     uuid;
  v_meta   record;
  v_evt    record;
  v_qtd    int;
  v_ok     boolean;
  v_msg    text;
  v_org_meta uuid;
begin
  -- (B1) meta de negocio do colaborador 1 (quota 2: esta + a proxima).
  v_res := public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
    'Meta de negocio soberana (P2)', 'KPI de negocio (P2)', '100 unidades (P2)',
    v_a1, 'f0700000-0000-0000-0000-000000000030');
  v_id := (v_res->>'goal_id')::uuid;
  if v_id is null then
    raise exception '[FAIL] B1: meta_criar nao devolveu goal_id';
  end if;

  select g.* into v_meta from public.evaluation_goals g where g.id = v_id;
  if v_meta.id is null then
    raise exception '[FAIL] B1: meta nao gravada';
  end if;
  if v_meta.organization_id <> v_alfa or v_meta.cycle_id <> v_ciclo
     or v_meta.collaborator_id <> v_col1 or v_meta.tipo <> 'NEGOCIO_PROJETO' then
    raise exception '[FAIL] B1: vinculos soberanos divergentes (org/ciclo/colaborador/tipo)';
  end if;
  if v_meta.status <> 'EM_ANDAMENTO' or v_meta.version <> 0 or v_meta.excluida then
    raise exception '[FAIL] B1: meta deveria nascer EM_ANDAMENTO/version 0/nao excluida (status=%, version=%, excluida=%)',
      v_meta.status, v_meta.version, v_meta.excluida;
  end if;
  if v_meta.descricao <> 'Meta de negocio soberana (P2)' then
    raise exception '[FAIL] B1: conteudo gravado divergente';
  end if;
  if v_meta.resultado_final is not null or v_meta.atingida is not null
     or v_meta.data_fechamento is not null then
    raise exception '[FAIL] B1: meta EM_ANDAMENTO nasceu com campo de fechamento';
  end if;
  if (v_res->>'version')::int <> 0 or v_res->>'status' <> 'EM_ANDAMENTO' then
    raise exception '[FAIL] B1: retorno divergente do estado criado (%)', v_res;
  end if;

  -- UUID SOBERANO: identidade gerada pelo banco, nunca recebida do corpo.
  if position('p_goal_id' in pg_get_function_arguments(
       'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)'::regprocedure)) > 0 then
    raise exception '[FAIL] B1: meta_criar aceita id de meta no corpo (identidade deve nascer no banco)';
  end if;

  -- Evento CRIADA: um, da meta/tenant corretos, com autoria resolvida no banco.
  select count(*) into v_qtd from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_id;
  if v_qtd <> 1 then
    raise exception '[FAIL] B1: esperado 1 evento para a meta nova (encontrado %)', v_qtd;
  end if;
  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_id;
  if v_evt.event_type <> 'CRIADA' or v_evt.entity_type <> 'evaluation_goal' then
    raise exception '[FAIL] B1: evento deveria ser CRIADA/evaluation_goal (recebido %/%)',
      v_evt.event_type, v_evt.entity_type;
  end if;
  if v_evt.actor_user_profile_id <> v_a1 then
    raise exception '[FAIL] B1: autoria do evento nao e o ator verificado';
  end if;
  -- A membership de autoria e RESOLVIDA no banco (nao existe parametro de membership).
  if v_evt.actor_membership_id <> 'f0d00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] B1: membership de autoria nao foi resolvida do banco';
  end if;
  if position('membership' in pg_get_function_arguments(
       'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)'::regprocedure)) > 0 then
    raise exception '[FAIL] B1: meta_criar aceita membership no corpo (autoria deve ser resolvida no servidor)';
  end if;
  if v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] B1: payload_hash fora do formato SHA-256';
  end if;
  if v_evt.result_entity_id <> v_id then
    raise exception '[FAIL] B1: result_entity_id do evento nao e a meta criada';
  end if;
  if (v_evt.after_value->>'version')::int <> 0
     or v_evt.after_value->>'status' <> 'EM_ANDAMENTO' then
    raise exception '[FAIL] B1: after_value do evento divergente do estado criado';
  end if;

  -- (B2) segunda meta de negocio (colaborador 2) fecha a quota 2 do tipo.
  v_res := public.meta_criar(v_alfa, v_ciclo, v_col2, 'NEGOCIO_PROJETO',
    'Segunda meta de negocio (P2)', 'KPI de negocio (P2)', '50 unidades (P2)',
    v_a1, 'f0700000-0000-0000-0000-000000000031');
  if (v_res->>'goal_id')::uuid is null then
    raise exception '[FAIL] B2: segunda meta nao criada';
  end if;

  -- (B3) meta individual (colaborador 1) — quota 1 do tipo.
  v_res := public.meta_criar(v_alfa, v_ciclo, v_col1, 'INDIVIDUAL',
    'Meta individual soberana (P2)', 'KPI individual (P2)', '10 entregas (P2)',
    v_a1, 'f0700000-0000-0000-0000-000000000032');
  if (v_res->>'goal_id')::uuid is null then
    raise exception '[FAIL] B3: meta individual nao criada';
  end if;

  -- (B4) meta no OUTRO tenant (Beta), pelo ator de Beta — tenant respeitado.
  v_res := public.meta_criar(v_beta, v_cicb, v_colb, 'NEGOCIO_PROJETO',
    'Meta de negocio de Beta (P2)', 'KPI de Beta (P2)', '7 unidades (P2)',
    v_abeta, 'f0700000-0000-0000-0000-000000000033');
  v_id := (v_res->>'goal_id')::uuid;
  if v_id is null then
    raise exception '[FAIL] B4: meta de Beta nao criada';
  end if;
  select g.organization_id into v_org_meta from public.evaluation_goals g where g.id = v_id;
  if v_org_meta <> v_beta then
    raise exception '[FAIL] B4: meta criada no tenant errado';
  end if;

  -- (B5) QUOTA excedida (3a meta de negocio em Alfa) => CONFLICT sem efeito.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
      'probe acima da quota', 'kpi de probe', 'alvo de probe', v_a1,
      'f0700000-0000-0000-0000-000000000034');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] B5: criacao acima da quota deveria ser CONFLICT (recebido %)', v_msg;
  end if;
  select count(*) into v_qtd from public.evaluation_goals
   where organization_id = v_alfa and cycle_id = v_ciclo and tipo = 'NEGOCIO_PROJETO'
     and excluida = false;
  if v_qtd <> 2 then
    raise exception '[FAIL] B5: a recusa por quota alterou o estado (vivas=%)', v_qtd;
  end if;

  raise notice '[PASS] B: 4 criacoes validas (UUID do banco, version 0, vinculos soberanos, evento CRIADA com autoria resolvida no servidor) e quota excedida recusada sem efeito';
end $$;

-- ============================================================================
-- 4) V) Idempotencia por (organization_id, operation_id) + hash canonico
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_col1  uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_a1    uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_r1    jsonb;
  v_r2    jsonb;
  v_qtd   int;
  v_ok    boolean;
  v_msg   text;
begin
  -- (V1) replay IDENTICO devolve o MESMO resultado, sem novo evento.
  v_r1 := public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
    'Meta de negocio soberana (P2)', 'KPI de negocio (P2)', '100 unidades (P2)',
    v_a1, 'f0700000-0000-0000-0000-000000000030');
  v_r2 := public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
    'Meta de negocio soberana (P2)', 'KPI de negocio (P2)', '100 unidades (P2)',
    v_a1, 'f0700000-0000-0000-0000-000000000030');
  if v_r1 <> v_r2 then
    raise exception '[FAIL] V1: replay idempotente devolveu resultado diferente (% vs %)', v_r1, v_r2;
  end if;
  select count(*) into v_qtd from public.evaluation_goal_events
   where organization_id = v_alfa
     and operation_id = 'f0700000-0000-0000-0000-000000000030';
  if v_qtd <> 1 then
    raise exception '[FAIL] V1: replay duplicou evento (linhas=%)', v_qtd;
  end if;
  select count(*) into v_qtd from public.evaluation_goals
   where organization_id = v_alfa and cycle_id = v_ciclo
     and collaborator_id = v_col1 and tipo = 'NEGOCIO_PROJETO';
  if v_qtd <> 1 then
    raise exception '[FAIL] V1: replay duplicou meta (linhas=%)', v_qtd;
  end if;

  -- (V2) mesmo operation_id com INTENCAO DIFERENTE => CONFLICT, sem efeito.
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'INDIVIDUAL',
      'intencao divergente', 'kpi de probe', 'alvo de probe', v_a1,
      'f0700000-0000-0000-0000-000000000030');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] V2: operation_id reutilizado com intencao diferente deveria ser CONFLICT';
  end if;
  select count(*) into v_qtd from public.evaluation_goals
   where organization_id = v_alfa and cycle_id = v_ciclo and tipo = 'INDIVIDUAL';
  if v_qtd <> 1 then
    raise exception '[FAIL] V2: a recusa por intencao divergente criou estado (INDIVIDUAL=%)', v_qtd;
  end if;

  -- (V3) o escopo da idempotencia e POR ORGANIZACAO: o operation_id usado em
  --      OUTRO tenant NAO e tratado como intencao divergente neste tenant. A
  --      recusa observada aqui e a de QUOTA (a quota do tipo esta esgotada), o que
  --      prova que o lookup de idempotencia NAO curto-circuitou com CONFLICT de
  --      intencao diferente.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_criar(v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
      'probe de escopo do operation_id', 'kpi de probe', 'alvo de probe', v_a1,
      'f0700000-0000-0000-0000-000000000033');
  exception when others then v_ok := sqlerrm like '%quota%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] V3: operation_id de OUTRO tenant nao pode ser tratado como intencao divergente neste tenant (esperada a recusa de QUOTA, recebido %)', v_msg;
  end if;

  raise notice '[PASS] V: idempotencia por operation_id + hash canonico (replay devolve o mesmo resultado; intencao divergente e CONFLICT sem efeito)';
end $$;

-- ============================================================================
-- 5) C) Progresso: 0 e 100 aceitos; fora de 0..100, stale e divergencia negados
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_col1  uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_a1    uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_g1    uuid;
  v_res   jsonb;
  v_meta  record;
  v_evt   record;
  v_ok    boolean;
  v_txt   text;
begin
  select g.id into v_g1 from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo
     and g.collaborator_id = v_col1 and g.tipo = 'NEGOCIO_PROJETO';
  if v_g1 is null then
    raise exception '[FAIL] C: pre-condicao — meta criada em B ausente';
  end if;

  -- (C1) progresso FORA do dominio => INVALID_INPUT, sem efeito.
  foreach v_txt in array array['-1', '101'] loop
    v_ok := false;
    begin
      perform public.meta_atualizar_progresso(v_g1, v_alfa, 'probe fora do dominio',
        v_txt::integer, 0, v_a1, 'f0700000-0000-0000-0000-000000000040');
    exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
    end;
    if not v_ok then
      raise exception '[FAIL] C1: progresso % deveria ser INVALID_INPUT', v_txt;
    end if;
  end loop;
  select g.version, g.progresso_percentual into v_meta
    from public.evaluation_goals g where g.id = v_g1;
  if v_meta.version <> 0 or v_meta.progresso_percentual is not null then
    raise exception '[FAIL] C1: progresso invalido alterou o estado (version=%, progresso=%)',
      v_meta.version, v_meta.progresso_percentual;
  end if;

  -- (C2) progresso 0 ACEITO (version 0 -> 1).
  v_res := public.meta_atualizar_progresso(v_g1, v_alfa, 'zero por cento', 0, 0,
    v_a1, 'f0700000-0000-0000-0000-000000000041');
  if (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] C2: progresso 0 deveria levar a version 1 (recebido %)', v_res;
  end if;
  select g.progresso_percentual, g.resultado_atual, g.data_ultimo_acompanhamento, g.version
    into v_meta from public.evaluation_goals g where g.id = v_g1;
  if v_meta.progresso_percentual <> 0 or v_meta.resultado_atual <> 'zero por cento'
     or v_meta.data_ultimo_acompanhamento is null or v_meta.version <> 1 then
    raise exception '[FAIL] C2: acompanhamento nao gravado corretamente (progresso=%, resultado=%, data=%, version=%)',
      v_meta.progresso_percentual, v_meta.resultado_atual,
      v_meta.data_ultimo_acompanhamento, v_meta.version;
  end if;

  -- (C3) progresso 100 ACEITO (version 1 -> 2) + evento com before/after.
  v_res := public.meta_atualizar_progresso(v_g1, v_alfa, 'cem por cento', 100, 1,
    v_a1, 'f0700000-0000-0000-0000-000000000042');
  if (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] C3: progresso 100 deveria levar a version 2 (recebido %)', v_res;
  end if;
  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f0700000-0000-0000-0000-000000000042';
  if v_evt.event_type <> 'PROGRESSO_ATUALIZADO' then
    raise exception '[FAIL] C3: evento do progresso deveria ser PROGRESSO_ATUALIZADO (recebido %)',
      v_evt.event_type;
  end if;
  if (v_evt.before_value->>'progresso_percentual')::int <> 0
     or (v_evt.after_value->>'progresso_percentual')::int <> 100 then
    raise exception '[FAIL] C3: before/after do progresso divergentes (% / %)',
      v_evt.before_value, v_evt.after_value;
  end if;

  -- (C4) expected_version OBSOLETO => CONFLICT, sem efeito.
  v_ok := false;
  begin
    perform public.meta_atualizar_progresso(v_g1, v_alfa, 'stale', 50, 1,
      v_a1, 'f0700000-0000-0000-0000-000000000043');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] C4: expected_version obsoleto deveria ser CONFLICT';
  end if;
  select g.progresso_percentual, g.version into v_meta
    from public.evaluation_goals g where g.id = v_g1;
  if v_meta.progresso_percentual <> 100 or v_meta.version <> 2 then
    raise exception '[FAIL] C4: a recusa por versao alterou o estado (progresso=%, version=%)',
      v_meta.progresso_percentual, v_meta.version;
  end if;

  -- (C5) mesma operacao com intencao divergente => CONFLICT.
  v_ok := false;
  begin
    perform public.meta_atualizar_progresso(v_g1, v_alfa, 'intencao divergente', 42, 2,
      v_a1, 'f0700000-0000-0000-0000-000000000042');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] C5: intencao divergente no mesmo operation_id deveria ser CONFLICT';
  end if;
  if exists (
    select 1 from public.evaluation_goal_events
     where organization_id = v_alfa
       and operation_id = 'f0700000-0000-0000-0000-000000000043'
  ) then
    raise exception '[FAIL] C5: operacao recusada gravou evento';
  end if;

  raise notice '[PASS] C: progresso fora de 0..100 recusado sem efeito; 0 e 100 aceitos com version+1 e evento PROGRESSO_ATUALIZADO; stale e divergencia negados';
end $$;

-- ============================================================================
-- 6) D) Edicao do CONTEUDO PERMITIDO (definicao da meta)
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_col1  uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_a1    uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_fixv  uuid := 'f0900000-0000-0000-0000-000000000008';
  v_g1    uuid;
  v_res   jsonb;
  v_meta  record;
  v_evt   record;
  v_ok    boolean;
begin
  select g.id into v_g1 from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo
     and g.collaborator_id = v_col1 and g.tipo = 'NEGOCIO_PROJETO';

  -- (D1) expected_version OBSOLETO => CONFLICT, sem efeito.
  v_ok := false;
  begin
    perform public.meta_editar(v_g1, v_alfa, 'edicao com versao obsoleta',
      'kpi obsoleto', 'alvo obsoleto', 0, v_a1,
      'f0700000-0000-0000-0000-000000000050');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] D1: edicao com expected_version obsoleto deveria ser CONFLICT';
  end if;

  -- (D2) edicao VALIDA (version 2 -> 3) com before/after na trilha.
  v_res := public.meta_editar(v_g1, v_alfa, 'Meta de negocio EDITADA (P2)',
    'KPI editado (P2)', '120 unidades (P2)', 2, v_a1,
    'f0700000-0000-0000-0000-000000000051');
  if (v_res->>'version')::int <> 3 or v_res->>'status' <> 'EM_ANDAMENTO' then
    raise exception '[FAIL] D2: edicao deveria devolver version 3/EM_ANDAMENTO (recebido %)', v_res;
  end if;
  select g.descricao, g.kpi, g.valor_alvo, g.version into v_meta
    from public.evaluation_goals g where g.id = v_g1;
  if v_meta.descricao <> 'Meta de negocio EDITADA (P2)' or v_meta.kpi <> 'KPI editado (P2)'
     or v_meta.valor_alvo <> '120 unidades (P2)' or v_meta.version <> 3 then
    raise exception '[FAIL] D2: conteudo/version divergentes apos a edicao';
  end if;
  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f0700000-0000-0000-0000-000000000051';
  if v_evt.event_type <> 'EDITADA' then
    raise exception '[FAIL] D2: evento da edicao deveria ser EDITADA (recebido %)', v_evt.event_type;
  end if;
  if v_evt.before_value->>'descricao' <> 'Meta de negocio soberana (P2)'
     or (v_evt.before_value->>'version')::int <> 2
     or v_evt.after_value->>'descricao' <> 'Meta de negocio EDITADA (P2)'
     or (v_evt.after_value->>'version')::int <> 3 then
    raise exception '[FAIL] D2: before/after da edicao divergentes (% / %)',
      v_evt.before_value, v_evt.after_value;
  end if;

  -- (D3) ciclo NAO-ATIVO => CONFLICT (matriz D12: so ciclo ATIVO permite editar).
  v_ok := false;
  begin
    perform public.meta_editar(v_fixv, v_alfa, 'edicao em ciclo encerrado',
      'kpi de probe', 'alvo de probe', 0, v_a1,
      'f0700000-0000-0000-0000-000000000052');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] D3: edicao em ciclo ENCERRADO deveria ser CONFLICT';
  end if;
  if exists (
    select 1 from public.evaluation_goals g
     where g.id = v_fixv
       and (g.version <> 0 or g.descricao <> 'Meta viva em ciclo ENCERRADO (fixture P2)')
  ) then
    raise exception '[FAIL] D3: a recusa por ciclo alterou a meta de fixture';
  end if;

  -- (D4) textos em branco/bordas => INVALID_INPUT sem efeito.
  v_ok := false;
  begin
    perform public.meta_editar(v_g1, v_alfa, '  ', 'kpi', 'alvo', 3, v_a1,
      'f0700000-0000-0000-0000-000000000053');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] D4: edicao com descricao em branco deveria ser INVALID_INPUT';
  end if;
  if exists (select 1 from public.evaluation_goals g where g.id = v_g1 and g.version <> 3) then
    raise exception '[FAIL] D4: a recusa por texto alterou a version';
  end if;

  -- (D5) mesmo operation_id com intencao divergente => CONFLICT.
  v_ok := false;
  begin
    perform public.meta_editar(v_g1, v_alfa, 'intencao divergente de edicao',
      'kpi divergente', 'alvo divergente', 3, v_a1,
      'f0700000-0000-0000-0000-000000000051');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] D5: intencao divergente no mesmo operation_id deveria ser CONFLICT';
  end if;

  raise notice '[PASS] D: edicao valida da definicao (version+1, before/after) e recusas sem efeito (version obsoleta, ciclo ENCERRADO, texto em branco e intencao divergente)';
end $$;

-- ============================================================================
-- 7) E) Finalizacao coerente (1a finalizacao explicita; sem aprovacao)
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_col1  uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_col2  uuid := 'f0b00000-0000-0000-0000-000000000002';
  v_a1    uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_g1    uuid;
  v_g2    uuid;
  v_res   jsonb;
  v_meta  record;
  v_evt   record;
  v_ok    boolean;
  v_aprov int;
begin
  select g.id into v_g1 from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo
     and g.collaborator_id = v_col1 and g.tipo = 'NEGOCIO_PROJETO';
  select g.id into v_g2 from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo
     and g.collaborator_id = v_col2 and g.tipo = 'NEGOCIO_PROJETO';

  -- (E1) fechamento INCOERENTE: resultado_final em branco => INVALID_INPUT.
  v_ok := false;
  begin
    perform public.meta_finalizar(v_g2, v_alfa, '   ', true, 0, v_a1,
      'f0700000-0000-0000-0000-000000000060');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] E1: resultado_final em branco deveria ser INVALID_INPUT';
  end if;

  -- (E2) fechamento INCOERENTE: atingida ausente => INVALID_INPUT.
  v_ok := false;
  begin
    perform public.meta_finalizar(v_g2, v_alfa, 'fechamento sem atingida', null, 0, v_a1,
      'f0700000-0000-0000-0000-000000000061');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] E2: finalizacao sem atingida deveria ser INVALID_INPUT';
  end if;
  if exists (
    select 1 from public.evaluation_goals g
     where g.id = v_g2 and (g.status <> 'EM_ANDAMENTO' or g.version <> 0)
  ) then
    raise exception '[FAIL] E1/E2: fechamento incoerente alterou o estado';
  end if;

  -- (E3) finalizacao NAO_ATINGIDA coerente (version 0 -> 1).
  v_res := public.meta_finalizar(v_g2, v_alfa, 'meta nao atingida no periodo (P2)',
    false, 0, v_a1, 'f0700000-0000-0000-0000-000000000062');
  if v_res->>'status' <> 'NAO_ATINGIDA' or (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] E3: finalizacao NAO_ATINGIDA divergente (%)', v_res;
  end if;
  select g.status, g.atingida, g.resultado_final, g.data_fechamento, g.version into v_meta
    from public.evaluation_goals g where g.id = v_g2;
  if v_meta.status <> 'NAO_ATINGIDA' or v_meta.atingida is not false
     or v_meta.resultado_final <> 'meta nao atingida no periodo (P2)'
     or v_meta.data_fechamento is null or v_meta.version <> 1 then
    raise exception '[FAIL] E3: fechamento NAO_ATINGIDA incoerente no banco';
  end if;

  -- (E4) re-finalizacao SILENCIOSA nao existe => CONFLICT (use a revisao).
  v_ok := false;
  begin
    perform public.meta_finalizar(v_g2, v_alfa, 'segunda finalizacao', true, 1, v_a1,
      'f0700000-0000-0000-0000-000000000063');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] E4: re-finalizacao deveria ser CONFLICT (operacao explicita de revisao)';
  end if;

  -- (E5) finalizacao ATINGIDA coerente (G1: version 3 -> 4).
  v_res := public.meta_finalizar(v_g1, v_alfa, 'meta atingida no periodo (P2)',
    true, 3, v_a1, 'f0700000-0000-0000-0000-000000000064');
  if v_res->>'status' <> 'ATINGIDA' or (v_res->>'version')::int <> 4 then
    raise exception '[FAIL] E5: finalizacao ATINGIDA divergente (%)', v_res;
  end if;
  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f0700000-0000-0000-0000-000000000064';
  if v_evt.event_type <> 'FINALIZADA'
     or (v_evt.before_value->>'resultado_final') is not null
     or v_evt.after_value->>'atingida' <> 'true' then
    raise exception '[FAIL] E5: evento FINALIZADA divergente (% / %)',
      v_evt.before_value, v_evt.after_value;
  end if;

  -- (E6) lifecycle: editar/progredir meta FINALIZADA => CONFLICT.
  v_ok := false;
  begin
    perform public.meta_editar(v_g1, v_alfa, 'edicao apos finalizar',
      'kpi apos finalizar', 'alvo apos finalizar', 4, v_a1,
      'f0700000-0000-0000-0000-000000000065');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] E6: edicao de meta ATINGIDA deveria ser CONFLICT (lifecycle)';
  end if;

  v_ok := false;
  begin
    perform public.meta_atualizar_progresso(v_g1, v_alfa, 'progresso apos finalizar',
      50, 4, v_a1, 'f0700000-0000-0000-0000-000000000066');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] E6: progresso em meta ATINGIDA deveria ser CONFLICT (lifecycle)';
  end if;

  -- (E7) NENHUMA aprovacao foi criada/exigida pela finalizacao (D17).
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id = v_alfa;
  if v_aprov <> 0 then
    raise exception '[FAIL] E7: finalizacao criou aprovacao incidentalmente (%)', v_aprov;
  end if;

  raise notice '[PASS] E: fechamento incoerente recusado; ATINGIDA e NAO_ATINGIDA coerentes aceitos; re-finalizacao silenciosa inexistente; editar/progredir meta finalizada negados; NENHUMA aprovacao envolvida';
end $$;

-- ============================================================================
-- 8) F) Revisao de fechamento (fechamento anterior recuperavel na trilha)
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_col1  uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_col2  uuid := 'f0b00000-0000-0000-0000-000000000002';
  v_a1    uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_fixf  uuid := 'f0900000-0000-0000-0000-000000000009';
  v_g2    uuid;
  v_g3    uuid;
  v_res   jsonb;
  v_meta  record;
  v_evt   record;
  v_ok    boolean;
begin
  select g.id into v_g2 from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo
     and g.collaborator_id = v_col2 and g.tipo = 'NEGOCIO_PROJETO';
  select g.id into v_g3 from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo
     and g.collaborator_id = v_col1 and g.tipo = 'INDIVIDUAL';

  -- (F1) revisao VALIDA de NAO_ATINGIDA para ATINGIDA (version 1 -> 2).
  v_res := public.meta_revisar_finalizacao(v_g2, v_alfa,
    'fechamento revisado: meta atingida (P2)', true, 'revisao de fechamento (P2)', 1,
    v_a1, 'f0700000-0000-0000-0000-000000000070');
  if v_res->>'status' <> 'ATINGIDA' or (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] F1: revisao deveria devolver ATINGIDA/version 2 (recebido %)', v_res;
  end if;
  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f0700000-0000-0000-0000-000000000070';
  if v_evt.event_type <> 'REVISAO_FINALIZACAO' then
    raise exception '[FAIL] F1: evento da revisao deveria ser REVISAO_FINALIZACAO (recebido %)',
      v_evt.event_type;
  end if;
  -- O fechamento ANTERIOR esta integralmente recuperavel na trilha (D17).
  if v_evt.before_value->>'status' <> 'NAO_ATINGIDA'
     or v_evt.before_value->>'resultado_final' <> 'meta nao atingida no periodo (P2)'
     or v_evt.before_value->>'atingida' <> 'false'
     or (v_evt.before_value->>'version')::int <> 1
     or (v_evt.before_value->>'data_fechamento') is null then
    raise exception '[FAIL] F1: before_value nao preserva o fechamento anterior (%)',
      v_evt.before_value;
  end if;
  if v_evt.reason <> 'revisao de fechamento (P2)' then
    raise exception '[FAIL] F1: motivo da revisao nao foi registrado';
  end if;
  if v_evt.after_value->>'resultado_final' <> 'fechamento revisado: meta atingida (P2)'
     or v_evt.after_value->>'atingida' <> 'true' then
    raise exception '[FAIL] F1: after_value da revisao divergente (%)', v_evt.after_value;
  end if;

  -- (F2) revisao com expected_version obsoleto => CONFLICT sem efeito.
  v_ok := false;
  begin
    perform public.meta_revisar_finalizacao(v_g2, v_alfa, 'revisao com versao obsoleta',
      false, 'probe de versao', 1, v_a1, 'f0700000-0000-0000-0000-000000000071');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] F2: revisao com expected_version obsoleto deveria ser CONFLICT';
  end if;

  -- (F3) revisao de meta EM_ANDAMENTO => CONFLICT (operacao propria de finalizar).
  v_ok := false;
  begin
    perform public.meta_revisar_finalizacao(v_g3, v_alfa, 'revisao indevida',
      true, 'probe de lifecycle', 0, v_a1, 'f0700000-0000-0000-0000-000000000072');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] F3: revisao de meta EM_ANDAMENTO deveria ser CONFLICT';
  end if;

  -- (F4) revisar NAO exige ciclo ATIVO: a meta de fixture esta em ciclo ENCERRADO.
  v_res := public.meta_revisar_finalizacao(v_fixf, v_alfa,
    'fechamento de fixture revisado (P2)', true, 'revisao em ciclo encerrado (P2)', 1,
    v_a1, 'f0700000-0000-0000-0000-000000000073');
  if (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] F4: revisao em ciclo ENCERRADO deveria concluir (recebido %)', v_res;
  end if;

  -- (F5) resultado_final em branco => INVALID_INPUT sem efeito.
  v_ok := false;
  begin
    perform public.meta_revisar_finalizacao(v_fixf, v_alfa, '   ', true, 'probe de texto',
      2, v_a1, 'f0700000-0000-0000-0000-000000000074');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] F5: revisao com resultado_final em branco deveria ser INVALID_INPUT';
  end if;
  select g.version, g.resultado_final into v_meta
    from public.evaluation_goals g where g.id = v_fixf;
  if v_meta.version <> 2 or v_meta.resultado_final <> 'fechamento de fixture revisado (P2)' then
    raise exception '[FAIL] F5: a recusa por texto alterou o fechamento revisado';
  end if;

  raise notice '[PASS] F: revisao de fechamento explicita com fechamento anterior recuperavel na trilha; EM_ANDAMENTO, versao obsoleta e texto em branco negados; revisar nao exige ciclo ATIVO';
end $$;

-- ============================================================================
-- 9) G) Exclusao LOGICA (linha preservada) e meta excluida sem mutacao
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_cicb  uuid := 'f0d10000-0000-0000-0000-0000000000b1';
  v_col1  uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_colb  uuid := 'f0b00000-0000-0000-0000-0000000000b1';
  v_a1    uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_abeta uuid := 'f0c00000-0000-0000-0000-000000000002';
  v_fixv  uuid := 'f0900000-0000-0000-0000-000000000008';
  v_g3    uuid;
  v_g4    uuid;
  v_meta  record;
  v_evt   record;
  v_ok    boolean;
  v_n     int;
  v_rec   int;
begin
  select g.id into v_g3 from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo
     and g.collaborator_id = v_col1 and g.tipo = 'INDIVIDUAL';
  select g.id into v_g4 from public.evaluation_goals g
   where g.organization_id = v_beta and g.cycle_id = v_cicb
     and g.collaborator_id = v_colb;

  -- (G1) exclusao LOGICA de meta viva (version 0 -> 1); a LINHA permanece.
  perform public.meta_excluir(v_g3, v_alfa, 'meta individual cancelada (P2)', 0, v_a1,
    'f0700000-0000-0000-0000-000000000080');
  select g.status, g.excluida, g.data_exclusao, g.version into v_meta
    from public.evaluation_goals g where g.id = v_g3;
  if v_meta.excluida is not true or v_meta.data_exclusao is null
     or v_meta.version <> 1 or v_meta.status <> 'EM_ANDAMENTO' then
    raise exception '[FAIL] G1: exclusao logica incoerente (excluida=%, data=%, version=%, status=%)',
      v_meta.excluida, v_meta.data_exclusao, v_meta.version, v_meta.status;
  end if;
  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f0700000-0000-0000-0000-000000000080';
  if v_evt.event_type <> 'EXCLUIDA' or v_evt.reason <> 'meta individual cancelada (P2)'
     or v_evt.after_value->>'excluida' <> 'true'
     or v_evt.before_value->>'excluida' <> 'false' then
    raise exception '[FAIL] G1: evento EXCLUIDA divergente (%)', v_evt.after_value;
  end if;

  -- (G2) exclusao de meta JA excluida => CONFLICT (terminal).
  v_ok := false;
  begin
    perform public.meta_excluir(v_g3, v_alfa, 'segunda exclusao', 1, v_a1,
      'f0700000-0000-0000-0000-000000000081');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] G2: segunda exclusao deveria ser CONFLICT';
  end if;

  -- (G3) excluir NAO exige ciclo ATIVO: a meta de fixture esta em ciclo ENCERRADO.
  perform public.meta_excluir(v_fixv, v_alfa, 'meta viva de ciclo encerrado (P2)', 0, v_a1,
    'f0700000-0000-0000-0000-000000000082');
  select g.excluida, g.data_exclusao, g.version into v_meta
    from public.evaluation_goals g where g.id = v_fixv;
  if v_meta.excluida is not true or v_meta.data_exclusao is null or v_meta.version <> 1 then
    raise exception '[FAIL] G3: exclusao em ciclo ENCERRADO nao concluiu';
  end if;

  -- (G4) motivo em branco => INVALID_INPUT e versao obsoleta => CONFLICT (sem efeito).
  v_ok := false;
  begin
    perform public.meta_excluir(v_g4, v_beta, '  ', 0, v_abeta,
      'f0700000-0000-0000-0000-000000000083');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] G4: exclusao sem motivo deveria ser INVALID_INPUT';
  end if;
  v_ok := false;
  begin
    perform public.meta_excluir(v_g4, v_beta, 'probe de versao', 9, v_abeta,
      'f0700000-0000-0000-0000-000000000084');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] G4: exclusao com expected_version obsoleto deveria ser CONFLICT';
  end if;
  if exists (select 1 from public.evaluation_goals g where g.id = v_g4 and g.excluida) then
    raise exception '[FAIL] G4: recusa de exclusao alterou a meta de Beta';
  end if;

  -- (G5) meta EXCLUIDA nao aceita NENHUMA mutacao (5 operacoes).
  v_ok := false;
  begin
    perform public.meta_editar(v_g3, v_alfa, 'edicao em meta excluida', 'kpi', 'alvo', 1,
      v_a1, 'f0700000-0000-0000-0000-000000000085');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then raise exception '[FAIL] G5: editar meta excluida deveria ser CONFLICT'; end if;

  v_ok := false;
  begin
    perform public.meta_atualizar_progresso(v_g3, v_alfa, 'progresso em meta excluida', 10, 1,
      v_a1, 'f0700000-0000-0000-0000-000000000086');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then raise exception '[FAIL] G5: progredir meta excluida deveria ser CONFLICT'; end if;

  v_ok := false;
  begin
    perform public.meta_finalizar(v_g3, v_alfa, 'finalizacao em meta excluida', true, 1,
      v_a1, 'f0700000-0000-0000-0000-000000000087');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then raise exception '[FAIL] G5: finalizar meta excluida deveria ser CONFLICT'; end if;

  v_ok := false;
  begin
    perform public.meta_revisar_finalizacao(v_g3, v_alfa, 'revisao em meta excluida', true,
      'probe', 1, v_a1, 'f0700000-0000-0000-0000-000000000088');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then raise exception '[FAIL] G5: revisar meta excluida deveria ser CONFLICT'; end if;

  v_ok := false;
  begin
    perform public.meta_excluir(v_g3, v_alfa, 're-exclusao', 1, v_a1,
      'f0700000-0000-0000-0000-000000000089');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then raise exception '[FAIL] G5: re-excluir meta excluida deveria ser CONFLICT'; end if;

  -- Nenhuma das recusas alterou a meta excluida nem gravou evento.
  select g.version into v_meta from public.evaluation_goals g where g.id = v_g3;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g3;
  select count(*) into v_rec from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id in ('f0700000-0000-0000-0000-000000000085',
                            'f0700000-0000-0000-0000-000000000086',
                            'f0700000-0000-0000-0000-000000000087',
                            'f0700000-0000-0000-0000-000000000088',
                            'f0700000-0000-0000-0000-000000000089');
  if v_meta.version <> 1 or v_n <> 2 or v_rec <> 0 then
    raise exception '[FAIL] G5: recusas deixaram efeito (version=%, eventos da meta=%, eventos das recusas=%)',
      v_meta.version, v_n, v_rec;
  end if;

  raise notice '[PASS] G: exclusao logica (linha preservada, um evento EXCLUIDA) e meta excluida recusando editar/progredir/finalizar/revisar/re-excluir sem nenhum efeito';
end $$;

-- ============================================================================
-- 10) I) A quota continua autoridade do BANCO (nao apenas da RPC)
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_cicb  uuid := 'f0d10000-0000-0000-0000-0000000000b1';
  v_col1  uuid := 'f0b00000-0000-0000-0000-000000000001';
  v_colb  uuid := 'f0b00000-0000-0000-0000-0000000000b1';
  v_ok    boolean;
  v_msg   text;
  v_n     int;
begin
  -- (I1) INSERT DIRETO acima da quota => recusado pelo trigger da P1: o banco e a
  --      autoridade; a leitura sob o lock dentro da RPC e apenas a mensagem estavel.
  v_ok := false; v_msg := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_alfa, v_ciclo, v_col1, 'NEGOCIO_PROJETO',
            'probe direto acima da quota', 'kpi de probe', 'alvo de probe');
  exception when others then v_ok := sqlerrm like '%F5-10: quota%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] I1: INSERT direto acima da quota deveria violar o invariante do banco (recebido %)', v_msg;
  end if;

  -- (I2) INSERT DIRETO de tipo SEM quota (Beta/INDIVIDUAL) => fail-closed.
  v_ok := false; v_msg := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_beta, v_cicb, v_colb, 'INDIVIDUAL',
            'probe direto sem quota', 'kpi de probe', 'alvo de probe');
  exception when others then v_ok := sqlerrm like '%F5-10: quota%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] I2: INSERT direto sem quota configurada deveria ser recusado (recebido %)', v_msg;
  end if;

  -- (I3) INSERT DIRETO cross-tenant => barrado pelo BANCO (quota ou FK composta).
  v_ok := false; v_msg := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_alfa, v_ciclo, v_colb, 'INDIVIDUAL',
            'probe direto cross-tenant', 'kpi de probe', 'alvo de probe');
  exception when others then v_ok := (sqlstate = '23503' or sqlerrm like '%quota%'); v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] I3: INSERT direto cross-tenant deveria ser barrado pelo banco (recebido %)', v_msg;
  end if;

  -- Nenhum probe direto deixou residuo (5 metas em Alfa + 1 em Beta).
  select count(*) into v_n from public.evaluation_goals
   where organization_id in (v_alfa, v_beta);
  if v_n <> 6 then
    raise exception '[FAIL] I: os probes diretos alteraram o estado (metas=%)', v_n;
  end if;

  raise notice '[PASS] I: quota e isolamento continuam invariantes do BANCO (INSERT direto acima da quota, tipo sem quota e cross-tenant barrados pelo PostgreSQL, nao apenas pela RPC)';
end $$;

-- ============================================================================
-- 11) J) ACL, lock normativo e anti-escopo (P3/P4/P5/D21 nao antecipadas)
-- ============================================================================
do $$
declare
  v_fns  text[] := array[
    'meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)'];
  v_fn   text;
  v_rec  record;
  v_tab  text;
  v_prob text[] := array[]::text[];
  v_n    int;
  v_msg  text;
  v_ok   boolean;
  v_alvo uuid := 'f0900000-0000-0000-0000-000000000008';
begin
  -- (J1) superficie das 7 RPCs: INVOKER, search_path, EXECUTE e LOCK normativo.
  foreach v_fn in array v_fns loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config,
           lower(pg_get_functiondef(p.oid)) as def
      into v_rec
      from pg_proc p where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      v_prob := v_prob || ('ausente: ' || v_fn);
      continue;
    end if;
    if v_rec.prosecdef then
      v_prob := v_prob || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_prob := v_prob || ('sem search_path fixo: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_prob := v_prob || ('sem EXECUTE para service_role: ' || v_fn);
    end if;
    if has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE') then
      v_prob := v_prob || ('EXECUTE exposto a anon/authenticated: ' || v_fn);
    end if;
    if position('ciclo_lock_organizacao' in v_rec.def) = 0 then
      v_prob := v_prob || ('sem lock normativo da familia de ciclos: ' || v_fn);
    end if;
    if position('pg_advisory_xact_lock' in v_rec.def) > 0
       or position('position_reporting_lines:' in v_rec.def) > 0
       or position('f5_07_estrutura:' in v_rec.def) > 0 then
      v_prob := v_prob || ('lock de OUTRA familia: ' || v_fn);
    end if;
    if position('delete from' in v_rec.def) > 0 or position('truncate' in v_rec.def) > 0 then
      v_prob := v_prob || ('RPC com DELETE/TRUNCATE (exclusao fisica proibida): ' || v_fn);
    end if;
  end loop;

  -- (J2) anti-escopo: NENHUMA outra RPC de meta/goal (nem de fase futura).
  --      D21 (`meta_definir_limites_do_ciclo`, P2) e as operacoes de aprovacao
  --      (`meta_aprovar`/`meta_invalidar_aprovacoes`, P3) sao contrato das fases
  --      ja implementadas e por isso estao na LISTA FECHADA; leitura com gate,
  --      Policy Engine e RLS funcional seguem proibidas.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%')
     and p.proname <> all (array[
       'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
       'meta_revisar_finalizacao', 'meta_excluir', 'meta_definir_limites_do_ciclo',
       'meta_aprovar', 'meta_invalidar_aprovacoes']);
  if v_n <> 0 then
    v_prob := v_prob || format('%s RPC(s) de meta fora do contrato das P2/P3', v_n);
  end if;
  foreach v_fn in array array[
    'meta_listar_por_escopo', 'goal_listar', 'goal_aprovar'] loop
    if exists (
      select 1 from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname = v_fn
    ) then
      v_prob := v_prob || ('antecipacao de fase futura: ' || v_fn);
    end if;
  end loop;

  -- (J3) deny-by-default: nenhuma policy e nenhum privilegio de cliente.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = v_tab) then
      v_prob := v_prob || ('policy criada em ' || v_tab || ' (P4 nao antecipada)');
    end if;
    if has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'DELETE')
       or has_table_privilege('anon', 'public.' || v_tab, 'SELECT') then
      v_prob := v_prob || ('privilegio de cliente em ' || v_tab);
    end if;
    if has_table_privilege('service_role', 'public.' || v_tab, 'DELETE')
       or has_table_privilege('service_role', 'public.' || v_tab, 'TRUNCATE') then
      v_prob := v_prob || ('service_role com DELETE/TRUNCATE em ' || v_tab);
    end if;
  end loop;

  -- (J4) D2/D3: nenhuma representacao de aprovacao/matricula dentro da meta.
  if exists (
    select 1 from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'evaluation_goals'
       and (c.column_name like '%aprov%' or c.column_name like '%matricula%')
  ) then
    v_prob := v_prob || 'coluna de aprovacao/matricula dentro de evaluation_goals (D2/D3)';
  end if;

  if array_length(v_prob, 1) is not null then
    raise exception '[FAIL] J: %', array_to_string(v_prob, '; ');
  end if;

  -- (J5) DELETE FISICO negado no proprio banco (inclusive a service_role).
  v_ok := false; v_msg := null;
  begin
    set role service_role;
    delete from public.evaluation_goals where id = v_alvo;
    reset role;
  exception when others then
    v_ok := (sqlstate = '42501' or sqlerrm like '%append-only%');
    v_msg := sqlerrm;
    reset role;
  end;
  if not v_ok then
    raise exception '[FAIL] J5: DELETE de meta por service_role deveria ser negado (recebido %)', v_msg;
  end if;
  if not exists (select 1 from public.evaluation_goals g where g.id = v_alvo) then
    raise exception '[FAIL] J5: a meta foi APAGADA fisicamente';
  end if;

  v_ok := false; v_msg := null;
  begin
    set role service_role;
    delete from public.evaluation_goal_events
     where organization_id = 'f0a00000-0000-0000-0000-0000000000a1';
    reset role;
  exception when others then
    v_ok := (sqlstate = '42501' or sqlerrm like '%append-only%');
    v_msg := sqlerrm;
    reset role;
  end;
  if not v_ok then
    raise exception '[FAIL] J5: DELETE da trilha por service_role deveria ser negado (recebido %)', v_msg;
  end if;

  -- (J6) nenhuma capability nova (D6): catalogo de metas/observacoes continua 8.
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    raise exception '[FAIL] J6: capabilities de metas/observacoes = % (esperado 8)', v_n;
  end if;

  raise notice '[PASS] J: 7 RPCs INVOKER com lock normativo unico, EXECUTE so service_role, zero policy/privilegio de cliente, DELETE fisico negado no banco e nenhuma fase futura antecipada';
end $$;

-- ============================================================================
-- 12) K) Nenhuma aprovacao incidental (P3 nao antecipada)
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_aprov int;
  v_evt   int;
begin
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in (v_alfa, v_beta);
  if v_aprov <> 0 then
    raise exception '[FAIL] K: as operacoes da P2 criaram % aprovacao(oes) incidentalmente', v_aprov;
  end if;

  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in (v_alfa, v_beta)
     and event_type in ('APROVACAO_COORDENADOR', 'APROVACAO_GERENTE', 'APROVACAO_INVALIDADA');
  if v_evt <> 0 then
    raise exception '[FAIL] K: evento de aprovacao emitido pela P2 (%)', v_evt;
  end if;

  -- O status funcional NAO representa aprovacao: existem metas finalizadas com
  -- ZERO aprovacoes na organizacao (D3/D17) e nenhuma foi exigida.
  if not exists (
    select 1 from public.evaluation_goals g
     where g.organization_id = v_alfa and g.status in ('ATINGIDA', 'NAO_ATINGIDA')
  ) then
    raise exception '[FAIL] K: pre-condicao — nenhuma meta finalizada em Alfa';
  end if;

  -- A tabela de aprovacoes da P1 continua existindo (nao removida nem duplicada).
  if to_regclass('public.evaluation_goal_approvals') is null then
    raise exception '[FAIL] K: tabela de aprovacoes da P1 foi removida';
  end if;

  raise notice '[PASS] K: status funcional independente de aprovacao — nenhuma aprovacao criada, nenhum evento APROVACAO_* e nenhuma exigencia de aprovacao na P2';
end $$;

-- ============================================================================
-- 13) L) Estado final deterministico (nenhum residuo dos testes negativos)
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_metas int;
  v_vivas int;
  v_excl  int;
  v_aprov int;
  v_evt   int;
  v_tipo  text;
  v_rec   record;
begin
  select count(*) into v_metas from public.evaluation_goals where organization_id = v_alfa;
  if v_metas <> 5 then
    raise exception '[FAIL] L: Alfa deveria terminar com 5 metas (3 do ciclo ATIVO + 2 de fixture), encontrado %', v_metas;
  end if;
  select count(*) into v_metas from public.evaluation_goals where organization_id = v_beta;
  if v_metas <> 1 then
    raise exception '[FAIL] L: Beta deveria terminar com 1 meta, encontrado %', v_metas;
  end if;

  select count(*) into v_vivas from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo and g.excluida = false;
  select count(*) into v_excl from public.evaluation_goals g
   where g.organization_id = v_alfa and g.excluida = true;
  -- Vivas no ciclo ATIVO = as duas metas de negocio (a individual foi excluida
  -- logicamente e portanto NAO consome quota); excluidas em Alfa = 2 (a individual
  -- do ciclo ATIVO + a viva de fixture do ciclo ENCERRADO).
  if v_vivas <> 2 or v_excl <> 2 then
    raise exception '[FAIL] L: estado final inesperado (vivas no ciclo ATIVO=%, excluidas=%)',
      v_vivas, v_excl;
  end if;

  -- Versoes e estados finais, meta a meta (nenhum "residuo" dos negativos).
  for v_rec in
    select g.collaborator_id, g.tipo, g.status, g.version, g.excluida
      from public.evaluation_goals g
     where g.organization_id = v_alfa and g.cycle_id = v_ciclo
     order by g.collaborator_id, g.tipo
  loop
    if v_rec.tipo = 'NEGOCIO_PROJETO'
       and v_rec.collaborator_id = 'f0b00000-0000-0000-0000-000000000001' then
      if v_rec.status <> 'ATINGIDA' or v_rec.version <> 4 or v_rec.excluida then
        raise exception '[FAIL] L: meta de negocio do colaborador 1 deveria ser ATINGIDA/version 4 (status=%, version=%, excluida=%)',
          v_rec.status, v_rec.version, v_rec.excluida;
      end if;
    elsif v_rec.tipo = 'NEGOCIO_PROJETO'
          and v_rec.collaborator_id = 'f0b00000-0000-0000-0000-000000000002' then
      if v_rec.status <> 'ATINGIDA' or v_rec.version <> 2 or v_rec.excluida then
        raise exception '[FAIL] L: meta de negocio do colaborador 2 deveria ser ATINGIDA/version 2 apos revisao (status=%, version=%, excluida=%)',
          v_rec.status, v_rec.version, v_rec.excluida;
      end if;
    elsif v_rec.tipo = 'INDIVIDUAL' then
      if v_rec.status <> 'EM_ANDAMENTO' or v_rec.version <> 1 or not v_rec.excluida then
        raise exception '[FAIL] L: meta individual deveria estar excluida logicamente/version 1 (status=%, version=%, excluida=%)',
          v_rec.status, v_rec.version, v_rec.excluida;
      end if;
    end if;
  end loop;

  -- Trilha: um evento por operacao oficial, tipos do contrato e totais exatos.
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id = v_alfa;
  if v_evt <> 13 then
    raise exception '[FAIL] L: trilha de Alfa deveria ter 13 eventos, encontrado %', v_evt;
  end if;
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id = v_beta;
  if v_evt <> 1 then
    raise exception '[FAIL] L: trilha de Beta deveria ter 1 evento, encontrado %', v_evt;
  end if;

  for v_rec in
    select e.event_type as tipo, count(*) as qtd
      from public.evaluation_goal_events e
     where e.organization_id in (v_alfa, v_beta)
     group by e.event_type
  loop
    v_tipo := v_rec.tipo;
    if (v_tipo = 'CRIADA' and v_rec.qtd <> 4)
       or (v_tipo = 'PROGRESSO_ATUALIZADO' and v_rec.qtd <> 2)
       or (v_tipo = 'EDITADA' and v_rec.qtd <> 1)
       or (v_tipo = 'FINALIZADA' and v_rec.qtd <> 3)
       or (v_tipo = 'REVISAO_FINALIZACAO' and v_rec.qtd <> 2)
       or (v_tipo = 'EXCLUIDA' and v_rec.qtd <> 2) then
      raise exception '[FAIL] L: contagem inesperada de % (%)', v_tipo, v_rec.qtd;
    end if;
  end loop;

  -- Um evento por operation_id (idempotencia) em toda a trilha da P2.
  select count(*) into v_evt from (
    select e.operation_id from public.evaluation_goal_events e
     where e.organization_id in (v_alfa, v_beta)
     group by e.operation_id having count(*) > 1
  ) t;
  if v_evt <> 0 then
    raise exception '[FAIL] L: operation_id duplicado na trilha (%)', v_evt;
  end if;

  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in (v_alfa, v_beta);
  if v_aprov <> 0 then
    raise exception '[FAIL] L: estado final com % aprovacao(oes) inesperada(s)', v_aprov;
  end if;

  -- Nenhum artefato de mutacao deixado para tras pelo validador.
  select count(*) into v_evt from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_f5\_10\_p2%';
  if v_evt <> 0 then
    raise exception '[FAIL] L: artefato de mutacao deixado no schema (%)', v_evt;
  end if;

  raise notice '[PASS] L: estado final deterministico (Alfa 5 metas/13 eventos, Beta 1 meta/1 evento, 2 exclusoes logicas, 0 aprovacoes e nenhum residuo)';
end $$;

-- ============================================================================
-- 14) M) D21 — LIMITES DO CICLO (meta_definir_limites_do_ciclo)
-- ============================================================================
-- Decisao de review: o evento `LIMITES_DO_CICLO_ALTERADOS` vive em `cycle_events`
-- (configuracao do CICLO), NUNCA em `evaluation_goal_events`. Este bloco roda
-- depois do estado final (bloco L) justamente para provar que a operacao de
-- limites NAO toca a trilha nem as metas.
-- Pre-condicao: ciclo ATIVO de Alfa com `version = 1` e limites {NP: 2, IND: 1};
-- metas vivas do tipo NEGOCIO_PROJETO = 2 (as duas de negocio do ciclo ATIVO).
do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_encer uuid := 'f0d10000-0000-0000-0000-0000000000a2';
  v_cicb  uuid := 'f0d10000-0000-0000-0000-0000000000b1';
  v_beta  uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_a1    uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_abeta uuid := 'f0c00000-0000-0000-0000-000000000002';
  v_adis  uuid := 'f0c00000-0000-0000-0000-000000000003';
  v_aperf uuid := 'f0c00000-0000-0000-0000-000000000004';
  v_r1    jsonb;
  v_r2    jsonb;
  v_evt   record;
  v_ok    boolean;
  v_msg   text;
  v_n     int;
  v_qtd   int;
begin
  -- (M0) Pre-condicao do bloco.
  select c.version into v_n from public.evaluation_cycles c where c.id = v_ciclo;
  if v_n <> 1 then
    raise exception '[FAIL] M0: pre-condicao — ciclo ATIVO de Alfa deveria estar na version 1 (%)', v_n;
  end if;
  select l.quantidade into v_qtd from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'NEGOCIO_PROJETO';
  if v_qtd <> 2 then
    raise exception '[FAIL] M0: pre-condicao — limite inicial de NEGOCIO_PROJETO deveria ser 2 (%)', v_qtd;
  end if;

  -- (M1) ALTERACAO VALIDA (aumento) em ciclo ATIVO: version do CICLO +1 e evento
  --      `LIMITES_DO_CICLO_ALTERADOS` na trilha do CICLO, na mesma transacao.
  v_r1 := public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 3,
    'aumento de limite de metas de negocio (P2)', 1, v_a1,
    'f0700000-0000-0000-0000-000000000090');
  if (v_r1->>'version')::int <> 2 or v_r1->>'tipo' <> 'NEGOCIO_PROJETO'
     or (v_r1->>'quantidade')::int <> 3 then
    raise exception '[FAIL] M1: retorno da alteracao de limites divergente (%)', v_r1;
  end if;
  select c.version into v_n from public.evaluation_cycles c where c.id = v_ciclo;
  if v_n <> 2 then
    raise exception '[FAIL] M1: a version do CICLO deveria ser 2 (%)', v_n;
  end if;
  select l.quantidade into v_qtd from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'NEGOCIO_PROJETO';
  if v_qtd <> 3 then
    raise exception '[FAIL] M1: o limite gravado deveria ser 3 (%)', v_qtd;
  end if;
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f0700000-0000-0000-0000-000000000090';
  if v_evt.id is null then
    raise exception '[FAIL] M1: evento LIMITES_DO_CICLO_ALTERADOS ausente em cycle_events';
  end if;
  if v_evt.event_type <> 'LIMITES_DO_CICLO_ALTERADOS'
     or v_evt.entity_type <> 'evaluation_cycle' then
    raise exception '[FAIL] M1: evento deveria ser LIMITES_DO_CICLO_ALTERADOS/evaluation_cycle (%/%)',
      v_evt.event_type, v_evt.entity_type;
  end if;
  if v_evt.cycle_id <> v_ciclo or v_evt.result_entity_id <> v_ciclo then
    raise exception '[FAIL] M1: o evento deveria apontar o ciclo (cycle_id/result_entity_id)';
  end if;
  if v_evt.actor_user_profile_id <> v_a1
     or v_evt.actor_membership_id <> 'f0d00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] M1: autoria soberana do evento de limites incorreta';
  end if;
  if v_evt.reason <> 'aumento de limite de metas de negocio (P2)' then
    raise exception '[FAIL] M1: motivo do evento de limites nao registrado';
  end if;
  if v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] M1: payload_hash do evento de limites fora do formato SHA-256';
  end if;
  -- before_value preserva os limites ANTERIORES e a version anterior.
  if v_evt.before_value->'limites'->>'NEGOCIO_PROJETO' <> '2'
     or v_evt.before_value->'limites'->>'INDIVIDUAL' <> '1'
     or (v_evt.before_value->>'version')::int <> 1
     or (v_evt.before_value->>'quantidade')::int <> 2 then
    raise exception '[FAIL] M1: before_value nao preserva os limites anteriores (%)', v_evt.before_value;
  end if;
  -- after_value registra os NOVOS limites e a NOVA version do ciclo.
  if v_evt.after_value->'limites'->>'NEGOCIO_PROJETO' <> '3'
     or v_evt.after_value->'limites'->>'INDIVIDUAL' <> '1'
     or (v_evt.after_value->>'version')::int <> 2
     or v_evt.after_value->>'tipo' <> 'NEGOCIO_PROJETO'
     or (v_evt.after_value->>'quantidade')::int <> 3 then
    raise exception '[FAIL] M1: after_value nao registra os novos limites/version (%)', v_evt.after_value;
  end if;

  -- NENHUM evento no dominio de metas (o limite e configuracao do CICLO).
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.event_type = 'LIMITES_DO_CICLO_ALTERADOS';
  if v_n <> 0 then
    raise exception '[FAIL] M1: LIMITES_DO_CICLO_ALTERADOS vazou para evaluation_goal_events (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa;
  if v_n <> 13 then
    raise exception '[FAIL] M1: a trilha de metas foi alterada pela operacao de limites (%)', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_alfa and e.cycle_id = v_ciclo;
  if v_n <> 1 then
    raise exception '[FAIL] M1: esperado exatamente 1 evento de ciclo para a operacao (%)', v_n;
  end if;

  -- (M2) REPLAY IDENTICO: mesmo resultado, sem nova mutacao e sem novo evento.
  v_r2 := public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 3,
    'aumento de limite de metas de negocio (P2)', 1, v_a1,
    'f0700000-0000-0000-0000-000000000090');
  if v_r1 <> v_r2 then
    raise exception '[FAIL] M2: replay identico devolveu resultado diferente (% vs %)', v_r1, v_r2;
  end if;
  select c.version into v_n from public.evaluation_cycles c where c.id = v_ciclo;
  select count(*) into v_qtd from public.cycle_events e
   where e.organization_id = v_alfa and e.cycle_id = v_ciclo;
  if v_n <> 2 or v_qtd <> 1 then
    raise exception '[FAIL] M2: replay duplicou mutacao/evento (version=%, eventos=%)', v_n, v_qtd;
  end if;

  -- (M3) OPERATION_ID DIVERGENTE: mesma chave, intencao diferente => CONFLICT.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 0,
      'aumento de limite de metas de negocio (P2)', 2, v_a1,
      'f0700000-0000-0000-0000-000000000090');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] M3: operation_id divergente deveria ser CONFLICT (recebido %)', v_msg;
  end if;
  select l.quantidade into v_qtd from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'NEGOCIO_PROJETO';
  if v_qtd <> 3 then
    raise exception '[FAIL] M3: a recusa por intencao divergente alterou o limite (%)', v_qtd;
  end if;

  -- (M4) STALE expected_version => CONFLICT sem efeito.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 2,
      'reducao com versao obsoleta (P2)', 1, v_a1,
      'f0700000-0000-0000-0000-000000000092');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] M4: expected_version obsoleto deveria ser CONFLICT (recebido %)', v_msg;
  end if;
  select c.version into v_n from public.evaluation_cycles c where c.id = v_ciclo;
  if v_n <> 2 then
    raise exception '[FAIL] M4: a recusa por versao alterou a version do ciclo (%)', v_n;
  end if;

  -- (M5) REDUCAO EXATAMENTE ATE O NUMERO DE METAS VIVAS = ACEITA (2 vivas -> 2).
  v_r1 := public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 2,
    'reducao ate o numero de metas vivas (P2)', 2, v_a1,
    'f0700000-0000-0000-0000-000000000093');
  if (v_r1->>'version')::int <> 3 or (v_r1->>'quantidade')::int <> 2 then
    raise exception '[FAIL] M5: reducao ate o numero de metas vivas deveria ser aceita (%)', v_r1;
  end if;
  select l.quantidade into v_qtd from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'NEGOCIO_PROJETO';
  if v_qtd <> 2 then
    raise exception '[FAIL] M5: o limite apos a reducao deveria ser 2 (%)', v_qtd;
  end if;
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f0700000-0000-0000-0000-000000000093';
  if (v_evt.before_value->>'version')::int <> 2 or (v_evt.after_value->>'version')::int <> 3
     or v_evt.before_value->'limites'->>'NEGOCIO_PROJETO' <> '3'
     or v_evt.after_value->'limites'->>'NEGOCIO_PROJETO' <> '2' then
    raise exception '[FAIL] M5: before/after da reducao divergentes (% / %)',
      v_evt.before_value, v_evt.after_value;
  end if;

  -- (M6) REDUCAO ABAIXO DAS METAS VIVAS => CONFLICT sem efeito.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 1,
      'reducao abaixo das metas vivas (P2)', 3, v_a1,
      'f0700000-0000-0000-0000-000000000094');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] M6: reducao abaixo das metas vivas deveria ser CONFLICT (recebido %)', v_msg;
  end if;
  select c.version into v_n from public.evaluation_cycles c where c.id = v_ciclo;
  select l.quantidade into v_qtd from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'NEGOCIO_PROJETO';
  if v_n <> 3 or v_qtd <> 2 then
    raise exception '[FAIL] M6: a recusa por reducao alterou estado (version=%, limite=%)', v_n, v_qtd;
  end if;

  -- (M6b) o BANCO tambem recusa a reducao abaixo das vivas (autoridade do trigger
  --       da P1, independente da RPC).
  v_ok := false; v_msg := null;
  begin
    update public.evaluation_cycle_goal_limits l
       set quantidade = 1
     where l.organization_id = v_alfa and l.cycle_id = v_ciclo
       and l.tipo = 'NEGOCIO_PROJETO';
  exception when others then v_ok := sqlerrm like '%F5-10: quota%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] M6b: UPDATE direto abaixo das metas vivas deveria violar o invariante do banco (recebido %)', v_msg;
  end if;

  -- (M7) QUANTIDADE fora de 0..3 => INVALID_INPUT sem efeito.
  foreach v_msg in array array['4', '-1'] loop
    v_ok := false;
    begin
      perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO',
        v_msg::integer, 'probe de dominio (P2)', 3, v_a1,
        'f0700000-0000-0000-0000-0000000000a0');
    exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
    end;
    if not v_ok then
      raise exception '[FAIL] M7: quantidade % deveria ser INVALID_INPUT', v_msg;
    end if;
  end loop;
  -- motivo e tipo invalidos tambem sao INVALID_INPUT.
  v_ok := false;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 2,
      '   ', 3, v_a1, 'f0700000-0000-0000-0000-0000000000a1');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] M7: motivo em branco deveria ser INVALID_INPUT';
  end if;
  v_ok := false;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'EQUIPE', 2,
      'probe de tipo (P2)', 3, v_a1, 'f0700000-0000-0000-0000-0000000000a2');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] M7: tipo invalido deveria ser INVALID_INPUT';
  end if;
  select c.version into v_n from public.evaluation_cycles c where c.id = v_ciclo;
  if v_n <> 3 then
    raise exception '[FAIL] M7: probe invalido alterou a version do ciclo (%)', v_n;
  end if;

  -- (M8) CICLO NAO ATIVO => CONFLICT (o ciclo ENCERRADO de Alfa esta na version 3).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_definir_limites_do_ciclo(v_encer, v_alfa, 'NEGOCIO_PROJETO', 3,
      'probe em ciclo encerrado (P2)', 3, v_a1,
      'f0700000-0000-0000-0000-000000000095');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] M8: ciclo nao ATIVO deveria ser CONFLICT (recebido %)', v_msg;
  end if;

  -- (M9) CROSS-TENANT: ciclo de Beta com a organizacao Alfa => NOT_FOUND.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_definir_limites_do_ciclo(v_cicb, v_alfa, 'NEGOCIO_PROJETO', 1,
      'probe cross-tenant (P2)', 1, v_a1,
      'f0700000-0000-0000-0000-000000000096');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] M9: ciclo de outro tenant deveria ser NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (M10) PERFIL/MEMBERSHIP INVALIDOS, ator de outro tenant e expected_version
  --       ausente => FORBIDDEN / INVALID_INPUT, todos sem efeito.
  v_ok := false;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 2,
      'probe membership disabled (P2)', 3, v_adis,
      'f0700000-0000-0000-0000-000000000098');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] M10: ator com membership disabled deveria ser FORBIDDEN';
  end if;
  v_ok := false;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 2,
      'probe perfil disabled (P2)', 3, v_aperf,
      'f0700000-0000-0000-0000-000000000099');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] M10: ator com perfil disabled deveria ser FORBIDDEN';
  end if;
  v_ok := false;
  begin
    perform public.meta_definir_limites_do_ciclo(v_cicb, v_beta, 'NEGOCIO_PROJETO', 1,
      'probe ator de outro tenant (P2)', 1, v_a1,
      'f0700000-0000-0000-0000-00000000009a');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] M10: ator de outro tenant deveria ser FORBIDDEN';
  end if;
  v_ok := false;
  begin
    perform public.meta_definir_limites_do_ciclo(v_cicb, v_beta, 'NEGOCIO_PROJETO', 1,
      'probe expected_version ausente (P2)', null, v_abeta,
      'f0700000-0000-0000-0000-00000000009b');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] M10: expected_version ausente deveria ser INVALID_INPUT';
  end if;

  raise notice '[PASS] M/D21: alteracao valida de limites em ciclo ATIVO com version do CICLO +1 e evento LIMITES_DO_CICLO_ALTERADOS em cycle_events (before/after completos); replay identico sem novo efeito; operation_id divergente, stale, ciclo nao ATIVO, cross-tenant, perfil/membership invalidos e quantidade fora de 0..3 recusados sem efeito';
end $$;

-- ============================================================================
-- 15) M2) D21 — ROLLBACK TOTAL quando a gravacao do evento de limites falha
-- ============================================================================
-- A falha e injetada APENAS no INSERT de `cycle_events`, que ocorre DEPOIS do
-- upsert da quota e do incremento da version do ciclo: se a transacao nao fosse
-- atomica, quota/version ficariam mutadas sem evento. DDL no nivel SQL.
create or replace function public._mut_f5_10_p2_falhar_trilha_ciclo()
returns trigger
language plpgsql
as $mut$
begin
  raise exception 'MUT_F5_10_P2: falha injetada na gravacao da trilha de ciclo';
end;
$mut$;

create trigger _mut_f5_10_p2_trilha_ciclo before insert on public.cycle_events
  for each row execute function public._mut_f5_10_p2_falhar_trilha_ciclo();

do $$
declare
  v_alfa  uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_a1    uuid := 'f0c00000-0000-0000-0000-000000000001';
  v_ok    boolean;
  v_n     int;
  v_qtd   int;
begin
  v_ok := false;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 3,
      'probe de rollback dos limites (P2)', 3, v_a1,
      'f0700000-0000-0000-0000-000000000097');
  exception when others then v_ok := sqlerrm like '%MUT_F5_10_P2%';
  end;
  if not v_ok then
    raise exception '[FAIL] M2: a falha injetada na trilha do ciclo nao abortou a operacao';
  end if;

  select c.version into v_n from public.evaluation_cycles c where c.id = v_ciclo;
  select l.quantidade into v_qtd from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'NEGOCIO_PROJETO';
  if v_n <> 3 or v_qtd <> 2 then
    raise exception '[FAIL] M2: rollback incompleto (version=%, limite=%)', v_n, v_qtd;
  end if;
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f0700000-0000-0000-0000-000000000097'
  ) then
    raise exception '[FAIL] M2: evento registrado apesar da falha injetada';
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_alfa and e.cycle_id = v_ciclo;
  if v_n <> 2 then
    raise exception '[FAIL] M2: a trilha do ciclo mudou apos o rollback (%)', v_n;
  end if;
  -- A trilha de METAS segue intocada (o evento de limites nao vive nela).
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa;
  if v_n <> 13 then
    raise exception '[FAIL] M2: a trilha de metas foi alterada (%)', v_n;
  end if;

  raise notice '[PASS] M2/D21: falha injetada na trilha do CICLO => ROLLBACK TOTAL (limite e version do ciclo intactos, nenhum evento parcial, trilha de metas intocada)';
end $$;

drop trigger _mut_f5_10_p2_trilha_ciclo on public.cycle_events;
drop function public._mut_f5_10_p2_falhar_trilha_ciclo();

-- ============================================================================
-- 16) M3) D21 — Estado final do ciclo de limites e nao-vazamento para metas
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f0a00000-0000-0000-0000-0000000000a1';
  v_ciclo  uuid := 'f0d10000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f0a00000-0000-0000-0000-0000000000b1';
  v_lim    int;
  v_ver    int;
  v_evt    int;
  v_metas  int;
  v_goalev int;
  v_tipo   text;
begin
  -- Limites finais de Alfa ATIVO: {NEGOCIO_PROJETO: 2, INDIVIDUAL: 1} (restaurado).
  select l.quantidade into v_lim from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'NEGOCIO_PROJETO';
  if v_lim <> 2 then
    raise exception '[FAIL] M3: limite final de NEGOCIO_PROJETO deveria ser 2 (%)', v_lim;
  end if;
  select l.quantidade into v_lim from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'INDIVIDUAL';
  if v_lim <> 1 then
    raise exception '[FAIL] M3: limite final de INDIVIDUAL deveria ser 1 (%)', v_lim;
  end if;
  select count(*) into v_lim from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo;
  if v_lim <> 2 then
    raise exception '[FAIL] M3: a operacao de limites criou/removeu linhas de quota (%)', v_lim;
  end if;

  -- Version final do CICLO ATIVO e trilha do ciclo: exatamente 2 eventos D21.
  select c.version into v_ver from public.evaluation_cycles c where c.id = v_ciclo;
  select count(*) into v_evt from public.cycle_events e
   where e.organization_id = v_alfa and e.cycle_id = v_ciclo;
  select count(*) into v_goalev from public.cycle_events e
   where e.organization_id = v_alfa and e.event_type <> 'LIMITES_DO_CICLO_ALTERADOS';
  if v_ver <> 3 or v_evt <> 2 or v_goalev <> 0 then
    raise exception '[FAIL] M3: estado final do ciclo inesperado (version=%, eventos=%, nao-D21=%)',
      v_ver, v_evt, v_goalev;
  end if;

  -- NENHUM evento D21 na trilha de metas, em NENHUM tenant, e trilhas intactas.
  select count(*) into v_evt from public.evaluation_goal_events e
   where e.event_type = 'LIMITES_DO_CICLO_ALTERADOS';
  if v_evt <> 0 then
    raise exception '[FAIL] M3: evento de limites encontrado em evaluation_goal_events (%)', v_evt;
  end if;
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_goalev from public.evaluation_goal_events
   where organization_id in (v_alfa, v_beta);
  if v_metas <> 6 or v_goalev <> 14 then
    raise exception '[FAIL] M3: metas/eventos de metas alterados pela operacao de limites (metas=%, eventos=%)',
      v_metas, v_goalev;
  end if;

  -- A trilha de limites registra SOMENTE o tipo do contrato (nao antecipa nada).
  for v_tipo in
    select distinct e.event_type from public.cycle_events e
     where e.organization_id = v_alfa
  loop
    if v_tipo <> 'LIMITES_DO_CICLO_ALTERADOS' then
      raise exception '[FAIL] M3: tipo inesperado na trilha do ciclo (%)', v_tipo;
    end if;
  end loop;

  -- Nenhum artefato de mutacao (inclusive o da trilha do ciclo) deixado para tras.
  select count(*) into v_evt from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname like '\_mut\_f5\_10\_p2%';
  if v_evt <> 0 then
    raise exception '[FAIL] M3: artefato de mutacao deixado no schema (%)', v_evt;
  end if;

  raise notice '[PASS] M3/D21: limites finais {NEGOCIO_PROJETO: 2, INDIVIDUAL: 1}, version do ciclo 3, 2 eventos LIMITES_DO_CICLO_ALTERADOS em cycle_events e ZERO vazamento para a trilha de metas';
end $$;

-- ============================================================================
-- 17) Resumo
-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F5-10 P2: operacoes soberanas de metas validadas — criar, editar, progresso, finalizar, revisar fechamento, excluir logicamente e definir limites do ciclo (D21, evento em cycle_events), com UUID canonico, tenant revalidado, expected_version, idempotencia por operation_id, evento append-only, autoria resolvida no banco, lock normativo unico, quota do banco, atomicidade e zero DELETE fisico.';
  raise notice '============================================================';
end $$;
