-- ============================================================================
-- F5-10 P3 (Issue #214): validacao automatizada de APROVACOES e INVALIDACAO
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   supabase/validacao/23-cenario-f5-10-p3.sql   (fixture)
--   supabase/validacao/24-validar-f5-10-p3.sql   (este arquivo)
--
-- Contrato coberto (docs/F5-10-desenho-tecnico.md; D1-D25):
--   A  aprovacao valida de GERENTE e COORDENADOR (fato + evento + autoria),
--      sem alterar status/version da meta; replay idempotente;
--   B  recusas sem efeito: duplicidade vigente, stale, actor fora do snapshot,
--      owner sem papel congelado, sem vinculo, membership/perfil invalidos,
--      ator de outro tenant, meta de outro tenant, papel e expected_version
--      invalidos;
--   C  fail-closed ESTRUTURAL: papel ausente, avaliacao ausente, avaliacao sem
--      participantes e avaliacao CANCELADA ignorada;
--   D  GERENTE valido em segunda avaliacao (somente GESTAO_CADEIA);
--   E  matriz D19: alteracao MATERIAL invalida as aprovacoes vigentes
--      (atomicamente, com evento por papel); alteracao NAO efetiva, progresso,
--      primeira finalizacao, revisao de fechamento e quota NAO invalidam;
--      reaprovacao cria NOVO fato preservando o revogado;
--   F  `meta_invalidar_aprovacoes`: motivo obrigatorio, stale, cross-tenant,
--      invalidacao efetiva, replay idempotente, NO-OP SEM fato vigente
--      **REGISTRADO na trilha** (um evento, operation_id consumido,
--      result_entity_id NULL) com idempotencia TEMPORAL provada (nova aprovacao
--      vigente criada depois do NO-OP NAO e invalidada pelo replay) e payload
--      divergente => CONFLICT (nunca re-muta fato revogado);
--   G  soft delete e TERMINAL e preserva os fatos historicos;
--   H  rollback total com falhas injetadas (evento de aprovacao, evento de
--      invalidacao e evento EDITADA apos a invalidacao);
--   I  estrutura viva/overlay NAO transfere autoridade (ocorrencia original
--      encerrada => fail-closed);
--   J  ACL/anti-escopo: 9 RPCs, derivacao na estrutura congelada, zero DELETE,
--      zero policy e P4/P5 nao antecipadas;
--   K  estado final deterministico (fatos vigentes/revogados e eventos).
--
-- Saida deterministica: um `[PASS]` por bloco; qualquer falha aborta.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture presente e ESTADO LIMPO
-- ----------------------------------------------------------------------------
do $$
declare
  v_alfa   uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f1a00000-0000-0000-0000-0000000000b1';
  v_metas  int;
  v_evt    int;
  v_aprov  int;
  v_partic int;
  v_ger    uuid;
begin
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_partic from public.evaluation_participants
   where id::text like 'f1300000%';
  if v_metas <> 5 or v_evt <> 5 or v_aprov <> 0 or v_partic <> 4 then
    raise exception
      '[FAIL] pre-condicao: fixture F5-10 P3 ausente ou estado sujo (metas=%, eventos=%, aprovacoes=%, participantes=%) — execute `supabase db reset` e o cenario 23',
      v_metas, v_evt, v_aprov, v_partic;
  end if;

  -- A derivacao congelada precisa reconhecer os dois papeis da meta G1.
  v_ger := public.f5_10_aprovador_congelado(
    'f1000000-0000-0000-0000-000000000001', v_alfa, 'GERENTE');
  if v_ger <> 'f1b00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] pre-condicao: GERENTE congelado de G1 deveria ser c1 (%)', v_ger;
  end if;
  v_ger := public.f5_10_aprovador_congelado(
    'f1000000-0000-0000-0000-000000000001', v_alfa, 'COORDENADOR');
  if v_ger <> 'f1b00000-0000-0000-0000-000000000003'::uuid then
    raise exception '[FAIL] pre-condicao: COORDENADOR congelado de G1 deveria ser c3 (%)', v_ger;
  end if;

  raise notice '[PASS] pre-condicoes: fixture presente, estado limpo e derivacao congelada resolvendo G1 (GERENTE = c1, COORDENADOR = c3)';
end $$;

-- ============================================================================
-- 1) A) Aprovacao valida (fato + evento + idempotencia) — GERENTE e COORDENADOR
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_ger  uuid := 'f1000000-0000-0000-0000-000000000001';
  v_a1   uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_a2   uuid := 'f1c00000-0000-0000-0000-000000000002';
  v_res  jsonb;
  v_res2 jsonb;
  v_fato record;
  v_evt  record;
  v_meta record;
  v_n    int;
begin
  -- (A1) GERENTE original (c1) aprova a meta do dono c2.
  v_res := public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'aprovacao de gerente (P3)',
    0, v_a1, 'f1700000-0000-0000-0000-000000000101');
  if v_res->>'aprovado' <> 'true' or v_res->>'papel' <> 'GERENTE'
     or (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] A1: retorno da aprovacao divergente (%)', v_res;
  end if;

  select a.* into v_fato from public.evaluation_goal_approvals a
   where a.id = (v_res->>'aprovacao_id')::uuid;
  if v_fato.id is null then
    raise exception '[FAIL] A1: fato de aprovacao nao gravado';
  end if;
  if v_fato.organization_id <> v_alfa or v_fato.goal_id <> v_ger
     or v_fato.papel <> 'GERENTE' or v_fato.revogado_em is not null
     or v_fato.version <> 0 then
    raise exception '[FAIL] A1: fato de aprovacao divergente (papel=%, revogado=%, version=%)',
      v_fato.papel, v_fato.revogado_em, v_fato.version;
  end if;
  if v_fato.actor_user_profile_id <> v_a1
     or v_fato.actor_membership_id <> 'f1d00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] A1: autoria soberana do fato incorreta';
  end if;

  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f1700000-0000-0000-0000-000000000101';
  if v_evt.event_type <> 'APROVACAO_GERENTE'
     or v_evt.result_entity_id <> v_fato.id
     or v_evt.actor_user_profile_id <> v_a1
     or v_evt.payload_hash !~ '^[0-9a-f]{64}$'
     or v_evt.after_value->>'aprovacao_id' <> v_fato.id::text
     or v_evt.after_value->>'vigente' <> 'true'
     or v_evt.before_value->>'vigente' <> 'false' then
    raise exception '[FAIL] A1: evento APROVACAO_GERENTE divergente (%)', v_evt;
  end if;

  -- A aprovacao NAO muda status nem version da meta (D3/D17).
  select g.status, g.version into v_meta from public.evaluation_goals g where g.id = v_ger;
  if v_meta.status <> 'EM_ANDAMENTO' or v_meta.version <> 0 then
    raise exception '[FAIL] A1: a aprovacao alterou a meta (status=%, version=%)',
      v_meta.status, v_meta.version;
  end if;

  -- (A2) Replay IDENTICO: mesmo resultado, sem novo fato/evento.
  v_res2 := public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'aprovacao de gerente (P3)',
    0, v_a1, 'f1700000-0000-0000-0000-000000000101');
  if v_res <> v_res2 then
    raise exception '[FAIL] A2: replay identico devolveu resultado diferente (% vs %)', v_res, v_res2;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals
   where organization_id = v_alfa and goal_id = v_ger;
  if v_n <> 1 then
    raise exception '[FAIL] A2: replay duplicou o fato de aprovacao (%)', v_n;
  end if;

  -- (A3) COORDENADOR original (c3, distinto da cadeia) aprova a MESMA meta.
  v_res := public.meta_aprovar(v_ger, v_alfa, 'COORDENADOR', 'aprovacao de coordenador (P3)',
    0, v_a2, 'f1700000-0000-0000-0000-000000000102');
  select a.* into v_fato from public.evaluation_goal_approvals a
   where a.id = (v_res->>'aprovacao_id')::uuid;
  if v_fato.papel <> 'COORDENADOR' or v_fato.revogado_em is not null
     or v_fato.actor_user_profile_id <> v_a2 then
    raise exception '[FAIL] A3: fato de COORDENADOR divergente';
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f1700000-0000-0000-0000-000000000102'
     and e.event_type = 'APROVACAO_COORDENADOR';
  if v_n <> 1 then
    raise exception '[FAIL] A3: evento APROVACAO_COORDENADOR ausente/duplicado (%)', v_n;
  end if;

  -- (A4) Replay identico do COORDENADOR.
  v_res2 := public.meta_aprovar(v_ger, v_alfa, 'COORDENADOR', 'aprovacao de coordenador (P3)',
    0, v_a2, 'f1700000-0000-0000-0000-000000000102');
  if v_res <> v_res2 then
    raise exception '[FAIL] A4: replay do coordenador devolveu resultado diferente';
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals
   where organization_id = v_alfa and goal_id = v_ger;
  if v_n <> 2 then
    raise exception '[FAIL] A4: esperados 2 fatos vigentes (GERENTE + COORDENADOR), encontrados %', v_n;
  end if;

  -- (A5) operation_id ja utilizado com INTENCAO divergente => CONFLICT.
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'COORDENADOR', 'intencao divergente (P3)',
      0, v_a2, 'f1700000-0000-0000-0000-000000000101');
    raise exception '[FAIL] A5: operation_id divergente deveria ser CONFLICT';
  exception when others then
    if sqlerrm not like '%F5_10_CONFLICT%' then
      raise exception '[FAIL] A5: esperado F5_10_CONFLICT, recebido %', sqlerrm;
    end if;
  end;

  raise notice '[PASS] A: aprovacao valida de GERENTE e COORDENADOR (fato vigente + evento append-only + autoria soberana), sem alterar status/version da meta, com replay idempotente e operation_id divergente recusado';
end $$;

-- ============================================================================
-- 2) B) Recusas sem efeito (legitimidade, tenant, estado e forma)
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f1a00000-0000-0000-0000-0000000000b1';
  v_ger    uuid := 'f1000000-0000-0000-0000-000000000001';
  v_g2     uuid := 'f1000000-0000-0000-0000-000000000002';
  v_gbeta  uuid := 'f1000000-0000-0000-0000-0000000000b1';
  v_a1     uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_a3     uuid := 'f1c00000-0000-0000-0000-000000000003';
  v_a4     uuid := 'f1c00000-0000-0000-0000-000000000004';
  v_a5     uuid := 'f1c00000-0000-0000-0000-000000000005';
  v_a6     uuid := 'f1c00000-0000-0000-0000-000000000006';
  v_a7     uuid := 'f1c00000-0000-0000-0000-000000000007';
  v_abeta  uuid := 'f1c00000-0000-0000-0000-0000000000b1';
  v_fatos  int;
  v_evt    int;
  v_ok     boolean;
  v_msg    text;
begin
  select count(*) into v_fatos from public.evaluation_goal_approvals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in (v_alfa, v_beta);

  -- (B1) segunda aprovacao VIGENTE do mesmo papel => CONFLICT.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'duplicidade (P3)', 0, v_a1,
      'f1700000-0000-0000-0000-000000000111');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] B1: aprovacao vigente duplicada deveria ser CONFLICT (recebido %)', v_msg;
  end if;

  -- (B2) expected_version OBSOLETO => CONFLICT sem efeito.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g2, v_alfa, 'GERENTE', 'stale (P3)', 7, v_a1,
      'f1700000-0000-0000-0000-000000000112');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] B2: expected_version obsoleto deveria ser CONFLICT (recebido %)', v_msg;
  end if;

  -- (B3) ator FORA do snapshot congelado original (ocorrencia POSTERIOR nao vale).
  v_ok := false;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'ator fora do snapshot (P3)', 0, v_a4,
      'f1700000-0000-0000-0000-000000000113');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] B3: ator com ocorrencia POSTERIOR (overlay) deveria ser FORBIDDEN';
  end if;

  -- (B4) OWNER tentando aprovar a propria meta SEM papel congelado => FORBIDDEN.
  v_ok := false;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'owner sem papel (P3)', 0, v_a3,
      'f1700000-0000-0000-0000-000000000114');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] B4: owner (dono) sem papel congelado deveria ser FORBIDDEN';
  end if;

  -- (B5) ator com membership ativa mas SEM vinculo de colaborador => FORBIDDEN.
  v_ok := false;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'sem vinculo (P3)', 0, v_a5,
      'f1700000-0000-0000-0000-000000000115');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] B5: ator sem vinculo de colaborador deveria ser FORBIDDEN';
  end if;

  -- (B6) membership DISABLED e perfil DISABLED => FORBIDDEN.
  v_ok := false;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'membership disabled (P3)', 0, v_a6,
      'f1700000-0000-0000-0000-000000000116');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] B6: ator com membership disabled deveria ser FORBIDDEN';
  end if;
  v_ok := false;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'perfil disabled (P3)', 0, v_a7,
      'f1700000-0000-0000-0000-000000000117');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] B6: ator com perfil disabled deveria ser FORBIDDEN';
  end if;

  -- (B7) ator de OUTRO tenant => FORBIDDEN.
  v_ok := false;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'ator de outro tenant (P3)', 0, v_abeta,
      'f1700000-0000-0000-0000-000000000118');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%';
  end;
  if not v_ok then
    raise exception '[FAIL] B7: ator de outro tenant deveria ser FORBIDDEN';
  end if;

  -- (B8) meta de OUTRO tenant (cross-tenant) => NOT_FOUND.
  v_ok := false;
  begin
    perform public.meta_aprovar(v_gbeta, v_alfa, 'GERENTE', 'meta cross-tenant (P3)', 0, v_a1,
      'f1700000-0000-0000-0000-000000000119');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] B8: meta de outro tenant deveria ser NOT_FOUND';
  end if;

  -- (B9) papel invalido e expected_version ausente => INVALID_INPUT.
  v_ok := false;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'DIRETOR', 'papel invalido (P3)', 0, v_a1,
      'f1700000-0000-0000-0000-00000000011a');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] B9: papel invalido deveria ser INVALID_INPUT';
  end if;
  v_ok := false;
  begin
    perform public.meta_aprovar(v_ger, v_alfa, 'GERENTE', 'sem expected_version (P3)', null, v_a1,
      'f1700000-0000-0000-0000-00000000011b');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] B9: expected_version ausente deveria ser INVALID_INPUT';
  end if;

  -- Nenhuma recusa alterou fatos ou eventos.
  if (select count(*) from public.evaluation_goal_approvals
       where organization_id in (v_alfa, v_beta)) <> v_fatos
     or (select count(*) from public.evaluation_goal_events
          where organization_id in (v_alfa, v_beta)) <> v_evt then
    raise exception '[FAIL] B: recusas alteraram fatos/eventos (esperado % fatos e % eventos)',
      v_fatos, v_evt;
  end if;

  raise notice '[PASS] B: 11 recusas sem efeito (duplicidade vigente, stale, overlay posterior, owner sem papel, sem vinculo, membership/perfil disabled, ator e meta de outro tenant, papel e expected_version invalidos)';
end $$;

-- ============================================================================
-- 3) C) FAIL-CLOSED estrutural + D) GERENTE em segunda avaliacao
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_g1   uuid := 'f1000000-0000-0000-0000-000000000001';
  v_g2   uuid := 'f1000000-0000-0000-0000-000000000002';
  v_g3   uuid := 'f1000000-0000-0000-0000-000000000003';
  v_g4   uuid := 'f1000000-0000-0000-0000-000000000004';
  v_a1   uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_a2   uuid := 'f1c00000-0000-0000-0000-000000000002';
  v_res  jsonb;
  v_ok   boolean;
  v_msg  text;
  v_aprov uuid;
begin
  -- (C1) COORDENADOR quando NAO existe GESTAO_DIRETA distinta => fail-closed.
  if public.f5_10_aprovador_congelado(v_g2, v_alfa, 'COORDENADOR') is not null then
    raise exception '[FAIL] C1: G2 nao deveria reconhecer COORDENADOR (sem GESTAO_DIRETA)';
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g2, v_alfa, 'COORDENADOR', 'coordenador ausente (P3)', 0, v_a2,
      'f1700000-0000-0000-0000-000000000121');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] C1: ausencia de COORDENADOR distinto deveria ser CONFLICT (recebido %)', v_msg;
  end if;

  -- (C2) meta SEM avaliacao do dono => fail-closed.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g3, v_alfa, 'GERENTE', 'sem avaliacao (P3)', 0, v_a1,
      'f1700000-0000-0000-0000-000000000122');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] C2: meta sem avaliacao deveria ser CONFLICT (recebido %)', v_msg;
  end if;

  -- (C3) avaliacao SEM participantes => fail-closed.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g4, v_alfa, 'GERENTE', 'sem participantes (P3)', 0, v_a1,
      'f1700000-0000-0000-0000-000000000123');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] C3: avaliacao sem participantes deveria ser CONFLICT (recebido %)', v_msg;
  end if;

  -- (C4) avaliacao CANCELADA do MESMO dono e IGNORADA: G2 (EV2 nao cancelada +
  --      EV3 cancelada) resolve o papel normalmente pelo GERENTE congelado.
  if public.f5_10_aprovador_congelado(v_g2, v_alfa, 'GERENTE')
     <> 'f1b00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] C4: GERENTE de G2 deveria vir da avaliacao NAO CANCELADA (c1)';
  end if;

  -- (D1) GERENTE valido na segunda avaliacao (somente GESTAO_CADEIA).
  v_res := public.meta_aprovar(v_g2, v_alfa, 'GERENTE', 'aprovacao de gerente em G2 (P3)',
    0, v_a1, 'f1700000-0000-0000-0000-000000000124');
  v_aprov := (v_res->>'aprovacao_id')::uuid;
  if v_aprov is null then
    raise exception '[FAIL] D1: aprovacao de GERENTE em G2 nao registrada';
  end if;
  if not exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f1700000-0000-0000-0000-000000000124'
       and e.event_type = 'APROVACAO_GERENTE'
       and e.result_entity_id = v_aprov
  ) then
    raise exception '[FAIL] D1: evento APROVACAO_GERENTE de G2 ausente';
  end if;

  raise notice '[PASS] C/D: fail-closed estrutural (COORDENADOR ausente, avaliacao ausente, avaliacao sem participantes, avaliacao CANCELADA ignorada) e GERENTE valido em segunda avaliacao';
end $$;

-- ============================================================================
-- 4) E) Matriz D19: o que invalida e o que NAO invalida
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_ciclo  uuid := 'f1f00000-0000-0000-0000-0000000000a1';
  v_g1     uuid := 'f1000000-0000-0000-0000-000000000001';
  v_a1     uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_fato   record;
  v_meta   record;
  v_n      int;
  v_evt    int;
  v_res    jsonb;
begin
  -- (E1) alteracao MATERIAL (descricao) invalida AMBAS as aprovacoes vigentes,
  --      atomicamente, com um evento APROVACAO_INVALIDADA por papel.
  v_res := public.meta_editar(v_g1, v_alfa, 'Meta do dono EDITADA materialmente (P3)',
    'KPI de fixture (P3)', '100 unidades (P3)', 0, v_a1,
    'f1700000-0000-0000-0000-000000000131');
  if (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] E1: edicao deveria levar a meta para version 1 (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is not null;
  if v_n <> 2 then
    raise exception '[FAIL] E1: as DUAS aprovacoes vigentes deveriam ser invalidadas (%)', v_n;
  end if;
  select count(*) into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g1
     and e.event_type = 'APROVACAO_INVALIDADA';
  if v_evt <> 2 then
    raise exception '[FAIL] E1: esperados 2 eventos APROVACAO_INVALIDADA (%)', v_evt;
  end if;
  -- O fato anterior e PRESERVADO (mesma linha), revogado com motivo e version+1.
  select a.* into v_fato from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.papel = 'GERENTE';
  if v_fato.id is null or v_fato.revogado_em is null
     or v_fato.revogado_motivo is null or v_fato.version <> 1
     or v_fato.revogado_motivo <> 'invalidada por alteracao material da definicao da meta (D19)' then
    raise exception '[FAIL] E1: fato revogado divergente (revogado=%, motivo=%, version=%)',
      v_fato.revogado_em, v_fato.revogado_motivo, v_fato.version;
  end if;
  -- O evento de invalidacao carrega o fato e o motivo, e a trilha tem o EDITADA.
  if not exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa and e.goal_id = v_g1
       and e.event_type = 'APROVACAO_INVALIDADA'
       and e.result_entity_id = v_fato.id
       and e.before_value->>'vigente' = 'true'
       and e.after_value->>'vigente' = 'false'
       and e.after_value->>'revogado_motivo' =
           'invalidada por alteracao material da definicao da meta (D19)'
  ) then
    raise exception '[FAIL] E1: evento de invalidacao sem o fato/motivo corretos';
  end if;
  if not exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f1700000-0000-0000-0000-000000000131'
       and e.event_type = 'EDITADA'
  ) then
    raise exception '[FAIL] E1: evento EDITADA ausente na edicao que invalidou';
  end if;

  -- (E2) reaprovacao apos invalidacao CRIA NOVO FATO e preserva o anterior.
  v_res := public.meta_aprovar(v_g1, v_alfa, 'GERENTE', 'reaprovacao apos invalidacao (P3)',
    1, v_a1, 'f1700000-0000-0000-0000-000000000132');
  if (v_res->>'aprovacao_id')::uuid = v_fato.id then
    raise exception '[FAIL] E2: a reaprovacao deveria criar um NOVO fato';
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.papel = 'GERENTE';
  if v_n <> 2 then
    raise exception '[FAIL] E2: deveriam existir 2 fatos de GERENTE (1 revogado + 1 vigente), encontrados %', v_n;
  end if;
  select a.* into v_fato from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.papel = 'GERENTE'
     and a.revogado_em is null;
  if v_fato.id is null or v_fato.version <> 0 then
    raise exception '[FAIL] E2: o novo fato deveria nascer vigente/version 0';
  end if;

  -- (E3) edicao SEM alteracao efetiva NAO invalida a aprovacao vigente.
  perform public.meta_editar(v_g1, v_alfa, 'Meta do dono EDITADA materialmente (P3)',
    'KPI de fixture (P3)', '100 unidades (P3)', 1, v_a1,
    'f1700000-0000-0000-0000-000000000133');
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] E3: edicao sem alteracao efetiva NAO pode invalidar (%)', v_n;
  end if;

  raise notice '[PASS] E1..E3/D19: edicao MATERIAL invalida as aprovacoes vigentes (fato preservado, version+1, evento APROVACAO_INVALIDADA por papel) e reaprovacao cria NOVO fato; edicao SEM alteracao efetiva NAO invalida';
end $$;

-- ============================================================================
-- 5) H) ROLLBACK TOTAL com falhas injetadas na trilha
-- ============================================================================
-- Roda AQUI (antes das provas "nao invalida" e da finalizacao) porque a prova da
-- falha no evento EDITADA exige meta EM_ANDAMENTO: G1 so e finalizada no bloco
-- seguinte, e a edicao de uma meta finalizada e corretamente recusada pelo
-- lifecycle (o que nao exercitaria a atomicidade edicao + D19).
-- A falha e injetada por um GATILHO na trilha, controlado por GUC de sessao
-- (`f5_10_p3.falhar`), exercitando separadamente o evento de aprovacao, o de
-- invalidacao e o EDITADA (este DEPOIS da invalidacao ja ter ocorrido dentro da
-- RPC de edicao). DDL no nivel SQL, removida ao final deste bloco.
create or replace function public._mut_f5_10_p3_falhar_evento()
returns trigger
language plpgsql
as $mut$
declare
  v_alvo text := current_setting('f5_10_p3.falhar', true);
begin
  if v_alvo is not null and v_alvo <> '' and new.event_type = v_alvo then
    raise exception 'MUT_F5_10_P3: falha injetada no evento %', new.event_type;
  end if;
  return new;
end;
$mut$;

create trigger _mut_f5_10_p3_evento before insert on public.evaluation_goal_events
  for each row execute function public._mut_f5_10_p3_falhar_evento();

do $$
declare
  v_alfa uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_g1   uuid := 'f1000000-0000-0000-0000-000000000001';
  v_a1   uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_a2   uuid := 'f1c00000-0000-0000-0000-000000000002';
  v_ok   boolean;
  v_n    int;
  v_meta record;
begin
  -- (H1) falha no evento de APROVACAO: nenhum FATO parcial.
  select count(*) into v_n from public.evaluation_goal_approvals
   where organization_id = v_alfa and goal_id = v_g1 and papel = 'COORDENADOR';
  perform set_config('f5_10_p3.falhar', 'APROVACAO_COORDENADOR', true);
  v_ok := false;
  begin
    perform public.meta_aprovar(v_g1, v_alfa, 'COORDENADOR', 'probe de rollback (P3)', 2, v_a2,
      'f1700000-0000-0000-0000-000000000161');
  exception when others then v_ok := sqlerrm like '%MUT_F5_10_P3%';
  end;
  perform set_config('f5_10_p3.falhar', '', true);
  if not v_ok then
    raise exception '[FAIL] H1: a falha injetada no evento de aprovacao nao abortou a operacao';
  end if;
  if (select count(*) from public.evaluation_goal_approvals
       where organization_id = v_alfa and goal_id = v_g1 and papel = 'COORDENADOR') <> v_n then
    raise exception '[FAIL] H1: ROLLBACK incompleto — fato de aprovacao parcial ficou gravado';
  end if;
  if exists (
    select 1 from public.evaluation_goal_events
     where organization_id = v_alfa
       and operation_id = 'f1700000-0000-0000-0000-000000000161'
  ) then
    raise exception '[FAIL] H1: o evento do probe de rollback ficou na trilha';
  end if;

  -- (H2) falha no evento de INVALIDACAO: nenhuma revogacao parcial.
  perform set_config('f5_10_p3.falhar', 'APROVACAO_INVALIDADA', true);
  v_ok := false;
  begin
    perform public.meta_invalidar_aprovacoes(v_g1, v_alfa, 'probe de rollback (P3)', 2, v_a1,
      'f1700000-0000-0000-0000-000000000162');
  exception when others then v_ok := sqlerrm like '%MUT_F5_10_P3%';
  end;
  perform set_config('f5_10_p3.falhar', '', true);
  if not v_ok then
    raise exception '[FAIL] H2: a falha injetada no evento de invalidacao nao abortou a operacao';
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] H2: ROLLBACK incompleto — revogacao parcial (vigentes=%)', v_n;
  end if;
  if exists (
    select 1 from public.evaluation_goal_events
     where organization_id = v_alfa
       and operation_id = 'f1700000-0000-0000-0000-000000000162'
  ) then
    raise exception '[FAIL] H2: o evento do probe de rollback ficou na trilha';
  end if;

  -- (H3) falha no evento EDITADA DEPOIS da invalidacao: rollback da edicao E da
  --      invalidacao (matriz D19 e mutacao sao a MESMA transacao).
  select g.descricao, g.version, g.status into v_meta
    from public.evaluation_goals g where g.id = v_g1;
  perform set_config('f5_10_p3.falhar', 'EDITADA', true);
  v_ok := false;
  begin
    perform public.meta_editar(v_g1, v_alfa, 'edicao que deve ser revertida (P3)',
      'KPI revertido (P3)', '999 unidades (P3)', 2, v_a1,
      'f1700000-0000-0000-0000-000000000163');
  exception when others then v_ok := sqlerrm like '%MUT_F5_10_P3%';
  end;
  perform set_config('f5_10_p3.falhar', '', true);
  if not v_ok then
    raise exception '[FAIL] H3: a falha injetada no evento EDITADA nao abortou a edicao';
  end if;
  if exists (
    select 1 from public.evaluation_goals g
     where g.id = v_g1
       and (g.descricao is distinct from v_meta.descricao
            or g.version <> v_meta.version
            or g.status is distinct from v_meta.status)
  ) then
    raise exception '[FAIL] H3: ROLLBACK incompleto — a edicao persistiu';
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] H3: ROLLBACK incompleto — a invalidacao (D19) persistiu (vigentes=%)', v_n;
  end if;
  if exists (
    select 1 from public.evaluation_goal_events
     where organization_id = v_alfa
       and operation_id = 'f1700000-0000-0000-0000-000000000163'
  ) then
    raise exception '[FAIL] H3: evento parcial da edicao revertida ficou na trilha';
  end if;

  -- (H4) falha no evento do NO-OP (meta SEM fato vigente): nenhum registro
  --      parcial na trilha e nenhuma alteracao de aprovacao. A meta G3 nao tem
  --      avaliacao (logo, nenhuma aprovacao possivel) e esta em version 0.
  perform set_config('f5_10_p3.falhar', 'APROVACAO_INVALIDADA', true);
  v_ok := false;
  begin
    perform public.meta_invalidar_aprovacoes(
      'f1000000-0000-0000-0000-000000000003', v_alfa,
      'probe de rollback do NO-OP (P3)', 0, v_a1,
      'f1700000-0000-0000-0000-000000000164');
  exception when others then v_ok := sqlerrm like '%MUT_F5_10_P3%';
  end;
  perform set_config('f5_10_p3.falhar', '', true);
  if not v_ok then
    raise exception '[FAIL] H4: a falha injetada no evento do NO-OP nao abortou a operacao';
  end if;
  if exists (
    select 1 from public.evaluation_goal_events
     where organization_id = v_alfa
       and operation_id = 'f1700000-0000-0000-0000-000000000164'
  ) then
    raise exception '[FAIL] H4: o evento do NO-OP ficou na trilha apesar da falha';
  end if;
  if exists (
    select 1 from public.evaluation_goal_approvals
     where organization_id = v_alfa
       and goal_id = 'f1000000-0000-0000-0000-000000000003'
  ) then
    raise exception '[FAIL] H4: o NO-OP abortado tocou aprovacoes';
  end if;

  raise notice '[PASS] H: rollback TOTAL com falha no evento de aprovacao (nenhum fato parcial), no evento de invalidacao (nenhuma revogacao parcial), no evento EDITADA apos a invalidacao (edicao + D19 revertidas juntas) e no evento do NO-OP (nenhum registro parcial)';
end $$;

drop trigger _mut_f5_10_p3_evento on public.evaluation_goal_events;
drop function public._mut_f5_10_p3_falhar_evento();

-- ============================================================================
-- 6) E-cont) D19: o que NAO invalida (progresso, primeira finalizacao, revisao,
--    quota e soft delete) — continua a matriz §9.4
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f1f00000-0000-0000-0000-0000000000a1';
  v_g1    uuid := 'f1000000-0000-0000-0000-000000000001';
  v_a1    uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_meta  record;
  v_n     int;
begin
  -- (E4) progresso NAO invalida.
  perform public.meta_atualizar_progresso(v_g1, v_alfa, 'acompanhamento (P3)', 50, 2, v_a1,
    'f1700000-0000-0000-0000-000000000134');
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] E4: progresso NAO pode invalidar aprovacoes (%)', v_n;
  end if;

  -- (E5) primeira finalizacao NAO invalida.
  perform public.meta_finalizar(v_g1, v_alfa, 'fechamento (P3)', true, 3, v_a1,
    'f1700000-0000-0000-0000-000000000135');
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] E5: finalizacao NAO pode invalidar aprovacoes (%)', v_n;
  end if;

  -- (E6) revisao de fechamento NAO invalida.
  perform public.meta_revisar_finalizacao(v_g1, v_alfa, 'fechamento revisado (P3)', false,
    'revisao de fechamento (P3)', 4, v_a1, 'f1700000-0000-0000-0000-000000000136');
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] E6: revisao de fechamento NAO pode invalidar aprovacoes (%)', v_n;
  end if;
  select g.status, g.version into v_meta from public.evaluation_goals g where g.id = v_g1;
  if v_meta.status <> 'NAO_ATINGIDA' or v_meta.version <> 5 then
    raise exception '[FAIL] E6: estado/version da meta inesperados (status=%, version=%)',
      v_meta.status, v_meta.version;
  end if;

  -- (E7) alteracao de QUOTA NAO invalida (dominio do CHECK: 0..3).
  perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'INDIVIDUAL', 2,
    'aumento de quota (P3)', 1, v_a1, 'f1700000-0000-0000-0000-000000000137');
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] E7: quota NAO pode invalidar aprovacoes (%)', v_n;
  end if;

  -- (E8) soft delete e TERMINAL e PRESERVA os fatos historicos: G2 tem aprovacao
  --      VIGENTE do GERENTE que permanece vigente (nao vira invalidacao artificial).
  perform public.meta_excluir('f1000000-0000-0000-0000-000000000002', v_alfa,
    'meta cancelada na fixture (P3)', 0, v_a1, 'f1700000-0000-0000-0000-000000000138');
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa
     and a.goal_id = 'f1000000-0000-0000-0000-000000000002'
     and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] E8: soft delete NAO pode invalidar nem apagar aprovacoes (%)', v_n;
  end if;

  raise notice '[PASS] E-cont/D19: progresso, primeira finalizacao, revisao de fechamento, alteracao de quota e soft delete NAO invalidam as aprovacoes vigentes';
end $$;

-- ============================================================================
-- 5) F) `meta_invalidar_aprovacoes` — operacao soberana de invalidacao
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_g1    uuid := 'f1000000-0000-0000-0000-000000000001';
  v_gbeta uuid := 'f1000000-0000-0000-0000-0000000000b1';
  v_a1    uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_res   jsonb;
  v_res2  jsonb;
  v_fato  record;
  v_evento record;
  v_evt   int;
  v_n     int;
  v_fatos int;
  v_vig   int;
  v_versoes int;
  v_ok    boolean;
  v_msg   text;
begin
  -- (F1) motivo obrigatorio => INVALID_INPUT.
  v_ok := false;
  begin
    perform public.meta_invalidar_aprovacoes(v_g1, v_alfa, '   ', 5, v_a1,
      'f1700000-0000-0000-0000-000000000141');
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%';
  end;
  if not v_ok then
    raise exception '[FAIL] F1: invalidacao sem motivo deveria ser INVALID_INPUT';
  end if;

  -- (F2) expected_version obsoleto => CONFLICT.
  v_ok := false;
  begin
    perform public.meta_invalidar_aprovacoes(v_g1, v_alfa, 'stale (P3)', 3, v_a1,
      'f1700000-0000-0000-0000-000000000142');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] F2: invalidacao com expected_version obsoleto deveria ser CONFLICT';
  end if;

  -- (F3) cross-tenant => NOT_FOUND.
  v_ok := false;
  begin
    perform public.meta_invalidar_aprovacoes(v_gbeta, v_alfa, 'cross-tenant (P3)', 5, v_a1,
      'f1700000-0000-0000-0000-000000000143');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%';
  end;
  if not v_ok then
    raise exception '[FAIL] F3: meta de outro tenant deveria ser NOT_FOUND';
  end if;

  -- (F4) invalidacao EFETIVA do fato vigente de G1, sem tocar os ja revogados e
  --      sem alterar a version da META.
  v_res := public.meta_invalidar_aprovacoes(v_g1, v_alfa,
    'invalidacao soberana explicita (P3)', 5, v_a1,
    'f1700000-0000-0000-0000-000000000144');
  if (v_res->>'invalidated')::int <> 1 or v_res->>'papel' <> 'GERENTE' then
    raise exception '[FAIL] F4: invalidacao deveria atingir exatamente 1 fato (GERENTE) (%)', v_res;
  end if;
  select a.* into v_fato from public.evaluation_goal_approvals a
   where a.id = (v_res->>'aprovacao_id')::uuid;
  if v_fato.revogado_em is null or v_fato.version <> 1
     or v_fato.revogado_motivo <> 'invalidacao soberana explicita (P3)' then
    raise exception '[FAIL] F4: fato invalidado divergente (revogado=%, version=%, motivo=%)',
      v_fato.revogado_em, v_fato.version, v_fato.revogado_motivo;
  end if;
  select count(*) into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.event_type = 'APROVACAO_INVALIDADA'
     and e.result_entity_id = v_fato.id;
  if v_evt <> 1 then
    raise exception '[FAIL] F4: esperado exatamente 1 evento de invalidacao para o fato (%)', v_evt;
  end if;
  if exists (select 1 from public.evaluation_goals g where g.id = v_g1 and g.version <> 5) then
    raise exception '[FAIL] F4: a invalidacao alterou a version da META (deveria permanecer 5)';
  end if;

  -- (F5) replay IDENTICO devolve o MESMO resultado, sem novo evento.
  v_res2 := public.meta_invalidar_aprovacoes(v_g1, v_alfa,
    'invalidacao soberana explicita (P3)', 5, v_a1,
    'f1700000-0000-0000-0000-000000000144');
  if v_res <> v_res2 then
    raise exception '[FAIL] F5: replay da invalidacao devolveu resultado diferente (% vs %)', v_res, v_res2;
  end if;

  -- (F6) NO-OP PERSISTENTEMENTE IDEMPOTENTE (correcao pos-auditoria): sem fato
  --      vigente a INTENCAO e registrada na trilha (UM evento, com o operation_id
  --      e o payload_hash da intencao, result_entity_id NULL, invalidated = 0) e
  --      NENHUMA linha de `evaluation_goal_approvals` e alterada.
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id = v_alfa;
  select count(*), coalesce(sum(a.version), 0) into v_fatos, v_versoes
    from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1;
  select count(*) into v_vig from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_vig <> 0 then
    raise exception '[FAIL] F6: pre-condicao — G1 deveria estar sem aprovacao vigente (%)', v_vig;
  end if;

  v_res := public.meta_invalidar_aprovacoes(v_g1, v_alfa,
    'segunda invalidacao sem fatos vigentes (P3)', 5, v_a1,
    'f1700000-0000-0000-0000-000000000145');
  if (v_res->>'invalidated')::int <> 0 then
    raise exception '[FAIL] F6: sem fato vigente a invalidacao deveria ser NO-OP (%)', v_res;
  end if;
  if v_res->>'aprovacao_id' is not null or v_res->>'papel' is not null then
    raise exception '[FAIL] F6: o NO-OP nao pode devolver fato revogado (%)', v_res;
  end if;

  -- Exatamente UM evento novo, e ele E o registro do NO-OP.
  if (select count(*) from public.evaluation_goal_events where organization_id = v_alfa) <> v_evt + 1 then
    raise exception '[FAIL] F6: o NO-OP deveria gravar EXATAMENTE um evento';
  end if;
  if (select count(*) from public.evaluation_goal_events e
       where e.organization_id = v_alfa
         and e.operation_id = 'f1700000-0000-0000-0000-000000000145') <> 1 then
    raise exception '[FAIL] F6: esperado exatamente 1 evento para o NO-OP';
  end if;
  select e.* into v_evento from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f1700000-0000-0000-0000-000000000145';
  if v_evento.event_type <> 'APROVACAO_INVALIDADA'
     or v_evento.goal_id <> v_g1
     or v_evento.result_entity_id is not null
     or v_evento.actor_user_profile_id <> v_a1
     or v_evento.actor_membership_id <> 'f1d00000-0000-0000-0000-000000000001'::uuid
     or v_evento.reason <> 'segunda invalidacao sem fatos vigentes (P3)'
     or v_evento.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] F6: evento do NO-OP divergente (%)', v_evento;
  end if;
  if (v_evento.before_value->>'invalidated')::int <> 0
     or (v_evento.after_value->>'invalidated')::int <> 0
     or v_evento.before_value->>'fato_vigente_encontrado' <> 'false'
     or v_evento.after_value->>'fato_vigente_encontrado' <> 'false'
     or v_evento.after_value->>'registro' <> 'NO_OP'
     or (v_evento.after_value->>'versao_meta')::int <> 5
     or v_evento.after_value->>'status_meta' <> 'NAO_ATINGIDA'
     or v_evento.after_value->>'revogado_motivo' <> 'segunda invalidacao sem fatos vigentes (P3)'
     or v_evento.after_value->>'aprovacao_id' is not null
     or v_evento.after_value->>'versao_fato' is not null then
    raise exception '[FAIL] F6: before/after do NO-OP nao explicitam invalidated=0/versao/status/motivo (% / %)',
      v_evento.before_value, v_evento.after_value;
  end if;

  -- NENHUMA linha de `evaluation_goal_approvals` foi alterada.
  if (select count(*) from public.evaluation_goal_approvals a
       where a.organization_id = v_alfa and a.goal_id = v_g1) <> v_fatos
     or (select coalesce(sum(a.version), 0) from public.evaluation_goal_approvals a
          where a.organization_id = v_alfa and a.goal_id = v_g1) <> v_versoes
     or (select count(*) from public.evaluation_goal_approvals a
          where a.organization_id = v_alfa and a.goal_id = v_g1
            and a.revogado_em is null) <> v_vig then
    raise exception '[FAIL] F6: o NO-OP alterou linhas de aprovacao (fatos=%, versoes=%, vigentes=%)',
      v_fatos, v_versoes, v_vig;
  end if;

  -- Replay IMEDIATO do NO-OP: mesmo resultado e nenhum evento adicional.
  v_res2 := public.meta_invalidar_aprovacoes(v_g1, v_alfa,
    'segunda invalidacao sem fatos vigentes (P3)', 5, v_a1,
    'f1700000-0000-0000-0000-000000000145');
  if v_res <> v_res2 then
    raise exception '[FAIL] F6: replay imediato do NO-OP divergiu (% vs %)', v_res, v_res2;
  end if;
  if (select count(*) from public.evaluation_goal_events where organization_id = v_alfa) <> v_evt + 1 then
    raise exception '[FAIL] F6: o replay do NO-OP gravou evento adicional';
  end if;

  -- (F7) reaprovacao apos a invalidacao explicita cria NOVO FATO vigente.
  v_res := public.meta_aprovar(v_g1, v_alfa, 'GERENTE',
    'reaprovacao apos invalidacao explicita (P3)', 5, v_a1,
    'f1700000-0000-0000-0000-000000000146');
  if (v_res->>'aprovado') <> 'true' then
    raise exception '[FAIL] F7: reaprovacao apos invalidacao explicita falhou (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.papel = 'GERENTE';
  if v_n <> 3 then
    raise exception '[FAIL] F7: deveriam existir 3 fatos de GERENTE (2 revogados + 1 vigente), encontrados %', v_n;
  end if;

  -- (F8) TESTE CRITICO DE IDEMPOTENCIA TEMPORAL: com NOVA aprovacao VIGENTE criada
  --      DEPOIS do NO-OP, repetir EXATAMENTE a chamada com o MESMO operation_id e o
  --      MESMO payload continua devolvendo `invalidated = 0` e NAO pode invalidar a
  --      nova aprovacao (o registro do NO-OP consumiu o operation_id).
  select e.* into v_evento from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f1700000-0000-0000-0000-000000000146';
  select count(*) into v_vig from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_vig <> 1 then
    raise exception '[FAIL] F8: pre-condicao — G1 deveria ter exatamente 1 aprovacao vigente (%)', v_vig;
  end if;
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id = v_alfa;

  v_res := public.meta_invalidar_aprovacoes(v_g1, v_alfa,
    'segunda invalidacao sem fatos vigentes (P3)', 5, v_a1,
    'f1700000-0000-0000-0000-000000000145');
  if (v_res->>'invalidated')::int <> 0 then
    raise exception '[FAIL] F8: replay TEMPORAL do NO-OP deveria continuar invalidated = 0 (%)', v_res;
  end if;
  if v_res->>'aprovacao_id' is not null then
    raise exception '[FAIL] F8: o replay TEMPORAL devolveu fato revogado (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] F8: o replay TEMPORAL invalidou a NOVA aprovacao vigente (%)', v_n;
  end if;
  if not exists (
    select 1 from public.evaluation_goal_approvals a
     where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null
       and a.id = (v_evento.result_entity_id)
       and a.version = 0
  ) then
    raise exception '[FAIL] F8: a nova aprovacao vigente foi alterada pelo replay temporal';
  end if;
  if (select count(*) from public.evaluation_goal_events where organization_id = v_alfa) <> v_evt then
    raise exception '[FAIL] F8: o replay TEMPORAL gravou evento adicional';
  end if;
  if (select count(*) from public.evaluation_goal_events e
       where e.organization_id = v_alfa
         and e.operation_id = 'f1700000-0000-0000-0000-000000000145') <> 1 then
    raise exception '[FAIL] F8: deve existir APENAS UM evento para o NO-OP';
  end if;

  -- (F9) mesmo operation_id com PAYLOAD DIVERGENTE => CONFLICT (nada muda).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_invalidar_aprovacoes(v_g1, v_alfa,
      'payload divergente com o mesmo operation_id (P3)', 5, v_a1,
      'f1700000-0000-0000-0000-000000000145');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] F9: payload divergente no mesmo operation_id deveria ser CONFLICT (recebido %)', v_msg;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] F9: a recusa por payload divergente alterou a aprovacao vigente (%)', v_n;
  end if;
  if (select count(*) from public.evaluation_goal_events where organization_id = v_alfa) <> v_evt then
    raise exception '[FAIL] F9: a recusa por payload divergente gravou evento';
  end if;

  raise notice '[PASS] F: invalidacao soberana (motivo, stale, cross-tenant, fato preservado com version+1 e evento) com replay idempotente, NO-OP SEM fato vigente REGISTRADO na trilha (operation_id consumido, result_entity_id NULL), replay IMEDIATO e TEMPORAL (nova aprovacao vigente preservada), payload divergente => CONFLICT e reaprovacao gerando novo fato';
end $$;

-- ============================================================================
-- 6-bis) G) Meta EXCLUIDA: aprovacao/invalidacao recusadas e fatos preservados
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_g2   uuid := 'f1000000-0000-0000-0000-000000000002';
  v_a1   uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_ok   boolean;
  v_msg  text;
  v_n    int;
begin
  if not exists (select 1 from public.evaluation_goals g where g.id = v_g2 and g.excluida) then
    raise exception '[FAIL] G: pre-condicao — G2 deveria estar excluida logicamente';
  end if;

  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g2, v_alfa, 'COORDENADOR', 'aprovacao em meta excluida (P3)',
      1, v_a1, 'f1700000-0000-0000-0000-000000000151');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] G: aprovacao em meta excluida deveria ser CONFLICT (recebido %)', v_msg;
  end if;

  v_ok := false; v_msg := null;
  begin
    perform public.meta_invalidar_aprovacoes(v_g2, v_alfa, 'invalidacao em meta excluida (P3)',
      1, v_a1, 'f1700000-0000-0000-0000-000000000152');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] G: invalidacao em meta excluida deveria ser CONFLICT (recebido %)', v_msg;
  end if;

  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g2 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] G: o fato historico da meta excluida deveria permanecer vigente (%)', v_n;
  end if;

  raise notice '[PASS] G: meta excluida recusa aprovacao e invalidacao e PRESERVA os fatos historicos (soft delete e terminal, nao apaga nem invalida artificialmente)';
end $$;

-- ============================================================================
-- 8) I) Estrutura viva/overlay NAO transfere autoridade (fail-closed)
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_g1   uuid := 'f1000000-0000-0000-0000-000000000001';
  v_a1   uuid := 'f1c00000-0000-0000-0000-000000000001';
  v_a4   uuid := 'f1c00000-0000-0000-0000-000000000004';
  v_ok   boolean;
  v_msg  text;
begin
  -- A ocorrencia POSTERIOR (overlay de substituicao temporaria) de GESTAO_CADEIA
  -- ja existe em EV1 (c5) e nunca foi reconhecida (B3). Agora ENCERRAMOS a
  -- ocorrencia ORIGINAL (c1): o papel passa a NAO ser reconhecido — o contrato
  -- NUNCA promove o overlay a autoridade (fail-closed).
  update public.evaluation_participants
     set status = 'ended', valid_to = now()
   where id = 'f1300000-0000-0000-0000-000000000001';

  if public.f5_10_aprovador_congelado(v_g1, v_alfa, 'GERENTE') is not null then
    raise exception '[FAIL] I: com a ocorrencia ORIGINAL encerrada o papel deveria ser NAO reconhecido';
  end if;

  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g1, v_alfa, 'GERENTE', 'probe de overlay (P3)', 5, v_a1,
      'f1700000-0000-0000-0000-000000000171');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] I: papel encerrado deveria ser CONFLICT fail-closed (recebido %)', v_msg;
  end if;

  v_ok := false;
  begin
    perform public.meta_aprovar(v_g1, v_alfa, 'GERENTE', 'probe de overlay (P3)', 5, v_a4,
      'f1700000-0000-0000-0000-000000000172');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%';
  end;
  if not v_ok then
    raise exception '[FAIL] I: o overlay posterior NAO pode aprovar (fail-closed)';
  end if;

  raise notice '[PASS] I: ocorrencia ORIGINAL encerrada => papel NAO reconhecido (fail-closed) e overlay posterior nunca assume a autoridade — nenhuma hierarquia viva decide aprovacao';
end $$;

-- ============================================================================
-- 9) J) ACL, anti-escopo e ausencia de DELETE de fatos
-- ============================================================================
do $$
declare
  v_fns  text[] := array[
    'meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)',
    'meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'f5_10_aprovador_congelado(uuid, uuid, text)',
    'f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid)',
    'f5_10_derivar_operation_id(uuid, text)'];
  v_fn   text;
  v_rec  record;
  v_tab  text;
  v_def  text;
  v_prob text[] := array[]::text[];
  v_n    int;
  v_msg  text;
  v_ok   boolean;
  v_antes int;
  v_alvo uuid;
begin
  -- (J1) superficie: INVOKER, search_path, EXECUTE so service_role, sem DELETE.
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
    if position('delete from' in v_rec.def) > 0 or position('truncate' in v_rec.def) > 0 then
      v_prob := v_prob || ('funcao com DELETE/TRUNCATE: ' || v_fn);
    end if;
  end loop;

  -- (J2) nenhuma fonte VIVA no SQL de decisao de aprovacao.
  foreach v_fn in array array[
    'meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'f5_10_aprovador_congelado(uuid, uuid, text)'] loop
    select lower(pg_get_functiondef(p.oid)) into v_def
      from pg_proc p where p.oid = to_regprocedure('public.' || v_fn);
    foreach v_tab in array array['position_reporting_lines', 'occupations',
                                 'organizacao_resolver_', 'collegiate_'] loop
      if position(v_tab in v_def) > 0 then
        v_prob := v_prob || ('estrutura VIVA (' || v_tab || ') em ' || v_fn);
      end if;
    end loop;
  end loop;

  -- (J3) derivacao na fonte congelada e D19 conectada.
  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p where p.oid = to_regprocedure('public.f5_10_aprovador_congelado(uuid, uuid, text)');
  if position('evaluation_participants' in v_def) = 0
     or position('evaluations' in v_def) = 0 then
    v_prob := v_prob || 'derivacao sem a estrutura CONGELADA (evaluations/evaluation_participants)';
  end if;
  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p where p.oid = to_regprocedure('public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)');
  if position('f5_10_invalidar_aprovacoes_vigentes' in v_def) = 0
     or position('ciclo_lock_organizacao' in v_def) = 0 then
    v_prob := v_prob || 'meta_editar sem D19 ou sem o lock normativo';
  end if;

  -- (J4) anti-escopo: nenhuma RPC de meta/goal alem das 9 do contrato P2+P3.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%')
     and p.proname <> all (array[
       'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
       'meta_revisar_finalizacao', 'meta_excluir', 'meta_definir_limites_do_ciclo',
       'meta_aprovar', 'meta_invalidar_aprovacoes']);
  if v_n <> 0 then
    v_prob := v_prob || format('%s RPC(s) de meta fora do contrato P2+P3', v_n);
  end if;
  foreach v_fn in array array['meta_listar_por_escopo', 'goal_listar', 'goal_aprovar',
                              'meta_ler_por_escopo'] loop
    if exists (select 1 from pg_proc p
                where p.pronamespace = 'public'::regnamespace and p.proname = v_fn) then
      v_prob := v_prob || ('antecipacao de fase futura: ' || v_fn);
    end if;
  end loop;

  -- (J5) deny-by-default e nenhum privilegio de cliente nas 4 tabelas.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = v_tab) then
      v_prob := v_prob || ('policy criada em ' || v_tab || ' (P4 nao antecipada)');
    end if;
    if has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_tab, 'SELECT') then
      v_prob := v_prob || ('leitura de cliente aberta em ' || v_tab);
    end if;
    if has_table_privilege('service_role', 'public.' || v_tab, 'DELETE')
       or has_table_privilege('service_role', 'public.' || v_tab, 'TRUNCATE') then
      v_prob := v_prob || ('service_role com DELETE/TRUNCATE em ' || v_tab);
    end if;
  end loop;

  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_prob := v_prob || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  if array_length(v_prob, 1) is not null then
    raise exception '[FAIL] J: %', array_to_string(v_prob, '; ');
  end if;

  -- (J6) DELETE FISICO de fato de aprovacao negado no proprio banco.
  select a.id into v_alvo from public.evaluation_goal_approvals a
   where a.organization_id = 'f1a00000-0000-0000-0000-0000000000a1'
   order by a.created_at limit 1;
  select count(*) into v_antes from public.evaluation_goal_approvals
   where organization_id = 'f1a00000-0000-0000-0000-0000000000a1';
  v_ok := false; v_msg := null;
  begin
    set role service_role;
    delete from public.evaluation_goal_approvals where id = v_alvo;
    reset role;
  exception when others then
    v_ok := (sqlstate = '42501' or sqlerrm like '%append-only%');
    v_msg := sqlerrm;
    reset role;
  end;
  if not v_ok then
    raise exception '[FAIL] J6: DELETE de fato por service_role deveria ser negado (recebido %)', v_msg;
  end if;
  if (select count(*) from public.evaluation_goal_approvals
       where organization_id = 'f1a00000-0000-0000-0000-0000000000a1') <> v_antes then
    raise exception '[FAIL] J6: o fato foi APAGADO fisicamente';
  end if;

  raise notice '[PASS] J: 2 RPCs + 3 helpers INVOKER com EXECUTE so service_role, derivacao na estrutura CONGELADA, D19 conectada, zero DELETE de fatos, zero policy/P4/P5 e catalogo intacto';
end $$;

-- ============================================================================
-- 10) K) Estado final deterministico
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f1a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f1a00000-0000-0000-0000-0000000000b1';
  v_g1     uuid := 'f1000000-0000-0000-0000-000000000001';
  v_fatos  int;
  v_vig    int;
  v_rev    int;
  v_evt    int;
  v_tipo   text;
  v_rec    record;
  v_meta   record;
  v_n      int;
begin
  select count(*), count(*) filter (where revogado_em is null),
         count(*) filter (where revogado_em is not null)
    into v_fatos, v_vig, v_rev
    from public.evaluation_goal_approvals
   where organization_id in (v_alfa, v_beta);
  if v_fatos <> 5 or v_vig <> 2 or v_rev <> 3 then
    raise exception '[FAIL] K: fatos inesperados (total=%, vigentes=%, revogados=%)',
      v_fatos, v_vig, v_rev;
  end if;

  -- Coerencia fato x trilha: um evento de aprovacao por fato e um de invalidacao
  -- para cada fato revogado.
  for v_rec in
    select a.id, a.revogado_em
      from public.evaluation_goal_approvals a
     where a.organization_id = v_alfa
  loop
    select count(*) into v_evt from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.result_entity_id = v_rec.id
       and e.event_type in ('APROVACAO_COORDENADOR', 'APROVACAO_GERENTE');
    if v_evt <> 1 then
      raise exception '[FAIL] K: o fato % deveria ter exatamente 1 evento de aprovacao (%)',
        v_rec.id, v_evt;
    end if;
    select count(*) into v_evt from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.result_entity_id = v_rec.id
       and e.event_type = 'APROVACAO_INVALIDADA';
    if (v_rec.revogado_em is null and v_evt <> 0)
       or (v_rec.revogado_em is not null and v_evt <> 1) then
      raise exception '[FAIL] K: coerencia fato x invalidacao quebrada para % (%)', v_rec.id, v_evt;
    end if;
  end loop;

  select count(*) into v_evt from public.evaluation_goal_events where organization_id = v_alfa;
  if v_evt <> 19 then
    raise exception '[FAIL] K: trilha de Alfa deveria ter 19 eventos, encontrado %', v_evt;
  end if;
  -- Exatamente UM evento de invalidacao sem fato associado: o registro do NO-OP.
  select count(*) into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.event_type = 'APROVACAO_INVALIDADA'
     and e.result_entity_id is null;
  if v_evt <> 1 then
    raise exception '[FAIL] K: esperado exatamente 1 evento de invalidacao SEM fato (NO-OP), encontrado %', v_evt;
  end if;
  select count(*) into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.event_type = 'APROVACAO_INVALIDADA'
     and e.result_entity_id is not null;
  if v_evt <> 3 then
    raise exception '[FAIL] K: esperados 3 eventos de invalidacao COM fato revogado, encontrado %', v_evt;
  end if;
  select count(*) into v_evt from public.evaluation_goal_events where organization_id = v_beta;
  if v_evt <> 1 then
    raise exception '[FAIL] K: trilha de Beta deveria ter 1 evento, encontrado %', v_evt;
  end if;

  for v_rec in
    select e.event_type as tipo, count(*) as qtd
      from public.evaluation_goal_events e
     where e.organization_id = v_alfa
     group by e.event_type
  loop
    v_tipo := v_rec.tipo;
    if (v_tipo = 'CRIADA' and v_rec.qtd <> 4)
       or (v_tipo = 'APROVACAO_GERENTE' and v_rec.qtd <> 4)
       or (v_tipo = 'APROVACAO_COORDENADOR' and v_rec.qtd <> 1)
       or (v_tipo = 'APROVACAO_INVALIDADA' and v_rec.qtd <> 4)
       or (v_tipo = 'EDITADA' and v_rec.qtd <> 2)
       or (v_tipo = 'PROGRESSO_ATUALIZADO' and v_rec.qtd <> 1)
       or (v_tipo = 'FINALIZADA' and v_rec.qtd <> 1)
       or (v_tipo = 'REVISAO_FINALIZACAO' and v_rec.qtd <> 1)
       or (v_tipo = 'EXCLUIDA' and v_rec.qtd <> 1) then
      raise exception '[FAIL] K: contagem inesperada de % (%)', v_tipo, v_rec.qtd;
    end if;
  end loop;

  select count(*) into v_n from (
    select e.operation_id from public.evaluation_goal_events e
     where e.organization_id in (v_alfa, v_beta)
     group by e.operation_id having count(*) > 1
  ) t;
  if v_n <> 0 then
    raise exception '[FAIL] K: operation_id duplicado na trilha (%)', v_n;
  end if;

  select g.status, g.version into v_meta from public.evaluation_goals g where g.id = v_g1;
  if v_meta.status <> 'NAO_ATINGIDA' or v_meta.version <> 5 then
    raise exception '[FAIL] K: estado final de G1 inesperado (status=%, version=%)',
      v_meta.status, v_meta.version;
  end if;
  select l.quantidade into v_n from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.tipo = 'NEGOCIO_PROJETO';
  if v_n <> 3 then
    raise exception '[FAIL] K: quota final de NEGOCIO_PROJETO deveria ser 3 (%)', v_n;
  end if;
  select l.quantidade into v_n from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.tipo = 'INDIVIDUAL';
  if v_n <> 2 then
    raise exception '[FAIL] K: quota final de INDIVIDUAL deveria ser 2 (alterada no bloco E7) (%)', v_n;
  end if;

  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname like '\_mut\_f5\_10\_p3%';
  if v_n <> 0 then
    raise exception '[FAIL] K: artefato de mutacao deixado no schema (%)', v_n;
  end if;
  select count(*) into v_n from pg_trigger t
   where t.tgname like '\_mut\_f5\_10\_p3%' and not t.tgisinternal;
  if v_n <> 0 then
    raise exception '[FAIL] K: gatilho de mutacao deixado no schema (%)', v_n;
  end if;

  raise notice '[PASS] K: estado final deterministico (5 fatos de aprovacao — 2 vigentes e 3 revogados —, 19 eventos em Alfa e 1 em Beta, exatamente 1 evento de invalidacao sem fato (NO-OP registrado), status funcional de G1 intacto e nenhum residuo)';
end $$;

-- ============================================================================
-- 11) Resumo
-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F5-10 P3: aprovacoes e invalidacao validadas — fato auditavel (GERENTE = GESTAO_CADEIA original; COORDENADOR = GESTAO_DIRETA original e distinta), legitimidade EXCLUSIVAMENTE da estrutura congelada, expected_version sob lock, idempotencia por operation_id, evento append-only por fato/mutacao, autoria soberana, matriz D19 conectada a meta_editar, reaprovacao com historico preservado, rollback total e zero DELETE fisico.';
  raise notice '============================================================';
end $$;
