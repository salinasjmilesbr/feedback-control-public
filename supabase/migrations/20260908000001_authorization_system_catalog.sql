-- ============================================================================
-- F4-01 (Issue #88): catálogo de sistema determinístico (D9 = A, D16 = A)
-- ----------------------------------------------------------------------------
-- Propósito: semear, de forma determinística e versionada (migration), o
-- catálogo GLOBAL de capabilities e o access_role de sistema `admin` (conjunto
-- mínimo de roles — D14 = B ajustada). Nenhum dado real; UUIDs fixos com
-- prefixo `c0` (não colidem com os cenários de validação).
--
-- Regras (contrato docs/F4-01-desenho-tecnico.md):
--   - capabilities globais (D1 = A); código único em notação domínio.verbo
--     (D15 = A);
--   - `admin` é access_role de SISTEMA (is_system = true, organization_id NULL)
--     atribuído por membership/organização (D17 = A), independente de
--     collaborator (não referencia estrutura F3);
--   - `admin` NÃO recebe capabilities de conteúdo confidencial (D18 = A
--     ajustada): não há capability confidencial genérica neste catálogo, e o
--     bundle `admin` contém apenas administração/leitura não-confiável;
--   - nenhuma role `manager`/`collaborator` baseada em cargo (D14);
--   - rebuild reproduzível: mesmos UUIDs, mesmos códigos, mesma ordem.
-- ============================================================================

insert into public.capabilities (id, code, name, description) values
  ('c0000000-0000-4000-8000-000000000001', 'membership.read',
   'Ler memberships', 'Consultar memberships da organização.'),
  ('c0000000-0000-4000-8000-000000000002', 'membership.manage',
   'Gerenciar memberships', 'Conceder/revogar access_roles e administrar memberships da organização.'),
  ('c0000000-0000-4000-8000-000000000003', 'access_role.manage',
   'Gerenciar roles de acesso', 'Configurar access_roles customizadas e suas capabilities na organização.'),
  ('c0000000-0000-4000-8000-000000000004', 'collaborator.read',
   'Ler colaboradores', 'Consultar colaboradores da organização (alcance definido por escopo, F4-02).'),
  ('c0000000-0000-4000-8000-000000000005', 'collaborator.manage',
   'Gerenciar colaboradores', 'Administrar cadastro de colaboradores da organização.'),
  ('c0000000-0000-4000-8000-000000000006', 'org.structure.manage',
   'Gerenciar estrutura organizacional', 'Administrar unidades, posições, reporting lines, occupations e movimentações.'),
  ('c0000000-0000-4000-8000-000000000007', 'org.catalog.manage',
   'Gerenciar catálogos organizacionais', 'Administrar job_roles e seniority_levels (catálogos, nunca autorização).'),
  ('c0000000-0000-4000-8000-000000000008', 'settings.manage',
   'Gerenciar configurações', 'Administrar escala, expectativas de cargo e configuração geral.'),
  ('c0000000-0000-4000-8000-000000000009', 'cycle.read',
   'Ler ciclos', 'Consultar ciclos de avaliação.'),
  ('c0000000-0000-4000-8000-000000000010', 'cycle.manage',
   'Gerenciar ciclos', 'Criar, ativar e encerrar ciclos (cancelamento/reabertura/correção de período são fluxos excepcionais auditáveis).'),
  ('c0000000-0000-4000-8000-000000000011', 'evaluation.read',
   'Ler avaliações', 'Consultar avaliações (conteúdo de terceiros é confidencial; D18).'),
  ('c0000000-0000-4000-8000-000000000012', 'evaluation.create',
   'Criar avaliações', 'Criar avaliações conforme escopo avaliativo (F4-02).'),
  ('c0000000-0000-4000-8000-000000000013', 'evaluation.write',
   'Editar avaliações', 'Editar avaliações (imutabilidade de concluídas é regra de domínio).'),
  ('c0000000-0000-4000-8000-000000000014', 'evaluation.cancel',
   'Cancelar avaliações', 'Cancelar avaliações (fluxo auditado).'),
  ('c0000000-0000-4000-8000-000000000015', 'evaluation.reopen',
   'Reabrir avaliações', 'Reabrir avaliações concluídas (fluxo excepcional auditado).'),
  ('c0000000-0000-4000-8000-000000000016', 'goal.read',
   'Ler metas', 'Consultar metas (conteúdo de terceiros é confidencial; D18).'),
  ('c0000000-0000-4000-8000-000000000017', 'goal.write',
   'Editar metas', 'Criar/editar/progredir/finalizar metas conforme escopo (F4-02).'),
  ('c0000000-0000-4000-8000-000000000018', 'goal.approve',
   'Aprovar metas', 'Aprovar metas conforme escopo (F4-02).'),
  ('c0000000-0000-4000-8000-000000000019', 'observation.read',
   'Ler observações', 'Consultar observações (Comunicado/terceiros regidos por conteúdo e escopo futuros).'),
  ('c0000000-0000-4000-8000-000000000020', 'observation.write',
   'Editar observações', 'Criar/editar/excluir observações em ciclo ATIVO.'),
  ('c0000000-0000-4000-8000-000000000021', 'report.read',
   'Ler relatórios', 'Consultar relatórios gerenciais/equipe e histórico individual.');

-- ----------------------------------------------------------------------------
-- Access role de sistema `admin` (única role inicial — D14 = B ajustada)
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id)
values ('c0000000-0000-4000-8000-0000000000f1', 'admin', 'active', true, null);

-- ----------------------------------------------------------------------------
-- Bundle `admin` (administração da organização; SEM conteúdo confidencial)
-- ----------------------------------------------------------------------------
insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'c0000000-0000-4000-8000-0000000000f1'
   and c.code in (
     'membership.read',
     'membership.manage',
     'access_role.manage',
     'collaborator.read',
     'collaborator.manage',
     'org.structure.manage',
     'org.catalog.manage',
     'settings.manage',
     'cycle.read'
   );
