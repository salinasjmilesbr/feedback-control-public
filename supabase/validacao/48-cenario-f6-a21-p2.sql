-- ============================================================================
-- F6-A21 P2 (Issue #327): cenário da EQUIVALÊNCIA TEMPORAL do subgrafo pessoal
-- ----------------------------------------------------------------------------
-- Grafo de ALFA (now() = instante do banco; encerrados terminam em 2026-06-01):
--
--   P_ATOR   (U1) ocupada por ATOR   (ocupação VIGENTE)
--   P_CHEFE  (U1) ocupada por CHEFE  (ocupação VIGENTE)  <- acima do ator
--   P_TOPO   (U1) VAGA                                  <- acima do chefe (vaga!)
--   P_SUB    (U2) ocupada por SUB    (ocupação VIGENTE)  <- abaixo do ator
--   P_ANTIGO (U2) ocupação ENCERRADA de ANTIGO; linha VIGENTE ANTIGO -> ATOR
--                 (posição entra no alcance; a PESSOA não, por ocupação encerrada)
--   P_FECHADA(U2) ocupação vigente de FECHADA, mas linha ENCERRADA FECHADA -> ATOR
--                 (nem posição nem pessoa entram)
--   P_ENCERRADA (U2) POSIÇÃO ENCERRADA, sem relação alguma: o banco PROÍBE
--                 relação aberta para posição encerrada (invariante estrutural)
--                 e proíbe duas relações sobrepostas na mesma subordinada, então
--                 o recorte de vigência de POSIÇÃO é defesa em profundidade
--   P_FORA   (U2) ocupada por FORA, sem qualquer relação com o ator
--
--   Colegiado de ATOR: 1 VIGENTE (membro CHEFE) e 1 ENCERRADO (membro FORA).
--
-- Esperado para PESSOA_A (vinculada a ATOR, sem capability):
--   posicoes = 5 (ATOR, CHEFE, TOPO, SUB, ANTIGO)
--   colaboradores = 3 (ATOR, CHEFE, SUB)   — sem ANTIGO/FECHADA/FORA
--   reporting_lines = 4 — sem a linha encerrada e sem a linha da posição encerrada
--   colegiados = 1 (só o vigente), membros_colegiado = 1 (CHEFE)
-- ============================================================================

\set ON_ERROR_STOP on

delete from public.membership_collaborator_links l
 where l.organization_id::text like 'f6a22000-%'
    or l.membership_id in (select m.id from public.user_organization_memberships m
                            where m.user_profile_id::text like 'f6a22000-%');
delete from public.collegiate_configuration_members where organization_id::text like 'f6a22000-%';
delete from public.collegiate_configurations where organization_id::text like 'f6a22000-%';
delete from public.position_reporting_lines where organization_id::text like 'f6a22000-%';
delete from public.occupations where organization_id::text like 'f6a22000-%';
delete from public.organizational_positions where organization_id::text like 'f6a22000-%';
delete from public.organizational_unit_parent_periods where organization_id::text like 'f6a22000-%';
delete from public.organizational_units where organization_id::text like 'f6a22000-%';
delete from public.collaborators where organization_id::text like 'f6a22000-%';
delete from public.seniority_levels where organization_id::text like 'f6a22000-%';
delete from public.job_roles where organization_id::text like 'f6a22000-%';
delete from public.membership_access_role_assignments
 where organization_id::text like 'f6a22000-%'
    or membership_id in (select m.id from public.user_organization_memberships m
                          where m.user_profile_id::text like 'f6a22000-%');
delete from public.user_organization_memberships
 where organization_id::text like 'f6a22000-%' or user_profile_id::text like 'f6a22000-%';
delete from public.user_profiles where id::text like 'f6a22000-%';
delete from public.organizations where id::text like 'f6a22000-%';
delete from auth.users where id::text like 'f6a22000-%';

insert into public.organizations (id, name) values
  ('f6a22000-0000-4000-8000-0000000000a1', 'F6-A21P2 Alfa'),
  ('f6a22000-0000-4000-8000-0000000000a2', 'F6-A21P2 Beta');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token,
  reauthentication_token, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', 'f6a22000-0000-4000-8000-000000000001',
   'authenticated', 'authenticated', 'admin.alfa.f6a22@example.invalid',
   crypt('virtus-senha-f6a22-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a22000-0000-4000-8000-000000000002',
   'authenticated', 'authenticated', 'pessoa.alfa.f6a22@example.invalid',
   crypt('virtus-senha-f6a22-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a22000-0000-4000-8000-000000000003',
   'authenticated', 'authenticated', 'carolina.f6a22@example.invalid',
   crypt('virtus-senha-f6a22-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'f6a22000-0000-4000-8000-000000000004',
   'authenticated', 'authenticated', 'admin.beta.f6a22@example.invalid',
   crypt('virtus-senha-f6a22-local', gen_salt('bf')), now(),
   '', '', '', '', '', '', '', '',
   '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.user_profiles (id, status) values
  ('f6a22000-0000-4000-8000-000000000001', 'active'),
  ('f6a22000-0000-4000-8000-000000000002', 'active'),
  ('f6a22000-0000-4000-8000-000000000003', 'active'),
  ('f6a22000-0000-4000-8000-000000000004', 'active');

insert into public.user_organization_memberships (user_profile_id, organization_id, status) values
  ('f6a22000-0000-4000-8000-000000000001', 'f6a22000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a22000-0000-4000-8000-000000000002', 'f6a22000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a22000-0000-4000-8000-000000000003', 'f6a22000-0000-4000-8000-0000000000a1', 'active'),
  ('f6a22000-0000-4000-8000-000000000004', 'f6a22000-0000-4000-8000-0000000000a2', 'active');

insert into public.membership_access_role_assignments
  (membership_id, organization_id, access_role_id, status, created_by)
select m.id, m.organization_id, r.id, 'active', m.user_profile_id
  from public.user_organization_memberships m
  join public.access_roles r
    on r.is_system = true and r.status = 'active' and r.organization_id is null and r.name = 'admin'
 where m.user_profile_id in ('f6a22000-0000-4000-8000-000000000001',
                             'f6a22000-0000-4000-8000-000000000004');

insert into public.job_roles (id, organization_id, name, code, status) values
  ('f6a22000-0000-4000-8000-000000000b01', 'f6a22000-0000-4000-8000-0000000000a1',
   'Cargo Fictício P2', 'F6A22A', 'active');
insert into public.seniority_levels (id, organization_id, name, status) values
  ('f6a22000-0000-4000-8000-000000000b11', 'f6a22000-0000-4000-8000-0000000000a1',
   'Senioridade Fictícia P2', 'active');

insert into public.organizational_units (id, organization_id, name, valid_from) values
  ('f6a22000-0000-4000-8000-000000000c01', 'f6a22000-0000-4000-8000-0000000000a1',
   'Unidade P2 1', '2026-01-01T00:00:00Z'),
  ('f6a22000-0000-4000-8000-000000000c02', 'f6a22000-0000-4000-8000-0000000000a1',
   'Unidade P2 2', '2026-01-01T00:00:00Z');

-- Posições: todas VIGENTES, exceto P_ENCERRADA (encerrada em 2026-06-01).
insert into public.organizational_positions
  (id, organization_id, unit_id, job_role_id, seniority_level_id, valid_from, valid_to) values
  ('f6a22000-0000-4000-8000-000000000d01', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000c01', 'f6a22000-0000-4000-8000-000000000b01',
   'f6a22000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000d02', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000c01', 'f6a22000-0000-4000-8000-000000000b01',
   'f6a22000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000d03', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000c01', 'f6a22000-0000-4000-8000-000000000b01',
   'f6a22000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000d04', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000c02', 'f6a22000-0000-4000-8000-000000000b01',
   'f6a22000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000d05', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000c02', 'f6a22000-0000-4000-8000-000000000b01',
   'f6a22000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000d06', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000c02', 'f6a22000-0000-4000-8000-000000000b01',
   'f6a22000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000d07', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000c02', 'f6a22000-0000-4000-8000-000000000b01',
   'f6a22000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000d08', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000c02', 'f6a22000-0000-4000-8000-000000000b01',
   'f6a22000-0000-4000-8000-000000000b11', '2026-01-01T00:00:00Z', '2026-06-01T00:00:00Z');

insert into public.collaborators (id, organization_id) values
  ('f6a22000-0000-4000-8000-000000000e01', 'f6a22000-0000-4000-8000-0000000000a1'),
  ('f6a22000-0000-4000-8000-000000000e02', 'f6a22000-0000-4000-8000-0000000000a1'),
  ('f6a22000-0000-4000-8000-000000000e03', 'f6a22000-0000-4000-8000-0000000000a1'),
  ('f6a22000-0000-4000-8000-000000000e04', 'f6a22000-0000-4000-8000-0000000000a1'),
  ('f6a22000-0000-4000-8000-000000000e05', 'f6a22000-0000-4000-8000-0000000000a1'),
  ('f6a22000-0000-4000-8000-000000000e06', 'f6a22000-0000-4000-8000-0000000000a1');

-- Ocupações: ATOR/CHEFE/SUB vigentes; ANTIGO ENCERRADA; FECHADA e FORA vigentes.
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from, valid_to) values
  ('f6a22000-0000-4000-8000-000000000f01', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e01', 'f6a22000-0000-4000-8000-000000000d01',
   'ator vigente', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000f02', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e02', 'f6a22000-0000-4000-8000-000000000d02',
   'chefe vigente', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000f03', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e03', 'f6a22000-0000-4000-8000-000000000d04',
   'sub vigente', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000f04', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e04', 'f6a22000-0000-4000-8000-000000000d05',
   'antigo ENCERRADA', '2026-01-01T00:00:00Z', '2026-06-01T00:00:00Z'),
  ('f6a22000-0000-4000-8000-000000000f05', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e05', 'f6a22000-0000-4000-8000-000000000d06',
   'fechada vigente', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000f06', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e06', 'f6a22000-0000-4000-8000-000000000d07',
   'fora vigente', '2026-01-01T00:00:00Z', null);

-- Reporting lines: 4 vigentes no alcance; 1 ENCERRADA; 1 ligada a posição encerrada.
insert into public.position_reporting_lines
  (id, organization_id, subordinate_position_id, manager_position_id, reason, valid_from, valid_to) values
  ('f6a22000-0000-4000-8000-000000000101', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000d01', 'f6a22000-0000-4000-8000-000000000d02',
   'ator -> chefe (vigente)', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000102', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000d04', 'f6a22000-0000-4000-8000-000000000d01',
   'sub -> ator (vigente)', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000103', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000d02', 'f6a22000-0000-4000-8000-000000000d03',
   'chefe -> topo VAGA (vigente)', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000104', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000d05', 'f6a22000-0000-4000-8000-000000000d01',
   'antigo -> ator (vigente, ocupacao encerrada)', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000105', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000d06', 'f6a22000-0000-4000-8000-000000000d01',
   'fechada -> ator ENCERRADA', '2026-01-01T00:00:00Z', '2026-06-01T00:00:00Z');

-- Colegiado: 1 VIGENTE (membro CHEFE) e 1 ENCERRADO (membro FORA).
insert into public.collegiate_configurations
  (id, organization_id, collaborator_id, valid_from, valid_to) values
  ('f6a22000-0000-4000-8000-000000000201', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e01', '2026-01-01T00:00:00Z', null),
  ('f6a22000-0000-4000-8000-000000000202', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e03', '2026-01-01T00:00:00Z', '2026-06-01T00:00:00Z');

insert into public.collegiate_configuration_members
  (configuration_id, organization_id, member_collaborator_id) values
  ('f6a22000-0000-4000-8000-000000000201', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e02'),
  ('f6a22000-0000-4000-8000-000000000202', 'f6a22000-0000-4000-8000-0000000000a1',
   'f6a22000-0000-4000-8000-000000000e06');

insert into public.membership_collaborator_links
  (membership_id, organization_id, collaborator_id, status)
select m.id, m.organization_id, 'f6a22000-0000-4000-8000-000000000e01', 'active'
  from public.user_organization_memberships m
 where m.user_profile_id = 'f6a22000-0000-4000-8000-000000000002'
   and m.organization_id = 'f6a22000-0000-4000-8000-0000000000a1';

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.position_reporting_lines
   where organization_id = 'f6a22000-0000-4000-8000-0000000000a1';
  if v_n <> 5 then
    raise exception '[FAIL] F6-A21 P2 cenario: reporting lines=% (esperado 5)', v_n;
  end if;
  select count(*) into v_n from public.organizational_positions
   where organization_id = 'f6a22000-0000-4000-8000-0000000000a1';
  if v_n <> 8 then
    raise exception '[FAIL] F6-A21 P2 cenario: posicoes=% (esperado 8)', v_n;
  end if;
  raise notice '[PASS] F6-A21 P2 cenario: 8 posicoes (1 encerrada sem relacao), 5 linhas (1 encerrada), vaga no meio, ocupacao encerrada, colegiado vigente+encerrado';
end $$;
