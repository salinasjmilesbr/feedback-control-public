# F5-11 — Observações soberanas e histórico auditável (reconhecimento + proposta de desenho)

> **Atividade:** F5-11 — Issue **#238**. **Base:** `main` = `5889decb81d4dc3feca15ca15d37f164e2f614ea`
> (squash do PR #236 / Issue #224). **Branch:** `docs/f5-11-observacoes-soberanas-desenho`.
> **Natureza desta rodada:** **reconhecimento integral + proposta de desenho**. **NÃO é documento
> normativo** e **não fecha** o contrato: as questões arquiteturais reais estão em **§15 (Q1–Q16)** e
> **nenhuma implementação pode começar antes de elas serem fechadas**.
> **Nenhuma migration, RPC, Edge Function, policy, RLS, capability, alteração funcional de UI ou
> persistência foi criada ou alterada nesta rodada.** A única alteração é documental.
> **Regras de leitura:** onde este documento diz **PROPÕE**, é proposta com recomendação fundamentada
> (sujeita a fechamento); onde diz **DECIDE (herdado)**, é decisão já fechada em contrato anterior
> (F4-* / F5-09 / F5-10) que **não se reabre** sem evidência técnica nova (`.ai/architecture-rules.md` §4).

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
- **Importação do acervo legado** — ver §10 (decisão inicial: **não migrar**).
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

- `resolver_collaborator_vinculado(user_profile, org) returns table(collaborator_id)` —
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

# PROPOSTA DE DESENHO (não normativa — Q1–Q16 abertas em §15)

## 7. Modelo soberano proposto

### 7.1 Identidade (PROPÕE)

A identidade canônica passa a ser **`evaluation_observations.id` (uuid, PK)**, atribuída pelo banco.
`matricula`, `autorNome`, `(ano, numero)` e o UUID do browser são **rótulos de projeção** — nunca
identidade, chave de leitura ou autorização. Vínculos por UUID: `organization_id` (tenant da linha),
`collaborator_id` (`collaborators.id`), `cycle_id` (`evaluation_cycles.id`) e autoria por
`author_user_profile_id`/`author_membership_id` (padrão do ator verificado) mais
`author_collaborator_id` derivado do vínculo (nulo quando o ator não tem vínculo de colaborador).

### 7.2 Tabelas (PROPÕE — esboço, não DDL final)

```sql
-- esboço ilustrativo; nomes/constraints a ratificar em Q1/Q2/Q3/Q6/Q7/Q8/Q16
create table public.evaluation_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  collaborator_id uuid not null,                 -- alvo (collaborators.id)
  cycle_id uuid not null,                        -- evaluation_cycles.id  (Q2)
  tipo text not null check (tipo in ('POSITIVA','NEUTRA','NEGATIVA')),
  texto text not null check (texto <> '' and texto = btrim(texto)),
  comunicado boolean not null default false,
  comunicado_em timestamptz,
  comunicado_por_user_profile_id uuid,
  comunicado_por_membership_id uuid,             -- Q7
  excluida boolean not null default false,
  excluida_em timestamptz,
  excluida_por_user_profile_id uuid,
  excluida_por_membership_id uuid,
  motivo_exclusao text,                          -- Q8/Q16
  author_user_profile_id uuid not null,
  author_membership_id uuid not null,
  author_collaborator_id uuid,                   -- derivado do vínculo (Q3)
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
  constraint ck_evaluation_observations_comunicado check (
    (comunicado and comunicado_em is not null
       and comunicado_por_user_profile_id is not null and comunicado_por_membership_id is not null)
    or (not comunicado and comunicado_em is null
       and comunicado_por_user_profile_id is null and comunicado_por_membership_id is null)),
  constraint ck_evaluation_observations_exclusao check (
    (excluida and excluida_em is not null and excluida_por_user_profile_id is not null
       and excluida_por_membership_id is not null and motivo_exclusao is not null)
    or (not excluida and excluida_em is null and excluida_por_user_profile_id is null
       and excluida_por_membership_id is null))
);
create index ix_evaluation_observations_alvo
  on public.evaluation_observations (organization_id, collaborator_id, cycle_id) where not excluida;

-- trilha append-only (molde cycle_events / evaluation_goal_events)
create table public.evaluation_observation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  observation_id uuid not null,
  entity_type text not null check (entity_type = 'evaluation_observation'),
  event_type text not null check (event_type in
    ('CRIADA','EDITADA','COMUNICADO','COMUNICACAO_REMOVIDA','EXCLUIDA','REVOGADA')),
  effective_date timestamptz not null,
  reason text,                                   -- obrigatório em EXCLUIDA/REVOGADA (Q8/Q16)
  before_value jsonb, after_value jsonb,         -- Q6
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  result_entity_id uuid,
  actor_user_profile_id uuid not null,
  actor_membership_id uuid not null,
  operation_id uuid not null,
  created_at timestamptz not null default now(),
  constraint uq_evaluation_observation_events_org_operation unique (organization_id, operation_id)
);
```

**Sem tabela de histórico separada além da trilha**: o "histórico" que a UI mostra passa a ser a
leitura da trilha append-only (Q6). **Sem colunas de meta/avaliação dobradas** na linha da
observação: a observação **não** altera `nota_media`, não gera `evaluation_scores` e não influencia
`evaluation_aggregates` (decisão de não escopo, §2).

### 7.3 Semântica das colunas (PROPÕE)

| Coluna | Semântica |
|---|---|
| `tipo` | domínio fechado de 3 valores; **imutável?** — ver Q4 (o legado permite trocar o tipo na edição e registra `tipoAnterior`) |
| `texto` | conteúdo da observação; `btrim`, não vazio; limite de tamanho em Q16 |
| `cycle_id` | ciclo **da criação**; **imutável** após a criação (paridade com `observacaoStorage.ts:154-156`) |
| `comunicado` + `comunicado_em` + `comunicado_por_*` | fato auditável da disponibilização ao avaliado (Q7) |
| `excluida` + `excluida_em` + `excluida_por_*` + `motivo_exclusao` | exclusão **lógica** com rastreabilidade (nunca física) |
| `author_*` | autoria **derivada** de `auth.uid()` na fronteira; **imutável** (nunca transferível) |
| `version` | concorrência otimista; `version + 1` em toda mutação efetiva (Q10) |
| `created_at`/`updated_at` | relógio **do servidor** (`public.set_updated_at()`) |

### 7.4 Ciclo e estados (PROPÕE)

- `cycle_id` **obrigatório** (Q2): a criação legada sempre exige `(ano, ciclo)` e ciclo `ATIVO`; o
  "sem ciclo" do tipo atual só existe para dados antigos, que **não serão migrados** (§10).
- **Mutação** (criar/editar/comunicar/excluir/revogar) somente com ciclo **`ATIVO`**, lido da **linha
  soberana** — paridade com `validarCicloAtivo` (`observacaoStorage.ts:30-39`) e com o domínio de
  metas (F5-10 §10).
- **Leitura** permitida independentemente do estado do ciclo (histórico permanece consultável após
  `ENCERRADO`/`CANCELADO`) — Q12.
- A observação **não** muda de ciclo: corrigir o período do ciclo **não** altera a observação.

### 7.5 Edição (PROPÕE)

- A edição recebe a **definição completa** dos campos editáveis (`tipo`, `texto`, `comunicado`) e
  **não** faz merge parcial (padrão `goal.editar`, F5-10 §13).
- `cycle_id`, `collaborator_id` e autoria são **imutáveis**: alterá-los ⇒ `INVALID_INPUT` (o
  contrato de forma nem aceita esses campos nas operações de mutação existente).
- `expected_version` **obrigatório**; divergência ⇒ `CONFLICT`.
- Cada edição efetiva grava evento append-only com **before-image** dos campos alterados (Q6) para
  preservar o "Texto anterior" que a UI mostra hoje (`ObservacoesColaborador.tsx:641-653`).

### 7.6 Exclusão e revogação (PROPÕE)

- **Exclusão é sempre lógica** (`excluida = true` + carimbo + `motivo_exclusao` obrigatório — Q16).
  **Exclusão física é proibida** (ACL sem `DELETE`/`TRUNCATE` + triggers de imutabilidade).
- **Revogação** (desfazer a exclusão lógica) é operação **distinta**, permitida **somente** com ciclo
  `ATIVO` e **somente** pelo autor, com evento `REVOGADA` (Q8). A trilha preserva
  `EXCLUIDA` e `REVOGADA` — a exclusão nunca é apagada do histórico.
- Observação excluída: leitura **histórica** permanece (para quem já podia ler), mutação e
  comunicação **negadas**.

### 7.7 Comunicado (PROPÕE)

`comunicado` deixa de ser booleano anônimo e passa a ser **fato auditável**:
`comunicado = true` exige `comunicado_em` + `comunicado_por_user_profile_id` +
`comunicado_por_membership_id` (CHECK), e cada transição grava evento próprio
(`COMUNICADO` / `COMUNICACAO_REMOVIDA`). É **ato de disponibilização ao avaliado**: habilita a leitura
por SELF (§8). Sem capability nova (Q7) — o gate é `observation.edit` sobre o recurso, com a
semântica que o catálogo F4-01 declarou como futura.

### 7.8 Temporalidade e histórico (PROPÕE)

- **Toda** mudança relevante é um evento append-only com `effective_date`, `actor_*`, `operation_id`,
  `payload_hash` e before/after (Q6) — a trilha é a **única** fonte do histórico.
- Imutabilidade em **duas camadas** (ACL + triggers), como `cycle_events`/`evaluation_goal_events`.
- Timestamps de negócio (`comunicado_em`, `excluida_em`) vêm do **servidor**.
- Períodos usam a convenção do projeto `[valid_from, valid_to)`; exceção já documentada do domínio de
  ciclo (`data_fim` inclusiva) **não** se aplica aqui (a observação não tem período próprio).

### 7.9 Comportamento por estado (PROPÕE — consolidado em §8)

- **Colaborador `active`** (`ATIVO`): tudo permitido conforme a relação.
- **Colaborador `leave`** (`LICENCA`): permite **criar** (paridade explícita com
  `authorizationPolicy.test.ts:132-149`), editar, comunicar e excluir — Q11.
- **Colaborador `inactive`** (`DESLIGADO`): **nega criar**, comunica e edita; **permite ler e
  excluir** (higiene de conteúdo) — Q11.
- **Ciclo `PLANEJADO`**: nega mutação (não é o "ciclo ativo" legado), permite leitura.
- **Ciclo `ATIVO`**: permite tudo conforme relação + autoria.
- **Ciclo `ENCERRADO`/`CANCELADO`**: nega mutação, permite leitura histórica.
- **Observação excluída**: nega mutação e comunicação; permite leitura histórica.
- **Status do colaborador não resolvido / vínculo do ator ausente / relação não resolvida**:
  **DENY** (fail-closed).

## 8. Autorização — matriz preliminar (PROPÕE)

**Capabilities (nenhuma nova — paridade com a F5-10 D6):** `observation.read`, `observation.create`,
`observation.edit`, `observation.delete`. O catálogo permanece com **31** códigos físicos e
`goal.% + observation.% = 8`. `observation.write` permanece **deprecada** e não é usada.
**Não há** capability de comunicação: marcar/desmarcar comunicado é `observation.edit` sobre o
recurso (Q7).

| # | Operação | Capability | Gate | Relação / escopo | Estado do colaborador | Estado do ciclo | Autoria |
|---|---|---|---|---|---|---|---|
| 1 | **listar** observações de terceiros (painel/acompanhamento) | `observation.read` | **administrativo** (leitura sem alvo único autorizável; molde F5-10 §11 / `goal.listar_por_escopo`) + filtro por relação | interseção: escopos do ator (`DIRECT_REPORTS`/`DESCENDANTS`) ∩ relação congelada | qualquer | qualquer | irrelevante |
| 2 | **listar** as próprias comunicadas (MinhaAvaliação / PDF) | `observation.read` | **funcional**, alvo `{observation \| collaborator}` | **SELF** com `comunicado = true` e `not excluida` | qualquer | qualquer | de terceiro |
| 3 | **visualizar** uma observação | `observation.read` | funcional | SELF-comunicada **ou** relação (autor, `DIRECT_REPORTS`, `DESCENDANTS`) | qualquer | qualquer | — |
| 4 | **criar** | `observation.create` | funcional | `DIRECT_REPORTS` / `DESCENDANTS` (relação do ciclo); **SELF = DENY** | ≠ `inactive` | `ATIVO` | autor = ator |
| 5 | **editar** | `observation.edit` | funcional | relação **e** `author_user_profile_id = ator` (Q5) | qualquer | `ATIVO` | **autor** |
| 6 | **marcar comunicado** | `observation.edit` | funcional | relação **e** autor (Q5/Q7) | ≠ `inactive` | `ATIVO` | **autor** |
| 7 | **desmarcar comunicado** | `observation.edit` | funcional | relação **e** autor | qualquer | `ATIVO` | **autor** |
| 8 | **excluir** (lógica, com motivo) | `observation.delete` | funcional | relação **e** autor | qualquer | `ATIVO` | **autor** |
| 9 | **revogar exclusão** | `observation.edit` | funcional | relação **e** autor (Q8) | qualquer | `ATIVO` | **autor** |
| 10 | **consultar histórico** | `observation.read` | funcional | **mesma** regra de (3) — a trilha não amplia alcance | qualquer | qualquer | — |

**Invariantes fail-closed (obrigatórios em qualquer variante escolhida):**

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

**Concessão (Q15):** hoje **nenhuma** role de sistema concede `observation.*`, e o bundle `admin` é
**proibido por guarda** de conter capability de leitura de conteúdo
(`02-validar-f4-01.sql:563-578`). Sem decisão explícita de concessão, o domínio nasce **DENY em
produção** — exatamente o risco R2 da F5-10. O fechamento de Q15 é **pré-requisito** da P3.

## 9. Segurança — ameaças e controles (PROPÕE)

| # | Ameaça | Vetor no legado | Controle proposto |
|---|---|---|---|
| T1 | **Cross-tenant** | não há tenant; qualquer navegador vê tudo | `organization_id` derivado/revalidado server-side (`user_has_active_membership`); FK composta de tenant; `NOT_FOUND` indistinguível |
| T2 | **IDOR** | `id` é UUID do browser; nenhuma verificação de escopo na leitura | alvo resolvido por `(id, organization_id)` **e** relação verificada **antes** de devolver a linha; RLS/deny-by-default como defesa em profundidade |
| T3 | **Alteração de autoria** | `autorMatricula`/`autorNome` no payload; `excluidaPor*` textual | autoria **derivada** de `auth.uid()` na fronteira; campos de autoria **não** existem no contrato de mutação; `UNIQUE`/FK de membership; autoria imutável |
| T4 | **Alteração indevida de `collaborator_id`** | campo do objeto local | `collaborator_id` **não** é editável; alvo vem do alvo da operação e é revalidado no tenant |
| T5 | **Alteração indevida de `cycle_id`** | `atualizarObservacao` recusa, mas o blob é livre | `cycle_id` **fora** do contrato de edição; CHECK/FK de tenant; mudança de ciclo ⇒ `INVALID_INPUT` |
| T6 | **Leitura fora do escopo** | leitura sem gate (`ColaboradorDetalhePage`) | gate funcional `observation.read` + relação; leitura de terceiros só por RPC com gate; **SELF só comunicadas** |
| T7 | **Mutação fora do escopo** | `edit`/`delete` só com `can()` (UX) | `authorize` equivalente **server-side** em toda RPC; `authorize()` no cliente é UX, nunca enforcement |
| T8 | **Manipulação de histórico** | array embutido, reescrevível | trilha append-only com ACL sem `UPDATE`/`DELETE`/`TRUNCATE` **e** triggers de imutabilidade; before-image + `payload_hash` |
| T9 | **Exclusão física** | limpar `localStorage` apaga tudo | `DELETE`/`TRUNCATE` revogados até de `service_role`; exclusão **só** lógica; carimbo + motivo |
| T10 | **Spoofing de comunicado** | booleano anônimo alterável na edição | `comunicado_em`/`comunicado_por_*` gravados server-side; CHECK de coerência; evento próprio; sem campo livre de "comunicado por" |
| T11 | **Concorrência / lost update** | array inteiro regravado (last-write-wins) | `expected_version` + `SELECT ... FOR UPDATE`; `version + 1`; evento na **mesma** transação (Q10) |
| T12 | **Replay / duplicidade** | não existe | `unique (organization_id, operation_id)` + `payload_hash` derivado server-side; replay com a mesma intenção devolve o mesmo resultado; intenção divergente ⇒ `CONFLICT`; sub-eventos via `f5_10_derivar_operation_id` |
| T13 | **Escalada por `capability`/`role` no corpo** | `authorizationContext` montado no cliente | allowlist **estrita** de chaves por operação (forma nunca é autoridade); capability derivada de mapa fechado; `role`/`cargo`/`funcao` **nunca** autorizam |
| T14 | **Estado autorizativo declarado pelo cliente** | `comunicado`/`excluida` no payload | estado lido da **linha soberana**; o cliente envia **intenção**, nunca estado |
| T15 | **Denial-of-service por payload** | texto livre sem limite | limite de tamanho na fronteira **e** no banco (Q16) |
| T16 | **Vazamento por log/erro** | mensagens cruas | códigos públicos fechados (`CodigoPublico`) na Edge; mensagem do banco nunca chega ao cliente |
| T17 | **Fail-open silencioso** | `catch { return [] }` e mundo DEV | fail-closed explícito: indisponibilidade vira **erro/fase explícita**, nunca lista vazia silenciosa |
| T18 | **Concessão indevida de leitura confidencial** | — | `observation.*` **fora** do bundle `admin` (guarda existente); concessão explícita e testável (Q15) |

## 10. Dados legados (decisão inicial: **NÃO migrar**)

**Decisão inicial assumida:** **não migrar** o acervo de `feedback-control-observacoes`. Evidência
que sustenta a decisão (e que o implementador deve reconferir, não presumir):

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

**Condição explícita para reabrir esta decisão:** evidência concreta e verificável de conteúdo de
produção com valor funcional (por exemplo, relato do responsável de produto de que avaliações
publicadas dependem de observações comunicadas de um determinado ciclo). Sem essa evidência, migrar
seria construir histórico **não soberano** (autoria não verificável) sobre dados não rastreáveis —
o que contraria o objetivo da atividade.

**Consequência para o cutover:** aplica-se o modelo de **barreira de escrita** já usado na F5-10
(D24): a leitura legada, se mantida, é **estritamente transitória** e não pode sobreviver como
fallback funcional; a escrita local passa a **lançar** apontando a porta soberana; **após** o cutover
não há dual-read. Se o responsável decidir por migrar, será **atividade própria**, com
congelamento/exportação, contagem de entrada, quarentena para ambiguidade e **sem** dual-write.

## 11. Estratégia de cutover (PROPÕE)

1. **Autorização primeiro, UI depois:** `observation` sai de `TIPOS_RECURSO_NAO_SOBERANOS`
   (`resourceContextReal.ts:38`), ganha `carregarRecurso` real e `alvosPermitidos` por relação; o
   gate funcional passa a existir **antes** de a UI mudar de fonte.
2. **Porta soberana de leitura** (molde `src/services/*Soberanos/` + repositório
   `src/infrastructure/supabase/observacoes/`) — a UI **não** fala RPC direto.
3. **Controlador de mutações** por operação (`criar`, `editar`, `definir_comunicado`, `excluir`,
   `revogar`) com `operation_id` gerado no cliente e `expected_version` da leitura soberana.
4. **Telas/consumidores:** `ObservacoesColaborador.tsx` (CRUD + histórico), `ColaboradorDetalhePage`
   (KPIs `contarObservacoesPorTipo` + painel), `MinhaAvaliacaoDetalhePage` (comunicadas),
   `exportarAvaliacaoPdf` (comunicadas). O filtro/ordenação
   (`filtroObservacoesPorCiclo.ts`, `ordenacaoPorCiclo.ts`) é reaproveitado sobre as projeções
   soberanas.
5. **Barreira de escrita** em `observacaoStorage.ts` (`criarObservacao`/`atualizarObservacao`/
   `excluirObservacao` lançam apontando a porta soberana) e **remoção do caminho funcional** de
   leitura local — sem dual-read.
6. **Segundo produtor:** `geradorDadosTeste.ts` deixa de escrever a chave legada (ou passa a gerar
   via porta soberana), e a lista de exceção "legado leitura"
   (`estruturaUiSeguranca.test.ts:391-409`) é ajustada.
7. **Guardas invertidas do CI:** substituir `15-validar-f5-09-p9.sql:2121-2173` e
   `30-validar-f5-10-p7.sql:1401-1413` pelas asserções positivas da F5-11 (a tabela/funções passam a
   ser **exigidas**, com a contagem de capabilities **inalterada** em 31).
8. **Dívidas encerradas na F5-11:** os marcadores `▸(add authorize)` de
   `docs/F4-09-desenho-tecnico.md:253-255` e a assimetria registrada em
   `docs/F5-07-desenho-tecnico.md:1331-1338` §20.4.
9. **Resíduo morto:** decidir destino de `ImpactoTemporalPeriodoCiclo.observacoes`,
   `persistirCorrecaoPeriodoCicloAtivoInterno` e `confirmarCorrecaoPeriodoCiclo.ts:14`.

## 12. Testes necessários (PROPÕE)

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
**proíbem** observação, `catalogoCapabilities.test.ts` (se houver concessão, Q15) e
`p9MatrizIntegrada`/guards que contam 8 capabilities.

## 13. Decomposição recomendada (PROPÕE — Q14)

**Recomendação: P1–P6**, derivada da complexidade **real** encontrada e **não** copiada da F5-10:

| Fase | Conteúdo | Por que é uma fronteira própria |
|---|---|---|
| **P0** | **este documento** + fechamento de Q1–Q16 | nenhuma implementação com decisão aberta (AGENTS.md §6) |
| **P1** | Schema: `evaluation_observations` + `evaluation_observation_events`; FKs compostas de tenant; CHECKs de coerência; `version`; ACL/deny-by-default; triggers de imutabilidade; substituição das **guardas invertidas** do CI; cenário + validador | é o único pacote que mexe no schema e nas guardas que hoje **proíbem** observação |
| **P2** | Operações soberanas `observacao_*` (criar/editar/definir_comunicado/excluir/revogar/obter/listar_por_escopo/histórico), `expected_version`, `operation_id`, idempotência, eventos, gate funcional reutilizável | domínio puro, sem UI; gateia tudo antes de existir superfície |
| **P3** | Autorização: `observation` como **recurso soberano** (sai de `TIPOS_RECURSO_NAO_SOBERANOS`), `carregarRecurso`, `alvosPermitidos` por relação, matriz capability × estado com **fonte única**, **concessão explícita** (Q15) com teste de ALLOW no caminho de produção, RLS | mudança **transversal** ao Policy Engine e à concessão — não é "mais uma RPC" |
| **P4** | Edge `observacoes` (trio `index`/`core`/`contrato`) + contrato transportável único + adapter fail-closed + guardas de grafo de imports | fronteira de confiança e de exposição |
| **P5** | Cutover: porta soberana, controlador de mutações, telas, consumidores de arrasto (PDF, MinhaAvaliação, KPIs), barreira de escrita, `geradorDadosTeste`, listas de exceção, resíduo morto | é o pacote que **remove** o legado do caminho funcional |
| **P6** | Validação integrada: matriz SQL, concorrência real entre duas sessões, regressões P1–P10, relatório de gates executados × não executados (molde `docs/F5-09-p9-matriz-integrada.md`) | fecha com evidência, não com opinião |

**Por que não é 1 pacote:** há fronteiras arquiteturais claras (schema/ACL ≠ domínio ≠ autorização
transversal ≠ fronteira ≠ cutover ≠ validação) e cada uma tem gate próprio; um único PR misturaria
migration, RPC, Policy Engine, Edge e UI — exatamente o que a F5-10 evitou.

**Por que não são 7 como na F5-10:** a F5-10 tinha **aprovações** (P3), **autorização+RLS** (P4) e
**backfill** (P6) como pacotes separados. A F5-11 **não tem** aprovação, **não tem** quota/limite,
**não tem** matriz de invalidação e **não tem** backfill (§10) ⇒ 6 pacotes. Se Q15 exigir novo
bundle/role de sistema, isso é **escopo da P3**, não uma fase nova.

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

## 15. QUESTÕES ABERTAS (Q1–Q16 — requerem fechamento antes da implementação)

> Formato: **Q# — pergunta.** Alternativas **A/B/C**; **recomendação** fundamentada.
> Nenhuma destas decisões foi tomada nesta rodada.

**Q1 — Nomenclatura e forma das tabelas.**
A) `public.evaluation_observations` + `public.evaluation_observation_events` (recomendada);
B) `public.observations` + `public.observation_events`;
C) reusar `cycle_events` com `entity_type = 'evaluation_observation'`.
**Recomendação: A** — consistência com `evaluation_goals`/`evaluation_goal_events`, prefixo de RPC
`observacao_*` e ausência de colisão. **C é rejeitada**: `cycle_events` tem
`ck_cycle_events_entity_type check (entity_type = 'evaluation_cycle')` e
`unique (organization_id, operation_id)` — misturar domínios colidiria idempotência e exigiria
alterar constraint de contrato F5-09 **fechado**.

**Q2 — `cycle_id` obrigatório ou opcional.**
A) `cycle_id NOT NULL` (recomendada); B) `cycle_id` nulo com estado explícito "sem ciclo";
C) `cycle_id NOT NULL` + coluna `fora_do_ciclo boolean`.
**Recomendação: A** — a criação legada **sempre** exige `(ano, ciclo)` com ciclo `ATIVO`
(`observacaoStorage.ts:30-39,98-137`); os campos opcionais do tipo existem só para dados antigos, que
**não serão migrados** (§10); "fora de ciclo" não tem regra funcional, escopo nem autorização
definidos — criar essa via seria inventar domínio.

**Q3 — Forma e autoridade da autoria.**
A) `author_user_profile_id` + `author_membership_id` NOT NULL derivados do ator verificado, mais
`author_collaborator_id` **derivado** do vínculo e **nulo** quando não houver (recomendada);
B) apenas `author_user_profile_id`;
C) manter `autorMatricula`/`autorNome` como rótulos de exibição vindos do cliente.
**Recomendação: A**, com **fail-closed**: a operação exige **vínculo único de colaborador ativo** na
organização (padrão `f5_10_vinculo_meta_do_ator`) — sem vínculo ⇒ **DENY**, inclusive para ADMIN
("ADMIN não é superuser de conteúdo confidencial"). **C é rejeitada**: é exatamente a ameaça T3.
Rótulos de exibição (nome/matrícula) podem continuar existindo como **projeção** calculada
server-side, nunca como campo aceito do cliente.

**Q4 — Semântica da edição.**
A) edição com **definição completa** de `tipo` + `texto` + `comunicado`, com `cycle_id`/
`collaborator_id`/autoria **imutáveis** (recomendada);
B) edição **parcial** (só os campos enviados);
C) edição restrita a `texto` (tipo e comunicado só na criação).
**Recomendação: A** — paridade com o legado (a UI edita tipo, texto e comunicado) e com
`goal.editar` (F5-10 §13: a RPC recebe a definição completa; a fronteira não faz merge de domínio).

**Q5 — Quem pode editar/excluir.**
A) **somente o autor** (`author_user_profile_id = ator`) dentro da relação (recomendada);
B) autor **ou** a cadeia de gestão acima;
C) qualquer ator com a capability no escopo (comportamento atual, testado em
`authorizationPolicy.test.ts:508-518`).
**Recomendação: A** — observação é **registro de autoria**: permitir que terceiro reescreva o texto
de outro autor destrói a integridade probatória (ameaças T3/T8) e é incompatível com "histórico
auditável". **C é explicitamente rejeitada** e exige **inverter** o teste citado. Se o produto
precisar de correção por terceiro, o caminho correto é **nova observação** (ou revogação), não
sobrescrita alheia.

**Q6 — Necessidade e forma da tabela de histórico.**
A) trilha append-only `evaluation_observation_events` com `before_value`/`after_value jsonb`,
`payload_hash`, `operation_id`, `actor_*` e `event_type ∈ {CRIADA, EDITADA, COMUNICADO,
COMUNICACAO_REMOVIDA, EXCLUIDA, REVOGADA}` (recomendada);
B) trilha **sem** before-image (só hash/after-image);
C) **sem** trilha: colunas de auditoria na própria linha.
**Recomendação: A** — é o **único** desenho que preserva o que a UI mostra hoje
("Texto anterior", `ObservacoesColaborador.tsx:641-653`), cumpre "histórico auditável" e
impede manipulação (T8). **C é rejeitada**: colunas na linha não são append-only.

**Q7 — Semântica de `comunicado` e sua capability.**
A) colunas `comunicado_em` + `comunicado_por_user_profile_id` + `comunicado_por_membership_id`,
CHECK de coerência, evento próprio, gate = **`observation.edit`** sobre o recurso (recomendada);
B) manter apenas `comunicado boolean` (estado atual);
C) capability nova `observation.communicate`.
**Recomendação: A** — comunicar é **ato de disponibilização ao avaliado** (habilita a leitura SELF):
precisa de autoria e instante para ser auditável; o próprio catálogo F4-01 registrou a semântica como
futura (`20260908000001:59-60`) e a F4-09 §7.3 já a mapeia para `observation.edit`. **B é rejeitada**
(ameaça T10). **C é rejeitada**: capability nova quebraria a decisão herdada D6 da F5-10 (catálogo
31) e exigiria reescrever validadores de contagem em vários arquivos de CI.

**Q8 — Revogação da exclusão.**
A) revogação **permitida**, somente pelo autor e com ciclo `ATIVO`, gate `observation.edit`, evento
`REVOGADA`, `version + 1`, motivo obrigatório (recomendada);
B) **não existe** revogação (paridade estrita com o legado);
C) revogação por capability nova `observation.revoke`.
**Recomendação: A** — o escopo pedido inclui "excluir/revogar"; a exclusão é lógica, logo desfazê-la é
operação de **estado**, não de destruição, e a trilha preserva os dois eventos. **C é rejeitada** pelo
mesmo motivo de Q7-C (D6 herdado).

**Q9 — RLS: padrão de exposição.**
A) **deny-by-default integral** (ZERO policy, ZERO privilégio de cliente; leitura **exclusivamente**
por RPC com gate) — padrão D22-A (F5-10 P5, `20260927000000:54-58`) (recomendada);
B) policy `select_same_tenant` + `grant select` mínimo (padrão F5-10 **P4**, depois revertido);
C) policy own-tenant + policy SELF adicional.
**Recomendação: A** — o conteúdo da observação é **confidencial** (catálogo F4-01: "conteúdo de
terceiros é confidencial") e a lição registrada da F5-10 é que expor `SELECT` de tenant e só depois
endurecer gera retrabalho e risco (R11 da F5-10). Ainda: A evita depender de `evaluation_cycles`
permanecer legível por `authenticated` (assimetria declarada em aberto pela F5-10 P5).

**Q10 — Estratégia de concorrência.**
A) **sem advisory lock**; `expected_version` + `SELECT ... FOR UPDATE` na linha da observação
(recomendada);
B) reusar `ciclo_lock_organizacao` (família `evaluation_cycles:<org>`);
C) família nova `evaluation_observations:<org>`.
**Recomendação: A** — a observação é uma linha isolada cuja mutação **não** altera estado de ciclo,
quota ou agregado; versão otimista + row lock já elimina lost update (T11) sem serializar **todas** as
escritas de observação da organização (que B faria). **C é rejeitada**: a doutrina de
`20260914020000_f5_08_lock_key_alignment.sql` exige **uma** chave por família e proíbe família nova
sem necessidade. **Condição de revisão explícita:** se a implementação introduzir invariante sobre o
**conjunto** (ex.: limite de observações por ciclo, comunicação em lote), esta decisão deve ser
reaberta.

**Q11 — Estado do colaborador (`active` / `leave` / `inactive`).**
A) criar/comunicar exigem status ≠ `inactive`; **`leave` permite criar** (paridade com o legado e com
`authorizationPolicy.test.ts:132-149`); ler/editar/excluir/revogar permitidos em qualquer status
(recomendada);
B) `inactive` **e** `leave` bloqueiam criação, comunicação e edição;
C) bloqueia criar apenas quando o status **não resolve** (fail-closed implícito).
**Recomendação: A** — preserva a regra funcional vigente e é explícita; B mudaria comportamento sem
evidência de produto. **C é rejeitada**: status não resolvido já é DENY por falta de evidência, não
por regra de negócio.

**Q12 — Estado do ciclo.**
A) mutação **somente** com ciclo `ATIVO` (linha soberana); leitura em **qualquer** estado, inclusive
`CANCELADO` (recomendada);
B) leitura vedada em `CANCELADO`;
C) mutação também em `ENCERRADO` mediante capability excepcional.
**Recomendação: A** — paridade com `validarCicloAtivo` e com a matriz de metas; o histórico precisa
sobreviver ao encerramento. **B** esconderia trilha auditável sem base. **C** criaria caminho de
mutação pós-encerramento sem contrato.

**Q13 — Dados legados.**
A) **não migrar** + barreira de escrita no módulo legado + remoção da leitura local do caminho
funcional, sem dual-read (recomendada, §10);
B) não migrar, mas manter leitura local rotulada "legado" no painel;
C) migrar com pontes autoritativas, congelamento e quarentena.
**Recomendação: A** — os dados são descartáveis por construção (§10) e a autoria não é verificável;
**C** criaria histórico soberano sobre autoria não soberana. **B** mantém duas verdades na mesma tela,
antipadrão já rejeitado pela F5-10 D24. Reabrir **somente** com evidência concreta de perda funcional
relevante para produção (§10).

**Q14 — Decomposição.**
A) **P1–P6** (§13) (recomendada); B) pacote único; C) P1–P4 fundindo autorização no schema e Edge no
cutover.
**Recomendação: A** — fronteiras arquiteturais reais, cada uma com gate próprio; **B** misturaria
migration, RPC, Policy Engine, Edge e UI no mesmo PR; **C** acoplaria a mudança transversal de
autorização (P3) ao schema, dificultando auditoria e revertendo a separação que a F5-10 provou útil.

**Q15 — Concessão explícita de `observation.*` em produção.**
A) **bundle/role de sistema de gestão dedicado** (distinto de `admin`), concedendo as 4 capabilities
com escopos atribuídos por *assignment*, com teste de ALLOW no **caminho de produção**
(recomendada);
B) deixar apenas concedível em **roles customizadas** (o domínio nasce DENY no seed e o ADMIN concede
caso a caso), com teste de ALLOW criando a concessão explicitamente na fixture;
C) incluir as 4 no bundle `admin`.
**Recomendação: A** — sem concessão explícita o domínio nasce **DENY em produção** (risco R2 da
F5-10). **C é rejeitada**: a guarda `02-validar-f4-01.sql:563-578` **exige** que o bundle `admin`
**não** contenha `observation.read`/`create`/`edit`/`delete` (nem `report.read`), e a doutrina diz que
ADMIN não é superuser de conteúdo confidencial. **B** é aceitável como fallback **se** criar um novo
role de sistema for considerado fora do escopo da F5-11 — mas então a entrega precisa declarar
explicitamente que o domínio fica **DENY** até concessão administrativa, e o teste de ALLOW precisa
provar o caminho de concessão (nunca `localWorld`).

**Q16 — Limites de forma e motivo.**
A) `texto` com limite explícito (proposta: **1..2000** caracteres, `btrim`, não vazio) e
`motivo_exclusao` **obrigatório** na exclusão (recomendada);
B) `texto` sem limite e motivo opcional;
C) `texto` **1..500** (paridade literal com `LIMITE_TEXTO` de metas) e motivo obrigatório.
**Recomendação: A** — `cycle_events.reason` é `not null` e `goal.excluir` exige motivo: a
auditabilidade da exclusão depende do motivo. 500 caracteres é apertado para um texto de observação
(o legado não impõe limite); 2000 mantém o limite de forma no banco **e** na fronteira (ameaça T15).

## 16. Riscos

| # | Risco | Sev. | Mitigação proposta |
|---|---|---|---|
| R1 | `observation.*` sem concessão ⇒ domínio **DENY** em produção (análogo ao R2 da F5-10) | alta | **Q15** + teste de ALLOW no caminho de produção na P3 |
| R2 | Autoria continuar não soberana (impersonação/`usuarioAtual`) | alta | **Q3** + proibição de campos de autoria no contrato + guardas anti-`localWorld` |
| R3 | Editar/excluir observação de terceiro continuar ALLOW | alta | **Q5** + inversão declarada de `authorizationPolicy.test.ts:508-518` |
| R4 | `comunicado` continuar booleano anônimo (divulgação não auditável) | alta | **Q7** (carimbo + evento) |
| R5 | Duas verdades na tela (local + soberano) durante o cutover | média | **Q13-A** + barreira de escrita (F5-10 D24) |
| R6 | Relação congelada inexistente para o ciclo (sem avaliação/participantes) ⇒ **DENY** de criação legítima | média | P1 deve provar o caminho normal na fixture; se insuficiente, reabrir a relação de leitura (Q do §8, alternativa B) |
| R7 | Guardas invertidas do CI quebradas por engano em vez de substituídas | média | P1 declara a substituição de `15-validar-f5-09-p9.sql:2121-2173` e `30-validar-f5-10-p7.sql:1401-1413` |
| R8 | Escopo vazar para F5-10/F5-12 ou para "observação de critério" | média | §2 + §3.10; validadores de contagem de capabilities permanecem 31/8 |
| R9 | RLS exposta e depois endurecida (retrabalho) | média | **Q9-A** (deny-by-default integral desde a P1) |
| R10 | Concorrência subestimada (edição + comunicação simultâneas) | média | **Q10** + concorrência real entre duas sessões na P6 |
| R11 | Perda silenciosa do acervo legado no cutover | baixa | §10: sem migração **declarada**; nenhuma remoção automática da chave; congelamento só se Q13 mudar |
| R12 | Decisão de concessão (Q15) adiada para a P3 com a P2 já implementada ⇒ retrabalho | média | fechar Q15 **junto** com Q1–Q14, na P0 |
| R13 | `evaluation_cycles` continuar legível por `authenticated` (assimetria declarada em aberto pela F5-10 P5) | baixa | **Q9-A** não depende dessa leitura |

## 17. Decomposição, definição de pronto e método

### 17.1 Definição de pronto (DoD) proposta

1. Contêiner de observações no PostgreSQL com RLS deny-by-default, escrita fechada e trilha
   append-only.
2. Nenhuma autoridade funcional de observação no `localStorage`; nenhum fallback funcional.
3. `observation.*` decidível **em produção** pelo caminho canônico (sem `localWorld`).
4. Autoria soberana derivada de `auth.uid()`, imutável, com `operation_id` e `payload_hash`.
5. Comunicação ao avaliado como **fato auditável** (quem/quando), e leitura SELF **apenas** do
   comunicado.
6. Exclusão sempre lógica, com motivo e rastreabilidade; revogação auditada; exclusão física negada
   por ACL **e** por trigger.
7. Concorrência real provada entre duas sessões; `expected_version` e rollback comprovados.
8. Cutover das telas e consumidores com ciclo por **UUID soberano**; guardas invertidas substituídas.
9. Gates verdes (focados, suíte completa, build, lint, `git diff --check`, bateria SQL na ordem do CI)
   no SHA auditado; CI verde; auditorias independentes aprovadas.
10. F5-10/F5-12 não antecipadas; contratos da F5-09 (D1–D28) e da F5-10 (D1–D25) não reabertos;
    catálogo permanece **31**.

### 17.2 Método desta rodada (DEV-02 / DEV-03)

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
- **Nenhuma** execução pesada: **0** `npm test`, **0** `npm run build`, **0** `npm run lint`,
  **0** `db reset`, **0** chamada ao Supabase local, **0** RPC, **0** migration. Não houve alteração
  funcional, logo uma bateria pesada não produziria informação nova (DEV-03: "uma execução deve
  produzir nova informação").
- **1 lote privilegiado** previsto: `git add` + `commit` + `push` da documentação (DEV-02 —
  operações agrupadas).
- **Nenhuma** repetição de gate, **nenhuma** elevação de sandbox, **nenhum** `gh`/PAT/credencial,
  **nenhum** merge.
- **Tempo:** não medido de forma confiável nesta rodada (declarado, não estimado).
- **Usage/custo:** não observável a partir do ambiente — não reportado.
