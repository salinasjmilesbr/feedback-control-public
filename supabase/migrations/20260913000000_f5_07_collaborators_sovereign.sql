-- ============================================================================
-- F5-07 (Etapa 5): colaboradores e historico organizacional soberanos
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-07-desenho-tecnico.md (D1-D20 FECHADAS) e espinha de
-- interfaces congelada (.git/F5-07_SPINE.md, §1.1-§1.4).
--
-- Este arquivo entrega a parte ESTRUTURAL e de LEITURA:
--   §1  extensoes aditivas de `collaborators` (D3: dados de pessoa sem
--       temporalidade propria — a evolucao fica no log append-only);
--   §2  extensao aditiva `job_roles.code` (D5: rotulo operacional estavel;
--       NUNCA autorizacao, hierarquia ou escopo);
--   §3  `collaborator_events` (D8: log APPEND-ONLY da MUDANCA — o estado em
--       cada data continua nas tabelas temporais F3);
--   §4  RLS/grants do log (D12/I11: SELECT own-tenant, nenhuma policy de
--       escrita, escrita somente pelo caminho server-side);
--   §5  helper `colaborador_ator_valido` (D27/F5-06: service_role EXECUTA e
--       nunca decide; a funcao revalida perfil ativo + membership ativa);
--   §6  projecao soberana de leitura (D2/D4/D7: matricula da linha ABERTA,
--       status vigente na data, estrutura da OCUPACAO vigente e gestor
--       DERIVADO — nada de coluna desnormalizada);
--   §7  grants (funcoes somente service_role; tabelas minimas por operacao).
--
-- As RPCs de mutacao estao em `20260913010000_f5_07_collaborators_rpc.sql`.
--
-- Padrao de seguranca (identico a F5-02/F5-04/F5-06): SECURITY INVOKER,
-- `set search_path = public`, `revoke all ... from public, anon, authenticated`
-- + `grant execute ... to service_role`, ZERO SECURITY DEFINER novo (I12).
-- Nenhuma policy/grant existente e enfraquecida; nada de capability nova.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) `collaborators` — extensao aditiva de dados de pessoa (D3)
-- ----------------------------------------------------------------------------
-- Nome/e-mail NAO sao autoridade, hierarquia nem prova de identidade (I4/I8);
-- nao recebem vigencia propria porque a evolucao ja fica registrada no log
-- append-only (§3) — a alternativa "tabela temporal de pessoa" foi rejeitada
-- em D3. As colunas entram preenchidas de forma DETERMINISTICA antes de
-- `not null`, de modo que uma base ja povoada (ou vazia) continue valida e
-- nenhum registro existente seja perdido: o backfill e um no-op em base vazia.
alter table public.collaborators add column if not exists full_name text;
alter table public.collaborators add column if not exists email text;
alter table public.collaborators add column if not exists admission_date date;

update public.collaborators
   set full_name = 'Colaborador ' || right(id::text, 12)
 where full_name is null;

update public.collaborators
   set email = 'colaborador+' || id::text || '@example.invalid'
 where email is null;

alter table public.collaborators alter column full_name set not null;
alter table public.collaborators alter column email set not null;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'ck_collaborators_full_name'
       and conrelid = 'public.collaborators'::regclass
  ) then
    alter table public.collaborators
      add constraint ck_collaborators_full_name
      check (full_name <> '' and full_name = btrim(full_name));
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conname = 'ck_collaborators_email'
       and conrelid = 'public.collaborators'::regclass
  ) then
    alter table public.collaborators
      add constraint ck_collaborators_email
      check (email <> '' and email = btrim(email) and position('@' in email) > 1);
  end if;
end $$;

-- Unicidade de e-mail por organizacao, case-insensitive. Indice funcional
-- unico (a convencao F1-02 exige constraint para unicidade de colunas, mas o
-- contrato fixa a expressao `lower(email)`; mesmo padrao dos indices unicos
-- funcionais/parciais ja usados na F5-06). Sem predicado parcial: o estado
-- "desligado" e temporal (collaborator_status_periods), nao uma coluna desta
-- tabela, e o indice parcial exigiria desnormalizar status (proibido por D4).
create unique index if not exists uq_collaborators_org_email
  on public.collaborators (organization_id, lower(email));

comment on column public.collaborators.full_name is
  'F5-07 D3: nome canonico da pessoa. Nao e autoridade, nao e hierarquia e nao '
  'tem vigencia propria; a evolucao fica registrada em collaborator_events.';
comment on column public.collaborators.email is
  'F5-07 D3: contato da pessoa. Unico por organizacao em lower(email); nao e '
  'prova de identidade nem de autorizacao.';
comment on column public.collaborators.admission_date is
  'F5-07 D3/D6: admissao DECLARADA (dado de cadastro). A vigencia soberana de '
  'status e identificador continua em collaborator_status_periods e '
  'collaborator_identifiers.';
comment on constraint ck_collaborators_full_name on public.collaborators is
  'F5-07: nome nao vazio e sem espacos nas bordas.';
comment on constraint ck_collaborators_email on public.collaborators is
  'F5-07: e-mail nao vazio, sem espacos nas bordas e com @ em posicao > 1.';

-- Compatibilidade do caminho LEGADO de escrita (fixtures e validadores F3/F4/
-- F5-02/F5-06 que inserem `collaborators (id, organization_id)`): as colunas
-- novas entram `not null` (D3) e o trigger abaixo preenche valor SINTETICO
-- DETERMINISTICO — a MESMA regra do backfill acima — quando o caminho de
-- escrita nao informa dado de pessoa. Nao e dado real, nao e autoridade e nao
-- substitui `colaborador_criar` (que sempre informa os campos). Sem este
-- guard, toda fixture anterior quebraria no `db reset` do CI.
create or replace function public.colaborador_pessoa_sintetica()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.full_name is null then
    new.full_name := 'Colaborador ' || right(new.id::text, 12);
  end if;
  if new.email is null then
    new.email := 'colaborador+' || new.id::text || '@example.invalid';
  end if;
  return new;
end;
$$;

comment on function public.colaborador_pessoa_sintetica() is
  'F5-07 D3: preenche full_name/email com valor sintetico deterministico quando '
  'o caminho legado de escrita nao informa dado de pessoa (preserva fixtures '
  'anteriores com as colunas not null). O caminho soberano sempre informa.';

create trigger trg_collaborators_pessoa_sintetica
  before insert on public.collaborators
  for each row execute function public.colaborador_pessoa_sintetica();

-- ----------------------------------------------------------------------------
-- 2) `job_roles.code` — rotulo operacional estavel (D5)
-- ----------------------------------------------------------------------------
-- Uso PERMITIDO: rotulo/UX e compatibilidade com o `funcao` legado.
-- Uso PROIBIDO: autorizacao, hierarquia, escopo, requisito de avaliador ou
-- qualquer decisao do Policy Engine (T-22 prova o negativo). O codigo nao
-- substitui o nome e NUNCA renomeia item de catalogo.
alter table public.job_roles add column if not exists code text;

-- Backfill DETERMINISTICO por organizacao: `upper(btrim(name))` para os cinco
-- rotulos do baseline, somente quando o nome casar apos normalizacao de caixa.
-- O `not exists` de irmao equivalente evita que dois nomes distintos com o
-- mesmo rotulo normalizado (ex.: 'Gerente' e 'GERENTE') disputem o mesmo code:
-- nesse caso AMBOS ficam sem code (nunca escolhe arbitrariamente).
update public.job_roles jr
   set code = upper(btrim(jr.name))
 where jr.code is null
   and upper(btrim(jr.name)) in (
     'GERENTE', 'COORDENADOR', 'CONSULTOR', 'ANALISTA', 'ESTAGIARIO')
   and not exists (
     select 1
       from public.job_roles jr2
      where jr2.organization_id = jr.organization_id
        and jr2.id <> jr.id
        and upper(btrim(jr2.name)) = upper(btrim(jr.name))
   );

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'ck_job_roles_code'
       and conrelid = 'public.job_roles'::regclass
  ) then
    alter table public.job_roles
      add constraint ck_job_roles_code
      check (code is null or (code <> '' and code = btrim(code) and code = upper(code)));
  end if;
end $$;

create unique index if not exists uq_job_roles_org_code
  on public.job_roles (organization_id, code)
  where code is not null;

comment on column public.job_roles.code is
  'F5-07 D5: rotulo operacional estavel do catalogo (ex.: GERENTE, ANALISTA). '
  'Unico por organizacao quando nao nulo. NUNCA e autorizacao, hierarquia, '
  'escopo nem requisito de avaliador — nenhuma decisao do Policy Engine pode '
  'consultar esta coluna.';
comment on constraint ck_job_roles_code on public.job_roles is
  'F5-07 D5: code nao vazio, sem espacos nas bordas e em caixa alta.';

-- ----------------------------------------------------------------------------
-- 3) `collaborator_events` — log APPEND-ONLY da mudanca (D8)
-- ----------------------------------------------------------------------------
-- Duas verdades complementares (contrato §11.1): as tabelas temporais F3
-- respondem "qual era o estado em cada data"; este log responde "quem mudou,
-- quando, por que, com que escopo de ciclo e qual era o valor anterior".
-- O log NUNCA substitui o estado atual nem e autoridade de tenant/ator:
-- `before_value`/`after_value` sao registro, nao fonte de decisao.
--
-- Unique de REFERENCIA aditivo para a FK composta de tenant
-- `(actor_membership_id, organization_id)` — mesmo padrao aditivo ja usado na
-- F3-04 (`uq_organizational_positions_id_organization`). Nada muda na tabela.
do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'uq_user_organization_memberships_id_organization'
       and conrelid = 'public.user_organization_memberships'::regclass
  ) then
    alter table public.user_organization_memberships
      add constraint uq_user_organization_memberships_id_organization
      unique (id, organization_id);
  end if;
end $$;

create table public.collaborator_events (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null,
  collaborator_id       uuid,
  position_id           uuid,
  event_type            text        not null,
  effective_date        timestamptz not null,
  cycle_scope           text        not null default 'CICLO_ATUAL_E_POSTERIORES',
  reference_cycle_id    uuid,
  reason                text        not null,
  before_value          jsonb,
  after_value           jsonb,
  payload_hash          text,
  result_entity_id      uuid,
  actor_user_profile_id uuid        not null,
  actor_membership_id   uuid        not null,
  operation_id          uuid        not null,
  created_at            timestamptz not null default now(),
  constraint pk_collaborator_events primary key (id),
  -- Exatamente as 4 FKs do contrato congelado (espinha §1.2): colaborador,
  -- ciclo de referencia, ator e membership do ator. `position_id` e o alvo
  -- registrado dos eventos posicao x posicao (reporting line) e nao tem FK —
  -- o tenant ja e amarrado pelas duas FKs compostas abaixo.
  constraint fk_collaborator_events_collaborators
    foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict,
  constraint fk_collaborator_events_cycle
    foreign key (reference_cycle_id, organization_id)
    references public.evaluation_cycles (id, organization_id)
    on delete restrict,
  constraint fk_collaborator_events_actor
    foreign key (actor_user_profile_id)
    references public.user_profiles (id)
    on delete restrict,
  constraint fk_collaborator_events_actor_membership
    foreign key (actor_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict,
  -- Idempotencia (D13): retry de rede com o mesmo operation_id nao duplica
  -- evento nem mutacao; payload divergente e recusado pela RPC.
  constraint uq_collaborator_events_org_operation
    unique (organization_id, operation_id),
  constraint ck_collaborator_events_type
    check (event_type in (
      'ADMISSAO', 'DADOS_PESSOAIS_ALTERADOS', 'IDENTIFICADOR_DEFINIDO',
      'IDENTIFICADOR_ENCERRADO', 'STATUS_ALTERADO', 'OCUPACAO_INICIADA',
      'OCUPACAO_ENCERRADA', 'REPORTING_LINE_INICIADA', 'REPORTING_LINE_ENCERRADA',
      'RESPONSABILIDADE_INICIADA', 'RESPONSABILIDADE_ENCERRADA',
      'SUCESSAO_REGISTRADA',
      -- Desvio ADITIVO registrado (ver bloco 11 da migration de RPCs): o
      -- bootstrap de catalogo (D16) e operacao de ORGANIZACAO sem alvo de
      -- colaborador/posicao; sem um tipo proprio, a regra "toda mutacao grava
      -- evento na mesma transacao" seria impossivel de cumprir.
      'CATALOGO_ATUALIZADO')),
  constraint ck_collaborator_events_cycle_scope
    check (cycle_scope in ('CICLO_ATUAL_E_POSTERIORES', 'SOMENTE_CICLOS_POSTERIORES')),
  constraint ck_collaborator_events_reason
    check (reason <> '' and reason = btrim(reason)),
  -- Todo evento DE ENTIDADE tem um alvo REAL: colaborador (eventos de pessoa,
  -- status e ocupacao) ou posicao (estrutura posicao x posicao). O unico
  -- evento sem alvo de entidade e o de CATALOGO da organizacao.
  constraint ck_collaborator_events_alvo
    check (
      (event_type = 'CATALOGO_ATUALIZADO'
        and collaborator_id is null and position_id is null)
      or (event_type <> 'CATALOGO_ATUALIZADO'
        and num_nonnulls(collaborator_id, position_id) >= 1)
    )
);

comment on table public.collaborator_events is
  'F5-07 D8: log APPEND-ONLY das mudancas de colaborador e da estrutura '
  'relacionada. O estado em cada data continua nas tabelas temporais F3; o log '
  'registra autor soberano, motivo, vigencia, escopo de ciclo e delta '
  'estruturado. Evento e mutacao na MESMA transacao; UPDATE tem trigger de '
  'excecao e o caminho server-side recebe somente SELECT/INSERT.';
comment on column public.collaborator_events.effective_date is
  'F5-07 D8: data de EFEITO da mudanca (intencao validada), nunca a data de '
  'gravacao; `created_at` registra quando o fato foi gravado.';
comment on column public.collaborator_events.cycle_scope is
  'F5-07 §11.2: preserva a regra de baseline "vale do ciclo atual em diante" '
  '(CICLO_ATUAL_E_POSTERIORES) ou "somente ciclos posteriores". A APLICACAO da '
  'regra a um ciclo concreto e da F5-09.';
comment on column public.collaborator_events.reference_cycle_id is
  'F5-07 §11.2/D8: ciclo de referencia (evaluation_cycles) da movimentacao; '
  'opcional e sempre validado contra o tenant (FK composta).';
comment on column public.collaborator_events.payload_hash is
  'F5-07 D13: md5 do jsonb normalizado da INTENCAO. Mesmo operation_id + mesmo '
  'hash devolve o mesmo resultado; hash diferente e CONFLICT (nunca adivinha).';
comment on column public.collaborator_events.result_entity_id is
  'F5-07 D13: entidade resultante da operacao (colaborador, ocupacao, '
  'reporting line ou responsabilidade) usada na repeticao idempotente.';
comment on column public.collaborator_events.before_value is
  'F5-07 D8: registro do delta (valor anterior). NAO e fonte de decisao, nao e '
  'autoridade de tenant nem de ator.';

create index ix_collaborator_events_collaborator_id
  on public.collaborator_events (collaborator_id);
create index ix_collaborator_events_organization_id
  on public.collaborator_events (organization_id);

-- Append-only no BANCO (nao apenas na aplicacao): UPDATE levanta excecao.
-- DELETE e barrado pela ausencia de grant ao caminho server-side (D12/§10.3).
create or replace function public.enforce_collaborator_events_append_only()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  raise exception 'F5-07: collaborator_events e append-only (UPDATE negado)';
end;
$$;

comment on function public.enforce_collaborator_events_append_only() is
  'F5-07 D8: impede UPDATE da trilha de colaborador/historico organizacional '
  '(append-only); DELETE nao e concedido ao caminho server-side.';

create trigger trg_collaborator_events_append_only
  before update on public.collaborator_events
  for each row execute function public.enforce_collaborator_events_append_only();

-- ----------------------------------------------------------------------------
-- 4) RLS e grants de `collaborator_events` (D12/§10.2/§10.3)
-- ----------------------------------------------------------------------------
-- Policy SELECT own-tenant (mesmo padrao da F4-08): a RLS responde "o dado
-- pertence ao tenant do ator?" — a decisao "pode ler o historico?" continua
-- sendo do Policy Engine/RPC. NENHUMA policy de INSERT/UPDATE/DELETE: mutacao
-- so pelo caminho server-side.
--
-- Grants: SOMENTE service_role (select, insert). `authenticated` mantem a
-- policy (contrato §10.2) mas NAO recebe SELECT: a leitura de historico passa
-- pela RPC `colaborador_historico_listar` (espinha §1.2). UPDATE/DELETE nunca
-- sao concedidos.
alter table public.collaborator_events enable row level security;

create policy collaborator_events_select_same_tenant on public.collaborator_events
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

revoke all on public.collaborator_events from public, anon, authenticated, service_role;
grant select, insert on public.collaborator_events to service_role;
revoke update, delete on public.collaborator_events from service_role;

-- ----------------------------------------------------------------------------
-- 5) Helper de ator (D27/F5-06) — revalidacao server-side em toda operacao
-- ----------------------------------------------------------------------------
-- `service_role` executa e NAO decide: a decisao de autorizacao e do Policy
-- Engine/plano administrativo na fronteira confiavel (I9). Este helper e a
-- defesa em profundidade no BANCO: perfil ATIVO + membership ATIVA no tenant.
create or replace function public.colaborador_ator_valido(
  p_actor_user_profile_id uuid,
  p_organization_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    p_actor_user_profile_id is not null
    and p_organization_id is not null
    and exists (
      select 1
        from public.user_organization_memberships m
        join public.user_profiles up on up.id = m.user_profile_id
       where m.user_profile_id = p_actor_user_profile_id
         and m.organization_id = p_organization_id
         and m.status = 'active'
         and up.status = 'active'
    );
$$;

comment on function public.colaborador_ator_valido(uuid, uuid) is
  'F5-07 D27: revalida o ator soberano (user_profile ativo + membership ativa '
  'no tenant) em toda operacao server-side. Revogacao vale na operacao '
  'seguinte (I10). Nao substitui o Policy Engine; e defesa em profundidade.';

-- ----------------------------------------------------------------------------
-- 6) Leitura soberana (D2/D4/D7) — SECURITY INVOKER, STABLE, service_role
-- ----------------------------------------------------------------------------
-- Regras (contrato §6.5 e espinha §1.4):
--   - identidade = collaborators.id (UUID); matricula e INTENCAO de leitura;
--   - matricula = linha ABERTA de collaborator_identifiers (valid_to is null);
--   - status vigente NA DATA pedida (a fronteira entrega a data de referencia);
--   - estrutura derivada da OCUPACAO vigente na data — nunca coluna do
--     colaborador nem texto de cargo (I4);
--   - gestor DERIVADO por organizacao_resolver_gestor_direto (F3-07, I4);
--   - ausencia de status/ocupacao => NULL (nunca erro, nunca invencao — I7);
--   - colaborador de outro tenant => vazio/NOT_FOUND (indistinguivel).
create or replace function public.colaborador_visao_listar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_data timestamptz,
  p_filtros jsonb
)
returns table (
  collaborator_id uuid,
  matricula text,
  full_name text,
  email text,
  status text,
  admission_date date,
  unit_id uuid,
  unit_name text,
  job_role_code text,
  job_role_name text,
  seniority_name text,
  manager_collaborator_id uuid,
  manager_full_name text,
  version integer
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_data    timestamptz := coalesce(p_data, now());
  v_filtros jsonb       := coalesce(p_filtros, '{}'::jsonb);
  v_status  text;
  v_busca   text;
  v_unit    uuid;
  v_collab  uuid;
begin
  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if jsonb_typeof(v_filtros) <> 'object' then
    raise exception 'F5_07_INVALID_INPUT: p_filtros deve ser um objeto JSON';
  end if;

  v_status := nullif(btrim(coalesce(v_filtros ->> 'status', '')), '');
  if v_status is not null and v_status not in ('active', 'leave', 'inactive') then
    raise exception 'F5_07_INVALID_INPUT: filtro status invalido (active, leave ou inactive)';
  end if;

  if nullif(btrim(coalesce(v_filtros ->> 'unit_id', '')), '') is not null then
    begin
      v_unit := (v_filtros ->> 'unit_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'F5_07_INVALID_INPUT: filtro unit_id nao e UUID valido';
    end;
  end if;

  -- Filtro INTERNO por UUID: usado por `colaborador_visao_obter` para nao
  -- duplicar a projecao. A fronteira confiavel (Edge) nunca o envia — o
  -- contrato externo de `p_filtros` e apenas status/unit_id/busca.
  if nullif(btrim(coalesce(v_filtros ->> 'collaborator_id', '')), '') is not null then
    begin
      v_collab := (v_filtros ->> 'collaborator_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'F5_07_INVALID_INPUT: filtro collaborator_id nao e UUID valido';
    end;
  end if;

  v_busca := nullif(btrim(coalesce(v_filtros ->> 'busca', '')), '');

  return query
  select
    c.id,
    ident.business_code,
    c.full_name,
    c.email,
    sta.status,
    c.admission_date,
    est.pos_unit_id,
    est.pos_unit_name,
    est.pos_job_role_code,
    est.pos_job_role_name,
    est.pos_seniority_name,
    gest.manager_responsible_collaborator_id,
    gest.full_name,
    c.version
  from public.collaborators c
  left join lateral (
    select i.business_code
      from public.collaborator_identifiers i
     where i.collaborator_id = c.id
       and i.valid_to is null
     order by i.valid_from desc, i.id
     limit 1
  ) ident on true
  left join lateral (
    select sp.status
      from public.collaborator_status_periods sp
     where sp.collaborator_id = c.id
       and sp.valid_from <= v_data
       and (sp.valid_to is null or sp.valid_to > v_data)
     order by sp.valid_from desc, sp.id
     limit 1
  ) sta on true
  left join lateral (
    select p.unit_id as pos_unit_id,
           u.name    as pos_unit_name,
           jr.code   as pos_job_role_code,
           jr.name   as pos_job_role_name,
           sl.name   as pos_seniority_name
      from public.occupations o
      join public.organizational_positions p
        on p.id = o.organizational_position_id
       and p.organization_id = c.organization_id
      join public.organizational_units u
        on u.id = p.unit_id
       and u.organization_id = c.organization_id
      join public.job_roles jr
        on jr.id = p.job_role_id
       and jr.organization_id = c.organization_id
      left join public.seniority_levels sl
        on sl.id = p.seniority_level_id
       and sl.organization_id = c.organization_id
     where o.collaborator_id = c.id
       and o.organization_id = c.organization_id
       and o.valid_from <= v_data
       and (o.valid_to is null or o.valid_to > v_data)
     order by o.valid_from desc, o.id
     limit 1
  ) est on true
  left join lateral (
    select g.manager_responsible_collaborator_id, mgr.full_name
      from public.organizacao_resolver_gestor_direto(c.id, v_data) g
      join public.collaborators mgr
        on mgr.id = g.manager_responsible_collaborator_id
     order by g.occupied_position_id, g.manager_position_id
     limit 1
  ) gest on true
  where c.organization_id = p_organization_id
    and (v_collab is null or c.id = v_collab)
    and (v_status is null or sta.status = v_status)
    and (v_unit is null or est.pos_unit_id = v_unit)
    and (
      v_busca is null
      or c.full_name ilike '%' || v_busca || '%'
      or c.email ilike '%' || v_busca || '%'
      or coalesce(ident.business_code, '') ilike '%' || v_busca || '%'
    )
  order by c.full_name, c.id;
end;
$$;

comment on function public.colaborador_visao_listar(uuid, uuid, timestamptz, jsonb) is
  'F5-07 D2/D4/D7: projecao soberana da lista de colaboradores do tenant. '
  'Matricula da linha ABERTA, status vigente na data, estrutura derivada da '
  'ocupacao vigente (unidade/job_role/senioridade) e gestor DERIVADO por '
  'organizacao_resolver_gestor_direto. Nao escreve, nao migra e nao inventa '
  'registro (I7). Filtros externos: status, unit_id e busca (nome/email/'
  'matricula, ILIKE). EXECUTE somente service_role.';

create or replace function public.colaborador_visao_obter(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_collaborator_id uuid,
  p_data timestamptz
)
returns table (
  collaborator_id uuid,
  matricula text,
  full_name text,
  email text,
  status text,
  admission_date date,
  unit_id uuid,
  unit_name text,
  job_role_code text,
  job_role_name text,
  seniority_name text,
  manager_collaborator_id uuid,
  manager_full_name text,
  version integer
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if p_collaborator_id is null then
    raise exception 'F5_07_INVALID_INPUT: collaborator_id obrigatorio';
  end if;

  -- Mesma projecao da lista (fonte unica, sem duplicar regra de derivacao).
  -- Vazio quando o colaborador nao existe OU pertence a outro tenant
  -- (indistinguivel — fail-closed).
  return query
  select l.*
    from public.colaborador_visao_listar(
      p_organization_id,
      p_actor_user_profile_id,
      p_data,
      jsonb_build_object('collaborator_id', p_collaborator_id)
    ) l;
end;
$$;

comment on function public.colaborador_visao_obter(uuid, uuid, uuid, timestamptz) is
  'F5-07 D2: projecao soberana de UM colaborador (por UUID). Reusa a lista '
  'como fonte unica de derivacao; devolve vazio para inexistente ou de outro '
  'tenant (fail-closed, indistinguivel de negacao). EXECUTE somente '
  'service_role.';

create or replace function public.colaborador_resolver_matricula(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_matricula text
)
returns uuid
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_qtd int;
  v_id  uuid;
begin
  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  if p_matricula is null or btrim(p_matricula) = '' then
    raise exception 'F5_07_INVALID_INPUT: matricula obrigatoria (intencao a resolver)';
  end if;

  -- Ponte matricula -> UUID (D2) resolvida pela linha ABERTA. Zero ou mais de
  -- uma linha aberta devolve NULL: a funcao NUNCA escolhe arbitrariamente.
  select count(*) into v_qtd
    from public.collaborator_identifiers i
   where i.organization_id = p_organization_id
     and i.business_code = btrim(p_matricula)
     and i.valid_to is null;

  if v_qtd <> 1 then
    return null;
  end if;

  select i.collaborator_id into v_id
    from public.collaborator_identifiers i
   where i.organization_id = p_organization_id
     and i.business_code = btrim(p_matricula)
     and i.valid_to is null;

  return v_id;
end;
$$;

comment on function public.colaborador_resolver_matricula(uuid, uuid, text) is
  'F5-07 D2: ponte INTENCAO matricula -> identidade UUID, resolvida pela linha '
  'ABERTA de collaborator_identifiers (valid_to is null). Zero ou mais de uma '
  'linha aberta devolve NULL (nunca escolhe arbitrariamente; a fronteira trata '
  'ausencia/ambiguidade como NOT_FOUND). EXECUTE somente service_role.';

create or replace function public.colaborador_historico_listar(
  p_organization_id uuid,
  p_actor_user_profile_id uuid,
  p_collaborator_id uuid
)
returns table (
  event_id uuid,
  event_type text,
  effective_date timestamptz,
  reason text,
  cycle_scope text,
  reference_cycle_id uuid,
  actor_user_profile_id uuid,
  actor_full_name text,
  before_value jsonb,
  after_value jsonb,
  created_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if p_collaborator_id is null then
    raise exception 'F5_07_INVALID_INPUT: collaborator_id obrigatorio';
  end if;

  if not public.colaborador_ator_valido(p_actor_user_profile_id, p_organization_id) then
    raise exception 'F5_07_FORBIDDEN: ator sem perfil ativo e membership ativa na organizacao';
  end if;

  -- Ausencia (inexistente OU de outro tenant) devolve VAZIO, nunca erro: a
  -- leitura nao vaza existencia (T-04) e o limite confiavel traduz vazio em
  -- NOT_FOUND indistinguivel (contrato F5-07 §8.2 / §14.3).
  if not exists (
    select 1
      from public.collaborators c
     where c.id = p_collaborator_id
       and c.organization_id = p_organization_id
  ) then
    return;
  end if;

  -- `actor_full_name`: user_profiles nao guarda nome de pessoa (F2-01). O nome
  -- soberano disponivel do OPERADOR e o do colaborador vinculado a membership
  -- ativa usada na operacao (F5-02); sem vinculo, fica NULL (nunca inventa).
  return query
  select e.id,
         e.event_type,
         e.effective_date,
         e.reason,
         e.cycle_scope,
         e.reference_cycle_id,
         e.actor_user_profile_id,
         vinculo.full_name,
         e.before_value,
         e.after_value,
         e.created_at
    from public.collaborator_events e
    left join lateral (
      select c.full_name
        from public.user_organization_memberships m
        join public.membership_collaborator_links l
          on l.membership_id = m.id
         and l.status = 'active'
        join public.collaborators c
          on c.id = l.collaborator_id
         and c.organization_id = m.organization_id
       where m.user_profile_id = e.actor_user_profile_id
         and m.organization_id = p_organization_id
         and m.status = 'active'
       limit 1
    ) vinculo on true
   where e.organization_id = p_organization_id
     and e.collaborator_id = p_collaborator_id
   order by e.effective_date desc, e.created_at desc;
end;
$$;

comment on function public.colaborador_historico_listar(uuid, uuid, uuid) is
  'F5-07 D8: linha do tempo append-only do colaborador (eventos + vigencia), '
  'ordenada por effective_date/created_at desc. `actor_full_name` deriva do '
  'colaborador vinculado a membership ativa do operador (F5-02) — nunca de '
  'payload. EXECUTE somente service_role.';

-- ----------------------------------------------------------------------------
-- 7) Grants — funcoes somente service_role e tabelas minimas por operacao
-- ----------------------------------------------------------------------------
revoke all on function public.colaborador_ator_valido(uuid, uuid) from public, anon, authenticated;
revoke all on function public.colaborador_visao_listar(uuid, uuid, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function public.colaborador_visao_obter(uuid, uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.colaborador_resolver_matricula(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.colaborador_historico_listar(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.colaborador_pessoa_sintetica() from public, anon, authenticated;

grant execute on function public.colaborador_ator_valido(uuid, uuid) to service_role;
grant execute on function public.colaborador_visao_listar(uuid, uuid, timestamptz, jsonb) to service_role;
grant execute on function public.colaborador_visao_obter(uuid, uuid, uuid, timestamptz) to service_role;
grant execute on function public.colaborador_resolver_matricula(uuid, uuid, text) to service_role;
grant execute on function public.colaborador_historico_listar(uuid, uuid, uuid) to service_role;

-- Leitura e escrita do caminho server-side (F5-07 §10.3): o minimo por
-- operacao. `authenticated` permanece sem DML em todas elas e sem qualquer
-- privilegio no log; `anon` permanece sem privilegio (F4-08 D17).
grant select, insert, update on public.collaborators to service_role;
grant select, insert, update on public.collaborator_identifiers to service_role;
grant select, insert, update on public.collaborator_status_periods to service_role;
grant select, insert, update on public.occupations to service_role;
grant select, insert, update on public.position_reporting_lines to service_role;
grant select, insert, update on public.temporary_responsibilities to service_role;
grant select on public.organizational_units to service_role;
grant select on public.organizational_positions to service_role;
grant select, insert, update on public.job_roles to service_role;
grant select, insert on public.seniority_levels to service_role;
grant select on public.evaluation_cycles to service_role;
grant select on public.user_profiles to service_role;
grant select on public.user_organization_memberships to service_role;
grant select on public.membership_collaborator_links to service_role;

-- Sem DELETE nas tabelas temporais e no log (I5/I6): historico nunca e apagado.
revoke delete on public.collaborator_identifiers from service_role;
revoke delete on public.collaborator_status_periods from service_role;
revoke delete on public.occupations from service_role;
revoke delete on public.position_reporting_lines from service_role;
revoke delete on public.temporary_responsibilities from service_role;
