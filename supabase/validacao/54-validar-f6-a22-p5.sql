-- F6-A22 P5 / Issue #355: ORGANIZATION para criação administrativa.
\set ON_ERROR_STOP on
set local role service_role;

do $$
declare v_def text;
begin
  select pg_get_functiondef('public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)'::regprocedure)
    into v_def;
  if position('g.scope_type = ''ORGANIZATION''' in v_def) = 0 then
    raise exception '[FAIL] ORGANIZATION nao esta no gate server-side';
  end if;
  if position('g.scope_type = ''DIRECT_REPORTS''' in v_def) = 0
     or position('g.scope_type = ''DESCENDANTS''' in v_def) = 0 then
    raise exception '[FAIL] DIRECT_REPORTS/DESCENDANTS foram removidos';
  end if;
  if position('p.organization_id = p_organization_id' in v_def) = 0
     or position('posicao nao esta vaga' in v_def) = 0 then
    raise exception '[FAIL] tenant/vacancia nao permanecem na RPC';
  end if;
  raise notice '[PASS] RPC exige collaborator.create e preserva tenant, vacancia e os tres escopos';
end $$;

do $$
declare v_def text;
begin
  select pg_get_functiondef('public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)'::regprocedure)
    into v_def;
  if position('g.scope_type = ''DIRECT_REPORTS'' and a.depth = 1' in v_def) = 0
     or position('g.scope_type = ''DESCENDANTS'' and a.depth > 0' in v_def) = 0 then
    raise exception '[FAIL] DIRECT_REPORTS/DESCENDANTS foram alterados';
  end if;
  raise notice '[PASS] DIRECT_REPORTS/DESCENDANTS existentes permanecem efetivos';
end $$;

do $$
begin
  if has_function_privilege('anon','public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)','EXECUTE')
     or has_function_privilege('authenticated','public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)','EXECUTE') then
    raise exception '[FAIL] RPC de criação exposta a cliente';
  end if;
  raise notice '[PASS] RPC permanece server-side/service_role';
end $$;

reset role;

set local role service_role;

-- Provas comportamentais: todas as mutações ficam dentro de transações revertidas.
begin;
do $$
declare v_id uuid; v_pos uuid := 'f6a21000-0000-4000-8000-000000000d09';
begin
  insert into public.access_role_assignment_scopes
    (id, assignment_id, organization_id, scope_type, status, created_by)
  select 'f3550000-0000-4000-8000-000000000010', a.id, m.organization_id,
    'ORGANIZATION', 'active', m.user_profile_id
    from public.membership_access_role_assignments a
    join public.user_organization_memberships m on m.id = a.membership_id
    join public.access_roles r on r.id = a.access_role_id
   where m.user_profile_id = 'f6a21000-0000-4000-8000-000000000001'
     and m.organization_id = 'f6a21000-0000-4000-8000-0000000000a1'
     and r.name = 'admin';

  insert into public.organizational_positions
    (id,organization_id,unit_id,job_role_id,seniority_level_id,name,valid_from)
  values (v_pos,'f6a21000-0000-4000-8000-0000000000a1',
    'f6a21000-0000-4000-8000-000000000c01',
    'f6a21000-0000-4000-8000-000000000b01',
    'f6a21000-0000-4000-8000-000000000b11','P5 ORGANIZATION vaga','2026-01-01');
  v_id := public.colaborador_criar_no_escopo(
    'f6a21000-0000-4000-8000-0000000000a1',
    'f6a21000-0000-4000-8000-000000000001',
    'f3550000-0000-4000-8000-000000000001',v_pos,
    'Colaborador P5 Organization','p5-org@example.invalid','P5ORG001','2026-01-01','active');
  if not exists (select 1 from public.collaborators where id=v_id and organization_id='f6a21000-0000-4000-8000-0000000000a1') then
    raise exception '[FAIL] ORGANIZATION same-tenant nao persistiu o colaborador';
  end if;
  raise notice '[PASS] ORGANIZATION + posição vaga same-tenant = ALLOW';
end $$;
rollback;

begin;
do $$
begin
  begin
    perform public.colaborador_criar_no_escopo(
      'f6a21000-0000-4000-8000-0000000000a1',
      'f6a21000-0000-4000-8000-000000000001',
      'f3550000-0000-4000-8000-000000000002',
      'f6a21000-0000-4000-8000-000000000d05',
      'Cross Tenant P5','cross@example.invalid','P5CROSS001','2026-01-01','active');
    raise exception '[FAIL] ORGANIZATION cross-tenant foi aceito';
  exception when others then
    if sqlerrm not like 'F6_A22_NOT_FOUND%' then raise; end if;
    raise notice '[PASS] ORGANIZATION cross-tenant = DENY';
  end;
end $$;
rollback;

begin;
do $$
begin
  begin
    perform public.colaborador_criar_no_escopo(
      'f6a21000-0000-4000-8000-0000000000a1',
      'f6a21000-0000-4000-8000-000000000002',
      'f3550000-0000-4000-8000-000000000003',
      'f6a21000-0000-4000-8000-000000000d04',
      'Sem Cap P5','semcap@example.invalid','P5NOCAP001','2026-01-01','active');
    raise exception '[FAIL] ator sem collaborator.create foi aceito';
  exception when others then
    if sqlerrm not like 'F6_A22_FORBIDDEN%' then raise; end if;
    raise notice '[PASS] sem collaborator.create = DENY';
  end;
end $$;
rollback;

do $$
declare v_left integer;
begin
  select count(*) into v_left from public.collaborators where matricula is null and full_name like 'P5 %';
  if v_left <> 0 then raise exception '[FAIL] teste deixou persistencia parcial (%)', v_left; end if;
  raise notice '[PASS] falhas nao deixaram persistencia parcial';
end $$;

reset role;
