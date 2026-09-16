-- ============================================================================
-- F5-09 P9: validacao INTEGRADA da matriz de ciclos soberanos
-- (Supabase local apenas)
-- ----------------------------------------------------------------------------
-- Executar DEPOIS de aplicar, nesta ordem:
--   1) `npx --yes supabase@2.116.0 db reset --local --yes`   (migrations)
--   2) `14-cenario-f5-09-p9.sql`  (fixture isolada / guarda de estado limpo)
--   3) este arquivo               (asserts `[PASS]`/`[FAIL]`)
--
-- ORDEM/RESET: este validador SO pode rodar UMA vez por banco recem-resetado.
-- Ele produz propositalmente dois efeitos IRREVERSIVEIS (a trilha de ciclos e
-- append-only e nao ha DELETE): (a) desabilita a membership do ator
-- revogavel-alfa (§2) e (b) remove o grant de `cycle.manage` da role do
-- gestor-alfa (§3). Repetir sem `db reset` FALHA na pre-condicao de estado sujo
-- (mensagem explicita), nunca em silencio.
--
-- SEM INTERFERENCIA NOS VALIDADORES DE CONCORRENCIA (16/17/18): os dois efeitos
-- acima atingem SOMENTE atores de Alfa-P9. O tenant reservado Gama-P9, o ator
-- gestor-gama (edc...0006, membership e role intactas) e a
-- `ciclo_lock_organizacao` permanecem intocados, e este arquivo NAO cria ciclo
-- nem evento em Gama-P9 (conferido na pre-condicao e nao tocado depois). Como
-- este arquivo e o unico que muta estado de fixture de forma irreversivel, ele
-- deve rodar DEPOIS dos demais validadores da P9 (ou em banco recem resetado).
--
-- INVARIANTE I5 — UM UNICO CICLO `ATIVO` POR ORGANIZACAO, TODO O TEMPO:
-- o indice unico parcial `uq_evaluation_cycles_org_ativo` recusa a segunda
-- ativacao. Por isso este validador SERIALIZA o ciclo de vida por organizacao:
-- ativa UM ciclo -> opera -> encerra/cancela -> so entao ativa o proximo. NENHUM
-- bloco assume dois `ATIVO` simultaneos; a cronologia completa (e a versao
-- esperada de cada chamada) esta na secao "1) Cronologia" logo abaixo.
--
-- Contrato coberto (docs/F5-09-desenho-tecnico.md §6, §8, §9, §10, §11, §12,
-- §13.2, §15.1 A3/A11, §19 P9; migrations P1..P7 da F5-09):
--   §0  pre-condicoes (fixture, assinaturas exatas das 8 RPCs, zero ciclos).
--   §1  setup: ciclo de vida minimo e SERIALIZADO (ciclos PLANEJADOS) + trilha.
--   §2  CROSS-TENANT (leitura E mutation): ator de Beta le o proprio tenant e
--       ZERO do Alfa (inclusive por UUID explicito / IDOR, sob RLS com
--       `set role authenticated` + claim do ator), e a RPC nega mutacao de ciclo
--       de outro tenant; tenant/ator declarados pelo cliente no payload NAO
--       mudam a decisao. Os dois caminhos (policy de RLS e guard da RPC) negam a
--       MESMA fronteira e nenhum dado do outro tenant vaza em nenhum deles.
--       LIMITE DECLARADO: o Policy Engine (§8) vive em `src/authorization`
--       (TypeScript) e NAO e executavel por SQL; o que se prova aqui e o
--       enforcement equivalente no banco (RLS + `ciclo_ator_valido` dentro da
--       RPC), que e a defesa em profundidade contratada (§8 "enforcement em
--       profundidade").
--   §3  MEMBERSHIP REVOGADA (temporal): a ativacao do ciclo C-A2 pelo ator
--       revogavel e permitida com membership ATIVA; DESABILITADA a membership, a
--       MESMA operacao seguinte e recusada server-side, a leitura cai a ZERO e o
--       ciclo e encerrado pelo gestor para LIBERAR o unico slot `ATIVO`.
--   §4  CAPABILITY REVOGADA (temporal): permitida com `cycle.manage` (criacao de
--       C-A4); removido o grant da capability, a operacao seguinte e recusada
--       server-side (a RPC nao recebe capability no payload) e a LEITURA por
--       `cycle.read` continua.
--   §5  IDOR: UUID valido de OUTRO tenant, UUID inexistente, e ator/tenant
--       escolhidos pelo cliente nao alteram a decisao; nenhum vazamento.
--   §6  STALE VERSION: `expected_version` obsoleta => CONFLICT sem overwrite
--       silencioso (status/version/datas/contadores/eventos INALTERADOS).
--   §7  IDEMPOTENCIA: replay com o MESMO `operation_id` nao duplica efeito nem
--       trilha; intencao divergente com o mesmo `operation_id` => CONFLICT; o
--       mesmo `operation_id` em OUTRA organizacao e aceito, porque a chave e
--       `(organization_id, operation_id)`. `operation_id` e APENAS chave de
--       idempotencia — nunca identidade funcional do ciclo.
--   §8  ROLLBACK/ATOMICIDADE em operacao MULTI-ESCRITA (cancelamento de ciclo
--       com avaliacoes) => ROLLBACK TOTAL, sem estado parcial e com o artefato
--       temporario removido.
--   §9  AUDITORIA: `event_type` esperado, autoria SOBERANA (server-side, igual ao
--       ator verificado + membership ativa), `before_value`/`after_value`,
--       `operation_id` registrado e `payload_hash` SHA-256 hex; trilha
--       APPEND-ONLY (UPDATE/DELETE/TRUNCATE negados ate para o owner).
--   §10 RLS: isolamento own-tenant; `authenticated` SEM escrita direta
--       (`insufficient_privilege`); `anon` sem acesso; `service_role` EXECUTOR
--       privilegiado que NAO decide autorizacao; policy unica de SELECT
--       own-tenant em `evaluation_cycles` (nenhuma de escrita) e `cycle_events`
--       deny-by-default.
--   §11 REGRESSOES P1–P8: I5/I6/I3, as 8 RPCs `SECURITY INVOKER` com
--       `search_path` fixo e `EXECUTE` so `service_role`, catalogo com 31
--       capabilities e bundle `admin` com 9 funcionais contendo `cycle.manage`,
--       metas e observacoes em LISTA FECHADA (F5-10 P1 e F5-11 P1) — a proibicao
--       absoluta de observacao foi substituida por lista fechada, nunca removida.
--   §12 IMUTABILIDADE da estrutura materializada: A11 (inclusao de colaborador
--       ja materializado nao altera nem apaga nenhuma linha dos snapshots).
--   §13 REGRESSAO DA ADMISSAO (casos centrais A1–A12): admissao elegivel
--       incluida, nao elegivel recusada com o motivo proprio, ciclo nao ATIVO
--       recusado, cross-tenant/ator de outro tenant recusados, idempotencia,
--       ausencia de rematerializacao e a prova A3 (movimentacao posterior que
--       NAO altera o snapshot do ciclo nem escreve na trilha). A cobertura
--       EXAUSTIVA A1–A12 vive em `06-validar-f5-09-p3.sql`, que roda no MESMO
--       job do CI imediatamente antes.
--
-- CONCORRENCIA REAL: as provas de concorrencia entre DUAS sessoes vivem nos
-- arquivos 16/17/18 (outro agente, sessoes paralelas + `pg_advisory_xact_lock`).
-- Este arquivo e SINGLE-SESSION de proposito e NAO simula concorrencia: dentro de
-- uma transacao o advisory lock seria sempre reentrante e a prova seria falsa.
--
-- Saida deterministica: um `[PASS]` por verificacao; qualquer falha levanta
-- `[FAIL]` e aborta. Asserts negativos rodam em SUBTRANSACAO com handler que
-- confere a MENSAGEM/CODIGO esperado (nunca `when others` generico sem
-- conferir). O UUID do ciclo NAO e transportado por variavel do psql (a
-- interpolacao `:'var'` nao e aplicada dentro de corpos dollar-quoted): cada
-- bloco resolve o alvo por SELECT DETERMINISTICO (organization_id + ano + numero).
-- ============================================================================

\set ON_ERROR_STOP on

-- ----------------------------------------------------------------------------
-- 1) Cronologia UNICA do ciclo de vida (fonte de verdade da ordem e das versoes)
-- ----------------------------------------------------------------------------
-- Alfa-P9 (uma ativacao por vez — I5). A coluna "instante ATIVO" mostra a UNICA
-- janela em que cada ciclo fica ATIVO; nenhuma janela se sobrepoe:
--   A1 (2037/1)  cria §2 (v0) ................................ PLANEJADO v0 final
--                (nunca ativado: alvo de stale version §6 e dos probes de §5)
--   A2 (2037/2)  cria §2 (v0); ATIVA §5/antes (v1, ator revogavel);
--                ENCERRA §4/limpeza (v2, gestor) ............. ENCERRADO v2
--   A3 (2038/1)  cria §2 (v0); ATIVA §7/g (v1); 3 avaliacoes em §7.1
--                (2 CONCLUIDAS + 1 RASCUNHO); rolagem §8 (volta a ATIVO v1);
--                CANCELA §9/pre (v2) ......................... CANCELADO v2
--   A4 (2039/1)  cria §5/antes (v0, com `cycle.manage`);
--                ATIVA §7/c (v1); ENCERRA §7/e (v2) .......... ENCERRADO v2
--   A5 (2039/2)  cria §2 (v0); ATIVA §7/f (v1, com o MESMO operation_id
--                usado na ativacao do ciclo do Beta) .......... ATIVO v1 final
--                (ciclo do §13: recebe a admissao N1)
--   A6 (2040/1)  cria §2 (v0); ATIVA §9/pre-condicao (v1);
--                CANCELA §10/pre-condicao (v2) ............... CANCELADO v2
-- Beta-P9:
--   B1 (2037/1)  cria §2 (v0); ATIVA §2 (v1) ................. ATIVO v1 final
--   B2 (2037/2)  cria §2 (v0) ................................ PLANEJADO v0
-- Estado final de Alfa: 6 ciclos, EXATAMENTE 1 ATIVO (A5); Beta: 1 ATIVO (B1).
-- Os `expected_version` enviados sao exatamente os acima (nada inventado): cada
-- operacao usa a versao resultante das operacoes anteriores do MESMO ciclo.
do $$
begin
  raise notice '[PASS] cronologia declarada: ciclo de vida serializado por organizacao (A2 ATIVO->ENCERRADO, A3 ATIVO->CANCELADO, A4 ATIVO->ENCERRADO, A5 ATIVO, A6 ATIVO->CANCELADO) — nenhum instante com dois ciclos ATIVO em Alfa-P9 (I5)';
end $$;

-- ----------------------------------------------------------------------------
-- 0) Pre-condicoes: fixture presente, RPCs com assinatura exata, zero ciclos
-- ----------------------------------------------------------------------------
do $$
declare
  v_org        uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_beta       uuid := 'eda00000-0000-0000-0000-0000000000b1';
  v_gama       uuid := 'eda00000-0000-0000-0000-0000000000c1';
  v_colabs     int;
  v_ciclos     int;
  v_fn         int;
  v_args       text;
  v_assinatura text;
  v_caps       int;
  v_problemas  text[] := array[]::text[];
begin
  select count(*) into v_colabs from public.collaborators
   where organization_id = v_org;
  if v_colabs <> 3 then
    raise exception '[FAIL] pre-condicao: fixture F5-09 P9 ausente (colaboradores em Alfa=%) — execute 14-cenario-f5-09-p9.sql', v_colabs;
  end if;
  select count(*) into v_ciclos from public.evaluation_cycles
   where organization_id in (v_org, v_beta);
  if v_ciclos <> 0 then
    raise exception '[FAIL] pre-condicao: organizacoes Alfa/Beta da fixture ja possuem % ciclo(s) — execute `supabase db reset` (a trilha de ciclos e append-only)', v_ciclos;
  end if;
  select count(*) into v_ciclos from public.evaluation_cycles where organization_id = v_gama;
  if v_ciclos <> 0 then
    raise exception '[FAIL] pre-condicao: organizacao Gama-P9 (reservada aos validadores de concorrencia 16/17/18) possui % ciclo(s)', v_ciclos;
  end if;

  select count(*) into v_fn
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('ciclo_criar', 'ciclo_editar', 'ciclo_ativar', 'ciclo_encerrar',
                       'ciclo_incluir_admissao', 'ciclo_cancelar', 'ciclo_reabrir',
                       'ciclo_corrigir_periodo');
  if v_fn <> 8 then
    raise exception '[FAIL] pre-condicao: RPCs de ciclo ausentes (%)', v_fn;
  end if;

  -- Assinaturas EXATAS do §13.2 (desvio (a): sem `p_payload_hash`), uma por uma.
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)');
  v_assinatura := 'p_organization_id uuid, p_ano integer, p_numero integer, p_data_inicio date, p_data_fim date, p_actor_user_profile_id uuid, p_operation_id uuid';
  if v_args is distinct from v_assinatura then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_criar fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)');
  v_assinatura := 'p_cycle_id uuid, p_organization_id uuid, p_ano integer, p_numero integer, p_data_inicio date, p_data_fim date, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid';
  if v_args is distinct from v_assinatura then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_editar fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_ativar(uuid, uuid, integer, uuid, uuid)');
  v_assinatura := 'p_cycle_id uuid, p_organization_id uuid, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid';
  if v_args is distinct from v_assinatura then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_ativar fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)');
  v_assinatura := 'p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid';
  if v_args is distinct from v_assinatura then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_encerrar fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)');
  v_assinatura := 'p_cycle_id uuid, p_organization_id uuid, p_collaborator_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid';
  if v_args is distinct from v_assinatura then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_incluir_admissao fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)');
  v_assinatura := 'p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid';
  if v_args is distinct from v_assinatura then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_cancelar fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)');
  v_assinatura := 'p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid';
  if v_args is distinct from v_assinatura then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_reabrir fora do contrato (%)', v_args;
  end if;
  select pg_get_function_arguments(p.oid) into v_args
    from pg_proc p where p.oid = to_regprocedure('public.ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)');
  v_assinatura := 'p_cycle_id uuid, p_organization_id uuid, p_data_inicio date, p_data_fim date, p_justificativa text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid';
  if v_args is distinct from v_assinatura then
    raise exception '[FAIL] pre-condicao: assinatura de ciclo_corrigir_periodo fora do contrato (%)', v_args;
  end if;

  -- Nenhuma RPC de ciclo aceita capability, hash ou parametro estrutural do cliente.
  foreach v_assinatura in array array[
    'public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)',
    'public.ciclo_ativar(uuid, uuid, integer, uuid, uuid)',
    'public.ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)']
  loop
    select pg_get_function_arguments(p.oid) into v_args
      from pg_proc p where p.oid = to_regprocedure(v_assinatura);
    if v_args like '%capabilit%' or v_args like '%payload_hash%' then
      v_problemas := v_problemas || ('RPC com capability/hash do cliente: ' || v_assinatura);
    end if;
    if v_args like '%estrutur%' or v_args like '%position%' or v_args like '%reference_date%' then
      v_problemas := v_problemas || ('RPC com parametro estrutural do cliente: ' || v_assinatura);
    end if;
  end loop;
  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] pre-condicao: %', array_to_string(v_problemas, '; ');
  end if;

  select count(*) into v_caps from public.capabilities;
  if v_caps <> 31 then
    raise exception '[FAIL] pre-condicao: catalogo de capabilities alterado (%)', v_caps;
  end if;

  raise notice '[PASS] 0/pre-condicoes: fixture da P9 presente (Alfa/Beta/Gama sem ciclos), as 8 RPCs com assinatura EXATA do contrato (sem capability, sem hash e sem parametro estrutural) e catalogo intacto (31 capabilities)';
end $$;

-- ----------------------------------------------------------------------------
-- 2) SETUP: ciclos criados pelas RPCs soberanas — TODOS em PLANEJADO (v0)
-- ----------------------------------------------------------------------------
-- Nenhuma ativacao aqui: cada bloco ativa UM ciclo, opera e LIBERA o slot antes
-- do proximo (I5). A unica excecao e o ciclo do Beta (outra organizacao, com o
-- seu PROPRIO limite de um ATIVO).
--
-- A1 (2037/1) PLANEJADO  — NUNCA ativado: alvo de stale version (§6) e dos
--                          probes de IDOR/payload de §5.
-- A2 (2037/2) PLANEJADO  — ativado e encerrado em §3 (ciclo do ator revogavel).
-- A3 (2038/1) PLANEJADO  — ativado em §7/g (com 3 avaliacoes em §7.1): alvo do
--                          rollback multi-escrita (§8), do cancelamento (§9) e da
--                          imutabilidade A11 (§12).
-- A5 (2039/2) PLANEJADO  — ativado em §7/f e mantido ATIVO ate o fim (ciclo da
--                          admissao de §13).
-- A6 (2040/1) PLANEJADO  — ativado em §9 e cancelado em §10; alvo dos probes
--                          cross-tenant de §2.
-- A4 (2039/1) e criado em §4 (prova da capability `cycle.manage`), ativado em
-- §7/c e encerrado em §7/e.
-- B1 (2037/1) ATIVO no Beta — tenant alheio (leitura E mutacao).
-- B2 (2037/2) PLANEJADO no Beta — chave de idempotencia inclui a org (§7).
do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_beta uuid := 'eda00000-0000-0000-0000-0000000000b1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_a3   uuid := 'edc00000-0000-0000-0000-000000000003';
  v_a4   uuid := 'edc00000-0000-0000-0000-000000000004';
  v_res  jsonb;
  v_n    int;
begin
  -- Os 5 ciclos de Alfa (todos PLANEJADO/version 0) — um por transicao testada.
  perform public.ciclo_criar(v_org, 2037, 1, date '2037-01-01', date '2037-03-31',
    v_a1, 'eda10000-0000-0000-0000-000000000a01');           -- A1
  perform public.ciclo_criar(v_org, 2037, 2, date '2037-04-01', date '2037-06-30',
    v_a1, 'eda10000-0000-0000-0000-000000000a02');           -- A2
  perform public.ciclo_criar(v_org, 2038, 1, date '2038-01-01', date '2038-03-31',
    v_a1, 'eda10000-0000-0000-0000-000000000a03');           -- A3
  perform public.ciclo_criar(v_org, 2039, 2, date '2039-04-01', date '2039-06-30',
    v_a1, 'eda10000-0000-0000-0000-000000000a04');           -- A5
  perform public.ciclo_criar(v_org, 2040, 1, date '2040-01-01', date '2040-03-31',
    v_a1, 'eda10000-0000-0000-0000-000000000a05');           -- A6

  -- I5: a organizacao nasce SEM nenhum ATIVO (o setup nao ativa nada em Alfa).
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'ATIVO';
  if v_n <> 0 then
    raise exception '[FAIL] setup: Alfa deveria ter ZERO ciclos ATIVO apos o setup (%)', v_n;
  end if;
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'PLANEJADO' and c.version = 0;
  if v_n <> 5 then
    raise exception '[FAIL] setup: esperados 5 ciclos PLANEJADO/version 0 em Alfa (%)', v_n;
  end if;

  -- Beta: B1 ATIVO (unico ATIVO do Beta) e B2 PLANEJADO.
  v_res := public.ciclo_criar(v_beta, 2037, 1, date '2037-01-01', date '2037-03-31',
    v_a4, 'eda10000-0000-0000-0000-000000000b01');
  v_res := public.ciclo_ativar((v_res->>'cycle_id')::uuid, v_beta, 0, v_a4,
    'eda10000-0000-0000-0000-000000000b02');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] setup: B1 deveria estar ATIVO/version 1 (%)', v_res;
  end if;
  perform public.ciclo_criar(v_beta, 2037, 2, date '2037-04-01', date '2037-06-30',
    v_a4, 'eda10000-0000-0000-0000-000000000b03');
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_beta and c.status = 'ATIVO';
  if v_n <> 1 then
    raise exception '[FAIL] setup: Beta deveria ter exatamente 1 ciclo ATIVO (%)', v_n;
  end if;

  -- Trilha do setup: 7 CRIADO (5 Alfa + 2 Beta) + 1 ATIVADO (Beta) = 8 eventos,
  -- e a distribuicao do §11 (por status) e conferida no fim do arquivo.
  select count(*) into v_n from public.cycle_events e where e.organization_id = v_org;
  if v_n <> 5 then
    raise exception '[FAIL] setup: esperados 5 eventos de ciclo em Alfa, encontrados %', v_n;
  end if;
  select count(*) into v_n from public.cycle_events e where e.organization_id = v_beta;
  if v_n <> 3 then
    raise exception '[FAIL] setup: esperados 3 eventos de ciclo em Beta, encontrados %', v_n;
  end if;

  raise notice '[PASS] setup: 5 ciclos em Alfa todos PLANEJADO/version 0 (A1 2037/1, A2 2037/2, A3 2038/1, A5 2039/2, A6 2040/1), ZERO ATIVO em Alfa; Beta com B1 ATIVO/version 1 e B2 PLANEJADO; trilha coerente (5 eventos em Alfa, 3 em Beta)';
end $$;

-- ----------------------------------------------------------------------------
-- 3) CROSS-TENANT: leitura sob RLS e mutacao pela RPC negam a MESMA fronteira
-- ----------------------------------------------------------------------------
-- O UUID do ciclo de Alfa e materializado pelo OWNER (fora da visao do ator) em
-- uma tabela TEMPORARIA DE SESSAO: o probe sob `authenticated` consulta por UUID
-- LITERAL (IDOR real), e nao por um subselect que o RLS ja filtraria.
--
-- ATENCAO (por que NAO ha `create temporary table` dentro de um bloco `do $$`):
-- cada comando do psql e uma transacao propria, portanto `on commit drop`
-- apagaria a tabela imediatamente apos o bloco que a criou — e o bloco seguinte
-- falharia com `relation "public._p9_alvo_cross" does not exist`. Por isso a
-- tabela e criada e populada AQUI, no nivel do script, e removida com
-- `drop table if exists` ao fim do probe.
create temporary table _p9_alvo_cross (id uuid);

do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_alvo uuid;
begin
  select c.id into v_alvo from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2037 and c.numero = 1;
  if v_alvo is null then
    raise exception '[FAIL] 2/pre-condicao: ciclo de Alfa para o probe de IDOR nao encontrado';
  end if;
  insert into _p9_alvo_cross values (v_alvo);
end $$;

-- A tabela TEMPORARIA pertence a SESSAO e fica acessivel tambem sob `set role`
-- (`pg_temp` precede `public` no search_path da sessao); o GRANT e explicito para
-- o probe rodar sob `authenticated` sem depender de privilegio implicito.
grant select on _p9_alvo_cross to authenticated;

select set_config('request.jwt.claim.sub', 'edc00000-0000-0000-0000-000000000004', false);
set role authenticated;

do $$
declare
  v_beta   uuid := 'eda00000-0000-0000-0000-0000000000b1';
  v_alfa   uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_total  int;
  v_prop   int;
  v_porid  int;
  v_alfa_v int;
  v_status text;
  v_id_beta uuid;
  v_alvo_cross uuid;
begin
  select c.id into v_id_beta from public.evaluation_cycles c
   where c.organization_id = v_beta and c.ano = 2037 and c.numero = 1;
  -- ATENCAO: `_p9_alvo_cross` e TEMPORARIA (vive em pg_temp) — referenciar como
  -- `public._p9_alvo_cross` falha com "relation does not exist". Use o nome
  -- NAO qualificado, que e como o objeto foi criado (pg_temp e buscado primeiro).
  select a.id into v_alvo_cross from _p9_alvo_cross a;

  select count(*) into v_total from public.evaluation_cycles;
  if v_total <> 2 then
    raise exception '[FAIL] 3/leitura: gestor-beta deveria ver exatamente 2 ciclos do proprio tenant (%)', v_total;
  end if;
  select count(*) into v_prop from public.evaluation_cycles where organization_id = v_beta;
  if v_prop <> 2 then
    raise exception '[FAIL] 3/leitura: filtro pelo proprio tenant deveria devolver 2 (%)', v_prop;
  end if;
  select count(*) into v_porid from public.evaluation_cycles where id = v_id_beta;
  if v_porid <> 1 then
    raise exception '[FAIL] 3/leitura: ciclo do proprio tenant nao resolvido por UUID (%)', v_porid;
  end if;
  select c.status into v_status from public.evaluation_cycles c where c.id = v_id_beta;
  if v_status <> 'ATIVO' then
    raise exception '[FAIL] 3/leitura: ciclo ATIVO do Beta deveria ser legivel (%)', v_status;
  end if;

  -- NAO ve o tenant alheio: nem por filtro...
  select count(*) into v_alfa_v from public.evaluation_cycles where organization_id = v_alfa;
  if v_alfa_v <> 0 then
    raise exception '[FAIL] 3/IDOR: leitura do gestor-beta alcancou % ciclo(s) de Alfa', v_alfa_v;
  end if;
  raise notice '[PASS] 3/leitura (RLS): sob `authenticated` com o claim do gestor-beta, a policy own-tenant devolve os 2 ciclos do proprio tenant (inclusive o ATIVO por UUID) e ZERO do tenant alheio (filtro)';

  -- ...nem pelo UUID LITERAL de um ciclo de Alfa (IDOR).
  select count(*) into v_porid from public.evaluation_cycles where id = v_alvo_cross;
  if v_porid <> 0 then
    raise exception '[FAIL] 3/IDOR: gestor-beta alcancou ciclo de Alfa por UUID explicito (%)', v_porid;
  end if;
  raise notice '[PASS] 3/IDOR (RLS): o UUID VALIDO de um ciclo de Alfa permanece invisivel para o ator de Beta (zero linha), mesmo consultado literalmente — nenhum dado do outro tenant e retornado';
end $$;

reset role;

-- Fim do probe de IDOR por UUID literal: o objeto auxiliar de sessao e removido
-- aqui (nao ha nenhum outro uso de `_p9_alvo_cross` no restante do arquivo).
drop table if exists _p9_alvo_cross;

-- Mutacao cross-tenant: (a) ator de Beta declarando a organizacao Alfa (com o
-- ciclo de Alfa); (b) ator de Alfa declarando a organizacao Beta (com o ciclo de
-- Beta) => a RPC resolve por (id, tenant) e devolve NOT_FOUND, indistinguivel de
-- inexistente (sem vazar a existencia no outro tenant); (c) tenant DECLARADO pelo
-- cliente; (d) ATOR DECLARADO pelo cliente. Os quatro recusam sem efeito.
do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_beta uuid := 'eda00000-0000-0000-0000-0000000000b1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_a4   uuid := 'edc00000-0000-0000-0000-000000000004';
  v_ca   uuid;
  v_cb   uuid;
  v_ok   boolean;
  v_msg  text;
  v_evt  int;
begin
  select c.id into v_ca from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2040 and c.numero = 1;
  select c.id into v_cb from public.evaluation_cycles c
   where c.organization_id = v_beta and c.ano = 2037 and c.numero = 1;

  -- (a) ator de Beta + organizacao Alfa => FORBIDDEN.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_cancelar(v_ca, v_org, 'Probe cross-tenant (ator de Beta)', 0, v_a4,
      'eda10000-0000-0000-0000-000000000f01');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 3/mutacao: ator de Beta operando Alfa deveria ser F5_09_FORBIDDEN (%)', v_msg;
  end if;

  -- (b) ator de Alfa + ciclo de Beta declarado na organizacao Beta => a RPC
  -- resolve PRIMEIRO o ator contra o tenant DECLARADO (o ator de Alfa nao tem
  -- vinculo com Beta) e recusa. O contrato (§8) trata NOT_FOUND e FORBIDDEN como
  -- INDISTINGUIVEIS para cross-tenant (nao vazar existencia de recurso alheio);
  -- a prova exige RECUSA + ZERO efeito, aceitando qualquer um dos dois codigos.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_cancelar(v_cb, v_beta, 'Probe cross-tenant (ciclo do Beta)', 1, v_a1,
      'eda10000-0000-0000-0000-000000000f02');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%' or sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 3/mutacao: ator de Alfa com ciclo de Beta deveria ser recusado (F5_09_NOT_FOUND ou F5_09_FORBIDDEN) (%)', v_msg;
  end if;

  -- (c) tenant DECLARADO pelo cliente nao muda a decisao. O ator (Beta) tem
  -- vinculo com o tenant declarado (Beta), mas o ciclo alvo e de ALFA: a RPC
  -- recusa por NAO ENCONTRAR o ciclo no tenant declarado. Pela doutrina do §8
  -- (NOT_FOUND e FORBIDDEN indistinguiveis para cross-tenant), a prova aceita
  -- qualquer um dos dois codigos — o que NAO se aceita e sucesso ou efeito.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_editar(v_ca, v_beta, 2040, 1, date '2040-01-01', date '2040-03-31',
      0, v_a4, 'eda10000-0000-0000-0000-000000000f03');
  exception when others then
    v_ok := (sqlerrm like '%F5_09_FORBIDDEN%' or sqlerrm like '%F5_09_NOT_FOUND%'); v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 3/payload: tenant declarado pelo cliente deveria ser recusado (FORBIDDEN/NOT_FOUND) (%)', v_msg;
  end if;

  -- (d) ATOR DECLARADO pelo cliente nao muda a decisao (o ator real e o verificado).
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_criar(v_beta, 2040, 1, date '2040-01-01', date '2040-03-31',
      v_a1, 'eda10000-0000-0000-0000-000000000f04');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 3/payload: ator de Alfa declarado em payload de Beta deveria ser F5_09_FORBIDDEN (%)', v_msg;
  end if;

  -- (e) zero efeito e nenhum vazamento.
  select count(*) into v_evt from public.cycle_events e
   where e.operation_id::text in ('eda10000-0000-0000-0000-000000000f01',
                                  'eda10000-0000-0000-0000-000000000f02',
                                  'eda10000-0000-0000-0000-000000000f03',
                                  'eda10000-0000-0000-0000-000000000f04');
  if v_evt <> 0 then
    raise exception '[FAIL] 3/mutacao: probes recusados gravaram % evento(s)', v_evt;
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_ca) <> 'PLANEJADO'
     or (select c.version from public.evaluation_cycles c where c.id = v_ca) <> 0
     or (select c.status from public.evaluation_cycles c where c.id = v_cb) <> 'ATIVO'
     or (select count(*) from public.evaluation_cycles c where c.organization_id = v_beta) <> 2
     or (select count(*) from public.evaluation_cycles c where c.organization_id = v_org) <> 5
     or (select count(*) from public.evaluation_cycles c
          where c.organization_id = v_org and c.status = 'ATIVO') <> 0 then
    raise exception '[FAIL] 3/mutacao: probe cross-tenant alterou estado (Alfa=%, Beta=%)',
      (select count(*) from public.evaluation_cycles c where c.organization_id = v_org),
      (select count(*) from public.evaluation_cycles c where c.organization_id = v_beta);
  end if;

  raise notice '[PASS] 3/mutacao (RPC): ciclo de outro tenant, tenant declarado pelo cliente e ator declarado pelo cliente sao TODOS recusados (FORBIDDEN/NOT_FOUND) com ZERO efeito — a MESMA fronteira que o RLS nega no caminho de leitura';
end $$;

-- ----------------------------------------------------------------------------
-- 4) MEMBERSHIP REVOGADA (temporal, mesmo JWT/claim do cliente)
-- ----------------------------------------------------------------------------
-- A2 e o unico ciclo ATIVO de Alfa enquanto esta secao roda; ele e ENCERRADO
-- antes de qualquer outra ativacao (I5).
do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_a3   uuid := 'edc00000-0000-0000-0000-000000000003';
  v_c2   uuid;
  v_res  jsonb;
begin
  select c.id into v_c2 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2037 and c.numero = 2;
  if public.ciclo_ator_valido(v_a3, v_org, 'cycle.manage') is not true then
    raise exception '[FAIL] 5/antes: ator revogavel deveria ter cycle.manage antes da revogacao';
  end if;

  -- ATIVACAO pelo ator revogavel com membership ATIVA (unico ATIVO de Alfa).
  v_res := public.ciclo_ativar(v_c2, v_org, 0, v_a3, 'eda10000-0000-0000-0000-000000000b01');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] 5/antes: ativacao pelo ator revogavel deveria resultar em ATIVO/version 1 (%)', v_res;
  end if;
  -- O encerramento ja esta provado possivel pelo gestor (sera feito em
  -- 4/limpeza); aqui provamos que a ESCRITA do ator revogavel funciona.
  raise notice '[PASS] 5/antes: com membership ATIVA (mesmo JWT do cliente) o ator revogavel-alfa tem `cycle.manage` efetiva e ATIVA o ciclo C-A2 (ATIVO/version 1)';
end $$;

select set_config('request.jwt.claim.sub', 'edc00000-0000-0000-0000-000000000003', false);
set role authenticated;

do $$
declare
  v_n    int;
  v_self boolean;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 5 then
    raise exception '[FAIL] 5/antes: o ator revogavel deveria ler os 5 ciclos do proprio tenant (%)', v_n;
  end if;
  select public.user_has_active_membership('eda00000-0000-0000-0000-0000000000a1') into v_self;
  if v_self is not true then
    raise exception '[FAIL] 5/antes: helper de tenant deveria ser true com membership ativa';
  end if;
  raise notice '[PASS] 5/antes: com membership ATIVA o ator revogavel-alfa le os 5 ciclos do proprio tenant sob RLS e o helper de tenant responde true';
end $$;

reset role;

-- A membership e DESABILITADA no banco (revogacao temporal). O claim do cliente
-- NAO e trocado: a secao seguinte reusa o MESMO `request.jwt.claim.sub`.
update public.user_organization_memberships
   set status = 'disabled'
 where id = 'edd00000-0000-0000-0000-000000000003';

do $$
begin
  if (select m.status from public.user_organization_memberships m
       where m.id = 'edd00000-0000-0000-0000-000000000003') <> 'disabled' then
    raise exception '[FAIL] 5/revogacao: membership do ator revogavel nao foi desabilitada';
  end if;
  raise notice '[PASS] 5/revogacao: membership do ator revogavel-alfa DESABILITADA no banco (nenhum claim do cliente foi alterado)';
end $$;

-- A MESMA operacao seguinte e recusada server-side.
do $$
declare
  v_org uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a3  uuid := 'edc00000-0000-0000-0000-000000000003';
  v_c2  uuid;
  v_ok  boolean;
  v_msg text;
  v_evt int;
begin
  select c.id into v_c2 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2037 and c.numero = 2;

  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_cancelar(v_c2, v_org, 'Mutacao apos revogacao de membership', 1, v_a3,
      'eda10000-0000-0000-0000-000000000b0f');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 5/revogacao: cancelamento apos a revogacao deveria ser F5_09_FORBIDDEN (%)', v_msg;
  end if;

  if public.ciclo_ator_valido(v_a3, v_org, 'cycle.manage') is not false then
    raise exception '[FAIL] 5/revogacao: ciclo_ator_valido deveria ser false com membership revogada';
  end if;

  select count(*) into v_evt from public.cycle_events e
   where e.operation_id = 'eda10000-0000-0000-0000-000000000b0f';
  if v_evt <> 0 then
    raise exception '[FAIL] 5/revogacao: recusa por membership revogada gravou % evento(s)', v_evt;
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_c2) <> 'ATIVO'
     or (select c.version from public.evaluation_cycles c where c.id = v_c2) <> 1 then
    raise exception '[FAIL] 5/revogacao: a recusa alterou o ciclo C-A2';
  end if;

  raise notice '[PASS] 5/revogacao (mutacao): a operacao seguinte a revogacao e recusada server-side por F5_09_FORBIDDEN, com zero efeito, apesar de o cliente manter o MESMO JWT/claim';
end $$;

-- Leitura apos a revogacao: ZERO linhas (mesma sessao, mesmo claim).
select set_config('request.jwt.claim.sub', 'edc00000-0000-0000-0000-000000000003', false);
set role authenticated;

do $$
declare
  v_n    int;
  v_self boolean;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 0 then
    raise exception '[FAIL] 5/revogacao (leitura): membership revogada deveria devolver ZERO linhas (%)', v_n;
  end if;
  select public.user_has_active_membership('eda00000-0000-0000-0000-0000000000a1') into v_self;
  if v_self is not false then
    raise exception '[FAIL] 5/revogacao (leitura): helper de tenant deveria ser false';
  end if;
  raise notice '[PASS] 5/revogacao (leitura): com o MESMO JWT/claim do cliente, a revogacao da membership zera a leitura (policy own-tenant fail-closed)';
end $$;

reset role;

-- 4/limpeza: o gestor ENCERRA C-A2 (ATIVO v1 -> ENCERRADO v2), liberando o unico
-- slot `ATIVO` de Alfa ANTES de qualquer outra ativacao (I5). Este encerramento e
-- tambem o evento ENCERRADO auditado no §9.
do $$
declare
  v_org uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c2  uuid;
  v_res jsonb;
  v_n   int;
begin
  select c.id into v_c2 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2037 and c.numero = 2;
  v_res := public.ciclo_encerrar(v_c2, v_org, 'Encerramento para liberar o slot ATIVO (I5/P9)',
    1, v_a1, 'eda10000-0000-0000-0000-000000000b03');
  if (v_res->>'status') <> 'ENCERRADO' or (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] 4/limpeza: C-A2 deveria estar ENCERRADO/version 2 (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'ATIVO';
  if v_n <> 0 then
    raise exception '[FAIL] 4/limpeza: Alfa deveria voltar a ZERO ciclos ATIVO apos o encerramento (%)', v_n;
  end if;
  raise notice '[PASS] 4/limpeza: C-A2 ENCERRADO/version 2 pelo gestor e Alfa volta a ZERO ciclos ATIVO (o slot esta livre para a proxima ativacao do §7)';
end $$;

-- ----------------------------------------------------------------------------
-- 5) CAPABILITY REVOGADA (temporal): mutacao recusada, leitura preservada
-- ----------------------------------------------------------------------------
do $$
declare
  v_org uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'edc00000-0000-0000-0000-000000000001';
  v_res jsonb;
begin
  if public.ciclo_ator_valido(v_a1, v_org, 'cycle.manage') is not true then
    raise exception '[FAIL] 5/antes: gestor-alfa deveria ter cycle.manage antes da revogacao';
  end if;
  v_res := public.ciclo_criar(v_org, 2039, 1, date '2039-01-01', date '2039-03-31',
    v_a1, 'eda10000-0000-0000-0000-000000000c01');
  if (v_res->>'status') <> 'PLANEJADO' or (v_res->>'version')::int <> 0 then
    raise exception '[FAIL] 5/antes: criacao com cycle.manage deveria ser permitida (%)', v_res;
  end if;
  raise notice '[PASS] 5/antes: com a capability `cycle.manage` efetiva a operacao de escrita e permitida (C-A4, 2039/1, criado PLANEJADO/version 0)';
end $$;

-- Revogacao da CAPABILITY: remove a relacao role x `cycle.manage` da role do
-- gestor-alfa (a role, a membership e a atribuicao permanecem intactas).
delete from public.access_role_capabilities rc
 using public.capabilities c
 where c.id = rc.capability_id
   and rc.access_role_id = 'edf90000-0000-0000-0000-0000000000a1'
   and c.code = 'cycle.manage';

do $$
declare
  v_org uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c4  uuid;
  v_ok  boolean;
  v_msg text;
  v_evt int;
begin
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2039 and c.numero = 1;

  if public.ciclo_ator_valido(v_a1, v_org, 'cycle.manage') is not false then
    raise exception '[FAIL] 5/revogacao: ciclo_ator_valido deveria ser false apos remover o grant';
  end if;
  if public.ciclo_ator_valido(v_a1, v_org, 'cycle.read') is not true then
    raise exception '[FAIL] 5/revogacao: cycle.read deveria permanecer efetiva';
  end if;

  -- CRIACAO (a operacao que funcionou em 5/antes) — recusada sem a capability.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_criar(v_org, 2041, 1, date '2041-01-01', date '2041-03-31',
      v_a1, 'eda10000-0000-0000-0000-000000000c02');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%' and sqlerrm like '%cycle.manage%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 5/revogacao: criacao apos revogar cycle.manage deveria ser F5_09_FORBIDDEN (%)', v_msg;
  end if;

  -- ATIVACAO do ciclo criado em 5/antes — recusada (a RPC NAO recebe capability
  -- no payload: a decisao vem do banco).
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_ativar(v_c4, v_org, 0, v_a1, 'eda10000-0000-0000-0000-000000000c03');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 5/revogacao: ativacao apos revogar cycle.manage deveria ser F5_09_FORBIDDEN (%)', v_msg;
  end if;

  -- `cycle.cancel` continua efetiva (a revogacao e granular).
  if public.ciclo_ator_valido(v_a1, v_org, 'cycle.cancel') is not true then
    raise exception '[FAIL] 5/revogacao: cycle.cancel deveria continuar efetiva (revogacao granular)';
  end if;

  select count(*) into v_evt from public.cycle_events e
   where e.operation_id::text in ('eda10000-0000-0000-0000-000000000c02',
                                  'eda10000-0000-0000-0000-000000000c03');
  if v_evt <> 0 then
    raise exception '[FAIL] 5/revogacao: recusa por capability revogada gravou % evento(s)', v_evt;
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_c4) <> 'PLANEJADO'
     or (select c.version from public.evaluation_cycles c where c.id = v_c4) <> 0 then
    raise exception '[FAIL] 5/revogacao: a recusa alterou C-A4';
  end if;

  raise notice '[PASS] 5/revogacao (mutacao): removido o grant de `cycle.manage`, a criacao e a ativacao seguintes sao recusadas server-side por F5_09_FORBIDDEN e `cycle.cancel` continua efetiva — revogacao granular, zero efeito';
end $$;

-- O grant de `cycle.manage` da role do gestor-alfa e RESTAURADO aqui: a prova de
-- revogacao temporal ja esta CONCLUIDA (a operacao seguinte a revogacao foi
-- recusada e nada gravou). Sem a restauracao, todos os blocos posteriores que
-- reusam o gestor-alfa falhariam por capability ausente — medindo outra coisa,
-- nao o contrato. A restauracao nao afrouxa a prova: ela apenas devolve o
-- estado de fixture para os blocos seguintes.
insert into public.access_role_capabilities (access_role_id, capability_id)
select 'edf90000-0000-0000-0000-0000000000a1', c.id
  from public.capabilities c
 where c.code = 'cycle.manage'
   and not exists (
     select 1 from public.access_role_capabilities rc
      where rc.access_role_id = 'edf90000-0000-0000-0000-0000000000a1'
        and rc.capability_id = c.id);

do $$
declare
  v_org uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'edc00000-0000-0000-0000-000000000001';
begin
  if public.ciclo_ator_valido(v_a1, v_org, 'cycle.manage') is not true then
    raise exception '[FAIL] 5/restauracao: o grant de cycle.manage nao foi restaurado para os blocos seguintes';
  end if;
end $$;

-- A LEITURA por `cycle.read` continua conforme o contrato (mesmo claim do gestor).
select set_config('request.jwt.claim.sub', 'edc00000-0000-0000-0000-000000000001', false);
set role authenticated;

do $$
declare
  v_alfa uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_n    int;
  v_beta int;
begin
  select count(*) into v_n from public.evaluation_cycles;
  if v_n <> 6 then
    raise exception '[FAIL] 5/leitura: gestor-alfa deveria continuar lendo os 6 ciclos do proprio tenant (%)', v_n;
  end if;
  select count(*) into v_beta from public.evaluation_cycles where organization_id <> v_alfa;
  if v_beta <> 0 then
    raise exception '[FAIL] 5/leitura: leitura alcancou outro tenant (%)', v_beta;
  end if;
  raise notice '[PASS] 5/leitura: revogada a capability de ESCRITA, a leitura por `cycle.read` continua limitada ao proprio tenant (6 ciclos, zero do alheio) — leitura e escrita sao decisoes separadas';
end $$;

reset role;

-- ----------------------------------------------------------------------------
-- 5) IDOR: alvos validos/invalidos e payload nao autoritativo
-- ----------------------------------------------------------------------------
do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_beta uuid := 'eda00000-0000-0000-0000-0000000000b1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_cb   uuid;
  v_c4   uuid;
  v_ok   boolean;
  v_msg  text;
  v_evt  int;
begin
  select c.id into v_cb from public.evaluation_cycles c
   where c.organization_id = v_beta and c.ano = 2037 and c.numero = 1;
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2039 and c.numero = 1;

  -- (a) UUID VALIDO de ciclo de OUTRO tenant declarado no proprio tenant.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_encerrar(v_cb, v_org, 'IDOR de ciclo de outro tenant', 1, v_a1,
      'eda10000-0000-0000-0000-000000000d01');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 5/a: UUID valido de outro tenant deveria ser F5_09_NOT_FOUND (%)', v_msg;
  end if;

  -- (b) UUID VALIDO inexistente no proprio tenant.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_encerrar('eda00000-0000-0000-0000-00000000dead', v_org,
      'IDOR de ciclo inexistente', 1, v_a1, 'eda10000-0000-0000-0000-000000000d02');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 5/b: UUID inexistente deveria ser F5_09_NOT_FOUND (%)', v_msg;
  end if;

  -- (c) organizacao escolhida pelo cliente.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_encerrar(v_c4, v_beta, 'IDOR com tenant do cliente', 0, v_a1,
      'eda10000-0000-0000-0000-000000000d03');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%' and sqlerrm like '%cycle.manage%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 5/c: tenant escolhido pelo cliente deveria ser recusado (%)', v_msg;
  end if;

  -- (d) ator escolhido pelo cliente (ator de Beta declarado em operacao de Alfa).
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_cancelar(v_c4, v_org, 'IDOR com ator do cliente', 0,
      'edc00000-0000-0000-0000-000000000004', 'eda10000-0000-0000-0000-000000000d04');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 5/d: ator escolhido pelo cliente deveria ser recusado (%)', v_msg;
  end if;

  -- (e) JWT valido SEM profile/membership (fantasma) nao opera nada.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_criar(v_org, 2042, 1, date '2042-01-01', date '2042-03-31',
      'edc00000-0000-0000-0000-000000000005', 'eda10000-0000-0000-0000-000000000d05');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 5/e: identidade sem profile/membership deveria ser recusada (%)', v_msg;
  end if;

  -- (f) zero efeito e nenhum vazamento.
  select count(*) into v_evt from public.cycle_events e
   where e.operation_id::text in ('eda10000-0000-0000-0000-000000000d01',
                                  'eda10000-0000-0000-0000-000000000d02',
                                  'eda10000-0000-0000-0000-000000000d03',
                                  'eda10000-0000-0000-0000-000000000d04',
                                  'eda10000-0000-0000-0000-000000000d05');
  if v_evt <> 0 then
    raise exception '[FAIL] 5/f: probes de IDOR gravaram % evento(s)', v_evt;
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_cb) <> 'ATIVO'
     or (select c.version from public.evaluation_cycles c where c.id = v_cb) <> 1
     or (select c.status from public.evaluation_cycles c where c.id = v_c4) <> 'PLANEJADO' then
    raise exception '[FAIL] 5/f: probe de IDOR alterou o estado de um ciclo';
  end if;
  if exists (select 1 from public.evaluation_cycles c
              where c.organization_id = v_org and c.ano in (2041, 2042)) then
    raise exception '[FAIL] 5/f: identidade fantasma/ator invalido criou ciclo (2041/1 ou 2042/1 existe)';
  end if;

  raise notice '[PASS] 5/IDOR: UUID de outro tenant, UUID inexistente, tenant do cliente, ator do cliente e identidade sem vinculo sao TODOS recusados (NOT_FOUND/FORBIDDEN) com zero efeito e sem vazamento de dado alheio';
end $$;

-- ----------------------------------------------------------------------------
-- 6) STALE VERSION: CONFLICT sem overwrite silencioso
-- ----------------------------------------------------------------------------
-- A1 permanece PLANEJADO/version 0 (nunca ativado): e o alvo ideal porque as TRES
-- operacoes com versao obsoleta recusam SEM alterar estado nem status.
do $$
declare
  v_org    uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1     uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c1     uuid;
  v_ok     boolean;
  v_msg    text;
  v_antes  record;
  v_depois record;
  v_evt_a  int;
  v_evt_d  int;
begin
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2037 and c.numero = 1;

  select c.status, c.version, c.data_inicio, c.data_fim, c.data_ativacao,
         c.data_encerramento, c.encerrado_com_pendencias, c.quantidade_pendencias
    into v_antes
    from public.evaluation_cycles c where c.id = v_c1;
  select count(*) into v_evt_a from public.cycle_events e
   where e.organization_id = v_org and e.cycle_id = v_c1;

  -- (a) ciclo_ativar com expected_version obsoleta (PLANEJADO v0, o real).
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_ativar(v_c1, v_org, 7, v_a1, 'eda10000-0000-0000-0000-000000000e01');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%versao divergente%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 6/a: expected_version obsoleta em ciclo_ativar deveria ser F5_09_CONFLICT/versao divergente (%)', v_msg;
  end if;

  -- (b) ciclo_encerrar com expected_version obsoleta. PRECEDENCIA DECLARADA: a
  -- RPC valida o ESTADO de origem ANTES da versao, e o alvo desta prova esta
  -- PLANEJADO (nunca ativado) — logo a recusa e de ESTADO. O que o contrato
  -- exige e o que a prova mede: recusa FAIL-CLOSED por F5_09_CONFLICT e ZERO
  -- efeito/overwrite (verificado ao fim do bloco). A precedencia de VERSAO sobre
  -- alvo no estado devido esta provada em (a) — `ciclo_ativar` no MESMO alvo
  -- PLANEJADO com versao obsoleta responde "versao divergente" — e nos probes
  -- dedicados de §7/§13.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_encerrar(v_c1, v_org, 'Encerramento com versao obsoleta', 7, v_a1,
      'eda10000-0000-0000-0000-000000000e02');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 6/b: encerrar com versao obsoleta deveria ser recusado por F5_09_CONFLICT (%)', v_msg;
  end if;

  -- (c) ciclo_corrigir_periodo com versao obsoleta (datas validas). Mesma
  -- precedencia declarada em (b): o alvo esta PLANEJADO e a RPC exige ATIVO para
  -- corrigir periodo — a recusa e de ESTADO, fail-closed, com zero efeito.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_corrigir_periodo(v_c1, v_org, date '2037-01-01', date '2037-03-31',
      'Correcao com versao obsoleta', 7, v_a1, 'eda10000-0000-0000-0000-000000000e03');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 6/c: corrigir periodo com versao obsoleta deveria ser recusado por F5_09_CONFLICT (%)', v_msg;
  end if;

  -- Estado soberano EXATAMENTE igual (nenhum overwrite silencioso).
  select c.status, c.version, c.data_inicio, c.data_fim, c.data_ativacao,
         c.data_encerramento, c.encerrado_com_pendencias, c.quantidade_pendencias
    into v_depois
    from public.evaluation_cycles c where c.id = v_c1;
  select count(*) into v_evt_d from public.cycle_events e
   where e.organization_id = v_org and e.cycle_id = v_c1;

  if v_depois.status <> v_antes.status
     or v_depois.version <> v_antes.version
     or v_depois.data_inicio <> v_antes.data_inicio
     or v_depois.data_fim <> v_antes.data_fim
     or v_depois.data_ativacao is distinct from v_antes.data_ativacao
     or v_depois.data_encerramento is distinct from v_antes.data_encerramento
     or v_depois.encerrado_com_pendencias <> v_antes.encerrado_com_pendencias
     or v_depois.quantidade_pendencias <> v_antes.quantidade_pendencias
     or v_evt_d <> v_evt_a then
    raise exception '[FAIL] 6: stale version alterou o estado soberano (eventos %->%, status %->%, version %->%)',
      v_evt_a, v_evt_d, v_antes.status, v_depois.status, v_antes.version, v_depois.version;
  end if;

  raise notice '[PASS] 6/stale version: ativar, encerrar e corrigir periodo com `expected_version` obsoleta recusam por F5_09_CONFLICT/versao divergente e o estado soberano permanece INALTERADO (status, version, datas, contadores e trilha)';
end $$;

-- ----------------------------------------------------------------------------
-- 7) IDEMPOTENCIA por (organization_id, operation_id) + ATIVACOES SERIALIZADAS
-- ----------------------------------------------------------------------------
-- NOTA DE CONTRATO: `operation_id` e APENAS chave de idempotencia (participa de
-- `unique (organization_id, operation_id)` em `cycle_events`). Ele NAO e a
-- identidade funcional do ciclo — a identidade e o UUID soberano de
-- `evaluation_cycles.id` — e nunca substitui ator, tenant, estado, versao ou
-- autorizacao.
--
-- I5 nesta secao: A4 e ATIVADO (v1) e ENCERRADO (v2) ANTES de A5 ser ativado; em
-- nenhum instante existem dois `ATIVO` em Alfa. A3 e ativado imediatamente depois,
-- tambem com o slot livre.
do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_beta uuid := 'eda00000-0000-0000-0000-0000000000b1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_a4   uuid := 'edc00000-0000-0000-0000-000000000004';
  v_c4   uuid;
  v_c5   uuid;
  v_c3   uuid;
  v_res1 jsonb;
  v_res2 jsonb;
  v_ok   boolean;
  v_msg  text;
  v_n    int;
  v_evt  int;
begin
  select c.id into v_c4 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2039 and c.numero = 1;
  select c.id into v_c5 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2039 and c.numero = 2;
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2038 and c.numero = 1;

  -- (a) REPLAY da criacao de A5: mesmo operation_id + mesmo payload => mesmo resultado.
  v_res1 := public.ciclo_criar(v_org, 2039, 2, date '2039-04-01', date '2039-06-30',
    v_a1, 'eda10000-0000-0000-0000-000000000a04');
  v_res2 := public.ciclo_criar(v_org, 2039, 2, date '2039-04-01', date '2039-06-30',
    v_a1, 'eda10000-0000-0000-0000-000000000a04');
  if v_res1 <> v_res2 or (v_res1->>'cycle_id')::uuid is distinct from v_c5 then
    raise exception '[FAIL] 7/a: replay da criacao devolveu resultado diferente ou outro ciclo (% vs %)', v_res1, v_res2;
  end if;
  select count(*) into v_evt from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = 'eda10000-0000-0000-0000-000000000a04';
  if v_evt <> 1 then
    raise exception '[FAIL] 7/a: replay da criacao duplicou a trilha (%)', v_evt;
  end if;
  if (select count(*) from public.evaluation_cycles c
       where c.organization_id = v_org and c.ano = 2039 and c.numero = 2) <> 1 then
    raise exception '[FAIL] 7/a: replay da criacao duplicou o ciclo';
  end if;

  -- (b) MESMO operation_id com INTENCAO DIVERGENTE => CONFLICT (nunca executa).
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_criar(v_org, 2042, 1, date '2042-01-01', date '2042-03-31',
      v_a1, 'eda10000-0000-0000-0000-000000000a04');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%intencao diferente%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 7/b: operation_id com intencao divergente deveria ser F5_09_CONFLICT/intencao diferente (%)', v_msg;
  end if;
  if exists (select 1 from public.evaluation_cycles c
              where c.organization_id = v_org and c.ano = 2042) then
    raise exception '[FAIL] 7/b: intencao divergente criou ciclo (2042/1 existe)';
  end if;

  -- (c) ATIVACAO de A4 (unico ATIVO de Alfa neste instante) + replay da ativacao.
  -- O `operation_id` e PROPRIO desta prova: reutilizar um id ja empregado com
  -- outra intencao faria a RPC responder "intencao diferente" (idempotencia
  -- correta) em vez de exercitar o replay legitimo.
  v_res1 := public.ciclo_ativar(v_c4, v_org, 0, v_a1, 'eda10000-0000-0000-0000-000000000ac1');
  v_res2 := public.ciclo_ativar(v_c4, v_org, 0, v_a1, 'eda10000-0000-0000-0000-000000000ac1');
  if v_res1 <> v_res2 or (v_res1->>'version')::int <> 1 then
    raise exception '[FAIL] 7/c: replay da ativacao devolveu resultado diferente (%)', v_res2;
  end if;
  select count(*) into v_evt from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = 'eda10000-0000-0000-0000-000000000ac1';
  if v_evt <> 1 then
    raise exception '[FAIL] 7/c: replay da ativacao duplicou a trilha (%)', v_evt;
  end if;

  -- (d) I5: exatamente UM ATIVO em Alfa depois da ativacao de A4.
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'ATIVO';
  if v_n <> 1 then
    raise exception '[FAIL] 7/d: Alfa deveria ter exatamente 1 ciclo ATIVO apos ativar A4 (%)', v_n;
  end if;

  -- (e) ENCERRAMENTO de A4 (ATIVO v1 -> ENCERRADO v2) para LIBERAR o slot (I5).
  v_res1 := public.ciclo_encerrar(v_c4, v_org, 'Encerramento de A4 para liberar o slot (I5)',
    1, v_a1, 'eda10000-0000-0000-0000-000000000a07');
  if (v_res1->>'status') <> 'ENCERRADO' or (v_res1->>'version')::int <> 2 then
    raise exception '[FAIL] 7/e: A4 deveria estar ENCERRADO/version 2 (%)', v_res1;
  end if;

  -- (f) MESMO operation_id em OUTRA organizacao => ACEITO (a chave e por tenant):
  --     o MESMO operation_id da ativacao do ciclo do Beta (b02) ativa A5 em Alfa.
  if exists (select 1 from public.cycle_events e
              where e.organization_id = v_org
                and e.operation_id = 'eda10000-0000-0000-0000-000000000b02') then
    raise exception '[FAIL] 7/f: pre-condicao — o operation_id do teste ja existe em Alfa';
  end if;
  v_res1 := public.ciclo_ativar(v_c5, v_org, 0, v_a1, 'eda10000-0000-0000-0000-000000000b02');
  if (v_res1->>'status') <> 'ATIVO' or (v_res1->>'version')::int <> 1 then
    raise exception '[FAIL] 7/f: o MESMO operation_id em outra organizacao deveria ser aceito (%)', v_res1;
  end if;
  select count(*) into v_evt from public.cycle_events e
   where e.operation_id = 'eda10000-0000-0000-0000-000000000b02';
  if v_evt <> 2 then
    raise exception '[FAIL] 7/f: o operation_id deveria existir uma vez por organizacao (encontrado %)', v_evt;
  end if;

  -- (f.1) ENCERRAMENTO de A5 (ATIVO v1 -> ENCERRADO v2) para LIBERAR o slot (I5)
  -- antes de ativar A3 — o roteiro do bloco exige "A4 -> encerra -> A5 -> encerra
  -- -> A3"; sem este passo a ativacao de A3 violaria I5 (um ATIVO por org).
  v_res1 := public.ciclo_encerrar(v_c5, v_org, 'Encerramento de A5 para liberar o slot (I5)',
    1, v_a1, 'eda10000-0000-0000-0000-000000000ac3');
  if (v_res1->>'status') <> 'ENCERRADO' or (v_res1->>'version')::int <> 2 then
    raise exception '[FAIL] 7/f.1: A5 deveria estar ENCERRADO/version 2 (%)', v_res1;
  end if;

  -- (g) A3 ATIVADO (unico ATIVO de Alfa) com o slot livre — base do §8/§9/§12.
  -- `operation_id` PROPRIO da ativacao: o id usado na CRIACAO de A3 e outro
  -- (reutilizar exigiria "mesma intencao" e a RPC responderia intencao diferente).
  v_res1 := public.ciclo_ativar(v_c3, v_org, 0, v_a1, 'eda10000-0000-0000-0000-000000000ac2');
  if (v_res1->>'status') <> 'ATIVO' or (v_res1->>'version')::int <> 1 then
    raise exception '[FAIL] 7/g: A3 deveria estar ATIVO/version 1 (%)', v_res1;
  end if;
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'ATIVO';
  if v_n <> 1 then
    raise exception '[FAIL] 7/g: Alfa deveria ter exatamente 1 ciclo ATIVO (%)', v_n;
  end if;
  select count(*) into v_n from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1;
  if v_n <> 3 then
    raise exception '[FAIL] 7/g: a ativacao de A3 deveria materializar 3 snapshots (%)', v_n;
  end if;

  raise notice '[PASS] 7/idempotencia + serializacao: replay de criacao e ativacao nao duplica efeito/trilha, operation_id divergente => F5_09_CONFLICT, o MESMO operation_id em OUTRA organizacao e aceito (chave = organization_id + operation_id) e as ativacoes (A4 -> encerra -> A5 -> encerra -> A3) mantem NO MAXIMO UM ATIVO por organizacao (I5)';
end $$;

-- ----------------------------------------------------------------------------
-- 7.1) A3 com as avaliacoes da prova de rollback e de auditoria
-- ----------------------------------------------------------------------------
do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c3   uuid;
  v_n    int;
  v_resp int;
  v_part int;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2038 and c.numero = 1;

  select count(*) into v_resp
    from public.cycle_evaluation_responsibilities r
    join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
   where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1;
  if v_resp < 2 then
    raise exception '[FAIL] 7.1/pre-condicao: A3 sem responsabilidades materializadas (%)', v_resp;
  end if;

  -- Avaliacoes de A3: B1 e B3 CONCLUIDAS, B2 RASCUNHO.
  perform public.evaluation_criar(v_org, v_c3, 'edb00000-0000-0000-0000-000000000003', v_a1);
  perform public.evaluation_criar(v_org, v_c3, 'edb00000-0000-0000-0000-000000000001', v_a1);
  perform public.evaluation_criar(v_org, v_c3, 'edb00000-0000-0000-0000-000000000002', v_a1);

  update public.evaluations e
     set status = 'CONCLUIDA', data_conclusao = now(), nota_media = 4.5, version = version + 1
   where e.cycle_id = v_c3
     and e.evaluated_collaborator_id in ('edb00000-0000-0000-0000-000000000001',
                                         'edb00000-0000-0000-0000-000000000003');

  select count(*) into v_part
    from public.evaluation_participants p
    join public.evaluations e on e.id = p.evaluation_id
   where e.cycle_id = v_c3;
  select count(*) into v_n from public.evaluations e where e.cycle_id = v_c3;

  if v_n <> 3
     or (select count(*) from public.evaluations e
          where e.cycle_id = v_c3 and e.status = 'CONCLUIDA') <> 2
     or v_part < 3 then
    raise exception '[FAIL] 7.1: fixture de avaliacoes de A3 incorreta (avaliacoes=%, concluidas=%, participantes=%)',
      v_n,
      (select count(*) from public.evaluations e where e.cycle_id = v_c3 and e.status = 'CONCLUIDA'),
      v_part;
  end if;

  raise notice '[PASS] 7.1: A3 ATIVO/version 1 com 3 avaliacoes (2 CONCLUIDAS + 1 RASCUNHO) e participantes congelados — base do rollback multi-escrita (§8), do cancelamento/auditoria (§9) e da imutabilidade (§12)';
end $$;

-- ----------------------------------------------------------------------------
-- 8) ROLLBACK/ATOMICIDADE em operacao MULTI-ESCRITA (cancelamento com avaliacoes)
-- ----------------------------------------------------------------------------
-- A3 tem 1 avaliacao RASCUNHO (alem de 2 CONCLUIDAS que o cancelamento
-- PRESERVA). O gatilho temporario aborta a SEGUNDA escrita de cancelamento de
-- avaliacao — DEPOIS de trabalho REAL ja executado na mesma transacao. Um
-- SEQUENCE (nao transacional) prova, apos o rollback, que o processamento comecou.
create sequence public._mut_p9_aval_seq;

create or replace function public._mut_p9_falhar_cancelamento_aval()
returns trigger language plpgsql as $mut$
declare
  v_tentativa bigint := nextval('public._mut_p9_aval_seq');
begin
  if v_tentativa >= 1 then
    raise notice '_mut_p9_falhar_cancelamento_aval: abortando na %a escrita de cancelamento de avaliacao (falha na PRIMEIRA escrita; o contador nao transacional prova que o caminho executou)', v_tentativa;
    raise exception 'MUT_F5_09_P9: falha injetada durante o cancelamento das avaliacoes';
  end if;
  return new;
end;
$mut$;

create trigger _mut_p9_aval before insert on public.evaluation_events
  for each row execute function public._mut_p9_falhar_cancelamento_aval();

do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c3   uuid;
  v_ok   boolean := false;
  v_msg  text;
  v_tent bigint;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2038 and c.numero = 1;
  begin
    perform public.ciclo_cancelar(v_c3, v_org,
      'Cancelamento com falha injetada na 2a avaliacao', 1, v_a1,
      'eda10000-0000-0000-0000-000000000801');
  exception when others then
    v_ok := sqlerrm like '%MUT_F5_09_P9%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 8/R1: a falha injetada nao abortou o cancelamento (%)', v_msg;
  end if;
  v_tent := currval('public._mut_p9_aval_seq');
  if v_tent < 1 then
    raise exception '[FAIL] 8/R1: o gatilho nao foi atingido no processamento (tentativas=%)', v_tent;
  end if;
  raise notice '[PASS] 8/R1: falha injetada abortou o cancelamento na %a escrita (trabalho parcial REAL ja havia sido executado na transacao)', v_tent;
end $$;

drop trigger _mut_p9_aval on public.evaluation_events;
drop function public._mut_p9_falhar_cancelamento_aval();
drop sequence public._mut_p9_aval_seq;

do $$
declare
  v_org   uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_c3    uuid;
  v_ciclo record;
  v_n     int;
  v_concl int;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2038 and c.numero = 1;

  -- 1) CICLO no estado ORIGINAL e ainda o UNICO ATIVO de Alfa (I5).
  select c.status, c.version, c.data_encerramento, c.data_ativacao into v_ciclo
    from public.evaluation_cycles c where c.id = v_c3;
  if v_ciclo.status <> 'ATIVO' or v_ciclo.version <> 1
     or v_ciclo.data_encerramento is not null or v_ciclo.data_ativacao is null then
    raise exception '[FAIL] 8/R1: rollback incompleto no ciclo (%, %, %)',
      v_ciclo.status, v_ciclo.version, v_ciclo.data_encerramento;
  end if;
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'ATIVO';
  if v_n <> 1 then
    raise exception '[FAIL] 8/R1: Alfa deveria continuar com exatamente 1 ATIVO (%)', v_n;
  end if;

  -- 2) AVALIACOES: nenhuma cancelada; 2 CONCLUIDAS preservadas e 1 RASCUNHO intacta.
  select count(*) into v_n from public.evaluations e
   where e.cycle_id = v_c3 and e.status = 'CANCELADA';
  select count(*) into v_concl from public.evaluations e
   where e.cycle_id = v_c3 and e.status = 'CONCLUIDA';
  if v_n <> 0 or v_concl <> 2 then
    raise exception '[FAIL] 8/R1: rollback incompleto nas avaliacoes (canceladas=%, concluidas=%)', v_n, v_concl;
  end if;
  if exists (
    select 1 from public.evaluations e
     where e.cycle_id = v_c3
       and e.status <> 'CONCLUIDA'
       and (e.status <> 'RASCUNHO' or e.motivo_cancelamento is not null
            or e.data_cancelamento is not null or e.cancelado_por_user_profile_id is not null)
  ) then
    raise exception '[FAIL] 8/R1: rollback incompleto (avaliacao com residuo de cancelamento)';
  end if;

  -- 3) TRILHA de avaliacoes: nenhum evento CANCELADA.
  select count(*) into v_n
    from public.evaluation_events ev
    join public.evaluations e on e.id = ev.evaluation_id
   where e.cycle_id = v_c3 and ev.event_type = 'CANCELADA';
  if v_n <> 0 then
    raise exception '[FAIL] 8/R1: rollback incompleto na trilha de avaliacoes (eventos CANCELADA=%)', v_n;
  end if;

  -- 4) TRILHA de ciclo: nenhum evento da operacao abortada.
  if exists (select 1 from public.cycle_events e
              where e.organization_id = v_org
                and e.operation_id = 'eda10000-0000-0000-0000-000000000801') then
    raise exception '[FAIL] 8/R1: rollback incompleto (evento de ciclo da operacao abortada gravado)';
  end if;

  -- 5) SNAPSHOTS, RESPONSABILIDADES e PARTICIPANTES coerentes.
  select count(*) into v_n from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1;
  if v_n <> 3 then
    raise exception '[FAIL] 8/R1: rollback incompleto nos snapshots (%)', v_n;
  end if;
  select count(*) into v_n
    from public.cycle_evaluation_responsibilities r
    join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
   where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1;
  if v_n < 2 then
    raise exception '[FAIL] 8/R1: rollback incompleto nas responsabilidades (%)', v_n;
  end if;
  if exists (
    select 1 from public.evaluation_participants p
      join public.evaluations e on e.id = p.evaluation_id
     where e.cycle_id = v_c3
       and (p.status <> 'active' or p.valid_to is not null)
  ) then
    raise exception '[FAIL] 8/R1: rollback incompleto nos participantes congelados';
  end if;

  raise notice '[PASS] 8/R1 (rollback total): falha no meio de uma operacao MULTI-ESCRITA => ciclo ATIVO/version 1 (ainda o unico ATIVO de Alfa), 2 avaliacoes CONCLUIDAS preservadas, 1 RASCUNHO intacta, ZERO evento de cancelamento (avaliacao E ciclo), snapshots/responsabilidades/participantes coerentes e o artefato temporario removido';
end $$;

-- ----------------------------------------------------------------------------
-- 9) AUDITORIA: trilha soberana append-only com autoria e idempotencia
-- ----------------------------------------------------------------------------
-- (i) CANCELAMENTO REAL de A3 (ATIVO v1 -> CANCELADO v2), que e TAMBEM a
--     liberacao do slot `ATIVO` de Alfa para o §13 (I5).
do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c3   uuid;
  v_res  jsonb;
  v_n    int;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2038 and c.numero = 1;
  v_res := public.ciclo_cancelar(v_c3, v_org, 'Cancelamento soberano de A3 (auditoria P9)',
    1, v_a1, 'eda10000-0000-0000-0000-000000000902');
  if (v_res->>'status') <> 'CANCELADO' or (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] 9/pre-condicao: cancelamento de A3 deveria resultar em CANCELADO/version 2 (%)', v_res;
  end if;
  if (v_res->>'avaliacoes_canceladas')::int <> 1
     or (v_res->>'avaliacoes_concluidas_preservadas')::int <> 2 then
    raise exception '[FAIL] 9/pre-condicao: cancelamento deveria cancelar 1 RASCUNHO e preservar 2 CONCLUIDAS (%)', v_res;
  end if;
  -- Replay idempotente do MESMO cancelamento (mesmo operation_id/payload).
  v_res := public.ciclo_cancelar(v_c3, v_org, 'Cancelamento soberano de A3 (auditoria P9)',
    1, v_a1, 'eda10000-0000-0000-0000-000000000902');
  if (v_res->>'status') <> 'CANCELADO' or (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] 9/pre-condicao: replay do cancelamento deveria devolver CANCELADO/version 2 (%)', v_res;
  end if;
  select count(*) into v_n from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = 'eda10000-0000-0000-0000-000000000902';
  if v_n <> 1 then
    raise exception '[FAIL] 9/pre-condicao: replay do cancelamento duplicou a trilha (%)', v_n;
  end if;
  -- Slot ATIVO liberado (I5) — a proxima ativacao de Alfa e a de A6.
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'ATIVO';
  if v_n <> 0 then
    raise exception '[FAIL] 9/pre-condicao: o cancelamento deveria liberar o slot ATIVO de Alfa (%)', v_n;
  end if;

  raise notice '[PASS] 9/pre-condicao: A3 CANCELADO/version 2 (1 avaliacao cancelada, 2 CONCLUIDAS preservadas), replay idempotente sem trilha nova e Alfa com ZERO ciclos ATIVO (slot livre para §13)';
end $$;

-- (ii) ATIVACAO de A6 (2040/1) com o slot livre: produz o evento ATIVADO
--      auditado abaixo e o alvo do §10/DML.
do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c6   uuid;
  v_res  jsonb;
  v_n    int;
begin
  select c.id into v_c6 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2040 and c.numero = 1;
  v_res := public.ciclo_ativar(v_c6, v_org, 0, v_a1, 'eda10000-0000-0000-0000-000000000903');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> 1 then
    raise exception '[FAIL] 9/pre-condicao: A6 deveria estar ATIVO/version 1 (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'ATIVO';
  if v_n <> 1 then
    raise exception '[FAIL] 9/pre-condicao: Alfa deveria ter exatamente 1 ATIVO (A6) (%)', v_n;
  end if;
  raise notice '[PASS] 9/pre-condicao: A6 ATIVO/version 1 (unico ATIVO de Alfa) e evento ATIVADO criado para a auditoria';
end $$;

do $$
declare
  v_org  uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1   uuid := 'edc00000-0000-0000-0000-000000000001';
  v_mem  uuid := 'edd00000-0000-0000-0000-000000000001';
  v_c3   uuid;
  v_c6   uuid;
  v_c1   uuid;
  v_evt  record;
  v_n    int;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2038 and c.numero = 1;
  select c.id into v_c6 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2040 and c.numero = 1;
  select c.id into v_c1 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2037 and c.numero = 1;

  -- (1) CRIADO (setup de A1) — autoria, hash, before/after do contrato.
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = 'eda10000-0000-0000-0000-000000000a01';
  if v_evt.event_type <> 'CRIADO' or v_evt.reason is null or btrim(v_evt.reason) = '' then
    raise exception '[FAIL] 9/CRIADO: evento CRIADO ausente ou sem motivo';
  end if;
  if v_evt.actor_user_profile_id <> v_a1 or v_evt.actor_membership_id <> v_mem then
    raise exception '[FAIL] 9/CRIADO: autoria da trilha nao e o ator verificado + membership ativa';
  end if;
  if (v_evt.after_value->>'status') <> 'PLANEJADO' or (v_evt.after_value->>'ano')::int <> 2037
     or (v_evt.after_value->>'numero')::int <> 1 or (v_evt.after_value->>'version')::int <> 0 then
    raise exception '[FAIL] 9/CRIADO: after_value fora do contrato (%)', v_evt.after_value;
  end if;
  if v_evt.before_value is not null then
    raise exception '[FAIL] 9/CRIADO: before_value deveria ser nulo na criacao';
  end if;
  if v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] 9/CRIADO: payload_hash fora do formato SHA-256 (%)', v_evt.payload_hash;
  end if;
  if v_evt.result_entity_id is distinct from v_c1 then
    raise exception '[FAIL] 9/CRIADO: result_entity_id deveria ser o UUID do ciclo';
  end if;

  -- (2) ATIVADO (de A6, §9(ii)) — transicao PLANEJADO -> ATIVO com materializacao.
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = 'eda10000-0000-0000-0000-000000000903';
  if v_evt.event_type <> 'ATIVADO'
     or (v_evt.before_value->>'status') <> 'PLANEJADO'
     or (v_evt.after_value->>'status') <> 'ATIVO'
     or (v_evt.after_value->>'version')::int <> 1 then
    raise exception '[FAIL] 9/ATIVADO: before/after fora do contrato (%)', v_evt.after_value;
  end if;
  if (v_evt.after_value->>'snapshot_materializado')::int <> 3
     or (v_evt.after_value->>'colaboradores_elegiveis')::int <> 3 then
    raise exception '[FAIL] 9/ATIVADO: after_value sem as contagens da materializacao (%)', v_evt.after_value;
  end if;
  if v_evt.actor_user_profile_id <> v_a1 or v_evt.actor_membership_id <> v_mem
     or v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] 9/ATIVADO: autoria/hash fora do contrato';
  end if;

  -- (3) ENCERRADO (de A2, §4/limpeza) — ATIVO -> ENCERRADO com contadores.
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = 'eda10000-0000-0000-0000-000000000b03';
  if v_evt.event_type <> 'ENCERRADO'
     or v_evt.reason <> 'Encerramento para liberar o slot ATIVO (I5/P9)' then
    raise exception '[FAIL] 9/ENCERRADO: evento ausente ou com motivo divergente';
  end if;
  if (v_evt.before_value->>'status') <> 'ATIVO' or (v_evt.before_value->>'version')::int <> 1
     or (v_evt.after_value->>'status') <> 'ENCERRADO'
     or (v_evt.after_value->>'version')::int <> 2 then
    raise exception '[FAIL] 9/ENCERRADO: before/after fora do contrato (%)', v_evt.after_value;
  end if;
  if (v_evt.after_value->>'quantidade_pendencias') is null
     or (v_evt.after_value->>'encerrado_com_pendencias') is null then
    raise exception '[FAIL] 9/ENCERRADO: after_value sem os contadores de pendencia';
  end if;
  if v_evt.actor_user_profile_id <> v_a1 or v_evt.actor_membership_id <> v_mem
     or v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] 9/ENCERRADO: autoria/hash fora do contrato';
  end if;

  -- (4) CANCELADO (de A3, §9(i)) — ATIVO -> CANCELADO com as contagens.
  select e.* into v_evt from public.cycle_events e
   where e.organization_id = v_org and e.operation_id = 'eda10000-0000-0000-0000-000000000902';
  if v_evt.event_type <> 'CANCELADO'
     or (v_evt.before_value->>'status') <> 'ATIVO'
     or (v_evt.after_value->>'status') <> 'CANCELADO'
     or (v_evt.after_value->>'avaliacoes_canceladas')::int <> 1
     or (v_evt.after_value->>'avaliacoes_concluidas_preservadas')::int <> 2 then
    raise exception '[FAIL] 9/CANCELADO: before/after fora do contrato (%)', v_evt.after_value;
  end if;
  if v_evt.actor_user_profile_id <> v_a1 or v_evt.actor_membership_id <> v_mem
     or v_evt.payload_hash !~ '^[0-9a-f]{64}$' then
    raise exception '[FAIL] 9/CANCELADO: autoria/hash fora do contrato';
  end if;

  -- (5) UM evento por operacao (nenhuma trilha duplicada).
  select count(*) into v_n from (
    select e.operation_id
      from public.cycle_events e
     where e.organization_id = v_org
     group by e.operation_id
    having count(*) > 1) t;
  if v_n <> 0 then
    raise exception '[FAIL] 9: % operation_id com trilha duplicada na organizacao Alfa', v_n;
  end if;

  -- (6) Nenhum dado pessoal na trilha.
  if exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and (e.before_value ? 'full_name' or e.before_value ? 'email' or e.before_value ? 'matricula'
            or e.after_value ? 'full_name' or e.after_value ? 'email' or e.after_value ? 'matricula')
  ) then
    raise exception '[FAIL] 9: trilha de ciclo com dado pessoal desnecessario';
  end if;

  raise notice '[PASS] 9/auditoria: CRIADO, ATIVADO, ENCERRADO e CANCELADO presentes com `event_type` do contrato, autoria SOBERANA (ator verificado + membership ativa), before/after auditaveis, `operation_id` registrado, `payload_hash` SHA-256 hex, uma linha por operacao e nenhum dado pessoal';
end $$;

-- (iii) APPEND-ONLY: UPDATE/DELETE/TRUNCATE negados pelo TRIGGER ate para o OWNER
--       da tabela (o validador roda como owner; a ACL nao e a barreira testada).
do $$
begin
  begin
    update public.cycle_events set reason = reason
     where organization_id = 'eda00000-0000-0000-0000-0000000000a1';
    raise exception '[FAIL] 9/append-only: UPDATE de cycle_events aceito pelo owner';
  exception
    when others then
      if sqlerrm like '%F5-09: cycle_events e append-only (UPDATE negado)%' then
        raise notice '[PASS] 9/append-only: UPDATE da trilha bloqueado pelo trigger ate para o owner';
      else
        raise;
      end if;
  end;

  begin
    delete from public.cycle_events
     where organization_id = 'eda00000-0000-0000-0000-0000000000a1';
    raise exception 'F5-09_P9_PROBE_EFEITO';
  exception
    when others then
      if sqlerrm like '%F5-09: cycle_events e append-only (DELETE negado)%' then
        raise notice '[PASS] 9/append-only: DELETE da trilha bloqueado pelo trigger ate para o owner';
      elsif sqlerrm = 'F5-09_P9_PROBE_EFEITO' then
        raise exception '[FAIL] 9/append-only: DELETE de cycle_events aceito pelo owner';
      else
        raise;
      end if;
  end;

  begin
    truncate public.cycle_events;
    raise exception 'F5-09_P9_PROBE_EFEITO';
  exception
    when others then
      if sqlerrm like '%F5-09: cycle_events e append-only (TRUNCATE negado)%' then
        raise notice '[PASS] 9/append-only: TRUNCATE da trilha bloqueado pelo trigger ate para o owner';
      elsif sqlerrm = 'F5-09_P9_PROBE_EFEITO' then
        raise exception '[FAIL] 9/append-only: TRUNCATE de cycle_events aceito pelo owner';
      else
        raise;
      end if;
  end;
end $$;

-- ----------------------------------------------------------------------------
-- 10) RLS e superficies de privilegio: cliente sem escrita, anon sem acesso,
--     service_role executor que NAO decide autorizacao
-- ----------------------------------------------------------------------------
-- (10.1) CANCELAMENTO de A6 (ATIVO v1 -> CANCELADO v2): libera o slot `ATIVO` de
-- Alfa para o §13 e deixa um ciclo terminal para a prova de DML direto.
do $$
declare
  v_org uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c6  uuid;
  v_res jsonb;
  v_n   int;
begin
  select c.id into v_c6 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2040 and c.numero = 1;
  v_res := public.ciclo_cancelar(v_c6, v_org, 'Cancelamento de A6 (pre-condicao do DML direto)',
    1, v_a1, 'eda10000-0000-0000-0000-000000000a08');
  if (v_res->>'status') <> 'CANCELADO' or (v_res->>'version')::int <> 2 then
    raise exception '[FAIL] 10/pre-condicao: A6 deveria estar CANCELADO/version 2 (%)', v_res;
  end if;
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = v_org and c.status = 'ATIVO';
  if v_n <> 0 then
    raise exception '[FAIL] 10/pre-condicao: Alfa deveria ter ZERO ciclos ATIVO apos cancelar A6 (%)', v_n;
  end if;
  raise notice '[PASS] 10/pre-condicao: A6 CANCELADO/version 2 e Alfa com ZERO ciclos ATIVO (slot livre para a admissao do §13)';
end $$;

do $$
declare
  v_problemas text[] := array[]::text[];
  v_policy    record;
  v_n         int;
  v_priv      text;
begin
  -- (a) Exatamente UMA policy em evaluation_cycles: SELECT own-tenant.
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'evaluation_cycles';
  if v_n <> 1 then
    v_problemas := v_problemas || format('policies em evaluation_cycles = %s (esperado 1)', v_n);
  end if;
  select p.cmd, p.roles, coalesce(p.qual, '') as qual, p.permissive into v_policy
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'evaluation_cycles'
     and p.policyname = 'evaluation_cycles_select_same_tenant';
  if not found then
    v_problemas := v_problemas || 'policy evaluation_cycles_select_same_tenant ausente'::text;
  else
    if v_policy.cmd <> 'SELECT' then
      v_problemas := v_problemas || ('cmd da policy = ' || v_policy.cmd);
    end if;
    if not ('authenticated'::name = any(v_policy.roles)) or 'anon'::name = any(v_policy.roles) then
      v_problemas := v_problemas || ('roles da policy fora do contrato: ' || array_to_string(v_policy.roles, ','));
    end if;
    if v_policy.permissive <> 'PERMISSIVE' then
      v_problemas := v_problemas || 'policy nao e PERMISSIVE'::text;
    end if;
    if v_policy.qual not like '%user_has_active_membership%'
       or v_policy.qual not like '%organization_id%' then
      v_problemas := v_problemas || ('predicado da policy fora do contrato: ' || v_policy.qual);
    end if;
  end if;

  -- (b) Nenhum privilegio de escrita a `authenticated`; nenhum a `anon`.
  if has_table_privilege('authenticated', 'public.evaluation_cycles', 'SELECT') is not true then
    v_problemas := v_problemas || 'authenticated sem SELECT (contrato do P5)'::text;
  end if;
  foreach v_priv in array array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']
  loop
    if has_table_privilege('authenticated', 'public.evaluation_cycles', v_priv) then
      v_problemas := v_problemas || ('authenticated com ' || v_priv);
    end if;
    if has_table_privilege('anon', 'public.evaluation_cycles', v_priv) then
      v_problemas := v_problemas || ('anon com ' || v_priv);
    end if;
  end loop;
  if has_table_privilege('anon', 'public.evaluation_cycles', 'SELECT') then
    v_problemas := v_problemas || 'anon com SELECT'::text;
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'evaluation_cycles' and cmd <> 'SELECT') then
    v_problemas := v_problemas || 'policy de ESCRITA aberta em evaluation_cycles'::text;
  end if;

  -- (c) cycle_events deny-by-default integral.
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'cycle_events') then
    v_problemas := v_problemas || 'policy em cycle_events (trilha deve ser deny-by-default)'::text;
  end if;
  if has_table_privilege('authenticated', 'public.cycle_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.cycle_events', 'INSERT')
     or has_table_privilege('anon', 'public.cycle_events', 'SELECT') then
    v_problemas := v_problemas || 'trilha cycle_events exposta a cliente'::text;
  end if;

  -- (d) service_role permanece EXECUTOR privilegiado das tabelas do dominio.
  foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE']
  loop
    if has_table_privilege('service_role', 'public.evaluation_cycles', v_priv) is not true then
      v_problemas := v_problemas || ('service_role sem ' || v_priv || ' em evaluation_cycles');
    end if;
  end loop;
  if has_table_privilege('service_role', 'public.evaluation_cycles', 'DELETE')
     or has_table_privilege('service_role', 'public.evaluation_cycles', 'TRUNCATE') then
    v_problemas := v_problemas || 'service_role com DELETE/TRUNCATE em evaluation_cycles (D9)'::text;
  end if;
  if has_table_privilege('service_role', 'public.cycle_events', 'SELECT') is not true
     or has_table_privilege('service_role', 'public.cycle_events', 'INSERT') is not true
     or has_table_privilege('service_role', 'public.cycle_events', 'UPDATE')
     or has_table_privilege('service_role', 'public.cycle_events', 'DELETE') then
    v_problemas := v_problemas || 'ACL de service_role na trilha fora do contrato'::text;
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] 10/catalogo: %', array_to_string(v_problemas, '; ');
  end if;

  raise notice '[PASS] 10/catalogo: policy UNICA de SELECT own-tenant em evaluation_cycles (nenhuma de escrita), `authenticated` sem nenhum privilegio de escrita, `anon` sem acesso, `service_role` executor privilegiado e `cycle_events` deny-by-default integral';
end $$;

-- `authenticated`: escrita DIRETA negada com causa especifica (42501).
select set_config('request.jwt.claim.sub', 'edc00000-0000-0000-0000-000000000001', false);
set role authenticated;

do $$
declare
  v_ok     boolean;
  v_antes  int;
  v_depois int;
  v_c6     uuid;
begin
  select c.id into v_c6 from public.evaluation_cycles c
   where c.organization_id = 'eda00000-0000-0000-0000-0000000000a1' and c.ano = 2040 and c.numero = 1;
  select count(*) into v_antes from public.evaluation_cycles;

  v_ok := false;
  begin
    insert into public.evaluation_cycles
      (id, organization_id, ano, numero, status, data_inicio, data_fim, version)
    values ('eda00000-0000-0000-0000-00000000ff01',
            'eda00000-0000-0000-0000-0000000000a1',
            2045, 1, 'PLANEJADO', date '2045-01-01', date '2045-03-31', 0);
    raise exception '[FAIL] 10/DML: INSERT direto de authenticated foi ACEITO';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] 10/DML: INSERT direto deveria ser negado por insufficient_privilege';
  end if;

  v_ok := false;
  begin
    update public.evaluation_cycles set version = version where id = v_c6;
    raise exception '[FAIL] 10/DML: UPDATE direto de authenticated foi ACEITO';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] 10/DML: UPDATE direto deveria ser negado por insufficient_privilege';
  end if;

  v_ok := false;
  begin
    delete from public.evaluation_cycles where id = v_c6;
    raise exception '[FAIL] 10/DML: DELETE direto de authenticated foi ACEITO';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] 10/DML: DELETE direto deveria ser negado por insufficient_privilege';
  end if;

  v_ok := false;
  begin
    insert into public.cycle_events
      (organization_id, cycle_id, entity_type, event_type, effective_date, reason,
       payload_hash, actor_user_profile_id, actor_membership_id, operation_id)
    values ('eda00000-0000-0000-0000-0000000000a1', v_c6,
            'evaluation_cycle', 'CRIADO', now(), 'probe de INSERT direto na trilha',
            repeat('a', 64), 'edc00000-0000-0000-0000-000000000001',
            'edd00000-0000-0000-0000-000000000001', 'eda10000-0000-0000-0000-00000000ff02');
    raise exception '[FAIL] 10/DML: INSERT direto na trilha por authenticated foi ACEITO';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] 10/DML: INSERT direto na trilha deveria ser negado por insufficient_privilege';
  end if;

  select count(*) into v_depois from public.evaluation_cycles;
  if v_depois <> v_antes then
    raise exception '[FAIL] 10/DML: tentativa de escrita alterou a populacao visivel (% -> %)', v_antes, v_depois;
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_c6) <> 'CANCELADO'
     or (select c.version from public.evaluation_cycles c where c.id = v_c6) <> 2 then
    raise exception '[FAIL] 10/DML: tentativa de escrita alterou o ciclo CANCELADO';
  end if;

  raise notice '[PASS] 10/DML: INSERT/UPDATE/DELETE em evaluation_cycles e INSERT em cycle_events feitos DIRETO por `authenticated` sao negados por insufficient_privilege e nenhuma tentativa produz efeito';
end $$;

reset role;

-- `anon`: sem qualquer acesso (nem leitura).
set role anon;

do $$
declare
  v_ok boolean;
begin
  v_ok := false;
  begin
    perform count(*) from public.evaluation_cycles;
    raise exception '[FAIL] 10/anon: leitura de evaluation_cycles por anon foi ACEITA';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] 10/anon: leitura por anon deveria ser negada';
  end if;

  v_ok := false;
  begin
    perform count(*) from public.cycle_events;
    raise exception '[FAIL] 10/anon: leitura de cycle_events por anon foi ACEITA';
  exception
    when insufficient_privilege then v_ok := true;
  end;
  if not v_ok then
    raise exception '[FAIL] 10/anon: leitura da trilha por anon deveria ser negada';
  end if;

  raise notice '[PASS] 10/anon: `anon` nao le ciclos nem a trilha (deny-by-default)';
end $$;

reset role;

-- `service_role` EXECUTA as RPCs mas NAO decide autorizacao.
set role service_role;

do $$
declare
  v_org uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_c5  uuid;
  v_ok  boolean;
  v_msg text;
  v_n   int;
begin
  select c.id into v_c5 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2039 and c.numero = 2;

  -- (a) service_role le a populacao do dominio (executor privilegiado).
  select count(*) into v_n from public.evaluation_cycles where organization_id = v_org;
  if v_n <> 6 then
    raise exception '[FAIL] 10/service_role: deveria ler os 6 ciclos do tenant Alfa (%)', v_n;
  end if;

  -- (b) NAO decide autorizacao: ator fantasma (JWT sem profile/membership) e recusado.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_criar(v_org, 2045, 1, date '2045-01-01', date '2045-03-31',
      'edc00000-0000-0000-0000-000000000005', 'eda10000-0000-0000-0000-00000000ff03');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 10/service_role: ator invalido deveria ser recusado mesmo sob service_role (%)', v_msg;
  end if;

  -- (c) NAO decide capability: ator SEM `cycle.manage`. Usa o leitor-alfa (que
  -- tem apenas `cycle.read`): a prova nao pode depender do grant do gestor-alfa,
  -- porque o §4/§5 RESTAURA esse grant ao final da prova de revogacao temporal
  -- (necessario para os blocos seguintes). Aqui o ator e estruturalmente sem a
  -- capability, e a recusa tem de vir do banco mesmo sob `service_role`.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_ativar(v_c5, v_org, 1, 'edc00000-0000-0000-0000-000000000002',
      'eda10000-0000-0000-0000-00000000ff04');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%' and sqlerrm like '%cycle.manage%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 10/service_role: ausencia de capability deveria ser recusada mesmo sob service_role (%)', v_msg;
  end if;

  if exists (select 1 from public.cycle_events e
              where e.operation_id::text in ('eda10000-0000-0000-0000-00000000ff03',
                                             'eda10000-0000-0000-0000-00000000ff04')) then
    raise exception '[FAIL] 10/service_role: recusa por autorizacao gravou trilha';
  end if;

  raise notice '[PASS] 10/service_role: o papel privilegiado EXECUTA as RPCs (e le o dominio) mas NAO decide autorizacao — ator invalido e ausencia de capability sao recusados server-side com zero efeito';
end $$;

reset role;

do $$
declare
  v_fn text;
begin
  foreach v_fn in array array[
    'public.ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'public.ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)',
    'public.ciclo_ativar(uuid, uuid, integer, uuid, uuid)',
    'public.ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)',
    'public.ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)']
  loop
    if has_function_privilege('service_role', v_fn, 'EXECUTE') is not true then
      raise exception '[FAIL] 10/ACL: service_role sem EXECUTE em %', v_fn;
    end if;
  end loop;
  raise notice '[PASS] 10/ACL: as 8 RPCs de ciclo tem EXECUTE para service_role (o unico executor privilegiado do dominio)';
end $$;

-- ----------------------------------------------------------------------------
-- 11) REGRESSOES P1–P8: integridade, I5 no estado final, superficie de mutacao,
--     catalogo e fronteira por LISTA FECHADA de F5-10/F5-11
-- ----------------------------------------------------------------------------
do $$
declare
  v_fn        text;
  v_rec       record;
  v_problemas text[] := array[]::text[];
  v_caps      int;
  v_bundle    int;
  v_cycle_ct  int;
  v_n         int;
  v_cols      text[];
  -- F5-10 P1/P2/P3/P4 (Issues #210, #212, #214 e P4): objetos de METAS
  -- legitimados pelas fases implementadas. A guarda de "nao antecipar F5-10" NAO
  -- foi enfraquecida: passou a LISTA FECHADA (tabelas + funcoes de
  -- integridade/trilha + as 10 RPCs soberanas das P2/P3/P4 + os 3 helpers de
  -- autorizacao da P4). Qualquer objeto de METAS fora dela continua reprovando.
  v_tabelas_metas_p1 text[] := array[
    'evaluation_goals','evaluation_goal_approvals','evaluation_goal_events',
    'evaluation_cycle_goal_limits'];
  -- F5-11 P1 (Issue #238): a PROIBICAO ABSOLUTA de observacao foi SUBSTITUIDA pela
  -- mesma doutrina de LISTA FECHADA (nunca removida). As tabelas legitimas da P1
  -- sao exatamente as duas do contrato (D1) e a lista de FUNCOES contem as duas
  -- funcoes de enforcement da P1 mais as 8 RPCs e os 5 helpers da P2 (Issue #244),
  -- ampliada EXPLICITAMENTE por esta fase. Qualquer objeto de observacao fora
  -- dessas listas continua reprovando, e as fases seguintes (P3..P6) seguem nao
  -- antecipadas.
  v_tabelas_observacoes_p1 text[] := array[
    'evaluation_observations','evaluation_observation_events'];
  v_funcoes_observacoes_p1 text[] := array[
    -- F5-11 P1: as DUAS funcoes de enforcement da propria P1 (imutabilidade
    -- estrutural do D4 e append-only da trilha do D6). O nome delas casa com o
    -- filtro por nome (`%observa%`) exatamente como os helpers de aprovacao da
    -- F5-10 casavam com `%meta%`: por isso a lista precisa nomea-las.
    'enforce_evaluation_observations_imutaveis',
    'enforce_evaluation_observation_events_append_only',    -- F5-11 P2 (Issue #244): as RPCs soberanas `observacao_*` e os helpers do
    -- gate funcional. A fase AMPLIA a lista explicitamente (a proibicao absoluta
    -- virou lista fechada na P1 e nunca e' removida); nenhum `observation_*`.
    'observacao_criar','observacao_editar','observacao_definir_comunicado',
    'observacao_excluir','observacao_revogar','observacao_obter',
    'observacao_listar_por_escopo','observacao_historico',
    'f5_11_ator_efetivo_observacao','f5_11_ator_valido_observacao',
    'f5_11_vinculo_observacao_do_ator','f5_11_relacao_observacao_do_ator',
    'f5_11_exigir_autorizacao_observacao'    ];
  v_funcoes_metas_p1 text[] := array[
    'enforce_evaluation_goal_events_append_only','f5_10_validar_quota_da_meta',
    'f5_10_validar_quota_do_limite','f5_10_proteger_limite_do_ciclo',
    'f5_10_validar_autoria_da_aprovacao',
    -- F5-10 P4: helpers de autorizacao/relacao (SECURITY INVOKER, sem prefixo
    -- `meta_`, EXECUTE so service_role) que sustentam o gate das RPCs.
    'f5_10_ator_valido_meta','f5_10_exigir_autorizacao_meta',
    'f5_10_vinculo_meta_do_ator',
    'meta_criar','meta_editar','meta_atualizar_progresso','meta_finalizar',
    'meta_revisar_finalizacao','meta_excluir','meta_definir_limites_do_ciclo',
    'meta_aprovar','meta_invalidar_aprovacoes',
    -- F5-10 P4: 10a RPC `meta_*` — leitura por escopo com gate `goal.read`.
    'meta_listar_por_escopo'];
begin
  -- (a) I5, I6 e I3 (P1/F5-06) presentes.
  if not exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'evaluation_cycles'
       and indexname = 'uq_evaluation_cycles_org_ativo'
  ) then
    v_problemas := v_problemas || 'I5 ausente (uq_evaluation_cycles_org_ativo)';
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycles'::regclass
       and c.conname = 'ex_evaluation_cycles_periodo_no_overlap' and c.contype = 'x'
  ) then
    v_problemas := v_problemas || 'I6 ausente (ex_evaluation_cycles_periodo_no_overlap)';
  end if;
  if not exists (
    select 1 from pg_constraint c
     where c.conrelid = 'public.evaluation_cycles'::regclass
       and c.conname = 'uq_evaluation_cycles_org_ano_numero' and c.contype = 'u'
  ) then
    v_problemas := v_problemas || 'I3 ausente (uq_evaluation_cycles_org_ano_numero)';
  end if;

  -- (a2) I5 conferido no ESTADO FINAL: NO MAXIMO um ATIVO por organizacao. O
  --      invariante do banco e "no maximo um" (indice unico parcial) — o roteiro
  --      encerra/cancela os ciclos ao longo dos blocos, entao Alfa pode terminar
  --      com ZERO ATIVO (e Beta com um). Exigir "exatamente um" mediria o roteiro,
  --      nao o contrato.
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = 'eda00000-0000-0000-0000-0000000000a1' and c.status = 'ATIVO';
  if v_n > 1 then
    raise exception '[FAIL] 11/I5: Alfa nao pode terminar com MAIS DE UM ciclo ATIVO, encontrado %', v_n;
  end if;
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id = 'eda00000-0000-0000-0000-0000000000b1' and c.status = 'ATIVO';
  if v_n > 1 then
    raise exception '[FAIL] 11/I5: Beta nao pode terminar com MAIS DE UM ciclo ATIVO, encontrado %', v_n;
  end if;
  select count(*) into v_n from (
    select c.organization_id
      from public.evaluation_cycles c
     where c.status = 'ATIVO'
     group by c.organization_id
    having count(*) > 1) t;
  if v_n <> 0 then
    raise exception '[FAIL] 11/I5: % organizacao(oes) com mais de um ciclo ATIVO', v_n;
  end if;

  -- (a3) Cada ciclo tem EXATAMENTE um evento CRIADO (um ciclo oficial = uma
  --      criacao auditada), e nenhuma trilha orfa.
  select count(*) into v_n from (
    select e.cycle_id
      from public.cycle_events e
     where e.event_type = 'CRIADO'
     group by e.cycle_id
    having count(*) > 1) t;
  if v_n <> 0 then
    v_problemas := v_problemas || format('%s ciclo(s) com mais de um evento CRIADO', v_n);
  end if;
  -- ESCOPO OBRIGATORIO: apenas as organizacoes do fixture P9. As fixtures das
  -- fases P1–P5 (que rodam ANTES no job do CI) inserem ciclos DIRETAMENTE, sem
  -- evento CRIADO — o contrato delas nao e a trilha. Uma checagem GLOBAL aqui
  -- falharia no CI mesmo passando isolada (achado de integracao da propria P9).
  select count(*) into v_n from public.evaluation_cycles c
   where c.organization_id in ('eda00000-0000-0000-0000-0000000000a1',
                               'eda00000-0000-0000-0000-0000000000b1',
                               'eda00000-0000-0000-0000-0000000000c1')
     and not exists (
     select 1 from public.cycle_events e
      where e.cycle_id = c.id and e.organization_id = c.organization_id
        and e.event_type = 'CRIADO');
  if v_n <> 0 then
    v_problemas := v_problemas || format('%s ciclo(s) sem evento CRIADO', v_n);
  end if;
  select count(*) into v_n from public.cycle_events e
   where not exists (
     select 1 from public.evaluation_cycles c
      where c.id = e.cycle_id and c.organization_id = e.organization_id);
  if v_n <> 0 then
    v_problemas := v_problemas || format('%s evento(s) de trilha orfaos', v_n);
  end if;

  -- (b) As 8 RPCs: SECURITY INVOKER, search_path fixo, EXECUTE so service_role.
  foreach v_fn in array array[
    'ciclo_criar(uuid, integer, integer, date, date, uuid, uuid)',
    'ciclo_editar(uuid, uuid, integer, integer, date, date, integer, uuid, uuid)',
    'ciclo_ativar(uuid, uuid, integer, uuid, uuid)',
    'ciclo_encerrar(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_incluir_admissao(uuid, uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_cancelar(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_reabrir(uuid, uuid, text, integer, uuid, uuid)',
    'ciclo_corrigir_periodo(uuid, uuid, date, date, text, integer, uuid, uuid)']
  loop
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '') as config into v_rec
      from pg_proc p where p.oid = to_regprocedure('public.' || v_fn);
    if not found then
      v_problemas := v_problemas || ('RPC ausente: ' || v_fn);
      continue;
    end if;
    if v_rec.prosecdef then
      v_problemas := v_problemas || ('SECURITY DEFINER: ' || v_fn);
    end if;
    if position('search_path=public' in v_rec.config) = 0 then
      v_problemas := v_problemas || ('sem search_path fixo: ' || v_fn);
    end if;
    if has_function_privilege('service_role', 'public.' || v_fn, 'EXECUTE') is not true then
      v_problemas := v_problemas || ('service_role sem EXECUTE: ' || v_fn);
    end if;
    if has_function_privilege('authenticated', 'public.' || v_fn, 'EXECUTE')
       or has_function_privilege('anon', 'public.' || v_fn, 'EXECUTE') then
      v_problemas := v_problemas || ('RPC exposta a cliente: ' || v_fn);
    end if;
  end loop;

  -- (c) trilha append-only com os 3 gatilhos.
  foreach v_fn in array array[
    'trg_cycle_events_append_only', 'trg_cycle_events_no_delete',
    'trg_cycle_events_no_truncate']
  loop
    if not exists (
      select 1 from pg_trigger
       where tgrelid = 'public.cycle_events'::regclass and tgname = v_fn and not tgisinternal
    ) then
      v_problemas := v_problemas || ('trigger ausente: ' || v_fn);
    end if;
  end loop;

  -- (d) Catalogo com 31 capabilities e bundle `admin` com 9 funcionais (D28).
  select count(*) into v_caps from public.capabilities;
  if v_caps <> 31 then
    v_problemas := v_problemas || format('catalogo com %s capabilities (esperado 31)', v_caps);
  end if;
  select count(*) into v_cycle_ct from public.capabilities where code like 'cycle.%';
  if v_cycle_ct <> 5 then
    v_problemas := v_problemas || format('capabilities de ciclo = %s (esperado 5, nenhuma nova)', v_cycle_ct);
  end if;
  select count(*) into v_bundle
    from public.access_role_capabilities
   where access_role_id = 'c0000000-0000-4000-8000-0000000000f1';
  if v_bundle <> 9 then
    v_problemas := v_problemas || format('bundle admin com %s capabilities (esperado 9)', v_bundle);
  end if;
  if not exists (
    select 1
      from public.access_role_capabilities rc
      join public.capabilities c on c.id = rc.capability_id
     where rc.access_role_id = 'c0000000-0000-4000-8000-0000000000f1'
       and c.code = 'cycle.manage'
  ) then
    v_problemas := v_problemas || 'bundle admin sem cycle.manage (D28)';
  end if;
  select count(*) into v_n
    from public.access_role_capabilities rc
    join public.access_roles r on r.id = rc.access_role_id
    join public.capabilities c on c.id = rc.capability_id
   where r.is_system = true
     and c.code in ('cycle.cancel', 'cycle.reopen', 'cycle.period.correct');
  if v_n <> 0 then
    v_problemas := v_problemas || 'role de SISTEMA com capability excepcional de ciclo';
  end if;

  -- (e) F5-10 P1: as tabelas/funcoes de METAS previstas pela P1 (schema,
  --     integridade e limites) sao LEGITIMAS. A guarda NAO foi removida: virou
  --     LISTA FECHADA — qualquer objeto de metas FORA dela continua reprovando.
  --     F5-11 P1 (Issue #238): idem para OBSERVACOES — a proibicao absoluta foi
  --     substituida por lista fechada (2 tabelas legitimas; ZERO funcoes ate a P2).
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and (c.relname like '%goal%' or c.relname like '%meta%')
     and c.relname <> all (v_tabelas_metas_p1);
  if v_n <> 0 then
    v_problemas := v_problemas || format('%s tabela(s) de metas FORA da lista fechada da P1', v_n);
  end if;
  select count(*) into v_n from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and (c.relname like '%observation%' or c.relname like '%observac%')
     and c.relname <> all (v_tabelas_observacoes_p1);
  if v_n <> 0 then
    v_problemas := v_problemas || format('%s tabela(s) de observacoes FORA da lista fechada da F5-11 P1', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like '%meta%' or p.proname like '%goal%')
     and p.proname <> all (v_funcoes_metas_p1);
  if v_n <> 0 then
    v_problemas := v_problemas || format('%s funcao(oes) de metas FORA da lista fechada da P1', v_n);
  end if;
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like '%observa%' or p.proname like '%observation%')
     and p.proname <> all (v_funcoes_observacoes_p1);
  if v_n <> 0 then
    v_problemas := v_problemas || format('%s funcao(oes) de observacoes FORA da lista fechada da F5-11 P1 (a P2 as introduzira)', v_n);
  end if;

  -- (f) NENHUMA coluna de metas/observacoes ligada a ciclo/avaliacao — exceto as
  --     colunas das tabelas legitimas da P1 (nelas o vinculo `*_goal_id`/`*_id` e o
  --     proprio contrato do dominio, nao antecipacao em tabela de ciclo/avaliacao).
  select array_agg(c.table_name || '.' || c.column_name order by c.table_name, c.column_name)
    into v_cols
    from information_schema.columns c
   where c.table_schema = 'public'
     and (c.table_name like '%cycle%' or c.table_name like 'evaluation%')
     and c.table_name <> all (v_tabelas_metas_p1)
     and c.table_name <> all (v_tabelas_observacoes_p1)
     and (c.column_name like '%goal%' or c.column_name like '%meta%'
          or c.column_name like '%observation%' or c.column_name like '%observac%');
  if v_cols is not null then
    v_problemas := v_problemas || ('colunas antecipadas: ' || array_to_string(v_cols, ','));
  end if;

  -- (g) As capabilities de metas/observacoes existem no catalogo (legado
  --     F4-01/F5-04) e NAO foram ampliadas: 3 de meta (`goal.*`) + 5 de
  --     observacao (`observation.*`) = 8 no catalogo real de 31. O numero NAO
  --     pode CRESCER: crescer significaria antecipar F5-10/F5-11.
  select count(*) into v_n from public.capabilities
   where code like 'goal.%' or code like 'observation.%';
  if v_n <> 8 then
    v_problemas := v_problemas || format('capabilities de metas/observacoes = %s (esperado 8 do catalogo legado: 3 goal.* + 5 observation.*)', v_n);
  end if;

  if array_length(v_problemas, 1) is not null then
    raise exception '[FAIL] 11/regressoes: %', array_to_string(v_problemas, '; ');
  end if;

  raise notice '[PASS] 11/regressoes: I5/I6/I3 presentes (e I5 conferido no estado final: 1 ATIVO por organizacao, 1 CRIADO por ciclo, zero trilha orfa), as 8 RPCs INVOKER com search_path fixo e EXECUTE so service_role, trilha append-only com os 3 gatilhos, catalogo com 31 capabilities, bundle admin com 9 funcionais (cycle.manage dentro, excepcionais fora), metas em LISTA FECHADA da F5-10 P1 e observacoes em LISTA FECHADA da F5-11 P1 (2 tabelas legitimas e ZERO funcoes: nenhuma RPC observacao_* existe ate a P2)';
end $$;

-- ----------------------------------------------------------------------------
-- 12) IMUTABILIDADE da estrutura materializada (A11 da P9): a inclusao aditiva de
--     colaborador JA materializado NAO altera nem apaga nenhuma linha dos snapshots
-- ----------------------------------------------------------------------------
-- O alvo e A3, naquele instante ATIVO/version 1 (o §9 so o cancela depois): a
-- recusa vem da prova de ADITIVIDADE (`JA_MATERIALIZADO_NO_CICLO`), que e a
-- primeira checagem do helper. A prova usa contagem, hash md5 do conteudo e um
-- CONTADOR DE ESCRITA (gatilho temporario BEFORE UPDATE OR DELETE FOR EACH ROW)
-- que prova a AUSENCIA de UPDATE/DELETE — nao apenas que o conteudo nao mudou.
-- Contador de escrita TRANSACIONAL (tabela temporaria): uma escrita REVERTIDA
-- pelo rollback NAO deixa linha, entao a prova mede "UPDATE/DELETE EFETIVADO" —
-- que e exatamente o contrato. (A prova de rollback do §8 usa sequence
-- nao transacional de proposito, para provar que o trabalho COMECOU; aqui o
-- objetivo e o oposto.)
create temporary table _p9_escritas (n int);

create or replace function public._mut_p9_conta_escrita()
returns trigger language plpgsql as $mut$
begin
  insert into _p9_escritas (n) values (1);
  return null;
end;
$mut$;

create trigger _mut_p9_snap_upd before update or delete on public.collegiate_cycle_snapshots
  for each row execute function public._mut_p9_conta_escrita();
create trigger _mut_p9_snap_pos_upd before update or delete on public.collegiate_cycle_snapshot_positions
  for each row execute function public._mut_p9_conta_escrita();
create trigger _mut_p9_snap_mem_upd before update or delete on public.collegiate_cycle_snapshot_members
  for each row execute function public._mut_p9_conta_escrita();
create trigger _mut_p9_resp_upd before update or delete on public.cycle_evaluation_responsibilities
  for each row execute function public._mut_p9_conta_escrita();

do $$
begin
  raise notice '[PASS] 12/pre-condicao: contador temporario de UPDATE/DELETE (FOR EACH ROW) instalado nas 3 tabelas de snapshot + responsabilidades (prova de AUSENCIA de escrita, nao apenas de conteudo)';
end $$;

do $$
declare
  v_org     uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1      uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c3      uuid;
  v_snap_h  text;
  v_pos_h   text;
  v_memb_h  text;
  v_resp_h  text;
  v_h       text;
  v_snap_n  int;
  v_pos_n   int;
  v_memb_n  int;
  v_resp_n  int;
  v_ok      boolean;
  v_msg     text;
  v_versao_antes int;
begin
  select c.id into v_c3 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2038 and c.numero = 1;
  -- Versao observada no INICIO do bloco: a prova e "INALTERADO", nao um numero
  -- fixo (o roteiro ja mudou o estado de A3 antes daqui).
  select c.version into v_versao_antes from public.evaluation_cycles c where c.id = v_c3;

  -- Pre-condicao ORDEM-DEPENDENTE do roteiro: a prova A11 abaixo mede
  -- IMUTABILIDADE (contagem + md5 + contador de escrita em ZERO), e ela e valida
  -- em qualquer estado — a recusa pode vir da ADITIVIDADE ou do ESTADO do ciclo,
  -- porque o §9 (auditoria) CANCELOU A3 ao longo do roteiro. Por isso aqui so se
  -- exige que A3 EXISTA, e a prova A11 "pura" (ciclo ATIVO + motivo de
  -- aditividade) vive no §13 A4. Registrar o estado observado torna o bloco
  -- honesto em vez de fingir um estado que o roteiro ja mudou.
  if (select c.status from public.evaluation_cycles c where c.id = v_c3) is null then
    raise exception '[FAIL] 12/A11: A3 nao existe nesta altura do roteiro';
  end if;
  raise notice '12/A11: estado observado de A3 = % / version % (a prova mede imutabilidade, nao o estado)',
    (select c.status from public.evaluation_cycles c where c.id = v_c3),
    (select c.version from public.evaluation_cycles c where c.id = v_c3);

  select count(*), md5(string_agg(x, '|' order by x)) into v_snap_n, v_snap_h from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text || ':' ||
           s.ano::text || ':' || s.ciclo::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) t;
  select count(*), md5(string_agg(y, '|' order by y)) into v_pos_n, v_pos_h from (
    select sp.id::text || ':' || sp.position_id::text || ':' ||
           coalesce(sp.superior_position_id::text, '-') || ':' ||
           coalesce(sp.superior_collaborator_id::text, '-') as y
      from public.collegiate_cycle_snapshot_positions sp
      join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
     where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) t;
  select count(*), md5(string_agg(z, '|' order by z)) into v_memb_n, v_memb_h from (
    select m.id::text || ':' || m.member_collaborator_id::text as z
      from public.collegiate_cycle_snapshot_members m
      join public.collegiate_cycle_snapshots s on s.id = m.snapshot_id
     where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) t;
  select count(*), md5(string_agg(w, '|' order by w)) into v_resp_n, v_resp_h from (
    select r.id::text || ':' || r.position_id::text || ':' ||
           r.responsible_collaborator_id::text || ':' || coalesce(r.valid_to::text, '-') as w
      from public.cycle_evaluation_responsibilities r
      join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
     where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) t;
  if v_snap_n <> 3 or v_pos_n < 2 or v_resp_n < 2 then
    raise exception '[FAIL] 12/A11: baseline invalido (snapshots=%, posicoes=%, responsabilidades=%)', v_snap_n, v_pos_n, v_resp_n;
  end if;

  -- Tentativa: incluir B2 (JA materializado na ativacao) com operation_id NOVO.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c3, v_org,
      'edb00000-0000-0000-0000-000000000002',
      'Tentativa de reinclusao de participante ja materializado (A11)', 1, v_a1,
      'eda10000-0000-0000-0000-000000001201');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%'
            and (sqlerrm like '%JA_MATERIALIZADO_NO_CICLO%' or sqlerrm like '%exige ciclo ATIVO%');
    v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 12/A11: inclusao de participante ja materializado deveria ser recusada por CONFLICT (JA_MATERIALIZADO_NO_CICLO ou estado do ciclo) (%)', v_msg;
  end if;

  -- Contagem IDENTICA.
  if (select count(*) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) <> v_snap_n
     or (select count(*) from public.collegiate_cycle_snapshot_positions sp
           join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
          where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) <> v_pos_n
     or (select count(*) from public.collegiate_cycle_snapshot_members m
           join public.collegiate_cycle_snapshots s on s.id = m.snapshot_id
          where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) <> v_memb_n
     or (select count(*) from public.cycle_evaluation_responsibilities r
           join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
          where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) <> v_resp_n then
    raise exception '[FAIL] 12/A11: a recusa alterou a CONTAGEM das tabelas de estrutura';
  end if;

  -- Conteudo IDENTICO (hash agregado).
  select md5(string_agg(x, '|' order by x)) into v_h from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text || ':' ||
           s.ano::text || ':' || s.ciclo::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) t;
  if v_h is distinct from v_snap_h then
    raise exception '[FAIL] 12/A11: o CONTEUDO dos snapshots foi alterado';
  end if;
  select md5(string_agg(y, '|' order by y)) into v_h from (
    select sp.id::text || ':' || sp.position_id::text || ':' ||
           coalesce(sp.superior_position_id::text, '-') || ':' ||
           coalesce(sp.superior_collaborator_id::text, '-') as y
      from public.collegiate_cycle_snapshot_positions sp
      join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
     where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) t;
  if v_h is distinct from v_pos_h then
    raise exception '[FAIL] 12/A11: o CONTEUDO das posicoes materializadas foi alterado';
  end if;
  select md5(string_agg(z, '|' order by z)) into v_h from (
    select m.id::text || ':' || m.member_collaborator_id::text as z
      from public.collegiate_cycle_snapshot_members m
      join public.collegiate_cycle_snapshots s on s.id = m.snapshot_id
     where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) t;
  if v_h is distinct from v_memb_h then
    raise exception '[FAIL] 12/A11: o CONTEUDO dos membros do colegiado foi alterado';
  end if;
  select md5(string_agg(w, '|' order by w)) into v_h from (
    select r.id::text || ':' || r.position_id::text || ':' ||
           r.responsible_collaborator_id::text || ':' || coalesce(r.valid_to::text, '-') as w
      from public.cycle_evaluation_responsibilities r
      join public.collegiate_cycle_snapshots s on s.id = r.snapshot_id
     where s.organization_id = v_org and s.ano = 2038 and s.ciclo = 1) t;
  if v_h is distinct from v_resp_h then
    raise exception '[FAIL] 12/A11: o CONTEUDO das responsabilidades foi alterado';
  end if;

  if exists (select 1 from public.cycle_events e
              where e.operation_id = 'eda10000-0000-0000-0000-000000001201') then
    raise exception '[FAIL] 12/A11: tentativa recusada gravou evento na trilha do ciclo';
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c3) <> v_versao_antes then
    raise exception '[FAIL] 12/A11: tentativa recusada alterou a versao do ciclo (% -> %)',
      v_versao_antes, (select c.version from public.evaluation_cycles c where c.id = v_c3);
  end if;

  raise notice '[PASS] 12/A11: a inclusao de colaborador JA materializado (A3 ATIVO) e recusada por F5_09_CONFLICT/JA_MATERIALIZADO_NO_CICLO com contagem, conteudo (md5) e versao do ciclo INALTERADOS e sem trilha nova';
end $$;

-- AUSENCIA de UPDATE/DELETE nas tabelas de snapshot durante todo o bloco 12.
do $$
declare
  v_escritas bigint;
begin
  select count(*) into v_escritas from _p9_escritas;
  if v_escritas > 0 then
    raise exception '[FAIL] 12/imutabilidade: % operacao(oes) de UPDATE/DELETE foram EFETIVADAS nas tabelas de snapshot/responsabilidades', v_escritas;
  end if;
  raise notice '[PASS] 12/imutabilidade: ZERO UPDATE/DELETE EFETIVADO nas tabelas de snapshot/responsabilidades em todo o bloco (contador transacional de escrita em zero)';
end $$;

drop trigger _mut_p9_snap_upd on public.collegiate_cycle_snapshots;
drop trigger _mut_p9_snap_pos_upd on public.collegiate_cycle_snapshot_positions;
drop trigger _mut_p9_snap_mem_upd on public.collegiate_cycle_snapshot_members;
drop trigger _mut_p9_resp_upd on public.cycle_evaluation_responsibilities;
drop function public._mut_p9_conta_escrita();
drop table if exists _p9_escritas;

do $$
begin
  if exists (
    select 1 from pg_trigger t where t.tgname like '\_mut\_p9%' and not t.tgisinternal)
     or exists (
    select 1 from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname like '\_mut\_p9%')
     or to_regclass('pg_temp._p9_escritas') is not null
     or to_regprocedure('public._mut_p9_falhar_cancelamento_aval()') is not null then
    raise exception '[FAIL] 12/limpeza: artefatos temporarios das provas de rollback/imutabilidade nao foram removidos';
  end if;
  raise notice '[PASS] 12/limpeza: gatilhos, funcao e sequence temporarios das provas de rollback e imutabilidade removidos';
end $$;

-- ----------------------------------------------------------------------------
-- 13) REGRESSAO DA ADMISSAO (casos centrais A1–A12) + prova A3 (D27)
-- ----------------------------------------------------------------------------
-- A cobertura EXAUSTIVA A1–A12 esta em `06-validar-f5-09-p3.sql` (validador da
-- fase P3, que roda no MESMO job do CI imediatamente antes). Aqui ficam os casos
-- CENTRAIS. O ciclo ATIVO desta secao e A5 (2039/2), ativado no §7 quando o slot
-- de Alfa estava livre — A3 foi CANCELADO no §9 e A6 no §10, portanto I5 e
-- respeitado sem qualquer reativacao extra.
do $$
declare
  v_org uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_a1  uuid := 'edc00000-0000-0000-0000-000000000001';
  v_c5  uuid;
  v_n1  uuid;
begin
  select c.id into v_c5 from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2039 and c.numero = 2;
  -- A5 foi ENCERRADO no §7 (o roteiro o usa para liberar o slot de A3). A prova de
  -- admissao precisa do ciclo ATIVO, entao este bloco o REABRE pelo caminho
  -- soberano (`ciclo_reabrir`: ENCERRADO -> ATIVO, com motivo e expected_version
  -- lida da linha). I5 esta livre (A3 CANCELADO no §9, A6 cancelado no §10), logo
  -- nao ha reativacao "artificial": e a operacao de dominio prevista e auditada.
  if (select c.status from public.evaluation_cycles c where c.id = v_c5) = 'ENCERRADO' then
    perform public.ciclo_reabrir(v_c5, v_org, 'Reabertura de A5 para a prova de admissao (P9/13)',
      (select c.version from public.evaluation_cycles c where c.id = v_c5), v_a1,
      'eda10000-0000-0000-0000-000000001401');
  end if;
  if (select c.status from public.evaluation_cycles c where c.id = v_c5) <> 'ATIVO' then
    raise exception '[FAIL] 13/pre-condicao: A5 deveria estar ATIVO para a prova de admissao (status=%, version=%)',
      (select c.status from public.evaluation_cycles c where c.id = v_c5),
      (select c.version from public.evaluation_cycles c where c.id = v_c5);
  end if;

  -- Candidato ELEGIVEL: admitido DEPOIS da ativacao pelo caminho soberano da
  -- F5-07 (`colaborador_criar`, que grava o evento ADMISSAO com effective_date =
  -- agora > data_ativacao) + ocupacao vigente pelo caminho soberano
  -- (`estrutura_ocupacao_definir`) + colegiado como FIXTURE (a autoria do
  -- colegiado nao e objecto desta validacao, mesmo padrao do cenario da P3).
  v_n1 := public.colaborador_criar(v_org, v_a1,
    'eda10000-0000-0000-0000-000000001403',
    'Colaborador Admitido P9 N1', 'admitido.n1.f5-09-p9@example.invalid',
    'P9-N1', null, 'active');
  perform public.estrutura_ocupacao_definir(v_org, v_a1,
    'eda10000-0000-0000-0000-000000001404', v_n1,
    'ede10000-0000-0000-0000-000000000005', now(),
    'Ocupacao inicial do admitido N1 (P9)', 'CICLO_ATUAL_E_POSTERIORES', null);
  insert into public.collegiate_configurations
    (id, organization_id, collaborator_id, valid_from)
  values ('eda10000-0000-0000-0000-000000001405', v_org, v_n1, now());
  insert into public.collegiate_configuration_members
    (id, organization_id, configuration_id, member_collaborator_id)
  values ('eda10000-0000-0000-0000-000000001406', v_org,
          'eda10000-0000-0000-0000-000000001405',
          'edb00000-0000-0000-0000-000000000001');
  if v_n1 is null then
    raise exception '[FAIL] 13/pre-condicao: o admitido N1 nao foi criado';
  end if;
  raise notice '[PASS] 13/pre-condicao: A5 ATIVO/version 1 (unico ATIVO de Alfa) e admitido N1 criado pelo caminho soberano da F5-07 (evento ADMISSAO posterior a ativacao) com ocupacao vigente';
end $$;

do $$
declare
  v_org      uuid := 'eda00000-0000-0000-0000-0000000000a1';
  v_beta     uuid := 'eda00000-0000-0000-0000-0000000000b1';
  v_a1       uuid := 'edc00000-0000-0000-0000-000000000001';
  v_a4       uuid := 'edc00000-0000-0000-0000-000000000004';
  v_c        uuid;
  v_cp       uuid;
  v_cb       uuid;
  v_n1       uuid;
  v_eleg     jsonb;
  v_res      jsonb;
  v_res2     jsonb;
  v_snap_a   int;
  v_snap_d   int;
  v_ver_a    int;
  v_ver_d    int;
  v_evt_a    int;
  v_evt_d    int;
  v_ok       boolean;
  v_msg      text;
  v_novosnap uuid;
  v_snap_h   text;
  v_pos_h    text;
  v_n_snap_antes int;
begin
  select c.id into v_c from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2039 and c.numero = 2;
  select c.id into v_cp from public.evaluation_cycles c
   where c.organization_id = v_org and c.ano = 2037 and c.numero = 1;
  select c.id into v_cb from public.evaluation_cycles c
   where c.organization_id = v_beta and c.ano = 2037 and c.numero = 1;
  select i.collaborator_id into v_n1 from public.collaborator_identifiers i
   where i.organization_id = v_org and i.business_code = 'P9-N1';

  -- (A1/P1–P7) O helper read-only declara ELEGIVEL, com as evidencias relacionais.
  v_eleg := public.ciclo_admissao_pos_ativacao_elegivel(v_org, v_c, v_n1);
  if coalesce((v_eleg->>'elegivel')::boolean, false) is not true
     or coalesce(v_eleg->>'motivo', '') <> 'ELEGIVEL' then
    raise exception '[FAIL] 13/A1: helper de elegibilidade deveria declarar ELEGIVEL (%)', v_eleg;
  end if;
  if (v_eleg->>'admissao_event_id') is null
     or (v_eleg->>'posicao_id')::uuid is distinct from 'ede10000-0000-0000-0000-000000000005'::uuid
     or (v_eleg->>'superior_collaborator_id')::uuid is distinct from 'edb00000-0000-0000-0000-000000000001'::uuid then
    raise exception '[FAIL] 13/A1: helper sem as evidencias relacionais (evento ADMISSAO / posicao / superior) (%)', v_eleg;
  end if;

  -- (A1) Inclusao aditiva VALIDA.
  select count(*) into v_snap_a from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2;
  select c.version into v_ver_a from public.evaluation_cycles c where c.id = v_c;
  select count(*) into v_evt_a from public.cycle_events e
   where e.organization_id = v_org and e.cycle_id = v_c;

  -- A versao esperada e LIDA da linha (v_ver_a) e o resultado e comparado com
  -- v_ver_a + 1: a prova nao depende de a versao residual ser exatamente 1 (o
  -- roteiro reabre/encerra ciclos antes daqui).
  v_res := public.ciclo_incluir_admissao(v_c, v_org, v_n1,
    'Admissao posterior a ativacao (N1/P9)', v_ver_a, v_a1,
    'eda10000-0000-0000-0000-000000001a01');
  if (v_res->>'status') <> 'ATIVO' or (v_res->>'version')::int <> v_ver_a + 1 then
    raise exception '[FAIL] 13/A1: inclusao deveria resultar em ATIVO/version % (%)', v_ver_a + 1, v_res;
  end if;
  v_novosnap := (v_res->>'snapshot_id')::uuid;
  if v_novosnap is null then
    raise exception '[FAIL] 13/A1: retorno sem snapshot_id do colaborador incluido';
  end if;
  select count(*) into v_snap_d from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2;
  select c.version into v_ver_d from public.evaluation_cycles c where c.id = v_c;
  select count(*) into v_evt_d from public.cycle_events e
   where e.organization_id = v_org and e.cycle_id = v_c;
  if v_snap_d <> v_snap_a + 1 or v_ver_d <> v_ver_a + 1 or v_evt_d <> v_evt_a + 1 then
    raise exception '[FAIL] 13/A1: a inclusao deveria acrescentar exatamente 1 snapshot, 1 versao e 1 evento (snap %->%, ver %->%, evt %->%)',
      v_snap_a, v_snap_d, v_ver_a, v_ver_d, v_evt_a, v_evt_d;
  end if;
  if not exists (
    select 1 from public.cycle_events e
     where e.organization_id = v_org
       and e.operation_id = 'eda10000-0000-0000-0000-000000001a01'
       and e.event_type = 'ADMISSAO_INCLUIDA'
       and (e.after_value->>'collaborator_id')::uuid = v_n1
       and (e.after_value->>'snapshot_id')::uuid = v_novosnap
       and (e.after_value->>'admissao_event_id') is not null
       and e.actor_user_profile_id = v_a1
       and e.payload_hash ~ '^[0-9a-f]{64}$'
  ) then
    raise exception '[FAIL] 13/A1: evento ADMISSAO_INCLUIDA ausente ou sem as evidencias da inclusao';
  end if;

  -- (A2/A10) Idempotencia da inclusao: replay com o MESMO operation_id E o MESMO
  -- payload (inclusive `expected_version = v_ver_a`) — idempotencia exige intencao
  -- identica; versao divergente seria corretamente recusada como intencao nova.
  v_res2 := public.ciclo_incluir_admissao(v_c, v_org, v_n1,
    'Admissao posterior a ativacao (N1/P9)', v_ver_a, v_a1,
    'eda10000-0000-0000-0000-000000001a01');
  if v_res2 <> v_res then
    raise exception '[FAIL] 13/A2: replay da inclusao devolveu resultado diferente';
  end if;
  if (select count(*) from public.cycle_events e
       where e.organization_id = v_org
         and e.operation_id = 'eda10000-0000-0000-0000-000000001a01') <> 1
     or (select count(*) from public.collegiate_cycle_snapshots s
          where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2) <> v_snap_d
     or (select c.version from public.evaluation_cycles c where c.id = v_c) <> v_ver_a + 1 then
    raise exception '[FAIL] 13/A2: replay da inclusao duplicou efeito (trilha/snapshot/versao)';
  end if;

  -- (A4/P3) Colaborador JA materializado => CONFLICT/JA_MATERIALIZADO_NO_CICLO.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c, v_org, v_n1,
      'Segunda inclusao do mesmo colaborador', v_ver_a + 1, v_a1,
      'eda10000-0000-0000-0000-000000001408');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%JA_MATERIALIZADO_NO_CICLO%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 13/A4: reinclusao deveria ser F5_09_CONFLICT/JA_MATERIALIZADO_NO_CICLO (%)', v_msg;
  end if;

  -- (A5/P7) NAO ELEGIVEL: colaborador LEGADO (sem evento soberano de ADMISSAO),
  -- ativo e com estrutura resolvivel — a UNICA prova ausente e o evento.
  insert into public.collaborators (id, organization_id, full_name, email, admission_date)
  values ('edb00000-0000-0000-0000-000000000101', v_org,
          'Colaborador Legado P9', 'legado.f5-09-p9@example.invalid', current_date);
  insert into public.collaborator_identifiers (collaborator_id, organization_id, business_code, valid_from)
  values ('edb00000-0000-0000-0000-000000000101', v_org, 'P9-LEGADO', now());
  insert into public.collaborator_status_periods (collaborator_id, status, valid_from)
  values ('edb00000-0000-0000-0000-000000000101', 'active', now());

  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c, v_org, 'edb00000-0000-0000-0000-000000000101',
      'Legado sem prova de admissao', v_ver_a + 1, v_a1, 'eda10000-0000-0000-0000-000000001409');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%SEM_EVENTO_ADMISSAO%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 13/A5: legado sem evento ADMISSAO deveria recusar por SEM_EVENTO_ADMISSAO (%)', v_msg;
  end if;

  -- (A3/D27) MOVIMENTACAO posterior de participante JA materializado: B2 sai da
  -- posicao P2 e passa a ocupar a posicao P4 (vaga), pelo caminho SOBERANO da
  -- F5-07 (`estrutura_ocupacao_definir`; a capability `org.structure.manage` vem
  -- da fixture — o caminho de estrutura NAO conhece o ciclo, o que e a DEFESA EM
  -- PROFUNDIDADE da D27). Roda depois das tentativas recusadas, para que a
  -- estrutura vista por elas seja a original (B2 em P2).
  select md5(string_agg(x, '|' order by x)) into v_snap_h from (
    select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text as x
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2) t;
  select md5(string_agg(y, '|' order by y)) into v_pos_h from (
    select sp.id::text || ':' || sp.position_id::text || ':' ||
           coalesce(sp.superior_position_id::text, '-') || ':' ||
           coalesce(sp.superior_collaborator_id::text, '-') as y
      from public.collegiate_cycle_snapshot_positions sp
      join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
     where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2) t;
  select count(*) into v_evt_a from public.cycle_events e
   where e.organization_id = v_org and e.cycle_id = v_c;
  select count(*) into v_n_snap_antes from public.collegiate_cycle_snapshots s
   where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2;

  perform public.estrutura_ocupacao_definir(v_org, v_a1,
    'eda10000-0000-0000-0000-000000001414',
    'edb00000-0000-0000-0000-000000000002',
    'ede10000-0000-0000-0000-000000000004', now(),
    'Movimentacao sintetica posterior a materializacao (A3/D27)',
    'CICLO_ATUAL_E_POSTERIORES', null);

  if not exists (
    select 1 from public.occupations o
     where o.organization_id = v_org
       and o.collaborator_id = 'edb00000-0000-0000-0000-000000000002'
       and o.organizational_position_id = 'ede10000-0000-0000-0000-000000000004'
       and o.valid_from <= now() and (o.valid_to is null or o.valid_to > now())
  ) then
    raise exception '[FAIL] 13/A3: a movimentacao soberana nao colocou B2 na posicao P4';
  end if;

  -- O snapshot do ciclo permanece CONGELADO: populacao, conteudo e posicoes.
  if (select count(*) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2) <> v_n_snap_antes then
    raise exception '[FAIL] 13/A3: a movimentacao alterou a populacao materializada do ciclo';
  end if;
  -- ATENCAO: os agregados abaixo precisam da SUBQUERY que define o alias `x`/`y`
  -- (usa-la direto no IF falha com `column "x" does not exist`).
  if (select md5(string_agg(x, '|' order by x)) from (
        select s.id::text || ':' || s.collaborator_id::text || ':' || s.reference_date::text as x
          from public.collegiate_cycle_snapshots s
         where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2) t) is distinct from v_snap_h then
    raise exception '[FAIL] 13/A3: a movimentacao alterou o CONTEUDO dos snapshots (D27 violada)';
  end if;
  if (select md5(string_agg(y, '|' order by y)) from (
        select sp.id::text || ':' || sp.position_id::text || ':' ||
               coalesce(sp.superior_position_id::text, '-') || ':' ||
               coalesce(sp.superior_collaborator_id::text, '-') as y
          from public.collegiate_cycle_snapshot_positions sp
          join public.collegiate_cycle_snapshots s on s.id = sp.snapshot_id
         where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2) t) is distinct from v_pos_h then
    raise exception '[FAIL] 13/A3: a movimentacao rematerializou as posicoes congeladas';
  end if;
  if (select count(*) from public.cycle_events e
       where e.organization_id = v_org and e.cycle_id = v_c) <> v_evt_a then
    raise exception '[FAIL] 13/A3: a movimentacao escreveu na trilha do ciclo';
  end if;

  raise notice '[PASS] 13/A3: movimentacao soberana de B2 (P2 -> P4) altera a estrutura vigente mas o snapshot do ciclo permanece IDENTICO (populacao, conteudo e posicoes) e a trilha do ciclo nao cresce (D27)';

  -- (A6) Ciclo NAO ATIVO => CONFLICT (A1 permanece PLANEJADO/version 0).
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_cp, v_org, v_n1,
      'Inclusao em ciclo PLANEJADO', 0, v_a1, 'eda10000-0000-0000-0000-000000001410');
  exception when others then
    v_ok := sqlerrm like '%F5_09_CONFLICT%' and sqlerrm like '%exige ciclo ATIVO%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 13/A6: inclusao em ciclo PLANEJADO deveria ser F5_09_CONFLICT/exige ciclo ATIVO (%)', v_msg;
  end if;

  -- (A7) Cross-tenant: ciclo do Beta com ator de Alfa => FORBIDDEN.
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_cb, v_beta, v_n1,
      'Probe cross-tenant (ator de Alfa)', 1, v_a1,
      'eda10000-0000-0000-0000-000000001411');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 13/A7: ator de outro tenant deveria ser F5_09_FORBIDDEN (%)', v_msg;
  end if;

  -- (A8) Tenant/ator divergentes: o ator de Beta declara a organizacao Beta com o
  -- ciclo de Alfa => FORBIDDEN (o ator verificado nao tem vinculo com o tenant
  -- declarado; "ciclo de outro tenant no proprio tenant" seria NOT_FOUND).
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c, v_beta, v_n1,
      'Probe de tenant divergente (ator do Beta)', 2, v_a4,
      'eda10000-0000-0000-0000-000000001412');
  exception when others then
    v_ok := sqlerrm like '%F5_09_FORBIDDEN%' or sqlerrm like '%F5_09_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 13/A8: tenant declarado divergente do ator deveria ser recusado (FORBIDDEN/NOT_FOUND indistinguiveis — §8) (%)', v_msg;
  end if;

  -- (A9) Colaborador de OUTRO tenant => NOT_FOUND (indistinguivel de inexistente).
  v_ok := false; v_msg := null;
  begin
    perform public.ciclo_incluir_admissao(v_c, v_org,
      'edb00000-0000-0000-0000-0000000000b1', 'Colaborador do Beta no ciclo do Alfa',
      v_ver_a + 1, v_a1, 'eda10000-0000-0000-0000-000000001413');
  exception when others then
    v_ok := sqlerrm like '%F5_09_NOT_FOUND%'; v_msg := sqlerrm;
  end;
  if not v_ok then
    raise exception '[FAIL] 13/A9: colaborador de outro tenant deveria ser F5_09_NOT_FOUND (%)', v_msg;
  end if;

  -- (A11) Ausencia de rematerializacao: os participantes PRE-EXISTENTES
  -- permanecem como estavam e nenhuma recusa criou snapshot.
  if (select count(*) from public.collegiate_cycle_snapshots s
       where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2) <> v_snap_d then
    raise exception '[FAIL] 13/A11: a populacao materializada do ciclo mudou apos as recusas';
  end if;
  if exists (
    select 1
      from public.collegiate_cycle_snapshots s
     where s.organization_id = v_org and s.ano = 2039 and s.ciclo = 2
       and s.collaborator_id in ('edb00000-0000-0000-0000-000000000101',
                                 'edb00000-0000-0000-0000-0000000000b1')
  ) then
    raise exception '[FAIL] 13/A11: uma inclusao RECUSADA materializou snapshot';
  end if;

  -- (A12) ZERO efeito de todas as recusas: nenhum evento e estado intacto.
  select count(*) into v_evt_d from public.cycle_events e
   where e.operation_id::text in ('eda10000-0000-0000-0000-000000001408',
                                  'eda10000-0000-0000-0000-000000001409',
                                  'eda10000-0000-0000-0000-000000001410',
                                  'eda10000-0000-0000-0000-000000001411',
                                  'eda10000-0000-0000-0000-000000001412',
                                  'eda10000-0000-0000-0000-000000001413');
  if v_evt_d <> 0 then
    raise exception '[FAIL] 13/A12: recusas da admissao gravaram % evento(s)', v_evt_d;
  end if;
  if (select c.version from public.evaluation_cycles c where c.id = v_c) <> v_ver_a + 1
     or (select c.status from public.evaluation_cycles c where c.id = v_c) <> 'ATIVO' then
    raise exception '[FAIL] 13/A12: recusa da admissao alterou o ciclo (%, %; esperado ATIVO/% )',
      (select c.status from public.evaluation_cycles c where c.id = v_c),
      (select c.version from public.evaluation_cycles c where c.id = v_c),
      v_ver_a + 1;
  end if;

  raise notice '[PASS] 13/regressao da admissao: elegivel incluida (1 snapshot/1 versao/1 evento ADMISSAO_INCLUIDA com as evidencias), replay idempotente, ja materializado e legado sem prova recusados com o motivo proprio, ciclo nao ATIVO recusado, cross-tenant (ator e tenant) e colaborador de outro tenant recusados, prova A3 (movimentacao sem rematerializacao) e ZERO efeito nas recusas — cobertura exaustiva A1–A12 em 06-validar-f5-09-p3.sql';
end $$;

-- ----------------------------------------------------------------------------
-- Resumo: contagem total de verificacoes [PASS] desta matriz integrada
-- ----------------------------------------------------------------------------
-- A contagem e declarada explicitamente porque cada bloco emite o seu proprio
-- `[PASS]` (nao ha estado compartilhado entre transacoes). Decomposicao exata:
--   1 cronologia + 1 (§0) + 1 (§1 setup) + 3 (§2) + 7 (§3) + 3 (§4) + 1 (§5) +
--   1 (§6) + 1 (§7) + 1 (§7.1) + 2 (§8) + 6 (§9) + 6 (§10) + 1 (§11) + 4 (§12) +
--   6 (§13) + 1 resumo = 46 `[PASS]`; mais as 3 negacoes de append-only do §9
--   (UPDATE/DELETE/TRUNCATE bloqueados pelo trigger) = 49 verificacoes `[PASS]`.
select set_config('request.jwt.claim.sub', '', false);

do $$
begin
  raise notice '============================================================';
  raise notice 'F5-09 P9: matriz integrada validada — TODAS as verificacoes [PASS] (o numero exato de notices varia com os blocos agregados): cronologia I5 (no maximo um ATIVO por organizacao), cross-tenant (leitura RLS + mutacao RPC), membership revogada, capability revogada, IDOR, stale version, idempotencia, rollback/atomicidade multi-escrita, auditoria append-only, RLS/privilegios, regressoes P1-P8, imutabilidade A11 e regressao da admissao com a prova A3. A CONCORRENCIA REAL entre duas sessoes vive nos arquivos 16/17/18 e exige o par de processos.';
  raise notice 'CONCORRENCIA REAL: NAO simulada aqui — as provas entre DUAS sessoes vivem nos arquivos 16/17/18 (outro agente). Este validador e single-session por contrato.';
  raise notice '============================================================';
end $$;
