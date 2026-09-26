-- F6 / Issue #365 — projeção histórica de reporting line no colaborador.
-- A autoridade permanece em collaborator_events, occupations e posições UUID.

create or replace function public.colaborador_historico_listar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_collaborator_id uuid
)
returns table (
  event_id uuid,
  event_type text,
  effective_date timestamptz,
  reason text,
  cycle_scope text,
  reference_cycle_id uuid,
  actor_user_profile_id uuid,
  actor_full_name text,
  before_value jsonb,
  after_value jsonb,
  created_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if p_collaborator_id is null then
    raise exception 'F5_07_INVALID_INPUT: collaborator_id obrigatorio';
  end if;

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if not exists (
    select 1 from public.collaborators c
     where c.id = p_collaborator_id
       and c.organization_id = p_organization_id
  ) then
    return;
  end if;

  return query
  with eventos as (
    select e.*,
           false as eh_reporting,
           null::jsonb as ocupantes_gestor
      from public.collaborator_events e
     where e.organization_id = p_organization_id
       and e.collaborator_id = p_collaborator_id

    union all

    select e.*,
           true as eh_reporting,
           historico.ocupantes_gestor
      from public.collaborator_events e
      join public.occupations subordinada
        on subordinada.organization_id = e.organization_id
       and subordinada.collaborator_id = p_collaborator_id
       and subordinada.organizational_position_id = e.position_id
       and subordinada.valid_from <= e.effective_date
       and (subordinada.valid_to is null or subordinada.valid_to > e.effective_date)
      cross join lateral (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'manager_position_id', gestores.manager_position_id,
                 'occupant_collaborator_id', ocupante.collaborator_id,
                 'occupant_full_name', ocupante.full_name
               ) order by gestores.manager_position_id), '[]'::jsonb) as ocupantes_gestor
          from (
            select nullif(e.after_value->>'manager_position_id', '')::uuid as manager_position_id
             where e.event_type = 'REPORTING_LINE_INICIADA'
            union
            select nullif(item->>'manager_position_id', '')::uuid
              from jsonb_array_elements(coalesce(e.before_value->'linhas', '[]'::jsonb)) item
             where e.event_type = 'REPORTING_LINE_ENCERRADA'
          ) gestores
          left join lateral (
            select o.collaborator_id, c.full_name
              from public.occupations o
              join public.collaborators c
                on c.id = o.collaborator_id
               and c.organization_id = p_organization_id
             where o.organization_id = p_organization_id
               and o.organizational_position_id = gestores.manager_position_id
               and case
                     when e.event_type = 'REPORTING_LINE_INICIADA'
                       then o.valid_from <= e.effective_date
                        and (o.valid_to is null or o.valid_to > e.effective_date)
                     when e.event_type = 'REPORTING_LINE_ENCERRADA'
                       then o.valid_from < e.effective_date
                        and (o.valid_to is null or o.valid_to >= e.effective_date)
                     else false
                   end
             order by o.valid_from desc, o.id
             limit 1
          ) ocupante on true
      ) historico on true
     where e.organization_id = p_organization_id
       and e.collaborator_id is null
       and e.position_id is not null
       and e.event_type in ('REPORTING_LINE_INICIADA', 'REPORTING_LINE_ENCERRADA')
  )
  select e.id,
         e.event_type,
         e.effective_date,
         e.reason,
         e.cycle_scope,
         e.reference_cycle_id,
         e.actor_user_profile_id,
         vinculo.full_name,
         case when e.eh_reporting
              then e.before_value || jsonb_build_object('historical_manager_occupants', e.ocupantes_gestor)
              else e.before_value end,
         case when e.eh_reporting
              then e.after_value || jsonb_build_object('historical_manager_occupants', e.ocupantes_gestor)
              else e.after_value end,
         e.created_at
    from eventos e
    left join lateral (
      select c.full_name
        from public.user_organization_memberships m
        join public.membership_collaborator_links l
          on l.membership_id = m.id and l.status = 'active'
        join public.collaborators c
          on c.id = l.collaborator_id and c.organization_id = m.organization_id
       where m.user_profile_id = e.actor_user_profile_id
         and m.organization_id = p_organization_id
         and m.status = 'active'
       limit 1
    ) vinculo on true
   order by e.effective_date desc, e.created_at desc;
end;
$$;

comment on function public.colaborador_historico_listar(uuid, uuid, uuid) is
  'F6 #365: projeta eventos de reporting line no historico do colaborador pela ocupacao soberana na data efetiva; nunca usa o ocupante atual.';
