-- F6-A22 P2 (#338): provas server-side do grant de posição.
-- Pré-requisito: 48-cenario-f6-a21-p2.sql + 51-cenario-f6-a22-p2.sql.
\set ON_ERROR_STOP on

-- O ator PESSOA_A (profile 2) ocupa d01; d04 é direto, d05 é descendente
-- estrutural, e d07 está fora da árvore.
set local role service_role;
do $$
declare v_n integer; v_edit integer; v_structure integer; v_origin integer;
begin
  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002',
      'f6a22000-0000-4000-8000-0000000000a1')
   where capability_code in ('collaborator.read','collaborator.create')
     and scope_type in ('DIRECT_REPORTS','DESCENDANTS')
     and grant_origin = 'position_responsibility:f6a22000-0000-4000-8000-000000000901';
  if v_n <> 4 then raise exception '[FAIL] ocupante vigente nao recebeu bundle/scopes: %', v_n; end if;

  select count(*) into v_edit from public.resolver_capabilities_escopos_efetivas(
    'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
   where capability_code = 'collaborator.edit';
  select count(*) into v_structure from public.resolver_capabilities_efetivas(
    'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
   where capability_code = 'org.structure.manage';
  select count(*) into v_origin from public.resolver_capabilities_escopos_efetivas(
    'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
   where grant_origin like 'position_responsibility:%';
  if v_edit <> 0 or v_structure <> 0 or v_origin <> 4 then
    raise exception '[FAIL] bundle ampliado ou origem divergente edit=% structure=% origin=%', v_edit, v_structure, v_origin;
  end if;
  raise notice '[PASS] ocupante vigente recebe read/create, scopes e origem; edit/structure.manage ausentes';
end $$;

do $$
declare v_n integer;
begin
  select count(*) into v_n from public.resolver_alvos_escopo(
    'f6a22000-0000-4000-8000-000000000002',
    'f6a22000-0000-4000-8000-0000000000a1','DIRECT_REPORTS',null,now())
   where collaborator_id = 'f6a22000-0000-4000-8000-000000000e06';
  if v_n <> 0 then raise exception '[FAIL] alvo inexistente/cross-tenant entrou no alcance'; end if;
  select count(*) into v_n from public.resolver_alvos_escopo(
    'f6a22000-0000-4000-8000-000000000002',
    'f6a22000-0000-4000-8000-0000000000a1','DIRECT_REPORTS',null,now())
   where position_id = 'f6a22000-0000-4000-8000-000000000d04';
  if v_n <> 1 then raise exception '[FAIL] alvo direto permitido nao resolvido'; end if;
  if exists (select 1 from public.resolver_alvos_escopo(
    'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1',
    'DESCENDANTS',null,now()) where position_id = 'f6a22000-0000-4000-8000-000000000d07') then
    raise exception '[FAIL] alvo fora do alcance foi resolvido';
  end if;
  raise notice '[PASS] alvo direto permitido; alvo fora da hierarquia negado';
end $$;

begin;
update public.organizational_position_responsibilities
   set status = 'revoked', valid_to = now()
 where id = 'f6a22000-0000-4000-8000-000000000901';
do $$ begin
  if exists (select 1 from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
      where grant_origin = 'position_responsibility:f6a22000-0000-4000-8000-000000000901') then
    raise exception '[FAIL] responsabilidade encerrada ainda concede';
  end if;
  raise notice '[PASS] responsabilidade encerrada remove efeito';
end $$;
rollback;

begin;
update public.occupations set valid_to = now()
 where id = 'f6a22000-0000-4000-8000-000000000f01';
do $$ begin
  if exists (select 1 from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
      where grant_origin = 'position_responsibility:f6a22000-0000-4000-8000-000000000901') then
    raise exception '[FAIL] ocupação encerrada ainda concede';
  end if;
  raise notice '[PASS] ocupação encerrada remove efeito';
end $$;
rollback;

do $$ begin
  if exists (select 1 from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a2')) then
    raise exception '[FAIL] cross-tenant produziu grant';
  end if;
  raise notice '[PASS] cross-tenant DENY';
end $$;

begin;
insert into public.organizational_position_responsibilities
  (id, organization_id, position_id, responsibility_code, valid_from, created_by)
values ('f6a22000-0000-4000-8000-000000000902',
        'f6a22000-0000-4000-8000-0000000000a1',
        'f6a22000-0000-4000-8000-000000000d03', 'PEOPLE_MANAGEMENT',
        '2026-01-01T00:00:00Z', 'f6a22000-0000-4000-8000-000000000001');
do $$ begin
  if exists (select 1 from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
      where grant_origin = 'position_responsibility:f6a22000-0000-4000-8000-000000000902') then
    raise exception '[FAIL] posição vaga produziu grant';
  end if;
  raise notice '[PASS] responsabilidade em posição vaga não produz grant';
end $$;
rollback;

begin;
update public.occupations set valid_to = now()
 where id = 'f6a22000-0000-4000-8000-000000000f01';
insert into public.collaborators (id, organization_id)
values ('f6a22000-0000-4000-8000-000000000e07', 'f6a22000-0000-4000-8000-0000000000a1');
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from)
values ('f6a22000-0000-4000-8000-000000000f07',
        'f6a22000-0000-4000-8000-0000000000a1',
        'f6a22000-0000-4000-8000-000000000e07',
        'f6a22000-0000-4000-8000-000000000d01',
        'troca de ocupante P2', now());
insert into public.membership_collaborator_links
  (membership_id, organization_id, collaborator_id, status)
select id, organization_id, 'f6a22000-0000-4000-8000-000000000e07', 'active'
  from public.user_organization_memberships
 where user_profile_id = 'f6a22000-0000-4000-8000-000000000003';
do $$ begin
  if exists (select 1 from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
      where grant_origin = 'position_responsibility:f6a22000-0000-4000-8000-000000000901') then
    raise exception '[FAIL] ocupante anterior reteve grant após troca';
  end if;
  if not exists (select 1 from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000003','f6a22000-0000-4000-8000-0000000000a1')
      where grant_origin = 'position_responsibility:f6a22000-0000-4000-8000-000000000901') then
    raise exception '[FAIL] novo ocupante não recebeu grant no intervalo vigente';
  end if;
  raise notice '[PASS] troca de ocupante remove o grant anterior e concede ao novo';
end $$;
rollback;

begin;
insert into public.occupations
  (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from)
values ('f6a22000-0000-4000-8000-000000000f08',
        'f6a22000-0000-4000-8000-0000000000a1',
        'f6a22000-0000-4000-8000-000000000e01',
        'f6a22000-0000-4000-8000-000000000d03',
        'ambiguidade ocupacional P2', '2026-01-01T00:00:00Z');
do $$ begin
  if exists (select 1 from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
      where grant_origin like 'position_responsibility:%') then
    raise exception '[FAIL] ambiguidade ocupacional foi deduplicada em vez de DENY';
  end if;
  raise notice '[PASS] ambiguidade ocupacional resulta em fail-closed';
end $$;
rollback;

begin;
-- Simula exclusivamente um estado legado/inconsistente: remove, dentro da
-- transação, as barreiras de unicidade do link e abre um segundo link ativo.
drop index public.uq_membership_collaborator_links_active_membership;
insert into public.membership_collaborator_links
  (membership_id, organization_id, collaborator_id, status)
select id, organization_id, 'f6a22000-0000-4000-8000-000000000e02', 'active'
  from public.user_organization_memberships
 where user_profile_id = 'f6a22000-0000-4000-8000-000000000002';
do $$ begin
  if exists (select 1 from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
      where grant_origin like 'position_responsibility:%') then
    raise exception '[FAIL] dois links ativos foram aceitos pela responsabilidade';
  end if;
  raise notice '[PASS] dois links ativos para colaboradores distintos resultam em DENY da responsabilidade';
end $$;
do $$ begin
  if exists (select 1 from public.resolver_capabilities_efetivas(
      'f6a22000-0000-4000-8000-000000000002','f6a22000-0000-4000-8000-0000000000a1')
      where capability_code in ('collaborator.read', 'collaborator.create')) then
    raise exception '[FAIL] dois links ativos concederam collaborator.read/create';
  end if;
  raise notice '[PASS] dois links ativos nao concedem read/create no resolver sem escopo';
end $$;
rollback;
reset role;
