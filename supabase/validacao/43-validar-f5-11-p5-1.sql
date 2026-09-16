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
  -- H) RESULTADO + HIGIENE
  -- ==========================================================================
  if array_length(v_falhas, 1) > 0 then
    raise exception '[FAIL] F5-11 P5.1: % verificacao(oes) falharam: %',
      array_length(v_falhas, 1), array_to_string(v_falhas, ' | ');
  end if;

  -- Higiene: remove as linhas de trilha criadas por ESTE validador (o DELETE e'
  -- do proprietario; o runtime de aplicacao continua sem DELETE — D18).
  if v_org is not null and v_membership is not null then
    delete from public.privilege_mutation_audit
     where organization_id = v_org and membership_id = v_membership
       and access_role_id = v_role and action = 'system_grant'
       and actor_user_profile_id is null
       and created_at >= now() - interval '5 minutes';
  end if;

  raise notice '[PASS] F5-11 P5.1: bundle do 5o perfil (1 capability, zero scope), provisionamento automatico (origin=system), lifecycle/backfill idempotentes, D18 discriminado e append-only, SELF le/nao muta/cross-tenant fail-closed, observacoes_gestor e admin intactos';
end $validar$;
