-- ============================================================================
-- F5-08 P1 (Etapa 5): estrutura organizacional e catalogos soberanos
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-08-desenho-tecnico.md (D1-D25 FECHADAS; §27 P1).
--
-- Este arquivo entrega a FUNDACAO DE BANCO do P1:
--   §1  `structure_events` (D13/§8.3): trilha APPEND-ONLY da administracao
--       estrutural e de catalogo — o estado em cada data continua nas tabelas
--       temporais F3; a trilha registra autor soberano, motivo, delta
--       estruturado, `operation_id` e `payload_hash` (idempotencia);
--   §2  RLS/grants da trilha (D8/§13.2/§13.3): deny-by-default, nenhuma
--       policy, escrita somente pelo caminho server-side, DELETE nunca
--       concedido;
--   §3  I1/D7: anti-ciclo de UNIDADES (lacuna documentada pela F3-03),
--       fail-closed, temporal, com o advisory lock NORMATIVO da F3-04
--       (`position_reporting_lines:<organization_id>`) — D14/D24;
--   §4  I2/D6: encerrar unidade exige ausencia dos TRES casos de estrutura
--       vigente na DATA EFETIVA do encerramento (posicao vigente; unidade como
--       FILHA; unidade como PAI) — correcao obrigatoria da revisao do PR #182;
--   §5  I3/D6: encerrar posicao exige ausencia de ocupacao vigente na data
--       efetiva (o trigger F3-04 de reporting line permanece intacto);
--   §6  indice D20 em `organizational_unit_parent_periods.parent_unit_id`;
--   §7  normalizacao explicita dos grants de `service_role` nas tabelas
--       administradas pela F5-08 (D8/D20/§13.3) — sem depender de default
--       privileges.
--
-- As 15 RPCs novas pertencem ao P2 (`20260914010000_f5_08_structure_rpc.sql`).
-- O alinhamento da chave de advisory lock das RPCs estruturais da F5-07 esta em
-- `20260914020000_f5_08_lock_key_alignment.sql` (D24).
--
-- Padrao de seguranca (identico a F5-02/F5-04/F5-06/F5-07): SECURITY INVOKER,
-- `set search_path = public`, ZERO SECURITY DEFINER novo, nenhuma policy de
-- escrita, nenhuma capability nova, nenhuma alteracao em resolvers/scopes da F4
-- e nenhuma migration aplicada reescrita (apenas aditivo).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) `structure_events` — trilha append-only da estrutura e do catalogo (D13)
-- ----------------------------------------------------------------------------
-- Por que uma tabela nova (e nao `collaborator_events`): a trilha da F5-07 e
-- ancorada em colaborador/posicao (CHECK + FKs) e nao tem ancora para
-- `organizational_unit_id`, `job_role_id`, `seniority_level_id` ou colegiado;
-- estende-la exigiria relaxar CHECK/FK de contrato fechado (§8.3).
--
-- `before_value`/`after_value`/`payload_hash` NUNCA sao autoridade de tenant ou
-- de ator (F5-07 §12.2 / F5-06 D26): a trilha registra, nao decide.
--
-- As duas FKs de autoria (`actor_user_profile_id` e a FK composta de
-- `actor_membership_id` + `organization_id`) materializam §15.3 — "autoria exige
-- conta" — no mesmo padrao de `collaborator_events`.
create table public.structure_events (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null,
  entity_type           text        not null,
  entity_id             uuid,
  event_type            text        not null,
  effective_date        timestamptz not null,
  reason                text        not null,
  before_value          jsonb,
  after_value           jsonb,
  payload_hash          text        not null,
  result_entity_id      uuid,
  actor_user_profile_id uuid        not null,
  actor_membership_id   uuid        not null,
  operation_id          uuid        not null,
  created_at            timestamptz not null default now(),
  constraint pk_structure_events primary key (id),
  constraint fk_structure_events_organizations
    foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  constraint fk_structure_events_actor
    foreign key (actor_user_profile_id)
    references public.user_profiles (id)
    on delete restrict,
  constraint fk_structure_events_actor_membership
    foreign key (actor_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict,
  -- Idempotencia (D13/D14): retry com o mesmo `operation_id` nao duplica o
  -- evento — a RPC devolve o mesmo resultado quando o `payload_hash` confere e
  -- responde CONFLICT quando diverge.
  constraint uq_structure_events_org_operation
    unique (organization_id, operation_id),
  constraint ck_structure_events_entity_type
    check (entity_type in (
      'organizational_unit',
      'organizational_unit_parent_period',
      'organizational_position',
      'job_role',
      'seniority_level',
      'collegiate_configuration')),
  constraint ck_structure_events_event_type
    check (event_type in (
      'CRIADO', 'RENOMEADO', 'ENCERRADO', 'REATIVADO',
      'PARENT_DEFINIDO', 'PARENT_ENCERRADO',
      'MEMBROS_ALTERADOS', 'COLEGIADO_ENCERRADO')),
  constraint ck_structure_events_reason
    check (reason <> '' and reason = btrim(reason))
);

comment on table public.structure_events is
  'F5-08 D13/§8.3: log APPEND-ONLY da administracao de estrutura organizacional '
  'e catalogos. O estado em cada data continua nas tabelas temporais F3; a '
  'trilha registra tenant, entidade, tipo de operacao, data de negocio, motivo, '
  'delta estruturado, autor soberano e idempotencia. Evento e mutacao na MESMA '
  'transacao (P2); UPDATE tem trigger de excecao e o caminho server-side recebe '
  'somente SELECT/INSERT.';
comment on column public.structure_events.effective_date is
  'F5-08 §15.1: data de EFEITO da mudanca (valid_from/valid_to da mutacao), '
  'nunca a data de gravacao; `created_at` registra quando o fato foi gravado '
  '(timestamp server-side).';
comment on column public.structure_events.payload_hash is
  'F5-08 D13/D14: hash do payload canonico da INTENCAO. Mesmo operation_id + '
  'mesmo hash devolve o mesmo resultado; hash diferente e CONFLICT.';
comment on column public.structure_events.result_entity_id is
  'F5-08 D13: entidade resultante da operacao quando difere de `entity_id` '
  '(ex.: periodo parent criado ao alterar o vinculo), usada na repeticao '
  'idempotente.';
comment on column public.structure_events.before_value is
  'F5-08 §15.2: estado estrutural anterior relevante (normalizado; nunca dado '
  'pessoal). NAO e fonte de decisao nem autoridade de tenant/ator.';
comment on column public.structure_events.after_value is
  'F5-08 §15.2: estado estrutural novo relevante (normalizado). NAO e fonte de '
  'decisao nem autoridade de tenant/ator.';
comment on column public.structure_events.entity_id is
  'F5-08 §8.3: entidade afetada pela mutacao (unidade, periodo parent, posicao, '
  'cargo, senioridade ou configuracao de colegiado).';

create index ix_structure_events_organization_id
  on public.structure_events (organization_id);
create index ix_structure_events_entity
  on public.structure_events (organization_id, entity_type, entity_id);
create index ix_structure_events_effective
  on public.structure_events (organization_id, effective_date);

-- Append-only no BANCO (nao apenas na aplicacao): UPDATE levanta excecao.
-- DELETE e barrado pela ausencia de grant a TODOS os papeis de aplicacao
-- (anon/authenticated/service_role) — mesmo padrao de `collaborator_events`
-- (F5-07 §10.3/D8/§13.3); somente o superuser local das validacoes remove
-- linhas sinteticas para reexecutar o cenario.
create or replace function public.enforce_structure_events_append_only()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  raise exception 'F5-08: structure_events e append-only (UPDATE negado)';
end;
$$;

comment on function public.enforce_structure_events_append_only() is
  'F5-08 D8/D13: impede UPDATE da trilha estrutural (append-only); DELETE nunca '
  'e concedido a anon/authenticated/service_role.';

create trigger trg_structure_events_append_only
  before update on public.structure_events
  for each row execute function public.enforce_structure_events_append_only();

-- ----------------------------------------------------------------------------
-- 2) RLS e grants de `structure_events` (§13.2/§13.3/§13.7)
-- ----------------------------------------------------------------------------
-- Deny-by-default INTEGRAL: nenhuma policy e criada (nem SELECT) e nenhum grant
-- e concedido a `anon`/`authenticated`. A leitura de trilha, quando existir,
-- passa pelo caminho server-side (P4/P5) — a F5-08 nao cria superficie nova a
-- `authenticated` (D10/D16).
alter table public.structure_events enable row level security;

revoke all on public.structure_events from public, anon, authenticated, service_role;
grant select, insert on public.structure_events to service_role;
revoke update, delete on public.structure_events from service_role;

-- ----------------------------------------------------------------------------
-- 3) I1 — anti-ciclo de UNIDADES (D7/§10.2 I1)
-- ----------------------------------------------------------------------------
-- A F3-03 documentou explicitamente que a prevencao de ciclos MULTINIVEL entre
-- unidades ficaria com a aplicacao (`20260907130000:62-65, 194-195`). A F5-08
-- fecha a lacuna no BANCO, fail-closed, no mesmo desenho temporal do trigger
-- anti-ciclo da F3-04 (`20260907140000:256-303`):
--
--   - a recursao sobe por `parent_unit_id` a partir do PAI da linha gravada e
--     rejeita quando alcanca a propria `unit_id`;
--   - cada passo carrega a INTERSECAO TEMPORAL ACUMULADA do caminho: comeca na
--     janela da linha (`tstzrange(new.valid_from, coalesce(new.valid_to,
--     'infinity'), '[)')`) e, a cada aresta percorrida, intersecta a janela
--     acumulada com a janela `[valid_from, valid_to)` daquela aresta
--     (operador `*` de `tstzrange`, sempre com semantica `[)`);
--   - a recursao so continua enquanto a interseccao acumulada for NAO VAZIA
--     (guarda `&&`), e o ciclo so e recusado quando `new.unit_id` e alcancado
--     com interseccao NAO VAZIA — isto e, quando existe um INSTANTE em que
--     todas as arestas do caminho estao simultaneamente vigentes (definicao do
--     contrato: ciclo temporal "na data da linha");
--   - consequencia: arestas que se sobrepoem individualmente a janela da linha,
--     mas sem instante comum, NAO sao recusadas (sem falso positivo), e nenhum
--     ciclo REAL escapa (fail-closed);
--   - `union` (e nao `union all`) deduplica por `(unit_id, janela)`: a busca a
--     partir desse par nao depende do caminho percorrido, o que tambem impede
--     recursao infinita em bases legadas com ciclo pre-existente;
--   - a linha em gravacao e excluida da recursao (`pp.id is distinct from
--     new.id`) para nao bloquear atualizacoes que nao mudam a hierarquia;
--   - `new.parent_unit_id is null` (raiz) retorna cedo — raiz e ausencia de
--     relacao, nao uma relacao com a organizacao;
--   - self-parent e coberto por `ck_organizational_unit_parent_periods_not_self`
--     (retorna cedo para nao duplicar a mensagem);
--   - o lock e o MESMO da F3-04 (`position_reporting_lines:<organization_id>`),
--     normativo por D14/D24: as duas rotas de escrita estrutural serializam
--     entre si e com o trigger anti-ciclo de posicoes.
--
-- Nenhuma hierarquia e derivada de cargo, senioridade, nome, matricula ou
-- frontend: a unica fonte e `organizational_unit_parent_periods`.
create or replace function public.enforce_organizational_unit_parent_periods_no_cycle()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.parent_unit_id is null then
    return new; -- raiz: ausencia de relacao, sem risco de ciclo
  end if;

  if new.parent_unit_id = new.unit_id then
    return new; -- auto-relacao e tratada pela check constraint
  end if;

  perform pg_advisory_xact_lock(
    hashtext('position_reporting_lines:' || new.organization_id::text)
  );

  if exists (
    with recursive caminho(unit_id, janela) as (
      -- Passo inicial: a janela da propria linha em gravacao.
      select new.parent_unit_id,
             tstzrange(new.valid_from,
                       coalesce(new.valid_to, 'infinity'::timestamptz), '[)')
      union
      -- Cada aresta percorrida intersecta a janela acumulada com a sua;
      -- a guarda `&&` interrompe o ramo quando a interseccao esvazia.
      select pp.parent_unit_id,
             c.janela * tstzrange(pp.valid_from,
                                  coalesce(pp.valid_to, 'infinity'::timestamptz), '[)')
      from public.organizational_unit_parent_periods pp
      join caminho c on pp.unit_id = c.unit_id
      where pp.id is distinct from new.id
        and pp.organization_id = new.organization_id
        and pp.parent_unit_id is not null
        and c.janela && tstzrange(pp.valid_from,
                                  coalesce(pp.valid_to, 'infinity'::timestamptz), '[)')
    )
    select 1
    from caminho
    where unit_id = new.unit_id
      and not isempty(janela)
  ) then
    raise exception
      'organizational_unit_parent_periods: ciclo hierarquico de unidades detectado';
  end if;

  return new;
end;
$$;

comment on function public.enforce_organizational_unit_parent_periods_no_cycle() is
  'F5-08 D7/§10.2 I1 (corrigido na auditoria do PR #183): impede ciclos '
  'multi-nivel entre unidades recusando apenas quando existe INTERSECAO '
  'TEMPORAL NAO VAZIA ao longo de todo o caminho — isto e, um instante em que '
  'todas as arestas do ciclo estejam simultaneamente vigentes (semantica `[)`; '
  'sem falso positivo e sem falso negativo). Fail-closed, sem correcao '
  'automatica, com o advisory xact lock normativo por organizacao (mesma chave '
  'da F3-04 — D14/D24).';

create trigger trg_organizational_unit_parent_periods_no_cycle
  before insert or update on public.organizational_unit_parent_periods
  for each row
  execute function public.enforce_organizational_unit_parent_periods_no_cycle();

-- ----------------------------------------------------------------------------
-- 4) I2 — encerramento de UNIDADE exige ausencia de estrutura vigente (D6)
-- ----------------------------------------------------------------------------
-- Revisao arquitetural do PR #182 (correcao obrigatoria): na DATA EFETIVA do
-- encerramento (`new.valid_to`), os TRES casos abaixo devem estar ausentes:
--
--   (i)   `organizational_positions` vigente com `unit_id` = unidade;
--   (ii)  `organizational_unit_parent_periods` vigente com `unit_id` = unidade
--         (unidade como FILHA);
--   (iii) `organizational_unit_parent_periods` vigente com
--         `parent_unit_id` = unidade (unidade como PAI) — sem este caso, uma
--         unidade filha ativa poderia continuar apontando para um pai
--         encerrado (estrutura impossivel).
--
-- Semantica temporal `[valid_from, valid_to)`: "vigente em T" e
-- `valid_from <= T and (valid_to is null or valid_to > T)`. Portanto a relacao
-- dependente encerrada EXATAMENTE em T NAO conta como vigente em T, e o fluxo
-- valido e: encerrar a relacao dependente em T e, em seguida, encerrar a
-- unidade em T.
--
-- Fail-closed e sem cascata: o trigger recusa a operacao e nunca encerra
-- dependencias automaticamente (mesmo padrao do trigger F3-04 de reporting
-- line, que permanece intacto).
create or replace function public.enforce_organizational_unit_close_requires_no_open_structure()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_ref timestamptz;
begin
  -- Apenas a DEFINICAO de encerramento (valid_to) e validada; reabertura nao
  -- existe nesta atividade (D21).
  if new.valid_to is null then
    return new;
  end if;

  -- Nada a validar quando a janela nao mudou (evita custo em updates de rotulo).
  if tg_op = 'UPDATE'
     and new.valid_from = old.valid_from
     and new.valid_to is not distinct from old.valid_to then
    return new;
  end if;

  v_ref := new.valid_to;

  -- Caso (i): posicao vigente na data de encerramento.
  if exists (
    select 1
    from public.organizational_positions p
    where p.unit_id = new.id
      and p.organization_id = new.organization_id
      and p.valid_from <= v_ref
      and (p.valid_to is null or p.valid_to > v_ref)
  ) then
    raise exception
      'organizational_units: encerramento com posicao vigente na data de encerramento (encerre as posicoes antes)';
  end if;

  -- Caso (ii): unidade como FILHA em relacao de parent vigente.
  if exists (
    select 1
    from public.organizational_unit_parent_periods pp
    where pp.unit_id = new.id
      and pp.organization_id = new.organization_id
      and pp.valid_from <= v_ref
      and (pp.valid_to is null or pp.valid_to > v_ref)
  ) then
    raise exception
      'organizational_units: encerramento com relacao de parent vigente na data de encerramento (unidade como filha)';
  end if;

  -- Caso (iii): unidade como PAI de outra unidade ainda vigente. O criterio e o
  -- mesmo instante T: uma relacao encerrada exatamente em T nao bloqueia.
  if exists (
    select 1
    from public.organizational_unit_parent_periods pp
    where pp.parent_unit_id = new.id
      and pp.organization_id = new.organization_id
      and pp.valid_from <= v_ref
      and (pp.valid_to is null or pp.valid_to > v_ref)
  ) then
    raise exception
      'organizational_units: encerramento com unidade filha vigente na data de encerramento (unidade como pai)';
  end if;

  return new;
end;
$$;

comment on function public.enforce_organizational_unit_close_requires_no_open_structure() is
  'F5-08 D6/§10.2 I2 (revisao PR #182): na data efetiva do encerramento da '
  'unidade, recusa a operacao quando existir (i) posicao vigente na unidade, '
  '(ii) parent-period vigente com a unidade como FILHA ou (iii) parent-period '
  'vigente com a unidade como PAI. Fail-closed, sem cascata; a relacao '
  'encerrada exatamente em T nao e considerada vigente em T ([valid_from, '
  'valid_to)).';

create trigger trg_organizational_units_close_structure
  before update of valid_from, valid_to on public.organizational_units
  for each row
  execute function public.enforce_organizational_unit_close_requires_no_open_structure();

-- ----------------------------------------------------------------------------
-- 5) I3 — encerramento de POSICAO exige ausencia de ocupacao vigente (D6)
-- ----------------------------------------------------------------------------
-- Analogamente ao trigger da F3-04 que impede encerrar posicao com reporting line
-- fora da nova validade (`trg_organizational_positions_close_reporting_lines`,
-- `20260907140000:313-350`): este e o caso da OCUPACAO. Mesma semantica
-- temporal: ocupacao encerrada exatamente em T nao e vigente em T, logo o fluxo
-- valido e encerrar a ocupacao em T e depois a posicao em T.
--
-- O trigger da F3-04 NAO e alterado nem duplicado: os dois convivem (reporting
-- line e ocupacao sao guardas distintas, ambas fail-closed).
create or replace function public.enforce_organizational_position_close_requires_no_open_occupations()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.valid_to is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.valid_from = old.valid_from
     and new.valid_to is not distinct from old.valid_to then
    return new;
  end if;

  if exists (
    select 1
    from public.occupations o
    where o.organizational_position_id = new.id
      and o.organization_id = new.organization_id
      and o.valid_from <= new.valid_to
      and (o.valid_to is null or o.valid_to > new.valid_to)
  ) then
    raise exception
      'organizational_positions: encerramento com ocupacao vigente na data de encerramento (encerre as ocupacoes antes)';
  end if;

  return new;
end;
$$;

comment on function public.enforce_organizational_position_close_requires_no_open_occupations() is
  'F5-08 D6/§10.2 I3: recusa encerrar (ou reduzir a validade de) uma posicao '
  'enquanto existir ocupacao vigente na data efetiva do encerramento '
  '(fail-closed, sem fechamento automatico). Complementa — sem substituir — o '
  'trigger F3-04 de reporting lines.';

create trigger trg_organizational_positions_close_occupations
  before update of valid_from, valid_to on public.organizational_positions
  for each row
  execute function public.enforce_organizational_position_close_requires_no_open_occupations();

-- ----------------------------------------------------------------------------
-- 6) Indice D20 — `organizational_unit_parent_periods.parent_unit_id`
-- ----------------------------------------------------------------------------
-- Os resolvers de descendencia (F3-07) e o anti-ciclo I1 percorrem a aresta
-- pai -> filho, mas a F3-03 criou indice apenas em `unit_id`
-- (`20260907130000:261`). Indice aditivo, sem alterar constraints existentes.
create index ix_organizational_unit_parent_periods_parent_unit_id
  on public.organizational_unit_parent_periods (parent_unit_id);

-- ----------------------------------------------------------------------------
-- 7) Normalizacao de grants de `service_role` nas tabelas administradas (§13.3)
-- ----------------------------------------------------------------------------
-- Os default privileges do Supabase concedem DML amplo (inclusive DELETE) a
-- `service_role`; a F5-08 nao depende deles: cada tabela administrada recebe
-- grant EXPLICITO do necessario e tem DELETE revogado (D8) — encerramento e
-- `valid_to`/`status`, nunca exclusao fisica.
--
-- `anon`/`authenticated` NAO sao tocados: a leitura own-tenant das 8 tabelas
-- ja e contrato fechado da F4-08 (`20260908110000:33-69, 112-125`) e nenhuma
-- policy de escrita e criada (§13.1/§13.2).
--
-- `occupations`, `temporary_responsibilities`, snapshots de colegiado e demais
-- tabelas da F5-07/F5-06 permanecem INTOCADAS (o DELETE de
-- `position_reporting_lines` ja foi revogado pela F5-07 em `20260913000000:794`;
-- reafirmamos o estado para deixar o contrato explicito).
revoke all on public.organizational_units from public, anon, authenticated, service_role;
grant select, insert, update on public.organizational_units to service_role;
revoke delete on public.organizational_units from service_role;

revoke all on public.organizational_unit_parent_periods from public, anon, authenticated, service_role;
grant select, insert, update on public.organizational_unit_parent_periods to service_role;
revoke delete on public.organizational_unit_parent_periods from service_role;

revoke all on public.organizational_positions from public, anon, authenticated, service_role;
grant select, insert, update on public.organizational_positions to service_role;
revoke delete on public.organizational_positions from service_role;

revoke all on public.position_reporting_lines from public, anon, authenticated, service_role;
grant select, insert, update on public.position_reporting_lines to service_role;
revoke delete on public.position_reporting_lines from service_role;

revoke all on public.job_roles from public, anon, authenticated, service_role;
grant select, insert, update on public.job_roles to service_role;
revoke delete on public.job_roles from service_role;

revoke all on public.seniority_levels from public, anon, authenticated, service_role;
grant select, insert, update on public.seniority_levels to service_role;
revoke delete on public.seniority_levels from service_role;

revoke all on public.collegiate_configurations from public, anon, authenticated, service_role;
grant select, insert, update on public.collegiate_configurations to service_role;
revoke delete on public.collegiate_configurations from service_role;

revoke all on public.collegiate_configuration_members from public, anon, authenticated, service_role;
grant select, insert, update on public.collegiate_configuration_members to service_role;
revoke delete on public.collegiate_configuration_members from service_role;

-- Reafirma a leitura own-tenant das 8 tabelas ao papel `authenticated`
-- (nenhuma alteracao de policy; a F4-08 permanece a unica fonte de RLS de
-- leitura) e garante que `anon` continue sem qualquer privilegio de tabela.
grant select on public.organizational_units to authenticated;
grant select on public.organizational_unit_parent_periods to authenticated;
grant select on public.organizational_positions to authenticated;
grant select on public.position_reporting_lines to authenticated;
grant select on public.job_roles to authenticated;
grant select on public.seniority_levels to authenticated;
grant select on public.collegiate_configurations to authenticated;
grant select on public.collegiate_configuration_members to authenticated;

revoke all on public.organizational_units from anon;
revoke all on public.organizational_unit_parent_periods from anon;
revoke all on public.organizational_positions from anon;
revoke all on public.position_reporting_lines from anon;
revoke all on public.job_roles from anon;
revoke all on public.seniority_levels from anon;
revoke all on public.collegiate_configurations from anon;
revoke all on public.collegiate_configuration_members from anon;

-- ----------------------------------------------------------------------------
-- 8) EXECUTE das funcoes de trigger (§13.4)
-- ----------------------------------------------------------------------------
-- Funcoes de trigger NAO sao superficie de API: nenhuma delas recebe EXECUTE de
-- `public`/`anon`/`authenticated` (o PostgreSQL concede EXECUTE a PUBLIC por
-- default; aqui o default e removido). O disparo do trigger nao depende de
-- privilegio de EXECUTE, portanto revogar nao altera o comportamento das
-- garantias I1/I2/I3 nem do append-only (D7/D8/§13.4).
revoke all on function public.enforce_structure_events_append_only()
  from public, anon, authenticated;
revoke all on function public.enforce_organizational_unit_parent_periods_no_cycle()
  from public, anon, authenticated;
revoke all on function public.enforce_organizational_unit_close_requires_no_open_structure()
  from public, anon, authenticated;
revoke all on function public.enforce_organizational_position_close_requires_no_open_occupations()
  from public, anon, authenticated;
