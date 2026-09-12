# Virtus — Handoff (contexto operacional de retomada)

> Registro **operacional e estável** para retomada entre agentes/sessões.
> **Não copie** dados pessoais, segredos, credenciais, tokens, chaves ou
> informações corporativas sensíveis. Referencie Issues/PRs/documentos em vez de
> transcrever conteúdo. GitHub continua sendo a fonte de verdade do andamento.

## 1. Como retomar uma atividade interrompida

1. Leia `AGENTS.md` e `AGENTS.md` → `.ai/*` (ordem de `.ai/virtus-context.md`).
2. Leia **este arquivo** — seção 3 (registro de estado) — para saber onde a
   última entrega parou.
3. Confirme no GitHub (fonte de verdade) a Issue, o PR e o estado real da branch.
4. Em paralelo ao registro, verifique localmente com:

```bash
git status -sb        # branch atual, ahead/behind de origin
git log --oneline -3  # últimos commits locais
git diff --stat       # alterações não commitadas
```

5. Se um push falhou pela limitação conhecida (`.ai/git-rules.md`), o trabalho
   está **commitado localmente** e aguarda o usuário executar o push; não refaça
   e não tente contornar.

## 2. Instrução permanente de manutenção

A cada entrega (concluída ou interrompida), **atualize a seção 3** com o novo
estado e remova entradas obsoletas. Mantenha apenas contexto operacional:
branch, SHA, PR, atividade e próximos passos. **Nunca** adicione segredos,
credenciais, conteúdo real de pessoas/empresa ou trechos de documentos aqui.

## 3. Registro de estado (última entrega)

> Atualizar ao final de cada atividade.

- **Atividade (rodada atual):** F5-09 — **P1 (integridade de schema e trilha de
  auditoria) IMPLEMENTADA** — **aguardando auditoria GPT**. Contrato:
  `docs/F5-09-desenho-tecnico.md` (§19 P1; D1–D28 ratificadas) e
  `docs/F5-09-duvidas.md`.
- **Base:** `main`/`origin/main` = `27f4bb0f91f8c34c26417f3df4d40485d775d0f1`
  (desenho F5-09 integrado pelo PR #189).
- **Branch da P1:** `feat/f5-09-p1-cycle-schema` — **sem merge**; o push/PR do
  sandbox é bloqueado (`.ai/git-rules.md`), então o PR fica para o usuário.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Entregue nesta rodada (P1) — 5 arquivos:**
  - `supabase/migrations/20260915000000_f5_09_cycle_sovereign.sql`: **I5** índice
    único parcial `uq_evaluation_cycles_org_ativo` (um ciclo `ATIVO` por
    organização); **I6** exclusion parcial
    `ex_evaluation_cycles_periodo_no_overlap`
    (`daterange(data_inicio, data_fim + 1, '[)')` — `data_fim` inclusiva para o
    produto —, com `CANCELADO` e linhas sem período fora do índice); `DELETE` e
    `TRUNCATE` de `evaluation_cycles` revogados de
    `public`/`anon`/`authenticated`/`service_role` (**D8/D9** — exclusão física
    proibida em todos os estados); trilha append-only **`cycle_events`** (FK
    composta `(cycle_id, organization_id)`, FK composta de autoria, `unique
    (organization_id, operation_id)` para idempotência, `payload_hash` SHA-256
    hex, CHECKs de `entity_type`/`event_type` — já contemplando
    `ADMISSAO_INCLUIDA` do P3 —, trigger de UPDATE negado, RLS deny-by-default
    integral com `service_role` recebendo só `SELECT`/`INSERT`); helpers
    `ciclo_ator_valido` (perfil + membership ativa + allowlist FECHADA das
    capabilities de ciclo, reusando `evaluation_ator_valido` e
    `resolver_capabilities_efetivas`) e `ciclo_lock_organizacao` (chave
    **normativa** única da família: `evaluation_cycles:<organization_id>`);
    pre-flight de baseline fail-closed (não corrige dados) e guarda final
    fail-closed. **Sem RPCs `ciclo_*`** (P2+) e **sem policy de leitura** (P5).
  - `supabase/validacao/01-cenario-f5-09.sql`: fixture determinística e
    reexecutável (2 orgs; 7 ciclos — adjacência de período, `CANCELADO`
    sobreposto, ciclo sem período e o mesmo período em outro tenant; atores com e
    sem capability, membership e perfil desabilitados; 1 evento de trilha).
  - `supabase/validacao/02-validar-f5-09.sql`: validador do P1 (schema do
    contrato, I5/I6 por comportamento, `data_fim` inclusiva por adjacência,
    exclusão física negada por ACL **e** por comportamento, `cycle_events`
    completo — incluindo idempotência e FKs de tenant —, append-only em duas
    camadas, helpers, lock e regressão F5-06/F5-07/F5-08).
  - `.github/workflows/ci.yml`: o job `supabase-local` passou a executar
    `01-cenario-f5-09.sql` + `02-validar-f5-09.sql` **antes** da regressão
    F5-06/F5-07.
  - `supabase/migrations/README.md`: registro da migration da P1.
- **NÃO entregue (fora do P1, por contrato — nada antecipado):**
  `ciclo_criar`/`ciclo_editar`/`ciclo_ativar`/`ciclo_encerrar` (P2),
  `ciclo_incluir_admissao` + helper de elegibilidade da admissão (P3),
  `ciclo_cancelar`/`ciclo_reabrir`/`ciclo_corrigir_periodo` (P4), leitura RLS +
  porta/projeção do cliente (P5), Policy Engine (P6), Edge `ciclos` +
  reconciliação do bundle `admin` (P7), cutover (P8) e validação integrada (P9).
  Nenhuma capability nova e nenhum arquivo de `src/` alterado.
- **Gates desta rodada:** `npm test` (**108 arquivos / 1677 testes**, exit 0),
  `npm run build` (exit 0), `npm run lint` (exit 0),
  `npx tsc -b tsconfig.app.json` (exit 0) e `git diff --check` (exit 0). Os
  **validadores SQL NÃO foram executados neste host**: o daemon do Docker Desktop
  está inacessível (`permission denied ... npipe:////./pipe/dockerDesktopLinuxEngine`,
  com timeout inclusive sob elevação), então `supabase db reset` + `01/02` rodam
  no job `supabase-local` do CI — limitação registrada, nunca mascarada como
  verde.
- **Próxima atividade:** auditoria GPT do P1; depois **P2** (RPCs de gestão do
  ciclo), sem decisão arquitetural aberta.
- **Correção pós-CI (PR #190, mesma branch):** o job `supabase-local` falhava no
  validador **legado** `supabase/validacao/02-validar-f4-08.sql` **antes** dos
  validadores da F5-09, com
  `[FAIL] tabela public nao classificada (D16 — catalogacao explicita
  obrigatoria): cycle_events` — o schema guard global do F4-08 exige catalogação
  explícita de toda tabela `public` e ainda não conhecia a tabela nova. Correção
  **mínima e sem relaxar contrato**: `cycle_events` foi classificada como
  **tabela fechada** (RLS habilitada, **sem policy**, **sem SELECT/INSERT/UPDATE/
  DELETE** para `authenticated`/`anon`, `service_role` apenas `SELECT`/`INSERT`,
  append-only) em todas as listas/contadores do F4-08 — `v_closed` (policy, 22→23),
  `v_closed` (SELECT, 22→23), anon `v_todos` (44→45), DML `v_todos` (44→45), schema
  guard (44→45) e a lista comportamental de tabelas fechadas invisíveis (22→23) —
  e nas **duas cópias** da lista de classificação do
  `03-validar-f4-08-mutacoes.sql` (mutação B). `collaborator_events` permanece na
  categoria especial dele (policy SELECT own-tenant sem grant). A migration da P1
  **não** foi alterada e nenhuma regra da F5-09/P1 foi relaxada (contagem total de
  policies segue 22: `cycle_events` não tem policy no P1).

### 3.6 F5-09 — desenho técnico (rodada anterior, integrada pelo PR #189)

> Histórico do contrato; **não** é o estado atual da atividade (ver §3 acima).

- **Atividade:** F5-09 — **Ciclos soberanos** — **DESENHO
  TÉCNICO revisado** (`docs/F5-09-desenho-tecnico.md`, D1–D28 e fases P1–P9) com o
  registro de ratificação em `docs/F5-09-duvidas.md`
  (Q-F5-09-1..3 **RATIFICADAS**; nenhuma dúvida aberta).
- **Base:** `main`/`origin/main` = `6550c81d14a9d3e61b3c1b4f49471948f880bbc8`
  (F5-08 P6 integrado, PR #188; baseline esperado da F5-09 conferido).
- **Branch do desenho:** `docs/f5-09-ciclos-soberanos` — **sem PR** nesta rodada;
  **somente documentação**: nenhuma migration, RPC, Edge Function, capability,
  policy, teste de runtime ou alteração de frontend entrou nesta rodada.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Entregue nesta rodada (desenho F5-09):**
  - autoridade soberana do ciclo reusa `public.evaluation_cycles` (F5-06 D15) de
    forma **aditiva** — nenhuma tabela concorrente de ciclo/estrutura/versão;
  - identidade canônica = `evaluation_cycles.id` (UUID); `(ano, numero)` é apenas
    rótulo humano e regra de unicidade (`uq_evaluation_cycles_org_ano_numero`); a
    ponte `(ano, numero) → UUID` (`evaluation_resolver_ciclo` e o mapa de
    `assignedSupabase.ts`) permanece só como INTENÇÃO na fronteira confiável, com
    condição de remoção registrada;
  - máquina de estados sobre os quatro estados já existentes, com origem,
    destino, capability, pré-condições, efeitos transacionais e reversibilidade
    por transição; `CANCELADO` terminal; encerramento **reusa**
    `evaluation_fechar_ciclo_pendencias`; cancelamento resolve as avaliações não
    concluídas na mesma transação;
  - estrutura por ciclo = snapshot F3-08 + responsabilidades F3-09 + congelamento
    de participantes da F5-06 (congelada na ativação; hierarquia sempre relacional,
    nunca texto);
  - integridade nova no banco: índice único parcial de ciclo `ATIVO` por
    organização, exclusion de sobreposição de períodos (meio-aberto), trilha
    append-only `cycle_events` com `unique (organization_id, operation_id)` +
    `payload_hash`, chave normativa de advisory lock por organização;
  - autorização **sem capability nova** (`cycle.read`, `cycle.manage`,
    `cycle.cancel`, `cycle.reopen`, `cycle.period.correct`), Edge nova
    `supabase/functions/ciclos` (namespace `cycle.*`) e RPCs `ciclo_*`
    (SECURITY INVOKER, EXECUTE só `service_role`);
  - leitura soberana por RLS own-tenant (`user_has_active_membership`) + grant de
    SELECT a `authenticated`; escrita do cliente permanece fechada (deny-by-default);
  - cutover do cliente classificado A/B/C/D para os **21 arquivos** que hoje leem
    ou escrevem ciclo local;
  - fecha a pendência declarada da F5-07 (filtro de histórico do colaborador por
    ciclo) usando `collaborator_events.reference_cycle_id`;
  - **duas lacunas de contrato identificadas e endereçadas de forma aditiva:**
    `cycle.read`/`cycle.manage` caem hoje no `default → null` do
    `authorizationPolicy.ts` (⇒ DENY) e nenhuma role de sistema concede
    `cycle.manage` (o bundle `admin` tem só `cycle.read`) — resolvida pela **D28**
    (reconciliação aditiva do catálogo no P7).
- **Revisão 2 desta rodada (RATIFICAÇÃO incorporada):** a auditoria GPT do desenho
  ratificou as três dúvidas e o contrato foi revisado de ponta a ponta — **zero
  dúvida bloqueante aberta**:
  - **Q-F5-09-1 (alternativa A)** — `PLANEJADO→CANCELADO` permitido com
    `cycle.cancel`, motivo obrigatório, autoria soberana, trilha append-only,
    `expected_version` e idempotência; `CANCELADO` terminal; **exclusão física
    proibida em todos os estados** (D8/D9; ampliação aditiva do `domainState` e da
    descrição da capability, sem capability nova);
  - **Q-F5-09-2 (regra híbrida)** — a estrutura do ciclo **não** é "congelamento
    absoluto" nem rematerialização genérica: população inicial materializada na
    ativação, **admissões posteriores elegíveis podem ser acrescentadas** por
    operação soberana, explícita, auditada e **exclusivamente aditiva** (D26), com
    snapshots existentes **imutáveis** e movimentações de posição/unidade/gestor/
    reporting line/colegiado valendo **no próximo ciclo** (D27);
  - **Q-F5-09-3 (alternativa A)** — `cycle.manage` entra **aditivamente** no bundle
    `admin`; `cycle.cancel`/`cycle.reopen`/`cycle.period.correct` permanecem fora
    do bundle, só por configuração explícita (D28, executada no P7).
- **Inclusão aditiva de nova admissão (D26) — onde ficou:** operação restrita
  `cycle.admissao.incluir` / RPC `ciclo_incluir_admissao` + helper read-only
  `ciclo_admissao_pos_ativacao_elegivel`, na fase **P3**. A prova de "nova
  admissão" é **soberana** (nunca flag do cliente): evento append-only
  `collaborator_events.event_type = 'ADMISSAO'` com
  `cycle_scope = 'CICLO_ATUAL_E_POSTERIORES'` e `effective_date > data_ativacao`,
  mais ausência de período de status anterior à ativação em
  `collaborator_status_periods`; a coluna declarada
  `collaborators.admission_date` **não** é prova. Sem prova ⇒ **recusa**
  (fail-closed), registrada como requisito técnico da implementação (§7.2/R15) —
  a regra não é flexibilizada. O contrato **não** tem parâmetro estrutural algum e
  impede por construção sobrescrever snapshot, trocar posição, recalcular gestor
  ou colegiado, inclusão cross-tenant e uso genérico como "atualizar estrutura".
- **Plano revisado:** **P1–P9** (a fase nova **P3** existe para a inclusão aditiva
  e a reconciliação do catálogo ficou no **P7**); D1–D28. **(Estado atual: P1
  implementada — ver §3.)**
- **`.ai/current-task.md`:** não existe neste repositório (nem no histórico). A
  ausência é registrada aqui conforme `AGENTS.md` §1; o estado operacional de
  retomada continua sendo este arquivo.

### 3.5 F5-08 (concluída e integrada)

- **Atividade:** F5-08 — Estrutura organizacional e catálogos soberanos (contrato
  em `docs/F5-08-desenho-tecnico.md`, D1–D25). P1–P6 integrados em `main`; o
  squash do P6 (cutover estrutural) é `6550c81` (PR #188) — a antiga branch
  `feat/f5-08-p6-cutover-estrutura` está encerrada e **nada da F5-08 foi
  transferido para a F5-09** (a F5-09 só assumiu o domínio de ciclos).
- **Entregue (P1–P5, na base):** migrations `20260914000000`
  (`structure_events` append-only + triggers I1–I3 + grants), `20260914010000`
  (15 RPCs `estrutura_*`/`catalogo_*`) e `20260914020000` (chave única de advisory
  lock, D24); contrato/Edge `supabase/functions/colaboradores`; porta/serviço do
  cliente (`services/colaboradoresSoberanos/acessoColaboradoresSoberanos.ts`),
  leitura soberana por RLS
  (`infrastructure/supabase/estrutura/repositorioEstruturaSoberana.ts`); telas
  Unidades/Posições/Catálogos/Colegiado e alocação do colaborador (ocupação +
  reporting line).
- **Entregue nesta rodada (P6 — cutover estrutural):**
  - `authorizationPolicy.ts`: fallback do mundo funcional para o cadastro local
    **removido**; resta apenas sob barreira explícita de DEV
    (`simulacaoDevPermitida`) ⇒ produção fail-closed;
  - `mundoFuncional.ts`: `SEM_BINDINGS_DEV` — a derivação local de bindings deixou
    de ser implícita; sem binding explícito (teste) ou da projeção soberana, a
    capability é NEGADA (inclusive o fluxo SELF);
  - `historicoOrganizacionalStorage.ts`: sem promoção de texto `respondePara` a
    relação de gestão (escrita local é barreira desde a F5-07);
  - `src/data/evaluationTeam.ts` removido (código morto, sem consumidores);
  - guardas do cutover: bloco P6 em
    `src/authorization/estruturaUiSeguranca.test.ts` (sweep global de `src/`) e
    `src/authorization/cutoverEstrutural.test.ts` (runtime, produção × DEV);
  - `supabase/validacao/03-validar-f5-08-cutover.sql` (leitura RLS own-tenant
    positiva/negativa, fail-closed sem membership ativa, superfície de escrita do
    cliente fechada, capability negada, RPC como única autoridade, chave única de
    serialização, idempotência e histórico preservado);
  - `.github/workflows/ci.yml`: o job `supabase-local` passa a executar os **três**
    validadores da F5-08 e a regressão F5-06/F5-07 (§13.7/§23.4); timeout 40 min.
- **Blockers da auditoria RESOLVIDOS (correção nesta branch):** o §19.1 do
  contrato exige que as decisões de elegibilidade/papel de `progressoAvaliacao`,
  `cicloEquipeService` e `metaStorage` usem estrutura SOBERANA — não era decisão
  futura da F5-09. Duas rodadas de correção, sem criar fonte nova (sem
  migration/RPC/Edge/capability):
  - **1ª rodada:** `src/services/projecaoEstruturalSoberana.ts` como fronteira; os
    três módulos + `permissaoAvaliacao.ts` + `MinhaAvaliacaoDetalhePage.tsx`
    deixaram de ler `funcao`, `gestorDiretoMatricula`,
    `avaliadoresColegiadoMatriculas` e `getColaboradoresVisiveis`;
    `authorization/providers/localWorld.ts` virou DEV-only (fora do gate ⇒ mundo
    vazio ⇒ DENY); fail-closed em todas as decisões.
  - **2ª rodada (blockers finais):** a projeção passou a ser **UUID-first** —
    `collaboratorId`, `gestorSoberanoPositionId`, `cadeiaDeGestaoPositionIds`,
    `cadeiaDeGestaoCollaboratorIds`, `colegiadoSoberanoCollaboratorIds` — e o
    modelo **não conhece matrícula**; o campo textual `papel`
    (GERENTE/COORDENADOR/OUTRO) foi **eliminado** e substituído por fatos
    relacionais soberanos (`temCadeiaDeGestaoSoberana`,
    `gestorSoberanoTemSuperior`, `raizDaCadeiaSoberana`, `colegiadoSoberano`);
  - **PRODUTOR conectado:** `src/services/estruturaSoberanaCliente.ts` carrega a
    estrutura pelo caminho normal já existente (`lerEstrutura` RLS/P4 +
    `listarColaboradores` F5-07), publica a projeção e mantém a **ponte de
    compatibilidade** matrícula ↔ UUID (fronteira, nunca chave estrutural);
    `src/pages/useEstruturaSoberanaDoCliente.ts` é acionado pelo shell
    autenticado (`LayoutFuncional` em `src/routes/AppRoutes.tsx`) — nenhum
    consumidor injeta projeção manualmente e a ausência de injeção deixou de ser
    "modo DENY";
  - **Blocker final (corrida/multi-tenant) RESOLVIDO:** o produtor deixou de
    deduplicar A e B como se fossem a mesma solicitação. Agora há **geração
    monotônica** (`let geracao = 0`) + organização vigente: uma carga só publica
    se ainda for a vigente (`publicarSeVigente`); iniciar uma carga publica
    imediatamente `carregando` com estrutura VAZIA (a estrutura do tenant anterior
    deixa de ser acessível na troca); a dedupe é **por organização**; e
    `invalidarEstruturaSoberana()` (usada pelo hook quando a organização ativa
    vira `null`/`undefined`) incrementa a geração, limpa a carga em curso e
    publica estado inválido/vazio — resposta antiga nunca republica;
  - **Residual final (unmount/logout) RESOLVIDO:** o hook ganhou um cleanup de
    **dependência VAZIA** (`useEffect(() => () => invalidarEstruturaSoberana(), [])`)
    que roda **apenas no unmount** do shell — o `LayoutAutenticado` pode parar de
    renderizar o `LayoutFuncional` sem passar por `organizacaoAtivaId == null`;
    sem ele, a estrutura do tenant A permanecia em memória após o logout e um
    login posterior em B podia observá-la antes do novo efeito executar. Não roda
    em re-render nem na troca A → B (que tem caminho próprio);
  - provas: `projecaoEstruturalSoberana.test.ts` (8), `estruturaSoberanaCliente.test.ts`
    (19 — corrida A→B determinística nos dois sentidos, dedupe por org, `null`
    invalidando contexto, falha real sem vazar outro tenant e lifecycle do shell:
    unmount invalida + assinatura removida, carga em voo não publica, novo login
    em B nunca vê A, A→B sem unmount segue funcionando),
    `cutoverEstruturalServicos.test.ts` (4) e o bloco estático
    `estruturaUiSeguranca.test.ts` (39 no arquivo), que reprova modelo com
    matrícula, consumidores lendo campos locais, produtor não acionado, produtor
    sem proteção de troca de tenant e hook sem cleanup de unmount;
  - `docs/F5-08-p6-duvida-mundo-funcional.md` documenta os blockers resolvidos, a
    identidade UUID, a segurança multi-tenant (§2.3), o fail-closed e o que resta
    à F5-09 (apenas o domínio de ciclos: persistência e estrutura POR CICLO) — sem
    autoridade estrutural local.
- **Residual declarado (fora do blocker, não silencioso):** `relatorioService`
  (filtros por `gestorDiretoMatricula`), `exportarAvaliacaoPdf` (identificação de
  avaliadores), `visibilidadeColaboradores` (sem chamador de produção) e
  `historicoOrganizacionalStorage` (snapshots/efetivos). Registrado na §6 do
  documento acima; exige atividade própria (relatórios/PDF).
- **Consequência do cutover (verificada):** em produção a estrutura de
  ciclo/metas é obtida da leitura soberana (RLS) pelo produtor publicado no shell
  autenticado, sempre correspondendo à **organização ativa** (troca de tenant
  segura); falha real do Supabase ⇒ fail-closed, e a decisão real de autorização
  permanece server-side (Edge + Policy Engine + RLS). Coberto por
  `cutoverEstrutural.test.ts`, `cutoverEstruturalServicos.test.ts`,
  `projecaoEstruturalSoberana.test.ts` e `estruturaSoberanaCliente.test.ts`.
- **Validação então registrada (branch do P6):** `npm test` (**108 arquivos /
  1677 testes** verdes), `npm run build`, `npm run lint`,
  `npx tsc -b tsconfig.app.json` e `git diff --check` executados localmente
  (todos verdes). Os **validadores SQL não foram executados** naquele host
  (Docker/Supabase indisponível) — rodam no job `supabase-local` do CI; a
  limitação está registrada no relatório da atividade. Nenhuma
  migration/RPC/Edge/capability nova foi criada no P6.

### 3.1 F5-07 (concluída e integrada)

- **Atividade:** F5-07 — Colaboradores e histórico organizacional soberanos
  (contrato em `docs/F5-07-desenho-tecnico.md`, D1–D20); integrada em `main` como
  `7137f1f`.
- **Entregue:** migrations `20260913000000`/`20260913010000` (extensões aditivas em
  `collaborators`, `job_roles.code`, log append-only `collaborator_events`, helper
  de ator e 16 funções/RPCs), Edge `colaboradores` (15 operações, com gate
  funcional no Policy Engine e gate administrativo da F5-04 **separados**), porta
  única `acessoColaboradoresSoberanos`, barreiras fail-closed em
  `colaboradorStorage`/`historicoOrganizacionalStorage`, telas migradas para UUID
  com matrícula resolvida no servidor e remoção do código morto.
- **Validação então registrada:** `npm test` 94 arquivos / 1346 testes; `build`,
  `lint` e `git diff --check` verdes; validadores SQL após `db reset` — F5-07
  (44 PASS + 22 PASS de cutover), F4-08 (56 + 8) e F5-06 (25 + 13).
- **Limites assumidos:** alocação/estrutura (cargo, área, função, senioridade,
  gestor, colegiado) é **F5-08** — a F5-07 não fabrica estrutura sintética e as
  telas exibem "sem alocação". Ciclos/metas/observações seguem legados.
- **Defeito PREEXISTENTE em `main`, não corrigido (fora de escopo):** a Edge
  `supabase/functions/avaliacoes/index.ts:8` importa
  `src/authorization/catalogoCapacidades.ts` (inexistente; o módulo real é
  `catalogoCapabilities.ts`), o que impede o bundle da função F5-06. Não afeta
  `npm test`/`build`/`lint`/`tsc` (apenas o bundle Deno da Edge).

### 3.2 BUG #170 (concluída e integrada)

- **Atividade:** BUG #170 — item "Ciclos" duplicado no menu para Gerente e
  Coordenador (Issue #170). Correção de **navegação/UX**, integrada em `main`.
- **Branch:** `fix/170-ciclos-menu-duplicado`.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Causa raiz:** `NavegacaoPrincipal` tinha DOIS gates de menu para o MESMO
  assunto — `cycle.management.view` (`/ciclos`) e `cycle.coordinator.list`
  (`/painel-ciclos`). Ambos são **aliases da mesma capability canônica**
  (`cycle.read`, colapso Q1 da F4-09 em `authorization/canonical.ts`), e Gerente e
  Coordenador possuem `cycle.read`: as duas condições ficavam verdadeiras ao mesmo
  tempo e o menu renderizava dois itens consecutivos rotulados "Ciclos" (ambos com
  `IconCalendar`). Antes da centralização F4 os gates eram
  `funcao === "GERENTE"` / `funcao === "COORDENADOR"` — mutuamente exclusivos —,
  por isso o rótulo repetido nunca aparecia.
- **Correção:** UM ÚNICO item "Ciclos" → `/ciclos`, gated pela capability canônica
  `cycle.read` (visibilidade de menu é UX; o resource `{ kind: "global" }` é
  transitório e nunca prova de autorização). Rotas, capabilities, roles, RLS e
  contratos F4/F5 intactos. `/painel-ciclos` permanece rota autorizada e
  alcançável por "Minha equipe" (Início → `ColaboradoresPage`, botão do
  COORDENADOR). Teste novo `src/components/NavegacaoPrincipal.test.tsx` (13 casos)
  fixa o invariante de UM item por contexto e o menu completo de Gerente,
  Coordenador, Analista, Consultor, Estagiário e colaborador sem função.
- **Validação desta rodada (todo exit 0):** `npm test` (85 arquivos, 1082 testes),
  `npm run build`, `npm run lint`, `git diff --check origin/main...HEAD`.

### 3.3 DEV-02 (concluída e integrada)

- **Atividade:** DEV-02 — reduzir interrupções por elevação de acesso dos agentes
  (Issue #177). Somente camada de contexto; sem alteração funcional.
- **Integração:** `main` no SHA `e098754…` (PR #178).
- **Regra registrada:** `.ai/workflow.md` **§6**, com síntese permanente em
  `AGENTS.md` **§4**: aprovação técnica/arquitetural ≠ autorização de elevação de
  acesso; com desenho FECHADO não se repete pedido de aprovação; trabalho em lote
  com autoauditoria estática antes dos comandos privilegiados; comandos que exigem
  elevação agrupados em um ou poucos gates; proibido alterar PAT/credenciais/
  configurações ou reduzir controles.
- **Limitação do ambiente (registrada):** neste host o sandbox exige elevação
  (`danger-full-access`) até para comandos triviais (`git status`, `npm test`,
  `lint`) e para Docker/Supabase — agrupar operações por gate e registrar a
  limitação, nunca contornar a proteção (`.ai/git-rules.md` §3;
  `.ai/workflow.md` §6.4).

### 3.4 F5-06 (concluída e integrada)

- **Atividade:** F5-06 — Avaliações no PostgreSQL (Issue #103).
- **Branch:** `feat/f5-06-avaliacoes-postgresql` — **squash merge em `main`** como
  `f540f0f5d16a4b3f33a99f7e4f0e8fb7c5c30584` (PR #176, `Closes #103`); a cabeça do
  PR auditada foi `a11687e…`, com a correção final de whitespace em `c38de2b…`.
- **PR:** #176 — fechado e integrado. Este agente **não** declara a atividade
  aprovada: a aprovação é da auditoria independente.
- **Estado — SQL, fronteira e caminho TS (completo e validado):** migrations
  F5-06 (schema, funções e `20260911020000_f5_06_cutover_leitura_e_ciclo.sql`),
  Edge Function `avaliacoes`, policy/capabilities, ponte matrícula → UUID,
  resolução ano+ciclo, painel do participante e `cutoverAvaliacoesService`.
- **Estado — CUTOVER DAS TELAS (concluído nesta rodada):** nenhuma avaliação
  NOVA é criada/editada/cancelada/reaberta em `localStorage`; a autoridade é o
  PostgreSQL pelo caminho soberano.
  - Telas migradas: `NovoFeedbackPage` (criação + notas/observações/comentário
    final), `EditarFeedbackPage` (leitura do painel + gravação soberana +
    conclusão), `FeedbackDetalhePage` (cancelar/reabrir soberanos),
    `CiclosAvaliacaoPage` (ativação e encerramento).
  - Serviços migrados: `cancelamentoAvaliacaoService`,
    `reaberturaAvaliacaoService`, `cicloEquipeService`
    (`criarAvaliacoesDoCicloAtivado` e `concluirAvaliacoesNoEncerramentoDoCiclo`
    agora **async** e soberanos).
  - Novos módulos: `src/services/acessoAvaliacoesSoberanas.ts` (porta única das
    telas; nenhuma página importa Supabase) e `src/services/origemAvaliacaoTela.ts`
    (FONTE ÚNICA da decisão de origem, por EVIDÊNCIA de cutover).
  - Síncrono → assíncrono: `criarAvaliacoesDoCicloAtivado`,
    `concluirAvaliacoesNoEncerramentoDoCiclo`, `cancelarAvaliacao`,
    `reabrirAvaliacao` e os handlers das quatro telas (com estados de
    processamento/erro preservados).
  - `feedbackStorage` é **somente leitura** para o legado: `saveFeedback` foi
    removida; `updateFeedback`, `persistirCancelamentoAuditadoInterno`,
    `persistirReaberturaAuditadaInterno` e `removerAvaliacaoVaziaNoCleanupInterno`
    existem apenas como barreiras que lançam (fail-closed). Exclusão de ciclo com
    avaliação vazia no legado agora é recusada — a limpeza do legado pertence à
    atividade de importação (fora do escopo, §1.3).
- **Estado — CORREÇÕES PÓS-AUDITORIA GPT (rodada 1):**
  1. **Origem POSTGRES exige EVIDÊNCIA, nunca formato.** `ehIdTecnicoPostgres`
     passou a ser usado SOMENTE como validação de formato, nunca como
     classificação de origem; id legado numérico, textual ou **em formato de
     UUID** não é promovido por isso; nenhuma heurística de data.
  2. **Navegação das avaliações novas.** O livro-caixa de cutover ganhou índices
     de NAVEGAÇÃO (`CHAVE_CICLO_AVALIACOES`) e as telas passaram a abrir a
     avaliação nova pelo painel soberano.
- **Estado — CORREÇÕES PÓS-AUDITORIA GPT (rodada 2, FINAL):**
  1. **Descoberta SOBERANA (localStorage é opcional).** A prova de existência vem
     do SERVIDOR: `resolverLeituraAvaliacao` (`origemAvaliacaoTela.ts`) consulta a
     fronteira confiável para qualquer id candidato e só usa o acervo local quando
     o servidor responde `NOT_FOUND` (o código público do erro é exposto em
     `ResultadoCutover.codigo` para essa distinção — sem inspeção de texto).
     Consequências: `localStorage` apagado, outro navegador/dispositivo,
     livro-caixa ausente/corrompido e **URL soberana aberta diretamente** não
     escondem uma avaliação real; falha de backend/indeterminação é fail-closed e
     nunca vira leitura local silenciosa; `NOT_FOUND` e negação permanecem
     indistinguíveis (sem vazar existência cross-tenant).
     No SQL, ausência de ocorrência vigente do ator no painel passou a devolver
     `NULL` (resultado "sem painel") em vez de exceção, permitindo distinguir
     "não existe/não acessível" de "falha real".
  2. **Índices de navegação ISOLADOS por organização.** `chaveAnoCiclo` e
     `chaveCicloColaborador` passaram a incluir `organizationId`
     (`org|ano-ciclo`), e `registrarAvaliacoesDoCiclo`/`lerAvaliacoesDoCiclo`/
     `lerAvaliacaoNovaDoColaboradorNoCiclo`/`esquecerAvaliacaoNovaDoColaboradorNoCiclo`
     recebem a organização. Mesma matrícula/ano/ciclo em orgs diferentes não
     colide; trocar de organização ativa não reutiliza índice alheio. A
     organização ali é apenas NAMESPACE DE CACHE — não é prova de tenant nem
     autorização (toda operação revalida server-side).
  3. **Preflight de duplicidade validado no servidor.** `NovoFeedbackPage` não
     bloqueia mais só pelo cache: confirma a existência na fronteira confiável e,
     se a entrada estiver obsoleta, esquece o cache e segue com a criação
     legítima. A autoridade da unicidade continua sendo o índice único parcial do
     banco, e nada é criado localmente.
- **Estado — CORREÇÕES DA AUDITORIA GPT-5.6 TERRA (rodada 3, FINAL):**
  1. **BLOCKER 1 — assinatura de `evaluation_resolver_ciclo`.** A Edge enviava
     `p_matricula_avaliado`, argumento que NUNCA existiu na RPC; com PostgREST a
     divergência quebra a chamada e impedia toda criação nova. A Edge passou a
     enviar EXATAMENTE a assinatura real:
     `evaluation_resolver_ciclo(p_organization_id uuid, p_ano integer,
     p_numero integer, p_actor_user_profile_id uuid) returns uuid`.
     A matrícula continua sendo INTENÇÃO resolvida pela ponte F3-01 **antes** do
     Policy Engine (para o alvo autorizável) e não trafega de novo. Nenhum
     overload foi criado. Teste novo `avaliacoesContratoRpc.test.ts` lê o código
     real da Edge e falha se algum argumento voltar a divergir do contrato.
  2. **BLOCKER 2 — IDOR em `participant_id`.** As RPCs `evaluation_gravar_notas`
     e `evaluation_gravar_comentario` aceitavam `p_participant_id` do chamador e
     só validavam que a ocorrência pertencia à avaliação e estava vigente: um ator
     autorizado podia forjar o id da ocorrência de TERCEIRO. Agora a ocorrência
     editável é derivada SOBERANAMENTE do ator, por
     `evaluation_ocorrencia_do_ator(organization_id, evaluation_id, actor)`:
     `auth.uid()` → perfil → membership ativa no tenant do RECURSO → vínculo
     F5-02 → ocorrência VIGENTE pertencente a ele. **`participant_id` foi
     REMOVIDO do contrato externo** (Edge, `core.ts`, `contrato.ts`, repositório,
     controlador e serviço) e a validação de forma RECUSA o campo
     (`INVALID_INPUT`); as assinaturas antigas foram dropadas. Defesas em
     profundidade nas RPCs: ator revalidado, tenant do recurso revalidado,
     ocorrência vinculada ao ator, vigência respeitada e fail-closed em ausência
     **ou ambiguidade** (duas ocorrências vigentes ⇒ recusa).
     O `painel_participante` continua devolvendo SOMENTE a ocorrência própria
     (usada como catálogo/identidade da tela) e D20 permanece intacta.
- **Telas que ainda leem SOMENTE o legado (justificativa):**
  - `CiclosAvaliacaoPage`/`PainelCicloPage`/`relatorioService`: o painel é
    montado pelo domínio de **ciclos**, que ainda vive em `localStorage`
    (migração de ciclos é outra atividade — D15). Enquanto o ciclo não existir no
    banco, não há avaliação nova daquele ciclo a listar; quando existir, o índice
    de navegação é o caminho. Nenhuma autoridade local é exercida.
  - `ColaboradorDetalhePage`: lista o histórico administrativo do acervo legado;
    a avaliação nova é alcançável pelo índice/painel. Adotar a leitura soberana
    nessa listagem é aditivo.
- **Pendências/limitações conhecidas (não bloqueiam o critério de conclusão):**
  1. **Gravação de ciclo (entidade `evaluation_cycles`) é de outra atividade**
     (D15). Sem o ciclo correspondente no banco, `evaluation.criar` é recusado e
     a tela reporta quantas avaliações ficaram **bloqueadas** (nunca cria local).
  2. **Remoção de nota**: `evaluation_gravar_notas` aceita notas `1..5`; limpar
     uma nota já gravada não a apaga (não há API de exclusão). O valor anterior
     permanece — alteração de contrato exigiria nova `Q#`.
  3. **Listagem administrativa do legado** (item acima) permanece legado.
  4. **Descoberta de id fora da URL**: sem estado local, o produto alcança a
     avaliação pela URL/painel; uma listagem soberana "por ciclo/colaborador"
     (Edge + Policy Engine) é evolução aditiva e depende da migração de ciclos.
  5. **Ator com duas ocorrências vigentes** na mesma avaliação (ex.: o mesmo
     colaborador como responsável direto E membro do colegiado) é recusado por
     ambiguidade (fail-closed, coberto pelo validador). O cenário sintético
     encerra a ocorrência redundante para exercitar o fluxo positivo. Resolver a
     escrita nesse caso exigiria papel explícito na intenção ⇒ nova `Q#`.
- **Validação da F5-06 (todo exit 0):** `npm test` (84 arquivos,
  1069 testes), `npm run build`, `npm run lint`, `git diff --check`;
  validadores SQL no Supabase local — `01-cenario-f5-06.sql`,
  `02-validar-f5-06.sql` (25 PASS), `03-validar-f5-06-cutover.sql` (13 PASS,
  incluindo os testes negativos de IDOR), `01-cenario-f4-08.sql`,
  `02-validar-f4-08.sql` (56 PASS), `03-validar-f4-08-mutacoes.sql` (8 PASS).
- **Contexto do repositório:** `main` contém F4, F5-01..F5-06 e a DEV-02 já
  integradas (F5-06 em `f540f0f…`, DEV-02 em `e098754…`); o BUG #170 é a atividade
  em curso nesta branch, sem alteração funcional fora da navegação.
- **Próximos passos:** auditoria independente sobre o novo SHA do BUG #170; abrir
  PR quando solicitado; a Issue #170 **não** deve ser fechada por este agente.
  Nenhum agente declara a própria entrega aprovada (`.ai/workflow.md` §6.3,
  item 8).
