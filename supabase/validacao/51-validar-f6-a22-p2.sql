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
reset role;
