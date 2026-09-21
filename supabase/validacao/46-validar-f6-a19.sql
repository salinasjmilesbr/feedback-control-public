-- ============================================================================
-- F6-A19 (Issue #319): validação automatizada — CONVITE COM VÍNCULO SOBERANO
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de `46-cenario-f6-a19.sql`, como owner/superuser local, com
-- ON_ERROR_STOP ativo. Um `[PASS]` por verificação; falha aborta (código ≠ 0).
--
-- Prova, no BANCO (fonte da verdade):
--   A. invariantes da migration: 4 SECURITY DEFINER (F4-08), RPC do convite
--      INVOKER e service_role-only, D15 intacta (membership.manage não é
--      concedível e NÃO está associada a nenhuma role), bundle `admin` = 9;
--   B. predicado de autoridade `usuario_eh_administrador`: admin legítimo do
--      tenant ALLOW; role de domínio (evaluator) DENY; cross-tenant DENY; sem
--      membership DENY;
--   C. RPC `convidado_acesso_criar`: ALLOW cria perfil + membership + VÍNCULO
--      com a colaboradora e ZERO roles; cross-tenant (colaboradora de outro
--      tenant) e colaboradora inexistente ⇒ P0002 sem estado parcial; retry do
--      mesmo (usuário, organização) ⇒ 23505 sem duplicar vínculo; falha do
--      primitivo (vínculo já existente) ⇒ P0001 com ZERO perfil/membership
--      (nada parcial); colaboradora preexistente intacta;
--   D. ACL: `anon` e `authenticated` NÃO executam a RPC.
--
-- O bloco C roda em transação REVERTIDA (`begin`/`rollback`): a prova não deixa
-- estado no banco.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) Invariantes estruturais
-- ============================================================================
do $$
declare
  v_definer   integer;
  v_def       boolean;
  v_manage    boolean;
  v_vinculada integer;
  v_bundle    integer;
begin
  select count(*) into v_definer
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_definer <> 4 then
    raise exception '[FAIL] DEFINER esperado=4, encontrado=%', v_definer;
  end if;

  select p.prosecdef into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'convidado_acesso_criar';
  if v_def is not false then
    raise exception '[FAIL] convidado_acesso_criar deveria ser SECURITY INVOKER';
  end if;

  if has_function_privilege('anon', 'public.convidado_acesso_criar(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.convidado_acesso_criar(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] convidado_acesso_criar com EXECUTE para anon/authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.convidado_acesso_criar(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] convidado_acesso_criar sem EXECUTE para service_role';
  end if;

  select grantable_via_role into v_manage
    from public.capabilities where code = 'membership.manage';
  if v_manage is distinct from false then
    raise exception '[FAIL] membership.manage deveria seguir NAO concedivel por role (D15)';
  end if;

  select count(*) into v_vinculada
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code = 'membership.manage';
  if v_vinculada <> 0 then
    raise exception '[FAIL] membership.manage associada a role (%): o gate antigo era impossivel', v_vinculada;
  end if;

  select count(*) into v_bundle
    from public.access_role_capabilities rc
    join public.access_roles r on r.id = rc.access_role_id
   where r.name = 'admin' and r.is_system = true;
  if v_bundle <> 9 then
    raise exception '[FAIL] bundle admin esperado=9, encontrado=%', v_bundle;
  end if;

  raise notice '[PASS] F6-A19/A: RPC INVOKER service_role-only; 4 DEFINER, D15 e bundle admin (9) intactos; membership.manage em NENHUMA role';
end $$;

-- ============================================================================
-- B) Predicado de autoridade administrativa (gate da Edge)
-- ============================================================================
do $$
declare
  v_admin boolean;
  v_dominio boolean;
  v_cross boolean;
  v_sem_membership boolean;
begin
  v_admin := public.usuario_eh_administrador(
    'f6a19000-0000-4000-8000-000000000001', 'f6a19000-0000-4000-8000-0000000000a1');
  v_dominio := public.usuario_eh_administrador(
    'f6a19000-0000-4000-8000-000000000002', 'f6a19000-0000-4000-8000-0000000000a1');
  v_cross := public.usuario_eh_administrador(
    'f6a19000-0000-4000-8000-000000000003', 'f6a19000-0000-4000-8000-0000000000a1');
  v_sem_membership := public.usuario_eh_administrador(
    'f6a19000-0000-4000-8000-000000000004', 'f6a19000-0000-4000-8000-0000000000a1');

  if not v_admin then
    raise exception '[FAIL] admin legitimo do tenant NAO reconhecido (convite seria negado)';
  end if;
  if v_dominio then
    raise exception '[FAIL] role de dominio (evaluator) conferiu autoridade administrativa';
  end if;
  if v_cross then
    raise exception '[FAIL] cross-tenant: admin de BETA reconhecido como admin de ALFA';
  end if;
  if v_sem_membership then
    raise exception '[FAIL] usuario sem membership reconhecido como administrador';
  end if;

  raise notice '[PASS] F6-A19/B: admin legitimo ALLOW; role de dominio, cross-tenant e sem membership DENY';
end $$;

-- ============================================================================
-- C) RPC de provisionamento (transação REVERTIDA)
-- ============================================================================
begin;

set local role service_role;

do $$
declare
  v_colab_alfa uuid;
  v_colab_beta uuid;
  v_membership uuid;
  v_status text;
  v_links integer;
  v_roles integer;
  v_n integer;
  v_ok boolean;
  v_state text;
begin
  select i.collaborator_id into v_colab_alfa
    from public.collaborator_identifiers i
   where i.organization_id = 'f6a19000-0000-4000-8000-0000000000a1'
     and i.business_code = 'ACME002' and i.valid_to is null;
  select i.collaborator_id into v_colab_beta
    from public.collaborator_identifiers i
   where i.organization_id = 'f6a19000-0000-4000-8000-0000000000a2'
     and i.business_code = 'BETA001' and i.valid_to is null;
  if v_colab_alfa is null or v_colab_beta is null then
    raise exception '[FAIL] cenario sem as colaboradoras ACME002/BETA001';
  end if;

  -- (C1) ALLOW: provisiona a conta do CONVIDADO vinculada à colaboradora ACME002.
  v_membership := public.convidado_acesso_criar(
    'f6a19000-0000-4000-8000-000000000004',
    'f6a19000-0000-4000-8000-0000000000a1',
    v_colab_alfa);

  select m.status into v_status
    from public.user_organization_memberships m where m.id = v_membership;
  if v_status is distinct from 'active' then
    raise exception '[FAIL] membership do convidado nao esta ativa (%)', coalesce(v_status, 'ausente');
  end if;

  select p.status into v_status from public.user_profiles p
   where p.id = 'f6a19000-0000-4000-8000-000000000004';
  if v_status is distinct from 'active' then
    raise exception '[FAIL] perfil interno do convidado nao esta ativo (%)', coalesce(v_status, 'ausente');
  end if;

  select count(*) into v_links
    from public.membership_collaborator_links l
   where l.membership_id = v_membership
     and l.collaborator_id = v_colab_alfa
     and l.status = 'active';
  if v_links <> 1 then
    raise exception '[FAIL] vinculo conta<->colaboradora esperado=1, encontrado=%', v_links;
  end if;

  -- NENHUMA autoridade administrativa: o convite (a RPC) não concede `admin`.
  -- A role de DOMÍNIO `observacoes_avaliado` é auto-provisionada pelo trigger
  -- certificado da F5-11 P5.1 ao criar o VÍNCULO — comportamento do produto, não
  -- concessão do convite (por isso é aceita e documentada abaixo).
  select count(*) into v_roles
    from public.membership_access_role_assignments a
    join public.access_roles r on r.id = a.access_role_id
   where a.membership_id = v_membership and r.name = 'admin';
  if v_roles <> 0 then
    raise exception '[FAIL] o convite concedeu a role admin (%)', v_roles;
  end if;

  if public.usuario_eh_administrador(
       'f6a19000-0000-4000-8000-000000000004', 'f6a19000-0000-4000-8000-0000000000a1') then
    raise exception '[FAIL] o convidado passou a ter autoridade administrativa';
  end if;

  select count(*) into v_roles
    from public.membership_access_role_assignments a
    join public.access_roles r on r.id = a.access_role_id
   where a.membership_id = v_membership and r.name <> 'observacoes_avaliado';
  if v_roles <> 0 then
    raise exception '[FAIL] convite concedeu role fora do auto-provisionamento certificado (%)', v_roles;
  end if;

  select count(*) into v_roles
    from public.membership_access_role_assignments a
    join public.access_roles r on r.id = a.access_role_id
   where a.membership_id = v_membership
     and r.name = 'observacoes_avaliado'
     and r.is_system = true;
  if v_roles <> 1 then
    raise exception '[FAIL] auto-provisionamento da F5-11 P5.1 (vinculo) esperado=1, encontrado=%', v_roles;
  end if;

  -- (C2) DENY cross-tenant: colaboradora de BETA na organização ALFA.
  v_ok := false;
  begin
    perform public.convidado_acesso_criar(
      'f6a19000-0000-4000-8000-000000000005',
      'f6a19000-0000-4000-8000-0000000000a1',
      v_colab_beta);
    v_ok := true;
  exception when others then
    v_state := sqlstate;
    if v_state <> 'P0002' then
      raise exception '[FAIL] cross-tenant: esperado P0002, veio %', v_state;
    end if;
  end;
  if v_ok then
    raise exception '[FAIL] cross-tenant ACEITO (colaboradora de outro tenant)';
  end if;
  select count(*) into v_n from public.user_profiles
   where id = 'f6a19000-0000-4000-8000-000000000005';
  if v_n <> 0 then
    raise exception '[FAIL] cross-tenant deixou perfil parcial (%)', v_n;
  end if;

  -- (C3) DENY colaboradora inexistente.
  v_ok := false;
  begin
    perform public.convidado_acesso_criar(
      'f6a19000-0000-4000-8000-000000000005',
      'f6a19000-0000-4000-8000-0000000000a1',
      'f6a19000-0000-4000-8000-00000000ffff');
    v_ok := true;
  exception when others then
    v_state := sqlstate;
    if v_state <> 'P0002' then
      raise exception '[FAIL] colaboradora inexistente: esperado P0002, veio %', v_state;
    end if;
  end;
  if v_ok then
    raise exception '[FAIL] colaboradora inexistente ACEITA';
  end if;

  -- (C4) RETRY: mesma conta/organização ⇒ 23505 e NENHUM vínculo duplicado.
  v_ok := false;
  begin
    perform public.convidado_acesso_criar(
      'f6a19000-0000-4000-8000-000000000004',
      'f6a19000-0000-4000-8000-0000000000a1',
      v_colab_alfa);
    v_ok := true;
  exception when others then
    v_state := sqlstate;
    if v_state <> '23505' then
      raise exception '[FAIL] retry: esperado 23505, veio %', v_state;
    end if;
  end;
  if v_ok then
    raise exception '[FAIL] retry ACEITO (deveria colidir no perfil existente)';
  end if;
  select count(*) into v_links
    from public.membership_collaborator_links l
   where l.collaborator_id = v_colab_alfa and l.status = 'active';
  if v_links <> 1 then
    raise exception '[FAIL] retry duplicou o vinculo (ativos=%)', v_links;
  end if;

  -- (C5) FALHA PARCIAL ZERO: colaboradora já vinculada ⇒ P0001 do primitivo e
  -- nada do CONVIDADO_2 (perfil/membership) sobrevive.
  v_ok := false;
  begin
    perform public.convidado_acesso_criar(
      'f6a19000-0000-4000-8000-000000000005',
      'f6a19000-0000-4000-8000-0000000000a1',
      v_colab_alfa);
    v_ok := true;
  exception when others then
    v_state := sqlstate;
    if v_state <> 'P0001' then
      raise exception '[FAIL] vinculo duplicado: esperado P0001, veio %', v_state;
    end if;
  end;
  if v_ok then
    raise exception '[FAIL] vinculo duplicado ACEITO';
  end if;
  select count(*) into v_n from public.user_profiles
   where id = 'f6a19000-0000-4000-8000-000000000005';
  if v_n <> 0 then
    raise exception '[FAIL] falha parcial: perfil do CONVIDADO_2 persistiu (%)', v_n;
  end if;
  select count(*) into v_n from public.user_organization_memberships
   where user_profile_id = 'f6a19000-0000-4000-8000-000000000005';
  if v_n <> 0 then
    raise exception '[FAIL] falha parcial: membership do CONVIDADO_2 persistiu (%)', v_n;
  end if;

  -- (C6) A colaboradora preexistente permanece INTACTA (nem recriada nem alterada).
  select count(*) into v_n from public.collaborators
   where organization_id = 'f6a19000-0000-4000-8000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] colaboradoras em ALFA esperado=1, encontrado=%', v_n;
  end if;
  select count(*) into v_n from public.collaborators
   where id = v_colab_alfa
     and organization_id = 'f6a19000-0000-4000-8000-0000000000a1'
     and version = 0;
  if v_n <> 1 then
    raise exception '[FAIL] colaboradora ACME002 foi recriada ou alterada pela RPC';
  end if;

  raise notice '[PASS] F6-A19/C: ALLOW (perfil+membership+vinculo, ZERO autoridade administrativa; role de dominio da P5.1 vem do vinculo); cross-tenant e inexistente DENY (P0002); retry 23505 sem duplicata; falha parcial ZERO (P0001); colaboradora intacta';
end $$;

rollback;

-- ============================================================================
-- D) ACL: anon/authenticated não executam a RPC do convite
-- ============================================================================
begin;
set local role anon;
do $$
begin
  begin
    perform public.convidado_acesso_criar(
      'f6a19000-0000-4000-8000-000000000004',
      'f6a19000-0000-4000-8000-0000000000a1',
      'f6a19000-0000-4000-8000-0000000000c1');
    raise exception '[FAIL] anon executou a RPC do convite';
  exception
    when insufficient_privilege then
      raise notice '[PASS] F6-A19/D: anon nao executa convidado_acesso_criar';
  end;
end $$;
rollback;

begin;
set local role authenticated;
do $$
begin
  begin
    perform public.convidado_acesso_criar(
      'f6a19000-0000-4000-8000-000000000004',
      'f6a19000-0000-4000-8000-0000000000a1',
      'f6a19000-0000-4000-8000-0000000000c1');
    raise exception '[FAIL] authenticated executou a RPC do convite';
  exception
    when insufficient_privilege then
      raise notice '[PASS] F6-A19/D: authenticated nao executa convidado_acesso_criar';
  end;
end $$;
rollback;

do $$
begin
  raise notice '[PASS] F6-A19: convite com vinculo soberano validado (invariantes, autoridade, provisionamento, retry/falha parcial e ACL)';
end $$;
