# F4-09 — Contrato arquitetural: autorização funcional aplicada aos domínios do Virtus (Issue #96)

> **Status:** DESENHO TÉCNICO — contrato em revisão de desenho. Esta atividade é
> **somente documentação**: nenhum código funcional, nenhuma migration, nenhuma
> alteração de banco, nenhuma policy RLS foi produzida. A Issue #96 **permanece
> aberta**; o PR desta atividade é somente documentação e **NÃO usa `Closes #96`**;
> **sem merge**.
>
> A implementação da F4-09 **começa somente após o merge da F4-08 (PR #154)**.
> Este desenho usa o CONTRATO fechado da F4-08 (docs/F4-08-desenho-tecnico.md),
> mas **não depende de código não mergeado como se já estivesse na main**.

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
  localmente. As invariantes que a F4-09 define (§15) deverão sobreviver à
  migração F5, quando cada tabela funcional nascerá com RLS + `organization_id` +
  classificação D16 e o enforcement passar a ser revalidado atomicamente na
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

### 4.1 Casos que a matriz (§7) decide explicitamente

1. colaborador A → avaliação de B: DENY;
2. colaborador → própria avaliação ANTES da liberação: DENY (estado);
3. colaborador → própria avaliação DEPOIS da liberação, se a regra funcional
   permitir: ALLOW (SELF + capability + estado);
4. gestor atual → avaliação histórica anterior a assumir a equipe: regra
   explícita (sem presunção de acesso);
5. ex-gestor → avaliação após perder a relação: DENY (salvo contrato histórico
   explícito);
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

Regra de desenho (refinada na matriz): em **leitura/resolução** de conteúdo
confidencial, preferir resultado vazio/not-found genérico (não distingue
existência); em **mutação**, erro de autorização pode ser explícito quando não
há benefício em ocultar. O engine já mapeia `CROSS_TENANT/TARGET_INVALID →
NOT_FOUND` (F4-03 D6), coerente com esta regra.

## 6. Estado atual real (inventário verificado no repositório)

### 6.1 Descobertas estruturais (pré-condições do desenho)

1. **Persistência:** nenhum domínio funcional usa banco/Supabase. Tudo em
   `localStorage`, JSON serializado. `src/infrastructure/supabase/` é apenas um
   cliente condicional (auth) sem fluxo funcional.
2. **Duas superfícies de autorização coexistem:**
   - **Engine novo** (`policyEngine/` + providers): usado em produção somente no
     fluxo de **metas próprias** (`goal.write` + SELF via `localWorld`) e nos
     núcleos de concessão C/D (sem UI). O resto do app usa:
   - **API legada** (`authorizationPolicy.ts`): decisão **por `funcao`**
     (GERENTE/COORDENADOR/…) + estado do recurso + helpers
     (`permissaoAvaliacao.ts`, `visibilidadeColaboradores.ts`,
     `relatorioService.ts`, `metaStorage.podeAprovarMetaNoCiclo`). Esta é a
     superfície que a F4-09 precisa **substituir por chamadas ao engine**.
3. **Dois vocabulários de capability (drift registrado — F4-06 Q6):** catálogo SQL
   (21) × `Capability.ts` runtime (36). Coincidem por string apenas em
   `settings.manage`, `evaluation.read/create/write`, `goal.write/approve`. O
   runtime é a referência dos contratos F4-06/07; a F4-09 usa o vocabulário
   runtime e propõe alinhamento (Q1).
4. **Duas trilhas de identidade:** (a) Supabase Auth resolve identidade
   (user_profile/membership/org — **sem dados de colaborador/cargo**); (b)
   Impersonação DEV escolhe um `Colaborador` sintético (matrícula/função/status).
   **Não existe em src código mapeando user_profile → colaborador** — a ponte
   existe no banco (`membership_collaborator_links` + `resolver_collaborador_vinculado`)
   e está prevista para F5. Hoje o ator do engine é `actorId = String(matricula)`
   no tenant sintético `organizacao-sintetica-local`.
5. **Regra legada por cargo** é o que F4-09 erradica: nenhuma capability nasce de
   `funcao`; a relação que autoriza (gestor da cadeia, coordenador direto,
   colegiado/avaliador) é **dado estrutural/derivado** (gestorDireto,
   avaliadoresColegiado, histórico organizacional, snapshot F3-08/09 após F5).

### 6.2 Domínios funcionais (inventário por domínio)

Legenda de estados: Ciclo `PLANEJADO|ATIVO|ENCERRADO|CANCELADO`; Avaliação
`RASCUNHO|PRONTA_PARA_FEEDBACK|CONCLUIDA|CANCELADA`; Observação
`POSITIVA|NEUTRA|NEGATIVA` (+ `comunicado:boolean` + soft delete); Meta
`EM_ANDAMENTO|ATINGIDA|NAO_ATINGIDA`; Colaborador
`ATIVO|LICENCA|DESLIGADO`.

| Domínio (entidade) | Persistência (chave localStorage) | Services/repos | Páginas/componentes | Ops | Sensibilidade | Histórico/auditoria |
|---|---|---|---|---|---|---|
| Ciclos (`CicloAvaliacao`) | `feedback-control-ciclos` | `cicloAvaliacaoStorage`, `cicloEquipeService`, serviços cancelar/reabrir/corrigir/reabrir | `CiclosAvaliacaoPage`, `PainelCicloPage`, `PainelCiclosCoordenadorPage` | criar/ativar/encerrar/excluir(planejado)/editar período/config/corrigir período/cancelar/reabrir | Baixa (config de janela) | `cancelamento/encerramentos/reaberturas/correcoesPeriodo` |
| Avaliações (`Feedback`) | `feedback-control-feedbacks` | `feedbackStorage`, `permissaoAvaliacao`, `progressoAvaliacao`, cancelar/reabrir, `cicloEquipeService` | `ColaboradorDetalhePage`, `NovoFeedbackPage`, `EditarFeedbackPage`, `FeedbackDetalhePage`, `MinhaAvaliacao(Detalhe)Page` | criar/editar(papéis)/concluir/cancelar/reabrir/ler | **MUITO ALTA** (notas, comentários, votos, feedback final) | `dataConclusao`, `canceladoPor*`, `reaberturas[]`, snapshots de expectativa; disponibilização ao avaliado só em `CONCLUIDA` |
| Observações (`Observacao`) | `feedback-control-observacoes` | `observacaoStorage` | `ObservacoesColaborador`, filtro por ciclo | criar/editar/excluir (soft)/marcar comunicado/ler | **ALTA** (podem ser negativas; avaliado vê só `comunicado`) | `historico[]` (CRIAÇÃO/EDIÇÃO/EXCLUSÃO), `excluida` + autor |
| Metas (`Meta`) | `feedback-control-metas` | `metaStorage` | `MinhasMetasPage`, `AcompanhamentoMetasPage`, `PainelCicloPage` | criar/editar/aprovar(excluir/acompanhar/finalizar) | Média (dono + aprovações) | `historico[]` (8 ações), soft delete, invalidação de aprovações |
| Colaboradores (`Colaborador`) | `feedback-control-colaboradores` | `colaboradorStorage`, portas hexagonais (`CollaboratorRepository`) | `ColaboradoresPage`, `NovoColaborador/EditarColaborador/DetalhePage`, `InicioPage` | listar/criar/editar/ver detalhe | Alta (dados pessoais) | desligamento por status; movimentações em `HistoricoOrganizacional` |
| Hist. organizacional (`MovimentacaoOrganizacional`) | `feedback-control-historico-organizacional` | `historicoOrganizacionalStorage` | `ColaboradorDetalhePage` | registrar/ler | Média | append-only; base "quem era o gestor na data/ciclo" |
| Régua/notas (`EscalaAvaliacao`) | `feedback-control-escala-avaliacao` | `escalaAvaliacaoStorage` | `ConfiguracoesAparenciaPage` | ler/salvar/restaurar | Baixa (config) | histórico de versões preservado por storage |
| Expectativa de cargo | `feedback-control-expectativas-cargo` | `expectativaCargoStorage` | `ConfiguracoesAparenciaPage` | ler/salvar/restaurar | Baixa | snapshots na criação de avaliação |
| Branding/config | `feedback-control-branding` | `brandingStorage` | `ConfiguracoesAparenciaPage` | ler/salvar/resetar | Baixa | padrão + persistência |
| Relatórios (derivado) | (não persiste; agrega painel+escala) | `relatorioService`, `exportarAvaliacaoPdf` | `RelatoriosPage` | ler/exportar | **ALTA** (agrega avaliações) | consolida só `PRONTA_PARA_FEEDBACK/CONCLUIDA`; coordenador só equipe direta |

Modelo de avaliação: `Feedback` pertence a um avaliado (`colaboradorId`) e a um
ciclo por referência implícita `ano+ciclo` (1|2|3); notas por papel
(`notaGerente/notaCoordenador/notaColegiado/notaFinal`) com autoria; o avaliado
vê a avaliação somente `CONCLUIDA` e observações somente `comunicado`.

## 7. Matriz de autorização (DOMÍNIO × AÇÃO × CAPABILITY × TARGET × SCOPE ×
RELAÇÃO × ESTADO × TEMPORALIDADE × CONFIDENCIALIDADE × ORIGEM)

Convenção: capability = código runtime; target = tipo de recurso; scope =
`SELF|DIRECT_REPORTS|DESCENDANTS|ORGANIZATIONAL_UNIT|ORGANIZATION|ASSIGNED`;
origem = A/B (normal), C (exceptional), D (pilot — development only, nunca
confidencial); coluna "quem/porquê" resume a regra (detalhe nas notas por
domínio). Para operações hoje sem `authorize` no serviço (somente `can` na UI),
a F4-09 adiciona o `authorize` (marcado ▸).

### 7.1 Ciclos (administração GERENTE + visão coordenador)

| Ação | Capability | Target | Scope | Regra (estado/temporalidade) | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Ver administração de ciclos | `cycle.management.view` | ciclo | ORGANIZATION | — | GERENTE (na A/B, ver Q sobre origem da capability pré-F5) |
| Criar/ativar/encerrar ciclo | `cycle.management.view` | ciclo | ORGANIZATION | transição PLANEJADO→ATIVO→ENCERRADO; encerrar exige pendências resolvidas | gerente do tenant; demais: DENY |
| Corrigir período de ciclo ATIVO | `cycle.period.correct.manager` | ciclo | ORGANIZATION | só ATIVO; justificativa | gerente; coordenador: DENY |
| Cancelar ciclo ATIVO | `cycle.cancel.manager` | ciclo | ORGANIZATION | só ATIVO; auditoria | gerente |
| Reabrir ciclo ENCERRADO | `cycle.reopen.manager` | ciclo | ORGANIZATION | só ENCERRADO; impede 2 ATIVOS | gerente |
| Excluir ciclo PLANEJADO | `cycle.management.view` | ciclo | ORGANIZATION | só PLANEJADO e sem avaliações preenchidas | gerente |
| Painel de ciclo (equipe) | `cycle.team.panel.view` | colaborador-list/ciclo | DIRECT_REPORTS (coordenador) / DESCENDANTS (gerente) | dataset = colaboradores visíveis na data | gerente (descendentes) e coordenador (diretos), conforme §7.6; usuário comum: DENY |
| Painel agregado do coordenador | `cycle.coordinator.list` | ciclo | DIRECT_REPORTS | apenas ciclos em que é coordenador | coordenador; demais: DENY |

### 7.2 Avaliações (administração: quem avalia/edita/gerencia)

Base de relação (dado estrutural, não cargo): gerente = gerente responsável na
cadeia do avaliado (`gestorDiretoMatricula` ↑ até GERENTE); coordenador =
coordenador direto de avaliado ANALISTA/ESTAGIÁRIO; colegiado = membro do
colegiado do avaliado (derivado de F3-08 após F5; hoje do
`avaliadoresColegiadoMatriculas` + histórico).

| Ação | Capability | Target | Scope | Regra (estado) | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Criar avaliação do avaliado no ciclo | `evaluation.create` | evaluation (avaliado×ciclo) | DESCENDANTS (gerente)/DIRECT_REPORTS (coordenador)/ASSIGNED (colegiado) | ciclo ≠ CANCELADO; avaliado ATIVO; avaliado elegível no ciclo | gerente/coordenador/colegiado com relação; ADMIN comum sem relação: DENY; avaliado (SELF): DENY |
| Ler avaliação de terceiro (avaliador/admin) | `evaluation.read` (admin: `evaluation.view.admin`) | evaluation | DIRECT_REPORTS/DESCENDANTS/ASSIGNED | estado qualquer, se autorizado; sem autorização ⇒ DENY/not-found | avaliador com relação; **ex-gestor/fora do alcance: DENY**; histórico só com regra explícita |
| Ler própria avaliação | `evaluation.read` | evaluation (SELF) | SELF | **somente CONCLUIDA** e ciclo ≠ CANCELADO | avaliado; antes da liberação: DENY |
| Editar (papel gerente) | `evaluation.edit.manager` | evaluation | DESCENDANTS | ciclo ≠ CANCELADO e status ≠ CONCLUIDA/CANCELADA; merge por papel | gerente da cadeia |
| Editar (papel coordenador) | `evaluation.edit.coordinator` | evaluation | DIRECT_REPORTS | idem; avaliado ANALISTA/ESTAGIÁRIO | coordenador direto |
| Editar (papel colegiado) | `evaluation.edit.board` | evaluation | ASSIGNED | idem | membro do colegiado atribuído |
| Concluir/pronta para feedback | `evaluation.write` | evaluation | conforme papel | transições legais | quem pode editar o papel |
| Cancelar avaliação | `evaluation.cancel.manager` | evaluation | DESCENDANTS | ciclo ≠ CANCELADO; status ≠ CANCELADA | gerente da cadeia (não coordenador/colegiado) |
| Reabrir avaliação CONCLUIDA | `evaluation.reopen.manager` | evaluation | DESCENDANTS | status CONCLUIDA; ciclo ≠ ENCERRADO/CANCELADO | gerente da cadeia |
| Acesso excepcional a conteúdo de terceiros | `evaluation.read` via C | evaluation (+cycleId) | C | somente leitura; ciclo obrigatório; A/B DENY + confidencial; 1 grant; janela | beneficiário do grant C; revogado/expirado ⇒ DENY |
| Avaliado ler avaliação (visão Minha Avaliação) | `evaluation.read` | evaluation (SELF) | SELF | CONCLUIDA + ciclo ≠ CANCELADO | avaliado |

### 7.3 Observações (quem pode criar/ver/editar/excluir/comunicar)

| Ação | Capability | Target | Scope | Regra | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Criar observação sobre colaborador | `observation.create` | observation (colaborador×ciclo) | DIRECT_REPORTS/DESCENDANTS | ciclo ATIVO; avaliado ≠ DESLIGADO | gerente/coordenador (na relação); avaliado: DENY |
| Editar observação | `observation.edit` ▸(add authorize) | observation | DIRECT_REPORTS/DESCENDANTS | ciclo ATIVO; autor/gestor no alcance | gerente/coordenador; demais: DENY |
| Excluir observação | `observation.delete` ▸(add authorize) | observation | DIRECT_REPORTS/DESCENDANTS | ciclo ATIVO; soft delete + histórico | gerente/coordenador |
| Marcar como `Comunicado` | `observation.edit` ▸ | observation | DIRECT_REPORTS/DESCENDANTS | decisão do gestor/coordenador | gestor/coordenador |
| Colaborador ver observações | leitura restrita (não é capability `observation.read` genérica para o avaliado) | observation (SELF, só ciclo) | SELF | **somente `comunicado=true`** do próprio ciclo; não-comunicadas invisíveis | avaliado (comunicadas); não-comunicadas: DENY mesmo SELF |

### 7.4 Metas

| Ação | Capability | Target | Scope | Regra | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Criar/editar/excluir/acompanhar/finalizar meta própria | `goal.create.own/edit.own/delete.own/progress.own/finalize.own` (base `goal.write`+SELF) | goal (owner SELF) | SELF | ciclo ATIVO; dono = ator; perfil com fluxos próprios (definição em Q3) | colaborador dono (não-gerente, conforme perfil funcional); gerente dono: ver Q3 |
| Aprovar meta (coordenador) | `goal.approve.coordinator` | goal | DIRECT_REPORTS | ciclo ATIVO; meta do subordinado | coordenador direto |
| Aprovar meta (gerente) | `goal.approve.manager` | goal | DESCENDANTS | ciclo ATIVO | gerente responsável na cadeia |
| Aprovar meta (colegiado) | `goal.approve` | goal | ASSIGNED | se a regra funcional prevê colegiado em metas (ver F4-04: `goal.*` não usa ASSIGNED de evaluation — Q) | colegiado só onde previsto; não vira hierarquia |
| Acompanhar metas de terceiro | `goal.view.admin` | goal | DIRECT_REPORTS/DESCENDANTS | ciclo ATIVO | gerente/coordenador no alcance |

### 7.5 Relatórios e dashboard

| Ação | Capability | Target | Scope | Regra | Quem pode / quem não pode |
|---|---|---|---|---|---|
| Ver relatórios | `report.view` | relatório (dataset colaboradores) | DIRECT_REPORTS (coordenador) / DESCENDANTS (gerente) | dataset limitado antes da agregação (§12); consolida só PRONTA_PARA_FEEDBACK/CONCLUIDA; coordenador só equipe direta (não colegiado) | gerente/coordenador no alcance; **ADMIN comum: DENY**; **D não cobre `report.view`**; C não abre relatório genérico |
| Dashboard/Início | `cycle.team.panel.view`/`goal.view.admin` | conforme | conforme §7.1/7.4 | dataset visível | conforme |

### 7.6 Escopo de colaboradores visíveis (base funcional)

- gerente: descendentes da cadeia (BFS por gestorDireto) — equivalente a
  DESCENDANTS;
- coordenador: subordinados diretos ∪ colegiado onde é avaliador (para
  operação/avaliação); em **relatório**: somente equipe direta;
- demais: `[]` (fail-closed);
- a F4-09 substitui `getColaboradoresVisiveis`/`authorizationPolicy` por
  providers do engine que derivam DIRECT_REPORTS/DESCENDANTS/ASSIGNED dos dados
  (gestorDireto + colegiado + histórico na data), **sem cargo**.

### 7.7 Origem de autorização e confidencialidade

- conteúdo de avaliação/feedback e observações não-comunicadas = **confidencial**
  (classificação soberana por domínio/probe `isTargetConfidential`); relatório
  consolidado = confidencial;
- A/B tentam primeiro; confidencial: A/B DENY ⇒ somente C (leitura, contrato
  F4-06); não-confidencial: A/B DENY ⇒ D possível (development only, F4-07);
  indeterminada ⇒ DENY;
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
- origem C/D só como fallback pontual quando A/B DENY (§8.2); erros públicos:
  cross-tenant/target inválido ⇒ NOT_FOUND; estado inválido ⇒ CONFLICT; demais ⇒
  FORBIDDEN.

### 8.1 Onde `authorize()` deve ser chamado (F4-09)

- Na **camada de serviço/use-case**, imediatamente antes da mutação e antes de
  retornar leitura crítica — nunca na UI;
- alvo/contexto resolvidos do **recurso carregado** (nunca `collaboratorId`/
  `evaluationId`/`cycleId`/`organizationId` do cliente); tenant derivado do
  recurso;
- TOCTOU: `can`/`listAllowedTargets` não substituem `authorize`; com F5, a
  revalidação ocorre na mesma RPC/transação (F4-03 D9) com RLS por linha;
- a F4-09 adiciona `authorize` onde hoje só existe `can` (marcado ▸ na §7), em
  especial: edição/exclusão de observação, abertura da página de edição de
  avaliação e leituras administrativas sensíveis.

### 8.2 Origens A/B, C, D

- A/B = membership → role → capability → scope (fonte real após F5; no mundo
  local, binding explícito de desenvolvimento — Q2);
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
temporalidade + confidencialidade avaliados juntos. Vale a mesma análise para
DIRECT_REPORTS/DESCENDANTS/UNIT/ORGANIZATION/ASSIGNED:

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
coordenador (sucessão F3-09); desligamento/licença (status do colaborador).

- relação atual **não concede automaticamente** acesso histórico sem regra
  explícita;
- relação passada **não continua concedendo** acesso atual (ex-gestor perde;
  substituição expira; desligamento remove);
- ciclo avaliativo é congelado (responsável/colegiado = F3-08/09);
- resolução sempre na **data de contexto explícita**.

## 11. Observações e feedback (análise explícita)

- conteúdo sensível: observações podem ser negativas sobre o colaborador; a
  visão do colaborador é **somente `comunicado=true`** do próprio ciclo
  (baseline/Issue #96) — não-comunicadas nunca chegam ao avaliado (nem mesmo
  SELF);
- criar: gestor/coordenador no alcance, ciclo ATIVO, avaliado ativo;
- editar/excluir: autorizado a gestor/coordenador no alcance, ciclo ATIVO, com
  `authorize` (hoje parcialmente só `can`);
- "marcar como comunicado": decisão de gestor/coordenador (ato de
  disponibilização ao avaliado);
- histórico/rastreabilidade: soft delete + `historico[]` + autores preservados;
- feedback final de gerente/coordenador e votos de colegiado são os campos mais
  sensíveis — nunca expostos por SELF antes de `CONCLUIDA` e nunca por
  agregação não autorizada (§12).

## 12. Relatórios e agregações

- `report.view` não está no bundle do ADMIN comum; D não cobre `report.view`;
  C não abre relatório como domínio genérico;
- **limitar o dataset antes da agregação** (limit-then-aggregate fail-closed):
  a consulta agrega sobre o conjunto de alvos autorizados (scopes do ator);
  sem scope ⇒ dataset vazio ⇒ agregado vazio;
- filtros/export herdam o dataset autorizado; contagens não revelam existência
  de dados confidenciais fora do alcance.

## 13. Ameaças a considerar (threat model e testes futuros)

IDOR; troca de `collaboratorId`/`evaluationId`/`cycleId`/`organizationId`;
manipulação de URL/query; chamada direta ao service/repository/API; enumeração;
acesso antecipado; acesso histórico indevido; ex-gestor; gestor fora do scope;
usuário comum tentando relatório gerencial; inferência de existência por erro;
manipulação de estado no frontend; localStorage adulterado; refresh/session
stale; capability removida durante a sessão; assignment removido; substituição
expirada; C revogado; D revogado.

## 14. Arquitetura de aplicação (fluxo seguro por operação)

1. **Entrada funcional** (page → hook → service): UI pede uma operação
   (capability) sobre um recurso;
2. **Service/use-case** (fronteira de aplicação) é o único executor e o único que
   chama o engine;
3. **Carregar o recurso** (storage/repositório) para derivar alvo/contexto; o
   tenant é derivado do recurso; nunca confiar em ids/org do cliente;
4. **`authorize`** no serviço imediatamente antes da operação (TOCTOU), com
   origens A/B→C/D conforme §8.2 e probe de domínio (estado) soberano;
5. **Persistir/retornar** após ALLOW; falha → erro público F0-05 (mutação) ou
   vazio/not-found genérico (leitura confidencial).

Evita: carregar confidencial antes de autorizar (quando carregar em si vaza,
usar predicação vazia/not-found); confiar em target/org do frontend; duplicar
autorização em UI; autorizar por cargo/nome; bypass por chamada direta.

## 15. F4-08 e F5

- **F4-09 protege agora:** fluxos funcionais localStorage pela invocação única do
  engine em cada operação, com contexto soberano (identidade + perfil +
  membership) e mundo local derivado dos dados (relação por gestorDireto/
  colegiado/histórico) — sem simular RLS.
- **Depende de F5:** RLS em tabelas funcionais e impossibilidade de bypass por
  chamada direta a API/banco. Quando os domínios migrarem, cada tabela funcional
  nasce com `ENABLE RLS` + policy por comando + `organization_id` + classificação
  D16 e revalidação atômica na RPC/transação (F4-03 D9).
- **Invariantes que devem sobreviver à migração:** avaliação só acessível com
  autorização explícita (idade não reduz confidencialidade); avaliado vê somente
  observações `comunicado`; colegiado (ASSIGNED) sem hierarquia; ADMIN sem leitura
  de confidencial sem grant excepcional; mutação respeita estado do ciclo/
  recurso; SELF restrito por estado; **nenhuma segunda regra paralela de
  autorização**.

## 16. Matriz de testes (desenho; priorizar NEGATIVOS)

Obrigatórios (refinados na implementação; decisões §18 e questões §17 pendentes
não bloqueiam a lista): funcionário A → avaliação de B = DENY; SELF antes da
liberação = DENY; SELF após liberação (quando permitido) = ALLOW; ex-gestor →
histórico indevido = DENY; gestor correto → recurso dentro do scope = ALLOW;
gestor → fora do scope = DENY; ID manipulado = DENY; C válido = ALLOW somente no
contrato C; C revogado = DENY; D válido somente onde permitido; D nunca abre
confidencial; D revogado = DENY; substituição válida = ALLOW na janela;
substituição expirada = DENY; assignment removido = DENY; capability removida =
DENY; relatório não vaza dados fora do dataset autorizado; usuário não
autorizado não enumera existência de avaliações; mutação direta sem UI = DENY;
observação não-comunicada invisível ao avaliado; ciclo cancelado bloqueia
criar/editar; colegiado não obtém hierarquia do avaliado; ADMIN comum não lê
confidencial; localStorage adulterado não concede (sem persistência real, o
enforcement é de aplicação — teste de regressão do gate único).

## 17. Questões para validação

Convenção do projeto: dúvida/ambiguidade/decisão de negócio **não é assumida
silenciosamente** — registrada abaixo. O desenho pode ser concluído e o PR
aberto mesmo com questões abertas; **a implementação não começa enquanto
decisões arquiteturais permanecerem abertas** (§18/§19).

1. **Q1 — Vocabulário de capabilities (drift 21 SQL × 36 runtime).**
   Contexto: catálogo SQL (F4-01) e `Capability.ts` quase disjuntos; runtime é a
   referência das F4-06/07 e do código. Decisão necessária: qual vocabulário
   governa a F4-09 e como reconciliar (espelhar runtime no catálogo? manter 2
   camadas com mapa explícito?). Alternativas: (a) alinhar o catálogo SQL ao
   runtime (granular, sem capability por papel); (b) derivar runtime do catálogo
   (perde granularidade funcional). Recomendação: (a) — unificar com
   capabilities de domínio.verbo genéricas (avaliar remover variantes
   `.manager/.coordinator/.board` que codificam papel — a F4 separa capability do
   quem). Impacto: migrations F4-01, providers, testes. Seções: §6.1(3), §7.
2. **Q2 — Origem de capability no mundo local (pré-F5).** Contexto: o engine
   exige capability de membership→role; hoje `localWorld` só dá `goal.write` e
   não há roles locais. Decisão: como o ambiente DEV/local concede capabilities
   funcionais sem reintroduzir cargo e sem simular F5? Alternativas: (a) binding
   local explícito por colaborador (rolo de "perfil de desenvolvimento") que o
   F5 substitui por membership do banco; (b) usar o perfil PILOT D como mundo de
   teste (não confidencial) + C para teste de confidencial. Recomendação: (a),
   marcado DEV-only com fail-closed fora de DEV; nenhum mapeamento funcao→
   capability em runtime. Impacto: §6.1(2,4), §8.2, §7. Seções: §7, §8.
3. **Q3 — SELF/metas e perfis com fluxos próprios.** Contexto: hoje
   `perfilPossuiFluxosPropriosAtuais` exclui GERENTE de metas próprias; "SELF não
   abre tudo" e a regra de negócio decide. Decisão: quais funções/perfis têm
   ciclo "Minhas Metas"/"Minha Avaliação" (e se o gerente é excluído por regra
   funcional, não por cargo de autorização). Recomendação: manter a regra
   funcional como domainState/probe e confirmar com negócio. Seções: §7.2/7.4,
   §9.
4. **Q4 — Liberação/publicação da avaliação ao avaliado.** Contexto: hoje o
   avaliado vê a avaliação só `CONCLUIDA`; existe `PRONTA_PARA_FEEDBACK` para
   consolidação. Decisão: qual é o marco de "liberação" e se o avaliado deve ter
   acesso em `PRONTA_PARA_FEEDBACK` (após feedback do gestor) ou apenas
   `CONCLUIDA`; notificação? Recomendação: confirmar com negócio; tratar o marco
   como estado no domainState (nunca "idade"). Seções: §4, §7.2, §9.
5. **Q5 — Acesso do gestor a avaliação histórica anterior à sua gestão.**
   Contexto: gestor atual, equipe assumida agora; contrato não prevê acesso
   retroativo automático. Decisão: negar por padrão ou permitir leitura
   administrativa com regra explícita (auditável)? Recomendação: DENY por padrão
   (histórico = snapshot congelado); ALLOW apenas com regra explícita de domínio.
   Seções: §4.1(4), §10.
6. **Q6 — Observações e relatórios como domínio no contrato C.** Contexto:
   F4-06 cobre piloto `evaluation.read`; relatório e observações não entram como
   domínio genérico em C. Decisão: manter fora de C nesta fase? Recomendação:
   sim (nada muda em C sem nova versão/contrato). Seções: §7.3/7.5, §8.2.
7. **Q7 — Encerramento com pendências e correção de período × autorização.**
   Contexto: regras de pendências/encerramento existem em serviço. Decisão: se
   todas as mutações de encerramento passam por authorize (capability +
   domainState) ou apenas domainState com capability administrativa já
   concedida. Recomendação: authorize + domainState; confirmar capability de
   encerramento no vocabulário (Q1). Seções: §7.1.

## 18. Decisões arquiteturais (fechadas neste desenho)

1. **D1 — Fronteira de aplicação primeiro.** A F4-09 aplica o Policy Engine aos
   domínios funcionais na camada de serviço (enforcement `authorize`) e usa
   `can` somente para UX; o RLS dos domínios funcionais é adiado a F5 (sem
   simular segurança de banco para localStorage). Fonte: F4-03 D5/D9, F4-08 D22,
   Issue #96.
2. **D2 — Substituir a superfície legada.** `authorizationPolicy.ts` (decisão por
   `funcao`) e helpers legados (`permissaoAvaliacao`, `visibilidadeColaboradores`,
   `aplicarEscopoRelatorio`, `podeAprovarMetaNoCiclo`) deixam de ser a fonte de
   decisão; a relação autorizadora passa a ser derivada de dados (gestorDireto +
   colegiado + histórico na data) via providers do engine. `legacyMap` permanece
   somente como artefato de regressão (nunca runtime). Fonte: F4-01 inv.1, F4-03
   D1/D2/D18.
3. **D3 — Mundo local (pré-F5) derivado dos dados, sem cargo.** O provider do
   mundo local resolve DIRECT_REPORTS/DESCENDANTS a partir da cadeia
   `gestorDiretoMatricula` e ASSIGNED a partir do colegiado/avaliadores na data
   (hoje `avaliadoresColegiadoMatriculas` + histórico; após F5, fontes F3-08/09).
   Nenhuma capability é derivada de `funcao`. Fonte: F4-04/05, F4-08 D1.
4. **D4 — SELF não abre conteúdo antes do estado.** SELF + capability + estado +
   temporalidade + confidencialidade avaliados conjuntamente: avaliação própria
   só liberada por estado (Q4); observações não-comunicadas invisíveis mesmo a
   SELF. Fonte: F4-03 pipeline, §4/§9 deste desenho.
5. **D5 — Capability × tipo de alvo em allowlist fechada.** Combinação não
   prevista ⇒ DENY (ex.: `evaluation.*` sobre alvo evaluation; `observation.*`
   não usa alvo de goal). Fonte: F4-04 D18.
6. **D6 — ASSIGNED não cria hierarquia nem wildcard.** Colegiado só sobre o
   alvo tipado atribuído; não concede metas/observações do avaliado. Fonte:
   F4-04/05, Issue #96.
7. **D7 — Confidencialidade soberana por domínio/probe.** Classificação
   (`isTargetConfidential`) decide C vs D; indeterminada ⇒ DENY; D nunca é
   fallback de confidencial; C fora de `listAllowedTargets`. Fonte: F4-06 D7,
   F4-07 D7/Q7.
8. **D8 — Grants C/D respeitam os contratos existentes.** C: leitura,
   `evaluation.read`, ciclo obrigatório, 1×1, janela; D: development-only,
   perfil versionado, ≤30 dias; revogação/expiração ⇒ efeito imediato. Fonte:
   F4-06, F4-07.
9. **D9 — Sem tabelas novas e sem novo DEFINER nesta fase.** A F4-09 é
   enforcement de aplicação + testes; nenhuma tabela C/D, nenhum SECURITY
   DEFINER, nenhum FORCE RLS. Fonte: F4-08 D9/D10/D22.
10. **D10 — Autorização administrativa de ciclo/avaliação exige relação, não
    cargo.** Criar/editar/cancelar/reabrir exige relação (gerente da cadeia /
    coordenador direto / colegiado) + capability + estado; ADMIN comum não lê
    confidencial sem C. Fonte: F4-01 D18, Issue #96.

## 19. Confirmações da atividade

Nenhum código funcional, nenhuma migration, nenhuma alteração de banco, nenhuma
policy RLS foi produzida — somente `docs/F4-09-desenho-tecnico.md`. Issue #96
permanece aberta; o PR é somente documentação e **não usa `Closes #96`**; **sem
merge**. A implementação da F4-09 começa somente após o merge da F4-08 (PR
#154) e após o fechamento das decisões pendentes (§17 Q1–Q7 e §18 itens que
dependerem de validação).

_Seções em aberto para revisão: §7 (matriz a validar contra Q1–Q7), §17 (Q1–Q7),
§18 (D1–D10)._
