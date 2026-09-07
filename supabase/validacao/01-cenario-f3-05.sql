-- ============================================================================
-- F3-05 (Issue #82): cenário sintético de validação — ocupações temporais de
-- colaboradores em posições (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-05.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F3-05), com catálogos,
--     unidades, colaboradores (núcleo F3-01 + status periods) e posições;
--   - occupations demonstrando: posição ocupada e posição vaga (sem qualquer
--     occupation); um colaborador ocupando DUAS posições simultaneamente;
--     troca de ocupante na MESMA posição (sem recriar a posição);
--     transferência com histórico (fechar + abrir); licença independente da
--     occupation (colaborador em leave mantém a ocupação vigente, sem recriar);
--   - uma reporting line (P2 → P1) que deve permanecer independente do
--     ocupante (troca de ocupante não a altera);
--   - colaborador sem occupations (C4) para o teste positivo de desligamento e
--     posição encerrada (P5) para o teste de integridade temporal.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-05.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo f7,
--     sem colidir com os cenários anteriores).
--   - Apenas dados sintéticos; nenhum nome/estrutura/dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.occupations
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborator_status_periods
where collaborator_id in (
  'f7b00000-0000-0000-0000-0000000000c1',
  'f7b00000-0000-0000-0000-0000000000c2',
  'f7b00000-0000-0000-0000-0000000000c3',
  'f7b00000-0000-0000-0000-0000000000c4',
  'f7b00000-0000-0000-0000-0000000000d1'
);

delete from public.position_reporting_lines
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_positions
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborators
where id in (
  'f7b00000-0000-0000-0000-0000000000c1',
  'f7b00000-0000-0000-0000-0000000000c2',
  'f7b00000-0000-0000-0000-0000000000c3',
  'f7b00000-0000-0000-0000-0000000000c4',
  'f7b00000-0000-0000-0000-0000000000d1'
);

delete from public.job_roles
where organization_id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações, catálogos e unidades
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f7a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-05 Alfa'),
  ('f7a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F3-05 Beta');

insert into public.job_roles (id, organization_id, name) values
  ('f7d00000-0000-0000-0000-000000000001', 'f7a00000-0000-0000-0000-0000000000a1', 'Gerente'),
  ('f7d00000-0000-0000-0000-000000000002', 'f7a00000-0000-0000-0000-0000000000a1', 'Analista'),
  ('f7d00000-0000-0000-0000-000000000011', 'f7a00000-0000-0000-0000-0000000000b1', 'Gerente'),
  ('f7d00000-0000-0000-0000-000000000012', 'f7a00000-0000-0000-0000-0000000000b1', 'Analista');

insert into public.organizational_units (id, organization_id, name, valid_from, valid_to) values
  ('f7e00000-0000-0000-0000-0000000000a1', 'f7a00000-0000-0000-0000-0000000000a1',
   'Unidade Alfa F3-05', '2025-01-01T00:00:00Z', null),
  ('f7e00000-0000-0000-0000-0000000000b1', 'f7a00000-0000-0000-0000-0000000000b1',
   'Unidade Beta F3-05', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Colaboradores (núcleo F3-01) e status periods
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f7b00000-0000-0000-0000-0000000000c1', 'f7a00000-0000-0000-0000-0000000000a1'),
  ('f7b00000-0000-0000-0000-0000000000c2', 'f7a00000-0000-0000-0000-0000000000a1'),
  ('f7b00000-0000-0000-0000-0000000000c3', 'f7a00000-0000-0000-0000-0000000000a1'),
  ('f7b00000-0000-0000-0000-0000000000c4', 'f7a00000-0000-0000-0000-0000000000a1'),
  ('f7b00000-0000-0000-0000-0000000000d1', 'f7a00000-0000-0000-0000-0000000000b1');

-- C3: active → leave → active (licença sem efeito sobre occupations).
insert into public.collaborator_status_periods (
  collaborator_id, status, valid_from, valid_to
) values
  ('f7b00000-0000-0000-0000-0000000000c1', 'active', '2025-01-01T00:00:00Z', null),
  ('f7b00000-0000-0000-0000-0000000000c2', 'active', '2025-01-01T00:00:00Z', null),
  ('f7b00000-0000-0000-0000-0000000000c3', 'active', '2025-01-01T00:00:00Z', '2025-03-31T00:00:00Z'),
  ('f7b00000-0000-0000-0000-0000000000c3', 'leave',  '2025-04-01T00:00:00Z', '2025-05-31T00:00:00Z'),
  ('f7b00000-0000-0000-0000-0000000000c3', 'active', '2025-06-01T00:00:00Z', null),
  ('f7b00000-0000-0000-0000-0000000000c4', 'active', '2025-01-01T00:00:00Z', null),
  ('f7b00000-0000-0000-0000-0000000000d1', 'active', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Posições formais (P5 encerrada em 2025-06-30)
-- ----------------------------------------------------------------------------
insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('f7c00000-0000-0000-0000-0000000000a1', 'f7a00000-0000-0000-0000-0000000000a1',
   'f7e00000-0000-0000-0000-0000000000a1', 'f7d00000-0000-0000-0000-000000000001', null,
   '2025-01-01T00:00:00Z', null),
  ('f7c00000-0000-0000-0000-0000000000a2', 'f7a00000-0000-0000-0000-0000000000a1',
   'f7e00000-0000-0000-0000-0000000000a1', 'f7d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f7c00000-0000-0000-0000-0000000000a3', 'f7a00000-0000-0000-0000-0000000000a1',
   'f7e00000-0000-0000-0000-0000000000a1', 'f7d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f7c00000-0000-0000-0000-0000000000a4', 'f7a00000-0000-0000-0000-0000000000a1',
   'f7e00000-0000-0000-0000-0000000000a1', 'f7d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f7c00000-0000-0000-0000-0000000000a5', 'f7a00000-0000-0000-0000-0000000000a1',
   'f7e00000-0000-0000-0000-0000000000a1', 'f7d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z'),
  ('f7c00000-0000-0000-0000-0000000000b1', 'f7a00000-0000-0000-0000-0000000000b1',
   'f7e00000-0000-0000-0000-0000000000b1', 'f7d00000-0000-0000-0000-000000000011', null,
   '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Reporting line independente do ocupante (P2 → P1)
-- ----------------------------------------------------------------------------
insert into public.position_reporting_lines (
  organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
) values (
  'f7a00000-0000-0000-0000-0000000000a1',
  'f7c00000-0000-0000-0000-0000000000a2',
  'f7c00000-0000-0000-0000-0000000000a1',
  'Analista reporta ao Gerente (F3-05)',
  '2025-01-01T00:00:00Z', null
);

-- ----------------------------------------------------------------------------
-- Occupations
-- ----------------------------------------------------------------------------
-- oc1: C1 ocupa P1 (Gerente) até 2025-06-30 (encerrada na transferência).
-- oc2: C1 ocupa P2 (Analista) vigente — C1 ocupa DUAS posições enquanto oc1
--      está aberta (2025-01-01..2025-06-30).
-- oc3: C2 assume P1 em 2025-07-01 — troca de ocupante na MESMA posição.
-- oc4: C3 ocupa P3 vigente — permanece durante o período de licença de C3.
-- oc6: Cb ocupa BP1 (Beta).
-- P4 não possui occupation (posição vaga); P5 é posição encerrada sem
-- ocupação (apenas para o teste de integridade temporal).
insert into public.occupations (
  organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
) values
  ('f7a00000-0000-0000-0000-0000000000a1', 'f7b00000-0000-0000-0000-0000000000c1',
   'f7c00000-0000-0000-0000-0000000000a1', 'Gerente titular',
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z'),
  ('f7a00000-0000-0000-0000-0000000000a1', 'f7b00000-0000-0000-0000-0000000000c1',
   'f7c00000-0000-0000-0000-0000000000a2', 'Acumula posicao de analista',
   '2025-01-01T00:00:00Z', null),
  ('f7a00000-0000-0000-0000-0000000000a1', 'f7b00000-0000-0000-0000-0000000000c2',
   'f7c00000-0000-0000-0000-0000000000a1', 'Troca de ocupante na posicao',
   '2025-07-01T00:00:00Z', null),
  ('f7a00000-0000-0000-0000-0000000000a1', 'f7b00000-0000-0000-0000-0000000000c3',
   'f7c00000-0000-0000-0000-0000000000a3', 'Analista em licenca mantida',
   '2025-01-01T00:00:00Z', null),
  ('f7a00000-0000-0000-0000-0000000000b1', 'f7b00000-0000-0000-0000-0000000000d1',
   'f7c00000-0000-0000-0000-0000000000b1', 'Gerente Beta',
   '2025-01-01T00:00:00Z', null);
