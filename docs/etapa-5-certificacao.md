# Virtus — Certificação Transversal da Etapa 5

> **Atividade:** Issue #256 — **esta entrega É a F5-12** (validação integrada e fechamento formal da
> Etapa 5): a certificação transversal e o fechamento **são este artefato**, e não uma fase
> posterior. **Natureza:** auditoria e documentação — nenhum código funcional, migration, RPC, role,
> capability, refatoração ou teste novo foi criado. **Base:** `origin/main`
> (branch `docs/etapa-5-certificacao`).
> **Método:** levantamento das obrigações já assumidas nas fontes do repositório (roadmap em
> `.ai/virtus-context.md`, `.ai/workflow.md`, `.ai/handoff.md`, os desenhos `docs/F4-*`/`docs/F5-*`,
> os documentos de auditoria da Etapa 5 e as certificações por fase, em especial
> `docs/F5-11-certificacao.md`), com **reutilização** da prova já registrada (validadores, passos
> de CI, testes automatizados e registros de gate efetivamente executados). **A Issue #256 não é
> legível neste ambiente** (`gh` ausente): o recorte de "Etapa 5" foi derivado do roadmap e dos
> documentos do próprio repositório — tudo o que depender do texto da Issue fica **NÃO VERIFICADO**.

## 0. Fontes das obrigações

| Fonte | O que define |
| --- | --- |
| `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md` §3 e §4 | os **três BLOCKERS** históricos da Etapa 5 e a lista de itens não bloqueantes |
| `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md` §4 | a lista de **resíduos da Etapa 5** (CRITICAL/HIGH/MEDIUM/LOW) |
| `docs/F5-07-desenho-tecnico.md` §20 (tabela e §20.5) | sequência F5-07 → F5-08 → F5-09 → F5-10 → F5-11 → **F5-12 — validação integrada e fechamento da Etapa 5, que é ESTA entrega (Issue #256)**: consolida a matriz `T-01…T-24`, o guard F4-08 e o contrato de evento |
| `docs/F5-01-desenho-tecnico.md` … `docs/F5-11-desenho-tecnico.md` §17.1 | critérios de aceite **por fase** |
| `docs/F5-11-certificacao.md` | certificação da F5-11 (P1…P6) com evidência citável |
| `docs/F5-09-p9-matriz-integrada.md`, `docs/F5-10-p7-matriz-integrada.md` | matrizes transversais já produzidas pelas fases de ciclos e metas |
| `.github/workflows/ci.yml` | passos de validação por fase (autoridade de CI) |

## 1. Matriz obrigação × evidência × status

### 1.1 Os três BLOCKERS históricos da Etapa 5

| # | Obrigação | Evidência existente | Status |
| --- | --- | --- | --- |
| B1 | **Ciclos** deixarem de ter autoridade local (lifecycle soberano, RLS, listagem server-side) | F5-09: migrations + validadores `01-cenario-f5-09` … `15-validar-f5-09-p9` e os pares de concorrência `16/17/18` — **todos verdes** no gate de pipeline executado (56/56); matriz `docs/F5-09-p9-matriz-integrada.md`; guarda `src/services/ciclosSoberanosSemFallback.test.ts` (nenhum dual-read no caminho soberano; `localCycleRepository` classificado explicitamente como LEGADO, `:58`) | **demonstrada** (com dívida residual de leitores legados — ver §2) |
| B2 | **Colaboradores e histórico estrutural** soberanos (UUID, membership, vigência, sucessão, RLS) | F5-07: `01/02/03-f5-07` verdes (`PASS=44` no validador e `22` no cutover) no pipeline executado; F5-08 (estrutura/catálogos): `02-validar-f5-08` `PASS=57` e `03-validar-f5-08-cutover` `PASS=12` | **demonstrada** |
| B3 | **Metas e observações** dentro da autoridade PostgreSQL (schema, policies, RPC/Edge, auditoria append-only, transações, cutover) | F5-10: `20/22/24/26/28/30/33` verdes (`12/17/12/23/15/19/3`), matriz `docs/F5-10-p7-matriz-integrada.md`; F5-11: cadeia `34…43` **10/10 verde** e `docs/F5-11-certificacao.md` | **demonstrada** |

### 1.2 Obrigações transversais

| # | Obrigação | Evidência existente | Status |
| --- | --- | --- | --- |
| T1 | **Trust boundaries** (browser → Edge → RPC → Postgres; nenhuma autoridade declarada pelo cliente) | padrão §6.7 aplicado nas edges (`supabase/functions/*/{index,core,contrato}.ts`); validadores da F5-11 provam a allowlist estrita e a ausência de campos de autoridade; guardas `src/authorization/estruturaUiSeguranca.test.ts:525-536` (nenhum `.rpc(`/credencial de serviço em módulo de produção) | **demonstrada** |
| T2 | **D1–D22** do desenho (decisões fechadas das fases) | `docs/F4-03-desenho-tecnico.md` (D1–D23 do Policy Engine), `docs/F5-01…F5-11-desenho-tecnico.md` (D1–D16/D21/D22 por domínio; emendas registradas: D15 em `docs/F5-11-desenho-tecnico.md` §8 e §24) | **demonstrada** |
| T3 | **RLS/policies** fechadas com isolamento por tenant | `02-validar-f4-08`, `03-validar-f4-08-mutacoes`, e as asserções de RLS/ACL de cada validador de fase (ex.: F5-11 `43` blocos de RLS/ACL) — todos verdes no pipeline executado | **demonstrada** |
| T4 | **ACL/grants** mínimos (EXECUTE só `service_role`; revokes de `public/anon/authenticated`) | mesmos validadores de ACL por fase; na F5-11: `42/43` + guarda `F5_11_P5_4_GUARDA`; `supabase/migrations/20260908100000_f4_08_helpers_function_grants.sql` | **demonstrada** |
| T5 | **Auditoria/trilhas append-only** com autoria soberana | F5-11: `privilege_mutation_audit` com `system_grant`/`system_revoke` e ator NULL para o caminho automático (constraint discriminante bicondicional, migration `20260934000000`/`20260936000000`); validador `43` blocos D e H0; `evaluation_events`/`collaborator_events`/`structure_events`/`cycle_events` nas fases correspondentes | **demonstrada** |
| T6 | **Idempotência e concorrência** (sem advisory lock; versão otimista; eventos só na transição real) | D10 (`expected_version` + `operation_id`) nos validadores de metas/observações/ciclos; **pares de concorrência reais** `16/17/18` e `31/32/33` verdes; F5-11 P5.4 eliminou a corrida de primeiro provisionamento por upsert único | **demonstrada** |
| T7 | **Multi-tenant / IDOR** (alvo sempre por `(id, tenant)`; `NOT_FOUND` indistinguível) | validadores de cross-tenant por fase (F5-11 `43` bloco F; F4-08; F5-09/F5-10) — verdes | **demonstrada** |
| T8 | **Fail-closed** em ausência/incoerência de dado soberano | provas por fase (ex.: F5-11 `35`/`39` provam DENY por capability com ator inelegível; `43` provas de SELF; resolvedores exigem perfil/membership/vínculo ativos) | **demonstrada** |
| T9 | **Guardas de estrutura de UI** (sem `.rpc(`, sem credencial, sem dual-read, sem autoridade local no caminho soberano) | `src/authorization/estruturaUiSeguranca.test.ts` (>100 módulos de produção), `src/services/ciclosSoberanosSemFallback.test.ts`; a F5.1/P5.1 da F5-11 fechou o **dual-read** que a guarda da F5-09 detectou | **demonstrada** |
| T10 | **CI completo** (todos os passos de validação por fase) | `.github/workflows/ci.yml` (passos F4-08 → F5-11, incluindo reaplicação idempotente da migration D28 e os dois pares de concorrência); pipeline CI-equivalente reproduzido localmente **56/56 verde** na árvore de certificação | **demonstrada localmente**; o **CI oficial do SHA** é a autoridade final e fica **PENDENTE do orquestrador** |
| T11 | **Coerência promessa × prova** por fase | `docs/F5-11-certificacao.md` (P1…P6) + matrizes `docs/F5-09-p9-matriz-integrada.md` e `docs/F5-10-p7-matriz-integrada.md`; nenhum critério de fase anterior ficou órfão **dentro** da F5-11 (as dependências declaradas — “quem concede `observation.read` ao avaliado” — foram fechadas na P5.1) | **demonstrada**, exceto os resíduos de §2 |

### 1.3 Prova do R1 — auditoria dos leitores legados de ciclo (verificação CONCLUÍDA nesta entrega)

**Método:** leitura estática de cada leitor, seguindo a cadeia de chamadas até um ponto de entrada de
produção (página/componente/serviço), com atenção a (i) alimentar `can()`/`authorize()`/Policy
Engine, (ii) gate de UI que esconde/aplica ação, (iii) verificação de permissão/papel, (iv) comparação
de tenant e (v) bloqueio funcional. **Nenhum código foi alterado** — apenas auditado e registrado.

| Leitor (arquivo:linha) | O que lê do estado local | Caminho de chamada até produção | Participa de decisão de autorização/segurança? | Classificação final |
| --- | --- | --- | --- | --- |
| `src/services/permissaoAvaliacao.ts:3,44,59` (`getCicloAtivo`, `getColaboradoresEfetivosNoCiclo`) | ciclo ATIVO local + colaboradores "efetivos do ciclo" (fallback do mundo local) | **Nenhum consumidor de produção**: `obterPermissoesAvaliacao` é importado somente por testes (`authorizationPolicy.test.ts:2`, `cutoverEstruturalServicos.test.ts:229`, `permissaoAvaliacao.test.ts:6`, `estruturaSoberanaCliente.test.ts:392`). As telas que exibem os mesmos rótulos usam `can()` soberano (`EditarFeedbackPage.tsx:547-559`, `NovoFeedbackPage.tsx:329-345`); a própria função é fail-closed sem evidência estrutural (`:71-72`) e está na lista de leitura legada da guarda (`estruturaUiSeguranca.test.ts:406`) | **Não** | **morto/sem consumidor de produção** (o suspeito mais forte do R1 foi inocentado) |
| `src/pages/EditarFeedbackPage.tsx:39,510,544` | `getCiclosAvaliacao().find(...)` → `cicloDaAvaliacao` | `:544 cycle: cicloDaAvaliacao` → `can(authorizationContext, "evaluation.edit.manager/coordinator/board", evaluationResource)` (`:547-559`) → `AccessRestrictedState` (`:565-570`) | **Sim, como INSUMO do gate de UI**: o domínio de ciclo do engine vem de `resource.cycle.status` (`authorizationPolicy.ts:130,211,221,244,287`) | **apresentação/UX com duplicação de autoridade** — o soberano (servidor) prevalece e revalida a mutação |
| `src/pages/FeedbackDetalhePage.tsx:193,209,213-244` | idem (`getCiclosAvaliacao().find`) | `:209 cycle: cicloDaAvaliacao` → `can(...)` (6 chamadas, `:213-244`) | **Sim, como INSUMO do gate de UI** | idem (apresentação/UX com duplicação de autoridade) |
| `src/pages/NovoFeedbackPage.tsx:37,188,251,254,330-340,784` | `getCicloAtivo()` | `:251 cycle: cicloAtivo` → `can("evaluation.create"/"evaluation.edit.*")` (`:254,330,333,340`) **e** `authorize(contextoAutorizado, "evaluation.create", evaluationResource)` (`:784`) | **Sim, como INSUMO do gate de UI e do pré-voo do cliente** | idem — a decisão efetiva é do servidor (o próprio arquivo registra isso em `:321`) |
| `src/services/cicloEquipeService.ts:6`, `src/services/relatorioService.ts:5`, `src/pages/PainelCicloPage.tsx:11`, `src/pages/RelatoriosPage.tsx:11,28`, `src/pages/painelCicloStatus.ts:2`, `src/pages/PainelCiclosCoordenadorPage.tsx:4` | `getCiclosAvaliacao` (painéis e relatórios) | render de painéis/relatórios; os `can()` dessas telas (`PainelCicloPage.tsx:176`, `RelatoriosPage.tsx:82`, `PainelCiclosCoordenadorPage.tsx:12`) **não** recebem o ciclo local | **Não** | apresentação/UX apenas |
| `src/services/historicoOrganizacionalStorage.ts:22` | ciclos para histórico organizacional | render de histórico | **Não** | apresentação/UX apenas |
| `src/services/cancelamentoCicloService.ts:8`, `src/services/reaberturaCicloService.ts:8` | ciclos locais | serviços legados que operam o acervo local; as mutações soberanas de ciclo passam por Edge/RPC | **Não** | legado de mutação local (resíduo R1) |
| `src/infrastructure/localStorage/localCycleRepository.ts:33,72` | porta `CycleRepository` cumprida localmente | LEGADO declarado (`src/services/ciclosSoberanosSemFallback.test.ts:58`); o caminho soberano não o importa | **Não** | morto/legado declarado (R2) |
| `src/pages/CiclosAvaliacaoPage.tsx:11`, `src/pages/ColaboradoresPage.tsx:30`, `src/pages/MinhaAvaliacaoPage.tsx:9`, `src/pages/MinhaAvaliacaoDetalhePage.tsx:399` | `formatarPeriodoCiclo`/`getCiclosAvaliacao`/`getCiclosAdministrativos` | render (listagem, formatação, rótulos) | **Não** | apresentação/UX apenas |
| `src/services/geradorDadosTeste.ts:7` | ciclos para semente DEV | ferramenta de desenvolvimento | **Não** | fora do caminho de produção |

**Duplicação de autoridade:** existe — e é **de UX**, não de autoridade final. Nas três páginas de
avaliação (`EditarFeedbackPage`, `FeedbackDetalhePage`, `NovoFeedbackPage`) o `cycle` do recurso
avaliado por `can()`/`authorize()` no cliente vem do **acervo local**, enquanto o caminho soberano
resolve o ciclo por UUID/projeção (`src/pages/PainelCicloPage.tsx:44` documenta justamente a
substituição do `getCiclosAvaliacao().find(...)` pelo UUID). **Prevalece o soberano**: toda mutação é
revalidada server-side (Policy Engine do servidor + RLS + RPC), portanto o efeito possível do insumo
local é **divergência de apresentação** (esconder/habilitar ação na tela) — nunca concessão de
autoridade que o servidor negaria.

**Resposta explícita do R1:** **NÃO existe uso de estado local como autoridade de decisão de
autorização/segurança no caminho de produção** — logo **não há lacuna bloqueante**. Permanece uma
dívida de apresentação/limpeza (com a nota acima), a ser tratada como resíduo do acervo legado.

## 2. Obrigações NÃO demonstradas (ou parcialmente)

| # | Item | Classificação | Evidência da ausência |
| --- | --- | --- | --- |
| R1 | **Leitores legados de ciclo ainda presentes em módulos de produção** (ciclo local alimentando telas/serviços operacionais): `src/services/cicloEquipeService.ts:6`, `src/services/historicoOrganizacionalStorage.ts:22`, `src/services/permissaoAvaliacao.ts:3`, `src/services/cancelamentoCicloService.ts:8`, `src/services/reaberturaCicloService.ts:8`, `src/services/relatorioService.ts:5` (via `cicloEquipeService`), `src/pages/{CiclosAvaliacaoPage,ColaboradoresPage,EditarFeedbackPage,FeedbackDetalhePage,MinhaAvaliacaoPage,NovoFeedbackPage,PainelCicloPage,PainelCiclosCoordenadorPage,RelatoriosPage}.tsx` — importando `cicloAvaliacaoStorage` (`STORAGE_KEY = "feedback-control-ciclos"`, `src/services/cicloAvaliacaoStorage.ts:8`) | **DÍVIDA não bloqueante — verificação CONCLUÍDA NESTA ENTREGA** (a ressalva que a certificação anterior deixava como pendência da F5-12, que **é esta entrega**): **nenhum leitor legado é AUTORIDADE de decisão de autorização/segurança**; a autoridade é server-side (Policy Engine do servidor + RLS + RPC), revalidada em toda mutação. Permanece como resíduo de apresentação/limpeza, com **uma nota material**: em 3 páginas o ciclo local entra como *insumo* do gate de UI (`can()`/pré-voo `authorize()` do cliente) — duplicação de autoridade em nível de UX, em que o soberano prevalece (ver §1.3) | prova completa na tabela do **§1.3** (leitor × o que lê × caminho de chamada × classificação); a lista de resíduos da Etapa 5 (`docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md:83-108`) marcava o conjunto como CRITICAL/HIGH |
| R2 | **`localCycleRepository.ts`** (porta `CycleRepository` cumprida localmente, `src/infrastructure/localStorage/localCycleRepository.ts:33,72`) | **DÍVIDA não bloqueante** (declarada) | existe e continua LEGADO por decisão explícita da F5-09 (`src/services/ciclosSoberanosSemFallback.test.ts:58`); o caminho soberano de ciclos não o importa (guarda verde) |
| R3 | **Testes que pré-carregam chaves legadas** (`feedback-control-ciclos`, `-observacoes`, `-metas`) como fixtures | **DÍVIDA não bloqueante** | itens MEDIUM da lista de resíduos (`…:106-108`); confirmados por grep (ex.: `src/pages/FeedbackDetalhePage.test.tsx:106`, `src/services/cicloEquipeService.test.ts:180`). Fixtures válidas, porém **não** são prova de autoridade soberana |
| R4 | **Prova literal de transferência entre organizações** no validador da F5-11 | **DÍVIDA não bloqueante** | registrada em `docs/F5-11-certificacao.md`; a regra está provada (elegibilidade por membership + cenários C6/C7) |
| R5 | **Defeito latente de diagnóstico** (`v_falhas \|\| 'literal'` em `text[]`) em `supabase/validacao/41-validar-f5-11-p3.sql` | **DÍVIDA não bloqueante** | registrado em `docs/F5-11-certificacao.md`; só se manifesta quando uma guarda da P3 falha (troca `[FAIL]` legível por erro de array) |
| R6 | **Cenário `42-cenario-f5-11-p5-1.sql`** ainda derivando organização/ciclo do tenant da P2 | **DÍVIDA não bloqueante** | registrado em `docs/F5-11-certificacao.md` |
| R7 | **2 falhas pré-existentes de testes** em Windows/CRLF (`AcompanhamentoMetasPage.test.tsx`, `MinhasMetasPage.test.tsx`) | **FORA DE ESCOPO** (não contratada pela Etapa 5) | `npm test` 2301/2303 nos gates executados; o CI oficial passa |
| R8 | **Importação do acervo legado real** | **FORA DE ESCOPO** (decisão de produto) | `docs/F5-07-desenho-tecnico.md` §20.6 |
| R9 | **Redesign visual, hardening/observabilidade de produção (F6)** | **FORA DE ESCOPO** | itens não bloqueantes do checkpoint (`…:90`) |
| R10 | **F5-12 — validação integrada e fechamento formal da Etapa 5** | **ESTA ENTREGA (Issue #256)** — deixa de ser pendência | `docs/F5-07-desenho-tecnico.md:1280` e §20.5 definem a F5-12 como a validação integrada que consolida a matriz `T-01…T-24`, o guard F4-08 e o contrato de evento; **este documento é essa validação e esse fechamento** (não há fase posterior prevista para o fechamento da Etapa 5) |

## 3. O que depende de fases futuras

1. **F5-12 — validação integrada e fechamento da Etapa 5: É ESTA ENTREGA (Issue #256).** Não há fase
   posterior prevista para o fechamento da Etapa 5: este documento consolida a matriz `T-01…T-24`, o
   guard F4-08 e o contrato de evento, **fecha R1** (verificação concluída em §1.3) e **aceita
   formalmente R2–R6 como dívida não bloqueante** desta entrega.
2. **F6 — hardening de produção**: observabilidade, escala, redesign e as 2 falhas de teste
   Windows/CRLF.
3. **Importação do acervo legado**: atividade própria, se houver decisão de produto.
4. **Limpeza do resíduo de apresentação do R1** (ciclo local como insumo de gate de UI em três
   páginas): atividade de limpeza/backlog, sem efeito de autoridade — o soberano prevalece.

## 4. Gates necessários para o fechamento (execução do orquestrador)

1. **Pipeline CI-equivalente completo** (56 steps, ordem do `ci.yml`, com a reaplicação da
   migration D28 duas vezes e os dois pares de concorrência reais) — executado nesta árvore:
   **56/56 verdes** (duas execuções: a primeira parou em *flake do harness local* no par 16/17 —
   sessão B mediu 1,954 s contra o limiar de 2 s — e a segunda fechou 56/56, mesma árvore).
2. **Cadeia de banco `34…43`**: `10/10 verdes` (34:1 · 35:11 · 36:1 · 37:8 · 38:1 · 39:7 · 40:3 ·
   41:4 · 42:2 · 43:1).
3. `git diff --check` **exit 0**; `npm test` **2301/2303** (apenas as 2 falhas PRÉ-EXISTENTES de
   Windows/CRLF); `npm run build` **exit 0**; `npm run lint` **exit 0**.
4. **CI oficial do PR/SHA (GitHub)** — **PENDENTE (orquestrador)**: é a autoridade final,
   especialmente para os pares de concorrência.

## 5. Resposta explícita

**NÃO existe lacuna material bloqueante AGORA** para a certificação transversal e o fechamento da
Etapa 5 (**F5-12 = esta entrega**, Issue #256): os três BLOCKERS históricos estão demonstradamente
resolvidos, as obrigações transversais têm evidência citável e os gates locais aplicáveis estão
verdes. **R1 foi verificado e fechado nesta entrega** (prova em §1.3): **nenhum leitor legado de ciclo
é autoridade de decisão de autorização/segurança** — a autoridade é server-side e prevalece; resta
apenas resíduo de apresentação (ciclo local como insumo do gate de UI em três páginas). O que
permanece são **dívidas não bloqueantes** (R2–R6, aceitas formalmente nesta entrega), **itens fora de
escopo** (R7–R9) e a **F5-12, que é este artefato** (R10, deixando de ser pendência). Ressalvas de
verificação: (i) o texto da Issue #256 e das demais Issues não é legível neste ambiente; (ii) o **CI
oficial do SHA final** ainda não foi executado — é a autoridade final e fica **PENDENTE do
orquestrador**.
