-- ============================================================================
-- F5-06 (Issue #103): avaliações — cálculo oficial e RPCs transacionais
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-06-desenho-tecnico.md (D4/D5/D6/D7/D13/D16/D18/D19/D20/
-- D23/D24/D25/D26/D27 FECHADAS).
--
-- Padrão de segurança (idêntico à F5-02/F5-04):
--   - SECURITY INVOKER (nenhum SECURITY DEFINER novo — AC7/F4-08 D9);
--   - EXECUTE concedido SOMENTE a service_role (fronteira confiável server-side);
--   - o ator é o `auth.uid()`/`user_profile_id` VERIFICADO server-side pela Edge
--     Function (auth.getUser) e chega como parâmetro; a função SEMPRE revalida
--     perfil ativo + membership ativa no tenant (D27: service_role não decide
--     autorização — a decisão é do Policy Engine antes da chamada);
--   - mutação crítica + evento na MESMA transação (D26).
--
-- Cálculo oficial (D13/D24/D25): server-side, parcelas por RESPONSABILIDADE
-- configurada (individual = nota do participante; agregada COLEGIADO = média dos
-- votos válidos), sem arredondamento intermediário, `numeric(12,8)`.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) evaluation_aggregates — derivados materializados do cálculo (D13)
-- ----------------------------------------------------------------------------
create table public.evaluation_aggregates (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  evaluation_id   uuid        not null,
  escopo          text        not null,
  criterion_id    uuid,
  subcriterion_id uuid,
  nota            numeric(12,8) not null,
  updated_at      timestamptz not null default now(),
  constraint pk_evaluation_aggregates primary key (id),
  constraint fk_evaluation_aggregates_evaluation
    foreign key (evaluation_id, organization_id)
    references public.evaluations (id, organization_id) on delete restrict,
  constraint fk_evaluation_aggregates_criterion
    foreign key (criterion_id, organization_id)
    references public.evaluation_config_criteria (id, organization_id) on delete restrict,
  constraint fk_evaluation_aggregates_subcriterion
    foreign key (subcriterion_id, organization_id)
    references public.evaluation_config_subcriteria (id, organization_id) on delete restrict,
  constraint ck_evaluation_aggregates_escopo check (escopo in ('CRITERIO', 'SUBCRITERIO')),
  constraint ck_evaluation_aggregates_alvo check (
    (escopo = 'SUBCRITERIO' and subcriterion_id is not null and criterion_id is null)
    or (escopo = 'CRITERIO' and criterion_id is not null and subcriterion_id is null)
  ),
  constraint ck_evaluation_aggregates_nota check (nota >= 0 and nota <= 5)
);

create unique index uq_evaluation_aggregates_alvo
  on public.evaluation_aggregates (evaluation_id, escopo, coalesce(subcriterion_id, criterion_id));

alter table public.evaluation_aggregates enable row level security;
revoke all on public.evaluation_aggregates from anon, authenticated, service_role;
grant select, insert, update, delete on public.evaluation_aggregates to service_role;

comment on table public.evaluation_aggregates is
  'F5-06 D13: derivados MATERIALIZADOS do calculo oficial (por criterio e por '
  'subcriterio). Recomputaveis por evaluation_calcular; a fonte soberana sao as '
  'notas em evaluation_scores.';

-- ----------------------------------------------------------------------------
-- 2) Guard de ator/tenant (D27): perfil ativo + membership ativa na organização
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_ator_valido(
  p_actor_user_profile_id uuid,
  p_organization_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    p_actor_user_profile_id is not null
    and p_organization_id is not null
    and exists (
      select 1
        from public.user_organization_memberships m
        join public.user_profiles up on up.id = m.user_profile_id
       where m.user_profile_id = p_actor_user_profile_id
         and m.organization_id = p_organization_id
         and m.status = 'active'
         and up.status = 'active'
    );
$$;

comment on function public.evaluation_ator_valido(uuid, uuid) is
  'F5-06 D27: revalida ator soberano (perfil ativo + membership ativa no tenant) '
  'em toda funcao server-side. service_role NAO substitui a decisao de '
  'autorizacao do Policy Engine (que ocorre antes, na fronteira confiavel).';

-- ----------------------------------------------------------------------------
-- 3) evaluation_config_bootstrap — configuração baseline versionada (D5/D16/D22)
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_config_bootstrap(
  p_organization_id uuid,
  p_actor_user_profile_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_version_id uuid;
  v_criterios jsonb;
  v_criterio jsonb;
  v_criterion_id uuid;
  v_sub text;
  v_pos int;
  v_codes text[] := array[
  'desempenho-tecnico','produtividade','comunicacao','trabalho-em-equipe',
  'proatividade-e-iniciativa','adaptacao-e-flexibilidade',
  'comprometimento-e-responsabilidade','desenvolvimento-profissional'];
  v_names text[] := array[
  'Desempenho técnico','Produtividade','Comunicação','Trabalho em equipe',
  'Proatividade e iniciativa','Adaptação e flexibilidade',
  'Comprometimento e responsabilidade','Desenvolvimento profissional'];
  v_subs text[][] := array[
    array['Qualidade do trabalho entregue','Cumprimento de prazos','Conhecimento técnico e aplicação prática','Capacidade de resolver problemas'],
    array['Volume de trabalho realizado','Eficiência no uso do tempo','Organização e priorização de tarefas'],
    array['Clareza na comunicação verbal e escrita','Capacidade de ouvir e compreender','Participação em reuniões e interações com a equipe'],
    array['Colaboração com colegas','Respeito e empatia no ambiente de trabalho','Contribuição para um clima positivo'],
    array['Capacidade de tomar decisões sem depender sempre de orientação','Sugestão de melhorias e novas ideias','Disposição para assumir responsabilidades'],
    array['Reação a mudanças e imprevistos','Facilidade de aprender novas ferramentas ou processos','Resiliência diante de desafios'],
    array['Pontualidade e assiduidade','Cumprimento de metas e compromissos','Alinhamento com os valores da empresa'],
    array['Busca por aprendizado contínuo','Participação em treinamentos ou cursos','Aplicação de novos conhecimentos no dia a dia']];
  i int;
  j int;
begin
  if not public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;

  select id into v_version_id
    from public.evaluation_config_versions
   where organization_id = p_organization_id and version = 1;
  if found then
    return v_version_id;
  end if;

  insert into public.evaluation_config_versions
    (organization_id, version, checksum, origem, status)
  values (p_organization_id, 1, 'baseline-f5-06-v1', 'SISTEMA', 'active')
  returning id into v_version_id;

  for i in 1 .. array_length(v_codes, 1) loop
    insert into public.evaluation_config_criteria
      (organization_id, config_version_id, code, name, position)
    values (p_organization_id, v_version_id, v_codes[i], v_names[i], i - 1)
    returning id into v_criterion_id;

    for j in 1 .. array_length(v_subs[i], 1) loop
      insert into public.evaluation_config_subcriteria
        (organization_id, config_criterion_id, code, name, position)
      values (p_organization_id, v_criterion_id,
              v_codes[i] || '-s' || (j - 1), v_subs[i][j], j - 1);
    end loop;
  end loop;

  insert into public.evaluation_config_scale_bands
    (organization_id, config_version_id, nota, significado, descricao, limite_minimo, cor, cor_fundo)
  values
    (p_organization_id, v_version_id, 5, 'Excelente',
     'Desempenho excepcional. Serve como referência para os demais. Alta autonomia e impacto no dia a dia.',
     4.7, '#107C41', '#E7F6EC'),
    (p_organization_id, v_version_id, 4, 'Acima do esperado',
     'Supera expectativas em vários aspectos. Demonstra iniciativa e consistência. Há espaço para melhorias.',
     3.9, '#660099', '#F4EAF8'),
    (p_organization_id, v_version_id, 3, 'Dentro do esperado',
     'Cumpre as responsabilidades de forma adequada. Há espaço para melhorias.',
     2.9, '#8A6D00', '#FFF4CE'),
    (p_organization_id, v_version_id, 2, 'Abaixo do esperado',
     'Performance abaixo do nível esperado pelo cargo. Apresenta dificuldades frequentes e precisa de orientação constante.',
     2.0, '#C94A12', '#FFF0E8'),
    (p_organization_id, v_version_id, 1, 'Insatisfatório',
     'Desempenho insatisfatório, não atende aos requisitos mínimos. Necessita mudança de atitude imediata em curto prazo.',
     1.0, '#A4262C', '#FDE7E9');

  insert into public.evaluation_config_participant_roles
    (organization_id, config_version_id, role_type, required,
     contributes_to_score, requires_final_comment, min_participants, max_participants,
     aggregation_mode, position)
  values
    (p_organization_id, v_version_id, 'GESTAO_CADEIA', true, true, true, 0, 1, 'INDIVIDUAL', 0),
    (p_organization_id, v_version_id, 'GESTAO_DIRETA', false, true, true, 0, 1, 'INDIVIDUAL', 1),
    (p_organization_id, v_version_id, 'COLEGIADO', false, true, false, 0, null, 'AGGREGATED', 2);

  return v_version_id;
end;
$$;

comment on function public.evaluation_config_bootstrap(uuid, uuid) is
  'F5-06 D5/D16/D22: cria a versao 1 de configuracao da organizacao com a '
  'baseline funcional (8 criterios, 25 subcriterios, escala 1..5 e papeis de '
  'responsabilidade). Idempotente. Nenhuma decisao de participante depende de '
  'cargo/job_role/seniority/funcao. EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 4) evaluation_calcular — cálculo OFICIAL server-side (D13/D24/D25)
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_calcular(p_evaluation_id uuid)
returns numeric
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org uuid;
  v_config uuid;
  v_media numeric(12,8);
begin
  select organization_id, config_version_id
    into v_org, v_config
    from public.evaluations
   where id = p_evaluation_id;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;

  -- Subcritério: média das PARCELAS válidas das responsabilidades que
  -- contribuem para o score. Parcela individual = nota do participante;
  -- parcela agregada (COLEGIADO) = média dos votos válidos dos membros.
  delete from public.evaluation_aggregates where evaluation_id = p_evaluation_id;

  insert into public.evaluation_aggregates
    (organization_id, evaluation_id, escopo, subcriterion_id, criterion_id, nota)
  select v_org, p_evaluation_id, 'SUBCRITERIO', p.subcriterion_id, null, p.nota
    from (
      select x.subcriterion_id, avg(x.parcela) as nota
        from (
          select sc.subcriterion_id, part.role_type, avg(sc.nota) as parcela
            from public.evaluation_scores sc
            join public.evaluation_participants part
              on part.id = sc.participant_id
             and part.organization_id = v_org
            join public.evaluation_config_participant_roles pcr
              on pcr.config_version_id = v_config
             and pcr.organization_id = v_org
             and pcr.role_type = part.role_type
             and pcr.contributes_to_score
           where sc.evaluation_id = p_evaluation_id
           group by sc.subcriterion_id, part.role_type
        ) x
       group by x.subcriterion_id
    ) p;

  insert into public.evaluation_aggregates
    (organization_id, evaluation_id, escopo, criterion_id, subcriterion_id, nota)
  select v_org, p_evaluation_id, 'CRITERIO', sc.config_criterion_id, null, avg(a.nota)
    from public.evaluation_aggregates a
    join public.evaluation_config_subcriteria sc
      on sc.id = a.subcriterion_id
     and sc.organization_id = v_org
   where a.evaluation_id = p_evaluation_id
     and a.escopo = 'SUBCRITERIO'
   group by sc.config_criterion_id;

  select avg(a.nota) into v_media
    from public.evaluation_aggregates a
   where a.evaluation_id = p_evaluation_id
     and a.escopo = 'CRITERIO';

  update public.evaluations
     set nota_media = v_media
   where id = p_evaluation_id;

  return v_media;
end;
$$;

comment on function public.evaluation_calcular(uuid) is
  'F5-06 D13/D24/D25: CALCULO OFICIAL server-side. Responsabilidade individual = '
  'UMA parcela com a nota do participante; COLEGIADO = UMA parcela com a media '
  'dos votos validos (nunca peso por membro). Sem arredondamento intermediario '
  '(numeric 12,8). Materializa evaluation_aggregates e evaluations.nota_media. '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 5) evaluation_criar — criação transacional com snapshot de participantes
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_criar(
  p_organization_id uuid,
  p_cycle_id uuid,
  p_evaluated_collaborator_id uuid,
  p_config_version_id uuid,
  p_participants jsonb,
  p_actor_user_profile_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
  v_status text;
  v_item jsonb;
begin
  if not public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;

  select status into v_status from public.evaluation_cycles
   where id = p_cycle_id and organization_id = p_organization_id;
  if not found then
    raise exception 'F5-06: ciclo inexistente ou de outro tenant';
  end if;
  if v_status not in ('PLANEJADO', 'ATIVO') then
    raise exception 'F5-06: ciclo nao permite nova avaliacao (status %)', v_status;
  end if;

  if not exists (
    select 1 from public.collaborators
     where id = p_evaluated_collaborator_id and organization_id = p_organization_id
  ) then
    raise exception 'F5-06: colaborador avaliado de outro tenant ou inexistente';
  end if;

  if not exists (
    select 1 from public.evaluation_config_versions
     where id = p_config_version_id and organization_id = p_organization_id
  ) then
    raise exception 'F5-06: versao de configuracao de outro tenant ou inexistente';
  end if;

  insert into public.evaluations
    (organization_id, cycle_id, evaluated_collaborator_id, config_version_id, status)
  values (p_organization_id, p_cycle_id, p_evaluated_collaborator_id,
          p_config_version_id, 'RASCUNHO')
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(coalesce(p_participants, '[]'::jsonb)) loop
    insert into public.evaluation_participants
      (organization_id, evaluation_id, role_type, collaborator_id, user_profile_id,
       origem, origem_ref_id, valid_from, status)
    values (
      p_organization_id, v_id,
      v_item ->> 'role_type',
      (v_item ->> 'collaborator_id')::uuid,
      nullif(v_item ->> 'user_profile_id', '')::uuid,
      coalesce(nullif(v_item ->> 'origem', ''), 'ESTRUTURA'),
      nullif(v_item ->> 'origem_ref_id', '')::uuid,
      coalesce(nullif(v_item ->> 'valid_from', '')::timestamptz, now()),
      'active'
    );
  end loop;

  insert into public.evaluation_events
    (organization_id, evaluation_id, event_type, actor_user_profile_id, entidade, valor_novo)
  values (p_organization_id, v_id, 'CRIADA', p_actor_user_profile_id, 'evaluations',
          jsonb_build_object('cycle_id', p_cycle_id,
                             'evaluated_collaborator_id', p_evaluated_collaborator_id,
                             'config_version_id', p_config_version_id));

  perform public.evaluation_calcular(v_id);
  return v_id;
end;
$$;

comment on function public.evaluation_criar(uuid, uuid, uuid, uuid, jsonb, uuid) is
  'F5-06 D23/D26/D27: cria a avaliacao + snapshot de OCORRENCIAS de participante '
  'e grava o evento CRIADA na MESMA transacao. O snapshot e montado pela '
  'fronteira confiavel a partir das fontes F3 (collegiate_cycle_snapshots, '
  'cycle_evaluation_responsibilities, temporary_responsibilities, sucessao). '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 6) evaluation_gravar_notas / comentário — lote transacional
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_gravar_notas(
  p_evaluation_id uuid,
  p_participant_id uuid,
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
  v_item jsonb;
  v_nota smallint;
begin
  select organization_id, status into v_org, v_status
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
  if not exists (
    select 1 from public.evaluation_participants
     where id = p_participant_id and evaluation_id = p_evaluation_id and organization_id = v_org
  ) then
    raise exception 'F5-06: participante (ocorrencia) nao pertence a avaliacao';
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_notas, '[]'::jsonb)) loop
    v_nota := (v_item ->> 'nota')::smallint;
    if v_nota is null or v_nota < 1 or v_nota > 5 then
      raise exception 'F5-06: nota invalida (esperado 1..5)';
    end if;
    insert into public.evaluation_scores
      (organization_id, evaluation_id, participant_id, subcriterion_id, nota,
       autor_user_profile_id, data_avaliacao)
    values (v_org, p_evaluation_id, p_participant_id,
            (v_item ->> 'subcriterion_id')::uuid, v_nota,
            p_actor_user_profile_id, now())
    on conflict (participant_id, subcriterion_id) do update
      set nota = excluded.nota,
          autor_user_profile_id = excluded.autor_user_profile_id,
          data_avaliacao = excluded.data_avaliacao,
          version = public.evaluation_scores.version + 1;
  end loop;

  insert into public.evaluation_events
    (organization_id, evaluation_id, event_type, actor_user_profile_id, entidade, entidade_id, valor_novo)
  values (v_org, p_evaluation_id, 'NOTA_ALTERADA', p_actor_user_profile_id,
          'evaluation_scores', p_participant_id,
          jsonb_build_object('notas', coalesce(p_notas, '[]'::jsonb)));

  return public.evaluation_calcular(p_evaluation_id);
end;
$$;

create or replace function public.evaluation_gravar_comentario(
  p_evaluation_id uuid,
  p_participant_id uuid,
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
begin
  if p_escopo not in ('CRITERIO', 'FINAL') then
    raise exception 'F5-06: escopo de comentario invalido';
  end if;
  if p_texto is null or btrim(p_texto) = '' then
    raise exception 'F5-06: comentario vazio';
  end if;

  select organization_id, status into v_org, v_status
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

  insert into public.evaluation_comments
    (organization_id, evaluation_id, participant_id, escopo, criterion_id, texto,
     autor_user_profile_id, data)
  values (v_org, p_evaluation_id, p_participant_id, p_escopo, p_criterion_id,
          btrim(p_texto), p_actor_user_profile_id, now())
  on conflict (participant_id, escopo, criterion_id) do update
    set texto = excluded.texto,
        autor_user_profile_id = excluded.autor_user_profile_id,
        data = excluded.data,
        version = public.evaluation_comments.version + 1;

  insert into public.evaluation_events
    (organization_id, evaluation_id, event_type, actor_user_profile_id, entidade, entidade_id, valor_novo)
  values (v_org, p_evaluation_id, 'COMENTARIO_ALTERADO', p_actor_user_profile_id,
          'evaluation_comments', p_participant_id,
          jsonb_build_object('escopo', p_escopo, 'criterion_id', p_criterion_id));
end;
$$;

-- ----------------------------------------------------------------------------
-- 7) evaluation_pendencias_calcular — completude conforme configuração congelada
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_pendencias_calcular(p_evaluation_id uuid)
returns table (codigo text, role_type text, participant_id uuid, subcriterion_id uuid, descricao text)
language sql
stable
security invoker
set search_path = public
as $$
  with aval as (
    select e.id, e.organization_id, e.config_version_id
      from public.evaluations e where e.id = p_evaluation_id
  ),
  cfg as (
    select pcr.role_type, pcr.required, pcr.contributes_to_score, pcr.requires_final_comment,
           pcr.min_participants, pcr.max_participants
      from public.evaluation_config_participant_roles pcr
      join aval a on a.config_version_id = pcr.config_version_id
  ),
  ativos as (
    select p.role_type, count(*)::int as qtd
      from public.evaluation_participants p
      join aval a on a.id = p.evaluation_id
     where p.status = 'active'
     group by p.role_type
  ),
  -- participação obrigatória ausente/insuficiente
  p1 as (
    select 'PARTICIPANTE_OBRIGATORIO_AUSENTE'::text as codigo, c.role_type,
           null::uuid as participant_id, null::uuid as subcriterion_id,
           ('Participante obrigatorio ausente: ' || c.role_type)::text as descricao
      from cfg c
      left join ativos a on a.role_type = c.role_type
     where c.required and coalesce(a.qtd, 0) < greatest(c.min_participants, 1)
  ),
  -- notas faltantes por responsabilidade contribuinte (por subcritério)
  p2 as (
    select 'NOTA_FALTANTE'::text, c.role_type, null::uuid, sub.id,
           ('Nota faltante em ' || c.role_type || ': ' || sub.name)
      from cfg c
      join aval av on true
      join public.evaluation_config_subcriteria sub on sub.organization_id = av.organization_id
      join public.evaluation_config_criteria cri on cri.id = sub.config_criterion_id
     where c.contributes_to_score
       and cri.config_version_id = av.config_version_id
       and exists (
         select 1 from public.evaluation_participants p
          where p.evaluation_id = av.id and p.role_type = c.role_type and p.status = 'active'
       )
       and not exists (
         select 1
           from public.evaluation_scores sc
           join public.evaluation_participants p on p.id = sc.participant_id
          where sc.evaluation_id = av.id
            and sc.subcriterion_id = sub.id
            and p.role_type = c.role_type
            and p.status = 'active'
       )
  ),
  -- feedback final obrigatório ausente
  p3 as (
    select 'FEEDBACK_FINAL_FALTANTE'::text, c.role_type, null::uuid, null::uuid,
           ('Feedback final faltante: ' || c.role_type)
      from cfg c
      join aval av on true
     where c.requires_final_comment
       and exists (
         select 1 from public.evaluation_participants p
          where p.evaluation_id = av.id and p.role_type = c.role_type and p.status = 'active'
       )
       and not exists (
         select 1
           from public.evaluation_comments cm
           join public.evaluation_participants p on p.id = cm.participant_id
          where cm.evaluation_id = av.id
            and cm.escopo = 'FINAL'
            and p.role_type = c.role_type
            and p.status = 'active'
       )
  )
  select * from p1 union all select * from p2 union all select * from p3;
$$;

comment on function public.evaluation_pendencias_calcular(uuid) is
  'F5-06 D18/D19: completude conforme a CONFIGURACAO CONGELADA. Participante '
  'obrigatorio ausente, nota faltante em responsabilidade contribuinte e '
  'feedback final obrigatorio. Membros de colegiado sem voto nao viram zero: '
  'geram pendencia quando o papel e obrigatorio. EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 8) evaluation_concluir / reabrir / cancelar — transições auditadas (D8/D18)
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_concluir(
  p_evaluation_id uuid,
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
  v_pend int;
begin
  select organization_id, status into v_org, v_status
    from public.evaluations where id = p_evaluation_id for update;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;
  if v_status = 'CANCELADA' then
    raise exception 'F5-06: avaliacao cancelada nao pode ser concluida';
  end if;
  if v_status = 'CONCLUIDA' then
    raise exception 'F5-06: avaliacao ja concluida';
  end if;

  select count(*) into v_pend from public.evaluation_pendencias_calcular(p_evaluation_id);
  if v_pend > 0 then
    raise exception 'F5-06: conclusao normal exige completude (pendencias=%)', v_pend;
  end if;

  perform public.evaluation_calcular(p_evaluation_id);

  update public.evaluations
     set status = 'CONCLUIDA', data_conclusao = now(), version = version + 1
   where id = p_evaluation_id;

  insert into public.evaluation_events
    (organization_id, evaluation_id, event_type, actor_user_profile_id, entidade, valor_novo)
  values (v_org, p_evaluation_id, 'CONCLUIDA', p_actor_user_profile_id, 'evaluations',
          jsonb_build_object('status', 'CONCLUIDA'));
end;
$$;

create or replace function public.evaluation_reabrir(
  p_evaluation_id uuid,
  p_motivo text,
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
  v_anterior jsonb;
begin
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'F5-06: motivo da reabertura e obrigatorio';
  end if;

  select organization_id, status, jsonb_build_object('status', status, 'data_conclusao', data_conclusao)
    into v_org, v_status, v_anterior
    from public.evaluations where id = p_evaluation_id for update;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;
  if v_status <> 'CONCLUIDA' then
    raise exception 'F5-06: reabertura exige avaliacao CONCLUIDA (status atual %)', v_status;
  end if;

  update public.evaluations
     set status = 'RASCUNHO', data_conclusao = null, version = version + 1
   where id = p_evaluation_id;

  insert into public.evaluation_events
    (organization_id, evaluation_id, event_type, actor_user_profile_id, motivo,
     entidade, valor_anterior, valor_novo)
  values (v_org, p_evaluation_id, 'REABERTA', p_actor_user_profile_id, btrim(p_motivo),
          'evaluations', v_anterior, jsonb_build_object('status', 'RASCUNHO'));
end;
$$;

create or replace function public.evaluation_cancelar(
  p_evaluation_id uuid,
  p_motivo text,
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
begin
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'F5-06: motivo do cancelamento e obrigatorio';
  end if;

  select organization_id, status into v_org, v_status
    from public.evaluations where id = p_evaluation_id for update;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;
  if v_status = 'CANCELADA' then
    raise exception 'F5-06: avaliacao ja cancelada';
  end if;

  update public.evaluations
     set status = 'CANCELADA',
         motivo_cancelamento = btrim(p_motivo),
         cancelado_por_user_profile_id = p_actor_user_profile_id,
         data_cancelamento = now(),
         version = version + 1
   where id = p_evaluation_id;

  insert into public.evaluation_events
    (organization_id, evaluation_id, event_type, actor_user_profile_id, motivo,
     entidade, valor_anterior, valor_novo)
  values (v_org, p_evaluation_id, 'CANCELADA', p_actor_user_profile_id, btrim(p_motivo),
          'evaluations', jsonb_build_object('status', v_status),
          jsonb_build_object('status', 'CANCELADA'));
end;
$$;

-- ----------------------------------------------------------------------------
-- 9) evaluation_fechar_ciclo_pendencias — marcador permanente (D11/D18)
-- ----------------------------------------------------------------------------
create or replace function public.evaluation_fechar_ciclo_pendencias(
  p_cycle_id uuid,
  p_organization_id uuid,
  p_actor_user_profile_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_eval record;
  v_pend record;
  v_total int := 0;
  v_qtd int;
begin
  if not public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;
  if not exists (
    select 1 from public.evaluation_cycles
     where id = p_cycle_id and organization_id = p_organization_id
  ) then
    raise exception 'F5-06: ciclo inexistente ou de outro tenant';
  end if;

  for v_eval in
    select id from public.evaluations
     where cycle_id = p_cycle_id
       and organization_id = p_organization_id
       and status not in ('CONCLUIDA', 'CANCELADA')
       and encerrada_com_pendencias = false
     for update
  loop
    select count(*) into v_qtd from public.evaluation_pendencias_calcular(v_eval.id);
    if v_qtd > 0 then
      for v_pend in select * from public.evaluation_pendencias_calcular(v_eval.id) loop
        insert into public.evaluation_pendencies
          (organization_id, evaluation_id, codigo, role_type, participant_id,
           criterion_id, subcriterion_id, descricao, registrada_por_user_profile_id)
        values (p_organization_id, v_eval.id, v_pend.codigo, v_pend.role_type,
                v_pend.participant_id, null, v_pend.subcriterion_id, v_pend.descricao,
                p_actor_user_profile_id);
      end loop;

      update public.evaluations
         set encerrada_com_pendencias = true, version = version + 1
       where id = v_eval.id;

      insert into public.evaluation_events
        (organization_id, evaluation_id, event_type, actor_user_profile_id, motivo,
         entidade, valor_novo)
      values (p_organization_id, v_eval.id, 'PENDENCIA_MARCADA',
              p_actor_user_profile_id, 'Fechamento de ciclo com avaliacao incompleta',
              'evaluations', jsonb_build_object('pendencias', v_qtd));

      v_total := v_total + 1;
    end if;
  end loop;

  update public.evaluation_cycles
     set encerrado_com_pendencias = v_total > 0,
         quantidade_pendencias = v_total,
         version = version + 1
   where id = p_cycle_id and organization_id = p_organization_id;

  return v_total;
end;
$$;

comment on function public.evaluation_fechar_ciclo_pendencias(uuid, uuid, uuid) is
  'F5-06 D11/D18: no fechamento do ciclo, avaliacoes incompletas recebem '
  'MARCADOR PERMANENTE + pendencias persistidas SEM serem convertidas em '
  'CONCLUIDA. Idempotente (nao remarca) e transacional. EXECUTE somente '
  'service_role.';

-- ----------------------------------------------------------------------------
-- 10) evaluation_leitura_avaliado — transparência server-side (D20)
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
  v_resultado jsonb;
begin
  select e.id, e.organization_id, e.status, e.nota_media, e.config_version_id,
         e.evaluated_collaborator_id
    into v_eval
    from public.evaluations e
   where e.id = p_evaluation_id;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;

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

  -- janela de transparência: somente avaliação CONCLUIDA
  if v_eval.status <> 'CONCLUIDA' then
    raise exception 'F5-06: avaliacao ainda nao visivel ao avaliado';
  end if;

  select jsonb_build_object(
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
      select jsonb_agg(jsonb_build_object('criterio', cri.name, 'nota', a.nota) order by cri.position)
        from public.evaluation_aggregates a
        join public.evaluation_config_criteria cri on cri.id = a.criterion_id
       where a.evaluation_id = v_eval.id and a.escopo = 'CRITERIO'
    ), '[]'::jsonb),
    'subcriterios', coalesce((
      select jsonb_agg(jsonb_build_object('criterio', cri.name, 'subcriterio', sub.name, 'nota', a.nota)
                       order by cri.position, sub.position)
        from public.evaluation_aggregates a
        join public.evaluation_config_subcriteria sub on sub.id = a.subcriterion_id
        join public.evaluation_config_criteria cri on cri.id = sub.config_criterion_id
       where a.evaluation_id = v_eval.id and a.escopo = 'SUBCRITERIO'
    ), '[]'::jsonb),
    'colegiado', coalesce((
      select jsonb_agg(distinct jsonb_build_object('colaborador', col.nome))
        from public.evaluation_participants p
        join public.collaborators col on col.id = p.collaborator_id
       where p.evaluation_id = v_eval.id
         and p.role_type = 'COLEGIADO'
         and p.status = 'active'
    ), '[]'::jsonb),
    'comentarios_finais', coalesce((
      select jsonb_agg(jsonb_build_object('role_type', p.role_type, 'texto', cm.texto))
        from public.evaluation_comments cm
        join public.evaluation_participants p on p.id = cm.participant_id
        join public.evaluation_config_participant_roles pcr
          on pcr.config_version_id = v_eval.config_version_id
         and pcr.role_type = p.role_type
         and pcr.requires_final_comment
       where cm.evaluation_id = v_eval.id
         and cm.escopo = 'FINAL'
         and p.status = 'active'
    ), '[]'::jsonb)
  ) into v_resultado;

  -- NUNCA expõe voto/nota individual, participant_id correlacionado nem
  -- comentário interno: a projeção acima é a única superfície do avaliado.
  return v_resultado;
end;
$$;

comment on function public.evaluation_leitura_avaliado(uuid, uuid) is
  'F5-06 D20: projecao server-side de transparencia do AVALIADO. Retorna '
  'nota_media, agregados por criterio/subcriterio, faixa da escala congelada, '
  'lista de membros do colegiado e comentarios finais destinados ao avaliado. '
  'NUNCA retorna voto/nota individual nem participant_id correlacionado. '
  'EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 11) Grants: EXECUTE somente service_role (sem superfície para authenticated)
-- ----------------------------------------------------------------------------
revoke all on function public.evaluation_ator_valido(uuid, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_config_bootstrap(uuid, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_calcular(uuid) from public, anon, authenticated;
revoke all on function public.evaluation_criar(uuid, uuid, uuid, uuid, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_gravar_notas(uuid, uuid, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_gravar_comentario(uuid, uuid, text, uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_pendencias_calcular(uuid) from public, anon, authenticated;
revoke all on function public.evaluation_concluir(uuid, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_reabrir(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_cancelar(uuid, text, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_fechar_ciclo_pendencias(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_leitura_avaliado(uuid, uuid) from public, anon, authenticated;

grant execute on function public.evaluation_ator_valido(uuid, uuid) to service_role;
grant execute on function public.evaluation_config_bootstrap(uuid, uuid) to service_role;
grant execute on function public.evaluation_calcular(uuid) to service_role;
grant execute on function public.evaluation_criar(uuid, uuid, uuid, uuid, jsonb, uuid) to service_role;
grant execute on function public.evaluation_gravar_notas(uuid, uuid, jsonb, uuid) to service_role;
grant execute on function public.evaluation_gravar_comentario(uuid, uuid, text, uuid, text, uuid) to service_role;
grant execute on function public.evaluation_pendencias_calcular(uuid) to service_role;
grant execute on function public.evaluation_concluir(uuid, uuid) to service_role;
grant execute on function public.evaluation_reabrir(uuid, text, uuid) to service_role;
grant execute on function public.evaluation_cancelar(uuid, text, uuid) to service_role;
grant execute on function public.evaluation_fechar_ciclo_pendencias(uuid, uuid, uuid) to service_role;
grant execute on function public.evaluation_leitura_avaliado(uuid, uuid) to service_role;
