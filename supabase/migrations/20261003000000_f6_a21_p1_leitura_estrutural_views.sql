-- ============================================================================
-- F6-A21 P1 (Issue #327) — CAMADA ADITIVA DE LEITURA ESTRUTURAL SEGURA (views)
-- ----------------------------------------------------------------------------
-- P1 é ADITIVO: cria as vistas soberanas e seus grants e NÃO revoga nada, NÃO
-- altera o cliente e NÃO fecha D16/F4-08 (isso é P3).
--
-- MECANISMO (prova exigida pela Issue): views com privilégio do OWNER
-- (`security_invoker` ausente/false, o padrão). A view é propriedade da role de
-- migration — a MESMA que possui as tabelas — e o F4-08 certifica que NENHUMA
-- tabela tem FORCE ROW LEVEL SECURITY; portanto a view lê as tabelas (inclusive
-- as autorizativas) com os privilégios do owner, enquanto `authenticated`
-- continua SEM privilégio algum nelas. Não há helper `SECURITY DEFINER`, não há
-- grant em tabela autorizativa e não há função nova.
--
-- VIEWS:
--   - `estrutura_autorizacao`   → projeção MÍNIMA para a UI (uma linha por
--     membership ativa do PRÓPRIO auth.uid()): capabilities de leitura
--     administrativa e o vínculo soberano do ator;
--   - `estrutura_administrativa`→ fotografia administrativa do tenant, com as
--     seções filtradas por capability: `org.structure.manage` (estrutura e
--     pessoas) e `org.catalog.manage` (catálogos). Membership-only ⇒ ZERO linhas;
--   - `estrutura_pessoal`       → SUBGRAFO do próprio ator (vínculo soberano +
--     cadeia de gestão acima/abaixo + colegiado e pessoas alcançadas), sem exigir
--     capability administrativa.
--
-- INVARIANTES: nenhuma capability/role/bundle nova; nenhum `SECURITY DEFINER`
-- novo (continua 4); nenhum grant nas tabelas autorizativas; nenhuma autoridade
-- derivada de cargo/título/matrícula; nenhuma escrita; cross-tenant sempre por
-- `organization_id` da membership ativa do próprio ator (fail-closed).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) Premissa do mecanismo: nenhuma tabela com FORCE RLS (F4-08)
-- ----------------------------------------------------------------------------
do $premissa$
declare v_n integer;
begin
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relforcerowsecurity;
  if v_n <> 0 then
    raise exception 'F6_A21_P1: FORCE RLS presente em % tabela(s) — o mecanismo de view-owner nao e valido', v_n;
  end if;
  raise notice '[PASS] F6-A21 P1: nenhuma tabela com FORCE RLS (view lê com privilégio do owner)';
end $premissa$;

-- ----------------------------------------------------------------------------
-- 1) `estrutura_autorizacao` — projeção mínima (UI) e eixo das demais views
-- ----------------------------------------------------------------------------
create or replace view public.estrutura_autorizacao as
select
  m.organization_id,
  -- Leitura por RELAÇÕES (não por função): a view herda o privilégio do OWNER
  -- para relações, mas NÃO para EXECUTE de funções. O predicado espelha
  -- exatamente `resolver_capabilities_efetivas` (F4-01/F5-04): membership ativa
  -- (outer) + atribuição ativa + role ativa + capability ativa e não deprecada.
  exists (
    select 1
      from public.membership_access_role_assignments a
      join public.access_roles r
        on r.id = a.access_role_id and r.status = 'active'
      join public.access_role_capabilities rc
        on rc.access_role_id = r.id
      join public.capabilities c
        on c.id = rc.capability_id and c.status = 'active' and c.deprecated = false
     where a.membership_id = m.id
       and a.status = 'active'
       and c.code = 'org.structure.manage'
  ) as pode_estrutura,
  exists (
    select 1
      from public.membership_access_role_assignments a
      join public.access_roles r
        on r.id = a.access_role_id and r.status = 'active'
      join public.access_role_capabilities rc
        on rc.access_role_id = r.id
      join public.capabilities c
        on c.id = rc.capability_id and c.status = 'active' and c.deprecated = false
     where a.membership_id = m.id
       and a.status = 'active'
       and c.code = 'org.catalog.manage'
  ) as pode_catalogo,
  -- Vínculo soberano: espelha `resolver_collaborator_vinculado` (F5-02 Q4=A) —
  -- membership ativa (outer), perfil ativo (outer) e link ATIVO.
  (
    select l.collaborator_id
      from public.membership_collaborator_links l
     where l.membership_id = m.id
       and l.status = 'active'
     limit 1
  ) as collaborator_id
from public.user_organization_memberships m
join public.user_profiles up on up.id = m.user_profile_id
where m.user_profile_id = auth.uid()
  and m.status = 'active'
  and up.status = 'active';

comment on view public.estrutura_autorizacao is
  'F6-A21 P1 (#327): projecao MINIMA de autorizacao do PROPRIO ator (auth.uid) — '
  'uma linha por membership ativa: pode_estrutura/pode_catalogo (capabilities '
  'efetivas existentes) e o vinculo soberano (resolver_collaborador_vinculado). '
  'Nao expoe dados de terceiros nem tabelas autorizativas.';

-- ----------------------------------------------------------------------------
-- 2) `estrutura_administrativa` — fotografia do tenant gated por capability
-- ----------------------------------------------------------------------------
create or replace view public.estrutura_administrativa as
select
  a.organization_id,
  a.pode_estrutura,
  a.pode_catalogo,
  case when a.pode_estrutura then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, name, valid_from, valid_to, version
        from public.organizational_units
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as unidades,
  case when a.pode_estrutura then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, unit_id, parent_unit_id, valid_from, valid_to, version
        from public.organizational_unit_parent_periods
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as periodos_parent,
  case when a.pode_estrutura then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to, version
        from public.organizational_positions
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as posicoes,
  case when a.pode_estrutura then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, subordinate_position_id, manager_position_id, reason,
             valid_from, valid_to, version
        from public.position_reporting_lines
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as reporting_lines,
  case when a.pode_estrutura then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, collaborator_id, organizational_position_id, valid_from, valid_to, version
        from public.occupations
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as ocupacoes,
  case when a.pode_estrutura then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, collaborator_id, valid_from, valid_to, version
        from public.collegiate_configurations
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as colegiados,
  case when a.pode_estrutura then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select configuration_id, member_collaborator_id
        from public.collegiate_configuration_members
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as membros_colegiado,
  case when a.pode_estrutura then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, full_name
        from public.collaborators
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as colaboradores,
  case when a.pode_catalogo then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, code, name, status, version
        from public.job_roles
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as cargos,
  case when a.pode_catalogo then (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select id, name, status, version
        from public.seniority_levels
       where organization_id = a.organization_id) x
  ) else '[]'::jsonb end as senioridades
from public.estrutura_autorizacao a
where a.pode_estrutura or a.pode_catalogo;

comment on view public.estrutura_administrativa is
  'F6-A21 P1 (#327): fotografia estrutural ADMINISTRATIVA do tenant para o ator '
  '(auth.uid) — uma linha por organizacao em que ele tem membership ATIVA e '
  'capability efetiva (org.structure.manage para estrutura/pessoas; '
  'org.catalog.manage para catalogos, com as secoes filtradas). Membership-only '
  'nao recebe NENHUMA linha. Somente leitura, sem escrita e sem dado de outro '
  'tenant (organization_id sempre da membership do proprio ator).';

-- ----------------------------------------------------------------------------
-- 3) `estrutura_pessoal` — subgrafo soberano do próprio ator
-- ----------------------------------------------------------------------------
create or replace view public.estrutura_pessoal as
with recursive base as (
  select a.organization_id, a.collaborator_id
    from public.estrutura_autorizacao a
   where a.collaborator_id is not null
),
semente as (
  select b.organization_id, o.organizational_position_id as pos
    from base b
    join public.occupations o
      on o.organization_id = b.organization_id
     and o.collaborator_id = b.collaborator_id
),
acima as (
  select organization_id, pos from semente
  union
  select r.organization_id, r.manager_position_id
    from public.position_reporting_lines r
    join acima a
      on a.organization_id = r.organization_id
     and a.pos = r.subordinate_position_id
),
abaixo as (
  select organization_id, pos from semente
  union
  select r.organization_id, r.subordinate_position_id
    from public.position_reporting_lines r
    join abaixo a
      on a.organization_id = r.organization_id
     and a.pos = r.manager_position_id
),
alcance as (
  select organization_id, pos from acima
  union
  select organization_id, pos from abaixo
),
posicoes_alcance as (
  select distinct organization_id, pos from alcance
),
colaboradores_alcance as (
  select b.organization_id, b.collaborator_id as cid from base b
  union
  select o.organization_id, o.collaborator_id
    from public.occupations o
    join posicoes_alcance pa
      on pa.organization_id = o.organization_id
     and pa.pos = o.organizational_position_id
)
select
  b.organization_id,
  b.collaborator_id,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select u.id, u.name, u.valid_from, u.valid_to, u.version
        from public.organizational_units u
       where u.organization_id = b.organization_id
         and u.id in (
           select p.unit_id from public.organizational_positions p
            join posicoes_alcance pa
              on pa.organization_id = p.organization_id and pa.pos = p.id)) x
  ) as unidades,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select pp.id, pp.unit_id, pp.parent_unit_id, pp.valid_from, pp.valid_to, pp.version
        from public.organizational_unit_parent_periods pp
       where pp.organization_id = b.organization_id
         and pp.unit_id in (
           select p.unit_id from public.organizational_positions p
            join posicoes_alcance pa
              on pa.organization_id = p.organization_id and pa.pos = p.id)) x
  ) as periodos_parent,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select p.id, p.unit_id, p.job_role_id, p.seniority_level_id,
             p.valid_from, p.valid_to, p.version
        from public.organizational_positions p
        join posicoes_alcance pa
          on pa.organization_id = p.organization_id and pa.pos = p.id) x
  ) as posicoes,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select r.id, r.subordinate_position_id, r.manager_position_id, r.reason,
             r.valid_from, r.valid_to, r.version
        from public.position_reporting_lines r
       where r.organization_id = b.organization_id
         and r.subordinate_position_id in (
           select pos from posicoes_alcance where organization_id = b.organization_id)
         and r.manager_position_id in (
           select pos from posicoes_alcance where organization_id = b.organization_id)) x
  ) as reporting_lines,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select o.id, o.collaborator_id, o.organizational_position_id,
             o.valid_from, o.valid_to, o.version
        from public.occupations o
       where o.organization_id = b.organization_id
         and o.collaborator_id in (
           select cid from colaboradores_alcance where organization_id = b.organization_id)) x
  ) as ocupacoes,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.collaborator_id, c.valid_from, c.valid_to, c.version
        from public.collegiate_configurations c
       where c.organization_id = b.organization_id
         and c.collaborator_id in (
           select cid from colaboradores_alcance where organization_id = b.organization_id)) x
  ) as colegiados,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select m.configuration_id, m.member_collaborator_id
        from public.collegiate_configuration_members m
       where m.organization_id = b.organization_id
         and m.configuration_id in (
           select c.id from public.collegiate_configurations c
            where c.organization_id = b.organization_id
              and c.collaborator_id in (
                select cid from colaboradores_alcance where organization_id = b.organization_id))) x
  ) as membros_colegiado,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.full_name
        from public.collaborators c
       where c.organization_id = b.organization_id
         and c.id in (
           select cid from colaboradores_alcance where organization_id = b.organization_id)) x
  ) as colaboradores,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select j.id, j.code, j.name, j.status, j.version
        from public.job_roles j
       where j.organization_id = b.organization_id
         and j.id in (
           select p.job_role_id from public.organizational_positions p
            join posicoes_alcance pa
              on pa.organization_id = p.organization_id and pa.pos = p.id)) x
  ) as cargos,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select s.id, s.name, s.status, s.version
        from public.seniority_levels s
       where s.organization_id = b.organization_id
         and s.id in (
           select p.seniority_level_id from public.organizational_positions p
            join posicoes_alcance pa
              on pa.organization_id = p.organization_id and pa.pos = p.id
            where p.seniority_level_id is not null)) x
  ) as senioridades
from base b;

comment on view public.estrutura_pessoal is
  'F6-A21 P1 (#327): SUBGRAFO estrutural do PROPRIO ator (auth.uid) — vinculo '
  'soberano (F5-02) + cadeia de gestao acima/abaixo + colegiado e pessoas '
  'alcancadas, para preservar as superficies PESSOAIS de ciclo/meta/avaliacao. '
  'Nao exige capability administrativa e NAO devolve a fotografia do tenant: as '
  'secoes sao limitadas ao alcance do ator.';

-- ----------------------------------------------------------------------------
-- 4) ACL: somente as três views, somente para `authenticated`
-- ----------------------------------------------------------------------------
revoke all on public.estrutura_autorizacao from public, anon, authenticated;
revoke all on public.estrutura_administrativa from public, anon, authenticated;
revoke all on public.estrutura_pessoal from public, anon, authenticated;
grant select on public.estrutura_autorizacao to authenticated;
grant select on public.estrutura_administrativa to authenticated;
grant select on public.estrutura_pessoal to authenticated;

-- ----------------------------------------------------------------------------
-- 5) Guardas fail-closed da própria migration
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_n         integer;
  v_sem_inv   boolean;
  v_mesmo_dono boolean;
begin
  -- (a) Semântica OWNER: as views não declaram `security_invoker=true` e
  --     pertencem ao MESMO owner das tabelas (mecanismo de leitura privilegiada).
  select coalesce(array_to_string(c.reloptions, ','), '') not like '%security_invoker=true%'
    into v_sem_inv
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'estrutura_administrativa';
  if v_sem_inv is not true then
    raise exception 'F6_A21_P1: estrutura_administrativa nao usa semantica owner';
  end if;

  select (select c.relowner from pg_class c where c.relname = 'estrutura_administrativa')
       = (select c.relowner from pg_class c where c.relname = 'organizational_units')
    into v_mesmo_dono;
  if v_mesmo_dono is not true then
    raise exception 'F6_A21_P1: views e tabelas com owners diferentes — mecanismo invalido';
  end if;

  -- (b) Substituição de view só é permitida com as MESMAS colunas: garante que
  --     um `create or replace view` futuro não troque o contrato em silêncio.
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and c.relname in ('estrutura_autorizacao', 'estrutura_administrativa', 'estrutura_pessoal');
  if v_n <> 3 then
    raise exception 'F6_A21_P1: esperadas 3 views, encontradas %', v_n;
  end if;

  -- (c) `authenticated` recebe SELECT SOMENTE nas três views previstas.
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v'
     and has_table_privilege('authenticated', c.oid, 'SELECT');
  if v_n <> 3 then
    raise exception 'F6_A21_P1: authenticated com SELECT em % view(s) (esperado 3)', v_n;
  end if;
  if has_table_privilege('anon', 'public.estrutura_administrativa', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_pessoal', 'SELECT')
     or has_table_privilege('anon', 'public.estrutura_autorizacao', 'SELECT') then
    raise exception 'F6_A21_P1: anon com SELECT em view do #327';
  end if;

  -- (d) NENHUM privilégio novo nas tabelas autorizativas nem no resolver.
  if has_table_privilege('authenticated', 'public.access_roles', 'SELECT')
     or has_table_privilege('authenticated', 'public.access_role_capabilities', 'SELECT')
     or has_table_privilege('authenticated', 'public.membership_access_role_assignments', 'SELECT') then
    raise exception 'F6_A21_P1: authenticated com SELECT em tabela autorizativa';
  end if;
  if has_function_privilege('authenticated', 'public.resolver_capabilities_efetivas(uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.resolver_collaborador_vinculado(uuid, uuid)', 'EXECUTE') then
    raise exception 'F6_A21_P1: authenticated executa resolver de autorizacao';
  end if;

  -- (e) Invariantes de plataforma: 4 DEFINER, capabilities intactas, D15 intacta.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4 then
    raise exception 'F6_A21_P1: esperado exatamente 4 SECURITY DEFINER, encontrado %', v_n;
  end if;

  select count(*) into v_n
    from public.capabilities
   where code in ('org.structure.manage', 'org.catalog.manage')
     and status = 'active' and deprecated = false;
  if v_n <> 2 then
    raise exception 'F6_A21_P1: capabilities administrativas esperadas=2, encontradas=%', v_n;
  end if;

  select count(*) into v_n
    from public.capabilities where code = 'membership.manage' and grantable_via_role = false;
  if v_n <> 1 then
    raise exception 'F6_A21_P1: D15 alterada (membership.manage deveria seguir nao concedivel)';
  end if;

  -- (f) P1 é ADITIVO: a leitura direta existente permanece INTACTA (P3 a fecha).
  if not has_table_privilege('authenticated', 'public.organizational_positions', 'SELECT') then
    raise exception 'F6_A21_P1: leitura direta ja revogada — P1 deve ser aditivo';
  end if;

  raise notice '[PASS] F6-A21 P1: 3 views owner-semantics, service do ator, SELECT so em authenticated, zero privilegio novo em tabela autorizativa, 4 DEFINER/D15 intactos e leitura direta preservada (aditivo)';
end $guarda$;
