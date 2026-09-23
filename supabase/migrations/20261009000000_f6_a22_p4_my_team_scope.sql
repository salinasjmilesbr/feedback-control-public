-- F6-A22 P4: Minha equipe e criacao limitada ao escopo soberano.
-- Nenhuma role/capability nova; DIRECT_REPORTS/DESCENDANTS sao resolvidos
-- exclusivamente pelos resolvers existentes.

create or replace function public.f6_a22_p4_tem_escopo_colaborador(
  p_actor_user_profile_id uuid,
  p_organization_id uuid,
  p_capability_code text,
  p_collaborator_id uuid,
  p_data timestamptz default now()
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
      from public.resolver_capabilities_escopos_efetivas(
        p_actor_user_profile_id, p_organization_id) g
      cross join lateral public.resolver_alvos_escopo(
        p_actor_user_profile_id, p_organization_id, g.scope_type,
        g.organizational_unit_id, coalesce(p_data, now())) alvo
     where g.capability_code = p_capability_code
       and p_capability_code in ('collaborator.read', 'collaborator.create')
       and g.scope_type in ('DIRECT_REPORTS', 'DESCENDANTS')
       and alvo.collaborator_id = p_collaborator_id
  );
$$;

revoke all on function public.f6_a22_p4_tem_escopo_colaborador(uuid, uuid, text, uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.f6_a22_p4_tem_escopo_colaborador(uuid, uuid, text, uuid, timestamptz)
  to service_role;

-- A RPC de criacao conserva o primitivo F5-07 e apenas acrescenta a prova de
-- que a posicao pretendida e existente, vaga e alcancavel pelo ator.
create or replace function public.colaborador_criar_no_escopo(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_operation_id uuid,
  p_position_id uuid,
  p_full_name text,
  p_email text,
  p_matricula text,
  p_admission_date date,
  p_status_inicial text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_position_id is null
     or not exists (
       select 1 from public.organizational_positions p
        where p.id = p_position_id and p.organization_id = p_organization_id
          and p.valid_from <= now() and (p.valid_to is null or p.valid_to > now()))
  then
    raise exception 'F6_A22_NOT_FOUND: posicao inexistente ou de outro tenant';
  end if;

  if exists (
    select 1 from public.occupations o
     where o.organization_id = p_organization_id
       and o.organizational_position_id = p_position_id
       and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
  ) then
    raise exception 'F6_A22_CONFLICT: posicao nao esta vaga';
  end if;

  if not exists (
    with recursive ator_posicao as (
      select o.organizational_position_id as position_id
        from public.resolver_collaborador_vinculado(
          p_actor_user_profile_id, p_organization_id) v
        join public.occupations o on o.collaborator_id = v.collaborator_id
         and o.organization_id = p_organization_id
         and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
    ),
    alcances as (
      select ap.position_id as root_position_id, ap.position_id as position_id, 0 as depth
        from ator_posicao ap
      union all
      select a.root_position_id, rl.subordinate_position_id, a.depth + 1
        from alcances a
        join public.position_reporting_lines rl
          on rl.organization_id = p_organization_id
         and rl.manager_position_id = a.position_id
         and rl.valid_from <= now() and (rl.valid_to is null or rl.valid_to > now())
       where a.depth < 100
    )
    select 1
      from public.resolver_capabilities_escopos_efetivas(
        p_actor_user_profile_id, p_organization_id) g
      join alcances a on a.position_id = p_position_id
     where g.capability_code = 'collaborator.create'
       and ((g.scope_type = 'DIRECT_REPORTS' and a.depth = 1)
         or (g.scope_type = 'DESCENDANTS' and a.depth > 0))
  ) then
    raise exception 'F6_A22_FORBIDDEN: posicao fora do escopo autorizado';
  end if;

  v_id := public.colaborador_criar(
    p_organization_id, p_actor_user_profile_id, p_operation_id,
    p_full_name, p_email, p_matricula, p_admission_date, p_status_inicial);
  return v_id;
end;
$$;

revoke all on function public.colaborador_criar_no_escopo(uuid, uuid, uuid, uuid, text, text, text, date, text)
  from public, anon, authenticated;
grant execute on function public.colaborador_criar_no_escopo(uuid, uuid, uuid, uuid, text, text, text, date, text)
  to service_role;

-- Minha equipe: a mesma projecao soberana do #327, agora limitada ao alcance
-- estrutural quando o ator nao e' um administrador estrutural.
alter function public.colaborador_visao_listar(uuid, uuid, timestamptz, jsonb)
  rename to colaborador_visao_listar_admin;

create or replace function public.colaborador_visao_listar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_data timestamptz,
  p_filtros jsonb
)
returns table (
  collaborator_id uuid, matricula text, full_name text, email text, status text,
  admission_date date, unit_id uuid, unit_name text, job_role_code text,
  job_role_name text, seniority_name text, manager_collaborator_id uuid,
  manager_full_name text, version integer
)
language sql stable security invoker set search_path = public
as $$
  select l.*
    from public.colaborador_visao_listar_admin(
      p_organization_id, p_actor_user_profile_id, p_data, p_filtros) l
   where exists (
     select 1 from public.resolver_capabilities_efetivas(
       p_actor_user_profile_id, p_organization_id) c
      where c.capability_code = 'org.structure.manage'
   )
   or public.f6_a22_p4_tem_escopo_colaborador(
        p_actor_user_profile_id, p_organization_id, 'collaborator.read',
        l.collaborator_id, coalesce(p_data, now()))
$$;

revoke all on function public.colaborador_visao_listar(uuid, uuid, timestamptz, jsonb)
  from public, anon, authenticated;
grant execute on function public.colaborador_visao_listar(uuid, uuid, timestamptz, jsonb)
  to service_role;
