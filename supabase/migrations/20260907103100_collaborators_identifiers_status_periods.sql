-- ============================================================================
-- F3-01 (Issue #78): colaboradores com identidade interna imutável e lifecycle
-- temporal
-- ----------------------------------------------------------------------------
-- Propósito: criar o núcleo persistente de colaboradores da organização sem
-- embutir hierarquia, área, gestor direto, posição ou ocupação no cadastro da
-- pessoa, seguindo as convenções da F1-02 (supabase/migrations/README.md) e as
-- entidades da F2-01/F2-02 (organizations, user_profiles,
-- user_organization_memberships):
--
--   - public.collaborators                — identidade técnica do colaborador
--     (UUID interno imutável) escopada por organização; sem matrícula/código,
--     nome ou e-mail como identidade;
--   - public.collaborator_identifiers     — identificador(es) de negócio
--     (ex.: matrícula/código) com validade temporal, permitindo evolução/
--     histórico do código sem trocar collaborators.id;
--   - public.collaborator_status_periods  — períodos de status do colaborador
--     (ACTIVE/LEAVE/INACTIVE) por valid_from/valid_to, histórico não
--     destrutivo e sem sobreposição temporal no banco.
--
-- Decisões técnicas registradas (Issue #78 e revisão de escopo desta etapa):
--   - `collaborators` carrega apenas identidade técnica (id + organization_id)
--     e colunas técnicas; nome/e-mail/CPF são atributos de cadastro de pessoa
--     de issues futuras — nada de gestorDireto, area, unidade, funcao,
--     senioridade, cargo, posição ou ocupação aqui (F3-02/F3-03 em diante);
--   - identificadores de negócio vivem em tabela própria com validade temporal
--     (código atual = linha aberta com valid_to null; troca de código = fechar
--     a linha e abrir outra), nunca em coluna de collaborators; cada código é
--     único por organização (sem reutilização na mesma organização), reuso
--     entre organizações diferentes é permitido;
--   - status em text + check nomeado, valores lowercase: 'active' (ATIVO),
--     'leave' (LICENCA) e 'inactive' (DESLIGADO); 'terminated' e ESTAGIARIO
--     não entram: ESTAGIARIO é função organizacional (catálogo da F3-02,
--     Issue #79), não status de pessoa;
--   - linha do tempo única por colaborador: exclusion constraint com
--     `tstzrange` meio-aberto `[valid_from, valid_to)` impede QUALQUER
--     sobreposição de períodos do mesmo colaborador (um único status por
--     instante; no máximo um período aberto vigente), inclusive entre status
--     "incompatíveis"; períodos fechados permanecem preservados (histórico);
--   - períodos temporalmente inválidos (valid_to <= valid_from, código vazio)
--     rejeitados por check constraints no banco;
--   - LEAVE (licença) é estado do colaborador e NÃO encerra posição/ocupação:
--     não existe tabela de posição/ocupação nesta issue e nenhuma FK aponta
--     para estrutura organizacional;
--   - todas as FKs com ON DELETE RESTRICT (padrão F1-02): exclusão física de
--     organização, colaborador, identificador ou período de status exige
--     tratamento explícito de domínio em fase futura; mudanças de lifecycle
--     ocorrem por novos períodos/status, nunca por exclusão de histórico;
--   - RLS habilitado e deny-by-default nas três tabelas, sem policies e sem
--     grants nesta etapa (mesmo padrão F2-01/F2-02); nenhuma política existente
--     é alterada e nada de Auth/membership é tocado.
--
-- Fora do escopo desta etapa (não antecipar — Issue #78):
--   - árvore/hierarquia, reporting lines, gestorDireto, area/unidade;
--   - posições, ocupações e vínculo de membership a colaborador
--     (collaborator_id em user_organization_memberships fica para migration
--     aditiva futura, registrada na F2-02);
--   - funções/senioridades (F3-02), unidades/posições formais (F3-03),
--     capabilities/roles (Fase 4), avaliação/colegiado;
--   - dados reais, colunas de senha/secret/token e alterações no runtime.
--
-- Dependências: migration dedicada
-- `20260907103000_enable_btree_gist.sql` (extensão btree_gist) e as tabelas
-- public.organizations (F2-01).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.collaborators
-- ----------------------------------------------------------------------------
-- Identidade técnica do colaborador dentro de uma organização. O UUID interno
-- (`id`) é imutável e nunca é chave de negócio; matrícula/código, nome e
-- e-mail não participam da identidade. Escopo por organização via
-- organization_id (FK RESTRICT), seguindo o padrão da F1-02: entidades
-- multi-organização carregam organization_id desde a criação.
--
-- A linha NÃO possui atributos de pessoa/estrutura nesta etapa: nome/e-mail
-- (cadastro de pessoa) e função/senioridade/cargo/área/posição pertencem a
-- issues futuras; incluir esses campos agora seria antecipar funcionalidade
-- (proibido pela Issue #78). `version` presente porque a entidade admite
-- edição concorrente futura; `updated_at` mantido pelo trigger técnico F1-03.
create table public.collaborators (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_collaborators primary key (id),
  constraint uq_collaborators_id_organization unique (id, organization_id),
  constraint fk_collaborators_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict
);

comment on table public.collaborators is
  'Colaborador (identidade tecnica interna) - F3-01 (Issue #78). Nome canonico '
  'da tabela: collaborators (termo registrado nas decisoes da F2-02).';

comment on column public.collaborators.id is
  'Identificador tecnico imutavel (UUID), nunca chave de negocio e nunca '
  'reutilizado (convencao F1-02); gerado por gen_random_uuid().';

comment on column public.collaborators.organization_id is
  'Organizacao (public.organizations) da qual o colaborador faz parte. '
  'ON DELETE RESTRICT: excluir uma organizacao exige tratar os colaboradores '
  'explicitamente em fase futura.';

comment on constraint uq_collaborators_id_organization on public.collaborators is
  'Unique de referencia para a FK composta de collaborator_identifiers '
  '(collaborator_id, organization_id): garante no banco que o organization_id '
  'do identificador e sempre igual ao organization_id do colaborador '
  '(consistencia declarativa, decisao D4 da Issue #78).';

comment on column public.collaborators.version is
  'Controle de concorrencia otimista (F1-02); incrementado pela aplicacao a '
  'cada atualizacao. Nao e dado de negocio.';

comment on constraint fk_collaborators_organizations on public.collaborators is
  'ON DELETE RESTRICT (padrao F1-02): sem cascata silenciosa — colaboradores e '
  'seus historicos sao ancoras preservaveis; exclusao fisica de organizacao '
  'exige decisao de dominio em fase futura.';

create index ix_collaborators_organization_id
  on public.collaborators (organization_id);

create trigger trg_collaborators_updated_at
  before update on public.collaborators
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.collaborator_identifiers
-- ----------------------------------------------------------------------------
-- Identificadores de negocio do colaborador (ex.: matricula/codigo) com
-- validade temporal, separados do UUID interno. Decisao tecnica (Issue #78):
--   - o codigo atual e a linha com valid_to null (aberta); trocar o codigo
--     historico = fechar a linha atual (valid_to) e inserir a nova linha
--     aberta — o collaborator.id nunca muda;
--   - unicidade por organizacao: no maximo um colaborador com o mesmo codigo
--     em uma mesma organizacao, em qualquer vigencia (sem reutilizacao de
--     codigo dentro da organizacao — regra atual da aplicacao); reuso entre
--     organizacoes diferentes e permitido (unique inclui organization_id);
--   - linha do tempo unica por colaborador via exclusion constraint: nenhum
--     periodo sobreposto (no maximo um codigo vigente por colaborador);
--   - organization_id e repetido aqui de forma direta para permitir a
--     constraint unique por organizacao e consultas/RLS futuros por
--     organizacao; a consistencia entre identifiers.organization_id e
--     collaborators.organization_id e garantida no banco por FK composta
--     (collaborator_id, organization_id) → collaborators(id, organization_id)
--     (decisao D4 da Issue #78);
--   - codigo armazenado como text (aceita numeros e/ou letras de futuros
--     esquemas de codigo) ja normalizado: sem espacos nas bordas e nao vazio
--     (check constraint).
create table public.collaborator_identifiers (
  id              uuid        not null default gen_random_uuid(),
  collaborator_id uuid        not null,
  organization_id uuid        not null,
  business_code   text        not null,
  valid_from      timestamptz not null,
  valid_to        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_collaborator_identifiers primary key (id),
  constraint uq_collaborator_identifiers_organization_code
    unique (organization_id, business_code),
  constraint fk_collaborator_identifiers_collaborators foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint ck_collaborator_identifiers_business_code
    check (business_code <> '' and business_code = btrim(business_code)),
  constraint ck_collaborator_identifiers_valid_to
    check (valid_to is null or valid_to > valid_from),
  constraint ex_collaborator_identifiers_no_overlap
    exclude using gist (
      collaborator_id with =,
      tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
    )
);

comment on table public.collaborator_identifiers is
  'Identificadores de negocio do colaborador com validade temporal - F3-01 '
  '(Issue #78). Codigo atual = linha aberta (valid_to null); historico nao '
  'destrutivo; business_code nunca e PK nem identidade tecnica.';

comment on column public.collaborator_identifiers.business_code is
  'Codigo de negocio do colaborador na organizacao (ex.: matricula). Unico por '
  'organizacao em qualquer vigencia; normalizado (sem espacos nas bordas). '
  'Alteracoes de codigo preservam historico sem trocar collaborators.id.';

comment on column public.collaborator_identifiers.valid_to is
  'Fim da vigencia (bound exclusivo, meio-aberto [valid_from, valid_to)); '
  'null = codigo vigente (periodo aberto). Fechar a linha atual e inserir nova '
  'linha aberta representa a troca historica de codigo.';

comment on column public.collaborator_identifiers.organization_id is
  'Organizacao do codigo. Repetida de forma direta para permitir a constraint '
  'unique (organization_id, business_code) e o escopo por organizacao; a '
  'igualdade com collaborators.organization_id e garantida pela FK composta '
  'fk_collaborator_identifiers_collaborators.';

comment on constraint fk_collaborator_identifiers_collaborators
  on public.collaborator_identifiers is
  'FK composta (collaborator_id, organization_id) → '
  'collaborators(id, organization_id), ON DELETE RESTRICT (padrao F1-02): '
  'garante no banco que todo identificador aponta para um colaborador e que o '
  'organization_id do identificador e sempre igual ao do colaborador '
  '(consistencia declarativa da decisao D4 da Issue #78).';

comment on constraint uq_collaborator_identifiers_organization_code
  on public.collaborator_identifiers is
  'Sem reutilizacao de codigo dentro da mesma organizacao (qualquer vigencia); '
  'o mesmo codigo pode existir em organizacoes diferentes (multi-organizacao).';

comment on constraint ck_collaborator_identifiers_valid_to
  on public.collaborator_identifiers is
  'Periodo temporalmente valido: valid_to, quando presente, deve ser posterior '
  'a valid_from (periodo meio-aberto nao degenerado).';

comment on constraint ex_collaborator_identifiers_no_overlap
  on public.collaborator_identifiers is
  'No maximo um identificador vigente por colaborador: periodos do mesmo '
  'colaborador nao podem se sobrepor (exclusion constraint com tstzrange '
  'meio-aberto e btree_gist).';

create index ix_collaborator_identifiers_collaborator_id
  on public.collaborator_identifiers (collaborator_id);

create trigger trg_collaborator_identifiers_updated_at
  before update on public.collaborator_identifiers
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.collaborator_status_periods
-- ----------------------------------------------------------------------------
-- Períodos de status do colaborador (linha do tempo de lifecycle). Decisão
-- técnica (Issue #78):
--   - status como text + check nomeado, valores lowercase ingleses conforme
--     convenção F1-02 e o padrão já usado nas F2 ('active'/'disabled'):
--       'active'  ↔ ATIVO      (em atividade na organização);
--       'leave'   ↔ LICENCA    (licença: estado do colaborador — NÃO encerra
--                                posição/ocupação, inexistente nesta issue);
--       'inactive'↔ DESLIGADO  (desligado da organização; terminal nesta fase);
--     'terminated' não é usado (carga semântica de RH nem sempre fiel ao
--     desligamento) e ESTAGIARIO não é status (função — catálogo da F3-02);
--   - linha do tempo única por colaborador: exclusion constraint impede
--     QUALQUER sobreposição de períodos do mesmo colaborador (um único status
--     por instante — estados simultâneos incompatíveis como active+leave são
--     impossíveis no banco) e garante no máximo um período aberto vigente;
--     transições (ex.: ACTIVE → LEAVE → ACTIVE) fecham a linha anterior
--     (valid_to) e abrem a próxima, preservando o histórico;
--   - períodos temporalmente inválidos (valid_to <= valid_from) rejeitados por
--     check constraint; sem exclusão física de histórico (FK RESTRICT e RLS
--     deny-by-default; nenhuma policy de escrita nesta fase).
create table public.collaborator_status_periods (
  id              uuid        not null default gen_random_uuid(),
  collaborator_id uuid        not null,
  status          text        not null default 'active',
  valid_from      timestamptz not null,
  valid_to        timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_collaborator_status_periods primary key (id),
  constraint fk_collaborator_status_periods_collaborators foreign key (collaborator_id)
    references public.collaborators (id)
    on delete restrict,
  constraint ck_collaborator_status_periods_status
    check (status in ('active', 'leave', 'inactive')),
  constraint ck_collaborator_status_periods_valid_to
    check (valid_to is null or valid_to > valid_from),
  constraint ex_collaborator_status_periods_no_overlap
    exclude using gist (
      collaborator_id with =,
      tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz), '[)') with &&
    )
);

comment on table public.collaborator_status_periods is
  'Periodos de status do colaborador (lifecycle temporal) - F3-01 (Issue #78). '
  'Historico nao destrutivo com valid_from/valid_to; um unico status por '
  'instante.';

comment on column public.collaborator_status_periods.status is
  'Status do colaborador na organizacao: active (ATIVO), leave (LICENCA — '
  'estado do colaborador, nao encerra posicao/ocupacao) ou inactive '
  '(DESLIGADO). Conjunto ampliavel apenas por nova migration (F1-02).';

comment on column public.collaborator_status_periods.valid_to is
  'Fim da vigencia (bound exclusivo, meio-aberto [valid_from, valid_to)); '
  'null = status vigente (periodo aberto). Transicoes fecham a linha anterior '
  'e abrem a proxima, preservando historico.';

comment on constraint ck_collaborator_status_periods_status
  on public.collaborator_status_periods is
  'Dominio de status da F3-01: active/leave/inactive (mapeamento documentado '
  'ATIVO/LICENCA/DESLIGADO); ESTAGIARIO e funcao (F3-02), nao status.';

comment on constraint ck_collaborator_status_periods_valid_to
  on public.collaborator_status_periods is
  'Periodo temporalmente valido: valid_to, quando presente, deve ser posterior '
  'a valid_from (periodo meio-aberto nao degenerado).';

comment on constraint ex_collaborator_status_periods_no_overlap
  on public.collaborator_status_periods is
  'Linha do tempo unica por colaborador: nenhuma sobreposicao de periodos do '
  'mesmo colaborador (um unico status por instante; no maximo um periodo '
  'aberto vigente). Impede no banco estados simultaneos incompativeis '
  '(ex.: active e leave ao mesmo tempo) via exclusion constraint com tstzrange '
  'meio-aberto e btree_gist.';

create index ix_collaborator_status_periods_collaborator_id
  on public.collaborator_status_periods (collaborator_id);

create trigger trg_collaborator_status_periods_updated_at
  before update on public.collaborator_status_periods
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default (sem policies nesta etapa)
-- ----------------------------------------------------------------------------
-- RLS é habilitada nas três tabelas novas. NENHUMA policy é criada nesta
-- migration, no mesmo padrão da F2-01/F2-02:
--   - deny-by-default integral: sem policy, nenhuma role submetida a RLS
--     (inclusive `authenticated`) consegue ler ou escrever nessas tabelas;
--   - esta issue não define modelo de acesso a colaboradores (escopos/
--     permissões são da Fase 4): qualquer policy agora seria permissiva ou
--     anteciparia autorização futura;
--   - políticas restritivas entrarão, quando o modelo de acesso existir, como
--     novas migrations aditivas — nunca nesta.
-- Nenhum grant é concedido a anon/authenticated/service_role; as policies e
-- grants das F2-03/F2-07 (identidade/sessão) permanecem inalterados e nenhuma
-- tabela de Auth/membership é tocada.
alter table public.collaborators enable row level security;
alter table public.collaborator_identifiers enable row level security;
alter table public.collaborator_status_periods enable row level security;
