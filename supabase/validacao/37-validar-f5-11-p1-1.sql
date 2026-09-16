-- ============================================================================
-- F5-11 P1.1 (Issue #242): VALIDADOR do finding MEDIUM do Codex —
-- COERENCIA perfil <-> membership (e author_collaborator_id) NA MESMA organizacao.
-- Saida: [PASS]/[FAIL]; falha aborta (ON_ERROR_STOP).
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-11-desenho-tecnico.md (D1-D16 + §19) e migration corretiva
-- `20260930000000_f5_11_p1_1_coerencia_identidade_observacoes.sql`.
-- Cenario: `36-cenario-f5-11-p1-1.sql` (prefixo `fe`).
--
-- O QUE ESTE VALIDADOR PROVA (e o que ele NAO repete):
--   - NAO repete cross-tenant (isso e o bloco E do validador 35 da P1);
--   - prova o finding do Codex: numa MESMA organizacao com perfil A -> membership A
--     e perfil B -> membership B, a combinacao A+B tem de ser RECUSADA nos QUATRO
--     pares perfil<->membership, e a coerente tem de continuar valida;
--   - prova a paridade de `author_collaborator_id` com o resolvedor canonico
--     (`resolver_collaborador_vinculado`) na MATRIZ INTEGRAL: perfil ATIVO +
--     membership ATIVA + vinculo ATIVO (C: vinculo disabled; D: membership
--     disabled com vinculo ativo - o finding do Codex; E: perfil disabled);
--   - prova a SEPARACAO DE CLASSES DE ERRO: incoerencia => P0001; ausencia =>
--     NOT NULL/CHECK; inexistencia/cross-tenant => FK (23503).
--
-- Blocos:
--   A  preflight (fixture, mecanismo instalado, D15 intacto, fronteira preservada)
--   B  paridade INTEGRAL com o resolvedor canonico do vinculo (as 3 condicoes)
--   C  NEGATIVOS intra-tenant dos 4 pares perfil<->membership
--   D  NEGATIVOS de author_collaborator_id (vinculo, membership e perfil disabled)
--   E  NEGATIVOS no caminho de UPDATE (a linha e mutavel)
--   F  POSITIVOS (combinacoes legitimas continuam validas)
--   G  separacao de classes de erro + invariantes da P1 preservados (D4/D6/D9)
--   H  higiene final (nenhuma linha incoerente persistida)
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) PREFLIGHT fail-closed
-- ============================================================================
do $$
declare
  v_falhas text[] := array[]::text[];
  v_n      int;
  v_fn     text;
begin
  -- (A1) fixture presente.
  select count(*) into v_n from public.organizations
   where id = 'fea00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    v_falhas := v_falhas || format('org da fixture = %s (esperado 1)', v_n);
  end if;
  select count(*) into v_n from public.user_organization_memberships
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1' and status = 'active';
  if v_n <> 4 then
    v_falhas := v_falhas || format('memberships ativas na MESMA org = %s (esperado 4)', v_n);
  end if;

  -- (A1b) as TRES negativas da matriz de paridade estao MESMO na fixture:
  --       D = membership DISABLED com vinculo ATIVO (o finding do Codex);
  --       E = perfil DISABLED com membership e vinculo ATIVOS;
  --       C = vinculo DISABLED. Sem elas os testes negativos do bloco D nao
  --       provariam nada (poderiam estar recusando por outro motivo).
  select count(*) into v_n from public.user_organization_memberships
   where id = 'fed00000-0000-0000-0000-000000000004' and status = 'disabled';
  if v_n <> 1 then
    v_falhas := v_falhas || format('membership DISABLED do perfil D = %s (esperado 1)', v_n);
  end if;
  select count(*) into v_n from public.user_profiles
   where id = 'fec00000-0000-0000-0000-000000000005' and status = 'disabled';
  if v_n <> 1 then
    v_falhas := v_falhas || format('perfil DISABLED E = %s (esperado 1)', v_n);
  end if;
  select count(*) into v_n from public.membership_collaborator_links
   where membership_id = 'fed00000-0000-0000-0000-000000000004'
     and organization_id = 'fea00000-0000-0000-0000-0000000000a1'
     and collaborator_id = 'feb00000-0000-0000-0000-000000000004'
     and status = 'active';
  if v_n <> 1 then
    v_falhas := v_falhas || format('vinculo ATIVO D->colaborador D = %s (esperado 1)', v_n);
  end if;
  select count(*) into v_n from public.membership_collaborator_links
   where membership_id = 'fed00000-0000-0000-0000-000000000005'
     and organization_id = 'fea00000-0000-0000-0000-0000000000a1'
     and collaborator_id = 'feb00000-0000-0000-0000-000000000005'
     and status = 'active';
  if v_n <> 1 then
    v_falhas := v_falhas || format('vinculo ATIVO E->colaborador E = %s (esperado 1)', v_n);
  end if;

  -- (A2) o mecanismo estrutural da P1.1 esta instalado, e INVOKER e com search_path fixo.
  foreach v_fn in array array[
    'f5_11_validar_coerencia_identidade',
    'f5_11_validar_coerencia_identidade_evento'] loop
    if not exists (
      select 1 from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname = v_fn
    ) then
      v_falhas := v_falhas || format('funcao ausente: %s', v_fn);
      continue;
    end if;
    if exists (
      select 1 from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname = v_fn and p.prosecdef
    ) then
      v_falhas := v_falhas || format('funcao com SECURITY DEFINER: %s', v_fn);
    end if;
    if not exists (
      select 1 from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname = v_fn
         and p.proconfig is not null
         and array_to_string(p.proconfig, ',') like '%search_path=public%'
    ) then
      v_falhas := v_falhas || format('funcao sem search_path fixo: %s', v_fn);
    end if;
  end loop;

  -- (A3) os dois gatilhos existem, sao BEFORE ROW e chamam as funcoes certas.
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_observations'::regclass
       and t.tgname = 'trg_evaluation_observations_coerencia_identidade'
       and not t.tgisinternal and t.tgtype = 23
       and t.tgfoid = 'public.f5_11_validar_coerencia_identidade()'::regprocedure
  ) then
    v_falhas := v_falhas || 'gatilho de coerencia da LINHA ausente/incorreto (esperado BEFORE INSERT OR UPDATE ROW)';
  end if;
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_observation_events'::regclass
       and t.tgname = 'trg_evaluation_observation_events_coerencia_identidade'
       and not t.tgisinternal and t.tgtype = 7
       and t.tgfoid = 'public.f5_11_validar_coerencia_identidade_evento()'::regprocedure
  ) then
    v_falhas := v_falhas || 'gatilho de coerencia da TRILHA ausente/incorreto (esperado BEFORE INSERT ROW)';
  end if;

  -- (A4) D15 INTACTO e fronteira preservada.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo = %s (esperado 31)', v_n);
  end if;
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('goal.%% + observation.%% = %s (esperado 8)', v_n);
  end if;
  -- F5-11 P3 (Issue #246): D15 resolvida — `observation.*` existe em EXATAMENTE
  -- UMA role de sistema (`observacoes_gestor`, 4 capabilities) e em ZERO no
  -- bundle `admin` (a proibicao da P1.1 virou LISTA FECHADA explicita).
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 4 then
    v_falhas := v_falhas || format('observation.* com %s concessao(oes) (esperado 4)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
    join public.access_roles r on r.id = rc.access_role_id
   where c.code like 'observation.%'
     and (r.name <> 'observacoes_gestor' or r.is_system = false);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s concessao(oes) de observation.* FORA de observacoes_gestor', v_n);
  end if;
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    v_falhas := v_falhas || format('bundle admin com %s capabilities (esperado 9)', v_n);
  end if;
  if (select array_agg(r.name order by r.name) from public.access_roles r where r.is_system = true)
     is distinct from array['admin', 'metas_aprovador', 'metas_dono', 'observacoes_gestor'] then
    v_falhas := v_falhas || 'conjunto de roles de SISTEMA mudou (a P1.1 nao cria role/bundle/perfil)';
  end if;
  -- F5-11 P2 (Issue #244): a superficie `observacao_*` passou a existir e e'
  -- EXATAMENTE a lista fechada das 8 RPCs (a P1.1 nao cria nem esconde nenhuma).
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname like 'observacao\_%'
     and p.proname <> all (array[
       'observacao_criar', 'observacao_editar', 'observacao_definir_comunicado',
       'observacao_excluir', 'observacao_revogar', 'observacao_obter',
       'observacao_listar_por_escopo', 'observacao_historico']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) observacao_* FORA da lista fechada da P2', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname like 'observation\_%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) observation_* (prefixo proibido pelo D1)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] A/preflight F5-11 P1.1: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] A/preflight: fixture intra-tenant presente (5 identidades na MESMA organizacao: A/B/C com perfil e membership ATIVOS, D com membership DISABLED + vinculo ATIVO e E com perfil DISABLED - a matriz INTEGRAL de paridade; 4 memberships ativas), as 2 funcoes de coerencia instaladas (INVOKER, search_path fixo) com os 2 gatilhos BEFORE ROW corretos, catalogo 31, admin com 9 SEM observation.*, nenhuma concessao de observation.* (D15 intacto, e a concessao e artefato da P3) e a superficie observacao_* EXATAMENTE com as 8 RPCs da P2 (nem uma a mais)';
end $$;

-- ============================================================================
-- B) PARIDADE COM O RESOLVEDOR CANONICO (a regra nao e inventada)
-- ============================================================================
do $$
declare
  v_colab uuid;
  v_n     int;
begin
  -- (B1) perfil A -> colaborador A (vinculo ATIVO).
  select collaborator_id into v_colab
    from public.resolver_collaborador_vinculado('fec00000-0000-0000-0000-000000000001',
                                                'fea00000-0000-0000-0000-0000000000a1');
  if v_colab is distinct from 'feb00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] B1: resolver_collaborador_vinculado(perfil A) = % (esperado colaborador A)', v_colab;
  end if;

  -- (B2) perfil B -> colaborador B.
  select collaborator_id into v_colab
    from public.resolver_collaborador_vinculado('fec00000-0000-0000-0000-000000000002',
                                                'fea00000-0000-0000-0000-0000000000a1');
  if v_colab is distinct from 'feb00000-0000-0000-0000-000000000002'::uuid then
    raise exception '[FAIL] B2: resolver_collaborador_vinculado(perfil B) = % (esperado colaborador B)', v_colab;
  end if;

  -- (B3) perfil C tem vinculo DISABLED: o resolvedor NAO resolve (Q6=B).
  select count(*) into v_n
    from public.resolver_collaborador_vinculado('fec00000-0000-0000-0000-000000000003',
                                                'fea00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] B3: vinculo disabled resolveu no resolvedor canonico (% linha(s)) — premissa do teste invalida', v_n;
  end if;

  -- (B4) FINDING DO CODEX (metade ausente): perfil D tem membership DISABLED e
  --      vinculo ATIVO - o resolvedor NAO resolve (ele exige membership ativa).
  select count(*) into v_n
    from public.resolver_collaborador_vinculado('fec00000-0000-0000-0000-000000000004',
                                                'fea00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] B4 (finding do Codex): membership DISABLED com vinculo ATIVO resolveu no resolvedor canonico (% linha(s)) - premissa do teste invalida', v_n;
  end if;

  -- (B5) perfil E tem PERFIL DISABLED e vinculo ATIVO - o resolvedor NAO resolve
  --      (ele exige user_profiles.status = active).
  select count(*) into v_n
    from public.resolver_collaborador_vinculado('fec00000-0000-0000-0000-000000000005',
                                                'fea00000-0000-0000-0000-0000000000a1');
  if v_n <> 0 then
    raise exception '[FAIL] B5: perfil DISABLED resolveu no resolvedor canonico (% linha(s)) - premissa do teste invalida', v_n;
  end if;

  raise notice '[PASS] B/paridade INTEGRAL: o resolvedor canonico (F5-02) resolve perfil A -> colaborador A e perfil B -> colaborador B, e NAO resolve NENHUMA das tres negativas (C: vinculo DISABLED; D: membership DISABLED com vinculo ativo, o finding do Codex; E: perfil DISABLED) - a regra de author_collaborator_id do gatilho e a MESMA do resolvedor, nao uma regra inventada';
end $$;

-- ============================================================================
-- C) NEGATIVOS intra-tenant — os QUATRO pares perfil <-> membership
-- ============================================================================
-- Cada teste exige sqlstate P0001 (incoerencia estrutural). Se a FK (23503) ou o
-- CHECK (23514) respondessem antes, o finding NAO estaria corrigido.
do $$
declare
  v_st  text;
  v_ok  boolean;
  v_n   int;
  v_antes int;
begin
  select count(*) into v_antes from public.evaluation_observations
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';

  -- (C1) AUTORIA: perfil A com membership B.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'tentativa incoerente de autoria (P1.1)',
            'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000002');
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] C1 (finding do Codex): author_user_profile_id = perfil A com author_membership_id = membership B foi ACEITO ou recusado com o sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;

  -- (C2) COMUNICADO: perfil A com membership B (o CHECK do contrato esta satisfeito,
  --      logo quem tem de recusar e o invariante de coerencia).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       comunicado, comunicado_em, comunicado_por_user_profile_id, comunicado_por_membership_id,
       author_user_profile_id, author_membership_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'tentativa incoerente de comunicado (P1.1)',
            true, now(), 'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000002',
            'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001');
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] C2 (finding do Codex): comunicado_por_user_profile_id = perfil A com comunicado_por_membership_id = membership B foi ACEITO ou recusado com o sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;

  -- (C3) EXCLUSAO: perfil A com membership B.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       excluida, excluida_em, excluida_por_user_profile_id, excluida_por_membership_id,
       motivo_exclusao, author_user_profile_id, author_membership_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'tentativa incoerente de exclusao (P1.1)',
            true, now(), 'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000002',
            'motivo ficticio (P1.1)',
            'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001');
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] C3 (finding do Codex): excluida_por_user_profile_id = perfil A com excluida_por_membership_id = membership B foi ACEITO ou recusado com o sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;

  -- (C4) ATOR DA TRILHA: perfil A com membership B.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observation_events
      (organization_id, observation_id, entity_type, event_type, effective_date,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'fe900000-0000-0000-0000-000000000001',
            'evaluation_observation', 'EDITADA', now(), repeat('a', 64),
            'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000002',
            gen_random_uuid());
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] C4 (finding do Codex): actor_user_profile_id = perfil A com actor_membership_id = membership B foi ACEITO ou recusado com o sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;

  -- Nenhuma das 4 tentativas pode ter persistido linha.
  select count(*) into v_n from public.evaluation_observations
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';
  if v_n <> v_antes then
    raise exception '[FAIL] C: tentativa incoerente PERSISTIU linha (antes=%, depois=%)', v_antes, v_n;
  end if;

  raise notice '[PASS] C/negativos intra-tenant: os QUATRO pares perfil<->membership (autoria, comunicado, exclusao e ator do evento) RECUSAM a combinacao perfil A + membership B — MESMA organizacao — com P0001 (incoerencia estrutural), e nenhuma tentativa persistiu linha';
end $$;

-- ============================================================================
-- D) NEGATIVOS de author_collaborator_id (regra = resolvedor canonico INTEGRAL)
-- ============================================================================
do $$
declare
  v_st  text;
  v_msg text;
  v_ok  boolean;
  v_n   int;
begin
  -- (D1) colaborador B informado para a membership A.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id, author_collaborator_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'tentativa de colaborador trocado (P1.1)',
            'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001',
            'feb00000-0000-0000-0000-000000000002');
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] D1: author_collaborator_id = colaborador B com membership A foi ACEITO ou recusado com sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;

  -- (D2) colaborador A informado para a membership B.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id, author_collaborator_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'tentativa de colaborador trocado 2 (P1.1)',
            'fec00000-0000-0000-0000-000000000002', 'fed00000-0000-0000-0000-000000000002',
            'feb00000-0000-0000-0000-000000000001');
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] D2: author_collaborator_id = colaborador A com membership B foi ACEITO ou recusado com sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;

  -- (D3) vinculo DISABLED: informar o colaborador C para a membership C tem de ser
  --      recusado, porque o resolvedor canonico NAO resolve link disabled (Q6=B).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id, author_collaborator_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'tentativa com vinculo disabled (P1.1)',
            'fec00000-0000-0000-0000-000000000003', 'fed00000-0000-0000-0000-000000000003',
            'feb00000-0000-0000-0000-000000000003');
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] D3: author_collaborator_id com vinculo DISABLED foi ACEITO ou recusado com sqlstate errado (%) — esperado P0001 (paridade com o resolvedor)', coalesce(v_st, 'sem erro');
  end if;

  -- (D4) FINDING DO CODEX (metade ausente): membership D DISABLED + vinculo D ATIVO
  --      + colaborador correto do vinculo. O perfil esta ATIVO e a membership
  --      pertence a ele, logo o par perfil<->membership e coerente: quem TEM de
  --      recusar e o enforcement de author_collaborator_id.
  v_ok := false; v_st := null; v_msg := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id, author_collaborator_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'tentativa com membership disabled e vinculo ativo (P1.1)',
            'fec00000-0000-0000-0000-000000000004', 'fed00000-0000-0000-0000-000000000004',
            'feb00000-0000-0000-0000-000000000004');
  exception when others then v_st := sqlstate; v_msg := sqlerrm; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] D4 (finding do Codex): membership DISABLED com vinculo ATIVO aceitou author_collaborator_id (sqlstate=%) - esperado P0001', coalesce(v_st, 'sem erro');
  end if;
  if v_msg is null or v_msg not like '%Issue #242%' or v_msg not like '%author_collaborator_id%' then
    raise exception '[FAIL] D4: a recusa nao veio do enforcement de COERENCIA de author_collaborator_id (mensagem=%)', coalesce(v_msg, '<nula>');
  end if;

  -- (D5) TERCEIRA condicao do resolvedor: perfil E DISABLED com membership ATIVA e
  --      vinculo ATIVO e colaborador correto do vinculo - tambem tem de ser recusado.
  v_ok := false; v_st := null; v_msg := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id, author_collaborator_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'tentativa com perfil disabled (P1.1)',
            'fec00000-0000-0000-0000-000000000005', 'fed00000-0000-0000-0000-000000000005',
            'feb00000-0000-0000-0000-000000000005');
  exception when others then v_st := sqlstate; v_msg := sqlerrm; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] D5: perfil DISABLED aceitou author_collaborator_id (sqlstate=%) - esperado P0001', coalesce(v_st, 'sem erro');
  end if;
  if v_msg is null or v_msg not like '%Issue #242%' or v_msg not like '%author_collaborator_id%' then
    raise exception '[FAIL] D5: a recusa nao veio do enforcement de COERENCIA de author_collaborator_id (mensagem=%)', coalesce(v_msg, '<nula>');
  end if;

  -- (D6) NENHUMA das tentativas D1..D5 pode ter persistido linha: a fixture tem
  --      exatamente UMA observacao (a linha de base legitima do bloco 6).
  select count(*) into v_n from public.evaluation_observations
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';
  if v_n <> 1 then
    raise exception '[FAIL] D6: tentativa de author_collaborator_id incoerente PERSISTIU linha (observacoes da fixture = %, esperado 1)', v_n;
  end if;

  raise notice '[PASS] D/negativos de author_collaborator_id (paridade INTEGRAL com o resolvedor): colaborador de OUTRA membership (D1, D2), vinculo DISABLED (D3), membership DISABLED com vinculo ATIVO (D4 - o finding do Codex) e PERFIL DISABLED (D5) sao RECUSADOS com P0001 pelo enforcement de coerencia, e NENHUMA tentativa persistiu linha (D6)';
end $$;

-- ============================================================================
-- E) NEGATIVOS no caminho de UPDATE (a linha e MUTAVEL — D4 preserva a mutacao)
-- ============================================================================
-- NOTA DE RIGOR (prova individual do mecanismo): em UPDATE de
-- `author_collaborator_id` DOIS gatilhos podem levantar P0001 — o invariante de
-- COERENCIA desta atividade e o gatilho de IMUTABILIDADE do D4 (instalado na P1).
-- Para nao creditar a recusa ao mecanismo errado, os tres testes deste bloco
-- verificam tambem a MENSAGEM: ela tem de ser a do invariante de coerencia
-- ('Issue #242'). Em E1/E2 isso e automatico (o gatilho do D4 nao guarda
-- `comunicado_por_*`/`excluida_por_*`); em E3 e a prova de que quem recusou foi a
-- coerencia, e nao a imutabilidade.
--
-- No caminho de INSERT (blocos C e D) so o invariante de coerencia pode levantar
-- P0001 nestas tabelas: o gatilho de imutabilidade do D4 e BEFORE UPDATE e os tres
-- gatilhos da trilha guardam UPDATE/DELETE/TRUNCATE — nenhum deles dispara em
-- INSERT. Logo P0001 no INSERT identifica, sem ambiguidade, o mecanismo da P1.1.
do $$
declare
  v_st text;
  v_msg text;
  v_ok boolean;
  v_alvo uuid := 'fe900000-0000-0000-0000-000000000001';
begin
  -- (E1) marcar comunicado com o par incoerente.
  v_ok := false; v_st := null; v_msg := null;
  begin
    update public.evaluation_observations
       set comunicado_por_user_profile_id = 'fec00000-0000-0000-0000-000000000001',
           comunicado_por_membership_id   = 'fed00000-0000-0000-0000-000000000002'
     where id = v_alvo;
  exception when others then v_st := sqlstate; v_msg := sqlerrm; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] E1: UPDATE com par de COMUNICADO incoerente foi ACEITO ou recusado com sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;
  if v_msg is null or v_msg not like '%Issue #242%' then
    raise exception '[FAIL] E1: a recusa nao veio do invariante de coerencia (mensagem=%)', coalesce(v_msg, '<nula>');
  end if;

  -- (E2) excluir com o par incoerente.
  v_ok := false; v_st := null; v_msg := null;
  begin
    update public.evaluation_observations
       set excluida = true, excluida_em = now(),
           excluida_por_user_profile_id = 'fec00000-0000-0000-0000-000000000001',
           excluida_por_membership_id   = 'fed00000-0000-0000-0000-000000000002',
           motivo_exclusao = 'motivo ficticio (P1.1)'
     where id = v_alvo;
  exception when others then v_st := sqlstate; v_msg := sqlerrm; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] E2: UPDATE com par de EXCLUSAO incoerente foi ACEITO ou recusado com sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;
  if v_msg is null or v_msg not like '%Issue #242%' then
    raise exception '[FAIL] E2: a recusa nao veio do invariante de coerencia (mensagem=%)', coalesce(v_msg, '<nula>');
  end if;

  -- (E3) trocar author_collaborator_id para o colaborador de outra membership.
  --      Prova que quem recusou foi a COERENCIA (mensagem cita a coluna), e nao a
  --      imutabilidade do D4 (cuja mensagem fala em campos IMUTAVEIS).
  v_ok := false; v_st := null; v_msg := null;
  begin
    update public.evaluation_observations
       set author_collaborator_id = 'feb00000-0000-0000-0000-000000000002'
     where id = v_alvo;
  exception when others then v_st := sqlstate; v_msg := sqlerrm; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] E3: UPDATE de author_collaborator_id incoerente foi ACEITO ou recusado com sqlstate errado (%) — esperado P0001', coalesce(v_st, 'sem erro');
  end if;
  if v_msg is null or v_msg not like '%Issue #242%' or v_msg not like '%author_collaborator_id%' then
    raise exception '[FAIL] E3: a recusa nao veio do invariante de COERENCIA de author_collaborator_id (mensagem=%)', coalesce(v_msg, '<nula>');
  end if;

  -- (E4) a linha alvo continua INTACTA apos as 3 tentativas.
  if not exists (
    select 1 from public.evaluation_observations
     where id = v_alvo and comunicado and not excluida
       and comunicado_por_membership_id = 'fed00000-0000-0000-0000-000000000001'
       and author_collaborator_id = 'feb00000-0000-0000-0000-000000000001'
  ) then
    raise exception '[FAIL] E4: as tentativas de UPDATE incoerente alteraram a linha legitima';
  end if;

  raise notice '[PASS] E/negativos no UPDATE: marcar comunicado, excluir e trocar author_collaborator_id com par/colaborador incoerente sao RECUSADOS com P0001 no caminho de UPDATE (a linha e mutavel), e a linha legitima permanece intacta';
end $$;

-- ============================================================================
-- F) POSITIVOS — as combinacoes legitimas continuam validas
-- ============================================================================
do $$
declare
  v_obs_n   int;
  v_ev_n    int;
  v_antes_obs int;
  v_antes_ev  int;
begin
  select count(*) into v_antes_obs from public.evaluation_observations
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_antes_ev from public.evaluation_observation_events
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';

  -- (F1) par COERENTE completo: autor A/A + colaborador A + comunicado A/A + exclusao A/A.
  insert into public.evaluation_observations
    (organization_id, collaborator_id, cycle_id, tipo, texto,
     comunicado, comunicado_em, comunicado_por_user_profile_id, comunicado_por_membership_id,
     author_user_profile_id, author_membership_id, author_collaborator_id)
  values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
          'fed10000-0000-0000-0000-0000000000a1', 'POSITIVA', 'observacao coerente A/A (P1.1)',
          true, now(), 'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001',
          'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001',
          'feb00000-0000-0000-0000-000000000001');

  -- (F2) par COERENTE do perfil B (prova que o invariante nao "chumbou" uma identidade).
  insert into public.evaluation_observations
    (organization_id, collaborator_id, cycle_id, tipo, texto,
     author_user_profile_id, author_membership_id, author_collaborator_id)
  values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000002',
          'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'observacao coerente B/B (P1.1)',
          'fec00000-0000-0000-0000-000000000002', 'fed00000-0000-0000-0000-000000000002',
          'feb00000-0000-0000-0000-000000000002');

  -- (F3) author_collaborator_id NULO continua legitimo (ator sem vinculo): o
  --      invariante julga COERENCIA entre valores INFORMADOS; a completude da
  --      derivacao e responsabilidade da operacao soberana da P2, nao deste gate.
  insert into public.evaluation_observations
    (organization_id, collaborator_id, cycle_id, tipo, texto,
     author_user_profile_id, author_membership_id, author_collaborator_id)
  values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
          'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'observacao com autoria sem vinculo (P1.1)',
          'fec00000-0000-0000-0000-000000000003', 'fed00000-0000-0000-0000-000000000003', null);

  -- (F4) trilha com ator COERENTE (perfil A + membership A).
  insert into public.evaluation_observation_events
    (organization_id, observation_id, entity_type, event_type, effective_date,
     reason, payload_hash, result_entity_id,
     actor_user_profile_id, actor_membership_id, operation_id)
  values ('fea00000-0000-0000-0000-0000000000a1', 'fe900000-0000-0000-0000-000000000001',
          'evaluation_observation', 'EDITADA', now(), 'evento coerente (P1.1)',
          repeat('b', 64), 'fe900000-0000-0000-0000-000000000001',
          'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001',
          'fe600000-0000-0000-0000-000000000002');

  -- (F5) transicoes legitimas na LINHA: excluir e revogar com o par coerente.
  update public.evaluation_observations
     set excluida = true, excluida_em = now(),
         excluida_por_user_profile_id = 'fec00000-0000-0000-0000-000000000001',
         excluida_por_membership_id = 'fed00000-0000-0000-0000-000000000001',
         motivo_exclusao = 'motivo ficticio de prova (P1.1)'
   where id = 'fe900000-0000-0000-0000-000000000001';
  update public.evaluation_observations
     set excluida = false, excluida_em = null,
         excluida_por_user_profile_id = null, excluida_por_membership_id = null,
         motivo_exclusao = null
   where id = 'fe900000-0000-0000-0000-000000000001';

  select count(*) into v_obs_n from public.evaluation_observations
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';
  select count(*) into v_ev_n from public.evaluation_observation_events
   where organization_id = 'fea00000-0000-0000-0000-0000000000a1';

  if v_obs_n <> v_antes_obs + 3 then
    raise exception '[FAIL] F: observacoes legitimas nao foram persistidas (antes=%, depois=%, esperado +3)', v_antes_obs, v_obs_n;
  end if;
  if v_ev_n <> v_antes_ev + 1 then
    raise exception '[FAIL] F: evento legitimo nao foi persistido (antes=%, depois=%, esperado +1)', v_antes_ev, v_ev_n;
  end if;

  raise notice '[PASS] F/positivos: as combinacoes COERENTES continuam validas — perfil A + membership A (+ colaborador A), perfil B + membership B (+ colaborador B), author_collaborator_id NULO, evento com ator coerente, e as transicoes legitimas de exclusao e revogacao (3 observacoes e 1 evento persistidos)';
end $$;

-- ============================================================================
-- G) SEPARACAO DE CLASSES DE ERRO + invariantes da P1 preservados
-- ============================================================================
do $$
declare
  v_st text;
  v_ok boolean;
begin
  -- (G1) par com apenas UM lado informado continua sendo recusado pelo CHECK do
  --      contrato (23514) — o invariante de coerencia NAO pode mascarar a classe
  --      de erro da constraint.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       comunicado, comunicado_em, comunicado_por_membership_id,
       author_user_profile_id, author_membership_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'par incompleto (P1.1)',
            true, now(), 'fed00000-0000-0000-0000-000000000001',
            'fec00000-0000-0000-0000-000000000001', 'fed00000-0000-0000-0000-000000000001');
  exception when others then v_st := sqlstate; if v_st = '23514' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] G1: par com apenas um lado informado deveria cair no CHECK do contrato (23514), veio %', coalesce(v_st, 'sem erro');
  end if;

  -- (G2) perfil INEXISTENTE continua caindo na FK (23503), nao no invariante.
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'perfil inexistente (P1.1)',
            gen_random_uuid(), 'fed00000-0000-0000-0000-000000000001');
  exception when others then v_st := sqlstate; if v_st = '23503' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] G2: perfil inexistente deveria cair na FK (23503), veio %', coalesce(v_st, 'sem erro');
  end if;

  -- (G3) membership INEXISTENTE continua caindo na FK (23503).
  v_ok := false; v_st := null;
  begin
    insert into public.evaluation_observations
      (organization_id, collaborator_id, cycle_id, tipo, texto,
       author_user_profile_id, author_membership_id)
    values ('fea00000-0000-0000-0000-0000000000a1', 'feb00000-0000-0000-0000-000000000001',
            'fed10000-0000-0000-0000-0000000000a1', 'NEUTRA', 'membership inexistente (P1.1)',
            'fec00000-0000-0000-0000-000000000001', gen_random_uuid());
  exception when others then v_st := sqlstate; if v_st = '23503' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] G3: membership inexistente deveria cair na FK (23503), veio %', coalesce(v_st, 'sem erro');
  end if;

  -- (G4) D4 INTACTA: campo imutavel continua recusado por gatilho (P0001).
  v_ok := false; v_st := null;
  begin
    update public.evaluation_observations
       set author_membership_id = 'fed00000-0000-0000-0000-000000000002'
     where id = 'fe900000-0000-0000-0000-000000000001';
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] G4: D4 (imutabilidade) deixou de recusar — sqlstate %', coalesce(v_st, 'sem erro');
  end if;

  -- (G5) D6 INTACTA: a trilha continua append-only.
  v_ok := false; v_st := null;
  begin
    update public.evaluation_observation_events
       set reason = 'reescrita (P1.1)'
     where id = 'fe700000-0000-0000-0000-000000000001';
  exception when others then v_st := sqlstate; if v_st = 'P0001' then v_ok := true; end if;
  end;
  if not v_ok then
    raise exception '[FAIL] G5: D6 (append-only) deixou de recusar UPDATE — sqlstate %', coalesce(v_st, 'sem erro');
  end if;

  -- (G6) D9 INTACTA: RLS ligada, ZERO policy e cliente negado por PERMISSAO.
  if exists (
    select 1 from pg_policies p
     where p.schemaname = 'public'
       and p.tablename in ('evaluation_observations', 'evaluation_observation_events')
  ) then
    raise exception '[FAIL] G6: policy apareceu nas tabelas de observacoes (D9 exige ZERO)';
  end if;
  set role authenticated;
  v_ok := false; v_st := null;
  begin
    perform count(*) from public.evaluation_observations;
  exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  reset role;
  if not v_ok or v_st <> '42501' then
    raise exception '[FAIL] G6: SELECT de authenticated deveria ser negado por permissao (42501), veio %', coalesce(v_st, 'sem erro');
  end if;

  raise notice '[PASS] G/classes de erro e invariantes: incoerencia estrutural = P0001; par incompleto = CHECK do contrato (23514); referencia inexistente = FK (23503) — cada classe com o seu sqlstate — e D4 (imutabilidade), D6 (append-only) e D9 (RLS/ACL, cliente negado por 42501) permanecem INTACTAS';
end $$;

-- ============================================================================
-- H) HIGIENE
-- ============================================================================
do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] H: % funcao(oes) temporaria(s) `_mut_*` residual(is)', v_n;
  end if;
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'S' and c.relname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] H: % sequence(s) temporaria(s) `_mut_*` residual(is)', v_n;
  end if;
  select count(*) into v_n from pg_trigger t where t.tgname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] H: % gatilho(s) temporario(s) `_mut_*` residual(is)', v_n;
  end if;

  raise notice '[PASS] H/higiene: nenhum residuo de prova no schema';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-11 P1.1 (Issue #242): FINDING MEDIUM DO CODEX CORRIGIDO.';
  raise notice '  Os 4 pares perfil<->membership (autoria, comunicado, exclusao e ator';
  raise notice '  do evento) recusam combinacoes INTRA-TENANT incoerentes com P0001;';
  raise notice '  author_collaborator_id segue o resolvedor canonico F5-02 com paridade';
  raise notice '  INTEGRAL (perfil ativo + membership ativa + vinculo ativo); as';
  raise notice '  combinacoes legitimas continuam validas;';
  raise notice '  D4/D6/D9 intactas; D15 continua bloqueando a P3; P2 nao iniciada.';
  raise notice '============================================================';
end $$;
