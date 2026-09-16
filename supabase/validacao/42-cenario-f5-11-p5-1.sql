-- ============================================================================
-- F5-11 P5.1 (Issue #252): CENARIO da fixture do SELF/read (LOTE SQL)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de: 40-cenario-f5-11-p3.sql (fixture `f5b3` da P3).
-- Este cenario NAO cria organizacao/perfil/membership do zero: ele REUSA a
-- fixture soberana da P3 (prefixo `f5b3`) e exerce o LIFECYCLE do
-- provisionamento automatico (T) sobre memberships reais:
--   1) localiza a organizacao da fixture P3 (prefixo f5b3) e uma membership com
--      vinculo ATIVO (= elegivel) e uma membership SEM vinculo (= inelegivel);
--   2) desativa o vinculo da elegivel  => o trigger deve REVOGAR o perfil;
--   3) reativa o vinculo              => o trigger deve REATIVAR NO LUGAR;
--   4) reexecuta a funcao de provisionamento sobre a elegivel (REPLAY) para a
--      prova de idempotencia/ausencia de evento falso no validador 43;
--   5) emite os identificadores como NOTICE (o validador 43 os redescobre por
--      consulta, sem depender de variavel de sessao).
-- O cenario NAO concede nada manualmente: o provisionamento e' 100% automatico.
-- ============================================================================

\set ON_ERROR_STOP on

do $cenario$
declare
  v_org        uuid;
  v_com_vinculo uuid;
  v_sem_vinculo uuid;
  v_status_ini text;
  v_role       uuid;
begin
  -- membership ELEGIVEL: membership ATIVA + perfil ATIVO + vinculo ATIVO.
  -- A ORGANIZACAO e' DERIVADA da propria membership elegivel (e nao o contrario):
  -- o cenario 40 da P3 registra uma organizacao-espelho (prefixo `f5b3`) apenas
  -- para o guard insert-once, enquanto a ESTRUTURA VIVA (memberships/vinculos)
  -- vive no tenant da P2 (ver 40-cenario-f5-11-p3.sql:61-63). Buscar "a org
  -- primeiro" e exigir vinculo ativo nela produzia FAIL falso (:103).
  select m.organization_id, m.id into v_org, v_com_vinculo
    from public.user_organization_memberships m
    join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
    join public.membership_collaborator_links l
      on l.membership_id = m.id and l.status = 'active'
   where m.status = 'active'
   order by m.id limit 1;
  if v_com_vinculo is null then
    raise exception '[FAIL] cenario P5.1: nenhuma membership elegivel (membership ativa + perfil ativo + vinculo ativo) no banco';
  end if;

  select id into v_role from public.access_roles
   where name = 'observacoes_avaliado' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    raise exception '[FAIL] cenario P5.1: perfil observacoes_avaliado ausente — migration da P5.1 nao aplicada';
  end if;

  -- membership INELEGIVEL por ausencia de vinculo (membership sem vinculo NAO
  -- recebe o perfil — regra aprovada).
  select m.id into v_sem_vinculo
    from public.user_organization_memberships m
   where m.organization_id = v_org and m.status = 'active'
     and not exists (select 1 from public.membership_collaborator_links l where l.membership_id = m.id)
   order by m.id limit 1;

  -- (1) elegivel ja' provisionada pelo backfill da migration (assignment ATIVA).
  if not exists (
    select 1 from public.membership_access_role_assignments a
     where a.membership_id = v_com_vinculo and a.access_role_id = v_role and a.status = 'active'
  ) then
    raise exception '[FAIL] cenario P5.1: backfill nao provisionou a membership elegivel';
  end if;

  -- (2) INATIVACAO do vinculo => revogacao automatica (por status, nunca DELETE).
  select status into v_status_ini from public.membership_collaborator_links
   where membership_id = v_com_vinculo;
  update public.membership_collaborator_links
     set status = 'disabled', updated_at = now(), version = version + 1
   where membership_id = v_com_vinculo;

  if not exists (
    select 1 from public.membership_access_role_assignments a
     where a.membership_id = v_com_vinculo and a.access_role_id = v_role and a.status = 'revoked'
  ) then
    raise exception '[FAIL] cenario P5.1: inativacao do vinculo nao revogou o perfil';
  end if;

  -- (3) REATIVACAO do vinculo => reativacao NO LUGAR (mesma assignment).
  update public.membership_collaborator_links
     set status = v_status_ini, updated_at = now(), version = version + 1
   where membership_id = v_com_vinculo;

  if not exists (
    select 1 from public.membership_access_role_assignments a
     where a.membership_id = v_com_vinculo and a.access_role_id = v_role and a.status = 'active'
  ) then
    raise exception '[FAIL] cenario P5.1: reativacao do vinculo nao reprovisionou o perfil';
  end if;

  -- (4) REPLAY explicito da funcao (idempotencia / ausencia de evento falso).
  if public.f5_11_p5_1_provisionar_observacoes_avaliado(v_com_vinculo) <> 'none' then
    raise exception '[FAIL] cenario P5.1: replay em estado correto gerou transicao (deveria ser none)';
  end if;

  raise notice '[PASS] cenario P5.1: fixture pronta (org=%, elegivel=%, sem_vinculo=%, role=%)',
    v_org, v_com_vinculo, coalesce(v_sem_vinculo::text, 'nenhuma'), v_role;
end $cenario$;

-- ============================================================================
-- 6) FIXTURE SELF DEDICADA (prefixo f5c1) — o "AVALIADO PURO".
--
-- Por que existe: as fixtures das fases anteriores nao foram desenhadas para
-- SELF (nao havia observacao comunicada do proprio avaliado e as identidades
-- estavam entrelacadas com papeis de gestao). Aqui criamos:
--   * AVALIADO PURO  -> user_profile f5c1c000-...-a1 / membership f5c1d000-...-a1
--                       / colaborador f5c1e000-...-c1  (SEM papel de gestao)
--   * TERCEIRO       -> colaborador f5c1e000-...-c2 (sem vinculo com o avaliado)
--   * observacoes do AVALIADO PURO: COMUNICADA, NAO COMUNICADA e EXCLUIDA
--   * observacao do TERCEIRO (que o avaliado NAO pode ler)
--
-- O provisionamento automatico e' provado aqui: o INSERT do vinculo dispara o
-- trigger da P5.1 e concede `observacoes_avaliado` sem nenhuma acao manual.
-- Idempotente (o cenario pode ser reexecutado) e sem `begin/rollback`, no
-- padrao insert-once persistente do molde 40-cenario-f5-11-p3.sql.
-- ============================================================================
do $selffix$
declare
  -- ids RESERVADOS da fixture SELF (prefixo f5c1) — o 43 assere contra eles.
  v_self_profile    constant uuid := 'f5c1c000-0000-0000-0000-0000000000a1';
  v_self_membership constant uuid := 'f5c1d000-0000-0000-0000-0000000000a1';
  v_self_colab      constant uuid := 'f5c1e000-0000-0000-0000-0000000000c1';
  v_terceiro_colab  constant uuid := 'f5c1e000-0000-0000-0000-0000000000c2';
  v_org      uuid;
  v_ciclo    uuid;
  v_role     uuid;
  v_assign   int;
  v_obs_com  uuid;
  v_obs_nao  uuid;
  v_obs_exc  uuid;
  v_obs_ter  uuid;
begin
  -- (6.1) organizacao VIVA (o mesmo predicado de elegibilidade usado no bloco 5;
  --       a org-espelho do 40 nao tem estrutura viva).
  select m.organization_id into v_org
    from public.user_organization_memberships m
    join public.user_profiles up on up.id = m.user_profile_id and up.status = 'active'
    join public.membership_collaborator_links l on l.membership_id = m.id and l.status = 'active'
   where m.status = 'active'
   order by m.id limit 1;
  if v_org is null then
    raise exception '[FAIL] cenario P5.1 (SELF): nenhuma organizacao com membership elegivel';
  end if;

  -- (6.2) ciclo soberano da organizacao (cycle_id e NOT NULL — D2).
  select c.id into v_ciclo
    from public.evaluation_cycles c
   where c.organization_id = v_org
   order by c.id limit 1;
  if v_ciclo is null then
    raise exception '[FAIL] cenario P5.1 (SELF): organizacao % sem ciclo para ancorar as observacoes', v_org;
  end if;

  select r.id into v_role from public.access_roles r
   where r.name = 'observacoes_avaliado' and r.is_system = true;

  -- (6.3) identidade do AVALIADO PURO (auth.users + user_profiles + membership).
  if not exists (select 1 from auth.users u where u.id = v_self_profile) then
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
       raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values
      (v_self_profile, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', 'avaliado.puro.f5-11-p5-1@example.invalid', 'x', now(),
       '{}'::jsonb, '{}'::jsonb, now(), now());
  end if;

  if not exists (select 1 from public.user_profiles p where p.id = v_self_profile) then
    insert into public.user_profiles (id, status) values (v_self_profile, 'active');
  end if;

  if not exists (select 1 from public.user_organization_memberships m where m.id = v_self_membership) then
    insert into public.user_organization_memberships
      (id, user_profile_id, organization_id, status)
    values (v_self_membership, v_self_profile, v_org, 'active');
  end if;

  -- (6.4) colaboradores: o proprio AVALIADO PURO e o TERCEIRO (ambos ativos).
  if not exists (select 1 from public.collaborators c where c.id = v_self_colab) then
    insert into public.collaborators (id, organization_id) values (v_self_colab, v_org);
  end if;
  if not exists (
    select 1 from public.collaborator_status_periods s where s.collaborator_id = v_self_colab
  ) then
    insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
    values (v_self_colab, 'active', '2024-01-01T00:00:00Z');
  end if;

  if not exists (select 1 from public.collaborators c where c.id = v_terceiro_colab) then
    insert into public.collaborators (id, organization_id) values (v_terceiro_colab, v_org);
  end if;
  if not exists (
    select 1 from public.collaborator_status_periods s where s.collaborator_id = v_terceiro_colab
  ) then
    insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
    values (v_terceiro_colab, 'active', '2024-01-01T00:00:00Z');
  end if;

  -- (6.5) vinculo ATIVO do AVALIADO PURO — o INSERT e' a PROVA do provisionamento
  --       automatico (trigger da P5.1), sem nenhuma concessao manual.
  if not exists (
    select 1 from public.membership_collaborator_links l where l.membership_id = v_self_membership
  ) then
    insert into public.membership_collaborator_links
      (membership_id, organization_id, collaborator_id, status)
    values (v_self_membership, v_org, v_self_colab, 'active');
  end if;

  select count(*) into v_assign
    from public.membership_access_role_assignments a
   where a.membership_id = v_self_membership
     and a.access_role_id = v_role
     and a.status = 'active'
     and a.origin = 'system'
     and a.created_by is null;
  if v_assign <> 1 then
    raise exception '[FAIL] cenario P5.1 (SELF): avaliado puro sem assignment automatica ativa (achou %)', v_assign;
  end if;

  -- (6.6) observacoes do AVALIADO PURO: COMUNICADA, NAO COMUNICADA e EXCLUIDA.
  --       Os carimbos de comunicado/exclusao sao exigidos pelos CHECKs da P1 (D7).
  select o.id into v_obs_com
    from public.evaluation_observations o
   where o.collaborator_id = v_self_colab and o.comunicado = true and o.excluida = false
   order by o.id limit 1;
  if v_obs_com is null then
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       comunicado, comunicado_em, comunicado_por_user_profile_id, comunicado_por_membership_id,
       author_user_profile_id, author_membership_id, author_collaborator_id, version)
    values
      (v_org, v_self_colab, v_ciclo, 'POSITIVA',
       'observacao ficticia COMUNICADA do avaliado puro (fixture SELF da P5.1)',
       true, now(), v_self_profile, v_self_membership,
       v_self_profile, v_self_membership, v_self_colab, 0)
    returning id into v_obs_com;
  end if;

  select o.id into v_obs_nao
    from public.evaluation_observations o
   where o.collaborator_id = v_self_colab and o.comunicado = false and o.excluida = false
   order by o.id limit 1;
  if v_obs_nao is null then
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id, author_collaborator_id, version)
    values
      (v_org, v_self_colab, v_ciclo, 'NEUTRA',
       'observacao ficticia NAO COMUNICADA do avaliado puro (fixture SELF da P5.1)',
       v_self_profile, v_self_membership, v_self_colab, 0)
    returning id into v_obs_nao;
  end if;

  select o.id into v_obs_exc
    from public.evaluation_observations o
   where o.collaborator_id = v_self_colab and o.excluida = true
   order by o.id limit 1;
  if v_obs_exc is null then
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       excluida, excluida_em, excluida_por_user_profile_id, excluida_por_membership_id,
       motivo_exclusao,
       author_user_profile_id, author_membership_id, author_collaborator_id, version)
    values
      (v_org, v_self_colab, v_ciclo, 'NEGATIVA',
       'observacao ficticia EXCLUIDA do avaliado puro (fixture SELF da P5.1)',
       true, now(), v_self_profile, v_self_membership, 'motivo ficticio de exclusao (P5.1)',
       v_self_profile, v_self_membership, v_self_colab, 0)
    returning id into v_obs_exc;
  end if;

  -- (6.7) observacao do TERCEIRO (comunicada) — o avaliado NAO pode le-la.
  select o.id into v_obs_ter
    from public.evaluation_observations o
   where o.collaborator_id = v_terceiro_colab and o.comunicado = true and o.excluida = false
   order by o.id limit 1;
  if v_obs_ter is null then
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       comunicado, comunicado_em, comunicado_por_user_profile_id, comunicado_por_membership_id,
       author_user_profile_id, author_membership_id, author_collaborator_id, version)
    values
      (v_org, v_terceiro_colab, v_ciclo, 'NEUTRA',
       'observacao ficticia COMUNICADA do TERCEIRO (fixture SELF da P5.1)',
       true, now(), v_self_profile, v_self_membership,
       -- O AUTOR e' o AVALIADO PURO: `author_collaborator_id` tem de ser o
       -- colaborador do VINCULO da membership autora (invariante P1.1/D3-D4,
       -- trigger `f5_11_validar_coerencia_identidade`), e NAO o alvo. O alvo
       -- continua sendo `collaborator_id = v_terceiro_colab`.
       v_self_profile, v_self_membership, v_self_colab, 0)
    returning id into v_obs_ter;
  end if;

  raise notice '[PASS] cenario P5.1 (SELF): fixture dedicada pronta (org=%, avaliado=%, membro=%, colab=%, terceiro=%, comunicada=%, nao_comunicada=%, excluida=%, obs_terceiro=%, assignment_automatica=%)',
    v_org, v_self_profile, v_self_membership, v_self_colab, v_terceiro_colab,
    v_obs_com, v_obs_nao, v_obs_exc, v_obs_ter, v_assign;
end $selffix$;
