-- ============================================================================
-- F5-06 (Issue #103): resolução soberana de ciclo e leitura da PRÓPRIA
-- ocorrência do participante autenticado
-- ----------------------------------------------------------------------------
-- Duas funções mínimas, aditivas ao contrato fechado (docs/F5-06-desenho-tecnico.md):
--
--   1) evaluation_resolver_ciclo(organization_id, ano, numero):
--      ano+ciclo são INTENÇÃO do cliente; o tenant é revalidado server-side e a
--      resolução acontece exclusivamente dentro da organização validada.
--      Zero ou múltiplos ciclos ⇒ recusa (fail-closed). O UUID retornado é o
--      vínculo soberano usado na criação da avaliação (D15).
--
--   2) evaluation_painel_participante(evaluation_id, actor_user_profile_id):
--      LEITURA DE EDIÇÃO — o participante autenticado recebe SOMENTE a própria
--      ocorrência (notas e comentários que ele lançou) + os códigos/nomes do
--      catálogo congelado para montar a tela. NÃO devolve voto/nota individual
--      de terceiros, nem `participant_id` alheio. A ocorrência própria é
--      resolvida/revalidada SERVER-SIDE a partir do ator soberano + vínculo
--      (F5-02) + avaliação + vigência; `participant_id` do cliente nunca é
--      prova de identidade. Ambiguidade ou ausência de vínculo ⇒ recusa.
--
-- D20 permanece ÍNTEGRA: ela regula a transparência do AVALIADO
-- (evaluation_leitura_avaliado). Esta leitura serve ao PARTICIPANTE autorizado
-- a editar a própria ocorrência e não expõe voto individual de terceiros.
--
-- Padrão de segurança idêntico à migration anterior: SECURITY INVOKER,
-- set search_path = public, EXECUTE somente service_role.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) evaluation_resolver_ciclo — ano + ciclo → evaluation_cycles.id (D15)
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_resolver_ciclo(
  p_organization_id uuid,
  p_ano integer,
  p_numero integer,
  p_actor_user_profile_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_ids uuid[];
  v_status text;
begin
  if not public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;

  if p_ano is null or p_ano <= 0 then
    raise exception 'F5-06: ano de ciclo invalido';
  end if;
  if p_numero is null or p_numero not in (1, 2, 3) then
    raise exception 'F5-06: numero de ciclo invalido (1..3)';
  end if;

  -- Resolução EXCLUSIVAMENTE dentro da organização validada.
  select array_agg(c.id order by c.id), min(c.status)
    into v_ids, v_status
    from public.evaluation_cycles c
   where c.organization_id = p_organization_id
     and c.ano = p_ano
     and c.numero = p_numero;

  if v_ids is null then
    raise exception 'F5-06: ciclo inexistente para o ano/numero informados';
  end if;
  if array_length(v_ids, 1) <> 1 then
    raise exception 'F5-06: mais de um ciclo para o mesmo ano/numero (ambiguidade)';
  end if;
  if v_status = 'CANCELADO' then
    raise exception 'F5-06: ciclo cancelado nao pode receber avaliacoes';
  end if;

  return v_ids[1];
end;
$$;

comment on function public.evaluation_resolver_ciclo(uuid, integer, integer, uuid) is
  'F5-06 D15/D27: resolve ano+ciclo (INTENCAO do cliente) para o UUID soberano '
  'de evaluation_cycles.id, exclusivamente dentro da organizacao validada do '
  'ator. Zero ou multiplos ciclos, ou ciclo cancelado, sao recusados '
  '(fail-closed). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 2) evaluation_painel_participante — leitura da PRÓPRIA ocorrência (edição)
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_painel_participante(
  p_evaluation_id uuid,
  p_actor_user_profile_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_eval record;
  v_colaborador uuid;
  v_participante record;
  v_ocorrencias int;
  v_instante timestamptz;
  v_papeis text[];
  v_resultado jsonb;
begin
  select e.id, e.organization_id, e.config_version_id, e.cycle_id, e.status,
         e.evaluated_collaborator_id, coalesce(e.data_conclusao, now()) as instante,
         c.ano as ciclo_ano, c.numero as ciclo_numero
    into v_eval
    from public.evaluations e
    join public.evaluation_cycles c
      on c.id = e.cycle_id and c.organization_id = e.organization_id
   where e.id = p_evaluation_id;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;
  v_instante := v_eval.instante;

  -- Vínculo soberano do ator (F5-02): o cliente NUNCA informa de quem é a
  -- ocorrência; ela é derivada do ator autenticado.
  select l.collaborator_id into v_colaborador
    from public.user_organization_memberships m
    join public.membership_collaborator_links l
      on l.membership_id = m.id and l.status = 'active'
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_eval.organization_id
     and m.status = 'active';
  if v_colaborador is null then
    raise exception 'F5-06: ator sem vinculo de colaborador na organizacao';
  end if;

  -- Ocorrência VIGENTE do próprio ator nesta avaliação. Ambiguidade (mais de
  -- uma ocorrência vigente) é recusada: nunca escolhe arbitrariamente.
  --
  -- AUSÊNCIA de ocorrência NÃO é erro de backend: é o resultado "não há painel
  -- para este ator" (a avaliação pode existir para outro ator). Devolver `null`
  -- permite à fronteira distinguir "não existe/não é acessível" (NOT_FOUND, que
  -- não vaza existência cross-tenant) de "indeterminação" (falha real, que é
  -- fail-closed). Nenhum dado de terceiro é revelado em qualquer caso.
  select count(*) into v_ocorrencias
    from public.evaluation_participants p
   where p.evaluation_id = v_eval.id
     and p.organization_id = v_eval.organization_id
     and p.collaborator_id = v_colaborador
     and p.valid_from <= v_instante
     and (p.valid_to is null or p.valid_to > v_instante);

  if v_ocorrencias = 0 then
    return null;
  end if;
  if v_ocorrencias > 1 then
    raise exception 'F5-06: mais de uma ocorrencia vigente do ator nesta avaliacao (ambiguidade)';
  end if;

  select p.id, p.role_type, p.collaborator_id, p.valid_from, p.valid_to
    into v_participante
    from public.evaluation_participants p
   where p.evaluation_id = v_eval.id
     and p.organization_id = v_eval.organization_id
     and p.collaborator_id = v_colaborador
     and p.valid_from <= v_instante
     and (p.valid_to is null or p.valid_to > v_instante);

  -- Papéis efetivamente atribuídos ao próprio ator (para a UI permitir editar
  -- apenas o que lhe cabe). Nenhum papel de TERCEIRO é revelado.
  select array_agg(distinct p.role_type)
    into v_papeis
    from public.evaluation_participants p
   where p.evaluation_id = v_eval.id
     and p.organization_id = v_eval.organization_id
     and p.collaborator_id = v_colaborador
     and p.valid_from <= v_instante
     and (p.valid_to is null or p.valid_to > v_instante);

  select jsonb_build_object(
    'evaluation_id', v_eval.id,
    'organization_id', v_eval.organization_id,
    'cycle_id', v_eval.cycle_id,
    'cycle_ano', v_eval.ciclo_ano,
    'cycle_numero', v_eval.ciclo_numero,
    'config_version_id', v_eval.config_version_id,
    'status', v_eval.status,
    'evaluated_collaborator_id', v_eval.evaluated_collaborator_id,
    'meus_papeis', coalesce(to_jsonb(v_papeis), '[]'::jsonb),
    'participante_ocorrencia_id', v_participante.id,
    'participante_role_type', v_participante.role_type,
    'participante_vigencia', jsonb_build_object(
      'valid_from', v_participante.valid_from,
      'valid_to', v_participante.valid_to
    ),
    -- Catálogo CONGELADO da avaliação: necessário para montar a tela; não é
    -- dado de terceiros. Os IDs são os da PRÓPRIA configuração congelada (o
    -- cliente precisa deles para gravar nota/comentário do seu papel); não
    -- revelam ocorrência, voto ou nota de terceiro algum.
    'criterios', coalesce((
      select jsonb_agg(jsonb_build_object('id', cri.id, 'code', cri.code,
                                          'name', cri.name,
                                          'position', cri.position)
                       order by cri.position)
        from public.evaluation_config_criteria cri
       where cri.organization_id = v_eval.organization_id
         and cri.config_version_id = v_eval.config_version_id
    ), '[]'::jsonb),
    'subcriterios', coalesce((
      select jsonb_agg(jsonb_build_object('id', sub.id, 'code', sub.code,
                                          'name', sub.name,
                                          'position', sub.position,
                                          'criterion_code', cri.code)
                       order by cri.position, sub.position)
        from public.evaluation_config_subcriteria sub
        join public.evaluation_config_criteria cri
          on cri.id = sub.config_criterion_id
         and cri.organization_id = v_eval.organization_id
         and cri.config_version_id = v_eval.config_version_id
       where sub.organization_id = v_eval.organization_id
    ), '[]'::jsonb),
    -- SOMENTE as notas da PRÓPRIA ocorrência.
    'minhas_notas', coalesce((
      select jsonb_agg(jsonb_build_object('subcriterion_id', sc.subcriterion_id,
                                          'nota', sc.nota,
                                          'data_avaliacao', sc.data_avaliacao)
                       order by sc.subcriterion_id)
        from public.evaluation_scores sc
       where sc.evaluation_id = v_eval.id
         and sc.organization_id = v_eval.organization_id
         and sc.participant_id = v_participante.id
    ), '[]'::jsonb),
    -- SOMENTE os comentários da PRÓPRIA ocorrência.
    'meus_comentarios', coalesce((
      select jsonb_agg(jsonb_build_object('escopo', cm.escopo,
                                          'criterion_id', cm.criterion_id,
                                          'texto', cm.texto)
                       order by cm.escopo, cm.criterion_id)
        from public.evaluation_comments cm
       where cm.evaluation_id = v_eval.id
         and cm.organization_id = v_eval.organization_id
         and cm.participant_id = v_participante.id
    ), '[]'::jsonb),
    -- Papéis que exigem comentário final (configuração congelada da avaliação).
    'papeis_com_feedback_final', coalesce((
      select jsonb_agg(pcr.role_type order by pcr.role_type)
        from public.evaluation_config_participant_roles pcr
       where pcr.organization_id = v_eval.organization_id
         and pcr.config_version_id = v_eval.config_version_id
         and pcr.requires_final_comment
    ), '[]'::jsonb)
  ) into v_resultado;

  return v_resultado;
end;
$$;

comment on function public.evaluation_painel_participante(uuid, uuid) is
  'F5-06: LEITURA DE EDICAO do participante autenticado. Devolve o catalogo '
  'congelado da avaliacao (ids/codigos/nomes dos criterios e subcriterios da '
  'PROPRIA configuracao congelada, necessarios para gravar o que cabe ao ator) '
  'e SOMENTE a propria ocorrencia (notas e comentarios lancados pelo ator) + os '
  'papeis que lhe foram atribuidos. NAO devolve voto ou nota individual de '
  'terceiros nem participant_id alheio; a ocorrencia propria e resolvida '
  'server-side pelo vinculo F5-02 + vigencia (o participant_id do cliente nunca '
  'e prova de identidade). D20 (transparencia do AVALIADO) permanece inalterada '
  'em evaluation_leitura_avaliado. Ausencia de ocorrencia vigente do ator '
  'devolve NULL (resultado "sem painel"), distinguindo-se de falha real de '
  'backend; a avaliacao inexistente continua recusada (NOT_FOUND, sem revelar '
  'existencia cross-tenant). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- Grants: EXECUTE somente service_role (sem superfície para authenticated)
-- ----------------------------------------------------------------------------
revoke all on function public.evaluation_resolver_ciclo(uuid, integer, integer, uuid)
  from public, anon, authenticated;
revoke all on function public.evaluation_painel_participante(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.evaluation_resolver_ciclo(uuid, integer, integer, uuid)
  to service_role;
grant execute on function public.evaluation_painel_participante(uuid, uuid)
  to service_role;
