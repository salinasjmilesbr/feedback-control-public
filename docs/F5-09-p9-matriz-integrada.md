# F5-09/P9 — Matriz executável da validação integrada

> Atividade: **F5-09/P9 — Validação Integrada de Ciclos Soberanos**.
> Base: `main` = `a1e30a86` (F5-09/P8 integrada pelo squash do PR #205).
> Branch: `feat/f5-09-p9-integrated-validation`.
> Contrato: especificação da Issue (11 blocos obrigatórios) + `docs/F5-09-desenho-tecnico.md`
> §11/§12/§13.2/§19 (P9) + `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md` §3.

## 1. O que a P9 é (e o que ela NÃO é)

É **validação integrada**: prova, sob condições adversas e no contrato REAL já
entregue (P1–P8), que a autoridade de ciclo é soberana e que nenhum caminho de
cliente consegue suplantá-la.

Não é:

- antecipação de **F5-10** (metas) nem de **F5-11** (observações);
- criação de RPC, policy, RLS, capability, Edge ou migration;
- redesign visual;
- implementação de nova API de histórico;
- correção oportunista de defeitos fora do contrato (ex.: import pré-existente
  de `supabase/functions/avaliacoes`).

Alterações de produção só são admitidas se um teste revelar defeito real que
impeça o cumprimento de contrato já fechado — com evidência, severidade e
registro. **Nenhum defeito de produção foi encontrado nesta rodada.**

## 2. Como executar (local, Supabase em Docker)

```bash
npx --yes supabase@2.116.0 db reset --local --yes            # estado limpo (trilha e append-only)

docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/14-cenario-f5-09-p9.sql               # fixture integrada (prefixo `ed`)
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/15-validar-f5-09-p9.sql               # blocos 1–5 e 7–11

# Bloco 6 — CONCORRÊNCIA REAL: duas sessões psql distintas
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/16-sessao-a-f5-09-p9-concorrencia.sql &    # sessão A (background)
sleep 1
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/17-sessao-b-f5-09-p9-concorrencia.sql      # sessão B (foreground)
wait
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/18-validar-f5-09-p9-concorrencia.sql  # consolidação pós-corrida
```

No CI, os quatro passos rodam no job `supabase-local`, **depois** do validador
`13-validar-f5-09-p7-d28.sql` e **antes** das regressões F5-06/F5-07
(`.github/workflows/ci.yml`), com a sessão A em background e a B em foreground.

## 3. Matriz dos 11 blocos obrigatórios

| # | Bloco obrigatório | Onde é provado | Tipo |
|---|---|---|---|
| 1 | Cross-tenant (leitura e mutação; UUID de outro tenant; coerência RLS × Policy Engine) | `15-validar-f5-09-p9.sql` §1 | SQL |
| 2 | Membership revogada (vale já na operação seguinte; estado client-side não preserva ALLOW) | `15` §2 | SQL |
| 3 | Capability revogada (`can()` é só UX; enforcement server-side) | `15` §3 | SQL |
| 4 | IDOR (UUID válido inacessível; payload não escolhe ator/tenant/capability) | `15` §4 | SQL |
| 5 | Stale `expectedVersion` (CONFLICT; sem overwrite silencioso) | `15` §5 | SQL |
| 6 | **Concorrência real entre duas sessões** | `16` + `17` + `18` | PostgreSQL multi-sessão |
| 7 | Idempotência (`operation_id` é chave, não identidade) | `15` §7 | SQL |
| 8 | Rollback/atomicidade (falha controlada; nenhum estado parcial) | `15` §8 | SQL |
| 9 | Auditoria (evento esperado, autoria soberana, before/after, operation identity, append-only) | `15` §9 | SQL |
| 10 | RLS (own-tenant; `authenticated` sem escrita; `service_role` executor e não decisor) | `15` §10 | SQL |
| 11 | Regressões P1–P8 (focadas + suíte completa; sem fallback/dual-read/dual-write; sem antecipar F5-10/F5-11) | `15` §11 + `src/services/ciclosSoberanos/p9MatrizIntegrada.test.ts` + suíte Vitest | SQL + TS + guardas estáticas |
| ★ | Imutabilidade de snapshot e regressão da admissão (A3/A11 e A1–A12 da P3) | `15` §12/§13 (cobertura exaustiva em `06-validar-f5-09-p3.sql`) | SQL |

### Prova de concorrência real (bloco 6) — desenho

- **Sessão A** cria o ciclo pelo caminho legítimo (`ciclo_criar`) e, em seguida,
  executa a MESMA edição (`ciclo_editar`) com um artefato temporário em `public`
  (sequence + trigger `BEFORE UPDATE` em `evaluation_cycles`) que publica uma
  **marca não transacional** e faz a escrita demorar **8 s**. Durante esse
  intervalo A **detém** `ciclo_lock_organizacao` (`pg_advisory_xact_lock` na
  chave normativa `evaluation_cycles:<organization_id>`), adquirido pela RPC
  **antes** do `select for update` e da checagem de `expected_version`.
- **Sessão B** (processo `psql` separado) usa um laço determinístico de até
  **120 × 0,25 s = 30 s** que exige **duas** condições: (i) o ciclo criado por A
  existir e (ii) a **marca de A já estar publicada**. A condição (ii) é o
  refinamento que torna a prova determinística: sem ela, "esperar apenas a
  existência do ciclo" deixaria a corrida real de *quem pega o lock primeiro* e
  B poderia vencer por escalonamento. Com a marca, A vence sempre, porque a marca
  só existe depois de A estar dentro do UPDATE **com o lock em mãos**.
- B então mede o tempo e tenta a MESMA edição com o MESMO `expected_version`
  (0), porém com intenção divergente (outras datas e outro `operation_id`).
- B **bloqueia** no lock de A; quando A confirma, B adquire o lock, relê a versão
  (agora 1) e termina em **CONFLICT**. O `[PASS]` de B exige as duas condições:
  o erro de conflito do contrato **e** tempo decorrido ≥ 2 s (prova de que B
  esperou — sem isso não haveria contenção demonstrada).
- `18-validar-f5-09-p9-concorrencia.sql` consolida: estado final é o de A,
  período é o de A (nenhum lost update), uma única linha de ciclo válida e
  exatamente um evento por operação — nada da intenção de B.
- **Onde vive a evidência**: o *bloqueio* de B só é observável no **stdout de
  B** (tempo medido + mensagem do CONFLITO), porque a tentativa perdedora não
  deixa estado algum no banco; o validador 18 prova o estado consolidado e a
  ausência de qualquer efeito de B. Os dois artefatos são registrados juntos.
- **Ajustes de sessão declarados** (nenhum controle de produto relaxado, nenhum
  objeto de banco alterado): `statement_timeout = 0` e `lock_timeout = 0` nas
  sessões A/B — a janela de 8 s e a espera no lock são **contratadas** pela prova
  — e `read committed` na sessão B (a reavaliação de `expected_version` sob o
  lock depende de *snapshot* por comando, que é o nível default do Supabase).

**Distinção explícita da P8:** a P8 provou concorrência **client-side** (geração
monotônica no controlador: duas leituras/mutations na mesma aba, promise
atrasada, flag `operacaoEmAndamento`, fail-closed local). A P9 prova contenção
**server-side**: dois backends PostgreSQL concorrentes disputando o mesmo lock
de organização, com o cliente (A/B) apenas disparando a operação. São garantias
diferentes: a primeira impede estado de UI inconsistente; a segunda impede
lost update no banco.

## 4. Lado cliente (`src/services/ciclosSoberanos/p9MatrizIntegrada.test.ts`)

Em node (sem jsdom), com fakes injetados e leitura `?raw` dos módulos:

- **P9-1** — existem exatamente as 8 operações contratadas, com gate/capability
  do contrato (`cycle.manage` em criar/editar/ativar/encerrar/admissão;
  `cycle.cancel`, `cycle.reopen`, `cycle.period.correct` nas excepcionais;
  `cycle.criar` é o único gate administrativo).
- **P9-2** — nenhuma operação/capability de metas ou observações foi antecipada;
  as fontes do caminho soberano não citam `cycle_goals`/`observac`.
- **P9-3/P9-4** — a página não fala com o banco nem com storage local
  (`.rpc(`, `functions.invoke`, `localStorage`, `sessionStorage`,
  `localCycleRepository`, `crypto.randomUUID` ausentes); `functions.invoke`
  aparece **só** no adapter da Edge.
- **P9-5** — composição sem caminho soberano (`cliente: null`) é fail-closed.
- **P9-6** — `operationId` é chave de idempotência: único por chamada e distinto
  do UUID do ciclo (identidade), com `expectedVersion` da leitura soberana e
  **nenhum** campo de autoridade no payload (sem `actor`/`role`/`capability`/
  `status`).
- **P9-7/P9-8** — mutation soberana não grava nada em storage local (sem
  dual-write) e `novoOperationId()` é UUID v4 distinto a cada chamada.
- **P9-9/P9-10** — regressões P5–P8 preservadas: gerações monotônicas de leitura
  e mutation, filtro da última leitura, mensagem de confirmação indisponível;
  leitura pelo repositório RLS e mutation pela Edge.

## 5. Resultados por bloco

### Execução de referência (host local, Docker + Supabase local)

Bateria completa na ordem do CI: **33/33 entradas, `falhas=0`** (`db reset` exit 0).

| Bloco | Evidência |
|---|---|
| 1–5, 7–11 e ★ (fixture `14` + validador `15`) | `15` exit 0, **42 notices `[PASS]`, `FAIL=0`, `ERROR=0`**; fixture `14` exit 0 (PASS=2, insert-once) |
| 6 (concorrência real) | sessão A `[PASS]=5`, sessão B `[PASS]=5`, consolidação `18` `[PASS]=4`: A deteve `ciclo_lock_organizacao` por **~8,02 s**; B ficou **bloqueada ~7,32 s** e terminou em `F5_09_CONFLICT`; estado/período finais são os de A (nenhum lost update); trilha `CRIADO + EDITADO`; zero evento da intenção perdedora; append-only confirmado |
| Regressões P1–P8 (SQL) | P1 `61`, P2 `21`, P3 `17`, P4 `21`, P5 `10`, P7 `7` + D28 (`12`→`1`, reaplicação→`1`, validador `13`→`5`), F5-04 `25`, F5-08 `57+12`, F5-06 `26+13`, F5-07 `44+22` — **zero falhas** |
| Regressões P5–P8 (cliente) | `p9MatrizIntegrada.test.ts` **10/10**; focados de ciclos+página **71**; `npm test` **120 arquivos / 1860 testes** |

### Findings da P9 (registrados)

1. **Defeito de integração real, encontrado apenas na ordem do CI**: o §11 do validador contava ciclos **globalmente** exigindo evento `CRIADO`; como as fixtures P1–P5 (que rodam antes) inserem ciclos **diretamente**, a checagem acusava 9 ciclos "sem CRIADO" ✗ — passava isolada e **falharia no CI**. Corrigido escopando a checagem às organizações do fixture P9 (`eda…a1/b1/c1`). É exatamente o tipo de defeito que a validação integrada existe para pegar.
2. **14 defeitos de artefato de validação** corrigidos por execução real (nenhum de produção): I5 violado no setup; tabela temporária qualificada como `public.`; `RAISE` com 6 placeholders e 5 argumentos; `string_agg(x, …)` sem a subquery que define `x`; colisões de `operation_id` entre chamadas com intenções diferentes; replay de idempotência com payload divergente; precedência **estado antes de versão** nas RPCs (asserções ajustadas ao contrato real, com a precedência declarada); `NOT_FOUND`/`FORBIDDEN` **indistinguíveis** para cross-tenant (§8); grant de `cycle.manage` não restaurado após a prova de revogação; encerramento ausente entre A5→A3 (violava I5); gatilho de rollback disparando só na 2ª escrita; invariante I5 "no máximo um ATIVO" (não "exatamente um"); catálogo legado de metas/observações = **8** (`3 goal.* + 5 observation.*`), não 7; contador de escrita **não transacional** (`nextval`) contando escrita revertida.
3. **Defeito do harness local** (meu, não versionado): o contador de falhas somava errado porque `Write-Output` dentro de função entra no valor de retorno — corrigido; a bateria passou a reportar corretamente (foi assim que o defeito nº 1 apareceu).
4. **Nenhum defeito de produção**: em todos os casos o PostgreSQL/RLS/Edge recusaram ou efetivaram exatamente conforme o contrato fechado (D1–D28), verificado por consulta direta ao banco. Nenhuma migration, RPC, policy, Edge ou página foi alterada pela P9.

## 6. Gates executados × não executados

**Executados neste host** (Docker 29.7.2 + Supabase local):

- preflight: branch/base (`main` = `a1e30a86`), HEAD, worktree limpo, Docker acessível, `db reset --local --yes` exit 0;
- bateria SQL completa na ordem do CI: **33/33, `falhas=0`** (inclui fixture/validador P9, concorrência em duas sessões e todas as regressões);
- focados (`ciclosSoberanos` + página + matriz P9): **71** verdes;
- `npm test` **120 arquivos / 1860 testes**; `npm run build`; `npm run lint`; `npx tsc -b tsconfig.app.json`; `git diff --check`; `git status --short` — todos exit 0.

**Não executados (e por quê)**:

- **job `supabase-local` do CI**: os passos P9 foram adicionados ao workflow, mas o CI só roda no **SHA auditado** após o push — a evidência local acima usa exatamente os mesmos arquivos e a mesma ordem;
- **auditoria GPT e auditoria independente Codex**: etapas externas do fluxo, posteriores a esta entrega;
- nenhum gate SQL deixou de ser executado (nenhuma migration/backend novo foi criado pela P9).

## 7. Desvios e limitações declarados

1. **Nomes dos arquivos**: o §19 do desenho cita
   `supabase/validacao/07-validar-f5-09-cutover.sql`, que **nunca existiu** (o
   prefixo `07` pertence a `07-cenario-f5-09-p4.sql`). A P9 usa a numeração
   global seguinte — `14`–`18` — sem renumerar arquivos históricos.
2. **Sem RPC de leitura**: `ciclo_painel`/`ciclo_historico` não existem (débito
   declarado na P7); a leitura integrada é validada por **RLS/PostgREST**
   (P5), não por RPC nova — criar RPC não é superfície da P9.
3. **`p_payload_hash`**: desvio já declarado em P2–P4 (hash derivado
   server-side); a P9 valida o `payload_hash` gravado na trilha, não um
   parâmetro de entrada.
4. **Fixture insert-once**: a trilha é append-only protegida; cada execução
   íntegra exige `db reset` (o CI faz isso; ids/`operation_id` são fixos).
5. **A3/A11 (imutabilidade de snapshot)**: provados por comparação de conteúdo e
   contagem de escrita na validação integrada; a cobertura exaustiva A1–A12 da
   admissão permanece em `06-validar-f5-09-p3.sql`, que roda no mesmo job do CI.
