-- ============================================================================
-- F3-06 (Issue #83): cenário sintético de validação — responsabilidades
-- temporárias e substituições (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-06.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F3-06), com catálogos,
--     unidades, colaboradores (núcleo F3-01 + status periods), posições e
--     occupations (titular canônico);
--   - temporary_responsibilities demonstrando: titular mantém occupation
--     durante a substituição; substituto sem occupation artificial; mesmo
--     substituto cobrindo duas posições simultaneamente; tipo evaluative
--     (preparação para resolução futura); período obrigatoriamente fechado;
--     reporting line independente;
--   - C4 (sem occupation na posição alvo) e P5 (posição encerrada) para os
--     testes de rejeição.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-06.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo f8,
--     sem colidir com os cenários anteriores).
--   - Apenas dados sintéticos; nenhum nome/estrutura/dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.temporary_responsibilities
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.occupations
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborator_status_periods
where collaborator_id in (
  'f8b00000-0000-0000-0000-0000000000c1',
  'f8b00000-0000-0000-0000-0000000000c2',
  'f8b00000-0000-0000-0000-0000000000c3',
  'f8b00000-0000-0000-0000-0000000000c4',
  'f8b00000-0000-0000-0000-0000000000d1'
);

delete from public.position_reporting_lines
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_positions
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.collaborators
where id in (
  'f8b00000-0000-0000-0000-0000000000c1',
  'f8b00000-0000-0000-0000-0000000000c2',
  'f8b00000-0000-0000-0000-0000000000c3',
  'f8b00000-0000-0000-0000-0000000000c4',
  'f8b00000-0000-0000-0000-0000000000d1'
);

delete from public.job_roles
where organization_id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações, catálogos e unidades
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f8a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-06 Alfa'),
  ('f8a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F3-06 Beta');

insert into public.job_roles (id, organization_id, name) values
  ('f8d00000-0000-0000-0000-000000000001', 'f8a00000-0000-0000-0000-0000000000a1', 'Gerente'),
  ('f8d00000-0000-0000-0000-000000000002', 'f8a00000-0000-0000-0000-0000000000a1', 'Analista'),
  ('f8d00000-0000-0000-0000-000000000011', 'f8a00000-0000-0000-0000-0000000000b1', 'Gerente'),
  ('f8d00000-0000-0000-0000-000000000012', 'f8a00000-0000-0000-0000-0000000000b1', 'Analista');

insert into public.organizational_units (id, organization_id, name, valid_from, valid_to) values
  ('f8e00000-0000-0000-0000-0000000000a1', 'f8a00000-0000-0000-0000-0000000000a1',
   'Unidade Alfa F3-06', '2025-01-01T00:00:00Z', null),
  ('f8e00000-0000-0000-0000-0000000000b1', 'f8a00000-0000-0000-0000-0000000000b1',
   'Unidade Beta F3-06', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Colaboradores e status periods
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f8b00000-0000-0000-0000-0000000000c1', 'f8a00000-0000-0000-0000-0000000000a1'),
  ('f8b00000-0000-0000-0000-0000000000c2', 'f8a00000-0000-0000-0000-0000000000a1'),
  ('f8b00000-0000-0000-0000-0000000000c3', 'f8a00000-0000-0000-0000-0000000000a1'),
  ('f8b00000-0000-0000-0000-0000000000c4', 'f8a00000-0000-0000-0000-0000000000a1'),
  ('f8b00000-0000-0000-0000-0000000000d1', 'f8a00000-0000-0000-0000-0000000000b1');

insert into public.collaborator_status_periods (
  collaborator_id, status, valid_from, valid_to
) values
  ('f8b00000-0000-0000-0000-0000000000c1', 'active', '2025-01-01T00:00:00Z', null),
  ('f8b00000-0000-0000-0000-0000000000c2', 'active', '2025-01-01T00:00:00Z', null),
  ('f8b00000-0000-0000-0000-0000000000c3', 'active', '2025-01-01T00:00:00Z', '2025-03-31T00:00:00Z'),
  ('f8b00000-0000-0000-0000-0000000000c3', 'leave',  '2025-04-01T00:00:00Z', '2025-05-31T00:00:00Z'),
  ('f8b00000-0000-0000-0000-0000000000c3', 'active', '2025-06-01T00:00:00Z', null),
  ('f8b00000-0000-0000-0000-0000000000c4', 'active', '2025-01-01T00:00:00Z', null),
  ('f8b00000-0000-0000-0000-0000000000d1', 'active', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Posições formais (P5 encerrada em 2025-06-30)
-- ----------------------------------------------------------------------------
insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('f8c00000-0000-0000-0000-0000000000a1', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8e00000-0000-0000-0000-0000000000a1', 'f8d00000-0000-0000-0000-000000000001', null,
   '2025-01-01T00:00:00Z', null),
  ('f8c00000-0000-0000-0000-0000000000a2', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8e00000-0000-0000-0000-0000000000a1', 'f8d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f8c00000-0000-0000-0000-0000000000a3', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8e00000-0000-0000-0000-0000000000a1', 'f8d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f8c00000-0000-0000-0000-0000000000a4', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8e00000-0000-0000-0000-0000000000a1', 'f8d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f8c00000-0000-0000-0000-0000000000a5', 'f8a00000-0000-0000-0000-0000000000a1',
   'f8e00000-0000-0000-0000-0000000000a1', 'f8d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z'),
  ('f8c00000-0000-0000-0000-0000000000b1', 'f8a00000-0000-0000-0000-0000000000b1',
   'f8e00000-0000-0000-0000-0000000000b1', 'f8d00000-0000-0000-0000-000000000011', null,
   '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Occupations (titular canônico)
-- ----------------------------------------------------------------------------
insert into public.occupations (
  organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to
) values
  ('f8a00000-0000-0000-0000-0000000000a1', 'f8b00000-0000-0000-0000-0000000000c1',
   'f8c00000-0000-0000-0000-0000000000a1', 'Gerente titular', '2025-01-01T00:00:00Z', null),
  ('f8a00000-0000-0000-0000-0000000000a1', 'f8b00000-0000-0000-0000-0000000000c1',
   'f8c00000-0000-0000-0000-0000000000a2', 'Acumula analise', '2025-01-01T00:00:00Z', null),
  ('f8a00000-0000-0000-0000-0000000000a1', 'f8b00000-0000-0000-0000-0000000000c3',
   'f8c00000-0000-0000-0000-0000000000a3', 'Analista (licenca mantida)', '2025-01-01T00:00:00Z', null),
  ('f8a00000-0000-0000-0000-0000000000b1', 'f8b00000-0000-0000-0000-0000000000d1',
   'f8c00000-0000-0000-0000-0000000000b1', 'Gerente Beta', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Reporting line independente do ocupante (P2 → P1)
-- ----------------------------------------------------------------------------
insert into public.position_reporting_lines (
  organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
) values (
  'f8a00000-0000-0000-0000-0000000000a1',
  'f8c00000-0000-0000-0000-0000000000a2',
  'f8c00000-0000-0000-0000-0000000000a1',
  'Analista reporta ao Gerente (F3-06)',
  '2025-01-01T00:00:00Z', null
);

-- ----------------------------------------------------------------------------
-- Temporary responsibilities (período obrigatoriamente fechado)
-- ----------------------------------------------------------------------------
-- tr1: C2 substitui P1 (operacional) — titular C1 mantém a occupation.
-- tr2: C2 substitui P2 (operacional) — mesmo substituto em duas posições.
-- tr3: C2 com responsabilidade avaliativa sobre P3 (encerrada; prepara
--      resolução futura, sem implementar domínio de avaliação).
insert into public.temporary_responsibilities (
  organization_id, organizational_position_id, substitute_collaborator_id,
  responsibility_type, reason, valid_from, valid_to
) values
  ('f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a1',
   'f8b00000-0000-0000-0000-0000000000c2', 'operational',
   'Cobrir gerencia em ferias', '2025-03-01T00:00:00Z', '2025-04-30T00:00:00Z'),
  ('f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a2',
   'f8b00000-0000-0000-0000-0000000000c2', 'operational',
   'Cobrir analise simultanea', '2025-03-01T00:00:00Z', '2025-04-30T00:00:00Z'),
  ('f8a00000-0000-0000-0000-0000000000a1', 'f8c00000-0000-0000-0000-0000000000a3',
   'f8b00000-0000-0000-0000-0000000000c2', 'evaluative',
   'Preparar responsabilidade avaliativa', '2025-01-01T00:00:00Z', '2025-02-28T00:00:00Z');
