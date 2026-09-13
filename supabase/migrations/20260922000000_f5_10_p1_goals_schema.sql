-- ============================================================================
-- F5-10 P1 (Issue #210): SCHEMA, INTEGRIDADE e LIMITES das METAS soberanas
-- ----------------------------------------------------------------------------
-- Contrato normativo: docs/F5-10-desenho-tecnico.md (D1-D25; §6.2 tabelas, §7
-- lifecycle, §8 limites, §9 aprovacoes, §11 RLS, §12 concorrencia, §15 testes).
--
-- O que esta migration FAZ (exclusivamente P1 - estrutura):
--   1) public.evaluation_goals            - identidade UUID + vinculos soberanos;
--   2) public.evaluation_goal_approvals   - FATO de aprovacao (nunca campo/status);
--   3) public.evaluation_goal_events      - trilha APPEND-ONLY (D11);
--   4) public.evaluation_cycle_goal_limits- autoridade soberana de quota (D4/D20/D21);
--   5) invariantes estruturais de quota (D20/D21) por trigger NO BANCO;
--   6) RLS DENY-BY-DEFAULT INTEGRAL + ACL minima (nenhuma superficie ao cliente).
--
-- O que esta migration NAO faz (anti-escopo explicito da P1):
--   - nenhuma RPC funcional (criar/editar/progresso/finalizar/revisar/excluir);
--   - nenhuma logica funcional de aprovacao/invalidacao (P3);
--   - nenhuma policy de leitura own-tenant e nenhum grant a authenticated (P4);
--   - nenhuma capability nova, nenhum Edge, nenhum cliente, nenhum cutover.
--
-- Identidade (D1): `evaluation_goals.id` e a identidade canonica; `ano`/`numero`
-- e matricula NAO existem aqui como identidade. Tenant sempre na LINHA
-- (`organization_id`), com FK COMPOSTA para que o vinculo cross-tenant seja
-- impossivel estruturalmente (nao apenas por checagem de aplicacao).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) PREFLIGHT fail-closed do baseline (nao corrige nada; so recusa)
-- ----------------------------------------------------------------------------
do $$
declare
  v_faltando text[] := array[]::text[];
begin
  -- Primitivas soberanas que a P1 referencia.
  if to_regclass('public.organizations') is null then
    v_faltando := v_faltando || 'public.organizations';
  end if;
  if to_regclass('public.collaborators') is null then
    v_faltando := v_faltando || 'public.collaborators';
  end if;
  if to_regclass('public.evaluation_cycles') is null then
    v_faltando := v_faltando || 'public.evaluation_cycles';
  end if;
  if to_regclass('public.user_organization_memberships') is null then
    v_faltando := v_faltando || 'public.user_organization_memberships';
  end if;
  if to_regclass('public.user_profiles') is null then
    v_faltando := v_faltando || 'public.user_profiles';
  end if;
  if to_regprocedure('public.set_updated_at()') is null then
    v_faltando := v_faltando || 'public.set_updated_at()';
  end if;

  -- Chaves candidatas exigidas pelas FKs compostas de tenant.
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycles'::regclass
       and c.conname = 'uq_evaluation_cycles_id_organization'
  ) then
    v_faltando := v_faltando || 'uq_evaluation_cycles_id_organization';
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.collaborators'::regclass
       and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%(id, organization_id)%'
  ) then
    v_faltando := v_faltando || 'collaborators(id, organization_id) unico';
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.user_organization_memberships'::regclass
       and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%(id, organization_id)%'
  ) then
    v_faltando := v_faltando || 'user_organization_memberships(id, organization_id) unico';
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception 'F5-10 P1: baseline incompleto: %', array_to_string(v_faltando, ', ');
  end if;

  -- A migration NAO e idempotente por design (mesma doutrina das fases F5-09):
  -- reexecutar sobre um banco ja migrado deve falhar ALTO, nunca "meio aplicar".
  if to_regclass('public.evaluation_goals') is not null
     or to_regclass('public.evaluation_goal_approvals') is not null
     or to_regclass('public.evaluation_goal_events') is not null
     or to_regclass('public.evaluation_cycle_goal_limits') is not null then
    raise exception 'F5-10 P1: objetos de metas ja existem (esperado banco limpo / db reset)';
  end if;

  raise notice 'F5-10 P1: preflight ok (baseline presente, sem objetos de metas)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) public.evaluation_goals - a meta (D1, D3, D5, D12, D16, D17)
-- ----------------------------------------------------------------------------
create table public.evaluation_goals (
  id                          uuid        not null default gen_random_uuid(),
  organization_id             uuid        not null,
  cycle_id                    uuid        not null,
  collaborator_id             uuid        not null,
  tipo                        text        not null,
  descricao                   text        not null,
  kpi                         text        not null,
  valor_alvo                  text        not null,
  status                      text        not null default 'EM_ANDAMENTO',
  resultado_atual             text,
  progresso_percentual        integer,
  data_ultimo_acompanhamento  timestamptz,
  resultado_final             text,
  atingida                    boolean,
  data_fechamento             timestamptz,
  excluida                    boolean     not null default false,
  data_exclusao               timestamptz,
  version                     integer     not null default 0,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint pk_evaluation_goals primary key (id),
  constraint uq_evaluation_goals_id_organization unique (id, organization_id),
  constraint fk_evaluation_goals_organizations
    foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  -- FK COMPOSTA: o ciclo da meta tem de ser do MESMO tenant da meta
  -- (isolamento estrutural cross-tenant).
  constraint fk_evaluation_goals_cycle
    foreign key (cycle_id, organization_id)
    references public.evaluation_cycles (id, organization_id)
    on delete restrict,
  constraint fk_evaluation_goals_collaborator
    foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint ck_evaluation_goals_tipo
    check (tipo in ('NEGOCIO_PROJETO', 'INDIVIDUAL')),
  constraint ck_evaluation_goals_status
    check (status in ('EM_ANDAMENTO', 'ATINGIDA', 'NAO_ATINGIDA')),
  -- D16: progresso e INTEIRO informado no dominio 0..100 (validacao server-side,
  -- nunca derivado de `valor_alvo`, que e texto).
  constraint ck_evaluation_goals_progresso
    check (progresso_percentual is null
           or (progresso_percentual >= 0 and progresso_percentual <= 100)),
  constraint ck_evaluation_goals_textos
    check (descricao <> '' and descricao = btrim(descricao)
           and kpi <> '' and kpi = btrim(kpi)
           and valor_alvo <> '' and valor_alvo = btrim(valor_alvo)),
  constraint ck_evaluation_goals_version check (version >= 0),
  -- D5: exclusao APENAS logica - os dois campos andam juntos.
  constraint ck_evaluation_goals_exclusao
    check ((excluida = false and data_exclusao is null)
           or (excluida = true and data_exclusao is not null)),
  -- D17 (ENDURECIDO na correcao pos-auditoria): o estado de fechamento tem de
  -- ser COERENTE, nao apenas "completo". Combinações contraditorias nascem
  -- recusadas: `EM_ANDAMENTO` NAO pode ter campos de fechamento; `ATINGIDA`
  -- exige `atingida = true` e `NAO_ATINGIDA` exige `atingida = false`; o
  -- `resultado_final` e obrigatorio, NAO VAZIO e sem espacos nas bordas.
  constraint ck_evaluation_goals_fechamento
    check (
      (status = 'EM_ANDAMENTO'
       and resultado_final is null and atingida is null and data_fechamento is null)
      or (status = 'ATINGIDA'
          and atingida = true
          and data_fechamento is not null
          and resultado_final is not null
          and resultado_final <> ''
          and resultado_final = btrim(resultado_final))
      or (status = 'NAO_ATINGIDA'
          and atingida = false
          and data_fechamento is not null
          and resultado_final is not null
          and resultado_final <> ''
          and resultado_final = btrim(resultado_final))
    )
);

comment on table public.evaluation_goals is
  'F5-10 P1 (D1/D3/D5/D16/D17): meta soberana. Identidade = id (uuid, gerado '
  'pelo banco); cycle_id e collaborator_id sao os vinculos SOBERANOS (uuid) e '
  '`ano`/`numero`/matricula NAO existem como identidade. `status` e o estado '
  'FUNCIONAL e NAO representa aprovacao (D3): aprovacao e FATO em '
  'evaluation_goal_approvals. Exclusao apenas logica (D5). `version` e a base do '
  'expected_version (D12).';
comment on column public.evaluation_goals.progresso_percentual is
  'F5-10 P1 (D16): inteiro informado, 0..100, validado no banco; NUNCA derivado '
  'de resultado_atual/valor_alvo enquanto valor_alvo for texto.';
comment on column public.evaluation_goals.valor_alvo is
  'F5-10 P1: rotulo textual do alvo (mesmo tipo do legado). Nao e identidade nem '
  'fonte de calculo de progresso nesta fase.';
comment on column public.evaluation_goals.atingida is
  'F5-10 P1 (D17): resultado do fechamento (true = ATINGIDA, false = '
  'NAO_ATINGIDA). Revisao de fechamento (P2) nao sobrescreve silenciosamente: '
  'gera evento REVISAO_FINALIZACAO com before/after.';
comment on column public.evaluation_goals.version is
  'F5-10 P1 (D12): versao otimista. Toda mutacao efetiva incrementa 1; a RPC '
  'compara expected_version apos o lock e responde CONFLICT quando diverge.';

-- Unicidade PARCIAL (D1/§6.2): uma unica meta VIVA por (organizacao, ciclo,
-- dono, tipo). Metas excluidas logicamente nao bloqueiam nova criacao.
create unique index uq_evaluation_goals_org_cycle_collab_tipo_viva
  on public.evaluation_goals (organization_id, cycle_id, collaborator_id, tipo)
  where excluida = false;

create index ix_evaluation_goals_organization_id
  on public.evaluation_goals (organization_id);
create index ix_evaluation_goals_cycle
  on public.evaluation_goals (organization_id, cycle_id);
create index ix_evaluation_goals_collaborator
  on public.evaluation_goals (organization_id, collaborator_id);
create index ix_evaluation_goals_status
  on public.evaluation_goals (organization_id, cycle_id, status)
  where excluida = false;

create trigger trg_evaluation_goals_updated_at
  before update on public.evaluation_goals
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2) public.evaluation_cycle_goal_limits - QUOTA soberana por ciclo (D4/D20/D21)
-- ----------------------------------------------------------------------------
create table public.evaluation_cycle_goal_limits (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  cycle_id        uuid        not null,
  tipo            text        not null,
  quantidade      integer     not null,
  version         integer     not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint pk_evaluation_cycle_goal_limits primary key (id),
  constraint uq_evaluation_cycle_goal_limits_id_organization unique (id, organization_id),
  constraint fk_evaluation_cycle_goal_limits_organizations
    foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint fk_evaluation_cycle_goal_limits_cycle
    foreign key (cycle_id, organization_id)
    references public.evaluation_cycles (id, organization_id)
    on delete restrict,
  constraint uq_evaluation_cycle_goal_limits_cycle_tipo unique (cycle_id, tipo),
  constraint ck_evaluation_cycle_goal_limits_tipo
    check (tipo in ('NEGOCIO_PROJETO', 'INDIVIDUAL')),
  -- Mesmo dominio do contrato (0|1|2|3) - a quota e configuracao do ciclo.
  constraint ck_evaluation_cycle_goal_limits_quantidade
    check (quantidade >= 0 and quantidade <= 3),
  constraint ck_evaluation_cycle_goal_limits_version check (version >= 0)
);

comment on table public.evaluation_cycle_goal_limits is
  'F5-10 P1 (D4/D20/D21): AUTORIDADE soberana da quota de metas por '
  '(ciclo, tipo). Substitui os campos de quota do ciclo legado; nenhuma coluna '
  'de metas foi adicionada ao contrato funcional de evaluation_cycles. A quota e '
  'invariante server-side: o banco recusa meta acima do limite (trigger) e '
  'recusa reduzir a quota abaixo das metas vivas (trigger), nunca confiando na UI.';
comment on column public.evaluation_cycle_goal_limits.quantidade is
  'F5-10 P1: 0..3 (mesmo dominio do contrato). Ausencia de linha = quota ZERO '
  '(fail-closed): o banco nao cria meta de um tipo sem configuracao explicita.';

create index ix_evaluation_cycle_goal_limits_organization_id
  on public.evaluation_cycle_goal_limits (organization_id);
create index ix_evaluation_cycle_goal_limits_cycle
  on public.evaluation_cycle_goal_limits (organization_id, cycle_id);

create trigger trg_evaluation_cycle_goal_limits_updated_at
  before update on public.evaluation_cycle_goal_limits
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 3) public.evaluation_goal_approvals - FATO de aprovacao (D2, §9)
-- ----------------------------------------------------------------------------
create table public.evaluation_goal_approvals (
  id                  uuid        not null default gen_random_uuid(),
  organization_id     uuid        not null,
  goal_id             uuid        not null,
  papel               text        not null,
  -- AUTORIA SOBERANA COMPLETA (D2/§9.3, corrigido na revisao pos-auditoria): o
  -- fato de aprovacao guarda o PERFIL e a MEMBERSHIP do ator - nunca matricula,
  -- nome ou qualquer identidade textual.
  actor_user_profile_id uuid      not null,
  actor_membership_id uuid        not null,
  decidido_em         timestamptz not null default now(),
  motivo              text,
  revogado_em         timestamptz,
  revogado_motivo     text,
  version             integer     not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint pk_evaluation_goal_approvals primary key (id),
  constraint uq_evaluation_goal_approvals_id_organization unique (id, organization_id),
  constraint fk_evaluation_goal_approvals_organizations
    foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  -- FK COMPOSTA: a aprovacao e da meta do MESMO tenant.
  constraint fk_evaluation_goal_approvals_goal
    foreign key (goal_id, organization_id)
    references public.evaluation_goals (id, organization_id)
    on delete restrict,
  -- AUTORIA SOBERANA (D2/D14): membership verificada no tenant da linha.
  constraint fk_evaluation_goal_approvals_actor_membership
    foreign key (actor_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict,
  -- AUTORIA SOBERANA (D2/§9.3): o PERFIL do ator e FK real de identidade.
  constraint fk_evaluation_goal_approvals_actor_profile
    foreign key (actor_user_profile_id)
    references public.user_profiles (id)
    on delete restrict,
  constraint ck_evaluation_goal_approvals_papel
    check (papel in ('COORDENADOR', 'GERENTE')),
  constraint ck_evaluation_goal_approvals_version check (version >= 0),
  constraint ck_evaluation_goal_approvals_motivo
    check (motivo is null or (motivo <> '' and motivo = btrim(motivo))),
  constraint ck_evaluation_goal_approvals_revogacao
    check ((revogado_em is null and revogado_motivo is null)
           or (revogado_em is not null))
);

comment on table public.evaluation_goal_approvals is
  'F5-10 P1 (D2/D19/§9): a aprovacao e um FATO auditavel - linha propria, '
  'autoria soberana COMPLETA (actor_user_profile_id + actor_membership_id, '
  'ambos coerentes entre si e com o tenant) e historico preservado. NUNCA e '
  'campo mutavel em evaluation_goals nem status funcional. Revogacao/invalidacao '
  'grava revogado_em (nunca apaga o fato); a aprovacao vigente e a linha com '
  'revogado_em is null (unicidade parcial por papel). A legitimidade de QUEM '
  'aprova (GESTAO_CADEIA/GESTAO_DIRETA - D14/D25) e resolvida pela operacao da '
  'P3, nao por constraint.';
comment on column public.evaluation_goal_approvals.actor_user_profile_id is
  'F5-10 P1 (D2/§9.3): perfil soberano do autor da decisao (FK para '
  'user_profiles). Nao e matricula, nome nem identidade textual; a coerencia com '
  'actor_membership_id e garantida por trigger (mesmo perfil da membership no '
  'tenant da linha).';
comment on column public.evaluation_goal_approvals.decidido_em is
  'F5-10 P1: instante da decisao (server-side). Nao e a data de gravacao da '
  'revisao (created_at) e nunca vem do cliente.';
comment on column public.evaluation_goal_approvals.revogado_em is
  'F5-10 P1 (D19): quando preenchido, o fato esta invalidado/revogado. A linha '
  'permanece na tabela e na trilha - invalidar nao apaga historico.';

-- Uma unica aprovacao VIGENTE por (meta, papel): a segunda vira CONFLICT na P3.
create unique index uq_evaluation_goal_approvals_goal_papel_vigente
  on public.evaluation_goal_approvals (goal_id, papel)
  where revogado_em is null;

create index ix_evaluation_goal_approvals_organization_id
  on public.evaluation_goal_approvals (organization_id);
create index ix_evaluation_goal_approvals_goal
  on public.evaluation_goal_approvals (organization_id, goal_id);

create trigger trg_evaluation_goal_approvals_updated_at
  before update on public.evaluation_goal_approvals
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 3.1) COERENCIA DA AUTORIA SOBERANA (D2/§9.3) — decisao de desenho registrada
-- ----------------------------------------------------------------------------
-- Os dois campos de autoria exigidos pelo contrato (perfil + membership) sao
-- ambos NOT NULL e cada um tem FK propria. A COERENCIA entre eles (a membership
-- pertence ao perfil informado) NAO pode ser expressa por FK composta sem ALTERAR
-- contrato anterior: `user_organization_memberships` possui a chave candidata
-- `(id, organization_id)` (usada pelas FKs de tenant de todo o projeto), mas NAO
-- possui `(id, organization_id, user_profile_id)` — e criar indice/chave nova
-- naquela tabela seria mexer em contrato fechado de outra fase. A alternativa
-- adotada, SEM alterar contrato anterior e SEM nova arquitetura, e o trigger
-- abaixo (mesma doutrina de invariante estrutural das quotas): fail-closed na
-- gravacao, com mensagem explicita.
create or replace function public.f5_10_validar_autoria_da_aprovacao()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_perfil uuid;
begin
  -- Ausencia de perfil NAO e tratada aqui: quem recusa e o NOT NULL da coluna
  -- (23502), para que a mensagem de erro seja a do contrato de schema. Este
  -- trigger cuida apenas de COERENCIA entre valores efetivamente informados.
  if new.actor_user_profile_id is null then
    return new;
  end if;

  -- Perfil INEXISTENTE tambem nao e tratado aqui: quem recusa e a FK
  -- fk_evaluation_goal_approvals_actor_profile (23503). Assim cada classe de
  -- defeito tem o seu codigo: 23502 (ausente), 23503 (perfil inexistente) e
  -- P0001 (perfil existente, porem incoerente com a membership/tenant).
  if not exists (
    select 1 from public.user_profiles p where p.id = new.actor_user_profile_id
  ) then
    return new;
  end if;

  select m.user_profile_id into v_perfil
    from public.user_organization_memberships m
   where m.id = new.actor_membership_id
     and m.organization_id = new.organization_id;

  -- A FK composta ja garante que a membership existe NO TENANT da linha; aqui se
  -- garante que ela pertence ao PERFIL informado como autor da decisao.
  if v_perfil is distinct from new.actor_user_profile_id then
    raise exception
      'F5-10: autoridade de aprovacao incoerente (actor_user_profile_id % nao e o perfil da membership % no tenant %)',
      new.actor_user_profile_id, new.actor_membership_id, new.organization_id;
  end if;

  return new;
end;
$$;

comment on function public.f5_10_validar_autoria_da_aprovacao() is
  'F5-10 P1 (D2/§9.3): invariante de COERENCIA da autoria soberana - o perfil '
  'informado tem de ser o perfil da membership informada, no tenant da linha. '
  'Nao decide legitimidade funcional (isso e a P3): apenas impede autoria '
  'incoerente ou forjada no fato de aprovacao.';

create trigger trg_evaluation_goal_approvals_autoria
  before insert or update of actor_user_profile_id, actor_membership_id, organization_id
  on public.evaluation_goal_approvals
  for each row execute function public.f5_10_validar_autoria_da_aprovacao();

-- ----------------------------------------------------------------------------
-- 4) public.evaluation_goal_events - trilha APPEND-ONLY (D11, §13)
-- ----------------------------------------------------------------------------
create table public.evaluation_goal_events (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null,
  goal_id               uuid        not null,
  entity_type           text        not null,
  event_type            text        not null,
  effective_date        timestamptz not null,
  reason                text,
  before_value          jsonb,
  after_value           jsonb,
  payload_hash          text        not null,
  result_entity_id      uuid,
  actor_user_profile_id uuid        not null,
  actor_membership_id   uuid        not null,
  operation_id          uuid        not null,
  created_at            timestamptz not null default now(),
  constraint pk_evaluation_goal_events primary key (id),
  constraint fk_evaluation_goal_events_organizations
    foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  -- FK COMPOSTA: o evento e da meta do MESMO tenant.
  constraint fk_evaluation_goal_events_goal
    foreign key (goal_id, organization_id)
    references public.evaluation_goals (id, organization_id)
    on delete restrict,
  constraint fk_evaluation_goal_events_actor
    foreign key (actor_user_profile_id)
    references public.user_profiles (id)
    on delete restrict,
  constraint fk_evaluation_goal_events_actor_membership
    foreign key (actor_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict,
  -- Idempotencia (D11): retry com o mesmo operation_id nao duplica evento.
  constraint uq_evaluation_goal_events_org_operation
    unique (organization_id, operation_id),
  constraint ck_evaluation_goal_events_entity_type
    check (entity_type = 'evaluation_goal'),
  -- Tipos do contrato (§6.2). O CHECk e FECHADO e ja contempla as operacoes da
  -- P2/P3 para nao reabrir contrato fechado depois.
  constraint ck_evaluation_goal_events_event_type
    check (event_type in (
      'CRIADA', 'EDITADA', 'PROGRESSO_ATUALIZADO', 'FINALIZADA',
      'REVISAO_FINALIZACAO', 'EXCLUIDA', 'APROVACAO_COORDENADOR',
      'APROVACAO_GERENTE', 'APROVACAO_INVALIDADA',
      'LIMITES_DO_CICLO_ALTERADOS')),
  constraint ck_evaluation_goal_events_reason
    check (reason is null or (reason <> '' and reason = btrim(reason))),
  -- `payload_hash` = SHA-256 hex minusculo de 64 caracteres, DERIVADO
  -- server-side pela RPC (nunca parametro do cliente).
  constraint ck_evaluation_goal_events_payload_hash
    check (payload_hash ~ '^[0-9a-f]{64}$')
);

comment on table public.evaluation_goal_events is
  'F5-10 P1 (D11/§13): log APPEND-ONLY das mutacoes oficiais de meta. Registra '
  'tenant, meta, tipo de operacao, data de efeito, motivo, delta normalizado, '
  'autor soberano (auth.uid + membership), hash do payload da intencao e '
  'idempotencia por (organization_id, operation_id). O estado oficial continua '
  'em evaluation_goals; a trilha registra, nao decide. APPEND-ONLY COMPLETO: '
  'UPDATE/DELETE/TRUNCATE negados por trigger (mesmo para owner e service_role) '
  'e, na primeira camada, por ausencia de grant.';
comment on column public.evaluation_goal_events.effective_date is
  'F5-10 P1: data de EFEITO da mudanca, nunca a data de gravacao (created_at).';
comment on column public.evaluation_goal_events.payload_hash is
  'F5-10 P1 (D11): SHA-256 hex do payload canonico da INTENCAO. Mesmo '
  'operation_id + mesmo hash devolve o mesmo resultado; hash divergente e '
  'CONFLICT (regra aplicada pela operacao da P2).';

create index ix_evaluation_goal_events_organization_id
  on public.evaluation_goal_events (organization_id);
create index ix_evaluation_goal_events_goal
  on public.evaluation_goal_events (organization_id, goal_id);
create index ix_evaluation_goal_events_effective
  on public.evaluation_goal_events (organization_id, effective_date);

-- Append-only no BANCO em PROFUNDIDADE (mesma doutrina de cycle_events):
-- UPDATE/DELETE/TRUNCATE levantam excecao por trigger, INCLUSIVE para o owner e
-- para service_role; os revokes do bloco 6 sao a PRIMEIRA camada e o trigger e a
-- SEGUNDA, resistente a privilege drift.
create or replace function public.enforce_evaluation_goal_events_append_only()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  raise exception 'F5-10: evaluation_goal_events e append-only (% negado)', tg_op;
end;
$$;

comment on function public.enforce_evaluation_goal_events_append_only() is
  'F5-10 P1 (D11): torna a trilha de metas APPEND-ONLY NO BANCO - UPDATE, DELETE '
  'e TRUNCATE levantam excecao mesmo para o owner e para service_role, '
  'resistindo a privilege drift.';

create trigger trg_evaluation_goal_events_append_only
  before update on public.evaluation_goal_events
  for each row execute function public.enforce_evaluation_goal_events_append_only();

create trigger trg_evaluation_goal_events_no_delete
  before delete on public.evaluation_goal_events
  for each row execute function public.enforce_evaluation_goal_events_append_only();

create trigger trg_evaluation_goal_events_no_truncate
  before truncate on public.evaluation_goal_events
  for each statement execute function public.enforce_evaluation_goal_events_append_only();

-- ----------------------------------------------------------------------------
-- 5) INVARIANTES DE QUOTA no banco (D20/D21) - nenhuma confianca na UI
-- ----------------------------------------------------------------------------
-- ESCOPO DECLARADO: estes invariantes sao ESTRUTURAIS (unicidade/limite por
-- linha e por agregado). A P1 NAO alega protecao autonoma contra CORRIDA
-- concorrente: o COUNT sem lock e proposital e sera serializado pela familia
-- normativa de advisory lock nas OPERACOES SOBERANAS da P2 (e provado com
-- concorrencia real na P7). NENHUMA familia de lock nova e criada aqui.
-- (a) Criar/reativar meta acima da quota => recusa.
--     Ausencia de linha de quota = quota ZERO (fail-closed), coerente com o
--     legado (`ciclo.quantidadeMetas* ?? 0`).
create or replace function public.f5_10_validar_quota_da_meta()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_limite    integer;
  v_vivas     integer;
begin
  -- Meta excluida logicamente nao consome quota.
  if new.excluida then
    return new;
  end if;

  select l.quantidade into v_limite
    from public.evaluation_cycle_goal_limits l
   where l.organization_id = new.organization_id
     and l.cycle_id = new.cycle_id
     and l.tipo = new.tipo;

  if v_limite is null then
    raise exception
      'F5-10: quota de metas % do ciclo % nao configurada (quota zero; fail-closed)',
      new.tipo, new.cycle_id;
  end if;

  select count(*) into v_vivas
    from public.evaluation_goals g
   where g.organization_id = new.organization_id
     and g.cycle_id = new.cycle_id
     and g.tipo = new.tipo
     and g.excluida = false
     and g.id <> new.id;

  if v_vivas + 1 > v_limite then
    raise exception
      'F5-10: quota de metas % do ciclo excedida (limite %, vivas %, nova 1)',
      new.tipo, v_limite, v_vivas;
  end if;

  return new;
end;
$$;

comment on function public.f5_10_validar_quota_da_meta() is
  'F5-10 P1 (D20): INVARIANTE de quota no banco - a criacao (ou reativacao por '
  'soft delete revertido) de meta acima do limite e recusada pelo proprio '
  'PostgreSQL, independentemente do cliente.';

create trigger trg_evaluation_goals_quota
  before insert or update of tipo, cycle_id, excluida, organization_id
  on public.evaluation_goals
  for each row execute function public.f5_10_validar_quota_da_meta();

-- (b) Reduzir a quota abaixo das metas vivas => recusa (D21).
create or replace function public.f5_10_validar_quota_do_limite()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_vivas integer;
begin
  select count(*) into v_vivas
    from public.evaluation_goals g
   where g.organization_id = new.organization_id
     and g.cycle_id = new.cycle_id
     and g.tipo = new.tipo
     and g.excluida = false;

  if new.quantidade < v_vivas then
    raise exception
      'F5-10: quota de metas % do ciclo nao pode ser reduzida para % (existem % metas vivas)',
      new.tipo, new.quantidade, v_vivas;
  end if;

  return new;
end;
$$;

comment on function public.f5_10_validar_quota_do_limite() is
  'F5-10 P1 (D21): a quota nunca pode ficar ABAIXO da quantidade de metas nao '
  'excluidas daquele tipo; a recusa e estrutural (trigger), nunca apenas de UI.';

create trigger trg_evaluation_cycle_goal_limits_quota
  before insert or update of quantidade, tipo, cycle_id
  on public.evaluation_cycle_goal_limits
  for each row execute function public.f5_10_validar_quota_do_limite();

-- (c) Apagar a linha de quota "zeraria" a quota em silencio => recusa.
create or replace function public.f5_10_proteger_limite_do_ciclo()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  raise exception 'F5-10: evaluation_cycle_goal_limits nao aceita DELETE (altere a quota pela operacao soberana)';
end;
$$;

comment on function public.f5_10_proteger_limite_do_ciclo() is
  'F5-10 P1 (D4/D21): apagar a quota faria a proxima criacao cair em '
  'fail-closed silenciosamente; a protecao e explicita.';

create trigger trg_evaluation_cycle_goal_limits_no_delete
  before delete on public.evaluation_cycle_goal_limits
  for each row execute function public.f5_10_proteger_limite_do_ciclo();

-- ----------------------------------------------------------------------------
-- 6) RLS e ACL: DENY-BY-DEFAULT INTEGRAL (P1 nao abre superficie ao cliente)
-- ----------------------------------------------------------------------------
-- A P1 NAO cria policy de leitura nem grant a authenticated/anon: a matriz
-- funcional de leitura e da P4 (D22). Nesta fase o cliente nao tem NENHUM
-- privilegio e nenhuma policy existe - fail-closed por construcao. O executor
-- tecnico e `service_role` (nunca autoridade funcional).
alter table public.evaluation_goals enable row level security;
alter table public.evaluation_goal_approvals enable row level security;
alter table public.evaluation_goal_events enable row level security;
alter table public.evaluation_cycle_goal_limits enable row level security;

revoke all on public.evaluation_goals from public, anon, authenticated, service_role;
grant select, insert, update on public.evaluation_goals to service_role;
revoke delete, truncate on public.evaluation_goals from service_role;

revoke all on public.evaluation_goal_approvals from public, anon, authenticated, service_role;
grant select, insert, update on public.evaluation_goal_approvals to service_role;
revoke delete, truncate on public.evaluation_goal_approvals from service_role;

revoke all on public.evaluation_goal_events from public, anon, authenticated, service_role;
grant select, insert on public.evaluation_goal_events to service_role;
revoke update, delete, truncate on public.evaluation_goal_events from service_role;

revoke all on public.evaluation_cycle_goal_limits from public, anon, authenticated, service_role;
grant select, insert, update on public.evaluation_cycle_goal_limits to service_role;
revoke delete, truncate on public.evaluation_cycle_goal_limits from service_role;

-- ----------------------------------------------------------------------------
-- 7) GUARDA FINAL fail-closed: prova o contrato que a P1 fecha
-- ----------------------------------------------------------------------------
do $$
declare
  v_tab    text;
  v_falhas text[] := array[]::text[];
  v_n      int;
begin
  -- (a) as 4 tabelas existem com RLS habilitada.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relkind = 'r'
    ) then
      v_falhas := v_falhas || format('tabela ausente: %s', v_tab);
      continue;
    end if;
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      v_falhas := v_falhas || format('RLS desabilitada: %s', v_tab);
    end if;
    -- DENY-BY-DEFAULT: nenhuma policy em nenhuma das quatro tabelas.
    if exists (
      select 1 from pg_policies p
       where p.schemaname = 'public' and p.tablename = v_tab
    ) then
      v_falhas := v_falhas || format('policy indevida na P1: %s', v_tab);
    end if;
    -- Nenhum privilegio ao cliente.
    if has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('anon', format('public.%I', v_tab), 'SELECT')
       or has_table_privilege('anon', format('public.%I', v_tab), 'INSERT')
       or has_table_privilege('anon', format('public.%I', v_tab), 'UPDATE')
       or has_table_privilege('anon', format('public.%I', v_tab), 'DELETE') then
      v_falhas := v_falhas || format('privilegio de cliente: %s', v_tab);
    end if;
  end loop;

  -- (b) service_role e EXECUTOR tecnico (sem DELETE/TRUNCATE).
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if has_table_privilege('service_role', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('service_role', format('public.%I', v_tab), 'TRUNCATE') then
      v_falhas := v_falhas || format('service_role com DELETE/TRUNCATE: %s', v_tab);
    end if;
  end loop;

  -- (c) trilha append-only com os TRES triggers.
  select count(*) into v_n
    from pg_trigger t
   where t.tgrelid = 'public.evaluation_goal_events'::regclass
     and not t.tgisinternal
     and t.tgname in ('trg_evaluation_goal_events_append_only',
                      'trg_evaluation_goal_events_no_delete',
                      'trg_evaluation_goal_events_no_truncate');
  if v_n <> 3 then
    v_falhas := v_falhas || format('triggers append-only da trilha = %s (esperado 3)', v_n);
  end if;

  -- (d) invariantes de quota presentes.
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_goals'::regclass
       and t.tgname = 'trg_evaluation_goals_quota' and not t.tgisinternal
  ) then
    v_falhas := v_falhas || 'trigger de quota da meta ausente';
  end if;
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_cycle_goal_limits'::regclass
       and t.tgname = 'trg_evaluation_cycle_goal_limits_quota' and not t.tgisinternal
  ) then
    v_falhas := v_falhas || 'trigger de reducao de quota ausente';
  end if;
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_cycle_goal_limits'::regclass
       and t.tgname = 'trg_evaluation_cycle_goal_limits_no_delete' and not t.tgisinternal
  ) then
    v_falhas := v_falhas || 'protecao contra DELETE de quota ausente';
  end if;

  -- (e) unicidades parciais do contrato.
  if not exists (
    select 1 from pg_indexes i
     where i.schemaname = 'public' and i.tablename = 'evaluation_goals'
       and i.indexname = 'uq_evaluation_goals_org_cycle_collab_tipo_viva'
  ) then
    v_falhas := v_falhas || 'unico parcial de meta viva ausente';
  end if;
  if not exists (
    select 1 from pg_indexes i
     where i.schemaname = 'public' and i.tablename = 'evaluation_goal_approvals'
       and i.indexname = 'uq_evaluation_goal_approvals_goal_papel_vigente'
  ) then
    v_falhas := v_falhas || 'unico parcial de aprovacao vigente ausente';
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycle_goal_limits'::regclass
       and c.conname = 'uq_evaluation_cycle_goal_limits_cycle_tipo' and c.contype = 'u'
  ) then
    v_falhas := v_falhas || 'unico (cycle_id, tipo) da quota ausente';
  end if;

  -- (f) FKs COMPOSTAS de tenant (isolamento cross-tenant estrutural).
  foreach v_tab in array array[
    'fk_evaluation_goals_cycle', 'fk_evaluation_goals_collaborator',
    'fk_evaluation_goal_approvals_goal', 'fk_evaluation_goal_events_goal',
    'fk_evaluation_cycle_goal_limits_cycle'] loop
    if not exists (
      select 1 from pg_constraint c
       where c.conname = v_tab and c.contype = 'f'
         and pg_get_constraintdef(c.oid) like '%organization_id)%'
    ) then
      v_falhas := v_falhas || format('FK composta de tenant ausente: %s', v_tab);
    end if;
  end loop;

  -- (g) nenhuma RPC/Edge/capability nova (anti-escopo da P1).
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%');
  if v_n <> 0 then
    v_falhas := v_falhas || format('RPC funcional de meta antecipada: %s', v_n);
  end if;

  -- (h) AUTORIA SOBERANA COMPLETA da aprovacao (D2/§9.3, correcao pos-auditoria):
  --     coluna NOT NULL, FK propria de perfil e trigger de coerencia.
  if not exists (
    select 1 from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'evaluation_goal_approvals'
       and c.column_name = 'actor_user_profile_id' and c.is_nullable = 'NO'
  ) then
    v_falhas := v_falhas || 'actor_user_profile_id ausente ou nullable em evaluation_goal_approvals';
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_goal_approvals'::regclass
       and c.conname = 'fk_evaluation_goal_approvals_actor_profile' and c.contype = 'f'
       and pg_get_constraintdef(c.oid) like '%user_profiles%'
  ) then
    v_falhas := v_falhas || 'FK de perfil do autor ausente em evaluation_goal_approvals';
  end if;
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_goal_approvals'::regclass
       and t.tgname = 'trg_evaluation_goal_approvals_autoria' and not t.tgisinternal
  ) then
    v_falhas := v_falhas || 'trigger de coerencia de autoria ausente';
  end if;

  -- (i) CHECK de fechamento ENDURECIDO (D17, correcao pos-auditoria): a definicao
  --     precisa conter as clausulas coerentes de ATINGIDA/NAO_ATINGIDA e o
  --     non-empty/trim do resultado_final.
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_goals'::regclass
       and c.conname = 'ck_evaluation_goals_fechamento' and c.contype = 'c'
       and pg_get_constraintdef(c.oid) like '%ATINGIDA%'
       and pg_get_constraintdef(c.oid) like '%NAO_ATINGIDA%'
       and pg_get_constraintdef(c.oid) like '%btrim%'
  ) then
    v_falhas := v_falhas || 'CHECK de fechamento nao esta endurecido (D17)';
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception 'F5-10 P1: guarda final reprovou: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-10 P1: guarda final ok (4 tabelas com RLS deny-by-default, ACL minima, trilha append-only com 3 triggers, invariantes de quota e FKs compostas de tenant)';
end $$;
