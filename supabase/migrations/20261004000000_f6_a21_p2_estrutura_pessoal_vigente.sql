-- ============================================================================
-- F6-A21 P2 (Issue #327) — EQUIVALÊNCIA TEMPORAL DO SUBGRAFO PESSOAL
-- ----------------------------------------------------------------------------
-- `create or replace` de `estrutura_pessoal` (mesmas colunas do P1) para
-- reproduzir a MESMA semântica de vigência da projeção estrutural soberana
-- (`vigenteNaReferencia`, em `src/services/projecaoEstruturalSoberana.ts`):
-- modelo meio-aberto `[valid_from, valid_to)` na referência; a referência do
-- caminho pessoal é `now()` (o cliente usa `new Date()` como default).
--
-- O que muda (somente RESTRIÇÃO — nenhum dado novo é exposto):
--   1. a semente usa apenas OCUPAÇÕES VIGENTES do ator;
--   2. a travessia acima/abaixo usa apenas REPORTING LINES VIGENTES (posição
--      vaga no meio NÃO quebra a travessia: ela é por posição, não por ocupante);
--   3. o alcance contém apenas POSIÇÕES VIGENTES — posição encerrada não amplia;
--   4. os colaboradores do alcance entram por OCUPAÇÃO VIGENTE — ocupação
--      encerrada não amplia o alcance (histórico não vaza para o presente);
--   5. o colegiado considera apenas CONFIGURAÇÃO VIGENTE e seus membros;
--   6. unidades/períodos de parent apenas VIGENTES.
--
-- Invariantes: nenhuma capability/role nova, nenhum `SECURITY DEFINER`,
-- nenhum grant em tabela autorizativa, nenhuma escrita, nenhum histórico
-- devolvido como se fosse presente.
-- ============================================================================

create or replace view public.estrutura_pessoal as
with recursive base as (
  select a.organization_id, a.collaborator_id
    from public.estrutura_autorizacao a
   where a.collaborator_id is not null
),
vigente_ocupacao as (
  select o.id, o.organization_id, o.collaborator_id, o.organizational_position_id,
         o.valid_from, o.valid_to, o.version
    from public.occupations o
   where o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
),
vigente_reporting as (
  select r.id, r.organization_id, r.subordinate_position_id, r.manager_position_id,
         r.reason, r.valid_from, r.valid_to, r.version
    from public.position_reporting_lines r
   where r.valid_from <= now() and (r.valid_to is null or r.valid_to > now())
),
vigente_posicao as (
  select p.id, p.organization_id, p.unit_id, p.job_role_id, p.seniority_level_id,
         p.valid_from, p.valid_to, p.version
    from public.organizational_positions p
   where p.valid_from <= now() and (p.valid_to is null or p.valid_to > now())
),
vigente_colegiado as (
  select c.id, c.organization_id, c.collaborator_id, c.valid_from, c.valid_to, c.version
    from public.collegiate_configurations c
   where c.valid_from <= now() and (c.valid_to is null or c.valid_to > now())
),
vigente_unidade as (
  select u.id, u.organization_id, u.name, u.valid_from, u.valid_to, u.version
    from public.organizational_units u
   where u.valid_from <= now() and (u.valid_to is null or u.valid_to > now())
),
vigente_parent as (
  select pp.id, pp.organization_id, pp.unit_id, pp.parent_unit_id,
         pp.valid_from, pp.valid_to, pp.version
    from public.organizational_unit_parent_periods pp
   where pp.valid_from <= now() and (pp.valid_to is null or pp.valid_to > now())
),
semente as (
  select b.organization_id, vo.organizational_position_id as pos
    from base b
    join vigente_ocupacao vo
      on vo.organization_id = b.organization_id
     and vo.collaborator_id = b.collaborator_id
),
acima as (
  select organization_id, pos from semente
  union
  select vr.organization_id, vr.manager_position_id
    from vigente_reporting vr
    join acima a
      on a.organization_id = vr.organization_id
     and a.pos = vr.subordinate_position_id
),
abaixo as (
  select organization_id, pos from semente
  union
  select vr.organization_id, vr.subordinate_position_id
    from vigente_reporting vr
    join abaixo a
      on a.organization_id = vr.organization_id
     and a.pos = vr.manager_position_id
),
alcance as (
  select organization_id, pos from acima
  union
  select organization_id, pos from abaixo
),
posicoes_alcance as (
  select distinct a.organization_id, a.pos
    from alcance a
    join vigente_posicao vp
      on vp.organization_id = a.organization_id
     and vp.id = a.pos
),
colaboradores_alcance as (
  select b.organization_id, b.collaborator_id as cid from base b
  union
  select vo.organization_id, vo.collaborator_id
    from vigente_ocupacao vo
    join posicoes_alcance pa
      on pa.organization_id = vo.organization_id
     and pa.pos = vo.organizational_position_id
)
select
  b.organization_id,
  b.collaborator_id,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select u.id, u.name, u.valid_from, u.valid_to, u.version
        from vigente_unidade u
       where u.organization_id = b.organization_id
         and u.id in (
           select vp.unit_id from vigente_posicao vp
            join posicoes_alcance pa
              on pa.organization_id = vp.organization_id and pa.pos = vp.id)) x
  ) as unidades,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select pp.id, pp.unit_id, pp.parent_unit_id, pp.valid_from, pp.valid_to, pp.version
        from vigente_parent pp
       where pp.organization_id = b.organization_id
         and pp.unit_id in (
           select vp.unit_id from vigente_posicao vp
            join posicoes_alcance pa
              on pa.organization_id = vp.organization_id and pa.pos = vp.id)) x
  ) as periodos_parent,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select vp.id, vp.unit_id, vp.job_role_id, vp.seniority_level_id,
             vp.valid_from, vp.valid_to, vp.version
        from vigente_posicao vp
        join posicoes_alcance pa
          on pa.organization_id = vp.organization_id and pa.pos = vp.id) x
  ) as posicoes,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select vr.id, vr.subordinate_position_id, vr.manager_position_id, vr.reason,
             vr.valid_from, vr.valid_to, vr.version
        from vigente_reporting vr
       where vr.organization_id = b.organization_id
         and vr.subordinate_position_id in (
           select pos from posicoes_alcance where organization_id = b.organization_id)
         and vr.manager_position_id in (
           select pos from posicoes_alcance where organization_id = b.organization_id)) x
  ) as reporting_lines,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select vo.id, vo.collaborator_id, vo.organizational_position_id,
             vo.valid_from, vo.valid_to, vo.version
        from vigente_ocupacao vo
       where vo.organization_id = b.organization_id
         and vo.collaborator_id in (
           select cid from colaboradores_alcance where organization_id = b.organization_id)) x
  ) as ocupacoes,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select vc.id, vc.collaborator_id, vc.valid_from, vc.valid_to, vc.version
        from vigente_colegiado vc
       where vc.organization_id = b.organization_id
         and vc.collaborator_id in (
           select cid from colaboradores_alcance where organization_id = b.organization_id)) x
  ) as colegiados,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select m.configuration_id, m.member_collaborator_id
        from public.collegiate_configuration_members m
       where m.organization_id = b.organization_id
         and m.configuration_id in (
           select vc.id from vigente_colegiado vc
            where vc.organization_id = b.organization_id
              and vc.collaborator_id in (
                select cid from colaboradores_alcance where organization_id = b.organization_id))) x
  ) as membros_colegiado,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select c.id, c.full_name
        from public.collaborators c
       where c.organization_id = b.organization_id
         and c.id in (
           select cid from colaboradores_alcance where organization_id = b.organization_id)) x
  ) as colaboradores,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select j.id, j.code, j.name, j.status, j.version
        from public.job_roles j
       where j.organization_id = b.organization_id
         and j.id in (
           select vp.job_role_id from vigente_posicao vp
            join posicoes_alcance pa
              on pa.organization_id = vp.organization_id and pa.pos = vp.id)) x
  ) as cargos,
  (
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from (
      select s.id, s.name, s.status, s.version
        from public.seniority_levels s
       where s.organization_id = b.organization_id
         and s.id in (
           select vp.seniority_level_id from vigente_posicao vp
            join posicoes_alcance pa
              on pa.organization_id = vp.organization_id and pa.pos = vp.id
            where vp.seniority_level_id is not null)) x
  ) as senioridades
from base b;

comment on view public.estrutura_pessoal is
  'F6-A21 P2 (#327): SUBGRAFO estrutural VIGENTE do proprio ator (auth.uid) — '
  'vinculo soberano + cadeia de gestao acima/abaixo + colegiado vigente e '
  'pessoas alcancadas por OCUPACAO vigente. Modelo meio-aberto '
  '[valid_from, valid_to) na referencia now(), identico a vigenteNaReferencia da '
  'projecao estrutural (F5-08 P6). Historico encerrado NAO amplia o alcance; '
  'posicao vaga nao quebra a travessia (ela e por posicao). Nao exige capability '
  'administrativa e NAO devolve a fotografia do tenant.';

do $guarda$
declare
  v_n integer;
begin
  -- A view mantem as MESMAS colunas do P1 (create or replace exige equivalencia).
  select count(*) into v_n
    from information_schema.columns
   where table_schema = 'public' and table_name = 'estrutura_pessoal';
  if v_n <> 12 then
    raise exception 'F6_A21_P2: estrutura_pessoal deveria ter 12 colunas, tem %', v_n;
  end if;

  -- A definicao usa as seis fontes VIGENTES (nenhum historico entra).
  if position('vigente_ocupacao' in pg_get_viewdef('public.estrutura_pessoal'::regclass)) = 0
     or position('vigente_reporting' in pg_get_viewdef('public.estrutura_pessoal'::regclass)) = 0
     or position('vigente_posicao' in pg_get_viewdef('public.estrutura_pessoal'::regclass)) = 0
     or position('vigente_colegiado' in pg_get_viewdef('public.estrutura_pessoal'::regclass)) = 0 then
    raise exception 'F6_A21_P2: definicao sem os recortes de vigencia esperados';
  end if;

  -- Invariantes de plataforma preservadas.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_n <> 4 then
    raise exception 'F6_A21_P2: DEFINER esperado=4, encontrado=%', v_n;
  end if;

  raise notice '[PASS] F6-A21 P2: estrutura_pessoal restrita a relacoes/ocupacoes/posicoes/colegiado VIGENTES (now()), mesmas colunas do P1 e 4 DEFINER intactos';
end $guarda$;
