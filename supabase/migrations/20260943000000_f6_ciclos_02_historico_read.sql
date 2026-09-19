-- F6-CICLOS-02 (#300): leitura soberana da trilha já existente de ciclos.
-- A tabela permanece sem SELECT para clientes; somente a Edge service_role
-- executa esta RPC depois de autenticar, validar tenant e aplicar cycle.read.

create or replace function public.ciclo_historico_listar(
  p_cycle_id uuid,
  p_organization_id uuid,
  p_actor_user_profile_id uuid
)
returns table (
  id uuid,
  organization_id uuid,
  cycle_id uuid,
  event_type text,
  effective_date timestamptz,
  reason text,
  actor_user_profile_id uuid,
  created_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if not public.ciclo_ator_valido(
    p_actor_user_profile_id, p_organization_id, 'cycle.read'
  ) then
    raise exception 'F5_09_FORBIDDEN: ator sem cycle.read no tenant';
  end if;

  if not exists (
    select 1
      from public.evaluation_cycles c
     where c.id = p_cycle_id
       and c.organization_id = p_organization_id
  ) then
    raise exception 'F5_09_NOT_FOUND: ciclo inexistente no tenant';
  end if;

  return query
    select e.id, e.organization_id, e.cycle_id, e.event_type,
           e.effective_date, e.reason, e.actor_user_profile_id, e.created_at
      from public.cycle_events e
     where e.organization_id = p_organization_id
       and e.cycle_id = p_cycle_id
     order by e.effective_date asc, e.created_at asc, e.id asc;
end;
$$;

comment on function public.ciclo_historico_listar(uuid, uuid, uuid) is
  'F6-CICLOS-02: leitura tenant-scoped e server-side da trilha append-only de ciclo. '
  'Revalida membership/perfil ativos e cycle.read; nunca exposta ao cliente por SELECT.';

revoke all on function public.ciclo_historico_listar(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.ciclo_historico_listar(uuid, uuid, uuid)
  to service_role;
