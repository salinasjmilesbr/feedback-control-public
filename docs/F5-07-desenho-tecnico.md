# F5-07 — Colaboradores e histórico organizacional soberanos (contrato arquitetural e desenho)

> **Estado:** ABERTO — contrato proposto para revisão e fechamento (há `Q1` em §19).
> **Atividade:** F5-07 (Etapa 5). **Issue:** ainda não vinculada; a atividade é
> definida pelo diagnóstico da Etapa 5 (`auditoria-etapa-5-diagnostico.md`, §5 —
> "F5-07 — Colaboradores e histórico organizacional PostgreSQL").
> **Depende de (contratos FECHADOS e implementados):** F3-01…F3-10, F4-01…F4-10,
> F5-01, F5-02, F5-03, F5-04, F5-05, F5-06. Nenhum desses contratos é reaberto
> aqui; onde há lacuna, o desenho cria contrato **novo** e aditivo.
> **Não implementa nada:** este documento é o contrato da implementação futura.

## 1. Objetivo e limites

### 1.1 Objetivo

Eliminar a autoridade operacional do `localStorage` sobre **colaboradores**,
**identificadores humanos envolvidos** (matrícula e correlatos), **status e
vigências**, **estrutura organizacional relacionada ao colaborador**,
**histórico organizacional**, **sucessão** e **responsabilidades**, tornando o
PostgreSQL/Supabase a fonte soberana única desses domínios, com identidade
funcional por UUID de colaborador, tenant revalidado server-side, mutações
autorizadas pelo gate soberano, histórico temporal preservado e autoria
auditável.

### 1.2 O que a F5-07 entrega (contrato)

1. **Leitura soberana** do colaborador e da estrutura vigente (projeção
   server-side com identidade UUID, matrícula vigente, dados de pessoa, status
   vigente e atributos estruturais derivados).
2. **Mutações soberanas** de colaborador: criação, edição de dados de pessoa,
   definição/troca de identificador, transição de status.
3. **Mutações soberanas de alocação estrutural** do colaborador: ocupação
   (colaborador × posição), reporting line (posição × posição),
   responsabilidade temporária e registro de sucessão — sempre por
   fechar-e-abrir vigência, nunca por sobrescrita.
4. **Histórico organizacional soberano**: linha do tempo append-only com tipo,
   data de vigência, motivo, escopo por ciclo, referência de ciclo, autor
   soberano e delta estruturado (valor anterior/novo).
5. **Autorização** na fronteira confiável para cada operação, reaproveitando
   ActorContext/ResourceContext reais (F5-05) e o Policy Engine (F4).
6. **RLS e grants** como barreira real, com o mínimo de superfície para
   `authenticated` e mutação exclusivamente por RPC `SECURITY INVOKER`
   executada por `service_role`.
7. **Cutover** das telas e serviços de colaborador/histórico, sem dual-write e
   sem fallback silencioso para `localStorage`.
8. **Matriz de testes** e gates de conclusão (§16/§17).

### 1.3 Fora de escopo (F5-07)

- **Ciclos de avaliação** (entidade e lifecycle): **F5-08**. A F5-07 apenas
  registra o contrato mínimo de que necessita (§20.1) e referencia
  `evaluation_cycles.id` como ciclo de referência de uma movimentação.
- **Metas** (F5-09) e **observações** (F5-10): consomem a estrutura entregue
  aqui, mas não são migradas nesta atividade (§20.2/§20.3).
- **Validação transversal final da Etapa 5** (F5-11) e **hardening de produção**
  (Etapa 6).
- **Administração da estrutura organizacional** (CRUD completo de
  `organizational_units`, `organizational_positions`,
  `organizational_unit_parent_periods`, `job_roles`, `seniority_levels`,
  `collegiate_configurations`). A F5-07 **consome** essas estruturas; elas
  precisam existir no banco (ver §20.5 — dependência registrada e
  `D16`/bootstrap mínimo).
- **Importação histórica ampla** do `localStorage` (colaboradores, estrutura e
  movimentações legadas). A F5-07 **não** importa o acervo local: define o
  regime de leitura do legado (§14) e deixa a importação para atividade
  própria, se houver decisão de produto.
- **Reabertura de contratos F3/F4/F5**: nenhuma decisão fechada é revista;
  onde o contrato é omisso, cria-se contrato novo e aditivo.

## 2. Estado atual auditado (evidência)

> Auditoria somente de leitura desta atividade (nenhum arquivo alterado).
> Convenção: `arquivo:linha` para código; `migration:linha` para banco.

### 2.1 Autoridade local hoje

| Aspecto | Estado real |
| --- | --- |
| Chave de colaboradores | `feedback-control-colaboradores` (`src/services/colaboradorStorage.ts:8`) |
| Chave de histórico | `feedback-control-historico-organizacional` (`src/services/historicoOrganizacionalStorage.ts:11`) |
| Escrita em leitura | `getColaboradores()` **regrava** o storage em toda leitura (migração/normalização + injeção de gestores) — `colaboradorStorage.ts:161-164` |
| Hierarquia inventada | `gestorDiretoMatricula` é derivado do **texto** `respondePara` por mapa hardcoded (`colaboradorStorage.ts:59-64,90-134`); `funcao` ausente vira `"ANALISTA"` (`:96`); `senioridade` inferida do **texto livre** `cargo` (`:100-121`) |
| Registros injetados | `garantirGestores` injeta 4 gestores hardcoded (matrículas 900001-900004) sempre que ausentes (`colaboradorStorage.ts:10-57,136-148`) |
| Normalização destrutiva | `formatarNomePessoa` reescreve `nome`/`respondePara`/`gerente` (`colaboradorStorage.ts:66-85,125-129`) |
| Escrita de cadastro | `saveColaborador` (`:188`), `updateColaborador` (`:199`, **no-op silencioso** se a matrícula não existir) |
| Histórico | Append-only local, sem idempotência e sem autorização: `registrarMovimentacaoOrganizacional` (`historicoOrganizacionalStorage.ts:133-174`) |
| Recomputação | O estado por data é **recalculado** aplicando deltas sobre o snapshot-base (`historicoOrganizacionalStorage.ts:264-300`); sem histórico, devolve o **estado atual** (anacronismo, `:277-279`) |
| Autor do histórico | `autorMatricula`/`autorNome` do tipo local (`src/types/HistoricoOrganizacional.ts:43-44`) — autoria textual, não soberana |
| Gate de escrita por cargo | `geradorDadosTeste.ts:447-451` nega por `funcao !== "GERENTE"` **fora** do Policy Engine |

### 2.2 Tipo `Colaborador` (o que precisa ser decomposto)

`src/types/Colaborador.ts:18-40` mistura quatro naturezas distintas:

| Campo | Natureza real |
| --- | --- |
| `matricula: number` | **identidade funcional** hoje (PK natural, rota, chave de decisão) |
| `nome`, `email` | dados de pessoa |
| `cargo`, `area`, `funcao`, `senioridade` | **estrutura** (devem vir da posição ocupada) |
| `gestorDiretoMatricula` | **hierarquia** derivada (posição → reporting line) |
| `avaliadoresColegiadoMatriculas` | **atribuição** (colegiado/F3-08/F3-09) |
| `respondePara`, `gerente` | apresentação/legado (nomes em texto) |
| `dataAdmissao`, `dataInicioLicenca`, `dataFimLicenca`, `dataDesligamento` | temporalidade hoje duplicada do histórico |
| `status: ATIVO｜LICENCA｜DESLIGADO` | estado vigente (temporal) |

**Não existe** `id` soberano no frontend, **não existe** tenant no tipo, e o
mundo de autorização usa `LOCAL_ORGANIZATION_ID = "organizacao-sintetica-local"`
(`src/authorization/mundoFuncional.ts:20`).

### 2.3 Banco: o que já existe (reuso obrigatório)

24 tabelas estruturais/autorizativas já existem (`supabase/migrations/`). As
decisivas para esta atividade:

| Tabela | Papel | Colunas-chave | Vigência |
| --- | --- | --- | --- |
| `collaborators` | identidade técnica | `id uuid`, `organization_id`, `version` (`20260907103100…:81-92`) | — |
| `collaborator_identifiers` | matrícula/código de negócio | `business_code text`, unique `(organization_id, business_code)`, FK composta de tenant (`:153-178`) | `valid_from`/`valid_to` + exclusion por colaborador |
| `collaborator_status_periods` | status | `status ∈ (active, leave, inactive)` (`:255-277`) | `valid_from`/`valid_to` + exclusion **por colaborador** |
| `job_roles` / `seniority_levels` | catálogos | `name`, `status`, unique `(organization_id, name)` (`20260907120000…:81-96,151-…)` | — |
| `organizational_units` / `organizational_unit_parent_periods` | unidades e hierarquia de unidades | `name`, `unit_id`, `parent_unit_id` (`20260907130000…:119-127,196-205`) | `valid_from`/`valid_to` |
| `organizational_positions` | posição formal | `unit_id`, `job_role_id`, `seniority_level_id` (`:288-298`) | `valid_from`/`valid_to` |
| `position_reporting_lines` | hierarquia formal | `subordinate_position_id`, `manager_position_id`, `reason`, `ck_…_not_self` (`20260907140000…:87-121`) | `valid_from`/`valid_to` + exclusion por subordinado |
| `occupations` | colaborador × posição | `collaborator_id`, `organizational_position_id`, `reason` (`20260907150000…:69-99`) | `valid_from`/`valid_to` + exclusion por posição |
| `temporary_responsibilities` | substituto temporário | `organizational_position_id`, `substitute_collaborator_id`, `responsibility_type`, `reason` (`20260907160000…:73-84`) | `valid_from`/`valid_to` |
| `collegiate_configurations` / `_members` | colegiado | `collaborator_id`, `member_collaborator_id` (`20260907180000…:59-67,116-123`) | `valid_from`/`valid_to` (configuração) |
| `cycle_evaluation_responsibilities` | responsável avaliativo por ciclo | `snapshot_id`, `position_id`, `responsible_collaborator_id` (`20260907190000…:151-161`) | `valid_from`/`valid_to` |
| `evaluation_succession_events` | **sucessão auditável** | `previous_…`, `new_responsible_collaborator_id`, `succession_date`, `motive`, **`author_user_profile_id`** (`:232-242`) | evento com autoria soberana |
| `membership_collaborator_links` | vínculo conta ↔ colaborador | `membership_id`, `collaborator_id`, `status ∈ (active, disabled)` (`20260908010000…:52-78`) | **sem** vigência (F5-02 Q6=B); histórico em linhas `disabled` |

**Resolvers estruturais já prontos (F3-07):**
`organizacao_resolver_responsavel_posicao`, `organizacao_resolver_gestor_direto`,
`organizacao_resolver_subordinados_diretos`, `organizacao_resolver_descendentes`,
`organizacao_resolver_cadeia`, `organizacao_resolver_escopo_posicoes`,
`organizacao_resolver_escopo_unidades`
(`20260907170000_organization_resolution.sql:47,96,138,181,239,292,358`) —
`SECURITY INVOKER`, `STABLE`, `set search_path = public`, EXECUTE só
`service_role`, **gestor direto sempre DERIVADO** (`:21-22`).

**Sucessão/responsabilidade avaliativa prontas (F3-09/F4-08):**
`organizacao_resolver_avaliador_avaliado`,
`materializar_responsabilidades_avaliacao`, `registrar_sucessao_avaliador`
(redefinida com guard cross-tenant em `20260908130000…:19`),
`resolver_responsavel_avaliacao_vigente` (`20260907190000…:113,301,362,499`).

**Vínculo (F5-02) pronto:** `vincular_colaborador`, `desativar_vinculo_colaborador`,
`trocar_vinculo_colaborador`, `resolver_collaborator_vinculado`
(`20260909020000…:29,98,122`; `20260909000000…:22`), INVOKER, EXECUTE só
`service_role`; unicidade ativa por índices parciais (F5-02
`20260909010000…:30-50`).

**Plano administrativo já decidido (F5-04):** `usuario_eh_administrador`
(membership ativa + assignment ativa de role de sistema no tenant) e as RPC
`conceder_acesso_role_rpc`/`revogar_acesso_role_rpc`, com trilha append-only
(`20260910020000_f5_04_admin_rpc_functions.sql:39-63,103-135,177-200`).

### 2.4 Banco: RLS, grants e autoria (o que falta)

- **RLS habilitada em todas as 24 tabelas**, mas **F3/F4-01/F4-02 não criam
  policy alguma** — deny-by-default (ex.: `20260907103100…:320-334`).
- A **F4-08** acrescentou **apenas** policies `SELECT` own-tenant (helper
  `user_has_active_membership`, `20260908100000…:26`) e concedeu **apenas
  `SELECT`** a `authenticated`, depois de `revoke all on all tables in schema
  public from anon, authenticated` (`20260908140000…`). **Não existe policy de
  INSERT/UPDATE/DELETE** em nenhuma tabela estrutural: mutação direta pelo
  cliente é impossível hoje; mutação estrutural só por RPC/transação
  (F4-08 D7).
- `collaborator_status_periods` **não tem** `organization_id` (filha indireta);
  a policy usa `EXISTS` via `collaborators`
  (`20260908110000_f4_08_rls_select_own_tenant.sql:81-90`).
- `membership_collaborator_links`, `access_role_assignment_scopes`,
  `access_role_assignment_unit_targets`, `evaluation_succession_events`,
  `access_roles`, `access_role_capabilities`,
  `membership_access_role_assignments` e `privilege_mutation_audit` estão
  **sem policy e sem grant** a `authenticated` (deliberado).
- **Autoria ausente nas tabelas F3:** `collaborators`,
  `collaborator_identifiers`, `collaborator_status_periods`, `occupations`,
  `position_reporting_lines`, `temporary_responsibilities` **não têm**
  `created_by`/`updated_by` — a própria migration registra a ausência como
  limitação (`20260907140000…:46-50`, `20260907150000…:43-45`,
  `20260907160000…:51-53`). Exceções: `access_role_assignment_scopes.created_by`
  e `evaluation_succession_events.author_user_profile_id`.
- **Não existe** coluna de pessoa (nome/e-mail/documento/telefone) em nenhuma
  tabela (`collaborators` só tem identidade + técnicos).
- **Não existe** tabela de histórico organizacional nem de auditoria de
  mutações estruturais (a única trilha append-only estrutural é
  `privilege_mutation_audit`, restrita a privilégios).
- **Guard do CI exige catalogação**: toda tabela `public` precisa estar no
  catálogo classificado de `supabase/validacao/02-validar-f4-08.sql:265-292` e
  no espelho de `03-validar-f4-08-mutacoes.sql:60-76`; tabela nova não
  catalogada **reprova o CI**.

### 2.5 Autorização hoje (o que já decide corretamente)

- Allowlist capability × target (`src/authorization/policyEngine/capabilityTarget.ts:15-72`):
  `collaborator.read`/`collaborator.create`/`collaborator.edit` →
  `["collaborator"]` ✅; `org.structure.manage`, `org.catalog.manage`,
  `membership.read`, `membership.manage`, `access_role.manage` → `[]` ⇒
  **DENY no engine** (resolução administrativa, externa ao engine).
- Scopes fechados: `SELF`, `DIRECT_REPORTS`, `DESCENDANTS`,
  `ORGANIZATIONAL_UNIT`, `ORGANIZATION`, `ASSIGNED`
  (`src/authorization/policyEngine/types.ts:12-18`); `ASSIGNED` **não é
  wildcard** (`providers/assigned.ts:4-11`); escopo é propriedade da atribuição
  e resolvido **por capability** (`providers/reais.ts`); assignment sem linha de
  scope ⇒ fail-closed (F4-02 D14/D15).
- Hierarquia derivada da estrutura (`providers/structure.ts:12-17,32-102`);
  `funcao`/`cargo`/`job_role` **proibidos** como prova (F4-10-matriz §4).
- **ResourceContext real já reconhece** `collaborator`, `position` e
  `organizational_unit` como tipos soberanos
  (`src/authorization/resourceContextReal.ts:21-26`), com
  `domainStateEstrutural = { allows: () => true }` (`:97`, "a estrutura F3 não
  define predicado de lifecycle") e recusa de alvos sintéticos globais
  (`:88-90,178-182`).
- Hoje, o "mundo funcional" do Policy Engine é alimentado por
  `getColaboradores()` do `localStorage`
  (`src/authorization/authorizationPolicy.ts:1,61`; falha de storage ⇒ `[]` ⇒
  DENY) — é **este** acoplamento que a F5-07 elimina.
- Revogação vale na operação seguinte e **não existe cache de decisão entre
  requests** (F4-10 §18; `providers/reais.ts:31-32`).

### 2.6 Telas e consumidores (impacto real do cutover)

| Tela/consumidor | Estado |
| --- | --- |
| `InicioPage` (`/`) | roteia por `funcao` (`src/pages/InicioPage.tsx:12`); renderiza `ColaboradoresPage` para GERENTE/COORDENADOR |
| `ColaboradoresPage` (sem rota própria, vive em `/`) | lê `getColaboradores()` no render (`:19`); filtro/agrupamento por **texto** `respondePara` (`:55,73`); botões por `funcao` (`:168,187,209`); chave de lista = matrícula (`:345,375,391`) |
| `NovoColaboradorPage` (`/colaboradores/novo`) | escreve `saveColaborador` (`:166`) + histórico (`:168`); tudo síncrono; matrícula validada no cliente (`:126-131`) |
| `EditarColaboradorPage` (`/colaborador/:id/editar`) | `:id` = **matrícula** (`:38,41`); escreve `updateColaborador` (`:233`) + movimentação (`:236`); `useState` inicializado do storage e nunca ressincronizado (`:49-74`) |
| `ColaboradorDetalhePage` (`/colaborador/:id`) | `:id` = matrícula (`:313,335`); 8 leituras síncronas no render (`:316,337,357,398,427,430,454,458`); avaliações vindas **só** do acervo legado (`:430`); histórico recomputado na tela (`:263-310`) |
| Serviços que tratam a lista local como autoridade | `permissaoAvaliacao.ts:5,21`, `metaStorage.ts:5,6`, `cicloEquipeService.ts:3,6`, `cancelamentoCicloService.ts:9`, `reaberturaCicloService.ts:9`, `correcaoPeriodoCicloService.ts:13`, `visibilidadeColaboradores.ts:22` |
| Código morto divergente | `src/components/ColaboradoresPage.tsx` — cópia não roteada, com botão "Novo colaborador" **sem gate** (`:95-102`) |
| Testes de tela | **não existem** para `ColaboradoresPage`, `NovoColaboradorPage`, `EditarColaboradorPage`, `InicioPage`; existe só `ColaboradorDetalhePage.test.tsx` (23 linhas, um helper) |

### 2.7 Lacunas objetivas (G1–G12)

| # | Lacuna | Consequência |
| --- | --- | --- |
| **G1** | Nenhum CRUD soberano de colaborador (nenhuma RPC, nenhum caminho de escrita) | Impossível operar sem `localStorage` |
| **G2** | `collaborators` não guarda dados de pessoa (nome/e-mail) | A UI não tem identidade legível no banco |
| **G3** | Autoria ausente nas tabelas F3 | Mutações estruturais não são atribuíveis |
| **G4** | Nenhuma tabela de histórico organizacional / auditoria estrutural | Histórico e trilha seguem locais |
| **G5** | Nenhuma policy de escrita e nenhuma RPC de estrutura | Estrutura só é gravável por superuser |
| **G6** | `org.structure.manage`/`org.catalog.manage` têm target `[]` no engine | Não há caminho de enforcement definido para estrutura |
| **G7** | Sem projeção soberana "colaborador vigente" (status + ocupação + hierarquia na data) | Cada consumidor recalcularia por conta própria |
| **G8** | Matrícula como identidade de rota/lista/decisão | Vaza a identidade errada para a fronteira confiável |
| **G9** | Nenhuma capability/RPC para transição de status de colaborador | `active/leave/inactive` não é operável |
| **G10** | Nenhuma capability/RPC para mudança de gestor/unidade/posição | Movimentação não é operável |
| **G11** | Nenhum teste de tela de colaborador | Cutover sem rede de proteção |
| **G12** | Catálogo `job_roles` sem código estável (só `name` textual) | O `funcao` legado não tem de onde ser derivado sem heurística textual |

### 2.8 Divergências baseline × objetivo (resolvidas neste contrato)

| Baseline local | Tratamento na F5-07 |
| --- | --- |
| `matricula` como identidade | `collaborators.id` (UUID) é a identidade; matrícula vira **intenção** (D2) |
| `gestorDiretoMatricula` gravado no colaborador | **Derivado** de `position_reporting_lines` + `occupations` (D4) |
| `cargo`/`area`/`funcao`/`senioridade` no colaborador | Derivados da **ocupação vigente** (D4/D5) |
| Snapshot `anterior`/`atual` por movimentação | Delta estruturado no log append-only (§11/§12) |
| Recomputação local do estado por data | Resolução **server-side** por data (§11.3) |
| `autorMatricula`/`autorNome` | `actor_user_profile_id` soberano (D8) |
| Seed e gestores injetados na leitura | Proibido: a leitura não escreve e não inventa registros (I7) |

## 3. Escopo

1. **Colaborador**: identidade, dados de pessoa, identificador de negócio
   (matrícula), status/vigência.
2. **Alocação estrutural**: ocupação (colaborador × posição), reporting line
   (posição × posição), responsabilidade temporária, colegiado e sucessão —
   apenas **escrita via RPC** e **leitura**; a administração dos catálogos e das
   unidades/posições não pertence à F5-07 (§20.5).
3. **Histórico organizacional** soberano e auditável, incluindo o escopo por
   ciclo herdado do baseline.
4. **Fronteira confiável**: Edge Function própria, ActorContext/ResourceContext
   reais, Policy Engine antes de toda mutação privilegiada.
5. **RLS/grants** das tabelas envolvidas, incluindo a catalogação obrigatória no
   guard do CI.
6. **Cutover** das telas/serviços de colaborador e histórico, com testes de
   navegação/autorização e validadores SQL.

## 4. Fora de escopo (explícito)

- Ciclos (F5-08), metas (F5-09), observações (F5-10), validação transversal
  (F5-11), hardening (Etapa 6).
- CRUD de `organizational_units`, `organizational_unit_parent_periods`,
  `organizational_positions`, `job_roles`, `seniority_levels`,
  `collegiate_configurations` (administração de estrutura/catálogo).
- Importação do acervo legado de colaboradores/histórico/movimentações.
- Redesign visual, novos fluxos de produto e mudanças de regra de negócio não
  exigidas pela soberania (ex.: reabertura de status de desligado).
- Reabertura de qualquer `D#` fechada de F3/F4/F5.

## 5. Invariantes (I1–I14)

- **I1 — Identidade:** `collaborators.id` (UUID) é a identidade funcional;
  matrícula jamais é PK, FK de identidade ou prova de autoridade.
- **I2 — Tenant:** `organization_id` do colaborador/recurso é **derivado do
  recurso carregado** e revalidado contra membership ativa do ator; o tenant do
  payload é intenção.
- **I3 — Fail-closed:** ausência, ambiguidade, divergência de tenant, ausência
  de membership/vínculo/perfil ativo ⇒ **DENY**, com erro público estável.
- **I4 — Estrutura derivada:** cargo, área, função, senioridade e gestor
  derivam da ocupação/reporting line **na data pedida**; nunca de coluna do
  colaborador, de `funcao`, de cargo textual ou de `job_role`.
- **I5 — Temporalidade não destrutiva:** alteração de status, identificador,
  ocupação, reporting line e responsabilidade = **fechar a vigência e abrir
  nova**; nunca `UPDATE` que apague passado nem `DELETE`.
- **I6 — Histórico imutável:** o log de eventos é append-only, com autoria
  soberana, motivo, data de vigência e delta estruturado; evento e mutação na
  **mesma transação**.
- **I7 — Leitura não escreve:** nenhuma leitura pode criar, migrar, normalizar
  ou injetar registro; nenhum dado é inventado no caminho de leitura.
- **I8 — Sem autoridade local:** `localStorage`, estado React, matrícula,
  cargo textual, JWT, URL e payload **não** concedem autoridade; o browser é
  cliente.
- **I9 — Gate soberano:** toda mutação privilegiada passa por `authorize()`
  antes da execução; `service_role` é **executor**, nunca decisão; nenhuma
  regra de autorização paralela é criada.
- **I10 — Revogação imediata:** revogar membership/role/vínculo vale na
  **operação seguinte**, sem logout e sem cache de decisão entre requests.
- **I11 — RLS como barreira:** toda tabela nova nasce com `ENABLE RLS`, policy
  de leitura own-tenant e **nenhuma** policy de escrita para `authenticated`;
  mutação só por RPC `SECURITY INVOKER` com EXECUTE restrito a `service_role`.
- **I12 — Sem `SECURITY DEFINER` novo:** nenhuma função desta atividade pode ser
  `DEFINER`; os DEFINER existentes permanecem como estão.
- **I13 — Sem dual-write:** nenhuma operação escreve simultaneamente em
  PostgreSQL e `localStorage`; a partir do cutover de escrita existe **uma**
  autoridade.
- **I14 — Escopo é alcance, não permissão:** `SELF`/`DIRECT_REPORTS`/
  `DESCENDANTS`/`ORGANIZATIONAL_UNIT`/`ORGANIZATION`/`ASSIGNED` continuam
  resolvidos por dados e por capability; `ASSIGNED` continua **sem** hierarquia
  e **sem** wildcard.

## 6. Modelo de dados

### 6.1 Princípio: reuso máximo, extensão aditiva mínima

A F5-07 **não** redesenha a estrutura F3: ela já contém identidade,
identificadores com vigência, status com vigência, catálogos, unidades,
posições, reporting lines, ocupações, responsabilidades temporárias, colegiado
e sucessão (tabela em §2.3). São necessárias apenas **três intervenções**:

| # | Intervenção | Tipo |
| --- | --- | --- |
| 1 | Dados de pessoa no colaborador (`full_name`, `email`, `admission_date`) | `ALTER TABLE … ADD COLUMN` aditivo em `collaborators` (D3) |
| 2 | Código estável nos catálogos (`code`) para derivação do rótulo operacional | `ALTER TABLE … ADD COLUMN` aditivo em `job_roles` (D5) |
| 3 | Log append-only de eventos/movimentações do colaborador | **tabela nova** `collaborator_events` (D8), que não tem equivalente existente |

Nenhuma outra tabela nova. Nenhuma coluna desnormalizada de gestor, cargo,
área, função ou senioridade.

### 6.2 `collaborators` (extensão aditiva — D3)

```
full_name      text        not null          -- nome canônico da pessoa
email          text        not null          -- contato; normalizado (trim, lowercase)
admission_date date        null              -- admissão declarada (histórico tem a vigência)
```

- `check (full_name <> '' and full_name = btrim(full_name))`;
  `check (email <> '' and email = btrim(email) and position('@' in email) > 1)`;
  unique **por organização** de `email` (índice parcial, apenas colaboradores
  não desligados): `uq_collaborators_org_email`.
- Sem vigência: nome/e-mail **não** são autoridade nem hierarquia; a evolução
  fica no log (D3, alternativa rejeitada em §18).
- `version` (já existente) passa a ser **obrigatório** nas mutações (D13).

### 6.3 `job_roles.code` (extensão aditiva — D5)

```
code text null   -- ex.: GERENTE | COORDENADOR | CONSULTOR | ANALISTA | ESTAGIARIO
```

- Unique por organização quando não nulo: `uq_job_roles_org_code`.
- Backfill **por organização** a partir do `name` (mapa determinístico
  documentado na migration), sem renomear nada.
- **Uso permitido:** rótulo operacional e compatibilidade com o `funcao` legado
  (UX/derivação de exibição). **Uso proibido:** autorização, hierarquia, escopo,
  requisito de avaliador ou qualquer decisão do Policy Engine — validado por
  teste negativo (T-22, §16.2).
- **Não contradiz a F5-06 D16/D17:** o rótulo **não** é consultado em nenhum ponto
  do cálculo oficial, da configuração de avaliação, da exigência/cardinalidade de
  participantes ou da resolução de responsáveis avaliativos (F3-09) — essas
  decisões continuam vindo da estrutura/posição e do snapshot congelado.

### 6.4 `collaborator_events` (tabela nova — D8)

```
id                       uuid        not null default gen_random_uuid()
organization_id          uuid        not null
collaborator_id          uuid        not null
event_type               text        not null
effective_date           timestamptz not null
cycle_scope              text        not null default 'CICLO_ATUAL_E_POSTERIORES'
reference_cycle_id       uuid        null
reason                   text        not null
before_value             jsonb       null
after_value              jsonb       null
actor_user_profile_id    uuid        not null
actor_membership_id      uuid        not null
operation_id             uuid        not null
created_at               timestamptz not null default now()
```

| Regra | Definição |
| --- | --- |
| `event_type` | `ADMISSAO`, `DADOS_PESSOAIS_ALTERADOS`, `IDENTIFICADOR_DEFINIDO`, `IDENTIFICADOR_ENCERRADO`, `STATUS_ALTERADO`, `OCUPACAO_INICIADA`, `OCUPACAO_ENCERRADA`, `REPORTING_LINE_INICIADA`, `REPORTING_LINE_ENCERRADA`, `RESPONSABILIDADE_INICIADA`, `RESPONSABILIDADE_ENCERRADA`, `SUCESSAO_REGISTRADA` (conjunto ampliável só por nova migration) |
| `cycle_scope` | `CICLO_ATUAL_E_POSTERIORES` ou `SOMENTE_CICLOS_POSTERIORES` — **preserva** a regra de baseline `movimentoValeParaCiclo` (`historicoOrganizacionalStorage.ts:176-190`) |
| FKs | `(collaborator_id, organization_id)` → `collaborators(id, organization_id)`; `(reference_cycle_id, organization_id)` → `evaluation_cycles(id, organization_id)` (unicidade já existe: `uq_evaluation_cycles_id_organization`, `20260911000000…`); `actor_user_profile_id` → `user_profiles(id)`; `(actor_membership_id, organization_id)` → `user_organization_memberships(id, organization_id)` |
| Tenant | `organization_id` **nunca** é autoridade do payload: deriva do colaborador carregado e da membership do ator (I2) |
| Append-only | trigger que **levanta exceção** em `UPDATE`; `DELETE` revogado; `service_role` recebe **somente `INSERT`** (mesmo padrão de `evaluation_events`, F5-06 D26) |
| Idempotência | `unique (organization_id, operation_id)` — retry de rede não duplica evento nem mutação (D13) |
| Leitura | policy `SELECT` own-tenant (via `EXISTS` no colaborador, como `collaborator_status_periods`), sem acesso de `authenticated` a `before_value`/`after_value` quando confidencial (§10.3) |

**Por que uma tabela nova é inevitável:** o baseline tem uma entidade
"movimentação" (tipo, vigência, motivo, escopo por ciclo, ciclo de referência,
autor e snapshots antes/depois — `src/types/HistoricoOrganizacional.ts:30-45`)
que **não** é derivável das tabelas temporais: autor, motivo por operação,
escopo por ciclo e o par antes/depois não existem nelas, e as tabelas F3
registram apenas o resultado. As tabelas temporais seguem sendo a **verdade do
estado em cada data**; o log é a **verdade da mudança** (§11.1).

### 6.5 Projeção soberana do colaborador (leitura)

Funções `SECURITY INVOKER`, `STABLE`, `set search_path = public`, EXECUTE só
`service_role`:

- `colaborador_visao_listar(p_organization_id uuid, p_actor_user_profile_id uuid, p_data timestamptz, p_filtros jsonb)` —
  devolve, por colaborador do tenant: `collaborator_id`, `business_code`
  vigente, `full_name`, `email`, `status` vigente, `ativo_em`, unidade vigente
  (`unit_id`/`unit_name`), `job_role_code`/`job_role_name`, `seniority_name`,
  `manager_collaborator_id`/`manager_full_name` (por
  `organizacao_resolver_gestor_direto`), `colegiado_ids`, `admission_date`.
- `colaborador_visao_obter(...)` — mesma projeção para um colaborador (por UUID
  ou por matrícula resolvida **no servidor**).
- `colaborador_historico_listar(...)` — linha do tempo (eventos + vigências)
  por data e por ciclo.

Regras da projeção: nada de coluna desnormalizada; nada de escrita; ausência de
ocupação vigente ⇒ campos estruturais `NULL` (não erro); ausência de status
vigente ⇒ fail-closed na operação que exigir status; colaborador de outro
tenant ⇒ `NOT_FOUND` (indistinguível de inexistente).

### 6.6 Matriz de origem de cada campo consumido pela UI

| Campo legado (`Colaborador`) | Origem soberana |
| --- | --- |
| `matricula` | `collaborator_identifiers.business_code` da linha **aberta** |
| `nome`, `email` | `collaborators.full_name` / `.email` |
| `status` | `collaborator_status_periods.status` vigente na data |
| `cargo` | `job_roles.name` da posição vigente |
| `area` | `organizational_units.name` da posição vigente |
| `funcao` | `job_roles.code` da posição vigente (rótulo; nunca autorização) |
| `senioridade` | `seniority_levels.name` da posição vigente |
| `gestorDiretoMatricula` (`respondePara`) | `organizacao_resolver_gestor_direto(colaborador, data)` → colaborador responsável da posição superior (UUID + nome) |
| `avaliadoresColegiadoMatriculas` | `collegiate_configuration_members` vigentes |
| `dataAdmissao` | `collaborators.admission_date` (declarado) **ou** vigência do evento `ADMISSAO` |
| `dataInicio/FimLicenca`, `dataDesligamento` | vigências de `collaborator_status_periods` (`leave`/`inactive`) |

## 7. Trust boundaries

```
browser (cliente)                     │ fronteira confiável                        │ banco
──────────────────────────────────────┼────────────────────────────────────────────┼────────────────────────
tela → porta TS (intenção)            │ Edge Function `colaboradores`              │ RPC INVOKER
  · UUID OU matrícula (intenção)      │  1. valida FORMA do payload                │  · revalida ator/membership/tenant
  · organização ativa (intenção UX)   │  2. auth.getUser (auth.uid soberano)       │  · aplica invariantes temporais
  · nunca capability/role/tenant      │  3. ActorContext real (perfil+membership)  │  · grava estado + evento (1 tx)
    como prova                       │  4. carrega RECURSO soberano → ResourceCtx │  · devolve projeção
                                      │  5. Policy Engine / authorize (gate)       │
                                      │  6. executor service_role → RPC            │
                                      │  7. erro público estável (sem vazar)       │
```

- O cliente **não** recebe nada que prove autoridade: nem capability, nem
  role, nem scope, nem status interno, nem a lista de tenants.
- `NOT_FOUND` e `FORBIDDEN` permanecem **indistinguíveis** para o cliente
  (padrão F5-05/F5-06) — nenhum vazamento de existência cross-tenant.
- O tenant do recurso vem da **linha carregada**; divergência com a organização
  validada do ator ⇒ DENY (`resourceContextReal.ts:134-142`).
- O `organization_id` da organização ativa do browser é **intenção**: entra
  como filtro de UX e é revalidado contra a membership ativa (I2).

## 8. Operações e contratos

**Fronteira:** nova Edge Function `supabase/functions/colaboradores`, com o
mesmo esqueleto da `avaliacoes` (config obrigatória, `service_role` sem sessão,
método, JWT obrigatório, `auth.getUser`, validação de forma, ponte
matrícula→UUID, Policy Engine, executor, erro público). Operações nomeadas
`dominio.verbo`.

### 8.1 Catálogo de operações

| Operação | Intenção (payload) | Capability | RPC (executor) | Efeito |
| --- | --- | --- | --- | --- |
| `collaborator.listar` | `organization_id`, `data_referencia?`, filtros (unidade, status, busca) | `collaborator.read` (escopo) | `colaborador_visao_listar` | leitura |
| `collaborator.obter` | `collaborator_id` **ou** `matricula` | `collaborator.read` (escopo) | `colaborador_visao_obter` | leitura |
| `collaborator.criar` | `organization_id`, `full_name`, `email`, `matricula`, `admission_date?`, `status_inicial?` | `collaborator.create` | `colaborador_criar` | cria `collaborators` + `collaborator_identifiers` + `collaborator_status_periods` + evento `ADMISSAO` |
| `collaborator.editar` | `collaborator_id`, `full_name?`, `email?`, `admission_date?`, `expected_version` | `collaborator.edit` | `colaborador_editar` | atualiza pessoa + evento `DADOS_PESSOAIS_ALTERADOS` |
| `collaborator.identificador.definir` | `collaborator_id`, `nova_matricula`, `vigencia`, `motivo` | `collaborator.edit` | `colaborador_identificador_definir` | fecha `business_code` vigente, abre novo + evento |
| `collaborator.status.alterar` | `collaborator_id`, `novo_status ∈ (active,leave,inactive)`, `vigencia`, `motivo` | `collaborator.edit` | `colaborador_status_alterar` | fecha período vigente, abre novo + evento `STATUS_ALTERADO` |
| `colaborador.ocupacao.definir` | `collaborator_id`, `position_id`, `vigencia`, `motivo`, `cycle_scope?`, `reference_cycle_id?` | `org.structure.manage` (administrativo, §9.2) | `estrutura_ocupacao_definir` | fecha ocupação vigente, abre nova + evento |
| `colaborador.ocupacao.encerrar` | `collaborator_id`, `vigencia`, `motivo` | idem | `estrutura_ocupacao_encerrar` | fecha ocupação vigente + evento |
| `estrutura.reporting.definir` | `subordinate_position_id`, `manager_position_id`, `vigencia`, `motivo` | idem | `estrutura_reporting_definir` | fecha linha vigente, abre nova + evento |
| `estrutura.reporting.encerrar` | `subordinate_position_id`, `vigencia`, `motivo` | idem | `estrutura_reporting_encerrar` | fecha linha vigente + evento |
| `estrutura.responsabilidade.definir` | `position_id`, `substitute_collaborator_id`, `responsibility_type`, `vigencia`, `motivo` | idem | `estrutura_responsabilidade_definir` | abre responsabilidade temporária + evento |
| `estrutura.responsabilidade.encerrar` | `responsibility_id`, `vigencia`, `motivo` | idem | `estrutura_responsabilidade_encerrar` | fecha responsabilidade + evento |
| `estrutura.sucessao.registrar` | `responsibility_ids[]`, `succession_date`, `motivo` | idem | `registrar_sucessao_avaliador` (**já existe**, F3-09/F4-08) | materializa sucessão + evento `SUCESSAO_REGISTRADA` |
| `colaborador.historico.listar` | `collaborator_id`, `data_referencia?`, `ciclo?` | `collaborator.read` (escopo) | `colaborador_historico_listar` | leitura da linha do tempo |

### 8.2 Contrato de cada operação (forma comum)

- **Entrada validada por FORMA**, nunca por autoridade: UUIDs com formato
  validado; datas ISO; `motivo` obrigatório (trim, não vazio, limite de
  tamanho); `expected_version` inteiro quando a operação muta uma linha
  existente; `operation_id` UUID obrigatório (idempotência).
- **Intenção vs autoridade:** `organization_id`, `matricula` e qualquer
  atributo derivado são intenção; a fronteira resolve o alvo soberano
  (`collaborator_id` + `organization_id` reais) antes do Policy Engine.
- **Resposta:** `{ ok: true, operacao, resultado }` em sucesso; erro público
  estável em falha (`FORBIDDEN` 403, `NOT_FOUND` 404, `CONFLICT` 409,
  `INVALID_INPUT` 400, `INTERNAL` 500, `NOT_AUTHORIZED` 401), com mensagem
  genérica e sem detalhe interno.
- **`CONFLICT`** cobre: `expected_version` divergente, violação de vigência
  (sobreposição), transição de status inválida, `inactive` com ocupação aberta,
  matrícula já existente na organização, `operation_id` repetido com payload
  diferente.
- **Nenhuma operação aceita** `capability`, `role`, `scope`, `actor_*` ou
  `organization_id` como prova; `actor_user_profile_id` é **sempre** resolvido
  pela fronteira a partir do JWT.

### 8.3 Regras de negócio por operação (preservação do baseline)

- `collaborator.criar`: exige matrícula normalizada e única **na organização em
  qualquer vigência** (regra atual do banco:
  `uq_collaborator_identifiers_organization_code`); cria o período de status
  inicial (`active` por padrão, `leave` permitido); **não** cria estrutura
  (se o payload trouxer posição, a operação é composta: `colaborador.criar`
  seguida de `colaborador.ocupacao.definir`, ambas autorizadas e auditadas); a
  operação composta é **transacional** (uma transação, dois eventos) para não
  deixar colaborador sem alocação por falha parcial.
- `collaborator.editar`: **não** altera matrícula, status, estrutura nem
  hierarquia (cada um tem operação própria e auditável); exige
  `expected_version`.
- `collaborator.status.alterar`: transições permitidas na F5-07:
  `active → leave`, `leave → active`, `active → inactive`, `leave → inactive`.
  `inactive → *` fica **fora de escopo** (readmissão exige atividade própria). A
  data de vigência deve ser posterior ao início do período vigente. Transição
  para `inactive` **exige** que não exista ocupação/reporting line/responsabilidade
  vigente do colaborador: a RPC devolve `CONFLICT` com a lista do que falta
  encerrar — **não** fecha nada silenciosamente (D6), respeitando o trigger
  `enforce_collaborator_inactive_requires_closed_occupations`
  (`20260907150000…:218`).
- `collaborator.identificador.definir`: fecha a linha aberta (`valid_to`) e
  insere a nova aberta; **nunca** reutiliza código dentro da organização; a
  exclusão de sobreposição do banco continua sendo a última barreira.
- Ocupação/reporting line: validação de tenant por FK composta (já existente),
  coerência temporal (não sobrepor), proibição de auto-reporting (já existente)
  e detecção de ciclo na hierarquia pelo trigger
  `enforce_position_reporting_lines_no_cycle`
  (`20260907140000…:256-303`, com lock de transação por organização).
- Sucessão: **reuso direto** de `registrar_sucessao_avaliador`, que já grava
  `author_user_profile_id` e tem guard cross-tenant (F4-08).

## 9. Autorização

### 9.1 Dois planos (herdados, não reinventados)

| Plano | Capacidades | Gate |
| --- | --- | --- |
| **Funcional (conteúdo sobre o colaborador)** | `collaborator.read`, `collaborator.create`, `collaborator.edit` | **Policy Engine** (`authorize()`) — targets `["collaborator"]` já compatíveis |
| **Administrativo (estrutura/catálogo)** | `org.structure.manage` (e futuramente `org.catalog.manage`) | **plano administrativo já decidido na F5-04**: membership ativa + assignment ativa de role de sistema no tenant, server-side (`usuario_eh_administrador`, `20260910020000…:39-63`), com trilha append-only — ver `Q1` em §19 |

Isso **não** cria autorização paralela: o plano administrativo é o já fechado
pela F4-01/F4-09 (plano administrativo de controle ≠ plano funcional) e
implementado pela F5-04; o plano funcional continua sendo o Policy Engine. A
F5-07 apenas **usa** os dois caminhos, sem inventar um terceiro.

### 9.2 Mapeamento operação → capability → gate

| Operação | Capability | Gate | Target/alcance |
| --- | --- | --- | --- |
| `collaborator.listar` | `collaborator.read` | engine | `collaborator` (escopo filtra o universo) |
| `collaborator.obter` | `collaborator.read` | engine | `collaborator` do alvo (SELF/DIRECT_REPORTS/DESCENDANTS/UNIT/ORGANIZATION) |
| `collaborator.criar` | `collaborator.create` | engine | `collaborator` (novo) + organização validada |
| `collaborator.editar` | `collaborator.edit` | engine | `collaborator` do alvo |
| `collaborator.identificador.definir` | `collaborator.edit` | engine | `collaborator` do alvo |
| `collaborator.status.alterar` | `collaborator.edit` | engine | `collaborator` do alvo |
| `colaborador.ocupacao.*` | `org.structure.manage` | administrativo | organização + `position` |
| `estrutura.reporting.*` | `org.structure.manage` | administrativo | organização + `position` |
| `estrutura.responsabilidade.*` | `org.structure.manage` | administrativo | organização + `position` |
| `estrutura.sucessao.registrar` | `org.structure.manage` | administrativo | organização + `position` |
| `colaborador.historico.listar` | `collaborator.read` | engine | `collaborator` do alvo |

**Nenhuma capability nova é criada.** As capabilities necessárias já existem no
catálogo canônico (`20260908000001_authorization_system_catalog.sql:29-36`) e no
bundle `admin` da F5-04. `collaborator.manage` (deprecada) **não** é usada.

### 9.3 ActorContext e ResourceContext (N)

- **ActorContext** (server-side, na Edge): `auth.uid()` → `user_profiles`
  (`status='active'`) → membership ativa na organização → link ativo →
  `collaboratorId` (UUID, pode ser `null` para ADMIN sem vínculo, como em
  F5-05 D14). Nenhuma identidade vem do payload.
- **ResourceContext** para operações de conteúdo: `kind: "collaborator"`,
  `target: { type: "collaborator", id: <uuid> }`, `organizationId` **da linha
  carregada**, `ownerCollaboratorId` = o próprio colaborador alvo,
  `structure.positionId`/`unitId` da ocupação vigente (para resolução de
  escopo), `domainState` = predicado do domínio (§9.4).
- Operações estruturais carregam `position`/`organizational_unit` como recurso
  (§9.2). Os tipos `cycle`, `goal`, `observation` **continuam não
  autorizáveis** (D19/D22 da F5-05) — nenhuma exceção é aberta aqui.

### 9.4 Onde `authorize()` ocorre (O)

- **Somente na fronteira confiável**, **antes** de qualquer RPC privilegiada
  (F5-06 D27). Nenhuma página ou serviço local decide acesso; `can()` no
  cliente permanece **apenas UX** (I9).
- Predicado de domínio por operação (o `domainState` real):
  - leitura: permite (a estrutura não tem predicado de lifecycle — F5-05
    `domainStateEstrutural`), com o escopo definindo o alcance;
  - `collaborator.editar`: exige status vigente `active` ou `leave`;
  - `collaborator.status.alterar`: exige transição válida e vigência coerente;
  - ocupação/reporting line/responsabilidade: exige colaborador não `inactive`
    (e, quando aplicável, posição vigente na data);
  - histórico: permite leitura sob o mesmo escopo da leitura do colaborador.
- Códigos de recusa: ausência de perfil/membership/vínculo ⇒ `NOT_AUTHORIZED`/
  `FORBIDDEN`; alvo de outro tenant, inexistente ou sem permissão ⇒ `NOT_FOUND`
  (indistinguível); estado inválido ⇒ `CONFLICT`.
- **Não contradiz a F5-05:** ela declarou `domainStateEstrutural =
  { allows: () => true }` porque a estrutura F3 **não** definia predicado de
  lifecycle (`resourceContextReal.ts:92-97`). Os predicados acima são **novos e
  específicos das operações introduzidas por esta atividade**; a leitura continua
  sempre permitida e nenhum contrato da F5-05 é alterado — apenas se passa a ter
  `domainState` real (em vez do probe permissivo) nas mutações que a F5-07 cria.

### 9.5 `service_role` e revogação

- `service_role` executa a RPC e **não** decide; o JWT do usuário **não** é
  propagado para o banco; o ator verificado atravessa como
  `p_actor_user_profile_id` e a RPC **revalida** perfil ativo + membership ativa
  no tenant do recurso (defesa em profundidade, padrão `evaluation_ator_valido`).
- Revogar membership, role ou vínculo produz efeito na **operação seguinte**
  (I10): toda chamada reconstrói ActorContext/provider por operação, sem cache
  de ALLOW entre requests.

## 10. RLS

### 10.1 O que a RLS garante (independentemente da aplicação)

RLS responde **"este dado pertence ao tenant do ator?"**; o Policy Engine
responde **"o ator pode executar esta ação?"** (F4-08 §1.2). Mesmo com API
direta, JWT manipulado ou `organizationId` forjado, a RLS impede leitura
cross-tenant, IDOR por UUID e *parent-swap* — porque a policy exige
`user_has_active_membership(organization_id)` com `auth.uid()`.

### 10.2 Policies necessárias

| Tabela | Ação |
| --- | --- |
| `collaborators`, `collaborator_identifiers`, `collaborator_status_periods`, `occupations`, `position_reporting_lines`, `temporary_responsibilities` | manter `SELECT` own-tenant (F4-08) |
| `collaborator_events` (**nova**) | `ENABLE RLS` + `SELECT` own-tenant via `EXISTS` no colaborador; **nenhuma** policy de INSERT/UPDATE/DELETE |
| `evaluation_succession_events`, `cycle_evaluation_responsibilities` | permanecem fechadas a `authenticated` (mantido); leitura administrativa via RPC |

Nenhuma policy `USING (true)` nova (o guard do CI reprova policy trivialmente
permissiva em tabela de tenant). Nenhum `FORCE RLS`.

### 10.3 Grants

- `authenticated`: **apenas `SELECT`** nas tabelas com policy own-tenant;
  `collaborator_events` idem; sem DML em nenhuma tabela estrutural.
- `service_role`: `SELECT`/`INSERT`/`UPDATE` conforme a operação; em
  `collaborator_events` **somente `INSERT`** (e `SELECT` para a RPC de histórico);
  `DELETE` revogado nas tabelas temporais e no log.
- Funções: `revoke all … from public, anon, authenticated` +
  `grant execute … to service_role` em **todas** as RPC novas; nenhuma RPC nova
  acessível a `authenticated`.
- **Nenhuma função nova `SECURITY DEFINER`** (I12); o guard da F4-08 continua
  validando a lista de DEFINER existente.

### 10.4 Catalogação obrigatória (guard do CI)

`collaborator_events` **e** eventuais objetos novos entram:
1. no catálogo classificado de `supabase/validacao/02-validar-f4-08.sql` (toda
   tabela nova não classificada ⇒ FAIL);
2. no espelho literal de `supabase/validacao/03-validar-f4-08-mutacoes.sql`.
Sem isso o CI fica vermelho — é requisito de conclusão (§17).

## 11. Temporalidade e histórico

### 11.1 Duas verdades complementares

| Verdade | Onde vive | Responde |
| --- | --- | --- |
| **Estado em cada data** | tabelas temporais (`collaborator_status_periods`, `collaborator_identifiers`, `occupations`, `position_reporting_lines`, `temporary_responsibilities`, `organizational_*`) | "quem era o gestor em 2026-03-31?", "qual o status no ciclo X?" |
| **Mudança** | `collaborator_events` (append-only) | "quem mudou, quando, por quê, com que escopo e qual era o valor anterior?" |

O log **nunca substitui** o estado atual nem é autoridade de tenant/ator (D26
da F5-06 é reaplicado aqui): `before_value`/`after_value` são registro, não
fonte de decisão.

### 11.2 Escopo por ciclo (preservação do baseline)

O baseline permite que uma movimentação valha "do ciclo atual em diante" ou
**somente para ciclos posteriores** (`SOMENTE_CICLOS_POSTERIORES`,
`src/types/HistoricoOrganizacional.ts:14-16`;
`historicoOrganizacionalStorage.ts:176-190`). A F5-07 **preserva** a regra
registrando `cycle_scope` + `reference_cycle_id` no evento; a **aplicação** da
regra a um ciclo concreto depende da entidade de ciclo soberana (**F5-08**) e
fica registrada como contrato de dependência (§20.1). Enquanto isso, a leitura
de aplicabilidade por ciclo permanece no caminho legado **sem** adquirir
autoridade (nada é escrito).

### 11.3 Leitura histórica

- Data de referência é **parâmetro** da operação; o servidor resolve o estado
  vigente **naquela data** (nunca "hoje" implícito, nunca estado atual como
  fallback anacrônico — o fallback atual `historicoOrganizacionalStorage.ts:277-279`
  é removido).
- Sem histórico: o estado exibido é o **estado vigente real** das tabelas
  temporais (não o cadastro "atual" reescrito).
- Ausência de período vigente na data ⇒ campos `NULL` para o que não existia
  (ex.: colaborador ainda não admitido) ⇒ a operação de negócio que exigir
  aquele dado é recusada (fail-closed).

### 11.4 Não reescrita do passado

Nenhuma operação da F5-07 altera linha temporal já fechada (`valid_to`
preenchido) nem o log: correções retroativas exigem fluxo excepcional próprio,
autorizado e auditado, **fora do escopo** desta atividade (mantém a decisão da
F3-05/F3-04). Fechar a vigência atual e abrir outra é o único caminho de
mudança.

### 11.5 Sucessão e responsabilidades

- **Responsabilidade temporária**: reuso de `temporary_responsibilities` (F3-06)
  — substituto **não** herda capabilities do titular (F4-05) e o efeito é
  **derivado por data**, nunca persistido como grant.
- **Sucessão avaliativa**: reuso de `evaluation_succession_events` +
  `registrar_sucessao_avaliador` (F3-09/F4-08), que já grava autoria soberana;
  a estrutura vigente **não** reescreve o passado (F4-05 §9; HIST-004/005).
- **Colegiado**: reuso de `collegiate_configurations`/`_members` (F3-08) e dos
  snapshots de ciclo; `ASSIGNED` continua **derivado**, nunca copiado
  (F4-02 D6).

## 12. Autoria e auditoria

### 12.1 Modelo

Mesmo contrato de evento já fechado na F5-06 (D7/D26), aplicado ao domínio
estrutural: **operação crítica e evento na mesma transação**, evento
append-only, autoria soberana resolvida server-side, delta estruturado,
`payload` nunca como autoridade de tenant ou de ator.

### 12.2 Campos mínimos do evento

| Campo | Papel | Autoridade |
| --- | --- | --- |
| `organization_id` | tenant do fato | derivado do colaborador/recurso (nunca do payload) |
| `collaborator_id` | entidade afetada | resolvido na fronteira |
| `event_type` | o que aconteceu | derivado da operação executada |
| `effective_date` | vigência do efeito | parâmetro validado (data de efeito) |
| `cycle_scope`, `reference_cycle_id` | escopo por ciclo (baseline §11.2) | intenção validada |
| `reason` | motivo obrigatório | parâmetro validado (não vazio) |
| `before_value`, `after_value` | registro do delta | **não** é fonte de decisão |
| `actor_user_profile_id` | **autoria soberana** | `auth.uid()` verificado na Edge |
| `actor_membership_id` | âncora de autorização usada | membership ativa revalidada |
| `operation_id` | idempotência | gerado no cliente, único por organização |
| `created_at` | quando | `now()` do banco |

### 12.3 Autoria exige conta (limitação registrada)

O **operador** é sempre um `user_profile` autenticado (com membership ativa no
tenant): é ele quem responde pela mutação. O **colaborador afetado** pode não ter
conta — e não precisa ter: `collaborator_id` é identidade interna e não implica
login (F5-01 §4; F5-05 §5.3). Consequência: a trilha responde "quem operou", não
"quem autorizou pessoalmente a própria mudança"; não existe, nem na F5-06, ator
soberano sem conta, e a F5-07 **não** inventa um (D8).

### 12.4 Imutabilidade garantida no banco

Trigger que levanta exceção em `UPDATE` de `collaborator_events`; `DELETE`
revogado; `service_role` com **somente `INSERT`**; `authenticated` sem DML. A
trilha é lida por RPC (escopo de `collaborator.read` para o histórico do próprio
colaborador/equipe; administrativo para auditoria completa). Nenhuma operação da
F5-07 apaga ou edita evento.

### 12.5 O que a trilha responde

"Quem alterou o gestor deste colaborador, quando, com que vigência, por qual
motivo, com que escopo de ciclo, e qual era o valor anterior?" — auditável por
consulta, sem depender do cliente.

## 13. Concorrência

### 13.1 Versão otimista (obrigatória)

Toda operação que altera uma linha existente exige `expected_version` (coluna
`version` já existente no padrão F1-02). Divergência ⇒ `CONFLICT` (409) e
**nenhuma** escrita. Comparação e incremento dentro da mesma transação da RPC.

### 13.2 Barreiras temporais no banco

As invariantes temporais não dependem da aplicação: *exclusion constraints*
(sobreposição por colaborador/posição/subordinado), `ck_*_valid_to`,
`ck_position_reporting_lines_not_self` e o trigger anti-ciclo
(`enforce_position_reporting_lines_no_cycle`) permanecem a **última barreira**.
Nas operações estruturais a RPC toma o **lock de transação por organização**
(mesmo padrão da F3-04) para serializar leitura-antes-de-escrever da hierarquia.

### 13.3 Duas alterações simultâneas

Duas transações concorrentes sobre o mesmo colaborador/posição: a primeira fecha
a vigência e abre a nova; a segunda falha por `CONFLICT` (versão) ou por
sobreposição temporal (exclusion) — nunca produz duas vigências abertas nem
perda silenciosa.

### 13.4 Revogação entre leitura e mutação (TOCTOU)

A decisão de autorização **não** é reaproveitada: a RPC revalida
perfil/membership/tenant/vínculo na **mesma transação** da mutação (padrão
F5-06). Revogação entre a leitura da tela e o clique do usuário ⇒ a mutação é
negada (`FORBIDDEN`), mesmo que a tela ainda mostre o botão (`can()` é UX).

### 13.5 Idempotência de retry

`operation_id` único por organização: retry do mesmo pedido (mesmo
`operation_id` + mesmo payload) devolve o mesmo resultado sem duplicar evento ou
mutação; `operation_id` repetido com payload **diferente** ⇒ `CONFLICT` (nunca
"adivinha" a intenção).

## 14. Cutover

### 14.1 Fases (espelha F5-06 D12)

| Fase | Conteúdo | Critério de passagem |
| --- | --- | --- |
| **1. Schema/RPC/RLS** | extensões aditivas, `collaborator_events`, RPCs, policies, grants, validadores | validadores SQL verdes; guard F4-08 atualizado |
| **2. Paridade** | projeção soberana × baseline local (nome, matrícula, status, estrutura derivada) em cenário sintético | divergência zero onde o dado local é válido; divergências explicadas |
| **3. Cutover de escrita** | telas gravam **somente** pela Edge; escrita local vira barreira que lança | nenhuma escrita em `localStorage` nos fluxos migrados |
| **4. Cutover de leitura** | leituras server-first; `NOT_FOUND` do servidor ≠ negação | telas funcionam sem `localStorage` de colaboradores |
| **5. Remoção da autoridade local** | `colaboradorStorage`/`historicoOrganizacionalStorage` sem poder de decisão; dataset do Policy Engine vem do servidor | nenhum consumidor de produção lê colaborador do `localStorage` |

### 14.2 Evidência de cutover: ESTRUTURAL, nunca por data

Não existe marcador por registro como no `feedback` legado, porque colaborador
não é um agregado criado pelo usuário final em lote: a evidência é **estrutural**
— (i) o módulo local **não expõe caminho de escrita** (funções que lançam),
(ii) existe **uma** porta soberana de leitura/escrita, (iii) toda identidade que
atravessa a fronteira é UUID (`collaborators.id`), e (iv) id numérico legado
(matrícula) **não** é promovido por formato. Nenhuma heurística de data, de
formato ou de presença em `localStorage` classifica origem.

### 14.3 Comportamento das leituras

- Server-first: a tela pede ao servidor; a resposta é a autoridade.
- `NOT_FOUND` (inexistente **ou** não acessível, indistinguíveis) ⇒ estado vazio
  explícito; qualquer outro código ⇒ erro visível (**nunca** leitura local
  silenciosa).
- Ausência de configuração/caminho ⇒ **fail-closed** com erro reportado (padrão
  `acessoAvaliacoesSoberanas.ts:10-16`); não existe fallback para `localStorage`.

### 14.4 Comportamento das escritas

- Toda escrita vai para a Edge; a resposta só é sucesso com o registro
  confirmado server-side.
- `saveColaborador`, `updateColaborador`, `registrarMovimentacaoOrganizacional` e
  equivalentes tornam-se **barreiras que lançam** (fail-closed), como
  `feedbackStorage` na F5-06.
- **Sem dual-write** em nenhum momento (nem direto, nem reverso).

### 14.5 Dados existentes no `localStorage`

- Colaboradores/histórico locais: **legado somente leitura para exibição**, se e
  enquanto houver decisão de produto para isso; jamais autoridade; jamais fonte
  de escrita.
- Avaliações legadas continuam legíveis pelo caminho legado (F5-06), sem relação
  com esta atividade.
- O seed DEV (`src/data/colaboradores.ts`, impersonação) permanece **apenas**
  como fixture de desenvolvimento explicitamente *gated*, sem participar do
  caminho soberano nem de produção.

### 14.6 Ausência de dado soberano

- Colaborador inexistente no banco ⇒ `NOT_FOUND`; **não** se cria nada local e
  **não** se promove o registro local a autoridade.
- Organização sem estrutura cadastrada ⇒ colaborador existe como identidade +
  pessoa + identificador + status, **sem** alocação; a UI mostra "sem alocação" e
  as operações que exigem posição são recusadas (fail-closed). Nada de estrutura
  sintética e nada de hierarquia fabricada.

### 14.7 Bootstrap mínimo (somente o indispensável — D16)

Autoriza-se **apenas** um bootstrap de **catálogo**, idempotente e auditado, via
plano administrativo: criar/garantir `job_roles` (com `code`) e
`seniority_levels` da organização a partir de uma lista explícita. **Não** cria
unidades, posições nem reporting lines — fabricar hierarquia seria criar
autoridade falsa (I4/I9). A administração de estrutura permanece dependência
registrada (§20.5).

### 14.8 Rollback

Antes do primeiro registro **exclusivamente** soberano, reverter é permitido.
Depois dele, rollback para `localStorage` é **proibido**: fix-forward, com o
legado permanecendo read-only. Nenhuma flag de ambiente pode devolver autoridade
local (mesma decisão da F5-06 D12).

## 15. Impacto em services/pages

### 15.1 Módulos novos (caminho soberano)

- `src/services/colaboradoresSoberanos/` — porta única das telas (equivalente a
  `acessoAvaliacoesSoberanas.ts`): nenhuma página importa Supabase.
- `src/infrastructure/supabase/colaboradores/` — contrato de entrada/saída
  (tipos + validação de forma), repositório (chamadas à Edge) e leitura da
  projeção.
- Projeção/vigência: tipo `ColaboradorSoberano` com `collaboratorId` (UUID),
  `matricula` (rótulo), dados de pessoa, status vigente e atributos derivados —
  **substitui** o uso de `Colaborador` como fonte de decisão nas telas migradas.

### 15.2 Módulos que passam a ser barreira (leitura legada, escrita proibida)

| Módulo | Mudança |
| --- | --- |
| `src/services/colaboradorStorage.ts` | `getColaboradores` deixa de migrar/injetar/gravar (I7); `saveColaborador`/`updateColaborador` lançam (fail-closed) |
| `src/services/historicoOrganizacionalStorage.ts` | `registrarMovimentacaoOrganizacional` lança; leitura de legado permanece, sem autoridade |
| `src/infrastructure/localStorage/localCollaboratorRepository.ts` | adapter local desativado no caminho de produção (o port passa a ter implementação Supabase) |
| `src/services/resetBaseDesenvolvimento.ts` | passa a ser o único caminho que apaga chaves locais (DEV) — não é autoridade |

### 15.3 Mundo funcional do Policy Engine

Hoje `authorizationPolicy.colaboradoresDoRecurso` cai em `getColaboradores()`
(`src/authorization/authorizationPolicy.ts:1,61`). Após a F5-07:

- o **dataset** de colaboradores usado pelas decisões passa a vir da projeção
  soberana (server-side), carregada pela porta única;
- a decisão de **acesso efetivo** deixa de depender do cliente: quem decide é a
  Edge + Policy Engine por operação;
- `can()` no cliente continua **UX** e passa a operar sobre dados soberanos, não
  sobre `localStorage`;
- falha/ausência de dataset ⇒ **DENY** (fail-closed), nunca "modo local".

### 15.4 Telas (mudança obrigatória)

| Tela | Mudança |
| --- | --- |
| `InicioPage` | deixa de rotear por `funcao` como se fosse autorização (roteamento por capability/estado soberano) |
| `ColaboradoresPage` | passa a listar a projeção soberana (assíncrona, com loading/erro); remove filtro por texto `respondePara`; chaves por UUID; mantém a massa de teste DEV explicitamente gated |
| `NovoColaboradorPage` | criação pela Edge (com estados de processamento/erro); matrícula é intenção; sem escrita local; sem histórico local |
| `EditarColaboradorPage` | carrega por UUID com versão; `expected_version` no envio; operações separadas para pessoa, matrícula e status; sem `useState` inicializado de storage sem ressincronização |
| `ColaboradorDetalhePage` | carrega por UUID; histórico pela trilha soberana; KPIs derivados do dado soberano; avaliações pelo caminho soberano quando existir (F5-06) e legado apenas como legado |

### 15.5 Rotas e identificadores

- `:id` passa a ser **UUID do colaborador**; `AppRoutes.tsx:137-145` e os links
  (`ColaboradorCard.tsx:21`, etc.) migram.
- **Compatibilidade:** URL antiga com matrícula é resolvida **no servidor**
  (ponte matrícula→UUID, fail-closed se ausente/ambígua); nunca no cliente e
  nunca por heurística. Nenhuma rota nova é criada sem necessidade.

### 15.6 Consumidores fora de escopo (não migrados agora)

`metaStorage`, `observacaoStorage`, `cicloAvaliacaoStorage`, `cicloEquipeService`,
`permissaoAvaliacao`, `cancelamentoCicloService`, `reaberturaCicloService`,
`correcaoPeriodoCicloService`, `exportarAvaliacaoPdf`, `geradorDadosTeste`,
`relatorioService`:

- passam a consumir o **dataset soberano** de colaboradores (via porta única)
  para não reintroduzir `localStorage` como mundo funcional;
- **não** têm sua própria persistência migrada aqui (F5-08/09/10);
- **não** ganham nenhuma nova autoridade local, e as decisões por `funcao` que
  hoje existem neles permanecem **rotuladas como UX/transitórias**, com a
  decisão real na fronteira. `geradorDadosTeste.ts:447-451` (negação por cargo
  fora do Policy Engine) é **removido ou convertido em `can()` de UX**, pois é
  autorização por cargo — proibida (I9).

### 15.7 Código morto

`src/components/ColaboradoresPage.tsx` (cópia não roteada, botão "Novo
colaborador" sem gate) é **removido** na implementação — não é refatoração
oportunista, é remoção de superfície divergente sem gate.

### 15.8 Testes de tela a criar

`ColaboradoresPage`, `NovoColaboradorPage`, `EditarColaboradorPage`,
`ColaboradorDetalhePage` e `InicioPage` hoje **não têm** teste de renderização
(§2.6). A implementação cria testes cobrindo: listagem soberana, criação
autorizada/negada, edição com conflito de versão, transição de status,
comportamento sem alocação e ausência de escrita local.

## 16. Testes

### 16.1 Validadores SQL (padrão do repositório)

| Arquivo | Papel |
| --- | --- |
| `supabase/validacao/01-cenario-f5-07.sql` | cenário sintético determinístico: 2 organizações, colaboradores, estrutura, vínculos, atores com roles distintas |
| `supabase/validacao/02-validar-f5-07.sql` | schema/constraints/RLS/grants/funções + comportamento + negativos (padrão `[PASS]`/`[FAIL]`) |
| `supabase/validacao/03-validar-f5-07-cutover.sql` | cutover/anti-IDOR/cross-tenant/append-only/concorrência/idempotência |

### 16.2 Matriz mínima obrigatória

| # | Caso | Artefato | Asserção |
| --- | --- | --- | --- |
| T-01 | CRUD autorizado (criar/editar/status/identificador) | 02 | efeito persistido + evento com autor |
| T-02 | CRUD negado (sem capability) | 02 | negação + nenhum efeito |
| T-03 | cross-tenant (colaborador de outra organização) | 02/03 | `NOT_FOUND`/DENY, nada escrito |
| T-04 | IDOR (UUID de terceiro fora do escopo) | 03 | DENY; leitura não vaza existência |
| T-05 | colaborador inexistente | 03 | `NOT_FOUND`, nenhuma criação |
| T-06 | membership revogada | 03 | DENY na operação seguinte |
| T-07 | usuário sem collaborator em operação que exige um | 02 | DENY (escopos estruturais vazios) |
| T-08 | troca de gestor | 02 | fecha linha, abre nova; gestor derivado muda na data nova e não na anterior |
| T-09 | troca de unidade/posição | 02 | nova ocupação; cargo/área/função derivados mudam; histórico intacto |
| T-10 | mudança de status (active→leave→active) | 02 | vigências encadeadas, sem sobreposição |
| T-11 | licença | 02 | ocupação preservada; aplicabilidade suspensa |
| T-12 | desligamento (`inactive`) com ocupação aberta | 02 | `CONFLICT` e nada escrito; após encerrar, permite |
| T-13 | sucessão | 02 | evento de sucessão com autor; passado não reescrito |
| T-14 | histórico temporal (estado em data passada) | 02 | gestor/status/unidade corretos na data; sem anacronismo |
| T-15 | concorrência (duas alterações simultâneas) | 03 | segunda falha por versão/sobreposição |
| T-16 | revogação entre leitura e mutação | 03 | mutação negada |
| T-17 | matrícula de outro tenant como intenção | 03 | resolução falha fechado (`NOT_FOUND`) |
| T-18 | acesso direto por UUID (authenticated, fora do escopo) | 03 | RLS/policy barra |
| T-19 | RLS de leitura own-tenant (13+ tabelas) | 02 | `authenticated` só vê o próprio tenant |
| T-20 | auditoria/autoria (evento obrigatório na mesma transação) | 02 | mutação sem evento é impossível |
| T-21 | ausência de escrita em `localStorage` após cutover | 03 + TS | barreiras lançam; nenhuma chave alterada |
| T-22 | mudar `job_roles.code`/senioridade **não** altera capability/escopo | 02 | prova de que não há autorização por cargo |
| T-23 | evento append-only (`UPDATE`/`DELETE` proibidos) | 02 | exceção/permissão negada |
| T-24 | idempotência (`operation_id` repetido) | 03 | sem efeito duplicado; payload divergente ⇒ `CONFLICT` |

### 16.3 Testes TypeScript

- **Contrato Edge → RPC** (mesmo padrão de
  `src/authorization/avaliacoesContratoRpc.test.ts`): lê o código real da Edge
  com `?raw` e exige nome + argumentos nomeados exatos de cada RPC; falha se
  aparecer argumento inexistente, `matricula` como identidade de escrita ou
  campos proibidos.
- **Repositório/porta**: payloads sem `organization_id` como prova, sem
  `capability`/`actor_*`, com `expected_version`/`operation_id`.
- **Autorização negativa**: `FORBIDDEN`/`NOT_FOUND`/`CONFLICT` mapeados, sem
  vazamento de detalhe interno.
- **Telas**: renderização com dados soberanos, estados de erro/carregamento,
  ausência de alocação e **proibição de escrita local**.
- **Regressão**: `NavegacaoPrincipal.test.tsx` e testes de autorização
  existentes continuam verdes.

### 16.4 Gates de CI

`npm test`, `npm run build`, `npm run lint`, `git diff --check` +
`supabase db reset` + validadores F5-07, **mais** a regressão obrigatória dos
validadores F4-08 (`02-validar-f4-08.sql`, `03-validar-f4-08-mutacoes.sql`) e
F5-06, que são sensíveis a tabela nova não catalogada.

## 17. Gates de conclusão (critérios de aceite)

1. Nenhum caminho de escrita de colaborador/histórico em `localStorage`; nenhuma
   leitura de produção usando o storage local como autoridade.
2. `collaborators.id` (UUID) é a identidade que atravessa a fronteira; matrícula
   é intenção resolvida server-side (D2).
3. Colaborador criado, editado, com identificador e status alterados
   exclusivamente por RPC autorizada, com evento append-only e autoria soberana.
4. Estrutura derivada (cargo/área/função/senioridade/gestor) resolvida
   server-side na data pedida; nenhuma coluna desnormalizada criada.
5. Troca de gestor/unidade/posição e transição de status preservam histórico
   (fechar-e-abrir), sem reescrever passado.
6. Sucessão e responsabilidades operando por RPC já existente/endurecida, com
   autoria.
7. Política: `authorize()` antes de toda mutação de conteúdo; plano
   administrativo para estrutura (Q1 fechada); nenhuma autorização paralela;
   nenhum DEFINER novo.
8. RLS habilitada nas tabelas envolvidas, `SELECT` own-tenant, nenhuma policy de
   escrita, grants mínimos; guard F4-08 e teste de mutações atualizados e verdes.
9. Cutover executado por fases, sem dual-write, com `localStorage` sem
   autoridade e sem fallback silencioso.
10. Matriz de testes T-01…T-24 implementada e verde; validadores F5-07 e
    regressões (F4-08/F5-06) verdes; `npm test`/`build`/`lint`/`diff --check`
    verdes.
11. Nenhuma alteração fora do escopo; nenhuma decisão fechada de F3/F4/F5
    reaberta; nenhuma capability nova.

## 18. Decisões (D1–D18)

**D1 — PostgreSQL é a fonte soberana do colaborador e do histórico.**
*Justificativa:* o diagnóstico da Etapa 5 classifica colaboradores e histórico
como LEGADO (`auditoria-etapa-5-diagnostico.md` §2) e o objetivo da atividade é
eliminar essa autoridade. *Consequência:* telas/serviços passam a consumir
projeção server-side; a autoridade local é removida por fases. *Alternativa
rejeitada:* manter `localStorage` como cache autoritativo (violaria I8/I13).

**D2 — Identidade funcional = `collaborators.id` (UUID); matrícula é INTENÇÃO.**
*Justificativa:* convenção F1-02 e F5-02/F5-06 D3; `collaborator_identifiers` já
modela código de negócio com vigência. *Consequência:* rotas/APIs usam UUID;
matrícula é resolvida na fronteira (ponte), com compatibilidade de URL legada.
*Alternativa rejeitada:* promover matrícula a chave (reintroduziria G8/G4).

**D3 — Dados de pessoa passam a viver em `collaborators` (extensão aditiva), sem
temporalidade própria.**
*Justificativa:* nome/e-mail não são autoridade nem hierarquia; a evolução fica
registrada no log (before/after). *Consequência:* identidade legível no banco sem
nova tabela. *Alternativa rejeitada:* tabela temporal de pessoa (custo e
complexidade desproporcionais ao risco; histórico consultável pelo log).

**D4 — Atributos estruturais NÃO são colunas do colaborador.**
*Justificativa:* a estrutura F3 já os deriva por ocupação + reporting line, e o
gestor é **sempre** derivado (F3-07 §21-22); F4 proíbe cargo como prova.
*Consequência:* `cargo`/`area`/`funcao`/`senioridade`/`gestorDireto` viram
projeção. *Alternativa rejeitada:* manter colunas desnormalizadas (duas verdades,
divergência entre telas, hierarquia inventada como hoje).

**D5 — Rótulo operacional (`funcao`) deriva de `job_roles.code` (coluna aditiva).**
*Justificativa:* o catálogo existe, mas sem código estável o rótulo legado só
seria derivável por texto (heurística proibida). *Consequência:* `funcao` é
label/UX e compatibilidade; **nunca** autorização (T-22 prova). *Alternativa
rejeitada:* derivar por nome textual (frágil, e reintroduz cargo como decisão) ou
manter enum no cadastro (segunda verdade).

**D6 — Estado e status mudam por fechar-e-abrir vigência; `inactive` exige
estrutura encerrada explicitamente.**
*Justificativa:* preserva histórico (I5) e respeita o trigger
`enforce_collaborator_inactive_requires_closed_occupations`. *Consequência:*
`CONFLICT` com a lista do que falta encerrar; readmissão fora de escopo.
*Alternativa rejeitada:* fechar ocupações silenciosamente em cascata (apagaria
decisão estrutural sem motivo próprio por posição).

**D7 — Alteração de gestor/unidade/posição = nova linha temporal.**
*Justificativa:* `position_reporting_lines`/`occupations` já são temporais com
`reason` obrigatório e exclusion de sobreposição. *Consequência:* nenhum `UPDATE`
destrutivo; consulta por data. *Alternativa rejeitada:* gravar `gestor_id` no
colaborador (é a lacuna G7 atual).

**D8 — Histórico organizacional = log append-only `collaborator_events` +
tabelas temporais.**
*Justificativa:* autor, motivo, escopo por ciclo e delta antes/depois **não**
existem nas tabelas temporais; o log replica o contrato de evento já fechado na
F5-06 (D26/D7). *Consequência:* uma tabela nova, imutável, catalogada no guard.
*Alternativa rejeitada (a):* derivar todo o histórico das tabelas temporais
(perde autoria/motivo/escopo). *Alternativa rejeitada (b):* criar entidade
"movimentação" separada da auditoria (duas trilhas divergentes).

**D9 — Sucessão, responsabilidades temporárias e colegiado são REUSO das
estruturas F3-06/F3-08/F3-09.**
*Justificativa:* já existem, com vigência, guard cross-tenant e autoria
(`evaluation_succession_events.author_user_profile_id`). *Consequência:* nenhuma
tabela nova nesse subdomínio; efeito autorizativo continua derivado por data
(F4-05). *Alternativa rejeitada:* remodelar sucessão (reabriria F3-09).

**D10 — Autorização em dois planos, ambos já decididos.**
*Justificativa:* `collaborator.*` tem target compatível no engine;
`org.structure.manage` tem `[]` (DENY no engine) e pertence ao plano
administrativo já implementado pela F5-04. *Consequência:* nenhuma capability
nova, nenhuma lógica paralela, `Q1` (§19) confirma o caminho administrativo.
*Alternativa rejeitada:* criar capability nova ou ampliar a allowlist do engine
por conta própria.

**D11 — ActorContext/ResourceContext reais, tenant do recurso.**
*Justificativa:* F5-05 já reconhece `collaborator`/`position`/
`organizational_unit` como tipos soberanos e recusa `cycle`/`goal`/`observation`.
*Consequência:* reaproveitamento direto, sem mudar a F5-05; nenhum alvo global.
*Alternativa rejeitada:* autorizar por `{kind:"global"}` (transitório, nunca
autorização).

**D12 — RLS deny-by-default + leitura own-tenant + mutação só por RPC INVOKER
`service_role`; nenhum DEFINER novo.**
*Justificativa:* F4-08 D7/D10/D11 e I11/I12. *Consequência:* nenhuma policy de
escrita para `authenticated`; catalogação obrigatória no guard do CI.
*Alternativa rejeitada:* liberar DML direto com policy de escrita (ampliaria
superfície e enfraqueceria a fronteira).

**D13 — Concorrência por versão otimista + barreiras temporais + idempotência.**
*Justificativa:* `version` é padrão F1-02; exclusion/check já são a última
barreira; `operation_id` evita duplicação por retry. *Consequência:* `CONFLICT`
explícito, sem perda silenciosa. *Alternativa rejeitada:* last-write-wins (perda
de alteração concorrente).

**D14 — Cutover por fases com evidência estrutural; rollback proibido após o
primeiro registro exclusivo.**
*Justificativa:* replica o regime já aceito na F5-06 D12, com evidência adaptada
(§14.2). *Consequência:* sem dual-write e sem flag que restaure autoridade local.
*Alternativa rejeitada:* convivência prolongada das duas autoridades.

**D15 — Legado local permanece somente leitura; seed DEV é fixture gated.**
*Justificativa:* preserva compatibilidade sem conceder autoridade (F5-05 D19).
*Consequência:* escrita local lança; DEV não participa do caminho soberano.
*Alternativa rejeitada:* apagar o legado (perda de histórico exibível) ou
mantê-lo como fallback (I13).

**D16 — Bootstrap mínimo apenas de catálogo (job_roles/seniority_levels).**
*Justificativa:* sem catálogo não há como atribuir posição; fabricar
unidades/posições/hierarquia criaria autoridade falsa. *Consequência:*
organização sem estrutura opera colaboradores **sem alocação**; administração de
estrutura fica como dependência (§20.5). *Alternativa rejeitada:* bootstrap que
cria unidades/posições e reporting lines sintéticas (inventaria hierarquia e, com
ela, escopos).

**D17 — Rotas passam a UUID com compatibilidade de matrícula resolvida no
servidor.**
*Justificativa:* identidade funcional UUID (D2) sem quebrar links existentes.
*Consequência:* uma resolução a mais na fronteira, fail-closed se ambígua.
*Alternativa rejeitada:* manter matrícula na URL (identidade errada na fronteira)
ou quebrar URLs antigas sem tratamento.

**D18 — Testes e gates proporcionais ao risco, com regressão obrigatória do guard
do CI.**
*Justificativa:* tabela nova não catalogada reprova o CI (F4-08); telas de
colaborador não têm teste hoje. *Consequência:* matriz T-01…T-24 + validadores +
testes de tela. *Alternativa rejeitada:* validar só por teste unitário.

## 19. Questões abertas

### Q1 — Como `org.structure.manage` (e `org.catalog.manage`) é enforçada?

**Contexto.** A allowlist capability × target da F4-04 (D18) não prevê target
para essas capabilities: `org.structure.manage` e `org.catalog.manage` têm `[]`
em `src/authorization/policyEngine/capabilityTarget.ts:45-46`, o que faz o engine
responder DENY para qualquer alvo. Elas pertencem ao **plano administrativo**
(F4-01/F4-09), e a F5-04 já implementou esse plano para
`membership.manage`/`access_role.manage` com `usuario_eh_administrador`
(membership ativa + assignment ativa de role de sistema no tenant, server-side,
com trilha append-only — `20260910020000_f5_04_admin_rpc_functions.sql:39-63`). A
F4-08 (D7) determina que mutação estrutural seja **exclusivamente** por
RPC/transação, mas **não** define qual gate a precede. A F5-07 precisa de um
caminho de enforcement para ocupação, reporting line, responsabilidade e
sucessão.

**Alternativas.**

- **A (recomendada, adotada neste desenho):** plano administrativo já decidido —
  a Edge monta o ActorContext de `auth.uid()` e exige, server-side, membership
  ativa **e** assignment ativa de role de sistema que conceda
  `org.structure.manage` no tenant, com trilha append-only; o Policy Engine
  continua sendo o gate das operações de conteúdo (`collaborator.*`). *Custo:*
  zero alteração em contrato fechado. *Risco:* convivem dois caminhos de gate
  (funcional e administrativo), ambos já existentes e auditados.
- **B:** estender a allowlist da F4-04 para `org.structure.manage` ×
  `position`/`organizational_unit`/`collaborator` e resolver escopos estruturais
  no provider. *Custo:* altera contrato fechado da F4-04/F4-09 e o provider de
  escopos; exige nova validação da F4. *Benefício:* um único caminho de gate.
- **C:** criar capability nova (ex.: `collaborator.structure.manage`). *Custo:*
  amplia catálogo canônico e bundle; contraria a orientação de não criar
  capability sem necessidade.

**Recomendação:** **A**, exatamente como descrito em §9.1/§9.2. O desenho inteiro
assume A; se a revisão fechar B ou C, §9.2 e §16 mudam (e B exige alteração de
contrato F4).

## 20. Dependências para F5-08/F5-09/F5-10 (e F5-11)

### 20.1 F5-08 — Ciclos de avaliação

- A F5-07 grava `cycle_scope` + `reference_cycle_id` (FK para
  `evaluation_cycles`), **preservando** a regra de baseline "somente ciclos
  posteriores" (§11.2). A **aplicação** dessa regra a um ciclo concreto é da
  F5-08, que passará a ser a autoridade do ciclo.
- Contrato entregue à F5-08: (i) `evaluation_cycles` é a referência soberana de
  ciclo (já existe, mínima — F5-06 D15 —, extensível apenas aditivamente);
  (ii) o estado organizacional de uma data é resolvido pelas tabelas temporais
  (não pelo ciclo); (iii) a data de referência de um ciclo deve ser resolvida
  server-side (hoje é calculada no cliente,
  `historicoOrganizacionalStorage.ts:192-209`) — a F5-08 passa a fornecer esse
  dado e a F5-07 não o duplica.
- Nada da F5-07 depende da criação de ciclo para funcionar, exceto o
  preenchimento **opcional** de `reference_cycle_id`.

### 20.2 F5-09 — Metas

- Consome o que a F5-07 entrega: `collaborator_id` (UUID), projeção vigente
  (unidade/posição/gestor derivado na data) e histórico.
- Contrato necessário: toda meta referencia colaborador por UUID; a relação
  "gestor/responsável" é resolvida por `organizacao_resolver_gestor_direto` na
  data; nenhuma meta pode usar matrícula como identidade.
- `metaStorage.ts` hoje monta o mundo funcional local: após a F5-07 deve usar o
  dataset soberano (não a chave local) e não ganha autoridade nova.

### 20.3 F5-10 — Observações

- Mesmo contrato de identidade/estrutura da F5-09; autoria soberana por
  `actor_user_profile_id` no padrão de evento (§12).
- `ObservacoesColaborador.tsx` hoje usa `authorize` na criação e apenas `can` na
  edição/exclusão — a assimetria deve ser corrigida quando as observações forem
  soberanas (registrada aqui como dívida a resolver na F5-10, não nesta
  atividade).

### 20.4 F5-11 — Validação transversal final

- A F5-11 poderá reutilizar diretamente: matriz T-01…T-24, projeção soberana,
  guard F4-08 atualizado e o contrato de evento, sem reabrir a F5-07.

### 20.5 Dependência **da** F5-07: administração de estrutura e catálogo

- A F5-07 **consome** unidades, posições, reporting lines, catálogos e colegiado;
  **não** os administra (§4).
- Contrato mínimo necessário para a F5-07 ser plenamente utilizável (atividade
  própria, hoje inexistente): CRUD temporal de `organizational_units`,
  `organizational_unit_parent_periods`, `organizational_positions`, `job_roles`,
  `seniority_levels` e `collegiate_configurations`, sob o mesmo padrão desta
  atividade (Edge + plano administrativo + RLS + auditoria).
- Até que exista, valem §14.6/§14.7: colaborador sem alocação, catálogo via
  bootstrap mínimo (D16), nunca estrutura sintética.

### 20.6 Importação do acervo legado

- Fora de escopo nesta e nas atividades listadas; se houver decisão de produto,
  será atividade própria, com auditoria e sem dual-write.

## 21. Rastreabilidade das perguntas obrigatórias

| Pergunta | Onde é respondida |
| --- | --- |
| A. Fonte soberana de collaborator | §1.2, §6.1, D1 |
| B. Identificador que atravessa fronteiras | §6.1, §8.2, D2 |
| C. Papel de matrícula e identificadores humanos | §2.2, §6.6, D2 |
| D. Como criar colaborador | §8.1, §8.3 |
| E. Como editar colaborador | §8.1, §8.3 |
| F. Ativar, inativar e licença | §8.1, §8.3, D6 |
| G. Vigência temporal | §6.4, §11.1, §11.4, I5 |
| H. Gestor/unidade/posição sem destruir histórico | §8.1, §11.4, D7 |
| I. Sucessão | §8.1, §11.5, D9 |
| J. Responsabilidades históricas e atuais | §11.1, §11.5, D9 |
| K. Impedir ciclos/hierarquias impossíveis | §8.3, §13.2 (triggers/exclusions da F3) |
| L. Mutações × capabilities | §9.2, D10 |
| M. Scopes aplicáveis | §9.2, §9.3, I14 |
| N. ActorContext/ResourceContext por operação | §9.3, D11 |
| O. Onde `authorize()` ocorre | §9.4, I9 |
| P. O que a RLS garante | §10.1, D12 |
| Q. IDOR e cross-tenant | §7, §10.1, T-03/T-04/T-17/T-18 |
| R. Autoria/auditoria | §12, D8 |
| S. Revogação na operação seguinte | §9.5, §13.4, I10 |
| T. Concorrência | §13, D13 |
| U. Migração das telas sem dual-write | §14.4, §15.4, D14 |
| V. Dados existentes no `localStorage` | §14.5, D15 |
| W. Legado somente leitura | §14.5, §15.2, D15 |
| X. Consumers que precisam mudar | §15.1–§15.8 |
| Y. Preparação de F5-08/09/10 | §20.1–§20.4 |
