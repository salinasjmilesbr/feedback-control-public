-- ============================================================================
-- F5-11 P3 (Issue #246): cenario FOCADO de AUTORIZACAO/CONCESSAO/SCOPE
-- (Supabase local apenas) — prefixo PROPRIO `f5b3` (nao colide com `f5b2` da P2)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de: 34/35 (P1), 36/37 (P1.1), 38/39 (P2) — este cenario AMPLIA
-- a fixture da P2 (que ja tem o GESTOR `f5b2e000-…-c1`, seus subordinados
-- diretos e o ciclo ATIVO) e acrescenta:
--   - um DESCENDENTE (NETO) do gestor: posicao que reporta ao subordinado
--     direto, para separar DIRECTO de DESCENDANTE no enforcement da relacao;
--   - a CONCESSAO do perfil de sistema `observacoes_gestor` por assignments
--     com scopes DIFERENTES, incluindo os casos negativos exigidos:
--         GESTOR (c1)  -> scope DIRECT_REPORTS        (ALLOW direto)
--         SUB_ATIVO(c2)-> scope DESCENDANTS           (ALLOW descendentes)
--         OUTRO (c5)   -> SEM scope                   (DENY: scope obrigatorio)
--         SEM_CAP (c6) -> scope ORGANIZATION          (DENY: fora do bundle)
--         NETO         -> scope SELF                  (ALLOW so SELF-comunicada)
--     A concessao e' feita pelo caminho soberano existente
--     (`conceder_acesso_role`, service_role) + linha de scope da assignment —
--     exatamente como nas fases F4-02/F4-08/F5-07/F5-08. NENHUMA role
--     customizada e' criada aqui e NENHUMA capability nova.
--   - observacoes de teste (comunicada e nao comunicada) sobre o NETO e sobre o
--     subordinado direto, criadas pelas RPCs soberanas (autor = GESTOR).
-- Regras: EXECUTAR SOMENTE no Supabase local; INSERT-ONCE (guarda abaixo);
-- dados ficticios.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1 from public.organizations
   where id = 'f5b3a000-0000-0000-0000-0000000000a1'
     and name = 'Org Sintetica F5-11 P3 Alfa'
) as cenario_f5_11_p3_carregado \gset

\if :cenario_f5_11_p3_carregado
do $$
begin
  raise notice '[PASS] cenario F5-11 P3 ja carregado - reexecucao no-op (fixture insert-once)';
end $$;
\else
do $$
begin
  if exists (
    select 1 from public.organizations where id = 'f5b3a000-0000-0000-0000-0000000000a1'
  ) then
    raise exception
      '[FAIL] cenario F5-11 P3: COLISAO de UUID - a organizacao % ja existe com outro nome',
      'f5b3a000-0000-0000-0000-0000000000a1';
  end if;
  -- A fixture da P2 precisa estar presente (a P3 AMPLIA a mesma organizacao).
  if not exists (
    select 1 from public.organizations
     where id = 'f5b2a000-0000-0000-0000-0000000000a1'
       and name = 'Org Sintetica F5-11 P2 Alfa'
  ) then
    raise exception '[FAIL] cenario F5-11 P3: a fixture da P2 (38) nao esta carregada';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 1) Organizacao PROPRIETARIA da fixture P3 (o tenant e' o mesmo da P2? NAO:
--    a P3 usa o MESMO tenant da P2 para herdar a estrutura viva, e registra uma
--    organizacao-espelho apenas para o guard insert-once).
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f5b3a000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-11 P3 Alfa');

-- ----------------------------------------------------------------------------
-- 2) DESCENDENTE (NETO): identidade propria + posicao sob o subordinado direto
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('f5b3c000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'neto.f5-11-p3@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('f5b3c000-0000-0000-0000-0000000000a1', 'active');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status) values
  ('f5b3d000-0000-0000-0000-0000000000a1', 'f5b3c000-0000-0000-0000-0000000000a1',
   'f5b2a000-0000-0000-0000-0000000000a1', 'active');

insert into public.collaborators (id, organization_id) values
  ('f5b3e000-0000-0000-0000-0000000000c1', 'f5b2a000-0000-0000-0000-0000000000a1');

insert into public.collaborator_status_periods (collaborator_id, status, valid_from) values
  ('f5b3e000-0000-0000-0000-0000000000c1', 'active', '2024-01-01T00:00:00Z');

insert into public.organizational_positions (
  id, organization_id, unit_id, job_role_id, valid_from, name
) values ('f5b3f000-0000-0000-0000-0000000000e1', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b2f000-0000-0000-0000-0000000000a1', 'f5b2f000-0000-0000-0000-0000000000b1',
   '2018-01-01T00:00:00Z', 'F6 P4.5 40-cenario-f5-11-p3 posição funcional');

insert into public.position_reporting_lines
  (organization_id, subordinate_position_id, manager_position_id, reason, valid_from) values
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b3f000-0000-0000-0000-0000000000e1',
   'f5b2f000-0000-0000-0000-0000000000e2', 'estrutura sintetica F5-11 P3 (neto)',
   '2018-01-01T00:00:00Z');

insert into public.occupations
  (organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to) values
  ('f5b2a000-0000-0000-0000-0000000000a1', 'f5b3e000-0000-0000-0000-0000000000c1',
   'f5b3f000-0000-0000-0000-0000000000e1', 'ocupacao sintetica', '2024-01-01T00:00:00Z', null);

insert into public.membership_collaborator_links
  (membership_id, organization_id, collaborator_id, status) values
  ('f5b3d000-0000-0000-0000-0000000000a1', 'f5b2a000-0000-0000-0000-0000000000a1',
   'f5b3e000-0000-0000-0000-0000000000c1', 'active');

-- ----------------------------------------------------------------------------
-- 3) CONCESSAO EXPLICITA (D15) por assignments com scopes distintos
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    constant uuid := 'f5b2a000-0000-0000-0000-0000000000a1';
  v_role   uuid;
  v_gestor constant uuid := 'f5b2d000-0000-0000-0000-0000000000a1';
  v_sub    constant uuid := 'f5b2d000-0000-0000-0000-0000000000a6';
  v_outro  constant uuid := 'f5b2d000-0000-0000-0000-0000000000a2';
  v_semcap constant uuid := 'f5b2d000-0000-0000-0000-0000000000a3';
  v_neto   constant uuid := 'f5b3d000-0000-0000-0000-0000000000a1';
  v_autor  constant uuid := 'f5b2c000-0000-0000-0000-0000000000a1';
  v_par    record;
begin
  select id into v_role
    from public.access_roles
   where name = 'observacoes_gestor' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    raise exception '[FAIL] cenario F5-11 P3: perfil de sistema observacoes_gestor ausente (migration da P3 nao aplicada)';
  end if;

  -- (a) assignments pelo caminho SOBERANO existente (service_role/owner).
  perform public.conceder_acesso_role(v_gestor, v_role, v_autor);
  perform public.conceder_acesso_role(v_sub, v_role, v_autor);
  perform public.conceder_acesso_role(v_outro, v_role, v_autor);   -- SEM scope (negativo)
  perform public.conceder_acesso_role(v_semcap, v_role, v_autor);  -- scope ORGANIZATION (negativo)
  perform public.conceder_acesso_role(v_neto, v_role, v_autor);    -- scope SELF (regra do dominio)

  -- (b) scopes das assignments (linha filha 1:N; SELF/ORGANIZATION nao satisfazem
  --     o enforcement de gestao; OUTRO fica DELIBERADAMENTE sem linha).
  for v_par in
    select * from (values
      (v_gestor, 'DIRECT_REPORTS'),
      (v_sub,    'DESCENDANTS'),
      (v_semcap, 'ORGANIZATION'),
      (v_neto,   'SELF')) as t(membership_id, scope_type)
  loop
    insert into public.access_role_assignment_scopes
      (assignment_id, organization_id, scope_type, status, created_by)
    select a.id, v_org, v_par.scope_type, 'active', v_autor
      from public.membership_access_role_assignments a
     where a.membership_id = v_par.membership_id
       and a.access_role_id = v_role
       and a.status = 'active';
  end loop;

  raise notice '[PASS] cenario F5-11 P3: concessao de observacoes_gestor criada (DIRECT_REPORTS no gestor; DESCENDANTS no sub; SELF no neto; ORGANIZATION no sem-capability; e um assignment SEM scope)';
end $$;

-- ----------------------------------------------------------------------------
-- 4) Observacoes de teste (criadas pelas RPCs soberanas; autor = GESTOR)
-- ----------------------------------------------------------------------------
do $$
declare
  v_org    constant uuid := 'f5b2a000-0000-0000-0000-0000000000a1';
  v_ciclo  constant uuid := 'f5b21000-0000-0000-0000-0000000000a1';
  v_gestor constant uuid := 'f5b2c000-0000-0000-0000-0000000000a1';
  v_neto   constant uuid := 'f5b3e000-0000-0000-0000-0000000000c1';
  v_sub    constant uuid := 'f5b2e000-0000-0000-0000-0000000000c2';
  v_fora   constant uuid := 'f5b2e000-0000-0000-0000-0000000000c5';
  v_res    jsonb;
  v_obs_neto_com uuid;
  v_obs_neto_nao uuid;
  v_obs_sub      uuid;
begin
  -- (a) observacao sobre o NETO, COMUNICADA (para a regra SELF do dominio).
  v_res := public.observacao_criar(
    v_org, v_ciclo, v_neto, 'POSITIVA', 'observacao ficticia da P3 sobre o neto (comunicada)',
    v_gestor, 'bbbb0000-0000-0000-0000-000000000001');
  v_obs_neto_com := (v_res->>'observation_id')::uuid;
  perform public.observacao_definir_comunicado(
    v_obs_neto_com, v_org, true, 0, v_gestor, 'bbbb0000-0000-0000-0000-000000000002');

  -- (b) observacao sobre o NETO, NAO comunicada.
  v_res := public.observacao_criar(
    v_org, v_ciclo, v_neto, 'NEUTRA', 'observacao ficticia da P3 sobre o neto (nao comunicada)',
    v_gestor, 'bbbb0000-0000-0000-0000-000000000003');
  v_obs_neto_nao := (v_res->>'observation_id')::uuid;

  -- (c) observacao sobre o SUBORDINADO DIRETO (para DIRECTO x DESCENDENTE).
  v_res := public.observacao_criar(
    v_org, v_ciclo, v_sub, 'NEUTRA', 'observacao ficticia da P3 sobre o subordinado direto',
    v_gestor, 'bbbb0000-0000-0000-0000-000000000004');
  v_obs_sub := (v_res->>'observation_id')::uuid;

  -- (d) observacao sobre colaborador FORA da relacao do gestor — inserida
  --     DIRETAMENTE (a criacao por RPC e' corretamente negada para ele); serve
  --     para provar que o SCOPE NAO substitui a RELACAO estrutural.
  insert into public.evaluation_observations
    (organization_id, collaborator_id, cycle_id, tipo, texto,
     author_user_profile_id, author_membership_id, author_collaborator_id, version)
  values
    (v_org, v_fora, v_ciclo, 'NEUTRA', 'observacao ficticia da P3 fora da relacao (fixture direta)',
     v_gestor, 'f5b2d000-0000-0000-0000-0000000000a1', 'f5b2e000-0000-0000-0000-0000000000c1', 0);

  raise notice '[PASS] cenario F5-11 P3: observacoes de teste criadas (neto comunicada=%, neto nao comunicada=%, subordinado direto=%, e uma fora da relacao por fixture direta)',
    v_obs_neto_com, v_obs_neto_nao, v_obs_sub;
end $$;

-- ----------------------------------------------------------------------------
-- 5) Consistencia da fixture
-- ----------------------------------------------------------------------------
do $$
declare
  v_org     int;
  v_perfis  int;
  v_memb    int;
  v_neto    int;
  v_assign  int;
  v_scopes  int;
  v_obs     int;
begin
  select count(*) into v_org from public.organizations
   where id = 'f5b3a000-0000-0000-0000-0000000000a1';
  select count(*) into v_perfis from public.user_profiles
   where id::text like 'f5b3c000-%';
  select count(*) into v_memb from public.user_organization_memberships
   where id::text like 'f5b3d000-%';
  select count(*) into v_neto from public.collaborators
   where id = 'f5b3e000-0000-0000-0000-0000000000c1';
  select count(*) into v_assign from public.membership_access_role_assignments a
    join public.access_roles r on r.id = a.access_role_id
   where r.name = 'observacoes_gestor' and a.status = 'active';
  select count(*) into v_scopes from public.access_role_assignment_scopes s
    join public.membership_access_role_assignments a on a.id = s.assignment_id
    join public.access_roles r on r.id = a.access_role_id
   where r.name = 'observacoes_gestor';
  select count(*) into v_obs from public.evaluation_observations
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and texto like 'observacao ficticia da P3%';

  if v_org <> 1 or v_perfis <> 1 or v_memb <> 1 or v_neto <> 1
     or v_assign <> 5 or v_scopes <> 4 or v_obs <> 4 then
    raise exception
      '[FAIL] cenario F5-11 P3 incompleto (org=% perfis=% memb=% neto=% assignments=% scopes=% obs=%)',
      v_org, v_perfis, v_memb, v_neto, v_assign, v_scopes, v_obs;
  end if;

  raise notice '[PASS] cenario F5-11 P3: 1 organizacao-marcadora, 1 descendente (neto) com posicao sob o subordinado direto, 5 assignments de observacoes_gestor (4 com scope: DIRECT_REPORTS, DESCENDANTS, ORGANIZATION e SELF; 1 SEM scope) e 4 observacoes ficticias (1 comunicada sobre o neto, 1 nao comunicada, 1 sobre o subordinado direto e 1 fora da relacao)';
end $$;

\endif
