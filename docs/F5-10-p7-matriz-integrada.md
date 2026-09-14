# F5-10/P7 — Matriz executável da validação integrada do domínio de metas

> Atividade: **F5-10/P7 — Validação integrada e certificação do domínio de metas**
> (Issue **#232**).
> Base: `main` = `f53144ff81cc8e011e68f81b1e3f942f50decb29`.
> Branch: `feat/f5-10-p7-validacao-integrada`.
> Contrato: `docs/F5-10-desenho-tecnico.md` §7 (lifecycle), §9 (aprovações e matriz
> D19), §10 (autorização), §11 (RLS × Policy Engine — D22), §12 (concorrência,
> versão e idempotência — D10/D11/D12), §15 (testes e validação integrada), §19 P7
> e §20 (DoD); `docs/F5-10-P5.2-contrato-leitura-soberana-metas.md`;
> `docs/F5-10-P5.3-autoridade-painel-ciclo.md`.
> Molde: `docs/F5-09-p9-matriz-integrada.md`.

## 1. O que a P7 é (e o que ela NÃO é)

É **validação integrada / certificação**: prova, sob condições adversas e no
contrato **REAL já entregue em P1–P6**, que o domínio de metas é soberano e que
nenhum caminho de cliente consegue suplantá-lo.

Não é:

- antecipação de **F5-11** (observações);
- criação de RPC, policy, RLS, grant, capability, Edge ou migration;
- reabertura de D1–D25 (F5-10) ou de D1–D28 (F5-09);
- duplicação dos validadores estreitos das fases P1–P5.2, que rodam no **mesmo job
  do CI**, imediatamente antes;
- redesign de UI ou manutenção oportunista fora do contrato.

Alterações de produção só seriam admitidas se um teste revelasse **defeito real**
contra contrato já fechado, com evidência, severidade e registro.

## 2. Como executar (local, Supabase em Docker)

```bash
npx --yes supabase@2.116.0 db reset --local --yes              # estado limpo

docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/29-cenario-f5-10-p7.sql                 # fixture integrada (prefixo `e8`)
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/30-validar-f5-10-p7.sql                 # matriz dos blocos 1 e 4–19

# Bloco 6 — CONCORRÊNCIA REAL: duas sessões psql distintas
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/31-sessao-a-f5-10-p7-concorrencia.sql &   # sessão A (background)
sleep 1
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/32-sessao-b-f5-10-p7-concorrencia.sql     # sessão B (foreground)
wait
docker exec -i supabase_db_feedback-control psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < supabase/validacao/33-validar-f5-10-p7-concorrencia.sql   # consolidação + higiene
```

No CI (`.github/workflows/ci.yml`, job `supabase-local`), os quatro passos rodam
**depois** do validador `28-validar-f5-10-p5-2.sql` e **antes** das regressões
F5-06/F5-07, com a sessão A em background e a B em foreground.

### Fixture: três organizações com papéis NÃO sobrepostos

| Org | Prefixo | Papel exclusivo |
|---|---|---|
| **Alfa-P7** | `e8a…a1` | matriz integrada (blocos 1 e 4–19) |
| **Beta-P7** | `e8a…b1` | provas cross-tenant / IDOR |
| **Gama-P7** | `e8a…c1` | **concorrência real** (31/32/33) — nasce **sem meta alguma** |

O prefixo `e8` foi escolhido por **inventário**: `f3` pertence ao cenário F3-01,
`d8` ao F4-08, `e7` ao F5-09/P7-D28, e `ee`/`f0`/`f1`/`f2` às P1–P4 — nenhum
deles é reutilizado (renumerar arquivos históricos é proibido pela Issue).

## 3. Matriz dos 20 blocos obrigatórios

| # | Bloco obrigatório | Onde é provado | Tipo |
|---|---|---|---|
| 1 | Sequência histórica integrada | `30` §S1 (parte A) + §S9 (parte B) | SQL |
| 2 | Concorrência real de edição com a mesma versão | `31` + `32` + `33` (fase 1) | PostgreSQL multi-sessão |
| 3 | Concorrência real de aprovação | `31` + `32` + `33` (fases 2 e 3) | PostgreSQL multi-sessão |
| 4 | Cross-tenant / IDOR | `30` §S2 | SQL |
| 5 | Membership revogada / perfil desabilitado | `30` §S3 | SQL |
| 6 | Capability sem relação | `30` §S4 | SQL |
| 7 | Relação sem capability | `30` §S4 | SQL |
| 8 | SELF escrevendo meta de terceiro | `30` §S5 | SQL |
| 9 | Aprovador sem `goal.write` | `30` §S6 | SQL |
| 10 | Ciclo inativo | `30` §S10 | SQL |
| 11 | Meta excluída | `30` §S11 | SQL |
| 12 | Quota excedida | `30` §S12 (RPC **e** invariante do banco) | SQL |
| 13 | Idempotência: mesmo payload / divergente | `30` §S8 | SQL |
| 14 | Rollback quando o evento falha | `30` §S7 (falha injetada na trilha) | SQL |
| 15 | Append-only | `30` §S13 | SQL |
| 16 | Browser / direct RPC proibido | `30` §S14 (lado servidor **e** cliente) + guardas TS já existentes | SQL + TS |
| 17 | Ausência de fallback / `localStorage` | `src/authorization/cutoverMetasSoberanas.test.ts` e `src/authorization/estruturaUiSeguranca.test.ts` (P6) + `30` §S14 | TS + SQL |
| 18 | Regressões P1–P6 | `30` §S16 + bateria SQL completa na ordem do CI + suíte Vitest | SQL + TS |
| 19 | Guardas invertidas coerentes | `30` §S15 | SQL |
| 20 | CI no SHA exato + auditorias finais | workflow + §6 deste documento | externo |

### Prova de concorrência real (blocos 2 e 3) — desenho

- **Sessão A** cria as **duas** metas da corrida pelo caminho legítimo
  (`meta_criar`) na organização **Gama-P7** e instala **dois artefatos
  temporários** em `public`: sequences **não transacionais** (marca de contenção)
  e gatilhos que atrasam uma escrita em **~8 s** (`pg_sleep`) —
  `_mut_p7_contencao_edicao` (BEFORE UPDATE em `evaluation_goals`) e
  `_mut_p7_contencao_aprovacao` (BEFORE INSERT em `evaluation_goal_approvals`).
- **Fase 1 (edição, mesma versão).** A chama `meta_editar` com
  `expected_version = 0`; o `UPDATE` dispara o gatilho e A dorme **dentro da
  transação**, já detendo `ciclo_lock_organizacao` (chave
  `evaluation_cycles:<org>`, adquirida pela RPC **antes** do `SELECT … FOR UPDATE`
  e da checagem de versão — D10/D12). A sessão B aguarda, em laço determinístico
  de até **120 × 0,25 s = 30 s**, a existência do alvo **e** a marca publicada
  (a marca só existe depois de A estar dentro do `UPDATE` com o lock em mãos —
  é isso que elimina a corrida de "quem pega o lock primeiro"). B então tenta a
  **mesma** edição com o **mesmo** `expected_version = 0` e intenção divergente:
  fica **bloqueada** no mesmo lock, e ao adquiri-lo relê a versão (agora 1) e
  termina em **`F5_10_CONFLICT` de versão divergente**. B só aceita a prova com
  **tempo decorrido ≥ 2 s** — sem a espera medida não haveria contenção
  demonstrada.
- **Fase 2 (aprovação, mesmo papel).** Diferença essencial em relação aos ciclos:
  **a aprovação não altera `version` da meta** (D2/D3). Logo, o
  `expected_version` de B continua válido e o que reprova B é a regra "**uma única
  aprovação VIGENTE por (meta, papel)**", avaliada **depois** do lock. Sem a
  serialização, as duas sessões poderiam passar pela mesma checagem `exists` antes
  do commit da primeira (READ COMMITTED). B termina em **`F5_10_CONFLICT` de "já
  existe aprovação vigente do papel GERENTE"**, também com espera ≥ 2 s.
- **Fase 3 (papéis distintos — contraparte positiva).** Com o lock já livre, o
  **COORDENADOR congelado** aprova a **mesma** meta: os dois fatos **coexistem**
  (um vigente por papel), com a autoria congelada de cada um, e o fato de A
  permanece intacto — nenhuma escrita legítima se perde.
- **Onde vive a evidência.** O **bloqueio** de B só é observável no **stdout de
  B** (tempo medido + mensagem do CONFLITO), porque a tentativa perdedora **não
  deixa estado**. O consolidador `33` prova o estado consolidado e a **ausência**
  de qualquer efeito das intenções perdedoras, além da **higiene** (remoção dos
  artefatos temporários). Os dois artefatos são registrados juntos.
- **Ajustes de sessão declarados** (nenhum controle de produto relaxado, nenhum
  objeto de banco alterado): `statement_timeout = 0` e `lock_timeout = 0` nas
  sessões A/B — a janela de 8 s e a espera no lock são **contratadas** pela prova
  — e `read committed` na sessão B (a releitura da versão sob o lock depende de
  snapshot por comando, que é o nível default do Supabase).

## 4. Lado cliente

Os blocos 16 e 17 têm a metade **estática/TS** já entregue pela **P5** e pela
**P6**, executada pela suíte Vitest no mesmo CI:

- `src/authorization/estruturaUiSeguranca.test.ts` — nenhum arquivo de produção
  chama `.rpc(` nem carrega `SERVICE_ROLE_KEY`; a autoridade de mundo local não é
  consumida por estrutura;
- `src/authorization/cutoverMetasSoberanas.test.ts` — guardas do cutover de metas
  (sem `localStorage`, sem dual-read/dual-write, identidade de ciclo por UUID
  soberano);
- `src/authorization/metasEdge.test.ts`, `metasEdgeImportGraph.test.ts`,
  `metasContratoRpc.test.ts`, `metaRecursoSoberano.test.ts`,
  `src/infrastructure/supabase/metas/*` — fronteira, contrato Edge→RPC e adapter
  fail-closed.

A P7 **não** reescreve essas guardas: ela verifica que continuam verdes e que o
lado SQL correspondente (permissão 42501 para `authenticated`/`anon`) segue
fechado.

## 5. Resultados por bloco

### Execução de referência (host local, Docker 29.7.2 + Supabase local, PostgreSQL 17.6)

Gate **focado** da P7 (`db reset` + `29` + `30` + `31/32/33`): **`falhas=0` de 4
entradas**; `db reset` **exit 0**.

| Bloco | Evidência |
|---|---|
| 0 (preflight) + 1 + 4–19 (fixture `29` + validador `30`) | `30` exit 0 com **19 notices `[PASS]`, `FAIL=0`, `ERROR=0`**; fixture `29` exit 0 (`PASS=2`: consistência + guarda de estado limpo) |
| 2 e 3 (concorrência real) | sessão A `[PASS]=5`, sessão B `[PASS]=4`, consolidação `33` `[PASS]=3`. **A deteve `ciclo_lock_organizacao` por ~8,03 s (edição) e ~8,02 s (aprovação)**; **B ficou bloqueada ~7,47 s** e terminou em `F5_10_CONFLICT` de **versão divergente**, e **~7,77 s** e terminou em `F5_10_CONFLICT` de **"já existe aprovação vigente"**; a fase 3 (papéis distintos) coexistiu com **2 fatos vigentes**, 1 por papel, o fato de A intacto e **nenhuma escrita legítima perdida** |
| 18 (regressões P1–P6) | `30` §S16 (invariantes estruturais, FKs de tenant, gatilhos, CHECK endurecido, 10 RPCs `INVOKER` com gate e lock normativo) + **bateria SQL completa na ordem do CI** + suíte Vitest |

### Findings da P7 (registrados)

1. **Nenhum defeito de produção.** Em todos os cenários o PostgreSQL/RLS/as RPCs
   recusaram ou efetivaram exatamente conforme o contrato fechado (D1–D25). A P7
   **não** alterou nenhuma migration, RPC, policy, RLS, Edge ou página.
2. **Três defeitos de artefato de validação — meus, encontrados na 1ª execução real
   e corrigidos em lote, com causa-raiz distinta em cada um:**
   (a) a guarda de estado limpo de `29` e o preflight de `30` esperavam **4** metas
   e **4** eventos em Alfa+Beta, mas a fixture cria **5** (4 em Alfa + 1 em Beta) —
   asserção minha, não do produto;
   (b) a MARCA de contenção da **aprovação** era consumida **2×** porque o gatilho
   temporário estava escopado apenas por `goal_id`: a **contraparte positiva** da
   fase 3 (COORDENADOR) insere na mesma meta **depois** da contenção e inflava o
   contador — corrigido escopando o gatilho **também por `papel = 'GERENTE'`**, de
   modo que `marca == 1` volte a significar "uma única escrita na janela de
   contenção";
   (c) um bloco morto/confuso de verificação na FASE 2 da sessão A, removido.
3. **Ponto cego da guarda por nome (achado estrutural):** a lista fechada de
   anti-antecipação de `15-validar-f5-09-p9.sql` filtra por **nome**
   (`%meta%`/`%goal%`); quatro helpers de aprovação **não casam** com o filtro
   (`f5_10_aprovador_congelado`, `f5_10_invalidar_aprovacoes_vigentes`,
   `f5_10_derivar_operation_id`, `f5_10_exigir_relacao_aprovador`) e por isso
   escapam dela. A P7 **não edita a guarda histórica** (fora do escopo) e passa a
   provar os quatro **individualmente** em §S15 — inclusive que seguem
   `SECURITY INVOKER` com `EXECUTE` só `service_role`.

## 6. Gates executados × não executados

**Executados neste host** (Docker 29.7.2 + Supabase local, PostgreSQL 17.6):

- **preflight obrigatório** (Issue #232), executado **antes** de qualquer
  implementação: Docker acessível (29.7.2), Supabase local acessível
  (PostgreSQL 17.6) e `db reset --local --yes` **exit 0**;
- **gate focado** da P7: `db reset` + `29` + `30` + `31/32/33` = **`falhas=0`**;
- **bateria SQL completa na ordem do CI** (inclui as regressões F5-06/F5-07):
  **46/46 entradas, `falhas=0`**;
- `npm run build` **exit 0**, `npm run lint` **exit 0**,
  `npx tsc -b tsconfig.app.json` **exit 0**, `git diff --cached --check`
  **exit 0**;
- `npm test`: **126 arquivos / 2060 testes PASS, 2 falhas** — **limitação de
  ambiente, não de escopo** (ver abaixo).

### `npm test` local: 2 falhas por CRLF do working copy Windows (limitação registrada)

```
src/pages/MinhasMetasPage.test.tsx:340  FAIL  toMatch(/await atualizarLista\(\);\n\s*return true;/)
src/pages/AcompanhamentoMetasPage.test.tsx:341  FAIL  toContain('relacaoAutorizaPapel(\n      meta.relacao,…')
Test Files  2 failed | 126 passed (128)     Tests  2 failed | 2060 passed (2062)
```

Causa-raiz **provada** (não presumida):

1. `git diff HEAD -- src/` está **vazio** — nenhum arquivo de `src/` difere do
   baseline `f53144f`. A P7 altera apenas 8 arquivos (1 doc, 1 workflow, 5
   validadores SQL e o handoff), **nenhum de `src/`**; logo as falhas são
   **pré-existentes e independentes** desta atividade.
2. `core.autocrlf = true` e **não existe `.gitattributes`** ⇒ no Windows o working
   copy é materializado com **CRLF** (`MinhasMetasPage.tsx`: 1426 CRLF, 0 LF solto).
3. As duas asserções comparam **texto-fonte** (`?raw`) com literais que contêm
   `\n`. Sonda objetiva executada nos mesmos arquivos:

   | Asserção | com CRLF (disco) | com LF (CI/Linux) |
   |---|---|---|
   | `MinhasMetasPage.test.tsx:340` | **FAIL** | **PASS** |
   | `AcompanhamentoMetasPage.test.tsx:341` | **FAIL** | **PASS** |
   | `AcompanhamentoMetasPage.test.tsx:347` | PASS | PASS |

4. O **CI roda em `ubuntu-latest`**, cujo checkout é **LF** ⇒ as mesmas asserções
   casam e o job fica verde.

**Não corrigido de propósito:** a correção exigiria editar dois arquivos de teste
**fora do inventário aprovado** da Issue #232 (que lista explicitamente "sem
manutenção oportunista") ou introduzir `.gitattributes`, mudança transversal de
repositório que **não** pertence a esta atividade. Fica registrado como
**findings para o owner** — alternativas: (a) `.gitattributes` com
`* text=auto eol=lf`; (b) tornar as asserções insensíveis a fim-de-linha
(`\r?\n` / normalizar a fonte antes de comparar).

**Não executados (e por quê):**

- **job `supabase-local` do CI no SHA exato:** os passos P7 foram adicionados ao
  workflow, mas o CI só roda **após o push** — a evidência local usa exatamente os
  mesmos arquivos e a mesma ordem;
- **auditoria GPT e auditoria independente Codex:** etapas externas do fluxo,
  posteriores a esta entrega.

## 7. Métricas DEV-02 / DEV-03

- **Batches privilegiados (elevações): 3** — (1) **P-0** preflight + criação da
  branch; (2) **P-1** gate focado (que rodou **2×**: a 1ª revelou os 3 defeitos de
  artefato descritos em §5 e a 2ª ficou verde, com causa-raiz analisada **antes**
  de cada correção); (3) **P-3** gate final (bateria completa + `npm` + commit).
  Nenhuma elevação foi usada para "tentativa às cegas".
- **Repetições justificadas:** o gate focado rodou 2× porque a 1ª execução produziu
  **três informações novas e independentes** (contagem da fixture, escopo do
  gatilho de marca, bloco morto). O full gate roda **1×** sobre o estado
  consolidado, conforme DEV-03.
- **Custo/usage:** o baseline informado na Issue é o **único dado observado**
  (US$ 62,82 acumulado / US$ 16,17 de saldo no início da P7). **Nenhuma métrica de
  consumo foi inferida** — as métricas "Last 7 days" são móveis e não representam o
  consumo isolado desta atividade.

## 8. Desvios e limitações declarados

1. **Referência documental quebrada (não criada artificialmente):**
   `docs/F5-10-P5.2-contrato-leitura-soberana-metas.md` cita
   `docs/F5-10-P6-lacuna-arquitetural-leitura-metas.md`, que **não existe em
   `main`** (viveu na branch `feat/f5-10-p6-cutover-metas`, commit `916b9d7`).
   Conforme a Issue, a referência é **registrada como desvio** e **nenhum artefato
   histórico é fabricado** para preenchê-la.
2. **Numeração dos validadores:** a Issue manda respeitar o inventário real. A P7
   usa `29`–`33` (o `27` permanece livre por salto histórico das fases P4/P5) e
   **não renumera** nenhum arquivo existente.
3. **`p_payload_hash`:** desvio já declarado em P2–P5 (hash derivado server-side).
   A P7 valida o `payload_hash` **gravado na trilha**, não um parâmetro de entrada.
4. **Fixture insert-once:** a trilha é append-only e as FKs são `RESTRICT` — não
   existe reset parcial. Cada rodada íntegra exige `db reset` (o CI faz isso).
5. **Ponto cego da guarda por nome (achado da P7):** a lista fechada de
   anti-antecipação (`15-validar-f5-09-p9.sql`) filtra por **nome**
   (`%meta%`/`%goal%`). Quatro helpers de aprovação — `f5_10_aprovador_congelado`,
   `f5_10_invalidar_aprovacoes_vigentes`, `f5_10_derivar_operation_id` e
   `f5_10_exigir_relacao_aprovador` — **não casam com o filtro** e por isso
   escapam da lista. A P7 **não altera** a guarda histórica (fora do escopo
   editá-la) e passa a provar esses quatro helpers **individualmente** em §S15.
6. **Gama-P7 é organização exclusiva da corrida:** qualquer escrita de outro
   arquivo ali faz `31`/`33` falharem com mensagem explícita — e a correção é
   reatribuir a organização, nunca afrouxar a prova.
7. **`p9MatrizIntegrada.test.ts` (guarda P9-2) NÃO precisou de ajuste:** o caminho
   soberano de **ciclos** não cita objetos de metas e a P7 não toca aquele código —
   verificado estaticamente. O §15 do desenho citava também `metaStorage.test.ts`,
   ajuste que ficou **obsoleto**: `metaStorage.ts` e seu teste foram **removidos na
   P6** (PR #228).
8. **`.ai/handoff.md` estava atrás da `main`:** a P5.2 (#222), a P5.3 (#226/#227) e a
   P6 (#220) foram integradas sem registro. A lacuna foi sanada na entrada **3.20**
   do handoff, conforme exigido pela Issue.
