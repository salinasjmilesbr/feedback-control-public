-- ============================================================================
-- F3-07 (Issue #84): cenário sintético de validação — resolução organizacional
-- por data (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-07.sql:
--
--   - uma organização sintética (Alfa F3-07) com catálogos, unidades,
--     colaboradores (núcleo + status), posições e reporting lines formando uma
--     árvore que exercita: gerência sem Coordenador, posição superior VAGA com
--     substituto operacional temporário, múltiplas occupations, licença sem
--     excluir titular, cadeia com ancestrais vagos;
--   - occupations e temporary responsibilities para distinguir titular e
--     substituto na resolução.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-07.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo f9).
--   - Apenas dados sintéticos; nenhum nome/estrutura/dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.temporary_responsibilities
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.occupations
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.collaborator_status_periods
where collaborator_id in (
  'f9b00000-0000-0000-0000-0000000000c1',
  'f9b00000-0000-0000-0000-0000000000c2',
  'f9b00000-0000-0000-0000-0000000000c3',
  'f9b00000-0000-0000-0000-0000000000c4',
  'f9b00000-0000-0000-0000-0000000000c5',
  'f9b00000-0000-0000-0000-0000000000c6',
  'f9b00000-0000-0000-0000-0000000000c7'
);

delete from public.position_reporting_lines
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_positions
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.organizational_units
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.collaborators
where id in (
  'f9b00000-0000-0000-0000-0000000000c1',
  'f9b00000-0000-0000-0000-0000000000c2',
  'f9b00000-0000-0000-0000-0000000000c3',
  'f9b00000-0000-0000-0000-0000000000c4',
  'f9b00000-0000-0000-0000-0000000000c5',
  'f9b00000-0000-0000-0000-0000000000c6',
  'f9b00000-0000-0000-0000-0000000000c7'
);

delete from public.job_roles
where organization_id = 'f9a00000-0000-0000-0000-0000000000a1';

delete from public.organizations
where id = 'f9a00000-0000-0000-0000-0000000000a1';

-- ----------------------------------------------------------------------------
-- Organização, catálogos e unidades
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f9a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-07 Alfa');

insert into public.job_roles (id, organization_id, name) values
  ('f9d00000-0000-0000-0000-000000000001', 'f9a00000-0000-0000-0000-0000000000a1', 'Gerente'),
  ('f9d00000-0000-0000-0000-000000000002', 'f9a00000-0000-0000-0000-0000000000a1', 'Coordenador'),
  ('f9d00000-0000-0000-0000-000000000003', 'f9a00000-0000-0000-0000-0000000000a1', 'Analista'),
  ('f9d00000-0000-0000-0000-000000000004', 'f9a00000-0000-0000-0000-0000000000a1', 'Consultor');

insert into public.organizational_units (id, organization_id, name, valid_from, valid_to) values
  ('f9e00000-0000-0000-0000-000000000001', 'f9a00000-0000-0000-0000-0000000000a1',
   'Unidade Um F3-07', '2025-01-01T00:00:00Z', null),
  ('f9e00000-0000-0000-0000-000000000002', 'f9a00000-0000-0000-0000-0000000000a1',
   'Unidade Dois F3-07', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Colaboradores e status (C_LEAVE: active → leave → active)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f9b00000-0000-0000-0000-0000000000c1', 'f9a00000-0000-0000-0000-0000000000a1'),
  ('f9b00000-0000-0000-0000-0000000000c2', 'f9a00000-0000-0000-0000-0000000000a1'),
  ('f9b00000-0000-0000-0000-0000000000c3', 'f9a00000-0000-0000-0000-0000000000a1'),
  ('f9b00000-0000-0000-0000-0000000000c4', 'f9a00000-0000-0000-0000-0000000000a1'),
  ('f9b00000-0000-0000-0000-0000000000c5', 'f9a00000-0000-0000-0000-0000000000a1'),
  ('f9b00000-0000-0000-0000-0000000000c6', 'f9a00000-0000-0000-0000-0000000000a1'),
  ('f9b00000-0000-0000-0000-0000000000c7', 'f9a00000-0000-0000-0000-0000000000a1');

insert into public.collaborator_status_periods (
  collaborator_id, status, valid_from, valid_to
) values
  ('f9b00000-0000-0000-0000-0000000000c1', 'active', '2025-01-01T00:00:00Z', null),
  ('f9b00000-0000-0000-0000-0000000000c2', 'active', '2025-01-01T00:00:00Z', null),
  ('f9b00000-0000-0000-0000-0000000000c3', 'active', '2025-01-01T00:00:00Z', null),
  ('f9b00000-0000-0000-0000-0000000000c4', 'active', '2025-01-01T00:00:00Z', '2025-03-31T00:00:00Z'),
  ('f9b00000-0000-0000-0000-0000000000c4', 'leave',  '2025-04-01T00:00:00Z', '2025-05-31T00:00:00Z'),
  ('f9b00000-0000-0000-0000-0000000000c4', 'active', '2025-06-01T00:00:00Z', null),
  ('f9b00000-0000-0000-0000-0000000000c5', 'active', '2025-01-01T00:00:00Z', null),
  ('f9b00000-0000-0000-0000-0000000000c6', 'active', '2025-01-01T00:00:00Z', null),
  ('f9b00000-0000-0000-0000-0000000000c7', 'active', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Posições formais
-- ----------------------------------------------------------------------------
insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('f9c00000-0000-0000-0000-0000000000a1', 'f9a00000-0000-0000-0000-0000000000a1',
   'f9e00000-0000-0000-0000-000000000001', 'f9d00000-0000-0000-0000-000000000001', null,
   '2025-01-01T00:00:00Z', null),
  ('f9c00000-0000-0000-0000-0000000000a2', 'f9a00000-0000-0000-0000-0000000000a1',
   'f9e00000-0000-0000-0000-000000000001', 'f9d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f9c00000-0000-0000-0000-0000000000a3', 'f9a00000-0000-0000-0000-0000000000a1',
   'f9e00000-0000-0000-0000-000000000001', 'f9d00000-0000-0000-0000-000000000003', null,
   '2025-01-01T00:00:00Z', null),
  ('f9c00000-0000-0000-0000-0000000000a4', 'f9a00000-0000-0000-0000-0000000000a1',
   'f9e00000-0000-0000-0000-000000000001', 'f9d00000-0000-0000-0000-000000000003', null,
   '2025-01-01T00:00:00Z', null),
  ('f9c00000-0000-0000-0000-0000000000a5', 'f9a00000-0000-0000-0000-0000000000a1',
   'f9e00000-0000-0000-0000-000000000002', 'f9d00000-0000-0000-0000-000000000004', null,
   '2025-01-01T00:00:00Z', null),
  ('f9c00000-0000-0000-0000-0000000000a6', 'f9a00000-0000-0000-0000-0000000000a1',
   'f9e00000-0000-0000-0000-000000000002', 'f9d00000-0000-0000-0000-000000000003', null,
   '2025-01-01T00:00:00Z', null),
  ('f9c00000-0000-0000-0000-0000000000a7', 'f9a00000-0000-0000-0000-0000000000a1',
   'f9e00000-0000-0000-0000-000000000002', 'f9d00000-0000-0000-0000-000000000003', null,
   '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Reporting lines (hierarquia formal)
-- ----------------------------------------------------------------------------
insert into public.position_reporting_lines (
  organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
) values
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9c00000-0000-0000-0000-0000000000a2',
   'f9c00000-0000-0000-0000-0000000000a1', 'Coordenador sob Gerente', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9c00000-0000-0000-0000-0000000000a3',
   'f9c00000-0000-0000-0000-0000000000a2', 'Analista sob Coordenador', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9c00000-0000-0000-0000-0000000000a4',
   'f9c00000-0000-0000-0000-0000000000a3', 'Analista sob Analista', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9c00000-0000-0000-0000-0000000000a5',
   'f9c00000-0000-0000-0000-0000000000a1', 'Consultor direto ao Gerente (sem Coordenador)', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9c00000-0000-0000-0000-0000000000a6',
   'f9c00000-0000-0000-0000-0000000000a1', 'Analista direto ao Gerente (sem Coordenador)', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9c00000-0000-0000-0000-0000000000a7',
   'f9c00000-0000-0000-0000-0000000000a6', 'Analista sob Analista (multi-gerencia)', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Occupations (titular canônico)
-- ----------------------------------------------------------------------------
insert into public.occupations (
  organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
) values
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9b00000-0000-0000-0000-0000000000c1',
   'f9c00000-0000-0000-0000-0000000000a1', 'Gerente titular', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9b00000-0000-0000-0000-0000000000c3',
   'f9c00000-0000-0000-0000-0000000000a3', 'Analista titular', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9b00000-0000-0000-0000-0000000000c4',
   'f9c00000-0000-0000-0000-0000000000a4', 'Analista em licenca mantida', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9b00000-0000-0000-0000-0000000000c5',
   'f9c00000-0000-0000-0000-0000000000a5', 'Consultor (multi)', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9b00000-0000-0000-0000-0000000000c5',
   'f9c00000-0000-0000-0000-0000000000a6', 'Analista (multi)', '2025-01-01T00:00:00Z', null),
  ('f9a00000-0000-0000-0000-0000000000a1', 'f9b00000-0000-0000-0000-0000000000c7',
   'f9c00000-0000-0000-0000-0000000000a7', 'Analista subordinado', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Temporary responsibility: substituto operacional da posição VAGA P_CORD
-- ----------------------------------------------------------------------------
insert into public.temporary_responsibilities (
  organization_id, organizational_position_id, substitute_collaborator_id,
  responsibility_type, reason, valid_from, valid_to
) values (
  'f9a00000-0000-0000-0000-0000000000a1',
  'f9c00000-0000-0000-0000-0000000000a2',
  'f9b00000-0000-0000-0000-0000000000c2',
  'operational',
  'Cobrir coordenacao vaga',
  '2025-03-01T00:00:00Z', '2025-05-31T00:00:00Z'
);
