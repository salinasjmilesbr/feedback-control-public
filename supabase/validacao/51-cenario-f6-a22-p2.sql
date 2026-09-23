-- F6-A22 P2 (#338): responsabilidade sintética sobre a posição ocupada pelo ator.
-- Pré-requisito: 48-cenario-f6-a21-p2.sql.
\set ON_ERROR_STOP on
insert into public.organizational_position_responsibilities
  (id, organization_id, position_id, responsibility_code, valid_from, created_by)
values ('f6a22000-0000-4000-8000-000000000901',
        'f6a22000-0000-4000-8000-0000000000a1',
        'f6a22000-0000-4000-8000-000000000d01',
        'PEOPLE_MANAGEMENT', '2026-01-01T00:00:00Z',
        'f6a22000-0000-4000-8000-000000000001');
