-- ============================================================================
-- F6-A14 (Issue #286): scope do primeiro Admin no bootstrap
-- ----------------------------------------------------------------------------
-- A migration F6-A11 já foi aplicada e não é editada retroativamente.
-- Este gatilho cobre somente a janela GREENFIELD do bootstrap: assignment da
-- role de sistema `admin` em organização ainda sem colaboradores. Assim, a
-- nova organização materializa o scope ORGANIZATION antes da criação da
-- âncora F5-02, sem backfill de tenants existentes (D30).
-- ============================================================================

create or replace function public.f6_a14_materializar_scope_bootstrap_admin()
returns trigger
language plpgsql
security invoker
set search_path = public
as $fn$
begin
  if new.status = 'active'
     and exists (
       select 1
         from public.access_roles r
        where r.id = new.access_role_id
          and r.name = 'admin'
          and r.is_system = true
          and r.status = 'active'
     )
     and not exists (
       select 1
         from public.collaborators c
        where c.organization_id = new.organization_id
     )
  then
    insert into public.access_role_assignment_scopes (
      assignment_id, scope_type, status
    )
    values (new.id, 'ORGANIZATION', 'active')
    on conflict (assignment_id, scope_type) do nothing;
  end if;

  return new;
end;
$fn$;

drop trigger if exists trg_f6_a14_scope_bootstrap_admin
  on public.membership_access_role_assignments;

create trigger trg_f6_a14_scope_bootstrap_admin
after insert on public.membership_access_role_assignments
for each row
execute function public.f6_a14_materializar_scope_bootstrap_admin();

comment on function public.f6_a14_materializar_scope_bootstrap_admin() is
  'F6-A14: materializa ORGANIZATION somente para assignment admin ativa em '
  'tenant GREENFIELD sem colaboradores; nao faz backfill de tenants existentes.';

do $guarda$
begin
  if not exists (
    select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
     where t.tgname = 'trg_f6_a14_scope_bootstrap_admin'
       and c.relname = 'membership_access_role_assignments'
       and not t.tgisinternal
  ) then
    raise exception 'F6_A14: trigger do scope do bootstrap ausente';
  end if;
end;
$guarda$;
