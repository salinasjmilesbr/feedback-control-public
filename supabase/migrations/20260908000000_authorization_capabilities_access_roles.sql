-- ============================================================================
-- F4-01 (Issue #88): capabilities e access_roles (modelo de autorização)
-- ----------------------------------------------------------------------------
-- Propósito: criar o modelo explícito de autorização do Virtus, sem derivar
-- permissões de cargo/função organizacional. Contrato arquitetural:
-- docs/F4-01-desenho-tecnico.md (decisões D1–D18 fechadas).
--
-- Entidades criadas:
--   - public.capabilities — catálogo GLOBAL de permissões (D1 = A):
--     `code` único global (notação domínio.verbo, D15 = A); status
--     active/disabled (D5 = A); sem organization_id (catálogo do produto);
--   - public.access_roles — papéis de ACESSO, jamais cargo (D2 = C, D14):
--     roles de sistema (is_system = true, organization_id NULL) + roles
--     customizadas por organização (organization_id NOT NULL);
--   - public.access_role_capabilities — associação N:N role → capability
--     (D11 = A; capabilities globais => associação livre entre roles e o
--     catálogo global);
--   - public.membership_access_role_assignments — atribuição membership →
--     access_role (D3 = A: roles são a única via; D4 = A: múltiplas roles por
--     membership; D12 = A: tabela-âncora enxuta que a F4-02 estenderá com
--     escopo; D13 = A: autor mínimo created_by).
--
-- Integridade:
--   - cross-tenant por construção: a coluna organization_id da atribuição é
--     garantida igual à membership via FK composta aditiva
--     uq_user_organization_memberships_id_organization + FK composta; e o
--     trigger enforce_membership_role_within_organization bloqueia role
--     customizada de outra organização (roles de sistema têm organization_id
--     NULL e não podem participar de FK composta — por isso a checagem de
--     tenant do lado da role é por trigger, no mesmo padrão F3).
--   - sem exclusão física (D5/D6): FKs ON DELETE RESTRICT; catálogos com
--     status; atribuição revogada por status (revoked), nunca apagada.
--
-- RLS: deny-by-default nas quatro tabelas novas (RLS habilitado, zero
-- policies, zero grants a authenticated/anon) — D7/D9 e invariante 7. Nenhuma
-- leitura/escrita ampla antes da etapa da F4 que a autorizar.
--
-- Mecanismo técnico mínimo server-side (D16 = A ajustada), exclusivo
-- service_role (sem bypass para authenticated):
--   - conceder_acesso_role / revogar_acesso_role (SECURITY DEFINER): validam
--     membership ativa, perfil ativo, role ativa e tenant;
--   - resolver_capabilities_efetivas (SECURITY DEFINER, EXECUTE service_role):
--     predicado canônico de capabilities efetivas (usado por testes/futuras
--     policies), sem escopo (scopes são F4-02).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Referência aditiva em memberships para a FK composta de tenant
-- (padrão F3-03/04/05). Aditiva: não altera colunas nem regras existentes.
-- ----------------------------------------------------------------------------
alter table public.user_organization_memberships
  add constraint uq_user_organization_memberships_id_organization
    unique (id, organization_id);

comment on constraint uq_user_organization_memberships_id_organization
  on public.user_organization_memberships is
  'Referencia aditiva (id, organization_id) para a FK composta de tenant da '
  'F4-01 (membership_access_role_assignments). Nao altera regras da F2-02.';

-- ----------------------------------------------------------------------------
-- public.capabilities — catálogo global da unidade explícita de permissão
-- ----------------------------------------------------------------------------
create table public.capabilities (
  id          uuid        not null default gen_random_uuid(),
  code        text        not null,
  name        text        not null,
  description text,
  status      text        not null default 'active',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  version     integer     not null default 0,
  constraint pk_capabilities primary key (id),
  constraint uq_capabilities_code unique (code),
  constraint ck_capabilities_code
    check (code <> '' and code = btrim(code) and code = lower(code)),
  constraint ck_capabilities_name
    check (name <> '' and name = btrim(name)),
  constraint ck_capabilities_status
    check (status in ('active', 'disabled'))
);

comment on table public.capabilities is
  'Catalogo GLOBAL de capabilities (unidade explicita de permissao) - F4-01 '
  '(Issue #88, D1=A/D15=A). Sem organization_id: vocabulario unico do produto.';

comment on column public.capabilities.code is
  'Codigo estavel e unico global (notacao dominio.verbo, espelho de '
  'src/authorization/Capability.ts). Nunca reutilizado apos deprecacao.';

comment on column public.capabilities.status is
  'active/disabled (D5=A). Inativacao sem exclusao fisica; conjunto ampliavel '
  'apenas por migration.';

create trigger trg_capabilities_updated_at
  before update on public.capabilities
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.access_roles — papéis de acesso (sistema + customizados por org)
-- ----------------------------------------------------------------------------
create table public.access_roles (
  id              uuid        not null default gen_random_uuid(),
  name            text        not null,
  status          text        not null default 'active',
  is_system       boolean     not null default false,
  organization_id uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_access_roles primary key (id),
  constraint uq_access_roles_organization_name unique (organization_id, name),
  constraint fk_access_roles_organizations foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint ck_access_roles_name check (name <> '' and name = btrim(name)),
  constraint ck_access_roles_status check (status in ('active', 'disabled')),
  constraint ck_access_roles_system_scope check (
    (is_system and organization_id is null)
    or (not is_system and organization_id is not null)
  )
);

comment on table public.access_roles is
  'Access role (papel de ACESSO, jamais cargo) - F4-01 (Issue #88, D2=C/D14). '
  'Sistema (is_system=true, organization_id null) ou customizado por '
  'organizacao.';

comment on column public.access_roles.is_system is
  'true = role de sistema/bootstrap (imutavel por migration, D6=B); '
  'false = role customizada por organizacao (organization_id obrigatorio).';

comment on column public.access_roles.organization_id is
  'NULL apenas para roles de sistema (globais); roles customizadas pertencem a '
  'uma organizacao (ownership tenant, D10=A).';

comment on constraint uq_access_roles_organization_name on public.access_roles is
  'Nome unico por organizacao para roles customizadas (espelho job_roles). '
  'Roles de sistema usam a unica parcial uq_access_roles_system_name.';

comment on constraint ck_access_roles_system_scope on public.access_roles is
  'Consistencia is_system x organization_id: sistema => org NULL; '
  'customizada => org NOT NULL (D2=C).';

-- Unicidade global do nome das roles de sistema (organization_id NULL).
-- Exceção documentada à convenção F1-02 (unicidade por constraint unique):
-- é a forma declarativa de unicidade PARCIAL (apenas system roles); a
-- unicidade das customizadas permanece por constraint
-- uq_access_roles_organization_name.
create unique index uq_access_roles_system_name
  on public.access_roles (name)
  where organization_id is null;

create trigger trg_access_roles_updated_at
  before update on public.access_roles
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.access_role_capabilities — associação role → capability (N:N)
-- ----------------------------------------------------------------------------
create table public.access_role_capabilities (
  id             uuid        not null default gen_random_uuid(),
  access_role_id uuid        not null,
  capability_id  uuid        not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  version        integer     not null default 0,
  constraint pk_access_role_capabilities primary key (id),
  constraint uq_access_role_capabilities_role_capability
    unique (access_role_id, capability_id),
  constraint fk_access_role_capabilities_roles foreign key (access_role_id)
    references public.access_roles (id)
    on delete restrict,
  constraint fk_access_role_capabilities_capabilities foreign key (capability_id)
    references public.capabilities (id)
    on delete restrict
);

comment on table public.access_role_capabilities is
  'Associacao N:N access_role -> capability (D11=A). Capabilities sao globais: '
  'qualquer role (sistema/org) agrupa capabilities do catalogo global.';

comment on constraint uq_access_role_capabilities_role_capability
  on public.access_role_capabilities is
  'Uma capability por role no maximo uma vez.';

create index ix_access_role_capabilities_capability_id
  on public.access_role_capabilities (capability_id);

create trigger trg_access_role_capabilities_updated_at
  before update on public.access_role_capabilities
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.membership_access_role_assignments — atribuição membership → role
-- ----------------------------------------------------------------------------
create table public.membership_access_role_assignments (
  id              uuid        not null default gen_random_uuid(),
  membership_id   uuid        not null,
  organization_id uuid        not null,
  access_role_id  uuid        not null,
  status          text        not null default 'active',
  created_by      uuid        not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_membership_access_role_assignments primary key (id),
  constraint uq_membership_access_role_assignments_membership_role
    unique (membership_id, access_role_id),
  constraint fk_membership_access_role_assignments_memberships
    foreign key (membership_id)
    references public.user_organization_memberships (id)
    on delete restrict,
  constraint fk_membership_access_role_assignments_membership_organization
    foreign key (membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict,
  constraint fk_membership_access_role_assignments_roles
    foreign key (access_role_id)
    references public.access_roles (id)
    on delete restrict,
  constraint fk_membership_access_role_assignments_author
    foreign key (created_by)
    references public.user_profiles (id)
    on delete restrict,
  constraint ck_membership_access_role_assignments_status
    check (status in ('active', 'revoked'))
);

comment on table public.membership_access_role_assignments is
  'Atribuicao membership -> access_role (D3=A/D4=A/D12=A/D13=A). Uma linha por '
  'par (membership, role) em qualquer status; revogacao = status revoked no '
  'lugar (sem exclusao fisica; historico preservado).';

comment on column public.membership_access_role_assignments.organization_id is
  'Tenant denormalizado, garantido igual ao da membership pela FK composta.';

comment on column public.membership_access_role_assignments.status is
  'active/revoked (D6/D7). Revogar nunca apaga a linha.';

comment on column public.membership_access_role_assignments.created_by is
  'Autor minimo da concessao (user_profiles) - D13=A (precedente F3-09).';

comment on constraint uq_membership_access_role_assignments_membership_role
  on public.membership_access_role_assignments is
  'No maximo uma linha por par membership/role (reativacao no lugar, padrao '
  'F2-02).';

create index ix_membership_access_role_assignments_organization_id
  on public.membership_access_role_assignments (organization_id);

create index ix_membership_access_role_assignments_access_role_id
  on public.membership_access_role_assignments (access_role_id);

create index ix_membership_access_role_assignments_created_by
  on public.membership_access_role_assignments (created_by);

create trigger trg_membership_access_role_assignments_updated_at
  before update on public.membership_access_role_assignments
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Trigger de integridade cross-tenant do lado da role (padrão F3)
-- ----------------------------------------------------------------------------
create or replace function public.enforce_membership_role_within_organization()
returns trigger
language plpgsql
as $$
declare
  v_role_organization_id uuid;
begin
  select r.organization_id
    into v_role_organization_id
    from public.access_roles r
   where r.id = new.access_role_id;

  if v_role_organization_id is not null
     and v_role_organization_id <> new.organization_id then
    raise exception 'F4-01: access_role pertence a outra organizacao (cross-tenant negado)';
  end if;

  return new;
end;
$$;

comment on function public.enforce_membership_role_within_organization() is
  'F4-01: bloqueia atribuicao de role customizada a membership de outra '
  'organizacao. Roles de sistema (organization_id NULL) sao livres.';

create trigger trg_membership_access_role_assignments_role_organization
  before insert or update of access_role_id, organization_id
  on public.membership_access_role_assignments
  for each row
  execute function public.enforce_membership_role_within_organization();

-- ----------------------------------------------------------------------------
-- Mecanismo técnico mínimo server-side (D16 = A ajustada) — EXECUTE só para
-- service_role (sem bypass para authenticated/anon).
-- ----------------------------------------------------------------------------

-- Concessão (cria ou reativa a atribuição no lugar).
create or replace function public.conceder_acesso_role(
  p_membership_id uuid,
  p_access_role_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organization_id    uuid;
  v_user_profile_id    uuid;
  v_membership_status  text;
  v_profile_status     text;
  v_role_organization  uuid;
  v_role_status        text;
begin
  if p_actor_user_profile_id is null then
    raise exception 'F4-01: ator da concessao e obrigatorio';
  end if;

  select m.organization_id, m.user_profile_id, m.status
    into v_organization_id, v_user_profile_id, v_membership_status
    from public.user_organization_memberships m
   where m.id = p_membership_id;

  if not found then
    raise exception 'F4-01: membership inexistente';
  end if;
  if v_membership_status <> 'active' then
    raise exception 'F4-01: membership nao ativa';
  end if;

  select up.status
    into v_profile_status
    from public.user_profiles up
   where up.id = v_user_profile_id;

  if v_profile_status is null or v_profile_status <> 'active' then
    raise exception 'F4-01: perfil do usuario nao ativo';
  end if;

  select r.organization_id, r.status
    into v_role_organization, v_role_status
    from public.access_roles r
   where r.id = p_access_role_id;

  if not found then
    raise exception 'F4-01: access_role inexistente';
  end if;
  if v_role_status <> 'active' then
    raise exception 'F4-01: access_role nao ativa';
  end if;
  if v_role_organization is not null and v_role_organization <> v_organization_id then
    raise exception 'F4-01: access_role de outra organizacao';
  end if;

  insert into public.membership_access_role_assignments
    (membership_id, organization_id, access_role_id, status, created_by)
  values
    (p_membership_id, v_organization_id, p_access_role_id, 'active', p_actor_user_profile_id)
  on conflict (membership_id, access_role_id) do update
    set status = 'active',
        updated_at = now(),
        version = public.membership_access_role_assignments.version + 1;
end;
$$;

comment on function public.conceder_acesso_role(uuid, uuid, uuid) is
  'F4-01 (D16): concessao/reativacao server-side de access_role a uma '
  'membership. Valida membership ativa, perfil ativo, role ativa e tenant; '
  'reativa no lugar (sem duplicar linha). EXECUTE somente service_role.';

-- Revogação por estado (nunca exclusão física).
create or replace function public.revogar_acesso_role(
  p_membership_id uuid,
  p_access_role_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
begin
  if p_actor_user_profile_id is null then
    raise exception 'F4-01: ator da revogacao e obrigatorio';
  end if;

  update public.membership_access_role_assignments
     set status = 'revoked',
         updated_at = now(),
         version = version + 1
   where membership_id = p_membership_id
     and access_role_id = p_access_role_id;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'F4-01: atribuicao inexistente';
  end if;
end;
$$;

comment on function public.revogar_acesso_role(uuid, uuid, uuid) is
  'F4-01 (D16): revogacao server-side por estado (status=revoked), sem '
  'exclusao fisica da atribuicao. EXECUTE somente service_role.';

-- Predicado canônico de capabilities efetivas (sem escopo — F4-02).
create or replace function public.resolver_capabilities_efetivas(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns table (capability_code text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct c.code
    from public.user_organization_memberships m
    join public.user_profiles up
      on up.id = m.user_profile_id
    join public.membership_access_role_assignments a
      on a.membership_id = m.id
     and a.status = 'active'
    join public.access_roles r
      on r.id = a.access_role_id
     and r.status = 'active'
    join public.access_role_capabilities rc
      on rc.access_role_id = r.id
    join public.capabilities c
      on c.id = rc.capability_id
     and c.status = 'active'
   where m.user_profile_id = p_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active'
     and up.status = 'active'
   order by c.code
$$;

comment on function public.resolver_capabilities_efetivas(uuid, uuid) is
  'F4-01 (D16): predicado canonico de capabilities efetivas de um usuario em '
  'uma organizacao (membership ativa + perfil ativo + atribuicao ativa + role '
  'ativa + capability ativa). Sem escopo (F4-02). EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- Fronteira de execução: somente service_role (espelho criar_perfil_membership)
-- ----------------------------------------------------------------------------
revoke all on function public.conceder_acesso_role(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.conceder_acesso_role(uuid, uuid, uuid)
  to service_role;

revoke all on function public.revogar_acesso_role(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.revogar_acesso_role(uuid, uuid, uuid)
  to service_role;

revoke all on function public.resolver_capabilities_efetivas(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.resolver_capabilities_efetivas(uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default nas quatro tabelas novas (zero policies, zero grants)
-- ----------------------------------------------------------------------------
alter table public.capabilities enable row level security;
alter table public.access_roles enable row level security;
alter table public.access_role_capabilities enable row level security;
alter table public.membership_access_role_assignments enable row level security;
