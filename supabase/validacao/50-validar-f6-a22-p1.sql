-- F6-A22 P1 (#338): provas reais dos invariantes.
-- Pré-requisito: 47-cenario-f6-a21-p1.sql (dados sintéticos Alfa/Beta).
-- O bloco termina com ROLLBACK e não deixa dados de validação persistidos.
\set ON_ERROR_STOP on
begin;

insert into public.organizational_position_responsibilities
  (id, organization_id, position_id, responsibility_code, valid_from, valid_to, created_by)
values ('f6a22000-0000-4000-8000-000000000001', 'f6a21000-0000-4000-8000-0000000000a1',
        'f6a21000-0000-4000-8000-000000000d01', 'PEOPLE_MANAGEMENT',
        '2026-02-01T00:00:00Z', '2026-06-01T00:00:00Z',
        'f6a21000-0000-4000-8000-000000000001');

do $$ begin
  begin
    insert into public.organizational_position_responsibilities
      (organization_id, position_id, responsibility_code, valid_from, created_by)
    values ('f6a21000-0000-4000-8000-0000000000a2', 'f6a21000-0000-4000-8000-000000000d01',
            'PEOPLE_MANAGEMENT', '2026-07-01T00:00:00Z', 'f6a21000-0000-4000-8000-000000000004');
    raise exception '[FAIL] tenant FK aceitou posição cross-tenant';
  exception when foreign_key_violation then raise notice '[PASS] tenant FK cross-tenant'; end;
end $$;

do $$ begin
  begin
    insert into public.organizational_position_responsibilities
      (organization_id, position_id, responsibility_code, valid_from, valid_to, created_by)
    values ('f6a21000-0000-4000-8000-0000000000a1', 'f6a21000-0000-4000-8000-000000000d02',
            'PEOPLE_MANAGEMENT', '2026-08-01T00:00:00Z', '2026-08-01T00:00:00Z',
            'f6a21000-0000-4000-8000-000000000001');
    raise exception '[FAIL] valid_to <= valid_from foi aceito';
  exception when check_violation then raise notice '[PASS] intervalo inválido'; end;
end $$;

do $$ begin
  begin
    insert into public.organizational_position_responsibilities
      (organization_id, position_id, responsibility_code, valid_from, valid_to, created_by)
    values ('f6a21000-0000-4000-8000-0000000000a1', 'f6a21000-0000-4000-8000-000000000d01',
            'PEOPLE_MANAGEMENT', '2026-05-01T00:00:00Z', '2026-07-01T00:00:00Z',
            'f6a21000-0000-4000-8000-000000000001');
    raise exception '[FAIL] sobreposição foi aceita';
  exception when exclusion_violation then raise notice '[PASS] sobreposição temporal'; end;
end $$;

do $$ begin
  begin
    delete from public.organizational_position_responsibilities
     where id = 'f6a22000-0000-4000-8000-000000000001';
    raise exception '[FAIL] DELETE físico foi aceito';
  exception when raise_exception then
    if sqlerrm not like 'F6-A22:%append-only%' then raise; end if;
    raise notice '[PASS] DELETE físico rejeitado';
  end;
end $$;

do $$ declare v text[]; begin
  select array_agg(capability_code order by capability_code) into v
    from public.organizational_position_responsibility_bundle
   where responsibility_code = 'PEOPLE_MANAGEMENT';
  if v is distinct from array['collaborator.create','collaborator.read']::text[] then
    raise exception '[FAIL] bundle divergente: %', v;
  end if;
  if exists (select 1 from public.organizational_position_responsibility_bundle
              where capability_code = 'collaborator.edit') then
    raise exception '[FAIL] collaborator.edit presente';
  end if;
  raise notice '[PASS] bundle exato; collaborator.edit ausente';
end $$;

do $$ begin
  begin
    set local role authenticated; perform 1 from public.organizational_position_responsibilities;
    raise exception '[FAIL] authenticated leu diretamente';
  exception when insufficient_privilege then raise notice '[PASS] authenticated sem SELECT direto'; end;
  reset role;
  begin
    set local role anon; perform 1 from public.organizational_position_responsibilities;
    raise exception '[FAIL] anon leu diretamente';
  exception when insufficient_privilege then raise notice '[PASS] anon sem SELECT direto'; end;
  reset role;
end $$;

rollback;
select '[PASS] F6-A22 P1: provas executadas com rollback' as resultado;
