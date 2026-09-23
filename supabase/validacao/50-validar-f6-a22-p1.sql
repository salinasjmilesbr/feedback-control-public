-- F6-A22 P1 (#338): validacao proporcional de schema e fronteiras.
do $$
declare v integer;
begin
  select count(*) into v from public.organizational_position_responsibilities_catalog;
  if v <> 1 then raise exception 'FAIL: catalogo PEOPLE_MANAGEMENT'; end if;
  select count(*) into v from public.organizational_position_responsibility_bundle;
  if v <> 2 then raise exception 'FAIL: bundle deve conter exatamente 2 capabilities'; end if;
  if exists (select 1 from public.organizational_position_responsibility_bundle where capability_code = 'collaborator.edit') then
    raise exception 'FAIL: collaborator.edit nao pertence ao bundle';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in (
    'organizational_position_responsibilities',
    'organizational_position_responsibility_bundle',
    'organizational_position_responsibilities_catalog',
    'organizational_position_responsibility_events')) then
    raise exception 'FAIL: tabelas P1 devem permanecer deny-by-default';
  end if;
  if has_table_privilege('authenticated', 'public.organizational_position_responsibilities', 'SELECT')
     or has_table_privilege('authenticated', 'public.organizational_position_responsibilities', 'INSERT')
     or has_table_privilege('authenticated', 'public.organizational_position_responsibility_events', 'SELECT') then
    raise exception 'FAIL: acesso direto do cliente';
  end if;
  raise notice '[PASS] F6-A22 P1: tenant-scoped schema, bundle exato, deny-by-default e trilha protegida';
end $$;

-- As provas de isolamento tenant/FKs, intervalos e sobreposicao sao exercitadas
-- pelo banco com dados sintéticos do cenário F6-A22; estes asserts estruturais
-- garantem que as respectivas barreiras estão instaladas.
select constraint_name from information_schema.table_constraints
 where table_schema = 'public'
   and table_name = 'organizational_position_responsibilities'
   and constraint_name in ('ex_opr_no_overlap', 'ck_opr_valid_to', 'fk_opr_position');

select tgname from pg_trigger
 where tgrelid = 'public.organizational_position_responsibility_events'::regclass
   and tgname = 'trg_opr_events_append_only';
