-- ============================================================================
-- F3-03 (Issue #80): cenário sintético de validação — unidades e posições da
-- estrutura formal (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-03.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F3-03);
--   - catálogos de funções/senioridades próprios de cada organização
--     (necessários às FKs compostas das posições);
--   - `organizational_units` com existência temporal (vigentes e uma unidade
--     encerrada) e `organizational_unit_parent_periods` com histórico de
--     reestruturação (mudança de parent sem recriar a unidade; unidade raiz;
--     nível intermediário criado depois);
--   - `organizational_positions` vagas (sem ocupante — ocupação é issue
--     posterior), incluindo: posição de Gerente e posições de Analista na
--     MESMA unidade sem Coordenador intermediário; duas posições idênticas
--     (mesma unidade+função+senioridade null) como ocorrências distintas; o
--     mesmo job_role (Analista) em unidades de alturas diferentes; Especialista
--     em unidade sem filhos/subordinados; posição encerrada preservada.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-03.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo f5,
--     sem colidir com os cenários anteriores).
--   - Apenas dados sintéticos; nenhuma estrutura/nome/área real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.organizational_positions
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_unit_parent_periods
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.job_roles
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.seniority_levels
where organization_id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f5a00000-0000-0000-0000-0000000000a1',
  'f5a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações sintéticas (F3-03)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f5a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-03 Alfa'),
  ('f5a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F3-03 Beta');

-- ----------------------------------------------------------------------------
-- Catálogos por organização (Alfa: vários; Beta: subconjunto)
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name) values
  ('f5d00000-0000-0000-0000-000000000001', 'f5a00000-0000-0000-0000-0000000000a1', 'Diretor'),
  ('f5d00000-0000-0000-0000-000000000002', 'f5a00000-0000-0000-0000-0000000000a1', 'Gerente'),
  ('f5d00000-0000-0000-0000-000000000003', 'f5a00000-0000-0000-0000-0000000000a1', 'Coordenador'),
  ('f5d00000-0000-0000-0000-000000000004', 'f5a00000-0000-0000-0000-0000000000a1', 'Analista'),
  ('f5d00000-0000-0000-0000-000000000005', 'f5a00000-0000-0000-0000-0000000000a1', 'Especialista'),
  ('f5d00000-0000-0000-0000-000000000006', 'f5a00000-0000-0000-0000-0000000000a1', 'Consultor'),
  ('f5d00000-0000-0000-0000-000000000021', 'f5a00000-0000-0000-0000-0000000000b1', 'Analista'),
  ('f5d00000-0000-0000-0000-000000000022', 'f5a00000-0000-0000-0000-0000000000b1', 'Consultor');

insert into public.seniority_levels (id, organization_id, name) values
  ('f5d00000-0000-0000-0000-000000000011', 'f5a00000-0000-0000-0000-0000000000a1', 'Junior'),
  ('f5d00000-0000-0000-0000-000000000012', 'f5a00000-0000-0000-0000-0000000000a1', 'Pleno'),
  ('f5d00000-0000-0000-0000-000000000013', 'f5a00000-0000-0000-0000-0000000000a1', 'Senior'),
  ('f5d00000-0000-0000-0000-000000000031', 'f5a00000-0000-0000-0000-0000000000b1', 'Senior');

-- ----------------------------------------------------------------------------
-- Unidades — Alfa (existência temporal na própria entidade)
-- ----------------------------------------------------------------------------
-- A_ROOT : raiz (Diretoria), vigente desde 2025-01-01.
-- A_GER  : Gerencia, vigente desde 2025-01-01 (sem níveis intermediários
--          obrigatórios; Analistas podem ficar diretamente nela).
-- A_CORD : Coordenacao criada em 2025-07-01 (nível inserido depois — expansão
--          entre níveis conhecidos).
-- A_ESP  : unidade de Especialistas (sem filhos/subordinados) vigente desde
--          2025-01-01.
-- A_DIR2 : nova Diretoria criada em 2025-07-01 (expansão futura acima).
-- A_FEC  : unidade encerrada em 2025-06-30 (histórico preservado).
insert into public.organizational_units (id, organization_id, name, valid_from, valid_to) values
  ('f5b00000-0000-0000-0000-0000000000a1', 'f5a00000-0000-0000-0000-0000000000a1',
   'Diretoria Alfa F3-03', '2025-01-01T00:00:00Z', null),
  ('f5b00000-0000-0000-0000-0000000000a2', 'f5a00000-0000-0000-0000-0000000000a1',
   'Gerencia Alfa F3-03', '2025-01-01T00:00:00Z', null),
  ('f5b00000-0000-0000-0000-0000000000a3', 'f5a00000-0000-0000-0000-0000000000a1',
   'Coordenacao Alfa F3-03', '2025-07-01T00:00:00Z', null),
  ('f5b00000-0000-0000-0000-0000000000a4', 'f5a00000-0000-0000-0000-0000000000a1',
   'Especialistas Alfa F3-03', '2025-01-01T00:00:00Z', null),
  ('f5b00000-0000-0000-0000-0000000000a5', 'f5a00000-0000-0000-0000-0000000000a1',
   'Diretoria Nova Alfa F3-03', '2025-07-01T00:00:00Z', null),
  ('f5b00000-0000-0000-0000-0000000000a6', 'f5a00000-0000-0000-0000-0000000000a1',
   'Unidade Encerrada Alfa F3-03', '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z');

-- Unidades — Beta (configuração mínima independente).
insert into public.organizational_units (id, organization_id, name, valid_from, valid_to) values
  ('f5b00000-0000-0000-0000-0000000000b1', 'f5a00000-0000-0000-0000-0000000000b1',
   'Unidade Beta F3-03', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Parent temporal (árvore de unidades) — Alfa
-- ----------------------------------------------------------------------------
-- A_ROOT é raiz (parent null). A_GER muda de parent em 2025-07-01 (de A_ROOT
-- para A_DIR2) SEM recriar a unidade: dois períodos preservam o histórico.
-- A_CORD (nível intermediário criado depois) é filha de A_GER. A_ESP e A_FEC
-- são filhas de A_ROOT; A_FEC teve o período de composição encerrado junto com
-- a unidade.
insert into public.organizational_unit_parent_periods (
  organization_id, unit_id, parent_unit_id, valid_from, valid_to
) values
  ('f5a00000-0000-0000-0000-0000000000a1', 'f5b00000-0000-0000-0000-0000000000a1', null,
   '2025-01-01T00:00:00Z', null),
  ('f5a00000-0000-0000-0000-0000000000a1', 'f5b00000-0000-0000-0000-0000000000a2',
   'f5b00000-0000-0000-0000-0000000000a1',
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z'),
  ('f5a00000-0000-0000-0000-0000000000a1', 'f5b00000-0000-0000-0000-0000000000a2',
   'f5b00000-0000-0000-0000-0000000000a5',
   '2025-07-01T00:00:00Z', null),
  ('f5a00000-0000-0000-0000-0000000000a1', 'f5b00000-0000-0000-0000-0000000000a3',
   'f5b00000-0000-0000-0000-0000000000a2',
   '2025-07-01T00:00:00Z', null),
  ('f5a00000-0000-0000-0000-0000000000a1', 'f5b00000-0000-0000-0000-0000000000a4',
   'f5b00000-0000-0000-0000-0000000000a1',
   '2025-01-01T00:00:00Z', null),
  ('f5a00000-0000-0000-0000-0000000000a1', 'f5b00000-0000-0000-0000-0000000000a6',
   'f5b00000-0000-0000-0000-0000000000a1',
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z');

-- Parent temporal — Beta (raiz).
insert into public.organizational_unit_parent_periods (
  organization_id, unit_id, parent_unit_id, valid_from, valid_to
) values
  ('f5a00000-0000-0000-0000-0000000000b1', 'f5b00000-0000-0000-0000-0000000000b1', null,
   '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Posições — Alfa (todas vagas; sem colaborador/ocupação)
-- ----------------------------------------------------------------------------
-- P_GER     : Gerente na Gerencia (sem Coordenador intermediário exigido).
-- P_ANL_GER : Analista na Gerencia (mesma unidade do Gerente).
-- P_ANL2_GER: SEGUNDA posição idêntica a P_ANL_GER (mesma unidade+função+
--             senioridade null) — ocorrência formal distinta.
-- P_ANL_CORD: Analista (Pleno) na Coordenacao — o mesmo job_role Analista em
--             outra altura/parte da estrutura.
-- P_ESP     : Especialista (Senior) na unidade de Especialistas — sem equipe.
-- P_CONS_F  : Consultor encerrado em 2025-06-30 (histórico preservado).
insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('f5c00000-0000-0000-0000-0000000000a1', 'f5a00000-0000-0000-0000-0000000000a1',
   'f5b00000-0000-0000-0000-0000000000a2', 'f5d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f5c00000-0000-0000-0000-0000000000a2', 'f5a00000-0000-0000-0000-0000000000a1',
   'f5b00000-0000-0000-0000-0000000000a2', 'f5d00000-0000-0000-0000-000000000004', null,
   '2025-01-01T00:00:00Z', null),
  ('f5c00000-0000-0000-0000-0000000000a6', 'f5a00000-0000-0000-0000-0000000000a1',
   'f5b00000-0000-0000-0000-0000000000a2', 'f5d00000-0000-0000-0000-000000000004', null,
   '2025-01-01T00:00:00Z', null),
  ('f5c00000-0000-0000-0000-0000000000a3', 'f5a00000-0000-0000-0000-0000000000a1',
   'f5b00000-0000-0000-0000-0000000000a3', 'f5d00000-0000-0000-0000-000000000004',
   'f5d00000-0000-0000-0000-000000000012',
   '2025-07-01T00:00:00Z', null),
  ('f5c00000-0000-0000-0000-0000000000a4', 'f5a00000-0000-0000-0000-0000000000a1',
   'f5b00000-0000-0000-0000-0000000000a4', 'f5d00000-0000-0000-0000-000000000005',
   'f5d00000-0000-0000-0000-000000000013',
   '2025-01-01T00:00:00Z', null),
  ('f5c00000-0000-0000-0000-0000000000a5', 'f5a00000-0000-0000-0000-0000000000a1',
   'f5b00000-0000-0000-0000-0000000000a2', 'f5d00000-0000-0000-0000-000000000006', null,
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z');

-- Posições — Beta (configuração mínima independente).
insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('f5c00000-0000-0000-0000-0000000000b1', 'f5a00000-0000-0000-0000-0000000000b1',
   'f5b00000-0000-0000-0000-0000000000b1', 'f5d00000-0000-0000-0000-000000000021', null,
   '2025-01-01T00:00:00Z', null),
  ('f5c00000-0000-0000-0000-0000000000b2', 'f5a00000-0000-0000-0000-0000000000b1',
   'f5b00000-0000-0000-0000-0000000000b1', 'f5d00000-0000-0000-0000-000000000022',
   'f5d00000-0000-0000-0000-000000000031',
   '2025-01-01T00:00:00Z', null);
