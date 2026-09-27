-- F6 / Issue #379 — bundle funcional genérico de Gestão de equipe.
-- Aditiva e idempotente: reutiliza roles, capabilities, assignments e scopes
-- soberanos existentes. Não concede autoridade administrativa.

do $$
declare
  v_role uuid;
  v_cap uuid;
  v_code text;
  v_expected text[] := array[
    'collaborator.read',
    'cycle.read',
    'evaluation.read',
    'goal.read',
    'goal.write',
    'observation.read',
    'observation.create',
    'observation.edit',
    'observation.delete',
    'report.read'
  ];
  v_actual text[];
begin
  select id into v_role
    from public.access_roles
   where name = 'gestao_equipe'
     and is_system = true
     and organization_id is null
     and status = 'active';

  if v_role is null then
    insert into public.access_roles (name, status, is_system, organization_id)
    values ('gestao_equipe', 'active', true, null)
    returning id into v_role;
  end if;

  foreach v_code in array v_expected loop
    select id into v_cap
      from public.capabilities
     where code = v_code
       and status = 'active'
       and deprecated = false
       and grantable_via_role = true;
    if v_cap is null then
      raise exception
        'F6_379_BUNDLE: capability % ausente, inativa, depreciada ou nao concedivel', v_code;
    end if;

    insert into public.access_role_capabilities (access_role_id, capability_id)
    values (v_role, v_cap)
    on conflict (access_role_id, capability_id) do nothing;
  end loop;

  select array_agg(c.code order by c.code)
    into v_actual
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where rc.access_role_id = v_role;

  if v_actual is distinct from (select array_agg(x order by x) from unnest(v_expected) as t(x)) then
    raise exception
      'F6_379_BUNDLE: bundle gestao_equipe deve conter exatamente as capabilities do contrato; atual=%',
      coalesce(v_actual::text, '{}');
  end if;

  if exists (
    select 1
      from public.access_role_capabilities rc
      join public.capabilities c on c.id = rc.capability_id
     where rc.access_role_id = v_role
       and c.code in (
         'access_role.manage', 'membership.manage', 'cycle.manage',
         'org.structure.manage', 'org.catalog.manage', 'settings.manage'
       )
  ) then
    raise exception 'F6_379_BUNDLE: gestao_equipe nao pode conter capability administrativa';
  end if;

  if exists (
    select 1
      from public.access_roles
     where id = v_role
       and (is_system is distinct from true or organization_id is not null
            or status <> 'active')
  ) then
    raise exception 'F6_379_BUNDLE: role gestao_equipe deve ser sistema ativa e global';
  end if;

  raise notice 'F6_379: bundle gestao_equipe instalado com 10 capabilities exatas; scope permanece em access_role_assignment_scopes';
end
$$;
