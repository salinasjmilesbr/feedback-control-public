# F5-10 P6 (Issue #220) — LACUNA ARQUITETURAL: leitura de metas além do contrato soberano

> **STATUS: IMPLEMENTAÇÃO PARADA — aguardando decisão.**
> Branch: `feat/f5-10-p6-cutover-metas` · Baseline: `86074c5bf24f40cc243822b03b5a4fe6d6d87815`
> Nenhuma linha de código de produto foi escrita. Nenhuma RPC, capability ou RLS foi
> criada/alterada. Este documento é o registro obrigatório de dúvida arquitetural.

## 0. Como a evidência foi obtida

1. Leitura do SQL soberano real (baseline + migrations P2–P4):
   `supabase/migrations/20260925000000_f5_10_p4_authorization_rls.sql:2146-2255`
   (`meta_listar_por_escopo`) e `:210-250` (`f5_10_vinculo_meta_do_ator`).
2. Leitura dos call sites reais dos consumidores de metas (páginas e serviços), com
   `arquivo:linha` citado em cada lacuna abaixo.
3. Preflight de ambiente executado no baseline: Docker OK, Supabase local OK,
   `db reset` OK, estado conferido no banco (`policies_public=23`,
   `metas_policies=0`, `authenticated` sem `SELECT` em `evaluation_goals`,
   `meta_listar_por_escopo` presente).

## 1. Contrato soberano de LEITURA que existe hoje (fonte única)

`meta_listar_por_escopo(p_organization_id uuid, p_cycle_id uuid, p_actor_user_profile_id uuid)`
— `20260925000000_f5_10_p4_authorization_rls.sql:2154`.

- Gate: capability `goal.read` **e** relação aceita, aplicada dentro da RPC.
- **Linhas devolvidas** (`:2194-2219`): **somente** as metas em que o ator é
  - `SELF` → `g.collaborator_id = f5_10_vinculo_meta_do_ator(ator, org)`, ou
  - `APROVADOR_GERENTE_CONGELADO` / `APROVADOR_COORDENADOR_CONGELADO` → a partir do
    **snapshot congelado** da avaliação original do dono (`f5_10_aprovador_congelado`).
- Recorte obrigatório por **um** ciclo (`p_cycle_id`); não há leitura cross-cycle.
- Sem paginação, sem agregados, sem contagens.
- Projeção devolvida (porta `src/application/ports/GoalRepository.ts`,
  `MetaSoberana`): `id, organizationId, cycleId, collaboratorId, tipo, descricao, kpi,
  valorAlvo, status, progressoPercentual, resultadoAtual, resultadoFinal, atingida,
  excluida, version, relacao, aprovacoesVigentes`. **Não há `dataCriacao`/timestamp de
  criação de meta.**
- A Edge `metas` expõe **apenas** essa operação de leitura (`goal.listar_por_escopo`);
  as outras 8 operações são mutações.

**Consequência direta:** qualquer tela/serviço que precise de metas de **terceiros que
não sejam o dono (SELF) nem o aprovador congelado**, de **mais de um ciclo**, de
**agregados** ou do **timestamp de criação** da meta **não é atendido** pelo contrato
soberano atual.

## 2. Lacunas identificadas (formato exigido: consumidor → necessidade → contrato → lacuna → alternativas → recomendação)

### L1 — Painel do ciclo (escopo de painel/equipe)

1. **Consumidor:** `src/pages/PainelCicloPage.tsx:101` — `getMetasDoCiclo(cicloAtual.id)`
   (todas as metas do ciclo), usado no KPI de metas pendentes
   (`:147-160`) e no recorte por vínculo (`:104-116`).
2. **Necessidade:** ler metas de **todos os colaboradores do ciclo** para contar
   pendências do perfil que está vendo a tela.
3. **Contrato atual:** `goal.listar_por_escopo` devolve apenas SELF + aprovador
   congelado da avaliação original de cada dono (`P4:2194-2219`).
4. **Lacuna:** a tela decide acesso a metas por **`usuario.funcao === "GERENTE"`**
   (`:141`) e por **`linha.colaborador.gestorDiretoMatricula === usuario.matricula`**
   (`:142`) — ou seja, hierarquia **viva** e `funcao` como autoridade, exatamente o que
   o Bloco D proíbe. O contrato soberano não tem (nem deveria ter por engano) um escopo
   "painel": o aprovador congelado é um fato histórico por meta, não um papel de tela.
5. **Alternativas (sem implementar nada nesta atividade):**
   - (A) **Decisão de autoridade primeiro:** definir quem pode ler metas de quem em
     escala de painel (snapshot congelado × hierarquia viva × capability administrativa
     `goal.read` por organização/unidade) e só depois decidir a superfície;
   - (B) **Nova operação soberana de leitura de painel** (atividade própria, com
     contrato/gate/capability e análise de RLS próprios) — fora do escopo declarado da
     P6 ("não crie RPC nova", "não amplie `goal.read` silenciosamente");
   - (C) **Reescopo de produto:** o KPI do painel passa a contar apenas o que o ator
     legitimamente lê (SELF + aprovador congelado) — muda o significado do número;
   - (D) **Manter o painel legado** nesta entrega e migrar só os consumidores
     compatíveis — aceita explicitamente legado remanescente (contraria o critério 1–4
     da Issue).
6. **Recomendação:** (A) → depois (B) ou (C), por decisão do owner. Não implementar
   nenhuma delas dentro da P6.

### L2 — Pendências de metas por colaborador (relatório de equipe)

1. **Consumidor:** `src/services/cicloEquipeService.ts:596-620` —
   `getMetasDoCiclo(ciclo.id)` para montar pendências por colaborador
   (`colaboradorId`, `colaboradorNome`, `detalhes: [descricao]`).
2. **Necessidade:** varrer as metas de **todo o ciclo**, cruzando com aplicabilidade do
   colaborador, para listar pendências de fechamento.
3. **Contrato atual:** idem L1 (SELF + aprovador congelado, um ciclo, sem agregados).
4. **Lacuna:** escopo de leitura de equipe/organização inexistente no contrato; a
   projeção soberana também não traz `colaboradorNome` (rótulo de apresentação que hoje
   vem do registro legado).
5. **Alternativas:** as mesmas de L1 (A–D).
6. **Recomendação:** mesma de L1; agrupar L1+L2 em uma única decisão de escopo de
   painel/equipe.

### L3 — Impacto da correção de período do ciclo (escopo de ciclo + campo ausente)

1. **Consumidores:** `src/services/correcaoPeriodoCicloService.ts:53`
   (`getMetasDoCiclo(ciclo.id, true)` — inclusive excluídas) e
   `src/services/impactoCorrecaoPeriodoCiclo.ts:51-56`
   (`meta.cicloId`, `meta.dataCriacao`, `meta.id`).
2. **Necessidade:** contar/identificar **todas** as metas do ciclo criadas fora do novo
   período, para o registro de impacto da correção.
3. **Contrato atual:** `meta_listar_por_escopo` (escopo SELF/aprovador, um ciclo) **e**
   a projeção `MetaSoberana` **não expõe `dataCriacao`** (`GoalRepository.ts:78-97`).
4. **Lacuna:** duas, independentes — (i) escopo cycle-wide (L1) e (ii) **campo de
   auditoria ausente** na projeção soberana; sem ele a regra de impacto não é
   calculável nem com escopo ampliado.
5. **Alternativas:**
   - Para (i): as mesmas de L1;
   - Para (ii): expor o timestamp de criação na projeção soberana (mudança de contrato
     da operação de leitura — atividade/decisão própria) **ou** mover o cálculo de
     impacto para o servidor (fora do escopo da P6);
   - (E) Reescopo: a correção de período deixa de reportar impacto de metas.
6. **Recomendação:** não ampliar a projeção dentro da P6; decidir junto com o escopo de
   ciclo (L1/L2).

### L4 — PDF de avaliação (metas de terceiro, ciclo resolvido por ano/número)

1. **Consumidor:** `src/services/exportarAvaliacaoPdf.ts:101-112` —
   `getMetasDoColaboradorNoCiclo(colaborador.matricula, cicloDaAvaliacao.id)`, com o
   ciclo resolvido por `getCiclosAvaliacao().find(ano, ciclo)` (`:101`).
2. **Necessidade:** incluir no PDF de avaliação as metas do **colaborador avaliado**
   (terceiro), no ciclo daquele feedback.
3. **Contrato atual:** leitura só de SELF/aprovador congelado; e o `cycleId` UUID
   soberano não é obtido por (ano, número) na superfície de metas.
4. **Lacuna:** se quem exporta **não** for o aprovador congelado do avaliado, não há
   caminho soberano; e a resolução do ciclo por rótulo local (`ano`/`ciclo`) é
   dependência do domínio de CICLOS (fora do escopo da P6), com o agravante do critério
   "zero ciclo funcional resolvido por ID local legado".
5. **Alternativas:**
   - (A) Confirmar que o exportador é sempre o aprovador congelado (então cabe no
     contrato; resta só resolver o `cycleId` soberano por `ano`/`numero` via
     `CycleRepository` — leitura de ciclos, não de metas);
   - (B) Superfície de exportação/relatório própria (atividade própria);
   - (C) Reescopo: PDF deixa de listar metas.
6. **Recomendação:** decidir se o PDF é caso de "terceiro autorizado" (aprovador
   congelado) ou de relatório administrativo — a resposta muda completamente o desenho.

## 3. Consumidores que **cabem** no contrato atual (não bloqueiam)

| Consumidor | Escopo | Evidência |
|---|---|---|
| `src/pages/MinhasMetasPage.tsx:120` | SELF (`usuario.matricula`) | cabe em `goal.listar_por_escopo` |
| `src/pages/MinhaAvaliacaoDetalhePage.tsx:115` | SELF (`usuarioAtual.matricula`) | cabe |
| `src/pages/AcompanhamentoMetasPage.tsx:130` | terceiro **se** aprovador congelado (`colaboradorAtual`) | a confirmar na implementação (relação congelada) |
| `src/pages/NovoFeedbackPage.tsx:307` e `src/pages/EditarFeedbackPage.tsx:513` | terceiro (colaborador do feedback) | idem |

Ressalva comum: essas telas hoje decidem aprovação/exigência **localmente**
(`metaEstaAprovada`, `metaExigeAprovacaoCoordenador` — `MinhasMetasPage.tsx:133,548,554`;
`AcompanhamentoMetasPage.tsx:135,175,180`; `NovoFeedbackPage.tsx:312`;
`EditarFeedbackPage.tsx:519`), o que o Bloco D proíbe; a substituição pela **fato**
soberano (`aprovacoesVigentes`/`relacao`) é viável apenas para as metas que o ator pode
ler — o que reforça que o bloqueio é o escopo, não a tela.

## 4. O que NÃO foi feito (por contrato)

- Nenhuma RPC nova, nenhuma capability nova, nenhuma alteração de RLS.
- Nenhum backfill, importador, staging, quarentena ou mapa legacy→UUID.
- Nenhum dado legado migrado ou preservado.
- Nenhuma alteração de código de produto (a árvore de trabalho contém apenas este `.md`
  e os scripts de recon/preflight em `.git/`).

## 5. Decisão necessária (para o owner/auditoria)

1. **Regra de autoridade de leitura em escala de painel/equipe:** snapshot congelado,
   hierarquia viva, capability administrativa por organização/unidade, ou outra?
2. **Escopo da P6 diante do bloqueio:** (i) ampliar contrato soberano em atividade
   própria e depois retomar a P6; (ii) reescopar o produto (painel/impacto/PDF deixam de
   ver metas de terceiros); (iii) entregar P6 parcial para os consumidores SELF/
   aprovador-congelado e registrar o legado remanescente de forma explícita.
3. **Projeção soberana:** expor `dataCriacao` (e talvez rótulos de apresentação do dono)
   na leitura, ou mover o cálculo de impacto para o servidor?
4. **Dependência de ciclos:** como os consumidores de metas obtêm o `cycleId` UUID
   soberano (por `ano`/`numero` via `CycleRepository`), já que hoje usam
   `getCiclosAvaliacao()` (localStorage de ciclos, domínio da F5-09)?


## 6. ANEXO — Inventário real do legado (recon estático repo-wide)

### 6.1 Superfície de `src/services/metaStorage.ts` (616 linhas, 12 exports, 100% síncrona)

| export | linha | lê | grava | observação |
|---|---|---|---|---|
| `getMetasDoColaboradorNoCiclo` | `:40-57` | `getTodasMetas()` | — | filtra matrícula+ciclo, exclui `excluida` |
| `getMetasDoCiclo` | `:59-72` | idem | — | **cycle-wide** |
| `contarMetasPorTipo` | `:74-81` | idem | — | **export morto** (só uso interno `:260`) |
| `metaExigeAprovacaoCoordenador` | `:171-199` | estrutura + ciclo local | — | autorização local |
| `metaEstaAprovada` | `:201-218` | campos `aprovacao*` do objeto | — | aprovação como campo, não fato |
| `podeAprovarMetaNoCiclo` | `:220-247` | estrutura local | — | paridade com o engine testada |
| `criarMeta` | `:249-306` | metas + ciclo local + quota local | `persistir` `:304` | `crypto.randomUUID()` `:281` |
| `atualizarMeta` | `:308-390` | `:322` | `:343-389` | invalida aprovações |
| `aprovarMeta` | `:392-521` | `:401` | `:456-480` | `domainState` **hardcoded true** `:421` |
| `excluirMeta` | `:523-568` | `:529` | `:543-567` | soft delete |
| `atualizarAcompanhamentoMeta` | `:570-629` | `:590` | `:604-628` | não invalida aprovação |
| `finalizarMeta` | `:631-684` | `:644` | `:658-683` | **não checa status** => re-finalização silenciosa |

Internos relevantes: `STORAGE_KEY` `:24`; `getTodasMetas` `:26-34`; `persistir` `:36-38`
(regrava o array INTEIRO); `autorizarMetaPropria` `:106-127` (**autorização local** via
`authorize()` + `criarProvidersMundoLocal`).

### 6.2 Contagens (repo inteiro)

| item | nº | onde |
|---|---|---|
| importadores de `metaStorage` | **12** (8 produção, 4 teste) | sem barrel, sem reexport, sem `import type` |
| ocorrências de `feedback-control-metas` | **19** em 9 arquivos (3 produtivos) | + 2 em docs |
| `.rpc("meta_…")` no cliente | **0** (9 na Edge `index.ts:296-391`) | — |
| `.from("evaluation_goal…")` no cliente | **0** (1 real: `functions/metas/index.ts:196`) | — |
| `crypto.randomUUID()` de identidade de meta | **13** (2 arquivos) | `metaStorage.ts:281,296,350,366,470,506,554,616,671`; `geradorDadosTeste.ts:324,346,353,362` |
| `sessionStorage` em `src/` | **0** | — |
| testes que exercitam o legado | **11 arquivos** | — |
| guardas estáticas com metas/localStorage | **7 arquivos** | 3 quebram por construção no corte |

### 6.3 Achados que agravam o risco do cutover (todos com evidência)

1. **Autorização local na tela principal:** `MinhasMetasPage.tsx:5-8,82-93` monta
   `criarProvidersMundoLocal(usuario, colaboradores)` + `LOCAL_ORGANIZATION_ID` e decide
   `goal.write` com `can(...)` — o oposto do Bloco D ("browser não decide autorização de
   meta"). É também um dos dois únicos produtores que citam `providers/localWorld`, e a
   guarda `estruturaUiSeguranca.test.ts:504-509` exige **igualdade exata** dessa lista.
2. **Segundo writer oculto da mesma chave:** `geradorDadosTeste.ts:529-532` regrava
   `feedback-control-metas` inteiro, e o módulo está no **grafo de produção** por
   `ColaboradoresPage.tsx:36` (import estático; o gate `simulacaoDevPermitida`
   `:460-462` é de **runtime**, não de import). `resetBaseDesenvolvimento.ts:23,36-38`
   apaga a chave.
3. **Quota com duas autoridades:** legado em `feedback-control-ciclos`
   (`quantidadeMetasNegocio/Individuais`, `cicloAvaliacaoStorage.ts:109-110`), lido por
   `MinhasMetasPage.tsx:124-128`; soberano em `evaluation_cycle_goal_limits`
   (`meta_definir_limites_do_ciclo`). `atualizarConfiguracaoMetasCiclo`
   (`cicloAvaliacaoStorage.ts:327-359`) **não tem chamador**.
4. **Ciclo ativo resolvido localmente:** `MinhasMetasPage.tsx:10,58` (`getCicloAtivo()`),
   `exportarAvaliacaoPdf.ts:101` e `MinhaAvaliacaoDetalhePage.tsx:108`
   (`getCiclosAvaliacao().find(ano, ciclo)`) — o `cycleId` UUID soberano não vem desses
   caminhos (ver §5.4).
5. **Testes que byte-comparam / semeiam a chave** e guardas de lista fechada
   (`metaStorage.test.ts`, `cutoverEstruturalServicos.test.ts:351,385`,
   `AcompanhamentoMetasPage.test.tsx:34`, `cancelamentoCicloService.test.ts:77-83`,
   `correcaoPeriodoCicloService.test.ts:231`, `reaberturaCicloService.test.ts:131,148`,
   `estruturaUiSeguranca.test.ts:391-411,504-509,553-558`) terão de ser reescritos no
   MESMO commit do corte, sob pena de CI vermelho.
6. **`src/types/Meta.ts` não é 100% legado:** `GoalRepository.ts:46` e
   `repositorioMetasSoberanas.ts:51` importam `StatusMeta` dele — a remoção do tipo
   quebra o caminho novo. E `repositorioMetasSoberanas.ts:307` usa
   `crypto.randomUUID()` como **`operationId`** (idempotência), não como identidade —
   qualquer guarda anti-UUID precisa distinguir os dois casos.

### 6.4 Consumidores de produção e escopo exigido (consolidado)

| arquivo:linha | operação | escopo | cabe hoje? |
|---|---|---|---|
| `MinhasMetasPage.tsx:120,133,162,207,238,247,286` | CRUD + progresso + finalização (SELF) | SELF | mutações SIM / **autorização local a remover** |
| `MinhaAvaliacaoDetalhePage.tsx:115` | leitura (SELF) | SELF | SIM |
| `AcompanhamentoMetasPage.tsx:130,163,175,180` | leitura + `aprovarMeta` | terceiro (aprovador congelado?) | a confirmar na implementação |
| `NovoFeedbackPage.tsx:307-312` | leitura p/ bloquear feedback | terceiro | idem |
| `EditarFeedbackPage.tsx:513-519` | leitura p/ bloquear feedback | terceiro | idem |
| `exportarAvaliacaoPdf.ts:107-112` | leitura p/ PDF | terceiro (por rótulo ano/ciclo) | **NÃO** (L4) |
| `PainelCicloPage.tsx:101,141-160` | cycle-wide p/ KPI | painel/equipe | **NÃO** (L1) |
| `cicloEquipeService.ts:596-621` | cycle-wide p/ pendências | painel/equipe | **NÃO** (L2) |
| `correcaoPeriodoCicloService.ts:53` + `impactoCorrecaoPeriodoCiclo.ts:51-56` | cycle-wide + `dataCriacao` | ciclo/administrativo | **NÃO** (L3) |

Mutações legadas x operações soberanas: `criarMeta`->`goal.criar`,
`atualizarMeta`->`goal.editar`, `atualizarAcompanhamentoMeta`->`goal.atualizar_progresso`,
`finalizarMeta`->`goal.finalizar`, `aprovarMeta`->`goal.aprovar`,
`excluirMeta`->`goal.excluir` — **cobertura 1:1, nenhuma mutação falta na Edge**.

## 7. ANEXO 2 — Limites da superfície soberana e defeito de transporte (recon dedicado)

### 7.1 Defeito verificado no adapter — bloqueia o critério 11 ("409 tratado explicitamente")

- `src/infrastructure/supabase/metas/edgeMetas.ts:180-195` lê o corpo do erro em
  `error.context.error.code` (mesmo padrão do molde `src/infrastructure/supabase/ciclos/edgeCiclos.ts:134-140`).
- **Verificação de primeira mão:** em `@supabase/functions-js`,
  `FunctionsHttpError.context` é o objeto **`Response`** —
  `node_modules/@supabase/functions-js/dist/main/FunctionsClient.js:96-97` documenta
  `await error.context.json()` e o throw em `:274` passa `response`. Um `Response` **não
  tem** `.error`.
- **Consequência:** `codigoPublico(undefined)` ⇒ **toda negação da Edge chega ao
  repositório/tela como `FORBIDDEN`** com a mensagem genérica. `CONFLICT` (409 —
  `expected_version` divergente, ciclo não ATIVO, estado/exclusão terminal, quota,
  `operation_id` com hash divergente, aprovação vigente duplicada) e `NOT_FOUND` (404)
  **nunca são distinguíveis**.
- **Por que é bloqueio da P6:** o Bloco C exige "conflito 409 tratado explicitamente;
  refresh soberano quando aplicável; informar estado de conflito; não simular sucesso".
  Sem corrigir o adapter, nenhuma tela consegue separar "sem permissão" de "versão
  divergente" — e o adapter é artefato **já merged e auditado da P5** (mudança exige
  decisão do owner).
- O teste do P5 não detecta: `src/infrastructure/supabase/metas/edgeMetas.test.ts:323-337,349-358`
  injeta `context` como objeto simples.

### 7.2 Matriz de limites do contrato soberano (o que NÃO existe hoje)

| Necessidade | Hoje | Evidência |
|---|---|---|
| Metas de terceiro que não é aprovador congelado | NÃO | P4:2235-2239 + P4:361-368 |
| Metas de um colaborador específico | NÃO | P4:2154-2158 (assinatura só org/ciclo/ator) |
| Metas de vários ciclos numa chamada | NÃO | P4:2234 (igualdade de ciclo) |
| Metas de unidade/organização inteira | NÃO | P4:2232-2239 |
| Agregados/contagens por tipo/status | PARCIAL | só `quantidade` do escopo (P4:2247), ignorado pelo repo (`:235-243`) |
| Nome/matrícula/cargo do dono | PARCIAL | outra superfície (`acessoColaboradoresSoberanos.ts:102-126`), join local, sem filtro por ciclo |
| Leitura de UMA meta por `goal_id` | NÃO | único caminho é o escopo do ciclo (P4:2154) |
| Paginação/limite | NÃO | `jsonb_agg` de todas as autorizadas (P4:2195-2240) |
| Histórico/trilha de eventos da meta | NÃO | `evaluation_goal_events` sem policy/grant e sem RPC de leitura |
| Quota/limites do ciclo para a UI | NÃO | tabela deny-by-default; só eco pós-escrita (P4:1706-1708); `CicloSoberano` não tem quota (`CycleRepository.ts:34-50`) |
| Quem aprovou | NÃO | `aprovacoes_vigentes` projeta papel/id/data/motivo, não o aprovador (P4:2221-2230) |
| "Aprovação exigida" / "meta aprovada" | PARCIAL | fatos sim; a exigência condicional do COORDENADOR só existe em `f5_10_aprovador_congelado` (P3:329-369) |
| Filtrar apenas não excluídas | PARCIAL | flag vem no payload; filtro é do cliente (P4:2212) |
| Versão atual da meta / status do ciclo | SIM | P4:2213 / P4:2245 |
| Mutações | 8 | `contrato.ts:53-62` |

### 7.3 Lacunas adicionais (além de L1–L4)

- **E1 — sem leitura de uma meta por `goal_id`:** deep link/notificação por meta obriga a
  baixar o ciclo inteiro e filtrar; fora do escopo autorizado o resultado é **ausência na
  lista** (não um 404 explícito).
- **E2 — sem paginação:** um único `jsonb` com todas as metas autorizadas do ciclo.
- **E3 — quota sem superfície:** o KPI legado "N de M metas" (`MinhasMetasPage.tsx:124-128`)
  fica **sem fonte soberana**; `CicloSoberano` não carrega quota.
- **E4 — histórico da meta órfão:** o legado exibia `historico[]` (`types/Meta.ts:26-40,80`);
  não há leitura de eventos.
- **E5 — aprovação sem identidade:** não há como exibir **quem** aprovou.
- **E6 — assimetria de fronteiras na mesma tela:** metas por Edge + `service_role`; ciclos
  por PostgREST + RLS (`20260919000000_f5_09_cycle_read_rls.sql:170-178`) — a própria P5
  registra que `evaluation_cycles` não foi tocada (P5H:15).
- **E7 — `relacao` é rótulo derivado** (CASE P4:2214-2220): quem é gerente **e** coordenador
  congelado recebe sempre `GERENTE`.
- **E8 — não existe `src/services/metasSoberanos/**`** (nenhum serviço de metas no cliente);
  as 9 telas/serviços seguem no legado.
- **E9 — idempotência de leitura inerte:** `goal.listar_por_escopo` exige `operation_id`
  (`contrato.ts:286`) mas a RPC não o recebe (`index.ts:387-395`).
- **E10 — comentário stale no D22-A:** o cabeçalho de
  `supabase/migrations/20260927000000_f5_10_p5_d22a_hardening.sql:2` diz "PREPARADO, AINDA
  NAO APLICADO". O estado real foi verificado no preflight desta rodada
  (`db reset` OK; `policies_public=23`, `metas_policies=0`, `authenticated` sem `SELECT`
  em `evaluation_goals`), ou seja, **aplicado** — o comentário precisa de correção
  documental (arquivo já merged/auditado; não alterar sem decisão).
- **R2 — descarte silencioso:** linha fora do contrato é descartada em
  `repositorioMetasSoberanas.ts:231-233` e o `escopo` é derivado localmente (`:241`),
  ignorando `relacao_ator` do servidor: drift de contrato pode virar
  `SEM_META_AUTORIZADA` (vazio por anomalia), contra o que o próprio cabeçalho promete
  (`:23-25`).
- **R5 — rótulos ausentes** (`ano`/`numero`, nome, matrícula, cargo, datas) empurram a UI a
  reintroduzir resíduo local (`cicloAvaliacaoStorage`/`colaboradorStorage`) ou a inventar
  dado — proibido por D1/D8.

### 7.4 Decisões adicionais necessárias

5. **Corrigir o adapter** (ler `await error.context.json()`) antes de retomar a P6, ou
   aceitar P6 sem discriminação de 409?
6. **Quota do ciclo na UI:** nova leitura soberana (atividade própria) ou remover o KPI?
7. **Histórico da meta:** remover da UI ou criar superfície de leitura?
8. **Aprovação:** expor no servidor o fato derivado ("exigida"/"vigente", quem aprovou) ou
   simplificar a UI para mostrar apenas os fatos que já existem?
9. **Rótulos (`ano`/`numero`, nome do dono):** usar as superfícies soberanas existentes de
   ciclo/colaborador e proibir rótulo legado — confirmar essa direção.

## 8. ANEXO 3 — Classificação fina dos consumidores: escopo real, órfãos e lacunas duras

### 8.1 Correções de severidade (revisão do §2)

- **L4 (PDF) DEIXA de ser bloqueio:** `exportarAvaliacaoPdf.ts` tem um único chamador,
  `MinhaAvaliacaoDetalhePage.tsx:251` — **SELF**. Cabe no contrato; exige apenas virar
  assíncrono/pré-carregar as metas antes de gerar o PDF.
- **L2 e L3 são CÓDIGO ÓRFÃO hoje:** `cicloEquipeService.analisarPendenciasDoCiclo`
  (`:527-629`) e `correcaoPeriodoCicloService`/`impactoCorrecaoPeriodoCiclo` **não têm
  chamador de produção** (só testes). Não bloqueiam o cutover funcional; exigem decisão de
  destino (remover ou reativar em superfície soberana).
- **L1 permanece bloqueio:** `PainelCicloPage` é página viva e usa `getMetasDoCiclo` no KPI
  de metas pendentes (`:147-167`) e no botão "Acompanhar metas".

### 8.2 Lacunas que bloqueiam a rota funcional VIVA (além de L1)

| # | Lacuna | Consumidores | Por que não cabe |
|---|---|---|---|
| G1 | **"Meta aprovada"/"pendente" é INDERIVÁVEL** | `MinhasMetasPage.tsx:133,548,550`; `AcompanhamentoMetasPage.tsx:134-136,146-157,180`; `NovoFeedbackPage.tsx:311-313`; `EditarFeedbackPage.tsx:518-520` | A regra "coordenador exigido ⇔ ocorrência congelada `GESTAO_DIRETA` distinta de `GESTAO_CADEIA`" (`docs/F5-10-desenho-tecnico.md:287,304-308`; P3:358-368) **não é projetada**; `aprovacoes_vigentes` só tem fatos **decididos** — para o ator SELF, "não exigido" e "pendente" são indistinguíveis hoje |
| G3 | **Quota do ciclo sem leitura** | `MinhasMetasPage.tsx:124-128,480,602-620` ("X de Y", habilitar categoria e botão "Adicionar meta") | `evaluation_cycle_goal_limits` é deny-by-default e o port só tem `definirLimitesDoCiclo` (ESCRITA); `CicloSoberano` não carrega quota |
| G4 | **Nenhuma data na projeção** | `dataUltimoAcompanhamento` (`MinhasMetasPage.tsx:544`, `AcompanhamentoMetasPage.tsx:233`), `dataFechamento` (`MinhasMetasPage.tsx:590`), `dataCriacao` (`impactoCorrecaoPeriodoCiclo.ts:55`) | `MetaSoberana` não tem campo de data; a única é `aprovacoesVigentes[].decididoEm` |
| G5 | **Nome de quem aprovou ausente** | `AcompanhamentoMetasPage.tsx:269,297` | A projeção traz papel/id/data/motivo, sem nome/matrícula do aprovador |
| G6 | **Escopo painel/equipe** | `PainelCicloPage.tsx:101,137-167` | Ver L1: a tela deriva acesso de `funcao`/`gestorDiretoMatricula` **vivos**, enquanto a legitimidade soberana é a ocorrência **congelada** (D14/§9.1) |
| G12 | **Autorização de UX inexequível** | `MinhasMetasPage.tsx:82-93` (`criarProvidersMundoLocal`+`LOCAL_ORGANIZATION_ID`); `AcompanhamentoMetasPage.tsx:80-107`; `PainelCicloPage.tsx:137-197` (`can()` com `funcao`+mundo local) | Em PROD o mundo local é vazio ⇒ DENY; não existe loader de cliente para `{type:"goal", id}` (o de `contextoAutorizacao.ts:358-391` é só da Edge). A projeção traz `relacao`/`status`/`excluida`/`ciclo_status` — suficiente para habilitar ação por RELAÇÃO+ESTADO, **não** para capability |
| G11/G2 | **Pontes de UUID** | `MinhasMetasPage.tsx:58` (`getCicloAtivo()` legado, que **fabrica** UUID em `cicloAvaliacaoStorage.ts:52-81`); `PainelCicloPage.tsx:77` e `AcompanhamentoMetasPage.tsx:55` resolvem o UUID da URL contra o array local; identidade do dono é matrícula na UI e UUID no contrato | Decisão pendente: de onde vem o `cycleId` soberano e como a UI mapeia `collaboratorId` ↔ matrícula/nome |
| G8 | Mutações exigem `motivo` + `expectedVersion` que a UI não tem | `MinhasMetasPage.tsx:279-298` (`window.confirm`, sem motivo/versão); "Revisar fechamento" hoje reusa `finalizarMeta` (`:521`) | Cabe no contrato com mudança de UX — **mas depende de discriminar 409** (ver §7.1) |

### 8.3 Órfãos / código morto (decisão de destino)

- `atualizarConfiguracaoMetasCiclo` (`cicloAvaliacaoStorage.ts:327`) — **zero chamadores**;
  `CiclosAvaliacaoPage.tsx:617` é placeholder ⇒ **não existe consumidor de
  `definirLimitesDoCiclo`** hoje.
- `contarMetasPorTipo` (`metaStorage.ts:74-81`) — export morto.
- `analisarPendenciasDoCiclo`, `corrigirPeriodoCicloAtivo`,
  `analisarImpactoCorrecaoPeriodoCicloAtivo` — órfãos.

### 8.4 Confirmado que CABE no contrato (só exige virar assíncrono)

`MinhaAvaliacaoDetalhePage.tsx` (SELF, 1 ciclo, campos todos na projeção);
`exportarAvaliacaoPdf.ts` (SELF, idem); núcleo de aprovação de
`AcompanhamentoMetasPage.tsx` (relação congelada + `status`/`excluida`/`ciclo_status` +
`aprovacoes_vigentes[papel]`, ressalvadas G1/G5); aviso de metas sem aprovação em
`NovoFeedbackPage.tsx`/`EditarFeedbackPage.tsx` (só quando o avaliador é o aprovador
congelado); núcleo SELF de `MinhasMetasPage.tsx` (ressalvadas G1/G3/G4/G8/G11/G12);
`resetBaseDesenvolvimento.ts` (só limpeza DEV).

### 8.5 Decisões adicionais necessárias

10. **G1:** quem responde "meta aprovada" (todos os papéis exigidos) e como a UI separa
    "não exigido" de "pendente"?
11. **G3:** de onde a UI lê os limites do ciclo (D20 diz que só projeta)?
12. **G4/G5:** datas de acompanhamento/fechamento e nome do aprovador saem da UI ou vêm de
    outra superfície?
13. **G12:** confirmar que a decisão de UX passa a ser por RELAÇÃO+ESTADO da projeção
    (nunca por `can()`/`localWorld`/`funcao`).
14. **Órfãos:** `analisarPendenciasDoCiclo`, `corrigirPeriodoCicloAtivo`,
    `analisarImpactoCorrecaoPeriodoCicloAtivo` e `atualizarConfiguracaoMetasCiclo` são
    removidos na P6 ou reativados em superfície soberana futura?