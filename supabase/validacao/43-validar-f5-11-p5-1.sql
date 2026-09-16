-- ============================================================================
-- F5-11 P5.1 (Issue #252): VALIDADOR do SELF/read soberano (LOTE SQL)
-- Saida: [PASS]/[FAIL]; falha aborta (ON_ERROR_STOP).
-- Executar DEPOIS de: 42-cenario-f5-11-p5-1.sql (fixture/lifecycle).
-- ----------------------------------------------------------------------------
-- Contrato coberto (docs/F5-11-desenho-tecnico.md §8 D15 (emenda P5.1); §20.3;
-- §23): A bundle do 5o perfil; B assignment automatica (origin=system, sem ator
-- humano, zero scope); C lifecycle/backfill/idempotencia; D D18 (allowlist +
-- ator discriminado + append-only); E SELF le/nao le/nao muta; F cross-tenant;
-- G `observacoes_gestor`/`admin`/catalogo intactos; H higiene.
-- ============================================================================

\set ON_ERROR_STOP on

do $validar$
declare
  v_falhas       text[] := array[]::text[];
  v_role         uuid;
  v_admin        uuid;
  v_org          uuid;
  v_membership   uuid;
  v_sem_vinculo  uuid;
  v_profile      uuid;
  v_colab        uuid;
  v_obs          uuid;
  v_obs_terceiro uuid;
  v_n            integer;
  v_txt          text;
  v_acao         text;
  v_antes        integer;
  v_depois       integer;
  v_ok           boolean;
  v_mem2         uuid;
  v_org2         uuid;
  v_assign_id    uuid;
  v_assign_id2   uuid;
  v_antes2       integer;
  v_depois2      integer;
  v_humanos      integer;
  v_humanos_dep  integer;
  v_rev_antes    integer;
  v_rev_depois   integer;
  v_gestor_antes integer;
  v_gestor_dep   integer;
begin
  -- ==========================================================================
  -- A) BUNDLE do perfil novo (conjunto EXATO) e coerencia de dominio
  -- ==========================================================================
  select id into v_role from public.access_roles
   where name = 'observacoes_avaliado' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    v_falhas := v_falhas || text 'A1: perfil observacoes_avaliado ausente/nao e role de sistema ativa sem organizacao';
  else
    select count(*) into v_n from public.access_role_capabilities m
     where m.access_role_id = v_role;
    if v_n <> 1 then
      v_falhas := v_falhas || format('A2: observacoes_avaliado deveria ter EXATAMENTE 1 capability (tem %s)', v_n);
    end if;
    select count(*) into v_n
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_role and c.code = 'observation.read';
    if v_n <> 1 then
      v_falhas := v_falhas || text 'A3: observacoes_avaliado sem observation.read';
    end if;
    -- ZERO scope: o SELF e' isento de scope de gestao.
    select count(*) into v_n
      from public.access_role_assignment_scopes s
      join public.membership_access_role_assignments a on a.id = s.assignment_id
     where a.access_role_id = v_role;
    if v_n <> 0 then
      v_falhas := v_falhas || format('A4: observacoes_avaliado NAO pode ter scope (tem %s linhas)', v_n);
    end if;
  end if;

  if (select count(*) from public.capabilities) <> 31 then
    v_falhas := v_falhas || text 'A5: catalogo de capabilities deveria ter 31 codigos';
  end if;

  select count(distinct r.name) into v_n
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
    join public.capabilities c on c.id = m.capability_id
   where r.is_system = true and c.code like 'observation.%';
  if v_n <> 2 then
    v_falhas := v_falhas || format('A6: deveria haver EXATAMENTE 2 perfis de sistema com observation.* (tem %s)', v_n);
  end if;
  if exists (
    select 1
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
      join public.capabilities c on c.id = m.capability_id
     where r.is_system = true
       and r.name not in ('observacoes_gestor', 'observacoes_avaliado')
       and c.code like 'observation.%'
  ) then
    v_falhas := v_falhas || text 'A7: observation.* em role de sistema FORA do conjunto aprovado';
  end if;

  -- G) `observacoes_gestor` inalterado (4 capabilities) e admin sem observation.*
  select count(*) into v_n
    from public.access_role_capabilities m
    join public.access_roles r on r.id = m.access_role_id
    join public.capabilities c on c.id = m.capability_id
   where r.name = 'observacoes_gestor'
     and c.code in ('observation.read','observation.create','observation.edit','observation.delete');
  if v_n <> 4 then
    v_falhas := v_falhas || format('G1: observacoes_gestor deveria manter 4 capabilities de observacao (tem %s)', v_n);
  end if;
  select id into v_admin from public.access_roles where name = 'admin' and is_system = true;
  if v_admin is null then
    v_falhas := v_falhas || text 'G2: perfil admin ausente';
  elsif exists (
    select 1
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_admin and c.code like 'observation.%'
  ) then
    v_falhas := v_falhas || text 'G3: admin com observation.*';
  end if;

  -- ==========================================================================
  -- B) ASSIGNMENT AUTOMATICA (origin=system) — fixture do cenario 42
  -- ==========================================================================
  -- A organizacao NAO pode ser escolhida por prefixo: o cenario 40 da P3 registra
  -- uma organizacao-ESPELHO (prefixo `f5b3`) apenas para o guard insert-once, e a
  -- estrutura VIVA (perfis/memberships/vinculos) esta no tenant da P2. A
  -- organizacao e' portanto DERIVADA da propria membership ELEGIVEL (membership
  -- ativa + perfil ativo + vinculo ativo) — mesma derivacao do cenario 42.
  select m.organization_id into v_org
    from public.user_organization_memberships m
    join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
    join public.membership_collaborator_links l
      on l.membership_id = m.id and l.status = 'active'
   where m.status = 'active'
   order by m.id limit 1;
  if v_org is null then
    v_falhas := v_falhas || text 'B0: nenhuma organizacao com membership ELEGIVEL na fixture (rode 42-cenario antes)';
  end if;

  select m.id, m.user_profile_id into v_membership, v_profile
    from public.user_organization_memberships m
    join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
    join public.membership_collaborator_links l
      on l.membership_id = m.id and l.status = 'active'
   where m.organization_id = v_org and m.status = 'active'
   order by m.id limit 1;
  if v_membership is null then
    v_falhas := v_falhas || text 'B1: nenhuma membership elegivel na fixture';
  else
    select count(*) into v_n from public.membership_access_role_assignments a
     where a.membership_id = v_membership and a.access_role_id = v_role;
    if v_n <> 1 then
      v_falhas := v_falhas || format('B2: deveria haver EXATAMENTE 1 assignment (membership, role) — tem %s', v_n);
    end if;
    select a.origin, a.status, (a.created_by is null)
      into v_txt, v_acao, v_ok
      from public.membership_access_role_assignments a
     where a.membership_id = v_membership and a.access_role_id = v_role;
    if v_acao <> 'active' then
      v_falhas := v_falhas || format('B3: assignment deveria estar active (esta %s)', coalesce(v_acao,'<nulo>'));
    end if;
    if v_txt <> 'system' then
      v_falhas := v_falhas || format('B4: assignment automatica deveria ter origin=system (tem %s)', coalesce(v_txt,'<nulo>'));
    end if;
    if not coalesce(v_ok, false) then
      v_falhas := v_falhas || text 'B5: provisionamento automatico NAO pode gravar ator humano (created_by deve ser NULL)';
    end if;

    -- C) LIFECYCLE: inativacao -> revogacao; reativacao -> NO LUGAR; replay -> none
    update public.membership_collaborator_links
       set status = 'disabled', updated_at = now(), version = version + 1
     where membership_id = v_membership;
    select count(*) into v_n from public.membership_access_role_assignments a
     where a.membership_id = v_membership and a.access_role_id = v_role and a.status = 'revoked';
    if v_n <> 1 then
      v_falhas := v_falhas || text 'C1: inativacao do vinculo deveria revogar a assignment (por status, sem DELETE)';
    end if;

    update public.membership_collaborator_links
       set status = 'active', updated_at = now(), version = version + 1
     where membership_id = v_membership;
    select count(*) into v_n from public.membership_access_role_assignments a
     where a.membership_id = v_membership and a.access_role_id = v_role;
    if v_n <> 1 then
      v_falhas := v_falhas || format('C2: reativacao deveria REUSAR a mesma assignment (linhas=%s)', v_n);
    end if;
    select count(*) into v_n from public.membership_access_role_assignments a
     where a.membership_id = v_membership and a.access_role_id = v_role and a.status = 'active';
    if v_n <> 1 then
      v_falhas := v_falhas || text 'C3: reativacao do vinculo nao devolveu a assignment para active';
    end if;

    -- REPLAY: duas execucoes em estado correto nao geram transicao nem evento.
    select count(*) into v_antes from public.privilege_mutation_audit
     where membership_id = v_membership and access_role_id = v_role;
    v_acao := public.f5_11_p5_1_provisionar_observacoes_avaliado(v_membership);
    if v_acao <> 'none' then
      v_falhas := v_falhas || format('C4: replay em estado correto deveria devolver none (devolveu %s)', v_acao);
    end if;
    select count(*) into v_depois from public.privilege_mutation_audit
     where membership_id = v_membership and access_role_id = v_role;
    if v_depois <> v_antes then
      v_falhas := v_falhas || format('C5: replay gerou EVENTO FALSO (antes=%s depois=%s)', v_antes, v_depois);
    end if;

    -- Membership SEM vinculo NAO e' elegivel (nao recebe o perfil).
    select m.id into v_sem_vinculo
      from public.user_organization_memberships m
     where m.organization_id = v_org and m.status = 'active'
       and not exists (select 1 from public.membership_collaborator_links l where l.membership_id = m.id)
     order by m.id limit 1;
    if v_sem_vinculo is not null then
      v_acao := public.f5_11_p5_1_provisionar_observacoes_avaliado(v_sem_vinculo);
      if v_acao <> 'none' then
        v_falhas := v_falhas || text 'C6: membership SEM vinculo nao pode ser provisionada';
      end if;
      if exists (
        select 1 from public.membership_access_role_assignments a
         where a.membership_id = v_sem_vinculo and a.access_role_id = v_role and a.status = 'active'
      ) then
        v_falhas := v_falhas || text 'C7: membership sem vinculo recebeu o perfil (deveria ser fail-closed)';
      end if;
    end if;
  end if;

  -- ==========================================================================
  -- D) D18 — allowlist, ator discriminado e append-only
  -- ==========================================================================
  if v_org is not null and v_membership is not null then
    -- (D1) system_grant com ator NULL e' ACEITO pelo caminho autorizado.
    insert into public.privilege_mutation_audit
      (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
    values (v_org, v_membership, v_role, 'system_grant', null);

    -- (D2) grant HUMANO com ator NULL deve ser REJEITADO.
    v_ok := true;
    begin
      insert into public.privilege_mutation_audit
        (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
      values (v_org, v_membership, v_role, 'grant', null);
    exception when check_violation then v_ok := false;
    end;
    if v_ok then
      v_falhas := v_falhas || text 'D2: grant com ator NULL foi aceito (deveria violar a constraint discriminante)';
    end if;

    -- (D3) system_* com ator NAO nulo deve ser REJEITADO.
    v_ok := true;
    begin
      insert into public.privilege_mutation_audit
        (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
      values (v_org, v_membership, v_role, 'system_revoke', v_profile);
    exception when check_violation then v_ok := false;
    end;
    if v_ok then
      v_falhas := v_falhas || text 'D3: system_* com ator humano foi aceito (o beneficiario NAO e ator)';
    end if;

    -- (D4) action desconhecida continua REJEITADA (allowlist fechada).
    v_ok := true;
    begin
      insert into public.privilege_mutation_audit
        (organization_id, membership_id, access_role_id, action, actor_user_profile_id)
      values (v_org, v_membership, v_role, 'escalate', v_profile);
    exception when check_violation then v_ok := false;
    end;
    if v_ok then
      v_falhas := v_falhas || text 'D4: action desconhecida foi aceita';
    end if;

    -- (D5) append-only: UPDATE continua bloqueado.
    v_ok := true;
    begin
      update public.privilege_mutation_audit set action = 'revoke'
       where organization_id = v_org and membership_id = v_membership
         and access_role_id = v_role and action = 'system_grant';
    exception when others then v_ok := false;
    end;
    if v_ok then
      v_falhas := v_falhas || text 'D5: UPDATE na trilha append-only foi aceito';
    end if;
  end if;

  -- ==========================================================================
  -- E) SELF — le / nao le / nao muta, contra a FIXTURE SELF DEDICADA (prefixo
  --    f5c1) construida pelo cenario 42. O ator e' o AVALIADO PURO: com um ator
  --    de GESTAO, E2 mediria o papel de gestao (resolveria as 3 mutacoes) e E4
  --    mediria a relacao de gestao (leria o terceiro legitimamente) — foi
  --    exatamente o defeito da rodada anterior. Nenhuma prova usa [SKIP].
  -- ==========================================================================
  declare
    v_self_profile    constant uuid := 'f5c1c000-0000-0000-0000-0000000000a1';
    v_self_membership constant uuid := 'f5c1d000-0000-0000-0000-0000000000a1';
    v_self_colab      constant uuid := 'f5c1e000-0000-0000-0000-0000000000c1';
    v_terceiro_colab  constant uuid := 'f5c1e000-0000-0000-0000-0000000000c2';
    v_org_self        uuid;
    v_ciclo_self      uuid;
    v_obs_com         uuid;
    v_obs_nao         uuid;
    v_obs_exc         uuid;
    v_obs_ter         uuid;
    v_mutou           boolean;
  begin
    select m.organization_id into v_org_self
      from public.user_organization_memberships m
     where m.id = v_self_membership;

    if v_org_self is null then
      v_falhas := v_falhas || text 'E0: fixture SELF dedicada ausente (o cenario 42 nao criou o AVALIADO PURO)';
    else
      -- (E1) a capability chega pelo resolver soberano SEM scope (achado da P5.1).
      select count(*) into v_n
        from public.resolver_capabilities_efetivas(v_self_profile, v_org_self) r
       where r.capability_code = 'observation.read';
      if v_n < 1 then
        v_falhas := v_falhas || text 'E1: o AVALIADO PURO nao resolve observation.read apos o provisionamento automatico';
      end if;

      -- (E2) ZERO mutacao SELF: o perfil provisionado concede SOMENTE leitura.
      select count(*) into v_n
        from public.resolver_capabilities_efetivas(v_self_profile, v_org_self) r
       where r.capability_code in ('observation.create','observation.edit','observation.delete');
      if v_n <> 0 then
        v_falhas := v_falhas || format('E2: AVALIADO PURO resolveu %s capability(ies) de mutacao (deveria ser 0)', v_n);
      end if;

      -- (E3) listagem SELF e' AUTORIZADA (nao lanca) — o blocker da P5 deixa de existir.
      begin
        perform 1 from public.observacao_listar_por_escopo(v_org_self, v_self_profile, 'SELF', null, now());
      exception when others then
        v_falhas := v_falhas || format('E3: listagem SELF negada (sqlstate=%s msg=%s)', sqlstate, sqlerrm);
      end;

      -- Ids das observacoes da fixture (o 42 os criou).
      select o.id, o.cycle_id into v_obs_com, v_ciclo_self
        from public.evaluation_observations o
       where o.collaborator_id = v_self_colab and o.comunicado = true and o.excluida = false
       order by o.id limit 1;
      select o.id into v_obs_nao
        from public.evaluation_observations o
       where o.collaborator_id = v_self_colab and o.comunicado = false and o.excluida = false
       order by o.id limit 1;
      select o.id into v_obs_exc
        from public.evaluation_observations o
       where o.collaborator_id = v_self_colab and o.excluida = true
       order by o.id limit 1;
      select o.id into v_obs_ter
        from public.evaluation_observations o
       where o.collaborator_id = v_terceiro_colab and o.comunicado = true and o.excluida = false
       order by o.id limit 1;

      -- (E4) SELF le a PROPRIA comunicada (prova POSITIVA, sem SKIP).
      if v_obs_com is null then
        v_falhas := v_falhas || text 'E4: fixture SELF sem observacao COMUNICADA do proprio avaliado';
      else
        begin
          perform 1 from public.observacao_obter(v_obs_com, v_org_self, v_self_profile);
        exception when others then
          v_falhas := v_falhas || format('E4: SELF nao leu a PROPRIA comunicada (sqlstate=%s msg=%s)', sqlstate, sqlerrm);
        end;
      end if;

      -- (E5) SELF NAO le a propria NAO COMUNICADA (D7/D9).
      if v_obs_nao is null then
        v_falhas := v_falhas || text 'E5: fixture SELF sem observacao NAO COMUNICADA do proprio avaliado';
      else
        v_mutou := false;
        begin
          perform 1 from public.observacao_obter(v_obs_nao, v_org_self, v_self_profile);
          v_mutou := true;
        exception when others then null;
        end;
        if v_mutou then
          v_falhas := v_falhas || text 'E5: SELF leu a propria NAO COMUNICADA (deveria negar)';
        end if;
      end if;

      -- (E5b) SELF NAO le a propria EXCLUIDA (D8/D9).
      if v_obs_exc is null then
        v_falhas := v_falhas || text 'E5b: fixture SELF sem observacao EXCLUIDA do proprio avaliado';
      else
        v_mutou := false;
        begin
          perform 1 from public.observacao_obter(v_obs_exc, v_org_self, v_self_profile);
          v_mutou := true;
        exception when others then null;
        end;
        if v_mutou then
          v_falhas := v_falhas || text 'E5b: SELF leu a propria EXCLUIDA (deveria negar)';
        end if;
      end if;

      -- (E5c) SELF NAO le observacao de TERCEIRO (sem oraculo de existencia).
      if v_obs_ter is null then
        v_falhas := v_falhas || text 'E5c: fixture SELF sem observacao COMUNICADA do TERCEIRO';
      else
        v_mutou := false;
        begin
          perform 1 from public.observacao_obter(v_obs_ter, v_org_self, v_self_profile);
          v_mutou := true;
        exception when others then null;
        end;
        if v_mutou then
          v_falhas := v_falhas || text 'E5c: SELF leu observacao de TERCEIRO (deveria negar)';
        end if;
      end if;

      -- (E6) ZERO mutacoes SELF: as 5 mutacoes sao negadas PELO GATE. A mensagem e'
      --      exigida (P0001 + F5_11_) para nao aceitar como "negado" um erro de
      --      assinatura/ambiente (falso positivo).
      if v_ciclo_self is null then
        v_falhas := v_falhas || text 'E6: fixture SELF sem ciclo soberano para a tentativa de criacao';
      else
        v_mutou := false;
        begin
          perform public.observacao_criar(v_org_self, v_ciclo_self, v_self_colab, 'NEUTRA',
            'tentativa de mutacao SELF (deve ser negada)', v_self_profile, gen_random_uuid());
          v_mutou := true;
        exception when others then
          if sqlstate <> 'P0001' or position('F5_11_' in sqlerrm) = 0 then
            v_falhas := v_falhas || format('E6/criar: negado por motivo inesperado (sqlstate=%s msg=%s)', sqlstate, sqlerrm);
          end if;
        end;
        if v_mutou then v_falhas := v_falhas || text 'E6/criar: mutacao SELF foi ACEITA'; end if;

        v_mutou := false;
        begin
          perform public.observacao_editar(v_obs_com, v_org_self, 'NEUTRA',
            'tentativa de edicao SELF (deve ser negada)', false, 0, v_self_profile, gen_random_uuid());
          v_mutou := true;
        exception when others then
          if sqlstate <> 'P0001' or position('F5_11_' in sqlerrm) = 0 then
            v_falhas := v_falhas || format('E6/editar: negado por motivo inesperado (sqlstate=%s msg=%s)', sqlstate, sqlerrm);
          end if;
        end;
        if v_mutou then v_falhas := v_falhas || text 'E6/editar: mutacao SELF foi ACEITA'; end if;

        v_mutou := false;
        begin
          perform public.observacao_definir_comunicado(v_obs_com, v_org_self, false, 0, v_self_profile, gen_random_uuid());
          v_mutou := true;
        exception when others then
          if sqlstate <> 'P0001' or position('F5_11_' in sqlerrm) = 0 then
            v_falhas := v_falhas || format('E6/comunicar: negado por motivo inesperado (sqlstate=%s msg=%s)', sqlstate, sqlerrm);
          end if;
        end;
        if v_mutou then v_falhas := v_falhas || text 'E6/comunicar: mutacao SELF foi ACEITA'; end if;

        v_mutou := false;
        begin
          perform public.observacao_excluir(v_obs_com, v_org_self, 'motivo ficticio SELF', 0, v_self_profile, gen_random_uuid());
          v_mutou := true;
        exception when others then
          if sqlstate <> 'P0001' or position('F5_11_' in sqlerrm) = 0 then
            v_falhas := v_falhas || format('E6/excluir: negado por motivo inesperado (sqlstate=%s msg=%s)', sqlstate, sqlerrm);
          end if;
        end;
        if v_mutou then v_falhas := v_falhas || text 'E6/excluir: mutacao SELF foi ACEITA'; end if;

        v_mutou := false;
        begin
          perform public.observacao_revogar(v_obs_exc, v_org_self, 'motivo ficticio SELF', 0, v_self_profile, gen_random_uuid());
          v_mutou := true;
        exception when others then
          if sqlstate <> 'P0001' or position('F5_11_' in sqlerrm) = 0 then
            v_falhas := v_falhas || format('E6/revogar: negado por motivo inesperado (sqlstate=%s msg=%s)', sqlstate, sqlerrm);
          end if;
        end;
        if v_mutou then v_falhas := v_falhas || text 'E6/revogar: mutacao SELF foi ACEITA'; end if;
      end if;
    end if;
  end;

  -- ==========================================================================
  -- F) CROSS-TENANT / IDOR: organizacao alheia nao produz leitura
  -- ==========================================================================
  if v_membership is not null then
    v_ok := true;
    begin
      perform 1 from public.observacao_listar_por_escopo(
        '00000000-0000-4000-8000-000000000000'::uuid, v_profile, 'SELF', null, now());
    exception when others then v_ok := false;
    end;
    if v_ok then
      v_falhas := v_falhas || text 'F1: listagem SELF com organizacao alheia foi aceita (cross-tenant)';
    end if;
  end if;

  -- ==========================================================================
  -- H0) AUDITORIA DO CAMINHO AUTOMATICO + coerencia origin x created_by
  -- ==========================================================================
  if v_org is not null and v_membership is not null and v_role is not null then
    -- (H0.1) o provisionamento automatico registrou system_grant com ator NULL.
    select count(*) into v_n
      from public.privilege_mutation_audit a
     where a.organization_id = v_org
       and a.membership_id = v_membership
       and a.access_role_id = v_role
       and a.action = 'system_grant'
       and a.actor_user_profile_id is null;
    if v_n < 1 then
      v_falhas := v_falhas || text 'H0.1: o provisionamento automatico NAO registrou system_grant com ator NULL na trilha D18';
    end if;

    -- (H0.2) nenhuma linha HUMANA (grant/revoke) pode existir com ator NULL.
    select count(*) into v_n
      from public.privilege_mutation_audit a
     where a.action in ('grant','revoke') and a.actor_user_profile_id is null;
    if v_n <> 0 then
      v_falhas := v_falhas || format('H0.2: % linha(s) humanas de trilha com ator NULL (a discriminante nao esta valendo)', v_n);
    end if;

    -- (H0.3) origin='human' com created_by NULL deve ser REJEITADO.
    v_ok := true;
    begin
      update public.membership_access_role_assignments
         set origin = 'human', created_by = null
       where organization_id = v_org and membership_id = v_membership and access_role_id = v_role;
    exception when others then v_ok := false;
    end;
    if v_ok then
      v_falhas := v_falhas || text 'H0.3: assignment com origin=human e created_by NULL foi aceita (deveria violar a constraint de coerencia)';
    end if;

    -- (H0.4) origin='system' com created_by PREENCHIDO deve ser REJEITADO.
    v_ok := true;
    begin
      update public.membership_access_role_assignments
         set origin = 'system', created_by = v_profile
       where organization_id = v_org and membership_id = v_membership and access_role_id = v_role;
    exception when others then v_ok := false;
    end;
    if v_ok then
      v_falhas := v_falhas || text 'H0.4: assignment com origin=system e created_by preenchido foi aceita (o beneficiario NAO e autor)';
    end if;
  end if;

  -- ==========================================================================
  -- I) P5.3 — LIFECYCLE por `user_profiles.status` (propagacao MATERIALIZADA)
  -- ==========================================================================
  -- A elegibilidade tem TRES fatores (membership + perfil + vinculo); a P5.1
  -- criou triggers apenas para membership e vinculo. Aqui provamos que a
  -- mudanca ISOLADA de `user_profiles.status` propaga para CADA membership:
  -- (a) active->disabled REVOGA; (b) replay NAO gera evento/linha; (c) a
  -- reativacao reusa a MESMA assignment; (d) evento SO' em transicao real, com
  -- ator NULL; (e) multiplas memberships reavaliadas individualmente; (f)
  -- inelegivel segue inelegivel apos reativar o perfil; (g) resolvedor
  -- fail-closed; (h) ZERO impacto em humanos/admin/gestor/metas_*.
  if v_profile is not null and v_membership is not null and v_role is not null then
    -- ESCOPO DA PROVA: o AVALIADO PURO da fixture dedicada (prefixo f5c1) — o
    -- MESMO ator das provas E. As variaveis externas apontam para a fixture de
    -- GESTAO das fases anteriores (outro perfil, sem segunda membership), e usar
    -- aquele ator mediria outro papel. A partir daqui, TODA a prova do bloco I
    -- (e a higiene correspondente) opera sobre este perfil e suas memberships.
    v_profile    := 'f5c1c000-0000-0000-0000-0000000000a1';
    v_membership := 'f5c1d000-0000-0000-0000-0000000000a1';
    select m.organization_id into v_org
      from public.user_organization_memberships m
     where m.id = v_membership;

    -- Descoberta DETERMINISTICA da segunda membership do MESMO perfil (fixture
    -- f5c1 do cenario 42): nao e' truncamento de consulta de negocio.
    select m.id, m.organization_id into v_mem2, v_org2
      from public.user_organization_memberships m
     where m.user_profile_id = v_profile and m.id <> v_membership
     order by m.id
     limit 1;
    if v_mem2 is null then
      v_falhas := v_falhas || text 'I0: fixture sem segunda membership do MESMO perfil (caso (e) nao e'' testavel)';
    end if;

    select a.id into v_assign_id
      from public.membership_access_role_assignments a
     where a.membership_id = v_membership and a.access_role_id = v_role;
    if v_mem2 is not null then
      select a.id into v_assign_id2
        from public.membership_access_role_assignments a
       where a.membership_id = v_mem2 and a.access_role_id = v_role;
    end if;

    -- (h) fotografia ANTES: humano (grant/revoke) e roles nao-avaliado.
    select count(*) into v_humanos
      from public.privilege_mutation_audit a where a.action in ('grant','revoke');
    select count(*) into v_gestor_antes
      from public.membership_access_role_assignments a
      join public.access_roles r on r.id = a.access_role_id
     where r.is_system = true
       and r.name in ('observacoes_gestor','metas_dono','metas_aprovador','admin');

    -- Pre-condicao: as duas memberships estao ativas (provisionadas).
    select count(*) into v_n
      from public.membership_access_role_assignments a
     where a.access_role_id = v_role and a.status = 'active'
       and a.membership_id in (v_membership, coalesce(v_mem2, v_membership));
    if v_n <> (case when v_mem2 is null then 1 else 2 end) then
      v_falhas := v_falhas || format('I1: pre-condicao falhou — esperava % assignment(s) ativa(s) do perfil SELF (tem %s)', (case when v_mem2 is null then 1 else 2 end), v_n);
    end if;

    -- Fotografia da trilha ANTES da transicao provocada por ESTE teste: as
    -- transicoes dos blocos de lifecycle anteriores JA' deixaram eventos de
    -- `system_revoke` para o mesmo role/membership, logo a assercao e' por DELTA.
    select count(*) into v_rev_antes
      from public.privilege_mutation_audit a
     where a.access_role_id = v_role and a.action = 'system_revoke'
       and a.membership_id in (v_membership, coalesce(v_mem2, v_membership))
       and a.actor_user_profile_id is null;

    -- (a) active -> disabled: REVOGA em TODAS as memberships do perfil.
    update public.user_profiles set status = 'disabled' where id = v_profile;

    select count(*) into v_rev_depois
      from public.privilege_mutation_audit a
     where a.access_role_id = v_role and a.action = 'system_revoke'
       and a.membership_id in (v_membership, coalesce(v_mem2, v_membership))
       and a.actor_user_profile_id is null;

    select count(*) into v_n
      from public.membership_access_role_assignments a
     where a.access_role_id = v_role and a.status = 'active'
       and a.membership_id in (v_membership, coalesce(v_mem2, v_membership));
    if v_n <> 0 then
      v_falhas := v_falhas || format('I2/a: perfil disabled manteve %s assignment(s) do perfil SELF ativa(s) (deveria revogar todas)', v_n);
    end if;

    -- (g) inelegivel => o resolvedor NAO entrega observation.read (fail-closed).
    if exists (
      select 1 from public.resolver_capabilities_efetivas(v_profile, v_org) c
       where c.capability_code = 'observation.read'
    ) then
      v_falhas := v_falhas || text 'I3/g: resolvedor entregou observation.read com perfil disabled (fail-closed violado)';
    end if;

    -- (d) a transicao REAL registrou system_revoke com ator NULL: EXATAMENTE um
    --     por membership AFETADA POR ESTE TESTE (delta), nunca eventos falsos.
    if v_rev_depois - v_rev_antes <> (case when v_mem2 is null then 1 else 2 end) then
      v_falhas := v_falhas || format('I4/d: a transicao de perfil deveria gerar EXATAMENTE %s system_revoke (uma por membership) com ator NULL; delta observado=%s',
        (case when v_mem2 is null then 1 else 2 end), v_rev_depois - v_rev_antes);
    end if;

    -- (b) REPLAY da inativacao: nenhum evento/linha nova.
    select count(*) into v_antes2
      from public.privilege_mutation_audit a
     where a.access_role_id = v_role
       and a.membership_id in (v_membership, coalesce(v_mem2, v_membership));
    select count(*) into v_gestor_dep
      from public.membership_access_role_assignments a where a.access_role_id = v_role;

    update public.user_profiles set status = 'disabled' where id = v_profile;

    select count(*) into v_depois2
      from public.privilege_mutation_audit a
     where a.access_role_id = v_role
       and a.membership_id in (v_membership, coalesce(v_mem2, v_membership));
    if v_depois2 <> v_antes2 then
      v_falhas := v_falhas || format('I5/b: replay da inativacao gerou evento FALSO (%s -> %s)', v_antes2, v_depois2);
    end if;
    select count(*) into v_n
      from public.membership_access_role_assignments a where a.access_role_id = v_role;
    if v_n <> v_gestor_dep then
      v_falhas := v_falhas || format('I5/b: replay da inativacao criou/removeu assignment (%s -> %s)', v_gestor_dep, v_n);
    end if;

    -- (f) inelegibilidade por VINCULO: com o vinculo disabled, reativar o
    --     perfil NAO pode reprovisionar aquela membership.
    if v_mem2 is not null then
      update public.membership_collaborator_links set status = 'disabled' where membership_id = v_mem2;
      update public.user_profiles set status = 'active' where id = v_profile;
      select count(*) into v_n
        from public.membership_access_role_assignments a
       where a.membership_id = v_mem2 and a.access_role_id = v_role and a.status = 'active';
      if v_n <> 0 then
        v_falhas := v_falhas || text 'I6/f: membership com vinculo disabled foi provisionada ao reativar o perfil (elegibilidade de vinculo ignorada)';
      end if;
      -- Volta o vinculo: a MESMA assignment deve ser reativada (nunca nova linha).
      update public.membership_collaborator_links set status = 'active' where membership_id = v_mem2;
    else
      update public.user_profiles set status = 'active' where id = v_profile;
    end if;

    -- (c) reativacao: a MESMA assignment (mesmo id) volta a 'active', sem
    --     duplicar linha.
    select count(*) into v_n
      from public.membership_access_role_assignments a
     where a.membership_id = v_membership and a.access_role_id = v_role and a.status = 'active';
    if v_n <> 1 then
      v_falhas := v_falhas || format('I7/c: reativacao nao devolveu a assignment ativa da membership principal (ativas=%s)', v_n);
    end if;
    if v_assign_id is not null and not exists (
      select 1 from public.membership_access_role_assignments a
       where a.id = v_assign_id and a.status = 'active'
    ) then
      v_falhas := v_falhas || text 'I7/c: a reativacao NAO reusou a MESMA assignment (id original nao esta ativo)';
    end if;
    if v_mem2 is not null then
      if v_assign_id2 is not null and not exists (
        select 1 from public.membership_access_role_assignments a
         where a.id = v_assign_id2 and a.status = 'active'
      ) then
        v_falhas := v_falhas || text 'I7/c: a segunda membership nao reusou a MESMA assignment apos reativacao';
      end if;
      select count(*) into v_n
        from public.membership_access_role_assignments a
       where a.membership_id = v_mem2 and a.access_role_id = v_role;
      if v_n <> 1 then
        v_falhas := v_falhas || format('I7/c: segunda membership deveria ter EXATAMENTE 1 assignment do perfil SELF (tem %s)', v_n);
      end if;
    end if;

    -- (d) a reativacao real registrou system_grant com ator NULL.
    select count(*) into v_n
      from public.privilege_mutation_audit a
     where a.access_role_id = v_role and a.action = 'system_grant'
       and a.membership_id = v_membership and a.actor_user_profile_id is null;
    if v_n < 1 then
      v_falhas := v_falhas || text 'I8/d: reativacao nao registrou system_grant com ator NULL';
    end if;

    -- (g) elegivel novamente => o resolvedor volta a entregar observation.read.
    if not exists (
      select 1 from public.resolver_capabilities_efetivas(v_profile, v_org) c
       where c.capability_code = 'observation.read'
    ) then
      v_falhas := v_falhas || text 'I9/g: resolvedor NAO entregou observation.read com perfil ativo (fail-closed invertido)';
    end if;

    -- (h) ZERO impacto em humanos, admin, gestor e metas.
    select count(*) into v_humanos_dep
      from public.privilege_mutation_audit a where a.action in ('grant','revoke');
    if v_humanos_dep <> v_humanos then
      v_falhas := v_falhas || format('I10/h: a propagacao tocou a trilha HUMANA (%s -> %s)', v_humanos, v_humanos_dep);
    end if;
    select count(*) into v_n
      from public.membership_access_role_assignments a
      join public.access_roles r on r.id = a.access_role_id
     where r.is_system = true
       and r.name in ('observacoes_gestor','metas_dono','metas_aprovador','admin');
    if v_n <> v_gestor_antes then
      v_falhas := v_falhas || format('I11/h: a propagacao tocou assignments de outros perfis de sistema (%s -> %s)', v_gestor_antes, v_n);
    end if;
  end if;

  -- ==========================================================================
  -- J) F5-11 P5.4 — role automatica EXCLUSIVA (finding 1) + corrida (finding 2)
  -- ==========================================================================
  if v_role is not null and v_membership is not null then
    declare
      v_j_msg    text;
      v_j_n      int;
      v_j_hum    int;
      v_j_assign int;
      v_j_ev     int;
      v_mem_col  uuid := 'f5c1d000-0000-0000-0000-0000000000a9';
      v_prof_col uuid := 'f5c1c000-0000-0000-0000-0000000000a9';
    begin
      -- (a) GRANT humano da role automatica: bloqueado, fail-closed, sem efeito.
      v_j_hum := (select count(*) from public.privilege_mutation_audit a where a.action in ('grant','revoke'));
      v_j_assign := (select count(*) from public.membership_access_role_assignments a where a.access_role_id = v_role);
      begin
        perform public.conceder_acesso_role_rpc(v_membership, v_role, v_profile);
        v_falhas := v_falhas || text 'J1/a: conceder_acesso_role_rpc ACEITOU a role automatica (deveria bloquear)';
      exception when others then
        v_j_msg := sqlerrm;
        if position('AUTOMATICA' in v_j_msg) = 0 then
          v_falhas := v_falhas || format('J1/a: bloqueio com mensagem inesperada (%s)', v_j_msg);
        end if;
      end;

      -- (a) REVOKE humano da role automatica: bloqueado, fail-closed.
      begin
        perform public.revogar_acesso_role_rpc(v_membership, v_role, v_profile);
        v_falhas := v_falhas || text 'J2/a: revogar_acesso_role_rpc ACEITOU a role automatica (deveria bloquear)';
      exception when others then
        v_j_msg := sqlerrm;
        if position('AUTOMATICA' in v_j_msg) = 0 then
          v_falhas := v_falhas || format('J2/a: bloqueio com mensagem inesperada (%s)', v_j_msg);
        end if;
      end;

      -- (a) bloqueio NAO produziu efeito algum.
      if (select count(*) from public.membership_access_role_assignments a where a.access_role_id = v_role) <> v_j_assign then
        v_falhas := v_falhas || text 'J1/J2/a: o bloqueio alterou assignments';
      end if;
      if (select count(*) from public.privilege_mutation_audit a where a.action in ('grant','revoke')) <> v_j_hum then
        v_falhas := v_falhas || text 'J1/J2/a: o bloqueio gravou trilha humana';
      end if;
      if not exists (
        select 1 from public.membership_access_role_assignments a
         where a.membership_id = v_membership and a.access_role_id = v_role
           and a.status = 'active' and a.origin = 'system'
      ) then
        v_falhas := v_falhas || text 'J2/a: a assignment automatica foi afetada pelo bloqueio';
      end if;

      -- (c) COLISAO: membership inelegivel (sem vinculo) + assignment HUMANA
      -- pre-existente => a automacao falha e NAO altera o historico humano.
      -- A FK `fk_user_profiles_auth_users` exige a identidade em `auth.users`
      -- ANTES do profile — mesmo padrao do cenario 42 (6.3), idempotente.
      if not exists (select 1 from auth.users u where u.id = v_prof_col) then
        insert into auth.users
          (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
           raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
        values
          (v_prof_col, '00000000-0000-0000-0000-000000000000', 'authenticated',
           'authenticated', 'colisao.p54.f5-11-p5-1@example.invalid', 'x', now(),
           '{}'::jsonb, '{}'::jsonb, now(), now());
      end if;
      insert into public.user_profiles (id, status)
      values (v_prof_col, 'active')
      on conflict (id) do nothing;
      insert into public.user_organization_memberships (id, user_profile_id, organization_id, status)
      values (v_mem_col, v_prof_col, v_org, 'active')
      on conflict (id) do nothing;
      insert into public.membership_access_role_assignments
        (membership_id, organization_id, access_role_id, status, origin, created_by)
      values (v_mem_col, v_org, v_role, 'active', 'human', v_profile)
      on conflict (membership_id, access_role_id) do nothing;

      if not exists (
        select 1 from public.membership_access_role_assignments a
         where a.membership_id = v_mem_col and a.access_role_id = v_role and a.origin = 'human'
      ) then
        v_falhas := v_falhas || text 'J3/c: fixture de colisao humana nao pode ser criada (premissa do teste)';
      else
        v_j_ev := (select count(*) from public.privilege_mutation_audit a
                    where a.membership_id = v_mem_col and a.access_role_id = v_role);
        begin
          perform public.f5_11_p5_1_provisionar_observacoes_avaliado(v_mem_col);
          v_falhas := v_falhas || text 'J3/c: a automacao NAO falhou diante de assignment HUMANA (colisao)';
        exception when others then
          v_j_msg := sqlerrm;
          if position('colisao' in lower(v_j_msg)) = 0 then
            v_falhas := v_falhas || format('J3/c: falha de colisao com mensagem inesperada (%s)', v_j_msg);
          end if;
        end;
        if (select count(*) from public.privilege_mutation_audit a
              where a.membership_id = v_mem_col and a.access_role_id = v_role) <> v_j_ev then
          v_falhas := v_falhas || text 'J3/c: a colisao gerou evento na trilha';
        end if;
        select count(*) into v_j_n from public.membership_access_role_assignments a
         where a.membership_id = v_mem_col and a.access_role_id = v_role
           and a.origin = 'human' and a.created_by is not null and a.status = 'active';
        if v_j_n <> 1 then
          v_falhas := v_falhas || format('J3/c: historico HUMANO alterado pela automacao (%s linhas humanas intactas)', v_j_n);
        end if;
      end if;

      -- (b) a automacao so altera origem system; chamadas repetidas em estado ja
      -- provisionado sao idempotentes e NAO geram evento (equivalente determini-
      -- stico do "perdedor da corrida nao emite evento").
      v_j_ev := (select count(*) from public.privilege_mutation_audit a
                  where a.membership_id = v_membership and a.access_role_id = v_role);
      perform public.f5_11_p5_1_provisionar_observacoes_avaliado(v_membership);
      perform public.f5_11_p5_1_provisionar_observacoes_avaliado(v_membership);
      if (select count(*) from public.privilege_mutation_audit a
            where a.membership_id = v_membership and a.access_role_id = v_role) <> v_j_ev then
        v_falhas := v_falhas || text 'J5/d: chamadas repetidas em estado ja provisionado geraram evento (corrida/idempotencia)';
      end if;
      select count(*) into v_j_n from public.membership_access_role_assignments a
       where a.membership_id = v_membership and a.access_role_id = v_role;
      if v_j_n <> 1 then
        v_falhas := v_falhas || format('J5/d: deveria existir EXATAMENTE 1 assignment do perfil SELF (tem %s)', v_j_n);
      end if;
      if not exists (
        select 1 from public.membership_access_role_assignments a
         where a.membership_id = v_membership and a.access_role_id = v_role
           and a.origin = 'system' and a.created_by is null
      ) then
        v_falhas := v_falhas || text 'J5/d: a assignment automatica perdeu origem system/created_by NULL';
      end if;

      -- Higiene da fixture de colisao (ordem que respeita as FKs).
      delete from public.privilege_mutation_audit
       where membership_id = v_mem_col and access_role_id = v_role;
      delete from public.membership_access_role_assignments
       where membership_id = v_mem_col and access_role_id = v_role;
      delete from public.user_organization_memberships where id = v_mem_col;
      delete from public.user_profiles where id = v_prof_col;
      -- Higiene COMPLETA: remove tambem a identidade criada para a prova de
      -- colisao (depois do profile, respeitando a FK) — sem residuo.
      delete from auth.users where id = v_prof_col;
    end;
  end if;

  -- ==========================================================================
  -- H) RESULTADO + HIGIENE
  -- ==========================================================================
  if array_length(v_falhas, 1) > 0 then
    raise exception '[FAIL] F5-11 P5.1: % verificacao(oes) falharam: %',
      array_length(v_falhas, 1), array_to_string(v_falhas, ' | ');
  end if;

  -- Higiene: remove as linhas de trilha criadas por ESTE validador (o DELETE e'
  -- do proprietario; o runtime de aplicacao continua sem DELETE — D18).
  -- Higiene da trilha AUTOMATICA criada durante ESTE validador (blocos C e I):
  -- escopo por ROLE + janela temporal + ator NULL (eventos `system_*`), cobrindo
  -- TODAS as memberships tocadas pelas transicoes do proprio validador — antes
  -- o escopo era uma unica membership, o que deixaria residuo dos outros blocos.
  if v_role is not null then
    delete from public.privilege_mutation_audit
     where access_role_id = v_role
       and action in ('system_grant','system_revoke')
       and actor_user_profile_id is null
       and created_at >= now() - interval '5 minutes';
  end if;

  -- Higiene da P5.3: o perfil e o vinculo JA' foram restaurados para 'active'
  -- nas provas do bloco I; aqui removemos a fixture EXTRA (segunda membership em
  -- outra organizacao, criada pelo cenario 42) e a trilha que este validador
  -- gerou para ela — o pipeline seguinte (F5-06/F5-07) nao ve residuo.
  if v_mem2 is not null then
    delete from public.privilege_mutation_audit
     where membership_id = v_mem2 and access_role_id = v_role
       and created_at >= now() - interval '5 minutes';
    delete from public.membership_access_role_assignments where membership_id = v_mem2;
    delete from public.membership_collaborator_links where membership_id = v_mem2;
    delete from public.user_organization_memberships where id = v_mem2;
  end if;
  if v_org2 is not null then
    delete from public.collaborators c
     where c.organization_id = v_org2
       and not exists (select 1 from public.membership_collaborator_links l where l.collaborator_id = c.id)
       and not exists (select 1 from public.evaluation_observations o where o.collaborator_id = c.id);
    delete from public.organizations o
     where o.id = v_org2
       and not exists (select 1 from public.user_organization_memberships m where m.organization_id = o.id);
  end if;

  raise notice '[PASS] F5-11 P5.1: bundle do 5o perfil (1 capability, zero scope), provisionamento automatico (origin=system), lifecycle/backfill idempotentes, D18 discriminado e append-only, SELF le/nao muta/cross-tenant fail-closed, observacoes_gestor e admin intactos';
end $validar$;
