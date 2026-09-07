-- ============================================================================
-- F2-10 (Issue #77): cenário sintético de validação — múltiplas contas e
-- isolamento de identidade (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação integrada da F2-10:
--
--   - identidades Auth sintéticas distintas (UUIDs fixos e e-mails
--     @example.invalid) para ADMIN, A, B, C (sem membership), D (usada no
--     passo de usuário desabilitado) e E (usada no passo de membership
--     desabilitada);
--   - organizações sintéticas Alfa e Beta;
--   - perfis internos (user_profiles) e memberships
--     (user_organization_memberships) coerentes com o cenário da matriz;
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local de desenvolvimento (docker exec/psql
--     no banco local). Nunca em projeto remoto.
--   - Insere via superuser local (equivalente a service_role): a RLS permanece
--     intacta (nenhuma policy é alterada) — a validação do isolamento acontece
--     pelas chamadas autenticadas na etapa 02-validar-f2-10.mjs.
--   - Reexecutável: remove e recria somente os UUIDs fixos abaixo.
--   - Apenas dados sintéticos; nenhum dado real é utilizado.
-- ============================================================================

-- Remover o cenário anterior (somente os UUIDs fixos desta validação).
delete from public.user_organization_memberships
where user_profile_id in (
  'b0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-00000000000a',
  'b0000000-0000-0000-0000-00000000000b',
  'b0000000-0000-0000-0000-00000000000c',
  'b0000000-0000-0000-0000-00000000000d',
  'b0000000-0000-0000-0000-00000000000e'
) or organization_id in (
  'c0000000-0000-0000-0000-0000000000a1',
  'c0000000-0000-0000-0000-0000000000b1'
);

delete from public.user_profiles
where id in (
  'b0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-00000000000a',
  'b0000000-0000-0000-0000-00000000000b',
  'b0000000-0000-0000-0000-00000000000c',
  'b0000000-0000-0000-0000-00000000000d',
  'b0000000-0000-0000-0000-00000000000e'
);

delete from public.organizations
where id in (
  'c0000000-0000-0000-0000-0000000000a1',
  'c0000000-0000-0000-0000-0000000000b1'
);

-- auth.identities/auth.sessions/etc. possuem ON DELETE CASCADE para auth.users.
delete from auth.users
where id in (
  'b0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-00000000000a',
  'b0000000-0000-0000-0000-00000000000b',
  'b0000000-0000-0000-0000-00000000000c',
  'b0000000-0000-0000-0000-00000000000d',
  'b0000000-0000-0000-0000-00000000000e'
);

-- ----------------------------------------------------------------------------
-- Organizações sintéticas
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('c0000000-0000-0000-0000-0000000000a1', 'Org Sintetica Alfa (F2-10)'),
  ('c0000000-0000-0000-0000-0000000000b1', 'Org Sintetica Beta (F2-10)');

-- ----------------------------------------------------------------------------
-- Identidades Auth sintéticas (senhas determinísticas apenas de teste local)
-- ----------------------------------------------------------------------------
-- Senha local sintética compartilhada para o cenário: "virtus-senha-f2-10-local"
-- (nunca remota; os usuários só existem no banco local desta validação).
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token,
  reauthentication_token, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000001',
   'authenticated', 'authenticated', 'admin.f2-10@example.invalid',
   crypt('virtus-senha-f2-10-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000000a',
   'authenticated', 'authenticated', 'conta.a.f2-10@example.invalid',
   crypt('virtus-senha-f2-10-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000000b',
   'authenticated', 'authenticated', 'conta.b.f2-10@example.invalid',
   crypt('virtus-senha-f2-10-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000000c',
   'authenticated', 'authenticated', 'conta.c.f2-10@example.invalid',
   crypt('virtus-senha-f2-10-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000000d',
   'authenticated', 'authenticated', 'conta.d.f2-10@example.invalid',
   crypt('virtus-senha-f2-10-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-00000000000e',
   'authenticated', 'authenticated', 'conta.e.f2-10@example.invalid',
   crypt('virtus-senha-f2-10-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now());

-- ----------------------------------------------------------------------------
-- Identidades de provedor "email" (mesmo formato gerado pelo Auth Admin)
-- ----------------------------------------------------------------------------
insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select gen_random_uuid(), u.id, u.id::text,
       jsonb_build_object('sub', u.id::text, 'email', u.email),
       'email', now(), now(), now()
from auth.users u
where u.id in (
  'b0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-00000000000a',
  'b0000000-0000-0000-0000-00000000000b',
  'b0000000-0000-0000-0000-00000000000c',
  'b0000000-0000-0000-0000-00000000000d',
  'b0000000-0000-0000-0000-00000000000e'
);

-- ----------------------------------------------------------------------------
-- Perfis internos (todos ativos no início do cenário)
-- ----------------------------------------------------------------------------
insert into public.user_profiles (id, status) values
  ('b0000000-0000-0000-0000-000000000001', 'active'),
  ('b0000000-0000-0000-0000-00000000000a', 'active'),
  ('b0000000-0000-0000-0000-00000000000b', 'active'),
  ('b0000000-0000-0000-0000-00000000000c', 'active'),
  ('b0000000-0000-0000-0000-00000000000d', 'active'),
  ('b0000000-0000-0000-0000-00000000000e', 'active');

-- ----------------------------------------------------------------------------
-- Memberships (matriz inicial do cenário)
-- ----------------------------------------------------------------------------
--   ADMIN  -> Alfa  (ativa)      A -> Alfa (ativa)      B -> Beta (ativa)
--   C      -> nenhuma            D -> Beta (ativa)      E -> Alfa (ativa)
-- Os passos 8/9 da validação desativam D (usuário) e a membership de E.
insert into public.user_organization_memberships (user_profile_id, organization_id, status) values
  ('b0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-0000000000a1', 'active'),
  ('b0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000a1', 'active'),
  ('b0000000-0000-0000-0000-00000000000b', 'c0000000-0000-0000-0000-0000000000b1', 'active'),
  ('b0000000-0000-0000-0000-00000000000d', 'c0000000-0000-0000-0000-0000000000b1', 'active'),
  ('b0000000-0000-0000-0000-00000000000e', 'c0000000-0000-0000-0000-0000000000a1', 'active');
