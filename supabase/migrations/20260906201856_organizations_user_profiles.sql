-- ============================================================================
-- F2-01 (Issue #68): organizations e perfis internos de usuário
-- ----------------------------------------------------------------------------
-- Propósito: primeira migration funcional da Fase 2. Cria somente as
-- entidades-base de identidade organizacional do Virtus sobre a fundação da
-- F1-03, seguindo as convenções da F1-02 (supabase/migrations/README.md):
--
--   - public.organizations — organização (raiz do requisito multi-organização);
--   - public.user_profiles — perfil interno do usuário, ligado 1:1 ao Supabase
--     Auth (auth.users), sem duplicar senha, credenciais ou segredos.
--
-- Fora do escopo desta etapa (não antecipar — Issue #68):
--   - memberships, colaboradores, cargos/job roles, senioridade, unidades/
--     posições organizacionais, roles/capabilities, convites, impersonação;
--   - qualquer coluna de senha/secret/token/credential/refresh;
--   - policies RLS permissivas, fluxos de desativação ou autorização futura;
--   - alterações no runtime da aplicação (localStorage segue como persistência
--     funcional; nenhum fluxo do frontend é migrado nesta Issue).
--
-- Comportamento:
--   - aplica em banco vazio (fluxo local de rebuild/`supabase db reset`);
--   - depende de `auth.users` existir: o serviço Auth local é habilitado na
--     F2-01 (supabase/config.toml);
--   - migration versionada e aditiva; correções futuras entram como novas
--     migrations, nunca editando esta.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.organizations
-- ----------------------------------------------------------------------------
-- Raiz da multi-organização (requisito arquitetural da F2). Nesta etapa contém
-- apenas metadados mínimos; identificação legal, marca e demais atributos de
-- domínio entram com as fases de estrutura organizacional. Escopo por tabela
-- (convenção F1-02):
--   - sem organization_id: é a própria raiz do escopo por organização;
--   - sem unicidade de negócio em `name`: regra de unicidade/identidade legal é
--     decisão de domínio de fases posteriores (convenção F1-02);
--   - `version` presente porque a entidade admite edição concorrente (renomear
--     organização); `updated_at` mantido pelo trigger técnico da F1-03.
create table public.organizations (
  id         uuid        not null default gen_random_uuid(),
  name       text        not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version    integer     not null default 0,
  constraint pk_organizations primary key (id),
  constraint ck_organizations_name check (btrim(name) <> '')
);

comment on table public.organizations is
  'Organizacao (raiz multi-organizacao) - F2-01 (Issue #68).';

comment on column public.organizations.id is
  'Identificador tecnico imutavel (UUID), nunca chave de negocio '
  '(convencao F1-02); gerado por gen_random_uuid().';

comment on column public.organizations.name is
  'Nome de exibicao da organizacao. Sem unicidade nesta etapa: identidade '
  'legal e regras de unicidade sao decisoes de dominio de fases posteriores.';

comment on column public.organizations.version is
  'Controle de concorrencia otimista (F1-02); incrementado pela aplicacao a '
  'cada atualizacao. Nao e dado de negocio.';

create trigger trg_organizations_updated_at
  before update on public.organizations
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.user_profiles
-- ----------------------------------------------------------------------------
-- Perfil interno do usuário Virtus, vinculado 1:1 ao usuário de autenticação
-- (auth.users). Preserva a separação entre identidade de autenticação e
-- colaborador organizacional (conceitos distintos; o colaborador é entidade de
-- domínio futura e não o usuário de acesso). Nenhuma credencial de
-- autenticação é duplicada aqui: senha, hash, refresh token, MFA e afins
-- permanecem exclusivamente no Supabase Auth.
--
-- Nome canônico: user_profiles (perfil interno de usuário). As etapas F2-02 em
-- diante (ex.: memberships usuário-organização) referenciam esta tabela.
-- Escopo por tabela (convenção F1-02):
--   - sem organization_id: o perfil é identidade global; a participação em
--     organizações será modelada por memberships (F2-02), pois o usuário pode
--     pertencer a múltiplas organizações;
--   - FK em `id` (a própria PK) cobre o requisito de índice por FK: a PK já
--     indexa a coluna, dispensando índice adicional;
--   - `version` presente porque a entidade admite edição concorrente (futura
--     transição de status); `updated_at` mantido pelo trigger técnico da F1-03.
create table public.user_profiles (
  id         uuid        not null,
  status     text        not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version    integer     not null default 0,
  constraint pk_user_profiles primary key (id),
  constraint fk_user_profiles_auth_users foreign key (id)
    references auth.users (id)
    on delete restrict,
  constraint ck_user_profiles_status check (status in ('active', 'disabled'))
);

comment on table public.user_profiles is
  'Perfil interno do usuario Virtus, ligado 1:1 a auth.users - F2-01 (Issue #68).';

comment on column public.user_profiles.id is
  'Mesmo uuid do registro em auth.users (identidade de autenticacao). PK 1:1: '
  'o perfil interno so existe para uma identidade autenticada valida.';

comment on column public.user_profiles.status is
  'Status interno preparado para evolucao (F2-07 - desativacao/reativacao). '
  'Default active; nenhum fluxo de desativacao e implementado nesta etapa. '
  'Conjunto ampliavel apenas via nova migration (convencao F1-02).';

comment on column public.user_profiles.version is
  'Controle de concorrencia otimista (F1-02); incrementado pela aplicacao a '
  'cada atualizacao. Nao e dado de negocio.';

comment on constraint fk_user_profiles_auth_users on public.user_profiles is
  'Delete behavior RESTRICT (padrao F1-02): a remocao de um usuario em '
  'auth.users exige tratamento explicito do perfil pela aplicacao em fase '
  'futura. CASCADE foi rejeitado: o perfil e ancora de identidade que pode ser '
  'referenciada por memberships e historicos, e exclusao silenciosa em cascata '
  'nao foi decidida pela Issue #68.';

create trigger trg_user_profiles_updated_at
  before update on public.user_profiles
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
-- RLS é habilitada nas duas tabelas. NENHUMA policy é criada nesta migration:
--   - deny-by-default integral: sem policy, nenhuma role submetida a RLS
--     (inclusive `authenticated`) consegue ler ou escrever nessas tabelas;
--   - não existe ainda fluxo autenticado, membership, papel ou escopo que
--     justifique uma policy; qualquer policy agora seria permissiva ou
--     anteciparia autorização futura (proibido pela Issue #68 e F1-02);
--   - o acesso efetivo, quando autorizado em fases posteriores, entra por
--     policies restritivas em novas migrations aditivas, nunca nesta.
-- Nenhum grant é concedido a anon/authenticated/service_role: mesmo via API,
-- as tabelas permanecem inacessíveis, reforçando o deny-by-default.
alter table public.organizations enable row level security;
alter table public.user_profiles enable row level security;
