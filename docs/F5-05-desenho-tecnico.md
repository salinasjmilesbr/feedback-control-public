# F5-05 — ActorContext / ResourceContext real (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de análise e desenho, sem código funcional**.
> Estado: **FECHADO — contrato pronto para implementação** (auditoria arquitetural
> independente incorporada; `Q1–Q5` **RESOLVIDAS** → §17; `D1–D23` **FECHADAS** → §16).
>
> Fase: 5 — Identidade e Multiusuário · Atividade: F5-05
> Base: `main` (F5-01, F5-02, F5-03 e F5-04 concluídas/mergeadas)
> Referência de limite: `docs/F5-04-desenho-tecnico.md` §11 e `docs/F5-01-desenho-tecnico.md` §9.2

---

## 1. Objetivo e limites

### 1.1 Objetivo

Definir o contrato real dos **contextos consumidos pelo Policy Engine** em runtime
autenticado, ligando os componentes soberanos já entregues:

```
identidade (F5-01) + organização ativa (F5-03) + membership (F5-01)
  + collaborator vinculado (F5-02) + roles/capabilities/scopes (F5-04)
        → ActorContext

recurso carregado (tenant/owner/atributos)
        → ResourceContext

ActorContext + ResourceContext + capability pretendida
        → Policy Engine (F4-03)
        → ALLOW / DENY
```

A F5-05 responde, no nível de contrato: **o que exatamente é o ator**, **o que
exatamente é o recurso** na fronteira de autorização, **de onde cada dado vem**
(nunca do cliente), **onde e em que ordem os contextos são montados** e **como o
Policy Engine os consome**.

### 1.2 Origem do escopo desta atividade

O contrato já reservava a F5-05 para isto (não é reabertura de decisão):

- **F5-01 §9.2:** “F5-05 (ActorContext): única porta de entrada do `ActorRef` real
  no Policy Engine; nenhuma página monta `ActorRef`; `actorId = auth.uid()`
  (perfil), com resolução do colaborador vinculado dentro dos providers por
  `(actorId, organizationId)`”.
- **F5-01 §9.1:** esboço de `interface ActorContext { identity, organizationId,
  toActorRef() }` — a F5-05 o concretiza.
- **F5-04 §11:** “**F5-05:** montar `ActorContext`/`ResourceContext` — instanciar
  o provider real no engine com `actorId=auth.uid()` + org validada + vínculo,
  carregar recursos por tenant e alimentar `authorize()/can()` reais”.
- **F5-03 D13:** `ActorContext` consumirá `(auth.uid, org validada)`; a
  apresentação do colaborador vinculado foi **diferida para a F5-05** (fechada em
  §17/Q5 → D23).

**Escopo confirmado (resolve Q1 → §17):** `F5-05 = ActorContext / ResourceContext`,
conforme os contratos F5 já fechados. A antiga Issue **#102** (“[F5-05] db(goal):
migrar metas”) está fechada como `not_planned` e é **artefato de roadmap
anterior**; **não é reaberta** e **não altera o escopo técnico** desta atividade.
Eventual migração de metas terá **código/atividade próprios** quando for
replanejada.

### 1.3 O que a F5-05 entrega (contrato)

1. Definição dos campos/conceitos de `ActorContext` e `ResourceContext` e das
   **origens soberanas** de cada um.
2. Invariantes de montagem, ordem de resolução, fail-closed e **fronteira
   confiável server-side**.
3. Contrato de integração com o Policy Engine (entrada, providers, resultado,
   `authorize()`/`can()`).
4. Garantias de multitenancy/anti-IDOR, revogação/freshness e fronteira com RLS.
5. Limite explícito do mundo híbrido (legado `localStorage` × persistência
   soberana) — §1.4 e D19.
6. Impactos esperados, estratégia de testes e critérios de aceite da futura
   implementação.

### 1.4 Fora de escopo (F5-05)

- Reescrever o Policy Engine (F4-03) ou seus contratos de providers;
- alterar agentes de decisão já fechados: capabilities/scopes (F4-01/02/04/05),
  origem **B** temporária (F4-05), origem **C** excepcional (F4-06), origem **D**
  Pilot (F4-07), RLS (F4-08), catálogo/vocabulário (F5-04);
- **migrar os domínios funcionais** (ciclos, avaliações, metas, observações,
  colaboradores) de `localStorage` para persistência server-side — atividade
  própria; a F5-05 apenas **declara a fronteira transitória** e implementa o
  contrato real onde já há persistência soberana (D19);
- **criar wrapper/adapter/abstração que transforme dado do `localStorage` em
  autoridade** — proibido (D19); caminhos legados permanecem **legados/
  transitórios** até a migração;
- UI (telas/indicadores de contexto), observabilidade externa e hardening geral
  (F6);
- plano administrativo/controle (conceder/revogar roles), que permanece no RPC
  server-side da F5-04 (§13/D18);
- implementação de código nesta rodada.

---

## 2. Estado atual (inventário verificado)

### 2.1 Policy Engine — contrato de entrada já fechado (F4-03)

`src/authorization/policyEngine/types.ts` e `policyEngine.ts` já definem:

```ts
interface ActorRef { actorId: string; organizationId: string }

interface AuthorizationRequest {
  actor: ActorRef;
  capability: Capability;      // ação pretendida (código fechado)
  target: TargetRef;           // tipo+id do alvo
  context: { date: Date; cycleId?: string };
  domainState?: DomainStateProbe; // ausente ⇒ DENY (INDETERMINATE)
}
```

Pipeline determinística implementada (`decidir`): identidade → profile →
membership → **tenant do alvo derivado do recurso** (`resolveTargetTenant`) →
capability (membership ⊕ temporária) → compatibility capability×target → scope ×
relação → data → `domainState` → ALLOW. `authorize()` lança em DENY; `can()`
retorna a decisão; `listAllowedTargets()` é **auxiliar** (nunca fonte de decisão).

Providers contratados (interfaces em `types.ts`): `identity`, `capabilities`,
`scopes`, `targets`, `relations` (+ opcionais `temporary` B, `exceptional` C,
`pilot` D). O engine é **agnóstico ao significado de `actorId`** (string opaca
usada coerentemente).

### 2.2 Providers atuais — mundo DEV (pré-F5)

- `src/authorization/mundoFuncional.ts` — `criarProvidersMundoFuncional` deriva
  providers dos **dados do seed local** + `bindingsDev` (binding DEV-only
  derivado da **estrutura**, nunca de `funcao`), com
  `organizationId = LOCAL_ORGANIZATION_ID` (tenant sintético único) e
  `actorId = String(matricula)`.
- `src/authorization/providers/localWorld.ts`, `structure.ts`,
  `structuralRelation.ts`, `assigned.ts`, `temporary.ts`, `exceptional.ts`,
  `pilot.ts` — núcleos puros já testados (F4-04…F4-07) que a F5-05 reutiliza com
  **outra fonte de dados**.
- `src/authorization/autorizacaoFuncional.ts` e `authorizationPolicy.ts` —
  fachadas de compatibilidade que montam o ator a partir do colaborador DEV e
  delegam ao engine. `authorizationPolicy.ts` usa alvos sintéticos em alguns
  casos (ex.: `{ type: "cycle", id: "global" }`) — evidência para D22 (§16).
  **Atenção:** esses módulos executam no **browser** e são **cliente**, não
  fronteira confiável (D20).
- `src/authorization/ResourceContext.ts` — **tipos de recurso de aplicação**
  (`global`, `collaborator-list`, `cycle`, `collaborator`, `evaluation`, `goal`,
  `observation`) usados pelas fachadas; **não** há ainda um `ResourceContext`
  real com tenant/owner/estado derivados de persistência.

### 2.3 Camada de autenticação/identidade (F5-01/02/03) — já implementada

- `src/auth/controladorSessao.ts` — máquina de sessão com estados
  `verificando | naoAutenticado | autenticado | semOrganizacao |
  aguardandoSelecao | sessaoIndisponivel | acessoNegado | indisponivel |
  sessaoExpirada`; identidade resolvida via `resolverIdentidade` (perfil ativo +
  memberships ativas + organizações derivadas).
- `src/auth/tipos.ts` — `AuthIdentity` (= `IdentidadeResolvida`), com
  `authUserId === perfil.id`, `perfil.status === "active"`, memberships somente
  ativas; `ColaboradorVinculado` (F5-02) com `membership`, `linkId`,
  `colaboradorId`, `organizationId`.
- `src/auth/contratos.ts` — portas `RepositorioIdentidade` e
  `VinculoIdentityResolver.resolverColaborador(authUserId, organizationId)`
  (contrato F5-02; sem implementação runtime/executável pelo frontend).
- `src/auth/organizacaoAtiva.ts` — organização ativa = **intenção de UX**;
  `organizacaoEfetiva` deriva N (0 ⇒ null; 1 ⇒ implícita; >1 ⇒ selecionada
  válida, senão null); persistência local é conveniência, nunca prova.
- `src/auth/AuthProvider.tsx` — expõe `organizacaoAtivaId`,
  `organizacoesDisponiveis`, `selecionarOrganizacao`, `organizacaoVersao`
  (dados de sessão/UX; **não** é fronteira de autorização — D20).

### 2.4 Autorização real de roles/capabilities (F5-04) — já implementada

- Catálogo canônico DB (29 códigos não-deprecados) + espelho TS
  (`catalogoCapabilities.ts`), com fail-closed para código desconhecido.
- Resolvers `resolver_capabilities_efetivas(user_profile, org)` e
  `resolver_capabilities_escopos_efetivas(user_profile, org)` — `EXECUTE`
  somente `service_role`, chamadas **por operação** no servidor (D17: sem cache
  de ALLOW entre requisições).
- Plano administrativo separado (D15) e RPCs `conceder_acesso_role_rpc` /
  `revogar_acesso_role_rpc` com **ator verificado server-side**
  (`p_actor_user_profile_id` vindo de `auth.getUser` na Edge Function) +
  `usuario_eh_administrador` + trilha append-only (D18) — **este é o padrão de
  fronteira confiável server-side** que a F5-05 generaliza (D20).
- Nenhum arquivo TS consome os resolvers reais ainda — é exatamente o que a
  F5-05 liga.

### 2.5 Gap objetivo

Não existe hoje, no runtime autenticado:

1. um **ActorContext real** (identidade+org validada+membership+vínculo) que
   produza o `ActorRef` **em fronteira confiável server-side**;
2. um **ResourceContext real** (recurso carregado com tenant/owner/atributos e
   `domainState`) que produza o `TargetRef` — apenas para recursos com
   persistência soberana (D19/D22);
3. **providers reais** ligados ao banco (membership/roles/capabilities/scopes/
   estrutura) no lugar do mundo DEV.

---

## 3. Fronteira conceitual e fronteira de confiança

### 3.1 Contexto de aplicação × contrato do engine

Termos que **não** podem ser confundidos (evita duplicação de autorização):

| Camada | Conceito | Papel | Não é |
| --- | --- | --- | --- |
| Aplicação (server) | **ActorContext** | Agrega quem é o ator (identidade, org validada, membership, vínculo) e produz o `ActorRef` | O `AuthorizationRequest`; estado global de UI; binding DEV |
| Engine (F4-03) | **ActorRef** | `{ actorId, organizationId }` — identidade+tenant usados na pipeline | Fonte de capability/scope (isto vem dos providers) |
| Aplicação (server) | **ResourceContext** | Representa o **recurso carregado**: tenant proprietário, owner/subject, atributos de scope e `domainState`; produz `TargetRef` | Permissão; decisão de autorização |
| Engine (F4-03) | **TargetRef** | `{ type, id }` — referência tipada do alvo usada na pipeline | Objeto de domínio completo |

Regra: **a aplicação monta contexto; o engine decide.** Nenhuma camada de
aplicação (página, componente, hook, service de domínio) reimplementa a decisão.

### 3.2 Fronteira confiável server-side (definição inequívoca — D20)

> **FRONTEIRA CONFIÁVEL SERVER-SIDE** = **Edge Function / RPC / backend confiável
> equivalente** que revalida **`auth.uid()`, tenant, membership e recurso no
> servidor**.
>
> **Browser / React / hooks / `localStorage` / client SDK / `src/services/*`
> executado no browser** = **CLIENTE NÃO CONFIÁVEL** para concessão de autoridade.

Consequências contratuais:

1. **Enforcement** (`authorize()`) e a **montagem do `ActorContext`/`ActorRef`**
   usados como prova ocorrem **exclusivamente na fronteira confiável
   server-side**, **por operação** (D20);
2. o cliente **nunca** monta, recebe como prova, nem reutiliza `ActorRef`/
   `ResourceContext` para autorizar;
3. qualquer `ActorRef`/contexto que exista no browser é **projeção não soberana**
   para **UX** e **jamais** é aceito por `authorize()` como prova;
4. o contrato **não fixa** uma tecnologia única (Edge Function × RPC × backend
   equivalente) onde os contratos anteriores não a fixaram; a **fronteira de
   confiança** é o que precisa ser inequívoca;
5. o padrão já implementado na F5-04 (Edge Function + RPC com ator verificado) é
   a referência de fronteira para o plano administrativo e o modelo a generalizar
   no plano funcional.

**Proibição explícita:** tratar `src/services/*`, hooks ou código TypeScript
executado no browser como “server-side”, ou como fonte de prova de identidade,
tenant, membership, role, capability ou escopo.

---

## 4. ActorContext real

### 4.1 Campos/conceitos

```ts
interface ActorContext {
  /** Snapshot de identidade (F5-01): authUserId, perfil ativo, memberships ativas, organizações. */
  readonly identity: AuthIdentity;
  /** Organização em uso — intenção (F5-03) VALIDADA contra membership ativa. */
  readonly organizationId: string;
  /** Membership ativa que ancora a organização em uso (1 por org). */
  readonly membership: MembershipAutenticada;
  /** Vínculo (F5-02) — OPICIONAL; null = sem colaborador (ex.: ADMIN). */
  readonly collaboratorId: string | null;
  /** Contrato do engine (derivado; D2/D7). */
  toActorRef(): ActorRef; // { actorId: identity.authUserId, organizationId }
}
```

**Não fazem parte do `ActorContext`** (e o porquê):

- **capabilities/scopes materializados** — resolvidos pelos providers **por
  operação** (F5-04 D5/D17); um snapshot envelheceria e violaria “revogação
  efetiva na operação subsequente” (D10);
- **origens B/C/D** — permanecem providers independentes do engine (F5-04 D12);
- **role/claims/estado de UI/matrícula** — nunca são autoridade;
- **nome/`displayName`/avatar/apresentação** — preocupação de **UX/perfil**, não
  de identidade soberana nem de autorização (D23); `collaboratorId` só existe
  quando necessário a relações/scopes.

O `ActorContext` de **enforcement** é construído **na fronteira confiável
server-side, por operação** (D20); nenhuma página/componente o monta ou o recebe
como prova.

### 4.2 Origem soberana de cada informação

| Informação | Origem soberana | Caminho (fronteira confiável) | Nunca |
| --- | --- | --- | --- |
| `authUserId` | Supabase Auth (`auth.uid()` / `auth.getUser`) | sessão JWT validada **no servidor** | `user.id` de estado de UI, claims, e-mail, `localStorage` |
| Perfil (existência/status) | `public.user_profiles` sob RLS | `resolverIdentidade` (F2/F5-01) no servidor | status informado pelo cliente |
| Memberships ativas | `public.user_organization_memberships` sob RLS | `buscarMembershipsAtivas` no servidor | lista/`localStorage` |
| Organizações disponíveis | derivadas das memberships ativas | `buscarOrganizacoes` no servidor | seleção do cliente |
| `organizationId` em uso | **intenção** do cliente **validada** contra membership ativa | `organizacaoEfetiva` + revalidação server-side por operação | org “provada” por payload/JWT/`localStorage` |
| `membership` | a membership ativa correspondente à org em uso | derivação do snapshot no servidor | id de membership enviado pelo cliente |
| `collaboratorId` | `membership_collaborator_links` (F5-02) via `resolver_collaborador_vinculado` | `(authUserId, organizationId)` no servidor | matrícula, e-mail, nome, cargo |
| capabilities/scopes | `public.capabilities`/roles/scopes (F4-01/02) via resolvers (F5-04) | por operação, no servidor | role/capability do cliente |

### 4.3 O que **não** pode vir do cliente (proibição explícita)

`actorId`/`user_profile_id`, `organization_id` como prova, `membership_id`,
`collaborator_id`/matrícula como identidade, roles/capabilities/scopes, claims do
JWT como autorização, qualquer “organização ativa” persistida no cliente, e
**qualquer `ActorRef`/contexto montado no browser**. O cliente transporta
**intenção e identificadores de recurso** (§6.6), nunca prova.

### 4.4 Invariantes

1. `identity.authUserId === identity.perfil.id` e `perfil.status === "active"`;
2. `organizationId` ∈ organizações disponíveis do snapshot (senão não há ator);
3. `membership.organizationId === organizationId` e `membership.status === "active"`;
4. `collaboratorId` é `null` quando não há vínculo ativo — e isso **não** é erro
   (ADMIN): apenas escopos estruturais ficam vazios (F5-02 D6/D11);
5. `toActorRef().actorId === identity.authUserId`; **nunca** matrícula;
6. o contexto é **por-request e imutável** (não é mutado por páginas);
7. `capabilities`/`scopes` **não** são campos do contexto (§4.1);
8. o contexto de **enforcement** só existe/é consumido na **fronteira confiável
   server-side** (D20).

---

## 5. ResourceContext real

### 5.1 O que caracteriza um recurso

O `ResourceContext` é a representação de aplicação do **recurso efetivamente
carregado** por fonte **server-side soberana**, suficiente para que o engine
decida:

```ts
interface ResourceContext {
  readonly kind: ResourceKind;               // tipo do recurso (ver 5.5)
  readonly target: TargetRef;                // tipo+id do alvo no engine
  readonly organizationId: string;           // tenant DO RECURSO — OBRIGATÓRIO (D22)
  readonly ownerCollaboratorId: string | null; // subject/owner quando aplicável
  readonly structure: ResourceStructure;     // atributos p/ scope (posição, unidade, reporting)
  readonly domainState: DomainStateProbe;    // predicados de domínio (estado atual)
  readonly cycleId?: string;                 // quando o recurso pertence a ciclo
}
```

`organizationId` é **obrigatório/não-null** para todo recurso autorizável pelo
Policy Engine (D22): recursos sem tenant soberano **não são** autorizáveis via
engine.

### 5.2 Tenant proprietário

Derivado **sempre do próprio recurso carregado** (coluna `organization_id` / FK
composta do tenant), **de fonte server-side**, nunca do `organizationId` do
caller nem da organização ativa por si só. O engine confirma igualdade com o ator
(`targetTenant !== actor.organizationId ⇒ CROSS_TENANT`); a montagem já deve
falhar antes disso quando o recurso não pertence ao tenant (§5.6).

### 5.3 Owner/subject

- **Com owner/subject:** avaliação (avaliado), meta (dono), observação
  (colaborador), colaborador (o próprio) — necessário para SELF, ASSIGNED,
  relações e `domainState`.
- **Sem owner/subject:** ciclo (recurso de tenant), unidade/posição (estrutura),
  relatórios (agregado) — o alvo é o próprio recurso e a decisão depende de
  scope/relação/estado do tenant.
- Recursos cujo subject não possui membership/conta (colaborador sem login) são
  normais: **colaborador ≠ conta** (F5-01 §4, F5-02 D4); o vínculo só existe
  quando há membership (F5-02 D2).

### 5.4 Atributos necessários para decisões de scope

- **Posição/ocupação na data** (para SELF/DIRECT_REPORTS/DESCENDANTS), unidade
  (ORGANIZATIONAL_UNIT), reporting line e histórico temporal — fonte é a
  estrutura F3; o `RelationProvider` real consome os resolvers F3-07/F4-02;
- **Ciclo** e snapshot quando a decisão é de ciclo (contexto congelado × vivo —
  F4-03 §12 / F4-02 D9);
- **Estado do domínio** (`domainState`) — predicados do domínio, não regra de
  autorização (F4-03 §13).

### 5.5 Diferenças entre recursos

| Classe | Exemplos | Tenant | Owner/subject | Autorizável pelo engine? |
| --- | --- | --- | --- | --- |
| Tenant-rooted com subject | avaliação, meta, observação | coluna do recurso (server) | colaborador | **Sim** — escopo SELF/ASSIGNED/DIRECT_REPORTS/DESCENDANTS |
| Tenant-rooted sem subject | ciclo | coluna do recurso (server) | — | **Sim** — escopo ORGANIZATION; `domainState` do ciclo |
| Estrutural | colaborador, posição, unidade | coluna do recurso (server) | colaborador/posição | **Sim** — escopo por relação F3 |
| Agregado/derivado | relatório | coluna (server) | — | **Sim** — decisão por scope + capability |
| **Global/informativo** (sem tenant) | catálogo de capabilities, configuração global | **nenhum** | — | **Não** — fora da decisão funcional do engine (D22); sujeito às proteções próprias de persistência/RLS |
| **Legado/transitório** (`localStorage`) | ciclos, avaliações, metas, observações, colaboradores ainda sem persistência server-side | **indeterminado no servidor** | — | **Não** — não produz `ResourceContext` soberano (D19); permanece **legado/transitório** até a migração |

### 5.6 Recurso inexistente, inválido ou de outro tenant

Comportamento **fail-closed** obrigatório:

- **inexistente/inacessível** ⇒ o servidor **não** monta `ResourceContext` e
  **não** chama o engine para decidir ALLOW; a operação falha com erro público
  genérico (`NOT_FOUND` quando o ator não deve saber da existência), conforme
  F4-03 §14;
- **inconsistente** (tenant ausente, FK órfã, owner inexistente) ⇒
  `TARGET_INVALID`/DENY, sem heurística;
- **de outro tenant** ⇒ DENY (`CROSS_TENANT` → público `NOT_FOUND`/`FORBIDDEN`),
  sem vazar existência;
- **sem tenant soberano** (global ou legado) ⇒ **não é autorizável** pelo engine
  (D19/D22): não se inventa tenant, não se cria alvo sintético;
- **nunca** “carregar com tenant do ator para tentar autorizar” — o recurso de
  outro tenant não se torna autorizável por reinterpretação.

---

## 6. Construção dos contextos

### 6.1 Onde são montados

- **ActorContext de enforcement:** construído **na fronteira confiável
  server-side** (Edge Function / RPC / backend equivalente — D20), **por
  operação**, a partir da sessão validada (`auth.uid()`), da identidade (F5-01),
  da organização ativa validada (F5-03) e do vínculo (F5-02).
- **ResourceContext:** construído **no servidor** (mesma fronteira), a partir do
  recurso carregado **de fonte soberana** — preferencialmente no mesmo serviço/
  transação que carrega o dado para a operação.
- **Proibido:** montar/enviar `ActorRef`/`ResourceContext` do browser como prova;
  páginas/hooks/`src/services` no browser **não** são fronteira confiável (D20) e
  **não** montam contexto de enforcement.
- **UX:** o frontend pode consumir uma **fachada/adapter de `can()`** ou
  resultados derivados de autorização; o que existir no browser é **projeção não
  soberana** (D20).

### 6.2 Consultas/fontes

| Contexto | Fonte (server-side) |
| --- | --- |
| ActorContext | sessão (auth), `user_profiles`, `user_organization_memberships`, `membership_collaborator_links` (F5-02) |
| Providers de capability/scope | `resolver_capabilities_efetivas` / `resolver_capabilities_escopos_efetivas` (F5-04) |
| Providers de relação/target | resolvers F3-07/F3-09/F4-02 (estrutura, reporting, occupations, scopes, unit targets) |
| ResourceContext | repositório do domínio **com persistência soberana** + `domainState` do domínio |

### 6.3 Ordem de resolução (na fronteira confiável, por operação)

```
1. sessão válida (auth.uid)                         ── F5-01
2. perfil ativo                                      ── F5-01 (fail-closed)
3. memberships ativas                                ── F5-01/F5-03
4. organização em uso validada (intenção → membership ativa)  ── F5-03
5. vínculo do colaborador (0..1) para (auth.uid, org) ── F5-02 (opcional)
6. ActorContext / ActorRef                            ── F5-05 (server)
7. carregamento do recurso soberano (tenant/owner/estado) ── domínio (server)
8. ResourceContext / TargetRef + domainState          ── F5-05 (server)
9. capability pretendida (ação)                       ── chamador
10. engine: providers reais por operação              ── F5-04 + F4
11. ALLOW / DENY (authorize lança; can retorna)
```

Qualquer falha em 1–8 ⇒ **contexto não montado** ⇒ operação negada (não se
“chuta” contexto para o engine decidir). Passos 6–8 e 10 ocorrem **no servidor**.

### 6.4 Fail-closed

- ausência de qualquer elo ⇒ contexto inválido ⇒ DENY;
- erro técnico na resolução ⇒ DENY (erro público da taxonomia F0-05);
- `date` ausente ⇒ DENY (`INDETERMINATE`, F4-03);
- `domainState` ausente/indeterminado ⇒ DENY;
- recurso sem tenant soberano ⇒ **não autorizável** (D19/D22);
- nenhum default permissivo, nenhum fallback por omissão.

### 6.5 Dados inconsistentes/incompletos

Perfil inativo, membership inativa/ausente, vínculo `disabled`/inexistente
(⇒ `collaboratorId = null`, não é erro), recurso sem tenant, capability fora do
catálogo (⇒ DENY por D14 F5-04). Divergência entre snapshots (ex.: org em uso não
mais disponível) ⇒ re-resolução e, se ainda divergente, DENY.

### 6.6 Fronteira client/server

| Transportável pelo cliente (intenção) | Nunca transportável (prova) |
| --- | --- |
| organização pretendida (F5-03) | `actorId`/`user_profile_id` “provando” quem é |
| id/tipo do recurso alvo (rota, formulário) | `organization_id` como prova de tenant |
| **data de negócio** explícita quando o domínio exigir (validada no servidor — D21) | timestamp soberano da decisão/autorização |
| estado de UI/UX | role/capability/scope |
| — | membership/collaborator id como identidade; qualquer `ActorRef` do browser |

O servidor **revalida** a intenção contra o estado persistido sob RLS/`auth.uid()`
(F5-01 §5.2; F5-03 D6/D8).

---

## 7. Integração com o Policy Engine

### 7.1 Contrato de entrada

O engine **não muda** (F4-03). A F5-05 produz exatamente o `AuthorizationRequest`
já contratado, **na fronteira confiável**:

```
ActorContext → request.actor      (ActorRef)
capability   → request.capability (ação pretendida; catálogo F5-04)
ResourceContext → request.target      (TargetRef)
ResourceContext → request.context     ({ date, cycleId })
ResourceContext → request.domainState (DomainStateProbe)
```

**Data de decisão × data de negócio (D21):**

- `context.date` é o **instante soberano da decisão/autorização** (“agora”),
  proveniente **exclusivamente do relógio server-side confiável**; o cliente
  **não** escolhe esse timestamp;
- uma **data de negócio** pode ser enviada como **intenção/parâmetro funcional**
  quando o domínio exigir (ex.: correção retroativa autorizada); ela é
  **validada server-side** e **não substitui** o instante soberano da decisão;
- se a implementação precisar distinguir semanticamente ambos, isso é feito
  **sem alterar o contrato do engine** nesta rodada (nenhuma incompatibilidade
  comprovada que o exija).

### 7.2 Relação dos contextos com a ação

- a **capability** é pedida pelo chamador (a ação pretendida) e **nunca** é
  declarada como possuída; a posse vem do provider real (F5-04);
- o **alvo** vem do recurso carregado **no servidor** (nunca do cliente);
- o **tenant** é conferido pelo engine a partir do alvo
  (`resolveTargetTenant`), reforçando a montagem server-side.

### 7.3 Scopes e origens

- scopes (SELF/DIRECT_REPORTS/DESCENDANTS/ORGANIZATIONAL_UNIT/ORGANIZATION) e
  seus alvos vêm das assignments ativas (F4-02/F5-04) + relação estrutural F3;
- **ASSIGNED** continua resolvido pela origem de colegiado/avaliação
  (F4-04/F4-05), nunca derivado de hierarquia;
- **B** (temporária, F4-05), **C** (excepcional, F4-06) e **D** (pilot, F4-07)
  permanecem **origens independentes** avaliadas pelo engine, com seus guards —
  a F5-05 apenas garante que o `ActorRef` real (`actorId = auth.uid()`) é o mesmo
  que essas origens já assumem (`beneficiaryUserProfileId`).

### 7.4 Resultado

`AuthorizationDecision { allowed, denial{reason, publicCode}, diagnostics }`;
`reason`/`diagnostics` são internos; a UI recebe apenas o código público (F0-05)
— e `CROSS_TENANT` vira `NOT_FOUND`/`FORBIDDEN` sem vazar existência.

### 7.5 `authorize()` × `can()`

- **`authorize()`** = enforcement: chamado **na fronteira confiável server-side**
  imediatamente antes da mutação, com o contexto montado no servidor;
- **`can()`** = UX: predicação para habilitar/ocultar, **nunca** enforcement; no
  browser é **projeção não soberana** (D20);
- ambos compartilham `decidir()` (mesma pipeline) — a paridade é estrutural, não
  uma segunda implementação;
- ocultação de UI jamais substitui `authorize()` (regra permanente).

---

## 8. Multi-tenancy

1. **Anti-IDOR/cross-tenant:** o tenant do alvo deriva do recurso carregado
   (§5.2); `actor.organizationId` deriva da membership ativa (§4.2); divergência
   ⇒ DENY. IDs de outro tenant não são “reinterpretados” para o tenant do ator.
2. **Organização ativa:** intenção de UX validada; sem seleção válida não há
   `ActorContext` (estado `aguardandoSelecao` — F5-03 D3/D12).
3. **Membership válida:** pré-condição de operação no tenant; revogada/inativa ⇒
   DENY e re-derivação de estado (F5-01 D4, F5-03 D7).
4. **Recurso do tenant:** carregado sob RLS/consulta server-side; recurso de
   outro tenant é indistinguível de inexistente para efeito de resposta.
5. **Divergências:** qualquer inconsistência (org do recurso ≠ org do ator,
   membership ausente, vínculo de outra org) ⇒ DENY fail-closed, com log interno
   — nunca correção silenciosa.
6. **Recurso sem tenant soberano:** não autorizável (D19/D22) — não se cria
   tenant sintético para “passar” pelo engine.

---

## 9. Revogação e freshness

- **Nenhum cache de ALLOW entre requisições** (F5-04 D17; F4-03 D12): cada
  operação re-resolve identidade/membership/vínculo/capability/scope **na
  fronteira confiável**.
- **Cache permitido:** apenas **intra-requisição** — reutilizar a mesma leitura
  dentro da **mesma** operação/transação (ex.: resolver capabilities uma vez para
  avaliar várias capabilities na MESMA operação) é aceitável **desde que** não
  atravesse o limite da requisição nem o ponto de mutação.
- **Revogação efetiva na operação subsequente:** revogar role/assignment,
  desativar role/capability, desativar membership/vínculo e rebaixar perfil
  cortam a autorização na próxima operação (F4-01/F4-02 lifecycle; F5-04 D8).
- **TOCTOU:** entre a checagem (T0) e a mutação (T2), revogação ⇒ a operação em
  T2 deve DENY; quando a persistência for server-side, a revalidação e a mutação
  devem ser **atômicas na mesma transação/RPC** (F4-03 D9; F4-08 D7).
- **Troca de organização:** invalida contexto/dados do tenant anterior (F5-03 D9).
- **Projeção de UX no browser:** pode ficar defasada até a próxima revalidação;
  isso **não** afeta a decisão (que é sempre server-side) — nunca é prova.

---

## 10. Relação com RLS

| Pergunta | Responde | Escopo |
| --- | --- | --- |
| “Esta identidade autenticada pode tocar dados deste tenant?” | **RLS** (F4-08) | fronteira estrutural de tenant, por linha/tabela |
| “Esta identidade pode executar esta capability sobre este recurso?” | **Policy Engine** (F4-03) | autorização funcional fina |

- RLS **não concede capability**; o engine **não substitui** o isolamento de
  banco (F4-08 §1.2);
- RLS não implementa DIRECT_REPORTS/DESCENDANTS/ASSIGNED/scopes (F4-08 D5);
- a F5-05 não abre policies, não cria superfície nova a `authenticated` e não
  cria `SECURITY DEFINER`;
- a montagem do `ResourceContext` respeita a RLS: leituras **server-side** sob RLS
  (ou `service_role` em caminho confiável) — nunca leitura ampla no cliente;
- leitura **informativa** de catálogo/global continua sujeita às proteções
  próprias de persistência/RLS (não é decisão funcional do engine — D22).

---

## 11. Impactos esperados na implementação (não implementar agora)

**Fronteira confiável (obrigatória para enforcement):**

- **Edge Function / RPC / backend equivalente** para montar `ActorContext` e
  `ResourceContext` de enforcement e executar `authorize()` — a F5-05 não fixa
  qual tecnologia; fixa que a **fronteira é server-side** (D20).

**Prováveis módulos afetados:**

- `src/auth/*` — a **projeção de UX** derivada de identidade/organização; **sem**
  expor `ActorRef` bruto no `AuthProvider` sem necessidade demonstrável (D20);
- `src/authorization/autorizacaoFuncional.ts` / `authorizationPolicy.ts` —
  fachadas de compatibilidade: passam a consumir decisões **derivadas** do
  contexto real, permanecendo no browser apenas como **UX**; a superfície por
  cargo continua proibida em runtime;
- serviços de domínio **com persistência soberana** — carregar `ResourceContext`
  e autorizar na fronteira server-side;
- `src/authorization/ResourceContext.ts` — evoluir de tipos de recurso de
  aplicação para o contrato real (tenant **obrigatório**, owner, estado).

**Novos módulos/abstrações provavelmente necessários:**

- montagem do `ActorContext`/`ActorRef` na fronteira server-side;
- providers reais (capabilities, scopes, targets, relations) consumindo os
  resolvers F5-04/F4-02/F3-07;
- montagem/normalização de `ResourceContext` para recursos com persistência
  soberana.

Nenhuma linha de código nesta rodada.

---

## 12. Estratégia de testes da futura implementação

| Grupo | Cenários |
| --- | --- |
| Happy path | ator com membership ativa + capability + scope + relação + `domainState` ⇒ ALLOW |
| Spoofing de contexto | `actorId`/`organization_id`/`role`/`capability` enviados pelo cliente ⇒ **sem efeito**; payload com capability desconhecida ⇒ DENY |
| **Fronteira de confiança** | `ActorRef`/contexto do browser (React/hook/`localStorage`/`src/services`) ⇒ **nunca** aceito como prova por `authorize()`; enforcement exige contexto montado server-side (D20) |
| **Mundo híbrido/legado** | domínio ainda em `localStorage` **não** produz `ResourceContext` soberano; nenhum wrapper converte dado local em autoridade (D19) |
| **Recursos globais** | recurso sem tenant soberano **não** é autorizável pelo engine; nenhum tenant sintético; `{type:"cycle", id:"global"}` não autoriza (D22) |
| **Data de decisão × data de negócio** | “agora” vem do servidor; data de negócio do cliente é validada e não substitui o instante soberano (D21) |
| Cross-tenant | ator de A tentando recurso de B (id direto, filtro, rota, lista) ⇒ DENY/`NOT_FOUND`, sem vazar existência |
| Membership inválida/inativa | membership `disabled`, perfil inativo, sem membership na org ⇒ DENY |
| Role/capability revogada | revogação entre operações ⇒ DENY na seguinte (sem logout); reativação ⇒ volta a permitir |
| Recurso inexistente | alvo inexistente/inacessível ⇒ DENY sem ALLOW por omissão |
| Recurso de outro tenant | inclui recurso filho/indireto (FK poisoning) e alvo composto |
| Scopes | SELF/DIRECT_REPORTS/DESCENDANTS/UNIT/ORGANIZATION e ASSIGNED; vaga não corrompe cadeia; sem vínculo ⇒ estruturais vazios |
| DENY fail-closed | ausência de data/`domainState`/tenant/contexto ⇒ DENY |
| Paridade `can` × `authorize` | para cada mutação, `authorize()` usa o mesmo contexto de `can()`; divergência ⇒ falha de teste |
| Origens B/C/D | independentes e não “turbinadas” pelo contexto (C só com A/B DENY e confidencial; D dev-only, nunca confidencial) |
| ADMIN sem colaborador | contexto válido, `collaboratorId = null`, escopos estruturais vazios, sem confidencial |

Complementos obrigatórios: validação SQL/Supabase local quando a implementação
tocar RLS/resolvers; regressão dos validadores F4/F5 existentes.

---

## 13. Compatibilidade com F5-01/02/03/04 e contratos F4

- **F5-01 (identidade):** `ActorContext` consome `AuthIdentity`; invariantes
  preservadas (authUserId = perfil = auth.uid; perfil ativo; memberships ativas).
- **F5-02 (vínculo):** `collaboratorId` resolvido por
  `(authUserId, organizationId)`; sem vínculo ⇒ null (ADMIN), escopos estruturais
  vazios. Nenhuma superfície nova executável pelo frontend.
- **F5-03 (organização ativa):** intenção validada; sem estado server-side de
  “org ativa” (D5); revalidação por operação (D6); cross-tenant DENY (D8).
- **F5-04 (roles/capabilities):** catálogo DB canônico; resolução por operação;
  sem cache de ALLOW; plano administrativo/controle **fora** do `ActorContext`
  (permanece RPC server-side com ator verificado — D15/D16, referência de
  fronteira confiável para D20).
- **F4-03 (engine):** contrato de entrada/saída inalterado; `authorize`/`can`/
  `listAllowedTargets` mantidos; a distinção “data de decisão × data de negócio”
  (D21) é documentada **sem** alterar o contrato nesta rodada.
- **F4-04/F4-05/F4-06/F4-07:** relações/hierarquia, temporária, excepcional e
  pilot seguem como providers/origens independentes; a F5-05 só troca a fonte de
  dados (DEV → real) via a mesma interface.
- **F4-08 (RLS):** fronteira preservada; nenhuma policy nova; nenhuma redução de
  controle.
- **F4-09 (aplicação funcional):** as fachadas permanecem porta de **UX**; o
  enforcement passa a exigir contexto montado na fronteira confiável.

---

## 14. Critérios de aceite (da futura implementação)

1. `ActorContext` real montado **na fronteira confiável server-side, por
   operação**, a partir de identidade (F5-01) + org validada (F5-03) + membership
   + vínculo (F5-02); `actorId = auth.uid()`;
2. `ResourceContext` real com **tenant obrigatório** derivado do recurso + owner/
   atributos + `domainState`, produzindo `TargetRef` válido;
3. cliente nunca fornece prova de identidade/tenant/role/capability/scope —
   inclusive **nenhum `ActorRef`/contexto do browser é aceito por `authorize()`**;
4. cross-tenant/IDOR ⇒ DENY fail-closed (incl. filhos/indiretos);
5. nenhum cache de ALLOW entre requisições; revogação efetiva na operação
   subsequente;
6. origens B/C/D preservadas como providers independentes;
7. RLS preservada como barreira independente; sem nova superfície a
   `authenticated`; sem `SECURITY DEFINER` novo;
8. `authorize()` é enforcement e usa o mesmo contexto de `can()` (paridade);
9. ADMIN sem colaborador: contexto válido, escopos estruturais vazios;
10. **fronteira do mundo híbrido declarada**: domínios ainda em `localStorage`
    permanecem legados/transitórios, **sem** wrapper que transforme dado local em
    autoridade; o contrato real é implementado onde já há persistência soberana;
11. **recursos globais/informativos sem tenant não são autorizáveis** pelo engine
    (nenhum tenant sintético);
12. **instante da decisão** vem do relógio server-side; **data de negócio** é
    intenção validada e não substitui o instante soberano;
13. regressão F4/F5 verde (test/build/lint/diff-check + validadores SQL
    aplicáveis).

---

## 15. Riscos

| Risco | Mitigação |
| --- | --- |
| Cliente “montando” contexto (spoofing) | contexto só na fronteira server-side; cliente transporta intenção (D4/D6/D20) |
| **Browser confundido com server-side** | definição inequívoca de fronteira (D20) + teste dedicado (§12) |
| Divergência entre `can()` e `authorize()` | mesma pipeline `decidir()` + testes de paridade (§12) |
| Stale de privilégio | sem cache de ALLOW entre requisições; resolução por operação (D10) |
| IDOR por recurso de outro tenant | tenant do recurso + `CROSS_TENANT` DENY sem vazar existência (§8) |
| Duplicação de autorização em serviços/páginas | engine como única decisão; fachadas apenas UX (§3) |
| **Mundo híbrido mascarando “real”** | limite explícito + proibição de wrapper (D19; §5.5) |
| Tenant sintético para “passar” no engine | recursos globais não autorizáveis (D22) |
| Data de negócio usada como instante da decisão | relógio server-side soberano; data de negócio validada (D21) |
| Origens C/D “turbinadas” pelo contexto | providers independentes; guards F4-06/07 (D11) |
| Apresentação acoplada à autorização | `displayName`/avatar fora do ActorContext (D23) |
| Confusão ActorContext × ActorRef | fronteira conceitual (§3.1, D7) |

---

## 16. Decisões arquiteturais (D1–D23 — todas FECHADAS)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | ActorContext = única porta do ActorRef real | Nenhuma página/componente monta `ActorRef`; a montagem de enforcement é da fronteira confiável server-side (F5-01 §9.2) | FECHADA |
| D2 | `actorId` soberano | `actorId = identity.authUserId = user_profile.id = auth.uid()`; nunca matrícula/e-mail (F5-01 D1/D7) | FECHADA |
| D3 | `organizationId` = org ativa validada | Intenção de UX (F5-03) revalidada contra membership ativa; sem seleção válida não há contexto (F5-03 D1/D3/D12) | FECHADA |
| D4 | Montagem server-side | `ActorContext`/`ResourceContext` são montados na fronteira confiável server-side; o cliente só transporta intenção (F5-01 D6/§5.2; D20) | FECHADA |
| D5 | Capabilities/scopes vêm da F5-04 | Resolvidos dos resolvers canônicos do DB por operação; nunca do cliente/estado (F5-04 D2/D5) | FECHADA |
| D6 | Tenant do recurso derivado do recurso | Coluna/FK do próprio recurso carregado, de fonte server-side; nunca do `organizationId` do caller (F4-03 §5/§10; F4-08 D1) | FECHADA |
| D7 | ActorContext ≠ ActorRef; ResourceContext ≠ TargetRef | Contexto de aplicação produz o contrato do engine; o engine consome `ActorRef`/`TargetRef` (§3.1) | FECHADA |
| D8 | Cross-tenant/inexistente ⇒ DENY | Fail-closed com código público sem vazar existência (F4-03 §14; regras permanentes) | FECHADA |
| D9 | Fail-closed universal | Ausência/indeterminação/erro ⇒ DENY; nenhum default permissivo (F4-03 §3.3) | FECHADA |
| D10 | Sem cache de ALLOW entre requisições | Resolução por operação; revogação efetiva na operação subsequente (F5-04 D17; F4-03 D12) | FECHADA |
| D11 | B/C/D permanecem providers independentes | Não viram campos do ActorContext nem capabilities “concedidas” pelo contexto (F5-04 D12; F4-05/06/07) | FECHADA |
| D12 | Engine F4-03 inalterado | F5-05 alimenta o `AuthorizationRequest`/providers existentes; nenhuma reescrita (F4-03 D1/D5) | FECHADA |
| D13 | `authorize()` = enforcement; `can()` = UX | Mesma pipeline `decidir()`; ocultação de UI não autoriza (F4-03 D5; regras permanentes) | FECHADA |
| D14 | ADMIN sem colaborador | Contexto válido com `collaboratorId = null`; escopos estruturais vazios; sem confidencial (F5-02 D6/D11; F5-04 D11; F4-02 D17) | FECHADA |
| D15 | Contexto por-request e imutável | Sem singleton; páginas não mutam; re-resolução é o único caminho de atualização (F5-01 D13) | FECHADA |
| D16 | Fronteira RLS × engine preservada | RLS = tenant boundary; engine = autorização funcional; nenhum substitui o outro (F4-08 §1.2/D5/D12) | FECHADA |
| D17 | Data/hora de decisão | `context.date` = instante soberano do **relógio server-side**; nunca do cliente (F4-03 §12/D13) | FECHADA |
| D18 | Plano administrativo fora do ActorContext | Conceder/revogar roles permanece no RPC server-side com ator verificado (F5-04 D15/D16) | FECHADA |
| D19 | Mundo híbrido — limite declarado (resolve Q2) | `ActorContext` é **real** (identidade/membership/org/vínculo/roles/capabilities/scopes/estrutura têm fonte soberana); `ResourceContext` é **real apenas** para recursos cujo tenant, subject/owner e estado derivem de fonte server-side soberana. Domínios ainda **apenas em `localStorage`** (ciclos, avaliações, metas, observações e afins) **não** produzem `ResourceContext` soberano e permanecem **legados/transitórios** até a migração; **proibido** wrapper/adapter que transforme dado local em autoridade; a F5-05 **não é bloqueada** por isso — implementa o contrato real onde há persistência confiável e declara a fronteira transitória | FECHADA |
| D20 | Fronteira confiável server-side inequívoca (resolve Q3) | **FRONTEIRA CONFIÁVEL SERVER-SIDE = Edge Function / RPC / backend confiável equivalente** que revalida `auth.uid()`, tenant, membership e recurso **no servidor**. **Browser/React/hooks/`localStorage`/client SDK/`src/services` executado no browser = cliente não confiável.** Enforcement e a montagem do `ActorRef` de prova ocorrem **por operação** na fronteira confiável; nenhuma página/componente recebe `ActorRef` como prova; para UX, o browser pode consumir fachada/adapter de `can()` ou resultados derivados, sempre **projeção não soberana** nunca reutilizada por `authorize()`; **não** expor `ActorRef` bruto no `AuthProvider` sem necessidade demonstrável | FECHADA |
| D21 | Data de decisão × data de negócio (ajuste B) | O **instante da decisão/autorização** vem **exclusivamente do relógio server-side confiável**; o cliente **não** escolhe o timestamp soberano. Uma **data de negócio** pode ser enviada como **intenção/parâmetro funcional** quando o domínio exigir, **validada server-side**, e **não substitui** o instante soberano; eventual distinção semântica no engine é documentada **sem** alterar seu contrato nesta rodada (salvo incompatibilidade comprovada) | FECHADA |
| D22 | Recursos globais não autorizáveis; `organizationId` obrigatório (resolve Q4) | Recursos globais/informativos **não** são transformados em `TargetRef` tenant-scoped; **não** se cria tenant sintético/global; `{ type: "cycle", id: "global" }` (e equivalentes) **não** é autorização real; gates funcionais usam recurso **real tenant-rooted**; leitura puramente informativa de catálogo/global fica fora da decisão funcional e sujeita às proteções de persistência/RLS. Consequência: para recursos **autorizáveis**, `ResourceContext.organizationId` é **obrigatório/não-null**. Caso real futuro de autorização funcional sobre recurso global ⇒ **nova decisão arquitetural** (não antecipar) | FECHADA |
| D23 | Apresentação fora do ActorContext (resolve Q5) | `displayName`/nome/avatar **não** pertencem ao `ActorContext` de autorização; `collaboratorId` existe **somente** quando necessário a relações/scopes; apresentação é preocupação de **UX/perfil** e **não** participa da identidade soberana nem da decisão. Separação explícita entre identidade, autorização e apresentação | FECHADA |

---

## 17. Questões de auditoria — Q1–Q5 RESOLVIDAS (FECHADAS)

> Cada questão foi **respondida na auditoria arquitetural independente** e
> incorporada como decisão fechada ou como esclarecimento contratual. Mantidas
> abaixo para rastreabilidade. **Nenhuma questão permanece aberta.**

### Q1 — Numeração/escopo de “F5-05” (Issue #102) — **FECHADA (alternativa A)**

- **Contexto:** a Issue **#102** (“[F5-05] db(goal): migrar metas, limites e
  histórico para PostgreSQL”) está fechada como `not_planned` e rotula “F5-05 —
  Metas no PostgreSQL”; os contratos F5-01 §1.2/§9.2 e F5-04 §11 definem
  **F5-05 = ActorContext / ResourceContext**.
- **Decisão (A):** manter `F5-05 = ActorContext / ResourceContext`, conforme os
  contratos F5 já fechados; tratar a Issue #102 como **artefato de roadmap
  anterior**; **não reabrir** a Issue #102; **não alterar** o escopo técnico
  desta atividade por causa dela; eventual migração de metas terá **código/
  atividade próprios** quando replanejada.
- **Impacto:** nomenclatura de Issue/branch/PR; **nenhum impacto técnico**.
- **Seções dependentes:** §1.2.

### Q2 — Mundo híbrido / `localStorage` — **FECHADA (alternativa A — D19)**

- **Contexto:** ciclos, avaliações, metas, observações e colaboradores ainda
  vivem apenas em `localStorage` (F4-03 §1.3/§10; F4-08 §1.3; F5-04 §16); um
  `ResourceContext` “real” exige tenant derivado do recurso (D6), impossível
  server-side para dado que vive no cliente.
- **Decisão (A — D19), explícita:** `ActorContext` é **real** (identidade,
  membership, organização, vínculo, roles/capabilities/scopes e estrutura têm
  fonte soberana); `ResourceContext` é **real apenas** para recursos cujo tenant,
  subject/owner e estado derivem de **fonte server-side soberana**; os domínios
  mantidos apenas em `localStorage` **não** produzem `ResourceContext` soberano e
  permanecem **legados/transitórios** até a migração; **não** criar wrapper/
  adapter/abstração que transforme dado local em autoridade; **não** bloquear a
  F5-05 inteira — implementar o contrato real onde já há persistência confiável e
  **declarar explicitamente** a fronteira transitória.
- **Impacto:** escopo da implementação e critérios de aceite (§14.10); risco de
  falsa sensação de “real” mitigado pela declaração explícita.
- **Seções dependentes:** §1.4, §5.5, §6.2, §11, §12, §14, D19.

### Q3 — Disponibilização do ActorContext — **FECHADA (alternativa A — D20)**

- **Contexto:** F5-01 §9.2 proíbe “página monta `ActorRef`”, mas não definia o
  mecanismo; havia ambiguidade sobre código TS/serviços no browser.
- **Decisão (A — D20), com precisão:** enforcement constrói `ActorContext`/
  `ActorRef` **por operação** em **fronteira confiável server-side** (Edge
  Function / RPC / backend equivalente); **`src/services/*`, hooks, React e
  código executado no browser são CLIENTE**, não fronteira confiável; nenhuma
  página/componente recebe/monta `ActorRef` como prova; para **UX**, o frontend
  pode consumir **fachada/adapter de `can()`** ou resultados derivados, sendo
  qualquer `ActorRef` no browser **projeção não soberana** nunca reutilizada por
  `authorize()`; **evitar** expor `ActorRef` bruto no `AuthProvider` sem
  necessidade demonstrável; preservar D1, D4, D13 e as trust boundaries.
- **Impacto:** arquitetura de injeção e testabilidade; elimina o risco de ator de
  UI usado como prova.
- **Seções dependentes:** §3.2, §6.1, §6.6, §7.5, §11, §12, §14, D20.

### Q4 — Recursos globais sem tenant — **FECHADA (alternativa A — D22)**

- **Contexto:** o engine exige derivar o tenant do alvo (`undefined ⇒
  TARGET_INVALID` — F4-03 §10/§14), mas há recursos globais e o código legado usa
  alvos sintéticos (`{ type: "cycle", id: "global" }`).
- **Decisão (A — D22):** recursos globais/informativos **não** são artificialmente
  transformados em `TargetRef` tenant-scoped; **não** criar tenant sintético;
  `{ type: "cycle", id: "global" }` **não** é autorização real; gates funcionais
  usam recurso **real tenant-rooted**; leitura puramente informativa de
  catálogo/global fica fora da decisão funcional (proteções próprias de
  persistência/RLS). Consequência: `ResourceContext.organizationId` é
  **obrigatório/não-null** para recursos autorizáveis. Caso real futuro ⇒ **nova
  decisão**, sem antecipar.
- **Impacto:** contrato de `ResourceContext`; limpeza de gates legados.
- **Seções dependentes:** §5.1, §5.5, §5.6, §8, §10, §12, §14, D22.

### Q5 — Apresentação do colaborador vinculado — **FECHADA (alternativa A — D23)**

- **Contexto:** F5-01 D14/Q5 mantiveram o nome pelo e-mail até a F5-02; F5-02 D4
  fixou que colaborador **não** identifica a conta; **F5-03 D13 diferiu a
  apresentação do collaborator para a F5-05**.
- **Decisão (A — D23):** `displayName`/nome/avatar **não** pertencem ao
  `ActorContext` de autorização; `collaboratorId` existe **somente** quando
  necessário a relações/scopes; apresentação é preocupação de **UX/perfil** e não
  participa da identidade soberana nem da decisão; separação explícita entre
  identidade, autorização e apresentação.
- **Impacto:** campos do `ActorContext`; telas seguem pelo e-mail/`user_profile`
  até atividade de UX própria.
- **Seções dependentes:** §4.1, §11, D23.

---

## 18. Confirmações desta atividade

- **Nenhuma implementação funcional**: não houve alteração de código, migration,
  teste, contrato existente, navegação/UI ou configuração; apenas
  `docs/F5-05-desenho-tecnico.md` foi criado/atualizado.
- Estado final: **FECHADO — contrato pronto para implementação**; `Q1–Q5`
  **RESOLVIDAS** (§17) e `D1–D23` **FECHADAS** (§16); **nenhuma pergunta aberta**
  e **nenhuma incompatibilidade arquitetural concreta** remanescente.
- Contratos F4 e F5 anteriores **preservados**; nenhuma decisão fechada reaberta;
  nenhuma premissa inventada (as decisões de auditoria foram incorporadas como
  recebidas).
- Próximo passo (após merge do desenho): implementação da F5-05 em PR próprio,
  seguindo o contrato fechado — **não** iniciada aqui.
