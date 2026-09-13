-- ============================================================================
-- F5-10 P4 — CORRECAO POS-AUDITORIA GPT (Issue #216): REVALIDACAO INTEGRAL DA
-- RELACAO CONGELADA EM TODOS OS CAMINHOS DE RETORNO DE `meta_aprovar`.
-- ----------------------------------------------------------------------------
-- Auditoria independente (SHA auditado c65df8551e29a4d7705a5aa26e0d4598acf75f5d):
-- CHANGES REQUIRED — 1 blocker funcional de autorizacao.
--
-- DEFEITO: o gate da P4 (`f5_10_exigir_autorizacao_meta('APROVAR', ...)`) prova
-- a CAPABILITY `goal.approve` ANTES da idempotencia, mas a RELACAO congelada do
-- papel era provada somente DEPOIS: (12) `f5_10_aprovador_congelado` e (13)
-- vinculo soberano unico + comparacao ator==aprovador. Com isso, os DOIS
-- retornos de replay (`operation_id` ja consumido — caminho rapido, antes do
-- lock, e caminho sob o lock) devolviam sucesso provando apenas a capability,
-- sem reprovar a relacao exigida pelo contrato (capability + relacao = ALLOW).
--
-- CORRECAO (minima e sem novo motor de autorizacao): a MESMA regra das etapas
-- (12)/(13) — que ja era a fonte unica em SQL, `f5_10_aprovador_congelado` +
-- `resolver_collaborador_vinculado` — passa a viver em UM unico ponto,
-- `f5_10_exigir_relacao_aprovador`, chamado nos TRES caminhos de retorno:
--   (i)  replay rapido (antes do lock);
--   (ii) replay sob o lock;
--   (iii) execucao normal (no lugar das etapas (12)/(13) originais).
-- As mensagens, a ordem e os sqlstates sao IDENTICOS aos da P3, de modo que
-- nenhuma expectativa funcional existente muda (D19/P3 preservados).
--
-- NAO altera: idempotencia (mesmo `operation_id` continua devolvendo o MESMO
-- resultado, sem novo fato/evento), estrutura congelada, D19, `cycle.manage` em
-- `meta_definir_limites_do_ciclo`, capabilities (nenhuma nova), familia de
-- advisory lock, migrations historicas (a migration da P4 NAO e editada) nem a
-- fronteira de `goal.approve` (que continua NAO implicando `goal.write`).
-- Fail-closed em qualquer ausencia/inconsistencia.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed)
-- ----------------------------------------------------------------------------
do $$
declare
  v_fn       text;
  v_faltando text[] := array[]::text[];
begin
  foreach v_fn in array array[
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid)',
    'public.f5_10_aprovador_congelado(uuid, uuid, text)',
    'public.resolver_collaborador_vinculado(uuid, uuid)',
    'public.evaluation_ator_valido(uuid, uuid)',
    'public.ciclo_lock_organizacao(uuid)'] loop
    if to_regprocedure(v_fn) is null then
      v_faltando := v_faltando || ('funcao ausente: ' || v_fn);
    end if;
  end loop;

  -- A migration da P4 (auditada) precisa continuar sendo a que define o gate.
  if not exists (
    select 1 from pg_proc p
     where p.oid = to_regprocedure('public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)')
       and position('f5_10_exigir_autorizacao_meta' in pg_get_functiondef(p.oid)) > 0
  ) then
    v_faltando := v_faltando || 'meta_aprovar sem o gate funcional da P4 (migration auditada)';
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception 'F5_10_P4B_PREFLIGHT: baseline inconsistente: %',
      array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-10 P4 (correcao pos-auditoria): preflight OK (meta_aprovar do artefato auditado presente com o gate da P4, resolvers canonicos disponiveis)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) `f5_10_exigir_relacao_aprovador` — FONTE UNICA da relacao congelada
-- ----------------------------------------------------------------------------
-- Reproduz LITERALMENTE as etapas (12) e (13) de `meta_aprovar` da P3 (mesma
-- ordem, mesmas mensagens, mesmos sqlstates), agora em um ponto unico chamado
-- em todos os caminhos de retorno. Nao cria autoridade nova: le a estrutura
-- CONGELADA (`evaluations`/`evaluation_participants` via
-- `f5_10_aprovador_congelado`) e o vinculo soberano do ator
-- (`resolver_collaborador_vinculado`, F5-02). Nunca usa hierarquia viva,
-- matricula, nome, cargo textual, `localWorld` ou estado declarado pelo cliente.
create or replace function public.f5_10_exigir_relacao_aprovador(
  p_goal_id uuid,
  p_organization_id uuid,
  p_papel text,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_dono       uuid;
  v_aprovador  uuid;
  v_qtd        integer;
  v_ator_colab uuid;
begin
  -- (1) Alvo resolvido pelo tenant do ATOR (mesma mensagem das RPCs).
  select g.collaborator_id into v_dono
    from public.evaluation_goals g
   where g.id = p_goal_id
     and g.organization_id = p_organization_id;
  if not found then
    raise exception 'F5_10_NOT_FOUND: meta inexistente ou de outro tenant';
  end if;

  -- (2) Papel na estrutura CONGELADA (D14/D15/§9.1) — fail-closed quando a
  --     estrutura nao reconhece o papel.
  v_aprovador := public.f5_10_aprovador_congelado(
                   p_goal_id, p_organization_id, p_papel);
  if v_aprovador is null then
    raise exception
      'F5_10_CONFLICT: papel % nao reconhecido na estrutura CONGELADA da avaliacao do dono da meta (fail-closed)',
      p_papel;
  end if;

  -- (3) Vinculo soberano UNICO do ator (perfil ativo + membership ativa +
  --     link ativo): ausencia ou ambiguidade => fail-closed.
  select count(*) into v_qtd
    from public.resolver_collaborador_vinculado(
           p_actor_user_profile_id, p_organization_id) c;
  if v_qtd <> 1 then
    raise exception
      'F5_10_FORBIDDEN: ator sem vinculo UNICO de colaborador ativo na organizacao (fail-closed)';
  end if;

  select c.collaborator_id into v_ator_colab
    from public.resolver_collaborador_vinculado(
           p_actor_user_profile_id, p_organization_id) c;

  -- (4) O ator TEM de ser o colaborador CONGELADO daquele papel.
  if v_ator_colab <> v_aprovador then
    raise exception
      'F5_10_FORBIDDEN: ator nao e o participante congelado do papel % (autoridade vem do snapshot do ciclo)',
      p_papel;
  end if;
end;
$$;

comment on function public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid) is
  'F5-10 P4 (correcao pos-auditoria, Issue #216): FONTE UNICA da RELACAO '
  'congelada de aprovacao, extraida das etapas (12)/(13) da P3 e chamada em '
  'TODOS os caminhos de retorno de `meta_aprovar` (replay rapido, replay sob o '
  'lock e execucao normal). Ordem e mensagens IDENTICAS as da P3: alvo por '
  '(id, tenant) => NOT_FOUND; papel nao reconhecido na estrutura CONGELADA => '
  'CONFLICT; vinculo soberano unico ausente => FORBIDDEN; ator diferente do '
  'participante congelado => FORBIDDEN. A autoridade vem EXCLUSIVAMENTE do '
  'snapshot da avaliacao original (`evaluation_participants`), nunca da '
  'hierarquia viva. SECURITY INVOKER, STABLE, search_path=public; EXECUTE '
  'somente service_role.';

revoke all on function public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 2) `meta_aprovar` RECONECTADA (create or replace): relacao congelada em
--    TODOS os caminhos de retorno (2 replays + execucao normal).
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
    -- P4 (correcao pos-auditoria #216): a RELACAO CONGELADA do papel e
    -- revalidada ANTES de QUALQUER retorno de replay (capability ja provada
    -- pelo gate da P4, acima): replay NAO e caminho de excecao.
    perform public.f5_10_exigir_relacao_aprovador(
      p_goal_id, v_org, p_papel, p_actor_user_profile_id);
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
    -- P4 (correcao pos-auditoria #216): a RELACAO CONGELADA do papel e
    -- revalidada ANTES de QUALQUER retorno de replay (capability ja provada
    -- pelo gate da P4, acima): replay NAO e caminho de excecao.
    perform public.f5_10_exigir_relacao_aprovador(
      p_goal_id, v_org, p_papel, p_actor_user_profile_id);
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

  -- (12)+(13) P4 (correcao pos-auditoria #216): LEGITIMIDADE ESTRUTURAL
  -- CONGELADA em PONTO UNICO (mesma ordem/mensagens da P3): resolve o papel
  -- na estrutura CONGELADA (fail-closed) e exige que o ator seja o
  -- colaborador congelado daquele papel, por vinculo soberano UNICO.
  perform public.f5_10_exigir_relacao_aprovador(
    p_goal_id, v_org, p_papel, p_actor_user_profile_id);

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
  'F5-10 P4 (correcao pos-auditoria, Issue #216): registra a APROVACAO como FATO '
  'auditavel + evento append-only. A autorizacao funcional exige a capability '
  'goal.approve (gate da P4, antes da idempotencia) E a RELACAO CONGELADA do '
  'papel — revalidada por 5_10_exigir_relacao_aprovador em TODOS os caminhos '
  'de retorno, INCLUSIVE no replay rapido e no replay sob o lock (correcao do '
  'blocker de enforcement apontado pela auditoria GPT). A legitimidade continua '
  'vindo EXCLUSIVAMENTE dos participantes congelados da avaliacao original do dono '
  '(GERENTE=GESTAO_CADEIA, COORDENADOR=GESTAO_DIRETA original e distinta), nunca '
  'da hierarquia viva. expected_version da META comparado apos o lock e o SELECT '
  'FOR UPDATE. NAO altera status/version da meta e NAO implica goal.write. '
  'Idempotencia preservada: replay legitimo devolve o MESMO resultado sem novo '
  'fato/evento. EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 3) ACL reafirmada + guarda final FAIL-CLOSED da correcao
-- ----------------------------------------------------------------------------
revoke all on function public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)
  to service_role;

do $$
declare
  v_def        text;
  v_aux        text;
  v_fn         text;
  v_n          integer;
  v_falhas     text[] := array[]::text[];
  v_habilitadas text[] := array[
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid)'];
begin
  -- (a) A correcao existe, e INVOKER com search_path fixo e EXECUTE so service_role.
  foreach v_fn in array v_habilitadas loop
    if to_regprocedure(v_fn) is null then
      v_falhas := v_falhas || ('funcao ausente: ' || v_fn);
      continue;
    end if;
    select lower(pg_get_functiondef(p.oid)) into v_aux
      from pg_proc p where p.oid = to_regprocedure(v_fn);
    if (select p.prosecdef from pg_proc p where p.oid = to_regprocedure(v_fn)) then
      v_falhas := v_falhas || ('SECURITY DEFINER inesperado: ' || v_fn);
    end if;
    if (select position('search_path=public' in coalesce(array_to_string(p.proconfig, ','), ''))
          from pg_proc p where p.oid = to_regprocedure(v_fn)) = 0 then
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
  if array_length(v_falhas, 1) is not null then
    raise exception 'F5_10_P4B_GUARD: superficie da correcao inconsistente: %',
      array_to_string(v_falhas, '; ');
  end if;

  -- (b) `meta_aprovar`: a relacao e exigida nos TRES caminhos (2 replays + normal),
  --     a capability continua no gate e o lock normativo segue no corpo.
  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)');

  select (length(v_def) - length(replace(v_def, 'f5_10_exigir_relacao_aprovador', '')))
         / length('f5_10_exigir_relacao_aprovador')
    into v_n;
  if v_n <> 3 then
    v_falhas := v_falhas || format('meta_aprovar chama a relacao %s vez(es) (esperado 3: 2 replays + normal)', v_n);
  end if;
  if position('f5_10_exigir_autorizacao_meta' in v_def) = 0 then
    v_falhas := v_falhas || 'meta_aprovar sem o gate de capability da P4';
  end if;
  if position('ciclo_lock_organizacao' in v_def) = 0 then
    v_falhas := v_falhas || 'meta_aprovar sem o lock normativo da familia de ciclos';
  end if;
  -- Nenhuma fonte VIVA / identidade textual na decisao de aprovacao.
  foreach v_aux in array array['position_reporting_lines', 'occupations',
                               'organizacao_resolver_', 'collegiate_'] loop
    if position(v_aux in v_def) > 0 then
      v_falhas := v_falhas || ('estrutura VIVA (' || v_aux || ') no corpo de meta_aprovar');
    end if;
  end loop;

  -- (c) O helper le a estrutura CONGELADA e o vinculo soberano, e nada vivo.
  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid)');
  if position('f5_10_aprovador_congelado' in v_def) = 0
     or position('resolver_collaborador_vinculado' in v_def) = 0
     or position('evaluation_goals' in v_def) = 0 then
    v_falhas := v_falhas || 'helper sem a fonte CONGELADA/vinculo soberano canonico';
  end if;
  foreach v_aux in array array['position_reporting_lines', 'occupations',
                               'organizacao_resolver_', 'collegiate_', 'localstorage'] loop
    if position(v_aux in v_def) > 0 then
      v_falhas := v_falhas || ('estrutura VIVA/legado (' || v_aux || ') no helper');
    end if;
  end loop;
  if position('f5_10_not_found: meta inexistente ou de outro tenant' in v_def) = 0
     or position('nao reconhecido na estrutura congelada' in v_def) = 0
     or position('sem vinculo unico de colaborador ativo' in v_def) = 0
     or position('nao e o participante congelado do papel' in v_def) = 0 then
    v_falhas := v_falhas || 'mensagens fail-closed da P3 ausentes no helper';
  end if;

  -- (d) Anti-escopo: catalogo intacto, nenhum DEFINER novo, nenhuma capability nova.
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname <> all (array[
       'conceder_acesso_role', 'criar_perfil_membership',
       'resolver_capabilities_efetivas', 'revogar_acesso_role']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('SECURITY DEFINER novo em public = %s (esperado 0)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception 'F5_10_P4B_GUARD: correcao pos-auditoria inconsistente: %',
      array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-10 P4 (correcao pos-auditoria): guarda final OK (relacao congelada exigida nos 3 caminhos de retorno de meta_aprovar, capability no gate, lock normativo preservado, nenhuma fonte viva, catalogo e DEFINER intactos)';
end $$;
