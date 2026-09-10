-- ============================================================================
-- F5-06 (Issue #103): CORREÇÃO DE AUDITORIA — contratos da fronteira confiável
-- ----------------------------------------------------------------------------
-- Esta migration é ADITIVA e corretiva (nenhuma decisão D#/Q# é reaberta):
--
--   1) BLOCKER 1 — assinatura da resolução de ciclo
--      `evaluation_resolver_ciclo` NUNCA aceitou `p_matricula_avaliado`, mas a
--      Edge Function enviava esse argumento. Com PostgREST a divergência quebra
--      a chamada (função inexistente) e impedia toda criação nova. A Edge passa
--      a enviar EXATAMENTE a assinatura abaixo. A ponte matrícula → UUID é
--      resolvida ANTES do Policy Engine (F3-01) e não precisa trafegar de novo.
--
--        evaluation_resolver_ciclo(
--          p_organization_id uuid,
--          p_ano integer,
--          p_numero integer,
--          p_actor_user_profile_id uuid
--        ) returns uuid
--
--   2) BLOCKER 2 — IDOR em participant_id (correção de segurança)
--      `evaluation_gravar_notas` e `evaluation_gravar_comentario` recebiam
--      `p_participant_id` do chamador e só validavam que a ocorrência pertencia
--      à avaliação e estava vigente. Um ator autorizado a escrever podia forjar
--      o id da ocorrência de TERCEIRO e alterar notas/comentários alheios.
--
--      A ocorrência editável passa a ser derivada SOBERANAMENTE do ator:
--        auth.uid() → user_profile → membership ativa no tenant →
--        membership_collaborator_links (F5-02) → collaborator →
--        ocorrência (evaluation_participants) VIGENTE pertencente a ele.
--      O browser NÃO escolhe a ocorrência: `participant_id` deixou de existir
--      no contrato externo dessas operações (Edge e TypeScript acompanham).
--
-- Defesas em profundidade preservadas/exigidas nas RPCs: ator revalidado,
-- tenant revalidado, ocorrência vinculada ao ator, vigência respeitada e
-- fail-closed em ausência ou ambiguidade. Nenhum `SECURITY DEFINER` novo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Resolução SOBERANA da própria ocorrência editável
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_ocorrencia_do_ator(
  p_organization_id uuid,
  p_evaluation_id uuid,
  p_actor_user_profile_id uuid
)
returns table (occurrence_id uuid, role_type text)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_org uuid;
  v_colaborador uuid;
  v_qtd int;
begin
  -- Tenant do RECURSO: nunca do chamador (o payload/argumento não é autoridade).
  select e.organization_id into v_org
    from public.evaluations e
   where e.id = p_evaluation_id
     and e.organization_id = p_organization_id;
  if v_org is null then
    raise exception 'F5-06: avaliacao inexistente no tenant informado';
  end if;

  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;

  -- Vínculo soberano do ator (F5-02): o cliente NUNCA informa de quem é a
  -- ocorrência; ela é derivada do ator autenticado.
  select l.collaborator_id into v_colaborador
    from public.user_organization_memberships m
    join public.membership_collaborator_links l
      on l.membership_id = m.id and l.status = 'active'
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_org
     and m.status = 'active';
  if v_colaborador is null then
    raise exception 'F5-06: ator sem vinculo de colaborador na organizacao';
  end if;

  -- Ocorrência VIGENTE do próprio ator nesta avaliação. Ambiguidade é recusada
  -- (nunca escolhe arbitrariamente); ausência devolve vazio (fail-closed no
  -- chamador, que recusa a gravação).
  select count(*) into v_qtd
    from public.evaluation_participants p
   where p.evaluation_id = p_evaluation_id
     and p.organization_id = v_org
     and p.collaborator_id = v_colaborador
     and p.valid_from <= now()
     and (p.valid_to is null or p.valid_to > now());

  if v_qtd > 1 then
    raise exception 'F5-06: mais de uma ocorrencia vigente do ator nesta avaliacao (ambiguidade)';
  end if;

  return query
    select p.id, p.role_type
      from public.evaluation_participants p
     where p.evaluation_id = p_evaluation_id
       and p.organization_id = v_org
       and p.collaborator_id = v_colaborador
       and p.valid_from <= now()
       and (p.valid_to is null or p.valid_to > now());
end;
$$;

comment on function public.evaluation_ocorrencia_do_ator(uuid, uuid, uuid) is
  'F5-06 (correcao de auditoria): resolve a ocorrencia EDITAVEL do ator '
  'autenticado a partir de auth.uid() -> perfil -> membership ativa no tenant do '
  'recurso -> vinculo F5-02 -> ocorrencia vigente em evaluation_participants. O '
  'cliente nunca escolhe a ocorrencia; ausencia devolve vazio e ambiguidade '
  'recusa (fail-closed). SECURITY INVOKER. EXECUTE somente service_role.';

revoke all on function public.evaluation_ocorrencia_do_ator(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.evaluation_ocorrencia_do_ator(uuid, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 2) Gravação de notas — sem participant_id do cliente
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_gravar_notas(
  p_evaluation_id uuid,
  p_notas jsonb,
  p_actor_user_profile_id uuid
)
returns numeric
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org uuid;
  v_status text;
  v_config uuid;
  v_instante timestamptz;
  v_participant_id uuid;
  v_item jsonb;
  v_nota smallint;
  v_sub uuid;
  v_anterior smallint;
  v_id uuid;
begin
  select organization_id, status, config_version_id into v_org, v_status, v_config
    from public.evaluations where id = p_evaluation_id for update;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;
  if v_status in ('CONCLUIDA', 'CANCELADA') then
    raise exception 'F5-06: avaliacao % e imutavel (reabra antes de editar)', v_status;
  end if;

  -- A ocorrência editável é SEMPRE a do ator autenticado (nunca do payload).
  select o.occurrence_id into v_participant_id
    from public.evaluation_ocorrencia_do_ator(v_org, p_evaluation_id, p_actor_user_profile_id) o;
  if v_participant_id is null then
    raise exception 'F5-06: ator sem ocorrencia vigente nesta avaliacao (autorizacao negada)';
  end if;

  v_instante := now();

  for v_item in select * from jsonb_array_elements(coalesce(p_notas, '[]'::jsonb)) loop
    v_nota := (v_item ->> 'nota')::smallint;
    v_sub := (v_item ->> 'subcriterion_id')::uuid;
    if v_nota is null or v_nota < 1 or v_nota > 5 then
      raise exception 'F5-06: nota invalida (esperado 1..5)';
    end if;

    -- O subcriterio precisa pertencer a CONFIGURACAO CONGELADA da avaliacao
    -- (D6): subcriterio de outra versao do mesmo tenant e recusado.
    if not exists (
      select 1
        from public.evaluation_config_subcriteria sub
        join public.evaluation_config_criteria cri
          on cri.id = sub.config_criterion_id
         and cri.organization_id = sub.organization_id
       where sub.id = v_sub
         and sub.organization_id = v_org
         and cri.config_version_id = v_config
    ) then
      raise exception 'F5-06 D6: subcriterio nao pertence a configuracao '
        'congelada da avaliacao';
    end if;

    select sc.nota into v_anterior
      from public.evaluation_scores sc
     where sc.evaluation_id = p_evaluation_id
       and sc.participant_id = v_participant_id
       and sc.subcriterion_id = v_sub;

    insert into public.evaluation_scores
      (organization_id, evaluation_id, participant_id, subcriterion_id, nota,
       autor_user_profile_id, data_avaliacao)
    values (v_org, p_evaluation_id, v_participant_id, v_sub, v_nota,
            p_actor_user_profile_id, v_instante)
    on conflict (participant_id, subcriterion_id) do update
      set nota = excluded.nota,
          autor_user_profile_id = excluded.autor_user_profile_id,
          data_avaliacao = excluded.data_avaliacao,
          version = public.evaluation_scores.version + 1
    returning id into v_id;

    -- Delta ESTRUTURADO por nota (D26): a trilha guarda valor anterior e novo,
    -- com entidade/entidade_id apontando para a linha real da nota — nunca
    -- apenas o payload bruto do lote.
    insert into public.evaluation_events
      (organization_id, evaluation_id, event_type, actor_user_profile_id,
       entidade, entidade_id, valor_anterior, valor_novo)
    values (v_org, p_evaluation_id, 'NOTA_ALTERADA', p_actor_user_profile_id,
            'evaluation_scores', v_id,
            case when v_anterior is null then null
                 else jsonb_build_object('participant_id', v_participant_id,
                                         'subcriterion_id', v_sub,
                                         'nota', v_anterior) end,
            jsonb_build_object('participant_id', v_participant_id,
                               'subcriterion_id', v_sub,
                               'nota', v_nota));
  end loop;

  return public.evaluation_calcular(p_evaluation_id);
end;
$$;

comment on function public.evaluation_gravar_notas(uuid, jsonb, uuid) is
  'F5-06 (correcao de auditoria/IDOR): grava o lote de notas EXCLUSIVAMENTE na '
  'ocorrencia do ator autenticado, resolvida server-side (auth.uid -> vinculo '
  'F5-02 -> ocorrencia vigente). NAO aceita participant_id do chamador. Valida '
  'que o subcriterio pertence a configuracao congelada e grava delta estruturado '
  '(valor_anterior/valor_novo) por nota. Lote transacional; recalcula o agregado '
  'oficial na mesma transacao. EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 3) Gravação de comentário — sem participant_id do cliente
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_gravar_comentario(
  p_evaluation_id uuid,
  p_escopo text,
  p_criterion_id uuid,
  p_texto text,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org uuid;
  v_status text;
  v_config uuid;
  v_instante timestamptz;
  v_participant_id uuid;
  v_anterior text;
  v_id uuid;
begin
  if p_escopo not in ('CRITERIO', 'FINAL') then
    raise exception 'F5-06: escopo de comentario invalido';
  end if;
  if p_texto is null or btrim(p_texto) = '' then
    raise exception 'F5-06: comentario vazio';
  end if;

  select organization_id, status, config_version_id into v_org, v_status, v_config
    from public.evaluations where id = p_evaluation_id for update;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;
  if v_status in ('CONCLUIDA', 'CANCELADA') then
    raise exception 'F5-06: avaliacao % e imutavel (reabra antes de editar)', v_status;
  end if;

  -- A ocorrência editável é SEMPRE a do ator autenticado (nunca do payload).
  select o.occurrence_id into v_participant_id
    from public.evaluation_ocorrencia_do_ator(v_org, p_evaluation_id, p_actor_user_profile_id) o;
  if v_participant_id is null then
    raise exception 'F5-06: ator sem ocorrencia vigente nesta avaliacao (autorizacao negada)';
  end if;

  v_instante := now();

  if p_escopo = 'CRITERIO' then
    if p_criterion_id is null then
      raise exception 'F5-06: comentario de criterio exige criterion_id';
    end if;
    if not exists (
      select 1 from public.evaluation_config_criteria cri
       where cri.id = p_criterion_id
         and cri.organization_id = v_org
         and cri.config_version_id = v_config
    ) then
      raise exception 'F5-06 D6: criterio nao pertence a configuracao '
        'congelada da avaliacao';
    end if;

    select cm.texto into v_anterior
      from public.evaluation_comments cm
     where cm.participant_id = v_participant_id
       and cm.evaluation_id = p_evaluation_id
       and cm.escopo = 'CRITERIO'
       and cm.criterion_id = p_criterion_id;

    if v_anterior is not null then
      update public.evaluation_comments cm
         set texto = btrim(p_texto),
             autor_user_profile_id = p_actor_user_profile_id,
             data = v_instante,
             version = cm.version + 1
       where cm.participant_id = v_participant_id
         and cm.evaluation_id = p_evaluation_id
         and cm.escopo = 'CRITERIO'
         and cm.criterion_id = p_criterion_id
      returning cm.id into v_id;
    else
      insert into public.evaluation_comments
        (organization_id, evaluation_id, participant_id, escopo, criterion_id,
         texto, autor_user_profile_id, data)
      values (v_org, p_evaluation_id, v_participant_id, 'CRITERIO', p_criterion_id,
              btrim(p_texto), p_actor_user_profile_id, v_instante)
      returning id into v_id;
    end if;
  else
    select cm.texto into v_anterior
      from public.evaluation_comments cm
     where cm.participant_id = v_participant_id
       and cm.evaluation_id = p_evaluation_id
       and cm.escopo = 'FINAL';

    if v_anterior is not null then
      update public.evaluation_comments cm
         set texto = btrim(p_texto),
             autor_user_profile_id = p_actor_user_profile_id,
             data = v_instante,
             version = cm.version + 1
       where cm.participant_id = v_participant_id
         and cm.evaluation_id = p_evaluation_id
         and cm.escopo = 'FINAL'
      returning cm.id into v_id;
    else
      insert into public.evaluation_comments
        (organization_id, evaluation_id, participant_id, escopo, criterion_id,
         texto, autor_user_profile_id, data)
      values (v_org, p_evaluation_id, v_participant_id, 'FINAL', null,
              btrim(p_texto), p_actor_user_profile_id, v_instante)
      returning id into v_id;
    end if;
  end if;

  insert into public.evaluation_events
    (organization_id, evaluation_id, event_type, actor_user_profile_id,
     entidade, entidade_id, valor_anterior, valor_novo)
  values (v_org, p_evaluation_id, 'COMENTARIO_ALTERADO', p_actor_user_profile_id,
          'evaluation_comments', v_id,
          case when v_anterior is null then null
               else jsonb_build_object('escopo', p_escopo,
                                       'criterion_id', p_criterion_id,
                                       'texto', v_anterior) end,
          jsonb_build_object('escopo', p_escopo,
                             'criterion_id', p_criterion_id,
                             'texto', btrim(p_texto)));
end;
$$;

comment on function public.evaluation_gravar_comentario(uuid, text, uuid, text, uuid) is
  'F5-06 (correcao de auditoria/IDOR): grava o comentario EXCLUSIVAMENTE na '
  'ocorrencia do ator autenticado, resolvida server-side (auth.uid -> vinculo '
  'F5-02 -> ocorrencia vigente). NAO aceita participant_id do chamador. Valida '
  'escopo, criterio da configuracao congelada e registra evento auditado com '
  'delta estruturado. EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- Grants: novas assinaturas fechadas para authenticated (padrão F5-06)
-- ----------------------------------------------------------------------------
revoke all on function public.evaluation_gravar_notas(uuid, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.evaluation_gravar_notas(uuid, jsonb, uuid)
  to service_role;

revoke all on function public.evaluation_gravar_comentario(uuid, text, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.evaluation_gravar_comentario(uuid, text, uuid, text, uuid)
  to service_role;

-- A assinatura ANTIGA (com participant_id) é removida para que o browser não
-- tenha nenhum caminho capaz de escolher a ocorrência de terceiro.
drop function if exists public.evaluation_gravar_notas(uuid, uuid, jsonb, uuid);
drop function if exists public.evaluation_gravar_comentario(uuid, uuid, text, uuid, text, uuid);
