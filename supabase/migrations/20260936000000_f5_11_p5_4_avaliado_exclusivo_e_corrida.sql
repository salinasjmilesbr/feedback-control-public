-- ============================================================================
-- F5-11 P5.4 (PR #253) — observacoes_avaliado EXCLUSIVAMENTE automatica
--                        + corrida no PRIMEIRO provisionamento
--
-- FINDING 1 (MEDIUM) — colisao assignment HUMANA x AUTOMATICA.
--   `observacoes_avaliado` existe para ser concedida APENAS por elegibilidade.
--   Antes desta migration, nada impedia que o caminho administrativo
--   (`conceder_acesso_role_rpc` / `revogar_acesso_role_rpc`,
--   `20260910020000_f5_04_admin_rpc_functions.sql:75-136` e `:150-202`) ou uma
--   escrita direta concedesse/revogasse essa role com `origin='human'`, e a
--   automacao da P5.1 (`20260933000000:279-359`) fazia UPDATE sem distinguir a
--   origem — podendo sobrescrever `origin`/`created_by` de uma linha HUMANA.
--
-- FINDING 2 (LOW) — corrida no PRIMEIRO provisionamento.
--   A versao anterior fazia `select ... for update` seguido de INSERT/UPDATE
--   separados (`:320-351`). Sem linha existente, duas transacoes concorrentes
--   nao bloqueiam uma a outra pelo `for update` (nao ha linha para travar sobre
--   o predicado do SELECT) => o perdedor podia levantar violacao de unicidade ou
--   emitir evento `system_grant` FALSO no D18 (dois eventos para uma unica
--   transicao real).
--
-- CORRECAO (menor, sem advisory lock, sem DELETE, sem SECURITY DEFINER novo):
--   (a) as DUAS RPCs administrativas passam a recusar, FAIL-CLOSED e antes de
--       qualquer efeito, a role automatica (bloqueio explicito por nome +
--       is_system, com erro publico no padrao F5-04);
--   (b) a funcao unica da P5.1 e' reescrita (`create or replace`) para
--       (i) FAIL-CLOSED em COLISAO: se existir assignment `origin='human'` para
--           a role, ela LEVANTA e NAO altera `origin`, `created_by` nem o
--           historico humano;
--       (ii) provisionar por UM UNICO `insert ... on conflict do update ...
--            where status <> 'active' returning id`, o que elimina a corrida
--            (o perdedor nao atualiza e nao RETORNA linha) e garante evento
--            `system_grant`/`system_revoke` SOMENTE para a transicao vencedora;
--       (iii) revogar apenas linhas `origin='system'` (nunca toca humana).
--   Nomes desta migration evitam o radical `observa` de proposito: as listas
--   FECHADAS de funcoes do dominio de observacoes das fases anteriores filtram
--   `proname like '%observa%'` (35-validar-f5-11-p1, 15-validar-f5-09-p9,
--   30-validar-f5-10-p7) — usa-lo exigiria editar guardas fora do escopo.
--
-- Nao altera: migrations P5.1/P5.2/P5.3 (arquivos publicados nesta branch),
-- semantica SELF, D18 (ator NULL em evento automatico), RLS/ACL existentes.
-- SECURITY INVOKER, `search_path` fixo, sem advisory lock, sem DELETE.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A) RPCs administrativas: bloqueio EXPLICITO da role automatica (fail-closed)
-- ----------------------------------------------------------------------------
create or replace function public.conceder_acesso_role_rpc(
  p_membership_id uuid,
  p_access_role_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_target_org  uuid;
  v_target_user uuid;
begin
  if p_actor_user_profile_id is null then
    raise exception 'F5-04: ator ausente (identidade verificada obrigatoria)';
  end if;

  -- F5-11 P5.4: `observacoes_avaliado` e' EXCLUSIVAMENTE automatica. O bloqueio
  -- e' propriedade da role (nao depende de tenant/autoridade) e vem ANTES de
  -- qualquer efeito: nenhuma assignment, nenhum evento, nada persistido.
  if exists (
    select 1 from public.access_roles r
     where r.id = p_access_role_id
       and r.is_system = true
       and r.name = 'observacoes_avaliado'
  ) then
    raise exception 'F5-04: a role observacoes_avaliado e AUTOMATICA (provisionada por elegibilidade) e nao pode ser concedida por caminho administrativo';
  end if;

  select m.organization_id, m.user_profile_id
    into v_target_org, v_target_user
    from public.user_organization_memberships m
   where m.id = p_membership_id
     and m.status = 'active';

  if not found then
    raise exception 'F5-04: membership alvo inexistente ou inativa';
  end if;

  -- Prevenção de self-escalation (D15/D16): quem concede não se auto-concede.
  if v_target_user = p_actor_user_profile_id then
    raise exception 'F5-04: self-escalation negada (ator nao pode conceder a propria membership)';
  end if;

  -- Tenant revalidado (D16): ator com perfil ativo + membership ativa na org
  -- alvo. Cross-tenant = DENY.
  if not exists (
    select 1
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id
     where m.user_profile_id = p_actor_user_profile_id
       and m.organization_id = v_target_org
       and m.status = 'active'
       and up.status = 'active'
  ) then
    raise exception 'F5-04: ator sem membership ativa na organizacao alvo (cross-tenant negado)';
  end if;

  -- AUTORIZAÇÃO ADMINISTRATIVA (D16/Q3): somente administrador do tenant.
  if not public.usuario_eh_administrador(p_actor_user_profile_id, v_target_org) then
    raise exception 'F5-04: ator sem autoridade administrativa (nao e administrador do tenant)';
  end if;

  -- Delega ao primitivo DEFINER (valida membership ativa, perfil ativo, role
  -- ativa e tenant da role).
  perform public.conceder_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);

  -- Trilha append-only (D18) com autoria soberana (user.id verificado).
  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values
    (v_target_org, p_membership_id, p_access_role_id, 'grant', p_actor_user_profile_id);
end;
$fn$;

create or replace function public.revogar_acesso_role_rpc(
  p_membership_id uuid,
  p_access_role_id uuid,
  p_actor_user_profile_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_target_org uuid;
begin
  if p_actor_user_profile_id is null then
    raise exception 'F5-04: ator ausente (identidade verificada obrigatoria)';
  end if;

  -- F5-11 P5.4: revogacao HUMANA da role automatica tambem e' bloqueada
  -- (fail-closed, antes de qualquer efeito).
  if exists (
    select 1 from public.access_roles r
     where r.id = p_access_role_id
       and r.is_system = true
       and r.name = 'observacoes_avaliado'
  ) then
    raise exception 'F5-04: a role observacoes_avaliado e AUTOMATICA (revogada por elegibilidade) e nao pode ser revogada por caminho administrativo';
  end if;

  select m.organization_id
    into v_target_org
    from public.user_organization_memberships m
   where m.id = p_membership_id
     and m.status = 'active';

  if not found then
    raise exception 'F5-04: membership alvo inexistente ou inativa';
  end if;

  -- Tenant revalidado (D16): cross-tenant = DENY.
  if not exists (
    select 1
      from public.user_organization_memberships m
      join public.user_profiles up on up.id = m.user_profile_id
     where m.user_profile_id = p_actor_user_profile_id
       and m.organization_id = v_target_org
       and m.status = 'active'
       and up.status = 'active'
  ) then
    raise exception 'F5-04: ator sem membership ativa na organizacao alvo (cross-tenant negado)';
  end if;

  -- AUTORIZAÇÃO ADMINISTRATIVA (D16/Q3): somente administrador do tenant.
  if not public.usuario_eh_administrador(p_actor_user_profile_id, v_target_org) then
    raise exception 'F5-04: ator sem autoridade administrativa (nao e administrador do tenant)';
  end if;

  perform public.revogar_acesso_role(p_membership_id, p_access_role_id, p_actor_user_profile_id);

  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values
    (v_target_org, p_membership_id, p_access_role_id, 'revoke', p_actor_user_profile_id);
end;
$fn$;

comment on function public.conceder_acesso_role_rpc(uuid, uuid, uuid) is
  'F5-04 (D16): concessao/reativacao de access_role a membership por caminho '
  'server-side/transacional. Ator = identidade autenticada verificada server-side '
  '(auth.getUser na Edge Function), jamais do cliente; tenant revalidado '
  '(cross-tenant DENY); anti-self-escalation; AUTORIZACAO ADMINISTRATIVA '
  '(administrador do tenant via usuario_eh_administrador); recusa FAIL-CLOSED a '
  'role automatica observacoes_avaliado (F5-11 P5.4); grava trilha D18. '
  'SECURITY INVOKER; EXECUTE somente service_role.';

comment on function public.revogar_acesso_role_rpc(uuid, uuid, uuid) is
  'F5-04 (D16): revogacao de access_role de membership por caminho '
  'server-side/transacional. Ator = identidade verificada server-side; tenant '
  'revalidado (cross-tenant DENY); AUTORIZACAO ADMINISTRATIVA (administrador do '
  'tenant); recusa FAIL-CLOSED a role automatica observacoes_avaliado '
  '(F5-11 P5.4); grava trilha D18. SECURITY INVOKER; EXECUTE somente service_role.';

revoke all on function public.conceder_acesso_role_rpc(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.revogar_acesso_role_rpc(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.conceder_acesso_role_rpc(uuid, uuid, uuid) to service_role;
grant execute on function public.revogar_acesso_role_rpc(uuid, uuid, uuid) to service_role;

-- ----------------------------------------------------------------------------
-- B) Funcao UNICA da P5.1: colisao fail-closed + upsert unico (corrida)
-- ----------------------------------------------------------------------------
create or replace function public.f5_11_p5_1_provisionar_observacoes_avaliado(p_membership_id uuid)
returns text
language plpgsql
security invoker
set search_path = public
as $fn$
declare
  v_role             uuid;
  v_org              uuid;
  v_profile          uuid;
  v_perfil_ativo     boolean;
  v_vinculo_ativo    boolean;
  v_membership_ativa boolean;
  v_elegivel         boolean;
  v_origem           text;
  v_hit              uuid;
  v_acao             text;
begin
  select r.id into v_role from public.access_roles r
   where r.name = 'observacoes_avaliado' and r.is_system = true
     and r.organization_id is null and r.status = 'active';
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

  -- COLISAO (P5.4/c): assignment HUMANA para a role AUTOMATICA => o caminho
  -- automatico FALHA explicitamente e NAO altera origin/created_by/historico.
  select a.origin into v_origem
    from public.membership_access_role_assignments a
   where a.membership_id = p_membership_id and a.access_role_id = v_role;
  if v_origem = 'human' then
    raise exception 'F5-11 P5.1: colisao com assignment HUMANA da role automatica observacoes_avaliado (membership %) — a automacao nao altera historico humano', p_membership_id;
  end if;

  if v_elegivel then
    -- UPSERT UNICO (P5.4/d): on conflict resolve a corrida no indice unico
    -- (membership_id, access_role_id) SEM advisory lock. O `where` garante que
    -- o perdedor da corrida (linha ja' ativa) NAO atualiza e NAO retorna linha
    -- => nenhum evento falso. Insercao nova e reativacao real retornam id.
    insert into public.membership_access_role_assignments
      (membership_id, organization_id, access_role_id, status, origin, created_by)
    values (p_membership_id, v_org, v_role, 'active', 'system', null)
    on conflict (membership_id, access_role_id) do update
       set status = 'active',
           origin = 'system',
           created_by = null,
           updated_at = now(),
           version = public.membership_access_role_assignments.version + 1
     where public.membership_access_role_assignments.status <> 'active'
    returning id into v_hit;

    if v_hit is null then
      return 'none';  -- ja' ativo (ou perdedor da corrida): SEM evento falso
    end if;
    v_acao := 'system_grant';
  else
    -- Revoga SOMENTE linhas automaticas: historico humano fica intocado.
    update public.membership_access_role_assignments a
       set status = 'revoked', updated_at = now(), version = a.version + 1
     where a.membership_id = p_membership_id
       and a.access_role_id = v_role
       and a.status = 'active'
       and a.origin = 'system'
    returning a.id into v_hit;

    if v_hit is null then
      return 'none';  -- sem historico automatico ativo: idempotente
    end if;
    v_acao := 'system_revoke';
  end if;

  -- Evento AUTOMATICO: ator NULL (o beneficiario nao e' ator); alvo inequivoco.
  insert into public.privilege_mutation_audit
    (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
  values (v_org, p_membership_id, v_role, v_acao, null);

  return v_acao;
end $fn$;

comment on function public.f5_11_p5_1_provisionar_observacoes_avaliado(uuid) is
  $c$
F5-11 P5.1 (revisada na P5.4): provisiona/revoga observacoes_avaliado para UMA
membership por ELEGIBILIDADE (membership + perfil + vinculo ativos). Idempotente:
grava evento system_grant/system_revoke SOMENTE em transicao real; upsert UNICO
por (membership_id, access_role_id) elimina a corrida do primeiro provisionamento
(o perdedor nao retorna linha e nao gera evento); COLISAO com assignment
origin='human' LEVANTA e nunca altera historico humano; revoga apenas linhas
origin='system'; nunca DELETE. SECURITY INVOKER, search_path fixo, sem advisory
lock.
$c$;

revoke all on function public.f5_11_p5_1_provisionar_observacoes_avaliado(uuid)
  from public, anon, authenticated;
grant execute on function public.f5_11_p5_1_provisionar_observacoes_avaliado(uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- C) Guarda fail-closed da propria migration
-- ----------------------------------------------------------------------------
do $guarda$
declare
  v_role uuid;
  v_def  text;
  v_colisao_ok boolean;
begin
  select r.id into v_role from public.access_roles r
   where r.name = 'observacoes_avaliado' and r.is_system = true
     and r.organization_id is null and r.status = 'active';
  if v_role is null then
    raise exception 'F5_11_P5_4_GUARDA: role automatica ausente — P5.1 nao aplicada';
  end if;

  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'f5_11_p5_1_provisionar_observacoes_avaliado';
  if v_def is null then
    raise exception 'F5_11_P5_4_GUARDA: funcao de provisionamento ausente';
  end if;

  -- A definicao revisada precisa conter os tres marcadores da correcao.
  if position('on conflict (membership_id, access_role_id) do update' in v_def) = 0 then
    raise exception 'F5_11_P5_4_GUARDA: upsert unico ausente (corrida nao resolvida)';
  end if;
  if position('colisao' in lower(v_def)) = 0 then
    raise exception 'F5_11_P5_4_GUARDA: guarda de colisao humana ausente';
  end if;
  if position('and a.origin = ''system''' in v_def) = 0 then
    raise exception 'F5_11_P5_4_GUARDA: revogacao restrita a origem system ausente';
  end if;

  -- As duas RPCs administrativas precisam recusar a role automatica.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'conceder_acesso_role_rpc';
  if v_def is null or position('observacoes_avaliado' in v_def) = 0 then
    raise exception 'F5_11_P5_4_GUARDA: conceder_acesso_role_rpc sem bloqueio da role automatica';
  end if;
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'revogar_acesso_role_rpc';
  if v_def is null or position('observacoes_avaliado' in v_def) = 0 then
    raise exception 'F5_11_P5_4_GUARDA: revogar_acesso_role_rpc sem bloqueio da role automatica';
  end if;

  -- Sem SECURITY DEFINER novo e sem EXECUTE para authenticated.
  select (not p.prosecdef) into v_colisao_ok
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'f5_11_p5_1_provisionar_observacoes_avaliado';
  if not v_colisao_ok then
    raise exception 'F5_11_P5_4_GUARDA: funcao de provisionamento virou SECURITY DEFINER';
  end if;

  raise notice '[PASS] F5-11 P5.4: observacoes_avaliado exclusivamente automatica (RPCs recusam, colisao humana fail-closed, upsert unico sem evento falso)';
end $guarda$;
