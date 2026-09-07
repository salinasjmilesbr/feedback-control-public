-- ============================================================================
-- F3-07 (Issue #84): resolução organizacional — gestor, subordinados e escopo
-- estrutural por data
-- ----------------------------------------------------------------------------
-- Propósito: criar a camada canônica de resolução estrutural (serviços/queries
-- de domínio) que deriva, para uma data fornecida pelo chamador, a estrutura
-- vigente SEM armazenar campos redundantes de gestor direto. Usa como fontes:
--   - organizational_positions;
--   - position_reporting_lines (hierarquia formal entre posições);
--   - occupations (titular canônico);
--   - temporary_responsibilities (substituto, distinguível do titular).
--
-- Decisões técnicas registradas (Issue #84 e revisão de escopo desta etapa):
--   - interface: funções SQL públicas `RETURNS TABLE`, `SECURITY INVOKER`,
--     `STABLE`, `set search_path = public`; NENHUM grant adicional a
--     anon/authenticated/service_role (o RLS deny-by-default atual permanece
--     integral; `service_role`/superuser resolvem internamente); sem bypass de
--     tenant isolation e sem views materializadas; a camada estabelece a
--     semântica canônica, sem expor superfície privilegiada — autorização e RLS
--     futuros poderão reutilizar/encapsular esta lógica explicitamente;
--   - gestor direto é DERIVADO da estrutura (reporting line + occupation), nunca
--     de campo no colaborador nem de cargo/senioridade;
--   - titular × substituto (Q2): para cada posição/data são retornados
--     `titular` (occupation vigente), `substitute` (temporary responsibility
--     vigente de tipo operational/operational_evaluative) e
--     `responsible` = substituto operacional > titular > NULL (posição vaga);
--     `evaluative` isolado NÃO participa da resolução operacional; titular e
--     substituto permanecem consultáveis separadamente;
--   - status do colaborador (Q3): NÃO é filtro adicional — leave mantém a
--     occupation; inactive corretamente encerrado deixa de resolver pela
--     ausência de occupation válida (F3-05), não por filtro de status;
--   - posição superior vaga é estruturalmente válida: a cadeia continua a ser
--     percorrida pela reporting line mesmo sem ocupante, retornando
--     `responsible = NULL` quando não há substituto;
--   - múltiplas occupations de um colaborador produzem UNIÃO coerente de escopo
--     (linhas por posição ocupada e por descendentes estruturais);
--   - colegiado/dotted line NÃO entram no escopo hierárquico (inexistentes).
--
-- Fora do escopo (não antecipar): autorização por capability, RLS final de
-- recursos, composição de colegiado, snapshot de ciclo, resolução avaliativa
-- definitiva.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Responsável de uma posição em uma data (titular / substituto / efetivo)
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_responsavel_posicao(
  p_position_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid
)
language sql
stable
set search_path = public
as $$
  with titular as (
    select collaborator_id
    from public.occupations
    where organizational_position_id = p_position_id
      and valid_from <= p_data
      and (valid_to is null or valid_to > p_data)
    limit 1
  ),
  substituto as (
    select substitute_collaborator_id
    from public.temporary_responsibilities
    where organizational_position_id = p_position_id
      and responsibility_type in ('operational', 'operational_evaluative')
      and valid_from <= p_data
      and valid_to > p_data
    limit 1
  )
  select
    p_position_id,
    (select collaborator_id from titular),
    (select substitute_collaborator_id from substituto),
    coalesce(
      (select substitute_collaborator_id from substituto),
      (select collaborator_id from titular)
    )
$$;

comment on function public.organizacao_resolver_responsavel_posicao(uuid, timestamptz) is
  'F3-07: resolve titular (occupation), substituto operacional (temporary '
  'responsibility operational/operational_evaluative) e responsavel efetivo '
  '(substituto > titular > NULL) de uma posicao em uma data.';

-- ----------------------------------------------------------------------------
-- 2) Gestor formal direto de um colaborador em uma data
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_gestor_direto(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  occupied_position_id uuid,
  manager_position_id uuid,
  manager_titular_collaborator_id uuid,
  manager_substitute_collaborator_id uuid,
  manager_responsible_collaborator_id uuid
)
language sql
stable
set search_path = public
as $$
  select
    occ.organizational_position_id,
    rl.manager_position_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id
  from public.occupations occ
  join public.position_reporting_lines rl
    on rl.subordinate_position_id = occ.organizational_position_id
   and rl.valid_from <= p_data
   and (rl.valid_to is null or rl.valid_to > p_data)
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    rl.manager_position_id, p_data
  ) r
  where occ.collaborator_id = p_collaborator_id
    and occ.valid_from <= p_data
    and (occ.valid_to is null or occ.valid_to > p_data)
$$;

comment on function public.organizacao_resolver_gestor_direto(uuid, timestamptz) is
  'F3-07: resolve o gestor formal direto de um colaborador em uma data, por '
  'posicao ocupada (reporting line + responsavel da posicao superior; vazio se '
  'raiz/sem superior).';

-- ----------------------------------------------------------------------------
-- 3) Subordinados diretos de um colaborador em uma data
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_subordinados_diretos(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  subordinate_position_id uuid,
  subordinate_titular_collaborator_id uuid,
  subordinate_substitute_collaborator_id uuid,
  subordinate_responsible_collaborator_id uuid
)
language sql
stable
set search_path = public
as $$
  select distinct
    rl.subordinate_position_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id
  from public.position_reporting_lines rl
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    rl.subordinate_position_id, p_data
  ) r
  where rl.valid_from <= p_data
    and (rl.valid_to is null or rl.valid_to > p_data)
    and exists (
      select 1
      from public.occupations occ
      where occ.collaborator_id = p_collaborator_id
        and occ.organizational_position_id = rl.manager_position_id
        and occ.valid_from <= p_data
        and (occ.valid_to is null or occ.valid_to > p_data)
    )
$$;

comment on function public.organizacao_resolver_subordinados_diretos(uuid, timestamptz) is
  'F3-07: resolve as posicoes que reportam diretamente a alguma posicao ocupada '
  'pelo colaborador em uma data, com titular/substituto/responsavel de cada '
  'subordinado.';

-- ----------------------------------------------------------------------------
-- 4) Descendentes estruturais de um colaborador em uma data
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_descendentes(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid,
  depth integer
)
language sql
stable
set search_path = public
as $$
  with recursive base as (
    select occ.organizational_position_id as pos_id, 0::int as depth
    from public.occupations occ
    where occ.collaborator_id = p_collaborator_id
      and occ.valid_from <= p_data
      and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  descend as (
    select rl.subordinate_position_id as pos_id, b.depth + 1 as depth
    from base b
    join public.position_reporting_lines rl
      on rl.manager_position_id = b.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
    union
    select rl.subordinate_position_id, d.depth + 1
    from descend d
    join public.position_reporting_lines rl
      on rl.manager_position_id = d.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
  )
  select distinct on (d.pos_id)
    d.pos_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id,
    d.depth
  from descend d
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    d.pos_id, p_data
  ) r
  order by d.pos_id, d.depth
$$;

comment on function public.organizacao_resolver_descendentes(uuid, timestamptz) is
  'F3-07: resolve as posicoes descendentes (transitivas) sob as posicoes '
  'ocupadas pelo colaborador em uma data, com profundidade e responsavel de '
  'cada posicao.';

-- ----------------------------------------------------------------------------
-- 5) Cadeia hierárquica ascendente de um colaborador em uma data
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_cadeia(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid,
  depth integer
)
language sql
stable
set search_path = public
as $$
  with recursive base as (
    select occ.organizational_position_id as pos_id, 0::int as depth
    from public.occupations occ
    where occ.collaborator_id = p_collaborator_id
      and occ.valid_from <= p_data
      and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  upstream as (
    select b.pos_id, b.depth from base b
    union
    select rl.manager_position_id, u.depth + 1
    from upstream u
    join public.position_reporting_lines rl
      on rl.subordinate_position_id = u.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
  )
  select distinct on (u.pos_id)
    u.pos_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id,
    u.depth
  from upstream u
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    u.pos_id, p_data
  ) r
  order by u.pos_id, u.depth
$$;

comment on function public.organizacao_resolver_cadeia(uuid, timestamptz) is
  'F3-07: resolve a cadeia hierarquica ascendente (posicoes ocupadas + '
  'ancestrais pela reporting line, inclusive posicoes vagas) com responsavel '
  'por posicao.';

-- ----------------------------------------------------------------------------
-- 6) Escopo estrutural (posições) sob responsabilidade de um colaborador
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_escopo_posicoes(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  position_id uuid,
  unit_id uuid,
  titular_collaborator_id uuid,
  substitute_collaborator_id uuid,
  responsible_collaborator_id uuid,
  is_own_position boolean
)
language sql
stable
set search_path = public
as $$
  with recursive own as (
    select occ.organizational_position_id as pos_id
    from public.occupations occ
    where occ.collaborator_id = p_collaborator_id
      and occ.valid_from <= p_data
      and (occ.valid_to is null or occ.valid_to > p_data)
  ),
  descend as (
    select rl.subordinate_position_id as pos_id
    from own o
    join public.position_reporting_lines rl
      on rl.manager_position_id = o.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
    union
    select rl.subordinate_position_id
    from descend d
    join public.position_reporting_lines rl
      on rl.manager_position_id = d.pos_id
     and rl.valid_from <= p_data
     and (rl.valid_to is null or rl.valid_to > p_data)
  ),
  escopo as (
    select pos_id, true as propria from own
    union
    select pos_id, false as propria from descend
  )
  select distinct on (e.pos_id)
    e.pos_id,
    p.unit_id,
    r.titular_collaborator_id,
    r.substitute_collaborator_id,
    r.responsible_collaborator_id,
    e.propria
  from escopo e
  join public.organizational_positions p on p.id = e.pos_id
  cross join lateral public.organizacao_resolver_responsavel_posicao(
    e.pos_id, p_data
  ) r
  order by e.pos_id, e.propria desc
$$;

comment on function public.organizacao_resolver_escopo_posicoes(uuid, timestamptz) is
  'F3-07: uniao coerente das posicoes sob responsabilidade do colaborador em '
  'uma data (proprias ocupadas + descendentes estruturais), com unidade e '
  'responsavel de cada posicao.';

-- ----------------------------------------------------------------------------
-- 7) Escopo estrutural (unidades) sob responsabilidade de um colaborador
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_resolver_escopo_unidades(
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  unit_id uuid
)
language sql
stable
set search_path = public
as $$
  select distinct e.unit_id
  from public.organizacao_resolver_escopo_posicoes(p_collaborator_id, p_data) e
  where e.unit_id is not null
$$;

comment on function public.organizacao_resolver_escopo_unidades(uuid, timestamptz) is
  'F3-07: unidades (distintas) sob responsabilidade do colaborador em uma '
  'data, derivadas do escopo de posicoes.';

-- ----------------------------------------------------------------------------
-- Nota de segurança/grants
-- ----------------------------------------------------------------------------
-- As funções são SECURITY INVOKER e NÃO recebem grants adicionais: mantêm o
-- grant EXECUTE padrão (PUBLIC) do PostgreSQL, mas — por serem INVOKER — ficam
-- sujeitas ao RLS deny-by-default atual (anon/authenticated não leem as tabelas
-- de domínio, portanto não obtêm dados; service_role/superuser resolvem
-- internamente). Nenhuma superfície privilegiada nem bypass de tenant
-- isolation é introduzido nesta issue.
