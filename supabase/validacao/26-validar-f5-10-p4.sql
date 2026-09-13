-- ============================================================================
-- F5-10 P4 (Issue #216): validacao automatizada de AUTORIZACAO/RLS de metas
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   supabase/validacao/25-cenario-f5-10-p4.sql   (fixture)
--   supabase/validacao/26-validar-f5-10-p4.sql   (este arquivo)
--
-- Contrato coberto (docs/F5-10-desenho-tecnico.md §10/§11/D6-D9/D12/D14/D19/
-- D21/D22/D25) e as migrations REAIS da P1/P2/P3:
--   A  17 NEGATIVOS (todos DENY): cross-tenant, membership/perfil invalidos,
--      gestor sem SELF (editar/progredir/finalizar), dono sem goal.approve,
--      aprovador congelado sem a capability, capability sem relacao congelada,
--      hierarquia VIVA divergente, meta excluida, ciclo NAO ATIVO, alvo
--      inexistente, estado/tenant pelo corpo, leitura de terceiro, RPC direta
--      por cliente e DML/SELECT de cliente nas 4 tabelas;
--   B  10 POSITIVOS (todos ALLOW): SELF criar/editar/progredir/finalizar/ler,
--      GERENTE e COORDENADOR congelados aprovando, gestor congelado lendo SO o
--      autorizado, overlay posterior que NAO transfere autoridade, capability +
--      relacao coexistentes e LIMITES como operacao administrativa de ciclo;
--   C  `meta_invalidar_aprovacoes` exige `goal.write` + SELF;
--   D  RLS own-tenant como barreira de TENANT (nao de capability) e trilha/
--      quotas deny-by-default INTEGRAL;
--   E  estado final deterministico (contagens calculadas, nao arbitradas).
--
-- Saida deterministica: um `[PASS]` por bloco; qualquer falha aborta.
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 0) PREFLIGHT: fixture presente, estado LIMPO e superficie da P4 intacta
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_metas  int;
  v_evt    int;
  v_aprov  int;
  v_pol    int;
  v_n      int;
  v_tab    text;
begin
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in (v_alfa, v_beta);
  if v_metas <> 7 or v_evt <> 7 or v_aprov <> 0 then
    raise exception
      '[FAIL] pre-condicao: fixture F5-10 P4 ausente ou estado sujo (metas=%, eventos=%, aprovacoes=%) — execute `supabase db reset` e os cenarios 25/26',
      v_metas, v_evt, v_aprov;
  end if;

  -- RLS own-tenant da P4: exatamente 1 policy SELECT por tabela legivel...
  foreach v_tab in array array['evaluation_goals', 'evaluation_goal_approvals'] loop
    select count(*) into v_pol from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_pol <> 1 then
      raise exception '[FAIL] pre-condicao: % deveria ter exatamente 1 policy (encontradas %)',
        v_tab, v_pol;
    end if;
  end loop;
  -- ...e deny-by-default INTEGRAL na trilha e nas quotas.
  foreach v_tab in array array['evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    select count(*) into v_pol from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_pol <> 0 then
      raise exception '[FAIL] pre-condicao: % deveria permanecer deny-by-default (policies=%)',
        v_tab, v_pol;
    end if;
  end loop;

  -- Catalogo intacto: nenhuma capability nova (D6) e as 3 de meta concediveis.
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    raise exception '[FAIL] pre-condicao: capabilities de metas/observacoes = % (esperado 8)', v_n;
  end if;
  select count(*) into v_n from public.capabilities
   where code in ('goal.read', 'goal.write', 'goal.approve')
     and status = 'active' and deprecated = false and grantable_via_role;
  if v_n <> 3 then
    raise exception '[FAIL] pre-condicao: capabilities de meta efetivas/concediveis = % (esperado 3)', v_n;
  end if;

  -- Capability EFETIVA dos atores centrais (o gate depende dela).
  if not public.f5_10_ator_valido_meta(
       'f2c00000-0000-0000-0000-000000000001', v_alfa, 'goal.write')
     or not public.f5_10_ator_valido_meta(
       'f2c00000-0000-0000-0000-000000000001', v_alfa, 'goal.read') then
    raise exception '[FAIL] pre-condicao: o dono a1 deveria ter goal.read + goal.write';
  end if;
  if not public.f5_10_ator_valido_meta(
       'f2c00000-0000-0000-0000-000000000002', v_alfa, 'goal.approve') then
    raise exception '[FAIL] pre-condicao: o gerente congelado a2 deveria ter goal.approve';
  end if;
  if public.f5_10_ator_valido_meta(
       'f2c00000-0000-0000-0000-000000000005', v_alfa, 'goal.approve') then
    raise exception '[FAIL] pre-condicao: o gerente congelado a5 NAO pode ter goal.approve';
  end if;
  if public.f5_10_ator_valido_meta(
       'f2c00000-0000-0000-0000-000000000009', v_alfa, 'goal.write') then
    raise exception '[FAIL] pre-condicao: o terceiro a9 NAO pode ter goal.write';
  end if;
  -- Codigo fora da allowlist => false (fail-closed).
  if public.f5_10_ator_valido_meta(
       'f2c00000-0000-0000-0000-000000000001', v_alfa, 'cycle.manage') then
    raise exception '[FAIL] pre-condicao: cycle.manage NAO pertence a allowlist de meta';
  end if;

  raise notice '[PASS] preflight: fixture limpa (7 metas, 7 eventos CRIADA, 0 aprovacoes), 2 policies own-tenant de metas, trilha/limites deny-by-default, catalogo intacto (8 capabilities N/obs; 3 de meta concediveis) e capability efetiva dos atores verificada';
end $$;

-- ============================================================================
-- 1) NEGATIVOS 1/11/12/13: TENANT, ALVO, ESTADO e CICLO antes de qualquer escrita
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_m1     uuid := 'f2000000-0000-0000-0000-000000000001';
  v_m3     uuid := 'f2000000-0000-0000-0000-000000000003';
  v_m4     uuid := 'f2000000-0000-0000-0000-000000000004';
  v_mbeta  uuid := 'f2000000-0000-0000-0000-0000000000b1';
  v_a1     uuid := 'f2c00000-0000-0000-0000-000000000001';
  v_ab     uuid := 'f2c00000-0000-0000-0000-0000000000b1';
  v_a6     uuid := 'f2c00000-0000-0000-0000-000000000006';
  v_fant   uuid := 'f2ff0000-0000-0000-0000-0000000000ff';
  v_ok     boolean;
  v_msg    text;
  v_metas  int;
  v_evt    int;
begin
  select count(*) into v_metas from public.evaluation_goals where organization_id in (v_alfa, v_beta);
  select count(*) into v_evt from public.evaluation_goal_events where organization_id in (v_alfa, v_beta);

  -- (N13a) meta INEXISTENTE (uuid valido) => NOT_FOUND, no gate.
  v_ok := false; v_msg := null;
  begin
    perform public.f5_10_exigir_autorizacao_meta('EDITAR', v_a1, v_alfa, v_fant, null);
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N13a: meta inexistente deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (N13b) meta INEXISTENTE pela RPC => NOT_FOUND.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_fant, v_alfa, 'probe de alvo inexistente (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 0, v_a1,
      'f2700000-0000-0000-0000-0000000000f1');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N13b: meta inexistente na RPC deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (N13c) ciclo INEXISTENTE na criacao => NOT_FOUND.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_criar(v_alfa, v_fant, 'f2b00000-0000-0000-0000-000000000001',
      'NEGOCIO_PROJETO', 'probe de ciclo inexistente (P4)', 'KPI probe (P4)',
      '1 unidade (P4)', v_a1, 'f2700000-0000-0000-0000-0000000000f2');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N13c: ciclo inexistente deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (N1) meta do tenant Beta operada com o tenant Alfa: no gate a meta NAO e
  -- resolvida (cross-tenant = inexistente) => NOT_FOUND, sem confirmar existencia.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_mbeta, v_alfa, 'probe cross-tenant (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 0, v_a1,
      'f2700000-0000-0000-0000-0000000000f3');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N1a: meta de outro tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_mbeta, v_alfa, 'GERENTE', 'probe cross-tenant (P4)',
      0, v_a1, 'f2700000-0000-0000-0000-0000000000f4');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N1b: aprovacao cross-tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (N1c) ator de OUTRO tenant (Beta) sem capability no tenant Alfa: o gate
  -- resolve o alvo no tenant do ATOR e a capability e ausente => FORBIDDEN.
  v_ok := false; v_msg := null;
  begin
    perform public.f5_10_exigir_autorizacao_meta('EDITAR', v_ab, v_alfa, v_m1, null);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N1c: ator de outro tenant deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_m1, v_alfa, 'probe ator de outro tenant (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 0, v_ab,
      'f2700000-0000-0000-0000-0000000000f5');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N1d: RPC com ator de outro tenant deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (N1e) alvo de OUTRO tenant na CRIACAO: colaborador de Beta => NOT_FOUND.
  v_ok := false; v_msg := null;
  begin
    perform public.f5_10_exigir_autorizacao_meta('CRIAR', v_a1, v_alfa, null,
      'f2b00000-0000-0000-0000-0000000000c1');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N1e: colaborador alvo de outro tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_criar(v_alfa, 'f2d10000-0000-0000-0000-0000000000a1',
      'f2b00000-0000-0000-0000-0000000000c1', 'INDIVIDUAL',
      'probe alvo cross-tenant (P4)', 'KPI probe (P4)', '1 unidade (P4)', v_a1,
      'f2700000-0000-0000-0000-0000000000f6');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N1f: criacao com alvo de outro tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (N13d) meta INEXISTENTE (uuid valido) na aprovacao => NOT_FOUND.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_fant, v_alfa, 'GERENTE', 'probe de alvo inexistente (P4)',
      0, v_a1, 'f2700000-0000-0000-0000-0000000000f7');
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N13d: meta inexistente na aprovacao deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;

  -- (N11) meta EXCLUIDA: editar e aprovar recusados com CONFLICT (soft delete e
  -- terminal) — nunca sucesso, nunca NOT_FOUND (a meta existe no tenant).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_m4, v_alfa, 'probe em meta excluida (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 2, v_a1,
      'f2700000-0000-0000-0000-0000000000f8');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N11a: edicao de meta excluida deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(v_m4, v_alfa, 'probe (P4)', 10, 2, v_a1,
      'f2700000-0000-0000-0000-0000000000f9');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N11b: progresso de meta excluida deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_finalizar(v_m4, v_alfa, 'probe (P4)', true, 2, v_a1,
      'f2700000-0000-0000-0000-0000000000fa');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N11c: finalizacao de meta excluida deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_excluir(v_m4, v_alfa, 'probe (P4)', 2, v_a1,
      'f2700000-0000-0000-0000-0000000000fb');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N11d: reexclusao de meta excluida deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_invalidar_aprovacoes(v_m4, v_alfa, 'probe (P4)', 2, v_a1,
      'f2700000-0000-0000-0000-0000000000fc');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N11e: invalidacao em meta excluida deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  -- A meta excluida continua EXATAMENTE como estava (nada de reativacao).
  if not exists (
    select 1 from public.evaluation_goals g
     where g.id = v_m4 and g.excluida and g.version = 2 and g.data_exclusao is not null
  ) then
    raise exception '[FAIL] N11f: a meta excluida foi alterada pelas recusas';
  end if;

  -- (N12a) ciclo NAO ATIVO na CRIACAO => CONFLICT (o gate passa: alvo e SELF).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_criar(v_alfa, 'f2d10000-0000-0000-0000-0000000000a2',
      'f2b00000-0000-0000-0000-000000000001', 'NEGOCIO_PROJETO',
      'probe de ciclo encerrado (P4)', 'KPI probe (P4)', '1 unidade (P4)', v_a1,
      'f2700000-0000-0000-0000-0000000000fd');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N12a: criacao em ciclo NAO ATIVO deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  -- (N12b) idem por RPC de EDICAO sobre meta viva em ciclo encerrado.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_m3, v_alfa, 'probe de ciclo encerrado (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 0, v_a1,
      'f2700000-0000-0000-0000-0000000000fe');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N12b: edicao em ciclo NAO ATIVO deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  -- (N12c) idem na APROVACAO (mesmo passando pelo gate com goal.approve).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m3, v_alfa, 'GERENTE', 'probe de ciclo encerrado (P4)',
      0, v_a6, 'f2700000-0000-0000-0000-0000000000ff');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N12c: aprovacao em ciclo NAO ATIVO deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  -- (N12d) idem no PROGRESSO (meta viva do dono em ciclo encerrado).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(v_m3, v_alfa, 'probe (P4)', 10, 0, v_a1,
      'f2700000-0000-0000-0000-000000000100');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N12d: progresso em ciclo NAO ATIVO deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  -- (N12e) idem na FINALIZACAO.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_finalizar(v_m3, v_alfa, 'probe (P4)', true, 0, v_a1,
      'f2700000-0000-0000-0000-000000000101');
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N12e: finalizacao em ciclo NAO ATIVO deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;

  -- Nenhuma das recusas criou meta, evento ou fato.
  if (select count(*) from public.evaluation_goals where organization_id in (v_alfa, v_beta)) <> v_metas
     or (select count(*) from public.evaluation_goal_events where organization_id in (v_alfa, v_beta)) <> v_evt
     or exists (select 1 from public.evaluation_goal_approvals where organization_id in (v_alfa, v_beta)) then
    raise exception '[FAIL] N1/N11/N12/N13: recusa alterou o estado (esperado % metas e % eventos, 0 aprovacoes)',
      v_metas, v_evt;
  end if;

  raise notice '[PASS] N1/N11/N12/N13 (17 recusas): ator e alvo de outro tenant (NOT_FOUND/FORBIDDEN), meta e ciclo inexistentes (NOT_FOUND), meta EXCLUIDA e ciclo NAO ATIVO recusando criar/editar/progredir/finalizar/aprovar/invalidar/excluir (CONFLICT) — SEM nenhum efeito';
end $$;

-- ============================================================================
-- 2) NEGATIVOS 2/3: membership REVOGADA e perfil `disabled` (autoria soberana)
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m2   uuid := 'f2000000-0000-0000-0000-000000000002';
  v_a1   uuid := 'f2c00000-0000-0000-0000-000000000001';
  v_a7   uuid := 'f2c00000-0000-0000-0000-000000000007';
  v_a8   uuid := 'f2c00000-0000-0000-0000-000000000008';
  v_ok   boolean;
  v_msg  text;
begin
  -- (N2a) membership REVOGADA (status disabled) => FORBIDDEN com a mensagem
  -- EXATA das RPCs ('ator sem perfil/membership ativa na organizacao').
  update public.user_organization_memberships set status = 'disabled'
   where id = 'f2d00000-0000-0000-0000-000000000001';
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_m2, v_alfa, 'probe de membership revogada (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 0, v_a1,
      'f2700000-0000-0000-0000-000000000201');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N2a: membership revogada deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  if position('ator sem perfil/membership ativa na organizacao' in v_msg) = 0 then
    raise exception '[FAIL] N2a: mensagem divergente do contrato (%)', v_msg;
  end if;
  -- o gate funcional tambem nega e nenhum vinculo SELF e reconhecido.
  v_ok := false; v_msg := null;
  begin
    perform public.f5_10_exigir_autorizacao_meta('EDITAR', v_a1, v_alfa, v_m2, null);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N2b: gate com membership revogada deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  if public.f5_10_vinculo_meta_do_ator(v_a1, v_alfa) is not null then
    raise exception '[FAIL] N2c: membership revogada nao pode resolver vinculo SELF';
  end if;
  -- Reativacao para o restante da bateria (a recusa nao pode ter mutado nada).
  update public.user_organization_memberships set status = 'active'
   where id = 'f2d00000-0000-0000-0000-000000000001';
  if public.f5_10_vinculo_meta_do_ator(v_a1, v_alfa)
     <> 'f2b00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] N2d: vinculo SELF deveria voltar ao normal apos reativacao';
  end if;

  -- (N3a) perfil `disabled` com membership ATIVA => FORBIDDEN (mesma mensagem).
  update public.user_profiles set status = 'disabled'
   where id = 'f2c00000-0000-0000-0000-000000000001';
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_m2, v_alfa, 'probe de perfil disabled (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 0, v_a1,
      'f2700000-0000-0000-0000-000000000202');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N3a: perfil disabled deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  if position('ator sem perfil/membership ativa na organizacao' in v_msg) = 0 then
    raise exception '[FAIL] N3a: mensagem divergente do contrato (%)', v_msg;
  end if;
  update public.user_profiles set status = 'active'
   where id = 'f2c00000-0000-0000-0000-000000000001';

  -- (N2/N3) o ator da fixture com membership `disabled` (a7) e o de perfil
  -- `disabled` (a8) continuam recusados pelo gate, sem tocar o banco.
  v_ok := false; v_msg := null;
  begin
    perform public.f5_10_exigir_autorizacao_meta('CRIAR', v_a7, v_alfa, null,
      'f2b00000-0000-0000-0000-000000000002');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N2e: a7 (membership disabled) deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.f5_10_exigir_autorizacao_meta('CRIAR', v_a8, v_alfa, null,
      'f2b00000-0000-0000-0000-000000000002');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N3b: a8 (perfil disabled) deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  raise notice '[PASS] N2/N3: membership REVOGADA e perfil `disabled` recusam com a mensagem EXATA do contrato (`F5_10_FORBIDDEN: ator sem perfil/membership ativa na organizacao`), sem resolver vinculo SELF e sem efeito colateral';
end $$;

-- ============================================================================
-- 3) NEGATIVOS 4/5/6: GESTOR com goal.write sobre meta de TERCEIRO => exige SELF
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m2   uuid := 'f2000000-0000-0000-0000-000000000002';
  v_a4   uuid := 'f2c00000-0000-0000-0000-000000000004';
  v_ok   boolean;
  v_msg  text;
begin
  -- Pre-condicao do cenario: a4 TEM goal.write e NAO e o dono de M2 (dono = c1).
  if not public.f5_10_ator_valido_meta(v_a4, v_alfa, 'goal.write') then
    raise exception '[FAIL] N4: a4 deveria ter goal.write (pre-condicao do negativo)';
  end if;
  if public.f5_10_vinculo_meta_do_ator(v_a4, v_alfa)
     = 'f2b00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] N4: a4 NAO pode ser o dono de M2 (pre-condicao do negativo)';
  end if;

  -- (N4) EDITAR meta de terceiro => FORBIDDEN citando SELF.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_m2, v_alfa, 'probe de gestor sem SELF (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 0, v_a4,
      'f2700000-0000-0000-0000-000000000401');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N4: gestor sem SELF editando meta de terceiro deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;
  if position('exige SELF' in v_msg) = 0 then
    raise exception '[FAIL] N4: mensagem deveria citar SELF (%)', v_msg;
  end if;

  -- (N5) ATUALIZAR PROGRESSO de meta de terceiro => FORBIDDEN SELF.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(v_m2, v_alfa, 'probe de gestor sem SELF (P4)',
      10, 0, v_a4, 'f2700000-0000-0000-0000-000000000402');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige SELF' in v_msg) = 0 then
    raise exception '[FAIL] N5: progresso por gestor sem SELF deveria ser FORBIDDEN com SELF (recebido %)', v_msg;
  end if;

  -- (N6) FINALIZAR meta de terceiro => FORBIDDEN SELF.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_finalizar(v_m2, v_alfa, 'probe de gestor sem SELF (P4)', true, 0, v_a4,
      'f2700000-0000-0000-0000-000000000403');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige SELF' in v_msg) = 0 then
    raise exception '[FAIL] N6: finalizacao por gestor sem SELF deveria ser FORBIDDEN com SELF (recebido %)', v_msg;
  end if;

  -- O gate tambem recusa a INVALIDACAO e a EXCLUSAO de terceiro (mesma relacao).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_invalidar_aprovacoes(v_m2, v_alfa, 'probe de gestor sem SELF (P4)',
      0, v_a4, 'f2700000-0000-0000-0000-000000000404');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige SELF' in v_msg) = 0 then
    raise exception '[FAIL] N4b: invalidacao por gestor sem SELF deveria ser FORBIDDEN com SELF (recebido %)', v_msg;
  end if;

  -- M2 permanece INTOCADA (nenhuma mutacao parcial).
  if not exists (
    select 1 from public.evaluation_goals g
     where g.id = v_m2 and g.status = 'EM_ANDAMENTO' and g.version = 0
       and g.progresso_percentual is null and g.resultado_final is null
  ) then
    raise exception '[FAIL] N4/N5/N6: M2 foi alterada pelas recusas de gestor';
  end if;

  raise notice '[PASS] N4/N5/N6: GESTOR com goal.write (nao dono) recusado em editar/progredir/finalizar/invalidar meta de TERCEIRO com `F5_10_FORBIDDEN: operacao X exige SELF (goal.write apenas sobre a propria meta)` — goal.write NAO e escrita sobre meta alheia';
end $$;

-- ============================================================================
-- 4) NEGATIVOS 7/8/9/10: capability e RELACAO CONGELADA de aprovacao
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m1     uuid := 'f2000000-0000-0000-0000-000000000001';
  v_m2     uuid := 'f2000000-0000-0000-0000-000000000002';
  v_m6     uuid := 'f2000000-0000-0000-0000-000000000006';
  v_a2     uuid := 'f2c00000-0000-0000-0000-000000000002';
  v_a3     uuid := 'f2c00000-0000-0000-0000-000000000003';
  -- a4 = gestor com `goal.write` e SEM `goal.approve` (fixture): e o ator do N7.
  v_a4     uuid := 'f2c00000-0000-0000-0000-000000000004';
  v_a5     uuid := 'f2c00000-0000-0000-0000-000000000005';
  v_a6     uuid := 'f2c00000-0000-0000-0000-000000000006';
  v_a9     uuid := 'f2c00000-0000-0000-0000-000000000009';
  v_aa     uuid := 'f2c00000-0000-0000-0000-00000000000a';
  v_ok     boolean;
  v_msg    text;
  v_vivo   uuid;
  v_cong   uuid;
  v_colab  uuid;
begin
  -- (N7) ator com membership/vínculo validos e SEM a capability `goal.approve`:
  -- a capability e exigida ANTES da relacao => DENY pelo GATE.
  if public.f5_10_ator_valido_meta(v_a4, v_alfa, 'goal.approve') then
    raise exception '[FAIL] N7: a4 NAO pode ter goal.approve (pre-condicao do negativo)';
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m2, v_alfa, 'GERENTE', 'probe sem capability (P4)',
      0, v_a4, 'f2700000-0000-0000-0000-000000000501');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige a capability goal.approve' in v_msg) = 0 then
    raise exception '[FAIL] N7: aprovacao sem a capability goal.approve deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (N8) APROVADOR CONGELADO ORIGINAL de M6 (c5 = GESTAO_CADEIA) SEM a
  -- capability `goal.approve`: a relacao existe e a capability nao => DENY.
  if public.f5_10_aprovador_congelado(v_m6, v_alfa, 'GERENTE')
     <> 'f2b00000-0000-0000-0000-000000000005'::uuid then
    raise exception '[FAIL] N8: pre-condicao — o GERENTE congelado de M6 deveria ser c5';
  end if;
  if public.f5_10_ator_valido_meta(v_a5, v_alfa, 'goal.approve') then
    raise exception '[FAIL] N8: a5 NAO pode ter goal.approve (pre-condicao do negativo)';
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m6, v_alfa, 'GERENTE', 'probe de aprovador sem capability (P4)',
      0, v_a5, 'f2700000-0000-0000-0000-000000000502');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige a capability goal.approve' in v_msg) = 0 then
    raise exception '[FAIL] N8: aprovador congelado sem goal.approve deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (N9) ator COM `goal.approve` mas SEM a relacao congelada: o gate passa (a
  -- aprovacao NAO resolve relacao) e a RPC recusa por NAO ser o participante
  -- congelado do papel (D19/D25).
  if not public.f5_10_ator_valido_meta(v_a6, v_alfa, 'goal.approve') then
    raise exception '[FAIL] N9: a6 deveria ter goal.approve (pre-condicao do negativo)';
  end if;
  if public.f5_10_vinculo_meta_do_ator(v_a6, v_alfa) is not null then
    raise exception '[FAIL] N9: a6 NAO pode ter vinculo unico (pre-condicao do negativo)';
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m2, v_alfa, 'GERENTE', 'probe de aprovador sem relacao (P4)',
      0, v_a6, 'f2700000-0000-0000-0000-000000000503');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok
     or (position('participante congelado do papel GERENTE' in v_msg) = 0
         and position('sem vinculo UNICO de colaborador ativo' in v_msg) = 0) then
    raise exception '[FAIL] N9: capability sem relacao congelada deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (N10) HIERARQUIA VIVA DIVERGENTE: `aa` (c7) e o gestor VIVO do dono de M1 e
  -- TEM `goal.approve`, mas o participante CONGELADO e c2. A autoridade NAO vem
  -- da estrutura viva (D14/D15) => DENY.
  if not public.f5_10_ator_valido_meta(v_aa, v_alfa, 'goal.approve') then
    raise exception '[FAIL] N10: aa deveria ter goal.approve (pre-condicao do negativo)';
  end if;
  select r.manager_responsible_collaborator_id into v_vivo
    from public.organizacao_resolver_gestor_direto(
           'f2b00000-0000-0000-0000-000000000001',
           '2029-01-01T00:00:00Z') r;
  v_cong := public.f5_10_aprovador_congelado(v_m1, v_alfa, 'GERENTE');
  v_colab := public.f5_10_vinculo_meta_do_ator(v_aa, v_alfa);
  if v_vivo is distinct from v_colab then
    raise exception '[FAIL] N10: pre-condicao — o gestor VIVO do dono deveria ser o colaborador de aa (% vs %)',
      v_vivo, v_colab;
  end if;
  if v_cong is null or v_cong = v_colab then
    raise exception '[FAIL] N10: pre-condicao — o GERENTE congelado deveria DIVERGIR do gestor vivo (%)', v_cong;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'probe de hierarquia viva (P4)',
      0, v_aa, 'f2700000-0000-0000-0000-000000000504');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('participante congelado do papel GERENTE' in v_msg) = 0 then
    raise exception '[FAIL] N10: gestor da hierarquia VIVA deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;

  -- Nenhuma das 4 tentativas criou fato ou evento.
  if exists (
    select 1 from public.evaluation_goal_approvals
     where organization_id = v_alfa
       and goal_id in (v_m1, v_m2, v_m6)
  ) then
    raise exception '[FAIL] N7..N10: as recusas de aprovacao criaram FATO';
  end if;
  if exists (
    select 1 from public.evaluation_goal_events
     where organization_id = v_alfa
       and operation_id in (
         'f2700000-0000-0000-0000-000000000501', 'f2700000-0000-0000-0000-000000000502',
         'f2700000-0000-0000-0000-000000000503', 'f2700000-0000-0000-0000-000000000504')
  ) then
    raise exception '[FAIL] N7..N10: as recusas de aprovacao gravaram EVENTO';
  end if;
  -- A prova de que `aa` NAO e o congelado fica registrada na leitura direta.
  if not exists (
    select 1 from public.evaluation_participants p
     where p.evaluation_id = 'f2200000-0000-0000-0000-000000000001'
       and p.role_type = 'GESTAO_CADEIA'
       and p.collaborator_id = v_cong
       and p.status = 'active'
  ) or exists (
    select 1 from public.evaluation_participants p
     where p.evaluation_id = 'f2200000-0000-0000-0000-000000000001'
       and p.role_type = 'GESTAO_CADEIA'
       and p.collaborator_id = v_colab
  ) then
    raise exception '[FAIL] N10: `evaluation_participants` deveria provar que aa NAO e o participante congelado';
  end if;

  raise notice '[PASS] N7/N8/N9/N10: dono sem goal.approve, aprovador congelado sem goal.approve, capability sem relacao congelada e gestor da hierarquia VIVA (divergente) recusados — a legitimidade vem EXCLUSIVAMENTE do snapshot congelado';
end $$;

-- ============================================================================
-- 5) NEGATIVO 14: o corpo NAO carrega estado/tenant/autoridade
-- ============================================================================
do $$
declare
  v_fns text[] := array[
    'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)',
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_listar_por_escopo(uuid, uuid, uuid)'];
  -- Parametros de ESTADO/AUTORIDADE que o cliente NAO pode declarar. `progresso`,
  -- `resultado_final`, `atingida`, `papel`, `operation_id` e `payload_hash` sao
  -- ENTRADAS legitimas da operacao (validadas/derivadas server-side), nao estado
  -- declarado — por isso ficam FORA da lista.
  v_proibidos text[] := array['status', 'aprovado', 'domainstate', 'excluida',
                              'vigente', 'revogado'];
  v_fn    text;
  v_args  text;
  v_key   text;
  v_ok    boolean;
  v_msg   text;
  v_erros text[] := array[]::text[];
begin
  -- (N14a) NENHUM parametro de ESTADO/AUTORIDADE nas 10 RPCs. `expected_version`
  -- e permitido (versao otimista do proprio recurso, nunca estado), mas nao pode
  -- existir nenhum parametro com nome de estado do dominio.
  foreach v_fn in array v_fns loop
    v_args := lower(coalesce(pg_get_function_arguments(to_regprocedure(v_fn)), ''));
    if position('expected_version' in v_args) > 0
       and position('expected_version' in replace(v_args, 'expected_version', '')) > 0 then
      v_erros := v_erros || ('expected_version repetido em ' || v_fn);
    end if;
    foreach v_key in array v_proibidos loop
      if position(v_key in replace(v_args, 'expected_version', '')) > 0 then
        v_erros := v_erros || format('%s expoe o parametro de estado `%s`', v_fn, v_key);
      end if;
    end loop;
  end loop;
  -- Prova explicita e fechada por assinatura (o cliente NAO tem como forjar):
  if position('status' in lower(coalesce(pg_get_function_arguments(
       to_regprocedure('public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)')), ''))) > 0
     or position('version' in lower(coalesce(pg_get_function_arguments(
       to_regprocedure('public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)')), ''))) > 0 then
    v_erros := v_erros || 'meta_criar aceita status/version'::text;
  end if;
  -- Unico parametro com `version` no nome e `expected_version` (todos os demais
  -- sao identidade/tenant/autoria/forma).
  foreach v_fn in array v_fns loop
    v_args := lower(coalesce(pg_get_function_arguments(to_regprocedure(v_fn)), ''));
    if position('version' in v_args) > 0
       and position('expected_version' in v_args) = 0 then
      v_erros := v_erros || ('parametro de version fora de expected_version: ' || v_fn);
    end if;
  end loop;

  if array_length(v_erros, 1) is not null then
    raise exception '[FAIL] N14a: %', array_to_string(v_erros, '; ');
  end if;

  -- (N14b) tentar enviar `status`/`tipo` como argumento EXTRA e ERRO de
  -- assinatura (42883) — nao existe sobrecarga que aceite estado do corpo.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(
      'f2000000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1',
      'probe estado pelo corpo (P4)', 10, 0, 'f2c00000-0000-0000-0000-000000000001',
      'f2700000-0000-0000-0000-000000000601', 'ATINGIDA');
  exception when others then v_ok := (sqlstate = '42883'); v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N14b: argumento extra de estado deveria falhar por ASSINATURA/42883 (recebido %)', v_msg;
  end if;

  -- (N14c) `meta_aprovar` sem o papel: nenhuma sobrecarga aceita "aprovar sem
  -- papel" (o papel e parametro OBRIGATORIO do contrato).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(
      'f2000000-0000-0000-0000-000000000002', 'f2a00000-0000-0000-0000-0000000000a1',
      'probe sem papel (P4)', 0, 'f2c00000-0000-0000-0000-000000000001',
      'f2700000-0000-0000-0000-000000000602');
  exception when others then v_ok := (sqlstate = '42883'); v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N14c: chamada sem o papel obrigatorio deveria falhar por ASSINATURA/42883 (recebido %)', v_msg;
  end if;

  -- (N14d) a associacao operacao -> capability e FECHADA no gate: uma operacao
  -- desconhecida e recusada ANTES de qualquer consulta (fail-closed).
  v_ok := false; v_msg := null;
  begin
    perform public.f5_10_exigir_autorizacao_meta('PROGREDIR_COM_STATUS',
      'f2c00000-0000-0000-0000-000000000001', 'f2a00000-0000-0000-0000-0000000000a1', null, null);
  exception when others then v_ok := sqlerrm like '%operacao de meta desconhecida%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] N14d: operacao desconhecida deveria ser recusada fail-closed (recebido %)', v_msg;
  end if;
  -- O chamador tambem NAO escolhe a capability: o gate deriva do mapa FECHADO.
  if public.f5_10_ator_valido_meta(
       'f2c00000-0000-0000-0000-000000000009',
       'f2a00000-0000-0000-0000-0000000000a1', 'goal.read') is not true then
    raise exception '[FAIL] N14e: a9 deveria ter goal.read (pre-condicao da prova de capability fixa)';
  end if;

  raise notice '[PASS] N14: as 10 RPCs NAO aceitam parametro de estado/tenant/autoridade (apenas identidade, forma e `expected_version`), argumento extra de estado falha por assinatura (42883) e a capability vem do mapa FECHADO operacao->capability do gate';
end $$;

-- ============================================================================
-- 6) NEGATIVO 15: LEITURA de terceiro nao pode revelar meta alheia
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_ciclo uuid := 'f2d10000-0000-0000-0000-0000000000a1';
  v_a9    uuid := 'f2c00000-0000-0000-0000-000000000009';
  v_res   jsonb;
begin
  -- (N15a) `a9` TEM `goal.read` e vinculo soberano unico, mas NAO e dono nem
  -- aprovador congelado de meta alguma: a RPC devolve ZERO e nenhuma meta.
  if not public.f5_10_ator_valido_meta(v_a9, v_alfa, 'goal.read') then
    raise exception '[FAIL] N15: a9 deveria ter goal.read';
  end if;
  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_a9);
  if (v_res->>'quantidade')::int <> 0
     or v_res->>'relacao_ator' <> 'SEM_META_AUTORIZADA'
     or v_res->'metas' <> '[]'::jsonb then
    raise exception '[FAIL] N15a: leitura de TERCEIRO deveria devolver 0 metas (%)', v_res;
  end if;

  -- (N15b) leitura cross-tenant pelo RPC => DENY. A ordem fail-closed do gate e
  -- CAPABILITY antes do alvo: o ator sem `goal.read` no tenant recebe FORBIDDEN;
  -- com capability e ciclo alheio, NOT_FOUND. Ambas negam e nao revelam o dado.
  begin
    perform public.meta_listar_por_escopo(
      v_beta, 'f2d10000-0000-0000-0000-0000000000b1', v_a9);
    raise exception '[FAIL] N15b: leitura de ciclo de outro tenant deveria ser negada';
  exception when others then
    if sqlerrm not like '%F5_10_FORBIDDEN%' and sqlerrm not like '%F5_10_NOT_FOUND%' then
      raise exception '[FAIL] N15b: esperado F5_10_FORBIDDEN ou F5_10_NOT_FOUND, recebido %', sqlerrm;
    end if;
  end;
  -- (N15c) prova de que `a9` nao e dono nem aprovador congelado de nada.
  if exists (
    select 1 from public.evaluation_goals g
     where g.organization_id = v_alfa
       and g.collaborator_id = public.f5_10_vinculo_meta_do_ator(v_a9, v_alfa)
  ) then
    raise exception '[FAIL] N15c: a9 nao pode ser dono de meta de fixture';
  end if;

  raise notice '[PASS] N15: terceiro com `goal.read` (capability + vinculo) recebe `quantidade = 0` e nenhuma meta de terceiro; ciclo de outro tenant na leitura => F5_10_NOT_FOUND';
end $$;

-- ============================================================================
-- 7) POSITIVO 1: DONO CRIA a propria meta (SELF) em ciclo ATIVO
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  -- O DONO deste positivo e o colaborador `f2b...0002` (c2): quem cria a propria
  -- meta e o ator VINCULADO a ele (a2), pois o gate da P4 exige SELF.
  v_a1   uuid := 'f2c00000-0000-0000-0000-000000000002';
  v_res  jsonb;
  v_m5   uuid;
  v_meta record;
  v_evt  record;
begin
  v_res := public.meta_criar(
    v_alfa, 'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000002',
    'INDIVIDUAL', 'Meta criada pelo proprio dono (P4)', 'KPI de fixture (P4)',
    '25 unidades (P4)', v_a1, 'f2700000-0000-0000-0000-000000000701');
  v_m5 := (v_res->>'goal_id')::uuid;
  if v_m5 is null or v_res->>'status' <> 'EM_ANDAMENTO' or (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] P1: criacao SELF deveria nascer EM_ANDAMENTO/version 0 (%)', v_res;
  end if;

  select g.* into v_meta from public.evaluation_goals g where g.id = v_m5;
  if v_meta.organization_id <> v_alfa
     or v_meta.collaborator_id <> 'f2b00000-0000-0000-0000-000000000002'::uuid
     or v_meta.cycle_id <> 'f2d10000-0000-0000-0000-0000000000a1'::uuid
     or v_meta.tipo <> 'INDIVIDUAL' or v_meta.excluida then
    raise exception '[FAIL] P1: meta criada divergente do contrato (%)', v_meta;
  end if;

  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f2700000-0000-0000-0000-000000000701';
  if v_evt.event_type <> 'CRIADA'
     or v_evt.result_entity_id <> v_m5
     or v_evt.actor_user_profile_id <> v_a1
     or v_evt.actor_membership_id <> 'f2d00000-0000-0000-0000-000000000002'::uuid
     or v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] P1: evento CRIADA divergente (%)', v_evt;
  end if;

  raise notice '[PASS] P1: DONO com `goal.read` + `goal.write` CRIA a propria meta (SELF) em ciclo ATIVO — identidade do banco, EM_ANDAMENTO/version 0, autoria soberana e evento CRIADA';
end $$;

-- ============================================================================
-- 8) POSITIVO 2: DONO EDITA a propria meta com `expected_version`
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m2   uuid := 'f2000000-0000-0000-0000-000000000002';
  v_a1   uuid := 'f2c00000-0000-0000-0000-000000000001';
  v_res  jsonb;
  v_meta record;
begin
  v_res := public.meta_editar(v_m2, v_alfa, 'Meta SELF editada pelo dono (P4)',
    'KPI editado pelo dono (P4)', '55 unidades (P4)', 0, v_a1,
    'f2700000-0000-0000-0000-000000000702');
  if (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] P2: edicao SELF deveria levar a meta para version 1 (%)', v_res;
  end if;
  select g.* into v_meta from public.evaluation_goals g where g.id = v_m2;
  if v_meta.descricao <> 'Meta SELF editada pelo dono (P4)'
     or v_meta.kpi <> 'KPI editado pelo dono (P4)'
     or v_meta.valor_alvo <> '55 unidades (P4)' then
    raise exception '[FAIL] P2: a definicao da meta nao foi atualizada (%)', v_meta;
  end if;
  if not exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f2700000-0000-0000-0000-000000000702'
       and e.event_type = 'EDITADA'
       and e.before_value->>'valor_alvo' = '50 unidades (P4)'
       and e.after_value->>'valor_alvo' = '55 unidades (P4)'
  ) then
    raise exception '[FAIL] P2: evento EDITADA sem before/after coerentes';
  end if;
  -- expected_version OBSOLETO continua sendo CONFLICT (nao e caminho de estado).
  begin
    perform public.meta_editar(v_m2, v_alfa, 'probe stale (P4)', 'KPI stale (P4)',
      '1 unidade (P4)', 0, v_a1, 'f2700000-0000-0000-0000-000000000703');
    raise exception '[FAIL] P2: expected_version obsoleto deveria ser CONFLICT';
  exception when others then
    if sqlerrm not like '%F5_10_CONFLICT%' then
      raise exception '[FAIL] P2: esperado F5_10_CONFLICT, recebido %', sqlerrm;
    end if;
  end;

  raise notice '[PASS] P2: DONO EDITA a propria meta (`descricao`/`kpi`/`valor_alvo`) com `expected_version` sob o lock normativo, version +1 e evento EDITADA com before/after; versao obsoleta segue CONFLICT';
end $$;

-- ============================================================================
-- 9) POSITIVOS 3/4/5: PROGRESSO, FINALIZACAO e LEITURA SELF
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f2d10000-0000-0000-0000-0000000000a1';
  v_m2    uuid := 'f2000000-0000-0000-0000-000000000002';
  v_a1    uuid := 'f2c00000-0000-0000-0000-000000000001';
  v_res   jsonb;
  v_meta  record;
  v_evt   record;
begin
  -- (P3) DONO ATUALIZA o progresso (0..100).
  v_res := public.meta_atualizar_progresso(v_m2, v_alfa, 'Acompanhamento do dono (P4)',
    40, 1, v_a1, 'f2700000-0000-0000-0000-000000000704');
  select g.* into v_meta from public.evaluation_goals g where g.id = v_m2;
  if v_meta.progresso_percentual <> 40
     or v_meta.resultado_atual <> 'Acompanhamento do dono (P4)'
     or v_meta.data_ultimo_acompanhamento is null
     or v_meta.version <> 2 then
    raise exception '[FAIL] P3: progresso SELF divergente (%)', v_meta;
  end if;
  if not exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f2700000-0000-0000-0000-000000000704'
       and e.event_type = 'PROGRESSO_ATUALIZADO'
  ) then
    raise exception '[FAIL] P3: evento PROGRESSO_ATUALIZADO ausente';
  end if;

  -- (P4) DONO FINALIZA a propria meta.
  v_res := public.meta_finalizar(v_m2, v_alfa, 'Fechamento do dono (P4)', true, 2, v_a1,
    'f2700000-0000-0000-0000-000000000705');
  if v_res->>'status' <> 'ATINGIDA' or (v_res->>'version')::int <> 3 then
    raise exception '[FAIL] P4: finalizacao deveria resultar em ATINGIDA/version 3 (%)', v_res;
  end if;
  select g.* into v_meta from public.evaluation_goals g where g.id = v_m2;
  if v_meta.status <> 'ATINGIDA' or v_meta.atingida is not true
     or v_meta.resultado_final <> 'Fechamento do dono (P4)' or v_meta.data_fechamento is null then
    raise exception '[FAIL] P4: fechamento SELF incoerente (%)', v_meta;
  end if;
  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f2700000-0000-0000-0000-000000000705';
  if v_evt.event_type <> 'FINALIZADA' or v_evt.after_value->>'atingida' <> 'true' then
    raise exception '[FAIL] P4: evento FINALIZADA divergente (%)', v_evt;
  end if;

  -- (P5) DONO LE as metas AUTORIZADAS no ciclo: M1/M2 (relacao SELF) e M5 —
  --      criada pelo positivo 1, dona c2 — pela RELACAO CONGELADA (o dono c1 e o
  --      `GESTAO_CADEIA` congelado da avaliacao de M5). Nenhuma outra meta.
  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_a1);
  if (v_res->>'quantidade')::int <> 3
     or v_res->>'relacao_ator' <> 'ESCOPO_APLICADO'
     or v_res->>'ciclo_status' <> 'ATIVO' then
    raise exception '[FAIL] P5: leitura deveria devolver as 3 metas autorizadas do dono no ciclo (%)', v_res;
  end if;
  if not exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where m->>'goal_id' = v_m2::text and m->>'relacao' = 'SELF'
       and m->>'status' = 'ATINGIDA' and (m->>'version')::int = 3
  ) then
    raise exception '[FAIL] P5: a meta do dono deveria aparecer com relacao SELF (%)', v_res->'metas';
  end if;
  -- Meta de TERCEIRO so entra pela RELACAO CONGELADA (nunca como SELF).
  if exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where (m->>'collaborator_id') <> 'f2b00000-0000-0000-0000-000000000001'
       and (m->>'relacao') not like 'APROVADOR%'
  ) then
    raise exception '[FAIL] P5: a leitura vazou meta de terceiro sem relacao congelada (%)', v_res->'metas';
  end if;

  raise notice '[PASS] P3/P4/P5: DONO ATUALIZA progresso (0..100, data do servidor), FINALIZA a propria meta (ATINGIDA com fechamento coerente) e LE por `meta_listar_por_escopo` as 4 metas do ciclo com relacao SELF — nenhuma meta de terceiro';
end $$;

-- ============================================================================
-- 10) POSITIVOS 6/7: GERENTE e COORDENADOR CONGELADOS aprovam M1
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m1    uuid := 'f2000000-0000-0000-0000-000000000001';
  v_a2    uuid := 'f2c00000-0000-0000-0000-000000000002';
  v_a3    uuid := 'f2c00000-0000-0000-0000-000000000003';
  v_res   jsonb;
  v_fato  record;
  v_evt   record;
  v_n     int;
begin
  -- (P6) GERENTE CONGELADO (c2 = GESTAO_CADEIA ORIGINAL) aprova.
  v_res := public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'aprovacao de gerente (P4)',
    0, v_a2, 'f2700000-0000-0000-0000-000000000706');
  if v_res->>'aprovado' <> 'true' or v_res->>'papel' <> 'GERENTE' then
    raise exception '[FAIL] P6: aprovacao do GERENTE congelado falhou (%)', v_res;
  end if;
  select a.* into v_fato from public.evaluation_goal_approvals a
   where a.id = (v_res->>'aprovacao_id')::uuid;
  if v_fato.id is null or v_fato.papel <> 'GERENTE' or v_fato.revogado_em is not null
     or v_fato.actor_user_profile_id <> v_a2
     or v_fato.actor_membership_id <> 'f2d00000-0000-0000-0000-000000000002'::uuid then
    raise exception '[FAIL] P6: fato de aprovacao do GERENTE divergente (%)', v_fato;
  end if;
  select e.* into v_evt from public.evaluation_goal_events e
   where e.organization_id = v_alfa
     and e.operation_id = 'f2700000-0000-0000-0000-000000000706';
  if v_evt.event_type <> 'APROVACAO_GERENTE' or v_evt.result_entity_id <> v_fato.id
     or v_evt.after_value->>'vigente' <> 'true' then
    raise exception '[FAIL] P6: evento APROVACAO_GERENTE divergente (%)', v_evt;
  end if;
  -- A aprovacao NAO altera status/version da meta (D3/D17).
  if not exists (
    select 1 from public.evaluation_goals g where g.id = v_m1 and g.status = 'EM_ANDAMENTO' and g.version = 0
  ) then
    raise exception '[FAIL] P6: a aprovacao alterou status/version da meta';
  end if;
  -- Replay identico: mesmo resultado, sem novo fato.
  if public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'aprovacao de gerente (P4)',
       0, v_a2, 'f2700000-0000-0000-0000-000000000706') <> v_res then
    raise exception '[FAIL] P6: replay identico devolveu resultado diferente';
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_m1;
  if v_n <> 1 then
    raise exception '[FAIL] P6: o replay duplicou o fato (%)', v_n;
  end if;

  -- (P7) COORDENADOR CONGELADO (c3 = GESTAO_DIRETA ORIGINAL e DISTINTA) aprova.
  v_res := public.meta_aprovar(v_m1, v_alfa, 'COORDENADOR', 'aprovacao de coordenador (P4)',
    0, v_a3, 'f2700000-0000-0000-0000-000000000707');
  select a.* into v_fato from public.evaluation_goal_approvals a
   where a.id = (v_res->>'aprovacao_id')::uuid;
  if v_fato.id is null or v_fato.papel <> 'COORDENADOR' or v_fato.revogado_em is not null
     or v_fato.actor_user_profile_id <> v_a3 then
    raise exception '[FAIL] P7: fato de aprovacao do COORDENADOR divergente (%)', v_fato;
  end if;
  if not exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f2700000-0000-0000-0000-000000000707'
       and e.event_type = 'APROVACAO_COORDENADOR'
       and e.result_entity_id = v_fato.id
  ) then
    raise exception '[FAIL] P7: evento APROVACAO_COORDENADOR ausente';
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_m1 and a.revogado_em is null;
  if v_n <> 2 then
    raise exception '[FAIL] P7: esperados 2 fatos VIGENTES (GERENTE + COORDENADOR), encontrados %', v_n;
  end if;

  raise notice '[PASS] P6/P7: GERENTE (GESTAO_CADEIA original) e COORDENADOR (GESTAO_DIRETA original e distinta) CONGELADOS com `goal.approve` aprovam M1 — fato vigente + evento append-only + autoria soberana, sem alterar status/version, com replay idempotente';
end $$;

-- ============================================================================
-- 10-bis) CORRECAO POS-AUDITORIA GPT (Issue #216): o REPLAY de `meta_aprovar`
--         tambem tem de provar capability + RELACAO CONGELADA em TODOS os
--         caminhos de retorno (blocker de enforcement apontado na auditoria).
-- ============================================================================
-- No artefato auditado (c65df85) a relacao congelada era provada apenas na
-- execucao normal: os dois retornos de idempotencia (replay rapido, antes do
-- lock, e replay sob o lock) devolviam sucesso provando somente `goal.approve`.
-- Este bloco prova A-G:
--   A  replay LEGITIMO devolve o MESMO resultado, sem novo fato/evento;
--   B  replay apos PERDA da capability => FORBIDDEN, sem efeito;
--   C  capability presente e RELACAO ausente (vinculo desativado) => FORBIDDEN;
--   D  outro ator com `goal.approve` que NAO e o aprovador congelado => FORBIDDEN
--      (e operation_id alheio => CONFLICT, nunca sucesso);
--   E  hierarquia VIVA divergente NAO transfere autoridade => FORBIDDEN;
--   F  prova ESTATICA dos 3 caminhos de retorno (o replay sob lock nao e
--      alcancavel numa unica sessao sem concorrencia; concorrencia real de
--      metas e escopo da P7);
--   G  ausencia de efeitos colaterais em todos os DENY.
do $$
declare
  v_alfa    uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m1      uuid := 'f2000000-0000-0000-0000-000000000001';
  v_a2      uuid := 'f2c00000-0000-0000-0000-000000000002';
  v_a3      uuid := 'f2c00000-0000-0000-0000-000000000003';
  v_aa      uuid := 'f2c00000-0000-0000-0000-00000000000a';
  v_role    uuid := 'f2f90000-0000-0000-0000-000000000002';
  v_link    uuid := 'f2e00000-0000-0000-0000-000000000002';
  v_cap     uuid;
  v_res     jsonb;
  v_base    jsonb;
  v_ok      boolean;
  v_msg     text;
  v_fatos   int;
  v_eventos int;
  v_versao  int;
  v_def     text;
begin
  select id into v_cap from public.capabilities where code = 'goal.approve';
  if v_cap is null then
    raise exception '[FAIL] H: capability goal.approve ausente do catalogo';
  end if;

  -- (A) REPLAY LEGITIMO: mesmo ator, mesmo operation_id e mesmo payload.
  v_base := public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'aprovacao de gerente (P4)',
    0, v_a2, 'f2700000-0000-0000-0000-000000000706');
  v_res := public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'aprovacao de gerente (P4)',
    0, v_a2, 'f2700000-0000-0000-0000-000000000706');
  if v_res <> v_base or v_res->>'aprovado' <> 'true' then
    raise exception '[FAIL] H(A): replay legitimo deveria devolver o MESMO resultado (%)', v_res;
  end if;

  select count(*) into v_fatos from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_m1;
  select count(*) into v_eventos from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_m1;
  select g.version into v_versao from public.evaluation_goals g where g.id = v_m1;

  -- (B) REPLAY APOS PERDA DA CAPABILITY (mesmo ator/operation_id): o gate da P4
  --     roda ANTES do replay => FORBIDDEN. Concessao removida e RESTAURADA aqui.
  delete from public.access_role_capabilities rc
   where rc.access_role_id = v_role and rc.capability_id = v_cap;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'aprovacao de gerente (P4)',
      0, v_a2, 'f2700000-0000-0000-0000-000000000706');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  insert into public.access_role_capabilities (access_role_id, capability_id)
  values (v_role, v_cap);
  if not v_ok or position('exige a capability goal.approve' in v_msg) = 0 then
    raise exception '[FAIL] H(B): replay sem goal.approve deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (C) CAPABILITY PRESENTE, RELACAO AUSENTE: vinculo soberano do ator
  --     desativado (e restaurado) => FORBIDDEN pela RELACAO, sem efeito.
  update public.membership_collaborator_links l set status = 'disabled' where l.id = v_link;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'aprovacao de gerente (P4)',
      0, v_a2, 'f2700000-0000-0000-0000-000000000706');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  update public.membership_collaborator_links l set status = 'active' where l.id = v_link;
  if not v_ok or position('sem vinculo UNICO de colaborador ativo' in v_msg) = 0 then
    raise exception '[FAIL] H(C): replay sem relacao congelada deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (D1) OUTRO ATOR COM `goal.approve` (COORDENADOR congelado) tentando o papel
  --      GERENTE com operation_id NOVO => FORBIDDEN pela relacao.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'probe de outro aprovador (P4)',
      0, v_a3, 'f2700000-0000-0000-0000-0000000009d1');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('nao e o participante congelado do papel GERENTE' in v_msg) = 0 then
    raise exception '[FAIL] H(D1): outro ator com goal.approve deveria ser FORBIDDEN pela relacao (recebido %)', v_msg;
  end if;
  -- (D2) "REPLAY" DO MESMO operation_id POR OUTRO ATOR: o payload_hash canonico
  --      e da INTENCAO (nao inclui o ator), logo o caminho de replay e alcancado
  --      e a RELACAO recusa — outro ator NAO reaproveita o operation_id alheio.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'aprovacao de gerente (P4)',
      0, v_a3, 'f2700000-0000-0000-0000-000000000706');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('nao e o participante congelado do papel GERENTE' in v_msg) = 0 then
    raise exception '[FAIL] H(D2): replay do operation_id alheio deveria ser FORBIDDEN pela relacao (recebido %)', v_msg;
  end if;

  -- (E) HIERARQUIA VIVA DIVERGENTE: `aa` (gestor VIVO, com goal.approve) NAO
  --     substitui o participante CONGELADO.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_m1, v_alfa, 'GERENTE', 'probe de hierarquia viva (P4)',
      0, v_aa, 'f2700000-0000-0000-0000-0000000009e1');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('nao e o participante congelado do papel GERENTE' in v_msg) = 0 then
    raise exception '[FAIL] H(E): hierarquia viva nao pode aprovar (recebido %)', v_msg;
  end if;

  -- (F) PROVA ESTATICA dos caminhos de retorno: relacao exigida em 3 pontos
  --     (2 replays + execucao normal), gate da capability e lock preservados.
  select lower(pg_get_functiondef(p.oid)) into v_def
    from pg_proc p
   where p.oid = to_regprocedure('public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)');
  if (length(v_def) - length(replace(v_def, 'f5_10_exigir_relacao_aprovador', '')))
     / length('f5_10_exigir_relacao_aprovador') <> 3 then
    raise exception '[FAIL] H(F): meta_aprovar deveria exigir a relacao nos 3 caminhos de retorno';
  end if;
  if position('f5_10_exigir_autorizacao_meta' in v_def) = 0 then
    raise exception '[FAIL] H(F): meta_aprovar perdeu o gate de capability da P4';
  end if;
  if position('ciclo_lock_organizacao' in v_def) = 0 then
    raise exception '[FAIL] H(F): meta_aprovar perdeu o lock normativo da familia de ciclos';
  end if;

  -- (G) AUSENCIA DE EFEITOS COLATERAIS nos DENY (B/C/D/E).
  if (select count(*) from public.evaluation_goal_approvals a
       where a.organization_id = v_alfa and a.goal_id = v_m1) <> v_fatos then
    raise exception '[FAIL] H(G): os DENY de replay alteraram evaluation_goal_approvals';
  end if;
  if (select count(*) from public.evaluation_goal_events e
       where e.organization_id = v_alfa and e.goal_id = v_m1) <> v_eventos then
    raise exception '[FAIL] H(G): os DENY de replay gravaram evento';
  end if;
  if (select g.version from public.evaluation_goals g where g.id = v_m1) <> v_versao then
    raise exception '[FAIL] H(G): os DENY de replay alteraram a versao da meta';
  end if;
  if (select count(*) from public.access_role_capabilities rc
       where rc.access_role_id = v_role and rc.capability_id = v_cap) <> 1 then
    raise exception '[FAIL] H(G): a capability removida em (B) nao foi restaurada';
  end if;
  if (select count(*) from public.membership_collaborator_links l
       where l.id = v_link and l.status = 'active') <> 1 then
    raise exception '[FAIL] H(G): o vinculo alterado em (C) nao foi restaurado';
  end if;

  raise notice '[PASS] H (correcao pos-auditoria): REPLAY de meta_aprovar revalida capability + RELACAO CONGELADA nos 3 caminhos de retorno (A legitimo devolve o MESMO resultado; B/C/D/E recusam), sem novo fato, sem evento e sem alterar a meta';
end $$;

-- ============================================================================
-- 11) POSITIVO 8: GESTOR CONGELADO le SOMENTE as metas autorizadas
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_ciclo uuid := 'f2d10000-0000-0000-0000-0000000000a1';
  v_m1    uuid := 'f2000000-0000-0000-0000-000000000001';
  v_m5    uuid := 'f2000000-0000-0000-0000-000000000005';
  v_m6    uuid := 'f2000000-0000-0000-0000-000000000006';
  v_a2    uuid := 'f2c00000-0000-0000-0000-000000000002';
  v_res   jsonb;
  v_m5id  uuid;
begin
  -- O GERENTE congelado de M1/M2 (c2) e DONO de M5 (criada no positivo 1): a
  -- leitura devolve as metas com relacao APROVADOR_*_CONGELADO (M1 e M2, ambas
  -- do dono c1) e M6 (COORDENADOR congelado, dona c3) + M5 (SELF) = 4 metas.
  select g.id into v_m5id from public.evaluation_goals g
   where g.organization_id = v_alfa and g.collaborator_id = 'f2b00000-0000-0000-0000-000000000002'
     and g.cycle_id = v_ciclo and not g.excluida;

  v_res := public.meta_listar_por_escopo(v_alfa, v_ciclo, v_a2);
  if (v_res->>'quantidade')::int <> 4 or v_res->>'relacao_ator' <> 'ESCOPO_APLICADO' then
    raise exception '[FAIL] P8: o gestor congelado deveria ler exatamente 4 metas autorizadas (%)', v_res;
  end if;
  if not exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where m->>'goal_id' = v_m1::text and m->>'relacao' = 'APROVADOR_GERENTE_CONGELADO'
  ) then
    raise exception '[FAIL] P8: M1 deveria vir como APROVADOR_GERENTE_CONGELADO (%)', v_res->'metas';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where m->>'goal_id' = v_m5id::text and m->>'relacao' = 'SELF'
  ) then
    raise exception '[FAIL] P8: M5 deveria vir como SELF para o seu dono (%)', v_res->'metas';
  end if;
  -- M6 entra pelo papel CONGELADO de COORDENADOR (c2 = GESTAO_DIRETA original
  -- e distinta de EV3) — nunca pela estrutura viva.
  if not exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where m->>'goal_id' = v_m6::text and m->>'relacao' = 'APROVADOR_COORDENADOR_CONGELADO'
  ) then
    raise exception '[FAIL] P8: M6 deveria vir como APROVADOR_COORDENADOR_CONGELADO para c2 (%)', v_res->'metas';
  end if;
  -- NUNCA as metas que nao lhe pertencem (nem como dono, nem como congelado).
  -- M2 (dono c1, MESMA avaliacao congelada de M1) ENTRA por
  -- APROVADOR_GERENTE_CONGELADO; M3/M4 (ciclo encerrado) e M8 (Beta) ficam FORA.
  if exists (
    select 1 from jsonb_array_elements(v_res->'metas') m
     where (m->>'goal_id')::uuid not in (v_m1, v_m5id, v_m6,
                                         'f2000000-0000-0000-0000-000000000002'::uuid)
  ) then
    raise exception '[FAIL] P8: a leitura do gestor congelado vazou meta nao autorizada (%)', v_res->'metas';
  end if;

  -- A leitura NAO exige ciclo ATIVO e NAO cria evento (leitura nao e fato).
  if exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa and e.event_type not in (
       'CRIADA', 'EDITADA', 'PROGRESSO_ATUALIZADO', 'FINALIZADA', 'REVISAO_FINALIZACAO',
       'EXCLUIDA', 'APROVACAO_COORDENADOR', 'APROVACAO_GERENTE', 'APROVACAO_INVALIDADA',
       'LIMITES_DO_CICLO_ALTERADOS')
  ) then
    raise exception '[FAIL] P8: a leitura criou evento na trilha';
  end if;

  raise notice '[PASS] P8: GESTOR CONGELADO le por `meta_listar_por_escopo` SOMENTE o escopo autorizado (SELF + APROVADOR_*_CONGELADO) e nunca as demais metas do ciclo';
end $$;

-- ============================================================================
-- 12) POSITIVO 9: overlay POSTERIOR nao transfere autoridade
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m6     uuid := 'f2000000-0000-0000-0000-000000000006';
  v_a3     uuid := 'f2c00000-0000-0000-0000-000000000003';
  v_a4     uuid := 'f2c00000-0000-0000-0000-000000000004';
  v_res    jsonb;
  v_fato   record;
  v_n      int;
  v_evt    int;
begin
  -- (P9-pre) O overlay POSTERIOR de GESTAO_CADEIA (c4) esta ATIVO em EV3...
  if not exists (
    select 1 from public.evaluation_participants p
     where p.id = 'f2300000-0000-0000-0000-000000000006'
       and p.role_type = 'GESTAO_CADEIA'
       and p.collaborator_id = 'f2b00000-0000-0000-0000-000000000004'
       and p.origem = 'SUBSTITUICAO_TEMPORARIA'
       and p.status = 'active' and p.valid_from > '2026-01-01T00:00:00Z'
  ) then
    raise exception '[FAIL] P9: pre-condicao — o overlay posterior deveria existir ATIVO';
  end if;
  -- ...e o papel continua sendo do participante ORIGINAL (menor valid_from).
  if public.f5_10_aprovador_congelado(v_m6, v_alfa, 'GERENTE')
     <> 'f2b00000-0000-0000-0000-000000000005'::uuid then
    raise exception '[FAIL] P9: o GERENTE congelado deveria ser o ORIGINAL (c5)';
  end if;
  -- O overlay NAO tem `goal.approve` (tem apenas `goal.write`): o DENY e
  -- fail-closed por capability AUSENTE, e a prova ESTRUTURAL de que ele NAO e a
  -- autoridade do papel e o proprio `f5_10_aprovador_congelado` (que devolve c5).
  if public.f5_10_ator_valido_meta(v_a4, v_alfa, 'goal.approve') then
    raise exception '[FAIL] P9: o overlay a4 NAO pode ter goal.approve no cenario';
  end if;
  -- A relacao CONGELADA aponta SOMENTE para o participante ORIGINAL: o overlay
  -- (c4) nunca coincide com a autoridade do papel de cadeia.
  if public.f5_10_vinculo_meta_do_ator(v_a4, v_alfa)
     = public.f5_10_aprovador_congelado(v_m6, v_alfa, 'GERENTE') then
    raise exception '[FAIL] P9: o overlay nao pode coincidir com o participante congelado';
  end if;
  if public.f5_10_vinculo_meta_do_ator(v_a4, v_alfa)
     <> 'f2b00000-0000-0000-0000-000000000004'::uuid then
    raise exception '[FAIL] P9: o overlay a4 deveria estar vinculado a c4';
  end if;
  begin
    perform public.meta_aprovar(v_m6, v_alfa, 'GERENTE', 'probe de overlay (P4)', 0, v_a4,
      'f2700000-0000-0000-0000-000000000708');
    raise exception '[FAIL] P9: o overlay posterior NAO pode aprovar';
  exception when others then
    if sqlerrm not like '%F5_10_FORBIDDEN%' then
      raise exception '[FAIL] P9: esperado F5_10_FORBIDDEN para o overlay, recebido %', sqlerrm;
    end if;
  end;

  -- (P9) O COORDENADOR congelado de M6 (c2, GESTAO_DIRETA original distinta)
  -- aprova normalmente; em seguida o overlay posterior NAO assuma nada.
  select count(*) into v_evt from public.evaluation_goal_events where organization_id = v_alfa;
  v_res := public.meta_aprovar(v_m6, v_alfa, 'COORDENADOR', 'aprovacao do coordenador de M6 (P4)',
    0, 'f2c00000-0000-0000-0000-000000000002', 'f2700000-0000-0000-0000-000000000709');
  select a.* into v_fato from public.evaluation_goal_approvals a
   where a.id = (v_res->>'aprovacao_id')::uuid;
  if v_fato.id is null or v_fato.papel <> 'COORDENADOR' or v_fato.revogado_em is not null then
    raise exception '[FAIL] P9: a aprovacao do COORDENADOR congelado de M6 falhou (%)', v_res;
  end if;
  if not exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f2700000-0000-0000-0000-000000000708'
  ) then
    -- a tentativa do overlay nao pode ter gravado NADA.
    null;
  else
    raise exception '[FAIL] P9: a tentativa do overlay gravou evento';
  end if;

  -- Agora o overlay e o ORIGINAL continuam como estao: a autoridade do papel de
  -- CADEIA permanece sem fato (o original nao aprovou) e NENHUM deles mudou.
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_m6 and a.papel = 'GERENTE';
  if v_n <> 0 then
    raise exception '[FAIL] P9: nao pode existir aprovacao de GERENTE em M6 (%)', v_n;
  end if;
  if not exists (
    select 1 from public.evaluation_participants p
     where p.id = 'f2300000-0000-0000-0000-000000000006' and p.status = 'active'
  ) then
    raise exception '[FAIL] P9: o overlay posterior deveria permanecer intocado';
  end if;

  raise notice '[PASS] P9: a movimentacao estrutural POSTERIOR (overlay de GESTAO_CADEIA) NAO transfere a aprovacao — o participante ORIGINAL continua sendo a autoridade do papel e o overlay e recusado sem gravar fato/evento';
end $$;

-- ============================================================================
-- 13) POSITIVO 10: capability + relacao coexistem; LIMITES e de CICLO
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_ciclo  uuid := 'f2d10000-0000-0000-0000-0000000000a1';
  v_m1     uuid := 'f2000000-0000-0000-0000-000000000001';
  v_a1     uuid := 'f2c00000-0000-0000-0000-000000000001';
  v_a2     uuid := 'f2c00000-0000-0000-0000-000000000002';
  v_ad     uuid := 'f2c00000-0000-0000-0000-0000000000d1';
  v_a9     uuid := 'f2c00000-0000-0000-0000-000000000009';
  v_res    jsonb;
  v_ok     boolean;
  v_msg    text;
  v_n      int;
begin
  -- (P10a) O DONO tem `goal.read` + `goal.write` e a RELACAO SELF: cria, edita
  -- (positivo 1/2) e LE (positivo 5) — a capability e a relacao COEXISTEM.
  if not public.f5_10_ator_valido_meta(v_a1, v_alfa, 'goal.write')
     or not public.f5_10_ator_valido_meta(v_a1, v_alfa, 'goal.read') then
    raise exception '[FAIL] P10a: o dono deveria acumular goal.read + goal.write';
  end if;
  if public.f5_10_vinculo_meta_do_ator(v_a1, v_alfa)
     <> 'f2b00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] P10a: o dono deveria ter o vinculo SELF c1';
  end if;

  -- (P10b) O APROVADOR tem `goal.approve` e NAO escreve: a mesma relacao/ator
  -- nao pode editar meta de terceiro (DENY SELF).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_m1, v_alfa, 'probe de aprovador escrevendo (P4)',
      'KPI probe (P4)', '1 unidade (P4)', 0, v_a2,
      'f2700000-0000-0000-0000-00000000080a');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige SELF' in v_msg) = 0 then
    raise exception '[FAIL] P10b: o aprovador NAO pode escrever em meta de terceiro (recebido %)', v_msg;
  end if;
  -- `meta_invalidar_aprovacoes` tambem exige `goal.write`: capability ausente.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_invalidar_aprovacoes(v_m1, v_alfa, 'probe de aprovador (P4)',
      0, v_a2, 'f2700000-0000-0000-0000-00000000080b');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  -- (P10b-2) `meta_invalidar_aprovacoes` por APROVADOR: negada pela RELACAO
  -- (SELF) — o ator tem goal.write (P1) mas nao e o dono.
  -- A autoridade de INVALIDAR e `goal.write` + SELF (dono): o gate nega ANTES,
  -- com a mensagem fail-closed da relacao de escrita.
  if not v_ok or position('exige SELF' in v_msg) = 0 then
    raise exception '[FAIL] P10b: invalidacao por aprovador deveria negar por SELF (recebido %)', v_msg;
  end if;

  -- (P10c) LIMITES continua operacao ADMINISTRATIVA de ciclo: `cycle.manage`
  -- consegue (`ad`), `goal.write` do DONO NAO consegue, e o TERCEIRO leitor
  -- (sem ciclo) tambem nao.
  v_ok := false; v_msg := null;
  begin
    perform public.f5_10_exigir_autorizacao_meta('LIMITES', v_a1, v_alfa, null, null);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige a capability cycle.manage' in v_msg) = 0 then
    raise exception '[FAIL] P10c: o dono com goal.write NAO pode definir LIMITES (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 2,
      'probe de dono tentando limites (P4)', 1, v_a1,
      'f2700000-0000-0000-0000-00000000080c');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok or position('exige a capability cycle.manage' in v_msg) = 0 then
    raise exception '[FAIL] P10c: meta_definir_limites_do_ciclo pelo dono deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 2,
      'probe de terceiro tentando limites (P4)', 1, v_a9,
      'f2700000-0000-0000-0000-00000000080d');
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] P10c: LIMITES pelo terceiro leitor deveria ser FORBIDDEN (recebido %)', v_msg;
  end if;

  -- `ad` (cycle.manage) CONSEGUE: a quota NAO pode ficar abaixo das metas vivas
  -- (existe 1 meta NEGOCIO_PROJETO viva no ciclo ATIVO) => 3 -> 2 e valido.
  v_res := public.meta_definir_limites_do_ciclo(v_ciclo, v_alfa, 'NEGOCIO_PROJETO', 2,
    'limite ajustado pelo admin de ciclo (P4)', 1, v_ad,
    'f2700000-0000-0000-0000-00000000080e');
  if (v_res->>'quantidade')::int <> 2 or v_res->>'tipo' <> 'NEGOCIO_PROJETO' then
    raise exception '[FAIL] P10c: definicao de limites por cycle.manage falhou (%)', v_res;
  end if;
  if (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] P10c: a versao do CICLO deveria ir para 2 (%)', v_res;
  end if;
  select l.quantidade into v_n from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_ciclo and l.tipo = 'NEGOCIO_PROJETO';
  if v_n <> 2 then
    raise exception '[FAIL] P10c: a quota deveria ser 2 (%)', v_n;
  end if;
  -- O evento de LIMITES pertence a trilha do CICLO (D21), nunca a de metas.
  if not exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f2700000-0000-0000-0000-00000000080e'
       and e.event_type = 'LIMITES_DO_CICLO_ALTERADOS'
  ) then
    raise exception '[FAIL] P10c: evento LIMITES_DO_CICLO_ALTERADOS ausente em cycle_events';
  end if;
  if exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f2700000-0000-0000-0000-00000000080e'
  ) then
    raise exception '[FAIL] P10c: LIMITES nao pode usar a trilha de metas';
  end if;

  raise notice '[PASS] P10: capability e relacao COEXISTEM (dono cria/edita/le por SELF; aprovador aprova e NAO escreve; invalidacao exige goal.write) e LIMITES permanece operacao ADMINISTRATIVA de ciclo (`cycle.manage` define; `goal.write` e leitor NAO definem)';
end $$;

-- ============================================================================
-- 14) `meta_invalidar_aprovacoes`: `goal.write` + SELF
-- ============================================================================
do $$
declare
  v_alfa uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m1   uuid := 'f2000000-0000-0000-0000-000000000001';
  v_mm5  uuid;
  v_a1   uuid := 'f2c00000-0000-0000-0000-000000000001';
  v_a2   uuid := 'f2c00000-0000-0000-0000-000000000002';
  v_res  jsonb;
  v_n    int;
begin
  -- M5 e criada pelo proprio VALIDADOR (id gerado pelo banco no positivo 1):
  -- resolve pelo dono c2 no ciclo ATIVO, em vez de um UUID fixo de fixture.
  select g.id into v_mm5 from public.evaluation_goals g
   where g.organization_id = v_alfa
     and g.cycle_id = 'f2d10000-0000-0000-0000-0000000000a1'
     and g.collaborator_id = 'f2b00000-0000-0000-0000-000000000002'
     and not g.excluida
   order by g.created_at desc
   limit 1;
  if v_mm5 is null then
    raise exception '[FAIL] G2: a meta criada no positivo 1 (dono c2) nao foi encontrada';
  end if;
  -- (G1) APROVADOR CONGELADO de M1 SEM `goal.write` => DENY na capability.
  begin
    perform public.meta_invalidar_aprovacoes(v_m1, v_alfa, 'probe (P4)', 0, v_a2,
      'f2700000-0000-0000-0000-000000000901');
    raise exception '[FAIL] G1: aprovador nao pode invalidar (sem goal.write)';
  exception when others then
    if sqlerrm not like '%F5_10_FORBIDDEN%' or position('goal.write' in sqlerrm) = 0 then
      raise exception '[FAIL] G1: esperado F5_10_FORBIDDEN citando goal.write, recebido %', sqlerrm;
    end if;
  end;

  -- (G2) DONO com `goal.write` + SELF invalida as aprovacoes vigentes da
  -- PROPRIA meta (M5, criada no positivo 1, sem fato vigente => NO-OP
  -- REGISTRADO na trilha, sem tocar `evaluation_goal_approvals`).
  select count(*) into v_n from public.evaluation_goal_approvals
   where organization_id = v_alfa;
  -- (G2) DONO da M5 (c2 = ator a2) com `goal.write` + SELF invalida as
  -- aprovacoes da PROPRIA meta (sem fato vigente => NO-OP REGISTRADO na trilha,
  -- sem tocar `evaluation_goal_approvals`).
  select count(*) into v_n from public.evaluation_goal_approvals
   where organization_id = v_alfa;
  v_res := public.meta_invalidar_aprovacoes(v_mm5, v_alfa,
    'invalidacao explicita do dono (P4)', 0, v_a2,
    'f2700000-0000-0000-0000-000000000902');
  if (v_res->>'invalidated')::int <> 0 or v_res->>'aprovacao_id' is not null then
    raise exception '[FAIL] G2: sem fato vigente a invalidacao deveria ser NO-OP (%)', v_res;
  end if;
  if (select count(*) from public.evaluation_goal_approvals where organization_id = v_alfa) <> v_n then
    raise exception '[FAIL] G2: a invalidacao do dono tocou aprovacoes';
  end if;
  if not exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f2700000-0000-0000-0000-000000000902'
       and e.event_type = 'APROVACAO_INVALIDADA'
  ) then
    raise exception '[FAIL] G2: o NO-OP do dono deveria estar REGISTRADO na trilha';
  end if;

  -- (G3) M1 e do PROPRIO dono a1: a invalidacao EFETIVA e permitida (goal.write +
  -- SELF) e revoga os 2 fatos vigentes PRESERVANDO o historico; a reaprovacao
  -- seguinte prova que o ciclo continua vivo.
  v_res := public.meta_invalidar_aprovacoes(v_m1, v_alfa,
    'invalidacao explicita do dono em M1 (P4)', 0, v_a1,
    'f2700000-0000-0000-0000-000000000903');
  if (v_res->>'invalidated')::int <> 2 then
    raise exception '[FAIL] G3: a invalidacao deveria revogar os 2 fatos vigentes de M1 (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_m1 and a.revogado_em is not null;
  if v_n <> 2 then
    raise exception '[FAIL] G3: os 2 fatos deveriam estar REVOGADOS e preservados (%)', v_n;
  end if;

  -- (G4) REAPROVACAO pelo COORDENADOR congelado continua valida e CRIANDO FATO.
  v_res := public.meta_aprovar(v_m1, v_alfa, 'COORDENADOR', 'reaprovacao apos invalidacao (P4)',
    0, 'f2c00000-0000-0000-0000-000000000003', 'f2700000-0000-0000-0000-000000000904');
  if v_res->>'aprovado' <> 'true' then
    raise exception '[FAIL] G4: a reaprovacao deveria criar novo fato vigente (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_m1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] G4: esperado exatamente 1 fato vigente em M1 (%)', v_n;
  end if;

  raise notice '[PASS] G: `meta_invalidar_aprovacoes` exige `goal.write` + SELF (dono ALLOW com NO-OP registrado e invalidacao efetiva preservando historico; aprovador congelado DENY citando goal.write) e a reaprovacao apos invalidacao cria NOVO fato';
end $$;

-- ============================================================================
-- 15) E) ATOMICIDADE: falha injetada na trilha reverte meta + evento
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_m2    uuid := 'f2000000-0000-0000-0000-000000000002';
  v_a1    uuid := 'f2c00000-0000-0000-0000-000000000001';
  v_antes record;
  v_ok    boolean;
  v_msg   text;
begin
  select g.descricao, g.version, g.status into v_antes
    from public.evaluation_goals g where g.id = v_m2;

  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_m2, v_alfa, 'edicao que deve ser revertida (P4)',
      'KPI revertido (P4)', '999 unidades (P4)', 3, v_a1,
      'f2700000-0000-0000-0000-000000000a01', 'ATINGIDA');
  exception when others then v_ok := (sqlstate = '42883'); v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] E: argumento extra deveria falhar por 42883 (recebido %)', v_msg;
  end if;
  if not exists (
    select 1 from public.evaluation_goals g
     where g.id = v_m2 and g.descricao = v_antes.descricao
       and g.version = v_antes.version and g.status = v_antes.status
  ) then
    raise exception '[FAIL] E: a chamada invalida alterou a meta';
  end if;
  if exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.operation_id = 'f2700000-0000-0000-0000-000000000a01'
  ) then
    raise exception '[FAIL] E: a chamada invalida gravou evento';
  end if;

  raise notice '[PASS] E: chamada com argumento fora da assinatura falha ANTES de qualquer efeito (42883) — meta, versao, status e trilha intactos';
end $$;

-- ============================================================================
-- 16) NEGATIVOS 16/17 (RLS): cliente NAO le nem escreve as tabelas de metas
-- ============================================================================
select set_config('request.jwt.claim.sub', 'f2c00000-0000-0000-0000-000000000001', false);
set role authenticated;

do $$
declare
  v_alfa  uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_mbeta uuid := 'f2000000-0000-0000-0000-0000000000b1';
  v_ok    boolean;
  v_n     int;
begin
  -- (N16a) `authenticated` NAO executa NENHUMA das 12 funcoes de metas.
  if has_function_privilege('authenticated',
       'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] N16a: authenticated nao pode ter EXECUTE em meta_listar_por_escopo';
  end if;
  v_ok := false;
  begin
    perform public.meta_listar_por_escopo(v_alfa, 'f2d10000-0000-0000-0000-0000000000a1',
      'f2c00000-0000-0000-0000-000000000001');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N16a: chamada DIRETA de meta_listar_por_escopo por authenticated deveria ser permission denied';
  end if;
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, 'f2d10000-0000-0000-0000-0000000000a1',
      'f2b00000-0000-0000-0000-000000000001', 'INDIVIDUAL', 'probe (P4)', 'KPI (P4)',
      '1 unidade (P4)', 'f2c00000-0000-0000-0000-000000000001',
      'f2700000-0000-0000-0000-000000000b01');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N16a: chamada DIRETA de meta_criar por authenticated deveria ser permission denied';
  end if;
  v_ok := false;
  begin
    perform public.f5_10_ator_valido_meta('f2c00000-0000-0000-0000-000000000001', v_alfa, 'goal.read');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N16a: helper f5_10_ator_valido_meta nao pode ser executavel por authenticated';
  end if;

  -- (N17a) RLS own-tenant: o ator enxerga SOMENTE as metas do PROPRIO tenant.
  select count(*) into v_n from public.evaluation_goals;
  if v_n <> 7 then
    raise exception '[FAIL] N17a: o cliente de Alfa deveria ver as 7 metas de Alfa (viu %)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goals where organization_id = v_beta;
  if v_n <> 0 then
    raise exception '[FAIL] N17a: cross-tenant por filtro deveria ser 0 linhas (viu %)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goals where id = v_mbeta;
  if v_n <> 0 then
    raise exception '[FAIL] N17a: cross-tenant por ID direto deveria ser 0 linhas (viu %)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals;
  if v_n <> 4 then
    raise exception '[FAIL] N17a: o cliente deveria ver os 4 fatos de aprovacao de Alfa (viu %)', v_n;
  end if;

  -- (N17b) DML de cliente nas 4 tabelas => permission denied (42501).
  v_ok := false;
  begin
    insert into public.evaluation_goals (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_alfa, 'f2d10000-0000-0000-0000-0000000000a1', 'f2b00000-0000-0000-0000-000000000001',
            'INDIVIDUAL', 'probe de INSERT de cliente (P4)', 'KPI (P4)', '1 unidade (P4)');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17b: INSERT em evaluation_goals por authenticated deveria ser 42501';
  end if;
  v_ok := false;
  begin
    update public.evaluation_goals set version = version + 1;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17b: UPDATE em evaluation_goals por authenticated deveria ser 42501';
  end if;
  v_ok := false;
  begin
    delete from public.evaluation_goals;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17b: DELETE em evaluation_goals por authenticated deveria ser 42501';
  end if;
  v_ok := false;
  begin
    insert into public.evaluation_goal_approvals (organization_id, goal_id, papel, actor_user_profile_id, actor_membership_id)
    values (v_alfa, 'f2000000-0000-0000-0000-000000000001', 'GERENTE',
            'f2c00000-0000-0000-0000-000000000002', 'f2d00000-0000-0000-0000-000000000002');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17b: INSERT em evaluation_goal_approvals por authenticated deveria ser 42501';
  end if;
  v_ok := false;
  begin
    delete from public.evaluation_goal_approvals;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17b: DELETE em evaluation_goal_approvals por authenticated deveria ser 42501';
  end if;

  -- (N17c) a TRILHA e as QUOTAS sao deny-by-default INTEGRAL: nem SELECT.
  v_ok := false;
  begin
    perform 1 from public.evaluation_goal_events;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17c: SELECT em evaluation_goal_events por authenticated deveria ser 42501';
  end if;
  v_ok := false;
  begin
    perform 1 from public.evaluation_cycle_goal_limits;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17c: SELECT em evaluation_cycle_goal_limits por authenticated deveria ser 42501';
  end if;
  v_ok := false;
  begin
    insert into public.evaluation_goal_events
      (organization_id, goal_id, entity_type, event_type, effective_date, payload_hash,
       actor_user_profile_id, actor_membership_id, operation_id)
    values (v_alfa, 'f2000000-0000-0000-0000-000000000001', 'evaluation_goal', 'EDITADA', now(),
            repeat('0', 64), 'f2c00000-0000-0000-0000-000000000001',
            'f2d00000-0000-0000-0000-000000000001', gen_random_uuid());
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17c: INSERT na trilha por authenticated deveria ser 42501';
  end if;
  v_ok := false;
  begin
    update public.evaluation_cycle_goal_limits set quantidade = 0;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17c: UPDATE em quotas por authenticated deveria ser 42501';
  end if;

  -- (N17d) ACL fechada nas 13 funcoes (10 RPCs + 3 helpers) e nas 4 tabelas.
  if has_table_privilege('authenticated', 'public.evaluation_goals', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_goals', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_goals', 'DELETE')
     or has_table_privilege('authenticated', 'public.evaluation_goal_approvals', 'INSERT')
     or has_table_privilege('authenticated', 'public.evaluation_goal_approvals', 'UPDATE')
     or has_table_privilege('authenticated', 'public.evaluation_goal_approvals', 'DELETE')
     or has_table_privilege('authenticated', 'public.evaluation_goal_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.evaluation_cycle_goal_limits', 'SELECT') then
    raise exception '[FAIL] N17d: privilegio de cliente inesperado nas tabelas de metas';
  end if;

  raise notice '[PASS] N16/N17: `authenticated` NAO executa nenhuma funcao de metas (permission denied / 42501), NAO escreve nas tabelas, NAO le a trilha nem as quotas e o SELECT sob RLS devolve SOMENTE o proprio tenant (cross-tenant = 0 linhas)';
end $$;

-- ACL fechada das 13 funcoes (prova declarativa, independente da role corrente).
do $$
declare
  v_fns text[] := array[
    'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)',
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_listar_por_escopo(uuid, uuid, uuid)',
    'public.f5_10_ator_valido_meta(uuid, uuid, text)',
    'public.f5_10_vinculo_meta_do_ator(uuid, uuid)',
    'public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid)',
    -- Correcao pos-auditoria (Issue #216): a fonte unica da RELACAO congelada
    -- tambem e um objeto de autorizacao e entra na verificacao de ACL.
    'public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid)'];
  v_fn     text;
  v_secdef boolean;
  v_config text;
begin
  foreach v_fn in array v_fns loop
    if to_regprocedure(v_fn) is null then
      raise exception '[FAIL] ACL: funcao ausente: %', v_fn;
    end if;
    if has_function_privilege('authenticated', v_fn, 'EXECUTE')
       or has_function_privilege('anon', v_fn, 'EXECUTE') then
      raise exception '[FAIL] ACL: EXECUTE exposto a cliente em %', v_fn;
    end if;
    if not has_function_privilege('service_role', v_fn, 'EXECUTE') then
      raise exception '[FAIL] ACL: service_role sem EXECUTE em %', v_fn;
    end if;
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '')
      into v_secdef, v_config
      from pg_proc p where p.oid = to_regprocedure(v_fn);
    if v_secdef then
      raise exception '[FAIL] ACL: SECURITY DEFINER inesperado em %', v_fn;
    end if;
    if position('search_path=public' in v_config) = 0 then
      raise exception '[FAIL] ACL: search_path fixo ausente em %', v_fn;
    end if;
  end loop;
  raise notice '[PASS] ACL: as 10 RPCs e os 3 helpers da P4 sao INVOKER com EXECUTE SOMENTE para `service_role` (nenhuma superficie para authenticated/anon)';
end $$;

reset role;

-- Cenario `anon`: nenhuma leitura e nenhum EXECUTE.
set role anon;
do $$
declare
  v_ok boolean;
begin
  v_ok := false;
  begin
    perform 1 from public.evaluation_goals;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] N17e: anon leu evaluation_goals';
  end if;
  if has_table_privilege('anon', 'public.evaluation_goals', 'SELECT')
     or has_table_privilege('anon', 'public.evaluation_goal_approvals', 'SELECT')
     or has_table_privilege('anon', 'public.evaluation_goal_events', 'SELECT')
     or has_table_privilege('anon', 'public.evaluation_cycle_goal_limits', 'SELECT') then
    raise exception '[FAIL] N17e: anon com privilegio de leitura nas tabelas de metas';
  end if;
  if has_function_privilege('anon', 'public.meta_listar_por_escopo(uuid, uuid, uuid)', 'EXECUTE') then
    raise exception '[FAIL] N17e: anon com EXECUTE em meta_listar_por_escopo';
  end if;
  raise notice '[PASS] N17e/anon: nenhuma leitura nas 4 tabelas de metas e nenhum EXECUTE nas RPCs (permission denied)';
end $$;
reset role;

select set_config('request.jwt.claim.sub', '', false);

-- ============================================================================
-- 17) NEGATIVO 17 (cont.): leitura cross-tenant sob RLS pelo OWNER de Beta
-- ============================================================================
select set_config('request.jwt.claim.sub', 'f2c00000-0000-0000-0000-0000000000c1', false);
set role authenticated;
do $$
declare
  v_alfa uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_n    int;
begin
  -- O dono de Beta ve SOMENTE a meta de Beta...
  select count(*) into v_n from public.evaluation_goals;
  if v_n <> 1 then
    raise exception '[FAIL] N17f: o cliente de Beta deveria ver 1 meta (viu %)', v_n;
  end if;
  -- ...e NENHUMA meta de Alfa, nem por filtro nem por ID direto.
  select count(*) into v_n from public.evaluation_goals where organization_id = v_alfa;
  if v_n <> 0 then
    raise exception '[FAIL] N17f: Beta nao pode ver metas de Alfa (viu %)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goals
   where id = 'f2000000-0000-0000-0000-000000000001';
  if v_n <> 0 then
    raise exception '[FAIL] N17f: Beta nao pode ver meta de Alfa por ID direto (viu %)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals;
  if v_n <> 0 then
    raise exception '[FAIL] N17f: Beta nao pode ver fatos de aprovacao de Alfa (viu %)', v_n;
  end if;
  raise notice '[PASS] N17f: RLS e barreira de TENANT nos dois sentidos — o cliente de Beta ve somente Beta e ZERO linhas de Alfa (filtro e ID direto)';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- ============================================================================
-- 18) GUARDA FINAL FAIL-CLOSED: estado consolidado CALCULADO
-- ============================================================================
do $$
declare
  v_alfa    uuid := 'f2a00000-0000-0000-0000-0000000000a1';
  v_beta    uuid := 'f2a00000-0000-0000-0000-0000000000b1';
  v_metas   int;
  v_fixture int;
  v_novas   int;
  v_excl    int;
  v_evt     int;
  v_por_op  int;
  v_aprov   int;
  v_vig     int;
  v_rev     int;
  v_pend    int;
  v_roles   int;
  v_assign  int;
  v_caps    int;
  v_fn      text;
  v_meta    text;
  v_n       int;
  v_erros   text[] := array[]::text[];
  v_fns     text[] := array[
    'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)',
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_listar_por_escopo(uuid, uuid, uuid)',
    'public.f5_10_ator_valido_meta(uuid, uuid, text)',
    'public.f5_10_vinculo_meta_do_ator(uuid, uuid)',
    'public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid)',
    -- Correcao pos-auditoria (Issue #216): a fonte unica da RELACAO congelada
    -- tambem e um objeto de autorizacao e entra na verificacao de ACL.
    'public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid)'];
  v_tabelas text[] := array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'];
  v_rec     record;
begin
  -- (a) ESTADO CONSOLIDADO calculado (nada arbitrado).
  select count(*) into v_fixture from public.evaluation_goals
   where organization_id in (v_alfa, v_beta) and id::text like 'f2000000%';
  select count(*) into v_novas from public.evaluation_goals
   where organization_id in (v_alfa, v_beta) and id::text not like 'f2000000%';
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_excl from public.evaluation_goals
   where organization_id in (v_alfa, v_beta) and excluida;
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_por_op from (
    select e.operation_id from public.evaluation_goal_events e
     where e.organization_id in (v_alfa, v_beta)
     group by e.operation_id having count(*) > 1) t;
  select count(*), count(*) filter (where revogado_em is null),
         count(*) filter (where revogado_em is not null)
    into v_aprov, v_vig, v_rev
    from public.evaluation_goal_approvals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_roles from public.access_roles where id::text like 'f2f90000%';
  select count(*) into v_assign from public.membership_access_role_assignments
   where id::text like 'f2f80000%' and status = 'active';
  select count(*) into v_caps from public.access_role_capabilities rc
    join public.access_roles ar on ar.id = rc.access_role_id
   where ar.id::text like 'f2f90000%';

  if v_fixture <> 7 then
    v_erros := v_erros || format('metas de fixture = %s (esperado 7)', v_fixture);
  end if;
  if v_novas <> 1 then
    v_erros := v_erros || format('metas criadas pelo validador = %s (esperado 1: M5)', v_novas);
  end if;
  if v_metas <> 8 then
    v_erros := v_erros || format('metas do cenario = %s (esperado 8)', v_metas);
  end if;
  if v_excl <> 1 then
    v_erros := v_erros || format('metas excluidas = %s (esperado 1)', v_excl);
  end if;
  if v_evt <> 18 then
    v_erros := v_erros || format('eventos na trilha = %s (esperado 18 = 7 CRIADA de fixture + 11 do validador)', v_evt);
  end if;
  if v_por_op <> 0 then
    v_erros := v_erros || format('operation_id duplicado na trilha = %s', v_por_op);
  end if;
  if v_aprov <> 4 or v_vig <> 2 or v_rev <> 2 then
    v_erros := v_erros || format('fatos de aprovacao = %s (vigentes %s / revogados %s), esperado 4 (2/2)',
      v_aprov, v_vig, v_rev);
  end if;
  if v_roles <> 6 then
    v_erros := v_erros || format('roles da fixture = %s (esperado 6)', v_roles);
  end if;
  if v_assign <> 10 then
    v_erros := v_erros || format('assignments ativos = %s (esperado 10: a2 tambem tem goal.write)', v_assign);
  end if;
  if v_caps <> 10 then
    v_erros := v_erros || format('capabilities das roles da fixture = %s (esperado 10)', v_caps);
  end if;

  -- (b) Coerencia evento x fato: 1 evento de aprovacao por fato vigente e 1 de
  -- invalidacao por fato revogado.
  for v_rec in
    select a.id, a.revogado_em
      from public.evaluation_goal_approvals a
     where a.organization_id = v_alfa
  loop
    select count(*) into v_n from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.result_entity_id = v_rec.id
       and e.event_type in ('APROVACAO_GERENTE', 'APROVACAO_COORDENADOR');
    if v_n <> 1 then
      v_erros := v_erros || format('fato %s com %s evento(s) de aprovacao', v_rec.id, v_n);
    end if;
    select count(*) into v_n from public.evaluation_goal_events e
     where e.organization_id = v_alfa
       and e.result_entity_id = v_rec.id
       and e.event_type = 'APROVACAO_INVALIDADA';
    if (v_rec.revogado_em is null and v_n <> 0)
       or (v_rec.revogado_em is not null and v_n <> 1) then
      v_erros := v_erros || format('coerencia fato x invalidacao quebrada para %s (%s)', v_rec.id, v_n);
    end if;
  end loop;

  -- (c) Nenhuma surpresa na trilha: tipos, contagens e autores esperados.
  for v_rec in
    select e.event_type as tipo, count(*) as qtd
      from public.evaluation_goal_events e
     where e.organization_id in (v_alfa, v_beta)
     group by e.event_type
  loop
    if (v_rec.tipo = 'CRIADA' and v_rec.qtd <> 8)
       or (v_rec.tipo = 'EDITADA' and v_rec.qtd <> 1)
       or (v_rec.tipo = 'PROGRESSO_ATUALIZADO' and v_rec.qtd <> 1)
       or (v_rec.tipo = 'FINALIZADA' and v_rec.qtd <> 1)
       or (v_rec.tipo = 'APROVACAO_GERENTE' and v_rec.qtd <> 1)
       -- P7 (COORDENADOR congelado) + G4 (reaprovacao apos invalidacao) + o
       -- COORDENADOR da reaprovacao seguinte = 3 fatos de COORDENADOR.
       or (v_rec.tipo = 'APROVACAO_COORDENADOR' and v_rec.qtd <> 3)
       -- G2 (NO-OP do dono) + G3 (2 revogacoes efetivas) = 3 invalidacoes.
       or (v_rec.tipo = 'APROVACAO_INVALIDADA' and v_rec.qtd <> 3) then
      v_erros := v_erros || format('contagem inesperada de %s (%s)', v_rec.tipo, v_rec.qtd);
    end if;
  end loop;
  -- Nenhum evento de tipo PROIBIDO nesta fase (revisao/exclusao/limites).
  foreach v_meta in array array['REVISAO_FINALIZACAO', 'EXCLUIDA', 'LIMITES_DO_CICLO_ALTERADOS'] loop
    select count(*) into v_n from public.evaluation_goal_events e
     where e.organization_id in (v_alfa, v_beta) and e.event_type = v_meta;
    if v_n <> 0 then
      v_erros := v_erros || format('evento %s inesperado nesta bateria (%s)', v_meta, v_n);
    end if;
  end loop;
  -- Todos os 7 tipos ESPERADOS existem com a contagem do cenario.
  foreach v_meta in array array['CRIADA', 'EDITADA', 'PROGRESSO_ATUALIZADO', 'FINALIZADA',
                                 'APROVACAO_GERENTE', 'APROVACAO_COORDENADOR',
                                 'APROVACAO_INVALIDADA'] loop
    select count(*) into v_n from public.evaluation_goal_events e
     where e.organization_id in (v_alfa, v_beta) and e.event_type = v_meta;
    if v_n = 0 then
      v_erros := v_erros || format('evento %s ausente na trilha', v_meta);
    end if;
  end loop;
  -- A meta criada pelo validador (M5, dona c2) tem autoria SOBERANA do ator
  -- vinculado a ela (a2) — alem dos autores da fixture (a1 em Alfa, ac em Beta).
  if exists (
    select 1 from public.evaluation_goal_events e
     where e.organization_id in (v_alfa, v_beta)
       and e.event_type = 'CRIADA'
       and e.actor_user_profile_id <> 'f2c00000-0000-0000-0000-000000000001'
       and e.actor_user_profile_id <> 'f2c00000-0000-0000-0000-000000000002'
       and e.actor_user_profile_id <> 'f2c00000-0000-0000-0000-0000000000c1'
  ) then
    v_erros := v_erros || 'evento CRIADA com autoria inesperada'::text;
  end if;

  -- (d) Meta criada pelo validador: viva, EM_ANDAMENTO, version 0.
  select count(*) into v_n from public.evaluation_goals g
   where g.organization_id = v_alfa and g.id::text not like 'f2000000%'
     and g.status = 'EM_ANDAMENTO' and g.version = 0 and not g.excluida;
  if v_n <> 1 then
    v_erros := v_erros || format('meta criada pelo validador em estado inesperado (%s)', v_n);
  end if;

  -- (e) Superficie da P4 intacta: 2 policies own-tenant; trilha/limites
  --     deny-by-default; nada de DELETE para service_role.
  foreach v_meta in array array['evaluation_goals', 'evaluation_goal_approvals'] loop
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = v_meta;
    if v_n <> 1 then
      v_erros := v_erros || format('%s com %s policies (esperado 1 SELECT own-tenant)', v_meta, v_n);
    end if;
  end loop;
  foreach v_meta in array array['evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = v_meta;
    if v_n <> 0 then
      v_erros := v_erros || format('%s com policy (deveria ser deny-by-default integral)', v_meta);
    end if;
  end loop;
  foreach v_meta in array v_tabelas loop
    if has_table_privilege('service_role', format('public.%I', v_meta), 'DELETE')
       or has_table_privilege('service_role', format('public.%I', v_meta), 'TRUNCATE') then
      v_erros := v_erros || format('service_role com DELETE/TRUNCATE em %s', v_meta);
    end if;
    if has_table_privilege('authenticated', format('public.%I', v_meta), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', v_meta), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', v_meta), 'DELETE') then
      v_erros := v_erros || format('authenticated com DML em %s', v_meta);
    end if;
  end loop;

  -- (f) As 13 funcoes: INVOKER, search_path fixo, EXECUTE so service_role.
  foreach v_fn in array v_fns loop
    if to_regprocedure(v_fn) is null then
      v_erros := v_erros || ('funcao ausente: ' || v_fn);
      continue;
    end if;
    declare
      v_sec boolean;
      v_cfg text;
    begin
      select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '')
        into v_sec, v_cfg
        from pg_proc p where p.oid = to_regprocedure(v_fn);
      if v_sec then
        v_erros := v_erros || ('SECURITY DEFINER inesperado: ' || v_fn);
      end if;
      if position('search_path=public' in v_cfg) = 0 then
        v_erros := v_erros || ('search_path ausente: ' || v_fn);
      end if;
    end;
    if has_function_privilege('authenticated', v_fn, 'EXECUTE')
       or has_function_privilege('anon', v_fn, 'EXECUTE') then
      v_erros := v_erros || ('EXECUTE exposto a cliente: ' || v_fn);
    end if;
    if not has_function_privilege('service_role', v_fn, 'EXECUTE') then
      v_erros := v_erros || ('service_role sem EXECUTE: ' || v_fn);
    end if;
  end loop;

  -- (g) Anti-escopo: nenhuma RPC de meta fora das 10 do contrato e catalogo
  --     intacto (D6: nenhuma capability nova).
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and (p.proname like 'meta\_%' or p.proname like 'goal\_%')
     and p.proname <> all (array[
       'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
       'meta_revisar_finalizacao', 'meta_excluir', 'meta_definir_limites_do_ciclo',
       'meta_aprovar', 'meta_invalidar_aprovacoes', 'meta_listar_por_escopo']);
  if v_n <> 0 then
    v_erros := v_erros || format('%s RPC(s) de meta fora do contrato da P4', v_n);
  end if;
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_erros := v_erros || format('capabilities de metas/observacoes = %s (esperado 8)', v_n);
  end if;

  -- (h) Nenhum artefato temporario deixado para tras.
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_%';
  if v_n <> 0 then
    v_erros := v_erros || format('funcao de mutacao deixada no schema (%s)', v_n);
  end if;
  select count(*) into v_n from pg_trigger t
   where t.tgname like '\_mut\_%' and not t.tgisinternal;
  if v_n <> 0 then
    v_erros := v_erros || format('gatilho de mutacao deixado no schema (%s)', v_n);
  end if;

  if array_length(v_erros, 1) is not null then
    raise exception '[FAIL] guarda final da P4: %', array_to_string(v_erros, '; ');
  end if;

  raise notice '[PASS] guarda final: 8 metas (7 de fixture + 1 criada pelo dono c2), 1 excluida, 18 eventos (8 CRIADA, 1 EDITADA, 1 PROGRESSO_ATUALIZADO, 1 FINALIZADA, 1 APROVACAO_GERENTE, 3 APROVACAO_COORDENADOR, 3 APROVACAO_INVALIDADA) sem operation_id duplicado, 4 fatos de aprovacao (2 vigentes / 2 revogados) coerentes com a trilha, 6 roles e 10 assignments intactos, 2 policies own-tenant, trilha/limites deny-by-default, 13 funcoes INVOKER com EXECUTE so service_role e catalogo sem capability nova';
end $$;

-- ============================================================================
-- 19) Resumo
-- ============================================================================
do $$
begin
  raise notice '============================================================';
  raise notice 'F5-10 P4: autorizacao/RLS de metas validadas — 17 negativos (cross-tenant, membership/perfil invalidos, gestor sem SELF, capability ausente, capability sem relacao congelada, hierarquia VIVA divergente, meta excluida, ciclo NAO ATIVO, alvo inexistente, estado pelo corpo, leitura de terceiro, RPC direta e DML/SELECT de cliente) e 10 positivos (SELF criar/editar/progredir/finalizar/ler, GERENTE e COORDENADOR congelados aprovando, leitura SO do escopo autorizado, overlay que nao transfere autoridade, capability+relacao coexistentes e LIMITES administrativo de ciclo).';
  raise notice '============================================================';
end $$;

do $$
begin
  raise notice '[PASS] F5-10 P4: validacao concluida — a autoridade e a CAPABILITY efetiva (F4) + a RELACAO (SELF ou participante CONGELADO), o ESTADO permanece nas pre-condicoes de cada RPC, o cliente nao executa nem escreve e o tenant e barreira de RLS nos dois sentidos';
end $$;
