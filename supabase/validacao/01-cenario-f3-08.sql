-- ============================================================================
-- F3-08 (Issue #85): cenário sintético de validação — configuração padrão do
-- colegiado e snapshot por ciclo (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-08.sql:
--
--   - organização Alfa com catálogo, unidade, colaboradores, posições,
--     occupations e reporting lines (F3-01..F3-07);
--   - colaboradores avaliados cobrindo: colegiado com 2 membros (EVAL1),
--     sem configuração (EVAL2), configuração explicitamente vazia (EVAL3),
--     avaliado sem posição na data (EVAL4) e avaliado com DUAS posições
--     ocupadas e superiores distintos (EVAL5);
--   - organização Beta mínima (colaborador) para testes cross-organization;
--   - posição P_Z para o teste de "mudança posterior de occupation não altera
--     snapshot".
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-08.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo fa).
--   - Apenas dados sintéticos; nenhum nome/estrutura/dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.collegiate_cycle_snapshot_members
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.collegiate_cycle_snapshot_positions
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.collegiate_cycle_snapshots
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.collegiate_configuration_members
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.collegiate_configurations
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.temporary_responsibilities
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.occupations
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.collaborator_status_periods
where collaborator_id::text like 'fab00000-0000-0000-0000-0000000000%';

delete from public.position_reporting_lines
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.organizational_positions
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.organizational_units
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.collaborators
where id::text like 'fab00000-0000-0000-0000-0000000000%';

delete from public.job_roles
where organization_id in ('faa00000-0000-0000-0000-0000000000a1',
                          'faa00000-0000-0000-0000-0000000000b1');

delete from public.organizations
where id in ('faa00000-0000-0000-0000-0000000000a1',
             'faa00000-0000-0000-0000-0000000000b1');

-- ----------------------------------------------------------------------------
-- Organização, catálogo, unidade e posições (Alfa)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('faa00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-08 Alfa'),
  ('faa00000-0000-0000-0000-0000000000b1', 'Org Sintetica F3-08 Beta');

insert into public.job_roles (id, organization_id, name) values
  ('fad00000-0000-0000-0000-000000000001', 'faa00000-0000-0000-0000-0000000000a1', 'Gerente'),
  ('fad00000-0000-0000-0000-000000000002', 'faa00000-0000-0000-0000-0000000000a1', 'Analista'),
  ('fad00000-0000-0000-0000-000000000011', 'faa00000-0000-0000-0000-0000000000b1', 'Analista');

insert into public.organizational_units (id, organization_id, name, valid_from, valid_to) values
  ('fae00000-0000-0000-0000-000000000001', 'faa00000-0000-0000-0000-0000000000a1',
   'Unidade F3-08', '2025-01-01T00:00:00Z', null);

insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('fac00000-0000-0000-0000-0000000000a1', 'faa00000-0000-0000-0000-0000000000a1',
   'fae00000-0000-0000-0000-000000000001', 'fad00000-0000-0000-0000-000000000001', null,
   '2025-01-01T00:00:00Z', null),
  ('fac00000-0000-0000-0000-0000000000a7', 'faa00000-0000-0000-0000-0000000000a1',
   'fae00000-0000-0000-0000-000000000001', 'fad00000-0000-0000-0000-000000000001', null,
   '2025-01-01T00:00:00Z', null),
  ('fac00000-0000-0000-0000-0000000000a2', 'faa00000-0000-0000-0000-0000000000a1',
   'fae00000-0000-0000-0000-000000000001', 'fad00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('fac00000-0000-0000-0000-0000000000a3', 'faa00000-0000-0000-0000-0000000000a1',
   'fae00000-0000-0000-0000-000000000001', 'fad00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('fac00000-0000-0000-0000-0000000000a4', 'faa00000-0000-0000-0000-0000000000a1',
   'fae00000-0000-0000-0000-000000000001', 'fad00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('fac00000-0000-0000-0000-0000000000a5', 'faa00000-0000-0000-0000-0000000000a1',
   'fae00000-0000-0000-0000-000000000001', 'fad00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('fac00000-0000-0000-0000-0000000000a6', 'faa00000-0000-0000-0000-0000000000a1',
   'fae00000-0000-0000-0000-000000000001', 'fad00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('fac00000-0000-0000-0000-0000000000a8', 'faa00000-0000-0000-0000-0000000000a1',
   'fae00000-0000-0000-0000-000000000001', 'fad00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Colaboradores (Alfa e Beta) e status
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('fab00000-0000-0000-0000-0000000000c1', 'faa00000-0000-0000-0000-0000000000a1'), -- C_GER
  ('fab00000-0000-0000-0000-0000000000c2', 'faa00000-0000-0000-0000-0000000000a1'), -- EVAL1
  ('fab00000-0000-0000-0000-0000000000c3', 'faa00000-0000-0000-0000-0000000000a1'), -- EVAL2
  ('fab00000-0000-0000-0000-0000000000c4', 'faa00000-0000-0000-0000-0000000000a1'), -- EVAL3
  ('fab00000-0000-0000-0000-0000000000c5', 'faa00000-0000-0000-0000-0000000000a1'), -- EVAL4
  ('fab00000-0000-0000-0000-0000000000c6', 'faa00000-0000-0000-0000-0000000000a1'), -- EVAL5
  ('fab00000-0000-0000-0000-0000000000c7', 'faa00000-0000-0000-0000-0000000000a1'), -- M1
  ('fab00000-0000-0000-0000-0000000000c8', 'faa00000-0000-0000-0000-0000000000a1'), -- M2
  ('fab00000-0000-0000-0000-0000000000d1', 'faa00000-0000-0000-0000-0000000000b1'); -- CBeta

insert into public.collaborator_status_periods (collaborator_id, status, valid_from, valid_to) values
  ('fab00000-0000-0000-0000-0000000000c1', 'active', '2025-01-01T00:00:00Z', null),
  ('fab00000-0000-0000-0000-0000000000c2', 'active', '2025-01-01T00:00:00Z', null),
  ('fab00000-0000-0000-0000-0000000000c3', 'active', '2025-01-01T00:00:00Z', null),
  ('fab00000-0000-0000-0000-0000000000c4', 'active', '2025-01-01T00:00:00Z', null),
  ('fab00000-0000-0000-0000-0000000000c5', 'active', '2025-01-01T00:00:00Z', null),
  ('fab00000-0000-0000-0000-0000000000c6', 'active', '2025-01-01T00:00:00Z', null),
  ('fab00000-0000-0000-0000-0000000000c7', 'active', '2025-01-01T00:00:00Z', null),
  ('fab00000-0000-0000-0000-0000000000c8', 'active', '2025-01-01T00:00:00Z', null),
  ('fab00000-0000-0000-0000-0000000000d1', 'active', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Reporting lines (hierarquia formal; P_E3 é raiz/sem superior)
-- ----------------------------------------------------------------------------
insert into public.position_reporting_lines (
  organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
) values
  ('faa00000-0000-0000-0000-0000000000a1', 'fac00000-0000-0000-0000-0000000000a2',
   'fac00000-0000-0000-0000-0000000000a1', 'E1 sob Gerente', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fac00000-0000-0000-0000-0000000000a3',
   'fac00000-0000-0000-0000-0000000000a1', 'E2 sob Gerente', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fac00000-0000-0000-0000-0000000000a5',
   'fac00000-0000-0000-0000-0000000000a1', 'X sob Gerente 1', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fac00000-0000-0000-0000-0000000000a6',
   'fac00000-0000-0000-0000-0000000000a7', 'Y sob Gerente 2', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Occupations (titulares)
-- ----------------------------------------------------------------------------
insert into public.occupations (
  organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
) values
  ('faa00000-0000-0000-0000-0000000000a1', 'fab00000-0000-0000-0000-0000000000c1',
   'fac00000-0000-0000-0000-0000000000a1', 'Gerente 1', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fab00000-0000-0000-0000-0000000000c1',
   'fac00000-0000-0000-0000-0000000000a7', 'Gerente 2', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fab00000-0000-0000-0000-0000000000c2',
   'fac00000-0000-0000-0000-0000000000a2', 'E1 ocupado', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fab00000-0000-0000-0000-0000000000c3',
   'fac00000-0000-0000-0000-0000000000a3', 'E2 ocupado', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fab00000-0000-0000-0000-0000000000c4',
   'fac00000-0000-0000-0000-0000000000a4', 'E3 ocupado (raiz)', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fab00000-0000-0000-0000-0000000000c6',
   'fac00000-0000-0000-0000-0000000000a5', 'X ocupado', '2025-01-01T00:00:00Z', null),
  ('faa00000-0000-0000-0000-0000000000a1', 'fab00000-0000-0000-0000-0000000000c6',
   'fac00000-0000-0000-0000-0000000000a6', 'Y ocupado', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Configurações padrão do colegiado
-- ----------------------------------------------------------------------------
-- EVAL1: v1 [2025-01-01, null) membros {M1, M2}.
insert into public.collegiate_configurations (
  id, organization_id, collaborator_id, valid_from, valid_to
) values (
  'fa100000-0000-0000-0000-000000000001',
  'faa00000-0000-0000-0000-0000000000a1',
  'fab00000-0000-0000-0000-0000000000c2',
  '2025-01-01T00:00:00Z', null
);

insert into public.collegiate_configuration_members (
  organization_id, configuration_id, member_collaborator_id
) values
  ('faa00000-0000-0000-0000-0000000000a1', 'fa100000-0000-0000-0000-000000000001',
   'fab00000-0000-0000-0000-0000000000c7'),
  ('faa00000-0000-0000-0000-0000000000a1', 'fa100000-0000-0000-0000-000000000001',
   'fab00000-0000-0000-0000-0000000000c8');

-- EVAL3: configuração EXPLICITAMENTE vazia [2025-01-01, null) (sem membros).
insert into public.collegiate_configurations (
  id, organization_id, collaborator_id, valid_from, valid_to
) values (
  'fa100000-0000-0000-0000-000000000004',
  'faa00000-0000-0000-0000-0000000000a1',
  'fab00000-0000-0000-0000-0000000000c4',
  '2025-01-01T00:00:00Z', null
);
