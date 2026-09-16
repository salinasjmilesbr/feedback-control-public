-- ============================================================================
-- F5-11 P5.1 (Issue #252): SELF/read soberano de observacoes COMUNICADAS
-- ----------------------------------------------------------------------------
-- Base: 970c257e5b1b2ff3ec7ad3f148681f337a558258 (P1-P5 integradas).
-- Escopo desta migration (LOTE SQL):
--   A  preflight fail-closed (P2/P3 instaladas; catalogo 31; observacoes_gestor
--      com EXATAMENTE as 4 capabilities; `admin` com ZERO observation.*);
--   B  5o role de SISTEMA `observacoes_avaliado` com EXATAMENTE
--      `observation.read` (SEM create/edit/delete, SEM scope);
--   C  D18 (`privilege_mutation_audit`): allowlist de `action` ampliada para
--      `system_grant`/`system_revoke` + ator NULLABLE com constraint
--      DISCRIMINANTE bicondicional (humano exige ator; sistema exige NULL);
--   D  representacao SISTEMA na ASSIGNMENT: `origin` + `created_by` nullable com
--      constraint discriminante (espelho do D18) — o beneficiario NUNCA aparece
--      como ator humano ficticio e nenhum UUID sentinela e' usado;
--   E  provisionamento AUTOMATICO por elegibilidade (triggers de TABELA,
--      SECURITY INVOKER, `search_path` fixo, sem advisory lock);
--   F  BACKFILL idempotente das memberships ja elegiveis;
--   G  guardas finais fail-closed (dois perfis com observation.*; zero scope;
--      admin intacto; D18 coerente).
--
-- Decisao arquitetural (orquestrador): SELF/read e' AUTOMATICO para todo
-- avaliado ELEGIVEL (membership + perfil + vinculo ATIVOS). Elegibilidade
-- comeca SOMENTE com vinculo ativo: membership sem vinculo NAO recebe role.
-- NAO altera `observacoes_gestor`, `admin`, catalogo (31), RPCs P2/P3, Edge.
--
-- LIMITACAO DECLARADA (P5.1): NAO existe trigger para `user_profiles.status` (o
-- escopo aprovado cobre os dois triggers de TABELA: vinculo e membership). Se o
-- perfil for inativado sem alteracao de membership/vinculo, a MATERIALIZACAO da
-- assignment pode ficar defasada; a AUTORIZACAO permanece FAIL-CLOSED porque
-- `resolver_capabilities_efetivas` (F5-04) exige perfil ATIVO.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- A) PREFLIGHT fail-closed
-- ----------------------------------------------------------------------------
do $pre$
declare
  v_catalogo integer;
  v_role     uuid;
  v_n        integer;
begin
  select count(*) into v_catalogo from public.capabilities;
  if v_catalogo <> 31 then
    raise exception 'F5_11_P5_1_PREFLIGHT: catalogo deveria ter 31 capabilities (tem %)', v_catalogo;
  end if;

  -- P2/P3 instaladas: a RPC soberana de listagem e' o ponto de extensao do SELF.
  if to_regprocedure('public.observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)') is null then
    raise exception 'F5_11_P5_1_PREFLIGHT: observacao_listar_por_escopo (P2/P3) ausente';
  end if;

  select id into v_role from public.access_roles
   where name = 'observacoes_gestor' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    raise exception 'F5_11_P5_1_PREFLIGHT: perfil observacoes_gestor ausente';
  end if;

  select count(*) into v_n
    from public.access_role_capabilities m
    join public.capabilities c on c.id = m.capability_id
   where m.access_role_id = v_role
     and c.code in ('observation.read','observation.create','observation.edit','observation.delete');
  if v_n <> 4 then
    raise exception 'F5_11_P5_1_PREFLIGHT: observacoes_gestor deveria manter 4 capabilities (tem %)', v_n;
  end if;

  -- `admin` permanece SEM observation.* (invariante nao negociavel).
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.name = 'admin' and c.code like 'observation.%'
  ) then
    raise exception 'F5_11_P5_1_PREFLIGHT: admin nao pode ter observation.*';
  end if;

  raise notice 'F5-11 P5.1: preflight OK (catalogo 31; P2/P3 instaladas; observacoes_gestor com 4; admin sem observation.*)';
end $pre$;

-- ----------------------------------------------------------------------------
-- B) 5o perfil de SISTEMA: `observacoes_avaliado` (EXATAMENTE observation.read)
-- ----------------------------------------------------------------------------
-- Molde normativo: `observacoes_gestor` (P3, 20260932000000:165-241). Diferenca
-- deliberada: aqui ha' UM unico codigo de capability e NENHUM scope — o SELF e'
-- isento de scope pelo gate (P3 §8 linha 2; P3:518-526 / :408-415).
do $role$
declare
  v_role     uuid;
  v_cap      uuid;
  v_catalogo integer;
  v_n        integer;
begin
  select count(*) into v_catalogo from public.capabilities;

  select id into v_role
    from public.access_roles
   where name = 'observacoes_avaliado' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    insert into public.access_roles (name, status, is_system, organization_id)
    values ('observacoes_avaliado', 'active', true, null)
    returning id into v_role;
  end if;

  select c.id into v_cap
    from public.capabilities c
   where c.code = 'observation.read'
     and c.status = 'active' and c.deprecated = false
     and c.grantable_via_role = true;
  if v_cap is null then
    raise exception 'F5_11_P5_1_BUNDLE: capability observation.read indisponivel';
  end if;

  insert into public.access_role_capabilities (access_role_id, capability_id)
  select v_role, v_cap
   where not exists (
     select 1 from public.access_role_capabilities m
      where m.access_role_id = v_role and m.capability_id = v_cap);

  -- ---- Guarda fail-closed do bundle (conjunto EXATO de 1) ----
  if (select count(*) from public.capabilities) <> v_catalogo then
    raise exception 'F5_11_P5_1_BUNDLE: catalogo de capabilities mudou de tamanho';
  end if;
  select count(*) into v_n
    from public.access_role_capabilities m
    join public.capabilities c on c.id = m.capability_id
   where m.access_role_id = v_role;
  if v_n <> 1 then
    raise exception 'F5_11_P5_1_BUNDLE: observacoes_avaliado deveria ter EXATAMENTE 1 capability (tem %)', v_n;
  end if;
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_role
       and c.code <> 'observation.read'
  ) then
    raise exception 'F5_11_P5_1_BUNDLE: observacoes_avaliado tem capability diferente de observation.read';
  end if;
  if not exists (
    select 1 from public.access_roles
     where id = v_role and is_system = true and organization_id is null and status = 'active'
  ) then
    raise exception 'F5_11_P5_1_BUNDLE: observacoes_avaliado nao e role de sistema ativa sem organizacao';
  end if;

  -- Coerencia com o NOVO FATO APROVADO: existem DOIS (e apenas dois) perfis de
  -- sistema com `observation.*` — `observacoes_gestor` (gestao, 4 codigos) e
  -- `observacoes_avaliado` (SELF, 1 codigo). Nenhuma OUTRA role de sistema pode
  -- portar capability de observacao, e `admin` segue com zero.
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and r.name not in ('observacoes_gestor', 'observacoes_avaliado')
       and c.code like 'observation.%'
  ) then
    raise exception 'F5_11_P5_1_BUNDLE: observation.* concedida a role de sistema FORA de {observacoes_gestor, observacoes_avaliado}';
  end if;
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.name = 'admin' and c.code like 'observation.%'
  ) then
    raise exception 'F5_11_P5_1_BUNDLE: admin nao pode ter observation.*';
  end if;

  raise notice 'F5-11 P5.1: perfil `observacoes_avaliado` (5o role de sistema) com EXATAMENTE observation.read; catalogo intacto; admin e metas_* intactos';
end $role$;

-- ----------------------------------------------------------------------------
-- C) D18 — trilha append-only passa a distinguir evento HUMANO de SISTEMA
-- ----------------------------------------------------------------------------
-- Regra: `grant`/`revoke` exigem ator HUMANO real; `system_grant`/`system_revoke`
-- exigem ator NULL (o beneficiario NAO e' ator; nada de UUID sentinela e nada de
-- identidade humana sintetica). O beneficiario permanece identificavel pelo
-- alvo da propria linha (organization_id + membership_id + access_role_id).
alter table public.privilege_mutation_audit
  drop constraint ck_privilege_mutation_audit_action;
alter table public.privilege_mutation_audit
  add constraint ck_privilege_mutation_audit_action
  check (action in ('grant', 'revoke', 'system_grant', 'system_revoke'));

alter table public.privilege_mutation_audit
  alter column actor_user_profile_id drop not null;

alter table public.privilege_mutation_audit
  add constraint ck_privilege_mutation_audit_actor_por_action
  check (
    case
      when action in ('system_grant', 'system_revoke') then actor_user_profile_id is null
      else actor_user_profile_id is not null
    end
  ) not valid;
alter table public.privilege_mutation_audit
  validate constraint ck_privilege_mutation_audit_actor_por_action;

comment on table public.privilege_mutation_audit is $c$
F5-04 (D18) + F5-11 P5.1: trilha append-only de mutacoes de privilegio
(grant/revoke HUMANO com autoria soberana; system_grant/system_revoke
AUTOMATICOS por elegibilidade, sem ator humano). Linhas imutaveis; sem FK de
historico.
$c$;

comment on column public.privilege_mutation_audit.action is $c$
grant | revoke (mutacao humana) | system_grant | system_revoke (provisionamento
automatico por elegibilidade - F5-11 P5.1).
$c$;

comment on column public.privilege_mutation_audit.actor_user_profile_id is $c$
Autoria soberana da mutacao HUMANA (derivada de auth.uid() server-side). NULL e
LEGITIMO APENAS em system_grant/system_revoke: nesse caminho o beneficiario da
concessao e identificado pelo alvo da linha (organization_id + membership_id +
access_role_id) e NUNCA como ator.
$c$;

-- ----------------------------------------------------------------------------
-- D) ASSIGNMENT — representacao SISTEMA (origin) sem ator humano ficticio
-- ----------------------------------------------------------------------------
-- `created_by` continua sendo a autoria HUMANA; o provisionamento automatico
-- grava `origin = 'system'` e `created_by` NULL. Beneficiario identificavel por
-- `membership_id` (a membership nunca e' apagada: revogacao e' por status).
alter table public.membership_access_role_assignments
  add column origin text not null default 'human';

alter table public.membership_access_role_assignments
  add constraint ck_membership_access_role_assignments_origin
  check (origin in ('human', 'system'));

alter table public.membership_access_role_assignments
  alter column created_by drop not null;

alter table public.membership_access_role_assignments
  add constraint ck_membership_access_role_assignments_author_por_origin
  check (
    case
      when origin = 'system' then created_by is null
      else created_by is not null
    end
  ) not valid;
alter table public.membership_access_role_assignments
  validate constraint ck_membership_access_role_assignments_author_por_origin;

comment on column public.membership_access_role_assignments.origin is $c$
human | system (F5-11 P5.1). human = concessao/revogacao por ator (created_by
obrigatorio); system = provisionamento AUTOMATICO por elegibilidade (created_by
NULL, beneficiario identificado por membership_id).
$c$;

comment on column public.membership_access_role_assignments.created_by is $c$
Autoria HUMANA da atribuicao. NULL e LEGITIMO APENAS quando origin = system
(F5-11 P5.1); nunca usar UUID sentinela nem o beneficiario.
$c$;

-- ----------------------------------------------------------------------------
-- E) PROVISIONAMENTO AUTOMATICO — uma funcao (fonte unica) + triggers de TABELA
-- ----------------------------------------------------------------------------
-- Decisao: UPSERT DIRETO (nao reutilizamos `conceder_acesso_role`) porque o
-- primitivo exige ator humano (`created_by` NOT NULL/`origin='human'`) e
-- inseriria a atribuicao como se fosse humana — o que o orquestrador reprovou.
-- O upsert direto preserva `on conflict (membership_id, access_role_id)`
-- (reativacao NO LUGAR, nunca DELETE) e grava `origin='system'`.
--
-- Idempotencia e ausencia de EVENTO FALSO: a funcao le a assignment da
-- membership (`for update`, lock de LINHA — sem advisory lock) e so' grava
-- evento quando ha' TRANSICAO REAL (criacao ou mudanca de status). Replay em
-- estado ja' correto nao gera linha de assignment nem evento.
--
-- Elegibilidade: membership `active` + `user_profiles.status='active'` +
-- vinculo `active`. Membership SEM vinculo NAO e' elegivel.
create or replace function public.f5_11_p5_1_provisionar_observacoes_avaliado(p_membership_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_role       uuid;
  v_org        uuid;
  v_profile    uuid;
  v_perfil_ativo boolean;
  v_vinculo_ativo boolean;
  v_membership_ativa boolean;
  v_elegivel   boolean;
  v_assignment uuid;
  v_status     text;
  v_acao       text;
begin
  select id into v_role from public.access_roles
   where name = 'observacoes_avaliado' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    return 'none';  -- fail-closed: sem perfil aprovado, nada e' provisionado
  end if;

  select m.organization_id, m.user_profile_id, (m.status = 'active'), (up.status = 'active')
    into v_org, v_profile, v_membership_ativa, v_perfil_ativo
    from public.user_organization_memberships m
    join public.user_profiles up on up.id = m.user_profile_id
   where m.id = p_membership_id;
  if v_org is null then
    return 'none';
  end if;

  select (l.status = 'active') into v_vinculo_ativo
    from public.membership_collaborator_links l
   where l.membership_id = p_membership_id;
  v_vinculo_ativo := coalesce(v_vinculo_ativo, false);

  v_elegivel := v_membership_ativa and v_perfil_ativo and v_vinculo_ativo;

  select a.id, a.status into v_assignment, v_status
    from public.membership_access_role_assignments a
   where a.membership_id = p_membership_id and a.access_role_id = v_role
     for update;

  if v_elegivel then
    if v_assignment is null then
      insert into public.membership_access_role_assignments
        (membership_id, organization_id, access_role_id, status, origin, created_by)
      values (p_membership_id, v_org, v_role, 'active', 'system', null);
      v_acao := 'system_grant';
    elsif v_status <> 'active' then
      update public.membership_access_role_assignments
         set status = 'active', origin = 'system', created_by = null,
             updated_at = now(), version = version + 1
       where id = v_assignment;
      v_acao := 'system_grant';
    else
      return 'none';  -- ja' ativo: SEM evento falso e SEM escrita
    end if;
  else
    if v_assignment is null then
      return 'none';  -- inelegivel sem historico: nada a revogar
    elsif v_status = 'active' then
      update public.membership_access_role_assignments
         set status = 'revoked', updated_at = now(), version = version + 1
       where id = v_assignment;
      v_acao := 'system_revoke';
    else
      return 'none';  -- ja' revogado: idempotente
    end if;
  end if;

  -- Evento AUTOMATICO: ator NULL (o beneficiario nao e' ator); alvo inequivoco.
  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values (v_org, p_membership_id, v_role, v_acao, null);

  return v_acao;
end $fn$;

comment on function public.f5_11_p5_1_provisionar_observacoes_avaliado(uuid) is $c$
F5-11 P5.1: provisiona/revoga observacoes_avaliado para UMA membership por
ELEGIBILIDADE (membership + perfil + vinculo ativos). Idempotente: grava evento
system_grant/system_revoke SOMENTE em transicao real; reativacao NO LUGAR (on
conflict por unicidade membership + role); nunca DELETE. SECURITY INVOKER,
search_path fixo, sem advisory lock.
$c$;

revoke all on function public.f5_11_p5_1_provisionar_observacoes_avaliado(uuid)
  from public, anon, authenticated;
grant execute on function public.f5_11_p5_1_provisionar_observacoes_avaliado(uuid)
  to service_role;

-- Trigger 1: nascimento/alteracao do VINCULO decide a elegibilidade.
create or replace function public.f5_11_p5_1_trigger_vinculo_observacoes_avaliado()
returns trigger
language plpgsql
security invoker
set search_path = public
as $fn$
begin
  perform public.f5_11_p5_1_provisionar_observacoes_avaliado(new.membership_id);
  return null;
end $fn$;

-- Trigger 2: status da MEMBERSHIP (inativacao/reativacao). Membership sem
-- vinculo continua NAO elegivel (a funcao trata).
create or replace function public.f5_11_p5_1_trigger_membership_observacoes_avaliado()
returns trigger
language plpgsql
security invoker
set search_path = public
as $fn$
begin
  perform public.f5_11_p5_1_provisionar_observacoes_avaliado(new.id);
  return null;
end $fn$;

drop trigger if exists trg_f5_11_p5_1_vinculo on public.membership_collaborator_links;
create trigger trg_f5_11_p5_1_vinculo
  after insert or update of status on public.membership_collaborator_links
  for each row execute function public.f5_11_p5_1_trigger_vinculo_observacoes_avaliado();

drop trigger if exists trg_f5_11_p5_1_membership on public.user_organization_memberships;
create trigger trg_f5_11_p5_1_membership
  after update of status on public.user_organization_memberships
  for each row execute function public.f5_11_p5_1_trigger_membership_observacoes_avaliado();

-- ----------------------------------------------------------------------------
-- F) BACKFILL idempotente das memberships JA' elegiveis
-- ----------------------------------------------------------------------------
-- Reutiliza a MESMA funcao (fonte unica de regra). Replay: nenhuma assignment
-- duplicada e nenhum evento falso (a funcao so' grava em transicao real).
do $backfill$
declare
  v_membership uuid;
  v_acao       text;
  v_grants     integer := 0;
  v_revokes    integer := 0;
  v_total      integer := 0;
begin
  for v_membership in
    select m.id
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
      join public.membership_collaborator_links l
        on l.membership_id = m.id and l.status = 'active'
     where m.status = 'active'
     order by m.id
  loop
    v_acao := public.f5_11_p5_1_provisionar_observacoes_avaliado(v_membership);
    v_total := v_total + 1;
    if v_acao = 'system_grant' then
      v_grants := v_grants + 1;
    elsif v_acao = 'system_revoke' then
      v_revokes := v_revokes + 1;
    end if;
  end loop;

  raise notice 'F5-11 P5.1: backfill avaliou % memberships elegiveis (system_grant=%, system_revoke=%, sem transicao=%)',
    v_total, v_grants, v_revokes, v_total - v_grants - v_revokes;
end $backfill$;

-- ----------------------------------------------------------------------------
-- G) GUARDAS FINAIS fail-closed
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_role     uuid;
  v_admin    uuid;
  v_n        integer;
begin
  select id into v_role from public.access_roles
   where name = 'observacoes_avaliado' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    raise exception 'F5_11_P5_1_GUARDA: perfil observacoes_avaliado ausente';
  end if;

  select count(*) into v_n
    from public.access_role_capabilities m
    join public.capabilities c on c.id = m.capability_id
   where m.access_role_id = v_role and c.code = 'observation.read';
  if v_n <> 1 then
    raise exception 'F5_11_P5_1_GUARDA: observacoes_avaliado sem observation.read';
  end if;

  -- ZERO scope: o SELF e' isento de scope de gestao; nenhuma linha de scope
  -- pode existir para as assignments deste perfil.
  select count(*) into v_n
    from public.access_role_assignment_scopes s
    join public.membership_access_role_assignments a on a.id = s.assignment_id
   where a.access_role_id = v_role;
  if v_n <> 0 then
    raise exception 'F5_11_P5_1_GUARDA: observacoes_avaliado NAO pode ter scope (tem %)', v_n;
  end if;

  -- Exatamente DOIS perfis de sistema com observation.* (aprovado).
  select count(distinct r.name) into v_n
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
    join public.capabilities c on c.id = m.capability_id
   where r.is_system = true and c.code like 'observation.%';
  if v_n <> 2 then
    raise exception 'F5_11_P5_1_GUARDA: deveria haver EXATAMENTE 2 perfis de sistema com observation.* (tem %)', v_n;
  end if;

  select id into v_admin from public.access_roles where name = 'admin' and is_system = true;
  if v_admin is not null and exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_admin and c.code like 'observation.%'
  ) then
    raise exception 'F5_11_P5_1_GUARDA: admin com observation.*';
  end if;

  -- D18 + assignment: constraints discriminantes presentes.
  if not exists (
    select 1 from pg_constraint
     where conname = 'ck_privilege_mutation_audit_actor_por_action'
       and conrelid = 'public.privilege_mutation_audit'::regclass and convalidated
  ) then
    raise exception 'F5_11_P5_1_GUARDA: constraint discriminante do D18 ausente/invalida';
  end if;
  if not exists (
    select 1 from pg_constraint
     where conname = 'ck_membership_access_role_assignments_author_por_origin'
       and conrelid = 'public.membership_access_role_assignments'::regclass and convalidated
  ) then
    raise exception 'F5_11_P5_1_GUARDA: constraint discriminante da assignment ausente/invalida';
  end if;
  if not exists (
    select 1 from pg_trigger
     where tgname = 'trg_f5_11_p5_1_vinculo' and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
     where tgname = 'trg_f5_11_p5_1_membership' and not tgisinternal
  ) then
    raise exception 'F5_11_P5_1_GUARDA: triggers de provisionamento ausentes';
  end if;

  raise notice 'F5-11 P5.1: guardas finais OK (1 capability; zero scope; 2 perfis com observation.*; admin intacto; D18 e assignment coerentes; triggers ativos)';
end $guarda$;
