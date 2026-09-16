# F5-11 — Certificação (Issue #254)

> **Artefato documental.** Nenhum código funcional, migration, RPC, role, capability,
> validador de banco ou refatoração foi criado ou alterado nesta rodada. Este documento
> existe para que o fechamento da F5-11 seja **verificável**, não opinativo.

## 0. Base, método e limites

- **Base auditada:** a árvore de trabalho da branch `docs/f5-11-p6-certificacao` (criada pelo
  orquestrador a partir da `main` atualizada). Esta sessão **não tem shell**: o SHA exato do
  HEAD e a comparação com `origin/main` devem ser confirmados pelo orquestrador.
- **Método:** auditoria estática (leitura de fonte/SQL com `arquivo:linha`) confrontada com os
  critérios de aceite **§17.1 (P1–P6)** e a **matriz normativa §8** de
  `docs/F5-11-desenho-tecnico.md`.
- **Issues ilegíveis:** `#238` (mãe) e `#254` **não são legíveis neste ambiente** (não há `gh`).
  Portanto todo critério aqui foi **extraído do desenho técnico** (§8, §17.1 e registros §18–§23);
  qualquer requisito que exista **apenas** no texto das Issues e não no desenho está marcado como
  **NÃO VERIFICADO** (§5).
- **Gates de banco/CI não foram executados nesta rodada** (sem shell). O que se certifica aqui é a
  **existência e a coerência da evidência**; os números de execução citados vêm dos gates/CI já
  registrados e devem ser **reproduzidos no SHA final** pelo orquestrador (§3).

## 1. Critérios de aceite × evidência × status

| Fase | Critério (desenho §17.1, linha) | Evidência concreta | Status |
|---|---|---|---|
| **P1** | Tabelas de §7.2, RLS deny-by-default integral (D9), trilha append-only (D6), exclusão física negada (D8), FKs compostas de tenant, guardas invertidas substituídas, cenário+validador `[PASS]`, catálogo em 31 (linha 1228) | `supabase/migrations/20260929000000_f5_11_p1_observations_schema.sql`; `supabase/validacao/34-cenario-f5-11-p1.sql`; `35-validar-f5-11-p1.sql` (PASS=11 no gate local); `.github/workflows/ci.yml:462-479` | **CERTIFICADO** |
| **P1.1** | Coerência estrutural perfil↔membership intra-tenant; `author_collaborator_id` determinado pelo resolvedor soberano (Issue #242, finding MEDIUM do Codex) | `supabase/migrations/20260930000000_f5_11_p1_1_coerencia_identidade_observacoes.sql`; `36-cenario-f5-11-p1-1.sql`; `37-validar-f5-11-p1-1.sql` (PASS=8); `ci.yml:480-496`; `docs/F5-11-desenho-tecnico.md` §19 | **CERTIFICADO** |
| **P2** | RPCs `observacao_*` SECURITY INVOKER + `search_path` fixo + `EXECUTE` só `service_role`; gate por operação com allowlist fechada; `expected_version` com `FOR UPDATE` antes da comparação (D10); idempotência dupla (D6); eventos na mesma transação; matriz D11/D12 e fail-closed (linha 1229) | `supabase/migrations/20260931000000_f5_11_p2_observacoes_rpc.sql`; `38-cenario-f5-11-p2.sql`; `39-validar-f5-11-p2.sql` (PASS=7); `ci.yml:497-513`; desenho §20 | **CERTIFICADO** |
| **P3** | `observation` **fora** de `TIPOS_RECURSO_NAO_SOBERANOS`; `carregarRecurso` real; `alvosPermitidos` por relação; matriz capability × estado com fonte única; tabela D15 documentada; `admin` sem `observation.*`; ALLOW no caminho de produção; `authorizationPolicy.test.ts:508-518` invertido (D5) (linha 1230) | `20260932000000_f5_11_p3_authorization_observacoes.sql` (perfil `observacoes_gestor` em `:176-180`); `40-cenario-f5-11-p3.sql`; `41-validar-f5-11-p3.sql` (PASS=4); `ci.yml:514-530`; `src/authorization/resourceContextReal.ts:55` (`TIPOS_RECURSO_NAO_SOBERANOS = [] as const`) + guarda `src/authorization/ciclosPolicyEngine.test.ts:177`; `src/authorization/estadoDominioObservacao.ts`; desenho §21 | **CERTIFICADO** |
| **P4** | Edge `observacoes` com trio `index`/`core`/`contrato` + contrato transportável único; allowlist estrita por operação; adapter fail-closed nos 3 caminhos e todos os `CodigoPublico`; guardas de grafo de imports (linha 1231) | `supabase/functions/observacoes/index.ts`, `core.ts`, `contrato.ts`; `src/infrastructure/supabase/observacoes/contrato.ts`; `edgeObservacoes.ts`; testes `src/authorization/observacoesEdgeImportGraph.test.ts`, `observacoesContratoRpc.test.ts`, `src/infrastructure/supabase/observacoes/*.test.ts`; `supabase/config.toml` `[functions.observacoes]`; desenho §22 | **CERTIFICADO** |
| **P5** | `observacaoStorage.ts` com barreira que lança nas 3 mutações e leitura local fora do caminho funcional (D13); `geradorDadosTeste` sem escrita na chave legada; telas e arrasto (PDF, MinhaAvaliação, KPIs) lendo do soberano; listas de exceção ajustadas; resíduo morto resolvido; **sem dual-read** (linha 1232) | `src/services/observacaoStorage.ts:34-39` (`ERRO_ESCRITA_LOCAL_OBSERVACOES`/`barreiraDeEscritaLocal`) e `:126,142,153`; guardas `src/authorization/estruturaUiSeguranca.test.ts:530-531` e `src/services/observacaoStorage.test.ts:144-145`; `src/application/ports/ObservationRepository.ts`; `src/infrastructure/supabase/observacoes/repositorioObservacoesSoberanas.ts`; `src/services/observacoesSoberanas/{controladorObservacoes,mapeadorObservacaoUi,fluxoMutacaoObservacao}.ts`; `src/services/acessoObservacoesSoberanas.ts`; `src/pages/observacoesSoberanasDaPagina.ts`; `src/pages/ColaboradorDetalhePage.tsx`; `src/services/exportarAvaliacaoPdf.ts`; desenho §23 | **CERTIFICADO** |
| **P5.1** | SELF/read soberano de observações **comunicadas**: 5º system role `observacoes_avaliado` com **exatamente** `observation.read`, **sem scope**, provisionado **automaticamente** por elegibilidade (membership + perfil + vínculo ativos); inelegível ⇒ `revoked`; reativação na mesma assignment; D18 com ator SISTEMA | `20260933000000_f5_11_p5_1_self_read_observacoes.sql` (role em `:101-105`; função/triggers/backfill/guardas); `42-cenario-f5-11-p5-1.sql`; `43-validar-f5-11-p5-1.sql`; `ci.yml:531-547` | **CERTIFICADO** |
| **P5.2** | Autoridade administrativa por role: `usuario_eh_administrador` exige a role `admin` (não qualquer role de sistema) — fecha escalada amplificada pela P5.1 | `20260934000000_f5_11_p5_2_admin_authority_por_role.sql`; prova discriminante em `supabase/validacao/02-validar-f5-04.sql` (bloco 7.1) | **CERTIFICADO** |
| **P5.3** | Lifecycle completo: mudança isolada de `user_profiles.status` reavalia **cada** membership pela **mesma** função (sem duplicar a regra), com evento só em transição real | `20260935000000_f5_11_p5_3_lifecycle_perfil_avaliado.sql`; bloco `I` de `43-validar-f5-11-p5-1.sql` | **CERTIFICADO** |
| **P5.4** | `observacoes_avaliado` **exclusivamente automática**: grant/revoke humano bloqueado nas duas RPCs administrativas; colisão `origin='human'` falha fail-closed sem alterar histórico; corrida do primeiro provisionamento eliminada por upsert único (sem advisory lock) | `20260936000000_f5_11_p5_4_avaliado_exclusivo_e_corrida.sql`; bloco `J` de `43-validar-f5-11-p5-1.sql` | **CERTIFICADO** |
| **P6** | Matriz SQL integrada + **concorrência real entre duas sessões**; cross-tenant/IDOR/membership revogada/perfil inativo/capability ausente/relação ausente; idempotência e rollback; regressões P1–P8/F5-06/F5-07; **relatório de gates executados × não executados**; certificação (linha 1233) | **este documento** + os validadores 34–43 e o pipeline CI-equivalente (56 steps, com os 2 pares de concorrência reais) descrito em §3 | **CERTIFICADO DOCUMENTALMENTE** (execução dos gates é do orquestrador — §3) |

## 2. Inventário das entregas F5-11 (com caminho)

**Migrations (8):** `20260929000000_f5_11_p1_observations_schema.sql`;
`20260930000000_f5_11_p1_1_coerencia_identidade_observacoes.sql`;
`20260931000000_f5_11_p2_observacoes_rpc.sql`;
`20260932000000_f5_11_p3_authorization_observacoes.sql`;
`20260933000000_f5_11_p5_1_self_read_observacoes.sql`;
`20260934000000_f5_11_p5_2_admin_authority_por_role.sql`;
`20260935000000_f5_11_p5_3_lifecycle_perfil_avaliado.sql`;
`20260936000000_f5_11_p5_4_avaliado_exclusivo_e_corrida.sql`.

**RPCs/funções soberanas:** `observacao_criar`, `observacao_editar`, `observacao_definir_comunicado`,
`observacao_excluir`, `observacao_revogar`, `observacao_obter`, `observacao_listar_por_escopo`,
`observacao_historico` (+ helpers `f5_11_*` de identidade/relação/escopo/status/gate) —
`20260931000000` e `20260932000000`.

**Roles de sistema envolvidos:** `admin` (permanece **sem** `observation.*`), `metas_dono`,
`metas_aprovador`, `observacoes_gestor` (P3, `20260932000000:176-180`), `observacoes_avaliado`
(P5.1, `20260933000000:101-105`) — 5 roles de sistema.

**Edge:** `supabase/functions/observacoes/{index.ts,core.ts,contrato.ts}` +
`supabase/config.toml` (`[functions.observacoes]`, `verify_jwt = true`).

**Cliente:** `src/application/ports/ObservationRepository.ts`;
`src/infrastructure/supabase/observacoes/{contrato.ts,edgeObservacoes.ts,repositorioObservacoesSoberanas.ts}`;
`src/services/observacoesSoberanas/{controladorObservacoes.ts,mapeadorObservacaoUi.ts,fluxoMutacaoObservacao.ts}`;
`src/services/acessoObservacoesSoberanas.ts`; `src/pages/observacoesSoberanasDaPagina.ts`;
consumidores cortados: `src/components/ObservacoesColaborador.tsx`,
`src/components/filtroObservacoesPorCiclo.ts`, `src/pages/ColaboradorDetalhePage.tsx`,
`src/pages/MinhaAvaliacaoDetalhePage.tsx`, `src/services/exportarAvaliacaoPdf.ts`,
`src/services/observacaoStorage.ts`, `src/services/geradorDadosTeste.ts`.

**Validadores da cadeia (10):** `34/35` (P1), `36/37` (P1.1), `38/39` (P2), `40/41` (P3),
`42/43` (P5.1 inclusive P5.2–P5.4) — `supabase/validacao/` — mais os passos de CI em
`.github/workflows/ci.yml:462-547`.

**Suíte de testes da fase:** `src/authorization/observacoesEdgeImportGraph.test.ts`,
`observacoesContratoRpc.test.ts`, `observacaoRecursoSoberano.test.ts`, `observacoesEdge.test.ts`,
`src/infrastructure/supabase/observacoes/{contrato,edgeObservacoes,repositorioObservacoesSoberanas}.test.ts`,
`src/services/observacoesSoberanas/{controladorObservacoes,mapeadorObservacaoUi,fluxoMutacaoObservacao}.test.ts`,
`src/components/ObservacoesColaborador.test.tsx`, `src/pages/ColaboradorDetalhePage*.test.tsx`,
`src/pages/MinhaAvaliacaoDetalhePage.selfFailClosed.test.tsx`,
`src/services/{observacaoStorage,exportarAvaliacaoPdf}.test.ts`.

## 3. Gates exigidos para o fechamento (execução do orquestrador)

| # | Gate | Resultado esperado | Observação |
|---|---|---|---|
| 1 | `supabase db reset --local --yes` + cadeia `34…43` (fail-fast) | **10/10 etapas verdes**, zero `[FAIL]` | as 8 migrations F5-11 aplicam sem erro |
| 2 | Pipeline CI-equivalente **completo** (56 steps, ordem do CI, incluindo a reaplicação da migration D28 ×2 e os **dois pares de concorrência reais**) | **56/56 verdes** | reproduz o job `Supabase local — RLS/policy validation` |
| 3 | `npm test` | **2301/2303**, com **apenas** as 2 falhas pré-existentes de Windows/CRLF | nenhuma falha nova |
| 4 | `npm run build` | exit 0 | — |
| 5 | `npm run lint` | exit 0 | sem `eslint-disable` novo |
| 6 | `git diff --check` | exit 0 | — |
| 7 | CI do SHA final (GitHub) | SUCCESS | **autoridade** para os pares de concorrência |

## 4. Dívidas classificadas

| # | Dívida | Classificação | Evidência/impacto |
|---|---|---|---|
| 1 | Prova **literal** de transferência entre organizações no validador da P5.1 (provisionar na membership nova e revogar na antiga) | **Dívida não bloqueante** | a regra está provada pela elegibilidade **por membership** (blocos C6/C7 do `43`) e o trigger é por linha de membership; falta apenas a fixture de segunda organização |
| 2 | Defeito **latente de diagnóstico**: `v_falhas := v_falhas || 'literal'` em `text[]` em `41-validar-f5-11-p3.sql` | **Dívida não bloqueante** | hoje adormecido (só explode se uma guarda da P3 falhar, trocando um `[FAIL]` legível por `malformed array literal`); **não afeta autorização** |
| 3 | `42-cenario-f5-11-p5-1.sql` ainda deriva organização/ciclo do tenant da P2 (não é 100% autossuficiente) | **Dívida não bloqueante** | a fixture SELF dedicada (`f5c1`) é própria; a base da organização é herdada |
| 4 | 2 falhas PRÉ-EXISTENTES de Windows/CRLF em `src/pages/AcompanhamentoMetasPage.test.tsx` e `src/pages/MinhasMetasPage.test.tsx` | **Fora de escopo** (F5-10) | não introduzidas pela F5-11 |
| 5 | Fidelidade do harness local aos pares de concorrência do CI (sessão A em background + dianteira, em vez de `A &` no mesmo shell) | **Fora de escopo** | a autoridade para concorrência é o CI do SHA final |
| 6 | `gh` indisponível ⇒ abertura de PR e merge | **Fora de escopo / DEV-04** | branch + SHA + título/corpo entregues ao orquestrador |
| 7 | Resíduo morto histórico do domínio de ciclos (`ImpactoTemporalPeriodoCiclo.observacoes`, `persistirCorrecaoPeriodoCicloAtivoInterno`, `confirmarCorrecaoPeriodoCiclo.ts`) | **Dívida não bloqueante** | não está no caminho funcional de observações |

## 5. NÃO VERIFICADO nesta auditoria

1. **Texto das Issues #238 e #254** (ilegíveis sem `gh`): todos os critérios acima foram extraídos
   de `docs/F5-11-desenho-tecnico.md` (§8 e §17.1). Requisito que exista **apenas** nas Issues e não
   no desenho fica **não verificado**.
2. **SHA/HEAD e comparação com `origin/main`**: esta sessão não tem shell; o orquestrador deve
   confirmar a base auditada.
3. **Execução real dos gates** (§3): não executados nesta rodada por ausência de shell — os números
   citados (§1) vêm dos gates/CI já registrados nas fases e precisam ser reproduzidos no SHA final.
4. **Registro das fases P5.1–P5.4 no desenho técnico:** os registros §-numerados do desenho param na
   **§23 (P5)**; a família P5.1–P5.4 está registrada no handoff, no CI e nas migrations, mas **não** em
   uma seção própria do desenho (lacuna **documental**, não funcional — ver §6).

## 6. Lacuna MATERIAL BLOQUEANTE

**Não.** Na evidência disponível (fonte, SQL, validadores, CI e registros de fase), **nenhuma lacuna
bloqueante** foi encontrada para o fechamento da F5-11: todas as fases têm critério de aceite
atendido com evidência citável, e as pendências remanescentes são **dívidas não bloqueantes** ou
**fora de escopo** (§4). As duas ressalvas que impedem uma certificação "cega" são de **verificação**,
não de mérito: (i) os gates de §3 precisam ser reproduzidos no SHA final pelo orquestrador (incluindo
o CI, autoridade dos pares de concorrência); e (ii) o texto das Issues #238/#254 não pôde ser lido,
de modo que qualquer critério exclusivo delas permanece **não verificado**.
