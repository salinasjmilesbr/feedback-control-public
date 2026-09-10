# F5-05 — ActorContext / ResourceContext real (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de análise e desenho, sem código funcional**.
> Estado: **PROPOSTA para revisão arquitetural** — decisões `D1–D19` com status
> explícito; **Q1–Q5 ABERTAS** (§17) — **não implementar antes de fechá-las**.
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
  toActorRef() }` — a F5-05 o concretiza/ajusta.
- **F5-04 §11:** “**F5-05:** montar `ActorContext`/`ResourceContext` — instanciar
  o provider real no engine com `actorId=auth.uid()` + org validada + vínculo,
  carregar recursos por tenant e alimentar `authorize()/can()` reais”.
- **F5-03 D13:** `ActorContext` consumirá `(auth.uid, org validada)`; a
  apresentação do colaborador vinculado foi **diferida para a F5-05** (§17/Q5).

### 1.3 O que a F5-05 entrega (contrato)

1. Definição dos campos/conceitos de `ActorContext` e `ResourceContext` e das
   **origens soberanas** de cada um.
2. Invariantes de montagem, ordem de resolução, fail-closed e fronteira
   client/server.
3. Contrato de integração com o Policy Engine (entrada, providers, resultado,
   `authorize()`/`can()`).
4. Garantias de multitenancy/anti-IDOR, revogação/freshness e fronteira com RLS.
5. Impactos esperados, estratégia de testes e critérios de aceite da futura
   implementação.

### 1.4 Fora de escopo (F5-05)

- Reescrever o Policy Engine (F4-03) ou seus contratos de providers;
- alterar agentes de decisão já fechados: capabilities/scopes (F4-01/02/04/05),
  origem **B** temporária (F4-05), origem **C** excepcional (F4-06), origem **D**
  Pilot (F4-07), RLS (F4-08), catálogo/vocabulário (F5-04);
- **migrar os domínios funcionais** (ciclos, avaliações, metas, observações,
  colaboradores) de `localStorage` para Postgres — a migração é atividade
  própria; a F5-05 apenas define como o contexto se comporta no mundo resultante
  (ver §17/Q2);
- UI (inclusive telas/indicadores de contexto), visualização de contexto,
  observabilidade externa e hardening geral (F6);
- plano administrativo/controle (conceder/revogar roles) que permanece no RPC
  server-side da F5-04 (§13/D16);
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
  casos (ex.: `{ type: "cycle", id: "global" }`) — evidência relevante para §17/Q4.
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
  `organizacoesDisponiveis`, `selecionarOrganizacao`, `organizacaoVersao`.

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
  `usuario_eh_administrador` + trilha append-only (D18).
- Nenhum arquivo TS consome os resolvers reais ainda — é exatamente o que a
  F5-05 liga.

### 2.5 Gap objetivo

Não existe hoje, no runtime autenticado:

1. um **ActorContext real** (identidade+org validada+membership+vínculo) que
   produza o `ActorRef`;
2. um **ResourceContext real** (recurso carregado com tenant/owner/atributos e
   `domainState`) que produza o `TargetRef`;
3. **providers reais** ligados ao banco (membership/roles/capabilities/scopes/
   estrutura) no lugar do mundo DEV.

---

## 3. Fronteira conceitual: contexto de aplicação × contrato do engine

Termos que **não** podem ser confundidos (evita duplicação de autorização):

| Camada | Conceito | Papel | Não é |
| --- | --- | --- | --- |
| Aplicação | **ActorContext** | Agrega quem é o ator (identidade, org validada, membership, vínculo) e produz o `ActorRef` | O `AuthorizationRequest`; estado global de UI; binding DEV |
| Engine (F4-03) | **ActorRef** | `{ actorId, organizationId }` — identidade+tenant usados na pipeline | Fonte de capability/scope (isto vem dos providers) |
| Aplicação | **ResourceContext** | Representa o **recurso carregado**: tenant proprietário, owner/subject, atributos de scope e `domainState`; produz `TargetRef` | Permissão; decisão de autorização |
| Engine (F4-03) | **TargetRef** | `{ type, id }` — referência tipada do alvo usada na pipeline | Objeto de domínio completo |

Regra: **a aplicação monta contexto; o engine decide.** Nenhuma camada de
aplicação (página, componente, hook, service de domínio) reimplementa a decisão.

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
  /** Contrato do engine (derivado; ver D2/D7). */
  toActorRef(): ActorRef; // { actorId: identity.authUserId, organizationId }
}
```

**Não fazem parte do `ActorContext`** (e o porquê):

- **capabilities/scopes materializados** — resolvidos pelos providers **por
  operação** (F5-04 D5/D17); um snapshot envelheceria e violaria “revogação
  efetiva na operação subsequente” (D10);
- **origens B/C/D** — permanecem providers independentes do engine (F5-04 D12);
- **role/claims/estado de UI/matrícula** — nunca são autoridade.

### 4.2 Origem soberana de cada informação

| Informação | Origem soberana | Caminho | Nunca |
| --- | --- | --- | --- |
| `authUserId` | Supabase Auth (`auth.uid()` / `auth.getUser`) | sessão validada no servidor | `user.id` de estado de UI, claims, e-mail |
| Perfil (existência/status) | `public.user_profiles` sob RLS | `resolverIdentidade` (F2/F5-01) | status informado pelo cliente |
| Memberships ativas | `public.user_organization_memberships` sob RLS | `buscarMembershipsAtivas` | lista/localStorage |
| Organizações disponíveis | derivadas das memberships ativas | `buscarOrganizacoes` | seleção do cliente |
| `organizationId` em uso | **intenção** do cliente **validada** contra membership ativa | `organizacaoEfetiva` + revalidação server-side por operação | org “provada” por payload/JWT/localStorage |
| `membership` | a membership ativa correspondente à org em uso | derivação do snapshot | id de membership enviado pelo cliente |
| `collaboratorId` | `membership_collaborator_links` (F5-02) via `resolver_collaborador_vinculado` | `(authUserId, organizationId)` | matrícula, e-mail, nome, cargo |
| capabilities/scopes | `public.capabilities`/roles/scopes (F4-01/02) via resolvers (F5-04) | por operação, `service_role` | role/capability do cliente |

### 4.3 O que **não** pode vir do cliente (proibição explícita)

`actorId`/`user_profile_id`, `organization_id` como prova, `membership_id`,
`collaborator_id`/matrícula como identidade, roles/capabilities/scopes, claims
do JWT como autorização, e qualquer “organização ativa” persistida no cliente.
O cliente transporta **intenção e identificadores de recurso** (§6.6), nunca
prova.

### 4.4 Invariantes

1. `identity.authUserId === identity.perfil.id` e `perfil.status === "active"`;
2. `organizationId` ∈ organizações disponíveis do snapshot (senão não há ator);
3. `membership.organizationId === organizationId` e `membership.status === "active"`;
4. `collaboratorId` é `null` quando não há vínculo ativo — e isso **não** é erro
   (ADMIN): apenas escopos estruturais ficam vazios (F5-02 D6/D11);
5. `toActorRef().actorId === identity.authUserId`; **nunca** matrícula;
6. o contexto é **por-request e imutável** (não é mutado por páginas);
7. `capabilities`/`scopes` **não** são campos do contexto (§4.1).

---

## 5. ResourceContext real

### 5.1 O que caracteriza um recurso

O `ResourceContext` é a representação de aplicação do **recurso efetivamente
carregado** pelo serviço, suficiente para que o engine decida:

```ts
interface ResourceContext {
  readonly kind: ResourceKind;               // tipo do recurso (ver 5.5)
  readonly target: TargetRef;                // tipo+id do alvo no engine
  readonly organizationId: string | null;    // tenant DO RECURSO (coluna do recurso)
  readonly ownerCollaboratorId: string | null; // subject/owner quando aplicável
  readonly structure: ResourceStructure;     // atributos p/ scope (posição, unidade, reporting)
  readonly domainState: DomainStateProbe;    // predicados de domínio (estado atual)
  readonly cycleId?: string;                 // quando o recurso pertence a ciclo
}
```

### 5.2 Tenant proprietário

Derivado **sempre do próprio recurso carregado** (coluna `organization_id` /
FK composta do tenant), nunca do `organizationId` do caller nem da organização
ativa por si só. O engine confirma igualdade com o ator
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
  (ORGANIZATIONAL_UNIT), reporting line e histórico temporal — a fonte é a
  estrutura F3; o `RelationProvider` real consome os resolvers F3-07/F4-02;
- **Ciclo** e snapshot quando a decisão é de ciclo (contexto congelado × vivo —
  F4-03 §12 / F4-02 D9);
- **Estado do domínio** (`domainState`) — predicados do domínio, não regra de
  autorização (F4-03 §13).

### 5.5 Diferenças entre recursos

| Classe | Exemplos | Tenant | Owner/subject | Observação |
| --- | --- | --- | --- | --- |
| Tenant-rooted com subject | avaliação, meta, observação | coluna do recurso | colaborador | escopo SELF/ASSIGNED/DIRECT_REPORTS/DESCENDANTS |
| Tenant-rooted sem subject | ciclo | coluna do recurso | — | escopo ORGANIZATION; `domainState` do ciclo |
| Estrutural | colaborador, posição, unidade | coluna do recurso | colaborador/posição | escopo por relação F3 |
| Agregado/derivado | relatório | coluna | — | decisão por scope + capability; sem persistência própria |
| **Global** (sem tenant) | catálogo de capabilities, configuração global | **nenhum** | — | ver §17/Q4 — hoje há alvos sintéticos no código legado |
| Sem persistência real | domínios ainda em `localStorage` | **indeterminado** | — | ver §17/Q2 (limite explícito da F5-05) |

### 5.6 Recurso inexistente, inválido ou de outro tenant

Comportamento **fail-closed** obrigatório:

- **inexistente/inacessível** ⇒ o serviço **não** monta `ResourceContext` e
  **não** chama o engine para decidir ALLOW; a operação falha com erro público
  genérico (`NOT_FOUND` quando o ator não deve saber da existência), conforme
  F4-03 §14;
- **inconsistente** (tenant ausente, FK órfã, owner inexistente) ⇒
  `TARGET_INVALID`/DENY, sem heurística;
- **de outro tenant** ⇒ DENY (`CROSS_TENANT` → público `NOT_FOUND`/`FORBIDDEN`),
  sem vazar existência;
- **nunca** “carregar com tenant do ator para tentar autorizar” — o recurso de
  outro tenant não se torna autorizável por reinterpretação.

---

## 6. Construção dos contextos

### 6.1 Onde são montados

- **ActorContext:** na **camada de serviço/adaptação server-side**, derivado da
  sessão/identidade (F5-01), da organização ativa validada (F5-03) e do vínculo
  (F5-02). Nenhuma página/componente monta `ActorRef` (F5-01 §9.2).
- **ResourceContext:** no **serviço do domínio** que carrega o recurso — o mesmo
  que já carrega o dado para a operação (evita uma segunda fonte de verdade e
  mantém a decisão próxima do dado).
- Ambas as montagens são **por operação** (não há singleton de contexto).

### 6.2 Consultas/fontes

| Contexto | Fonte |
| --- | --- |
| ActorContext | sessão (auth), `user_profiles`, `user_organization_memberships`, `membership_collaborator_links` (F5-02) |
| Providers de capability/scope | `resolver_capabilities_efetivas` / `resolver_capabilities_escopos_efetivas` (F5-04) |
| Providers de relação/target | resolvers F3-07/F3-09/F4-02 (estrutura, reporting, occupations, scopes, unit targets) |
| ResourceContext | repositório do próprio domínio (tenant/owner/estado) + `domainState` do domínio |

### 6.3 Ordem de resolução

```
1. sessão válida (auth.uid)                         ── F5-01
2. perfil ativo                                      ── F5-01 (fail-closed)
3. memberships ativas                                ── F5-01/F5-03
4. organização em uso validada (intenção → membership ativa)  ── F5-03
5. vínculo do colaborador (0..1) para (auth.uid, org) ── F5-02 (opcional)
6. ActorContext / ActorRef                            ── F5-05
7. carregamento do recurso pelo serviço (tenant/owner/estado) ── domínio
8. ResourceContext / TargetRef + domainState          ── F5-05
9. capability pretendida (ação)                       ── chamador
10. engine: providers reais por operação              ── F5-04 + F4
11. ALLOW / DENY (authorize lança; can retorna)
```

Qualquer falha em 1–7 ⇒ **contexto não montado** ⇒ operação negada (não se
“chuta” contexto para o engine decidir).

### 6.4 Fail-closed

- ausência de qualquer elo ⇒ contexto inválido ⇒ DENY;
- erro técnico na resolução ⇒ DENY (erro público da taxonomia F0-05);
- `date` ausente ⇒ DENY (`INDETERMINATE`, F4-03);
- `domainState` ausente/indeterminado ⇒ DENY;
- nenhum default permissivo, nenhum fallback por omissão.

### 6.5 Dados inconsistentes/incompletos

Perfil inativo, membership inativa/ausente, vínculo `disabled`/inexistente
(⇒ `collaboratorId = null`, não é erro), recurso sem tenant, capability fora do
catálogo (⇒ DENY por D14 F5-04). Divergência entre snapshots (ex.: org em uso
não mais disponível) ⇒ re-resolução e, se ainda divergente, DENY.

### 6.6 Fronteira client/server

| Transportável pelo cliente (intenção) | Nunca transportável (prova) |
| --- | --- |
| organização pretendida (F5-03) | `actorId`/`user_profile_id` “provando” quem é |
| id/tipo do recurso alvo (rota, formulário) | `organization_id` como prova de tenant |
| data de negócio explícita quando a operação exigir | role/capability/scope |
| estado de UI/UX | membership/collaborator id como identidade |

O servidor **revalida** a intenção contra o estado persistido sob RLS/`auth.uid()`
(F5-01 §5.2; F5-03 D6/D8).

---

## 7. Integração com o Policy Engine

### 7.1 Contrato de entrada

O engine **não muda** (F4-03). A F5-05 produz exatamente o `AuthorizationRequest`
já contratado:

```
ActorContext → request.actor      (ActorRef)
capability   → request.capability (ação pretendida; catálogo F5-04)
ResourceContext → request.target      (TargetRef)
ResourceContext → request.context     ({ date, cycleId })
ResourceContext → request.domainState (DomainStateProbe)
```

### 7.2 Relação dos contextos com a ação

- a **capability** é pedida pelo chamador (a ação pretendida) e **nunca** é
  declarada como possuída; a posse vem do provider real (F5-04);
- o **alvo** vem do recurso carregado (nunca do cliente);
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
`reason`/`diagnostics` são internos; a UI recebe apenas o código público
(F0-05) — e `CROSS_TENANT` vira `NOT_FOUND`/`FORBIDDEN` sem vazar existência.

### 7.5 `authorize()` × `can()`

- **`authorize()`** = enforcement: chamado pela camada de serviço imediatamente
  antes da mutação, com o mesmo contexto do `can()`;
- **`can()`** = UX: predicação para habilitar/ocultar, **nunca** enforcement;
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

---

## 9. Revogação e freshness

- **Nenhum cache de ALLOW entre requisições** (F5-04 D17; F4-03 D12): cada
  operação re-resolve identidade/membership/vínculo/capability/scope.
- **Cache permitido:** apenas **intra-requisição** — reutilizar a mesma leitura
  dentro da mesma operação/transação (ex.: resolver capabilities uma vez para
  avaliar várias capabilities na MESMA operação) é aceitável **desde que** não
  atravesse o limite da requisição/o ponto de mutação. Detalhe do limite
  intra-request em §17/Q3-adjacente (registrado como pendência de precisão).
- **Revogação efetiva na operação subsequente:** revogar role/assignment,
  desativar role/capability, desativar membership/vínculo e rebaixar perfil
  cortam a autorização na próxima operação (F4-01/F4-02 lifecycle; F5-04 D8).
- **TOCTOU:** entre a checagem (T0) e a mutação (T2), revogação ⇒ a operação em
  T2 deve DENY; quando a persistência for server-side, a revalidação e a mutação
  devem ser **atômicas na mesma transação/RPC** (F4-03 D9; F4-08 D7).
- **Troca de organização:** invalida contexto/dados do tenant anterior (F5-03 D9).

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
- a montagem do `ResourceContext` respeita a RLS: leituras server-side sob RLS
  (ou `service_role` em caminho confiável) — nunca leitura ampla no cliente.

---

## 11. Impactos esperados na implementação (não implementar agora)

**Prováveis módulos afetados:**

- `src/auth/*` — formalizar o `ActorContext` real sobre `AuthIdentity` +
  organização ativa + vínculo; expor o seam de montagem;
- `src/authorization/autorizacaoFuncional.ts` / `authorizationPolicy.ts` —
  substituir o mundo DEV pelo contexto real (mantendo `can`/`authorize`);
- `src/services/*` (domínios: ciclos, avaliações, metas, observações,
  colaboradores, relatórios) — carregar `ResourceContext` e chamar o engine com
  o contexto real;
- `src/authorization/ResourceContext.ts` — evoluir de tipos de recurso de
  aplicação para o contrato real (tenant/owner/estado).

**Novos módulos/abstrações provavelmente necessários:**

- `src/authorization/actorContext.ts` — montagem do `ActorContext`/`ActorRef`;
- `src/authorization/providers/*Supabase*` — providers reais (capabilities,
  scopes, targets, relations) consumindo os resolvers F5-04/F4-02/F3-07;
- `src/authorization/resourceContext*.ts` — montagem/normalização de recursos.

Nenhuma linha de código nesta rodada.

---

## 12. Estratégia de testes da futura implementação

| Grupo | Cenários |
| --- | --- |
| Happy path | ator com membership ativa + capability + scope + relação + `domainState` ⇒ ALLOW |
| Spoofing de contexto | `actorId`/`organization_id`/`role`/`capability` enviados pelo cliente ⇒ **sem efeito** (o contexto do servidor prevalece); payload com capability desconhecida ⇒ DENY |
| Cross-tenant | ator de A tentando recurso de B (por id direto, filtro, rota, filtro de lista) ⇒ DENY/`NOT_FOUND`, sem vazar existência |
| Membership inválida/inativa | membership `disabled`, perfil inativo, sem membership na org ⇒ DENY |
| Role/capability revogada | revogação entre operações ⇒ DENY na seguinte (sem logout); reativação ⇒ volta a permitir |
| Recurso inexistente | alvo inexistente/inacessível ⇒ DENY sem ALLOW por omissão |
| Recurso de outro tenant | inclui recurso filho/indireto (FK poisoning) e alvo composto |
| Scopes | SELF/DIRECT_REPORTS/DESCENDANTS/UNIT/ORGANIZATION e ASSIGNED; vaga não corrompe cadeia; sem vínculo ⇒ estruturais vazios |
| DENY fail-closed | ausência de data/`domainState`/tenant/contexto ⇒ DENY |
| Paridade `can` × `authorize` | para cada operação de mutação, o `authorize()` usa o mesmo contexto do `can()`; divergência ⇒ falha de teste |
| Origens B/C/D | independentes e não “turbinadas” pelo contexto (C só com A/B DENY e confidencial; D dev-only, nunca confidencial) |
| ADMIN sem colaborador | contexto válido, `collaboratorId = null`, escopos estruturais vazios, sem confidencial |

Complementos obrigatórios: validação SQL/Supabase local quando a implementação
tocar RLS/resolvers; regressão dos validadores F4/F5 existentes.

---

## 13. Compatibilidade com F5-01/02/03/04 e contratos F4

- **F5-01 (identidade):** `ActorContext` consome `AuthIdentity`; invariantes
  preservadas (authUserId = perfil = auth.uid; perfil ativo; memberships ativas).
- **F5-02 (vínculo):** `collaboratorId` resolvido por
  `(authUserId, organizationId)`; sem vínculo ⇒ null (ADMIN), escopos
  estruturais vazios. Nenhuma superfície nova executável pelo frontend.
- **F5-03 (organização ativa):** intenção validada; sem estado server-side de
  “org ativa” (D5); revalidação por operação (D6); cross-tenant DENY (D8).
- **F5-04 (roles/capabilities):** catálogo DB canônico; resolução por operação;
  sem cache de ALLOW; plano administrativo/controle **fora** do `ActorContext`
  (permanece RPC server-side com ator verificado — D15/D16).
- **F4-03 (engine):** contrato de entrada/saída inalterado; `authorize`/`can`/
  `listAllowedTargets` mantidos.
- **F4-04/F4-05/F4-06/F4-07:** relações/hierarquia, temporária, excepcional e
  pilot seguem como providers/origens independentes; a F5-05 só troca a fonte de
  dados (DEV → real) via a mesma interface.
- **F4-08 (RLS):** fronteira preservada; nenhuma policy nova; nenhuma redução de
  controle.
- **F4-09 (aplicação funcional):** as fachadas permanecem a porta de entrada,
  agora alimentadas pelo contexto real (a superfície legada por cargo continua
  proibida em runtime).

---

## 14. Critérios de aceite (da futura implementação)

1. `ActorContext` real montado server-side a partir de identidade (F5-01) + org
   validada (F5-03) + membership + vínculo (F5-02); `actorId = auth.uid()`;
2. `ResourceContext` real com tenant derivado do recurso + owner/atributos +
   `domainState`, produzindo `TargetRef` válido;
3. cliente nunca fornece prova de identidade/tenant/role/capability/scope;
4. cross-tenant/IDOR ⇒ DENY fail-closed (incl. filhos/indiretos);
5. nenhum cache de ALLOW entre requisições; revogação efetiva na operação
   subsequente;
6. origens B/C/D preservadas como providers independentes;
7. RLS preservada como barreira independente; sem nova superfície a
   `authenticated`; sem `SECURITY DEFINER` novo;
8. `authorize()` é enforcement e usa o mesmo contexto de `can()` (paridade);
9. ADMIN sem colaborador: contexto válido, escopos estruturais vazios;
10. regressão F4/F5 verde (test/build/lint/diff-check + validadores SQL
    aplicáveis).

---

## 15. Riscos

| Risco | Mitigação |
| --- | --- |
| Cliente “montando” contexto (spoofing) | contexto só no servidor; cliente transporta intenção (D4/D6) |
| Divergência entre `can()` e `authorize()` | mesma pipeline `decidir()` + testes de paridade (§12) |
| Stale de privilégio | sem cache de ALLOW entre requisições; resolução por operação (D10) |
| IDOR por recurso de outro tenant | tenant do recurso + `CROSS_TENANT` DENY sem vazar existência (§8) |
| Duplicação de autorização em serviços/páginas | engine como única decisão; fachadas preservadas (§3) |
| Mundo híbrido (localStorage) mascarar “real” | limite explícito + Q2 (§17) |
| Origens C/D “turbinadas” pelo contexto | providers independentes; guards F4-06/07 (D11) |
| Confusão ActorContext × ActorRef | fronteira conceitual (§3, D7) |

---

## 16. Decisões arquiteturais (D1–D19)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | ActorContext = única porta do ActorRef real | Nenhuma página/componente monta `ActorRef`; a montagem é da camada de serviço (F5-01 §9.2) | FECHADA |
| D2 | `actorId` soberano | `actorId = identity.authUserId = user_profile.id = auth.uid()`; nunca matrícula/e-mail (F5-01 D1/D7) | FECHADA |
| D3 | `organizationId` = org ativa validada | Intenção de UX (F5-03) revalidada contra membership ativa; sem seleção válida não há contexto (F5-03 D1/D3/D12) | FECHADA |
| D4 | Montagem server-side | `ActorContext` e `ResourceContext` são montados no servidor/serviço; o cliente só transporta intenção (F5-01 D6/§5.2) | FECHADA |
| D5 | Capabilities/scopes vêm da F5-04 | Resolvidos dos resolvers canônicos do DB por operação; nunca do cliente/estado (F5-04 D2/D5) | FECHADA |
| D6 | Tenant do recurso derivado do recurso | Coluna/FK do próprio recurso carregado; nunca do `organizationId` do caller (F4-03 §5/§10; F4-08 D1) | FECHADA |
| D7 | ActorContext ≠ ActorRef; ResourceContext ≠ TargetRef | Contexto de aplicação produz o contrato do engine; o engine consome `ActorRef`/`TargetRef` (§3) | FECHADA |
| D8 | Cross-tenant/inexistente ⇒ DENY | Fail-closed com código público sem vazar existência (F4-03 §14; regras permanentes) | FECHADA |
| D9 | Fail-closed universal | Ausência/indeterminação/erro ⇒ DENY; nenhum default permissivo (F4-03 §3.3) | FECHADA |
| D10 | Sem cache de ALLOW entre requisições | Resolução por operação; revogação efetiva na operação subsequente (F5-04 D17; F4-03 D12) | FECHADA |
| D11 | B/C/D permanecem providers independentes | Não viram campos do ActorContext nem capabilities “concedidas” pelo contexto (F5-04 D12; F4-05/06/07) | FECHADA |
| D12 | Engine F4-03 inalterado | F5-05 alimenta o `AuthorizationRequest`/providers existentes; nenhuma reescrita (F4-03 D1/D5) | FECHADA |
| D13 | `authorize()` = enforcement; `can()` = UX | Mesma pipeline `decidir()`; ocultação de UI não autoriza (F4-03 D5; regras permanentes) | FECHADA |
| D14 | ADMIN sem colaborador | Contexto válido com `collaboratorId = null`; escopos estruturais vazios; sem confidencial (F5-02 D6/D11; F5-04 D11; F4-02 D17) | FECHADA |
| D15 | Contexto por-request e imutável | Sem singleton; páginas não mutam; re-resolução é o único caminho de atualização (F5-01 D13) | FECHADA |
| D16 | Fronteira RLS × engine preservada | RLS = tenant boundary; engine = autorização funcional; nenhum substitui o outro (F4-08 §1.2/D5/D12) | FECHADA |
| D17 | Data/hora de decisão | `date` explícita fornecida pelo serviço (relógio do servidor); nunca do cliente (F4-03 §12/D13) | FECHADA |
| D18 | Plano administrativo fora do ActorContext | Conceder/revogar roles permanece no RPC server-side com ator verificado (F5-04 D15/D16) | FECHADA |
| D19 | Mundo híbrido declarado | Enquanto domínios funcionais estiverem em `localStorage`, a F5-05 declara explicitamente o que é “contexto real” e o que permanece transitório — **forma exata depende de Q2** | PENDENTE (Q2) |

---

## 17. Questões em aberto (Q1–Q5)

> Registradas porque o repositório/contratos **não** permitem decisão segura sem
> premissa inventada. Nenhuma implementação antes do fechamento.

### Q1 — Numeração e escopo de “F5-05” (conflito com a Issue #102) — **ABERTA**

- **Evidência:** a Issue **#102** (“[F5-05] db(goal): migrar metas, limites e
  histórico para PostgreSQL”) está **fechada como `not_planned`** e rotula
  “F5-05 — **Metas no PostgreSQL**”. Já os contratos fechados
  (`F5-01` §1.2/§9.2 e `F5-04` §11/§16) definem **F5-05 = ActorContext /
  ResourceContext** (esta atividade).
- **Problema:** dois escopos distintos sob o mesmo código; sem definição oficial,
  o “F5-05” desta atividade pode colidir com o roadmap de migração de metas.
- **Alternativas:** (A) manter o contrato dos documentos (F5-05 = ActorContext) e
  reclassificar a Issue #102 como atividade de migração de domínio (outro
  código); (B) renomear esta atividade; (C) manter ambos com sufixos.
- **Recomendação:** **A** — o contrato fechado prevalece; a Issue #102
  (`not_planned`) deve ser reclassificada sem reabrir decisões.
- **Impacto:** nomenclatura de Issue/branch/PR; nenhum impacto técnico.
- **Seções dependentes:** §1.2, toda a nomenclatura do documento.

### Q2 — Mundo híbrido de persistência: o que a F5-05 pode declarar “real”? — **ABERTA**

- **Evidência:** os domínios funcionais (ciclos, avaliações, metas, observações,
  colaboradores) permanecem em `localStorage` (F4-03 §1.3/§10; F4-08 §1.3;
  F5-04 §16). Só a estrutura F3 e a autorização F4/F5 têm persistência
  server-side. Um `ResourceContext` “real” exige **tenant do recurso derivado do
  recurso** (D6), o que não é possível server-side para dado que vive no cliente.
- **Problema:** definir o limite da F5-05 sem transformar dado do cliente em
  autoridade (regra permanente) e sem inventar persistência.
- **Alternativas:** (A) F5-05 limita o “contexto real” ao que já tem persistência
  soberana (estrutura F3 + autorização F4/F5 + identidade/membership/vínculo) e
  declara explicitamente que os domínios funcionais permanecem no mundo
  transitório até a migração; (B) F5-05 define um `ResourceContext` híbrido com
  carga server-side por repositório (exige a migração antes); (C) F5-05 fica
  bloqueada até a migração de todos os domínios.
- **Recomendação:** **A** (com limite declarado, issue própria para a migração e
  reexecução das invariantes na persistência real — princípio já adotado em
  F4-10 Q1).
- **Impacto:** escopo da implementação e critérios de aceite; risco de falsa
  sensação de “real” se (A) não for explícito.
- **Seções dependentes:** §1.4, §5.5, §6.2, §11, §12, D19.

### Q3 — Mecanismo de disponibilização do ActorContext na aplicação — **ABERTA**

- **Evidência:** F5-01 §9.2 proíbe “página monta ActorRef”, mas não define o
  mecanismo; hoje `AuthProvider` expõe apenas dados de sessão/organização
  (F5-03) e as fachadas montam o ator a partir do colaborador DEV.
- **Problema:** escolher como serviços e UI obtêm o contexto sem reintroduzir
  ator vindo do cliente.
- **Alternativas:** (A) função de serviço que monta o `ActorContext` **por
  operação** (sem estado global) e o injeta nos serviços; (B) contexto React
  enriquecido expondo `actorRef` para `can()` (UX) **e** serviços montando o
  `ActorRef` server-side para `authorize()`; (C) misto conforme (A)+(B).
- **Recomendação:** **C** — enforcement sempre por montagem server-side por
  operação; o valor exposto ao React serve **apenas** UX e nunca é prova.
- **Impacto:** arquitetura de injeção, testabilidade, risco de ator de UI ser
  usado como prova se mal aplicado.
- **Seções dependentes:** §6.1, §11, §12.

### Q4 — Recursos globais sem tenant — **ABERTA**

- **Evidência:** o engine exige derivar o tenant do alvo
  (`resolveTargetTenant`; `undefined ⇒ TARGET_INVALID` — F4-03 §10/§14), mas há
  recursos globais (catálogo `capabilities`, configuração global) e o código
  legado usa alvos **sintéticos** (`{ type: "cycle", id: "global" }`, ator) para
  gates de navegação (evidência: `authorizationPolicy.ts`).
- **Problema:** definir como o `ResourceContext`/`TargetRef` representa recurso
  global sem inventar tenant nem aceitar alvo sintético como autorização real.
- **Alternativas:** (A) recursos globais **não** passam pelo engine (não são
  operações autorizáveis; leitura de catálogo é apenas informativa e a RLS
  cuida); (B) criar um tipo de alvo global explícito com regra de tenant própria;
  (C) manter alvos sintéticos e documentá-los como transitórios.
- **Recomendação:** **A**, substituindo os alvos sintéticos por gates
  explícitos/`capability` sobre alvo real, ou por UX derivada de contexto real.
- **Impacto:** contratos de `TargetRef` (evitar reabrir F4-03 sem necessidade) e
  a limpeza de gates legados.
- **Seções dependentes:** §5.5, §7.3, §11, §13.

### Q5 — Apresentação do colaborador vinculado (nome exibido) — **ABERTA**

- **Evidência:** F5-01 D14/Q5 mantiveram o nome pelo e-mail até a F5-02 avaliar o
  colaborador vinculado; F5-02 D4 fixou que colaborador **não** identifica a
  conta; **F5-03 D13 diferiu explicitamente “Q5 (apresentação do collaborator)”
  para a F5-05**.
- **Problema:** decidir se a apresentação (nome/identidade visual do ator) entra
  no escopo da F5-05 e, em caso positivo, como derivá-la sem transformar
  `collaborator` em identidade de autorização.
- **Alternativas:** (A) F5-05 mantém a apresentação **fora** do `ActorContext`
  (apenas `collaboratorId` quando necessário à autorização) e a apresentação
  segue pelo e-mail/`user_profile`, tratada em atividade de UX; (B) F5-05 expõe
  um campo de apresentação (ex.: `displayName`) derivado do colaborador
  vinculado, **nunca** usado como chave de identidade/autorização.
- **Recomendação:** **A** (mantém a separação identidade × apresentação), salvo
  decisão do revisor.
- **Impacto:** campos do `ActorContext` e telas; risco de acoplar apresentação à
  autorização.
- **Seções dependentes:** §4.1, §11.

---

## 18. Confirmações desta atividade

- **Nenhuma implementação funcional**: não houve alteração de código, migration,
  teste, contrato existente ou UI; apenas este documento foi criado.
- Documento **pronto para auditoria arquitetural independente**; estado
  explicitado como **PROPOSTA** com **Q1–Q5 abertas** (§17).
- Decisões `D1–D18` **FECHADAS** (derivadas dos contratos existentes);
  `D19` **PENDENTE** (depende de Q2).
- Contratos F4 e F5 anteriores **preservados**; nenhuma decisão fechada reaberta;
  nenhuma premissa inventada — o que não é decisível pelo repositório está em Q.
- Próximo passo (após revisão/fechamento das Q): implementação da F5-05 em PR
  próprio, seguindo o contrato fechado — **não** iniciada aqui.
