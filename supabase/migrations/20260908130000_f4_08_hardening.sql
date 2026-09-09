-- ============================================================================
-- F4-08 (Issue #95): endurecimento de funções — achados de segurança §12
-- ----------------------------------------------------------------------------
-- 1) `registrar_sucessao_avaliador`: correlação soberana de tenant — todas as
--    responsabilidades informadas DEVEM pertencer à MESMA organization_id
--    (derivada do banco, nunca do chamador). Cross-tenant = DENY fail-closed.
-- 2) Triggers F3-04/F3-05/F3-06: FOUND check — parent inexistente → raise
--    (fail-closed), nunca continuar com variável NULL/estado parcial.
-- 3) Triggers F4-01/F4-02 sem `set search_path`: adiciona `set search_path =
--    public` (defesa contra hijacking de search_path).
--
-- Nenhum SECURITY DEFINER novo; nenhuma ampliação de grants. `create or
-- replace` preserva os triggers já vinculados e os comentários existentes.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) registrar_sucessao_avaliador — guard de tenant (F4-08 §12.1)
-- ----------------------------------------------------------------------------
create or replace function public.registrar_sucessao_avaliador(
  p_responsibility_ids uuid[],
  p_succession_date timestamptz,
  p_motive text,
  p_author_user_profile_id uuid
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_rid uuid;
  v_open record;
  v_organization_id uuid;
  v_superior_position_id uuid;
  v_new_responsible uuid;
begin
  if p_motive is null or btrim(p_motive) = '' then
    raise exception 'registrar_sucessao_avaliador: motivo obrigatorio';
  end if;
  if p_succession_date is null then
    raise exception 'registrar_sucessao_avaliador: data de sucessao obrigatoria';
  end if;
  if p_author_user_profile_id is null then
    raise exception 'registrar_sucessao_avaliador: autor obrigatorio';
  end if;

  foreach v_rid in array coalesce(p_responsibility_ids, '{}'::uuid[])
  loop
    -- Responsabilidade identificada pelo ID canonico informado (D8).
    select cer.id, cer.organization_id, cer.snapshot_id, cer.position_id,
           cer.responsible_collaborator_id, cer.valid_from, cer.valid_to
      into v_open
    from public.cycle_evaluation_responsibilities cer
    where cer.id = v_rid;

    if not found then
      raise exception
        'registrar_sucessao_avaliador: responsabilidade nao encontrada (id %)', v_rid;
    end if;

    -- F4-08 (§12.1): correlação soberana de tenant. O organization_id vem da
    -- própria responsabilidade (banco), nunca do chamador; qualquer mistura de
    -- organizações em uma única sucessão é negada (fail-closed).
    if v_organization_id is null then
      v_organization_id := v_open.organization_id;
    elsif v_open.organization_id <> v_organization_id then
      raise exception
        'registrar_sucessao_avaliador: responsabilidades de organizacoes distintas (cross-tenant negado)';
    end if;

    -- Nunca reabre responsabilidade encerrada (D8).
    if v_open.valid_to is not null then
      raise exception
        'registrar_sucessao_avaliador: responsabilidade ja encerrada (id %)', v_rid;
    end if;

    -- Idempotencia: sucessao ja registrada para esta (snapshot, posicao, data).
    if exists (
      select 1
      from public.evaluation_succession_events e
      where e.snapshot_id = v_open.snapshot_id
        and e.position_id = v_open.position_id
        and e.succession_date = p_succession_date
    ) then
      continue;
    end if;

    if p_succession_date <= v_open.valid_from then
      raise exception
        'registrar_sucessao_avaliador: data de sucessao deve ser posterior ao inicio da responsabilidade';
    end if;

    -- Posicao superior congelada no snapshot (nao recalculada retroativamente).
    select sp.superior_position_id
      into v_superior_position_id
    from public.collegiate_cycle_snapshot_positions sp
    where sp.snapshot_id = v_open.snapshot_id
      and sp.position_id = v_open.position_id;

    if v_superior_position_id is null then
      raise exception
        'registrar_sucessao_avaliador: posicao sem superior no snapshot';
    end if;

    -- Novo responsavel permanente (titular) na data de sucessao.
    select r.titular_collaborator_id
      into v_new_responsible
    from public.organizacao_resolver_responsavel_avaliativo_posicao(
      v_superior_position_id, p_succession_date
    ) r;

    if v_new_responsible is null then
      raise exception
        'registrar_sucessao_avaliador: sem novo responsavel resolvido na data';
    end if;

    if v_new_responsible = v_open.responsible_collaborator_id then
      continue; -- nada a transferir
    end if;

    -- Fecha a responsabilidade aberta e abre a nova (close+open).
    update public.cycle_evaluation_responsibilities
       set valid_to = p_succession_date
     where id = v_open.id
       and valid_to is null;

    insert into public.cycle_evaluation_responsibilities (
      id, organization_id, snapshot_id, position_id,
      responsible_collaborator_id, valid_from
    ) values (
      gen_random_uuid(),
      v_open.organization_id,
      v_open.snapshot_id,
      v_open.position_id,
      v_new_responsible,
      p_succession_date
    );

    -- Evento de sucessao (append-only, imutavel).
    insert into public.evaluation_succession_events (
      id, organization_id, snapshot_id, position_id,
      previous_responsible_collaborator_id, new_responsible_collaborator_id,
      succession_date, motive, author_user_profile_id
    ) values (
      gen_random_uuid(),
      v_open.organization_id,
      v_open.snapshot_id,
      v_open.position_id,
      v_open.responsible_collaborator_id,
      v_new_responsible,
      p_succession_date,
      btrim(p_motive),
      p_author_user_profile_id
    );
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2) Triggers F3-04/F3-05/F3-06 — FOUND check (fail-closed)
-- ----------------------------------------------------------------------------

-- F3-05 (occupations): posição alvo inexistente → raise.
create or replace function public.enforce_occupation_within_position()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_pos_from timestamptz;
  v_pos_to   timestamptz;
begin
  select valid_from, valid_to
    into v_pos_from, v_pos_to
  from public.organizational_positions
  where id = new.organizational_position_id;

  if not found then
    raise exception
      'occupations: posicao alvo inexistente (fail-closed)';
  end if;

  if new.valid_from < v_pos_from then
    raise exception
      'occupations: periodo inicia antes da existencia da posicao';
  end if;

  if new.valid_to is null then
    if v_pos_to is not null then
      raise exception
        'occupations: ocupacao aberta alem do encerramento da posicao';
    end if;
  else
    if v_pos_to is not null and new.valid_to > v_pos_to then
      raise exception
        'occupations: periodo termina depois do encerramento da posicao';
    end if;
  end if;

  return new;
end;
$$;

-- F3-06 (temporary_responsibilities): posição alvo inexistente → raise.
create or replace function public.enforce_temporary_responsibility_within_position()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_pos_from timestamptz;
  v_pos_to   timestamptz;
begin
  select valid_from, valid_to
    into v_pos_from, v_pos_to
  from public.organizational_positions
  where id = new.organizational_position_id;

  if not found then
    raise exception
      'temporary_responsibilities: posicao alvo inexistente (fail-closed)';
  end if;

  if new.valid_from < v_pos_from then
    raise exception
      'temporary_responsibilities: periodo inicia antes da existencia da posicao';
  end if;

  if v_pos_to is not null and new.valid_to > v_pos_to then
    raise exception
      'temporary_responsibilities: periodo termina depois do encerramento da posicao';
  end if;

  return new;
end;
$$;

-- F3-04 (position_reporting_lines): posições inexistentes → raise.
create or replace function public.enforce_position_reporting_lines_within_positions()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_sub_from timestamptz;
  v_sub_to   timestamptz;
  v_man_from timestamptz;
  v_man_to   timestamptz;
begin
  select valid_from, valid_to
    into v_sub_from, v_sub_to
  from public.organizational_positions
  where id = new.subordinate_position_id;

  if not found then
    raise exception
      'position_reporting_lines: posicao subordinada inexistente (fail-closed)';
  end if;

  select valid_from, valid_to
    into v_man_from, v_man_to
  from public.organizational_positions
  where id = new.manager_position_id;

  if not found then
    raise exception
      'position_reporting_lines: posicao gestora inexistente (fail-closed)';
  end if;

  if new.valid_from < v_sub_from or new.valid_from < v_man_from then
    raise exception
      'position_reporting_lines: periodo inicia antes da existencia das posicoes';
  end if;

  if new.valid_to is null then
    if v_sub_to is not null or v_man_to is not null then
      raise exception
        'position_reporting_lines: relacao aberta alem do encerramento de uma posicao';
    end if;
  else
    if (v_sub_to is not null and new.valid_to > v_sub_to)
       or (v_man_to is not null and new.valid_to > v_man_to) then
      raise exception
        'position_reporting_lines: periodo termina depois do encerramento de uma posicao';
    end if;
  end if;

  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3) Triggers F4-01/F4-02 — `set search_path = public` (defesa contra
--    hijacking de search_path)
-- ----------------------------------------------------------------------------

create or replace function public.enforce_membership_role_within_organization()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_role_organization_id uuid;
begin
  select r.organization_id
    into v_role_organization_id
    from public.access_roles r
   where r.id = new.access_role_id;

  -- Caso 1: role INEXISTENTE — lookup sem linha NÃO é system role (NULL ≠
  -- wildcard). Fail-closed.
  if not found then
    raise exception
      'F4-01: access_role inexistente (id %), atribuicao negada (fail-closed)',
      new.access_role_id;
  end if;

  -- Caso 2: system role válida — organization_id NULL é explícito, não wildcard.
  if v_role_organization_id is null then
    return new;
  end if;

  -- Caso 3: tenant role válida — deve pertencer à MESMA organização da membership.
  if v_role_organization_id <> new.organization_id then
    raise exception 'F4-01: access_role pertence a outra organizacao (cross-tenant negado)';
  end if;

  return new;
end;
$$;

create or replace function public.enforce_unit_target_scope_type()
returns trigger
language plpgsql
set search_path = public
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
