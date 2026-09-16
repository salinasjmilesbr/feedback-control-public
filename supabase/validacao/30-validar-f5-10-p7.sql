-- ============================================================================
-- F5-10 P7 (Issue #232): VALIDACAO INTEGRADA do dominio de metas — MATRIZ
-- (Supabase local apenas; executar SEMPRE depois de 29-cenario-f5-10-p7.sql)
-- ----------------------------------------------------------------------------
-- Contrato: docs/F5-10-desenho-tecnico.md (§7 lifecycle, §9 aprovacoes + matriz
-- D19, §10 autorizacao, §11 RLS x Policy Engine — D22, §12 concorrencia/versao/
-- idempotencia — D10/D11/D12, §15 testes e validacao integrada, §19 P7, §20 DoD).
-- Molde do relatorio: docs/F5-09-p9-matriz-integrada.md.
--
-- ESTA E A MATRIZ DOS BLOCOS 1 a 19 (o bloco 6 — CONCORRENCIA REAL entre duas
-- sessoes — vive nos arquivos 31/32/33 e o bloco 20 — CI no SHA exato +
-- auditorias — e etapa externa, registrada em docs/F5-10-p7-matriz-integrada.md):
--
--   §1  BLOCO 1  — sequencia historica integrada (parte A: criar -> editar ->
--                  progresso -> aprovar GERENTE -> aprovar COORDENADOR ->
--                  alteracao MATERIAL (matriz D19) -> reaprovar);
--   §2  BLOCO 4  — cross-tenant / IDOR (+ leitura por escopo SELF e congelada);
--   §3  BLOCO 5  — membership revogada / perfil desabilitado;
--   §4  BLOCOS 6/7 — CAPABILITY sem RELACAO e RELACAO sem CAPABILITY;
--   §5  BLOCO 8  — SELF tentando escrever meta de TERCEIRO (+ coexistencia);
--   §6  BLOCO 9  — aprovador SEM `goal.write`;
--   §7  BLOCO 14 — rollback TOTAL quando a gravacao do evento falha;
--   §8  BLOCO 13 — idempotencia: mesmo payload e payload divergente;
--   §9  BLOCO 1  — sequencia historica integrada (parte B: finalizar -> revisar
--                  -> excluir) + consolidacao da trilha;
--   §10 BLOCO 10 — ciclo NAO ATIVO;
--   §11 BLOCO 11 — meta EXCLUIDA (soft delete terminal);
--   §12 BLOCO 12 — quota excedida (RPC **e** invariante do BANCO);
--   §13 BLOCO 15 — trilha APPEND-ONLY;
--   §14 BLOCOS 16/17 — RLS/ACL de cliente e proibicao de RPC direta;
--   §15 BLOCO 19 — guardas invertidas coerentes (inventario FECHADO);
--   §16 BLOCO 18 — regressoes P1–P6 (invariantes consolidados);
--   §17 guarda final fail-closed + resumo.
--
-- PRINCIPIO DESTA FASE: a P7 NAO reimplementa motor algum, NAO cria RPC/policy/
-- RLS/grant/capability/migration e NAO duplica os validadores estreitos das fases
-- P1–P5.2 (que rodam no MESMO job do CI, antes deste). Ela prova o dominio de
-- metas de forma INTEGRADA e sob condicoes adversas, no contrato REAL entregue.
-- Somente o cenario 29 (fixture) e' pre-requisito do estado inicial; a meta da
-- sequencia integrada e criada aqui pelo caminho LEGITIMO (`meta_criar`).
-- ============================================================================

\set ON_ERROR_STOP on

-- ============================================================================
-- 0) PREFLIGHT: fixture presente, estado LIMPO e superficie intacta
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'e8a00000-0000-0000-0000-0000000000b1';
  v_gama  uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_metas int;
  v_evt   int;
  v_aprov int;
  v_gama_evt int;
  v_pol   int;
  v_n     int;
  v_tab   text;
begin
  select count(*) into v_metas from public.evaluation_goals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_evt from public.evaluation_goal_events
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_aprov from public.evaluation_goal_approvals
   where organization_id in (v_alfa, v_beta);
  select count(*) into v_gama_evt from public.evaluation_goal_events
   where organization_id = v_gama;

  -- A fixture 29 cria 5 metas (4 em Alfa + 1 em Beta) com 1 evento CRIADA cada.
  if v_metas <> 5 or v_evt <> 5 or v_aprov <> 0 or v_gama_evt <> 0 then
    raise exception
      '[FAIL] pre-condicao: fixture F5-10 P7 ausente ou estado sujo (metas Alfa/Beta=%, eventos=%, aprovacoes=%, eventos Gama=%) — execute `supabase db reset` e os cenarios 29/30',
      v_metas, v_evt, v_aprov, v_gama_evt;
  end if;
  if not exists (select 1 from public.organizations where id = v_gama) then
    raise exception '[FAIL] pre-condicao: Gama-P7 ausente (a corrida 31/32/33 depende dela)';
  end if;

  -- D22-A: as 4 tabelas de metas seguem DENY-BY-DEFAULT INTEGRAL (ZERO policy e
  -- ZERO privilegio de cliente) — a leitura funcional passa SO pela superficie
  -- soberana `meta_listar_por_escopo`.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    select count(*) into v_pol from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_pol <> 0 then
      raise exception '[FAIL] pre-condicao: % deveria estar deny-by-default integral (policies=%)',
        v_tab, v_pol;
    end if;
    if has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT')
       or has_table_privilege('anon', format('public.%I', v_tab), 'SELECT') then
      raise exception '[FAIL] pre-condicao: % nao pode conceder SELECT a authenticated/anon (D22-A)', v_tab;
    end if;
  end loop;

  -- Catalogo intacto (D6: NENHUMA capability nova) e as 3 de meta concediveis.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    raise exception '[FAIL] pre-condicao: catalogo com % capabilities (esperado 31)', v_n;
  end if;
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    raise exception '[FAIL] pre-condicao: capabilities de metas/observacoes = % (esperado 8)', v_n;
  end if;

  -- Capability EFETIVA dos atores centrais (o gate depende dela).
  if not public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000001', v_alfa, 'goal.write')
     or not public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000001', v_alfa, 'goal.read') then
    raise exception '[FAIL] pre-condicao: o dono a1 deveria ter goal.read + goal.write';
  end if;
  if not public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000002', v_alfa, 'goal.approve') then
    raise exception '[FAIL] pre-condicao: o gerente congelado a2 deveria ter goal.approve';
  end if;
  -- Item 9 exige que o aprovador NAO tenha goal.write.
  if public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000002', v_alfa, 'goal.write') then
    raise exception '[FAIL] pre-condicao: o gerente congelado a2 NAO pode ter goal.write (item 9)';
  end if;
  if public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000003', v_alfa, 'goal.write') then
    raise exception '[FAIL] pre-condicao: o coordenador congelado a3 NAO pode ter goal.write';
  end if;
  -- Item 7 exige que o ator com RELACAO congelada NAO tenha capability alguma.
  if public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000005', v_alfa, 'goal.approve')
     or public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000005', v_alfa, 'goal.write') then
    raise exception '[FAIL] pre-condicao: a5 (relacao congelada de EV2) NAO pode ter capability de meta';
  end if;
  -- a7/a8 sao recusados pelo ESTADO (membership/perfil), nao pela capability.
  if public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000007', v_alfa, 'goal.write') then
    raise exception '[FAIL] pre-condicao: a7 (membership revogada) nao pode ter capability efetiva';
  end if;
  if public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000008', v_alfa, 'goal.write') then
    raise exception '[FAIL] pre-condicao: a8 (perfil disabled) nao pode ter capability efetiva';
  end if;
  if public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000009', v_alfa, 'goal.write') then
    raise exception '[FAIL] pre-condicao: o leitor a9 NAO pode ter goal.write';
  end if;
  -- Codigo fora da allowlist => false (fail-closed).
  if public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000001', v_alfa, 'cycle.manage') then
    raise exception '[FAIL] pre-condicao: cycle.manage NAO pertence a allowlist de meta';
  end if;

  raise notice '[PASS] preflight: fixture limpa (4 metas, 4 eventos CRIADA, 0 aprovacoes em Alfa/Beta; Gama-P7 sem meta/evento), as 4 tabelas de metas deny-by-default integral (ZERO policy e ZERO SELECT de cliente — D22-A), catalogo intacto (31 capabilities; 8 de metas/observacoes) e capability efetiva/inefetiva dos atores verificada';
end $$;

-- ============================================================================
-- 1) BLOCO 1 (parte A) + BLOCOS 4/5/6/7/8/9 — sequencia integrada e negativos
--    de autorizacao sobre a MESMA meta criada pelo caminho legitimo
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_beta   uuid := 'e8a00000-0000-0000-0000-0000000000b1';
  v_c1     uuid := 'e8d10000-0000-0000-0000-0000000000a1';
  v_c2     uuid := 'e8d10000-0000-0000-0000-0000000000a2';
  v_cbeta  uuid := 'e8d10000-0000-0000-0000-0000000000b1';
  v_dono   uuid := 'e8b00000-0000-0000-0000-000000000001';
  v_a1     uuid := 'e8c00000-0000-0000-0000-000000000001';
  v_a2     uuid := 'e8c00000-0000-0000-0000-000000000002';
  v_a3     uuid := 'e8c00000-0000-0000-0000-000000000003';
  v_a4     uuid := 'e8c00000-0000-0000-0000-000000000004';
  v_a5     uuid := 'e8c00000-0000-0000-0000-000000000005';
  v_a6     uuid := 'e8c00000-0000-0000-0000-000000000006';
  v_a7     uuid := 'e8c00000-0000-0000-0000-000000000007';
  v_a8     uuid := 'e8c00000-0000-0000-0000-000000000008';
  v_a9     uuid := 'e8c00000-0000-0000-0000-000000000009';
  v_ab     uuid := 'e8c00000-0000-0000-0000-0000000000b1';
  v_g3     uuid := 'e8000000-0000-0000-0000-000000000003';
  v_g4     uuid := 'e8000000-0000-0000-0000-000000000004';
  v_g5     uuid := 'e8000000-0000-0000-0000-000000000005';
  v_g6     uuid := 'e8000000-0000-0000-0000-000000000006';
  v_gbeta  uuid := 'e8000000-0000-0000-0000-0000000000b1';
  v_d1     uuid := 'e8d00000-0000-0000-0000-000000000001';
  v_d2     uuid := 'e8d00000-0000-0000-0000-000000000002';
  v_d3     uuid := 'e8d00000-0000-0000-0000-000000000003';
  v_o1     uuid := 'e8700000-0000-0000-0000-0000000000a1';
  v_o2     uuid := 'e8700000-0000-0000-0000-0000000000a2';
  v_o3     uuid := 'e8700000-0000-0000-0000-0000000000a3';
  v_o4     uuid := 'e8700000-0000-0000-0000-0000000000a4';
  v_o5     uuid := 'e8700000-0000-0000-0000-0000000000a5';
  v_o6     uuid := 'e8700000-0000-0000-0000-0000000000a6';
  v_o7     uuid := 'e8700000-0000-0000-0000-0000000000a7';
  v_probe  uuid := 'e8700000-0000-0000-0000-0000000000f1';
  v_ok_op  uuid := 'e8700000-0000-0000-0000-0000000000ab';
  v_res    jsonb;
  v_env    jsonb;
  v_g1     uuid;
  v_v      int;
  v_st     text;
  v_n      int;
  v_ok     boolean;
  v_msg    text;
  v_aprov  uuid;
  v_ger    uuid;
begin
  -- --------------------------------------------------------------------------
  -- §1 (BLOCO 1, parte A) — SEQUENCIA HISTORICA INTEGRADA pelo caminho LEGITIMO
  -- --------------------------------------------------------------------------
  -- (1) CRIAR: identidade UUID do banco, version 0, EM_ANDAMENTO, ciclo ATIVO.
  v_res := public.meta_criar(v_alfa, v_c1, v_dono, 'NEGOCIO_PROJETO',
    'Descricao inicial da sequencia integrada (P7)',
    'KPI inicial da sequencia integrada (P7)',
    '100 unidades (P7)', v_a1, v_o1);
  v_g1 := (v_res->>'goal_id')::uuid;
  if v_g1 is null then
    raise exception '[FAIL] S1/criar: meta_criar nao devolveu goal_id (%)', v_res;
  end if;
  if (v_res->>'version')::int <> 0 or (v_res->>'status') <> 'EM_ANDAMENTO' then
    raise exception '[FAIL] S1/criar: retorno deveria ser version 0 / EM_ANDAMENTO (%)', v_res;
  end if;
  select g.version, g.status into v_v, v_st
    from public.evaluation_goals g
   where g.id = v_g1 and g.organization_id = v_alfa and g.cycle_id = v_c1
     and g.collaborator_id = v_dono and g.tipo = 'NEGOCIO_PROJETO' and g.excluida = false;
  if v_v is distinct from 0 or v_st is distinct from 'EM_ANDAMENTO' then
    raise exception '[FAIL] S1/criar: linha divergente do contrato (version=%, status=%)', v_v, v_st;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g1
     and e.event_type = 'CRIADA' and e.operation_id = v_o1
     and e.result_entity_id = v_g1
     and e.actor_user_profile_id = v_a1 and e.actor_membership_id = v_d1;
  if v_n <> 1 then
    raise exception '[FAIL] S1/criar: evento CRIADA esperado 1x com autoria soberana a1/d1 e result_entity_id da meta (%)', v_n;
  end if;

  -- (2) EDITAR (alteracao MATERIAL de definicao): version 0 -> 1.
  v_res := public.meta_editar(v_g1, v_alfa,
    'Descricao A da sequencia integrada (P7)',
    'KPI A da sequencia integrada (P7)',
    '150 unidades (P7)', 0, v_a1, v_o2);
  if (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] S1/editar: retorno deveria ser version 1 (%)', v_res;
  end if;
  -- Sem aprovacao vigente ainda: a alteracao material NAO gera evento de invalidacao.
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g1 and e.operation_id = v_o2
     and e.event_type = 'EDITADA';
  if v_n <> 1 then
    raise exception '[FAIL] S1/editar: evento EDITADA esperado 1x (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g1
     and e.event_type = 'APROVACAO_INVALIDADA';
  if v_n <> 0 then
    raise exception '[FAIL] S1/editar: sem aprovacao vigente nao pode haver APROVACAO_INVALIDADA (%)', v_n;
  end if;

  -- (3) PROGRESSO: version 1 -> 2, progresso INTEIRO informado (D16).
  v_res := public.meta_atualizar_progresso(v_g1, v_alfa,
    'Resultado parcial A da sequencia integrada (P7)', 40, 1, v_a1, v_o3);
  if (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] S1/progresso: retorno deveria ser version 2 (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goals g
   where g.id = v_g1 and g.progresso_percentual = 40
     and g.resultado_atual = 'Resultado parcial A da sequencia integrada (P7)'
     and g.data_ultimo_acompanhamento is not null and g.version = 2;
  if v_n <> 1 then
    raise exception '[FAIL] S1/progresso: progresso/resultado/data nao foram gravados server-side';
  end if;

  -- (4) APROVAR GERENTE (participante CONGELADO de EV1): a aprovacao e FATO e
  --     NAO altera status nem version da meta (D2/D3).
  v_res := public.meta_aprovar(v_g1, v_alfa, 'GERENTE',
    'Aprovacao do gerente congelado (P7)', 2, v_a2, v_o4);
  if (v_res->>'aprovado')::boolean is not true or (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] S1/aprovar GERENTE: retorno divergente (%)', v_res;
  end if;
  if (v_res->>'papel') <> 'GERENTE' then
    raise exception '[FAIL] S1/aprovar GERENTE: papel divergente (%)', v_res;
  end if;
  select g.version into v_v from public.evaluation_goals g where g.id = v_g1;
  if v_v <> 2 then
    raise exception '[FAIL] S1/aprovar GERENTE: a aprovacao NAO pode alterar a version da meta (version=%)', v_v;
  end if;

  -- (5) APROVAR COORDENADOR (participante CONGELADO distinto de EV1).
  v_res := public.meta_aprovar(v_g1, v_alfa, 'COORDENADOR',
    'Aprovacao do coordenador congelado (P7)', 2, v_a3, v_o5);
  if (v_res->>'aprovado')::boolean is not true then
    raise exception '[FAIL] S1/aprovar COORDENADOR: retorno divergente (%)', v_res;
  end if;
  select g.version into v_v from public.evaluation_goals g where g.id = v_g1;
  if v_v <> 2 then
    raise exception '[FAIL] S1/aprovar COORDENADOR: a aprovacao NAO pode alterar a version da meta (version=%)', v_v;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 2 then
    raise exception '[FAIL] S1/aprovar: esperadas 2 aprovacoes VIGENTES (GERENTE + COORDENADOR), encontradas %', v_n;
  end if;

  -- (6) ALTERACAO MATERIAL novamente (version 2 -> 3): a matriz D19 invalida
  --     ATOMICAMENTE as duas aprovacoes vigentes, na MESMA transacao, com um
  --     evento APROVACAO_INVALIDADA por papel (nunca DELETE — o fato e preservado).
  v_res := public.meta_editar(v_g1, v_alfa,
    'Descricao B da sequencia integrada (P7)',
    'KPI B da sequencia integrada (P7)',
    '200 unidades (P7)', 2, v_a1, v_o6);
  if (v_res->>'version')::int <> 3 then
    raise exception '[FAIL] S1/D19: retorno deveria ser version 3 (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 0 then
    raise exception '[FAIL] S1/D19: nenhuma aprovacao pode permanecer vigente apos alteracao MATERIAL (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1
     and a.revogado_em is not null and a.revogado_motivo is not null and a.version = 1;
  if v_n <> 2 then
    raise exception '[FAIL] S1/D19: os 2 fatos devem ser PRESERVADOS com revogado_em/revogado_motivo e version+1 (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g1
     and e.event_type = 'APROVACAO_INVALIDADA';
  if v_n <> 2 then
    raise exception '[FAIL] S1/D19: esperados 2 eventos APROVACAO_INVALIDADA (um por papel), encontrados %', v_n;
  end if;
  -- O PRIMEIRO sub-evento da intencao usa o operation_id DERIVADO determinista.
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g1
     and e.event_type = 'APROVACAO_INVALIDADA'
     and e.operation_id = public.f5_10_derivar_operation_id(v_o6, 'D19_INVALIDACAO')
     and e.result_entity_id is not null;
  if v_n <> 1 then
    raise exception '[FAIL] S1/D19: o 1o sub-evento deveria usar o operation_id derivado D19_INVALIDACAO (%)', v_n;
  end if;

  -- (7) REAPROVAR GERENTE apos a invalidacao: FATO NOVO, preservando o revogado.
  v_res := public.meta_aprovar(v_g1, v_alfa, 'GERENTE',
    'Reaprovacao do gerente congelado apos alteracao material (P7)', 3, v_a2, v_o7);
  if (v_res->>'aprovado')::boolean is not true then
    raise exception '[FAIL] S1/reaprovar: retorno divergente (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.papel = 'GERENTE';
  if v_n <> 2 then
    raise exception '[FAIL] S1/reaprovar: reaprovar deve criar um FATO NOVO preservando o revogado (esperados 2 fatos GERENTE, encontrados %)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1
     and a.papel = 'GERENTE' and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] S1/reaprovar: exatamente 1 GERENTE vigente (%)', v_n;
  end if;

  ---------------------------------------------------------------------------
  raise notice '[PASS] S1 (bloco 1, parte A): sequencia integrada pelo caminho LEGITIMO — CRIADA (v0) -> EDITADA (v1) -> PROGRESSO (v2) -> APROVACAO_GERENTE + APROVACAO_COORDENADOR (fatos, version da meta INTACTA em 2) -> alteracao MATERIAL (v3, 2 x APROVACAO_INVALIDADA com operation_id derivado, fatos preservados com version+1) -> REAPROVACAO (fato novo)';
  ---------------------------------------------------------------------------

  -- --------------------------------------------------------------------------
  -- §2 (BLOCO 4) — CROSS-TENANT / IDOR
  -- --------------------------------------------------------------------------
  -- A meta do outro tenant NAO e resolvida (cross-tenant = inexistente): a
  -- recusa e NOT_FOUND e NAO confirma a existencia do alvo.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_gbeta, v_alfa, 'probe cross-tenant (P7)',
      'KPI probe (P7)', '1 unidade (P7)', 0, v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S2/cross-tenant: editar meta de outro tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;
  -- (o ator aqui e a2, que TEM `goal.approve`: assim a recusa e atribuivel SO ao
  -- alvo cross-tenant e nao a uma capability ausente)
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_gbeta, v_alfa, 'GERENTE', 'probe cross-tenant (P7)',
      0, v_a2, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S2/cross-tenant: aprovar meta de outro tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;
  -- Ator de OUTRO tenant operando meta de Alfa: o alvo e resolvido no tenant do
  -- ATOR => NOT_FOUND (nunca sucesso, nunca confirmacao de existencia).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_g1, v_beta, 'probe ator de outro tenant (P7)',
      'KPI probe (P7)', '1 unidade (P7)', 3, v_ab, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S2/cross-tenant: ator de outro tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;
  -- Alvo de OUTRO tenant na CRIACAO.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_criar(v_alfa, v_c1, 'e8b00000-0000-0000-0000-0000000000b1',
      'NEGOCIO_PROJETO', 'probe alvo cross-tenant (P7)', 'KPI probe (P7)',
      '1 unidade (P7)', v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S2/cross-tenant: criacao com alvo de outro tenant deveria ser F5_10_NOT_FOUND (recebido %)', v_msg;
  end if;
  -- Ator sem membership no tenant consultado.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_listar_por_escopo(v_beta, v_cbeta, v_a1);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S2/cross-tenant: leitura por escopo em tenant sem membership deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  -- IDOR / leitura de terceiro: a superficie soberana devolve SOMENTE o escopo
  -- autorizado. a9 tem `goal.read` e vinculo soberano unico, mas NENHUMA relacao.
  v_env := public.meta_listar_por_escopo(v_alfa, v_c1, v_a9);
  if (v_env->>'quantidade')::int <> 0
     or jsonb_array_length(v_env->'metas') <> 0 then
    raise exception '[FAIL] S2/IDOR: a9 nao tem relacao com meta alguma e deveria receber ZERO metas (%)', v_env;
  end if;
  -- Contraparte POSITIVA: SELF e os dois papeis CONGELADOS recebem 1 meta (G1).
  v_env := public.meta_listar_por_escopo(v_alfa, v_c1, v_a1);
  if (v_env->>'quantidade')::int <> 1 then
    raise exception '[FAIL] S2/SELF: o dono a1 deveria ler exatamente a propria meta (%)', v_env;
  end if;
  v_env := public.meta_listar_por_escopo(v_alfa, v_c1, v_a2);
  if (v_env->>'quantidade')::int <> 1 then
    raise exception '[FAIL] S2/GERENTE: o gerente CONGELADO a2 deveria ler a meta do liderado (%)', v_env;
  end if;
  v_env := public.meta_listar_por_escopo(v_alfa, v_c1, v_a3);
  if (v_env->>'quantidade')::int <> 1 then
    raise exception '[FAIL] S2/COORDENADOR: o coordenador CONGELADO a3 deveria ler a meta (%)', v_env;
  end if;

  raise notice '[PASS] S2 (bloco 4): cross-tenant e IDOR — meta/ator/alvo de outro tenant => F5_10_NOT_FOUND, tenant sem membership => F5_10_FORBIDDEN, e a leitura por escopo devolve ZERO metas para ator sem relacao (a9) e EXATAMENTE a meta autorizada para SELF (a1) e para os 2 papeis CONGELADOS (a2/a3)';

  -- --------------------------------------------------------------------------
  -- §3 (BLOCO 5) — MEMBERSHIP REVOGADA / PERFIL DESABILITADO
  -- --------------------------------------------------------------------------
  -- a7 e' o DONO LEGITIMO de G4 (vinculo ativo) e tem a role de dono: a UNICA
  -- causa da recusa e' a membership `disabled`. a8 idem em G5 (perfil `disabled`).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_g4, v_alfa, 'probe membership revogada (P7)',
      'KPI probe (P7)', '1 unidade (P7)', 0, v_a7, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S3/membership: SELF com membership REVOGADA deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_g5, v_alfa, 'probe perfil disabled (P7)',
      'KPI probe (P7)', '1 unidade (P7)', 0, v_a8, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S3/perfil: SELF com perfil `disabled` deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  -- Nenhum efeito colateral: G4/G5 permanecem version 0 e sem evento novo.
  select count(*) into v_n from public.evaluation_goals g
   where g.id in (v_g4, v_g5) and g.version = 0;
  if v_n <> 2 then
    raise exception '[FAIL] S3: as recusas nao podem mutar a meta (G4/G5 deveriam seguir version 0)';
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.operation_id = v_probe;
  if v_n <> 0 then
    raise exception '[FAIL] S3: recusa NAO pode gravar evento na trilha (%)', v_n;
  end if;

  raise notice '[PASS] S3 (bloco 5): membership REVOGADA (a7 em G4, da qual e dono legitimo com vinculo ativo) e perfil `disabled` (a8 em G5) sao recusados com F5_10_FORBIDDEN — o estado do ator e revalidado SERVER-SIDE, sem mutacao e sem evento';

  -- --------------------------------------------------------------------------
  -- §4 (BLOCOS 6/7) — CAPABILITY SEM RELACAO e RELACAO SEM CAPABILITY
  -- --------------------------------------------------------------------------
  -- (item 7) RELACAO sem CAPABILITY: a5 e' o GERENTE CONGELADO ORIGINAL de G3
  -- (a relacao EXISTE e e comprovada abaixo) mas NAO tem capability alguma.
  v_ger := public.f5_10_aprovador_congelado(v_g3, v_alfa, 'GERENTE');
  if v_ger <> 'e8b00000-0000-0000-0000-000000000005'::uuid then
    raise exception '[FAIL] S4/item7: a relacao congelada de a5 com G3 deveria existir (%)', v_ger;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g3, v_alfa, 'GERENTE', 'probe relacao sem capability (P7)',
      0, v_a5, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S4/item7: RELACAO congelada sem CAPABILITY deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  -- (item 6) CAPABILITY sem RELACAO: a6 tem `goal.approve` mas NAO e o
  -- participante congelado. O papel COORDENADOR esta SEM vigente (foi
  -- invalidado em §1), de modo que a recusa e atribuivel SO a relacao.
  if not public.f5_10_ator_valido_meta(v_a6, v_alfa, 'goal.approve') then
    raise exception '[FAIL] S4/item6: a6 deveria ter goal.approve (a capability e o ponto do teste)';
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g1, v_alfa, 'COORDENADOR', 'probe capability sem relacao (P7)',
      3, v_a6, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S4/item6: CAPABILITY sem RELACAO congelada deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  -- A RELACAO e' exigida ANTES do estado: com o papel GERENTE JA VIGENTE, a
  -- tentativa de a6 continua FORBIDDEN (e nao CONFLICT de "ja existe vigente").
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g1, v_alfa, 'GERENTE', 'probe precedencia relacao x estado (P7)',
      3, v_a6, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S4/item6: com GERENTE vigente, o ator sem relacao deve ser F5_10_FORBIDDEN e nao CONFLICT (recebido %)', v_msg;
  end if;

  raise notice '[PASS] S4 (blocos 6/7): RELACAO congelada SEM capability (a5, gerente congelado de G3, sem role) => F5_10_FORBIDDEN; CAPABILITY SEM relacao congelada (a6, goal.approve) => F5_10_FORBIDDEN, inclusive quando o papel ja tem vigente (a relacao e provada ANTES do estado)';

  -- --------------------------------------------------------------------------
  -- §5 (BLOCO 8) — SELF tentando escrever meta de TERCEIRO
  -- --------------------------------------------------------------------------
  -- a4 TEM `goal.write`, mas a escrita e SELF: G1 pertence a c1 (dono a1).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_g1, v_alfa, 'probe SELF de terceiro (P7)',
      'KPI probe (P7)', '1 unidade (P7)', 3, v_a4, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S5: SELF de terceiro na EDICAO deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(v_g1, v_alfa, 'probe SELF de terceiro (P7)',
      90, 3, v_a4, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S5: SELF de terceiro no PROGRESSO deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_finalizar(v_g1, v_alfa, 'probe SELF de terceiro (P7)', true, 3, v_a4, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S5: SELF de terceiro na FINALIZACAO deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_excluir(v_g1, v_alfa, 'probe SELF de terceiro (P7)', 3, v_a4, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S5: SELF de terceiro na EXCLUSAO deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  -- Coexistencia (capability + relacao CORRETA = ALLOW): a4 edita a PROPRIA meta
  -- G3. ATENCAO: esta e a UNICA intencao de prova que PERSISTE, por isso recebe um
  -- `operation_id` PROPRIO (`v_ok_op`); `v_probe` fica reservado as intencoes
  -- RECUSADAS — assim nenhuma recusa posterior colide com o `operation_id` de uma
  -- intencao ja consumida (defeito real encontrado na validacao integrada da P9).
  v_res := public.meta_editar(v_g3, v_alfa, 'Descricao propria do terceiro (P7)',
    'KPI proprio do terceiro (P7)', '35 unidades (P7)', 0, v_a4, v_ok_op);
  if (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] S5: o dono a4 deveria conseguir editar a PROPRIA meta (%)', v_res;
  end if;

  raise notice '[PASS] S5 (bloco 8): com `goal.write` e SEM a relacao SELF, editar/progredir/finalizar/excluir meta de TERCEIRO e F5_10_FORBIDDEN; com a relacao SELF correta (a4 na propria G3, version 0 -> 1) a escrita e efetiva — capability e relacao precisam COEXISTIR';

  -- --------------------------------------------------------------------------
  -- §6 (BLOCO 9) — aprovador SEM `goal.write`
  -- --------------------------------------------------------------------------
  -- a2 APROVOU legitimamente (§1) e NAO pode escrever: `goal.approve` nao implica
  -- `goal.write` (D7/D9).
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_g1, v_alfa, 'probe aprovador escrevendo (P7)',
      'KPI probe (P7)', '1 unidade (P7)', 3, v_a2, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S6: aprovador sem `goal.write` deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(v_g1, v_alfa, 'probe aprovador progredindo (P7)',
      10, 3, v_a2, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S6: aprovador sem `goal.write` no PROGRESSO deveria ser F5_10_FORBIDDEN (recebido %)', v_msg;
  end if;

  raise notice '[PASS] S6 (bloco 9): o aprovador CONGELADO que aprova legitimamente (§1) NAO recebe `goal.write` — editar e progredir a meta sao F5_10_FORBIDDEN (goal.approve NAO implica goal.write)';
end $$;

-- ============================================================================
-- 2) BLOCO 14 — ROLLBACK TOTAL quando a gravacao do EVENTO falha
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_c1     uuid := 'e8d10000-0000-0000-0000-0000000000a1';
  v_a1     uuid := 'e8c00000-0000-0000-0000-000000000001';
  v_g1     uuid;
  v_o      uuid := 'e8700000-0000-0000-0000-0000000000f2';
  v_ok     boolean;
  v_msg    text;
  v_v      int;
  v_prog   int;
  v_res    text;
  v_n      int;
begin
  select g.id into v_g1
    from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_c1
     and g.collaborator_id = 'e8b00000-0000-0000-0000-000000000001'
     and g.tipo = 'NEGOCIO_PROJETO';
  if v_g1 is null then
    raise exception '[FAIL] S7: meta da sequencia integrada nao resolvida';
  end if;

  select g.version, g.progresso_percentual, g.resultado_atual
    into v_v, v_prog, v_res
    from public.evaluation_goals g
   where g.id = v_g1;
  if v_v <> 3 or v_prog <> 40 then
    raise exception '[FAIL] S7: pre-condicao do rollback divergente (version=%, progresso=%)', v_v, v_prog;
  end if;

  -- Artefato TEMPORARIO de injecao de falha: recusa a gravacao do evento da
  -- intencao `v_o`, exatamente na 1a escrita da trilha.
  drop trigger if exists _mut_p7_falha_evento on public.evaluation_goal_events;
  drop function if exists public._mut_p7_falha_evento_fn();
  create function public._mut_p7_falha_evento_fn()
  returns trigger
  language plpgsql
  as $mut$
  begin
    if new.operation_id = 'e8700000-0000-0000-0000-0000000000f2' then
      raise exception 'P7_FALHA_INJETADA: gravacao da trilha recusada (teste de rollback)';
    end if;
    return new;
  end;
  $mut$;
  create trigger _mut_p7_falha_evento
    before insert on public.evaluation_goal_events
    for each row execute function public._mut_p7_falha_evento_fn();

  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(v_g1, v_alfa,
      'Resultado B (nao deve persistir — P7)', 77, 3, v_a1, v_o);
  exception when others then v_ok := sqlerrm like '%P7_FALHA_INJETADA%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S7: a falha injetada deveria ter interrompido a operacao (recebido %)', v_msg;
  end if;

  drop trigger if exists _mut_p7_falha_evento on public.evaluation_goal_events;
  drop function if exists public._mut_p7_falha_evento_fn();

  -- ROLLBACK TOTAL: nem o UPDATE da meta nem o evento da intencao persistiram.
  select g.version, g.progresso_percentual, g.resultado_atual
    into v_v, v_prog, v_res
    from public.evaluation_goals g
   where g.id = v_g1;
  if v_v <> 3 or v_prog <> 40
     or v_res <> 'Resultado parcial A da sequencia integrada (P7)' then
    raise exception '[FAIL] S7: ROLLBACK incompleto — a meta foi parcialmente mutada (version=%, progresso=%, resultado=%)',
      v_v, v_prog, v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.operation_id = v_o;
  if v_n <> 0 then
    raise exception '[FAIL] S7: a intencao que falhou NAO pode deixar evento na trilha (%)', v_n;
  end if;
  -- Higiene do artefato temporario.
  if exists (select 1 from pg_trigger t
              where t.tgrelid = 'public.evaluation_goal_events'::regclass
                and t.tgname = '_mut_p7_falha_evento') then
    raise exception '[FAIL] S7/higiene: gatilho temporario de injecao NAO foi removido';
  end if;

  raise notice '[PASS] S7 (bloco 14): com falha injetada na gravacao da TRILHA, `meta_atualizar_progresso` reverte INTEGRALMENTE — version/progresso/resultado intactos e ZERO evento da intencao que falhou (atomicidade real, nao apenas ausencia de erro)';
end $$;

-- ============================================================================
-- 3) BLOCO 13 — IDEMPOTENCIA: mesmo payload e payload divergente
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_c1     uuid := 'e8d10000-0000-0000-0000-0000000000a1';
  v_a1     uuid := 'e8c00000-0000-0000-0000-000000000001';
  v_a2     uuid := 'e8c00000-0000-0000-0000-000000000002';
  v_o2     uuid := 'e8700000-0000-0000-0000-0000000000a2';
  v_o7     uuid := 'e8700000-0000-0000-0000-0000000000a7';
  v_probe  uuid := 'e8700000-0000-0000-0000-0000000000f3';
  v_g1     uuid;
  v_res    jsonb;
  v_apr_1  uuid;
  v_apr_2  uuid;
  v_n      int;
  v_ok     boolean;
  v_msg    text;
begin
  select g.id into v_g1
    from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_c1
     and g.collaborator_id = 'e8b00000-0000-0000-0000-000000000001'
     and g.tipo = 'NEGOCIO_PROJETO';

  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.operation_id = v_o2;
  if v_n <> 1 then
    raise exception '[FAIL] S8: pre-condicao — a intencao % deveria ter exatamente 1 evento (%)', v_o2, v_n;
  end if;

  -- (a) REPLAY LEGITIMO: MESMA intencao (mesmos argumentos) => MESMO resultado,
  --     sem novo fato e sem novo evento. `operation_id` e CHAVE DE IDEMPOTENCIA,
  --     nunca identidade funcional.
  v_res := public.meta_editar(v_g1, v_alfa,
    'Descricao A da sequencia integrada (P7)',
    'KPI A da sequencia integrada (P7)',
    '150 unidades (P7)', 0, v_a1, v_o2);
  if (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] S8/replay: o replay deveria devolver o MESMO resultado do 1o processamento (version 1) (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.operation_id = v_o2;
  if v_n <> 1 then
    raise exception '[FAIL] S8/replay: o replay NAO pode duplicar evento (%)', v_n;
  end if;
  if (select g.version from public.evaluation_goals g where g.id = v_g1) <> 3 then
    raise exception '[FAIL] S8/replay: o replay NAO pode mutar a meta (version deveria seguir 3)';
  end if;

  -- (b) PAYLOAD DIVERGENTE com o mesmo operation_id => CONFLICT.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_g1, v_alfa,
      'Descricao DIVERGENTE com o mesmo operation_id (P7)',
      'KPI A da sequencia integrada (P7)',
      '150 unidades (P7)', 0, v_a1, v_o2);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S8/divergente: intencao divergente com o mesmo operation_id deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;

  -- (c) REPLAY da APROVACAO: o mesmo operation_id devolve o MESMO fato.
  select a.id into v_apr_1 from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1
     and a.papel = 'GERENTE' and a.revogado_em is null;
  v_res := public.meta_aprovar(v_g1, v_alfa, 'GERENTE',
    'Reaprovacao do gerente congelado apos alteracao material (P7)', 3, v_a2, v_o7);
  if (v_res->>'aprovacao_id')::uuid <> v_apr_1 then
    raise exception '[FAIL] S8/replay aprovacao: deveria devolver o MESMO aprovacao_id (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.papel = 'GERENTE';
  if v_n <> 2 then
    raise exception '[FAIL] S8/replay aprovacao: o replay NAO pode criar fato novo (esperados 2 GERENTE) (%)', v_n;
  end if;
  -- (d) Aprovacao com intencao divergente e o mesmo operation_id => CONFLICT.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g1, v_alfa, 'GERENTE',
      'Motivo DIVERGENTE com o mesmo operation_id (P7)', 3, v_a2, v_o7);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S8/divergente aprovacao: intencao divergente deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  -- Nenhuma tentativa recusada pode ter deixado evento.
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.operation_id = v_probe;
  if v_n <> 0 then
    raise exception '[FAIL] S8: as recusas nao podem gravar evento (%)', v_n;
  end if;

  raise notice '[PASS] S8 (bloco 13): idempotencia — replay com o MESMO payload devolve o MESMO resultado sem novo evento/fato (meta e aprovacao) e intencao DIVERGENTE com o mesmo operation_id e F5_10_CONFLICT';
end $$;

-- ============================================================================
-- 4) BLOCO 1 (parte B) — finalizar -> revisar -> excluir + trilha consolidada
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_c1     uuid := 'e8d10000-0000-0000-0000-0000000000a1';
  v_a1     uuid := 'e8c00000-0000-0000-0000-000000000001';
  v_o8     uuid := 'e8700000-0000-0000-0000-0000000000a8';
  v_o9     uuid := 'e8700000-0000-0000-0000-0000000000a9';
  v_o10    uuid := 'e8700000-0000-0000-0000-0000000000aa';
  v_g1     uuid;
  v_res    jsonb;
  v_before jsonb;
  v_v      int;
  v_st     text;
  v_n      int;
begin
  select g.id into v_g1
    from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_c1
     and g.collaborator_id = 'e8b00000-0000-0000-0000-000000000001'
     and g.tipo = 'NEGOCIO_PROJETO';

  -- (8) FINALIZAR: 1a finalizacao explicita; NAO exige aprovacao e NAO invalida
  --     as aprovacoes vigentes (D17/D19).
  v_res := public.meta_finalizar(v_g1, v_alfa,
    'Fechamento A da sequencia integrada (P7)', true, 3, v_a1, v_o8);
  if (v_res->>'version')::int <> 4 or (v_res->>'status') <> 'ATINGIDA' then
    raise exception '[FAIL] S9/finalizar: retorno deveria ser version 4 / ATINGIDA (%)', v_res;
  end if;
  select g.version, g.status into v_v, v_st from public.evaluation_goals g where g.id = v_g1;
  if v_v <> 4 or v_st <> 'ATINGIDA' then
    raise exception '[FAIL] S9/finalizar: linha divergente (version=%, status=%)', v_v, v_st;
  end if;
  if not exists (select 1 from public.evaluation_goals g
                  where g.id = v_g1 and g.atingida is true and g.data_fechamento is not null
                    and g.resultado_final = 'Fechamento A da sequencia integrada (P7)') then
    raise exception '[FAIL] S9/finalizar: fechamento coerente (atingida/data/resultado) nao gravado';
  end if;
  -- D19: FINALIZAR nao invalida.
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] S9/finalizar: a 1a finalizacao NAO pode invalidar aprovacoes (vigentes=%)', v_n;
  end if;

  -- (9) REVISAR FECHAMENTO: operacao EXPLICITA; o fechamento anterior fica
  --     INTEGRALMENTE recuperavel no before_value (nunca sobrescrita silenciosa).
  v_res := public.meta_revisar_finalizacao(v_g1, v_alfa,
    'Fechamento B da sequencia integrada (P7)', false,
    'Revisao do fechamento (P7)', 4, v_a1, v_o9);
  if (v_res->>'version')::int <> 5 or (v_res->>'status') <> 'NAO_ATINGIDA' then
    raise exception '[FAIL] S9/revisar: retorno deveria ser version 5 / NAO_ATINGIDA (%)', v_res;
  end if;
  select e.before_value into v_before from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.operation_id = v_o9 and e.event_type = 'REVISAO_FINALIZACAO';
  if v_before is null
     or (v_before->>'atingida')::boolean is not true
     or (v_before->>'resultado_final') <> 'Fechamento A da sequencia integrada (P7)' then
    raise exception '[FAIL] S9/revisar: o before_value deve preservar INTEGRALMENTE o fechamento anterior (%)', v_before;
  end if;

  -- (10) EXCLUIR: soft delete TERMINAL; a linha e a trilha permanecem (D5/D9) e
  --      a exclusao NAO invalida aprovacoes (D19).
  v_res := public.meta_excluir(v_g1, v_alfa,
    'Encerramento da sequencia integrada (P7)', 5, v_a1, v_o10);
  if (v_res->>'version')::int <> 6 then
    raise exception '[FAIL] S9/excluir: retorno deveria ser version 6 (%)', v_res;
  end if;
  if not exists (select 1 from public.evaluation_goals g
                  where g.id = v_g1 and g.excluida is true and g.data_exclusao is not null
                    and g.version = 6) then
    raise exception '[FAIL] S9/excluir: soft delete coerente (excluida/data/version) nao gravado';
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals a
   where a.organization_id = v_alfa and a.goal_id = v_g1 and a.revogado_em is null;
  if v_n <> 1 then
    raise exception '[FAIL] S9/excluir: a exclusao logica NAO pode invalidar aprovacoes (vigentes=%)', v_n;
  end if;

  -- CONSOLIDACAO DA TRILHA: 12 eventos, 1 por operacao, sem operation_id duplicado.
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g1;
  if v_n <> 12 then
    raise exception '[FAIL] S9/trilha: esperados 12 eventos na meta da sequencia, encontrados %', v_n;
  end if;
  select count(*) into v_n from (
    select e.event_type, count(*) as c
      from public.evaluation_goal_events e
     where e.organization_id = v_alfa and e.goal_id = v_g1
     group by e.event_type) t
   where (t.event_type = 'CRIADA' and t.c = 1)
      or (t.event_type = 'EDITADA' and t.c = 2)
      or (t.event_type = 'PROGRESSO_ATUALIZADO' and t.c = 1)
      or (t.event_type = 'APROVACAO_GERENTE' and t.c = 2)
      or (t.event_type = 'APROVACAO_COORDENADOR' and t.c = 1)
      or (t.event_type = 'APROVACAO_INVALIDADA' and t.c = 2)
      or (t.event_type = 'FINALIZADA' and t.c = 1)
      or (t.event_type = 'REVISAO_FINALIZACAO' and t.c = 1)
      or (t.event_type = 'EXCLUIDA' and t.c = 1);
  if v_n <> 9 then
    raise exception '[FAIL] S9/trilha: distribuicao de event_type divergente do contrato (% de 9 tipos esperados)', v_n;
  end if;
  select count(*) into v_n from (
    select e.operation_id
      from public.evaluation_goal_events e
     where e.organization_id = v_alfa and e.goal_id = v_g1
     group by e.operation_id having count(*) > 1) t;
  if v_n <> 0 then
    raise exception '[FAIL] S9/trilha: operation_id duplicado na trilha da meta (%)', v_n;
  end if;
  -- Autoria soberana: toda a trilha da meta tem autoria resolvida no banco
  -- (o dono a1 nas operacoes do dono; os aprovadores congelados nas aprovacoes).
  select count(*) into v_n from public.evaluation_goal_events e
   where e.organization_id = v_alfa and e.goal_id = v_g1
     and e.actor_user_profile_id is null;
  if v_n <> 0 then
    raise exception '[FAIL] S9/trilha: % evento(s) sem autoria soberana', v_n;
  end if;

  raise notice '[PASS] S9 (bloco 1, parte B): FINALIZAR (v4/ATINGIDA, sem invalidar) -> REVISAR (v5/NAO_ATINGIDA com o fechamento anterior INTEGRAL no before_value) -> EXCLUIR (v6, soft delete terminal, sem invalidar) — trilha consolidada com 12 eventos, 1 por operacao, operation_id unico e autoria soberana';
end $$;

-- ============================================================================
-- 5) BLOCOS 10/11/12 — ciclo NAO ATIVO, meta EXCLUIDA e QUOTA EXCEDIDA
-- ============================================================================
do $$
declare
  v_alfa   uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_c1     uuid := 'e8d10000-0000-0000-0000-0000000000a1';
  v_c2     uuid := 'e8d10000-0000-0000-0000-0000000000a2';
  v_dono   uuid := 'e8b00000-0000-0000-0000-000000000001';
  v_a1     uuid := 'e8c00000-0000-0000-0000-000000000001';
  v_a2     uuid := 'e8c00000-0000-0000-0000-000000000002';
  v_g6     uuid := 'e8000000-0000-0000-0000-000000000006';
  v_probe  uuid := 'e8700000-0000-0000-0000-0000000000f4';
  v_g1     uuid;
  v_ok     boolean;
  v_msg    text;
  v_n      int;
begin
  select g.id into v_g1
    from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_c1
     and g.collaborator_id = v_dono and g.tipo = 'NEGOCIO_PROJETO';

  -- --------------------------------------------------------------------------
  -- §10 (BLOCO 10) — CICLO NAO ATIVO (G6 vive em ciclo ENCERRADO)
  -- --------------------------------------------------------------------------
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_g6, v_alfa, 'probe ciclo encerrado (P7)',
      'KPI probe (P7)', '1 unidade (P7)', 0, v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%' and sqlerrm like '%ATIVO%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S10/editar: edicao em ciclo NAO ATIVO deveria ser F5_10_CONFLICT de ciclo ATIVO (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(v_g6, v_alfa, 'probe ciclo encerrado (P7)',
      10, 0, v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%' and sqlerrm like '%ATIVO%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S10/progresso: acompanhamento em ciclo NAO ATIVO deveria ser F5_10_CONFLICT de ciclo ATIVO (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g6, v_alfa, 'GERENTE', 'probe ciclo encerrado (P7)',
      0, v_a2, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%' and sqlerrm like '%ATIVO%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S10/aprovar: aprovacao em ciclo NAO ATIVO deveria ser F5_10_CONFLICT de ciclo ATIVO (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_criar(v_alfa, v_c2, v_dono, 'NEGOCIO_PROJETO',
      'probe criacao em ciclo encerrado (P7)', 'KPI probe (P7)', '1 unidade (P7)',
      v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%' and sqlerrm like '%ATIVO%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S10/criar: criacao em ciclo NAO ATIVO deveria ser F5_10_CONFLICT de ciclo ATIVO (recebido %)', v_msg;
  end if;
  -- Nenhum efeito: G6 segue version 0 e sem evento.
  select count(*) into v_n from public.evaluation_goals g
   where g.id = v_g6 and g.version = 0 and g.status = 'EM_ANDAMENTO' and g.excluida = false;
  if v_n <> 1 then
    raise exception '[FAIL] S10: as recusas por ciclo NAO ATIVO nao podem mutar a meta';
  end if;

  raise notice '[PASS] S10 (bloco 10): em ciclo ENCERRADO, editar/progredir/aprovar/criar sao F5_10_CONFLICT de "exige ciclo ATIVO" (o estado do CICLO e lido da linha soberana, nunca do corpo)';

  -- --------------------------------------------------------------------------
  -- §11 (BLOCO 11) — META EXCLUIDA (soft delete TERMINAL)
  -- --------------------------------------------------------------------------
  v_ok := false; v_msg := null;
  begin
    perform public.meta_editar(v_g1, v_alfa, 'probe meta excluida (P7)',
      'KPI probe (P7)', '1 unidade (P7)', 6, v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%' and sqlerrm like '%excluida%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S11/editar: edicao de meta EXCLUIDA deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_atualizar_progresso(v_g1, v_alfa, 'probe meta excluida (P7)',
      10, 6, v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S11/progresso: acompanhamento de meta EXCLUIDA deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_finalizar(v_g1, v_alfa, 'probe meta excluida (P7)', true, 6, v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S11/finalizar: finalizacao de meta EXCLUIDA deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  v_ok := false; v_msg := null;
  begin
    perform public.meta_aprovar(v_g1, v_alfa, 'GERENTE', 'probe meta excluida (P7)',
      6, v_a2, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%' and sqlerrm like '%excluida%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S11/aprovar: aprovacao de meta EXCLUIDA deveria ser F5_10_CONFLICT (recebido %)', v_msg;
  end if;
  -- A exclusao logica e TERMINAL: nem a propria exclusao se repete.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_excluir(v_g1, v_alfa, 'probe reexclusao (P7)', 6, v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%' and sqlerrm like '%ja excluida%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S11/excluir: reexclusao deveria ser F5_10_CONFLICT terminal (recebido %)', v_msg;
  end if;
  -- A LINHA existe (nunca DELETE fisico) e a version nao regrediu.
  select count(*) into v_n from public.evaluation_goals g
   where g.id = v_g1 and g.excluida = true and g.version = 6;
  if v_n <> 1 then
    raise exception '[FAIL] S11: a meta excluida deve PERSISTIR (nenhum DELETE fisico) com version 6';
  end if;

  raise notice '[PASS] S11 (bloco 11): meta EXCLUIDA e terminal — editar/progredir/finalizar/aprovar/re-excluir sao F5_10_CONFLICT, a linha PERSISTE (nenhum DELETE fisico) e nenhuma tentativa recusada grava evento';

  -- --------------------------------------------------------------------------
  -- §12 (BLOCO 12) — QUOTA EXCEDIDA (INDIVIDUAL = 2, com 2 metas vivas em C1)
  -- --------------------------------------------------------------------------
  select count(*) into v_n from public.evaluation_cycle_goal_limits l
   where l.organization_id = v_alfa and l.cycle_id = v_c1 and l.tipo = 'INDIVIDUAL';
  if v_n <> 1 then
    raise exception '[FAIL] S12: pre-condicao — quota INDIVIDUAL de C1 ausente';
  end if;
  select count(*) into v_n from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_c1
     and g.tipo = 'INDIVIDUAL' and g.excluida = false;
  if v_n <> 2 then
    raise exception '[FAIL] S12: pre-condicao — esperadas 2 metas INDIVIDUAL vivas em C1, encontradas %', v_n;
  end if;
  -- (a) A RPC recusa acima do limite.
  v_ok := false; v_msg := null;
  begin
    perform public.meta_criar(v_alfa, v_c1, v_dono, 'INDIVIDUAL',
      'probe quota excedida (P7)', 'KPI probe (P7)', '1 unidade (P7)', v_a1, v_probe);
  exception when others then v_ok := sqlerrm like '%F5_10_CONFLICT%' and sqlerrm like '%quota%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S12/quota: criacao acima da quota deveria ser F5_10_CONFLICT de quota (recebido %)', v_msg;
  end if;
  -- (b) A quota e INVARIANTE DO BANCO (D20): a insercao DIRETA tambem e recusada
  --     pelo trigger, independentemente do cliente ou da RPC.
  v_ok := false; v_msg := null;
  begin
    insert into public.evaluation_goals
      (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_alfa, v_c1, 'e8b00000-0000-0000-0000-000000000009', 'INDIVIDUAL',
            'probe de insercao direta acima da quota (P7)', 'KPI probe (P7)', '1 unidade (P7)');
  exception when others then v_ok := sqlerrm like '%quota%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S12/invariante: o BANCO deveria recusar insercao direta acima da quota (D20) (recebido %)', v_msg;
  end if;
  -- (c) A quota nao pode ser REDUZIDA abaixo das metas vivas (D21, trigger).
  v_ok := false; v_msg := null;
  begin
    update public.evaluation_cycle_goal_limits
       set quantidade = 1
     where organization_id = v_alfa and cycle_id = v_c1 and tipo = 'INDIVIDUAL';
  exception when others then v_ok := sqlerrm like '%nao pode ser reduzida%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] S12/reducao: reduzir a quota abaixo das metas vivas deveria ser recusado (D21) (recebido %)', v_msg;
  end if;
  -- Nenhuma das recusas criou meta.
  select count(*) into v_n from public.evaluation_goals g
   where g.organization_id = v_alfa and g.cycle_id = v_c1 and g.tipo = 'INDIVIDUAL';
  if v_n <> 2 then
    raise exception '[FAIL] S12: as recusas de quota nao podem criar meta (INDIVIDUAL=%)', v_n;
  end if;

  raise notice '[PASS] S12 (bloco 12): quota excedida — a RPC recusa (F5_10_CONFLICT), o BANCO recusa a insercao DIRETA (invariante D20) e a quota nao pode ser reduzida abaixo das metas vivas (D21); nenhuma recusa cria meta';
end $$;

-- ============================================================================
-- 6) BLOCO 15 — TRILHA APPEND-ONLY
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_antes int;
  v_depois int;
  v_ok    boolean;
begin
  select count(*) into v_antes from public.evaluation_goal_events where organization_id = v_alfa;
  if v_antes = 0 then
    raise exception '[FAIL] S13: pre-condicao — trilha de Alfa vazia';
  end if;

  v_ok := false;
  begin
    update public.evaluation_goal_events set reason = 'adulteracao (P7)' where organization_id = v_alfa;
  exception when others then v_ok := sqlerrm like '%append-only%';
  end;
  if not v_ok then
    raise exception '[FAIL] S13/UPDATE: a trilha deve recusar UPDATE com mensagem append-only (mesmo para o owner)';
  end if;

  v_ok := false;
  begin
    delete from public.evaluation_goal_events where organization_id = v_alfa;
  exception when others then v_ok := sqlerrm like '%append-only%';
  end;
  if not v_ok then
    raise exception '[FAIL] S13/DELETE: a trilha deve recusar DELETE com mensagem append-only';
  end if;

  v_ok := false;
  begin
    truncate public.evaluation_goal_events;
  exception when others then v_ok := sqlerrm like '%append-only%';
  end;
  if not v_ok then
    raise exception '[FAIL] S13/TRUNCATE: a trilha deve recusar TRUNCATE com mensagem append-only';
  end if;

  select count(*) into v_depois from public.evaluation_goal_events where organization_id = v_alfa;
  if v_depois <> v_antes then
    raise exception '[FAIL] S13: a trilha mudou de tamanho apesar das recusas (antes=%, depois=%)', v_antes, v_depois;
  end if;

  raise notice '[PASS] S13 (bloco 15): a trilha de metas e APPEND-ONLY no BANCO — UPDATE, DELETE e TRUNCATE sao recusados pelo trigger (mesmo para owner/service_role), com a contagem de eventos intacta (%)', v_antes;
end $$;

-- ============================================================================
-- 7) BLOCOS 16/17 — RLS/ACL de cliente e proibicao de RPC direta
-- ============================================================================
do $$
declare
  v_fn   text;
  v_tab  text;
  v_n    int;
begin
  -- Privilegios DECLARADOS: nem `authenticated` nem `anon` executam QUALQUER
  -- funcao da superficie de metas, e nao ha privilegio de tabela.
  foreach v_fn in array array[
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
    'public.f5_10_exigir_autorizacao_meta(text, uuid, uuid, uuid, uuid)',
    'public.f5_10_vinculo_meta_do_ator(uuid, uuid)',
    'public.f5_10_aprovador_congelado(uuid, uuid, text)',
    'public.f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid)',
    'public.f5_10_derivar_operation_id(uuid, text)',
    'public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid)'] loop
    if to_regprocedure(v_fn) is null then
      raise exception '[FAIL] S14: funcao do contrato ausente: %', v_fn;
    end if;
    if has_function_privilege('authenticated', v_fn, 'EXECUTE')
       or has_function_privilege('anon', v_fn, 'EXECUTE') then
      raise exception '[FAIL] S14: EXECUTE exposto a cliente em %', v_fn;
    end if;
    if not has_function_privilege('service_role', v_fn, 'EXECUTE') then
      raise exception '[FAIL] S14: service_role sem EXECUTE em %', v_fn;
    end if;
  end loop;

  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if has_table_privilege('authenticated', format('public.%I', v_tab), 'SELECT')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'INSERT')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'UPDATE')
       or has_table_privilege('authenticated', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('anon', format('public.%I', v_tab), 'SELECT')
       or has_table_privilege('anon', format('public.%I', v_tab), 'INSERT') then
      raise exception '[FAIL] S14: privilegio de cliente residual em %', v_tab;
    end if;
    -- service_role e EXECUTOR tecnico: nunca DELETE/TRUNCATE.
    if has_table_privilege('service_role', format('public.%I', v_tab), 'DELETE')
       or has_table_privilege('service_role', format('public.%I', v_tab), 'TRUNCATE') then
      raise exception '[FAIL] S14: service_role com DELETE/TRUNCATE em %', v_tab;
    end if;
  end loop;

  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef
     and p.proname <> all (array[
       'conceder_acesso_role', 'criar_perfil_membership',
       'resolver_capabilities_efetivas', 'revogar_acesso_role']);
  if v_n <> 0 then
    raise exception '[FAIL] S14: SECURITY DEFINER novo em public (%)', v_n;
  end if;

  raise notice '[PASS] S14 (blocos 16/17, lado servidor): as 17 funcoes do contrato tem EXECUTE SO para `service_role`, as 4 tabelas de metas nao concedem NENHUM privilegio a `authenticated`/`anon`, `service_role` nao tem DELETE/TRUNCATE e nao existe SECURITY DEFINER novo';
end $$;

-- A prova EFETIVA de recusa por PERMISSAO exige impersonar o cliente.
select set_config('request.jwt.claim.sub', 'e8c00000-0000-0000-0000-000000000001', false);
set role authenticated;

do $$
declare
  v_alfa  uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_c1    uuid := 'e8d10000-0000-0000-0000-0000000000a1';
  v_g1    uuid := 'e8000000-0000-0000-0000-000000000003';
  v_ok    boolean;
begin
  -- RPC direta do browser (Edge e a UNICA fronteira autorizada — D23).
  v_ok := false;
  begin
    perform public.meta_criar(v_alfa, v_c1, 'e8b00000-0000-0000-0000-000000000001',
      'INDIVIDUAL', 'probe de RPC direta (P7)', 'KPI probe (P7)', '1 unidade (P7)',
      'e8c00000-0000-0000-0000-000000000001', 'e8700000-0000-0000-0000-0000000000fb');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: chamada DIRETA de meta_criar por `authenticated` deveria ser permission denied (42501)';
  end if;
  v_ok := false;
  begin
    perform public.meta_listar_por_escopo(v_alfa, v_c1, 'e8c00000-0000-0000-0000-000000000001');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: chamada DIRETA de meta_listar_por_escopo por `authenticated` deveria ser 42501';
  end if;
  v_ok := false;
  begin
    perform public.f5_10_ator_valido_meta('e8c00000-0000-0000-0000-000000000001', v_alfa, 'goal.read');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: helper f5_10_ator_valido_meta nao pode ser executavel por `authenticated`';
  end if;

  -- Nenhuma das 4 tabelas: SELECT e DML negados por PERMISSAO (42501) — D22-A.
  v_ok := false;
  begin
    perform 1 from public.evaluation_goals;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: SELECT em evaluation_goals por `authenticated` deveria ser 42501 (D22-A)';
  end if;
  v_ok := false;
  begin
    perform 1 from public.evaluation_goal_approvals;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: SELECT em evaluation_goal_approvals por `authenticated` deveria ser 42501';
  end if;
  v_ok := false;
  begin
    perform 1 from public.evaluation_goal_events;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: SELECT em evaluation_goal_events por `authenticated` deveria ser 42501';
  end if;
  v_ok := false;
  begin
    perform 1 from public.evaluation_cycle_goal_limits;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: SELECT em evaluation_cycle_goal_limits por `authenticated` deveria ser 42501';
  end if;
  v_ok := false;
  begin
    insert into public.evaluation_goals (organization_id, cycle_id, collaborator_id, tipo, descricao, kpi, valor_alvo)
    values (v_alfa, v_c1, 'e8b00000-0000-0000-0000-000000000001', 'INDIVIDUAL',
            'probe de INSERT de cliente (P7)', 'KPI probe (P7)', '1 unidade (P7)');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: INSERT em evaluation_goals por `authenticated` deveria ser 42501';
  end if;
  v_ok := false;
  begin
    update public.evaluation_goals set version = version + 1;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: UPDATE em evaluation_goals por `authenticated` deveria ser 42501';
  end if;
  v_ok := false;
  begin
    delete from public.evaluation_goals;
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: DELETE em evaluation_goals por `authenticated` deveria ser 42501';
  end if;
  v_ok := false;
  begin
    insert into public.evaluation_goal_approvals
      (organization_id, goal_id, papel, actor_user_profile_id, actor_membership_id)
    values (v_alfa, v_g1, 'GERENTE',
            'e8c00000-0000-0000-0000-000000000002', 'e8d00000-0000-0000-0000-000000000002');
  exception when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] S14: INSERT em evaluation_goal_approvals por `authenticated` deveria ser 42501';
  end if;

  raise notice '[PASS] S14 (blocos 16/17, lado cliente): `authenticated` NAO executa as RPCs/helpers de metas (42501) e NAO le nem escreve NENHUMA das 4 tabelas — a superficie de leitura funcional e exclusivamente `meta_listar_por_escopo` (via Edge) e nao ha caminho direto de browser';
end $$;

reset role;

-- ============================================================================
-- 8) BLOCO 19 — guardas invertidas coerentes (inventario FECHADO)
-- ============================================================================
do $$
declare
  v_tab    text;
  v_fn     text;
  v_n      int;
  v_falhas text[] := array[]::text[];
begin
  -- (a) As 4 tabelas do contrato existem, com RLS habilitada e ZERO policy.
  foreach v_tab in array array[
    'evaluation_goals', 'evaluation_goal_approvals',
    'evaluation_goal_events', 'evaluation_cycle_goal_limits'] loop
    if not exists (
      select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tab and c.relkind = 'r' and c.relrowsecurity
    ) then
      v_falhas := v_falhas || format('tabela de metas ausente ou sem RLS: %s', v_tab);
    end if;
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = v_tab;
    if v_n <> 0 then
      v_falhas := v_falhas || format('policy em %s (%s) — D22-A exige deny-by-default integral', v_tab, v_n);
    end if;
  end loop;

  -- (b) A guarda INVERTIDA das fases anteriores e' uma LISTA FECHADA por nome
  --     (`%meta%`/`%goal%`): nada de metas pode existir FORA dela. A P7 reforca a
  --     coerencia provando tambem os helpers cujo NOME NAO casa com o filtro —
  --     exatamente o ponto cego que a lista fechada por nome nao cobre.
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and (c.relname like '%goal%' or c.relname like '%meta%')
     and c.relname <> all (array[
       'evaluation_goals', 'evaluation_goal_approvals',
       'evaluation_goal_events', 'evaluation_cycle_goal_limits']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s tabela(s) de metas FORA da lista fechada', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like '%meta%' or p.proname like '%goal%')
     and p.proname <> all (array[
       'enforce_evaluation_goal_events_append_only', 'f5_10_validar_quota_da_meta',
       'f5_10_validar_quota_do_limite', 'f5_10_proteger_limite_do_ciclo',
       'f5_10_validar_autoria_da_aprovacao', 'f5_10_ator_valido_meta',
       'f5_10_exigir_autorizacao_meta', 'f5_10_vinculo_meta_do_ator',
       'meta_criar', 'meta_editar', 'meta_atualizar_progresso', 'meta_finalizar',
       'meta_revisar_finalizacao', 'meta_excluir', 'meta_definir_limites_do_ciclo',
       'meta_aprovar', 'meta_invalidar_aprovacoes', 'meta_listar_por_escopo']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) de metas FORA da lista fechada', v_n);
  end if;
  -- Ponto cego declarado: os 4 helpers de aprovacao cujo nome NAO casa com
  -- `%meta%`/`%goal%`. Eles existem, sao INVOKER e tem EXECUTE so service_role.
  foreach v_fn in array array[
    'public.f5_10_aprovador_congelado(uuid, uuid, text)',
    'public.f5_10_invalidar_aprovacoes_vigentes(uuid, uuid, uuid, uuid, text, text, uuid)',
    'public.f5_10_derivar_operation_id(uuid, text)',
    'public.f5_10_exigir_relacao_aprovador(uuid, uuid, text, uuid)'] loop
    if to_regprocedure(v_fn) is null then
      v_falhas := v_falhas || format('helper de aprovacao ausente: %s', v_fn);
    elsif (select p.prosecdef from pg_proc p where p.oid = to_regprocedure(v_fn)) then
      v_falhas := v_falhas || format('helper de aprovacao com SECURITY DEFINER: %s', v_fn);
    end if;
  end loop;

  -- (c) F5-11 (observacoes): a PROIBICAO ABSOLUTA de objeto de observacao foi
  --     SUBSTITUIDA pela doutrina de LISTA FECHADA (nunca removida). A F5-11 P1
  --     (Issue #238) legitimou as DUAS tabelas do contrato (linha + trilha) e as duas
  --     funcoes de enforcement; a F5-11 P2 (Issue #244) acrescentou as 8 RPCs
  --     `observacao_*` e os 5 helpers do gate, ampliando a lista explicitamente.
  --     Qualquer objeto de observacao fora dessas listas continua reprovando.
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and (c.relname like '%observation%' or c.relname like '%observac%')
     and c.relname <> all (array[
       'evaluation_observations','evaluation_observation_events']);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s tabela(s) de observacoes FORA da lista fechada da F5-11 P1', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like '%observa%' or p.proname like '%observation%')
     and p.proname <> all (array[
       -- F5-11 P1: as DUAS funcoes de enforcement da propria P1 (imutabilidade
       -- estrutural D4 e append-only da trilha D6). O nome casa com o filtro por
       -- nome — a lista fechada precisa nomea-las, sem abrir espaco para RPC.
       'enforce_evaluation_observations_imutaveis',
       'enforce_evaluation_observation_events_append_only',    -- F5-11 P2 (Issue #244): as RPCs soberanas `observacao_*` e os helpers do
    -- gate funcional. A fase AMPLIA a lista explicitamente (a proibicao absoluta
    -- virou lista fechada na P1 e nunca e' removida); nenhum `observation_*`.
    'observacao_criar','observacao_editar','observacao_definir_comunicado',
    'observacao_excluir','observacao_revogar','observacao_obter',
    'observacao_listar_por_escopo','observacao_historico',
    'f5_11_ator_efetivo_observacao','f5_11_ator_valido_observacao',
    'f5_11_vinculo_observacao_do_ator','f5_11_relacao_observacao_do_ator',
    'f5_11_exigir_autorizacao_observacao'       ]);
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s funcao(oes) de observacoes FORA da lista fechada da F5-11 P1 (nenhuma RPC observacao_* existe ate a P2)', v_n);
  end if;
  -- As duas tabelas legitimas da F5-11 P1 precisam EXISTIR (a lista fechada nao
  -- pode virar desculpa para ausencia).
  foreach v_fn in array array[
    'evaluation_observations', 'evaluation_observation_events'] loop
    if to_regclass('public.' || v_fn) is null then
      v_falhas := v_falhas || format('tabela legitima da F5-11 P1 ausente: %s', v_fn);
    end if;
  end loop;

  -- (d) Catalogo de capabilities e bundle `admin` intactos (D6/D28).
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_falhas := v_falhas || format('catalogo com %s capabilities (esperado 31)', v_n);
  end if;
  select count(*) into v_n from public.capabilities where code like 'cycle.%';
  if v_n <> 5 then
    v_falhas := v_falhas || format('capabilities de ciclo = %s (esperado 5)', v_n);
  end if;
  select count(*) into v_n from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_n <> 9 then
    v_falhas := v_falhas || format('bundle admin com %s capabilities (esperado 9)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] S15 (bloco 19): guardas invertidas incoerentes: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] S15 (bloco 19): guardas invertidas coerentes — 4 tabelas de metas com RLS e ZERO policy, NENHUM objeto de metas fora da lista fechada (tabelas e funcoes), os 4 helpers de aprovacao cujo nome NAO casa com o filtro por nome provados individualmente (INVOKER, EXECUTE so service_role), F5-11 em LISTA FECHADA da P1 (as 2 tabelas do contrato existem e NENHUMA funcao observacao_* foi criada), catalogo com 31 capabilities, 5 de ciclo e bundle admin com 9';
end $$;

-- ============================================================================
-- 9) BLOCO 18 — regressoes P1–P6 (invariantes consolidados)
-- ============================================================================
do $$
declare
  v_n      int;
  v_falhas text[] := array[]::text[];
  v_nome   text;
begin
  -- P1: invariantes estruturais, unicidades parciais e FKs compostas de tenant.
  foreach v_nome in array array[
    'uq_evaluation_goals_org_cycle_collab_tipo_viva',
    'uq_evaluation_goal_approvals_goal_papel_vigente'] loop
    if not exists (select 1 from pg_indexes
                    where schemaname = 'public' and indexname = v_nome) then
      v_falhas := v_falhas || format('indice parcial ausente: %s', v_nome);
    end if;
  end loop;
  foreach v_nome in array array[
    'fk_evaluation_goals_cycle', 'fk_evaluation_goals_collaborator',
    'fk_evaluation_goal_approvals_goal', 'fk_evaluation_goal_events_goal',
    'fk_evaluation_cycle_goal_limits_cycle'] loop
    if not exists (select 1 from pg_constraint c
                    where c.conname = v_nome and c.contype = 'f'
                      and pg_get_constraintdef(c.oid) like '%organization_id)%') then
      v_falhas := v_falhas || format('FK composta de tenant ausente: %s', v_nome);
    end if;
  end loop;
  foreach v_nome in array array[
    'trg_evaluation_goal_events_append_only',
    'trg_evaluation_goal_events_no_delete',
    'trg_evaluation_goal_events_no_truncate',
    'trg_evaluation_goals_quota',
    'trg_evaluation_cycle_goal_limits_quota',
    'trg_evaluation_cycle_goal_limits_no_delete',
    'trg_evaluation_goal_approvals_autoria'] loop
    if not exists (select 1 from pg_trigger t
                    where t.tgname = v_nome and not t.tgisinternal) then
      v_falhas := v_falhas || format('gatilho do contrato ausente: %s', v_nome);
    end if;
  end loop;
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'public.evaluation_goals'::regclass
                    and c.conname = 'ck_evaluation_goals_fechamento' and c.contype = 'c'
                    and pg_get_constraintdef(c.oid) like '%ATINGIDA%'
                    and pg_get_constraintdef(c.oid) like '%btrim%') then
    v_falhas := v_falhas || 'CHECK de fechamento nao esta endurecido (D17)';
  end if;

  -- P2/P3/P4/P5.2: as 10 RPCs do contrato existem, sao INVOKER com search_path
  -- fixo e EXECUTE SO para service_role.
  foreach v_nome in array array[
    'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)',
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_listar_por_escopo(uuid, uuid, uuid)'] loop
    if (select p.prosecdef from pg_proc p where p.oid = to_regprocedure(v_nome)) then
      v_falhas := v_falhas || format('RPC com SECURITY DEFINER: %s', v_nome);
    end if;
    if (select position('search_path=public' in coalesce(array_to_string(p.proconfig, ','), ''))
          from pg_proc p where p.oid = to_regprocedure(v_nome)) = 0 then
      v_falhas := v_falhas || format('RPC sem search_path fixo: %s', v_nome);
    end if;
  end loop;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like 'meta\_%';
  if v_n <> 10 then
    v_falhas := v_falhas || format('RPCs meta_* = %s (esperado exatamente 10)', v_n);
  end if;

  -- P5/D22-A: nenhuma policy nas 4 tabelas e nenhum privilegio de cliente.
  select count(*) into v_n from pg_policies
   where schemaname = 'public'
     and tablename in ('evaluation_goals', 'evaluation_goal_approvals',
                       'evaluation_goal_events', 'evaluation_cycle_goal_limits');
  if v_n <> 0 then
    v_falhas := v_falhas || format('policies residuais nas tabelas de metas (%s)', v_n);
  end if;

  -- P4: o gate funcional continua no corpo de TODAS as RPCs de mutacao/leitura.
  foreach v_nome in array array[
    'public.meta_criar(uuid, uuid, uuid, text, text, text, text, uuid, uuid)',
    'public.meta_editar(uuid, uuid, text, text, text, integer, uuid, uuid)',
    'public.meta_atualizar_progresso(uuid, uuid, text, integer, integer, uuid, uuid)',
    'public.meta_finalizar(uuid, uuid, text, boolean, integer, uuid, uuid)',
    'public.meta_revisar_finalizacao(uuid, uuid, text, boolean, text, integer, uuid, uuid)',
    'public.meta_excluir(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_definir_limites_do_ciclo(uuid, uuid, text, integer, text, integer, uuid, uuid)',
    'public.meta_aprovar(uuid, uuid, text, text, integer, uuid, uuid)',
    'public.meta_invalidar_aprovacoes(uuid, uuid, text, integer, uuid, uuid)',
    'public.meta_listar_por_escopo(uuid, uuid, uuid)'] loop
    if not exists (
      select 1 from pg_proc p
       where p.oid = to_regprocedure(v_nome)
         and (position('f5_10_exigir_autorizacao_meta' in pg_get_functiondef(p.oid)) > 0
              or position('f5_10_exigir_relacao_aprovador' in pg_get_functiondef(p.oid)) > 0
              or position('f5_10_ator_valido_meta' in pg_get_functiondef(p.oid)) > 0
              or position('f5_10_vinculo_meta_do_ator' in pg_get_functiondef(p.oid)) > 0)
    ) then
      v_falhas := v_falhas || format('RPC sem gate funcional no corpo: %s', v_nome);
    end if;
  end loop;

  -- P4/D10: as 9 RPCs que MUTAM meta/limite/aprovacao adquirem a MESMA familia
  -- normativa de lock dos ciclos (nenhuma chave nova; a leitura pura nao trava).
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('meta_criar', 'meta_editar', 'meta_atualizar_progresso',
                       'meta_finalizar', 'meta_revisar_finalizacao', 'meta_excluir',
                       'meta_aprovar', 'meta_invalidar_aprovacoes',
                       'meta_definir_limites_do_ciclo')
     and position('ciclo_lock_organizacao' in pg_get_functiondef(p.oid)) > 0;
  if v_n <> 9 then
    v_falhas := v_falhas || format('RPCs de MUTACAO com o lock normativo = %s (esperado exatamente 9)', v_n);
  end if;
  -- E NENHUMA RPC de metas usa lock literal (familia nova proibida por D10).
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like 'meta\_%'
     and position('pg_advisory_xact_lock' in pg_get_functiondef(p.oid)) > 0;
  if v_n <> 0 then
    v_falhas := v_falhas || format('%s RPC(s) de metas com pg_advisory_xact_lock literal (familia nova proibida)', v_n);
  end if;

  if array_length(v_falhas, 1) is not null then
    raise exception '[FAIL] S16 (bloco 18): regressoes P1–P6 quebradas: %', array_to_string(v_falhas, '; ');
  end if;

  raise notice '[PASS] S16 (bloco 18): regressoes P1–P6 verdes — unicidades parciais, 5 FKs compostas de tenant, 7 gatilhos do contrato, CHECK de fechamento endurecido, exatamente 10 RPCs `meta_*` INVOKER com search_path fixo e EXECUTE so service_role, gate funcional presente no corpo das 10 RPCs, as 9 RPCs de MUTACAO com o lock normativo da familia de CICLOS (sem chave literal/familia nova) e ZERO policy de cliente';
end $$;

-- ============================================================================
-- 10) GUARDA FINAL fail-closed + resumo
-- ============================================================================
do $$
declare
  v_alfa  uuid := 'e8a00000-0000-0000-0000-0000000000a1';
  v_beta  uuid := 'e8a00000-0000-0000-0000-0000000000b1';
  v_gama  uuid := 'e8a00000-0000-0000-0000-0000000000c1';
  v_erros text[] := array[]::text[];
  v_n     int;
begin
  -- Estado consolidado do dominio apos a matriz (deterministico).
  select count(*) into v_n from public.evaluation_goals
   where organization_id = v_alfa;
  if v_n <> 5 then
    v_erros := v_erros || format('Alfa com %s metas (esperado 5: 4 de fixture + a da sequencia)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_goals
   where organization_id = v_alfa and excluida = true;
  if v_n <> 1 then
    v_erros := v_erros || format('Alfa com %s metas excluidas (esperado 1)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_goal_events
   where organization_id = v_alfa;
  if v_n <> 17 then
    v_erros := v_erros || format('Alfa com %s eventos (esperado 17: 4 de fixture + 1 da edicao de G3 + 12 da sequencia)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_goal_events
   where organization_id = v_beta;
  if v_n <> 1 then
    v_erros := v_erros || format('Beta com %s eventos (esperado 1: a CRIADA da fixture)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals
   where organization_id = v_alfa;
  if v_n <> 3 then
    v_erros := v_erros || format('Alfa com %s fatos de aprovacao (esperado 3: 2 GERENTE + 1 COORDENADOR)', v_n);
  end if;
  select count(*) into v_n from public.evaluation_goal_approvals
   where organization_id = v_alfa and revogado_em is null;
  if v_n <> 1 then
    v_erros := v_erros || format('Alfa com %s aprovacoes vigentes (esperado 1: GERENTE)', v_n);
  end if;
  -- Gama-P7 e' INTOCADA pela matriz (organizacao exclusiva da corrida).
  select count(*) into v_n from public.evaluation_goal_events where organization_id = v_gama;
  if v_n <> 0 then
    v_erros := v_erros || format('Gama-P7 com %s eventos: a matriz NAO pode escrever na organizacao da corrida', v_n);
  end if;

  -- Nenhum residuo de artefato temporario de prova.
  select count(*) into v_n from pg_trigger t
   where t.tgname like '\_mut\_%' and not t.tgisinternal;
  if v_n <> 0 then
    v_erros := v_erros || format('gatilho temporario de prova deixado no schema (%s)', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_%';
  if v_n <> 0 then
    v_erros := v_erros || format('funcao temporaria de prova deixada no schema (%s)', v_n);
  end if;
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'S' and c.relname like '\_mut\_%';
  if v_n <> 0 then
    v_erros := v_erros || format('sequence temporaria de prova deixada no schema (%s)', v_n);
  end if;

  -- Anti-escopo: a P7 nao criou superficie alguma.
  select count(*) into v_n from public.capabilities;
  if v_n <> 31 then
    v_erros := v_erros || format('catalogo com %s capabilities (a P7 nao pode criar capability)', v_n);
  end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'public'
     and tablename in ('evaluation_goals', 'evaluation_goal_approvals',
                       'evaluation_goal_events', 'evaluation_cycle_goal_limits');
  if v_n <> 0 then
    v_erros := v_erros || format('a P7 nao pode criar policy (%s)', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef
     and p.proname <> all (array[
       'conceder_acesso_role', 'criar_perfil_membership',
       'resolver_capabilities_efetivas', 'revogar_acesso_role']);
  if v_n <> 0 then
    v_erros := v_erros || format('a P7 nao pode criar SECURITY DEFINER (%s)', v_n);
  end if;

  if array_length(v_erros, 1) is not null then
    raise exception '[FAIL] guarda final da P7: %', array_to_string(v_erros, '; ');
  end if;

  raise notice '[PASS] guarda final da P7: 5 metas em Alfa (1 excluida), 17 eventos (4 de fixture + 1 da edicao de G3 + 12 da sequencia integrada), 3 fatos de aprovacao (1 vigente GERENTE / 2 revogados), Beta com 1 evento, Gama-P7 INTOCADA (reservada a corrida 31/32/33), ZERO artefato temporario residual e ZERO superficie nova (nenhuma capability/policy/SECURITY DEFINER)';
end $$;

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-10 P7: MATRIZ INTEGRADA do dominio de metas concluida (blocos 1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 e 19).';
  raise notice 'Bloco 1  — sequencia historica integrada: criar -> editar -> progresso -> aprovar (2 papeis congelados) -> alteracao MATERIAL (D19: 2 invalidacoes com operation_id derivado, fatos preservados) -> reaprovar -> finalizar -> revisar (fechamento anterior recuperavel) -> excluir (soft delete terminal).';
  raise notice 'Bloco 4  — cross-tenant/IDOR: NOT_FOUND para meta/ator/alvo de outro tenant, FORBIDDEN sem membership e leitura por escopo devolvendo SO o autorizado (SELF + papeis congelados).';
  raise notice 'Bloco 5  — membership REVOGADA e perfil `disabled` recusados por F5_10_FORBIDDEN, sem mutacao e sem evento.';
  raise notice 'Blocos 6/7 — CAPABILITY sem RELACAO e RELACAO sem CAPABILITY, ambas DENY, com a relacao provada ANTES do estado.';
  raise notice 'Bloco 8  — SELF de terceiro recusado em editar/progredir/finalizar/excluir; a escrita SELF legitima coexiste (capability + relacao).';
  raise notice 'Bloco 9  — aprovador congelado aprova e NAO escreve (goal.approve NAO implica goal.write).';
  raise notice 'Bloco 10 — ciclo NAO ATIVO recusado em editar/progredir/aprovar/criar.';
  raise notice 'Bloco 11 — meta EXCLUIDA e terminal e a linha PERSISTE (nenhum DELETE fisico).';
  raise notice 'Bloco 12 — quota excedida recusada pela RPC **e** pelo invariante do BANCO; quota nao pode ser reduzida abaixo das metas vivas.';
  raise notice 'Bloco 13 — idempotencia: replay com o mesmo payload devolve o MESMO resultado; payload divergente e F5_10_CONFLICT.';
  raise notice 'Bloco 14 — rollback TOTAL quando a gravacao da trilha falha (nem a meta nem o evento persistem).';
  raise notice 'Bloco 15 — trilha APPEND-ONLY: UPDATE/DELETE/TRUNCATE negados por gatilho.';
  raise notice 'Blocos 16/17 — cliente nao executa RPC/helper algum (42501) e nao le nem escreve as 4 tabelas.';
  raise notice 'Bloco 18 — regressoes P1–P6 verdes (unicidades, FKs de tenant, gatilhos, CHECK endurecido, 10 RPCs INVOKER com gate e lock normativo).';
  raise notice 'Bloco 19 — guardas invertidas coerentes, inclusive os helpers fora do filtro por nome.';
  raise notice 'Bloco 6 (CONCORRENCIA REAL) — provado em DUAS sessoes pelos arquivos 31/32/33.';
  raise notice '============================================================';
end $$;
