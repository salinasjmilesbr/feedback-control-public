# F5-10 — Metas soberanas no PostgreSQL (desenho técnico)

> **Atividade:** F5-10 — auditoria arquitetural/read-only + desenho técnico.
> **Issue:** #208. **Base:** `main` = `285b2dd` (squash da F5-09/P9, integrada).
> **Branch:** `docs/f5-10-metas-soberanas-desenho`.
> **Natureza:** documento de contrato. **Nenhum código funcional foi alterado** nesta atividade.
> **Convenção de referência:** `docs/F5-09-desenho-tecnico.md` (seções 1–20) e
> `docs/F5-09-duvidas.md` (Q-F5-09-1..3 ratificadas).

## 1. Objetivo

Definir o contrato **soberano** do domínio de Metas: identidade canônica,
lifecycle, limites por ciclo, aprovações, progresso/finalização, trilha de
auditoria append-only, autorização (Policy Engine + capabilities + scopes),
RLS own-tenant, RPCs/Edge, cutover do frontend e eliminação do `localStorage`
como fonte funcional.

## 2. Escopo / não escopo

**Escopo:** o domínio de metas de ciclo (negócio/projeto e individuais), seus
limites por ciclo, aprovações de coordenador e gerente, progresso, finalização,
histórico e a substituição do acervo local por autoridade no PostgreSQL.

**Não escopo (dívidas de outros domínios — não tratar aqui):**

- **F5-11 (observações)**: `observation.*` segue como está; nada neste desenho
  cria tabela/RPC/Edge de observação.
- **F5-07**: histórico do colaborador e a pendência
  `ciclo_listar_colaborador_por_ciclo` (§13.6 do desenho da F5-09).
- **F5-08**: estrutura organizacional e catálogos (apenas consumidos).
- **F5-09**: ciclo, sua trilha e suas RPCs (apenas consumidos/reusados).
- Reescrita do modelo de avaliação (F5-06): metas **não** compõem nota hoje —
  “Cumprimento de metas e compromissos” é apenas texto de subcritério
  (`src/data/modeloAvaliacao.ts:62`); nenhuma dependência de nota foi encontrada.

## 3. Inventário auditado (base `285b2dd`)

### 3.1 Modelo de dados atual — `src/types/Meta.ts` (lido integralmente)

| Campo | Tipo | Observação |
|---|---|---|
| `id` | `string` | gerado **no browser** (`crypto.randomUUID()` em `metaStorage`) |
| `colaboradorMatricula` / `colaboradorNome` | `number` / `string` | vínculo por **matrícula** + nome desnormalizado |
| `cicloId` | `string` | UUID de ciclo **gerado no browser** por `cicloAvaliacaoStorage` |
| `ano`, `ciclo` | `number`, `1\|2\|3` | `(ano, numero)` copiado **denormalizado** |
| `tipo` | `NEGOCIO_PROJETO \| INDIVIDUAL` | dois tipos; **não existe** meta de equipe |
| `descricao`, `kpi`, `valorAlvo` | `string` | conteúdo |
| `status` | `EM_ANDAMENTO \| ATINGIDA \| NAO_ATINGIDA` | `Meta.ts:5-8` |
| `aprovacaoCoordenador` / `aprovacaoGerente` | `{ matricula, nome, data }?` | **estado autorizativo no próprio objeto** (`:61-62`) |
| `resultadoAtual`, `progressoPercentual`, `dataUltimoAcompanhamento` | `string?`, `number?`, `string?` | acompanhamento |
| `resultadoFinal`, `atingida`, `dataFechamento` | `string?`, `boolean?`, `string?` | fechamento |
| `dataCriacao` / `dataUltimaAtualizacao` | `string` | ISO local |
| `excluida` / `dataExclusao` | `boolean`, `string?` | **exclusão lógica** (não física) |
| `historico` | `HistoricoMeta[]` | trilha **dentro do objeto**, com `autorMatricula`/`autorNome` |

`AcaoHistoricoMeta` (`Meta.ts:10-18`) já enumera as ações desejadas:
`CRIACAO`, `EDICAO`, `ATUALIZACAO_PROGRESSO`, `FINALIZACAO`, `EXCLUSAO`,
`APROVACAO_COORDENADOR`, `APROVACAO_GERENTE`, `INVALIDACAO_APROVACOES`.

### 3.2 Persistência hoje

- **Único** acervo: `localStorage["feedback-control-metas"]`
  (`src/services/metaStorage.ts:24,27,37`). Não existe tabela, RPC, Edge,
  repositório ou policy de meta (três buscas independentes: `create table` com
  `goal|meta` ⇒ nenhum; `supabase/migrations` só tem os 3 códigos de catálogo;
  nenhum arquivo em `src/infrastructure/supabase/**` cita meta).
- O CI **proíbe** meta no schema hoje: `supabase/validacao/15-validar-f5-09-p9.sql`
  (≈`:2095-2132`) falha se existir tabela/RPC/coluna com `%goal%`/`%meta%`/
  `%observac%`. **Consequência:** a F5-10 terá de ajustar esse validador na
  própria atividade (é um guarda de “não antecipar F5-10”, não um contrato de
  produto).
- `getMetasDoColaboradorNoCiclo(colaboradorMatricula, cicloId)`,
  `getMetasDoCiclo(cicloId)`, `contarMetasPorTipo(...)` — todas leem o blob e
  filtram em memória (`metaStorage.ts:40-81`).

### 3.3 Lifecycle real (implementado)

| Operação | Onde | Como decide hoje |
|---|---|---|
| Criação/edição | `metaStorage.ts` (criar/atualizar) | valida ciclo ATIVO **lido do `localStorage`** (`validarCicloAtivo`, `:89-98`), aplica limite do tipo (`limiteDoTipo`, `:83-87`) e chama `authorize("goal.write")` com **mundo sintético** (`:106-127`) |
| Limite por tipo | `metaStorage.ts:83-87`, `:259-272` **e** UI (`MinhasMetasPage.tsx:124-128`) | duplicado em duas camadas |
| Aprovação | `metaStorage.ts:418-423` (autorização) e `:427-438`, `:454`, `:490` (regra) | `domainState: dominioPermite(true)` **hardcoded**; idempotência por *early-return* local; relação resolvida por `gestorMatriculaLegada`/`getGerenteResponsavelNoCiclo` |
| Exigência de aprovação do coordenador | `metaExigeAprovacaoCoordenador` (`:171-199`) | “coordenador = nível **intermediário**” (`gestorTemSuperior`), **fail-closed** sem evidência estrutural |
| Progresso/finalização | `metaStorage.ts` (acompanhamento/finalização) | grava campos no objeto e empurra um `HistoricoMeta` no array |
| Exclusão | `metaStorage.ts` | lógica (`excluida = true`), nunca física |
| Histórico | `Meta.historico[]` | array **mutável** dentro do objeto |

Estados: apenas `EM_ANDAMENTO` → `ATINGIDA`/`NAO_ATINGIDA`; **não há** transição
para “cancelada”, nem estado de aprovação separado do conteúdo.

### 3.4 Autorização atual (auditada)

- Catálogo: `goal.read` / `goal.write` / `goal.approve` existem desde a F4-01
  (`supabase/migrations/20260908000001_authorization_system_catalog.sql:53-58`),
  **sem nenhuma implementação** e **sem nenhuma role/bundle que os conceda**.
- `authorizationPolicy.ts:174-212`: existe `case "goal"`, mas o alvo é
  `{ type:"collaborator", id:<dono> }` e o `domainState` é **declarado pelo
  chamador** (`cycle.status` lido do `localStorage`).
- `resourceContextReal.ts:33`: `TIPOS_RECURSO_NAO_SOBERANOS = ["goal","observation"]`
  ⇒ no caminho de enforcement, meta é `TARGET_NAO_SOBERANO`/`TARGET_INVALID`
  (`contextoAutorizacao.test.ts:287-291`, `actorContext.test.ts:173`).
  Ou seja: **meta não é tipo soberano** e não passa pelo enforcement; o fluxo
  real só funciona porque endereça `collaborator`.
- Em produção o `goal.*` é **indecidível como ALLOW** pelo caminho
  role→capability: o mundo sintético de DEV devolve vazio fora de `DEV`
  (`providers/localWorld.ts:30-37`, `config/ambiente.ts:117-118`) ⇒ DENY total.
- `AcompanhamentoMetasPage.tsx:80-107` monta `AuthorizationContext` com o campo
  **textual** `funcao` e usa `can("goal.approve.*"/"goal.view.admin")` para
  decidir acesso e botões — `can()` é UX, não autorização.

### 3.5 Consumidores (mapa completo no relatório de auditoria da rodada)

**Metas diretas:** `MinhasMetasPage` (ALTO esforço de cutover),
`AcompanhamentoMetasPage` (ALTO), `PainelCicloPage`, `MinhaAvaliacaoPage`,
`PainelCiclosCoordenadorPage`.

**Arrastam metas junto:** `NovoFeedbackPage` (aviso de “metas sem aprovação
formal”, não bloqueia), `EditarFeedbackPage` (idem), `MinhaAvaliacaoDetalhePage`
(exibição), `exportarAvaliacaoPdf.ts` (seção “Metas do Ciclo”), `cicloEquipeService.ts`
(pendência `papel:"Metas"` no fechamento), `correcaoPeriodoCicloService.ts` +
`impactoCorrecaoPeriodoCiclo.ts` (impacto da correção de período).

**Inconsistência factual encontrada:** no impacto da correção de período,
avaliações/observações são filtradas por `(ano, ciclo)` e metas por `cicloId`
(`impactoCorrecaoPeriodoCiclo.ts:42` vs `:52` vs `:59-61`) — dois universos de
identidade no mesmo cálculo.

### 3.6 Testes existentes que tocam metas

`metaStorage.test.ts`, `AcompanhamentoMetasPage.test.tsx`,
`authorizationPolicy.test.ts` (paridade `goal.approve` × `podeAprovarMetaNoCiclo`
em `:909-919`), `estruturaSoberanaCliente.test.ts`, `cutoverEstruturalServicos.test.ts`,
`cancelamentoCicloService.test.ts`, `reaberturaCicloService.test.ts`,
`correcaoPeriodoCicloService.test.ts`, `cicloEquipeService.test.ts`,
`PainelCicloPage.test.tsx`, `estruturaUiSeguranca.test.ts` (listas de exceção
`:391-411`), `resetBaseDesenvolvimento.test.ts` e — **importante** —
`p9MatrizIntegrada.test.ts:145-158` + `15-validar-f5-09-p9.sql`: invariantes de
“nenhuma antecipação de F5-10” que a F5-10 **inverte por contrato**.

### 3.7 O que **não existe** (declarado)

Tabela/RPC/Edge/RLS de meta; `MetaProgresso` e `aprovacaoMeta` como tipos
(zero ocorrências em `src/`); **peso** de meta (o único `peso` em testes é peso
de colegiado na avaliação); meta de equipe; bridge `(ano,numero)` ↔ UUID de ciclo
para metas; qualquer `expectedVersion`, `operationId` ou trilha append-only.

## 4. Mapas exigidos

| # | Item | Situação |
|---|---|---|
| a | modelo de dados | §3.1 — blob único, matrícula+nome, `cicloId` fabricado, `(ano,numero)` denormalizado, histórico embutido |
| b | lifecycle | §3.3 — 3 estados, sem cancelamento, aprovação fora do estado |
| c | regras de negócio | ciclo ATIVO; limite por tipo (negócio/individuais); coordenador = nível intermediário; gerente = raiz da cadeia; fail-closed sem estrutura |
| d | autorização | §3.4 — 3 capabilities sem concessão; alvo `collaborator`; meta não soberana; estado declarado pelo cliente |
| e | dependências legadas | `localStorage` (blob único), UUID de ciclo no browser, matrícula/nome, `localWorld` DEV |
| f | riscos de concorrência | last-write-wins no blob; sem versão; duas abas sobrescrevem; retry duplica histórico |
| g | riscos de multiusuário | aprovação e progresso concorrentes; decisões por `funcao` textual; auditoria sem autoria soberana |
| h | dual-read/dual-write/fallback | **dual-write não existe** (é o inverso: acervo local **sem** contraparte remota); fallback silencioso existe via `localWorld` em DEV |
| i | contratos a reutilizar | §10 (padrões da F5-09: UUID, trilha append-only, `expected_version`, idempotência, lock por organização, RLS policy-antes-do-grant, Edge `index/core/contrato`, adapter fail-closed) |
| j | dívidas fora do escopo | §2 — F5-11, F5-07 §13.6, F5-08, nota de avaliação, `RelatoriosPage` |

## 5. Problemas e resíduos a resolver pela F5-10

1. **Construção, não troca de fonte:** não há backend; será preciso **construir +
   backfill** de um acervo sem tenant, sem autoria confiável e com ids fabricados.
2. **Duas identidades de ciclo incompatíveis:** `Meta.cicloId` (UUID local)
   ≠ `evaluation_cycles.id` (UUID soberano), **sem bridge**; `cicloAvaliacaoStorage`
   ainda **fabrica** ciclos no caminho de leitura ⇒ metas órfãs por construção.
3. **Autorização inoperante em produção:** `goal.*` sem concessão e mundo
   sintético ⇒ DENY; em DEV concede `goal.write`+SELF a qualquer ativo.
4. **Estado autorizativo dentro do objeto mutável do cliente** (aprovações +
   histórico), com idempotência por *early-return* local.
5. **Regra de negócio duplicada** (limite em serviço e UI; relação de aprovação
   no serviço e no engine; assimetria entre os dois ramos de
   `metaStorage.aprovarMeta` — o ramo do gerente recomputa a estrutura, o do
   coordenador recebe pronta).
6. **Consumidores arrastam metas** com resoluções de ciclo diferentes (`(ano,numero)`,
   `cicloId` local, `id` de URL).

## 6. Modelo soberano proposto

### 6.1 Identidade

- **`evaluation_goals.id` (uuid, PK)** é a identidade canônica da meta.
- `(ano, numero)` e `colaboradorMatricula`/`nome` passam a **rótulos/projeção**,
  nunca identidade, chave de leitura ou autorização.
- Vínculos por **UUID**: `organization_id`, `cycle_id` (FK para
  `evaluation_cycles`), `collaborator_id` (FK para `collaborators`).
- A identidade **nunca** é gerada pelo cliente: quem cria é a RPC/Edge
  (D22/F5-09 §5 é o precedente).

### 6.2 Tabelas propostas (aditivas; nenhum objeto da F5-09 alterado)

```
public.evaluation_goals
  id uuid pk
  organization_id uuid not null            -- tenant da LINHA (autoridade)
  cycle_id uuid not null                   -- FK composta com organization_id
  collaborator_id uuid not null            -- dono da meta (FK composta)
  tipo text not null                       -- NEGOCIO_PROJETO | INDIVIDUAL
  descricao text not null, kpi text not null, valor_alvo text not null
  status text not null default 'EM_ANDAMENTO'   -- EM_ANDAMENTO | ATINGIDA | NAO_ATINGIDA
  resultado_atual text, progresso_percentual numeric(5,2),
  data_ultimo_acompanhamento timestamptz,
  resultado_final text, atingida boolean, data_fechamento timestamptz,
  excluida boolean not null default false, data_exclusao timestamptz,
  version integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()

public.evaluation_goal_approvals         -- aprovação como FATO, não como campo do objeto
  id uuid pk, organization_id uuid not null, goal_id uuid not null,
  papel text not null,                     -- COORDENADOR | GERENTE
  actor_membership_id uuid not null,       -- autoria soberana (FK composta)
  decidido_em timestamptz not null default now(), motivo text,
  revogado_em timestamptz, revogado_motivo text

public.evaluation_goal_events            -- trilha append-only (mesmo desenho de cycle_events)
  id uuid pk, organization_id uuid not null, goal_id uuid not null,
  event_type text not null check (in ('CRIADA','EDITADA','PROGRESSO_ATUALIZADO',
    'FINALIZADA','EXCLUIDA','APROVACAO_COORDENADOR','APROVACAO_GERENTE','APROVACOES_INVALIDADAS')),
  actor_membership_id uuid not null, reason text,
  operation_id uuid not null, payload_hash text not null,
  before_value jsonb, after_value jsonb, created_at timestamptz not null default now(),
  unique (organization_id, operation_id)

public.evaluation_cycle_goal_limits      -- limites por ciclo (substitui campos locais do ciclo)
  id uuid pk, organization_id uuid not null, cycle_id uuid not null,
  tipo text not null, quantidade integer not null check (quantidade >= 0),
  unique (cycle_id, tipo)
```

**Notas de integridade (padrões da F5-09 que se aplicam):**

- **Unicidade parcial proposta:** `unique (organization_id, cycle_id, collaborator_id, tipo)
  where excluida = false` — uma meta viva por (ciclo, dono, tipo), espelhando
  `uq_evaluation_cycles_org_ativo`.
- **Limite verificado no banco, não no cliente:** uma função de guarda
  (`goal_limite_disponivel(...)`) ou `CHECK` via trigger na inserção/reativação;
  a UI continua consultando para UX.
- **Exclusão nunca física:** `DELETE`/`TRUNCATE` revogados (D9 é precedente).
- **FKs compostas com `organization_id`** em todas as tabelas, para o tenant do
  evento/aprovação nunca divergir do tenant da meta.

## 7. Lifecycle soberano proposto

| Transição | Origem | Capability | Pré-condições |
|---|---|---|---|
| criar | — | `goal.write` (SELF) ou administrativo (ver Q3) | ciclo `ATIVO` **da linha**; limite do tipo disponível; sem sobreposição de unicidade parcial |
| editar (conteúdo) | `EM_ANDAMENTO` | `goal.write` (SELF) | `expected_version`; **invalida aprovações** (evento `APROVACOES_INVALIDADAS`) |
| atualizar progresso | `EM_ANDAMENTO` | `goal.write` (SELF) | `expected_version` |
| finalizar | `EM_ANDAMENTO` | `goal.write` (SELF) + aprovações vigentes exigidas pelo tipo | `expected_version`; `resultadoFinal`/`atingida`; **não** reabre |
| excluir (soft) | `EM_ANDAMENTO`/finalizada | `goal.write` (SELF) ou administrativo | `expected_version`; motivo; nunca físico |
| aprovar (coordenador) | meta viva, ciclo `ATIVO` | `goal.approve` + relação soberana | não é o dono; é o nível **intermediário** da cadeia (Q4) |
| aprovar (gerente) | idem | `goal.approve` + relação soberana | é a **raiz** da cadeia do dono no ciclo (Q4) |
| invalidar aprovações | disparado por edição relevante, mudança de estrutura do dono no ciclo ou correção de período | sistema (RPC) | registra evento, nunca apaga a aprovação anterior |

**Regras de estado derivadas (proposta):** o `status` **não** guarda aprovação.
“Aprovada” = existência de aprovação vigente (não revogada) por papel, derivada
da tabela de aprovações; isso elimina o estado autorizativo dentro do objeto.

## 8. Limites/configuração por ciclo

- Hoje: `CicloAvaliacao.quantidadeMetasNegocio/quantidadeMetasIndividuais` no
  acervo local; o P8 removeu esses campos da tela de ciclos ✓.
- Proposta: tabela `evaluation_cycle_goal_limits` (§6.2), escrita pelo mesmo
  caminho administrativo do ciclo (`cycle.manage`/D19) e **lida** por metas.
- **Alternativa (Q5):** manter a configuração dentro do ciclo soberano (colunas
  em `evaluation_cycles` ou `evaluation_config_versions`) — exigiria migration
  sobre objeto da F5-09; a tabela nova é estritamente aditiva.

## 9. Aprovações e invalidação

- Aprovação é **fato auditável**: linha em `evaluation_goal_approvals` + evento
  append-only na trilha, com autoria **soberana** (membership do ator
  verificado) — nunca `autorMatricula`/`autorNome` do cliente.
- **Revogação** = `revogado_em` + evento de invalidação; histórico preservado.
- **Quando invalidar (proposta):** edição de conteúdo relevante (descrição, KPI,
  valor alvo, tipo), mudança de dono/estrutura vigente do dono no ciclo, e
  correção de período do ciclo. Mudança de progresso **não** invalida.
- **Quem é “coordenador”/“gerente”:** resolução **relacional** na data do ciclo
  (F3-09/F5-08 — `organizacao_resolver_gestor_direto`/responsável vigente);
  proibido decidir por `funcao`/cargo textual. A regra do nível intermediário
  (`metaExigeAprovacaoCoordenador`) é preservada como **semântica**, mas
  resolvida no servidor.
- **Fail-closed:** sem evidência estrutural, a aprovação do coordenador é
  **exigida** (preserva o comportamento atual) e a do gerente é negada.

## 10. Autorização proposta

- **Capabilities:** reutilizar `goal.read`, `goal.write`, `goal.approve`
  (nenhuma capability nova — D20 é precedente). Mapeamento proposto:
  criar/editar/progresso/finalizar/excluir ⇒ `goal.write`; aprovar ⇒ `goal.approve`;
  ler ⇒ `goal.read`. **Alternativa e risco** se o produto exigir granularidade
  (Q1): novos códigos quebrariam os espelhos `Capability.ts`,
  `catalogoCapabilities.ts`, `capabilityTarget.ts` e o contador do validador P9.
- **Concessão em produção** é decisão explícita (Q2): sem role/bundle que
  conceda `goal.*`, a F5-10 nasceria inacessível; conceder ao bundle `admin`
  daria leitura de metas de terceiros a ADMIN (contra
  `.ai/architecture-rules.md` §2). Proposta: **metas próprias** por vínculo
  (SELF) + `goal.approve` por **configuração explícita** (como
  `cycle.cancel`/`reopen`/`period.correct` ficaram fora do bundle na F5-09).
- **Alvo autorizável:** promover `goal` a **tipo soberano** (Q3): registrar em
  `TIPOS_RECURSO_SOBERANOS`, exigir **UUID canônico**, adicionar `goal` em
  `resolveTargetTenant` e um `carregarRecurso` real de meta (linha com
  `organization_id` + `status`) — é o mecanismo já usado para `cycle`.
- **`domainState`:** derivado **da linha soberana** (status da meta + status do
  ciclo lido do banco), com fonte única compartilhada entre adaptador e
  enforcement (precedente: `estadoDominioCiclo.ts` + `contextoAutorizacao.ts`).
- **Scopes:** SELF para o dono; hierarquia (unidade/descendentes) para
  aprovação, conforme a estrutura vigente no ciclo.

## 11. RLS e fronteira

- `evaluation_goals`: RLS habilitada; **policy de SELECT own-tenant** via
  `public.user_has_active_membership(organization_id)` **antes** do grant;
  `grant select` mínimo a `authenticated`; **nenhuma** policy de escrita;
  `service_role` sem `DELETE`/`TRUNCATE`.
- `evaluation_goal_approvals` e `evaluation_goal_limits`: mesma doutrina
  (leitura own-tenant para aprovações/limites; escrita só pelo executor).
- `evaluation_goal_events`: **deny-by-default integral** (sem policy), `revoke all`
  e apenas `select, insert` para `service_role`, com os **3 triggers** de
  imutabilidade (UPDATE/DELETE/TRUNCATE), inclusive contra owner/`service_role`.
- Cross-tenant: FK composta com `organization_id` + RLS + revalidação na RPC
  (defesa em profundidade; a RLS é a barreira).

## 12. Concorrência, versão e idempotência

- `version integer` em `evaluation_goals` + `p_expected_version` em toda
  mutação ⇒ `F5_10_CONFLICT` sem overwrite silencioso.
- **Lock por organização:** a família de metas precisa de chave normativa. Duas
  opções (Q6): (a) **reusar** `evaluation_cycles:<org>` (uma chave para os dois
  domínios do ciclo, evita deadlock entre RPC de ciclo e de meta); (b) criar
  `evaluation_goals:<org>` — exigiria catalogação explícita na guarda P6-6 da
  F5-08. **Recomendação: (a)**.
- **Idempotência:** `unique (organization_id, operation_id)` na trilha +
  `payload_hash` SHA-256 **derivado server-side** (desvio de `p_payload_hash`
  já ratificado em P2–P4). `operationId` é **chave de idempotência**, nunca
  identidade funcional.
- **Aprovações concorrentes:** a unicidade parcial `(goal_id, papel) where
  revogado_em is null` garante um único aprovador vigente por papel; segunda
  aprovação ⇒ CONFLICT.

## 13. Contrato Edge/RPC

- **RPCs propostas** (todas `SECURITY INVOKER`, `search_path = public`, `EXECUTE`
  só `service_role`, com preflight e guarda final fail-closed — modelo
  `20260916000000_f5_09_cycle_rpc.sql`):
  `meta_criar`, `meta_editar`, `meta_atualizar_progresso`, `meta_finalizar`,
  `meta_excluir`, `meta_aprovar` (papel derivado do ator), `meta_invalidar_aprovacoes`,
  `meta_definir_limites_do_ciclo`.
- **Edge nova** `supabase/functions/metas` (D25: uma Edge por domínio) com a
  ordem `método → JWT (auth.getUser) → forma com allowlist estrita → tenant
  revalidado → gate por operação (sem default) → execução com service_role e
  ator verificado → resposta/erro público`, reusando o trio
  `index`/`core`/`contrato` e o **contrato transportável único** compartilhado
  com o cliente (`src/infrastructure/supabase/ciclos/contrato.ts` é o modelo).
- **Adapter de cliente fail-closed** (modelo `edgeCiclos.ts`): transporte,
  `error` no corpo, 2xx fora do contrato e código desconhecido **nunca** viram
  sucesso.
- **Leitura** continua por **RLS/PostgREST** (não criar RPC de leitura, salvo
  necessidade provada — a F5-09 declarou essa mesma pendência).
- Guardas novas: contrato Edge→RPC (nomes/args exatos) e grafo de imports da Edge.

## 14. Cutover do frontend e eliminação do `localStorage`

1. **Leitura**: `MinhasMetasPage` e `AcompanhamentoMetasPage` passam a ler de
   porta soberana (repositório RLS), com `ciclo_id` **da URL/estado soberano**,
   nunca `getCicloAtivo()` local.
2. **Mutação**: tudo pelo controlador soberano → Edge `metas` → RPC; nenhuma
   escrita em `localStorage` (o `metaStorage` deixa de ser autoridade).
3. **Backfill (Q7)** — o ponto mais delicado: as metas locais apontam para
   `cicloId` **fabricado no browser**, sem bridge. Proposta:
   - mapear por `(organization_id, ano, numero)` para o `evaluation_cycles.id`
     soberano **quando o ciclo existir** (o `(ano,numero)` já está denormalizado
     na meta);
   - metas cujo ciclo **não** existir no soberano entram em **relatório de
     quarentena** (não migrar, não inventar ciclo, não gravar em `localStorage`);
   - `colaboradorMatricula` → `collaborators.id` por `collaborator_identifiers`
     (business code) com **falha explícita** quando não resolver;
   - executar **uma vez**, com `operation_id` determinístico por meta e
     evidência de contagem antes/depois; sem dual-write permanente.
4. **Legado**: `metaStorage` vira LEITURA transitória para o backfill e depois é
   removido do caminho funcional; nenhum fallback é mantido.
5. **Consumidores de arrasto** (feedback, PDF, fechamento, impacto da correção)
   passam a resolver ciclo por UUID soberano — o mesmo caminho do P8.

## 15. Estratégia de testes e validação integrada

- **SQL (job `supabase-local`)**: cenário isolado insert-once + validador com
  `[PASS]`/`[FAIL]` e preflight/guarda final; cobrindo limites, unicidade
  parcial, trilha append-only (UPDATE/DELETE/TRUNCATE negados), aprovações e
  invalidação, cross-tenant/IDOR por UUID, stale `expected_version`,
  idempotência, rollback de operação multi-escrita e RLS/ACL.
- **Concorrência real entre duas sessões** (padrão da F5-10/P9 — arquivos
  16/17/18): duas sessões editando a mesma meta; a perdedora deve terminar em
  `F5_10_CONFLICT` depois de **esperar o lock**.
- **TS/node**: Policy Engine (matriz capability × status × relação), fronteira
  soberana (UUID canônico, tenant divergente, membership revogada), porta do
  cliente (fail-closed) e guardas estáticas anti-`localStorage`/anti-UUID-no-browser.
- **Ajuste obrigatório de testes existentes**: os invariantes de “nenhuma
  antecipação de F5-10” (`p9MatrizIntegrada.test.ts`, `15-validar-f5-09-p9.sql`)
  são **invertidos** pela F5-10 e devem ser atualizados na atividade, de forma
  explícita, junto com `metaStorage.test.ts`, `AcompanhamentoMetasPage.test.tsx`,
  `estruturaUiSeguranca.test.ts` (listas de exceção) e o teste de paridade de
  `authorizationPolicy.test.ts:909-919`.

## 16. Riscos

| # | Risco | Severidade | Mitigação proposta |
|---|---|---|---|
| R1 | Backfill sem bridge de ciclo ⇒ metas órfãs | **alta** | mapear por `(org, ano, numero)`; quarentena explícita; nunca fabricar ciclo |
| R2 | `goal.*` inacessível em produção (DENY) | **alta** | decidir concessão (Q2) antes da P4; teste de ALLOW real no CI |
| R3 | Estado autorizativo no cliente virar “verdade” no cutover | **alta** | aprovações como fato no banco + invalidação auditada |
| R4 | Regra de negócio duplicada (limite/aprovação) | média | fonte única no banco + projeção para UX |
| R5 | Consumidores de arrasto com identidade de ciclo heterogênea | média | cutover por UUID soberano; corrigir `impactoCorrecaoPeriodoCiclo` na mesma atividade |
| R6 | Lock novo causando deadlock com RPCs de ciclo | média | reusar a chave `evaluation_cycles:<org>` (Q6) |
| R7 | Guardas de “não antecipar F5-10” quebrarem o CI | baixa | atualizar os validadores na própria atividade (declarado) |
| R8 | Escopo crescer para observações (F5-11) | média | `observation.*` intocado; nenhuma tabela de observação |

## 17. Decisões propostas (para ratificação)

- **D1** — identidade canônica = `evaluation_goals.id` (uuid); `(ano,numero)` e
  matrícula são rótulos.
- **D2** — aprovação é **fato auditável em tabela própria**, nunca campo do
  objeto nem status.
- **D3** — `status` da meta não representa aprovação; “aprovada” é derivado.
- **D4** — limites por ciclo em tabela aditiva própria.
- **D5** — exclusão apenas lógica (D9 da F5-09 preservado).
- **D6** — reuso das 3 capabilities existentes (`goal.read/write/approve`), sem
  capability nova.
- **D7** — `goal` promovido a tipo soberano (UUID canônico, `carregarRecurso`).
- **D8** — trilha append-only `evaluation_goal_events` com `operation_id` único
  por organização e `payload_hash` server-side.
- **D9** — `expected_version` em toda mutação.
- **D10** — lock por organização **reusando** a chave da família de ciclos
  (pendente Q6).
- **D11** — Edge própria `metas` (D25), com contrato transportável único.
- **D12** — leitura por RLS/PostgREST; nenhuma RPC de leitura nova.
- **D13** — autoria soberana (membership do ator verificado) em toda trilha.
- **D14** — legitimidade de aprovação resolvida por **hierarquia relacional**
  vigente no ciclo (F3-09); proibido `funcao`/cargo textual.
- **D15** — sem dual-write permanente e sem fallback funcional para `localStorage`.

## 18. QUESTÕES PARA DECISÃO

> Formato: problema → alternativas → recomendação. **Não decidir silenciosamente.**

**Q1 — Granularidade das capabilities.** (a) reusar `goal.read/write/approve`;
(b) criar `goal.create/edit/finalize/delete`. *Recomendação:* **(a)** — D20
(“nenhuma capability nova”) e evita tocar 3 espelhos TS + o contador do validador
P9; a distinção fina fica no estado/capability do recurso.

**Q2 — Concessão em produção.** (a) `goal.read/write` no bundle `admin`;
(b) metas próprias por vínculo (SELF) + `goal.approve` só por configuração
explícita; (c) role de sistema nova. *Recomendação:* **(b)** — (a) daria a ADMIN
leitura de metas de terceiros, contra `.ai/architecture-rules.md` §2.

**Q3 — Tipo de alvo autorizável.** (a) promover `goal` a soberano
(`{type:"goal", id:UUID}`); (b) manter `{type:"collaborator", id:<dono>}`.
*Recomendação:* **(a)** — (b) mantém meta fora do enforcement e o tenant da meta
nunca é derivado do recurso; (a) exige `resolveTargetTenant` + `carregarRecurso`.

**Q4 — Fonte da relação de aprovação.** (a) raiz/intermediário da cadeia
relacional vigente no ciclo (F3-09); (b) cargo/função textual (status quo em
`AcompanhamentoMetasPage`). *Recomendação:* **(a)**, com fail-closed quando a
estrutura não for resolvível (preserva `metaExigeAprovacaoCoordenador`).

**Q5 — Onde ficam os limites por ciclo.** (a) tabela aditiva
`evaluation_cycle_goal_limits`; (b) colunas em `evaluation_cycles` (objeto da
F5-09). *Recomendação:* **(a)** — (b) mexe em contrato fechado de outra fase.

**Q6 — Chave de advisory lock.** (a) reusar `evaluation_cycles:<org>`;
(b) criar `evaluation_goals:<org>`. *Recomendação:* **(a)** — evita deadlock
entre RPC de ciclo e de meta; (b) exigiria catalogação explícita na guarda P6-6.

**Q7 — Backfill das metas locais.** (a) migrar só o que resolve por
`(org, ano, numero)` → UUID soberano, resto em quarentena; (b) migrar tudo
fabricando ciclos; (c) descartar o acervo local. *Recomendação:* **(a)** — (b)
fabrica identidade (proibido); (c) perde dado do usuário sem trilha.

**Q8 — Metas de terceiros (gestor/coordenador).** O gerente pode **criar/editar**
meta do liderado, ou só **aprovar**? O legado só permite ao dono escrever e ao
gestor aprovar. *Recomendação:* manter SELF para escrita; gestor/coordenador
apenas aprovam e leem (ampliar exige decisão explícita).

**Q9 — Progresso parcial e arredondamento.** `progressoPercentual` é livre
(0–100) ou derivado de `resultadoAtual` vs `valorAlvo` (que é texto)? *Recomendação:*
manter numérico 0–100 informado pelo dono no primeiro momento e **não** inferir
de texto (o `valorAlvo` é `string` hoje); derivação fica como evolução.

**Q10 — Finalização exige aprovações?** (a) só exige para `NEGOCIO_PROJETO`;
(b) exige para ambos; (c) não exige. *Recomendação:* decidir com o produto;
tecnicamente **(a)** preserva o comportamento atual do coordenador e mantém
`ATINGIDA/NAO_ATINGIDA` independente de aprovação.

**Q11 — Correção de período do ciclo invalida aprovações?** *Recomendação:* sim,
quando o período mudar o ciclo de referência — com evento
`APROVACOES_INVALIDADA` (conforme §6.2) e sem apagar histórico.

**Q12 — Limite de metas: bloqueia ou alerta?** Hoje o serviço **bloqueia** a
criação acima do limite e a UI também. *Recomendação:* manter **bloqueio no
banco** (invariante) e alerta na UI.

## 19. Decomposição recomendada

> Derivada da arquitetura encontrada (não é a lista inicial: inclui P0 de
> contrato/backfill e P7 de validação integrada).

- **P0 — Contrato e decisões.** Ratificar Q1–Q12; registrar em
  `docs/F5-10-duvidas.md` (molde: `docs/F5-09-duvidas.md`). *Sem código.*
- **P1 — Schema, integridade e limites.** As 4 tabelas, FKs compostas, índices
  únicos parciais, `version`, triggers de `updated_at`, revokes/deny-by-default,
  preflight + guarda final fail-closed. *Inclui* o ajuste do validador P9
  (remoção do guarda de “não antecipar metas”) e o validador P1.
- **P2 — RPCs de operações da meta.** `meta_criar/editar/atualizar_progresso/
  finalizar/excluir` + `meta_definir_limites_do_ciclo` (INVOKER, EXECUTE só
  `service_role`, `expected_version`, idempotência, lock, eventos).
- **P3 — Aprovações.** `meta_aprovar` + `meta_invalidar_aprovacoes`, tabela de
  aprovações, resolução relacional coordenador/gerente, regras de invalidação.
- **P4 — Autorização.** `goal` como tipo soberano, `domainState` de meta com
  fonte única, `resolveTargetTenant`, mapa capability×status×relação, RLS de
  leitura e a **decisão de concessão** (Q2) com teste de ALLOW real.
- **P5 — Edge e cliente.** `supabase/functions/metas` (trio + contrato),
  contrato transportável compartilhado, adapter fail-closed, guardas
  Edge→RPC/import-graph.
- **P6 — Cutover do frontend e backfill.** Porta soberana de leitura, controlador
  de mutações, telas (`MinhasMetasPage`, `AcompanhamentoMetasPage`), consumidores
  de arrasto (feedback, detalhe, PDF, fechamento, correção de período),
  **backfill com quarentena** (Q7) e remoção do `localStorage` do caminho funcional.
- **P7 — Validação integrada.** Matriz de cenários + concorrência real entre duas
  sessões + revisão de todas as guardas/regressões P1–P8, no molde
  `docs/F5-09-p9-matriz-integrada.md`.

## 20. Definição de pronto (DoD)

- Container de metas no PostgreSQL com RLS own-tenant e escrita fechada.
- Nenhuma autoridade funcional de meta no `localStorage`.
- `goal.*` **decidível** em produção por caminho canônico (não por mundo DEV).
- Trilha append-only com autoria soberana, `operation_id` e `payload_hash`.
- Concorrência real provada entre duas sessões; `expected_version` e rollback
  comprovados.
- Cutover das telas e dos consumidores de arrasto com ciclo por UUID soberano.
- Backfill executado com evidência de contagem e quarentena explícita.
- Gates do projeto verdes (focados, suíte completa, build, lint, tsc,
  `git diff --check`, bateria SQL na ordem do CI) no SHA auditado.
- F5-11 **não** antecipada; D1–D28 da F5-09 não reabertas sem evidência nova.

---

### Anexo A — Como esta auditoria foi feita

Varredura read-only por conteúdo (`meta`, `Meta`, `metaStorage`, `goal`, `peso`,
`progresso`, `aprovacao`, `coordenador`, `gerente`, `limite`,
`quantidadeMetas`) em `src/`, `supabase/` e `docs/`, mais leitura integral de
`src/types/Meta.ts` e das partes de `src/services/metaStorage.ts` relevantes a
limite, ciclo ativo, autorização e aprovação, e conferência dos padrões da
F5-09 nas migrations `20260915/16/17/18/19/21*`. Buscas que resultaram vazias
(tabela de metas, `MetaProgresso`, `aprovacaoMeta`, peso de meta) estão
declaradas no §3.7 com os termos usados. Nenhum `db reset`, `npm`, teste ou
alteração de código funcional foi executado.
