-- F6-A23 / Issue #353: projeções soberanas com identidade funcional da posição.

create or replace view public.estrutura_administrativa as
select a.organization_id, a.pode_estrutura, a.pode_catalogo,
case when a.pode_estrutura then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,name,valid_from,valid_to,version from public.organizational_units where organization_id=a.organization_id)x) else '[]'::jsonb end as unidades,
case when a.pode_estrutura then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,unit_id,parent_unit_id,valid_from,valid_to,version from public.organizational_unit_parent_periods where organization_id=a.organization_id)x) else '[]'::jsonb end as periodos_parent,
case when a.pode_estrutura then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,name,unit_id,job_role_id,seniority_level_id,valid_from,valid_to,version from public.organizational_positions where organization_id=a.organization_id)x) else '[]'::jsonb end as posicoes,
case when a.pode_estrutura then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,subordinate_position_id,manager_position_id,reason,valid_from,valid_to,version from public.position_reporting_lines where organization_id=a.organization_id)x) else '[]'::jsonb end as reporting_lines,
case when a.pode_estrutura then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,collaborator_id,organizational_position_id,valid_from,valid_to,version from public.occupations where organization_id=a.organization_id)x) else '[]'::jsonb end as ocupacoes,
case when a.pode_estrutura then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,collaborator_id,valid_from,valid_to,version from public.collegiate_configurations where organization_id=a.organization_id)x) else '[]'::jsonb end as colegiados,
case when a.pode_estrutura then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select configuration_id,member_collaborator_id from public.collegiate_configuration_members where organization_id=a.organization_id)x) else '[]'::jsonb end as membros_colegiado,
case when a.pode_estrutura then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,full_name from public.collaborators where organization_id=a.organization_id)x) else '[]'::jsonb end as colaboradores,
case when a.pode_catalogo then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,code,name,status,version from public.job_roles where organization_id=a.organization_id)x) else '[]'::jsonb end as cargos,
case when a.pode_catalogo then (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (select id,name,status,version from public.seniority_levels where organization_id=a.organization_id)x) else '[]'::jsonb end as senioridades
from public.estrutura_autorizacao a where a.pode_estrutura or a.pode_catalogo;

create or replace view public.estrutura_pessoal as
with recursive base as (select a.organization_id,a.collaborator_id from public.estrutura_autorizacao a where a.collaborator_id is not null),
vigente_ocupacao as (select o.id,o.organization_id,o.collaborator_id,o.organizational_position_id,o.valid_from,o.valid_to,o.version from public.occupations o where o.valid_from<=now() and (o.valid_to is null or o.valid_to>now())),
vigente_reporting as (select r.id,r.organization_id,r.subordinate_position_id,r.manager_position_id,r.reason,r.valid_from,r.valid_to,r.version from public.position_reporting_lines r where r.valid_from<=now() and (r.valid_to is null or r.valid_to>now())),
vigente_posicao as (select p.id,p.organization_id,p.name,p.unit_id,p.job_role_id,p.seniority_level_id,p.valid_from,p.valid_to,p.version from public.organizational_positions p where p.valid_from<=now() and (p.valid_to is null or p.valid_to>now())),
vigente_colegiado as (select c.id,c.organization_id,c.collaborator_id,c.valid_from,c.valid_to,c.version from public.collegiate_configurations c where c.valid_from<=now() and (c.valid_to is null or c.valid_to>now())),
vigente_unidade as (select u.id,u.organization_id,u.name,u.valid_from,u.valid_to,u.version from public.organizational_units u where u.valid_from<=now() and (u.valid_to is null or u.valid_to>now())),
vigente_parent as (select pp.id,pp.organization_id,pp.unit_id,pp.parent_unit_id,pp.valid_from,pp.valid_to,pp.version from public.organizational_unit_parent_periods pp where pp.valid_from<=now() and (pp.valid_to is null or pp.valid_to>now())),
semente as (select b.organization_id,vo.organizational_position_id as pos from base b join vigente_ocupacao vo on vo.organization_id=b.organization_id and vo.collaborator_id=b.collaborator_id),
acima as (select organization_id,pos from semente union select vr.organization_id,vr.manager_position_id from vigente_reporting vr join acima a on a.organization_id=vr.organization_id and a.pos=vr.subordinate_position_id),
abaixo as (select organization_id,pos from semente union select vr.organization_id,vr.subordinate_position_id from vigente_reporting vr join abaixo a on a.organization_id=vr.organization_id and a.pos=vr.manager_position_id),
alcance as (select organization_id,pos from acima union select organization_id,pos from abaixo),
posicoes_alcance as (select distinct a.organization_id,a.pos from alcance a join vigente_posicao vp on vp.organization_id=a.organization_id and vp.id=a.pos),
colaboradores_alcance as (select b.organization_id,b.collaborator_id as cid from base b union select vo.organization_id,vo.collaborator_id from vigente_ocupacao vo join posicoes_alcance pa on pa.organization_id=vo.organization_id and pa.pos=vo.organizational_position_id)
select b.organization_id,b.collaborator_id,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select u.id,u.name,u.valid_from,u.valid_to,u.version from vigente_unidade u where u.organization_id=b.organization_id and u.id in(select vp.unit_id from vigente_posicao vp join posicoes_alcance pa on pa.organization_id=vp.organization_id and pa.pos=vp.id))x) as unidades,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select pp.id,pp.unit_id,pp.parent_unit_id,pp.valid_from,pp.valid_to,pp.version from vigente_parent pp where pp.organization_id=b.organization_id and pp.unit_id in(select vp.unit_id from vigente_posicao vp join posicoes_alcance pa on pa.organization_id=vp.organization_id and pa.pos=vp.id))x) as periodos_parent,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select vp.id,vp.name,vp.unit_id,vp.job_role_id,vp.seniority_level_id,vp.valid_from,vp.valid_to,vp.version from vigente_posicao vp join posicoes_alcance pa on pa.organization_id=vp.organization_id and pa.pos=vp.id)x) as posicoes,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select vr.id,vr.subordinate_position_id,vr.manager_position_id,vr.reason,vr.valid_from,vr.valid_to,vr.version from vigente_reporting vr where vr.organization_id=b.organization_id and vr.subordinate_position_id in(select pos from posicoes_alcance where organization_id=b.organization_id) and vr.manager_position_id in(select pos from posicoes_alcance where organization_id=b.organization_id))x) as reporting_lines,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select vo.id,vo.collaborator_id,vo.organizational_position_id,vo.valid_from,vo.valid_to,vo.version from vigente_ocupacao vo where vo.organization_id=b.organization_id and vo.collaborator_id in(select cid from colaboradores_alcance where organization_id=b.organization_id))x) as ocupacoes,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select vc.id,vc.collaborator_id,vc.valid_from,vc.valid_to,vc.version from vigente_colegiado vc where vc.organization_id=b.organization_id and vc.collaborator_id in(select cid from colaboradores_alcance where organization_id=b.organization_id))x) as colegiados,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select m.configuration_id,m.member_collaborator_id from public.collegiate_configuration_members m where m.organization_id=b.organization_id and m.configuration_id in(select vc.id from vigente_colegiado vc where vc.organization_id=b.organization_id and vc.collaborator_id in(select cid from colaboradores_alcance where organization_id=b.organization_id)))x) as membros_colegiado,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select c.id,c.full_name from public.collaborators c where c.organization_id=b.organization_id and c.id in(select cid from colaboradores_alcance where organization_id=b.organization_id))x) as colaboradores,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select j.id,j.code,j.name,j.status,j.version from public.job_roles j where j.organization_id=b.organization_id and j.id in(select vp.job_role_id from vigente_posicao vp join posicoes_alcance pa on pa.organization_id=vp.organization_id and pa.pos=vp.id))x) as cargos,
(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (select s.id,s.name,s.status,s.version from public.seniority_levels s where s.organization_id=b.organization_id and s.id in(select vp.seniority_level_id from vigente_posicao vp join posicoes_alcance pa on pa.organization_id=vp.organization_id and pa.pos=vp.id where vp.seniority_level_id is not null))x) as senioridades
from base b;

revoke all on public.estrutura_administrativa from public,anon,authenticated;
revoke all on public.estrutura_pessoal from public,anon,authenticated;
grant select on public.estrutura_administrativa to authenticated;
grant select on public.estrutura_pessoal to authenticated;

do $guard$
begin
  if position('organizational_positions.name' in pg_get_viewdef('public.estrutura_administrativa'::regclass,true))=0
     or position('vigente_posicao' in pg_get_viewdef('public.estrutura_pessoal'::regclass,true))=0
     or position('vp.name' in pg_get_viewdef('public.estrutura_pessoal'::regclass,true))=0 then raise exception 'F6_A23: projeção soberana sem name'; end if;
  if has_table_privilege('anon','public.estrutura_administrativa','SELECT') or has_table_privilege('anon','public.estrutura_pessoal','SELECT') then raise exception 'F6_A23: grant anon indevido'; end if;
  if not has_table_privilege('authenticated','public.estrutura_administrativa','SELECT') or not has_table_privilege('authenticated','public.estrutura_pessoal','SELECT') then raise exception 'F6_A23: grant authenticated ausente'; end if;
  raise notice '[PASS] F6-A23: views explícitas projetam organizational_positions.name com grants preservados';
end;
$guard$;
