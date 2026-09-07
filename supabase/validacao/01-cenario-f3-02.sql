-- ============================================================================
-- F3-02 (Issue #79): cenário sintético de validação — catálogos de funções e
-- senioridades (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f3-02.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F3-02);
--   - `job_roles` configurados por organização: Alfa com os oito conceitos do
--     piloto (Diretor, Gerente Senior, Gerente, Especialista, Coordenador,
--     Consultor, Analista e Estagiario — nomes apenas como categorias
--     sintéticas) + um item desativado; Beta com um subconjunto diferente
--     (Analista, Consultor e Estagiario);
--   - `seniority_levels` configurados por organização: Alfa com Junior, Pleno
--     e Senior; Beta com somente Senior (configurações diferentes por org);
--   - prova estrutural de que "Analista Junior/Pleno/Senior" é representável
--     como função + senioridade independentes (nunca como degraus
--     hierárquicos), que Especialista não carrega equipe/liderança e que
--     Estagiario é função válida sem ocorrência em dados piloto.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do deny-by-default
--     acontece na etapa 02-validar-f3-02.sql via `set role authenticated`.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo (prefixo f4,
--     sem colidir com os cenários de validação anteriores).
--   - Apenas dados sintéticos; nenhum dado real é utilizado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
-- ----------------------------------------------------------------------------
delete from public.job_roles
where organization_id in (
  'f4a00000-0000-0000-0000-0000000000a1',
  'f4a00000-0000-0000-0000-0000000000b1'
);

delete from public.seniority_levels
where organization_id in (
  'f4a00000-0000-0000-0000-0000000000a1',
  'f4a00000-0000-0000-0000-0000000000b1'
);

delete from public.organizations
where id in (
  'f4a00000-0000-0000-0000-0000000000a1',
  'f4a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações sintéticas (F3-02)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f4a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F3-02 Alfa'),
  ('f4a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F3-02 Beta');

-- ----------------------------------------------------------------------------
-- job_roles — Alfa: oito conceitos do piloto como categorias sintéticas
-- (somente identificação/configuração; nenhum atributo de hierarquia,
-- liderança ou autorização) + um item desativado para provar desativação sem
-- exclusão física.
-- ----------------------------------------------------------------------------
insert into public.job_roles (organization_id, name, status) values
  ('f4a00000-0000-0000-0000-0000000000a1', 'Diretor', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Gerente Senior', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Gerente', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Especialista', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Coordenador', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Consultor', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Analista', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Estagiario', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Gerente Regional', 'disabled');

-- ----------------------------------------------------------------------------
-- job_roles — Beta: subconjunto e combinação diferentes (configuração
-- independente por organização).
-- ----------------------------------------------------------------------------
insert into public.job_roles (organization_id, name, status) values
  ('f4a00000-0000-0000-0000-0000000000b1', 'Analista', 'active'),
  ('f4a00000-0000-0000-0000-0000000000b1', 'Consultor', 'active'),
  ('f4a00000-0000-0000-0000-0000000000b1', 'Estagiario', 'active');

-- ----------------------------------------------------------------------------
-- seniority_levels — Alfa: Junior, Pleno e Senior (independentes de job_role).
-- ----------------------------------------------------------------------------
insert into public.seniority_levels (organization_id, name, status) values
  ('f4a00000-0000-0000-0000-0000000000a1', 'Junior', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Pleno', 'active'),
  ('f4a00000-0000-0000-0000-0000000000a1', 'Senior', 'active');

-- ----------------------------------------------------------------------------
-- seniority_levels — Beta: somente Senior (configuração diferente de Alfa;
-- organização pode não usar todas as senioridades).
-- ----------------------------------------------------------------------------
insert into public.seniority_levels (organization_id, name, status) values
  ('f4a00000-0000-0000-0000-0000000000b1', 'Senior', 'active');
