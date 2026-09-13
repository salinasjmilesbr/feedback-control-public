# F5-10 — Metas soberanas no PostgreSQL (contrato normativo)

> **Atividade:** F5-10 — Issue **#208**. **Base:** `main` = `285b2dd` (squash da F5-09/P9).
> **Branch:** `docs/f5-10-metas-soberanas-desenho`.
> **Natureza:** documento **normativo** — fecha o contrato para implementação. **Nenhum código funcional foi alterado.**
> **Histórico:** `98549b3` (auditoria + desenho inicial), `f259c08` (achados do 3º relatório),
> esta revisão (fechamento de Q1–Q14 conforme revisão GPT sobre `f259c08`).
> **Regras de leitura:** onde este documento diz **DECIDE**, a decisão está fechada e não pode ser
> reinterpretada na implementação. O que não pôde ser fechado aparece em **§18 BLOCKERS DOCUMENTAIS**,
> nunca como escolha deixada ao implementador.

## 1. Objetivo

Substituir a autoridade funcional de metas (hoje `localStorage`) por **autoridade soberana no
PostgreSQL**, com identidade UUID, lifecycle explícito, aprovações como fatos auditáveis, limites
invariantes no banco, autorização pelo Policy Engine, RLS fail-closed, Edge própria e cutover sem
fallback.

## 2. Escopo / não escopo

**Escopo:** metas de ciclo (`NEGOCIO_PROJETO` e `INDIVIDUAL`), limites por ciclo, aprovações de
coordenador e gerente, progresso, finalização/revisão, histórico, e a eliminação do `localStorage`
como fonte funcional.

**Não escopo:** F5-11 (observações; `observation.*` intocado), F5-07 (histórico organizacional e a
pendência `ciclo_listar_colaborador_por_ciclo`), F5-08 (estrutura/catálogos — apenas consumidos),
F5-09 (ciclo/trilha/RPCs — apenas consumidos), nota de avaliação (F5-06; **não há** vínculo entre
meta e nota — “Cumprimento de metas e compromissos” é texto de subcritério).

## 3. Inventário auditado (base `285b2dd`)

### 3.1 Modelo atual — `src/types/Meta.ts` (81 linhas, lido integralmente)

`Meta` (`:42-81`): `id` **UUID do browser** (`metaStorage.ts:281`); `colaboradorMatricula`+`colaboradorNome`
(vínculo por matrícula, `:44-45`); `cicloId` **UUID de ciclo fabricado no browser**
(`cicloAvaliacaoStorage.ts:54,69,142`) **e** `ano`/`ciclo` denormalizados (`:48-49`); `tipo`
(`:1-3`); `descricao`/`kpi`/`valorAlvo` (texto livre); `status` ∈ `EM_ANDAMENTO|ATINGIDA|NAO_ATINGIDA`
(`:5-8`); `aprovacaoCoordenador?`/`aprovacaoGerente?` = `{matricula,nome,data}` (`:20-24`) —
**estado autorizativo no objeto**; `resultadoAtual?`, `progressoPercentual?` (0..100 digitado),
`dataUltimoAcompanhamento?`; `resultadoFinal?`, `atingida?`, `dataFechamento?`; `dataCriacao`/
`dataUltimaAtualizacao` (relógio do browser); `excluida`/`dataExclusao?` (soft delete);
`historico: HistoricoMeta[]` (`:26-40`, com `autorMatricula`/`autorNome`).
`AcaoHistoricoMeta` (`:10-18`) já enumera 8 ações. **Não há** `version`, `motivo`/`justificativa`
nem schema-version local.

### 3.2 Persistência

- **Único** acervo: `localStorage["feedback-control-metas"]` (`metaStorage.ts:24,27,37`); toda
  mutação regrava o **array inteiro** (`:304,343,456,492,543,604,658`).
- **Fallback silencioso com perda de dado:** JSON corrompido ⇒ `catch { return [] }` (`:31-33`).
- **Segundo produtor da mesma chave:** `src/services/geradorDadosTeste.ts:525-532` (DEV-gated).
- **Não existe** tabela, RPC, Edge, repositório, porta ou policy de metas; o CI **proíbe** meta no
  schema hoje (`supabase/validacao/15-validar-f5-09-p9.sql:2095-2132` — guarda a substituir em P1).
- **Não há** dual-write: existe o inverso — acervo local **sem contraparte remota** (cutover =
  backfill + construção).

### 3.3 Lifecycle real

| Transição | Como ocorre hoje |
|---|---|
| criar | `criarMeta` (`:249-306`), valida ciclo `ATIVO` **lido do `localStorage`** (`:89-98`) e limite do tipo (`:259-272`) |
| editar | `atualizarMeta` (`:308-390`); invalida aprovações se `alteracaoRelevante` (compara **só** `descricao`/`kpi`/`valorAlvo`, `:337-340`, `:379-384`) |
| progresso | `atualizarAcompanhamentoMeta` (`:570-629`); **não** invalida aprovação |
| finalizar | `finalizarMeta` (`:631-684`); **não checa o status atual** ⇒ re-finalização **silenciosa** (a UI oferece “Revisar fechamento”, `MinhasMetasPage.tsx:521`) |
| reabrir | **não existe** |
| excluir | `excluirMeta` (`:523-568`), lógica |
| aprovar | `aprovarMeta` (`:392-521`), `domainState: dominioPermite(true)` **hardcoded** (`:421`), idempotência por *early-return* (`:454`, `:490`) |

**Regras de aprovação vigentes (preservar a semântica):**
`metaExigeAprovacaoCoordenador` (`:171-199`) = “coordenador = nível **intermediário**” (`gestorTemSuperior`),
**fail-closed** sem evidência estrutural; `podeAprovarMetaNoCiclo` (`:220-247`) = gestor direto
(coordenador) **ou** raiz da cadeia (gerente); `metaEstaAprovada` (`:201-218`) =
`(!exigeCoordenador || aprovacaoCoordenador) && aprovacaoGerente` ⇒ **o gerente é sempre exigido**.
Quota: `quantidadeMetasNegocio/Individuais` no ciclo legado, `0|1|2|3`, alterável **só em
`PLANEJADO`** (`cicloAvaliacaoStorage.ts:327-359`) — e o caminho soberano **não a transporta**
(F5-09 D24). Agregação atual: média aritmética simples com `Math.round`
(`MinhasMetasPage.tsx:660`, `AcompanhamentoMetasPage.tsx:137-144`). **Não há** peso, nota nem
agregação por ciclo.

### 3.4 Autorização atual

`goal.read`/`goal.write`/`goal.approve` existem no catálogo desde a F4-01
(`20260908000001_authorization_system_catalog.sql:53-58`) e **nenhuma role/bundle os concede**.
`authorizationPolicy.ts:174-212` tem `case "goal"` com alvo `{type:"collaborator"}` e `domainState`
**declarado pelo cliente**; `resourceContextReal.ts:33` mantém `goal` em
`TIPOS_RECURSO_NAO_SOBERANOS` (⇒ `TARGET_NAO_SOBERANO` no enforcement). Em HOMOLOG/PROD o mundo
sintético devolve vazio (`providers/localWorld.ts:30-37`) ⇒ **o domínio é integralmente negado**;
em DEV é concedido por fixture (`:59-70`). `AcompanhamentoMetasPage.tsx:80-107` decide acesso por
`funcao` textual + `can()` (UX, não autorização).

### 3.5 Consumidores e acoplamentos

Diretos: `MinhasMetasPage`, `AcompanhamentoMetasPage` (maior esforço de cutover), `PainelCicloPage`,
`MinhaAvaliacaoPage`, `PainelCiclosCoordenadorPage`. De arrasto: `NovoFeedbackPage`/`EditarFeedbackPage`
(aviso de meta sem aprovação — **não bloqueia**), `MinhaAvaliacaoDetalhePage`, `exportarAvaliacaoPdf.ts`
(“Metas do Ciclo”), `cicloEquipeService.ts` (pendência `papel:"Metas"`),
`correcaoPeriodoCicloService.ts`/`impactoCorrecaoPeriodoCiclo.ts` — **inconsistência factual**:
avaliações/observações por `(ano,ciclo)` (`:42`,`:59-61`) e metas por `cicloId` (`:52`).
`PainelCicloPage.tsx:102,137-167` decide KPI por `funcao`/`gestorDiretoMatricula` local.
Colisão de identidade já observável: a gestão navega com UUID soberano (`CiclosAvaliacaoPage.tsx:122,484`)
e `PainelCicloPage.tsx:77`/`AcompanhamentoMetasPage.tsx:55` resolvem o mesmo `:cicloId` contra o ciclo
local ⇒ “Metas não encontradas”.

### 3.6 Testes existentes

`metaStorage.test.ts` (**5 casos**, nenhum cobre criação com sucesso, limite excedido, invalidação,
progresso fora de 0..100, re-finalização ou soft delete), `AcompanhamentoMetasPage.test.tsx` (3),
`authorizationPolicy.test.ts` (paridade `goal.approve` × `podeAprovarMetaNoCiclo`, ~`:909-916`),
`estruturaSoberanaCliente.test.ts`, `cutoverEstruturalServicos.test.ts`,
`cancelamentoCicloService.test.ts`, `reaberturaCicloService.test.ts`,
`correcaoPeriodoCicloService.test.ts`, `impactoCorrecaoPeriodoCiclo.test.ts`,
`cicloEquipeService.test.ts`, `estruturaUiSeguranca.test.ts` (guardas `:504-509`, `:516-525`,
`:527-538`, `:553-579`), `controladorGestaoCiclos.test.ts:775-791`, `p9MatrizIntegrada.test.ts:145-158`
e o invariante SQL `15-validar-f5-09-p9.sql:2095-2132`.

### 3.7 O que **não existe** (declarado)

Tabela/RPC/Edge/porta/RLS de meta · `MetaProgresso`/`aprovacaoMeta` como tipos · **peso** de meta ·
nota de meta · meta de equipe · bridge `(ano,numero)`↔UUID **para metas** · `version`/`expectedVersion` ·
`motivo` · reabertura · versionamento de schema local · sincronização multi-aba/lock.

## 4. Mapas exigidos

| # | Item | Situação |
|---|---|---|
| a | modelo | §3.1 — um blob, matrícula+nome, `cicloId` fabricado, `(ano,numero)` denormalizado, histórico embutido |
| b | lifecycle | §3.3 — 3 estados, aprovação ortogonal, re-finalização silenciosa, sem reabertura |
| c | regras | ciclo `ATIVO`; limite por tipo; coordenador=intermediário; gerente=raiz; fail-closed; gerente sempre exigido; agregação por média |
| d | autorização | §3.4 — 3 capabilities sem concessão; alvo `collaborator`; meta não soberana; estado declarado pelo cliente |
| e | legado | `localStorage` (blob), UUID de ciclo no browser, matrícula/nome, mundo sintético DEV, quota no ciclo legado |
| f | concorrência | last-write-wins do array; TOCTOU na quota e na aprovação; sem versão/lock; multi-aba sem sincronização |
| g | multiusuário | aprovações concorrentes se sobrescrevem; decisões por `funcao` textual; autoria não soberana |
| h | dual-read/write/fallback | **sem dual-write**; fallback silencioso (JSON corrompido ⇒ `[]`); fallback de mundo DEV |
| i | contratos a reutilizar | §13 e §17 (padrões F5-09: UUID, trilha append-only, `expected_version`, idempotência, lock, RLS policy-antes-do-grant, Edge `index/core/contrato`, adapter fail-closed) |
| j | dívidas fora do escopo | §2 |

## 5. Problemas e resíduos

1. **Construção + backfill**, não troca de fonte (não há backend).
2. **Duas identidades de ciclo incompatíveis, sem bridge**; `cicloAvaliacaoStorage` **fabrica** ciclos
   no caminho de leitura ⇒ metas órfãs por construção.
3. **Autorização inoperante em produção** (`goal.*` sem concessão + mundo sintético ⇒ DENY).
4. **Estado autorizativo dentro do objeto mutável** do cliente; idempotência por *early-return*;
   **aprovações concorrentes se sobrescrevem** (array inteiro regravado: `:401-456`, `:490-492`).
5. **Decisão estrutural síncrona sobre projeção assíncrona** ⇒ fail-closed **silencioso**
   (`useEstruturaSoberanaDoCliente.ts:59`).
6. **Consumidores de arrasto** com três chaves de ciclo diferentes (inclui a divergência dentro de
   `impactoCorrecaoPeriodoCiclo`).

---

# CONTRATO NORMATIVO

## 6. Modelo soberano

### 6.1 Identidade

**DECIDE (D1):** a identidade canônica da meta é **`evaluation_goals.id` (uuid, PK)**, atribuída
pelo banco. `ano`/`numero` e matrícula/nome são **rótulos de projeção**, nunca identidade, chave de
leitura ou autorização. Vínculos por UUID: `organization_id` (tenant da linha), `cycle_id`
(fk para `evaluation_cycles`) e `collaborator_id` (fk para `collaborators`).
**Nenhum id de meta nasce no cliente** (modelo: `gestaoCiclosSoberanos.ts:97-103`).

### 6.2 Tabelas (aditivas; nenhum objeto da F5-09 alterado)

```
public.evaluation_goals
  id uuid pk, organization_id uuid not null,
  cycle_id uuid not null, collaborator_id uuid not null,
  tipo text not null check (tipo in ('NEGOCIO_PROJETO','INDIVIDUAL')),
  descricao text not null, kpi text not null, valor_alvo text not null,
  status text not null default 'EM_ANDAMENTO'
    check (status in ('EM_ANDAMENTO','ATINGIDA','NAO_ATINGIDA')),
  resultado_atual text, progresso_percentual integer
    check (progresso_percentual is null or progresso_percentual between 0 and 100),
  data_ultimo_acompanhamento timestamptz,
  resultado_final text, atingida boolean, data_fechamento timestamptz,
  excluida boolean not null default false, data_exclusao timestamptz,
  version integer not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
  -- FK COMPOSTAS de tenant (modelo cycle_events):
  --   (cycle_id, organization_id) -> evaluation_cycles(id, organization_id)
  --   (collaborator_id, organization_id) -> collaborators(id, organization_id)

public.evaluation_goal_approvals
  id uuid pk, organization_id uuid not null, goal_id uuid not null,
  papel text not null check (papel in ('COORDENADOR','GERENTE')),
  actor_membership_id uuid not null,          -- autoria SOBERANA (fk composta)
  decidido_em timestamptz not null default now(), motivo text,
  revogado_em timestamptz, revogado_motivo text
  -- único vigente: unique (goal_id, papel) where revogado_em is null

public.evaluation_goal_events            -- trilha append-only (mesmo desenho de cycle_events)
  id uuid pk, organization_id uuid not null, goal_id uuid not null,
  event_type text not null check (event_type in
    ('CRIADA','EDITADA','PROGRESSO_ATUALIZADO','FINALIZADA','REVISAO_FINALIZACAO',
     'EXCLUIDA','APROVACAO_COORDENADOR','APROVACAO_GERENTE','APROVACAO_INVALIDADA',
     'LIMITES_DO_CICLO_ALTERADOS')),
  actor_user_profile_id uuid not null, actor_membership_id uuid not null,
  reason text, operation_id uuid not null, payload_hash text not null
    check (payload_hash ~ '^[0-9a-f]{64}$'),
  before_value jsonb, after_value jsonb, result_entity_id uuid,
  created_at timestamptz not null default now(),
  unique (organization_id, operation_id)

public.evaluation_cycle_goal_limits      -- DECIDE (D4, Q5=A)
  id uuid pk, organization_id uuid not null, cycle_id uuid not null,
  tipo text not null check (tipo in ('NEGOCIO_PROJETO','INDIVIDUAL')),
  quantidade integer not null check (quantidade >= 0 and quantidade <= 3),
  unique (cycle_id, tipo)
```

**DECIDE (D3):** `status` **não** representa aprovação; “aprovada” é **derivado** de
`evaluation_goal_approvals` vigente.
**DECIDE (D5):** exclusão é **apenas lógica**; `DELETE`/`TRUNCATE` revogados (D9 da F5-09 preservado).
**DECIDE (D20, Q12):** a quota é **invariante server-side** — o banco **bloqueia** criação acima do
limite (função de guarda chamada pela RPC de criação); a UI apenas antecipa/projeta a informação.

## 7. Lifecycle (normativo)

**DECIDE (D17, Q10):** **finalização e aprovação são dimensões independentes**. Finalizar **não**
exige aprovação prévia; o `status` funcional **não** codifica aprovação.

| Operação | Origem | Capability | Pré-condições | Evento |
|---|---|---|---|---|
| criar | — | `goal.write` + SELF (D9) | ciclo `ATIVO` (**da linha soberana**); quota disponível (invariante no banco); unicidade parcial | `CRIADA` |
| editar definição | viva | `goal.write` + SELF | `expected_version`; sujeita à matriz §9.4 | `EDITADA` |
| atualizar progresso | viva | `goal.write` + SELF | `expected_version`; inteiro 0..100 | `PROGRESSO_ATUALIZADO` |
| finalizar (1ª vez) | `EM_ANDAMENTO` | `goal.write` + SELF | `expected_version`; `resultado_final`+`atingida` | `FINALIZADA` |
| **revisar/re-finalizar** | já finalizada | `goal.write` + SELF | `expected_version` + `operation_id`; **operação explícita** | `REVISAO_FINALIZACAO` com `before_value` = fechamento anterior (**recuperável na trilha**) |
| excluir | viva ou finalizada | `goal.write` + SELF | `expected_version`; motivo | `EXCLUIDA` |
| aprovar | viva, ciclo `ATIVO` | `goal.approve` + escopo relacional (§9) | não é o dono; relação congelada (§9.1); sem aprovação vigente do mesmo papel | `APROVACAO_*` |
| invalidar aprovações | disparado por mutação material (§9.4) | sistema (na RPC da mutação) | registra `APROVACAO_INVALIDADA` por papel; **nunca apaga** o fato anterior | `APROVACAO_INVALIDADA` |

**DECIDE (D17):** **não** é criado estado `REABERTA`/reabertura — a revisão de fechamento é a
operação explícita acima, e o fechamento anterior permanece integralmente na trilha.
**Nunca** sobrescrever silenciosamente (a re-finalização silenciosa do legado **não** é preservada).

## 8. Limites / configuração por ciclo

**DECIDE (D4, Q5=A):** limites exclusivamente em `evaluation_cycle_goal_limits`; **proibido** adicionar
colunas de metas ao contrato funcional de `evaluation_cycles`.
**DECIDE (D21, Q14):** a quota **pode** ser alterada durante o ciclo `ATIVO`, por **operação
soberana explícita** (`meta_definir_limites_do_ciclo`), com: autorização **administrativa** derivada
do catálogo vigente — **`cycle.manage` no plano administrativo (D19/D21 da F5-09)**, sem capability
nova (Q1); `expected_version` do ciclo; `operation_id`; evento append-only
`LIMITES_DO_CICLO_ALTERADOS`; **lock organizacional normativo**; e a regra
**`quantidade` nunca pode ser reduzida abaixo do total de metas não excluídas daquele tipo**
(violação ⇒ `F5_10_CONFLICT`, nunca exclusão de meta). Nenhuma alteração silenciosa ou local pelo cliente.

## 9. Aprovações, legitimidade e invalidação

### 9.1 Fonte soberana da legitimidade — **B1 RESOLVIDO**

**DECIDE (D14, Q4=A):** a legitimidade para aprovar é **exclusivamente relacional** e deriva dos
**PARTICIPANTES CONGELADOS DA AVALIAÇÃO DO CICLO** (`evaluation_participants`) — **não** da estrutura
viva, **não** de cargo/função textual, **não** de matrícula/nome e **não** do cliente. Regra exata:

1. **link determinístico meta → avaliação:** `evaluations` com `organization_id = meta.organization_id`,
   `cycle_id = meta.cycle_id`, `evaluated_collaborator_id = meta.collaborator_id`,
   `status <> 'CANCELADA'` — no máximo uma linha (índice único
   `uq_evaluations_org_cycle_collaborator_nao_cancelada`,
   `20260911000000_f5_06_evaluation_schema.sql:257-258`);
2. **COORDENADOR** = participante `role_type = 'GESTAO_DIRETA'` dessa avaliação
   (`evaluation_participants`, `:271-317`);
3. **GERENTE** = participante `role_type = 'GESTAO_CADEIA'` dessa avaliação (topo da cadeia de gestão);
4. **ocorrência ORIGINAL** (estabilidade sob *overlays*): entre as ocorrências do papel, escolher a de
   **menor `valid_from`** (empate ⇒ menor `collaborator_id`), preservando a linha do tempo append-only
   (`valid_to` fecha, nunca reescreve) — replicando a própria regra da F5-06
   (`20260911010000_f5_06_evaluation_functions.sql:599-606`);
5. **fail-closed:** sem avaliação, sem ocorrência do papel, ou com `status <> 'active'`/
   `valid_to` preenchido ⇒ o papel **não** é reconhecido (nunca “aprova por falta de prova”).

**Proibido** (inalterado): `funcao`/cargo textual, `gestorDiretoMatricula` do cadastro local,
matrícula/nome como identidade, estrutura viva atual, heurística por nome, `localStorage` e qualquer
estado declarado pelo cliente. **Movimentação estrutural posterior NÃO rematerializa o ciclo**
(F5-09/D27 preservado) ⇒ os aprovadores de uma meta são **estáveis durante o ciclo** (regra 4).

### 9.1.1 Prova arquitetural (auditoria que resolveu B1)

| Elo | Evidência |
|---|---|
| Resolvedor soberano de **cadeia** existe | `organizacao_resolver_cadeia(collaborator_id, timestamptz)` com `depth`/`position_id`/`responsible_collaborator_id`; uso canônico pega o **maior `depth`** = topo: `20260911010000_f5_06_evaluation_functions.sql:388-396` |
| F5-06 **materializa** os dois papéis por avaliação | `insert into public.evaluation_participants (... 'GESTAO_CADEIA', v_cadeia, v_cadeia_origem, ...)` e `... 'GESTAO_DIRETA', v_direta, ...`, com `valid_from = coalesce(v_ref, p_instante)`: `:402-419`; `GESTAO_CADEIA` é **obrigatória** na configuração baseline (`:196`) |
| Papéis são de **RELAÇÃO, nunca cargo** | `check (role_type in ('GESTAO_CADEIA','GESTAO_DIRETA','COLEGIADO'))` (`20260911000000_f5_06_evaluation_schema.sql:300-301`); comentário `:165-167` |
| Congelamento e histórico | `GESTAO_CADEIA`/`GESTAO_DIRETA` derivam da mesma fonte soberana F3-07/F3-09 no instante de referência (`:368`, `:390-396`); `COLEGIADO` vem do snapshot F3-08 (`:421-431`); histórico preservado por `valid_to` (nunca reescrito) — D23 (`:324-327`) |
| Equivalência com a regra do legado | `GESTAO_DIRETA` só é criado quando o gestor direto **difere** do responsável de cadeia (`:410-419`) ⇒ “coordenador exigido quando existir nível intermediário” = “existe ocorrência `GESTAO_DIRETA`”; `GESTAO_CADEIA` = topo ⇒ “gerente = raiz” e “sempre exigido” (obrigatório no baseline) — **D15 preservado literalmente** |

**Consequência para D14 (refinamento, não contradição):** a projeção congelada que define os
aprovadores **não** é o snapshot de posições (registra apenas o superior **imediato**:
`20260907180000_collegiate_configuration_snapshot.sql:265-273`) nem
`cycle_evaluation_responsibilities` (materializa o **responsável avaliativo** da posição do avaliado:
`20260907190000:186-201`); é a **materialização de participantes da avaliação**, que já contém o
**topo da cadeia** congelado no instante de referência. As duas estruturas anteriores permanecem como
**defesa em profundidade** e como fonte do `GESTAO_DIRETA` original, mas **não** definem o gerente.

**Impacto em P3/P4:** P3 implementa a derivação **lendo `evaluation_participants`** (não percorre a
cadeia do snapshot); P4 define o escopo de `goal.approve` como “o ator **É** o participante
`GESTAO_DIRETA`/`GESTAO_CADEIA` (ocorrência original) da avaliação da meta” — UUID contra UUID, sem
cargo e sem estrutura viva. **B1 não bloqueia mais nenhuma fase.**

### 9.2 Regra funcional preservada do legado

**DECIDE (D15):** preservar a semântica vigente:
- **aprovação do gerente é sempre exigida** (`metaEstaAprovada`, `metaStorage.ts:201-218`);
- **aprovação do coordenador é exigida quando existir o nível intermediário aplicável**
  (`metaExigeAprovacaoCoordenador`, `:171-199`: coordenador = nível **intermediário** da cadeia);
- ausência de evidência estrutural ⇒ **fail-closed**.

### 9.3 Aprovação como fato

**DECIDE (D2):** aprovação é **linha em `evaluation_goal_approvals`** + evento append-only
(`APROVACAO_COORDENADOR`/`APROVACAO_GERENTE`), com autoria **soberana**
(`actor_user_profile_id`+`actor_membership_id`), **nunca** `autorMatricula`/`autorNome` do cliente.
Revogação/invalidação = `revogado_em` + `APROVACAO_INVALIDADA`; os fatos antigos **permanecem**.
Uma segunda aprovação vigente do mesmo papel é recusada (unique parcial).

### 9.4 MATRIZ NORMATIVA DE INVALIDAÇÃO (D19, Q11)

> **Objeto aprovado** = a **definição** da meta: `tipo`, `descricao`, `kpi`, `valor_alvo`.
> Aprovação só é invalidada por **mutação material do objeto/condição aprovada**.

| Mutação | Invalida aprovação de COORDENADOR | Invalida aprovação de GERENTE | Observação |
|---|---|---|---|
| `descricao` | **SIM** | **SIM** | mutação material |
| `kpi` | **SIM** | **SIM** | mutação material |
| `valor_alvo` | **SIM** | **SIM** | mutação material |
| `tipo` | **SIM** | **SIM** | muda a categoria aprovada; sujeita novamente à quota |
| `resultado_atual` / `progresso_percentual` | NÃO | NÃO | acompanhamento, não altera o objeto aprovado |
| primeira finalização | NÃO | NÃO | finalizar **não** exige aprovação (§7) |
| revisão/re-finalização | NÃO | NÃO | revisa o **fechamento**, não a definição; fica na trilha |
| alteração de quota do ciclo | NÃO | NÃO | configuração do ciclo; não pode reduzir abaixo do existente (§8) |
| correção de período do ciclo | **NÃO** | **NÃO** | **DECIDE (D18, Q11):** corrigir datas não altera cycle UUID, goal UUID, estrutura materializada nem o conteúdo aprovado |
| movimentação estrutural após a ativação | NÃO | NÃO | D27: o ciclo não é rematerializado (§9.1) |
| exclusão (soft) da meta | — | — | terminal; aprovações permanecem na trilha como fato histórico |

## 10. Autorização (normativo)

**DECIDE (D6, Q1=A):** **somente** `goal.read`, `goal.write` e `goal.approve`. **Nenhuma capability
nova** na F5-10; o catálogo permanece com 31 códigos.

**DECIDE (D7, Q2=B):**
- **dono da meta:** `goal.read` + `goal.write` **por SELF** (escopo SELF; alvo = a própria meta);
- **ator legitimado à aprovação:** `goal.read` + `goal.approve` **pelo escopo relacional aplicável**
  (§9.1);
- **`goal.approve` NÃO implica `goal.write`** — aprovar não autoriza editar, progredir, finalizar,
  re-finalizar nem excluir;
- **concessões/configuração explícitas e testáveis em produção** (via role/atribuição de escopo no
  catálogo vigente);
- **nenhuma autorização pode depender de `localWorld`/DEV** — proibido `criarProvidersMundoLocal` no
  caminho funcional de metas; o teste de ALLOW deve exercitar o caminho de produção.

**DECIDE (D8, Q3=A):** `goal` é **recurso soberano**: `{type:"goal", id:<UUID canônico>}`; tenant,
dono e estado derivam do **recurso real** (`carregarRecurso` da linha em `evaluation_goals`),
registrado em `TIPOS_RECURSO_SOBERANOS` e em `resolveTargetTenant`.

**DECIDE (D9, Q8):** **escrita é SELF**. Gestor/coordenador legitimado **pode ler e aprovar**, e
**não** recebe `goal.write` sobre meta de liderado ⇒ **não** pode criar, editar, atualizar progresso,
finalizar, re-finalizar nem excluir meta de terceiro. Ampliar isso exige decisão nova.

**DECIDE (D12):** `expected_version` obrigatório em **toda** mutação; comparação **após** o lock e o
`select for update`; divergência ⇒ `F5_10_CONFLICT`.
**DECIDE (matriz capability × estado):** matriz com **fonte única** consumida pelo Policy Engine
(modelo `estadoDominioCiclo.ts`): `EM_ANDAMENTO` ⇒ criar/editar/progredir/finalizar/excluir/aprovar;
`ATINGIDA`/`NAO_ATINGIDA` ⇒ ler, aprovar, revisar, excluir; excluída ⇒ somente leitura histórica.
**Estado do ciclo** também participa: só ciclo `ATIVO` permite mutação
(criar/editar/progredir/finalizar/aprovar), lido **da linha soberana** do ciclo.

## 11. RLS × Policy Engine (fronteira sem ambiguidade — D22)

**RLS** é **barreira de isolamento/visibilidade de tenant**: `evaluation_goals` e
`evaluation_goal_approvals` com `enable row level security`, **uma policy de SELECT own-tenant**
(`public.user_has_active_membership(organization_id)`) **criada antes do grant**, `grant select`
mínimo a `authenticated`, **nenhuma** policy de escrita; `evaluation_goal_events` **deny-by-default
integral** com 3 triggers de imutabilidade e `service_role` apenas `SELECT`/`INSERT`.

**Policy Engine** é a **autoridade funcional**: decide se **o ator** pode executar **a operação**
sobre **o recurso** (capability + escopo/relação + estado).

**DECIDE:** `SELECT` own-tenant **NÃO** significa que qualquer membro do tenant possui `goal.read`
funcional sobre qualquer meta. Portanto o **caminho de leitura apresentado ao produto respeita os
dois contratos**:
- **leitura própria** (`MinhasMetasPage`): leitura direta sob RLS com filtro SELF
  (`collaborator_id = ator`);
- **leitura de terceiros** (acompanhamento/aprovação): **RPC de leitura com gate funcional**
  (`meta_listar_por_escopo`) que aplica `goal.read` + escopo relacional (§9.1) **antes** de devolver
  linhas; a RLS continua como defesa em profundidade.
  > **Mudança declarada:** o rascunho anterior propunha “nenhuma RPC de leitura” (espelhando a
  > pendência da F5-09). A separação exigida (RLS ≠ autorização funcional) **obriga** este caminho
  > com gate; a decisão está fechada aqui e a criação dessa RPC é escopo da P4/P5.

## 12. Concorrência, versão e idempotência

**DECIDE (D10, Q6=A):** reutilizar a **mesma família normativa de advisory lock organizacional dos
ciclos**, com a **chave exata**:

```sql
pg_advisory_xact_lock(hashtext('evaluation_cycles:' || p_organization_id::text))
```

Regras: (a) **uma única** chave para a família ciclo+metas; (b) adquirida **no início** de toda RPC
que muta meta, limite ou aprovação; (c) **proibido** criar lock independente
(`evaluation_goals:<org>`) ou adquirir locks em ordem incompatível (deadlock) — a guarda de
catalogação de locks (padrão P6-6 da F5-08) deve registrar a família de metas sob a **mesma** chave.

**DECIDE (D11):** idempotência por `unique (organization_id, operation_id)` na trilha +
`payload_hash` SHA-256 **derivado server-side** (desvio já ratificado em P2–P4);
`operation_id` é **chave de idempotência**, nunca identidade funcional. Replay com a mesma intenção
devolve o mesmo resultado; intenção divergente ⇒ `F5_10_CONFLICT`.
**DECIDE:** `version = version + 1` em toda mutação efetiva; nenhum overwrite silencioso.

## 13. Contrato Edge/RPC

**RPCs** (todas `SECURITY INVOKER`, `search_path = public`, `EXECUTE` **só** `service_role`,
preflight + guarda final fail-closed — modelo `20260916000000_f5_09_cycle_rpc.sql`):
`meta_criar`, `meta_editar`, `meta_atualizar_progresso`, `meta_finalizar`, `meta_revisar_finalizacao`,
`meta_excluir`, `meta_aprovar`, `meta_invalidar_aprovacoes` (interna às mutações),
`meta_definir_limites_do_ciclo`, `meta_listar_por_escopo` (leitura com gate, §11).

**DECIDE (D23):** Edge própria `supabase/functions/metas` (D25 da F5-09: uma Edge por domínio), com
a ordem `método → JWT (auth.getUser) → forma com allowlist estrita → tenant revalidado → gate por
operação (sem default) → execução com service_role e ator verificado → resposta/erro público`, reuso
do trio `index`/`core`/`contrato` e **contrato transportável único** compartilhado com o cliente
(modelo `src/infrastructure/supabase/ciclos/contrato.ts`). `service_role` **executa, nunca decide**.
Cliente: adapter fail-closed (modelo `edgeCiclos.ts`); **proibido** `.rpc(` no browser e
**proibida** `SERVICE_ROLE_KEY` no cliente (guardas já existentes em
`src/authorization/estruturaUiSeguranca.test.ts:527-538`).

## 14. Cutover, backfill e legado

**DECIDE (D13, Q7=A):** backfill **somente** por pontes autoritativas e resolução inequívoca:
`evaluation_resolver_ciclo(org, ano, numero, actor)` (recusa 0, >1 e `CANCELADO`),
`mapearCiclosPorAnoNumero`, `ponteMatricula` (recusa ambiguidade) e `ponteColaborador`.
**Rejeitar** (⇒ **QUARENTENA**): zero correspondências, múltiplas correspondências, ciclo `CANCELADO`,
colaborador ambíguo. **Proibido:** fabricar ciclo, fabricar collaborator, descartar silenciosamente,
manter fallback funcional.
**Antes do backfill:** (1) **congelar/exportar** o acervo legado; (2) registrar **contagem de
entrada**; (3) **abortar** diante de JSON corrompido ou divergência inesperada; (4) registrar
**contagem migrada e quarentenada**. Considerar explicitamente o **segundo produtor da chave**
(`geradorDadosTeste.ts:525-532`) — o congelamento deve registrar quem escreveu por último.

**DECIDE (D24):** cutover com o modelo de **barreira de escrita** identificado no legado
(`colaboradorStorage.ts:53-62`): leitura legada transitória **somente** enquanto estritamente
necessária ao backfill; **escrita local bloqueada** (`throw` apontando a porta soberana); **após o
cutover, nenhuma leitura funcional de fallback**. Guardas preservadas: frontend não chama RPC
diretamente, mutações via Edge/`functions.invoke`, `metaStorage` sai do caminho funcional.
**Consumidores de arrasto** (feedback/detalhe/PDF/fechamento/impacto da correção) passam a resolver
ciclo pelo **UUID soberano**; a divergência de chave em `impactoCorrecaoPeriodoCiclo` é corrigida na
mesma atividade (P6).

## 15. Testes e validação integrada

- **SQL (job `supabase-local`)**: cenário isolado insert-once + validador `[PASS]`/`[FAIL]` com
  preflight/guarda final cobrindo limites (invariante), unicidade parcial, trilha append-only
  (UPDATE/DELETE/TRUNCATE negados), aprovações e **matriz §9.4**, cross-tenant/IDOR por UUID,
  stale `expected_version`, idempotência, rollback multi-escrita, RLS/ACL.
- **Concorrência real entre duas sessões** (padrão da P9, arquivos 16/17/18): duas sessões editando a
  mesma meta e duas aprovando papéis distintos; a perdedora termina em `F5_10_CONFLICT` **depois de
  esperar o lock**.
- **TS/node**: Policy Engine (capability × estado × relação), fronteira soberana (UUID canônico,
  tenant divergente, membership revogada, `goal.approve` sem `goal.write`), porta do cliente
  (fail-closed), guardas anti-`localStorage`/anti-UUID-no-browser e anti-`localWorld` no caminho de metas.
- **Ajustes obrigatórios**: substituir o invariante SQL que **proíbe** metas
  (`15-validar-f5-09-p9.sql:2095-2132`) e o guarda de “não antecipar F5-10”
  (`p9MatrizIntegrada.test.ts:145-158`, se afetado); atualizar `metaStorage.test.ts` (cobrir criação,
  limite, invalidação, progresso inválido, revisão e soft delete), `estruturaUiSeguranca.test.ts`
  (listas de exceção) e o teste de paridade `goal.approve` (`authorizationPolicy.test.ts:909-916`).

## 16. Riscos

| # | Risco | Sev. | Mitigação (normativa) |
|---|---|---|---|
| R1 | Backfill sem bridge ⇒ metas órfãs | alta | D13 (pontes autoritativas + quarentena) |
| R2 | `goal.*` inacessível em produção | alta | D7 (concessão explícita) + teste de ALLOW real em P4 |
| R3 | Estado autorizativo do cliente virar verdade | alta | D2/D3 (aprovação como fato; status não representa aprovação) |
| R4 | Regra duplicada (limite/aprovação) | média | D4/D20 (invariante no banco) + §9.1 (fonte única) |
| R5 | Consumidores com identidades de ciclo heterogêneas | média | D24 + correção em `impactoCorrecaoPeriodoCiclo` (P6) |
| R6 | Deadlock entre RPC de ciclo e de meta | média | D10 (chave única e ordem única) |
| R7 | Guardas de “não antecipar F5-10” quebrarem o CI | baixa | atualização declarada em P1/P7 |
| R8 | Escopo vazar para F5-11 | média | `observation.*` intocado |
| R9 | Fail-closed silencioso (estrutura não carregada) | média | o caminho soberano expõe a indisponibilidade com fase explícita |
| R10 | Perda silenciosa do acervo legado no backfill | média | D13 (congelar/exportar + abortar em divergência) |
| R11 | `goal.read` de leitura de terceiros exposta por RLS sem gate funcional | alta | §11 (RPC de leitura com gate) |
| R12 | Participantes da avaliação podem receber *overlay* (substituição temporária/sucessão) **após** a ativação | média | D14 regra 4: ancorar na **ocorrência original** (`valid_from` mínimo) e nunca reescrever histórico (F5-06 D23) |

## 17. DECISÕES NORMATIVAS FECHADAS

| # | Decisão | Origem |
|---|---|---|
| D1 | Identidade canônica = `evaluation_goals.id` (uuid, do banco); `(ano,numero)`/matrícula = rótulos | auditoria |
| D2 | Aprovação é **fato** em tabela própria + evento; nunca campo do objeto nem status | auditoria |
| D3 | `status` não representa aprovação; “aprovada” é derivado | auditoria |
| D4 | Limites em `evaluation_cycle_goal_limits` (aditiva); proibido colunizar metas no ciclo | **Q5=A** |
| D5 | Exclusão apenas lógica (D9 da F5-09 preservado) | auditoria |
| D6 | Capabilities: **somente** `goal.read`/`goal.write`/`goal.approve`; nenhuma nova | **Q1=A** |
| D7 | Concessão: dono = read+write por SELF; aprovador = read+approve por escopo relacional; `goal.approve` **não** implica `goal.write`; concessões explícitas e testáveis em produção; **nenhuma** dependência de `localWorld`/DEV | **Q2=B** |
| D8 | `goal` é recurso soberano `{type:"goal", id:UUID}`; tenant/dono/estado do recurso real | **Q3=A** |
| D9 | Escrita é SELF; gestor/coordenador lê e aprova, **não** escreve meta de terceiro | **Q8** |
| D10 | Lock: **mesma** família dos ciclos, chave exata `hashtext('evaluation_cycles:' \|\| org)`; proibido lock independente/ordem incompatível | **Q6=A** |
| D11 | Trilha append-only + idempotência `(organization_id, operation_id)` + `payload_hash` server-side | auditoria |
| D12 | `expected_version` obrigatório em toda mutação; `version+1`; `F5_10_CONFLICT` | auditoria |
| D13 | Backfill só por pontes autoritativas; rejeições ⇒ quarentena; congelar/exportar; contagens; abortar em corrupção/divergência; proibido fabricar/descartar/fallback | **Q7=A** |
| D14 | Legitimidade de aprovação é **relacional**, derivada dos **participantes congelados da avaliação** (`GESTAO_CADEIA` = gerente; `GESTAO_DIRETA` = coordenador; **ocorrência original**); movimentação posterior não rematerializa; fail-closed | **Q4=A + B1 resolvido (§9.1/§9.1.1)** |
| D15 | Regra preservada: **gerente sempre exigido**; coordenador quando há nível intermediário; fail-closed sem evidência | **Q4=A** |
| D16 | `progresso_percentual`: inteiro informado, 0..100, validado server-side; **não** derivar de `resultadoAtual`/`valorAlvo` (texto); agregação de projeção = média aritmética simples com `Math.round`, **sem peso**, **sem** virar nota | **Q9+Q13 (consolidadas)** |
| D17 | Finalização **independente** de aprovação; 1ª finalização é transição explícita; alteração posterior é **revisão/re-finalização explícita** com `expected_version`+`operation_id`+evento específico, fechamento anterior recuperável; **sem estado REABERTA**; nunca sobrescrever silenciosamente | **Q10** |
| D18 | Correção do período do ciclo **não** invalida aprovação | **Q11** |
| D19 | Matriz normativa de invalidação (§9.4) | **Q10/Q11** |
| D20 | Quota é **invariante server-side**; banco bloqueia acima do limite; UI só projeta | **Q12** |
| D21 | Quota alterável no `ATIVO` por operação soberana explícita, gate administrativo **`cycle.manage`** (sem capability nova), `expected_version`, `operation_id`, evento, lock, e **nunca abaixo do existente** | **Q14** |
| D22 | RLS = isolamento/visibilidade de tenant; Policy Engine = autoridade funcional; `SELECT` own-tenant **não** concede `goal.read` funcional; leitura de terceiros com gate (§11) | revisão GPT |
| D23 | Edge `metas` + contrato transportável único; RPCs `SECURITY INVOKER` com `EXECUTE` só `service_role`; sem `.rpc(`/`SERVICE_ROLE_KEY` no cliente | auditoria |
| D24 | Cutover com barreira de escrita; leitura legada só para backfill; **sem fallback funcional após o cutover** | **Q7 + revisão GPT** |
| D25 | A projeção congelada que define os aprovadores é `evaluation_participants` da avaliação do ciclo (`GESTAO_CADEIA`/`GESTAO_DIRETA`, ocorrência original); snapshot de posições e `cycle_evaluation_responsibilities` ficam como defesa em profundidade | **B1 resolvido (§9.1.1)** |

**Rastreabilidade Q→D (nenhuma questão permanece aberta):** Q1→D6 · Q2→D7 · Q3→D8 · Q4→D14/D15 ·
Q5→D4 · Q6→D10 · Q7→D13/D24 · Q8→D9 · Q9+Q13→D16 (consolidadas) · Q10→D17/D19 · Q11→D18/D19 ·
Q12→D20 · Q14→D21. A numeração original de **Q9 e Q13** foi consolidada em **D16** por
duplicidade conceitual (progresso × agregação); a rastreabilidade dos dois números é preservada aqui.

## 18. BLOCKERS DOCUMENTAIS

**Nenhum blocker aberto.** **B1 foi RESOLVIDO** por auditoria read-only — ver §9.1 (regra) e §9.1.1
(prova arquitetural, com evidência nas migrations F3-08/F3-09/F5-06).

**Histórico do B1 (dúvida original e desfecho).** A dúvida era se a estrutura congelada permitia
reconstruir a **cadeia até a raiz** para determinar o **gerente**. A auditoria confirmou que:
`collegiate_cycle_snapshot_positions` registra **apenas o superior imediato** por posição ocupada
(`20260907180000:374-409`, comentário `:265-273`) e `cycle_evaluation_responsibilities` materializa o
**responsável avaliativo da posição do avaliado**
(`20260907190000:186-201`) — **nenhuma das duas guarda a raiz**. Porém a raiz **já é materializada**
por outro artefato soberano da F5-06: `evaluation_participants.role_type = 'GESTAO_CADEIA'`, derivado
de `organizacao_resolver_cadeia` no instante de referência
(`20260911010000:388-419`), com o coordenador em `'GESTAO_DIRETA'`. Logo **não é criada estrutura
nova** e D14/D15 são **refinadas** (§9.1), não substituídas.

**Itens de implementação já decididos (não são blockers):** substituição do invariante SQL que proíbe
metas (P1); capability administrativa da quota = `cycle.manage` (D21 — derivável do catálogo vigente
sem ampliar privilégio e sem capability nova); criação da RPC de leitura com gate (D22/§11).

## 19. Decomposição final (P1–P7)

> **P0 (contrato e decisões) está CONCLUÍDO por este documento.** A ordem abaixo é a recomendada;
> cada pacote é pequeno, auditável e tem gates próprios.

- **P1 — Schema, integridade e limites.** As 4 tabelas (§6.2), FKs compostas de tenant, unicidade
  parcial `(org, cycle_id, collaborator_id, tipo) where excluida = false`, `version`, triggers de
  `updated_at`, trilha append-only com os 3 triggers, ACL/deny-by-default, quota como invariante
  (guarda server-side), preflight + guarda final fail-closed; **substituir o invariante SQL que
  proíbe metas** e registrar a migration no `README`; cenário + validador P1.
- **P2 — Operações soberanas.** `meta_criar`, `meta_editar`, `meta_atualizar_progresso`,
  `meta_finalizar`, `meta_revisar_finalizacao`, `meta_excluir`, `meta_definir_limites_do_ciclo`
  (INVOKER, `EXECUTE` só `service_role`, `expected_version`, `operation_id`, idempotência, lock D10,
  eventos, invalidação conforme §9.4).
- **P3 — Aprovações e invalidação.** `meta_aprovar` + `meta_invalidar_aprovacoes`, tabela de
  aprovações, resolução relacional congelada (§9.1), regra preservada (§9.2), matriz §9.4;
  **derivação lida de `evaluation_participants`** — B1 resolvido (§9.1.1); sem blocker.
- **P4 — Autorização e RLS.** `goal` como tipo soberano (D8), matriz capability × estado com fonte
  única, `carregarRecurso` real de meta, escopos SELF/relacional, **concessão explícita** (D7) com
  teste de **ALLOW real em produção**, RLS own-tenant (policy antes do grant) e a **RPC de leitura
  com gate** (§11).
- **P5 — Edge e cliente.** `supabase/functions/metas` (trio + contrato), contrato transportável
  único, adapter fail-closed, guardas Edge→RPC e de grafo de imports.
- **P6 — Cutover e backfill.** Porta soberana de leitura própria, controlador de mutações, telas
  (`MinhasMetasPage`, `AcompanhamentoMetasPage`), consumidores de arrasto (feedback, detalhe, PDF,
  fechamento, impacto da correção — corrigindo a divergência de chave), **backfill com congelamento/
  exportação, contagens e quarentena** (D13) e barreira de escrita (D24).
- **P7 — Validação integrada.** Matriz de cenários SQL, **concorrência real entre duas sessões**
  (edição e aprovação), regressões P1–P8, ajuste das guardas invertidas e relatório de gates
  executados × não executados (molde `docs/F5-09-p9-matriz-integrada.md`).

## 20. Definição de pronto (DoD)

1. Container de metas no PostgreSQL com RLS own-tenant, escrita fechada e quota invariante.
2. Nenhuma autoridade funcional de meta no `localStorage`; nenhum fallback funcional.
3. `goal.*` decidível **em produção** pelo caminho canônico (sem `localWorld`).
4. Aprovação como fato auditável, com legitimidade **relacional congelada** e matriz §9.4 aplicada.
5. Trilha append-only com autoria soberana, `operation_id`, `payload_hash`; revisão de fechamento
   auditada (nunca sobrescrita).
6. Concorrência real provada entre duas sessões; `expected_version` e rollback comprovados.
7. Cutover das telas e dos consumidores com ciclo por UUID soberano; backfill com evidência de
   contagem e quarentena explícita.
8. Gates verdes (focados, suíte completa, build, lint, tsc, `git diff --check`, bateria SQL na ordem
   do CI) no SHA auditado; CI verde; auditorias GPT e Codex aprovadas.
9. F5-11 não antecipada; contratos da F5-09 (D1–D28) não reabertos.

---

### Anexo A — Método

Auditoria read-only por conteúdo (`meta`, `Meta`, `metaStorage`, `goal`, `peso`, `progresso`,
`aprovacao`, `coordenador`, `gerente`, `limite`, `quantidadeMetas`) em `src/`, `supabase/` e `docs/`;
leitura integral de `src/types/Meta.ts` e das partes relevantes de `src/services/metaStorage.ts`;
varredura dos `create table` das migrations (nenhuma tabela de metas); conferência dos padrões da
F5-09 nas migrations `20260915/16/17/18/19/20/21*`; três frentes independentes de auditoria
(modelo/lifecycle, consumo no cliente, autorização/RLS). Ausências são declaradas com o método de
busca. **Nenhum** `db reset`, `npm`, teste, build, lint ou `tsc` foi executado; a única verificação
desta rodada é `git diff --check`.
