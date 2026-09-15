-- ============================================================================
-- F5-11 P1 (Issue #238): SCHEMA e TRILHA AUDITAVEL das OBSERVACOES soberanas
-- ----------------------------------------------------------------------------
-- Contrato normativo: docs/F5-11-desenho-tecnico.md (D1-D16; §7.2 tabelas,
-- §7.3 semantica das colunas, §8 autorizacao, §9 seguranca, §12 testes,
-- §13/§13.1 fronteira e dependencias da P1).
--
-- O que esta migration FAZ (exclusivamente P1 - estrutura):
--   1) public.evaluation_observations       - a observacao (D1/D2/D3/D7/D8/D16);
--   2) public.evaluation_observation_events - trilha APPEND-ONLY (D6);
--   3) imutabilidade estrutural de colaborador/ciclo/autoria (D4) por TRIGGER;
--   4) RLS DENY-BY-DEFAULT INTEGRAL (D9) + ACL minima (nenhuma superficie ao
--      cliente: zero policy e zero privilegio a `anon`/`authenticated`);
--   5) substituicao dos GUARDS INVERTIDOS das fases anteriores (feita nos
--      validadores 15-F5-09-P9, 30-F5-10-P7 e 02-F4-08, nao aqui).
--
-- O que esta migration NAO faz (anti-escopo explicito da P1):
--   - NENHUMA RPC `observacao_*` (P2) e NENHUMA funcao funcional de dominio;
--   - NENHUMA policy de leitura own-tenant e NENHUM grant a authenticated (P3);
--   - NENHUMA mudanca no Policy Engine, em capabilities, roles, bundles ou
--     concessoes (P3). O blocker D15 permanece ABERTO: nenhuma capability
--     `observation.*` e concedida, `admin` continua SEM `observation.*`;
--   - NENHUM advisory lock (D10: concorrencia por version + row lock, na P2);
--   - NENHUM Edge, nenhum cliente, nenhum cutover, nenhuma migracao de
--     localStorage (D13 - a barreira contra persistencia local e a P5).
--
-- Identidade (D1): `evaluation_observations.id` e a identidade canonica; o UUID
-- do browser, a matricula, o nome do autor e `(ano, ciclo)` NAO existem aqui como
-- identidade. Tenant sempre na LINHA (`organization_id`), com FK COMPOSTA para
-- que o vinculo cross-tenant seja impossivel ESTRUTURALMENTE (nao apenas por
-- checagem de aplicacao).
--
-- D2: `cycle_id` e NOT NULL e soberano. O modelo legado de observacao SEM CICLO
-- NAO e preservado - nao existe coluna anulavel, estado "fora de ciclo" nem
-- variante equivalente.
--
-- D3: a autoria e EXCLUSIVAMENTE derivada do contexto autenticado (`auth.uid()`
-- verificado na fronteira) e gravada pelo servidor. Nenhum campo de autoria
-- aceito do cliente e autoridade; a P1 nao possui superficie de escrita para
-- cliente algum (zero policy, zero privilegio), logo nem existe caminho pelo qual
-- o cliente possa declarar autoria.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) PREFLIGHT fail-closed do baseline (nao corrige nada; so recusa)
-- ----------------------------------------------------------------------------
do $$
declare
  v_faltando text[] := array[]::text[];
  v_n        int;
begin
  -- Primitivas soberanas que a P1 referencia.
  if to_regclass('public.organizations') is null then
    v_faltando := v_faltando || 'public.organizations';
  end if;
  if to_regclass('public.collaborators') is null then
    v_faltando := v_faltando || 'public.collaborators';
  end if;
  if to_regclass('public.evaluation_cycles') is null then
    v_faltando := v_faltando || 'public.evaluation_cycles';
  end if;
  if to_regclass('public.user_organization_memberships') is null then
    v_faltando := v_faltando || 'public.user_organization_memberships';
  end if;
  if to_regclass('public.user_profiles') is null then
    v_faltando := v_faltando || 'public.user_profiles';
  end if;
  if to_regprocedure('public.set_updated_at()') is null then
    v_faltando := v_faltando || 'public.set_updated_at()';
  end if;
  if to_regprocedure('public.user_has_active_membership(uuid)') is null then
    v_faltando := v_faltando || 'public.user_has_active_membership(uuid)';
  end if;

  -- Chaves candidatas exigidas pelas FKs compostas de tenant.
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycles'::regclass
       and c.conname = 'uq_evaluation_cycles_id_organization'
  ) then
    v_faltando := v_faltando || 'uq_evaluation_cycles_id_organization';
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.collaborators'::regclass
       and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%(id, organization_id)%'
  ) then
    v_faltando := v_faltando || 'collaborators(id, organization_id) unico';
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.user_organization_memberships'::regclass
       and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%(id, organization_id)%'
  ) then
    v_faltando := v_faltando || 'user_organization_memberships(id, organization_id) unico';
  end if;

  if array_length(v_faltando, 1) is not null then
    raise exception 'F5-11 P1: baseline incompleto: %', array_to_string(v_faltando, ', ');
  end if;

  -- A migration NAO e idempotente por design (mesma doutrina das fases F5-09 e
  -- F5-10): reexecutar sobre um banco ja migrado deve falhar ALTO, nunca
  -- "meio aplicar".
  if to_regclass('public.evaluation_observations') is not null
     or to_regclass('public.evaluation_observation_events') is not null then
    raise exception 'F5-11 P1: objetos de observacoes ja existem (esperado banco limpo / db reset)';
  end if;

  -- Fronteira da P1: nenhuma superficie funcional pode existir ainda. Se ja
  -- houver funcao `observa%`/`observation%`, a P2 foi antecipada.
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like '%observa%' or p.proname like '%observation%');
  if v_n <> 0 then
    raise exception 'F5-11 P1: % funcao(oes) de observacoes ja instalada(s) (a P1 nao cria RPC; P2 antecipada)', v_n;
  end if;

  -- D15 permanece ABERTO e intacto: catalogo com 31 capabilities (3 `goal.%` +
  -- 5 `observation.%` = 8) e NENHUMA concessao de `observation.*` a role alguma.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    raise exception 'F5-11 P1: catalogo com % capabilities (esperado 31)', v_n;
  end if;
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    raise exception 'F5-11 P1: capabilities de metas/observacoes = % (esperado 8)', v_n;
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    raise exception 'F5-11 P1: % concessao(oes) de observation.* ja existente(s) — D15 e decisao da P3, nunca da P1', v_n;
  end if;

  raise notice 'F5-11 P1: preflight ok (baseline presente, sem objetos de observacoes, sem RPC, catalogo intacto e D15 sem concessao)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) public.evaluation_observations - a observacao (D1, D2, D3, D7, D8, D16)
-- ----------------------------------------------------------------------------
create table public.evaluation_observations (
  id                          uuid        not null default gen_random_uuid(),
  organization_id             uuid        not null,
  collaborator_id             uuid        not null,   -- alvo (D2)
  cycle_id                    uuid        not null,   -- D2: OBRIGATORIO e soberano
  tipo                        text        not null,
  texto                       text        not null,
  comunicado                  boolean     not null default false,
  comunicado_em               timestamptz,
  comunicado_por_user_profile_id  uuid,
  comunicado_por_membership_id    uuid,
  excluida                    boolean     not null default false,
  excluida_em                 timestamptz,
  excluida_por_user_profile_id    uuid,
  excluida_por_membership_id      uuid,
  motivo_exclusao             text,
  author_user_profile_id      uuid        not null,   -- D3: derivado de auth.uid()
  author_membership_id        uuid        not null,   -- D3: derivado
  author_collaborator_id      uuid,                   -- D3: derivado do vinculo
  version                     integer     not null default 0,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint pk_evaluation_observations primary key (id),
  constraint uq_evaluation_observations_id_organization unique (id, organization_id),
  constraint fk_evaluation_observations_organizations
    foreign key (organization_id) references public.organizations (id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_cycle
    foreign key (cycle_id, organization_id)
    references public.evaluation_cycles (id, organization_id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_collaborator
    foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_author_profile
    foreign key (author_user_profile_id) references public.user_profiles (id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_author_membership
    foreign key (author_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_author_collaborator
    foreign key (author_collaborator_id, organization_id)
    references public.collaborators (id, organization_id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_comunicado_profile
    foreign key (comunicado_por_user_profile_id) references public.user_profiles (id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_comunicado_membership
    foreign key (comunicado_por_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_excluida_profile
    foreign key (excluida_por_user_profile_id) references public.user_profiles (id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observations_excluida_membership
    foreign key (excluida_por_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict on update restrict,
  constraint ck_evaluation_observations_tipo
    check (tipo in ('POSITIVA', 'NEUTRA', 'NEGATIVA')),
  -- D16: `btrim` e 1..2000 caracteres, validado NO BANCO (a fronteira repete).
  constraint ck_evaluation_observations_texto
    check (texto = btrim(texto) and char_length(texto) between 1 and 2000),
  constraint ck_evaluation_observations_version check (version >= 0),
  -- D7: comunicado e FATO - nunca booleano anonimo; carimbo obrigatorio e coerente.
  constraint ck_evaluation_observations_comunicado check (
    (comunicado and comunicado_em is not null
       and comunicado_por_user_profile_id is not null
       and comunicado_por_membership_id is not null)
    or (not comunicado and comunicado_em is null
       and comunicado_por_user_profile_id is null
       and comunicado_por_membership_id is null)),
  -- D8/D16: exclusao logica sempre com ator, instante e MOTIVO; sem motivo nao ha exclusao.
  constraint ck_evaluation_observations_exclusao check (
    (excluida and excluida_em is not null
       and excluida_por_user_profile_id is not null
       and excluida_por_membership_id is not null
       and motivo_exclusao is not null
       and motivo_exclusao = btrim(motivo_exclusao)
       and char_length(motivo_exclusao) between 1 and 2000)
    or (not excluida and excluida_em is null
       and excluida_por_user_profile_id is null
       and excluida_por_membership_id is null
       and motivo_exclusao is null))
);

comment on table public.evaluation_observations is
  'F5-11 P1 (D1/D2/D3/D7/D8/D16): observacao soberana de colaborador por ciclo. '
  'Identidade canonica = id (uuid do banco). cycle_id e NOT NULL (D2 - o modelo '
  'legado sem ciclo NAO e preservado). Autoria EXCLUSIVAMENTE derivada do contexto '
  'autenticado (D3). Comunicado e FATO auditavel com ator e instante (D7). '
  'Exclusao e SEMPRE logica, com motivo (D8/D16). Deny-by-default integral (D9).';

comment on column public.evaluation_observations.collaborator_id is
  'F5-11 (D2/D4): alvo da observacao (collaborators.id) - IMUTAVEL apos a criacao.';
comment on column public.evaluation_observations.cycle_id is
  'F5-11 (D2/D4): ciclo soberano (evaluation_cycles.id) - OBRIGATORIO e IMUTAVEL apos a criacao.';
comment on column public.evaluation_observations.author_user_profile_id is
  'F5-11 (D3): autoria derivada de auth.uid() na fronteira, gravada pelo servidor. '
  'Nunca aceita do cliente e IMUTAVEL apos a criacao.';
comment on column public.evaluation_observations.author_membership_id is
  'F5-11 (D3): membership ativa do autor no tenant da linha - derivada, IMUTAVEL.';
comment on column public.evaluation_observations.author_collaborator_id is
  'F5-11 (D3): colaborador vinculado ao autor (derivado do vinculo); NULO quando o '
  'ator nao possui vinculo de colaborador. IMUTAVEL apos a criacao.';
comment on column public.evaluation_observations.comunicado_em is
  'F5-11 (D7): instante do FATO de comunicacao, gravado pelo SERVIDOR.';
comment on column public.evaluation_observations.motivo_exclusao is
  'F5-11 (D8/D16): motivo OBRIGATORIO da exclusao logica (btrim, 1..2000). NULO '
  'quando a observacao nao esta excluida.';
comment on column public.evaluation_observations.version is
  'F5-11 (D10): concorrencia otimista (expected_version + row lock na P2). A P1 '
  'nao incrementa a versao: quem incrementa e a operacao soberana da P2.';

-- Indice de leitura por alvo; parcial em `not excluida` (a consulta funcional
-- nunca varre o acervo excluido). Nao substitui a FK: e apoio de leitura.
create index ix_evaluation_observations_alvo
  on public.evaluation_observations (organization_id, collaborator_id, cycle_id)
  where not excluida;

create trigger trg_evaluation_observations_updated_at
  before update on public.evaluation_observations
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2) IMUTABILIDADE ESTRUTURAL (D4) - colaborador, ciclo e autoria sao imutaveis
-- ----------------------------------------------------------------------------
-- D4 e NORMATIVO: "colaborador, ciclo e autoria sao imutaveis apos a criacao".
-- A fronteira transportavel da P2 nem aceitara esses campos, mas a garantia
-- precisa ser ESTRUTURAL (resistente a bug de RPC e a privilege drift), como a
-- doutrina de integridade ja usada nas fases anteriores. O trigger NAO limita os
-- campos mutaveis do contrato (tipo, texto, comunicado, excluida, motivo,
-- carimbos, version, updated_at).
create or replace function public.enforce_evaluation_observations_imutaveis()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.id is distinct from old.id
     or new.organization_id is distinct from old.organization_id
     or new.collaborator_id is distinct from old.collaborator_id
     or new.cycle_id is distinct from old.cycle_id
     or new.author_user_profile_id is distinct from old.author_user_profile_id
     or new.author_membership_id is distinct from old.author_membership_id
     or new.author_collaborator_id is distinct from old.author_collaborator_id
     or new.created_at is distinct from old.created_at then
    raise exception
      'F5-11 (D4): identidade, tenant, colaborador, ciclo e autoria sao IMUTAVEIS '
      'apos a criacao; apenas tipo, texto, comunicado, exclusao, motivo, carimbos '
      'e version sao mutaveis';
  end if;
  return new;
end;
$$;

comment on function public.enforce_evaluation_observations_imutaveis() is
  'F5-11 P1 (D4): torna ESTRUTURALMENTE imutaveis, apos a criacao, a identidade, o '
  'tenant, o colaborador, o ciclo e a autoria da observacao - resistente a bug de '
  'RPC e a privilege drift.';

create trigger trg_evaluation_observations_imutaveis
  before update on public.evaluation_observations
  for each row execute function public.enforce_evaluation_observations_imutaveis();

-- ----------------------------------------------------------------------------
-- 3) public.evaluation_observation_events - trilha APPEND-ONLY (D6)
-- ----------------------------------------------------------------------------
-- Molde normativo do D6: `cycle_events` / `evaluation_goal_events` (before/after
-- image, payload_hash derivado server-side, operation_id como chave de
-- idempotencia, ator soberano, FK COMPOSTA de tenant).
create table public.evaluation_observation_events (
  id                      uuid        not null default gen_random_uuid(),
  organization_id         uuid        not null,
  observation_id          uuid        not null,
  entity_type             text        not null,
  event_type              text        not null,
  effective_date          timestamptz not null,
  reason                  text,
  before_value            jsonb,
  after_value             jsonb,
  payload_hash            text        not null,
  result_entity_id        uuid,
  actor_user_profile_id   uuid        not null,
  actor_membership_id     uuid        not null,
  operation_id            uuid        not null,
  created_at              timestamptz not null default now(),
  constraint pk_evaluation_observation_events primary key (id),
  constraint fk_evaluation_observation_events_organizations
    foreign key (organization_id) references public.organizations (id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observation_events_observation
    foreign key (observation_id, organization_id)
    references public.evaluation_observations (id, organization_id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observation_events_actor
    foreign key (actor_user_profile_id) references public.user_profiles (id)
    on delete restrict on update restrict,
  constraint fk_evaluation_observation_events_actor_membership
    foreign key (actor_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id)
    on delete restrict on update restrict,
  constraint uq_evaluation_observation_events_org_operation
    unique (organization_id, operation_id),
  -- D6: conjunto FECHADO de eventos; nenhum evento fora desta lista.
  constraint ck_evaluation_observation_events_entity_type
    check (entity_type = 'evaluation_observation'),
  constraint ck_evaluation_observation_events_event_type
    check (event_type in ('CRIADA', 'EDITADA', 'COMUNICADO',
                          'COMUNICACAO_REMOVIDA', 'EXCLUIDA', 'REVOGADA')),
  -- D8/D16: motivo OBRIGATORIO em EXCLUIDA e REVOGADA.
  constraint ck_evaluation_observation_events_reason check (
    event_type not in ('EXCLUIDA', 'REVOGADA')
    or (reason is not null and reason = btrim(reason)
        and char_length(reason) between 1 and 2000)),
  constraint ck_evaluation_observation_events_payload_hash
    check (payload_hash ~ '^[0-9a-f]{64}$')
);

comment on table public.evaluation_observation_events is
  'F5-11 P1 (D6): trilha AUDITAVEL e APPEND-ONLY das observacoes. Before/after '
  'image, payload_hash derivado server-side e operation_id como chave de '
  'idempotencia por (organization_id, operation_id). Sem reescrita e sem exclusao '
  'fisica - ACL sem UPDATE/DELETE/TRUNCATE e tres triggers de imutabilidade.';

comment on column public.evaluation_observation_events.before_value is
  'F5-11 (D6): imagem ANTERIOR dos campos alterados (preserva "Texto anterior" na UI).';
comment on column public.evaluation_observation_events.effective_date is
  'F5-11 (D6): instante EFETIVO do fato, gravado pelo servidor.';
comment on column public.evaluation_observation_events.payload_hash is
  'F5-11 (D6): SHA-256 hex da intencao canonica, DERIVADO server-side (nunca do corpo).';

-- Append-only no BANCO em PROFUNDIDADE (mesma doutrina de cycle_events e de
-- evaluation_goal_events): UPDATE/DELETE/TRUNCATE levantam excecao por trigger,
-- INCLUSIVE para o owner e para `service_role`; os revokes do bloco 5 sao a
-- PRIMEIRA camada e o trigger e a SEGUNDA, resistente a privilege drift.
create or replace function public.enforce_evaluation_observation_events_append_only()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  raise exception 'F5-11 (D6): evaluation_observation_events e append-only (% negado)', tg_op;
end;
$$;

comment on function public.enforce_evaluation_observation_events_append_only() is
  'F5-11 P1 (D6): torna a trilha de observacoes APPEND-ONLY NO BANCO - UPDATE, '
  'DELETE e TRUNCATE levantam excecao mesmo para o owner e para service_role, '
  'resistindo a privilege drift.';

create trigger trg_evaluation_observation_events_append_only
  before update on public.evaluation_observation_events
  for each row execute function public.enforce_evaluation_observation_events_append_only();

create trigger trg_evaluation_observation_events_no_delete
  before delete on public.evaluation_observation_events
  for each row execute function public.enforce_evaluation_observation_events_append_only();

create trigger trg_evaluation_observation_events_no_truncate
  before truncate on public.evaluation_observation_events
  for each statement execute function public.enforce_evaluation_observation_events_append_only();

-- ----------------------------------------------------------------------------
-- 4) RLS DENY-BY-DEFAULT INTEGRAL (D9)
-- ----------------------------------------------------------------------------
-- D9 e NORMATIVO: as duas tabelas nascem com RLS habilitada, ZERO policy e ZERO
-- privilegio de cliente. NAO se repete o padrao (F5-10 P4) de expor SELECT
-- own-tenant e endurecer depois: a leitura funcional nascera exclusivamente na
-- superficie soberana da P2/P3 (RPC com gate + Edge).
alter table public.evaluation_observations        enable row level security;
alter table public.evaluation_observation_events   enable row level security;

-- ----------------------------------------------------------------------------
-- 5) ACL MINIMA - `service_role` e EXECUTOR tecnico, nunca DECISOR
-- ----------------------------------------------------------------------------
-- Observacoes: `select`/`insert`/`update` (a exclusao e LOGICA - D8), sem
-- `delete`/`truncate`. Trilha: somente `select`/`insert`, sem `update`/`delete`/
-- `truncate` (D6). Nenhum privilegio a `public`/`anon`/`authenticated`.
revoke all on public.evaluation_observations from public, anon, authenticated, service_role;
grant select, insert, update on public.evaluation_observations to service_role;
revoke delete, truncate on public.evaluation_observations from service_role;

revoke all on public.evaluation_observation_events from public, anon, authenticated, service_role;
grant select, insert on public.evaluation_observation_events to service_role;
revoke update, delete, truncate on public.evaluation_observation_events from service_role;

-- ----------------------------------------------------------------------------
-- 6) GUARDA FINAL fail-closed do estado da P1 (prova o que foi instalado)
-- ----------------------------------------------------------------------------
do $$
declare
  v_falhas text[] := array[]::text[];
  v_tab    text;
  v_priv   text;
  v_n      int;
begin
  -- (a) as 2 tabelas existem, sao tabelas comuns e estao com RLS habilitada.
  foreach v_tab in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relkind = 'r'
    ) then
      v_falhas := v_falhas || format('tabela ausente: %s', v_tab);
      continue;
    end if;
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      v_falhas := v_falhas || format('RLS desabilitada: %s', v_tab);
    end if;
    -- D9: DENY-BY-DEFAULT INTEGRAL - nenhuma policy, de nenhum cmd.
    if exists (
      select 1 from pg_policies p
       where p.schemaname = 'public' and p.tablename = v_tab
    ) then
      v_falhas := v_falhas || format('policy indevida na P1 (D9 exige ZERO): %s', v_tab);
    end if;
    -- Nenhum privilegio de cliente (nem leitura, nem escrita).
    foreach v_priv in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
      if has_table_privilege('authenticated', format('public.%I', v_tab), v_priv) then
        v_falhas := v_falhas || format('%s: authenticated com %s', v_tab, v_priv);
      end if;
      if has_table_privilege('anon', format('public.%I', v_tab), v_priv) then
        v_falhas := v_falhas || format('%s: anon com %s', v_tab, v_priv);
      end if;
    end loop;
  end loop;

  -- (b) `service_role` e EXECUTOR tecnico: sem DELETE/TRUNCATE em lugar algum.
  if has_table_privilege('service_role', 'public.evaluation_observations', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_observations', 'TRUNCATE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'TRUNCATE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'UPDATE') then
    v_falhas := v_falhas || 'service_role com privilegio de reescrita/exclusao fisica';
  end if;
  if not has_table_privilege('service_role', 'public.evaluation_observations', 'INSERT')
     or not has_table_privilege('service_role', 'public.evaluation_observations', 'UPDATE')
     or not has_table_privilege('service_role', 'public.evaluation_observation_events', 'INSERT') then
    v_falhas := v_falhas || 'service_role sem o privilegio minimo de execucao (insert/update)';
  end if;

  -- (c) trilha append-only com os TRES triggers + imutabilidade estrutural (D4).
  select count(*) into v_n
    from pg_trigger t
   where t.tgrelid = 'public.evaluation_observation_events'::regclass
     and not t.tgisinternal
     and t.tgname in ('trg_evaluation_observation_events_append_only',
                      'trg_evaluation_observation_events_no_delete',
                      'trg_evaluation_observation_events_no_truncate');
  if v_n <> 3 then
    v_falhas := v_falhas || format('triggers append-only da trilha = %s (esperado 3)', v_n);
  end if;
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_observations'::regclass
       and t.tgname = 'trg_evaluation_observations_imutaveis' and not t.tgisinternal
  ) then
    v_falhas := v_falhas || 'trigger de imutabilidade estrutural (D4) ausente';
  end if;
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_observations'::regclass
       and t.tgname = 'trg_evaluation_observations_updated_at' and not t.tgisinternal
  ) then
    v_falhas := v_falhas || 'trigger de updated_at ausente';
  end if;

  -- (d) constraints do contrato (§7.2) presentes, uma a uma.
  foreach v_tab in array array[
    'pk_evaluation_observations',
    'uq_evaluation_observations_id_organization',
    'fk_evaluation_observations_organizations',
    'fk_evaluation_observations_cycle',
    'fk_evaluation_observations_collaborator',
    'fk_evaluation_observations_author_profile',
    'fk_evaluation_observations_author_membership',
    'fk_evaluation_observations_author_collaborator',
    'ck_evaluation_observations_tipo',
    'ck_evaluation_observations_texto',
    'ck_evaluation_observations_version',
    'ck_evaluation_observations_comunicado',
    'ck_evaluation_observations_exclusao',
    'pk_evaluation_observation_events',
    'uq_evaluation_observation_events_org_operation',
    'fk_evaluation_observation_events_organizations',
    'fk_evaluation_observation_events_observation',
    'fk_evaluation_observation_events_actor',
    'fk_evaluation_observation_events_actor_membership',
    'ck_evaluation_observation_events_entity_type',
    'ck_evaluation_observation_events_event_type',
    'ck_evaluation_observation_events_reason',
    'ck_evaluation_observation_events_payload_hash'] loop
    if not exists (select 1 from pg_constraint c where c.conname = v_tab) then
      v_falhas := v_falhas || format('constraint ausente: %s', v_tab);
    end if;
  end loop;

  -- (e) D2: `cycle_id` e NOT NULL (o modelo legado sem ciclo nao foi preservado).
  if exists (
    select 1 from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'evaluation_observations'
       and c.column_name = 'cycle_id' and c.is_nullable <> 'NO'
  ) then
    v_falhas := v_falhas || 'cycle_id anulavel (D2 exige NOT NULL)';
  end if;

  -- (f) Fronteira da P1: NENHUMA funcao de observacao e NENHUM SECURITY DEFINER novo.
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'observacao\_%' or p.proname like 'observation\_%'
          or p.proname like '%observacao%');
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) de observacao instalada(s) (a P1 nao cria RPC)', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef
     and p.proname in ('enforce_evaluation_observations_imutaveis',
                       'enforce_evaluation_observation_events_append_only');
  if v_n <> 0 then
    v_falhas := v_falhas || 'funcao de enforcement da P1 com SECURITY DEFINER';
  end if;

  -- (g) Catalogo e D15 INTACTOS: 31 capabilities, 8 de metas/observacoes,
  --     bundle `admin` com 9 e SEM nenhuma `observation.*`.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo com %s capabilities (esperado 31)', v_n);
  end if;
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('D15 violado: %s concessao(oes) de observation.*', v_n);
  end if;
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    v_falhas := v_falhas || format('bundle admin com %s capabilities (esperado 9 - D15 intacto)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
    join public.access_roles r on r.id = rc.access_role_id
   where r.is_system = true and c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('role de SISTEMA com %s capability de observacao (D15 exige o contrario)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] F5-11 P1: guarda final: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] F5-11 P1: guarda final: evaluation_observations + evaluation_observation_events criadas com RLS DENY-BY-DEFAULT INTEGRAL (ZERO policy, ZERO privilegio de cliente - D9), cycle_id NOT NULL (D2), autoria derivada (D3), imutabilidade estrutural de colaborador/ciclo/autoria (D4), trilha append-only com os 3 gatilhos (D6), check constraints do contrato presentes, service_role sem DELETE/TRUNCATE, nenhuma RPC criada (fronteira da P1) e D15 intacto (catalogo 31; admin com 9 e SEM observation.*)';
end $$;
