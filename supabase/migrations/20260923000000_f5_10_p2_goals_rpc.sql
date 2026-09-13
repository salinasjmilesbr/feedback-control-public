-- ============================================================================
-- F5-10 P2 (Issue #212): RPCs SOBERANAS de METAS — criar, editar, progresso,
-- finalizar, revisar fechamento e exclusao logica.
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md (D1-D25; §7 lifecycle, §10 autorizacao,
-- §12 concorrencia/versao/idempotencia, §13 contrato RPC/Edge, §19 P2) e o
-- desenho fechado da P1 (`20260922000000_f5_10_p1_goals_schema.sql`).
-- Pre-requisito: P1 (as 4 tabelas, a trilha append-only e os invariantes de
-- quota). Padrao de RPC reusado da F5-09 P2 (`20260916000000_f5_09_cycle_rpc.sql`):
-- preflight + guarda final fail-closed, idempotencia por (organization_id,
-- operation_id) com hash canonico DERIVADO server-side, `expected_version`
-- comparado APOS o lock e o `select for update`, evento append-only na MESMA
-- transacao e EXECUTE restrito a `service_role`.
--
-- Entregue AQUI (e somente isto):
--   1) `meta_criar`                — CRIADA
--   2) `meta_editar`               — EDITADA (conteudo permitido)
--   3) `meta_atualizar_progresso`  — PROGRESSO_ATUALIZADO
--   4) `meta_finalizar`            — FINALIZADA (1a finalizacao explicita)
--   5) `meta_revisar_finalizacao`  — REVISAO_FINALIZACAO (fechamento anterior
--                                     integralmente recuperavel na trilha)
--   6) `meta_excluir`              — EXCLUIDA (soft delete; DELETE fisico segue
--                                     proibido por ACL e pela doutrina da P1)
--
-- Fora do escopo (fases seguintes), deliberadamente NAO implementado:
--   - P3: `meta_aprovar` / `meta_invalidar_aprovacoes` e a matriz §9.4. NENHUMA
--     aprovacao e criada, alterada, invalidada ou exigida por estas RPCs:
--     finalizar NAO exige aprovacao e status funcional NAO codifica aprovacao
--     (D3/D17). Nenhum evento `APROVACAO_*` e emitido aqui;
--   - P4: matriz funcional `goal.read`/`goal.write`/`goal.approve`, Policy
--     Engine, RLS own-tenant, grants ao cliente e a RPC de leitura com gate (§11);
--   - P5: Edge `metas`, contrato transportavel e adapter;
--   - P6: cutover, backfill, frontend e consumidores;
--   - P7: bateria integrada e concorrencia real entre duas sessoes;
--   - F5-11 (observacoes): intocado.
--
-- Invariantes preservadas (D1-D25):
--   - PostgreSQL e a autoridade: nenhum valor do corpo decide tenant, autoria,
--     status, version, fechamento, quota ou evento;
--   - identidade canonica = `evaluation_goals.id` (uuid do banco): NENHUMA RPC
--     recebe id de meta para criar — o id nasce no banco;
--   - `organization_id` e o tenant do ATOR verificado; a meta e resolvida SEMPRE
--     por `(id, organization_id)` — cross-tenant e NOT_FOUND (nunca "metade" da
--     operacao);
--   - `expected_version` obrigatorio em TODA mutacao, comparado depois do lock e
--     do `select for update`; divergencia => `F5_10_CONFLICT` (D12);
--   - `version = version + 1` em toda mutacao efetiva; a CRIACAO nasce com
--     `version = 0` (mesma convencao da F5-09 P2: uma operacao = um incremento);
--   - idempotencia por `unique (organization_id, operation_id)` da trilha +
--     `payload_hash` SHA-256 canonico derivado server-side (desvio (b));
--     replay identico devolve o MESMO resultado; intencao divergente => CONFLICT;
--   - lock: MESMA familia normativa dos ciclos, pela funcao canonica
--     `public.ciclo_lock_organizacao` (chave
--     `evaluation_cycles:<organization_id>`), adquirido no INICIO da mutacao —
--     NENHUMA familia/chave nova (D10);
--   - quota: continua autoridade do BANCO (triggers da P1). A RPC de criacao
--     apenas LE sob o lock para produzir mensagem estavel e serializar a decisao;
--     a mesma fonte (`evaluation_cycle_goal_limits`, ausencia = zero) e o trigger
--     da P1 e a ULTIMA barreira — nenhuma politica paralela;
--   - exclusao APENAS logica: nenhuma RPC emite DELETE/TRUNCATE (provado estaticamente
--     pela guarda final);
--   - operacoes ATOMICAS: meta + evento na MESMA transacao; falha em qualquer
--     parte => ROLLBACK TOTAL (nenhuma mutacao e nenhum evento parcial);
--   - lifecycle (§7 + matriz D12): `EM_ANDAMENTO` permite editar/progredir/
--     finalizar; `ATINGIDA`/`NAO_ATINGIDA` permitem apenas revisar/excluir;
--     excluida nao aceita mutacao; ciclo `ATIVO` e exigido para criar/editar/
--     progredir/finalizar (revisar/excluir sao historicas e NAO o exigem).
--
-- DESVIOS e BLOQUEIO DECLARADOS para auditoria:
--   (a) `meta_definir_limites_do_ciclo` (D21) NAO foi implementada nesta rodada.
--       D21 exige o evento append-only `LIMITES_DO_CICLO_ALTERADOS`, mas o
--       contrato §6.2 — implementado pela P1 — declara
--       `evaluation_goal_events.goal_id uuid NOT NULL` com FK COMPOSTA para
--       `evaluation_goals`. Um evento de CICLO nao possui meta associada: nao ha
--       valor NAO ARBITRARIO para `goal_id` (e um ciclo sem metas nao teria
--       nenhum), e escolher "uma meta qualquer" corromperia a semantica da
--       trilha. Tornar a coluna nullable ou criar trilha propria de limites
--       REABRE decisao fechada (D4/D11/§6.2), o que este trabalho nao faz sem
--       decisao do dono do contrato: o item fica registrado como BLOCKER
--       DOCUMENTAL para a auditoria da P2. A quota permanece invariante do banco
--       (triggers da P1) e as RPCs desta fase serializam pela familia normativa
--       de lock (D10) — nenhuma politica de quota nova, nenhum `DELETE` de quota.
--   (b) `p_payload_hash` NAO e parametro das RPCs: o hash e DERIVADO server-side
--       dos parametros ja validados (mesmo desvio declarado e ratificado na
--       F5-09 P2); aceita-lo do cliente permitiria replay com hash forjado.
--   (c) `meta_editar` NAO altera `tipo`: o legado (`atualizarMeta` compara
--       descricao/kpi/valorAlvo) nao possui operacao de troca de tipo e o
--       contrato nao a define nesta fase. A matriz §9.4 continua valendo para
--       qualquer operacao futura de troca de tipo; o trigger de quota da P1
--       segue cobrindo `update of tipo` caso ela venha a existir.
--   (d) As RPCs revalidam ATOR/TENANT/membership (autoria soberana) mas NAO
--       decidem a matriz funcional `goal.write`/SELF: essa decisao pertence ao
--       Policy Engine (P4) na fronteira confiavel, e a superficie tecnica e a
--       Edge (P5) com EXECUTE restrito a `service_role` — que EXECUTA, nunca
--       decide autorizacao em nome do ator.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
-- A P2 depende integralmente da P1 e das primitivas soberanas ja fechadas
-- (ator/tenant e lock de organizacao). Se o baseline nao for exatamente o
-- esperado, a migration ABORTA (nada e acomodado).
do $$
declare
  v_faltando text[] := array[]::text[];
  v_fn       text;
  v_tab      text;
  v_prims    text[] := array[
    'evaluation_ator_valido(uuid, uuid)',
    'ciclo_lock_organizacao(uuid)'];
begin
  -- P1: as 4 tabelas com RLS habilitada (a P2 nao abre superficie ao cliente).
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

  -- P1: idempotencia da trilha e append-only completo (3 triggers).
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

  -- P1: invariantes de quota (2 triggers) e protecao contra DELETE da quota.
  foreach v_fn in array array[
    'trg_evaluation_goals_quota', 'trg_evaluation_cycle_goal_limits_quota',
    'trg_evaluation_cycle_goal_limits_no_delete'] loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid in ('public.evaluation_goals'::regclass,
                         'public.evaluation_cycle_goal_limits'::regclass)
         and tgname = v_fn and not tgisinternal
    ) then
      v_faltando := v_faltando || ('trigger ' || v_fn);
    end if;
  end loop;

  -- P1: CHECK de fechamento COERENTE (nao apenas completo) - correcao pos-auditoria.
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_goals'::regclass
       and c.conname = 'ck_evaluation_goals_fechamento' and c.contype = 'c'
       and pg_get_constraintdef(c.oid) like '%ATINGIDA%'
       and pg_get_constraintdef(c.oid) like '%NAO_ATINGIDA%'
       and pg_get_constraintdef(c.oid) like '%btrim%'
  ) then
    v_faltando := v_faltando || 'ck_evaluation_goals_fechamento endurecido';
  end if;

  -- Primitivas reutilizadas: existem e sao executaveis pelo caminho server-side.
  foreach v_fn in array v_prims loop
    if to_regprocedure('public.' || v_fn) is null then
      v_faltando := v_faltando || ('funcao ' || v_fn);
    elsif has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_faltando := v_faltando || ('EXECUTE de service_role em ' || v_fn);
    end if;
  end loop;

  -- Fontes soberanas consumidas pela P2.
  foreach v_fn in array array[
    'public.evaluation_cycles', 'public.collaborators',
    'public.evaluation_cycle_goal_limits'] loop
    if to_regclass(v_fn) is null then
      v_faltando := v_faltando || ('tabela ' || v_fn);
    end if;
  end loop;

  if array_length(v_faltando, 1) is not null then
    raise exception
      'F5_10_P2_INCOMPATIBLE_BASELINE: baseline incompativel com o contrato da P2: %',
      array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-10 P2: preflight OK (P1 + primitivas de ator/tenant e lock de organizacao disponiveis)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) `meta_criar` — CRIADA (identidade UUID nasce no banco)
-- ----------------------------------------------------------------------------
-- Idempotente por `(organization_id, operation_id)` + hash canonico; exige ciclo
-- `ATIVO` da linha soberana, colaborador do MESMO tenant, quota disponivel
-- (invariante do banco) e unicidade parcial da meta viva. O evento CRIADA e
-- gravado na MESMA transacao.
create or replace function public.meta_criar(
  p_organization_id uuid,
  p_cycle_id uuid,
  p_collaborator_id uuid,
  p_tipo text,
  p_descricao text,
  p_kpi text,
  p_valor_alvo text,
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
  v_id         uuid;
  v_versao     integer;
  v_ciclo      record;
  v_limite     integer;
  v_vivas      integer;
  v_instante   timestamptz := now();
begin
  -- (1) Forma do payload — nada aqui e autoridade.
  if p_organization_id is null or p_cycle_id is null or p_collaborator_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: organization_id, cycle_id, collaborator_id, ator e operation_id obrigatorios';
  end if;
  if p_tipo is null or p_tipo not in ('NEGOCIO_PROJETO', 'INDIVIDUAL') then
    raise exception 'F5_10_INVALID_INPUT: tipo deve ser NEGOCIO_PROJETO ou INDIVIDUAL';
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

  -- (2) Hash canonico da INTENCAO (derivado server-side — desvio (b)).
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_criar',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'collaborator_id', p_collaborator_id,
    'tipo', p_tipo,
    'descricao', p_descricao,
    'kpi', p_kpi,
    'valor_alvo', p_valor_alvo
  )::text, 'UTF8')), 'hex');

  -- (3) Ator soberano (perfil ativo + membership ativa no tenant), na mesma
  --     transacao. A decisao funcional (goal.write/SELF) e do Policy Engine (P4):
  --     aqui se revalida apenas que o ator existe e pertence ao tenant (desvio (d)).
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

  -- (4) Idempotencia — caminho rapido (revalidado sob o lock em (7)).
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_goal_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'goal_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status');
  end if;

  -- (5) Membership do ator (autoria soberana da trilha — nunca vem do corpo).
  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_10_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (6) Serializacao pela familia NORMATIVA de lock dos ciclos (D10) — mesma
  --     chave, nenhuma familia nova.
  perform public.ciclo_lock_organizacao(v_org);

  -- (7) Idempotencia sob o lock: retry concorrente identico devolve o MESMO
  --     resultado em vez de colidir nas constraints.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_goal_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'goal_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'status', v_evento.after_value->>'status');
  end if;

  -- (8) Ciclo do MESMO tenant e ATIVO (lido da linha soberana).
  select c.id, c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org;
  if not found then
    raise exception 'F5_10_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;
  if v_ciclo.status <> 'ATIVO' then
    raise exception 'F5_10_CONFLICT: criacao de meta exige ciclo ATIVO (status atual %)',
      v_ciclo.status;
  end if;

  -- (9) Colaborador do MESMO tenant (a FK composta da P1 e a ultima barreira).
  if not exists (
    select 1 from public.collaborators c
     where c.id = p_collaborator_id and c.organization_id = v_org
  ) then
    raise exception 'F5_10_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  -- (10) QUOTA: leitura sob o lock (serializa a decisao). A regra e a MESMA do
  --      invariante da P1 (ausencia de linha = zero, fail-closed) e o trigger
  --      continua sendo a ULTIMA barreira — nenhuma politica paralela.
  select l.quantidade into v_limite
    from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_org
     and l.cycle_id = p_cycle_id
     and l.tipo = p_tipo;
  if v_limite is null then
    raise exception 'F5_10_CONFLICT: quota de metas % do ciclo nao configurada (quota zero; fail-closed)',
      p_tipo;
  end if;
  select count(*) into v_vivas
    from public.evaluation_goals g
   where g.organization_id = v_org
     and g.cycle_id = p_cycle_id
     and g.tipo = p_tipo
     and g.excluida = false;
  if v_vivas + 1 > v_limite then
    raise exception 'F5_10_CONFLICT: quota de metas % do ciclo excedida (limite %, vivas %)',
      p_tipo, v_limite, v_vivas;
  end if;

  -- (11) Unicidade parcial (meta viva por ciclo/dono/tipo) com mensagem estavel.
  if exists (
    select 1 from public.evaluation_goals g
     where g.organization_id = v_org
       and g.cycle_id = p_cycle_id
       and g.collaborator_id = p_collaborator_id
       and g.tipo = p_tipo
       and g.excluida = false
  ) then
    raise exception 'F5_10_CONFLICT: ja existe meta viva deste tipo para o colaborador no ciclo';
  end if;

  -- (12) Criacao: identidade UUID do banco, EM_ANDAMENTO, version 0.
  insert into public.evaluation_goals (
    organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo,
    status, version
  ) values (
    v_org, p_cycle_id, p_collaborator_id, p_tipo, p_descricao, p_kpi, p_valor_alvo,
    'EM_ANDAMENTO', 0
  )
  returning id, version into v_id, v_versao;

  -- (13) Trilha append-only na MESMA transacao (§12/D11).
  insert into public.evaluation_goal_events (
    organization_id, goal_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, v_id, 'evaluation_goal', 'CRIADA', v_instante,
    'Criacao de meta (EM_ANDAMENTO)',
    null,
    jsonb_build_object(
      'status', 'EM_ANDAMENTO', 'version', v_versao, 'tipo', p_tipo,
      'cycle_id', p_cycle_id, 'collaborator_id', p_collaborator_id),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object('goal_id', v_id, 'version', v_versao, 'status', 'EM_ANDAMENTO');
end;
$$;

comment on function public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid) is
  'F5-10 P2 (§7/D1/D11/D12/D20): cria meta do tenant do ator verificado em ciclo '
  'ATIVO, com identidade UUID gerada pelo banco, status EM_ANDAMENTO e version 0. '
  'Quota (invariante do banco) e unicidade parcial sao revalidadas sob o lock '
  'normativo da familia de ciclos; evento CRIADA na mesma transacao. Idempotente '
  'por (organization_id, operation_id) + hash canonico derivado server-side. '
  'Nunca aceita tenant, autoria, status, version, id ou quota do corpo.';

-- ----------------------------------------------------------------------------
-- 2) `meta_editar` — EDITADA (conteudo permitido: descricao/kpi/valor_alvo)
-- ----------------------------------------------------------------------------
-- Ordem UNICA de pre-condicoes aplicada por TODAS as RPCs de mutacao desta fase:
--   (a) forma do payload; (b) ator/tenant; (c) idempotencia; (d) lock normativo;
--   (e) idempotencia sob o lock; (f) existencia por (id, organization_id)
--   [cross-tenant = NOT_FOUND]; (g) exclusao logica; (h) estado do ciclo quando
--   exigido; (i) estado funcional da meta (lifecycle); (j) expected_version.
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
  'F5-10 P2 (§7/D12): edita a DEFINICAO da meta (descricao/kpi/valor_alvo) em '
  'ciclo ATIVO e meta EM_ANDAMENTO, com expected_version comparado sob o lock '
  'normativo. `tipo` NAO e editavel nesta fase (desvio (c) do header) e nenhuma '
  'aprovacao e tocada (P3). Evento EDITADA com before/after normalizados.';

-- ----------------------------------------------------------------------------
-- 3) `meta_atualizar_progresso` — PROGRESSO_ATUALIZADO
-- ----------------------------------------------------------------------------
-- Acompanhamento NAO e mutacao material do objeto aprovado (§9.4) e NAO exige
-- aprovacao. `progresso_percentual` e INTEIRO informado, 0..100 (D16) — nunca
-- derivado de `valor_alvo`/`resultado_atual` (texto).
create or replace function public.meta_atualizar_progresso(
  p_goal_id uuid,
  p_organization_id uuid,
  p_resultado_atual text,
  p_progresso_percentual integer,
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
  if p_goal_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: goal_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_10_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_progresso_percentual is not null
     and (p_progresso_percentual < 0 or p_progresso_percentual > 100) then
    raise exception 'F5_10_INVALID_INPUT: progresso_percentual deve estar entre 0 e 100';
  end if;
  if p_resultado_atual is not null
     and (p_resultado_atual = '' or p_resultado_atual <> btrim(p_resultado_atual)) then
    raise exception 'F5_10_INVALID_INPUT: resultado_atual nao pode ser vazio nem ter espacos nas bordas';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_atualizar_progresso',
    'organization_id', v_org,
    'goal_id', p_goal_id,
    'resultado_atual', p_resultado_atual,
    'progresso_percentual', p_progresso_percentual,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

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

  perform public.ciclo_lock_organizacao(v_org);

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

  select g.id, g.cycle_id, g.status, g.excluida, g.version,
         g.resultado_atual, g.progresso_percentual
    into v_meta
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
  end if;
  if v_meta.excluida then
    raise exception 'F5_10_CONFLICT: meta excluida nao aceita acompanhamento';
  end if;

  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = v_meta.cycle_id and c.organization_id = v_org;
  if v_ciclo is distinct from 'ATIVO' then
    raise exception 'F5_10_CONFLICT: acompanhamento de meta exige ciclo ATIVO (status atual %)',
      coalesce(v_ciclo, 'AUSENTE');
  end if;

  if v_meta.status <> 'EM_ANDAMENTO' then
    raise exception 'F5_10_CONFLICT: acompanhamento exige meta EM_ANDAMENTO (status atual %)',
      v_meta.status;
  end if;

  if v_meta.version <> p_expected_version then
    raise exception 'F5_10_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- `data_ultimo_acompanhamento` e SEMPRE o instante do servidor (nunca do corpo).
  update public.evaluation_goals
     set resultado_atual = p_resultado_atual,
         progresso_percentual = p_progresso_percentual,
         data_ultimo_acompanhamento = v_instante,
         version = version + 1
   where id = p_goal_id
     and organization_id = v_org
  returning version into v_versao;

  insert into public.evaluation_goal_events (
    organization_id, goal_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_goal_id, 'evaluation_goal', 'PROGRESSO_ATUALIZADO', v_instante,
    'Atualizacao de acompanhamento da meta',
    jsonb_build_object(
      'status', v_meta.status, 'version', v_meta.version,
      'resultado_atual', v_meta.resultado_atual,
      'progresso_percentual', v_meta.progresso_percentual),
    jsonb_build_object(
      'status', v_meta.status, 'version', v_versao,
      'resultado_atual', p_resultado_atual,
      'progresso_percentual', p_progresso_percentual,
      'data_ultimo_acompanhamento', v_instante),
    v_hash, p_goal_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object('goal_id', p_goal_id, 'version', v_versao, 'status', v_meta.status);
end;
$$;

comment on function public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid) is
  'F5-10 P2 (§7/D16): registra acompanhamento (resultado_atual e '
  'progresso_percentual inteiro 0..100) em meta EM_ANDAMENTO de ciclo ATIVO. Nao '
  'altera a definicao aprovada, nao exige aprovacao e grava '
  'data_ultimo_acompanhamento do SERVIDOR. Evento PROGRESSO_ATUALIZADO com '
  'before/after.';

-- ----------------------------------------------------------------------------
-- 4) `meta_finalizar` — FINALIZADA (1a finalizacao explicita)
-- ----------------------------------------------------------------------------
-- Finalizacao e INDEPENDENTE de aprovacao (D17): esta RPC NAO le, cria nem exige
-- aprovacao. Re-finalizacao silenciosa NAO existe: se a meta ja estiver fechada,
-- a operacao correta e `meta_revisar_finalizacao`.
create or replace function public.meta_finalizar(
  p_goal_id uuid,
  p_organization_id uuid,
  p_resultado_final text,
  p_atingida boolean,
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
  v_status      text;
  v_versao      integer;
  v_instante    timestamptz := now();
begin
  if p_goal_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: goal_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_10_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_atingida is null then
    raise exception 'F5_10_INVALID_INPUT: atingida e obrigatorio na finalizacao';
  end if;
  if p_resultado_final is null or p_resultado_final = ''
     or p_resultado_final <> btrim(p_resultado_final) then
    raise exception 'F5_10_INVALID_INPUT: resultado_final obrigatorio, nao vazio e sem espacos nas bordas';
  end if;

  v_status := case when p_atingida then 'ATINGIDA' else 'NAO_ATINGIDA' end;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_finalizar',
    'organization_id', v_org,
    'goal_id', p_goal_id,
    'resultado_final', p_resultado_final,
    'atingida', p_atingida,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

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

  perform public.ciclo_lock_organizacao(v_org);

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

  select g.id, g.cycle_id, g.status, g.excluida, g.version,
         g.resultado_final, g.atingida, g.data_fechamento
    into v_meta
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
  end if;
  if v_meta.excluida then
    raise exception 'F5_10_CONFLICT: meta excluida nao aceita finalizacao';
  end if;

  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = v_meta.cycle_id and c.organization_id = v_org;
  if v_ciclo is distinct from 'ATIVO' then
    raise exception 'F5_10_CONFLICT: finalizacao de meta exige ciclo ATIVO (status atual %)',
      coalesce(v_ciclo, 'AUSENTE');
  end if;

  if v_meta.status <> 'EM_ANDAMENTO' then
    raise exception 'F5_10_CONFLICT: meta ja finalizada (%) — use meta_revisar_finalizacao',
      v_meta.status;
  end if;

  if v_meta.version <> p_expected_version then
    raise exception 'F5_10_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  update public.evaluation_goals
     set status = v_status,
         resultado_final = p_resultado_final,
         atingida = p_atingida,
         data_fechamento = v_instante,
         version = version + 1
   where id = p_goal_id
     and organization_id = v_org
  returning version into v_versao;

  insert into public.evaluation_goal_events (
    organization_id, goal_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_goal_id, 'evaluation_goal', 'FINALIZADA', v_instante,
    'Finalizacao da meta',
    jsonb_build_object(
      'status', v_meta.status, 'version', v_meta.version,
      'resultado_final', v_meta.resultado_final, 'atingida', v_meta.atingida,
      'data_fechamento', v_meta.data_fechamento),
    jsonb_build_object(
      'status', v_status, 'version', v_versao,
      'resultado_final', p_resultado_final, 'atingida', p_atingida,
      'data_fechamento', v_instante),
    v_hash, p_goal_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object('goal_id', p_goal_id, 'version', v_versao, 'status', v_status);
end;
$$;

comment on function public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid) is
  'F5-10 P2 (§7/D17): primeira finalizacao explicita de meta EM_ANDAMENTO em '
  'ciclo ATIVO. `atingida` decide o status (ATINGIDA/NAO_ATINGIDA) e o CHECK de '
  'fechamento coerente da P1 e a ultima barreira. NAO exige, cria ou invalida '
  'aprovacao. Evento FINALIZADA com before/after; re-finalizacao exige '
  'meta_revisar_finalizacao (nunca sobrescrita silenciosa).';

-- ----------------------------------------------------------------------------
-- 5) `meta_revisar_finalizacao` — REVISAO_FINALIZACAO
-- ----------------------------------------------------------------------------
-- Operacao EXPLICITA (§7/D17): nao existe estado REABERTA e o fechamento anterior
-- permanece INTEGRALMENTE recuperavel na trilha (`before_value`). Nao exige ciclo
-- ATIVO (operacao historica de fechamento, fora da lista do §10/D12).
create or replace function public.meta_revisar_finalizacao(
  p_goal_id uuid,
  p_organization_id uuid,
  p_resultado_final text,
  p_atingida boolean,
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
  v_org         uuid := p_organization_id;
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_meta        record;
  v_status      text;
  v_versao      integer;
  v_instante    timestamptz := now();
begin
  if p_goal_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: goal_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_10_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_atingida is null then
    raise exception 'F5_10_INVALID_INPUT: atingida e obrigatorio na revisao de fechamento';
  end if;
  if p_resultado_final is null or p_resultado_final = ''
     or p_resultado_final <> btrim(p_resultado_final) then
    raise exception 'F5_10_INVALID_INPUT: resultado_final obrigatorio, nao vazio e sem espacos nas bordas';
  end if;
  if p_motivo is not null and (p_motivo = '' or p_motivo <> btrim(p_motivo)) then
    raise exception 'F5_10_INVALID_INPUT: motivo nao pode ser vazio nem ter espacos nas bordas';
  end if;

  v_status := case when p_atingida then 'ATINGIDA' else 'NAO_ATINGIDA' end;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_revisar_finalizacao',
    'organization_id', v_org,
    'goal_id', p_goal_id,
    'resultado_final', p_resultado_final,
    'atingida', p_atingida,
    'motivo', p_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

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

  perform public.ciclo_lock_organizacao(v_org);

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

  select g.id, g.cycle_id, g.status, g.excluida, g.version,
         g.resultado_final, g.atingida, g.data_fechamento
    into v_meta
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
  end if;
  if v_meta.excluida then
    raise exception 'F5_10_CONFLICT: meta excluida nao aceita revisao de fechamento';
  end if;

  -- Revisao SOMENTE de meta ja finalizada; a 1a finalizacao tem operacao propria.
  if v_meta.status not in ('ATINGIDA', 'NAO_ATINGIDA') then
    raise exception 'F5_10_CONFLICT: revisao exige meta finalizada (status atual %) — use meta_finalizar',
      v_meta.status;
  end if;

  if v_meta.version <> p_expected_version then
    raise exception 'F5_10_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  update public.evaluation_goals
     set status = v_status,
         resultado_final = p_resultado_final,
         atingida = p_atingida,
         data_fechamento = v_instante,
         version = version + 1
   where id = p_goal_id
     and organization_id = v_org
  returning version into v_versao;

  -- O fechamento ANTERIOR fica integralmente recuperavel na trilha (§7/D17).
  insert into public.evaluation_goal_events (
    organization_id, goal_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_goal_id, 'evaluation_goal', 'REVISAO_FINALIZACAO', v_instante,
    p_motivo,
    jsonb_build_object(
      'status', v_meta.status, 'version', v_meta.version,
      'resultado_final', v_meta.resultado_final, 'atingida', v_meta.atingida,
      'data_fechamento', v_meta.data_fechamento),
    jsonb_build_object(
      'status', v_status, 'version', v_versao,
      'resultado_final', p_resultado_final, 'atingida', p_atingida,
      'data_fechamento', v_instante),
    v_hash, p_goal_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object('goal_id', p_goal_id, 'version', v_versao, 'status', v_status);
end;
$$;

comment on function public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid) is
  'F5-10 P2 (§7/D17): revisa/re-finaliza explicitamente o FECHAMENTO de meta ja '
  'finalizada, com expected_version e operation_id proprios; o fechamento '
  'anterior e preservado em `before_value` (nunca sobrescrito silenciosamente). '
  'Nao exige ciclo ATIVO (operacao historica) e nao toca aprovacoes. Evento '
  'REVISAO_FINALIZACAO.';

-- ----------------------------------------------------------------------------
-- 6) `meta_excluir` — EXCLUIDA (soft delete; DELETE fisico segue proibido)
-- ----------------------------------------------------------------------------
-- Exclusao APENAS logica (D5): a linha permanece, `excluida`/`data_exclusao`
-- andam juntos (CHECK da P1) e a meta passa a nao aceitar mutacao. Aprovacoes
-- permanecem como fato historico (P3). Nao exige ciclo ATIVO.
create or replace function public.meta_excluir(
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
  v_org         uuid := p_organization_id;
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_meta        record;
  v_versao      integer;
  v_instante    timestamptz := now();
begin
  if p_goal_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: goal_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_10_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_motivo is null or p_motivo = '' or p_motivo <> btrim(p_motivo) then
    raise exception 'F5_10_INVALID_INPUT: motivo obrigatorio, nao vazio e sem espacos nas bordas';
  end if;

  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_excluir',
    'organization_id', v_org,
    'goal_id', p_goal_id,
    'motivo', p_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

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

  perform public.ciclo_lock_organizacao(v_org);

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

  select g.id, g.status, g.excluida, g.version
    into v_meta
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
  end if;
  if v_meta.excluida then
    raise exception 'F5_10_CONFLICT: meta ja excluida (exclusao logica e terminal)';
  end if;

  if v_meta.version <> p_expected_version then
    raise exception 'F5_10_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- Exclusao LOGICA: a linha permanece; os dois campos andam juntos (CHECK da P1).
  update public.evaluation_goals
     set excluida = true,
         data_exclusao = v_instante,
         version = version + 1
   where id = p_goal_id
     and organization_id = v_org
  returning version into v_versao;

  insert into public.evaluation_goal_events (
    organization_id, goal_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_goal_id, 'evaluation_goal', 'EXCLUIDA', v_instante,
    p_motivo,
    jsonb_build_object(
      'status', v_meta.status, 'version', v_meta.version,
      'excluida', false, 'data_exclusao', null),
    jsonb_build_object(
      'status', v_meta.status, 'version', v_versao,
      'excluida', true, 'data_exclusao', v_instante),
    v_hash, p_goal_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object('goal_id', p_goal_id, 'version', v_versao, 'status', v_meta.status);
end;
$$;

comment on function public.meta_excluir(uuid, uuid, text, integer, uuid, uuid) is
  'F5-10 P2 (§7/D5): exclusao LOGICA da meta (excluida=true + data_exclusao) com '
  'motivo obrigatorio, expected_version sob o lock normativo e evento EXCLUIDA. '
  'A linha NAO e apagada: DELETE/TRUNCATE continuam negados por ACL e pela '
  'doutrina da P1; meta excluida nao aceita novas mutacoes.';

-- ----------------------------------------------------------------------------
-- 7) ACL das RPCs (EXECUTE somente service_role)
-- ----------------------------------------------------------------------------
-- SECURITY INVOKER + search_path fixo; nenhuma superficie a public/anon/
-- authenticated (o cliente nunca chama RPC privilegiada direto — a fronteira
-- confiavel e a Edge, P5). `service_role` EXECUTA, nunca decide autorizacao.
revoke all on function public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)
  to service_role;
grant execute on function public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)
  to service_role;
grant execute on function public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)
  to service_role;
grant execute on function public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 8) Guarda final FAIL-CLOSED (§19 P2)
-- ----------------------------------------------------------------------------
-- A migration so termina se: as 6 RPCs existirem com a assinatura do contrato,
-- SECURITY INVOKER, search_path fixo, EXECUTE restrito a `service_role` e SEM
-- `DELETE`/`TRUNCATE` no corpo; TODAS usarem o lock normativo da familia de
-- ciclos (e nenhuma familia nova); e o deny-by-default/append-only/invariantes
-- da P1 continuarem intactos.
do $$
declare
  v_falhas  text[] := array[]::text[];
  v_fns     text[] := array[
    'meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'meta_excluir(uuid, uuid, text, integer, uuid, uuid)'];
  v_fn      text;
  v_rec     record;
  v_tab     text;
  v_n       integer;
begin
  foreach v_fn in array v_fns loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config,
           lower(pg_get_functiondef(p.oid)) as def
      into v_rec
      from pg_proc p
     where p.oid = to_regprocedure('public.' || v_fn);
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
    -- Serializacao: TODA mutacao usa a MESMA chave normativa dos ciclos (D10).
    if position('ciclo_lock_organizacao' in v_rec.def) = 0 then
      v_falhas := v_falhas || ('sem lock normativo: ' || v_fn);
    end if;
    if position('pg_advisory_xact_lock' in v_rec.def) > 0
       or position('position_reporting_lines:' in v_rec.def) > 0
       or position('f5_07_estrutura:' in v_rec.def) > 0 then
      v_falhas := v_falhas || ('lock fora da familia normativa: ' || v_fn);
    end if;
    -- Exclusao apenas logica: nenhuma RPC apaga ou trunca.
    if position('delete from' in v_rec.def) > 0
       or position('truncate' in v_rec.def) > 0 then
      v_falhas := v_falhas || ('RPC com DELETE/TRUNCATE: ' || v_fn);
    end if;
    -- P3 nao antecipada: nenhuma RPC cria/invalida aprovacao nesta fase.
    if position('insert into public.evaluation_goal_approvals' in v_rec.def) > 0
       or position('update public.evaluation_goal_approvals' in v_rec.def) > 0 then
      v_falhas := v_falhas || ('RPC tocando aprovacoes (P3): ' || v_fn);
    end if;
  end loop;

  -- Deny-by-default e append-only da P1 intactos (nenhuma policy nova).
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

  foreach v_fn in array array[
    'trg_evaluation_goal_events_append_only', 'trg_evaluation_goal_events_no_delete',
    'trg_evaluation_goal_events_no_truncate'] loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = 'public.evaluation_goal_events'::regclass
         and tgname = v_fn and not tgisinternal
    ) then
      v_falhas := v_falhas || ('trigger append-only ausente: ' || v_fn);
    end if;
  end loop;

  foreach v_fn in array array[
    'trg_evaluation_goals_quota', 'trg_evaluation_cycle_goal_limits_quota',
    'trg_evaluation_cycle_goal_limits_no_delete'] loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid in ('public.evaluation_goals'::regclass,
                         'public.evaluation_cycle_goal_limits'::regclass)
         and tgname = v_fn and not tgisinternal
    ) then
      v_falhas := v_falhas || ('invariante de quota ausente: ' || v_fn);
    end if;
  end loop;

  -- Anti-escopo: nenhuma RPC funcional de meta alem das 6 do contrato desta fase.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%')
     and p.proname <> all (array[
       'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
       'meta_revisar_finalizacao', 'meta_excluir']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s RPC(s) de meta fora do contrato da P2', v_n);
  end if;

  select count(*) into v_n
    from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception 'F5_10_P2_GUARD: superficie da P2 inconsistente: %',
      array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-10 P2: guarda final OK (6 RPCs INVOKER com lock normativo, EXECUTE so service_role, zero DELETE, deny-by-default e invariantes da P1 intactos)';
end $$;
