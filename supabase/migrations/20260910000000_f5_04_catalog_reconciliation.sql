-- ============================================================================
-- F5-04 (Issue #165): reconciliação do catálogo de capabilities (D14/D15)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-04-desenho-tecnico.md (D1–D18 FECHADAS).
--
-- D14 — DB é a fonte canônica dos códigos concedíveis por role; convergência
-- controlada DB↔engine por MIGRATION ADITIVA (nunca por mapper runtime
-- fuzzy/permissivo); código desconhecido ⇒ DENY (fail-closed); deprecação de
-- aliases SEM remoção física.
--
-- D15 — separação entre o plano FUNCIONAL (roles concedem capabilities
-- funcionais) e o plano ADMINISTRATIVO de controle: `membership.manage`,
-- `access_role.manage`, `exceptional_access.grant` e `pilot_full_access.grant`
-- ficam FORA do catálogo concedível por role (grantable_via_role = false);
-- prevenção de self-escalation é estrutural (nenhuma role carrega capability de
-- controle; trigger rejeita associação role→capability não-concedível).
--
-- Catálogo canônico resultante (29 códigos, espelho de Capability.ts):
--   colaborador/ciclo/avaliação/meta/observação (ações granulares),
--   report.read, settings.manage, membership.read/manage, access_role.manage,
--   org.structure.manage, org.catalog.manage, exceptional_access.grant,
--   pilot_full_access.grant.
-- Códigos coarse deprecados (mantidos fisicamente): collaborator.manage,
-- observation.write (reconciliados às ações granulares).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Colunas aditivas em capabilities (D15): marcador de concedível-por-role e
--    deprecação sem remoção física.
-- ----------------------------------------------------------------------------
alter table public.capabilities
  add column grantable_via_role boolean not null default true,
  add column deprecated boolean not null default false;

comment on column public.capabilities.grantable_via_role is
  'F5-04 (D15): true = capability FUNCIONAL concedivel por access_role; '
  'false = plano ADMINISTRATIVO de controle (membership.manage, '
  'access_role.manage, exceptional_access.grant, pilot_full_access.grant), '
  'fora do catalogo concedivel por role. Nunca altera a decisao do engine: a '
  'posse continua sendo resolvida pelo Policy Engine.';

comment on column public.capabilities.deprecated is
  'F5-04 (D14): true = codigo coarse/legado reconciliado as acoes granulares '
  'canonicas (ex.: collaborator.manage -> collaborator.create/edit). Sem '
  'remocao fisica (D14); nunca concedido por role nova; codigo desconhecido no '
  'engine => DENY.';

-- ----------------------------------------------------------------------------
-- 2) Novas capabilities canônicas (D14, migration aditiva). UUIDs fixos,
--    prefixo c0, continuando a sequência do catálogo de sistema F4-01.
--    grantable_via_role=false para as duas do plano C/D (D15).
-- ----------------------------------------------------------------------------
insert into public.capabilities (id, code, name, description, grantable_via_role) values
  ('c0000000-0000-4000-8000-000000000022', 'collaborator.create',
   'Criar colaboradores', 'Criar colaborador da organizacao (acao granular; F4-09 §6.3).', true),
  ('c0000000-0000-4000-8000-000000000023', 'collaborator.edit',
   'Editar colaboradores', 'Editar cadastro de colaborador da organizacao (acao granular; F4-09 §6.3).', true),
  ('c0000000-0000-4000-8000-000000000024', 'cycle.cancel',
   'Cancelar ciclos', 'Cancelar ciclo ATIVO (fluxo excepcional auditavel).', true),
  ('c0000000-0000-4000-8000-000000000025', 'cycle.reopen',
   'Reabrir ciclos', 'Reabrir ciclo ENCERRADO (fluxo excepcional auditavel).', true),
  ('c0000000-0000-4000-8000-000000000026', 'cycle.period.correct',
   'Corrigir periodo de ciclos', 'Corrigir periodo de ciclo ATIVO (fluxo excepcional auditavel).', true),
  ('c0000000-0000-4000-8000-000000000027', 'observation.create',
   'Criar observacoes', 'Criar observacao em ciclo ATIVO (acao granular; F4-09 §6.3).', true),
  ('c0000000-0000-4000-8000-000000000028', 'observation.edit',
   'Editar observacoes', 'Editar observacao em ciclo ATIVO (acao granular; F4-09 §6.3).', true),
  ('c0000000-0000-4000-8000-000000000029', 'observation.delete',
   'Excluir observacoes', 'Excluir (soft) observacao em ciclo ATIVO (acao granular; F4-09 §6.3).', true),
  ('c0000000-0000-4000-8000-000000000030', 'exceptional_access.grant',
   'Conceder acesso excepcional', 'Conceder acesso excepcional C (F4-06). Plano administrativo: fora do catalogo concedivel por role.', false),
  ('c0000000-0000-4000-8000-000000000031', 'pilot_full_access.grant',
   'Conceder Pilot Full Access', 'Conceder Pilot Full Access D (F4-07, dev-only). Plano administrativo: fora do catalogo concedivel por role.', false);

-- ----------------------------------------------------------------------------
-- 3) Marca as capabilities de controle como não-concedíveis por role (D15).
-- ----------------------------------------------------------------------------
update public.capabilities
   set grantable_via_role = false
 where code in ('membership.manage', 'access_role.manage');

-- ----------------------------------------------------------------------------
-- 4) Depreca os códigos coarse reconciliados (D14, sem remoção física).
-- ----------------------------------------------------------------------------
update public.capabilities
   set deprecated = true
 where code in ('collaborator.manage', 'observation.write');

-- ----------------------------------------------------------------------------
-- 5) Ajuste do bundle `admin` (D15): remove as capabilities de controle e o
--    código coarse deprecado; adiciona as ações granulares de gestão de
--    cadastro. Resultado = bundle FUNCIONAL de administração (8 capabilities),
--    SEM controle e SEM conteúdo confidencial.
-- ----------------------------------------------------------------------------
delete from public.access_role_capabilities
 where access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
   and capability_id in (
     select id from public.capabilities
      where code in ('membership.manage', 'access_role.manage', 'collaborator.manage')
   );

insert into public.access_role_capabilities (access_role_id, capability_id)
select 'c0000000-0000-4000-8000-0000000000f1', c.id
  from public.capabilities c
 where c.code in ('collaborator.create', 'collaborator.edit')
 on conflict (access_role_id, capability_id) do nothing;

-- ----------------------------------------------------------------------------
-- 6) Trigger D15: nenhuma role pode associar capability de controle ou
--    deprecada (separação do plano administrativo, enforcement estrutural).
-- ----------------------------------------------------------------------------
create or replace function public.enforce_role_capability_grantable()
returns trigger
language plpgsql
as $$
declare
  v_grantable boolean;
  v_deprecated boolean;
begin
  select c.grantable_via_role, c.deprecated
    into v_grantable, v_deprecated
    from public.capabilities c
   where c.id = new.capability_id;

  if not found then
    raise exception 'F5-04: capability inexistente';
  end if;

  if v_deprecated then
    raise exception 'F5-04: capability deprecada nao pode ser associada a access_role (codigo desconhecido => DENY)';
  end if;

  if not v_grantable then
    raise exception 'F5-04: capability do plano administrativo (controle/C-D) nao pode ser associada a access_role';
  end if;

  return new;
end;
$$;

comment on function public.enforce_role_capability_grantable() is
  'F5-04 (D15): impede que qualquer access_role (sistema ou customizada) '
  'associe capability do plano administrativo (grantable_via_role=false) ou '
  'deprecada. Prevencao estrutural de self-escalation: controle/C-D nao '
  'transitam por role.';

create trigger trg_access_role_capabilities_grantable
  before insert or update of capability_id
  on public.access_role_capabilities
  for each row
  execute function public.enforce_role_capability_grantable();

-- ----------------------------------------------------------------------------
-- 7) Endurecimento dos resolvers (D14): excluem capability deprecada. Código
--    desconhecido/deprecado nunca é devolvido como capability efetiva
--    (fail-closed); a tradução é feita no catálogo, nunca em runtime.
-- ----------------------------------------------------------------------------
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
     and c.deprecated = false
   where m.user_profile_id = p_user_profile_id
     and m.organization_id = p_organization_id
     and m.status = 'active'
     and up.status = 'active'
   order by c.code
$$;

comment on function public.resolver_capabilities_efetivas(uuid, uuid) is
  'F4-01/F5-04 (D14): predicado canonico de capabilities efetivas (sem escopo). '
  'Exclui capability deprecada (fail-closed). EXECUTE somente service_role.';

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
   and c.deprecated = false
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
  'F4-02/F5-04 (D14): capabilities efetivas com scope (e alvo de unidade). '
  'Exclui capability deprecada (fail-closed). Assignment sem scope nao aparece.';
