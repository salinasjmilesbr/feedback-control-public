# Virtus — Registro Canônico de Dívidas Técnicas

> **Propósito:** este é o **registro canônico** das dívidas técnicas conhecidas e aceitas do Virtus.
> Ele consolida, com IDs estáveis `DT-xxx`, o que as fases, auditorias e certificações já registraram
> como **não demonstrado**, **aceito como dívida** ou **fora de escopo** — sem reanalisar o código
> além do necessário para citar a evidência já existente.
>
> **REGRA DE USO (inegociável):** uma dívida registrada aqui **NÃO é uma Issue** e **não autoriza
> trabalho**. Ela vira Issue **somente por decisão explícita do orquestrador**, com o ID `DT-xxx` no
> título (ex.: `DT-006 — Gate geral do Painel de ciclo usa alvo sintético ({kind:"global"})`). Registrar aqui **não**
> bloqueia entrega, **não** reabre decisão fechada (`D#`/`Q#`) e **não** substitui a Issue da
> atividade: é memória técnica, não contrato de trabalho.
>
> **Como reavaliar:** cada bloco define o **momento de reavaliação** (fase, gate ou evento). Na
> reavaliação, o ID **não é reutilizado**: o status passa a `concluída`, `absorvida` ou `fora de
> escopo`, com a evidência nova anexada ao próprio bloco (ou movido para as seções finais). Se a
> reavaliação encontrar **contradição entre fontes**, ela é **registrada**, não resolvida por escolha
> unilateral (§4). Nenhuma dívida pode ser **removida** deste registro: o que sai do estado `aberta`
> vai para as seções §3 ou §4 com a evidência que o fechou.
>
> **Natureza desta rodada (Issue #258):** registro **documental**. Nenhum código, migration, teste,
> Issue ou correção foi criado/executado; nenhuma dívida foi transformada em Issue.
>
> **Duas classes neste registro:** **dívidas** (§1–§3: não bloqueantes, aceitas) e **FINDINGS
> BLOQUEANTES** (§0.1: defeitos funcionais concretos, demonstrados, que **exigem Issue e correção
> antes do fechamento** da atividade correspondente). Um finding bloqueante **não** pode ser
> rebaixado a dívida — nem o inverso — sem decisão explícita do orquestrador.

## 0. Fontes consolidadas

| Fonte | O que fornece |
| --- | --- |
| `docs/etapa-5-certificacao.md` | matriz `B1–B3`/`T1–T11`, prova do `R1` (§1.3) e itens `R1–R10` (§2, §3) |
| `docs/F5-11-certificacao.md` | certificação da F5-11 (P1–P6) e dívidas classificadas (§4, §5) |
| `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md` | três BLOCKERS históricos (§3) e itens não bloqueantes (§4) |
| `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md` | lista de resíduos da Etapa 5 — CRITICAL/HIGH/MEDIUM/LOW (§4) |
| `docs/F5-08-p6-duvida-mundo-funcional.md` | residual declarado de estrutura/matrícula (§7) |
| `docs/F5-10-P5.3-autoridade-painel-ciclo.md` | dívidas `D4`/`D5` do domínio de ciclo (§, linhas citadas) |
| `docs/F5-10-p7-matriz-integrada.md` | evidência do CRLF e da dívida documental do processo |
| `docs/F5-09-p9-matriz-integrada.md` | matriz integrada de ciclos (evidência do blocker B1) |
| `docs/F5-11-desenho-tecnico.md`, `docs/F4-09-desenho-tecnico.md` | registros de origem de dívidas específicas |
| `.ai/handoff.md`, `.ai/virtus-context.md` | dívidas, limitações e pendências citadas no contexto operacional |
| `.github/workflows/ci.yml` | passos de validação (autoridade de CI); o arquivo **não** declara limitação conhecida |

## 0.1 FINDINGS BLOQUEANTES (não são dívidas)

> **Finding bloqueante** = defeito funcional **concreto e demonstrado** que **impede o fechamento** da
> atividade/fase correspondente até ser corrigido em **Issue própria**. Não é dívida aceita: o ID fica
> neste registro (não reutilizável), o histórico da classificação anterior é preservado e a correção
> **não** é implementada por quem apenas documenta.

#### DT-013 — [FINDING BLOQUEANTE] Edge `avaliacoes` importa módulo inexistente
- **Título curto:** `supabase/functions/avaliacoes/index.ts` importa `catalogoCapacidades.ts` (inexistente).
- **Origem:** F5-06/F5-07 (registrado no handoff como defeito preexistente em `main`, não corrigido);
  **reclassificado de “dívida não bloqueante” para FINDING BLOQUEANTE na Issue #258**, por decisão do
  orquestrador.
- **Evidência (duas pontas):** (i) `supabase/functions/avaliacoes/index.ts:8` —
  `import { capabilityCanonica } from "../../../src/authorization/catalogoCapacidades.ts";`;
  (ii) o módulo **não existe**: o arquivo real é `src/authorization/catalogoCapabilities.ts` e
  `catalogoCapacidades.ts` não existe em nenhum ponto do repositório. A guarda de grafo de imports já
  documenta o caso: `src/authorization/ciclosEdgeImportGraph.test.ts:24,153,233`.
- **Impacto:** o **bundle Deno** da Edge `avaliacoes` não é produzível (a função não inicializa).
  Escapa de `npm test`/`build`/`lint`/`tsc` porque o código Deno de `supabase/functions/**` não entra
  no build TypeScript; **não** afeta a autorização (a autoridade é o servidor: Policy Engine + RLS +
  RPC).
- **Classificação:** **FINDING BLOQUEANTE** (não é dívida aceita).
- **Motivo de bloqueio:** é defeito funcional concreto com evidência direta, e não um resíduo de
  apresentação; mantê-lo como dívida aceita mascararia uma Edge quebrada.
- **Momento de reavaliação:** **Issue própria e correção ANTES do fechamento da #258**, conforme
  decisão do orquestrador.
- **Status:** `bloqueante — pendente de Issue`.

## 1. Dívidas registradas

### A. Acervo local e legado

#### DT-001 — Leitores legados de ciclo em módulos de produção
- **Título curto:** ciclo local ainda alimenta telas/serviços operacionais (resíduo de apresentação).
- **Origem:** Etapa 5 (resíduo CRITICAL/HIGH) + certificação transversal (R1, verificação concluída).
- **Evidência:** `docs/etapa-5-certificacao.md:91` (R1) e `docs/etapa-5-certificacao.md:61-72` (tabela da
  prova, com arquivo:linha por leitor: `src/services/cicloEquipeService.ts:6`,
  `src/services/historicoOrganizacionalStorage.ts:22`, `src/services/permissaoAvaliacao.ts:3`,
  `src/services/cancelamentoCicloService.ts:8`, `src/services/reaberturaCicloService.ts:8`,
  `src/services/relatorioService.ts:5` e as páginas que importam `cicloAvaliacaoStorage`,
  `STORAGE_KEY = "feedback-control-ciclos"` em `src/services/cicloAvaliacaoStorage.ts:8`);
  `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md:83-108`.
- **Impacto:** resíduo de apresentação/limpeza; **atenção material registrada** — em três páginas
  (`EditarFeedbackPage`, `FeedbackDetalhePage`, `NovoFeedbackPage`) o ciclo **local** entra como
  **insumo** do gate de UI (`can()` e pré-voo `authorize()` do cliente), o que é **duplicação de
  autoridade em nível de UX**: o efeito possível é divergência de apresentação (esconder/habilitar
  ação na tela), **nunca** concessão que o servidor negaria.
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** a autoridade é **server-side** (Policy Engine do servidor + RLS + RPC) e
  revalida toda mutação; nenhum leitor legado é **autoridade** de decisão de autorização/segurança
  (`docs/etapa-5-certificacao.md:83-85`), e `permissaoAvaliacao.ts` **não tem consumidor de produção**
  (`docs/etapa-5-certificacao.md:63`).
- **Momento de reavaliação:** atividade própria de limpeza do acervo legado (backlog) ou fase F6.
- **Status:** `aberta`.

#### DT-002 — Estrutura local/matrícula em serviços operacionais
- **Título curto:** filtros/alcance e identificação por matrícula local em relatórios, PDF e visibilidade.
- **Origem:** F5-08 P6 (residual declarado) + auditoria da F5-09.
- **Evidência:** `docs/F5-08-p6-duvida-mundo-funcional.md:155-164` (tabela do §7:
  `src/services/relatorioService.ts`, `src/services/exportarAvaliacaoPdf.ts`,
  `src/services/visibilidadeColaboradores.ts`, `src/services/historicoOrganizacionalStorage.ts`);
  `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md:102-104`.
- **Impacto:** filtros/alcance de relatório e identificação documental ainda usam estrutura/matrícula
  local; não concedem papel de avaliação/aprovação, mas exigem atividade própria (relatórios/PDF).
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** declarado como fora do blocker da F5-08 P6 e sem papel de autorização
  (`docs/F5-08-p6-duvida-mundo-funcional.md:159-162`).
- **Momento de reavaliação:** atividade própria de relatórios/PDF (F6 ou backlog).
- **Status:** `aberta`.

#### DT-003 — `localCycleRepository.ts` mantido como LEGADO por decisão
- **Título curto:** porta `CycleRepository` cumprida localmente, sem consumidor no caminho soberano.
- **Origem:** F5-09 + certificação transversal (R2).
- **Evidência:** `docs/etapa-5-certificacao.md:92` (R2) e `:70`;
  `src/services/ciclosSoberanosSemFallback.test.ts` (classificação explícita como LEGADO, citada em
  `docs/etapa-5-certificacao.md:34`).
- **Impacto:** código legado vivo no repositório; risco de reutilização indevida por engano.
- **Classificação:** **dívida não bloqueante** (legado declarado).
- **Motivo de não bloqueio:** o caminho soberano de ciclos **não o importa** e a guarda
  anti-dual-read está verde.
- **Momento de reavaliação:** limpeza do acervo legado (junto de DT-001).
- **Status:** `aberta`.

#### DT-004 — Fixtures de teste que pré-carregam chaves legadas
- **Título curto:** testes semeiam `feedback-control-ciclos`/`-observacoes`/`-metas`.
- **Origem:** auditoria da F5-09 (MEDIUM) + certificação transversal (R3).
- **Evidência:** `docs/etapa-5-certificacao.md:93` (R3);
  `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md:106-108` (exemplos citados pela certificação:
  `src/pages/FeedbackDetalhePage.test.tsx:106`, `src/services/cicloEquipeService.test.ts:180`).
- **Impacto:** fixtures válidas, porém **não** são prova de autoridade soberana após o cutover.
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** são dados de teste; nenhuma prova de autorização depende delas após o
  cutover (as provas vivem nos validadores SQL e no CI).
- **Momento de reavaliação:** limpeza do acervo legado (junto de DT-001/DT-003).
- **Status:** `aberta`.

### B. Autorização e decisão de produto

#### DT-006 — Gate geral do Painel de ciclo usa alvo sintético (`{kind:"global"}`)
- **Título curto:** `cycle.team.panel.view` com `{kind:"global"}` — autoridade não soberana e decisão em aberto.
- **Origem:** F5-10 P5.3 (dívida `D5`), explicitamente fora do cutover de metas.
- **Evidência:** `docs/F5-10-P5.3-autoridade-painel-ciclo.md:84` (o gate usa o `case "global"` com alvo
  sintético, que o próprio código declara não ser autorização real —
  `src/authorization/authorizationPolicy.ts:319-328` — e **em produção o mundo sintético é vazio ⇒
  DENY**) e `:258-263` (`D5`: "permanece **dívida do domínio de ciclo/avaliação** … registrar que o
  gate geral do Painel **precisa de correção própria antes de produção**").
- **Impacto:** **material**: em produção o gate tende a **negar** o acesso ao Painel (mundo sintético
  vazio), enquanto em teste libera papéis; **quem** deve acessar o Painel e **por qual autoridade** é
  **decisão em aberto**. Não afeta a autoridade de metas (server-side) nem a integridade de dados.
- **Classificação:** **dívida não bloqueante** (com reavaliação obrigatória **antes de produção**).
- **Motivo de não bloqueio:** a F5-10 P5.3 fechou `D5` como não bloqueante do cutover de metas e a
  certificação transversal da Etapa 5 não registrou lacuna bloqueante; o efeito é de **acesso à tela**,
  não de concessão de autoridade de domínio — mas é a dívida mais material deste registro.
- **Momento de reavaliação:** **antes de produção** (hardening F6 ou atividade própria do domínio de
  ciclo/avaliação). Observação de cobertura: **este item não aparece na matriz `T1–T11`** de
  `docs/etapa-5-certificacao.md` — registrar como lacuna de cobertura daquela certificação.
- **Status:** `aberta`.

#### DT-007 — Remoção de nota de avaliação sem API de exclusão
- **Título curto:** limpar nota gravada não a apaga (`evaluation_gravar_notas` aceita `1..5`).
- **Origem:** `.ai/handoff.md` (pendências conhecidas da atividade de cutover de avaliações).
- **Evidência:** `.ai/handoff.md:1898-1900` ("limpar uma nota já gravada não a apaga (não há API de
  exclusão). O valor anterior permanece — alteração de contrato exigiria nova `Q#`");
  `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:88` lista "ausência de exclusão de
  nota/comentário, se mantida como decisão de produto" entre os itens não bloqueantes do checkpoint.
- **Impacto:** usuário não consegue reverter uma nota para "sem nota"; a alteração exige mudança de
  contrato (nova `Q#`), portanto é decisão de produto.
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** comportamento declarado e aceito; não afeta autorização, tenant ou
  integridade.
- **Momento de reavaliação:** decisão de produto (nova `Q#`) antes de qualquer implementação.
- **Status:** `aberta`.

### C. Validação, CI e diagnóstico

#### DT-008 — Defeito latente de diagnóstico `22P02` em `41-validar-f5-11-p3.sql`
- **Título curto:** `v_falhas || 'literal'` em `text[]` troca `[FAIL]` legível por erro de array.
- **Origem:** F5-11 (F4-09/P1.1/P4 registram a dívida como pré-existente e **não tocada**) +
  certificação da F5-11 + certificação transversal.
- **Evidência:** `docs/F5-11-certificacao.md:102` (dívida 2) e `docs/etapa-5-certificacao.md:95` (R5);
  `docs/F5-11-desenho-tecnico.md:1474` e `:1483` (mecanismo: o PostgreSQL resolve a concatenação como
  **array** ⇒ `22P02` em vez do diagnóstico) e `:1620` ("A dívida diagnóstica pré-existente `22P02`
  **não foi tocada**"); `.ai/handoff.md:96` ("a dívida pré-existente `22P02` **não** foi tocada").
  **Um único ID agrupa as quatro fontes** (mesma dívida, descrita por ângulos diferentes).
- **Impacto:** apenas **diagnóstico** de validação: quando uma guarda da P3 falhar, o validador aborta
  com `malformed array literal`/`22P02` em vez de reportar `[FAIL]`. **Não afeta autorização nem dado.**
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** adormecido enquanto os validadores passam; fail-closed preservado
  (aborta de qualquer forma).
- **Momento de reavaliação:** próxima atividade que tocar validadores da P3/P5.1 (correção de 1 linha
  por sítio, sem alterar asserções).
- **Status:** `aberta`.

#### DT-009 — Prova literal de transferência entre organizações (validador da P5.1)
- **Título curto:** falta a fixture de segunda organização no validador da P5.1.
- **Origem:** P5.1 + certificação da F5-11 + certificação transversal (R4).
- **Evidência:** `docs/F5-11-certificacao.md:101` (dívida 1) e `docs/etapa-5-certificacao.md:94` (R4).
- **Impacto:** a regra está provada **pela elegibilidade por membership** e o trigger é por linha de
  membership; falta a prova **literal** (provisionar na membership nova e revogar na antiga).
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** a semântica exigida está provada por via equivalente (blocos C6/C7 do
  validador `43`, conforme a certificação).
- **Momento de reavaliação:** próxima atividade sobre o par `42`/`43` (a fixture `f5c1` já existe).
- **Status:** `aberta`.

#### DT-010 — Cenário `42-cenario-f5-11-p5-1.sql` derivando tenant da P2
- **Título curto:** cenário da P5.1 não é 100% autossuficiente (organização/ciclo herdados).
- **Origem:** P5.1 + certificação da F5-11 + certificação transversal (R6).
- **Evidência:** `docs/F5-11-certificacao.md:103` (dívida 3) e `docs/etapa-5-certificacao.md:96` (R6).
- **Impacto:** fragilidade de fixture: a organização/ciclo vêm do tenant da P2; a fixture SELF
  dedicada (`f5c1`) é própria, mas a base é herdada.
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** o cenário passa e as provas são discriminantes; a fragilidade é de
  manutenção, não de evidência.
- **Momento de reavaliação:** junto de DT-009 (mesmo par de arquivos).
- **Status:** `aberta`.

> **`DT-013` não é dívida:** foi **reclassificado como FINDING BLOQUEANTE** — ver **§0.1** (ID
> preservado e não reutilizável; a correção exige **Issue própria antes do fechamento da #258**).

### D. Documentação

#### DT-014 — Fases P5.1–P5.4 sem seção própria no desenho técnico da F5-11
- **Título curto:** registros §-numerados do desenho param na §23 (P5).
- **Origem:** certificação da F5-11 (§5, não verificado/lacuna documental).
- **Evidência:** `docs/F5-11-certificacao.md:119-121` ("a família P5.1–P5.4 está registrada no handoff,
  no CI e nas migrations, mas **não** em uma seção própria do desenho (lacuna **documental**, não
  funcional)").
- **Impacto:** rastreabilidade documental fragmentada (a prova existe; a narrativa do desenho, não).
- **Classificação:** **dívida não bloqueante** (documental).
- **Motivo de não bloqueio:** não altera comportamento, contrato nem prova; o fechamento da Etapa 5
  (`docs/etapa-5-certificacao.md`) consolida a matriz com evidência citável.
- **Momento de reavaliação:** próxima atividade documental do domínio de observações.
- **Status:** `aberta`.

#### DT-015 — Registros históricos do handoff que podem ser lidos como estado atual
- **Título curto:** handoff contém bullets de época que contradizem o estado vigente.
- **Origem:** consolidação desta atividade (Issue #258).
- **Evidência:** `.ai/handoff.md:351-353` afirma "**P2 e P3 NÃO foram iniciadas.** Nenhuma RPC
  `observacao_*`, nenhuma função de domínio, nenhuma policy de leitura, nenhum Edge, nenhum cutover…" —
  em contradição com o estado vigente (P2 e P3 integradas: migrations
  `supabase/migrations/20260931000000_f5_11_p2_observacoes_rpc.sql` e
  `supabase/migrations/20260932000000_f5_11_p3_authorization_observacoes.sql`, registradas em
  `docs/etapa-5-certificacao.md:34-36`).
- **Impacto:** risco de leitura errada do estado por agentes/humanos que consultem o handoff
  (o handoff é, por desenho, um registro histórico — mas bullets de estado lidos isoladamente
  enganam).
- **Classificação:** **dívida não bloqueante** (documental).
- **Motivo de não bloqueio:** a fonte de verdade de estado é `docs/etapa-5-certificacao.md`,
  `.ai/virtus-context.md` e o próprio código; o histórico **não deve** ser apagado (regra desta
  atividade: não remover conhecimento vigente).
- **Momento de reavaliação:** próxima atualização de handoff (marcar o bullet como registro de época,
  como já se faz em outros pontos).
- **Status:** `aberta`.

### E. Processo e governança

#### DT-016 — Desvio de processo: implementação iniciada antes da Issue da fase
- **Título curto:** atividade implementada antes de existir a Issue correspondente (P3 da F5-11).
- **Origem:** governança/processo (registro do handoff) — **não** é defeito funcional.
- **Evidência:** `.ai/handoff.md:98-101` ("P3 — DESVIO DE PROCESSO REGISTRADO (não ocultado): a
  implementação da P3 **começou antes de existir a Issue da fase** … A Issue **#246** … foi criada
  **depois** pelo orquestrador, que **regularizou** a rastreabilidade Issue-antes-do-código"); a regra
  correspondente está em `.ai/workflow.md` (Issue → branch → implementação).
- **Impacto:** risco de rastreabilidade (código executado antes de o contrato estar publicado);
  **regularizado** e registrado sem ocultação.
- **Classificação:** **dívida não bloqueante** (processo/governança).
- **Motivo de não bloqueio:** a rastreabilidade foi regularizada (Issue #246) e o desvio ficou
  documentado; é risco de processo recorrente, não defeito de produto.
- **Momento de reavaliação:** permanente — a regra "Issue antes do código" vale para toda atividade
  nova; reavaliar se o desvio voltar a ocorrer.
- **Status:** `absorvida` (regularizada na Issue #246).

### F. Ciclo e estrutura (resíduos)

#### DT-017 — Resíduo morto histórico do domínio de ciclos
- **Título curto:** `ImpactoTemporalPeriodoCiclo.observacoes`, `persistirCorrecaoPeriodoCicloAtivoInterno`,
  `confirmarCorrecaoPeriodoCiclo.ts`.
- **Origem:** F5-11 (dívida declarada) + certificação transversal.
- **Evidência:** `docs/F5-11-certificacao.md:107` (dívida 7) e `.ai/handoff.md:237` (fora de escopo/dívidas).
- **Impacto:** código morto no domínio de ciclos/correções; não está no caminho funcional de observações.
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** sem consumo no caminho funcional avaliado pelas fases.
- **Momento de reavaliação:** limpeza do domínio de ciclo (junto de DT-001/DT-003).
- **Status:** `aberta`.

#### DT-018 — Listagem administrativa de legado e ausência de listagem soberana alternativa
- **Título curto:** `ColaboradorDetalhePage` lista histórico do acervo legado; sem listagem soberana
  "por ciclo/colaborador" (descoberta de id fora da URL).
- **Origem:** atividade de cutover de avaliações (pendências conhecidas no handoff).
- **Evidência:** `.ai/handoff.md:1891-1893` (listagem do histórico administrativo é do acervo legado;
  adotar a leitura soberana ali é aditivo) e `.ai/handoff.md:1901-1903` (listagem administrativa do
  legado permanece; descoberta de id fora da URL depende de URL/painel).
- **Impacto:** funcionalidade limitada (sem listagem soberana de avaliações por ciclo/colaborador);
  não afeta autorização (a leitura é do acervo legado, exibição).
- **Classificação:** **dívida não bloqueante**.
- **Motivo de não bloqueio:** declarada como não bloqueante do critério de conclusão da atividade
  (`.ai/handoff.md:1894`).
- **Momento de reavaliação:** próxima atividade do domínio de avaliações/colaboradores.
- **Status:** `aberta`.

## 2. Fora de escopo (registrados, não contratados)

> **QUADRO-RESUMO (não é o formato completo).** Cada linha deste quadro traz apenas **ID**, **item
> (título curto)**, **evidência** e **motivo de não contratação** — o **status** é dado pela própria
> seção (`fora de escopo`) e a **origem** está na evidência citada. O formato **COMPLETO**, com os
> **9 campos** (ID, título, origem, evidência, impacto, classificação, motivo de não bloqueio, momento
> de reavaliação e status), é o do **§1** — quadro-resumo não substitui o bloco completo quando a
> dívida for reavaliada.

| ID | Item | Evidência | Por que fora de escopo |
| --- | --- | --- | --- |
| **DT-005** | `feedbackStorage` legado somente leitura | `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:85` | item não bloqueante declarado no checkpoint; leitura legada |
| **DT-011** | Fidelidade do harness local aos pares de concorrência do CI | `docs/F5-11-certificacao.md:105` | limitação de ambiente; a autoridade é o CI do SHA final |
| **DT-012** | 2 falhas pré-existentes de testes em Windows/CRLF (`AcompanhamentoMetasPage.test.tsx`, `MinhasMetasPage.test.tsx`) | `docs/F5-11-certificacao.md:104`, `docs/etapa-5-certificacao.md:97` e `docs/F5-10-p7-matriz-integrada.md:264-266` (o `npm test` passou no runner Linux, confirmando CRLF do working copy Windows) | não contratada pela Etapa 5; o CI oficial passa |
| **DT-019** | `gh` indisponível ⇒ abertura de PR/merge manual (DEV-04) | `docs/F5-11-certificacao.md:106`; `.ai/git-rules.md:64` | limitação de ambiente/processo; DEV-04 define a entrega de branch+SHA |
| **DT-020** | Escala/expectativas locais usadas apenas por telas legadas | `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:87` | item não bloqueante do checkpoint |
| **DT-021** | Importação do acervo legado real / histórico antigo | `docs/etapa-5-certificacao.md:98` (R8) e `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:86` | exige decisão de produto (`docs/F5-07-desenho-tecnico.md` §20.6, citado em R8) |
| **DT-022** | Redesign visual e hardening/observabilidade de produção (F6) | `docs/etapa-5-certificacao.md:99` (R9) e `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:90` | fase própria (F6) |
| **DT-023** | Negação fail-closed quando existem duas ocorrências vigentes | `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:89` | comportamento **aceito** (fail-closed); item não bloqueante declarado |

## 3. Concluídas / absorvidas

> **QUADRO-RESUMO (não é o formato completo).** Cada linha deste quadro traz apenas **ID**, **item
> (título curto)**, **como foi absorvida** e **evidência** — o **status** é dado pela própria seção
> (`concluída`/`absorvida`) e a **origem** está na evidência citada. O formato **COMPLETO**, com os
> **9 campos**, é o do **§1** (os blocos das dívidas absorvidas permanecem com o bloco completo quando
> existirem, com `Status: absorvida`).

| ID | Item | Como foi absorvida | Evidência |
| --- | --- | --- | --- |
| **DT-024** | `observation.edit`/`observation.delete` **sem enforcement** (`▸(add authorize)` no desenho da F4-09) | a F5-11 entregou o gate funcional, a Edge e o adapter; o `authorize` do domínio de observações passou a existir no caminho de produção | `docs/F4-09-desenho-tecnico.md:253-255` (estado original) × `docs/F5-11-certificacao.md` (P2/P3/P4 certificadas) e `docs/etapa-5-certificacao.md:42-52` |
| **DT-025** | Ausência de trigger para `user_profiles.status` (limitação declarada na migration da P5.1) | a P5.3 acrescentou o trigger de tabela que reavalia cada membership pela **mesma** função de provisionamento | `supabase/migrations/20260935000000_f5_11_p5_3_lifecycle_perfil_avaliado.sql:81-83` (`trg_f5_11_p5_3_perfil`, `after insert or update of status`) + bloco `I` do validador `supabase/validacao/43-validar-f5-11-p5-1.sql` (`docs/etapa-5-certificacao.md:36`) |
| **DT-026** | `PainelCicloPage` resolvendo o ciclo pelo storage legado (dívida `D4` da F5-10 P5.3) | o painel passou a resolver pelo **UUID soberano** (a substituição do `getCiclosAvaliacao().find(...)` pelo UUID está documentada no próprio arquivo) | `docs/F5-10-P5.3-autoridade-painel-ciclo.md:254-256` (D4) × `docs/etapa-5-certificacao.md:77-78` (cita `src/pages/PainelCicloPage.tsx:44`) |
| **DT-027** | Os três **BLOCKERS históricos** da Etapa 5 (ciclos com autoridade local; colaboradores/histórico locais; metas e observações fora do PostgreSQL) | demonstradamente resolvidos pelas fases F5-07 a F5-11, com evidência de validadores e pipeline | `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:55-81` (enunciado) × `docs/etapa-5-certificacao.md:30-36` (`B1`–`B3` **demonstradas**) |
| **DT-028** | Dívida **documental de processo**: conteúdo versionado de certificação/handoff não refletia o estado real do PR/CI (auditoria Codex reprovou o SHA por esse motivo) | corrigida naquele PR, sem correção de código; a prática de registrar gates executados × pendentes com marcador explícito passou a ser o padrão | `docs/F5-10-p7-matriz-integrada.md:267-270` |
| **DT-016** | **Desvio de processo:** implementação da P3 iniciada antes de existir a Issue da fase | regularizado pelo orquestrador, que criou a Issue **#246** e restabeleceu a rastreabilidade Issue-antes-do-código; desvio registrado sem ocultação | `.ai/handoff.md:98-101` |

## 4. Contradições encontradas entre fontes

> Registradas por exigência metodológica: **não** foram resolvidas por escolha unilateral. Em cada
> caso, as duas versões e os caminhos estão citados; a resolução pertence ao orquestrador.

**C1 — `cicloEquipeService.ts` e `historicoOrganizacionalStorage.ts`: "decisões operacionais" × "apresentação/UX".**
- Versão A (auditoria pré-P8): "`metaStorage.ts`, `observacaoStorage.ts`, `cicloEquipeService.ts` e
  `historicoOrganizacionalStorage.ts` ainda usam ciclo local e/ou bridges `(ano,ciclo)` **em decisões
  operacionais**" — `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md:104`.
- Versão B (certificação transversal): os mesmos arquivos são classificados como
  "**apresentação/UX apenas**" e "**não** participam de decisão de autorização"
  (`docs/etapa-5-certificacao.md:67-68`; ver também `:74-85`).
- Leitura possível: A descreve o estado **antes** do cutover da F5-09 (planejamento P5–P9) e B o estado
  **posterior**, já certificado. Ainda assim, a contradição fica **registrada** porque A usa a
  expressão "decisões operacionais" e B usa "apresentação/UX apenas" para os mesmos arquivos.

**C2 — Adapter de ciclos: "não há adapter Supabase/Edge para ciclos" × cutover entregue.**
- Versão A (auditoria pré-P8): "`localCycleRepository.ts` ainda é **exclusivamente local**; **não há
  adapter Supabase/Edge para ciclos**" — `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md:100`.
- Versão B: a F5-09 entregou o caminho soberano de ciclos e o `localCycleRepository` passou a ser
  **LEGADO declarado** sem consumidor soberano — `docs/etapa-5-certificacao.md:34` e `:70`, `:92` (R2).
- Leitura possível: contradição **de época** (A é insumo de planejamento; B é a certificação do estado
  final). Registrada como tal.

**C3 — Metas/observações: "não há tabelas PostgreSQL correspondentes" × `B3` demonstrada.**
- Versão A (checkpoint pós-F5-06): "esses domínios **não possuem** fonte server-side equivalente;
  **não há tabelas PostgreSQL correspondentes** nas migrations atuais"
  — `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:73-79`.
- Versão B: `B3` **demonstrada**, com F5-10/F5-11 certificadas e a cadeia `34…43` verde
  — `docs/etapa-5-certificacao.md:36`.
- Leitura possível: contradição **de época** (o checkpoint é o enunciado do blocker; a certificação
  registra a resolução). Registrada como tal.

**C4 — Estado das fases P2/P3 no handoff × estado vigente.**
- Versão A: "**P2 e P3 NÃO foram iniciadas.** Nenhuma RPC `observacao_*`…" — `.ai/handoff.md:351-353`.
- Versão B: P2 e P3 integradas, com migrations e validadores certificados
  — `supabase/migrations/20260931000000_f5_11_p2_observacoes_rpc.sql`,
  `supabase/migrations/20260932000000_f5_11_p3_authorization_observacoes.sql`,
  `docs/etapa-5-certificacao.md:34-36`.
- Leitura possível: A é um **registro de época** do próprio handoff (que é, por desenho, histórico). A
  contradição é real para quem lê o bullet isoladamente — origem da dívida **DT-015**.

## 5. Observações de cobertura desta consolidação

1. **Cobertura incompleta reconhecida:** a matriz `T1–T11` de `docs/etapa-5-certificacao.md` **não**
   inclui o gate geral do Painel de ciclo (dívida `D5` da F5-10 P5.3) — lacuna de **cobertura da
   certificação**, registrada no bloco **DT-006**.
2. **Dívida sem evidência suficiente para registro próprio:** não foram encontradas, nas fontes
   consolidadas, dívidas com impacto técnico que não pudessem ser citadas por documento existente. A
   ressalva é de **verificação**: as Issues (`#256`, `#258` e demais) **não são legíveis** neste
   ambiente (`gh` ausente), portanto qualquer dívida que exista **apenas** no texto de uma Issue
   permanece **não registrada aqui**.
3. **Dívidas consolidadas a partir de mais de uma fonte (um ID, várias evidências):** **DT-001**
   (certificação transversal `R1` + auditoria da F5-09), **DT-002** (F5-08 P6 §7 + auditoria da F5-09),
   **DT-008** (certificação da F5-11 + desenho técnico da F5-11 em três pontos + handoff),
   **DT-012** (certificação da F5-11 + certificação transversal + matriz integrada da F5-10 P7) e
   **DT-027** (checkpoint da Etapa 5 + certificação transversal).
4. **Nada foi transformado em Issue** e nenhuma correção foi implementada: a regra "dívida → Issue
   somente por decisão explícita do orquestrador" está descrita no topo deste documento e **não** foi
   executada.
