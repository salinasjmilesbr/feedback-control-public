-- ============================================================================
-- F5-11 P2 (Issue #244): VALIDADOR das RPCs soberanas `observacao_*`
-- Saida: [PASS]/[FAIL]; falha aborta (ON_ERROR_STOP).
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de:
--   supabase/validacao/38-cenario-f5-11-p2.sql   (fixture)
--   supabase/validacao/39-validar-f5-11-p2.sql   (este arquivo)
--
-- Contrato coberto (docs/F5-11-desenho-tecnico.md; D1-D16; §7, §8, §12, §17.1):
--   A  preflight: 8 RPCs + 6 helpers INVOKER, search_path fixo, EXECUTE so
--      service_role, lista FECHADA da superficie, catalogo 31, D15 intacto,
--      D4/D6/D9 e a coerencia da P1.1 preservados;
--   B  ESTADO DE PRODUCAO (ator INELEGIVEL): o MESMO create que o bloco C aceita e'
--      NEGADO por capability — na P5.1 a elegibilidade (membership + perfil +
--      vinculo ATIVOS) concede `observacoes_avaliado` AUTOMATICAMENTE, logo a
--      prova de DENY por capability exige ator inelegivel — + ACL
--      (authenticated/anon nao executam nem leem: 42501);
--   C  (begin/rollback, com concessao TRANSITORIA de fixture) a matriz completa:
--      positivos de criar/editar/comunicar/descomunicar/excluir/revogar com
--      versao, eventos e before/after; idempotencia dupla; negativos de D11
--      (active/leave/inactive e status nao resolvido), D12 (4 estados de ciclo),
--      D5 (outro autor), D10 (stale), D16 (texto/motivo), relacao, SELF,
--      cross-tenant, override de identidade (auth.uid()), perfil inativo,
--      membership revogada, capability ausente, operacao desconhecida; leitura
--      (obter/listar_por_escopo/historico) e rollback por falha injetada;
--   D  POS-ROLLBACK: NADA persistiu do CENARIO (zero concessao de fixture; os 2
--      perfis de sistema com observation.* vem das migrations P3/P5.1 — 4 de
--      gestao + 1 SELF automatica aos elegiveis, admin sempre ZERO — e nao deste
--      cenario), nenhuma role/bundle de fixture, zero observacao/evento e zero
--      residuo `_mut_`.
--
-- NOTA DE RIGOR (D15 x testes funcionais): a P2 NAO concede `observation.*` (a
-- concessao e' artefato da P3). Para exercitar o caminho ALLOW sem conceder nada,
-- o bloco C cria uma role de FIXTURE (is_system = false) e a concessao DENTRO de
-- uma transacao explicitamente DESFEITA (`begin` ... `rollback`): o estado final
-- do banco e' identico ao inicial e o bloco D prova isso. Nenhuma role/bundle/
-- perfil de PRODUTO e' criado e `admin` permanece sem `observation.*`.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) PREFLIGHT fail-closed
-- ============================================================================
do $$
declare
  v_falhas   text[] := array[]::text[];
  v_rpcs     text[] := array[
    'observacao_criar(uuid, uuid, uuid, text, text, uuid, uuid)',
    'observacao_editar(uuid, uuid, text, text, boolean, integer, uuid, uuid)',
    'observacao_definir_comunicado(uuid, uuid, boolean, integer, uuid, uuid)',
    'observacao_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_revogar(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_obter(uuid, uuid, uuid)',
    'observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)',
    'observacao_historico(uuid, uuid, uuid)'];
  v_helpers  text[] := array[
    'f5_11_ator_efetivo_observacao(uuid)',
    'f5_11_ator_valido_observacao(uuid, uuid, text)',
    'f5_11_vinculo_observacao_do_ator(uuid, uuid)',
    'f5_11_relacao_observacao_do_ator(uuid, uuid, uuid, timestamptz)',
    'f5_11_status_vigente_do_colaborador(uuid, timestamptz)',
    'f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid)'];
  v_fn       text;
  v_tab      text;
  v_rec      record;
  v_n        integer;
begin
  -- (A1) fixture presente e IDENTIFICADA: o nome detecta colisao de UUID entre
  --      fases (defeito ja ocorrido com o prefixo `f2` da F5-10 P4) e as
  --      contagens filtram pelo PREFIXO dos ids, ficando imunes a convivencia
  --      com qualquer outra fixture da bateria.
  select count(*) into v_n from public.organizations
   where id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and name = 'Org Sintetica F5-11 P2 Alfa';
  if v_n <> 1 then
    v_falhas := v_falhas || 'organizacao da fixture ausente OU com outro nome (colisao de UUID entre fixtures)';
  end if;
  select count(*) into v_n from public.collaborators
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and id::text like 'f5b2e000-%';
  if v_n <> 9 then
    v_falhas := v_falhas || format('colaboradores da fixture em Alfa = %s (esperado 9)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_cycles
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and id::text like 'f5b21000-%';
  if v_n <> 4 then
    v_falhas := v_falhas || format('ciclos da fixture em Alfa = %s (esperado 4)', v_n);
  end if;

  -- (A2) superficie exata, INVOKER, search_path fixo e EXECUTE so service_role.
  foreach v_fn in array (v_rpcs || v_helpers) loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config
      into v_rec
      from pg_proc p
     where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      v_falhas := v_falhas || ('funcao ausente: ' || v_fn);
      continue;
    end if;
    if v_rec.prosecdef then
      v_falhas := v_falhas || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_falhas := v_falhas || ('sem search_path fixo: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_falhas := v_falhas || ('sem EXECUTE para service_role: ' || v_fn);
    end if;
    if has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE') then
      v_falhas := v_falhas || ('EXECUTE exposto a anon/authenticated: ' || v_fn);
    end if;
  end loop;

  -- (A3) lista FECHADA: nenhuma `observacao_*` fora das 8 RPCs e nenhuma
  --      `observation_*` (prefixo proibido pelo D1).
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname like 'observacao\_%'
     and not exists (
       select 1 from unnest(v_rpcs) f
        where to_regprocedure('public.' || f) = p.oid
     );
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) observacao_* FORA da lista fechada da P2', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like 'observation\_%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) observation_* (D1 proibe o prefixo)', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s residuo(s) `_mut_` no schema', v_n);
  end if;

  -- (A4) D9/D4/D6/P1.1 INTACTOS.
  foreach v_tab in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      v_falhas := v_falhas || ('RLS desabilitada: ' || v_tab);
    end if;
    if exists (
      select 1 from pg_policies where schemaname = 'public' and tablename = v_tab
    ) then
      v_falhas := v_falhas || ('policy indevida (D9 exige ZERO): ' || v_tab);
    end if;
    if has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'DELETE')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'TRUNCATE') then
      v_falhas := v_falhas || ('privilegio de cliente aberto em ' || v_tab);
    end if;
  end loop;
  foreach v_fn in array array[
    'trg_evaluation_observations_imutaveis',
    'trg_evaluation_observations_updated_at',
    'trg_evaluation_observation_events_append_only',
    'trg_evaluation_observation_events_no_delete',
    'trg_evaluation_observation_events_no_truncate',
    'trg_evaluation_observations_coerencia_identidade',
    'trg_evaluation_observation_events_coerencia_identidade'] loop
    if not exists (select 1 from pg_trigger t where t.tgname = v_fn and not t.tgisinternal) then
      v_falhas := v_falhas || ('gatilho ausente: ' || v_fn);
    end if;
  end loop;

  -- (A5) D15 RESOLVIDA NA P3 (Issue #246): 4 concessoes, TODAS no perfil
  --      funcional `observacoes_gestor`; `admin` continua sem observation.*. A
  --      P2 nao concedia nada; a P3 INVERTE isso em lista fechada explicita.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo = %s (esperado 31)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 5 then
    v_falhas := v_falhas || format('%s concessao(oes) de observation.* (esperado 5: 4 em observacoes_gestor + 1 em observacoes_avaliado)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
    join public.access_roles r on r.id = rc.access_role_id
   where c.code like 'observation.%'
     and (r.is_system is not true
          or (r.name, c.code) not in (
            ('observacoes_gestor', 'observation.read'),
            ('observacoes_gestor', 'observation.create'),
            ('observacoes_gestor', 'observation.edit'),
            ('observacoes_gestor', 'observation.delete'),
            ('observacoes_avaliado', 'observation.read')
          ));
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s concessao(oes) de observation.* FORA da lista fechada (role, capability)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.access_roles r on r.id = rc.access_role_id
   where r.name = 'observacoes_avaliado' and r.is_system = true;
  if v_n <> 1 then
    v_falhas := v_falhas || format('observacoes_avaliado com %s capabilities (esperado 1: observation.read)', v_n);
  end if;
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    v_falhas := v_falhas || format('bundle admin com %s capabilities (esperado 9)', v_n);
  end if;
  if (select array_agg(r.name order by r.name)
        from public.access_roles r where r.is_system = true)
     is distinct from array['admin', 'evaluator', 'metas_aprovador', 'metas_dono', 'observacoes_avaliado', 'observacoes_gestor'] then
    v_falhas := v_falhas || 'conjunto de roles de SISTEMA mudou';
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] A/preflight F5-11 P2: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] A/preflight: fixture presente; 8 RPCs + 6 helpers INVOKER com search_path fixo e EXECUTE SO service_role (lista FECHADA, nenhuma observation_*); catalogo 31; concessoes de observation.* = 4 em `observacoes_gestor` (gestao, P3) + 1 em `observacoes_avaliado` (SELF, provisionada AUTOMATICAMENTE aos elegiveis pela P5.1) e admin com 9 SEM observation.*; RLS ligada com ZERO policy e ZERO privilegio de cliente; D4/D6 e a coerencia da P1.1 instalados';
end $$;

-- ============================================================================
-- B) ESTADO DE PRODUCAO (D15 + F5-11 P5.1): o DENY por CAPABILITY exige ator
--    INELEGIVEL. Com a provisao AUTOMATICA do perfil SELF `observacoes_avaliado`
--    (P5.1, Issue #252) todo ator ELEGIVEL (membership + perfil + vinculo ATIVOS)
--    passa a ter `observation.read`; logo a AUSENCIA de capability como MOTIVO do
--    DENY so pode ser provada com ator sem perfil/membership/vinculo ativo. Aqui
--    usamos o ator de PERFIL INATIVO (`...a4`) — genuinamente INELEGIVEL (mesmo
--    ator ja usado no bloco C5). A prova POSITIVA do invariante novo esta no C5.
-- ============================================================================
do $$
declare
  v_st   text;
  v_msg  text;
  v_n    int;
begin
  v_st := null; v_msg := null;
  begin
    perform public.observacao_criar(
      'f5b2a000-0000-0000-0000-0000000000a1', 'f5b21000-0000-0000-0000-0000000000a1',
      'f5b2e000-0000-0000-0000-0000000000c2', 'NEUTRA', 'tentativa de ator INELEGIVEL (P2/P5.1)',
      'f5b2c000-0000-0000-0000-0000000000a4', gen_random_uuid());
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('capability' in v_msg) = 0 then
    raise exception '[FAIL] B1: ator INELEGIVEL no create deveria ser DENY por capability (P0001 com "capability"), veio % / %',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  v_st := null; v_msg := null;
  begin
    perform public.observacao_obter(
      'f5b21000-0000-0000-0000-0000000000a1', 'f5b2a000-0000-0000-0000-0000000000a1',
      'f5b2c000-0000-0000-0000-0000000000a4');
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('capability' in v_msg) = 0 then
    raise exception '[FAIL] B2: ator INELEGIVEL na leitura deveria ser DENY por capability, veio % / %',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  select count(*) into v_n from public.evaluation_observations
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1';
  if v_n <> 0 then
    raise exception '[FAIL] B: o DENY por capability PERSISTIU linha (% observacoes)', v_n;
  end if;

  -- ACL: cliente NAO executa as RPCs nem le as tabelas.
  set role authenticated;
  v_st := null;
  begin
    perform public.observacao_obter(
      'f5b21000-0000-0000-0000-0000000000a1', 'f5b2a000-0000-0000-0000-0000000000a1',
      'f5b2c000-0000-0000-0000-0000000000a1');
  exception when insufficient_privilege then v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  reset role;
  if v_st is distinct from '42501' then
    raise exception '[FAIL] B3: authenticated executou observacao_obter (sqlstate %) — EXECUTE deveria ser negado por permissao', coalesce(v_st, 'sem erro');
  end if;

  set role authenticated;
  v_st := null;
  begin
    perform count(*) from public.evaluation_observations;
  exception when insufficient_privilege then v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  reset role;
  if v_st is distinct from '42501' then
    raise exception '[FAIL] B4: authenticated leu evaluation_observations (sqlstate %) — D9 exige 42501', coalesce(v_st, 'sem erro');
  end if;

  raise notice '[PASS] B/estado de producao (D15/P5.1): ator INELEGIVEL (membership, perfil ou vinculo nao ativos) tem o create e a leitura NEGADOS por capability (P0001) e NADA persiste; `authenticated` nao executa as RPCs nem le as tabelas (42501). O ator ELEGIVEL recebe `observacoes_avaliado` AUTOMATICAMENTE (P5.1) e cai na regra de alvo/relacao; a concessao de gestao e artefato da P3';
end $$;

-- ============================================================================
-- C) MATRIZ FUNCIONAL (concessao TRANSITORIA desfeita por rollback)
-- ============================================================================
begin;

-- (C0) Fixture TRANSITORIA de capacidade: role de teste (is_system = false) com as
--      4 capabilities e assignments ativos para GESTOR, OUTRO e SUB_ATIVO.
insert into public.access_roles (id, name, status, is_system, organization_id) values
  ('f5b29000-0000-0000-0000-0000000000f1', 'f5-11-p2-fixture-transitoria', 'active', false,
   'f5b2a000-0000-0000-0000-0000000000a1');

insert into public.access_role_capabilities (access_role_id, capability_id)
select 'f5b29000-0000-0000-0000-0000000000f1', c.id
  from public.capabilities c
 where c.code in ('observation.read', 'observation.create',
                  'observation.edit', 'observation.delete');

insert into public.membership_access_role_assignments
  (id, membership_id, organization_id, access_role_id, status, created_by) values
  ('f5b28000-0000-0000-0000-0000000000a1', 'f5b2d000-0000-0000-0000-0000000000a1',
   'f5b2a000-0000-0000-0000-0000000000a1', 'f5b29000-0000-0000-0000-0000000000f1',
   'active', 'f5b2c000-0000-0000-0000-0000000000a1'),
  ('f5b28000-0000-0000-0000-0000000000a2', 'f5b2d000-0000-0000-0000-0000000000a2',
   'f5b2a000-0000-0000-0000-0000000000a1', 'f5b29000-0000-0000-0000-0000000000f1',
   'active', 'f5b2c000-0000-0000-0000-0000000000a2'),
  ('f5b28000-0000-0000-0000-0000000000a6', 'f5b2d000-0000-0000-0000-0000000000a6',
   'f5b2a000-0000-0000-0000-0000000000a1', 'f5b29000-0000-0000-0000-0000000000f1',
   'active', 'f5b2c000-0000-0000-0000-0000000000a6');
-- F5-11 P3 (Issue #246): o gate passou a exigir SCOPE CUMULATIVO (D15) alem da
-- capability. A concessao TRANSITORIA desta fixture passa a ter scope de GESTAO
-- (DESCENDANTS, que cobre DIRECT_REPORTS), preservando integralmente os cenarios
-- ALLOW da P2; a leitura SELF-comunicada continua isenta por regra do dominio.
insert into public.access_role_assignment_scopes
  (assignment_id, organization_id, scope_type, status, created_by)
select a.id, 'f5b2a000-0000-0000-0000-0000000000a1', 'DESCENDANTS', 'active',
       'f5b2c000-0000-0000-0000-0000000000a1'
  from public.membership_access_role_assignments a
 where a.access_role_id = 'f5b29000-0000-0000-0000-0000000000f1'
   and a.status = 'active';

-- Helper TRANSITORIO de assercao negativa (removido no fim deste bloco; a
-- transacao e' desfeita de qualquer forma).
create or replace function public._mut_f5_11_p2_neg(
  p_sql text,
  p_state text,
  p_trecho text,
  p_rotulo text
)
returns void
language plpgsql
as $$
declare
  v_st  text;
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is null then
    raise exception '[FAIL] %: operacao foi ACEITA (esperado %)', p_rotulo, p_state;
  end if;
  if v_st is distinct from p_state then
    raise exception '[FAIL] %: sqlstate % (esperado %) — %', p_rotulo, v_st, p_state, v_msg;
  end if;
  if p_trecho is not null and position(p_trecho in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] %: mensagem sem o trecho "%" (veio: %)', p_rotulo, p_trecho, v_msg;
  end if;
end;
$$;

do $$
declare
  v_alfa  uuid := 'f5b2a000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f5b2a000-0000-0000-0000-0000000000b1';
  v_pgest uuid := 'f5b2c000-0000-0000-0000-0000000000a1';
  v_poutro uuid := 'f5b2c000-0000-0000-0000-0000000000a2';
  v_psemcap uuid := 'f5b2c000-0000-0000-0000-0000000000a3';
  v_pperfil uuid := 'f5b2c000-0000-0000-0000-0000000000a4';
  v_pmemb  uuid := 'f5b2c000-0000-0000-0000-0000000000a5';
  v_psub   uuid := 'f5b2c000-0000-0000-0000-0000000000a6';
  v_pbeta  uuid := 'f5b2c000-0000-0000-0000-0000000000b1';
  v_mgest  uuid := 'f5b2d000-0000-0000-0000-0000000000a1';
  v_moutro uuid := 'f5b2d000-0000-0000-0000-0000000000a2';
  v_msub   uuid := 'f5b2d000-0000-0000-0000-0000000000a6';
  v_cgest  uuid := 'f5b2e000-0000-0000-0000-0000000000c1';
  v_csub   uuid := 'f5b2e000-0000-0000-0000-0000000000c2';
  v_clic   uuid := 'f5b2e000-0000-0000-0000-0000000000c3';
  v_cinat  uuid := 'f5b2e000-0000-0000-0000-0000000000c4';
  v_coutro uuid := 'f5b2e000-0000-0000-0000-0000000000c5';
  v_csemcap uuid := 'f5b2e000-0000-0000-0000-0000000000c6';
  v_csemst uuid := 'f5b2e000-0000-0000-0000-0000000000c7';
  v_cbeta  uuid := 'f5b2e000-0000-0000-0000-0000000000d1';
  v_cativo uuid := 'f5b21000-0000-0000-0000-0000000000a1';
  v_cplan  uuid := 'f5b21000-0000-0000-0000-0000000000a2';
  v_cenc   uuid := 'f5b21000-0000-0000-0000-0000000000a3';
  v_ccanc  uuid := 'f5b21000-0000-0000-0000-0000000000a4';
  v_cbeta_c uuid := 'f5b21000-0000-0000-0000-0000000000b1';

  v_obs1  uuid;
  v_obs2  uuid;
  v_obs3  uuid;
  v_obs_inat uuid;
  v_obs_beta uuid;
  v_res   jsonb;
  v_res2  jsonb;
  v_ver   integer;
  v_n     integer;
  v_ant_obs integer;
  v_ant_ev  integer;
  v_msg   text;
  v_st    text;
begin
  select count(*) into v_ant_obs from public.evaluation_observations
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_ant_ev from public.evaluation_observation_events
   where organization_id in (v_alfa, v_beta);
  if v_ant_obs <> 0 or v_ant_ev <> 0 then
    raise exception '[FAIL] C0: a fixture deveria comecar sem observacoes/eventos (obs=%, ev=%)',
      v_ant_obs, v_ant_ev;
  end if;

  -- --------------------------------------------------------------------------
  -- (C1) POSITIVOS: criar (active), criar (leave), editar, comunicar,
  --      descomunicar, excluir e revogar — com versao, eventos e before/after.
  -- --------------------------------------------------------------------------
  v_res := public.observacao_criar(
    v_alfa, v_cativo, v_csub, 'POSITIVA', 'observacao ficticia da P2 (c2)',
    v_pgest, 'f5b20000-0000-0000-0000-000000000001');
  v_obs1 := (v_res->>'observation_id')::uuid;
  if v_obs1 is null or (v_res->>'version')::integer <> 0 then
    raise exception '[FAIL] C1/criar: retorno inesperado (%)', v_res;
  end if;
  if not exists (
    select 1 from public.evaluation_observations o
     where o.id = v_obs1 and o.organization_id = v_alfa and o.collaborator_id = v_csub
       and o.cycle_id = v_cativo and o.tipo = 'POSITIVA'
       and o.texto = 'observacao ficticia da P2 (c2)'
       and o.comunicado = false and o.excluida = false and o.version = 0
       and o.author_user_profile_id = v_pgest
       and o.author_membership_id = v_mgest
       and o.author_collaborator_id = v_cgest
  ) then
    raise exception '[FAIL] C1/criar: linha persistida fora do contrato (autoria derivada de auth.uid()/vinculo)';
  end if;

  -- D11: criacao PERMITIDA para colaborador em `leave`.
  v_res := public.observacao_criar(
    v_alfa, v_cativo, v_clic, 'NEUTRA', 'observacao ficticia da P2 (leave)',
    v_pgest, 'f5b20000-0000-0000-0000-000000000002');
  v_obs2 := (v_res->>'observation_id')::uuid;
  if v_obs2 is null then
    raise exception '[FAIL] C1/criar(leave): retorno sem observation_id (%)', v_res;
  end if;

  -- Edicao da DEFINICAO COMPLETA (tipo/texto) pelo AUTOR.
  v_res := public.observacao_editar(
    v_obs1, v_alfa, 'NEGATIVA', 'observacao ficticia da P2 (editada)', false, 0,
    v_pgest, 'f5b20000-0000-0000-0000-000000000003');
  v_ver := (v_res->>'version')::integer;
  if v_ver <> 1 or (v_res->>'transicao_comunicado') is not null then
    raise exception '[FAIL] C1/editar: retorno inesperado (%)', v_res;
  end if;
  if not exists (
    select 1 from public.evaluation_observation_events e
     where e.observation_id = v_obs1 and e.event_type = 'EDITADA'
       and e.before_value->>'texto' = 'observacao ficticia da P2 (c2)'
       and e.after_value->>'texto' = 'observacao ficticia da P2 (editada)'
       and e.before_value->>'version' = '0' and e.after_value->>'version' = '1'
       and e.actor_user_profile_id = v_pgest and e.actor_membership_id = v_mgest
       and e.payload_hash ~ '^[0-9a-f]{64}$'
  ) then
    raise exception '[FAIL] C1/editar: evento EDITADA ausente/incoerente (before/after)';
  end if;

  -- COMUNICAR pela edicao (transicao = FATO proprio com evento dedicado).
  v_res := public.observacao_editar(
    v_obs1, v_alfa, 'NEGATIVA', 'observacao ficticia da P2 (editada)', true, 1,
    v_pgest, 'f5b20000-0000-0000-0000-000000000004');
  v_ver := (v_res->>'version')::integer;
  if v_ver <> 2 or (v_res->>'transicao_comunicado') <> 'COMUNICADO' then
    raise exception '[FAIL] C1/editar+comunicar: retorno inesperado (%)', v_res;
  end if;
  if not exists (
    select 1 from public.evaluation_observation_events e
     where e.observation_id = v_obs1 and e.event_type = 'COMUNICADO'
       and e.operation_id <> 'f5b20000-0000-0000-0000-000000000004'
  ) then
    raise exception '[FAIL] C1/editar+comunicar: evento COMUNICADO com operation_id derivado ausente';
  end if;

  -- DESCOMUNICAR pela RPC dedicada.
  v_res := public.observacao_definir_comunicado(
    v_obs1, v_alfa, false, 2, v_pgest, 'f5b20000-0000-0000-0000-000000000005');
  v_ver := (v_res->>'version')::integer;
  if v_ver <> 3 or (v_res->>'evento') <> 'COMUNICACAO_REMOVIDA' then
    raise exception '[FAIL] C1/descomunicar: retorno inesperado (%)', v_res;
  end if;

  -- COMUNICAR de novo (para o teste de leitura SELF-comunicada).
  v_res := public.observacao_definir_comunicado(
    v_obs1, v_alfa, true, 3, v_pgest, 'f5b20000-0000-0000-0000-000000000006');
  v_ver := (v_res->>'version')::integer;
  if v_ver <> 4 or (v_res->>'evento') <> 'COMUNICADO' then
    raise exception '[FAIL] C1/comunicar: retorno inesperado (%)', v_res;
  end if;
  if not exists (
    select 1 from public.evaluation_observations o
     where o.id = v_obs1 and o.comunicado and o.comunicado_em is not null
       and o.comunicado_por_user_profile_id = v_pgest
       and o.comunicado_por_membership_id = v_mgest
  ) then
    raise exception '[FAIL] C1/comunicar: carimbo do comunicado nao e o ator/instante soberanos';
  end if;

  -- EXCLUSAO LOGICA com motivo.
  v_res := public.observacao_excluir(
    v_obs2, v_alfa, 'motivo ficticio da exclusao logica (P2)', 0,
    v_pgest, 'f5b20000-0000-0000-0000-000000000007');
  if not exists (
    select 1 from public.evaluation_observations o
     where o.id = v_obs2 and o.excluida and o.excluida_em is not null
       and o.excluida_por_user_profile_id = v_pgest
       and o.excluida_por_membership_id = v_mgest
       and o.motivo_exclusao = 'motivo ficticio da exclusao logica (P2)'
  ) then
    raise exception '[FAIL] C1/excluir: exclusao logica nao registrou ator/instante/motivo';
  end if;
  if not exists (
    select 1 from public.evaluation_observation_events e
     where e.observation_id = v_obs2 and e.event_type = 'EXCLUIDA'
       and e.reason = 'motivo ficticio da exclusao logica (P2)'
       and e.after_value->>'excluida' = 'true'
  ) then
    raise exception '[FAIL] C1/excluir: evento EXCLUIDA sem o motivo como `reason`';
  end if;

  -- Revogacao (desfaz a exclusao; a trilha preserva EXCLUIDA).
  v_res := public.observacao_revogar(
    v_obs2, v_alfa, 'motivo ficticio da revogacao (P2)', 1,
    v_pgest, 'f5b20000-0000-0000-0000-000000000008');
  if not exists (
    select 1 from public.evaluation_observations o
     where o.id = v_obs2 and not o.excluida and o.motivo_exclusao is null
       and o.excluida_por_user_profile_id is null
  ) then
    raise exception '[FAIL] C1/revogar: a revogacao nao desfez a exclusao logica';
  end if;
  if not exists (
    select 1 from public.evaluation_observation_events e
     where e.observation_id = v_obs2 and e.event_type = 'REVOGADA'
       and e.reason = 'motivo ficticio da revogacao (P2)'
  ) then
    raise exception '[FAIL] C1/revogar: evento REVOGADA ausente';
  end if;
  select count(*) into v_n from public.evaluation_observation_events
   where observation_id = v_obs2 and event_type = 'EXCLUIDA';
  if v_n <> 1 then
    raise exception '[FAIL] C1/revogar: a trilha perdeu o evento EXCLUIDA (% linhas)', v_n;
  end if;

  -- --------------------------------------------------------------------------
  -- (C2) IDEMPOTENCIA: replay identico devolve o MESMO resultado e nao duplica.
  -- --------------------------------------------------------------------------
  v_res := public.observacao_criar(
    v_alfa, v_cativo, v_csub, 'POSITIVA', 'observacao ficticia da P2 (c2)',
    v_pgest, 'f5b20000-0000-0000-0000-000000000001');
  if (v_res->>'observation_id')::uuid <> v_obs1 or coalesce((v_res->>'idempotente')::boolean, false) is not true then
    raise exception '[FAIL] C2: replay do create nao devolveu o MESMO resultado (%)', v_res;
  end if;
  v_res := public.observacao_editar(
    v_obs1, v_alfa, 'NEGATIVA', 'observacao ficticia da P2 (editada)', false, 0,
    v_pgest, 'f5b20000-0000-0000-0000-000000000003');
  if coalesce((v_res->>'idempotente')::boolean, false) is not true then
    raise exception '[FAIL] C2: replay da edicao nao foi idempotente (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_observation_events where observation_id = v_obs1;
  if v_n <> 6 then
    raise exception '[FAIL] C2: replays duplicaram eventos (% linhas, esperado 6: CRIADA, EDITADA, EDITADA+COMUNICADO, COMUNICACAO_REMOVIDA, COMUNICADO)', v_n;
  end if;
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, %L::uuid)',
           v_alfa, v_cativo, v_csub, 'POSITIVA', 'intencao DIFERENTE com o mesmo operation_id',
           v_pgest, 'f5b20000-0000-0000-0000-000000000001'),
    'P0001', 'intencao diferente', 'C2/replay com hash divergente');

  -- --------------------------------------------------------------------------
  -- (C3) NEGATIVOS de CRIACAO: D11 (matriz de estados do colaborador).
  -- --------------------------------------------------------------------------
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_cinat, 'NEUTRA', 'tentativa para colaborador inactive (P2)', v_pgest),
    'P0001', 'inactive (D11)', 'C3/criar inactive (D11)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csemst, 'NEUTRA', 'tentativa para colaborador sem status (P2)', v_pgest),
    'P0001', 'nao resolvido', 'C3/criar sem status vigente (fail-closed)');

  -- --------------------------------------------------------------------------
  -- (C4) NEGATIVOS de CRIACAO: relacao, SELF, cross-tenant e ciclo (D12).
  -- --------------------------------------------------------------------------
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_coutro, 'NEUTRA', 'tentativa fora da relacao (P2)', v_pgest),
    'P0001', 'DIRECT_REPORTS/DESCENDANTS', 'C4/criar fora da relacao');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_cgest, 'NEUTRA', 'tentativa SELF (P2)', v_pgest),
    'P0001', 'SELF', 'C4/criar SELF (avaliado nao cria sobre si)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_cbeta, 'NEUTRA', 'tentativa cross-tenant (P2)', v_pgest),
    'P0001', 'NOT_FOUND', 'C4/criar colaborador de outro tenant');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cbeta_c, v_csub, 'NEUTRA', 'tentativa com ciclo de outro tenant (P2)', v_pgest),
    'P0001', 'NOT_FOUND', 'C4/criar ciclo de outro tenant');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cplan, v_csub, 'NEUTRA', 'tentativa em ciclo PLANEJADO (P2)', v_pgest),
    'P0001', 'ciclo ATIVO', 'C4/criar em ciclo PLANEJADO');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cenc, v_csub, 'NEUTRA', 'tentativa em ciclo ENCERRADO (P2)', v_pgest),
    'P0001', 'ciclo ATIVO', 'C4/criar em ciclo ENCERRADO');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_ccanc, v_csub, 'NEUTRA', 'tentativa em ciclo CANCELADO (P2)', v_pgest),
    'P0001', 'ciclo ATIVO', 'C4/criar em ciclo CANCELADO');

  -- --------------------------------------------------------------------------
  -- (C5) NEGATIVOS de FORMA (D16) e de ator/tenant.
  -- --------------------------------------------------------------------------
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csub, 'NEUTRA', '', v_pgest),
    'P0001', 'texto obrigatorio', 'C5/texto vazio');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csub, 'NEUTRA', '   ', v_pgest),
    'P0001', 'texto obrigatorio', 'C5/texto so com espacos');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csub, 'NEUTRA', ' texto com bordas ', v_pgest),
    'P0001', 'bordas', 'C5/texto com espacos nas bordas');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csub, 'NEUTRA', repeat('a', 2001), v_pgest),
    'P0001', '2000', 'C5/texto > 2000 (D16)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csub, 'INVALIDA', 'tipo fora do dominio (P2)', v_pgest),
    'P0001', 'tipo', 'C5/tipo fora do dominio');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, null, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_csub, 'NEUTRA', 'sem ciclo (P2)', v_pgest),
    'P0001', 'obrigatorios', 'C5/forma sem ciclo');
  -- Perfil inativo e membership revogada: ator invalido => DENY (fail-closed).
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csub, 'NEUTRA', 'ator com perfil inativo (P2)', v_pperfil),
    'P0001', 'capability', 'C5/ator com perfil inativo');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csub, 'NEUTRA', 'ator com membership revogada (P2)', v_pmemb),
    'P0001', 'capability', 'C5/ator com membership revogada');
  -- F5-11 P5.1 (Issue #252): o ator ELEGIVEL (membership + perfil + vinculo ATIVOS)
  -- recebe AUTOMATICAMENTE o perfil de sistema `observacoes_avaliado` com
  -- `observation.read`. A ausencia de capability como MOTIVO de DENY permanece
  -- provada acima, pelos atores INELEGIVEIS (perfil inativo e membership
  -- revogada); aqui provamos o invariante NOVO — o ator que antes nao tinha
  -- concessao agora TEM a capability de leitura no resolver soberano (sem scope,
  -- como o contrato SELF exige).
  if not exists (
    select 1 from public.resolver_capabilities_efetivas(v_psemcap, v_alfa) c
     where c.capability_code = 'observation.read'
  ) then
    raise exception '[FAIL] C5: ator ELEGIVEL nao recebeu observation.read automaticamente (P5.1)';
  end if;

  -- --------------------------------------------------------------------------
  -- (C6) NEGATIVOS de MUTACAO: D5 (outro autor), D10 (stale), D8/D16 (motivo)
  --      e transicoes invalidas.
  -- --------------------------------------------------------------------------
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_editar(%L::uuid, %L::uuid, %L, %L, false, 4, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, 'NEUTRA', 'tentativa de outro autor (P2)', v_poutro),
    'P0001', 'autor', 'C6/editar por OUTRO autor do MESMO tenant (D5)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_definir_comunicado(%L::uuid, %L::uuid, false, 4, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, v_poutro),
    'P0001', 'autor', 'C6/comunicado por OUTRO autor (D5)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_excluir(%L::uuid, %L::uuid, %L, 4, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, 'tentativa de exclusao por outro autor (P2)', v_poutro),
    'P0001', 'autor', 'C6/excluir por OUTRO autor (D5)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_revogar(%L::uuid, %L::uuid, %L, 4, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, 'tentativa de revogacao por outro autor (P2)', v_poutro),
    'P0001', 'autor', 'C6/revogar por OUTRO autor (D5)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_editar(%L::uuid, %L::uuid, %L, %L, true, 0, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, 'NEUTRA', 'tentativa com versao obsoleta (P2)', v_pgest),
    'P0001', 'versao divergente', 'C6/editar com expected_version obsoleto (D10)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_excluir(%L::uuid, %L::uuid, null, 4, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, v_pgest),
    'P0001', 'motivo', 'C6/excluir sem motivo (D8/D16)');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_excluir(%L::uuid, %L::uuid, %L, 4, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, '   ', v_pgest),
    'P0001', 'motivo', 'C6/excluir com motivo vazio');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_revogar(%L::uuid, %L::uuid, %L, 4, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, 'revogacao de observacao nao excluida (P2)', v_pgest),
    'P0001', 'nao esta excluida', 'C6/revogar observacao nao excluida');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_definir_comunicado(%L::uuid, %L::uuid, true, 4, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, v_pgest),
    'P0001', 'ja esta no estado', 'C6/comunicar observacao ja comunicada (nenhum evento falso)');
  -- Observacao excluida nao aceita edicao.
  perform public.observacao_excluir(
    v_obs1, v_alfa, 'motivo ficticio para testar observacao excluida (P2)', 4,
    v_pgest, 'f5b20000-0000-0000-0000-000000000009');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_editar(%L::uuid, %L::uuid, %L, %L, true, 5, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, 'NEUTRA', 'edicao de observacao excluida (P2)', v_pgest),
    'P0001', 'excluida', 'C6/editar observacao excluida');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_definir_comunicado(%L::uuid, %L::uuid, false, 5, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, v_pgest),
    'P0001', 'excluida', 'C6/comunicar observacao excluida');
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_excluir(%L::uuid, %L::uuid, %L, 5, %L::uuid, gen_random_uuid())',
           v_obs1, v_alfa, 'segunda exclusao (P2)', v_pgest),
    'P0001', 'ja esta excluida', 'C6/excluir duas vezes');
  -- Devolve a observacao ao estado comunicado (para os testes de leitura).
  perform public.observacao_revogar(
    v_obs1, v_alfa, 'motivo ficticio da revogacao final (P2)', 5,
    v_pgest, 'f5b20000-0000-0000-0000-00000000000a');

  -- --------------------------------------------------------------------------
  -- (C7) GATE: operacao desconhecida e OVERRIDE DE IDENTIDADE (D3).
  -- --------------------------------------------------------------------------
  perform public._mut_f5_11_p2_neg(
    format('select public.f5_11_exigir_autorizacao_observacao(%L, %L::uuid, %L::uuid, %L::uuid, null)',
           'PUBLICAR', v_pgest, v_alfa, v_obs1),
    'P0001', 'desconhecida', 'C7/operacao desconhecida (allowlist fechada)');
  perform public._mut_f5_11_p2_neg(
    format('select public.f5_11_exigir_autorizacao_observacao(%L, %L::uuid, null, null, %L::uuid)',
           'CRIAR', v_pgest, v_csub),
    'P0001', 'organizacao obrigatoria', 'C7/gate sem organizacao');
  -- Identidade: com JWT presente (auth.uid()) o parametro NAO pode divergir.
  perform set_config('request.jwt.claim.sub', v_pgest::text, true);
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_pgest::text)::text, true);
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_alfa, v_cativo, v_csub, 'NEUTRA', 'tentativa de override de identidade (P2)', v_poutro),
    'P0001', 'diverge do ator informado', 'C7/override de identidade (auth.uid() manda)');
  -- E com o MESMO ator do JWT a operacao e' aceita (auth.uid() nao bloqueia o legitimo).
  v_res := public.observacao_criar(
    v_alfa, v_cativo, v_csub, 'NEUTRA', 'observacao ficticia com JWT coerente (P2)',
    v_pgest, 'f5b20000-0000-0000-0000-00000000000b');
  v_obs3 := (v_res->>'observation_id')::uuid;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
  if auth.uid() is not null then
    raise exception '[FAIL] C7: auth.uid() nao voltou a NULL apos o teste de override (%)', auth.uid();
  end if;
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_obter(%L::uuid, %L::uuid, %L::uuid)',
           v_obs1, v_alfa, v_poutro),
    'P0001', 'fora do escopo', 'C7/leitura sem relacao (OUTRO)');

  -- --------------------------------------------------------------------------
  -- (C8) LEITURA: obter, listar_por_escopo e historico.
  -- --------------------------------------------------------------------------
  v_res := public.observacao_obter(v_obs1, v_alfa, v_pgest);
  if (v_res->>'observation_id')::uuid <> v_obs1 or (v_res->>'version')::integer <> 6 then
    raise exception '[FAIL] C8/obter (autor): retorno inesperado (%)', v_res;
  end if;
  -- SELF-comunicada: o proprio colaborador alvo LE (D7/§8 linha 2).
  v_res := public.observacao_obter(v_obs1, v_alfa, v_psub);
  if (v_res->>'observation_id')::uuid <> v_obs1 then
    raise exception '[FAIL] C8/obter SELF-comunicada: retorno inesperado (%)', v_res;
  end if;
  -- SELF NAO le o que nao esta comunicado (v_obs3 nasce sem comunicado).
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_obter(%L::uuid, %L::uuid, %L::uuid)', v_obs3, v_alfa, v_psub),
    'P0001', 'fora do escopo', 'C8/SELF nao le observacao NAO comunicada');
  -- Cross-tenant: alvo de outro tenant => NOT_FOUND indistinguivel.
  insert into public.evaluation_observations (
    organization_id, collaborator_id, cycle_id, tipo, texto,
    author_user_profile_id, author_membership_id, author_collaborator_id, version)
  values (v_beta, v_cbeta, v_cbeta_c, 'NEUTRA', 'observacao ficticia de Beta (P2)',
          v_pbeta, 'f5b2d000-0000-0000-0000-0000000000b1', v_cbeta, 0)
  returning id into v_obs_beta;
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_obter(%L::uuid, %L::uuid, %L::uuid)', v_obs_beta, v_alfa, v_pgest),
    'P0001', 'NOT_FOUND', 'C8/obter alvo de outro tenant');

  -- listar_por_escopo: escopo fora da allowlist fechada.
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_listar_por_escopo(%L::uuid, %L::uuid, %L, null, null)',
           v_alfa, v_pgest, 'ORGANIZATION'),
    'P0001', 'allowlist fechada', 'C8/listar com escopo fora da allowlist');
  -- SELF: so' o comunicado e nao excluido (v_obs1 comunicado; v_obs3 nao).
  v_res := public.observacao_listar_por_escopo(v_alfa, v_psub, 'SELF', null, null);
  if (v_res->>'total')::integer <> 1 then
    raise exception '[FAIL] C8/listar SELF: esperava 1 observacao comunicada, veio % (%)',
      v_res->>'total', v_res;
  end if;
  -- DIRECT_REPORTS: os alvos do GESTOR (c2 e c3), nao excluidos.
  v_res := public.observacao_listar_por_escopo(v_alfa, v_pgest, 'DIRECT_REPORTS', null, null);
  if (v_res->>'total')::integer < 2 then
    raise exception '[FAIL] C8/listar DIRECT_REPORTS: esperava >= 2 observacoes dos alvos, veio %', v_res->>'total';
  end if;
  if (v_res->>'self_collaborator_id')::uuid <> v_cgest then
    raise exception '[FAIL] C8/listar: self_collaborator_id nao e o vinculo soberano do ator (%)', v_res;
  end if;
  v_res2 := public.observacao_listar_por_escopo(v_alfa, v_pgest, 'DESCENDANTS', null, null);
  if (v_res2->>'total')::integer < 2 then
    raise exception '[FAIL] C8/listar DESCENDANTS: esperava >= 2 observacoes, veio %', v_res2->>'total';
  end if;

  -- historico: a trilha NAO amplia alcance e preserva before/after.
  v_res := public.observacao_historico(v_obs1, v_alfa, v_pgest);
  if (v_res->>'total')::integer <> 8 then
    raise exception '[FAIL] C8/historico (autor): esperava 8 eventos, veio % (%)', v_res->>'total', v_res;
  end if;
  v_res := public.observacao_historico(v_obs1, v_alfa, v_psub);
  if (v_res->>'total')::integer <> 8 then
    raise exception '[FAIL] C8/historico (SELF-comunicada): esperava 8 eventos, veio %', v_res->>'total';
  end if;
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_historico(%L::uuid, %L::uuid, %L::uuid)', v_obs1, v_alfa, v_poutro),
    'P0001', 'fora do escopo', 'C8/historico sem visibilidade');

  -- --------------------------------------------------------------------------
  -- (C9) D11 na transicao de comunicado (marcar exige != inactive).
  -- --------------------------------------------------------------------------
  -- Observacao sobre o colaborador `inactive` inserida DIRETAMENTE na fixture
  -- (a criacao por RPC e' proibida pelo D11) para provar a regra de COMUNICAR.
  insert into public.evaluation_observations (
    organization_id, collaborator_id, cycle_id, tipo, texto,
    author_user_profile_id, author_membership_id, author_collaborator_id, version)
  values (v_alfa, v_cinat, v_cativo, 'NEUTRA', 'observacao ficticia de colaborador inactive (P2)',
          v_pgest, v_mgest, v_cgest, 0)
  returning id into v_obs_inat;
  perform public._mut_f5_11_p2_neg(
    format('select public.observacao_definir_comunicado(%L::uuid, %L::uuid, true, 0, %L::uuid, gen_random_uuid())',
           v_obs_inat, v_alfa, v_pgest),
    'P0001', 'inactive (D11)', 'C9/comunicar colaborador inactive (D11)');

  raise notice '[PASS] C/matriz funcional (concessao transitoria): criar (active e leave), editar, comunicar, descomunicar, excluir e revogar com version+1, eventos e before/after coerentes; idempotencia dupla (replay identico devolve o mesmo e nao duplica; hash divergente => CONFLICT); D11 (active/leave permitem; inactive e status nao resolvido negam; comunicar inactive nega), D12 (PLANEJADO/ENCERRADO/CANCELADO negam; ATIVO permite), D5 (outro autor nega nas 4 mutacoes), D10 (stale negado), D16 (texto vazio/bordas/>2000 e motivo ausente negados), relacao/SELF/cross-tenant/capability/perfil inativo/membership revogada negados, operacao desconhecida negada, override de identidade negado por auth.uid(); leitura (autor, relacao, SELF-comunicada, listar por escopo e historico); NENHUM negativo persistiu linha ou evento';
end $$;

-- ----------------------------------------------------------------------------
-- (C10) ATOMICIDADE: falha injetada na trilha => rollback TOTAL (linha + evento)
-- ----------------------------------------------------------------------------
-- O gatilho de injecao e' artefato de FIXTURE (prefixo `_mut_`), criado e
-- removido DENTRO da transacao desfeita — nunca persiste (bloco E prova).
create or replace function public._mut_f5_11_p2_falha()
returns trigger
language plpgsql
as $fn$
begin
  raise exception 'falha injetada na trilha (P2)';
end;
$fn$;

create trigger _mut_f5_11_p2_falha_trg
  before insert on public.evaluation_observation_events
  for each row execute function public._mut_f5_11_p2_falha();

do $$
declare
  v_st  text;
  v_msg text;
  v_n   int;
begin
  begin
    perform public.observacao_criar(
      'f5b2a000-0000-0000-0000-0000000000a1', 'f5b21000-0000-0000-0000-0000000000a1',
      'f5b2e000-0000-0000-0000-0000000000c2', 'NEUTRA', 'observacao com falha injetada (P2)',
      'f5b2c000-0000-0000-0000-0000000000a1', 'f5b20000-0000-0000-0000-00000000000c');
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is null or position('falha injetada' in coalesce(v_msg, '')) = 0 then
    raise exception '[FAIL] C10: a falha injetada na trilha nao abortou a operacao (% / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;
  select count(*) into v_n from public.evaluation_observations
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and texto = 'observacao com falha injetada (P2)';
  if v_n <> 0 then
    raise exception '[FAIL] C10: a observacao PERSISTIU apesar da falha na trilha (% linhas) - atomicidade violada', v_n;
  end if;

  raise notice '[PASS] C10/atomicidade: a falha injetada na trilha aborta a operacao e NENHUMA observacao persiste (linha e evento na MESMA transacao)';
end $$;

drop trigger _mut_f5_11_p2_falha_trg on public.evaluation_observation_events;
drop function public._mut_f5_11_p2_falha();

-- ----------------------------------------------------------------------------
-- (C11) NAO PERSISTENCIA DOS NEGATIVOS: as contagens fecham com o previsto
-- ----------------------------------------------------------------------------
-- Observacoes: v_obs1, v_obs2 e v_obs3 (via RPC) + a de Beta e a do colaborador
-- inativo (fixtures diretas) = 5. Eventos: 8 + 3 + 1 = 12. Qualquer negativo que
-- tivesse persistido (linha OU evento) quebraria estas contagens.
do $$
declare
  v_n int;
begin
  select count(*) into v_n from public.evaluation_observations
   where organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                             'f5b2a000-0000-0000-0000-0000000000b1');
  if v_n <> 5 then
    raise exception '[FAIL] C11: observacoes persistidas = % (esperado 5: 3 via RPC + 2 fixtures diretas); algum negativo persistiu', v_n;
  end if;
  select count(*) into v_n from public.evaluation_observation_events
   where organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                             'f5b2a000-0000-0000-0000-0000000000b1');
  if v_n <> 12 then
    raise exception '[FAIL] C11: eventos persistidos = % (esperado 12); algum negativo gerou evento', v_n;
  end if;
  select count(*) into v_n from public.evaluation_observation_events e
   where e.organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                               'f5b2a000-0000-0000-0000-0000000000b1')
     and e.operation_id not in (
       'f5b20000-0000-0000-0000-000000000001',
       'f5b20000-0000-0000-0000-000000000002',
       'f5b20000-0000-0000-0000-000000000003',
       'f5b20000-0000-0000-0000-000000000004',
       'f5b20000-0000-0000-0000-000000000005',
       'f5b20000-0000-0000-0000-000000000006',
       'f5b20000-0000-0000-0000-000000000007',
       'f5b20000-0000-0000-0000-000000000008',
       'f5b20000-0000-0000-0000-000000000009',
       'f5b20000-0000-0000-0000-00000000000a',
       'f5b20000-0000-0000-0000-00000000000b')
     and e.event_type not in ('COMUNICADO', 'COMUNICACAO_REMOVIDA');
  if v_n <> 0 then
    raise exception '[FAIL] C11: % evento(s) com operation_id nao previsto (tentativa recusada gerou evento)', v_n;
  end if;

  raise notice '[PASS] C11/nao persistencia: os negativos do bloco C NAO deixaram observacao nem evento — a superficie persistida fecha exatamente nas 5 observacoes e 12 eventos previstos';
end $$;

drop function public._mut_f5_11_p2_neg(text, text, text, text);

rollback;

-- ============================================================================
-- D) POS-ROLLBACK: nada persistiu (D15 intacto, zero residuo da fixture de teste)
-- ============================================================================
do $$
declare
  v_n int;
  v_roles text;
begin
  -- F5-11 P3 (Issue #246) + P5.1 (Issue #252): o catalogo JA tem as 4 concessoes
  -- LEGITIMAS do perfil `observacoes_gestor` (P3) e a de LEITURA do perfil SELF
  -- `observacoes_avaliado` (P5.1). O que este bloco prova e' que a concessao
  -- TRANSITORIA da fixture NAO persistiu: nenhuma concessao fora da LISTA FECHADA
  -- de pares (role, capability) e nenhuma role/assignment/scope de teste.
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
    join public.access_roles r on r.id = rc.access_role_id
   where c.code like 'observation.%'
     and (r.is_system is not true
          or (r.name, c.code) not in (
            ('observacoes_gestor', 'observation.read'),
            ('observacoes_gestor', 'observation.create'),
            ('observacoes_gestor', 'observation.edit'),
            ('observacoes_gestor', 'observation.delete'),
            ('observacoes_avaliado', 'observation.read')
          ));
  if v_n <> 0 then
    raise exception '[FAIL] D1: a concessao TRANSITORIA persistiu (% concessao(oes) de observation.* fora da lista fechada)', v_n;
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 5 then
    raise exception '[FAIL] D1: observation.* no catalogo = % (esperado 5: 4 em observacoes_gestor + 1 em observacoes_avaliado)', v_n;
  end if;
  select count(*) into v_n from public.access_roles
   where id = 'f5b29000-0000-0000-0000-0000000000f1';
  if v_n <> 0 then
    raise exception '[FAIL] D2: a role de fixture persistiu';
  end if;
  select count(*) into v_n from public.evaluation_observations
   where organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                             'f5b2a000-0000-0000-0000-0000000000b1');
  if v_n <> 0 then
    raise exception '[FAIL] D3: o bloco transitorio deixou % observacao(oes) persistida(s)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_observation_events
   where organization_id in ('f5b2a000-0000-0000-0000-0000000000a1',
                             'f5b2a000-0000-0000-0000-0000000000b1');
  if v_n <> 0 then
    raise exception '[FAIL] D4: o bloco transitorio deixou % evento(s) persistido(s)', v_n;
  end if;
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    raise exception '[FAIL] D5: bundle admin com % capabilities (esperado 9)', v_n;
  end if;
  select array_to_string(array_agg(r.name order by r.name), ',') into v_roles
    from public.access_roles r where r.is_system = true;
  if v_roles <> 'admin,evaluator,metas_aprovador,metas_dono,observacoes_avaliado,observacoes_gestor' then
    raise exception '[FAIL] D6: roles de sistema = % (esperado admin,evaluator,metas_aprovador,metas_dono,observacoes_avaliado,observacoes_gestor)', v_roles;
  end if;

  raise notice '[PASS] D/pos-rollback: a fixture transitoria NAO persistiu — nenhuma concessao fora da lista fechada (4 em observacoes_gestor + 1 em observacoes_avaliado), nenhuma role de teste, ZERO observacao/evento, admin com 9 e sem observation.*: o estado entregue pela P2 e EXATAMENTE o estado de producao (DENY ate a P3 para o gestor; SELF pela P5.1)' ;
end $$;

-- ============================================================================
-- E) HIGIENE final
-- ============================================================================
do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] E: % funcao(oes) temporaria(s) `_mut_*` residual(is)', v_n;
  end if;
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'S' and c.relname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] E: % sequence(s) temporaria(s) `_mut_*` residual(is)', v_n;
  end if;
  select count(*) into v_n from pg_trigger t where t.tgname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] E: % gatilho(s) temporario(s) `_mut_*` residual(is)', v_n;
  end if;

  raise notice '[PASS] E/higiene: nenhum residuo de prova no schema';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-11 P2 (Issue #244): RPCs soberanas observacao_* VALIDADAS.';
  raise notice '  A superficie e EXATAMENTE a lista fechada (8 RPCs + 6 helpers);';
  raise notice '  o gate funcional aplica capability + D5 + D11 + D12 + relacao;';
  raise notice '  concorrencia por version + row lock (SEM advisory lock);';
  raise notice '  eventos na MESMA transacao (D6) e rollback total comprovados;';
  raise notice '  D4/D6/D9 e a P1.1 intactos; catalogo 31; admin SEM observation.*;';
  raise notice '  ZERO concessao de FIXTURE do cenario; D15 vigente apos a emenda da P5.1';
  raise notice '  (6 roles de sistema; 4 concessoes de gestao + 1 SELF automatica aos elegiveis; admin ZERO).';
  raise notice '============================================================';
end $$;
