-- ============================================================================
-- F5-09 P1: integridade soberana de ciclos e trilha de auditoria
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-09-desenho-tecnico.md (§9 RLS, §10 Integridade, §11
-- Concorrencia, §12 Auditoria, §19 P1) e docs/F5-09-duvidas.md (ratificacao das
-- Q-F5-09-1..3). Decisoes aplicadas nesta fase: D1 (entidade unica), D4
-- (semantica temporal), D5 (estados), D8/D9 (CANCELADO terminal, exclusao fisica
-- proibida), D12 (atomicidade — contrato das RPCs do P2+), D14 (um ATIVO por
-- organizacao), D15 (sem sobreposicao), D22/D23 (parte aplicavel a fundacao) e
-- as integridades I5/I6/I11/I12/I13/I14.
--
-- Esta migration entrega SOMENTE a fundacao do P1:
--   §1  pre-flight de compatibilidade do baseline (FAIL-CLOSED, sem corrigir
--       dados) — I5/I6 nao sao criadas sobre dados incompativeis;
--   §2  I5 — no maximo UM ciclo ATIVO por organizacao (indice unico parcial);
--   §3  I6 — proibicao de sobreposicao temporal entre ciclos NAO CANCELADOS da
--       mesma organizacao (exclusion GiST com predicado, semantica meio-aberta);
--   §4  D8/D9 — proibicao de exclusao fisica (DELETE/TRUNCATE) de ciclo para os
--       papeis de aplicacao; a RPC de cancelamento pertence ao P4;
--   §5  `cycle_events` — trilha append-only (schema, constraints, indices,
--       trigger de UPDATE negado, RLS deny-by-default e grants minimos);
--   §6  `ciclo_ator_valido` — guard de ator/tenant/capability (reuso integral
--       da autoridade existente; nenhuma identidade nova);
--   §7  `ciclo_lock_organizacao` — chave NORMATIVA de advisory lock da familia
--       de ciclos (fundacao; consumida pelas RPCs do P2-P4);
--   §8  guarda final FAIL-CLOSED (constraints, grants e deny-by-default).
--
-- Fora do escopo (P2+), deliberadamente NAO implementado aqui: RPCs `ciclo_*`,
-- helper de elegibilidade da admissao (P3), Edge Function `ciclos` (P7),
-- alteracao do Policy Engine e reconciliacao do bundle `admin` (P6/P7), policy
-- de LEITURA de `evaluation_cycles` para `authenticated` (P5) e cutover do
-- cliente (P8).
--
-- Identidade canonica: `evaluation_cycles.id` (UUID) — D2. `(ano, numero)`
-- permanece apenas rotulo humano e regra de unicidade
-- (`uq_evaluation_cycles_org_ano_numero`, criada pela F5-06 e NAO alterada
-- aqui). Nenhuma tabela concorrente de ciclo e criada (D1).
--
-- Baseline (verificado antes de escrever esta migration): as unicas linhas de
-- `evaluation_cycles` criadas no repositorio (fixtures F5-06/F5-07 e o cenario
-- de cutover da F5-06) sao UMA por organizacao com periodo 2026-01-01..2026-06-30
-- e status ATIVO, mais uma linha transitoria sem periodo em
-- `03-validar-f5-06-cutover.sql` (removida pelo proprio cenario). Nao ha
-- duplicidade de ATIVO nem sobreposicao => baseline compativel. Ainda assim, o
-- §1 REVALIDA isso no banco e ABORTA sem alterar dado algum se divergir.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Pre-flight de compatibilidade do baseline (fail-closed, sem corrigir dado)
-- ----------------------------------------------------------------------------
-- Nenhum dado e "ajustado" para caber na constraint: incompatibilidade real
-- ABORTA a migration com mensagem explicita e o operador decide. Criar a
-- constraint sem este pre-flight tambem falharia (a validacao varreria a
-- tabela), mas a mensagem seria opaca e o motivo (I5 x I6) ficaria implicito.
do $$
declare
  v_org     uuid;
  v_qtd     int;
begin
  select c.organization_id, c.qtd
    into v_org, v_qtd
    from (
      select organization_id, count(*) as qtd
        from public.evaluation_cycles
       where status = 'ATIVO'
       group by organization_id
      having count(*) > 1
       order by organization_id
       limit 1
    ) c;

  if v_qtd is not null then
    raise exception
      'F5_09_INCOMPATIBLE_BASELINE (I5): organizacao % possui % ciclos ATIVO; '
      'resolva os dados antes de aplicar (nenhum dado foi alterado)', v_org, v_qtd;
  end if;

  raise notice 'F5-09 P1: baseline compativel com I5 (no maximo um ciclo ATIVO por organizacao)';
end $$;

do $$
declare
  v_org uuid;
begin
  select a.organization_id
    into v_org
    from public.evaluation_cycles a
    join public.evaluation_cycles b
      on b.organization_id = a.organization_id
     and b.id > a.id
   where a.status <> 'CANCELADO'
     and b.status <> 'CANCELADO'
     and a.data_inicio is not null and a.data_fim is not null
     and b.data_inicio is not null and b.data_fim is not null
     and daterange(a.data_inicio, a.data_fim + 1, '[)')
         && daterange(b.data_inicio, b.data_fim + 1, '[)')
   order by a.organization_id
   limit 1;

  if v_org is not null then
    raise exception
      'F5_09_INCOMPATIBLE_BASELINE (I6): organizacao % possui ciclos NAO '
      'CANCELADOS com periodo sobreposto; resolva os dados antes de aplicar '
      '(nenhum dado foi alterado)', v_org;
  end if;

  raise notice 'F5-09 P1: baseline compativel com I6 (sem sobreposicao de periodo)';
end $$;

-- ----------------------------------------------------------------------------
-- 2) I5/D14 — no maximo UM ciclo ATIVO por organizacao
-- ----------------------------------------------------------------------------
-- A regra existia APENAS no cliente (`ativarCiclo` procurava `outroAtivo`).
-- Indice unico PARCIAL: `CANCELADO`, `ENCERRADO` e `PLANEJADO` nao participam,
-- portanto varios ciclos nao-ativos coexistem (a unicidade de negocio continua
-- sendo `uq_evaluation_cycles_org_ano_numero`, da F5-06).
create unique index uq_evaluation_cycles_org_ativo
  on public.evaluation_cycles (organization_id)
  where status = 'ATIVO';

comment on index public.uq_evaluation_cycles_org_ativo is
  'F5-09 P1 (I5/D14): no maximo UM ciclo ATIVO por organizacao, garantido pelo '
  'banco (antes so o cliente validava). Duas ativacoes concorrentes: uma vence, '
  'a outra recebe CONFLICT. Indice parcial: apenas status = ATIVO.';

-- ----------------------------------------------------------------------------
-- 3) I6/D15 — sem sobreposicao temporal entre ciclos NAO CANCELADOS
-- ----------------------------------------------------------------------------
-- Semantica temporal (D4, coerente com [valid_from, valid_to) da F5-08 §19.1):
--   - `data_inicio`/`data_fim` sao DATE e `data_fim` e o ULTIMO dia do ciclo
--     (INCLUSIVO para o produto);
--   - a comparacao tecnica usa o intervalo MEIO-ABERTO equivalente
--     `daterange(data_inicio, data_fim + 1, '[)')`.
-- Predicado (partial exclusion — sintaxe com `where (...)` apos os parametros
-- do indice, conforme CREATE TABLE/EXCLUDE do PostgreSQL):
--   - ciclos CANCELADOS nao bloqueiam periodo;
--   - linhas sem periodo (data_inicio/data_fim nulos, aceitas pelo CHECK da
--     F5-06 em ciclo "minimo") ficam FORA do indice.
alter table public.evaluation_cycles
  add constraint ex_evaluation_cycles_periodo_no_overlap
  exclude using gist (
    organization_id with =,
    daterange(data_inicio, data_fim + 1, '[)') with &&
  )
  where (
    status <> 'CANCELADO'
    and data_inicio is not null
    and data_fim is not null
  );

comment on constraint ex_evaluation_cycles_periodo_no_overlap on public.evaluation_cycles is
  'F5-09 P1 (I6/D15/D4): dois ciclos NAO CANCELADOS da mesma organizacao nao '
  'podem ter periodo sobreposto. data_fim e inclusiva para o produto e a '
  'comparacao tecnica usa o intervalo meio-aberto daterange(data_inicio, '
  'data_fim + 1, ''[)''). Ciclos CANCELADOS nao bloqueiam periodo; linhas sem '
  'periodo ficam fora do indice parcial.';

-- ----------------------------------------------------------------------------
-- 4) D8/D9 — proibicao de exclusao fisica de ciclo
-- ----------------------------------------------------------------------------
-- `CANCELADO` e o encerramento definitivo (D8) e nenhum estado admite DELETE
-- fisico (D9/T10/I12). A F5-06 ja revogou tudo de anon/authenticated/service_role
-- e concedeu SOMENTE SELECT/INSERT/UPDATE a service_role; as revogacoes abaixo
-- tornam a proibicao explicita, idempotente e reaplicavel, e cobrem TRUNCATE
-- (que RLS nao protege e apagaria a tabela inteira).
revoke delete, truncate on public.evaluation_cycles
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5) `cycle_events` — trilha soberana append-only de ciclos (§12)
-- ----------------------------------------------------------------------------
-- Por que uma tabela nova (e nao reuso): `collaborator_events` (F5-07) e
-- ancorada em colaborador/posicao, `evaluation_events` (F5-06) e ancorada em
-- avaliacao e `structure_events` (F5-08) tem CHECK fechado de `entity_type` que
-- nao cobre ciclo — estender qualquer uma exigiria relaxar contrato fechado,
-- exatamente o motivo que a F5-08 registrou para criar a propria trilha.
--
-- Autoria: `actor_user_profile_id` (auth.uid() verificado server-side) e a FK
-- composta de `actor_membership_id` + `organization_id` materializam "autoria
-- exige conta" (D23). `autorMatricula`/`autorNome` do cliente NAO existem aqui:
-- payload do browser nunca e autoridade.
--
-- `before_value`/`after_value`/`payload_hash` registram, NAO decidem: nunca sao
-- autoridade de tenant, de ator ou de estado (mesma doutrina de
-- `structure_events`, F5-08 §8.3).
create table public.cycle_events (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null,
  cycle_id              uuid        not null,
  entity_type           text        not null,
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
  constraint pk_cycle_events primary key (id),
  constraint fk_cycle_events_organizations
    foreign key (organization_id)
    references public.organizations (id)
    on delete restrict,
  -- FK COMPOSTA: o ciclo do evento tem de ser do MESMO tenant do evento
  -- (isolamento estrutural, nao apenas checagem na aplicacao).
  constraint fk_cycle_events_cycle
    foreign key (cycle_id, organization_id)
    references public.evaluation_cycles (id, organization_id)
    on delete restrict,
  constraint fk_cycle_events_actor
    foreign key (actor_user_profile_id)
    references public.user_profiles (id)
    on delete restrict,
  constraint fk_cycle_events_actor_membership
    foreign key (actor_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict,
  -- Idempotencia (D12/§11): retry com o mesmo `operation_id` nao duplica evento
  -- nem mutacao; a RPC devolve o mesmo resultado quando o `payload_hash`
  -- confere e responde CONFLICT quando diverge.
  constraint uq_cycle_events_org_operation
    unique (organization_id, operation_id),
  constraint ck_cycle_events_entity_type
    check (entity_type = 'evaluation_cycle'),
  -- `ADMISSAO_INCLUIDA` ja pertence ao contrato do P1 mesmo sendo emitido pelas
  -- RPCs do P3 (D26): o tipo nasce com a trilha para nao exigir alteracao de
  -- CHECK de contrato fechado depois.
  constraint ck_cycle_events_event_type
    check (event_type in (
      'CRIADO', 'EDITADO', 'ATIVADO', 'ENCERRADO', 'CANCELADO', 'REABERTO',
      'PERIODO_CORRIGIDO', 'ADMISSAO_INCLUIDA')),
  constraint ck_cycle_events_reason
    check (reason <> '' and reason = btrim(reason)),
  -- `payload_hash` = SHA-256 do payload canonico da INTENCAO, em hexadecimal
  -- minusculo de 64 caracteres — mesma convencao das RPCs da F5-08
  -- (`encode(sha256(convert_to(<payload>::text, 'UTF8')), 'hex')`). O CHECK
  -- impede que um hash invalido entre na trilha (fail-closed na origem).
  constraint ck_cycle_events_payload_hash
    check (payload_hash ~ '^[0-9a-f]{64}$')
);

comment on table public.cycle_events is
  'F5-09 P1 (§12/D12/D23): log APPEND-ONLY das mutacoes oficiais de ciclo. '
  'Registra tenant, ciclo, tipo de operacao, data de efeito, motivo, delta '
  'normalizado, autor soberano (auth.uid + membership), hash do payload da '
  'intencao e idempotencia por (organization_id, operation_id). O estado oficial '
  'continua em `evaluation_cycles`; a trilha registra, nao decide. APPEND-ONLY '
  'COMPLETO: UPDATE/DELETE/TRUNCATE negados por trigger (mesmo para o owner e '
  'para service_role) e, na primeira camada, por ausencia de grant; o caminho '
  'server-side recebe somente SELECT/INSERT.';
comment on column public.cycle_events.effective_date is
  'F5-09 P1 (§12.6): data de EFEITO da mudanca, nunca a data de gravacao '
  '(`created_at` registra quando o fato foi gravado, server-side).';
comment on column public.cycle_events.payload_hash is
  'F5-09 P1 (§11/D12): SHA-256 hex (64 caracteres) do payload canonico da '
  'INTENCAO. Mesmo operation_id + mesmo hash devolve o mesmo resultado; hash '
  'divergente e CONFLICT. Nao e autoridade de tenant/ator/estado.';
comment on column public.cycle_events.result_entity_id is
  'F5-09 P1: entidade resultante da operacao quando difere de `cycle_id` (ex.: '
  'linha de `collegiate_cycle_snapshots` criada pela inclusao aditiva do P3).';
comment on column public.cycle_events.before_value is
  'F5-09 P1 (§12.3): estado anterior relevante e NORMALIZADO (status, periodo, '
  'versao, contagens, motivo). Nunca dado pessoal e nunca fonte de decisao.';
comment on column public.cycle_events.after_value is
  'F5-09 P1 (§12.3): estado novo relevante e NORMALIZADO. Nunca fonte de decisao.';
comment on column public.cycle_events.reason is
  'F5-09 P1 (§12.2): motivo obrigatorio (nao vazio, sem espacos nas bordas) nos '
  'fluxos excepcionais (cancelar/reabrir/corrigir periodo), no encerramento e na '
  'inclusao aditiva de nova admissao.';

create index ix_cycle_events_organization_id
  on public.cycle_events (organization_id);
create index ix_cycle_events_cycle
  on public.cycle_events (organization_id, cycle_id);
create index ix_cycle_events_effective
  on public.cycle_events (organization_id, effective_date);

-- Append-only no BANCO em PROFUNDIDADE (nao apenas na aplicacao e nao apenas por
-- ACL): UPDATE, DELETE e TRUNCATE levantam excecao por trigger, INCLUSIVE para o
-- OWNER e para `service_role` (que contorna RLS). Os revokes do §9 continuam
-- valendo como PRIMEIRA camada; o trigger e a SEGUNDA, resistente a privilege
-- drift — uma migration futura que concedesse DELETE/TRUNCATE por engano a
-- `service_role` nao conseguiria apagar a trilha.
--
-- Uma unica funcao cobre as tres operacoes (TG_OP compoe o motivo da excecao). O
-- trigger de TRUNCATE e STATEMENT-level, exigencia do PostgreSQL para TRUNCATE.
create or replace function public.enforce_cycle_events_append_only()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  raise exception 'F5-09: cycle_events e append-only (% negado)', tg_op;
end;
$$;

comment on function public.enforce_cycle_events_append_only() is
  'F5-09 P1 (§12.5): torna a trilha de ciclos APPEND-ONLY NO BANCO — UPDATE, '
  'DELETE e TRUNCATE levantam excecao mesmo para o owner e para service_role, '
  'resistindo a privilege drift (grant acidental futuro). Primeira camada: os '
  'revokes de UPDATE/DELETE/TRUNCATE a anon/authenticated/service_role.';

create trigger trg_cycle_events_append_only
  before update on public.cycle_events
  for each row execute function public.enforce_cycle_events_append_only();

create trigger trg_cycle_events_no_delete
  before delete on public.cycle_events
  for each row execute function public.enforce_cycle_events_append_only();

create trigger trg_cycle_events_no_truncate
  before truncate on public.cycle_events
  for each statement execute function public.enforce_cycle_events_append_only();

-- RLS/grants da trilha (§9): deny-by-default INTEGRAL — nenhuma policy (nem
-- SELECT) e nenhum privilegio a `anon`/`authenticated`. A leitura de trilha e
-- server-side (P7/P9); a F5-09 nao abre superficie nova ao cliente.
alter table public.cycle_events enable row level security;

revoke all on public.cycle_events from public, anon, authenticated, service_role;
grant select, insert on public.cycle_events to service_role;
revoke update, delete, truncate on public.cycle_events from service_role;

-- ----------------------------------------------------------------------------
-- 6) `ciclo_ator_valido` — guard de ator/tenant/capability (§8, D23)
-- ----------------------------------------------------------------------------
-- Reuso INTEGRAL da autoridade existente: `auth.uid()` (recebido como perfil ja
-- resolvido server-side) + membership/perfil ATIVOS no tenant
-- (`evaluation_ator_valido`, F5-06) + capabilities EFETIVAS do ator
-- (`resolver_capabilities_efetivas`, F4-01/F5-04 D14/D19). Nenhuma fonte nova
-- de identidade; tenant e identidade NUNCA vem do corpo da requisicao.
--
-- Allowlist FECHADA de capabilities: a funcao so aceita os codigos do dominio de
-- ciclo. Sem isso, a RPC poderia consultar "qualquer capability que o ator
-- tenha" — o guard passa a provar exatamente a capability do ciclo exigida pela
-- operacao (fail-closed para codigo desconhecido, deprecado ou de outro
-- dominio, que `resolver_capabilities_efetivas` ja exclui).
create or replace function public.ciclo_ator_valido(
  p_actor_user_profile_id uuid,
  p_organization_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    coalesce(p_capability, '') in (
      'cycle.read', 'cycle.manage', 'cycle.cancel', 'cycle.reopen',
      'cycle.period.correct'
    )
    and public.evaluation_ator_valido(p_actor_user_profile_id, p_organization_id)
    and exists (
      select 1
        from public.resolver_capabilities_efetivas(
               p_actor_user_profile_id, p_organization_id) c
       where c.capability_code = p_capability
    );
$$;

comment on function public.ciclo_ator_valido(uuid, uuid, text) is
  'F5-09 P1 (§8/D23): revalida ator soberano (perfil e membership ATIVOS no '
  'tenant), aplica a allowlist FECHADA das capabilities de ciclo e confirma que '
  'a capability EXIGIDA e efetiva do ator (F5-04 D14/D19). Nao substitui a '
  'decisao do Policy Engine (que ocorre antes, na fronteira confiavel): e '
  'defesa em profundidade dentro da transacao. Codigo desconhecido => false '
  '(fail-closed). EXECUTE somente service_role.';

revoke all on function public.ciclo_ator_valido(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.ciclo_ator_valido(uuid, uuid, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- 7) `ciclo_lock_organizacao` — chave NORMATIVA de advisory lock (§11)
-- ----------------------------------------------------------------------------
-- Doutrina de chave unica por familia de recurso (ver
-- `20260914020000_f5_08_lock_key_alignment.sql`): duas chaves para a mesma
-- familia quebram a serializacao. A familia de CICLOS usa exatamente:
--
--   evaluation_cycles:<organization_id>
--
-- As chaves existentes de outras familias
-- (`position_reporting_lines:` da F3-04/F5-08 e `f5_07_estrutura:` da F5-07)
-- NAO sao reutilizadas aqui. A funcao existe para que a chave tenha UM UNICO
-- ponto de definicao: as RPCs do P2-P4 (criar/editar/ativar/encerrar/cancelar/
-- reabrir/corrigir periodo/incluir admissao) devem chama-la no INICIO da
-- transacao. O P1 nao implementa nenhuma dessas transicoes.
create or replace function public.ciclo_lock_organizacao(p_organization_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if p_organization_id is null then
    raise exception
      'F5_09_INVALID_INPUT: organization_id obrigatorio para o lock de ciclo';
  end if;

  -- Lock de TRANSACAO (liberado no commit/rollback).
  perform pg_advisory_xact_lock(
    hashtext('evaluation_cycles:' || p_organization_id::text)
  );
end;
$$;

comment on function public.ciclo_lock_organizacao(uuid) is
  'F5-09 P1 (§11): serializa, por organizacao, TODA mutacao oficial de ciclo '
  'com a chave normativa unica da familia (evaluation_cycles:<organization_id>). '
  'Deve ser chamada no inicio de cada RPC que muta ciclo (P2-P4). Chave '
  'exclusiva desta familia; nao reutilizar em outra. EXECUTE somente '
  'service_role.';

revoke all on function public.ciclo_lock_organizacao(uuid)
  from public, anon, authenticated;
grant execute on function public.ciclo_lock_organizacao(uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 8) EXECUTE das funcoes de trigger (§12.5)
-- ----------------------------------------------------------------------------
-- Funcao de trigger NAO e superficie de API: nenhum EXECUTE a
-- `public`/`anon`/`authenticated` (o PostgreSQL concede EXECUTE a PUBLIC por
-- default; aqui o default e removido). O disparo do trigger nao depende de
-- privilegio de EXECUTE, portanto revogar nao afeta a garantia de append-only.
revoke all on function public.enforce_cycle_events_append_only()
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 9) Guarda final FAIL-CLOSED (§19 P1)
-- ----------------------------------------------------------------------------
-- A migration so termina se a fundacao estiver exatamente como o contrato
-- exige: I5/I6 presentes, unicidade de negocio da F5-06 preservada, exclusao
-- fisica fechada a TODOS os papeis de aplicacao, trilha append-only e
-- deny-by-default, e nenhuma policy antecipando a leitura do P5.
do $$
declare
  v_problemas text[] := array[]::text[];
begin
  -- I5
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public'
       and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_problemas := v_problemas || 'I5 ausente (uq_evaluation_cycles_org_ativo)';
  end if;

  -- I6
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_cycles'::regclass
       and conname = 'ex_evaluation_cycles_periodo_no_overlap'
       and contype = 'x'
  ) then
    v_problemas := v_problemas || 'I6 ausente (ex_evaluation_cycles_periodo_no_overlap)';
  end if;

  -- Contrato da F5-06 preservado (unicidade de negocio ano+numero)
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.evaluation_cycles'::regclass
       and conname = 'uq_evaluation_cycles_org_ano_numero'
       and contype = 'u'
  ) then
    v_problemas := v_problemas || 'uq_evaluation_cycles_org_ano_numero ausente (F5-06 alterada)';
  end if;

  -- D9: exclusao fisica fechada
  if has_table_privilege('service_role', 'public.evaluation_cycles', 'DELETE') then
    v_problemas := v_problemas || 'service_role com DELETE em evaluation_cycles';
  end if;
  if has_table_privilege('service_role', 'public.evaluation_cycles', 'TRUNCATE') then
    v_problemas := v_problemas || 'service_role com TRUNCATE em evaluation_cycles';
  end if;
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('authenticated', 'public.evaluation_cycles', 'TRUNCATE') then
    v_problemas := v_problemas || 'authenticated com escrita em evaluation_cycles (P5 nao antecipado)';
  end if;
  if has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'INSERT')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'UPDATE')
     or has_table_privilege('anon', 'public.evaluation_cycles', 'DELETE') then
    v_problemas := v_problemas || 'anon com privilegio em evaluation_cycles';
  end if;

  -- RLS habilitada nas duas tabelas e nenhuma policy no P1
  if not exists (
    select 1 from pg_class
     where oid = 'public.evaluation_cycles'::regclass and relrowsecurity
  ) then
    v_problemas := v_problemas || 'RLS desabilitada em evaluation_cycles';
  end if;
  if not exists (
    select 1 from pg_class
     where oid = 'public.cycle_events'::regclass and relrowsecurity
  ) then
    v_problemas := v_problemas || 'RLS desabilitada em cycle_events';
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename in ('evaluation_cycles', 'cycle_events')
  ) then
    v_problemas := v_problemas || 'policy antecipada (P1 e deny-by-default integral; leitura de ciclo e do P5)';
  end if;

  -- Trilha: append-only COMPLETO no banco (UPDATE + DELETE + TRUNCATE) e grants
  -- minimos. Um trigger ausente seria privilege drift nao coberto.
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.cycle_events'::regclass
       and tgname = 'trg_cycle_events_append_only'
       and not tgisinternal
       and pg_get_triggerdef(oid) like '%BEFORE UPDATE%'
  ) then
    v_problemas := v_problemas || 'trigger append-only de UPDATE ausente em cycle_events';
  end if;
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.cycle_events'::regclass
       and tgname = 'trg_cycle_events_no_delete'
       and not tgisinternal
       and pg_get_triggerdef(oid) like '%BEFORE DELETE%'
  ) then
    v_problemas := v_problemas || 'trigger append-only de DELETE ausente em cycle_events';
  end if;
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.cycle_events'::regclass
       and tgname = 'trg_cycle_events_no_truncate'
       and not tgisinternal
       and pg_get_triggerdef(oid) like '%BEFORE TRUNCATE%'
  ) then
    v_problemas := v_problemas || 'trigger append-only de TRUNCATE ausente em cycle_events';
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'UPDATE')
     or has_table_privilege('service_role', 'public.cycle_events', 'DELETE')
     or has_table_privilege('service_role', 'public.cycle_events', 'TRUNCATE') then
    v_problemas := v_problemas || 'service_role com UPDATE/DELETE/TRUNCATE em cycle_events';
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'SELECT') is not true
     or has_table_privilege('service_role', 'public.cycle_events', 'INSERT') is not true then
    v_problemas := v_problemas || 'service_role sem SELECT/INSERT em cycle_events';
  end if;
  if has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'UPDATE')
     or has_table_privilege('authenticated', 'public.cycle_events', 'DELETE') then
    v_problemas := v_problemas || 'authenticated com privilegio em cycle_events';
  end if;
  if has_table_privilege('anon', 'public.cycle_events', 'SELECT')
     or has_table_privilege('anon', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.cycle_events', 'UPDATE')
     or has_table_privilege('anon', 'public.cycle_events', 'DELETE') then
    v_problemas := v_problemas || 'anon com privilegio em cycle_events';
  end if;

  -- Helpers do P1: existem e nao sao superficie do cliente
  if has_function_privilege('authenticated', 'public.ciclo_ator_valido(uuid, uuid, text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.ciclo_ator_valido(uuid, uuid, text)', 'EXECUTE') then
    v_problemas := v_problemas || 'ciclo_ator_valido exposto ao cliente';
  end if;
  if has_function_privilege('authenticated', 'public.ciclo_lock_organizacao(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.ciclo_lock_organizacao(uuid)', 'EXECUTE') then
    v_problemas := v_problemas || 'ciclo_lock_organizacao exposto ao cliente';
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception 'F5_09_GUARD: fundacao do P1 inconsistente: %',
      array_to_string(v_problemas, '; ');
  end if;

  raise notice 'F5-09 P1: guarda final OK (I5/I6 presentes, exclusao fisica fechada, trilha append-only e deny-by-default)';
end $$;
