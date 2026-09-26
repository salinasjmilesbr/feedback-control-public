-- ============================================================================
-- F5-08 P1 (Etapa 5): alinhamento da chave de advisory lock — D24/Q4
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-08-desenho-tecnico.md (§14.3, §20.1, D14, D24 — Q4 = A,
-- aprovado na revisao arquitetural do PR #182).
--
-- As 4 RPCs estruturais entregues pela F5-07 usavam
-- `hashtext('f5_07_estrutura:' || organization_id)`, chave DIFERENTE da usada
-- pelo trigger anti-ciclo da F3-04
-- (`hashtext('position_reporting_lines:' || organization_id)`,
-- `20260907140000:253-268`, que documenta o lock como normativo). Com duas
-- chaves, as rotas de escrita nao serializavam entre si e o anti-ciclo podia
-- nao enxergar o estado concorrente (janela real de corrida).
--
-- Esta migration aplica `create or replace function` nas 4 funcoes trocando
-- SOMENTE a chave de lock para a normativa:
--
--   position_reporting_lines:<organization_id>
--
-- Garantias (P1):
--   - corpo copiado LITERALMENTE da F5-07; a unica diferenca e a chave;
--   - NENHUMA mudanca de assinatura, de tipo de retorno, de autorizacao ou de
--     comportamento funcional;
--   - ACLs existentes sao preservadas (create or replace nao altera grants);
--   - o bloco de guarda no fim FALHA FECHADO se qualquer funcao estrutural de
--     `public` ainda referenciar a chave antiga.
--
-- Nada de SECURITY DEFINER novo e nenhuma alteracao em tabelas/policies.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Substituicao literal das 4 funcoes (somente a chave de lock muda)
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
  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

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

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || v_org::text));

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

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || p_organization_id::text));

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

  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:' || p_organization_id::text));

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

-- ----------------------------------------------------------------------------
-- 2) Guarda fail-closed: nenhuma funcao estrutural pode manter a chave antiga
-- ----------------------------------------------------------------------------
-- Cobre qualquer caminho de escrita estrutural (`estrutura_*`) que ainda
-- referencie a chave antiga — hoje ou por regressao futura. A migration aborta
-- com excecao se encontrar.
do $$
declare
  v_pendentes text[];
begin
  select array_agg(p.proname order by p.proname)
    into v_pendentes
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'estrutura\_%'
    and p.prosrc like '%f5_07_estrutura:%';

  if v_pendentes is not null then
    raise exception
      'F5-08 D24: funcoes estruturais ainda usam a chave antiga f5_07_estrutura: %',
      array_to_string(v_pendentes, ', ');
  end if;

  raise notice '[PASS] F5-08 D24: nenhuma funcao estrutural usa a chave antiga';
end $$;
