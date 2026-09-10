# F5-06 — Avaliações no PostgreSQL (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de análise e desenho, sem código funcional**.
> Estado: **FECHADO — contrato pronto para implementação** (revisão arquitetural
> independente GPT-5.6 incorporada). `D1–D27` **FECHADAS** (§14); `Q1–Q8`
> **RESOLVIDAS** com rastreabilidade `Q# → D#` (§15).
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
  — atividades próprias; a F5-06 consome seus contratos, não os migra. A
  `evaluation_cycles` criada aqui é **mínima** e será **estendida aditivamente**
  pela atividade de ciclos (D15);
- alteração de contratos F3/F4/F5 fechados;
- normalização/conversão de notas entre **versões diferentes** de configuração
  (D21 — fora desta atividade);
- hardening geral (F6), produção/hospedagem, observabilidade externa;
- implementação de código nesta rodada.

---

## 2. Baseline funcional reconstruída (evidência)

> Reconstruída a partir do código atual. **Não se assume** que o comportamento
> atual é automaticamente correto: as divergências com a Issue #103 e com os
> contratos fechados estão em §2.9 e foram **resolvidas** por decisão (§15).

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
  (`src/types/Colaborador.ts`) — **decisão de produto baseada em `funcao`**
  (eliminada do contrato futuro por D16/D17).
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
  e entra como **uma única parcela** — não é média das médias por critério
  (ponderação preservada por D25).

Escala (faixas por `limiteMinimo`) em `escalaAvaliacaoStorage.ts`; faixas de
relatório em `relatorioService.ts` (`getItemEscalaPorNota`).

### 2.5 Pendências e fechamento de ciclo

`src/services/progressoAvaliacao.ts` (`calcularProgressoAvaliacao`):

- `gerenteNecessario` = **existe um gestor com `funcao === "GERENTE"` na cadeia**
  (regra eliminada por D17);
- `coordenadorNecessario` = “usa estrutura analista” **e**
  `gestorDireto.funcao === "COORDENADOR"` (eliminada por D16);
- `colegiadoNecessario` = “usa estrutura analista” **e** há avaliadores de colegiado;
- pendências = notas faltantes por papel + `feedbackFinalGerente` /
  `feedbackFinalCoordenador` vazios;
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

### 2.9 Divergências baseline × Issue #103 × contratos fechados (todas resolvidas)

| # | Achado | Evidência | Resolução |
| --- | --- | --- | --- |
| G1 | **Papéis avaliativos fixos** no modelo de dados (`notaGerente`/`notaCoordenador`/`notaColegiado`) | `types/Feedback.ts` | D1 (modelo orientado a participantes) |
| G2 | **Requisito de participante por `funcao`** | `progressoAvaliacao.ts`, `permissaoAvaliacao.ts` | D16 (configuração versionada; sem cargo em runtime) |
| G3 | **Duas regras** para “gerente responsável” (raiz × `funcao === "GERENTE"`) | `permissaoAvaliacao.ts` × `progressoAvaliacao.ts` | D17 (raiz estrutural é a definição única) |
| G4 | Identidade do avaliado é **matrícula numérica** | `Feedback.colaboradorId: number` | D3 (UUID de `collaborators.id`) |
| G5 | **Sem tabela de ciclos** no Postgres | migrations; `cicloAvaliacaoStorage.ts` | D15 (`evaluation_cycles` mínima, extensão aditiva) |
| G6 | Modelo de critérios constante de código; escala global sem versionamento | `data/modeloAvaliacao.ts`, `escalaAvaliacaoStorage.ts` | D5/D6/D22 (configuração versionada; escala na versão) |
| G7 | Reabertura/cancelamento apenas em arrays do próprio registro | `types/Feedback.ts` | D7/D26 (trilha append-only) |
| G8 | `localStorage` é a fonte de verdade | `feedbackStorage.ts` | §11 / D12 (cutover sem dual-write; Supabase fonte única) |
| G9 | Sem **unicidade** de avaliação por (colaborador, ciclo) no armazenamento | `existeAvaliacaoNaoCanceladaNoCiclo` | D9 (índice único parcial) |
| G10 | Reabertura/cancelamento “só gerente” por scope DESCENDANTS | `docs/F4-09` §7.2 | D10 (preservado via capability + scope) |

---

## 3. Modelo de dados

> Todas as tabelas novas são **tenant-rooted** (`organization_id`), com
> `ENABLE RLS`, policy pronta antes do grant, FKs `ON DELETE RESTRICT`,
> `created_at/updated_at/version` conforme F1-02, e **sem exclusão física** de
> histórico (D16 F4-08). Números decimais são `numeric` (nunca float binário — D24).

### 3.1 `evaluation_cycles` (vínculo soberano ao ciclo — D15, mínima)

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

**Unique:** `(organization_id, ano, numero)` + `(id, organization_id)` (FK
composta). **Escopo mínimo (D15):** identidade, tenant, período/status e
`config_version_id` necessários à avaliação; **não** absorve a lógica do domínio
de ciclos (correções de período, reabertura de ciclo, encerramento detalhado),
que a **estenderá aditivamente**. `evaluation_cycles` **não** pode continuar
sendo apenas `ano + número` no cliente.

### 3.2 `evaluation_config_versions` (+ critérios, subcritérios, faixas e papéis)

- `evaluation_config_versions`: `id`, `organization_id`, `version` (int),
  `checksum` (hash do conteúdo), `origem` (`SISTEMA|ORGANIZACAO`), `status`
  (`active|superseded`), timestamps; **unique** `(organization_id, version)`.
- `evaluation_config_criteria`: `id`, `config_version_id`, `code`, `name`,
  `position`, unique `(config_version_id, code)`.
- `evaluation_config_subcriteria`: `id`, `config_criterion_id`, `code`, `name`,
  `position`, unique `(config_criterion_id, code)`.
- `evaluation_config_scale_bands`: `id`, `config_version_id`, `nota` (1..5),
  `significado`, `descricao`, `limite_minimo numeric(12,8)`, `cor`, `cor_fundo`,
  unique `(config_version_id, nota)`.
- **`evaluation_config_participant_roles`** (D16 — exigência dos participantes):
  `id`, `config_version_id`, `role_type` (relação, não cargo), `required`
  (boolean), `contributes_to_score` (boolean), `requires_final_comment`
  (boolean), `min_participants` (smallint NOT NULL default 0),
  `max_participants` (smallint NULL = sem limite), `aggregation_mode`
  (`INDIVIDUAL|AGGREGATED`), `position`; **unique** `(config_version_id, role_type)`;
  CHECK `min_participants >= 0`,
  `max_participants IS NULL OR max_participants >= min_participants`, e
  `COLEGIADO` com `aggregation_mode='AGGREGATED'` e `min_participants = 0` (0..N).

**Imutabilidade:** versão publicada é **imutável** (nova versão para mudar);
a avaliação referencia a versão usada (D5/D6/D22). A escala **pertence** à mesma
versão (D22). A configuração de papéis **define exigência e cardinalidade**, e o
**snapshot da avaliação (§3.4) define o que valia naquele ciclo/avaliação** (D16).

### 3.3 `evaluations` (avaliação)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | — |
| `organization_id` | uuid NOT NULL | FK `organizations(id)` |
| `cycle_id` | uuid NOT NULL | FK composta `(cycle_id, organization_id)` → `evaluation_cycles` |
| `evaluated_collaborator_id` | uuid NOT NULL | FK composta `(…, organization_id)` → `collaborators` (**UUID**, D3) |
| `status` | text NOT NULL | `RASCUNHO|PRONTA_PARA_FEEDBACK|CONCLUIDA|CANCELADA` (D8) |
| `nota_media` | numeric(12,8) NULL | consolidada (D13/D24/§6) |
| `config_version_id` | uuid NOT NULL | versão congelada (D6) |
| `expectativa_snapshot` | jsonb NULL | expectativa de cargo capturada na criação |
| `data_conclusao` | timestamptz NULL | — |
| `encerrada_com_pendencias` | boolean NOT NULL default false | marcador **permanente** (D11) |
| `motivo_cancelamento`, `cancelado_por_user_profile_id`, `data_cancelamento` | — | cancelamento auditado |
| `version`, `created_at`, `updated_at` | padrão | — |

**Unique parcial (D9):** um índice único parcial garante **no máximo uma
avaliação não cancelada** por `(organization_id, cycle_id, evaluated_collaborator_id)`
(`WHERE status <> 'CANCELADA'`). **Unique:** `(id, organization_id)`.

### 3.4 `evaluation_participants` (OCORRÊNCIAS de atribuição — D23)

Cada linha é uma **ocorrência histórica** de atribuição (não um vínculo eterno):
a mesma pessoa pode ocupar o mesmo `role_type` em **períodos distintos**
(sucessão, substituição encerrada e posterior retorno).

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | identifica a **ocorrência** |
| `evaluation_id` | uuid NOT NULL | FK composta → `evaluations` |
| `organization_id` | uuid NOT NULL | tenant |
| `role_type` | text NOT NULL | catálogo **de relação** (§5.1; D2) |
| `collaborator_id` | uuid NOT NULL | FK composta → `collaborators` (identidade interna imutável) |
| `user_profile_id` | uuid NULL | FK → `user_profiles` (conta vinculada, quando houver) |
| `origem` | text NOT NULL | `ESTRUTURA|SUBSTITUICAO_TEMPORARIA|SUCESSAO|SNAPSHOT_CICLO` |
| `origem_ref_id` | uuid NULL | `temporary_responsibilities.id` / `evaluation_succession_events.id` |
| `valid_from` | timestamptz NOT NULL | início da vigência |
| `valid_to` | timestamptz NULL | fim da vigência (`NULL` = vigente) |
| `status` | text NOT NULL | `active|ended` — estado **operacional derivado**; **não substitui** a vigência |
| `version`, `created_at`, `updated_at` | padrão | — |

**Constraints:**
1. **Sem** unique eterno por `(evaluation_id, role_type, collaborator_id)`.
2. **Exclusion constraint** (`btree_gist` já habilitado) impedindo **sobreposição
   inválida** de atribuições equivalentes do mesmo papel:
   `EXCLUDE USING gist (evaluation_id WITH =, role_type WITH =, collaborator_id WITH =, tstzrange(valid_from, coalesce(valid_to, 'infinity'::timestamptz)) WITH &&)`.
3. CHECK `valid_to IS NULL OR valid_to > valid_from`.
4. Revogação/retorno: encerra-se a ocorrência (`valid_to`, `status='ended'`) e
   **cria-se nova ocorrência** — nenhuma linha histórica é apagada.
5. `evaluation_scores.participant_id` aponta para a **ocorrência correta** (a
   vigente no momento da nota).

### 3.5 `evaluation_scores` (nota por ocorrência × subcritério)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | — |
| `evaluation_id` | uuid NOT NULL | FK composta → `evaluations` |
| `organization_id` | uuid NOT NULL | tenant |
| `participant_id` | uuid NOT NULL | FK composta → `evaluation_participants` (**ocorrência**) |
| `subcriterion_id` | uuid NOT NULL | FK → `evaluation_config_subcriteria` |
| `nota` | smallint NOT NULL | **CHECK `between 1 and 5`** (D4) — ausência = linha inexistente (nunca `0`) |
| `autor_user_profile_id` | uuid NULL | autoria |
| `data_avaliacao` | timestamptz NULL | — |
| `version`, `created_at`, `updated_at` | padrão | — |

**Unique:** `(participant_id, subcriterion_id)` (uma nota por ocorrência por
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

### 3.7 `evaluation_events` (histórico/auditoria — append-only, D7/D26)

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | uuid PK | — |
| `evaluation_id`, `organization_id` | — | FKs compostas |
| `event_type` | text NOT NULL | `CRIADA|CONCLUIDA|REABERTA|CANCELADA|PENDENCIA_MARCADA|NOTA_ALTERADA|COMENTARIO_ALTERADO|PARTICIPANTE_ALTERADO` |
| `actor_user_profile_id` | uuid NOT NULL | **autoria soberana** (server-side) |
| `motivo` | text NULL | obrigatório em `REABERTA`/`CANCELADA` |
| `entidade` / `entidade_id` | text / uuid NULL | **referência explícita** ao objeto alterado |
| `valor_anterior` / `valor_novo` | jsonb NULL | delta auditável **tipado por evento** |
| `created_at` | timestamptz NOT NULL | append-only |

**Contrato do evento (D26):**
1. **O evento nunca é fonte substituta do estado atual** — o estado vive nas
   tabelas do domínio; o evento é trilha;
2. `payload`/`valor_*` **não são autoridade** de tenant nem de ator:
   `organization_id` vem da FK composta e `actor_user_profile_id` é resolvido
   **server-side**;
3. alterações de nota/comentário registram `entidade`/`entidade_id` +
   `valor_anterior`/`valor_novo` **estruturados** por tipo de evento (não depende
   exclusivamente de payload arbitrário);
4. **a operação crítica e o seu evento pertencem à MESMA transação** (atômico);
5. sem `UPDATE`/`DELETE` (append-only); `authenticated` sem DML direto.

### 3.8 `evaluation_pendencies` (pendências do fechamento — marcador permanente)

`id`, `evaluation_id`, `organization_id`,
`codigo` (`NOTA_FALTANTE|FEEDBACK_FINAL_FALTANTE|PARTICIPANTE_OBRIGATORIO_AUSENTE`),
`role_type`/`participant_id` (quando aplicável), `criterion_id`/`subcriterion_id`
(quando aplicável), `descricao`, `registrada_em`,
`registrada_por_user_profile_id`. **Append-only por fechamento** (novo fechamento
⇒ novas linhas; histórico preservado). Substitui o array de strings
`pendenciasEncerramento`.

### 3.9 Invariantes de integridade (todas as tabelas)

1. `organization_id` NOT NULL; **FKs compostas** `(referencia_id, organization_id)`
   em todas as relações (cross-tenant por construção) — padrão F3/F4-01.
2. Nenhum FK/campo para `job_roles`/`seniority_levels`/cargo/função em nenhuma
   tabela do domínio (D16/D17 — invariante de arquitetura).
3. Status em catálogo fechado por CHECK; transições validadas por RPC/função
   (§10), não por trigger genérico.
4. `evaluation_scores.nota` ∈ [1,5]; ausência = linha inexistente (nunca `0`).
5. **Participantes são ocorrências**: vigência + exclusion de sobreposição
   equivalente; nenhuma ocorrência histórica é apagada (D23).
6. Avaliação **CONCLUIDA**: alterações de nota/comentário somente por reabertura
   auditada (D8).
7. Uma avaliação não cancelada por (org, ciclo, colaborador) — índice único
   parcial (D9).
8. Agregados persistidos em `numeric` (nunca float binário); nenhum
   arredondamento intermediário (D24).
9. Toda operação que altera estado **e** seu evento são atômicos (D26).

---

## 4. Identidade e tenant (contratos F5 preservados)

| Regra | Origem fechada |
| --- | --- |
| `auth.uid()` é a identidade soberana | F5-01 D1 |
| Identidade **interna imutável** do avaliado/participante = `collaborators.id` (**UUID**) — nunca matrícula/e-mail/nome | F5-02 D1/D4; D3 |
| `organization_id` derivado/validado **server-side** contra membership ativa; nunca do browser | F5-01 D6, F5-03 D1/D6 |
| Vínculo soberano ao **ciclo** por `cycle_id` do tenant (`evaluation_cycles` mínima) | Issue #103; D15 |
| Vínculo ao colaborador por FK composta de tenant | F3/F4-01 |
| `actor_id`/`organization_id` do cliente **nunca** concedem autoridade | F5-03 D8, F5-05 D6/D20 |
| Cross-tenant ⇒ **DENY/fail-closed** | regras permanentes |
| Enforcement na **fronteira confiável server-side**; browser/React/hooks/services no browser = cliente | F5-05 D20 |
| `evaluated_collaborator_id` e `organization_id` sempre da **linha real** carregada server-side (nunca do payload) | D10/D27 |

---

## 5. Participantes

### 5.1 Catálogo de `role_type` (D2)

Semântica de **RELAÇÃO + responsabilidade**, nunca de cargo:

| `role_type` | Semântica (relação) | Baseline correspondente |
| --- | --- | --- |
| `GESTAO_CADEIA` | responsável pela **raiz** da cadeia de gestão do avaliado (D17) | “Gerente” |
| `GESTAO_DIRETA` | gestor **direto** do avaliado | “Coordenador direto” |
| `COLEGIADO` | membro de colegiado atribuído ao avaliado (**0..N**, agregado) | “Colegiado” |
| *(extensível por migration)* | outros responsáveis configuráveis | Issue #103 (“outros responsáveis”) |

- Catálogo **fechado por migration** (não texto livre) e **sem** referência a
  cargo; múltiplas ocorrências por papel são intrínsecas (§3.4).
- A **exigência**, a **cardinalidade** e o **papel no cálculo** vêm de
  `evaluation_config_participant_roles` (D16), **não** de `funcao`.

### 5.2 Configuração → snapshot (D16)

- `evaluation_config_participant_roles` define, por versão de configuração:
  `role_type`, `required`, `contributes_to_score`, `requires_final_comment`,
  `min_participants`, `max_participants`, `aggregation_mode`.
- Na **abertura da avaliação**, a configuração vigente é **congelada** (D6) e os
  participantes são **snapshotados** em `evaluation_participants` a partir das
  fontes soberanas do ciclo (`collegiate_cycle_snapshots(+_members)`,
  `cycle_evaluation_responsibilities`, F3-08/F3-09), com `origem` registrando a
  procedência.
- **Nenhuma consulta a `job_role`, `funcao`, `seniority` ou `cargo` em runtime**
  decide participantes obrigatórios (D16/D17).

### 5.3 Sucessão e substituição temporária

- **Sucessão de avaliador** (F3-09): referencia o snapshot do ciclo; sucessão
  vigente após a abertura **encerra a ocorrência anterior** (`valid_to`) e
  **cria nova ocorrência**, com evento auditado — nunca silencioso.
- **Substituição temporária** (F3-06/F4-05): ocorrência com
  `origem='SUBSTITUICAO_TEMPORARIA'` + `origem_ref_id` e **vigência**; fora da
  vigência não conta para pendência nem para o cálculo.
- **Retorno do titular**: nova ocorrência do mesmo `collaborator_id`/`role_type`
  em período distinto (permitido pela exclusion constraint, que só proíbe
  **sobreposição**) — D23.

### 5.4 Estrutura mudou depois da abertura do ciclo

| Situação | Comportamento contratado |
| --- | --- |
| Colaborador troca de gestor | Snapshot preservado; novo responsável entra como **nova ocorrência** auditada (encerrando a anterior) |
| Gestor sai da empresa | Ocorrência permanece (histórico); se a avaliação não estiver concluída, exige **nova ocorrência** (RPC auditada) ou pendência no fechamento |
| Colegiado alterado | Snapshot preservado; alterações por RPC auditada (encerra/cria ocorrências) |
| Ciclo encerrado com avaliação incompleta | Marcador permanente (§3.8) + pendências; **não** converte a avaliação em `CONCLUIDA` (D18) |

---

## 6. Cálculo

### 6.1 Ponderação por RESPONSABILIDADE (D25 — anti-regressão)

> Cada **responsabilidade avaliativa configurada** contribui como **UMA parcela**.
> Membros do colegiado **não** pesam individualmente.

```
parcela(responsabilidade INDIVIDUAL)  = nota do participante (ocorrência vigente)
parcela(responsabilidade AGREGADA)    = média dos votos VÁLIDOS dos membros
                                        (COLEGIADO: aggregation_mode = AGGREGATED)

nota_subcriterio = média das PARCELAS VÁLIDAS das responsabilidades com
                   contributes_to_score = true
nota_criterio    = média das nota_subcriterio válidas
nota_media       = média das nota_criterio válidas
(ausência de qualquer parcela válida ⇒ 0 / "sem avaliação")
```

Portanto `GESTAO_CADEIA + GESTAO_DIRETA + COLEGIADO` **continua equivalente** à
baseline `gerente + coordenador + média do colegiado`, **cada bloco com o mesmo
peso**. Qualquer responsabilidade adicional configurada entra como **mais uma
parcela** (nunca redistribui pesos existentes de forma implícita).

Regras preservadas da baseline (§2.4): notas **1–5**; **ausência/zero = sem
avaliação**; **sem arredondamento** no cálculo; formatação de 1 casa é apenas
apresentação.

### 6.2 Precisão e tolerância (D24)

| Item | Definição |
| --- | --- |
| Representação oficial | **`numeric`** (decimal) — **nunca float binário** |
| Precisão persistida | `numeric(12,8)` para agregados (`nota_media`, notas por critério/subcritério) e `limite_minimo` das faixas |
| Cálculo | server-side, **sem arredondamento nas etapas intermediárias**; materialização com escala 8 (arredondamento somente na gravação, ≤ meio dígito da última casa) |
| Arredondamento | **somente** na apresentação (1 casa decimal) |
| Tolerância de paridade (testes) | `|Δ| ≤ 1e-8` entre a média da baseline (float JS) e o valor persistido (numeric escala 8) — compatível com a representação |
| Proibição | usar float binário como fonte oficial ou comparar com `===` |

### 6.3 Onde o cálculo acontece (D13)

- **Fonte soberana:** as notas persistidas (banco). O cálculo é executado
  **server-side** em RPC/transação que grava os agregados (`nota_media`, por
  critério e por subcritério) como **derivados materializados** para
  relatórios/leitura, e é **recomputável** por função pura para validação;
- o frontend **não** calcula a nota oficial; pode pré-visualizar com a mesma
  função pura compartilhada (UX);
- recomputação disponível para auditoria/consistência (teste dedicado).

### 6.4 Casos de borda

| Caso | Comportamento |
| --- | --- |
| Colegiado com 0 membros | A parcela agregada **não existe**; média apenas das parcelas existentes |
| Membro de colegiado **sem voto** | **Não** entra como zero no cálculo; se era participante **obrigatório** pelo snapshot/configuração ⇒ **gera pendência** (D19) |
| Participante sem nenhuma nota | Não entra em nenhuma média (não é zero) |
| Todos sem nota | `nota_media = 0` (“sem avaliação”) |
| Subcritério/critério desativado na configuração | Não participa do cálculo da avaliação que referencia aquela versão (D5/D6); avaliações existentes seguem a **sua** versão |
| Configuração alterada após a abertura | **Não afeta** a avaliação em curso (versão congelada — D6) |
| Nota fora de 1–5 | Rejeitada por CHECK + validação na RPC (nunca persiste) |

---

## 7. Workflow da avaliação

### 7.1 Estados e transições (D8/D18)

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
| Criar avaliação | ciclo `ATIVO` (ou `PLANEJADO` se o contrato do ciclo permitir), avaliado ativo/elegível; sem outra avaliação não cancelada | `evaluation.create` |
| Preencher/editar | ciclo ≠ `CANCELADO`; status ∉ {`CONCLUIDA`,`CANCELADA`} | `evaluation.write` |
| Enviar para feedback | idem | `evaluation.write` |
| **Concluir (fluxo normal)** | **completude** conforme a configuração congelada (`required`/`contributes_to_score`/`requires_final_comment` + pendências zeradas) | `evaluation.write` (**sem capability nova** — D18) |
| **Reabrir** | status `CONCLUIDA`; ciclo ≠ `ENCERRADO`/`CANCELADO`; motivo obrigatório | `evaluation.reopen` (scope da cadeia de gestão — preserva “GERENTE-only” F4-09) |
| **Cancelar** | status ≠ `CANCELADA`; ciclo ≠ `CANCELADO`; motivo obrigatório | `evaluation.cancel` (scope DESCENDANTS — preserva baseline) |
| Fechar ciclo | operação do ciclo (não da avaliação) | `cycle.manage` |
| Marcar pendência permanente | fechamento do ciclo com avaliação incompleta | operação do ciclo (transacional) |

- **Conclusão normal exige completude** conforme a configuração congelada da
  avaliação; **completude é regra de workflow/domínio, não capability** (D18).
- **A exceção para avaliação incompleta é o fechamento do ciclo**: a avaliação
  pode permanecer **não concluída**, o fechamento registra **marcador permanente**
  + pendências, e **não** converte a avaliação em `CONCLUIDA` automaticamente (D18).
- **Imutabilidade normal de CONCLUIDA** preservada (D8) — reforçada por RPC/RLS
  (não apenas `domainState` de aplicação).
- **Reabertura** grava `evaluation_events` (`REABERTA` + motivo + autor soberano)
  e limpa `data_conclusao` mantendo o histórico.
- **Cancelamento** grava `CANCELADA` + motivo + autor + `evaluation_events`.
- **Toda operação composta** (criar com participantes, gravar lote, concluir,
  reabrir, cancelar, fechar ciclo com pendências) é **transacional** (§10) e o
  seu evento pertence à **mesma transação** (D26).

---

## 8. Autorização

### 8.1 Integração obrigatória (sem autorização paralela)

| Camada | Papel |
| --- | --- |
| **Policy Engine (F4-03)** | única decisão de autorização (ALLOW/DENY) |
| **F5-04 capabilities × scopes** | `evaluation.read/create/write/cancel/reopen` com escopos/alcance reais |
| **F5-05 ActorContext/ResourceContext** | ator real (`auth.uid`) + recurso **tenant-rooted** derivado da **linha real** da avaliação |
| **RLS (F4-08)** | barreira de isolamento (tenant) independente |
| **`can()`** | somente UX |
| **Domínio** | regras de estado (imutabilidade, transições, completude) via `domainState`/predicados — nunca autorização |

Após a F5-06, `evaluation` passa a ser um `TargetRef` autorizável com
`organization_id` derivado do recurso (`ResourceContext` real, D19/D22 da F5-05).

### 8.2 `service_role` ≠ autorização (D27)

> Funções server-side que **bypassam RLS** (`service_role`, `SECURITY DEFINER`)
> **não** são, por si, autorização. Toda função/RPC/Edge que executa operação do
> domínio deve **primeiro construir o `ActorContext` real** (`auth.uid()` /
> `auth.getUser()` verificado server-side, organização e membership revalidadas)
> e **passar pelo Policy Engine** (`authorize()`), aplicando então a mutação.
> O `service_role` é credencial de **execução privilegiada**, não de decisão.

### 8.3 Mapeamento operação → capability (D10)

| Operação | Capability existente | Scope |
| --- | --- | --- |
| Ler avaliação de terceiro | `evaluation.read` | DIRECT_REPORTS/DESCENDANTS/ASSIGNED conforme relação |
| Ler a própria avaliação (SELF) | `evaluation.read` | SELF + `domainState` (transparência — §9) |
| Criar/editar/preencher/concluir | `evaluation.create` / `evaluation.write` | conforme relação |
| Cancelar | `evaluation.cancel` | DESCENDANTS |
| Reabrir | `evaluation.reopen` | DESCENDANTS |
| Fechar ciclo com pendências | `cycle.manage` | ORGANIZATION |

**Nenhuma capability nova é necessária** (`evaluation.complete` **não** existe —
D18). Se alguma operação futura não couber no catálogo, será aberta como nova
`Q#` — nenhuma identificada.

---

## 9. Transparência e privacidade do colegiado (D20)

### 9.1 O que o avaliado pode receber

Após a avaliação estar **visível segundo o workflow** (transparência), o avaliado
pode receber:

- `nota_media`;
- **notas agregadas por critério**;
- **notas agregadas por subcritério**;
- **faixa/descrição** derivada da versão da escala congelada;
- **lista dos membros do colegiado** (permitida pela Issue #103);
- **comentários finais explicitamente destinados ao avaliado**, conforme a
  responsabilidade/configuração (`requires_final_comment` + destino).

### 9.2 Nunca expor ao avaliado

- **voto individual** de membro do colegiado;
- **nota individual** de participante do colegiado;
- **`participant_id` correlacionado a voto/nota**;
- **comentários internos de terceiros** não destinados ao avaliado;
- qualquer dado de avaliação **não concluída** (fora da janela de transparência).

### 9.3 Garantia server-side (não pela UI)

1. A leitura do avaliado usa **projeção/RPC server-side** que retorna apenas os
   campos agregados de §9.1 — a projeção **não inclui** `evaluation_scores` de
   participantes individuais nem `participant_id` junto de nota;
2. **RLS**: o avaliado acessa apenas a sua avaliação (via
   `evaluated_collaborator_id` ligado à sua membership/F5-02); as tabelas
   `evaluation_scores`/`evaluation_comments` são **deny-by-default** para
   `authenticated` (somente via RPC com projeção);
3. testes de transparência obrigatórios (§12) validam **ausência** de voto/nota
   individual e de correlação por participante na resposta do avaliado.

---

## 10. Concorrência e transações

| Risco | Proteção contratada |
| --- | --- |
| Duas avaliações não canceladas (mesmo colaborador/ciclo) | **índice único parcial** (§3.3) + verificação na RPC (conflito) |
| Double-submit de criação | unique + RPC transacional (chave natural) |
| Conclusão concorrente | RPC + `SELECT … FOR UPDATE` da avaliação; transição validada no servidor; segunda tentativa ⇒ conflito (sem evento duplicado) |
| Reabertura concorrente | idem (lock + estado `CONCLUIDA` obrigatório) |
| Gravação parcial de notas/comentários | **uma transação** para o lote; falha ⇒ rollback total (sem estado parcial) |
| Mudança estrutural concorrente | participante é **ocorrência/snapshot**; alteração só por RPC auditada; sem reescrita implícita |
| Sobreposição de vigência de ocorrências | **exclusion constraint** (§3.4) + validação transacional |
| Alteração de configuração durante a avaliação | versão **congelada** (D6); versão imutável |
| Fechamento de ciclo concorrente | RPC do ciclo com lock; marcador permanente idempotente |
| Evento divergente do estado | evento e mutação na **mesma transação** (D26) |

**Operações que exigem RPC/função transacional server-side:** criar avaliação
(com participantes), gravar lote de notas/comentários, concluir, reabrir,
cancelar, fechar ciclo com pendências e qualquer mutação de participante. Nenhuma
delas é DML direto de `authenticated` (padrão F4-08 D7) e todas passam por
`authorize()` com `ActorContext` real (D27).

---

## 11. Migração / cutover (D12 — atualizado)

### 11.1 Princípios

- A F5-06 **não** importa avaliações históricas reais (fora de escopo da Issue);
- **Sem dual-write** (nem direto, nem reverso);
- Supabase vira **única fonte de verdade** ao final da validação.

### 11.2 Fases

| Fase | Estado |
| --- | --- |
| 1. Schema + RPC + RLS + testes (sem tráfego real) | Supabase pronto; `localStorage` ainda autoridade |
| 2. **Paridade** — baseline de cálculo executada contra o novo modelo (fixtures sintéticas) e comparada ao resultado atual (tolerância `1e-8` — D24) | evidência de paridade |
| 3. **Cutover de escrita** — serviços escrevem **somente** em Supabase para avaliações **novas** (a partir da data de corte) | `localStorage` **read-only** para o domínio |
| 4. **Cutover de leitura** — leitura server-side; `localStorage` deixa de ser consultado | Supabase = fonte única |
| 5. **Remoção** da autoridade local (código local do domínio removido; chave preservada apenas como legado morto até limpeza) | — |

### 11.3 Rollback (contrato)

- **Antes do cutover de escrita** (nenhum registro exclusivo no banco): o
  rollback para o caminho legado é **permitido** (simples reversão de flag);
- **A partir da primeira avaliação escrita exclusivamente no Supabase**: Supabase
  **permanece a fonte de verdade**; **rollback para `localStorage` como
  autoridade é PROIBIDO**; correções usam **fix-forward / roll-forward** no banco
  e na aplicação;
- **feature flag** pode **desabilitar novas mutações** ou trocar a versão de
  backend, mas **não** restaurar `localStorage` como autoridade;
- **nenhum dual-write reverso** (não exportar do banco para o `localStorage`);
- avaliações pré-existentes em `localStorage` permanecem visíveis no modo legado
  até a atividade de importação (fora de escopo), **sem** virar autoridade no
  novo caminho.

---

## 12. Testes e validadores (matriz mínima)

| Grupo | Cenários |
| --- | --- |
| **Cálculo** | parcelas por responsabilidade (individual × agregada); colegiado **não** pesa por membro; médias subcritério/critério/final; ausência/zero; colegiado vazio; participantes incompletos; sem arredondamento; **paridade com a baseline (tolerância 1e-8)**; recomputação == materializado |
| **Precisão** | `numeric` sem float; arredondamento só na apresentação; nenhum arredondamento intermediário |
| **Participantes (ocorrências)** | sucessão; substituição encerrada + retorno do titular; múltiplos períodos do mesmo papel; **exclusion impede sobreposição**; vigência define ativo; score aponta para a ocorrência correta |
| **Colegiado** | consolidação por subcritério; membro sem voto **não** entra como zero; membro obrigatório sem voto ⇒ **pendência** |
| **Configuração** | `evaluation_config_participant_roles` define exigência/cardinalidade; `COLEGIADO` 0..N; versão imutável; congelamento na abertura; alteração posterior não afeta a avaliação |
| **Conclusão** | completude exigida conforme configuração congelada; imutabilidade após concluir; edição ⇒ DENY |
| **Pendência / fechamento** | fechamento com incompleta ⇒ marcador permanente + pendências; **não** converte em `CONCLUIDA`; idempotência |
| **Reabertura** | capability/scope corretos; motivo obrigatório; histórico preservado; concorrência |
| **Cancelamento** | motivo/autor; unicidade liberada para nova avaliação |
| **Concorrência** | criação duplicada; double-submit; conclusão/reabertura concorrentes; rollback de gravação parcial |
| **Unique/constraints** | uma não cancelada por (org, ciclo, colaborador); uma nota por (ocorrência, subcritério); um comentário por (ocorrência, escopo, critério); exclusion de vigência |
| **Eventos/auditoria** | append-only; autoria soberana; evento na mesma transação; payload **não** é autoridade de tenant/ator; delta estruturado em alteração de nota/comentário |
| **Tenant/IDOR** | leitura/escrita cross-tenant ⇒ DENY; id de outro tenant; recurso inexistente |
| **RLS** | deny-by-default; policies por comando; `authenticated` sem DML; schema guard |
| **Capabilities/scopes** | cada operação mapeada (§8.3); escopo herdado da relação; revogação entre operações |
| **ActorContext/ResourceContext** | avaliação como recurso tenant-rooted (F5-05); cross-tenant DENY; sem tenant sintético |
| **`service_role` × autorização** | função que bypassa RLS **ainda** passa por `ActorContext` + Policy Engine; sem decisão implícita por credencial |
| **Transparência** | avaliado recebe agregados + faixa + lista de colegiado; **nunca** voto/nota individual, `participant_id` correlacionado ou comentário interno; avaliação não concluída invisível |
| **Cutover/rollback** | paridade antes do cutover; após o primeiro registro exclusivo no banco: **sem** rollback para `localStorage`; flag não restaura autoridade local |
| **Regressão baseline** | fixtures sintéticas com os mesmos resultados esperados da baseline atual |

**Comandos obrigatórios:** `npm test`, `npm run build`, `npm run lint`,
`git diff --check`; **validadores Supabase locais** (cenário + validador SQL do
domínio, RLS/schema guard) e regressão dos validadores F4/F5 existentes.

---

## 13. Riscos

| Risco | Mitigação |
| --- | --- |
| Divergência de cálculo entre baseline e banco | paridade com tolerância `1e-8` + fixtures da baseline (§12) |
| **Regressão de ponderação** (colegiado pesando por membro) | D25 explícito + teste dedicado de ponderação |
| Modelo “orientado a participantes” perder semântica de papel | catálogo `role_type` **de relação** + configuração versionada + testes por cenário |
| Regra por `funcao` sobreviver disfarçada | proibição de FK/campo de cargo (invariante §3.9.2) + D16/D17 |
| Snapshot de participantes inconsistente com a estrutura | ocorrências imutáveis + exclusão de sobreposição + alterações só por RPC auditada |
| Duplicidade de avaliação sob concorrência | unique parcial + transação |
| Vazamento de voto individual do colegiado | projeção server-side + RLS + testes de transparência |
| **Rollback indevido para `localStorage` após cutover** | D12/§11.3 proíbe; fix-forward obrigatório |
| Evento divergente do estado / payload como autoridade | D26 (mesma transação; payload não é autoridade) |
| Configuração mudar no meio do ciclo | versão congelada por avaliação (D6/D22) |
| Migração de ciclos fora de escopo bloquear a F5-06 | D15 (tabela mínima; extensão aditiva) |
| Agregado materializado divergir do cálculo | recomputação server-side + teste de consistência |
| Precisão insuficiente/float binário | `numeric(12,8)` + proibição de float oficial (D24) |

---

## 14. Decisões arquiteturais (D1–D27 — todas FECHADAS)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | **Modelo orientado a participantes** | Notas/comentários por **participante** (linhas), não colunas fixas; colegiado 0..N natural | FECHADA |
| D2 | **`role_type` = relação, não cargo** | Catálogo fechado por migration com semântica de relação (`GESTAO_CADEIA`, `GESTAO_DIRETA`, `COLEGIADO`, extensível) | FECHADA |
| D3 | **Identidade por UUID** | `evaluated_collaborator_id`/`participant.collaborator_id` = `collaborators.id` (F5-02); matrícula é legado | FECHADA |
| D4 | **Nota 1–5; ausência ≠ 0** | CHECK 1..5; ausência = linha inexistente; agregação ignora ausências | FECHADA |
| D5 | **Configuração versionada e imutável** | Critérios/subcritérios/faixas/**papéis de participante** em versões; publicada é imutável | FECHADA |
| D6 | **Versão congelada por avaliação** | A avaliação referencia a versão vigente na abertura; mudanças posteriores não a afetam | FECHADA |
| D7 | **Trilha append-only de eventos** | `evaluation_events` com autoria soberana, motivo e delta estruturado; sem UPDATE/DELETE | FECHADA |
| D8 | **Estados e transições preservados** | `RASCUNHO→PRONTA_PARA_FEEDBACK→CONCLUIDA`, `CANCELADA`, reabertura excepcional; `CONCLUIDA` imutável reforçada por RPC/RLS | FECHADA |
| D9 | **Unicidade de avaliação não cancelada** | Índice único parcial `(org, cycle, evaluated_collaborator) WHERE status <> 'CANCELADA'` | FECHADA |
| D10 | **Autorização reutiliza o catálogo F5-04** | Sem capability nova; `evaluation.read/create/write/cancel/reopen` + scopes/relação; enforcement server-side; `can()` só UX | FECHADA |
| D11 | **Pendência permanente persistida** | `evaluation_pendencies` (append-only por fechamento) + `encerrada_com_pendencias` | FECHADA |
| D12 | **Cutover em fases; sem dual-write; rollback proibido após o 1º registro exclusivo** | §11.2/§11.3: antes do cutover de escrita o retorno ao legado é permitido; depois, Supabase é fonte de verdade, rollback para `localStorage` é **proibido**, correções por fix-forward, flag não restaura autoridade local, sem dual-write reverso | FECHADA |
| D13 | **Cálculo server-side e materializado** | Cálculo em RPC/transação; agregados materializados como derivados; frontend não calcula a nota oficial; recomputável para validação | FECHADA |
| D14 | **Transparência do colegiado garantida no servidor** | Detalhamento final em D20 | FECHADA |
| D15 | **`evaluation_cycles` mínima, extensível aditivamente (resolve Q1)** | Identidade, tenant, período/status mínimo e `config_version_id`; **não** absorve a lógica do domínio de ciclos; atividade futura **estende** de forma aditiva; ciclos não podem continuar só como `ano+número` no cliente | FECHADA |
| D16 | **Exigência de participantes por configuração versionada, sem cargo (resolve Q2)** | `evaluation_config_participant_roles` (`role_type`, `required`, `contributes_to_score`, `requires_final_comment`, `min_participants`, `max_participants`, `aggregation_mode`) + snapshot na avaliação; **nenhuma** consulta a `job_role`/`funcao`/`seniority`/cargo em runtime | FECHADA |
| D17 | **`GESTAO_CADEIA` = raiz estrutural da cadeia (resolve Q3)** | Definição única do responsável de cadeia (raiz aplicável ao ciclo); a regra `funcao == "GERENTE"` é **eliminada** do contrato futuro (mudança intencional vs. baseline) | FECHADA |
| D18 | **Conclusão normal exige completude; exceção é o fechamento do ciclo (resolve Q4)** | Capability continua `evaluation.write`; completude é regra de **workflow/domínio**, não capability; **sem** `evaluation.complete`; ciclo pode fechar com avaliação **não concluída** (marcador permanente + pendências), **sem** conversão automática em `CONCLUIDA` | FECHADA |
| D19 | **Colegiado sem voto: não é zero no cálculo; gera pendência se obrigatório (resolve Q5)** | Cálculo: média apenas dos votos válidos; pendência: membro obrigatório sem voto ⇒ pendência | FECHADA |
| D20 | **Transparência: agregados permitidos; individual jamais (resolve Q6)** | Avaliado recebe `nota_media`, agregados por critério/subcritério, faixa/descrição e lista de membros do colegiado; **nunca** voto/nota individual, `participant_id` correlacionado ou comentário interno; comentários finais destinados ao avaliado conforme configuração; garantido por **projeção/RPC server-side**, não pela UI | FECHADA |
| D21 | **Comparabilidade apenas na mesma versão de configuração (resolve Q7)** | Comparação automática só entre avaliações da mesma versão; entre versões ⇒ sinalizar **não diretamente comparável**; **sem** normalização/conversão nesta fase | FECHADA |
| D22 | **Escala pertence à versão de configuração (resolve Q8)** | Tenant-rooted, versionada, imutável após publicação, congelada por avaliação/ciclo; alterações criam nova versão | FECHADA |
| D23 | **Participantes como OCORRÊNCIAS históricas** | `id` identifica a ocorrência; mesma pessoa pode repetir `role_type` em períodos distintos; `valid_from`/`valid_to` definem vigência; `status` é operacional e **não** substitui a vigência; **exclusion constraint** impede sobreposição equivalente; **sem** unique eterno por (evaluation, role, collaborator); todas as ocorrências preservadas; `evaluation_scores` aponta para a ocorrência correta | FECHADA |
| D24 | **Precisão decimal oficial; sem float; tolerância compatível** | `numeric(12,8)` para agregados e faixas; cálculo sem arredondamento intermediário (arredondamento só na gravação, ≤ meio dígito da última casa, e na apresentação de 1 casa); tolerância de teste `1e-8`; proibido float binário como fonte oficial ou comparação por `===` | FECHADA |
| D25 | **Ponderação: uma parcela por responsabilidade configurada** | Individual ⇒ parcela = nota do participante; agregada (COLEGIADO) ⇒ parcela = média dos votos válidos; `nota_subcriterio` = média das parcelas válidas das responsabilidades com `contributes_to_score`; preserva a equivalência com a baseline (gerente + coordenador + média do colegiado, mesmo peso) e **impede regressão de ponderação** | FECHADA |
| D26 | **Contrato do evento de auditoria** | Evento **nunca** substitui o estado atual; `organization_id` por FK composta e `actor_user_profile_id` resolvido server-side (payload **não** é autoridade de tenant/ator); alterações guardam `entidade`/`entidade_id` + delta **estruturado**; operação crítica e evento na **mesma transação** | FECHADA |
| D27 | **`service_role` ≠ autorização** | Função server-side que bypassa RLS deve **primeiro** construir `ActorContext` real (`auth.uid()`/`auth.getUser()` + tenant/membership revalidados) e passar pelo **Policy Engine**; a credencial privilegiada é execução, não decisão | FECHADA |

---

## 15. Questões de revisão — Q1–Q8 RESOLVIDAS (rastreabilidade `Q# → D#`)

> Cada questão foi **respondida na revisão arquitetural independente** e
> incorporada como decisão FECHADA. Mantidas para rastreabilidade. **Nenhuma
> questão arquitetural permanece aberta.**

### Q1 — Entidade soberana de ciclo — **RESOLVIDA → D15 (alternativa A)**

- **Contexto:** avaliações referenciavam ciclo por `ano + 1|2|3`, sem entidade
  server-side (G5), enquanto a Issue #103 exige vínculo soberano ao ciclo.
- **Decisão:** a F5-06 cria **`evaluation_cycles` mínima** (identidade, tenant,
  período/status, `config_version_id`), **sem** absorver a lógica futura do
  domínio de ciclos; a atividade de ciclos **estende aditivamente**; ciclos não
  podem permanecer apenas `ano+número` no cliente.
- **Seções dependentes:** §1.3, §3.1, §4, D15.

### Q2 — Estrutura avaliativa sem cargo — **RESOLVIDA → D16 (A + C)**

- **Contexto:** exigência de participantes derivava de `funcao` (G2).
- **Decisão:** configuração **versionada por organização** com estrutura
  explícita de responsabilidades (`role_type`, `required`,
  `contributes_to_score`, `requires_final_comment`, `min/max_participants`,
  `aggregation_mode`), **snapshotada** na avaliação; **nenhuma** consulta a
  `job_role`/`funcao`/`seniority`/cargo em runtime; `COLEGIADO` 0..N.
- **Seções dependentes:** §3.2, §5.1, §5.2, D16.

### Q3 — “Gerente responsável” — **RESOLVIDA → D17 (alternativa A)**

- **Contexto:** duas regras divergentes (raiz da cadeia × `funcao === "GERENTE"`)
  — G3.
- **Decisão:** `GESTAO_CADEIA` = **raiz estrutural soberana** da cadeia aplicável
  ao ciclo; a regra por `funcao` é **eliminada**; registrada como **mudança
  intencional** frente à baseline.
- **Seções dependentes:** §2.5, §5.1, D17.

### Q4 — Conclusão e completude — **RESOLVIDA → D18 (alternativa A, sem capability nova)**

- **Decisão:** conclusão **normal** exige completude conforme a configuração
  congelada; capability continua **`evaluation.write`**; completude é regra de
  **workflow/domínio**; **sem** `evaluation.complete`; a exceção para avaliação
  incompleta é o **fechamento do ciclo** (marcador permanente + pendências), sem
  conversão automática em `CONCLUIDA`.
- **Seções dependentes:** §7.1, §8.2, §8.3, D18.

### Q5 — Colegiado sem voto — **RESOLVIDA → D19 (cálculo A; pendência B)**

- **Decisão:** no cálculo, ausência **não** entra como zero (média só dos votos
  válidos); como **pendência**, membro **obrigatório** sem voto gera pendência.
- **Seções dependentes:** §6.4, §12, D19.

### Q6 — Transparência do avaliado — **RESOLVIDA → D20 (alternativa B)**

- **Decisão:** avaliado recebe `nota_media`, agregados por critério e por
  subcritério, faixa/descrição da escala e a lista de membros do colegiado;
  **nunca** voto/nota individual, `participant_id` correlacionado a voto ou
  comentários internos de terceiros; comentários finais destinados ao avaliado
  conforme a responsabilidade/configuração; garantido por **projeção/RPC
  server-side**.
- **Seções dependentes:** §9, §12, D20.

### Q7 — Comparabilidade histórica — **RESOLVIDA → D21 (alternativa A para F5-06)**

- **Decisão:** comparação automática apenas entre avaliações da **mesma versão**
  de configuração; entre versões ⇒ **não diretamente comparável**, sem
  normalização/conversão nesta fase.
- **Seções dependentes:** §1.3, §13, D21.

### Q8 — Escala — **RESOLVIDA → D22 (alternativa A)**

- **Decisão:** a escala pertence à **mesma** `evaluation_config_version`:
  tenant-rooted, versionada, imutável após publicação, congelada por
  avaliação/ciclo; alterações criam nova versão.
- **Seções dependentes:** §3.2, §6, D22.

---

## 16. Critérios de aceite rastreados (Issue #103 × contrato)

| Critério da Issue #103 | Como o contrato atende | Seção |
| --- | --- | --- |
| modelo não depende de papéis avaliativos fixos por cargo | D1/D2/D16/D17 + `role_type` de relação + config versionada | §3.2, §3.4, §5 |
| preservar snapshot de participantes/responsabilidades do ciclo | ocorrências snapshotadas + fontes F3-08/09 | §3.4, §5.2 |
| suportar gestor direto, outros responsáveis e colegiado 0..N | catálogo extensível + `min/max_participants` + 0..N | §3.2, §5.1 |
| preservar sucessão de avaliador e substituição temporária | ocorrências + vigência + `origem_ref_id` + eventos | §3.4, §5.3 |
| preservar cálculo validado (1–5, ausência, colegiado consolidado, médias, config versionada) | D4/D5/D6/D13/D25 + §6 | §6 |
| cálculo preserva resultados esperados da baseline | paridade com tolerância `1e-8` + teste de ponderação | §6.1, §12 |
| conclusão, pendência permanente e reabertura GERENTE-only/capability equivalente | D8/D11/D18 + `evaluation.reopen` (scope) | §7, §8.3 |
| imutabilidade normal de avaliação concluída | D8 (RPC/RLS) | §7.1 |
| transparência (lista de colegiado; nunca voto individual) | D20 + projeção server-side | §9 |
| uma única avaliação não cancelada por colaborador/ciclo | D9 (índice único parcial) | §3.3 |
| operações compostas críticas transacionais | §10 (RPC + lock + evento na mesma transação) | §10 |
| cortar `localStorage` após validação | D12/§11 (cutover; rollback proibido após 1º registro) | §11 |
| aplicar RLS/autorização F4 | D10/D27 + F4-08 | §8 |
| concorrência não cria duplicadas/estados parciais | §10 (unique, lock, transação) | §10 |
| conclusão/reabertura/pendências preservam histórico | D7/D11/D26 | §3.7, §3.8 |
| Supabase como fonte única após validação | §11 (fases; sem dual-write) | §11 |
| identidade interna imutável + vínculo soberano ao ciclo | D3 + D15 | §3.1, §4 |
| sem importação de históricos reais (fora de escopo) | §1.3/§11 | §11.1 |

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
  teste ou contrato existente foi alterado; apenas este documento foi atualizado.
- Estado final: **FECHADO — contrato pronto para implementação**; `D1–D27`
  **FECHADAS** (§14); `Q1–Q8` **RESOLVIDAS** com rastreabilidade `Q# → D#` (§15);
  **nenhuma questão arquitetural aberta**.
- Correções da revisão incorporadas: ocorrências de participante (D23), precisão
  decimal/tolerância coerentes (D24), ponderação por responsabilidade (D25),
  contrato do evento (D26), `service_role` ≠ autorização (D27), cutover/rollback
  (D12/§11.3) e configuração de papéis (D16/§3.2).
- Contratos F3/F4/F5 **preservados**; a migração de ciclos (D15), metas e
  observações **não** foi antecipada.
- Próximo passo: implementação da F5-06 em PR próprio, seguindo este contrato —
  **não** iniciada aqui. Nenhum PR aberto e nenhum merge realizado.
