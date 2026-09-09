# F4-09 — Contrato arquitetural: autorização funcional aplicada aos domínios do Virtus (Issue #96)

> **Status: CONTRATO FECHADO PARA IMPLEMENTAÇÃO.**
> Q1–Q7 **FECHADAS** (§17); D1–D12 **FECHADAS** (§18); matriz §7 revisada para o
> vocabulário canônico (capability = ação) — sem contradições internas.
>
> **IMPLEMENTAÇÃO BLOQUEADA ATÉ O MERGE DA F4-08 / PR #154.** Esta atividade é
> **somente documentação**: nenhum código funcional, nenhuma migration, nenhuma
> alteração de banco, nenhuma policy RLS foi produzida. A Issue #96 **permanece
> aberta**; o PR desta atividade é somente documentação e **NÃO usa `Closes #96`**;
> **sem merge**.

## 1. Objetivo e fronteira (Issue #96)

Aplicar a arquitetura de autorização construída nas F4-01…F4-08 aos domínios
funcionais do Virtus (avaliações, metas, observações, ciclos e correlatos),
garantindo que **possuir acesso ao tenant NÃO significa possuir acesso aos dados
funcionais de outras pessoas**.

- **RLS (F4-08)** responde "esta identidade autenticada tem membership ativa para
  tocar dados deste tenant?". Hoje o RLS cobre as 28 tabelas estruturais/
  autorizativas; os **domínios funcionais permanecem em localStorage** (pré-F5).
- **Policy Engine (F4-03)** responde "esta identidade pode executar esta
  capability sobre este recurso neste contexto?". É a **única porta** de decisão
  na camada de aplicação.

### 1.1 Fora de escopo (Issue #96 e contratos)

migração de persistência não executada (F5); relatórios avançados; produção;
redesenhar Edge Functions/Policy Engine/F4-06/F4-07; domínios localStorage (F5
não é antecipada); tabelas C/D; FORCE RLS; novos SECURITY DEFINER; fechar a
Issue #96.

### 1.2 Dependência F4-08/F5

- **Herda do contrato F4-08:** fronteira soberana D1 (`auth.uid()` + profile
  ativo + membership ativa); RLS como última barreira quando houver tabela;
  "policy pronta antes de conceder acesso"; sem FORCE RLS; sem novo DEFINER.
- **Para os domínios funcionais (localStorage):** a F4-09 protege na **camada de
  aplicação**, sem simular segurança de banco para dado que ainda existe apenas
  localmente. As invariantes definidas na §15 deverão sobreviver à migração F5,
  quando cada tabela funcional nascerá com RLS + `organization_id` +
  classificação D16 e o enforcement passará a ser revalidado atomicamente na
  RPC/transação (F4-03 D9).

## 2. Adversários (segurança e confidencialidade permanentes)

- **Ameaça interna:** usuário legítimo da própria organização acessando o que não
  deve: avaliação de outro; a própria avaliação antes da liberação; avaliação
  histórica sem autorização; observações não-comunicadas; feedback de outra
  pessoa; dados de outra equipe; dados de antigo subordinado; dados de quem nunca
  esteve sob sua responsabilidade; ex-gestor; gestor fora do scope; usuário comum
  tentando relatório gerencial.
- **Ameaça externa:** API direta; manipulação de IDs; enumeração; inferência de
  existência; sessão inválida; JWT inválido; tenant incorreto.

O sistema **não pode depender da interface** para impedir esses acessos.

## 3. Regra fundamental (duas fronteiras)

1. RLS (quando houver tabela): pertence ao tenant?
2. Policy Engine: capability + recurso + contexto?

**Membership NÃO significa autorização funcional genérica.** A F4-09 combina as
duas fronteiras. Para domínios localStorage a fronteira é o Policy Engine,
resolvida por identidade autenticada + perfil ativo + membership ativa (D1
F4-08) + capability + estado funcional + temporalidade — **nunca por cargo,
nome ou parâmetro do frontend** (F4-01 inv.1: cargo nunca concede capability).

## 4. Confidencialidade de avaliações (requisito CRÍTICO)

Princípio: **uma avaliação só é acessível quando existe autorização explícita
para aquele usuário, naquele contexto e naquele momento. A idade da avaliação
nunca reduz sua confidencialidade.** Avaliação histórica permanece protegida;
não se assume "avaliação antiga = menos confidencial"; a mudança organizacional
atual não reescreve autorização histórica quando o contrato histórico
(snapshot F3-08/09, sucessão F3-09) determina outra coisa.

### 4.1 Casos decididos (fechados; ver matriz §7)

1. colaborador A → avaliação de B: DENY;
2. colaborador → própria avaliação ANTES da liberação: DENY (estado);
3. colaborador → própria avaliação em `CONCLUIDA` (se a regra funcional
   permitir): ALLOW (SELF + capability + estado) — Q4 fechada;
4. gestor atual → avaliação histórica anterior a assumir a equipe: **DENY por
   padrão** (Q5 fechada); histórico usa relação/snapshot soberano do período;
5. ex-gestor → avaliação após perder a relação: DENY;
6. coordenador → pessoa fora do alcance: DENY;
7. gerente extrapolando scope: DENY;
8. substituto temporário (F4-05): ALLOW somente na janela e nas capabilities
   previstas (contexto vivo);
9. C (F4-06): ALLOW somente no contrato C (leitura, ciclo, 1 grant);
10. D (F4-07): nunca abre conteúdo confidencial;
11. histórico F3-08/09: RLS protege tenant; leitura funcional segue capability +
    regra histórica (snapshot congelado soberano).

## 5. Não vazar a existência do dado (information disclosure)

Quando apropriado, o usuário não autorizado não deve distinguir com facilidade
"registro inexistente" de "registro existe, mas você não pode acessar".
Superfícies: IDs e consulta direta; contagens e listas; filtros/autocomplete;
mensagens de erro; metadata/endpoints; relatórios/agregações (§12); histórico.

Regra: em **leitura/resolução** de conteúdo confidencial, preferir resultado
vazio/not-found genérico (não distingue existência); em **mutação**, erro de
autorização pode ser explícito quando não há benefício em ocultar. O engine já
mapeia `CROSS_TENANT/TARGET_INVALID → NOT_FOUND` (F4-03 D6), coerente com esta
regra.

## 6. Estado atual real (inventário verificado no repositório)

### 6.1 Descobertas estruturais (pré-condições do desenho)

1. **Persistência:** nenhum domínio funcional usa banco/Supabase. Tudo em
   `localStorage`, JSON serializado. `src/infrastructure/supabase/` é apenas um
   cliente condicional (auth) sem fluxo funcional.
2. **Duas superfícies de autorização coexistem:** o **engine novo**
   (`policyEngine/` + providers) é usado em produção somente no fluxo de **metas
   próprias** (`goal.write` + SELF) e nos núcleos de concessão C/D (sem UI); o
   restante do app usa a **API legada** (`authorizationPolicy.ts`), que decide **por
   `funcao`** (GERENTE/COORDENADOR/…) + estado do recurso + helpers legados. A
   F4-09 substitui a superfície legada por chamadas ao engine (D2).
3. **Drift de vocabulário (Q1 fechada):** catálogo SQL (21) × `Capability.ts`
   runtime (36), quase disjuntos, com várias capabilities runtime codificando
   papel (`.manager/.coordinator/.board/.view.admin` etc.). **Capability passa a
   representar AÇÃO**; papel é expresso por relação/scope/target/domainState
   (Q1). Ver §6.3 (catálogo canônico) e o mapa de reconciliação.
4. **Duas trilhas de identidade:** (a) Supabase Auth resolve identidade
   (user_profile/membership/org — **sem dados de colaborador/cargo**); (b)
   Impersonação DEV escolhe um `Colaborador` sintético. **Não existe em src
   código mapeando user_profile → colaborador** — a ponte existe no banco
   (`membership_collaborator_links` + `resolver_collaborador_vinculado`) e está
   prevista para F5.
5. **Mundo local pré-F5 (Q2 fechada):** para a F4-09 rodar antes da F5, será usado
   **binding explícito DEV-only de capabilities por colaborador/identidade**
   (nunca derivado de `funcao`; fail-closed fora de DEV; transitório). A F5
   substitui pelo fluxo real `membership → access_role → capability`.

### 6.2 Domínios funcionais (inventário por domínio)

Legenda de estados: Ciclo `PLANEJADO|ATIVO|ENCERRADO|CANCELADO`; Avaliação
`RASCUNHO|PRONTA_PARA_FEEDBACK|CONCLUIDA|CANCELADA`; Observação
`POSITIVA|NEUTRA|NEGATIVA` (+ `comunicado:boolean` + soft delete); Meta
`EM_ANDAMENTO|ATINGIDA|NAO_ATINGIDA`; Colaborador
`ATIVO|LICENCA|DESLIGADO`.

| Domínio (entidade) | Persistência (chave localStorage) | Services/repos | Páginas/componentes | Sensibilidade | Histórico/auditoria |
|---|---|---|---|---|---|
| Ciclos (`CicloAvaliacao`) | `feedback-control-ciclos` | `cicloAvaliacaoStorage`, `cicloEquipeService`, serviços cancelar/reabrir/corrigir | `CiclosAvaliacaoPage`, `PainelCicloPage`, `PainelCiclosCoordenadorPage` | Baixa (config de janela) | `cancelamento/encerramentos/reaberturas/correcoesPeriodo` |
| Avaliações (`Feedback`) | `feedback-control-feedbacks` | `feedbackStorage`, `permissaoAvaliacao`, `progressoAvaliacao`, cancelar/reabrir | `ColaboradorDetalhePage`, `Novo/EditarFeedbackPage`, `FeedbackDetalhePage`, `MinhaAvaliacao(Detalhe)Page` | **MUITO ALTA** | `dataConclusao`, `canceladoPor*`, `reaberturas[]`; avaliado só `CONCLUIDA` |
| Observações (`Observacao`) | `feedback-control-observacoes` | `observacaoStorage` | `ObservacoesColaborador` | **ALTA** (avaliado vê só `comunicado`) | `historico[]`, soft delete + autor |
| Metas (`Meta`) | `feedback-control-metas` | `metaStorage` | `MinhasMetasPage`, `AcompanhamentoMetasPage`, `PainelCicloPage` | Média | `historico[]` (8 ações), soft delete, invalidação de aprovações |
| Colaboradores (`Colaborador`) | `feedback-control-colaboradores` | `colaboradorStorage`, portas hexagonais | `ColaboradoresPage`, `Novo/EditarColaborador/DetalhePage`, `InicioPage` | Alta (dados pessoais) | desligamento por status; movimentações |
| Hist. organizacional | `feedback-control-historico-organizacional` | `historicoOrganizacionalStorage` | `ColaboradorDetalhePage` | Média | append-only; base "gestor na data/ciclo" |
| Régua/notas, expectativa, branding | chaves próprias dos storages | `escalaAvaliacaoStorage` etc. | `ConfiguracoesAparenciaPage` | Baixa | padrão + preservação |
| Relatórios (derivado) | (não persiste) | `relatorioService`, `exportarAvaliacaoPdf` | `RelatoriosPage` | **ALTA** (agrega avaliações) | consolida só `PRONTA_PARA_FEEDBACK/CONCLUIDA` |

Modelo de avaliação: `Feedback` pertence a um avaliado (`colaboradorId`) e a um
ciclo por referência implícita `ano+ciclo` (1|2|3); notas por papel com autoria;
o avaliado vê a avaliação somente `CONCLUIDA` e observações somente `comunicado`.

### 6.3 Catálogo canônico de capabilities (Q1 fechada — estratégia)

**Decisão:** capability = **ação**, nunca papel organizacional. Gerente,
coordenador e colegiado são distinguidos por **relação + scope + target +
domainState**, e por **quem recebe a capability** (configuração de `access_role`
por membership — F4-01/F5), nunca por nome de capability com sufixo de papel.

**Reconciliação das 21 SQL × 36 runtime:**

1. O catálogo SQL da F4-01 já é majoritariamente de ação (`evaluation.cancel`,
   `evaluation.reopen`, `goal.approve`…). Ele vira a **âncora canônica**.
2. Capabilities runtime que codificam papel são **depreciadas e mapeadas** para a
   ação canônica correspondente (a diferença real vai para scope/relação/
   domainState):
   - `evaluation.edit.manager` / `evaluation.edit.coordinator` /
     `evaluation.edit.board` → **`evaluation.write`** (o papel que edita é
     resolvido por scope DESCENDANTS/DIRECT_REPORTS/ASSIGNED + merge por papel
     como regra funcional);
   - `evaluation.view.admin` → **`evaluation.read`** (ler avaliação de terceiro
     exige relação/scope; ler a própria exige SELF + `CONCLUIDA`);
   - `evaluation.cancel.manager` → **`evaluation.cancel`**;
   - `evaluation.reopen.manager` → **`evaluation.reopen`**;
   - `cycle.cancel.manager` → **`cycle.cancel`**;
   - `cycle.reopen.manager` → **`cycle.reopen`**;
   - `cycle.period.correct.manager` → **`cycle.period.correct`**;
   - `goal.approve.manager` / `goal.approve.coordinator` → **`goal.approve`**;
   - `goal.*.own` → **`goal.write`** com scope **SELF** (+ `goal.read` para ver);
   - `goal.view.admin` → **`goal.read`**;
   - `report.view` → **`report.read`** (código SQL);
   - `collaborator.list` → **`collaborator.read`** (dataset via scope);
   - `collaborator.create` / `collaborator.edit` permanecem (ações), alinhadas ao
     catálogo de gestão de cadastro;
   - `observation.create/edit/delete` permanecem (ações), reconciliadas com
     `observation.read/write` do catálogo (ver nota da matriz §7.3);
   - `cycle.coordinator.list`, `cycle.management.view`, `cycle.team.panel.view`
     → leituras administrativas de ciclo: **`cycle.read`** + scope (painel de
     equipe = DIRECT_REPORTS/DESCENDANTS; administração = role com `cycle.read`
     administrativo);
   - `exceptional_access.grant`, `pilot_full_access.grant` permanecem (ações de
     concessão, F4-06/F4-07).
3. **Catálogo canônico proposto após F4-09 (uma única lista compartilhada — TS
   union + linhas SQL sincronizadas):**
   `collaborator.read/create/edit`; `cycle.read/manage/cancel/reopen/period.correct`;
   `evaluation.read/create/write/cancel/reopen`; `goal.read/write/approve`;
   `observation.read/create/edit/delete`; `report.read`; `settings.manage`;
   `membership.read/manage`; `access_role.manage`; `org.structure.manage`;
   `org.catalog.manage`; `exceptional_access.grant`; `pilot_full_access.grant`
   (~27 códigos). As capabilities legadas com papel permanecem apenas como
   **aliases de migração** (mapeadas ao canônico), nunca como novas decisões.

## 7. Matriz de autorização (DOMÍNIO × AÇÃO × CAPABILITY(canônica) × TARGET ×
SCOPE × RELAÇÃO × ESTADO/TEMPORALIDADE × CONFIDENCIALIDADE × ORIGEM)

Convenção: capability = **ação canônica** (§6.3); scope =
`SELF|DIRECT_REPORTS|DESCENDANTS|ORGANIZATIONAL_UNIT|ORGANIZATION|ASSIGNED`;
"quem" = **relação resolvida por dado** (gerente da cadeia via `gestorDireto`
na data; coordenador direto; membro de colegiado atribuído) **+ concessão da
capability por role** — nunca cargo; origem A/B (normal), C (exceptional), D
(pilot — development only, nunca confidencial). Operações que hoje têm somente
`can` na UI recebem `authorize` no serviço (▸). `domainState` valida se a ação
pode ocorrer naquele estado/momento (Q7).

### 7.1 Ciclos

| Ação | Capability | Target | Scope | Estado/temporalidade | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Ver administração de ciclos | `cycle.read` | ciclo | ORGANIZATION | — | role administrativa com `cycle.read`; demais: DENY |
| Criar/ativar/encerrar/configurar ciclo | `cycle.manage` | ciclo | ORGANIZATION | transições legais; encerrar exige pendências resolvidas (domainState) | role administrativa com `cycle.manage`; demais: DENY |
| Corrigir período (ciclo ATIVO) | `cycle.period.correct` | ciclo | ORGANIZATION | só ATIVO; justificativa (domainState) | role administrativa (gerente) com `cycle.period.correct`; coordenador: DENY |
| Cancelar ciclo (ATIVO) | `cycle.cancel` | ciclo | ORGANIZATION | só ATIVO (domainState); auditoria | role administrativa (gerente); demais: DENY |
| Reabrir ciclo (ENCERRADO) | `cycle.reopen` | ciclo | ORGANIZATION | só ENCERRADO; impede 2 ATIVOS (domainState) | role administrativa (gerente) |
| Excluir ciclo PLANEJADO | `cycle.manage` | ciclo | ORGANIZATION | só PLANEJADO e sem avaliações preenchidas (domainState) | role administrativa |
| Painel de ciclo (equipe/coordenador) | `cycle.read` | colaborador-list/ciclo | DIRECT_REPORTS (coordenador) / DESCENDANTS (gerente) | dataset = colaboradores visíveis na data | gerente (descendentes) e coordenador (diretos) no alcance; usuário comum: DENY |

### 7.2 Avaliações

| Ação | Capability | Target | Scope | Estado/temporalidade/confidencial | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Criar avaliação do avaliado no ciclo | `evaluation.create` | evaluation (avaliado×ciclo) | DESCENDANTS / DIRECT_REPORTS / ASSIGNED | ciclo ≠ CANCELADO; avaliado ATIVO e elegível (domainState) | gerente/coordenador/colegiado com relação; ADMIN comum sem relação: DENY; avaliado (SELF): DENY |
| Ler avaliação de terceiro (avaliador/admin) | `evaluation.read` | evaluation | DIRECT_REPORTS / DESCENDANTS / ASSIGNED | confidencial; sem relação ⇒ DENY/not-found; histórico só com regra explícita (Q5) | avaliador com relação; ex-gestor/fora do alcance: DENY |
| Ler própria avaliação | `evaluation.read` | evaluation (SELF) | SELF | **somente `CONCLUIDA`** e ciclo ≠ CANCELADO (Q4; SELF nunca supera) | avaliado; antes da liberação: DENY |
| Editar/avaliar por papel | `evaluation.write` | evaluation | DESCENDANTS (gerente) / DIRECT_REPORTS (coordenador) / ASSIGNED (colegiado) | ciclo ≠ CANCELADO e status ≠ CONCLUIDA/CANCELADA; merge por papel é regra funcional | gerente/coordenador/colegiado com relação (papel por scope); demais: DENY |
| Cancelar avaliação | `evaluation.cancel` | evaluation | DESCENDANTS (cadeia do gerente) | ciclo ≠ CANCELADO; status ≠ CANCELADA (domainState) | role de gestão com `evaluation.cancel` na cadeia (regra funcional "só gerente" mantida por concessão+scope); coordenador/colegiado: DENY |
| Reabrir avaliação CONCLUIDA | `evaluation.reopen` | evaluation | DESCENDANTS (cadeia do gerente) | status CONCLUIDA; ciclo ≠ ENCERRADO/CANCELADO (domainState) | role de gestão com `evaluation.reopen` na cadeia |
| Acesso excepcional (C) | `evaluation.read` via C | evaluation (+cycleId) | C | somente leitura; ciclo obrigatório; A/B DENY + confidencial; 1 grant; janela | beneficiário do grant C; revogado/expirado ⇒ DENY |

### 7.3 Observações

| Ação | Capability | Target | Scope | Estado/temporalidade/confidencial | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Criar observação sobre colaborador | `observation.create` | observation (colaborador×ciclo) | DIRECT_REPORTS / DESCENDANTS | ciclo ATIVO; avaliado ≠ DESLIGADO (domainState) | gerente/coordenador na relação; avaliado: DENY |
| Editar observação | `observation.edit` ▸(add authorize) | observation | DIRECT_REPORTS / DESCENDANTS | ciclo ATIVO; autor/gestor no alcance | gerente/coordenador; demais: DENY |
| Excluir observação | `observation.delete` ▸(add authorize) | observation | DIRECT_REPORTS / DESCENDANTS | ciclo ATIVO; soft delete + histórico | gerente/coordenador |
| Marcar como `Comunicado` | `observation.edit` ▸ | observation | DIRECT_REPORTS / DESCENDANTS | ato de disponibilização ao avaliado | gerente/coordenador |
| Colaborador ver observações do próprio ciclo | regra funcional sobre dados (não abre não-comunicado) | observation (SELF, só ciclo) | SELF | **somente `comunicado=true`** do próprio ciclo | avaliado (comunicadas); não-comunicadas: DENY mesmo SELF |

> Nota de reconciliação (§6.3): `observation.edit`/`observation.delete` e
> `observation.read/write` do catálogo podem ser unificados na implementação como
> ações granulares canônicas; o essencial (Q1) é que nenhum código carregue papel
> no nome. A granularidade de edição vs. exclusão é mantida por serem ações
> distintas com auditoria própria.

### 7.4 Metas

| Ação | Capability | Target | Scope | Estado/temporalidade | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Criar/editar/acompanhar/finalizar meta própria | `goal.write` | goal (owner SELF) | SELF | ciclo ATIVO; dono = ator; perfil com fluxo próprio é regra funcional (Q3) | colaborador dono (conforme perfil funcional atual — Q3 preserva a regra do produto) |
| Aprovar meta (coordenador/gerente) | `goal.approve` | goal | DIRECT_REPORTS (coordenador) / DESCENDANTS (gerente) | ciclo ATIVO; meta do subordinado no alcance (domainState) | coordenador direto / gerente da cadeia (papel por scope) |
| Acompanhar/ver metas de terceiro | `goal.read` | goal | DIRECT_REPORTS / DESCENDANTS | ciclo ATIVO | gerente/coordenador no alcance |
| Metas do colegiado | — | — | — | regra funcional de produto (Q3) | colegiado não obtém hierarquia nem metas por ASSIGNED de avaliação (F4-04) |

### 7.5 Relatórios e dashboards

| Ação | Capability | Target | Scope | Regra | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Ver relatórios | `report.read` | relatório (dataset colaboradores) | DIRECT_REPORTS (coordenador) / DESCENDANTS (gerente) | **limit-then-aggregate (D12)**; consolida só `PRONTA_PARA_FEEDBACK/CONCLUIDA`; coordenador só equipe direta | gerente/coordenador no alcance; ADMIN comum: DENY; D não cobre `report.read`; C não abre relatório genérico |

### 7.6 Escopo de colaboradores visíveis (base funcional)

- gerente: descendentes da cadeia (equivalente a DESCENDANTS);
- coordenador: subordinados diretos ∪ colegiado onde é avaliador (para operação);
  em **relatório**: somente equipe direta;
- demais: `[]` (fail-closed);
- a F4-09 substitui `getColaboradoresVisiveis`/`authorizationPolicy` por
  providers do engine que derivam DIRECT_REPORTS/DESCENDANTS/ASSIGNED dos dados
  (gestorDireto + colegiado + histórico na data), **sem cargo** (D2/D3).

### 7.7 Origem de autorização e confidencialidade

- conteúdo de avaliação/feedback e observações não-comunicadas = **confidencial**
  (classificação soberana por domínio/probe `isTargetConfidential`); relatório
  consolidado = confidencial;
- A/B tentam primeiro; confidencial: A/B DENY ⇒ somente C (leitura, F4-06);
  não-confidencial: A/B DENY ⇒ D possível (development only, F4-07); indeterminada
  ⇒ DENY;
- C fora de `listAllowedTargets`; D não cobre confidencial; C/D revogados/
  expirados ⇒ DENY.

## 8. Policy Engine (F4-03 soberana) e pontos de chamada

- `authorize(request)` = **enforcement real** (lança erro público F0-05 em DENY);
- `can(request)` = **UX somente** (retorna `AuthorizationDecision` — usar
  `.allowed`); `listAllowedTargets(...)` = **auxiliar de listagem** (remove
  origem C; nunca é prova para mutação);
- proibido: segunda regra paralela em tela/hook/service/repository; `legacyMap`
  nunca consultado em runtime; páginas/serviços não decidem;
- pipeline fail-closed (identidade→profile→membership→tenant→capability→
  capability×target→scope/relação→data→domainState→ALLOW);
- origem C/D só como fallback pontual quando A/B DENY (§7.7); erros públicos:
  cross-tenant/target inválido ⇒ NOT_FOUND; estado inválido ⇒ CONFLICT; demais ⇒
  FORBIDDEN.

### 8.1 Onde `authorize()` deve ser chamado (F4-09)

- Na **camada de serviço/use-case**, imediatamente antes da mutação e antes de
  retornar leitura crítica — nunca na UI;
- alvo/contexto resolvidos do **recurso carregado** (nunca ids/org do cliente);
  tenant derivado do recurso;
- TOCTOU: `can`/`listAllowedTargets` não substituem `authorize`; com F5, a
  revalidação ocorre na mesma RPC/transação (F4-03 D9) com RLS por linha;
- a F4-09 adiciona `authorize` onde hoje só existe `can` (▸ na §7), em especial:
  edição/exclusão de observação e leituras administrativas sensíveis.

### 8.2 Origens A/B, C, D

- A/B = membership → role → capability → scope (fonte real após F5; no mundo
  local, binding DEV-only explícito — Q2/D3);
- C (F4-06): allowlist fechada `evaluation.read`, leitura, ciclo obrigatório,
  1 grant por (beneficiário, capability, target, tenant, janela); avaliada só
  quando A/B DENY e confidencial; não revela inventário;
- D (F4-07): development-only, `PILOT_PROFILE_V1`, nunca confidencial/segurança/
  configuração, ≤30 dias;
- auditoria preserva origem (`membership:…`, `temporary:<id>`,
  `exceptional:<grantId>`, `pilot:<grantId>`).

## 9. SELF e outras relações

**SELF não significa "posso ler qualquer dado sobre mim"**: a própria avaliação
pode estar bloqueada pelo estado (publicação) — SELF + capability + estado +
temporalidade + confidencialidade avaliados juntos (Q4). Vale a mesma análise
para DIRECT_REPORTS/DESCENDANTS/UNIT/ORGANIZATION/ASSIGNED:

- DIRECT_REPORTS/DESCENDANTS dão **alcance** sobre colaboradores da árvore na
  data — não liberam conteúdo; a capability e o estado decidem a ação;
- UNIT: só a unidade atribuída (sem subunidades);
- ORGANIZATION: alcance de todo o tenant, **não permissão** sobre conteúdo de
  terceiros;
- ASSIGNED (colegiado/avaliação): só o alvo tipado atribuído (avaliado × posição
  × ciclo); não cria hierarquia, não vira wildcard, não concede metas/
  observações do avaliado.

## 10. Temporalidade

Distinguir: relação atual (viva); relação no momento da avaliação; snapshot/
histórico (F3-08 imutável); assignment histórico; substituição temporária
(F4-05, janela `[valid_from, valid_to)`, contexto vivo); mudança de gestor/
coordenador (sucessão F3-09); desligamento/licença.

- relação atual **não concede automaticamente** acesso histórico sem regra
  explícita (Q5: DENY por padrão);
- relação passada **não continua concedendo** acesso atual (ex-gestor perde;
  substituição expira; desligamento remove);
- ciclo avaliativo é congelado (responsável/colegiado = F3-08/09);
- resolução sempre na **data de contexto explícita**.

## 11. Observações e feedback (análise explícita)

- conteúdo sensível: observações podem ser negativas; a visão do colaborador é
  **somente `comunicado=true`** do próprio ciclo — não-comunicadas nunca chegam
  ao avaliado (nem SELF);
- criar: gestor/coordenador no alcance, ciclo ATIVO, avaliado ativo;
- editar/excluir: gestor/coordenador no alcance, ciclo ATIVO, com `authorize`
  (hoje parcialmente só `can`);
- "marcar como comunicado": ato de disponibilização ao avaliado;
- histórico/rastreabilidade: soft delete + `historico[]` + autores preservados;
- feedback final e votos de colegiado são os campos mais sensíveis — nunca por
  SELF antes de `CONCLUIDA` e nunca por agregação não autorizada.

## 12. Relatórios e agregações (D12)

- `report.read` não está no bundle do ADMIN comum; D não cobre `report.read`; C
  não abre relatório como domínio genérico;
- **limit-then-aggregate (D12):** (1) determinar os targets/dataset autorizados;
  (2) limitar o dataset; (3) só então agregar/calcular/exportar. Proibido
  agregar o dataset completo e filtrar depois. Sem targets autorizados ⇒ dataset
  vazio ⇒ agregado vazio. Vale também após a migração F5.
- filtros/export herdam o dataset autorizado; contagens não revelam existência de
  dados confidenciais fora do alcance.

## 13. Ameaças a considerar (threat model e testes futuros)

IDOR; troca de `collaboratorId`/`evaluationId`/`cycleId`/`organizationId`;
manipulação de URL/query; chamada direta ao service/repository/API; enumeração;
acesso antecipado; acesso histórico indevido; ex-gestor; gestor fora do scope;
usuário comum tentando relatório gerencial; inferência de existência por erro;
manipulação de estado no frontend; localStorage adulterado; refresh/session
stale; capability removida durante a sessão; assignment removido; substituição
expirada; C revogado; D revogado; **ADMIN (função/perfil administrativo) usado
como bypass de conteúdo confidencial (D11)**; agregação sobre dataset completo
seguida de filtro (D12).

## 14. Arquitetura de aplicação (fluxo seguro por operação)

1. **Entrada funcional** (page → hook → service): UI pede uma operação
   (capability de ação) sobre um recurso;
2. **Service/use-case** (fronteira de aplicação) é o único executor e o único que
   chama o engine;
3. **Carregar o recurso** para derivar alvo/contexto; o tenant é derivado do
   recurso; nunca confiar em ids/org do cliente;
4. **`authorize`** no serviço imediatamente antes da operação (TOCTOU), com
   origens A/B→C/D conforme §7.7 e probe de domínio (domainState) soberano
   (Q7);
5. **Persistir/retornar** após ALLOW; falha → erro público F0-05 (mutação) ou
   vazio/not-found genérico (leitura confidencial).

Evita: carregar confidencial antes de autorizar; confiar em target/org do
frontend; duplicar autorização em UI; autorizar por cargo/nome; bypass por
chamada direta; ADMIN como superusuário de conteúdo (D11).

## 15. F4-08 e F5

- **F4-09 protege agora:** fluxos funcionais localStorage pela invocação única do
  engine em cada operação, com contexto soberano (identidade + perfil +
  membership) e mundo local derivado dos dados (relação por gestorDireto/
  colegiado/histórico) — sem simular RLS.
- **Depende de F5:** RLS em tabelas funcionais e impossibilidade de bypass por
  chamada direta a API/banco. Quando os domínios migrarem, cada tabela funcional
  nasce com `ENABLE RLS` + policy por comando + `organization_id` + classificação
  D16 e revalidação atômica na RPC/transação (F4-03 D9); **D12 (limit-then-
  aggregate) vale também após F5**.
- **Invariantes que devem sobreviver à migração:** avaliação só acessível com
  autorização explícita (idade não reduz confidencialidade); avaliado vê somente
  observações `comunicado`; colegiado (ASSIGNED) sem hierarquia; ADMIN sem leitura
  de confidencial sem grant excepcional (D11); mutação respeita estado do ciclo/
  recurso; SELF restrito por estado; nenhuma segunda regra paralela.

## 16. Matriz de testes (desenho; priorizar NEGATIVOS)

Obrigatórios (vocabulário canônico; implementação após merge F4-08): funcionário
A → avaliação de B = DENY; SELF antes da liberação (`PRONTA_PARA_FEEDBACK` e
anteriores) = DENY; SELF em `CONCLUIDA` (quando permitido) = ALLOW; ex-gestor →
histórico indevido = DENY; gestor correto → recurso dentro do scope = ALLOW;
gestor → fora do scope = DENY; ID manipulado = DENY; C válido = ALLOW somente no
contrato C; C revogado = DENY; D válido somente onde permitido; D nunca abre
confidencial; D revogado = DENY; substituição válida = ALLOW na janela;
substituição expirada = DENY; assignment removido = DENY; capability removida =
DENY; **ADMIN sem relação lendo avaliação/observação não-comunicada = DENY
(D11)**; relatório não vaza dados fora do dataset autorizado (D12 — agregar
dataset completo e filtrar depois = proibido); usuário não autorizado não
enumera existência de avaliações; mutação direta sem UI = DENY; observação
não-comunicada invisível ao avaliado; ciclo cancelado bloqueia criar/editar;
colegiado não obtém hierarquia do avaliado; nenhum mapeamento `funcao →
capability` em runtime (regressão).

## 17. Questões — Q1–Q7 (TODAS FECHADAS)

Histórico das questões abertas no desenho, agora **fechadas**:

1. **Q1 — Vocabulário de capabilities — FECHADA.** Capability representa **ação**,
   não papel. Gerente/coordenador/colegiado distinguidos por relação/scope/
   target/domainState e por concessão de role — nunca por capability com sufixo
   de papel. Estratégia de reconciliação e catálogo canônico em §6.3; nenhum
   mapeamento `funcao → capability` em runtime.
2. **Q2 — Origem de capability no mundo local (pré-F5) — FECHADA.** Binding
   **explícito DEV-only** de capabilities por colaborador/identidade para permitir
   a F4-09 antes da F5; nunca derivado de `funcao`; fail-closed fora de DEV;
   transitório; F5 substitui por `membership → access_role → capability`.
3. **Q3 — SELF/metas e perfis com fluxos próprios — FECHADA.** Preservar nesta
   fase as regras funcionais atuais do produto; não redesenhar quem possui fluxo
   próprio durante a F4-09. Diferença funcional por perfil é modelada em
   domainState/regra funcional, nunca transformando cargo em fonte de autorização.
   Revisão de produto eventual = backlog separado.
4. **Q4 — Publicação/liberação da avaliação — FECHADA.** O avaliado lê a própria
   avaliação **somente em `CONCLUIDA`**. `PRONTA_PARA_FEEDBACK` permanece
   confidencial (não é publicação). SELF nunca supera essa regra.
5. **Q5 — Gestor atual × avaliação histórica anterior — FECHADA.** **DENY por
   padrão**: assumir responsabilidade atual não concede acesso a avaliações
   históricas anteriores à relação. Histórico usa relação/snapshot soberano do
   período. Exceção futura: explícita, capability específica, auditável e
   desenhada separadamente.
6. **Q6 — C para observações/relatórios — FECHADA.** Não ampliar o contrato C
   nesta fase; C permanece exatamente conforme F4-06; observações e relatórios não
   se tornam acessíveis genericamente por C.
7. **Q7 — Encerramento e mutações administrativas — FECHADA.** Toda mutação
   administrativa funcional passa por **`authorize()` + `domainState`**: a
   capability responde se o ator pode executar a ação; o domainState responde se a
   ação pode ocorrer naquele estado/momento. Nenhuma substitui a outra.

## 18. Decisões arquiteturais — D1–D12 (TODAS FECHADAS)

1. **D1 — Fronteira de aplicação primeiro.** A F4-09 aplica o Policy Engine aos
   domínios funcionais na camada de serviço (enforcement `authorize`) e usa `can`
   somente para UX; o RLS dos domínios funcionais é adiado a F5 (sem simular
   segurança de banco para localStorage).
2. **D2 — Substituir a superfície legada.** `authorizationPolicy.ts` (decisão por
   `funcao`) e helpers legados deixam de ser a fonte de decisão; a relação
   autorizadora passa a ser derivada de dados (gestorDireto + colegiado +
   histórico na data) via providers do engine. `legacyMap` permanece somente como
   artefato de regressão (nunca runtime).
3. **D3 — Mundo local (pré-F5) derivado dos dados, sem cargo.** O provider do
   mundo local resolve DIRECT_REPORTS/DESCENDANTS a partir da cadeia
   `gestorDiretoMatricula` e ASSIGNED do colegiado/avaliadores na data; nenhuma
   capability é derivada de `funcao`; binding DEV-only (Q2).
4. **D4 — SELF não abre conteúdo antes do estado.** SELF + capability + estado +
   temporalidade + confidencialidade avaliados conjuntamente (Q4: só `CONCLUIDA`).
5. **D5 — Capability × tipo de alvo em allowlist fechada.** Combinação não
   prevista ⇒ DENY.
6. **D6 — ASSIGNED não cria hierarquia nem wildcard.** Colegiado só sobre o alvo
   tipado atribuído; não concede metas/observações do avaliado.
7. **D7 — Confidencialidade soberana por domínio/probe.** Classificação
   (`isTargetConfidential`) decide C vs D; indeterminada ⇒ DENY; D nunca é fallback
   de confidencial; C fora de `listAllowedTargets`.
8. **D8 — Grants C/D respeitam F4-06/F4-07.** C: leitura, `evaluation.read`,
   ciclo obrigatório, 1×1, janela; D: development-only, perfil versionado, ≤30
   dias; revogação/expiração ⇒ efeito imediato.
9. **D9 — Sem tabelas novas e sem novo DEFINER nesta fase.** Enforcement de
   aplicação + testes; nenhuma tabela C/D, nenhum SECURITY DEFINER, nenhum FORCE
   RLS.
10. **D10 — Administrativo exige relação, não cargo.** Criar/editar/cancelar/
    reabrir exige relação + capability + estado; ver D11.
11. **D11 — ADMIN NÃO É SUPERUSUÁRIO DE CONTEÚDO.** Ter função/perfil/capability
    administrativa NÃO concede automaticamente leitura de avaliações, notas,
    comentários, observações confidenciais, feedback ou histórico confidencial.
    Conteúdo confidencial exige autorização explícita sobre target/contexto
    (C é a única via excepcional); cargo/função ADMIN nunca funciona como bypass.
12. **D12 — LIMIT-THEN-AGGREGATE.** Relatórios, dashboards, médias, contagens,
    rankings e exports: (1) determinam os targets/dataset autorizados; (2) limitam
    o dataset; (3) só então agregam/calculam/exportam. Proibido agregar o dataset
    completo e filtrar depois. Sem targets autorizados ⇒ dataset vazio ⇒ agregado
    vazio. Vale também após a migração F5.

## 19. Confirmações da atividade

- **Somente documentação:** nenhum código funcional, nenhuma migration, nenhuma
  alteração de banco, nenhuma policy RLS foi produzida.
- **Contrato fechado para implementação**, com **implementação bloqueada até o
  merge da F4-08 / PR #154**.
- Issue #96 **permanece aberta**; o PR é somente documentação e **não usa
  `Closes #96`**; **sem merge**.
- Q1–Q7 fechadas (§17); D1–D12 fechadas (§18); matriz §7 consistente com o
  vocabulário canônico (§6.3); nenhum texto interno contradiz as decisões.

## 20. Implementação — registro de entrega (Issue #96, PR #157)

> **Status:** implementado (migração funcional INTEGRAL em runtime). PR de
> implementação **`Closes #96`**, sem merge.

### 20.1 Arquitetura implementada

- **Vocabulário canônico (Q1):** `Capability.ts` lista o catálogo de AÇÃO (§6.3)
  e mantém os aliases legados como depreciados; `canonical.ts`
  (`canonicalizarCapability`) reconcilia alias→canônico; `capabilityTarget.ts`
  inclui os códigos canônicos.
- **Mundo funcional local (D2/D3/Q2):** `mundoFuncional.ts` deriva relações de
  `gestorDiretoMatricula`/`avaliadoresColegiadoMatriculas` (nunca `funcao`);
  `derivarBindingsDev` constrói o binding DEV-only EXPLÍCITO por estrutura
  (raiz→gestão, gestor de 1º nível→coordenação, colegiado→ASSIGNED, demais→SELF);
  resolve alvos `collaborator` e `cycle` no tenant sintético e adiciona
  `ORGANIZATION` (raiz) restrita a alvos de domínio (ciclo) — nunca a colaborador
  (D6/D10: não vaza para relações de avaliação/meta/observação).
- **Facade (D1/Q7):** `autorizacaoFuncional.ts` — `autorizar` (enforcement),
  `pode` (UX), `alvosPermitidos` (listagem, base do limit-then-aggregate) e
  `dominioPermite` (domainState). Alvo sempre derivado do recurso, nunca de ids
  do cliente.
- **`authorizationPolicy.ts` é AGORA um adaptador de compatibilidade que DELEGA ao
  engine** (`policyEngine.decidir` via `can`/`authorize`). Não possui regra
  soberana, nem derivação por `funcao`/`cargo`, nem bypass: apenas traduz o
  vocabulário legado (capability + resource) para a requisição do engine
  (capability canônica + target + domainState). Todos os call sites de runtime
  (`can`/`authorize`/`scopeCollaborators`) passam pelo engine.

### 20.2 Superfícies de runtime migradas (decisão integral via engine)

| Domínio | Operações | Enforcement |
| --- | --- | --- |
| Avaliação | create/edit/cancel/reopen/read | `authorizationPolicy` → engine (`evaluation.*` + scope + domainState de ciclo/status) |
| Meta | approve/own (write/read) | `metaStorage.aprovarMeta` (engine) e `authorizationPolicy` (`goal.approve`/`goal.write` + cadeia de gestão/SELF) |
| Observação | create/edit/delete/read | `authorizationPolicy` → engine (`observation.*` + ciclo ATIVO + status do alvo) |
| Relatório | read (escopo) | `authorizationPolicy` → engine (`report.read`) + `relatorioService.aplicarEscopoRelatorio`/`visibilidadeColaboradores` (dados) |
| Ciclo | cancel/reopen/period.correct | `cancelamentoCicloService`/`reaberturaCicloService`/`correcaoPeriodoCicloService` carregam e passam `collaborators` → engine (`cycle.*` + domainState) |
| Colaborador | create/edit/list | `authorizationPolicy` → engine (`collaborator.*`) |

- `permissaoAvaliacao.ts` (gerente = raiz da cadeia; coordenador = gestor direto),
  `visibilidadeColaboradores.ts` (raiz→descendentes; não-raiz→diretos+colegiado),
  `metaStorage.podeAprovarMetaNoCiclo` e `relatorioService.aplicarEscopoRelatorio`
  deixaram de ser fonte de decisão por cargo: são derivados de dados e/ou
  consumidos pelo domínio (workflow/papel exibido), nunca ALLOW/DENY por `funcao`.
- **Colapso Q1 aplicado:** `evaluation.edit.manager/coordinator/board` →
  `evaluation.write`; `goal.approve.manager/coordinator` → `goal.approve`;
  `goal.*.own` → `goal.write` (SELF); `cycle.management.view`/`cycle.coordinator.list`/
  `cycle.team.panel.view` → `cycle.read`; `report.view` → `report.read`;
  `collaborator.list` → `collaborator.read`. O papel é resolvido por
  capability + scope + relação + domainState, nunca pelo nome da capability.

### 20.3 Limitações genuínas pré-F5 (fora do escopo de #96)

- **Temporalidade histórica (Q5) é fail-closed no engine:** o engine usa a relação
  corrente (`gestorDiretoMatricula`); `historico-organizacional` NÃO concede
  autorização (ex-gestor ⇒ DENY; novo gestor sem relação corrente ⇒ DENY). A
  temporalidade por ciclo é responsabilidade do domínio (pré-F5), nunca do engine.
- **Scope é por ator (não capability×scope):** a granularidade capability×scope
  fecha na F5. No mundo local, casos de vazamento entre scopes são contidos por
  domainState soberano (ex.: `goal.approve` exige `estaNaCadeiaDeGestao`;
  `goal.write` exige `ator === owner`; `ORGANIZATION` não cobre colaborador).
- Sem tabelas novas, sem novo SECURITY DEFINER, sem FORCE RLS (D9). O RLS
  funcional real é F5.

### 20.4 Testes

- Novo `f4-09-functional.test.ts` (12 testes): A→B DENY; SELF só CONCLUIDA;
  coordenador/gerente/colegiado por relação; alterar `funcao` sem mudar relação
  NÃO concede; capability removida ⇒ DENY imediato; ID manipulado ⇒ TARGET_INVALID;
  metas/observações; listAllowedTargets limita dataset.
- `authorizationPolicy.test.ts` atualizado para o mundo derivado de dados:
  colapso Q1, `goal.approve`/`goal.write` com domainState de cadeia/SELF e
  histórico fail-closed (ex-gestor DENY / gestor atual ALLOW).
- Total: **758 testes** (56 arquivos); build e lint OK; `git diff --check` limpo;
  validação Supabase local F4-08 reexecutada (sem regressão de tenant/security).

### 20.5 Ausência estática de autorização por cargo

- `grep -nE "funcao ===|funcao !==|\.funcao ===" src/authorization` não retorna
  ALLOW/DENY por `funcao`/`cargo`/nome de papel: `funcao` permanece apenas em
  UX/apresentação e em regra de DOMÍNIO sobre o AVALIADO
  (`funcaoUsaEstruturaAvaliacaoAnalista`), nunca como fonte de autorização do ator.
