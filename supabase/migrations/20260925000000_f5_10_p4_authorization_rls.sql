-- ============================================================================
-- F5-10 P4 (Issue #216): AUTORIZACAO de metas — recurso soberano `goal`,
-- Policy Engine (matriz capability x estado), gates funcionais nas RPCs,
-- RLS own-tenant (policy ANTES do grant) e leitura soberana por escopo.
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md §10 (autorizacao), §11 (RLS x Policy
-- Engine — D22), §7 (lifecycle), §9 (aprovacoes/legitimidade congelada), §13
-- (contrato Edge/RPC), §19 P4 e D6-D9/D12/D14/D21/D25.
--
-- Entregue AQUI (e somente isto):
--   1) `f5_10_ator_valido_meta` — revalidacao da capability EFETIVA do ator com
--      allowlist FECHADA das 3 capabilities de meta (`goal.read`, `goal.write`,
--      `goal.approve`), no MESMO molde de `ciclo_ator_valido` (F5-09 P1) e
--      reusando `resolver_capabilities_efetivas` (F4-01/F5-04) — nenhuma fonte
--      nova de identidade, nenhum motor paralelo;
--   2) `f5_10_vinculo_meta_do_ator` — vinculo soberano UNICO ator -> collaborator
--      (`resolver_collaborator_vinculado`, F5-02): 0 ou >1 vinculo => NULL
--      (fail-closed), pois SELF e a relacao de escrita (D9);
--   3) `f5_10_exigir_autorizacao_meta` — GATE FUNCIONAL unico das 10 RPCs:
--      capability (pelo mapa FECHADO operacao -> capability) + relacao
--      (SELF para `goal.write`; a relacao CONGELADA de `goal.approve` continua
--      resolvida por papel em `meta_aprovar`, P3 — sem segunda decisao
--      contraditoria, D19);
--   4) as 9 RPCs da P2/P3 RECONECTADAS por `create or replace` com o gate no
--      inicio (antes da idempotencia rapida: replay tambem passa pela
--      autorizacao funcional);
--   5) `meta_listar_por_escopo` — leitura com gate (§11/D22): RLS e barreira de
--      TENANT; a leitura de TERCEIROS exige `goal.read` + relacao congelada;
--   6) RLS own-tenant: policy de SELECT em `evaluation_goals` e
--      `evaluation_goal_approvals` criada ANTES do `grant select`;
--      `evaluation_goal_events` e `evaluation_cycle_goal_limits` permanecem
--      deny-by-default integral;
--   7) ACL/comment das funcoes novas + guarda final FAIL-CLOSED.
--
-- DECISOES desta fase (fechadas, registradas no relatorio da P4):
--   (a) NENHUMA capability nova: `goal.read/write/approve` ja existem desde a
--       F4-01 (catalogo fisico permanece com 31 codigos; `goal.%`+`observation.%`
--       continuam 8) — D6 preservado;
--   (b) NENHUM escopo novo no catalogo (`access_role_assignment_scopes`): para
--       alvo `goal` o Policy Engine interpreta os escopos EXISTENTES sobre a
--       materializacao CONGELADA (`DESCENDANTS` => GERENTE = GESTAO_CADEIA
--       original; `DIRECT_REPORTS` => COORDENADOR = GESTAO_DIRETA original e
--       distinta; `SELF` => dono da meta). A relacao SQL canonica e
--       `f5_10_aprovador_congelado` (P3) — nunca estrutura viva;
--   (c) O gate cobre CAPABILITY + RELACAO. O ESTADO (ciclo ATIVO, lifecycle da
--       meta, exclusao logica, `expected_version`) permanece nas pre-condicoes
--       de cada RPC: uma unica fonte por regra, nenhum gate contraditorio;
--   (d) `meta_definir_limites_do_ciclo` continua operacao ADMINISTRATIVA de
--       ciclo (`cycle.manage`, D21) — NAO convertida para `goal.write`;
--   (e) `meta_invalidar_aprovacoes` (operacao explicita) exige `goal.write` +
--       SELF: coerente com D19 (a invalidacao decorre de mutacao material do
--       DONO) e incapaz de virar bypass (nao amplia aprovacao, nao escreve
--       meta e nao cria fato vigente). A invalidacao INTERNA de `meta_editar`
--       (`f5_10_invalidar_aprovacoes_vigentes`) NAO recebe gate proprio.
--
-- Fora do escopo (P5+), deliberadamente NAO implementado: Edge `metas`,
-- contrato transportavel, adapter/cliente, cutover/backfill das telas (P6),
-- concorrencia real entre sessoes e matriz integrada (P7), qualquer objeto de
-- `observation.*` (F5-11) e qualquer alteracao nas constraints/indices/triggers
-- da P1 ou nas RPCs `ciclo_*` da F5-09.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
do $$
declare
  v_tab        text;
  v_fn         text;
  v_faltando   text[] := array[]::text[];
  v_n          integer;
begin
  -- (a) As 4 tabelas da P1 existem com RLS habilitada e SEM policy (a P4 e a
  --     fase que cria exatamente 2): a leitura de cliente nasce aqui.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      v_faltando := v_faltando || ('RLS nao habilitada em ' || v_tab);
    end if;
    if not exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = v_tab
    ) then
      v_faltando := v_faltando || ('tabela ausente: ' || v_tab);
    end if;
    if exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = v_tab
    ) then
      v_faltando := v_faltando || ('policy pre-existente em ' || v_tab || ' (estado inesperado antes da P4)');
    end if;
    if has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_tab, 'SELECT') then
      v_faltando := v_faltando || ('leitura de cliente ja aberta em ' || v_tab);
    end if;
  end loop;

  -- (b) Autoridade existente reusada (nenhuma fonte nova).
  foreach v_fn in array array[
    'public.evaluation_ator_valido(uuid, uuid)',
    'public.ciclo_ator_valido(uuid, uuid, text)',
    'public.resolver_capabilities_efetivas(uuid, uuid)',
    'public.resolver_collaborador_vinculado(uuid, uuid)',
    'public.user_has_active_membership(uuid)',
    'public.ciclo_lock_organizacao(uuid)',
    'public.f5_10_aprovador_congelado(uuid, uuid, text)',
    'public.f5_10_derivar_operation_id(uuid, text)'] loop
    if to_regprocedure(v_fn) is null then
      v_faltando := v_faltando || ('funcao ausente: ' || v_fn);
    end if;
  end loop;

  -- (c) As 9 RPCs da P2/P3 existem com as assinaturas do contrato.
  foreach v_fn in array array[
    'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)',
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)'] loop
    if to_regprocedure(v_fn) is null then
      v_faltando := v_faltando || ('RPC ausente: ' || v_fn);
    end if;
  end loop;

  -- (d) Catalogo: as 3 capabilities de meta existem e sao concediveis via role
  --     (D7: concessao EXPLICITA por role/atribuicao do catalogo vigente).
  select count(*) into v_n
    from public.capabilities
   where code in ('goal.read', 'goal.write', 'goal.approve')
     and status = 'active'
     and deprecated = false
     and grantable_via_role;
  if v_n <> 3 then
    v_faltando := v_faltando || format('capabilities de meta efetivas/concediveis = %s (esperado 3)', v_n);
  end if;

  -- (e) Catalogo intacto: nenhuma capability nova nesta fase.
  select count(*) into v_n
    from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_faltando := v_faltando || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception 'F5_10_P4_PREFLIGHT: baseline inconsistente: %',
      array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-10 P4: preflight OK (P1 com RLS e zero policy, autoridade F4/F5-06/F5-09 reusavel, 9 RPCs da P2/P3 presentes, catalogo intacto com 3 capabilities de meta concediveis)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) `f5_10_ator_valido_meta` — capability EFETIVA com allowlist FECHADA (§10)
-- ----------------------------------------------------------------------------
-- Mesmo molde normativo de `ciclo_ator_valido` (F5-09 P1 §8/D23): o gate nao
-- pergunta "qualquer capability do ator"; ele prova EXATAMENTE a capability de
-- meta exigida pela operacao. Codigo desconhecido, de outro dominio ou
-- deprecado => false (fail-closed), pois `resolver_capabilities_efetivas` ja
-- exclui deprecadas e `nao concediveis`.
create or replace function public.f5_10_ator_valido_meta(
  p_actor_user_profile_id uuid,
  p_organization_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    coalesce(p_capability, '') in ('goal.read', 'goal.write', 'goal.approve')
    and public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id)
    and exists (
      select 1
        from public.resolver_capabilities_efetivas(
               p_actor_user_profile_id, p_organization_id) c
       where c.capability_code = p_capability
    );
$$;

comment on function public.f5_10_ator_valido_meta(uuid, uuid, text) is
  'F5-10 P4 (§10/D6/D7): revalida ator soberano (perfil e membership ATIVOS no '
  'tenant), aplica a allowlist FECHADA das capabilities de meta '
  '(goal.read/goal.write/goal.approve) e confirma que a capability exigida e '
  'EFETIVA do ator via `resolver_capabilities_efetivas` (F4-01/F5-04). Nao e um '
  'segundo motor: e a mesma autoridade F4 revalidada na transacao (defesa em '
  'profundidade). Codigo fora da allowlist => false. EXECUTE somente service_role.';

revoke all on function public.f5_10_ator_valido_meta(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.f5_10_ator_valido_meta(uuid, uuid, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- 2) `f5_10_vinculo_meta_do_ator` — SELF = vinculo soberano UNICO (D9)
-- ----------------------------------------------------------------------------
-- SELF nao e "declarado": e o vinculo ATIVO e UNICO entre o perfil soberano do
-- ator, sua membership ATIVA e um collaborator (`resolver_collaborator_vinculado`,
-- F5-02). Zero vinculo ou ambiguidade (mais de um) => NULL => o gate nega
-- (fail-closed): nenhuma heuristica por matricula, nome, cargo ou corpo.
create or replace function public.f5_10_vinculo_meta_do_ator(
  p_actor_user_profile_id uuid,
  p_organization_id uuid
)
returns uuid
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_qtd    integer;
  v_colab  uuid;
begin
  if p_actor_user_profile_id is null or p_organization_id is null then
    return null;
  end if;

  select count(*) into v_qtd
    from public.resolver_collaborador_vinculado(
           p_actor_user_profile_id, p_organization_id) c;
  if v_qtd <> 1 then
    return null;
  end if;

  select c.collaborator_id into v_colab
    from public.resolver_collaborador_vinculado(
           p_actor_user_profile_id, p_organization_id) c;
  return v_colab;
end;
$$;

comment on function public.f5_10_vinculo_meta_do_ator(uuid, uuid) is
  'F5-10 P4 (§10/D9): resolve o vinculo SOBERANO e UNICO do ator com um '
  'collaborator do tenant (perfil ativo + membership ativa + link ativo, F5-02). '
  'Zero ou mais de um vinculo => NULL (fail-closed): e a definicao de SELF usada '
  'pelo gate de metas (nunca matricula/nome/cargo/corpo). EXECUTE somente service_role.';

revoke all on function public.f5_10_vinculo_meta_do_ator(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.f5_10_vinculo_meta_do_ator(uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 3) `f5_10_exigir_autorizacao_meta` — GATE FUNCIONAL UNICO (capability+relacao)
-- ----------------------------------------------------------------------------
-- Mapa FECHADO operacao -> capability: a capability NAO vem do chamador (nao ha
-- como pedir uma capability mais fraca para uma operacao mais forte).
--   CRIAR/EDITAR/PROGRESSO/FINALIZAR/REVISAR/EXCLUIR/INVALIDAR -> goal.write
--   LER                                                      -> goal.read
--   APROVAR                                                  -> goal.approve
--   LIMITES (configuracao do CICLO, D21)                     -> cycle.manage
--
-- Ordem normativa (fail-closed, sem oracle de tenant):
--   (1) alvo resolvido por (id, tenant): meta/collaborator de outro tenant =>
--       NOT_FOUND (mesma mensagem das RPCs) — nao revela existencia cross-tenant;
--   (2) CAPABILITY (F4): capability sem relacao => DENY;
--   (3) RELACAO: relacao sem capability => DENY (a capability ja foi exigida em
--       (2)); `goal.write` exige SELF (dono). `goal.approve` NAO duplica a
--       resolucao do papel congelado (P3 resolve GERENTE/COORDENADOR em
--       `meta_aprovar`, D19/D25); `goal.read` exige vinculo soberano unico (o
--       ESCOPO da leitura — SELF/aprovador congelado — e aplicado por
--       `meta_listar_por_escopo`); `cycle.manage` nao tem relacao (administrativo).
-- O ESTADO (ciclo ATIVO/lifecycle/exclusao/version) NAO e decidido aqui: cada
-- RPC mantem sua pre-condicao (fonte unica por regra; nenhum gate contraditorio).
create or replace function public.f5_10_exigir_autorizacao_meta(
  p_operacao text,
  p_actor_user_profile_id uuid,
  p_organization_id uuid,
  p_goal_id uuid,
  p_collaborator_alvo_id uuid
)
returns void
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_cap      text;
  v_dono     uuid;
  v_vinculo  uuid;
begin
  v_cap := case coalesce(p_operacao, '')
    when 'CRIAR'      then 'goal.write'
    when 'EDITAR'     then 'goal.write'
    when 'PROGRESSO'  then 'goal.write'
    when 'FINALIZAR'  then 'goal.write'
    when 'REVISAR'    then 'goal.write'
    when 'EXCLUIR'    then 'goal.write'
    when 'INVALIDAR'  then 'goal.write'
    when 'LER'        then 'goal.read'
    when 'APROVAR'    then 'goal.approve'
    when 'LIMITES'    then 'cycle.manage'
    else null
  end;

  if v_cap is null then
    raise exception
      'F5_10_FORBIDDEN: operacao de meta desconhecida (%) — fail-closed',
      coalesce(p_operacao, '<null>');
  end if;

  if p_actor_user_profile_id is null or p_organization_id is null then
    raise exception
      'F5_10_FORBIDDEN: ator e organizacao sao obrigatorios na autorizacao funcional de meta';
  end if;

  -- (1) Alvo soberano resolvido pelo tenant do ATOR (nunca do corpo).
  if p_goal_id is not null then
    select g.collaborator_id into v_dono
      from public.evaluation_goals g
     where g.id = p_goal_id
       and g.organization_id = p_organization_id;
    if not found then
      raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
    end if;
  elsif v_cap = 'goal.write' then
    if p_collaborator_alvo_id is null then
      raise exception
        'F5_10_FORBIDDEN: criacao de meta exige o colaborador alvo (SELF)';
    end if;
    if not exists (
      select 1 from public.collaborators c
       where c.id = p_collaborator_alvo_id
         and c.organization_id = p_organization_id
    ) then
      raise exception 'F5_10_NOT_FOUND: colaborador inexistente ou de outro tenant';
    end if;
    v_dono := p_collaborator_alvo_id;
  end if;

  -- (2) CAPABILITY efetiva (fonte unica F4/F5-04/F5-09).
  if v_cap = 'cycle.manage' then
    if not public.ciclo_ator_valido(
             p_actor_user_profile_id, p_organization_id, v_cap) then
      raise exception
        'F5_10_FORBIDDEN: operacao % exige a capability % (ausente ou nao efetiva)',
        p_operacao, v_cap;
    end if;
    return;
  end if;

  if not public.f5_10_ator_valido_meta(
           p_actor_user_profile_id, p_organization_id, v_cap) then
    raise exception
      'F5_10_FORBIDDEN: operacao % exige a capability % (ausente ou nao efetiva)',
      p_operacao, v_cap;
  end if;

  -- (3) RELACAO.
  if v_cap = 'goal.read' then
    if public.f5_10_vinculo_meta_do_ator(
         p_actor_user_profile_id, p_organization_id) is null then
      raise exception
        'F5_10_FORBIDDEN: leitura de metas exige vinculo UNICO de colaborador ativo (fail-closed)';
    end if;
    return;
  end if;

  if v_cap = 'goal.approve' then
    -- A relacao CONGELADA (GERENTE=GESTAO_CADEIA / COORDENADOR=GESTAO_DIRETA,
    -- ocorrencia original) e resolvida por PAPEL dentro de `meta_aprovar` (P3):
    -- duplicar aqui criaria um segundo gate contraditorio (D19).
    return;
  end if;

  -- goal.write => SELF: somente o DONO escreve (D9). Gestor/coordenador
  -- legitimado a ler/aprovar NAO ganha escrita sobre meta de terceiro.
  v_vinculo := public.f5_10_vinculo_meta_do_ator(
                 p_actor_user_profile_id, p_organization_id);
  if v_vinculo is null then
    raise exception
      'F5_10_FORBIDDEN: ator sem vinculo UNICO de colaborador ativo na organizacao (fail-closed)';
  end if;
  if v_dono is null or v_vinculo <> v_dono then
    raise exception
      'F5_10_FORBIDDEN: operacao % exige SELF (goal.write apenas sobre a propria meta)',
      p_operacao;
  end if;
end;
$$;

comment on function public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid) is
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): gate funcional UNICO das RPCs de meta. '
  'Deriva a capability de um mapa FECHADO operacao->capability (o chamador nao '
  'escolhe a capability), resolve o alvo por (id, tenant do ator) com NOT_FOUND '
  'para cross-tenant, exige a capability EFETIVA (F4) e a RELACAO: goal.write => '
  'SELF (dono); goal.approve => capability + a resolucao congelada por papel de '
  '`meta_aprovar` (P3, sem duplicacao); goal.read => vinculo soberano unico; '
  'LIMITES => cycle.manage (administrativo de ciclo, D21). Capacidade sem '
  'relacao => DENY; relacao sem capability => DENY. O ESTADO permanece nas '
  'pre-condicoes de cada RPC. EXECUTE somente service_role.';

revoke all on function public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 3.1) RPCs da P2/P3 RECONECTADAS com o gate funcional (create or replace)
-- ----------------------------------------------------------------------------
-- Cada RPC recebe, IMEDIATAMENTE apos a revalidacao do ator soberano (passo 3)
-- e ANTES da idempotencia rapida, uma unica chamada ao gate funcional
-- `f5_10_exigir_autorizacao_meta`: assim ate o replay de um `operation_id`
-- conhecido passa por capability + relacao (fail-closed). Nenhum corpo de
-- regra de negocio foi alterado: o ESTADO continua nas pre-condicoes de cada
-- RPC (fonte unica por regra, sem gate contraditorio — D19).

-- ----------------------------------------------------------------------------
-- meta_criar - operacao CRIAR (gate funcional P4)
-- ----------------------------------------------------------------------------
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
  --     transacao. A decisao funcional (capability efetiva + relacao) e revalidada no GATE da P4 logo abaixo:
  --     aqui se revalida que o ator existe e pertence ao tenant (o GATE da P4 abaixo exige capability + relacao).
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('CRIAR', p_actor_user_profile_id, v_org, null, p_collaborator_id);

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
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao CRIAR): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- meta_editar - operacao EDITAR (gate funcional P4)
-- ----------------------------------------------------------------------------
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

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('EDITAR', p_actor_user_profile_id, v_org, p_goal_id, null);

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
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao EDITAR): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- meta_atualizar_progresso - operacao PROGRESSO (gate funcional P4)
-- ----------------------------------------------------------------------------
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

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('PROGRESSO', p_actor_user_profile_id, v_org, p_goal_id, null);

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
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao PROGRESSO): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- meta_finalizar - operacao FINALIZAR (gate funcional P4)
-- ----------------------------------------------------------------------------
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

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('FINALIZAR', p_actor_user_profile_id, v_org, p_goal_id, null);

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
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao FINALIZAR): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- meta_revisar_finalizacao - operacao REVISAR (gate funcional P4)
-- ----------------------------------------------------------------------------
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

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('REVISAR', p_actor_user_profile_id, v_org, p_goal_id, null);

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
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao REVISAR): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- meta_excluir - operacao EXCLUIR (gate funcional P4)
-- ----------------------------------------------------------------------------
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

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('EXCLUIR', p_actor_user_profile_id, v_org, p_goal_id, null);

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
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao EXCLUIR): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- meta_definir_limites_do_ciclo - operacao LIMITES (gate funcional P4)
-- ----------------------------------------------------------------------------
create or replace function public.meta_definir_limites_do_ciclo(
  p_cycle_id uuid,
  p_organization_id uuid,
  p_tipo text,
  p_quantidade integer,
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
  v_ciclo       record;
  v_antes       jsonb;
  v_depois      jsonb;
  v_anterior    integer;
  v_vivas       integer;
  v_versao      integer;
  v_instante    timestamptz := now();
begin
  -- (1) Forma do payload — nada aqui e autoridade.
  if p_cycle_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception 'F5_10_INVALID_INPUT: cycle_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_tipo is null or p_tipo not in ('NEGOCIO_PROJETO', 'INDIVIDUAL') then
    raise exception 'F5_10_INVALID_INPUT: tipo deve ser NEGOCIO_PROJETO ou INDIVIDUAL';
  end if;
  if p_quantidade is null or p_quantidade < 0 or p_quantidade > 3 then
    raise exception 'F5_10_INVALID_INPUT: quantidade deve estar entre 0 e 3';
  end if;
  if p_motivo is null or p_motivo = '' or p_motivo <> btrim(p_motivo) then
    raise exception 'F5_10_INVALID_INPUT: motivo obrigatorio, nao vazio e sem espacos nas bordas';
  end if;
  if p_expected_version is null then
    raise exception 'F5_10_INVALID_INPUT: expected_version obrigatorio';
  end if;

  -- (2) Hash canonico da INTENCAO (derivado server-side — desvio (b)).
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'meta_definir_limites_do_ciclo',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'tipo', p_tipo,
    'quantidade', p_quantidade,
    'motivo', p_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (3) Ator soberano do tenant.
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao';
  end if;

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('LIMITES', p_actor_user_profile_id, v_org, null, null);

  -- (4) Idempotencia — caminho rapido (revalidado sob o lock em (7)).
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'tipo', v_evento.after_value->>'tipo',
      'quantidade', (v_evento.after_value->>'quantidade')::integer);
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

  -- (6) MESMA familia normativa de lock dos ciclos (D10) — nenhuma chave nova.
  perform public.ciclo_lock_organizacao(v_org);

  -- (7) Idempotencia sob o lock.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_10_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'cycle_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'tipo', v_evento.after_value->>'tipo',
      'quantidade', (v_evento.after_value->>'quantidade')::integer);
  end if;

  -- (8) Ciclo do MESMO tenant (cross-tenant = NOT_FOUND) e ATIVO + versao.
  select c.id, c.status, c.version into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_10_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;
  if v_ciclo.status <> 'ATIVO' then
    raise exception
      'F5_10_CONFLICT: alteracao de limites de metas exige ciclo ATIVO (status atual %)',
      v_ciclo.status;
  end if;
  if v_ciclo.version <> p_expected_version then
    raise exception 'F5_10_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- (9) Limites ANTERIORES (mapa completo do ciclo) — preservados em before_value.
  select coalesce(jsonb_object_agg(l.tipo, l.quantidade), '{}'::jsonb) into v_antes
    from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_org
     and l.cycle_id = p_cycle_id;
  select l.quantidade into v_anterior
    from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_org
     and l.cycle_id = p_cycle_id
     and l.tipo = p_tipo;

  -- (10) NUNCA abaixo das metas NAO EXCLUIDAS do tipo (D21). Mesma fonte do
  --      trigger da P1 (que segue sendo a ULTIMA barreira).
  select count(*) into v_vivas
    from public.evaluation_goals g
   where g.organization_id = v_org
     and g.cycle_id = p_cycle_id
     and g.tipo = p_tipo
     and g.excluida = false;
  if p_quantidade < v_vivas then
    raise exception
      'F5_10_CONFLICT: limite de % nao pode ser reduzido para % (existem % metas vivas)',
      p_tipo, p_quantidade, v_vivas;
  end if;

  -- (11) UPSERT soberano: definir o limite CRIA a linha quando ausente (ausencia
  --      na P1 = quota ZERO) e atualiza quando existe, avancando a `version` da
  --      propria linha (nenhum overwrite silencioso).
  insert into public.evaluation_cycle_goal_limits (
    organization_id, cycle_id, tipo, quantidade, version
  ) values (
    v_org, p_cycle_id, p_tipo, p_quantidade, 0
  )
  on conflict (cycle_id, tipo) do update
    set quantidade = excluded.quantidade,
        version = public.evaluation_cycle_goal_limits.version + 1;

  -- (12) Version do CICLO: +1 efetivo (D12).
  update public.evaluation_cycles
     set version = version + 1
   where id = p_cycle_id
     and organization_id = v_org
  returning version into v_versao;

  -- (13) Limites NOVOS (mapa completo) + nova version do ciclo.
  select coalesce(jsonb_object_agg(l.tipo, l.quantidade), '{}'::jsonb) into v_depois
    from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_org
     and l.cycle_id = p_cycle_id;

  -- (14) Trilha append-only DO CICLO na MESMA transacao (D21): before_value
  --      preserva os limites anteriores; after_value registra os novos limites e
  --      a nova version do ciclo; result_entity_id = cycle_id.
  insert into public.cycle_events (
    organization_id, cycle_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_cycle_id, 'evaluation_cycle', 'LIMITES_DO_CICLO_ALTERADOS', v_instante,
    p_motivo,
    jsonb_build_object(
      'limites', v_antes, 'version', v_ciclo.version,
      'tipo', p_tipo, 'quantidade', v_anterior),
    jsonb_build_object(
      'limites', v_depois, 'version', v_versao,
      'tipo', p_tipo, 'quantidade', p_quantidade),
    v_hash, p_cycle_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'cycle_id', p_cycle_id, 'version', v_versao,
    'tipo', p_tipo, 'quantidade', p_quantidade);
end;
$$;

comment on function public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid) is
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao LIMITES): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- meta_aprovar - operacao APROVAR (gate funcional P4)
-- ----------------------------------------------------------------------------
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

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('APROVAR', p_actor_user_profile_id, v_org, p_goal_id, null);

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
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao APROVAR): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- meta_invalidar_aprovacoes - operacao INVALIDAR (gate funcional P4)
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
  v_qtd        integer;
  v_instante   timestamptz := now();
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

  -- F5-10 P4 (§10/D6/D7/D9/D21): GATE FUNCIONAL — capability efetiva +
  -- relacao (goal.write => SELF; LIMITES => cycle.manage; APROVAR => a
  -- relacao congelada por papel fica em `meta_aprovar`). Nenhuma decisao
  -- de ESTADO e duplicada aqui (D19).
  perform public.f5_10_exigir_autorizacao_meta('INVALIDAR', p_actor_user_profile_id, v_org, p_goal_id, null);

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

  -- Nucleo reutilizavel: revoga APENAS fatos vigentes (fato ja revogado NUNCA e
  -- re-mutado). O nucleo NAO grava evento quando nao ha fato vigente: o registro da
  -- intencao NO-OP e responsabilidade DESTA RPC (abaixo).
  v_res := public.f5_10_invalidar_aprovacoes_vigentes(
    p_goal_id, v_org, p_actor_user_profile_id, v_membership, p_motivo, v_hash,
    p_operation_id);
  v_qtd := (v_res->>'invalidated')::integer;

  -- NO-OP PERSISTENTEMENTE IDEMPOTENTE (correcao pos-auditoria): sem fato vigente
  -- a INTENCAO e registrada na trilha com o MESMO `operation_id` e o MESMO
  -- `payload_hash` canonico. Sem esse registro, um replay temporal posterior
  -- (depois de surgir NOVA aprovacao vigente) invalidaria um fato que NAO existia
  -- na intencao original, violando "mesmo operation_id + mesmo payload => mesmo
  -- resultado sem nova mutacao". `result_entity_id` fica NULL porque nenhum fato
  -- foi revogado e NENHUMA linha de `evaluation_goal_approvals` e tocada; a
  -- autoria soberana e o motivo sao preservados e before/after deixam explicito
  -- que a busca por fato vigente retornou vazio (com versao/status da meta para
  -- reconstrucao).
  if v_qtd = 0 then
    insert into public.evaluation_goal_events (
      organization_id, goal_id, entity_type, event_type, effective_date, reason,
      before_value, after_value, payload_hash, result_entity_id,
      actor_user_profile_id, actor_membership_id, operation_id
    ) values (
      v_org, p_goal_id, 'evaluation_goal', 'APROVACAO_INVALIDADA', v_instante,
      p_motivo,
      jsonb_build_object(
        'invalidated', 0, 'fato_vigente_encontrado', false,
        'aprovacao_id', null, 'papel', null,
        'versao_meta', v_meta.version, 'status_meta', v_meta.status,
        'motivo', p_motivo),
      jsonb_build_object(
        'invalidated', 0, 'fato_vigente_encontrado', false,
        'aprovacao_id', null, 'papel', null,
        'versao_fato', null, 'revogado_em', null, 'revogado_motivo', p_motivo,
        'versao_meta', v_meta.version, 'status_meta', v_meta.status,
        'registro', 'NO_OP'),
      v_hash, null, p_actor_user_profile_id, v_membership, p_operation_id
    );
  end if;

  return jsonb_build_object(
    'goal_id', p_goal_id,
    'invalidated', v_qtd,
    'aprovacao_id', (v_res->>'aprovacao_id')::uuid,
    'papel', v_res->>'papel',
    'versao_fato', (v_res->>'versao_fato')::integer,
    'revogado_em', v_res->>'revogado_em',
    'motivo', p_motivo);
end;
$$;

comment on function public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid) is
  'F5-10 P4 (§10/D6/D7/D9/D19/D21): RPC da P2/P3 RECONECTADA com o gate '
  'funcional 5_10_exigir_autorizacao_meta (operacao INVALIDAR): capability efetiva do '
  'catalogo F4 (goal.write/goal.approve/goal.read ou cycle.manage para LIMITES) + '
  'relacao SELF (dono) — capacidade sem relacao => DENY; relacao sem capability '
  '=> DENY. O comportamento de negocio (pre-condicoes de estado, trilha '
  'append-only, idempotencia, lock normativo e D19) permanece o da migration '
  'de origem (20260923000000/20260924000000). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 4) `meta_listar_por_escopo` — leitura soberana com GATE FUNCIONAL (§11/D22)
-- ----------------------------------------------------------------------------
-- RLS responde "esta identidade tem membership ativa no tenant da linha?";
-- o Policy Engine responde "esta identidade pode LER ESTA meta?". `SELECT`
-- own-tenant NAO concede `goal.read` funcional: por isso a leitura de TERCEIROS
-- passa por esta RPC, que aplica `goal.read` + relacao ANTES de devolver linhas.
--   - SELF: as metas do proprio colaborador vinculado;
--   - relacao CONGELADA: metas em que o ator E o participante congelado
--     GERENTE (GESTAO_CADEIA original) ou COORDENADOR (GESTAO_DIRETA original e
--     distinta) da avaliacao do dono — mesma regra de `f5_10_aprovador_congelado`
--     (P3), nunca estrutura viva;
--   - nenhuma outra meta e devolvida; sem vinculo soberano unico => DENY.
-- A leitura NAO exige ciclo ATIVO (matriz §10: leitura inclusive historica e de
-- meta excluida) e NAO cria evento (leitura nao e fato da trilha).
create or replace function public.meta_listar_por_escopo(
  p_organization_id uuid,
  p_cycle_id uuid,
  p_actor_user_profile_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_org       uuid := p_organization_id;
  v_vinculo   uuid;
  v_ciclo     text;
  v_metas     jsonb;
  v_qtd       integer;
begin
  if p_organization_id is null or p_cycle_id is null
     or p_actor_user_profile_id is null then
    raise exception
      'F5_10_INVALID_INPUT: organization_id, cycle_id e actor sao obrigatorios';
  end if;

  -- (1) Gate funcional `goal.read` (capability efetiva + vinculo soberano unico).
  perform public.f5_10_exigir_autorizacao_meta(
    'LER', p_actor_user_profile_id, v_org, null, null);

  v_vinculo := public.f5_10_vinculo_meta_do_ator(
                 p_actor_user_profile_id, v_org);

  -- (2) Ciclo do MESMO tenant (a leitura e sempre escopada por ciclo).
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org;
  if not found then
    raise exception 'F5_10_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- (3) Linhas AUTORIZADAS: SELF (dono) ou relacao CONGELADA do papel.
  select coalesce(jsonb_agg(x.meta order by x.ordem), '[]'::jsonb), count(*)
    into v_metas, v_qtd
    from (
      select g.id as ordem,
             jsonb_build_object(
               'goal_id', g.id,
               'cycle_id', g.cycle_id,
               'collaborator_id', g.collaborator_id,
               'tipo', g.tipo,
               'descricao', g.descricao,
               'kpi', g.kpi,
               'valor_alvo', g.valor_alvo,
               'status', g.status,
               'progresso_percentual', g.progresso_percentual,
               'resultado_atual', g.resultado_atual,
               'resultado_final', g.resultado_final,
               'atingida', g.atingida,
               'excluida', g.excluida,
               'version', g.version,
               'relacao',
                 case
                   when g.collaborator_id = v_vinculo then 'SELF'
                   when public.f5_10_aprovador_congelado(g.id, v_org, 'GERENTE') = v_vinculo
                     then 'APROVADOR_GERENTE_CONGELADO'
                   else 'APROVADOR_COORDENADOR_CONGELADO'
                 end,
               'aprovacoes_vigentes', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'papel', a.papel,
                          'aprovacao_id', a.id,
                          'decidido_em', a.decidido_em,
                          'motivo', a.motivo) order by a.papel)
                   from public.evaluation_goal_approvals a
                  where a.organization_id = v_org
                    and a.goal_id = g.id
                    and a.revogado_em is null), '[]'::jsonb)
             ) as meta
        from public.evaluation_goals g
       where g.organization_id = v_org
         and g.cycle_id = p_cycle_id
         and (
           g.collaborator_id = v_vinculo
           or public.f5_10_aprovador_congelado(g.id, v_org, 'GERENTE') = v_vinculo
           or public.f5_10_aprovador_congelado(g.id, v_org, 'COORDENADOR') = v_vinculo
         )
    ) x;

  return jsonb_build_object(
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'ciclo_status', v_ciclo,
    'relacao_ator', case when v_qtd = 0 then 'SEM_META_AUTORIZADA' else 'ESCOPO_APLICADO' end,
    'quantidade', v_qtd,
    'metas', v_metas);
end;
$$;

comment on function public.meta_listar_por_escopo(uuid, uuid, uuid) is
  'F5-10 P4 (§11/D7/D8/D22): LEITURA soberana por escopo. Aplica o gate '
  'funcional `goal.read` (capability efetiva + vinculo soberano unico) e devolve '
  'SOMENTE as metas em que o ator e o DONO (SELF) ou o participante CONGELADO '
  'GERENTE/COORDENADOR da avaliacao do dono (f5_10_aprovador_congelado, P3; '
  'nunca estrutura viva). A RLS own-tenant continua como defesa em profundidade '
  'no caminho de leitura propria. Exige ciclo do MESMO tenant; NAO exige ciclo '
  'ATIVO (leitura historica) e NAO grava evento. EXECUTE somente service_role.';

revoke all on function public.meta_listar_por_escopo(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_listar_por_escopo(uuid, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 5) Catalogo: bundle MINIMO de metas (D7)
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- 5) BUNDLE MINIMO de metas (D7) — concessao EXPLICITA pelo catalogo vigente
-- ----------------------------------------------------------------------------
-- O bundle `admin` NAO recebe nenhuma capability de meta: `goal.*` nao e
-- autoridade administrativa, e a D7 exige concessao EXPLICITA. Como o catalogo
-- de roles e populado por migration (`is_system`, `organization_id` nulo) e a
-- atribuicao a membership acontece pelo caminho soberano ja existente
-- (`conceder_acesso_role` / fluxo administrativo, service_role), a P4 entrega o
-- MINIMO necessario para `goal.*` ser decidivel em producao:
--   - `metas_dono`:      goal.read + goal.write   (dono da meta — SELF);
--   - `metas_aprovador`: goal.read + goal.approve (aprovador CONGELADO).
-- Nenhuma capability nova (o catalogo permanece com 31 codigos) e nenhuma
-- capability de meta fora destas duas roles de sistema. Idempotente e aditivo:
-- reexecutar nao duplica role, vinculo nem capability.
do $$
declare
  v_cap_read     uuid;
  v_cap_write    uuid;
  v_cap_approve  uuid;
  v_role_dono    uuid;
  v_role_aprov   uuid;
  v_catalogo     integer;
begin
  select id into v_cap_read
    from public.capabilities
   where code = 'goal.read' and status = 'active'
     and deprecated = false and grantable_via_role = true;
  select id into v_cap_write
    from public.capabilities
   where code = 'goal.write' and status = 'active'
     and deprecated = false and grantable_via_role = true;
  select id into v_cap_approve
    from public.capabilities
   where code = 'goal.approve' and status = 'active'
     and deprecated = false and grantable_via_role = true;
  if v_cap_read is null or v_cap_write is null or v_cap_approve is null then
    raise exception
      'F5_10_P4_BUNDLE: capability de meta ausente/inativa/depreciada/nao concedivel por role';
  end if;

  select count(*) into v_catalogo from public.capabilities;

  -- Roles de SISTEMA (organization_id nulo). O UNIQUE
  -- `uq_access_roles_organization_name` nao colide com organization_id nulo,
  -- por isso a idempotencia e pelo NOME + escopo de sistema.
  select id into v_role_dono
    from public.access_roles
   where name = 'metas_dono' and is_system = true
     and organization_id is null and status = 'active';
  if v_role_dono is null then
    insert into public.access_roles (name, status, is_system, organization_id)
    values ('metas_dono', 'active', true, null)
    returning id into v_role_dono;
  end if;

  select id into v_role_aprov
    from public.access_roles
   where name = 'metas_aprovador' and is_system = true
     and organization_id is null and status = 'active';
  if v_role_aprov is null then
    insert into public.access_roles (name, status, is_system, organization_id)
    values ('metas_aprovador', 'active', true, null)
    returning id into v_role_aprov;
  end if;

  -- Vinculos ADITIVOS e idempotentes (a constraint UNIQUE do par impede duplicata).
  insert into public.access_role_capabilities (access_role_id, capability_id)
  select v_role_dono, x.cap
    from (values (v_cap_read), (v_cap_write)) as x(cap)
   where not exists (
     select 1 from public.access_role_capabilities m
      where m.access_role_id = v_role_dono and m.capability_id = x.cap);

  insert into public.access_role_capabilities (access_role_id, capability_id)
  select v_role_aprov, x.cap
    from (values (v_cap_read), (v_cap_approve)) as x(cap)
   where not exists (
     select 1 from public.access_role_capabilities m
      where m.access_role_id = v_role_aprov and m.capability_id = x.cap);

  -- Guarda fail-closed do bundle: conjuntos EXATOS, catalogo intacto e nenhuma
  -- capability de meta fora destas duas roles de sistema.
  if (select count(*) from public.capabilities) <> v_catalogo then
    raise exception 'F5_10_P4_BUNDLE: catalogo de capabilities mudou de tamanho durante a P4';
  end if;

  if (select count(*) from public.access_role_capabilities
       where access_role_id = v_role_dono) <> 2
     or not exists (
       select 1 from public.access_role_capabilities
        where access_role_id = v_role_dono and capability_id = v_cap_read)
     or not exists (
       select 1 from public.access_role_capabilities
        where access_role_id = v_role_dono and capability_id = v_cap_write)
     or exists (
       select 1 from public.access_role_capabilities
        where access_role_id = v_role_dono and capability_id = v_cap_approve) then
    raise exception
      'F5_10_P4_BUNDLE: role metas_dono deveria ter EXATAMENTE goal.read + goal.write';
  end if;

  if (select count(*) from public.access_role_capabilities
       where access_role_id = v_role_aprov) <> 2
     or not exists (
       select 1 from public.access_role_capabilities
        where access_role_id = v_role_aprov and capability_id = v_cap_read)
     or not exists (
       select 1 from public.access_role_capabilities
        where access_role_id = v_role_aprov and capability_id = v_cap_approve)
     or exists (
       select 1 from public.access_role_capabilities
        where access_role_id = v_role_aprov and capability_id = v_cap_write) then
    raise exception
      'F5_10_P4_BUNDLE: role metas_aprovador deveria ter EXATAMENTE goal.read + goal.approve';
  end if;

  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and c.code like 'goal.%'
       and r.id <> all (array[v_role_dono, v_role_aprov])
  ) then
    raise exception
      'F5_10_P4_BUNDLE: capability de meta concedida a OUTRA role de sistema';
  end if;

  raise notice 'F5-10 P4: bundle minimo de metas OK (metas_dono = goal.read+goal.write; metas_aprovador = goal.read+goal.approve; catalogo intacto; nenhuma capability de meta fora destas roles de sistema)';
end $$;

-- ----------------------------------------------------------------------------
-- 6) RLS own-tenant: policy ANTES do grant (padrao F4-08 §9 / F5-09 P5)
-- ----------------------------------------------------------------------------
-- RLS e barreira de ISOLAMENTO/VISIBILIDADE de tenant (D22) — NAO e capability:
-- o predicado e a membership ATIVA do ator autenticado na organizacao da PROPRIA
-- linha (`user_has_active_membership`, F4-08); nenhum filtro vem do cliente.
-- `evaluation_goal_events` (trilha append-only) e
-- `evaluation_cycle_goal_limits` (configuracao do ciclo) permanecem
-- deny-by-default INTEGRAL: nenhuma policy e nenhum privilegio de cliente.
alter table public.evaluation_goals enable row level security;
alter table public.evaluation_goal_approvals enable row level security;

do $$
begin
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_goals'
       and policyname = 'evaluation_goals_select_same_tenant'
  ) then
    raise notice 'F5-10 P4: policy evaluation_goals_select_same_tenant ja existia — nao recriada';
  else
    create policy evaluation_goals_select_same_tenant on public.evaluation_goals
      for select
      to authenticated
      using (public.user_has_active_membership(organization_id));
  end if;
end $$;

do $$
begin
  if exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'evaluation_goal_approvals'
       and policyname = 'evaluation_goal_approvals_select_same_tenant'
  ) then
    raise notice 'F5-10 P4: policy evaluation_goal_approvals_select_same_tenant ja existia — nao recriada';
  else
    create policy evaluation_goal_approvals_select_same_tenant on public.evaluation_goal_approvals
      for select
      to authenticated
      using (public.user_has_active_membership(organization_id));
  end if;
end $$;

-- Grants MINIMOS: SOMENTE SELECT (nenhum DML, nenhuma REFERENCES/TRIGGER).
revoke all on public.evaluation_goals from public, anon;
revoke all on public.evaluation_goal_approvals from public, anon;
revoke insert, update, delete, truncate, references, trigger
  on public.evaluation_goals from authenticated;
revoke insert, update, delete, truncate, references, trigger
  on public.evaluation_goal_approvals from authenticated;
grant select on public.evaluation_goals to authenticated;
grant select on public.evaluation_goal_approvals to authenticated;

-- `service_role` continua EXECUTOR TECNICO (nunca decide autorizacao) e mantem
-- exatamente os privilegios da P1: sem DELETE/TRUNCATE (D9/D5).
revoke all on public.evaluation_goals from service_role;
revoke all on public.evaluation_goal_approvals from service_role;
revoke all on public.evaluation_goal_events from service_role;
revoke all on public.evaluation_cycle_goal_limits from service_role;
grant select, insert, update on public.evaluation_goals to service_role;
grant select, insert, update on public.evaluation_goal_approvals to service_role;
grant select, insert on public.evaluation_goal_events to service_role;
grant select, insert, update on public.evaluation_cycle_goal_limits to service_role;

-- ----------------------------------------------------------------------------
-- 7) ACL das RPCs de meta (INVOKER; EXECUTE SOMENTE service_role) + guarda final
-- ----------------------------------------------------------------------------
-- `create or replace` preserva os grants ja aplicados na P2/P3, mas a ACL e
-- reafirmada explicitamente (auditoria: nenhuma superficie nova de mutacao para
-- `authenticated`/`anon`).
revoke all on function public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)
  to service_role;
revoke all on function public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)
  to service_role;
revoke all on function public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)
  to service_role;
revoke all on function public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)
  to service_role;
revoke all on function public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)
  to service_role;
revoke all on function public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)
  to service_role;
revoke all on function public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)
  to service_role;
revoke all on function public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)
  to service_role;
revoke all on function public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)
  to service_role;
revoke all on function public.meta_listar_por_escopo(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_listar_por_escopo(uuid, uuid, uuid)
  to service_role;
revoke all on function public.f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid)
  to service_role;

do $$
declare
  v_tab        text;
  v_fn         text;
  v_policy     record;
  v_rec        record;
  v_n          integer;
  v_falhas     text[] := array[]::text[];
  v_habilitadas text[] := array[
    'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)',
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_listar_por_escopo(uuid, uuid, uuid)',
    'public.f5_10_ator_valido_meta(uuid, uuid, text)',
    'public.f5_10_vinculo_meta_do_ator(uuid, uuid)',
    'public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid)'];
begin
  -- (a) Policy: exatamente 1 SELECT own-tenant por tabela legivel, com o helper
  --     de tenant do F4-08, sem WITH CHECK e sem escrita.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals'] loop
    select count(*) into v_n
      from pg_policies where schemaname = 'public' and tablename = v_tab;
    if v_n <> 1 then
      v_falhas := v_falhas || format('%s: %s policies (esperado 1 SELECT own-tenant)', v_tab, v_n);
    else
      select * into v_policy
        from pg_policies where schemaname = 'public' and tablename = v_tab;
      if v_policy.cmd <> 'SELECT' then
        v_falhas := v_falhas || format('%s: policy %s com cmd %s (esperado SELECT)', v_tab, v_policy.policyname, v_policy.cmd);
      end if;
      if not ('authenticated' = any (v_policy.roles)) then
        v_falhas := v_falhas || format('%s: policy sem a role authenticated', v_tab);
      end if;
      if position('user_has_active_membership(organization_id)'
                  in coalesce(v_policy.qual, '')) = 0 then
        v_falhas := v_falhas || format('%s: policy sem o predicado de membership ativa do tenant', v_tab);
      end if;
      if v_policy.with_check is not null then
        v_falhas := v_falhas || format('%s: policy de SELECT com WITH CHECK', v_tab);
      end if;
    end if;

    if not has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT') then
      v_falhas := v_falhas || format('%s: authenticated sem SELECT', v_tab);
    end if;
    foreach v_fn in array array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      if has_table_privilege('authenticated', 'public.' || v_tab, v_fn) then
        v_falhas := v_falhas || format('%s: authenticated com %s', v_tab, v_fn);
      end if;
      if has_table_privilege('anon', 'public.' || v_tab, v_fn) then
        v_falhas := v_falhas || format('%s: anon com %s', v_tab, v_fn);
      end if;
    end loop;
  end loop;

  -- (b) Trilha e limites: deny-by-default INTEGRAL (nenhuma policy, nenhum
  --     privilegio de cliente) e `service_role` sem DELETE/TRUNCATE.
  foreach v_tab in array array[
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = v_tab
    ) then
      v_falhas := v_falhas || format('%s: policy indevida (deny-by-default integral)', v_tab);
    end if;
    foreach v_fn in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] loop
      if has_table_privilege('authenticated', 'public.' || v_tab, v_fn)
         or has_table_privilege('anon', 'public.' || v_tab, v_fn) then
        v_falhas := v_falhas || format('%s: privilegio de cliente %s (deveria ser zero)', v_tab, v_fn);
      end if;
    end loop;
  end loop;

  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if has_table_privilege('service_role', 'public.' || v_tab, 'DELETE')
       or has_table_privilege('service_role', 'public.' || v_tab, 'TRUNCATE') then
      v_falhas := v_falhas || format('%s: service_role com DELETE/TRUNCATE', v_tab);
    end if;
  end loop;

  -- (c) Funcoes: presentes, INVOKER, search_path fixo, EXECUTE so service_role.
  foreach v_fn in array v_habilitadas loop
    if to_regprocedure(v_fn) is null then
      v_falhas := v_falhas || ('funcao ausente: ' || v_fn);
      continue;
    end if;
    select p.prosecdef, array_to_string(p.proconfig, ',') as cfg
      into v_rec
      from pg_proc p
     where p.oid = to_regprocedure(v_fn);
    if v_rec.prosecdef then
      v_falhas := v_falhas || ('SECURITY DEFINER inesperado: ' || v_fn);
    end if;
    if position('search_path=public' in coalesce(v_rec.cfg, '')) = 0 then
      v_falhas := v_falhas || ('search_path ausente: ' || v_fn);
    end if;
    if has_function_privilege('authenticated', v_fn, 'EXECUTE')
       or has_function_privilege('anon', v_fn, 'EXECUTE') then
      v_falhas := v_falhas || ('EXECUTE exposto a cliente: ' || v_fn);
    end if;
    if not has_function_privilege('service_role', v_fn, 'EXECUTE') then
      v_falhas := v_falhas || ('service_role sem EXECUTE: ' || v_fn);
    end if;
  end loop;

  -- (d) Anti-escopo: exatamente 10 RPCs de meta; catalogo de capabilities intacto
  --     (nenhuma capability nova) e as 3 de meta ativas/concediveis; nenhum
  --     SECURITY DEFINER novo (os 4 do F4-08 permanecem os unicos).
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%')
     and p.proname <> all (array[
       'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
       'meta_revisar_finalizacao', 'meta_excluir', 'meta_definir_limites_do_ciclo',
       'meta_aprovar', 'meta_invalidar_aprovacoes', 'meta_listar_por_escopo']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s RPC(s) de meta fora do contrato P4', v_n);
  end if;

  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  select count(*) into v_n from public.capabilities
   where code in ('goal.read', 'goal.write', 'goal.approve')
     and status = 'active' and grantable_via_role;
  if v_n <> 3 then
    v_falhas := v_falhas || format('capabilities de meta concediveis = %s (esperado 3)', v_n);
  end if;

  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname <> all (array[
       'conceder_acesso_role', 'criar_perfil_membership',
       'resolver_capabilities_efetivas', 'revogar_acesso_role']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('SECURITY DEFINER novo em public = %s (esperado 0; os 4 do F4-08 preservados)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception 'F5_10_P4_GUARD: superficie da P4 inconsistente: %',
      array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-10 P4: guarda final OK (2 policies own-tenant de metas, trilha/limites deny-by-default, escrita de cliente fechada, 10 RPCs + 3 helpers INVOKER com EXECUTE so service_role, catalogo intacto sem capability nova e sem novo SECURITY DEFINER)';
end $$;
