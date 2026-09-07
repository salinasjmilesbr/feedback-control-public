-- ============================================================================
-- F3-04 (Issue #81): cenário sintético de validação — reporting lines
-- temporais entre posições (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-04.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F3-04), com catálogos, uma
--     unidade por org e posições formais (todas vagas — occupation fora do
--     escopo);
--   - cadeia formal que exercita os casos exigidos: Diretor→Diretor,
--     Gerente→Gerente Sênior, Gerente→Gerente, Analista→Gerente direto (sem
--     Coordenador), mesmo job_role (Analista) em alturas diferentes,
--     Especialista sem subordinados, posição raiz por AUSÊNCIA de linha;
--   - temporalidade: troca de superior fechando o período anterior e abrindo
--     outro (P_ANL3), uma posição encerrada com linha encerrada consistente
--     (P_FECH) e gaps permitidos;
--   - reporting lines com `reason` obrigatório (não vazio).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-04.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo f6,
--     sem colidir com os cenários anteriores).
--   - Apenas dados sintéticos; nenhum nome/estrutura/dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.position_reporting_lines
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_positions
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizational_units
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.job_roles
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.seniority_levels
where organization_id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f6a00000-0000-0000-0000-0000000000a1',
  'f6a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações sintéticas (F3-04)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f6a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-04 Alfa'),
  ('f6a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F3-04 Beta');

-- ----------------------------------------------------------------------------
-- Catálogos por organização
-- ----------------------------------------------------------------------------
insert into public.job_roles (id, organization_id, name) values
  ('f6d00000-0000-0000-0000-000000000001', 'f6a00000-0000-0000-0000-0000000000a1', 'Diretor'),
  ('f6d00000-0000-0000-0000-000000000002', 'f6a00000-0000-0000-0000-0000000000a1', 'Gerente'),
  ('f6d00000-0000-0000-0000-000000000003', 'f6a00000-0000-0000-0000-0000000000a1', 'Gerente Senior'),
  ('f6d00000-0000-0000-0000-000000000004', 'f6a00000-0000-0000-0000-0000000000a1', 'Analista'),
  ('f6d00000-0000-0000-0000-000000000005', 'f6a00000-0000-0000-0000-0000000000a1', 'Especialista'),
  ('f6d00000-0000-0000-0000-000000000006', 'f6a00000-0000-0000-0000-0000000000a1', 'Consultor'),
  ('f6d00000-0000-0000-0000-000000000021', 'f6a00000-0000-0000-0000-0000000000b1', 'Gerente'),
  ('f6d00000-0000-0000-0000-000000000022', 'f6a00000-0000-0000-0000-0000000000b1', 'Analista');

insert into public.seniority_levels (id, organization_id, name) values
  ('f6d00000-0000-0000-0000-000000000011', 'f6a00000-0000-0000-0000-0000000000a1', 'Junior'),
  ('f6d00000-0000-0000-0000-000000000012', 'f6a00000-0000-0000-0000-0000000000a1', 'Pleno'),
  ('f6d00000-0000-0000-0000-000000000013', 'f6a00000-0000-0000-0000-0000000000a1', 'Senior'),
  ('f6d00000-0000-0000-0000-000000000031', 'f6a00000-0000-0000-0000-0000000000b1', 'Senior');

-- ----------------------------------------------------------------------------
-- Unidades (uma por org, apenas como âncora estrutural das posições)
-- ----------------------------------------------------------------------------
insert into public.organizational_units (id, organization_id, name, valid_from, valid_to) values
  ('f6b00000-0000-0000-0000-0000000000a1', 'f6a00000-0000-0000-0000-0000000000a1',
   'Unidade Alfa F3-04', '2025-01-01T00:00:00Z', null),
  ('f6b00000-0000-0000-0000-0000000000b1', 'f6a00000-0000-0000-0000-0000000000b1',
   'Unidade Beta F3-04', '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Posições — Alfa
-- ----------------------------------------------------------------------------
insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('f6c00000-0000-0000-0000-0000000000a1', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000001', null,
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000a2', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000001', null,
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000a3', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000003', null,
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000a4', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000a5', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000002', null,
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000a6', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000004', null,
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000a7', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000004',
   'f6d00000-0000-0000-0000-000000000012',
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000a8', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000004',
   'f6d00000-0000-0000-0000-000000000013',
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000a9', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000005',
   'f6d00000-0000-0000-0000-000000000013',
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000aa', 'f6a00000-0000-0000-0000-0000000000a1',
   'f6b00000-0000-0000-0000-0000000000a1', 'f6d00000-0000-0000-0000-000000000006', null,
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z');

-- Posições — Beta
insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to
) values
  ('f6c00000-0000-0000-0000-0000000000b1', 'f6a00000-0000-0000-0000-0000000000b1',
   'f6b00000-0000-0000-0000-0000000000b1', 'f6d00000-0000-0000-0000-000000000021', null,
   '2025-01-01T00:00:00Z', null),
  ('f6c00000-0000-0000-0000-0000000000b2', 'f6a00000-0000-0000-0000-0000000000b1',
   'f6b00000-0000-0000-0000-0000000000b1', 'f6d00000-0000-0000-0000-000000000022',
   'f6d00000-0000-0000-0000-000000000031',
   '2025-01-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Reporting lines — Alfa (cadeia formal; ausência de linha = raiz)
-- ----------------------------------------------------------------------------
insert into public.position_reporting_lines (
  organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
) values
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a2',
   'f6c00000-0000-0000-0000-0000000000a1', 'Estrutura inicial (Diretor sob Diretor)',
   '2025-01-01T00:00:00Z', null),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a3',
   'f6c00000-0000-0000-0000-0000000000a2', 'Estrutura inicial (Gerente Senior sob Diretor)',
   '2025-01-01T00:00:00Z', null),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a4',
   'f6c00000-0000-0000-0000-0000000000a3', 'Gerente sob Gerente Senior',
   '2025-01-01T00:00:00Z', null),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a5',
   'f6c00000-0000-0000-0000-0000000000a4', 'Gerente sob Gerente',
   '2025-01-01T00:00:00Z', null),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a6',
   'f6c00000-0000-0000-0000-0000000000a5', 'Analista direto ao Gerente (sem Coordenador)',
   '2025-01-01T00:00:00Z', null),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a7',
   'f6c00000-0000-0000-0000-0000000000a5', 'Analista Pleno sob Gerente',
   '2025-01-01T00:00:00Z', null),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a9',
   'f6c00000-0000-0000-0000-0000000000a2', 'Especialista sob Diretor',
   '2025-01-01T00:00:00Z', null),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a8',
   'f6c00000-0000-0000-0000-0000000000a1', 'Analista Senior sob Diretor',
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z'),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000a8',
   'f6c00000-0000-0000-0000-0000000000a3', 'Mudanca de superior (reorganizacao)',
   '2025-07-01T00:00:00Z', null),
  ('f6a00000-0000-0000-0000-0000000000a1', 'f6c00000-0000-0000-0000-0000000000aa',
   'f6c00000-0000-0000-0000-0000000000a5', 'Consultor sob Gerente',
   '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z');

-- Reporting lines — Beta
insert into public.position_reporting_lines (
  organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to
) values
  ('f6a00000-0000-0000-0000-0000000000b1', 'f6c00000-0000-0000-0000-0000000000b2',
   'f6c00000-0000-0000-0000-0000000000b1', 'Analista sob Gerente (Beta)',
   '2025-01-01T00:00:00Z', null);
