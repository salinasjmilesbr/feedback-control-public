-- ============================================================================
-- F5-07 (Etapa 5): RPCs transacionais de colaborador e estrutura (D13/D19/D26)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-07-desenho-tecnico.md (D1-D20 FECHADAS) e espinha de
-- interfaces congelada (.git/F5-07_SPINE.md, §1.5).
--
-- Padrao comum a TODAS as mutacoes (espinha §0 e §1.5):
--   1. `security invoker` + `set search_path = public`; ZERO SECURITY DEFINER;
--   2. revalida o ator (`colaborador_ator_valido`) e DERIVA/CONFIRMA o tenant
--      pelo RECURSO carregado — o `organization_id` do payload e INTENCAO;
--   3. idempotencia por `(organization_id, operation_id)` + `payload_hash`
--      (md5 do jsonb normalizado da INTENCAO): mesmo hash devolve o mesmo
--      resultado; hash diferente => `F5_07_CONFLICT:`;
--   4. `p_expected_version` obrigatorio nas operacoes que alteram linha
--      existente (concorrencia otimista, D13) — auferido sob `for update`;
--   5. vigencia sempre FECHAR-E-ABRIR (nunca UPDATE destrutivo sobre periodo
--      fechado, nunca DELETE — I5);
--   6. evento append-only gravado NA MESMA TRANSACAO (D8/D26);
--   7. devolve o resultado (entidade/versao) e nao decide autorizacao: a
--      decisao e do Policy Engine (plano funcional) ou do plano administrativo
--      (D19), na fronteira confiavel, ANTES da chamada (I9).
--
-- Erros publicos com prefixo estavel (traduzidos pela Edge):
--   F5_07_INVALID_INPUT: / F5_07_NOT_FOUND: / F5_07_CONFLICT: / F5_07_FORBIDDEN:
--
-- Nenhum CRUD de `organizational_units`, `organizational_positions`,
-- `job_roles` (exceto `code`), `seniority_levels` (exceto o bootstrap de
-- catalogo D16) ou `collegiate_configurations`: isso e F5-08 (D20).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) `colaborador_criar` — identidade + pessoa + identificador + status (D2/D3/D6)
-- ----------------------------------------------------------------------------
create or replace function public.colaborador_criar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_full_name text,
  p_email text,
  p_matricula text,
  p_admission_date date,
  p_status_inicial text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org        uuid := p_organization_id;
  v_full_name  text := btrim(coalesce(p_full_name, ''));
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_matricula  text := btrim(coalesce(p_matricula, ''));
  v_status     text := coalesce(nullif(btrim(coalesce(p_status_inicial, '')), ''), 'active');
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_id         uuid;
  -- Inicio da vigencia do vinculo: a admissao DECLARADA quando informada
  -- (ancorada em UTC para nao depender do TimeZone da sessao), senao `now()`.
  -- Identificador, periodo de status e evento usam o MESMO instante.
  v_inicio     timestamptz := coalesce(
                                (p_admission_date::timestamp at time zone 'UTC'),
                                now());
begin
  -- (1) Forma do payload: nada aqui e autoridade.
  if p_operation_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id obrigatorio (idempotencia)';
  end if;
  if v_full_name = '' then
    raise exception 'F5_07_INVALID_INPUT: full_name obrigatorio';
  end if;
  if v_email = '' or position('@' in v_email) <= 1 then
    raise exception 'F5_07_INVALID_INPUT: email invalido';
  end if;
  if v_matricula = '' then
    raise exception 'F5_07_INVALID_INPUT: matricula obrigatoria';
  end if;
  if v_status not in ('active', 'leave') then
    raise exception 'F5_07_INVALID_INPUT: status inicial deve ser active ou leave';
  end if;

  -- (2) Ator revalidado no BANCO (service_role executa, nunca decide — I9/D27).
  -- Aqui o tenant vem do payload e e aceito SOMENTE porque foi revalidado
  -- contra a membership ativa do ator (I2).
  if not public.colaborador_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  -- (3) Idempotencia (D13).
  v_hash := md5(jsonb_build_object(
    'operacao', 'colaborador_criar',
    'organization_id', v_org,
    'full_name', v_full_name,
    'email', v_email,
    'matricula', v_matricula,
    'admission_date', p_admission_date,
    'status_inicial', v_status
  )::text);

  select e.payload_hash, e.result_entity_id
    into v_evento
    from public.collaborator_events e
   where e.organization_id = v_org
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  -- (4) Regras de negocio preservadas do baseline (§8.3): matricula unica na
  -- organizacao em QUALQUER vigencia e e-mail unico (case-insensitive).
  if exists (
    select 1
      from public.collaborator_identifiers i
     where i.organization_id = v_org
       and i.business_code = v_matricula
  ) then
    raise exception 'F5_07_CONFLICT: matricula ja utilizada na organizacao';
  end if;

  if exists (
    select 1
      from public.collaborators c
     where c.organization_id = v_org
       and lower(c.email) = v_email
  ) then
    raise exception 'F5_07_CONFLICT: email ja utilizado na organizacao';
  end if;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_07_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- (5) Identidade + pessoa (D3) + identificador ABERTO + status inicial (D6).
  insert into public.collaborators (organization_id, full_name, email, admission_date)
  values (v_org, v_full_name, v_email, p_admission_date)
  returning id into v_id;

  insert into public.collaborator_identifiers
    (collaborator_id, organization_id, business_code, valid_from)
  values (v_id, v_org, v_matricula, v_inicio);

  insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
  values (v_id, v_status, v_inicio);

  -- (6) Evento append-only na MESMA transacao (D8/D26).
  insert into public.collaborator_events (
    organization_id, collaborator_id, event_type, effective_date, cycle_scope,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, v_id, 'ADMISSAO', v_inicio, 'CICLO_ATUAL_E_POSTERIORES',
    'Admissao de colaborador', null,
    jsonb_build_object(
      'full_name', v_full_name,
      'email', v_email,
      'matricula', v_matricula,
      'admission_date', p_admission_date,
      'status', v_status),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_id;
end;
$$;

comment on function public.colaborador_criar(uuid, uuid, uuid, text, text, text, date, text) is
  'F5-07 D2/D3/D6/D13: cria colaborador (identidade UUID), identificador ABERTO '
  'e periodo de status inicial (active por padrao; leave aceito), gravando o '
  'evento ADMISSAO com autoria soberana na MESMA transacao. Nao cria estrutura '
  '(ocupacao e operacao propria). Idempotente por operation_id + payload_hash. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 2) `colaborador_editar` — somente dados de pessoa, com versao (D3/D13)
-- ----------------------------------------------------------------------------
create or replace function public.colaborador_editar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_full_name text,
  p_email text,
  p_admission_date date,
  p_expected_version integer
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid;
  v_novo_nome   text;
  v_novo_email  text;
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_atual       record;
  v_status      text;
  v_nome        text;
  v_email       text;
  v_admissao    date;
  v_versao      integer;
begin
  if p_operation_id is null or p_collaborator_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id e collaborator_id obrigatorios';
  end if;
  if p_expected_version is null then
    raise exception 'F5_07_INVALID_INPUT: expected_version obrigatorio (concorrencia otimista)';
  end if;
  if p_full_name is not null and btrim(p_full_name) = '' then
    raise exception 'F5_07_INVALID_INPUT: full_name vazio';
  end if;
  if p_email is not null and (btrim(p_email) = '' or position('@' in btrim(p_email)) <= 1) then
    raise exception 'F5_07_INVALID_INPUT: email invalido';
  end if;

  v_novo_nome  := case when p_full_name is null then null else btrim(p_full_name) end;
  v_novo_email := case when p_email is null then null else lower(btrim(p_email)) end;

  v_hash := md5(jsonb_build_object(
    'operacao', 'colaborador_editar',
    'organization_id', p_organization_id,
    'collaborator_id', p_collaborator_id,
    'full_name', v_novo_nome,
    'email', v_novo_email,
    'admission_date', p_admission_date,
    'expected_version', p_expected_version
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  -- Idempotencia ANTES da comparacao de versao: o retry do MESMO pedido devolve
  -- o MESMO resultado (a versao devolvida e a registrada no evento).
  select e.payload_hash, e.after_value
    into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value ->> 'version')::integer, 0);
  end if;

  -- Tenant DERIVADO do RECURSO (nunca do parametro) e lock otimista.
  select c.organization_id, c.version, c.full_name, c.email, c.admission_date
    into v_atual
    from public.collaborators c
   where c.id = p_collaborator_id
     for update;
  if not found then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  v_org := v_atual.organization_id;
  if v_org is distinct from p_organization_id then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  if v_atual.version <> p_expected_version then
    raise exception 'F5_07_CONFLICT: versao divergente (esperado %, atual %)',
      p_expected_version, v_atual.version;
  end if;

  -- Predicado de dominio da operacao (§9.4): editar pessoa exige status
  -- vigente active ou leave (inactive/ausente => fail-closed).
  select sp.status into v_status
    from public.collaborator_status_periods sp
   where sp.collaborator_id = p_collaborator_id
     and sp.valid_from <= now()
     and (sp.valid_to is null or sp.valid_to > now())
   order by sp.valid_from desc, sp.id
   limit 1;
  if v_status is null then
    raise exception 'F5_07_CONFLICT: colaborador sem status vigente (fail-closed)';
  end if;
  if v_status not in ('active', 'leave') then
    raise exception 'F5_07_CONFLICT: edicao de dados de pessoa exige status vigente active ou leave';
  end if;

  v_nome     := coalesce(v_novo_nome, v_atual.full_name);
  v_email    := coalesce(v_novo_email, v_atual.email);
  v_admissao := coalesce(p_admission_date, v_atual.admission_date);

  if v_email is distinct from v_atual.email then
    if exists (
      select 1
        from public.collaborators c
       where c.organization_id = v_org
         and lower(c.email) = v_email
         and c.id <> p_collaborator_id
    ) then
      raise exception 'F5_07_CONFLICT: email ja utilizado na organizacao';
    end if;
  end if;

  update public.collaborators
     set full_name = v_nome,
         email = v_email,
         admission_date = v_admissao,
         version = version + 1
   where id = p_collaborator_id
  returning version into v_versao;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, event_type, effective_date, cycle_scope,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_collaborator_id, 'DADOS_PESSOAIS_ALTERADOS', now(),
    'CICLO_ATUAL_E_POSTERIORES', 'Alteracao de dados de pessoa',
    jsonb_build_object(
      'full_name', v_atual.full_name,
      'email', v_atual.email,
      'admission_date', v_atual.admission_date,
      'version', v_atual.version),
    jsonb_build_object(
      'full_name', v_nome,
      'email', v_email,
      'admission_date', v_admissao,
      'version', v_versao),
    v_hash, p_collaborator_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_versao;
end;
$$;

comment on function public.colaborador_editar(uuid, uuid, uuid, uuid, text, text, date, integer) is
  'F5-07 D3/D13: altera SOMENTE dados de pessoa (full_name/email/admission_date — '
  'matricula, status e estrutura tem operacao propria), exige expected_version e '
  'status vigente active/leave, incrementa version e grava '
  'DADOS_PESSOAIS_ALTERADOS na MESMA transacao. Devolve a nova version; retry '
  'idempotente devolve a mesma version. SECURITY INVOKER; EXECUTE somente '
  'service_role.';

-- ----------------------------------------------------------------------------
-- 3) `colaborador_identificador_definir` — fecha a linha aberta e abre a nova (I5)
-- ----------------------------------------------------------------------------
create or replace function public.colaborador_identificador_definir(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_nova_matricula text,
  p_vigencia timestamptz,
  p_motivo text,
  p_expected_version integer
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org         uuid;
  v_matricula   text := btrim(coalesce(p_nova_matricula, ''));
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_atual       record;
  v_anterior    record;
  v_versao      integer;
begin
  if p_operation_id is null or p_collaborator_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id e collaborator_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if p_expected_version is null then
    raise exception 'F5_07_INVALID_INPUT: expected_version obrigatorio (concorrencia otimista)';
  end if;
  if v_matricula = '' then
    raise exception 'F5_07_INVALID_INPUT: nova_matricula obrigatoria';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'colaborador_identificador_definir',
    'organization_id', p_organization_id,
    'collaborator_id', p_collaborator_id,
    'nova_matricula', v_matricula,
    'vigencia', p_vigencia,
    'motivo', v_motivo,
    'expected_version', p_expected_version
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash, e.after_value
    into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value ->> 'version')::integer, 0);
  end if;

  select c.organization_id, c.version
    into v_atual
    from public.collaborators c
   where c.id = p_collaborator_id
     for update;
  if not found then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  v_org := v_atual.organization_id;
  if v_org is distinct from p_organization_id then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  if v_atual.version <> p_expected_version then
    raise exception 'F5_07_CONFLICT: versao divergente (esperado %, atual %)',
      p_expected_version, v_atual.version;
  end if;

  -- Sem reutilizacao de codigo dentro da organizacao, em QUALQUER vigencia
  -- (regra do banco preservada: uq_collaborator_identifiers_organization_code).
  if exists (
    select 1
      from public.collaborator_identifiers i
     where i.organization_id = v_org
       and i.business_code = v_matricula
  ) then
    raise exception 'F5_07_CONFLICT: matricula ja utilizada na organizacao (codigo nunca e reutilizado)';
  end if;

  select i.id, i.business_code, i.valid_from
    into v_anterior
    from public.collaborator_identifiers i
   where i.collaborator_id = p_collaborator_id
     and i.valid_to is null
   order by i.valid_from desc, i.id
   limit 1;

  if found then
    if p_vigencia <= v_anterior.valid_from then
      raise exception 'F5_07_CONFLICT: vigencia deve ser posterior ao inicio do identificador vigente';
    end if;

    update public.collaborator_identifiers
       set valid_to = p_vigencia,
           version = version + 1
     where id = v_anterior.id;
  end if;

  insert into public.collaborator_identifiers
    (collaborator_id, organization_id, business_code, valid_from)
  values (p_collaborator_id, v_org, v_matricula, p_vigencia);

  update public.collaborators
     set version = version + 1
   where id = p_collaborator_id
  returning version into v_versao;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';

  -- Evento UNICO com o par (encerrado + definido) em before/after — a espinha
  -- admite explicitamente esta forma (evita dois eventos para um operation_id,
  -- que e chave de idempotencia unica por organizacao).
  insert into public.collaborator_events (
    organization_id, collaborator_id, event_type, effective_date, cycle_scope,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_collaborator_id, 'IDENTIFICADOR_DEFINIDO', p_vigencia,
    'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    case when v_anterior.id is null then null
         else jsonb_build_object(
           'matricula', v_anterior.business_code,
           'valid_from', v_anterior.valid_from,
           'valid_to', p_vigencia,
           'encerrado', true) end,
    jsonb_build_object(
      'matricula', v_matricula,
      'valid_from', p_vigencia,
      'version', v_versao),
    v_hash, p_collaborator_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_versao;
end;
$$;

comment on function public.colaborador_identificador_definir(uuid, uuid, uuid, uuid, text, timestamptz, text, integer) is
  'F5-07 I5/D13: troca a matricula FECHANDO a linha aberta (valid_to = vigencia) '
  'e ABRINDO nova linha — nunca UPDATE destrutivo do passado, nunca reuso de '
  'codigo na organizacao. Grava IDENTIFICADOR_DEFINIDO com o par (encerrado + '
  'definido) em before/after, incrementa version e devolve a nova version. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 4) `colaborador_status_alterar` — transicoes fechar-e-abrir (D6/D13)
-- ----------------------------------------------------------------------------
create or replace function public.colaborador_status_alterar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_novo_status text,
  p_vigencia timestamptz,
  p_motivo text,
  p_cycle_scope text,
  p_reference_cycle_id uuid,
  p_expected_version integer
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org          uuid;
  v_novo         text := lower(btrim(coalesce(p_novo_status, '')));
  v_motivo       text := btrim(coalesce(p_motivo, ''));
  v_scope        text := coalesce(nullif(btrim(coalesce(p_cycle_scope, '')), ''),
                                  'CICLO_ATUAL_E_POSTERIORES');
  v_hash         text;
  v_evento       record;
  v_membership   uuid;
  v_atual        record;
  v_periodo      record;
  v_pend_ocup    text;
  v_pend_report  text;
  v_pend_resp    text;
  v_versao       integer;
begin
  if p_operation_id is null or p_collaborator_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id e collaborator_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if p_expected_version is null then
    raise exception 'F5_07_INVALID_INPUT: expected_version obrigatorio (concorrencia otimista)';
  end if;
  if v_novo not in ('active', 'leave', 'inactive') then
    raise exception 'F5_07_INVALID_INPUT: novo_status invalido (active, leave ou inactive)';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;
  if v_scope not in ('CICLO_ATUAL_E_POSTERIORES', 'SOMENTE_CICLOS_POSTERIORES') then
    raise exception 'F5_07_INVALID_INPUT: cycle_scope invalido';
  end if;
  if p_reference_cycle_id is not null then
    if not exists (
      select 1
        from public.evaluation_cycles ec
       where ec.id = p_reference_cycle_id
         and ec.organization_id = p_organization_id
    ) then
      raise exception 'F5_07_NOT_FOUND: ciclo de referencia inexistente ou de outro tenant';
    end if;
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'colaborador_status_alterar',
    'organization_id', p_organization_id,
    'collaborator_id', p_collaborator_id,
    'novo_status', v_novo,
    'vigencia', p_vigencia,
    'motivo', v_motivo,
    'cycle_scope', v_scope,
    'reference_cycle_id', p_reference_cycle_id,
    'expected_version', p_expected_version
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash, e.after_value
    into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return coalesce((v_evento.after_value ->> 'version')::integer, 0);
  end if;

  select c.organization_id, c.version
    into v_atual
    from public.collaborators c
   where c.id = p_collaborator_id
     for update;
  if not found then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  v_org := v_atual.organization_id;
  if v_org is distinct from p_organization_id then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  if v_atual.version <> p_expected_version then
    raise exception 'F5_07_CONFLICT: versao divergente (esperado %, atual %)',
      p_expected_version, v_atual.version;
  end if;

  -- Periodo VIGENTE = linha aberta (valid_to is null) — a exclusion da F3-01
  -- garante no maximo um. Ausencia => fail-closed.
  select sp.id, sp.status, sp.valid_from
    into v_periodo
    from public.collaborator_status_periods sp
   where sp.collaborator_id = p_collaborator_id
     and sp.valid_to is null
   order by sp.valid_from desc, sp.id
   limit 1;
  if not found then
    raise exception 'F5_07_CONFLICT: colaborador sem periodo de status vigente (fail-closed)';
  end if;

  if p_vigencia <= v_periodo.valid_from then
    raise exception 'F5_07_CONFLICT: vigencia deve ser posterior ao inicio do periodo de status vigente';
  end if;

  -- Transicoes permitidas na F5-07: active->leave, leave->active,
  -- active->inactive, leave->inactive. Readmissao (inactive->*) esta fora de
  -- escopo (§8.3).
  if not (
    (v_periodo.status = 'active' and v_novo in ('leave', 'inactive'))
    or (v_periodo.status = 'leave' and v_novo in ('active', 'inactive'))
  ) then
    raise exception 'F5_07_CONFLICT: transicao de status invalida (% -> %)',
      v_periodo.status, v_novo;
  end if;

  -- D6: `inactive` exige estrutura ENCERRADA explicitamente — a RPC devolve a
  -- lista do que falta encerrar e NAO fecha nada silenciosamente.
  if v_novo = 'inactive' then
    select
      (select string_agg(o.id::text, ', ' order by o.id)
         from public.occupations o
        where o.collaborator_id = p_collaborator_id
          and o.organization_id = v_org
          and (o.valid_to is null or o.valid_to > p_vigencia)),
      (select string_agg(rl.id::text, ', ' order by rl.id)
         from public.position_reporting_lines rl
        where rl.organization_id = v_org
          and (rl.valid_to is null or rl.valid_to > p_vigencia)
          and rl.subordinate_position_id in (
                select o.organizational_position_id
                  from public.occupations o
                 where o.collaborator_id = p_collaborator_id
                   and o.organization_id = v_org
                   and (o.valid_to is null or o.valid_to > p_vigencia))),
      (select string_agg(tr.id::text, ', ' order by tr.id)
         from public.temporary_responsibilities tr
        where tr.organization_id = v_org
          and tr.substitute_collaborator_id = p_collaborator_id
          and tr.valid_to > p_vigencia)
      into v_pend_ocup, v_pend_report, v_pend_resp;

    if v_pend_ocup is not null or v_pend_report is not null or v_pend_resp is not null then
      raise exception 'F5_07_CONFLICT: desligamento exige estrutura encerrada '
        '(ocupacao: %; reporting_line: %; responsabilidade: %)',
        coalesce(v_pend_ocup, '-'), coalesce(v_pend_report, '-'), coalesce(v_pend_resp, '-');
    end if;
  end if;

  -- Fechar-e-abrir (I5): nunca UPDATE destrutivo do passado.
  update public.collaborator_status_periods
     set valid_to = p_vigencia,
         version = version + 1
   where id = v_periodo.id;

  insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
  values (p_collaborator_id, v_novo, p_vigencia);

  update public.collaborators
     set version = version + 1
   where id = p_collaborator_id
  returning version into v_versao;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, event_type, effective_date, cycle_scope,
    reference_cycle_id, reason, before_value, after_value, payload_hash,
    result_entity_id, actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_collaborator_id, 'STATUS_ALTERADO', p_vigencia, v_scope,
    p_reference_cycle_id, v_motivo,
    jsonb_build_object('status', v_periodo.status, 'valid_from', v_periodo.valid_from,
                       'valid_to', p_vigencia),
    jsonb_build_object('status', v_novo, 'valid_from', p_vigencia, 'version', v_versao),
    v_hash, p_collaborator_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_versao;
end;
$$;

comment on function public.colaborador_status_alterar(uuid, uuid, uuid, uuid, text, timestamptz, text, text, uuid, integer) is
  'F5-07 D6/D13: transiciona status por FECHAR-E-ABRIR vigencia (active->leave, '
  'leave->active, active->inactive, leave->inactive). `inactive` exige estrutura '
  'encerrada: devolve F5_07_CONFLICT listando ocupacao/reporting line/'
  'responsabilidade pendentes e NAO fecha nada silenciosamente. Grava '
  'STATUS_ALTERADO com cycle_scope/ciclo de referencia e devolve a nova version. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 5) `estrutura_ocupacao_definir` — fecha a ocupacao vigente e abre a nova (D7)
-- ----------------------------------------------------------------------------
create or replace function public.estrutura_ocupacao_definir(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_position_id uuid,
  p_vigencia timestamptz,
  p_motivo text,
  p_cycle_scope text,
  p_reference_cycle_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org           uuid;
  v_motivo        text := btrim(coalesce(p_motivo, ''));
  v_scope         text := coalesce(nullif(btrim(coalesce(p_cycle_scope, '')), ''),
                                   'CICLO_ATUAL_E_POSTERIORES');
  v_hash          text;
  v_evento        record;
  v_membership    uuid;
  v_collab        record;
  v_status        text;
  v_fechadas_qtd  int;
  v_fechadas_list jsonb;
  v_fech_pos      uuid;
  v_id            uuid;
  v_op_encerr     uuid;
  v_agora         timestamptz := now();
begin
  if p_operation_id is null or p_collaborator_id is null or p_position_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id, collaborator_id e position_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;
  if v_scope not in ('CICLO_ATUAL_E_POSTERIORES', 'SOMENTE_CICLOS_POSTERIORES') then
    raise exception 'F5_07_INVALID_INPUT: cycle_scope invalido';
  end if;
  if p_reference_cycle_id is not null then
    if not exists (
      select 1
        from public.evaluation_cycles ec
       where ec.id = p_reference_cycle_id
         and ec.organization_id = p_organization_id
    ) then
      raise exception 'F5_07_NOT_FOUND: ciclo de referencia inexistente ou de outro tenant';
    end if;
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_ocupacao_definir',
    'organization_id', p_organization_id,
    'collaborator_id', p_collaborator_id,
    'position_id', p_position_id,
    'vigencia', p_vigencia,
    'motivo', v_motivo,
    'cycle_scope', v_scope,
    'reference_cycle_id', p_reference_cycle_id
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id
    into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select c.organization_id into v_collab
    from public.collaborators c
   where c.id = p_collaborator_id
     for update;
  if not found then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;
  v_org := v_collab.organization_id;
  if v_org is distinct from p_organization_id then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  if not exists (
    select 1
      from public.organizational_positions p
     where p.id = p_position_id
       and p.organization_id = v_org
  ) then
    raise exception 'F5_07_NOT_FOUND: posicao inexistente ou de outro tenant';
  end if;

  -- Predicado de dominio (§9.4): colaborador desligado nao recebe alocacao.
  select sp.status into v_status
    from public.collaborator_status_periods sp
   where sp.collaborator_id = p_collaborator_id
     and sp.valid_from <= v_agora
     and (sp.valid_to is null or sp.valid_to > v_agora)
   order by sp.valid_from desc, sp.id
   limit 1;
  if v_status = 'inactive' then
    raise exception 'F5_07_CONFLICT: colaborador inativo nao pode receber ocupacao';
  end if;

  -- Lock de transacao por organizacao (mesmo padrao da F3-04): serializa
  -- leitura-antes-de-escrever da estrutura do tenant.
  perform pg_advisory_xact_lock(hashtext('f5_07_estrutura:' || v_org::text));

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'occupation_id', o.id,
           'position_id', o.organizational_position_id,
           'valid_from', o.valid_from) order by o.valid_from, o.id), '[]'::jsonb),
         (array_agg(o.organizational_position_id order by o.valid_from, o.id))[1]
    into v_fechadas_qtd, v_fechadas_list, v_fech_pos
    from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from < p_vigencia
     and (o.valid_to is null or o.valid_to > p_vigencia);

  update public.occupations o
     set valid_to = p_vigencia,
         version = version + 1
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from < p_vigencia
     and (o.valid_to is null or o.valid_to > p_vigencia);

  -- A posicao alvo precisa estar VAGA na vigencia (a exclusion constraint e a
  -- ultima barreira; aqui o erro sai com codigo publico estavel).
  if exists (
    select 1
      from public.occupations o
     where o.organizational_position_id = p_position_id
       and o.valid_from <= p_vigencia
       and (o.valid_to is null or o.valid_to > p_vigencia)
  ) then
    raise exception 'F5_07_CONFLICT: posicao ja possui ocupante vigente nessa data (encerre antes)';
  end if;

  insert into public.occupations
    (organization_id, collaborator_id, organizational_position_id, reason, valid_from)
  values (v_org, p_collaborator_id, p_position_id, v_motivo, p_vigencia)
  returning id into v_id;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reference_cycle_id, reason, before_value, after_value,
    payload_hash, result_entity_id, actor_user_profile_id, actor_membership_id,
    operation_id
  ) values (
    v_org, p_collaborator_id, p_position_id, 'OCUPACAO_INICIADA', p_vigencia,
    v_scope, p_reference_cycle_id, v_motivo,
    jsonb_build_object('ocupacoes_encerradas', v_fechadas_list),
    jsonb_build_object('occupation_id', v_id, 'position_id', p_position_id,
                       'valid_from', p_vigencia),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  -- Encerramento registrado na MESMA transacao. A chave de idempotencia e
  -- `(organization_id, operation_id)` (unica), portanto o evento secundario usa
  -- um operation_id DERIVADO deterministico do principal — repetir o pedido
  -- devolve o resultado sem gravar nada novo (o lote e sempre o mesmo par).
  if v_fechadas_qtd > 0 then
    v_op_encerr := md5(p_operation_id::text || ':OCUPACAO_ENCERRADA')::uuid;

    insert into public.collaborator_events (
      organization_id, collaborator_id, position_id, event_type, effective_date,
      cycle_scope, reference_cycle_id, reason, before_value, after_value,
      payload_hash, result_entity_id, actor_user_profile_id, actor_membership_id,
      operation_id
    ) values (
      v_org, p_collaborator_id,
      case when v_fechadas_qtd = 1 then v_fech_pos else null end,
      'OCUPACAO_ENCERRADA', p_vigencia, v_scope, p_reference_cycle_id, v_motivo,
      jsonb_build_object('ocupacoes', v_fechadas_list),
      jsonb_build_object('valid_to', p_vigencia),
      v_hash,
      case when v_fechadas_qtd = 1 then v_fech_pos else null end,
      p_actor_user_profile_id, v_membership, v_op_encerr
    );
  end if;

  return v_id;
end;
$$;

comment on function public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid) is
  'F5-07 D7: aloca o colaborador em uma posicao FECHANDO as ocupacoes vigentes '
  'na data e ABRINDO a nova, com eventos OCUPACAO_INICIADA (e '
  'OCUPACAO_ENCERRADA quando fechou) na MESMA transacao. Tenant derivado do '
  'recurso, ator revalidado, lock por organizacao, posicao alvo precisa estar '
  'vaga. SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 6) `estrutura_ocupacao_encerrar` — fecha a ocupacao vigente (D7)
-- ----------------------------------------------------------------------------
create or replace function public.estrutura_ocupacao_encerrar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_collaborator_id uuid,
  p_vigencia timestamptz,
  p_motivo text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org        uuid;
  v_motivo     text := btrim(coalesce(p_motivo, ''));
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_collab     record;
  v_qtd        int;
  v_lista      jsonb;
  v_pos        uuid;
begin
  if p_operation_id is null or p_collaborator_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id e collaborator_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_ocupacao_encerrar',
    'organization_id', p_organization_id,
    'collaborator_id', p_collaborator_id,
    'vigencia', p_vigencia,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return;
  end if;

  select c.organization_id into v_collab
    from public.collaborators c
   where c.id = p_collaborator_id
     for update;
  if not found then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;
  v_org := v_collab.organization_id;
  if v_org is distinct from p_organization_id then
    raise exception 'F5_07_NOT_FOUND: colaborador inexistente ou de outro tenant';
  end if;

  perform pg_advisory_xact_lock(hashtext('f5_07_estrutura:' || v_org::text));

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'occupation_id', o.id,
           'position_id', o.organizational_position_id,
           'valid_from', o.valid_from) order by o.valid_from, o.id), '[]'::jsonb),
         (array_agg(o.organizational_position_id order by o.valid_from, o.id))[1]
    into v_qtd, v_lista, v_pos
    from public.occupations o
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from < p_vigencia
     and (o.valid_to is null or o.valid_to > p_vigencia);

  if v_qtd = 0 then
    raise exception 'F5_07_NOT_FOUND: nao ha ocupacao vigente para encerrar nessa data';
  end if;

  update public.occupations o
     set valid_to = p_vigencia,
         version = version + 1
   where o.collaborator_id = p_collaborator_id
     and o.organization_id = v_org
     and o.valid_from < p_vigencia
     and (o.valid_to is null or o.valid_to > p_vigencia);

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reason, before_value, after_value, payload_hash,
    result_entity_id, actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    v_org, p_collaborator_id, case when v_qtd = 1 then v_pos else null end,
    'OCUPACAO_ENCERRADA', p_vigencia, 'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    jsonb_build_object('ocupacoes', v_lista),
    jsonb_build_object('valid_to', p_vigencia),
    v_hash, case when v_qtd = 1 then v_pos else null end,
    p_actor_user_profile_id, v_membership, p_operation_id
  );
end;
$$;

comment on function public.estrutura_ocupacao_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) is
  'F5-07 D7: encerra a(s) ocupacao(oes) vigente(s) do colaborador na data por '
  'valid_to (nunca DELETE), gravando OCUPACAO_ENCERRADA na MESMA transacao. '
  'Ausencia de ocupacao vigente => F5_07_NOT_FOUND (nunca cria estado). '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 7) `estrutura_reporting_definir` — fecha a linha vigente e abre a nova (D7)
-- ----------------------------------------------------------------------------
create or replace function public.estrutura_reporting_definir(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_subordinate_position_id uuid,
  p_manager_position_id uuid,
  p_vigencia timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_motivo      text := btrim(coalesce(p_motivo, ''));
  v_hash        text;
  v_evento      record;
  v_membership  uuid;
  v_sub_from    timestamptz;
  v_sub_to      timestamptz;
  v_man_from    timestamptz;
  v_man_to      timestamptz;
  v_qtd         int;
  v_lista       jsonb;
  v_id          uuid;
  v_op_encerr   uuid;
begin
  if p_operation_id is null or p_subordinate_position_id is null or p_manager_position_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id, subordinate_position_id e manager_position_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;
  if p_manager_position_id = p_subordinate_position_id then
    raise exception 'F5_07_INVALID_INPUT: auto-reporting proibido';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_reporting_definir',
    'organization_id', p_organization_id,
    'subordinate_position_id', p_subordinate_position_id,
    'manager_position_id', p_manager_position_id,
    'vigencia', p_vigencia,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id
    into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select p.valid_from, p.valid_to
    into v_sub_from, v_sub_to
    from public.organizational_positions p
   where p.id = p_subordinate_position_id
     and p.organization_id = p_organization_id;
  if not found then
    raise exception 'F5_07_NOT_FOUND: posicao subordinada inexistente ou de outro tenant';
  end if;

  select p.valid_from, p.valid_to
    into v_man_from, v_man_to
    from public.organizational_positions p
   where p.id = p_manager_position_id
     and p.organization_id = p_organization_id;
  if not found then
    raise exception 'F5_07_NOT_FOUND: posicao superior inexistente ou de outro tenant';
  end if;

  if p_vigencia < v_sub_from or p_vigencia < v_man_from then
    raise exception 'F5_07_CONFLICT: vigencia anterior a existencia das posicoes';
  end if;
  if v_sub_to is not null or v_man_to is not null then
    raise exception 'F5_07_CONFLICT: reporting line aberta exige posicoes vigentes (nao encerradas)';
  end if;

  perform pg_advisory_xact_lock(hashtext('f5_07_estrutura:' || p_organization_id::text));

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'reporting_line_id', rl.id,
           'manager_position_id', rl.manager_position_id,
           'valid_from', rl.valid_from) order by rl.valid_from, rl.id), '[]'::jsonb)
    into v_qtd, v_lista
    from public.position_reporting_lines rl
   where rl.subordinate_position_id = p_subordinate_position_id
     and rl.organization_id = p_organization_id
     and rl.valid_from < p_vigencia
     and (rl.valid_to is null or rl.valid_to > p_vigencia);

  -- Fechar a linha vigente do subordinado antes de validar ciclo/abrir a nova.
  update public.position_reporting_lines rl
     set valid_to = p_vigencia,
         version = version + 1
   where rl.subordinate_position_id = p_subordinate_position_id
     and rl.organization_id = p_organization_id
     and rl.valid_from < p_vigencia
     and (rl.valid_to is null or rl.valid_to > p_vigencia);

  -- Prevencao de ciclo multi-nivel: mesma semantica do trigger F3-04
  -- (`enforce_position_reporting_lines_no_cycle`, ultima barreira). Aqui o erro
  -- sai com codigo publico estavel.
  if exists (
    with recursive upstream as (
      select rl.manager_position_id as mgr
        from public.position_reporting_lines rl
       where rl.subordinate_position_id = p_manager_position_id
         and rl.valid_from < p_vigencia
         and (rl.valid_to is null or rl.valid_to > p_vigencia)
      union
      select rl.manager_position_id
        from public.position_reporting_lines rl
        join upstream u on rl.subordinate_position_id = u.mgr
       where rl.valid_from < p_vigencia
         and (rl.valid_to is null or rl.valid_to > p_vigencia)
    )
    select 1 from upstream where mgr = p_subordinate_position_id
  ) then
    raise exception 'F5_07_CONFLICT: ciclo hierarquico detectado na reporting line';
  end if;

  insert into public.position_reporting_lines
    (organization_id, subordinate_position_id, manager_position_id, reason, valid_from)
  values (p_organization_id, p_subordinate_position_id, p_manager_position_id,
          v_motivo, p_vigencia)
  returning id into v_id;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, position_id, event_type, effective_date, cycle_scope,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    p_organization_id, p_subordinate_position_id, 'REPORTING_LINE_INICIADA',
    p_vigencia, 'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    jsonb_build_object('linhas_encerradas', v_lista),
    jsonb_build_object('reporting_line_id', v_id,
                       'subordinate_position_id', p_subordinate_position_id,
                       'manager_position_id', p_manager_position_id,
                       'valid_from', p_vigencia),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  if v_qtd > 0 then
    v_op_encerr := md5(p_operation_id::text || ':REPORTING_LINE_ENCERRADA')::uuid;

    insert into public.collaborator_events (
      organization_id, position_id, event_type, effective_date, cycle_scope,
      reason, before_value, after_value, payload_hash, result_entity_id,
      actor_user_profile_id, actor_membership_id, operation_id
    ) values (
      p_organization_id, p_subordinate_position_id, 'REPORTING_LINE_ENCERRADA',
      p_vigencia, 'CICLO_ATUAL_E_POSTERIORES', v_motivo,
      jsonb_build_object('linhas', v_lista),
      jsonb_build_object('valid_to', p_vigencia),
      v_hash, null, p_actor_user_profile_id, v_membership, v_op_encerr
    );
  end if;

  return v_id;
end;
$$;

comment on function public.estrutura_reporting_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text) is
  'F5-07 D7: define a reporting line formal do subordinado FECHANDO a linha '
  'vigente e ABRINDO a nova, com eventos REPORTING_LINE_INICIADA (e '
  'REPORTING_LINE_ENCERRADA quando fechou) na MESMA transacao. Auto-reporting e '
  'ciclo hierarquico sao recusados com codigo publico; lock por organizacao. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 8) `estrutura_reporting_encerrar` — fecha a linha vigente (D7)
-- ----------------------------------------------------------------------------
create or replace function public.estrutura_reporting_encerrar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_subordinate_position_id uuid,
  p_vigencia timestamptz,
  p_motivo text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_motivo     text := btrim(coalesce(p_motivo, ''));
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_qtd        int;
  v_lista      jsonb;
begin
  if p_operation_id is null or p_subordinate_position_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id e subordinate_position_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_reporting_encerrar',
    'organization_id', p_organization_id,
    'subordinate_position_id', p_subordinate_position_id,
    'vigencia', p_vigencia,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return;
  end if;

  if not exists (
    select 1
      from public.organizational_positions p
     where p.id = p_subordinate_position_id
       and p.organization_id = p_organization_id
  ) then
    raise exception 'F5_07_NOT_FOUND: posicao subordinada inexistente ou de outro tenant';
  end if;

  perform pg_advisory_xact_lock(hashtext('f5_07_estrutura:' || p_organization_id::text));

  select count(*),
         coalesce(jsonb_agg(jsonb_build_object(
           'reporting_line_id', rl.id,
           'manager_position_id', rl.manager_position_id,
           'valid_from', rl.valid_from) order by rl.valid_from, rl.id), '[]'::jsonb)
    into v_qtd, v_lista
    from public.position_reporting_lines rl
   where rl.subordinate_position_id = p_subordinate_position_id
     and rl.organization_id = p_organization_id
     and rl.valid_from < p_vigencia
     and (rl.valid_to is null or rl.valid_to > p_vigencia);

  if v_qtd = 0 then
    raise exception 'F5_07_NOT_FOUND: nao ha reporting line vigente para encerrar nessa data';
  end if;

  update public.position_reporting_lines rl
     set valid_to = p_vigencia,
         version = version + 1
   where rl.subordinate_position_id = p_subordinate_position_id
     and rl.organization_id = p_organization_id
     and rl.valid_from < p_vigencia
     and (rl.valid_to is null or rl.valid_to > p_vigencia);

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, position_id, event_type, effective_date, cycle_scope,
    reason, before_value, after_value, payload_hash, result_entity_id,
    actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    p_organization_id, p_subordinate_position_id, 'REPORTING_LINE_ENCERRADA',
    p_vigencia, 'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    jsonb_build_object('linhas', v_lista),
    jsonb_build_object('valid_to', p_vigencia),
    v_hash, null, p_actor_user_profile_id, v_membership, p_operation_id
  );
end;
$$;

comment on function public.estrutura_reporting_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) is
  'F5-07 D7: encerra a reporting line vigente do subordinado por valid_to '
  '(nunca DELETE), gravando REPORTING_LINE_ENCERRADA na MESMA transacao. '
  'Ausencia de linha vigente => F5_07_NOT_FOUND. SECURITY INVOKER; EXECUTE '
  'somente service_role.';

-- ----------------------------------------------------------------------------
-- 9) `estrutura_responsabilidade_definir` — substituicao temporaria (D9)
-- ----------------------------------------------------------------------------
-- `temporary_responsibilities` (F3-06) exige periodo FECHADO (`valid_to not
-- null`). Como a espinha fixa a assinatura de abertura sem data-fim, a abertura
-- grava `valid_to` = fim de existencia da posicao alvo ou `'infinity'`
-- (sentinela de "aberta"); `estrutura_responsabilidade_encerrar` substitui esse
-- valor pela vigencia real. Nenhuma coluna/tabela nova e criada (D9: reuso).
create or replace function public.estrutura_responsabilidade_definir(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_position_id uuid,
  p_substitute_collaborator_id uuid,
  p_responsibility_type text,
  p_vigencia timestamptz,
  p_motivo text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_motivo     text := btrim(coalesce(p_motivo, ''));
  v_tipo       text := lower(btrim(coalesce(p_responsibility_type, '')));
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_pos_from   timestamptz;
  v_pos_to     timestamptz;
  v_valid_to   timestamptz;
  v_status     text;
  v_id         uuid;
begin
  if p_operation_id is null or p_position_id is null or p_substitute_collaborator_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id, position_id e substitute_collaborator_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;
  if v_tipo not in ('operational', 'evaluative', 'operational_evaluative') then
    raise exception 'F5_07_INVALID_INPUT: responsibility_type invalido (operational, evaluative ou operational_evaluative)';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_responsabilidade_definir',
    'organization_id', p_organization_id,
    'position_id', p_position_id,
    'substitute_collaborator_id', p_substitute_collaborator_id,
    'responsibility_type', v_tipo,
    'vigencia', p_vigencia,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash, e.result_entity_id
    into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return v_evento.result_entity_id;
  end if;

  select p.valid_from, p.valid_to
    into v_pos_from, v_pos_to
    from public.organizational_positions p
   where p.id = p_position_id
     and p.organization_id = p_organization_id;
  if not found then
    raise exception 'F5_07_NOT_FOUND: posicao inexistente ou de outro tenant';
  end if;

  if not exists (
    select 1
      from public.collaborators c
     where c.id = p_substitute_collaborator_id
       and c.organization_id = p_organization_id
  ) then
    raise exception 'F5_07_NOT_FOUND: colaborador substituto inexistente ou de outro tenant';
  end if;

  if p_vigencia < v_pos_from then
    raise exception 'F5_07_CONFLICT: vigencia anterior a existencia da posicao';
  end if;

  -- Predicado de dominio (§9.4): colaborador desligado nao recebe
  -- responsabilidade temporaria.
  select sp.status into v_status
    from public.collaborator_status_periods sp
   where sp.collaborator_id = p_substitute_collaborator_id
     and sp.valid_from <= p_vigencia
     and (sp.valid_to is null or sp.valid_to > p_vigencia)
   order by sp.valid_from desc, sp.id
   limit 1;
  if v_status = 'inactive' then
    raise exception 'F5_07_CONFLICT: colaborador inativo nao pode receber responsabilidade temporaria';
  end if;

  v_valid_to := coalesce(v_pos_to, 'infinity'::timestamptz);

  -- Nao ha "definir" destrutivo: se ja existe responsabilidade vigente na
  -- posicao, o erro e explicito (a exclusion da F3-06 e a ultima barreira).
  if exists (
    select 1
      from public.temporary_responsibilities tr
     where tr.organizational_position_id = p_position_id
       and tr.organization_id = p_organization_id
       and tr.valid_from <= p_vigencia
       and tr.valid_to > p_vigencia
  ) then
    raise exception 'F5_07_CONFLICT: ja existe responsabilidade temporaria vigente na posicao (encerre antes)';
  end if;

  -- Auto-substituicao (trigger F3-06 e a ultima barreira; erro com codigo).
  if exists (
    select 1
      from public.occupations o
     where o.organizational_position_id = p_position_id
       and o.collaborator_id = p_substitute_collaborator_id
       and o.valid_from < v_valid_to
       and (o.valid_to is null or o.valid_to > p_vigencia)
  ) then
    raise exception 'F5_07_CONFLICT: substituto nao pode ser o ocupante formal da posicao no periodo';
  end if;

  insert into public.temporary_responsibilities
    (organization_id, organizational_position_id, substitute_collaborator_id,
     responsibility_type, reason, valid_from, valid_to)
  values (p_organization_id, p_position_id, p_substitute_collaborator_id,
          v_tipo, v_motivo, p_vigencia, v_valid_to)
  returning id into v_id;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reason, before_value, after_value, payload_hash,
    result_entity_id, actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    p_organization_id, p_substitute_collaborator_id, p_position_id,
    'RESPONSABILIDADE_INICIADA', p_vigencia, 'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    null,
    jsonb_build_object('responsibility_id', v_id, 'position_id', p_position_id,
                       'substitute_collaborator_id', p_substitute_collaborator_id,
                       'responsibility_type', v_tipo, 'valid_from', p_vigencia),
    v_hash, v_id, p_actor_user_profile_id, v_membership, p_operation_id
  );

  return v_id;
end;
$$;

comment on function public.estrutura_responsabilidade_definir(uuid, uuid, uuid, uuid, uuid, text, timestamptz, text) is
  'F5-07 D9: abre responsabilidade temporaria (substituicao) sobre uma posicao, '
  'reusando `temporary_responsibilities` (F3-06) — o substituto NAO herda '
  'capabilities do titular. Como a tabela exige periodo fechado, a abertura usa '
  'valid_to = fim de existencia da posicao ou infinity (sentinela), substituido '
  'no encerramento. SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 10) `estrutura_responsabilidade_encerrar` — fecha a responsabilidade (D9)
-- ----------------------------------------------------------------------------
create or replace function public.estrutura_responsabilidade_encerrar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_responsibility_id uuid,
  p_vigencia timestamptz,
  p_motivo text
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_motivo     text := btrim(coalesce(p_motivo, ''));
  v_hash       text;
  v_evento     record;
  v_membership uuid;
  v_resp       record;
begin
  if p_operation_id is null or p_responsibility_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id e responsibility_id obrigatorios';
  end if;
  if p_vigencia is null then
    raise exception 'F5_07_INVALID_INPUT: vigencia obrigatoria';
  end if;
  if v_motivo = '' then
    raise exception 'F5_07_INVALID_INPUT: motivo obrigatorio';
  end if;

  v_hash := md5(jsonb_build_object(
    'operacao', 'estrutura_responsabilidade_encerrar',
    'organization_id', p_organization_id,
    'responsibility_id', p_responsibility_id,
    'vigencia', p_vigencia,
    'motivo', v_motivo
  )::text);

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  select e.payload_hash into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return;
  end if;

  select tr.id, tr.organizational_position_id, tr.substitute_collaborator_id,
         tr.valid_from, tr.valid_to
    into v_resp
    from public.temporary_responsibilities tr
   where tr.id = p_responsibility_id
     and tr.organization_id = p_organization_id;
  if not found then
    raise exception 'F5_07_NOT_FOUND: responsabilidade temporaria inexistente ou de outro tenant';
  end if;

  if not (v_resp.valid_from < p_vigencia and v_resp.valid_to > p_vigencia) then
    raise exception 'F5_07_CONFLICT: vigencia fora do periodo da responsabilidade (ja encerrada ou nao iniciada)';
  end if;

  update public.temporary_responsibilities tr
     set valid_to = p_vigencia,
         version = version + 1
   where tr.id = p_responsibility_id;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active';

  insert into public.collaborator_events (
    organization_id, collaborator_id, position_id, event_type, effective_date,
    cycle_scope, reason, before_value, after_value, payload_hash,
    result_entity_id, actor_user_profile_id, actor_membership_id, operation_id
  ) values (
    p_organization_id, v_resp.substitute_collaborator_id,
    v_resp.organizational_position_id, 'RESPONSABILIDADE_ENCERRADA', p_vigencia,
    'CICLO_ATUAL_E_POSTERIORES', v_motivo,
    jsonb_build_object('responsibility_id', v_resp.id,
                       'valid_from', v_resp.valid_from,
                       'valid_to', v_resp.valid_to),
    jsonb_build_object('valid_to', p_vigencia),
    v_hash, v_resp.id, p_actor_user_profile_id, v_membership, p_operation_id
  );
end;
$$;

comment on function public.estrutura_responsabilidade_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) is
  'F5-07 D9: encerra a responsabilidade temporaria substituindo valid_to pela '
  'vigencia informada (nunca DELETE), gravando RESPONSABILIDADE_ENCERRADA na '
  'MESMA transacao. Vigencia fora do periodo => F5_07_CONFLICT. SECURITY '
  'INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 11) `colaborador_catalogo_bootstrap` — bootstrap MINIMO de catalogo (D16)
-- ----------------------------------------------------------------------------
-- Autoriza-se APENAS o bootstrap de catalogo (`job_roles` com `code` e
-- `seniority_levels` por nome). NUNCA cria unidades, posicoes, reporting lines
-- nem colegiado — fabricar hierarquia seria criar autoridade falsa (D16/D20).
-- Plano administrativo (D19): a capability `org.catalog.manage` e enforçada na
-- fronteira confiavel (Edge); a RPC revalida o ATOR no banco (defesa em
-- profundidade) e nao decide autorizacao.
--
-- OPERACAO DE ORGANIZACAO: o catalogo nao tem alvo de colaborador nem de
-- posicao. Para cumprir a regra "toda mutacao grava evento append-only na MESMA
-- transacao" (D8/D26) sem enfraquecer a invariante dos eventos de entidade, a
-- tabela ganhou o tipo `CATALOGO_ATUALIZADO` (unico tipo autorizado a nao ter
-- alvo — ver `ck_collaborator_events_alvo` na migration de schema). DESVIO
-- ADITIVO registrado na entrega: a espinha §1.2 lista 12 tipos e nao preve
-- operacao de organizacao sem alvo, o que tornaria a regra impossivel.
create or replace function public.colaborador_catalogo_bootstrap(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_catalogo jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_item       jsonb;
  v_code       text;
  v_name       text;
  v_hash       text;
  v_evento     record;
  v_membership uuid;
begin
  if p_operation_id is null then
    raise exception 'F5_07_INVALID_INPUT: operation_id obrigatorio (idempotencia)';
  end if;
  if p_catalogo is null or jsonb_typeof(p_catalogo) <> 'object' then
    raise exception 'F5_07_INVALID_INPUT: p_catalogo deve ser um objeto JSON';
  end if;
  if p_catalogo ? 'job_roles' and jsonb_typeof(p_catalogo -> 'job_roles') <> 'array' then
    raise exception 'F5_07_INVALID_INPUT: job_roles deve ser um array de {code, name}';
  end if;
  if p_catalogo ? 'seniority_levels' and jsonb_typeof(p_catalogo -> 'seniority_levels') <> 'array' then
    raise exception 'F5_07_INVALID_INPUT: seniority_levels deve ser um array de {name}';
  end if;

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  -- Idempotencia (D13): mesmo operation_id + mesmo payload_hash => mesmo
  -- resultado (nenhuma escrita nova); hash diferente => CONFLICT.
  v_hash := md5(jsonb_build_object(
    'operacao', 'colaborador_catalogo_bootstrap',
    'organization_id', p_organization_id,
    'catalogo', p_catalogo
  )::text);

  select e.payload_hash into v_evento
    from public.collaborator_events e
   where e.organization_id = p_organization_id
     and e.operation_id = p_operation_id;
  if found then
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F5_07_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;
    return;
  end if;

  for v_item in
    select * from jsonb_array_elements(coalesce(p_catalogo -> 'job_roles', '[]'::jsonb))
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'F5_07_INVALID_INPUT: item de job_roles deve ser objeto {code, name}';
    end if;

    v_code := nullif(btrim(coalesce(v_item ->> 'code', '')), '');
    v_name := nullif(btrim(coalesce(v_item ->> 'name', '')), '');
    if v_code is null or v_name is null then
      raise exception 'F5_07_INVALID_INPUT: job_roles exige code e name nao vazios';
    end if;
    if v_code <> upper(v_code) then
      raise exception 'F5_07_INVALID_INPUT: code de job_role deve estar em caixa alta';
    end if;

    -- Idempotente por (organization_id, code); NUNCA renomeia item existente.
    if exists (
      select 1 from public.job_roles jr
       where jr.organization_id = p_organization_id and jr.code = v_code
    ) then
      continue;
    end if;

    if exists (
      select 1 from public.job_roles jr
       where jr.organization_id = p_organization_id
         and jr.name = v_name
         and jr.code is null
    ) then
      update public.job_roles jr
         set code = v_code
       where jr.organization_id = p_organization_id
         and jr.name = v_name
         and jr.code is null;
    elsif exists (
      select 1 from public.job_roles jr
       where jr.organization_id = p_organization_id
         and jr.name = v_name
         and jr.code is not null
         and jr.code <> v_code
    ) then
      raise exception 'F5_07_CONFLICT: job_role com o mesmo nome ja possui outro code (nunca renomeia)';
    else
      insert into public.job_roles (organization_id, code, name)
      values (p_organization_id, v_code, v_name);
    end if;
  end loop;

  for v_item in
    select * from jsonb_array_elements(coalesce(p_catalogo -> 'seniority_levels', '[]'::jsonb))
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'F5_07_INVALID_INPUT: item de seniority_levels deve ser objeto {name}';
    end if;

    v_name := nullif(btrim(coalesce(v_item ->> 'name', '')), '');
    if v_name is null then
      raise exception 'F5_07_INVALID_INPUT: seniority_levels exige name nao vazio';
    end if;

    if not exists (
      select 1 from public.seniority_levels sl
       where sl.organization_id = p_organization_id and sl.name = v_name
    ) then
      insert into public.seniority_levels (organization_id, name)
      values (p_organization_id, v_name);
    end if;
  end loop;

  select m.id into v_membership
    from public.user_organization_memberships m
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active';
  if v_membership is null then
    raise exception 'F5_07_FORBIDDEN: membership ativa do ator nao resolvida';
  end if;

  -- Evento append-only na MESMA transacao (D8/D26) — operacao de ORGANIZACAO,
  -- sem alvo de colaborador/posicao (`event_type` CATALOGO_ATUALIZADO).
  insert into public.collaborator_events (
    organization_id, event_type, effective_date, cycle_scope, reason,
    after_value, payload_hash, actor_user_profile_id, actor_membership_id,
    operation_id
  ) values (
    p_organization_id, 'CATALOGO_ATUALIZADO', now(),
    'CICLO_ATUAL_E_POSTERIORES', 'Bootstrap de catalogo organizacional',
    jsonb_build_object('catalogo', p_catalogo),
    v_hash, p_actor_user_profile_id, v_membership, p_operation_id
  );
end;
$$;

comment on function public.colaborador_catalogo_bootstrap(uuid, uuid, uuid, jsonb) is
  'F5-07 D16/D13: bootstrap MINIMO e idempotente do catalogo da organizacao '
  '(job_roles com code + seniority_levels por nome). NUNCA cria unidades, '
  'posicoes ou reporting lines (descricao de estrutura e F5-08/D20) e nunca '
  'renomeia item existente. Grava o evento append-only CATALOGO_ATUALIZADO na '
  'MESMA transacao (operacao de organizacao, sem alvo de entidade). SECURITY '
  'INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 12) Grants: EXECUTE somente service_role (sem superficie para o cliente)
-- ----------------------------------------------------------------------------
revoke all on function public.colaborador_criar(uuid, uuid, uuid, text, text, text, date, text) from public, anon, authenticated;
revoke all on function public.colaborador_editar(uuid, uuid, uuid, uuid, text, text, date, integer) from public, anon, authenticated;
revoke all on function public.colaborador_identificador_definir(uuid, uuid, uuid, uuid, text, timestamptz, text, integer) from public, anon, authenticated;
revoke all on function public.colaborador_status_alterar(uuid, uuid, uuid, uuid, text, timestamptz, text, text, uuid, integer) from public, anon, authenticated;
revoke all on function public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid) from public, anon, authenticated;
revoke all on function public.estrutura_ocupacao_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function public.estrutura_reporting_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function public.estrutura_reporting_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function public.estrutura_responsabilidade_definir(uuid, uuid, uuid, uuid, uuid, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public.estrutura_responsabilidade_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) from public, anon, authenticated;
revoke all on function public.colaborador_catalogo_bootstrap(uuid, uuid, uuid, jsonb) from public, anon, authenticated;

grant execute on function public.colaborador_criar(uuid, uuid, uuid, text, text, text, date, text) to service_role;
grant execute on function public.colaborador_editar(uuid, uuid, uuid, uuid, text, text, date, integer) to service_role;
grant execute on function public.colaborador_identificador_definir(uuid, uuid, uuid, uuid, text, timestamptz, text, integer) to service_role;
grant execute on function public.colaborador_status_alterar(uuid, uuid, uuid, uuid, text, timestamptz, text, text, uuid, integer) to service_role;
grant execute on function public.estrutura_ocupacao_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid) to service_role;
grant execute on function public.estrutura_ocupacao_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) to service_role;
grant execute on function public.estrutura_reporting_definir(uuid, uuid, uuid, uuid, uuid, timestamptz, text) to service_role;
grant execute on function public.estrutura_reporting_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) to service_role;
grant execute on function public.estrutura_responsabilidade_definir(uuid, uuid, uuid, uuid, uuid, text, timestamptz, text) to service_role;
grant execute on function public.estrutura_responsabilidade_encerrar(uuid, uuid, uuid, uuid, timestamptz, text) to service_role;
grant execute on function public.colaborador_catalogo_bootstrap(uuid, uuid, uuid, jsonb) to service_role;
