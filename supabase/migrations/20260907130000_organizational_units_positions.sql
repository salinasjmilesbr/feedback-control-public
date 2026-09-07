-- ============================================================================
-- F3-03 (Issue #80): estrutura organizacional formal — unidades e posições
-- ----------------------------------------------------------------------------
-- Propósito: modelar unidades e posições formais independentemente das
-- pessoas que futuramente as ocuparão, seguindo as convenções da F1-02
-- (supabase/migrations/README.md) e o estado das F2/F3-01/F3-02:
--
--   - public.organizational_units              — unidade formal da organização
--     (raiz da composição estrutural; identidade estável e existência
--     temporal própria);
--   - public.organizational_unit_parent_periods — relação temporal de
--     composição pai/filho entre unidades (histórico de reestruturações;
--     NÃO é reporting line entre posições);
--   - public.organizational_positions          — posição formal vinculada a
--     unidade + job_role + seniority opcional, com existência temporal
--     própria e sem ocupante nesta fase.
--
-- Decisões técnicas registradas (Issue #80 e revisão de escopo desta etapa):
--   - `organizational_units` carrega apenas `name` como atributo de
--     identificação/configuração (núcleo mínimo, padrão organizations/
--     catálogos F3-02), único por organização; nome não infere nível,
--     hierarquia ou tipo da unidade; nenhuma coluna de code/order/rank;
--   - existência temporal da unidade na própria entidade: `valid_from`
--     obrigatório e `valid_to` null enquanto vigente (`valid_to > valid_from`
--     quando encerrada); o encerramento preserva a linha e o UUID (histórico
--     não destrutivo); reativação após encerramento = nova unidade
--     (documentado nesta migration);
--   - parent das unidades em RELAÇÃO TEMPORAL SEPARADA
--     (`organizational_unit_parent_periods`): `unit_id` (filho),
--     `parent_unit_id` null = raiz, `valid_from`/`valid_to`, no máximo um
--     parent vigente por unidade em cada instante (exclusion constraint
--     meio-aberta), mudança de parent sem recriar a unidade e histórico
--     integral de reestruturações; a relação representa somente composição
--     formal de unidades — não reporting line, gestor, dotted line, projeto,
--     comitê ou autorização;
--   - `organizational_positions` sem name/code próprios: identificada pelo
--     UUID e caracterizada estruturalmente por unidade + função + senioridade
--     opcional + validade temporal; múltiplas posições com a mesma combinação
--     são ocorrências formais distintas válidas (sem unique natural);
--     `valid_from`/`valid_to` representam a EXISTÊNCIA formal da posição
--     (encerramento preserva UUID/histórico), não a permanência de ocupante —
--     troca/vacância de ocupante não recria posição e será modelada em issue
--     posterior (occupation); nenhuma regra de preservar/substituir a
--     identidade da posição em futura alteração estrutural é definida
--     silenciosamente nesta issue (colunas de contexto são atualizáveis e a
--     decisão de domínio caberá à issue correspondente);
--   - hierarquia independente de cargo: job_role/seniority não determinam a
--     posição na árvore, não existe rank nem sequência fixa de cargos; duas
--     posições com o mesmo job_role podem existir em partes/alturas
--     diferentes; Especialista sem subordinados e Gerente → Analista sem
--     Coordenador são representáveis (unidades sem níveis intermediários);
--   - integridade multi-organização DECLARATIVA via FKs compostas
--     `(ref_id, organization_id) → (id, organization_id)` (padrão da FK
--     composta do F3-01), com unique de referência aditiva nas tabelas-alvo
--     (inclusive `uq_job_roles_id_organization` e
--     `uq_seniority_levels_id_organization` adicionadas via ALTER nesta
--     migration, sem alterar semântica dos catálogos); referência opcional
--     (`seniority_level_id`, `parent_unit_id`) permite NULL sem quebrar a FK;
--   - prevenção de ciclos: constraints declarativas no banco (auto-parent
--     proibido; no máximo um parent vigente por unidade; sem sobreposição
--     temporal de parent do mesmo filho; consistência de organização child/
--     parent); ciclos multi-nível NÃO são detectados por trigger recursivo
--     nesta issue — validação de ciclos profundos é responsabilidade da
--     aplicação/serviço que mantém a árvore (limitação documentada, não é
--     permissão de ciclos);
--   - FKs `ON DELETE RESTRICT` em todas as novas relações e RLS habilitado
--     deny-by-default sem policies/grants (mesmo padrão das fases anteriores);
--     encerramentos/reestruturações por validade/histórico, nunca exclusão
--     física.
--
-- Fora do escopo desta etapa (não antecipar — Issue #80):
--   - ocupantes/occupation, collaborator_id em posição, reporting line entre
--     posições, gestor direto, colegiado, dotted line, substituição
--     temporária, snapshot de ciclo, capabilities/autorização (Fase 4),
--     dados/estrutura real da Vivo.
--
-- Dependências: public.organizations (F2-01), public.job_roles e
-- public.seniority_levels (F3-02), extensão btree_gist (F3-01, para a
-- exclusion constraint temporal do parent).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Unique de referência aditiva para FKs compostas (integridade multi-org)
-- ----------------------------------------------------------------------------
-- As FKs compostas desta migration referenciam `(id, organization_id)` das
-- tabelas de catálogo da F3-02. Unique de referência é ADITIVA e não altera a
-- semântica dos catálogos (id continua a PK; o par (id, organization_id) já é
-- funcionalmente único) — serve apenas como alvo declarativo das FKs
-- compostas, no mesmo padrão de `uq_collaborators_id_organization` (F3-01).
alter table public.job_roles
  add constraint uq_job_roles_id_organization unique (id, organization_id);

alter table public.seniority_levels
  add constraint uq_seniority_levels_id_organization unique (id, organization_id);

comment on constraint uq_job_roles_id_organization on public.job_roles is
  'Unique de referencia (F3-03, Issue #80) para as FKs compostas de '
  'organizational_positions: garante no banco que job_role e posicao '
  'pertencem a mesma organizacao. Aditiva; nao altera a semantica do catalogo.';

comment on constraint uq_seniority_levels_id_organization on public.seniority_levels is
  'Unique de referencia (F3-03, Issue #80) para a FK composta opcional de '
  'organizational_positions: garante no banco que seniority e posicao '
  'pertencem a mesma organizacao. Aditiva; nao altera a semantica do catalogo.';

-- ----------------------------------------------------------------------------
-- public.organizational_units
-- ----------------------------------------------------------------------------
-- Unidade formal da organização (ex.: diretoria, gerência, coordenação,
-- núcleo — NENHUM nível é codificado como obrigatório; a estrutura permite
-- expansão acima/abaixo/entre níveis conhecidos). Unidade existe
-- independentemente de ocupantes e de posições.
--
-- Existência temporal: `valid_from` obrigatório; `valid_to` null = unidade
-- vigente; encerramento = update em `valid_to` (preserva linha/UUID;
-- reativação após encerramento = nova unidade, decisão documentada). A
-- composição (parent) é tratada em relação temporal separada — mudanças de
-- parent não recriam nem encerram a unidade.
create table public.organizational_units (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  name            text        not null,
  valid_from      timestamptz not null,
  valid_to        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_organizational_units primary key (id),
  constraint uq_organizational_units_id_organization unique (id, organization_id),
  constraint uq_organizational_units_organization_name unique (organization_id, name),
  constraint fk_organizational_units_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint ck_organizational_units_name
    check (name <> '' and name = btrim(name)),
  constraint ck_organizational_units_valid_to
    check (valid_to is null or valid_to > valid_from)
);

comment on table public.organizational_units is
  'Unidade formal da estrutura organizacional - F3-03 (Issue #80). Existe sem '
  'ocupantes; composicao parent tratada em relacao temporal separada.';

comment on column public.organizational_units.id is
  'Identificador tecnico imutavel (UUID) da unidade; preservado em '
  'encerramentos e reestruturacoes (nunca reutilizado).';

comment on column public.organizational_units.organization_id is
  'Organizacao (public.organizations) dona da unidade. ON DELETE RESTRICT.';

comment on column public.organizational_units.name is
  'Nome da unidade formal (rotulo). Unico por organizacao; nao infere nivel, '
  'hierarquia ou tipo; nenhuma sequencia de cargos/niveis e codificada.';

comment on column public.organizational_units.valid_to is
  'Fim da existencia formal (bound exclusivo, meio-aberto [valid_from, '
  'valid_to)); null = unidade vigente. Encerramento preserva a linha e o UUID '
  '(reativacao apos encerramento = nova unidade, decisao documentada).';

comment on constraint uq_organizational_units_organization_name
  on public.organizational_units is
  'No maximo uma unidade com o mesmo nome por organizacao. O nome nao e '
  'identidade tecnica nem indicador de nivel/hierarquia.';

comment on constraint uq_organizational_units_id_organization
  on public.organizational_units is
  'Unique de referencia para as FKs compostas (posicoes e relacao temporal de '
  'parent): garante tenant integrity de forma declarativa.';

comment on constraint ck_organizational_units_valid_to
  on public.organizational_units is
  'Existencia temporal valida: valid_to, quando presente, posterior a '
  'valid_from (periodo meio-aberto nao degenerado).';

create trigger trg_organizational_units_updated_at
  before update on public.organizational_units
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.organizational_unit_parent_periods
-- ----------------------------------------------------------------------------
-- Relação temporal de composição pai/filho entre unidades (árvore formal de
-- unidades). `parent_unit_id` null em um período = unidade raiz (sem pai)
-- naquele período; períodos meio-abertos `[valid_from, valid_to)`; exclusion
-- constraint por `unit_id` garante NO MÁXIMO UM parent vigente por unidade em
-- cada instante (e impede sobreposições incompatíveis). Reestruturação =
-- fechar o período atual e abrir outro, preservando o histórico e SEM recriar
-- a unidade.
--
-- Consistência declarativa: as FKs compostas (unit_id, organization_id) e
-- (parent_unit_id, organization_id) → organizational_units(id,
-- organization_id) garantem que filho, pai e a própria linha pertencem à
-- mesma organização. Auto-parent é proibido por check. Ciclos multi-nível são
-- responsabilidade da aplicação (limitação documentada nesta migration).
create table public.organizational_unit_parent_periods (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  unit_id         uuid        not null,
  parent_unit_id  uuid,
  valid_from      timestamptz not null,
  valid_to        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_organizational_unit_parent_periods primary key (id),
  constraint fk_organizational_unit_parent_periods_child_unit
    foreign key (unit_id, organization_id)
    references public.organizational_units (id, organization_id)
    on delete restrict,
  constraint fk_organizational_unit_parent_periods_parent_unit
    foreign key (parent_unit_id, organization_id)
    references public.organizational_units (id, organization_id)
    on delete restrict,
  constraint ck_organizational_unit_parent_periods_valid_to
    check (valid_to is null or valid_to > valid_from),
  constraint ck_organizational_unit_parent_periods_not_self
    check (parent_unit_id is null or parent_unit_id <> unit_id),
  constraint ex_organizational_unit_parent_periods_no_overlap
    exclude using gist (
      unit_id with =,
      tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
    )
);

comment on table public.organizational_unit_parent_periods is
  'Composicao temporal pai/filho entre unidades formais - F3-03 (Issue #80). '
  'Somente estrutura formal; NAO e reporting line entre posicoes.';

comment on column public.organizational_unit_parent_periods.unit_id is
  'Unidade filha (public.organizational_units). Exclusion constraint garante '
  'no maximo um parent vigente por instante.';

comment on column public.organizational_unit_parent_periods.parent_unit_id is
  'Unidade pai; null = unidade raiz no periodo. Auto-parent proibido; ciclos '
  'multi-nivel validados pela aplicacao (documentado).';

comment on column public.organizational_unit_parent_periods.valid_to is
  'Fim do periodo de composicao (meio-aberto); null = vigente. Fechar e abrir '
  'periodos preserva o historico de reestruturacoes sem recriar unidades.';

comment on constraint fk_organizational_unit_parent_periods_child_unit
  on public.organizational_unit_parent_periods is
  'FK composta (unit_id, organization_id): filho e relacao pertencem a mesma '
  'organizacao (tenant integrity declarativa); ON DELETE RESTRICT.';

comment on constraint fk_organizational_unit_parent_periods_parent_unit
  on public.organizational_unit_parent_periods is
  'FK composta (parent_unit_id, organization_id): pai e relacao pertencem a '
  'mesma organizacao; parent null (raiz) nao e validado; ON DELETE RESTRICT.';

comment on constraint ck_organizational_unit_parent_periods_not_self
  on public.organizational_unit_parent_periods is
  'Auto-parent proibido (uma unidade nao pode ser pai de si mesma).';

comment on constraint ex_organizational_unit_parent_periods_no_overlap
  on public.organizational_unit_parent_periods is
  'No maximo um parent vigente por unidade em cada instante (periodos do mesmo '
  'filho nao podem se sobrepor; so ha um periodo aberto por unidade).';

create index ix_organizational_unit_parent_periods_unit_id
  on public.organizational_unit_parent_periods (unit_id);

create index ix_organizational_unit_parent_periods_organization_id
  on public.organizational_unit_parent_periods (organization_id);

create trigger trg_organizational_unit_parent_periods_updated_at
  before update on public.organizational_unit_parent_periods
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.organizational_positions
-- ----------------------------------------------------------------------------
-- Posição formal da organização, vinculada a uma unidade, a um job_role e,
-- opcionalmente, a uma seniority_level. A posição existe sem ocupante (posição
-- vaga é o estado natural desta fase; ocupação é issue posterior e NUNCA via
-- collaborator_id aqui). Múltiplas posições com a mesma combinação
-- unidade+função+senioridade são ocorrências formais distintas (sem unique
-- natural). `valid_from`/`valid_to` expressam a existência formal da posição,
-- não a permanência de ocupante.
--
-- Consistência multi-organização: FKs compostas para organizational_units,
-- job_roles e seniority_levels (esta última permite NULL = posição sem
-- senioridade). Colunas de contexto são FKs normais: a regra de domínio sobre
-- preservar ou substituir a identidade da posição em futuras alterações
-- estruturais NÃO é definida silenciosamente nesta issue.
create table public.organizational_positions (
  id                 uuid        not null default gen_random_uuid(),
  organization_id    uuid        not null,
  unit_id            uuid        not null,
  job_role_id        uuid        not null,
  seniority_level_id uuid,
  valid_from         timestamptz not null,
  valid_to           timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  version            integer     not null default 0,
  constraint pk_organizational_positions primary key (id),
  constraint fk_organizational_positions_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint fk_organizational_positions_units foreign key (unit_id, organization_id)
    references public.organizational_units (id, organization_id)
    on delete restrict,
  constraint fk_organizational_positions_job_roles foreign key (job_role_id, organization_id)
    references public.job_roles (id, organization_id)
    on delete restrict,
  constraint fk_organizational_positions_seniority_levels foreign key (seniority_level_id, organization_id)
    references public.seniority_levels (id, organization_id)
    on delete restrict,
  constraint ck_organizational_positions_valid_to
    check (valid_to is null or valid_to > valid_from)
);

comment on table public.organizational_positions is
  'Posicao formal da estrutura organizacional - F3-03 (Issue #80). Existe sem '
  'ocupante; occupation e reporting line sao issues posteriores.';

comment on column public.organizational_positions.id is
  'Identificador tecnico imutavel (UUID) da posicao. Posicoes distintas com a '
  'mesma combinacao unidade+funcao+senioridade sao entidades independentes.';

comment on column public.organizational_positions.unit_id is
  'Unidade formal (public.organizational_units) da posicao. FK composta '
  'garante a mesma organizacao.';

comment on column public.organizational_positions.job_role_id is
  'Funcao (public.job_roles) da posicao. FK composta garante a mesma '
  'organizacao; funcao NAO determina posicao na arvore nem hierarquia.';

comment on column public.organizational_positions.seniority_level_id is
  'Senioridade opcional (public.seniority_levels); null = posicao sem '
  'senioridade. FK composta garante a mesma organizacao quando preenchida; '
  'senioridade NAO determina hierarquia.';

comment on column public.organizational_positions.valid_to is
  'Fim da existencia formal da posicao (meio-aberto [valid_from, valid_to)); '
  'null = vigente. Encerramento preserva a linha/UUID; NAO representa '
  'permanencia de ocupante.';

comment on constraint fk_organizational_positions_units
  on public.organizational_positions is
  'FK composta (unit_id, organization_id): posicao e unidade pertencem a mesma '
  'organizacao; ON DELETE RESTRICT.';

comment on constraint fk_organizational_positions_job_roles
  on public.organizational_positions is
  'FK composta (job_role_id, organization_id): posicao e funcao pertencem a '
  'mesma organizacao; ON DELETE RESTRICT.';

comment on constraint fk_organizational_positions_seniority_levels
  on public.organizational_positions is
  'FK composta (seniority_level_id, organization_id), opcional (NULL nao '
  'validado): posicao e senioridade, quando houver, pertencem a mesma '
  'organizacao; ON DELETE RESTRICT.';

comment on constraint ck_organizational_positions_valid_to
  on public.organizational_positions is
  'Existencia temporal valida: valid_to, quando presente, posterior a '
  'valid_from (periodo meio-aberto nao degenerado).';

create index ix_organizational_positions_organization_id
  on public.organizational_positions (organization_id);

create index ix_organizational_positions_unit_id
  on public.organizational_positions (unit_id);

create index ix_organizational_positions_job_role_id
  on public.organizational_positions (job_role_id);

create index ix_organizational_positions_seniority_level_id
  on public.organizational_positions (seniority_level_id);

create trigger trg_organizational_positions_updated_at
  before update on public.organizational_positions
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
-- RLS é habilitada nas três tabelas novas. NENHUMA policy é criada nesta
-- migration, no mesmo padrão das F2-01/F2-02/F3-01/F3-02:
--   - deny-by-default integral: sem policy, nenhuma role submetida a RLS
--     (inclusive `authenticated`) consegue ler ou escrever na estrutura;
--   - esta issue não define modelo de acesso à estrutura organizacional
--     (escopos/permissões são da Fase 4);
--   - policies restritivas entrarão, quando o modelo de acesso existir, como
--     novas migrations aditivas — nunca nesta.
-- Nenhum grant é concedido a anon/authenticated/service_role; as policies e
-- grants das F2-03/F2-07 e o estado das tabelas F3-01/F3-02 permanecem
-- inalterados.
alter table public.organizational_units enable row level security;
alter table public.organizational_unit_parent_periods enable row level security;
alter table public.organizational_positions enable row level security;
