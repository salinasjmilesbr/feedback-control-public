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

begin;
insert into public.membership_collaborator_links
  (membership_id, organization_id, collaborator_id, status)
select m.id, m.organization_id, 'f6a22000-0000-4000-8000-000000000e02', 'active'
  from public.user_organization_memberships m
 where m.user_profile_id = 'f6a22000-0000-4000-8000-000000000003'
   and m.organization_id = 'f6a22000-0000-4000-8000-0000000000a1';

do $$
declare v_same_role boolean; v_with_people integer; v_without_people integer;
begin
  select p1.job_role_id = p2.job_role_id
    into v_same_role
    from public.organizational_positions p1
    join public.organizational_positions p2
      on p2.id = 'f6a22000-0000-4000-8000-000000000d02'
   where p1.id = 'f6a22000-0000-4000-8000-000000000d01';
  if v_same_role is distinct from true then
    raise exception '[FAIL] posições comparadas não reutilizam o mesmo cargo';
  end if;

  select count(*) into v_with_people
    from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000002',
      'f6a22000-0000-4000-8000-0000000000a1')
   where grant_origin = 'position_responsibility:f6a22000-0000-4000-8000-000000000901';
  select count(*) into v_without_people
    from public.resolver_capabilities_escopos_efetivas(
      'f6a22000-0000-4000-8000-000000000003',
      'f6a22000-0000-4000-8000-0000000000a1')
   where grant_origin like 'position_responsibility:%';
  if v_with_people <> 4 or v_without_people <> 0 then
    raise exception '[FAIL] mesmo cargo produziu efeito divergente inesperado: com=% sem=%',
      v_with_people, v_without_people;
  end if;
  raise notice '[PASS] mesmo cargo: posição com PEOPLE_MANAGEMENT concede 4 grants; ocupante da posição sem responsabilidade recebe 0 grants';
end $$;
rollback;

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
-- F6 / Issue #427 — JULGAMENTO: a segunda ocupação simultânea de e01 (em d03)
-- NÃO é mais representável. A exclusion `ex_occupations_collaborator_no_overlap`
-- recusa o INSERT (23P01), então o estado "ambíguo" que este bloco simulava NÃO
-- pode ser construído sem desabilitar constraint — o que é proibido. O bloco
-- preserva a INTENÇÃO (fail-closed diante de ambiguidade ocupacional) provando:
--   (1) o banco recusa a sobreposição (23P01) e NADA é persistido — a
--       ambiguidade é impedida na origem, que é o fail-closed mais forte; e
--   (2) o resolver continua NEGANDO grants de `position_responsibility` sempre
--       que a cardinalidade de ocupação do vínculo não é exatamente 1 (guarda
--       `ao.occupation_count = 1`), comportamento que a constraint não substitui.
do $$
declare
  v_ok boolean := false;
  v_state text := null;
  v_msg text := null;
  v_n int;
begin
  -- Pré-condição: e01 tem exatamente UMA ocupação vigente (f01 em d01).
  select count(*) into v_n
    from public.occupations
   where collaborator_id = 'f6a22000-0000-4000-8000-000000000e01'
     and organization_id = 'f6a22000-0000-4000-8000-0000000000a1'
     and valid_from <= now() and (valid_to is null or valid_to > now());
  if v_n <> 1 then
    raise exception '[FAIL] pre-condicao: e01 deveria ter 1 ocupacao vigente (tem %)', v_n;
  end if;

  begin
    insert into public.occupations
      (id, organization_id, collaborator_id, organizational_position_id, reason, valid_from)
    values ('f6a22000-0000-4000-8000-000000000f08',
            'f6a22000-0000-4000-8000-0000000000a1',
            'f6a22000-0000-4000-8000-000000000e01',
            'f6a22000-0000-4000-8000-000000000d03',
            'ambiguidade ocupacional P2 (recusada pela exclusion por colaborador)', '2026-01-01T00:00:00Z');
    raise exception '[FAIL] a segunda ocupacao simultanea de e01 foi ACEITA (ambiguidade construida)';
  exception
    when exclusion_violation then
      v_state := sqlstate; v_msg := sqlerrm; v_ok := true;
    when others then
      v_state := sqlstate; v_msg := sqlerrm;
  end;

  if not v_ok then
    raise exception '[FAIL] sobreposicao de ocupacao de e01 NAO foi recusada pela exclusion por colaborador (sqlstate=% msg=%)',
      coalesce(v_state, 'sem erro'), coalesce(v_msg, 'sem mensagem');
  end if;
  if v_msg is null
     or position('ex_occupations_collaborator_no_overlap' in v_msg) = 0 then
    raise exception '[FAIL] recusa de e01 nao veio da exclusion por colaborador (msg=%)', v_msg;
  end if;

  -- (1) Fail-closed na origem: nada de ambíguo persistiu.
  select count(*) into v_n
    from public.occupations
   where collaborator_id = 'f6a22000-0000-4000-8000-000000000e01'
     and organization_id = 'f6a22000-0000-4000-8000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] tentativa recusada deixou ocupacao persistida para e01 (tem %)', v_n;
  end if;
  raise notice '[PASS] ambiguidade ocupacional impedida na origem: segunda ocupacao de e01 recusada (23P01, ex_occupations_collaborator_no_overlap) sem persistir nada';
end $$;

-- (2) Guarda de cardinalidade do resolver preservada: a recusa de grants
-- `position_responsibility` exige `occupation_count = 1` do vínculo do ator
-- (`actor_occupations`), portanto o estado >1 jamais produziria união/escolha por
-- ordenação — o DENY por ambiguidade é intrínseco ao resolver, e não apenas um
-- efeito colateral da constraint.
do $$
declare
  v_guarda boolean := false;
begin
  select (position('occupation_count = 1' in p.prosrc) > 0)
    into v_guarda
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'resolver_capabilities_escopos_efetivas';
  if v_guarda is distinct from true then
    raise exception '[FAIL] resolver sem a guarda de cardinalidade (occupation_count = 1) de fail-closed';
  end if;
  raise notice '[PASS] ambiguidade ocupacional resulta em fail-closed (guarda de cardinalidade do resolver + barreira do banco)';
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
