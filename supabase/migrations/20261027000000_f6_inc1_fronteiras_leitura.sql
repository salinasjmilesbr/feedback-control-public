-- ============================================================================
-- F6 — Incremento 1: FRONTEIRAS DE LEITURA de Avaliações
--
-- Contrato: docs/F6-avaliacoes-contrato-soberano-revisao.md (R2, R3, R7)
-- Natureza: migration ADITIVA. Nenhuma migration histórica é editada.
--
--   1) evaluation_painel_participantes — projeção COLETIVA dos participantes
--      (R2): identidades/papéis vigentes, notas individuais existentes
--      (inclusive de cada colegiado), comentários por critério, Feedbacks
--      Finais existentes e progresso FACTUAL (decisão α: contagem derivada dos
--      dados; NÃO é completude normativa — pendências por ocorrência são do
--      Incremento 2).
--   2) evaluation_leitura_avaliado v2 — projeção SELF pós-CONCLUIDA (R3):
--      blocos INDIVIDUAIS do gerente (GESTAO_CADEIA) e do coordenador
--      (GESTAO_DIRETA) + agregado do COLEGIADO por SUBCRITÉRIO (mesma parcela
--      do cálculo oficial). REMOVE o vazamento de identidade do colegiado que a
--      versão anterior expunha (`colaborador_id` da lista de membros).
--
-- Invariantes preservadas: identidade por UUID, tenant revalidado, ocorrência
-- resolvida do ator autenticado, ausência permanece ausência (nunca zero),
-- CONCLUIDA imutável para mutação, N=1 do colegiado mantém o agregado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) evaluation_painel_participantes — leitura COLETIVA dos participantes (R2)
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_painel_participantes(
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
  v_instante timestamptz;
  v_ocorrencias int;
  v_meu record;
  v_papeis text[];
  v_total_subcriterios int;
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
    raise exception 'F6: avaliacao inexistente';
  end if;
  v_instante := v_eval.instante;

  -- Vínculo soberano do ator (F5-02): o cliente NUNCA informa a ocorrência.
  select l.collaborator_id into v_colaborador
    from public.user_organization_memberships m
    join public.membership_collaborator_links l
      on l.membership_id = m.id and l.status = 'active'
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_eval.organization_id
     and m.status = 'active';
  if v_colaborador is null then
    raise exception 'F6: ator sem vinculo de colaborador na organizacao';
  end if;

  -- Requisito (b) do R2: ocorrência MATERIALIZADA e VIGENTE do ator. Ausência
  -- devolve `null` (a fronteira converte em recusa, sem vazar existência).
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

  -- R2: múltiplas ocorrências vigentes legítimas do mesmo ator, em papéis
  -- distintos, NÃO são ambiguidade para esta leitura (a projeção é coletiva e
  -- não escolhe ocorrência editável). Identificamos a PRÓPRIA ocorrência apenas
  -- para renderização — sem conceder escrita por payload.
  select p.id, p.role_type into v_meu
    from public.evaluation_participants p
   where p.evaluation_id = v_eval.id
     and p.organization_id = v_eval.organization_id
     and p.collaborator_id = v_colaborador
     and p.valid_from <= v_instante
     and (p.valid_to is null or p.valid_to > v_instante)
   order by p.valid_from desc, p.id
   limit 1;

  select array_agg(distinct p.role_type) into v_papeis
    from public.evaluation_participants p
   where p.evaluation_id = v_eval.id
     and p.organization_id = v_eval.organization_id
     and p.collaborator_id = v_colaborador
     and p.valid_from <= v_instante
     and (p.valid_to is null or p.valid_to > v_instante);

  select count(*) into v_total_subcriterios
    from public.evaluation_config_subcriteria sub
    join public.evaluation_config_criteria cri
      on cri.id = sub.config_criterion_id
     and cri.organization_id = sub.organization_id
   where sub.organization_id = v_eval.organization_id
     and cri.config_version_id = v_eval.config_version_id;

  return jsonb_build_object(
    'evaluationId', v_eval.id,
    'organizationId', v_eval.organization_id,
    'cycleId', v_eval.cycle_id,
    'cycleAno', v_eval.ciclo_ano,
    'cycleNumero', v_eval.ciclo_numero,
    'configVersionId', v_eval.config_version_id,
    'status', v_eval.status,
    'evaluatedCollaboratorId', v_eval.evaluated_collaborator_id,
    'meuParticipante', jsonb_build_object(
      'ocorrenciaId', v_meu.id,
      'roleType', v_meu.role_type,
      'meusPapeis', coalesce(to_jsonb(v_papeis), '[]'::jsonb)
    ),
    -- Identidades e papéis dos participantes VIGENTES (R2).
    'participantes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'collaboratorId', p.collaborator_id,
               'nome', col.full_name,
               'roleType', p.role_type,
               'validFrom', p.valid_from,
               'validTo', p.valid_to)
             order by p.role_type, col.full_name)
        from public.evaluation_participants p
        join public.collaborators col
          on col.id = p.collaborator_id
         and col.organization_id = p.organization_id
       where p.evaluation_id = v_eval.id
         and p.organization_id = v_eval.organization_id
         and p.valid_from <= v_instante
         and (p.valid_to is null or p.valid_to > v_instante)
    ), '[]'::jsonb),
    -- Catálogo CONGELADO (necessário para renderização; não é dado de terceiro).
    'criterios', coalesce((
      select jsonb_agg(jsonb_build_object('criterionId', cri.id, 'code', cri.code,
                                          'name', cri.name, 'position', cri.position)
                       order by cri.position)
        from public.evaluation_config_criteria cri
       where cri.organization_id = v_eval.organization_id
         and cri.config_version_id = v_eval.config_version_id
    ), '[]'::jsonb),
    'subcriterios', coalesce((
      select jsonb_agg(jsonb_build_object('subcriterionId', sub.id, 'code', sub.code,
                                          'name', sub.name, 'position', sub.position,
                                          'criterionCode', cri.code)
                       order by cri.position, sub.position)
        from public.evaluation_config_subcriteria sub
        join public.evaluation_config_criteria cri
          on cri.id = sub.config_criterion_id
         and cri.organization_id = sub.organization_id
       where sub.organization_id = v_eval.organization_id
         and cri.config_version_id = v_eval.config_version_id
    ), '[]'::jsonb),
    -- NOTAS INDIVIDUAIS já preenchidas — inclusive de cada colegiado (R2).
    'notas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'collaboratorId', p.collaborator_id,
               'roleType', p.role_type,
               'subcriterionId', sc.subcriterion_id,
               'nota', sc.nota)
             order by p.role_type, sc.subcriterion_id)
        from public.evaluation_scores sc
        join public.evaluation_participants p
          on p.id = sc.participant_id
         and p.evaluation_id = sc.evaluation_id
         and p.organization_id = sc.organization_id
       where sc.evaluation_id = v_eval.id
         and sc.organization_id = v_eval.organization_id
         and p.valid_from <= v_instante
         and (p.valid_to is null or p.valid_to > v_instante)
    ), '[]'::jsonb),
    -- COMENTÁRIOS por critério existentes (R2).
    'comentarios', coalesce((
      select jsonb_agg(jsonb_build_object(
               'collaboratorId', p.collaborator_id,
               'roleType', p.role_type,
               'criterionId', cm.criterion_id,
               'texto', cm.texto)
             order by p.role_type, cm.criterion_id)
        from public.evaluation_comments cm
        join public.evaluation_participants p
          on p.id = cm.participant_id
         and p.evaluation_id = cm.evaluation_id
         and p.organization_id = cm.organization_id
       where cm.evaluation_id = v_eval.id
         and cm.organization_id = v_eval.organization_id
         and cm.escopo = 'CRITERIO'
         -- F1: a PROJEÇÃO não confia apenas no invariante de escrita (R1).
         -- COLEGIADO nunca aparece em comentários por critério, mesmo diante de
         -- dado histórico/anômalo.
         and p.role_type in ('GESTAO_CADEIA', 'GESTAO_DIRETA')
         and p.valid_from <= v_instante
         and (p.valid_to is null or p.valid_to > v_instante)
    ), '[]'::jsonb),
    -- FEEDBACKS FINAIS existentes dos papéis que os possuem (R2).
    'feedbacksFinais', coalesce((
      select jsonb_agg(jsonb_build_object(
               'collaboratorId', p.collaborator_id,
               'roleType', p.role_type,
               'texto', cm.texto)
             order by p.role_type)
        from public.evaluation_comments cm
        join public.evaluation_participants p
          on p.id = cm.participant_id
         and p.evaluation_id = cm.evaluation_id
         and p.organization_id = cm.organization_id
       where cm.evaluation_id = v_eval.id
         and cm.organization_id = v_eval.organization_id
         and cm.escopo = 'FINAL'
         -- F1: idem para o Feedback Final — somente gerente e coordenador, sem
         -- depender do invariante de escrita (R1).
         and p.role_type in ('GESTAO_CADEIA', 'GESTAO_DIRETA')
         and p.valid_from <= v_instante
         and (p.valid_to is null or p.valid_to > v_instante)
    ), '[]'::jsonb),
    -- PROGRESSO FACTUAL (decisão α): SOMENTE contagens derivadas dos dados
    -- existentes. Não declara completude nem pendência oficial — isso é o
    -- Incremento 2. Voto ausente NÃO vira zero (é contagem, não nota).
    'progressoFactual', coalesce((
      select jsonb_agg(jsonb_build_object(
               'collaboratorId', p.collaborator_id,
               'roleType', p.role_type,
               'notasInformadas', (
                 select count(*) from public.evaluation_scores sc
                  where sc.evaluation_id = v_eval.id
                    and sc.organization_id = v_eval.organization_id
                    and sc.participant_id = p.id),
               'subcriteriosTotal', v_total_subcriterios)
             order by p.role_type, p.collaborator_id)
        from public.evaluation_participants p
       where p.evaluation_id = v_eval.id
         and p.organization_id = v_eval.organization_id
         and p.valid_from <= v_instante
         and (p.valid_to is null or p.valid_to > v_instante)
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.evaluation_painel_participantes(uuid, uuid) is
  'F6 Incremento 1 (R2): projecao COLETIVA dos participantes vigentes — '
  'identidades, papeis, notas individuais existentes (inclusive colegiado), '
  'comentarios por criterio, Feedbacks Finais e progresso FACTUAL (nao e '
  'completude normativa). SECURITY INVOKER; EXECUTE somente service_role.';

revoke all on function public.evaluation_painel_participantes(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.evaluation_painel_participantes(uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 2) evaluation_leitura_avaliado v2 — projeção SELF pós-CONCLUIDA (R3)
--
-- Substitui a projeção anterior mantendo ASSINATURA e a janela de transparência.
-- Mudanças: (a) REMOVE `colegiado` (lista de identidades correlacionável ao
-- agregado N=1); (b) adiciona `gestao` com os blocos INDIVIDUAIS do gerente e do
-- coordenador (notas, comentários por critério e Feedback Final); (c) adiciona
-- `colegiado_agregado` por SUBCRITÉRIO, sem voto/participant_id/identidade.
-- `comentarios_finais` foi substituído por `gestao.*.feedback_final`.
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_leitura_avaliado(
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
  v_instante timestamptz;
begin
  select e.id, e.organization_id, e.status, e.nota_media, e.config_version_id,
         e.evaluated_collaborator_id, coalesce(e.data_conclusao, now()) as instante
    into v_eval
    from public.evaluations e
   where e.id = p_evaluation_id;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;
  v_instante := v_eval.instante;

  -- o solicitante precisa ser o COLABORADOR AVALIADO (via vinculo membership)
  select l.collaborator_id into v_colaborador
    from public.user_organization_memberships m
    join public.membership_collaborator_links l
      on l.membership_id = m.id and l.status = 'active'
   where m.user_profile_id = p_actor_user_profile_id
     and m.organization_id = v_eval.organization_id
     and m.status = 'active';
  if v_colaborador is null or v_colaborador <> v_eval.evaluated_collaborator_id then
    raise exception 'F5-06: leitura de transparencia restrita ao colaborador avaliado';
  end if;

  -- janela de transparencia: somente avaliacao CONCLUIDA
  if v_eval.status <> 'CONCLUIDA' then
    raise exception 'F5-06: avaliacao ainda nao visivel ao avaliado';
  end if;

  return jsonb_build_object(
    'evaluation_id', v_eval.id,
    'nota_media', v_eval.nota_media,
    'faixa', (
      select jsonb_build_object('nota', b.nota, 'significado', b.significado,
                                'descricao', b.descricao, 'limite_minimo', b.limite_minimo)
        from public.evaluation_config_scale_bands b
       where b.config_version_id = v_eval.config_version_id
         and b.organization_id = v_eval.organization_id
         and b.limite_minimo <= coalesce(v_eval.nota_media, 0)
       order by b.limite_minimo desc
       limit 1
    ),
    'criterios', coalesce((
      select jsonb_agg(jsonb_build_object('criterio', cri.name, 'nota', a.nota)
                       order by cri.position)
        from public.evaluation_aggregates a
        join public.evaluation_config_criteria cri
          on cri.id = a.criterion_id
         and cri.organization_id = v_eval.organization_id
         and cri.config_version_id = v_eval.config_version_id
       where a.evaluation_id = v_eval.id
         and a.organization_id = v_eval.organization_id
         and a.escopo = 'CRITERIO'
    ), '[]'::jsonb),
    'subcriterios', coalesce((
      select jsonb_agg(jsonb_build_object('criterio', cri.name, 'subcriterio', sub.name, 'nota', a.nota)
                       order by cri.position, sub.position)
        from public.evaluation_aggregates a
        join public.evaluation_config_subcriteria sub
          on sub.id = a.subcriterion_id
         and sub.organization_id = v_eval.organization_id
        join public.evaluation_config_criteria cri
          on cri.id = sub.config_criterion_id
         and cri.organization_id = v_eval.organization_id
         and cri.config_version_id = v_eval.config_version_id
       where a.evaluation_id = v_eval.id
         and a.organization_id = v_eval.organization_id
         and a.escopo = 'SUBCRITERIO'
    ), '[]'::jsonb),
    -- R3: blocos INDIVIDUAIS do gerente (GESTAO_CADEIA) e do coordenador
    -- (GESTAO_DIRETA) materializados. Ausência do papel ⇒ `null` (nunca zero).
    'gestao', jsonb_build_object(
      'GESTAO_CADEIA', (
        select jsonb_build_object(
          'presente', true,
          'notas', coalesce((
            select jsonb_agg(jsonb_build_object('subcriterion_id', sc.subcriterion_id,
                                                'nota', sc.nota)
                             order by sc.subcriterion_id)
              from public.evaluation_scores sc
             where sc.evaluation_id = v_eval.id
               and sc.organization_id = v_eval.organization_id
               and sc.participant_id = p.id), '[]'::jsonb),
          'comentarios', coalesce((
            select jsonb_agg(jsonb_build_object('criterion_id', cm.criterion_id,
                                                'texto', cm.texto)
                             order by cm.criterion_id)
              from public.evaluation_comments cm
             where cm.evaluation_id = v_eval.id
               and cm.organization_id = v_eval.organization_id
               and cm.participant_id = p.id
               and cm.escopo = 'CRITERIO'), '[]'::jsonb),
          'feedback_final', (
            select cm.texto
              from public.evaluation_comments cm
             where cm.evaluation_id = v_eval.id
               and cm.organization_id = v_eval.organization_id
               and cm.participant_id = p.id
               and cm.escopo = 'FINAL'
             limit 1)
        )
          from public.evaluation_participants p
         where p.evaluation_id = v_eval.id
           and p.organization_id = v_eval.organization_id
           and p.role_type = 'GESTAO_CADEIA'
           and p.valid_from <= v_instante
           and (p.valid_to is null or p.valid_to > v_instante)
         order by p.valid_from desc, p.id
         limit 1
      ),
      'GESTAO_DIRETA', (
        select jsonb_build_object(
          'presente', true,
          'notas', coalesce((
            select jsonb_agg(jsonb_build_object('subcriterion_id', sc.subcriterion_id,
                                                'nota', sc.nota)
                             order by sc.subcriterion_id)
              from public.evaluation_scores sc
             where sc.evaluation_id = v_eval.id
               and sc.organization_id = v_eval.organization_id
               and sc.participant_id = p.id), '[]'::jsonb),
          'comentarios', coalesce((
            select jsonb_agg(jsonb_build_object('criterion_id', cm.criterion_id,
                                                'texto', cm.texto)
                             order by cm.criterion_id)
              from public.evaluation_comments cm
             where cm.evaluation_id = v_eval.id
               and cm.organization_id = v_eval.organization_id
               and cm.participant_id = p.id
               and cm.escopo = 'CRITERIO'), '[]'::jsonb),
          'feedback_final', (
            select cm.texto
              from public.evaluation_comments cm
             where cm.evaluation_id = v_eval.id
               and cm.organization_id = v_eval.organization_id
               and cm.participant_id = p.id
               and cm.escopo = 'FINAL'
             limit 1)
        )
          from public.evaluation_participants p
         where p.evaluation_id = v_eval.id
           and p.organization_id = v_eval.organization_id
           and p.role_type = 'GESTAO_DIRETA'
           and p.valid_from <= v_instante
           and (p.valid_to is null or p.valid_to > v_instante)
         order by p.valid_from desc, p.id
         limit 1
      )
    ),
    -- R3: COLEGIADO somente como parcela AGREGADA por SUBCRITÉRIO — a mesma
    -- parcela usada pelo cálculo oficial (média dos votos VÁLIDOS dos membros
    -- vigentes; o colegiado pesa como UMA parcela). Nenhum voto individual,
    -- `participant_id` ou identidade correlacionável; N=1 exibe normalmente;
    -- ausência de voto não gera linha (nunca zero).
    'colegiado_agregado', coalesce((
      select jsonb_agg(jsonb_build_object(
               'subcriterion_id', x.subcriterion_id,
               'subcriterio', x.subcriterio,
               'criterio', x.criterio,
               'nota', x.nota)
             order by x.criterio_position, x.subcriterio_position)
        from (
          select sc.subcriterion_id,
                 sub.name as subcriterio,
                 cri.name as criterio,
                 cri.position as criterio_position,
                 sub.position as subcriterio_position,
                 avg(sc.nota) as nota
            from public.evaluation_scores sc
            join public.evaluation_participants p
              on p.id = sc.participant_id
             and p.evaluation_id = sc.evaluation_id
             and p.organization_id = v_eval.organization_id
             and p.role_type = 'COLEGIADO'
             and p.valid_from <= v_instante
             and (p.valid_to is null or p.valid_to > v_instante)
            join public.evaluation_config_participant_roles pcr
              on pcr.config_version_id = v_eval.config_version_id
             and pcr.organization_id = v_eval.organization_id
             and pcr.role_type = 'COLEGIADO'
             and pcr.contributes_to_score
            join public.evaluation_config_subcriteria sub
              on sub.id = sc.subcriterion_id
             and sub.organization_id = v_eval.organization_id
            join public.evaluation_config_criteria cri
              on cri.id = sub.config_criterion_id
             and cri.organization_id = v_eval.organization_id
             and cri.config_version_id = v_eval.config_version_id
           where sc.evaluation_id = v_eval.id
             and sc.organization_id = v_eval.organization_id
           group by sc.subcriterion_id, sub.name, cri.name, cri.position, sub.position
        ) x
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.evaluation_leitura_avaliado(uuid, uuid) is
  'F6 Incremento 1 (R3): projecao SELF pos-CONCLUIDA — agregados oficiais, '
  'blocos individuais de GESTAO_CADEIA/GESTAO_DIRETA e colegiado SOMENTE '
  'agregado por subcriterio (sem voto/participant_id/identidade). SECURITY '
  'INVOKER; EXECUTE somente service_role.';

revoke all on function public.evaluation_leitura_avaliado(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.evaluation_leitura_avaliado(uuid, uuid)
  to service_role;
