-- ============================================================================
-- F5-02 (vínculo usuário autenticado ↔ colaborador): caminho administrativo
-- server-side/transacional de mutação do vínculo (D9)
-- ----------------------------------------------------------------------------
-- D9 (fechada): criar, desativar e TROCAR o vínculo somente por caminho
-- server-side/transacional; sem DML direto para `authenticated`.
--
-- As três funções são `SECURITY INVOKER` (padrão F3-09/F4-02 D18; nenhum
-- `SECURITY DEFINER` novo) e têm `EXECUTE` concedido SOMENTE a `service_role`
-- (revogado de `public`/`anon`/`authenticated`) — a fronteira confiável usada
-- pelas Edge Functions/tooling, nunca pelo cliente.
--
-- Regras (Q6 = B / Q3 = B):
--   - a troca é ATÔMICA: desativa o link `active` atual e insere a nova linha
--     `active` numa única transação; falha em qualquer etapa = rollback total;
--   - NUNCA sobrescrever `collaborator_id` de linha existente (histórica ou
--     ativa);
--   - linhas `disabled` permanecem como histórico;
--   - tenant correlation preservada pelas FKs compostas existentes
--     (membership e colaborador na MESMA organization_id), com checagem
--     explícita para erro claro (cross-tenant negado);
--   - as unicidades parciais (migration anterior) são backstop: violação ⇒
--     `unique_violation`/erro e rollback.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- vincular_colaborador: cria vínculo active para uma membership
-- ----------------------------------------------------------------------------
create or replace function public.vincular_colaborador(
  p_membership_id uuid,
  p_collaborator_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_link_id uuid;
begin
  select organization_id into v_organization_id
    from public.user_organization_memberships
   where id = p_membership_id
     and status = 'active';
  if not found then
    raise exception 'vincular_colaborador: membership inexistente ou inativa';
  end if;

  -- tenant correlation: colaborador na MESMA organização (FK composta é
  -- backstop; cheque explícito para erro claro — cross-tenant negado).
  if not exists (
    select 1 from public.collaborators
     where id = p_collaborator_id
       and organization_id = v_organization_id
  ) then
    raise exception 'vincular_colaborador: colaborador de outro tenant ou inexistente (cross-tenant negado)';
  end if;

  -- Q6 = B: no máximo 1 link active por membership.
  if exists (
    select 1 from public.membership_collaborator_links
     where membership_id = p_membership_id
       and status = 'active'
  ) then
    raise exception 'vincular_colaborador: membership ja possui vinculo ativo';
  end if;

  -- Q3 = B: no máximo 1 link active por (collaborator, organization).
  if exists (
    select 1 from public.membership_collaborator_links
     where collaborator_id = p_collaborator_id
       and organization_id = v_organization_id
       and status = 'active'
  ) then
    raise exception 'vincular_colaborador: colaborador ja possui vinculo ativo na organizacao';
  end if;

  insert into public.membership_collaborator_links
    (membership_id, organization_id, collaborator_id, status)
  values
    (p_membership_id, v_organization_id, p_collaborator_id, 'active')
  returning id into v_link_id;

  return v_link_id;
end;
$$;

comment on function public.vincular_colaborador(uuid, uuid) is
  'F5-02 (D9): cria vinculo active membership->collaborator (mesmo tenant). '
  'Fail-closed: membership inativa, colaborador cross-tenant, membership ja '
  'com vinculo ativo (Q6) ou colaborador ja ativo na organizacao (Q3) => erro. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- desativar_vinculo_colaborador: desativa o link active de uma membership
-- ----------------------------------------------------------------------------
create or replace function public.desativar_vinculo_colaborador(
  p_membership_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.membership_collaborator_links
     set status = 'disabled'
   where membership_id = p_membership_id
     and status = 'active';
end;
$$;

comment on function public.desativar_vinculo_colaborador(uuid) is
  'F5-02 (D9): desativa o vinculo active da membership (linha vira historico '
  'disabled; nunca sobrescreve collaborator_id). Idempotente (sem active = '
  'no-op). SECURITY INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- trocar_vinculo_colaborador: desativa o link ativo e cria o novo (atômico)
-- ----------------------------------------------------------------------------
create or replace function public.trocar_vinculo_colaborador(
  p_membership_id uuid,
  p_novo_collaborator_id uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_organization_id uuid;
  v_link_id uuid;
begin
  select organization_id into v_organization_id
    from public.user_organization_memberships
   where id = p_membership_id
     and status = 'active';
  if not found then
    raise exception 'trocar_vinculo_colaborador: membership inexistente ou inativa';
  end if;

  if not exists (
    select 1 from public.collaborators
     where id = p_novo_collaborator_id
       and organization_id = v_organization_id
  ) then
    raise exception 'trocar_vinculo_colaborador: colaborador de outro tenant ou inexistente (cross-tenant negado)';
  end if;

  -- Q3 = B: o novo colaborador não pode ter outro vínculo active na mesma
  -- organização (em outra membership). Falha aqui ⇒ toda a transação é
  -- revertida (nenhum estado intermediário).
  if exists (
    select 1 from public.membership_collaborator_links
     where collaborator_id = p_novo_collaborator_id
       and organization_id = v_organization_id
       and status = 'active'
       and membership_id <> p_membership_id
  ) then
    raise exception 'trocar_vinculo_colaborador: colaborador ja possui vinculo ativo em outra membership da organizacao';
  end if;

  -- 1) desativa o link active atual (histórico preservado; nunca UPDATE de
  --    collaborator_id);
  update public.membership_collaborator_links
     set status = 'disabled'
   where membership_id = p_membership_id
     and status = 'active';

  -- 2) insere a nova linha active;
  insert into public.membership_collaborator_links
    (membership_id, organization_id, collaborator_id, status)
  values
    (p_membership_id, v_organization_id, p_novo_collaborator_id, 'active')
  returning id into v_link_id;

  return v_link_id;
end;
$$;

comment on function public.trocar_vinculo_colaborador(uuid, uuid) is
  'F5-02 (D9/Q6=B): troca o colaborador de uma membership de forma ATOMICA — '
  'desativa o link active atual (linha vira historico disabled) e insere nova '
  'linha active; nunca sobrescreve collaborator_id. Falha em qualquer etapa => '
  'rollback total. Tenant correlation preservada (FKs compostas). SECURITY '
  'INVOKER; EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- Grants: EXECUTE somente service_role (sem superfície para authenticated)
-- ----------------------------------------------------------------------------
revoke all on function public.vincular_colaborador(uuid, uuid) from public, anon, authenticated;
revoke all on function public.desativar_vinculo_colaborador(uuid) from public, anon, authenticated;
revoke all on function public.trocar_vinculo_colaborador(uuid, uuid) from public, anon, authenticated;

grant execute on function public.vincular_colaborador(uuid, uuid) to service_role;
grant execute on function public.desativar_vinculo_colaborador(uuid) to service_role;
grant execute on function public.trocar_vinculo_colaborador(uuid, uuid) to service_role;
