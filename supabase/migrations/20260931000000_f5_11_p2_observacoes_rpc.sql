-- ============================================================================
-- F5-11 P2 (Issue #244): RPCs soberanas `observacao_*`
-- ----------------------------------------------------------------------------
-- Contrato normativo: docs/F5-11-desenho-tecnico.md (D1-D16; §6.6, §7.5-§7.9,
-- §8, §12, §13 e §17.1). Modelo soberano da P1 e coerencia da P1.1 PRESERVADOS.
--
-- Esta migration NAO reabre D1-D16 e NAO antecipa P3:
--   - NENHUMA capability concedida (`observation.*` continua SEM concessao: D15
--     permanece BLOQUEANDO a P3) e nenhuma role/bundle/perfil criado/alterado;
--   - `admin` continua com 9 capabilities e SEM `observation.*`;
--   - NENHUMA policy criada e NENHUM privilegio de cliente: RLS/ACL da P1
--     continuam INTEGRAS (D9). `service_role` segue executor tecnico;
--   - NENHUM advisory lock (D10: `version` + row lock; a familia de lock de
--     ciclos NAO e usada aqui);
--   - NENHUMA UI/Edge/cliente/cutover/localStorage tocados (P4/P5 nao
--     antecipadas); NENHUMA migracao de dados legados (D13).
--
-- MODELO DE CONFIANCA (D3). `auth.uid()` e' a raiz soberana. No repositorio o
-- ator chega como parametro porque a fronteira confiavel (Edge) ja verificou o
-- JWT; aqui ele e' revalidado contra `auth.uid()`: quando existe JWT, o JWT e' a
-- autoridade e o parametro NAO pode divergir (fail-closed). Campos de autoria
-- NUNCA vem do corpo: `author_user_profile_id`, `author_membership_id` e
-- `author_collaborator_id` sao derivados server-side (D3/D4 e regra da P1.1,
-- com paridade INTEGRAL com `resolver_collaborador_vinculado`, F5-02).
--
-- ORDEM NORMATIVA de cada mutacao (§6.6): forma -> hash canonico -> ator ->
-- gate funcional -> membership -> idempotencia rapida -> LOCK DA LINHA ->
-- idempotencia sob o lock -> alvo por (id, tenant) -> `expected_version` ->
-- precondicoes de estado -> mutacao `version + 1` -> evento na MESMA transacao.
--
-- Superficie criada (14 funcoes `SECURITY INVOKER`, `search_path = public`,
-- `EXECUTE` somente `service_role`):
--   8 RPCs:  observacao_criar, observacao_editar, observacao_definir_comunicado,
--            observacao_excluir, observacao_revogar, observacao_obter,
--            observacao_listar_por_escopo, observacao_historico;
--   6 helpers internos: f5_11_ator_efetivo_observacao,
--            f5_11_ator_valido_observacao, f5_11_vinculo_observacao_do_ator,
--            f5_11_relacao_observacao_do_ator, f5_11_exigir_autorizacao_observacao,
--            f5_11_status_vigente_do_colaborador.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
do $$
declare
  v_faltando text[] := array[]::text[];
  v_fn       text;
  v_tab      text;
  v_n        integer;
begin
  -- (a) P1: as DUAS tabelas do contrato, com RLS ligada e ZERO policy.
  foreach v_tab in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if to_regclass('public.' || v_tab) is null then
      v_faltando := v_faltando || ('tabela ausente: ' || v_tab);
      continue;
    end if;
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      v_faltando := v_faltando || ('RLS desabilitada em ' || v_tab);
    end if;
    if exists (
      select 1 from pg_policies p
       where p.schemaname = 'public' and p.tablename = v_tab
    ) then
      v_faltando := v_faltando || ('policy indevida (D9 exige ZERO): ' || v_tab);
    end if;
  end loop;

  -- (b) P1: idempotencia da trilha, append-only e imutabilidade (D4/D6).
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_observation_events'::regclass
       and conname = 'uq_evaluation_observation_events_org_operation' and contype = 'u'
  ) then
    v_faltando := v_faltando || 'uq_evaluation_observation_events_org_operation';
  end if;
  foreach v_fn in array array[
    'trg_evaluation_observations_imutaveis',
    'trg_evaluation_observation_events_append_only',
    'trg_evaluation_observation_events_no_delete',
    'trg_evaluation_observation_events_no_truncate'] loop
    if not exists (
      select 1 from pg_trigger t
       where t.tgname = v_fn and not t.tgisinternal
    ) then
      v_faltando := v_faltando || ('trigger ' || v_fn);
    end if;
  end loop;

  -- (c) P1.1: coerencia perfil <-> membership <-> ator instalada (nao pode ser
  --     enfraquecida pela P2).
  foreach v_fn in array array[
    'f5_11_validar_coerencia_identidade',
    'f5_11_validar_coerencia_identidade_evento'] loop
    if to_regprocedure('public.' || v_fn || '()') is null then
      v_faltando := v_faltando || ('funcao da P1.1 ausente: ' || v_fn);
    end if;
  end loop;
  foreach v_fn in array array[
    'trg_evaluation_observations_coerencia_identidade',
    'trg_evaluation_observation_events_coerencia_identidade'] loop
    if not exists (
      select 1 from pg_trigger t where t.tgname = v_fn and not t.tgisinternal
    ) then
      v_faltando := v_faltando || ('trigger da P1.1 ausente: ' || v_fn);
    end if;
  end loop;

  -- (d) Primitivas soberanas reutilizadas (nenhuma nova e' criada aqui).
  foreach v_fn in array array[
    'evaluation_ator_valido(uuid, uuid)',
    'resolver_collaborador_vinculado(uuid, uuid)',
    'resolver_alvos_escopo(uuid, uuid, text, uuid, timestamptz)',
    'resolver_capabilities_efetivas(uuid, uuid)'] loop
    if to_regprocedure('public.' || v_fn) is null then
      v_faltando := v_faltando || ('funcao ' || v_fn);
    elsif has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_faltando := v_faltando || ('EXECUTE de service_role em ' || v_fn);
    end if;
  end loop;
  foreach v_tab in array array[
    'evaluation_cycles', 'collaborators', 'collaborator_status_periods',
    'user_profiles', 'user_organization_memberships', 'capabilities',
    'access_roles', 'access_role_capabilities',
    'membership_access_role_assignments'] loop
    if to_regclass('public.' || v_tab) is null then
      v_faltando := v_faltando || ('tabela ' || v_tab);
    end if;
  end loop;

  -- (e) D15 INTACTO (a P2 nao concede nada): catalogo 31, ZERO concessao de
  --     `observation.*`, bundle `admin` com 9 e SEM `observation.*` e o conjunto
  --     de roles de SISTEMA inalterado.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_faltando := v_faltando || format('catalogo com %s capabilities (esperado 31)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    v_faltando := v_faltando || format('%s concessao(oes) de observation.* (D15)', v_n);
  end if;
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    v_faltando := v_faltando || format('bundle admin com %s capabilities (esperado 9)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
     and c.code like 'observation.%';
  if v_n <> 0 then
    v_faltando := v_faltando || 'bundle admin com observation.*';
  end if;
  if (select array_agg(r.name order by r.name)
        from public.access_roles r where r.is_system = true)
     is distinct from array['admin', 'metas_aprovador', 'metas_dono'] then
    v_faltando := v_faltando || 'conjunto de roles de SISTEMA mudou';
  end if;

  -- (f) Baseline limpo: nenhuma RPC `observacao_*`/`observation_*` existe ainda.
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'observacao\_%' or p.proname like 'observation\_%');
  if v_n <> 0 then
    v_faltando := v_faltando || format('%s RPC(s) observacao_* ja existem (baseline sujo)', v_n);
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception
      'F5_11_P2_INCOMPATIBLE_BASELINE: baseline incompativel com o contrato da P2: %',
      array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-11 P2: preflight OK (P1 + P1.1 instaladas, primitivas soberanas disponiveis, catalogo 31, D15 intacto, baseline limpo)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) Helpers internos (SECURITY INVOKER; EXECUTE somente service_role)
-- ----------------------------------------------------------------------------

-- 1.1) Identidade da requisicao (D3): `auth.uid()` e' a raiz.
--      Quando existe JWT, ele e' autoridade e o ator informado pela fronteira
--      NAO pode divergir — tentativa de override ⇒ FORBIDDEN (fail-closed).
create or replace function public.f5_11_ator_efetivo_observacao(
  p_actor_user_profile_id uuid
)
returns uuid
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if p_actor_user_profile_id is null then
    raise exception
      'F5_11_INVALID_INPUT: ator obrigatorio (identidade soberana derivada de auth.uid())';
  end if;
  if v_uid is not null and v_uid is distinct from p_actor_user_profile_id then
    raise exception
      'F5_11_FORBIDDEN: identidade do solicitante (auth.uid()) diverge do ator informado — override de identidade negado';
  end if;
  return p_actor_user_profile_id;
end;
$$;

comment on function public.f5_11_ator_efetivo_observacao(uuid) is
  'F5-11 P2 (D3): amarra o ator informado pela fronteira a `auth.uid()`. Com JWT '
  'presente, o JWT e a autoridade e a divergencia e FORBIDDEN (nenhuma identidade '
  'do cliente vira autoridade de autoria). EXECUTE somente service_role.';

revoke all on function public.f5_11_ator_efetivo_observacao(uuid)
  from public, anon, authenticated;
grant execute on function public.f5_11_ator_efetivo_observacao(uuid)
  to service_role;

-- 1.2) Capability EFETIVA com allowlist FECHADA das capabilities de observacao
--      (mesmo molde de `f5_10_ator_valido_meta`, F5-10 P4 §10/D6).
create or replace function public.f5_11_ator_valido_observacao(
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
    coalesce(p_capability, '') in
      ('observation.read', 'observation.create', 'observation.edit', 'observation.delete')
    and public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id)
    and exists (
      select 1
        from public.resolver_capabilities_efetivas(
               p_actor_user_profile_id, p_organization_id) c
       where c.capability_code = p_capability
    );
$$;

comment on function public.f5_11_ator_valido_observacao(uuid, uuid, text) is
  'F5-11 P2 (§8): revalida ator soberano (perfil e membership ATIVOS no tenant), '
  'aplica a allowlist FECHADA das 4 capabilities de observacao (observation.read/'
  'create/edit/delete — observation.write e deprecada e nao entra) e confirma que '
  'a capability exigida e EFETIVA do ator via `resolver_capabilities_efetivas` '
  '(F4-01/F5-04). Codigo fora da allowlist => false (fail-closed). Sem concessao '
  'explicita (D15) o dominio permanece DENY em producao. EXECUTE somente service_role.';

revoke all on function public.f5_11_ator_valido_observacao(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.f5_11_ator_valido_observacao(uuid, uuid, text)
  to service_role;

-- 1.3) SELF sovereign: vinculo ATIVO e UNICO do ator com um collaborator do
--      tenant (`resolver_collaborador_vinculado`, F5-02). Zero ou ambiguidade =>
--      NULL (fail-closed): nunca matricula, nome, cargo ou corpo.
create or replace function public.f5_11_vinculo_observacao_do_ator(
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
  v_qtd   integer;
  v_colab uuid;
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

comment on function public.f5_11_vinculo_observacao_do_ator(uuid, uuid) is
  'F5-11 P2 (§8): resolve o SELF soberano do ator (perfil ativo + membership '
  'ativa + vinculo ativo e UNICO, F5-02). Zero/ambiguidade => NULL (fail-closed). '
  'EXECUTE somente service_role.';

revoke all on function public.f5_11_vinculo_observacao_do_ator(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.f5_11_vinculo_observacao_do_ator(uuid, uuid)
  to service_role;

-- 1.4) Relacao vigente do ator com o colaborador alvo: DIRECT_REPORTS ou
--      DESCENDANTS resolvidos na data (F4-02 `resolver_alvos_escopo`).
create or replace function public.f5_11_relacao_observacao_do_ator(
  p_actor_user_profile_id uuid,
  p_organization_id uuid,
  p_collaborator_id uuid,
  p_data timestamptz
)
returns boolean
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_rel boolean;
begin
  if p_actor_user_profile_id is null or p_organization_id is null
     or p_collaborator_id is null then
    return false;
  end if;

  select coalesce(bool_or(a.collaborator_id = p_collaborator_id), false)
    into v_rel
    from (
      select a1.collaborator_id
        from public.resolver_alvos_escopo(
               p_actor_user_profile_id, p_organization_id,
               'DIRECT_REPORTS', null, coalesce(p_data, now())) a1
      union all
      select a2.collaborator_id
        from public.resolver_alvos_escopo(
               p_actor_user_profile_id, p_organization_id,
               'DESCENDANTS', null, coalesce(p_data, now())) a2
    ) a;

  return coalesce(v_rel, false);
end;
$$;

comment on function public.f5_11_relacao_observacao_do_ator(uuid, uuid, uuid, timestamptz) is
  'F5-11 P2 (§8): relacao soberana do ator com o colaborador alvo — DIRECT_REPORTS '
  'ou DESCENDANTS resolvidos na data (F4-02). Ausencia de vinculo/relacao => false '
  '(fail-closed). SELF NAO entra aqui: SELF e tratado explicitamente pelo gate. '
  'EXECUTE somente service_role.';

revoke all on function public.f5_11_relacao_observacao_do_ator(uuid, uuid, uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.f5_11_relacao_observacao_do_ator(uuid, uuid, uuid, timestamptz)
  to service_role;

-- 1.5) Status VIGENTE do colaborador (D11), lido da linha soberana
--      (`collaborator_status_periods`, intervalo meio-aberto [valid_from, valid_to)).
--      NULL = nao resolvido (fail-closed).
create or replace function public.f5_11_status_vigente_do_colaborador(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns text
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_status text;
begin
  if p_collaborator_id is null then
    return null;
  end if;

  select sp.status into v_status
    from public.collaborator_status_periods sp
   where sp.collaborator_id = p_collaborator_id
     and sp.valid_from <= coalesce(p_data, now())
     and (sp.valid_to is null or sp.valid_to > coalesce(p_data, now()))
   order by sp.valid_from desc
   limit 1;

  return v_status;
end;
$$;

comment on function public.f5_11_status_vigente_do_colaborador(uuid, timestamptz) is
  'F5-11 P2 (D11): status VIGENTE do colaborador na data, lido apenas da fonte '
  'soberana `collaborator_status_periods` (meio-aberto). Nao resolvido => NULL '
  '(fail-closed). Helper NEUTRO de dominio (nao cria superficie de observacao). '
  'EXECUTE somente service_role.';

revoke all on function public.f5_11_status_vigente_do_colaborador(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.f5_11_status_vigente_do_colaborador(uuid, timestamptz)
  to service_role;

-- 1.6) GATE FUNCIONAL UNICO da observacao (capability + relacao + autoria).
--      O mapa operacao -> capability e FECHADO: a capability NUNCA vem do
--      chamador (nao ha como pedir a mais fraca para a operacao mais forte).
--        CRIAR                                       -> observation.create
--        EDITAR/COMUNICAR/DESCOMUNICAR/REVOGAR       -> observation.edit
--        EXCLUIR                                     -> observation.delete
--        OBTER/HISTORICO/LISTAR_ESCOPO               -> observation.read
--      Ordem: ator (auth.uid()) -> alvo por (id, tenant) -> capability ->
--      autoria/relacao. Fail-closed em qualquer ausencia.
create or replace function public.f5_11_exigir_autorizacao_observacao(
  p_operacao text,
  p_actor_user_profile_id uuid,
  p_organization_id uuid,
  p_observation_id uuid,
  p_collaborator_alvo_id uuid
)
returns void
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_operacao text := coalesce(p_operacao, '');
  v_cap      text;
  v_ator     uuid;
  v_alvo     uuid;
  v_autor    uuid;
  v_comunicado boolean;
  v_excluida   boolean;
  v_self     uuid;
  v_rel      boolean;
  v_status   text;
begin
  v_cap := case v_operacao
    when 'CRIAR'        then 'observation.create'
    when 'EDITAR'       then 'observation.edit'
    when 'COMUNICAR'    then 'observation.edit'
    when 'DESCOMUNICAR' then 'observation.edit'
    when 'REVOGAR'      then 'observation.edit'
    when 'EXCLUIR'      then 'observation.delete'
    when 'OBTER'        then 'observation.read'
    when 'HISTORICO'    then 'observation.read'
    when 'LISTAR_ESCOPO' then 'observation.read'
    else null
  end;

  if v_cap is null then
    raise exception
      'F5_11_FORBIDDEN: operacao de observacao desconhecida (%) — fail-closed',
      coalesce(p_operacao, '<null>');
  end if;

  -- (0) Identidade: auth.uid() e' a raiz (D3) — nenhum override pelo corpo.
  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  if p_organization_id is null then
    raise exception
      'F5_11_FORBIDDEN: organizacao obrigatoria na autorizacao funcional de observacao';
  end if;

  -- (1) CAPABILITY EFETIVA (F4) + ator/tenant (allowlist FECHADA).
  if not public.f5_11_ator_valido_observacao(v_ator, p_organization_id, v_cap) then
    raise exception
      'F5_11_FORBIDDEN: capability % ausente para a operacao % (fail-closed)',
      v_cap, v_operacao;
  end if;

  v_self := public.f5_11_vinculo_observacao_do_ator(v_ator, p_organization_id);

  -- (2) Alvo resolvido SEMPRE por (id, tenant): alvo de outro tenant nao e
  --     encontrado e a resposta e NOT_FOUND indistinguivel (sem oracle).
  if p_observation_id is not null then
    select o.collaborator_id, o.author_user_profile_id, o.comunicado, o.excluida
      into v_alvo, v_autor, v_comunicado, v_excluida
      from public.evaluation_observations o
     where o.id = p_observation_id
       and o.organization_id = p_organization_id;
    if not found then
      raise exception 'F5_11_NOT_FOUND: observacao inexistente ou de outro tenant';
    end if;
  else
    v_alvo := p_collaborator_alvo_id;
    if v_alvo is not null and not exists (
      select 1 from public.collaborators c
       where c.id = v_alvo and c.organization_id = p_organization_id
    ) then
      raise exception 'F5_11_NOT_FOUND: colaborador inexistente ou de outro tenant';
    end if;
  end if;

  -- (2b) ESTADO DO COLABORADOR (D11/§8, coluna "Estado do colaborador"):
  --      CRIAR e COMUNICAR exigem status VIGENTE resolvido e diferente de
  --      `inactive`; `active` e `leave` passam. A regra pertence a MATRIZ de
  --      autorizacao e e avaliada ANTES da relacao por dois motivos: (a) e a
  --      regra mais especifica/fail-closed do estado; (b) o colaborador
  --      `inactive` NAO tem occupation vigente (F3-05) e portanto nao resolveria
  --      relacao alguma — sem essa precedencia o teste de D11 nao seria
  --      atribuivel ao mecanismo pretendido.
  if v_operacao in ('CRIAR', 'COMUNICAR') then
    v_status := public.f5_11_status_vigente_do_colaborador(v_alvo, now());
    if v_status is null then
      raise exception
        'F5_11_FORBIDDEN: status vigente do colaborador alvo nao resolvido (fail-closed)';
    end if;
    if v_status = 'inactive' then
      raise exception
        'F5_11_CONFLICT: operacao % proibida para colaborador inactive (D11)',
        lower(v_operacao);
    end if;
  end if;

  -- (3) AUTORIA (D5) + RELACAO (§8), por operacao.
  if v_operacao in ('EDITAR', 'COMUNICAR', 'DESCOMUNICAR', 'REVOGAR', 'EXCLUIR') then
    if v_autor is distinct from v_ator then
      raise exception
        'F5_11_FORBIDDEN: somente o autor soberano pode % a observacao (autor persistido %)',
        lower(v_operacao), coalesce(v_autor::text, '<null>');
    end if;
    if not public.f5_11_relacao_observacao_do_ator(
             v_ator, p_organization_id, v_alvo, now()) then
      raise exception
        'F5_11_FORBIDDEN: ator sem relacao vigente com o colaborador alvo da observacao';
    end if;
  elsif v_operacao = 'CRIAR' then
    if v_alvo is null then
      raise exception 'F5_11_FORBIDDEN: criacao de observacao exige o colaborador alvo';
    end if;
    -- §8 invariante 4: SELF NAO cria observacao sobre si.
    if v_self is not null and v_self = v_alvo then
      raise exception 'F5_11_FORBIDDEN: SELF nao cria observacao sobre si proprio';
    end if;
    if not public.f5_11_relacao_observacao_do_ator(
             v_ator, p_organization_id, v_alvo, now()) then
      raise exception
        'F5_11_FORBIDDEN: colaborador alvo fora de DIRECT_REPORTS/DESCENDANTS do ator';
    end if;
  elsif v_operacao = 'LISTAR_ESCOPO' then
    -- Leitura sem alvo unico: o ESCOPO e aplicado pela propria RPC; aqui se
    -- exige o vinculo soberano do ator (sem ele nenhum escopo e resolvivel).
    if v_self is null then
      raise exception
        'F5_11_FORBIDDEN: ator sem vinculo soberano de colaborador na organizacao (fail-closed)';
    end if;
  else
    -- OBTER / HISTORICO: autor, relacao OU SELF-comunicada (§8 linhas 2/3).
    v_rel := public.f5_11_relacao_observacao_do_ator(
               v_ator, p_organization_id, v_alvo, now());
    if not (v_autor = v_ator
            or v_rel
            or (v_self is not null and v_self = v_alvo
                and v_comunicado and not v_excluida)) then
      raise exception
        'F5_11_FORBIDDEN: leitura da observacao fora do escopo do ator (autor, relacao ou SELF-comunicada)';
    end if;
  end if;
end;
$$;

comment on function public.f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid) is
  'F5-11 P2 (§8): gate funcional UNICO das 8 RPCs de observacao. Mapa FECHADO '
  'operacao -> capability (observacao desconhecida => raise), ator amarrado a '
  'auth.uid(), alvo resolvido por (id, tenant) com NOT_FOUND indistinguivel, '
  'AUTORIA D5 (somente o autor) e RELACAO DIRECT_REPORTS/DESCENDANTS. SELF nao '
  'cria sobre si; leitura SELF exige comunicado e nao excluida. Nenhuma '
  'autorizacao-de-ausencia: qualquer evidencia faltante => DENY. '
  'EXECUTE somente service_role.';

revoke all on function public.f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 2) `observacao_criar` — CRIADA (identidade UUID nasce no banco; D2/D3/D11/D12)
-- ----------------------------------------------------------------------------
-- Idempotente por `(organization_id, operation_id)`; ciclo ATIVO; colaborador
-- `active` ou `leave` (D11); autor derivado de auth.uid(); evento CRIADA na
-- MESMA transacao. Sem advisory lock (D10): a criacao nao tem linha a bloquear,
-- logo a serializacao de retry identico e' a unicidade do `operation_id` — e o
-- retry perdedor nao deixa residuo (o savepoint desfaz a linha desta transacao).
create or replace function public.observacao_criar(
  p_organization_id uuid,
  p_cycle_id uuid,
  p_collaborator_id uuid,
  p_tipo text,
  p_texto text,
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
  v_ator       uuid;
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_autor_colab uuid;
  v_id         uuid;
  v_versao     integer;
  v_ciclo      text;
  v_status     text;
  v_instante   timestamptz := now();
begin
  -- (1) Forma do payload — nada aqui e' autoridade.
  if p_organization_id is null or p_cycle_id is null or p_collaborator_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception
      'F5_11_INVALID_INPUT: organization_id, cycle_id, collaborator_id, ator e operation_id obrigatorios';
  end if;
  if p_tipo is null or p_tipo not in ('POSITIVA', 'NEUTRA', 'NEGATIVA') then
    raise exception 'F5_11_INVALID_INPUT: tipo deve ser POSITIVA, NEUTRA ou NEGATIVA';
  end if;
  if p_texto is null or p_texto = '' or p_texto <> btrim(p_texto) then
    raise exception 'F5_11_INVALID_INPUT: texto obrigatorio, nao vazio e sem espacos nas bordas';
  end if;
  if char_length(p_texto) > 2000 then
    raise exception 'F5_11_INVALID_INPUT: texto excede 2000 caracteres (recebido %)',
      char_length(p_texto);
  end if;

  -- (2) Identidade soberana (D3): auth.uid() e' a raiz.
  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  -- (3) Hash canonico da INTENCAO, derivado server-side (D6).
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'observacao_criar',
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'collaborator_id', p_collaborator_id,
    'tipo', p_tipo,
    'texto', p_texto
  )::text, 'UTF8')), 'hex');

  -- (4) Gate funcional (capability + relacao; SELF = DENY).
  perform public.f5_11_exigir_autorizacao_observacao(
    'CRIAR', v_ator, v_org, null, p_collaborator_id);

  -- (5) Idempotencia — caminho rapido.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'criada', true,
      'idempotente', true);
  end if;


  -- (6) Membership ativa do ator (autoria soberana da trilha) e vinculo de
  --     colaborador derivado do modelo soberano (nunca do corpo).
  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_11_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;
  v_autor_colab := public.f5_11_vinculo_observacao_do_ator(v_ator, v_org);

  -- (7) Ciclo do MESMO tenant e ATIVO (D12), lido da linha soberana.
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org;
  if not found then
    raise exception 'F5_11_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;
  if v_ciclo <> 'ATIVO' then
    raise exception 'F5_11_CONFLICT: criacao de observacao exige ciclo ATIVO (status atual %)',
      v_ciclo;
  end if;

  -- (8) Colaborador do MESMO tenant e status vigente (D11): `active` e `leave`
  --     permitem criacao; `inactive` NAO; status nao resolvido => DENY.
  if not exists (
    select 1 from public.collaborators c
     where c.id = p_collaborator_id and c.organization_id = v_org
  ) then
    raise exception 'F5_11_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;
  -- O status vigente do colaborador (D11) e' decidido no GATE funcional, antes da
  -- relacao — fonte unica da regra (nenhuma politica paralela aqui).

  -- (9) Criacao: identidade UUID do banco, autoria derivada, version 0.
  begin
    insert into public.evaluation_observations (
      organization_id, collaborator_id, cycle_id, tipo, texto,
      author_user_profile_id, author_membership_id, author_collaborator_id, version
    ) values (
      v_org, p_collaborator_id, p_cycle_id, p_tipo, p_texto,
      v_ator, v_membership, v_autor_colab, 0
    )
    returning id, version into v_id, v_versao;

    -- (10) Trilha append-only na MESMA transacao (D6).
    insert into public.evaluation_observation_events (
      organization_id, observation_id, entity_type, event_type, effective_date, reason,
      before_value, after_value, payload_hash, result_entity_id,
      actor_user_profile_id, actor_membership_id, operation_id
    ) values (
      v_org, v_id, 'evaluation_observation', 'CRIADA', v_instante,
      'Criacao de observacao',
      null,
      jsonb_build_object(
        'tipo', p_tipo, 'texto', p_texto, 'comunicado', false, 'excluida', false,
        'cycle_id', p_cycle_id, 'collaborator_id', p_collaborator_id,
        'version', v_versao),
      v_hash, v_id, v_ator, v_membership, p_operation_id
    );
  exception when unique_violation then
    -- Retry CONCORRENTE identico: o savepoint desfaz a observacao desta
    -- transacao; a intencao ja registrada devolve o MESMO resultado.
    select e.payload_hash, e.result_entity_id, e.after_value
      into v_evento
      from public.evaluation_observation_events e
     where e.organization_id = v_org
       and e.operation_id = p_operation_id;
    if not found then
      raise;
    end if;
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'criada', true,
      'idempotente', true);
  end;

  return jsonb_build_object(
    'observation_id', v_id, 'version', v_versao, 'criada', true, 'idempotente', false);
end;
$$;

comment on function public.observacao_criar(uuid, uuid, uuid, text, text, uuid, uuid) is
  'F5-11 P2 (§7.1/§8/D2/D3/D6/D11/D12): cria observacao soberana do tenant do ator '
  'verificado, em ciclo ATIVO, para colaborador active/leave, com identidade UUID '
  'do banco, autoria derivada de auth.uid() (perfil/membership/colaborador) e '
  'version 0. Gate `observation.create` + DIRECT_REPORTS/DESCENDANTS (SELF = DENY). '
  'Idempotente por (organization_id, operation_id) + payload_hash; evento CRIADA na '
  'MESMA transacao. SEM advisory lock (D10). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 3) `observacao_editar` — EDICAO da definicao completa (tipo/texto/comunicado)
-- ----------------------------------------------------------------------------
-- §7.5: a edicao recebe a DEFINICAO COMPLETA dos campos mutaveis e nao faz merge
-- parcial. §7.7: quando o comunicado TRANSICIONA, a transicao e' um FATO proprio
-- e grava evento dedicado (COMUNICADO / COMUNICACAO_REMOVIDA) — com
-- operation_id DERIVADO de forma deterministica (sub-evento da MESMA intencao).
-- D10: row lock + `expected_version`; NENHUM advisory lock.
create or replace function public.observacao_editar(
  p_observation_id uuid,
  p_organization_id uuid,
  p_tipo text,
  p_texto text,
  p_comunicado boolean,
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
  v_ator       uuid;
  v_hash       text;
  v_hash_com   text;
  v_evento     record;
  v_membership uuid;
  v_obs        record;
  v_ciclo      text;
  v_status     text;
  v_versao     integer;
  v_instante   timestamptz := now();
  v_transicao  text;
begin
  -- (a) Forma do payload.
  if p_observation_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception
      'F5_11_INVALID_INPUT: observation_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_11_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_tipo is null or p_tipo not in ('POSITIVA', 'NEUTRA', 'NEGATIVA') then
    raise exception 'F5_11_INVALID_INPUT: tipo deve ser POSITIVA, NEUTRA ou NEGATIVA';
  end if;
  if p_texto is null or p_texto = '' or p_texto <> btrim(p_texto) then
    raise exception 'F5_11_INVALID_INPUT: texto obrigatorio, nao vazio e sem espacos nas bordas';
  end if;
  if char_length(p_texto) > 2000 then
    raise exception 'F5_11_INVALID_INPUT: texto excede 2000 caracteres (recebido %)',
      char_length(p_texto);
  end if;
  if p_comunicado is null then
    raise exception 'F5_11_INVALID_INPUT: comunicado obrigatorio na definicao completa da edicao';
  end if;

  -- (b) Identidade soberana (D3).
  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  -- (c) Hash canonico da intencao.
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'observacao_editar',
    'organization_id', v_org,
    'observation_id', p_observation_id,
    'tipo', p_tipo,
    'texto', p_texto,
    'comunicado', p_comunicado,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (d) Gate funcional (capability + AUTORIA D5 + relacao).
  perform public.f5_11_exigir_autorizacao_observacao(
    'EDITAR', v_ator, v_org, p_observation_id, null);
  -- (e) Idempotencia — caminho rapido.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'idempotente', true);
  end if;


  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_11_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (f) Alvo por (id, tenant) + LOCK DA LINHA (D10). Sem advisory lock.
  select o.id, o.collaborator_id, o.cycle_id, o.tipo, o.texto, o.comunicado,
         o.comunicado_em, o.comunicado_por_user_profile_id, o.comunicado_por_membership_id,
         o.excluida, o.author_user_profile_id, o.version
    into v_obs
    from public.evaluation_observations o
   where o.id = p_observation_id
     and o.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_11_NOT_FOUND: observacao inexistente ou de outro tenant';
  end if;

  -- (g) Idempotencia SOB o lock (retry concorrente identico devolve o mesmo).
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'idempotente', true);
  end if;

  -- (h) Precondicoes de estado: observacao excluida nao aceita edicao; ciclo
  --     ATIVO (D12). Colaborador NAO e' reavaliado nesta operacao (§8 linha 5).
  if v_obs.excluida then
    raise exception 'F5_11_CONFLICT: observacao excluida nao aceita edicao';
  end if;
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = v_obs.cycle_id and c.organization_id = v_org;
  if v_ciclo is distinct from 'ATIVO' then
    raise exception 'F5_11_CONFLICT: edicao de observacao exige ciclo ATIVO (status atual %)',
      coalesce(v_ciclo, 'AUSENTE');
  end if;

  -- (i) expected_version comparado APOS o lock (D10).
  if v_obs.version <> p_expected_version then
    raise exception 'F5_11_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- (j) Transicao de comunicado: ir para `true` exige colaborador != inactive
  --     (§8 linha 6 — a regra mais restritiva vale para a transicao).
  if p_comunicado and not v_obs.comunicado then
    v_status := public.f5_11_status_vigente_do_colaborador(v_obs.collaborator_id, v_instante);
    if v_status is null then
      raise exception
        'F5_11_FORBIDDEN: status vigente do colaborador nao resolvido ao comunicar (fail-closed)';
    end if;
    if v_status = 'inactive' then
      raise exception
        'F5_11_CONFLICT: comunicado proibido para colaborador inactive (D11)';
    end if;
    v_transicao := 'COMUNICADO';
  elsif not p_comunicado and v_obs.comunicado then
    v_transicao := 'COMUNICACAO_REMOVIDA';
  else
    v_transicao := null;
  end if;

  -- (k) Mutacao `version + 1` (somente campos mutaveis do D4).
  update public.evaluation_observations
     set tipo = p_tipo,
         texto = p_texto,
         comunicado = p_comunicado,
         comunicado_em = case when p_comunicado then coalesce(v_obs.comunicado_em, v_instante) else null end,
         comunicado_por_user_profile_id = case when p_comunicado then coalesce(v_obs.comunicado_por_user_profile_id, v_ator) else null end,
         comunicado_por_membership_id = case when p_comunicado then coalesce(v_obs.comunicado_por_membership_id, v_membership) else null end,
         version = version + 1
   where id = p_observation_id
     and organization_id = v_org
  returning version into v_versao;

  -- (l) Evento EDITADA (before/after completos — preserva o "texto anterior").
  insert into public.evaluation_observation_events (
    organization_id, observation_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_observation_id, 'evaluation_observation', 'EDITADA', v_instante,
    'Edicao da definicao da observacao',
    jsonb_build_object(
      'tipo', v_obs.tipo, 'texto', v_obs.texto, 'comunicado', v_obs.comunicado,
      'excluida', v_obs.excluida, 'version', v_obs.version),
    jsonb_build_object(
      'tipo', p_tipo, 'texto', p_texto, 'comunicado', p_comunicado,
      'excluida', v_obs.excluida, 'version', v_versao),
    v_hash, p_observation_id, v_ator, v_membership, p_operation_id
  );

  -- (m) Transicao de comunicado como FATO proprio (D7), com operation_id
  --     DERIVADO (sub-evento da mesma intencao) — a unicidade
  --     `(organization_id, operation_id)` impede reuso.
  if v_transicao is not null then
    v_hash_com := encode(sha256(convert_to(jsonb_build_object(
      'operacao', 'observacao_editar',
      'sub_evento', v_transicao,
      'organization_id', v_org,
      'observation_id', p_observation_id,
      'comunicado', p_comunicado,
      'expected_version', p_expected_version
    )::text, 'UTF8')), 'hex');

    insert into public.evaluation_observation_events (
      organization_id, observation_id, entity_type, event_type, effective_date, reason,
      before_value, after_value, payload_hash, result_entity_id,
      actor_user_profile_id, actor_membership_id, operation_id
    ) values (
      v_org, p_observation_id, 'evaluation_observation', v_transicao, v_instante,
      case when v_transicao = 'COMUNICADO'
           then 'Comunicado ao avaliado (fato auditavel)'
           else 'Comunicacao removida' end,
      jsonb_build_object(
        'comunicado', v_obs.comunicado,
        'comunicado_em', v_obs.comunicado_em,
        'comunicado_por_user_profile_id', v_obs.comunicado_por_user_profile_id,
        'comunicado_por_membership_id', v_obs.comunicado_por_membership_id,
        'version', v_obs.version),
      jsonb_build_object(
        'comunicado', p_comunicado,
        'comunicado_em', case when p_comunicado then coalesce(v_obs.comunicado_em, v_instante) else null end,
        'comunicado_por_user_profile_id', case when p_comunicado then coalesce(v_obs.comunicado_por_user_profile_id, v_ator) else null end,
        'comunicado_por_membership_id', case when p_comunicado then coalesce(v_obs.comunicado_por_membership_id, v_membership) else null end,
        'version', v_versao),
      v_hash_com, p_observation_id, v_ator, v_membership,
      public.f5_10_derivar_operation_id(p_operation_id, v_transicao)
    );
  end if;

  return jsonb_build_object(
    'observation_id', p_observation_id,
    'version', v_versao,
    'comunicado', p_comunicado,
    'transicao_comunicado', v_transicao,
    'idempotente', false);
end;
$$;

comment on function public.observacao_editar(uuid, uuid, text, text, boolean, integer, uuid, uuid) is
  'F5-11 P2 (§7.5/§7.7/§8/D5/D10/D12): edita a DEFINICAO COMPLETA (tipo/texto/'
  'comunicado) da observacao do proprio autor soberano, com gate `observation.edit` '
  '+ relacao. Row lock + expected_version (D10; SEM advisory lock) e evento EDITADA '
  'na MESMA transacao; transicao de comunicado grava evento proprio (COMUNICADO/'
  'COMUNICACAO_REMOVIDA) com operation_id DERIVADO. Colaborador NAO e reavaliado '
  'nesta operacao (§8 linha 5); ir para comunicado exige != inactive (§8 linha 6). '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 4) `observacao_definir_comunicado` — transicao dedicada (D7)
-- ----------------------------------------------------------------------------
create or replace function public.observacao_definir_comunicado(
  p_observation_id uuid,
  p_organization_id uuid,
  p_comunicado boolean,
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
  v_ator       uuid;
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_obs        record;
  v_ciclo      text;
  v_status     text;
  v_versao     integer;
  v_instante   timestamptz := now();
  v_operacao   text;
  v_evento_tipo text;
begin
  -- (a) Forma.
  if p_observation_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception
      'F5_11_INVALID_INPUT: observation_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_comunicado is null then
    raise exception 'F5_11_INVALID_INPUT: comunicado (true/false) obrigatorio';
  end if;
  if p_expected_version is null then
    raise exception 'F5_11_INVALID_INPUT: expected_version obrigatorio';
  end if;

  v_operacao := case when p_comunicado then 'COMUNICAR' else 'DESCOMUNICAR' end;
  v_evento_tipo := case when p_comunicado then 'COMUNICADO' else 'COMUNICACAO_REMOVIDA' end;

  -- (b) Identidade soberana (D3).
  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  -- (c) Hash canonico da intencao.
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'observacao_definir_comunicado',
    'organization_id', v_org,
    'observation_id', p_observation_id,
    'comunicado', p_comunicado,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (d) Gate funcional (capability + AUTORIA D5 + relacao).
  perform public.f5_11_exigir_autorizacao_observacao(
    v_operacao, v_ator, v_org, p_observation_id, null);
  -- (e) Idempotencia — caminho rapido.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'comunicado', p_comunicado,
      'idempotente', true);
  end if;


  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_11_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (f) Alvo por (id, tenant) + LOCK DA LINHA (D10).
  select o.id, o.collaborator_id, o.cycle_id, o.comunicado, o.comunicado_em,
         o.comunicado_por_user_profile_id, o.comunicado_por_membership_id,
         o.excluida, o.version
    into v_obs
    from public.evaluation_observations o
   where o.id = p_observation_id
     and o.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_11_NOT_FOUND: observacao inexistente ou de outro tenant';
  end if;

  -- (g) Idempotencia sob o lock.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'comunicado', p_comunicado,
      'idempotente', true);
  end if;

  -- (h) Precondicoes de estado.
  if v_obs.excluida then
    raise exception 'F5_11_CONFLICT: observacao excluida nao aceita comunicacao';
  end if;
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = v_obs.cycle_id and c.organization_id = v_org;
  if v_ciclo is distinct from 'ATIVO' then
    raise exception 'F5_11_CONFLICT: comunicado exige ciclo ATIVO (status atual %)',
      coalesce(v_ciclo, 'AUSENTE');
  end if;
  if v_obs.comunicado = p_comunicado then
    raise exception 'F5_11_CONFLICT: comunicado ja esta no estado informado (nenhuma transicao a registrar)';
  end if;
  -- O status vigente do colaborador (D11) para COMUNICAR e' decidido no GATE
  -- funcional (operacao COMUNICAR), antes da relacao — fonte unica da regra.
  if v_obs.version <> p_expected_version then
    raise exception 'F5_11_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- (i) Mutacao: fato auditavel com ator e instante do SERVIDOR (D7).
  update public.evaluation_observations
     set comunicado = p_comunicado,
         comunicado_em = case when p_comunicado then v_instante else null end,
         comunicado_por_user_profile_id = case when p_comunicado then v_ator else null end,
         comunicado_por_membership_id = case when p_comunicado then v_membership else null end,
         version = version + 1
   where id = p_observation_id
     and organization_id = v_org
  returning version into v_versao;

  -- (j) Evento da transicao (COMUNICADO / COMUNICACAO_REMOVIDA).
  insert into public.evaluation_observation_events (
    organization_id, observation_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_observation_id, 'evaluation_observation', v_evento_tipo, v_instante,
    case when p_comunicado then 'Comunicado ao avaliado (fato auditavel)'
         else 'Comunicacao removida' end,
    jsonb_build_object(
      'comunicado', v_obs.comunicado,
      'comunicado_em', v_obs.comunicado_em,
      'comunicado_por_user_profile_id', v_obs.comunicado_por_user_profile_id,
      'comunicado_por_membership_id', v_obs.comunicado_por_membership_id,
      'version', v_obs.version),
    jsonb_build_object(
      'comunicado', p_comunicado,
      'comunicado_em', case when p_comunicado then v_instante else null end,
      'comunicado_por_user_profile_id', case when p_comunicado then v_ator else null end,
      'comunicado_por_membership_id', case when p_comunicado then v_membership else null end,
      'version', v_versao),
    v_hash, p_observation_id, v_ator, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'observation_id', p_observation_id,
    'version', v_versao,
    'comunicado', p_comunicado,
    'evento', v_evento_tipo,
    'idempotente', false);
end;
$$;

comment on function public.observacao_definir_comunicado(uuid, uuid, boolean, integer, uuid, uuid) is
  'F5-11 P2 (§7.7/§8/D5/D7/D11/D12): marca/desmarca o comunicado como FATO '
  'auditavel (ator e instante do servidor), somente pelo AUTOR soberano e com '
  '`observation.edit` (NENHUMA capability nova). Row lock + expected_version; '
  'evento COMUNICADO/COMUNICACAO_REMOVIDA na MESMA transacao. Marcar exige '
  'colaborador != inactive; estado ja igual => CONFLICT (nenhum evento falso). '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 5) `observacao_excluir` — exclusao LOGICA com motivo (D8/D16)
-- ----------------------------------------------------------------------------
create or replace function public.observacao_excluir(
  p_observation_id uuid,
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
  v_ator       uuid;
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_obs        record;
  v_ciclo      text;
  v_versao     integer;
  v_instante   timestamptz := now();
begin
  -- (a) Forma.
  if p_observation_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception
      'F5_11_INVALID_INPUT: observation_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_11_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_motivo is null or p_motivo = '' or p_motivo <> btrim(p_motivo) then
    raise exception
      'F5_11_INVALID_INPUT: motivo de exclusao obrigatorio, nao vazio e sem espacos nas bordas (D8/D16)';
  end if;
  if char_length(p_motivo) > 2000 then
    raise exception 'F5_11_INVALID_INPUT: motivo excede 2000 caracteres (recebido %)',
      char_length(p_motivo);
  end if;

  -- (b) Identidade soberana (D3).
  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  -- (c) Hash canonico.
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'observacao_excluir',
    'organization_id', v_org,
    'observation_id', p_observation_id,
    'motivo', p_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (d) Gate funcional (capability `observation.delete` + AUTORIA D5 + relacao).
  perform public.f5_11_exigir_autorizacao_observacao(
    'EXCLUIR', v_ator, v_org, p_observation_id, null);
  -- (e) Idempotencia — caminho rapido.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'excluida', true,
      'idempotente', true);
  end if;


  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_11_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (f) Alvo por (id, tenant) + LOCK DA LINHA (D10).
  select o.id, o.cycle_id, o.excluida, o.version
    into v_obs
    from public.evaluation_observations o
   where o.id = p_observation_id
     and o.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_11_NOT_FOUND: observacao inexistente ou de outro tenant';
  end if;

  -- (g) Idempotencia sob o lock.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'excluida', true,
      'idempotente', true);
  end if;

  -- (h) Precondicoes: exclusao e' transicao (nao idempotente em estado); ciclo
  --     ATIVO (D12); colaborador NAO e' reavaliado (§8 linha 8).
  if v_obs.excluida then
    raise exception 'F5_11_CONFLICT: observacao ja esta excluida (use a revogacao)';
  end if;
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = v_obs.cycle_id and c.organization_id = v_org;
  if v_ciclo is distinct from 'ATIVO' then
    raise exception 'F5_11_CONFLICT: exclusao de observacao exige ciclo ATIVO (status atual %)',
      coalesce(v_ciclo, 'AUSENTE');
  end if;
  if v_obs.version <> p_expected_version then
    raise exception 'F5_11_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- (i) Mutacao: exclusao SEMPRE logica, com ator, instante e MOTIVO (D8/D16).
  update public.evaluation_observations
     set excluida = true,
         excluida_em = v_instante,
         excluida_por_user_profile_id = v_ator,
         excluida_por_membership_id = v_membership,
         motivo_exclusao = p_motivo,
         version = version + 1
   where id = p_observation_id
     and organization_id = v_org
  returning version into v_versao;

  -- (j) Evento EXCLUIDA — o motivo e' o `reason` da trilha (D6/D8/D16).
  insert into public.evaluation_observation_events (
    organization_id, observation_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_observation_id, 'evaluation_observation', 'EXCLUIDA', v_instante,
    p_motivo,
    jsonb_build_object('excluida', false, 'version', v_obs.version),
    jsonb_build_object('excluida', true, 'motivo_exclusao', p_motivo, 'version', v_versao),
    v_hash, p_observation_id, v_ator, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'observation_id', p_observation_id,
    'version', v_versao,
    'excluida', true,
    'idempotente', false);
end;
$$;

comment on function public.observacao_excluir(uuid, uuid, text, integer, uuid, uuid) is
  'F5-11 P2 (§7.6/§8/D5/D8/D12/D16): exclusao LOGICA da observacao pelo autor '
  'soberano (`observation.delete` + relacao), com MOTIVO obrigatorio, ator, '
  'instante e version+1; evento EXCLUIDA com o motivo como `reason`. Exclusao '
  'fisica e PROIBIDA (ACL + triggers da P1). Row lock + expected_version '
  '(SEM advisory lock). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 6) `observacao_revogar` — desfaz a exclusao logica (D8)
-- ----------------------------------------------------------------------------
create or replace function public.observacao_revogar(
  p_observation_id uuid,
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
  v_ator       uuid;
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_obs        record;
  v_ciclo      text;
  v_versao     integer;
  v_instante   timestamptz := now();
begin
  -- (a) Forma.
  if p_observation_id is null or p_organization_id is null
     or p_actor_user_profile_id is null or p_operation_id is null then
    raise exception
      'F5_11_INVALID_INPUT: observation_id, organization_id, ator e operation_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_11_INVALID_INPUT: expected_version obrigatorio';
  end if;
  if p_motivo is null or p_motivo = '' or p_motivo <> btrim(p_motivo) then
    raise exception
      'F5_11_INVALID_INPUT: motivo da revogacao obrigatorio, nao vazio e sem espacos nas bordas (D8/D16)';
  end if;
  if char_length(p_motivo) > 2000 then
    raise exception 'F5_11_INVALID_INPUT: motivo excede 2000 caracteres (recebido %)',
      char_length(p_motivo);
  end if;

  -- (b) Identidade soberana (D3).
  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  -- (c) Hash canonico.
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'observacao_revogar',
    'organization_id', v_org,
    'observation_id', p_observation_id,
    'motivo', p_motivo,
    'expected_version', p_expected_version
  )::text, 'UTF8')), 'hex');

  -- (d) Gate funcional: revogar e' `observation.edit` (§8 linha 9) + AUTORIA D5.
  perform public.f5_11_exigir_autorizacao_observacao(
    'REVOGAR', v_ator, v_org, p_observation_id, null);
  -- (e) Idempotencia — caminho rapido.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'excluida', false,
      'idempotente', true);
  end if;


  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = v_ator
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_11_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (f) Alvo por (id, tenant) + LOCK DA LINHA (D10).
  select o.id, o.cycle_id, o.excluida, o.motivo_exclusao, o.version
    into v_obs
    from public.evaluation_observations o
   where o.id = p_observation_id
     and o.organization_id = v_org
   for update;
  if not found then
    raise exception 'F5_11_NOT_FOUND: observacao inexistente ou de outro tenant';
  end if;

  -- (g) Idempotencia sob o lock.
  select e.payload_hash, e.result_entity_id, e.after_value
    into v_evento
    from public.evaluation_observation_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_11_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return jsonb_build_object(
      'observation_id', v_evento.result_entity_id,
      'version', (v_evento.after_value->>'version')::integer,
      'excluida', false,
      'idempotente', true);
  end if;

  -- (h) Precondicoes: so' faz sentido revogar o que esta excluido; ciclo ATIVO.
  if not v_obs.excluida then
    raise exception 'F5_11_CONFLICT: observacao nao esta excluida (nada a revogar)';
  end if;
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = v_obs.cycle_id and c.organization_id = v_org;
  if v_ciclo is distinct from 'ATIVO' then
    raise exception 'F5_11_CONFLICT: revogacao exige ciclo ATIVO (status atual %)',
      coalesce(v_ciclo, 'AUSENTE');
  end if;
  if v_obs.version <> p_expected_version then
    raise exception 'F5_11_CONFLICT: versao divergente (expected_version desatualizado)';
  end if;

  -- (i) Mutacao: desfaz a exclusao logica (a trilha preserva EXCLUIDA).
  update public.evaluation_observations
     set excluida = false,
         excluida_em = null,
         excluida_por_user_profile_id = null,
         excluida_por_membership_id = null,
         motivo_exclusao = null,
         version = version + 1
   where id = p_observation_id
     and organization_id = v_org
  returning version into v_versao;

  -- (j) Evento REVOGADA com motivo obrigatorio (D6/D8/D16).
  insert into public.evaluation_observation_events (
    organization_id, observation_id, entity_type, event_type, effective_date, reason,
    before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_observation_id, 'evaluation_observation', 'REVOGADA', v_instante,
    p_motivo,
    jsonb_build_object('excluida', true, 'motivo_exclusao', v_obs.motivo_exclusao,
                       'version', v_obs.version),
    jsonb_build_object('excluida', false, 'motivo_exclusao', null, 'version', v_versao),
    v_hash, p_observation_id, v_ator, v_membership, p_operation_id
  );

  return jsonb_build_object(
    'observation_id', p_observation_id,
    'version', v_versao,
    'excluida', false,
    'idempotente', false);
end;
$$;

comment on function public.observacao_revogar(uuid, uuid, text, integer, uuid, uuid) is
  'F5-11 P2 (§7.6/§8/D5/D8/D12/D16): revoga a exclusao logica SOMENTE pelo autor '
  'soberano (`observation.edit` + relacao), em ciclo ATIVO, com motivo obrigatorio '
  'e evento REVOGADA. A trilha preserva EXCLUIDA — nada e apagado. Row lock + '
  'expected_version (SEM advisory lock). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 7) `observacao_obter` — leitura de UMA observacao (D9/§8 linhas 2/3)
-- ----------------------------------------------------------------------------
create or replace function public.observacao_obter(
  p_observation_id uuid,
  p_organization_id uuid,
  p_actor_user_profile_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_org uuid := p_organization_id;
  v_ator uuid;
  v_obs record;
begin
  if p_observation_id is null or p_organization_id is null
     or p_actor_user_profile_id is null then
    raise exception
      'F5_11_INVALID_INPUT: observation_id, organization_id e ator obrigatorios';
  end if;

  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  -- Gate: capability `observation.read` + (autor OU relacao OU SELF-comunicada).
  perform public.f5_11_exigir_autorizacao_observacao(
    'OBTER', v_ator, v_org, p_observation_id, null);

  select o.id, o.organization_id, o.collaborator_id, o.cycle_id, o.tipo, o.texto,
         o.comunicado, o.comunicado_em, o.excluida, o.motivo_exclusao,
         o.author_user_profile_id, o.author_collaborator_id, o.version,
         o.created_at, o.updated_at
    into v_obs
    from public.evaluation_observations o
   where o.id = p_observation_id
     and o.organization_id = v_org;
  if not found then
    raise exception 'F5_11_NOT_FOUND: observacao inexistente ou de outro tenant';
  end if;

  return jsonb_build_object(
    'observation_id', v_obs.id,
    'organization_id', v_obs.organization_id,
    'collaborator_id', v_obs.collaborator_id,
    'cycle_id', v_obs.cycle_id,
    'tipo', v_obs.tipo,
    'texto', v_obs.texto,
    'comunicado', v_obs.comunicado,
    'comunicado_em', v_obs.comunicado_em,
    'excluida', v_obs.excluida,
    'motivo_exclusao', v_obs.motivo_exclusao,
    'author_user_profile_id', v_obs.author_user_profile_id,
    'author_collaborator_id', v_obs.author_collaborator_id,
    'version', v_obs.version,
    'created_at', v_obs.created_at,
    'updated_at', v_obs.updated_at);
end;
$$;

comment on function public.observacao_obter(uuid, uuid, uuid) is
  'F5-11 P2 (§8 linhas 2/3/D9): le UMA observacao do tenant do ator com gate '
  '`observation.read` e visibilidade soberana (autor, relacao DIRECT_REPORTS/'
  'DESCENDANTS ou SELF-comunicada e nao excluida). Cross-tenant => NOT_FOUND '
  'indistinguivel. EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 8) `observacao_listar_por_escopo` — leitura por escopo (D9/§8 linhas 1/2)
-- ----------------------------------------------------------------------------
-- Allowlist FECHADA de escopos: SELF | DIRECT_REPORTS | DESCENDANTS (os demais
-- escopos do F4-02 nao tem relacao com observacao => raise). SELF devolve SOMENTE
-- o que esta comunicado e nao excluido (§8 linha 2); os escopos de gestao
-- devolvem as observacoes NAO excluidas dos alvos resolvidos na data.
create or replace function public.observacao_listar_por_escopo(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_escopo text,
  p_organizational_unit_id uuid,
  p_data timestamptz
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_org    uuid := p_organization_id;
  v_ator   uuid;
  v_escopo text := coalesce(p_escopo, '');
  v_data   timestamptz := coalesce(p_data, now());
  v_self   uuid;
  v_itens  jsonb;
  v_total  integer;
begin
  if p_organization_id is null or p_actor_user_profile_id is null then
    raise exception 'F5_11_INVALID_INPUT: organization_id e ator obrigatorios';
  end if;
  if v_escopo not in ('SELF', 'DIRECT_REPORTS', 'DESCENDANTS') then
    raise exception
      'F5_11_INVALID_INPUT: escopo % fora da allowlist fechada (SELF, DIRECT_REPORTS, DESCENDANTS)',
      coalesce(p_escopo, '<null>');
  end if;

  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  -- Gate: `observation.read` + vinculo soberano do ator (o escopo e' aplicado aqui).
  perform public.f5_11_exigir_autorizacao_observacao(
    'LISTAR_ESCOPO', v_ator, v_org, null, null);

  v_self := public.f5_11_vinculo_observacao_do_ator(v_ator, v_org);

  select coalesce(jsonb_agg(item order by ordem), '[]'::jsonb), count(*)
    into v_itens, v_total
    from (
      select jsonb_build_object(
               'observation_id', o.id,
               'collaborator_id', o.collaborator_id,
               'cycle_id', o.cycle_id,
               'tipo', o.tipo,
               'texto', o.texto,
               'comunicado', o.comunicado,
               'comunicado_em', o.comunicado_em,
               'excluida', o.excluida,
               'author_user_profile_id', o.author_user_profile_id,
               'author_collaborator_id', o.author_collaborator_id,
               'version', o.version,
               'created_at', o.created_at,
               'updated_at', o.updated_at) as item,
             o.created_at as ordem
        from public.evaluation_observations o
        join (
          select a.collaborator_id
            from public.resolver_alvos_escopo(
                   v_ator, v_org, v_escopo, p_organizational_unit_id, v_data) a
        ) alvo on alvo.collaborator_id = o.collaborator_id
       where o.organization_id = v_org
         and (
           case when v_escopo = 'SELF'
                then o.comunicado and not o.excluida
                else not o.excluida
           end
         )
    ) t;

  v_itens := coalesce(v_itens, '[]'::jsonb);
  v_total := coalesce(v_total, 0);

  return jsonb_build_object(
    'escopo', v_escopo,
    'self_collaborator_id', v_self,
    'data', v_data,
    'total', v_total,
    'itens', v_itens);
end;
$$;

comment on function public.observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz) is
  'F5-11 P2 (§8 linhas 1/2/D9): leitura por ESCOPO com `observation.read` e '
  'allowlist FECHADA (SELF, DIRECT_REPORTS, DESCENDANTS). SELF devolve somente o '
  'comunicado e nao excluido; os escopos de gestao devolvem as observacoes nao '
  'excluidas dos alvos resolvidos pela fonte soberana (F4-02), na data. Nenhum '
  'privilegio de cliente e criado — a leitura e exclusivamente por RPC. '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 9) `observacao_historico` — leitura da trilha (D6/D9/§8 linha 10)
-- ----------------------------------------------------------------------------
-- A trilha NAO amplia alcance: a visibilidade e' a MESMA de `observacao_obter`.
create or replace function public.observacao_historico(
  p_observation_id uuid,
  p_organization_id uuid,
  p_actor_user_profile_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_org    uuid := p_organization_id;
  v_ator   uuid;
  v_itens  jsonb;
  v_total  integer;
begin
  if p_observation_id is null or p_organization_id is null
     or p_actor_user_profile_id is null then
    raise exception
      'F5_11_INVALID_INPUT: observation_id, organization_id e ator obrigatorios';
  end if;

  v_ator := public.f5_11_ator_efetivo_observacao(p_actor_user_profile_id);

  perform public.f5_11_exigir_autorizacao_observacao(
    'HISTORICO', v_ator, v_org, p_observation_id, null);

  select coalesce(jsonb_agg(item order by ordem, id_ordem), '[]'::jsonb), count(*)
    into v_itens, v_total
    from (
      select jsonb_build_object(
               'event_id', e.id,
               'event_type', e.event_type,
               'effective_date', e.effective_date,
               'reason', e.reason,
               'before_value', e.before_value,
               'after_value', e.after_value,
               'payload_hash', e.payload_hash,
               'actor_user_profile_id', e.actor_user_profile_id,
               'actor_membership_id', e.actor_membership_id,
               'operation_id', e.operation_id,
               'created_at', e.created_at) as item,
             e.created_at as ordem,
             e.id as id_ordem
        from public.evaluation_observation_events e
       where e.observation_id = p_observation_id
         and e.organization_id = v_org
    ) t;

  v_itens := coalesce(v_itens, '[]'::jsonb);
  v_total := coalesce(v_total, 0);

  return jsonb_build_object(
    'observation_id', p_observation_id,
    'total', v_total,
    'eventos', v_itens);
end;
$$;

comment on function public.observacao_historico(uuid, uuid, uuid) is
  'F5-11 P2 (§7.8/§8 linha 10/D6/D9): devolve a TRILHA append-only da observacao '
  '(before/after, motivo, ator, payload_hash, operation_id) com a MESMA '
  'visibilidade de `observacao_obter` — a trilha nao amplia alcance. '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 10) Fronteira de execucao das 8 RPCs: SOMENTE `service_role`
-- ----------------------------------------------------------------------------
revoke all on function public.observacao_criar(uuid, uuid, uuid, text, text, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.observacao_editar(uuid, uuid, text, text, boolean, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.observacao_definir_comunicado(uuid, uuid, boolean, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.observacao_excluir(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.observacao_revogar(uuid, uuid, text, integer, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.observacao_obter(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.observacao_historico(uuid, uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.observacao_criar(uuid, uuid, uuid, text, text, uuid, uuid)
  to service_role;
grant execute on function public.observacao_editar(uuid, uuid, text, text, boolean, integer, uuid, uuid)
  to service_role;
grant execute on function public.observacao_definir_comunicado(uuid, uuid, boolean, integer, uuid, uuid)
  to service_role;
grant execute on function public.observacao_excluir(uuid, uuid, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.observacao_revogar(uuid, uuid, text, integer, uuid, uuid)
  to service_role;
grant execute on function public.observacao_obter(uuid, uuid, uuid)
  to service_role;
grant execute on function public.observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)
  to service_role;
grant execute on function public.observacao_historico(uuid, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 11) Guarda final FAIL-CLOSED da P2
-- ----------------------------------------------------------------------------
-- A migration so termina se: as 8 RPCs e os 6 helpers existirem, forem SECURITY
-- INVOKER com `search_path` fixo e EXECUTE somente `service_role`; as RPCs de
-- MUTACAO usarem row lock + `expected_version` e NENHUM advisory lock (D10);
-- toda mutacao gravar evento na MESMA transacao; a superficie `observacao_*`
-- for EXATAMENTE a lista fechada (nenhuma RPC extra, nenhuma `observation_*`);
-- e os invariantes da P1/P1.1 e o D15 continuarem INTACTOS.
do $$
declare
  v_falhas   text[] := array[]::text[];
  v_rpcs     text[] := array[
    'observacao_criar(uuid, uuid, uuid, text, text, uuid, uuid)',
    'observacao_editar(uuid, uuid, text, text, boolean, integer, uuid, uuid)',
    'observacao_definir_comunicado(uuid, uuid, boolean, integer, uuid, uuid)',
    'observacao_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_revogar(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_obter(uuid, uuid, uuid)',
    'observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)',
    'observacao_historico(uuid, uuid, uuid)'];
  v_helpers  text[] := array[
    'f5_11_ator_efetivo_observacao(uuid)',
    'f5_11_ator_valido_observacao(uuid, uuid, text)',
    'f5_11_vinculo_observacao_do_ator(uuid, uuid)',
    'f5_11_relacao_observacao_do_ator(uuid, uuid, uuid, timestamptz)',
    'f5_11_status_vigente_do_colaborador(uuid, timestamptz)',
    'f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid)'];
  v_mutacoes text[] := array[
    'observacao_criar(uuid, uuid, uuid, text, text, uuid, uuid)',
    'observacao_editar(uuid, uuid, text, text, boolean, integer, uuid, uuid)',
    'observacao_definir_comunicado(uuid, uuid, boolean, integer, uuid, uuid)',
    'observacao_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_revogar(uuid, uuid, text, integer, uuid, uuid)'];
  v_fn       text;
  v_tab      text;
  v_rec      record;
  v_n        integer;
begin
  -- (a) Superficie exata: 8 RPCs + 6 helpers, INVOKER, search_path fixo,
  --     EXECUTE somente service_role.
  foreach v_fn in array (v_rpcs || v_helpers) loop
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
    -- D3: a identidade passa pelo helper que amarra auth.uid().
    if v_fn = any (v_rpcs)
       and position('f5_11_ator_efetivo_observacao' in v_rec.def) = 0 then
      v_falhas := v_falhas || ('RPC sem amarracao a auth.uid() (D3): ' || v_fn);
    end if;
    -- D10: NENHUM advisory lock e NENHUMA familia de lock de ciclo.
    if position('pg_advisory' in v_rec.def) > 0
       or position('ciclo_lock_organizacao' in v_rec.def) > 0 then
      v_falhas := v_falhas || ('advisory lock no corpo (D10 proibe): ' || v_fn);
    end if;
    -- Exclusao apenas logica: nenhuma RPC apaga ou trunca.
    if position('delete from' in v_rec.def) > 0
       or position('truncate' in v_rec.def) > 0 then
      v_falhas := v_falhas || ('RPC com DELETE/TRUNCATE: ' || v_fn);
    end if;
  end loop;

  -- (b) Mutacoes: row lock + expected_version + evento na MESMA transacao.
  foreach v_fn in array v_mutacoes loop
    select lower(pg_get_functiondef(p.oid)) as def
      into v_rec
      from pg_proc p
     where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      continue;
    end if;
    if position('for update' in v_rec.def) = 0
       and position('observacao_criar' in v_fn) = 0 then
      v_falhas := v_falhas || ('mutacao sem row lock (D10): ' || v_fn);
    end if;
    if position('expected_version' in v_rec.def) = 0
       and position('observacao_criar' in v_fn) = 0 then
      v_falhas := v_falhas || ('mutacao sem expected_version (D10): ' || v_fn);
    end if;
    if position('insert into public.evaluation_observation_events' in v_rec.def) = 0 then
      v_falhas := v_falhas || ('mutacao sem evento na mesma transacao (D6): ' || v_fn);
    end if;
  end loop;

  -- (c) Lista FECHADA da superficie: nenhuma outra funcao `observacao_*` e
  --     NENHUMA `observation_*` (a P3/P4 nao pode ser antecipada).
  -- Comparacao por OID (`to_regprocedure`), nao por texto de assinatura: o
  -- formato canonico de `pg_get_function_identity_arguments` nao e' contrato.
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname like 'observacao\_%'
     and not exists (
       select 1 from unnest(v_rpcs) f
        where to_regprocedure('public.' || f) = p.oid
     );
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) observacao_* FORA da lista fechada da P2', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname like 'observation\_%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) observation_* (prefixo proibido pelo D1)', v_n);
  end if;

  -- (d) D9/D4/D6 da P1 e a coerencia da P1.1 continuam INTACTOS.
  foreach v_tab in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = v_tab
    ) then
      v_falhas := v_falhas || ('policy criada em ' || v_tab || ' (P3 nao antecipada)');
    end if;
    if has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'UPDATE') then
      v_falhas := v_falhas || ('privilegio de cliente aberto em ' || v_tab);
    end if;
  end loop;
  if has_table_privilege('service_role', 'public.evaluation_observations', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_observations', 'TRUNCATE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'UPDATE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'TRUNCATE') then
    v_falhas := v_falhas || 'service_role com privilegio de reescrita/exclusao fisica'::text;
  end if;
  foreach v_fn in array array[
    'enforce_evaluation_observations_imutaveis',
    'enforce_evaluation_observation_events_append_only',
    'f5_11_validar_coerencia_identidade',
    'f5_11_validar_coerencia_identidade_evento'] loop
    if to_regprocedure('public.' || v_fn || '()') is null then
      v_falhas := v_falhas || ('funcao de invariante ausente: ' || v_fn);
    end if;
  end loop;

  -- (e) D15 INTACTO: catalogo 31, ZERO concessao de `observation.*`, `admin`
  --     com 9 e SEM `observation.*`, roles de sistema inalteradas.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo com %s capabilities (esperado 31)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s concessao(oes) de observation.* (D15 violado)', v_n);
  end if;
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    v_falhas := v_falhas || format('bundle admin com %s capabilities (esperado 9)', v_n);
  end if;
  if (select array_agg(r.name order by r.name)
        from public.access_roles r where r.is_system = true)
     is distinct from array['admin', 'metas_aprovador', 'metas_dono'] then
    v_falhas := v_falhas || 'conjunto de roles de SISTEMA mudou'::text;
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] F5-11 P2: guarda final: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-11 P2: guarda final OK (8 RPCs observacao_* + 6 helpers INVOKER com search_path fixo e EXECUTE so service_role; row lock + expected_version SEM advisory lock; eventos na mesma transacao; lista fechada; D4/D6/D9 e P1.1 intactos; catalogo 31; admin 9 SEM observation.*; D15 segue BLOQUEANDO a P3)';
end $$;
