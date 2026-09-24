-- F6-A23 / Issue #353: expor a identidade funcional das posições nas leituras.
-- A view-base é apenas transitória nesta migration; o schema final mantém
-- somente as views canônicas e a semântica autorizativa já existente.

do $rewrite$
declare
  v_def text;
begin
  alter view public.estrutura_administrativa rename to estrutura_administrativa_f6_a23_base;
  select pg_get_viewdef('public.estrutura_administrativa_f6_a23_base'::regclass, true) into v_def;
  v_def := regexp_replace(v_def,
    'organizational_positions\.id,\s+organizational_positions\.unit_id',
    'organizational_positions.id, organizational_positions.name, organizational_positions.unit_id');
  if position('organizational_positions.name' in v_def) = 0 then
    raise exception 'F6_A23: formato inesperado da projeção administrativa';
  end if;
  drop view public.estrutura_administrativa_f6_a23_base cascade;
  execute 'create or replace view public.estrutura_administrativa as ' || v_def;

  alter view public.estrutura_pessoal rename to estrutura_pessoal_f6_a23_base;
  select pg_get_viewdef('public.estrutura_pessoal_f6_a23_base'::regclass, true) into v_def;
  v_def := regexp_replace(v_def,
    'p\.id,\s+p\.organization_id,\s+p\.unit_id',
    'p.id, p.organization_id, p.name, p.unit_id');
  v_def := regexp_replace(v_def,
    'vp\.id,\s+vp\.unit_id',
    'vp.id, vp.name, vp.unit_id');
  if position('p.name' in v_def) = 0 or position('vp.name' in v_def) = 0 then
    raise exception 'F6_A23: formato inesperado da projeção pessoal';
  end if;
  drop view public.estrutura_pessoal_f6_a23_base cascade;
  execute 'create or replace view public.estrutura_pessoal as ' || v_def;
end;
$rewrite$;

comment on view public.estrutura_administrativa is
  'F6-A23 (#353): fotografia estrutural administrativa com identidade funcional da posicao.';
comment on view public.estrutura_pessoal is
  'F6-A23 (#353): subgrafo estrutural vigente com identidade funcional da posicao.';

revoke all on public.estrutura_administrativa from public, anon, authenticated;
revoke all on public.estrutura_pessoal from public, anon, authenticated;
grant select on public.estrutura_administrativa to authenticated;
grant select on public.estrutura_pessoal to authenticated;

do $guard$
declare
  v_def_admin text;
  v_def_pessoal text;
begin
  select pg_get_viewdef('public.estrutura_administrativa'::regclass, true) into v_def_admin;
  select pg_get_viewdef('public.estrutura_pessoal'::regclass, true) into v_def_pessoal;

  if position('organizational_positions.name' in v_def_admin) = 0 then
    raise exception 'F6_A23: estrutura_administrativa nao projeta posicoes.name';
  end if;
  if position('p.name' in v_def_pessoal) = 0
     or position('vp.name' in v_def_pessoal) = 0 then
    raise exception 'F6_A23: estrutura_pessoal nao projeta posicoes.name';
  end if;
  if has_table_privilege('anon', 'public.estrutura_administrativa', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_pessoal', 'SELECT') then
    raise exception 'F6_A23: anon recebeu SELECT indevido';
  end if;
  if not has_table_privilege('authenticated', 'public.estrutura_administrativa', 'SELECT')
     or not has_table_privilege('authenticated', 'public.estrutura_pessoal', 'SELECT') then
    raise exception 'F6_A23: authenticated sem SELECT nas views canonicas';
  end if;
  if exists (
    select 1
      from public.estrutura_administrativa v,
           jsonb_array_elements(v.posicoes) e
     where not (e.value ? 'name')
  ) then
    raise exception 'F6_A23: estrutura_administrativa retornou posicao sem name';
  end if;
  if exists (
    select 1
      from public.estrutura_pessoal v,
           jsonb_array_elements(v.posicoes) e
     where not (e.value ? 'name')
  ) then
    raise exception 'F6_A23: estrutura_pessoal retornou posicao sem name';
  end if;
  raise notice '[PASS] F6-A23: ambas as projecoes soberanas expoem posicoes.name; grants e isolamento preservados';
end;
$guard$;
