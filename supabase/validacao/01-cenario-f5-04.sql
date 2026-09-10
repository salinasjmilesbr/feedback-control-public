-- ============================================================================
-- F5-04 (Issue #165): cenário sintético de validação — access roles e
-- capabilities reais (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma determinística e idempotente, o cenário local
-- usado pela validação 02-validar-f5-04.sql:
--
--   - duas organizações sintéticas (Alfa e Beta F5-04);
--   - perfis/memberships sintéticos: ADMIN_A (admin de Alfa, bootstrap via
--     conceder_acesso_role), USER_A (membro de Alfa), USER_B (membro de Beta),
--     SEM_MEMBRO (perfil ativo sem membership — p/ tenant revalidation);
--   - access_role customizada de Alfa `avaliadores` (capability
--     evaluation.read) para provar a concessão via RPC soberana (D16) e a
--     trilha append-only (D18).
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - Insere via superuser local; a RLS permanece intacta (nenhuma policy é
--     alterada). A validação do deny-by-default acontece na 02-validar-f5-04.sql.
--   - Reexecutável: remove/recria somente os UUIDs fixos (prefixo d5).
--   - Apenas dados sintéticos; nenhum dado real.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Remover o cenário anterior (ordem respeita FKs ON DELETE RESTRICT).
-- ----------------------------------------------------------------------------
delete from public.privilege_mutation_audit
where organization_id in (
  'd5a00000-0000-0000-0000-0000000000a1',
  'd5a00000-0000-0000-0000-0000000000b1'
);

delete from public.membership_access_role_assignments
where organization_id in (
  'd5a00000-0000-0000-0000-0000000000a1',
  'd5a00000-0000-0000-0000-0000000000b1'
);

delete from public.access_role_capabilities
where access_role_id = 'd5f00000-0000-0000-0000-0000000000f1';

delete from public.access_roles
where id = 'd5f00000-0000-0000-0000-0000000000f1';

delete from public.user_organization_memberships
where organization_id in (
  'd5a00000-0000-0000-0000-0000000000a1',
  'd5a00000-0000-0000-0000-0000000000b1'
);

delete from public.user_profiles
where id::text like 'd5b00000-0000-0000-0000-0000000000%';

delete from auth.users
where id::text like 'd5b00000-0000-0000-0000-0000000000%';

delete from public.organizations
where id in (
  'd5a00000-0000-0000-0000-0000000000a1',
  'd5a00000-0000-0000-0000-0000000000b1'
);

-- ----------------------------------------------------------------------------
-- Organizações sintéticas (F5-04)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name) values
  ('d5a00000-0000-0000-0000-0000000000a1', 'Org Sintetica F5-04 Alfa'),
  ('d5a00000-0000-0000-0000-0000000000b1', 'Org Sintetica F5-04 Beta');

-- ----------------------------------------------------------------------------
-- Identidades sintéticas (auth.users) + perfis internos
-- ----------------------------------------------------------------------------
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
   raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('d5b00000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin.a.f5-04@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d5b00000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'user.a.f5-04@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d5b00000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'user.b.f5-04@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d5b00000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sem.membro.f5-04@example.invalid', 'x', now(),
   '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.user_profiles (id, status) values
  ('d5b00000-0000-0000-0000-0000000000a1', 'active'),
  ('d5b00000-0000-0000-0000-0000000000a2', 'active'),
  ('d5b00000-0000-0000-0000-0000000000a3', 'active'),
  ('d5b00000-0000-0000-0000-0000000000a4', 'active');

-- ----------------------------------------------------------------------------
-- Memberships sintéticas (SEM_MEMBRO não possui membership)
-- ----------------------------------------------------------------------------
insert into public.user_organization_memberships
  (id, user_profile_id, organization_id, status)
values
  ('d5d00000-0000-0000-0000-0000000000a1', 'd5b00000-0000-0000-0000-0000000000a1',
   'd5a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d5d00000-0000-0000-0000-0000000000a2', 'd5b00000-0000-0000-0000-0000000000a2',
   'd5a00000-0000-0000-0000-0000000000a1', 'active'),
  ('d5d00000-0000-0000-0000-0000000000a3', 'd5b00000-0000-0000-0000-0000000000a3',
   'd5a00000-0000-0000-0000-0000000000b1', 'active');

-- ----------------------------------------------------------------------------
-- Access role customizada de Alfa: `avaliadores` (evaluation.read, grantable)
-- ----------------------------------------------------------------------------
insert into public.access_roles (id, name, status, is_system, organization_id)
values ('d5f00000-0000-0000-0000-0000000000f1', 'avaliadores', 'active', false,
        'd5a00000-0000-0000-0000-0000000000a1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select ar.id, c.id
  from public.access_roles ar
  cross join public.capabilities c
 where ar.id = 'd5f00000-0000-0000-0000-0000000000f1'
   and c.code = 'evaluation.read';

-- ----------------------------------------------------------------------------
-- Bootstrap: ADMIN_A recebe a role de sistema `admin` pelo primitivo F4-01
-- (conceder_acesso_role). A concessão via RPC soberana (auth.uid()) é exercitada
-- na validação 02-validar-f5-04.sql.
-- ----------------------------------------------------------------------------
select public.conceder_acesso_role(
  'd5d00000-0000-0000-0000-0000000000a1',
  'c0000000-0000-4000-8000-0000000000f1',
  'd5b00000-0000-0000-0000-0000000000a1'
);
