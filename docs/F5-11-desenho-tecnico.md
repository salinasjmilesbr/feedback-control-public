# F5-11 — Observações soberanas e histórico auditável (contrato normativo)

> **Atividade:** F5-11 — Issue **#238**. **Base:** `main` = `5889decb81d4dc3feca15ca15d37f164e2f614ea`
> (squash do PR #236 / Issue #224). **Branch:** `docs/f5-11-observacoes-soberanas-desenho`.
> **PR:** **#239** (desenho) — **não fecha a Issue #238** (`Refs #238`): a Issue só se encerra na P6.
> **Natureza:** documento **NORMATIVO**. Este é o **P0** da F5-11: reconhecimento integral, desenho e
> **fechamento arquitetural**. As questões **Q1–Q16** foram **FECHADAS na alternativa A** por
> **auditoria GPT que aprovou o desenho** e estão registradas como **decisões normativas D1–D16 em §15**
> — **nenhuma questão permanece aberta**. `DECIDE` neste documento é vinculante para a implementação e
> não pode ser reinterpretado nas fases P1–P6.
> **Histórico:** `91b9c61` (reconhecimento + proposta de desenho, Q1–Q16 abertas com alternativas
> A/B/C); `6d527cc` (fechamento de Q1–Q16 = A como D1–D16, revisão transversal de matriz, modelo,
> riscos, cutover, decomposição, critérios de aceite e dependências entre pacotes); **P1
> implementada** — migration `20260929000000_f5_11_p1_observations_schema.sql`, cenário `34` e
> validador `35`, com a substituição dos guards invertidos (registro em **§18**, que **não altera
> D1–D16**).
> **Nenhuma migration, RPC, Edge Function, policy, RLS, capability, alteração funcional de UI,
> persistência ou teste funcional foi criada ou alterada nesta rodada.** A alteração é **documental**.
> **Regras de leitura:** onde este documento diz **DECIDE**, a decisão está **fechada** (§15, D1–D16);
> onde diz **DECIDE (herdado)**, é decisão fechada em contrato anterior (F4-* / F5-09 / F5-10) que
> **não se reabre** sem evidência técnica nova (`.ai/architecture-rules.md` §4). A rastreabilidade
> **Q# → D#** está em §15 (subseção **Rastreabilidade Q# → D#**).

## 1. Objetivo

Transformar o domínio legado de **Observações** — hoje 100% `localStorage`, monousuário, sem
autorização efetiva e com histórico embutido em objeto mutável — em um **domínio soberano**:
persistido no PostgreSQL, multiusuário, com autoria derivada de `auth.uid()`, temporalidade
auditável, exclusão com rastreabilidade, RLS fail-closed e autorização pelo Policy Engine,
**reutilizando** a infraestrutura das Etapas 4 e 5 (F5-06 a F5-10) sem duplicá-la.

O baseline funcional que precisa continuar existindo: tipo `POSITIVA | NEUTRA | NEGATIVA`, data,
texto, indicador de **comunicado**, autoria, histórico, edição, exclusão com rastreabilidade,
vínculo com colaborador e vínculo com ciclo.

## 2. Escopo / não escopo

**Escopo (F5-11):** observações de colaborador por ciclo, seu texto, tipo, comunicação ao
colaborador, edição, exclusão lógica com rastreabilidade, revogação de exclusão, leitura própria e
por relação, histórico append-only, autorização, RLS, Edge/RPC e cutover do `localStorage`.

**Não escopo:**

- **F5-10 (metas) e F5-09 (ciclos):** D1–D28 de ambos **não são reabertas**. `evaluation_goals`,
  `evaluation_goal_*`, `evaluation_cycle_goal_limits`, `evaluation_cycles`, `cycle_events` e as
  RPCs `meta_*`/`ciclo_*` são **apenas consumidos**.
- **F5-06/F5-07/F5-08:** avaliações, colaboradores/histórico organizacional e estrutura/catálogos
  são **apenas consumidos**.
- **"Observação de critério"** (`Feedback.observacaoGerente` / `observacaoCoordenador`) — **conceito
  diferente** (§3.10), já soberano em F5-06. Não entra na F5-11.
- **Importação do acervo legado** — ver §10 (**DECIDE D13: não migrar**).
- **Nota de avaliação** (F5-06): a observação **não** gera nota, **não** agrega e **não** entra em
  cálculo de `nota_media`.
- Relatórios/BI sobre observações, notificações, anexos, menções, comentários em observação.

## 3. Inventário auditado (base `5889dec`)

### 3.1 Modelo atual — `src/types/Observacao.ts` (47 linhas, lido integralmente)

| Campo | Linha | Observação |
|---|---|---|
| `TipoObservacao = "POSITIVA" \| "NEUTRA" \| "NEGATIVA"` | `:1-4` | domínio fechado de 3 valores |
| `AcaoHistoricoObservacao = "CRIACAO" \| "EDICAO" \| "EXCLUSAO"` | `:6-9` | 3 ações; **não há** comunicação nem revogação |
| `HistoricoObservacao { id, acao, data, autorMatricula, autorNome, textoAnterior?, tipoAnterior?, comunicadoAnterior?, anoAnterior?, cicloAnterior? }` | `:11-22` | before-image parcial por evento; `autorMatricula`/`autorNome` **do cliente** |
| `Observacao.id: string` | `:25` | **UUID fabricado no browser** (`crypto.randomUUID()`, `observacaoStorage.ts:111`) |
| `colaboradorMatricula: number` | `:26` | vínculo por **matrícula legada** (não `collaborators.id`) |
| `tipo`, `texto`, `comunicado` | `:27-29` | texto livre `trim()`; `comunicado` é **booleano simples** |
| `ano?: number`, `ciclo?: 1 \| 2 \| 3` | `:31-33` | **opcionais** "para manter compatibilidade com observações antigas": ciclo legado denormalizado |
| `autorMatricula: number`, `autorNome: string` | `:35-36` | **autoria declarada pelo cliente** |
| `dataCriacao`, `dataUltimaAtualizacao` | `:38-39` | relógio do browser |
| `excluida`, `dataExclusao?`, `excluidaPorMatricula?`, `excluidaPorNome?` | `:41-44` | exclusão lógica sem motivo |
| `historico: HistoricoObservacao[]` | `:46` | **histórico embutido no objeto mutável** |

### 3.2 Persistência

- **Único acervo:** `localStorage["feedback-control-observacoes"]` (`observacaoStorage.ts:12`).
- **Toda mutação regrava o array inteiro** (`:134`, `:161-190`, `:207-233`) — last-write-wins.
- **Fallback silencioso com perda de dado:** JSON corrompido ⇒ `catch { return [] }` (`:19-23`).
- **Segundo produtor da mesma chave:** `src/services/geradorDadosTeste.ts:14,354-389` (DEV-gated).
- **Reset DEV** remove a chave: `src/services/resetBaseDesenvolvimento.ts:19-25`.
- **Não existe** tabela, RPC, Edge, repositório, porta ou policy soberana de observação (§6.9).
- **Não há dual-write**: o acervo local **não tem contraparte remota**.
- **Guarda SQL ativa que PROÍBE observações** no schema:
  `supabase/validacao/15-validar-f5-09-p9.sql:2121-2173` (tabela/RPC/coluna `%observac%`) e
  `supabase/validacao/30-validar-f5-10-p7.sql:1401-1413` (tabela/função de observação ⇒ `[FAIL]`).
  **Substituir essas guardas invertidas é item declarado da P1** (§13).

### 3.3 Call graph real

```
/collaborator/:collaboratorId  (AppRoutes.tsx:171)
└─ ColaboradorDetalhePage.tsx                     [leitura SOBERANA do colaborador: F5-07]
   ├─ getObservacoesByColaborador(matricula, mostrarExcluidas)      (:880-886)  [localStorage]
   ├─ filtrarObservacoesPorCiclo(...) + contarObservacoesPorTipo(...) (:880-887)
   │     → KPIs "Positivas / Neutras / Negativas"                   (:1132-1168)  [SEM gate]
   └─ <ObservacoesColaborador colaborador={colaboradorLegado} ...>   (:1185-1193)
      ├─ useUsuarioAtual()  → Colaborador LEGADO (localStorage / impersonação DEV)
      ├─ getCicloAtivo() / getCiclosAvaliacao()                     (:79-84)   [localStorage]
      ├─ can(ctx,"observation.create", {kind:"observation",...})     (:145-151) [UX]
      ├─ can(ctx,"observation.edit",   {kind:"observation",...})     (:153-166) [UX]
      ├─ can(ctx,"observation.delete", {kind:"observation",...})     (:168-181) [UX]
      ├─ getObservacoesByColaborador(matricula, mostrarExcluidas)    (:122-128) [localStorage]
      │     └─ ordenarPorAnoECiclo(...)                              utils/ordenacaoPorCiclo.ts
      ├─ filtrarObservacoesPorCiclo(...)                             (:122-128)
      ├─ criarObservacao(...)                                        (:236-244)
      │     ├─ validarCicloAtivo(ano, ciclo) → getCiclosAvaliacao()  (:30-39,107) [ciclo LEGADO]
      │     ├─ authorize(ctx,"observation.create", ...)              (:231-235)  ← ÚNICO authorize
      │     ├─ crypto.randomUUID() + autor = usuarioAtual            (:111,118-119)
      │     └─ localStorage.setItem(KEY, JSON.stringify(all+1))      (:134)
      ├─ atualizarObservacao(id, tipo, texto, comunicado, ano, ciclo, usuarioAtual) (:221-229)
      │     ├─ NO authorize() — apenas can() na UI
      │     └─ localStorage.setItem(...)                             (:161-190)
      └─ excluirObservacao(id, usuarioAtual)                         (:268)
            ├─ NO authorize() — apenas can() na UI
            └─ localStorage.setItem(...)                             (:207-233)

MinhaAvaliacaoDetalhePage.tsx  (visão SELF do avaliado)
└─ getObservacoesComunicadasByCiclo(usuarioAtual.matricula, feedback.ano, feedback.ciclo)  (:8,279)
      └─ getObservacoesComunicadasByColaborador → getObservacoesByColaborador   [localStorage]

exportarAvaliacaoPdf.ts        (PDF da avaliação)
└─ getObservacoesComunicadasByCiclo(colaborador.matricula, feedback.ano, feedback.ciclo) (:5,97)

geradorDadosTeste.ts  (DEV)    → lê/grava "feedback-control-observacoes" direto  (:14,354-389)
resetBaseDesenvolvimento.ts (DEV) → localStorage.removeItem("feedback-control-observacoes") (:19-25)
confirmarCorrecaoPeriodoCiclo.ts:14 → só TEXTO de impacto (produtor do impacto NÃO existe mais)
```

**Rotas:** **não existe rota própria de observação.** O painel é embutido na página de detalhe do
colaborador (`/colaborador/:collaboratorId`). O formulário é aberto por estado local
(`abrirNovaObservacaoToken`/`mostrarObservacoes`).

### 3.4 Operações e fluxos reais

| Operação | Onde | Regras aplicadas hoje |
|---|---|---|
| criar | `ObservacoesColaborador.tsx:205-257` → `criarObservacao` | `can` (UX) + `authorize` (só aqui); `validarCicloAtivo` (ciclo legado `ATIVO`); `texto.trim()` não vazio na UI; autor = `usuarioAtual`; `comunicado` escolhido no formulário |
| editar | `:194-203`, `:219-229` → `atualizarObservacao` | **só `can` (UX)**; `validarCicloAtivo`; ciclo **imutável** (`:154-156`); before-image no histórico |
| marcar/desmarcar comunicado | mesmo formulário de criar/editar (checkbox `:408-417`) | **não há operação própria** e **não há capability própria**; é um campo entre `tipo`/`texto`; sem carimbo de quem/quando |
| excluir | `:259-271` → `excluirObservacao` | **só `can` (UX)**; `window.confirm`; `validarCicloAtivo`; lógica (`excluida = true`) + `dataExclusao` + `excluidaPor*`; **sem motivo**; **sem revogação** |
| listar/visualizar | `:122-128` (painel) e `ColaboradorDetalhePage:880-887` (KPIs) | **nenhum gate** — lê o `localStorage` direto |
| ver histórico | `:603-657` (acordeão `historico.length`) | renderiza `historico` do objeto local; mostra `textoAnterior` quando `EDICAO` |
| próprias comunicadas | `MinhaAvaliacaoDetalhePage:279`, `exportarAvaliacaoPdf:97` | filtro de dados `comunicado === true` do `(ano,ciclo)` do feedback; **nenhum gate** |

### 3.5 Autorização atual

- **Capabilities:** 4 canônicas — `observation.read`, `observation.create`, `observation.edit`,
  `observation.delete` (`Capability.ts:23-26`; `catalogoCapabilities.ts:34-37`); `observation.write`
  existe **deprecada** (DB `20260910000000_f5_04_catalog_reconciliation.sql:85-87`; espelho
  `catalogoCapabilities.ts:67-70`). Catálogo físico **31**; canônico **29**; `goal.%` 3;
  `observation.%` física 5 (4 canônicas + 1 deprecada) ⇒ `goal.% + observation.% = 8`, número
  verificado por vários validadores do CI.
- **Concessão hoje:** **nenhuma** role de sistema concede `observation.*` (bundle `admin` = 9
  funcionais, sem conteúdo confidencial — guarda `supabase/validacao/02-validar-f4-01.sql:563-578`).
  As 4 canônicas são `grantable_via_role = true`, logo **role customizada pode concedê-las**.
- **Mundo DEV (não produção):** `mundoFuncional.ts` deriva capabilities de posição estrutural —
  conjunto de gestão (`:29-51`) e de coordenação (`:54-67`) incluem as 4; escopos `SELF`,
  `DIRECT_REPORTS`, `DESCENDANTS`, `ORGANIZATION` (`:230-243`). `ASSIGNED` **nunca** se aplica a
  `observation.*` (`:245-255`). Origem temporária: `providers/temporary.ts:52-58`
  (`create/edit/delete` × `DESCENDANTS`). Origem D (Pilot, dev-only): `providers/pilot.ts:43-45`.
- **Policy do cliente** (`authorizationPolicy.ts:214-250`), alvo **sempre**
  `{type:"collaborator", id: String(matricula)}`:
  - `create` ⇒ `cycle.status === "ATIVO" && collaborator.status !== "DESLIGADO"`;
  - `edit` e `delete` ⇒ **apenas** `cycle.status === "ATIVO"`;
  - `read` ⇒ `dominioPermite(true)`.
  `autorMatricula`, `excluida` e `comunicado` **não são consultados**; `funcao` **nunca** é
  consultada. Editar/excluir observação **de outro autor** é **ALLOW** — testado em
  `authorizationPolicy.test.ts:508-518`. `LICENCA` permite criar; `DESLIGADO` nega
  (`:132-149`); matriz de ciclo `ATIVO|PLANEJADO|ENCERRADO|CANCELADO` × `create|edit|delete`
  em `:275-298`.
- **Enforcement:** o **único** `authorize()` de observação é o de `create`
  (`ObservacoesColaborador.tsx:231`); `edit`/`delete` dependem **só de `can()`**; a camada de
  persistência **não importa autorização alguma**. A dívida está registrada no próprio contrato:
  `docs/F4-09-desenho-tecnico.md:253-255` marca `observation.edit`/`delete` com `▸(add authorize)`;
  §7.3 do mesmo documento é a **matriz normativa de observações já existente** e
  `docs/F5-07-desenho-tecnico.md:1331-1338` (§20.4) registra a assimetria como dívida da F5-11.
- **`observation` é recurso NÃO soberano:** `TIPOS_RECURSO_NAO_SOBERANOS = ["observation"] as const`
  (`resourceContextReal.ts:38`) ⇒ `TARGET_NAO_SOBERANO` ⇒ `TARGET_INVALID` na fronteira
  (`contextoAutorizacao.ts:306-308`). `capabilityTarget.ts:33-36` aceita `observation.*` apenas
  contra alvos `observation | collaborator | cycle`.
- **Consequência fail-closed já existente (fato estático):** `ObservacoesColaborador` **não passa
  `collaborators`**, e `colaboradoresDoRecurso` devolve `[]` fora do gate DEV do Vite
  (`authorizationPolicy.ts:67-85`; `config/ambiente.ts:117-118`) ⇒ `resolverAtor` = `undefined` ⇒
  **toda mutação de observação é DENY em build não-DEV** (o botão "+ Nova observação" nem renderiza).
- **`observation.read` não tem call site de produção** — a leitura é totalmente **sem gate**.

### 3.6 Consumidores e acoplamentos

| Consumidor | Uso | Tipo |
|---|---|---|
| `src/components/ObservacoesColaborador.tsx` | CRUD completo + histórico | **cutover principal** |
| `src/pages/ColaboradorDetalhePage.tsx` | KPIs por tipo + painel embutido (§`1127-1209`) | cutover |
| `src/pages/MinhaAvaliacaoDetalhePage.tsx` | observações **comunicadas** do próprio ciclo | cutover |
| `src/services/exportarAvaliacaoPdf.ts` | observações **comunicadas** no PDF | cutover |
| `src/services/geradorDadosTeste.ts` | **2º produtor da chave** (DEV) | cutover/barreira |
| `src/services/resetBaseDesenvolvimento.ts` | apaga a chave (DEV) | manter (só remove) |
| `src/pages/confirmarCorrecaoPeriodoCiclo.ts` | **apenas texto** do impacto | sem produtor (ver abaixo) |
| `src/types/CicloAvaliacao.ts:27-32` | `ImpactoTemporalPeriodoCiclo.observacoes` | **resíduo morto** |
| `src/components/filtroObservacoesPorCiclo.ts` | filtro/ordenação/KPIs por `(ano, ciclo)` | reaproveitável na UI soberana |
| `src/utils/ordenacaoPorCiclo.ts` | ordenação genérica `(ano, ciclo, data, id)` | idem |
| `src/authorization/estruturaUiSeguranca.test.ts:391-409` | lista de exceção "legado leitura" | ajustar no cutover |

**Inconsistência factual já resolvida parcialmente:** `correcaoPeriodoCicloService.ts` e
`impactoCorrecaoPeriodoCiclo.ts` **não existem mais** — foram removidos no cutover de metas
(`git log --diff-filter=D` ⇒ commit `4868ca7`, F5-10 P6 / Issue #220). O produtor do impacto de
correção de período é hoje **soberano** (F5-09). Restam apenas o tipo
(`CicloAvaliacao.ts:27-32`), a função `persistirCorrecaoPeriodoCicloAtivoInterno`
(`cicloAvaliacaoStorage.ts:472`, só usada por teste) e o texto de confirmação
(`confirmarCorrecaoPeriodoCiclo.ts:14`). **A observação do §3.5 da F5-10 sobre "três chaves de
ciclo" está desatualizada para observações**: hoje a chave de ciclo da observação é apenas
`(ano, ciclo)` legado.

### 3.7 Uso atual dos elementos pedidos

| Elemento | Como é usado hoje |
|---|---|
| `localStorage` | chave única `feedback-control-observacoes`; array inteiro; 2 produtores (app + gerador DEV); 1 removedor (reset DEV) |
| matrícula / identidade do colaborador | `colaboradorMatricula: number` — **identidade do alvo e do autor** é matrícula numérica legada |
| autor | `autorMatricula` + `autorNome` **vindos do cliente** (`usuarioAtual`, escolhido por impersonação DEV); sem vínculo com `auth.uid()` |
| ano/ciclo | `ano` + `ciclo (1\|2\|3)` denormalizados, **opcionais**; validação contra o **ciclo legado** local (`validarCicloAtivo`) |
| status do colaborador | **só** na política de `create`: `!== "DESLIGADO"` (`LICENCA` permite) |
| comunicado | booleano no objeto; **sem** operação própria, **sem** capability, **sem** carimbo de quem/quando; filtro de dados para a visão SELF e o PDF |
| timestamps | `dataCriacao`/`dataUltimaAtualizacao`/`dataExclusao` — **relógio do browser** |
| exclusão/histórico | exclusão lógica (`excluida`) **sem motivo** e **sem revogação**; histórico **embutido** em array mutável com before-image parcial (`textoAnterior`, `tipoAnterior`, `comunicadoAnterior`, `anoAnterior`, `cicloAnterior`) |

### 3.8 Testes existentes

`observacaoStorage.test.ts` (cobertura de leitura/ordenação/exclusão/validação de ciclo),
`filtroObservacoesPorCiclo.test.ts`, `reaberturaCicloService.test.ts:110-159` ("preserva
observações"), `cancelamentoCicloService.test.ts:64-90` (idem), `authorizationPolicy.test.ts`
(matriz principal, `:102-121, 123-185, 247-298, 480-528`), `f4-09-functional.test.ts:186-199`
(`observation.read`: SELF sobre terceiro ⇒ DENY; gestor no alcance ⇒ ALLOW),
`catalogoCapabilities.test.ts:34-49,79-82`, `ciclosPolicyEngine.test.ts:167-174`,
`actorContext.test.ts:172-180`, `providers/f4-04-core.test.ts:194,202`,
`providers/f4-05-core.test.ts:270-288`, `providers/f4-07-core.test.ts:208-213`,
`resetBaseDesenvolvimento.test.ts:8`. **Nenhum** teste exercita caminho server-side/Edge de
observação — porque **não existe**.

### 3.9 O que **não existe** (declarado)

Tabela, RPC, Edge, porta, repositório, policy, RLS e trilha de observação · capability de
comunicação · carimbo de comunicação · motivo de exclusão · revogação de exclusão · versionamento
(`version`/`expectedVersion`) · idempotência (`operation_id`/`payload_hash`) · bridge
`(ano, numero)` ↔ `evaluation_cycles.id` **para observações** · adaptador
`src/infrastructure/supabase/observacoes/` · Edge `supabase/functions/observacoes/` ·
`03-validar-f5-11-cutover.sql` · decisão sobre concessão de `observation.*` a role de sistema ·
sincronização multi-aba/lock.

### 3.10 Fronteira de vocabulário — duas coisas chamadas "observação"

| Conceito | Tipos/arquivos | Domínio | Situação |
|---|---|---|---|
| **Observação** (o domínio da F5-11) | `src/types/Observacao.ts`, `observacaoStorage.ts`, `ObservacoesColaborador.tsx` | positivo/neutro/negativo, comunicado, ciclo | **legado local — objeto desta atividade** |
| **Observação de critério** | `Feedback.ts:47-54` (`observacaoGerente`, `observacaoGerenteAutor*`, `observacaoCoordenador`, `observacaoCoordenadorAutor*`), `cicloEquipeService.ts:91-102`, `geradorDadosTeste.ts:194-236` | texto por critério **dentro da avaliação** | **já soberano em F5-06 — FORA do escopo** |

Essa separação é **obrigatória** para o desenho: nenhuma busca por `observac` pode arrastar o
segundo conceito para a F5-11.

## 4. Mapas exigidos

| # | Item | Situação (evidência) |
|---|---|---|
| a | modelo | §3.1 — blob local; UUID do browser; matrícula como identidade do alvo e do autor; `(ano,ciclo)` opcional denormalizado; histórico embutido |
| b | lifecycle | §3.4 — criar/editar/excluir **somente** com ciclo legado `ATIVO`; ciclo imutável; comunicado é campo; **sem** revogação |
| c | regras | ciclo `ATIVO`; colaborador ≠ `DESLIGADO` (só no create); texto não vazio; ciclo imutável na edição; exclusão lógica |
| d | autorização | §3.5 — 4 capabilities sem concessão de sistema; alvo por **matrícula**; recurso **declarado não soberano**; `authorize()` só no create; leitura sem gate; editar/excluir de terceiro = ALLOW |
| e | legado | `localStorage` (blob), UUID de ciclo no browser, matrícula/nome, mundo sintético DEV, ciclo legado com `dataInicio/dataFim` |
| f | concorrência | last-write-wins do array; sem versão, lock ou idempotência; multi-aba sem sincronização; TOCTOU entre `can()` e a gravação |
| g | multiusuário | autoria não soberana (impersonação local); "excluída por" textual; sem noção de tenant |
| h | dual-read/write/fallback | **sem dual-write**; fallback silencioso (JSON corrompido ⇒ `[]`); fallback de mundo DEV no Policy Engine |
| i | contratos a reutilizar | §6 (padrões F4-02/F4-08/F5-06/F5-09/F5-10: `auth.uid()`, membership, UUID, trilha append-only, `expected_version`, idempotência, `payload_hash`, RLS policy-antes-do-grant / deny-by-default, Edge `index`/`core`/`contrato`, adapter fail-closed) |
| j | dívidas fora do escopo | §2 |

## 5. Problemas e resíduos do legado

1. **Construção, não troca de fonte:** não há backend de observação; o acervo local não tem
   contraparte remota.
2. **Autoria não soberana:** `autorMatricula`/`autorNome` vêm do cliente; em DEV o autor é o
   colaborador escolhido no seletor de impersonação (`UsuarioAtualContext.tsx:4-14`). Não há
   vínculo com `auth.uid()`, membership ou `collaborators.id`.
3. **Três identidades incompatíveis:** UUID local do browser, matrícula numérica e `(ano, ciclo)`
   legado — nenhuma é `collaborators.id` / `evaluation_cycles.id`, e **não há bridge**.
4. **Autoridade de ciclo no cliente:** `validarCicloAtivo` lê `getCiclosAvaliacao()`
   (`cicloAvaliacaoStorage.ts`), que **fabrica** ciclos no caminho de leitura; a gestão de ciclos já
   é soberana (F5-09 P8) ⇒ risco de divergência e de observação órfã.
5. **Autorização inoperante em produção:** `observation` é tipo de recurso **não soberano** e, fora
   do DEV, o ator não resolve ⇒ `can()` falso e `authorize()` lança para **toda** mutação; o domínio
   é efetivamente **inutilizável fora do DEV**.
6. **Enforcement ausente em `edit`/`delete`:** só `can()` (UX) guarda; nenhum `authorize()`. A
   persistência não valida nada — qualquer caminho de código pode gravar.
7. **Regra de autoria inexistente:** editar/excluir observação **de outro autor** é ALLOW explícito
   (`authorizationPolicy.test.ts:508-518`) — incompatível com "alteração de autoria" como ameaça.
8. **Leitura sem gate:** KPIs e painel listam o acervo local sem decisão alguma; a regra "SELF só vê
   comunicado" existe apenas como **filtro de dados**.
9. **Histórico não é trilha:** array embutido no objeto mutável; apagável/reescrevível; sem
   append-only, sem hash, sem `operation_id`, sem autor soberano.
10. **`comunicado` é um booleano anônimo:** sem operação, sem capability, sem carimbo de quem/quando
    — a disponibilização ao avaliado (ato com efeito de divulgação) não é auditável. O próprio
    catálogo F4-01 registrou a semântica como **futura**:
    `20260908000001_authorization_system_catalog.sql:59-60` ("Comunicado/terceiros regidos por
    conteúdo e escopo **futuros**").
11. **Fallback silencioso com perda:** JSON corrompido ⇒ `[]` sem aviso.
12. **Segundo produtor da chave** (`geradorDadosTeste.ts`) e **exclusão física trivial** (limpar o
    `localStorage` do navegador) — rastreabilidade zero.
13. **Sem tenant:** não existe `organization_id`; qualquer pessoa com acesso ao navegador vê e
    altera tudo.
14. **Concorrência:** array inteiro regravado; duas abas/duas pessoas se sobrescrevem; sem
    `expected_version`, sem lock, sem idempotência.
15. **Observações sem ciclo:** o tipo admite `ano?`/`ciclo?` ausentes (dados antigos), mas a criação
    **sempre** exige ambos e ciclo ativo — a leitura exibe "Sem ciclo" (`:504-507`).
16. **Guarda invertida no CI:** o schema é **proibido** de conter observação hoje
    (`15-validar-f5-09-p9.sql:2121-2173`, `30-validar-f5-10-p7.sql:1401-1413`) — precisa ser
    substituída, não apenas ignorada.
17. **Resíduo morto:** `ImpactoTemporalPeriodoCiclo.observacoes` e
    `persistirCorrecaoPeriodoCicloAtivoInterno` sobrevivem sem produtor de produção.

## 6. Arquitetura existente a reutilizar

> Nada abaixo é criado pela F5-11: tudo já existe e deve ser **consumido**.

### 6.1 Identidade, tenant e fronteira

- `auth.uid()` é a raiz soberana (`architecture-rules.md` §1.1).
- **`public.user_has_active_membership(p_organization_id uuid) returns boolean`** —
  `20260908100000_f4_08_helpers_function_grants.sql:26`; `sql/stable/SECURITY INVOKER/search_path=public`;
  única helper de fronteira de tenant (perfil ativo + membership ativa).
- `evaluation_ator_valido` (`20260911010000_f5_06_evaluation_functions.sql:66`) e
  `colaborador_ator_valido` (`20260913000000_f5_07_collaborators_sovereign.sql:367`): mesma prova,
  com o ator como parâmetro (nas RPCs `auth.uid()` já foi verificado na Edge).
- **Colaborador é UUID** (`collaborators.id`); a **matrícula** é
  `collaborator_identifiers.business_code` (texto, com vigência — `20260907103100:153`), nunca PK.
- `p_organization_id` é sempre explícito e **sempre revalidado**; cross-tenant ⇒ `NOT_FOUND`
  indistinguível.

### 6.2 Relações estruturais e avaliativas

- `resolver_collaborador_vinculado(user_profile, org) returns table(collaborator_id)` —
  `20260908010000:263` (endurecido em `20260909000000:22`) ⇒ **raiz do SELF**.
- `resolver_alvos_escopo(user_profile, org, scope, unit, data) returns table(collaborator_id, position_id)`
  — `20260908010000:337`; implementa os 6 escopos.
- F3-07: `organizacao_resolver_gestor_direto`, `..._subordinados_diretos`, `..._descendentes`,
  `..._cadeia`, `..._escopo_posicoes`, `..._escopo_unidades`
  (`20260907170000:96,138,181,239,292,358`).
- F3-09 (avaliativos): `organizacao_resolver_avaliador_avaliado` (`20260907190000:113`).
- **Relação CONGELADA (o modelo mais próximo do que a F5-11 precisa):**
  `f5_10_aprovador_congelado(p_goal_id, p_organization_id, p_papel)` —
  `20260924000000_f5_10_p3_approvals_rpc.sql:273`: lê **somente** `evaluations` +
  `evaluation_participants`; `GERENTE` = ocorrência **original** de `GESTAO_CADEIA`; `COORDENADOR` =
  ocorrência **original** de `GESTAO_DIRETA` (quando distinta); exige vigência; ausência/duplicidade
  ⇒ `NULL` (fail-closed).
- `evaluation_participants` (`20260911000000:271`): `role_type ∈ GESTAO_CADEIA | GESTAO_DIRETA |
  COLEGIADO`, com `valid_from`/`valid_to`.

### 6.3 Autorização — helpers e padrão de gate

- **Não existe** `authorize`/`tem_capability`/`f5_*_autorizar` genérico. O padrão é **um guard por
  domínio com allowlist FECHADA de capabilities**: `ciclo_ator_valido(uuid,uuid,text)`
  (`20260915000000:342`), `f5_10_ator_valido_meta(uuid,uuid,text)` (`20260925000000:168`),
  **`f5_10_exigir_autorizacao_meta(operacao, ator, org, goal, colaborador)`** (`:275`, `void`, raise),
  `f5_10_vinculo_meta_do_ator(uuid,uuid)` (`:210`).
- Mapa **fechado** `operação → capability` dentro do guard; operação desconhecida ⇒ **raise**
  (`fail-closed`); a capability **nunca** vem do chamador.
- `resolver_capabilities_efetivas` (`20260908000000:416`, `SECURITY DEFINER`, só `service_role`) e
  `resolver_capabilities_escopos_efetivas` (`20260908010000:287`).
- Erros: `F5_07_/F5_09_/F5_10_` × `INVALID_INPUT | NOT_FOUND | CONFLICT | FORBIDDEN`
  (`<PREFIXO>_<CLASSE>: <mensagem>`, sqlstate `P0001`).
- Client-side: `criarProvidersReais` (`providers/reais.ts:221`) + `alvoMetaCorresponde`/
  `metaNoEscopoDoAtor` (`:151-215`) = **molde exato** para o alvo soberano de observação.

### 6.4 RLS

- Padrão own-tenant: `create policy <t>_select_same_tenant ... using
  (public.user_has_active_membership(organization_id))` **antes** do `grant select` (F4-08 D21).
- **Deny-by-default integral (D22-A) existe e está aplicado:**
  `20260927000000_f5_10_p5_d22a_hardening.sql:54-58` — as 4 tabelas de metas ficam com **ZERO
  policy** e **ZERO privilégio de cliente**; a leitura passa **exclusivamente** por RPC com gate.
  Policies de `public`: 25 → 23.
- `service_role` **executa, nunca decide**; `DELETE`/`TRUNCATE` sempre revogados.

### 6.5 Trilha append-only

- Molde mais completo: **`cycle_events`** (`20260915000000:186-243`) —
  `organization_id`, `<entidade>_id`, `entity_type`, `event_type`, `effective_date`, `reason`,
  `before_value jsonb`, `after_value jsonb`, `payload_hash` (`~'^[0-9a-f]{64}$'`), `result_entity_id`,
  `actor_user_profile_id`, `actor_membership_id`, `operation_id`, `created_at`; FK **composta** de
  tenant; `unique (organization_id, operation_id)`.
- **Imutabilidade em duas camadas:** ACL (`revoke all` de todos + `grant select, insert` só
  `service_role` + `revoke update, delete, truncate`) **e** triggers `BEFORE UPDATE`/`DELETE`/
  `TRUNCATE` que fazem `raise exception` (resistem a drift de privilégio; `20260922000000:505-531`).
- `payload_hash` = SHA-256 hex **derivado server-side** da intenção canônica
  (`20260925000000:469-478`); idempotência **dupla** (caminho rápido + sob o lock).
- **`f5_10_derivar_operation_id(p_base uuid, p_sufixo text) returns uuid`** (`20260924000000:240-258`,
  `immutable`) — para sub-eventos da **mesma** intenção (a unicidade `(org, operation_id)` impede
  reuso).

### 6.6 Versão, lock e idempotência

- `expected_version integer` obrigatório em toda mutação; comparado **depois** do lock e do
  `SELECT ... FOR UPDATE`; divergência ⇒ `<PREFIXO>_CONFLICT`; `version = version + 1` por mutação.
- Famílias de advisory lock (chave única por família, doutrina em
  `20260914020000_f5_08_lock_key_alignment.sql`): **`evaluation_cycles:<org>`** (ciclos **e** metas,
  via `ciclo_lock_organizacao`, `20260915000000:395-412`), `f5_07_estrutura:<org>`,
  `position_reporting_lines:<org>`. **Proibido** criar chave independente para a mesma família.
- Ordenação normativa das RPCs: forma → hash → ator → gate → membership → idempotência rápida →
  **lock** → idempotência sob lock → alvo por `(id, tenant)` → `FOR UPDATE` → **`expected_version`**
  → precondições de estado → mutação `version+1` → **evento na MESMA transação** → `jsonb`.

### 6.7 Edge, contrato e cliente

- Fluxo obrigatório: `frontend → functions.invoke("<edge>") → Edge (método → JWT/auth.getUser →
  forma com allowlist estrita → tenant revalidado → gate por operação → service_role) → RPC`.
  **Proibido** `.rpc(` no browser e **proibida** `SERVICE_ROLE_KEY` no cliente (guardas em
  `src/authorization/estruturaUiSeguranca.test.ts:527-538`).
- Trio por Edge: `index.ts` (Deno.serve) + `core.ts` (testável, `resolveCaller` injetado) +
  `contrato.ts`. Edge Functions existentes (8): `avaliacoes`, `ciclos`, `colaboradores`,
  `contexto-autorizacao`, `convidar-usuario`, `gerenciar-access-role`, `gerenciar-usuario`, `metas`.
- Contrato transportável único compartilhado Edge↔cliente (molde `metas/contrato.ts` +
  `src/infrastructure/supabase/metas/`): `CodigoPublico`, `OperacaoX`, `DEFINICAO_POR_OPERACAO`
  (gate funcional/administrativo + capability), `RPC_POR_OPERACAO`, `CHAVES_POR_OPERACAO`
  (allowlist estrita ⇒ forma nunca é autoridade).
- **`corpoDeErroEdge`** (`src/infrastructure/supabase/errosEdge.ts:60`, F5-10 P5.1 / Issue #221):
  `async`, aceita `Response` real ou objeto decodificado, **nunca lança**, fail-closed (`null`).
- Adapter fail-closed: `CODIGOS`, `codigoPublico(valor)` (desconhecido ⇒ `FORBIDDEN`), `invocar()`
  tratando `error` / `data.error` / `data.ok !== true` ⇒ `INTERNAL`.

### 6.8 Validação

- Par `<NN>-cenario-<fase>.sql` (fixture, **insert-once**, prefixo de UUID fixo por fase) +
  `<NN>-validar-<fase>.sql` (`raise notice '[PASS] …'`; `[FAIL]` + `ON_ERROR_STOP=1` aborta).
- Numeração **global 01..33**; **o 27 não existe (gap)**; **o próximo número livre é 34**.
- Concorrência real entre duas sessões: dois arquivos `psql` (A em background, B em foreground) +
  um consolidador (molde 31/32/33 da F5-10 P7).
- CI: `.github/workflows/ci.yml`, job `supabase-local` (`db start` → `db reset --local` → `docker
  exec … psql -v ON_ERROR_STOP=1 < <arquivo>`), com as **fases correntes antes das regressões**
  F5-06/F5-07; job `quality` = `npm test`, `npm run build`, `npm run lint`, `git diff --check`.
- Migrations: última é `20260928000000_f5_10_p5_2_leitura_soberana_metas.sql`; a P1 da F5-11
  nasceria em `20260929000000_*` e precisa ser registrada em `supabase/migrations/README.md`.
- Ciclo soberano: `evaluation_cycles` com `ano`, `numero (1..3)`, `status ∈ PLANEJADO|ATIVO|
  ENCERRADO|CANCELADO`, `data_inicio`/`data_fim` (**data_fim inclusiva**),
  `unique (organization_id, ano, numero)`, `uq (id, organization_id)`; bridge
  `evaluation_resolver_ciclo(org, ano, numero, actor)` (`20260911020000:33`) — **já existe** e é
  reutilizável para qualquer leitura por `(ano, numero)`.

### 6.9 O que **não** será reutilizado / está proibido reabrir

- `cicloAvaliacaoStorage` (ciclo legado local) como autoridade — **somente** leitura transitória
  enquanto durar o cutover.
- `TIPOS_RECURSO_NAO_SOBERANOS` para observação — **precisa sair** (é o ponto exato do cutover de
  autorização).
- D1–D28 da F5-09 e D1–D25 da F5-10 — **não reabrir**.
- Padrão "blob no `localStorage`", "estado autorizativo no objeto do cliente", "idempotência por
  early-return" (antipadrões já nomeados na F5-10 §5.4).

---

# CONTRATO NORMATIVO (fechado em §15 — D1–D16)

## 7. Modelo soberano (normativo)

### 7.1 Identidade (DECIDE — D1, D2, D3)

A identidade canônica **é** `evaluation_observations.id` (uuid, PK), atribuída pelo banco.
`matricula`, `autorNome`, `(ano, numero)` e o UUID do browser são **rótulos de projeção** — nunca
identidade, chave de leitura ou autorização. Vínculos por UUID: `organization_id` (tenant da linha),
`collaborator_id` (`collaborators.id`), `cycle_id` (`evaluation_cycles.id`, **obrigatório e
soberano** — D2) e autoria por `author_user_profile_id`/`author_membership_id` (padrão do ator
verificado) mais `author_collaborator_id` derivado do vínculo (nulo quando o ator não tem vínculo de
colaborador).

**DECIDE (D3):** a autoria é **exclusivamente derivada** do contexto autenticado/soberano. **Nenhum**
`author_user_profile_id`, `author_membership_id`, membership, matrícula, nome ou equivalente
fornecido pelo cliente é autoridade — e esses campos **não existem** no contrato transportável de
mutação (§8.4). Os campos de autoria são **gravados pelo servidor** a partir de `auth.uid()`
verificado na fronteira, e `author_collaborator_id` depende de **vínculo único de colaborador ativo**
na organização (ausência ⇒ **DENY**, fail-closed).

### 7.2 Tabelas (DECIDE — D1, D2, D3, D6, D7, D8, D16 — contrato da P1)

```sql
-- Contrato NORMATIVO das duas tabelas da P1. A P1 materializa exatamente esta
-- forma e o validador da P1 prova cada constraint (D1/D2/D3/D6/D7/D8/D16).
create table public.evaluation_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  collaborator_id uuid not null,                 -- alvo (collaborators.id) — D2
  cycle_id uuid not null,                        -- evaluation_cycles.id, OBRIGATÓRIO — D2
  tipo text not null check (tipo in ('POSITIVA','NEUTRA','NEGATIVA')),
  texto text not null check (texto = btrim(texto) and char_length(texto) between 1 and 2000),  -- D16
  comunicado boolean not null default false,     -- D7
  comunicado_em timestamptz,
  comunicado_por_user_profile_id uuid,
  comunicado_por_membership_id uuid,
  excluida boolean not null default false,       -- D8: exclusão SEMPRE lógica
  excluida_em timestamptz,
  excluida_por_user_profile_id uuid,
  excluida_por_membership_id uuid,
  motivo_exclusao text,
  author_user_profile_id uuid not null,          -- D3: derivado de auth.uid(), nunca do cliente
  author_membership_id uuid not null,            -- D3: derivado, nunca do cliente
  author_collaborator_id uuid,                   -- D3: derivado do vínculo (nulo se ADMIN sem vínculo)
  version integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_evaluation_observations_id_organization unique (id, organization_id),
  constraint fk_evaluation_observations_collaborator  foreign key (collaborator_id, organization_id)
    references public.collaborators (id, organization_id) on delete restrict,
  constraint fk_evaluation_observations_cycle         foreign key (cycle_id, organization_id)
    references public.evaluation_cycles (id, organization_id) on delete restrict,
  constraint fk_evaluation_observations_author_membership foreign key (author_membership_id, organization_id)
    references public.user_organization_memberships (id, organization_id) on delete restrict,
  -- D7: comunicado é FATO — nunca booleano anônimo; carimbo obrigatório e coerente.
  constraint ck_evaluation_observations_comunicado check (
    (comunicado and comunicado_em is not null
       and comunicado_por_user_profile_id is not null and comunicado_por_membership_id is not null)
    or (not comunicado and comunicado_em is null
       and comunicado_por_user_profile_id is null and comunicado_por_membership_id is null)),
  -- D8/D16: exclusão lógica sempre com ator, instante e MOTIVO; sem motivo não há exclusão.
  constraint ck_evaluation_observations_exclusao check (
    (excluida and excluida_em is not null and excluida_por_user_profile_id is not null
       and excluida_por_membership_id is not null
       and motivo_exclusao is not null and motivo_exclusao = btrim(motivo_exclusao)
       and char_length(motivo_exclusao) between 1 and 2000)
    or (not excluida and excluida_em is null and excluida_por_user_profile_id is null
       and excluida_por_membership_id is null and motivo_exclusao is null))
);
create index ix_evaluation_observations_alvo
  on public.evaluation_observations (organization_id, collaborator_id, cycle_id) where not excluida;

-- Trilha append-only (molde cycle_events / evaluation_goal_events) — D6.
create table public.evaluation_observation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  observation_id uuid not null,
  entity_type text not null check (entity_type = 'evaluation_observation'),
  -- D6/D7/D8: conjunto FECHADO de eventos; nenhum evento fora desta lista.
  event_type text not null check (event_type in
    ('CRIADA','EDITADA','COMUNICADO','COMUNICACAO_REMOVIDA','EXCLUIDA','REVOGADA')),
  effective_date timestamptz not null,
  reason text,
  before_value jsonb, after_value jsonb,         -- D6: before/after image por evento
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  result_entity_id uuid,
  actor_user_profile_id uuid not null,           -- autoria soberana do EVENTO
  actor_membership_id uuid not null,
  operation_id uuid not null,
  created_at timestamptz not null default now(),
  constraint uq_evaluation_observation_events_org_operation unique (organization_id, operation_id),
  -- D8/D16: motivo OBRIGATÓRIO em EXCLUIDA e REVOGADA.
  constraint ck_evaluation_observation_events_reason check (
    event_type not in ('EXCLUIDA','REVOGADA')
    or (reason is not null and reason = btrim(reason)
        and char_length(reason) between 1 and 2000))
);
```

**Sem tabela de histórico separada além da trilha** (D6): o "histórico" que a UI mostra **é** a
leitura da trilha append-only. **Sem colunas de meta/avaliação dobradas** na linha da observação: a
observação **não** altera `nota_media`, não gera `evaluation_scores` e não influencia
`evaluation_aggregates` (§2).

### 7.3 Semântica das colunas (DECIDE — D3, D4, D7, D8, D10, D16)

| Coluna | Semântica |
|---|---|
| `tipo` | domínio fechado de 3 valores; **mutável pela edição** (D4 — o legado troca o tipo e registra `tipoAnterior`; o contrato preserva isso) |
| `texto` | conteúdo da observação; `btrim`, **1..2000 caracteres** (D16) |
| `cycle_id` | ciclo **da criação**; **imutável** após a criação (D2/D4; paridade com `observacaoStorage.ts:154-156`) |
| `comunicado` + `comunicado_em` + `comunicado_por_*` | fato auditável da disponibilização ao avaliado (D7) |
| `excluida` + `excluida_em` + `excluida_por_*` + `motivo_exclusao` | exclusão **lógica** com rastreabilidade; motivo **obrigatório** (D8/D16); nunca física |
| `author_*` | autoria **derivada** de `auth.uid()` na fronteira; **imutável** — nunca transferível e nunca aceita do cliente (D3/D4) |
| `version` | concorrência otimista; `version + 1` em toda mutação efetiva (D10) |
| `created_at`/`updated_at` | relógio **do servidor** (`public.set_updated_at()`) |

### 7.4 Ciclo e estados (DECIDE — D2, D12)

- `cycle_id` **obrigatório e soberano** (D2): a criação legada sempre exige `(ano, ciclo)` com ciclo
  `ATIVO`. O modelo legado de observação **sem ciclo NÃO é preservado** — o "sem ciclo" do tipo atual
  só existia para dados antigos, que **não serão migrados** (§10, D13).
- **Mutação** (criar/editar/comunicar/descomunicar/excluir/revogar) somente com ciclo **`ATIVO`**,
  lido da **linha soberana** (D12) — paridade com `validarCicloAtivo`
  (`observacaoStorage.ts:30-39`) e com o domínio de metas (F5-10 §10).
- **Leitura histórica** permanece disponível nos demais estados (`PLANEJADO`, `ENCERRADO`,
  `CANCELADO`) conforme autorização (D12).
- A observação **não** muda de ciclo: corrigir o período do ciclo **não** altera a observação.

### 7.5 Edição (DECIDE — D4, D5, D10)

- A edição recebe a **definição completa** dos campos mutáveis (`tipo`, `texto`, `comunicado`) e
  **não** faz merge parcial (padrão `goal.editar`, F5-10 §13).
- **DECIDE (D4):** `collaborator_id`, `cycle_id` e autoria são **imutáveis após a criação**; o
  contrato de forma **nem aceita** esses campos nas operações de mutação existente — enviá-los ⇒
  `INVALID_INPUT`.
- **DECIDE (D5):** somente o **autor soberano** (`author_user_profile_id = ator`) pode editar, sempre
  **cumulativamente** com os demais gates (capability, relação, organização, estado do colaborador e
  estado do ciclo). Não existe edição de observação de terceiro.
- `expected_version` **obrigatório**; divergência ⇒ `CONFLICT` (D10).
- Cada edição efetiva grava evento append-only com **before-image** dos campos alterados (D6) para
  preservar o "Texto anterior" que a UI mostra hoje (`ObservacoesColaborador.tsx:641-653`).

### 7.6 Exclusão e revogação (DECIDE — D5, D8, D12, D16)

- **Exclusão é sempre lógica** (`excluida = true` + ator + instante + `motivo_exclusao`
  **obrigatório** — D8/D16). **Exclusão física é proibida** (ACL sem `DELETE`/`TRUNCATE` + triggers de
  imutabilidade).
- **Revogação** (desfazer a exclusão lógica) é operação **distinta**, permitida **somente pelo autor
  soberano** (D5) e **somente com ciclo `ATIVO`** (D12), com evento `REVOGADA` e motivo obrigatório
  (D8/D16). A trilha preserva `EXCLUIDA` **e** `REVOGADA` — a exclusão nunca é apagada do histórico.
- Observação excluída: leitura **histórica** permanece (para quem já podia ler), mutação e
  comunicação **negadas**.

### 7.7 Comunicado (DECIDE — D5, D7)

`comunicado` deixa de ser booleano anônimo e **é** **fato auditável**: `comunicado = true` exige
`comunicado_em` + `comunicado_por_user_profile_id` + `comunicado_por_membership_id` (CHECK), e cada
transição grava evento próprio (`COMUNICADO` / `COMUNICACAO_REMOVIDA`) com **ator e instante**
(D7). É **ato de disponibilização ao avaliado**: habilita a leitura por SELF (§8). O gate é
**`observation.edit`** sobre o recurso, **exclusivamente pelo autor soberano** (D5) — **nenhuma
capability nova é criada apenas para isso** (D7), e a semântica é a que o catálogo F4-01 declarou
como futura.

### 7.8 Temporalidade e histórico (DECIDE — D6)

- **Toda** mudança relevante **é** um evento append-only com `effective_date`, `actor_*`,
  `operation_id`, `payload_hash` e before/after (D6) — a trilha é a **única** fonte do histórico.
- **DECIDE (D6):** a trilha é **imutável**: **não** é permitido reescrever nem excluir fisicamente
  nenhum evento. Imutabilidade em **duas camadas** (ACL sem `UPDATE`/`DELETE`/`TRUNCATE` **e**
  triggers `BEFORE UPDATE`/`DELETE`/`TRUNCATE` que abortam), como
  `cycle_events`/`evaluation_goal_events`.
- Timestamps de negócio (`comunicado_em`, `excluida_em`) vêm do **servidor**.
- Períodos usam a convenção do projeto `[valid_from, valid_to)`; a exceção já documentada do domínio
  de ciclo (`data_fim` inclusiva) **não** se aplica aqui (a observação não tem período próprio).

### 7.9 Comportamento por estado (DECIDE — D11, D12 — consolidado em §8)

- **Colaborador `active`** (`ATIVO`): comportamento normal, conforme a relação.
- **Colaborador `leave`** (`LICENCA`): **criação permitida** (D11; paridade explícita com
  `authorizationPolicy.test.ts:132-149`), assim como editar, comunicar e excluir.
- **Colaborador `inactive`** (`DESLIGADO`): **nova criação proibida**, comunicação e edição
  proibidas; **leitura histórica e exclusão permanecem** conforme autorização (D11).
- **Ciclo `PLANEJADO`**: nega mutação (não é o "ciclo ativo" legado), permite leitura.
- **Ciclo `ATIVO`**: permite tudo conforme relação + autoria (D12).
- **Ciclo `ENCERRADO`/`CANCELADO`**: nega mutação, permite **leitura histórica** (D12).
- **Observação excluída**: nega mutação e comunicação; permite leitura histórica.
- **Status do colaborador não resolvido / vínculo do ator ausente / relação não resolvida**:
  **DENY** (fail-closed).

## 8. Autorização — matriz NORMATIVA (DECIDE — D3, D4, D5, D7, D8, D10, D11, D12, D15)

**Capabilities (nenhuma nova — paridade com a F5-10 D6):** `observation.read`, `observation.create`,
`observation.edit`, `observation.delete`. O catálogo permanece com **31** códigos físicos e
`goal.% + observation.% = 8`. `observation.write` permanece **deprecada** e não é usada.
**Não há** capability de comunicação: marcar/desmarcar comunicado é `observation.edit` sobre o
recurso (D7).

| # | Operação | Capability | Gate | Relação / escopo | Estado do colaborador | Estado do ciclo | Autoria |
|---|---|---|---|---|---|---|---|
| 1 | **listar** observações de terceiros (painel/acompanhamento) | `observation.read` | **administrativo** (leitura sem alvo único autorizável; molde F5-10 §11 / `goal.listar_por_escopo`) + filtro por relação | interseção: escopos do ator (`DIRECT_REPORTS`/`DESCENDANTS`) ∩ relação congelada | qualquer | qualquer | irrelevante |
| 2 | **listar** as próprias comunicadas (MinhaAvaliação / PDF) | `observation.read` | **funcional**, alvo `{observation \| collaborator}` | **SELF** com `comunicado = true` e `not excluida` | qualquer | qualquer | de terceiro |
| 3 | **visualizar** uma observação | `observation.read` | funcional | SELF-comunicada **ou** relação (autor, `DIRECT_REPORTS`, `DESCENDANTS`) | qualquer | qualquer | — |
| 4 | **criar** | `observation.create` | funcional | `DIRECT_REPORTS` / `DESCENDANTS` (relação do ciclo); **SELF = DENY** | ≠ `inactive` (D11) | `ATIVO` (D12) | autor = ator (D3) |
| 5 | **editar** | `observation.edit` | funcional | relação **e** `author_user_profile_id = ator` (**D5**) | qualquer | `ATIVO` | **autor** |
| 6 | **marcar comunicado** | `observation.edit` | funcional | relação **e** autor (**D5/D7**) | ≠ `inactive` | `ATIVO` | **autor** |
| 7 | **desmarcar comunicado** | `observation.edit` | funcional | relação **e** autor (**D5/D7**) | qualquer | `ATIVO` | **autor** |
| 8 | **excluir** (lógica, com motivo) | `observation.delete` | funcional | relação **e** autor (**D5/D8**) | qualquer | `ATIVO` | **autor** |
| 9 | **revogar exclusão** | `observation.edit` | funcional | relação **e** autor (**D5/D8**) | qualquer | `ATIVO` | **autor** |
| 10 | **consultar histórico** | `observation.read` | funcional | **mesma** regra de (3) — a trilha não amplia alcance | qualquer | qualquer | — |

**Invariantes fail-closed (NORMATIVOS):**

1. `organization_id`, `collaborator_id`, `cycle_id`, autoria, `comunicado`, `excluida`, `version` e
   `capability` **nunca** são confiados ao cliente: tenant é revalidado contra a membership ativa;
   o estado vem da **linha soberana**; a capability vem de mapa **fechado** operação → capability.
2. Capability **sem** relação ⇒ DENY. Relação **sem** capability ⇒ DENY. Operação desconhecida ⇒
   raise. Alvo de outro tenant ⇒ `NOT_FOUND` indistinguível (sem oráculo de tenant).
3. **`observation.read` não implica leitura de terceiro**: a leitura de terceiros passa por
   gate/RPC com relação (espelha a F5-10 D22 — `SELECT` de tenant **não** é autorização funcional).
4. **`observation.create/edit/delete` são exclusivos de gestão**: `SELF` **não** cria observação
   sobre si (F4-09 §7.3: "avaliado: DENY") e o próprio avaliado **só lê** o que está comunicado.
5. Editar/excluir **nunca** altera autor, colaborador, ciclo nem a trilha anterior.
6. Ausência de evidência (vínculo do ator, avaliação/participantes do ciclo, status do colaborador)
   ⇒ **DENY**, nunca "permite por default".
7. **Nenhuma** autorização pode depender de `localWorld`/DEV no caminho funcional; o teste de ALLOW
   deve exercitar o caminho de **produção**.

**Concessão (DECIDE — D15):** hoje **nenhuma** role de sistema concede `observation.*`, e o bundle
`admin` é **proibido por guarda** de conter capability de leitura de conteúdo
(`02-validar-f4-01.sql:563-578`). **Sem concessão explícita o domínio nasce DENY em produção**
(análogo ao risco R2 da F5-10), portanto:

1. `observation.*` **recebe concessão explícita** em **bundle/perfil de gestão adequado, distinto de
   `admin`**, usando o mecanismo já existente (`access_roles` + `access_role_capabilities` +
   `access_role_assignment_scopes`, F4-04/F5-04).
2. **`admin` permanece sem `observation.*`** — a guarda existente é preservada e **não** pode ser
   alterada para acomodar a F5-11.
3. **Obrigação normativa de identificação prévia:** **antes do início da P3**, este documento deve
   ser atualizado com a **tabela `capability → bundle/perfil existente → escopo`**, identificando
   **exatamente qual bundle existente** recebe cada capability. Essa tabela é **artefato de entrega
   da P3** e sua ausência **bloqueia** o início da P3.
4. **É proibido inventar um novo papel/bundle silenciosamente.** Se nenhum bundle/perfil existente
   for adequado, a criação de um novo é **decisão explícita** (registrada como nova decisão neste
   documento); a investigação deve **declarar por escrito** que os existentes foram avaliados e por
   que não servem.
5. A concessão é **testável no caminho de produção** (nunca via `localWorld`/DEV): o teste de ALLOW
   da P3 deve exercitar a capability efetiva concedida pelo mecanismo real.

> **Fato verificado no repositório — CORRIGIDO na execução da P1 (verificação no banco após
> `db reset`, base `6d527cc`):** o estado real tem **TRÊS** roles de sistema, e não uma:
> `admin` (`20260908000001_authorization_system_catalog.sql:69`), **`metas_dono`** e
> **`metas_aprovador`** — estas duas criadas pela **própria migration da F5-10 P4**
> (`20260925000000_f5_10_p4_authorization_rls.sql:2314-2332`, de forma aditiva e idempotente) como o
> **mecanismo de concessão explícita** do D7 da F5-10. Elas **não** são fixture de validação: são
> perfis de produto que **persistem** após `db reset` (a versão anterior desta nota estava
> **incorreta**). Consequências para a P3, sem alterar a decisão D15:
>
> 1. existe **precedente normativo** para o mecanismo de concessão por **perfil de sistema por
>    domínio** (foi assim que a F5-10 concedeu `goal.*`), e `metas_dono`/`metas_aprovador` são
>    perfis de **metas**, não de observações — **não** servem para `observation.*`;
> 2. `admin` continua **proibido** de receber `observation.*` (guarda `02-validar-f4-01.sql:563-578`);
> 3. logo **não há hoje perfil existente adequado** para receber `observation.*`, e a investigação
>    exigida pelo item 3 permanece **obrigatória** e **bloqueante** para a P3 — com a diferença de
>    que agora o candidato natural (perfil de sistema por domínio) já tem precedente explícito no
>    repositório e deve ser **decidido e nomeado**, nunca criado em silêncio.
>
> **D15 — DECISÃO FECHADA (orquestrador, 2026-09-16; registrada ANTES do código funcional da P3,
> como o item 3 exige).** O domínio passa a ser **decidível em produção** por um **perfil de sistema
> funcional dedicado**, criado por migration como os perfis de domínio da F5-10 P4 — e **não** por
> concessão ao `admin`:
>
> | capability | bundle/perfil (perfil de sistema, `organization_id` nulo) | scope (na assignment) |
> |---|---|---|
> | `observation.read` | **`observacoes_gestor`** | `DIRECT_REPORTS` / `DESCENDANTS` |
> | `observation.create` | **`observacoes_gestor`** | `DIRECT_REPORTS` / `DESCENDANTS` |
> | `observation.edit` | **`observacoes_gestor`** | `DIRECT_REPORTS` / `DESCENDANTS` |
> | `observation.delete` | **`observacoes_gestor`** | `DIRECT_REPORTS` / `DESCENDANTS` |
>
> **Normas da decisão:** (a) `admin` continua com **ZERO** `observation.*`; (b) `metas_dono` e
> `metas_aprovador` permanecem **exclusivos de metas**; (c) `observation.write` permanece
> **deprecada e não-concedível**; (d) **SELF não pertence ao bundle padrão** — a leitura
> SELF-comunicada segue a **regra específica do domínio** (§8 linha 2 / D7), sem exigir scope de
> gestão; (e) **ORGANIZATION não pertence ao bundle padrão** e não satisfaz o enforcement;
> (f) **custom roles continuam possíveis** pelo mecanismo soberano existente
> (`conceder_acesso_role` + `access_role_assignment_scopes`); (g) **o scope participa do enforcement
> REAL**, cumulativamente com a capability e com a relação estrutural — não é metadado declarativo;
> (h) **nenhuma autorização deriva de cargo ou nome textual**.
>
> **Fundamento (investigação documental, §21.1):** após `db reset` existem exatamente 3 roles de
> sistema — `admin` (9 capabilities, nenhuma de conteúdo), `metas_dono` (`goal.read`+`goal.write`) e
> `metas_aprovador` (`goal.read`+`goal.approve`) — e **zero** assignments/scopes semeados (toda
> concessão é runtime pelo caminho soberano). **Nenhum perfil existente é adequado:** `admin` é
> proibido pela guarda dura `02-validar-f4-01.sql:562-578` (que nomeia as 4 `observation.*`) e pelo
> item 2 acima; `metas_*` têm conjuntos **exatos** provados por guarda fail-closed
> (`20260925000000:2355-2396`) e `metas_dono` é o perfil do **avaliado** (conceder-lhe
> `observation.*` inverteria o invariante 4 do §8); F4-01 D14 proíbe roles de "manager"/
> "collaborator" por cargo. As 4 capabilities canônicas são `grantable_via_role = true` e
> `deprecated = false` (F5-04 D14), e o plano administrativo/controle (`membership.manage`,
> `access_role.manage`, `exceptional_access.grant`, `pilot_full_access.grant`) permanece **fora** do
> concedível por role — logo a concessão de `observation.*` é, por contrato, uma **role funcional**.

## 9. Segurança — ameaças e controles (NORMATIVO — DECIDE D3–D16)

| # | Ameaça | Vetor no legado | Controle NORMATIVO |
|---|---|---|---|
| T1 | **Cross-tenant** | não há tenant; qualquer navegador vê tudo | `organization_id` derivado/revalidado server-side (`user_has_active_membership`); FK composta de tenant; `NOT_FOUND` indistinguível |
| T2 | **IDOR** | `id` é UUID do browser; nenhuma verificação de escopo na leitura | alvo resolvido por `(id, organization_id)` **e** relação verificada **antes** de devolver a linha; RLS/deny-by-default como defesa em profundidade |
| T3 | **Alteração de autoria** | `autorMatricula`/`autorNome` no payload; `excluidaPor*` textual | autoria **derivada** de `auth.uid()` na fronteira (**D3**); campos de autoria **não** existem no contrato de mutação; FK de membership; autoria imutável |
| T4 | **Alteração indevida de `collaborator_id`** | campo do objeto local | `collaborator_id` **não** é editável (**D4**); alvo vem do alvo da operação e é revalidado no tenant |
| T5 | **Alteração indevida de `cycle_id`** | `atualizarObservacao` recusa, mas o blob é livre | `cycle_id` **fora** do contrato de edição (**D4**); FK de tenant; mudança de ciclo ⇒ `INVALID_INPUT` |
| T6 | **Leitura fora do escopo** | leitura sem gate (`ColaboradorDetalhePage`) | gate funcional `observation.read` + relação; leitura de terceiros só por RPC com gate; **SELF só comunicadas** (**D7/D9**) |
| T7 | **Mutação fora do escopo** | `edit`/`delete` só com `can()` (UX) | `authorize` equivalente **server-side** em toda RPC; `authorize()` no cliente é UX, nunca enforcement |
| T8 | **Manipulação de histórico** | array embutido, reescrevível | trilha append-only com ACL sem `UPDATE`/`DELETE`/`TRUNCATE` **e** triggers de imutabilidade; before-image + `payload_hash` (**D6**) |
| T9 | **Exclusão física** | limpar `localStorage` apaga tudo | `DELETE`/`TRUNCATE` revogados até de `service_role`; exclusão **só** lógica; carimbo + motivo (**D8/D16**) |
| T10 | **Spoofing de comunicado** | booleano anônimo alterável na edição | `comunicado_em`/`comunicado_por_*` gravados server-side; CHECK de coerência; evento próprio; sem campo livre de "comunicado por" (**D7**) |
| T11 | **Concorrência / lost update** | array inteiro regravado (last-write-wins) | `expected_version` + `SELECT ... FOR UPDATE`; `version + 1`; evento na **mesma** transação (**D10**) |
| T12 | **Replay / duplicidade** | não existe | `unique (organization_id, operation_id)` + `payload_hash` derivado server-side; replay com a mesma intenção devolve o mesmo resultado; intenção divergente ⇒ `CONFLICT`; sub-eventos via `f5_10_derivar_operation_id` |
| T13 | **Escalada por `capability`/`role` no corpo** | `authorizationContext` montado no cliente | allowlist **estrita** de chaves por operação (forma nunca é autoridade); capability derivada de mapa fechado; `role`/`cargo`/`funcao` **nunca** autorizam |
| T14 | **Estado autorizativo declarado pelo cliente** | `comunicado`/`excluida` no payload | estado lido da **linha soberana**; o cliente envia **intenção**, nunca estado |
| T15 | **Denial-of-service por payload** | texto livre sem limite | limite de tamanho na fronteira **e** no banco, 1..2000 (**D16**) |
| T16 | **Vazamento por log/erro** | mensagens cruas | códigos públicos fechados (`CodigoPublico`) na Edge; mensagem do banco nunca chega ao cliente |
| T17 | **Fail-open silencioso** | `catch { return [] }` e mundo DEV | fail-closed explícito: indisponibilidade vira **erro/fase explícita**, nunca lista vazia silenciosa |
| T18 | **Concessão indevida de leitura confidencial** | — | `observation.*` **fora** do bundle `admin` (guarda existente preservada); concessão explícita, em bundle de gestão distinto, testável no caminho de produção (**D15**) |
| T19 | **Autoria de terceiro sobrescrevendo registro alheio** | qualquer um com a capability no escopo editava/excluía | **somente o autor soberano** edita/exclui/revoga/altera comunicado, cumulativamente com os demais gates (**D5**) |

## 10. Dados legados (DECIDE — D13: **NÃO migrar**)

**DECIDE (D13):** **não migrar** o acervo de `feedback-control-observacoes`. Os dados atuais de
`localStorage` **são descartáveis de DEV/teste**. Evidência que sustenta a decisão (o implementador
deve **reconferir**, não presumir):

1. **Fonte:** os dados vivem **apenas** no `localStorage` de cada navegador; não há cópia
   server-side, não há contagem possível e não há `organization_id` associado.
2. **Dados de DEV/teste:** o gerador de dados de teste é o **segundo produtor** da chave
   (`geradorDadosTeste.ts`, DEV-gated) e o reset de base de desenvolvimento a **apaga**
   (`resetBaseDesenvolvimento.ts:19-25`) — ambos tratam a chave como **descartável**.
3. **Sem ponte autoritativa:** não existe bridge `(ano, ciclo)` ↔ `evaluation_cycles.id` **para
   observações** nem vínculo confiável matrícula → `collaborators.id` no acervo. A ponte
   `evaluation_resolver_ciclo` **existe** (§6.8) e poderia ser usada, mas o acervo não tem origem
   autenticada: a "matrícula do autor" foi escolhida no seletor de impersonação.
4. **Ausência de evidência de uso real:** não há telemetria, log ou consulta que prove existência de
   observações de produção. **Não é** prova de ausência — é ausência de prova.

**Condição NORMATIVA de reabertura (D13):** esta decisão só se reabre com **evidência concreta e
verificável** de conteúdo de produção com valor funcional (por exemplo, relato do responsável de
produto de que avaliações publicadas dependem de observações comunicadas de um determinado ciclo).
Sem essa evidência, migrar seria construir histórico **não soberano** (autoria não verificável) sobre
dados não rastreáveis — o que contraria o objetivo da atividade. Reabrir exige **nova decisão
registrada**, não reinterpretação na implementação.

**Consequência NORMATIVA para o cutover (D13 + D5/D9):** aplica-se o modelo de **barreira de
escrita** já usado na F5-10 (D24): **não há migração**; a leitura legada **não** sobrevive como
fallback funcional; a escrita local passa a **lançar** apontando a porta soberana; **após** o cutover
não há dual-read. Nenhuma rotina remove automaticamente a chave do usuário.

## 11. Estratégia de cutover (NORMATIVO — DECIDE D4, D5, D9, D13, D14, D15)

1. **Autorização primeiro, UI depois:** `observation` sai de `TIPOS_RECURSO_NAO_SOBERANOS`
   (`resourceContextReal.ts:38`), ganha `carregarRecurso` real e `alvosPermitidos` por relação; o
   gate funcional passa a existir **antes** de a UI mudar de fonte (D9).
2. **Concessão antes do cutover (D15):** a tabela `capability → bundle/perfil existente → escopo`
   exigida por D15 deve estar **documentada antes da P3**; sem ela a P3 não inicia.
3. **Porta soberana de leitura** (molde `src/services/*Soberanos/` + repositório
   `src/infrastructure/supabase/observacoes/`) — a UI **não** fala RPC direto.
4. **Controlador de mutações** por operação (`criar`, `editar`, `definir_comunicado`, `excluir`,
   `revogar`) com `operation_id` gerado no cliente e `expected_version` da leitura soberana;
   **nenhum** campo de autoria/tenant/estado é enviado pelo cliente (D3/D4).
5. **Telas/consumidores:** `ObservacoesColaborador.tsx` (CRUD + histórico), `ColaboradorDetalhePage`
   (KPIs `contarObservacoesPorTipo` + painel), `MinhaAvaliacaoDetalhePage` (comunicadas),
   `exportarAvaliacaoPdf` (comunicadas). O filtro/ordenação
   (`filtroObservacoesPorCiclo.ts`, `ordenacaoPorCiclo.ts`) é reaproveitado sobre as projeções
   soberanas.
6. **Barreira contra persistência local (D13):** `observacaoStorage.ts`
   (`criarObservacao`/`atualizarObservacao`/`excluirObservacao`) passa a **lançar** apontando a porta
   soberana, e a leitura local sai do **caminho funcional** — sem dual-read. Nenhuma remoção
   automática da chave do usuário.
7. **Segundo produtor:** `geradorDadosTeste.ts` deixa de escrever a chave legada (ou passa a gerar
   via porta soberana), e a lista de exceção "legado leitura"
   (`estruturaUiSeguranca.test.ts:391-409`) é ajustada.
8. **Guardas invertidas do CI:** substituir `15-validar-f5-09-p9.sql:2121-2173` e
   `30-validar-f5-10-p7.sql:1401-1413` pelas asserções positivas da F5-11 (a tabela/funções passam a
   ser **exigidas**, com a contagem de capabilities **inalterada** em 31).
9. **Dívidas encerradas na F5-11:** os marcadores `▸(add authorize)` de
   `docs/F4-09-desenho-tecnico.md:253-255` e a assimetria registrada em
   `docs/F5-07-desenho-tecnico.md:1331-1338` §20.4 — a assimetria é corrigida **invertendo**
   `authorizationPolicy.test.ts:508-518` (D5).
10. **Resíduo morto:** decidir destino de `ImpactoTemporalPeriodoCiclo.observacoes`,
    `persistirCorrecaoPeriodoCicloAtivoInterno` e `confirmarCorrecaoPeriodoCiclo.ts:14`.

## 12. Testes necessários (NORMATIVO)

**SQL (`supabase-local`), numeração a partir de 34:**

- preflight/guarda final fail-closed do par de tabelas: `ENABLE RLS`, ACL, `version`, CHECKs de
  coerência (`comunicado`, `exclusao`), FKs compostas de tenant;
- invariantes: exclusão **física** negada (42501/trigger) em `evaluation_observations`;
  `UPDATE`/`DELETE`/`TRUNCATE` negados em `evaluation_observation_events`;
- cross-tenant e IDOR por UUID (alvo de outro tenant ⇒ `NOT_FOUND`; leitura fora do escopo ⇒ 0
  linhas / negado);
- membership revogada; perfil inativo; capability ausente; relação ausente (fail-closed);
- matriz de estados: ciclo `PLANEJADO|ATIVO|ENCERRADO|CANCELADO` × colaborador
  `active|leave|inactive` × operações;
- `expected_version` obsoleto ⇒ `CONFLICT`; idempotência (mesmo `operation_id` + mesmo hash ⇒ mesmo
  resultado; hash divergente ⇒ `CONFLICT`); rollback multi-escrita (observação + evento);
- **concorrência real entre duas sessões**: duas edições simultâneas da mesma observação e
  comunicação concorrente; a perdedora termina em `CONFLICT` **depois** de esperar o lock;
- prova de que o catálogo permanece **31** e `goal.% + observation.%` = **8**.

**TS/node:** Policy Engine (`observation` como recurso soberano; SELF só comunicadas; editar/excluir
de terceiro ⇒ DENY — **invertendo** `authorizationPolicy.test.ts:508-518`); fronteira soberana
(UUID canônico, tenant divergente, membership revogada, `authorize` em edição/exclusão); porta do
cliente (fail-closed, todos os `CodigoPublico`); guardas anti-`localStorage`/anti-UUID-no-browser e
anti-`localWorld` no caminho de observações; paridade `catalogoCapabilities` ↔ DB.

**Ajustes obrigatórios:** `observacaoStorage.test.ts` (barreira de escrita),
`reaberturaCicloService.test.ts:110-159` e `cancelamentoCicloService.test.ts:64-90` (preservação sem
chave legada), `estruturaUiSeguranca.test.ts` (listas de exceção), os validadores SQL que hoje
**proíbem** observação, `catalogoCapabilities.test.ts` (concessão de D15) e
`p9MatrizIntegrada`/guards que contam 8 capabilities.

## 13. Decomposição oficial (DECIDE — D14)

**DECIDE (D14):** a F5-11 é executada em **P0–P6**, com estas fronteiras — **P0 está CONCLUÍDO por
este documento**:

| Fase | Conteúdo oficial | Por que é uma fronteira própria |
|---|---|---|
| **P0** | **Reconhecimento + desenho + fechamento arquitetural** (este documento; Q1–Q16 fechadas em D1–D16) | nenhuma implementação começa com decisão arquitetural aberta (`AGENTS.md` §6) |
| **P1** | **Schema + trilha + substituição das guardas invertidas:** `evaluation_observations` + `evaluation_observation_events` (§7.2), FKs compostas de tenant, CHECKs de coerência, `version`, ACL/deny-by-default, triggers de imutabilidade, cenário + validador, e a substituição de `15-validar-f5-09-p9.sql:2121-2173` / `30-validar-f5-10-p7.sql:1401-1413` | é o único pacote que mexe no schema e nas guardas que hoje **proíbem** observação |
| **P2** | **RPCs `observacao_*`:** criar/editar/definir_comunicado/excluir/revogar/obter/listar_por_escopo/histórico; `expected_version`, `operation_id`, idempotência, eventos, gate funcional reutilizável | domínio puro, sem UI; gateia tudo antes de existir superfície |
| **P3** | **Autorização + capabilities/concessões + RLS:** `observation` como **recurso soberano** (sai de `TIPOS_RECURSO_NAO_SOBERANOS`), `carregarRecurso`, `alvosPermitidos` por relação, matriz capability × estado com **fonte única**, **concessão explícita (D15)** com tabela `capability → bundle/perfil existente → escopo` documentada **antes** do início, RLS deny-by-default integral | mudança **transversal** ao Policy Engine e à concessão — não é "mais uma RPC" |
| **P4** | **Edge + cliente:** Edge `observacoes` (trio `index`/`core`/`contrato`) + contrato transportável único + adapter fail-closed + guardas de grafo de imports | fronteira de confiança e de exposição |
| **P5** | **Cutover + barreira contra persistência local:** porta soberana, controlador de mutações, telas, consumidores de arrasto (PDF, MinhaAvaliação, KPIs), barreira que lança em `observacaoStorage.ts`, `geradorDadosTeste`, listas de exceção, resíduo morto | é o pacote que **remove** o legado do caminho funcional |
| **P6** | **Validação integrada / certificação da F5-11:** matriz SQL, concorrência real entre duas sessões, regressões, relatório de gates executados × não executados (molde `docs/F5-09-p9-matriz-integrada.md`) | fecha com evidência, não com opinião |

### 13.1 Dependências entre os pacotes (NORMATIVO)

| Fase | Depende de | Dependência crítica declarada |
|---|---|---|
| **P1** | — (P0 concluído) | Nada bloqueia a P1. As guardas invertidas do CI **precisam** ser substituídas **na mesma fase**, sob pena de o CI falhar por guarda obsoleta. |
| **P2** | **P1** | As RPCs exigem as tabelas, a trilha, `version` e as ACLs da P1. Sem P1 não há alvo. |
| **P3** | **P1** + **P2** | A RLS da P3 incide sobre as tabelas da P1; a matriz e a concessão fecham o gate já implementado na P2 (**o gate não pode existir sem concessão**: sem D15 a P3 entrega DENY). **Pré-requisito de entrada:** tabela `capability → bundle/perfil existente → escopo` **documentada** neste documento (D15 item 3). |
| **P4** | **P2** + **P3** | A Edge precisa das RPCs (P2) e do gate/concessão decisível em produção (P3) para o teste de ALLOW real. |
| **P5** | **P4** | Não se faz cutover da UI sem a fronteira Edge/adapter pronta, sob pena de duas verdades na tela. |
| **P6** | **P1–P5** | É a certificação do conjunto; não inicia com qualquer fase pendente. |

**Ordem estrita:** P1 → P2 → P3 → P4 → P5 → P6. **Não há fase paralelizável** entre P1–P5 (cada uma
consome a anterior). P0 está fechado. Nenhuma fase pode ser iniciada "adiantando" parte da seguinte.

### 13.2 Por que não é 1 pacote e por que não são 7

**Por que não é 1 pacote:** há fronteiras arquiteturais claras (schema/ACL ≠ domínio ≠ autorização
transversal ≠ fronteira ≠ cutover ≠ validação) e cada uma tem gate próprio; um único PR misturaria
migration, RPC, Policy Engine, Edge e UI — exatamente o que a F5-10 evitou.

**Por que não são 7 como na F5-10:** a F5-10 tinha **aprovações**, **autorização+RLS** e **backfill**
como pacotes separados. A F5-11 **não tem** aprovação, **não tem** quota/limite, **não tem** matriz
de invalidação e **não tem** backfill (§10, D13) ⇒ 6 pacotes de implementação. A identificação do
bundle de concessão (D15) é **artefato obrigatório da P3**, não uma fase nova.

## 14. Decisões JÁ FECHADAS (herdadas — não reabrir)

| Origem | Decisão herdada que vincula a F5-11 |
|---|---|
| `AGENTS.md` §3 / `architecture-rules.md` §1 | `auth.uid()` soberano; tenant server-side; fail-closed; cross-tenant DENY; `can()` = UX, `authorize()` = enforcement; RLS como barreira |
| `architecture-rules.md` §2 | capability = ação, scope = alcance; role é a única via de concessão; **nenhuma autorização runtime por cargo/`funcao`** |
| `architecture-rules.md` §3 | preservar históricos e trilhas; mutações rastreáveis com autoria soberana |
| F5-10 **D6** | **nenhuma capability nova** (catálogo permanece 31) |
| F5-10 **D10** | família de advisory lock: **uma chave por família**, sem lock independente nem ordem incompatível |
| F5-10 **D11** | trilha append-only + idempotência `(organization_id, operation_id)` + `payload_hash` server-side |
| F5-10 **D12** | `expected_version` obrigatório em toda mutação; `version + 1`; `CONFLICT` |
| F5-10 **D22/§11** | RLS = isolamento de tenant; Policy Engine = autoridade funcional; `SELECT` de tenant **não** concede leitura funcional de terceiros |
| F5-10 **D22-A** (P5) | padrão **deny-by-default integral** disponível e aplicado (ZERO policy e ZERO privilégio de cliente) |
| F5-10 **D24** | cutover com **barreira de escrita**, sem fallback funcional após o cutover |
| F5-10 **D25** | projeção **congelada** (`evaluation_participants`) como fonte da legitimidade relacional |
| F4-09 §7.3 | matriz normativa de observações **já existe** (criar/editar/excluir/comunicado/SELF); os marcadores `▸(add authorize)` são **dívida a quitar aqui** |
| F4-08 D21 | policy **antes** do grant; `service_role` **executa, nunca decide** |
| F5-09 D1–D28 | ciclo soberano, `cycle_events` append-only, RPCs `ciclo_*`, UUID canônico — **não reabrir** |

> **Nota de numeração:** as decisões **próprias da F5-11** são **D1–D16**, fechadas em **§15** e sempre
> referenciadas neste documento sem prefixo (`D6`, `D13`…). As decisões **herdadas** de outras
> atividades são **sempre prefixadas com a atividade** (`F5-10 D6`, `F5-10 D24`, `F5-09 D28`…) e não
> se confundem com as da F5-11.

## 15. DECISÕES NORMATIVAS FECHADAS (Q1–Q16 → D1–D16)

> **Fechamento:** a **auditoria GPT aprovou o desenho** e **fechou Q1–Q16 na alternativa A**
> recomendada. Cada decisão abaixo é **NORMATIVA** e vincula a implementação das fases P1–P6; o
> histórico das alternativas A/B/C é preservado para rastreabilidade. **Nenhuma questão permanece
> aberta.** Rastreabilidade Q# → D# em **§15.10**.

**D1 — Nomenclatura e forma das tabelas (Q1 = A).**
**DECIDE:** as tabelas são `public.evaluation_observations` (linha) e
`public.evaluation_observation_events` (trilha append-only); as RPCs usam o prefixo `observacao_*`.
*Alternativas descartadas:* **B)** `observations`/`observation_events`; **C)** reusar `cycle_events`
com `entity_type = 'evaluation_observation'` — **C é incompatível**: `cycle_events` tem
`ck_cycle_events_entity_type check (entity_type = 'evaluation_cycle')` e
`unique (organization_id, operation_id)`, o que colidiria a idempotência e exigiria alterar
constraint de contrato F5-09 **fechado**.
*Fundamento:* consistência com `evaluation_goals`/`evaluation_goal_events` e ausência de colisão.

**D2 — `cycle_id` obrigatório e soberano (Q2 = A).**
**DECIDE:** `cycle_id uuid NOT NULL`, referenciando `evaluation_cycles.id`, com FK **composta de
tenant**. **O modelo legado de observação sem ciclo NÃO é preservado** — não existe estado "fora de
ciclo", coluna `fora_do_ciclo` nem ciclo nulo.
*Alternativas descartadas:* **B)** `cycle_id` nulo com estado explícito "sem ciclo"; **C)**
`cycle_id NOT NULL` + coluna `fora_do_ciclo boolean`.
*Fundamento:* a criação legada **sempre** exige `(ano, ciclo)` com ciclo `ATIVO`
(`observacaoStorage.ts:30-39,98-137`); os campos opcionais do tipo existiam **apenas** para dados
antigos, que **não serão migrados** (§10, D13); "fora de ciclo" não tem regra funcional, escopo nem
autorização — criá-lo seria inventar domínio.

**D3 — Autoria exclusivamente derivada do contexto autenticado (Q3 = A).**
**DECIDE:** a autoria é **derivada** de `auth.uid()` verificado na fronteira e gravada pelo servidor
em `author_user_profile_id` + `author_membership_id` (ambos **NOT NULL**) e `author_collaborator_id`
(derivado do vínculo; nulo quando o ator não tem vínculo de colaborador). **Nenhum**
`author_user_profile_id`, `author_membership_id`, membership, matrícula, nome ou equivalente
**fornecido pelo cliente é autoridade** — esses campos **não existem** no contrato transportável de
mutação. A operação exige **vínculo único de colaborador ativo** na organização (padrão
`f5_10_vinculo_meta_do_ator`); sem vínculo ⇒ **DENY**, inclusive para ADMIN ("ADMIN não é superuser
de conteúdo confidencial").
*Alternativas descartadas:* **B)** apenas `author_user_profile_id`; **C)** manter
`autorMatricula`/`autorNome` como rótulos vindos do cliente — **C é exatamente a ameaça T3**.
*Fundamento:* identidade soberana; rótulos de exibição (nome/matrícula) podem existir como
**projeção calculada server-side**, nunca como campo aceito do cliente.

**D4 — Semântica da edição; colaborador, ciclo e autoria imutáveis (Q4 = A).**
**DECIDE:** a edição recebe a **definição completa** dos campos mutáveis (`tipo` + `texto` +
`comunicado`) e **não** faz merge parcial. **`collaborator_id`, `cycle_id` e autoria são IMUTÁVEIS
após a criação**; o contrato de forma **nem aceita** esses campos nas operações de mutação existente
— enviá-los ⇒ `INVALID_INPUT`.
*Alternativas descartadas:* **B)** edição parcial (só os campos enviados); **C)** edição restrita a
`texto` (tipo e comunicado só na criação).
*Fundamento:* paridade com o legado (a UI edita tipo, texto e comunicado) e com `goal.editar`
(F5-10 §13: a RPC recebe a definição completa; a fronteira não faz merge de domínio).

**D5 — Somente o autor soberano edita/exclui/revoga/altera comunicado (Q5 = A).**
**DECIDE:** **somente o autor soberano** (`author_user_profile_id = ator`) pode **editar, excluir,
revogar a exclusão e alterar o estado de comunicado**, sempre **cumulativamente** com os demais
gates: capability, relação, organização/membership, estado do colaborador e estado do ciclo. **Não
existe** edição/exclusão de observação de terceiro — nem pela cadeia de gestão.
*Alternativas descartadas:* **B)** autor **ou** a cadeia de gestão acima; **C)** qualquer ator com a
capability no escopo (comportamento atual, testado em `authorizationPolicy.test.ts:508-518`).
*Fundamento:* a observação é **registro de autoria**; permitir que terceiro reescreva o texto de outro
autor destrói a integridade probatória (T3/T8/T19) e é incompatível com "histórico auditável".
**C é explicitamente rejeitada** e exige **inverter** o teste citado. Correção por terceiro, se
necessária ao produto, se faz por **nova observação** — nunca por sobrescrita alheia.

**D6 — Histórico append-only, auditável e imutável (Q6 = A).**
**DECIDE:** existe **uma** trilha append-only, `evaluation_observation_events`, com
`before_value`/`after_value jsonb`, `payload_hash` (SHA-256 derivado server-side), `operation_id`,
`actor_*` e `event_type ∈ {CRIADA, EDITADA, COMUNICADO, COMUNICACAO_REMOVIDA, EXCLUIDA, REVOGADA}`.
**Não** há tabela de histórico adicional além da trilha. **É proibido reescrever ou excluir
fisicamente eventos**: imutabilidade em **duas camadas** (ACL sem `UPDATE`/`DELETE`/`TRUNCATE` **e**
triggers `BEFORE UPDATE`/`DELETE`/`TRUNCATE` que abortam, resistentes a drift de privilégio).
*Alternativas descartadas:* **B)** trilha sem before-image (só hash/after-image); **C)** sem trilha,
com colunas de auditoria na linha — **C é rejeitada**: colunas na linha não são append-only.
*Fundamento:* é o único desenho que preserva o que a UI mostra hoje ("Texto anterior",
`ObservacoesColaborador.tsx:641-653`), cumpre "histórico auditável" e impede manipulação (T8).

**D7 — "Comunicado" é fato auditável; gate `observation.edit` (Q7 = A).**
**DECIDE:** `comunicado` **é** fato auditável com **ator e instante**: `comunicado = true` exige
`comunicado_em` + `comunicado_por_user_profile_id` + `comunicado_por_membership_id` (CHECK de
coerência), e **cada** transição grava evento próprio (`COMUNICADO` / `COMUNICACAO_REMOVIDA`). O gate
é **`observation.edit`** sobre o recurso, **exclusivamente pelo autor soberano** (D5).
**Não é criada capability nova apenas para isso.**
*Alternativas descartadas:* **B)** manter apenas `comunicado boolean` (estado atual) — **rejeitada**
pela ameaça T10; **C)** capability nova `observation.communicate` — **rejeitada**: quebraria a decisão
herdada F5-10 D6 (catálogo **31**) e exigiria reescrever validadores de contagem em vários arquivos de
CI.
*Fundamento:* comunicar é **ato de disponibilização ao avaliado** (habilita a leitura SELF) e precisa
de autoria e instante; o catálogo F4-01 registrou a semântica como **futura**
(`20260908000001:59-60`) e a F4-09 §7.3 já a mapeia para `observation.edit`.

**D8 — Exclusão lógica com motivo; revogação pelo autor em ciclo ATIVO (Q8 = A).**
**DECIDE:** a exclusão é **sempre lógica** (`excluida = true` + ator + instante + `motivo_exclusao`
**obrigatório**), com evento `EXCLUIDA`; **exclusão física é proibida**. A **revogação** da exclusão é
operação **distinta**, permitida **somente pelo autor soberano** (D5) e **somente com ciclo `ATIVO`**
(D12), com gate `observation.edit`, evento `REVOGADA`, `version + 1` e motivo obrigatório. A trilha
preserva `EXCLUIDA` **e** `REVOGADA` — a exclusão **nunca** é apagada do histórico.
*Alternativas descartadas:* **B)** não existir revogação (paridade estrita com o legado); **C)**
capability nova `observation.revoke` — **rejeitada** pelo mesmo motivo de D7-C (F5-10 D6 herdada).
*Fundamento:* a exclusão é lógica, logo desfazê-la é operação de **estado**, não de destruição; o
escopo da atividade inclui "excluir/revogar".

**D9 — RLS nasce deny-by-default integral (Q9 = A).**
**DECIDE:** as duas tabelas nascem com `ENABLE RLS`, **ZERO policy** e **ZERO privilégio de cliente**
(`anon`/`authenticated`) para `SELECT`/`INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`REFERENCES`/`TRIGGER`.
A leitura **passa exclusivamente** pela superfície soberana (RPC com gate, via Edge). Padrão
**D22-A** já aplicado na F5-10 P5 (`20260927000000:54-58`). **Não** se repete o padrão de exposição
temporária seguido de hardening posterior.
*Alternativas descartadas:* **B)** policy `select_same_tenant` + `grant select` mínimo (padrão da
F5-10 **P4**, depois revertido); **C)** policy own-tenant + policy SELF adicional.
*Fundamento:* o conteúdo da observação é **confidencial** (catálogo F4-01: "conteúdo de terceiros é
confidencial"); expor `SELECT` de tenant e só depois endurecer gera retrabalho e risco (lição R11 da
F5-10). Além disso, D9 evita depender de `evaluation_cycles` permanecer legível por `authenticated`
(assimetria declarada em aberto pela F5-10 P5).

**D10 — Concorrência por `version` + row lock; sem advisory lock (Q10 = A).**
**DECIDE:** a concorrência usa **`expected_version` + `SELECT ... FOR UPDATE`** na linha da
observação, com `version = version + 1` em toda mutação efetiva e o evento gravado na **mesma**
transação. **Não é introduzido advisory lock** — nenhuma família nova e nenhum reuso de
`ciclo_lock_organizacao`.
*Alternativas descartadas:* **B)** reusar `ciclo_lock_organizacao` (família `evaluation_cycles:<org>`);
**C)** família nova `evaluation_observations:<org>` — **rejeitada**: a doutrina de
`20260914020000_f5_08_lock_key_alignment.sql` exige **uma** chave por família e proíbe família nova
sem necessidade demonstrada.
*Fundamento:* a observação é uma **linha isolada** cuja mutação não altera estado de ciclo, quota ou
agregado; versão otimista + row lock já elimina lost update (T11) sem serializar todas as escritas de
observação da organização. **Condição NORMATIVA de revisão:** se a implementação introduzir
invariante sobre o **conjunto** (ex.: limite de observações por ciclo, comunicação em lote), esta
decisão **deve** ser reaberta por nova decisão registrada.

**D11 — Estado do colaborador (Q11 = A).**
**DECIDE:**
- **`active`** (`ATIVO`): comportamento normal, conforme a relação.
- **`leave`** (`LICENCA`): **criação permitida**, assim como editar, comunicar e excluir (paridade
  explícita com o legado e com `authorizationPolicy.test.ts:132-149`).
- **`inactive`** (`DESLIGADO`): **nova criação proibida**; comunicação e edição proibidas.
- **Leitura histórica permanece disponível** conforme autorização, em **todos** os estados; a
  exclusão permanece permitida (higiene de conteúdo).
- **Status do colaborador não resolvido** ⇒ **DENY** (fail-closed).
*Alternativas descartadas:* **B)** `inactive` **e** `leave` bloqueiam criação, comunicação e edição —
mudaria comportamento sem evidência de produto; **C)** bloquear apenas quando o status **não resolve**
— **rejeitada**: status não resolvido já é DENY por falta de evidência, não por regra de negócio.

**D12 — Estado do ciclo (Q12 = A).**
**DECIDE:** **mutações somente com ciclo `ATIVO`**, lido da **linha soberana** (criar, editar,
comunicar, descomunicar, excluir, revogar). **A leitura histórica permanece disponível nos demais
estados** (`PLANEJADO`, `ENCERRADO`, `CANCELADO`) conforme autorização.
*Alternativas descartadas:* **B)** leitura vedada em `CANCELADO` — esconderia trilha auditável sem
base; **C)** mutação também em `ENCERRADO` mediante capability excepcional — criaria caminho de
mutação pós-encerramento sem contrato.
*Fundamento:* paridade com `validarCicloAtivo` (`observacaoStorage.ts:30-39`) e com a matriz de metas
(F5-10 §10); o histórico precisa sobreviver ao encerramento.

**D13 — Dados legados: NÃO migrar (Q13 = A).**
**DECIDE:** os dados atuais de `localStorage` (`feedback-control-observacoes`) **NÃO serão migrados**
— são **descartáveis de DEV/teste**. Aplica-se **barreira contra persistência local**: a escrita local
passa a **lançar** apontando a porta soberana, **não há dual-read** e a leitura local sai do caminho
funcional. **Nenhuma** rotina remove automaticamente a chave do usuário. A reabertura exige
**evidência concreta de perda funcional relevante para produção** e **nova decisão registrada**
(§10).
*Alternativas descartadas:* **B)** não migrar, mas manter leitura local rotulada "legado" no painel —
mantém duas verdades na mesma tela, antipadrão já rejeitado pela F5-10 D24; **C)** migrar com pontes
autoritativas, congelamento e quarentena — criaria histórico **soberano** sobre **autoria não
soberana**.
*Fundamento:* §10 (fonte apenas no navegador, sem `organization_id`, sem contagem possível, sem ponte
autoritativa e sem prova de uso real).

**D14 — Decomposição oficial P0–P6 (Q14 = A).**
**DECIDE:** a F5-11 é executada nas fases **P0 a P6** definidas em §13, com a **ordem estrita** e as
**dependências** de §13.1: **P0** = reconhecimento + desenho + fechamento arquitetural (**concluído
por este documento**); **P1** = schema + trilha + substituição das guardas invertidas; **P2** = RPCs
`observacao_*`; **P3** = autorização + capabilities/concessões + RLS; **P4** = Edge + cliente;
**P5** = cutover + barreira contra persistência local; **P6** = validação integrada/certificação da
F5-11.
*Alternativas descartadas:* **B)** pacote único — misturaria migration, RPC, Policy Engine, Edge e UI
no mesmo PR; **C)** P1–P4 fundindo autorização no schema e Edge no cutover — acoplaria a mudança
transversal de autorização (P3) ao schema, dificultando auditoria.
*Fundamento:* fronteiras arquiteturais reais, cada uma com gate próprio; não são 7 como na F5-10
porque a F5-11 **não tem** aprovação, quota/limite, matriz de invalidação nem backfill (§13.2).

**D15 — Concessão explícita de `observation.*`, em bundle/perfil de gestão distinto de `admin`
(Q15 = A).**
**DECIDE:**
1. `observation.*` **recebe concessão explícita** em **bundle/perfil de gestão adequado, distinto de
   `admin`**, pelo mecanismo existente (`access_roles` + `access_role_capabilities` +
   `access_role_assignment_scopes`).
2. **`admin` permanece sem `observation.*`** — a guarda `02-validar-f4-01.sql:563-578` é preservada e
   **não** pode ser alterada para acomodar a F5-11.
3. **Antes da P3**, este documento **deve** conter a tabela **`capability → bundle/perfil existente →
   escopo`**, identificando **exatamente qual bundle existente** recebe cada capability; a tabela é
   **artefato de entrega da P3** e sua ausência **bloqueia o início da P3**.
4. **É proibido inventar um novo papel/bundle silenciosamente**; se nenhum existente servir, a criação
   de um novo é **decisão explícita registrada**, precedida de declaração escrita de que os
   existentes foram avaliados e por que não servem.
5. A concessão é **testável no caminho de produção** (nunca `localWorld`/DEV).
*Alternativas descartadas:* **B)** apenas roles customizadas (o domínio nasceria DENY no seed, com o
ADMIN concedendo caso a caso); **C)** incluir as 4 no bundle `admin` — **rejeitada**: a guarda
`02-validar-f4-01.sql:563-578` **exige** que `admin` **não** contenha
`observation.read`/`create`/`edit`/`delete` (nem `report.read`), e a doutrina diz que ADMIN não é
superuser de conteúdo confidencial.
*Fundamento:* sem concessão explícita o domínio nasce **DENY em produção** (análogo ao R2 da F5-10).

**D16 — Limites de forma e motivo (Q16 = A).**
**DECIDE:** `texto` tem limite explícito de **1..2000 caracteres**, com `btrim` e não vazio, validado
**na fronteira e no banco**; `motivo_exclusao` é **obrigatório** na exclusão (e na revogação), com
`btrim` e 1..2000. Os demais limites são exatamente os do §7.2/§7.3.
*Alternativas descartadas:* **B)** texto sem limite e motivo opcional; **C)** texto 1..500 (paridade
literal com `LIMITE_TEXTO` de metas) e motivo obrigatório.
*Fundamento:* `cycle_events.reason` é `not null` e `goal.excluir` exige motivo — a auditabilidade da
exclusão depende do motivo; 500 caracteres é apertado para um texto de observação (o legado não impõe
limite) e 2000 mantém o limite tanto no banco quanto na fronteira (ameaça T15).

### Rastreabilidade Q# → D# (nenhuma questão permanece aberta)

| Questão | Alternativa fechada | Decisão normativa | Onde incide |
|---|---|---|---|
| Q1 | **A** | **D1** nomenclatura/forma das tabelas | §7.2, P1 |
| Q2 | **A** | **D2** `cycle_id` obrigatório e soberano | §7.2, §7.4, DDL, P1 |
| Q3 | **A** | **D3** autoria derivada do contexto autenticado | §7.1, §7.3, §8, P2/P3 |
| Q4 | **A** | **D4** edição completa; colaborador/ciclo/autoria imutáveis | §7.3, §7.5, T4/T5, P2 |
| Q5 | **A** | **D5** só o autor soberano edita/exclui/revoga/comunica | §7.5–§7.7, §8, T19, P3 |
| Q6 | **A** | **D6** trilha append-only imutável com before/after | §7.2, §7.8, T8, P1 |
| Q7 | **A** | **D7** comunicado como fato auditável; gate `observation.edit` | §7.2, §7.7, T10, P1/P2 |
| Q8 | **A** | **D8** exclusão lógica com motivo; revogação em ciclo ATIVO | §7.6, T9, P1/P2 |
| Q9 | **A** | **D9** RLS deny-by-default integral desde a P1 | §8, T6, P1/P3 |
| Q10 | **A** | **D10** `version` + row lock; sem advisory lock | §8, T11, P2 |
| Q11 | **A** | **D11** estado do colaborador | §7.9, §8, P2/P3 |
| Q12 | **A** | **D12** estado do ciclo | §7.4, §7.9, §8, P2/P3 |
| Q13 | **A** | **D13** não migrar; barreira contra persistência local | §10, §11, P5 |
| Q14 | **A** | **D14** decomposição oficial P0–P6 | §13, §13.1, §13.2 |
| Q15 | **A** | **D15** concessão explícita em bundle de gestão distinto de `admin` | §8 (Concessão), P3 |
| Q16 | **A** | **D16** texto 1..2000, `btrim`; motivo obrigatório | §7.2, §7.3, T15, P1 |

## 16. Riscos e mitigação normativa

| # | Risco | Sev. | Mitigação NORMATIVA |
|---|---|---|---|
| R1 | `observation.*` sem concessão ⇒ domínio **DENY** em produção (análogo ao R2 da F5-10) | alta | **D15** (concessão explícita em bundle/perfil de gestão distinto de `admin`) + teste de ALLOW no caminho de produção na P3 |
| R2 | Autoria continuar não soberana (impersonação/`usuarioAtual`) | alta | **D3** (autoria derivada, campos ausentes do contrato) + guardas anti-`localWorld`; C de Q3 explicitamente rejeitada |
| R3 | Editar/excluir observação de terceiro continuar ALLOW | alta | **D5** + **inversão obrigatória** de `authorizationPolicy.test.ts:508-518` (P3) |
| R4 | `comunicado` continuar booleano anônimo (divulgação não auditável) | alta | **D7** (carimbo + evento + CHECK de coerência) |
| R5 | Duas verdades na tela (local + soberano) durante o cutover | média | **D13** + barreira contra persistência local (F5-10 D24): a escrita local **lança**, sem dual-read |
| R6 | Relação congelada inexistente para o ciclo (sem avaliação/participantes) ⇒ **DENY** de criação legítima | média | P2/P3 devem provar o caminho normal na fixture; se insuficiente, exige **nova decisão** sobre a relação de leitura (§8, invariante 3) |
| R7 | Guardas invertidas do CI quebradas por engano em vez de substituídas | média | **D14/P1**: substituição declarada de `15-validar-f5-09-p9.sql:2121-2173` e `30-validar-f5-10-p7.sql:1401-1413` |
| R8 | Escopo vazar para F5-10/F5-12 ou para "observação de critério" | média | §2 + §3.10; validadores de contagem permanecem **31** e `goal.% + observation.% = 8` |
| R9 | RLS exposta e depois endurecida (retrabalho) | média | **D9** (deny-by-default integral **desde a P1**) |
| R10 | Concorrência subestimada (edição + comunicação simultâneas) | média | **D10** + concorrência real entre duas sessões na P6 |
| R11 | Perda silenciosa do acervo legado no cutover | baixa | **D13**: sem migração **decidida**; nenhuma remoção automática da chave do usuário |
| R12 | P3 iniciar sem a tabela `capability → bundle/perfil existente → escopo` e o bundle ser "inventado" na implementação | média | **D15 item 3/4**: a tabela é **artefato de entrega da P3** e sua ausência **bloqueia o início da P3**; papel novo só por **decisão explícita registrada** |
| R13 | `evaluation_cycles` continuar legível por `authenticated` (assimetria declarada em aberto pela F5-10 P5) | baixa | **D9** não depende dessa leitura |
| R14 | Reabertura indevida de D2 (observação "sem ciclo") por conveniência de implementação | média | **D2** é normativa: não existe estado fora de ciclo; a P1 falha se a coluna for anulável |
| R15 | Concessão exigida por D15 induzir alteração da guarda de conteúdo confidencial do bundle `admin` | alta | **D15 item 2** + guarda `02-validar-f4-01.sql:563-578` **preservada**; alterá-la é proibido |

## 17. Critérios de aceite, dependências e método

### 17.1 Critérios de aceite (NORMATIVO — D14)

**Globais (a F5-11 só é certificável com todos):**

1. Contêiner de observações no PostgreSQL com RLS **deny-by-default integral**, escrita fechada e
   trilha append-only (D6/D9).
2. **Nenhuma** autoridade funcional de observação no `localStorage`; **nenhum** fallback funcional;
   barreira que **lança** na persistência local (D13).
3. `observation.*` decidível **em produção** pelo caminho canônico (sem `localWorld`), com concessão
   explícita identificada (D15).
4. Autoria soberana derivada de `auth.uid()`, **imutável**, com `operation_id` e `payload_hash` (D3/D6).
5. **Somente o autor soberano** edita/exclui/revoga/altera comunicado, cumulativamente com os demais
   gates (D5).
6. **`cycle_id` obrigatório** e imutável; **colaborador e autoria imutáveis** (D2/D4).
7. Comunicação ao avaliado como **fato auditável** (quem/quando), e leitura SELF **apenas** do
   comunicado (D7).
8. Exclusão sempre lógica, com **motivo**, rastreabilidade e revogação auditada; exclusão física negada
   por ACL **e** por trigger (D8/D16).
9. `texto` 1..2000 na fronteira **e** no banco (D16).
10. Concorrência real provada entre duas sessões; `expected_version` e rollback comprovados (D10).
11. Cutover das telas e consumidores com ciclo por **UUID soberano**; guardas invertidas substituídas
    (D13/D14).
12. Gates verdes (focados, suíte completa, build, lint, `git diff --check`, bateria SQL na ordem do CI)
    no SHA auditado; CI verde; auditorias independentes aprovadas.
13. F5-10/F5-12 não antecipadas; contratos da F5-09 (D1–D28) e da F5-10 (D1–D25) não reabertos;
    catálogo permanece **31** e `goal.% + observation.% = 8`.

**Por fase (critério de aceite de cada pacote):**

| Fase | Critérios de aceite |
|---|---|
| **P0** | ✅ **Concluído**: reconhecimento + desenho + **Q1–Q16 fechadas em D1–D16** (§15), sem decisão aberta. |
| **P1** | Tabelas de §7.2 materializadas (nomes, colunas e constraints — D1/D2/D16); **RLS deny-by-default integral** provada (`has_table_privilege` falso para `anon`/`authenticated` em SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER — D9); trilha com `UPDATE`/`DELETE`/`TRUNCATE` negados por ACL **e** por trigger (D6); exclusão física negada em `evaluation_observations` (D8); FKs compostas de tenant provadas; guardas invertidas substituídas; cenário insert-once + validador `[PASS]` (numeração a partir de **34**); catálogo inalterado em 31. |
| **P2** | RPCs `observacao_*` `SECURITY INVOKER` com `search_path` fixo e `EXECUTE` só `service_role`; gate por operação com allowlist **fechada** (operação desconhecida ⇒ raise); `expected_version` obrigatório com `FOR UPDATE` **antes** da comparação (D10); `operation_id` + `payload_hash` server-side com idempotência dupla (D6); eventos na **mesma** transação; matriz de estados (D11/D12) e fail-closed por ausência provados por SQL. |
| **P3** | `observation` **fora** de `TIPOS_RECURSO_NAO_SOBERANOS` e reconhecido como recurso soberano; `carregarRecurso` real; `alvosPermitidos` por relação; matriz capability × estado com **fonte única**; **tabela `capability → bundle/perfil existente → escopo` documentada neste documento (D15 item 3)**; `admin` permanece sem `observation.*` (guarda preservada); **teste de ALLOW no caminho de produção** (nunca `localWorld`); `authorizationPolicy.test.ts:508-518` **invertido** (D5); RLS de P1 confirmada. |
| **P4** | Edge `observacoes` com o trio `index`/`core`/`contrato` e o contrato transportável único; allowlist **estrita** de chaves por operação (sem campos de autoria/tenant/estado); adapter fail-closed cobrindo os três caminhos (`error`, `data.error`, `data.ok !== true`) e todos os `CodigoPublico`; guardas de grafo de imports (sem `.rpc(` no cliente, sem `SERVICE_ROLE_KEY`). |
| **P5** | `observacaoStorage.ts` com **barreira que lança** nas três mutações e leitura local fora do caminho funcional (D13); `geradorDadosTeste` sem escrita na chave legada; telas e consumidores de arrasto (PDF, MinhaAvaliação, KPIs) lendo do soberano; listas de exceção de `estruturaUiSeguranca.test.ts` ajustadas; resíduo morto resolvido; **sem dual-read**. |
| **P6** | Matriz SQL integrada + **concorrência real entre duas sessões** (edição e comunicação concorrentes, perdedora em `CONFLICT` **depois** de esperar o lock); cross-tenant, IDOR, membership revogada, perfil inativo, capability ausente e relação ausente; idempotência e rollback; regressões P1–P8/F5-06/F5-07; relatório de gates executados × não executados (molde `docs/F5-09-p9-matriz-integrada.md`); **certificação da F5-11**. |

### 17.2 Método desta rodada (DEV-02 / DEV-03)

**Rodada 1 (`91b9c61`) — reconhecimento + desenho:**

- **Leitura integral** de `src/types/Observacao.ts` e `src/services/observacaoStorage.ts`; leitura das
  partes relevantes de `ObservacoesColaborador.tsx`, `ColaboradorDetalhePage.tsx`,
  `MinhaAvaliacaoDetalhePage.tsx`, `exportarAvaliacaoPdf.ts`, `filtroObservacoesPorCiclo.ts`,
  `ordenacaoPorCiclo.ts`, `cicloAvaliacaoStorage.ts`, `resetBaseDesenvolvimento.ts`,
  `authorizationPolicy.ts`, `ResourceContext.ts`, `resourceContextReal.ts`, `reais.ts`,
  `mundoFuncional.ts`, `capabilityTarget.ts`, `catalogoCapabilities.ts`, `Capability.ts`.
- **Varredura por conteúdo** de `observac`, `Observac`, `POSITIVA|NEUTRA|NEGATIVA`, `comunicado`,
  `observation.`, `TIPOS_RECURSO_NAO_SOBERANOS` em `src/`, `supabase/`, `docs/` e `.github/`.
- **Varredura dos `create table`** das 35 migrations: **nenhuma** tabela de observação; levantamento
  das tabelas reutilizáveis (§6) e das trilhas append-only existentes.
- **Duas frentes independentes de auditoria read-only** (autorização do domínio; infraestrutura
  server-side reutilizável), com declaração explícita do que **não** foi encontrado.
- **Verificação de fato histórico:** `git log --diff-filter=D` provou que
  `impactoCorrecaoPeriodoCiclo.ts`/`correcaoPeriodoCicloService.ts` foram removidos em `4868ca7`
  (F5-10 P6) — a nota do §3.5 da F5-10 estava desatualizada para observações.

**Rodada 2 (esta revisão) — fechamento arquitetural do P0:**

- **Fechamento de Q1–Q16 = A** por auditoria GPT que aprovou o desenho, registrado como **D1–D16**
  (§15) com preservação do histórico das alternativas descartadas e tabela de rastreabilidade
  Q# → D# (§15.10).
- **Revisão transversal** para eliminar contradições decorrentes do fechamento: modelo de dados
  (§7.1–§7.3, com os limites de D16 e as CHECKs de coerência de D7/D8), matriz de autorização (§8,
  agora normativa, com o invariante de autoria de D5 e a concessão de D15), segurança (§9, com
  T19 novo), dados legados e cutover (§10–§11, D13), decomposição (§13) + **dependências entre Ps**
  (§13.1, nova), riscos (§16) e **critérios de aceite** (§17.1, com critério por fase).
- **Nenhuma** alteração funcional: **0** migration, **0** SQL, **0** RPC, **0** RLS, **0** capability,
  **0** Edge, **0** UI, **0** teste funcional.

**Ambas as rodadas (DEV-02 / DEV-03):**

- **Nenhuma** execução pesada: **0** `npm test`, **0** `npm run build`, **0** `npm run lint`,
  **0** `db reset`, **0** chamada ao Supabase local, **0** RPC, **0** migration. Não houve alteração
  funcional, logo uma bateria pesada não produziria informação nova (DEV-03: "uma execução deve
  produzir nova informação"); executadas apenas validações leves relevantes, incluindo
  `git diff --check`.
- **1 lote privilegiado por rodada**: `git add` + `commit` + `push` da documentação (DEV-02 —
  operações agrupadas).
- **Nenhuma** repetição de gate, **nenhuma** elevação de sandbox, **nenhum** `gh`/PAT/credencial,
  **nenhum** merge.
- **Tempo:** não medido de forma confiável nesta rodada (declarado, não estimado).
- **Usage/custo:** não observável a partir do ambiente — não reportado.

---

# REGISTRO DE IMPLEMENTAÇÃO (não altera D1–D16)

## 18. P1 — schema, trilha auditável e substituição dos guards invertidos (IMPLEMENTADA)

> **Rastreabilidade:** a P1 é entregue sob a **Issue #240** (`F5-11/P1 — Schema soberano, audit trail
> e substituição dos guards invertidos`), cuja **Issue-mãe é a #238** (F5-11). Esta é a issue que
> **governa** a P1 e que o PR correspondente deve **fechar** (`Closes #240`); a #238 **permanece
> aberta** até a P6. Os artefatos SQL citam `F5-11 P1 (Issue #238)` por já estarem **validados byte a
> byte** (bateria de banco 47/47 verde) e **não são reeditados** apenas para trocar o número da
> issue — a evidência vale mais que a referência cosmética.
> **Natureza:** registro do que foi efetivamente construído na P1. **Não altera nenhuma decisão
> D1–D16** e **não antecipa P2–P6**. Onde a implementação materializou algo que o esboço do §7.2 não
> listava literalmente, isso está **declarado** em §18.3.

### 18.1 Entregue

| Artefato | Conteúdo |
|---|---|
| `supabase/migrations/20260929000000_f5_11_p1_observations_schema.sql` | preflight fail-closed; as duas tabelas do §7.2 com o conjunto completo de constraints; índice de alvo parcial; trigger `updated_at`; **trigger de imutabilidade estrutural (D4)**; trilha append-only com os **3 triggers (D6)**; **RLS deny-by-default integral (D9)**; ACL mínima; guarda final fail-closed |
| `supabase/validacao/34-cenario-f5-11-p1.sql` | fixture isolada (prefixo `fd`): 2 orgs, 2 identidades com membership ativa, 3 colaboradores, 3 ciclos (Alfa `ATIVO`, Alfa `ENCERRADO`, Beta `ATIVO`), 4 observações (1 comunicada, 1 excluída com motivo, 1 em ciclo encerrado) e 6 eventos; guarda insert-once |
| `supabase/validacao/35-validar-f5-11-p1.sql` | validador por blocos A–K com `[PASS]`/`[FAIL]` (preflight, estrutura, CHECKs comportamentais, D2, FKs cross-tenant, D4, D6, D9, idempotência, fronteira da P1/D15, higiene) |
| `.github/workflows/ci.yml` | passos da P1 inseridos **antes** das regressões F5-06/F5-07 |

### 18.2 Guards invertidos: o padrão incorreto e a substituição

**Padrão incorreto encontrado (a mesma falha em três validadores):** a F5-11 era protegida por
**proibição absoluta** — qualquer tabela ou função cujo nome casasse com `%observac%`/`%observation%`
reprovava o CI. Esse guarda **não podia sobreviver** à P1, e **removê-lo** teria deixado o anti-escopo
sem cobertura. A substituição aplica a **mesma doutrina já usada quando a própria F5-10 chegou**
(proibição → **LISTA FECHADA**), de forma transversal, para não deixar variantes do mesmo defeito:

| Arquivo | Antes | Depois |
|---|---|---|
| `supabase/validacao/15-validar-f5-09-p9.sql` | contagem de tabelas e de funções `%observa%` devia ser **0**; bloco (f) não excluía tabelas de observação | **lista fechada**: `v_tabelas_observacoes_p1` (as 2 do contrato) e `v_funcoes_observacoes_p1` (**vazio** até a P2); bloco (f) exclui as tabelas legítimas |
| `supabase/validacao/30-validar-f5-10-p7.sql` | idem, com a mensagem "F5-11 intocada" | lista fechada com as 2 tabelas + **zero** funções + prova de que as 2 tabelas **existem** |
| `supabase/validacao/02-validar-f4-08.sql` | inventário D16, categoria "fechada", classificação de ACL e **contagens fixas** (49 tabelas; 26 fechadas) sem as tabelas de observação | as 2 tabelas entram em `v_closed`, no inventário `v_todos`, na classificação D16 e no bloco **deny-by-default integral**; contagens **49 → 51** e **26 → 28** |

**Nenhum** guarda foi enfraquecido ou removido: as três listas continuam reprovando qualquer objeto
de observação **fora** delas, e a P2 terá de **ampliar a lista de funções explicitamente** para
introduzir as RPCs `observacao_*`.

### 18.3 Declarações explícitas (desvios do esboço, sem alterar decisão)

1. **Integridade referencial completa (declarada).** O esboço do §7.2 listava colunas, CHECKs e uma
   FK composta; a implementação materializou o **conjunto completo de FKs** do molde normativo do D6
   (`cycle_events`/`evaluation_goal_events`): `organizations`, FKs compostas de tenant para
   `evaluation_cycles`, `collaborators` e `user_organization_memberships`, e FKs de perfil do ator —
   inclusive para quem **comunicou** e para quem **excluiu**. Motivo: o próprio checklist do
   repositório exige `FK/organization_id` coerente em tabela tenant-specific e o D6 referencia
   explicitamente aquele molde; sem elas o cross-tenant seria possível **na trilha** e o histórico
   poderia apontar para ator inexistente. Nenhuma coluna nem CHECK do contrato foi alterado.
2. **Imutabilidade estrutural (D4) por trigger, e não apenas por contrato de forma.** O D4 é
   normativo; a P1 o materializa no banco (resistente a bug de RPC e a privilege drift), sem limitar
   os campos mutáveis do contrato.
3. **A P1 não impõe estado de ciclo no schema.** A regra "mutação só em `ATIVO`" (D12) é **gate
   funcional** da P2/P3 — a fixture inclui, de propósito, uma observação em ciclo `ENCERRADO` para
   provar que o schema a aceita, deixando a fronteira explícita.
4. **`version` não é incrementada pela P1.** O `version + 1` pertence à operação soberana da P2
   (D10); a P1 apenas garante `version >= 0`.

### 18.4 Fronteira da P1 respeitada

**Nenhuma** RPC `observacao_*`, **nenhuma** função funcional de observação, **nenhuma** policy de
leitura, **nenhuma** capability nova, **nenhum** bundle/role novo, **nenhuma** concessão de
`observation.*`, **nenhum** Edge, **nenhum** cliente, **nenhum** cutover, **nenhuma** migração de
`localStorage`, **nenhum** advisory lock. O validador da P1 **falha** se qualquer um desses objetos
aparecer.

### 18.5 D15 continua BLOQUEANDO a P3 (estado inalterado)

`observation.*` continua **sem concessão alguma**; o bundle `admin` continua com **9** capabilities e
**sem** `observation.*` (a guarda `02-validar-f4-01.sql:563-578` foi **preservada**, não relaxada).
**Antes do início da P3** este documento deve receber a tabela
**`capability → bundle/perfil existente → escopo`** (D15 item 3). **A P1 não antecipa essa decisão e
não cria role, bundle ou perfil.**

### 18.6 Correção factual descoberta na execução da P1 (não altera D15)

A execução do validador da P1 contra o banco **real** (após `db reset`) provou que o estado de
concessão não era o que a nota anterior do §8 supunha: existem **três** roles de sistema —
`admin`, **`metas_dono`** e **`metas_aprovador`** —, sendo as duas últimas criadas de forma
**aditiva e idempotente pela migration da F5-10 P4** (`20260925000000:2314-2332`) como o mecanismo de
concessão explícita do D7 da F5-10. Elas **persistem** após `db reset` e **não** são fixture de
validação. O §8 foi **corrigido** e a conclusão sobre D15 foi **reforçada**, não relaxada:

- existe **precedente normativo** para conceder capability por **perfil de sistema por domínio**
  (foi assim que a F5-10 concedeu `goal.*`);
- `metas_dono`/`metas_aprovador` são perfis de **metas** e **não servem** para `observation.*`;
- `admin` continua **proibido** de receber `observation.*`;
- portanto **continua não havendo** perfil existente adequado, e a identificação exigida pelo D15
  item 3 permanece **obrigatória e bloqueante** para a P3 — agora com o mecanismo candidato
  (**perfil de sistema por domínio**) já **precedenciado** e tendo de ser **decidido e nomeado
  explicitamente**, nunca criado em silêncio.

> **Efeito na P1:** nenhum. A P1 **não** cria role, bundle nem perfil — o validador da P1 **falha**
> se o conjunto nomeado de roles de sistema deixar de ser exatamente
> `admin` + `metas_aprovador` + `metas_dono`.

---

## 19. P1.1 — coerência estrutural perfil↔membership (IMPLEMENTADA · Issue #242)

> **Rastreabilidade:** entregue sob a **Issue #242** (`F5-11/P1.1 — Correção do finding Codex`),
> mãe **#238**. **Não altera D1–D16**, **não resolve D15** e **não antecipa P2/P3**.

### 19.1 Finding MEDIUM do Codex (auditoria independente da P1)

As FKs da P1 provam, **separadamente**, que o perfil existe
(`fk_evaluation_observations_author_profile` → `user_profiles`) e que a membership existe **no
tenant** (`fk_evaluation_observations_author_membership` → `user_organization_memberships
(id, organization_id)`). **Nenhuma** delas prova que a membership informada pertence ao **perfil**
informado. Numa organização com perfil A → membership A e perfil B → membership B, uma escrita
técnica podia persistir **`author_user_profile_id = A` com `author_membership_id = B`** — autoria
incoerente, sem que constraint alguma reclamasse. O mesmo valia para `comunicado_por_*`,
`excluida_por_*` e `actor_*` da trilha.

### 19.2 Causa-raiz e mecanismo adotado

**Causa-raiz:** o par (perfil, membership) é uma relação de **identidade**, não de tenant. As FKs
cobrem existência e tenant; a coerência identitária não tinha garantia estrutural — e **não podia**
ser expressa por FK composta, porque exigiria uma **chave candidata nova** em
`user_organization_memberships (id, user_profile_id)` (a tabela só possui `(id, organization_id)`)
e, para o vínculo, em `membership_collaborator_links` (só possui `unique (membership_id)`); criar
chave nova ali seria **alterar contrato fechado de outra fase** (F4-01/F4-02).

**Mecanismo (migration corretiva ADITIVA `20260930000000_f5_11_p1_1_coerencia_identidade_observacoes.sql`;
a migration da P1 **não** é editada retroativamente):** duas funções `SECURITY INVOKER` com
`search_path = public` + dois gatilhos `BEFORE ROW` fail-closed, cobrindo os **quatro pares** —
`author_*`, `comunicado_por_*`, `excluida_por_*` (linha, `BEFORE INSERT OR UPDATE OF …`) e `actor_*`
(trilha, `BEFORE INSERT`).

**Separação de classes de erro (preservada):** valor **ausente** → `NOT NULL`/CHECK do contrato
(23502/23514); referência **inexistente ou cross-tenant** → FK composta (23503, garantido porque
**todo** lookup do gatilho é filtrado por `organization_id`); referência existente **incoerente** →
`P0001`. O gatilho só julga **coerência entre valores efetivamente informados**.

### 19.3 `author_collaborator_id` — regra determinada pelo modelo, não inventada

O D3 define o campo como **derivado do vínculo** e nulo quando o ator não tem vínculo. A derivação
canônica é **`public.resolver_collaborador_vinculado(profile, org)`** (F5-02, endurecido em
`20260909000000_f5_02_hardening_resolver_collaborador.sql`), que exige **cumulativamente** as **três**
condições: `user_profiles.status = 'active'`, `user_organization_memberships.status = 'active'` e
`membership_collaborator_links.status = 'active'` (vínculo `disabled` é histórico e **não** resolve —
Q6 = B). Portanto a coerência exigida é: **quando informado**, `author_collaborator_id` tem de ser o
colaborador **reconhecido pelo resolvedor** para o perfil informado, na membership informada e no
tenant da linha. É exatamente o que o gatilho impõe — **paridade INTEGRAL com o resolvedor** (o *mesmo*
join, ancorado na membership informada), provada no validador (§19.5, bloco B, inclusive B4/B5) e
exigida negativamente no bloco D (D4/D5). Nulo continua legítimo (ator sem vínculo): a completude da
derivação é responsabilidade da operação soberana da P2, não deste invariante.

### 19.4 Ajuste obrigatório na fixture da P1 (declarado)

A fixture `34-cenario-f5-11-p1.sql` informava `author_collaborator_id` **sem** existir o
`membership_collaborator_links` correspondente — ou seja, era ela própria incoerente com o D3. A
P1.1 **acrescentou os dois vínculos ativos** (Alfa e Beta) e passou a exigi-los na consistência da
fixture. Isso **afeta materialmente a evidência de 34/35**, que por isso foi **reexecutada** (e
segue verde: `34` 1 PASS, `35` 11 PASS) — as demais 40 etapas da bateria **não** foram afetadas
(nenhum outro validador toca as tabelas de observações e **nenhum validador existente foi
editado**).

### 19.5 Testes intra-tenant adicionados (o teste que faltava)

`36-cenario-f5-11-p1-1.sql` (prefixo `fe`): **uma** organização com **cinco** identidades, cada uma
com a **sua** membership **na mesma organização** e o **seu** colaborador vinculado — A e B com perfil
e membership **ativos** e vínculo **ativo**; C com vínculo **`disabled`**; **D com membership
`disabled` e vínculo ATIVO** (a metade ausente do *finding*); **E com perfil `disabled`** e membership
e vínculo ativos. As três negativas cobrem a **matriz integral** das três condições do resolvedor.
`37-validar-f5-11-p1-1.sql` (blocos A–H, **8 PASS**):

| Bloco | Prova |
|---|---|
| A | preflight: fixture intra-tenant, mecanismo instalado (INVOKER + `search_path`), `tgtype` correto dos dois gatilhos, catálogo 31, `admin` 9 sem `observation.*`, D15 intacto, nenhuma RPC |
| B | **paridade integral**: o resolvedor canônico resolve A→colaborador A e B→colaborador B e **não** resolve **nenhuma** das três negativas — C (vínculo `disabled`), D (membership `disabled` com vínculo ativo = o *finding*) e E (perfil `disabled`) — logo a regra do gatilho **é** a do resolvedor |
| C | **negativos intra-tenant dos 4 pares**: autor, comunicado, exclusão e ator do evento recusam **perfil A + membership B** com **P0001** (e nenhuma tentativa persiste linha) |
| D | **negativos de `author_collaborator_id`**: colaborador de outra membership (2 casos), vínculo **`disabled`**, **membership `disabled` com vínculo ATIVO (D4 — o *finding*)** e **perfil `disabled` (D5)** recusados com **P0001** e com verificação da **mensagem** (D4/D5); nenhuma tentativa persiste linha (D6) |
| E | **negativos no UPDATE** (a linha é mutável): marcar comunicado, excluir e trocar o colaborador — com **verificação da mensagem**, provando que quem recusou foi o invariante de **coerência** e não o gatilho de **imutabilidade** do D4 |
| F | **positivos**: A+A (+colaborador A), B+B (+colaborador B), `author_collaborator_id` **nulo**, evento com ator coerente e as transições legítimas de exclusão e revogação |
| G | **classes de erro** (par incompleto → 23514; referência inexistente → 23503) e invariantes **D4**, **D6** e **D9** intactos |
| H | higiene (nenhum resíduo de prova) |

### 19.6 Fronteira e estado

**Nenhuma** RPC `observacao_*`, nenhuma policy, nenhum grant, nenhuma capability nova, nenhum
`SECURITY DEFINER`, nenhuma role/bundle/perfil, nenhuma alteração de Edge/UI/cliente e nenhuma
migração de `localStorage`. **D15 continua BLOQUEANDO a P3** (`observation.*` sem concessão, `admin`
com 9 e sem `observation.*`). **P2 e P3 não iniciadas.**

### 19.7 Defeitos encontrados na própria execução (registrados, sem ampliar escopo)

1. **Corrigido neste artefato:** `v_faltando := v_faltando || '<literal>'` com **vírgula** no literal
   é resolvido pelo PostgreSQL como concatenação de **arrays** → `22P02` em vez do diagnóstico
   pretendido. As 10 ocorrências da migration da P1.1 receberam cast explícito `::text`.
2. **Corrigido neste artefato:** o resolvedor canônico chama-se
   **`resolver_collaborador_vinculado`** (híbrido: a **tabela** usa "collaborator" e a **função** usa
   "collaborador"), e não `resolver_collaborador_vinculado`. A grafia dos artefatos da P1.1 foi
   fixada por **igualdade de hash** com o identificador do banco (`md5 = a7539481ed2bbe7e8003cd2febef8d18`).
3. **Não corrigido (fora do escopo, apenas registrado):** o padrão do item 1 é **pré-existente** no
   repositório, em ramos que só executam em caso de falha — `20260922000000_f5_10_p1_goals_schema.sql:68,76,794`,
   `20260929000000_f5_11_p1_observations_schema.sql:89,97` e `02-validar-f5-09.sql:1257-1266`. Nesses
   pontos o guard **continua fail-closed** (aborta), mas abortaria com `22P02` em vez da mensagem
   diagnóstica pretendida. Editar retroativamente a migration da P1 contrariaria a doutrina de
   migrations e invalidaria evidência verde; fica registrado para atividade própria.

### 19.8 Correção pré-merge do PR #243 (auditoria Codex)

A auditoria **Codex** do **PR #243** (**REPROVADO**, 1 *finding* **MEDIUM**, Issue #242) apontou que a
verificação de `author_collaborator_id` exigia apenas `membership_collaborator_links.status = 'active'`
e **não** `user_organization_memberships.status = 'active'`, divergindo de
`resolver_collaborador_vinculado`: a combinação `membership disabled + link active` era **aceita**,
embora o resolvedor soberano **não** reconheça esse colaborador (§19.3).

**Correção mínima aplicada** — na **mesma** migration, que ainda **não está versionada** no PR aberto
(por isso foi editada no lugar, sem migration corretiva nova): a consulta passou a repetir **o mesmo
join do resolvedor** — perfil do ator **ATIVO** (`user_profiles.status = 'active'`), membership
informada **ATIVA** (`user_organization_memberships.status = 'active'`) e vínculo **ATIVO**
(`membership_collaborator_links.status = 'active'`) — ancorado na membership informada e no tenant da
linha. Sem redesenho do mecanismo, sem alterar os **quatro pares** já aprovados e sem ampliar escopo.

**Teste focado que faltava (obrigatório):** o bloco **D** do validador ganhou **D4** (membership
`disabled` + vínculo `active` + colaborador correto do vínculo ⇒ **recusado** com **P0001** e com a
**mensagem** do invariante de coerência, não a do D4/de FK) e **D5** (perfil `disabled`); **D6** prova
que **nenhuma** das tentativas persistiu linha. O bloco **B** ganhou **B4/B5**, provando que o
**resolvedor canônico também não resolve** D e E — a premissa dos negativos. A fixture `36` ganhou as
identidades **D** e **E**, e o preflight (A1b) passou a exigir a presença das três negativas.

## 20. P2 — RPCs soberanas `observacao_*` (IMPLEMENTADA · Issue #244)

> **Rastreabilidade:** entregue sob a **Issue #244** (`F5-11/P2 — RPCs soberanas observacao_*`),
> mãe **#238**, base `e7aecf27532948d21b97d04d9c15aa7478442cca`. **Não altera D1–D16**, **não
> resolve o D15** e **não antecipa P3**. A P1 e a P1.1 seguem intactas.

### 20.1 Superfície entregue

`supabase/migrations/20260931000000_f5_11_p2_observacoes_rpc.sql` — **14 funções `SECURITY
INVOKER`** com `search_path = public` e `EXECUTE` **somente `service_role`**: **8 RPCs** e **6
helpers** internos. Nenhuma policy, nenhum grant ao cliente, nenhuma capability/role/bundle novo,
nenhum `SECURITY DEFINER`.

| RPC | Assinatura (parâmetros) | Derivado soberanamente |
|---|---|---|
| `observacao_criar` | `(p_organization_id, p_cycle_id, p_collaborator_id, p_tipo, p_texto, p_actor_user_profile_id, p_operation_id)` | `id`, `author_user_profile_id`, `author_membership_id`, `author_collaborator_id`, `version = 0`, `comunicado = false`, carimbos, evento `CRIADA` |
| `observacao_editar` | `(p_observation_id, p_organization_id, p_tipo, p_texto, p_comunicado, p_expected_version, p_actor_user_profile_id, p_operation_id)` | autoria conferida, carimbos do comunicado, `version + 1`, evento `EDITADA` (+ `COMUNICADO`/`COMUNICACAO_REMOVIDA` na transição) |
| `observacao_definir_comunicado` | `(p_observation_id, p_organization_id, p_comunicado, p_expected_version, p_actor_user_profile_id, p_operation_id)` | carimbos do comunicado, `version + 1`, evento da transição |
| `observacao_excluir` | `(p_observation_id, p_organization_id, p_motivo, p_expected_version, p_actor_user_profile_id, p_operation_id)` | `excluida_em`, `excluida_por_*`, `motivo_exclusao`, `version + 1`, evento `EXCLUIDA` (motivo = `reason`) |
| `observacao_revogar` | `(p_observation_id, p_organization_id, p_motivo, p_expected_version, p_actor_user_profile_id, p_operation_id)` | carimbos de exclusão limpos, `version + 1`, evento `REVOGADA` |
| `observacao_obter` | `(p_observation_id, p_organization_id, p_actor_user_profile_id)` | projeção com visibilidade soberana (autor, relação ou SELF-comunicada) |
| `observacao_listar_por_escopo` | `(p_organization_id, p_actor_user_profile_id, p_escopo, p_organizational_unit_id, p_data)` | alvos por `resolver_alvos_escopo` (allowlist fechada `SELF`/`DIRECT_REPORTS`/`DESCENDANTS`) |
| `observacao_historico` | `(p_observation_id, p_organization_id, p_actor_user_profile_id)` | trilha append-only (mesma visibilidade de `obter`) |

**Helpers:** `f5_11_ator_efetivo_observacao` (amarra o ator a `auth.uid()`), `f5_11_ator_valido_observacao`
(allowlist fechada + capability efetiva), `f5_11_vinculo_observacao_do_ator` (SELF único),
`f5_11_relacao_observacao_do_ator` (DIRECT_REPORTS ∪ DESCENDANTS), `f5_11_status_vigente_do_colaborador`
(D11) e `f5_11_exigir_autorizacao_observacao` (gate funcional único).

### 20.2 Identidade (D3) e gates soberanos

- **`auth.uid()` é a raiz:** `f5_11_ator_efetivo_observacao` **amarra** o ator informado pela
  fronteira ao JWT — com JWT presente, divergência ⇒ `F5_11_FORBIDDEN` (override de identidade
  negado). Campos de autoria **nunca** vêm do corpo (D3/D4 + regra da P1.1, com paridade INTEGRAL
  com `resolver_collaborador_vinculado`).
- **Capability:** mapa **FECHADO** operação → capability — CRIAR→`observation.create`;
  EDITAR/COMUNICAR/DESCOMUNICAR/REVOGAR→`observation.edit`; EXCLUIR→`observation.delete`;
  OBTER/HISTORICO/LISTAR_ESCOPO→`observation.read`; operação desconhecida ⇒ **raise** (fail-closed).
  A capability vem sempre do mapa, nunca do chamador, e é conferida em
  `resolver_capabilities_efetivas` (F4-01/F5-04).
- **Author gate (D5):** somente o **autor persistido** (`author_user_profile_id = ator`) edita,
  comunica, descomunica, exclui e revoga — inclusive contra outro ator do **mesmo** tenant.
- **Relation gate:** o alvo tem de pertencer a `DIRECT_REPORTS` ∪ `DESCENDANTS` do colaborador do
  ator (F4-02, resolvido na data); **SELF não cria observação sobre si**.
- **Cycle gate (D12):** toda mutação exige ciclo **`ATIVO`** lido da linha soberana; a leitura
  histórica permanece nos demais estados.
- **Collaborator gate (D11):** matriz do §20.3.

### 20.3 Matrizes de decisão (mínimas, provadas por SQL)

**D11 — estado do colaborador** (fonte soberana `collaborator_status_periods`, meio-aberto):

| operação | `active` | `leave` | `inactive` | status não resolvido |
|---|---|---|---|---|
| criar | PERMITE | PERMITE | **NEGA** (`F5_11_CONFLICT`) | **NEGA** (`F5_11_FORBIDDEN`, fail-closed) |
| marcar comunicado | PERMITE | PERMITE | **NEGA** (`F5_11_CONFLICT`) | **NEGA** (`F5_11_FORBIDDEN`) |
| editar / descomunicar / excluir / revogar | PERMITE (sem gate de status — §8 linhas 5/7/8/9) | idem | idem | idem |

**D12 — estado do ciclo:** `ATIVO` ⇒ mutação permitida (com os demais gates);
`PLANEJADO`/`ENCERRADO`/`CANCELADO` ⇒ `F5_11_CONFLICT` nas cinco mutações; `obter`/`listar`/`historico`
seguem permitidos em qualquer estado.

**Tenant × autoria:** observação/alvo de outro tenant ⇒ `F5_11_NOT_FOUND` **indistinguível**; outro
ator do mesmo tenant ⇒ `F5_11_FORBIDDEN` (autoria).

**D10 — concorrência:** `expected_version` + `SELECT … FOR UPDATE` **sem advisory lock**; replay
idêntico (`operation_id` + `payload_hash`) devolve o **mesmo** resultado (idempotência dupla: caminho
rápido + sob o lock); hash divergente ⇒ `CONFLICT`; a criação é idempotente pela unicidade
`(organization_id, operation_id)` com **savepoint** (retry concorrente não deixa resíduo).

### 20.4 Eventos por operação (D6/D7)

| operação | evento(s) | observações |
|---|---|---|
| criar | `CRIADA` | `after` com tipo/texto/ciclo/colaborador/versão; `before` nulo |
| editar (conteúdo) | `EDITADA` | before/after completos (preserva o "texto anterior") |
| editar (com transição de comunicado) | `EDITADA` **+** `COMUNICADO`/`COMUNICACAO_REMOVIDA` | o sub-evento usa `operation_id` **derivado** (`f5_10_derivar_operation_id`) |
| definir comunicado | `COMUNICADO`/`COMUNICACAO_REMOVIDA` | ator e instante **do servidor** |
| excluir | `EXCLUIDA` | `reason` = motivo obrigatório |
| revogar | `REVOGADA` | `reason` = motivo obrigatório; a trilha preserva `EXCLUIDA` |

### 20.5 Declarações explícitas (desvios do esboço, sem alterar decisão)

1. **D11 é avaliado no gate ANTES da relação.** Fundamento estrutural: colaborador `inactive` não
   possui occupation vigente (invariante do F3-05), logo **jamais** resolveria relação alguma; sem
   essa precedência a recusa do D11 não seria atribuível ao mecanismo pretendido.
2. **`observacao_editar` carrega a definição completa** (§7.5: tipo/texto/comunicado) e, quando o
   comunicado transiciona, grava **`EDITADA` e** o evento dedicado (§7.7) — o sub-evento recebe
   `operation_id` derivado porque a trilha tem `unique (organization_id, operation_id)`.
3. **`observacao_listar_por_escopo`:** escopos **fechados** (`SELF`, `DIRECT_REPORTS`,
   `DESCENDANTS`); `SELF` devolve somente `comunicado and not excluida` (§8 linha 2); os escopos de
   gestão devolvem as **não excluídas** dos alvos resolvidos; sem paginação (P2).
4. **Caminho ALLOW sem concessão:** como o D15 mantém `observation.*` sem concessão, o validador
   exercita o ALLOW com uma concessão **transitória** dentro de `begin`/`rollback` — o bloco D prova
   que **nada** persistiu (zero concessão, nenhuma role de teste, zero linha/evento).

### 20.6 Evidência

- **Gate focado:** `34` 1 PASS, `35` 11 PASS, `36` 1 PASS, `37` 8 PASS, `38` 1 PASS, **`39` 7 PASS**
  (blocos A, B, C, C10, C11, D e E).
- **Bateria completa na ordem do CI: 52/52 etapas verdes**, incluindo as **duas concorrências
  reais** (A=0 / B=0) e o `39` verde **no ambiente em que a fixture antiga `f2` (F5-10 P4) está
  presente**.
- Provas de ambiente: **8** funções `observacao_*`, **zero** concessão de `observation.*`, `admin`
  com 9 e sem `observation.*`, **zero** resíduo `_mut_*`.

### 20.7 Fronteira e estado

**D15 continua BLOQUEANDO a P3** (nenhuma concessão de `observation.*`, nenhuma role/bundle/perfil
criado, `admin` permanece sem `observation.*`). **A P3 não foi iniciada.** Nenhuma UI/Edge/cliente/
cutover/localStorage foi tocado (P4/P5 não antecipadas) e **nenhuma migração de `localStorage`** foi
feita (D13). A dívida diagnóstica pré-existente `22P02` **não foi tocada**.

### 20.8 Defeitos encontrados na própria execução (registrados, sem ampliar escopo)

Todos de **andaime de teste/guarda** (nenhum de lógica das RPCs), corrigidos em rodada consolidada:

1. a guarda final da migration comparava a superfície `observacao_*` por **texto** de assinatura
   (`pg_get_function_identity_arguments`) — formato não é contrato; passou a comparar **OIDs**
   (`to_regprocedure`);
2. **vírgula final** nas listas fechadas injetadas em `15`/`30`/`35` (erro de script de edição);
3. fixture com `valid_to < valid_from` (CHECK do F3-05) e validade fora da posição/unidade;
4. comparação `uuid ~~ text` na consistência da fixture;
5. **`$$` aninhado**: o corpo da função de injeção encerrava o bloco `DO` que o continha (artefato
   movido para o nível da transação, com tag `$fn$`);
6. expectativa de trilha incompleta (a edição com transição grava **dois** eventos);
7. teste do gate passava a organização em vez de `NULL`;
8. **colisão de identificadores de fixture**: o prefixo `f2` da P2 era o mesmo da F5-10 P4
   (`25-cenario-f5-10-p4.sql`, org `f2a…-a1`); o guard insert-once usava só o id e **pulou a fixture
   inteira em silêncio** (o bloco A do `39` contou dados alheios: 7 colaboradores / 3 ciclos).
   Correção: prefixo **`f5b2`** (família verificada livre no repositório), guard identificado pelo
   **nome** da organização, **erro explícito de colisão** e contagens por **prefixo** de id.

## 21. P3 — autorização, concessão (D15) e scope soberano (IMPLEMENTADA · Issue #246)

> **Rastreabilidade:** base `0f7bcf625052ad3c07113962cfd8997cffb9245b`, mãe **#238**. A decisão
> **D15** foi registrada no §8 **antes** do código funcional (item 3 do próprio D15).

### 21.1 Concessão explícita (D15)

`supabase/migrations/20260932000000_f5_11_p3_authorization_observacoes.sql` cria o **perfil de
sistema funcional `observacoes_gestor`** (`is_system = true`, `organization_id` nulo) com
**EXATAMENTE** as 4 capabilities canônicas (`observation.read/create/edit/delete`) e guarda
fail-closed do conjunto exato — molde normativo da F5-10 P4 (`20260925000000:2265-2399`).
**Não** cria capability nova (catálogo **31**), **não** toca `admin`/`metas_dono`/`metas_aprovador`,
**não** cria policy nem privilégio de cliente e **não** semeia assignments: a atribuição é
configuração administrativa server-side pelo caminho soberano existente (`conceder_acesso_role` +
linha em `access_role_assignment_scopes`), como nas fases F4-02/F4-08/F5-07/F5-08.

### 21.2 Scope é enforcement real (não metadado)

O gate `f5_11_exigir_autorizacao_observacao` e a RPC `observacao_listar_por_escopo` foram
**reescritos por `create or replace`** (a migration da P2 **não** é editada) e passam a exigir
**cumulativamente**: (1) **capability** efetiva (allowlist fechada, `auth.uid()` amarrado);
(2) **SCOPE** do único resolver soberano escopado (`resolver_capabilities_escopos_efetivas`, F4-02 —
assignment **ativa** *e* scope **ativo**): mutações e leitura de terceiros exigem
`scope_type ∈ {DIRECT_REPORTS, DESCENDANTS}`; um assignment **sem** scope tem a capability (resolver
sem scope) mas **não** passa o gate — é essa assimetria que prova que o **scope decide** (validador
`41`, bloco C); (3) **RELAÇÃO** estrutural (DIRECT_REPORTS ∪ DESCENDANTS) — o scope **não** substitui
a relação (bloco G); (4) **AUTORIA** D5 e **estado** D11/D12 como na P2. Helper novo:
`f5_11_ator_tem_escopo_observacao`.

**Exceção normativa declarada:** a **leitura SELF-comunicada** (§8 linha 2 / D7) é a única operação
sem exigência de scope de gestão (regra específica do domínio); por isso não há scope `SELF` no
bundle padrão e `ORGANIZATION` não o satisfaz.

### 21.3 Fronteira, regressões e cliente

- Guards das fases anteriores **invertidas explicitamente** (nunca removidas): `35` (A3/J5 +
  conjunto de roles), `37` (D15) e `39` (A5/D) passaram de “zero concessão de `observation.*`” para
  “**exatamente 4**, todas em `observacoes_gestor`, zero em `admin`/`metas_*`”; `15`/`30`/`35`
  ampliaram a **lista fechada de funções** com o helper de scope; `ci.yml` ganhou as duas etapas da
  P3 (após `39`, antes das regressões F5-06/F5-07), sem remover nem enfraquecer etapa alguma.
- **Cliente (Policy Engine):** `observation` saiu de `TIPOS_RECURSO_NAO_SOBERANOS` (lista agora
  **vazia**), passou a tipo **soberano** com identidade UUID em `montarResourceContextSoberano`/
  `motivoAlvoNaoAutorizavel`, ganhou **fonte única** da matriz de estado (`estadoDominioObservacao`)
  e a política espelha **D5** (somente o autor edita/exclui/revoga), com a inversão da expectativa
  legada em `authorizationPolicy.test.ts`. Na fronteira (`contextoAutorizacao`), o probe da
  observação é **fail-closed** até o loader soberano existir (P4) — o `domainState` declarado pelo
  chamador **nunca** é autoridade para recurso soberano (invariante 1 do §8).
- **Atualização da P4 (§22) — nota de estado, sem reescrever o registro da P3:** o loader soberano foi
  implementado; o probe da fronteira passou a ser **derivado da linha carregada** (§22.4) e a matriz de
  estado foi extraída para o módulo Edge-safe `estadoDominioObservacao.ts` (§22.5) para não arrastar
  `import.meta.env`/`localStorage` ao grafo Deno compartilhado pelas Edge Functions. O parágrafo acima
  permanece legível como o registro da P3 **na época**.
- **Não** antecipa P4 (Edge/cliente), P5 (cutover/UI) nem P6 (certificação); nenhuma migração de
  `localStorage` (D13).

### 21.4 Evidência

Gate focado (`34` 1, `35` 11, `36` 1, `37` 8, `38` 1, `39` 7, `40` 1, `41` blocos A–L) e bateria
completa na ordem do CI com as duas concorrências reais — contagens no relatório da entrega. Provas
diretas: perfil com conjunto **exato**; `admin` com 9 e **zero** `observation.*`; `metas_*`
exclusivas de metas; `observation.write` deprecada e **não-concedível** (recusa por trigger da
F5-04); DENY sem grant / **sem scope** / com scope **incompatível**; ALLOW com `DIRECT_REPORTS` e com
`DESCENDANTS` (e `DIRECT_REPORTS` **não** alcançando o descendente); relação ainda obrigatória mesmo
com scope; SELF pela regra do domínio; cross-tenant/IDOR `NOT_FOUND`; escopo fora da allowlist
`INVALID_INPUT`; RLS/ACL intactos (ZERO policy, cliente `42501`); nenhum negativo persistido.

## 22. P4 — Edge e cliente: loader soberano de observações (IMPLEMENTADA · Issue #248)

> **Rastreabilidade:** base `83fb225213501c360660c2968c31f577a8a75373` (`main` pós-P3), mãe **#238**.
> A P4 **não altera SQL**: as migrations da P1/P2/P3 permanecem intocadas. Os gates finais desta fase
> (`npm test`, `npm run build`, `npm run lint`, `git diff --check`) são executados pelo **orquestrador**
> no gate privilegiado — ver o marcador `GATES PENDENTES (orquestrador)` em §22.8.

### 22.1 Escopo entregue

**Edge `observacoes` (trio, molde §6.7):** `supabase/functions/observacoes/index.ts` é o **único** arquivo
que lê `SUPABASE_SERVICE_ROLE_KEY` e cria o cliente privilegiado (`Deno.serve`); `core.ts` é o núcleo
**testável** (sem APIs de runtime, dependências injetadas) e declara a ordem inegociável
identidade soberana (`auth.getUser`) → forma da intenção com **allowlist estrita** → tenant **revalidado**
contra membership ativa → `avaliarGate` por operação → execução privilegiada **sem propagar o JWT**; e
`contrato.ts` é apenas **reexportação** do contrato-fonte (nenhuma cópia de operações, gates,
capabilities ou validação de forma — molde `supabase/functions/metas/contrato.ts`). `supabase/config.toml`
registra `[functions.observacoes]` com `verify_jwt = true` e
`entrypoint = "./functions/observacoes/index.ts"`.

**Contrato transportável único:** `src/infrastructure/supabase/observacoes/contrato.ts` — as **8
operações** `observacao.*` (`criar`, `editar`, `definir_comunicado`, `excluir`, `revogar`, `obter`,
`listar_por_escopo`, `historico`), `DEFINICAO_POR_OPERACAO` (operação → gate/capability, **sem
fallback**), `RPC_POR_OPERACAO` em paridade **1:1** com as RPCs `observacao_*` da P2, `CHAVES_POR_OPERACAO`
e `validarEntradaObservacao` (forma fail-closed). Edge, adapter de cliente e testes consomem **a mesma**
fonte — nenhuma segunda verdade sobre operações/gates/capabilities/forma.

**Adapter fail-closed:** `src/infrastructure/supabase/observacoes/edgeObservacoes.ts` chama
`functions.invoke("observacoes")` e devolve o `resultado` **bruto** da RPC (a fronteira não inventa
campos). Cobre os **três** caminhos de falha exigidos pelo §17.1/P4: `error` de transporte, `data.error`
e `data.ok !== true` / ausência da própria chave `resultado` (com `resultado: null` **aceito** como
sucesso). Código público desconhecido ⇒ `FORBIDDEN` (fail-closed). **Sem** `.rpc(`, **sem**
`SERVICE_ROLE_KEY`, **sem** `localStorage` e **sem** fallback.

**Guardas e testes da fase:** `src/authorization/observacoesEdgeImportGraph.test.ts` (resolve o grafo
**real** de imports a partir de `supabase/functions/observacoes/index.ts`, espelho de
`metasEdgeImportGraph`), `src/authorization/observacoesContratoRpc.test.ts` (contrato × SQL **real** das
migrations da P2/P3), `src/authorization/observacaoRecursoSoberano.test.ts`,
`src/infrastructure/supabase/observacoes/contrato.test.ts` e
`src/infrastructure/supabase/observacoes/edgeObservacoes.test.ts`.

### 22.2 Mapa operação → gate: 7 funcionais + `listar_por_escopo` administrativa

**Sete operações são FUNCIONAIS** (Policy Engine com recurso REAL): `criar` (alvo funcional =
**colaborador-ALVO** — a observação ainda não existe; molde `goal.criar`), `editar`,
`definir_comunicado`, `excluir`, `revogar`, `obter` e `historico` (alvo `{type:"observation", id}`, a
identidade canônica do D1). **`observacao.listar_por_escopo` é ADMINISTRATIVA** (`observation.read`): a
listagem **não tem um alvo único autorizável** e o escopo/relação são decididos pela RPC soberana
`observacao_listar_por_escopo` (fonte única), exatamente como `goal.listar_por_escopo` na F5-10.
Fundamento: **§8 linha 1** (normativa) + molde da F5-10.
Declaração honesta de execução: a primeira versão do contrato nasceu com essa operação **funcional** e foi
**corrigida dentro da própria fase** — funcional exigiria um UUID de alvo que a listagem não possui, e a
fronteira devolveria `INVALID_INPUT` antes mesmo do gate (a listagem morreria).

### 22.3 Allowlist estrita e instante soberano (D21)

`CHAVES_COMUNS = {organization_id, operacao, operation_id}` é a base de todas as operações e qualquer
chave fora da allowlist da operação é `INVALID_INPUT`. **Nunca** são transportáveis: autoria
(`actor_*`/`author_*`/`membership_id`), tenant (`tenant_id`), estado (`status`, `excluida*`,
`comunicado_*`, `motivo_exclusao`), `version`/`domainState`/`capability`/`scope`/`payload_hash`.
`cycle_id` e `collaborator_id` existem **apenas na criação** (D4 — a mutação de linha existente não os
aceita); `expected_version` apenas nas **4** mutações de linha existente; `motivo` apenas em
`excluir`/`revogar` (D16).
**`data` não é transportável em nenhuma operação:** o instante da decisão é **soberano** (D21) — o F4-02
resolve os alvos de escopo "na data" e uma data escolhida pelo cliente seria **autoridade declarada pelo
chamador**. O relógio usado é o da fronteira/RPC.

### 22.4 Probe soberano da fronteira (alvo `observation`) e ramo de CRIAÇÃO

O probe **fail-closed** deixado pela P3 foi **substituído** pelo probe derivado da **linha soberana**
carregada em `contextoAutorizacao.ts`: a matriz vem da fonte única (`estadoDominioObservacao`) composta
com (a) a **AUTORIA D5** (`exigeAutoriaObservacao`; o autor autorizável é `author_collaborator_id`
comparado ao **vínculo** do ator — nunca a `usuarioAtual`/payload) e (b) a regra de **leitura
SELF-comunicada** (§8 linha 2; D7/D9). O `domainState` declarado pelo chamador **não** participa
(invariante 1 do §8).

**Ramo novo de criação (§8 linha 4):** para `observation.create` com alvo `collaborator`, o probe é
`probeObservacaoSoberanaDeCriacao`, composto de
`estadoDominioObservacao({cicloStatus, colaboradorStatus})` — ciclo `ATIVO` (D12) **e** colaborador-alvo
≠ `DESLIGADO` (D11) — com **SELF = DENY** (invariante 4: criar/editar/excluir são atos de **gestão**; o
avaliado não cria sobre si) e **status não resolvido ⇒ DENY** (fail-closed). O
`ContextoAvaliacaoSoberano` ganhou dois campos **opcionais** (`colaboradorStatus`, `cicloStatus`)
fornecidos pelo loader da Edge para o alvo `collaborator` (status **soberano** do colaborador-alvo e
`status` da linha do ciclo validado no payload); ausência ⇒ string vazia ⇒ o probe **NEGA**. O ramo exige
**simultaneamente** a capability `observation.create` e o alvo `collaborator`, de modo que nenhum outro
domínio muda de comportamento (`evaluation.*`/`goal.*` intactos).

### 22.5 `estadoDominioObservacao.ts` — módulo Edge-safe, e por quê

A P3 declarou a matriz de estado **dentro de `authorizationPolicy.ts`**. A P4 a **extraiu** para
`src/authorization/estadoDominioObservacao.ts` **sem mudança de semântica**, porque o adaptador de
compatibilidade importa `config/ambiente` (`import.meta.env` no **topo** do módulo) e serviços de cliente
(`colaboradorStorage`/`localStorage`), e `contextoAutorizacao.ts` está no grafo das Edge Functions
(`avaliacoes`, `ciclos`, `colaboradores`, `metas` e `observacoes`): um import estático daquele módulo
levaria `import.meta.env`/`localStorage` ao runtime **Deno** e **quebraria o boot** das Edges. O novo
módulo depende **apenas** de tipos do Policy Engine — mesmo padrão de `estadoDominioMeta.ts` e
`estadoDominioCiclo.ts` — e `authorizationPolicy.ts` passou a **importar e REEXPORTAR**
(`estadoDominioObservacao`, `EstadoObservacaoSoberano`), preservando a **superfície pública da P3** e
mantendo a matriz em **fonte única** (nada duplicado nos dois caminhos).

### 22.6 Ramo `observation` no provider (`reais.ts`) — condição para ALLOW real

`contextoAutorizacao.ts` monta os providers com **`criarProvidersReais`** (`providers/reais.ts`), logo o
tradutor de relação por escopo (`isTargetInScope`) está no caminho da **fronteira**. Sem um ramo para o
alvo `observation`, `SELF`/`DIRECT_REPORTS`/`DESCENDANTS` retornavam `false` e o gate negava por **scope
insuficiente** mesmo com capability, probe e concessão corretos: **nenhum ALLOW real** seria alcançável —
e o §17.1/P4 exige o ALLOW no caminho de **produção**. Foram adicionados `alvoObservacaoCorresponde` (a
relação é definida sobre o **colaborador-ALVO** da observação, `evaluation_observations.collaborator_id`;
o **id** da observação nunca define relação) e `observacaoNoEscopoDoAtor`: **SELF** = o ator é o
colaborador-alvo (via `donoDoAlvo`, derivado da linha real); **DIRECT_REPORTS**/**DESCENDANTS** = o
colaborador-alvo ∈ alvos resolvidos do escopo; **sem `donoDoAlvo` ⇒ DENY** (fail-closed). `ORGANIZATION`
não satisfaz — a P3 exige `DIRECT_REPORTS`/`DESCENDANTS` no gate, com a leitura SELF-comunicada como
exceção normativa do domínio.

### 22.7 Dívidas declaradas (NÃO resolvidas na P4)

1. **Autoria como relação no provider:** não existe análogo a `metaDoAlvo` para o **autor soberano** da
   observação, então o provider **não** a resolve: a autoria D5 é composta pelo probe do domínio e o SQL
   (`observacao_obter`/`observacao_editar`) é a autoridade final. Consequência assumida e declarada: um
   **autor fora do escopo "na data"** pode ser negado pelo engine onde o SQL permitiria — divergência
   **fail-closed** (nunca permissiva). A correção exige campo novo em
   `ResourceContext`/`DadosProvidersReais`, fora do escopo desta fase.
2. **Quem concede `observation.read` ao AVALIADO (SELF):** segue **decisão da P5**. A P3 entregou apenas
   o perfil `observacoes_gestor` com escopos `DIRECT_REPORTS`/`DESCENDANTS`; o bundle padrão **não** tem
   scope `SELF` — por isso a leitura SELF-comunicada é uma **exceção normativa do gate**, não uma
   concessão.
3. **`localStorage`/cutover de UI (P5) e certificação (P6):** não iniciados. Nenhuma migração de dados
   legados (D13) e **nenhum** call site de produção migrado nesta fase.

### 22.8 Evidência

**GATES PENDENTES (orquestrador):** `npm test`, `npm run build`, `npm run lint` e `git diff --check` são
executados pelo orquestrador no **gate privilegiado** desta fase, depois do congelamento dos arquivos
deste PR. Nenhum resultado de gate é afirmado neste registro.
Os artefatos de teste da fase estão listados em §22.1 e cobrem: grafo real de imports da Edge (nenhum
import relativo quebrado, `service_role` **só** em `index.ts`, `core.ts` sem runtime e o caminho de
cliente sem `.rpc(`), contrato × SQL real da P2/P3 (nomes, ordem e tipos dos 8 RPCs;
`p_actor_user_profile_id` sempre e `p_payload_hash` nunca; `p_operation_id` apenas nas mutações), forma e
allowlist do contrato, adapter fail-closed nos três caminhos e o recurso soberano da observação na
fronteira (incluindo o ramo de criação com SELF = DENY).

> **Nota de atualização (P5 — §23):** os gates da P4 **foram executados** pelo orquestrador no gate
> privilegiado: `npm test` **2209/2211** (apenas as **2 falhas pré-existentes** de Windows/CRLF —
> `AcompanhamentoMetasPage.test.tsx` e `MinhasMetasPage.test.tsx`), `npm run build` exit 0,
> `npm run lint` exit 0 e `git diff --check` exit 0, com commits `df3defe` (implementação), `47777fb`
> (registro dos gates) e `ea3ad43` (correção pré-merge da ligação Edge→schema) publicados em
> `feat/f5-11-p4-edge-observacoes`. O parágrafo acima é o registro da época do congelamento.

## 23. P5 — cutover soberano da UI (IMPLEMENTADA · Issue #250)

> **Rastreabilidade:** base **`8e88e3752b9ea3467a94c53fdd58b5eca9b92edc`** (squash da P4 em `main`),
> Issues **#250** (fase) e **#238** (mãe). **SQL intocado nesta fase** (nenhuma migration, nenhum RPC
> novo, nenhuma alteração de RLS/ACL); **nenhuma migração de dados de `localStorage`** (D13); **P6 não
> antecipada**. Registro da P3 em §21 e da P4 em §22. Decisões `D1–D16/D21/D22` **permanecem fechadas** —
> a P5 não reabriu nenhuma e **não** criou capability, grant, role, scope ou exceção de autorização.

### 23.1 Escopo entregue

- **Porta soberana (nova):** `src/application/ports/ObservationRepository.ts` — contrato de leitura por
  escopo, leitura de uma observação, **leitura da TRILHA** (`observacao.historico`) e as cinco mutações
  idempotentes; identidade por **UUID**; `ResultadoObservacoes<T>` e `ErroObservacoesSoberanas`
  (fail-closed, sem valor default permissivo).
- **Repositório soberano (novo):** `src/infrastructure/supabase/observacoes/repositorioObservacoesSoberanas.ts`
  — implementado **exclusivamente** sobre o adapter da P4 (`criarEdgeObservacoes`); sem `.rpc(`, sem
  credencial de serviço, sem `.from(`, sem `localStorage`/`sessionStorage` e sem fallback local.
- **Controlador de mutações (novo):** `src/services/observacoesSoberanas/controladorObservacoes.ts` —
  gera o `operation_id` (idempotência, D6/D10) e obtém o `expected_version` **sempre da leitura
  soberana**, nunca do browser; traduz o `CodigoPublico` em mensagem de UI e **não** transporta autoria,
  tenant, estado nem instante.
- **View-model (novo):** `src/services/observacoesSoberanas/mapeadorObservacaoUi.ts` — `ObservacaoDeUi`
  com identidade por UUID e rótulos (matrícula/nome) **injetados por parâmetro**; o mapeador devolve
  `null` quando falta o rótulo do colaborador-alvo (nunca completa dado inexistente). O tipo legado
  `src/types/Observacao.ts` ficou **intocado** (§23.3).
- **Cutover da UI gerencial:** `src/components/ObservacoesColaborador.tsx` (sem `observacaoStorage`, sem
  gate de autorização com alvo/contexto fabricados — o componente **não decide** autorização),
  `src/components/filtroObservacoesPorCiclo.ts`, `src/pages/ColaboradorDetalhePage.tsx` (observações do
  colaborador-alvo pela porta, alimentando o KPI), `src/services/exportarAvaliacaoPdf.ts` (lista
  soberana recebida por parâmetro, no molde já usado por `metasDoCiclo`, **sem leitura local**),
  `src/services/acessoObservacoesSoberanas.ts` e `src/pages/observacoesSoberanasDaPagina.ts`
  (`src/services/observacoesSoberanas/fluxoMutacaoObservacao.ts` para o fluxo de mutação).
- **Barreira D13 (legado somente leitura):** `src/services/observacaoStorage.ts` — as três mutações
  (`criarObservacao`/`atualizarObservacao`/`excluirObservacao`) passaram a **LANÇAR**
  (`ERRO_ESCRITA_LOCAL_OBSERVACOES`, retorno `never`); removidos o `persistir`, o gate de ciclo LOCAL
  `validarCicloAtivo` (D12 é do servidor) e o id fabricado no browser (`crypto.randomUUID`); as quatro
  leituras permanecem como **legado fora do caminho funcional**, sem dual-read. O segundo produtor da
  chave foi cortado (`src/services/geradorDadosTeste.ts` — a semente DEV deixa de produzir observações
  locais); `src/services/resetBaseDesenvolvimento.ts` permanece como **removedor** de DEV. A guarda
  `src/authorization/estruturaUiSeguranca.test.ts` passou a incluir o módulo em `CAMINHOS_LEGADO_LEITURA`
  e ganhou prova de que o acervo legado é **somente leitura**.
- **Dívidas da P4 fechadas:** (i) a **autoria como relação** chega ao provider —
  `observacaoDoAlvo?: ObservacaoRecursoContext` em `src/authorization/providers/reais.ts`, repassado por
  `src/authorization/contextoAutorizacao.ts` a partir do bloco soberano `resourceContext.observacao`
  (montado pela P4), de modo que o **autor** da LINHA lê a própria observação ainda que o alvo esteja
  fora do escopo "na data", e não-autor/autor ausente continuam DENY; (ii) o **vocabulário de status**
  foi normalizado na fronteira pelo normalizador canônico já existente (`statusColaboradorDoSoberano`:
  `active|leave|inactive` → `ATIVO|LICENCA|DESLIGADO`, desconhecido ⇒ `""` ⇒ fail-closed), sem criar
  segundo vocabulário no loader/Edge e sem duplicar a matriz de `estadoDominioObservacao.ts`.

### 23.2 Funil e autoridade preservada

`UI → porta soberana → adapter da P4 (functions.invoke("observacoes")) → Edge → RPC observacao_*`. A
P5 **não** criou autoridade no cliente: o browser não declara tenant, autoria, estado, versão,
capability nem instante; o `expected_version` vem da leitura e o `operation_id` é a única chave de
idempotência. Toda negação continua vindo do gate soberano (capability + escopo + relação + autoria +
D11/D12) e a RLS permanece a última barreira. **Gate de UI local foi REMOVIDO**: o painel antes decidia
com alvo/contexto fabricados no browser (`{kind:"observation",…}` + `usuarioAtual`), o que não é
autorização efetiva (§11 itens 3–5); agora a tela renderiza o resultado soberano e a mutação negada
exibe o código público — comportamento **fail-closed**, sem caminho permissivo novo.

### 23.3 Identidade por UUID (e por que o tipo legado não foi reaproveitado)

A projeção soberana devolve UUIDs (`observacao_obter`, `observacao_listar_por_escopo` e
`observacao_historico`), enquanto o tipo legado `src/types/Observacao.ts` exige matrícula **numérica**
(`colaboradorMatricula`/`autorMatricula`). Reaproveitá-lo exigiria derivar identidade no cliente — o que
seria criar **autoridade local de identidade** e um mapeamento não soberano UUID↔matrícula. A P5 optou
por um view-model **novo e independente** (`ObservacaoDeUi`), com UUID como identidade e rótulos
injetados por parâmetro a partir dos dados de colaborador que a própria página já carrega; o tipo legado
permanece intocado (nenhum consumidor novo o usa para autorização).

### 23.4 Barreira D13, ausência de migração e ausência de fallback

- **Sem migração de dados locais** (D13, §13.1): o acervo legado fica **invisível** após a barreira; não
  há importação, espelhamento nem dual-read.
- **Sem fallback produtivo**: nenhum caminho funcional cai para `observacaoStorage`/`localStorage`
  quando a chamada soberana falha — a falha é exposta como negação/erro público.
- **Sem autoridade local**: leitura local não decide nada; o gate de ciclo local foi removido do caminho
  de escrita e o id deixou de ser fabricado no browser.

### 23.5 SELF/read — **ADIADO para a fase corretiva P5.1 (BLOCKER registrado)**

**Decisão do orquestrador nesta fase:** o fluxo do avaliado (`src/pages/MinhaAvaliacaoDetalhePage.tsx`)
ficou **fail-closed e sem autoridade local** — lista de observações comunicadas vazia de forma explícita
(constante), sem bloco/atalho na tela e sem seção no PDF, com comentário no código apontando a
dependência. **Nenhuma** capability, grant, role, scope ou exceção de autorização foi criada; **D15 e o
mapa fechado da P3 permanecem inalterados**; `observacoes_gestor` permanece como está.

**Motivo técnico (fato verificado):** a exceção normativa de **escopo** para a leitura SELF-comunicada
já existe no gate da P3 (a exigência de escopo de gestão é dispensada quando `v_escopo = 'SELF'`), mas a
**capability** `observation.read` é exigida **antes** dela e o avaliado **não possui a concessão** — o
D15 concedeu `observation.*` apenas a `observacoes_gestor`, com escopos `DIRECT_REPORTS`/`DESCENDANTS`.
Logo, habilitar a leitura SELF exige uma **decisão de concessão**, território de D15, que esta fase não
pode tomar sozinha.

**Escopo fixado pelo orquestrador para a P5.1:** leitura **somente SELF**; somente observações
`comunicado = true`; observações **excluídas não visíveis**; **zero mutações SELF**; `observacoes_gestor`
**inalterado**; **fail-closed** e **isolamento cross-tenant** preservados; nenhuma reutilização de
capability de outro domínio (`evaluation.read` ou equivalente) e nenhuma alteração do mapa fechado da P3.

### 23.6 Dívidas restantes (P5.1 e P6)

1. **P5.1 (bloqueante):** concessão mínima de `observation.read` ao avaliado, com o escopo acima, e o
   consequente cutover da leitura SELF na UI/PDF.
2. **Resíduo morto de observações (não removido nesta fase, para decisão):**
   `ImpactoTemporalPeriodoCiclo.observacoes`, `persistirCorrecaoPeriodoCicloAtivoInterno` e
   `confirmarCorrecaoPeriodoCiclo.ts` — nenhum comportamento de ciclo foi alterado.
3. **P6 (certificação):** validação integrada/certificação da F5-11 com o SQL real, incluindo o caminho
   ALLOW do `observacoes_gestor` e a ausência de oráculo de tenant.
4. **Item de verificação** recomendado na P5.1/P6: a guarda de conexão entre Edge e schema (nomes e
   assinaturas dos `resolver_*` e das `observacao_*`) deve continuar derivada do **fonte real**, nunca de
   lista digitada — foi assim que um typo de comentário gerou um falso positivo de auditoria na P4.

### 23.7 Evidência

**GATES PENDENTES (orquestrador):** `npm test`, `npm run build`, `npm run lint` e `git diff --check` são
executados pelo orquestrador no **gate privilegiado** desta fase, depois do congelamento dos arquivos
deste PR. Nenhum resultado de gate é afirmado neste registro.

> **Nota de atualização (P6 — certificação, §24):** os gates da P5 **foram executados** pelo orquestrador
> no gate privilegiado: `npm test` **2296/2298** (apenas as **2 falhas pré-existentes** de Windows/CRLF),
> `npm run build` exit 0, `npm run lint` exit 0 e `git diff --check` exit 0, com os commits `6fd020d`
> (implementação) e `5dedc1f` (registro dos gates) publicados em
> `feat/f5-11-p5-cutover-observacoes`. O parágrafo acima é o registro da época do congelamento.
> Os gates locais da **certificação** (F5-11 inteira) estão em `docs/F5-11-certificacao.md` §3 —
> pendente apenas o **CI oficial do PR/SHA**.

Os artefatos de teste da fase cobrem: porta/repositório (operação e chaves derivadas do contrato real,
fail-closed nos três caminhos, varredura `?raw` contra `.rpc(`/credencial/storage), controlador
(idempotência, versão lida da leitura, ausência de campo de autoridade), view-model (rótulo ausente ⇒
`null`), painel/timeline, detalhe do gestor + KPI, PDF sem leitura local, barreira D13 (as três mutações
lançam, chave byte a byte inalterada, nenhum estado de ciclo libera escrita local) e as guardas de
estrutura de UI (acervo legado **somente leitura**).

## 24. P5.1–P5.4 — SELF/read automático, autoridade por role e lifecycle da role automática (IMPLEMENTADAS · Issues #252/#253; certificação na Issue #254)

> **EMENDA DE D15 (registrada).** O §8 (D15) exigia "concessão **EXPLÍCITA** em bundle/perfil de gestão" e
> a P3 registrou `observacoes_gestor` como a **única** role com `observation.*`. A partir da P5.1 existem
> **DOIS** perfis de sistema com `observation.*`: `observacoes_gestor` (gestão, as 4 capabilities,
> **inalterado**) e `observacoes_avaliado` (**exatamente `observation.read`**, **sem scope assignment**),
> concedido **AUTOMATICAMENTE** por elegibilidade. `admin` permanece **sem** `observation.*`; `metas_dono`
> e `metas_aprovador` seguem exclusivos do domínio de metas. A guarda interna da migration da P3
> ("`observation.*` em OUTRA role de sistema") é *point-in-time* e fica **superseded** por esta emenda —
> reaplicar a P3 depois da P5.1 falharia nessa guarda.
>
> **Decisão do orquestrador (P5, Issue #250):** SELF/read foi **adiado** para a fase corretiva P5.1 (a
> capability é exigida antes da exceção normativa de escopo), com o fluxo do avaliado **fail-closed** até
> a P5.1. O escopo fixado — leitura **somente SELF**, **somente `comunicado = true`**, excluídas
> invisíveis, **zero mutações SELF**, `observacoes_gestor` inalterado — foi implementado e certificado.

| Fase | Migration | Entrega | Evidência de banco |
|---|---|---|---|
| P5.1 | `20260933000000_f5_11_p5_1_self_read_observacoes.sql` | 5º system role `observacoes_avaliado`; triggers de tabela (`membership_collaborator_links`, `user_organization_memberships`); backfill idempotente; **D18** com `system_grant`/`system_revoke` (ator NULL + constraint discriminante) e coluna `origin` em `membership_access_role_assignments` | `42-cenario`/`43-validar-f5-11-p5-1.sql`; `ci.yml:531-547` |
| P5.2 | `20260934000000_f5_11_p5_2_admin_authority_por_role.sql` | `usuario_eh_administrador` passa a exigir a role **`admin`** (fecha a escalada de privilégio que a P5.1 amplificava) | bloco 7.1 de `02-validar-f5-04.sql` |
| P5.3 | `20260935000000_f5_11_p5_3_lifecycle_perfil_avaliado.sql` | trigger em `user_profiles` reavalia **cada** membership pela **mesma** função (nenhuma duplicação da regra de elegibilidade) | bloco `I` de `43-validar-f5-11-p5-1.sql` |
| P5.4 | `20260936000000_f5_11_p5_4_avaliado_exclusivo_e_corrida.sql` | role automática **exclusiva** (grant/revoke humano bloqueados nas duas RPCs administrativas; colisão `origin='human'` falha fail-closed) e **upsert único** antirracismo (sem advisory lock) | bloco `J` de `43-validar-f5-11-p5-1.sql` |

**Elegibilidade (fonte única):** membership ativa + `user_profiles` ativo + vínculo ativo. Inelegível ⇒
assignment `revoked` (**nunca** DELETE físico); reativação na **mesma** assignment; evento
`system_grant`/`system_revoke` **somente** em transição real, com `actor_user_profile_id` **NULL**.

**Certificação, dívidas classificadas e gates exigidos:** `docs/F5-11-certificacao.md` (Issue #254).