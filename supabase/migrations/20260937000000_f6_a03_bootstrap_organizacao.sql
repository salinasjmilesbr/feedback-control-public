-- ============================================================================
-- F6-A03 (Issue #266): BOOTSTRAP MINIMO SEGURO DO GREENFIELD
-- ----------------------------------------------------------------------------
-- Contrato: docs/F6-A03-desenho-tecnico.md (D1–D21 e Q1–Q3 FECHADAS — normativas).
--
-- PROBLEMA (auditado no desenho, §3):
--   B1 — nao existia caminho autorizado para criar organizacao (RLS + zero
--        policies + zero grant de escrita + nenhuma RPC que insira em
--        `organizations`);
--   B2 — nao existia caminho para o PRIMEIRO `admin` do tenant:
--        `usuario_eh_administrador` exige atribuicao ativa de `admin`
--        (circular) e `conceder_acesso_role_rpc` proibe auto-concessao.
--
-- ENTREGA (unica tabela nova + uma RPC; nenhuma capability, role, policy ou
-- grant de cliente novo):
--   A) `platform_provisioning_events` — ancora de IDEMPOTENCIA + trilha de
--      criacao de tenant do PLANO DE PLATAFORMA. RLS deny-by-default integral
--      (zero policies), `service_role` SOMENTE SELECT+INSERT, append-only.
--      SEM FKs (precedente explicito do D18 da F5-04: registro imutavel nao
--      bloqueia o ciclo de vida da origem) — e e essa ausencia de FK que permite
--      registrar o ATOR mesmo quando o `user_profiles` dele ainda nao existia
--      antes desta transacao (D17).
--   B) `organizacao_provisionar_inicial(...)` — RPC `SECURITY INVOKER`,
--      `search_path` fixo, `EXECUTE` somente `service_role`, SEM `SECURITY
--      DEFINER` novo (a guarda F4-08 exige exatamente 4). UMA transacao:
--        c. insere a ORGANIZACAO (id por `gen_random_uuid()` — nunca declarado
--           pelo chamador, convencao F1-02);
--        d. garante `user_profiles` do FOUNDER (D16) — linha GLOBAL, sem
--           membership e sem atribuicao;
--        e. garante `user_profiles` do ATOR (D17) — a FK de autoria
--           `created_by -> user_profiles` do primitivo F4-01 exige a linha, e a
--           alternativa (autor sintetico / `system_grant`) falsificaria a
--           autoria que o D18 protege;
--        f. insere a MEMBERSHIP ativa do founder na organizacao NOVA;
--        g. concede a role de sistema `admin` pelo PRIMITIVO
--           `conceder_acesso_role` (reuso F4-01 D16) — resolvida por NOME, nunca
--           pelo UUID do catalogo (D9/D13);
--        h. grava a trilha D18 (`privilege_mutation_audit`, `grant`, ator humano);
--        i. fecha o evento de provisionamento (idempotencia + auditoria).
--
-- CONTENCAO POR CONSTRUCAO (D3/§5.2): a RPC so INSERE organizacao nova e so
-- toca membership/atribuicao do tenant recem-nascido. NUNCA atualiza nem exclui
-- organizacao, membership ou atribuicao preexistentes; qualquer caminho que
-- exigisse tocar estado existente LEVANTA. Mesmo em posse de `service_role`, o
-- pior caso e criar um tenant novo e vazio.
--
-- IDEMPOTENCIA (D6): `operation_id` + `payload_hash` calculado SERVER-SIDE; UM
-- unico `insert ... on conflict (operation_id) do nothing returning id` como
-- ponto de serializacao (SEM advisory lock — molde F5-11 P5.4). Quem retorna
-- linha e o dono da operacao; quem nao retorna rele o evento: mesmo hash ⇒
-- REPLAY (devolve o `organization_id` ja gravado, sem novo efeito), hash
-- divergente ⇒ RECUSA fail-closed.
--
-- NAO altera `usuario_eh_administrador` (F5-11 P5.2), `conceder_acesso_role_rpc`
-- (F5-11 P5.4), o anti-self-escalation do plano do TENANT, o catalogo (31
-- capabilities), o bundle `admin` (9 funcionais) nem qualquer RLS existente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A) public.platform_provisioning_events — idempotencia + trilha de plataforma
-- ----------------------------------------------------------------------------
-- Escopo por tabela (convencao F1-02): a entidade e do PLANO DE PLATAFORMA, nao
-- de um tenant especifico — `organization_id` e o tenant CRIADO (dado da trilha,
-- nao escopo de consulta). Por isso nao recebe `updated_at`/`version` (linha
-- imutavel) nem FKs.
create table public.platform_provisioning_events (
  id                      uuid        not null default gen_random_uuid(),
  operation_id            uuid        not null,
  payload_hash            text        not null,
  organization_id         uuid        not null,
  organization_name       text        not null,
  actor_user_profile_id   uuid        not null,
  founder_user_profile_id uuid        not null,
  created_at              timestamptz not null default now(),
  constraint pk_platform_provisioning_events primary key (id),
  constraint uq_platform_provisioning_events_operation_id unique (operation_id),
  constraint ck_platform_provisioning_events_payload_hash
    check (payload_hash ~ '^[0-9a-f]{64}$'),
  constraint ck_platform_provisioning_events_organization_name
    check (btrim(organization_name) <> '')
);

comment on table public.platform_provisioning_events is
  'F6-A03 (Issue #266): trilha append-only do PLANO DE PLATAFORMA — registra a '
  'criacao de cada tenant pelo operador autorizado e e a ANCORA DE IDEMPOTENCIA '
  'da RPC organizacao_provisionar_inicial (unique em operation_id + payload_hash '
  'canonico calculado server-side). NAO e tabela de tenant: nao tem FK, policy '
  'nem privilegio de cliente.';

comment on column public.platform_provisioning_events.operation_id is
  'Chave de idempotencia declarada pelo CHAMADOR AUTENTICADO (a Edge deriva do '
  'corpo validado por allowlist estrita). Unica: repetir a operacao com o MESMO '
  'payload devolve o mesmo organization_id (replay); com payload DIFERENTE '
  'recusa fail-closed.';

comment on column public.platform_provisioning_events.payload_hash is
  'SHA-256 hex do payload CANONICO da intencao, calculado SERVER-SIDE na RPC '
  '(nunca aceito do corpo) — mesmo molde de cycle_events/goal_events.';

comment on column public.platform_provisioning_events.organization_id is
  'Organizacao CRIADA pela operacao (dado da trilha; sem FK, como o D18 da '
  'F5-04 exige para registros imutaveis).';

comment on column public.platform_provisioning_events.actor_user_profile_id is
  'OPERADOR DE PLATAFORMA que executou a operacao — identidade AUTENTICADA '
  'verificada server-side (auth.getUser na Edge) e revalidada pela RPC. Sem FK: '
  'a linha global de user_profiles do ator passa a existir NA MESMA transacao '
  '(D17), mas a trilha nao depende dela para sobreviver.';

comment on column public.platform_provisioning_events.founder_user_profile_id is
  'PRIMEIRO Admin do tenant estabelecido pela operacao (identidade autenticada '
  'preexistente; a FK de user_profiles -> auth.users e a barreira de existencia).';

-- Append-only no caminho de aplicacao (UPDATE negado por trigger; DELETE
-- bloqueado pela revogacao de privilegio de service_role abaixo).
create or replace function public.enforce_platform_provisioning_events_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception 'F6-A03: platform_provisioning_events e append-only (UPDATE negado)';
end;
$$;

comment on function public.enforce_platform_provisioning_events_append_only() is
  'F6-A03: impede UPDATE de registros da trilha de provisionamento de '
  'plataforma (append-only). DELETE e bloqueado por revogacao de privilegio de '
  'service_role (somente SELECT+INSERT); a higienizacao pertence ao '
  'proprietario/superuser, fora do runtime.';

create trigger trg_platform_provisioning_events_append_only
  before update on public.platform_provisioning_events
  for each row
  execute function public.enforce_platform_provisioning_events_append_only();

-- RLS deny-by-default integral: ZERO policy (nenhum cliente le/escreve a trilha).
alter table public.platform_provisioning_events enable row level security;

-- Fronteira de execucao: `service_role` (a Edge) apenas SELECT + INSERT.
revoke all on public.platform_provisioning_events
  from anon, authenticated, service_role;
grant select, insert on public.platform_provisioning_events to service_role;

-- ----------------------------------------------------------------------------
-- B) public.organizacao_provisionar_inicial — bootstrap transacional/idempotente
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_provisionar_inicial(
  p_operation_id            uuid,
  p_organization_name       text,
  p_founder_user_profile_id uuid,
  p_actor_user_profile_id   uuid
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_nome          text;
  v_hash          text;
  v_org           uuid;
  v_evento_id     uuid;
  v_evento        public.platform_provisioning_events%rowtype;
  v_role          uuid;
  v_status_ator   text;
  v_membership    uuid;
begin
  -- (1) FORMA do payload — nada aqui e autoridade.
  if p_operation_id is null
     or p_actor_user_profile_id is null
     or p_founder_user_profile_id is null then
    raise exception 'F6_A03_INVALID_INPUT: operation_id, ator e primeiro Admin sao obrigatorios';
  end if;

  v_nome := btrim(coalesce(p_organization_name, ''));
  if v_nome = '' then
    raise exception 'F6_A03_INVALID_NAME: nome da organizacao obrigatorio';
  end if;

  -- (2) HASH canonico da INTENCAO, derivado SERVER-SIDE (nunca do corpo).
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'organizacao_provisionar_inicial',
    'organization_name', v_nome,
    'founder_user_profile_id', p_founder_user_profile_id
  )::text, 'UTF8')), 'hex');

  -- (3) GATE DE PLATAFORMA no banco (D14/D17): o ator precisa ser admissivel.
  --     Perfil AUSENTE e admissivel (o ambiente virgem nao tem perfil ainda e a
  --     linha e criada no passo (6)); perfil EXISTENTE e nao ativo RECUSA.
  --     A autoridade nominal da allowlist e da fronteira server-side (Edge): a
  --     RPC e contida por CONSTRUCAO (D3) e nunca e alcancavel por `authenticated`
  --     (EXECUTE so service_role).
  select up.status into v_status_ator
    from public.user_profiles up
   where up.id = p_actor_user_profile_id;
  if found and v_status_ator <> 'active' then
    raise exception 'F6_A03_FORBIDDEN: perfil do operador de plataforma nao esta ativo';
  end if;

  -- (4) FOUNDER: perfil existente precisa estar ativo (paridade com
  --     `conceder_acesso_role`, que exige perfil ativo do titular).
  if exists (
    select 1 from public.user_profiles up
     where up.id = p_founder_user_profile_id and up.status <> 'active'
  ) then
    raise exception 'F6_A03_INVALID_FOUNDER: perfil do primeiro Admin nao esta ativo';
  end if;

  -- (5) Role de sistema `admin` resolvida NOMINALMENTE (D9/D13 — nunca por UUID).
  select r.id into v_role
    from public.access_roles r
   where r.name = 'admin'
     and r.is_system = true
     and r.organization_id is null
     and r.status = 'active';
  if v_role is null then
    raise exception 'F6_A03_INTERNAL: role de sistema admin indisponivel';
  end if;

  -- (6) IDEMPOTENCIA — ponto UNICO de serializacao (unique em operation_id).
  --     O id da organizacao e gerado pelo BANCO (convencao F1-02) e ja entra na
  --     trilha: e ele que torna o replay devolvivel sem novo efeito.
  v_org := gen_random_uuid();

  insert into public.platform_provisioning_events (
    operation_id, payload_hash, organization_id, organization_name,
    actor_user_profile_id, founder_user_profile_id
  ) values (
    p_operation_id, v_hash, v_org, v_nome,
    p_actor_user_profile_id, p_founder_user_profile_id
  )
  on conflict (operation_id) do nothing
  returning id into v_evento_id;

  if v_evento_id is null then
    -- A operacao JA foi registrada (retry ou concorrente vencedor): rele a
    -- trilha e decide entre REPLAY e RECUSA, sem produzir efeito nenhum.
    select * into v_evento
      from public.platform_provisioning_events e
     where e.operation_id = p_operation_id;

    if not found then
      raise exception 'F6_A03_CONFLICT: operacao concorrente nao concluida';
    end if;
    if v_evento.payload_hash is distinct from v_hash then
      raise exception 'F6_A03_CONFLICT: operation_id ja utilizado com intencao diferente';
    end if;

    return v_evento.organization_id;  -- REPLAY: mesmo resultado, zero efeito novo
  end if;

  -- (7) ORGANIZACAO nova (unico INSERT de organizacao do produto).
  insert into public.organizations (id, name)
  values (v_org, v_nome);

  -- (8) Linhas GLOBAIS de identidade (D16/D17). Sao identidade global, sem
  --     membership e sem atribuicao: por si so NAO concedem nada (autorizacao
  --     exige membership + atribuicao ativas).
  begin
    insert into public.user_profiles (id) values (p_founder_user_profile_id)
    on conflict (id) do nothing;
  exception when foreign_key_violation then
    -- FK `user_profiles.id -> auth.users.id`: identidade inexistente.
    raise exception 'F6_A03_INVALID_FOUNDER: identidade autenticada do primeiro Admin inexistente';
  end;

  insert into public.user_profiles (id) values (p_actor_user_profile_id)
  on conflict (id) do nothing;

  -- (9) MEMBERSHIP ativa do founder na organizacao NOVA (par necessariamente
  --     novo: a organizacao acabou de nascer nesta transacao).
  insert into public.user_organization_memberships (
    user_profile_id, organization_id, status
  ) values (
    p_founder_user_profile_id, v_org, 'active'
  )
  returning id into v_membership;

  -- (10) CONCESSAO pelo PRIMITIVO da F4-01 (reuso D4): valida membership ativa,
  --      perfil ativo, role ativa e tenant; reativa no lugar. O caminho do TENANT
  --      (`conceder_acesso_role_rpc`) permanece INTOCADO — inclusive o
  --      anti-self-escalation (D5).
  perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);

  -- (11) Trilha D18 append-only, com autoria SOBERANA do operador verificado.
  insert into public.privilege_mutation_audit (
    organization_id, membership_id, access_role_id, action, actor_user_profile_id
  ) values (
    v_org, v_membership, v_role, 'grant', p_actor_user_profile_id
  );

  -- (12) GUARDA FINAL fail-closed: o tenant so se confirma completo.
  if not exists (select 1 from public.organizations o where o.id = v_org) then
    raise exception 'F6_A03_INTERNAL: organizacao nao persistida';
  end if;
  if not exists (
    select 1 from public.user_organization_memberships m
     where m.id = v_membership and m.organization_id = v_org and m.status = 'active'
  ) then
    raise exception 'F6_A03_INTERNAL: membership do primeiro Admin nao persistida';
  end if;
  if not exists (
    select 1 from public.membership_access_role_assignments a
     where a.membership_id = v_membership
       and a.access_role_id = v_role
       and a.organization_id = v_org
       and a.status = 'active'
  ) then
    raise exception 'F6_A03_INTERNAL: atribuicao da role admin nao persistida';
  end if;

  return v_org;
end;
$fn$;

comment on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid) is
  'F6-A03 (Issue #266): provisionamento INICIAL de um tenant pelo PLANO DE '
  'PLATAFORMA — cria a organizacao, garante as linhas globais de user_profiles do '
  'founder (D16) e do ator (D17), cria a membership ativa do primeiro Admin e '
  'concede a role de sistema `admin` resolvida NOMINALMENTE pelo primitivo '
  'conceder_acesso_role (F4-01), gravando a trilha D18. Idempotente por '
  'operation_id + payload_hash server-side: mesmo payload ⇒ replay do '
  'organization_id; payload divergente ⇒ recusa fail-closed. CONTIDA POR '
  'CONSTRUCAO: so insere organizacao NOVA e nunca toca tenant preexistente. '
  'SECURITY INVOKER, search_path fixo, EXECUTE somente service_role.';

-- Fronteira de execucao: sem superficie para `authenticated`/`anon`.
revoke all on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- C) GUARDA fail-closed da propria migration
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_def        text;
  v_policies   integer;
  v_rls        boolean;
  v_admin_n    integer;
  v_catalogo   integer;
  v_bundle     integer;
  v_auth_exec  integer;
begin
  -- (1) Tabela nova: existe, com RLS habilitado e ZERO policy.
  if to_regclass('public.platform_provisioning_events') is null then
    raise exception 'F6_A03: tabela platform_provisioning_events ausente';
  end if;

  select c.relrowsecurity into v_rls
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'platform_provisioning_events';
  if v_rls is not true then
    raise exception 'F6_A03: platform_provisioning_events sem RLS habilitado';
  end if;

  select count(*) into v_policies
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'platform_provisioning_events';
  if v_policies <> 0 then
    raise exception 'F6_A03: platform_provisioning_events deveria ter ZERO policy (tem %)', v_policies;
  end if;

  -- (2) RPC: SECURITY INVOKER (nao DEFINER), search_path fixo e EXECUTE so service_role.
  select pg_get_functiondef('public.organizacao_provisionar_inicial(uuid, text, uuid, uuid)'::regprocedure)
    into v_def;
  if position('SECURITY DEFINER' in v_def) <> 0 then
    raise exception 'F6_A03: organizacao_provisionar_inicial nao pode ser SECURITY DEFINER';
  end if;
  -- `pg_get_functiondef` NAO emite `SECURITY INVOKER` (o default) e renderiza o
  -- `search_path` como `SET search_path TO 'public'` — por isso a prova do
  -- caminho de busca e pelo NOME do parâmetro, nao pela forma `=public`.
  if position('search_path' in replace(v_def, ' ', '')) = 0 then
    raise exception 'F6_A03: organizacao_provisionar_inicial sem search_path fixo';
  end if;

  select count(*) into v_auth_exec
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
   where n.nspname = 'public'
     and p.proname = 'organizacao_provisionar_inicial'
     and a.privilege_type = 'EXECUTE'
     and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole);
  if v_auth_exec <> 0 then
    raise exception 'F6_A03: organizacao_provisionar_inicial com EXECUTE indevido (public/anon/authenticated)';
  end if;

  -- (3) Invariantes herdados INTACTOS: exatamente 1 role de sistema `admin`
  --     ativa, catalogo com 31 capabilities e bundle `admin` com 9 funcionais
  --     (nenhuma capability nova; nenhuma role nova).
  select count(*) into v_admin_n
    from public.access_roles r
   where r.is_system = true and r.name = 'admin' and r.status = 'active';
  if v_admin_n <> 1 then
    raise exception 'F6_A03: esperada EXATAMENTE 1 role de sistema admin ativa (encontradas %)', v_admin_n;
  end if;

  select count(*) into v_catalogo from public.capabilities;
  if v_catalogo <> 31 then
    raise exception 'F6_A03: catalogo de capabilities deveria ter 31 codigos (tem %)', v_catalogo;
  end if;

  select count(*) into v_bundle
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
   where r.name = 'admin' and r.is_system = true;
  if v_bundle <> 9 then
    raise exception 'F6_A03: bundle admin deveria manter 9 capabilities funcionais (tem %)', v_bundle;
  end if;

  raise notice '[PASS] F6-A03: platform_provisioning_events (RLS + zero policy + append-only) e organizacao_provisionar_inicial (INVOKER, search_path fixo, EXECUTE so service_role) instalados; catalogo 31 e bundle admin 9 intactos';
end $guarda$;
