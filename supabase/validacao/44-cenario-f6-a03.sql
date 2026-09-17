-- ============================================================================
-- F6-A03 (Issue #266): cenário sintético — BOOTSTRAP DE PLATAFORMA
-- ----------------------------------------------------------------------------
-- Propósito: preparar, de forma DETERMINÍSTICA e RE-EXECUTÁVEL, as identidades
-- sintéticas usadas pelo validador `45-validar-f6-a03.sql`:
--
--   OPERADOR        (auth + user_profiles ATIVO)  — operador de plataforma;
--   FOUNDER         (auth, SEM perfil)            — exercita D16 (perfil criado);
--   OPERADOR_NOVO   (auth, SEM perfil/membership) — exercita D17 (ator sem perfil
--                                                   = ambiente VIRGEM admissível);
--   OPERADOR_INATIVO(auth + user_profiles disabled) — deve ser RECUSADO;
--   FOUNDER_INATIVO (auth + user_profiles disabled) — deve ser RECUSADO;
--   INEXISTENTE     (nenhuma identidade no Auth)   — deve ser RECUSADO (FK).
--
-- Estado PREEXISTENTE que o provisionamento NÃO pode tocar (critério 6):
--   LEGADO          organização + membership + atribuição `admin` do OPERADOR.
--
-- Regras:
--   - EXECUTAR SOMENTE no Supabase local (docker exec/psql). Nunca remoto.
--   - Insere via owner do schema (`postgres`), como os demais cenários: a RLS
--     permanece intacta (nenhuma policy é alterada).
--   - Apenas dados sintéticos (`@example.invalid`); nenhuma credencial real.
--   - Prefixo de UUID exclusivo `f6a3`; organizações criadas pelo validador são
--     identificadas por NOME (`F6-A03 %`) — o id é gerado pelo banco.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Limpeza idempotente (somente o que este cenário cria)
-- ----------------------------------------------------------------------------
delete from public.membership_access_role_assignments a
 using public.user_organization_memberships m
 where a.membership_id = m.id
   and (m.organization_id in (
          select o.id from public.organizations o
           where o.id = 'f6a30000-0000-4000-8000-0000000000a1' or o.name like 'F6-A03 %'
        )
        or m.user_profile_id in (
          'f6a30000-0000-4000-8000-000000000001','f6a30000-0000-4000-8000-000000000002',
          'f6a30000-0000-4000-8000-000000000003','f6a30000-0000-4000-8000-000000000004',
          'f6a30000-0000-4000-8000-000000000005'
        ));

delete from public.privilege_mutation_audit
 where organization_id in (
         select o.id from public.organizations o
          where o.id = 'f6a30000-0000-4000-8000-0000000000a1' or o.name like 'F6-A03 %'
       )
    or actor_user_profile_id in (
         'f6a30000-0000-4000-8000-000000000001','f6a30000-0000-4000-8000-000000000002',
         'f6a30000-0000-4000-8000-000000000003','f6a30000-0000-4000-8000-000000000004',
         'f6a30000-0000-4000-8000-000000000005');

delete from public.platform_provisioning_events
 where organization_name like 'F6-A03 %'
    or actor_user_profile_id in (
         'f6a30000-0000-4000-8000-000000000001','f6a30000-0000-4000-8000-000000000003',
         'f6a30000-0000-4000-8000-000000000004')
    or founder_user_profile_id in (
         'f6a30000-0000-4000-8000-000000000002','f6a30000-0000-4000-8000-000000000005');

delete from public.user_organization_memberships
 where organization_id in (
         select o.id from public.organizations o
          where o.id = 'f6a30000-0000-4000-8000-0000000000a1' or o.name like 'F6-A03 %'
       )
    or user_profile_id in (
         'f6a30000-0000-4000-8000-000000000001','f6a30000-0000-4000-8000-000000000002',
         'f6a30000-0000-4000-8000-000000000003','f6a30000-0000-4000-8000-000000000004',
         'f6a30000-0000-4000-8000-000000000005');

delete from public.user_profiles
 where id in (
   'f6a30000-0000-4000-8000-000000000001','f6a30000-0000-4000-8000-000000000002',
   'f6a30000-0000-4000-8000-000000000003','f6a30000-0000-4000-8000-000000000004',
   'f6a30000-0000-4000-8000-000000000005');

delete from public.organizations
 where id = 'f6a30000-0000-4000-8000-0000000000a1' or name like 'F6-A03 %';

delete from auth.users
 where id in (
   'f6a30000-0000-4000-8000-000000000001','f6a30000-0000-4000-8000-000000000002',
   'f6a30000-0000-4000-8000-000000000003','f6a30000-0000-4000-8000-000000000004',
   'f6a30000-0000-4000-8000-000000000005');

-- ----------------------------------------------------------------------------
-- Organização PREEXISTENTE (estado que o provisionamento não pode tocar)
-- ----------------------------------------------------------------------------
insert into public.organizations (id, name)
values ('f6a30000-0000-4000-8000-0000000000a1', 'F6-A03 Legado (preexistente)');

-- ----------------------------------------------------------------------------
-- Identidades Auth sintéticas
-- ----------------------------------------------------------------------------
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token,
  reauthentication_token, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'f6a30000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'operador.f6-a03@example.invalid',
   crypt('virtus-senha-f6-a03-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a30000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'founder.f6-a03@example.invalid',
   crypt('virtus-senha-f6-a03-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a30000-0000-4000-8000-000000000003',
   'authenticated', 'authenticated', 'operador.novo.f6-a03@example.invalid',
   crypt('virtus-senha-f6-a03-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a30000-0000-4000-8000-000000000004',
   'authenticated', 'authenticated', 'operador.inativo.f6-a03@example.invalid',
   crypt('virtus-senha-f6-a03-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a30000-0000-4000-8000-000000000005',
   'authenticated', 'authenticated', 'founder.inativo.f6-a03@example.invalid',
   crypt('virtus-senha-f6-a03-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now());

-- ----------------------------------------------------------------------------
-- Perfis internos: OPERADOR ativo, OPERADOR_INATIVO/FOUNDER_INATIVO disabled.
-- FOUNDER e OPERADOR_NOVO ficam SEM perfil de propósito (D16/D17).
-- ----------------------------------------------------------------------------
insert into public.user_profiles (id, status) values
  ('f6a30000-0000-4000-8000-000000000001', 'active'),
  ('f6a30000-0000-4000-8000-000000000004', 'disabled'),
  ('f6a30000-0000-4000-8000-000000000005', 'disabled');

-- ----------------------------------------------------------------------------
-- Estado PREEXISTENTE: OPERADOR é membro (e `admin`) da organização LEGADO.
-- ----------------------------------------------------------------------------
insert into public.user_organization_memberships (user_profile_id, organization_id, status)
values ('f6a30000-0000-4000-8000-000000000001', 'f6a30000-0000-4000-8000-0000000000a1', 'active');

insert into public.membership_access_role_assignments
  (membership_id, organization_id, access_role_id, status, created_by)
select m.id,
       'f6a30000-0000-4000-8000-0000000000a1',
       r.id,
       'active',
       'f6a30000-0000-4000-8000-000000000001'
  from public.user_organization_memberships m
  join public.access_roles r
    on r.name = 'admin' and r.is_system = true and r.organization_id is null
 where m.user_profile_id = 'f6a30000-0000-4000-8000-000000000001'
   and m.organization_id = 'f6a30000-0000-4000-8000-0000000000a1';

do $$
declare v_n integer;
begin
  select count(*) into v_n
    from public.platform_provisioning_events e
   where e.organization_name like 'F6-A03 %'
      or e.actor_user_profile_id::text like 'f6a30000-%'
      or e.founder_user_profile_id::text like 'f6a30000-%';
  if v_n <> 0 then
    raise exception '[FAIL] F6-A03 cenario: trilha remanescente (%)', v_n;
  end if;

  raise notice '[PASS] F6-A03 cenario: identidades sinteticas, organizacao LEGADO preexistente e trilha limpa';
end $$;
