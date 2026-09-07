-- ============================================================================
-- F3-08 (Issue #85): colegiado padrão e snapshot por ciclo
-- ----------------------------------------------------------------------------
-- Propósito: modelar a configuração padrão do colegiado de avaliação (0..N,
-- opcional) e o snapshot imutável por ciclo, separando as relações avaliativas
-- transversais da hierarquia formal. O colegiado NÃO cria PositionReportingLine,
-- occupation nem escopo hierárquico.
--
-- Decisões D1–D14 + QA/QB registradas nesta migration:
--   - configuração padrão ancorada no COLLABORATOR AVALIADO (D1); a lista de
--     membros é EXPLÍCITA por avaliado, 0..N, sem derivação por cargo/
--     senioridade/unidade/reporting line (D2);
--   - membros: colaboradores da mesma organização, sem self e sem duplicados
--     (D3); cardinalidade 0..N; 0 membros = "sem colegiado", distinguível de
--     ausência de configuração (D8);
--   - validade temporal da configuração: períodos meio-abertos
--     `[valid_from, valid_to)` por avaliado (valid_to null = vigente; exclusão
--     de sobreposição; no máximo uma vigente); mudanças normais fecham a versão
--     e criam nova, preservando o histórico de configuração (D4/D9/D10);
--   - snapshot por ciclo: chave de negócio (organization_id, ano, ciclo) +
--     collaborator_id do avaliado, SEM tabela de ciclos (D5/D14; integração
--     futura com a entidade canônica de ciclo); unique por
--     (organization_id, ano, ciclo, collaborator_id);
--   - conteúdo do snapshot (D7-B/QA/QB): para cada avaliado informado
--     explicitamente pelo chamador (QA-A), registra posições ocupadas na data
--     de referência, superior formal direto resolvido por posição (F3-07:
--     responsável = substituto operacional > titular > NULL) e membros do
--     colegiado congelados da configuração vigente; avaliado sem posição na
--     data gera snapshot válido com posições vazias (QB-A); identidades por
--     UUID, sem cópia de nomes/cargos;
--   - materialização: RPC EXPLÍCITA, transacional e idempotente
--     (`materializar_colegiado_ciclo`), executada na ativação do ciclo
--     (PLANEJADO → ATIVO), recebendo organization_id, ano, ciclo, data de
--     referência e a lista de avaliados (D6/QA); repetição não duplica nem
--     substitui snapshots (ON CONFLICT DO NOTHING + guardas por snapshot);
--   - snapshots IMUTÁVEIS no fluxo normal (D10): sem update/delete físico,
--     sem recálculo automático por mudanças posteriores de config/occupation/
--     reporting (D9); correção retroativa excepcional fora do escopo;
--   - integridade multi-organização por FKs compostas
--     `(ref_id, organization_id) → (id, organization_id)` (D11); ON DELETE
--     RESTRICT em todas as FKs (D12);
--   - RLS habilitado e deny-by-default nas tabelas novas, sem policies/grants;
--     funções SECURITY INVOKER, sem bypass (D13);
--   - ciclos do localStorage permanecem intactos (sem migração) — apenas o
--     alinhamento da chave de negócio (D14).
--
-- Fora do escopo (não antecipar): capabilities/RLS finais, notas/votos/pesos
-- do colegiado, UI final, migração do domínio de ciclos, dados reais,
-- correção retroativa excepcional.
--
-- Dependências: public.organizations (F2-01), public.collaborators (F3-01),
-- public.organizational_positions/position_reporting_lines/occupations
-- (F3-03/04/05), funções de resolução da F3-07, extensão btree_gist (F3-01).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) public.collegiate_configurations — versões temporais por avaliado
-- ----------------------------------------------------------------------------
create table public.collegiate_configurations (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  collaborator_id uuid        not null,
  valid_from      timestamptz not null,
  valid_to        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_collegiate_configurations primary key (id),
  constraint uq_collegiate_configurations_id_organization unique (id, organization_id),
  constraint fk_collegiate_configurations_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint fk_collegiate_configurations_collaborators foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint ck_collegiate_configurations_valid_to
    check (valid_to is null or valid_to > valid_from),
  constraint ex_collegiate_configurations_no_overlap
    exclude using gist (
      collaborator_id with =,
      tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
    )
);

comment on table public.collegiate_configurations is
  'Configuracao padrao do colegiado (versoes temporais por colaborador '
  'avaliado) - F3-08 (Issue #85). 0 membros = sem colegiado (explicito).';

comment on column public.collegiate_configurations.collaborator_id is
  'Colaborador AVALIADO ao qual a configuracao se aplica (ancora na pessoa). '
  'No maximo uma configuracao vigente por instante (exclusion).';

comment on column public.collegiate_configurations.valid_to is
  'Fim da vigencia (meio-aberto [valid_from, valid_to)); null = vigente. '
  'Mudanca normal fecha a versao e cria outra, preservando o historico.';

comment on constraint ex_collegiate_configurations_no_overlap
  on public.collegiate_configurations is
  'No maximo uma versao de configuracao vigente por avaliado por instante '
  '(periodos do mesmo avaliado nao se sobrepoem).';

create index ix_collegiate_configurations_organization_id
  on public.collegiate_configurations (organization_id);

create index ix_collegiate_configurations_collaborator_id
  on public.collegiate_configurations (collaborator_id);

create trigger trg_collegiate_configurations_updated_at
  before update on public.collegiate_configurations
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2) public.collegiate_configuration_members — membros 0..N da versão
-- ----------------------------------------------------------------------------
create table public.collegiate_configuration_members (
  id                  uuid        not null default gen_random_uuid(),
  organization_id     uuid        not null,
  configuration_id    uuid        not null,
  member_collaborator_id uuid     not null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  version             integer     not null default 0,
  constraint pk_collegiate_configuration_members primary key (id),
  constraint uq_collegiate_configuration_members_config_member
    unique (configuration_id, member_collaborator_id),
  constraint fk_collegiate_configuration_members_configurations
    foreign key (configuration_id, organization_id)
    references public.collegiate_configurations (id, organization_id)
    on delete restrict,
  constraint fk_collegiate_configuration_members_collaborators
    foreign key (member_collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict
);

comment on table public.collegiate_configuration_members is
  'Membros (0..N) do colegiado por versao da configuracao - F3-08. Sem '
  'derivacao automatica; sem self; sem duplicados.';

comment on constraint uq_collegiate_configuration_members_config_member
  on public.collegiate_configuration_members is
  'Sem membro duplicado na mesma versao da configuracao.';

create index ix_collegiate_configuration_members_organization_id
  on public.collegiate_configuration_members (organization_id);

create index ix_collegiate_configuration_members_member_collaborator_id
  on public.collegiate_configuration_members (member_collaborator_id);

create trigger trg_collegiate_configuration_members_updated_at
  before update on public.collegiate_configuration_members
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Trigger: avaliado não pode ser membro do próprio colegiado (D3)
-- ----------------------------------------------------------------------------
create or replace function public.enforce_collegiate_configuration_member_not_self()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.collegiate_configurations c
    where c.id = new.configuration_id
      and c.collaborator_id = new.member_collaborator_id
  ) then
    raise exception
      'collegiate_configuration_members: avaliado nao pode ser membro do proprio colegiado';
  end if;
  return new;
end;
$$;

comment on function public.enforce_collegiate_configuration_member_not_self() is
  'F3-08: impede self no colegiado (membro = avaliado) na gravacao.';

create trigger trg_collegiate_configuration_members_not_self
  before insert or update on public.collegiate_configuration_members
  for each row
  execute function public.enforce_collegiate_configuration_member_not_self();

-- ----------------------------------------------------------------------------
-- 3) public.collegiate_cycle_snapshots — cabeçalho do snapshot por ciclo
-- ----------------------------------------------------------------------------
create table public.collegiate_cycle_snapshots (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  ano             integer     not null,
  ciclo           integer     not null,
  collaborator_id uuid        not null,
  reference_date  timestamptz not null,
  created_at      timestamptz not null default now(),
  constraint pk_collegiate_cycle_snapshots primary key (id),
  constraint uq_collegiate_cycle_snapshots_id_organization unique (id, organization_id),
  constraint uq_collegiate_cycle_snapshots_org_ano_ciclo_avaliado
    unique (organization_id, ano, ciclo, collaborator_id),
  constraint fk_collegiate_cycle_snapshots_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint fk_collegiate_cycle_snapshots_collaborators foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint ck_collegiate_cycle_snapshots_ano check (ano > 0),
  constraint ck_collegiate_cycle_snapshots_ciclo check (ciclo in (1, 2, 3))
);

comment on table public.collegiate_cycle_snapshots is
  'Snapshot imutavel por ciclo e por avaliado - F3-08. Chave de negocio '
  '(organization_id, ano, ciclo, collaborator_id); sem tabela de ciclos '
  '(integracao futura).';

comment on column public.collegiate_cycle_snapshots.reference_date is
  'Data de referencia da ativacao (inicio do ciclo) usada para resolver '
  'configuracao vigente, occupations e reporting lines.';

comment on constraint uq_collegiate_cycle_snapshots_org_ano_ciclo_avaliado
  on public.collegiate_cycle_snapshots is
  'Um unico snapshot por (organizacao, ano, ciclo, avaliado); materializacao '
  'idempotente (nao substitui nem duplica).';

create index ix_collegiate_cycle_snapshots_organization_id
  on public.collegiate_cycle_snapshots (organization_id);

create index ix_collegiate_cycle_snapshots_collaborator_id
  on public.collegiate_cycle_snapshots (collaborator_id);

-- ----------------------------------------------------------------------------
-- 4) public.collegiate_cycle_snapshot_positions — posições ocupadas + superior
-- ----------------------------------------------------------------------------
create table public.collegiate_cycle_snapshot_positions (
  id                      uuid        not null default gen_random_uuid(),
  snapshot_id             uuid        not null,
  organization_id         uuid        not null,
  position_id             uuid        not null,
  superior_position_id    uuid,
  superior_collaborator_id uuid,
  created_at              timestamptz not null default now(),
  constraint pk_collegiate_cycle_snapshot_positions primary key (id),
  constraint uq_collegiate_cycle_snapshot_positions_snapshot_position
    unique (snapshot_id, position_id),
  constraint fk_collegiate_cycle_snapshot_positions_snapshots
    foreign key (snapshot_id, organization_id)
    references public.collegiate_cycle_snapshots (id, organization_id)
    on delete restrict,
  constraint fk_collegiate_cycle_snapshot_positions_positions
    foreign key (position_id, organization_id)
    references public.organizational_positions (id, organization_id)
    on delete restrict,
  constraint fk_collegiate_cycle_snapshot_positions_superior_position
    foreign key (superior_position_id, organization_id)
    references public.organizational_positions (id, organization_id)
    on delete restrict,
  constraint fk_collegiate_cycle_snapshot_positions_superior_collaborator
    foreign key (superior_collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint ck_collegiate_cycle_snapshot_positions_superior_pair
    check (superior_collaborator_id is null or superior_position_id is not null)
);

comment on table public.collegiate_cycle_snapshot_positions is
  'Posicoes ocupadas pelo avaliado na data de referencia do snapshot, com o '
  'superior formal direto resolvido por posicao (F3-07: responsavel = '
  'substituto operacional > titular > NULL). Imutavel.';

comment on column public.collegiate_cycle_snapshot_positions.superior_collaborator_id is
  'Superior formal direto RESOLVIDO na data (responsavel efetivo da posicao '
  'superior); null quando a posicao nao possui superior ou este esta vago sem '
  'substituto.';

comment on constraint ck_collegiate_cycle_snapshot_positions_superior_pair
  on public.collegiate_cycle_snapshot_positions is
  'Superior colaborador so pode existir se houver posicao superior registrada.';

create index ix_collegiate_cycle_snapshot_positions_organization_id
  on public.collegiate_cycle_snapshot_positions (organization_id);

create index ix_collegiate_cycle_snapshot_positions_position_id
  on public.collegiate_cycle_snapshot_positions (position_id);

-- ----------------------------------------------------------------------------
-- 5) public.collegiate_cycle_snapshot_members — colegiado congelado
-- ----------------------------------------------------------------------------
create table public.collegiate_cycle_snapshot_members (
  id                      uuid        not null default gen_random_uuid(),
  snapshot_id             uuid        not null,
  organization_id         uuid        not null,
  member_collaborator_id  uuid        not null,
  created_at              timestamptz not null default now(),
  constraint pk_collegiate_cycle_snapshot_members primary key (id),
  constraint uq_collegiate_cycle_snapshot_members_snapshot_member
    unique (snapshot_id, member_collaborator_id),
  constraint fk_collegiate_cycle_snapshot_members_snapshots
    foreign key (snapshot_id, organization_id)
    references public.collegiate_cycle_snapshots (id, organization_id)
    on delete restrict,
  constraint fk_collegiate_cycle_snapshot_members_collaborators
    foreign key (member_collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict
);

comment on table public.collegiate_cycle_snapshot_members is
  'Membros do colegiado CONGELADOS no snapshot do ciclo (0..N), materializados '
  'da configuracao vigente na data de referencia. Imutavel.';

comment on constraint uq_collegiate_cycle_snapshot_members_snapshot_member
  on public.collegiate_cycle_snapshot_members is
  'Sem membro duplicado no mesmo snapshot.';

create index ix_collegiate_cycle_snapshot_members_organization_id
  on public.collegiate_cycle_snapshot_members (organization_id);

create index ix_collegiate_cycle_snapshot_members_member_collaborator_id
  on public.collegiate_cycle_snapshot_members (member_collaborator_id);

-- ----------------------------------------------------------------------------
-- 6) RPC de materialização (ativação do ciclo) — transacional e idempotente
-- ----------------------------------------------------------------------------
create or replace function public.materializar_colegiado_ciclo(
  p_organization_id uuid,
  p_ano integer,
  p_ciclo integer,
  p_reference_date timestamptz,
  p_evaluated_collaborator_ids uuid[]
)
returns void
language plpgsql
set search_path = public
as $$
begin
  if p_ano <= 0 then
    raise exception 'materializar_colegiado_ciclo: ano invalido';
  end if;
  if p_ciclo not in (1, 2, 3) then
    raise exception 'materializar_colegiado_ciclo: ciclo invalido (1..3)';
  end if;

  -- Valida a lista de avaliados: todos existentes e da mesma organização.
  if exists (
    select 1
    from unnest(p_evaluated_collaborator_ids) as x(cid)
    left join public.collaborators c
      on c.id = x.cid and c.organization_id = p_organization_id
    where x.cid is null or c.id is null
  ) then
    raise exception
      'materializar_colegiado_ciclo: avaliado inexistente ou de outra organizacao';
  end if;

  -- Cabeçalho do snapshot (idempotente: repetição não duplica/substitui).
  insert into public.collegiate_cycle_snapshots (
    id, organization_id, ano, ciclo, collaborator_id, reference_date
  )
  select
    gen_random_uuid(),
    p_organization_id,
    p_ano,
    p_ciclo,
    x.cid,
    p_reference_date
  from (
    select distinct cid
    from unnest(p_evaluated_collaborator_ids) as u(cid)
    where u.cid is not null
  ) x
  on conflict (organization_id, ano, ciclo, collaborator_id) do nothing;

  -- Posições ocupadas na data + superior formal direto resolvido por posição.
  insert into public.collegiate_cycle_snapshot_positions (
    id, snapshot_id, organization_id, position_id,
    superior_position_id, superior_collaborator_id
  )
  select
    gen_random_uuid(),
    s.id,
    s.organization_id,
    occ.organizational_position_id,
    rl.manager_position_id,
    r.responsible_collaborator_id
  from public.collegiate_cycle_snapshots s
  join (
    select distinct cid
    from unnest(p_evaluated_collaborator_ids) as u(cid)
    where u.cid is not null
  ) x on x.cid = s.collaborator_id
  cross join lateral (
    select occ.organizational_position_id
    from public.occupations occ
    where occ.collaborator_id = s.collaborator_id
      and occ.organization_id = s.organization_id
      and occ.valid_from <= p_reference_date
      and (occ.valid_to is null or occ.valid_to > p_reference_date)
  ) occ
  left join lateral (
    select rl.manager_position_id
    from public.position_reporting_lines rl
    where rl.subordinate_position_id = occ.organizational_position_id
      and rl.organization_id = s.organization_id
      and rl.valid_from <= p_reference_date
      and (rl.valid_to is null or rl.valid_to > p_reference_date)
  ) rl on true
  left join lateral public.organizacao_resolver_responsavel_posicao(
    rl.manager_position_id, p_reference_date
  ) r on true
  where s.organization_id = p_organization_id
    and s.ano = p_ano
    and s.ciclo = p_ciclo
    and not exists (
      select 1
      from public.collegiate_cycle_snapshot_positions sp
      where sp.snapshot_id = s.id
    );

  -- Membros do colegiado congelados da configuração vigente na data.
  insert into public.collegiate_cycle_snapshot_members (
    id, snapshot_id, organization_id, member_collaborator_id
  )
  select
    gen_random_uuid(),
    s.id,
    s.organization_id,
    m.member_collaborator_id
  from public.collegiate_cycle_snapshots s
  join (
    select distinct cid
    from unnest(p_evaluated_collaborator_ids) as u(cid)
    where u.cid is not null
  ) x on x.cid = s.collaborator_id
  cross join lateral (
    select cm.member_collaborator_id
    from public.collegiate_configuration_members cm
    join public.collegiate_configurations c
      on c.id = cm.configuration_id
     and c.organization_id = cm.organization_id
    where c.collaborator_id = s.collaborator_id
      and c.organization_id = s.organization_id
      and c.valid_from <= p_reference_date
      and (c.valid_to is null or c.valid_to > p_reference_date)
  ) m
  where s.organization_id = p_organization_id
    and s.ano = p_ano
    and s.ciclo = p_ciclo
    and not exists (
      select 1
      from public.collegiate_cycle_snapshot_members sm
      where sm.snapshot_id = s.id
    );
end;
$$;

comment on function public.materializar_colegiado_ciclo(uuid, integer, integer, timestamptz, uuid[]) is
  'F3-08: materializa (na ativacao do ciclo) o snapshot imutavel de colegiado '
  'por avaliado, com posicoes ocupadas e superior formal direto resolvido na '
  'data de referencia. Transacional e idempotente; SECURITY INVOKER.';

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
alter table public.collegiate_configurations enable row level security;
alter table public.collegiate_configuration_members enable row level security;
alter table public.collegiate_cycle_snapshots enable row level security;
alter table public.collegiate_cycle_snapshot_positions enable row level security;
alter table public.collegiate_cycle_snapshot_members enable row level security;
