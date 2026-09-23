-- F6-A22 P4 — guards direcionados da superfície Minha equipe.
-- A prova é estrutural e fail-closed; os cenários vivos continuam nos guards
-- P2/P3 e no resolver soberano já exercitado pelo banco local.
do $$
declare
  v_def text;
begin
  if not has_function_privilege(
    'service_role',
    'public.f6_a22_p4_tem_escopo_colaborador(uuid,uuid,text,uuid,timestamptz)',
    'EXECUTE')
     or has_function_privilege(
       'authenticated',
       'public.f6_a22_p4_tem_escopo_colaborador(uuid,uuid,text,uuid,timestamptz)',
       'EXECUTE')
  then
    raise exception '[FAIL] P4: helper de escopo nao esta fechado ao service_role';
  end if;

  select pg_get_functiondef(
    'public.f6_a22_p4_tem_escopo_colaborador(uuid,uuid,text,uuid,timestamptz)'::regprocedure)
    into v_def;
  if position('resolver_capabilities_escopos_efetivas' in v_def) = 0
     or position('DIRECT_REPORTS' in v_def) = 0
     or position('DESCENDANTS' in v_def) = 0
     or position('collaborator.read' in v_def) = 0
  then
    raise exception '[FAIL] P4: helper nao deriva capability e alcance dos resolvers soberanos';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)',
    'EXECUTE')
     or has_function_privilege(
       'authenticated',
       'public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)',
       'EXECUTE')
  then
    raise exception '[FAIL] P4: RPC de criacao limitada nao esta fechada';
  end if;

  select pg_get_functiondef(
    'public.colaborador_criar_no_escopo(uuid,uuid,uuid,uuid,text,text,text,date,text)'::regprocedure)
    into v_def;
  if position('position_reporting_lines' in v_def) = 0
     or position('F6_A22_FORBIDDEN' in v_def) = 0
     or position('F6_A22_CONFLICT' in v_def) = 0
  then
    raise exception '[FAIL] P4: criacao nao prova escopo, vacancia e negacao';
  end if;

  raise notice '[PASS] F6-A22 P4: Minha equipe usa capability+DIRECT_REPORTS/DESCENDANTS; criacao exige posicao vigente vaga e RPC fechada';
end $$;
