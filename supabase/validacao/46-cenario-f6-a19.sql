-- ============================================================================
-- F6-A19 (Issue #319): cenário sintético — CONVITE ADMINISTRATIVO COM VÍNCULO
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma DETERMINÍSTICA e RE-EXECUTÁVEL, o estado usado
-- pelo validador `46-validar-f6-a19.sql`:
--
--   ADMIN        auth + perfil ATIVO + membership ativa em ALFA + role `admin`
--                (administrador LEGÍTIMO do tenant — quem pode convidar);
--   NAO_ADMIN    auth + perfil ATIVO + membership ativa em ALFA + role
--                `evaluator` (role de DOMÍNIO: nunca confere autoridade
--                administrativa — F6-306);
--   OUTRO_TENANT auth + perfil ATIVO + membership ativa em BETA + role `admin`
--                (admin de OUTRO tenant: cross-tenant deve ser NEGADO em ALFA);
--   CONVIDADO    auth SEM perfil/membership (conta a provisionar pela RPC);
--   CONVIDADO_2  auth SEM perfil/membership (retry / falha parcial).
--
-- Colaboradoras (criadas pelo PRIMITIVO canônico `colaborador_criar`, F5-07):
--   matrícula textual `ACME002` em ALFA e `BETA001` em BETA.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - Apenas dados sintéticos (`@example.invalid`); nenhuma credencial real.
--   - Prefixo de UUID exclusivo `f6a19`; nada fora desse prefixo é tocado.
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- Limpeza idempotente (somente o que este cenário cria)
-- ----------------------------------------------------------------------------
delete from public.membership_collaborator_links l
 where l.membership_id in (
         select m.id from public.user_organization_memberships m
          where m.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                                      'f6a19000-0000-4000-8000-0000000000a2')
             or m.user_profile_id::text like 'f6a19000-0000-4000-8000-0000000000%')
    or l.collaborator_id in (
         select c.id from public.collaborators c
          where c.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                                      'f6a19000-0000-4000-8000-0000000000a2'));

delete from public.collaborator_events e
 where e.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                             'f6a19000-0000-4000-8000-0000000000a2')
    or e.collaborator_id in (
         select c.id from public.collaborators c
          where c.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                                      'f6a19000-0000-4000-8000-0000000000a2'));

delete from public.collaborator_status_periods s
 where s.collaborator_id in (
         select c.id from public.collaborators c
          where c.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                                      'f6a19000-0000-4000-8000-0000000000a2'));

delete from public.collaborator_identifiers i
 where i.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                             'f6a19000-0000-4000-8000-0000000000a2');

delete from public.collaborators c
 where c.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                             'f6a19000-0000-4000-8000-0000000000a2');

delete from public.membership_access_role_assignments a
 where a.membership_id in (
         select m.id from public.user_organization_memberships m
          where m.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                                      'f6a19000-0000-4000-8000-0000000000a2')
             or m.user_profile_id::text like 'f6a19000-0000-4000-8000-0000000000%');

delete from public.user_organization_memberships m
 where m.organization_id in ('f6a19000-0000-4000-8000-0000000000a1',
                             'f6a19000-0000-4000-8000-0000000000a2')
    or m.user_profile_id::text like 'f6a19000-0000-4000-8000-0000000000%';

delete from public.user_profiles p
 where p.id::text like 'f6a19000-0000-4000-8000-0000000000%';

delete from public.organizations o
 where o.id in ('f6a19000-0000-4000-8000-0000000000a1',
                'f6a19000-0000-4000-8000-0000000000a2');

delete from auth.users u
 where u.id::text like 'f6a19000-0000-4000-8000-0000000000%';

-- ----------------------------------------------------------------------------
-- Organizações e identidades Auth sintéticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('f6a19000-0000-4000-8000-0000000000a1', 'F6-A19 Alfa'),
  ('f6a19000-0000-4000-8000-0000000000a2', 'F6-A19 Beta');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token,
  reauthentication_token, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'f6a19000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'admin.f6-a19@example.invalid',
   crypt('virtus-senha-f6-a19-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a19000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'nao.admin.f6-a19@example.invalid',
   crypt('virtus-senha-f6-a19-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a19000-0000-4000-8000-000000000003',
   'authenticated', 'authenticated', 'outro.tenant.f6-a19@example.invalid',
   crypt('virtus-senha-f6-a19-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a19000-0000-4000-8000-000000000004',
   'authenticated', 'authenticated', 'convidado.f6-a19@example.invalid',
   crypt('virtus-senha-f6-a19-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a19000-0000-4000-8000-000000000005',
   'authenticated', 'authenticated', 'convidado2.f6-a19@example.invalid',
   crypt('virtus-senha-f6-a19-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now());

-- Perfis internos ATIVOS (CONVIDADO/CONVIDADO_2 ficam SEM perfil de propósito:
-- é a RPC do convite que os provisiona).
insert into public.user_profiles (id, status) values
  ('f6a19000-0000-4000-8000-000000000001', 'active'),
  ('f6a19000-0000-4000-8000-000000000002', 'active'),
  ('f6a19000-0000-4000-8000-000000000003', 'active');

-- Memberships: ADMIN e NAO_ADMIN em ALFA; OUTRO_TENANT em BETA.
insert into public.user_organization_memberships (user_profile_id, organization_id, status) values
  ('f6a19000-0000-4000-8000-000000000001', 'f6a19000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a19000-0000-4000-8000-000000000002', 'f6a19000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a19000-0000-4000-8000-000000000003', 'f6a19000-0000-4000-8000-0000000000a2', 'active');

-- Atribuições: `admin` para ADMIN (em ALFA) e para OUTRO_TENANT (em BETA);
-- `evaluator` para NAO_ADMIN (role de domínio — NUNCA autoridade admin).
insert into public.membership_access_role_assignments
  (membership_id, organization_id, access_role_id, status, created_by)
select m.id, m.organization_id, r.id, 'active', m.user_profile_id
  from public.user_organization_memberships m
  join public.access_roles r
    on r.is_system = true
   and r.status = 'active'
   and r.organization_id is null
 where (r.name = 'admin'
        and m.user_profile_id in ('f6a19000-0000-4000-8000-000000000001',
                                  'f6a19000-0000-4000-8000-000000000003'))
    or (r.name = 'evaluator'
        and m.user_profile_id = 'f6a19000-0000-4000-8000-000000000002');

-- ----------------------------------------------------------------------------
-- Colaboradoras pelo PRIMITIVO canônico da F5-07 (nenhuma inserção manual em
-- `collaborators`/`collaborator_identifiers`): matrícula TEXTUAL (Issue #319).
-- ----------------------------------------------------------------------------
do $$
declare
  v_colab_alfa uuid;
  v_colab_beta uuid;
begin
  v_colab_beta := public.colaborador_criar(
    'f6a19000-0000-4000-8000-0000000000a2',      -- organização BETA
    'f6a19000-0000-4000-8000-000000000003',      -- ator: admin de BETA
    'f6a19000-0000-4000-8000-0000000000b2',      -- operation_id
    'Colaboradora Fictícia Beta', 'colaboradora.beta@example.invalid',
    'BETA001', null, null);

  v_colab_alfa := public.colaborador_criar(
    'f6a19000-0000-4000-8000-0000000000a1',      -- organização ALFA
    'f6a19000-0000-4000-8000-000000000001',      -- ator: admin de ALFA
    'f6a19000-0000-4000-8000-0000000000b1',      -- operation_id
    'Colaboradora Fictícia Alfa', 'colaboradora.alfa@example.invalid',
    'ACME002', null, null);

  if v_colab_alfa is null or v_colab_beta is null then
    raise exception '[FAIL] F6-A19 cenario: colaboradora nao criada pelo primitivo';
  end if;

  raise notice '[PASS] F6-A19 cenario: identidades sinteticas, admin legitimo em ALFA, admin de OUTRO tenant em BETA e colaboradoras ACME002/BETA001 criadas pelo primitivo';
end $$;
