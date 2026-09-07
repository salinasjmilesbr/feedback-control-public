-- ============================================================================
-- F3-09 (Issue #86): responsabilidade avaliativa e sucessão de avaliador no ciclo
-- ----------------------------------------------------------------------------
-- Propósito: modelar, em camada separada e auditável, a responsabilidade de
-- avaliação por (ciclo, avaliado/snapshot, posição ocupada) e a sucessão do
-- avaliador quando há mudança definitiva de gestor durante o ciclo, SEM alterar
-- o snapshot imutável da F3-08 e SEM migrar o domínio de avaliações/ciclos.
--
-- Decisões D1–D9 registradas (Issue #86 e desenho consolidado):
--   - D1: a sucessão vive em camada separada (responsabilidade temporal +
--     evento de sucessão) e NUNCA altera o snapshot imutável da F3-08;
--   - D2: resolução avaliativa própria — temporary responsibility
--     ('evaluative'|'operational_evaluative') > titular; NÃO se reutiliza o
--     superior operacional congelado pela F3-08 como avaliador;
--   - D3: responsabilidade e sucessão granulares por (avaliado/snapshot +
--     organizational_position ocupada); múltiplas posições = responsabilidades
--     separadas; sem "posição primária";
--   - D4: modela-se apenas o gestor direto/responsável avaliativo resolvido
--     estruturalmente (sem reificar papéis GERENTE/COORDENADOR e sem inferir
--     hierarquia por job_role/seniority);
--   - D5: sucessão somente por RPC explícita, transacional e idempotente
--     (sem triggers em occupations/reporting lines);
--   - D6: responsabilidade temporal close+open + evento append-only imutável; a
--     responsabilidade ORIGINAL é materializada explicitamente uma única vez a
--     partir do contexto aplicável na ativação (nunca reconstruída
--     retroativamente da estrutura atual);
--   - D7: autor canônico = `author_user_profile_id uuid NOT NULL` →
--     `user_profiles(id)` (usuário autenticado ≠ colaborador; auditoria
--     registra quem executou no sistema, inclusive ator administrativo sem
--     collaborator; sem duplicar nome/e-mail textual);
--   - D8: o chamador determina quais relações ainda estão pendentes e informa
--     explicitamente as responsabilidades afetadas por IDs canônicos
--     (cycle_evaluation_responsibilities.id); o banco só altera responsabilidade
--     ABERTA, nunca reabre encerrada, preserva histórico e não cria status de
--     avaliação; a garantia de não enviar avaliação CONCLUÍDA pertence ao
--     chamador enquanto o domínio de avaliações viver no localStorage (reforço
--     server-side na migração futura);
--   - D9: reusam-se as regras existentes de leave/inactive/desligamento
--     (F3-05/F3-07); não se migra o "escopo" das movimentações (Fase B) e não
--     existe carência/tempo mínimo; o chamador fornece o conjunto afetado.
--
-- Regras adicionais: preservar F3-01..F3-08 intactas; snapshots F3-08
-- imutáveis; temporary responsibility nunca transforma substituto em gestor
-- histórico permanente (encerrado o período, a resolução avaliativa volta ao
-- responsável permanente vigente); FKs compostas multi-organização + ON DELETE
-- RESTRICT; RLS deny-by-default; sem capabilities/RLS finais; sem migração
-- completa de ciclos/avaliações; sem dados reais.
--
-- Responsabilidade congela o responsável PERMANENTE (titular); o substituto
-- avaliativo é overlay vivo por data (nunca congelado em responsabilidade).
--
-- Dependências: public.organizations (F2-01), public.user_profiles (F2-01),
-- public.collaborators (F3-01), public.organizational_positions (F3-03),
-- public.occupations (F3-05), public.temporary_responsibilities (F3-06),
-- funções de resolução (F3-07), collegiate_cycle_snapshots/_positions (F3-08).
-- A materialização das responsabilidades pressupõe snapshots F3-08 já
-- materializados (chamada em ordem documentada).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Responsável avaliativo de uma posição em uma data (titular/substituto)
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_responsavel_avaliativo_posicao(
  p_position_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid
)
language sql
stable
set search_path = public
as $$
  with titular as (
    select collaborator_id
    from public.occupations
    where organizational_position_id = p_position_id
      and valid_from <= p_data
      and (valid_to is null or valid_to > p_data)
    limit 1
  ),
  substituto as (
    select substitute_collaborator_id
    from public.temporary_responsibilities
    where organizational_position_id = p_position_id
      and responsibility_type in ('evaluative', 'operational_evaluative')
      and valid_from <= p_data
      and valid_to > p_data
    limit 1
  )
  select
    p_position_id,
    (select collaborator_id from titular),
    (select substitute_collaborator_id from substituto),
    coalesce(
      (select substitute_collaborator_id from substituto),
      (select collaborator_id from titular)
    )
$$;

comment on function public.organizacao_resolver_responsavel_avaliativo_posicao(uuid, timestamptz) is
  'F3-09: resolve o responsavel AVALIATIVO de uma posicao em uma data — titular '
  '(occupation) e substituto avaliativo (temporary responsibility '
  'evaluative/operational_evaluative), com responsavel = substituto > titular. '
  'Distinto do responsavel operacional da F3-07.';

-- ----------------------------------------------------------------------------
-- 2) Avaliador (gestor direto avaliativo) por posição ocupada do avaliado
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_avaliador_avaliado(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  occupied_position_id uuid,
  manager_position_id uuid,
  manager_collaborator_id uuid
)
language sql
stable
set search_path = public
as $$
  select
    occ.organizational_position_id,
    rl.manager_position_id,
    r.responsible_collaborator_id
  from public.occupations occ
  join public.position_reporting_lines rl
    on rl.subordinate_position_id = occ.organizational_position_id
   and rl.valid_from <= p_data
   and (rl.valid_to is null or rl.valid_to > p_data)
  cross join lateral public.organizacao_resolver_responsavel_avaliativo_posicao(
    rl.manager_position_id, p_data
  ) r
  where occ.collaborator_id = p_collaborator_id
    and occ.valid_from <= p_data
    and (occ.valid_to is null or occ.valid_to > p_data)
$$;

comment on function public.organizacao_resolver_avaliador_avaliado(uuid, timestamptz) is
  'F3-09: resolve, por posicao ocupada do avaliado em uma data, a posicao '
  'superior (reporting line) e o responsavel avaliativo dessa posicao superior '
  '(substituto > titular). Multiplas posicoes produzem multiplas linhas (D3).';

-- ----------------------------------------------------------------------------
-- 3) public.cycle_evaluation_responsibilities — responsabilidade temporal
-- ----------------------------------------------------------------------------
create table public.cycle_evaluation_responsibilities (
  id                          uuid        not null default gen_random_uuid(),
  organization_id             uuid        not null,
  snapshot_id                 uuid        not null,
  position_id                 uuid        not null,
  responsible_collaborator_id uuid        not null,
  valid_from                  timestamptz not null,
  valid_to                    timestamptz,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  version                     integer     not null default 0,
  constraint pk_cycle_evaluation_responsibilities primary key (id),
  constraint uq_cycle_evaluation_responsibilities_id_organization unique (id, organization_id),
  constraint fk_cycle_evaluation_responsibilities_snapshots
    foreign key (snapshot_id, organization_id)
    references public.collegiate_cycle_snapshots (id, organization_id)
    on delete restrict,
  constraint fk_cycle_evaluation_responsibilities_positions
    foreign key (position_id, organization_id)
    references public.organizational_positions (id, organization_id)
    on delete restrict,
  constraint fk_cycle_evaluation_responsibilities_collaborators
    foreign key (responsible_collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint ck_cycle_evaluation_responsibilities_valid_to
    check (valid_to is null or valid_to > valid_from),
  constraint ex_cycle_evaluation_responsibilities_no_overlap
    exclude using gist (
      snapshot_id with =,
      position_id with =,
      tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
    )
);

comment on table public.cycle_evaluation_responsibilities is
  'Responsabilidade avaliativa temporal por (snapshot do ciclo, posicao '
  'ocupada pelo avaliado) - F3-09 (Issue #86). Guarda o responsavel PERMANENTE '
  '(titular); sucessao = close+open; substituto e overlay vivo (nao congelado).';

comment on column public.cycle_evaluation_responsibilities.snapshot_id is
  'Snapshot F3-08 do ciclo (collegiate_cycle_snapshots) que congelou o '
  'responsavel original na ativacao; nunca mutado pela F3-09.';

comment on column public.cycle_evaluation_responsibilities.position_id is
  'Posicao organizacional ocupada pelo avaliado no snapshot (granularidade D3).';

comment on column public.cycle_evaluation_responsibilities.responsible_collaborator_id is
  'Responsavel permanente (titular da posicao superior) vigente no periodo. '
  'Alterado somente por sucessao (close+open); o substituto avaliativo nunca e '
  'gravado aqui.';

comment on column public.cycle_evaluation_responsibilities.valid_to is
  'Fim do periodo (meio-aberto [valid_from, valid_to)); null = vigente. '
  'Sucessao fecha a linha aberta e abre nova; nunca se reescreve historico.';

comment on constraint ex_cycle_evaluation_responsibilities_no_overlap
  on public.cycle_evaluation_responsibilities is
  'Linha do tempo unica por (snapshot, posicao): periodos nao se sobrepoem e '
  'ha no maximo uma responsabilidade vigente por snapshot+posicao.';

create index ix_cycle_evaluation_responsibilities_organization_id
  on public.cycle_evaluation_responsibilities (organization_id);

create index ix_cycle_evaluation_responsibilities_snapshot_id
  on public.cycle_evaluation_responsibilities (snapshot_id);

create index ix_cycle_evaluation_responsibilities_position_id
  on public.cycle_evaluation_responsibilities (position_id);

create index ix_cycle_evaluation_responsibilities_responsible_collaborator_id
  on public.cycle_evaluation_responsibilities (responsible_collaborator_id);

create trigger trg_cycle_evaluation_responsibilities_updated_at
  before update on public.cycle_evaluation_responsibilities
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 4) public.evaluation_succession_events — evento de sucessão (imutável)
-- ----------------------------------------------------------------------------
create table public.evaluation_succession_events (
  id                                uuid        not null default gen_random_uuid(),
  organization_id                   uuid        not null,
  snapshot_id                       uuid        not null,
  position_id                       uuid        not null,
  previous_responsible_collaborator_id uuid      not null,
  new_responsible_collaborator_id   uuid        not null,
  succession_date                   timestamptz not null,
  motive                            text        not null,
  author_user_profile_id            uuid        not null,
  created_at                        timestamptz not null default now(),
  constraint pk_evaluation_succession_events primary key (id),
  constraint uq_evaluation_succession_events_snapshot_position_date
    unique (snapshot_id, position_id, succession_date),
  constraint fk_evaluation_succession_events_snapshots
    foreign key (snapshot_id, organization_id)
    references public.collegiate_cycle_snapshots (id, organization_id)
    on delete restrict,
  constraint fk_evaluation_succession_events_positions
    foreign key (position_id, organization_id)
    references public.organizational_positions (id, organization_id)
    on delete restrict,
  constraint fk_evaluation_succession_events_previous_collaborators
    foreign key (previous_responsible_collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint fk_evaluation_succession_events_new_collaborators
    foreign key (new_responsible_collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint fk_evaluation_succession_events_author
    foreign key (author_user_profile_id)
    references public.user_profiles (id)
    on delete restrict,
  constraint ck_evaluation_succession_events_motive
    check (motive <> '' and motive = btrim(motive))
);

comment on table public.evaluation_succession_events is
  'Evento imutavel (append-only) de sucessao de avaliador - F3-09 (Issue #86). '
  'Preserva responsavel original (previous) e novo, com data/motivo/autor.';

comment on column public.evaluation_succession_events.author_user_profile_id is
  'Autor canonico da acao no sistema (user_profiles.id) — usuario autenticado, '
  'distinto do colaborador organizacional (D7); sem duplicar nome/e-mail.';

comment on column public.evaluation_succession_events.motive is
  'Motivo/justificativa da sucessao (obrigatorio, trim nao vazio).';

comment on constraint uq_evaluation_succession_events_snapshot_position_date
  on public.evaluation_succession_events is
  'Uma unica sucessao por (snapshot, posicao, data): garante idempotencia da '
  'RPC de sucessao.';

create index ix_evaluation_succession_events_organization_id
  on public.evaluation_succession_events (organization_id);

create index ix_evaluation_succession_events_snapshot_id
  on public.evaluation_succession_events (snapshot_id);

create index ix_evaluation_succession_events_position_id
  on public.evaluation_succession_events (position_id);

create index ix_evaluation_succession_events_author_user_profile_id
  on public.evaluation_succession_events (author_user_profile_id);

-- ----------------------------------------------------------------------------
-- 5) RPC de materialização das responsabilidades originais (ativação)
-- ----------------------------------------------------------------------------
create or replace function public.materializar_responsabilidades_avaliacao(
  p_organization_id uuid,
  p_ano integer,
  p_ciclo integer
)
returns void
language plpgsql
set search_path = public
as $$
begin
  if p_ano <= 0 then
    raise exception 'materializar_responsabilidades_avaliacao: ano invalido';
  end if;
  if p_ciclo not in (1, 2, 3) then
    raise exception 'materializar_responsabilidades_avaliacao: ciclo invalido (1..3)';
  end if;

  -- Materializa UMA responsabilidade original por (snapshot, posicao ocupada
  -- com superior), resolvendo o responsavel PERMANENTE (titular) da posicao
  -- superior na reference_date do snapshot. Idempotente (guard por snapshot+
  -- posicao). Depende dos snapshots F3-08 ja materializados.
  insert into public.cycle_evaluation_responsibilities (
    id, organization_id, snapshot_id, position_id,
    responsible_collaborator_id, valid_from
  )
  select
    gen_random_uuid(),
    s.organization_id,
    s.id,
    sp.position_id,
    r.titular_collaborator_id,
    s.reference_date
  from public.collegiate_cycle_snapshots s
  join public.collegiate_cycle_snapshot_positions sp
    on sp.snapshot_id = s.id
   and sp.organization_id = s.organization_id
  cross join lateral public.organizacao_resolver_responsavel_avaliativo_posicao(
    sp.superior_position_id, s.reference_date
  ) r
  where s.organization_id = p_organization_id
    and s.ano = p_ano
    and s.ciclo = p_ciclo
    and sp.superior_position_id is not null
    and r.titular_collaborator_id is not null
    and not exists (
      select 1
      from public.cycle_evaluation_responsibilities cer
      where cer.snapshot_id = s.id
        and cer.position_id = sp.position_id
    );
end;
$$;

comment on function public.materializar_responsabilidades_avaliacao(uuid, integer, integer) is
  'F3-09: materializa (na ativacao) as responsabilidades originais de avaliacao '
  'por (snapshot, posicao ocupada), congelando o responsavel PERMANENTE '
  '(titular) na reference_date. Transacional e idempotente; SECURITY INVOKER.';

-- ----------------------------------------------------------------------------
-- 6) RPC de sucessão de avaliador (explícita, transacional e idempotente)
-- ----------------------------------------------------------------------------
create or replace function public.registrar_sucessao_avaliador(
  p_responsibility_ids uuid[],
  p_succession_date timestamptz,
  p_motive text,
  p_author_user_profile_id uuid
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_rid uuid;
  v_open record;
  v_superior_position_id uuid;
  v_new_responsible uuid;
begin
  if p_motive is null or btrim(p_motive) = '' then
    raise exception 'registrar_sucessao_avaliador: motivo obrigatorio';
  end if;
  if p_succession_date is null then
    raise exception 'registrar_sucessao_avaliador: data de sucessao obrigatoria';
  end if;
  if p_author_user_profile_id is null then
    raise exception 'registrar_sucessao_avaliador: autor obrigatorio';
  end if;

  foreach v_rid in array coalesce(p_responsibility_ids, '{}'::uuid[])
  loop
    -- Responsabilidade identificada pelo ID canonico informado (D8).
    select cer.id, cer.organization_id, cer.snapshot_id, cer.position_id,
           cer.responsible_collaborator_id, cer.valid_from, cer.valid_to
      into v_open
    from public.cycle_evaluation_responsibilities cer
    where cer.id = v_rid;

    if not found then
      raise exception
        'registrar_sucessao_avaliador: responsabilidade nao encontrada (id %)', v_rid;
    end if;

    -- Nunca reabre responsabilidade encerrada (D8).
    if v_open.valid_to is not null then
      raise exception
        'registrar_sucessao_avaliador: responsabilidade ja encerrada (id %)', v_rid;
    end if;

    -- Idempotencia: sucessao ja registrada para esta (snapshot, posicao, data).
    if exists (
      select 1
      from public.evaluation_succession_events e
      where e.snapshot_id = v_open.snapshot_id
        and e.position_id = v_open.position_id
        and e.succession_date = p_succession_date
    ) then
      continue;
    end if;

    if p_succession_date <= v_open.valid_from then
      raise exception
        'registrar_sucessao_avaliador: data de sucessao deve ser posterior ao inicio da responsabilidade';
    end if;

    -- Posicao superior congelada no snapshot (nao recalculada retroativamente).
    select sp.superior_position_id
      into v_superior_position_id
    from public.collegiate_cycle_snapshot_positions sp
    where sp.snapshot_id = v_open.snapshot_id
      and sp.position_id = v_open.position_id;

    if v_superior_position_id is null then
      raise exception
        'registrar_sucessao_avaliador: posicao sem superior no snapshot';
    end if;

    -- Novo responsavel permanente (titular) na data de sucessao.
    select r.titular_collaborator_id
      into v_new_responsible
    from public.organizacao_resolver_responsavel_avaliativo_posicao(
      v_superior_position_id, p_succession_date
    ) r;

    if v_new_responsible is null then
      raise exception
        'registrar_sucessao_avaliador: sem novo responsavel resolvido na data';
    end if;

    if v_new_responsible = v_open.responsible_collaborator_id then
      continue; -- nada a transferir
    end if;

    -- Fecha a responsabilidade aberta e abre a nova (close+open).
    update public.cycle_evaluation_responsibilities
       set valid_to = p_succession_date
     where id = v_open.id
       and valid_to is null;

    insert into public.cycle_evaluation_responsibilities (
      id, organization_id, snapshot_id, position_id,
      responsible_collaborator_id, valid_from
    ) values (
      gen_random_uuid(),
      v_open.organization_id,
      v_open.snapshot_id,
      v_open.position_id,
      v_new_responsible,
      p_succession_date
    );

    -- Evento de sucessao (append-only, imutavel).
    insert into public.evaluation_succession_events (
      id, organization_id, snapshot_id, position_id,
      previous_responsible_collaborator_id, new_responsible_collaborator_id,
      succession_date, motive, author_user_profile_id
    ) values (
      gen_random_uuid(),
      v_open.organization_id,
      v_open.snapshot_id,
      v_open.position_id,
      v_open.responsible_collaborator_id,
      v_new_responsible,
      p_succession_date,
      btrim(p_motive),
      p_author_user_profile_id
    );
  end loop;
end;
$$;

comment on function public.registrar_sucessao_avaliador(uuid[], timestamptz, text, uuid) is
  'F3-09: registra a sucessao de avaliador (mudanca definitiva de gestor) para '
  'as responsabilidades abertas informadas, fechando a responsabilidade atual e '
  'abrindo a do novo responsavel, com evento de sucessao (data/motivo/autor). '
  'Transacional e idempotente; SECURITY INVOKER; nunca reabre encerrada.';

-- ----------------------------------------------------------------------------
-- 7) Consulta do responsável avaliativo vigente (overlay de substituto por data)
-- ----------------------------------------------------------------------------
create or replace function public.resolver_responsavel_avaliacao_vigente(
  p_organization_id uuid,
  p_ano integer,
  p_ciclo integer,
  p_data timestamptz
)
returns table (
  snapshot_id uuid,
  position_id uuid,
  responsible_collaborator_id uuid,
  is_substitute boolean
)
language sql
stable
set search_path = public
as $$
  with base as (
    select
      cer.snapshot_id,
      cer.position_id,
      cer.responsible_collaborator_id,
      sp.superior_position_id
    from public.cycle_evaluation_responsibilities cer
    join public.collegiate_cycle_snapshots s
      on s.id = cer.snapshot_id
     and s.organization_id = cer.organization_id
    join public.collegiate_cycle_snapshot_positions sp
      on sp.snapshot_id = cer.snapshot_id
     and sp.position_id = cer.position_id
     and sp.organization_id = cer.organization_id
    where s.organization_id = p_organization_id
      and s.ano = p_ano
      and s.ciclo = p_ciclo
      and cer.valid_from <= p_data
      and (cer.valid_to is null or cer.valid_to > p_data)
  )
  select
    b.snapshot_id,
    b.position_id,
    coalesce(r.substitute_collaborator_id, b.responsible_collaborator_id),
    (r.substitute_collaborator_id is not null)
  from base b
  left join lateral public.organizacao_resolver_responsavel_avaliativo_posicao(
    b.superior_position_id, p_data
  ) r on true
$$;

comment on function public.resolver_responsavel_avaliacao_vigente(uuid, integer, integer, timestamptz) is
  'F3-09: resolve o responsavel avaliativo vigente de um ciclo em uma data '
  '(responsabilidade permanente vigente + overlay do substituto avaliativo '
  'ativo na data). Substituto nunca e gestor permanente.';

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
alter table public.cycle_evaluation_responsibilities enable row level security;
alter table public.evaluation_succession_events enable row level security;
