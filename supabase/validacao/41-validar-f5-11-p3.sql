-- ============================================================================
-- F5-11 P3 (Issue #246): VALIDADOR da AUTORIZACAO/CONCESSAO/SCOPE soberanos
-- Saida: [PASS]/[FAIL]; falha aborta (ON_ERROR_STOP).
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de:
--   supabase/validacao/40-cenario-f5-11-p3.sql   (fixture + concessao)
--   supabase/validacao/41-validar-f5-11-p3.sql   (este arquivo)
--
-- Contrato coberto (docs/F5-11-desenho-tecnico.md; D1-D16; §8; §17.1 P3; §21):
--   A  inventario factual: perfil `observacoes_gestor` com EXATAMENTE as 4
--      capabilities; `admin` com 9 e ZERO observation.*; `metas_*` exclusivas de
--      metas; `observation.write` deprecada e nao concedida; catalogo 31;
--      concessao/scope da fixture; RLS/ACL e EXECUTE intactos;
--   B  DENY SEM GRANT (tenant alheio / sem assignment): capability ausente;
--   C  DENY COM CAPABILITY MAS **SEM SCOPE** — e a prova de que o scope (e nao a
--      capability) foi o motivo: o resolver SEM scope devolve a capability e o
--      resolver ESCOPADO devolve vazio;
--   D  DENY COM SCOPE INCOMPATIVEL (ORGANIZATION / SELF) para operacoes de
--      gestao — o scope existe, mas nao satisfaz o bundle;
--   E  ALLOW com scope DIRECT_REPORTS: criar/editar/comunicar/descomunicar/
--      excluir/revogar/obter/historico sobre subordinado DIRETO, com eventos;
--   F  DIRECTO x DESCENDENTE: o ator com DIRECT_REPORTS NAO alcanca o
--      descendente e o ator com DESCENDANTS alcanca;
--   G  a RELACAO estrutural continua obrigatoria mesmo com scope de gestao;
--   H  SELF: leitura da PROPRIA comunicada pela regra especifica do dominio
--      (sem scope de gestao), negada para nao comunicada, e listagem SELF;
--   I  cross-tenant / IDOR: alvo de outro tenant e id inexistente =>
--      NOT_FOUND indistinguivel; escopo fora da allowlist => INVALID_INPUT;
--   J  `observation.write` NAO e concedivel (trigger da F5-04) e segue deprecada;
--   K  RLS/ACL coerentes (ZERO policy, cliente 42501), D4/D6/D9 e P1.1 intactos;
--   L  higiene final.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- A) INVENTARIO / PREFLIGHT fail-closed
-- ============================================================================
do $$
declare
  v_falhas text[] := array[]::text[];
  v_role   uuid;
  v_fn     text;
  v_tab    text;
  v_n      integer;
  v_escopo text;
begin
  -- (A1) perfil de sistema com EXATAMENTE as 4 capabilities canonicas.
  select id into v_role
    from public.access_roles
   where name = 'observacoes_gestor' and is_system = true
     and organization_id is null and status = 'active';
  if v_role is null then
    v_falhas := v_falhas || 'perfil de sistema observacoes_gestor ausente/inativo/com organizacao';
  else
    select count(*) into v_n from public.access_role_capabilities where access_role_id = v_role;
    if v_n <> 4 then
      v_falhas := v_falhas || format('observacoes_gestor com %s capabilities (esperado 4)', v_n);
    end if;
    select count(*) into v_n
      from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where m.access_role_id = v_role
       and c.code in ('observation.read', 'observation.create',
                      'observation.edit', 'observation.delete');
    if v_n <> 4 then
      v_falhas := v_falhas || 'observacoes_gestor nao tem as 4 capabilities canonicas exatas';
    end if;
  end if;

  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 4 then
    v_falhas := v_falhas || format('%s concessao(oes) de observation.* (esperado 4)', v_n);
  end if;

  -- (A2) admin com 9 e ZERO observation.*.
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    v_falhas := v_falhas || format('bundle admin com %s capabilities (esperado 9)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
     and c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || 'admin com observation.*';
  end if;

  -- (A3) metas_* exclusivas de metas.
  foreach v_fn in array array['metas_dono', 'metas_aprovador'] loop
    select count(*) into v_n
      from public.access_role_capabilities m
      join public.access_roles r on r.id = m.access_role_id
     where r.name = v_fn and r.is_system = true;
    if v_n <> 2 then
      v_falhas := v_falhas || format('%s com %s capabilities (esperado 2)', v_fn, v_n);
    end if;
    if exists (
      select 1 from public.access_role_capabilities m
        join public.access_roles r on r.id = m.access_role_id
        join public.capabilities c on c.id = m.capability_id
       where r.name = v_fn and c.code like 'observation.%'
    ) then
      v_falhas := v_falhas || (v_fn || ' com observation.*');
    end if;
  end loop;

  -- (A4) observation.write deprecada e nao concedida; catalogo 31.
  if not exists (select 1 from public.capabilities where code = 'observation.write' and deprecated = true) then
    v_falhas := v_falhas || 'observation.write nao esta deprecada';
  end if;
  if exists (
    select 1 from public.access_role_capabilities m
      join public.capabilities c on c.id = m.capability_id
     where c.code = 'observation.write'
  ) then
    v_falhas := v_falhas || 'observation.write concedida a uma role';
  end if;
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo com %s codigos (esperado 31)', v_n);
  end if;

  -- (A5) fixture da P3 presente: assignments + scopes nos tipos esperados.
  select count(*) into v_n from public.membership_access_role_assignments a
    join public.access_roles r on r.id = a.access_role_id
   where r.name = 'observacoes_gestor' and a.status = 'active';
  if v_n <> 5 then
    v_falhas := v_falhas || format('assignments de observacoes_gestor = %s (esperado 5)', v_n);
  end if;
  for v_escopo in select unnest(array['DIRECT_REPORTS', 'DESCENDANTS', 'ORGANIZATION', 'SELF']) loop
    select count(*) into v_n
      from public.access_role_assignment_scopes s
      join public.membership_access_role_assignments a on a.id = s.assignment_id
      join public.access_roles r on r.id = a.access_role_id
     where r.name = 'observacoes_gestor' and s.scope_type = v_escopo and s.status = 'active';
    if v_n <> 1 then
      v_falhas := v_falhas || format('scope %s da fixture = %s (esperado 1)', v_escopo, v_n);
    end if;
  end loop;

  -- (A6) superficie: 8 RPCs + helpers INVOKER com search_path fixo e EXECUTE so
  --      service_role; RLS ligada com ZERO policy e ZERO privilegio de cliente.
  foreach v_fn in array array[
    'observacao_criar(uuid, uuid, uuid, text, text, uuid, uuid)',
    'observacao_editar(uuid, uuid, text, text, boolean, integer, uuid, uuid)',
    'observacao_definir_comunicado(uuid, uuid, boolean, integer, uuid, uuid)',
    'observacao_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_revogar(uuid, uuid, text, integer, uuid, uuid)',
    'observacao_obter(uuid, uuid, uuid)',
    'observacao_listar_por_escopo(uuid, uuid, text, uuid, timestamptz)',
    'observacao_historico(uuid, uuid, uuid)',
    'f5_11_ator_tem_escopo_observacao(uuid, uuid, text, text[])',
    'f5_11_exigir_autorizacao_observacao(text, uuid, uuid, uuid, uuid)'] loop
    if to_regprocedure('public.' || v_fn) is null then
      v_falhas := v_falhas || ('funcao ausente: ' || v_fn);
      continue;
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_falhas := v_falhas || ('sem EXECUTE para service_role: ' || v_fn);
    end if;
    if has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE') then
      v_falhas := v_falhas || ('EXECUTE exposto a anon/authenticated: ' || v_fn);
    end if;
  end loop;
  foreach v_tab in array array['evaluation_observations', 'evaluation_observation_events'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      v_falhas := v_falhas || ('RLS desabilitada: ' || v_tab);
    end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = v_tab) then
      v_falhas := v_falhas || ('policy indevida (o RLS da P3 e o DENY-BY-DEFAULT da P1): ' || v_tab);
    end if;
    if has_table_privilege('authenticated', 'public.' || v_tab, 'SELECT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || v_tab, 'UPDATE')
       or has_table_privilege('anon', 'public.' || v_tab, 'SELECT') then
      v_falhas := v_falhas || ('privilegio de cliente aberto em ' || v_tab);
    end if;
  end loop;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] A/preflight F5-11 P3: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] A/inventario: perfil de sistema `observacoes_gestor` com EXATAMENTE as 4 capabilities canonicas (read/create/edit/delete) e UNICA role com observation.*; `admin` com 9 e ZERO observation.*; `metas_dono`/`metas_aprovador` com exatamente 2 capabilities de metas cada e sem observation.*; `observation.write` DEPRECADA e nao concedida; catalogo 31; fixture com 5 assignments e 4 scopes (DIRECT_REPORTS/DESCENDANTS/ORGANIZATION/SELF); 8 RPCs + helpers INVOKER com EXECUTE SO service_role; RLS ligada, ZERO policy e ZERO privilegio de cliente';
end $$;

-- ============================================================================
-- B/D/H) NEGATIVOS de autorizacao (somente leitura; sem transacao)
-- ============================================================================
do $$
declare
  v_org    constant uuid := 'f5b2a000-0000-0000-0000-0000000000a1';
  v_ciclo  constant uuid := 'f5b21000-0000-0000-0000-0000000000a1';
  v_gestor constant uuid := 'f5b2c000-0000-0000-0000-0000000000a1';
  v_outro  constant uuid := 'f5b2c000-0000-0000-0000-0000000000a2';
  v_semcap constant uuid := 'f5b2c000-0000-0000-0000-0000000000a3';
  v_neto_p constant uuid := 'f5b3c000-0000-0000-0000-0000000000a1';
  v_beta   constant uuid := 'f5b2c000-0000-0000-0000-0000000000b1';
  v_csub   constant uuid := 'f5b2e000-0000-0000-0000-0000000000c2';
  v_cneto  constant uuid := 'f5b3e000-0000-0000-0000-0000000000c1';
  v_cfora  constant uuid := 'f5b2e000-0000-0000-0000-0000000000c5';
  v_n      integer;
  v_st     text;
  v_msg    text;
  v_res    jsonb;
begin
  -- (B) SEM GRANT: ator de outro tenant (nenhum assignment) => capability ausente.
  begin
    perform public.observacao_criar(v_org, v_ciclo, v_csub, 'NEUTRA',
      'tentativa sem grant (P3)', v_beta, gen_random_uuid());
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('capability' in v_msg) = 0 then
    raise exception '[FAIL] B: sem grant deveria ser DENY por capability (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;
  -- prova no resolver: nem sem scope nem com scope o ator alheio tem a capability.
  select count(*) into v_n
    from public.resolver_capabilities_efetivas(v_beta, v_org) c
   where c.capability_code like 'observation.%';
  if v_n <> 0 then
    raise exception '[FAIL] B: ator de outro tenant resolveu capability de observacao (% linhas)', v_n;
  end if;

  -- (C) CAPABILITY **SEM SCOPE**: o ator OUTRO tem a capability (resolver SEM
  --     scope) e NAO tem scope ativo (resolver ESCOPADO vazio) => a recusa e
  --     atribuivel ao SCOPE, nao a capability.
  select count(*) into v_n
    from public.resolver_capabilities_efetivas(v_outro, v_org) c
   where c.capability_code = 'observation.create';
  if v_n = 0 then
    raise exception '[FAIL] C: premissa invalida — o ator sem scope deveria TER a capability pelo resolver sem scope';
  end if;
  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(v_outro, v_org) c
   where c.capability_code = 'observation.create';
  if v_n <> 0 then
    raise exception '[FAIL] C: premissa invalida — o ator sem scope nao deveria resolver nada no resolver escopado (%)', v_n;
  end if;
  begin
    perform public.observacao_criar(v_org, v_ciclo, v_csub, 'NEUTRA',
      'tentativa com capability e sem scope (P3)', v_outro, gen_random_uuid());
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('scope de gestao' in v_msg) = 0 then
    raise exception '[FAIL] C: capability sem SCOPE deveria ser DENY por scope (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  -- (D) SCOPE INCOMPATIVEL (ORGANIZATION): existe scope ativo, mas fora do bundle.
  select count(*) into v_n
    from public.resolver_capabilities_escopos_efetivas(v_semcap, v_org) c
   where c.capability_code = 'observation.create' and c.scope_type = 'ORGANIZATION';
  if v_n <> 1 then
    raise exception '[FAIL] D: premissa invalida — o ator com scope ORGANIZATION deveria resolve-lo (%)', v_n;
  end if;
  begin
    perform public.observacao_criar(v_org, v_ciclo, v_csub, 'NEUTRA',
      'tentativa com scope incompativel (P3)', v_semcap, gen_random_uuid());
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('scope de gestao' in v_msg) = 0 then
    raise exception '[FAIL] D: scope ORGANIZATION deveria ser DENY (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  -- (H) SELF: o NETO (scope SELF) NAO tem relacao com ninguem; pela regra do
  --     dominio ele LE a propria COMUNICADA e NAO le a nao comunicada.
  begin
    perform public.observacao_obter(
      (select id from public.evaluation_observations
        where organization_id = v_org and collaborator_id = v_cneto and comunicado
        order by created_at limit 1), v_org, v_neto_p);
    v_st := null;
  exception when others then v_st := sqlstate;
  end;
  if v_st is not null then
    raise exception '[FAIL] H: a leitura SELF-comunicada deveria ser PERMITIDA (veio %)', v_st;
  end if;
  begin
    perform public.observacao_obter(
      (select id from public.evaluation_observations
        where organization_id = v_org and collaborator_id = v_cneto and not comunicado
        order by created_at limit 1), v_org, v_neto_p);
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  -- SELF SEM scope de gestao: a UNICA leitura SELF autorizada por norma e' a
  -- comunicada (provada acima). Qualquer outra e' negada pelo SCOPE — fail-closed,
  -- porque o bundle padrao nao carrega scope SELF.
  if v_st is distinct from 'P0001' or v_msg is null or position('scope de gestao' in v_msg) = 0 then
    raise exception '[FAIL] H: SELF sem scope de gestao deveria ser DENY por SCOPE na leitura NAO comunicada (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  -- (H2) DISCRIMINANTE (separacao de mecanismos): ator COM scope de gestao
  --      (SUB_ATIVO, DESCENDANTS) lendo uma observacao de colaborador FORA da sua
  --      relacao e da qual NAO e' autor (o alvo e' o colaborador c5, autor = GESTOR)
  --      => o SCOPE passa e a recusa vem da regra de VISIBILIDADE/RELACAO.
  begin
    perform public.observacao_obter(
      (select id from public.evaluation_observations
        where organization_id = v_org and collaborator_id = v_cfora
        order by created_at limit 1),
      v_org, 'f5b2c000-0000-0000-0000-0000000000a6');
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('fora do escopo' in v_msg) = 0 then
    raise exception '[FAIL] H2: ator COM scope de gestao e SEM relacao deveria ser DENY por VISIBILIDADE/RELACAO (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;
  -- SELF na listagem: permitido e devolve SOMENTE a comunicada (1 item).
  if (public.observacao_listar_por_escopo(v_org, v_neto_p, 'SELF', null, null)->>'total')::int <> 1 then
    raise exception '[FAIL] H: listagem SELF do neto deveria devolver 1 (a comunicada)';
  end if;
  -- E o SELF NAO lista escopo de GESTAO (scope SELF nao satisfaz o bundle).
  begin
    perform public.observacao_listar_por_escopo(v_org, v_neto_p, 'DIRECT_REPORTS', null, null);
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('scope de gestao' in v_msg) = 0 then
    raise exception '[FAIL] H: listagem de GESTAO com scope SELF deveria ser DENY (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  -- (G) mesmo COM scope de gestao, a RELACAO continua obrigatoria: o GESTOR
  --     (DIRECT_REPORTS) nao edita a observacao do colaborador fora da relacao.
  begin
    perform public.observacao_editar(
      (select id from public.evaluation_observations
        where organization_id = v_org and collaborator_id = v_cfora
        order by created_at limit 1),
      v_org, 'NEUTRA', 'tentativa com scope mas sem relacao (P3)', false, 0,
      v_gestor, gen_random_uuid());
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null
     or (position('relacao vigente' in v_msg) = 0 and position('DIRECT_REPORTS/DESCENDANTS' in v_msg) = 0) then
    raise exception '[FAIL] G: scope NAO substitui a RELACAO (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  -- (F) SCOPE x RELACAO — SEMANTICA FORMAL (D15/§8), SEM alterar a arquitetura:
  --     * `DIRECT_REPORTS` e `DESCENDANTS` sao os DOIS scopes validos da concessao
  --       de `observation.*`;
  --     * o scope participa OBRIGATORIAMENTE do enforcement do GRANT (o gate exige
  --       um grant com um desses tipos — provado nos blocos C e D);
  --     * o scope NAO redefine nem estreita a RELACAO FUNCIONAL do dominio;
  --     * a relacao autorizavel permanece DIRECT_REPORTS UNIAO DESCENDANTS (§8/D15);
  --     * logo, grant valido `DIRECT_REPORTS` + relacao valida de DESCENDANT
  --       produz ALLOW: o ALCANCE vem da RELACAO, nunca do tipo do scope;
  --     * e grant valido SEM qualquer relacao da uniao continua DENY
  --       (provado nos blocos G e H2).
  v_res := public.observacao_criar(
    v_org, v_ciclo, v_cneto, 'NEUTRA',
    'observacao ficticia da P3 (grant DIRECT_REPORTS + relacao DESCENDANT)',
    v_gestor, 'bbbb0000-0000-0000-0000-000000000017');
  if (v_res->>'observation_id') is null then
    raise exception '[FAIL] F: grant valido DIRECT_REPORTS + relacao DESCENDANTS deveria ser ALLOW (%)', v_res;
  end if;

  -- (I) escopo fora da allowlist => INVALID_INPUT (ORGANIZATION nao e' bundle).
  begin
    perform public.observacao_listar_por_escopo(v_org, v_gestor, 'ORGANIZATION', null, null);
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('allowlist fechada' in v_msg) = 0 then
    raise exception '[FAIL] I: escopo ORGANIZATION deveria ser INVALID_INPUT (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  -- (I) IDOR / cross-tenant: observacao inexistente e ciclo de outro tenant.
  begin
    perform public.observacao_obter(gen_random_uuid(), v_org, v_gestor);
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('NOT_FOUND' in v_msg) = 0 then
    raise exception '[FAIL] I: id inexistente deveria ser NOT_FOUND (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;
  begin
    perform public.observacao_criar(v_org, 'f5b21000-0000-0000-0000-0000000000b1', v_csub, 'NEUTRA',
      'tentativa com ciclo de outro tenant (P3)', v_gestor, gen_random_uuid());
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('NOT_FOUND' in v_msg) = 0 then
    raise exception '[FAIL] I: ciclo de outro tenant deveria ser NOT_FOUND (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  -- (J) `observation.write` NAO e concedivel: a associacao a role e' recusada
  --     pelo trigger da F5-04 (capability deprecada) — prova ESTRUTURAL.
  begin
    insert into public.access_role_capabilities (access_role_id, capability_id)
    select 'c0000000-0000-4000-8000-0000000000f1', c.id
      from public.capabilities c where c.code = 'observation.write';
    v_st := null; v_msg := null;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  if v_st is distinct from 'P0001' or v_msg is null or position('deprecada' in v_msg) = 0 then
    raise exception '[FAIL] J: observation.write deveria ser NAO-CONCEDIVEL (veio % / %)',
      coalesce(v_st, 'sem erro'), coalesce(v_msg, '<nula>');
  end if;

  select count(*) into v_n from public.evaluation_observations
   where organization_id = v_org and texto like 'tentativa%P3%';
  if v_n <> 0 then
    raise exception '[FAIL] K: os negativos de autorizacao PERSISTIRAM linha (% observacoes)', v_n;
  end if;

  raise notice '[PASS] B/D/H/I/J/K/negativos: sem grant => DENY por capability (e resolver vazio); com capability mas SEM SCOPE => DENY por SCOPE com a prova de atribuicao (resolver sem scope resolve, resolver escopado nao); com scope incompativel (ORGANIZATION/SELF) => DENY; SELF-comunicada PERMITIDA pela regra do dominio e negada para nao comunicada; a RELACAO estrutural continua obrigatoria mesmo com scope; grant valido DIRECT_REPORTS + relacao de DESCENDANT e ALLOW (o ALCANCE vem da RELACAO, nao do tipo do scope); escopo fora da allowlist => INVALID_INPUT; id inexistente e ciclo de outro tenant => NOT_FOUND; observation.write NAO-CONCEDIVEL por trigger; NENHUM negativo persistiu linha';
end $$;

-- ============================================================================
-- E/F) POSITIVOS (transacao desfeita: as mutacoes de prova nao persistem)
-- ============================================================================
begin;

create or replace function public._mut_f5_11_p3_neg(
  p_sql text, p_state text, p_trecho text, p_rotulo text
)
returns void
language plpgsql
as $$
declare
  v_st text; v_msg text;
begin
  begin
    execute p_sql;
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
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
  v_org    constant uuid := 'f5b2a000-0000-0000-0000-0000000000a1';
  v_ciclo  constant uuid := 'f5b21000-0000-0000-0000-0000000000a1';
  v_gestor constant uuid := 'f5b2c000-0000-0000-0000-0000000000a1';
  v_sub    constant uuid := 'f5b2c000-0000-0000-0000-0000000000a6';
  v_csub   constant uuid := 'f5b2e000-0000-0000-0000-0000000000c2';
  v_cneto  constant uuid := 'f5b3e000-0000-0000-0000-0000000000c1';
  v_res    jsonb;
  v_obs    uuid;
  v_ver    integer;
  v_n      integer;
begin
  -- (E) ALLOW com DIRECT_REPORTS sobre o subordinado DIRETO.
  v_res := public.observacao_criar(
    v_org, v_ciclo, v_csub, 'POSITIVA', 'observacao ficticia da P3 (ALLOW direct)',
    v_gestor, 'bbbb0000-0000-0000-0000-000000000010');
  v_obs := (v_res->>'observation_id')::uuid;
  if v_obs is null then
    raise exception '[FAIL] E: criar com scope DIRECT_REPORTS falhou (%)', v_res;
  end if;
  select version into v_ver from public.evaluation_observations where id = v_obs;

  v_res := public.observacao_editar(
    v_obs, v_org, 'NEGATIVA', 'observacao ficticia da P3 (ALLOW direct, editada)', false, v_ver,
    v_gestor, 'bbbb0000-0000-0000-0000-000000000011');
  v_ver := (v_res->>'version')::integer;

  v_res := public.observacao_definir_comunicado(
    v_obs, v_org, true, v_ver, v_gestor, 'bbbb0000-0000-0000-0000-000000000012');
  v_ver := (v_res->>'version')::integer;

  v_res := public.observacao_definir_comunicado(
    v_obs, v_org, false, v_ver, v_gestor, 'bbbb0000-0000-0000-0000-000000000013');
  v_ver := (v_res->>'version')::integer;

  -- leitura (autor + relacao, com scope) e historico.
  perform public.observacao_obter(v_obs, v_org, v_gestor);
  if (public.observacao_historico(v_obs, v_org, v_gestor)->>'total')::int < 4 then
    raise exception '[FAIL] E: historico deveria ter >= 4 eventos';
  end if;

  v_res := public.observacao_excluir(
    v_obs, v_org, 'motivo ficticio da P3 (ALLOW direct)', v_ver,
    v_gestor, 'bbbb0000-0000-0000-0000-000000000014');
  v_ver := (v_res->>'version')::integer;
  v_res := public.observacao_revogar(
    v_obs, v_org, 'motivo ficticio da revogacao P3', v_ver,
    v_gestor, 'bbbb0000-0000-0000-0000-000000000015');

  -- (F) ALLOW com DESCENDANTS sobre o NETO (o SUB e' gestor do neto).
  v_res := public.observacao_criar(
    v_org, v_ciclo, v_cneto, 'NEUTRA', 'observacao ficticia da P3 (ALLOW descendente)',
    v_sub, 'bbbb0000-0000-0000-0000-000000000016');
  if (v_res->>'observation_id') is null then
    raise exception '[FAIL] F: criar com scope DESCENDANTS sobre o descendente falhou (%)', v_res;
  end if;
  -- e o SUB NAO alcanca o subordinado direto do GESTOR (fora da relacao dele).
  perform public._mut_f5_11_p3_neg(
    format('select public.observacao_criar(%L::uuid, %L::uuid, %L::uuid, %L, %L, %L::uuid, gen_random_uuid())',
           v_org, v_ciclo, 'f5b2e000-0000-0000-0000-0000000000c3', 'NEUTRA',
           'tentativa do sub sobre quem nao e seu subordinado (P3)', v_sub),
    'P0001', 'DIRECT_REPORTS/DESCENDANTS', 'F/sub nao alcanca fora da propria relacao');

  -- (E) idempotencia continua valendo (replay identico do create do SUB).
  v_res := public.observacao_criar(
    v_org, v_ciclo, v_cneto, 'NEUTRA', 'observacao ficticia da P3 (ALLOW descendente)',
    v_sub, 'bbbb0000-0000-0000-0000-000000000016');
  if coalesce((v_res->>'idempotente')::boolean, false) is not true then
    raise exception '[FAIL] E: replay identico nao foi idempotente (%)', v_res;
  end if;

  -- (K) contagem DENTRO da transacao por IDENTIDADE: o texto original ja' foi
  --     alterado pela edicao de (E), logo comparar pelo texto seria falso-negativo.
  select count(*) into v_n from public.evaluation_observations
   where organization_id = v_org and id = v_obs;
  if v_n <> 1 then
    raise exception '[FAIL] E: a observacao ALLOW direct deveria existir exatamente 1 vez por id (veio %)', v_n;
  end if;

  raise notice '[PASS] E/F/positivos (transacao desfeita): com scope DIRECT_REPORTS o autor cria/edita/comunica/descomunica/exclui/revoga/le e consulta o historico do subordinado DIRETO (version +1, eventos na trilha e idempotencia preservada); com scope DESCENDANTS o ator alcanca o DESCENDENTE e continua negado fora da propria relacao';
end $$;

drop function public._mut_f5_11_p3_neg(text, text, text, text);

rollback;

-- ============================================================================
-- L) HIGIENE final
-- ============================================================================
do $$
declare
  v_n int;
begin
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] L: % funcao(oes) temporaria(s) `_mut_*` residual(is)', v_n;
  end if;
  select count(*) into v_n from pg_trigger t where t.tgname like '\_mut\_%';
  if v_n <> 0 then
    raise exception '[FAIL] L: % gatilho(s) temporario(s) `_mut_*` residual(is)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_observations
   where organization_id = 'f5b2a000-0000-0000-0000-0000000000a1'
     and texto like 'observacao ficticia da P3 (ALLOW%';
  if v_n <> 0 then
    raise exception '[FAIL] L: o bloco transitorio deixou % observacao(oes) de prova persistida(s)', v_n;
  end if;

  raise notice '[PASS] L/higiene: nenhum residuo de prova e nenhuma observacao do bloco transitorio persistida';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-11 P3 (Issue #246): AUTORIZACAO + CONCESSAO (D15) + SCOPE VALIDADOS.';
  raise notice '  Perfil de sistema `observacoes_gestor` com as 4 capabilities;';
  raise notice '  `admin` e `metas_*` SEM observation.*; observation.write deprecada;';
  raise notice '  ALLOW exige capability + SCOPE (DIRECT_REPORTS/DESCENDANTS) + relacao;';
  raise notice '  SELF-comunicada segue a regra especifica do dominio;';
  raise notice '  cross-tenant/IDOR fail-closed; RLS/ACL e P0-P2 preservados.';
  raise notice '============================================================';
end $$;
