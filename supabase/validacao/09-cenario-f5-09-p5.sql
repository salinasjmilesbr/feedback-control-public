-- ============================================================================
-- F5-09 P5: cenario sintetico de validacao — leitura soberana de ciclos
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md §9 (RLS own-tenant: policy ANTES do
-- grant), §13.5 (leitura por PostgREST sob RLS) e §19 P5; migration
-- `20260919000000_f5_09_cycle_read_rls.sql`.
--
-- Fixture para `10-validar-f5-09-p5.sql` — ISOLADA (prefixo `ec`) das fixtures
-- das fases P1–P4 e da F4-08:
--   - duas organizacoes (Alfa-P5 e Beta-P5) com CICLOS reais:
--     Alfa com 2 ciclos (1 ATIVO + 1 PLANEJADO) e Beta com 1 ciclo ATIVO;
--   - seis identidades sinteticas cobrindo a matriz do §9:
--     u_alfa (membership ATIVA em Alfa) ................. le o proprio tenant;
--     u_beta (membership ATIVA em Beta) ................. le apenas Beta;
--     u_sem_membership (profile ativo, SEM vinculo) ..... DENY (zero linhas);
--     u_membership_inativa (membership DISABLED) ........ DENY;
--     u_profile_inativo (profile INATIVO + membership) .. DENY (fail-closed);
--     u_fantasma (JWT sem profile/membership) ........... DENY.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - INSERT-ONCE: reexecucao e NO-OP (guarda abaixo). Para estado limpo use
--     `db reset` (como no CI).
--   - Os ciclos sao inseridos DIRETAMENTE (fixture): o objeto desta validacao e
--     a LEITURA por RLS, nao a mutacao (que tem validadores proprios nas fases
--     P2/P3/P4).
--   - Somente dados ficticios; nenhum dado real e pessoal.
-- ============================================================================

\set ON_ERROR_STOP on

select exists (
  select 1
    from public.organizations
   where id in ('eca00000-0000-0000-0000-0000000000a1',
                'eca00000-0000-0000-0000-0000000000b1')
) as cenario_f5_09_p5_carregado \gset

\if :cenario_f5_09_p5_carregado
do $$
begin
  raise notice '[PASS] cenario F5-09 P5 ja carregado — reexecucao no-op (fixture insert-once)';
end $$;
\else

-- ----------------------------------------------------------------------------
-- 1) Organizacoes sinteticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('eca00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-09 P5 Alfa'),
  ('eca00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-09 P5 Beta');

-- ----------------------------------------------------------------------------
-- 2) Identidades sinteticas (auth.users) + perfis internos
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ecc00000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'leitor.alfa.f5-09-p5@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('ecc00000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'leitor.beta.f5-09-p5@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('ecc00000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sem.membership.f5-09-p5@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('ecc00000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'membership.inativa.f5-09-p5@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('ecc00000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'profile.inativo.f5-09-p5@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

-- u_fantasma NAO tem profile (JWT valido sem vinculo soberano algum).
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('ecc00000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'fantasma.f5-09-p5@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

-- `user_profiles.status` no contrato F4-08 admite apenas 'active' e 'disabled':
-- o caso "profile inativo" usa 'disabled' (perfil desabilitado com membership
-- ATIVA) — o helper de tenant exige profile ATIVO e responde false.
insert into public.user_profiles (id, status) values
  ('ecc00000-0000-0000-0000-000000000001', 'active'),
  ('ecc00000-0000-0000-0000-000000000002', 'active'),
  ('ecc00000-0000-0000-0000-000000000003', 'active'),
  ('ecc00000-0000-0000-0000-000000000004', 'active'),
  ('ecc00000-0000-0000-0000-000000000005', 'disabled');

insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('ecd00000-0000-0000-0000-000000000001', 'ecc00000-0000-0000-0000-000000000001',
   'eca00000-0000-0000-0000-0000000000a1', 'active'),
  ('ecd00000-0000-0000-0000-000000000002', 'ecc00000-0000-0000-0000-000000000002',
   'eca00000-0000-0000-0000-0000000000b1', 'active'),
  ('ecd00000-0000-0000-0000-000000000004', 'ecc00000-0000-0000-0000-000000000004',
   'eca00000-0000-0000-0000-0000000000a1', 'disabled'),
  ('ecd00000-0000-0000-0000-000000000005', 'ecc00000-0000-0000-0000-000000000005',
   'eca00000-0000-0000-0000-0000000000a1', 'active');

-- ----------------------------------------------------------------------------
-- 3) Ciclos (fixture direta): 2 em Alfa (1 ATIVO + 1 PLANEJADO) e 1 no Beta
-- ----------------------------------------------------------------------------
insert into public.evaluation_cycles
  (id, organization_id, ano, numero, status, data_inicio, data_fim,
   data_ativacao, version) values
  ('ecd10000-0000-0000-0000-000000000001', 'eca00000-0000-0000-0000-0000000000a1',
   2035, 1, 'ATIVO', date '2035-01-01', date '2035-03-31', now(), 1),
  ('ecd10000-0000-0000-0000-000000000002', 'eca00000-0000-0000-0000-0000000000a1',
   2035, 2, 'PLANEJADO', date '2035-04-01', date '2035-06-30', null, 0),
  ('ecd10000-0000-0000-0000-0000000000b1', 'eca00000-0000-0000-0000-0000000000b1',
   2035, 1, 'ATIVO', date '2035-01-01', date '2035-03-31', now(), 1);

-- ----------------------------------------------------------------------------
-- 4) Consistencia da fixture (falha cedo se o cenario ficou incompleto)
-- ----------------------------------------------------------------------------
do $$
declare
  v_orgs     int;
  v_users    int;
  v_profiles int;
  v_active   int;
  v_ciclos_a int;
  v_ciclos_b int;
  v_ativos_a int;
  v_ok       boolean;
begin
  select count(*) into v_orgs from public.organizations
   where id in ('eca00000-0000-0000-0000-0000000000a1',
                'eca00000-0000-0000-0000-0000000000b1');
  select count(*) into v_users from auth.users
   where id::text like 'ecc00000-0000-0000-0000-0000000000%';
  select count(*) into v_profiles from public.user_profiles
   where id::text like 'ecc00000-0000-0000-0000-0000000000%';
  select count(*) into v_active from public.user_organization_memberships
   where organization_id in ('eca00000-0000-0000-0000-0000000000a1',
                             'eca00000-0000-0000-0000-0000000000b1')
     and status = 'active'
     and user_profile_id in ('ecc00000-0000-0000-0000-000000000001',
                             'ecc00000-0000-0000-0000-000000000002',
                             'ecc00000-0000-0000-0000-000000000005');
  select count(*) into v_ciclos_a from public.evaluation_cycles
   where organization_id = 'eca00000-0000-0000-0000-0000000000a1';
  select count(*) into v_ciclos_b from public.evaluation_cycles
   where organization_id = 'eca00000-0000-0000-0000-0000000000b1';
  select count(*) into v_ativos_a from public.evaluation_cycles
   where organization_id = 'eca00000-0000-0000-0000-0000000000a1' and status = 'ATIVO';

  if v_orgs <> 2 or v_users <> 6 or v_profiles <> 5
     or v_active <> 3 or v_ciclos_a <> 2 or v_ciclos_b <> 1 or v_ativos_a <> 1 then
    raise exception
      '[FAIL] cenario F5-09 P5 incompleto (orgs=%, users=%, profiles=%, memberships ativas=%, ciclos Alfa=%, ciclos Beta=%, ATIVO Alfa=%)',
      v_orgs, v_users, v_profiles, v_active, v_ciclos_a, v_ciclos_b, v_ativos_a;
  end if;

  -- O helper de tenant responde corretamente para a fixture (pre-condicao da
  -- matriz de leitura).
  if public.user_has_active_membership('eca00000-0000-0000-0000-0000000000a1') is not true then
    -- Sem JWT no contexto do dono o helper responde false: a checagem e feita
    -- pelo VALIDADOR com `request.jwt.claim.sub`; aqui apenas registramos.
    null;
  end if;

  raise notice '[PASS] cenario F5-09 P5: 2 orgs, 6 identidades (4 Alfa: ativa/sem membership/inativa/profile inativo + 1 Beta + 1 fantasma), 3 ciclos (Alfa ATIVO+PLANEJADO, Beta ATIVO)';
end $$;

\endif
