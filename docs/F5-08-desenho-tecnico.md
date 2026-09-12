# F5-08 — Estrutura organizacional e catálogos soberanos (contrato arquitetural e desenho)

> **Status deste documento:** DESENHO TÉCNICO — **AGUARDANDO DECISÕES** (Q1–Q5 em §28).
> **Nada foi implementado.** Esta atividade produz análise, decisões dedutíveis dos contratos
> existentes e registro explícito das dúvidas arquiteturais reais.
>
> - Branch de documentação: `docs/f5-08-estrutura-catalogos-soberanos`
> - Base: `main` em `7137f1f553be406a31e4ea60c42b92de4778c52e` (squash merge da F5-07)
> - Atividade: **F5-08 — Estrutura organizacional e catálogos soberanos**
> - Dependência direta: F5-07 (§20.1/§20.6) e plano administrativo F5-04
> - Decisões herdadas preservadas: **D19** e **D20** (F5-07) — ver §11.6 e §29 (D19)
>
> **Precedência aplicada em caso de conflito:** (1) regras de segurança já fechadas;
> (2) contratos aprovados F4/F5; (3) desenho F5-07 + D19/D20; (4) estado real da `main`;
> (5) `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md` — evidência **histórica,
> não normativa** (o roadmap daquele documento foi superseded; ver cabeçalho, linhas 3-8).
>
> **Leitura obrigatória já executada:** `AGENTS.md`; `.ai/virtus-context.md`;
> `.ai/workflow.md`; `.ai/architecture-rules.md`; `.ai/git-rules.md`; `.ai/handoff.md`;
> `docs/F5-07-desenho-tecnico.md` (íntegro); `docs/F5-04`; `docs/F5-05`; `docs/F4-02`;
> `docs/F4-04`; `docs/F4-08`; `docs/F4-10`; migrations F3-01…F5-07; Edge Functions;
> services/storages/telas/testes de estrutura.

## Resumo executivo

| Dimensão | Resultado |
| --- | --- |
| Tabelas de entidade novas | **0** — as 8 tabelas exigidas pela F5-07 §20.1 já existem (F3-02/03/04/08) |
| Tabelas novas | **1** — trilha append-only `structure_events` (D1, D13) |
| Colunas novas em tabelas existentes | **0** (D1) — motivo/autoria vivem na trilha, não na tabela |
| Constraints/triggers novos | anti-ciclo de **unidades** (lacuna documentada da F3-03), guarda de encerramento de unidade, guarda de catálogo inativo em relação nova (D6, D7, D17) |
| Índices novos | `organizational_unit_parent_periods.parent_unit_id` (ausente hoje) (D20) |
| RPCs novas | **15** (`SECURITY INVOKER`, `EXECUTE` só `service_role`) — §13.6/§21 |
| Capabilities novas | **0** — `org.structure.manage` e `org.catalog.manage` (D19) |
| Ampliação da allowlist capability×target | **nenhuma** — permanece `[]` (D19, F4-04 D18) |
| Políticas de RLS novas | **0** — a leitura own-tenant já existe (F4-08 §) (D16) |
| Fronteira server-side | **estende** a Edge `colaboradores`; nenhuma Edge nova (D9) |
| Cutover de UI | telas de administração de estrutura/catálogos + remoção da autoridade estrutural local (D18) |
| Questões abertas | **Q1–Q5** (§28) |
| Decisões registradas | **D1–D20** (§29) |

---

## 1. Título e status

- **Atividade:** F5-08 — Estrutura organizacional e catálogos soberanos.
- **Natureza:** contrato arquitetural + desenho técnico (documento único desta atividade).
- **Status:** **AGUARDANDO DECISÕES** — Q1–Q5 são decisões que **não** são dedutíveis dos
  contratos fechados nem do estado real do repositório (§28). Não há decisão inventada para
  evitar questão aberta, nem questão artificial onde contrato/código já decidem.
- **O que este documento é:** contrato da futura implementação (fase Pro), com inventário
  verificado, modelo de dados, plano administrativo, matrizes de operação/autorização,
  estratégia de testes e critérios de aceite.
- **O que este documento não é:** implementação. Nenhuma migration, RPC, tela ou teste é
  criado nesta atividade (F5-08 §BRANCH E COMMIT do enunciado).
- **Dependência de fechamento:** antes de iniciar a implementação, Q1–Q5 precisam de decisão
  (recomendações em §28). As decisões D1–D20 são suficientes para todo o restante.

## 2. Objetivo

Criar o **caminho soberano de administração** da estrutura organizacional e dos catálogos
consumidos pela F5-07 (`docs/F5-07-desenho-tecnico.md:1282-1303`), de modo que:

1. toda **escrita** de estrutura (unidades, hierarquia entre unidades, posições, reporting
   lines, colegiado) e de catálogo (`job_roles`, `seniority_levels`) ocorra por uma fronteira
   server-side transacional, autenticada, autorizada por capability e auditada;
2. toda **leitura** continue isolada por organização pela RLS já fechada na F4-08;
3. a hierarquia permaneça **derivada das relações estruturais soberanas** (F4-02 §19 inv.2/3;
   F4-04 §3/§6), nunca de cargo, senioridade, nome de coordenador, matrícula ou convenção de
   frontend;
4. nenhuma **autoridade estrutural local/sintética** sobreviva no cliente como fonte de
   verdade (`mundoFuncional`, `historicoOrganizacionalStorage`, seeds DEV, fallbacks);
5. o modelo temporal preserve fatos passados (fechar-e-abrir, nunca `UPDATE` destrutivo) e
   mantenha resolvíveis as referências históricas de colaboradores, avaliações, participantes,
   assignments e scopes;
6. `org.structure.manage` e `org.catalog.manage` sejam verificadas **sem quebrar D19**
   (plano administrativo server-side; nenhuma capability nova; nenhuma ampliação da allowlist
   funcional capability × target).

**Não-objetivo:** implementar qualquer parte de F5-09…F5-12 (ciclos, metas, observações,
importação de acervo legado).

## 3. Contexto e contratos herdados

### 3.1 Contratos fechados que restringem esta atividade

| Contrato | O que determina (evidência) | Efeito na F5-08 |
| --- | --- | --- |
| **Segurança raiz** (`AGENTS.md` §3; `.ai/architecture-rules.md`) | `auth.uid()` é raiz soberana; tenant validado server-side; payload/localStorage não concedem autoridade; fail-closed; cross-tenant DENY; RLS é barreira real | Toda mutação revalida ator, membership e tenant na mesma transação (§11, §14) |
| **F4-02 D1/D5/D6/D11/D15/D17** (`docs/F4-02-desenho-tecnico.md:212-222, 650-664, 666-684, 729-738, 782-791, 806-816`) | SELF/DR/DESCENDANTS/UNIT exigem vínculo membership→collaborator; UNIT = somente a unidade atribuída (sem subunidades); ASSIGNED derivado de F3-08/09; assignment sem scope = fail-closed | Nenhuma alteração nos resolvers; F5-08 apenas alimenta as tabelas que eles leem (§16) |
| **F4-02 §19 inv.2/3** (`:546-550`) e **F4-04 §3/§6/§21/§22** (`:74-77, 119-125, 386-398, 404-405`) | Proibido derivar hierarquia/autorização de cargo/função/senioridade/matrícula; grep de CI | Nome/código são rótulos; identidade é UUID (D3) |
| **F4-04 D18** (`docs/F4-04-desenho-tecnico.md:592-607`; §16 `:310-321`; §26.10.2 `:766-770`) | Allowlist explícita `Record<Capability, readonly TargetType[]>`; incompatibilidade ⇒ DENY; não concede autorização | `org.structure.manage`/`org.catalog.manage` permanecem `[]`; o gate administrativo não passa pelo engine (§11) |
| **F4-08** (`supabase/migrations/20260908110000_f4_08_rls_select_own_tenant.sql:33-69`; `20260908140000:27-72`) | SELECT own-tenant para as 14 tabelas de estrutura/catálogo, `grant select` a `authenticated`, `revoke all` de `anon`/`authenticated`, default privileges | A leitura já está resolvida por contrato; F5-08 não cria policy nova (D16) |
| **F4-10 §18 REV-001…REV-011** (`docs/F4-10-desenho-tecnico.md:349-370`) | Revogação efetiva na operação seguinte | Nenhum cache de autorização; capability reavaliada a cada operação (§14.5) |
| **F5-04 D10/D14/D16/D18** (`docs/F5-04-desenho-tecnico.md:462, 466, 468`; `20260910020000:39-219`; `20260910010000:22-86`) | Plano administrativo server-side; ator por identidade verificada; `usuario_eh_administrador`; trilha `privilege_mutation_audit`; nenhuma superfície a `authenticated` | Precedente de forma para as RPCs administrativas da F5-08 (§11.4, §13.6) |
| **F5-06 D26/D27** (`docs/F5-06-desenho-tecnico.md`; `20260911000000`) | Evento append-only na mesma transação; defesa em profundidade na fronteira | Molde da trilha (§15) |
| **F5-07 D5** (`:1115-1120`; §6.3 `:374-390`) | `job_roles.code` é **rótulo**; único por organização quando não nulo; backfill por `name`; proibido como autoridade | Catálogo administrado por rótulo; identidade por UUID (D3, D17) |
| **F5-07 D6** (`:1122-1128`) + `enforce_collaborator_inactive_requires_closed_occupations` (`20260907150000:218-236`) | Inativar colaborador exige ocupações encerradas | Análogo estrutural: encerrar unidade/posição exige estrutura vigente encerrada (D6) |
| **F5-07 D16** (`:1192-1198`; §14.7 `:898-905`) | Bootstrap **apenas de catálogo**, idempotente, auditado; proibido criar unidades/posições/reporting lines | `colaborador_catalogo_bootstrap` preservado; a administração plena é desta atividade |
| **F5-07 D19** (`:1212-1223`) e **Q1 fechada** (`:1240-1269`) | As duas capabilities no plano administrativo server-side; allowlist **não** é ampliada para `position`/`organizational_unit`/`collaborator` | §11 — gate por capability efetiva, não por alvo funcional |
| **F5-07 D20** (`:1225-1234`) | CRUD estrutural é atividade própria | Esta atividade |
| **F5-07 §12** (`:754-798`), **§13** (`:802-836`) | Evento + mutação na mesma transação; `payload` nunca é autoridade; versão otimista; barreiras temporais; idempotência por `operation_id` | §14, §15 |
| **F5-07 §14.6** (`:889-896`) | Colaborador existe **sem alocação**; operações que exigem posição são recusadas; nada de estrutura sintética | A UI de administração é a única forma de criar estrutura (§18) |

### 3.2 Estado das atividades anteriores

- F5-01…F5-07 **concluídas** (`main` = `7137f1f`, squash merge da F5-07).
- `docs/F3-02`, `docs/F3-08`, `docs/F3-09` **não existem** em `docs/` (só
  `docs/F3-10-desenho-validacao.md`), embora sejam citados como contratos fechados por F4-02 e
  F5-07. O contrato dessas atividades é verificável **apenas pelas migrations** — finding
  registrado em §25.4 (não bloqueia: as migrations são normativas e foram lidas).
- `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md` é diagnóstico histórico; sua
  seção "F5-08 — Ciclos de avaliação PostgreSQL" (`:109`) está **superseded** pelo roadmap
  vigente (F5-08 = estrutura/catálogos; F5-09 = ciclos). Usado aqui só como evidência.

## 4. Estado atual encontrado no repositório

### 4.1 Fonte real de verdade hoje (resposta à pergunta 1)

| Entidade | Fonte real na `main` | Evidência |
| --- | --- | --- |
| Unidade | `public.organizational_units` (F3-03) — **sem UI e sem escrita soberana** | `20260907130000:119-138` |
| Hierarquia entre unidades | `public.organizational_unit_parent_periods` — **sem UI**; ciclos multinível não são impedidos pelo banco | `:196-224`; comentários `:62-65, 194-195` |
| Posição | `public.organizational_positions` — **sem UI** | `:288-314` |
| Reporting line | `public.position_reporting_lines` — escrita soberana existe via F5-07 (`estrutura.reporting.definir/encerrar`), **sem UI** | `20260907140000`; `20260913010000` |
| Cargo / Senioridade | `public.job_roles` / `public.seniority_levels` — bootstrap soberano existe (`colaborador_catalogo.bootstrap`), **sem UI** | `20260907120000`; `20260913010000:1691-1810` |
| Colegiado | `public.collegiate_configurations` + `_members` — **sem escrita soberana e sem UI** | `20260907180000:59-151` |
| Estrutura **exibida/usada pelo cliente** | `localStorage` (`historicoOrganizacionalStorage`, `colaboradorStorage`) + seeds DEV (`src/data/colaboradores.ts`) + derivação local (`src/authorization/mundoFuncional.ts:129-232`) | §4.5 |

### 4.2 Banco: o que já existe (reuso obrigatório)

| Tabela | Colunas relevantes | Constraints-chave | Regime temporal |
| --- | --- | --- | --- |
| `job_roles` (F3-02) | `id`, `organization_id`, `name`, `code` (aditivo F5-07), `status ∈ (active,disabled)`, `version`, `created_at/updated_at` | `uq_job_roles_organization_name (organization_id,name)`; `uq_job_roles_org_code (organization_id,code) where code is not null` (F5-07); FK `organization_id → organizations on delete restrict` | **status** (sem vigência) |
| `seniority_levels` (F3-02) | `id`, `organization_id`, `name`, `status`, `version` | `uq_seniority_levels_organization_name`; FK restrict | **status** (sem vigência) |
| `organizational_units` (F3-03) | `id`, `organization_id`, `name`, `valid_from`, `valid_to`, `version` | `uq_organizational_units_organization_name` (**não parcial**); `ck_valid_to`; `ck_name` (trim, não vazio); FK restrict | **uma linha, uma janela** `[valid_from, valid_to)`; sem exclusion |
| `organizational_unit_parent_periods` (F3-03) | `id`, `organization_id`, `unit_id`, `parent_unit_id` (NULL = raiz), `valid_from/valid_to`, `version` | FKs **compostas** `(unit_id|parent_unit_id, organization_id)` restrict; `ck_not_self`; `ex_..._no_overlap` por `unit_id` | **versionado** fechar-e-abrir; exclusão de sobreposição por unidade |
| `organizational_positions` (F3-03) | `id`, `organization_id`, `unit_id`, `job_role_id`, `seniority_level_id` (nullable), `valid_from/valid_to`, `version` | FKs compostas restrict; `uq_organizational_positions_id_organization` (F3-03 `:73-75` do arquivo F3-04); `ck_valid_to` | **uma linha, uma janela**; sem exclusion |
| `position_reporting_lines` (F3-04) | `subordinate_position_id`, `manager_position_id`, `reason`, vigência, `version` | `ex_..._no_overlap` por subordinada; `ck_not_self`; trigger anti-ciclo com CTE recursiva + advisory lock; trigger que recusa encerrar posição com reporting line aberta | **versionado** |
| `collegiate_configurations` (F3-08) | `collaborator_id` (avaliado), vigência, `version` | `ex_..._no_overlap` por avaliado; FK composta com `collaborators` restrict | **versionado** por avaliado; 0 membros ≠ ausência |
| `collegiate_configuration_members` (F3-08) | `config_id`, `member_collaborator_id` | `uq_..._config_member`; trigger anti-self | pertence à versão (sem vigência própria) |
| `structure_events` | — | **não existe** | — |

**Consequências medidas:**

1. `organizational_units` e `organizational_positions` são "linha única com janela": **não há
   segunda janela de vigência** — reabrir uma unidade/posição encerrada não é expressável sem
   `UPDATE` destrutivo do fato registrado (Q1).
2. Não existe índice em `organizational_unit_parent_periods.parent_unit_id` (só em `unit_id`,
   `:261`), embora os resolvers de descendência percorram o sentido pai→filho (D20).
3. O banco **não** impede ciclos entre unidades (documentado pela própria F3-03 `:62-65,
   194-195`): "a prevenção de ciclos multinível é responsabilidade da aplicação" → lacuna que
   esta atividade fecha (D7).
4. **Não existe** guarda que recuse encerrar uma posição com **ocupação vigente** (só existe a
   guarda análoga para reporting line, `20260907140000:313-350`), nem guarda para encerrar uma
   unidade com posições/períodos parent vigentes (D6).

### 4.3 RLS, grants e privilégios (medido no banco local da `main`)

- Leitura: policies `*_select_same_tenant` para as 8 tabelas do escopo
  (`20260908110000:33-69`) + `grant select` a `authenticated` (`:112-125`); `anon` sem grant
  (`20260908140000:27-28`). **Nenhuma policy de INSERT/UPDATE/DELETE existe** em nenhuma
  tabela de estrutura/catálogo.
- Escrita: `service_role` possui, por **default privileges do Supabase**, DML amplo
  (SELECT/INSERT/UPDATE/DELETE) em todas as tabelas de estrutura/catálogo — **exceto**:
  `position_reporting_lines` (DELETE revogado explicitamente pela F5-07,
  `20260913000000:794`), `collaborator_events` (só SELECT/INSERT, `:357-359`) e
  `privilege_mutation_audit` (só SELECT/INSERT, `20260910010000:85-86`).
- A F5-07 concedeu explicitamente a `service_role`: `select` em `organizational_units` e
  `organizational_positions` (`:781-782`) e `select, insert, update` em `job_roles` (`:783`),
  mas apenas `select, insert` em `seniority_levels` (`:784`) — assimetria **mascarada** pelo
  default privilege (finding §25.4).
- O guard de CI `02-validar-f4-08.sql` audita privilégios de `anon`/`authenticated`, **não** os
  de `service_role` (finding §25.4).
- Conclusão para a F5-08: **nenhum grant novo de tabela é necessário**; o que falta é
  (a) normalizar/negar `DELETE` onde a política é fechar-e-abrir, (b) conceder explicitamente
  `INSERT/UPDATE` nas tabelas efetivamente administradas, e (c) catalogar privilégios de
  `service_role` no guard de CI (D8, D16, D20).

### 4.4 Autorização hoje

- **Plano funcional:** allowlist `capabilityTarget.ts:45-46` — `"org.structure.manage": []`,
  `"org.catalog.manage": []` (deny por construção no passo capability×target, `:74-80`). Os
  códigos existem no catálogo canônico TS (`src/authorization/Capability.ts:32-33`;
  `catalogoCapabilities.ts:43-44`) e no catálogo SQL (`20260908000001:33,35,86,87`).
- **Plano administrativo:** Edge `colaboradores` decide por capability efetiva —
  `avaliarGateAdministrativo` (`supabase/functions/colaboradores/core.ts:472-492`) usando
  `resolver_capabilities_efetivas` → RPC `resolver_capabilities_escopos_efetivas`
  (`index.ts:382,538`); mapa operação→capability em
  `src/infrastructure/supabase/colaboradores/contrato.ts:73-118`.
- **Já no plano administrativo (F5-07):** `colaborador.ocupacao.definir|encerrar`,
  `estrutura.reporting.definir|encerrar`, `estrutura.responsabilidade.definir|encerrar`,
  `estrutura.sucessao.registrar` (`org.structure.manage`) e
  `colaborador.catalogo.bootstrap` (`org.catalog.manage`).
- **`usuario_eh_administrador`** (`20260910020000:39-63`) verifica apenas membership ativa +
  assignment ativo de **role de sistema** ativa — **não** conhece capability. Coexiste com o
  gate por capability (divergência §25.3(a)); a F5-08 decide qual usar (D10).
- **Revalidação no banco:** `colaborador_ator_valido(profile, org)` = perfil ativo + membership
  ativa, `SECURITY INVOKER` (`20260913000000:367-389`) — usada pela F5-07. As RPCs
  administrativas da F5-04 validam a autoridade **dentro** da transação; as RPCs da F5-07
  confiam o gate à Edge e só revalidam ator (assimetria de defesa em profundidade — resolvida
  por D10).

### 4.5 Autoridade estrutural local/sintética no cliente (o que precisa morrer)

| Caminho | O que fabrica | Evidência |
| --- | --- | --- |
| `src/authorization/mundoFuncional.ts` | bindings GESTAO/COORDENACAO/COLEGIADO derivados de estrutura local; raiz = ausência de `gestorDiretoMatricula` | `:129-159`, `:196-232` |
| `src/authorization/authorizationPolicy.ts` | `colaboradoresDoRecurso` cai em `getColaboradores()` local | `:53-66`, `:336`, `:354` |
| `src/authorization/providers/localWorld.ts` | organização sintética `"organizacao-sintetica-local"`; `isMembershipActive: () => true` | `:14`, `:33` |
| `src/services/historicoOrganizacionalStorage.ts` | reconstrói cargo/área/função/senioridade/gestor/colegiado por deltas locais e **promove texto `respondePara` a gestor** | `:248-341` |
| `src/services/colaboradorStorage.ts` | fallback de seed | `:36` |
| `src/data/colaboradores.ts` | seed DEV auto-suficiente (900001-900004) com estrutura embutida | arquivo |
| `src/services/expectativaCargoStorage.ts` | mapeia `funcao`×`senioridade` → expectativa (autoridade local, domínio settings) | `:179-216` |
| `src/services/progressoAvaliacao.ts`, `cicloEquipeService.ts`, `metaStorage.ts` | decidem elegibilidade/papel por `funcao`/`gestorDireto`/colegiado local | `progressoAvaliacao.ts:61,92-102`; `cicloEquipeService.ts:115-185,221-321`; `metaStorage.ts:171-194,401-412` |
| `src/data/evaluationTeam.ts` | código morto com nomes/matrículas | arquivo |

### 4.6 Leitura e telas pós-cutover da F5-07

- Projeção soberana: `src/infrastructure/supabase/colaboradores/repositorioColaboradores.ts:28-46`
  expõe `unitId/unitName`, `jobRoleCode/jobRoleName`, `seniorityName`,
  `managerCollaboratorId/managerFullName`, `version`; **sem** `funcao`, **sem** colegiado.
- Porta já existente **sem consumidor de UI**:
  `acessoColaboradoresSoberanos.ts:211-332` (+ `serviceColaboradores.ts:253-302`,
  `repositorioColaboradores.ts:515-615`) expõe `definirOcupacao`, `encerrarOcupacao`,
  `definirReportingLine`, `encerrarReportingLine`, `definirResponsabilidadeTemporaria`,
  `encerrarResponsabilidadeTemporaria`, `registrarSucessao`, `bootstrapCatalogo`.
- Telas: `NovoColaboradorPage.tsx` (estrutura removida; bloco "Estrutura organizacional (F5-08)"
  `:49-52`), `EditarColaboradorPage.tsx` (campos read-only `:648-681`;
  `AVISO_SEM_ALOCACAO:61-63`), `ColaboradoresPage.tsx` (`possuiAlocacao:95-105`; "Sem alocação"
  `:474`), `ColaboradorDetalhePage.tsx` (`:604-628`), `InicioPage.tsx` (roteia por leitura
  soberana, nunca por `funcao`).

### 4.7 Lacunas objetivas (G1–G12)

| # | Lacuna | Efeito |
| --- | --- | --- |
| G1 | Nenhuma operação soberana para criar/editar/encerrar **unidade**, **período parent** e **posição** | Estrutura não pode ser criada pelo produto; colaborador fica "sem alocação" para sempre |
| G2 | Nenhuma operação soberana para **catálogo** (criar/renomear/desativar cargo e senioridade) além do bootstrap | Catálogo só nasce por bootstrap |
| G3 | Nenhuma operação soberana para **colegiado** (definir/alterar/encerrar configuração e membros) | Colegiado só existe em dados legados/dev |
| G4 | Sem guarda de **ciclo entre unidades** no banco | Estrutura impossível pode ser gravada; `DIRECT_REPORTS`/`DESCENDANTS` podem entrar em laço |
| G5 | Sem guarda de **encerramento com estrutura vigente** (unidade com posições; posição com ocupação) | Estrutura impossível: posição em unidade encerrada; ocupação em posição encerrada |
| G6 | Sem trilha de auditoria estrutural (não há tabela ancorada em `organizational_unit_id`) | Mutações estruturais sem autoria soberana |
| G7 | Sem índice em `parent_unit_id` | Descendência/ancestralidade com custo evitável |
| G8 | Sem normalização de privilégios de `service_role` (DELETE implícito por default privileges) | Falta de barreira para DELETE físico |
| G9 | Guard de CI não cobre privilégios de `service_role` nem as tabelas de estrutura/catálogo da F3/F5-07 | Regressão de privilégio passa despercebida |
| G10 | Nota de lock divergente: trigger anti-ciclo F3-04 usa `hashtext('position_reporting_lines:'||org)`; RPCs estruturais F5-07 usam `hashtext('f5_07_estrutura:'||org)` | Caminhos não serializam entre si (Q4) |
| G11 | Cliente ainda deriva estrutura localmente (§4.5) | Hierarquia/autorização podem divergir do servidor |
| G12 | Telas de administração inexistentes; portas de ocupação/reporting sem UI | Nenhum caminho de produto para administrar estrutura |

### 4.8 Divergências documentação × estado real (registradas, não silenciadas)

| # | Divergência | Situação |
| --- | --- | --- |
| a | `20260907120000:21-22` (F3-02) afirma "NÃO há coluna `code`"; `20260913000000:144` a adiciona | Resolvida como extensão aditiva (F5-07 D5); cabeçalho do F3-02 desatualizado |
| b | `docs/F4-07-desenho-tecnico.md:263-265` diz que `access_role.manage`/`membership.manage` existem "só no catálogo SQL"; hoje estão no TS (`catalogoCapabilities.ts:41-42`) | Documento defasado (finding) |
| c | F5-07 §6.4 (`:394-409`) não lista `position_id`, `payload_hash`, `result_entity_id` de `collaborator_events`, que existem (`20260913000000:216-233`) | Omissão documental (finding) |
| d | F4-02 §9 (`:296-297`) exemplifica `org.structure.manage + collaborator.manage + ORGANIZATION ⇒ administrar estrutura` | **Incompatível** com F4-04 D18 (allowlist `[]`) e F5-07 D10/D19; a F5-08 segue D19 e registra a divergência |
| e | F5-07 §10.4/§20.1 exigem catalogação no guard do CI; `.github/workflows/ci.yml` só executa validadores F4-08 e F5-04 | Guard incompleto (G9) — corrigido no escopo da F5-08 para as suas tabelas (D20) |
| f | `usuario_eh_administrador` não exige capability nem a role `admin` nominal, divergindo do texto de F5-04 §17 `:468` | Divergência de granularidade; resolvida para a F5-08 por D10 |
| g | `supabase/functions/colaboradores/core.ts:611-619` tem `default: return "org.structure.manage"` no mapa capability↔operação | Fallback implícito (hoje inócuo; finding §25.4) |

## 5. Escopo

**Entra no escopo da F5-08:**

1. Caminho soberano de **escrita** para: `organizational_units`,
   `organizational_unit_parent_periods`, `organizational_positions`,
   `position_reporting_lines` (UI; a operação já existe), `job_roles`, `seniority_levels`,
   `collegiate_configurations` (+ `collegiate_configuration_members`).
2. **Leitura soberana** para as telas de administração, no contrato F4-08 já vigente.
3. **Integridade estrutural**: anti-ciclo de unidades, guardas de encerramento, referência a
   catálogo inativo, integridade cross-tenant, sobreposições e estados impossíveis.
4. **Plano administrativo** de autorização (capability-precise) e respectiva defesa em
   profundidade no banco, preservando D19 (nenhuma capability nova; allowlist intacta).
5. **Auditoria/autoria** append-only das mutações estruturais e de catálogo.
6. **Concorrência**: versão otimista, idempotência por `operation_id`, serialização por
   organização, TOCTOU.
7. **Cutover da UI** das telas que criam/editam/listam/selecionam/relacionam essas entidades,
   incluindo devolver ao formulário de colaborador as seleções soberanas de unidade, cargo,
   senioridade e gestor.
8. **Remoção de autoridade estrutural local/sintética** (§4.5), preservando apenas cache/DEV
   explicitamente não soberano.
9. **Validação**: validadores SQL novos, testes TS e regressão dos gates F4/F5.
10. **Catalogação no guard do CI** para as tabelas/privilégios desta atividade.

## 6. Fora de escopo

1. **F5-09…F5-12**: ciclos de avaliação, metas, observações, importação de acervo legado.
2. **Alteração de contratos F4/F5 fechados**: allowlist capability×target (F4-04 D18), tipos de
   scope (F4-02 §4), resolvers F3-07/F4-02, projeção do colaborador (F5-07 §6.5/§6.6).
3. **Nova capability** ou novo plano de autorização (proibido por D19).
4. **Redesenho do modelo temporal das tabelas F3** (ex.: criar tabela de versões de unidade ou
   de posição) — tema de Q1/Q2; só entra se as questões forem decididas nesse sentido.
5. **Correção do defeito preexistente** `supabase/functions/avaliacoes/index.ts` →
   `catalogoCapacidades.ts` inexistente: não é bloqueador desta atividade; permanece como
   finding com manutenção própria (§25.4).
6. **Domínio `settings`** (`expectativaCargoStorage`, escala, expectativas, reset de base DEV):
   não é estrutura organizacional; permanece local por contrato próprio (finding §25.4).
7. **Dados reais / importação**: nenhuma migração de dados de produção; seeds continuam
   fictícios.
8. **`occupations`/`temporary_responsibilities`/snapshots de colegiado** como **novas** tabelas
   administradas: as operações de ocupação/responsabilidade já existem (F5-07); a F5-08 lhes dá
   UI (Q5). Snapshots por ciclo são F5-09.

## 7. Inventário das entidades afetadas

| Entidade | Tabela | Regime temporal (D2) | Identidade | Tenant key | F5-08 |
| --- | --- | --- | --- | --- | --- |
| Unidade organizacional | `organizational_units` | linha única + janela `[valid_from, valid_to)` | `id` (UUID) | `organization_id` (NOT NULL, FK restrict) | CRUD + encerramento |
| Vínculo pai/filho de unidade | `organizational_unit_parent_periods` | versionado (fechar-e-abrir) | `id`; unicidade de negócio = `(unit_id, janela)` | `organization_id` + FKs compostas | CRUD + encerramento |
| Posição | `organizational_positions` | linha única + janela | `id` (UUID) | `organization_id` + FKs compostas | CRUD + encerramento |
| Reporting line | `position_reporting_lines` | versionado | `id`; negócio = `(subordinate_position_id, janela)` | `organization_id` + FKs compostas | UI + guardas (operação já existe) |
| Cargo | `job_roles` | status `active|disabled` | `id`; rótulos `name`/`code` | `organization_id` (FK restrict) | CRUD + inativação |
| Senioridade | `seniority_levels` | status | `id`; rótulo `name` | `organization_id` (FK restrict) | CRUD + inativação |
| Configuração de colegiado | `collegiate_configurations` | versionado por avaliado | `id`; negócio = `(collaborator_id, janela)` | `organization_id` + FK composta | CRUD + encerramento |
| Membros do colegiado | `collegiate_configuration_members` | pertence à versão | `id`; único `(config_id, member_collaborator_id)` | `organization_id` | CRUD (via versão) |
| Trilha estrutural | `structure_events` | append-only | `id` | `organization_id` | **nova** (D13) |

**Entidades consumidoras (não administradas aqui, mas impactadas):** `occupations` (F3-05),
`temporary_responsibilities` (F3-06), `position_reporting_lines` (consumida por
DIRECT_REPORTS/DESCENDANTS), `collegiate_cycle_snapshots*` (F3-08), `collaborators` (F5-07),
`cycle_evaluation_responsibilities` (F3-09), `membership_collaborator_links` (F4-02),
`access_role_assignment_unit_targets` (F4-02).

## 8. Modelo de dados proposto

### 8.1 Princípio: reuso integral (D1)

As sete entidades exigidas pela F5-07 §20.1 **já existem** com PK/FK/constraints/exclusion e
versionamento compatíveis com o contrato temporal do projeto. A F5-08 **não cria tabela de
entidade nova**, não renomeia coluna, não altera domínio de coluna existente e não escreve
migration destrutiva. O que a F5-08 acrescenta é:

1. **operações** (RPCs transacionais) sobre as tabelas existentes;
2. **guardas de integridade** que faltam (ciclo de unidades; encerramento com estrutura
   vigente; referência a catálogo inativo em relação nova);
3. **uma** tabela de trilha append-only (`structure_events`);
4. **um** índice ausente;
5. **normalização de privilégios** de `service_role` e catalogação no guard do CI.

Alternativa rejeitada: **criar tabelas novas** (ex.: `organizational_unit_versions`,
`organizational_position_periods`) para "resolver" reabertura/reatribuição. Rejeitada porque
(i) duplicaria a fonte de verdade e quebraria FKs de `occupations`, `position_reporting_lines`,
`collegiate_cycle_snapshot_positions` e `access_role_assignment_unit_targets`;
(ii) não é exigida por nenhum contrato fechado; (iii) os casos que a motivariam são Q1/Q2.

### 8.2 Nenhum campo de motivo nas tabelas F3 (D1)

O motivo (`reason`) de criação/alteração/encerramento **não** vira coluna em
`organizational_units`/`organizational_positions`/`job_roles`/`seniority_levels`. Motivo,
autor, data efetiva e estado anterior são **eventos** (D13). Consequências:
`position_reporting_lines.reason` e `occupations.reason` (colunas já existentes em F3) são
**preservados como estão** — são atributos da própria relação temporal, não auditoria.

### 8.3 Tabela nova: `structure_events` (D13)

```
create table public.structure_events (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null,
  entity_type               text        not null,   -- 'organizational_unit' | 'organizational_unit_parent_period'
                                                  -- | 'organizational_position' | 'job_role'
                                                  -- | 'seniority_level' | 'collegiate_configuration'
  entity_id                 uuid,                   -- entidade afetada
  event_type                text        not null,   -- 'CRIADO' | 'RENOMEADO' | 'ENCERRADO' | 'REATIVADO'
                                                  -- | 'PARENT_DEFINIDO' | 'PARENT_ENCERRADO'
                                                  -- | 'MEMBROS_ALTERADOS' | 'COLEGIADO_ENCERRADO'
  effective_date            timestamptz not null,   -- data de negócio (valid_from/valid_to da mutação)
  reason                    text        not null,
  before_value              jsonb,                  -- estado anterior relevante (normalizado; nunca PII)
  after_value               jsonb,                  -- estado novo relevante (normalizado)
  payload_hash              text        not null,   -- sha256 do payload canônico (idempotência)
  result_entity_id          uuid,                   -- entidade resultante quando difere de entity_id
  actor_user_profile_id     uuid        not null,
  actor_membership_id       uuid        not null,
  operation_id              uuid        not null,
  created_at                timestamptz not null default now(),
  constraint pk_structure_events primary key (id),
  constraint uq_structure_events_org_operation unique (organization_id, operation_id),
  constraint fk_structure_events_organizations foreign key (organization_id)
    references public.organizations (id) on delete restrict,
  constraint ck_structure_events_entity_type check (entity_type in (...)),
  constraint ck_structure_events_event_type  check (event_type  in (...)),
  constraint ck_structure_events_reason      check (reason <> '' and reason = btrim(reason))
);
create index ix_structure_events_organization_id on public.structure_events (organization_id);
create index ix_structure_events_entity        on public.structure_events (organization_id, entity_type, entity_id);
create index ix_structure_events_effective     on public.structure_events (organization_id, effective_date);
```

Regras da trilha (idênticas em espírito a `collaborator_events`, F5-07 §12): evento e mutação na
**mesma transação**; `before_value`/`after_value`/`payload_hash` **nunca** são autoridade de
tenant ou de ator; `UPDATE`/`DELETE` bloqueados por trigger de exceção e por ausência de grant.

**Por que não estender `collaborator_events`** (alternativa rejeitada): a tabela tem
`collaborator_id`/`position_id` com CHECK/FK e tipos de evento ancorados em colaborador e
posição (`20260913000000:216-285`); não há âncora para `organizational_unit_id`,
`job_role_id` ou `seniority_level_id`. Estender exigiria relaxar CHECK/FK de uma tabela fechada
na F5-07 — violação de "não alterar contratos fechados". **Por que não reusar
`evaluation_events` (F5-06)**: nomenclatura divergente (`motivo`/`valor_anterior`/`valor_novo`),
sem `operation_id`/`payload_hash` e escopo de avaliação. **Por que não reusar
`privilege_mutation_audit` (F5-04)**: escopo é privilégio (`membership_id`, `access_role_id`,
`action ∈ grant|revoke`), não estrutura.

### 8.4 Índice novo (D20)

```
create index ix_organizational_unit_parent_periods_parent_unit_id
  on public.organizational_unit_parent_periods (parent_unit_id);
```
Necessário porque `organizacao_resolver_descendentes`/`_escopo_posicoes` e o novo guarda
anti-ciclo percorrem `parent_unit_id → unit_id`; hoje existe índice apenas em `unit_id`
(`20260907130000:261`). Nenhum outro índice é proposto sem uso comprovado (os de
`organizational_positions.job_role_id/seniority_level_id/unit_id` já existem, `:363-372`).

### 8.5 Extensões aditivas rejeitadas

| Extensão cogitada | Decisão | Motivo |
| --- | --- | --- |
| `code` em `seniority_levels` | **não** | Nenhum contrato exige; `funcao` legada só existe para cargo (F5-07 D5) |
| coluna de `rank`/ordenação em catálogos | **não** | F3-02 declara explicitamente ausência de coluna de ordenação (`:30-34`); ordenação é UX por `name` |
| `reason` nas tabelas de estrutura | **não** | Motivo vive na trilha (D1, D13) |
| `valid_from`/`valid_to` em `job_roles`/`seniority_levels` | **não** | Regime é status (F3-02 `:26-29, 116-118, 186-189`); introduzir vigência quebraria o regime por contrato |
| tabela de versões de unidade/posição | **não nesta atividade** | Q1/Q2 decidem a necessidade de produto |

## 9. Modelo temporal

### 9.1 Semântica obrigatória (D2)

`tstzrange(valid_from, coalesce(valid_to, 'infinity'), '[)')` — meio-aberto à direita, como em
todo o domínio; `valid_to > valid_from` (`ck_*_valid_to`); vigente na data `d` ⇔
`valid_from <= d < coalesce(valid_to,'infinity')`. **`valid_to` nunca retrocede** e nenhuma
linha temporal fechada é alterada (F5-07 §11.4). Mudança = **fechar + abrir**; a exceção de
retificação é Q3.

### 9.2 Regime por entidade

| Entidade | Regime | Como se altera | Como se encerra | Histórico |
| --- | --- | --- | --- | --- |
| `organizational_units` | **linha única + janela** | `UPDATE name` (rótulo) com `expected_version` e trilha (D4) | `UPDATE valid_to` | nome anterior na trilha; `valid_from/valid_to` são o próprio fato |
| `organizational_unit_parent_periods` | **versionado** | fecha o período vigente (`valid_to`) e abre novo (`valid_from`) na mesma transação | fecha o período vigente | linhas fechadas permanecem |
| `organizational_positions` | **linha única + janela** | atributos estruturais imutáveis (D5); a posição não tem rótulo próprio | `UPDATE valid_to` | ocupações/reporting lines referenciam o `id` imutável |
| `position_reporting_lines` | **versionado** | fecha + abre (operação F5-07 já existente) | fecha | linhas fechadas permanecem |
| `job_roles` / `seniority_levels` | **status** | `UPDATE name` (rótulo) / `status` | `status='disabled'` (**não** é vigência) | trilha de status/nome |
| `collegiate_configurations` (+ membros) | **versionado por avaliado** | fecha a versão vigente e cria nova versão com o conjunto de membros desejado (F3-08 D4/D9/D10) | fecha a versão vigente | versões anteriores com seus membros |

### 9.3 "As of" (estado atual × histórico)

- Estado atual: `valid_to is null` (unidades, posições, reporting lines, colegiado) e
  `status='active'` (catálogos).
- Estado histórico na data `d`: predicado de vigência acima. Nenhuma consulta "as of" nova é
  criada — usa-se o que os resolvers F3-07/F4-02 já fazem (`organizacao_resolver_*`,
  `resolver_alvos_escopo`; F4-02 D16 `:793-804`).
- **Snapshot de ciclo (F3-08/09) é imutável e não é recalculado** por mutações da F5-08
  (F3-08 D9/D10). Consequência explícita: encerrar uma posição hoje **não** altera o colegiado
  ou o superior congelado de ciclos passados.

### 9.4 Efeito em avaliações e histórico existentes

| Mutação da F5-08 | Efeito em dados passados |
| --- | --- |
| Renomear unidade/cargo (rótulo) | `area`/`cargo` exibidos mudam (rótulo corrente), **mas** `collaborator_events.before/after_value` preservam o rótulo vigente à época; snapshots de ciclo **não** copiam nomes (`20260907180000:24-30`) ⇒ nenhum fato passado é reescrito |
| Encerrar posição | `occupations`/reporting lines históricas continuam resolvíveis pelo `position_id`; nenhuma exclusão (FK restrict) |
| Encerrar unidade | posições e períodos parent históricos permanecem; **proibido** encerrar com posição ou período vigente (D6) |
| Desativar cargo/senioridade | posições existentes continuam válidas e legíveis; novas posições **não** podem referenciar item inativo (D17) |
| Alterar colegiado | abre nova versão; avaliações passadas usam snapshots congelados |

### 9.5 Continuidade e ausência de lacuna

Toda mutação versionada fecha a linha vigente com `valid_to` **no exato** `valid_from` da nova
linha (continuidade sem lacuna e sem sobreposição), satisfazendo a exclusion constraint. Se o
chamador pedir `valid_from` futuro, a linha vigente é fechada nessa data e existe um intervalo
"em vigor até lá" — comportamento determinístico, documentado na resposta da RPC.

### 9.6 Colegiado: ausência ≠ vazio (F3-08 D8)

- **Sem configuração**: nenhuma linha em `collegiate_configurations` para o avaliado ⇒ ausência.
- **Configuração com 0 membros**: versão vigente sem linhas em `_members` ⇒ "sem colegiado"
  **explícito**.
- `estrutura.colegiado.definir` com lista vazia cria a segunda situação; com lista não vazia,
  cria a versão com membros. `estrutura.colegiado.encerrar` produz a primeira.

## 10. Integridade estrutural

### 10.1 O que o PostgreSQL já garante (não duplicar na aplicação)

| Garantia | Onde |
| --- | --- |
| PKs, tenant ownership (`organization_id NOT NULL`), FK `→ organizations` restrict | F3-02/03/04/08 |
| **Cross-tenant impossível por construção** nas referências internas: FKs **compostas** `(ref_id, organization_id) → (id, organization_id)` | `20260907130000:207-214, 303-311`; `20260907180000:73-75, 131-134` |
| Não-auto-relação (`ck_not_self`; trigger anti-self no colegiado) | `20260907130000:217-218`; `20260907140000`; `20260907180000:159-184` |
| Sobreposição proibida onde há versionamento | `ex_*_no_overlap` (parent periods, reporting lines, occupations, temporary responsibilities, collegiate) |
| `valid_to > valid_from` | `ck_*_valid_to` |
| Nome não vazio e sem espaços nas bordas | `ck_*_name` |
| **Anti-ciclo em reporting lines** (CTE recursiva + advisory lock + recusa de par invertido) | `20260907140000:256-303` |
| Encerrar posição com reporting line aberta é recusado | `20260907140000:313-350` |
| Inativar colaborador com ocupação vigente é recusado | `20260907150000:218-236` |

### 10.2 O que falta e como é fechado

| # | Lacuna | Fechamento proposto | Camada |
| --- | --- | --- | --- |
| I1 | **Ciclo entre unidades** (documentado como responsabilidade da aplicação, `20260907130000:62-65, 194-195`) | Função `enforce_organizational_unit_parent_periods_no_cycle()` (BEFORE INSERT/UPDATE), CTE recursiva subindo por `parent_unit_id` na **data da linha**, recusando quando alcança `unit_id`; `pg_advisory_xact_lock(hashtext('position_reporting_lines:' || organization_id))` (mesma chave do trigger F3-04 — D14) | Trigger no banco |
| I2 | Encerrar **unidade** com posição vigente | Trigger `enforce_organizational_unit_close_requires_no_open_structure()`: recusa `valid_to` quando existe `organizational_positions` vigente na data com `unit_id` = unidade, ou `organizational_unit_parent_periods` vigente com `unit_id` = unidade | Trigger no banco |
| I3 | Encerrar **posição** com ocupação vigente | Trigger `enforce_organizational_position_close_requires_no_open_occupations()`: recusa `valid_to` quando existe `occupations` vigente na data da posição (análogo ao trigger F3-04 para reporting line, que já existe e é preservado) | Trigger no banco |
| I4 | Referência **nova** a catálogo inativo | Validação na RPC `estrutura_posicao_criar`: `job_roles.status='active'` e (`seniority_level_id` nulo **ou** `seniority_levels.status='active'`), ambos no mesmo `organization_id` | RPC (mais barato e explícito; **não** vira trigger para não impedir leitura histórica) |
| I5 | Período parent de unidade **encerrada** | Validação na RPC: unidade filha e pai (quando não nulo) vigentes na data pedida | RPC |
| I6 | Cross-tenant em `p_organization_id` vs entidade | Toda RPC resolve a entidade por `(id, organization_id)`; ausente ⇒ `NOT_FOUND` (nunca "existe em outro tenant") | RPC |
| I7 | Subordinação de posições **incompatíveis** | Já garantido: FK composta exige mesma organização; o trigger F3-04 exige que ambas as posições existam; auto-relação recusada. A F5-08 **não** inventa restrição de "mesma unidade" (não existe contrato para isso) | Banco (existente) |
| I8 | `parent_unit_id` sem índice | D20 | Índice |

### 10.3 Regras que exigem RPC transacional (e não constraint)

1. **Fechar + abrir** com `expected_version` e trilha na mesma transação (§14).
2. **Idempotência** por `operation_id`/`payload_hash` (constraint única + leitura prévia).
3. **Autoridade administrativa** por capability efetiva (§11).
4. **Tenant do ator** revalidado contra `p_organization_id` (§12).
5. **Referência a catálogo ativo** (I4) e **vigência das unidades** (I5).
6. **Colegiado**: substituir a versão vigente por nova versão com membros distintos — operação
   multi-linha (config + N membros) que precisa ser atômica.
7. **Encerramento com estrutura vigente**: a checagem é feita no trigger (I2/I3) **e**
   pré-validada na RPC, para devolver `CONFLICT` com mensagem pública estável em vez de erro
   cru do banco.

### 10.4 Estruturas impossíveis — resposta direta (pergunta 5)

| Estrutura impossível | Bloqueio |
| --- | --- |
| Unidade ancestral de si mesma (direta ou em N níveis) | I1 |
| Períodos parent sobrepostos para a mesma unidade | exclusion constraint existente |
| Posição em unidade encerrada / inexistente / de outra organização | I2 + FK composta + I6 |
| Posição com cargo/senioridade inativo, inexistente ou de outra organização | I4 + FK composta |
| Reporting line para posição de outra organização | FK composta + trigger F3-04 |
| Reporting line que cria ciclo | trigger F3-04 (preservado) |
| Ocupação em posição encerrada | I3 impede o encerramento com ocupação vigente; `trg_occupations_within_position` impede abrir ocupação fora da vigência da posição |
| Colegiado com o avaliado como membro | trigger `trg_collegiate_configuration_members_not_self` |
| Membro de colegiado de outra organização | FK composta |
| Vigência invertida / sobreposição no colegiado | `ck_*` + exclusion existentes |
| DELETE físico de fato estrutural | ausência de policy de escrita + `revoke delete` (D8) |

## 11. Plano administrativo e autorização

### 11.1 Gate: capability efetiva, nunca role nominal (D10)

A administração estrutural/catalogal **não** passa pelo Policy Engine funcional (allowlist `[]`,
D19). O gate é o plano administrativo server-side, na forma exata já entregue pela F5-07:

1. **Identidade**: `actor_user_profile_id` deriva **somente** de `auth.uid()` verificado na Edge
   (`auth.getUser`); nunca do corpo da requisição (F5-04 `:6-28`; F5-07 §7).
2. **Organização**: `organization_id` do corpo é **intenção**; revalidada contra a membership
   ativa do ator (divergência ⇒ `FORBIDDEN`).
3. **Capability**: `org.structure.manage` ou `org.catalog.manage` presente nas capabilities
   efetivas (`resolver_capabilities_efetivas`; RPC `resolver_capabilities_escopos_efetivas`,
   `20260910000000:158-238`), lida na Edge por `avaliarGateAdministrativo`
   (`core.ts:472-492`).
4. **Revalidação no banco (defesa em profundidade — decisão desta atividade)**: **toda** RPC da
   F5-08 revalida, **na mesma transação**:
   - `colaborador_ator_valido(p_actor_user_profile_id, p_organization_id)` (perfil ativo +
     membership ativa; `20260913000000:367-389`);
   - a **mesma capability** exigida, via `resolver_capabilities_escopos_efetivas`
     (`security invoker`, `EXECUTE` só `service_role`), filtrando
     `capability_code = <exigida>`.

**Por que `usuario_eh_administrador` não basta (e não é usado como gate da F5-08):** ele
verifica apenas "membership ativa + assignment de role de sistema ativa"
(`20260910020000:49-62`), sem olhar capability. Uma role **customizada** que conceda
`org.structure.manage` passa no gate por capability e falharia nele. F5-07 D19/Q1 `:1258` fecha
o requisito ("role administrativa **que conceda a capability exigida**"); a F5-08 implementa
exatamente isso nas duas camadas, sem reabrir F5-04 (as RPCs administrativas da F5-04 continuam
usando `usuario_eh_administrador`, adequado ao escopo delas).

### 11.2 ActorContext e ResourceContext (perguntas 13 e 14)

- **ActorContext:** mesma forma do plano administrativo F5-04/F5-07 —
  `{ userProfileId (de JWT verificado), organizationId (revalidado), capability exigida,
  operationId, occurredAt }`. Não há `ResourceContext` funcional (alvo tipado do vocabulário do
  engine) porque essas capabilities têm `target: []` (F4-04 D18): passar pelo engine resultaria
  em DENY permanente por construção. O "recurso" aqui é a entidade estrutural identificada por
  `(entity_id, organization_id)` e resolvida **dentro** da RPC.
- **Consequência:** nenhum `can()`/`authorize()` do cliente participa da decisão; `can()`
  continua exclusivamente UX (`.ai/architecture-rules.md`).

### 11.3 Mapa capability → operações (D11) — respostas às perguntas 10, 11 e 12

| Grupo | Capability | Operações |
| --- | --- | --- |
| Estrutura | `org.structure.manage` | unidade (criar/renomear/encerrar), parent period (definir/encerrar), posição (criar/encerrar), reporting line (definir/encerrar — **já existente**), responsabilidade temporária (definir/encerrar — **já existente**), sucessão (registrar — **já existente**), ocupação do colaborador (definir/encerrar — **já existente**), colegiado (definir/encerrar) |
| Catálogo | `org.catalog.manage` | cargo (criar/renomear/alterar status), senioridade (criar/renomear/alterar status), bootstrap de catálogo (**já existente**) |

**Operação que não se encaixa inequivocamente (pergunta 12):** `collegiate_configurations`.
O enunciado a lista no bloco CATÁLOGOS, mas ela **não é catálogo**: é relação temporal ancorada
em **um colaborador avaliado** (F3-08 `:9-15`), versionada, com membros explícitos, não
reutilizável entre avaliados; e **não cria hierarquia** (não gera reporting line, ocupação nem
escopo — F3-08 `:6-7`). **Decisão:** pertence a `org.structure.manage` (D11), porque (a) é
estrutura de **relação** de avaliação, não vocabulário reutilizável; (b) tratá-la como catálogo
sugeriria "desativar no lugar sem vigência", regime errado para relação temporal por avaliado;
(c) já convive com as relações estruturais na mesma fronteira. Alternativas rejeitadas:
capability nova (proibida por D19) e `org.catalog.manage` (misturaria regimes temporais
incompatíveis; o mapa existente da F5-07 usa `org.structure.manage` para relações versionadas).

### 11.4 Precedente de forma (F5-04) reutilizado

As RPCs da F5-08 seguem o formato de `conceder_acesso_role_rpc`
(`20260910020000:75-137`): ator não-nulo obrigatório; entidade-alvo resolvida no tenant;
tenant do ator revalidado; autoridade verificada; efeito aplicado; trilha gravada — tudo numa
transação. **Diferença deliberada:** `SECURITY INVOKER` (como a F5-07), não `SECURITY DEFINER`
(a F5-04 usa DEFINER nos primitivos por necessidade de delegação). Nenhum `SECURITY DEFINER`
novo (`.ai/architecture-rules.md`).

### 11.5 Revogação e freshness

Nenhum resultado de autorização é cacheado entre operações; a capability é reavaliada na Edge
**e** no banco em cada mutação. Revogar `org.structure.manage` passa a valer **na operação
seguinte** (F4-10 §18 REV-001…REV-011). Como a revalidação no banco repete a checagem, um
`service_role` mal utilizado (ou um cliente que chame a RPC com payload forjado) **não** obtém
autoridade: o ator precisa existir, ter membership ativa e ter a capability efetiva.

### 11.6 D19 e D20 — confirmação explícita (pergunta 28)

Não há evidência técnica nova que exija reconsiderar D19 ou D20:
`org.structure.manage`/`org.catalog.manage` continuam no plano administrativo server-side;
**nenhuma capability nova** é criada; a allowlist funcional capability×target **não** é
ampliada (permanece `[]` para as duas, `capabilityTarget.ts:45-46`, com o teste-guard
`colaboradoresContratoRpc.test.ts:639-654` preservado); o CRUD estrutural permanece na F5-08.
**D19 e D20 permanecem intactas** (D19 desta atividade).

## 12. Trust boundaries

### 12.1 Fronteiras

| Fronteira | Quem atravessa | Regra |
| --- | --- | --- |
| Navegador → Edge `colaboradores` | JWT do usuário + corpo | Corpo é **intenção**; identidade vem do JWT; forma validada pelo contrato compartilhado |
| Edge → Postgres (RPC) | `service_role`, **sem** o JWT do usuário no `Authorization` | `service_role` **executa**, nunca decide autorização; a decisão vem da capability do ator e das guardas do banco |
| Navegador → PostgREST (leitura) | JWT do usuário | RLS F4-08: SELECT own-tenant apenas |
| Navegador → tabelas (escrita) | — | **Bloqueado**: `revoke all` de `anon`/`authenticated` + ausência de policy de escrita |
| Navegador → RPC (direto) | — | **Bloqueado**: `revoke all on function ... from public, anon, authenticated`; `EXECUTE` só `service_role` |
| Frontend (mundo funcional local) | dados locais/DEV | **Não é autoridade** (D18); passa a consumir projeção soberana |

### 12.2 Ataques/erros do enunciado e onde são bloqueados

| Ataque/erro | Onde é bloqueado | Realização |
| --- | --- | --- |
| Trocar `organization_id` no payload | Edge (membership ativa) **e** RPC (revalidação na transação) ⇒ `FORBIDDEN` | §11.1 |
| Trocar IDs das entidades (usar id de outra organização) | Toda RPC resolve por `(id, organization_id)`; ausente ⇒ `NOT_FOUND` | §10.2 I6 |
| Relacionar entidades de organizações diferentes | FKs **compostas** `(ref_id, organization_id)` | `20260907130000:207-214, 303-311` |
| Revogar membership entre leitura e escrita | `colaborador_ator_valido` **dentro** da transação (TOCTOU) | §14.5 |
| Remover capability antes da mutação | Gate reavaliado na Edge **e** na RPC, por operação | §11.1, §11.5 |
| Chamar RPC diretamente / executá-la como `authenticated` | `EXECUTE` só `service_role` | §13.4 |
| Escrever diretamente nas tabelas | `revoke all` de `anon`/`authenticated` + sem policy de escrita | `20260908140000:27-28`; §13.2 |
| Alterar registros de auditoria | append-only por trigger de exceção + ausência de `UPDATE`/`DELETE` | `20260913000000:320-333`; D13 |
| Race conditions / criação concorrente | Versão otimista (`expected_version`) + advisory lock por organização | §14 |
| Ciclos gerados por concorrência | Lock **antes** da checagem recursiva, na mesma chave do trigger anti-ciclo | §10.2 I1; §14.3 |
| Usar registros inativos (cargo/senioridade) | Recusa em relação **nova** (I4); leitura histórica preservada | §10.2 I4 |
| Usar períodos históricos fora de vigência | Predicado de vigência em toda resolução; guardas I2/I3 | §9.1, §10.2 |
| Payload manipulado para "provar" tenant/ator | `actor_user_profile_id`/`organization_id` nunca vêm do corpo como prova | §11.1; F5-07 §12.2 |

## 13. RLS / grants / RPCs

### 13.1 Leitura (D16) — sem mudança

As 8 tabelas já têm policy `*_select_same_tenant` e `grant select` a `authenticated`
(`20260908110000:33-69, 112-125`). A F5-08 **não** cria policy de leitura, **não** cria RPC de
listagem administrativa e **não** altera grants de leitura. `anon` permanece sem acesso.
Consequência registrada: qualquer membro ativo da organização pode ler a estrutura da própria
organização — exatamente o que a F4-08 fechou; as telas de administração não usam essa
permissão como autorização de escrita.

### 13.2 Escrita — nenhuma policy, grants mínimos

- Nenhuma policy de INSERT/UPDATE/DELETE é criada: `authenticated` **não** escreve direto.
- Toda escrita ocorre por RPC `SECURITY INVOKER` executada por `service_role`.

### 13.3 Matriz de privilégios de tabela

| Tabela | `anon` | `authenticated` | `service_role` hoje | `service_role` proposto |
| --- | --- | --- | --- | --- |
| `organizational_units` | — | SELECT (own-tenant) | ALL (default privileges) | SELECT, INSERT, UPDATE (**revoke delete**) |
| `organizational_unit_parent_periods` | — | SELECT | ALL (default) | SELECT, INSERT, UPDATE (**revoke delete**) |
| `organizational_positions` | — | SELECT | ALL (default) | SELECT, INSERT, UPDATE (**revoke delete**) |
| `position_reporting_lines` | — | SELECT | SELECT, INSERT, UPDATE (DELETE já revogado na F5-07) | SELECT, INSERT, UPDATE |
| `job_roles` | — | SELECT | ALL (default) | SELECT, INSERT, UPDATE (**revoke delete**) |
| `seniority_levels` | — | SELECT | ALL (default) | SELECT, INSERT, UPDATE (**revoke delete**) |
| `collegiate_configurations` | — | SELECT | ALL (default) | SELECT, INSERT, UPDATE (**revoke delete**) |
| `collegiate_configuration_members` | — | SELECT | ALL (default) | SELECT, INSERT, UPDATE (**revoke delete**) |
| `structure_events` (**nova**) | — | — | — | SELECT, INSERT (**sem update/delete**) |
| snapshots de colegiado, `cycle_evaluation_responsibilities`, `evaluation_*` | — | conforme F4-08 | não administradas pela F5-08 | inalterado |

Notas: (i) os grants devem ser **explícitos** (`revoke all ... from service_role` seguido de
`grant ...`) para não depender de default privileges; (ii) `privilege_mutation_audit` e
`collaborator_events` permanecem intocados; (iii) nenhum grant novo a `anon`/`authenticated`.

### 13.4 EXECUTE

Toda RPC nova: `revoke all on function ... from public, anon, authenticated` +
`grant execute ... to service_role` (padrão F5-04 `:213-219` e F5-07 `:1851-1873`). Nenhuma RPC
exposta a `authenticated`. As funções de trigger **não** recebem `EXECUTE` de ninguém (não são
chamáveis diretamente).

### 13.5 SECURITY INVOKER × DEFINER

- **INVOKER** em todas as RPCs e funções de trigger/resolução novas.
- **DEFINER**: nenhum novo. A única função DEFINER na cadeia é `resolver_capabilities_efetivas`
  (F4-01/F5-04, `20260910000000:165`) — preexistente, usada como está, com `EXECUTE` restrito a
  `service_role`.
- Justificativa de não usar DEFINER: com `service_role` como executor e RLS deny-by-default
  para escrita, a elevação é desnecessária; `search_path` fixado em `public` em todas as funções.

### 13.6 RPCs propostas (assinaturas)

Todas recebem `p_organization_id uuid`, `p_actor_user_profile_id uuid`, `p_operation_id uuid`,
`p_motivo text`; onde há linha existente, também `p_expected_version integer`.

| RPC | Entrada adicional | Efeito |
| --- | --- | --- |
| `estrutura_unidade_criar` | `p_nome text`, `p_valid_from timestamptz` | cria unidade; evento `CRIADO` |
| `estrutura_unidade_renomear` | `p_unidade_id uuid`, `p_nome text`, `p_expected_version int` | rótulo (D4); evento `RENOMEADO` |
| `estrutura_unidade_encerrar` | `p_unidade_id uuid`, `p_valid_to timestamptz`, `p_expected_version int` | encerra (guardas I2/I5); evento `ENCERRADO` |
| `estrutura_unidade_parent_definir` | `p_unidade_id uuid`, `p_parent_unit_id uuid` (null = raiz), `p_valid_from timestamptz` | fecha período vigente + abre novo; anti-ciclo I1; evento `PARENT_DEFINIDO` |
| `estrutura_unidade_parent_encerrar` | `p_unidade_id uuid`, `p_valid_to timestamptz` | fecha período vigente (unidade vira raiz); evento `PARENT_ENCERRADO` |
| `estrutura_posicao_criar` | `p_unidade_id uuid`, `p_job_role_id uuid`, `p_seniority_level_id uuid`, `p_valid_from timestamptz` | cria posição (I4/I5); evento `CRIADO` |
| `estrutura_posicao_encerrar` | `p_posicao_id uuid`, `p_valid_to timestamptz`, `p_expected_version int` | encerra (guarda I3 + trigger F3-04); evento `ENCERRADO` |
| `catalogo_cargo_criar` | `p_nome text`, `p_code text` | cria cargo (`code` único quando não nulo); evento `CRIADO` |
| `catalogo_cargo_renomear` | `p_job_role_id uuid`, `p_nome text`, `p_expected_version int` | rótulo; `code` imutável; evento `RENOMEADO` |
| `catalogo_cargo_status_alterar` | `p_job_role_id uuid`, `p_status text`, `p_expected_version int` | `active`/`disabled`; evento `ENCERRADO`/`REATIVADO` |
| `catalogo_senioridade_criar` | `p_nome text` | cria senioridade; evento `CRIADO` |
| `catalogo_senioridade_renomear` | `p_seniority_level_id uuid`, `p_nome text`, `p_expected_version int` | rótulo; evento `RENOMEADO` |
| `catalogo_senioridade_status_alterar` | `p_seniority_level_id uuid`, `p_status text`, `p_expected_version int` | `active`/`disabled`; evento |
| `estrutura_colegiado_definir` | `p_collaborator_id uuid` (avaliado), `p_member_collaborator_ids uuid[]`, `p_valid_from timestamptz` | fecha a versão vigente + cria nova versão com membros; evento `MEMBROS_ALTERADOS` |
| `estrutura_colegiado_encerrar` | `p_collaborator_id uuid`, `p_valid_to timestamptz` | fecha a versão vigente (⇒ ausência); evento `COLEGIADO_ENCERRADO` |

**Reuso (não recriar):** `estrutura_ocupacao_definir|encerrar`,
`estrutura_reporting_definir|encerrar`, `estrutura_responsabilidade_definir|encerrar`,
`registrar_sucessao_avaliador`, `colaborador_catalogo_bootstrap` (F5-07).

### 13.7 Catalogação obrigatória (guard do CI)

`supabase/validacao/02-validar-f5-08.sql` deve catalogar (padrão `[PASS]`/`[FAIL]`, como
`02-validar-f4-08.sql`):

1. RLS habilitada + policy own-tenant nas 8 tabelas e deny-by-default em `structure_events`;
2. privilégios de **`anon`/`authenticated`** (nenhum DML; apenas SELECT nas 8);
3. privilégios de **`service_role`** (DML pretendido; **ausência** de DELETE onde D8 exige);
4. `EXECUTE` das RPCs (só `service_role`; ausência para `anon`/`authenticated`);
5. presença das constraints/triggers/índices novos (I1/I2/I3; índice D20);
6. ausência de `SECURITY DEFINER` novo.

E o job `supabase-local` do `.github/workflows/ci.yml` passa a executar
`01-cenario-f5-08.sql`, `02-validar-f5-08.sql` e `03-validar-f5-08-cutover.sql` (hoje o CI só
executa validadores F4-08/F5-04 — §4.8(e)).

## 14. Concorrência e transações

### 14.1 Unidade transacional

Uma operação = uma RPC = **uma** transação. Dentro dela, nesta ordem:

1. `pg_advisory_xact_lock(hashtext(<chave estrutural> || p_organization_id))` (D14);
2. revalidação de ator/membership (`colaborador_ator_valido`) e de capability efetiva (§11.1);
3. revalidação de tenant da entidade-alvo por `(id, organization_id)`;
4. validação de idempotência (`operation_id`/`payload_hash` — §14.4);
5. checagem de `expected_version` (quando há linha existente);
6. guardas de domínio (I1–I5) e fechamento/abertura temporal;
7. gravação do evento em `structure_events` (§15);
8. retorno do identificador/versão resultante.

Qualquer falha ⇒ `ROLLBACK` integral (nenhum estado parcial; nenhum evento órfão).

### 14.2 Versão otimista obrigatória (D14)

`expected_version` é obrigatório em toda mutação de linha existente (renomear, encerrar,
alterar status, definir/alterar colegiado quando a versão vigente é fechada). A comparação e o
incremento de `version` ocorrem **na mesma transação**. Divergência ⇒ `CONFLICT` (409) e
**nenhuma** escrita — o cliente deve recarregar e reexibir (nunca mesclar silenciosamente).
Espelha F5-07 D13/§13.1 e é viável porque `version` já existe nas tabelas F3
(`20260907120000:88,158`; `20260907130000:127,205,298`; e nas demais).

### 14.3 Chave de advisory lock (D14) e lacuna G10

O trigger anti-ciclo da F3-04 documenta: "o caminho de escrita futuro deve manter o mesmo lock"
(`20260907140000:253-255`) e usa `hashtext('position_reporting_lines:' || organization_id)`
(`:266-268`). **A F5-08 adota exatamente essa chave** em todas as suas mutações estruturais
(unidades, parent periods, posições, reporting lines via UI, colegiado). Efeito: as mutações da
F5-08 serializam com a checagem anti-ciclo do banco e entre si, por organização.

**Divergência registrada (não silenciada):** as RPCs estruturais da F5-07 usam
`hashtext('f5_07_estrutura:' || organization_id)` (`20260913010000:864, 1031, 1179, 1344`) —
chave diferente. Consequência real: uma mutação estrutural da F5-07 (ex.: definir reporting
line) **não** serializa com o trigger anti-ciclo nem com as mutações da F5-08. Como corrigir
(alterar a F5-07 dentro desta atividade ou abrir manutenção própria) é **Q4**; a F5-08 não
altera código da F5-07 por decisão própria.

### 14.4 Idempotência de retry (D14)

Mesmo padrão da F5-07 (§13.5): `unique (organization_id, operation_id)` em `structure_events`.

| Situação | Resposta |
| --- | --- |
| `operation_id` novo | executa e grava o evento |
| `operation_id` repetido **e** `payload_hash` idêntico | não reaplica; devolve o mesmo resultado (`result_entity_id`/versão do evento) |
| `operation_id` repetido **e** `payload_hash` diferente | `CONFLICT`, sem escrita |

### 14.5 TOCTOU (pergunta 23)

A autorização **não** é reaproveitada entre a leitura e a mutação: identidade, membership,
capability, tenant da entidade e estado (`version`, vigência) são revalidados **na mesma
transação** que grava. Um ator que perca o acesso entre o clique e a execução recebe
`FORBIDDEN`; uma estrutura alterada por outro usuário no intervalo recebe `CONFLICT`.

### 14.6 Duas mutações simultâneas da mesma estrutura (pergunta 24)

| Cenário | Resultado |
| --- | --- |
| Duas renomeações da mesma unidade | serialização pelo lock; a segunda falha em `expected_version` ⇒ `CONFLICT` |
| Definição concorrente de parent da mesma unidade | lock + exclusion constraint; uma vence, a outra recebe `CONFLICT`/erro de exclusão traduzido |
| Criação concorrente de reporting line que **juntas** formariam ciclo | lock por organização **antes** da CTE recursiva ⇒ a segunda enxerga a primeira e é recusada (nenhum ciclo persistido) |
| Encerrar posição enquanto outra operação abre ocupação | lock + guarda I3: a que chegar depois falha (encerrar ⇒ `CONFLICT`; ocupar ⇒ validação de vigência da posição) |
| Duas versões concorrentes de colegiado para o mesmo avaliado | lock + exclusion por avaliado ⇒ apenas uma versão vigente |
| Duplicação por retry de rede | idempotência por `operation_id` (§14.4) |

### 14.7 Isolamento e deadlocks

Toda mutação estrutural toma **o mesmo** lock por organização, na mesma ordem, e não toma lock
de outras organizações — reduzindo deadlock a zero entre organizações e serializando as
operações da mesma organização (aceitável: estrutura é administração de baixa frequência).
Nenhuma RPC usa `SERIALIZABLE`; o nível padrão (`READ COMMITTED`) combinado com lock explícito
e `expected_version` é suficiente e consistente com F5-07.

## 15. Auditoria e autoria

### 15.1 Modelo (D13)

Toda mutação da F5-08 grava **um ou mais** eventos em `structure_events` na **mesma
transação**, com `organization_id`, `entity_type`, `entity_id`, `event_type`, `effective_date`,
`reason`, `before_value`/`after_value` normalizados, `payload_hash`, `result_entity_id`,
`actor_user_profile_id`, `actor_membership_id`, `operation_id` e `created_at` server-side.

Cobre o mínimo exigido pelo enunciado: `organization_id` ✅; entidade ✅; `entity_id` ✅; tipo de
operação ✅; ator soberano ✅; timestamp server-side ✅ (`created_at`); estado anterior relevante
✅ (`before_value`); estado novo relevante/payload normalizado ✅ (`after_value`/`payload_hash`);
correlação/metadata ✅ (`operation_id`).

### 15.2 `before_value`/`after_value` — o que entra

Somente o **estado estrutural relevante** (`name`, `code`, `status`, `unit_id`, `job_role_id`,
`seniority_level_id`, `parent_unit_id`, `valid_from`, `valid_to`, `version`, ids de membros do
colegiado). **Nunca** dados pessoais (nomes de pessoas, matrícula, e-mail) — apenas UUIDs de
colaborador quando necessário. `payload` **nunca** é autoridade de tenant nem de ator
(F5-07 §12.2; F5-06 D26): a RPC não lê `before_value`/`after_value` para decidir nada.

### 15.3 Imutabilidade garantida no banco

Trigger de exceção em `UPDATE`/`DELETE` (mesmo padrão de `collaborator_events`,
`20260913000000:320-333`) + `revoke update, delete` de `service_role` + RLS habilitada sem
policy (deny-by-default para `anon`/`authenticated`). Autoria exige conta: o evento é rejeitado
se `actor_user_profile_id`/`actor_membership_id` não corresponderem a perfil+membership ativos
(coerência verificada na RPC; `NOT NULL` e FK registram o fato).

### 15.4 O que a trilha responde

Quem criou/renomeou/encerrou/reativou cada unidade, posição, cargo, senioridade e colegiado;
quando (data de negócio e timestamp do servidor); com que motivo; qual era o estado anterior;
qual operação (`operation_id`) o produziu — incluindo, para o colegiado, a composição anterior
e a nova. **Não** substitui `collaborator_events` (F5-07) nem `evaluation_events` (F5-06):
cada trilha cobre o seu agregado, e a correlação entre elas se dá por `operation_id`.

### 15.5 Reuso de mecanismos existentes

- `privilege_mutation_audit` (F5-04): **não** se aplica (é trilha de privilégio).
- `collaborator_events` (F5-07): permanece com o papel dela; as operações de **ocupação** e
  **reporting line** já a alimentam e continuam alimentando (a F5-08 **reusa** as operações
  existentes em vez de criar caminho paralelo).
- Nenhum segundo padrão de auditoria é criado **sem necessidade**: `structure_events` é o
  primeiro e único padrão para entidades que **não** são ancoradas em colaborador/posição
  (§8.3 justifica por que estender as existentes quebraria contrato fechado).

## 16. Impacto nos scopes/hierarquia

### 16.1 Nenhuma mudança de contrato nos resolvers (D12)

`organizacao_resolver_responsavel_posicao`, `organizacao_resolver_gestor_direto`,
`organizacao_resolver_subordinados_diretos`, `organizacao_resolver_descendentes`,
`organizacao_resolver_cadeia`, `organizacao_resolver_escopo_posicoes`,
`organizacao_resolver_escopo_unidades` (F3-07) e `resolver_alvos_escopo` (F4-02) **não são
alterados**. A F5-08 apenas passa a poder **alimentar** corretamente as tabelas que eles leem —
o que hoje é impossível pelo produto (G1–G3).

### 16.2 Efeito por scope (pergunta 19)

| Scope | Efeito |
| --- | --- |
| **SELF** | nenhum |
| **DIRECT_REPORTS** | nenhum no contrato; passa a refletir reporting lines criadas/encerradas pela UI. Encerrar posição com reporting line vigente é recusado (trigger F3-04), preservando a consistência do resolver |
| **DESCENDANTS** | nenhum no contrato; ganha o índice de `parent_unit_id` (D20) e a garantia de ausência de ciclo entre unidades (I1) |
| **ORGANIZATIONAL_UNIT** | nenhum no contrato (continua "somente a unidade atribuída, sem subunidades", F4-02 D5); encerrar unidade com posição vigente passa a ser impossível (I2), evitando alvo de unidade "morta" |
| **ASSIGNED** | nenhum: continua **derivado** de F3-08/09, nunca copiado (F4-02 D6). A F5-08 é quem passa a administrar a configuração de colegiado que o alimenta (via snapshot → `cycle_evaluation_responsibilities`) |
| **ORGANIZATION / CUSTOM** | nenhum |

### 16.3 Impactos estruturais garantidos (e por que são seguros)

1. **Encerrar posição** não apaga nem altera histórico: ocupações e reporting lines passadas
   continuam resolvíveis por `position_id`; a posição vaga continua sendo **alvo estrutural sem
   pessoa** (F4-02 §7 `:247-266`).
2. **Desativar catálogo** não invalida posições existentes (nenhuma FK condicionada a
   `status`); apenas impede referência **nova** (D17). `funcao`/`cargo` de posições existentes
   continuam resolvidos pela projeção (F5-07 §6.6).
3. **Colegiado** alterado não recalcula snapshots de ciclos passados (F3-08 D9/D10) nem cria
   hierarquia (F3-08 `:6-7`; F4-02 §19 inv.7).
4. **Nenhuma capability/scope novo** ⇒ nenhum `can()`/`authorize()` do cliente muda de
   resultado por causa da F5-08, exceto os que hoje dependem de estrutura local (§18/§19).

### 16.4 Regressão obrigatória dos gates F4/F5

| Gate | Como a F5-08 pode quebrá-lo | Prova exigida |
| --- | --- | --- |
| **F4-08/RLS** | novo grant, policy permissiva, tabela sem RLS | `02-validar-f4-08.sql` + `03-validar-f4-08-mutacoes.sql` + validator novo (§13.7) |
| **F4-04/hierarquia** | derivar hierarquia de cargo/função | grep de CI (`docs/F4-04-desenho-tecnico.md:386-398`) + testes de `src/authorization/providers/structure.ts` |
| **F4-09/domínios** | introduzir decisão de domínio por estrutura textual | testes existentes de `policyEngine`/domínios |
| **F5-04** | enfraquecer `usuario_eh_administrador` ou as RPCs administrativas | `02-validar-f5-04.sql` inalterado |
| **F5-05** | alterar ActorContext/ResourceContext | testes de `resourceContextReal`/`authorizationPolicy` |
| **F5-06** | alterar schema/RLS de avaliação | `02-validar-f5-06.sql`, `03-validar-f5-06-cutover.sql` |
| **F5-07** | alterar contrato/projeção/eventos de colaborador | `02-validar-f5-07.sql`, `03-validar-f5-07-cutover.sql`, `colaboradoresContratoRpc.test.ts` |

## 17. Backend/server-side boundary

### 17.1 Onde fica a fronteira (D9 — pergunta 8)

**Estender a Edge Function `colaboradores`** (`supabase/functions/colaboradores/`), que já é a
fronteira soberana da F5-07 e já hospeda 8 operações estruturais/catalogais
(`index.ts:201-293`). Nenhuma Edge/Function nova.

Justificativa: (a) mesma identidade, mesmo plano administrativo, mesmo `service_role`, mesma
taxonomia de erro — uma segunda fronteira duplicaria autenticação, dispatch e testes;
(b) as operações de ocupação/reporting/responsabilidade/sucessão **já vivem** nessa Edge e são
exatamente as que a UI de estrutura passa a chamar; (c) `.ai/architecture-rules.md` pede não
duplicar regras.

### 17.2 Arquivos tocados (implementação futura)

| Arquivo | Mudança |
| --- | --- |
| `src/infrastructure/supabase/colaboradores/contrato.ts` | novas operações em `OperacaoColaborador` + entradas em `DEFINICAO_POR_OPERACAO` (gate `administrativo`, capability `org.structure.manage`/`org.catalog.manage`) + validação de forma |
| `supabase/functions/colaboradores/index.ts` | dispatch para as RPCs novas (`admin.rpc(...)`) |
| `supabase/functions/colaboradores/core.ts` | reuso de `avaliarGateAdministrativo` e `projetarResultado` (sem novo gate) |
| `src/infrastructure/supabase/colaboradores/repositorioColaboradores.ts` | chamadas das operações novas |
| `src/services/colaboradoresSoberanos/*` | porta/serviço com as operações novas (+ consumidores de UI) |

### 17.3 Taxonomia de erro (contrato fechado F5-06/F5-07)

Reusa `CodigoPublico` (`contrato.ts:44-51`): `FORBIDDEN` (capability ausente, tenant do ator
inválido, guarda de autoridade), `NOT_FOUND` (entidade inexistente **no tenant**; nunca revela
existência em outro tenant), `CONFLICT` (`expected_version` divergente, `operation_id` com
payload diferente, guarda de integridade violada — ex.: encerrar unidade com posição vigente),
`INVALID_INPUT` (forma/vigência inválidas), `INTERNAL` (falha inesperada, sem vazar SQL).
Nenhuma mensagem crua do banco chega ao cliente.

## 18. Frontend e cutover

### 18.1 Telas atuais que criam/editam/listam/selecionam/relacionam (perguntas 20 e 21)

| Tela/arquivo | Hoje | F5-08 |
| --- | --- | --- |
| `NovoColaboradorPage.tsx` | estrutura removida; bloco "Estrutura organizacional (F5-08)" (`:249`) com aviso | passa a oferecer **seleções soberanas** (unidade, cargo, senioridade, posição/gestor) que criam ocupação/reporting line via porta soberana, sob demanda e com confirmação |
| `EditarColaboradorPage.tsx` | Unidade/Cargo/Senioridade/Gestor **read-only** (`:648-681`), `AVISO_SEM_ALOCACAO:61-63` | edição de alocação por operações soberanas (`colaborador.ocupacao.*`, `estrutura.reporting.*`), com motivo obrigatório e erro do servidor exibido |
| `ColaboradoresPage.tsx` | `possuiAlocacao:95-105`, fallback "Sem alocação" (`:474`), `AVISO_ESTRUTURA:67-68` | inalterado no essencial; passa a refletir alocação criada pela administração |
| `ColaboradorDetalhePage.tsx` | "Alocação vigente — derivada da ocupação soberana" (`:604-628`) | passa a exibir também a cadeia (gestor direto) e o colegiado vigente |
| **Novas telas (obrigatórias)** | não existem | (1) **Unidades**: lista + criar + renomear + encerrar + definir/alterar pai (árvore); (2) **Posições**: lista por unidade + criar + encerrar + ver ocupante + definir reporting line; (3) **Catálogos**: cargos e senioridades (criar, renomear, ativar/desativar); (4) **Colegiado**: por colaborador avaliado (definir membros, encerrar, ver versões) |
| **Alocação do colaborador** | portas prontas sem UI (`acessoColaboradoresSoberanos.ts:211-332`) | ganha consumidor de UI (fronteira de entrega: Q5) |
| `InicioPage.tsx` | roteia por leitura soberana, nunca `funcao` | inalterado |

### 18.2 Regras de UI inegociáveis

1. **Nenhuma escrita estrutural em `localStorage`** em produção (o storage local vira cache
   não soberano ou é removido — §19).
2. **IDs canônicos**: toda seleção envia `unit_id`/`job_role_id`/`seniority_level_id`/
   `position_id`/`collaborator_id`. Texto livre de cargo/área/gestor **desaparece** dos fluxos
   de estrutura (o texto legado continua **legível** via `code`/`name` da projeção).
3. **Sem optimistic update que represente estado rejeitado**: a tela só mostra a mudança depois
   do `ok` da RPC; em erro, a UI **não** altera o estado exibido e mostra o código público
   (`FORBIDDEN`/`NOT_FOUND`/`CONFLICT`/`INVALID_INPUT`) com mensagem própria.
4. **Invalidação/recarga após mutação**: recarregar a entidade e as **dependentes** (mudar
   parent de unidade ⇒ recarregar a árvore e os descendentes; encerrar posição ⇒ recarregar a
   cadeia de reporting; alterar colegiado ⇒ recarregar o colegiado vigente do avaliado).
   Nenhum cache de estrutura sobrevive à mutação bem-sucedida.
5. **`can()` apenas UX**: botões de administração aparecem/ocultam por capacidades, mas a
   decisão real é sempre do servidor; a UI deve tratar `FORBIDDEN` mesmo quando o botão estava
   visível (revogação entre leitura e clique).
6. **Sem fallback silencioso**: ausência de estrutura soberana é exibida como
   "sem alocação"/"sem estrutura cadastrada", nunca preenchida por heurística local.
7. **Motivo obrigatório** nas mutações que o exigem (encerramentos, alterações de rótulo,
   status e colegiado), coletado na UI e enviado no payload.

### 18.3 Ordem de cutover sugerida

1. Catálogos (menor risco; já existe bootstrap) → 2. Unidades + hierarquia → 3. Posições →
4. Alocação do colaborador (ocupação/reporting line) → 5. Colegiado → 6. Remoção dos caminhos
locais (§19) → 7. Remoção dos avisos "F5-08" das telas de colaborador.

Cada passo mantém o produto funcional: enquanto uma tela não está cortada, ela continua
**read-only** (não volta a escrever localmente).

## 19. Estratégia para legado/localStorage

### 19.1 O que **não** pode permanecer (autoridade estrutural)

| Caminho | Ação |
| --- | --- |
| `historicoOrganizacionalStorage` — reconstrução de estrutura e promoção de `respondePara` a gestor (`:248-341`) | **deixa de ser fonte estrutural**: no máximo leitura de exibição legada, sem efeito sobre hierarquia/autorização; escrita local bloqueada |
| `mundoFuncional.ts` — bindings GESTAO/COORDENACAO/COLEGIADO por estrutura local (`:129-232`) | derivação local **não** é autoridade: o mundo funcional passa a vir da projeção soberana; sem dado soberano ⇒ vazio (fail-closed), nunca inventado |
| `authorizationPolicy.ts:53-66` — fallback `getColaboradores()` | fallback removido; sem projeção soberana ⇒ conjunto vazio |
| `localWorld.ts` (`organization_id` sintético, `isMembershipActive: () => true`) | mantido **apenas** para DEV/teste, atrás do gate de modo DEV já existente; nunca em produção |
| `src/data/colaboradores.ts` (seed DEV com estrutura embutida) | continua permitido como **dado fictício de DEV**, explicitamente não soberano |
| `progressoAvaliacao.ts`/`cicloEquipeService.ts`/`metaStorage.ts` — decisão por `funcao`/`gestorDireto` local (`progressoAvaliacao.ts:61,92-102`; `cicloEquipeService.ts:115-185,221-321`) | decisões de **elegibilidade/papel** passam a usar a estrutura soberana (projeção/resolvers); `funcao` textual não decide hierarquia (F4-02 §19 inv.2/3) |
| `src/data/evaluationTeam.ts` | código morto: remover na implementação (finding) |

### 19.2 O que **pode** permanecer como cache não soberano (pergunta 22)

- Cache **em memória** da sessão (lista de unidades/posições/catálogos para preencher
  seletores), sempre invalidado após mutação e nunca usado para decidir autoridade.
- Dados de **DEV** (seeds/test-data), atrás do gate de modo DEV.
- Preferências locais **sem** semântica estrutural (filtros de tela, colunas visíveis).
- `resetBaseDesenvolvimento` pode permanecer, ajustado ao novo conjunto de chaves; não pode
  apagar estrutura soberana.

### 19.3 Proibições explícitas

- Nenhum **dual-write** estrutura↔local (o enunciado proíbe dual-write desnecessário).
- Nenhuma promoção de texto (`respondePara`, "coordenador X") a relação estrutural.
- Nenhuma matrícula como identidade funcional (F5-07 D3/D4).
- Nenhuma estrutura sintética criada no cliente para "destravar" a UI — sem estrutura soberana
  a UI mostra ausência e a operação que exige posição é recusada (F5-07 §14.6).

## 20. Estratégia de migrations

### 20.1 Composição (D20)

| Migration / arquivo | Conteúdo |
| --- | --- |
| `20260914000000_f5_08_structure_sovereign.sql` | `structure_events` (tabela + índices + trigger append-only + RLS deny-by-default); triggers I1/I2/I3; índice D20; normalização de privilégios de `service_role` (§13.3) |
| `20260914010000_f5_08_structure_rpc.sql` | 15 RPCs (`SECURITY INVOKER`) + grants de `EXECUTE` a `service_role` |
| `supabase/validacao/01-cenario-f5-08.sql` | cenário fictício multi-tenant (2 organizações), com ator admin, ator sem capability e estrutura de exemplo |
| `supabase/validacao/02-validar-f5-08.sql` | schema/constraints/triggers/índices/RLS/grants/funções + comportamento + negativos (padrão `[PASS]`/`[FAIL]`) |
| `supabase/validacao/03-validar-f5-08-cutover.sql` | cross-tenant, capability negada, concorrência, idempotência, ciclo, encerramento com estrutura vigente, histórico preservado |
| `.github/workflows/ci.yml` | passa a executar os três validadores no job `supabase-local` |

### 20.2 Regras

1. **Somente aditivo**: nenhuma migration aplicada é reescrita, nenhuma coluna removida,
   nenhum dado migrado.
2. **Sem alteração de contrato fechado**: nenhuma tabela F3/F5-07 tem CHECK/FK/índice
   relaxado; `collaborator_events`, `evaluation_events` e `privilege_mutation_audit` intocados.
3. **Idempotência de DDL**: `create table if not exists`/`drop trigger if exists` seguindo o
   estilo das migrations do repositório; `db reset` reproduz o estado do zero.
4. **Ordem**: DDL antes de RPC (as RPCs referenciam `structure_events` e as funções de trigger).
5. **Rollback**: como o desenho é aditivo, reverter = remover as duas migrations e restaurar os
   grants anteriores (documentado no PR); não há perda de dados históricos porque nenhuma
   tabela existente é alterada.
6. **Sem dados reais**: cenários e seeds apenas fictícios.
7. **Ciclos preexistentes**: o trigger anti-ciclo é criado depois de verificar que os dados
   existentes (DEV/local) não contêm ciclos; se houver, a validação falha explicitamente (não
   corrigir silenciosamente).

## 21. Matriz de operações

Convenções: **gate** é sempre administrativo; `motivo` é obrigatório em todas;
`expected_version` é obrigatório onde indicado.

### 21.1 Operações novas

| Operação (Edge) | Entidade | Tipo | Payload (além de `organizationId`/`operationId`/`motivo`) | Pré-condições | Efeito | Erros |
| --- | --- | --- | --- | --- | --- | --- |
| `estrutura.unidade.criar` | `organizational_units` | criar | `nome`, `validFrom` | nome único na org (trim, não vazio); ator com `org.structure.manage` | insere unidade vigente a partir de `validFrom` | `FORBIDDEN`, `INVALID_INPUT`, `CONFLICT` (nome já usado) |
| `estrutura.unidade.renomear` | idem | editar rótulo | `unidadeId`, `nome`, `expectedVersion` | unidade **vigente** na data; versão confere; D4 | `UPDATE name` + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `estrutura.unidade.encerrar` | idem | encerrar | `unidadeId`, `validTo`, `expectedVersion` | vigente; `validTo > validFrom`; **sem** posição vigente; **sem** período parent vigente como filha (I2) | `UPDATE valid_to` + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `estrutura.unidade.parent.definir` | `organizational_unit_parent_periods` | criar/alterar relação | `unidadeId`, `parentUnitId` (null = raiz), `validFrom` | ambos vigentes; sem ciclo (I1); sem sobreposição (exclusion) | fecha período vigente + abre novo + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `estrutura.unidade.parent.encerrar` | idem | encerrar relação | `unidadeId`, `validTo` | existe período vigente | fecha + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `estrutura.posicao.criar` | `organizational_positions` | criar | `unidadeId`, `jobRoleId`, `seniorityLevelId?`, `validFrom` | unidade vigente; cargo/senioridade **ativos** e da mesma org (I4/I5) | insere posição + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `estrutura.posicao.encerrar` | idem | encerrar | `posicaoId`, `validTo`, `expectedVersion` | vigente; **sem** ocupação vigente (I3); **sem** reporting line vigente (trigger F3-04) | `UPDATE valid_to` + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `catalogo.cargo.criar` | `job_roles` | criar | `nome`, `code?` | nome único; `code` único quando não nulo | insere `active` + evento | `FORBIDDEN`, `CONFLICT`, `INVALID_INPUT` |
| `catalogo.cargo.renomear` | idem | editar rótulo | `jobRoleId`, `nome`, `expectedVersion` | item existe; `code` **imutável** | `UPDATE name` + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT` |
| `catalogo.cargo.status.alterar` | idem | ativar/inativar | `jobRoleId`, `status`, `expectedVersion` | transição válida (`active`↔`disabled`) | `UPDATE status` + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `catalogo.senioridade.criar` | `seniority_levels` | criar | `nome` | nome único | insere `active` + evento | `FORBIDDEN`, `CONFLICT`, `INVALID_INPUT` |
| `catalogo.senioridade.renomear` | idem | editar rótulo | `seniorityLevelId`, `nome`, `expectedVersion` | item existe | `UPDATE name` + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT` |
| `catalogo.senioridade.status.alterar` | idem | ativar/inativar | `seniorityLevelId`, `status`, `expectedVersion` | transição válida | `UPDATE status` + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `estrutura.colegiado.definir` | `collegiate_configurations` + `_members` | criar/alterar versão | `collaboratorId` (avaliado), `memberCollaboratorIds[]`, `validFrom` | avaliado e membros existem na org; avaliado **não** é membro; sem duplicados; cardinalidade 0..N (F3-08 D3) | fecha versão vigente + cria nova + membros + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `INVALID_INPUT` |
| `estrutura.colegiado.encerrar` | idem | encerrar | `collaboratorId`, `validTo` | existe versão vigente | fecha versão vigente + evento | `FORBIDDEN`, `NOT_FOUND`, `CONFLICT` |

### 21.2 Operações reusadas da F5-07 (sem duplicação) + UI nova

| Operação existente | Capability | Papel na F5-08 |
| --- | --- | --- |
| `colaborador.ocupacao.definir` / `.encerrar` | `org.structure.manage` | UI de alocação do colaborador (Q5) |
| `estrutura.reporting.definir` / `.encerrar` | `org.structure.manage` | UI de reporting line (tela de Posições) |
| `estrutura.responsabilidade.definir` / `.encerrar` | `org.structure.manage` | UI de responsável temporário |
| `estrutura.sucessao.registrar` | `org.structure.manage` | UI de sucessão |
| `colaborador.catalogo.bootstrap` | `org.catalog.manage` | permanece (idempotente; nunca renomeia) |

### 21.3 Operações **não** criadas (e por quê)

| Operação cogitada | Decisão |
| --- | --- |
| `estrutura.posicao.reatribuir` (mover posição de unidade/cargo/senioridade) | **não** — D5/Q2 |
| `estrutura.unidade.reabrir` / `estrutura.posicao.reabrir` | **não** — Q1 |
| qualquer `*.excluir` (DELETE físico) | **proibido** — D8 |
| RPC de **leitura** administrativa (listar unidades/posições/catálogos) | **não** — leitura é RLS F4-08 (D16) |
| operação de snapshot de colegiado por ciclo | F5-09 |

## 22. Matriz de autorização

### 22.1 Operação × capability × camada de enforcement

| Operação | Capability | Edge (1ª checagem) | Banco (revalidação na transação) | RLS |
| --- | --- | --- | --- | --- |
| `estrutura.unidade.*` (5) | `org.structure.manage` | `avaliarGateAdministrativo` (`core.ts:472-492`) | `colaborador_ator_valido` + capability efetiva + tenant da entidade | escrita bloqueada; leitura own-tenant |
| `estrutura.posicao.*` (2) | `org.structure.manage` | idem | idem | idem |
| `catalogo.cargo.*` (3) | `org.catalog.manage` | idem | idem | idem |
| `catalogo.senioridade.*` (3) | `org.catalog.manage` | idem | idem | idem |
| `estrutura.colegiado.*` (2) | `org.structure.manage` (D11) | idem | idem | idem |
| `colaborador.ocupacao.*`, `estrutura.reporting.*`, `estrutura.responsabilidade.*`, `estrutura.sucessao.registrar` (F5-07) | `org.structure.manage` | idem | `colaborador_ator_valido` (padrão F5-07) | idem |
| `colaborador.catalogo.bootstrap` (F5-07) | `org.catalog.manage` | idem | `colaborador_ator_valido` | idem |
| Leitura de estrutura/catálogo (UI) | **nenhuma capability** (D16) | — | — | policy own-tenant F4-08 |

### 22.2 Matriz de privilégio × papel

| Papel | SELECT | INSERT/UPDATE | DELETE | EXECUTE RPC |
| --- | --- | --- | --- | --- |
| `anon` | — | — | — | — |
| `authenticated` (membro da org) | ✅ own-tenant (F4-08) | ❌ | ❌ | ❌ |
| `service_role` (executor da fronteira) | ✅ | ✅ nas tabelas administradas (`structure_events` é append-only) | ❌ (`revoke delete`) | ✅ |
| ator com a capability exigida | via `authenticated` | via RPC, com auditoria | ❌ | indireto (Edge) |
| ator sem a capability | via `authenticated` | ❌ (`FORBIDDEN`) | ❌ | ❌ |

### 22.3 `can()` do cliente

Nenhuma regra de autorização é duplicada em página/componente: a UI usa as capabilities que já
existem no vocabulário central para **ocultar** ações administrativas (UX) e trata o erro do
servidor como verdade. Nenhuma capability nova é adicionada ao vocabulário TS/SQL.

## 23. Testes

### 23.1 Validadores SQL (padrão do repositório)

| Arquivo | Conteúdo |
| --- | --- |
| `01-cenario-f5-08.sql` | 2 organizações fictícias; ator com `org.structure.manage`+`org.catalog.manage`; ator sem as capabilities; unidade/posição/cargo/senioridade/colegiado de exemplo; ocupação e reporting line |
| `02-validar-f5-08.sql` | schema/constraints/triggers/índices/RLS/grants/EXECUTE + comportamento + negativos (`[PASS]`/`[FAIL]`) |
| `03-validar-f5-08-cutover.sql` | cross-tenant, capability negada, concorrência, idempotência, ciclos, encerramento com estrutura vigente, histórico preservado |

### 23.2 Matriz mínima obrigatória (A–H do enunciado)

| Grupo | Casos obrigatórios |
| --- | --- |
| **A. Tenant** | SELECT isolado (org A não vê org B); mutação isolada; ID válido de outro tenant ⇒ `NOT_FOUND`/`FORBIDDEN` (nunca sucesso, nunca revelar existência) |
| **B. Capability** | ator sem `org.structure.manage` ⇒ `FORBIDDEN` em todas as operações de estrutura; sem `org.catalog.manage` ⇒ `FORBIDDEN` em catálogo; revogação passa a valer na operação seguinte; capability errada (ex.: `org.catalog.manage` em criação de unidade) **não** substitui |
| **C. RLS/grants** | `authenticated` não insere/atualiza/deleta tabela diretamente; `EXECUTE` das RPCs negado a `anon`/`authenticated`; `service_role` não decide autorização (RPC com ator sem capability ⇒ recusa) |
| **D. Integridade** | ciclo de unidade (direto e em 3 níveis) recusado; ciclo de reporting line recusado; referência cross-tenant recusada; `valid_to <= valid_from` recusado; sobreposição de período parent/reporting/colegiado recusada; encerrar unidade com posição vigente recusado; encerrar posição com ocupação vigente recusada; posição com catálogo inativo recusada; auto-relação recusada |
| **E. Concorrência** | duas renomeações concorrentes ⇒ uma `CONFLICT`; criação concorrente de reporting line que formaria ciclo ⇒ uma recusada, nenhum ciclo persistido; encerramento + ocupação concorrentes ⇒ estado final válido; retry com mesmo `operation_id` ⇒ sem duplicação; mesmo `operation_id` com payload diferente ⇒ `CONFLICT` |
| **F. Histórico** | encerrar/renomear hoje não altera `collaborator_events` antigos, snapshots de ciclo nem avaliações; posição encerrada continua resolvível por `occupations`/reporting lines antigas; desativar catálogo não invalida posições existentes |
| **G. Regressão** | F4-08 (RLS + mutações), F4-04 (hierarquia/allowlist), F4-09 (domínios), F5-04, F5-05, F5-06, F5-07 — comandos em §24.3 |
| **H. Frontend/cutover** | produção não escreve estrutura em `localStorage`; sem fallback silencioso; seleções usam IDs canônicos; erro de autorização/integridade exibido e **não** mascarado pela UI |

### 23.3 Testes TypeScript

- `contrato.ts`: forma das operações novas (payload obrigatório, `expectedVersion`, motivo,
  vigência), rejeição de operação desconhecida, mapeamento gate/capability (espelhando
  `colaboradoresContratoRpc.test.ts:639-654`).
- Edge: `FORBIDDEN` quando a capability efetiva não contém a exigida (mock do resolvedor);
  `CONFLICT`/`NOT_FOUND`/`INVALID_INPUT` propagados sem vazar SQL.
- Repositório/porta: chamadas com `operationId` e sem escrita local; atualização da projeção
  após mutação.
- Telas: testes de render garantindo (i) ausência de escrita em `localStorage` nos fluxos de
  estrutura, (ii) exibição do erro do servidor, (iii) uso de IDs canônicos, (iv) remoção dos
  avisos "F5-08" quando o fluxo existir.
- Autorização do cliente: `mundoFuncional`/`authorizationPolicy` sem fallback local
  (sem projeção soberana ⇒ vazio), no padrão dos testes de `providers/*`.

### 23.4 Gates de CI

`.github/workflows/ci.yml` — job `quality`: `npm test`, `npm run build`, `npm run lint`,
`git diff --check`. Job `supabase-local`: `db start` + `db reset` + validadores F4-08, F5-04
**e os três novos da F5-08** (§13.7). Gates locais adicionais: `npx tsc -b tsconfig.app.json`
(o Vitest não checa tipos) e execução dos validadores F5-06/F5-07 para regressão.

## 24. Critérios de aceite

### 24.1 Desta atividade (o desenho)

1. Documento com as 29 seções exigidas + rastreabilidade das 28 questões centrais (§30).
2. Decisões dedutíveis registradas como D1–D20 com evidência (arquivo:linha).
3. Questões não dedutíveis registradas como Q1–Q5 com contexto, alternativas, recomendação,
   impacto e seções dependentes.
4. Nenhuma reabertura de D19/D20 (declarado em §11.6/D19).
5. Divergências documentação × código registradas (§4.8); findings fora de escopo isolados
   (§25.4).
6. `git diff --check` limpo; diff restrito a documentação.

### 24.2 Da futura implementação (fechamento da F5-08)

1. Operações soberanas para **todas** as entidades do §5.1, com as guardas I1–I5.
2. `structure_events` append-only, gravada na mesma transação, com autoria soberana.
3. RLS/grants conforme §13.3/§13.4, com `service_role` sem `DELETE` onde D8 exige.
4. Nenhuma policy de escrita nova; `authenticated` continua sem DML.
5. Zero `SECURITY DEFINER` novo; todas as RPCs `SECURITY INVOKER` com `search_path` fixo.
6. Nenhuma capability nova; allowlist `[]` intacta; `authorizationPolicy`/`mundoFuncional` sem
   autoridade estrutural local.
7. Telas de administração funcionais para as 4 áreas do §18.1 + alocação do colaborador.
8. Nenhuma escrita estrutural em `localStorage` em produção; nenhum fallback silencioso.
9. Validadores F5-08 verdes **e** executados no CI; regressão F4-08/F5-04/F5-06/F5-07 verde.
10. `npm test`, `npm run build`, `npm run lint`, `git diff --check` verdes.

### 24.3 Comandos de validação

```bash
npm test
npm run build
npm run lint
npx tsc -b tsconfig.app.json
git diff --check
npx --yes supabase@2.116.0 db start --yes
npx --yes supabase@2.116.0 db reset --local --yes
# validadores (F4-08, F5-04, F5-06, F5-07, F5-08) via docker exec psql -v ON_ERROR_STOP=1
```

## 25. Riscos

### 25.1 Riscos do desenho (com mitigação)

| # | Risco | Severidade | Mitigação |
| --- | --- | --- | --- |
| R1 | Modelo "linha única com janela" não permitir reabrir unidade/posição | Média | Comportamento explícito na UI; reabrir não é expressável hoje ⇒ Q1; ausência de reescrita de passado |
| R2 | Reatribuir posição exigir nova posição ⇒ histórico com várias posições | Média | D5/Q2; ocupações/reporting lines históricas preservadas |
| R3 | Custo do trigger anti-ciclo de unidades em árvores grandes | Baixa | CTE recursiva com índice novo (D20) + lock por organização; profundidade real pequena |
| R4 | Serialização por organização reduz throughput de administração | Baixa | Estrutura é operação de baixa frequência; leitura não é serializada |
| R5 | Chave de advisory lock divergente da F5-07 (G10) | **Alta** (integridade) | F5-08 adota a chave da F3-04 (D14); Q4 resolve a F5-07 |
| R6 | Guarda I3 pode impedir operação legítima (encerrar posição recém-desocupada) | Baixa | Apenas ocupação **vigente** na data bloqueia; encerrar a ocupação primeiro é o fluxo previsto |
| R7 | Renomear rótulo muda exibição histórica (`area`/`cargo`) | Média | Aceito por contrato (rótulo ≠ identidade; snapshots não copiam nomes); trilha guarda o valor anterior; aviso na UI |
| R8 | Default privileges de `service_role` reintroduzirem DML amplo | Média | `revoke all` + `grant` explícito na migration + catalogação no guard do CI (§13.7) |
| R9 | Bootstrap de catálogo (F5-07) e CRUD novo divergirem | Baixa | Bootstrap **nunca renomeia** (`20260913010000:1762-1792`); `code` imutável no CRUD (D4) |
| R10 | Cutover incompleto deixar autoridade estrutural local viva | **Alta** (segurança) | §18/§19 com checklist; testes H; remoção dos fallbacks é critério de aceite (§24.2 item 6) |

### 25.2 Riscos de segurança residuais

1. `service_role` continua sendo executor poderoso: mitigado por grants mínimos, revalidação de
   ator/capability no banco (§11.1) e auditoria.
2. Estrutura é **legível** por qualquer membro ativo da organização (F4-08): aceito por
   contrato; a F5-08 não amplia nem reduz isso.
3. `localWorld`/seeds DEV permanecem no bundle: mitigado pelo gate de modo DEV existente e por
   teste que garanta que produção não escreve estrutura localmente.

### 25.3 Riscos de conformidade com a F5-07

Nenhuma alteração é proposta em `collaborators`, `collaborator_events`, `collaborador_visao_*`,
nos resolvers ou no contrato de operações existente. A divergência de lock (§4.7 G10) é o único
ponto que toca código da F5-07 — e está isolado em Q4.

### 25.4 Findings fora de escopo (registrados; **não** corrigidos nesta atividade)

| # | Finding | Recomendação |
| --- | --- | --- |
| F1 | `supabase/functions/avaliacoes/index.ts:8` importa `catalogoCapacidades.ts` inexistente (risco preexistente citado no enunciado) | Issue/manutenção própria; **não** bloqueia o desenho (a F5-08 não toca a Edge `avaliacoes`) |
| F2 | Default privileges do Supabase dão DML amplo a `service_role`; `02-validar-f4-08.sql` audita apenas `anon`/`authenticated` | Corrigido **no escopo da F5-08** para as suas tabelas (§13.7); demais tabelas em hardening próprio |
| F3 | Assimetria de grants da F5-07 (`seniority_levels` com `select, insert`; `job_roles` com `select, insert, update`), mascarada por default privileges | F5-08 normaliza no seu escopo; origem (F5-07) registrada como dívida |
| F4 | Chave de advisory lock divergente (G10) | Q4 |
| F5 | `core.ts:611-619` — `default: return "org.structure.manage"` no mapa capability↔operação | Fail-closed por construção (trocar `default` por exceção) em manutenção própria; hoje inócuo (`contrato.ts:510` rejeita operação desconhecida) |
| F6 | `docs/F3-02`, `docs/F3-08`, `docs/F3-09` inexistentes em `docs/` embora citados como contratos fechados | Recuperar/arquivar os contratos ou ajustar citações; não bloqueia (migrations são normativas) |
| F7 | `docs/F4-07-desenho-tecnico.md:263-265` desatualizado (capabilities "só no catálogo SQL") | Atualização documental própria |
| F8 | F5-07 §6.4 não lista `position_id`/`payload_hash`/`result_entity_id` de `collaborator_events` (§4.8 c) | Correção documental própria |
| F9 | `src/data/evaluationTeam.ts` — código morto | Remover na implementação da F5-08 (já no escopo de limpeza, §19.1) |
| F10 | CI executa apenas validadores F4-08/F5-04; validadores F5-06/F5-07 existem e não rodam | F5-08 liga os seus; ligar os demais é hardening do CI |
| F11 | `expectativaCargoStorage` mantém autoridade local por `funcao`×`senioridade` (domínio settings) | Fora do escopo; registrar para a atividade de settings |

## 26. Dependências

### 26.1 Dependências satisfeitas

- **F5-07** concluída (`main` = `7137f1f`): fronteira server-side, projeção soberana, trilha
  append-only, plano administrativo, mapa operação→capability, 8 operações estruturais prontas.
- **F5-04** concluída: plano administrativo, `usuario_eh_administrador`, catálogo de
  capabilities, `resolver_capabilities_efetivas`/`_escopos_efetivas`.
- **F4-08** concluída: RLS de leitura own-tenant + revogação de privilégios.
- Tabelas F3-02/03/04/08 existentes com constraints e exclusion; `btree_gist` habilitada
  (`20260907103000`).

### 26.2 Dependências de decisão (bloqueiam a implementação)

- **Q1** (reabertura de unidade/posição), **Q2** (reatribuição de posição), **Q3**
  (retificação), **Q4** (chave de lock / F5-07), **Q5** (fronteira da UI de alocação).

### 26.3 Dependências de atividades futuras

- **F5-09** (ciclos) consome `collegiate_configurations` via snapshot — não depende da UI da
  F5-08, mas depende de a configuração poder ser mantida (esta atividade).
- **F5-12** (validação integrada) deve incluir as telas de administração da F5-08 no roteiro.
- Importação de acervo legado (F5-07 §20.6) precisará destas operações; este desenho não a
  antecipa.

## 27. Plano de implementação sugerido

| Fase | Entrega | Gate |
| --- | --- | --- |
| **P1** | Migration DDL: `structure_events`, triggers I1–I3, índice D20, normalização de grants | `db reset` + `02-validar-f5-08.sql` (schema) |
| **P2** | RPCs (15) + grants de `EXECUTE` | validador + testes de comportamento SQL |
| **P3** | Contrato/Edge: operações novas, dispatch, taxonomia de erro | `npm test`, `npx tsc -b`, testes de contrato |
| **P4** | Porta/serviço no cliente + telas de Catálogos, Unidades, Posições, Colegiado | testes de tela (sem escrita local) |
| **P5** | Alocação do colaborador (ocupação/reporting line) nas telas existentes | testes de tela + remoção dos avisos "F5-08" |
| **P6** | Remoção da autoridade estrutural local (§19) + CI (validadores) | `03-validar-f5-08-cutover.sql`, regressão F4/F5 completa, `npm run build`/`lint`, `git diff --check` |

Cada fase é um lote coeso; os comandos que exigem elevação são agrupados no gate de cada fase
(`AGENTS.md` §4). Nenhuma fase começa com Q aberta que a afete.

## 28. Questões para validação

> Dúvidas arquiteturais **reais**: não são dedutíveis dos contratos fechados nem do estado do
> código. Cada uma traz recomendação; a implementação das partes afetadas fica bloqueada até a
> decisão.

### Q1 — Reabertura/segunda janela de vigência de unidade e de posição

- **Contexto:** `organizational_units` e `organizational_positions` são "uma linha, uma janela"
  (`20260907130000:119-138, 288-314`), sem exclusion e sem tabela de versões. Encerrar = gravar
  `valid_to`; **não existe** forma não destrutiva de reabrir (exigiria limpar `valid_to`, isto é,
  reescrever um fato registrado) nem de ter duas janelas para o mesmo `id`. Além disso,
  `uq_organizational_units_organization_name` **não é parcial** (`:130`): o nome de uma unidade
  encerrada permanece reservado.
- **Alternativas:** (A) manter o modelo e tratar "reabrir" como **nova unidade/posição** (novo
  UUID, possivelmente nome variante), preservando histórico e FKs; (B) permitir reabertura por
  `UPDATE valid_to = null` quando a janela encerrada **nunca** foi usada por ocupação, reporting
  line ou escopo; (C) criar tabela de versões de unidade/posição (mudança de modelo, migração de
  FKs — rejeitada em §8.1).
- **Recomendação:** **(A)** nesta atividade — zero mudança de modelo, zero risco para FKs e
  contratos, comportamento explícito na UI ("unidade encerrada não pode ser reaberta; crie uma
  nova"). Se o produto exigir reabertura, reabrir contrato em atividade própria (é mudança de
  modelo temporal, não detalhe de implementação).
- **Impacto:** UI/UX e operação; nenhum impacto de segurança. Nenhuma RPC de reabertura é
  especificada enquanto não decidido.
- **Seções dependentes:** §8.1, §9.2, §21.3, §24.2, R1.

### Q2 — Reatribuição de posição preservando a identidade

- **Contexto:** D5 fixa que `unit_id`/`job_role_id`/`seniority_level_id` são imutáveis (alterá-los
  reescreveria o significado histórico da posição referenciada por `occupations`,
  `position_reporting_lines` e `collegiate_cycle_snapshot_positions`). Não há contrato que diga
  se o produto precisa "mover a posição X para a unidade Y mantendo o mesmo id".
- **Alternativas:** (A) nova posição (novo UUID) + encerramento da anterior — alocação atual e
  futura seguem por novas ocupações; (B) permitir `UPDATE` de atributos com vigência nova
  (exigiria versionar a posição: tabela nova, Q1-C); (C) permitir `UPDATE` direto (rejeitado:
  reescreve passado).
- **Recomendação:** **(A)**, com a UI deixando claro que "mover" = encerrar + criar e que a
  ocupação vigente precisa ser encerrada/recriada (as guardas I3 e o trigger F3-04 já impedem
  encerrar posição com ocupação/reporting vigente).
- **Impacto:** UX de administração e continuidade da cadeia (reporting lines precisam ser
  redefinidas ao trocar a posição). Nenhum impacto de segurança.
- **Seções dependentes:** §9.2, §10.2 (I3), §21.3, R2.

### Q3 — Retificação de lançamento equivocado (janela nunca consumida)

- **Contexto:** a F5-07 §11.4 proíbe alterar linha temporal fechada e o enunciado exige preservar
  fatos passados. Mas um erro percebido imediatamente (ex.: `valid_from` equivocado, cargo
  trocado, unidade errada) que **nunca** foi consumido por ocupação, reporting line, escopo ou
  snapshot deixa o modelo sem correção limpa: fechar + abrir produz um segmento histórico
  artificial que nunca existiu na realidade.
- **Alternativas:** (A) proibir retificação — corrigir sempre por fechar + abrir, com `reason`
  explicando; (B) permitir `UPDATE` excepcional quando comprovadamente não houve consumo (janela
  sem ocupação/reporting/escopo/snapshot e dentro de tolerância temporal), com evento
  `RETIFICADO` e `before/after`; (C) permitir `UPDATE` livre pelo administrador (rejeitado:
  reescreve história sem controle).
- **Recomendação:** **(A)** nesta atividade (fail-closed, zero exceção de imutabilidade, sem API
  que possa ser usada para reescrever história); se a operação real exigir (B), implementar em
  atividade própria com guardas explícitas e auditoria dedicada.
- **Impacto:** operacional (qualidade do histórico) e de UX (mensagem clara de como corrigir).
  Nenhum impacto de segurança.
- **Seções dependentes:** §9.1, §14.2, D8, R7.

### Q4 — Unificação da chave de advisory lock (F3-04 × RPCs estruturais da F5-07)

- **Contexto:** o trigger anti-ciclo da F3-04 usa `hashtext('position_reporting_lines:' || org)`
  e documenta que o caminho de escrita futuro deve usar o mesmo lock (`20260907140000:253-268`);
  as RPCs estruturais da F5-07 usam `hashtext('f5_07_estrutura:' || org)`
  (`20260913010000:864, 1031, 1179, 1344`). Consequência: as duas rotas **não** serializam —
  duas escritas concorrentes (uma por cada rota) podem avaliar a árvore antes de a outra
  commitar, e o anti-ciclo pode não enxergar o estado que a outra está criando.
- **Alternativas:** (A) F5-08 adota a chave da F3-04 nas suas RPCs (feito em D14) e a **F5-07 é
  corrigida** na mesma implementação, trocando a chave nas 4 ocorrências; (B) F5-08 adota a
  chave da F3-04 e a F5-07 é corrigida em manutenção própria (mantém o risco aberto no
  intervalo); (C) alterar o **trigger** da F3-04 para a chave da F5-07 (rejeitado: contraria a
  documentação normativa da própria F3-04).
- **Recomendação:** **(A)** — correção pontual (4 literais) que elimina uma janela de
  integridade real, sem alterar contrato (nenhuma assinatura; comportamento observável muda
  apenas para melhor). Exige, porém, aprovação por tocar código da F5-07 (atividade fechada).
  Se a decisão for preservar a F5-07 intocada, adotar **(B)** e registrar Issue própria.
- **Impacto:** integridade sob concorrência (R5). Não muda autorização nem schema.
- **Seções dependentes:** §4.7 G10, §14.3, §25.4 F4, D14.

### Q5 — Fronteira de entrega da UI de alocação do colaborador

- **Contexto:** a F5-07 removeu unidade/cargo/senioridade/gestor dos formulários e deixou-os
  **read-only** com o aviso "Estrutura organizacional (F5-08)"
  (`EditarColaboradorPage.tsx:61-63, 648-681`), mas **já entregou** as operações soberanas de
  ocupação/reporting line sem nenhum consumidor de UI
  (`acessoColaboradoresSoberanos.ts:211-332`). A estrutura só tem valor operacional quando
  alguém **aloca** o colaborador.
- **Alternativas:** (A) a F5-08 entrega também essas telas (alocação + reporting line na UI de
  colaborador, reusando as operações existentes); (B) a F5-08 entrega apenas a administração de
  estrutura/catálogo e a alocação fica para atividade própria (ex.: F5-08b); (C) a alocação é
  absorvida pela F5-09 (ciclos) por causa da elegibilidade — rejeitada: alocação é estrutura,
  não ciclo.
- **Recomendação:** **(A)**, porque sem UI de alocação a F5-08 entrega estrutura que ninguém
  consegue aplicar e o §20.1 da F5-07 exige que a F5-08 feche a administração estrutural;
  alternativamente (B), com Issue explícita e critérios de aceite da F5-08 reduzidos ao §18.1
  (1)–(3).
- **Impacto:** escopo/cronograma da atividade; nenhum impacto de segurança.
- **Seções dependentes:** §18.1, §21.2, §24.2 item 7, §27 P5.

## 29. Decisões arquiteturais

### D1 — Reuso integral das tabelas F3; nenhuma entidade estrutural nova

As tabelas exigidas já existem com PK/FK/constraints/exclusion/versionamento compatíveis. A
F5-08 **não cria tabela de entidade**; a única tabela nova é a trilha `structure_events` (§8.3) e
nenhuma coluna nova é adicionada. Nenhum campo de motivo entra nas tabelas F3 (§8.2).
*Evidência:* F5-07 §20.1 `:1282-1303`; `20260907120000`, `20260907130000`, `20260907140000`,
`20260907180000`.

### D2 — Três regimes temporais distintos, sem unificação

`valid_to` monotônico, intervalo `[)`, vigência `valid_from <= d < coalesce(valid_to,'infinity')`;
regime por entidade conforme §9.2 (janela única para unidade/posição; versionado fechar-e-abrir
para relações; status para catálogos). Alterar regime existente exigiria contrato novo —
proibido nesta atividade.
*Evidência:* F3-02 `:26-29, 116-118`; F3-03 `:136-137, 219-223`; F3-08 D4/D9/D10.

### D3 — Identidade funcional é UUID; nome/código são rótulos

Nenhum nome, código, senioridade textual ou matrícula é identidade, hierarquia, escopo,
requisito de avaliador ou decisão do Policy Engine.
*Evidência:* F5-07 D3/D5 (§6.3 `:374-390`, teste T-22); F4-02 §19 inv.2/3 `:546-550`;
F4-04 §3/§6.

### D4 — Rótulos editáveis com trilha; `code` de cargo imutável; encerrado não é renomeado

Renomear unidade/cargo/senioridade é permitido **enquanto vigente/ativo**, com
`expected_version`, motivo e evento com `before_value`. `job_roles.code`, uma vez atribuído, é
**imutável** (chave de compatibilidade com a `funcao` legada e de idempotência do bootstrap).
Unidade/posição/catálogo **encerrado/inativo** não é renomeado.
*Evidência:* `20260907120000:21-22, 110-113` (nome não é identidade);
`20260913000000:144, 178-179` (code); `20260913010000:1762-1792` (bootstrap nunca renomeia).

### D5 — Atributos estruturais da posição são imutáveis

`unit_id`, `job_role_id` e `seniority_level_id` não são alterados em posição existente; mudança
⇒ nova posição (novo UUID) e encerramento da anterior (necessidade de produto: Q2).
*Evidência:* invariante de não reescrita do passado (F5-07 §11.4); FKs de `occupations`,
`position_reporting_lines` e `collegiate_cycle_snapshot_positions` referenciam `position_id`.

### D6 — Encerramento é `valid_to`; encerrar com estrutura vigente é recusado

Nenhum encerramento usa DELETE. Encerrar **unidade** exige ausência de posição vigente e de
período parent vigente como filha (I2); encerrar **posição** exige ausência de ocupação vigente
(I3) e de reporting line vigente (trigger F3-04). Análogo a F5-07 D6
(`20260907150000:218-236`).
*Evidência:* `20260907140000:313-350`; F5-07 D6 `:1122-1128`.

### D7 — Prevenção de ciclos de unidade no banco

Novo trigger com CTE recursiva sobre `organizational_unit_parent_periods` na data da linha,
recusando ciclo, sob advisory lock por organização. Fecha a lacuna que a F3-03 deixou
explicitamente para a aplicação (`20260907130000:62-65, 194-195`).
*Evidência:* `20260907130000` (comentários); trigger análogo da F3-04 `:256-303`.

### D8 — DELETE físico proibido

Sem policy de DELETE; `revoke delete` de `service_role` nas tabelas administradas; catálogos
inativados no lugar; fatos temporais encerrados por `valid_to`. Correção de lançamento
equivocado: Q3.
*Evidência:* `20260907120000:26-29, 116-118`; F5-07 `20260913000000:791-795`.

### D9 — Fronteira server-side é a Edge `colaboradores` estendida

Nenhuma Edge nova; as operações novas entram no contrato compartilhado, no dispatch e no
repositório já existentes.
*Evidência:* `supabase/functions/colaboradores/index.ts:201-293`;
`src/infrastructure/supabase/colaboradores/contrato.ts:73-118`.

### D10 — Gate administrativo por capability efetiva, nas duas camadas

`org.structure.manage`/`org.catalog.manage` verificadas na Edge (padrão D19/F5-07) **e**
revalidadas na transação do banco (`colaborador_ator_valido` +
`resolver_capabilities_escopos_efetivas`). `usuario_eh_administrador` **não** é o gate da F5-08
(não conhece capability). Nenhuma capability nova; allowlist funcional intacta.
*Evidência:* `20260910020000:39-63`; `core.ts:472-492`; F5-07 D19/Q1 `:1212-1269`; F5-06 D27.

### D11 — Colegiado pertence a `org.structure.manage`

`collegiate_configurations` (+ membros) é relação temporal por avaliado, não catálogo (§11.3).
*Evidência:* F3-08 `:6-15, 59-83`; F4-02 D6 (ASSIGNED derivado); `contrato.ts:86-113`.

### D12 — Resolvers e scopes intocados

F3-07/F4-02 permanecem como estão; nenhuma capability, scope ou alvo novo; DIRECT_REPORTS,
DESCENDANTS, UNIT e ASSIGNED mantêm contrato e passam apenas a receber dados corretos.
*Evidência:* F4-02 §4–§10, D5/D6; F4-04 §21 (grep de CI).

### D13 — Trilha append-only `structure_events`

Nova tabela (§8.3) molde de `collaborator_events`; evento e mutação na mesma transação;
append-only no banco; `payload` nunca é autoridade.
*Evidência:* F5-07 D8/§12 `:754-798`; `20260913000000:216-333`; F5-06 D26.

### D14 — Concorrência: versão otimista + lock por organização + idempotência

`expected_version` obrigatório em mutação de linha existente; lock
`hashtext('position_reporting_lines:' || organization_id)` (chave da F3-04) em toda mutação
estrutural; idempotência por `operation_id`/`payload_hash`. A divergência da F5-07 é Q4.
*Evidência:* F5-07 §13/D13; `20260907140000:253-268`; `20260913000000:255-258`.

### D15 — Integridade cross-tenant por construção

FKs compostas `(ref_id, organization_id)` (existentes) + tenant do ator revalidado + entidade
resolvida por `(id, organization_id)`; cross-tenant ⇒ DENY/`NOT_FOUND`.
*Evidência:* `20260907130000:207-214, 303-311`; `.ai/architecture-rules.md`.

### D16 — Leitura permanece no contrato F4-08

Sem policy nova, sem RPC de listagem, sem gate administrativo para leitura; SELECT own-tenant já
concedido a `authenticated`.
*Evidência:* `20260908110000:33-69, 112-125`; F4-08.

### D17 — Catálogos: inativação no lugar; item inativo não é referenciável em relação nova

`status ∈ (active, disabled)`; sem exclusão; sem coluna de ordenação (`name` ordena a UX);
`seniority_levels` não ganha `code`; leitura histórica preservada; novas posições exigem item
ativo (I4).
*Evidência:* `20260907120000:26-40, 116-118, 186-189`; F5-07 D5.

### D18 — Cutover e remoção da autoridade estrutural local

Telas de administração (§18.1) + alocação; seleções por ID canônico; erro do servidor exibido;
sem optimistic update que represente estado rejeitado; invalidação após mutação;
`mundoFuncional`/`authorizationPolicy` sem fallback local; sem escrita estrutural em
`localStorage` fora de DEV; nenhuma estrutura derivada de cargo/matrícula/nome.
*Evidência:* enunciado (UI E CUTOVER); F5-07 §14.6/§15.3; `.ai/architecture-rules.md`.

### D19 — D19 e D20 herdadas permanecem intactas

Nenhuma evidência técnica nova (§11.6). Nenhuma capability nova; allowlist `[]` preservada; CRUD
estrutural permanece nesta atividade.
*Evidência:* F5-07 D19 `:1212-1223`, D20 `:1225-1234`, Q1 fechada `:1240-1269`;
`capabilityTarget.ts:45-46`; `colaboradoresContratoRpc.test.ts:639-654`.

### D20 — Migrations aditivas, índice novo e catalogação no CI

Duas migrations aditivas + três validadores + execução no job `supabase-local` do CI; índice de
`parent_unit_id`; grants explícitos; nenhuma migration aplicada é reescrita.
*Evidência:* §20; `.github/workflows/ci.yml`; F5-07 §10.4/§20.1.

## 30. Rastreabilidade das 28 questões centrais

| # | Questão do enunciado | Onde é respondida |
| --- | --- | --- |
| 1 | Fonte real de verdade de cada entidade | §4.1 (tabela) |
| 2 | Tabelas que existem × precisam ser criadas/alteradas | §4.2, §8.1–§8.4 (reuso; 1 tabela nova; 1 índice) |
| 3 | Lifecycle temporal e semântica de validade | §9.1, §9.2, D2 |
| 4 | Alterações históricas sem sobrescrever fatos | §9.4, §9.5, D2, D5, D8 |
| 5 | Impedir ciclos, estruturas impossíveis, cross-tenant e sobreposições | §10.2 (I1–I7), §10.4, §12.2 |
| 6 | Constraints garantidas pelo PostgreSQL | §10.1, §10.4 |
| 7 | Regras que exigem função/RPC transacional | §10.3, §13.6 |
| 8 | Fronteira server-side das operações administrativas | §17.1, D9 |
| 9 | Como as capabilities são verificadas sem quebrar D19 | §11.1, §11.6, D10, D19 |
| 10 | Operações de `org.structure.manage` | §11.3, §22.1 |
| 11 | Operações de `org.catalog.manage` | §11.3, §22.1 |
| 12 | Operação que não se encaixa nos dois grupos | §11.3 (`collegiate_configurations` → `org.structure.manage`) |
| 13 | ActorContext necessário | §11.2 |
| 14 | ResourceContext funcional aplicável? | §11.2 (não; allowlist `[]`) |
| 15 | Autoria soberana | §15.1–§15.3, D13 |
| 16 | Eventos/auditoria append-only | §15, §8.3, D13 |
| 17 | DELETE físico × encerramento/inativação | D8, §9.2, §21.3, Q3 |
| 18 | Preservar referências históricas | §9.4, §16.3, §23.2 (F) |
| 19 | Impacto em DIRECT_REPORTS/DESCENDANTS/UNIT/ASSIGNED | §16.1, §16.2, D12 |
| 20 | Caminhos que ainda fabricam estrutura local | §4.5, §19.1 |
| 21 | Cutover desses caminhos | §18, §19, D18 |
| 22 | Leituras que permanecem cache × precisam migrar | §13.1, §19.2, D16 |
| 23 | TOCTOU entre decisão e mutação | §14.5 |
| 24 | Concorrência entre duas alterações simultâneas | §14.2, §14.3, §14.6 |
| 25 | Testes SQL/TS/integrados obrigatórios | §23 |
| 26 | Regressões F4/F5 necessárias | §16.4, §24.3 |
| 27 | Impacto nos contratos fechados da F5-07 | §3.1, §16, §25.3 |
| 28 | Evidência nova que exija reconsiderar D19/D20 | §11.6, D19 (**permanecem intactas**) |
