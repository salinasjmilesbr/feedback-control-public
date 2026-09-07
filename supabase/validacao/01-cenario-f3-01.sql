-- ============================================================================
-- F3-01 (Issue #78): cenário sintético de validação — colaboradores,
-- identificadores de negócio e períodos de status (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-01.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F3-01);
--   - quatro colaboradores sintéticos (Ana, Bruno, Carlos e Diana);
--   - identificadores de negócio (business_code) com validade temporal,
--     incluindo troca histórica de código sem trocar collaborator.id;
--   - períodos de status com histórico ACTIVE → LEAVE → ACTIVE e LEAVE vigente
--     coexistindo com vínculo organizacional (licença não encerra posição/
--     ocupação — nenhuma tabela de posição/ocupação existe nesta issue).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-01.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo f3,
--     sem colidir com os cenários de validação anteriores).
--   - Apenas dados sintéticos; nenhum dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.collaborator_status_periods
where collaborator_id in (
  'f3b00000-0000-0000-0000-0000000000a1',
  'f3b00000-0000-0000-0000-0000000000b1',
  'f3b00000-0000-0000-0000-0000000000c1',
  'f3b00000-0000-0000-0000-0000000000d1'
);

delete from public.collaborator_identifiers
where collaborator_id in (
  'f3b00000-0000-0000-0000-0000000000a1',
  'f3b00000-0000-0000-0000-0000000000b1',
  'f3b00000-0000-0000-0000-0000000000c1',
  'f3b00000-0000-0000-0000-0000000000d1'
);

delete from public.collaborators
where id in (
  'f3b00000-0000-0000-0000-0000000000a1',
  'f3b00000-0000-0000-0000-0000000000b1',
  'f3b00000-0000-0000-0000-0000000000c1',
  'f3b00000-0000-0000-0000-0000000000d1'
);

delete from public.organizations
where id in (
  'f3a00000-0000-0000-0000-0000000000a1',
  'f3a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações sintéticas (F3-01)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f3a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-01 Alfa'),
  ('f3a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F3-01 Beta');

-- ----------------------------------------------------------------------------
-- Colaboradores sintéticos (identidade técnica UUID; sem atributos de pessoa)
-- ----------------------------------------------------------------------------
insert into public.collaborators (id, organization_id) values
  ('f3b00000-0000-0000-0000-0000000000a1', 'f3a00000-0000-0000-0000-0000000000a1'), -- Ana  (Alfa)
  ('f3b00000-0000-0000-0000-0000000000b1', 'f3a00000-0000-0000-0000-0000000000b1'), -- Bruno (Beta)
  ('f3b00000-0000-0000-0000-0000000000c1', 'f3a00000-0000-0000-0000-0000000000a1'), -- Carlos (Alfa)
  ('f3b00000-0000-0000-0000-0000000000d1', 'f3a00000-0000-0000-0000-0000000000a1'); -- Diana (Alfa)

-- ----------------------------------------------------------------------------
-- Identificadores de negócio (código atual = linha aberta com valid_to null)
-- ----------------------------------------------------------------------------
-- Ana:   MAT-1001 (Alfa) vigente desde 2025-01-01.
-- Bruno: MAT-1001 (Beta) vigente desde 2025-01-01 — mesmo código de Ana, porém
--        em OUTRA organização (reuso entre organizações permitido pela unique
--        (organization_id, business_code)).
-- Carlos: MAT-2001 de 2025-01-01 a 2025-06-30 (fechado) e MAT-3001 vigente
--         desde 2025-07-01 — troca histórica de código SEM trocar o
--         collaborator.id.
-- Diana:  MAT-9001 (Alfa) vigente desde 2025-06-01.
insert into public.collaborator_identifiers (
  collaborator_id, organization_id, business_code, valid_from, valid_to
) values
  ('f3b00000-0000-0000-0000-0000000000a1', 'f3a00000-0000-0000-0000-0000000000a1',
   'MAT-1001', '2025-01-01T00:00:00Z', null),
  ('f3b00000-0000-0000-0000-0000000000b1', 'f3a00000-0000-0000-0000-0000000000b1',
   'MAT-1001', '2025-01-01T00:00:00Z', null),
  ('f3b00000-0000-0000-0000-0000000000c1', 'f3a00000-0000-0000-0000-0000000000a1',
   'MAT-2001', '2025-01-01T00:00:00Z', '2025-06-30T00:00:00Z'),
  ('f3b00000-0000-0000-0000-0000000000c1', 'f3a00000-0000-0000-0000-0000000000a1',
   'MAT-3001', '2025-07-01T00:00:00Z', null),
  ('f3b00000-0000-0000-0000-0000000000d1', 'f3a00000-0000-0000-0000-0000000000a1',
   'MAT-9001', '2025-06-01T00:00:00Z', null);

-- ----------------------------------------------------------------------------
-- Períodos de status (linha do tempo única por colaborador, meio-aberta)
-- ----------------------------------------------------------------------------
-- Ana:   ACTIVE [2025-01-01, 2025-03-31) → LEAVE [2025-04-01, 2025-06-30) →
--        ACTIVE vigente desde 2025-07-01 (histórico ACTIVE → LEAVE → ACTIVE).
-- Bruno: ACTIVE vigente desde 2025-01-01.
-- Carlos: ACTIVE vigente desde 2025-01-01.
-- Diana: LEAVE vigente desde 2025-06-01 — licença é estado do colaborador e
--        coexiste com o vínculo organizacional (linha em collaborators e
--        identificador vigente preservados; nenhuma ocupação/posição existe).
insert into public.collaborator_status_periods (
  collaborator_id, status, valid_from, valid_to
) values
  ('f3b00000-0000-0000-0000-0000000000a1', 'active',
   '2025-01-01T00:00:00Z', '2025-03-31T00:00:00Z'),
  ('f3b00000-0000-0000-0000-0000000000a1', 'leave',
   '2025-04-01T00:00:00Z', '2025-06-30T00:00:00Z'),
  ('f3b00000-0000-0000-0000-0000000000a1', 'active',
   '2025-07-01T00:00:00Z', null),
  ('f3b00000-0000-0000-0000-0000000000b1', 'active',
   '2025-01-01T00:00:00Z', null),
  ('f3b00000-0000-0000-0000-0000000000c1', 'active',
   '2025-01-01T00:00:00Z', null),
  ('f3b00000-0000-0000-0000-0000000000d1', 'leave',
   '2025-06-01T00:00:00Z', null);
