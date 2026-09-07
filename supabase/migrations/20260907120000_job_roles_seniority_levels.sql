-- ============================================================================
-- F3-02 (Issue #79): catálogos configuráveis de funções (job_roles) e
-- senioridades (seniority_levels)
-- ----------------------------------------------------------------------------
-- Propósito: separar função/cargo, senioridade e hierarquia para que o Virtus
-- não dependa de uma cadeia fixa de cargos. Cria dois catálogos
-- organizacionais configuráveis, independentes entre si e independentes da
-- posição organizacional, da hierarquia e da autorização, seguindo as
-- convenções da F1-02 (supabase/migrations/README.md) e as entidades das
-- F2-01/F3-01:
--
--   - public.job_roles          — catálogo de funções (ex.: Analista,
--     Especialista, Estagiário) pertencente a uma organização;
--   - public.seniority_levels   — catálogo de senioridades (ex.: Júnior,
--     Pleno, Sênior) pertencente a uma organização.
--
-- Decisões técnicas registradas (Issue #79 e revisão de escopo desta etapa):
--   - `name text not null` como atributo mínimo de identificação/
--     configuração, com check de trim (sem espaços nas bordas) e unicidade
--     exata por organização (`unique (organization_id, name)` em cada
--     catálogo); NÃO há coluna code/description e o nome NÃO é identidade
--     técnica (o UUID `id` o é) nem indicador de hierarquia;
--   - normalização de caixa é responsabilidade da aplicação (sem índice
--     funcional case-insensitive nesta fase — convenção F1-02);
--   - `status text + check ('active','disabled') default 'active'`, mesmo
--     padrão de user_profiles/user_organization_memberships (F2): a
--     desativação/evolução ocorre no lugar e preserva o registro e referências
--     históricas, sem exclusão física; status do catálogo NÃO representa
--     hierarquia, autorização nem status de colaborador;
--   - NENHUMA coluna de ordenação/rank (order/display_order) é criada: os
--     catálogos não carregam posição hierárquica; a aplicação pode ordenar
--     visualmente por `name`; ordenação puramente visual, se um dia necessária,
--     entra como requisito separado sem efeito sobre reporting line,
--     autorização ou hierarquia;
--   - job_role e seniority são conceitos INDEPENDENTES: nenhuma tabela de
--     junção/restrição de combinações e nenhuma FK cruzada entre os catálogos;
--     a validade/aplicabilidade de uma combinação (ex.: Analista + Pleno) será
--     definida quando estes conceitos forem usados pelas estruturas
--     organizacionais de issues posteriores (posições — F3-03); senioridade não
--     é obrigatória e não é embutida em job_role;
--   - não há hierarquia implícita por nome/código/ordem do catálogo e nenhuma
--     sequência Vivo (C-Level → VP → Diretor → Gerente Sênior etc.) é
--     codificada; Especialista não implica equipe e Estagiário é função válida
--     mesmo sem ocorrência nos dados do piloto;
--   - job_role/seniority NÃO concedem capability/autorização (independência de
--     autorização; capabilities/scopes são da Fase 4); nada de Auth/membership
--     é alterado;
--   - multi-organização: `organization_id` direto com FK `ON DELETE RESTRICT`
--     para `organizations`; organizações diferentes configuram catálogos
--     próprios (subconjuntos e combinações diferentes); unicidade coerente
--     dentro de cada organização e reuso do mesmo nome entre organizações
--     diferentes permitido;
--   - RLS habilitado e deny-by-default nas duas tabelas, sem policies e sem
--     grants nesta etapa (mesmo padrão F2-01/F2-02/F3-01); nenhuma policy
--     existente é alterada.
--
-- Fora do escopo desta etapa (não antecipar — Issue #79):
--   - organizational positions, reporting lines e árvore organizacional
--     (F3-03); ocupação de posições por colaboradores;
--   - capabilities/permissões (Fase 4), critérios de avaliação por função,
--     colegiado, snapshot de ciclo e frontend funcional dos catálogos;
--   - dados reais da Vivo e estrutura organizacional real.
--
-- Dependências: tabela public.organizations (F2-01, Issue #68).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.job_roles
-- ----------------------------------------------------------------------------
-- Catálogo de funções da organização (ex.: Diretor, Gerente Sênior, Gerente,
-- Especialista, Coordenador, Consultor, Analista, Estagiário — valores de
-- exemplo do piloto; o catálogo é configurável por organização e NÃO é
-- hardcoded na estrutura). A função descreve um tipo de papel organizacional;
-- não define nível hierárquico, não define subordinação e não concede
-- autorização.
--
-- Unicidade (decisão técnica): `unique (organization_id, name)` por catálogo —
-- o nome é consistência de configuração dentro da organização, nunca
-- identidade técnica; a PK `id` (UUID) é a identidade e a coluna líder da
-- unique (organization_id) cobre também o índice exigido pela FK.
create table public.job_roles (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  name            text        not null,
  status          text        not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_job_roles primary key (id),
  constraint uq_job_roles_organization_name unique (organization_id, name),
  constraint fk_job_roles_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint ck_job_roles_name check (name <> '' and name = btrim(name)),
  constraint ck_job_roles_status check (status in ('active', 'disabled'))
);

comment on table public.job_roles is
  'Catalogo configurável de funcoes (job roles) por organizacao - F3-02 '
  '(Issue #79). Funcao != hierarquia != autorizacao.';

comment on column public.job_roles.id is
  'Identificador tecnico imutavel (UUID), nunca chave de negocio '
  '(convencao F1-02); gerado por gen_random_uuid().';

comment on column public.job_roles.organization_id is
  'Organizacao (public.organizations) dona do catalogo. ON DELETE RESTRICT: '
  'excluir uma organizacao exige tratar os catalogos explicitamente.';

comment on column public.job_roles.name is
  'Nome/rótulo da funcao na organizacao (ex.: Analista, Especialista). '
  'Unico por organizacao; normalizado (sem espacos nas bordas); nao e '
  'identidade tecnica nem indicador de hierarquia.';

comment on column public.job_roles.status is
  'Estado do item do catalogo: active ou disabled (padrao F2). Desativacao '
  'preserva o registro e referencias historicas, sem exclusao fisica; nao '
  'representa hierarquia, autorizacao nem status de colaborador.';

comment on column public.job_roles.version is
  'Controle de concorrencia otimista (F1-02); incrementado pela aplicacao a '
  'cada atualizacao (renomear/desativar). Nao e dado de negocio.';

comment on constraint uq_job_roles_organization_name on public.job_roles is
  'Consistencia do catalogo: no maximo uma funcao com o mesmo nome por '
  'organizacao; o mesmo nome pode existir em organizacoes diferentes. O nome '
  'nao e identidade tecnica nem implica hierarquia.';

comment on constraint fk_job_roles_organizations on public.job_roles is
  'ON DELETE RESTRICT (padrao F1-02): sem cascata silenciosa — excluir uma '
  'organizacao exige tratar os catalogos explicitamente em fase futura.';

comment on constraint ck_job_roles_name on public.job_roles is
  'Nome nao vazio e sem espacos nas bordas (normalizacao por check).';

create trigger trg_job_roles_updated_at
  before update on public.job_roles
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.seniority_levels
-- ----------------------------------------------------------------------------
-- Catálogo de senioridades da organização (ex.: Junior, Pleno, Senior).
-- Senioridade é conceito SEPARADO de job_role: não há FK entre os catálogos,
-- não há exigência de senioridade para toda função e nenhuma combinação é
-- restrita nesta camada. Estruturalmente, "Analista Junior/Pleno/Senior" é
-- representável como uma linha em job_roles (Analista) e linhas em
-- seniority_levels (Junior/Pleno/Senior) — jamais como degraus hierárquicos
-- implícitos ou nomes compostos obrigatórios.
create table public.seniority_levels (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  name            text        not null,
  status          text        not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_seniority_levels primary key (id),
  constraint uq_seniority_levels_organization_name unique (organization_id, name),
  constraint fk_seniority_levels_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint ck_seniority_levels_name check (name <> '' and name = btrim(name)),
  constraint ck_seniority_levels_status check (status in ('active', 'disabled'))
);

comment on table public.seniority_levels is
  'Catalogo configuravel de senioridades por organizacao - F3-02 (Issue #79). '
  'Senioridade e independente de job_role e de hierarquia.';

comment on column public.seniority_levels.id is
  'Identificador tecnico imutavel (UUID), nunca chave de negocio '
  '(convencao F1-02); gerado por gen_random_uuid().';

comment on column public.seniority_levels.organization_id is
  'Organizacao (public.organizations) dona do catalogo. ON DELETE RESTRICT: '
  'excluir uma organizacao exige tratar os catalogos explicitamente.';

comment on column public.seniority_levels.name is
  'Nome/rótulo da senioridade na organizacao (ex.: Junior, Pleno, Senior). '
  'Unico por organizacao; normalizado (sem espacos nas bordas); nao e '
  'identidade tecnica, nao indica degrau hierarquico obrigatorio e nao '
  'concede autorizacao.';

comment on column public.seniority_levels.status is
  'Estado do item do catalogo: active ou disabled (padrao F2). Desativacao '
  'preserva o registro e referencias historicas, sem exclusao fisica; nao '
  'representa hierarquia, autorizacao nem status de colaborador.';

comment on column public.seniority_levels.version is
  'Controle de concorrencia otimista (F1-02); incrementado pela aplicacao a '
  'cada atualizacao. Nao e dado de negocio.';

comment on constraint uq_seniority_levels_organization_name
  on public.seniority_levels is
  'Consistencia do catalogo: no maximo uma senioridade com o mesmo nome por '
  'organizacao; o mesmo nome pode existir em organizacoes diferentes.';

comment on constraint fk_seniority_levels_organizations on public.seniority_levels is
  'ON DELETE RESTRICT (padrao F1-02): sem cascata silenciosa — excluir uma '
  'organizacao exige tratar os catalogos explicitamente em fase futura.';

comment on constraint ck_seniority_levels_name on public.seniority_levels is
  'Nome nao vazio e sem espacos nas bordas (normalizacao por check).';

create trigger trg_seniority_levels_updated_at
  before update on public.seniority_levels
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
-- RLS é habilitada nas duas tabelas novas. NENHUMA policy é criada nesta
-- migration, no mesmo padrão das F2-01/F2-02/F3-01:
--   - deny-by-default integral: sem policy, nenhuma role submetida a RLS
--     (inclusive `authenticated`) consegue ler ou escrever nos catálogos;
--   - esta issue não define modelo de acesso a catálogos (escopos/permissões
--     são da Fase 4): qualquer policy agora seria permissiva ou anteciparia
--     autorização futura;
--   - policies restritivas entrarão, quando o modelo de acesso existir, como
--     novas migrations aditivas — nunca nesta.
-- Nenhum grant é concedido a anon/authenticated/service_role; as policies e
-- grants das F2-03/F2-07 (identidade/sessão) e o estado das tabelas F3-01
-- permanecem inalterados.
alter table public.job_roles enable row level security;
alter table public.seniority_levels enable row level security;
