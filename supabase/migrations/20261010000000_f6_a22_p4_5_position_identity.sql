-- #338 P4.5 — identidade funcional legível da posição.
-- A migration é deliberadamente fail-closed: um runtime com posições exige
-- nomeação explícita fora desta alteração; nunca recebe backfill inventado.
do $$
begin
  if exists (select 1 from public.organizational_positions) then
    raise exception 'F6_A22_P45: organizational_positions existentes exigem nomeação explícita; migration abortada';
  end if;
end;
$$;

alter table public.organizational_positions
  add column name text not null,
  add constraint ck_organizational_positions_name_normalized
    check (name = btrim(name) and name <> '' and char_length(name) <= 160);

comment on column public.organizational_positions.name is
  'P4.5: rotulo funcional obrigatório da posição; nunca identidade ou autoridade.';

-- Remove a assinatura sem nome: não há rota legada executável após P4.5.
drop function public.estrutura_posicao_criar(uuid, uuid, uuid, uuid, uuid, uuid, timestamptz, text);

create function public.estrutura_posicao_criar(
  p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid,
  p_unidade_id uuid, p_job_role_id uuid, p_seniority_level_id uuid,
  p_name text, p_valid_from timestamptz, p_motivo text
) returns uuid language plpgsql security invoker set search_path = public as $$
declare
  v_org uuid := p_organization_id; v_nome text := btrim(coalesce(p_name, ''));
  v_motivo text := btrim(coalesce(p_motivo, '')); v_hash text; v_evento record;
  v_membership uuid; v_unidade record; v_cargo record; v_senioridade record; v_id uuid;
begin
  if p_organization_id is null or p_operation_id is null or p_unidade_id is null or p_job_role_id is null then
    raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id, unidade_id e job_role_id obrigatorios';
  end if;
  if v_nome = '' or char_length(v_nome) > 160 then raise exception 'F5_08_INVALID_INPUT: nome da posicao obrigatorio e limitado a 160 caracteres'; end if;
  if p_valid_from is null then raise exception 'F5_08_INVALID_INPUT: valid_from obrigatorio'; end if;
  if v_motivo = '' then raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio'; end if;
  v_hash := encode(sha256(convert_to(jsonb_build_object('operacao','estrutura_posicao_criar','organization_id',v_org,'unidade_id',p_unidade_id,'job_role_id',p_job_role_id,'seniority_level_id',p_seniority_level_id,'name',v_nome,'valid_from',p_valid_from,'motivo',v_motivo)::text,'UTF8')),'hex');
  if not public.colaborador_ator_valido(p_actor_user_profile_id,v_org) then raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao'; end if;
  if not exists (select 1 from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id,v_org) where capability_code='org.structure.manage') then raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage'; end if;
  select e.payload_hash,e.result_entity_id,e.after_value into v_evento from public.structure_events e where e.organization_id=v_org and e.operation_id=p_operation_id;
  if found then if v_evento.payload_hash is distinct from v_hash then raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente'; end if; return v_evento.result_entity_id; end if;
  select m.id into v_membership from public.user_organization_memberships m where m.user_profile_id=p_actor_user_profile_id and m.organization_id=v_org and m.status='active';
  if v_membership is null then raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida'; end if;
  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:'||v_org::text));
  select u.id,u.valid_from,u.valid_to into v_unidade from public.organizational_units u where u.id=p_unidade_id and u.organization_id=v_org for update;
  if not found then raise exception 'F5_08_NOT_FOUND: unidade inexistente ou de outro tenant'; end if;
  if not (v_unidade.valid_from<=p_valid_from and (v_unidade.valid_to is null or v_unidade.valid_to>p_valid_from)) then raise exception 'F5_08_CONFLICT: unidade nao vigente na data informada'; end if;
  select j.id,j.status into v_cargo from public.job_roles j where j.id=p_job_role_id and j.organization_id=v_org;
  if not found then raise exception 'F5_08_NOT_FOUND: cargo inexistente ou de outro tenant'; end if;
  if v_cargo.status<>'active' then raise exception 'F5_08_CONFLICT: cargo inativo nao pode ser usado em nova posicao'; end if;
  if p_seniority_level_id is not null then
    select s.id,s.status into v_senioridade from public.seniority_levels s where s.id=p_seniority_level_id and s.organization_id=v_org;
    if not found then raise exception 'F5_08_NOT_FOUND: senioridade inexistente ou de outro tenant'; end if;
    if v_senioridade.status<>'active' then raise exception 'F5_08_CONFLICT: senioridade inativa nao pode ser usada em nova posicao'; end if;
  end if;
  insert into public.organizational_positions (organization_id,unit_id,job_role_id,seniority_level_id,name,valid_from) values (v_org,p_unidade_id,p_job_role_id,p_seniority_level_id,v_nome,p_valid_from) returning id into v_id;
  insert into public.structure_events (organization_id,entity_type,entity_id,event_type,effective_date,reason,before_value,after_value,payload_hash,result_entity_id,actor_user_profile_id,actor_membership_id,operation_id)
  values (v_org,'organizational_position',v_id,'CRIADO',p_valid_from,v_motivo,null,jsonb_build_object('name',v_nome,'unit_id',p_unidade_id,'job_role_id',p_job_role_id,'seniority_level_id',p_seniority_level_id,'valid_from',p_valid_from,'version',0),v_hash,v_id,p_actor_user_profile_id,v_membership,p_operation_id);
  return v_id;
end;
$$;

create function public.estrutura_posicao_renomear(
  p_organization_id uuid, p_actor_user_profile_id uuid, p_operation_id uuid,
  p_posicao_id uuid, p_name text, p_expected_version integer, p_motivo text
) returns integer language plpgsql security invoker set search_path = public as $$
declare
  v_org uuid:=p_organization_id; v_nome text:=btrim(coalesce(p_name,'')); v_motivo text:=btrim(coalesce(p_motivo,''));
  v_hash text; v_evento record; v_membership uuid; v_posicao record; v_nova_versao integer;
begin
  if p_organization_id is null or p_operation_id is null or p_posicao_id is null then raise exception 'F5_08_INVALID_INPUT: organization_id, operation_id e posicao_id obrigatorios'; end if;
  if v_nome='' or char_length(v_nome)>160 then raise exception 'F5_08_INVALID_INPUT: nome da posicao obrigatorio e limitado a 160 caracteres'; end if;
  if p_expected_version is null then raise exception 'F5_08_INVALID_INPUT: expected_version obrigatorio'; end if;
  if v_motivo='' then raise exception 'F5_08_INVALID_INPUT: motivo obrigatorio'; end if;
  v_hash:=encode(sha256(convert_to(jsonb_build_object('operacao','estrutura_posicao_renomear','organization_id',v_org,'posicao_id',p_posicao_id,'name',v_nome,'expected_version',p_expected_version,'motivo',v_motivo)::text,'UTF8')),'hex');
  if not public.colaborador_ator_valido(p_actor_user_profile_id,v_org) then raise exception 'F5_08_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao'; end if;
  if not exists(select 1 from public.resolver_capabilities_escopos_efetivas(p_actor_user_profile_id,v_org) where capability_code='org.structure.manage') then raise exception 'F5_08_FORBIDDEN: ator sem a capability org.structure.manage'; end if;
  select e.payload_hash,e.result_entity_id,e.after_value into v_evento from public.structure_events e where e.organization_id=v_org and e.operation_id=p_operation_id;
  if found then if v_evento.payload_hash is distinct from v_hash then raise exception 'F5_08_CONFLICT: operation_id ja utilizado com intencao diferente'; end if; return coalesce((v_evento.after_value->>'version')::integer,0); end if;
  select m.id into v_membership from public.user_organization_memberships m where m.user_profile_id=p_actor_user_profile_id and m.organization_id=v_org and m.status='active';
  if v_membership is null then raise exception 'F5_08_FORBIDDEN: membership ativa do ator nao resolvida'; end if;
  perform pg_advisory_xact_lock(hashtext('position_reporting_lines:'||v_org::text));
  select p.id,p.name,p.valid_to,p.version into v_posicao from public.organizational_positions p where p.id=p_posicao_id and p.organization_id=v_org for update;
  if not found then raise exception 'F5_08_NOT_FOUND: posicao inexistente ou de outro tenant'; end if;
  if v_posicao.valid_to is not null then raise exception 'F5_08_CONFLICT: posicao encerrada nao pode ser renomeada'; end if;
  if v_posicao.version<>p_expected_version then raise exception 'F5_08_CONFLICT: versao divergente (expected_version desatualizado)'; end if;
  if v_nome=v_posicao.name then raise exception 'F5_08_CONFLICT: o nome informado ja e o nome atual da posicao'; end if;
  update public.organizational_positions set name=v_nome,version=version+1 where id=p_posicao_id and organization_id=v_org returning version into v_nova_versao;
  insert into public.structure_events (organization_id,entity_type,entity_id,event_type,effective_date,reason,before_value,after_value,payload_hash,result_entity_id,actor_user_profile_id,actor_membership_id,operation_id)
  values(v_org,'organizational_position',p_posicao_id,'RENOMEADO',now(),v_motivo,jsonb_build_object('name',v_posicao.name,'version',v_posicao.version),jsonb_build_object('name',v_nome,'version',v_nova_versao),v_hash,p_posicao_id,p_actor_user_profile_id,v_membership,p_operation_id);
  return v_nova_versao;
end;
$$;

revoke all on function public.estrutura_posicao_criar(uuid,uuid,uuid,uuid,uuid,uuid,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.estrutura_posicao_criar(uuid,uuid,uuid,uuid,uuid,uuid,text,timestamptz,text) to service_role;
revoke all on function public.estrutura_posicao_renomear(uuid,uuid,uuid,uuid,text,integer,text) from public,anon,authenticated;
grant execute on function public.estrutura_posicao_renomear(uuid,uuid,uuid,uuid,text,integer,text) to service_role;

-- As views continuam a ser a única superfície de leitura. A definição anterior
-- é conferida antes da alteração para evitar publicação silenciosa de projeção
-- parcial em uma base divergente.
do $$
declare v_def text;
begin
  select pg_get_viewdef('public.estrutura_administrativa'::regclass, true) into v_def;
  if position('unit_id' in v_def) = 0 or position('job_role_id' in v_def) = 0 then
    raise exception 'F6_A22_P45: definição inesperada de estrutura_administrativa';
  end if;
  v_def := regexp_replace(v_def, 'id,\s+unit_id,\s+job_role_id,\s+seniority_level_id', 'id, name, unit_id, job_role_id, seniority_level_id');
  v_def := regexp_replace(v_def, 'p\.id,\s+p\.unit_id,\s+p\.job_role_id,\s+p\.seniority_level_id', 'p.id, p.name, p.unit_id, p.job_role_id, p.seniority_level_id');
  execute 'create or replace view public.estrutura_administrativa as ' || v_def;
  select pg_get_viewdef('public.estrutura_pessoal'::regclass, true) into v_def;
  if position('p.unit_id' in v_def) = 0 or position('p.job_role_id' in v_def) = 0 then
    raise exception 'F6_A22_P45: definição inesperada de estrutura_pessoal';
  end if;
  v_def := regexp_replace(v_def, 'p\.id,\s+p\.unit_id,\s+p\.job_role_id,\s+p\.seniority_level_id', 'p.id, p.name, p.unit_id, p.job_role_id, p.seniority_level_id');
  execute 'create or replace view public.estrutura_pessoal as ' || v_def;
end;
$$;
