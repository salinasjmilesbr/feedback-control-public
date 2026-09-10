-- ============================================================================
-- F5-06 (Issue #103): avaliações no PostgreSQL — schema do domínio
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-06-desenho-tecnico.md (D1–D27 FECHADAS; Q1–Q8 resolvidas).
--
-- Entidades (todas tenant-rooted, `organization_id NOT NULL`):
--   evaluation_cycles ................ ciclo MÍNIMO (D15) — vínculo soberano
--   evaluation_config_versions ....... versão de configuração (D5/D6/D22)
--   evaluation_config_criteria ....... critérios da versão
--   evaluation_config_subcriteria .... subcritérios da versão
--   evaluation_config_scale_bands .... escala/faixas da versão (D22)
--   evaluation_config_participant_roles exigência/cardinalidade dos papéis (D16)
--   evaluations ...................... avaliação (D8/D9/D18)
--   evaluation_participants .......... OCORRÊNCIAS históricas de atribuição (D23)
--   evaluation_scores ................ nota 1..5 por ocorrência × subcritério (D4)
--   evaluation_comments .............. comentários por ocorrência (critério/final)
--   evaluation_events ................ trilha append-only (D7/D26)
--   evaluation_pendencies ............ pendências do fechamento (D11/D18)
--
-- Regras invariantes:
--   - FKs COMPOSTAS de tenant `(referencia_id, organization_id)` em todas as
--     relações (cross-tenant por construção) — padrão F3/F4-01;
--   - `ON DELETE RESTRICT` (sem exclusão física de histórico);
--   - identidade interna = `collaborators.id` (UUID) — nunca matrícula (D3);
--   - status por CHECK/catálogo fechado;
--   - nota 1..5; ausência = linha inexistente (nunca zero persistido) (D4);
--   - agregados `numeric(12,8)` — nunca float binário (D24);
--   - participantes como ocorrências + exclusion de sobreposição (D23);
--   - nenhuma coluna/FK para job_role/cargo/função (D16/D17);
--   - RLS deny-by-default (zero policies nesta migration).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) evaluation_config_versions — versão de configuração (imutável após publicar)
-- ----------------------------------------------------------------------------
create table public.evaluation_config_versions (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  version         integer     not null,
  checksum        text        not null,
  origem          text        not null default 'ORGANIZACAO',
  status          text        not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version_reg     integer     not null default 0,
  constraint pk_evaluation_config_versions primary key (id),
  constraint fk_evaluation_config_versions_organization
    foreign key (organization_id) references public.organizations (id) on delete restrict,
  constraint uq_evaluation_config_versions_id_organization unique (id, organization_id),
  constraint uq_evaluation_config_versions_org_version unique (organization_id, version),
  constraint ck_evaluation_config_versions_origem check (origem in ('SISTEMA', 'ORGANIZACAO')),
  constraint ck_evaluation_config_versions_status check (status in ('active', 'superseded')),
  constraint ck_evaluation_config_versions_checksum check (btrim(checksum) <> ''),
  constraint ck_evaluation_config_versions_version check (version > 0)
);

comment on table public.evaluation_config_versions is
  'F5-06 D5/D6/D22: versao de configuracao por organizacao (criterios, '
  'subcriterios, escala e papeis de participante). Publicada = imutavel; '
  'nova versao para alterar. Congelada na avaliacao.';

-- ----------------------------------------------------------------------------
-- 2) evaluation_config_criteria / subcriteria — estrutura versionada
-- ----------------------------------------------------------------------------
create table public.evaluation_config_criteria (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null,
  config_version_id uuid        not null,
  code              text        not null,
  name              text        not null,
  position          integer     not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint pk_evaluation_config_criteria primary key (id),
  constraint fk_evaluation_config_criteria_version
    foreign key (config_version_id, organization_id)
    references public.evaluation_config_versions (id, organization_id) on delete restrict,
  constraint uq_evaluation_config_criteria_id_organization unique (id, organization_id),
  constraint uq_evaluation_config_criteria_version_code unique (config_version_id, code),
  constraint uq_evaluation_config_criteria_version_position unique (config_version_id, position),
  constraint ck_evaluation_config_criteria_code check (btrim(code) <> ''),
  constraint ck_evaluation_config_criteria_name check (btrim(name) <> ''),
  constraint ck_evaluation_config_criteria_position check (position >= 0)
);

create table public.evaluation_config_subcriteria (
  id                  uuid        not null default gen_random_uuid(),
  organization_id     uuid        not null,
  config_criterion_id uuid        not null,
  code                text        not null,
  name                text        not null,
  position            integer     not null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint pk_evaluation_config_subcriteria primary key (id),
  constraint fk_evaluation_config_subcriteria_criterion
    foreign key (config_criterion_id, organization_id)
    references public.evaluation_config_criteria (id, organization_id) on delete restrict,
  constraint uq_evaluation_config_subcriteria_id_organization unique (id, organization_id),
  constraint uq_evaluation_config_subcriteria_criterion_code unique (config_criterion_id, code),
  constraint uq_evaluation_config_subcriteria_criterion_position unique (config_criterion_id, position),
  constraint ck_evaluation_config_subcriteria_code check (btrim(code) <> ''),
  constraint ck_evaluation_config_subcriteria_name check (btrim(name) <> ''),
  constraint ck_evaluation_config_subcriteria_position check (position >= 0)
);

-- ----------------------------------------------------------------------------
-- 3) evaluation_config_scale_bands — escala/faixas da versão (D22)
-- ----------------------------------------------------------------------------
create table public.evaluation_config_scale_bands (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null,
  config_version_id uuid        not null,
  nota              smallint    not null,
  significado       text        not null,
  descricao         text        not null,
  limite_minimo     numeric(12,8) not null,
  cor               text        not null,
  cor_fundo         text        not null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint pk_evaluation_config_scale_bands primary key (id),
  constraint fk_evaluation_config_scale_bands_version
    foreign key (config_version_id, organization_id)
    references public.evaluation_config_versions (id, organization_id) on delete restrict,
  constraint uq_evaluation_config_scale_bands_version_nota unique (config_version_id, nota),
  constraint ck_evaluation_config_scale_bands_nota check (nota between 1 and 5),
  constraint ck_evaluation_config_scale_bands_limite check (limite_minimo >= 0)
);

-- ----------------------------------------------------------------------------
-- 4) evaluation_config_participant_roles — exigência/cardinalidade (D16)
-- ----------------------------------------------------------------------------
create table public.evaluation_config_participant_roles (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null,
  config_version_id     uuid        not null,
  role_type             text        not null,
  required              boolean     not null default false,
  contributes_to_score  boolean     not null default true,
  requires_final_comment boolean    not null default false,
  min_participants      smallint    not null default 0,
  max_participants      smallint,
  aggregation_mode      text        not null default 'INDIVIDUAL',
  position              integer     not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint pk_evaluation_config_participant_roles primary key (id),
  constraint fk_evaluation_config_participant_roles_version
    foreign key (config_version_id, organization_id)
    references public.evaluation_config_versions (id, organization_id) on delete restrict,
  constraint uq_evaluation_config_participant_roles_version_role
    unique (config_version_id, role_type),
  constraint ck_evaluation_config_participant_roles_role
    check (role_type in ('GESTAO_CADEIA', 'GESTAO_DIRETA', 'COLEGIADO')),
  constraint ck_evaluation_config_participant_roles_aggregation
    check (aggregation_mode in ('INDIVIDUAL', 'AGGREGATED')),
  constraint ck_evaluation_config_participant_roles_min check (min_participants >= 0),
  constraint ck_evaluation_config_participant_roles_max
    check (max_participants is null or max_participants >= min_participants),
  constraint ck_evaluation_config_participant_roles_colegiado
    check (role_type <> 'COLEGIADO' or (aggregation_mode = 'AGGREGATED' and min_participants = 0))
);

comment on table public.evaluation_config_participant_roles is
  'F5-06 D16: exigencia, cardinalidade e papel no calculo por role_type de '
  'RELACAO (nunca cargo). COLEGIADO e 0..N agregado. Snapshotado na avaliacao.';

-- ----------------------------------------------------------------------------
-- 5) evaluation_cycles — ciclo MÍNIMO (D15; extensível aditivamente)
-- ----------------------------------------------------------------------------
create table public.evaluation_cycles (
  id                      uuid        not null default gen_random_uuid(),
  organization_id         uuid        not null,
  ano                     integer     not null,
  numero                  smallint    not null,
  status                  text        not null default 'PLANEJADO',
  data_inicio             date,
  data_fim                date,
  data_ativacao           timestamptz,
  data_encerramento       timestamptz,
  encerrado_com_pendencias boolean    not null default false,
  quantidade_pendencias   integer     not null default 0,
  config_version_id       uuid,
  version                 integer     not null default 0,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint pk_evaluation_cycles primary key (id),
  constraint fk_evaluation_cycles_organization
    foreign key (organization_id) references public.organizations (id) on delete restrict,
  constraint fk_evaluation_cycles_config_version
    foreign key (config_version_id, organization_id)
    references public.evaluation_config_versions (id, organization_id) on delete restrict,
  constraint uq_evaluation_cycles_id_organization unique (id, organization_id),
  constraint uq_evaluation_cycles_org_ano_numero unique (organization_id, ano, numero),
  constraint ck_evaluation_cycles_numero check (numero in (1, 2, 3)),
  constraint ck_evaluation_cycles_ano check (ano between 2000 and 2100),
  constraint ck_evaluation_cycles_status
    check (status in ('PLANEJADO', 'ATIVO', 'ENCERRADO', 'CANCELADO')),
  constraint ck_evaluation_cycles_periodo
    check (data_fim is null or data_inicio is null or data_fim >= data_inicio),
  constraint ck_evaluation_cycles_pendencias check (quantidade_pendencias >= 0)
);

comment on table public.evaluation_cycles is
  'F5-06 D15: ciclo MINIMO (identidade, tenant, periodo/status, config_version) '
  'para o vinculo soberano da avaliacao. Nao absorve a logica do dominio de '
  'ciclos; a atividade de ciclos estende esta tabela de forma ADITIVA.';

-- ----------------------------------------------------------------------------
-- 6) evaluations — avaliação (D3/D8/D9/D18)
-- ----------------------------------------------------------------------------
create table public.evaluations (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null,
  cycle_id                  uuid        not null,
  evaluated_collaborator_id uuid        not null,
  status                    text        not null default 'RASCUNHO',
  nota_media                numeric(12,8),
  config_version_id         uuid        not null,
  expectativa_snapshot      jsonb,
  data_conclusao            timestamptz,
  encerrada_com_pendencias  boolean     not null default false,
  motivo_cancelamento       text,
  cancelado_por_user_profile_id uuid,
  data_cancelamento         timestamptz,
  version                   integer     not null default 0,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint pk_evaluations primary key (id),
  constraint fk_evaluations_organization
    foreign key (organization_id) references public.organizations (id) on delete restrict,
  constraint fk_evaluations_cycle
    foreign key (cycle_id, organization_id)
    references public.evaluation_cycles (id, organization_id) on delete restrict,
  constraint fk_evaluations_evaluated_collaborator
    foreign key (evaluated_collaborator_id, organization_id)
    references public.collaborators (id, organization_id) on delete restrict,
  constraint fk_evaluations_config_version
    foreign key (config_version_id, organization_id)
    references public.evaluation_config_versions (id, organization_id) on delete restrict,
  constraint fk_evaluations_cancelado_por
    foreign key (cancelado_por_user_profile_id) references public.user_profiles (id) on delete restrict,
  constraint uq_evaluations_id_organization unique (id, organization_id),
  constraint ck_evaluations_status
    check (status in ('RASCUNHO', 'PRONTA_PARA_FEEDBACK', 'CONCLUIDA', 'CANCELADA')),
  constraint ck_evaluations_nota_media
    check (nota_media is null or (nota_media >= 0 and nota_media <= 5)),
  constraint ck_evaluations_cancelamento
    check (
      (status <> 'CANCELADA' and motivo_cancelamento is null and data_cancelamento is null)
      or (status = 'CANCELADA' and motivo_cancelamento is not null and btrim(motivo_cancelamento) <> '' and data_cancelamento is not null)
    )
);

-- única avaliação NÃO CANCELADA por (organização, ciclo, colaborador) — D9
create unique index uq_evaluations_org_cycle_collaborator_nao_cancelada
  on public.evaluations (organization_id, cycle_id, evaluated_collaborator_id)
  where status <> 'CANCELADA';

create index ix_evaluations_organization_id on public.evaluations (organization_id);
create index ix_evaluations_cycle_id on public.evaluations (cycle_id);

comment on column public.evaluations.nota_media is
  'F5-06 D13/D24: agregado materializado server-side em numeric (nunca float). '
  'Recomputavel pela funcao oficial de calculo.';

-- ----------------------------------------------------------------------------
-- 7) evaluation_participants — OCORRÊNCIAS históricas (D23)
-- ----------------------------------------------------------------------------
create table public.evaluation_participants (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  evaluation_id   uuid        not null,
  role_type       text        not null,
  collaborator_id uuid        not null,
  user_profile_id uuid,
  origem          text        not null default 'ESTRUTURA',
  origem_ref_id   uuid,
  valid_from      timestamptz not null default now(),
  valid_to        timestamptz,
  status          text        not null default 'active',
  version         integer     not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint pk_evaluation_participants primary key (id),
  constraint fk_evaluation_participants_evaluation
    foreign key (evaluation_id, organization_id)
    references public.evaluations (id, organization_id) on delete restrict,
  constraint fk_evaluation_participants_collaborator
    foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id) on delete restrict,
  constraint fk_evaluation_participants_user_profile
    foreign key (user_profile_id) references public.user_profiles (id) on delete restrict,
  constraint uq_evaluation_participants_id_organization unique (id, organization_id),
  constraint ck_evaluation_participants_role
    check (role_type in ('GESTAO_CADEIA', 'GESTAO_DIRETA', 'COLEGIADO')),
  constraint ck_evaluation_participants_origem
    check (origem in ('ESTRUTURA', 'SUBSTITUICAO_TEMPORARIA', 'SUCESSAO', 'SNAPSHOT_CICLO')),
  constraint ck_evaluation_participants_status check (status in ('active', 'ended')),
  constraint ck_evaluation_participants_vigencia
    check (valid_to is null or valid_to > valid_from),
  constraint ck_evaluation_participants_status_vigencia
    check ((status = 'active' and valid_to is null) or (status = 'ended' and valid_to is not null)),
  -- D23: NÃO existe unique eterno (evaluation, role, collaborator)
  constraint ex_evaluation_participants_vigencia
    exclude using gist (
      evaluation_id with =,
      role_type with =,
      collaborator_id with =,
      tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz)) with &&
    )
);

create index ix_evaluation_participants_evaluation_id
  on public.evaluation_participants (evaluation_id);
create index ix_evaluation_participants_organization_id
  on public.evaluation_participants (organization_id);

comment on table public.evaluation_participants is
  'F5-06 D23: cada linha e uma OCORRENCIA historica de atribuicao; a mesma '
  'pessoa pode repetir o role_type em periodos distintos; vigencia define o '
  'ativo; a exclusion impede sobreposicao equivalente; historico preservado.';

-- ----------------------------------------------------------------------------
-- 8) evaluation_scores — nota 1..5 por ocorrência × subcritério (D4)
-- ----------------------------------------------------------------------------
create table public.evaluation_scores (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null,
  evaluation_id         uuid        not null,
  participant_id        uuid        not null,
  subcriterion_id       uuid        not null,
  nota                  smallint    not null,
  autor_user_profile_id uuid,
  data_avaliacao        timestamptz,
  version               integer     not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint pk_evaluation_scores primary key (id),
  constraint fk_evaluation_scores_evaluation
    foreign key (evaluation_id, organization_id)
    references public.evaluations (id, organization_id) on delete restrict,
  constraint fk_evaluation_scores_participant
    foreign key (participant_id, organization_id)
    references public.evaluation_participants (id, organization_id) on delete restrict,
  constraint fk_evaluation_scores_subcriterion
    foreign key (subcriterion_id, organization_id)
    references public.evaluation_config_subcriteria (id, organization_id) on delete restrict,
  constraint fk_evaluation_scores_autor
    foreign key (autor_user_profile_id) references public.user_profiles (id) on delete restrict,
  constraint uq_evaluation_scores_participant_subcriterion unique (participant_id, subcriterion_id),
  constraint ck_evaluation_scores_nota check (nota between 1 and 5)
);

create index ix_evaluation_scores_evaluation_id on public.evaluation_scores (evaluation_id);
create index ix_evaluation_scores_organization_id on public.evaluation_scores (organization_id);

comment on column public.evaluation_scores.nota is
  'F5-06 D4: nota valida 1..5. Ausencia de avaliacao = linha INEXISTENTE '
  '(nunca zero persistido).';

-- ----------------------------------------------------------------------------
-- 9) evaluation_comments — comentários por ocorrência (critério/final)
-- ----------------------------------------------------------------------------
create table public.evaluation_comments (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null,
  evaluation_id         uuid        not null,
  participant_id        uuid        not null,
  escopo                text        not null,
  criterion_id          uuid,
  texto                 text        not null,
  autor_user_profile_id uuid,
  data                  timestamptz,
  version               integer     not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint pk_evaluation_comments primary key (id),
  constraint fk_evaluation_comments_evaluation
    foreign key (evaluation_id, organization_id)
    references public.evaluations (id, organization_id) on delete restrict,
  constraint fk_evaluation_comments_participant
    foreign key (participant_id, organization_id)
    references public.evaluation_participants (id, organization_id) on delete restrict,
  constraint fk_evaluation_comments_criterion
    foreign key (criterion_id, organization_id)
    references public.evaluation_config_criteria (id, organization_id) on delete restrict,
  constraint fk_evaluation_comments_autor
    foreign key (autor_user_profile_id) references public.user_profiles (id) on delete restrict,
  constraint uq_evaluation_comments_participant_escopo_criterion
    unique (participant_id, escopo, criterion_id),
  constraint ck_evaluation_comments_escopo check (escopo in ('CRITERIO', 'FINAL')),
  constraint ck_evaluation_comments_texto check (btrim(texto) <> ''),
  constraint ck_evaluation_comments_escopo_criterion
    check (
      (escopo = 'CRITERIO' and criterion_id is not null)
      or (escopo = 'FINAL' and criterion_id is null)
    )
);

-- Contrato 3.6: unique (participant_id, escopo, criterion_id). Como
-- 'criterion_id' e NULL no escopo FINAL, a unicidade exige dois indices
-- parciais: um UNIQUE simples nao bloqueia NULL (NULL <> NULL) e permitiria
-- comentario FINAL duplicado para a mesma ocorrencia (achado da auditoria).
create unique index uq_evaluation_comments_participant_escopo_criterion
  on public.evaluation_comments (participant_id, escopo, criterion_id)
  where escopo = 'CRITERIO';
create unique index uq_evaluation_comments_participant_final
  on public.evaluation_comments (participant_id)
  where escopo = 'FINAL';

create index ix_evaluation_comments_evaluation_id on public.evaluation_comments (evaluation_id);

-- ----------------------------------------------------------------------------
-- 10) evaluation_events — trilha append-only (D7/D26)
-- ----------------------------------------------------------------------------
create table public.evaluation_events (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null,
  evaluation_id         uuid        not null,
  event_type            text        not null,
  actor_user_profile_id uuid        not null,
  motivo                text,
  entidade              text,
  entidade_id           uuid,
  valor_anterior        jsonb,
  valor_novo            jsonb,
  created_at            timestamptz not null default now(),
  constraint pk_evaluation_events primary key (id),
  constraint fk_evaluation_events_evaluation
    foreign key (evaluation_id, organization_id)
    references public.evaluations (id, organization_id) on delete restrict,
  constraint fk_evaluation_events_actor
    foreign key (actor_user_profile_id) references public.user_profiles (id) on delete restrict,
  constraint ck_evaluation_events_type check (event_type in (
    'CRIADA', 'CONCLUIDA', 'REABERTA', 'CANCELADA', 'PENDENCIA_MARCADA',
    'NOTA_ALTERADA', 'COMENTARIO_ALTERADO', 'PARTICIPANTE_ALTERADO'
  )),
  constraint ck_evaluation_events_motivo
    check (event_type not in ('REABERTA', 'CANCELADA') or (motivo is not null and btrim(motivo) <> '')),
  constraint ck_evaluation_events_entidade
    check (entidade is null or btrim(entidade) <> '')
);

create index ix_evaluation_events_evaluation_id on public.evaluation_events (evaluation_id);
create index ix_evaluation_events_organization_id on public.evaluation_events (organization_id);

comment on table public.evaluation_events is
  'F5-06 D26: trilha APPEND-ONLY. Nunca substitui o estado atual; payload nao e '
  'autoridade de tenant/ator (organization_id por FK composta, actor resolvido '
  'server-side). Evento e mutacao na MESMA transacao.';

-- ----------------------------------------------------------------------------
-- 11) evaluation_pendencies — pendências do fechamento (D11/D18)
-- ----------------------------------------------------------------------------
create table public.evaluation_pendencies (
  id                             uuid        not null default gen_random_uuid(),
  organization_id                uuid        not null,
  evaluation_id                  uuid        not null,
  codigo                         text        not null,
  role_type                      text,
  participant_id                 uuid,
  criterion_id                   uuid,
  subcriterion_id                uuid,
  descricao                      text        not null,
  registrada_em                  timestamptz not null default now(),
  registrada_por_user_profile_id uuid        not null,
  constraint pk_evaluation_pendencies primary key (id),
  constraint fk_evaluation_pendencies_evaluation
    foreign key (evaluation_id, organization_id)
    references public.evaluations (id, organization_id) on delete restrict,
  constraint fk_evaluation_pendencies_participant
    foreign key (participant_id, organization_id)
    references public.evaluation_participants (id, organization_id) on delete restrict,
  constraint fk_evaluation_pendencies_registrada_por
    foreign key (registrada_por_user_profile_id) references public.user_profiles (id) on delete restrict,
  constraint ck_evaluation_pendencies_codigo
    check (codigo in ('NOTA_FALTANTE', 'FEEDBACK_FINAL_FALTANTE', 'PARTICIPANTE_OBRIGATORIO_AUSENTE')),
  constraint ck_evaluation_pendencies_descricao check (btrim(descricao) <> ''),
  constraint ck_evaluation_pendencies_role
    check (role_type is null or role_type in ('GESTAO_CADEIA', 'GESTAO_DIRETA', 'COLEGIADO'))
);

create index ix_evaluation_pendencies_evaluation_id on public.evaluation_pendencies (evaluation_id);

-- ----------------------------------------------------------------------------
-- 12) Triggers de updated_at (padrão F1-02) e append-only da trilha
-- ----------------------------------------------------------------------------
create trigger trg_evaluation_config_versions_updated_at
  before update on public.evaluation_config_versions
  for each row execute function public.set_updated_at();
create trigger trg_evaluation_config_criteria_updated_at
  before update on public.evaluation_config_criteria
  for each row execute function public.set_updated_at();
create trigger trg_evaluation_config_subcriteria_updated_at
  before update on public.evaluation_config_subcriteria
  for each row execute function public.set_updated_at();
create trigger trg_evaluation_config_scale_bands_updated_at
  before update on public.evaluation_config_scale_bands
  for each row execute function public.set_updated_at();
create trigger trg_evaluation_config_participant_roles_updated_at
  before update on public.evaluation_config_participant_roles
  for each row execute function public.set_updated_at();
create trigger trg_evaluation_cycles_updated_at
  before update on public.evaluation_cycles
  for each row execute function public.set_updated_at();
create trigger trg_evaluations_updated_at
  before update on public.evaluations
  for each row execute function public.set_updated_at();
create trigger trg_evaluation_participants_updated_at
  before update on public.evaluation_participants
  for each row execute function public.set_updated_at();
create trigger trg_evaluation_scores_updated_at
  before update on public.evaluation_scores
  for each row execute function public.set_updated_at();
create trigger trg_evaluation_comments_updated_at
  before update on public.evaluation_comments
  for each row execute function public.set_updated_at();

-- Trilha append-only: UPDATE negado (DELETE fica fora do runtime — higienização
-- administrativa via owner/superuser, como na F5-04 D18).
create or replace function public.enforce_evaluation_events_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception 'F5-06: evaluation_events e append-only (UPDATE negado)';
end;
$$;

comment on function public.enforce_evaluation_events_append_only() is
  'F5-06 D26/D7: impede UPDATE da trilha de eventos de avaliacao (append-only); '
  'DELETE restrito pela RLS (authenticated sem grant) e higienizacao apenas por '
  'owner/superuser.';

create trigger trg_evaluation_events_append_only
  before update on public.evaluation_events
  for each row execute function public.enforce_evaluation_events_append_only();

-- ----------------------------------------------------------------------------
-- 12.1) Configuração VERSIONADA IMUTÁVEL (D5/D6/D22 — enforcement REAL)
-- ----------------------------------------------------------------------------
-- O contrato exige que a versão publicada seja imutável e que alterações criem
-- NOVA versão. Conceder UPDATE ao caminho server-side não garante isso: era
-- possível alterar critério/subcritério/faixa/papel sob uma avaliação já
-- existente, mudando silenciosamente a regra de uma avaliação em curso. As
-- funções abaixo fecham o buraco no BANCO, não apenas na aplicação.
create or replace function public.enforce_evaluation_config_version_imutavel()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_em_uso boolean;
  v_tem_filhos boolean;
begin
  select exists (
    select 1 from public.evaluations e
     where e.config_version_id = old.id and e.organization_id = old.organization_id
  ) or exists (
    select 1 from public.evaluation_cycles c
     where c.config_version_id = old.id and c.organization_id = old.organization_id
  ) into v_em_uso;

  select exists (
      select 1 from public.evaluation_config_criteria c
       where c.config_version_id = old.id and c.organization_id = old.organization_id
    ) or exists (
      select 1 from public.evaluation_config_scale_bands b
       where b.config_version_id = old.id and b.organization_id = old.organization_id
    ) or exists (
      select 1 from public.evaluation_config_participant_roles r
       where r.config_version_id = old.id and r.organization_id = old.organization_id
    ) into v_tem_filhos;

  -- Versão ainda vazia e não referenciada = rascunho: o bootstrap pode ajustar.
  if v_em_uso or v_tem_filhos then
    raise exception 'F5-06 D5/D22: versao de configuracao publicada/em uso e '
      'imutavel (crie uma NOVA versao para alterar)';
  end if;

  return new;
end;
$$;

comment on function public.enforce_evaluation_config_version_imutavel() is
  'F5-06 D5/D6/D22: uma versao de configuracao que possui criterios/faixas/'
  'papeis ou que ja e referenciada por avaliacao/ciclo e IMUTAVEL — qualquer '
  'UPDATE e recusado e a alteracao exige nova versao.';

create trigger trg_evaluation_config_versions_imutavel
  before update on public.evaluation_config_versions
  for each row execute function public.enforce_evaluation_config_version_imutavel();

-- Filhos da versão: bloqueados quando o pai já está materializado/em uso.
create or replace function public.enforce_evaluation_config_children_imutaveis()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_pai uuid;
  v_org uuid;
  v_bloqueado boolean;
begin
  v_pai := coalesce(new.config_version_id, old.config_version_id);
  v_org := coalesce(new.organization_id, old.organization_id);

  select exists (
      select 1 from public.evaluation_config_criteria c
       where c.config_version_id = v_pai and c.organization_id = v_org
    ) or exists (
      select 1 from public.evaluation_config_scale_bands b
       where b.config_version_id = v_pai and b.organization_id = v_org
    ) or exists (
      select 1 from public.evaluation_config_participant_roles r
       where r.config_version_id = v_pai and r.organization_id = v_org
    ) or exists (
      select 1 from public.evaluations e
       where e.config_version_id = v_pai and e.organization_id = v_org
    ) into v_bloqueado;

  if v_bloqueado then
    raise exception 'F5-06 D5/D22: item de configuracao publicada/em uso e '
      'imutavel (crie uma NOVA versao para alterar)';
  end if;

  return coalesce(new, old);
end;
$$;

comment on function public.enforce_evaluation_config_children_imutaveis() is
  'F5-06 D5/D22: criterios, subcriterios, faixas e papeis de participante de '
  'uma versao ja materializada/publicada nao podem ser alterados in-place.';

create trigger trg_evaluation_config_criteria_imutavel
  before update or delete on public.evaluation_config_criteria
  for each row execute function public.enforce_evaluation_config_children_imutaveis();
create trigger trg_evaluation_config_subcriteria_imutavel
  before update or delete on public.evaluation_config_subcriteria
  for each row execute function public.enforce_evaluation_config_children_imutaveis();
create trigger trg_evaluation_config_scale_bands_imutavel
  before update or delete on public.evaluation_config_scale_bands
  for each row execute function public.enforce_evaluation_config_children_imutaveis();
create trigger trg_evaluation_config_participant_roles_imutavel
  before update or delete on public.evaluation_config_participant_roles
  for each row execute function public.enforce_evaluation_config_children_imutaveis();

-- ----------------------------------------------------------------------------
-- 13) RLS deny-by-default + least privilege (padrão F4-08/D16)
-- ----------------------------------------------------------------------------
alter table public.evaluation_config_versions enable row level security;
alter table public.evaluation_config_criteria enable row level security;
alter table public.evaluation_config_subcriteria enable row level security;
alter table public.evaluation_config_scale_bands enable row level security;
alter table public.evaluation_config_participant_roles enable row level security;
alter table public.evaluation_cycles enable row level security;
alter table public.evaluations enable row level security;
alter table public.evaluation_participants enable row level security;
alter table public.evaluation_scores enable row level security;
alter table public.evaluation_comments enable row level security;
alter table public.evaluation_events enable row level security;
alter table public.evaluation_pendencies enable row level security;

-- Nenhuma tabela do domínio e legível/gravável diretamente por authenticated:
-- leitura e mutação passam por RPC server-side com autorização (F5-06 §12/§14).
revoke all on public.evaluation_config_versions from anon, authenticated, service_role;
revoke all on public.evaluation_config_criteria from anon, authenticated, service_role;
revoke all on public.evaluation_config_subcriteria from anon, authenticated, service_role;
revoke all on public.evaluation_config_scale_bands from anon, authenticated, service_role;
revoke all on public.evaluation_config_participant_roles from anon, authenticated, service_role;
revoke all on public.evaluation_cycles from anon, authenticated, service_role;
revoke all on public.evaluations from anon, authenticated, service_role;
revoke all on public.evaluation_participants from anon, authenticated, service_role;
revoke all on public.evaluation_scores from anon, authenticated, service_role;
revoke all on public.evaluation_comments from anon, authenticated, service_role;
revoke all on public.evaluation_events from anon, authenticated, service_role;
revoke all on public.evaluation_pendencies from anon, authenticated, service_role;

-- service_role atua no caminho server-side (RPC/Edge): leitura necessária ao
-- cálculo/validação; a ESCRITA é feita pelas funções (INVOKER service_role).
grant select on public.evaluation_config_versions to service_role;
grant select on public.evaluation_config_criteria to service_role;
grant select on public.evaluation_config_subcriteria to service_role;
grant select on public.evaluation_config_scale_bands to service_role;
grant select on public.evaluation_config_participant_roles to service_role;
grant select on public.evaluation_cycles to service_role;
grant select on public.evaluations to service_role;
grant select on public.evaluation_participants to service_role;
grant select on public.evaluation_scores to service_role;
grant select on public.evaluation_comments to service_role;
grant select on public.evaluation_events to service_role;
grant select on public.evaluation_pendencies to service_role;

grant insert, update on public.evaluation_config_versions to service_role;
grant insert, update on public.evaluation_config_criteria to service_role;
grant insert, update on public.evaluation_config_subcriteria to service_role;
grant insert, update on public.evaluation_config_scale_bands to service_role;
grant insert, update on public.evaluation_config_participant_roles to service_role;
grant insert, update on public.evaluation_cycles to service_role;
grant insert, update on public.evaluations to service_role;
-- Sem DELETE: avaliacao e decisao auditada (historico preservado).
revoke delete on public.evaluations from service_role;
grant insert, update on public.evaluation_participants to service_role;
-- Sem DELETE: ocorrencias historicas nunca sao apagadas (D23).
revoke delete on public.evaluation_participants from service_role;
grant insert, update, delete on public.evaluation_scores to service_role;
grant insert, update, delete on public.evaluation_comments to service_role;
grant insert on public.evaluation_events to service_role;
grant insert on public.evaluation_pendencies to service_role;
