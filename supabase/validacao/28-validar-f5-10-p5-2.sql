-- ============================================================================
-- F5-10 P5.2 (Issue #222): validacao da PROJECAO da leitura soberana de metas
-- (`public.meta_listar_por_escopo`) — Supabase local apenas
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem (ordem do CI):
--   supabase/validacao/25-cenario-f5-10-p4.sql   (fixture; 7 metas, 0 aprovacoes)
--   supabase/validacao/26-validar-f5-10-p4.sql   (autorizacao/RLS da P4)
--   supabase/validacao/28-validar-f5-10-p5-2.sql (este arquivo)
--
-- Contrato: docs/F5-10-P5.2-contrato-leitura-soberana-metas.md (§3 projecao,
-- §4 estados de aprovacao, §5 quota, §6 guardas).
-- Migration sob prova: supabase/migrations/20260928000000_f5_10_p5_2_leitura_soberana_metas.sql
--
-- ============================================================================
-- DOUTRINA DESTE VALIDADOR (anti-circularidade e anti-suposicao)
-- ============================================================================
-- O validador NAO conhece a fixture. Nao existe, em nenhum ponto deste arquivo,
-- expectativa literal sobre QUAL meta tem QUAL aprovador CONGELADO, QUAL
-- `exigida`/`vigente` ou QUAL data. Toda expectativa e DERIVADA EM TEMPO DE
-- EXECUCAO (SQL) das fontes canonicas, e a descoberta de alvos (goal, papel,
-- ator, ciclo) e feita por CONSULTA ao banco (`order by ... limit 1`), nunca por
-- id de meta escrito a mao:
--
--   * `public.f5_10_aprovador_congelado(goal, org, papel)`
--       -> 20260924000000_f5_10_p3_approvals_rpc.sql:273-372 (fonte UNICA da
--          legitimidade; snapshot CONGELADO, nunca estrutura viva);
--   * `public.f5_10_vinculo_meta_do_ator(ator, org)`
--       -> 20260925000000_f5_10_p4_authorization_rls.sql:210-240 (SELF);
--   * `public.f5_10_exigir_autorizacao_meta(...)`
--       -> 20260925000000_f5_10_p4_authorization_rls.sql:275-391 (gate);
--   * `public.f5_10_ator_valido_meta(ator, org, capability)`
--       -> 20260925000000_f5_10_p4_authorization_rls.sql:168-188;
--   * `public.evaluation_ator_valido(ator, org)`
--       -> 20260911010000_f5_06_evaluation_functions.sql:66-88;
--   * `public.evaluation_goals`
--       -> 20260922000000_f5_10_p1_goals_schema.sql:98-175
--          (created_at :117, updated_at :118, data_ultimo_acompanhamento :110,
--           data_fechamento :113, data_exclusao :115);
--   * `public.evaluation_goal_approvals`
--       -> 20260922000000_f5_10_p1_goals_schema.sql:271-343
--          (papel :275, decidido_em :281, motivo :282, revogado_em :283;
--           unicidade parcial `(goal_id, papel) where revogado_em is null` :341-343);
--   * `public.evaluation_cycle_goal_limits`
--       -> 20260922000000_f5_10_p1_goals_schema.sql:221-247.
--
-- O ORACULO E O BANCO: a prova e de TRANSPORTE (a projecao carrega o fato
-- soberano?), nunca de semantica interna duplicada. Para CADA meta devolvida
-- pela RPC e CADA papel de `aprovacoes[]`, o valor PROJETADO e confrontado com o
-- valor CANONICO calculado no SQL, e `vigente`/`aprovacao_id`/`decidido_em`/
-- `motivo` sao confrontados com a LINHA REAL de `evaluation_goal_approvals`.
-- ============================================================================

-- ============================================================================
-- 0) PREFLIGHT: fixture presente, projecao P5.2 instalada e oraculos canonicos
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_oid   oid;
  v_sec   boolean;
  v_cfg   text;
  v_def   text;
  v_n     int;
  v_tab   text;
  v_ciclo uuid;
begin
  if to_regclass('public.evaluation_goals') is null
     or to_regclass('public.evaluation_goal_approvals') is null
     or to_regclass('public.evaluation_cycle_goal_limits') is null
     or to_regclass('public.evaluation_cycles') is null then
    raise exception '[FAIL] pre-condicao: schema de metas ausente — execute `supabase db reset` e os cenarios 25/26';
  end if;
  if not exists (select 1 from public.organizations o where o.id = v_alfa)
     or not exists (select 1 from public.organizations o where o.id = v_beta) then
    raise exception '[FAIL] pre-condicao: organizacoes da fixture F5-10 P4 (Alfa/Beta) ausentes — execute os cenarios 25/26';
  end if;

  -- (a) A superficie soberana contratada esta instalada com a assinatura EXATA,
  --     SECURITY INVOKER e `search_path` fixo.
  v_oid := to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid)');
  if v_oid is null then
    raise exception '[FAIL] pre-condicao: assinatura public.meta_listar_por_escopo(uuid, uuid, uuid) ausente';
  end if;
  select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), ''), pg_get_functiondef(p.oid)
    into v_sec, v_cfg, v_def
    from pg_proc p where p.oid = v_oid;
  if v_sec then
    raise exception '[FAIL] pre-condicao: meta_listar_por_escopo deveria ser SECURITY INVOKER';
  end if;
  if position('search_path=public' in v_cfg) = 0 then
    raise exception '[FAIL] pre-condicao: meta_listar_por_escopo deveria fixar search_path = public';
  end if;
  -- A projecao P5.2 esta instalada (migration aditiva aplicada): datas soberanas,
  -- estado de aprovacao por papel e quota do ciclo no envelope.
  if position('''criado_em''' in v_def) = 0
     or position('''atualizado_em''' in v_def) = 0
     or position('''data_ultimo_acompanhamento''' in v_def) = 0
     or position('''data_fechamento''' in v_def) = 0
     or position('''data_exclusao''' in v_def) = 0
     or position('''aprovacoes''' in v_def) = 0
     or position('''aprovador_collaborator_id''' in v_def) = 0
     or position('''exigida''' in v_def) = 0
     or position('''vigente''' in v_def) = 0
     or position('''limites''' in v_def) = 0 then
    raise exception '[FAIL] pre-condicao: a migration aditiva da P5.2 (20260928000000) nao esta aplicada';
  end if;

  -- (b) As fontes CANONICAS que servem de oraculo existem (sem elas nao ha prova).
  if to_regprocedure('public.f5_10_aprovador_congelado(uuid, uuid, text)') is null
     or to_regprocedure('public.f5_10_vinculo_meta_do_ator(uuid, uuid)') is null
     or to_regprocedure('public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid)') is null
     or to_regprocedure('public.f5_10_ator_valido_meta(uuid, uuid, text)') is null
     or to_regprocedure('public.evaluation_ator_valido(uuid, uuid)') is null
     or to_regprocedure('public.f5_10_derivar_operation_id(uuid, text)') is null then
    raise exception '[FAIL] pre-condicao: fonte canonica de comparacao ausente (P3/P4/F5-06)';
  end if;

  -- (c) Contrato de COLUNAS das fontes usadas na comparacao item a item.
  --     evaluation_goals (P1:98-175) — 11 colunas usadas aqui.
  select count(*) into v_n
    from pg_attribute a
   where a.attrelid = 'public.evaluation_goals'::regclass
     and a.attname in ('id', 'organization_id', 'cycle_id', 'collaborator_id', 'status',
                       'excluida', 'version', 'created_at', 'updated_at',
                       'data_ultimo_acompanhamento', 'data_fechamento', 'data_exclusao')
     and a.attnum > 0 and not a.attisdropped;
  if v_n <> 12 then
    raise exception '[FAIL] pre-condicao: evaluation_goals sem o contrato de colunas do oraculo (% de 12)', v_n;
  end if;
  --     evaluation_goal_approvals (P1:271-343) — 9 colunas usadas aqui.
  select count(*) into v_n
    from pg_attribute a
   where a.attrelid = 'public.evaluation_goal_approvals'::regclass
     and a.attname in ('id', 'organization_id', 'goal_id', 'papel', 'actor_user_profile_id',
                       'actor_membership_id', 'decidido_em', 'motivo', 'revogado_em')
     and a.attnum > 0 and not a.attisdropped;
  if v_n <> 9 then
    raise exception '[FAIL] pre-condicao: evaluation_goal_approvals sem o contrato de colunas do oraculo (% de 9)', v_n;
  end if;
  --     evaluation_cycle_goal_limits (P1:221-247) — 5 colunas usadas aqui.
  select count(*) into v_n
    from pg_attribute a
   where a.attrelid = 'public.evaluation_cycle_goal_limits'::regclass
     and a.attname in ('organization_id', 'cycle_id', 'tipo', 'quantidade', 'version')
     and a.attnum > 0 and not a.attisdropped;
  if v_n <> 5 then
    raise exception '[FAIL] pre-condicao: evaluation_cycle_goal_limits sem o contrato de colunas do oraculo (% de 5)', v_n;
  end if;

  -- (d) O ciclo ATIVO do tenant e DESCOBERTO (nunca literal): e o ciclo com metas
  --     mutaveis da fixture — o alvo das provas de transporte vivo.
  select c.id into v_ciclo
    from public.evaluation_cycles c
   where c.organization_id = v_alfa
     and c.status = 'ATIVO'
   order by (select count(*)
               from public.evaluation_goals g
              where g.organization_id = v_alfa and g.cycle_id = c.id) desc,
            c.id
   limit 1;
  if v_ciclo is null then
    raise exception '[FAIL] pre-condicao: nenhum ciclo ATIVO no tenant Alfa (fixture 25/26)';
  end if;
  select count(*) into v_n
    from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_ciclo;
  if v_n = 0 then
    raise exception '[FAIL] pre-condicao: ciclo ATIVO de Alfa sem metas (fixture 25/26)';
  end if;

  -- (e) Existe ator legivel (perfil + membership ATIVOS, vinculo UNICO e
  --     `goal.read` efetivo): sem ele nenhuma leitura pode ser exercitada.
  select count(*) into v_n
    from public.user_profiles p
   where public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
     and public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) is not null;
  if v_n = 0 then
    raise exception '[FAIL] pre-condicao: nenhum ator com goal.read + vinculo UNICO no tenant Alfa';
  end if;

  -- (f) As 4 tabelas de metas continuam deny-by-default INTEGRAL (a P5.2 nao
  --     amplia superficie: nenhuma policy, nenhum privilegio de cliente).
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_n <> 0 then
      raise exception '[FAIL] pre-condicao: % com % policy(ies) (D22-A exige zero)', v_tab, v_n;
    end if;
    if has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT')
       or has_table_privilege('anon', format('public.%I', v_tab), 'SELECT') then
      raise exception '[FAIL] pre-condicao: % nao pode conceder SELECT a authenticated/anon', v_tab;
    end if;
  end loop;

  -- (g) Catalogo intacto (nenhuma capability nova por esta fase).
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    raise exception '[FAIL] pre-condicao: capabilities de metas/observacoes = % (esperado 8)', v_n;
  end if;

  raise notice '[PASS] preflight: fixture F5-10 P4 presente, projecao P5.2 instalada (datas + aprovacoes por papel + limites), superficie INVOKER com search_path fixo, oraculos canonicos (P3/P4/F5-06) e contrato de colunas presentes, ciclo ATIVO descoberto, 4 tabelas de metas deny-by-default integral e catalogo intacto (8 goal.%%/observation.%%)';
end $$;

-- ============================================================================
-- 1) NUCLEO ANTI-CIRCULAR: para CADA meta projetada e CADA papel, o valor
--    PROJETADO e confrontado com o oraculo CANONICO calculado no SQL
-- ============================================================================
-- Varredura derivada: para TODO par (ator com `goal.read` + vinculo UNICO,
-- ciclo do tenant) a leitura e executada e a projecao e conferida item a item:
--   (a) `relacao` == relacao CONGELADA canonica e a meta satisfaz o predicado
--       canonico (SELF ∪ APROVADOR_GERENTE_CONGELADO ∪ APROVADOR_COORDENADOR_CONGELADO);
--   (b) COMPLETUDE: toda meta do (tenant, ciclo) que satisfaz o predicado
--       canonico esta projetada; AUSENCIA: nenhuma meta fora do predicado entra;
--   (c) as 5 datas projetadas == colunas da LINHA (`created_at`/`updated_at`/
--       `data_ultimo_acompanhamento`/`data_fechamento`/`data_exclusao`);
--   (d) `aprovacoes` == 2 itens, ordem COORDENADOR/GERENTE, `papel` no dominio;
--   (e) `exigida` == canonico ((papel='GERENTE') or congelado(COORDENADOR) is not null);
--   (f) `aprovador_collaborator_id` == colaborador CONGELADO do papel;
--   (g) `vigente`/`aprovacao_id`/`decidido_em`/`motivo` == linha VIGENTE de
--       `evaluation_goal_approvals` (e nulos quando NAO ha linha vigente);
--   (h) `aprovacoes_vigentes` == agregado canonico do MESMO fato;
--   (i) a leitura NAO grava evento (ler nao e fato).
do $$
declare
  v_alfa        uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_par         record;
  v_res         jsonb;
  v_meta        jsonb;
  v_ap          jsonb;
  v_item        jsonb;
  v_goal        uuid;
  v_vinculo     uuid;
  v_papel       text;
  v_pos         int;
  v_n_fato      int;
  v_fato_id     uuid;
  v_fato_dec    timestamptz;
  v_fato_motivo text;
  v_colab       uuid;
  v_cycle       uuid;
  v_criado      timestamptz;
  v_atualizado  timestamptz;
  v_dua         timestamptz;
  v_dfech       timestamptz;
  v_dexc        timestamptz;
  v_cong_coord  uuid;
  v_cong_papel  uuid;
  v_exig_can    boolean;
  v_rel_can     text;
  v_agg_can     jsonb;
  v_falta       int;
  v_vaza        int;
  v_n_pares     int := 0;
  v_n_meta      int := 0;
  v_n_item      int := 0;
  v_n_vig       int := 0;
  v_n_pend      int := 0;
  v_n_exempt    int := 0;
  v_ev_antes    bigint;
  v_ev_depois   bigint;
begin
  select count(*) into v_ev_antes
    from public.evaluation_goal_events e where e.organization_id = v_alfa;

  for v_par in
    select p.id as ator, c.id as ciclo
      from public.user_profiles p
      cross join public.evaluation_cycles c
     where c.organization_id = v_alfa
       and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
       and public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) is not null
     order by c.id, p.id
  loop
    v_n_pares := v_n_pares + 1;
    v_vinculo := public.f5_10_vinculo_meta_do_ator(v_par.ator, v_alfa);
    v_res := public.meta_listar_por_escopo(v_alfa, v_par.ciclo, v_par.ator);

    -- (0) Envelope: chaves e quantidade coerentes com o proprio corpo.
    if v_res is null or jsonb_typeof(v_res) <> 'object' then
      raise exception '[FAIL] 1: leitura nao devolveu objeto (ator %, ciclo %)', v_par.ator, v_par.ciclo;
    end if;
    if jsonb_typeof(v_res->'metas') <> 'array' or jsonb_typeof(v_res->'quantidade') <> 'number' then
      raise exception '[FAIL] 1: envelope sem `metas` (array) ou `quantidade` (numero) — ator %, ciclo %', v_par.ator, v_par.ciclo;
    end if;
    if (v_res->>'quantidade')::int <> jsonb_array_length(v_res->'metas') then
      raise exception '[FAIL] 1: `quantidade` (%) difere do tamanho de `metas` (%) — ator %, ciclo %',
        v_res->>'quantidade', jsonb_array_length(v_res->'metas'), v_par.ator, v_par.ciclo;
    end if;
    if v_res->>'relacao_ator' is distinct from
       (case when jsonb_array_length(v_res->'metas') = 0 then 'SEM_META_AUTORIZADA' else 'ESCOPO_APLICADO' end) then
      raise exception '[FAIL] 1: `relacao_ator` incoerente com `metas` (%) — ator %, ciclo %',
        v_res->>'relacao_ator', v_par.ator, v_par.ciclo;
    end if;
    if v_res->>'organization_id' <> v_alfa::text or v_res->>'cycle_id' <> v_par.ciclo::text then
      raise exception '[FAIL] 1: envelope com tenant/ciclo diferente do solicitado — ator %, ciclo %', v_par.ator, v_par.ciclo;
    end if;

    -- (a..h) item a item
    for v_meta in select m from jsonb_array_elements(v_res->'metas') m loop
      v_n_meta := v_n_meta + 1;
      v_goal := (v_meta->>'goal_id')::uuid;

      select g.cycle_id, g.collaborator_id, g.created_at, g.updated_at,
             g.data_ultimo_acompanhamento, g.data_fechamento, g.data_exclusao
        into v_cycle, v_colab, v_criado, v_atualizado, v_dua, v_dfech, v_dexc
        from public.evaluation_goals g
       where g.id = v_goal and g.organization_id = v_alfa;
      if v_cycle is null then
        raise exception '[FAIL] 1: meta projetada inexistente no tenant do envelope (goal %)', v_goal;
      end if;
      if v_cycle <> v_par.ciclo then
        raise exception '[FAIL] 1: meta projetada fora do ciclo do envelope (goal %, ciclo % vs %)',
          v_goal, v_cycle, v_par.ciclo;
      end if;

      v_cong_coord := public.f5_10_aprovador_congelado(v_goal, v_alfa, 'COORDENADOR');

      -- (a) relacao CONGELADA canonica
      v_rel_can := case
        when v_colab = v_vinculo then 'SELF'
        when public.f5_10_aprovador_congelado(v_goal, v_alfa, 'GERENTE') = v_vinculo
          then 'APROVADOR_GERENTE_CONGELADO'
        else 'APROVADOR_COORDENADOR_CONGELADO'
      end;
      if v_meta->>'relacao' is distinct from v_rel_can then
        raise exception '[FAIL] 1: `relacao` divergente da relacao CONGELADA canonica (goal %: projetado %, canonico %)',
          v_goal, v_meta->>'relacao', v_rel_can;
      end if;
      if not (v_colab = v_vinculo
              or public.f5_10_aprovador_congelado(v_goal, v_alfa, 'GERENTE') = v_vinculo
              or v_cong_coord = v_vinculo) then
        raise exception '[FAIL] 1: meta projetada SEM relacao canonica com o ator (goal %, ator %)', v_goal, v_par.ator;
      end if;

      -- (c) datas soberanas == colunas da LINHA (o corpo nao carrega datas)
      if v_criado is null or v_atualizado is null then
        raise exception '[FAIL] 1: coluna soberana de criacao/atualizacao nula (goal %)', v_goal;
      end if;
      if v_meta->>'criado_em' is null or v_meta->>'atualizado_em' is null then
        raise exception '[FAIL] 1: `criado_em`/`atualizado_em` nao podem ser nulos (goal %)', v_goal;
      end if;
      if coalesce(v_meta->'criado_em', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_criado), 'null'::jsonb)
         or coalesce(v_meta->'atualizado_em', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_atualizado), 'null'::jsonb)
         or coalesce(v_meta->'data_ultimo_acompanhamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_dua), 'null'::jsonb)
         or coalesce(v_meta->'data_fechamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_dfech), 'null'::jsonb)
         or coalesce(v_meta->'data_exclusao', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_dexc), 'null'::jsonb) then
        raise exception '[FAIL] 1: datas projetadas divergentes das colunas SOBERANAS da linha (goal %)', v_goal;
      end if;

      -- (d) `aprovacoes`: SEMPRE 2 itens, ordem CONTRATADA COORDENADOR, GERENTE
      v_ap := v_meta->'aprovacoes';
      if v_ap is null or jsonb_typeof(v_ap) <> 'array' or jsonb_array_length(v_ap) <> 2 then
        raise exception '[FAIL] 1: `aprovacoes` deveria ter SEMPRE os 2 papeis (goal %: %)', v_goal, v_ap;
      end if;
      if v_ap->0->>'papel' <> 'COORDENADOR' or v_ap->1->>'papel' <> 'GERENTE' then
        raise exception '[FAIL] 1: ordem dos papeis deveria ser COORDENADOR, GERENTE (goal %: %)', v_goal, v_ap;
      end if;

      for v_pos in 0 .. 1 loop
        v_n_item := v_n_item + 1;
        v_item := v_ap->v_pos;
        v_papel := v_item->>'papel';
        if v_papel not in ('COORDENADOR', 'GERENTE') then
          raise exception '[FAIL] 1: `papel` fora do dominio (goal %: %)', v_goal, v_item;
        end if;

        -- (e) `exigida` == canonico calculado no SQL
        if jsonb_typeof(v_item->'exigida') <> 'boolean' or jsonb_typeof(v_item->'vigente') <> 'boolean' then
          raise exception '[FAIL] 1: `exigida`/`vigente` deveriam ser booleanos (goal % papel %: %)', v_goal, v_papel, v_item;
        end if;
        v_cong_papel := public.f5_10_aprovador_congelado(v_goal, v_alfa, v_papel);
        v_exig_can := (v_papel = 'GERENTE') or (v_cong_coord is not null);
        if (v_item->>'exigida')::boolean is distinct from v_exig_can then
          raise exception '[FAIL] 1: `exigida` divergente do canonico (goal % papel %: projetado %, canonico %)',
            v_goal, v_papel, v_item->>'exigida', v_exig_can::text;
        end if;

        -- (f) identidade SOBERANA do aprovador == colaborador CONGELADO do papel
        if coalesce(v_item->'aprovador_collaborator_id', 'null'::jsonb)
           is distinct from coalesce(to_jsonb(v_cong_papel), 'null'::jsonb) then
          raise exception '[FAIL] 1: `aprovador_collaborator_id` divergente do colaborador CONGELADO (goal % papel %: projetado %, canonico %)',
            v_goal, v_papel, v_item->>'aprovador_collaborator_id', v_cong_papel::text;
        end if;

        -- (g) `vigente` confrontado com o FATO no banco (linha VIGENTE do papel)
        select count(*) into v_n_fato
          from public.evaluation_goal_approvals a
         where a.organization_id = v_alfa
           and a.goal_id = v_goal
           and a.papel = v_papel
           and a.revogado_em is null;
        if v_n_fato > 1 then
          raise exception '[FAIL] 1: mais de um fato VIGENTE de % para a meta % (unicidade parcial violada)',
            v_papel, v_goal;
        end if;
        select a.id, a.decidido_em, a.motivo
          into v_fato_id, v_fato_dec, v_fato_motivo
          from public.evaluation_goal_approvals a
         where a.organization_id = v_alfa
           and a.goal_id = v_goal
           and a.papel = v_papel
           and a.revogado_em is null;
        if (v_item->>'vigente')::boolean is distinct from (v_fato_id is not null) then
          raise exception '[FAIL] 1: `vigente` divergente do FATO em evaluation_goal_approvals (goal % papel %: projetado %, fato %)',
            v_goal, v_papel, v_item->>'vigente',
            (case when v_fato_id is null then 'sem linha vigente' else 'linha vigente' end);
        end if;
        if v_fato_id is not null then
          if coalesce(v_item->'aprovacao_id', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_fato_id), 'null'::jsonb)
             or coalesce(v_item->'decidido_em', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_fato_dec), 'null'::jsonb)
             or coalesce(v_item->'motivo', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_fato_motivo), 'null'::jsonb) then
            raise exception '[FAIL] 1: fato VIGENTE nao transportado fielmente (goal % papel %: aprovacao_id/decidido_em/motivo divergem da linha)',
              v_goal, v_papel;
          end if;
          if v_papel = 'GERENTE' and not v_exig_can then
            raise exception '[FAIL] 1: fato vigente de GERENTE com `exigida` canonica falsa (goal %)', v_goal;
          end if;
          v_n_vig := v_n_vig + 1;
        else
          -- Sem fato vigente: a projecao NAO pode inventar nem reaproveitar fato
          -- revogado.
          if v_item->>'aprovacao_id' is not null
             or v_item->>'decidido_em' is not null
             or v_item->>'motivo' is not null then
            raise exception '[FAIL] 1: papel SEM fato vigente projetou aprovacao_id/decidido_em/motivo (goal % papel %: %)',
              v_goal, v_papel, v_item;
          end if;
          if v_exig_can then
            v_n_pend := v_n_pend + 1;
          else
            v_n_exempt := v_n_exempt + 1;
            if v_cong_papel is not null then
              raise exception '[FAIL] 1: `exigida = false` com colaborador CONGELADO projetado (goal % papel %)', v_goal, v_papel;
            end if;
          end if;
        end if;
      end loop;

      -- (h) `aprovacoes_vigentes` (array legado) == MESMO fato, na mesma ordem
      select coalesce(jsonb_agg(jsonb_build_object(
               'papel', a.papel,
               'aprovacao_id', a.id,
               'decidido_em', a.decidido_em,
               'motivo', a.motivo) order by a.papel), '[]'::jsonb)
        into v_agg_can
        from public.evaluation_goal_approvals a
       where a.organization_id = v_alfa
         and a.goal_id = v_goal
         and a.revogado_em is null;
      if coalesce(v_meta->'aprovacoes_vigentes', '[]'::jsonb) is distinct from v_agg_can then
        raise exception '[FAIL] 1: `aprovacoes_vigentes` divergente do fato vigente (goal %: projetado %, canonico %)',
          v_goal, v_meta->'aprovacoes_vigentes', v_agg_can;
      end if;
    end loop;

    -- (b) COMPLETUDE: toda meta do (tenant, ciclo) que satisfaz o predicado
    --     canonico do ator DEVE estar projetada...
    select count(*) into v_falta
      from public.evaluation_goals g
     where g.organization_id = v_alfa
       and g.cycle_id = v_par.ciclo
       and (g.collaborator_id = v_vinculo
            or public.f5_10_aprovador_congelado(g.id, v_alfa, 'GERENTE') = v_vinculo
            or public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') = v_vinculo)
       and not exists (
         select 1 from jsonb_array_elements(v_res->'metas') m
          where (m->>'goal_id')::uuid = g.id);
    if v_falta <> 0 then
      raise exception '[FAIL] 1: % meta(s) AUTORIZADA(s) ausente(s) da projecao (ator %, ciclo %)',
        v_falta, v_par.ator, v_par.ciclo;
    end if;
    -- ... e NENHUMA meta fora do predicado pode entrar (prova de AUSENCIA).
    select count(*) into v_vaza
      from public.evaluation_goals g
     where g.organization_id = v_alfa
       and g.cycle_id = v_par.ciclo
       and not (g.collaborator_id = v_vinculo
                or public.f5_10_aprovador_congelado(g.id, v_alfa, 'GERENTE') = v_vinculo
                or public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') = v_vinculo)
       and exists (
         select 1 from jsonb_array_elements(v_res->'metas') m
          where (m->>'goal_id')::uuid = g.id);
    if v_vaza <> 0 then
      raise exception '[FAIL] 1: a projecao VAZOU % meta(s) SEM relacao canonica (ator %, ciclo %)',
        v_vaza, v_par.ator, v_par.ciclo;
    end if;
  end loop;

  -- (i) a leitura NAO e fato: nenhum evento novo na trilha de metas.
  select count(*) into v_ev_depois
    from public.evaluation_goal_events e where e.organization_id = v_alfa;
  if v_ev_depois <> v_ev_antes then
    raise exception '[FAIL] 1: a LEITURA gravou evento na trilha (% -> %)', v_ev_antes, v_ev_depois;
  end if;
  if v_n_pares = 0 or v_n_meta = 0 or v_n_item = 0 then
    raise exception '[FAIL] 1: nenhuma leitura exercitada (% pares, % metas, % itens)',
      v_n_pares, v_n_meta, v_n_item;
  end if;

  -- Cobertura DERIVADA do banco: se o tenant possui meta cujo COORDENADOR nao e
  -- reconhecido pela estrutura CONGELADA (=> `exigida = false`) e essa meta e
  -- legivel pelo seu dono, o estado "nao exigida" TEM de ter sido observado.
  if v_n_exempt = 0 and exists (
       select 1
         from public.evaluation_goals g
        where g.organization_id = v_alfa
          and public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') is null
          and exists (
            select 1 from public.user_profiles p
             where public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) = g.collaborator_id
               and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read'))) then
    raise exception '[FAIL] 1: o tenant possui meta sem COORDENADOR congelado legivel pelo dono, mas o estado `exigida = false` nao foi observado';
  end if;

  raise notice '[PASS] 1 (nucleo canonico): % par(es) (ator, ciclo) exercitado(s), % meta(s) projetada(s) e % item(ns) de aprovacao comparados item a item com os ORACULOS CANONICOS em tempo de execucao — relacao CONGELADA, `exigida`, `aprovador_collaborator_id`, `vigente`, `aprovacao_id`, `decidido_em`, `motivo`, `aprovacoes_vigentes` e as 5 datas soberanas (% vigente(s), % exigida(s) e pendente(s), % nao exigida(s)); nenhuma meta autorizada faltou, nenhuma meta sem relacao canonica entrou e a leitura nao gravou evento',
    v_n_pares, v_n_meta, v_n_item, v_n_vig, v_n_pend, v_n_exempt;
end $$;

-- ============================================================================
-- 2) TRANSPORTE VIVO DE UM FATO NOVO: `meta_aprovar` descoberto no banco e
--    releitura — a projecao passa a carregar EXATAMENTE a linha criada
-- ============================================================================
-- O alvo (meta, papel) e DESCOBERTO por consulta: meta do ciclo ATIVO, nao
-- excluida, cujo papel tem colaborador CONGELADO reconhecido, que ainda NAO tem
-- fato vigente e cujo ator congelado existe com `goal.approve`. Nenhum id de
-- meta, papel ou ator e literal.
do $$
declare
  v_alfa     uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_goal     uuid;
  v_papel    text;
  v_colab    uuid;
  v_ator     uuid;
  v_ciclo    uuid;
  v_ver      int;
  v_ver_ant  int;
  v_res      jsonb;
  v_leitura  jsonb;
  v_meta     jsonb;
  v_item     jsonb;
  v_id       uuid;
  v_row_id   uuid;
  v_row_dec  timestamptz;
  v_row_mot  text;
  v_row_ator uuid;
  v_row_memb uuid;
  v_n        int;
  v_op       uuid;
begin
  -- (a) DESCOBERTA do alvo (fail-closed: exige o cenario no banco).
  select g.id, p.papel, public.f5_10_aprovador_congelado(g.id, v_alfa, p.papel)
    into v_goal, v_papel, v_colab
    from public.evaluation_goals g
    cross join (values ('COORDENADOR'), ('GERENTE')) as p(papel)
   where g.organization_id = v_alfa
     and not g.excluida
     and exists (
       select 1 from public.evaluation_cycles c
        where c.id = g.cycle_id and c.organization_id = v_alfa and c.status = 'ATIVO')
     and public.f5_10_aprovador_congelado(g.id, v_alfa, p.papel) is not null
     and not exists (
       select 1 from public.evaluation_goal_approvals a
        where a.organization_id = v_alfa and a.goal_id = g.id
          and a.papel = p.papel and a.revogado_em is null)
     and exists (
       select 1 from public.user_profiles up
        where public.f5_10_vinculo_meta_do_ator(up.id, v_alfa)
                = public.f5_10_aprovador_congelado(g.id, v_alfa, p.papel)
          and public.f5_10_ator_valido_meta(up.id, v_alfa, 'goal.approve'))
   order by g.created_at, g.id, p.papel
   limit 1;
  if v_goal is null then
    raise exception '[FAIL] 2: pre-condicao: nenhuma meta do ciclo ATIVO com papel CONGELADO pendente e ator com goal.approve no banco — a prova de TRANSPORTE de um fato NOVO nao tem alvo';
  end if;
  select p.id into v_ator
    from public.user_profiles p
   where public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) = v_colab
     and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.approve')
   order by p.id
   limit 1;
  select g.cycle_id, g.version into v_ciclo, v_ver
    from public.evaluation_goals g
   where g.id = v_goal and g.organization_id = v_alfa;
  if v_ator is null or v_ciclo is null then
    raise exception '[FAIL] 2: pre-condicao: ator congelado com goal.approve ou ciclo da meta descoberta ausente';
  end if;

  -- (b) ANTES: a projecao ja do dono do papel mostra `exigida = true`,
  --     `vigente = false` e NENHUM id/data/motivo de fato.
  v_leitura := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  select m into v_meta from jsonb_array_elements(v_leitura->'metas') m where m->>'goal_id' = v_goal::text;
  if v_meta is null then
    raise exception '[FAIL] 2: a meta descoberta (%) deveria estar na leitura do seu aprovador CONGELADO', v_goal;
  end if;
  select i into v_item from jsonb_array_elements(v_meta->'aprovacoes') i where i->>'papel' = v_papel;
  if v_item is null then
    raise exception '[FAIL] 2: `aprovacoes` sem o papel descoberto (%) na meta %', v_papel, v_goal;
  end if;
  if (v_item->>'exigida')::boolean is not true
     or (v_item->>'vigente')::boolean is not false
     or v_item->>'aprovacao_id' is not null
     or v_item->>'decidido_em' is not null then
    raise exception '[FAIL] 2: ANTES de aprovar, o papel CONGELADO pendente deveria projetar exigida = true / vigente = false sem fato (%)', v_item;
  end if;
  v_ver_ant := (v_meta->>'version')::int;

  -- (c) FATO NOVO pela RPC soberana (aditivo; a fixture da P4 nao e editada).
  --     O `operation_id` e DERIVADO do alvo descoberto (helper canonico da P3,
  --     20260924000000:240-258): uma segunda execucao sobre outro alvo nunca
  --     colide com a intencao anterior.
  v_op := public.f5_10_derivar_operation_id(v_goal, 'fb-p5-2-fato-novo');
  perform set_config('dsh.p5_2_aprovacao_op', v_op::text, false);
  v_res := public.meta_aprovar(v_goal, v_alfa, v_papel,
    'aprovacao de fixture P5.2 (transporte de fato novo)', v_ver, v_ator, v_op);
  v_id := (v_res->>'aprovacao_id')::uuid;
  if v_id is null or v_res->>'aprovado' <> 'true' or v_res->>'papel' <> v_papel then
    raise exception '[FAIL] 2: a aprovacao do papel CONGELADO falhou (%)', v_res;
  end if;

  -- (d) A LINHA REAL do fato (oraculo independente da projecao).
  select a.id, a.decidido_em, a.motivo, a.actor_user_profile_id, a.actor_membership_id
    into v_row_id, v_row_dec, v_row_mot, v_row_ator, v_row_memb
    from public.evaluation_goal_approvals a
   where a.id = v_id and a.organization_id = v_alfa and a.goal_id = v_goal and a.papel = v_papel;
  if v_row_id is null then
    raise exception '[FAIL] 2: o fato devolvido por meta_aprovar (%) nao esta em evaluation_goal_approvals', v_id;
  end if;

  -- (e) DEPOIS: a projecao transporta EXATAMENTE a linha criada.
  v_leitura := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  select m into v_meta from jsonb_array_elements(v_leitura->'metas') m where m->>'goal_id' = v_goal::text;
  if v_meta is null then
    raise exception '[FAIL] 2: a meta aprovada (%) sumiu da leitura', v_goal;
  end if;
  select i into v_item from jsonb_array_elements(v_meta->'aprovacoes') i where i->>'papel' = v_papel;
  if v_item is null then
    raise exception '[FAIL] 2: `aprovacoes` sem o papel aprovado (%)', v_papel;
  end if;
  if (v_item->>'vigente')::boolean is not true
     or coalesce(v_item->'aprovacao_id', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_row_id), 'null'::jsonb)
     or coalesce(v_item->'decidido_em', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_row_dec), 'null'::jsonb)
     or coalesce(v_item->'motivo', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_row_mot), 'null'::jsonb) then
    raise exception '[FAIL] 2: a projecao NAO transportou o fato novo fielmente (goal % papel %: projetado %, linha %)',
      v_goal, v_papel, v_item, to_jsonb(v_row_id);
  end if;
  -- A identidade soberana projetada e o CONGELADO do papel, que e o colaborador
  -- do ator que decidiu (autoridade vem do snapshot, nunca do corpo).
  if coalesce(v_item->'aprovador_collaborator_id', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_colab), 'null'::jsonb)
     or public.f5_10_vinculo_meta_do_ator(v_ator, v_alfa) is distinct from v_colab
     or v_row_ator is distinct from v_ator then
    raise exception '[FAIL] 2: identidade do aprovador divergente (goal % papel %: projetado %, congelado %, ator %)',
      v_goal, v_papel, v_item->>'aprovador_collaborator_id', v_colab::text, v_ator::text;
  end if;
  if v_row_memb is null then
    raise exception '[FAIL] 2: fato sem autoria soberana de membership (%)', v_id;
  end if;
  -- Aprovacao e FATO: nao muda status/version da meta.
  if (v_meta->>'version')::int <> v_ver_ant then
    raise exception '[FAIL] 2: `meta_aprovar` nao pode alterar a version da meta (% -> %)',
      v_ver_ant, v_meta->>'version';
  end if;
  -- `aprovacoes_vigentes` (legado) passa a conter o fato novo.
  select count(*) into v_n
    from jsonb_array_elements(v_meta->'aprovacoes_vigentes') i
   where (i->>'aprovacao_id')::uuid = v_id and i->>'papel' = v_papel;
  if v_n <> 1 then
    raise exception '[FAIL] 2: `aprovacoes_vigentes` nao carrega o fato novo (%)', v_meta->'aprovacoes_vigentes';
  end if;

  raise notice '[PASS] 2 (transporte vivo de fato novo): apos `meta_aprovar` do papel DEVIDO (alvo descoberto no banco: meta %, papel %), a projecao passa a transportar `vigente = true` com `aprovacao_id`/`decidido_em`/`motivo` IDENTICOS a linha de `evaluation_goal_approvals`, `aprovador_collaborator_id` = colaborador CONGELADO (== vinculo do ator que decidiu), sem alterar `version` da meta e com `aprovacoes_vigentes` preservado',
    v_goal, v_papel;
end $$;

-- ============================================================================
-- 3) ESTADO "NAO EXIGIDA" DERIVADO DO BANCO (COORDENADOR fora da estrutura
--    CONGELADA) — a projecao carrega `exigida = false` sem identidade de fato
-- ============================================================================
-- O alvo e descoberto: meta cujo COORDENADOR nao e reconhecido pela estrutura
-- CONGELADA e cujo dono tem ator legivel. Nada e suposto sobre qual meta e essa.
do $$
declare
  v_alfa     uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_goal     uuid;
  v_ciclo    uuid;
  v_colab    uuid;
  v_ator     uuid;
  v_res      jsonb;
  v_meta     jsonb;
  v_item     jsonb;
  v_n_can    int;
  v_n_proj   int;
  v_n_ger    int;
begin
  select g.id, g.cycle_id, g.collaborator_id
    into v_goal, v_ciclo, v_colab
    from public.evaluation_goals g
   where g.organization_id = v_alfa
     and public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') is null
     and exists (
       select 1 from public.user_profiles p
        where public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) = g.collaborator_id
          and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read'))
   order by g.created_at, g.id
   limit 1;

  if v_goal is null then
    raise notice '[PASS] 3 (nao exigida): o banco NAO possui meta com COORDENADOR ausente da estrutura CONGELADA legivel pelo dono — estado nao observavel nesta fixture (nada a provar)';
    return;
  end if;

  select p.id into v_ator
    from public.user_profiles p
   where public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) = v_colab
     and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
   order by p.id
   limit 1;

  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  select m into v_meta from jsonb_array_elements(v_res->'metas') m where m->>'goal_id' = v_goal::text;
  if v_meta is null then
    raise exception '[FAIL] 3: a meta descoberta (%) deveria estar na leitura do seu dono', v_goal;
  end if;
  select i into v_item from jsonb_array_elements(v_meta->'aprovacoes') i where i->>'papel' = 'COORDENADOR';
  if v_item is null then
    raise exception '[FAIL] 3: `aprovacoes` sem o item COORDENADOR (%)', v_meta;
  end if;
  if (v_item->>'exigida')::boolean is not false
     or (v_item->>'vigente')::boolean is not false
     or v_item->>'aprovacao_id' is not null
     or v_item->>'decidido_em' is not null
     or v_item->>'motivo' is not null
     or v_item->>'aprovador_collaborator_id' is not null then
    raise exception '[FAIL] 3: COORDENADOR ausente da estrutura CONGELADA deveria projetar exigida = false, vigente = false e nenhum fato/identidade (%)', v_item;
  end if;

  -- Coerencia GLOBAL da leitura: o numero de itens COORDENADOR com
  -- `exigida = false` e igual ao numero de metas da leitura cujo COORDENADOR
  -- canonico e NULL (nenhum caso a mais, nenhum a menos).
  select count(*) into v_n_can
    from jsonb_array_elements(v_res->'metas') m
   where public.f5_10_aprovador_congelado((m->>'goal_id')::uuid, v_alfa, 'COORDENADOR') is null;
  select count(*) into v_n_proj
    from jsonb_array_elements(v_res->'metas') m
    cross join lateral jsonb_array_elements(m->'aprovacoes') i
   where i->>'papel' = 'COORDENADOR' and (i->>'exigida')::boolean is false;
  if v_n_proj <> v_n_can then
    raise exception '[FAIL] 3: `exigida = false` do COORDENADOR em % meta(s) mas o canonico reconhece % meta(s) sem COORDENADOR', v_n_proj, v_n_can;
  end if;
  -- O GERENTE e SEMPRE exigido (D15) em TODA meta projetada.
  select count(*) into v_n_ger
    from jsonb_array_elements(v_res->'metas') m
    cross join lateral jsonb_array_elements(m->'aprovacoes') i
   where i->>'papel' = 'GERENTE' and (i->>'exigida')::boolean is not true;
  if v_n_ger <> 0 then
    raise exception '[FAIL] 3: o GERENTE deveria ser SEMPRE exigido em toda meta (% meta(s) divergente(s))', v_n_ger;
  end if;

  raise notice '[PASS] 3 (nao exigida, derivada do banco): meta % (dona %) tem COORDENADOR FORA da estrutura CONGELADA e a projecao carrega `exigida = false` sem `aprovador_collaborator_id`/fato; em toda a leitura o numero de COORDENADOR nao exigido coincide com o canonico e o GERENTE permanece exigido (D15)',
    v_goal, v_colab;
end $$;

-- ============================================================================
-- 4) APROVADOR CONGELADO le meta de TERCEIRO pela relacao CONGELADA e NAO le
--    meta de quem nao e seu congelado (prova de AUSENCIA derivada)
-- ============================================================================
do $$
declare
  v_alfa    uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_goal    uuid;
  v_papel   text;
  v_colab   uuid;
  v_ator    uuid;
  v_ciclo   uuid;
  v_dono    uuid;
  v_res     jsonb;
  v_rel_esp text;
  v_n_can   int;
  v_n_proj  int;
  v_n_coord int := 0;
  v_par     record;
begin
  -- (a) O alvo e DESCOBERTO: meta cujo colaborador CONGELADO de algum papel
  --     existe, NAO e o dono e tem ator com `goal.read` (leitura de TERCEIRO).
  select g.id, p.papel, public.f5_10_aprovador_congelado(g.id, v_alfa, p.papel),
         g.cycle_id, g.collaborator_id
    into v_goal, v_papel, v_colab, v_ciclo, v_dono
    from public.evaluation_goals g
    cross join (values ('GERENTE'), ('COORDENADOR')) as p(papel)
   where g.organization_id = v_alfa
     and public.f5_10_aprovador_congelado(g.id, v_alfa, p.papel) is not null
     and public.f5_10_aprovador_congelado(g.id, v_alfa, p.papel) <> g.collaborator_id
     and exists (
       select 1 from public.user_profiles up
        where public.f5_10_vinculo_meta_do_ator(up.id, v_alfa)
                = public.f5_10_aprovador_congelado(g.id, v_alfa, p.papel)
          and public.f5_10_ator_valido_meta(up.id, v_alfa, 'goal.read'))
   order by g.created_at, g.id, p.papel
   limit 1;
  if v_goal is null then
    raise exception '[FAIL] 4: pre-condicao: nenhuma meta com aprovador CONGELADO de TERCEIRO legivel no banco — a relacao APROVADOR_*_CONGELADO nao tem alvo';
  end if;
  select p.id into v_ator
    from public.user_profiles p
   where public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) = v_colab
     and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
   order by p.id
   limit 1;
  v_rel_esp := case when v_papel = 'GERENTE'
                    then 'APROVADOR_GERENTE_CONGELADO'
                    else 'APROVADOR_COORDENADOR_CONGELADO' end;

  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  if not exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where m->>'goal_id' = v_goal::text and m->>'relacao' = v_rel_esp) then
    raise exception '[FAIL] 4: a meta de TERCEIRO % deveria vir como % para o congelado do papel % (%)',
      v_goal, v_rel_esp, v_papel, v_res->'metas';
  end if;
  -- A relacao projetada NUNCA e SELF para meta de terceiro.
  if exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where m->>'goal_id' = v_goal::text and m->>'relacao' = 'SELF') then
    raise exception '[FAIL] 4: meta de TERCEIRO projetada como SELF (%)', v_res->'metas';
  end if;

  -- (b) AUSENCIA derivada: para o MESMO ator, o conjunto projetado e EXATAMENTE
  --     o conjunto canonico do ciclo — nem uma meta a mais, nem uma a menos.
  select count(*) into v_n_can
    from public.evaluation_goals g
   where g.organization_id = v_alfa
     and g.cycle_id = v_ciclo
     and (g.collaborator_id = v_colab
          or public.f5_10_aprovador_congelado(g.id, v_alfa, 'GERENTE') = v_colab
          or public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') = v_colab);
  v_n_proj := jsonb_array_length(v_res->'metas');
  if v_n_proj <> v_n_can then
    raise exception '[FAIL] 4: o aprovador CONGELADO leu % meta(s) mas o canonico autoriza exatamente % (ciclo %)',
      v_n_proj, v_n_can, v_ciclo;
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where not exists (
       select 1 from public.evaluation_goals g
        where g.id = (m->>'goal_id')::uuid
          and g.organization_id = v_alfa
          and (g.collaborator_id = v_colab
               or public.f5_10_aprovador_congelado(g.id, v_alfa, 'GERENTE') = v_colab
               or public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') = v_colab))) then
    raise exception '[FAIL] 4: a leitura do aprovador CONGELADO VAZOU meta de quem NAO e seu congelado (%)', v_res->'metas';
  end if;

  -- (c) Cobertura adicional derivada: se existir meta de TERCEIRO cujo
  --     COORDENADOR congelado e distinto do dono e legivel, a relacao
  --     APROVADOR_COORDENADOR_CONGELADO tambem tem de aparecer.
  for v_par in
    select g.id as goal,
           public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') as colab,
           g.cycle_id as ciclo
      from public.evaluation_goals g
     where g.organization_id = v_alfa
       and public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') is not null
       and public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') <> g.collaborator_id
       and exists (
         select 1 from public.user_profiles up
          where public.f5_10_vinculo_meta_do_ator(up.id, v_alfa)
                  = public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR')
            and public.f5_10_ator_valido_meta(up.id, v_alfa, 'goal.read'))
     order by g.created_at, g.id
     limit 1
  loop
    select p.id into v_ator
      from public.user_profiles p
     where public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) = v_par.colab
       and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
     order by p.id limit 1;
    if not exists (
      select 1 from jsonb_array_elements(
               public.meta_listar_por_escopo(v_alfa, v_par.ciclo, v_ator)->'metas') m
       where m->>'goal_id' = v_par.goal::text and m->>'relacao' = 'APROVADOR_COORDENADOR_CONGELADO') then
      raise exception '[FAIL] 4: meta de TERCEIRO % deveria vir como APROVADOR_COORDENADOR_CONGELADO', v_par.goal;
    end if;
    v_n_coord := v_n_coord + 1;
  end loop;

  raise notice '[PASS] 4 (aprovador congelado): meta de TERCEIRO lida com `relacao` CONGELADA (%, papel %, ator %), sem virar SELF, com conjunto projetado EXATAMENTE igual ao canonico do ciclo (% metas) e nenhuma meta de quem nao e o congelado; casos COORDENADOR de terceiro observados: %',
    v_rel_esp, v_papel, v_ator, v_n_can, v_n_coord;
end $$;

-- ============================================================================
-- 5) DATAS SOBERANAS AO VIVO: acompanhamento -> fechamento -> exclusao logica
--    (alvo DESCOBERTO; cada passo confronta a projecao com a COLUNA)
-- ============================================================================
-- A prova nao cria meta nova (a quota do ciclo esta integralmente consumida pela
-- fixture: o trigger `trg_evaluation_goals_quota`, 20260922000000:544-597, conta
-- metas vivas por (ciclo, tipo) em TODO o ciclo). O alvo e descoberto no banco:
-- meta EM_ANDAMENTO, nao excluida, em ciclo ATIVO, cujo dono tem ator com
-- `goal.write` (SELF) — preferindo meta ainda SEM aprovacao vigente.
do $$
declare
  v_alfa     uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_goal     uuid;
  v_colab    uuid;
  v_ciclo    uuid;
  v_ver      int;
  v_ator     uuid;
  v_res      jsonb;
  v_leitura  jsonb;
  v_meta     jsonb;
  v_dua_ant  timestamptz;
  v_dfech_ant timestamptz;
  v_dexc_ant timestamptz;
  v_col_dua  timestamptz;
  v_col_dfech timestamptz;
  v_col_dexc timestamptz;
  v_criado   timestamptz;
  v_atualizado timestamptz;
  v_depois   text;
begin
  select g.id, g.collaborator_id, g.cycle_id, g.version
    into v_goal, v_colab, v_ciclo, v_ver
    from public.evaluation_goals g
   where g.organization_id = v_alfa
     and not g.excluida
     and g.status = 'EM_ANDAMENTO'
     and exists (
       select 1 from public.evaluation_cycles c
        where c.id = g.cycle_id and c.organization_id = v_alfa and c.status = 'ATIVO')
     and exists (
       select 1 from public.user_profiles p
        where public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) = g.collaborator_id
          and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.write'))
   order by (exists (
              select 1 from public.evaluation_goal_approvals a
               where a.organization_id = v_alfa and a.goal_id = g.id and a.revogado_em is null)),
            g.created_at, g.id
   limit 1;
  if v_goal is null then
    raise exception '[FAIL] 5: pre-condicao: nenhuma meta EM_ANDAMENTO de ciclo ATIVO com dono habilitado a `goal.write` — a sequencia viva de datas nao tem alvo';
  end if;
  select p.id into v_ator
    from public.user_profiles p
   where public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) = v_colab
     and public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.write')
   order by p.id limit 1;

  -- (a) ANTES: a projecao ja transporta as datas da linha (inclusive NULAS).
  v_leitura := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  select m into v_meta from jsonb_array_elements(v_leitura->'metas') m where m->>'goal_id' = v_goal::text;
  if v_meta is null then
    raise exception '[FAIL] 5: a meta descoberta (%) deveria estar na leitura do seu dono', v_goal;
  end if;
  select g.created_at, g.updated_at, g.data_ultimo_acompanhamento, g.data_fechamento, g.data_exclusao
    into v_criado, v_atualizado, v_dua_ant, v_dfech_ant, v_dexc_ant
    from public.evaluation_goals g where g.id = v_goal and g.organization_id = v_alfa;
  if v_meta->>'criado_em' is null or v_meta->>'atualizado_em' is null
     or coalesce(v_meta->'criado_em', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_criado), 'null'::jsonb)
     or coalesce(v_meta->'atualizado_em', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_atualizado), 'null'::jsonb)
     or coalesce(v_meta->'data_ultimo_acompanhamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_dua_ant), 'null'::jsonb)
     or coalesce(v_meta->'data_fechamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_dfech_ant), 'null'::jsonb)
     or coalesce(v_meta->'data_exclusao', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_dexc_ant), 'null'::jsonb) then
    raise exception '[FAIL] 5: estado inicial das datas divergente das colunas (goal %)', v_goal;
  end if;

  -- (b) ACOMPANHAMENTO => `data_ultimo_acompanhamento` AVANCA e a projecao segue a coluna.
  v_res := public.meta_atualizar_progresso(v_goal, v_alfa,
    'acompanhamento de fixture P5.2', 30, v_ver, v_ator,
    public.f5_10_derivar_operation_id(v_goal, 'fb-p5-2-progresso'));
  if (v_res->>'version')::int <> v_ver + 1 then
    raise exception '[FAIL] 5: `meta_atualizar_progresso` deveria levar a meta para version % (%)', v_ver + 1, v_res;
  end if;
  select g.data_ultimo_acompanhamento into v_col_dua
    from public.evaluation_goals g where g.id = v_goal and g.organization_id = v_alfa;
  v_leitura := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  select m into v_meta from jsonb_array_elements(v_leitura->'metas') m where m->>'goal_id' = v_goal::text;
  v_depois := v_meta->>'data_ultimo_acompanhamento';
  if v_depois is null or v_col_dua is null
     or coalesce(v_meta->'data_ultimo_acompanhamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_col_dua), 'null'::jsonb) then
    raise exception '[FAIL] 5: apos `meta_atualizar_progresso` a projecao nao transporta `data_ultimo_acompanhamento` da coluna (%)', v_meta;
  end if;
  if v_dua_ant is not null and v_col_dua <= v_dua_ant then
    raise exception '[FAIL] 5: `data_ultimo_acompanhamento` nao avancou apos o acompanhamento (% <= %)', v_col_dua, v_dua_ant;
  end if;
  if (v_meta->>'progresso_percentual')::int <> 30 then
    raise exception '[FAIL] 5: o progresso projetado deveria ser o informado (30), veio %', v_meta->>'progresso_percentual';
  end if;

  -- (c) FINALIZACAO => `data_fechamento` nasce e a projecao segue a coluna.
  v_res := public.meta_finalizar(v_goal, v_alfa, 'fechamento de fixture P5.2',
    true, v_ver + 1, v_ator,
    public.f5_10_derivar_operation_id(v_goal, 'fb-p5-2-fechar'));
  if (v_res->>'version')::int <> v_ver + 2 or v_res->>'status' <> 'ATINGIDA' then
    raise exception '[FAIL] 5: `meta_finalizar` deveria levar a meta a ATINGIDA/version % (%)', v_ver + 2, v_res;
  end if;
  select g.data_fechamento, g.data_ultimo_acompanhamento into v_col_dfech, v_col_dua
    from public.evaluation_goals g where g.id = v_goal and g.organization_id = v_alfa;
  v_leitura := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  select m into v_meta from jsonb_array_elements(v_leitura->'metas') m where m->>'goal_id' = v_goal::text;
  if v_col_dfech is null
     or coalesce(v_meta->'data_fechamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_col_dfech), 'null'::jsonb)
     or coalesce(v_meta->'data_ultimo_acompanhamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_col_dua), 'null'::jsonb)
     or v_meta->>'status' <> 'ATINGIDA'
     or (v_meta->>'atingida')::boolean is not true then
    raise exception '[FAIL] 5: apos `meta_finalizar` a projecao de datas/estado divergiu da linha (%)', v_meta;
  end if;
  if v_dfech_ant is not null and v_col_dfech <= v_dfech_ant then
    raise exception '[FAIL] 5: `data_fechamento` nao avancou apos a finalizacao (% <= %)', v_col_dfech, v_dfech_ant;
  end if;

  -- (d) EXCLUSAO LOGICA => `data_exclusao` nasce e a meta continua LEGIVEL.
  v_res := public.meta_excluir(v_goal, v_alfa, 'exclusao de fixture P5.2',
    v_ver + 2, v_ator,
    public.f5_10_derivar_operation_id(v_goal, 'fb-p5-2-excluir'));
  if (v_res->>'version')::int <> v_ver + 3 then
    raise exception '[FAIL] 5: a exclusao deveria levar a meta para version % (%)', v_ver + 3, v_res;
  end if;
  select g.data_exclusao, g.data_fechamento, g.data_ultimo_acompanhamento
    into v_col_dexc, v_col_dfech, v_col_dua
    from public.evaluation_goals g where g.id = v_goal and g.organization_id = v_alfa;
  v_leitura := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  select m into v_meta from jsonb_array_elements(v_leitura->'metas') m where m->>'goal_id' = v_goal::text;
  if v_meta is null then
    raise exception '[FAIL] 5: a meta EXCLUIDA deveria continuar legivel (leitura historica) — goal %', v_goal;
  end if;
  if v_col_dexc is null
     or (v_meta->>'excluida')::boolean is not true
     or coalesce(v_meta->'data_exclusao', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_col_dexc), 'null'::jsonb)
     or coalesce(v_meta->'data_fechamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_col_dfech), 'null'::jsonb)
     or coalesce(v_meta->'data_ultimo_acompanhamento', 'null'::jsonb) is distinct from coalesce(to_jsonb(v_col_dua), 'null'::jsonb) then
    raise exception '[FAIL] 5: apos `meta_excluir` as datas/exclusao projetadas divergiram da linha (%)', v_meta;
  end if;
  if v_dexc_ant is not null and v_col_dexc <= v_dexc_ant then
    raise exception '[FAIL] 5: `data_exclusao` nao avancou apos a exclusao (% <= %)', v_col_dexc, v_dexc_ant;
  end if;

  raise notice '[PASS] 5 (datas soberanas ao vivo): meta descoberta % percorreu acompanhamento -> finalizacao -> exclusao logica e em CADA passo a projecao transportou `data_ultimo_acompanhamento`/`data_fechamento`/`data_exclusao` IDENTICOS as colunas (datas novas, nao nulas e avancando), com `criado_em`/`atualizado_em` sempre iguais a `created_at`/`updated_at` e a meta excluida permanecendo legivel',
    v_goal;
end $$;

-- ============================================================================
-- 6) QUOTA: `limites` == `evaluation_cycle_goal_limits` do CICLO/tenant
--    (comparado com o agregado canonico) e `[]` fail-closed sem configuracao
-- ============================================================================
do $$
declare
  v_alfa     uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta     uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_ciclo    uuid;
  v_ciclo_b  uuid;
  v_ciclo_sq uuid := 'fbd10000-0000-0000-0000-000000000001';
  v_cfg      uuid;
  v_cfg_b    uuid;
  v_ator     uuid;
  v_ator_b   uuid;
  v_res      jsonb;
  v_lim_can  jsonb;
  v_n        int;
begin
  -- (a) Alfa: o ciclo ATIVO (descoberto) tem configuracao explicita.
  select c.id, c.config_version_id into v_ciclo, v_cfg
    from public.evaluation_cycles c
   where c.organization_id = v_alfa and c.status = 'ATIVO'
   order by (select count(*) from public.evaluation_goals g
              where g.organization_id = v_alfa and g.cycle_id = c.id) desc, c.id
   limit 1;
  select p.id into v_ator
    from public.user_profiles p
   where public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
     and public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) is not null
   order by p.id limit 1;
  if v_ciclo is null or v_cfg is null or v_ator is null then
    raise exception '[FAIL] 6: pre-condicao: ciclo ATIVO/configuracao/ator de Alfa ausentes';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'tipo', l.tipo, 'quantidade', l.quantidade, 'version', l.version) order by l.tipo), '[]'::jsonb)
    into v_lim_can
    from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo;
  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  if jsonb_typeof(v_res->'limites') <> 'array' then
    raise exception '[FAIL] 6: o envelope deveria trazer `limites` como array (%)', v_res->'limites';
  end if;
  if coalesce(v_res->'limites', 'null'::jsonb) is distinct from v_lim_can then
    raise exception '[FAIL] 6: `limites` divergente do agregado canonico do ciclo (projetado %, canonico %)',
      v_res->'limites', v_lim_can;
  end if;
  select count(*) into v_n from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo;
  if jsonb_array_length(v_res->'limites') <> v_n then
    raise exception '[FAIL] 6: `limites` com % item(ns) mas o ciclo tem % linha(s) de quota',
      jsonb_array_length(v_res->'limites'), v_n;
  end if;
  -- Chaves EXATAS por item e tipo dentro do dominio (o envelope nao inventa campo).
  if exists (
    select 1 from jsonb_array_elements(v_res->'limites') l
     where (l - 'tipo' - 'quantidade' - 'version') <> '{}'::jsonb) then
    raise exception '[FAIL] 6: item de `limites` com chave fora do contrato (%)', v_res->'limites';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_res->'limites') l
     where l->>'tipo' not in (select distinct l2.tipo from public.evaluation_cycle_goal_limits l2
                               where l2.organization_id = v_alfa and l2.cycle_id = v_ciclo)) then
    raise exception '[FAIL] 6: `limites` trouxe tipo que nao existe na quota do ciclo (%)', v_res->'limites';
  end if;

  -- (b) FAIL-CLOSED EXPLICITO: ciclo SEM configuracao => `[]` (nunca herda
  --     default nem copia de outro ciclo/tenant).
  --     O ciclo e criado como PLANEJADO de propositio: o tenant ja tem um ciclo
  --     ATIVO e `uq_evaluation_cycles_org_ativo` (20260915000000:117-119)
  --     admite UM unico ATIVO por organizacao; o periodo 2041 nao sobrepoe
  --     nenhum ciclo existente, respeitando `ex_evaluation_cycles_periodo_no_overlap`
  --     (20260915000000:139-149). A LEITURA nao exige ciclo ATIVO
  --     (20260928000000:207-210), de modo que o fail-closed `[]` e provado sem
  --     violar invariante de ciclo.
  insert into public.evaluation_cycles
    (id, organization_id, ano, numero, status, data_inicio, data_fim,
     data_ativacao, data_encerramento, config_version_id, version)
  values
    (v_ciclo_sq, v_alfa, 2041, 1, 'PLANEJADO', date '2041-01-01', date '2041-06-30',
     null, null, v_cfg, 1)
  on conflict (id) do nothing;
  if exists (
    select 1 from public.evaluation_cycle_goal_limits l
     where l.organization_id = v_alfa and l.cycle_id = v_ciclo_sq) then
    raise exception '[FAIL] 6: pre-condicao: o ciclo sem quota deveria estar SEM configuracao de limites';
  end if;
  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo_sq, v_ator);
  if (v_res->>'quantidade')::int <> 0
     or (v_res->'metas') <> '[]'::jsonb
     or v_res->>'relacao_ator' <> 'SEM_META_AUTORIZADA' then
    raise exception '[FAIL] 6: ciclo sem metas deveria devolver 0 metas (%)', v_res;
  end if;
  if coalesce(v_res->'limites', 'null'::jsonb) is distinct from '[]'::jsonb then
    raise exception '[FAIL] 6: ciclo SEM configuracao deveria devolver `limites = []` (fail-closed, sem default) (%)',
      v_res->'limites';
  end if;

  -- (c) OUTRO tenant: a quota vem do SEU proprio ciclo (comparada com o
  --     agregado canonico de Beta), nunca herdada de Alfa.
  select c.id, c.config_version_id into v_ciclo_b, v_cfg_b
    from public.evaluation_cycles c
   where c.organization_id = v_beta and c.status = 'ATIVO'
   order by c.id limit 1;
  select p.id into v_ator_b
    from public.user_profiles p
   where public.f5_10_ator_valido_meta(p.id, v_beta, 'goal.read')
     and public.f5_10_vinculo_meta_do_ator(p.id, v_beta) is not null
   order by p.id limit 1;
  if v_ciclo_b is null or v_ator_b is null then
    raise exception '[FAIL] 6: pre-condicao: ciclo ATIVO/ator do tenant Beta ausentes';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipo', l.tipo, 'quantidade', l.quantidade, 'version', l.version) order by l.tipo), '[]'::jsonb)
    into v_lim_can
    from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_beta and l.cycle_id = v_ciclo_b;
  v_res := public.meta_listar_por_escopo(v_beta, v_ciclo_b, v_ator_b);
  if coalesce(v_res->'limites', 'null'::jsonb) is distinct from v_lim_can then
    raise exception '[FAIL] 6: a quota do tenant Beta deveria vir do SEU ciclo (projetado %, canonico %)',
      v_res->'limites', v_lim_can;
  end if;
  if v_res->>'organization_id' <> v_beta::text or v_res->>'cycle_id' <> v_ciclo_b::text then
    raise exception '[FAIL] 6: envelope cross-tenant incoerente (%)', v_res;
  end if;

  raise notice '[PASS] 6 (quota): `limites` do envelope e IDENTICO ao agregado canonico de `evaluation_cycle_goal_limits` do (tenant, ciclo) — % item(ns) em Alfa e o proprio conjunto do ciclo de Beta —, com `{tipo, quantidade, version}` exatos, ciclo sem configuracao devolvendo `[]` (fail-closed, sem herdar default) e nenhuma chave fora do contrato',
    v_n;
end $$;

-- ============================================================================
-- 7) CROSS-TENANT / IDOR
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_ciclo  uuid;
  v_cicb   uuid;
  v_ator   uuid;
  v_atb    uuid;
  v_res    jsonb;
  v_ok     boolean;
  v_msg    text;
  v_n      int;
begin
  select p.id into v_ator
    from public.user_profiles p
   where public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
     and public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) is not null
   order by p.id limit 1;
  select c.id into v_ciclo
    from public.evaluation_cycles c
   where c.organization_id = v_alfa and c.status = 'ATIVO'
   order by c.id limit 1;
  select c.id into v_cicb
    from public.evaluation_cycles c
   where c.organization_id = v_beta
   order by c.id limit 1;
  select p.id into v_atb
    from public.user_profiles p
   where public.f5_10_ator_valido_meta(p.id, v_beta, 'goal.read')
     and public.f5_10_vinculo_meta_do_ator(p.id, v_beta) is not null
   order by p.id limit 1;
  if v_ator is null or v_ciclo is null or v_cicb is null or v_atb is null then
    raise exception '[FAIL] 7: pre-condicao: ator/ciclo de Alfa ou de Beta ausentes (fixture 25/26)';
  end if;

  -- (a) Ator de OUTRO tenant nao le a organizacao alheia (fail-closed).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_alfa, v_ciclo, v_atb);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 7: ator de outro tenant deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (b) Ciclo de OUTRO tenant => F5_10_NOT_FOUND (nunca revela existencia).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_alfa, v_cicb, v_ator);
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 7: ciclo de outro tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (c) Ciclo INEXISTENTE => F5_10_NOT_FOUND (mesmo tratamento, sem oracle).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_alfa, 'fbff0000-0000-0000-0000-0000000000ff', v_ator);
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 7: ciclo inexistente deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (d) IDOR: PARAMETROS NULOS => F5_10_INVALID_INPUT (nunca escopo global).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(null, v_ciclo, v_ator);
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 7: organization_id nulo deveria ser F5_10_INVALID_INPUT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_alfa, null, v_ator);
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 7: cycle_id nulo deveria ser F5_10_INVALID_INPUT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_alfa, v_ciclo, null);
  exception when others then v_ok := sqlerrm like '%F5_10_INVALID_INPUT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 7: ator nulo deveria ser F5_10_INVALID_INPUT (recebido %)', v_msg;
  end if;

  -- (e) NENHUMA meta de outro tenant/ciclo aparece na projecao, e toda linha
  --     devolvida pertence ao tenant E ao ciclo do ENVELOPE.
  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  if exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where (m->>'cycle_id')::uuid <> v_ciclo
        or not exists (
             select 1 from public.evaluation_goals g
              where g.id = (m->>'goal_id')::uuid
                and g.organization_id = v_alfa and g.cycle_id = v_ciclo)) then
    raise exception '[FAIL] 7: a projecao trouxe meta fora do tenant/ciclo do envelope (%)', v_res->'metas';
  end if;
  select count(*) into v_n
    from jsonb_array_elements(v_res->'metas') m
    join public.evaluation_goals g on g.id = (m->>'goal_id')::uuid
   where g.organization_id <> v_alfa;
  if v_n <> 0 then
    raise exception '[FAIL] 7: % meta(s) de OUTRO tenant na leitura de Alfa', v_n;
  end if;
  -- O tenant Beta tem metas: entao a prova acima nao e vazia.
  select count(*) into v_n from public.evaluation_goals g where g.organization_id = v_beta;
  if v_n = 0 then
    raise exception '[FAIL] 7: pre-condicao: o tenant Beta deveria ter meta de fixture (prova de ausencia sem objeto)';
  end if;

  raise notice '[PASS] 7 (cross-tenant/IDOR): ator de outro tenant => FORBIDDEN, ciclo de outro tenant/inexistente => NOT_FOUND, parametros nulos (organization_id, cycle_id e ator) => INVALID_INPUT e NENHUMA meta de outro tenant/ciclo entra na projecao (o corpo nao carrega escopo)';
end $$;

-- ============================================================================
-- 8) AUTORIZACAO NEGATIVA: capability, membership, perfil e vinculo soberano
--    (atores DESCOBERTOS pelo seu ESTADO no banco, nunca por id literal)
-- ============================================================================
do $$
declare
  v_alfa    uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_ciclo   uuid;
  v_ator    uuid;
  v_rev     uuid;
  v_dis     uuid;
  v_sem     uuid;
  v_zero    uuid;
  v_ok      boolean;
  v_msg     text;
  v_n       int;
  v_res     jsonb;
begin
  select c.id into v_ciclo
    from public.evaluation_cycles c
   where c.organization_id = v_alfa and c.status = 'ATIVO'
   order by c.id limit 1;
  if v_ciclo is null then
    raise exception '[FAIL] 8: pre-condicao: ciclo ATIVO de Alfa ausente';
  end if;

  -- (a) Ator com membership REVOGADA (nenhuma membership ATIVA no tenant).
  select m.user_profile_id into v_rev
    from public.user_organization_memberships m
   where m.organization_id = v_alfa
     and m.status <> 'active'
     and not exists (
       select 1 from public.user_organization_memberships m2
        where m2.organization_id = v_alfa and m2.user_profile_id = m.user_profile_id
          and m2.status = 'active')
   order by m.id limit 1;
  if v_rev is null then
    raise exception '[FAIL] 8: pre-condicao: nenhum ator com membership revogada no tenant (fixture 25)';
  end if;
  if public.evaluation_ator_valido(v_rev, v_alfa) then
    raise exception '[FAIL] 8: ator com membership revogada NAO pode ser ator valido';
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_alfa, v_ciclo, v_rev);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 8: membership revogada deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (b) Ator com perfil DESABILITADO e membership ativa.
  select m.user_profile_id into v_dis
    from public.user_organization_memberships m
    join public.user_profiles up on up.id = m.user_profile_id
   where m.organization_id = v_alfa and m.status = 'active' and up.status <> 'active'
   order by m.id limit 1;
  if v_dis is null then
    raise exception '[FAIL] 8: pre-condicao: nenhum ator com perfil desabilitado e membership ativa (fixture 25)';
  end if;
  if public.evaluation_ator_valido(v_dis, v_alfa) then
    raise exception '[FAIL] 8: ator com perfil desabilitado NAO pode ser ator valido';
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_alfa, v_ciclo, v_dis);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 8: perfil desabilitado deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (c) Ator SOBERANO (perfil + membership ativos) SEM `goal.read`.
  select p.id into v_sem
    from public.user_profiles p
   where public.evaluation_ator_valido(p.id, v_alfa)
     and not public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
   order by p.id limit 1;
  if v_sem is null then
    raise exception '[FAIL] 8: pre-condicao: nenhum ator soberano sem goal.read no tenant (fixture 25)';
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_alfa, v_ciclo, v_sem);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 8: ator sem goal.read deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (d) VINCULO NAO UNICO: a prova estrutural e a dos DOIS indices parciais da
  --     F5-02 (20260909010000:36-50) — com eles a ambiguidade e IMPOSSIVEL no
  --     schema (1 link ativo por membership e 1 por colaborador/tenant). O
  --     validador prova a impossibilidade E, se o banco algum dia oferecer um
  --     ator ambiguo, exige FORBIDDEN (fail-closed) para ele.
  select count(*) into v_n
    from pg_index i
   where i.indexrelid in (to_regclass('public.uq_membership_collaborator_links_active_membership'),
                          to_regclass('public.uq_membership_collaborator_links_active_collaborator'))
     and i.indisunique;
  if v_n <> 2 then
    raise exception '[FAIL] 8: os 2 indices parciais de unicidade do vinculo F5-02 deveriam existir (% de 2)', v_n;
  end if;
  select p.id into v_zero
    from public.user_profiles p
   where public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
     and public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) is null
   order by p.id limit 1;
  if v_zero is not null then
    v_ok := false; v_msg := null;
    begin
      perform public.meta_listar_por_escopo(v_alfa, v_ciclo, v_zero);
    exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
    end;
    if not v_ok then
      raise exception '[FAIL] 8: ator com capability `goal.read` SEM vinculo soberano deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
    end if;
  else
    raise notice '[PASS] 8d: o banco nao possui ator com `goal.read` e SEM vinculo soberano unico — o ramo de recusa por vinculo ausente nao foi exercitado';
  end if;
  for v_ator in
    select p.id
      from public.user_profiles p
     where (select count(*) from public.resolver_collaborador_vinculado(p.id, v_alfa)) > 1
     order by p.id
  loop
    v_ok := false; v_msg := null;
    begin
      perform public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
    exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
    end;
    if not v_ok then
      raise exception '[FAIL] 8: vinculo NAO unico deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
    end if;
  end loop;

  -- (e) Terceiro LEGITIMO sem meta autorizada: ZERO metas, mas o envelope
  --     continua trazendo a quota do ciclo (fato do CICLO, nao da relacao).
  select p.id into v_zero
    from public.user_profiles p
   where public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
     and public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) is not null
     and not exists (
       select 1 from public.evaluation_goals g
        where g.organization_id = v_alfa and g.cycle_id = v_ciclo
          and (g.collaborator_id = public.f5_10_vinculo_meta_do_ator(p.id, v_alfa)
               or public.f5_10_aprovador_congelado(g.id, v_alfa, 'GERENTE') = public.f5_10_vinculo_meta_do_ator(p.id, v_alfa)
               or public.f5_10_aprovador_congelado(g.id, v_alfa, 'COORDENADOR') = public.f5_10_vinculo_meta_do_ator(p.id, v_alfa)))
   order by p.id limit 1;
  if v_zero is not null then
    v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_zero);
    if (v_res->>'quantidade')::int <> 0
       or v_res->>'relacao_ator' <> 'SEM_META_AUTORIZADA'
       or (v_res->'metas') <> '[]'::jsonb then
      raise exception '[FAIL] 8: terceiro legitimo sem meta autorizada deveria devolver 0 metas (%)', v_res;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
             'tipo', l.tipo, 'quantidade', l.quantidade, 'version', l.version) order by l.tipo), '[]'::jsonb)
      into v_res
      from public.evaluation_cycle_goal_limits l
     where l.organization_id = v_alfa and l.cycle_id = v_ciclo;
    if v_res = '[]'::jsonb then
      raise exception '[FAIL] 8: pre-condicao: o ciclo ATIVO deveria ter quota configurada (prova de independencia)';
    end if;
  else
    raise notice '[PASS] 8e: o banco nao possui ator legitimo SEM meta autorizada no ciclo ATIVO — o ramo `SEM_META_AUTORIZADA` nao foi exercitado';
  end if;

  raise notice '[PASS] 8 (autorizacao negativa): membership REVOGADA, perfil DESABILITADO e ator sem `goal.read` recusam com F5_10_FORBIDDEN sem devolver meta; a ambiguidade de vinculo e estruturalmente IMPOSSIVEL (2 indices parciais F5-02 verificados) e, se existisse ator ambiguo, a leitura seria negada; terceiro legitimo sem meta autorizada devolve 0 metas mantendo a quota do ciclo';
end $$;

-- ============================================================================
-- 9) NAO AMPLIACAO PELO CLIENTE: assinatura inalterada + 42501
-- ============================================================================
do $$
declare
  v_args   text;
  v_n      int;
  v_ok     boolean;
  v_msg    text;
begin
  -- (a) ASSINATURA INALTERADA: exatamente os 3 parametros contratados, sem
  --     filtro adicional de colaborador/unidade/ciclo/escopo.
  v_args := lower(coalesce(pg_get_function_arguments(
    to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid)')), ''));
  if v_args <> 'p_organization_id uuid, p_cycle_id uuid, p_actor_user_profile_id uuid' then
    raise exception '[FAIL] 9: assinatura de meta_listar_por_escopo divergente do contrato (%)', v_args;
  end if;
  if position('collaborator' in v_args) > 0
     or position('unidade' in v_args) > 0
     or position('scope' in v_args) > 0
     or position('status' in v_args) > 0
     or position('version' in v_args) > 0 then
    raise exception '[FAIL] 9: assinatura expoe filtro de escopo/estado (%)', v_args;
  end if;

  -- (b) NENHUMA sobrecarga nova da mesma funcao (ampliacao de superficie).
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'meta_listar_por_escopo';
  if v_n <> 1 then
    raise exception '[FAIL] 9: meta_listar_por_escopo deveria ter exatamente 1 assinatura (%)', v_n;
  end if;

  -- (c) Parametro EXTRA falha por ASSINATURA (42883): nao existe sobrecarga que
  --     aceite "ampliar escopo" pelo corpo. Os 4 argumentos NAO pertencem a
  --     fixture de propositio: a recusa tem de vir da ASSINATURA, nunca dos dados.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(
      'fb000000-0000-0000-0000-0000000000c1', 'fb000000-0000-0000-0000-0000000000c2',
      'fb000000-0000-0000-0000-0000000000c3', 'fb000000-0000-0000-0000-0000000000c4');
  exception when others then v_ok := (sqlstate = '42883'); v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 9: parametro extra deveria falhar por ASSINATURA/42883 (recebido %)', v_msg;
  end if;

  -- (d) ACL: EXECUTE SOMENTE service_role (prova declarativa).
  if has_function_privilege('authenticated',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] 9: EXECUTE de cliente na leitura soberana';
  end if;
  if not has_function_privilege('service_role',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] 9: service_role sem EXECUTE na leitura soberana';
  end if;
  if not exists (
    select 1 from pg_proc p where p.oid = to_regprocedure(
      'public.meta_listar_por_escopo(uuid, uuid, uuid)') and not p.prosecdef
  ) then
    raise exception '[FAIL] 9: a leitura soberana deveria ser SECURITY INVOKER';
  end if;

  raise notice '[PASS] 9 (nao ampliacao): a assinatura permanece EXATAMENTE `(p_organization_id uuid, p_cycle_id uuid, p_actor_user_profile_id uuid)` (um unico overload), nenhum filtro de colaborador/unidade/ciclo/escopo e aceito, parametro extra falha por 42883 e EXECUTE de cliente nao existe';
end $$;

-- Cenario `authenticated`: chamada DIRETA negada por PERMISSAO (42501) e nenhuma
-- das 4 tabelas de metas e legivel pelo cliente. O claim e apenas a identidade
-- autenticada do cenario (nenhum valor de fixture e asserido).
select set_config('request.jwt.claim.sub', 'fb000000-0000-0000-0000-0000000000d4', false);
set role authenticated;

do $$
declare
  -- A recusa tem de ser por PERMISSAO (42501), independentemente dos valores:
  -- os parametros NAO pertencem a fixture (nenhuma expectativa de dado aqui).
  v_org   uuid := 'fb000000-0000-0000-0000-0000000000d1';
  v_ciclo uuid := 'fb000000-0000-0000-0000-0000000000d2';
  v_ator  uuid := 'fb000000-0000-0000-0000-0000000000d3';
  v_ok    boolean;
  v_st    text;
  v_tab   text;
  v_n     int;
begin
  v_ok := false; v_st := null;
  begin
    perform public.meta_listar_por_escopo(v_org, v_ciclo, v_ator);
  exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
            when others then v_st := sqlstate;
  end;
  if not v_ok or v_st <> '42501' then
    raise exception '[FAIL] 9b: chamada DIRETA por authenticated deveria ser NEGADA por permissao (42501), veio %', v_st;
  end if;

  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    v_ok := false; v_st := null;
    begin
      execute format('select count(*) from public.%I', v_tab) into v_n;
    exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
              when others then v_st := sqlstate;
    end;
    if not v_ok or v_st <> '42501' then
      raise exception '[FAIL] 9b: SELECT do cliente em % deveria ser 42501, veio %', v_tab, v_st;
    end if;
  end loop;

  raise notice '[PASS] 9b (cliente `authenticated`): a leitura soberana e as 4 tabelas de metas negam o cliente por PERMISSAO (42501) — nenhuma superficie nova, nenhuma leitura direta';
end $$;

reset role;

set role anon;
do $$
declare
  v_ok  boolean;
  v_st  text;
  v_tab text;
  v_n   int;
begin
  if has_function_privilege('anon', 'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] 9c: anon com EXECUTE na leitura soberana';
  end if;
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    v_ok := false; v_st := null;
    begin
      execute format('select count(*) from public.%I', v_tab) into v_n;
    exception when insufficient_privilege then v_ok := true; v_st := sqlstate;
              when others then v_st := sqlstate;
    end;
    if not v_ok or v_st <> '42501' then
      raise exception '[FAIL] 9c: SELECT de anon em % deveria ser 42501, veio %', v_tab, v_st;
    end if;
  end loop;
  raise notice '[PASS] 9c (cliente `anon`): nenhum EXECUTE e nenhuma leitura (42501) nas 4 tabelas de metas';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ============================================================================
-- 10) REGRESSAO + CONJUNTO EXATO DE CHAVES DO PAYLOAD + GUARDA ESTATICA DA
--     PROJECAO (nenhuma estrutura VIVA entra na leitura)
-- ============================================================================
do $$
declare
  v_alfa    uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_ciclo   uuid;
  v_ator    uuid;
  v_res     jsonb;
  v_meta    jsonb;
  v_env_esp text[] := array['organization_id', 'cycle_id', 'ciclo_status', 'relacao_ator',
                             'quantidade', 'limites', 'metas'];
  v_env_ant text[] := array['organization_id', 'cycle_id', 'ciclo_status', 'relacao_ator',
                             'quantidade', 'metas'];
  v_meta_esp text[] := array['goal_id', 'cycle_id', 'collaborator_id', 'tipo', 'descricao',
                             'kpi', 'valor_alvo', 'status', 'progresso_percentual',
                             'resultado_atual', 'resultado_final', 'atingida', 'excluida',
                             'version', 'relacao', 'aprovacoes_vigentes',
                             'criado_em', 'atualizado_em', 'data_ultimo_acompanhamento',
                             'data_fechamento', 'data_exclusao', 'aprovacoes'];
  v_meta_base text[] := array['goal_id', 'cycle_id', 'collaborator_id', 'tipo', 'descricao',
                              'kpi', 'valor_alvo', 'status', 'progresso_percentual',
                              'resultado_atual', 'resultado_final', 'atingida', 'excluida',
                              'version', 'relacao', 'aprovacoes_vigentes'];
  v_ap_esp  text[] := array['papel', 'exigida', 'vigente', 'aprovacao_id', 'decidido_em',
                            'motivo', 'aprovador_collaborator_id'];
  v_reais   text[];
  v_k       text;
  v_def     text;
  v_n       int;
  v_ev_antes bigint;
  v_ev_depois bigint;
begin
  select c.id into v_ciclo
    from public.evaluation_cycles c
   where c.organization_id = v_alfa and c.status = 'ATIVO'
   order by (select count(*) from public.evaluation_goals g
              where g.organization_id = v_alfa and g.cycle_id = c.id) desc, c.id
   limit 1;
  select p.id into v_ator
    from public.user_profiles p
   where public.f5_10_ator_valido_meta(p.id, v_alfa, 'goal.read')
     and public.f5_10_vinculo_meta_do_ator(p.id, v_alfa) is not null
   order by p.id limit 1;
  select count(*) into v_ev_antes from public.evaluation_goal_events e where e.organization_id = v_alfa;
  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_ator);
  select count(*) into v_ev_depois from public.evaluation_goal_events e where e.organization_id = v_alfa;
  if v_ev_depois <> v_ev_antes then
    raise exception '[FAIL] 10: a leitura gravou evento na trilha (% -> %)', v_ev_antes, v_ev_depois;
  end if;

  -- (a) Envelope: TODAS as chaves anteriores continuam presentes + `limites`,
  --     e o conjunto e EXATO (nem chave extra, nem perdida).
  foreach v_k in array v_env_ant loop
    if not (v_res ? v_k) then
      raise exception '[FAIL] 10: o envelope PERDEU a chave % (regressao)', v_k;
    end if;
  end loop;
  foreach v_k in array v_env_esp loop
    if not (v_res ? v_k) then
      raise exception '[FAIL] 10: o envelope deveria trazer a chave %', v_k;
    end if;
  end loop;
  select array_agg(k) into v_reais from (select jsonb_object_keys(v_res) as k) t;
  if (select array_agg(x order by x) from unnest(v_reais) x)
     <> (select array_agg(x order by x) from unnest(v_env_esp) x) then
    raise exception '[FAIL] 10: conjunto EXATO de chaves do envelope divergente (%)', to_jsonb(v_reais);
  end if;

  -- (b) Coerencia das chaves historicas.
  if v_res->>'organization_id' <> v_alfa::text
     or v_res->>'cycle_id' <> v_ciclo::text
     or v_res->>'ciclo_status' <> 'ATIVO'
     or v_res->>'relacao_ator' <> 'ESCOPO_APLICADO' then
    raise exception '[FAIL] 10: chaves historicas do envelope incoerentes (%)', v_res;
  end if;
  if (v_res->>'quantidade')::int <> jsonb_array_length(v_res->'metas') then
    raise exception '[FAIL] 10: `quantidade` deveria ser o tamanho de `metas` (%)', v_res;
  end if;

  -- (c) Cada meta: chaves EXATAS (as 16 anteriores + as 6 da P5.2), `aprovacoes`
  --     SEMPRE com os dois papeis e CADA item com as 7 chaves do contrato.
  for v_meta in select m from jsonb_array_elements(v_res->'metas') m loop
    foreach v_k in array v_meta_base loop
      if not (v_meta ? v_k) then
        raise exception '[FAIL] 10: a meta PERDEU a chave % (regressao) (goal %)', v_k, v_meta->>'goal_id';
      end if;
    end loop;
    foreach v_k in array v_meta_esp loop
      if not (v_meta ? v_k) then
        raise exception '[FAIL] 10: a meta deveria trazer a chave % (goal %)', v_k, v_meta->>'goal_id';
      end if;
    end loop;
    select array_agg(k) into v_reais from (select jsonb_object_keys(v_meta) as k) t;
    if (select array_agg(x order by x) from unnest(v_reais) x)
       <> (select array_agg(x order by x) from unnest(v_meta_esp) x) then
      raise exception '[FAIL] 10: conjunto EXATO de chaves da meta divergente (goal_id=%) (%)',
        v_meta->>'goal_id', to_jsonb(v_reais);
    end if;
    if jsonb_array_length(v_meta->'aprovacoes') <> 2
       or v_meta->'aprovacoes'->0->>'papel' <> 'COORDENADOR'
       or v_meta->'aprovacoes'->1->>'papel' <> 'GERENTE' then
      raise exception '[FAIL] 10: `aprovacoes` com os dois papeis/ordem divergente (goal %)', v_meta->>'goal_id';
    end if;
    for v_n in 0 .. 1 loop
      foreach v_k in array v_ap_esp loop
        if not (v_meta->'aprovacoes'->v_n ? v_k) then
          raise exception '[FAIL] 10: item de `aprovacoes` sem a chave % (goal % posicao %)',
            v_k, v_meta->>'goal_id', v_n;
        end if;
      end loop;
      select array_agg(k) into v_reais
        from (select jsonb_object_keys(v_meta->'aprovacoes'->v_n) as k) t;
      if (select array_agg(x order by x) from unnest(v_reais) x)
         <> (select array_agg(x order by x) from unnest(v_ap_esp) x) then
        raise exception '[FAIL] 10: conjunto EXATO de chaves do item de `aprovacoes` divergente (goal % posicao %)',
          v_meta->>'goal_id', v_n;
      end if;
    end loop;
    if jsonb_typeof(v_meta->'aprovacoes_vigentes') <> 'array' then
      raise exception '[FAIL] 10: `aprovacoes_vigentes` deveria continuar sendo array (%)', v_meta;
    end if;
  end loop;

  -- (d) Prova ESTATICA de que a PROJECAO conservou as chaves antigas (o
  --     `create or replace` nao removeu nenhuma) e acrescentou as novas.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid)');
  foreach v_k in array array['''goal_id''', '''cycle_id''', '''collaborator_id''', '''tipo''',
                             '''descricao''', '''kpi''', '''valor_alvo''', '''status''',
                             '''progresso_percentual''', '''resultado_atual''',
                             '''resultado_final''', '''atingida''', '''excluida''',
                             '''version''', '''relacao''', '''aprovacoes_vigentes''',
                             '''criado_em''', '''atualizado_em''',
                             '''data_ultimo_acompanhamento''', '''data_fechamento''',
                             '''data_exclusao''', '''aprovacoes''', '''papel''',
                             '''exigida''', '''vigente''', '''aprovacao_id''',
                             '''decidido_em''', '''motivo''',
                             '''aprovador_collaborator_id''', '''limites'''] loop
    if position(v_k in v_def) = 0 then
      raise exception '[FAIL] 10: a projecao da funcao perdeu a chave %', v_k;
    end if;
  end loop;
  -- O gate funcional e o predicado CONGELADO continuam identicos aos da P4.
  if position('f5_10_exigir_autorizacao_meta' in v_def) = 0
     or position('''LER''' in v_def) = 0
     or position('f5_10_vinculo_meta_do_ator' in v_def) = 0
     or position('f5_10_aprovador_congelado' in v_def) = 0
     or position('F5_10_NOT_FOUND' in v_def) = 0
     or position('SEM_META_AUTORIZADA' in v_def) = 0
     or position('ESCOPO_APLICADO' in v_def) = 0 then
    raise exception '[FAIL] 10: a leitura perdeu o gate funcional, o vinculo soberano ou o predicado congelado da P4';
  end if;
  -- A projecao NAO usa estrutura VIVA nem o resolver vivo: a identidade do
  -- aprovador vem do snapshot CONGELADO (f5_10_aprovador_congelado).
  if position('resolver_collaborator_vinculado' in v_def) > 0
     or position('position_reporting_lines' in v_def) > 0
     or position('organizacao_resolver_gestor_direto' in v_def) > 0
     or position('occupations' in v_def) > 0 then
    raise exception '[FAIL] 10: a projecao da leitura passou a depender de ESTRUTURA VIVA (contrato D14/D25 proibe)';
  end if;
  -- A quota vem do tenant/ciclo do envelope e a aprovacao vigente exige
  -- `revogado_em is null` (fato vivo).
  if position('evaluation_cycle_goal_limits' in v_def) = 0
     or position('a.organization_id = v_org' in v_def) = 0
     or position('a.revogado_em is null' in v_def) = 0 then
    raise exception '[FAIL] 10: a projecao de quota/aprovacao perdeu o filtro de tenant ou de fato vigente';
  end if;

  raise notice '[PASS] 10 (regressao + payload exato): o envelope mantem as 6 chaves anteriores e acrescenta `limites` (conjunto EXATO de 7); cada meta mantem as 16 chaves anteriores e acrescenta exatamente as 6 da P5.2 (22 chaves exatas) e cada item de `aprovacoes` traz exatamente as 7 chaves contratadas; a projecao estatica conserva o gate, o vinculo soberano, o predicado CONGELADO e a quota — e NAO usa estrutura viva nem resolver vivo; a leitura nao grava evento';
end $$;

-- ============================================================================
-- 11) GUARDA FINAL FAIL-CLOSED: superficie inalterada e estado consolidado
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_tab    text;
  v_priv   text;
  v_n      int;
  v_sec    boolean;
  v_cfg    text;
  v_op     text;
  v_erros  text[] := array[]::text[];
begin
  -- (a) A superficie autorizada NAO mudou: 1 overload, INVOKER, search_path fixo
  --     e EXECUTE somente service_role.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'meta_listar_por_escopo';
  if v_n <> 1 then
    v_erros := v_erros || format('overloads de meta_listar_por_escopo = %s (esperado 1)', v_n);
  end if;
  select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '')
    into v_sec, v_cfg
    from pg_proc p where p.oid = to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid)');
  if v_sec then
    v_erros := v_erros || 'meta_listar_por_escopo virou SECURITY DEFINER'::text;
  end if;
  if position('search_path=public' in v_cfg) = 0 then
    v_erros := v_erros || 'meta_listar_por_escopo sem search_path = public'::text;
  end if;
  if has_function_privilege('authenticated', 'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    v_erros := v_erros || 'EXECUTE exposto a cliente na leitura soberana'::text;
  end if;
  if not has_function_privilege('service_role', 'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    v_erros := v_erros || 'service_role sem EXECUTE na leitura soberana'::text;
  end if;

  -- (b) As 4 tabelas de metas continuam deny-by-default INTEGRAL.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_n <> 0 then
      v_erros := v_erros || format('%s com %s policy(ies)', v_tab, v_n);
    end if;
    foreach v_priv in array array[
      'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      if has_table_privilege('authenticated', format('public.%I', v_tab), v_priv) then
        v_erros := v_erros || format('%s: authenticated com %s', v_tab, v_priv);
      end if;
      if has_table_privilege('anon', format('public.%I', v_tab), v_priv) then
        v_erros := v_erros || format('%s: anon com %s', v_tab, v_priv);
      end if;
    end loop;
    if has_table_privilege('service_role', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('service_role', format('public.%I', v_tab), 'TRUNCATE') then
      v_erros := v_erros || format('%s: service_role com DELETE/TRUNCATE', v_tab);
    end if;
  end loop;

  -- (c) Nenhuma funcao de meta nova (anti-escopo) e catalogo intacto.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%')
     and p.proname <> all (array[
       'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
       'meta_revisar_finalizacao', 'meta_excluir', 'meta_definir_limites_do_ciclo',
       'meta_aprovar', 'meta_invalidar_aprovacoes', 'meta_listar_por_escopo']);
  if v_n <> 0 then
    v_erros := v_erros || format('%s funcao(oes) de meta fora do contrato', v_n);
  end if;
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_erros := v_erros || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  -- (d) Nenhum SECURITY DEFINER novo em `public` (whitelist D22-A de 4 nomes).
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname <> all (array[
       'conceder_acesso_role', 'criar_perfil_membership',
       'resolver_capabilities_efetivas', 'revogar_acesso_role']);
  if v_n <> 0 then
    v_erros := v_erros || format('SECURITY DEFINER novo em public = %s (esperado 0)', v_n);
  end if;

  -- (e) Estado consolidado DERIVADO: a fixture da P4 continua integra (nenhuma
  --     meta do namespace `f2000000` foi criada ou removida por este validador),
  --     o tenant Beta continua com meta, e o FATO aditivo criado no bloco 2
  --     continua VIGENTE (a prova de transporte vivo nao foi revertida).
  select count(*) into v_n from public.evaluation_goals
   where organization_id in (v_alfa, v_beta) and id::text like 'f2000000%';
  if v_n <> 7 then
    v_erros := v_erros || format('metas da fixture = %s (esperado 7 — este validador nao cria nem remove meta de fixture)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_goals
   where organization_id = v_beta;
  if v_n = 0 then
    v_erros := v_erros || 'o tenant Beta ficou sem meta de fixture'::text;
  end if;
  v_op := current_setting('dsh.p5_2_aprovacao_op', true);
  if v_op is null or v_op = '' then
    v_erros := v_erros || 'o bloco 2 nao registrou o `operation_id` do fato aditivo'::text;
  else
    select count(*) into v_n
      from public.evaluation_goal_events e
      join public.evaluation_goal_approvals a
        on a.id = e.result_entity_id and a.organization_id = e.organization_id
     where e.organization_id = v_alfa
       and e.operation_id::text = v_op
       and e.event_type in ('APROVACAO_COORDENADOR', 'APROVACAO_GERENTE')
       and a.revogado_em is null;
    if v_n <> 1 then
      v_erros := v_erros || format('o fato aditivo do bloco 2 deveria continuar VIGENTE (encontrado %s)', v_n);
    end if;
  end if;

  -- (f) Nenhum vinculo de teste deixado ATIVO pelo namespace do validador.
  select count(*) into v_n from public.membership_collaborator_links l
   where l.id::text like 'fb%' and l.status = 'active';
  if v_n <> 0 then
    v_erros := v_erros || 'vinculo do namespace do validador ficou ATIVO'::text;
  end if;

  if array_length(v_erros, 1) is not null then
    raise exception '[FAIL] guarda final da P5.2: %', array_to_string(v_erros, '; ');
  end if;

  raise notice '[PASS] guarda final: mesma assinatura/ACL da leitura soberana (1 overload, INVOKER, search_path fixo, EXECUTE so service_role), 4 tabelas de metas deny-by-default integral, nenhuma funcao de meta nova, catalogo intacto (8 goal.%%/observation.%%), nenhum SECURITY DEFINER novo, fixture da P4 integra e fato aditivo do bloco 2 vigente';
end $$;

-- ============================================================================
-- 12) Resumo
-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F5-10 P5.2: PROJECAO da leitura soberana de metas validada POR TRANSPORTE — cada meta projetada e cada papel de `aprovacoes` foram confrontados EM TEMPO DE EXECUCAO com os oraculos canonicos (f5_10_aprovador_congelado, evaluation_goal_approvals, evaluation_goals, evaluation_cycle_goal_limits), sem nenhuma expectativa literal de fixture.';
  raise notice '============================================================';
end $$;

do $$
begin
  raise notice '[PASS] F5-10 P5.2: validacao concluida — a superficie autorizada NAO mudou (mesma assinatura, mesmo conjunto de linhas, EXECUTE somente service_role) e apenas a PROJECAO foi estendida (datas soberanas, aprovacoes por papel e quota do ciclo)';
end $$;
