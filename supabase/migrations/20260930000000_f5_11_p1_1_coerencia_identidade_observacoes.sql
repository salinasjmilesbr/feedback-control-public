-- ============================================================================
-- F5-11 P1.1 — CORRECAO POS-AUDITORIA CODEX (Issue #242): COERENCIA ESTRUTURAL
-- ENTRE PERFIL E MEMBERSHIP NA AUTORIA DAS OBSERVACOES.
-- ----------------------------------------------------------------------------
-- Auditoria independente Codex sobre a F5-11/P1 (Issue #240, integrada em `main`
-- como 0fe76193a408c857cc006707c28cb32d8c1d03c2): finding **MEDIUM**.
--
-- DEFEITO: as FKs da P1 provam, SEPARADAMENTE, que o perfil existe
-- (`fk_evaluation_observations_author_profile` -> `user_profiles`) e que a
-- membership existe NO TENANT (`fk_evaluation_observations_author_membership`
-- -> `user_organization_memberships (id, organization_id)`). Nenhuma delas prova
-- que a membership INFORMADA pertence ao PERFIL informado. Numa organizacao com
-- perfil A -> membership A e perfil B -> membership B, uma escrita tecnica podia
-- persistir `author_user_profile_id = A` com `author_membership_id = B`:
-- autoria INCOERENTE (perfil de um ator, membership de outro) sem que nenhuma
-- constraint reclamasse.
--
-- CORRECAO (mesma doutrina do precedente soberano da F5-10 P1,
-- `20260922000000_f5_10_p1_goals_schema.sql:355-419`): invariante ESTRUTURAL por
-- TRIGGER fail-closed, `SECURITY INVOKER`, para os QUATRO pares perfil<->membership
-- do dominio:
--   (1) evaluation_observations.author_user_profile_id      x author_membership_id;
--   (2) evaluation_observations.comunicado_por_user_profile_id x comunicado_por_membership_id;
--   (3) evaluation_observations.excluida_por_user_profile_id   x excluida_por_membership_id;
--   (4) evaluation_observation_events.actor_user_profile_id    x actor_membership_id.
--
-- POR QUE TRIGGER E NAO CHAVE ESTRANGEIRA COMPOSTA (mesmo raciocinio do
-- precedente, documentado e NAO copiado mecanicamente):
--   - uma FK composta exigiria uma chave candidata ATIVA sobre
--     `user_organization_memberships (id, user_profile_id)` — a F5-10 P1 ja
--     registrou que essa tabela possui a chave `(id, organization_id)` mas NAO
--     `(id, user_profile_id)`, e criar chave/indice novo ali seria mexer em
--     CONTRATO FECHADO de outra fase (F4-01/F5-02);
--   - a mesma proibicao vale para o vinculo membership<->colaborador (abaixo).
--   Portanto o mecanismo e o TRIGGER, que nao cria chave, nao altera contrato de
--   outra fase e falha fechado na gravacao.
--
-- AUTHOR_COLLABORATOR_ID (D3) — REGRA DETERMINADA PELO MODELO SOBERANO EXISTENTE,
-- NAO INVENTADA: o contrato (D3) define `author_collaborator_id` como DERIVADO do
-- vinculo e NULO quando o ator nao tem vinculo. A derivacao canonica e
-- `public.resolver_collaborador_vinculado(profile, org)` (F5-02, endurecido em
-- `20260909000000_f5_02_hardening_resolver_collaborador.sql:22-43`), que resolve
-- membership ATIVA -> `membership_collaborator_links` com `status = 'active'`.
-- Logo a coerencia estrutural exigivel e: quando `author_collaborator_id` for
-- INFORMADO, ele tem de ser o colaborador do vinculo ATIVO da membership
-- informada, no tenant da linha (link `disabled` e historico e NAO resolve —
-- Q6 = B). Um FK composto tambem nao serve aqui: `membership_collaborator_links`
-- tem `unique (membership_id)` — chave que NAO cobre `(membership_id,
-- collaborator_id)` —, e criar chave nova ali seria alterar contrato fechado da
-- F4-02. A alternativa segura, aditiva e sem nova arquitetura e o mesmo trigger.
--
-- SEPARACAO DE CLASSES DE ERRO (doutrina do precedente, preservada):
--   - valor AUSENTE ................ NOT NULL da coluna          -> 23502
--   - referencia INEXISTENTE ....... FK composta                 -> 23503
--   - referencia existente INCOERENTE ... este trigger           -> P0001
-- Ausencia e inexistencia NAO sao tratadas aqui: o trigger so cuida de COERENCIA
-- entre valores EFETIVAMENTE informados. Consequencias deliberadas:
--   - par com apenas UM lado informado continua sendo recusado pelo CHECK do
--     contrato (`ck_evaluation_observations_comunicado` / `..._exclusao`), para
--     que a mensagem e o sqlstate continuem sendo os da constraint;
--   - alvo de OUTRO tenant continua caindo na FK composta (23503): as consultas
--     deste trigger sao SEMPRE filtradas por `organization_id`, de modo que um
--     alvo cross-tenant simplesmente NAO e encontrado aqui e a FK fala.
--
-- NAO altera (e o validador 37 prova): D1-D16, D4 (imutabilidade), D6
-- (append-only), D9 (RLS/ACL deny-by-default), FKs, CHECKs, indices, catalogo de
-- capabilities (31), bundle `admin` (9, SEM `observation.*`), nenhuma RPC
-- `observacao_*`, nenhuma policy, nenhum grant, nenhum SECURITY DEFINER, nenhuma
-- role/bundle/perfil e nenhuma decisao de D15. A migration da P1
-- (`20260929000000_...`) NAO e editada retroativamente: a correcao e ADITIVA,
-- como manda a doutrina de migrations do repositorio.
--
-- Nota sobre ACL: as funcoes sao `SECURITY INVOKER` e NAO recebem revoke
-- explicito de EXECUTE — mesma postura do precedente F5-10 P1 (que tambem nao
-- revoga). Funcoes de TRIGGER nao possuem superficie de chamada direta: o
-- PostgreSQL recusa invocacao fora de contexto de trigger (0A000).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) PREFLIGHT fail-closed do baseline
-- ----------------------------------------------------------------------------
do $$
declare
  v_faltando text[] := array[]::text[];
  v_col      text;
  v_n        int;
begin
  -- (a) as duas tabelas da P1 existem.
  if to_regclass('public.evaluation_observations') is null then
    v_faltando := v_faltando || 'public.evaluation_observations'::text;
  end if;
  if to_regclass('public.evaluation_observation_events') is null then
    v_faltando := v_faltando || 'public.evaluation_observation_events'::text;
  end if;

  -- (b) as COLUNAS dos quatro pares existem (o finding so pode ser corrigido
  --     sobre exatamente o contrato da P1).
  foreach v_col in array array[
    'author_user_profile_id', 'author_membership_id', 'author_collaborator_id',
    'comunicado_por_user_profile_id', 'comunicado_por_membership_id',
    'excluida_por_user_profile_id', 'excluida_por_membership_id'] loop
    if not exists (
      select 1 from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'evaluation_observations'
         and c.column_name = v_col
    ) then
      v_faltando := v_faltando || format('evaluation_observations.%s', v_col);
    end if;
  end loop;
  foreach v_col in array array['actor_user_profile_id', 'actor_membership_id'] loop
    if not exists (
      select 1 from information_schema.columns c
       where c.table_schema = 'public' and c.table_name = 'evaluation_observation_events'
         and c.column_name = v_col
    ) then
      v_faltando := v_faltando || format('evaluation_observation_events.%s', v_col);
    end if;
  end loop;

  -- (c) o modelo do vinculo que a regra de author_collaborator_id usa existe.
  if to_regclass('public.membership_collaborator_links') is null then
    v_faltando := v_faltando || 'public.membership_collaborator_links'::text;
  end if;
  if to_regprocedure('public.resolver_collaborador_vinculado(uuid, uuid)') is null then
    v_faltando := v_faltando || 'public.resolver_collaborador_vinculado(uuid, uuid)'::text;
  end if;

  -- (d) a fundacao da P1 esta integra (D4 e D6 presentes): a correcao nao pode
  --     ser aplicada sobre um baseline onde as garantias da P1 nao existem.
  foreach v_col in array array[
    'trg_evaluation_observations_imutaveis',
    'trg_evaluation_observations_updated_at',
    'trg_evaluation_observation_events_append_only',
    'trg_evaluation_observation_events_no_delete',
    'trg_evaluation_observation_events_no_truncate'] loop
    if not exists (select 1 from pg_trigger t where t.tgname = v_col and not t.tgisinternal) then
      v_faltando := v_faltando || format('gatilho da P1 ausente: %s', v_col);
    end if;
  end loop;

  if array_length(v_faltando, 1) is not null then
    raise exception 'F5-11 P1.1: baseline incompleto: %', array_to_string(v_faltando, ', ');
  end if;

  -- A migration NAO e idempotente por design: reexecutar sobre um banco ja
  -- corrigido deve falhar ALTO, nunca "meio aplicar".
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('f5_11_validar_coerencia_identidade',
                       'f5_11_validar_coerencia_identidade_evento');
  if v_n <> 0 then
    raise exception 'F5-11 P1.1: funcoes de coerencia ja existem (esperado banco limpo / db reset)';
  end if;
  select count(*) into v_n from pg_trigger t
   where t.tgname in ('trg_evaluation_observations_coerencia_identidade',
                      'trg_evaluation_observation_events_coerencia_identidade')
     and not t.tgisinternal;
  if v_n <> 0 then
    raise exception 'F5-11 P1.1: gatilhos de coerencia ja existem (esperado banco limpo / db reset)';
  end if;

  -- D15 permanece INTACTO: nenhuma concessao de `observation.*` e `admin` sem ela.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    raise exception 'F5-11 P1.1: catalogo com % capabilities (esperado 31)', v_n;
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    raise exception 'F5-11 P1.1: % concessao(oes) de observation.* (D15 e decisao da P3)', v_n;
  end if;

  raise notice 'F5-11 P1.1: preflight ok (tabelas/colunas da P1, gatilhos D4/D6, modelo de vinculo presente, catalogo 31 e D15 intacto)';
end $$;

-- ----------------------------------------------------------------------------
-- 1) LINHA da observacao — coerencia de autoria, comunicacao e exclusao
-- ----------------------------------------------------------------------------
-- Percorre os TRES pares da linha. Cada par e validado SOMENTE quando os dois
-- lados estao informados (a ausencia de um lado e assunto das constraints do
-- contrato, nao deste invariante de coerencia).
create or replace function public.f5_11_validar_coerencia_identidade()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_par          record;
  v_perfil_da_memb uuid;
  v_vinculado    uuid;
begin
  -- (1..3) perfil <-> membership, par a par.
  for v_par in
    select * from (values
      ('author',     new.author_user_profile_id,     new.author_membership_id),
      ('comunicado', new.comunicado_por_user_profile_id, new.comunicado_por_membership_id),
      ('exclusao',   new.excluida_por_user_profile_id,   new.excluida_por_membership_id)
    ) as t(rotulo, perfil, membership)
  loop
    -- Ausencia de um dos lados: quem recusa e a constraint do contrato
    -- (NOT NULL -> 23502; CHECK de coerencia -> 23514).
    if v_par.perfil is null or v_par.membership is null then
      continue;
    end if;

    -- Perfil INEXISTENTE: quem recusa e a FK (23503). Aqui so se julga COERENCIA
    -- entre referencias que existem.
    if not exists (select 1 from public.user_profiles p where p.id = v_par.perfil) then
      continue;
    end if;

    -- Busca SEMPRE filtrada pelo tenant da LINHA: alvo de outro tenant nao e
    -- encontrado aqui e a FK composta fala (23503).
    select m.user_profile_id into v_perfil_da_memb
      from public.user_organization_memberships m
     where m.id = v_par.membership
       and m.organization_id = new.organization_id;

    if v_perfil_da_memb is not null and v_perfil_da_memb is distinct from v_par.perfil then
      raise exception
        'F5-11 (Issue #242): autoria de % incoerente — perfil % nao e o perfil da membership % no tenant %',
        v_par.rotulo, v_par.perfil, v_par.membership, new.organization_id;
    end if;
  end loop;

  -- (4) author_collaborator_id: quando informado, tem de ser o colaborador do
  --     vinculo ATIVO da membership, no tenant da linha (paridade com
  --     `resolver_collaborador_vinculado`, F5-02 Q4=A / Q6=B). NULO continua
  --     legitimo (ator sem vinculo de colaborador).
  if new.author_collaborator_id is not null then
    if exists (
      select 1 from public.collaborators c
       where c.id = new.author_collaborator_id
         and c.organization_id = new.organization_id
    ) then
      select l.collaborator_id into v_vinculado
        from public.membership_collaborator_links l
       where l.membership_id = new.author_membership_id
         and l.organization_id = new.organization_id
         and l.status = 'active';

      if v_vinculado is distinct from new.author_collaborator_id then
        raise exception
          'F5-11 (Issue #242): author_collaborator_id % nao e o colaborador do vinculo ATIVO da membership % no tenant %',
          new.author_collaborator_id, new.author_membership_id, new.organization_id;
      end if;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.f5_11_validar_coerencia_identidade() is
  'F5-11 P1.1 (Issue #242, finding MEDIUM do Codex): invariante de COERENCIA da '
  'autoria da observacao — o perfil informado tem de ser o perfil da membership '
  'informada, no tenant da linha, para autor, comunicado e exclusao; e '
  'author_collaborator_id, quando informado, tem de ser o colaborador do vinculo '
  'ATIVO da membership (paridade com resolver_collaborador_vinculado, F5-02). '
  'Nao decide legitimidade funcional (isso e P2/P3): impede apenas combinacoes '
  'intra-tenant INCOERENTES. SECURITY INVOKER, search_path = public.';

-- BEFORE INSERT OR UPDATE: a linha e MUTAVEL (D4 preserva tipo/texto/comunicado/
-- exclusao/motivo/carimbos/version), logo o invariante precisa valer tambem nas
-- transicoes (marcar comunicado, excluir, revogar). `UPDATE OF` limita o disparo
-- as colunas que participam do invariante, como no precedente da F5-10.
create trigger trg_evaluation_observations_coerencia_identidade
  before insert or update of
    organization_id,
    author_user_profile_id, author_membership_id, author_collaborator_id,
    comunicado_por_user_profile_id, comunicado_por_membership_id,
    excluida_por_user_profile_id, excluida_por_membership_id
  on public.evaluation_observations
  for each row execute function public.f5_11_validar_coerencia_identidade();

-- ----------------------------------------------------------------------------
-- 2) TRILHA — coerencia do ator soberano do evento
-- ----------------------------------------------------------------------------
-- A trilha e APPEND-ONLY (D6): o invariante e verificado no INSERT. Um UPDATE
-- nunca chega a executar (os tres gatilhos da P1 abortam antes), portanto nao ha
-- caminho de mutacao a cobrir aqui.
create or replace function public.f5_11_validar_coerencia_identidade_evento()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_perfil_da_memb uuid;
begin
  -- `actor_user_profile_id` e `actor_membership_id` sao NOT NULL na trilha: a
  -- ausencia e assunto do NOT NULL (23502) e a referencia inexistente, da FK
  -- (23503). Aqui so se julga COERENCIA.
  if new.actor_user_profile_id is null or new.actor_membership_id is null then
    return new;
  end if;

  if not exists (select 1 from public.user_profiles p where p.id = new.actor_user_profile_id) then
    return new;
  end if;

  select m.user_profile_id into v_perfil_da_memb
    from public.user_organization_memberships m
   where m.id = new.actor_membership_id
     and m.organization_id = new.organization_id;

  if v_perfil_da_memb is not null and v_perfil_da_memb is distinct from new.actor_user_profile_id then
    raise exception
      'F5-11 (Issue #242): ator do evento incoerente — actor_user_profile_id % nao e o perfil da membership % no tenant %',
      new.actor_user_profile_id, new.actor_membership_id, new.organization_id;
  end if;

  return new;
end;
$$;

comment on function public.f5_11_validar_coerencia_identidade_evento() is
  'F5-11 P1.1 (Issue #242, finding MEDIUM do Codex): invariante de COERENCIA do '
  'ator da trilha — actor_user_profile_id tem de ser o perfil da '
  'actor_membership_id, no tenant da linha. Nao decide legitimidade funcional. '
  'SECURITY INVOKER, search_path = public.';

create trigger trg_evaluation_observation_events_coerencia_identidade
  before insert on public.evaluation_observation_events
  for each row execute function public.f5_11_validar_coerencia_identidade_evento();

-- ----------------------------------------------------------------------------
-- 3) GUARDA FINAL fail-closed do estado da P1.1
-- ----------------------------------------------------------------------------
do $$
declare
  v_falhas text[] := array[]::text[];
  v_tab    text;
  v_priv   text;
  v_fn     text;
  v_n      int;
begin
  -- (a) as duas funcoes existem, sao INVOKER e tem search_path fixo.
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

  -- (b) os dois gatilhos existem, sao BEFORE ROW e apontam para as funcoes certas.
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_observations'::regclass
       and t.tgname = 'trg_evaluation_observations_coerencia_identidade'
       and not t.tgisinternal and t.tgtype = 23  -- BEFORE (2) + ROW (1) + INSERT(4)+UPDATE(16)
       and t.tgfoid = 'public.f5_11_validar_coerencia_identidade()'::regprocedure
  ) then
    v_falhas := v_falhas || 'gatilho de coerencia da linha ausente ou com forma errada'::text;
  end if;
  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.evaluation_observation_events'::regclass
       and t.tgname = 'trg_evaluation_observation_events_coerencia_identidade'
       and not t.tgisinternal and t.tgtype = 7  -- BEFORE (2) + ROW (1) + INSERT (4)
       and t.tgfoid = 'public.f5_11_validar_coerencia_identidade_evento()'::regprocedure
  ) then
    v_falhas := v_falhas || 'gatilho de coerencia da trilha ausente ou com forma errada'::text;
  end if;

  -- (c) D4 e D6 INTACTOS.
  foreach v_fn in array array[
    'trg_evaluation_observations_imutaveis',
    'trg_evaluation_observations_updated_at',
    'trg_evaluation_observation_events_append_only',
    'trg_evaluation_observation_events_no_delete',
    'trg_evaluation_observation_events_no_truncate'] loop
    if not exists (select 1 from pg_trigger t where t.tgname = v_fn and not t.tgisinternal) then
      v_falhas := v_falhas || format('gatilho da P1 perdido: %s', v_fn);
    end if;
  end loop;

  -- (d) D9 INTACTO: RLS ligada, ZERO policy e ZERO privilegio de cliente.
  foreach v_tab in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relrowsecurity
    ) then
      v_falhas := v_falhas || format('RLS desabilitada: %s', v_tab);
    end if;
    if exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = v_tab) then
      v_falhas := v_falhas || format('policy indevida (D9 exige ZERO): %s', v_tab);
    end if;
    foreach v_priv in array array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] loop
      if has_table_privilege('authenticated', format('public.%I', v_tab), v_priv)
         or has_table_privilege('anon', format('public.%I', v_tab), v_priv) then
        v_falhas := v_falhas || format('%s: cliente com %s', v_tab, v_priv);
      end if;
    end loop;
  end loop;
  if has_table_privilege('service_role', 'public.evaluation_observations', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_observations', 'TRUNCATE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'UPDATE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_observation_events', 'TRUNCATE') then
    v_falhas := v_falhas || 'service_role com privilegio de reescrita/exclusao fisica'::text;
  end if;

  -- (e) FRONTEIRA P1.1: nenhuma RPC de dominio, nenhuma policy nova, nenhuma
  --     capability nova, nenhum DEFINER novo, nenhuma role/bundle/perfil e D15
  --     intacto.
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'observacao\_%' or p.proname like 'observation\_%');
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s RPC(s) observacao_* (a P2 nao pode ser antecipada)', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef
     and p.proname in ('f5_11_validar_coerencia_identidade',
                       'f5_11_validar_coerencia_identidade_evento');
  if v_n <> 0 then
    v_falhas := v_falhas || 'funcao da P1.1 com SECURITY DEFINER'::text;
  end if;
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo com %s capabilities (esperado 31)', v_n);
  end if;
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('goal.%% + observation.%% = %s (esperado 8)', v_n);
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.capabilities c on c.id = rc.capability_id
   where c.code like 'observation.%';
  if v_n <> 0 then
    v_falhas := v_falhas || format('D15 violado: %s concessao(oes) de observation.*', v_n);
  end if;
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
    v_falhas := v_falhas || 'admin com observation.*'::text;
  end if;
  if (select array_agg(r.name order by r.name)
        from public.access_roles r where r.is_system = true)
     is distinct from array['admin', 'metas_aprovador', 'metas_dono'] then
    v_falhas := v_falhas || 'conjunto de roles de SISTEMA mudou (a P1.1 nao cria role/bundle/perfil)'::text;
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] F5-11 P1.1: guarda final: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] F5-11 P1.1: guarda final: coerencia perfil<->membership instalada para os 4 pares (2 funcoes INVOKER com search_path fixo e 2 gatilhos BEFORE ROW), D4/D6/D9 intactos, nenhuma RPC/policy/capability/role nova, catalogo 31, bundle admin 9 SEM observation.* e D15 intacto';
end $$;
