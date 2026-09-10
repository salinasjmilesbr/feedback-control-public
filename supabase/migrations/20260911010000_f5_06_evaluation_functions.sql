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
  -- Array PLANO de subcriterios (a ordem segue os criterios acima) + quantos
  -- subcriterios pertencem a cada criterio. Evita array multidimensional
  -- irregular (nao suportado pelo PostgreSQL: 4 subcriterios no 1o criterio,
  -- 3 nos demais => 25 subcriterios no total).
  v_subs text[] := array[
    'Qualidade do trabalho entregue','Cumprimento de prazos','Conhecimento técnico e aplicação prática','Capacidade de resolver problemas',
    'Volume de trabalho realizado','Eficiência no uso do tempo','Organização e priorização de tarefas',
    'Clareza na comunicação verbal e escrita','Capacidade de ouvir e compreender','Participação em reuniões e interações com a equipe',
    'Colaboração com colegas','Respeito e empatia no ambiente de trabalho','Contribuição para um clima positivo',
    'Capacidade de tomar decisões sem depender sempre de orientação','Sugestão de melhorias e novas ideias','Disposição para assumir responsabilidades',
    'Reação a mudanças e imprevistos','Facilidade de aprender novas ferramentas ou processos','Resiliência diante de desafios',
    'Pontualidade e assiduidade','Cumprimento de metas e compromissos','Alinhamento com os valores da empresa',
    'Busca por aprendizado contínuo','Participação em treinamentos ou cursos','Aplicação de novos conhecimentos no dia a dia'];
  v_qtd_subs int[] := array[4, 3, 3, 3, 3, 3, 3, 3];
  i int;
  j int;
  v_idx int := 1;
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

    for j in 1 .. v_qtd_subs[i] loop
      insert into public.evaluation_config_subcriteria
        (organization_id, config_criterion_id, code, name, position)
      values (p_organization_id, v_criterion_id,
              v_codes[i] || '-s' || (j - 1), v_subs[v_idx], j - 1);
      v_idx := v_idx + 1;
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
  v_instante timestamptz;
  v_media numeric(12,8);
begin
  select organization_id, config_version_id into v_org, v_config
    from public.evaluations
   where id = p_evaluation_id;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;

  -- Instante SOBERANO de referência: a conclusão quando existir, senão now().
  -- A vigência das ocorrências é sempre avaliada contra ele (D23).
  select coalesce(e.data_conclusao, now()) into v_instante
    from public.evaluations e where e.id = p_evaluation_id;

  -- Subcritério: média das PARCELAS VÁLIDAS das responsabilidades que
  -- contribuem para o score, conforme a CONFIGURAÇÃO CONGELADA (D6/D25).
  -- Parcela individual = média das notas do papel; parcela agregada
  -- (COLEGIADO, aggregation_mode = AGGREGATED) = média dos votos VÁLIDOS dos
  -- membros vigentes. Cada RESPONSABILIDADE pesa como UMA parcela — o
  -- colegiado nunca pesa por membro.
  delete from public.evaluation_aggregates where evaluation_id = p_evaluation_id;

  insert into public.evaluation_aggregates
    (organization_id, evaluation_id, escopo, subcriterion_id, criterion_id, nota)
  select v_org, p_evaluation_id, 'SUBCRITERIO', p.subcriterion_id, null, p.parcela
    from (
      select x.subcriterion_id, avg(x.parcela) as parcela
        from (
          select sc.subcriterion_id, avg(sc.nota) as parcela
            from public.evaluation_scores sc
            join public.evaluation_participants part
              on part.id = sc.participant_id
             and part.evaluation_id = sc.evaluation_id
             and part.organization_id = v_org
             and part.valid_from <= v_instante
             and (part.valid_to is null or part.valid_to > v_instante)
            join public.evaluation_config_participant_roles pcr
              on pcr.config_version_id = v_config
             and pcr.organization_id = v_org
             and pcr.role_type = part.role_type
             and pcr.contributes_to_score
            join public.evaluation_config_subcriteria sub
              on sub.id = sc.subcriterion_id
             and sub.organization_id = v_org
            join public.evaluation_config_criteria cri
              on cri.id = sub.config_criterion_id
             and cri.organization_id = v_org
             and cri.config_version_id = v_config
           where sc.evaluation_id = p_evaluation_id
             and sc.organization_id = v_org
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
    join public.evaluation_config_criteria cri
      on cri.id = sc.config_criterion_id
     and cri.organization_id = v_org
     and cri.config_version_id = v_config
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
  'F5-06 D6/D13/D23/D24/D25: CALCULO OFICIAL server-side. Usa somente '
  'ocorrencias VIGENTES no instante soberano (conclusao quando houver, senao '
  'now()) e somente subcriterios da CONFIGURACAO CONGELADA da avaliacao. Cada '
  'RESPONSABILIDADE contribui como UMA parcela: individual = media das notas do '
  'papel; COLEGIADO (AGGREGATED) = media dos votos validos. Sem arredondamento '
  'intermediario (numeric 12,8). EXECUTE somente service_role.';

create or replace function public.evaluation_snapshot_participantes(
  p_organization_id uuid,
  p_evaluation_id uuid,
  p_evaluated_collaborator_id uuid,
  p_cycle_id uuid,
  p_instante timestamptz,
  p_actor_user_profile_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_ano integer;
  v_numero integer;
  v_snapshot uuid;
  v_ref timestamptz;
  v_qtd integer := 0;
  v_direta uuid;
  v_direta_origem text;
  v_direta_ref uuid;
  v_cadeia uuid;
  v_cadeia_origem text;
  v_cadeia_ref uuid;
begin
  if not public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;

  -- Fonte soberana do ciclo: a própria linha evaluation_cycles (D15).
  select c.ano, c.numero into v_ano, v_numero
    from public.evaluation_cycles c
   where c.id = p_cycle_id and c.organization_id = p_organization_id;
  if not found then
    raise exception 'F5-06: ciclo inexistente ou de outro tenant';
  end if;

  -- Snapshot F3-08 congelado do avaliado (fonte do colegiado e da data de
  -- referência). Sem snapshot materializado não há derivação possível.
  select s.id, s.reference_date into v_snapshot, v_ref
    from public.collegiate_cycle_snapshots s
   where s.organization_id = p_organization_id
     and s.ano = v_ano
     and s.ciclo = v_numero
     and s.collaborator_id = p_evaluated_collaborator_id;

  if v_snapshot is null then
    raise exception 'F5-06 D16/D23: snapshot de ciclo (F3-08) inexistente para '
      'o avaliado — materialize o colegiado/responsabilidades do ciclo antes de '
      'abrir a avaliacao';
  end if;

  -- GESTAO_DIRETA e GESTAO_CADEIA derivam da MESMA fonte soberana F3-07/F3-09
  -- (responsável avaliativo vigente por posição). A distinção é a posição na
  -- cadeia: CADEIA = raiz (maior profundidade); DIRETA = gestor formal direto
  -- (menor profundidade). Nenhuma consulta a cargo/job_role/seniority/funcao
  -- (D16/D17) e nenhuma decisão vem do payload do chamador.
  select g.manager_responsible_collaborator_id,
         case when g.manager_substitute_collaborator_id is not null
              then 'SUBSTITUICAO_TEMPORARIA' else 'ESTRUTURA' end,
         g.manager_position_id
    into v_direta, v_direta_origem, v_direta_ref
    from public.organizacao_resolver_gestor_direto(
      p_evaluated_collaborator_id, coalesce(v_ref, p_instante)
    ) g
   where g.manager_responsible_collaborator_id is not null
   order by g.occupied_position_id
   limit 1;

  select ch.responsible_collaborator_id,
         case when ch.substitute_collaborator_id is not null
              then 'SUBSTITUICAO_TEMPORARIA' else 'ESTRUTURA' end,
         ch.position_id
    into v_cadeia, v_cadeia_origem, v_cadeia_ref
    from public.organizacao_resolver_cadeia(
      p_evaluated_collaborator_id, coalesce(v_ref, p_instante)
    ) ch
   where ch.depth >= 1
     and ch.responsible_collaborator_id is not null
   order by ch.depth desc, ch.position_id
   limit 1;

  -- GESTAO_CADEIA (obrigatória na configuração baseline). A ocorrência sempre
  -- tem vigência explícita; ausência de responsável vira PENDÊNCIA de
  -- completude — nunca linha artificial em branco.
  if v_cadeia is not null then
    insert into public.evaluation_participants
      (organization_id, evaluation_id, role_type, collaborator_id,
       origem, origem_ref_id, valid_from, status)
    values (p_organization_id, p_evaluation_id, 'GESTAO_CADEIA', v_cadeia,
            v_cadeia_origem, v_cadeia_ref, coalesce(v_ref, p_instante), 'active');
    v_qtd := v_qtd + 1;
  end if;

  -- GESTAO_DIRETA: apenas quando o gestor formal direto NÃO for o mesmo
  -- responsável de cadeia (evita contar a mesma pessoa como duas parcelas).
  if v_direta is not null and v_direta is distinct from v_cadeia then
    insert into public.evaluation_participants
      (organization_id, evaluation_id, role_type, collaborator_id,
       origem, origem_ref_id, valid_from, status)
    values (p_organization_id, p_evaluation_id, 'GESTAO_DIRETA', v_direta,
            v_direta_origem, v_direta_ref, coalesce(v_ref, p_instante), 'active');
    v_qtd := v_qtd + 1;
  end if;

  -- COLEGIADO: snapshot soberano 0..N congelado no ciclo (F3-08).
  insert into public.evaluation_participants
    (organization_id, evaluation_id, role_type, collaborator_id,
     origem, origem_ref_id, valid_from, status)
  select p_organization_id, p_evaluation_id, 'COLEGIADO', m.member_collaborator_id,
         'SNAPSHOT_CICLO', m.snapshot_id, coalesce(v_ref, p_instante), 'active'
    from public.collegiate_cycle_snapshot_members m
   where m.snapshot_id = v_snapshot
     and m.organization_id = p_organization_id
     and m.member_collaborator_id <> p_evaluated_collaborator_id
   order by m.member_collaborator_id;

  v_qtd := v_qtd + coalesce((
    select count(*)::int from public.collegiate_cycle_snapshot_members m
     where m.snapshot_id = v_snapshot
       and m.organization_id = p_organization_id
       and m.member_collaborator_id <> p_evaluated_collaborator_id
  ), 0);

  return v_qtd;
end;
$$;

comment on function public.evaluation_snapshot_participantes(uuid, uuid, uuid, uuid, timestamptz, uuid) is
  'F5-06 D16/D17/D23: deriva SERVER-SIDE o snapshot de ocorrencias de '
  'participante das fontes soberanas do ciclo (collegiate_cycle_snapshots(+'
  '_members) para COLEGIADO e organizacao_resolver_gestor_direto/_cadeia para '
  'GESTAO_DIRETA/GESTAO_CADEIA). Nenhum collaborator_id/role_type/vigencia vem '
  'do cliente; nenhuma consulta a cargo/funcao/job_role/seniority. EXECUTE '
  'somente service_role.';

create or replace function public.evaluation_criar(
  p_organization_id uuid,
  p_cycle_id uuid,
  p_evaluated_collaborator_id uuid,
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
  v_config uuid;
  v_qtd int;
begin
  if not public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;

  -- A versão de configuração NAO vem do payload: e a versao soberana do ciclo,
  -- congelada na avaliacao no instante da abertura (D6/D15).
  select status, config_version_id into v_status, v_config
    from public.evaluation_cycles
   where id = p_cycle_id and organization_id = p_organization_id;
  if not found then
    raise exception 'F5-06: ciclo inexistente ou de outro tenant';
  end if;
  if v_status not in ('PLANEJADO', 'ATIVO') then
    raise exception 'F5-06: ciclo nao permite nova avaliacao (status %)', v_status;
  end if;
  if v_config is null then
    raise exception 'F5-06: ciclo sem versao de configuracao congelada';
  end if;
  if not exists (
    select 1 from public.evaluation_config_versions v
     where v.id = v_config and v.organization_id = p_organization_id
  ) then
    raise exception 'F5-06: versao de configuracao do ciclo indisponivel';
  end if;

  if not exists (
    select 1 from public.collaborators
     where id = p_evaluated_collaborator_id and organization_id = p_organization_id
  ) then
    raise exception 'F5-06: colaborador avaliado de outro tenant ou inexistente';
  end if;

  insert into public.evaluations
    (organization_id, cycle_id, evaluated_collaborator_id, config_version_id, status)
  values (p_organization_id, p_cycle_id, p_evaluated_collaborator_id,
          v_config, 'RASCUNHO')
  returning id into v_id;

  v_qtd := public.evaluation_snapshot_participantes(
    p_organization_id, v_id, p_evaluated_collaborator_id, p_cycle_id, now(),
    p_actor_user_profile_id);

  insert into public.evaluation_events
    (organization_id, evaluation_id, event_type, actor_user_profile_id,
     entidade, entidade_id, valor_novo)
  values (p_organization_id, v_id, 'CRIADA', p_actor_user_profile_id,
          'evaluations', v_id,
          jsonb_build_object('cycle_id', p_cycle_id,
                             'evaluated_collaborator_id', p_evaluated_collaborator_id,
                             'config_version_id', v_config,
                             'participantes', v_qtd));

  perform public.evaluation_calcular(v_id);
  return v_id;
end;
$$;

comment on function public.evaluation_criar(uuid, uuid, uuid, uuid) is
  'F5-06 D6/D16/D17/D23/D26/D27: cria a avaliacao usando a versao de '
  'configuracao SOBERANA do ciclo (nunca do payload), snapshotando as '
  'ocorrencias de participante server-side e gravando o evento CRIADA na MESMA '
  'transacao. EXECUTE somente service_role.';

create or replace function public.evaluation_participante_realinhar(
  p_evaluation_id uuid,
  p_motivo text,
  p_actor_user_profile_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_org uuid;
  v_status text;
  v_avaliado uuid;
  v_cycle uuid;
  v_instante timestamptz;
  v_alteradas int := 0;
  v_item record;
  v_cadeia_vigente uuid;
begin
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'F5-06: motivo do realinhamento de participantes e obrigatorio';
  end if;

  select organization_id, status, evaluated_collaborator_id, cycle_id
    into v_org, v_status, v_avaliado, v_cycle
    from public.evaluations where id = p_evaluation_id for update;
  if not found then
    raise exception 'F5-06: avaliacao inexistente';
  end if;
  if not public.evaluation_ator_valido(p_actor_user_profile_id, v_org) then
    raise exception 'F5-06: ator sem membership ativa na organizacao (autorizacao negada)';
  end if;
  if v_status in ('CONCLUIDA', 'CANCELADA') then
    raise exception 'F5-06: avaliacao % e imutavel (reabra antes de alterar participantes)', v_status;
  end if;

  v_instante := now();

  -- Conjunto derivado das fontes soberanas atuais.
  drop table if exists pg_temp.f5_06_derivado;
  create temporary table pg_temp.f5_06_derivado (role_type text, collaborator_id uuid)
    on commit drop;

  insert into pg_temp.f5_06_derivado (role_type, collaborator_id)
  select 'COLEGIADO', m.member_collaborator_id
    from public.collegiate_cycle_snapshots s
    join public.collegiate_cycle_snapshot_members m
      on m.snapshot_id = s.id and m.organization_id = s.organization_id
    join public.evaluation_cycles c
      on c.organization_id = s.organization_id and c.ano = s.ano and c.numero = s.ciclo
   where s.organization_id = v_org
     and c.id = v_cycle
     and s.collaborator_id = v_avaliado
     and m.member_collaborator_id <> v_avaliado
  union
  select 'GESTAO_CADEIA', ch.responsible_collaborator_id
    from public.organizacao_resolver_cadeia(v_avaliado, v_instante) ch
   where ch.depth >= 1 and ch.responsible_collaborator_id is not null
  union
  select 'GESTAO_DIRETA', g.manager_responsible_collaborator_id
    from public.organizacao_resolver_gestor_direto(v_avaliado, v_instante) g
   where g.manager_responsible_collaborator_id is not null;

  -- A responsabilidade de cadeia e unica: se a derivacao trouxer mais de um
  -- candidato, mantem a ocorrencia vigente e descarta o excedente (que fica
  -- visivel como pendencia de completude, nunca como reescrita silenciosa).
  select p.collaborator_id into v_cadeia_vigente
    from public.evaluation_participants p
   where p.evaluation_id = p_evaluation_id
     and p.role_type = 'GESTAO_CADEIA'
     and p.valid_from <= v_instante
     and (p.valid_to is null or p.valid_to > v_instante)
   order by p.valid_from
   limit 1;

  if v_cadeia_vigente is not null then
    delete from pg_temp.f5_06_derivado d
     where d.role_type = 'GESTAO_CADEIA'
       and d.collaborator_id <> v_cadeia_vigente;
  end if;

  -- Nao pode haver duas ocorrencias de cadeia no conjunto derivado.
  delete from pg_temp.f5_06_derivado d
   where d.role_type = 'GESTAO_CADEIA'
     and exists (
       select 1 from pg_temp.f5_06_derivado d2
        where d2.role_type = 'GESTAO_CADEIA' and d2.collaborator_id < d.collaborator_id
     );

  -- Quem saiu e ENCERRADO (valid_to), preservando o historico.
  for v_item in
    select p.id, p.role_type, p.collaborator_id
      from public.evaluation_participants p
     where p.evaluation_id = p_evaluation_id
       and p.valid_from <= v_instante
       and (p.valid_to is null or p.valid_to > v_instante)
       and not exists (
         select 1 from pg_temp.f5_06_derivado d
          where d.role_type = p.role_type and d.collaborator_id = p.collaborator_id
       )
     order by p.role_type, p.collaborator_id
  loop
    update public.evaluation_participants
       set valid_to = v_instante, status = 'ended', version = version + 1
     where id = v_item.id;

    insert into public.evaluation_events
      (organization_id, evaluation_id, event_type, actor_user_profile_id, motivo,
       entidade, entidade_id, valor_anterior, valor_novo)
    values (v_org, p_evaluation_id, 'PARTICIPANTE_ALTERADO', p_actor_user_profile_id,
            btrim(p_motivo), 'evaluation_participants', v_item.id,
            jsonb_build_object('role_type', v_item.role_type,
                               'collaborator_id', v_item.collaborator_id,
                               'vigente', true),
            jsonb_build_object('vigente', false, 'valid_to', v_instante));
    v_alteradas := v_alteradas + 1;
  end loop;

  -- Quem entrou ganha NOVA ocorrencia (nunca edicao da anterior).
  for v_item in
    select d.role_type, d.collaborator_id
      from pg_temp.f5_06_derivado d
     where not exists (
       select 1 from public.evaluation_participants p
        where p.evaluation_id = p_evaluation_id
          and p.role_type = d.role_type
          and p.collaborator_id = d.collaborator_id
          and p.valid_from <= v_instante
          and (p.valid_to is null or p.valid_to > v_instante)
     )
     order by d.role_type, d.collaborator_id
  loop
    insert into public.evaluation_participants
      (organization_id, evaluation_id, role_type, collaborator_id,
       origem, valid_from, status)
    values (v_org, p_evaluation_id, v_item.role_type, v_item.collaborator_id,
            'ESTRUTURA', v_instante, 'active');

    insert into public.evaluation_events
      (organization_id, evaluation_id, event_type, actor_user_profile_id, motivo,
       entidade, valor_anterior, valor_novo)
    values (v_org, p_evaluation_id, 'PARTICIPANTE_ALTERADO', p_actor_user_profile_id,
            btrim(p_motivo), 'evaluation_participants', null,
            jsonb_build_object('role_type', v_item.role_type,
                               'collaborator_id', v_item.collaborator_id,
                               'vigente', true,
                               'valid_from', v_instante));
    v_alteradas := v_alteradas + 1;
  end loop;

  if v_alteradas > 0 then
    perform public.evaluation_calcular(p_evaluation_id);
  end if;

  return v_alteradas;
end;
$$;

comment on function public.evaluation_participante_realinhar(uuid, text, uuid) is
  'F5-06 D16/D23: realinha as ocorrencias de participante com as fontes '
  'soberanas atuais (colegiado do snapshot + gestor direto/cadeia F3-07): '
  'encerra (valid_to) quem saiu e abre nova ocorrencia para quem entrou, sempre '
  'com evento auditado. Nunca reescreve historico. EXECUTE somente service_role.';

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
  v_config uuid;
  v_instante timestamptz;
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

  v_instante := now();

  -- A ocorrencia precisa existir, pertencer a ESTA avaliacao (garantido tambem
  -- pela FK composta participant+evaluation) e estar VIGENTE no instante
  -- soberano: ocorrencia futura ou ja encerrada nao recebe mutacao normal.
  if not exists (
    select 1 from public.evaluation_participants p
     where p.id = p_participant_id
       and p.evaluation_id = p_evaluation_id
       and p.organization_id = v_org
       and p.valid_from <= v_instante
       and (p.valid_to is null or p.valid_to > v_instante)
  ) then
    raise exception 'F5-06 D23: participante (ocorrencia) nao pertence a '
      'avaliacao ou nao esta vigente no instante da gravacao';
  end if;

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
       and sc.participant_id = p_participant_id
       and sc.subcriterion_id = v_sub;

    insert into public.evaluation_scores
      (organization_id, evaluation_id, participant_id, subcriterion_id, nota,
       autor_user_profile_id, data_avaliacao)
    values (v_org, p_evaluation_id, p_participant_id, v_sub, v_nota,
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
                 else jsonb_build_object('participant_id', p_participant_id,
                                         'subcriterion_id', v_sub,
                                         'nota', v_anterior) end,
            jsonb_build_object('participant_id', p_participant_id,
                               'subcriterion_id', v_sub,
                               'nota', v_nota));
  end loop;

  return public.evaluation_calcular(p_evaluation_id);
end;
$$;

comment on function public.evaluation_gravar_notas(uuid, uuid, jsonb, uuid) is
  'F5-06 D4/D6/D23/D26: grava o lote de notas de UMA ocorrencia vigente da '
  'avaliacao, validando que o subcriterio pertence a configuracao congelada e '
  'gravando delta estruturado (valor_anterior/valor_novo) por nota. Lote '
  'transacional; recalcula o agregado oficial na mesma transacao. EXECUTE '
  'somente service_role.';

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
  v_config uuid;
  v_instante timestamptz;
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

  v_instante := now();

  -- ACHADO DA AUDITORIA: a versao anterior aceitava qualquer participant_id do
  -- tenant (a FK garantia apenas o tenant). Agora a ocorrencia precisa existir,
  -- pertencer a ESTA avaliacao e estar VIGENTE.
  if not exists (
    select 1 from public.evaluation_participants p
     where p.id = p_participant_id
       and p.evaluation_id = p_evaluation_id
       and p.organization_id = v_org
       and p.valid_from <= v_instante
       and (p.valid_to is null or p.valid_to > v_instante)
  ) then
    raise exception 'F5-06 D23: participante (ocorrencia) nao pertence a '
      'avaliacao ou nao esta vigente no instante da gravacao';
  end if;

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
     where cm.participant_id = p_participant_id
       and cm.evaluation_id = p_evaluation_id
       and cm.escopo = 'CRITERIO'
       and cm.criterion_id = p_criterion_id;

    if v_anterior is not null then
      update public.evaluation_comments cm
         set texto = btrim(p_texto),
             autor_user_profile_id = p_actor_user_profile_id,
             data = v_instante,
             version = cm.version + 1
       where cm.participant_id = p_participant_id
         and cm.evaluation_id = p_evaluation_id
         and cm.escopo = 'CRITERIO'
         and cm.criterion_id = p_criterion_id
      returning cm.id into v_id;
    else
      insert into public.evaluation_comments
        (organization_id, evaluation_id, participant_id, escopo, criterion_id,
         texto, autor_user_profile_id, data)
      values (v_org, p_evaluation_id, p_participant_id, 'CRITERIO', p_criterion_id,
              btrim(p_texto), p_actor_user_profile_id, v_instante)
      returning id into v_id;
    end if;
  else
    select cm.texto into v_anterior
      from public.evaluation_comments cm
     where cm.participant_id = p_participant_id
       and cm.evaluation_id = p_evaluation_id
       and cm.escopo = 'FINAL';

    if v_anterior is not null then
      update public.evaluation_comments cm
         set texto = btrim(p_texto),
             autor_user_profile_id = p_actor_user_profile_id,
             data = v_instante,
             version = cm.version + 1
       where cm.participant_id = p_participant_id
         and cm.evaluation_id = p_evaluation_id
         and cm.escopo = 'FINAL'
      returning cm.id into v_id;
    else
      insert into public.evaluation_comments
        (organization_id, evaluation_id, participant_id, escopo, criterion_id,
         texto, autor_user_profile_id, data)
      values (v_org, p_evaluation_id, p_participant_id, 'FINAL', null,
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

comment on function public.evaluation_gravar_comentario(uuid, uuid, text, uuid, text, uuid) is
  'F5-06 D6/D23/D26: grava comentario de ocorrencia VIGENTE da avaliacao; o '
  'criterio precisa pertencer a configuracao congelada; delta estruturado '
  '(texto anterior/novo) registrado na trilha. EXECUTE somente service_role.';

create or replace function public.evaluation_pendencias_calcular(p_evaluation_id uuid)
returns table (codigo text, role_type text, participant_id uuid, subcriterion_id uuid, descricao text)
language sql
stable
security invoker
set search_path = public
as $$
  with aval as (
    select e.id, e.organization_id, e.config_version_id,
           coalesce(e.data_conclusao, now()) as instante
      from public.evaluations e where e.id = p_evaluation_id
  ),
  cfg as (
    select pcr.role_type, pcr.required, pcr.contributes_to_score, pcr.requires_final_comment,
           pcr.min_participants, pcr.max_participants
      from public.evaluation_config_participant_roles pcr
      join aval a on a.config_version_id = pcr.config_version_id
  ),
  -- Ocorrencias VIGENTES no instante soberano (D23): 'status' e apenas o
  -- indicador operacional; a vigencia e a fonte de verdade da completude.
  vigentes as (
    select p.role_type, count(*)::int as qtd
      from public.evaluation_participants p
      join aval a on a.id = p.evaluation_id
     where p.valid_from <= a.instante
       and (p.valid_to is null or p.valid_to > a.instante)
     group by p.role_type
  ),
  p1 as (
    select 'PARTICIPANTE_OBRIGATORIO_AUSENTE'::text as codigo, c.role_type,
           null::uuid as participant_id, null::uuid as subcriterion_id,
           ('Participante obrigatorio ausente: ' || c.role_type)::text as descricao
      from cfg c
      left join vigentes v on v.role_type = c.role_type
     where c.required and coalesce(v.qtd, 0) < greatest(c.min_participants, 1)
  ),
  -- Nota faltante por responsabilidade contribuinte (subcriterios da
  -- configuracao congelada).
  p2 as (
    select 'NOTA_FALTANTE'::text, c.role_type, null::uuid, sub.id,
           ('Nota faltante em ' || c.role_type || ': ' || sub.name)
      from cfg c
      join aval av on true
      join public.evaluation_config_criteria cri
        on cri.organization_id = av.organization_id
       and cri.config_version_id = av.config_version_id
      join public.evaluation_config_subcriteria sub
        on sub.config_criterion_id = cri.id
       and sub.organization_id = av.organization_id
     where c.contributes_to_score
       and exists (
         select 1 from public.evaluation_participants p
          where p.evaluation_id = av.id
            and p.role_type = c.role_type
            and p.valid_from <= av.instante
            and (p.valid_to is null or p.valid_to > av.instante)
       )
       and not exists (
         select 1
           from public.evaluation_scores sc
           join public.evaluation_participants p
             on p.id = sc.participant_id
            and p.evaluation_id = sc.evaluation_id
          where sc.evaluation_id = av.id
            and sc.subcriterion_id = sub.id
            and p.role_type = c.role_type
            and p.valid_from <= av.instante
            and (p.valid_to is null or p.valid_to > av.instante)
       )
  ),
  p3 as (
    select 'FEEDBACK_FINAL_FALTANTE'::text, c.role_type, null::uuid, null::uuid,
           ('Feedback final faltante: ' || c.role_type)
      from cfg c
      join aval av on true
     where c.requires_final_comment
       and exists (
         select 1 from public.evaluation_participants p
          where p.evaluation_id = av.id
            and p.role_type = c.role_type
            and p.valid_from <= av.instante
            and (p.valid_to is null or p.valid_to > av.instante)
       )
       and not exists (
         select 1
           from public.evaluation_comments cm
           join public.evaluation_participants p
             on p.id = cm.participant_id
            and p.evaluation_id = cm.evaluation_id
          where cm.evaluation_id = av.id
            and cm.escopo = 'FINAL'
            and p.role_type = c.role_type
            and p.valid_from <= av.instante
            and (p.valid_to is null or p.valid_to > av.instante)
       )
  )
  select * from p1 union all select * from p2 union all select * from p3;
$$;

comment on function public.evaluation_pendencias_calcular(uuid) is
  'F5-06 D18/D19/D23: completude conforme a CONFIGURACAO CONGELADA e a VIGENCIA '
  'das ocorrencias (ocorrencia futura ou encerrada nao conta). Participante '
  'obrigatorio ausente, nota faltante em responsabilidade contribuinte e '
  'feedback final obrigatorio. Membro de colegiado sem voto nao vira zero: gera '
  'pendencia apenas quando o papel e obrigatorio. EXECUTE somente service_role.';

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
  v_instante timestamptz;
  v_resultado jsonb;
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
    -- D20: SOMENTE o nome dos membros do colegiado vigente; nunca o voto ou a
    -- nota individual, nunca participant_id correlacionado.
    'colegiado', coalesce((
      select jsonb_agg(distinct jsonb_build_object('colaborador_id', p.collaborator_id))
        from public.evaluation_participants p
       where p.evaluation_id = v_eval.id
         and p.organization_id = v_eval.organization_id
         and p.role_type = 'COLEGIADO'
         and p.valid_from <= v_instante
         and (p.valid_to is null or p.valid_to > v_instante)
    ), '[]'::jsonb),
    -- Somente comentarios FINAIS de responsabilidades que os destinam ao
    -- avaliado (requires_final_comment), de ocorrencias vigentes.
    'comentarios_finais', coalesce((
      select jsonb_agg(jsonb_build_object('role_type', p.role_type, 'texto', cm.texto))
        from public.evaluation_comments cm
        join public.evaluation_participants p
          on p.id = cm.participant_id
         and p.evaluation_id = cm.evaluation_id
        join public.evaluation_config_participant_roles pcr
          on pcr.config_version_id = v_eval.config_version_id
         and pcr.organization_id = v_eval.organization_id
         and pcr.role_type = p.role_type
         and pcr.requires_final_comment
       where cm.evaluation_id = v_eval.id
         and cm.organization_id = v_eval.organization_id
         and cm.escopo = 'FINAL'
         and p.valid_from <= v_instante
         and (p.valid_to is null or p.valid_to > v_instante)
    ), '[]'::jsonb)
  ) into v_resultado;

  -- NUNCA expoe voto/nota individual, participant_id correlacionado nem
  -- comentario interno: a projecao acima e a unica superficie do avaliado.
  return v_resultado;
end;
$$;

comment on function public.evaluation_leitura_avaliado(uuid, uuid) is
  'F5-06 D20/D23: projecao server-side de transparencia do AVALIADO. Retorna '
  'nota_media, agregados por criterio/subcriterio, faixa da escala congelada, '
  'lista de membros do colegiado VIGENTES e comentarios finais destinados ao '
  'avaliado. NUNCA retorna voto/nota individual nem participant_id '
  'correlacionado. EXECUTE somente service_role.';

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
revoke all on function public.evaluation_snapshot_participantes(uuid, uuid, uuid, uuid, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_criar(uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.evaluation_participante_realinhar(uuid, text, uuid) from public, anon, authenticated;
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
grant execute on function public.evaluation_snapshot_participantes(uuid, uuid, uuid, uuid, timestamptz, uuid) to service_role;
grant execute on function public.evaluation_criar(uuid, uuid, uuid, uuid) to service_role;
grant execute on function public.evaluation_participante_realinhar(uuid, text, uuid) to service_role;
grant execute on function public.evaluation_gravar_notas(uuid, uuid, jsonb, uuid) to service_role;
grant execute on function public.evaluation_gravar_comentario(uuid, uuid, text, uuid, text, uuid) to service_role;
grant execute on function public.evaluation_pendencias_calcular(uuid) to service_role;
grant execute on function public.evaluation_concluir(uuid, uuid) to service_role;
grant execute on function public.evaluation_reabrir(uuid, text, uuid) to service_role;
grant execute on function public.evaluation_cancelar(uuid, text, uuid) to service_role;
grant execute on function public.evaluation_fechar_ciclo_pendencias(uuid, uuid, uuid) to service_role;
grant execute on function public.evaluation_leitura_avaliado(uuid, uuid) to service_role;

