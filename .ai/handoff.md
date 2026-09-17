# Virtus — Handoff (contexto operacional de retomada)

> Registro **operacional e estável** para retomada entre agentes/sessões.
> **Não copie** dados pessoais, segredos, credenciais, tokens, chaves ou
> informações corporativas sensíveis. Referencie Issues/PRs/documentos em vez de
> transcrever conteúdo. GitHub continua sendo a fonte de verdade do andamento.

## 1. Como retomar uma atividade interrompida

1. Leia `AGENTS.md` e `AGENTS.md` → `.ai/*` (ordem de `.ai/virtus-context.md`).
2. Leia **este arquivo** — seção 3 (registro de estado) — para saber onde a
   última entrega parou.
3. Confirme no GitHub (fonte de verdade) a Issue, o PR e o estado real da branch.
4. Em paralelo ao registro, verifique localmente com:

```bash
git status -sb        # branch atual, ahead/behind de origin
git log --oneline -3  # últimos commits locais
git diff --stat       # alterações não commitadas
```

5. Se um push falhou pela limitação conhecida (`.ai/git-rules.md`), o trabalho
   está **commitado localmente** e aguarda o usuário executar o push; não refaça
   e não tente contornar.

## 2. Instrução permanente de manutenção

A cada entrega (concluída ou interrompida), **atualize a seção 3** com o novo
estado e remova entradas obsoletas. Mantenha apenas contexto operacional:
branch, SHA, PR, atividade e próximos passos. **Nunca** adicione segredos,
credenciais, conteúdo real de pessoas/empresa ou trechos de documentos aqui.

## 3. Registro de estado (última entrega)

> Atualizar ao final de cada atividade.

### 3.28 F6-A09 — boot das Edges: specifier relativo sem extensão (Deno) — CORRIGIDO · PR/MERGE PENDENTES

- **Atividade/branch:** **F6-A09**, branch **`fix/f6-a09-edge-boot-extension`**, base
  **`main` = `098235979c668a2719e42f1845705f4a39b5dd39`**. Sem Issue/PR vinculados nesta sessão.
- **Defeito — o import exato:** `src/authorization/catalogoCapabilities.ts:1` era
  `import type { Capability } from "./Capability";` (**sem `.ts`**). O **Deno/Edge Runtime exige
  extensão explícita** em specifier relativo; Vite/Vitest/tsc toleram a omissão
  (`allowImportingTsExtensions: true`). Erro de runtime: `failed to create the graph: Failed
  resolving types. Relative import path ... not prefixed` ⇒ `503 {"code":"BOOT_ERROR"}`.
- **Correção mínima (1 linha de produto):** `"./Capability"` → `"./Capability.ts"`, alinhando o
  arquivo à convenção já usada por **todos** os vizinhos (`contextoAutorizacao.ts`,
  `estadoDominio*.ts`, `policyEngine/*`, `providers/reais.ts`; 157 imports relativos com `.ts`
  explícito em `src/`). Nenhum arquivo de `supabase/` foi tocado.
- **Alcance do MESMO padrão (varredura do grafo das 10 entries, 45 arquivos):** **exatamente 1**
  specifier relativo sem extensão (o defeito acima) e **0** imports relativos não resolvidos.
  Ele quebrava transitivamente **6 das 10** Edges: `colaboradores`, `metas`, `observacoes`,
  `ciclos`, `avaliacoes` e `contexto-autorizacao`.
- **Lacuna de gate fechada:** `src/authorization/ciclosEdgeImportGraph.test.ts` passou a coletar
  `semExtensao` em `percorrerGrafo()` e ganhou o `describe("F6-A09 — ...")` (3 casos): reprova
  qualquer specifier relativo sem `.ts`/`.tsx` em **qualquer** Edge, exige não-vacuidade do walk e
  trava o `"./Capability.ts"` do catálogo. Causa da cegueira do CI: `resolver()` tenta `${alvo}.ts`
  (resolve como o TypeScript) e o grafo continuava "íntegro" com o boot inválido para o Deno.
- **GATES (árvore final):** foco
  `npx vitest run src/authorization/{ciclos,metas,observacoes}EdgeImportGraph.test.ts` = **3
  arquivos / 26 testes, 0 falhas** (exit 0); **`npm test` = 3 falhas | 2392 passam (2395)** —
  **2 PRÉ-EXISTENTES Windows/CRLF** (`AcompanhamentoMetasPage.test.tsx`, `MinhasMetasPage.test.tsx`)
  + **1 AMBIENTAL** (`serviceColaboradores.test.ts:681`), provada por A/B: com as minhas alterações
  em `git stash` a falha **reproduz igual** (B1) e com `.env.local` **ausente** o arquivo **passa
  36/36** (B2) ⇒ **não** é regressão do F6-A09 (o CI ubuntu/LF não tem `.env.local`); `npm run build`
  **exit 0**; `npm run lint` **exit 0**; `git diff --check` **exit 0**; `git status --short` restrito
  aos **3 arquivos** previstos (2 de código/teste + este handoff).
- **RUNTIME verificado (edge-runtime 1.74.3 / Deno 2.1.4):** `POST` em
  `http://127.0.0.1:54321/functions/v1/<fn>` com o JWT do `.env.local` ⇒ **9 das 10 Edges bootam**
  e respondem com código próprio (`NOT_AUTHORIZED` 401 nas autenticadas, `INVALID_INPUT` 400 em
  `provisionar-organizacao`); antes da correção eram **6** em `BOOT_ERROR` 503.
- **BLOQUEIO REMANESCENTE — defeito DISTINTO e PRÉ-EXISTENTE (fora do escopo do F6-A09):**
  `supabase/functions/avaliacoes/assignedSupabase.ts:22` —
  `import type { SupabaseClient } from "@supabase/supabase-js"` (**bare specifier**, arquivo
  inalterado desde o **#176/F5-06**). Log do runtime: `Failed resolving types. Relative import path
  "@supabase/supabase-js" not prefixed with / or ./ or ../` ⇒ `avaliacoes` permanece `503
  BOOT_ERROR`. É **outra classe** de defeito (specifier nu, não extensão relativa) e envolve decisão
  própria (URL `https://esm.sh/@supabase/supabase-js@2` vs. import map) — **não** foi alterado aqui.
- **INCIDENTE DE AMBIENTE (registrado, não silenciado):** o container
  `supabase_edge_runtime_feedback-control` estava **órfão** (nenhum processo `functions serve`
  vivo; uptime reiniciando a cada poucos minutos) e **desapareceu após um `docker restart`** meu.
  Restaurei o serviço de funções com `npx supabase functions serve --env-file .env.f6-local`
  (**job em background desta sessão** — não sobrevive ao fim da sessão; reinicie se necessário).
  O `.env.local` foi preservado e usado apenas como bearer das sondas (valores nunca impressos).

### 3.27 F6-A04 — Entrada do Admin Virtus na superfície de plataforma (Issue #269) — IMPLEMENTADO · PR/MERGE PENDENTES

- **Atividade/branch:** **F6-A04** (Issue **#269**), branch **`feat/f6-a04-entrada-plataforma`**, base
  **`main` = `242cf26120fb367ed6e7b16d8730cc4775d2de85`** (desenho **aprovado e integrado**).
  Contrato normativo: `docs/F6-A04-desenho-tecnico.md` (§3.1/C1, D1–D5, critérios §6).
- **Entregue (6 arquivos, sendo 2 novos):** **`src/auth/EntradaPlataforma.tsx`** (novo) — componente
  **ÚNICO** com a sonda de UX já existente (`souOperadorDaPlataforma`, **D20**) e o `Link` para
  `ROTA_PLATAFORMA_NOVA_ORGANIZACAO`; o portão começa **fechado** (`useState(false)`), só abre com a
  sonda positiva e é **fail-closed** sem caminho soberano (`null`) e em qualquer falha; **não** decide
  autorização, **não** toca storage, **não** chama RPC e **não** carrega dado de tenant. **Call sites
  (4):** `src/auth/LoginPage.tsx` nos ramos **`acessoNegado`** (B1 — era beco sem saída) e
  **`autenticado`** (B2), `src/auth/AguardandoSelecao.tsx` (D5) e a **refatoração** de
  `src/auth/SemOrganizacao.tsx`, que deixou de ter o bloco inline. **Testes:**
  `src/auth/EntradaPlataforma.test.tsx` (novo — visibilidade `false`/`true`, portão fail-closed,
  barreiras estáticas e prova do **componente único** com ausência de sonda duplicada nos call sites)
  e um caso de regressão do ramo `acessoNegado` em `src/auth/roteamentoAutenticado.test.tsx`.
  **Nenhum** arquivo de `plataformaRotas.ts`, `LayoutPlataforma.tsx`, `AppRoutes.tsx`, Edge, RPC, SQL,
  CI ou navegação foi tocado (D2/D21 e critério 5 do contrato).
- **Mecanismo de sessão conferido (habilita o critério 1–3):** o cliente usado pela entrada é o de
  infraestrutura, que **lê a sessão persistida pelo cliente de Auth** (`persistSession: true`;
  `src/infrastructure/supabase/supabaseClient.ts:11-22` — fonte ÚNICA de sessão, F5-08 P4), portanto a
  chamada `functions.invoke` leva o **JWT do usuário** ao self-check da Edge.
- **GATES EXECUTADOS (árvore final):** **foco** `npx vitest run src/auth
  src/authorization/estruturaUiSeguranca.test.ts` = **52 arquivos / 1055 testes, 0 falhas** (exit 0);
  **`npm test` completo = 2 falhas | 2390 passam (2392)** — as 2 falhas são **PRÉ-EXISTENTES** de
  **Windows/CRLF** (`AcompanhamentoMetasPage.test.tsx` e `MinhasMetasPage.test.tsx`, `toMatch` sobre
  texto-fonte de páginas **não tocadas**; o CI ubuntu/LF é a autoridade); `npm run lint` **exit 0**;
  `npm run build` **exit 0**; `git diff --check` **exit 0**; `git status --short` restrito aos **6
  arquivos** previstos.
- **Limitação de verificação (registrada, não silenciada):** a jornada **ponta a ponta** (login →
  sessão → superfície) **não** foi executada neste workspace porque **não existe `.env.local`**
  (`VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` ausentes ⇒ `src/auth/cliente.ts:20-24` devolve `null`
  ⇒ estado `indisponivel` ⇒ a tela de login não renderiza formulário) — é o registro **R1/§3.3** do
  desenho (**pré-requisito operacional**, não defeito de código). A evidência possível neste ambiente
  é a de **testes de componente/render + leitura estática**, entregue acima; o projeto **não possui
  ambiente DOM**, então o estado pós-sonda é provado pela separação apresentação × portão e pela
  semântica fail-closed do próprio portão (coberta em `controladorProvisionamento.test.ts`).
- **Desvios do desenho (nenhum de contrato):** (i) o arquivo do componente expõe também
  `EntradaPlataformaVisivel` — sub-componente **puro** de apresentação, necessário para provar
  "oculta com `false` / visível com `true`" (critério 6) no tooling sem DOM; continua **um** arquivo,
  **uma** sonda e **um** link; (ii) foi acrescentado um caso de teste em
  `roteamentoAutenticado.test.tsx` ("testes correspondentes" do critério 5). Nada mais divergiu:
  D1–D5 e os critérios 1–5 do contrato foram seguidos.
- **Pendências:** `push` e abertura do PR pelo **orquestrador** (`.ai/git-rules.md` §3 — limitação do
  sandbox). **Nenhum merge** executado.

### 3.26 F6-A04 — Desenho do acesso do Admin Virtus à superfície de plataforma (Issue #269) — DESENHO ENTREGUE

- **Atividade:** F6-A04 (Issue **#269**), branch **`docs/f6-a04-login-plataforma-desenho`**, base
  **`main` = `ccf7948`** (F6-A03 **já integrada**, incluindo a correção do replay idempotente).
  **Exclusivamente documental**: zero código, SQL, CI ou teste alterado.
- **Artefato:** `docs/F6-A04-desenho-tecnico.md` (novo, curto) — percurso-alvo (login por e-mail/senha
  → sessão válida → `/plataforma/nova-organizacao`), auditoria com evidência arquivo:linha,
  **4 bloqueios**, a correção mínima, **D1–D5**, 4 ameaças, 7 critérios de aceite, registros
  **R1–R4** e **nenhuma dúvida bloqueante**.
- **Bloqueios demonstrados:** **B1** no estado `acessoNegado` (sessão válida **sem** `user_profiles`
  — o caso admissível do **D17** da F6-A03) a tela de login oferece **apenas "Sair"**
  (`src/auth/LoginPage.tsx:114-134`): o guard **admite** a rota (D19) mas **não há porta**;
  **B2** sessão válida **com** tenant (`autenticado`, `LoginPage.tsx:73-112`) e com N>1
  (`aguardandoSelecao` → `AguardandoSelecao.tsx:46-52`) também **não** têm entrada — a F6-A03 só
  ligou o link em `SemOrganizacao`; **B3** (pré-requisito de ambiente) sem
  `VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY` o cliente é `null` (`src/auth/cliente.ts:20-24`), o
  estado vira `indisponivel` e a tela **não renderiza formulário** (`LoginPage.tsx:45-59`) — **não
  existe `.env.local` neste workspace**; **B4** (raiz de confiança) o operador precisa existir no
  Auth com senha e estar na allowlist (`supabase/config.toml:63-66`; fixture sintética em
  `supabase/validacao/01-cenario-f2-10.sql`).
- **Correção desenhada (C1, mínima):** **um** componente `src/auth/EntradaPlataforma.tsx` com o
  self-check de UX já existente (`souOperadorDaPlataforma`, **D20**, fail-closed) + `Link` para
  `ROTA_PLATAFORMA_NOVA_ORGANIZACAO`, usado em **4 call sites** (ramos `acessoNegado` e
  `autenticado` do login — essenciais —, `aguardandoSelecao` e a refatoração de `SemOrganizacao`).
  **Nenhuma** rota, guard, Edge, RPC, RLS, grant, capability ou item de navegação novo.
- **Gates proporcionais (docs):** `git diff --check` **exit 0** e escopo conferido por
  `git status --short` (**apenas** `docs/F6-A04-desenho-tecnico.md` e este handoff). Nenhum gate de
  produto foi executado — nenhum artefato de runtime foi tocado, seguindo o precedente das
  atividades documentais (F6-01 e DEV-04).
- **Não verificável neste ambiente:** a jornada de ponta a ponta (exige `.env.local` + stack local +
  identidade sintética — §3.3 do documento) e o texto da Issue #269 (sem `gh`).
- **Pendências:** implementação em atividade posterior com contrato fechado; `push` e abertura do PR
  pelo **orquestrador** (`.ai/git-rules.md` §3 — limitação do sandbox; **nenhum** contorno).

### 3.25 F6-A03 — Implementação do bootstrap mínimo seguro do GREENFIELD (Issue #266) — INTEGRADA em `main` como `ccf7948`

- **Atividade/branch:** **F6-A03** (Issue **#266**), branch **`feat/f6-a03-bootstrap-greenfield`**,
  base **`main` = `453d16b0c7a143869065ef8f93f1bad9ab2c70b2`** (squash do **PR #267**, que fechou o
  desenho). Contrato normativo: **`docs/F6-A03-desenho-tecnico.md`** (D1–D21 e Q1–Q3 FECHADAS).
  **Nenhuma decisão foi reaberta e nenhum escopo foi ampliado** (sem portal SaaS, sem listagem de
  tenants, sem gestão de operadores/roles/planos/lifecycle).
- **Entregue (28 arquivos: 20 novos + 8 alterados).** **SQL:** migration
  `supabase/migrations/20260937000000_f6_a03_bootstrap_organizacao.sql` — tabela
  **`platform_provisioning_events`** (trilha append-only do plano de plataforma + âncora de
  idempotência: `unique (operation_id)`, `payload_hash` SHA-256, **sem FKs** pelo precedente do D18,
  RLS habilitado com **ZERO policy**, `service_role` **somente `SELECT`+`INSERT`**, UPDATE bloqueado
  por gatilho) e RPC **`organizacao_provisionar_inicial`** (`SECURITY INVOKER`, `search_path` fixo,
  `EXECUTE` só `service_role`, **sem DEFINER novo**; uma transação: organização com id do banco →
  `user_profiles` globais do **founder (D16)** e do **ator (D17)** → membership ativa → role `admin`
  **resolvida por nome** pelo primitivo `conceder_acesso_role` → trilha D18; idempotência por
  `operation_id` + `payload_hash` server-side com **um único** `insert … on conflict … do nothing
  returning` → replay devolve o mesmo `organization_id`, hash divergente recusa; **contenção por
  construção**: só cria tenant novo e vazio). **Edge:**
  `supabase/functions/provisionar-organizacao/{contrato,core,index}.ts` com as duas operações
  (`plataforma.provisionar_organizacao` e o self-check `plataforma.operador_atual`), allowlist de
  plataforma reutilizada (fail-closed), allowlist **estrita** de chaves, identidade soberana por
  `auth.getUser`, execução com `service_role` **sem o JWT do usuário**, e **compensação** do usuário
  criado no Auth quando a RPC falha; `[functions.provisionar-organizacao]` (`verify_jwt = true`) no
  `supabase/config.toml`. **Cliente:** `src/infrastructure/supabase/plataforma/{contrato,edgePlataforma}.ts`
  (adapter fail-closed nos 3 caminhos; código desconhecido ⇒ `INTERNAL`), porta
  `src/application/ports/ProvisionamentoPlataforma.ts` e
  `src/services/plataforma/{controladorProvisionamento,formularioPlataforma}.ts` (código público →
  taxonomia F0-05 com mensagem canônica). **UI mínima:** `src/pages/plataforma/NovaOrganizacaoPlataformaPage.tsx`
  (formulário com **dois** campos: nome + primeiro Admin "eu mesmo"/e-mail; confirmação exibe **só o
  nome** — nunca o UUID), guard puro `src/routes/plataformaRotas.ts`, `src/routes/LayoutPlataforma.tsx`
  (**fora** de `LayoutAutenticado`/`LayoutFuncional` — D19), rota registrada em `AppRoutes.tsx` e
  entrada condicional em `src/auth/SemOrganizacao.tsx`. **Validação/guardas:** `44-cenario-f6-a03.sql`
  + `45-validar-f6-a03.sql` (blocos A–G), 2 passos novos no `ci.yml`, guardas F4-08 atualizadas
  (`02-validar-f4-08.sql` → **52 tabelas / 29 fechadas** + D16; `03-validar-f4-08-mutacoes.sql` nas
  duas listas) e `supabase/migrations/README.md`. **Testes novos:** 112 casos em 7 arquivos
  (contrato, adapter, núcleo da Edge, controlador, guard, página/UI e o bloco novo de barreiras
  estáticas em `src/authorization/estruturaUiSeguranca.test.ts`).
- **CORREÇÃO PÓS-AUDITORIA (PR #268 — 1 bloqueante):** a auditoria apontou que, no caminho do
  primeiro Admin **por e-mail**, a Edge convidava no Auth **antes** de reconhecer o replay
  idempotente: repetir o mesmo `operation_id` após o primeiro sucesso encontrava o e-mail já
  existente e devolvia **`USER_EXISTS`** antes de chegar à RPC, quebrando a **idempotência ponta a
  ponta**. Correção LOCAL, **sem reabrir D1–D21 nem ampliar escopo**: (i) a Edge passou a consultar a
  âncora de idempotência (`platform_provisioning_events`, leitura por `service_role` — o `SELECT`
  concedido por D7/§6.4 ganhou seu consumidor) **antes de qualquer efeito colateral no Auth**, via a
  nova dependência `operacaoAplicada`; (ii) decisão pura e testável `reconhecerOperacaoAplicada` →
  `nenhum` | `replay` (delega o REPLAY à RPC, **fonte única**, com o founder da 1ª execução) |
  `divergente` (recusa `OPERATION_ALREADY_APPLIED`, sem convidar); a comparação do founder usa
  `auth.admin.getUserById` (lookup **direto por id**, sem listagem/enumeração) e e-mail ausente ⇒
  `divergente` (fail-closed); (iii) a RPC passou a resolver a **idempotência ANTES** da validação de
  estado do founder, na ordem do **§5** do contrato (`a`→`b`) — o REPLAY fica **ESTÁVEL** mesmo se o
  perfil do primeiro Admin for inativado depois, e operação NOVA com founder inativo segue
  fail-closed; (iv) **compensação best-effort** (`compensarFounder`/`deleteUser`): a falha dela
  **não** mascara mais o código público real (try/catch nos dois lados), tratada localmente **sem
  complexidade adicional** — o órfão fica sem perfil e sem membership (inacessível). **Teste novo
  exigido pela auditoria:** bloco “REPLAY REAL do caminho por e-mail” em
  `edgeProvisionamento.test.ts` (mesma intenção ⇒ **mesmo `organization_id` SEM novo convite**,
  ordem `consulta → provisão` provada; intenção divergente ⇒ `OPERATION_ALREADY_APPLIED` sem
  convidar) + bloco **E4** no validador `45` (replay estável com founder inativado). Nenhum grant,
  capability, role, policy ou policy de tabela mudou; `USER_EXISTS` para operação **NOVA** com
  e-mail existente permanece (limitação §13 F6 do contrato).
- **GATES EXECUTADOS (árvore final; Docker + CLI Supabase locais):** `npx supabase@2.116.0 db reset
  --local --yes` **exit 0**; **`01-cenario-f4-08` + `02-validar-f4-08` + `03-validar-f4-08-mutacoes`
  exit 0** (as guardas alteradas passam com a 52ª tabela classificada; **8 mutation tests** verdes);
  **`44-cenario-f6-a03` exit 0** e **`45-validar-f6-a03` exit 0** com os blocos **A/B/C/D/E/F/G**
  (preflight de RLS/ACL/DEFINER/catálogo 31/bundle 9; trilha invisível ao cliente e append-only;
  negativos fail-closed; caminho feliz com D16/D17 e **separação de planos**; idempotência
  replay/conflito; estado preexistente intocado + segunda organização; higiene); `npm run lint`
  **exit 0**; `npm run build` **exit 0**; `git diff --check` **exit 0**; **`npm test` = 2 falhas |
  2373 passam (2375)** — as 2 falhas são **PRÉ-EXISTENTES** e de **Windows/CRLF**
  (`AcompanhamentoMetasPage.test.tsx` 1/14 e `MinhasMetasPage.test.tsx` 1/14, ambas `toMatch` sobre
  **texto-fonte** de páginas **não tocadas**; confirmadas em execução focada) — o CI (ubuntu/LF) é a
  autoridade. **Gate focado da atividade: 112/112 verdes.**
- **Divergências/observações REGISTRADAS (nenhuma decisão reaberta):** (i) o §6.1 do contrato fixa as
  chaves transportáveis e **não** diz de onde a UI obtém a identidade do próprio operador para "eu
  mesmo" — implementado por `identidadeDoOperadorAutenticado()` (lê a **sessão local**,
  `cliente.auth.getSession()`), que **não é autoridade** (a Edge re-deriva o ator do JWT) e viaja no
  campo já contratado `founder_user_id`; (ii) arquivo adicional
  `src/services/plataforma/formularioPlataforma.ts` (conversão pura formulário→intenção) para manter o
  módulo React exportando **somente componentes** (regra `react-refresh/only-export-components`);
  (iii) o estado "ambiente sem caminho soberano" passou a ser **derivado** (ausência de controlador)
  em vez de estado, pela regra `react-hooks/set-state-in-effect` — comportamento fail-closed
  equivalente; (iv) **defeito próprio corrigido antes do gate**: a guarda de `search_path` usava
  `position('search_path=public' …)` sobre `pg_get_functiondef`, que renderiza `SET search_path TO
  'public'` — corrigida na migration **e** no validador `45`.
- **Limitação de ambiente registrada:** no início da atividade **não** havia engine Docker nem CLI
  Supabase (o `npx` era negado ao escrever no cache do npm); o engine foi aberto pelo responsável e
  o gate SQL rodou com `npx --yes supabase@2.116.0` + `docker exec` no container
  `supabase_db_feedback-control`. O **`push` continua bloqueado** pelo `askpass` do VS Code
  (`.ai/git-rules.md` §3) — commit local entregue com branch/SHA; **PR a abrir pelo orquestrador**
  (DEV-04), **sem merge**.

### 3.24 F6-A03 — Desenho do bootstrap mínimo seguro do GREENFIELD (Issue #266 / PR #267) — DESENHO ENTREGUE · Q1–Q3 FECHADAS (A) · UI MÍNIMA NO ESCOPO

- **Atividade:** **F6-A03** (Issue **#266**), branch **`docs/f6-a03-bootstrap-greenfield-desenho`**,
  base `main` = `52348dd`. **Atividade exclusivamente documental**: **zero** migration, RPC, Edge,
  capability, role, policy, RLS, grant, página, teste ou workflow de CI criados/alterados.
- **Artefato:** `docs/F6-A03-desenho-tecnico.md` (novo) — objetivo/não-escopo, estado atual auditado
  com evidência arquivo:linha, **5 bloqueios** (B1–B5) do GREENFIELD, separação explícita dos planos,
  fluxo mínimo **com a jornada de produto**, contratos propostos (Edge + RPC + **UI mínima** +
  self-check), componentes reutilizados × novos, guardas impactadas, critérios de aceite,
  **18 ameaças**, **21 decisões fechadas (D1–D21)** e **Q1–Q3 FECHADAS (alternativa A)**.
- **Bloqueios demonstrados (o GREENFIELD não é executável hoje):** **B1** não existe caminho
  autorizado para criar organização (RLS + zero policies + `revoke all` e regrant só `SELECT` em
  `organizations`; **nenhuma** RPC insere em `organizations` nas 62 migrations; organizações só
  nascem por fixture em `supabase/validacao/*`); **B2** o primeiro `admin` é inalcançável
  (`usuario_eh_administrador` exige atribuição ativa de `admin` ⇒ circular; `conceder_acesso_role_rpc`
  proíbe auto-concessão; o primitivo `conceder_acesso_role` não é exposto por nenhum caminho
  server-side); **B3** o convite cria perfil + membership e **nenhuma** role (o convidado entra com
  zero capabilities); **B4** não há superfície de produto para atribuir role (nenhum módulo do
  cliente invoca `gerenciar-access-role`, e `[functions.gerenciar-access-role]` **não** está
  declarado em `supabase/config.toml`); **B5** a superfície de produto **não é alcançável no
  ambiente virgem**: o molde `/convidar-usuario` vive sob `LayoutAutenticado`→`LayoutFuncional` e o
  formulário devolve `null` fora do estado `autenticado` — sem perfil o estado é `acessoNegado` e
  sem membership é `semOrganizacao`, exatamente as condições em que o bootstrap é necessário
  (⇒ **D19**). **B4 permanece** após esta atividade (a UI mínima só concede `admin` no bootstrap).
- **Q1–Q3 FECHADAS na alternativa A (registradas em D14–D17):** **Q1/D14** a autoridade de plataforma
  permanece na **allowlist do ambiente** (não se cria tabela `platform_operators` nesta atividade);
  **Q2/D15** o operador **pode** ser o próprio primeiro Admin (auto-bootstrap), sustentado pela
  contenção por construção; **Q3/D16** a transação **cria o `user_profiles` do founder** quando
  ausente — e, por consequência forçada (**D17**, derivada), também o do **ator**: a FK de
  `created_by` de `conceder_acesso_role` quebraria sem ele, e autor sintético/`system_grant`
  **falsificaria** a autoria que D18/P5.1 protegem. As alternativas **B** ficam registradas **apenas
  como reversão** (§13 F10).
- **Ajuste de escopo incorporado (D18–D21):** a solução **inclui a UI mínima de plataforma** —
  rota `/plataforma/nova-organizacao` **fora** de `LayoutAutenticado`/`LayoutFuncional` (**D19**),
  guard de plataforma que admite `semOrganizacao`/`acessoNegado`, página com **dois** campos
  (nome da organização + primeiro Admin: "eu mesmo" ou e-mail), **self-check de UX**
  `plataforma.operador_atual` (**D20**, UX e nunca autoridade; negativa neutra) e **escopo fechado**
  (**D21**: só organização + role `admin`; sem portal SaaS, sem listar tenants, sem gerir
  roles/operadores/planos/lifecycle).
- **Separação entregue:** **autoridade de plataforma** (allowlist do ambiente + `auth.getUser` +
  perfil ativo — confere **zero** capabilities/roles/membership; **não** é representável em
  `capabilities`/`access_roles`/assignments) × **role `admin` do tenant** (`access_role` de sistema
  validada por `usuario_eh_administrador`, `20260934000000:37-62`); nenhuma das duas implica a
  outra. Coerente com F4-01 D9/D16/D17, F5-03 §5.5, F5-04 D15/D16 e F5-11 P5.2 (nenhuma decisão
  fechada reaberta).
- **Núcleo técnico proposto:** Edge `provisionar-organizacao` (trio `index`/`core`/contrato, allowlist
  **estrita** de chaves, `verify_jwt = true`) + RPC `organizacao_provisionar_inicial` (**um**
  `SECURITY INVOKER`, `search_path` fixo, `EXECUTE` só `service_role`, **sem DEFINER novo** — a
  guarda F4-08 exige exatamente 4) com transação única e **idempotência por replay verificado**
  (`operation_id` + `payload_hash` server-side, um único `insert ... on conflict ... returning`,
  **sem advisory lock** — molde F5-11 P5.4); **contenção por construção** (só cria tenant novo e
  vazio, nunca toca estado pré-existente) e reuso do primitivo `conceder_acesso_role` + trilha D18
  `privilege_mutation_audit`. **Uma** tabela nova (`platform_provisioning_events`: RLS + zero
  policies, `service_role` só `SELECT`/`INSERT`, append-only).
- **Não verificado neste ambiente (registrado, não silenciado):** o texto da **Issue #266** (sem
  `gh`) — escopo derivado do enunciado da atividade; execução de `db reset`, Docker e CI (sem
  shell); e a descoberta automática da Edge `gerenciar-access-role` sem declaração no `config.toml`
  (**F1** do documento, registrado como **verificação pendente**, não como defeito afirmado).
- **Pendências:** implementação (atividade posterior, só com contrato fechado: migration + RPC, Edge,
  **UI mínima + guard**, validadores `44`/`45` e 2 passos de CI). **Nenhuma dúvida permanece
  aberta** — o desenho está **fechado para implementação**. `push`/PR/merge ficam com o
  **orquestrador** (DEV-04: `gh` ausente e `push` falhando por `askpass` do VS Code; **nenhum**
  contorno com PAT).

### 3.23 F5-11 — Observações soberanas e histórico auditável — P1/P1.1/P2/P3/P4/P5/P5.1–P5.4 IMPLEMENTADAS · CERTIFICADA (Issue #254) · PR/MERGE PENDENTES

- **FECHAMENTO/CERTIFICAÇÃO (Issue #254) — artefato novo `docs/F5-11-certificacao.md`:** auditoria dos critérios de aceite do §17.1 (P1–P6) contra evidência arquivo:linha, cobrindo também a família **P5.1–P5.4** (SELF/read automático com o 5º system role `observacoes_avaliado`; autoridade administrativa por role; lifecycle de `user_profiles.status`; exclusividade automática e ausência de corrida no primeiro provisionamento). **Nenhuma lacuna MATERIAL BLOQUEANTE** foi encontrada. Dívidas **não bloqueantes** (com evidência no artefato, §4): prova literal de transferência entre organizações no validador da P5.1; defeito latente de **diagnóstico** (`v_falhas || 'literal'` em `text[]`) em `41-validar-f5-11-p3.sql`; `42-cenario-f5-11-p5-1.sql` ainda derivando organização/ciclo do tenant da P2; resíduo morto do domínio de ciclos. **Fora de escopo:** as 2 falhas pré-existentes de Windows/CRLF (F5-10) e a fidelidade do harness local aos pares de concorrência. **Não verificável neste ambiente:** texto das Issues #238/#254 (sem `gh`) — critérios extraídos do desenho técnico — e o SHA/base auditados (sem shell).
- **ETAPA 5 — CERTIFICAÇÃO TRANSVERSAL (Issue #256) — artefato novo `docs/etapa-5-certificacao.md`:** auditoria **somente documental** (nenhum código/migration/RPC/role/capability/teste novo), com **reutilização** das certificações e gates já registrados. Obrigações levantadas do roadmap e dos documentos do repositório (`docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md` §3/§4, `docs/auditorias/auditoria-f5-09-preparacao-p5-p9.md` §4, §20 do `docs/F5-07-desenho-tecnico.md` e critérios §17.1 de cada fase); a **Issue #256 é ilegível** neste ambiente (sem `gh`). **A Issue #256 É a própria F5-12:** a validação integrada e o fechamento formal da Etapa 5 **são esta entrega** (não há fase posterior de fechamento). Resultado: os **três BLOCKERS históricos estão demonstradamente resolvidos** (ciclos → F5-09; colaboradores/histórico → F5-07/F5-08; metas/observações → F5-10/F5-11) e as **obrigações transversais** (trust boundaries, D1–D22, RLS/policies, ACL/grants, auditoria append-only, idempotência/concorrência, multi-tenant/IDOR, fail-closed, guardas de UI, CI completo, coerência promessa × prova) têm evidência citável. **NÃO há lacuna material bloqueante agora.** **R1 — FECHADO nesta entrega** (prova na tabela do §1.3): auditoria estática de cada leitor legado de ciclo (`cicloEquipeService`, `historicoOrganizacionalStorage`, `permissaoAvaliacao`, `cancelamentoCicloService`, `reaberturaCicloService`, `relatorioService`, `localCycleRepository` e as páginas que importam `cicloAvaliacaoStorage`) mostrou que **nenhum deles é AUTORIDADE de decisão de autorização/segurança**; `permissaoAvaliacao.ts` **não tem consumidor de produção** (importado só por testes) e a autoridade é server-side (Policy Engine do servidor + RLS + RPC). Ressalva material registrada: em `EditarFeedbackPage`, `FeedbackDetalhePage` e `NovoFeedbackPage` o ciclo **local** entra como **insumo** do gate de UI (`can()`/pré-voo `authorize()` do cliente, via `resource.cycle.status` em `authorizationPolicy.ts`) — **duplicação de autoridade em nível de UX, em que o soberano prevalece** (efeito possível: divergência de apresentação; nunca concessão indevida). **Dívidas não bloqueantes aceitas nesta entrega (R2–R6):** `localCycleRepository` LEGADO declarado; fixtures que pré-carregam chaves legadas; prova literal de transferência entre organizações; defeito latente de diagnóstico no `41-validar-f5-11-p3.sql`; cenário `42` derivando tenant da P2 — mais a limpeza do resíduo de apresentação do R1 (backlog). **Fora de escopo:** as 2 falhas pré-existentes de Windows/CRLF, a importação do acervo legado e o hardening/redesign de F6. **Gates locais executados (orquestrador):** invariantes de fronteira, `git diff --check` exit 0, `npm test` **2301/2303** (apenas as 2 PRÉ-EXISTENTES de Windows/CRLF), `npm run build` exit 0, `npm run lint` exit 0 — o pipeline CI-equivalente (56/56) e a cadeia de banco (34…43, 10/10) já estão certificados na base idêntica desta branch e não foram repetidos por não acrescentarem informação nova. **CI OFICIAL DO PR/SHA PENDENTE (orquestrador)** — autoridade final, especialmente dos pares de concorrência.
- **F5-11 — GATES LOCAIS EXECUTADOS (orquestrador, com shell):** `supabase db reset --local --yes` + cadeia `34…43` **10/10 verdes** (34:1, 35:11, 36:1, 37:8, 38:1, 39:7, 40:3, 41:4, 42:2, 43:1); pipeline CI-equivalente completo **56/56 steps VERDES** (ordem exata do CI, incluindo a reaplicação da migration D28 ×2 e os **dois pares de concorrência reais** — sessões A/B com `A=5/B=5` e `A=5/B=4`); `git diff --check` **exit 0**; `npm test` **2301/2303**, com **apenas as 2 falhas PRÉ-EXISTENTES** de Windows/CRLF (`AcompanhamentoMetasPage.test.tsx`, `MinhasMetasPage.test.tsx`); `npm run build` **exit 0**; `npm run lint` **exit 0**. Registro honesto: houve **duas execuções** do pipeline — a primeira parou num *flake do harness local* no par 16/17 (sessão B mediu **1,954 s** de espera contra o limiar de 2 s) e a segunda fechou **56/56**; a árvore é a mesma. **CI OFICIAL DO PR/SHA PENDENTE (orquestrador)** — é a autoridade para os pares de concorrência e nenhum resultado de CI é afirmado aqui.

- **Atividade-mãe:** **F5-11** — Issue **#238**. **P0** (desenho) entregue na branch
  `docs/f5-11-observacoes-soberanas-desenho`, base `main` = `5889decb81d4dc3feca15ca15d37f164e2f614ea`;
  PR **#239**; **integrado** em `main` como `6d527cc418f20e3fb60f0d25ad23f1013dcb17b4`.
  A **P1** (Issue **#240**) foi **integrada** em `main` como
  `0fe76193a408c857cc006707c28cb32d8c1d03c2`. **A #238 permanece aberta** até a P6.
- **P1.1 — issue que a governa:** **Issue #242** (`F5-11/P1.1 — Correção do finding Codex`), mãe
  **#238**. Branch: **`fix/f5-11-p1-1-coerencia-identidade`**, base `0fe76193a408c857cc006707c28cb32d8c1d03c2`.
- **P1.1 — o que corrigiu (finding MEDIUM do Codex na P1):** as FKs provavam perfil existente e
  membership no tenant, mas **não** que a membership é do **perfil** informado ⇒ numa organização com
  perfil A→membership A e perfil B→membership B, uma escrita técnica podia gravar
  `author_user_profile_id = A` com `author_membership_id = B`. **Correção estrutural ADITIVA**
  (migration `20260930000000_f5_11_p1_1_coerencia_identidade_observacoes.sql`; a migration da P1
  **não** é editada retroativamente), na doutrina do precedente `20260922000000_f5_10_p1_goals_schema.sql:355-419`:
  **2 funções `SECURITY INVOKER`** (`search_path = public`) + **2 gatilhos `BEFORE ROW`** cobrindo os
  **4 pares** (`author_*`, `comunicado_por_*`, `excluida_por_*` na linha; `actor_*` na trilha) e a
  coerência de **`author_collaborator_id`** com o **vínculo ATIVO** da membership. **Por que trigger e
  não FK:** exigiria chave candidata **nova** em `user_organization_memberships (id, user_profile_id)`
  (só possui `(id, organization_id)`) e em `membership_collaborator_links` (só possui
  `unique (membership_id)`) — criar chave nova seria alterar **contrato fechado** de outra fase.
  **Classes de erro preservadas:** ausência → 23502/23514; inexistente **ou cross-tenant** → 23503
  (todo lookup é filtrado por `organization_id`); existente **incoerente** → **P0001**.
- **P1.1 — `author_collaborator_id` (regra determinada, não inventada):** o modelo canônico é
  **`public.resolver_collaborador_vinculado(profile, org)`** (F5-02, hardening `20260909000000`), que exige
  **cumulativamente** perfil **ATIVO** (`user_profiles.status = 'active'`), membership **ATIVA**
  (`user_organization_memberships.status = 'active'`) e vínculo **ATIVO**
  (`membership_collaborator_links.status = 'active'`; vínculo `disabled` é histórico e **não** resolve).
  O gatilho impõe **exatamente** essa paridade **integral**; valor **nulo** segue legítimo (ator sem
  vínculo).
- **P1.1 — fixtures/validadores:** **`34` foi enriquecido** com os 2 vínculos membership↔colaborador
  (sem eles as observações da própria fixture seriam incoerentes com o D3) — por isso a evidência de
  **34/35 foi reexecutada e segue verde** (`34` 1 PASS, `35` 11 PASS); **`36-cenario-f5-11-p1-1.sql`**
  cria **UMA** organização com **5 identidades na MESMA organização** (A e B com perfil e membership
  ativos e vínculo ativo; C com vínculo **`disabled`**; **D com membership `disabled` e vínculo ATIVO**
  — a metade ausente do *finding*; **E com perfil `disabled`**) e **`37-validar-f5-11-p1-1.sql`**
  (blocos A–H, **8 PASS**) prova: paridade **integral** com o resolvedor (B, inclusive B4/B5),
  **negativos intra-tenant dos 4 pares** (C), negativos de `author_collaborator_id` incluindo vínculo,
  **membership** e **perfil** `disabled` (D4/D5/D6), negativos no **UPDATE** com verificação da
  **mensagem** do mecanismo (E), **positivos** (F), separação de classes de erro + D4/D6/D9 intactos (G)
  e higiene (H).
- **P1.1 — defeitos encontrados na própria execução (registrados):** (1) `text[] || '<literal com
  vírgula>'` é resolvido como concatenação de **arrays** (22P02) — corrigido com cast `::text` nas 10
  ocorrências da P1.1; (2) o resolvedor chama-se **`resolver_collaborador_vinculado`** (a **tabela** usa
  "collaborator", a **função** usa "colaborador") — grafia fixada por **igualdade de md5** com o banco
  (`a7539481ed2bbe7e8003cd2febef8d18`); (3) **não corrigido por estar fora do escopo**: o padrão (1)
  é **pré-existente** em `20260922000000:68,76,794`, `20260929000000:89,97` e `02-validar-f5-09.sql:1257-1266`
  — nesses pontos o guard **continua fail-closed**, mas abortaria com `22P02` em vez da mensagem
  diagnóstica. Registrado em `docs/F5-11-desenho-tecnico.md` §19.7.
- **P1.1 — correção PRÉ-MERGE (auditoria Codex do PR #243: REPROVADO com 1 finding MEDIUM):** a
  verificação de `author_collaborator_id` exigia só o **vínculo** ativo e **aceitava** `membership
  disabled + link active`, combinação que o resolvedor soberano **não** reconhece. Corrigida **antes do
  merge**, na **mesma** migration (ainda não versionada no PR aberto ⇒ editada no lugar, sem migration
  nova), repetindo o **join integral do resolvedor**; a fixture `36` ganhou **D** e **E** e o validador
  `37` ganhou **B4/B5**, **D4/D5/D6**. Registrado em `docs/F5-11-desenho-tecnico.md` §19.8. **Nenhum**
  outro item do escopo foi alterado; a dívida pré-existente `22P02` **não** foi tocada.
- **P2 — registro completo (Issue #244):** os bullets acima foram consolidados na entrega da P2.
- **P3 — DESVIO DE PROCESSO REGISTRADO (não ocultado):** a implementação da P3 **começou antes de
  existir a Issue da fase**. Este host **não** cria Issue (`gh` ausente e nenhuma API autorizada;
  nenhum workaround com PAT/credencial foi usado, conforme AGENTS.md/DEV-04). A Issue **#246**
  (`F5-11/P3 — autorização + capabilities/concessões + scope soberano`) foi criada **depois** pelo
  orquestrador, que **regularizou** a rastreabilidade Issue-antes-do-código e **fechou a D15**; a
  partir daí **todos** os artefatos da P3 referenciam **#246** (migration, validadores 40/41, docs
  §21, `README` de migrations e `ci.yml`). Branch
  **`feat/f5-11-p3-autorizacao-observacoes`**, base `0f7bcf625052ad3c07113962cfd8997cffb9245b`.
- **P3 — decisão D15 (registrada no §8 do desenho ANTES do código):** perfil de sistema funcional
  **`observacoes_gestor`** com **EXATAMENTE** `observation.read/create/edit/delete` e scope
  `DIRECT_REPORTS`/`DESCENDANTS`; `admin` **zero** `observation.*`; `metas_*` exclusivas de metas;
  `observation.write` deprecada; **SELF** e **ORGANIZATION** fora do bundle padrão; custom roles
  seguem possíveis pelo mecanismo soberano.
- **P3 — o que entregou:** migration `20260932000000_f5_11_p3_authorization_observacoes.sql` com o
  perfil e com o **scope como enforcement REAL** (gate e RPC de listagem reescritos por
  `create or replace`, sem editar a migration da P2): ALLOW exige **capability + scope
  (`resolver_capabilities_escopos_efetivas`) + relação + autoria/estado**. Fixtures/validadores
  novos: `40-cenario-f5-11-p3.sql` (prefixo `f5b3`, descendente + 5 assignments com scopes distintos,
  incluindo um **sem** scope) e `41-validar-f5-11-p3.sql` (A–L). Guards de `15`/`30`/`35`/`37`/`39`
  **invertidas explicitamente**; `ci.yml` com as duas etapas da P3.
- **P3 — cliente (Policy Engine):** `observation` soberano (lista de tipos não-soberanos **vazia**),
  UUID canônico, fonte única `estadoDominioObservacao`, espelho de **D5** e probe **fail-closed** na
  fronteira até o loader soberano existir (P4). 4 arquivos em `src/authorization/`.
- **P3 — evidência:** gate focado e bateria completa na ordem do CI (contagens no relatório).
  **P4/P5/P6 não iniciadas** — naquele momento; **atualização P4:** a P4 foi implementada depois (ver
  bloco P4 nesta seção).
- **P4 — issue que a governa:** **Issue #248** (`F5-11/P4 — loader soberano Edge/cliente para
  observações`), mãe **#238**. Branch **`feat/f5-11-p4-edge-observacoes`**, base
  `83fb225213501c360660c2968c31f577a8a75373` (squash da P3 em `main`). **PR PENDENTE** — este host não
  abre PR (DEV-04: `gh` ausente e nenhuma API autorizada; nenhum workaround com PAT/credencial).
- **P4 — o que entregou:** Edge **`observacoes`** (trio
  `supabase/functions/observacoes/{index,core,contrato}.ts`: `core.ts` é o núcleo testável com
  dependências injetadas, sem APIs de runtime, e `contrato.ts` apenas **reexporta**
  `src/infrastructure/supabase/observacoes/contrato.ts`, molde `supabase/functions/metas/contrato.ts`) e
  `[functions.observacoes]` em `supabase/config.toml` (`verify_jwt = true`,
  `entrypoint = "./functions/observacoes/index.ts"`).
- **P4 — contrato transportável único:** `src/infrastructure/supabase/observacoes/contrato.ts` com as **8
  operações** `observacao.*`, `DEFINICAO_POR_OPERACAO` (gate/capability, sem fallback),
  `RPC_POR_OPERACAO` em paridade **1:1** com as RPCs `observacao_*` da P2, `CHAVES_POR_OPERACAO` e
  `validarEntradaObservacao`; **nenhuma** cópia de operações/gates/capabilities/forma na Edge.
- **P4 — adapter fail-closed:** `src/infrastructure/supabase/observacoes/edgeObservacoes.ts` chama
  `functions.invoke("observacoes")` e devolve o `resultado` **bruto** da RPC; cobre os **três** caminhos
  (`error`, `data.error` e `data.ok !== true`/ausência da chave `resultado`, com `resultado: null` aceito
  como sucesso); código público desconhecido ⇒ `FORBIDDEN`; **sem** `.rpc(`, **sem** `SERVICE_ROLE_KEY`,
  **sem** `localStorage`/fallback.
- **P4 — gate por operação:** **7 funcionais** (`criar` com alvo funcional = **colaborador-ALVO** — a
  observação ainda não existe, molde `goal.criar`; `editar`/`definir_comunicado`/`excluir`/`revogar`/
  `obter`/`historico` com alvo `{type:"observation", id}`) e **`observacao.listar_por_escopo`
  ADMINISTRATIVA** (`observation.read`; §8 linha 1 + molde F5-10 `goal.listar_por_escopo`): a listagem não
  tem alvo único autorizável e o escopo/relação são decididos pela RPC. **Correção dentro da fase:** o
  contrato nasceu com a listagem **funcional** (exigiria UUID inexistente ⇒ `INVALID_INPUT`, matando a
  listagem) e foi corrigido antes do congelamento.
- **P4 — allowlist estrita e instante soberano:** `CHAVES_COMUNS = {organization_id, operacao,
  operation_id}` + chaves por operação; **nunca** transportáveis autoria/tenant/estado/`capability`/
  `scope`/`version`/`domainState`/`payload_hash`; `cycle_id`/`collaborator_id` só na **criação** (D4);
  `expected_version` só nas 4 mutações de linha existente; `motivo` só em `excluir`/`revogar`; **`data`
  não é transportável em nenhuma operação** (D21: o F4-02 resolve escopos "na data" e o instante da
  decisão é soberano, nunca declarado pelo chamador).
- **P4 — loader/fronteira:** `src/authorization/estadoDominioObservacao.ts` (novo módulo **Edge-safe** com
  a matriz + `exigeAutoriaObservacao`, dependendo só de tipos do Policy Engine, molde
  `estadoDominioMeta.ts`/`estadoDominioCiclo.ts`); `authorizationPolicy.ts` passou a **importar e
  reexportar** (`estadoDominioObservacao`, `EstadoObservacaoSoberano`) — superfície pública da P3
  preservada. **Motivo:** `authorizationPolicy.ts` importa `config/ambiente` (`import.meta.env` no topo) e
  `colaboradorStorage`/localStorage, e `contextoAutorizacao.ts` está no grafo das Edge Functions
  (`avaliacoes`, `ciclos`, `colaboradores`, `metas`, `observacoes`) — arrastá-los quebraria o boot Deno.
- **P4 — probe soberano e criação:** em `contextoAutorizacao.ts` o placeholder **fail-closed** da P3 foi
  substituído pelo probe derivado da **linha soberana** (`comunicado`/`excluida`/`cicloStatus`/
  `colaboradorStatus`/`author_collaborator_id` × vínculo do ator) composto com D5 e com a leitura
  SELF-comunicada; **ramo novo de CRIAÇÃO** (`observation.create` + alvo `collaborator`, §8 linha 4) com
  **SELF = DENY** (invariante 4) e **status não resolvido ⇒ DENY** (D11), usando dois campos **opcionais**
  novos em `ContextoAvaliacaoSoberano` (`colaboradorStatus`, `cicloStatus`) fornecidos pelo loader da Edge.
- **P4 — provider (`reais.ts`):** `alvoObservacaoCorresponde` + `observacaoNoEscopoDoAtor` (**SELF** = o
  ator é o colaborador-alvo, via `donoDoAlvo`; **DIRECT_REPORTS**/**DESCENDANTS** = alvo ∈ escopos
  resolvidos; sem `donoDoAlvo` ⇒ DENY; o id da observação nunca define relação). **Necessário** porque
  `contextoAutorizacao.ts` monta os providers com `criarProvidersReais`: sem esse ramo o gate negaria por
  scope e **nenhum ALLOW real** seria alcançável (§17.1/P4).
- **P4 — testes da fase:** `src/authorization/observacoesEdgeImportGraph.test.ts`,
  `src/authorization/observacoesContratoRpc.test.ts`,
  `src/authorization/observacaoRecursoSoberano.test.ts`,
  `src/infrastructure/supabase/observacoes/contrato.test.ts` e
  `src/infrastructure/supabase/observacoes/edgeObservacoes.test.ts`.
- **P4 — dívidas declaradas (para P5/P6):** (i) **autoria como relação no provider** não é resolvida (não
  há análogo a `metaDoAlvo`): um autor fora do escopo "na data" pode ser negado pelo engine onde o SQL
  permitiria — divergência **fail-closed** (nunca permissiva); corrigir exige campo novo em
  `ResourceContext`/`DadosProvidersReais`; (ii) **quem concede `observation.read` ao avaliado (SELF) segue
  decisão da P5** (a P3 entregou só `observacoes_gestor` com `DIRECT_REPORTS`/`DESCENDANTS`); (iii)
  `localStorage`/cutover de UI (P5) e certificação (P6) **não iniciados** — *naquele momento*: a P5 foi
  implementada na sequência e a P6 segue pendente (ver o bloco **P5** abaixo); nenhuma migração de
  `localStorage` (D13); (iv) SQL da P1/P2/P3 **intocado** nesta fase (nenhuma migration nova).
- **P4 — GATES EXECUTADOS (orquestrador, gate privilegiado agrupado):** `git diff --check` exit 0; `npm test` com 2184 de 2186 testes passando e **apenas as 2 falhas PRÉ-EXISTENTES** de Windows/CRLF (`AcompanhamentoMetasPage.test.tsx`, `MinhasMetasPage.test.tsx`) — nenhuma falha nova; `npm run build` exit 0; `npm run lint` exit 0; invariantes de fronteira conferidos (`.rpc(` = 0 e `SERVICE_ROLE_KEY` = 0 nos módulos de cliente, trio Edge presente). Commit **`df3defe1422d6227e41478552dd07152c433f87a`** (19 arquivos, +5597/-85) publicado em **`feat/f5-11-p4-edge-observacoes`** (`push` exit 0), base `83fb225213501c360660c2968c31f577a8a75373`. **Sem merge** — PR a abrir pelo orquestrador (DEV-04; `gh` ausente no ambiente). Correções autônomas dentro da fase: contrato (`observacao.listar_por_escopo` passou a GATE ADMINISTRATIVO conforme §8 linha 1 / molde F5-10 e `data` saiu da allowlist por D21), ramo de relação do alvo `observation` em `providers/reais.ts` e probe de criação (§8 linha 4) — todos com testes discriminantes próprios.
- **P5 — cutover soberano da UI (Issue #250):** branch **`feat/f5-11-p5-cutover-observacoes`**, base
  **`8e88e3752b9ea3467a94c53fdd58b5eca9b92edc`** (= HEAD de `main` = squash da P4), mãe **#238**. **PR a
  abrir pelo orquestrador** (DEV-04; `gh` ausente no ambiente). **SQL intocado** nesta fase (nenhuma
  migration, RPC, RLS ou ACL) e **nenhuma migração de dados de `localStorage`** (D13); P6 não antecipada
  e `D1–D16/D21/D22` não reabertas.
- **Autoridade preservada:** funil `UI → porta → adapter da P4 → Edge → RPC`. O browser não declara
  tenant, autoria, estado, versão, capability nem instante: o `expected_version` vem da **leitura
  soberana** e o `operation_id` é a única chave de idempotência. O **gate de UI legado foi REMOVIDO** do
  painel (decidia com alvo/contexto **fabricados** no browser — não era autorização efetiva): a tela
  renderiza o resultado soberano e a mutação negada exibe o código público (fail-closed).
- **Porta soberana e repositório:** `src/application/ports/ObservationRepository.ts`,
  `src/infrastructure/supabase/observacoes/repositorioObservacoesSoberanas.ts` (implementado **só** sobre
  `criarEdgeObservacoes`, sem `.rpc(`/credencial/`.from(`/storage), `src/services/observacoesSoberanas/`
  (`controladorObservacoes.ts`, `mapeadorObservacaoUi.ts`, `fluxoMutacaoObservacao.ts`),
  `src/services/acessoObservacoesSoberanas.ts` e `src/pages/observacoesSoberanasDaPagina.ts`.
- **Identidade por UUID:** a projeção soberana devolve UUID, então o tipo legado
  `src/types/Observacao.ts` (matrícula numérica) ficou **intocado**; o view-model `ObservacaoDeUi` usa
  UUID como identidade e recebe rótulos por parâmetro (devolve `null` quando falta o rótulo do alvo) —
  nenhuma autoridade local de identidade e nenhuma derivação de `ano`/`ciclo`.
- **Timeline soberana:** leitura da trilha (`observacao.historico`) acrescentada à porta/repositório e
  consumida pelo painel; nenhum campo inventado fora da projeção real da P2.
- **Cutover da UI gerencial:** `src/components/ObservacoesColaborador.tsx` (sem `observacaoStorage` e sem
  gate local), `src/components/filtroObservacoesPorCiclo.ts`, `src/pages/ColaboradorDetalhePage.tsx`
  (observações do colaborador-alvo + KPI pela porta) e `src/services/exportarAvaliacaoPdf.ts` (lista
  soberana por parâmetro, no molde `metasDoCiclo`, **sem** leitura local). Desenho visual preservado.
- **Barreira D13 no acervo legado:** `src/services/observacaoStorage.ts` — as três mutações passaram a
  **LANÇAR** (`ERRO_ESCRITA_LOCAL_OBSERVACOES`, retorno `never`); removidos `persistir`, o gate de ciclo
  LOCAL `validarCicloAtivo` e o id fabricado no browser; as quatro leituras permanecem como **legado
  somente leitura**, sem dual-read e **sem fallback**. Produtor DEV cortado em
  `src/services/geradorDadosTeste.ts` (a semente DEV deixa de produzir observações locais);
  `src/services/resetBaseDesenvolvimento.ts` preservado como removedor; a guarda
  `src/authorization/estruturaUiSeguranca.test.ts` inclui o módulo em `CAMINHOS_LEGADO_LEITURA` e ganhou
  prova de "acervo legado é SOMENTE LEITURA".
- **Dívidas da P4 fechadas nesta fase:** (i) **autoria como relação** chega ao provider
  (`observacaoDoAlvo` em `src/authorization/providers/reais.ts`, repassado por
  `src/authorization/contextoAutorizacao.ts` a partir de `resourceContext.observacao`); (ii)
  **vocabulário de status** normalizado na fronteira pelo normalizador canônico
  (`active|leave|inactive` → `ATIVO|LICENCA|DESLIGADO`, desconhecido ⇒ `""` ⇒ fail-closed), sem criar
  segundo vocabulário na borda e sem duplicar a matriz de `estadoDominioObservacao.ts`.
- **SELF/read — ADIADO PARA P5.1 (BLOCKER arquitetural registrado):** a exceção normativa de **escopo**
  para a leitura SELF-comunicada já existe no gate da P3, mas a **capability** `observation.read` é
  exigida **antes** dela e o avaliado **não possui a concessão** (D15 concedeu `observation.*` apenas a
  `observacoes_gestor`, com `DIRECT_REPORTS`/`DESCENDANTS`). Nesta fase **nenhuma** capability, grant,
  role, scope ou exceção foi criada; D15 e o **mapa fechado da P3 permanecem inalterados**; o fluxo do
  avaliado (`src/pages/MinhaAvaliacaoDetalhePage.tsx`) ficou **fail-closed** (lista vazia explícita, sem
  bloco/atalho na tela e sem seção no PDF), com comentário no código apontando a dependência.
  **Escopo fixado para a P5.1:** leitura **somente SELF**; somente observações `comunicado = true`;
  excluídas **não** visíveis; **zero** mutações SELF; `observacoes_gestor` **inalterado**; fail-closed e
  isolamento cross-tenant preservados; **sem** reutilizar capability de outro domínio.
- **Fora de escopo / dívidas:** resíduo morto de observações (`ImpactoTemporalPeriodoCiclo.observacoes`,
  `persistirCorrecaoPeriodoCicloAtivoInterno`, `confirmarCorrecaoPeriodoCiclo.ts`) **não removido** nesta
  fase; certificação integrada fica para a **P6**.
- **P5 — GATES EXECUTADOS (orquestrador, gate privilegiado agrupado):** `git diff --check` exit 0; `npm test` **2296 de 2298** testes passando, com **apenas as 2 falhas PRÉ-EXISTENTES** de Windows/CRLF (`AcompanhamentoMetasPage.test.tsx`, `MinhasMetasPage.test.tsx`) — nenhuma falha nova; `npm run build` exit 0; `npm run lint` exit 0 (os 3 erros `react-hooks/set-state-in-effect`/`Cannot access refs during render` do painel foram corrigidos ESTRUTURALMENTE, sem `eslint-disable`); invariantes de fronteira conferidos (`.rpc(` = 0 e `SERVICE_ROLE_KEY` = 0 nos módulos de cliente). Commit **`6fd020d2d043771c4e66eab339ba9d0e04cfa0af`** (36 arquivos, +5540/-873) publicado em **`feat/f5-11-p5-cutover-observacoes`** (`push` exit 0), base `8e88e3752b9ea3467a94c53fdd58b5eca9b92edc`. **Sem merge** — PR a abrir pelo orquestrador (DEV-04; `gh` ausente no ambiente).
- **P5.1 — BLOCKER ARQUITETURAL REGISTRADO (SELF/read):** nesta fase NÃO houve capability, grant, role, scope ou exceção de autorização novos, nem alteração de D15 ou do mapa fechado da P3. O fluxo do avaliado (`MinhaAvaliacaoDetalhePage`) ficou **fail-closed** (lista vazia explícita, sem bloco/atalho, sem seção no PDF e sem fallback local). Motivo técnico: a isenção normativa de escopo para a leitura SELF-comunicada já existe no gate da P3, mas a capability `observation.read` é exigida ANTES dela e o avaliado não possui a concessão (só `observacoes_gestor`, com escopos `DIRECT_REPORTS`/`DESCENDANTS`). Escopo fixado pelo orquestrador para a P5.1: leitura SOMENTE SELF, somente observações `comunicado = true`, excluídas invisíveis, zero mutações SELF, `observacoes_gestor` inalterado, fail-closed e isolamento cross-tenant preservados.
  `git diff --check` são executados pelo **orquestrador** no gate privilegiado da fase, depois do
  congelamento dos arquivos. **Nenhum resultado de gate é afirmado aqui** — substituir este marcador pelo
  resultado real.
- **P2 — issue que a governa:** **Issue #244** (`F5-11/P2 — RPCs soberanas observacao_*`), mãe
  **#238**. Branch **`feat/f5-11-p2-rpcs-observacoes`**, base `e7aecf27532948d21b97d04d9c15aa7478442cca`.
- **P2 — o que entregou:** migration `20260931000000_f5_11_p2_observacoes_rpc.sql` com **8 RPCs
  `observacao_*`** (`criar`, `editar`, `definir_comunicado`, `excluir`, `revogar`, `obter`,
  `listar_por_escopo`, `historico`) + **6 helpers** do gate — todas `SECURITY INVOKER`,
  `search_path = public`, `EXECUTE` só `service_role`. Gate funcional com mapa **FECHADO**
  operação→capability (`observation.create/edit/delete/read`), **auth.uid() × parâmetro** (D3),
  autoria **D5**, relação DIRECT_REPORTS/DESCENDANTS, ciclo **ATIVO** (D12) e matriz do colaborador
  (**D11**); concorrência por `expected_version` + `FOR UPDATE` **sem advisory lock** (D10); eventos
  na **MESMA** transação (D6) com `payload_hash` server-side e idempotência dupla; `observation.*`
  segue com **ZERO concessão** (D15 **continua BLOQUEANDO a P3**) e `admin` sem `observation.*`.
- **P2 — fixtures/validadores:** `38-cenario-f5-11-p2.sql` (prefixo **`f5b2`**: 2 organizações, 7
  identidades, 10 colaboradores, hierarquia viva para DIRECT_REPORTS, 5 ciclos e a matriz D11 com
  `active`/`leave`/`inactive` + 1 colaborador SEM status) e `39-validar-f5-11-p2.sql` (blocos A–E; o
  caminho ALLOW usa concessão **transitória** `begin`/`rollback`, provada **não persistente**). As
  listas fechadas de `15`/`30`/`35`/`37` foram **ampliadas explicitamente** (nenhuma guarda removida)
  e o `ci.yml` ganhou as duas etapas da P2.
- **P2 — evidência (executada; não repetir):** gate focado verde (**34** 1, **35** 11, **36** 1,
  **37** 8, **38** 1, **39** 7 PASS) e **bateria completa na ordem do CI: 52/52 etapas verdes**
  (2 concorrências reais A=0/B=0), com o `39` verde **no ambiente em que a fixture antiga `f2`
  (F5-10 P4) está presente**.
- **P2 — colisão de fixture (finding real, fechado):** a fixture da P2 nasceu com o prefixo `f2`,
  IGUAL ao da F5-10 P4 (`25-cenario-f5-10-p4.sql`, org `f2a…-a1`); como o guard insert-once usava só
  o id, ele confundiu "fixture de outra fase" com "já carregado" e **pulou a fixture inteira** — o
  full gate reprovou no bloco A do `39` (contou 7 colaboradores / 3 ciclos alheios). Correção:
  prefixo **`f5b2`** (família verificada livre), guard pelo **nome** da organização, **erro explícito
  de colisão** e contagens por **prefixo** de id (imunes à vizinhança).
- **P2 — defeitos intermediários da própria execução (registrados):** guarda comparando superfície
  por TEXTO de assinatura (→ OID); vírgula final nas listas fechadas injetadas; fixture com
  `valid_to < valid_from` (CHECK do F3-05) e validade fora da posição; `uuid ~~ text`; `$$` aninhado
  dentro de bloco `DO`; expectativa de trilha da edição com transição (grava **2** eventos);
  argumento `NULL` do teste do gate; e a colisão de prefixo acima. **Nove execuções privilegiadas**
  ocorreram antes da pausa de controle (DEV-02/DEV-03) — todas registradas para avaliação de
  aderência.
- **P1 — issue que a governa:** **Issue #240** (`F5-11/P1 — Schema soberano, audit trail e
  substituição dos guards invertidos`), **Issue-mãe #238**. O PR da P1 fecha **#240** (`Closes #240`)
  e **não** fecha a #238. Branch: **`feat/f5-11-p1-observacoes-schema`**, base `6d527cc…`
  (**já integrada** em `main` como `0fe76193a408c857cc006707c28cb32d8c1d03c2`).
- **Exceção de processo registrada pela Issue #240:** a P1 nasceu na esteira da #238 e a
  **regularização de rastreabilidade** (issue própria + PR próprio) é o objeto explícito da #240.
  Os **artefatos SQL** citam internamente `F5-11 P1 (Issue #238)` porque já estavam **validados byte
  a byte**; eles **não** foram reeditados só para trocar o número — **a evidência vale mais que a
  referência cosmética** (reenquadrar comentário invalidaria a bateria verde sem ganho técnico).
- **P0 CONCLUÍDO (contexto):** auditoria GPT aprovou o desenho e fechou **Q1–Q16 = A**, registradas
  como **decisões normativas D1–D16** (§15 do contrato) com rastreabilidade Q#→D#. Contrato:
  `cycle_id` obrigatório (D2); autoria **exclusivamente derivada** do contexto autenticado (D3);
  **só o autor soberano** edita/exclui/revoga/comunica (D5); colaborador/ciclo/autoria **imutáveis**
  (D4); histórico **append-only** (D6); **comunicado é fato auditável** com ator e instante, **sem
  capability nova** (D7); exclusão lógica com motivo e revogação em ciclo `ATIVO` (D8); **RLS
  deny-by-default integral** (D9); `version` + row lock, **sem advisory lock** (D10); `leave` cria,
  `inactive` não cria (D11); mutação só em ciclo `ATIVO` (D12); **não migrar** o `localStorage` (D13);
  decomposição **P0–P6** (D14); concessão explícita em bundle/perfil **distinto de `admin`** (D15);
  texto 1..2000 e motivo obrigatório (D16).
- **P1 — implementação (na árvore de trabalho da branch, pronta para commit):**
  migration `supabase/migrations/20260929000000_f5_11_p1_observations_schema.sql` com
  **`evaluation_observations`** (identidade UUID do banco; `cycle_id` **NOT NULL** com FK composta de
  tenant; `tipo` fechado; `texto` `btrim` 1..2000; `comunicado` como **fato** com carimbo e CHECK de
  coerência; exclusão **sempre lógica** com `motivo_exclusao` obrigatório; autoria derivada com
  `author_user_profile_id`/`author_membership_id` **NOT NULL**) e
  **`evaluation_observation_events`** (trilha **APPEND-ONLY** no molde `cycle_events`/
  `evaluation_goal_events`: `event_type` fechado, before/after, `payload_hash` SHA-256,
  `unique (organization_id, operation_id)`), **imutabilidade estrutural D4** por trigger,
  **RLS deny-by-default integral (ZERO policy, ZERO privilégio de cliente)** e `service_role` como
  executor técnico **sem `DELETE`/`TRUNCATE`**. Cenário `34-cenario-f5-11-p1.sql` e validador
  `35-validar-f5-11-p1.sql` (blocos A–K, **11 PASS**).
- **Guards invertidos SUBSTITUÍDOS (nunca removidos):** a **proibição absoluta** de objeto de
  observação virou **LISTA FECHADA** em `15-validar-f5-09-p9.sql` (2 tabelas legítimas + **zero**
  funções até a P2), `30-validar-f5-10-p7.sql` (idem, com prova de que as 2 tabelas **existem**) e
  `02-validar-f4-08.sql` (inventário/classificação D16 + deny-by-default integral + contagens
  **49 → 51** tabelas e **26 → 28** fechadas) e `03-validar-f4-08-mutacoes.sql` (as **duas** cópias
  da lista de classificação — variante do mesmo defeito que só apareceu na bateria completa).
- **Evidências JÁ EXECUTADAS e VÁLIDAS (não repetir — Issue #240 §1):** `db reset` local OK;
  **bateria de banco completa na ordem do CI: 47/47 etapas verdes**, incluindo as **duas
  concorrências reais (A=0 / B=0)**; `34-cenario` 1 PASS; **`35-validar` 11 PASS**; regressões
  F4-08/F5-04/F5-08/F5-09/F5-10/F5-06/F5-07 verdes; `git diff --check` limpo. Repetir `db reset` ou a
  bateria completa **apenas por cautela é proibido**.
- **Evidências da P1.1 (executadas; não repetir):** gate **focado** = `db reset` + **7 etapas
  verdes** — `01/02/03` (guards de schema/ACL do F4-08, os mais sensíveis a objeto novo: 57 PASS e
  8 PASS), `34/35` (P1 com a fixture enriquecida: 1 PASS e 11 PASS) e `36/37` (P1.1: 1 PASS e
  **8 PASS**). A bateria de **47 etapas NÃO foi repetida**: nenhum validador existente foi editado e
  os nomes das funções novas **não** casam com nenhuma lista fechada de `15`/`30`/`35` (sem
  `observa`/`meta`/`goal`), então a evidência anterior segue válida por construção; o CI do PR roda a
  bateria completa no ambiente autoritativo.
- **Evidências da correção pré-merge do PR #243 (executadas; não repetir):** gate **foco da correção**
  = `db reset` + **4 etapas verdes** — `34` 1 PASS, `35` 11 PASS, `36` 1 PASS e `37` **8 PASS** (agora
  com `A1b`, `B4/B5` e `D4/D5/D6`). As etapas `01/02/03` (F4-08) **não** foram repetidas: a correção
  altera apenas o **corpo** de uma função `SECURITY INVOKER` já existente — nenhum objeto, grant,
  policy, RLS ou **forma** de gatilho mudou (o próprio `37` reprova se a forma dos gatilhos mudar).
- **Gates de código desta correção (executados):** `git diff HEAD --stat -- src/` **vazio** (nada de
  TS/JS foi tocado), `git diff --check` exit 0, `npm run build` exit 0 e `npm run lint` exit 0.
  `npm test` registra **2 falhas PRÉ-EXISTENTES e idênticas** às da rodada da P1
  (`AcompanhamentoMetasPage` e `MinhasMetasPage`), ambas asserts de **fonte multilinha** que quebram
  no **Windows** por **CRLF** (`src/` intocado): **2075 testes passam** e o CI (ubuntu) é o ambiente
  autoritativo.
- **D15 continua BLOQUEANDO a P3 (estado inalterado):** `observation.*` **sem concessão alguma**;
  **`admin` continua SEM `observation.*`** (guarda `02-validar-f4-01.sql:563-578` **preservada**, e o
  validador da P1 **falha** se o bundle deixar de ter 9 ou se qualquer role de sistema receber
  `observation.*`); **nenhuma** role/bundle/perfil criado. **Antes da P3** o documento **deve**
  receber a tabela `capability → bundle/perfil existente → escopo`. **A P1 não antecipa D15.**
- **Correção factual (apenas evidência para a investigação de D15, nada resolvido aqui):** o banco
  real, após `db reset`, tem **três** roles de sistema — `admin`, **`metas_dono`** e
  **`metas_aprovador`** —, sendo as duas últimas criadas pela **migration da F5-10 P4**
  (`20260925000000:2314-2332`) como o mecanismo de concessão explícita do D7 da F5-10; **persistem**
  e **não** são fixture de validação (a nota anterior do §8 estava **incorreta** e foi corrigida).
  **Proibido** nesta fase: reutilizar `metas_dono`/`metas_aprovador` por conveniência, criar perfil de
  observações, conceder `observation.*` ou alterar o bundle `admin`.
- **P2 e P3 NÃO foram iniciadas.** Nenhuma RPC `observacao_*`, nenhuma função de domínio, nenhuma
  policy de leitura, nenhum Edge, nenhum cutover, nenhuma migração de `localStorage`. O validador da
  P1 **falha** se qualquer RPC aparecer.
- **Achados de reconhecimento que seguem válidos (P0):** o domínio é **inutilizável fora do DEV**
  (`observation` é recurso **não soberano** em `resourceContextReal.ts:38` e o componente não passa
  `collaborators`); `edit`/`delete` **não têm enforcement** (dívida registrada em
  `docs/F4-09-desenho-tecnico.md:253-255` e `docs/F5-07-desenho-tecnico.md:1331-1338` §20.4);
  editar/excluir observação **de outro autor** é **ALLOW** hoje (`authorizationPolicy.test.ts:508-518`)
  ⇒ a F5-11 **deve inverter** esse teste (D5); `comunicado` não tem capability (F4-01 registrou a
  semântica como **futura**); `impactoCorrecaoPeriodoCiclo.ts`/`correcaoPeriodoCicloService.ts` foram
  **removidos** em `4868ca7`.
- **Fronteira de escopo:** `Feedback.observacaoGerente`/`observacaoCoordenador` é **outro** conceito
  (observação de critério, já soberano em F5-06) — **fora** da F5-11.
- **Gap documental pré-existente (não corrigido, fora do escopo):** a migration
  `20260928000000_f5_10_p5_2_leitura_soberana_metas.sql` (F5-10 P5.2) **não** tem linha no
  `supabase/migrations/README.md`.
- **Próximos passos:** concluir a **P1.1** (commit/push + PR que **fecha #242**; o orquestrador conduz
  PR → auditoria GPT → CI → decisão Codex → squash) → depois **P2** (RPCs `observacao_*`) → **P3**
  (autorização + concessões + RLS, **bloqueada até existir o artefato de D15**) → **P4** (Edge +
  cliente) → **P5** (cutover + barreira contra persistência local) → **P6** (certificação). Contratos
  da F5-09 (D1–D28) e da F5-10 (D1–D25) **não reabrem**; catálogo permanece com **31** capabilities.
- **Lição DEV-03 desta execução (repetição excessiva de gates):** a P1 consumiu **3 execuções
  completas** da bateria SQL (≈47 etapas cada) e várias execuções focadas, **a maior parte por
  defeitos do harness local, não do produto**. Causas-raiz identificadas: (a) o runner PowerShell
  continuava após falha (retorno de função virou array) → mascarou o conjunto real de falhas e
  forçou reexecuções; (b) a leitura de exit code das duas sessões de concorrência era corrompida pelo
  interleaving de `stdout`/`stderr` → falso negativo nas duas corridas; (c) `Set-Location` com
  caminho acentuado quebrou no runner focado. **Regra adotada:** *harness de gate é código — quando
  ele falha duas vezes seguidas, a causa-raiz é do harness e deve ser corrigida ANTES de nova
  execução; e o gate completo nunca é a primeira tentativa de validar um artefato novo* (o caminho
  correto é sempre o validador focado primeiro). Nesta retomada: **0** `db reset`, **0** bateria
  completa, **1** batch de gates de código, **1** push — sem repetir nenhuma evidência verde.
- **Fallback DEV-04:** o ambiente **não** tem mecanismo autorizado de abertura de PR (sem `gh`, sem
  PAT/credencial — proibido instalar/contornar) ⇒ a entrega é **branch + SHA + título + corpo** e o
  PR deve ser aberto pelo **orquestrador**. **Nunca fazer merge.**

### 3.22 DEV-04 — abertura de PR e disparo antecipado do CI (Issue #234)

- **Atividade:** **DEV-04** (Issue #234), branch `docs/dev-04-pr-automatico`,
  base `main` = `0b2e3feba5be39a67936a77a847aa7777f70bc0e` (squash do PR #233).
  Atividade **exclusivamente processual/documental**: **nenhuma** mudança de
  código, SQL, migration, RPC, RLS, capability, Edge, página, teste ou workflow de
  CI; nenhuma credencial/PAT; `gh` **não** instalado.
- **Regra formalizada:** com a implementação e os **gates locais planejados**
  verdes e **sem blocker** → `commit + push` → **PR imediatamente** (vinculado com
  `Closes #<n>`) → **CI no SHA do PR** → auditoria GPT (Codex quando aplicável) →
  **squash merge** com solicitação explícita do responsável. O **agente de
  implementação nunca faz merge**; correção posterior ao PR gera **novo SHA** com
  **novo CI**; **não** se habilita CI pesado em push intermediário (integração com
  DEV-03).
- **Fallback agente → orquestrador (documentado):** quando o ambiente do agente
  **não** possui mecanismo **autorizado** para abrir PR, ele entrega **branch,
  SHA, título e corpo** e informa **explicitamente** que o PR precisa ser aberto
  pelo **orquestrador** (integração GitHub já autorizada). É **proibido**
  instalar `gh`, criar/usar PAT ou alterar credenciais/`git config` para
  contornar — o orquestrador é **preferível** a nova superfície de credencial
  (integração com DEV-02).
- **Onde ficou registrado (conjunto mínimo auditado):**
  `.ai/workflow.md` — **§1** (fluxo oficial completo), **§2** (fases 6–10:
  commit/push → PR → CI no SHA → auditoria → squash merge), **§5** (nota de
  leitura) e **§7 NOVO** (DEV-04: 7.1 fluxo de fechamento, 7.2 regras, 7.3
  limitação do ambiente, 7.4 integração com DEV-03, 7.5 integração com DEV-02,
  7.6 o que não altera e 7.7 rastreabilidade das regras DEV); `AGENTS.md` —
  **§1** (ordem de leitura atualizada) e **§6** (Fluxo GitHub: PR imediato,
  fallback, CI por SHA, proibição de merge); `.ai/git-rules.md` — **§1**
  (branch/PR), **§3** (limitação do sandbox agora cobre `push` **e** criação de
  PR) e **§4** (checklist DEV-04); e este handoff.
- **Auditoria de registro (fato relevante para retomada):** **DEV-01 = Issue
  #167**; **DEV-02 = Issue #177** (`.ai/workflow.md` §6 + `AGENTS.md` §4);
  **DEV-03 é regra operacional vigente (gate de fechamento / gates focados) SEM
  Issue e SEM documento normativo próprio** — está apenas citada em contratos,
  matrizes e corpos de Issue; **não existe "Plano Mestre"** no repositório (o
  equivalente normativo real é `.ai/workflow.md` + `AGENTS.md` +
  `.ai/git-rules.md`). **Pendência registrada para o owner:** formalizar DEV-01 e
  DEV-03 em documento normativo próprio, em atividade DEV futura (fora do escopo
  da #234).
- **Validação (atividade documental, DEV-03):** `git diff --check` e conferência
  de escopo — **não** se executa bateria completa de produto (nenhum artefato de
  runtime foi tocado). Nenhum gate de produto é afetado.
- **Não feito (por contrato):** configuração de Codex Code Review automático,
  instalação de `gh`, PAT/token, mudança de credenciais, alteração de workflow de
  CI e qualquer mudança funcional — todos explicitamente fora de escopo.

### 3.21 F5-10 P7 — validação integrada e certificação do domínio de metas (Issue #232)

- **Atividade:** F5-10 **P7** (Issue #232) na branch
  `feat/f5-10-p7-validacao-integrada`, base `main` =
  `f53144ff81cc8e011e68f81b1e3f942f50decb29` (após P6 e os PRs de dependência
  #229/#230/#231). **Commits publicados nesta branch:** a entrega
  `1db70b986d3ce9b90f1521ad0e4d0128834baa31` (8 arquivos, +3873 linhas) e o ajuste
  documental `3d33f68bf51e7e46aa019c4041625a4e33794f45`, seguidos de **correções
  documentais posteriores**; **push feito com sucesso**
  (`origin/feat/f5-10-p7-validacao-integrada`). **PR #233 ABERTO** (`Closes #232`)
  na branch acima. **F5-11 não iniciada.**
- **CI (fato permanente):** o SHA `3d33f68…` teve **CI verde — #264 / run
  `34908000458`**, evento `pull_request`, com os **dois jobs**
  (`Test, build, lint and diff-check` e `Supabase local — RLS/policy validation`,
  esta com os 4 passos novos da P7) em `success`; as **correções documentais
  posteriores** geraram **novos SHAs e novos runs de CI**, também verdes.
- **Regra de leitura (atemporal):** este handoff **não fixa** o "head atual" da
  branch nem o run de CI mais recente — **cada commit gera novo SHA e novo run**.
  Antes do fechamento/merge, **confirme o SHA final e o CI correspondente
  diretamente no GitHub / PR #233**.
- **Auditoria Codex do SHA `3d33f68…`: CHANGES REQUIRED / DO NOT MERGE, com
  APENAS dívida documental** — o conteúdo versionado de certificação e este handoff
  não refletiam o estado real do PR/CI. **Nenhum achado de código, SQL, workflow,
  `src/` ou arquitetura.** As correções foram aplicadas **somente em
  documentação** (`docs/F5-10-p7-matriz-integrada.md` e este handoff), em commits
  próprios — nenhum arquivo SQL, workflow, `src/` ou teste tocado, e sem full gate
  local (validação por `git diff --check` + conferência de escopo).
- **Pendências antes do merge:** (1) **auditoria delta GPT/Codex final** sobre o
  SHA que for efetivamente fechado; (2) **squash merge** (somente com solicitação
  explícita do responsável). O CI de cada correção é disparado automaticamente pelo
  PR #233 (evento `pull_request`) e deve ser conferido no GitHub **no SHA final**.
- **Natureza:** **certificação/validação integrada** — **não** é feature e **não**
  cria arquitetura: **zero** migration, RPC, capability, policy, RLS, grant, Edge ou
  página alterados.
- **Entregue (8 arquivos):** `supabase/validacao/29-cenario-f5-10-p7.sql` (fixture
  integrada ISOLADA, prefixo `e8`; 3 organizações com papéis não sobrepostos —
  Alfa = matriz, Beta = cross-tenant, Gama = corrida exclusiva),
  `30-validar-f5-10-p7.sql` (matriz dos blocos 1 e 4–19; **19 `[PASS]`**),
  `31-sessao-a-`/`32-sessao-b-`/`33-validar-`**concorrência** (bloco 6),
  `docs/F5-10-p7-matriz-integrada.md` (molde da P9, com gates executados × não
  executados, findings e desvios), `.github/workflows/ci.yml` (4 passos novos após
  a P5.2 e antes das regressões F5-06/F5-07) e este arquivo.
- **Bloco 6 — concorrência REAL (dois backends), o núcleo novo da P7:** a sessão A
  cria as 2 metas da corrida por `meta_criar` em Gama-P7 e detém
  `ciclo_lock_organizacao` (`evaluation_cycles:<org>`) dentro de uma escrita
  atrasada em ~8 s; a sessão B aguarda deterministicamente a **marca não
  transacional** publicada DENTRO da escrita e então tenta a MESMA operação.
  - **Fase 1 (edição, mesma versão):** A ~8,03 s; B **bloqueada ~7,47 s** →
    `F5_10_CONFLICT: versao divergente`; estado final é o de A (version 1) —
    **nenhum lost update**.
  - **Fase 2 (aprovação, MESMO papel):** a aprovação **não altera `version` da
    meta** (D2/D3), logo o `expected_version` de B segue válido e o que reprova B é
    "uma única aprovação VIGENTE por (meta, papel)", avaliada **depois** do lock:
    A ~8,02 s, B **bloqueada ~7,78 s** → `F5_10_CONFLICT: ja existe aprovacao
    vigente do papel GERENTE`.
  - **Fase 3 (papéis distintos, contraparte positiva):** COORDENADOR congelado
    aprova a MESMA meta — os **2 fatos coexistem** (1 vigente por papel) e o fato
    de A permanece intacto.
  - A prova de **contenção** vive no stdout da sessão B; o consolidador `33` prova o
    estado final, a **ausência** de efeito das intenções perdedoras e a **higiene**
    (remoção dos 2 gatilhos, 2 funções e 2 sequences temporárias).
- **Gates reais desta rodada:** preflight obrigatório (Docker 29.7.2 + Supabase
  local PostgreSQL 17.6 + `db reset` exit 0) **antes** de qualquer implementação;
  gate **focado** `db reset` + 29 + 30 + 31/32/33 = **`falhas=0`** (30 com 19
  `[PASS]`, concorrência A=5/B=4, consolidação 3); **bateria SQL completa na ordem
  do CI = 46/46 entradas, `falhas=0`**; `npm run build`/`npm run lint`/
  `npx tsc -b tsconfig.app.json` exit 0; `git diff --cached --check` exit 0.
- **Limitação de ambiente registrada (não é do escopo):** `npm test` local =
  **2060 PASS / 2 falhas** em `src/pages/MinhasMetasPage.test.tsx:340` e
  `src/pages/AcompanhamentoMetasPage.test.tsx:341`. Causa-raiz **provada**:
  `git diff HEAD -- src/` está **vazio** (as falhas são pré-existentes ao baseline
  `f53144f` e a P7 não toca `src/`), `core.autocrlf=true` **sem `.gitattributes`**
  materializa o working copy com **CRLF**, e as duas asserções comparam texto-fonte
  com literais que contêm `\n` — sonda objetiva: **FAIL com CRLF / PASS com LF**. O
  **CI (ubuntu-latest, LF)** casa as mesmas asserções. **Não corrigido de
  propósito** (editar 2 testes fora do inventário da Issue ou introduzir
  `.gitattributes` = manutenção oportunista/mudança transversal); registrado como
  finding para o owner.
- **Elevações de acesso (agrupadas, DEV-02):** **6 batches acumulados na P7** —
  (1) **P-0** preflight obrigatório + criação da branch; (2) **P-1** gate focado
  (**2 execuções**: a 1ª revelou 3 defeitos **meus** de artefato de validação —
  contagem da fixture, escopo do gatilho de marca e um bloco morto — corrigidos em
  lote com causa-raiz distinta); (3) **P-3** gate final (bateria SQL completa na
  ordem do CI + `npm` test/build/lint/tsc); (4) **diagnóstico** da falha de
  `npm test` (mandatório por DEV-03: root-cause **antes** de nova execução,
  produzindo a prova CRLF×LF); (5) **commit + push** do fechamento — os batches
  **1–5** formam a decomposição original da entrega; (6) **commit + push** da
  **correção documental pós-Codex** (batch adicional da mesma atividade). Nenhuma
  elevação para tentativa às cegas.
- **Não feito (por contrato):** F5-11, **auditoria delta GPT/Codex final** e
  **squash merge** (etapas externas/posteriores). **Nenhum defeito de produção
  encontrado.**

### 3.20 F5-10 P5.2 / P5.3 / P6 — lacunas documentais sanadas (Issues #222, #226 e #220)

> **Nota de manutenção:** este handoff ficou **atrás da `main`** entre a P5 e a P6
> (a P5.2, a P5.3 e a P6 foram integradas sem registro aqui). As entradas abaixo
> fecham a lacuna, em ordem cronológica, a partir do histórico e dos PRs
> (`#222`, `#227`, `#228`) — a **P7** é a entrada 3.21.

- **3.20.1 F5-10 P5.2 — leitura soberana de metas (Issue #222, PR #222):**
  `supabase/migrations/20260928000000_f5_10_p5_2_leitura_soberana_metas.sql`
  (`create or replace` de `meta_listar_por_escopo` — **mesma assinatura**) +
  `supabase/validacao/28-validar-f5-10-p5-2.sql` + `GoalRepository`/repositório
  (campos de data, `aprovacoes[]`, `limites`) e o contrato em
  `docs/F5-10-P5.2-contrato-leitura-soberana-metas.md`. **Zero** ampliação de
  privilégio: a superfície autorizada continua
  `SELF ∪ APROVADOR_GERENTE_CONGELADO ∪ APROVADOR_COORDENADOR_CONGELADO`; a RPC
  segue `SECURITY INVOKER` com `EXECUTE` só `service_role` e as 4 tabelas de metas
  seguem **deny-by-default integral** (D22-A).
- **3.20.2 F5-10 P5.3 — autoridade soberana do Painel de Ciclo (Issue #226,
  PR #227):** atividade **documental**
  (`docs/F5-10-P5.3-autoridade-painel-ciclo.md`). Decisão fechada: **autoridade
  zero nova** — o Painel não exibe metas individuais e o único consumo vivo é o
  KPI agregado "Minhas aprovações de metas", coberto pela superfície já existente.
  Nenhuma capability/RPC/relação/RLS/grant nova.
- **3.20.3 F5-10 P6 — cutover funcional de metas (Issue #220, PR #228, squash
  `4868ca7`):** consumidores migrados para `GoalRepository.listarMetasPorEscopo`
  (Edge `metas`) via acessor único `src/services/acessoMetasSoberanas.ts` e hook
  `useMetasSoberanasDaAvaliacao`; Painel de Ciclo por **UUID soberano**; **removidos**
  `metaStorage.ts`, `correcaoPeriodoCicloService.ts`,
  `impactoCorrecaoPeriodoCiclo.ts` e `cicloEquipeService.analisarPendenciasDoCiclo`;
  nova guarda `src/authorization/cutoverMetasSoberanas.test.ts` (13 guardas) e
  `estruturaUiSeguranca.test.ts` ajustado. Sem capability/RLS/RPC nova; nenhum dado
  de `localStorage` migrado; `can()`/`localWorld` fora da autoridade de metas.
- **3.20.4 Dependências (fora de atividades estruturais):** PRs `#229`
  (react-router-dom 7.18.3), `#230` (react-dom/@types/react-dom 19.3) e `#231`
  (vite 8.3.0) — squash-merged na `main` **depois** da P6. Baseline operacional da
  P7: `main` = `f53144ff81cc8e011e68f81b1e3f942f50decb29`.

### 3.19 F5-10 P5 — transporte soberano de metas + hardening D22-A (Issue #218)

- **Atividade:** F5-10 **P5** (Issue #218) na branch `feat/f5-10-p5-transporte-metas`,
  base `c5cf51acf60e67ac1ca54b6b26b92cb33f3cec0f`. **Sem PR e sem merge**; P6, P7 e
  F5-11 **não** iniciados.
- **Bloco 1 — transporte:** Edge Function `metas`
  (`supabase/functions/metas/{contrato,core,index}.ts`) com a ordem normativa
  (método → JWT via `auth.getUser` → forma → tenant revalidado contra membership
  ativa → gate → RPC privilegiada). O núcleo `metas(req, deps)` é testável e
  **não** menciona a credencial; `index.ts` é o **único** lugar que lê
  `SUPABASE_SERVICE_ROLE_KEY` (credencial de **execução** do ator verificado,
  nunca de decisão; o JWT do usuário não é propagado). Contrato transportável
  único em `src/infrastructure/supabase/metas/contrato.ts` (9 operações `goal.*`,
  sem `goal.invalidar_aprovacoes`, que é interna às mutações), adapter de cliente
  fail-closed `edgeMetas.ts`, porta `src/application/ports/GoalRepository.ts` e
  repositório `repositorioMetasSoberanas.ts` (leitura **exclusivamente** por
  `goal.listar_por_escopo`). `[functions.metas] verify_jwt = true` em
  `supabase/config.toml`. Gates: `criar`→funcional `goal.write` (alvo
  colaborador dono); `editar`/`atualizar_progresso`/`finalizar`/
  `revisar_finalizacao`/`excluir`→funcional `goal.write` (alvo meta);
  `aprovar`→funcional `goal.approve`; `definir_limites_do_ciclo`→funcional
  `cycle.manage` (alvo ciclo); `listar_por_escopo`→**administrativo** `goal.read`.
- **Bloco 2 — hardening D22-A (decisão aprovada pelo owner):** migration aditiva
  `supabase/migrations/20260927000000_f5_10_p5_d22a_hardening.sql` revoga as 2
  policies own-tenant e o `SELECT` de `authenticated` nas tabelas de metas,
  devolvendo as **4** tabelas (`evaluation_goals`, `evaluation_goal_approvals`,
  `evaluation_goal_events`, `evaluation_cycle_goal_limits`) a
  **deny-by-default integral**, preservando a matriz de `service_role` (executor
  técnico), **sem tocar `evaluation_cycles`**, sem RPC/capability/`SECURITY
  DEFINER` novos. Guardas P4 invertidas: `02-validar-f4-08.sql`,
  `02-validar-f5-06.sql`, `20-validar-f5-10-p1.sql`, `22-validar-f5-10-p2.sql`,
  `24-validar-f5-10-p3.sql`, `26-validar-f5-10-p4.sql` e registro em
  `supabase/migrations/README.md`.
- **Testes focados (ambos verdes):** Bloco 1 — `vitest` de 9 arquivos (**157
  testes, 0 falhas**) + `tsc -b` exit 0 + `eslint` dos arquivos de metas exit 0;
  Bloco 2 — `db reset` + **13/13 entradas** SQL afetadas (f4-08, f5-06, F5-10
  P1–P4), **falhas=0**.
- **Gate de fechamento:** db reset + bateria SQL completa na ordem do CI (**41/41 entradas, falhas=0**) + `npm test`/`npm run build`/`npm run lint` verdes + `git diff --cached --check` exit 0 + `git diff --check c5cf51acf60e67ac1ca54b6b26b92cb33f3cec0f...HEAD` exit 0.
- **Elevações de acesso (agrupadas, DEV-02/§6):** **6 batches privilegiados** —
  1 preflight/inventário, 1 criação de branch, 2 do teste focado do Bloco 1 (o 1º
  vermelho por defeito no teste de guarda, o 2º verde), 1 da bateria focada SQL do
  Bloco 2 e este gate completo; 1 tentativa do Bloco 1 foi barrada pelo sandbox
  (`spawn EPERM` no carregamento do `vite.config.ts`) **antes** de executar
  qualquer teste e foi reexecutada com acesso amplo. Nenhuma outra elevação foi
  usada para depuração.
- **Nota de leitura:** as entradas §3.17/§3.18 descrevem o estado da **P4**, que
  expunha `SELECT` own-tenant de metas a `authenticated`; essa exposição foi
  **revogada por decisão** no Bloco 2 desta entrega (D22-A). A leitura funcional de
  metas passa exclusivamente pela superfície soberana (`meta_listar_por_escopo`).
- **Não feito (por contrato):** P6 (cutover das telas legadas de metas), P7,
  F5-11, PR e merge.

### 3.18 F5-10 P4 — correção pós-auditoria GPT (Issue #216)

- **Atividade:** correção do **blocker funcional de autorização** apontado pela
  auditoria independente sobre o SHA auditado
  `c65df8551e29a4d7705a5aa26e0d4598acf75f5d`: `meta_aprovar` **não revalidava a
  RELAÇÃO congelada** nos caminhos de replay (rápido, antes do lock, e sob o lock),
  devolvendo sucesso provando apenas `goal.approve`. **Sem PR e sem merge**; a
  migration auditada (`20260925000000`) **não foi editada** — a correção entra por
  migration **aditiva**: `supabase/migrations/20260926000000_f5_10_p4_replay_aprovador.sql`.
- **Correção:** a MESMA regra das etapas (12)/(13) da P3
  (`f5_10_aprovador_congelado` + vínculo soberano único via
  `resolver_collaborador_vinculado`, mensagens e sqlstates **idênticos**) passa a
  viver em um único ponto, **`f5_10_exigir_relacao_aprovador`**, chamado nos **3
  caminhos de retorno**: replay rápido, replay sob o lock e execução normal
  (substituindo o bloco inline original). **Não** é um segundo motor: reusa a
  autoridade canônica já existente.
- **Preservado:** idempotência (replay legítimo devolve o **MESMO** resultado, sem
  novo fato/evento), legitimidade **exclusivamente** do snapshot congelado da
  avaliação original, D19, `cycle.manage` em `meta_definir_limites_do_ciclo`,
  `goal.approve` sem implicar `goal.write`, nenhuma capability nova, nenhum
  `SECURITY DEFINER` novo e nenhuma família nova de advisory lock.
- **Testes:** bloco **H (A–G)** novo em `26-validar-f5-10-p4.sql` — replay legítimo,
  perda de capability, relação ausente (vínculo desativado), outro ator com
  `goal.approve`, hierarquia viva divergente, prova estática dos 3 caminhos e
  ausência de efeitos colaterais nos DENY.
- **Gates reais desta rodada:** db reset + bateria SQL completa na ordem do CI (**41/41 entradas, falhas=0**) + `npm test`/`npm run build`/`npm run lint` verdes + `git diff --check` exit 0. Elevações de acesso: **9 batches privilegiados** (2 geração+teste focado com defeito no meu próprio harness de geração; 1 teste focado; 3 diagnósticos/focados durante a depuração da migration de correção; 1 teste focado que ficou verde; 1 gate com erro de sintaxe no meu script; 1 gate completo de fechamento verde). Cada execução foi precedida de análise; o gate completo rodou **2** vezes (a 1ª abortou por erro de sintaxe do meu script de gate, sem executar bateria ou commit).
- **Não feito (por contrato):** P5, P6, P7, F5-11, PR e merge.

### 3.17 F5-10 P4 — guardas/CI/harness/documentação (em andamento; implementação paralela)

- **Atividade:** F5-10 — **P4 (AUTORIZAÇÃO/RLS de metas)** — recorte de
  **guardas de validação, CI, harness local e documentação**. Contrato:
  `docs/F5-10-desenho-tecnico.md`. **Sem PR e sem merge**.
- **Escopo desta rodada (arquivos exclusivos):**
  `supabase/validacao/02-validar-f4-08.sql`,
  `supabase/validacao/02-validar-f5-06.sql`,
  `supabase/validacao/15-validar-f5-09-p9.sql`,
  `supabase/validacao/20-validar-f5-10-p1.sql`,
  `.github/workflows/ci.yml`, `.git/dsh-p9-sql.ps1`,
  `supabase/migrations/README.md` e este arquivo. A migration
  `supabase/migrations/20260925000000_f5_10_p4_authorization_rls.sql`, o cenário
  `25-cenario-f5-10-p4.sql`, o validador `26-validar-f5-10-p4.sql` e os ajustes de
  `22-validar-f5-10-p2.sql`/`24-validar-f5-10-p3.sql` pertencem a outro agente.
- **Fatos congelados refletidos nas guardas:** **2** policies RLS novas em
  `public` (total **23 → 25**) — `evaluation_goals_select_same_tenant` e
  `evaluation_goal_approvals_select_same_tenant`, ambas
  `for select to authenticated using (public.user_has_active_membership(organization_id))`,
  criadas **antes** do `grant select ... to authenticated`; `evaluation_goal_events`
  e `evaluation_cycle_goal_limits` permanecem **deny-by-default integral** (zero
  policy, zero privilégio de cliente); `service_role` inalterado; **10** RPCs
  `meta_*` (a nova `meta_listar_por_escopo` com gate `goal.read` + relação) e **3**
  helpers `f5_10_*` de autorização; **nenhuma** capability nova (**31**; `goal.%` +
  `observation.%` = **8**), **nenhum** bundle novo (`admin` = 9), **nenhuma**
  tabela nova (49) e `SECURITY DEFINER` ainda exatamente **4**.
- **Alterações por arquivo:** `02-validar-f4-08.sql` — goals/approvals saem de
  "fechada" e entram em `v_readable` (19 → 21), tabelas fechadas 26 → 24 e
  invisíveis 22 → 23, policies **23 → 25**, novo bloco explícito de nome/predicado
  das 2 policies do contrato. `02-validar-f5-06.sql` — a varredura
  `tablename like 'evaluation%'` passa a admitir **explicitamente** as 3 policies
  own-tenant (ciclos + metas), sem afrouxar nenhuma outra.
  `15-validar-f5-09-p9.sql` — lista fechada de metas ampliada para 18 nomes
  (10 RPCs + 3 helpers P4 + 5 de integridade), contadores de capability
  intocados. `20-validar-f5-10-p1.sql` — blocos A/J invertidos apenas para
  goals/approvals (exatamente 1 policy SELECT own-tenant cada, `SELECT` concedido,
  **nenhuma** escrita/`anon`; events/limits seguem exigindo zero policy e leitura
  negada por permissão 42501) e K com as 10 RPCs. `ci.yml` — 2 passos novos
  (`name` citado) imediatamente após a validação P3. `dsh-p9-sql.ps1` — 2 entradas
  novas após `24-validar-f5-10-p3.sql` (41 entradas no total).
- **Gates reais desta rodada:** db reset + bateria SQL completa na ordem do CI (**41/41 entradas, falhas=0**) + `npm test`/`npm run build`/`npm run lint` verdes + `git diff --check` exit 0. Elevações de acesso nesta rodada:
   **9 batches privilegiados** nesta fase: 1 preflight obrigatório (`db reset`) + 8
   execuções do fluxo de fechamento/depuração — cada rodada revelou **1 defeito real**
   no validador novo da P4 (encoding do gerador, literal de array sem cast, ator de
   mutação, colisão de fixture, contagens/autoria da guarda final), e o gate é
   fail-closed (aborta sem commitar). Registro honesto: não houve elevação "extra"
   por conveniência; houve reteste após correção em cada rodada.
- **Divergência registrada:** o reconhecimento `.git/p4-recon/C-validacao.md`
  supunha 4 policies novas; o contrato congelado da P4 fixa **2** (as guardas
  seguem o contrato). Os ajustes de `22-validar-f5-10-p2.sql` e
  `24-validar-f5-10-p3.sql` (lista fechada com **10** RPCs, remoção de
  `meta_listar_por_escopo` das listas de antecipação proibida, inversão das
  guardas de policy/SELECT para `evaluation_goals`/`evaluation_goal_approvals` e
  troca do ator das mutações pelo **DONO** da meta — SELF) foram feitos na mesma
  rodada de implementação, junto com as fixtures 21/23 (vínculos soberanos,
  roles por tenant e capabilities **existentes** do catálogo).
- **Não feito (por contrato):** P5 (Edge/adapter), P6 (frontend/cutover/backfill),
  P7 (bateria integrada e concorrência real), F5-11, PR e merge.

### 3.16 F5-10 P3 (implementada; aguardando auditoria independente)

- **Atividade:** F5-10 — **P3 (APROVAÇÕES e INVALIDAÇÃO de metas)** — Issue
  **#214**. Contrato: `docs/F5-10-desenho-tecnico.md` (D1–D25; §7, §9 e matriz
  D19/§9.4, §10, §12, §13, §19 P3). **Sem PR e sem merge**.
- **Base:** `main` = `6a2ade2e2d8a11815392bbc1726e08c1adf8d746` (squash da P2,
  `feat(F5-10): operações soberanas de metas (#213)`).
  **Branch:** `feat/f5-10-p3-aprovacoes-metas`.
- **Entregue:** `supabase/migrations/20260924000000_f5_10_p3_approvals_rpc.sql`
  (`meta_aprovar`, `meta_invalidar_aprovacoes`, a reconexão da **matriz D19** em
  `meta_editar` por `create or replace` — a migration histórica da P2 **não** foi
  editada — e 3 helpers: `f5_10_aprovador_congelado`,
  `f5_10_invalidar_aprovacoes_vigentes`, `f5_10_derivar_operation_id`),
  `supabase/validacao/23-cenario-`/`24-validar-f5-10-p3.sql`,
  `.github/workflows/ci.yml` (2 passos novos, com `name` citado),
  `supabase/migrations/README.md` e as listas fechadas de anti-antecipação
  (`20-validar-f5-10-p1.sql`, `15-validar-f5-09-p9.sql`, `22-validar-f5-10-p2.sql`)
  ampliadas para as **9** RPCs do contrato P2+P3.
- **Legitimidade (fonte única CONGELADA):** avaliação não cancelada do dono da
  meta (ausência/duplicidade ⇒ fail-closed); **GERENTE** = ocorrência **original**
  de `GESTAO_CADEIA` (`evaluation_participants`, menor `valid_from`, empate ⇒ menor
  `collaborator_id`); **COORDENADOR** = ocorrência original de `GESTAO_DIRETA`,
  **somente quando existir e for distinta** da cadeia; a ocorrência escolhida
  precisa estar **vigente** e o **ator** precisa ser o **colaborador congelado**
  do papel (vínculo único; ausência/ambigüidade ⇒ fail-closed). Nenhuma
  hierarquia viva, matrícula, nome ou papel declarado pelo cliente — a guarda
  estática do SQL proíbe `position_reporting_lines`/`occupations`/
  `organizacao_resolver_*` na decisão.
- **Fato e histórico:** aprovação é linha em `evaluation_goal_approvals` (uma
  vigente por `(goal_id, papel)`), **não** altera `status`/`version` da meta,
  **não** finaliza e **não** exige finalização; invalidar preenche
  `revogado_em`/`revogado_motivo` + `version + 1` **na própria linha** e emite
  `APROVACAO_INVALIDADA` (um por papel); **nenhum** `DELETE`; reaprovar cria
  **novo fato** preservando o revogado.
- **D19 conectada:** alteração **material** (`descricao`/`kpi`/`valor_alvo`)
  invalida atomicamente as vigentes dentro de `meta_editar`; edição não efetiva,
  progresso, primeira finalização, revisão, quota, correção de período,
  movimentação estrutural e **soft delete** (terminal) **não** invalidam.
- **Idempotência/version/lock:** `expected_version` da **meta** comparado após
  `ciclo_lock_organizacao` + `SELECT … FOR UPDATE` (desvio (a) do header);
  `operation_id` + `payload_hash` SHA-256 server-side; sub-eventos da mesma
  intenção usam `operation_id` **derivado determinísticamente** (desvio (e));
  `meta_invalidar_aprovacoes` sem fato vigente é **NO-OP REGISTRADO na trilha**
  (um evento `APROVACAO_INVALIDADA` com o `operation_id` consumido,
  `result_entity_id` NULL, `invalidated = 0`, versão/status/motivo em before/after
  e **nenhuma** linha de aprovação alterada) — idempotência **temporal** provada:
  replay depois de surgir nova aprovação vigente continua devolvendo
  `invalidated = 0` e nunca invalida o novo fato; payload divergente ⇒ CONFLICT.
- **Gates reais (host local):** `db reset` + bateria SQL completa na ordem do CI
  = **39/39 entradas, `falhas=0`** + `git diff --check` exit 0. `npm test`/
  `build`/`lint`/`tsc` **não se aplicam** (nenhum arquivo JS/TS alterado).
- **Elevações de acesso nesta rodada:** 6 (preflight obrigatório com `db reset` e
  criação da branch; batch #1 quota 0..3; batch #2 `min(uuid)`; batch #3
  `payload_hash` do helper; batch #4 expectativa absoluta no F6; batch #5 bloco H
  movido para antes da finalização; batch #6 reteste verde com commit/push).
- **Correção de auditoria (idempotência do NO-OP, mesma branch):** NO-OP de
  `meta_invalidar_aprovacoes` passou a ser **persistente** (evento na trilha com
  `operation_id` consumido), com teste temporal crítico (nova aprovação vigente
  criada depois do NO-OP e replay da MESMA intenção), rollback da gravação do
  NO-OP e documentação corrigida. Gates: `db reset` + bateria completa +
  `git diff --check` = **db reset + bateria SQL completa na ordem do CI (**39/39 entradas, falhas=0**) + `git diff --check` exit 0**; elevações nesta correção: **2 (batch #1 â€” defeito real: `v_msg` usado no novo teste F9 sem estar declarado no bloco F, corrigido; batch #2 â€” reteste verde com commit e push)**.
- **Não feito (por contrato):** P4 (matriz `goal.*`, Policy Engine, RLS funcional,
  grants ao cliente, leitura por escopo), P5 (Edge/adapter), P6 (frontend/cutover/
  backfill), P7 (bateria integrada e concorrência real), F5-11, PR e merge.

### 3.15 F5-10 P2 (implementada; aguardando auditoria independente)

- **Atividade:** F5-10 — **P2 (OPERAÇÕES SOBERANAS de metas)** — Issue **#212**.
  Contrato: `docs/F5-10-desenho-tecnico.md` (D1–D25; §7 lifecycle, §10, §12, §13,
  §19 P2). **Sem PR e sem merge** (ficam com o usuário).
- **Base:** `main` = `3ebdc4e462560b6d187d7b20e85b03e5d3b87be0` (squash do PR #211,
  F5-10 P1). **Branch:** `feat/f5-10-p2-operacoes-metas`.
- **Entregue:** `supabase/migrations/20260923000000_f5_10_p2_goals_rpc.sql`
  (7 RPCs: `meta_criar`, `meta_editar`, `meta_atualizar_progresso`,
  `meta_finalizar`, `meta_revisar_finalizacao`, `meta_excluir`,
  `meta_definir_limites_do_ciclo` — `SECURITY INVOKER`, `search_path` fixo,
  `EXECUTE` só `service_role`, preflight + guarda final), o **CHECK aditivo** de
  `cycle_events.event_type` (D21), `supabase/validacao/21-cenario-`/
  `22-validar-f5-10-p2.sql` (positivos e negativos do escopo, incluindo os blocos
  M/D21), `.github/workflows/ci.yml` (2 passos novos, com `name` citado),
  `supabase/migrations/README.md` e regressões de anti-antecipação:
  `20-validar-f5-10-p1.sql` (bloco K → **lista fechada** com as 7 RPCs da P2) e
  `15-validar-f5-09-p9.sql` (lista fechada ampliada).
- **Padrões reusados da F5-09 P2 (auditados, nada de arquitetura nova):**
  `expected_version` obrigatório comparado **depois** do lock e do
  `SELECT FOR UPDATE` (`F5_10_CONFLICT`), idempotência por
  `unique (organization_id, operation_id)` com `payload_hash` SHA-256 derivado
  server-side (replay idêntico devolve o mesmo resultado; intenção divergente é
  `CONFLICT`), autoria **resolvida no banco** (`evaluation_ator_valido` +
  membership por `SELECT`; nunca vem do corpo), **um** evento append-only por
  operação na mesma transação, `version + 1` por mutação efetiva, ROLLBACK total
  em falha parcial e códigos estáveis `F5_10_INVALID_INPUT`/`FORBIDDEN`/
  `NOT_FOUND`/`CONFLICT`.
- **Lock:** a **mesma** família normativa dos ciclos, pela função canônica
  `public.ciclo_lock_organizacao` (chave
  `evaluation_cycles:<organization_id>`), adquirida no início de cada mutação.
  **Nenhuma** família/chave nova e nenhum `pg_advisory_xact_lock` literal nas
  RPCs (a guarda P6-6 do cutover da F5-08 continua verde).
- **D21 — `meta_definir_limites_do_ciclo` (decisão de review, implementada):** o
  evento `LIMITES_DO_CICLO_ALTERADOS` é registrado em **`cycle_events`**, não em
  `evaluation_goal_events` — limite é configuração do ciclo; capability normativa
  `cycle.manage`; `expected_version` e lock são do ciclo; e a trilha de ciclo já
  possui `cycle_id`, FK tenant-bound, autoria soberana, `operation_id`,
  `payload_hash`, before/after e idempotência. O CHECK de
  `cycle_events.event_type` foi ampliado de forma **aditiva e fail-closed**
  (baseline conferido antes do `ALTER`). **Nada disso foi feito:** anular
  `evaluation_goal_events.goal_id`, `goal_id` arbitrário, tabela nova de eventos,
  família nova de lock ou edição de migration histórica da P1. A RPC faz
  **upsert** do limite de um tipo (nunca abaixo das metas não excluídas), com
  `expected_version` **do ciclo**, `version` do ciclo **+1**, `operation_id`,
  `payload_hash` server-side, evento na mesma transação (before = limites
  anteriores; after = novos limites + nova version; `result_entity_id` =
  `cycle_id`) e rollback total em falha. O gate funcional `cycle.manage` exigido
  por D21 permanece na fronteira confiável final (Policy Engine/Edge, P4/P5),
  registrado no comentário da RPC; a quota segue invariante do banco (triggers da
  P1) e **nenhuma** política de quota paralela foi criada.
- **Gates reais (host local):** `db reset` + bateria SQL completa na ordem do CI
  (**37/37 entradas, `falhas=0`**) + `git diff --check`. `npm test`/`build`/
  `lint`/`tsc` **não se aplicam** (nenhum arquivo JS/TS alterado; a suíte geral
  fica no CI).
- **Elevações de acesso nesta rodada:** 5 (diagnóstico obrigatório de
  base/preflight, fetch do SHA base inexistente localmente, criação da branch no
  SHA exigido, batch de validação SQL #1 — que encontrou 1 defeito real no
  cenário, corrigido — e batch de reteste com commit/push).
- **Correção de auditoria (D21, mesma branch):** commit com o CHECK aditivo, a
  7ª RPC, os blocos M/D21 do validador, as listas fechadas (7 RPCs) e o README.
  Gates: `db reset` + bateria completa + `git diff --check` = **db reset + bateria SQL completa na ordem do CI (**37/37 entradas, falhas=0**) + `git diff --check` exit 0**;
  elevações nesta correção: **1 (batch unico de validacao SQL + commit + push)**.
- **Não feito (por contrato):** P3 (aprovação/invalidação), P4 (matriz
  `goal.*`, Policy Engine, RLS own-tenant, RPC de leitura), P5 (Edge/cliente),
  P6 (cutover/backfill/frontend), P7 (bateria integrada e concorrência real),
  F5-11, PR e merge.

### 3.14 F5-10 P1 (implementada; correção pós-auditoria GPT aplicada)

- **Atividade:** F5-10 — **P1 (SCHEMA, INTEGRIDADE e LIMITES das metas
  soberanas)** — Issue **#210**. Contrato: `docs/F5-10-desenho-tecnico.md`
  (D1–D25). **Somente a P1**: P2–P7 não iniciadas, **sem PR e sem merge**.
- **Base:** `main` = `e5700e83388eb90ed4aa11f208127a5e2fc3f391`.
  **Branch:** `feat/f5-10-p1-schema-metas`.
- **Entregue:** `supabase/migrations/20260922000000_f5_10_p1_goals_schema.sql`
  (4 tabelas — `evaluation_goals`, `evaluation_goal_approvals` como FATO,
  `evaluation_goal_events` append-only e `evaluation_cycle_goal_limits` como
  autoridade de quota, com invariantes de quota no banco e RLS
  deny-by-default), `supabase/validacao/19-cenario-`/`20-validar-f5-10-p1.sql`
  (testes negativos), regressões de catálogo `02`/`03` (F4-08), guarda de
  anti-antecipação `15` (F5-09 P9 convertida em **lista fechada** da P1),
  `.github/workflows/ci.yml` e `supabase/migrations/README.md`.
- **Correção pós-auditoria** (auditoria GPT do commit `b3b3306`: **2 blockers**):
  (1) `evaluation_goal_approvals` ganhou **`actor_user_profile_id uuid not null`**
  com FK própria para `user_profiles(id)` — além de `actor_membership_id`, que
  segue vinculada ao tenant por FK composta — e o invariante de coerência
  `f5_10_validar_autoria_da_aprovacao` (perfil = perfil da membership no tenant),
  com códigos de erro distintos: 23502 ausente, 23503 inexistente, P0001
  incoerente. Coerência por FK composta exigiria chave nova em
  `user_organization_memberships` (contrato anterior), então **nenhum contrato
  anterior foi alterado** e a solução é o trigger fail-closed. (2)
  `ck_evaluation_goals_fechamento` **endurecido** de "completo" para "coerente":
  `EM_ANDAMENTO` ⇒ fechamento integralmente nulo; `ATINGIDA` ⇒ `atingida = true` +
  `data_fechamento` + `resultado_final` não vazio e `= btrim()`; `NAO_ATINGIDA` ⇒
  `atingida = false` + as mesmas regras — com negativos explícitos de todas as
  combinações contraditórias no validador 20 (bloco D).
- **A P1 não reivindica proteção autônoma de corrida:** o `COUNT` do trigger de
  quota continua sem lock e **nenhuma família de advisory lock nova** foi criada
  (a família `evaluation_cycles:` segue exclusiva das fases seguintes; a P2 traz as
  operações soberanas com lock e a P7 prova a concorrência real).
- **Gates reais (host local):** `db reset` + bateria SQL completa na ordem do CI
  (**35/35 entradas, `falhas=0`**) + `git diff --check` — exit 0.
  `npm test`/`build`/`lint`/`tsc` **não se aplicam** (nenhum arquivo JS/TS
  alterado nesta rodada).
- **Elevações de acesso nesta rodada:** **1** (bateria consolidada: `db reset` +
  validações SQL + `git diff --check` + `commit` + `push`).
- **Não feito (por contrato):** P2–P7, PR, merge e auditoria independente.

### 3.13 F5-09 P9 (implementada; aguardando auditoria independente)

- **Atividade:** F5-09 — **P9 (Validação Integrada de Ciclos Soberanos)
  IMPLEMENTADA** — aguardando auditoria GPT e auditoria independente Codex.
  Contrato: a especificação da atividade (11 blocos obrigatórios) + a matriz
  executável em `docs/F5-09-p9-matriz-integrada.md`.
- **Base:** `main`/`origin/main` = `a1e30a86` (F5-09 P8 integrada pelo squash do
  PR #205). **Branch da P9:** `feat/f5-09-p9-integrated-validation` — **sem
  merge**; o push (feito neste host) e o PR ficam com o usuário.
- **Entregue (7 arquivos):** `supabase/validacao/14-cenario-f5-09-p9.sql` (fixture
  isolada `ed`, insert-once), `15-validar-f5-09-p9.sql` (matriz integrada,
  **42 `[PASS]`**), `16-sessao-a-`/`17-sessao-b-`/`18-validar-`**concorrência**,
  `src/services/ciclosSoberanos/p9MatrizIntegrada.test.ts` (10 provas do cliente),
  `docs/F5-09-p9-matriz-integrada.md`, `.github/workflows/ci.yml` (passos P9 após
  o validador D28 e ANTES das regressões F5-06/F5-07) e `.ai/virtus-context.md`
  (estava desatualizado: dizia "P2–P9 não iniciadas").
- **Bloco 6 — concorrência REAL entre duas sessões:** sessão A (processo `psql`
  próprio) cria o ciclo e o edita segurando `ciclo_lock_organizacao`
  (`evaluation_cycles:<org>`) por ~8 s; sessão B espera deterministicamente a
  marca não transacional publicada DENTRO do UPDATE e tenta a MESMA edição com o
  MESMO `expected_version`: fica **bloqueada ~7,3 s** e termina em
  `F5_09_CONFLICT` (versão 0 vs 1). O estado final é o de A (nenhum lost update),
  nenhum evento da intenção perdedora e trilha `CRIADO + EDITADO` append-only.
  É contenção **server-side**, distinta da concorrência **client-side** da P8
  (geração monotônica do controlador).
- **Gates reais (host local, Docker + Supabase local):** `db reset` +
  **bateria SQL completa na ordem do CI: 33/33 entradas, `falhas=0`** (inclui
  fixture/validador P9, concorrência em duas sessões e todas as regressões
  F4-08/F5-04/F5-08/P1–P7/F5-06/F5-07) + focados **71** + `npm test`
  **120 arquivos / 1860 testes** + `npm run build` + `npm run lint` +
  `npx tsc -b tsconfig.app.json` + `git diff --check` — todos exit 0.
- **Findings (registrados, nenhum de produção):** (a) **defeito de integração**
  real — a checagem de ciclos sem evento `CRIADO` no §11 era GLOBAL e acusava os
  ciclos inseridos diretamente pelas fixtures P1–P5 (que rodam antes no CI):
  passava isolada e **falharia no job**; foi escopada às organizações do fixture
  P9; (b) **14 defeitos de artefato de validação** encontrados por execução real
  (I5 no setup; tabela temporária qualificada como `public.`; `RAISE` com
  placeholders a menos; `string_agg(x, …)` sem a subquery que define `x`;
  colisões de `operation_id` entre intenções diferentes; replay de idempotência
  com payload divergente; precedência estado-antes-de-versão; `NOT_FOUND` ×
  `FORBIDDEN` indistinguíveis no cross-tenant (§8); grant de `cycle.manage` não
  restaurado após a prova de revogação; encerramento ausente entre A5→A3 (I5);
  gatilho de rollback só na 2ª escrita; invariante I5 "no máximo um ATIVO";
  catálogo legado de metas/observações = 8, não 7; contador de escrita não
  transacional); (c) defeito do **harness local** (contador de falhas inflado por
  `Write-Output` dentro de função). **Produção intocada:** nenhuma migration,
  RPC, policy, RLS, Edge ou página foi alterada na P9.
- **Não feito (por contrato):** merge, abertura de PR e auditorias externas.
  **F5-10 (metas) e F5-11 (observações) permanecem pendentes.**

- **Atividade (rodada atual):** F5-09 — **P7 (Edge Function `ciclos` + reconciliação
  do catálogo D28) IMPLEMENTADA** — **aguardando auditoria independente**. Issue
  **#202**. Contrato: `docs/F5-09-desenho-tecnico.md` (§8 tabela
  operação→capability, §13.1 contrato da Edge e regras 1–9, §13.2 assinaturas das
  RPCs, §13.3 reuso obrigatório, §13.5 cliente, §19 P7) e `docs/F5-09-duvidas.md`
  (**D25** uma Edge por domínio, **D26** admissão, **D28** bundle `admin`).
- **Base:** `main`/`origin/main` = `014a7b4303bdcb2887dc0342810e363e2e141527`
  (F5-09 P6 integrada em `main`).
- **Branch da P7:** `feat/f5-09-p7-cycle-edge` — **sem merge**; push/PR ficam com
  o usuário.
- **Entregue nesta rodada (P7):**
  - `src/infrastructure/supabase/ciclos/contrato.ts` (novo): fonte **única** do
    contrato transportável — as 8 operações, o mapa EXPLÍCITO operação → gate
    (`funcional`/`administrativo`) → capability (sem default e sem alias), e a
    validação de FORMA com **allowlist estrita** de chaves por operação;
  - `supabase/functions/ciclos/core.ts` (novo): núcleo testável da fronteira —
    método → JWT (`auth.getUser`) → forma → **tenant revalidado** contra
    membership ativa → **gate** (Policy Engine com recurso real ou plano
    administrativo D19) → **execução privilegiada**; erro de RPC mapeado por
    prefixo `F5_09_*` para código público, com `INTERNAL` como fallback;
  - `supabase/functions/ciclos/index.ts` (novo): wiring Deno — cliente
    `service_role` (executor), `DepsContextoAutorizacao` com
    `carregarRecurso` de **ciclo** (linha real de `evaluation_cycles` com o
    `status` soberano → `domainState` do P6), resolutores da fronteira e dispatch
    das 8 RPCs com o ator verificado e **sem** `p_payload_hash`;
  - `supabase/functions/ciclos/contrato.ts` (novo): reexport do contrato
    compartilhado (estrutura `index`/`core`/`contrato` como nas demais Edges);
  - `src/infrastructure/supabase/ciclos/edgeCiclos.ts` (novo): adapter de cliente
    (8 métodos) que envia apenas INTENÇÃO e é fail-closed (erro de transporte,
    `error` no corpo, 2xx fora do contrato e código desconhecido NÃO viram
    sucesso);
  - `supabase/migrations/20260921000000_f5_09_p7_catalog_admin_bundle.sql`
    (**D28**): `cycle.manage` entra **aditivamente** no bundle `admin`
    (`+1` exato, idempotente), com preflight/guarda final fail-closed provando
    catálogo intacto, `cycle.read` preservada e as três excepcionais fora de
    qualquer role;
  - `supabase/validacao/11-validar-f5-09-p7.sql` (novo): bundle `admin` = 9
    funcionais com `cycle.manage`, excepcionais fora, catálogo com 31 códigos,
    descrição de `cycle.cancel` (P6), RLS own-tenant + escrita fechada +
    `cycle_events` deny-by-default (P5) e as 8 RPCs `INVOKER` com `EXECUTE` só
    `service_role` (P2–P4);
  - testes: `src/authorization/ciclosEdge.test.ts` (cobertura A–R: happy path das
    8 operações, UUID real como alvo, cross-tenant/IDOR, membership/perfil/
    identidade, capability/scope, campos textuais de autoridade, alvo
    malformado/sintético, `service_role` só após o gate, ausência de matriz de
    lifecycle e idempotência por `operationId`),
    `src/authorization/ciclosContratoRpc.test.ts` (contrato Edge → RPC com nomes e
    argumentos EXATOS + guard de que **toda** função chamada existe no schema,
    D28 estrito e nenhuma capability nova) e
    `src/infrastructure/supabase/ciclos/edgeCiclos.test.ts` (adapter do cliente);
  - adaptações explícitas de contrato antigo (D28): `02-validar-f5-04.sql` e
    `02-validar-f4-01.sql` passam a esperar **9** capabilities no bundle `admin`
    (com `cycle.manage`), mantendo as proibições de controle/deprecado/
    confidencial;
  - `.github/workflows/ci.yml` (validador P7 no job `supabase-local`, após o par
    P5 e antes das regressões F5-06/F5-07), `supabase/migrations/README.md` e este
    arquivo.
- **Arquitetura final da Edge:** request → `OPTIONS`/`POST` (405 fora disso) →
  `Authorization` obrigatório (401) → `auth.getUser` (401) → forma da intenção
  (400, allowlist estrita) → tenant do corpo revalidado contra a identidade
  (403/401) → gate por operação → RPC `ciclo_*` com `service_role` e ator
  verificado → resposta `{ok, operacao, resultado}` com erro público.
  `service_role` **executa**, nunca decide: nenhum caminho alternativo existe e o
  JWT do usuário não é propagado.
- **Correção pós-auditoria Codex (D28, mesma rodada):** as guardas da migration
  `20260921000000` foram restringidas ao **tipo de role** — as três excepcionais
  ficam proibidas apenas em roles **DE SISTEMA** (`is_system = true`) e seguem
  **concedíveis** em roles **CUSTOMIZADAS** (contrato D28/Q-F5-09-3); a migration
  passou a ser **realmente idempotente** (`v_ja_existia`: +1 só na primeira
  execução, 0 na reexecução, com prova de relação única e bundle no tamanho
  esperado). Provas automatizadas: `12-cenario/13-validar-f5-09-p7-d28.sql`
  (A–H, incluindo role customizada aceita, role de sistema recusada pelo
  predicado, primeira execução +1, reexecução sem duplicata e catálogo intacto) e
  a reaplicação da migration (2×) no job `supabase-local` do CI.
- **Operações expostas (8) e RPC de cada uma:** `cycle.criar`→`ciclo_criar`
  (plano administrativo, sem alvo sintético — D21); `cycle.editar`→`ciclo_editar`;
  `cycle.ativar`→`ciclo_ativar`; `cycle.encerrar`→`ciclo_encerrar`;
  `cycle.cancelar`→`ciclo_cancelar`; `cycle.reabrir`→`ciclo_reabrir`;
  `cycle.corrigir_periodo`→`ciclo_corrigir_periodo`;
  `cycle.admissao.incluir`→`ciclo_incluir_admissao` (matrícula resolvida na
  fronteira pela ponte F3-01; campos estruturais recusados — §13.1 regra 9).
- **D28:** bundle `admin` = 9 capabilities funcionais (`collaborator.create/edit/
  read`, **`cycle.manage`**, `cycle.read`, `membership.read`,
  `org.catalog.manage`, `org.structure.manage`, `settings.manage`);
  `cycle.cancel`/`cycle.reopen`/`cycle.period.correct` **não** estão em nenhuma
  role (configuração explícita apenas).
- **Gates reais desta rodada:** `supabase db reset --local --yes` (migration D28
  aplicada) + **suíte SQL completa na ordem do CI, 25 arquivos, ZERO `[FAIL]`** +
  `npm test`, `npm run build`, `npm run lint`, `npx tsc -b tsconfig.app.json`,
  `git diff --check` e `git status --short` — todos exit 0.
- **Limitações/desvios declarados:** (a) a Edge expõe SOMENTE as 8 operações de
  MUTAÇÃO contratadas — a **leitura/listagem** continua no contrato soberano
  P5/P6 (PostgREST + RLS), porque **não existe RPC de leitura** (`ciclo_painel`/
  `ciclo_historico` não foram criadas em P2–P5) e criar RPC nova não é superfície
  da P7; a pendência da F5-07 (§13.6, `ciclo_listar_colaborador_por_ciclo`)
  permanece aberta; (b) `cycle.editar` exige o período COMPLETO (ano, número,
  datas) porque a RPC `ciclo_editar` não aceita edição parcial — a fronteira não
  faz merge de domínio (§13.1 marcava os campos como opcionais: o contrato real da
  RPC prevalece); (c) `p_payload_hash` não é enviado (hash derivado server-side,
  desvio já declarado em P2–P4); (d) o fluxo LOCAL legado de ciclo
  (`cicloAvaliacaoStorage`) segue intacto — a substituição pela Edge é o cutover
  P8.
- **Permanece para P8+:** cutover de páginas/consumidores e remoção da autoridade
  local de ciclo (P8), validação integrada/concorrência (P9), F5-10 metas e
  F5-11 observações.

### 3.12 F5-09 P6 (implementada; aguardando auditoria independente)

- **Atividade:** F5-09 — **P6 (fechamento do Policy Engine para
  ciclos soberanos) IMPLEMENTADA** — **aguardando auditoria independente**.
  Issue **#200**. Contrato: `docs/F5-09-desenho-tecnico.md` (§8 tabela
  operação→capability + fechamentos aditivos, §16 R13/R17, §19 P6) e
  `docs/F5-09-duvidas.md` (**D8/Q-F5-09-1**, D20, D21, D22 — D28 permanece **P7**).
- **Base:** `main`/`origin/main` = `79203c7fb4e45c9f9cf002e23633f2e4d4abdb5a`
  (F5-09 P5 integrada em `main`).
- **Branch da P6:** `feat/f5-09-p6-cycle-policy-engine` — **sem merge**; push/PR
  ficam com o usuário.
- **Entregue nesta rodada (P6):**
  - `src/authorization/estadoDominioCiclo.ts` (novo): fonte **ÚNICA** da matriz de
    estado do ciclo — `cycle.read` = ciclo real carregado (qualquer status);
    `cycle.manage`/`cycle.cancel` = `PLANEJADO` ou `ATIVO`; `cycle.reopen` =
    `ENCERRADO`; `cycle.period.correct` = `ATIVO`; `CANCELADO` nega as mutações e
    mantém a leitura; status ausente/fora do domínio nega tudo; capability fora
    da matriz é negada (fail-closed);
  - `src/authorization/authorizationPolicy.ts`: o `case "cycle"` passa a decidir
    as **cinco** capabilities (antes `cycle.read`/`cycle.manage` caíam em
    `default → null ⇒ DENY`) sobre o alvo real `{type:"cycle", id: UUID}` com a
    matriz compartilhada; `cycle.cancel` ampliado para `{PLANEJADO, ATIVO}` (D8);
    recurso sem identidade de ciclo é fail-closed; o caso `global` permanece
    apenas como compatibilidade de UX/navegação — **nenhuma** capability de ciclo
    é decidida sobre `{type:"cycle", id:"global"}`;
  - `src/authorization/ResourceContext.ts`: `CycleResource.cycle` passa a ser a
    projeção **mínima** `CicloParaAutorizacao` (`id` = UUID canônico + `status`),
    satisfeita estruturalmente por `CicloSoberano` (P5) **e** por
    `CicloAvaliacao` (legado) — sem entidade nova e sem campo de tenant/identidade
    inventado (o tenant, no enforcement, vem da linha soberana);
  - `src/authorization/resourceContextReal.ts`: `cycle` entra em
    `TIPOS_RECURSO_SOBERANOS` (a P5 deu persistência server-side + RLS),
    passa a exigir identificador **UUID canônico** (`IDENTIFICADOR_INVALIDO` /
    `TARGET_NAO_SOBERANO`) e o `cycleId` do contexto passa a ser o próprio ciclo;
    meta/observação permanecem fora do limite soberano;
  - `src/authorization/contextoAutorizacao.ts`: no alvo `cycle` o `domainState`
    vem **sempre** do status da LINHA SOBERANA carregada (`recurso.status`) —
    estado declarado pelo chamador é ignorado (o legado não suplanta o caminho
    soberano);
  - `supabase/migrations/20260920000000_f5_09_p6_cycle_cancel_description.sql`:
    atualização aditiva da descrição de `cycle.cancel` (D8), com preflight e
    guarda final fail-closed (sem capability nova, sem bundle/role, sem
    schema/RLS/RPC);
  - testes: `src/authorization/ciclosPolicyEngine.test.ts` (matriz
    capability × status × aliases, alvo real, guardas estáticos de fonte única e
    de alvo sintético) e `src/authorization/ciclosFronteiraSoberana.test.ts`
    (fronteira real: UUID canônico, tenant divergente, membership
    revogada/ausente, perfil inativo, ator inexistente, capability
    ausente/revogada, scope insuficiente, alvo sintético/inválido, estado
    soberano prevalecendo e cargo/função textual sem efeito);
  - adaptações explícitas de contrato antigo: `src/authorization/actorContext.test.ts`
    (ciclo agora soberano + UUID obrigatório), `src/authorization/authorizationPolicy.test.ts`
    (`cycle.cancel` em `PLANEJADO` **e** `ATIVO`; `ENCERRADO` negado),
    `src/pages/CiclosAvaliacaoPage.test.tsx` (o botão de cancelamento passa a
    aparecer para ciclo `PLANEJADO` — efeito direto de D8) e
    `src/services/cancelamentoCicloService.test.ts` (a recusa de `PLANEJADO`
    deixou de ser da autorização e passou a ser do domínio LOCAL legado);
  - `supabase/migrations/README.md` e este arquivo.
- **Matriz final das 5 capabilities (P6):** `cycle.read` — ciclo real do tenant,
  qualquer status (inclusive `CANCELADO`); `cycle.manage` — `PLANEJADO`/`ATIVO`
  (o recorte por operação — editar/ativar/encerrar/admitir — segue revalidado nas
  RPCs, §8); `cycle.cancel` — `PLANEJADO`/`ATIVO` (D8); `cycle.reopen` —
  `ENCERRADO`; `cycle.period.correct` — `ATIVO`; `CANCELADO` nega as quatro
  mutações.
- **Gates reais desta rodada:** `supabase db reset --local --yes` (migration P6
  aplicada) + **suíte SQL completa na ordem do CI (24 arquivos, ZERO `[FAIL]`**;
  F4-08 57+9, F5-04 26, F5-08 58+13, F5-09 P1 62, P2 22, P3 18, P4 22, P5 11,
  F5-06 27+14, F5-07 45+23) + `npm test`, `npm run build`, `npm run lint`,
  `npx tsc -b tsconfig.app.json`, `git diff --check` (todos exit 0).
- **Resíduo declarado (P8):** o persistidor **local** legado
  (`cicloAvaliacaoStorage`) ainda exige `ATIVO` para cancelar, então o botão de
  cancelamento exibido para ciclo `PLANEJADO` (autorização já conforme D8) só se
  torna efetivo no cutover P8, quando o fluxo passa a usar a RPC soberana
  `ciclo_cancelar`. O `excluirCiclo` físico local também permanece (D9 proíbe
  exclusão; a auditoria já o classifica como resíduo CRITICAL do P8).
- **Permanece para P7+:** Edge Function `ciclos` + contratos Edge +
  reconciliação aditiva do catálogo (D28: `cycle.manage` no bundle `admin`),
  cutover de páginas/remoção da autoridade local (P8), validação integrada (P9) e
  F5-10/F5-11.

### 3.11 F5-09 P5 (implementada; aguardando auditoria independente)

- **Atividade:** F5-09 — **P5 (leitura soberana de ciclos por RLS
  own-tenant + porta do cliente) IMPLEMENTADA** — **aguardando auditoria
  independente**. Issue **#198**. Contrato: `docs/F5-09-desenho-tecnico.md`
  (§9 policy de leitura, §13.5 superfícies do cliente, §19 P5) e
  `docs/F5-09-duvidas.md` (**D22**).
- **Base:** `main`/`origin/main` = `2e9c2012da8e24995a7ad1dc5e006dcb19475469`
  (F5-09 P4 integrada em `main`).
- **Branch da P5:** `feat/f5-09-p5-cycle-sovereign-read` — **sem merge**; o push do
  sandbox é bloqueado (`.ai/git-rules.md`), então push/PR ficam para o usuário.
- **Entregue nesta rodada (P5):**
  - `supabase/migrations/20260919000000_f5_09_cycle_read_rls.sql`: **RLS de
    leitura** — `enable row level security` em `evaluation_cycles`, policy
    `evaluation_cycles_select_same_tenant` (SELECT para `authenticated` com
    `public.user_has_active_membership(organization_id)`) e `grant select`
    **mínimo** (policy antes do grant). Escrita do cliente **fechada**, `anon` sem
    privilégio, `cycle_events` deny-by-default, nenhuma RPC/capability nova
    (catálogo segue em 31), preflight e guarda final fail-closed.
  - `supabase/validacao/09-cenario-f5-09-p5.sql` (fixture **ISOLADA**, prefixo
    `ec`) e `10-validar-f5-09-p5.sql` (seções **A–K**: own-tenant, cross-tenant e
    IDOR por UUID, sem membership, membership/perfil revogados, JWT fantasma,
    DML negado com `insufficient_privilege`, conformidade de policy/grant,
    `cycle_events` fechado e regressões P1–P4).
  - adaptações de regressão: `02-validar-f4-08.sql` (`evaluation_cycles` passa de
    tabela **fechada** a **legível own-tenant**: listas, contagens e mensagens
    atualizadas), `04-validar-f5-09-p2.sql`, `06-validar-f5-09-p3.sql` e
    `08-validar-f5-09-p4.sql` (admitem a policy do P5 quando **conforme**; seguem
    proibindo RPC de leitura, policy de escrita e leitura por `anon`) e
    `02-validar-f5-06.sql` (a checagem "zero policies nas tabelas F5-06" passa a
    admitir **apenas** a policy de SELECT own-tenant de `evaluation_cycles`; a
    deny-by-default das demais tabelas F5-06 e qualquer policy de escrita
    continuam falha).
  - cliente: `src/application/ports/CycleRepository.ts` (porta **assíncrona** e
    **UUID-first**, resultado discriminado com código público),
    `src/infrastructure/supabase/ciclos/repositorioCiclosSoberanos.ts` (adapter de
    RLS; sessão como **pré-condição** → `NOT_AUTHORIZED`, erro → `FORBIDDEN`/
    `INTERNAL`, linha fora do contrato — **ou de outro tenant** — descartada:
    defesa em profundidade na projeção, já que a RLS é quem isola o tenant),
    `src/services/acessoCiclosSoberanos.ts` (porta única + cache de UX por
    **geração monotônica**: troca de organização/unmount/logout descartam resposta
    em voo) e `src/infrastructure/localStorage/localCycleRepository.ts`
    (**LEGACY/transitório**, `version: 0`, explicitamente **não** é fallback).
  - testes do cliente: adapter, porta/serviço (fail-closed, resposta atrasada,
    organização errada) e **guarda estática** anti-fallback/anti-dual-read, com o
    teste legado reescrito para o contrato assíncrono.
  - `.github/workflows/ci.yml` (o job `supabase-local` executa 09/10 após 07/08 e
    antes das regressões F5-06/F5-07), `supabase/migrations/README.md` e este
    arquivo.
- **Comportamento entregue:** `evaluation_cycles` passa a ser a **fonte de verdade
  de leitura** para o tenant do usuário autenticado: a RLS devolve somente ciclos
  da organização com membership ativa e perfil ativo; o filtro por
  `organization_id` no cliente é apenas **defesa em profundidade** (intenção de
  UX); ausência é **explícita** (`null`/lista vazia) e falha tem **código
  público** — nunca fallback local, dual-read ou dado inventado; `(ano, numero)`
  seguem apenas como **rótulos** (bridge transitória documentada para o cutover do
  P8). **Nenhuma página/componente foi alterado** nesta fase.
- **Gates reais desta rodada:** `supabase db reset` + trio F4-08 + cenário 09 +
  validador 10 (**todas as seções A–K `[PASS]`, zero `[FAIL]`**) + suíte SQL
  completa na ordem do CI (24 arquivos, **ZERO `[FAIL]`**) + `npm test`/
  `npm run build`/`npm run lint`/`npx tsc -b tsconfig.app.json`/
  `git diff --check`, todos exit 0.
- **Permanece para P6+:** Policy Engine `cycle.read`/`cycle.manage` (P6), Edge
  `ciclos` + reconciliação de catálogo/bundle (P7), cutover do frontend e remoção
  do storage local (P8), validação integrada (P9) e soberania de metas/observações
  (F5-10/F5-11).

### 3.10 F5-09 P4 (implementada; aguardando auditoria independente)

- **Atividade:** F5-09 — **P4 (transições excepcionais soberanas:
  cancelar, reabrir e corrigir período) IMPLEMENTADA** — **aguardando auditoria
  independente**. Issue **#194**. Contrato: `docs/F5-09-desenho-tecnico.md`
  (§6 T4/T5/T6/T7, §8 autorização, §10 I7/I8/I11/I12/I19, §11, §12, §13.2/§13.3,
  §19 P4) e `docs/F5-09-duvidas.md` (D1–D28; **D8/D9**, D10–D15 e D20/D21 em
  especial).
- **Base:** `main`/`origin/main` = `c804903d84c5dd6def690137f0ec286bc06ad56e`
  (F5-09 P3 integrada pelo squash do PR #193).
- **Branch da P4:** `feat/f5-09-p4-cycle-exceptional-transitions` — **sem
  merge**; o push do sandbox é bloqueado (`.ai/git-rules.md`), então push/PR ficam
  para o usuário.
- **Entregue nesta rodada (P4) — 6 arquivos:**
  - `supabase/migrations/20260918000000_f5_09_cycle_exceptional_transitions.sql`:
    `ciclo_cancelar` (T4/T5, `cycle.cancel`), `ciclo_reabrir` (T6,
    `cycle.reopen`) e `ciclo_corrigir_periodo` (T7, `cycle.period.correct`),
    todas `SECURITY INVOKER`, `search_path` fixo, `EXECUTE` só `service_role`,
    ACL revogada de `public`/`anon`/`authenticated`, preflight fail-closed do
    baseline e guarda final fail-closed;
  - `supabase/validacao/07-cenario-f5-09-p4.sql` (fixture **ISOLADA**, prefixo
    `eb`, insert-once) e `08-validar-f5-09-p4.sql` (todos os casos obrigatórios da
    P4, incluindo **4 probes cross-tenant diretos** por RPC e **rollback real em
    quatro fases**);
  - `.github/workflows/ci.yml` (o job `supabase-local` executa 07/08 após 05/06 e
    antes das regressões F5-06/F5-07);
  - `supabase/migrations/README.md` (registro da migration) e `.ai/handoff.md`.
- **Comportamento entregue:**
  - **cancelar** — `PLANEJADO`|`ATIVO` → `CANCELADO` (terminal; D8). Em `ATIVO`
    resolve na MESMA transação as avaliações **não concluídas** reusando
    `evaluation_cancelar` (F5-06) e **preserva** as `CONCLUIDA` (e as já
    `CANCELADA`, sem reescrever motivo/data). Em `PLANEJADO` exige que as
    avaliações tenham sido resolvidas antes (fail-closed) e não cria nada.
    Retorno: `cycle_id`, `status`, `version`, `avaliacoes_canceladas`,
    `avaliacoes_concluidas_preservadas`; evento `CANCELADO` com before/after e
    contagens. Nenhum `DELETE` (D9) e snapshots intocados.
  - **reabrir** — somente `ENCERRADO` → `ATIVO`, com motivo, sem outro `ATIVO`
    (I5/D14) e sem sobreposição com ciclos não cancelados (I6/D15). **Sem
    rematerialização**: nenhuma escrita em snapshots/posições/membros/
    responsabilidades/participantes e nenhuma chamada a F3-08/F3-09; **não cria
    avaliações**. Altera apenas `status`, `data_encerramento=null` e `version+1`,
    **preservando** `data_ativacao` e os contadores de pendência (histórico
    íntegro na trilha); evento `REABERTO`.
  - **corrigir período** — só `ATIVO`; `data_inicio <= data_fim`, período
    diferente do atual, `justificativa` obrigatória e sem sobreposição. Não toca
    estrutura/gestores/colegiado/participantes/responsabilidades. **Impacto
    calculado server-side** (o cliente não declara impacto): datas anterior/nova,
    `dias_antes`/`dias_depois`/`dias_delta`, `avaliacoes_no_ciclo`,
    `avaliacoes_concluidas`, `avaliacoes_nao_concluidas`,
    `avaliacoes_concluidas_fora_do_novo_periodo` e `participantes_materializados`;
    evento `PERIODO_CORRIGIDO` com before/after + `impacto` + justificativa.
- **Auditoria do ponto crítico de `version` (double increment):**
  `evaluation_cancelar` (F5-06) incrementa apenas `evaluations.version` e **não**
  toca `evaluation_cycles.version`; `evaluation_fechar_ciclo_pendencias` (que
  incrementa a versão do ciclo) **não** é usada por nenhuma RPC da P4 (a guarda
  final da migration reprova se for). Logo cada RPC incrementa a versão do ciclo
  exatamente uma vez (`expected_version + 1`), como na P2/P3.
- **Desvios mínimos declarados (documentados no header da migration):**
  (a) `p_payload_hash` **não** é parâmetro (mesmo desvio aceito na P2/P3: hash
  canônico derivado server-side); (b) o evento da correção é **`PERIODO_CORRIGIDO`**
  (e não `CORRECAO_PERIODO`): o §12 fixa esse tipo e o CHECK **fechado** de
  `cycle_events.event_type` (P1) só aceita esse nome — usar outro reabriria
  contrato congelado; (c) `ciclo_reabrir` limpa `data_encerramento` (T6) e
  **preserva** os contadores de pendência, com o histórico do encerramento
  integral na trilha append-only.
- **Nota de implementação (fail-closed defensivo):** o ramo "ciclo `PLANEJADO`
  com avaliações" do cancelamento é **inalcançável pelo caminho soberano** (a
  F3-08 só materializa na ativação e a F5-06 exige o snapshot do ciclo); ele é
  exercitado no validador por **estado sintético explícito** (materialização
  direta da estrutura) para provar que a RPC recusa mesmo assim.
- **Gates reais desta rodada (Docker Desktop acessível):** `supabase db reset` +
  cenário 07 + validador 08 (**16 `[PASS]`, 0 `[FAIL]`**) + suíte SQL completa na
  ordem do CI (22 arquivos, **ZERO `[FAIL]`**) + `npm test`/`npm run build`/
  `npm run lint`/`npx tsc -b tsconfig.app.json`/`git diff --check`, todos exit 0.
- **Limitações reais:** a contenção entre DUAS sessões segue não provável no
  validador de sessão única (coberta por lock estrutural + `expected_version`);
  o cenário é **insert-once** e exige `db reset` para nova execução limpa; o
  estado "ENCERRADO sobreposto" é **inalcançável por construção** (a exclusion I6
  recusa a criação sobreposta, provado no validador), então o ramo de
  sobreposição da reabertura é defesa em profundidade; a transição para
  `CONCLUIDA`/`PRONTA_PARA_FEEDBACK` das avaliações de fixture é feita por
  `UPDATE` direto (a completude de notas da F5-06 não é o objeto da P4).
- **Permanece para P5+:** leitura RLS + porta do cliente (P5), Policy Engine
  `cycle.read`/`cycle.manage` + `cycle.cancel`/`cycle.reopen`/
  `cycle.period.correct` (P6), Edge `ciclos` + reconciliação do bundle `admin`
  (P7), cutover do frontend (P8) e validação integrada (P9).

### 3.9 F5-09 P3 (integrada pelo squash do PR #193)

- **Atividade:** F5-09 — **P3 (inclusão aditiva soberana de nova
  admissão em ciclo `ATIVO`) IMPLEMENTADA** — **aguardando auditoria
  independente**. Contrato: `docs/F5-09-desenho-tecnico.md` (§6 nota da inclusão
  aditiva, §7.2 provas P1–P7, §7.3 contrato restrito, §10 I17–I19, §11/§12,
  §13.2/§13.3, §15.1 A1–A12, §19 P3) e `docs/F5-09-duvidas.md` (D1–D28
  ratificadas; **D26/D27** em especial).
- **Base:** `main`/`origin/main` = `c0b9375bc54d58a815e78ed6f332735e3f530d83`
  (F5-09 P2 integrada pelo squash do PR #191).
- **Branch da P3:** `feat/f5-09-p3-cycle-admission` — **sem merge**; o push do
  sandbox é bloqueado (`.ai/git-rules.md`), então push/PR ficam para o usuário.
- **Entregue nesta rodada (P3) — 6 arquivos:**
  - `supabase/migrations/20260917000000_f5_09_cycle_admission.sql`: helper
    **read-only** `ciclo_admissao_pos_ativacao_elegivel` (provas **P1–P7**
    fail-closed, com **motivo de recusa por prova** e evidências da estrutura
    resolvida) + RPC `ciclo_incluir_admissao` (contrato restrito, **sem** nenhum
    parâmetro estrutural), ACL `EXECUTE` só `service_role`, preflight de baseline
    e guarda final fail-closed;
  - `supabase/validacao/05-cenario-f5-09-p3.sql` (fixture **ISOLADA**, prefixo
    `ea`, insert-once, com atores/organizações/estrutura próprios) e
    `06-validar-f5-09-p3.sql` (28 casos obrigatórios + A1–A12, incluindo **4
    probes cross-tenant DIRETOS** na nova RPC e **rollback real em 3 fases**);
  - `.github/workflows/ci.yml` (job `supabase-local` executa 05/06 **após** 03/04
    e **antes** das regressões F5-06/F5-07);
  - `supabase/migrations/README.md` (registro da migration) e `.ai/handoff.md`.
- **Invariantes centrais da P3 (D26/D27):** a operação é a **única** ampliação de
  população depois da ativação e é **exclusivamente aditiva** — nenhum
  snapshot/posição/membro/responsabilidade existente é alterado ou removido (a
  RPC delega a F3-08/F3-09, que só inserem, e não aceita parâmetro estrutural);
  prova soberana de admissão revalidada server-side e **fail-closed**
  (`collaborators.admission_date` **não** é prova; legado/importado sem evento
  `ADMISSAO` é **recusado** — a correção é no caminho de importação); autorização
  e tenant sempre do ator verificado (`cycle.manage` **reusada**, nenhuma
  capability nova; `service_role` executa e não decide); lock normativo
  `evaluation_cycles:<organization_id>` (`ciclo_lock_organizacao`) +
  `expected_version` + idempotência por `(organization_id, operation_id)` com
  hash **derivado server-side**; **um** evento append-only `ADMISSAO_INCLUIDA`
  por mutação, com o **id do evento `ADMISSAO`** que autorizou; movimentação
  posterior **não** rematerializa o ciclo (D27).
- **Desvios mínimos declarados (vs §13.2, documentados no header da migration):**
  (a) `p_payload_hash` **não** é parâmetro (mesmo desvio já aceito na P2: o hash
  é derivado server-side dos parâmetros validados; aceitá-lo permitiria replay
  com hash forjado); (b) a inclusão incrementa `evaluation_cycles.version` **uma
  vez** — o §6 registra que a inclusão **não** é transição de estado, e é o que se
  cumpre (status, datas e contadores de pendência inalterados), mas a população
  materializada muda: sem o incremento o `expected_version` do §13.2 e o campo
  `version` do `after_value` (§12) ficariam degenerados; (c) **nenhum** helper
  novo de materialização — a F3-08 já aceita a menor granularidade segura
  (`array[collaborator_id]`, `on conflict do nothing`) e a F3-09 é idempotente por
  `(snapshot, posição)`; (d) **P6 aplicado de forma estrita**: a presença de
  qualquer evento `ADMISSAO` com `SOMENTE_CICLOS_POSTERIORES` recusa a inclusão
  no ciclo corrente (a operação não escolhe entre evidências conflitantes).
- **Gates reais desta rodada (Docker Desktop acessível):** `supabase db reset` +
  cenário 05 + validador 06 (**19 `[PASS]`, 0 `[FAIL]`**) + suíte SQL completa na
  ordem do CI + `npm test`/`npm run build`/`npm run lint`/`npx tsc -b
  tsconfig.app.json`/`git diff --check`, todos exit 0 (detalhes no PR).
- **Limitações reais:** a contenção entre DUAS sessões segue não provável no
  validador de sessão única (coberta por lock estrutural + `expected_version` +
  P3 de aditividade); o cenário é **insert-once** (trilha append-only) e exige
  `db reset` para nova execução limpa; o colegiado do colaborador admitido é
  **autorado como fixture** no validador, porque o caminho soberano da F5-08 para
  colegiado exige a capability `org.structure.manage` **com scope ativo** — fora
  do escopo da P3.
- **Permanece para P4+:** cancelar (T4/T5), reabrir (T6), corrigir período (T7),
  leitura RLS + porta do cliente (P5), Policy Engine `cycle.read`/`cycle.manage`
  (P6), Edge `ciclos` + reconciliação do bundle `admin` (P7), cutover (P8) e
  validação integrada (P9).

### 3.8 F5-09 P2 (integrada pelo squash do PR #191)

- **Atividade:** F5-09 — **P2 (RPCs soberanas de gestão de ciclo)
  IMPLEMENTADA** — **aguardando auditoria independente**. Contrato:
  `docs/F5-09-desenho-tecnico.md` (§6 T0–T3, §8, §10–§13, §19 P2; D1–D28
  ratificadas) e `docs/F5-09-duvidas.md`.
- **Base:** `main`/`origin/main` = `ccc10b8a468ae2ceee8121634bdca38141df81b6`
  (F5-09 P1 integrada pelo squash do PR #190).
- **Branch da P2:** `feat/f5-09-p2-cycle-management-rpcs` — **sem merge**; o
  push/PR do sandbox é bloqueado (`.ai/git-rules.md`), então o push/PR fica para
  o usuário.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Entregue nesta rodada (P2) — 6 arquivos:**
  - `supabase/migrations/20260916000000_f5_09_cycle_rpc.sql`: RPCs
    `ciclo_criar` (T0), `ciclo_editar` (T1), `ciclo_ativar` (T2) e
    `ciclo_encerrar` (T3), todas `SECURITY INVOKER`, `search_path = public`,
    `EXECUTE` só `service_role`; preflight fail-closed das primitivas da P1 e dos
    contratos F3-08/F3-09/F5-06; guarda final fail-closed;
  - `supabase/validacao/03-cenario-f5-09-p2.sql` (fixture insert-once, prefixo
    `e9`: 2 orgs, 4 atores, estrutura relacional, colegiado do avaliado) e
    `04-validar-f5-09-p2.sql` (testes A–W do §11 da rodada);
  - `.github/workflows/ci.yml` (job `supabase-local` executa 03/04 após 01/02);
  - `supabase/migrations/README.md` (registro da migration; **heading
    `## Plataforma e ferramentas` restaurado** — havia sido perdido no commit da
    P1) e `.ai/handoff.md` (este registro).
- **Invariantes da P2:** autorização sempre server-side
  (`ciclo_ator_valido` = ator + membership ativa + `cycle.manage` efetiva);
  idempotência por `(organization_id, operation_id)` + hash canônico **derivado
  server-side** (`cycle_events.payload_hash`); serialização pela chave normativa
  `evaluation_cycles:<organization_id>` (`ciclo_lock_organizacao`, P1);
  `expected_version` com CONFLICT; um único `ATIVO` por organização (I5) e
  não sobreposição (I6) da P1 como barreira final; materialização inicial
  **F3-08 + F3-09** na ativação (população elegível = colaboradores com status
  `active` vigente no instante; hierarquia sempre relacional); encerramento
  **reusa** `evaluation_fechar_ciclo_pendencias` (F5-06) sem duplicar lógica;
  **um evento append-only por mutação** (`CRIADO`/`EDITADO`/`ATIVADO`/
  `ENCERRADO`) com autoria soberana; atomicidade total (falha ⇒ rollback).
- **Desvios mínimos declarados (vs §13.2/§6/T2, documentados na migration):**
  (a) `p_payload_hash` **não** é parâmetro — o padrão soberano do projeto deriva
  o hash dos parâmetros validados (aceitá-lo permitiria replay com hash forjado);
  (b) `ciclo_encerrar` incrementa `version` **uma vez** (a F5-06 já incrementa ao
  gravar pendências) ⇒ resultado = `expected_version + 1`;
  (c) `reference_date` da materialização é o **instante** da ativação (o
  parâmetro da F3-08 é `timestamptz`; o §6/T2 escrevia `data_ativacao::date`).
- **Correção pós-CI #204 (somente no validador):** o teste **J** falhava com
  `[FAIL] J: a falha injetada na materializacao nao abortou a ativacao` porque
  rodava com **C1 ainda ATIVO**: `ciclo_ativar` recusava por I5/D14 (um único
  `ATIVO` por organização) **antes** da materialização, de modo que o gatilho
  injetado nunca era atingido — o teste não maquiava o erro (assertava a mensagem
  `MUT_F5_09_P2`), por isso falhava corretamente em vez de passar em falso.
  Correção **restrita a `supabase/validacao/04-validar-f5-09-p2.sql`**: as 4 RPCs,
  a regra de ciclo único ATIVO, a ordem validação→materialização, a migration e
  D1–D28 **não** foram tocadas. A prova de rollback do **encerramento** (O) passou
  a rodar sobre **C1** (o ciclo legitimamente ATIVO/version 2 da fixture), M/N
  encerra C1 e, **só então**, **J** roda sobre **C3** (2030/3), quando a
  organização já não tem ciclo ATIVO — a única pré-condição legítima para a
  ativação alcançar a materialização. J ganhou duas fases de falha injetada:
  **J.1** aborta na **2ª linha** do `INSERT` em `collegiate_cycle_snapshots`
  (contador por `SEQUENCE` não transacional, lido **depois** do rollback: prova de
  que havia trabalho parcial realmente executado) e **J.2** aborta no `INSERT` de
  `cycle_evaluation_responsibilities`, com o F3-08 já materializado; em seguida
  prova-se o rollback total (`PLANEJADO`, `data_ativacao` nula, version 0, zero
  snapshot/posição/membro/responsabilidade, zero evento) e a ativação legítima
  posterior (4 snapshots + responsabilidades + evento `ATIVADO`). Revisão
  preventiva da **mesma classe de pré-condição**: O e M/N dependiam de C3 estar
  ATIVO (que J, quebrado, nunca ativava) e agora operam sobre C1 com guarda de
  pré-condição explícita; R, P/Q, U, S/T e W foram conferidos e são independentes
  de ordem/estado `ATIVO`.
- **Limitações reais da rodada:** com o Docker Desktop disponível, a suíte SQL
  local completa foi executada neste host (`db reset` + os 18 arquivos de
  `supabase/validacao/` na ordem do CI, incluindo P1 e P2): **0 `[FAIL]`**, todos
  os arquivos com exit 0, e o validador P2 com 16 `[PASS]` (J.1 abortando na 2ª
  linha do `INSERT` de snapshots e J.2 no `INSERT` de responsabilidades); a
  **contenção real entre DUAS sessões** continua não provável no validador de
  sessão única (provado por lock estrutural + `expected_version` + I5, com a
  limitação registrada no §U); o cenário é **insert-once** (a trilha é append-only
  protegida) e o validador exige `db reset` para nova execução limpa.
- **Permanece para P3+:** admissão durante ciclo ativo (P3), cancelar/reabrir/
  corrigir período (P4), leitura RLS + porta do cliente (P5), Policy Engine
  `cycle.read`/`cycle.manage` (P6), Edge `ciclos` + reconciliação do bundle
  `admin` (P7), cutover do frontend/localStorage (P8) e validação integrada (P9).

### 3.7 F5-09 P1 (integrada pelo squash do PR #190)

- **Entregue na P1 — 5 arquivos:**
  - `supabase/migrations/20260915000000_f5_09_cycle_sovereign.sql`: **I5** índice
    único parcial `uq_evaluation_cycles_org_ativo` (um ciclo `ATIVO` por
    organização); **I6** exclusion parcial
    `ex_evaluation_cycles_periodo_no_overlap`
    (`daterange(data_inicio, data_fim + 1, '[)')` — `data_fim` inclusiva para o
    produto —, com `CANCELADO` e linhas sem período fora do índice); `DELETE` e
    `TRUNCATE` de `evaluation_cycles` revogados de
    `public`/`anon`/`authenticated`/`service_role` (**D8/D9** — exclusão física
    proibida em todos os estados); trilha append-only **`cycle_events`** (FK
    composta `(cycle_id, organization_id)`, FK composta de autoria, `unique
    (organization_id, operation_id)` para idempotência, `payload_hash` SHA-256
    hex, CHECKs de `entity_type`/`event_type` — já contemplando
    `ADMISSAO_INCLUIDA` do P3 —, trigger de UPDATE negado, RLS deny-by-default
    integral com `service_role` recebendo só `SELECT`/`INSERT`); helpers
    `ciclo_ator_valido` (perfil + membership ativa + allowlist FECHADA das
    capabilities de ciclo, reusando `evaluation_ator_valido` e
    `resolver_capabilities_efetivas`) e `ciclo_lock_organizacao` (chave
    **normativa** única da família: `evaluation_cycles:<organization_id>`);
    pre-flight de baseline fail-closed (não corrige dados) e guarda final
    fail-closed. **Sem RPCs `ciclo_*`** (P2+) e **sem policy de leitura** (P5).
  - `supabase/validacao/01-cenario-f5-09.sql`: fixture determinística e
    reexecutável (2 orgs; 7 ciclos — adjacência de período, `CANCELADO`
    sobreposto, ciclo sem período e o mesmo período em outro tenant; atores com e
    sem capability, membership e perfil desabilitados; 1 evento de trilha).
  - `supabase/validacao/02-validar-f5-09.sql`: validador do P1 (schema do
    contrato, I5/I6 por comportamento, `data_fim` inclusiva por adjacência,
    exclusão física negada por ACL **e** por comportamento, `cycle_events`
    completo — incluindo idempotência e FKs de tenant —, append-only em duas
    camadas, helpers, lock e regressão F5-06/F5-07/F5-08).
  - `.github/workflows/ci.yml`: o job `supabase-local` passou a executar
    `01-cenario-f5-09.sql` + `02-validar-f5-09.sql` **antes** da regressão
    F5-06/F5-07.
  - `supabase/migrations/README.md`: registro da migration da P1.
- **NÃO entregue (fora do P1, por contrato — nada antecipado):**
  `ciclo_criar`/`ciclo_editar`/`ciclo_ativar`/`ciclo_encerrar` (P2),
  `ciclo_incluir_admissao` + helper de elegibilidade da admissão (P3),
  `ciclo_cancelar`/`ciclo_reabrir`/`ciclo_corrigir_periodo` (P4), leitura RLS +
  porta/projeção do cliente (P5), Policy Engine (P6), Edge `ciclos` +
  reconciliação do bundle `admin` (P7), cutover (P8) e validação integrada (P9).
  Nenhuma capability nova e nenhum arquivo de `src/` alterado.
- **Gates desta rodada:** `npm test` (**108 arquivos / 1677 testes**, exit 0),
  `npm run build` (exit 0), `npm run lint` (exit 0),
  `npx tsc -b tsconfig.app.json` (exit 0) e `git diff --check` (exit 0). Os
  **validadores SQL NÃO foram executados neste host**: o daemon do Docker Desktop
  está inacessível (`permission denied ... npipe:////./pipe/dockerDesktopLinuxEngine`,
  com timeout inclusive sob elevação), então `supabase db reset` + `01/02` rodam
  no job `supabase-local` do CI — limitação registrada, nunca mascarada como
  verde.
- **Próxima atividade:** auditoria GPT do P1; depois **P2** (RPCs de gestão do
  ciclo), sem decisão arquitetural aberta.
- **Correção pós-CI (PR #190, mesma branch):** o job `supabase-local` falhava no
  validador **legado** `supabase/validacao/02-validar-f4-08.sql` **antes** dos
  validadores da F5-09, com
  `[FAIL] tabela public nao classificada (D16 — catalogacao explicita
  obrigatoria): cycle_events` — o schema guard global do F4-08 exige catalogação
  explícita de toda tabela `public` e ainda não conhecia a tabela nova. Correção
  **mínima e sem relaxar contrato**: `cycle_events` foi classificada como
  **tabela fechada** (RLS habilitada, **sem policy**, **sem SELECT/INSERT/UPDATE/
  DELETE** para `authenticated`/`anon`, `service_role` apenas `SELECT`/`INSERT`,
  append-only) em todas as listas/contadores do F4-08 — `v_closed` (policy, 22→23),
  `v_closed` (SELECT, 22→23), anon `v_todos` (44→45), DML `v_todos` (44→45), schema
  guard (44→45) e a lista comportamental de tabelas fechadas invisíveis (22→23) —
  e nas **duas cópias** da lista de classificação do
  `03-validar-f4-08-mutacoes.sql` (mutação B). `collaborator_events` permanece na
  categoria especial dele (policy SELECT own-tenant sem grant). A migration da P1
  **não** foi alterada e nenhuma regra da F5-09/P1 foi relaxada (contagem total de
  policies segue 22: `cycle_events` não tem policy no P1).
- **Correção pós-CI #2 (PR #190, mesma branch):** o passo
  `Run F5-08 cutover validation (P6)` falhava com
  `[FAIL] P6-6: funcao com advisory lock fora da chave normativa: ciclo_lock_organizacao`.
  O P6-6 fazia uma **varredura global** de funções com `pg_advisory_xact_lock` e
  pressupunha que toda função com lock pertencia à família estrutural da F5-08.
  Correção **mínima e sem relaxar D24**: o P6-6 passou a ser uma **classificação
  explícita por família** — catálogo fechado da **família estrutural** (15 RPCs da
  F5-08 + as 4 RPCs estruturais da F5-07 alinhadas pela `20260914020000` + os 2
  triggers anti-ciclo da F3-04/F5-08), cada uma provada **por função** como usuária
  **exclusiva** de `position_reporting_lines:<org>` (e de nenhuma chave alheia), e
  catálogo fechado das **demais famílias** com a sua chave normativa própria —
  hoje `ciclo_lock_organizacao` → `evaluation_cycles:` (F5-09, família de ciclos).
  Um **fechamento** reprova qualquer função com advisory lock fora dos dois
  catálogos (família nova exige catalogação explícita), a proibição de
  `SECURITY DEFINER` com lock continua global e a não vacuidade passou a exigir
  ≥ 15 funções **estruturais** com a chave D24. `ciclo_lock_organizacao` e a
  migration da F5-09/P1 **não** foram alteradas (a F5-09 **não** reutiliza
  `position_reporting_lines:` nem `f5_07_estrutura:`).
- **Correção pós-auditoria Codex (PR #190, mesma branch):** o bloqueante era
  `cycle_events` não ser append-only contra **privilege drift** (o trigger cobria
  só `UPDATE`; `DELETE`/`TRUNCATE` dependiam de revokes). Correção **na P1**:
  `enforce_cycle_events_append_only()` passou a levantar exceção para as três
  operações (`TG_OP` no motivo) e a trilha ganhou `trg_cycle_events_no_delete`
  (`BEFORE DELETE` row-level) e `trg_cycle_events_no_truncate` (`BEFORE TRUNCATE`
  statement-level) — proteção no banco **inclusive para o owner e para
  `service_role`**, mantidos os revokes como primeira camada; a guarda final da
  migration passou a exigir os três triggers. O validador
  `02-validar-f5-09.sql` ganhou a seção §4.3: probes de `UPDATE`/`DELETE`/
  `TRUNCATE` negados **para o owner** e sob **privilege drift simulado** (grant
  temporário de `DELETE`/`TRUNCATE` a `service_role`, revertido ao final, com
  conferência de ACL e de que a trilha continua com 1 linha). Consequência
  necessária: o cenário `01-cenario-f5-09.sql` deixou de apagar/recriar a fixture
  (a trilha é protegida e as FKs são `ON DELETE RESTRICT`) e passou a ser
  **INSERT-ONCE** (guarda `\gset`/`\if` + reexecução no-op). `evaluation_cycles`
  **não** foi alterada e nenhuma P2+ foi antecipada.

### 3.6 F5-09 — desenho técnico (rodada anterior, integrada pelo PR #189)

> Histórico do contrato; **não** é o estado atual da atividade (ver §3 acima).

- **Atividade:** F5-09 — **Ciclos soberanos** — **DESENHO
  TÉCNICO revisado** (`docs/F5-09-desenho-tecnico.md`, D1–D28 e fases P1–P9) com o
  registro de ratificação em `docs/F5-09-duvidas.md`
  (Q-F5-09-1..3 **RATIFICADAS**; nenhuma dúvida aberta).
- **Base:** `main`/`origin/main` = `6550c81d14a9d3e61b3c1b4f49471948f880bbc8`
  (F5-08 P6 integrado, PR #188; baseline esperado da F5-09 conferido).
- **Branch do desenho:** `docs/f5-09-ciclos-soberanos` — **sem PR** nesta rodada;
  **somente documentação**: nenhuma migration, RPC, Edge Function, capability,
  policy, teste de runtime ou alteração de frontend entrou nesta rodada.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Entregue nesta rodada (desenho F5-09):**
  - autoridade soberana do ciclo reusa `public.evaluation_cycles` (F5-06 D15) de
    forma **aditiva** — nenhuma tabela concorrente de ciclo/estrutura/versão;
  - identidade canônica = `evaluation_cycles.id` (UUID); `(ano, numero)` é apenas
    rótulo humano e regra de unicidade (`uq_evaluation_cycles_org_ano_numero`); a
    ponte `(ano, numero) → UUID` (`evaluation_resolver_ciclo` e o mapa de
    `assignedSupabase.ts`) permanece só como INTENÇÃO na fronteira confiável, com
    condição de remoção registrada;
  - máquina de estados sobre os quatro estados já existentes, com origem,
    destino, capability, pré-condições, efeitos transacionais e reversibilidade
    por transição; `CANCELADO` terminal; encerramento **reusa**
    `evaluation_fechar_ciclo_pendencias`; cancelamento resolve as avaliações não
    concluídas na mesma transação;
  - estrutura por ciclo = snapshot F3-08 + responsabilidades F3-09 + congelamento
    de participantes da F5-06 (congelada na ativação; hierarquia sempre relacional,
    nunca texto);
  - integridade nova no banco: índice único parcial de ciclo `ATIVO` por
    organização, exclusion de sobreposição de períodos (meio-aberto), trilha
    append-only `cycle_events` com `unique (organization_id, operation_id)` +
    `payload_hash`, chave normativa de advisory lock por organização;
  - autorização **sem capability nova** (`cycle.read`, `cycle.manage`,
    `cycle.cancel`, `cycle.reopen`, `cycle.period.correct`), Edge nova
    `supabase/functions/ciclos` (namespace `cycle.*`) e RPCs `ciclo_*`
    (SECURITY INVOKER, EXECUTE só `service_role`);
  - leitura soberana por RLS own-tenant (`user_has_active_membership`) + grant de
    SELECT a `authenticated`; escrita do cliente permanece fechada (deny-by-default);
  - cutover do cliente classificado A/B/C/D para os **21 arquivos** que hoje leem
    ou escrevem ciclo local;
  - fecha a pendência declarada da F5-07 (filtro de histórico do colaborador por
    ciclo) usando `collaborator_events.reference_cycle_id`;
  - **duas lacunas de contrato identificadas e endereçadas de forma aditiva:**
    `cycle.read`/`cycle.manage` caem hoje no `default → null` do
    `authorizationPolicy.ts` (⇒ DENY) e nenhuma role de sistema concede
    `cycle.manage` (o bundle `admin` tem só `cycle.read`) — resolvida pela **D28**
    (reconciliação aditiva do catálogo no P7).
- **Revisão 2 desta rodada (RATIFICAÇÃO incorporada):** a auditoria GPT do desenho
  ratificou as três dúvidas e o contrato foi revisado de ponta a ponta — **zero
  dúvida bloqueante aberta**:
  - **Q-F5-09-1 (alternativa A)** — `PLANEJADO→CANCELADO` permitido com
    `cycle.cancel`, motivo obrigatório, autoria soberana, trilha append-only,
    `expected_version` e idempotência; `CANCELADO` terminal; **exclusão física
    proibida em todos os estados** (D8/D9; ampliação aditiva do `domainState` e da
    descrição da capability, sem capability nova);
  - **Q-F5-09-2 (regra híbrida)** — a estrutura do ciclo **não** é "congelamento
    absoluto" nem rematerialização genérica: população inicial materializada na
    ativação, **admissões posteriores elegíveis podem ser acrescentadas** por
    operação soberana, explícita, auditada e **exclusivamente aditiva** (D26), com
    snapshots existentes **imutáveis** e movimentações de posição/unidade/gestor/
    reporting line/colegiado valendo **no próximo ciclo** (D27);
  - **Q-F5-09-3 (alternativa A)** — `cycle.manage` entra **aditivamente** no bundle
    `admin`; `cycle.cancel`/`cycle.reopen`/`cycle.period.correct` permanecem fora
    do bundle, só por configuração explícita (D28, executada no P7).
- **Inclusão aditiva de nova admissão (D26) — onde ficou:** operação restrita
  `cycle.admissao.incluir` / RPC `ciclo_incluir_admissao` + helper read-only
  `ciclo_admissao_pos_ativacao_elegivel`, na fase **P3**. A prova de "nova
  admissão" é **soberana** (nunca flag do cliente): evento append-only
  `collaborator_events.event_type = 'ADMISSAO'` com
  `cycle_scope = 'CICLO_ATUAL_E_POSTERIORES'` e `effective_date > data_ativacao`,
  mais ausência de período de status anterior à ativação em
  `collaborator_status_periods`; a coluna declarada
  `collaborators.admission_date` **não** é prova. Sem prova ⇒ **recusa**
  (fail-closed), registrada como requisito técnico da implementação (§7.2/R15) —
  a regra não é flexibilizada. O contrato **não** tem parâmetro estrutural algum e
  impede por construção sobrescrever snapshot, trocar posição, recalcular gestor
  ou colegiado, inclusão cross-tenant e uso genérico como "atualizar estrutura".
- **Plano revisado:** **P1–P9** (a fase nova **P3** existe para a inclusão aditiva
  e a reconciliação do catálogo ficou no **P7**); D1–D28. **(Estado atual: P1
  implementada — ver §3.)**
- **`.ai/current-task.md`:** não existe neste repositório (nem no histórico). A
  ausência é registrada aqui conforme `AGENTS.md` §1; o estado operacional de
  retomada continua sendo este arquivo.

### 3.5 F5-08 (concluída e integrada)

- **Atividade:** F5-08 — Estrutura organizacional e catálogos soberanos (contrato
  em `docs/F5-08-desenho-tecnico.md`, D1–D25). P1–P6 integrados em `main`; o
  squash do P6 (cutover estrutural) é `6550c81` (PR #188) — a antiga branch
  `feat/f5-08-p6-cutover-estrutura` está encerrada e **nada da F5-08 foi
  transferido para a F5-09** (a F5-09 só assumiu o domínio de ciclos).
- **Entregue (P1–P5, na base):** migrations `20260914000000`
  (`structure_events` append-only + triggers I1–I3 + grants), `20260914010000`
  (15 RPCs `estrutura_*`/`catalogo_*`) e `20260914020000` (chave única de advisory
  lock, D24); contrato/Edge `supabase/functions/colaboradores`; porta/serviço do
  cliente (`services/colaboradoresSoberanos/acessoColaboradoresSoberanos.ts`),
  leitura soberana por RLS
  (`infrastructure/supabase/estrutura/repositorioEstruturaSoberana.ts`); telas
  Unidades/Posições/Catálogos/Colegiado e alocação do colaborador (ocupação +
  reporting line).
- **Entregue nesta rodada (P6 — cutover estrutural):**
  - `authorizationPolicy.ts`: fallback do mundo funcional para o cadastro local
    **removido**; resta apenas sob barreira explícita de DEV
    (`simulacaoDevPermitida`) ⇒ produção fail-closed;
  - `mundoFuncional.ts`: `SEM_BINDINGS_DEV` — a derivação local de bindings deixou
    de ser implícita; sem binding explícito (teste) ou da projeção soberana, a
    capability é NEGADA (inclusive o fluxo SELF);
  - `historicoOrganizacionalStorage.ts`: sem promoção de texto `respondePara` a
    relação de gestão (escrita local é barreira desde a F5-07);
  - `src/data/evaluationTeam.ts` removido (código morto, sem consumidores);
  - guardas do cutover: bloco P6 em
    `src/authorization/estruturaUiSeguranca.test.ts` (sweep global de `src/`) e
    `src/authorization/cutoverEstrutural.test.ts` (runtime, produção × DEV);
  - `supabase/validacao/03-validar-f5-08-cutover.sql` (leitura RLS own-tenant
    positiva/negativa, fail-closed sem membership ativa, superfície de escrita do
    cliente fechada, capability negada, RPC como única autoridade, chave única de
    serialização, idempotência e histórico preservado);
  - `.github/workflows/ci.yml`: o job `supabase-local` passa a executar os **três**
    validadores da F5-08 e a regressão F5-06/F5-07 (§13.7/§23.4); timeout 40 min.
- **Blockers da auditoria RESOLVIDOS (correção nesta branch):** o §19.1 do
  contrato exige que as decisões de elegibilidade/papel de `progressoAvaliacao`,
  `cicloEquipeService` e `metaStorage` usem estrutura SOBERANA — não era decisão
  futura da F5-09. Duas rodadas de correção, sem criar fonte nova (sem
  migration/RPC/Edge/capability):
  - **1ª rodada:** `src/services/projecaoEstruturalSoberana.ts` como fronteira; os
    três módulos + `permissaoAvaliacao.ts` + `MinhaAvaliacaoDetalhePage.tsx`
    deixaram de ler `funcao`, `gestorDiretoMatricula`,
    `avaliadoresColegiadoMatriculas` e `getColaboradoresVisiveis`;
    `authorization/providers/localWorld.ts` virou DEV-only (fora do gate ⇒ mundo
    vazio ⇒ DENY); fail-closed em todas as decisões.
  - **2ª rodada (blockers finais):** a projeção passou a ser **UUID-first** —
    `collaboratorId`, `gestorSoberanoPositionId`, `cadeiaDeGestaoPositionIds`,
    `cadeiaDeGestaoCollaboratorIds`, `colegiadoSoberanoCollaboratorIds` — e o
    modelo **não conhece matrícula**; o campo textual `papel`
    (GERENTE/COORDENADOR/OUTRO) foi **eliminado** e substituído por fatos
    relacionais soberanos (`temCadeiaDeGestaoSoberana`,
    `gestorSoberanoTemSuperior`, `raizDaCadeiaSoberana`, `colegiadoSoberano`);
  - **PRODUTOR conectado:** `src/services/estruturaSoberanaCliente.ts` carrega a
    estrutura pelo caminho normal já existente (`lerEstrutura` RLS/P4 +
    `listarColaboradores` F5-07), publica a projeção e mantém a **ponte de
    compatibilidade** matrícula ↔ UUID (fronteira, nunca chave estrutural);
    `src/pages/useEstruturaSoberanaDoCliente.ts` é acionado pelo shell
    autenticado (`LayoutFuncional` em `src/routes/AppRoutes.tsx`) — nenhum
    consumidor injeta projeção manualmente e a ausência de injeção deixou de ser
    "modo DENY";
  - **Blocker final (corrida/multi-tenant) RESOLVIDO:** o produtor deixou de
    deduplicar A e B como se fossem a mesma solicitação. Agora há **geração
    monotônica** (`let geracao = 0`) + organização vigente: uma carga só publica
    se ainda for a vigente (`publicarSeVigente`); iniciar uma carga publica
    imediatamente `carregando` com estrutura VAZIA (a estrutura do tenant anterior
    deixa de ser acessível na troca); a dedupe é **por organização**; e
    `invalidarEstruturaSoberana()` (usada pelo hook quando a organização ativa
    vira `null`/`undefined`) incrementa a geração, limpa a carga em curso e
    publica estado inválido/vazio — resposta antiga nunca republica;
  - **Residual final (unmount/logout) RESOLVIDO:** o hook ganhou um cleanup de
    **dependência VAZIA** (`useEffect(() => () => invalidarEstruturaSoberana(), [])`)
    que roda **apenas no unmount** do shell — o `LayoutAutenticado` pode parar de
    renderizar o `LayoutFuncional` sem passar por `organizacaoAtivaId == null`;
    sem ele, a estrutura do tenant A permanecia em memória após o logout e um
    login posterior em B podia observá-la antes do novo efeito executar. Não roda
    em re-render nem na troca A → B (que tem caminho próprio);
  - provas: `projecaoEstruturalSoberana.test.ts` (8), `estruturaSoberanaCliente.test.ts`
    (19 — corrida A→B determinística nos dois sentidos, dedupe por org, `null`
    invalidando contexto, falha real sem vazar outro tenant e lifecycle do shell:
    unmount invalida + assinatura removida, carga em voo não publica, novo login
    em B nunca vê A, A→B sem unmount segue funcionando),
    `cutoverEstruturalServicos.test.ts` (4) e o bloco estático
    `estruturaUiSeguranca.test.ts` (39 no arquivo), que reprova modelo com
    matrícula, consumidores lendo campos locais, produtor não acionado, produtor
    sem proteção de troca de tenant e hook sem cleanup de unmount;
  - `docs/F5-08-p6-duvida-mundo-funcional.md` documenta os blockers resolvidos, a
    identidade UUID, a segurança multi-tenant (§2.3), o fail-closed e o que resta
    à F5-09 (apenas o domínio de ciclos: persistência e estrutura POR CICLO) — sem
    autoridade estrutural local.
- **Residual declarado (fora do blocker, não silencioso):** `relatorioService`
  (filtros por `gestorDiretoMatricula`), `exportarAvaliacaoPdf` (identificação de
  avaliadores), `visibilidadeColaboradores` (sem chamador de produção) e
  `historicoOrganizacionalStorage` (snapshots/efetivos). Registrado na §6 do
  documento acima; exige atividade própria (relatórios/PDF).
- **Consequência do cutover (verificada):** em produção a estrutura de
  ciclo/metas é obtida da leitura soberana (RLS) pelo produtor publicado no shell
  autenticado, sempre correspondendo à **organização ativa** (troca de tenant
  segura); falha real do Supabase ⇒ fail-closed, e a decisão real de autorização
  permanece server-side (Edge + Policy Engine + RLS). Coberto por
  `cutoverEstrutural.test.ts`, `cutoverEstruturalServicos.test.ts`,
  `projecaoEstruturalSoberana.test.ts` e `estruturaSoberanaCliente.test.ts`.
- **Validação então registrada (branch do P6):** `npm test` (**108 arquivos /
  1677 testes** verdes), `npm run build`, `npm run lint`,
  `npx tsc -b tsconfig.app.json` e `git diff --check` executados localmente
  (todos verdes). Os **validadores SQL não foram executados** naquele host
  (Docker/Supabase indisponível) — rodam no job `supabase-local` do CI; a
  limitação está registrada no relatório da atividade. Nenhuma
  migration/RPC/Edge/capability nova foi criada no P6.

### 3.1 F5-07 (concluída e integrada)

- **Atividade:** F5-07 — Colaboradores e histórico organizacional soberanos
  (contrato em `docs/F5-07-desenho-tecnico.md`, D1–D20); integrada em `main` como
  `7137f1f`.
- **Entregue:** migrations `20260913000000`/`20260913010000` (extensões aditivas em
  `collaborators`, `job_roles.code`, log append-only `collaborator_events`, helper
  de ator e 16 funções/RPCs), Edge `colaboradores` (15 operações, com gate
  funcional no Policy Engine e gate administrativo da F5-04 **separados**), porta
  única `acessoColaboradoresSoberanos`, barreiras fail-closed em
  `colaboradorStorage`/`historicoOrganizacionalStorage`, telas migradas para UUID
  com matrícula resolvida no servidor e remoção do código morto.
- **Validação então registrada:** `npm test` 94 arquivos / 1346 testes; `build`,
  `lint` e `git diff --check` verdes; validadores SQL após `db reset` — F5-07
  (44 PASS + 22 PASS de cutover), F4-08 (56 + 8) e F5-06 (25 + 13).
- **Limites assumidos:** alocação/estrutura (cargo, área, função, senioridade,
  gestor, colegiado) é **F5-08** — a F5-07 não fabrica estrutura sintética e as
  telas exibem "sem alocação". Ciclos/metas/observações seguem legados.
- **Defeito PREEXISTENTE em `main`, não corrigido (fora de escopo):** a Edge
  `supabase/functions/avaliacoes/index.ts:8` importa
  `src/authorization/catalogoCapacidades.ts` (inexistente; o módulo real é
  `catalogoCapabilities.ts`), o que impede o bundle da função F5-06. Não afeta
  `npm test`/`build`/`lint`/`tsc` (apenas o bundle Deno da Edge).
  **Classificação (Issue #258): FINDING BLOQUEANTE (`DT-013`) — RESOLVIDO pela Issue #260 / PR #261**
  (squash-merged; `main` `f8bf8e33429b11d66e0f8ac9c7bf617c9b2788af`, CI #306 verde); sem bloqueio da #258.

### 3.2 BUG #170 (concluída e integrada)

- **Atividade:** BUG #170 — item "Ciclos" duplicado no menu para Gerente e
  Coordenador (Issue #170). Correção de **navegação/UX**, integrada em `main`.
- **Branch:** `fix/170-ciclos-menu-duplicado`.
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Causa raiz:** `NavegacaoPrincipal` tinha DOIS gates de menu para o MESMO
  assunto — `cycle.management.view` (`/ciclos`) e `cycle.coordinator.list`
  (`/painel-ciclos`). Ambos são **aliases da mesma capability canônica**
  (`cycle.read`, colapso Q1 da F4-09 em `authorization/canonical.ts`), e Gerente e
  Coordenador possuem `cycle.read`: as duas condições ficavam verdadeiras ao mesmo
  tempo e o menu renderizava dois itens consecutivos rotulados "Ciclos" (ambos com
  `IconCalendar`). Antes da centralização F4 os gates eram
  `funcao === "GERENTE"` / `funcao === "COORDENADOR"` — mutuamente exclusivos —,
  por isso o rótulo repetido nunca aparecia.
- **Correção:** UM ÚNICO item "Ciclos" → `/ciclos`, gated pela capability canônica
  `cycle.read` (visibilidade de menu é UX; o resource `{ kind: "global" }` é
  transitório e nunca prova de autorização). Rotas, capabilities, roles, RLS e
  contratos F4/F5 intactos. `/painel-ciclos` permanece rota autorizada e
  alcançável por "Minha equipe" (Início → `ColaboradoresPage`, botão do
  COORDENADOR). Teste novo `src/components/NavegacaoPrincipal.test.tsx` (13 casos)
  fixa o invariante de UM item por contexto e o menu completo de Gerente,
  Coordenador, Analista, Consultor, Estagiário e colaborador sem função.
- **Validação desta rodada (todo exit 0):** `npm test` (85 arquivos, 1082 testes),
  `npm run build`, `npm run lint`, `git diff --check origin/main...HEAD`.

### 3.3 DEV-02 (concluída e integrada)

- **Atividade:** DEV-02 — reduzir interrupções por elevação de acesso dos agentes
  (Issue #177). Somente camada de contexto; sem alteração funcional.
- **Integração:** `main` no SHA `e098754…` (PR #178).
- **Regra registrada:** `.ai/workflow.md` **§6**, com síntese permanente em
  `AGENTS.md` **§4**: aprovação técnica/arquitetural ≠ autorização de elevação de
  acesso; com desenho FECHADO não se repete pedido de aprovação; trabalho em lote
  com autoauditoria estática antes dos comandos privilegiados; comandos que exigem
  elevação agrupados em um ou poucos gates; proibido alterar PAT/credenciais/
  configurações ou reduzir controles.
- **Limitação do ambiente (registrada):** neste host o sandbox exige elevação
  (`danger-full-access`) até para comandos triviais (`git status`, `npm test`,
  `lint`) e para Docker/Supabase — agrupar operações por gate e registrar a
  limitação, nunca contornar a proteção (`.ai/git-rules.md` §3;
  `.ai/workflow.md` §6.4).

### 3.4 F5-06 (concluída e integrada)

- **Atividade:** F5-06 — Avaliações no PostgreSQL (Issue #103).
- **Branch:** `feat/f5-06-avaliacoes-postgresql` — **squash merge em `main`** como
  `f540f0f5d16a4b3f33a99f7e4f0e8fb7c5c30584` (PR #176, `Closes #103`); a cabeça do
  PR auditada foi `a11687e…`, com a correção final de whitespace em `c38de2b…`.
- **PR:** #176 — fechado e integrado. Este agente **não** declara a atividade
  aprovada: a aprovação é da auditoria independente.
- **Estado — SQL, fronteira e caminho TS (completo e validado):** migrations
  F5-06 (schema, funções e `20260911020000_f5_06_cutover_leitura_e_ciclo.sql`),
  Edge Function `avaliacoes`, policy/capabilities, ponte matrícula → UUID,
  resolução ano+ciclo, painel do participante e `cutoverAvaliacoesService`.
- **Estado — CUTOVER DAS TELAS (concluído nesta rodada):** nenhuma avaliação
  NOVA é criada/editada/cancelada/reaberta em `localStorage`; a autoridade é o
  PostgreSQL pelo caminho soberano.
  - Telas migradas: `NovoFeedbackPage` (criação + notas/observações/comentário
    final), `EditarFeedbackPage` (leitura do painel + gravação soberana +
    conclusão), `FeedbackDetalhePage` (cancelar/reabrir soberanos),
    `CiclosAvaliacaoPage` (ativação e encerramento).
  - Serviços migrados: `cancelamentoAvaliacaoService`,
    `reaberturaAvaliacaoService`, `cicloEquipeService`
    (`criarAvaliacoesDoCicloAtivado` e `concluirAvaliacoesNoEncerramentoDoCiclo`
    agora **async** e soberanos).
  - Novos módulos: `src/services/acessoAvaliacoesSoberanas.ts` (porta única das
    telas; nenhuma página importa Supabase) e `src/services/origemAvaliacaoTela.ts`
    (FONTE ÚNICA da decisão de origem, por EVIDÊNCIA de cutover).
  - Síncrono → assíncrono: `criarAvaliacoesDoCicloAtivado`,
    `concluirAvaliacoesNoEncerramentoDoCiclo`, `cancelarAvaliacao`,
    `reabrirAvaliacao` e os handlers das quatro telas (com estados de
    processamento/erro preservados).
  - `feedbackStorage` é **somente leitura** para o legado: `saveFeedback` foi
    removida; `updateFeedback`, `persistirCancelamentoAuditadoInterno`,
    `persistirReaberturaAuditadaInterno` e `removerAvaliacaoVaziaNoCleanupInterno`
    existem apenas como barreiras que lançam (fail-closed). Exclusão de ciclo com
    avaliação vazia no legado agora é recusada — a limpeza do legado pertence à
    atividade de importação (fora do escopo, §1.3).
- **Estado — CORREÇÕES PÓS-AUDITORIA GPT (rodada 1):**
  1. **Origem POSTGRES exige EVIDÊNCIA, nunca formato.** `ehIdTecnicoPostgres`
     passou a ser usado SOMENTE como validação de formato, nunca como
     classificação de origem; id legado numérico, textual ou **em formato de
     UUID** não é promovido por isso; nenhuma heurística de data.
  2. **Navegação das avaliações novas.** O livro-caixa de cutover ganhou índices
     de NAVEGAÇÃO (`CHAVE_CICLO_AVALIACOES`) e as telas passaram a abrir a
     avaliação nova pelo painel soberano.
- **Estado — CORREÇÕES PÓS-AUDITORIA GPT (rodada 2, FINAL):**
  1. **Descoberta SOBERANA (localStorage é opcional).** A prova de existência vem
     do SERVIDOR: `resolverLeituraAvaliacao` (`origemAvaliacaoTela.ts`) consulta a
     fronteira confiável para qualquer id candidato e só usa o acervo local quando
     o servidor responde `NOT_FOUND` (o código público do erro é exposto em
     `ResultadoCutover.codigo` para essa distinção — sem inspeção de texto).
     Consequências: `localStorage` apagado, outro navegador/dispositivo,
     livro-caixa ausente/corrompido e **URL soberana aberta diretamente** não
     escondem uma avaliação real; falha de backend/indeterminação é fail-closed e
     nunca vira leitura local silenciosa; `NOT_FOUND` e negação permanecem
     indistinguíveis (sem vazar existência cross-tenant).
     No SQL, ausência de ocorrência vigente do ator no painel passou a devolver
     `NULL` (resultado "sem painel") em vez de exceção, permitindo distinguir
     "não existe/não acessível" de "falha real".
  2. **Índices de navegação ISOLADOS por organização.** `chaveAnoCiclo` e
     `chaveCicloColaborador` passaram a incluir `organizationId`
     (`org|ano-ciclo`), e `registrarAvaliacoesDoCiclo`/`lerAvaliacoesDoCiclo`/
     `lerAvaliacaoNovaDoColaboradorNoCiclo`/`esquecerAvaliacaoNovaDoColaboradorNoCiclo`
     recebem a organização. Mesma matrícula/ano/ciclo em orgs diferentes não
     colide; trocar de organização ativa não reutiliza índice alheio. A
     organização ali é apenas NAMESPACE DE CACHE — não é prova de tenant nem
     autorização (toda operação revalida server-side).
  3. **Preflight de duplicidade validado no servidor.** `NovoFeedbackPage` não
     bloqueia mais só pelo cache: confirma a existência na fronteira confiável e,
     se a entrada estiver obsoleta, esquece o cache e segue com a criação
     legítima. A autoridade da unicidade continua sendo o índice único parcial do
     banco, e nada é criado localmente.
- **Estado — CORREÇÕES DA AUDITORIA GPT-5.6 TERRA (rodada 3, FINAL):**
  1. **BLOCKER 1 — assinatura de `evaluation_resolver_ciclo`.** A Edge enviava
     `p_matricula_avaliado`, argumento que NUNCA existiu na RPC; com PostgREST a
     divergência quebra a chamada e impedia toda criação nova. A Edge passou a
     enviar EXATAMENTE a assinatura real:
     `evaluation_resolver_ciclo(p_organization_id uuid, p_ano integer,
     p_numero integer, p_actor_user_profile_id uuid) returns uuid`.
     A matrícula continua sendo INTENÇÃO resolvida pela ponte F3-01 **antes** do
     Policy Engine (para o alvo autorizável) e não trafega de novo. Nenhum
     overload foi criado. Teste novo `avaliacoesContratoRpc.test.ts` lê o código
     real da Edge e falha se algum argumento voltar a divergir do contrato.
  2. **BLOCKER 2 — IDOR em `participant_id`.** As RPCs `evaluation_gravar_notas`
     e `evaluation_gravar_comentario` aceitavam `p_participant_id` do chamador e
     só validavam que a ocorrência pertencia à avaliação e estava vigente: um ator
     autorizado podia forjar o id da ocorrência de TERCEIRO. Agora a ocorrência
     editável é derivada SOBERANAMENTE do ator, por
     `evaluation_ocorrencia_do_ator(organization_id, evaluation_id, actor)`:
     `auth.uid()` → perfil → membership ativa no tenant do RECURSO → vínculo
     F5-02 → ocorrência VIGENTE pertencente a ele. **`participant_id` foi
     REMOVIDO do contrato externo** (Edge, `core.ts`, `contrato.ts`, repositório,
     controlador e serviço) e a validação de forma RECUSA o campo
     (`INVALID_INPUT`); as assinaturas antigas foram dropadas. Defesas em
     profundidade nas RPCs: ator revalidado, tenant do recurso revalidado,
     ocorrência vinculada ao ator, vigência respeitada e fail-closed em ausência
     **ou ambiguidade** (duas ocorrências vigentes ⇒ recusa).
     O `painel_participante` continua devolvendo SOMENTE a ocorrência própria
     (usada como catálogo/identidade da tela) e D20 permanece intacta.
- **Telas que ainda leem SOMENTE o legado (justificativa):**
  - `CiclosAvaliacaoPage`/`PainelCicloPage`/`relatorioService`: o painel é
    montado pelo domínio de **ciclos**, que ainda vive em `localStorage`
    (migração de ciclos é outra atividade — D15). Enquanto o ciclo não existir no
    banco, não há avaliação nova daquele ciclo a listar; quando existir, o índice
    de navegação é o caminho. Nenhuma autoridade local é exercida.
  - `ColaboradorDetalhePage`: lista o histórico administrativo do acervo legado;
    a avaliação nova é alcançável pelo índice/painel. Adotar a leitura soberana
    nessa listagem é aditivo.
- **Pendências/limitações conhecidas (não bloqueiam o critério de conclusão):**
  1. **Gravação de ciclo (entidade `evaluation_cycles`) é de outra atividade**
     (D15). Sem o ciclo correspondente no banco, `evaluation.criar` é recusado e
     a tela reporta quantas avaliações ficaram **bloqueadas** (nunca cria local).
  2. **Remoção de nota**: `evaluation_gravar_notas` aceita notas `1..5`; limpar
     uma nota já gravada não a apaga (não há API de exclusão). O valor anterior
     permanece — alteração de contrato exigiria nova `Q#`.
  3. **Listagem administrativa do legado** (item acima) permanece legado.
  4. **Descoberta de id fora da URL**: sem estado local, o produto alcança a
     avaliação pela URL/painel; uma listagem soberana "por ciclo/colaborador"
     (Edge + Policy Engine) é evolução aditiva e depende da migração de ciclos.
  5. **Ator com duas ocorrências vigentes** na mesma avaliação (ex.: o mesmo
     colaborador como responsável direto E membro do colegiado) é recusado por
     ambiguidade (fail-closed, coberto pelo validador). O cenário sintético
     encerra a ocorrência redundante para exercitar o fluxo positivo. Resolver a
     escrita nesse caso exigiria papel explícito na intenção ⇒ nova `Q#`.
- **Validação da F5-06 (todo exit 0):** `npm test` (84 arquivos,
  1069 testes), `npm run build`, `npm run lint`, `git diff --check`;
  validadores SQL no Supabase local — `01-cenario-f5-06.sql`,
  `02-validar-f5-06.sql` (25 PASS), `03-validar-f5-06-cutover.sql` (13 PASS,
  incluindo os testes negativos de IDOR), `01-cenario-f4-08.sql`,
  `02-validar-f4-08.sql` (56 PASS), `03-validar-f4-08-mutacoes.sql` (8 PASS).
- **Contexto do repositório:** `main` contém F4, F5-01..F5-06 e a DEV-02 já
  integradas (F5-06 em `f540f0f…`, DEV-02 em `e098754…`); o BUG #170 é a atividade
  em curso nesta branch, sem alteração funcional fora da navegação.
- **Próximos passos:** auditoria independente sobre o novo SHA do BUG #170; abrir
  PR quando solicitado; a Issue #170 **não** deve ser fechada por este agente.
  Nenhum agente declara a própria entrega aprovada (`.ai/workflow.md` §6.3,
  item 8).
