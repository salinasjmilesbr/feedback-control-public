# F5-09 — Ciclos soberanos (desenho técnico)

> **Atividade:** F5-09 — Ciclos de avaliação no PostgreSQL (entidade de ciclo
> SOBERANA: identidade, estado, vigência, estrutura por ciclo e autorização).
> **Base:** `main` = `6550c81d14a9d3e61b3c1b4f49471948f880bbc8` (F5-08 P6
> integrado, PR #188).
> **Branch deste desenho:** `docs/f5-09-ciclos-soberanos`.
> **Natureza desta rodada:** DESENHO TÉCNICO — **nenhuma** implementação. Não há
> migration, RPC, Edge Function, capability, policy, teste de runtime nem
> alteração de frontend neste commit; todos os artefatos abaixo são contrato para
> as fases P1–P9 do §19.
> **Revisão 2 (ratificação):** as três dúvidas bloqueantes da rodada anterior
> foram **RATIFICADAS** pela auditoria GPT do desenho — Q-F5-09-1 (D8/D9:
> `PLANEJADO→CANCELADO` e proibição de exclusão física), Q-F5-09-2 (D26/D27:
> modelo híbrido de estrutura — população inicial na ativação, admissões
> posteriores **aditivas**, snapshots imutáveis e movimentações sem
> rematerialização) e Q-F5-09-3 (D28: `cycle.manage` no bundle `admin`). O
> documento foi revisado de ponta a ponta (§6, §7, §8, §10–§16, §17, §18, §19,
> §20) para eliminar contradições; **não há dúvida bloqueante aberta**.
> **Documento irmão:** `docs/F5-09-duvidas.md` — registro das três dúvidas
> **RATIFICADAS** (Q-F5-09-1..3) com a decisão final; nenhuma dúvida aberta.
> **Precedentes obrigatórios:** `docs/F5-06-desenho-tecnico.md` (avaliações),
> `docs/F5-07-desenho-tecnico.md` (colaboradores), `docs/F5-08-desenho-tecnico.md`
> (estrutura), `docs/F5-08-p6-duvida-mundo-funcional.md` (residuais declarados).

---

## 1. Objetivo

1. Tornar o **PostgreSQL a única autoridade de produção** sobre o ciclo de
   avaliação: existência, identidade, estado oficial, abertura, ativação,
   encerramento, cancelamento, reabertura, correção de período, vigência,
   organização proprietária, estrutura aplicável, elegibilidade oficial e
   transições permitidas.
2. Eliminar a autoridade local de ciclos (`localStorage`) **sem** criar uma
   segunda representação do mesmo conceito: a entidade soberana já existe
   (`public.evaluation_cycles`, F5-06 D15) e a F5-09 a **estende de forma
   aditiva**.
3. Definir a **estrutura POR CICLO** (§7) reusando o que já é soberano: snapshot
   de colegiado da F3-08 (`collegiate_cycle_snapshots` +
   `materializar_colegiado_ciclo`), responsabilidades avaliativas da F3-09
   (`cycle_evaluation_responsibilities`) e o congelamento de participantes da
   F5-06 (`evaluation_snapshot_participantes` / `evaluation_participants`).
4. Fechar a superfície de **autorização, RLS, integridade, concorrência,
   idempotência e auditoria** do domínio de ciclos, reusando integralmente os
   modelos F4-08/F5-04/F5-05/F5-06/F5-07/F5-08 — sem capability nova e sem
   tabela concorrente.
5. Classificar e executar o **cutover do cliente** (§14) sob o mesmo framework
   A/B/C/D do P6 da F5-08, preservando compatibilidade com F5-06 (avaliações
   soberanas), F5-07 (identidade UUID de colaborador) e F5-08 (estrutura UUID,
   RLS, capabilities, fail-closed, multi-tenant).
6. Entregar a **capacidade que a F5-07 declarou pendente**: o filtro de histórico
   do colaborador por ciclo (`supabase/functions/colaboradores/index.ts`, §"filtrar
   por ciclo depende da entidade de ciclo soberana (F5-09)") passa a usar o
   `cycle_id` UUID já existente em `collaborator_events.reference_cycle_id`.
7. Entregar a **única ampliação de população permitida depois da ativação** (D26):
   a operação soberana, explícita, auditada e **exclusivamente aditiva** que
   incorpora ao ciclo corrente o colaborador admitido **após** a ativação, com
   prova soberana de admissão, sem parâmetros estruturais e sem jamais alterar
   snapshot existente — e **sem** nenhuma operação genérica de rematerialização de
   estrutura (D27 mantém movimentações valendo no próximo ciclo).

**Fora de escopo (declarado, não silencioso):** metas (`goals`), observações
(`observations`), relatórios/PDF e a remoção da ponte matrícula → UUID de
colaborador (residual F5-07/F5-08). A quota de metas do ciclo
(`quantidadeMetasNegocio`/`quantidadeMetasIndividuais`) é atributo do domínio de
**metas** — ver D24 e §3.

---

## 2. Inventário atual (auditado na base `6550c81`)

### 2.1 Autoridade local no cliente (hoje)

| Superfície | Papel hoje |
| --- | --- |
| `src/services/cicloAvaliacaoStorage.ts` (527 linhas) | **Autoridade real.** `STORAGE_KEY = "feedback-control-ciclos"`; cria/semeia ciclos a partir de pares de `getFeedbacks()` quando a chave não existe (`crypto.randomUUID()` como id, primeiro `ATIVO`, restantes `ENCERRADO`); valida transições; persiste cancelamento/reabertura/correção de período com autoria fornecida pelo cliente (`autorMatricula`/`autorNome`) |
| `src/types/CicloAvaliacao.ts` | Modelo local: `id` local, `ano`, `ciclo` (1\|2\|3), datas, quota de metas, `status`, arrays de histórico (`encerramentos`, `reaberturas`, `correcoesPeriodo`, `cancelamento`) |
| `src/application/ports/CycleRepository.ts` + `src/infrastructure/localStorage/localCycleRepository.ts` | Porta + adaptador local (`getCiclosAvaliacao`, `getCicloAtivo`) |
| `src/services/cancelamentoCicloService.ts`, `reaberturaCicloService.ts`, `correcaoPeriodoCicloService.ts` | Fluxos excepcionais com `authorize()` sobre o ciclo **local** e persistência local |
| `src/services/cicloEquipeService.ts` | `criarAvaliacoesDoCicloAtivado`, `getPainelCiclo`, `analisarPendenciasDoCiclo`, `concluirAvaliacoesNoEncerramentoDoCiclo` |
| `src/services/metaStorage.ts`, `observacaoStorage.ts`, `historicoOrganizacionalStorage.ts`, `permissaoAvaliacao.ts`, `progressoAvaliacao.ts`, `exportarAvaliacaoPdf.ts`, `geradorDadosTeste.ts` | Consomem `getCiclosAvaliacao()`/`getCicloAtivo()` para decidir/rotular por ciclo |
| 12 páginas/componentes | `CiclosAvaliacaoPage`, `PainelCicloPage`, `PainelCiclosCoordenadorPage`, `MinhaAvaliacaoPage`, `MinhaAvaliacaoDetalhePage`, `MinhasMetasPage`, `AcompanhamentoMetasPage`, `NovoFeedbackPage`, `EditarFeedbackPage`, `FeedbackDetalhePage`, `RelatoriosPage`, `ColaboradorDetalhePage`, `ColaboradoresPage`, `ObservacoesColaborador` |

Total: **21 arquivos de produção** leem ou escrevem ciclo local (§14 traz a
classificação A/B/C/D de cada um).

### 2.2 Autoridade no PostgreSQL (já existente, NÃO recriar)

| Objeto | Papel soberano | Observação |
| --- | --- | --- |
| `public.evaluation_cycles` | Entidade de ciclo: `id uuid PK`, `organization_id`, `ano`, `numero`, `status`, `data_inicio`/`data_fim` (`date`), `data_ativacao`/`data_encerramento` (`timestamptz`), `encerrado_com_pendencias`, `quantidade_pendencias`, `config_version_id`, `version`, `created_at`/`updated_at` | `uq_evaluation_cycles_org_ano_numero`, `uq_evaluation_cycles_id_organization`, FK composta para `evaluation_config_versions (id, organization_id)`, CHECKs de status/`numero`/`ano`/período/pendências, trigger de `updated_at` |
| `public.evaluations`, `evaluation_participants`, `evaluation_events`, `evaluation_pendencies` | Avaliações soberanas (F5-06) | `evaluations.cycle_id` FK composta; índice único parcial `uq_evaluations_org_cycle_collaborator_nao_cancelada` |
| `evaluation_ator_valido(p_actor_user_profile_id, p_organization_id)` | Validação soberana de ator (membership ativa) | Reusar em todo RPC de ciclo |
| `evaluation_config_bootstrap(p_organization_id, p_actor_user_profile_id)` | Bootstrap soberano da versão de configuração | Fonte de `config_version_id` do ciclo |
| `evaluation_snapshot_participantes(p_organization_id, p_evaluation_id, p_evaluated_collaborator_id, p_cycle_id, p_instante, p_actor_user_profile_id)` | Congela participantes da avaliação a partir do snapshot F3-08 e resolve gestor direto/cadeia no `reference_date` | Não reimplementar |
| `evaluation_criar(p_organization_id, p_cycle_id, p_evaluated_collaborator_id, p_actor_user_profile_id)` | Criação de avaliação ancorada no **UUID do ciclo** e na versão de configuração **do ciclo** | Já UUID-first |
| `evaluation_pendencias_calcular(p_evaluation_id)` | Pendências por avaliação | Reusar |
| `evaluation_fechar_ciclo_pendencias(p_cycle_id, p_organization_id, p_actor_user_profile_id) returns integer` | Marca pendências **permanentes**, atualiza `encerrado_com_pendencias`/`quantidade_pendencias`/`version`, idempotente; **não** converte avaliação incompleta em `CONCLUIDA` | **Reusar no encerramento do ciclo** (D10) |
| `evaluation_concluir` / `evaluation_reabrir` / `evaluation_cancelar` | Transições de avaliação | Reusar nos efeitos do ciclo |
| `evaluation_resolver_ciclo(p_organization_id, p_ano, p_numero, p_actor_user_profile_id) returns uuid` | Ponte INTENÇÃO `(ano, numero)` → UUID do ciclo | Dívida controlada (D3) |
| `collegiate_cycle_snapshots` (+ `_positions`, `_members`), `materializar_colegiado_ciclo(p_organization_id, p_ano, p_ciclo, p_reference_date, p_evaluated_collaborator_ids uuid[])` | Snapshot temporal de colegiado por ciclo (F3-08), idempotente (`on conflict do nothing`) | Business key `(organization_id, ano, ciclo, collaborator_id)`; comentário original: "sem tabela de ciclos (integração futura)" |
| `cycle_evaluation_responsibilities` (F3-09) | Titular permanente + sucessão (fecha/abre vigência) + substituto como overlay vivo | Exclusion por sobreposição |
| `collaborator_events.reference_cycle_id` (F5-07) | Histórico do colaborador ancorado em ciclo | Habilita o filtro por ciclo pendente na F5-07 |
| `user_has_active_membership(organization_id)` (F4-08) | Helper de tenant da RLS SELECT own-tenant | Reusar na policy de leitura do ciclo |
| Capabilities no catálogo (F4-01/F5-04) | `cycle.read`, `cycle.manage`, `cycle.cancel`, `cycle.reopen`, `cycle.period.correct` (+ aliases `*.manager`, `cycle.management.view`, `cycle.coordinator.list`, `cycle.team.panel.view`) | **Nenhuma capability nova** (D20) |

### 2.3 Fronteira hoje

- **Escrita:** não existe RPC nem Edge de ciclo. `evaluation_cycles` só é
  inserida por fixtures/validadores. Nenhuma operação de ciclo é executada
  server-side.
- **Leitura:** o cliente **não** lê `evaluation_cycles` (o descritor em
  `src/infrastructure/supabase/avaliacoes/consultasAssigned.ts` é consumido por
  `src/services/avaliacoesSoberanas/assignedSoberano.ts`, cujo caminho de
  produção é a Edge `supabase/functions/avaliacoes/assignedSupabase.ts`).
- **RLS:** `evaluation_cycles` tem RLS **habilitada**, **zero policies** e
  `revoke all` de `anon`/`authenticated`/`service_role` com grants apenas a
  `service_role` (F5-06). Ou seja: hoje `authenticated` não vê nenhuma linha
  (deny-by-default).
- **Ponte ano+número:** viva em dois pontos — `evaluation.resolver_ciclo` (Edge
  `avaliacoes`) e `assignedSupabase.ts` (`(ano, numero) → cycle UUID` para
  traduzir snapshots F3-08). O snapshot F3-08 continua **keyed por ano+ciclo**.
- **Elegibilidade para nova avaliação:** a Edge `avaliacoes` considera
  `cicloPermiteNovaAvaliacao = exists(ciclos do tenant com status em
  (PLANEJADO, ATIVO))` e exige `cycle_id` na criação.
- **Gateway de estrutura por ciclo:** `collegiate_cycle_snapshots` e
  `cycle_evaluation_responsibilities` **já têm** SELECT para `authenticated` por
  tenant (F4-08), mas o cliente só as consome indiretamente (via Edge).

### 2.4 Lacunas de autorização encontradas (corrigir na F5-09, sem capability nova)

1. `src/authorization/authorizationPolicy.ts`, `case "cycle"`, mapeia apenas
   `cycle.cancel`, `cycle.period.correct` e `cycle.reopen`; `cycle.read` e
   `cycle.manage` caem no `default → null` ⇒ **DENY** (`montarContexto` nulo). O
   gate real de gestão de ciclo **não é executável hoje** contra um recurso
   `cycle` real.
2. `cycle.cancel` exige `status === "ATIVO"` e `cycle.reopen` exige
   `status === "ENCERRADO"` — coerentes com o produto local
   (`persistirCancelamentoCicloAuditadoInterno` exige `ATIVO`;
   `persistirReaberturaCicloAuditadaInterno` exige `ENCERRADO`) e com as
   descrições do catálogo F5-04. Qualquer ampliação é decisão explícita (D8).
3. O recurso `cycle` do engine recebe `resource.cycle.id`/`resource.cycle.status`
   **do chamador**. Em produção isso tem de vir da linha soberana lida
   server-side; status/datas locais nunca podem alimentar o enforcement.
4. Criação não tem recurso `cycle` (o ciclo ainda não existe) e a F5-05
   D19/D22 **proíbe** alvo sintético (`{type:"cycle", id:"global"}`) como prova
   de autorização. Precisa de decisão explícita de plano (D21).
5. Nenhuma role de sistema concede `cycle.manage` (o bundle `admin` recebe
   apenas `cycle.read`); `cycle.cancel`/`cycle.reopen`/`cycle.period.correct`
   foram criados depois da formação do bundle e também não estão nele. Isso
   torna a viabilidade do cutover dependente de configuração de role —
   resolvido pela **D28** (ratificada na Q-F5-09-3): `cycle.manage` entra
   aditivamente no bundle `admin` e as três excepcionais permanecem sob
   configuração explícita.

---

## 3. Problemas e resíduos a resolver

| # | Problema | Evidência | Tratamento na F5-09 |
| --- | --- | --- | --- |
| E1 | Existência do ciclo decidida no cliente; ciclos **semeados** a partir de avaliações legadas | `getCiclosAvaliacao()` cria ciclos quando a chave não existe | Estado soberano no PG; semente local vira cache de UX (D) |
| E2 | Identidade do ciclo é um UUID local; `ano`+`ciclo` funcionam como identidade prática | `CicloAvaliacao.id`; telas buscam por `item.id`; navegação por `ano`/`ciclo` | UUID canônico do banco (D2); `ano`+`numero` só identificador humano (D3) |
| E3 | Status oficial decidido e transicionado no cliente (`validarTransicaoNormal`) | `ativarCiclo`/`encerrarCiclo`/`atualizarStatusCiclo` | Máquina de estados no banco (§6, §13) |
| E4 | Regra "um ciclo ATIVO por organização" só existe no cliente | `ativarCiclo` procura `outroAtivo` | Índice único parcial no banco (D14) |
| E5 | Autoria fornecida pelo cliente (`autorMatricula`/`autorNome` em cancelamento, reabertura, correção, encerramento) | `CicloAvaliacao.ts` | Autoria sempre `auth.uid()` + membership (D23, §12) |
| E6 | Exclusão física de ciclo planejado existe no cliente | `excluirCiclo` | **D9 ratificada na Q-F5-09-1**: exclusão física proibida; o fluxo equivalente é `PLANEJADO→CANCELADO` (T5) |
| E7 | Histórico em arrays locais (`encerramentos`, `reaberturas`, `correcoesPeriodo`) | `cicloAvaliacaoStorage` | Trilha append-only `cycle_events` (§12) |
| E8 | Estrutura "por ciclo" não tem dono claro no cliente (cada tela recalcula) | `progressoAvaliacao`, `cicloEquipeService`, `metaStorage` | Estrutura por ciclo soberana (§7) + projeção única |
| E9 | Ponte `(ano, numero) → UUID` duplicada na fronteira | `evaluation.resolver_ciclo`, `assignedSupabase` | Mantida apenas como INTENÇÃO de tela, com condição de remoção (D3) |
| E10 | Superfície de leitura de ciclo ausente para `authenticated` | RLS sem policy em `evaluation_cycles` | Policy + grant de leitura own-tenant (§9) |
| E11 | Gate real de `cycle.read`/`cycle.manage` inexistente | §2.4 | Fechamento aditivo do Policy Engine (D20, §8) |
| E12 | Filtro de histórico do colaborador por ciclo declarado pendente na F5-07 | comentário na Edge `colaboradores` | Entregue por `cycle_id` (UUID) já existente (§13.6) |
| E13 | Quota de metas do ciclo só existe local e não há domínio de metas no PG | `quantidadeMetasNegocio`/`quantidadeMetasIndividuais` | Residual declarado para a F5-10 (D24) |
| E14 | Relatórios/PDF e `historicoOrganizacionalStorage` ainda rotulam por ciclo local | residual declarado no P6 da F5-08 | Leitura legada autorizada (B) e atividade própria declarada (§14, §16 R11) |
| E15 | Não existe **nenhum** caminho (local ou soberano) para incorporar ao ciclo corrente o colaborador admitido após a ativação | `criarAvaliacoesDoCicloAtivado` só roda na ativação | **D26** (ratificada): operação restrita, aditiva e auditada de inclusão de nova admissão (§7.2/§7.3, P3) |
| E16 | A prova de "nova admissão" não pode vir do cliente | `collaborators.admission_date` é dado **declarado** (F5-07 D3/D6) | Prova soberana em `collaborator_events.event_type = 'ADMISSAO'` + `collaborator_status_periods` (§7.2); ausência de prova ⇒ recusa (fail-closed) |

---

## 4. Modelo soberano proposto

Princípios (herdados de F5-08 §19.1–§19.3 e F5-05/F5-06):

1. **PostgreSQL é a única autoridade de produção.** O cliente pode ter cache,
   dados de DEV/teste e preferências de UX; nunca autoridade sobre existência,
   identidade, estado, vigência, estrutura aplicável ou transições do ciclo.
2. **Nenhuma segunda representação do mesmo conceito.** Nada de tabela nova de
   ciclo, de estrutura por ciclo ou de versão de configuração. Extensão aditiva
   de `evaluation_cycles` + trilha nova (justificada) + RPCs.
3. **UUID-first.** Toda referência interna a ciclo usa `evaluation_cycles.id`.
4. **Sem escrita dupla.** Enquanto o cutover não termina, a operação soberana
   é a única que grava; o caminho local vira barreira (falha explícita) ou cache.
5. **Fail-closed.** Sem identidade, sem membership ativa, sem capability, sem
   alvo soberano resolvido, sem versão de configuração ou com estado
   indeterminado ⇒ recusa, sem tocar em RPC privilegiada.
6. **Cross-tenant é DENY.** Toda RPC revalida `organization_id` da linha do ciclo
   contra o tenant do ator verificado; divergência nunca retorna dado.
7. **`service_role` executa, nunca decide autorização.** O gate é da Edge
   (Policy Engine / plano administrativo F5-04 D19); as RPCs revalidam em
   profundidade (ator, tenant, capability, estado, versão).
8. **Nada se apaga.** Nenhum `DELETE` em ciclo, avaliação, snapshot ou trilha;
   história preservada por append-only + versionamento otimista.
9. **Congelamento explícito por ciclo.** A estrutura aplicável a um ciclo é a
   vigente no instante da ativação; fatos passados nunca são reinterpretados com
   a estrutura atual (§7).

Arquitetura de camadas (mesma dos domínios F5-07/F5-08):

```
telas (React)  ──►  porta única do cliente (services/acessoCiclosSoberanos.ts)
                          │
                          ├─ leitura:  PostgREST sob RLS (evaluation_cycles + snapshots)
                          └─ mutação:  Edge Function `ciclos` (Policy Engine) ──► RPCs `ciclo_*`
                                                                                   (SECURITY INVOKER,
                                                                                    EXECUTE só service_role)
                                                                                        │
                                                                        evaluation_cycles + cycle_events
                                                                        + reuso das RPCs `evaluation_*`
                                                                        + materializar_colegiado_ciclo (F3-08)
```

---

## 5. Identidade

- **Identidade canônica:** `public.evaluation_cycles.id` (`uuid`,
  `gen_random_uuid()`), já existente desde a F5-06 D15. É o valor que trafega
  entre camadas, que aparece em `evaluations.cycle_id`, em
  `collaborator_events.reference_cycle_id`, na trilha e no alvo de autorização
  `{ type: "cycle", id }`.
- **Identificador humano:** `(ano, numero)` continua sendo o rótulo exibido
  ("2026 • Ciclo 2") e a regra de unicidade de negócio por organização
  (`uq_evaluation_cycles_org_ano_numero`). Não é identidade interna, não é
  chave de cache, não é parâmetro de escrita.
- **Vedado:** usar índice de array, posição na lista, `ano+ciclo` concatenado,
  chave de `localStorage`, matrícula ou texto de função como identidade de ciclo.
- **Resolução de intenção:** quando a tela legada conhece apenas `(ano, numero)`,
  a fronteira confiável resolve para UUID **antes** de qualquer decisão de
  autorização/de escrita (`evaluation_resolver_ciclo` para o caminho F5-06;
  `cycle.resolver` na Edge `ciclos` para o caminho novo). Não resolver ⇒ recusa.
- **Ponte como dívida controlada (D3):** `evaluation_resolver_ciclo` e o mapa
  `(ano, numero) → UUID` de `assignedSupabase.ts` permanecem porque o snapshot
  F3-08 usa `(organization_id, ano, ciclo, collaborator_id)` como business key.
  Condição de remoção: quando o snapshot F3-08 passar a referenciar `cycle_id`
  (atividade futura, fora da F5-09). A F5-09 **não** altera o contrato da F3-08.
- **Migração de identidade local → UUID:** a cache de UX guarda
  `{ cycleId (UUID soberano), ano, numero, status, periodo }`; ids locais não são
  promovidos, não são convertidos por heurística e não sobrevivem ao cutover.

---

## 6. Máquina de estados

Estados (CHECK já existente em `evaluation_cycles`): `PLANEJADO`, `ATIVO`,
`ENCERRADO`, `CANCELADO`. **Nenhum estado novo.**

| # | Origem | Destino | Quem pode executar | Capability | Pré-condições | Efeitos transacionais | Reversível |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T0 | — | `PLANEJADO` | Ator com capability efetiva de gestão de ciclo | `cycle.manage` (plano administrativo, D21) | Ator válido (`evaluation_ator_valido`); tenant ativo; `ano` 2000–2100; `numero` ∈ {1,2,3}; `data_inicio ≤ data_fim`; sem violar unique `(org, ano, numero)` nem sobreposição (D15); sem ciclo sobreposto não cancelado | `insert evaluation_cycles` (`status='PLANEJADO'`, `version=0`, `config_version_id` do bootstrap soberano); evento `CRIADO` em `cycle_events` | Ciclo PLANEJADO é editável e cancelável (não há "desfazer") |
| T1 | `PLANEJADO` | `PLANEJADO` | idem | `cycle.manage` (funcional, alvo `{cycle, UUID}`) | Estado atual `PLANEJADO`; `expected_version` confere; edição de `ano`/`numero`/`data_inicio`/`data_fim`/`config_version_id` respeita unicidade e sobreposição | `update` + `version+1`; evento `EDITADO` com `before_value`/`after_value` | Sim (nova edição auditada) |
| T2 | `PLANEJADO` | `ATIVO` | idem | `cycle.manage` (funcional) | Estado `PLANEJADO`; `config_version_id` **não nulo** (D19); nenhum outro `ATIVO` na organização (D14, garantido por índice único parcial); `expected_version` confere | `materializar_colegiado_ciclo(org, ano, numero, p_reference_date = data_ativacao::date, ids elegíveis)` (F3-08, idempotente) **antes** do update; `status='ATIVO'`, `data_ativacao=now()`, `version+1`; evento `ATIVADO` | Sim — `ATIVO → ENCERRADO → ATIVO` (T6) |
| T3 | `ATIVO` | `ENCERRADO` | idem | `cycle.manage` (funcional) | Estado `ATIVO`; `expected_version` confere | `evaluation_fechar_ciclo_pendencias(cycle_id, org, ator)` (F5-06, idempotente: marca pendências permanentes nas avaliações incompletas e grava `encerrado_com_pendencias`/`quantidade_pendencias`/`version`); depois `status='ENCERRADO'`, `data_encerramento=now()`, `version+1`; evento `ENCERRADO` com contagens | Sim — reabertura (T6) |
| T4 | `ATIVO` | `CANCELADO` | Ator com capability efetiva de cancelamento | `cycle.cancel` (funcional; `domainState` ampliado — D8 ratificada) | Estado `ATIVO`; `motivo` obrigatório (não vazio, sem espaços nas bordas); `expected_version` confere | Na **mesma transação**: `evaluation_cancelar` para cada avaliação do ciclo com status ∉ {`CONCLUIDA`, `CANCELADA`} (preserva concluídas); `status='CANCELADO'`, `version+1`; evento `CANCELADO` com motivo e contagens | **Não** — `CANCELADO` é terminal (reativação proibida, D8) |
| T5 | `PLANEJADO` | `CANCELADO` | idem T4 | `cycle.cancel` | Estado `PLANEJADO`; `motivo` obrigatório; sem avaliações no ciclo (fail-closed se houver: o operador cancela as avaliações antes — a criação exige ciclo PLANEJADO/ATIVO); `expected_version` confere | `status='CANCELADO'`, `version+1`; evento `CANCELADO` com motivo | **Não** (D8 ratificada na Q-F5-09-1 substitui a exclusão física; `CANCELADO` é terminal) |
| T6 | `ENCERRADO` | `ATIVO` | Ator com capability efetiva de reabertura | `cycle.reopen` (funcional; `domainState` `ENCERRADO`, já no contrato) | Estado `ENCERRADO`; `motivo` obrigatório; nenhum outro `ATIVO` na organização; `expected_version` confere | `status='ATIVO'`, `data_encerramento=null`, `version+1` (o histórico de encerramento **permanece** em `cycle_events`); evento `REABERTO` | Sim (novo encerramento é novo evento) |
| T7 | `ATIVO` | `ATIVO` (correção de período) | Ator com capability efetiva de correção | `cycle.period.correct` (funcional; `domainState` `ATIVO`, já no contrato) | Estado `ATIVO`; `data_inicio ≤ data_fim`; período diferente do atual; `justificativa` obrigatória; sem sobreposição (D15) | `update` das datas + `version+1`; evento `PERIODO_CORRIGIDO` (`before_value`/`after_value` + `impacto` calculado server-side); **não** altera snapshot, avaliações ou participantes já congelados | Sim (nova correção auditada) |
| T8 | `ATIVO`/`ENCERRADO`/`CANCELADO` | mesmo estado | qualquer | — | Operação repetida com **mesmo** `operation_id` e **mesmo** `payload_hash` | Nenhum efeito novo: a RPC devolve o resultado registrado (idempotência por `uq_cycle_events_org_operation`) | n/a |
| T9 | qualquer | — | qualquer | — | Transição não listada (ex.: `ENCERRADO → CANCELADO`, `CANCELADO → ATIVO`, `PLANEJADO → ENCERRADO`) | Recusa `CONFLICT`, nada gravado, nenhuma trilha de mutação | n/a |
| T10 | qualquer | — | qualquer | — | Exclusão física (`DELETE`) | **Proibida** por ausência de grant a todos os papéis de aplicação + decisão D9 | n/a |

**A inclusão aditiva de nova admissão (D26) não é transição de estado:** o ciclo
permanece `ATIVO` e nada muda em `status`, `data_*` ou contagens de pendência —
ela é operação de **população/estrutura do ciclo**, descrita no §7 (§7.1–§7.3), e
por isso não aparece como origem/destino na tabela acima. Exige ciclo `ATIVO`
(`domainState`) e é registrada na trilha pelo evento `ADMISSAO_INCLUIDA`.

Regras derivadas que **reusam contratos já existentes** (não são invenção da
F5-09):

- `authorizationPolicy.ts` já trata `cicloStatus === "CANCELADO"` como bloqueio
  para `evaluation.write`, `evaluation.cancel`, `evaluation.reopen` e
  `evaluation.create`. Por isso o cancelamento do ciclo **precisa** resolver as
  avaliações na mesma transação (T4): depois de `CANCELADO`, a avaliação não
  poderia mais nem ser cancelada pelo caminho normal.
- Após `ENCERRADO`, `evaluation.reopen` fica falso no `domainState` (contrato já
  existente) ⇒ encerrar congela a reabertura de avaliação; reabrir o ciclo (T6)
  a reabilita. Coerente com T3/T6.
- `quantidade_pendencias`/`encerrado_com_pendencias` são escritos **apenas** por
  `evaluation_fechar_ciclo_pendencias` (F5-06). A F5-09 não recalcula pendências
  no Edge nem no cliente.

---

## 7. Estrutura e snapshot por ciclo

A F5-09 **não cria** estrutura por ciclo: ela define **como** a estrutura
soberana existente é materializada, **o que** é imutável e **qual** a única
ampliação permitida depois da ativação. O modelo é **híbrido** (D26/D27) e a
expressão "congelamento na ativação", isoladamente, **não** descreve o contrato:

1. **População inicial materializada na ativação** (T2) — base do ciclo.
2. **Admissões posteriores elegíveis podem ser ACRESCENTADAS** ao ciclo corrente
   por operação soberana, explícita, auditada e **exclusivamente aditiva** (D26).
3. **Snapshots existentes são imutáveis** — nenhuma operação sobrescreve,
   recalcula ou remove linha já materializada.
4. **Movimentações não provocam rematerialização** — mudança de posição,
   unidade, gestor, reporting line ou colegiado posterior à entrada do
   colaborador no ciclo vale **no próximo ciclo** (D27).

**Insumos soberanos:** relações de gestão por posição
(`position_reporting_lines`, F3-04; soberanas desde a F5-08), ocupações
(`occupations`), colaboradores UUID (F5-07), snapshot de colegiado por ciclo
(`collegiate_cycle_snapshots` + `_positions` + `_members`, F3-08),
responsabilidades avaliativas (`cycle_evaluation_responsibilities`, F3-09) e o
congelamento de participantes da avaliação (`evaluation_participants`, F5-06).
Hierarquia **nunca** vem de `funcao` (texto) nem de matrícula.

### 7.1 Respostas às perguntas do escopo (oito originais + admissão posterior)

1. **Quando a estrutura é materializada.** Na transição `PLANEJADO → ATIVO` (T2),
   materializando o snapshot F3-08 com `p_reference_date` = data da ativação
   (`data_ativacao`) para os colaboradores elegíveis; a partir daí os
   participantes de cada avaliação são congelados por
   `evaluation_snapshot_participantes` no momento da criação. Antes da ativação
   não há estrutura de ciclo (não se avalia ciclo inexistente — fail-closed).
2. **Imutável × dinâmico.**
   *Imutável:* as linhas já materializadas no ciclo (posição e superior no
   `reference_date`, composição do colegiado do ciclo, participantes/responsáveis
   de cada avaliação criada), a versão de configuração do ciclo e o histórico.
   *Dinâmico:* nome e atributos cadastrais do colaborador (UUID não muda), estado
   de vínculo (ativo/afastado/desligado) e o overlay temporal de responsabilidade
   F3-09 para avaliações **ainda não criadas**. A população do ciclo pode
   **crescer** por admissão elegível (D26) e **nunca** é recalculada (D27).
3. **Colaborador muda de posição (D27).** O snapshot do ciclo mantém a posição
   vigente no `reference_date`; as avaliações já criadas não mudam; o histórico
   não é reinterpretado; a mudança vale **no próximo ciclo**. Se a movimentação
   ocorrer **antes** da ativação (ou antes da inclusão aditiva), vale a estrutura
   vigente no momento da materialização.
4. **Gestor muda (D27).** Duas camadas coexistem e continuam **separadas**:
   (a) o snapshot F5-06 resolve gestor direto/cadeia **no `reference_date` do
   ciclo** — determinístico e insensível a mudanças posteriores; (b)
   `cycle_evaluation_responsibilities` (F3-09) é temporal e resolvida por
   vigência na leitura/atribuição. Mudança de gestor **não** rematerializa o
   ciclo: avaliações já criadas preservam o congelado; sucessão/realinhamento
   continuam existindo como mecanismos excepcionais já contratados (F3-09/F5-06),
   sem recalcular o snapshot inteiro.
5. **Colegiado muda (D27).** A composição congelada do ciclo permanece. Alterar a
   configuração de colegiado **não** reescreve `collegiate_cycle_snapshot_members`
   do ciclo corrente: a mudança vale no próximo ciclo. Não existe operação
   genérica de recálculo de colegiado.
6. **Colaborador admitido após a ativação (D26).** **Pode** ser incorporado ao
   ciclo corrente por operação soberana, explícita, auditada e exclusivamente
   aditiva (§7.2/§7.3), desde que a nova admissão seja provada server-side.
   É a **única** ampliação permitida depois da ativação.
7. **Colaborador desligado ou afastado.** O snapshot permanece (história
   preservada); a avaliação já criada permanece íntegra; **novas** avaliações do
   ciclo para esse colaborador são recusadas pela elegibilidade soberana
   (vínculo/ocupação vigentes) — fail-closed, sem apagar nada.
8. **Qual estrutura vale para avaliações já iniciadas.** A congelada na criação
   da avaliação (`evaluation_participants`). Mudança exigiria realinhamento
   explícito e auditado (`evaluation_participante_realinhar`, F5-06), com motivo —
   o que **não** equivale a recalcular o snapshot do ciclo.
9. **Como o histórico é preservado.** Snapshots imutáveis + congelamento por
   avaliação + trilha append-only + `version`/`expected_version` + ausência de
   `DELETE`. A leitura de histórico por UUID do ciclo nunca reinterpreta o
   passado com a estrutura atual.

### 7.2 Prova soberana de nova admissão (D26)

A operação de inclusão aditiva **não aceita flag nem declaração do cliente**. A
condição é provada server-side com dados temporais já existentes:

| # | Prova | Regra |
| --- | --- | --- |
| P1 | **Evento soberano de admissão** | `exists (select 1 from public.collaborator_events e where e.organization_id = <org> and e.collaborator_id = <UUID> and e.event_type = 'ADMISSAO' and e.cycle_scope = 'CICLO_ATUAL_E_POSTERIORES' and e.effective_date > <ciclo.data_ativacao>)` — evento append-only gravado por `colaborador_criar` (F5-07 D8/D26) na mesma transação da criação, com autoria soberana, motivo, `effective_date` e `operation_id` |
| P2 | **Ausência de vida anterior na organização** | `not exists (select 1 from public.collaborator_status_periods p where p.collaborator_id = <UUID> and p.valid_from < <ciclo.data_ativacao>)` — se existir qualquer período de status anterior à ativação, a pessoa **não** é nova admissão e a operação é recusada |
| P3 | **Aditividade** | `not exists (select 1 from public.collegiate_cycle_snapshots s where s.organization_id = <org> and s.ano = <ano> and s.ciclo = <numero> and s.collaborator_id = <UUID>)` — já materializado ⇒ recusa (`CONFLICT`), nunca sobrescrita |
| P4 | **Ciclo ativo do tenant** | `evaluation_cycles.status = 'ATIVO'` e `organization_id` do ciclo = tenant do ator |
| P5 | **Elegibilidade vigente na inclusão** | colaborador com status `active` vigente (`collaborator_status_periods`, meio-aberto) **e** estrutura soberana resolvível na data da inclusão (ocupação vigente em `occupations`, com reporting line vigente quando houver) — os mesmos insumos do snapshot F3-08 |
| P6 | **Escopo de ciclo do evento** | `cycle_scope = 'SOMENTE_CICLOS_POSTERIORES'` ⇒ **recusa** (aplicação, pela F5-09, da regra de baseline da F5-07 §11.2, cuja "aplicação a um ciclo concreto é da F5-09") |
| P7 | **Ausência de prova ⇒ fail-closed** | colaborador **sem** evento `ADMISSAO` (legado/importado/fora do caminho soberano) ⇒ **recusa**. A coluna `collaborators.admission_date` é **dado declarado de cadastro** (F5-07 D3/D6) e **não** serve como prova |

**Requisito técnico da implementação (não flexibilizar a regra):** se, em algum
cenário real, a prova P1/P2 não puder ser estabelecida server-side (por exemplo
colaborador importado sem evento `ADMISSAO`), a operação **recusa** — e a correção
é fazer o caminho de importação/legado gravar o evento soberano, com atividade
própria, e **não** afrouxar a prova nem usar a inclusão aditiva como mecanismo de
correção de materialização (ver §15 casos 5 e 11).

### 7.3 Contrato restrito da operação de inclusão (D26)

- **Nome:** operação de Edge `cycle.admissao.incluir`; RPC
  `ciclo_incluir_admissao`. **Não existe** operação chamada
  "rematerializar estrutura" nem equivalente genérico (D26).
- **Entrada:** `{ organizationId, cycleId (UUID), matricula (INTENÇÃO, resolvida
  na fronteira F3-01) | collaboratorId (UUID), operationId, expectedVersion }`.
  **Nenhum** parâmetro de posição, unidade, gestor, reporting line, colegiado,
  `reference_date` ou lista de colaboradores.
- **Impedimentos por construção:**

| Comportamento proibido | Mecanismo que impede |
| --- | --- |
| Atualizar participante já materializado | P3 (recusa `CONFLICT`) + `materializar_colegiado_ciclo` só faz `on conflict do nothing` e não possui `UPDATE` |
| Mudar a posição de participante existente | A operação não aceita posição; atua apenas sobre o `collaborator_id` solicitado; a posição vem de `occupations` vigente na data |
| Recalcular gestor | Nenhum parâmetro de gestor; o superior é resolvido no `reference_date` da **inclusão** para o snapshot novo, sem tocar em snapshots existentes |
| Recalcular colegiado existente | Os membros são congelados da configuração vigente **apenas para o snapshot novo**; snapshots existentes têm seus membros preservados (`not exists` por `snapshot_id` na RPC F3-08) |
| Sobrescrever snapshot | As três tabelas de snapshot recebem somente `INSERT` (a RPC F3-08 não contém `UPDATE`/`DELETE`) e a trilha `cycle_events` é append-only |
| Inclusão cross-tenant | Tenant revalidado no Edge e na RPC; `materializar_colegiado_ciclo` rejeita avaliado de outra organização (validação já existente na F3-08) |
| Inclusão sem comprovação de admissão | P1+P2+P6+P7, fail-closed |
| Uso genérico como "atualizar estrutura do ciclo" | Contrato restrito acima + prova de admissão + aditividade + trilha com `event_type = 'ADMISSAO_INCLUIDA'` e referência ao evento de admissão que a autorizou |

**Verificado na base (sem necessidade de grant novo):** `service_role` mantém
privilégios completos de tabela (F4-08 §1) e o `EXECUTE` de
`materializar_colegiado_ciclo` já é concedido a `service_role`
(`20260908100000_f4_08_helpers_function_grants.sql`), portanto a inclusão aditiva
reusa a RPC da F3-08 sem ampliar privilégio algum.

---

## 8. Autorização

**Plano único, sem capability nova (D20).** O mapa operação → capability é
**explícito** e sem fallback (padrão F5-08 `DEFINICAO_POR_OPERACAO` /
`capacidadeDaOperacao`): operação desconhecida ⇒ `null` ⇒ DENY.

| Operação | Capability | Plano | Alvo autorizável | `domainState` |
| --- | --- | --- | --- | --- |
| `cycle.criar` | `cycle.manage` | Administrativo (F5-04 D19): capability efetiva do ator na organização | — (não existe recurso `cycle`; nenhum alvo sintético — D21) | n/a |
| `cycle.ler` / `cycle.listar` | `cycle.read` | Funcional | `{ type: "cycle", id: UUID }`; lista ancorada no colaborador do próprio ator (padrão `alvoDaDecisao`) | ciclo existente no tenant |
| `cycle.editar` (PLANEJADO) | `cycle.manage` | Funcional | `{ type: "cycle", id: UUID }` | `status === "PLANEJADO"` |
| `cycle.ativar` | `cycle.manage` | Funcional | idem | `status === "PLANEJADO"` |
| `cycle.encerrar` | `cycle.manage` | Funcional | idem | `status === "ATIVO"` |
| `cycle.cancelar` | `cycle.cancel` | Funcional | idem | `status ∈ {PLANEJADO, ATIVO}` (ampliação de D8 — hoje `ATIVO`) |
| `cycle.reabrir` | `cycle.reopen` | Funcional | idem | `status === "ENCERRADO"` (já no contrato) |
| `cycle.corrigir_periodo` | `cycle.period.correct` | Funcional | idem | `status === "ATIVO"` (já no contrato) |
| `cycle.admissao.incluir` | `cycle.manage` | Funcional | idem | `status === "ATIVO"`; a **prova soberana de nova admissão** (§7.2) é revalidada na RPC (o `domainState` do engine não a substitui) |

Fechamentos aditivos exigidos em `src/authorization/authorizationPolicy.ts`
(nenhum deles cria capability):

1. `case "cycle"` ganha `cycle.read` e `cycle.manage` (hoje `default → null ⇒
   DENY`), com `domainState` conforme a tabela acima.
2. `cycle.cancel` passa a aceitar `PLANEJADO` **e** `ATIVO` (D8, ratificado na
   Q-F5-09-1), com atualização **aditiva** da descrição da capability no catálogo
   (sem remoção física de capability — F5-04 D14).
3. A lista de ciclos ("posso listar") precisa de alvo soberano real: o
   colaborador do próprio ator (mesmo padrão do F5-08 `alvoDaDecisao`), nunca
   `{type:"cycle", id:"global"}` (proibido pela F5-05 D19/D22).
4. O `resource.cycle.status`/`id` passados ao engine **devem** ser derivados da
   linha soberana lida server-side (Edge), nunca do corpo da requisição.

**Enforcement em profundidade no banco:** toda RPC `ciclo_*` revalida, na mesma
transação: (a) ator com perfil ativo e membership ativa no tenant
(`evaluation_ator_valido`, já existente); (b) presença do código de capability
exigido nas capabilities efetivas do ator (reuso do resolver F5-04
`resolver_capabilities_efetivas`, padrão do enforcement F5-08); (c) existência do
ciclo no tenant (senão `NOT_FOUND`/`FORBIDDEN` indistinguíveis, sem vazar
cross-tenant); (d) estado de origem permitido e `expected_version`; (e) motivo
obrigatório nos fluxos excepcionais. Divergência de tenant ⇒ DENY.

**Configuração de role (não é capability nova):** hoje nenhuma role de sistema
concede `cycle.manage`/`cycle.cancel`/`cycle.reopen`/`cycle.period.correct`.
Quem recebe essas capabilities em produção é a **D28 (ratificada na
Q-F5-09-3)**: `cycle.manage` entra **aditivamente** no bundle `admin`; as três
excepcionais (`cycle.cancel`, `cycle.reopen`, `cycle.period.correct`) permanecem
**fora** do bundle e concedíveis apenas por configuração explícita de role,
coerente com a descrição do catálogo F5-04. Nenhuma capability nova. A
reconciliação aditiva do catálogo fica na fase **P7** (§19).

---

## 9. RLS

Contrato de leitura (aditivo, no padrão F4-08 — policy **antes** do grant):

```sql
alter table public.evaluation_cycles enable row level security;

create policy evaluation_cycles_select_same_tenant on public.evaluation_cycles
  for select to authenticated
  using (public.user_has_active_membership(organization_id));

grant select on public.evaluation_cycles to authenticated;
```

| Cenário | Resultado esperado |
| --- | --- |
| Ator com membership ativa na organização do ciclo | Vê apenas ciclos do **próprio** tenant |
| Ator sem membership ativa (revogada/inativa/inexistente) | **Zero** linhas (`user_has_active_membership` falso) |
| Ator de outro tenant | **Zero** linhas (cross-tenant nunca retorna dado) |
| `anon` | Sem grant ⇒ nenhuma leitura |
| Escrita direta do cliente (`insert`/`update`/`delete` em `evaluation_cycles`) | **Negada**: sem grant de escrita a `authenticated` e sem policy de escrita (deny-by-default) |
| Mutação | Somente pela fronteira transacional autorizada: Edge `ciclos` + RPCs `ciclo_*` (`SECURITY INVOKER`, `EXECUTE` só `service_role`) |
| Trilha `cycle_events` | Deny-by-default **integral** (`revoke all` de `public, anon, authenticated, service_role`; grants apenas `select, insert` a `service_role`; sem policy) — mesmo desenho de `structure_events` (F5-08 §13.2/§13.3) |
| Snapshot/estrutura por ciclo (`collegiate_cycle_snapshots*`, `cycle_evaluation_responsibilities`) | Já possuem SELECT own-tenant (F4-08); a F5-09 **não** altera essas policies e passa a referenciá-las por identidade (`snapshot_id`/`cycle_id`), não por `ano`+`ciclo` |

RLS é barreira de **tenant boundary**; ela não implementa capability, escopo,
elegibilidade nem `ASSIGNED` (permanecem no Policy Engine e nas RPCs).

---

## 10. Integridade

| # | Invariante | Como é garantida |
| --- | --- | --- |
| I1 | `organization_id` sempre presente e válido (FK para `organizations`) | Já existente; toda RPC recebe/deriva o tenant do ator e nunca confia no corpo |
| I2 | Identidade UUID única (`id` PK) | Já existente |
| I3 | `(organization_id, ano, numero)` único | `uq_evaluation_cycles_org_ano_numero` (já existente) |
| I4 | `ano` 2000–2100, `numero` ∈ {1,2,3}, `data_fim ≥ data_inicio`, pendências ≥ 0, `status` no domínio | CHECKs já existentes (F5-06). O contrato F5-06 admite `data_inicio`/`data_fim` nulos (ciclo "mínimo"); a F5-09 exige **datas não nulas** em `ciclo_criar`/`ciclo_ativar` por validação na RPC (fail-closed), **sem** alterar o CHECK da F5-06 |
| I5 | **Um único ciclo `ATIVO` por organização** | **Novo** índice único parcial: `create unique index uq_evaluation_cycles_org_ativo on public.evaluation_cycles (organization_id) where status = 'ATIVO'` (regra hoje só no cliente — E4) |
| I6 | Períodos de ciclos não cancelados não se sobrepõem na mesma organização | **Novo** `exclude using gist (organization_id with =, daterange(data_inicio, data_fim + 1, '[)') with &&) where (status <> 'CANCELADO' and data_inicio is not null and data_fim is not null)` — conversão meio-aberta canônica (D4/D15) |
| I7 | Ciclo com avaliações não é cancelado silenciosamente | T4: cancelamento resolve as avaliações não concluídas na mesma transação; T5 recusa cancelar PLANEJADO com avaliações |
| I8 | Encerramento com pendências é registrado | T3 reusa `evaluation_fechar_ciclo_pendencias`; `encerrado_com_pendencias`/`quantidade_pendencias` são escritos **só** ali |
| I9 | `config_version_id` do ciclo é soberano e obrigatório na ativação | `ciclo_criar` grava a versão do bootstrap soberano; T2 recusa ativação com `config_version_id` nulo (D19) |
| I10 | Datas inválidas / intervalos invertidos | CHECK de período (I4) + validação na RPC (fail-closed antes do update) |
| I11 | Histórico preservado | Trilha `cycle_events` append-only; `evaluation_events` append-only; snapshots imutáveis; nenhum `DELETE` |
| I12 | Exclusão física | Proibida (T10); nem `service_role` recebe `DELETE` |
| I13 | Concorrência | Advisory lock normativo por organização (§11) + `version`/`expected_version` |
| I14 | Operação repetida | `unique (organization_id, operation_id)` em `cycle_events` + `payload_hash` (§11) |
| I15 | Duas ativações simultâneas | I5 (índice único parcial) + lock: a segunda recebe `CONFLICT` |
| I16 | Ciclo de outro tenant nunca é alcançado | Revalidação por FK composta/`organization_id` em toda RPC + RLS own-tenant |
| I17 | Inclusão aditiva só de **nova admissão** elegível (D26) | Provas P1–P7 do §7.2 revalidadas na RPC; ausência de prova ⇒ recusa |
| I18 | Snapshot do ciclo **nunca** é sobrescrito/recalculado | P3 (recusa se já materializado) + RPC F3-08 só insere (`on conflict do nothing`, guardas `not exists`), sem `UPDATE`/`DELETE` em nenhuma das três tabelas de snapshot; a operação não aceita parâmetros estruturais |
| I19 | Movimentação não rematerializa o ciclo (D27) | Nenhuma operação de ciclo recalcula estrutura de participante já materializado; a estrutura só entra em cena na criação do snapshot (ativação ou inclusão aditiva de novo colaborador) |
| I20 | Sobreposição de ciclos | I6, em vigor por ratificação da D15 (garantida no banco, não apenas no cliente) |

---

## 11. Concorrência e idempotência

**Chave normativa de serialização por organização (padrão F5-08 D24):**

```sql
perform pg_advisory_xact_lock(hashtext('evaluation_cycles:' || v_org::text));
```

- Adquirida no **início** de toda RPC que muta ciclo (`ciclo_criar`, `ciclo_editar`,
  `ciclo_ativar`, `ciclo_encerrar`, `ciclo_cancelar`, `ciclo_reabrir`,
  `ciclo_corrigir_periodo`, `ciclo_incluir_admissao`).
- **Nenhuma outra família** de RPC usa essa chave (as chaves existentes são
  `position_reporting_lines:` da F3-04/F5-08 e `f5_07_estrutura:` da F5-07).
  A F5-09 registra a chave nova junto ao registro de chaves da F5-08 para manter
  a doutrina de chave única por família de recurso.
- Efeitos cross-domain na mesma transação (T3/T4 chamam RPCs `evaluation_*`) são
  serializados por essa mesma chave; o domínio de avaliação não possui advisory
  lock próprio, e o índice único parcial de avaliações permanece a garantia de
  unicidade.

**Idempotência:** `cycle_events` carrega `unique (organization_id, operation_id)`
e `payload_hash` (SHA-256 hex de 64 caracteres) do payload canônico da intenção.
Mesmo `operation_id` + mesmo hash ⇒ devolve o mesmo resultado, sem efeito novo;
mesmo `operation_id` + hash diferente ⇒ `CONFLICT` (nunca executa).

**Casos mínimos obrigatórios (validados em SQL, §15):**

| Caso | Resultado exigido |
| --- | --- |
| Duas ativações concorrentes do mesmo ciclo | Uma vence; a outra `CONFLICT` (estado/versão) e o índice único parcial garante no máximo um `ATIVO` |
| Duas ativações concorrentes de ciclos diferentes da mesma organização | Uma vence; a outra `CONFLICT` por I5 |
| Ativar + cancelar concorrentes | Serializados pelo lock; a segunda vê o estado já alterado ⇒ `CONFLICT` |
| Encerrar duas vezes (mesmo `operation_id`) | Idempotente: mesmo resultado, uma única linha de trilha |
| Encerrar duas vezes (operation_ids distintos) | `CONFLICT` (já não está `ATIVO`) |
| Retry da mesma operação com payload idêntico | Mesmo resultado, sem nova trilha |
| Retry com payload divergente | `CONFLICT` |
| `expected_version` obsoleto | `CONFLICT`, nada gravado |
| Cancelamento concorrente com criação de avaliação | Lock serializa; cancelamento cancela o que existir naquele instante; nova avaliação passa a ser recusada pelo `domainState` de `CANCELADO` |
| Duas inclusões concorrentes da **mesma** nova admissão | Lock serializa; a primeira materializa; a segunda recebe `CONFLICT` (P3 do §7.2) — ou é replay idempotente, se o `operation_id` for o mesmo |
| Inclusão aditiva concorrente com movimentação de posição | Lock serializa; o snapshot do colaborador incluído usa a estrutura vigente no instante em que a inclusão vence a corrida; snapshots existentes não são tocados |

---

## 12. Auditoria

**Trilha nova `public.cycle_events`** — append-only, espelhando o desenho de
`structure_events` (F5-08 D13/§8.3). Justificativa de tabela nova (e não reúso):
`collaborator_events` é ancorada em colaborador/posição (F5-07), `evaluation_events`
é ancorada em avaliação (F5-06) e `structure_events` tem CHECK fechado de
`entity_type` que não cobre ciclo — estendê-los exigiria relaxar contrato
fechado, exatamente o motivo que a F5-08 registrou para criar a sua própria
trilha.

Colunas previstas: `id uuid PK`, `organization_id`, `cycle_id uuid NOT NULL`,
`entity_type text` (`'evaluation_cycle'`), `event_type text` (`CRIADO`,
`EDITADO`, `ATIVADO`, `ENCERRADO`, `CANCELADO`, `REABERTO`, `PERIODO_CORRIGIDO`,
`ADMISSAO_INCLUIDA`), `effective_date timestamptz NOT NULL`, `reason text NOT NULL`
(não vazio, sem espaços nas bordas), `before_value jsonb`, `after_value jsonb`,
`payload_hash text NOT NULL`, `result_entity_id uuid`,
`actor_user_profile_id uuid NOT NULL`, `actor_membership_id uuid NOT NULL`,
`operation_id uuid NOT NULL`, `created_at timestamptz NOT NULL default now()`,
FKs `(organization_id) → organizations`, `(actor_user_profile_id) → user_profiles`,
`(actor_membership_id, organization_id) → user_organization_memberships (id, organization_id)`,
`(cycle_id, organization_id) → evaluation_cycles (id, organization_id)`,
`unique (organization_id, operation_id)`.

Não existe `event_type` genérico de "rematerialização de estrutura": a única
ampliação de população do ciclo é `ADMISSAO_INCLUIDA` (D26), cujo `after_value`
registra o `collaborator_id` incluído, o `reference_date` usado, a posição
resolvida e o **id do evento `ADMISSAO`** que comprovou a elegibilidade (§7.2 P1).

Regras:

1. **Autoria soberana:** `actor_user_profile_id` = `auth.uid()` **verificado
   server-side** (nunca do corpo) e `actor_membership_id` a membership ativa
   usada na decisão — materializa "autoria exige conta".
2. **`reason` obrigatório** em todo fluxo excepcional (cancelar, reabrir,
   corrigir período) , nos encerramentos e na **inclusão aditiva de nova
   admissão** (D26), cujo motivo registra a justificativa da ampliação do ciclo.
3. **`before_value`/`after_value`** guardam apenas estado normalizado relevante
   do ciclo (status, período, versão, contagens, motivo), **nunca** dados
   pessoais e **nunca** como autoridade de tenant/atr.
4. **Mesma transação:** mutação + evento sempre juntos; evento órfão ou mutação
   sem evento é falha de implementação (verificado por validador SQL).
5. **Append-only no banco:** trigger `before update` que levanta exceção;
   `DELETE` barrado por ausência de grant a `anon`/`authenticated`/`service_role`.
6. **Leitura de trilha:** caminho server-side (Edge/relatório). A F5-09 não abre
   superfície nova de leitura de trilha a `authenticated`.
7. Histórico de encerramentos/reaberturas/correções antes guardado em arrays no
   cliente passa a ser **derivado da trilha** (fonte única), não duplicado.

---

## 13. Contrato Edge/RPC

### 13.1 Edge Function nova `supabase/functions/ciclos` (namespace `cycle.*`)

Uma Edge por domínio, como F5-07/F5-08 (`supabase/functions/colaboradores`) e
F5-06 (`supabase/functions/avaliacoes`). Mantém `avaliacoes` intacta (a ponte
`evaluation.resolver_ciclo` continua lá para compatibilidade F5-06) e evita
reabrir o contrato da F5-06.

| Operação | Entrada (intenção) | Saída |
| --- | --- | --- |
| `cycle.listar` | `{ organizationId }` | Lista de ciclos do tenant visíveis ao ator (do mais recente para o mais antigo) |
| `cycle.obter` | `{ organizationId, cycleId }` | Ciclo + contagens + versão |
| `cycle.resolver` | `{ organizationId, ano, numero }` | `{ cycleId }` (ponte de INTENÇÃO, D3) |
| `cycle.criar` | `{ organizationId, ano, numero, dataInicio, dataFim, operationId }` | `{ cycleId, version }` |
| `cycle.editar` | `{ organizationId, cycleId, operationId, expectedVersion, dataInicio?, dataFim?, ano?, numero? }` | `{ version }` |
| `cycle.ativar` | `{ organizationId, cycleId, operationId, expectedVersion }` | `{ version, snapshotMaterializado }` |
| `cycle.encerrar` | `{ organizationId, cycleId, operationId, expectedVersion, motivo? }` | `{ version, quantidadePendencias }` |
| `cycle.cancelar` | `{ organizationId, cycleId, operationId, expectedVersion, motivo }` | `{ version, avaliacoesCanceladas }` |
| `cycle.reabrir` | `{ organizationId, cycleId, operationId, expectedVersion, motivo }` | `{ version }` |
| `cycle.corrigir_periodo` | `{ organizationId, cycleId, operationId, expectedVersion, dataInicio, dataFim, justificativa }` | `{ version, impacto }` |
| `cycle.admissao.incluir` | `{ organizationId, cycleId, operationId, expectedVersion, matricula \| collaboratorId, motivo }` | `{ version, snapshotId, collaboratorId }` |
| `cycle.historico` | `{ organizationId, cycleId }` | Eventos da trilha (leitura server-side) |

Regras da fronteira (herdadas de F5-07/F5-08):

1. `POST` apenas; `OPTIONS`/`405 METHOD_NOT_ALLOWED`; ausência de
   `Authorization` ⇒ `NOT_AUTHORIZED` (401).
2. Identidade por `auth.getUser` (`resolveCaller`); o JWT **não** é propagado às
   RPCs.
3. Validação de **forma** da intenção; forma nunca é autoridade.
4. Revalidação de tenant + resolução de alvo (UUID) **antes** do gate.
5. Gate por operação com mapa explícito e sem fallback (§8).
6. Execução privilegiada com ator verificado; erro de RPC mapeado para o
   `CodigoPublico` (`FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT`,
   `NOT_AUTHORIZED`, `METHOD_NOT_ALLOWED`, `INTERNAL`) com prefixo `F5_09_*` nas
   mensagens internas.
7. `cycle.criar` sem alvo `cycle` ⇒ plano administrativo (§8, D21).
8. Nenhuma operação aceita `organizationId` divergente do resolvido para o ator
   (divergência ⇒ `FORBIDDEN`).
9. `cycle.admissao.incluir` é a **única** operação que amplia a população de um
   ciclo ativo (D26). Ela resolve a intenção matrícula → UUID na fronteira
   (F3-01), **recusa** (`INVALID_INPUT`) qualquer campo estrutural no corpo
   (posição, unidade, gestor, reporting line, colegiado, `reference_date`, lista
   de colaboradores) e delega a prova soberana de admissão à RPC (§7.2). **Não
   existe** operação genérica de "rematerializar estrutura".

### 13.2 RPCs novas (migration F5-09, `SECURITY INVOKER`, `EXECUTE` só `service_role`)

| RPC | Assinatura prevista | Notas |
| --- | --- | --- |
| `ciclo_ator_valido` | `(p_actor_user_profile_id uuid, p_organization_id uuid, p_capability text) returns boolean` | Reusa `evaluation_ator_valido` + capabilities efetivas (F5-04) |
| `ciclo_criar` | `(p_organization_id uuid, p_ano integer, p_numero integer, p_data_inicio date, p_data_fim date, p_actor_user_profile_id uuid, p_operation_id uuid, p_payload_hash text) returns jsonb` | Idempotente; grava `cycle_events` `CRIADO`; resolve `config_version_id` pelo bootstrap soberano |
| `ciclo_editar` | `(p_cycle_id uuid, p_organization_id uuid, p_ano integer, p_numero integer, p_data_inicio date, p_data_fim date, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid, p_payload_hash text) returns jsonb` | Só `PLANEJADO` |
| `ciclo_ativar` | `(p_cycle_id uuid, p_organization_id uuid, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid, p_payload_hash text) returns jsonb` | Materializa F3-08 e ativa (T2) |
| `ciclo_encerrar` | `(p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid, p_payload_hash text) returns jsonb` | Reusa `evaluation_fechar_ciclo_pendencias` (T3) |
| `ciclo_cancelar` | `(p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid, p_payload_hash text) returns jsonb` | Cancela avaliações não concluídas na mesma transação (T4/T5) |
| `ciclo_reabrir` | `(p_cycle_id uuid, p_organization_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid, p_payload_hash text) returns jsonb` | T6 |
| `ciclo_corrigir_periodo` | `(p_cycle_id uuid, p_organization_id uuid, p_data_inicio date, p_data_fim date, p_justificativa text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid, p_payload_hash text) returns jsonb` | T7; impacto calculado server-side |
| `ciclo_admissao_pos_ativacao_elegivel` | `(p_organization_id uuid, p_cycle_id uuid, p_collaborator_id uuid) returns jsonb` | Helper **read-only** que aplica as provas P1–P7 do §7.2 e devolve elegibilidade + motivo da recusa (usado pela inclusão e pelo validador) |
| `ciclo_incluir_admissao` | `(p_cycle_id uuid, p_organization_id uuid, p_collaborator_id uuid, p_motivo text, p_expected_version integer, p_actor_user_profile_id uuid, p_operation_id uuid, p_payload_hash text) returns jsonb` | **D26** — operação restrita a nova admissão: valida P1–P7, recusa `CONFLICT` se já houver snapshot do colaborador no ciclo, chama `materializar_colegiado_ciclo(org, ano, numero, p_reference_date = now(), ARRAY[collaborator_id])` e grava `cycle_events` `ADMISSAO_INCLUIDA`; **nenhum** parâmetro estrutural |
| `ciclo_painel` | `(p_organization_id uuid, p_cycle_id uuid, p_actor_user_profile_id uuid) returns jsonb` | Leitura autorizada (ciclo + snapshot + contagens) |
| `ciclo_historico` | `(p_organization_id uuid, p_cycle_id uuid, p_actor_user_profile_id uuid) returns setof jsonb` | Trilha |
| `ciclo_listar_colaborador_por_ciclo` | `(p_organization_id uuid, p_cycle_id uuid, p_collaborator_id uuid, p_actor_user_profile_id uuid) returns setof jsonb` | Fecha o pendente da F5-07 (E12) usando `collaborator_events.reference_cycle_id` |

Erros: `F5_09_FORBIDDEN`, `F5_09_NOT_FOUND`, `F5_09_CONFLICT` (estado/versão/
idempotência divergente), `F5_09_INVALID_INPUT` (forma/valores), `F5_09_INTERNAL`.

### 13.3 Reuso obrigatório (proibido reimplementar)

- `evaluation_fechar_ciclo_pendencias` — encerramento (T3).
- `evaluation_cancelar` / `evaluation_concluir` / `evaluation_reabrir` — efeitos
  sobre avaliações (T4).
- `evaluation_snapshot_participantes` / `evaluation_criar` — congelamento e
  criação de avaliação (inalterados; seguem exigindo `cycle_id` UUID).
- `materializar_colegiado_ciclo` — snapshot de colegiado (T2 **e** inclusão
  aditiva de nova admissão, sempre com `on conflict do nothing`/guardas
  `not exists`; nenhuma sobrescrita). **Verificado na base:** `service_role`
  mantém privilégios completos de tabela (F4-08 §1) e o `EXECUTE` dessa RPC já é
  concedido a `service_role` (`20260908100000`), sem necessidade de grant novo.
- `evaluation_config_bootstrap` — versão de configuração do ciclo.
- `evaluation_ator_valido`, `resolver_capabilities_efetivas`,
  `user_has_active_membership` — ator/tenant/capability.

### 13.4 Compatibilidade mantida

- `evaluation.resolver_ciclo` e o mapa `(ano, numero) → UUID` de
  `assignedSupabase.ts` permanecem (D3), com condição de remoção registrada.
- `evaluation_criar` continua exigindo `cycle_id` UUID e lendo a versão de
  configuração **do ciclo**.
- Nenhuma alteração nas tabelas/CHECKs/RLS de F5-06, F5-07 e F5-08; a F5-09 só
  **adiciona** (índice único parcial, exclusion, tabela de trilha, RPCs, policy
  de leitura e o grant correspondente).

### 13.5 Cliente (leitura e escrita)

- **Leitura:** PostgREST sob RLS para `evaluation_cycles` (padrão F5-08 P4) e
  leitura do snapshot por `snapshot_id`/`cycle_id`; nenhuma leitura de ciclo por
  `localStorage` como autoridade.
- **Escrita:** exclusivamente pela Edge `ciclos`.
- **Porta única:** `src/services/acessoCiclosSoberanos.ts` (nenhuma página importa
  Supabase nem `cicloAvaliacaoStorage` para decidir), no padrão
  `acessoAvaliacoesSoberanas.ts` / `acessoColaboradoresSoberanos.ts`.
- **Projeção/cache:** `src/infrastructure/supabase/ciclos/repositorioCiclosSoberanos.ts`
  (descritores de leitura) + cache de UX publicada pelo shell autenticado, com
  geração monotônica e invalidação por troca de organização/unmount — mesma
  doutrina multi-tenant do `estruturaSoberanaCliente.ts` (F5-08 §2.3).

### 13.6 Pendência declarada da F5-07 (entregue aqui)

`supabase/functions/colaboradores/index.ts` registra que "filtrar por ciclo
depende da entidade de ciclo soberana (F5-09)". A F5-09 entrega
`ciclo_listar_colaborador_por_ciclo` (ou expõe o filtro na operação existente)
usando `collaborator_events.reference_cycle_id` (FK já existente para
`evaluation_cycles`) — sem alterar o schema da F5-07.

---

## 14. Frontend e cutover

Framework A/B/C/D (o mesmo do P6 da F5-08):

- **A — autoridade de produção a remover** (o cliente deixa de decidir/persistir).
- **B — leitura legada autorizada temporariamente** (com atividade própria
  declarada e sem autoridade).
- **C — DEV/teste/fixture** (atrás de barreira explícita `simulacaoDevPermitida`).
- **D — cache/UX sem autoridade** (pode permanecer; nunca decide).

| Superfície | Classificação | Ação na F5-09 |
| --- | --- | --- |
| `cicloAvaliacaoStorage.criarCiclo/ativarCiclo/encerrarCiclo/atualizarPeriodoCiclo/atualizarConfiguracaoMetasCiclo/excluirCiclo` | **A** | Remover como escrita; virar barreira fail-closed (padrão `feedbackStorage` na F5-06). `excluirCiclo` **não** é substituída por `DELETE`: a exclusão física é proibida (D9) e o fluxo equivalente passa a ser o cancelamento do ciclo `PLANEJADO` (T5) |
| `persistirCancelamentoCicloAuditadoInterno` / `persistirReaberturaCicloAuditadaInterno` / `persistirCorrecaoPeriodoCicloAtivoInterno` | **A** | Barreira fail-closed (autoria local nunca é aceita) |
| Semeadura de ciclos em `getCiclosAvaliacao()` | **A** | Eliminada: existência de ciclo vem do servidor |
| `cycleRepository` local (`localCycleRepository`) | **A** | Substituído pelo repositório soberano |
| `cancelamentoCicloService`, `reaberturaCicloService`, `correcaoPeriodoCicloService` | **A** | Passam a chamar a porta soberana (async, com estado de processamento/erro preservado nas telas) |
| `src/types/CicloAvaliacao.ts` (arrays `encerramentos`/`reaberturas`/`correcoesPeriodo`/`cancelamento` com autoria do cliente) | **A** | Modelo soberano: histórico vem da trilha; autoria nunca vem do cliente |
| `CiclosAvaliacaoPage` | **A → porta** | Gestão 100% pela porta soberana; `getCiclosAdministrativos` vira leitura da cache/projeção |
| `PainelCicloPage`, `PainelCiclosCoordenadorPage`, `MinhaAvaliacaoPage`, `MinhaAvaliacaoDetalhePage`, `MinhasMetasPage`, `AcompanhamentoMetasPage`, `NovoFeedbackPage`, `EditarFeedbackPage`, `FeedbackDetalhePage`, `RelatoriosPage` | **D** (leitura) | Consomem ciclo da projeção soberana; nenhuma transição local |
| `ColaboradorDetalhePage`, `ColaboradoresPage` (`painelDev`) | **D** / **C** | `painelDev` permanece atrás da barreira de DEV; o restante lê a projeção |
| `ObservacoesColaborador`, `observacaoStorage`, `metaStorage`, `permissaoAvaliacao`, `progressoAvaliacao` | **D** (com residual F5-10/F5-11) | Passam a ler a projeção soberana; o domínio de metas/observações segue local (atividade própria) |
| `historicoOrganizacionalStorage`, `exportarAvaliacaoPdf`, `relatorioService` (filtros por ciclo) | **B** | Residual já declarado no P6 da F5-08; leitura legada autorizada, sem autoridade |
| `geradorDadosTeste` | **C** | Permanece fixture de DEV |
| `localStorage` (`feedback-control-ciclos`) | **D** | Passa a ser cache de UX do servidor (nunca fonte de verdade); a chave antiga não é promovida |

Invariantes de cutover (verificados por guardas estáticos, §15):

1. Nenhum arquivo de `src/` escreve ciclo em `localStorage`, exceto o módulo de
   cache explicitamente marcado como UX (e ainda assim, nunca lendo de volta como
   autoridade).
2. Nenhum arquivo de `src/` obtém status/identidade de ciclo de `localStorage`
   para decidir autorização, elegibilidade, criação de avaliação ou transição.
3. Nenhuma página importa Supabase diretamente: a porta é
   `acessoCiclosSoberanos`.
4. Nenhum caminho de produção promove id local a UUID nem usa `ano`+`numero`
   como identidade interna.

**Inclusão aditiva de nova admissão (D26) × cutover.** A operação **não tem
contraparte local**: hoje a criação de avaliações do ciclo acontece só na ativação
(`criarAvaliacoesDoCicloAtivado`), e não existe caminho legado que acrescente um
colaborador admitido depois. Portanto ela **não é item de remoção (A)** nem de
leitura legada (B): é superfície **nova**, entregue pela Edge/RPC (P3/P7). A
exposição na tela de gestão de ciclos é incremento aditivo posterior, sempre pela
porta única e sem qualquer autoridade local; a ausência de botão não é autorização
(a decisão permanece server-side).

---

## 15. Estratégia de testes

Classificação: **SQL** (validadores `supabase/validacao/*.sql` executados no job
`supabase-local`), **UNIT** (Vitest), **INTEG** (Vitest com stub de fronteira
confiável, como `avaliacoesContratoRpc.test.ts`), **STATIC** (guardas de código
em Vitest lendo arquivos de `src/`), **CI** (workflow).

| # | Cenário | Tipo | Fase |
| --- | --- | --- | --- |
| 1 | Schema: colunas, CHECKs, índices, exclusion, partial unique, FKs, comentários | SQL | P1 |
| 2 | Grants/RLS: `evaluation_cycles` só SELECT a `authenticated`; `cycle_events` deny-by-default; `EXECUTE` de `ciclo_*` só `service_role` | SQL | P1/P5 |
| 3 | Leitura own-tenant positiva (ciclos do próprio tenant) | SQL | P5 |
| 4 | Cross-tenant: ator de outro tenant vê zero e não altera nada | SQL | P5 |
| 5 | Membership revogada/inativa ⇒ zero linhas + RPC `FORBIDDEN` | SQL | P5 |
| 6 | Capability negada: ator sem `cycle.manage`/`cycle.cancel`/`cycle.reopen`/`cycle.period.correct` recebe `FORBIDDEN` e **nada é gravado** | SQL | P2/P3/P4 |
| 7 | Máquina de estados: todas as transições válidas (T0–T7) | SQL | P2/P4 |
| 8 | Transições inválidas (T9): `ENCERRADO→CANCELADO`, `CANCELADO→ATIVO`, `PLANEJADO→ENCERRADO` ⇒ `CONFLICT` | SQL | P4 |
| 9 | Exclusão física: `DELETE` negado a todos os papéis de aplicação | SQL | P1 |
| 10 | Concorrência: duas ativações (mesmo ciclo e ciclos distintos) | SQL | P2 |
| 11 | Idempotência: retry mesmo `operation_id` (mesmo hash ⇒ mesmo resultado; hash divergente ⇒ `CONFLICT`) | SQL | P2/P3/P4 |
| 12 | `expected_version` obsoleto ⇒ `CONFLICT` sem efeito | SQL | P2/P3/P4 |
| 13 | Encerramento: pendências marcadas permanentemente, `quantidade_pendencias` correto, idempotência | SQL | P2 |
| 14 | Cancelamento: avaliações não concluídas canceladas; concluídas preservadas; contagens na trilha | SQL | P4 |
| 15 | Reabertura: proibida com outro `ATIVO`; preserva histórico de encerramento | SQL | P4 |
| 16 | Estrutura/snapshot: materialização na ativação idempotente; snapshot não sobrescrito; avaliação criada congela participantes | SQL | P2 |
| 17 | Avaliações vinculadas: ciclo com avaliações não é excluído/cancelado em silêncio; `evaluation_criar` segue exigindo `cycle_id` válido do tenant | SQL | P2/P4 |
| 18 | Histórico/trilha: mutação sem evento impossível; UPDATE/DELETE na trilha negados; evento com motivo nos fluxos excepcionais | SQL | P1/P4 |
| 19 | Ausência de autoridade local: criar/ativar/encerrar/cancelar/reabrir/corrigir no cliente não grava nada | STATIC + UNIT | P8 |
| 20 | Ausência de escrita local de ciclo: sweep de `src/` por `localStorage` e por métodos removidos | STATIC | P8 |
| 21 | Identidade: nenhuma superfície usa `ano`+`numero`/índice/`localStorage` como identidade | STATIC | P8 |
| 22 | Contrato Edge/RPC: nomes e assinaturas reais conferem (teste que lê o código-fonte, padrão `avaliacoesContratoRpc.test.ts`) | INTEG | P7 |
| 23 | Gate: operação desconhecida ⇒ DENY; `cycle.criar` sem âncora ⇒ DENY; `service_role` nunca decide | UNIT + INTEG | P6/P7 |
| 24 | Policy Engine: `cycle.read`/`cycle.manage`/`cycle.cancel`/`cycle.reopen`/`cycle.period.correct` com `domainState` correto por status | UNIT | P6 |
| 25 | Cutover do cliente: telas e serviços usam a porta soberana; nenhuma transição local; cache por organização sem vazamento entre tenants | UNIT + STATIC | P8 |
| 26 | Regressão F5-06/F5-07/F5-08 (validadores existentes + suíte Vitest completa) | SQL + CI | P9 |
| 27 | Filtro de histórico do colaborador por ciclo (UUID) | SQL + INTEG | P7 |

Nenhum cenário pode ser declarado verde sem execução: onde o host não permitir
(Docker/Supabase local), registrar comando, resultado e limitação (nunca mascarar
gate não executado como verde).

### 15.1 Casos obrigatórios da inclusão aditiva e da imutabilidade (D26/D27)

| # | Cenário | Resultado exigido | Tipo | Fase |
| --- | --- | --- | --- | --- |
| A1 | Admissão após a ativação (evento `ADMISSAO` com `effective_date > data_ativacao`, `cycle_scope = 'CICLO_ATUAL_E_POSTERIORES'`, sem período de status anterior) | Inclusão **permitida**; novo `collegiate_cycle_snapshots` + posições/membros criados no `reference_date` da inclusão; trilha `ADMISSAO_INCLUIDA` | SQL | P3 |
| A2 | Segunda inclusão do **mesmo** colaborador no mesmo ciclo | Mesmo `operation_id` ⇒ replay idempotente (mesmo resultado, uma trilha); `operation_id` distinto ⇒ **recusada** `CONFLICT` (P3) | SQL | P3 |
| A3 | Movimentação de posição/gestor/colegiado de participante **já materializado** | Snapshot do ciclo **permanece idêntico** (contagens e valores inalterados); nenhuma trilha de estrutura do ciclo é gravada | SQL | P3/P9 |
| A4 | Tentativa de usar a inclusão aditiva para **trocar a posição** de participante existente | Recusada (`CONFLICT` por P3); nenhuma alteração de posição no snapshot | SQL | P3 |
| A5 | Admissão **anterior** à ativação que ficou indevidamente fora do snapshot | **Fail-closed**: recusa (P2 e/ou `cycle_scope`), nada materializado — a operação **não** corrige silenciosamente erro de materialização | SQL | P3 |
| A6 | Inclusão de colaborador de **outro tenant** | Recusa indistinguível de inexistente (`NOT_FOUND`/`FORBIDDEN`), zero efeito | SQL | P3 |
| A7 | Ator com **membership revogada/inativa** | `FORBIDDEN`, nenhuma RPC privilegiada tocada | SQL | P3 |
| A8 | Ator **sem** `cycle.manage` | `FORBIDDEN`, nada gravado | SQL | P3/P7 |
| A9 | **Duas inclusões concorrentes** da mesma admissão | Lock serializa; uma materializa; a outra `CONFLICT` (ou replay, se mesmo `operation_id`); jamais duas linhas de snapshot | SQL | P3 |
| A10 | Retry/idempotência da inclusão (mesmo payload × payload divergente) | Mesmo payload ⇒ mesmo resultado; payload divergente ⇒ `CONFLICT` | SQL | P3 |
| A11 | Impossibilidade de **sobrescrever** snapshot | Tentativa de inclusão de colaborador já materializado não altera nenhuma linha; validador verifica que `UPDATE`/`DELETE` não existem nas três tabelas de snapshot dentro da operação | SQL + STATIC | P1/P3 |
| A12 | Ausência de **sobreposição** de ciclos | Inserção/edição que gere sobreposição com ciclo não `CANCELADO` da mesma organização é recusada pela exclusion (I6); ciclo `CANCELADO` não bloqueia | SQL | P1 |

---

## 16. Riscos

| # | Risco | Mitigação |
| --- | --- | --- |
| R1 | Duplicar a entidade de ciclo (segunda fonte de verdade) | D1: extensão aditiva de `evaluation_cycles`; proibição explícita de tabela nova de ciclo |
| R2 | Constraints novas (partial unique, exclusion) falharem sobre dados existentes | Verificação prévia no P1 (`db reset` + consulta de dados antes de aplicar); ambiente de produção tem a tabela apenas com fixtures — declarar no PR o resultado da checagem |
| R3 | `ano`+`numero` continuar vazando como identidade (cache, telas, ponte) | D2/D3 + guardas estáticos (cenários 21/25) |
| R4 | Estrutura do ciclo divergir da F5-08 (hierarquia textual ressurgindo) | §7: hierarquia sempre de `position_reporting_lines`; nenhuma leitura de `funcao` |
| R5 | Cancelamento deixar avaliações em estado impossível de cancelar | T4 resolve na mesma transação; cenário 14 |
| R6 | Encerramento divergir da F5-06 (converter avaliação incompleta em concluída) | T3 reusa `evaluation_fechar_ciclo_pendencias`; cenário 13 |
| R7 | Deadlock/concorrência com as chaves de advisory lock existentes | §11: chave própria por família, adquirida no início; nenhuma outra família usa a mesma chave |
| R8 | Rede de pontes acumulada (`evaluation_resolver_ciclo`, snapshots por ano/ciclo) | D3 registra a dívida e a condição de remoção; escopo não a amplia |
| R9 | Cutover tornar a gestão de ciclo impossível em produção (ninguém com `cycle.manage`) | **D28 (ratificada na Q-F5-09-3)**: `cycle.manage` entra aditivamente no bundle `admin` na fase **P7**, com validador SQL confirmando o bundle |
| R10 | Autoria voltar a ser fornecida pelo cliente | §12.1 + proibição de `autorMatricula`/`autorNome` no contrato Edge |
| R11 | Residuais (relatórios/PDF/histórico organizacional) ficarem silenciosos | Declarados (B) com atividade própria; cenário 19/25 os exclui explicitamente |
| R12 | Quota de metas local ser confundida com autoridade de ciclo | D24 + §1 (fora de escopo, domínio de metas) |
| R13 | Regressão em F5-06/07/08 por alteração de policy/RLS | Fechamentos aditivos e cenário 26 (validação cruzada) |
| R14 | Exclusão física reintroduzida por conveniência | T10 + I12 + cenário 9 |
| R15 | Prova de nova admissão indisponível para colaborador legado/importado (sem evento `ADMISSAO` ou sem linha do tempo de status) | P7 do §7.2: **fail-closed** (recusa), com requisito técnico explícito de que o caminho de importação grave o evento soberano em atividade própria — a regra **não** é flexibilizada e o `admission_date` declarado nunca é aceito como prova |
| R16 | Inclusão aditiva usada como "atualizar estrutura do ciclo" (bypass de D27) | Contrato restrito (§7.3): sem parâmetros estruturais, prova de admissão obrigatória, recusa quando já materializado, trilha com `ADMISSAO_INCLUIDA` + id do evento de admissão; casos A2–A5/A11 do §15.1 |
| R17 | Ampliação de `cycle.cancel` (D8) conceder cancelamento indevido de ciclo planejado a quem não tem a capability | Gate funcional com `cycle.cancel` + `domainState ∈ {PLANEJADO, ATIVO}` + motivo obrigatório + trilha; capability continua fora do bundle `admin` (D28), concedida só por configuração explícita |

---

## 17. Decisões (D1–D28)

- **D1 — Entidade única.** `public.evaluation_cycles` (F5-06 D15) é a entidade
  soberana de ciclo; a F5-09 a estende **aditivamente**. Nenhuma tabela nova de
  ciclo, de estrutura por ciclo ou de versão de configuração.
- **D2 — Identidade canônica UUID.** `evaluation_cycles.id` é a identidade;
  `(ano, numero)` é rótulo humano e regra de unicidade, nunca identidade interna,
  chave de cache ou parâmetro de escrita.
- **D3 — Ponte como intenção, dívida controlada.** `evaluation_resolver_ciclo` e
  o mapa `(ano, numero) → UUID` de `assignedSupabase.ts` permanecem (o snapshot
  F3-08 é keyed por `ano`+`ciclo`), usados apenas na fronteira confiável para
  converter INTENÇÃO em identidade; condição de remoção registrada (snapshot
  F3-08 passar a referenciar `cycle_id`). A F5-09 não altera o contrato F3-08.
- **D4 — Sem segunda representação temporal.** O período do ciclo são
  `data_inicio`/`data_fim` (`date`) e os instantes `data_ativacao`/
  `data_encerramento` (`timestamptz`) já existentes. Comparação canônica
  meio-aberta `daterange(data_inicio, data_fim + 1, '[)')`, coerente com
  `[valid_from, valid_to)` da F5-08 §19.1. `data_fim` é o último dia **inclusivo**
  para o produto.
- **D5 — Estados.** Exatamente os quatro do CHECK vigente
  (`PLANEJADO`/`ATIVO`/`ENCERRADO`/`CANCELADO`). Nenhum estado novo.
- **D6 — Transições.** Somente T0–T7 do §6. `ATIVO→ATIVO` e `ENCERRADO→ENCERRADO`
  com o mesmo `operation_id` são repetição idempotente (T8); qualquer transição
  não listada é `CONFLICT` (T9).
- **D7 — Reabertura permitida.** `ENCERRADO→ATIVO` com motivo, capability
  `cycle.reopen`, sem outro `ATIVO` na organização, preservando o histórico de
  encerramentos na trilha (não em arrays do cliente).
- **D8 — `CANCELADO` é terminal e substitui a exclusão física.**
  **(RATIFICADA na Q-F5-09-1: alternativa A.)** Inclui `PLANEJADO→CANCELADO` (T5)
  com capability `cycle.cancel`, motivo obrigatório, autoria soberana, trilha
  append-only, `expected_version` e idempotência; amplia o `domainState` de
  `cycle.cancel` de `ATIVO` para `{PLANEJADO, ATIVO}` em
  `authorizationPolicy.ts`. Substitui `excluirCiclo` do cliente com efeito de UX
  equivalente (ciclos `CANCELADO` já são filtrados por padrão em
  `getCiclosAdministrativos`) e **exige** atualizar, de forma **aditiva**, a
  descrição da capability no catálogo (`cycle.cancel`: "Cancelar ciclo ATIVO" →
  "Cancelar ciclo PLANEJADO ou ATIVO (fluxo excepcional auditável)"), sem remoção
  física de capability (F5-04 D14). Reativação de `CANCELADO` é proibida.
- **D9 — Exclusão física proibida.** Nenhum `DELETE` de ciclo (em nenhum estado),
  por nenhum papel de aplicação. Ciclo `PLANEJADO` é editável (T1) e cancelável
  (T5): não fica irrecuperável e não precisa ser apagado.
- **D10 — Encerramento reusa a F5-06.** `ciclo_encerrar` = `evaluation_fechar_ciclo_pendencias`
  + `status='ENCERRADO'` + `data_encerramento` + `version+1` + evento. Nenhuma
  regra de pendência é reimplementada; avaliação incompleta **não** vira
  `CONCLUIDA` (contrato F5-06 D11/D18 mantido).
- **D11 — Cancelamento resolve as avaliações na mesma transação.** Cancelar o
  ciclo cancela as avaliações não concluídas (caminho soberano existente) e
  preserva as concluídas; a trilha registra as contagens. Motivo: com
  `cicloStatus === 'CANCELADO'`, o `domainState` já existente bloquearia para
  sempre o cancelamento da avaliação pelo caminho normal.
- **D12 — Encerramento e cancelamento são atômicos e auditados.** Evento e
  mutação na mesma transação; falha ⇒ rollback integral (nenhum estado parcial).
- **D13 — Correção de período separada por estado.** `PLANEJADO` = edição comum
  (T1); `ATIVO` = correção auditada com justificativa e impacto calculado
  server-side (T7), sem reinterpretar dados já congelados.
- **D14 — Um único `ATIVO` por organização no banco.** Índice único parcial
  (I5) — a regra deixa de viver só no cliente.
- **D15 — Sem sobreposição de períodos.** **(RATIFICADA na Q-F5-09-2/revisão de
  produto.)** É **proibida** a sobreposição temporal entre ciclos não `CANCELADO`
  da mesma organização, garantida **no banco** (exclusion GiST, I6) e não apenas no
  cliente; a comparação usa o intervalo meio-aberto equivalente
  `daterange(data_inicio, data_fim + 1, '[)')` (D4), com `data_fim` inclusiva para
  o produto. Ciclos `CANCELADO` **não** bloqueiam o período.
- **D16 — Estrutura por ciclo = F3-08 + F3-09 + congelamento F5-06, ampliável
  apenas por admissão.** Nenhuma tabela nova de estrutura por ciclo. A F5-09
  define **como** a estrutura é materializada, **o que** é imutável e **qual** a
  única ampliação permitida (§7): população inicial materializada na ativação,
  inadmissão de recálculo, admissões posteriores elegíveis acrescentáveis (D26) e
  movimentações válidas no próximo ciclo (D27). **(Revisada para não contradizer
  D26/D27; "congelamento na ativação" isolado não é o contrato.)**
- **D17 — Materialização inicial na ativação; ampliação aditiva depois.**
  `reference_date` = data da ativação para a **população inicial**;
  `materializar_colegiado_ciclo` é chamada na transição T2 (idempotente, aditiva,
  nunca sobrescreve snapshot existente). Depois da ativação, a única chamada
  autorizada da mesma RPC é a **inclusão aditiva de nova admissão** (D26), sempre
  com um único `collaborator_id`, `reference_date` = instante da inclusão e prova
  soberana prévia (§7.2). **(Revisada: antes dizia apenas "congelamento na
  ativação".)**
- **D18 — Hierarquia sempre soberana.** Posição/superior/cadeia/colegiado vêm das
  relações F3-04/F3-08 e das ocupações F5-07/F5-08; **nunca** de texto (`funcao`,
  `respondePara`) nem de matrícula.
- **D19 — Versão de configuração é do ciclo.** `ciclo_criar` grava
  `config_version_id` a partir do bootstrap soberano; T2 recusa ativação sem
  versão. O cliente nunca informa versão de configuração.
- **D20 — Nenhuma capability nova.** Mapa do §8 sobre as capabilities existentes
  (`cycle.read`, `cycle.manage`, `cycle.cancel`, `cycle.reopen`,
  `cycle.period.correct`); fechamento aditivo dos ramos ausentes no
  `authorizationPolicy.ts` (hoje `cycle.read`/`cycle.manage` ⇒ DENY por
  `default → null`). A inclusão aditiva de nova admissão (D26) reusa
  `cycle.manage` — compatível com o catálogo existente ("Gerenciar ciclos"),
  sem criação de capability.
- **D21 — Plano de gate por operação.** Operações sobre ciclo existente são
  **funcionais** (Policy Engine, alvo `{type:"cycle", id: UUID}`, `domainState`
  do status soberano). `cycle.criar` é **administrativa** (capability efetiva
  F5-04 D19), porque o recurso ainda não existe e a F5-05 D19/D22 proíbe alvo
  sintético como prova de autorização.
- **D22 — Leitura soberana por RLS.** Policy
  `evaluation_cycles_select_same_tenant` + `grant select` a `authenticated`
  (padrão F4-08), sem qualquer grant de escrita ao cliente; mutações só pela
  fronteira autorizada (Edge + RPC).
- **D23 — Autoria soberana.** `auth.uid()` + membership ativa registrados na
  trilha; `autorMatricula`/`autorNome` do cliente deixam de existir no contrato.
- **D24 — Quota de metas é do domínio de metas (residual F5-10).**
  `quantidadeMetasNegocio`/`quantidadeMetasIndividuais` permanecem locais como
  configuração do domínio de metas, classificadas **D** (sem autoridade sobre
  existência/estado/identidade do ciclo). A F5-09 não cria coluna para um domínio
  inexistente; quando a F5-10 criar a entidade de metas, a quota migra com ela
  (aditivamente).
- **D25 — Uma Edge por domínio.** `supabase/functions/ciclos` (namespace
  `cycle.*`) nova; `avaliacoes` permanece intacta (a ponte
  `evaluation_resolver_ciclo` continua lá) — nenhum contrato F5-06 é reaberto.
- **D26 — Admissão durante ciclo ativo (RATIFICADA; Q-F5-09-2, parte B).**
  Colaborador admitido **após** a ativação pode ser incorporado ao ciclo corrente
  por operação **soberana, explícita, auditada e exclusivamente aditiva**
  (`cycle.admissao.incluir` / `ciclo_incluir_admissao`). Sua identidade é o
  **UUID** do colaborador e sua estrutura é resolvida **server-side** na data da
  inclusão (não vem do cliente). A operação **não pode** alterar snapshots
  existentes nem ser usada como mecanismo genérico de "atualizar estrutura do
  ciclo": ela existe apenas para incorporar colaborador elegível que não
  participava do ciclo por ter sido admitido depois da ativação, e exige a prova
  soberana P1–P7 do §7.2 (ausência de prova ⇒ fail-closed). Reusa a capability
  `cycle.manage`; nenhuma capability nova.
- **D27 — Movimentação durante ciclo ativo (RATIFICADA; Q-F5-09-2, parte A).**
  Mudança de posição, unidade, gestor, reporting line ou colegiado posterior à
  entrada do colaborador no ciclo **não** rematerializa sua estrutura naquele
  ciclo: a alteração vale **no próximo ciclo**, ressalvados os mecanismos
  excepcionais **já contratados** de sucessão (`cycle_evaluation_responsibilities`,
  F3-09) e de realinhamento de participante (`evaluation_participante_realinhar`,
  F5-06), que **não** equivalem a recalcular o snapshot inteiro. Snapshots
  existentes são imutáveis.
- **D28 — Reconciliação aditiva do catálogo (RATIFICADA; Q-F5-09-3, alternativa
  A).** `cycle.manage` entra **aditivamente** no bundle `admin`
  (`access_role_capabilities`), por migration de reconciliação (padrão
  `20260910000000_f5_04_catalog_reconciliation.sql`), na fase **P7**.
  `cycle.cancel`, `cycle.reopen` e `cycle.period.correct` permanecem **fora** do
  bundle, concedíveis apenas por configuração explícita de role (capabilities
  excepcionais). Nenhuma capability nova.

---

## 18. Dúvidas bloqueantes

**ZERO dúvida bloqueante conhecida para iniciar P1.** As três dúvidas da primeira
rodada foram **RATIFICADAS** pela auditoria GPT do desenho (registro completo em
`docs/F5-09-duvidas.md`, seção "Dúvidas ratificadas"):

| Dúvida | Situação | Decisão final e onde está refletida |
| --- | --- | --- |
| Q-F5-09-1 — ciclo `PLANEJADO`: cancelar × excluir fisicamente | **RATIFICADA** (alternativa A) | `PLANEJADO→CANCELADO` permitido com `cycle.cancel`, motivo obrigatório, autoria soberana, trilha append-only, `expected_version` e idempotência; `CANCELADO` terminal; `DELETE` físico proibido em **todos** os estados — **D8/D9**, refletidas em T5/T10, §8, D10/I12 e §14 |
| Q-F5-09-2 — estrutura do ciclo | **RATIFICADA com regra híbrida** | população inicial materializada na ativação + admissões posteriores elegíveis **aditivas** (**D26**) + snapshots existentes imutáveis + movimentações **sem** rematerialização (**D27**) — refletida no §7 inteiro (§7.1–§7.3), em I17–I19, §11, §12, §13 e §15.1 |
| Q-F5-09-3 — quem recebe `cycle.manage` em produção | **RATIFICADA** (alternativa A) | `cycle.manage` entra aditivamente no bundle `admin`; `cycle.cancel`/`cycle.reopen`/`cycle.period.correct` permanecem fora do bundle, concedíveis só por configuração explícita — **D28**, executada em **P7** |

**Nenhuma nova dúvida bloqueante surgiu** na revisão transversal: as regras
ratificadas são aplicáveis com dados temporais **já existentes** da F5-07
(`collaborator_events.event_type = 'ADMISSAO'` + `collaborator_status_periods`) e
sem nenhuma capability nova. O único ponto que a ratificação converteu em
**requisito técnico da implementação** (e não em dúvida) está no §7.2: colaborador
sem prova soberana de admissão ⇒ **recusa** (fail-closed), com a correção
pertencendo ao caminho de importação/legado, em atividade própria.

---

## 19. Plano de implementação (P1–P9)

A decomposição foi **reavaliada** após a ratificação da Q-F5-09-2. A regra híbrida
exige uma superfície nova — prova soberana de admissão + operação restrita +
trilha própria + casos de teste próprios —, que precisa de **fase independente**
para auditoria, e a reconciliação aditiva do catálogo (D28) precisa de dono
explícito. O plano passa de 8 para **9 fases** (não foi mantido em oito
artificialmente). Onde cada elemento novo entra:

| Elemento novo | Fase |
| --- | --- |
| Prova soberana de admissão (helper `ciclo_admissao_pos_ativacao_elegivel`) | **P3** |
| Inclusão aditiva de nova admissão (`ciclo_incluir_admissao`, D26) | **P3** |
| Autorização (gate + `domainState`; reuso de `cycle.manage`) | **P6** (consumida por P3 e P7) |
| Trilha (`cycle_events` + `ADMISSAO_INCLUIDA`) | tabela em **P1**, evento em **P3** |
| Testes (A1–A12 do §15.1) | **P3**; integração/regressão em **P9** |
| Cutover (a inclusão aditiva **não** tem contraparte local: é superfície nova) | **P8** |
| Reconciliação aditiva do catálogo (`cycle.manage` no bundle `admin`, D28) | **P7** |

### P1 — Integridade de schema e trilha de auditoria
- **Objetivo:** criar a base de integridade e auditoria do ciclo, sem tocar em
  comportamento de cliente.
- **Arquivos/superfícies esperadas:** `supabase/migrations/<ts>_f5_09_cycle_sovereign.sql`
  (índice único parcial I5, exclusion I6, tabela `cycle_events` — com
  `event_type` já contemplando `ADMISSAO_INCLUIDA` — + trigger append-only +
  índices + comentários, RLS/grants deny-by-default, helper `ciclo_ator_valido`,
  registro da chave normativa de advisory lock);
  `supabase/validacao/01-cenario-f5-09.sql`, `02-validar-f5-09.sql`;
  `supabase/migrations/README.md`.
- **Dependências:** nenhuma (base `6550c81`); Q-F5-09-1 e Q-F5-09-3 ratificadas.
- **Entregável:** migration aditiva + cenário/validador SQL 01/02 (schema,
  grants, RLS, exclusão física negada, trilha append-only, não sobreposição).
- **Gate de saída:** `db reset` + `01-cenario` + `02-validar` verdes no job
  `supabase-local`; nenhum arquivo de `src/` alterado; `git diff --check` limpo.
- **Risco principal:** constraint nova falhar sobre dados existentes (R2) —
  checar antes de aplicar e registrar.

### P2 — RPCs de gestão: criar, editar, ativar, encerrar
- **Objetivo:** tornar o ciclo gravável e ativável server-side, com materialização
  da população inicial e encerramento reusando a F5-06.
- **Arquivos/superfícies esperadas:**
  `supabase/migrations/<ts>_f5_09_cycle_rpc.sql` (`ciclo_criar`, `ciclo_editar`,
  `ciclo_ativar`, `ciclo_encerrar`), validadores SQL 03/04.
- **Dependências:** P1.
- **Entregável:** RPCs `SECURITY INVOKER` com `EXECUTE` só `service_role`,
  idempotência, `expected_version`, lock, materialização F3-08 (população
  inicial), reuso de `evaluation_fechar_ciclo_pendencias`, trilha.
- **Gate de saída:** validadores SQL verdes (T0, T1, T2, T3, T8, T9, I5, I6, I9,
  concorrência de ativação, idempotência, pendências, cenário 16).
- **Risco principal:** divergir do contrato F5-06 no encerramento (R6).

### P3 — Inclusão aditiva de nova admissão (D26)
- **Objetivo:** implementar a **única** ampliação de população permitida depois da
  ativação, com prova soberana e contrato restrito (§7.2/§7.3).
- **Arquivos/superfícies esperadas:**
  `supabase/migrations/<ts>_f5_09_cycle_admission.sql`
  (`ciclo_admissao_pos_ativacao_elegivel` — helper read-only com P1–P7 — e
  `ciclo_incluir_admissao`), validador SQL `05-validar-f5-09-admissao.sql`
  cobrindo A1–A12 do §15.1.
- **Dependências:** P1, P2.
- **Entregável:** helper de elegibilidade + RPC restrita (sem nenhum parâmetro
  estrutural), reuso de `materializar_colegiado_ciclo` com um único
  `collaborator_id`, recusa quando já materializado, trilha `ADMISSAO_INCLUIDA`
  com o id do evento `ADMISSAO` que autorizou.
- **Gate de saída:** validador SQL verde em A1–A12, incluindo os negativos
  (movimentação, tentativa de troca de posição, admissão anterior à ativação fora
  do snapshot, cross-tenant, membership revogada, capability negada, concorrência
  e idempotência) e a prova de que nenhuma linha existente de snapshot é alterada.
- **Risco principal:** a operação virar "atualizar estrutura do ciclo" (R16) ou a
  prova de admissão não ser estabelecível para colaborador legado (R15) — em
  ambos, a resposta é **recusa** (fail-closed), nunca flexibilização.

### P4 — Fluxos excepcionais: cancelar, reabrir, corrigir período
- **Objetivo:** implementar T4/T5/T6/T7 com efeitos transacionais sobre
  avaliações e trilha.
- **Arquivos/superfícies esperadas:** migration de RPCs excepcionais +
  validador SQL 06.
- **Dependências:** P2; Q-F5-09-1 ratificada (T5 e `domainState`).
- **Entregável:** RPCs + validador (cancelamento com avaliações, terminalidade de
  `CANCELADO`, reabertura com outro `ATIVO`, correção de período com impacto).
- **Gate de saída:** validadores SQL verdes, incluindo casos negativos e de
  concorrência.
- **Risco principal:** cancelamento deixar avaliações impossíveis de cancelar
  (R5) ou apagar história (I11).

### P5 — Leitura soberana e porta do cliente
- **Objetivo:** abrir leitura own-tenant do ciclo e criar a porta única de
  leitura/escrita no cliente.
- **Arquivos/superfícies esperadas:** migration com policy + grant (D22);
  `src/infrastructure/supabase/ciclos/repositorioCiclosSoberanos.ts`;
  `src/services/acessoCiclosSoberanos.ts`; testes UNIT/STATIC.
- **Dependências:** P1.
- **Entregável:** leitura por RLS, sem escrita; porta única; nenhuma página
  alterada ainda.
- **Gate de saída:** `npm test`, `npm run build`, `npm run lint`,
  `npx tsc -b tsconfig.app.json`, `git diff --check` verdes; validadores SQL de
  RLS (own-tenant × cross-tenant × membership revogada).
- **Risco principal:** abrir superfície de leitura além do necessário (mitigado
  por D22 e cenários 2–5).

### P6 — Fechamento do gate no Policy Engine
- **Objetivo:** tornar `cycle.read`/`cycle.manage` executáveis contra recurso real
  e ampliar `cycle.cancel` para `{PLANEJADO, ATIVO}` (D8), com atualização
  aditiva da descrição da capability.
- **Arquivos/superfícies esperadas:** `src/authorization/authorizationPolicy.ts`,
  `src/authorization/authorizationPolicy.test.ts`,
  `src/authorization/policyEngine/*` (se necessário) e migration aditiva de
  descrição da capability (`cycle.cancel`).
- **Dependências:** Q-F5-09-1 ratificada.
- **Entregável:** ramos de policy aditivos + testes de `domainState` por status,
  incluindo `cycle.admissao.incluir` (`ATIVO`).
- **Gate de saída:** `npm test` verde; nenhuma capability nova; nenhuma alteração
  em F4/F5 fora deste domínio.
- **Risco principal:** alterar contrato de autorização de outros domínios (R13).

### P7 — Edge Function `ciclos` e habilitação de produção (D28)
- **Objetivo:** expor o contrato autorizado de mutação e leitura de ciclo e
  garantir que a operação seja **executável em produção**.
- **Arquivos/superfícies esperadas:** `supabase/functions/ciclos/{index,core,contrato}.ts`
  (incluindo `cycle.admissao.incluir` com contrato restrito — §13.1 regra 9);
  `src/infrastructure/supabase/ciclos/edgeCiclos.ts`;
  `src/authorization/ciclosContratoRpc.test.ts` (teste que lê o código real da
  Edge, padrão `avaliacoesContratoRpc.test.ts`); **migration de reconciliação
  aditiva do catálogo** (`cycle.manage` no bundle `admin`, D28).
- **Dependências:** P2, P3, P4, P5, P6.
- **Entregável:** Edge com mapa explícito operação → capability, gate
  funcional/administrativo, erro tipado, ator verificado; `cycle.manage` no
  bundle `admin` (as três excepcionais permanecem fora).
- **Gate de saída:** testes INTEG/UNIT verdes; contrato conferido contra as
  assinaturas reais das RPCs; nenhum `default` de capability; validador SQL
  confirmando que `cycle.cancel`/`cycle.reopen`/`cycle.period.correct` **não**
  estão no bundle `admin`.
- **Risco principal:** divergência de assinatura (histórico real da F5-06 —
  bloqueia a operação inteira) e cutover publicado sem ninguém capaz de gerenciar
  ciclo (R9, mitigado por D28).

### P8 — Cutover do cliente
- **Objetivo:** remover a autoridade local de ciclo e migrar os 21 consumidores.
- **Arquivos/superfícies esperadas:** `src/services/cicloAvaliacaoStorage.ts`
  (barreiras fail-closed + cache UX), `src/types/CicloAvaliacao.ts`,
  `src/application/ports/CycleRepository.ts`,
  `src/infrastructure/localStorage/localCycleRepository.ts`,
  `src/services/{cancelamento,reabertura,correcaoPeriodo}cicloService.ts`,
  `src/services/cicloEquipeService.ts`, `metaStorage.ts`, `observacaoStorage.ts`,
  `permissaoAvaliacao.ts`, `progressoAvaliacao.ts`, as 12 páginas/componentes
  listados em §14, projeção/cache + hook do shell, guardas estáticos. A operação
  de inclusão aditiva é **superfície nova** (§14): a porta única pode expô-la, sem
  qualquer autoridade local e sem botão que substitua a decisão server-side.
- **Dependências:** P5, P6, P7.
- **Entregável:** cutover completo com classificação A/B/C/D aplicada e
  invariantes verificados.
- **Gate de saída:** suíte completa verde, guardas estáticos reprovando escrita
  local/identidade local, `build`/`lint`/`tsc`/`git diff --check` verdes.
- **Risco principal:** regressão funcional em telas de metas/observações que
  dependem de ciclo (R12) e vazamento entre tenants na troca de organização.

### P9 — Validação integrada, CI e DoD
- **Objetivo:** provar a integridade ponta a ponta e a não regressão dos
  domínios anteriores.
- **Arquivos/superfícies esperadas:** validador integrado de cutover
  `supabase/validacao/07-validar-f5-09-cutover.sql` (incluindo os casos A3/A11 de
  imutabilidade e a regressão de admissão), atualização de
  `.github/workflows/ci.yml` (job `supabase-local`), `.ai/handoff.md`,
  `.ai/virtus-context.md`.
- **Dependências:** P1–P8.
- **Entregável:** validação cruzada F5-06/F5-07/F5-08 + F5-09 e evidência
  registrada.
- **Gate de saída:** CI verde com todos os validadores; suíte Vitest completa;
  `build`/`lint`/`tsc`; relatório de gates executados × não executados.
- **Risco principal:** regressão silenciosa em F5-06/07/08 (R13).

**Número final de fases: 9.**

---

## 20. Definição de pronto (DoD)

1. Existe **uma** entidade soberana de ciclo (`evaluation_cycles` estendida
   aditivamente); nenhuma tabela concorrente foi criada.
2. Toda mutação oficial de ciclo ocorre por RPC transacional
   (`SECURITY INVOKER`, `EXECUTE` só `service_role`) através da Edge `ciclos`,
   com ator verificado e autoria soberana na trilha.
3. O cliente **não** decide existência, identidade, estado, vigência, transições
   nem estrutura aplicável do ciclo; nenhuma escrita local de ciclo existe em
   produção; a classificação A/B/C/D foi aplicada aos 21 consumidores.
4. Identidade é UUID em todas as camadas; `(ano, numero)` é apenas rótulo e
   unicidade; nenhuma superfície usa índice, texto ou chave de `localStorage`
   como identidade.
5. Máquina de estados do §6 implementada com pré-condições, capability,
   efeitos transacionais e trilha por transição; transições inválidas são
   `CONFLICT` sem efeito.
6. Estrutura por ciclo derivada de F3-04/F3-08/F3-09/F5-06, com **modelo
   híbrido** (D26/D27): população inicial materializada na ativação, snapshots
   existentes **imutáveis**, admissões posteriores elegíveis incorporáveis apenas
   pela operação restrita e aditiva (com prova soberana) e movimentações sem
   rematerialização; histórico preservado e nenhuma hierarquia textual.
7. A **inclusão aditiva de nova admissão** (D26) existe como a única ampliação de
   população: contrato sem parâmetros estruturais, prova soberana P1–P7
   obrigatória (§7.2), recusa quando já materializado, recusa sem prova
   (fail-closed) e trilha `ADMISSAO_INCLUIDA` referenciando o evento de admissão
   que a autorizou; nenhum snapshot existente é alterado.
8. **Movimentações durante o ciclo ativo** (D27) não rematerializam estrutura de
   participante já materializado: a alteração vale no próximo ciclo, ressalvados
   os mecanismos excepcionais já contratados (sucessão F3-09 e realinhamento
   F5-06), provado pelos casos A3/A4 do §15.1.
9. Integridade I1–I20 garantida no banco (constraints + RPCs) e provada por
   validadores SQL, incluindo concorrência, idempotência, `expected_version`
   obsoleto, exclusão física negada, cross-tenant e **não sobreposição de ciclos
   não `CANCELADO`** (D15, garantida no banco).
10. RLS de leitura own-tenant ativa e escrita do cliente fechada; trilha
    deny-by-default e append-only.
11. Autorização reusa as capabilities existentes (nenhuma nova), com mapa
    explícito e sem fallback; `service_role` nunca decide; fail-closed em toda
    ausência de âncora/capability/estado; `cycle.manage` concedida aditivamente no
    bundle `admin` (D28), com as três excepcionais mantidas fora dele.
12. Nenhuma regressão em F5-06, F5-07 e F5-08 (validadores e suíte completos).
13. Metas/observações/relatórios permanecem declarados como residual com
    atividade própria, sem autoridade sobre o ciclo.
14. **Zero dúvida bloqueante aberta:** Q-F5-09-1, Q-F5-09-2 e Q-F5-09-3
    ratificadas e refletidas no contrato (D8/D9, D15, D26/D27, D28), sem nenhuma
    decisão tomada em silêncio e sem nova dúvida identificada na revisão
    transversal.
15. Comandos de qualidade executados e registrados (`npm test`, `npm run build`,
    `npm run lint`, `npx tsc -b tsconfig.app.json`, `git diff --check`) e
    validadores SQL executados no CI; limitações do host declaradas quando
    houver.
