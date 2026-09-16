-- ============================================================================
-- F5-11 P3 (Issue #246): AUTORIZACAO + capabilities/concessoes + scope soberano
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-11-desenho-tecnico.md (D1-D16; §8 matriz NORMATIVA; §17.1
-- criterios da P3; §21 registro da D15 decidida pelo orquestrador).
--
-- DECISAO D15 (fechada pelo orquestrador): o dominio nasce DECIDIVEL em producao
-- por um perfil de SISTEMA funcional dedicado — `observacoes_gestor` — com
-- EXATAMENTE as 4 capabilities canonicas de observacao, atribuivel por assignment
-- com scope de GESTAO. `admin` permanece com ZERO `observation.*`;
-- `metas_dono`/`metas_aprovador` permanecem exclusivos de metas; `observation.write`
-- permanece DEPRECADA (nao concedivel por role, por trigger da F5-04).
--
-- Mapeamento normativo (capability -> perfil -> scope):
--   observation.read   -> observacoes_gestor -> DIRECT_REPORTS / DESCENDANTS
--   observation.create -> observacoes_gestor -> DIRECT_REPORTS / DESCENDANTS
--   observation.edit   -> observacoes_gestor -> DIRECT_REPORTS / DESCENDANTS
--   observation.delete -> observacoes_gestor -> DIRECT_REPORTS / DESCENDANTS
--   * SELF nao pertence ao bundle padrao: a leitura SELF-comunicada continua
--     regida pela regra ESPECIFICA do dominio (§8 linha 2 / D7), sem exigir
--     scope de gestao — e por isso NAO ha scope SELF no perfil.
--   * ORGANIZATION nao pertence ao bundle padrao (nao satisfaz o enforcement).
--
-- O QUE ESTA MIGRATION FAZ (e o que NAO faz):
--   1) cria o perfil de sistema `observacoes_gestor` + os 4 vinculos de
--      capability, com guarda fail-closed do conjunto EXATO (molde F5-10 P4);
--   2) faz o SCOPE participar do ENFORCEMENT REAL, cumulativamente com a
--      capability (allowlist fechada) e com a RELACAO estrutural: o gate das
--      RPCs passa a exigir, via `resolver_capabilities_escopos_efetivas`, um
--      grant com scope DIRECT_REPORTS ou DESCENDANTS (scope NAO e metadado);
--   3) NAO cria capability nova (catalogo 31), NAO toca `admin` nem as roles de
--      metas, NAO cria policy/RLS nova, NAO abre privilegio de cliente, NAO
--      altera tabela/coluna/constraint e NAO antecipa P4/P5/P6;
--   4) NAO edita retroativamente as migrations da P1/P1.1/P2: reescreve APENAS
--      as duas funcoes de gate por `create or replace` (doutrina do repositorio:
--      F5-10 P3 reconectou `meta_editar` do mesmo modo).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Preflight do baseline (fail-closed, sem ajuste silencioso)
-- ----------------------------------------------------------------------------
do $$
declare
  v_faltando text[] := array[]::text[];
  v_fn       text;
  v_rec      record;
  v_n        integer;
begin
  -- (a) P1/P1.1/P2 instaladas: as 2 tabelas + as funcoes de invariante e as
  --      funcoes da P2 (8 RPCs + 6 helpers) existem.
  foreach v_fn in array array[
    'public.evaluation_observations', 'public.evaluation_observation_events'] loop
    if to_regclass(v_fn) is null then
      v_faltando := v_faltando || ('tabela ausente: ' || v_fn);
    end if;
  end loop;
  foreach v_fn in array array[
    'enforce_evaluation_observations_imutaveis()',
    'enforce_evaluation_observation_events_append_only()',
    'f5_11_validar_coerencia_identidade()',
    'f5_11_validar_coerencia_identidade_evento()',
    'f5_11_ator_efetivo_observacao(uuid)',
    'f5_11_ator_valido_observacao(uuid, uuid, text)',
    'f5_11_vinculo_observacao_do_ator(uuid, uuid)',
    'f5_11_relacao_observacao_do_ator(uuid, uuid, uuid, timestamptz)',
    'f5_11_status_vigente_do_colaborador(uuid, timestamptz)',
    'f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid)',
    'observacao_criar(uuid, uuid, uuid, text, text, uuid, uuid)',
    'observacao_editar(uuid, uuid, text, text, boolean, integer, uuid, uuid)',
    'observacao_definir_comunicado(uuid, uuid, boolean, integer, uuid, uuid)',
    'observacao_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_revogar(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_obter(uuid, uuid, uuid)',
    'observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)',
    'observacao_historico(uuid, uuid, uuid)',
    'resolver_capabilities_efetivas(uuid, uuid)',
    'resolver_capabilities_escopos_efetivas(uuid, uuid)'] loop
    if to_regprocedure(v_fn) is null then
      v_faltando := v_faltando || ('funcao ausente: ' || v_fn);
    end if;
  end loop;

  -- (b) Catalogo INTACTO (31 codigos) e as 4 capabilities canonicas de
  --     observacao ativas, nao deprecadas e concediveis por role.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_faltando := v_faltando || format('catalogo com %s codigos (esperado 31)', v_n);
  end if;
  select count(*) into v_n from public.capabilities c
   where c.code in ('observation.read', 'observation.create',
                    'observation.edit', 'observation.delete')
     and c.status = 'active' and c.deprecated = false
     and c.grantable_via_role = true;
  if v_n <> 4 then
    v_faltando := v_faltando || format('%s capability(ies) canonica(s) de observacao utilizavel(is) (esperado 4)', v_n);
  end if;
  if not exists (
    select 1 from public.capabilities
     where code = 'observation.write' and deprecated = true
  ) then
    v_faltando := v_faltando || 'observation.write deveria estar DEPRECADA (F5-04 D14)';
  end if;

  -- (c) Baseline LIMPO: nenhuma concessao de `observation.*` antes da P3 (a
  --     F5-11 P1/P1.1/P2 nao concedem nada — D15 so e' resolvida aqui).
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    v_faltando := v_faltando || format('%s concessao(oes) de observation.* ja existentes (baseline sujo)', v_n);
  end if;

  -- (d) Roles de SISTEMA exatamente as 3 anteriores e `admin` com 9 SEM
  --     observation.* (as guardas que a P3 vai ampliar partem deste estado).
  if (select array_agg(r.name order by r.name)
        from public.access_roles r where r.is_system = true)
     is distinct from array['admin', 'metas_aprovador', 'metas_dono'] then
    v_faltando := v_faltando || 'conjunto de roles de SISTEMA inesperado antes da P3';
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
    v_faltando := v_faltando || 'bundle admin JA contem observation.* (guarda F4-01 violada)';
  end if;

  -- (e) D9 intacto antes de comecar (nenhuma policy nas 2 tabelas).
  foreach v_fn in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = v_fn
    ) then
      v_faltando := v_faltando || ('policy indevida antes da P3: ' || v_fn);
    end if;
  end loop;

  if array_length(v_faltando, 1) is not null then
    raise exception
      'F5_11_P3_INCOMPATIBLE_BASELINE: baseline incompativel com o contrato da P3: %',
      array_to_string(v_faltando, '; ');
  end if;

  raise notice 'F5-11 P3: preflight OK (P1 + P1.1 + P2 instaladas; catalogo 31; observation.write deprecada; ZERO concessao de observation.*; admin com 9 e sem observation.*; D9 intacto)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) CONCESSAO EXPLICITA (D15): perfil de sistema `observacoes_gestor`
-- ----------------------------------------------------------------------------
-- Perfil de SISTEMA funcional por dominio (organization_id nulo), criado por
-- MIGRATION, com conjunto EXATO das 4 capabilities — molde normativo da F5-10
-- P4 (`metas_dono`/`metas_aprovador`, `20260925000000:2265-2399`).
-- A ATRIBUICAO a memberships NAO acontece aqui: ela e' configuracao
-- administrativa server-side pelo caminho soberano ja existente
-- (`conceder_acesso_role`, `service_role`) + linha de scope da assignment
-- (`access_role_assignment_scopes`), exatamente como nas fases F4-02/F4-08/
-- F5-07/F5-08.
do $$
declare
  v_role     uuid;
  v_caps     uuid[];
  v_catalogo integer;
  v_n        integer;
begin
  select count(*) into v_catalogo from public.capabilities;

  select id into v_role
    from public.access_roles
   where name = 'observacoes_gestor' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    insert into public.access_roles (name, status, is_system, organization_id)
    values ('observacoes_gestor', 'active', true, null)
    returning id into v_role;
  end if;

  select array_agg(c.id order by c.code) into v_caps
    from public.capabilities c
   where c.code in ('observation.read', 'observation.create',
                    'observation.edit', 'observation.delete')
     and c.status = 'active' and c.deprecated = false
     and c.grantable_via_role = true;
  if array_length(v_caps, 1) <> 4 then
    raise exception 'F5_11_P3_BUNDLE: conjunto de capabilities de observacao incompleto';
  end if;

  insert into public.access_role_capabilities (access_role_id, capability_id)
  select v_role, x.cap
    from unnest(v_caps) as x(cap)
   where not exists (
     select 1 from public.access_role_capabilities m
      where m.access_role_id = v_role and m.capability_id = x.cap);

  -- ---- Guarda fail-closed do bundle (conjunto EXATO) ----
  if (select count(*) from public.capabilities) <> v_catalogo then
    raise exception 'F5_11_P3_BUNDLE: catalogo de capabilities mudou de tamanho';
  end if;
  select count(*) into v_n
    from public.access_role_capabilities m
    join public.capabilities c on c.id = m.capability_id
   where m.access_role_id = v_role and c.code like 'observation.%';
  if v_n <> 4 then
    raise exception 'F5_11_P3_BUNDLE: observacoes_gestor deveria ter EXATAMENTE 4 capabilities de observacao (tem %)', v_n;
  end if;
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_role
       and c.code not in ('observation.read', 'observation.create',
                          'observation.edit', 'observation.delete')
  ) then
    raise exception 'F5_11_P3_BUNDLE: observacoes_gestor tem capability FORA do dominio de observacao';
  end if;
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and r.id <> v_role
       and c.code like 'observation.%'
  ) then
    raise exception 'F5_11_P3_BUNDLE: observation.* concedida a OUTRA role de sistema';
  end if;
  if not exists (
    select 1 from public.access_roles
     where id = v_role and is_system = true and organization_id is null and status = 'active'
  ) then
    raise exception 'F5_11_P3_BUNDLE: observacoes_gestor nao e role de sistema ativa sem organizacao';
  end if;

  raise notice 'F5-11 P3: perfil de sistema `observacoes_gestor` com EXATAMENTE as 4 capabilities canonicas (read/create/edit/delete); catalogo intacto; nenhuma observation.* em admin/metas_*';
end $$;

-- ----------------------------------------------------------------------------
-- 2) Helper: o ator tem a capability COM scope compatível? (enforcement real)
-- ----------------------------------------------------------------------------
-- O scope NAO e metadado declarativo: ele e' lido do unico resolver soberano
-- escopado (`resolver_capabilities_escopos_efetivas`, F4-02/F5-04), que exige
-- assignment ATIVA + scope ATIVO. Assignment sem scope => nada aqui => DENY.
create or replace function public.f5_11_ator_tem_escopo_observacao(
  p_actor_user_profile_id uuid,
  p_organization_id uuid,
  p_capability text,
  p_escopos text[]
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    p_capability is not null
    and p_escopos is not null
    and exists (
      select 1
        from public.resolver_capabilities_escopos_efetivas(
               p_actor_user_profile_id, p_organization_id) c
       where c.capability_code = p_capability
         and c.scope_type = any (p_escopos)
    );
$$;

comment on function public.f5_11_ator_tem_escopo_observacao(uuid, uuid, text, text[]) is
  'F5-11 P3 (D15/§8): o ator possui a capability EXIGIDA com um SCOPE da lista —
  lido do resolver soberano escopado (F4-02: assignment ativa + scope ativo;
  assignment sem scope => falso, fail-closed). E o enforcement REAL do scope,
  cumulativo com a capability e com a relacao estrutural. EXECUTE somente service_role.';

revoke all on function public.f5_11_ator_tem_escopo_observacao(uuid, uuid, text, text[])
  from public, anon, authenticated;
grant execute on function public.f5_11_ator_tem_escopo_observacao(uuid, uuid, text, text[])
  to service_role;

-- ----------------------------------------------------------------------------
-- 3) GATE FUNCIONAL: capability + SCOPE + AUTORIA (D5) + RELACAO estrutural
-- ----------------------------------------------------------------------------
-- Reescrita por `create or replace` (a migration da P2 NAO e' editada):
--   - mantem TUDO o que a P2 provou (mapa FECHADO de operacao, auth.uid(),
--     alvo por (id, tenant) com NOT_FOUND indistinguivel, D11, D5 e relacao);
--   - ACRESCENTA o SCOPE como condicao CUMULATIVA: mutacoes e leitura de
--     terceiros exigem grant com scope DIRECT_REPORTS ou DESCENDANTS;
--   - EXCECAO NORMATIVA: a leitura SELF-comunicada (§8 linha 2/D7) NAO exige
--     scope de gestao — ela e' regida pela regra especifica do dominio, e o
--     perfil padrao nao carrega scope SELF.
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
  v_self_ok  boolean;
  v_escopos_gestao constant text[] := array['DIRECT_REPORTS', 'DESCENDANTS'];
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

  -- (2b) ESTADO DO COLABORADOR (D11/§8): CRIAR e COMUNICAR exigem status
  --      vigente resolvido e diferente de `inactive`; avaliado ANTES da relacao
  --      (precedencia declarada na P2: `inactive` nao tem occupation vigente).
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

  -- (2c) SCOPE SOBERANO (D15/P3) — condicao CUMULATIVA com capability e relacao.
  --      Leitura SELF-comunicada e' a UNICA excecao normativa (regra especifica
  --      do dominio, §8 linha 2 / D7).
  v_self_ok := (v_self is not null and v_alvo is not null and v_self = v_alvo
                and v_comunicado and not v_excluida);

  if v_operacao in ('CRIAR', 'EDITAR', 'COMUNICAR', 'DESCOMUNICAR', 'REVOGAR', 'EXCLUIR') then
    if not public.f5_11_ator_tem_escopo_observacao(
             v_ator, p_organization_id, v_cap, v_escopos_gestao) then
      raise exception
        'F5_11_FORBIDDEN: scope de gestao (DIRECT_REPORTS/DESCENDANTS) ausente para a operacao %',
        lower(v_operacao);
    end if;
  elsif v_operacao in ('OBTER', 'HISTORICO') and not v_self_ok then
    if not public.f5_11_ator_tem_escopo_observacao(
             v_ator, p_organization_id, v_cap, v_escopos_gestao) then
      raise exception
        'F5_11_FORBIDDEN: scope de gestao (DIRECT_REPORTS/DESCENDANTS) ausente para a operacao %',
        lower(v_operacao);
    end if;
  end if;
  -- LISTAR_ESCOPO: o gate exige a capability e o vinculo; o SCOPE e' exigido
  -- pela propria RPC, que conhece o escopo pedido (SELF x gestao).

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
    if v_self is null then
      raise exception
        'F5_11_FORBIDDEN: ator sem vinculo soberano de colaborador na organizacao (fail-closed)';
    end if;
  else
    -- OBTER / HISTORICO: autor, relacao OU SELF-comunicada (§8 linhas 2/3).
    v_rel := public.f5_11_relacao_observacao_do_ator(
               v_ator, p_organization_id, v_alvo, now());
    if not (v_autor = v_ator or v_rel or v_self_ok) then
      raise exception
        'F5_11_FORBIDDEN: leitura da observacao fora do escopo do ator (autor, relacao ou SELF-comunicada)';
    end if;
  end if;
end;
$$;

comment on function public.f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid) is
  'F5-11 P2 (reescrito na P3): gate funcional UNICO das 8 RPCs de observacao. '
  'Mapa FECHADO operacao -> capability, ator amarrado a auth.uid(), alvo por '
  '(id, tenant) com NOT_FOUND indistinguivel, D11 (estado do colaborador), '
  'AUTORIA D5, RELACAO DIRECT_REPORTS/DESCENDANTS e — desde a P3/D15 — SCOPE '
  'soberano CUMULATIVO (resolver escopado; mutacoes e leitura de terceiros '
  'exigem DIRECT_REPORTS/DESCENDANTS). Excecao normativa: leitura SELF-comunicada '
  'segue a regra especifica do dominio (§8 linha 2/D7). '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 4) `observacao_listar_por_escopo`: o SCOPE do escopo pedido passa a decidir
-- ----------------------------------------------------------------------------
-- Reescrita por `create or replace`, mantendo integralmente o comportamento da
-- P2 (allowlist fechada; SELF = somente comunicado e nao excluido; gestao =
-- nao excluidas dos alvos resolvidos) e acrescentando o ENFORCEMENT DO SCOPE:
--   - escopo SELF  -> regra especifica do dominio (sem scope de gestao);
--   - escopo de gestao (DIRECT_REPORTS/DESCENDANTS) -> exige grant com scope
--     DIRECT_REPORTS ou DESCENDANTS (senao DENY).
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

  perform public.f5_11_exigir_autorizacao_observacao(
    'LISTAR_ESCOPO', v_ator, v_org, null, null);

  -- (P3/D15) SCOPE: a listagem de GESTAO exige grant com scope de gestao; a
  -- listagem SELF permanece pela regra especifica do dominio (§8 linha 2).
  if v_escopo <> 'SELF' then
    if not public.f5_11_ator_tem_escopo_observacao(
             v_ator, v_org, 'observation.read',
             array['DIRECT_REPORTS', 'DESCENDANTS']) then
      raise exception
        'F5_11_FORBIDDEN: scope de gestao (DIRECT_REPORTS/DESCENDANTS) ausente para listar observacoes no escopo %',
        v_escopo;
    end if;
  end if;

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
  'F5-11 P2 (reescrito na P3): leitura por ESCOPO com `observation.read` e '
  'allowlist FECHADA (SELF, DIRECT_REPORTS, DESCENDANTS). SELF devolve somente o '
  'comunicado e nao excluido (regra especifica do dominio); os escopos de GESTAO '
  'exigem, desde a P3/D15, grant com SCOPE DIRECT_REPORTS/DESCENDANTS (o scope '
  'participa do enforcement real, cumulativo com a capability e com a relacao '
  'resolvida por `resolver_alvos_escopo`). Nenhum privilegio de cliente e criado. '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 5) Guarda final FAIL-CLOSED da P3
-- ----------------------------------------------------------------------------
do $$
declare
  v_falhas   text[] := array[]::text[];
  v_role     uuid;
  v_fn       text;
  v_tab      text;
  v_rec      record;
  v_def      text;
  v_n        integer;
begin
  -- (a) O perfil de sistema existe, ativo, sem organizacao, com EXATAMENTE 4
  --     capabilities, todas de observacao, e nenhuma observation.* em outra role
  --     de sistema (admin/metas_* intactas).
  select id into v_role
    from public.access_roles
   where name = 'observacoes_gestor' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    v_falhas := v_falhas || 'perfil de sistema observacoes_gestor ausente/inativo/com organizacao';
  else
    select count(*) into v_n from public.access_role_capabilities
     where access_role_id = v_role;
    if v_n <> 4 then
      v_falhas := v_falhas || format('observacoes_gestor com %s capabilities (esperado 4)', v_n);
    end if;
    select count(*) into v_n
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_role
       and c.code in ('observation.read', 'observation.create',
                      'observation.edit', 'observation.delete');
    if v_n <> 4 then
      v_falhas := v_falhas || format('observacoes_gestor com %s das 4 capabilities canonicas', v_n);
    end if;
  end if;

  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 4 then
    v_falhas := v_falhas || format('%s concessao(oes) de observation.* no catalogo (esperado 4, todas em observacoes_gestor)', v_n);
  end if;

  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
     and c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || 'admin com observation.* (F4-01 D18 / D15 violados)';
  end if;
  if (select count(*) from public.access_role_capabilities
       where access_role_id = 'c0000000-0000-4000-8000-0000000000f1') <> 9 then
    v_falhas := v_falhas || 'bundle admin mudou de tamanho';
  end if;

  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and r.name in ('metas_dono', 'metas_aprovador')
       and c.code like 'observation.%'
  ) then
    v_falhas := v_falhas || 'metas_dono/metas_aprovador receberam observation.*';
  end if;
  foreach v_fn in array array['metas_dono', 'metas_aprovador'] loop
    if (select count(*) from public.access_role_capabilities m
          join public.access_roles r on r.id = m.access_role_id
         where r.name = v_fn and r.is_system = true) <> 2 then
      v_falhas := v_falhas || (v_fn || ' deixou de ter exatamente 2 capabilities de metas');
    end if;
  end loop;

  -- (b) `observation.write` continua deprecada e NAO concedida por role.
  if not exists (
    select 1 from public.capabilities where code = 'observation.write' and deprecated = true
  ) then
    v_falhas := v_falhas || 'observation.write deixou de estar deprecada';
  end if;
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where c.code = 'observation.write'
  ) then
    v_falhas := v_falhas || 'observation.write concedida a alguma role (deprecada nao transita por role)';
  end if;

  -- (c) Catalogo INTACTO e nenhuma capability nova/tocada.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo com %s codigos (esperado 31)', v_n);
  end if;

  -- (d) O ENFORCEMENT do scope esta REALMENTE no codigo: o gate e a RPC de
  --     listagem chamam o helper escopado e o resolver escopado e citam os
  --     escopos de gestao. Nada de "scope declarativo".
  foreach v_fn in array array[
    'f5_11_ator_tem_escopo_observacao(uuid, uuid, text, text[])',
    'f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid)',
    'observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)'] loop
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
  end loop;

  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.f5_11_ator_tem_escopo_observacao(uuid, uuid, text, text[])');
  if v_def is null or position('resolver_capabilities_escopos_efetivas' in v_def) = 0 then
    v_falhas := v_falhas || 'helper de scope nao consulta o resolver ESCOPADO soberano';
  end if;

  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid)');
  if v_def is null
     or position('f5_11_ator_tem_escopo_observacao' in v_def) = 0
     or position('direct_reports' in v_def) = 0
     or position('descendants' in v_def) = 0 then
    v_falhas := v_falhas || 'gate nao exige o SCOPE de gestao (DIRECT_REPORTS/DESCENDANTS)';
  end if;

  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)');
  if v_def is null or position('f5_11_ator_tem_escopo_observacao' in v_def) = 0 then
    v_falhas := v_falhas || 'RPC de listagem nao exige o SCOPE de gestao';
  end if;

  -- (e) NENHUMA policy nova, NENHUM privilegio de cliente, D4/D6/D9 intactos.
  foreach v_tab in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = v_tab
    ) then
      v_falhas := v_falhas || ('policy criada em ' || v_tab || ' (o RLS da P3 e o DENY-BY-DEFAULT da P1)');
    end if;
    if has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'DELETE') then
      v_falhas := v_falhas || ('privilegio de cliente aberto em ' || v_tab);
    end if;
  end loop;
  foreach v_fn in array array[
    'enforce_evaluation_observations_imutaveis()',
    'enforce_evaluation_observation_events_append_only()',
    'f5_11_validar_coerencia_identidade()',
    'f5_11_validar_coerencia_identidade_evento()'] loop
    if to_regprocedure('public.' || v_fn) is null then
      v_falhas := v_falhas || ('funcao de invariante ausente: ' || v_fn);
    end if;
  end loop;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] F5-11 P3: guarda final: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-11 P3: guarda final OK (observacoes_gestor com EXATAMENTE as 4 capabilities; ZERO observation.* em admin/metas_*; observation.write deprecada e nao concedida; catalogo 31; SCOPE enforced no gate e na listagem via resolver escopado; nenhuma policy/privilegio novo; D4/D6/D9 e P1.1 intactos; D15 RESOLVIDA — a concessao existe e e decidivel em producao)';
end $$;
