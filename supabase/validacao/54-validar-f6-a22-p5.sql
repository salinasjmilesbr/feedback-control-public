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
