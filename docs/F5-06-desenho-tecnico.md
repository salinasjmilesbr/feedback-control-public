# F5-06 — Avaliações no PostgreSQL (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de análise e desenho, sem código funcional**.
> Estado: **EM REVISÃO** — baseline reconstruída, modelo proposto, `D1–D14`
> **PROPOSTAS** e `Q1–Q8` **ABERTAS** (§14/§15). **Nenhuma implementação antes do
> fechamento das questões.**
>
> Fase: 5 — Identidade e Multiusuário · Atividade: F5-06 · Issue **#103**
> (`[F5-06] db(evaluation): migrar avaliações, participantes e cálculo para PostgreSQL`)
> Base: `main` (F5-01…F5-05 concluídas; F5-05 mergeada via PR #172)
> Leitura de referência: `docs/F5-01…F5-05-desenho-tecnico.md`, `docs/F4-0x-desenho-tecnico.md`

---

## 1. Objetivo e limites

### 1.1 Objetivo

Definir, de forma implementável e sem ambiguidades, como o domínio de
**avaliações** migra de `localStorage` para PostgreSQL/Supabase preservando:
participantes e responsabilidades, notas/comentários, cálculo validado,
conclusão, pendências, reabertura, cancelamento, histórico/auditoria,
transparência do avaliado e isolamento por tenant — sob os contratos já fechados
de identidade (F5-01), vínculo (F5-02), organização ativa (F5-03),
roles/capabilities (F5-04) e ActorContext/ResourceContext (F5-05).

### 1.2 O que a F5-06 entrega (contrato)

1. Modelo de dados (tabelas, PK/FK, tenant ownership, constraints, estados,
   timestamps, invariantes).
2. Baseline funcional reconstruída do domínio atual (com evidência) e o mapa de
   divergências baseline × Issue #103 × contratos fechados.
3. Contrato de identidade/tenant, participantes, cálculo, workflow, autorização,
   transparência do colegiado e concorrência.
4. Estratégia de migração/cutover, testes/validadores, riscos, `D#` e `Q#`.

### 1.3 Fora de escopo (F5-06)

- **Importação de avaliações históricas reais** (explicitamente fora do escopo da
  Issue #103);
- **redesenho visual** da avaliação (Issue #103);
- migração dos demais domínios (`metas`, `observações`, `ciclos`, `colaboradores`)
  — atividades próprias; a F5-06 consome seus contratos, não os migra;
- alteração de contratos F3/F4/F5 fechados;
- hardening geral (F6), produção/hospedagem, observabilidade externa;
- implementação de código nesta rodada.

---

## 2. Baseline funcional reconstruída (evidência)

> Reconstruída a partir do código atual. **Não se assume** que o comportamento
> atual é automaticamente correto: as divergências com a Issue #103 e com os
> contratos fechados estão em §2.9.

### 2.1 Persistência atual

| Item | Evidência |
| --- | --- |
| Avaliações | `src/services/feedbackStorage.ts` — chave `feedback-control-feedbacks` (localStorage) |
| Ciclos | `src/services/cicloAvaliacaoStorage.ts` — `feedback-control-ciclos` |
| Colaboradores | `src/services/colaboradorStorage.ts` |
| Escala | `src/services/escalaAvaliacaoStorage.ts` — `feedback-control-escala-avaliacao` (global, não por organização) |
| Modelo de critérios | `src/data/modeloAvaliacao.ts` — **constante** (8 critérios, 25 subcritérios), não versionada em banco |
| Expectativa de cargo | `src/services/expectativaCargoStorage.ts` (snapshot copiado para a avaliação) |
| Histórico organizacional | `src/services/historicoOrganizacionalStorage.ts` (gestor na data/ciclo) |

### 2.2 Entidade `Feedback` (`src/types/Feedback.ts`)

- Identidade: `id` (string), **`colaboradorId: number` (matrícula)**, `colaboradorNome`.
- Vínculo ao ciclo: `ano: number` + `ciclo: 1 | 2 | 3` (não há `cycle_id`).
- Status: `RASCUNHO | PRONTA_PARA_FEEDBACK | CONCLUIDA | CANCELADA`.
- Notas: `notaMedia`, `criteriosDetalhados[]` (cada critério com `nota`,
  `subcriterios[]`, observações por “gerente”/“coordenador” **com autoria**) e
  cada subcritério com **colunas fixas por papel**: `notaGerente`,
  `notaCoordenador`, `notaColegiado`, `votosColegiado[]` (avaliador + nota +
  data), `notaFinal`.
- Conclusão/cancelamento/reabertura: `dataConclusao`, `motivoCancelamento`,
  `canceladoPor*`, `reaberturas[]` (`EventoReaberturaAvaliacao`).
- Pendências: `encerradaComPendencias` + `pendenciasEncerramento: string[]`.
- Legacy: `competencias[]`, `expectativaCargoSnapshot`.

### 2.3 Participantes (baseline)

`src/services/permissaoAvaliacao.ts`:

| Papel atual | Regra real (estrutura, não cargo) | Evidência |
| --- | --- | --- |
| **Gerente** | **raiz** da cadeia de `gestorDiretoMatricula` (sobe até não haver gestor), sobre o colaborador **efetivo no ciclo** | `encontrarGerenteResponsavel` |
| **Coordenador direto** | `gestorDiretoMatricula === ator` **e** o avaliado “usa estrutura analista” | `podeAvaliarComoCoordenador` |
| **Colegiado** | `avaliadoresColegiadoMatriculas` do avaliado **e** “usa estrutura analista” | `podeAvaliarComoColegiado` |

- “Usa estrutura analista” = `funcaoUsaEstruturaAvaliacaoAnalista(colaborador.funcao)`
  (`src/types/Colaborador.ts`) — **decisão de produto baseada em `funcao`**.
- Colaborador **efetivo no ciclo**: `getColaboradorEfetivoNoCiclo` (F3-09
  sucessão/histórico) — `src/services/historicoOrganizacionalStorage.ts`.
- Colegiado é 0..N (`avaliadoresColegiadoMatriculas: number[]`).

### 2.4 Cálculo (baseline exata)

`src/services/feedbackStorage.ts`:

```ts
mediaValores(valores) = { validos = valores finitos e > 0;
                          return validos.length ? soma(validos)/validos.length : 0 }
```

- subcritério: `notaColegiado = mediaValores(votos.nota > 0)` (se houver votos);
  `notaFinal = mediaValores([notaGerente, notaCoordenador, notaColegiado])`;
- critério: `nota = mediaValores(subcriterios.notaFinal)`;
- avaliação: `notaMedia = mediaValores(criterios.nota)`;
- **sem arredondamento** no cálculo (a formatação de 1 casa é de apresentação —
  `src/services/apresentacaoNota.ts`);
- **ausência/zero = “sem avaliação”** (nunca puxa a média para baixo);
- média do colegiado é **consolidada por subcritério** (média dos votos válidos)
  e entra como **uma** das três parcelas — não é média das médias por critério.

Escala (faixas por `limiteMinimo`) em `escalaAvaliacaoStorage.ts`; faixas de
relatório em `relatorioService.ts` (`getItemEscalaPorNota`).

### 2.5 Pendências e fechamento de ciclo

`src/services/progressoAvaliacao.ts` (`calcularProgressoAvaliacao`):

- `gerenteNecessario` = **existe um gestor com `funcao === "GERENTE"` na cadeia**;
- `coordenadorNecessario` = “usa estrutura analista” **e** `gestorDireto.funcao === "COORDENADOR"`;
- `colegiadoNecessario` = “usa estrutura analista” **e** há avaliadores de colegiado;
- pendências = notas faltantes por papel + `feedbackFinalGerente` / `feedbackFinalCoordenador` vazios;
- `completo = pendencias.length === 0`.

`src/services/cicloAvaliacaoStorage.ts` (`encerrarCiclo(id, quantidadePendencias)`)
registra `encerradoComPendencias`/`quantidadePendencias` no ciclo e
`src/services/cicloEquipeService.ts` grava **marcador permanente** por avaliação
(`encerradaComPendencias` + `pendenciasEncerramento[]`).

### 2.6 Workflow (baseline)

- `RASCUNHO → PRONTA_PARA_FEEDBACK → CONCLUIDA`; `CANCELADA` por fluxo auditado;
- avaliação **CONCLUIDA é imutável** em fluxo normal — garantido por
  `domainState` no adaptador do engine (`authorizationPolicy.ts`:
  `status !== "CONCLUIDA"`);
- **reabertura** excepcional com motivo obrigatório e autoria
  (`reaberturaAvaliacaoService.ts`), autorizada por capability
  `evaluation.reopen.manager` (alias canônico `evaluation.reopen`);
- **cancelamento** com motivo obrigatório e autoria
  (`cancelamentoAvaliacaoService.ts`), capability `evaluation.cancel.manager`
  (`evaluation.cancel`);
- uma única avaliação **não cancelada** por (colaborador, ano, ciclo) —
  `existeAvaliacaoNaoCanceladaNoCiclo` (erro na criação).

### 2.7 Autorização (baseline)

- Enforcement por `authorize()` do adaptador
  (`src/authorization/authorizationPolicy.ts`), alimentado pelo Policy Engine
  F4-03; recursos em `ResourceContext.ts` (`kind: "evaluation"` com
  `evaluatedCollaborator`, `cycle`, `evaluationStatus`);
- capabilities usadas: `evaluation.create/read/write/cancel/reopen`;
- o domínio **não** possui autorização paralela; as páginas usam `can()`.

### 2.8 Migração F5 já disponível para reuso

- identidade/tenant (F5-01/F5-03), vínculo `membership ↔ collaborator` (F5-02);
- capabilities × scopes e resolvers (F5-04);
- ActorContext/ResourceContext real + fronteira server-side (F5-05) — **o
  ResourceContext só cobre hoje recursos estruturais** (`collaborator`,
  `position`, `organizational_unit`); avaliação **não** é um alvo autorizável
  ainda (`TARGET_INVALID`), porque o domínio está em `localStorage` (D19 F5-05);
- estrutura F3 em Postgres: `collaborators`, `collaborator_status_periods`,
  `organizational_*`, `position_reporting_lines`, `occupations`,
  `temporary_responsibilities`, `collegiate_configurations(+_members)`,
  `collegiate_cycle_snapshots(+_positions/+_members)`,
  `cycle_evaluation_responsibilities`, `evaluation_succession_events`.

### 2.9 Divergências baseline × Issue #103 × contratos fechados

| # | Achado | Evidência | Consequência |
| --- | --- | --- | --- |
| G1 | **Papéis avaliativos fixos** no modelo de dados (`notaGerente`/`notaCoordenador`/`notaColegiado`) | `types/Feedback.ts` | A Issue #103 exige **participantes configuráveis** sem o literal Gerente+Coordenador+Colegiado ⇒ modelo precisa ser **orientado a participantes** |
| G2 | **Requisito de participante por `funcao`** (`funcao === "GERENTE"`, `funcao === "COORDENADOR"`, `funcaoUsaEstruturaAvaliacaoAnalista`) | `progressoAvaliacao.ts`, `permissaoAvaliacao.ts`, `types/Colaborador.ts` | Contratos F4/F5 proíbem autorização por cargo; aqui é regra funcional, mas a **fonte** precisa ser reexpressa sem cargo ⇒ **Q2** |
| G3 | **Duas regras diferentes** para “gerente responsável”: raiz da cadeia (`permissaoAvaliacao`) × gestor com `funcao === "GERENTE"` (`progressoAvaliacao`) | `permissaoAvaliacao.ts` × `progressoAvaliacao.ts` | Podem divergir (permissão permite, pendência não exige, ou vice-versa) ⇒ **Q3** |
| G4 | Identidade do avaliado é **matrícula numérica** | `Feedback.colaboradorId: number` | F5-02/F5-05 fixam `collaborators.id` (UUID) como identidade interna imutável ⇒ migrar para UUID (D3) |
| G5 | **Sem tabela de ciclos** no Postgres (ciclo = `ano + 1|2|3` no cliente) | migrations; `cicloAvaliacaoStorage.ts` | “Vínculo soberano ao ciclo” exige entidade de ciclo server-side ⇒ **Q1** |
| G6 | **Modelo de critérios é constante de código** (8 critérios/25 subcritérios) e a escala é global, sem versionamento em banco | `data/modeloAvaliacao.ts`, `escalaAvaliacaoStorage.ts` | “Configuração versionada” exige snapshot versionado por ciclo/avaliação ⇒ D5/D6 e **Q8** |
| G7 | Reabertura/cancelamento guardam apenas **arrays no próprio registro** (`reaberturas[]`, campos `canceladoPor*`) | `types/Feedback.ts` | Histórico/auditoria pede trilha append-only ⇒ D7 |
| G8 | `localStorage` é a **fonte de verdade** do domínio | `feedbackStorage.ts` | Issue #103: Supabase vira fonte única após validação (sem dual-write indefinido) ⇒ §11 |
| G9 | Não há **unicidade** de avaliação por (colaborador, ciclo) no armazenamento (checagem em código) | `existeAvaliacaoNaoCanceladaNoCiclo` | Concorrência exige constraint/índice único parcial no banco ⇒ D9 |
| G10 | Autorização de reabertura/cancelamento é “só gerente” por **scope DESCENDANTS** (matriz F4-09) | `docs/F4-09` §7.2; `reaberturaAvaliacaoService.ts` | Preservar via capability + scope (não reimplementar) ⇒ D10 |

---

## 3. Modelo de dados proposto

> Todas as tabelas novas são **tenant-rooted** (`organization_id`), com
> `ENABLE RLS`, policy pronta antes do grant, FKs `ON DELETE RESTRICT`,
> `created_at/updated_at/version` conforme F1-02, e **sem exclusão física** de
> histórico (D16 F4-08).

### 3.1 `evaluation_cycles` (vínculo soberano ao ciclo — ver Q1)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | `gen_random_uuid()` |
| `organization_id` | uuid NOT NULL | FK `organizations(id)` |
| `ano` | integer NOT NULL | CHECK faixa plausível |
| `numero` | smallint NOT NULL | CHECK `in (1,2,3)` |
| `status` | text NOT NULL | `PLANEJADO|ATIVO|ENCERRADO|CANCELADO` |
| `data_inicio` / `data_fim` | date | período do ciclo |
| `data_ativacao` / `data_encerramento` | timestamptz | — |
| `encerrado_com_pendencias` | boolean NOT NULL default false | espelho do fechamento |
| `quantidade_pendencias` | integer NOT NULL default 0 | — |
| `config_version_id` | uuid NULL | configuração **congelada na ativação** (D6) |
| `version`, `created_at`, `updated_at` | padrão F1-02 | — |

**Unique:** `(organization_id, ano, numero)`. **FK composta de tenant:**
`(id, organization_id)` única, para as FKs compostas das filhas.

### 3.2 `evaluation_config_versions` (+ critérios, subcritérios e faixas)

- `evaluation_config_versions`: `id`, `organization_id`, `version` (int),
  `checksum` (hash do conteúdo), `origem` (`SISTEMA|ORGANIZACAO`), `status`
  (`active|superseded`), timestamps; **unique** `(organization_id, version)`.
- `evaluation_config_criteria`: `id`, `config_version_id`, `code`, `name`,
  `position`, unique `(config_version_id, code)`.
- `evaluation_config_subcriteria`: `id`, `config_criterion_id`, `code`, `name`,
  `position`, unique `(config_criterion_id, code)`.
- `evaluation_config_scale_bands`: `id`, `config_version_id`, `nota` (1..5),
  `significado`, `descricao`, `limite_minimo numeric`, `cor`, `cor_fundo`,
  unique `(config_version_id, nota)`.

**Imutabilidade:** uma versão publicada é **imutável** (nova versão para mudar);
a avaliação referencia a versão usada (D5/D6).

### 3.3 `evaluations` (avaliação)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | — |
| `organization_id` | uuid NOT NULL | FK `organizations(id)` |
| `cycle_id` | uuid NOT NULL | FK composta `(cycle_id, organization_id)` → `evaluation_cycles` |
| `evaluated_collaborator_id` | uuid NOT NULL | FK composta `(…, organization_id)` → `collaborators` (**UUID**, D3) |
| `status` | text NOT NULL | `RASCUNHO|PRONTA_PARA_FEEDBACK|CONCLUIDA|CANCELADA` (D8) |
| `nota_media` | numeric(6,4) NULL | consolidada (D4/§6) |
| `config_version_id` | uuid NOT NULL | versão de configuração congelada (D6) |
| `expectativa_snapshot` | jsonb NULL | expectativa de cargo capturada na criação |
| `data_conclusao` | timestamptz NULL | — |
| `encerrada_com_pendencias` | boolean NOT NULL default false | marcador **permanente** (D11) |
| `motivo_cancelamento`, `cancelado_por_user_profile_id`, `data_cancelamento` | — | cancelamento auditado |
| `version`, `created_at`, `updated_at` | padrão | — |

**Unique parcial (D9):** um índice único parcial garante **no máximo uma
avaliação não cancelada** por `(organization_id, cycle_id, evaluated_collaborator_id)`
(`WHERE status <> 'CANCELADA'`), espelhando `existeAvaliacaoNaoCanceladaNoCiclo`.
**Unique:** `(id, organization_id)` (referência aditiva para FKs compostas).

### 3.4 `evaluation_participants` (participante/responsabilidade — snapshot)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | — |
| `evaluation_id` | uuid NOT NULL | FK composta → `evaluations` |
| `organization_id` | uuid NOT NULL | tenant |
| `role_type` | text NOT NULL | catálogo **de relação** (§5; D2) |
| `collaborator_id` | uuid NOT NULL | FK composta → `collaborators` (identidade interna imutável) |
| `user_profile_id` | uuid NULL | FK → `user_profiles` (quando houver conta vinculada) |
| `origem` | text NOT NULL | `ESTRUTURA|SUBSTITUICAO_TEMPORARIA|SUCESSAO|SNAPSHOT_CICLO` |
| `origem_ref_id` | uuid NULL | `temporary_responsibilities.id` / `evaluation_succession_events.id` |
| `status` | text NOT NULL | `active|revoked` (revogação no lugar) |
| `valid_from` / `valid_to` | timestamptz | vigência herdada da origem |
| `version`, `created_at`, `updated_at` | padrão | — |

**Unique:** `(evaluation_id, role_type, collaborator_id)`.
**Invariante:** ao menos um participante por avaliação criada (D1).
Participantes **0..N por papel** (colegiado 0..N) — sem colunas fixas por papel.

### 3.5 `evaluation_scores` (nota por participante × subcritério)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | — |
| `evaluation_id` | uuid NOT NULL | FK composta → `evaluations` |
| `organization_id` | uuid NOT NULL | tenant |
| `participant_id` | uuid NOT NULL | FK composta → `evaluation_participants` |
| `subcriterion_id` | uuid NOT NULL | FK → `evaluation_config_subcriteria` |
| `nota` | smallint NOT NULL | **CHECK `between 1 and 5`** (D4) — ausência = linha inexistente (nunca `0`) |
| `autor_user_profile_id` | uuid NULL | autoria |
| `data_avaliacao` | timestamptz NULL | — |
| `version`, `created_at`, `updated_at` | padrão | — |

**Unique:** `(participant_id, subcriterion_id)` (uma nota por participante por
subcritério). Sem exclusão física em avaliação concluída (D8/D11).

### 3.6 `evaluation_comments` (comentários)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | — |
| `evaluation_id`, `organization_id`, `participant_id` | — | FKs compostas |
| `escopo` | text NOT NULL | `CRITERIO|FINAL` |
| `criterion_id` | uuid NULL | obrigatório quando `escopo='CRITERIO'` (CHECK) |
| `texto` | text NOT NULL | CHECK `btrim(texto) <> ''` |
| `autor_user_profile_id`, `data` | — | autoria |
| `version`, `created_at`, `updated_at` | padrão | — |

**Unique:** `(participant_id, escopo, criterion_id)`.

### 3.7 `evaluation_events` (histórico/auditoria — append-only)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | — |
| `evaluation_id`, `organization_id` | — | FKs compostas |
| `event_type` | text NOT NULL | `CRIADA|CONCLUIDA|REABERTA|CANCELADA|PENDENCIA_MARCADA|NOTA_ALTERADA|COMENTARIO_ALTERADO|PARTICIPANTE_ALTERADO` |
| `actor_user_profile_id` | uuid NOT NULL | **autoria soberana** (server-side) |
| `motivo` | text NULL | obrigatório em `REABERTA`/`CANCELADA` |
| `payload` | jsonb NULL | antes/depois relevante |
| `created_at` | timestamptz NOT NULL | append-only |

**Regra:** sem `UPDATE`/`DELETE` (append-only; equivalente à trilha D18 F5-04);
`authenticated` sem DML direto.

### 3.8 `evaluation_pendencies` (pendências do fechamento — marcador permanente)

`id`, `evaluation_id`, `organization_id`, `codigo` (`NOTA_FALTANTE|FEEDBACK_FINAL_FALTANTE`),
`role_type`/`participant_id` (quando aplicável), `criterion_id`/`subcriterion_id`
(quando aplicável), `descricao`, `registrada_em`, `registrada_por_user_profile_id`.
**Append-only por fechamento** (novo fechamento ⇒ novas linhas; o histórico
anterior é preservado). Substitui o array de strings `pendenciasEncerramento`.

### 3.9 Invariantes de integridade (todas as tabelas)

1. `organization_id` NOT NULL em toda tabela do domínio; **FKs compostas**
   `(referencia_id, organization_id)` em todas as relações (cross-tenant por
   construção) — padrão F3/F4-01.
2. Nenhum FK para `job_roles`/`seniority_levels`/`cargo` (autorização/regra por
   cargo proibida — invariante F4-01/F4-09).
3. Status em catálogo fechado por CHECK; transições validadas por função/RPC
   (§10), não por trigger genérico.
4. `evaluation_scores.nota` ∈ [1,5]; ausência = linha inexistente (nunca `0`).
5. Avaliação **CONCLUIDA**: alterações de nota/comentário somente por reabertura
   auditada (D8).
6. Participante revogado mantém a linha (histórico) e **não** conta para
   pendência/participação ativa.
7. Uma avaliação não cancelada por (org, ciclo, colaborador) — índice único
   parcial (D9).

---

## 4. Identidade e tenant (contratos F5 preservados)

| Regra | Origem fechada |
| --- | --- |
| `auth.uid()` é a identidade soberana | F5-01 D1 |
| Identidade **interna imutável** do avaliado/participante = `collaborators.id` (**UUID**) — nunca matrícula/e-mail/nome | F5-02 D1/D4; `Feedback.colaboradorId` numérico é **legado** (G4) |
| `organization_id` derivado/validado **server-side** contra membership ativa; nunca do browser | F5-01 D6, F5-03 D1/D6 |
| Vínculo soberano ao **ciclo** por `cycle_id` do tenant (`evaluation_cycles`) | Issue #103; **Q1** |
| Vínculo ao colaborador por FK composta de tenant | F3/F4-01 |
| `actor_id`/`organization_id` do cliente **nunca** concedem autoridade | F5-03 D8, F5-05 D6/D20 |
| Cross-tenant ⇒ **DENY/fail-closed** | regras permanentes |
| Enforcement na **fronteira confiável server-side**; browser/React/hooks/services no browser = cliente | F5-05 D20 |

**Quem lê/escreve:** a avaliação é lida/escrita por RPC/Edge server-side
(fronteira confiável). O `localStorage` deixa de ser autoridade após o cutover
(§11).

---

## 5. Participantes (modelo sem papel fixo)

### 5.1 Catálogo de `role_type` (proposta — D2)

Semântica de **RELAÇÃO + responsabilidade**, nunca de cargo:

| `role_type` | Semântica (relação) | Baseline correspondente |
| --- | --- | --- |
| `GESTAO_CADEIA` | responsável pela **raiz** da cadeia de gestão do avaliado (§2.3) | “Gerente” |
| `GESTAO_DIRETA` | gestor **direto** do avaliado | “Coordenador direto” |
| `COLEGIADO` | membro de colegiado atribuído ao avaliado (0..N) | “Colegiado” |
| *(extensível por migration)* | outros responsáveis configuráveis | Issue #103 (“outros responsáveis”) |

- O catálogo é **fechado por migration** (não texto livre) e **não** referencia
  cargo; a existência de 0..N participantes por papel é intrínseca.
- A exigência de cada papel (obrigatório/opcional) é uma **regra de
  configuração da avaliação** — **Q2** (hoje derivada de `funcao`).

### 5.2 Snapshot

- `evaluation_participants` **é** o snapshot da avaliação: criado na abertura
  (§10, transacional) a partir das **fontes soberanas do ciclo**:
  `collegiate_cycle_snapshots(+_members)` e `cycle_evaluation_responsibilities`
  (F3-08/F3-09), com `origem` registrando a procedência.
- Mudanças estruturais posteriores **não** reescrevem o snapshot; novas
  responsabilidades/substituições vigentes geram **nova linha** (com vigência) ou
  revogação da anterior (`status='revoked'`), preservando histórico.
- Identidade do participante = `collaborator_id` (UUID) + `user_profile_id`
  quando houver conta vinculada (F5-02).

### 5.3 Sucessão e substituição temporária

- **Sucessão de avaliador** (F3-09): a avaliação referencia o snapshot do ciclo
  (`collegiate_cycle_snapshots`, `cycle_evaluation_responsibilities`,
  `evaluation_succession_events`); sucessão vigente após a abertura gera evento
  e ajuste de participante **auditado** (`evaluation_events`), nunca silencioso.
- **Substituição temporária** (F3-06/F4-05): o substituto é participante com
  `origem='SUBSTITUICAO_TEMPORARIA'` + `origem_ref_id` e **vigência**; fora da
  vigência não conta para pendência.
- **Sem cargo**: nenhuma decisão usa `funcao` (G2 ⇒ Q2).

### 5.4 Estrutura mudou depois da abertura do ciclo

| Situação | Comportamento contratado |
| --- | --- |
| Colaborador troca de gestor | Snapshot preservado; a avaliação continua com os participantes vigentes na abertura; eventual novo responsável entra como **nova linha** auditada |
| Gestor sai da empresa | Participante permanece (histórico); se a avaliação não estiver concluída, é necessário **novo participante** (RPC auditada) ou pendência permanente no fechamento |
| Colegiado alterado | Snapshot preservado; alterações exigem RPC auditada |
| Ciclo encerrado com avaliação incompleta | Marcador permanente (§3.8) + pendências; reabertura excepcional (§7) |

---

## 6. Cálculo

### 6.1 Decisões de preservação (baseline §2.4)

- notas válidas **1–5**; **ausência/zero = sem avaliação** (nunca puxa a média);
- `nota_colegiado(subcritério)` = **média dos votos válidos** dos participantes
  de colegiado **ativos** naquele subcritério;
- `nota_subcriterio` = média das notas **válidas** entre os participantes
  (na baseline: gerente + coordenador + colegiado consolidado);
- `nota_criterio` = média das `nota_subcriterio` válidas;
- `nota_media` = média das `nota_criterio` válidas;
- **sem arredondamento** no cálculo; formatação com 1 casa é de apresentação.

Com o modelo orientado a participantes (D1), a regra geral passa a ser:

```
nota_subcriterio = média das notas VÁLIDAS dos participantes ATIVOS que
                   pontuam naquele subcritério, com o colegiado previamente
                   CONSOLIDADO em UMA parcela (média dos seus votos válidos)
nota_criterio    = média das nota_subcriterio válidas
nota_media       = média das nota_criterio válidas
(ausência de qualquer nota válida ⇒ 0 / “sem avaliação”)
```

### 6.2 Onde o cálculo acontece

- **Fonte soberana:** o banco (notas persistidas). O cálculo é executado
  **server-side** em RPC/transação que grava `nota_media` como campo
  **derivado materializado** (para relatórios) **e** pode ser recomputado
  (função pura) para validação.
- O frontend **não** calcula a nota oficial; apenas exibe o valor persistido
  (UX pode pré-visualizar com a mesma função pura compartilhada).
- **Precisão:** `numeric(6,4)` para médias (suficiente para 3–4 casas sem erro
  binário); igualdade de paridade com a baseline por **tolerância explícita**
  (ex.: |Δ| ≤ 1e-9) nos testes.

### 6.3 Casos de borda (contratados)

| Caso | Comportamento |
| --- | --- |
| Colegiado vazio (0 membros) | A parcela “colegiado” **não existe**; média apenas das parcelas existentes |
| Participante sem nenhuma nota | Não entra em nenhuma média (não é zero) |
| Todos os participantes sem nota | `nota_media = 0` (“sem avaliação”) |
| Subcritério/critério desativado na configuração | Não participa do cálculo da avaliação que referencia aquela versão (D5/D6); avaliações existentes seguem a **sua** versão |
| Configuração alterada após a abertura | **Não afeta** a avaliação em curso (versão congelada — D6) |
| Nota fora de 1–5 | Rejeitada por CHECK + validação na RPC (nunca persiste) |

---

## 7. Workflow da avaliação

### 7.1 Estados e transições (D8)

```
RASCUNHO ──▶ PRONTA_PARA_FEEDBACK ──▶ CONCLUIDA          (fluxo normal)
   │                  │                   │
   └──────────────────┴───────────────────┴──▶ CANCELADA  (auditado, motivo)
                                          │
                            CONCLUIDA ──▶ RASCUNHO/PRONTA_PARA_FEEDBACK
                                          (REABERTURA excepcional, auditada)
```

| Transição | Pré-condições | Capability (F5-04) |
| --- | --- | --- |
| Criar avaliação | ciclo `ATIVO` (ou `PLANEJADO` se contrato permitir), avaliado ativo/elegível; sem outra avaliação não cancelada | `evaluation.create` |
| Preencher/editar | ciclo ≠ `CANCELADO`; status ∉ {`CONCLUIDA`,`CANCELADA`} | `evaluation.write` |
| Enviar para feedback | idem | `evaluation.write` |
| **Concluir** | pendências zeradas **ou** decisão explícita (`Q4`) | `evaluation.write` (**Q4**) |
| **Reabrir** | status `CONCLUIDA`; ciclo ≠ `ENCERRADO`/`CANCELADO`; motivo obrigatório | `evaluation.reopen` (scope da cadeia de gestão — preserva “GERENTE-only” F4-09) |
| **Cancelar** | status ≠ `CANCELADA`; ciclo ≠ `CANCELADO`; motivo obrigatório | `evaluation.cancel` (scope DESCENDANTS — preserva baseline) |
| Fechar ciclo | operação do ciclo (não da avaliação) | `cycle.manage` |
| Marcar pendência permanente | fechamento do ciclo com avaliação incompleta | operação do ciclo (transacional) |

- **Imutabilidade normal de CONCLUIDA** preservada (D8) — reforçada por RLS/RPC
  (não apenas `domainState` de aplicação).
- **Reabertura excepcional** grava `evaluation_events` (`REABERTA` + motivo +
  autor soberano) e limpa `data_conclusao` mantendo o histórico.
- **Cancelamento** grava `CANCELADA` + motivo + autor + `evaluation_events`.
- **Toda operação composta** (criar com participantes, concluir, reabrir,
  cancelar, fechar ciclo com pendências) é **transacional** (§10).

---

## 8. Autorização

### 8.1 Integração obrigatória (sem autorização paralela)

| Camada | Papel |
| --- | --- |
| **Policy Engine (F4-03)** | única decisão de autorização (ALLOW/DENY) |
| **F5-04 capabilities × scopes** | `evaluation.read/create/write/cancel/reopen` com escopos/alcance reais |
| **F5-05 ActorContext/ResourceContext** | ator real (`auth.uid`) + recurso **tenant-rooted** (a avaliação passa a ser um recurso de fonte soberana) |
| **RLS (F4-08)** | barreira de isolamento (tenant) independente |
| **`can()`** | somente UX |
| **Domínio** | regras de estado (imutabilidade, transições) via `domainState`/predicados — nunca autorização |

A F5-05 hoje recusa alvos não soberanos; após a F5-06, `evaluation` passa a ser
um `TargetRef` autorizável com `organization_id` derivado do recurso
(`ResourceContext` real), conforme D19/D22 da F5-05.

### 8.2 Mapeamento operação → capability (proposta, D10)

| Operação | Capability existente | Scope |
| --- | --- | --- |
| Ler avaliação de terceiro | `evaluation.read` | DIRECT_REPORTS/DESCENDANTS/ASSIGNED conforme relação |
| Ler a própria avaliação (SELF) | `evaluation.read` | SELF + `domainState` (somente `CONCLUIDA`) |
| Criar/editar/preencher | `evaluation.create` / `evaluation.write` | conforme relação |
| Concluir | `evaluation.write` | conforme relação (**Q4**) |
| Cancelar | `evaluation.cancel` | DESCENDANTS |
| Reabrir | `evaluation.reopen` | DESCENDANTS |
| Fechar ciclo com pendências | `cycle.manage` | ORGANIZATION |

**Nenhuma capability nova é proposta** neste documento; se alguma operação
relevante não couber no catálogo atual, será aberta como `Q#` (nenhuma
identificada até aqui).

---

## 9. Transparência e privacidade do colegiado

### 9.1 Regra preservada

- Avaliado **vê** a própria avaliação conforme a regra de transparência
  (baseline: `CONCLUIDA`; `domainState` SELF);
- Avaliado **vê a lista de membros do colegiado** (quando previsto);
- Avaliado **nunca** vê **voto/nota individual** de membro do colegiado — vê
  apenas a **parcela consolidada** do colegiado (`nota_colegiado`) quando a
  transparência permitir.

### 9.2 Garantia server-side (não apenas UI)

1. **Participantes** do colegiado são expostos por leitura **mínima** (nome do
   membro) via RPC/view dedicada;
2. **`evaluation_scores` individuais do colegiado nunca são retornados** para o
   avaliado: a leitura do avaliado usa uma projeção que expõe apenas
   `nota_media`, `nota_criterio`, `nota_subcriterio` e a parcela **agregada** do
   colegiado — nunca `participant_id` do colegiado com a nota;
3. RLS: o avaliado acessa apenas a sua avaliação (por `evaluated_collaborator_id`
   ligado à sua membership/F5-02); as linhas de `evaluation_scores` não são
   legíveis diretamente por `authenticated` (deny-by-default), somente via RPC
   server-side com projeção;
4. Notas/comentários de avaliação **não concluída** não são expostos ao avaliado
   (regra de transparência).

---

## 10. Concorrência e transações

| Risco | Proteção contratada |
| --- | --- |
| Duas avaliações não canceladas (mesmo colaborador/ciclo) | **índice único parcial** (§3.3) + verificação na RPC (erro de conflito) |
| Double-submit de criação | unique + RPC transacional idempotente por chave natural |
| Conclusão concorrente | RPC + `SELECT … FOR UPDATE` da avaliação; transição validada no servidor; segunda tentativa ⇒ conflito (não duplica evento) |
| Reabertura concorrente | idem (lock + estado `CONCLUIDA` obrigatório) |
| Gravação parcial de notas/comentários | **uma transação** para o lote da operação; falha ⇒ rollback total (sem estado parcial) |
| Mudança estrutural concorrente | participante é **snapshot**; alteração apenas por RPC auditada; sem reescrita implícita |
| Alteração de configuração durante a avaliação | configuração **congelada** na avaliação (D6); versão imutável |
| Fechamento de ciclo concorrente | RPC do ciclo com lock; marcador permanente idempotente |

**Operações que exigem RPC/função transacional server-side:** criar avaliação
(com participantes), gravar lote de notas/comentários, concluir, reabrir,
cancelar, fechar ciclo com pendências, e qualquer mutação de participante.
Nenhuma dessas operações é DML direto de `authenticated` (padrão F4-08 D7).

---

## 11. Migração / cutover

### 11.1 Princípios

- A F5-06 **não** importa avaliações históricas reais (fora de escopo da Issue);
- **Sem dual-write indefinido**: a convivência é por **leitura**, não por escrita
  dupla;
- Supabase vira **única fonte de verdade** ao final da validação.

### 11.2 Fases propostas (D12)

| Fase | Estado |
| --- | --- |
| 1. Schema + RPC + RLS + testes (sem tráfego real) | Supabase pronto; `localStorage` ainda autoridade |
| 2. **Paridade** — execução da mesma baseline de cálculo contra o novo modelo (fixtures sintéticas) e comparação com o resultado do código atual | evidência de paridade (tolerância explícita) |
| 3. **Cutover de escrita** — serviços passam a escrever **somente** em Supabase para avaliações **novas** (criadas após a data de corte) | `localStorage` **read-only** para o domínio |
| 4. **Cutover de leitura** — leitura de avaliações passa a ser server-side; `localStorage` deixa de ser consultado | Supabase = fonte única |
| 5. **Remoção** da autoridade local (código de leitura/escrita local do domínio removido; chave preservada apenas como legado morto até limpeza) | — |
| **Rollback técnico** | por ser aditivo, o rollback é **voltar a apontar a leitura/escrita para o local** enquanto não houver avaliações exclusivamente no banco; após o cutover de escrita, o rollback exige exportar o que foi criado no banco (documentar como limitação — ver Riscos) |

- Avaliações **pré-existentes** em `localStorage` permanecem visíveis no modo
  legado até a atividade de importação (fora de escopo), **sem** virar autoridade
  no novo caminho.

---

## 12. Testes e validadores (matriz mínima)

| Grupo | Cenários |
| --- | --- |
| **Cálculo** | médias por subcritério/critério/final; ausência/zero; colegiado vazio; participantes incompletos; sem arredondamento; paridade com a baseline (tolerância) |
| **Participantes** | gestão de cadeia/direta/colegiado 0..N; snapshot imutável; sucessão; substituição temporária com vigência; papel opcional |
| **Colegiado** | consolidação por subcritério; membro removido; votos parciais |
| **Conclusão** | pendências zeradas; imutabilidade após concluir; tentativa de edição ⇒ DENY |
| **Pendência** | fechamento incompleto ⇒ marcador permanente + pendências; idempotência |
| **Reabertura** | capability/scope corretos; motivo obrigatório; histórico preservado; concorrência |
| **Cancelamento** | motivo/autor; unicidade liberada para nova avaliação |
| **Concorrência** | criação duplicada; double-submit; conclusão/reabertura concorrentes; rollback de gravação parcial |
| **Unique constraints** | uma não cancelada por (org, ciclo, colaborador); uma nota por (participante, subcritério); um comentário por (participante, escopo, critério) |
| **Tenant/IDOR** | leitura/escrita cross-tenant ⇒ DENY; id de outro tenant; recurso inexistente |
| **RLS** | deny-by-default; policies por comando; `authenticated` sem DML; schema guard |
| **Capabilities/scopes** | cada operação mapeada (§8.2); escopo herdado da relação; revogação entre operações |
| **ActorContext/ResourceContext** | avaliação como recurso tenant-rooted (F5-05); cross-tenant DENY; sem tenant sintético |
| **Transparência** | avaliado vê agregado + lista de colegiado; **nunca** voto individual; avaliação não concluída invisível ao avaliado |
| **Regressão baseline** | fixtures sintéticas com os mesmos resultados esperados da baseline atual |

**Comandos obrigatórios:** `npm test`, `npm run build`, `npm run lint`,
`git diff --check`; **validadores Supabase locais** (cenário + validador SQL do
domínio, RLS/schema guard) e regressão dos validadores F4/F5 existentes.

---

## 13. Riscos

| Risco | Mitigação |
| --- | --- |
| Divergência de cálculo entre baseline e banco | paridade explícita com tolerância + fixtures da baseline (§12) |
| Modelo “orientado a participantes” perder semântica de papel | catálogo de `role_type` **de relação** + testes de equivalência por cenário |
| Regra por `funcao` sobreviver disfarçada | proibição de FK/campo de cargo; **Q2** fecha a fonte da estrutura |
| Snapshot de participantes ficar inconsistente com a estrutura | snapshot imutável + alterações só por RPC auditada + eventos |
| Duplicidade de avaliação sob concorrência | unique parcial + transação |
| Vazamento de voto individual do colegiado | projeção server-side + RLS + testes de transparência |
| Cutover com duas fontes | fases explícitas (§11) e proibição de dual-write |
| Configuração mudar no meio do ciclo | versão congelada por avaliação (D6) |
| Migração de ciclos fora de escopo bloquear a F5-06 | **Q1** decide a fronteira |
| `nota_media` materializada divergir do cálculo | recomputação server-side + teste de consistência |

---

## 14. Decisões propostas (D1–D14 — **PROPOSTAS**)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | **Modelo orientado a participantes** | Notas/comentários são por **participante** (linhas), não colunas fixas por papel; colegiado 0..N natural; atende “sem literal Gerente+Coordenador+Colegiado” (Issue #103, G1) | PROPOSTA |
| D2 | **`role_type` = relação, não cargo** | Catálogo fechado por migration com semântica de relação (`GESTAO_CADEIA`, `GESTAO_DIRETA`, `COLEGIADO`, extensível); nenhum FK/campo de cargo | PROPOSTA |
| D3 | **Identidade por UUID** | `evaluated_collaborator_id`/`participant.collaborator_id` referenciam `collaborators.id` (UUID imutável, F5-02); matrícula é legado (G4) | PROPOSTA |
| D4 | **Nota 1–5; ausência ≠ 0** | CHECK 1..5 em `evaluation_scores`; ausência = linha inexistente; agregação ignora ausências (preserva baseline §2.4) | PROPOSTA |
| D5 | **Configuração normalizada e imutável por versão** | Critérios/subcritérios/faixas em tabelas versionadas; versão publicada é imutável (nova versão para mudar) | PROPOSTA |
| D6 | **Versão congelada por avaliação** | A avaliação referencia a versão vigente na **abertura**; mudanças posteriores não afetam a avaliação em curso (preserva “configuração congelada após ativação”) | PROPOSTA |
| D7 | **Trilha append-only de eventos** | `evaluation_events` registra criação/conclusão/reabertura/cancelamento/pendência/alterações com **autoria soberana** (server-side) e motivo; sem UPDATE/DELETE | PROPOSTA |
| D8 | **Estados e transições preservados** | `RASCUNHO→PRONTA_PARA_FEEDBACK→CONCLUIDA`, `CANCELADA`, reabertura excepcional; **CONCLUIDA imutável**, reforçada por RPC/RLS | PROPOSTA |
| D9 | **Unicidade de avaliação não cancelada** | Índice único parcial `(organization_id, cycle_id, evaluated_collaborator_id) WHERE status <> 'CANCELADA'` (G9) | PROPOSTA |
| D10 | **Autorização reutiliza o catálogo F5-04** | Nenhuma capability nova; `evaluation.read/create/write/cancel/reopen` + scopes/relação; enforcement server-side; `can()` só UX | PROPOSTA |
| D11 | **Pendência permanente persistida** | `evaluation_pendencies` (append-only por fechamento) + `encerrada_com_pendencias`; preserva o marcador histórico (substitui o array de strings) | PROPOSTA |
| D12 | **Cutover em fases, sem dual-write** | Paridade → escrita → leitura → remoção da autoridade do `localStorage` (§11) | PROPOSTA |
| D13 | **Cálculo server-side e materializado** | Cálculo em RPC/transação server-side; `nota_media` materializada como derivado; frontend não calcula a nota oficial; precisão `numeric(6,4)`; sem arredondamento no cálculo | PROPOSTA |
| D14 | **Transparência do colegiado garantida no servidor** | Lista de membros exposta; **voto/nota individual nunca** retornado ao avaliado; projeção server-side + RLS | PROPOSTA |

---

## 15. Questões abertas (Q1–Q8)

> Abertas porque o repositório/Issue **não** trazem evidência suficiente para
> decisão segura. Cada uma traz contexto, alternativas, recomendação, impacto e
> risco.

### Q1 — Fronteira da entidade de ciclo na F5-06 — **ABERTA**

- **Contexto:** as avaliações referenciam ciclo por `ano + 1|2|3`; **não existe**
  tabela de ciclos no PostgreSQL (G5), enquanto a Issue #103 exige “vínculo
  soberano ao ciclo”.
- **Problema:** criar a entidade de ciclo aqui pode colidir com a atividade de
  migração de ciclos (correções de período, reabertura de ciclo, encerramento).
- **Alternativas:** (A) F5-06 cria `evaluation_cycles` **mínima** (ano, número,
  status, período, config congelada), sem a lógica completa de ciclo; (B) a
  entidade de ciclo é criada por atividade própria e a F5-06 fica bloqueada até
  lá; (C) avaliação referencia ciclo por `ano/numero` sem FK (rejeitada:
  contraria “vínculo soberano”).
- **Recomendação (Flash):** **(A)**.
- **Impacto:** desbloqueia a F5-06; exige que a atividade de ciclos **estenda**
  a tabela (aditivo), não a recrie.
- **Risco:** duplicação de modelagem se a atividade de ciclos divergir ⇒ mitigar
  com contrato explícito de extensão aditiva e reuso por FK.

### Q2 — Estrutura avaliativa sem cargo (fonte da exigência de participantes) — **ABERTA**

- **Contexto:** hoje a exigência de “coordenador direto” e “colegiado” depende de
  `funcaoUsaEstruturaAvaliacaoAnalista(funcao)` e de `funcao === "COORDENADOR"`
  (G2).
- **Problema:** a Issue #103 exige participantes **configuráveis conforme
  estrutura**, sem depender do literal de papéis/cargos; os contratos F4/F5
  proíbem autorização por cargo.
- **Alternativas:** (A) `estrutura_avaliacao` explícita escolhida/snapshotada na
  avaliação (ex.: `GESTAO_CADEIA+DIRETA+COLEGIADO` vs `GESTAO_CADEIA`); (B)
  derivar de `job_roles`/`seniority_levels` (catálogo F3-02) — reintroduz cargo
  como fonte; (C) configuração por organização (tabela de política de estrutura)
  versionada.
- **Recomendação (Flash):** **(A) + (C)**: a estrutura é uma **configuração
  versionada por organização** e o resultado é **snapshotado** na avaliação; o
  `job_role` nunca é consultado em runtime.
- **Impacto:** define o modelo de participantes e as pendências; afeta §5 e §6.
- **Risco:** sem decisão, a regra por `funcao` migra escondida para o banco.

### Q3 — Divergência da definição de “gerente responsável” — **ABERTA**

- **Contexto:** `permissaoAvaliacao` usa a **raiz da cadeia**; `progressoAvaliacao`
  exige um gestor com `funcao === "GERENTE"` (G3).
- **Problema:** permissão e pendência podem divergir (avaliação “completa” sem
  quem possa concluir, ou vice-versa).
- **Alternativas:** (A) raiz da cadeia é a definição única (alinhada a F4-09
  D2/D3); (B) manter as duas regras com precedência explícita; (C) redefinir por
  configuração.
- **Recomendação (Flash):** **(A)** — relação estrutural; a regra por `funcao`
  é legado a eliminar.
- **Impacto:** muda o cálculo de pendências para alguns perfis (regressão
  intencional e documentada).
- **Risco:** alteração de comportamento percebido (avaliações que hoje não
  exigem gerente passariam a exigir).

### Q4 — Quem conclui e completude como pré-requisito — **ABERTA**

- **Contexto:** a baseline conclui via `evaluation.write`; `calcularProgressoAvaliacao`
  define “completo”, mas **não foi localizada** validação explícita que impeça
  concluir com pendências.
- **Alternativas:** (A) concluir exige `completo = true`; (B) concluir é
  permitido com pendências (registradas em eventos/pendências); (C) depende de
  capability adicional.
- **Recomendação (Flash):** **(A)** com exceção explícita auditada (a decidir),
  pois preserva a semântica de “pendência é excepcional no fechamento do ciclo”.
- **Impacto:** define pré-condição da transição e a UX de conclusão.
- **Risco:** bloquear conclusões hoje permitidas (mudança de comportamento).

### Q5 — Papel do colegiado no cálculo quando o membro não votou — **ABERTA**

- **Contexto:** baseline consolida a média dos votos **válidos** (>0) por
  subcritério; um membro que não vota simplesmente não entra.
- **Alternativas:** (A) preservar baseline (média dos votos válidos); (B)
  considerar ausência como participação obrigatória (pendência) — o que já ocorre
  via `ProgressoPapel`.
- **Recomendação (Flash):** **(A)** para o cálculo **(B)** para a pendência
  (comportamento atual: ausência conta como pendência no progresso).
- **Impacto:** confirma §6; sem impacto no modelo.
- **Risco:** interpretação divergente de “média do colegiado consolidada”.

### Q6 — Transparência: quais itens o avaliado vê além da nota final — **ABERTA**

- **Contexto:** a base diz “avaliado vê dados conforme regras de transparência,
  incluindo lista de membros do colegiado, mas nunca votos/notas individuais”.
  Não há especificação completa (por exemplo: comentários por critério? nota por
  subcritério?).
- **Alternativas:** (A) avaliado vê apenas `nota_media` + faixa + comentário
  final do responsável; (B) avaliado vê `nota_media`, `nota_criterio` e
  `nota_subcritorio` (sem comentários internos); (C) matriz explícita por
  `role_type`.
- **Recomendação (Flash):** **(B)**, mantendo fora quaisquer votos individuais e
  comentários internos de terceiros; a lista de membros do colegiado é permitida.
- **Impacto:** define a projeção de leitura do avaliado (RPC/view) e os testes de
  transparência.
- **Risco:** exposição indevida (se amplo demais) ou quebra de UX (se restrito
  demais).

### Q7 — Comparabilidade histórica do cálculo após versionamento de configuração — **ABERTA**

- **Contexto:** a Issue exige “cálculo conforme configuração versionada”, mas o
  relatório compara notas entre ciclos (variação — `relatorioService`).
- **Alternativas:** (A) relatórios comparam apenas avaliações da **mesma versão**
  de configuração; (B) convertem/normalizam entre versões; (C) comparam valores
  absolutos com aviso.
- **Recomendação (Flash):** **(A)** nesta fase, sinalizando o aviso de
  incomparabilidade; conversão fica para atividade de relatórios.
- **Impacto:** define contrato de relatórios (fora do escopo direto, mas
  dependente do modelo).
- **Risco:** relatórios apresentarem variações enganosas.

### Q8 — Versionamento da escala de avaliação — **ABERTA**

- **Contexto:** a escala (faixas por `limiteMinimo`) é **global** e não
  versionada; hoje não há `organization_id` (G6).
- **Alternativas:** (A) escala no mesmo versionamento da configuração
  (por organização); (B) manter global e apenas snapshotar na avaliação; (C)
  escala por organização independente da configuração de critérios.
- **Recomendação (Flash):** **(A)** — uma única versão de configuração por
  organização (critérios + escala), snapshotada na avaliação.
- **Impacto:** define se `evaluation_config_scale_bands` pertence à versão (como
  proposto em §3.2) ou é catálogo global.
- **Risco:** faixas mudarem retroativamente em relatórios se não versionadas.

---

## 16. Critérios de aceite rastreados (Issue #103 × contrato)

| Critério da Issue #103 | Como o contrato atende | Seção |
| --- | --- | --- |
| modelo não depende de papéis avaliativos fixos por cargo | D1/D2 + `role_type` de relação + `evaluation_participants` | §3.4, §5 |
| preservar snapshot de participantes/responsabilidades do ciclo | `evaluation_participants` snapshot + fontes F3-08/09 | §5.2 |
| suportar gestor direto, outros responsáveis e colegiado 0..N | catálogo `role_type` extensível + 0..N | §5.1 |
| preservar sucessão de avaliador e substituição temporária | `origem`/`origem_ref_id`/vigência + eventos | §5.3 |
| preservar cálculo validado (1–5, ausência, colegiado consolidado, médias, config versionada) | D4/D5/D6/D13 + §6 | §6 |
| cálculo preserva resultados esperados da baseline | paridade com tolerância explícita | §12 |
| conclusão, pendência permanente e reabertura GERENTE-only/capability equivalente | D8/D11 + `evaluation.reopen` (scope) | §7, §8.2 |
| imutabilidade normal de avaliação concluída | D8 (RPC/RLS) | §7.1 |
| transparência (lista de colegiado; nunca voto individual) | D14 + projeção server-side | §9 |
| uma única avaliação não cancelada por colaborador/ciclo | D9 (índice único parcial) | §3.3 |
| operações compostas críticas transacionais | §10 (RPC + lock) | §10 |
| cortar `localStorage` após validação | D12 (fases de cutover) | §11 |
| aplicar RLS/autorização F4 | D10 + F4-08 | §8 |
| concorrência não cria duplicadas/estados parciais | §10 | §10 |
| conclusão/reabertura/pendências preservam histórico | D7/D11 | §3.7, §3.8 |
| Supabase como fonte única após validação | §11 | §11 |
| identidade interna imutável + vínculo soberano ao ciclo | D3 + **Q1** | §4 |
| sem importação de históricos reais (fora de escopo) | §1.3/§11 | §11.2 |

---

## 17. Arquivos analisados (leitura obrigatória cumprida)

**Processo/contexto:** `AGENTS.md`, `.ai/virtus-context.md`, `.ai/workflow.md`,
`.ai/architecture-rules.md`, `.ai/git-rules.md`, `.ai/handoff.md`.

**Issue/contratos:** GitHub Issue **#103**; `docs/F5-01-desenho-tecnico.md`,
`docs/F5-02-desenho-tecnico.md`, `docs/F5-03-desenho-tecnico.md`,
`docs/F5-04-desenho-tecnico.md`, `docs/F5-05-desenho-tecnico.md`,
`docs/F4-09-desenho-tecnico.md`, `docs/F4-08-desenho-tecnico.md`,
`docs/F4-03-desenho-tecnico.md`, `docs/F4-10-matriz-rastreabilidade.md`.

**Domínio de avaliações:** `src/types/Feedback.ts`, `src/types/CicloAvaliacao.ts`,
`src/types/EscalaAvaliacao.ts`, `src/types/Colaborador.ts`,
`src/data/modeloAvaliacao.ts`, `src/services/feedbackStorage.ts`,
`src/services/feedbackStorage.test.ts`, `src/services/progressoAvaliacao.ts`,
`src/services/permissaoAvaliacao.ts`, `src/services/permissaoAvaliacao.test.ts`,
`src/services/cancelamentoAvaliacaoService.ts`,
`src/services/reaberturaAvaliacaoService.ts`,
`src/services/cicloEquipeService.ts`, `src/services/cicloAvaliacaoStorage.ts`,
`src/services/escalaAvaliacaoStorage.ts`, `src/services/relatorioService.ts`,
`src/services/apresentacaoNota.ts`, `src/services/exportarAvaliacaoPdf.ts`,
`src/services/historicoOrganizacionalStorage.ts`,
`src/services/impactoCorrecaoPeriodoCiclo.ts`.

**Autorização/infra:** `src/authorization/authorizationPolicy.ts`,
`src/authorization/ResourceContext.ts`, `src/authorization/Capability.ts`,
`src/authorization/catalogoCapabilities.ts`,
`src/authorization/policyEngine/types.ts`,
`src/authorization/policyEngine/policyEngine.ts`,
`src/authorization/contextoAutorizacao.ts`, `src/auth/tipos.ts`,
`src/auth/contratos.ts`, `src/infrastructure/supabase/supabaseClient.ts`.

**Banco:** `supabase/migrations/*` (inventário das tabelas F2/F3/F4/F5),
`supabase/validacao/*` (padrão de validadores), `supabase/config.toml`.

---

## 18. Confirmações desta atividade

- **Nenhuma implementação funcional**: nenhuma migration, tabela, schema, código,
  teste ou contrato existente foi alterado; apenas este documento foi criado.
- Estado: **EM REVISÃO**; `D1–D14` **PROPOSTAS**; `Q1–Q8` **ABERTAS**.
- Baseline funcional **reconstruída com evidência** e confrontada com a Issue
  #103 e os contratos fechados (divergências G1–G10 em §2.9).
- Nenhuma questão foi fechada arbitrariamente; nenhuma premissa inventada — o que
  o repositório/Issue não sustenta está em `Q#`.
- Contratos F3/F4/F5 **preservados**; F5-06 não antecipa a migração de ciclos,
  metas ou observações.
- Próximo passo: revisão arquitetural independente (GPT) para fechar `Q1–Q8` e
  converter as decisões em contrato **FECHADO** antes de qualquer implementação.
