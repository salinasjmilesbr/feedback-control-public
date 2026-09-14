-- ============================================================================
-- F5-10 P5.2 (Issue #222) — LEITURA SOBERANA DE METAS: PROJECAO estendida
-- ----------------------------------------------------------------------------
-- Contrato FECHADO: docs/F5-10-P5.2-contrato-leitura-soberana-metas.md
--
-- DECISAO DE DESENHO (minimizacao): a SUPERFICIE AUTORIZADA NAO MUDA. O
-- predicado de `meta_listar_por_escopo` (P4) ja e exatamente
-- `SELF ∪ APROVADOR_GERENTE_CONGELADO ∪ APROVADOR_COORDENADOR_CONGELADO`
-- (`20260925000000_f5_10_p4_authorization_rls.sql:2194-2239`), derivado de
-- `f5_10_aprovador_congelado` (P3) — nunca de estrutura viva. Esta migration e
-- ESTRITAMENTE ADITIVA NA PROJECAO:
--   - MESMA assinatura `public.meta_listar_por_escopo(uuid, uuid, uuid)`;
--   - MESMO conjunto de linhas autorizadas e MESMO gate funcional
--     (`f5_10_exigir_autorizacao_meta('LER', ...)` + vinculo soberano unico);
--   - ZERO capability nova, ZERO policy nova, ZERO grant novo, ZERO RPC nova,
--     ZERO SECURITY DEFINER novo, ZERO mudanca de RLS;
--   - a P4 (`20260925000000:2154`) NAO e editada (migration historica).
--
-- PROJECAO ADICIONADA (por meta): `criado_em`, `atualizado_em`,
-- `data_ultimo_acompanhamento`, `data_fechamento`, `data_exclusao` e
-- `aprovacoes[]` (sempre os DOIS papeis, na ordem COORDENADOR, GERENTE, com
-- `papel`/`exigida`/`vigente`/`aprovacao_id`/`decidido_em`/`motivo`/
-- `aprovador_collaborator_id`). No envelope: `limites` (quota do ciclo).
-- `aprovacoes_vigentes[]` PERMANECE (compatibilidade).
--
-- LIMITACAO REGISTRADA (contrato §4 — fail-closed, NAO e autoridade nova):
-- `f5_10_aprovador_congelado` devolve NULL tanto para "coordenador nao distinto
-- da cadeia" (=> nao exigida) quanto para "estrutura congelada nao reconhecida"
-- (avaliacao ausente/duplicada/ocorrencia encerrada). A projecao NAO distingue
-- os dois casos para o papel COORDENADOR: distinguir exigiria duplicar a regra
-- de P3 na leitura (fonte unica proibida). O caminho de MUTACAO continua
-- fail-closed (`meta_aprovar` recusa papel nao reconhecido, P3), de modo que o
-- estado ambiguo nunca vira aprovacao.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) PREFLIGHT FAIL-CLOSED: o estado de partida e EXATAMENTE o estado da P4/P5
-- ----------------------------------------------------------------------------
-- Qualquer divergencia aborta a migration inteira (nada "meio aplicado"). Se o
-- preflight falhar, NENHUM objeto foi alterado — a funcao continua a da P4.
do $$
declare
  v_oid      oid;
  v_secdef   boolean;
  v_cfg      text;
  v_n        integer;
  v_tab      text;
  v_priv     text;
  v_falhas   text[] := array[]::text[];
  v_org_cols text;
begin
  -- (a) A assinatura soberana existe e continua sendo SECURITY INVOKER com
  --     `search_path = public` (o `create or replace` desta migration exige a
  --     assinatura EXATA; uma assinatura divergente criaria OVERLOAD e ampliaria
  --     a superficie).
  v_oid := to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid)');
  if v_oid is null then
    raise exception
      'F5_10_P5_2_PREFLIGHT: assinatura public.meta_listar_por_escopo(uuid, uuid, uuid) ausente (estado de partida invalido)';
  end if;

  select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '')
    into v_secdef, v_cfg
    from pg_proc p
   where p.oid = v_oid;
  if v_secdef then
    v_falhas := v_falhas || 'meta_listar_por_escopo deveria ser SECURITY INVOKER no estado de partida'::text;
  end if;
  if position('search_path=public' in v_cfg) = 0 then
    v_falhas := v_falhas || 'meta_listar_por_escopo deveria fixar search_path = public'::text;
  end if;

  -- (b) EXECUTE SOMENTE de `service_role` — nem `authenticated` nem `anon`.
  if not has_function_privilege('service_role',
         'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    v_falhas := v_falhas || 'service_role sem EXECUTE em meta_listar_por_escopo'::text;
  end if;
  if has_function_privilege('authenticated',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    v_falhas := v_falhas || 'meta_listar_por_escopo exposta a cliente (authenticated/anon)'::text;
  end if;

  -- (c) As 4 tabelas de metas continuam DENY-BY-DEFAULT INTEGRAL: ZERO policy e
  --     ZERO privilegio de cliente (D22-A, `20260927000000:77-98`).
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    select count(*) into v_n
      from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_n <> 0 then
      v_falhas := v_falhas || format('%s com %s policy(ies) no estado de partida (D22-A exige zero)', v_tab, v_n);
    end if;
    foreach v_priv in array array[
      'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      if has_table_privilege('authenticated', format('public.%I', v_tab), v_priv) then
        v_falhas := v_falhas || format('%s: authenticated com %s no estado de partida', v_tab, v_priv);
      end if;
      if has_table_privilege('anon', format('public.%I', v_tab), v_priv) then
        v_falhas := v_falhas || format('%s: anon com %s no estado de partida', v_tab, v_priv);
      end if;
    end loop;
  end loop;

  -- (d) Catalogo intacto: 8 capabilities `goal.%%` + `observation.%` (D6).
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  -- (e) A tabela de limites existe, com `organization_id` (a autorizacao desta
  --     projecao NAO afrouxa nada: o filtro e sempre o tenant do envelope) e com
  --     a unicidade `(cycle_id, tipo)` exigida pelo contrato §5.
  if to_regclass('public.evaluation_cycle_goal_limits') is null then
    raise exception
      'F5_10_P5_2_PREFLIGHT: public.evaluation_cycle_goal_limits ausente (a quota do ciclo e pre-requisito da projecao)';
  end if;
  select string_agg(a.attname, ',' order by a.attname) into v_org_cols
    from pg_attribute a
   where a.attrelid = 'public.evaluation_cycle_goal_limits'::regclass
     and a.attname in ('organization_id', 'cycle_id', 'tipo', 'quantidade', 'version')
     and a.attnum > 0 and not a.attisdropped;
  if v_org_cols is distinct from 'cycle_id,organization_id,quantidade,tipo,version' then
    v_falhas := v_falhas || format('evaluation_cycle_goal_limits sem as colunas do contrato (%)', coalesce(v_org_cols, '<nenhuma>'));
  end if;

  select count(*) into v_n
    from pg_constraint c
   where c.conrelid = 'public.evaluation_cycle_goal_limits'::regclass
     and c.contype = 'u'
     and pg_get_constraintdef(c.oid) like '%(cycle_id, tipo)%';
  if v_n <> 1 then
    v_falhas := v_falhas || format('unique (cycle_id, tipo) da quota = %s (esperado 1)', v_n);
  end if;

  -- (f) `service_role` continua EXECUTOR TECNICO da matriz da P1 (sem
  --     DELETE/TRUNCATE) nas 4 tabelas de metas.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if has_table_privilege('service_role', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('service_role', format('public.%I', v_tab), 'TRUNCATE') then
      v_falhas := v_falhas || format('%s: service_role com DELETE/TRUNCATE no estado de partida', v_tab);
    end if;
  end loop;

  if array_length(v_falhas, 1) is not null then
    raise exception
      'F5_10_P5_2_PREFLIGHT: estado de partida divergente do contrato: %',
      array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-10 P5.2: preflight OK (superficie soberana INVOKER com search_path fixo e EXECUTE so service_role, 4 tabelas de metas deny-by-default integral, catalogo com 8 goal.%%/observation.%%, quota com unique (cycle_id, tipo))';
end $$;

-- ----------------------------------------------------------------------------
-- 1) `meta_listar_por_escopo` — MESMA assinatura, MESMO conjunto de linhas
-- ----------------------------------------------------------------------------
-- O predicado de autorizacao (gate funcional + ciclo do mesmo tenant + SELF ∪
-- aprovador congelado) e COPIADO SEM ALTERACAO da P4
-- (`20260925000000_f5_10_p4_authorization_rls.sql:2172-2248`). Apenas a
-- PROJECAO foi estendida.
create or replace function public.meta_listar_por_escopo(
  p_organization_id uuid,
  p_cycle_id uuid,
  p_actor_user_profile_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_org       uuid := p_organization_id;
  v_vinculo   uuid;
  v_ciclo     text;
  v_metas     jsonb;
  v_limites   jsonb;
  v_qtd       integer;
begin
  if p_organization_id is null or p_cycle_id is null
     or p_actor_user_profile_id is null then
    raise exception
      'F5_10_INVALID_INPUT: organization_id, cycle_id e actor sao obrigatorios';
  end if;

  -- (1) Gate funcional `goal.read` (capability efetiva + vinculo soberano unico).
  perform public.f5_10_exigir_autorizacao_meta(
    'LER', p_actor_user_profile_id, v_org, null, null);

  v_vinculo := public.f5_10_vinculo_meta_do_ator(
                 p_actor_user_profile_id, v_org);

  -- (2) Ciclo do MESMO tenant (a leitura e sempre escopada por ciclo).
  select c.status into v_ciclo
    from public.evaluation_cycles c
   where c.id = p_cycle_id
     and c.organization_id = v_org;
  if not found then
    raise exception 'F5_10_NOT_FOUND: ciclo inexistente ou de outro tenant';
  end if;

  -- (3) Linhas AUTORIZADAS: SELF (dono) ou relacao CONGELADA do papel.
  --     A PROJECAO (P5.2) acrescenta as datas soberanas, o estado de aprovacao
  --     por papel e — no envelope — a quota do ciclo.
  select coalesce(jsonb_agg(x.meta order by x.ordem), '[]'::jsonb), count(*)
    into v_metas, v_qtd
    from (
      select g.id as ordem,
             jsonb_build_object(
               'goal_id', g.id,
               'cycle_id', g.cycle_id,
               'collaborator_id', g.collaborator_id,
               'tipo', g.tipo,
               'descricao', g.descricao,
               'kpi', g.kpi,
               'valor_alvo', g.valor_alvo,
               'status', g.status,
               'progresso_percentual', g.progresso_percentual,
               'resultado_atual', g.resultado_atual,
               'resultado_final', g.resultado_final,
               'atingida', g.atingida,
               'excluida', g.excluida,
               'version', g.version,
               'relacao',
                 case
                   when g.collaborator_id = v_vinculo then 'SELF'
                   when public.f5_10_aprovador_congelado(g.id, v_org, 'GERENTE') = v_vinculo
                     then 'APROVADOR_GERENTE_CONGELADO'
                   else 'APROVADOR_COORDENADOR_CONGELADO'
                 end,
               'aprovacoes_vigentes', coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'papel', a.papel,
                          'aprovacao_id', a.id,
                          'decidido_em', a.decidido_em,
                          'motivo', a.motivo) order by a.papel)
                   from public.evaluation_goal_approvals a
                  where a.organization_id = v_org
                    and a.goal_id = g.id
                    and a.revogado_em is null), '[]'::jsonb),
               -- (P5.2) datas SOBERANAS da linha (nunca datas do cliente).
               'criado_em', g.created_at,
               'atualizado_em', g.updated_at,
               'data_ultimo_acompanhamento', g.data_ultimo_acompanhamento,
               'data_fechamento', g.data_fechamento,
               'data_exclusao', g.data_exclusao,
               -- (P5.2) estado de aprovacao por PAPEL: SEMPRE os dois papeis, na
               -- ordem COORDENADOR, GERENTE (a UI nao reconstroi a regra).
               'aprovacoes', coalesce((
                 select jsonb_agg(y.fato order by y.posicao)
                   from (
                     select case p.papel when 'COORDENADOR' then 1 else 2 end as posicao,
                            jsonb_build_object(
                              'papel', p.papel,
                              -- D15: GERENTE e SEMPRE exigida; COORDENADOR so
                              -- quando o snapshot CONGELADO o reconhece
                              -- (fail-closed: estrutura nao reconhecida => false).
                              'exigida',
                                case p.papel
                                  when 'GERENTE' then true
                                  else public.f5_10_aprovador_congelado(
                                         g.id, v_org, 'COORDENADOR') is not null
                                end,
                              'vigente', (a.id is not null),
                              'aprovacao_id', a.id,
                              'decidido_em', a.decidido_em,
                              'motivo', a.motivo,
                              -- Identidade SOBERANA do aprovador: o colaborador
                              -- CONGELADO do papel (P3): meta_aprovar FORCA o ator a ser o
                              -- colaborador congelado (P3/REP), entao o fato e a
                              -- fonte unica - nunca autoria vinda do corpo.
                              'aprovador_collaborator_id',
                                public.f5_10_aprovador_congelado(g.id, v_org, p.papel)
                            ) as fato
                       from (values ('COORDENADOR'), ('GERENTE')) as p(papel)
                       left join public.evaluation_goal_approvals a
                         on a.organization_id = v_org
                        and a.goal_id = g.id
                        and a.papel = p.papel
                        and a.revogado_em is null
                   ) y), '[]'::jsonb)
             ) as meta
        from public.evaluation_goals g
       where g.organization_id = v_org
         and g.cycle_id = p_cycle_id
         and (
           g.collaborator_id = v_vinculo
           or public.f5_10_aprovador_congelado(g.id, v_org, 'GERENTE') = v_vinculo
           or public.f5_10_aprovador_congelado(g.id, v_org, 'COORDENADOR') = v_vinculo
         )
    ) x;

  -- (4) (P5.2) Quota do CICLO: `[]` quando nao ha configuracao explicita
  --     (ausencia de linha = quota ZERO e fail-closed no banco; esta projecao
  --     NUNCA inventa default nem herda de outro ciclo/tenant).
  select coalesce(
           jsonb_agg(jsonb_build_object(
             'tipo', l.tipo,
             'quantidade', l.quantidade,
             'version', l.version) order by l.tipo),
           '[]'::jsonb)
    into v_limites
    from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_org
     and l.cycle_id = p_cycle_id;

  return jsonb_build_object(
    'organization_id', v_org,
    'cycle_id', p_cycle_id,
    'ciclo_status', v_ciclo,
    'relacao_ator', case when v_qtd = 0 then 'SEM_META_AUTORIZADA' else 'ESCOPO_APLICADO' end,
    'quantidade', v_qtd,
    'limites', v_limites,
    'metas', v_metas);
end;
$$;

comment on function public.meta_listar_por_escopo(uuid, uuid, uuid) is
  'F5-10 P4 (§11/D7/D8/D22) + P5.2 (Issue #222): LEITURA soberana por escopo. '
  'Aplica o gate funcional `goal.read` (capability efetiva + vinculo soberano '
  'unico) e devolve SOMENTE as metas em que o ator e o DONO (SELF) ou o '
  'participante CONGELADO GERENTE/COORDENADOR da avaliacao do dono '
  '(f5_10_aprovador_congelado, P3; nunca estrutura viva). A RLS own-tenant '
  'continua como defesa em profundidade no caminho de leitura propria. Exige '
  'ciclo do MESMO tenant; NAO exige ciclo ATIVO (leitura historica) e NAO grava '
  'evento. A P5.2 ESTENDEU APENAS A PROJECAO: datas soberanas (criado_em, '
  'atualizado_em, data_ultimo_acompanhamento, data_fechamento, data_exclusao), '
  'estado de aprovacao por papel (`aprovacoes[]`, SEMPRE os dois papeis na ordem '
  'COORDENADOR, GERENTE, com exigida/vigente/aprovacao_id/decidido_em/motivo/'
  'aprovador_collaborator_id) e a quota do ciclo no envelope (`limites`, [] '
  'quando nao configurada). A superficie autorizada NAO mudou: mesmo conjunto de '
  'linhas, nenhuma capability/policy/grant/RPC nova e EXECUTE somente '
  'service_role. LIMITACAO REGISTRADA (contrato §4): `exigida` do papel '
  'COORDENADOR e false tanto para "coordenador nao distinto da cadeia" quanto '
  'para "estrutura congelada nao reconhecida" — a projecao nao distingue os dois '
  'casos (distinguir duplicaria a regra de P3); a mutacao (meta_aprovar) segue '
  'fail-closed, de modo que o estado ambiguo nunca vira aprovacao.';

-- A ACL e REAFIRMADA: `create or replace` nao concede nada novo, mas a leitura
-- soberana continua fechada a cliente (EXECUTE SOMENTE service_role).
revoke all on function public.meta_listar_por_escopo(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.meta_listar_por_escopo(uuid, uuid, uuid)
  to service_role;

-- ----------------------------------------------------------------------------
-- 2) GUARDA FINAL FAIL-CLOSED (estado final CALCULADO)
-- ----------------------------------------------------------------------------
do $$
declare
  v_oid      oid;
  v_secdef   boolean;
  v_cfg      text;
  v_def      text;
  v_n        integer;
  v_tab      text;
  v_priv     text;
  v_falhas   text[] := array[]::text[];
begin
  -- (a) A funcao continua INVOKER, com search_path fixo e MESMA assinatura.
  v_oid := to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid)');
  if v_oid is null then
    raise exception 'F5_10_P5_2_GUARD: assinatura de meta_listar_por_escopo ausente apos a migration';
  end if;
  select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), ''), pg_get_functiondef(p.oid)
    into v_secdef, v_cfg, v_def
    from pg_proc p
   where p.oid = v_oid;
  if v_secdef then
    v_falhas := v_falhas || 'meta_listar_por_escopo virou SECURITY DEFINER'::text;
  end if;
  if position('search_path=public' in v_cfg) = 0 then
    v_falhas := v_falhas || 'meta_listar_por_escopo perdeu search_path = public'::text;
  end if;
  if to_regprocedure('public.meta_listar_por_escopo(uuid, uuid, uuid, text)') is not null then
    v_falhas := v_falhas || 'OVERLOAD novo de meta_listar_por_escopo (ampliacao de superficie)'::text;
  end if;

  -- (b) O gate funcional e o predicado congelado continuam NA FUNCAO.
  if position('f5_10_exigir_autorizacao_meta' in v_def) = 0
     or position('f5_10_vinculo_meta_do_ator' in v_def) = 0
     or position('f5_10_aprovador_congelado' in v_def) = 0 then
    v_falhas := v_falhas || 'meta_listar_por_escopo perdeu o gate funcional ou a relacao congelada'::text;
  end if;
  if position('F5_10_NOT_FOUND' in v_def) = 0 then
    v_falhas := v_falhas || 'meta_listar_por_escopo perdeu o F5_10_NOT_FOUND do ciclo de outro tenant'::text;
  end if;

  -- (c) A projecao nova esta PRESENTE (as 5 datas + aprovacoes + limites).
  if position('''criado_em''' in v_def) = 0
     or position('''atualizado_em''' in v_def) = 0
     or position('''data_ultimo_acompanhamento''' in v_def) = 0
     or position('''data_fechamento''' in v_def) = 0
     or position('''data_exclusao''' in v_def) = 0
     or position('''aprovacoes''' in v_def) = 0
     or position('''limites''' in v_def) = 0 then
    v_falhas := v_falhas || 'projecao P5.2 incompleta (datas/aprovacoes/limites)'::text;
  end if;

  -- (d) A AUTORIZACAO e a IDENTIDADE do aprovador continuam no corpo da leitura:
  --     gate funcional (goal.read + vinculo soberano unico), relacao CONGELADA
  --     e identidade do aprovador pelo colaborador CONGELADO do papel (P3/REP
  --     forcam o ator a ser esse colaborador, entao o fato e a fonte unica -
  --     nenhuma resolucao viva do ator entra aqui).
  if position('f5_10_exigir_autorizacao_meta' in v_def) = 0
     or position('f5_10_vinculo_meta_do_ator' in v_def) = 0
     or position('f5_10_aprovador_congelado' in v_def) = 0 then
    v_falhas := v_falhas || 'projecao/autorizacao incompleta: gate funcional, vinculo soberano, relacao congelada ou identidade soberana do aprovador ausentes do corpo da leitura'::text;
  end if;

  -- (e) Cliente NUNCA executa a leitura soberana (EXECUTE so service_role).
  if has_function_privilege('authenticated',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE')
     or has_function_privilege('anon',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    v_falhas := v_falhas || 'meta_listar_por_escopo exposta a cliente'::text;
  end if;
  if not has_function_privilege('service_role',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    v_falhas := v_falhas || 'service_role perdeu EXECUTE em meta_listar_por_escopo'::text;
  end if;

  -- (f) NENHUMA policy nova e NENHUM privilegio de cliente nas 4 tabelas de
  --     metas (a P5.2 nao toca RLS/grant).
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    select count(*) into v_n
      from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_n <> 0 then
      v_falhas := v_falhas || format('%s com %s policy(ies) (P5.2 exige zero)', v_tab, v_n);
    end if;
    foreach v_priv in array array[
      'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
      if has_table_privilege('authenticated', format('public.%I', v_tab), v_priv) then
        v_falhas := v_falhas || format('%s: authenticated com %s', v_tab, v_priv);
      end if;
      if has_table_privilege('anon', format('public.%I', v_tab), v_priv) then
        v_falhas := v_falhas || format('%s: anon com %s', v_tab, v_priv);
      end if;
    end loop;
    if has_table_privilege('service_role', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('service_role', format('public.%I', v_tab), 'TRUNCATE') then
      v_falhas := v_falhas || format('%s: service_role com DELETE/TRUNCATE', v_tab);
    end if;
  end loop;

  -- (g) Catalogo INALTERADO: 8 capabilities `goal.%%` + `observation.%`.
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_falhas := v_falhas || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  -- (h) NENHUM `SECURITY DEFINER` novo em `public` (mesma whitelist de 4 nomes
  --     usada no hardening D22-A, `20260927000000:129-134`).
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname <> all (array[
       'conceder_acesso_role', 'criar_perfil_membership',
       'resolver_capabilities_efetivas', 'revogar_acesso_role']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('SECURITY DEFINER novo em public = %s (esperado 0)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception
      'F5_10_P5_2_GUARD: projecao P5.2 inconsistente: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice 'F5-10 P5.2: guarda final OK (mesma assinatura INVOKER com search_path fixo, EXECUTE so service_role, projecao estendida sem nova policy/grant/capability/DEFINER, 4 tabelas de metas deny-by-default integral e quota sem privilegio de cliente)';
end $$;
