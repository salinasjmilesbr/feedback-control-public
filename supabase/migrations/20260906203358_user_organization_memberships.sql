-- ============================================================================
-- F2-02 (Issue #69): user_organization_memberships
-- ----------------------------------------------------------------------------
-- Propósito: criar a relação entre o perfil interno do usuário
-- (public.user_profiles) e a organização (public.organizations), permitindo que
-- um usuário participe de múltiplas organizações sem exigir vínculo com
-- colaborador. Migration puramente aditiva sobre as entidades da F2-01 (Issue
-- #68), seguindo as convenções da F1-02 (supabase/migrations/README.md).
--
-- Fora do escopo desta etapa (não antecipar — Issue #69):
--   - tabela de colaboradores, roles/capabilities, estrutura organizacional,
--     login/logout, convites (F2-06), UI ou alterações de runtime;
--   - policies RLS permissivas e autorização antecipada.
--
-- Sobre `collaborator_id` (opcional, futuro): a Issue #69 pede para preparar
-- conceitualmente o vínculo opcional com colaborador. A tabela `collaborators`
-- ainda NÃO existe nesta etapa; portanto nenhuma coluna `collaborator_id` é
-- criada aqui — uma coluna uuid solta sem FK seria dependência artificial, e
-- uma FK quebrada é proibida. Quando a entidade Collaborator existir, uma
-- migration posterior aditiva introduzirá `collaborator_id uuid null` com FK
-- própria, `ON DELETE` definido naquela etapa.
--
-- Comportamento:
--   - aplica em banco vazio (fluxo local de rebuild/`supabase db reset`);
--   - depende das tabelas `organizations` e `user_profiles` (F2-01);
--   - migration versionada e aditiva; correções futuras entram como novas
--     migrations, nunca editando esta.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.user_organization_memberships
-- ----------------------------------------------------------------------------
-- Nome canônico: user_organization_memberships (termo da própria Issue #69).
-- Representa o vínculo de acesso de um usuário (perfil interno) a uma
-- organização. Um usuário pode ter várias linhas (uma por organização), o que
-- materializa a multi-organização; o colaborador, quando existir, é vínculo
-- organizacional distinto e NÃO é obrigatório para a membership.
--
-- Unicidade (decisão técnica): uma única linha por par (user_profile_id,
-- organization_id), em qualquer status, via constraint unique `uq_...`. Isso
-- garante a "unicidade coerente de membership ativo por usuário/organização":
-- no máximo uma membership ativa por par, pois uma linha desabilitada é
-- reativada no lugar (update de status preservando `created_at` e histórico) —
-- alinhado à preservação de histórico e à reativação administrativa previstas
-- na F2-07. Um índice unique parcial (somente `status = 'active'`) foi
-- rejeitado: além de violar a convenção F1-02 (unicidade exige constraint
-- unique própria, nunca índice avulso), permitiria múltiplas linhas históricas
-- por par e duplicaria a âncora da membership.
--
-- Escopo por tabela (convenção F1-02):
--   - `user_profile_id` cobre o índice por FK através da própria constraint
--     unique (coluna líder do índice que a implementa);
--   - `organization_id` recebe índice comum próprio (`ix_...`), justificado
--     pela FK e por consultas futuras por organização;
--   - `status` segue o padrão `text` + `check` da F1-02, com o mesmo domínio de
--     `user_profiles.status` (`active`/`disabled`); o conjunto é ampliável
--     apenas por nova migration (ex.: estados de convite na F2-06);
--   - `version` presente porque a linha admite edição concorrente (transições
--     de status); `updated_at` mantido pelo trigger técnico da F1-03.
create table public.user_organization_memberships (
  id              uuid        not null default gen_random_uuid(),
  user_profile_id uuid        not null,
  organization_id uuid        not null,
  status          text        not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_user_organization_memberships primary key (id),
  constraint uq_user_organization_memberships_user_profile_organization
    unique (user_profile_id, organization_id),
  constraint fk_user_organization_memberships_user_profiles foreign key (user_profile_id)
    references public.user_profiles (id)
    on delete restrict,
  constraint fk_user_organization_memberships_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint ck_user_organization_memberships_status
    check (status in ('active', 'disabled'))
);

comment on table public.user_organization_memberships is
  'Membership usuario-organizacao (F2-02, Issue #69): vinculo de acesso de um '
  'perfil interno a uma organizacao, sem exigir colaborador.';

comment on column public.user_organization_memberships.id is
  'Identificador tecnico imutavel (UUID), nunca chave de negocio '
  '(convencao F1-02); gerado por gen_random_uuid().';

comment on column public.user_organization_memberships.user_profile_id is
  'Perfil interno do usuario (public.user_profiles). Uma linha por par '
  'usuario/organizacao em qualquer status (unique); reativacao ocorre no lugar.';

comment on column public.user_organization_memberships.organization_id is
  'Organizacao (public.organizations) da qual o usuario participa.';

comment on column public.user_organization_memberships.status is
  'Status interno da membership, mesmo dominio de user_profiles.status '
  '(active/disabled), preparado para a evolucao da F2-07. Default active; '
  'nenhum fluxo de desativacao e implementado nesta etapa.';

comment on column public.user_organization_memberships.version is
  'Controle de concorrencia otimista (F1-02); incrementado pela aplicacao a '
  'cada atualizacao. Nao e dado de negocio.';

comment on constraint uq_user_organization_memberships_user_profile_organization
  on public.user_organization_memberships is
  'No maximo uma membership por par usuario/organizacao (qualquer status): '
  'unicidade coerente do membership ativo; desativacao/reativacao no lugar '
  'preserva created_at e historico (F2-07).';

comment on constraint fk_user_organization_memberships_user_profiles
  on public.user_organization_memberships is
  'ON DELETE RESTRICT (padrao F1-02): remover um perfil interno exige tratar '
  'as memberships explicitamente em fase futura; sem cascata silenciosa.';

comment on constraint fk_user_organization_memberships_organizations
  on public.user_organization_memberships is
  'ON DELETE RESTRICT (padrao F1-02): remover uma organizacao exige tratar as '
  'memberships explicitamente em fase futura; sem cascata silenciosa.';

create index ix_user_organization_memberships_organization_id
  on public.user_organization_memberships (organization_id);

create trigger trg_user_organization_memberships_updated_at
  before update on public.user_organization_memberships
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
-- RLS é habilitada na tabela. NENHUMA policy é criada nesta migration, no mesmo
-- padrão da F2-01:
--   - deny-by-default integral: sem policy, nenhuma role submetida a RLS
--     (inclusive `authenticated`) consegue ler ou escrever nesta tabela;
--   - ainda não existem fluxo autenticado, papel ou escopo de autorização que
--     justifiquem uma policy; qualquer policy agora seria permissiva ou
--     anteciparia autorização futura (proibido pela Issue #69 e pela F1-02);
--   - policies restritivas entrarão, quando houver modelo de acesso, como novas
--     migrations aditivas — nunca nesta.
-- Nenhum grant é concedido a anon/authenticated/service_role.
alter table public.user_organization_memberships enable row level security;
