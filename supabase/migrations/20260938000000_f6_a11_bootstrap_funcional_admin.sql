-- ============================================================================
-- F6-A11 (Issue #273): BOOTSTRAP FUNCIONAL DO PRIMEIRO ADMIN GREENFIELD
-- ----------------------------------------------------------------------------
-- Completa `public.organizacao_provisionar_inicial` (F6-A03, Issue #266) com a
-- ANCORA FUNCIONAL do primeiro Admin, conforme o contrato FECHADO
-- `docs/F6-A11-desenho-tecnico.md` (D22-D30). O que esta migration faz:
--
--   D23 - dados minimos do colaborador inicial: `full_name` (nome humano
--         informado), `email` da IDENTIDADE autenticada (resolvido server-side
--         pela Edge), `matricula` declarada. `admission_date` fica NULL (nao se
--         inventa data: a vigencia de identificador/status/evento inicia em
--         `now()` dentro do primitivo) e o status inicial e `active` (default
--         canonico). Nenhuma estrutura (ocupacao/cargo/unidade/colegiado) e
--         criada: ausencia de estrutura e NULL na projecao, nunca erro.
--
--   D24 - criacao + vinculo F5-02 ATOMICOS na MESMA transacao, pelos primitivos
--         existentes `colaborador_criar` (F5-07) e `vincular_colaborador`
--         (F5-02 D9). Nenhum INSERT direto em `membership_collaborator_links`
--         (Issue §5) e NENHUMA excecao de autorizacao: as operacoes funcionais
--         do Admin continuam decididas pelo Policy Engine sobre a ancora F5-02.
--         O ator do evento `ADMISSAO` e o PROPRIO founder: e o unico ator
--         FK-valido, porque `collaborator_events.actor_membership_id` e
--         NOT NULL com FK composta para a organizacao e somente o founder
--         recebe membership no tenant novo (F6-A03 §4/D21). A autoria do ATO DE
--         PLATAFORMA permanece com o operador em `platform_provisioning_events`
--         e em `privilege_mutation_audit` (D17/D18 preservados).
--
--   D25 - assinatura nova (3 parametros NO FIM), hash de intencao AMPLIADO e
--         DROP EXPLICITO da assinatura antiga: `create or replace` com lista de
--         parametros diferente cria SOBRECARGA, e a versao antiga ficaria viva
--         SEM a ancora funcional.
--
--   D27/D29 - `platform_provisioning_events` fica INTOCADA (trilha append-only,
--         sem coluna nova): o colaborador criado e derivavel pelo vinculo ativo
--         da membership do founder.
--
-- Invariantes preservados (nao reabrir): SECURITY INVOKER (nenhum
-- `SECURITY DEFINER` novo - a guarda F4-08 exige exatamente 4), `search_path`
-- fixo, EXECUTE somente `service_role`, idempotencia por `operation_id` +
-- `payload_hash` resolvida ANTES de qualquer escrita, fail-closed com rollback
-- total, tenant isolation pelas FKs compostas e RLS/policies/grants de cliente
-- inalterados.
--
-- Os prefixos de erro continuam `F6_A03_*` DE PROPOSITO: `codigoPublicoDeErroRpc`
-- (Edge `provisionar-organizacao`) mapeia essa taxonomia FECHADA para os codigos
-- publicos F0-05; renomear exigiria mexer no mapa e nenhum codigo publico novo e
-- necessario (D26).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (A) Remocao EXPLICITA da assinatura anterior (D25)
-- ----------------------------------------------------------------------------
-- Sem este DROP, o `create or replace` abaixo criaria uma SOBRECARGA e a versao
-- de 4 parametros continuaria instalada e executavel por `service_role` - um
-- caminho de bootstrap SEM ancora funcional (o defeito auditado na F6-A08).
drop function if exists public.organizacao_provisionar_inicial(uuid, text, uuid, uuid);

-- ----------------------------------------------------------------------------
-- (B) organizacao_provisionar_inicial - bootstrap transacional/idempotente com
--     a ancora funcional do primeiro Admin (F6-A11)
-- ----------------------------------------------------------------------------
create or replace function public.organizacao_provisionar_inicial(
  p_operation_id            uuid,
  p_organization_name       text,
  p_founder_user_profile_id uuid,
  p_actor_user_profile_id   uuid,
  p_founder_full_name       text,
  p_founder_matricula       text,
  p_founder_email           text
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_nome          text;
  v_full_name     text;
  v_matricula     text;
  v_email         text;
  v_hash          text;
  v_org           uuid;
  v_evento_id     uuid;
  v_evento        public.platform_provisioning_events%rowtype;
  v_role          uuid;
  v_status_ator   text;
  v_membership    uuid;
  v_collaborator  uuid;
begin
  -- (1) FORMA do payload - nada aqui e autoridade.
  if p_operation_id is null
     or p_actor_user_profile_id is null
     or p_founder_user_profile_id is null then
    raise exception 'F6_A03_INVALID_INPUT: operation_id, ator e primeiro Admin sao obrigatorios';
  end if;

  v_nome := btrim(coalesce(p_organization_name, ''));
  if v_nome = '' then
    raise exception 'F6_A03_INVALID_NAME: nome da organizacao obrigatorio';
  end if;

  -- D23: identidade funcional minima do primeiro Admin. A FORMA e validada aqui
  -- (nao depende de estado); o ESTADO do founder e validado no passo (6), depois
  -- da idempotencia, conforme a ordem do contrato §5.
  v_full_name := btrim(coalesce(p_founder_full_name, ''));
  if v_full_name = '' then
    raise exception 'F6_A03_INVALID_FOUNDER: nome humano do primeiro Admin obrigatorio';
  end if;

  v_matricula := btrim(coalesce(p_founder_matricula, ''));
  if v_matricula = '' then
    raise exception 'F6_A03_INVALID_FOUNDER: matricula do primeiro Admin obrigatoria';
  end if;

  v_email := lower(btrim(coalesce(p_founder_email, '')));
  if v_email = '' or position('@' in v_email) <= 1 then
    raise exception 'F6_A03_INVALID_FOUNDER: e-mail da identidade do primeiro Admin indisponivel';
  end if;

  -- (2) HASH canonico da INTENCAO, derivado SERVER-SIDE (nunca do corpo).
  --     D25: a identidade funcional minima participa do hash - retry com o mesmo
  --     `operation_id` e nome/matricula/e-mail diferentes e RECUSADO fail-closed.
  v_hash := encode(sha256(convert_to(jsonb_build_object(
    'operacao', 'organizacao_provisionar_inicial',
    'organization_name', v_nome,
    'founder_user_profile_id', p_founder_user_profile_id,
    'founder_full_name', v_full_name,
    'founder_matricula', v_matricula,
    'founder_email', v_email
  )::text, 'UTF8')), 'hex');

  -- (3) GATE DE PLATAFORMA no banco (D14/D17): o ator precisa ser admissivel.
  --     Perfil AUSENTE e admissivel (o ambiente virgem nao tem perfil ainda e a
  --     linha e criada no passo (8)); perfil EXISTENTE e nao ativo RECUSA.
  --     A autoridade nominal da allowlist e da fronteira server-side (Edge): a
  --     RPC e contida por CONSTRUCAO (D3) e nunca e alcancavel por `authenticated`
  --     (EXECUTE so service_role).
  select up.status into v_status_ator
    from public.user_profiles up
   where up.id = p_actor_user_profile_id;
  if found and v_status_ator <> 'active' then
    raise exception 'F6_A03_FORBIDDEN: perfil do operador de plataforma nao esta ativo';
  end if;

  -- (4) Role de sistema `admin` resolvida NOMINALMENTE (D9/D13 - nunca por UUID).
  select r.id into v_role
    from public.access_roles r
   where r.name = 'admin'
     and r.is_system = true
     and r.organization_id is null
     and r.status = 'active';
  if v_role is null then
    raise exception 'F6_A03_INTERNAL: role de sistema admin indisponivel';
  end if;

  -- (5) IDEMPOTENCIA - ponto UNICO de serializacao (unique em operation_id).
  --     O id da organizacao e gerado pelo BANCO (convencao F1-02) e ja entra na
  --     trilha: e ele que torna o replay devolvivel sem novo efeito.
  --
  --     ORDEM (contrato §5, passos `a`->`b`): a resolucao da idempotencia vem
  --     ANTES de qualquer validacao/escrita que dependa do ESTADO ATUAL do
  --     founder. Assim o REPLAY e ESTAVEL e sem efeito: repetir a MESMA intencao
  --     devolve o mesmo `organization_id` mesmo que o perfil do primeiro Admin
  --     tenha sido inativado depois (fail-closed permanece para operacao NOVA).
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

  -- (6) FOUNDER: perfil EXISTENTE precisa estar ativo (paridade com
  --     `conceder_acesso_role`, que exige perfil ativo do titular). Avaliado no
  --     caminho de operacao NOVA - depois da idempotencia, conforme o §5.
  if exists (
    select 1 from public.user_profiles up
     where up.id = p_founder_user_profile_id and up.status <> 'active'
  ) then
    raise exception 'F6_A03_INVALID_FOUNDER: perfil do primeiro Admin nao esta ativo';
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
  --      (`conceder_acesso_role_rpc`) permanece INTOCADO - inclusive o
  --      anti-self-escalation (D5).
  perform public.conceder_acesso_role(v_membership, v_role, p_actor_user_profile_id);

  -- (11) Trilha D18 append-only, com autoria SOBERANA do operador verificado.
  insert into public.privilege_mutation_audit (
    organization_id, membership_id, access_role_id, action, actor_user_profile_id
  ) values (
    v_org, v_membership, v_role, 'grant', p_actor_user_profile_id
  );

  -- (11.1) F6-A11/D24: ANCORA FUNCIONAL do primeiro Admin pelo PRIMITIVO canonico
  --        da F5-07. Ele grava, na MESMA transacao, `collaborators` +
  --        `collaborator_identifiers` (linha ABERTA) + `collaborator_status_periods`
  --        + evento `ADMISSAO`, e revalida o ator no banco
  --        (`colaborador_ator_valido`): o founder ja tem perfil ativo (8) e
  --        membership ativa (9), portanto e um ator valido. `admission_date` e
  --        `status_inicial` ficam a cargo do default canonico (NULL / `active`).
  --        O `operation_id` e o MESMO da operacao de plataforma: a unicidade
  --        `(organization_id, operation_id)` de `collaborator_events` permanece
  --        como segunda barreira contra duplicacao do evento.
  v_collaborator := public.colaborador_criar(
    v_org,
    p_founder_user_profile_id,
    p_operation_id,
    v_full_name,
    v_email,
    v_matricula,
    null,
    null
  );

  -- (11.2) F6-A11/D24: VINCULO F5-02 pelo primitivo canonico (F5-02 D9), NUNCA
  --        por INSERT direto (Issue §5). Ele valida mesmo tenant, no maximo 1
  --        vinculo ativo por membership (Q6=B) e por colaborador/organizacao
  --        (Q3=B) - as unicidades parciais seguem como backstop.
  perform public.vincular_colaborador(v_membership, v_collaborator);

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
  -- F6-A11: a ancora funcional e parte do estado CONFIRMADO do tenant.
  if not exists (
    select 1 from public.collaborators c
     where c.id = v_collaborator and c.organization_id = v_org
  ) then
    raise exception 'F6_A11_INTERNAL: colaborador do primeiro Admin nao persistido';
  end if;
  if not exists (
    select 1 from public.collaborator_identifiers i
     where i.collaborator_id = v_collaborator
       and i.organization_id = v_org
       and i.business_code = v_matricula
       and i.valid_to is null
  ) then
    raise exception 'F6_A11_INTERNAL: identificador aberto do primeiro Admin nao persistido';
  end if;
  if not exists (
    select 1 from public.collaborator_status_periods sp
     where sp.collaborator_id = v_collaborator
       and sp.status = 'active'
       and sp.valid_to is null
  ) then
    raise exception 'F6_A11_INTERNAL: periodo de status ativo do primeiro Admin nao persistido';
  end if;
  if not exists (
    select 1 from public.membership_collaborator_links l
     where l.membership_id = v_membership
       and l.collaborator_id = v_collaborator
       and l.organization_id = v_org
       and l.status = 'active'
  ) then
    raise exception 'F6_A11_INTERNAL: vinculo F5-02 do primeiro Admin nao persistido';
  end if;

  return v_org;
end;
$fn$;

comment on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text) is
  'F6-A03 (Issue #266) + F6-A11 (Issue #273): provisionamento INICIAL de um '
  'tenant pelo PLANO DE PLATAFORMA - cria a organizacao, garante as linhas '
  'globais de user_profiles do founder (D16) e do ator (D17), cria a membership '
  'ativa do primeiro Admin, concede a role de sistema `admin` resolvida '
  'NOMINALMENTE pelo primitivo conceder_acesso_role (F4-01) com trilha D18 e - '
  'F6-A11/D24 - cria a ANCORA FUNCIONAL do primeiro Admin na MESMA transacao: '
  'colaborador (nome humano em collaborators.full_name, D22) + identificador '
  'ABERTO (matricula declarada, D23) + periodo de status ativo + evento ADMISSAO '
  'pelo primitivo colaborador_criar (F5-07) e vinculo F5-02 ativo pelo primitivo '
  'vincular_colaborador (F5-02 D9). Idempotente por operation_id + payload_hash '
  'server-side (que inclui nome/matricula/e-mail, D25): mesmo payload => replay '
  'do organization_id; payload divergente => recusa fail-closed. CONTIDA POR '
  'CONSTRUCAO: so insere organizacao NOVA e nunca toca tenant preexistente. '
  'SECURITY INVOKER, search_path fixo, EXECUTE somente service_role.';

-- Fronteira de execucao: sem superficie para `authenticated`/`anon`.
revoke all on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- (C) GUARDA fail-closed da propria migration
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_def          text;
  v_policies     integer;
  v_rls          boolean;
  v_colunas      integer;
  v_admin_n      integer;
  v_catalogo     integer;
  v_bundle       integer;
  v_auth_exec    integer;
begin
  -- (1) A assinatura ANTIGA nao pode existir (D25): sobrecarga viva seria um
  --     caminho de bootstrap sem a ancora funcional.
  if to_regprocedure('public.organizacao_provisionar_inicial(uuid, text, uuid, uuid)') is not null then
    raise exception 'F6_A11: assinatura ANTIGA (4 parametros) ainda existe';
  end if;
  if to_regprocedure('public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)') is null then
    raise exception 'F6_A11: assinatura nova ausente';
  end if;

  -- (2) RPC: SECURITY INVOKER (nao DEFINER), search_path fixo, EXECUTE so
  --     service_role, e uso dos PRIMITIVOS canonicos (nao de DML direto no
  --     vinculo F5-02).
  select pg_get_functiondef(
    'public.organizacao_provisionar_inicial(uuid, text, uuid, uuid, text, text, text)'::regprocedure
  ) into v_def;
  if position('SECURITY DEFINER' in v_def) <> 0 then
    raise exception 'F6_A11: organizacao_provisionar_inicial nao pode ser SECURITY DEFINER';
  end if;
  if position('search_path' in replace(v_def, ' ', '')) = 0 then
    raise exception 'F6_A11: organizacao_provisionar_inicial sem search_path fixo';
  end if;
  if position('colaborador_criar' in v_def) = 0 then
    raise exception 'F6_A11: bootstrap nao usa o primitivo colaborador_criar';
  end if;
  if position('vincular_colaborador' in v_def) = 0 then
    raise exception 'F6_A11: bootstrap nao usa o primitivo vincular_colaborador';
  end if;
  -- Issue §5: o vinculo NUNCA e criado por DML direto. A busca e feita no corpo
  -- da FUNCAO (`v_def`); a guarda desta migration nao faz parte do
  -- `pg_get_functiondef` analisado.
  if position('insert into public.membership_collaborator_links' in lower(v_def)) <> 0 then
    raise exception 'F6_A11: bootstrap faz INSERT direto em membership_collaborator_links';
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
    raise exception 'F6_A11: organizacao_provisionar_inicial com EXECUTE indevido (public/anon/authenticated)';
  end if;

  -- (3) D29: a trilha de plataforma permanece INTOCADA (RLS, ZERO policy e
  --     exatamente as 8 colunas originais - nenhuma coluna nova).
  select c.relrowsecurity into v_rls
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'platform_provisioning_events';
  if v_rls is not true then
    raise exception 'F6_A11: platform_provisioning_events sem RLS habilitado';
  end if;
  select count(*) into v_policies
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'platform_provisioning_events';
  if v_policies <> 0 then
    raise exception 'F6_A11: platform_provisioning_events deveria ter ZERO policy (tem %)', v_policies;
  end if;
  select count(*) into v_colunas
    from information_schema.columns
   where table_schema = 'public' and table_name = 'platform_provisioning_events';
  if v_colunas <> 8 then
    raise exception 'F6_A11: platform_provisioning_events deveria manter 8 colunas (tem %)', v_colunas;
  end if;

  -- (4) Invariantes herdados INTACTOS: exatamente 1 role de sistema `admin`
  --     ativa, catalogo com 31 capabilities e bundle `admin` com 9 funcionais
  --     (nenhuma capability nova; nenhuma role nova).
  select count(*) into v_admin_n
    from public.access_roles r
   where r.is_system = true and r.name = 'admin' and r.status = 'active';
  if v_admin_n <> 1 then
    raise exception 'F6_A11: esperada EXATAMENTE 1 role de sistema admin ativa (encontradas %)', v_admin_n;
  end if;

  select count(*) into v_catalogo from public.capabilities;
  if v_catalogo <> 31 then
    raise exception 'F6_A11: catalogo de capabilities deveria ter 31 codigos (tem %)', v_catalogo;
  end if;

  select count(*) into v_bundle
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
   where r.name = 'admin' and r.is_system = true;
  if v_bundle <> 9 then
    raise exception 'F6_A11: bundle admin deveria manter 9 capabilities funcionais (tem %)', v_bundle;
  end if;

  raise notice '[PASS] F6-A11: bootstrap com ancora funcional (colaborador + identificador aberto + status + evento ADMISSAO + vinculo F5-02) instalado por primitivos canonicos; assinatura antiga removida; INVOKER/search_path/EXECUTE so service_role; catalogo 31 e bundle admin 9 intactos';
end $guarda$;
