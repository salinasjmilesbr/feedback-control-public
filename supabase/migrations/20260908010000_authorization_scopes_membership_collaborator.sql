-- ============================================================================
-- F4-02 (Issue #89): escopos de autorização (scope assignments)
-- ----------------------------------------------------------------------------
-- Propósito: modelar o ALCANCE (sobre quem/onde) das capabilities atribuídas na
-- F4-01, evoluindo `membership_access_role_assignments` de forma aditiva.
-- Contrato arquitetural: docs/F4-02-desenho-tecnico.md (D1–D18 fechadas).
--
-- Entidades criadas:
--   - public.membership_collaborator_links — vínculo explícito membership →
--     collaborator (D1 = A): uma linha por membership (reativação no lugar),
--     colaborador da MESMA organização (FKs compostas de tenant);
--   - public.access_role_assignment_scopes — tabela filha 1:N de scopes ligada
--     à assignment (D2 = B): tipos SELF/DIRECT_REPORTS/DESCENDANTS/
--     ORGANIZATIONAL_UNIT/ORGANIZATION/ASSIGNED; scope pertence à assignment,
--     nunca ao access_role (D3 = A); múltiplos scopes por assignment (D4 = A);
--     status active/revoked sem exclusão física (D5/D11);
--   - public.access_role_assignment_unit_targets — target TIPADO por entidade
--     (D6 = híbrida ajustada): somente para ORGANIZATIONAL_UNIT (consumidor
--     concreto); sem polimorfismo genérico inseguro; sem subunidades (D5).
--
-- Regras (invariantes do desenho):
--   - assignment sem scope = fail-closed (D15); ORGANIZATION é scope EXPLÍCITO
--     (D14) — nenhum default implícito;
--   - scopes estruturais (SELF/DIRECT_REPORTS/DESCENDANTS) exigem vínculo e
--     resolvem na data; ADMIN sem collaborator usa ORGANIZATION (D17);
--   - ASSIGNED derivado de F3-08/09 NÃO é duplicado (D6): o tipo existe, mas a
--     resolução de alvos de colegiado/avaliação pertence à F4-03/F4-05;
--   - substituição temporária (F3-06) NÃO é persistida (D13): resolvida por
--     data pelos resolvers F3-07; o mapa capability×responsibility_type é F4-05.
--
-- Funções (SECURITY INVOKER, STABLE — D18 = A): resolvem o que a RLS permitir;
-- service_role/superuser resolvem internamente (padrão F3-07). Nenhum DEFINER
-- novo. RLS deny-by-default nas três tabelas novas (zero policies, zero grants).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Referência aditiva em assignments (padrão F3/F4-01) para a FK composta de
-- tenant das linhas de scope.
-- ----------------------------------------------------------------------------
alter table public.membership_access_role_assignments
  add constraint uq_membership_access_role_assignments_id_organization
    unique (id, organization_id);

comment on constraint uq_membership_access_role_assignments_id_organization
  on public.membership_access_role_assignments is
  'Referencia aditiva (id, organization_id) para a FK composta de tenant da '
  'F4-02 (access_role_assignment_scopes). Nao altera regras da F4-01.';

-- ----------------------------------------------------------------------------
-- public.membership_collaborator_links — vínculo membership → collaborator
-- ----------------------------------------------------------------------------
create table public.membership_collaborator_links (
  id              uuid        not null default gen_random_uuid(),
  membership_id   uuid        not null,
  organization_id uuid        not null,
  collaborator_id uuid        not null,
  status          text        not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_membership_collaborator_links primary key (id),
  constraint uq_membership_collaborator_links_membership
    unique (membership_id),
  constraint fk_membership_collaborator_links_memberships
    foreign key (membership_id)
    references public.user_organization_memberships (id)
    on delete restrict,
  constraint fk_membership_collaborator_links_membership_organization
    foreign key (membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict,
  constraint fk_membership_collaborator_links_collaborators
    foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint ck_membership_collaborator_links_status
    check (status in ('active', 'disabled'))
);

comment on table public.membership_collaborator_links is
  'Vinculo explicito membership -> collaborator - F4-02 (Issue #89, D1=A). '
  'Base do scope SELF e da raiz dos scopes estruturais; uma linha por '
  'membership (reativacao no lugar).';

comment on column public.membership_collaborator_links.membership_id is
  'Membership (usuario+organizacao) vinculada. Unica por linha: no maximo um '
  'colaborador vinculado por membership.';

comment on column public.membership_collaborator_links.collaborator_id is
  'Colaborador (pessoa na estrutura) da MESMA organizacao (FK composta de '
  'tenant). ADMIN sem collaborator simplesmente nao possui vinculo.';

comment on column public.membership_collaborator_links.status is
  'active/disabled (sem exclusao fisica). Disabled = vinculo desativado (raiz '
  'de SELF/estruturais deixa de resolver).';

comment on constraint uq_membership_collaborator_links_membership
  on public.membership_collaborator_links is
  'No maximo uma linha por membership (um vinculo ativo; reativacao no lugar, '
  'padrao F2-02).';

create index ix_membership_collaborator_links_organization_id
  on public.membership_collaborator_links (organization_id);

create index ix_membership_collaborator_links_collaborator_id
  on public.membership_collaborator_links (collaborator_id);

create trigger trg_membership_collaborator_links_updated_at
  before update on public.membership_collaborator_links
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.access_role_assignment_scopes — linhas de scope por assignment
-- ----------------------------------------------------------------------------
create table public.access_role_assignment_scopes (
  id              uuid        not null default gen_random_uuid(),
  assignment_id   uuid        not null,
  organization_id uuid        not null,
  scope_type      text        not null,
  status          text        not null default 'active',
  created_by      uuid        not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  version         integer     not null default 0,
  constraint pk_access_role_assignment_scopes primary key (id),
  constraint uq_access_role_assignment_scopes_id_organization
    unique (id, organization_id),
  constraint uq_access_role_assignment_scopes_assignment_type
    unique (assignment_id, scope_type),
  constraint fk_access_role_assignment_scopes_assignments
    foreign key (assignment_id)
    references public.membership_access_role_assignments (id)
    on delete restrict,
  constraint fk_access_role_assignment_scopes_assignment_organization
    foreign key (assignment_id, organization_id)
    references public.membership_access_role_assignments (id, organization_id)
    on delete restrict,
  constraint fk_access_role_assignment_scopes_author
    foreign key (created_by)
    references public.user_profiles (id)
    on delete restrict,
  constraint ck_access_role_assignment_scopes_type
    check (scope_type in (
      'SELF',
      'DIRECT_REPORTS',
      'DESCENDANTS',
      'ORGANIZATIONAL_UNIT',
      'ORGANIZATION',
      'ASSIGNED'
    )),
  constraint ck_access_role_assignment_scopes_status
    check (status in ('active', 'revoked'))
);

comment on table public.access_role_assignment_scopes is
  'Scope (alcance) de uma atribuicao membership->access_role - F4-02 (D2=B). '
  'Scope pertence a assignment, nunca ao access_role (D3=A). Assignment sem '
  'linha de scope = fail-closed (D15).';

comment on column public.access_role_assignment_scopes.scope_type is
  'SELF | DIRECT_REPORTS | DESCENDANTS | ORGANIZATIONAL_UNIT | ORGANIZATION | '
  'ASSIGNED. Um tipo por (assignment) no maximo uma linha (alvos adicionais '
  'vivem em targets tipados).';

comment on column public.access_role_assignment_scopes.status is
  'active/revoked (D11). Revogar a assignment inativa os scopes filhos; a '
  'revogacao granular de scope e por status proprio, sem exclusao fisica.';

comment on constraint uq_access_role_assignment_scopes_assignment_type
  on public.access_role_assignment_scopes is
  'No maximo uma linha de scope por (assignment, tipo).';

create index ix_access_role_assignment_scopes_organization_id
  on public.access_role_assignment_scopes (organization_id);

create index ix_access_role_assignment_scopes_created_by
  on public.access_role_assignment_scopes (created_by);

create trigger trg_access_role_assignment_scopes_updated_at
  before update on public.access_role_assignment_scopes
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- public.access_role_assignment_unit_targets — alvo tipado de ORGANIZATIONAL_UNIT
-- ----------------------------------------------------------------------------
create table public.access_role_assignment_unit_targets (
  id                    uuid        not null default gen_random_uuid(),
  scope_id              uuid        not null,
  organization_id       uuid        not null,
  organizational_unit_id uuid       not null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  version               integer     not null default 0,
  constraint pk_access_role_assignment_unit_targets primary key (id),
  constraint uq_access_role_assignment_unit_targets_scope_unit
    unique (scope_id, organizational_unit_id),
  constraint fk_access_role_assignment_unit_targets_scopes
    foreign key (scope_id, organization_id)
    references public.access_role_assignment_scopes (id, organization_id)
    on delete restrict,
  constraint fk_access_role_assignment_unit_targets_units
    foreign key (organizational_unit_id, organization_id)
    references public.organizational_units (id, organization_id)
    on delete restrict
);

comment on table public.access_role_assignment_unit_targets is
  'Alvo tipado de um scope ORGANIZATIONAL_UNIT (D5/D6): somente a unidade '
  'explicitamente atribuida, sem subunidades. Sem polimorfismo generico.';

comment on constraint uq_access_role_assignment_unit_targets_scope_unit
  on public.access_role_assignment_unit_targets is
  'Uma unidade alvo no maximo uma vez por scope.';

create index ix_access_role_assignment_unit_targets_unit_id
  on public.access_role_assignment_unit_targets (organizational_unit_id);

create trigger trg_access_role_assignment_unit_targets_updated_at
  before update on public.access_role_assignment_unit_targets
  for each row
  execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Trigger: target de unidade só em scope ORGANIZATIONAL_UNIT
-- ----------------------------------------------------------------------------
create or replace function public.enforce_unit_target_scope_type()
returns trigger
language plpgsql
as $$
declare
  v_scope_type text;
begin
  select s.scope_type
    into v_scope_type
    from public.access_role_assignment_scopes s
   where s.id = new.scope_id;

  if v_scope_type is distinct from 'ORGANIZATIONAL_UNIT' then
    raise exception 'F4-02: target de unidade exige scope_type ORGANIZATIONAL_UNIT';
  end if;

  return new;
end;
$$;

comment on function public.enforce_unit_target_scope_type() is
  'F4-02: garante que um alvo de unidade pertence a um scope do tipo '
  'ORGANIZATIONAL_UNIT (target tipado; sem polimorfismo inseguro).';

create trigger trg_access_role_assignment_unit_targets_scope_type
  before insert or update of scope_id
  on public.access_role_assignment_unit_targets
  for each row
  execute function public.enforce_unit_target_scope_type();

-- ----------------------------------------------------------------------------
-- Funções de resolução (SECURITY INVOKER, STABLE — D18 = A)
-- ----------------------------------------------------------------------------

-- 1) Colaborador vinculado à membership ativa (raiz de SELF/estruturais).
create or replace function public.resolver_collaborador_vinculado(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns table (collaborator_id uuid)
language sql
stable
set search_path = public
as $$
  select l.collaborator_id
    from public.user_organization_memberships m
    join public.membership_collaborator_links l
      on l.membership_id = m.id
     and l.status = 'active'
   where m.user_profile_id = p_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active'
$$;

comment on function public.resolver_collaborador_vinculado(uuid, uuid) is
  'F4-02 (D1): colaborador vinculado a membership ativa do usuario na '
  'organizacao. Vazio quando nao ha vinculo (fail-closed para SELF/estruturais).';

-- 2) Capabilities efetivas × scope (união de roles ativas × scopes ativos).
create or replace function public.resolver_capabilities_escopos_efetivas(
  p_user_profile_id uuid,
  p_organization_id uuid
)
returns table (
  access_role_id         uuid,
  capability_code        text,
  scope_type             text,
  organizational_unit_id uuid
)
language sql
stable
set search_path = public
as $$
  select distinct
    r.id,
    c.code,
    s.scope_type,
    ut.organizational_unit_id
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
  join public.access_role_assignment_scopes s
    on s.assignment_id = a.id
   and s.status = 'active'
  left join public.access_role_assignment_unit_targets ut
    on ut.scope_id = s.id
  where m.user_profile_id = p_user_profile_id
    and m.organization_id = p_organization_id
    and m.status = 'active'
    and up.status = 'active'
$$;

comment on function public.resolver_capabilities_escopos_efetivas(uuid, uuid) is
  'F4-02: capabilities efetivas de um usuario na organizacao, com o scope (e '
  'alvo de unidade) de cada atribuicao ativa. Assignment sem scope nao aparece '
  '(fail-closed); membro/perfil/assignment/scope desabilitados tambem nao.';

-- 3) Alvos (colaboradores/posições) de um scope, resolvidos na data.
create or replace function public.resolver_alvos_escopo(
  p_user_profile_id      uuid,
  p_organization_id      uuid,
  p_scope_type           text,
  p_organizational_unit_id uuid,
  p_data                 timestamptz
)
returns table (collaborator_id uuid, position_id uuid)
language plpgsql
stable
set search_path = public
as $$
begin
  if p_scope_type = 'SELF' then
    return query
      select v.collaborator_id, null::uuid
        from public.resolver_collaborador_vinculado(p_user_profile_id, p_organization_id) v;
    return;
  end if;

  if p_scope_type = 'DIRECT_REPORTS' then
    return query
      select distinct r.subordinate_responsible_collaborator_id, r.subordinate_position_id
        from public.resolver_collaborador_vinculado(p_user_profile_id, p_organization_id) v
        cross join lateral public.organizacao_resolver_subordinados_diretos(v.collaborator_id, p_data) r
       where r.subordinate_responsible_collaborator_id is not null;
    return;
  end if;

  if p_scope_type = 'DESCENDANTS' then
    return query
      select distinct on (r.position_id)
             r.responsible_collaborator_id, r.position_id
        from public.resolver_collaborador_vinculado(p_user_profile_id, p_organization_id) v
        cross join lateral public.organizacao_resolver_descendentes(v.collaborator_id, p_data) r
       order by r.position_id, r.depth;
    return;
  end if;

  if p_scope_type = 'ORGANIZATIONAL_UNIT' then
    return query
      select distinct o.collaborator_id, o.organizational_position_id
        from public.organizational_positions p
        join public.occupations o
          on o.organizational_position_id = p.id
         and o.valid_from <= p_data
         and (o.valid_to is null or o.valid_to > p_data)
       where p.unit_id = p_organizational_unit_id
         and p.organization_id = p_organization_id
         and p.valid_from <= p_data
         and (p.valid_to is null or p.valid_to > p_data);
    return;
  end if;

  if p_scope_type = 'ORGANIZATION' then
    return query
      select c.id, null::uuid
        from public.collaborators c
       where c.organization_id = p_organization_id;
    return;
  end if;

  -- ASSIGNED: alvos derivados de F3-08/09 são resolvidos pela F4-03/F4-05;
  -- nenhum alvo estrutural é derivado aqui (fail-closed). Colegiado nunca vira
  -- hierarquia.
  return;
end;
$$;

comment on function public.resolver_alvos_escopo(uuid, uuid, text, uuid, timestamptz) is
  'F4-02: alvos (colaboradores/posicoes) de um scope, resolvidos na data '
  '(D9/D16). SELF usa o vinculo; DIRECT_REPORTS/DESCENDANTS usam os resolvers '
  'F3-07 (responsavel efetivo no contexto vivo); ORGANIZATIONAL_UNIT usa '
  'somente a unidade atribuida (sem subunidades); ORGANIZATION usa o tenant; '
  'ASSIGNED nao deriva hierarquia (fail-closed ate F4-03/F4-05).';

-- ----------------------------------------------------------------------------
-- RLS — deny-by-default nas três tabelas novas (zero policies, zero grants)
-- ----------------------------------------------------------------------------
alter table public.membership_collaborator_links enable row level security;
alter table public.access_role_assignment_scopes enable row level security;
alter table public.access_role_assignment_unit_targets enable row level security;
