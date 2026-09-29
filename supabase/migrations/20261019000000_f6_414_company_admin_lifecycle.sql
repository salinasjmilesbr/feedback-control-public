-- F6 / Issue #414 — ciclo de vida soberano dos Admins da Empresa.
-- A migration é aditiva: não cria role/capability/scope e não altera RLS.

create table if not exists public.company_admin_operations (
  id uuid not null default gen_random_uuid(),
  operation_id uuid not null,
  organization_id uuid not null,
  action text not null,
  target_user_profile_id uuid not null,
  target_membership_id uuid,
  actor_user_profile_id uuid not null,
  payload_hash text not null,
  result_membership_id uuid,
  created_at timestamptz not null default now(),
  constraint pk_company_admin_operations primary key (id),
  constraint uq_company_admin_operations_operation unique (organization_id, operation_id),
  constraint ck_company_admin_operations_action check (action in ('INVITE_GRANT','REVOKE','REACTIVATE')),
  constraint ck_company_admin_operations_hash check (payload_hash ~ '^[0-9a-f]{64}$')
);

alter table public.company_admin_operations enable row level security;
revoke all on public.company_admin_operations from public, anon, authenticated, service_role;
grant select, insert on public.company_admin_operations to service_role;

create or replace function public.company_admin_lock_organization(p_organization_id uuid)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if p_organization_id is null then
    raise exception 'F6_414_INVALID_ORGANIZATION' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtext('company_admins:' || p_organization_id::text));
end;
$$;

create or replace function public.company_admin_count_active(p_organization_id uuid)
returns integer language sql stable security invoker set search_path = public as $$
  select count(*)::integer
    from public.user_organization_memberships m
    join public.user_profiles p on p.id = m.user_profile_id and p.status = 'active'
    join public.membership_access_role_assignments a
      on a.membership_id = m.id and a.organization_id = m.organization_id and a.status = 'active'
    join public.access_roles r
      on r.id = a.access_role_id and r.is_system = true and r.name = 'admin' and r.status = 'active'
   where m.organization_id = p_organization_id and m.status = 'active';
$$;

create or replace function public.company_admin_validate_cardinality(p_organization_id uuid)
returns void language plpgsql security invoker set search_path = public as $$
declare v_count integer;
begin
  perform public.company_admin_lock_organization(p_organization_id);
  v_count := public.company_admin_count_active(p_organization_id);
  if v_count < 1 then
    raise exception 'F6_414_LAST_ADMIN: a organizacao deve manter ao menos um Admin ativo' using errcode = 'P0001';
  end if;
  if v_count > 4 then
    raise exception 'F6_414_ADMIN_LIMIT: a organizacao suporta no maximo quatro Admins ativos' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.company_admin_guard_deferred()
returns trigger language plpgsql security invoker set search_path = public as $$
declare v_org uuid; v_rec record;
begin
  if tg_table_name = 'organizations' then
    v_org := new.id;
    perform public.company_admin_validate_cardinality(v_org);
  elsif tg_table_name = 'user_profiles' then
    for v_rec in select organization_id from public.user_organization_memberships where user_profile_id = coalesce(new.id, old.id) loop
      perform public.company_admin_validate_cardinality(v_rec.organization_id);
    end loop;
  elsif tg_table_name = 'user_organization_memberships' then
    perform public.company_admin_validate_cardinality(coalesce(new.organization_id, old.organization_id));
  elsif tg_table_name = 'membership_access_role_assignments' then
    perform public.company_admin_validate_cardinality(coalesce(new.organization_id, old.organization_id));
  end if;
  return null;
end;
$$;

create constraint trigger trg_company_admin_org_cardinality
after insert on public.organizations deferrable initially deferred for each row execute function public.company_admin_guard_deferred();
create constraint trigger trg_company_admin_profile_cardinality
after update on public.user_profiles deferrable initially deferred for each row execute function public.company_admin_guard_deferred();
create constraint trigger trg_company_admin_membership_cardinality
after insert or update on public.user_organization_memberships deferrable initially deferred for each row execute function public.company_admin_guard_deferred();
create constraint trigger trg_company_admin_assignment_cardinality
after insert or update on public.membership_access_role_assignments deferrable initially deferred for each row execute function public.company_admin_guard_deferred();

create or replace function public.usuario_eh_administrador(p_user_profile_id uuid, p_organization_id uuid)
returns boolean language sql stable security invoker set search_path = public as $$
  select exists (
    select 1 from public.user_profiles p
    join public.user_organization_memberships m on m.user_profile_id = p.id and m.status = 'active'
    join public.membership_access_role_assignments a on a.membership_id = m.id and a.status = 'active'
    join public.access_roles r on r.id = a.access_role_id and r.is_system = true and r.name = 'admin' and r.status = 'active'
    where p.id = p_user_profile_id and p.status = 'active' and m.organization_id = p_organization_id
  );
$$;

create or replace function public.company_admin_invite_grant(
  p_operation_id uuid, p_organization_id uuid, p_target_user_profile_id uuid, p_actor_user_profile_id uuid, p_payload_hash text
) returns uuid language plpgsql security invoker set search_path = public as $$
declare v_membership uuid; v_role uuid; v_existing public.company_admin_operations%rowtype;
begin
  perform public.company_admin_lock_organization(p_organization_id);
  select * into v_existing from public.company_admin_operations where organization_id = p_organization_id and operation_id = p_operation_id;
  if found then
    if v_existing.payload_hash <> p_payload_hash then raise exception 'F6_414_OPERATION_CONFLICT' using errcode = 'P0001'; end if;
    return coalesce(v_existing.result_membership_id, v_existing.target_membership_id);
  end if;
  if not public.usuario_eh_administrador(p_actor_user_profile_id, p_organization_id) then raise exception 'F6_414_FORBIDDEN' using errcode = '42501'; end if;
  if public.company_admin_count_active(p_organization_id) >= 4 then raise exception 'F6_414_ADMIN_LIMIT' using errcode = 'P0001'; end if;
  select id into v_role from public.access_roles where is_system and name = 'admin' and status = 'active';
  if v_role is null then raise exception 'F6_414_ADMIN_ROLE_MISSING' using errcode = 'P0001'; end if;
  perform public.criar_perfil_membership(p_target_user_profile_id, p_organization_id, true);
  select id into v_membership from public.user_organization_memberships where user_profile_id = p_target_user_profile_id and organization_id = p_organization_id and status = 'active';
  perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);
  insert into public.company_admin_operations(operation_id, organization_id, action, target_user_profile_id, target_membership_id, actor_user_profile_id, payload_hash, result_membership_id)
  values (p_operation_id, p_organization_id, 'INVITE_GRANT', p_target_user_profile_id, v_membership, p_actor_user_profile_id, p_payload_hash, v_membership);
  insert into public.privilege_mutation_audit(organization_id, membership_id, access_role_id, action, actor_user_profile_id) values (p_organization_id, v_membership, v_role, 'grant', p_actor_user_profile_id);
  perform public.company_admin_validate_cardinality(p_organization_id);
  return v_membership;
end;
$$;

create or replace function public.company_admin_revoke(p_operation_id uuid, p_organization_id uuid, p_membership_id uuid, p_actor_user_profile_id uuid, p_payload_hash text)
returns void language plpgsql security invoker set search_path = public as $$
declare v_role uuid; v_existing public.company_admin_operations%rowtype; v_count integer;
begin
  perform public.company_admin_lock_organization(p_organization_id);
  select * into v_existing from public.company_admin_operations where organization_id = p_organization_id and operation_id = p_operation_id;
  if found then if v_existing.payload_hash <> p_payload_hash then raise exception 'F6_414_OPERATION_CONFLICT' using errcode = 'P0001'; end if; return; end if;
  if not public.usuario_eh_administrador(p_actor_user_profile_id, p_organization_id) then raise exception 'F6_414_FORBIDDEN' using errcode = '42501'; end if;
  v_count := public.company_admin_count_active(p_organization_id);
  if v_count <= 1 then raise exception 'F6_414_LAST_ADMIN' using errcode = 'P0001'; end if;
  select a.access_role_id into v_role from public.membership_access_role_assignments a join public.user_organization_memberships m on m.id = a.membership_id join public.access_roles r on r.id = a.access_role_id where a.membership_id = p_membership_id and a.organization_id = p_organization_id and m.organization_id = p_organization_id and a.status = 'active' and m.status = 'active' and r.is_system = true and r.name = 'admin' and r.status = 'active';
  if v_role is null then raise exception 'F6_414_NOT_ADMIN' using errcode = 'P0002'; end if;
  perform public.revogar_acesso_role(p_membership_id, v_role, p_actor_user_profile_id);
  insert into public.company_admin_operations(operation_id, organization_id, action, target_user_profile_id, target_membership_id, actor_user_profile_id, payload_hash) select p_operation_id, p_organization_id, 'REVOKE', m.user_profile_id, m.id, p_actor_user_profile_id, p_payload_hash from public.user_organization_memberships m where m.id = p_membership_id;
  insert into public.privilege_mutation_audit(organization_id, membership_id, access_role_id, action, actor_user_profile_id) values (p_organization_id, p_membership_id, v_role, 'revoke', p_actor_user_profile_id);
end;
$$;

create or replace function public.company_admin_reactivate(p_operation_id uuid, p_organization_id uuid, p_membership_id uuid, p_actor_user_profile_id uuid, p_payload_hash text)
returns void language plpgsql security invoker set search_path = public as $$
declare v_role uuid; v_existing public.company_admin_operations%rowtype; v_count integer;
begin
  perform public.company_admin_lock_organization(p_organization_id);
  select * into v_existing from public.company_admin_operations where organization_id = p_organization_id and operation_id = p_operation_id;
  if found then if v_existing.payload_hash <> p_payload_hash then raise exception 'F6_414_OPERATION_CONFLICT' using errcode = 'P0001'; end if; return; end if;
  if not public.usuario_eh_administrador(p_actor_user_profile_id, p_organization_id) then raise exception 'F6_414_FORBIDDEN' using errcode = '42501'; end if;
  if public.company_admin_count_active(p_organization_id) >= 4 then raise exception 'F6_414_ADMIN_LIMIT' using errcode = 'P0001'; end if;
  select id into v_role from public.access_roles where is_system and name = 'admin' and status = 'active';
  if v_role is null then raise exception 'F6_414_ADMIN_ROLE_MISSING' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.user_organization_memberships where id = p_membership_id and organization_id = p_organization_id) then raise exception 'F6_414_NOT_ADMIN' using errcode = 'P0002'; end if;
  perform public.conceder_acesso_role(p_membership_id, v_role, p_actor_user_profile_id);
  insert into public.company_admin_operations(operation_id, organization_id, action, target_user_profile_id, target_membership_id, actor_user_profile_id, payload_hash) select p_operation_id, p_organization_id, 'REACTIVATE', m.user_profile_id, m.id, p_actor_user_profile_id, p_payload_hash from public.user_organization_memberships m where m.id = p_membership_id;
  insert into public.privilege_mutation_audit(organization_id, membership_id, access_role_id, action, actor_user_profile_id) values (p_organization_id, p_membership_id, v_role, 'grant', p_actor_user_profile_id);
end;
$$;

-- Os RPCs legados continuam sendo a porta genérica para roles funcionais,
-- mas nunca podem mutar a role soberana admin. O bootstrap e as operações
-- company_admin_* usam os primitivos internos e permanecem compatíveis.
create or replace function public.conceder_acesso_role_rpc(
  p_membership_id uuid, p_access_role_id uuid, p_actor_user_profile_id uuid
) returns void language plpgsql security invoker set search_path = public as $$
declare v_org uuid; v_name text; v_is_system boolean;
begin
  select organization_id into v_org from public.user_organization_memberships where id = p_membership_id;
  if v_org is null or not public.usuario_eh_administrador(p_actor_user_profile_id, v_org) then
    raise exception 'F5_04_NOT_AUTHORIZED' using errcode = '42501';
  end if;
  select name, is_system into v_name, v_is_system from public.access_roles where id = p_access_role_id and status = 'active';
  if v_is_system and v_name = 'admin' then raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode = '42501'; end if;
  perform public.conceder_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);
end;
$$;

create or replace function public.revogar_acesso_role_rpc(
  p_membership_id uuid, p_access_role_id uuid, p_actor_user_profile_id uuid
) returns void language plpgsql security invoker set search_path = public as $$
declare v_org uuid; v_name text; v_is_system boolean;
begin
  select organization_id into v_org from public.user_organization_memberships where id = p_membership_id;
  if v_org is null or not public.usuario_eh_administrador(p_actor_user_profile_id, v_org) then
    raise exception 'F5_04_NOT_AUTHORIZED' using errcode = '42501';
  end if;
  select name, is_system into v_name, v_is_system from public.access_roles where id = p_access_role_id;
  if v_is_system and v_name = 'admin' then raise exception 'F6_414_ADMIN_USE_COMPANY_OPERATION' using errcode = '42501'; end if;
  perform public.revogar_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);
end;
$$;

revoke all on function public.conceder_acesso_role_rpc(uuid,uuid,uuid), public.revogar_acesso_role_rpc(uuid,uuid,uuid) from public, anon, authenticated;
grant execute on function public.conceder_acesso_role_rpc(uuid,uuid,uuid), public.revogar_acesso_role_rpc(uuid,uuid,uuid) to service_role;

revoke all on function public.company_admin_lock_organization(uuid), public.company_admin_count_active(uuid), public.company_admin_validate_cardinality(uuid), public.company_admin_invite_grant(uuid,uuid,uuid,uuid,text), public.company_admin_revoke(uuid,uuid,uuid,uuid,text), public.company_admin_reactivate(uuid,uuid,uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.company_admin_lock_organization(uuid), public.company_admin_count_active(uuid), public.company_admin_validate_cardinality(uuid), public.company_admin_invite_grant(uuid,uuid,uuid,uuid,text), public.company_admin_revoke(uuid,uuid,uuid,uuid,text), public.company_admin_reactivate(uuid,uuid,uuid,uuid,text) to service_role;

do $$ begin
  if not exists (select 1 from public.access_roles where is_system and name = 'admin' and status = 'active') then raise exception 'F6_414: role admin ausente'; end if;
end $$;
