-- F6-A22 P5 / Issue #355: ORGANIZATION também autoriza criação administrativa.
-- DIRECT_REPORTS/DESCENDANTS permanecem limitados à árvore do ator.

create or replace function public.colaborador_criar_no_escopo(
  p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid,
  p_position_id uuid, p_full_name text, p_email text, p_matricula text,
  p_admission_date date, p_status_inicial text
) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_id uuid;
begin
  if p_position_id is null or not exists (
    select 1 from public.organizational_positions p
     where p.id = p_position_id and p.organization_id = p_organization_id
       and p.valid_from <= now() and (p.valid_to is null or p.valid_to > now())) then
    raise exception 'F6_A22_NOT_FOUND: posicao inexistente ou de outro tenant';
  end if;

  if exists (
    select 1 from public.occupations o
     where o.organization_id = p_organization_id
       and o.organizational_position_id = p_position_id
       and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())) then
    raise exception 'F6_A22_CONFLICT: posicao nao esta vaga';
  end if;

  if not exists (
    with recursive ator_posicao as (
      select o.organizational_position_id as position_id
        from public.resolver_collaborador_vinculado(p_actor_user_profile_id, p_organization_id) v
        join public.occupations o on o.collaborator_id = v.collaborator_id
         and o.organization_id = p_organization_id
         and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
    ), alcances as (
      select ap.position_id as root_position_id, ap.position_id, 0 as depth from ator_posicao ap
      union all
      select a.root_position_id, rl.subordinate_position_id, a.depth + 1
        from alcances a join public.position_reporting_lines rl
          on rl.organization_id = p_organization_id
         and rl.manager_position_id = a.position_id
         and rl.valid_from <= now() and (rl.valid_to is null or rl.valid_to > now())
       where a.depth < 100
    )
    select 1
      from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id, p_organization_id) g
      left join alcances a on a.position_id = p_position_id
     where g.capability_code = 'collaborator.create'
       and (g.scope_type = 'ORGANIZATION'
         or (g.scope_type = 'DIRECT_REPORTS' and a.depth = 1)
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

revoke all on function public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)
  from public, anon, authenticated;
grant execute on function public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)
  to service_role;

do $guard$
declare v_def text;
begin
  select pg_get_functiondef('public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)'::regprocedure)
    into v_def;
  if position('g.scope_type = ''ORGANIZATION''' in v_def) = 0
     or position('DIRECT_REPORTS' in v_def) = 0
     or position('DESCENDANTS' in v_def) = 0 then
    raise exception 'F6_A22_P5: allowlist de escopo incompleta';
  end if;
  if has_function_privilege('anon', 'public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)', 'EXECUTE') then
    raise exception 'F6_A22_P5: RPC exposta a cliente';
  end if;
end;
$guard$;
