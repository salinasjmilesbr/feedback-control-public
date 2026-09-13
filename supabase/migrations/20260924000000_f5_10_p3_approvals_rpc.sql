-- ============================================================================
-- F5-10 P3 (Issue #214): APROVACOES e INVALIDACAO de metas.
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md (D1-D25; §7 lifecycle, §9 aprovacoes,
-- legitimidade e matriz de invalidacao, §10 autorizacao, §12 concorrencia/versao/
-- idempotencia, §13 contrato RPC, §19 P3) e a Issue #214.
-- Pre-requisito: P1 (`20260922000000_f5_10_p1_goals_schema.sql`) e P2
-- (`20260923000000_f5_10_p2_goals_rpc.sql`).
--
-- Entregue AQUI (e somente isto):
--   1) `meta_aprovar`              — APROVACAO_COORDENADOR / APROVACAO_GERENTE
--   2) `meta_invalidar_aprovacoes` — APROVACAO_INVALIDADA (preserva historico)
--   3) reconexao da matriz D19 em `meta_editar` (create or replace da RPC da P2,
--      SEM editar a migration historica ja mergeada da P2)
--   4) helpers soberanos reutilizaveis (derivacao do aprovador congelado,
--      invalidacao das aprovacoes vigentes e derivacao deterministica de
--      operation_id dos sub-eventos da mesma intencao)
--
-- LEGITIMIDADE (D14/D15 + §9.1) — fonte UNICA e CONGELADA:
--   - a avaliacao do dono da meta e resolvida por
--     `(organization_id, cycle_id, evaluated_collaborator_id)` com
--     `status <> 'CANCELADA'`; ausencia OU duplicidade => FAIL-CLOSED;
--   - GERENTE  = ocorrencia ORIGINAL de `GESTAO_CADEIA` em
--     `evaluation_participants` (menor `valid_from`; empate => menor
--     `collaborator_id`);
--   - COORDENADOR = ocorrencia ORIGINAL de `GESTAO_DIRETA`, SOMENTE quando existir
--     e for DISTINTA do responsavel de cadeia; caso contrario FAIL-CLOSED;
--   - a ocorrencia escolhida precisa estar VIGENTE (`status = 'active'` e
--     `valid_to is null`); caso contrario o papel NAO e reconhecido (nunca
--     "aprova por falta de prova" nem "aprova pela estrutura viva");
--   - o ATOR precisa ser o COLABORADOR congelado daquele papel, resolvido por
--     `resolver_collaborador_vinculado` (membro ativo + perfil ativo + vinculo
--     ativo e UNICO; ambiguedade => FAIL-CLOSED). NUNCA se usa matricula, nome,
--     papel declarado pelo cliente como autoridade, cargo, hierarquia viva
--     (`position_reporting_lines`/`occupations`/`organizacao_resolver_*`) nem
--     qualquer estrutura fora do snapshot do ciclo.
--
-- Fora do escopo (fases seguintes), deliberadamente NAO implementado:
--   - P4: matriz funcional `goal.read`/`goal.write`/`goal.approve`, Policy Engine,
--     RLS own-tenant funcional, grants ao cliente e a RPC de leitura com gate. O
--     catalogo `goal.approve` continua sendo o gate funcional FINAL a ser
--     conectado em P4/P5 — nesta fase a RPC revalida apenas ator/perfil/
--     membership/tenant + legitimidade ESTRUTURAL congelada;
--   - P5: Edge `metas`, contrato transportavel e adapter;
--   - P6: cutover, backfill, frontend e consumidores;
--   - P7: bateria integrada e concorrencia real entre duas sessoes;
--   - F5-11 (observacoes): intocado.
--
-- Invariantes (D1-D25) preservadas:
--   - a aprovacao e FATO auditavel em `evaluation_goal_approvals`; NUNCA campo
--     mutavel da meta, NUNCA `status` funcional (D2/D3) e NUNCA sobrescrita:
--     invalidar apenas preenche `revogado_em`/`revogado_motivo` e incrementa a
--     `version` da PROPRIA linha do fato; NENHUM `DELETE` (soft delete dos fatos);
--   - uma unica aprovacao VIGENTE por `(goal_id, papel)` (indice unico parcial da
--     P1) — reaprovar depois de invalidar CRIA NOVO FATO e preserva o revogado;
--   - aprovacao NAO muda `status` nem `version` da meta, NAO finaliza, NAO exige
--     finalizacao: `meta_finalizar` continua independente (D17);
--   - `expected_version` obrigatorio, comparado APOS o lock normativo e o
--     `SELECT ... FOR UPDATE`; divergencia => `F5_10_CONFLICT` (D12);
--   - idempotencia por `unique (organization_id, operation_id)` de
--     `evaluation_goal_events` com `payload_hash` SHA-256 derivado server-side;
--     replay identico devolve o MESMO resultado; intencao divergente => CONFLICT;
--   - UM evento append-only por fato/mutacao, na MESMA transacao, com autoria
--     soberana (`actor_user_profile_id` + `actor_membership_id` resolvidos no
--     banco) e `before_value`/`after_value` suficientes para reconstrucao;
--   - lock: MESMA familia normativa dos ciclos
--     (`public.ciclo_lock_organizacao`, chave
--     `evaluation_cycles:<organization_id>`) no inicio de toda mutacao —
--     NENHUMA familia/chave nova;
--   - rollback TOTAL em qualquer falha (nenhum fato sem evento e nenhum evento
--     sem mutacao).
--
-- DESVIOS DECLARADOS para auditoria:
--   (a) `expected_version` das operacoes de aprovacao refere-se a versao da
--       META (`evaluation_goals.version`) e e comparado sob o lock + FOR UPDATE.
--       A aprovacao NAO incrementa a versao da meta (o §7 nao define `version+1`
--       para `aprovar`; o fato tem `version` propria, que nasce em 0 e avanca
--       apenas quando o proprio fato e invalidado) — a versao da meta continua
--       medindo apenas as mutacoes da meta;
--   (b) `p_payload_hash` NAO e parametro: derivado server-side (mesmo desvio ja
--       ratificado nas fases anteriores);
--   (c) a invalidacao em si NAO exige ciclo `ATIVO`: ela e o inverso da aprovacao
--       sobre FATOS e nao altera definicao/estado funcional da meta; o gate de
--       ciclo permanece nas operacoes materiais (criar/editar/progredir/
--       finalizar/aprovar). A invalidacao conectada por D19 roda dentro de
--       `meta_editar`, que ja exige ciclo ATIVO;
--   (d) `meta_invalidar_aprovacoes` sem aprovacao VIGENTE e NO-OP auditavel:
--       devolve `invalidated = 0`, NAO grava evento (nenhuma mutacao sem evento) e
--       NAO consome `operation_id` — fatos ja revogados NUNCA sao re-mutados;
--   (e) os sub-eventos de uma MESMA intencao (invalidacao de mais de um papel, ou
--       invalidacao disparada por `meta_editar`) precisam de `operation_id`
--       distinto por evento (`unique (organization_id, operation_id)`); a
--       derivacao e DETERMINISTICA
--       (`f5_10_derivar_operation_id(base, sufixo)`, SHA-256 -> uuid) e o
--       `operation_id` da intencao e usado pelo PRIMEIRO evento — replays
--       continuam devolvendo o mesmo resultado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
do $$
declare
  v_faltando text[] := array[]::text[];
  v_fn       text;
  v_tab      text;
  v_prims    text[] := array[
    'evaluation_ator_valido(uuid, uuid)',
    'resolver_collaborador_vinculado(uuid, uuid)',
    'ciclo_lock_organizacao(uuid)'];
  v_rpcs     text[] := array[
    'meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)'];
begin
  -- P1: tabelas de metas com RLS e trilha append-only completa.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if to_regclass('public.' || v_tab) is null then
      v_faltando := v_faltando || ('tabela ' || v_tab);
    elsif not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      v_faltando := v_faltando || ('RLS desabilitada em ' || v_tab);
    end if;
  end loop;

  -- P1: unicidade parcial da aprovacao vigente + trigger de coerencia de autoria.
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_goal_approvals'
       and indexname = 'uq_evaluation_goal_approvals_goal_papel_vigente'
  ) then
    v_faltando := v_faltando || 'uq_evaluation_goal_approvals_goal_papel_vigente';
  end if;
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.evaluation_goal_approvals'::regclass
       and tgname = 'trg_evaluation_goal_approvals_autoria' and not tgisinternal
  ) then
    v_faltando := v_faltando || 'trg_evaluation_goal_approvals_autoria';
  end if;

  -- P1: idempotencia da trilha, 3 gatilhos append-only e tipos APROVACAO_*.
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_goal_events'::regclass
       and conname = 'uq_evaluation_goal_events_org_operation' and contype = 'u'
  ) then
    v_faltando := v_faltando || 'uq_evaluation_goal_events_org_operation';
  end if;
  foreach v_fn in array array[
    'trg_evaluation_goal_events_append_only', 'trg_evaluation_goal_events_no_delete',
    'trg_evaluation_goal_events_no_truncate'] loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = 'public.evaluation_goal_events'::regclass
         and tgname = v_fn and not tgisinternal
    ) then
      v_faltando := v_faltando || ('trigger ' || v_fn);
    end if;
  end loop;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_goal_events'::regclass
       and c.conname = 'ck_evaluation_goal_events_event_type' and c.contype = 'c'
       and position('APROVACAO_COORDENADOR' in pg_get_constraintdef(c.oid)) > 0
       and position('APROVACAO_GERENTE' in pg_get_constraintdef(c.oid)) > 0
       and position('APROVACAO_INVALIDADA' in pg_get_constraintdef(c.oid)) > 0
  ) then
    v_faltando := v_faltando || 'event_type sem os tipos APROVACAO_*';
  end if;

  -- P2: as 7 RPCs soberanas continuam existentes.
  foreach v_fn in array v_rpcs loop
    if to_regprocedure('public.' || v_fn) is null then
      v_faltando := v_faltando || ('RPC ' || v_fn);
    end if;
  end loop;

  -- F5-06: avaliacao do dono + snapshot congelado de participantes + vinculo.
  foreach v_tab in array array['evaluations', 'evaluation_participants'] loop
    if to_regclass('public.' || v_tab) is null then
      v_faltando := v_faltando || ('tabela ' || v_tab);
    end if;
  end loop;
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluations'
       and indexname = 'uq_evaluations_org_cycle_collaborator_nao_cancelada'
  ) then
    v_faltando := v_faltando || 'uq_evaluations_org_cycle_collaborator_nao_cancelada';
  end if;
  if to_regclass('public.membership_collaborator_links') is null then
    v_faltando := v_faltando || 'membership_collaborator_links (F5-02)';
  end if;

  -- Primitivas reutilizadas: existem e sao executaveis pelo caminho server-side.
  foreach v_fn in array v_prims loop
    if to_regprocedure('public.' || v_fn) is null then
      v_faltando := v_faltando || ('funcao ' || v_fn);
    elsif has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_faltando := v_faltando || ('EXECUTE de service_role em ' || v_fn);
    end if;
  end loop;

  if array_length(v_faltando, 1) is not null then
    raise exception
      'F5_10_P3_INCOMPATIBLE_BASELINE: baseline incompativel com o contrato da P3: %',
      array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-10 P3: preflight OK (P1 + P2 + F5-06/avaliacao congelada + primitivas de ator/vinculo/lock disponiveis)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) `f5_10_derivar_operation_id` — idempotencia de sub-eventos da MESMA intencao
-- ----------------------------------------------------------------------------
-- `evaluation_goal_events` tem `unique (organization_id, operation_id)`: uma
-- intencao que produz MAIS DE UM evento (invalidacao de dois papeis, ou
-- invalidacao disparada por `meta_editar`) precisa de `operation_id` distinto por
-- evento. A derivacao e DETERMINISTICA (SHA-256 -> uuid) para que replays sejam
-- reproduziveis; o `operation_id` da intencao fica com o PRIMEIRO evento.
create or replace function public.f5_10_derivar_operation_id(
  p_base uuid,
  p_sufixo text
)
returns uuid
language sql
immutable
security invoker
set search_path = public
as $$
  select (
    substr(h, 1, 8) || '-' || substr(h, 9, 4) || '-' || substr(h, 13, 4)
    || '-' || substr(h, 17, 4) || '-' || substr(h, 21, 12)
  )::uuid
    from (
      select encode(sha256(convert_to(
        coalesce(p_base::text, '') || ':' || coalesce(p_sufixo, ''), 'UTF8')), 'hex') as h
    ) t;
$$;

comment on function public.f5_10_derivar_operation_id(uuid, text) is
  'F5-10 P3: deriva de forma DETERMINISTICA o operation_id de um sub-evento da '
  'mesma intencao (SHA-256 -> uuid). Necessario porque a trilha tem '
  'unique (organization_id, operation_id) e uma intencao pode produzir mais de um '
  'evento (invalidacao de dois papeis / invalidacao disparada por meta_editar).';

-- ----------------------------------------------------------------------------
-- 2) `f5_10_aprovador_congelado` — fonte UNICA da legitimidade (D14/D15/§9.1)
-- ----------------------------------------------------------------------------
-- Devolve o COLABORADOR congelado do papel pedido, ou NULL para QUALQUER forma de
-- ausencia/ambiguidade/inconsistencia (fail-closed). Somente LEITURA da estrutura
-- CONGELADA (`evaluations` + `evaluation_participants`); nenhuma estrutura viva
-- (`position_reporting_lines`, `occupations`, `organizacao_resolver_*`).
create or replace function public.f5_10_aprovador_congelado(
  p_goal_id uuid,
  p_organization_id uuid,
  p_papel text
)
returns uuid
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_cycle     uuid;
  v_dono      uuid;
  v_avaliacao uuid;
  v_qtd       integer;
  v_papel     text;
  v_alvo      uuid;
  v_status    text;
  v_valid_to  timestamptz;
  v_cadeia    uuid;
begin
  if p_goal_id is null or p_organization_id is null then
    return null;
  end if;

  -- Meta do tenant: cross-tenant/inexistente => NULL (fail-closed).
  select g.cycle_id, g.collaborator_id into v_cycle, v_dono
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = p_organization_id;
  if v_cycle is null then
    return null;
  end if;

  -- Avaliacao NAO CANCELADA do dono da meta; ausencia OU duplicidade => NULL.
  -- (Nao ha agregado MIN/MAX para `uuid` no PostgreSQL: conta-se primeiro e so
  --  se busca a linha quando a cardinalidade e exatamente 1.)
  select count(*) into v_qtd
    from public.evaluations e
   where e.organization_id = p_organization_id
     and e.cycle_id = v_cycle
     and e.evaluated_collaborator_id = v_dono
     and e.status <> 'CANCELADA';
  if v_qtd <> 1 then
    return null;
  end if;

  select e.id into v_avaliacao
    from public.evaluations e
   where e.organization_id = p_organization_id
     and e.cycle_id = v_cycle
     and e.evaluated_collaborator_id = v_dono
     and e.status <> 'CANCELADA';

  -- Papel pedido -> papel CONGELADO da avaliacao (allowlist fechada).
  v_papel := case p_papel
               when 'GERENTE'     then 'GESTAO_CADEIA'
               when 'COORDENADOR' then 'GESTAO_DIRETA'
               else null
             end;
  if v_papel is null then
    return null;
  end if;

  -- Ocorrencia ORIGINAL do papel: menor `valid_from`; empate => menor
  -- `collaborator_id` (regra 4 do §9.1) — a estrutura viva NAO influencia.
  select p.collaborator_id, p.status, p.valid_to
    into v_alvo, v_status, v_valid_to
    from public.evaluation_participants p
   where p.evaluation_id = v_avaliacao
     and p.organization_id = p_organization_id
     and p.role_type = v_papel
   order by p.valid_from asc, p.collaborator_id asc
   limit 1;
  if v_alvo is null then
    return null;
  end if;

  -- Regra 5: a ocorrencia escolhida precisa estar VIGENTE (fail-closed).
  if v_status is distinct from 'active' or v_valid_to is not null then
    return null;
  end if;

  -- COORDENADOR somente quando DISTINTO do responsavel de cadeia.
  if p_papel = 'COORDENADOR' then
    select p.collaborator_id into v_cadeia
      from public.evaluation_participants p
     where p.evaluation_id = v_avaliacao
       and p.organization_id = p_organization_id
       and p.role_type = 'GESTAO_CADEIA'
     order by p.valid_from asc, p.collaborator_id asc
     limit 1;
    if v_cadeia is null or v_cadeia = v_alvo then
      return null;
    end if;
  end if;

  return v_alvo;
end;
$$;

comment on function public.f5_10_aprovador_congelado(uuid, uuid, text) is
  'F5-10 P3 (D14/D15/§9.1): resolve o COLABORADOR congelado do papel pedido '
  '(GERENTE = ocorrencia ORIGINAL de GESTAO_CADEIA; COORDENADOR = ocorrencia '
  'ORIGINAL de GESTAO_DIRETA, somente quando distinta da cadeia) a partir da '
  'avaliacao NAO CANCELADA do dono da meta. Menor valid_from; empate => menor '
  'collaborator_id. Ausencia de meta/avaliacao, duplicidade de avaliacoes, '
  'ocorrencia encerrada ou papel nao reconhecido => NULL (FAIL-CLOSED). Le '
  'SOMENTE estrutura congelada (evaluations + evaluation_participants); nenhuma '
  'hierarquia viva, matricula, nome ou papel declarado pelo cliente.';

-- ----------------------------------------------------------------------------
-- 3) `meta_aprovar` — APROVACAO_COORDENADOR / APROVACAO_GERENTE (D2/D14/D15)
-- ----------------------------------------------------------------------------
-- A aprovacao e FATO auditavel: cria UMA linha em `evaluation_goal_approvals`
-- (vigente = `revogado_em is null`, unica por `(goal_id, papel)`) + UM evento
-- append-only na MESMA transacao. NAO altera `status`/`version` da meta, NAO
-- finaliza, NAO exige finalizacao e NAO sobrescreve fato anterior.
create or replace function public.meta_aprovar(
  p_goal_id uuid,
  p_organization_id uuid,
  p_papel text,
  p_motivo text,
  p_expected_version integer,
  p_actor_user_profile_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org          uuid := p_organization_id;
  v_hash         text;
  v_evento       record;
  v_membership   uuid;
  v_meta         record;
  v_ciclo        text;
  v_aprovador    uuid;
  v_qtd          integer;
  v_ator_colab   uuid;
  v_aprovacao    uuid;
  v_versao_fato  integer;
  v_tipo_evento  text;
  v_instante     timestamptz := now();
begin
  -- (1) Forma do payload.
  if p_goal_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: goal_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_papel is null or p_papel not in ('COORDENADOR', 'GERENTE') then
    raise exception 'F5_10_INVALID_INPUT: papel deve ser COORDENADOR ou GERENTE';
  end if;
  if p_motivo is not null and (p_motivo = '' or p_motivo <> btrim(p_motivo)) then
    raise exception 'F5_10_INVALID_INPUT: motivo nao pode ser vazio nem ter espacos nas bordas';
  end if;
  if p_expected_version is null then
    raise exception 'F5_10_INVALID_INPUT: expected_version obrigatorio';
  end if;

  v_tipo_evento := case p_papel
                     when 'COORDENADOR' then 'APROVACAO_COORDENADOR'
                     else 'APROVACAO_GERENTE'
                   end;

  -- (2) Hash canonico da INTENCAO (derivado server-side — desvio (b)).
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_aprovar',
    'organization_id', v_org,
    'goal_id', p_goal_id,
    'papel', p_papel,
    'motivo', p_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (3) Ator soberano do tenant (perfil ativo + membership ativa).
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

  -- (4) Idempotencia — caminho rapido.
  select e.goal_id, e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_goal_events e
   where e.organization_id = v_org and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'goal_id', v_evento.goal_id,
      'aprovacao_id', v_evento.result_entity_id,
      'papel', v_evento.after_value->>'papel',
      'version', (v_evento.after_value->>'versao_meta')::integer,
      'status', v_evento.after_value->>'status_meta',
      'aprovado', true);
  end if;

  -- (5) Membership do ator (autoria soberana da trilha).
  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_10_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (6) MESMA familia normativa de lock dos ciclos (D10).
  perform public.ciclo_lock_organizacao(v_org);

  -- (7) Idempotencia sob o lock.
  select e.goal_id, e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_goal_events e
   where e.organization_id = v_org and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'goal_id', v_evento.goal_id,
      'aprovacao_id', v_evento.result_entity_id,
      'papel', v_evento.after_value->>'papel',
      'version', (v_evento.after_value->>'versao_meta')::integer,
      'status', v_evento.after_value->>'status_meta',
      'aprovado', true);
  end if;

  -- (8) Meta do MESMO tenant (cross-tenant => NOT_FOUND) + lock da linha.
  select g.id, g.cycle_id, g.status, g.excluida, g.version
    into v_meta
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
  end if;

  -- (9) Meta excluida logicamente e terminal: nao aceita aprovacao.
  if v_meta.excluida then
    raise exception 'F5_10_CONFLICT: meta excluida nao aceita aprovacao';
  end if;

  -- (10) Aprovacao exige ciclo ATIVO (§7: "aprovar | viva, ciclo ATIVO").
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = v_meta.cycle_id and c.organization_id = v_org;
  if v_ciclo is distinct from 'ATIVO' then
    raise exception 'F5_10_CONFLICT: aprovacao de meta exige ciclo ATIVO (status atual %)',
      coalesce(v_ciclo, 'AUSENTE');
  end if;

  -- (11) expected_version comparado APOS o lock e o SELECT FOR UPDATE (D12).
  if v_meta.version <> p_expected_version then
    raise exception 'F5_10_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- (12) Legitimidade ESTRUTURAL congelada (D14/D15/§9.1): fail-closed quando a
  --      estrutura nao reconhece o papel (sem avaliacao, duplicidade, papel
  --      ausente, ocorrencia encerrada ou coordenador nao distinto).
  v_aprovador := public.f5_10_aprovador_congelado(p_goal_id, v_org, p_papel);
  if v_aprovador is null then
    raise exception
      'F5_10_CONFLICT: papel % nao reconhecido na estrutura CONGELADA da avaliacao do dono da meta (fail-closed)',
      p_papel;
  end if;

  -- (13) O ATOR tem de ser o COLABORADOR congelado daquele papel (vinculo ativo
  --      e UNICO; sem vinculo ou ambiguidade => fail-closed). Nenhuma excecao por
  --      ser owner, por matricula/nome ou por papel declarado no corpo.
  --      (`uuid` nao tem agregado MIN/MAX: conta-se e depois se busca a linha.)
  select count(*) into v_qtd
    from public.resolver_collaborador_vinculado(p_actor_user_profile_id, v_org) c;
  if v_qtd <> 1 then
    raise exception
      'F5_10_FORBIDDEN: ator sem vinculo UNICO de colaborador ativo na organizacao (fail-closed)';
  end if;
  select c.collaborator_id into v_ator_colab
    from public.resolver_collaborador_vinculado(p_actor_user_profile_id, v_org) c;
  if v_ator_colab <> v_aprovador then
    raise exception
      'F5_10_FORBIDDEN: ator nao e o participante congelado do papel % (autoridade vem do snapshot do ciclo)',
      p_papel;
  end if;

  -- (14) Uma unica aprovacao VIGENTE por (meta, papel): a segunda e CONFLICT.
  if exists (
    select 1 from public.evaluation_goal_approvals a
     where a.organization_id = v_org
       and a.goal_id = p_goal_id
       and a.papel = p_papel
       and a.revogado_em is null
  ) then
    raise exception 'F5_10_CONFLICT: ja existe aprovacao vigente do papel % para a meta', p_papel;
  end if;

  -- (15) Fato: linha propria, autoria soberana resolvida no banco.
  insert into public.evaluation_goal_approvals (
    organization_id, goal_id, papel, actor_user_profile_id, actor_membership_id,
    motivo, version
  ) values (
    v_org, p_goal_id, p_papel, p_actor_user_profile_id, v_membership,
    p_motivo, 0
  )
  returning id, version into v_aprovacao, v_versao_fato;

  -- (16) Trilha append-only na MESMA transacao: um evento por FATO, com
  --      before/after suficientes para reconstrucao.
  insert into public.evaluation_goal_events (
    organization_id, goal_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_goal_id, 'evaluation_goal', v_tipo_evento, v_instante,
    p_motivo,
    jsonb_build_object(
      'papel', p_papel, 'vigente', false,
      'versao_meta', v_meta.version, 'status_meta', v_meta.status),
    jsonb_build_object(
      'aprovacao_id', v_aprovacao, 'papel', p_papel, 'vigente', true,
      'decidido_em', v_instante, 'motivo', p_motivo, 'versao_fato', v_versao_fato,
      'versao_meta', v_meta.version, 'status_meta', v_meta.status),
    v_hash, v_aprovacao, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'goal_id', p_goal_id, 'aprovacao_id', v_aprovacao, 'papel', p_papel,
    'version', v_meta.version, 'status', v_meta.status, 'aprovado', true);
end;
$$;

comment on function public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid) is
  'F5-10 P3 (D2/D14/D15/§9.1): registra a APROVACAO como FATO auditavel em '
  '`evaluation_goal_approvals` (uma vigente por meta/papel) + evento '
  'APROVACAO_COORDENADOR/APROVACAO_GERENTE na MESMA transacao. A legitimidade vem '
  'EXCLUSIVAMENTE da estrutura CONGELADA (evaluation_participants da avaliacao nao '
  'cancelada do dono): GERENTE = GESTAO_CADEIA original; COORDENADOR = '
  'GESTAO_DIRETA original e distinta da cadeia; o ator precisa SER o colaborador '
  'congelado (vinculo unico resolvido no banco). expected_version da META '
  'comparado apos o lock normativo e o SELECT FOR UPDATE. NAO altera status/version '
  'da meta, NAO finaliza e NAO exige finalizacao. O gate funcional `goal.approve` '
  'e da fronteira confiavel final (P4/P5).';

-- ----------------------------------------------------------------------------
-- 4) `f5_10_invalidar_aprovacoes_vigentes` — invalidacao com historico (D19)
-- ----------------------------------------------------------------------------
-- Nucleo REUTILIZAVEL da invalidacao (usado pela operacao soberana
-- `meta_invalidar_aprovacoes` e pela matriz D19 dentro de `meta_editar`):
--   - revoga APENAS fatos VIGENTES (`revogado_em is null`) do tenant/meta;
--   - preenche `revogado_em` + `revogado_motivo` e incrementa a `version` da
--     PROPRIA linha do fato (nunca DELETE, nunca reescreve o fato);
--   - grava UM evento `APROVACAO_INVALIDADA` por papel revogado, na MESMA
--     transacao, com autoria soberana;
--   - o `operation_id` recebido fica com o PRIMEIRO evento; os demais usam
--     derivacao deterministica (`f5_10_derivar_operation_id`);
--   - o `payload_hash` recebido e o da INTENCAO que disparou a invalidacao (a RPC
--     soberana passa o proprio hash canonico; `meta_editar` passa o hash da
--     edicao que a motivou) — assim o replay da operacao compara hashes
--     coerentes e nunca acusa intencao divergente por diferenca de derivacao;
--   - retorna o resultado reconstruivel do primeiro evento (para replay).
create or replace function public.f5_10_invalidar_aprovacoes_vigentes(
  p_goal_id uuid,
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_membership_id uuid,
  p_motivo text,
  p_payload_hash text,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_total       integer;
  v_papeis      text[] := array['GERENTE', 'COORDENADOR'];
  v_papel       text;
  v_rec         record;
  v_n           integer := 0;
  v_op_evento   uuid;
  v_primeira_id uuid;
  v_primeiro_papel text;
  v_versao_nova integer;
  v_primeira_versao integer;
  v_instante    timestamptz := now();
begin
  -- Total de fatos VIGENTES ANTES da invalidacao (o evento registra o total para
  -- reconstrucao; fatos ja revogados NUNCA sao re-mutados).
  select count(*) into v_total
    from public.evaluation_goal_approvals a
   where a.organization_id = p_organization_id
     and a.goal_id = p_goal_id
     and a.revogado_em is null;

  if v_total = 0 then
    return jsonb_build_object(
      'invalidated', 0, 'aprovacao_id', null, 'papel', null,
      'versao_fato', null, 'revogado_em', null, 'motivo', p_motivo);
  end if;

  foreach v_papel in array v_papeis loop
    for v_rec in
      select a.id, a.papel, a.version, a.decidido_em, a.motivo
        from public.evaluation_goal_approvals a
       where a.organization_id = p_organization_id
         and a.goal_id = p_goal_id
         and a.papel = v_papel
         and a.revogado_em is null
       order by a.decidido_em asc, a.id asc
       for update
    loop
      v_n := v_n + 1;
      v_op_evento := case when v_n = 1
                          then p_operation_id
                          else public.f5_10_derivar_operation_id(
                                 p_operation_id, v_rec.papel || ':' || v_rec.id::text)
                        end;

      update public.evaluation_goal_approvals
         set revogado_em = v_instante,
             revogado_motivo = p_motivo,
             version = version + 1
       where id = v_rec.id
         and organization_id = p_organization_id
      returning version into v_versao_nova;

      if v_n = 1 then
        v_primeira_id := v_rec.id;
        v_primeiro_papel := v_rec.papel;
        v_primeira_versao := v_versao_nova;
      end if;

      insert into public.evaluation_goal_events (
        organization_id, goal_id, entity_type, event_type, effective_date, reason,
        before_value, after_value, payload_hash, result_entity_id,
        actor_user_profile_id, actor_membership_id, operation_id
      ) values (
        p_organization_id, p_goal_id, 'evaluation_goal', 'APROVACAO_INVALIDADA',
        v_instante, p_motivo,
        jsonb_build_object(
          'aprovacao_id', v_rec.id, 'papel', v_rec.papel, 'vigente', true,
          'versao_fato', v_rec.version, 'decidido_em', v_rec.decidido_em,
          'motivo_fato', v_rec.motivo),
        jsonb_build_object(
          'aprovacao_id', v_rec.id, 'papel', v_rec.papel, 'vigente', false,
          'versao_fato', v_versao_nova, 'revogado_em', v_instante,
          'revogado_motivo', p_motivo, 'invalidated', v_total),
        p_payload_hash,
        v_rec.id, p_actor_user_profile_id, p_membership_id, v_op_evento
      );
    end loop;
  end loop;

  return jsonb_build_object(
    'invalidated', v_n, 'aprovacao_id', v_primeira_id, 'papel', v_primeiro_papel,
    'versao_fato', v_primeira_versao, 'revogado_em', v_instante, 'motivo', p_motivo);
end;
$$;

comment on function public.f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid) is
  'F5-10 P3 (D19): nucleo reutilizavel da invalidacao de aprovacoes VIGENTES — '
  'preenche revogado_em/revogado_motivo, incrementa a version da PROPRIA linha do '
  'fato (nunca DELETE, nunca reescreve) e grava UM evento APROVACAO_INVALIDADA por '
  'papel na MESMA transacao, com autoria soberana e operation_id (derivado de '
  'forma deterministica a partir do segundo evento). Idempotente por construcao: '
  'fatos ja revogados nao sao tocados e a ausencia de fatos vigentes nao grava '
  'evento. Usado por meta_invalidar_aprovacoes e pela matriz D19 em meta_editar.';

-- ----------------------------------------------------------------------------
-- 5) `meta_invalidar_aprovacoes` — operacao soberana de invalidacao (D19)
-- ----------------------------------------------------------------------------
create or replace function public.meta_invalidar_aprovacoes(
  p_goal_id uuid,
  p_organization_id uuid,
  p_motivo text,
  p_expected_version integer,
  p_actor_user_profile_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org        uuid := p_organization_id;
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_meta       record;
  v_res        jsonb;
begin
  if p_goal_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: goal_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_motivo is null or p_motivo = '' or p_motivo <> btrim(p_motivo) then
    raise exception 'F5_10_INVALID_INPUT: motivo obrigatorio, nao vazio e sem espacos nas bordas';
  end if;
  if p_expected_version is null then
    raise exception 'F5_10_INVALID_INPUT: expected_version obrigatorio';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_invalidar_aprovacoes',
    'organization_id', v_org,
    'goal_id', p_goal_id,
    'motivo', p_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

  select e.goal_id, e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_goal_events e
   where e.organization_id = v_org and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'goal_id', v_evento.goal_id,
      'invalidated', (v_evento.after_value->>'invalidated')::integer,
      'aprovacao_id', v_evento.result_entity_id,
      'papel', v_evento.after_value->>'papel',
      'versao_fato', (v_evento.after_value->>'versao_fato')::integer,
      'revogado_em', v_evento.after_value->>'revogado_em',
      'motivo', v_evento.after_value->>'revogado_motivo');
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_10_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  perform public.ciclo_lock_organizacao(v_org);

  select e.goal_id, e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_goal_events e
   where e.organization_id = v_org and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'goal_id', v_evento.goal_id,
      'invalidated', (v_evento.after_value->>'invalidated')::integer,
      'aprovacao_id', v_evento.result_entity_id,
      'papel', v_evento.after_value->>'papel',
      'versao_fato', (v_evento.after_value->>'versao_fato')::integer,
      'revogado_em', v_evento.after_value->>'revogado_em',
      'motivo', v_evento.after_value->>'revogado_motivo');
  end if;

  select g.id, g.cycle_id, g.status, g.excluida, g.version
    into v_meta
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
  end if;

  -- Soft delete e TERMINAL e NAO invalida fatos historicos por si: a invalidacao
  -- explicita de uma meta excluida e recusada (fail-closed).
  if v_meta.excluida then
    raise exception 'F5_10_CONFLICT: meta excluida nao aceita invalidacao de aprovacoes';
  end if;

  if v_meta.version <> p_expected_version then
    raise exception 'F5_10_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- Nucleo reutilizavel: nenhuma aprovacao vigente => NO-OP auditavel (sem
  -- evento e sem consumo do operation_id), nunca re-mutacao de fato revogado.
  v_res := public.f5_10_invalidar_aprovacoes_vigentes(
    p_goal_id, v_org, p_actor_user_profile_id, v_membership, p_motivo, v_hash,
    p_operation_id);

  return jsonb_build_object(
    'goal_id', p_goal_id,
    'invalidated', (v_res->>'invalidated')::integer,
    'aprovacao_id', (v_res->>'aprovacao_id')::uuid,
    'papel', v_res->>'papel',
    'versao_fato', (v_res->>'versao_fato')::integer,
    'revogado_em', v_res->>'revogado_em',
    'motivo', p_motivo);
end;
$$;

comment on function public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid) is
  'F5-10 P3 (D19): invalidacao SOBERANA das aprovacoes VIGENTES de uma meta, '
  'preservando o historico (revogado_em/revogado_motivo na propria linha, nunca '
  'DELETE) e emitindo UM evento APROVACAO_INVALIDADA por papel na MESMA transacao. '
  'expected_version da META comparado apos o lock normativo e o SELECT FOR UPDATE; '
  'idempotente por (organization_id, operation_id); sem fatos vigentes a operacao '
  'e NO-OP auditavel (invalidated = 0, sem evento e sem re-mutacao de fato '
  'revogado). Nao exige ciclo ATIVO (desvio (c) do header): nao altera definicao '
  'nem estado funcional da meta. O gate funcional `goal.approve` e da fronteira '
  'confiavel final (P4/P5).';

-- ----------------------------------------------------------------------------
-- 6) Matriz D19 conectada a `meta_editar` (create or replace da RPC da P2)
-- ----------------------------------------------------------------------------
-- A migration HISTORICA da P2 NAO e editada: a RPC e substituida aqui, no mesmo
-- desenho (mesma assinatura, mesmo lock, mesma idempotencia, mesmo evento
-- EDITADA, mesmo rollback) com UM acrescimo NORMATIVO: alteracao MATERIAL da
-- definicao (`descricao`/`kpi`/`valor_alvo`) invalida ATOMICAMENTE as aprovacoes
-- VIGENTES, com um evento `APROVACAO_INVALIDADA` por papel, pela MESMA transacao.
-- `tipo` nao e editavel nesta fase (nao existe operacao contratada de troca de
-- tipo) e as demais mutacoes (progresso, finalizacao, revisao, quota, soft
-- delete) NAO invalidam — exatamente a matriz §9.4/D19.
create or replace function public.meta_editar(
  p_goal_id uuid,
  p_organization_id uuid,
  p_descricao text,
  p_kpi text,
  p_valor_alvo text,
  p_expected_version integer,
  p_actor_user_profile_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid := p_organization_id;
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_meta        record;
  v_ciclo       text;
  v_versao      integer;
  v_instante    timestamptz := now();
begin
  -- (a) Forma do payload.
  if p_goal_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: goal_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_10_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_descricao is null or p_descricao = '' or p_descricao <> btrim(p_descricao) then
    raise exception 'F5_10_INVALID_INPUT: descricao obrigatoria, nao vazia e sem espacos nas bordas';
  end if;
  if p_kpi is null or p_kpi = '' or p_kpi <> btrim(p_kpi) then
    raise exception 'F5_10_INVALID_INPUT: kpi obrigatorio, nao vazio e sem espacos nas bordas';
  end if;
  if p_valor_alvo is null or p_valor_alvo = '' or p_valor_alvo <> btrim(p_valor_alvo) then
    raise exception 'F5_10_INVALID_INPUT: valor_alvo obrigatorio, nao vazio e sem espacos nas bordas';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_editar',
    'organization_id', v_org,
    'goal_id', p_goal_id,
    'descricao', p_descricao,
    'kpi', p_kpi,
    'valor_alvo', p_valor_alvo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (b) Ator soberano do tenant.
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

  -- (c) Idempotencia — caminho rapido.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_goal_events e
   where e.organization_id = v_org and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'goal_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status');
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_10_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (d) Lock normativo da familia de ciclos (D10).
  perform public.ciclo_lock_organizacao(v_org);

  -- (e) Idempotencia sob o lock.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_goal_events e
   where e.organization_id = v_org and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'goal_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status');
  end if;

  -- (f) Meta do MESMO tenant (cross-tenant e NOT_FOUND) + lock da linha.
  select g.id, g.cycle_id, g.tipo, g.descricao, g.kpi, g.valor_alvo,
         g.status, g.excluida, g.version
    into v_meta
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
  end if;

  -- (g) Exclusao logica e terminal.
  if v_meta.excluida then
    raise exception 'F5_10_CONFLICT: meta excluida nao aceita edicao';
  end if;

  -- (h) Ciclo ATIVO (matriz do §10/D12: so ciclo ATIVO permite editar).
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = v_meta.cycle_id and c.organization_id = v_org;
  if v_ciclo is distinct from 'ATIVO' then
    raise exception 'F5_10_CONFLICT: edicao de meta exige ciclo ATIVO (status atual %)',
      coalesce(v_ciclo, 'AUSENTE');
  end if;

  -- (i) Lifecycle: edicao de definicao SOMENTE em EM_ANDAMENTO (§7).
  if v_meta.status <> 'EM_ANDAMENTO' then
    raise exception 'F5_10_CONFLICT: edicao exige meta EM_ANDAMENTO (status atual %)',
      v_meta.status;
  end if;

  -- (j) expected_version comparado APOS o lock e o SELECT FOR UPDATE (D12).
  if v_meta.version <> p_expected_version then
    raise exception 'F5_10_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  update public.evaluation_goals
     set descricao = p_descricao,
         kpi = p_kpi,
         valor_alvo = p_valor_alvo,
         version = version + 1
   where id = p_goal_id
     and organization_id = v_org
  returning version into v_versao;

  -- (k) D19: SOMENTE alteracao MATERIAL (descricao/kpi/valor_alvo) invalida as
  --     aprovacoes VIGENTES — atomicamente, na MESMA transacao, com evento
  --     APROVACAO_INVALIDADA por papel. Replay idempotente retorna antes daqui.
  if v_meta.descricao is distinct from p_descricao
     or v_meta.kpi is distinct from p_kpi
     or v_meta.valor_alvo is distinct from p_valor_alvo then
    perform public.f5_10_invalidar_aprovacoes_vigentes(
      p_goal_id, v_org, p_actor_user_profile_id, v_membership,
      'invalidada por alteracao material da definicao da meta (D19)',
      v_hash,
      public.f5_10_derivar_operation_id(p_operation_id, 'D19_INVALIDACAO'));
  end if;

  insert into public.evaluation_goal_events (
    organization_id, goal_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_goal_id, 'evaluation_goal', 'EDITADA', v_instante,
    'Edicao de definicao da meta',
    jsonb_build_object(
      'status', v_meta.status, 'version', v_meta.version,
      'tipo', v_meta.tipo, 'descricao', v_meta.descricao,
      'kpi', v_meta.kpi, 'valor_alvo', v_meta.valor_alvo),
    jsonb_build_object(
      'status', v_meta.status, 'version', v_versao,
      'tipo', v_meta.tipo, 'descricao', p_descricao,
      'kpi', p_kpi, 'valor_alvo', p_valor_alvo),
    v_hash, p_goal_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object('goal_id', p_goal_id, 'version', v_versao, 'status', v_meta.status);
end;
$$;

comment on function public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid) is
  'F5-10 P2 + P3 (§7/D12/D19): edita a DEFINICAO da meta (descricao/kpi/'
  'valor_alvo) em ciclo ATIVO e meta EM_ANDAMENTO, com expected_version comparado '
  'sob o lock normativo. `tipo` NAO e editavel nesta fase. Alteracao MATERIAL '
  'invalida ATOMICAMENTE as aprovacoes VIGENTES (evento APROVACAO_INVALIDADA por '
  'papel, pela mesma transacao); progresso/finalizacao/revisao/quota/soft delete '
  'NAO invalidam (matriz §9.4/D19). Idempotente por operation_id + hash canonico; '
  'evento EDITADA com before/after normalizados.';

-- ----------------------------------------------------------------------------
-- 7) ACL das RPCs e dos helpers (EXECUTE somente service_role)
-- ----------------------------------------------------------------------------
-- SECURITY INVOKER + search_path fixo; nenhuma superficie a public/anon/
-- authenticated (o cliente nunca chama RPC privilegiada direto — a fronteira
-- confiavel e a Edge, P5). `service_role` EXECUTA, nunca decide autorizacao.
revoke all on function public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.f5_10_aprovador_congelado(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid)
  from public, anon, authenticated;
revoke all on function public.f5_10_derivar_operation_id(uuid, text)
  from public, anon, authenticated;

grant execute on function public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.f5_10_aprovador_congelado(uuid, uuid, text)
  to service_role;
grant execute on function public.f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid)
  to service_role;
grant execute on function public.f5_10_derivar_operation_id(uuid, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- 8) Guarda final FAIL-CLOSED (§19 P3)
-- ----------------------------------------------------------------------------
do $$
declare
  v_falhas  text[] := array[]::text[];
  v_fns     text[] := array[
    'meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)',
    'meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'f5_10_aprovador_congelado(uuid, uuid, text)',
    'f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid)',
    'f5_10_derivar_operation_id(uuid, text)'];
  v_fn      text;
  v_rec     record;
  v_tab     text;
  v_n       integer;
  v_def     text;
  -- Nenhuma destas fontes VIVAS pode aparecer no SQL de decisao de aprovacao.
  v_proibidos text[] := array[
    'position_reporting_lines', 'occupations', 'organizacao_resolver_',
    'collegiate_', 'collaborator_identifiers'];
begin
  foreach v_fn in array v_fns loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config,
           lower(pg_get_functiondef(p.oid)) as def
      into v_rec
      from pg_proc p where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      v_falhas := v_falhas || ('ausente: ' || v_fn);
      continue;
    end if;
    if v_rec.prosecdef then
      v_falhas := v_falhas || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_falhas := v_falhas || ('sem search_path fixo: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_falhas := v_falhas || ('sem EXECUTE para service_role: ' || v_fn);
    end if;
    if has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE') then
      v_falhas := v_falhas || ('EXECUTE exposto a anon/authenticated: ' || v_fn);
    end if;
    -- Exclusao apenas LOGICA dos fatos: nenhuma funcao apaga ou trunca.
    if position('delete from' in v_rec.def) > 0
       or position('truncate' in v_rec.def) > 0 then
      v_falhas := v_falhas || ('funcao com DELETE/TRUNCATE: ' || v_fn);
    end if;
    -- NENHUMA hierarquia viva participa da decisao de aprovacao.
    foreach v_tab in array v_proibidos loop
      if position(v_tab in v_rec.def) > 0 then
        v_falhas := v_falhas || ('uso de estrutura VIVA (' || v_tab || ') em ' || v_fn);
      end if;
    end loop;
  end loop;

  -- A derivacao da legitimidade le SOMENTE a estrutura congelada.
  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.f5_10_aprovador_congelado(uuid, uuid, text)');
  if v_def is null or position('evaluation_participants' in v_def) = 0 then
    v_falhas := v_falhas || 'derivacao sem evaluation_participants (fonte congelada)';
  end if;

  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)');
  if v_def is null or position('f5_10_aprovador_congelado' in v_def) = 0 then
    v_falhas := v_falhas || 'meta_aprovar sem derivacao congelada de aprovador';
  end if;

  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)');
  if v_def is null or position('f5_10_invalidar_aprovacoes_vigentes' in v_def) = 0 then
    v_falhas := v_falhas || 'meta_editar sem a matriz D19 conectada';
  end if;
  if v_def is null or position('ciclo_lock_organizacao' in v_def) = 0 then
    v_falhas := v_falhas || 'meta_editar sem o lock normativo';
  end if;

  -- Fato unico vigente por (meta, papel) continua garantido pelo indice parcial.
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_goal_approvals'
       and indexname = 'uq_evaluation_goal_approvals_goal_papel_vigente'
  ) then
    v_falhas := v_falhas || 'indice unico parcial da aprovacao vigente ausente';
  end if;

  -- Deny-by-default, ausencia de DELETE fisico e trilha append-only intactos.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = v_tab
    ) then
      v_falhas := v_falhas || ('policy criada em ' || v_tab || ' (P4 nao antecipada)');
    end if;
    if has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_tab, 'SELECT') then
      v_falhas := v_falhas || ('leitura de cliente aberta em ' || v_tab);
    end if;
    if has_table_privilege('service_role', 'public.' || v_tab, 'DELETE')
       or has_table_privilege('service_role', 'public.' || v_tab, 'TRUNCATE') then
      v_falhas := v_falhas || ('service_role com DELETE/TRUNCATE em ' || v_tab);
    end if;
  end loop;

  -- Anti-escopo: nenhuma RPC funcional de meta alem das 9 do contrato P2+P3.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%')
     and p.proname <> all (array[
       'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
       'meta_revisar_finalizacao', 'meta_excluir', 'meta_definir_limites_do_ciclo',
       'meta_aprovar', 'meta_invalidar_aprovacoes']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s RPC(s) de meta fora do contrato P2+P3', v_n);
  end if;

  select count(*) into v_n
    from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception 'F5_10_P3_GUARD: superficie da P3 inconsistente: %',
      array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-10 P3: guarda final OK (2 RPCs + helpers INVOKER com lock normativo, EXECUTE so service_role, derivacao da estrutura CONGELADA, D19 conectada a meta_editar, zero DELETE e nenhuma politica nova)';
end $$;