# F5-02 — Vínculo usuário autenticado ↔ colaborador (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de auditoria e desenho, sem código funcional**.
> Estado: **revisado (PR #161)** — Q1, Q3, Q4 e Q5 **FECHADAS/APROVADAS**; Q2
> **N/A (adiada para F5-05)**; Q6 **ABERTA** aguardando validação. Decisões
> D1–D14 revisadas; **D8 permanece ABERTA** enquanto Q6 estiver aberta.
>
> Fase: 5 — Identidade e Multiusuário · Atividade: F5-02 · Complexidade: Alta · Risco: Crítico

---

## 1. Objetivo

Definir o contrato arquitetural e o desenho de implementação do **vínculo
confiável** entre a identidade autenticada e o colaborador organizacional:

```
usuário autenticado (auth.uid())
  → user_profile (conta habilitada no Virtus)
  → membership (alcance de tenant)
  → MembershipCollaboratorLink (vínculo 1:0..1)
  → colaborador (entidade de domínio organizacional — F3)
```

Esse vínculo é a ponte soberana que etapas posteriores consumirão para **SELF**,
hierarquia, relações organizacionais, **ActorContext (F5-05)** e o **Policy
Engine** — sem nunca fazer do colaborador um substituto da conta de acesso, nem
do e-mail/matrícula/cargo uma chave de vínculo.

### 1.1 Princípios herdados (não redesenhados)

- `auth.uid()` é a raiz soberana da identidade autenticada (F5-01/D1);
- `user_profile.id = auth.uid()` e o perfil representa a **conta habilitada**;
- `membership` representa o **alcance de tenant** (contrato F4-08: profile ativo
  + membership ativa = fronteira soberana);
- `colaborador` pertence ao **domínio organizacional** (F3) e **não identifica a
  conta de acesso**;
- Policy Engine permanece o **gate soberano**; `authorize()` = enforcement;
  `can()` = UX; capability = ação; nenhuma autorização runtime por
  cargo/job_role/função;
- contexto fornecido pelo cliente (e-mail, matrícula, nome, cargo, `user_id`)
  **nunca é fonte soberana** de identidade, tenant ou vínculo;
- **`organization_id` NÃO é claim soberano da sessão/JWT**: `auth.uid()` vem da
  sessão autenticada; uma organização escolhida/enviada pelo cliente é apenas
  **intenção** e sua validade é confirmada **server-side contra uma membership
  ativa do `auth.uid()`** — sem membership ativa naquele tenant ⇒ DENY/fail-closed
  (fronteira exata da F5-01);
- fail-closed; tenant mismatch = DENY; RLS F4-08 e isolamento entre tenants
  permanecem vigentes;
- F4-02 (decisões **fechadas**) já definiu: vínculo em **tabela própria**
  (`membership_collaborator_links`), 1 vínculo ativo por (usuário, organização),
  FK composta de tenant, ADMIN/usuários sem colaborador usam scopes não
  estruturais (D17) e resolvers `SECURITY INVOKER`/bootstrap DEFINER restrito a
  `service_role` (D18 — **inalterado nesta atividade**).

### 1.2 O que a F5-02 entrega e o que deixa para etapas posteriores

| Assunto | F5-02 (este documento) | Etapa futura |
| --- | --- | --- |
| Contrato do vínculo, chaves, invariantes e tenant correlation | ✅ define | — |
| Auditoria/endurecimento de `membership_collaborator_links`, resolvers, RLS/grants | ✅ audita e define o alvo | implementação do contrato (PR próprio) |
| Superfície de leitura do próprio vínculo pelo frontend | ❌ **não cria** (Q1 = A fechada; Q2 N/A → F5-05) | F5-05, se necessário |
| Uso do vínculo para SELF/hierarquia no runtime | define contrato e impacto | F5-05 (ActorContext) e domínios |
| Seleção/“organização ativa”/switcher | ❌ fora | F5-03 |
| Roles/capabilities efetivas em runtime | ❌ fora (só aponta o seam) | F5-04 |
| ActorContext | ❌ fora (define interfaces que ele consumirá) | F5-05 |
| Migração de `localStorage`/persistência funcional/RLS de domínios | ❌ fora | posteriores |
| Hardening geral (F6), hosting, observabilidade, backup | ❌ fora | F6 |

---

## 2. Estado atual encontrado no código (inventário verificado)

### 2.1 Banco — `membership_collaborator_links` (F4-02, Issue #89)

Criada em `supabase/migrations/20260908010000_authorization_scopes_membership_collaborator.sql`
(contrato F4-02, decisão **D1 = A fechada**):

| Aspecto | Estado verificado |
| --- | --- |
| Colunas | `id uuid PK` · `membership_id uuid` · `organization_id uuid` · `collaborator_id uuid` · `status text (active/disabled)` · `created_at/updated_at/version` |
| 1 vínculo por membership | `uq_membership_collaborator_links_membership` unique (membership_id) — **vale inclusive quando a linha está `disabled`** (1 única linha por membership em qualquer status) |
| Tenant da membership | FK composta `(membership_id, organization_id)` → `user_organization_memberships(id, organization_id)` RESTRICT |
| Tenant do colaborador | FK composta `(collaborator_id, organization_id)` → `collaborators(id, organization_id)` RESTRICT |
| Reativação no lugar | `status active/disabled`; sem exclusão física; histórico preservado na linha |
| Índices | `organization_id` e `collaborator_id` |
| RLS | `ENABLE ROW LEVEL SECURITY`, **zero policies** (deny-by-default) |
| Grants | Nenhum SELECT/DML a `authenticated`/`anon` (revogados na F4-08 `revoke_excess`; tabela entre as **7 fechadas** validadas em `02-validar-f4-08.sql`) |

### 2.2 Banco — resolvers/funções relacionadas (F4-02/F4-08)

| Função | Modo | Estado |
| --- | --- | --- |
| `resolver_collaborador_vinculado(user_profile_id, organization_id)` → `collaborator_id` | `SECURITY INVOKER`, STABLE | Une membership **ativa** (`m.status='active'`) × link **ativo** (`l.status='active'`) pelo `membership_id`; filtrado por `user_profile_id` e `organization_id`. **Não junta `user_profiles` (profile ativo não é verificado aqui)** — divergência de defesa em profundidade vs. `resolver_capabilities_escopos_efetivas`, que junta `up.status='active'` (G2). |
| `resolver_capabilities_escopos_efetivas(user_profile_id, organization_id)` | INVOKER, STABLE | Exige profile ativo + membership ativa + assignments/roles/scopes ativos (fail-closed) |
| `resolver_alvos_escopo(user_profile_id, organization_id, scope, unit, data)` | INVOKER, STABLE | SELF/DIRECT_REPORTS/DESCENDANTS partem de `resolver_collaborador_vinculado` → resolvers F3-07; ORGANIZATIONAL_UNIT/ORGANIZATION; ASSIGNED = vazio (F4-03/F4-05) |
| Grants (F4-08) | — | `EXECUTE` desses resolvers **revogado** de `public/anon/authenticated`; concedido **somente a `service_role`** (uso interno/server-side) |

### 2.3 Banco — colaborador (F3-01) e sua identidade

- `collaborators(id uuid, organization_id uuid)` — **identidade técnica imutável**;
  sem matrícula/código/nome/e-mail na tabela (são cadastro/atributos de issues
  futuras); `uq (id, organization_id)` permite FKs compostas de tenant.
- `collaborator_identifiers` — códigos de negócio (matrícula) **temporais**, por
  organização; nunca chave de identidade de conta.
- `collaborator_status_periods` — status **temporal** `active/leave/inactive`,
  com exclusion constraint (1 período vigente por instante).
- Validação F4-08 prova: `authenticated` não lê a tabela fechada e não altera
  `organization_id`; FK composta bloqueia link cross-tenant mesmo via
  `service_role`/superuser.

### 2.4 Frontend/typescript

- Nenhum arquivo de `src/` referencia `membership_collaborator_links` ou
  `resolver_collaborador_vinculado` (grep verificado). A F5-01 resolve apenas
  profile + memberships + organizações; **não há passo de colaborador vinculado**.
- Identidade DEV (F2-09) seleciona **colaborador por matrícula**
  (`feedback-control-usuario-atual`), e as páginas montam
  `AuthorizationContext { actor: { matricula, funcao?, status } }`
  (`src/authorization/AuthorizationContext.ts`), que os adaptadores F4-09
  convertem em `actorId = String(matricula)` no mundo local
  (`src/authorization/mundoFuncional.ts`, `autorizacaoFuncional.ts`,
  `authorizationPolicy.ts`). Esse mundo é **DEV/sintético** e não participa de
  autorização server-side.
- Providers do Policy Engine para relações estruturais (`providers/structure.ts`,
  `assigned.ts`, etc.) trabalham com ids de colaborador **do dado de domínio**
  (snapshots/ocupações F3); a origem A/B (membership/temporária) e as origens
  C/D usam `userProfileId`/collaborator ids conforme o dado.
- Contratos de erro/estado da F5-01 em `src/auth/*` (ex.: `AuthIdentity`,
  estados `semOrganizacao`, `aguardandoSelecao`, `sessaoIndisponivel`) não
  dependem de colaborador.

### 2.5 Contratos já fechados que F5-02 respeita (referência)

- **F4-02 D1 (A):** vínculo em tabela própria; 1 vínculo ativo por (usuário,
  organização); ADMIN sem vínculo.
- **F4-02 D17 (A):** scopes estruturais exigem colaborador vinculado; sem
  vínculo resolvem vazio; ADMIN usa ORGANIZATION.
- **F4-02 D18 (A):** resolvers INVOKER; bootstrap DEFINER restrito a
  `service_role`. **(Não alterado nesta atividade — Q2 N/A.)**
- **F4-08 D1:** fronteira soberana de tenant = `auth.uid()` + `user_profiles`
  ativo + `user_organization_memberships` ativa; helper único
  `user_has_active_membership(org)`; cross-tenant DENY.
- **F5-01:** `user_profile.id = auth.uid()`; colaborador nunca identifica a
  conta; vínculo ocorre **no contexto da membership**; `organization_id` enviado
  pelo cliente é intenção, confirmada contra membership ativa do `auth.uid()`.

---

## 3. Gaps (G1–G10)

| # | Gap | Evidência | Consequência | Endereçado em |
| --- | --- | --- | --- | --- |
| G1 | Nenhum caminho TS/runtime resolve o colaborador a partir da identidade real (`auth.uid → membership → colaborador`) | grep `src/` sem referência ao link/resolver | ActorContext/SELF futuros não têm a ponte; hoje só o DEV usa colaborador | F5-02 (contrato) + F5-05 |
| G2 | `resolver_collaborador_vinculado` não verifica `user_profiles.status='active'` | migration F4-02 (função) vs. `resolver_capabilities_escopos_efetivas` | Perfil desabilitado (sem ban) ainda resolveria o vínculo por `service_role`; quebra a paridade do fail-closed D1/F4-08 | F5-02 (hardening — Q4 FECHADA) |
| G3 | Tabela do vínculo é **fechada** (RLS sem policy + sem grant SELECT) e resolvers sem `EXECUTE` para `authenticated` | F4-08 `revoke_excess` + `helpers_function_grants` + validação “7 tabelas fechadas” | Não existe superfície segura para o runtime resolver o próprio vínculo | F5-02: **manter fechado** (Q1 = A FECHADA); reavaliar exposição só em F5-05 (Q2 N/A) |
| G4 | Sem testes automatizados (TS ou validação SQL) para os estados inválidos do vínculo: profile desabilitado × link, membership revogada × link, colaborador inativo/inexistente | validação F4-02 testa apenas o caso feliz do `resolver_collaborador_vinculado` + `resolver_capabilities_escopos_efetivas` p/ disabled | Regressões silenciosas quando o vínculo entrar em runtime | F5-02 (estratégia de testes — caminhos internos/service_role) |
| G5 | Não há definição formal de “colaborador inativo” × vínculo (status temporal F3-01) no contrato de resolução | F3-01 status `active/leave/inactive`; link só tem `active/disabled` | SELF/hierarquia podem divergir sobre licença/desligado | F5-02 (Q5 FECHADA — âncora independente de status) |
| G6 | Possibilidade de um mesmo colaborador estar vinculado a **mais de um** membership **ativo** da mesma organização (usuários distintos): `unique` é só por `membership_id` | constraint F4-02 | Ambiguidade de SELF para o colaborador na organização | F5-02 (Q3 FECHADA — unique parcial do ativo) |
| G7 | Sem tratamento executável de “mudança de colaborador”/“mudança de organização” com histórico | modelo só tem status active/disabled e **UNIQUE(membership_id)** (impede 2ª linha histórica na mesma membership) | Mudanças administrativas sem caminho consistente e sem auditoria | F5-02 (Q6 ABERTA — análise A/B/C) |
| G8 | `membership` não tem coluna `collaborator_id` (por decisão F4-02 D1 = A); há risco de alguém reintroduzir vínculo por e-mail/matrícula no futuro | F2-02/migração F4-02 | Anti-pattern de identidade (regressão ao vínculo por chave de negócio) | F5-02 (contrato/regra permanente) |
| G9 | Mundo DEV usa matrícula como `actorId`; a semântica real (`auth.uid()`) ainda não está conectada aos providers estruturais | `mundoFuncional.ts`, `authorizationPolicy.ts` | Transição DEV→real exige o mapa (actorId, org) → colaborador via vínculo | F5-02 (seam) + F5-04/05 |
| G10 | Sem contrato de “quem pode criar/mover/remover vínculo” (path administrativo) e sem auditoria do vínculo | sem função/RPC de gestão do vínculo além da tabela | Mutação direta poderia virar caminho (proibido: F4-08 mutações só por RPC/transação) | F5-02 (D9; implementação) |

---

## 4. Modelo de vínculo

### 4.1 Cadeia soberana

```
auth.uid()  ──1:1──▶  user_profiles.id        (conta habilitada)
   │
   ▼ (profile ativo + membership ativa, confirmada server-side)
user_organization_memberships.user_profile_id   (alcance de tenant)
   │
   ▼ (1:0..1 ativo)
membership_collaborator_links                   (o vínculo)
   │
   ▼ (FK composta — mesmo tenant)
collaborators.id                                (pessoa organizacional — F3)
```

Regra: o vínculo **existe no contexto da membership** (par usuário+organização) e
aponta para um colaborador **do mesmo tenant**. Não existe “usuário global ligado
a colaborador” fora de uma organização.

### 4.2 Cardinalidades e formas válidas

| Relação | Cardinalidade | Como é garantida |
| --- | --- | --- |
| user_profile → membership | 1 → N | unique (user_profile_id, organization_id) F2-02 |
| membership → colaborador (via link) | 1 → **0..1** | no máx. 1 link **ativo** por membership (hoje 1 linha por membership em qualquer status — UNIQUE(membership_id); forma do histórico depende de Q6) |
| colaborador → membership (via link) | 1 → 0..1 **ativo** por organização | **Q3 FECHADA (B):** unique parcial do link ativo por `(collaborator_id, organization_id)` |
| link → tenant | 1 organização | FKs compostas (membership e colaborador) |

Formas válidas por (usuário, organização):
- membership ativa **sem** link → usuário da organização **sem colaborador**
  (ADMIN/administrativo; D17 F4-02);
- membership ativa **com** link ativo → usuário com colaborador (SELF e raiz de
  escopos estruturais);
- link `disabled` → equivale a “sem vínculo ativo” para fins de resolução
  (fail-closed), preservando o histórico da linha.

### 4.3 Invariantes do modelo

1. `link.membership_id` aponta para membership ativa (resolução) **e** o
   `user_profiles` do dono da membership está ativo (D1/F4-08 — G2);
2. `link.organization_id` = `membership.organization_id` = `collaborator.organization_id`
   (FKs compostas — indecomponível no banco);
3. no máximo **1 link ativo por membership** e, por decisão Q3 (B), no máximo
   **1 link ativo por `(collaborator_id, organization_id)`** (mesmo colaborador
   não representado por 2 contas/memberships ativas na mesma organização);
4. `collaborators.id` é UUID técnico imutável; matrícula/nome/e-mail **nunca**
   participam do vínculo;
5. sem vínculo ativo ⇒ scopes SELF/estruturais **não resolvem** (vazio = DENY);
6. link `disabled`/membership `disabled`/profile `disabled` ⇒ resolução vazia
   (fail-closed), sem exclusão física de histórico;
7. o formato exato de linhas históricas (1 linha única com troca controlada vs.
   múltiplas linhas históricas) depende de **Q6 (ABERTA)** — invariantes 3 e 6
   permanecem válidos em qualquer opção.

---

## 5. Chaves e invariantes da resolução

**Chave soberana do vínculo:** `user_profile_id` (= `auth.uid()`, derivado da
sessão autenticada) + `organization_id` **confirmado server-side contra uma
membership ativa do `auth.uid()`** — nunca e-mail, matrícula, nome ou cargo.

> **Fronteira exata (F5-01):** `organization_id` **NÃO** é claim soberano da
> sessão/JWT. Uma organização enviada pelo cliente é apenas **intenção**; sua
> validade é confirmada contra memberships **ativas** do `auth.uid()`; sem
> membership ativa naquele tenant ⇒ **DENY/fail-closed**.

Resolução mínima do colaborador vinculado (contrato):

```
resolveCollaborator(authUid, organizationId):
  1. profile = user_profiles(authUid)              → ausente/inativo ⇒ vazio
  2. membership = memberships ativas(authUid, org) → ausente (sem membership
                                                     ativa no tenant) ⇒ vazio
  3. link = links ativos(membership.id)            → ausente/disabled ⇒ vazio
  4. colaborador = collaborators(link.collaborator_id)
  5. ⇒ { colaborador, membership, link } (0 ou 1)
```

Regras:
- retorna **no máximo 1** colaborador por (authUid, organizationId);
- a organização é **parâmetro de contexto** (intenção do chamador), **nunca**
  derivada da sessão/JWT; a validade é confirmada contra a membership ativa do
  `auth.uid()` naquele tenant (sem membership ativa ⇒ DENY/vazio);
- falhas de qualquer elo = **vazio** (fail-closed), nunca heurística;
- o resultado é **por organização**: o mesmo usuário pode ter vínculos distintos
  em tenants distintos (cada um no próprio contexto);
- a resolução é **interna/server-side** nesta F5-02 (Q1 = A): não há função
  executável pelo frontend; o consumo em runtime ocorre em F5-05.

---

## 6. Tenant correlation

- **Declarativa:** `membership_collaborator_links` carrega `organization_id` e as
  FKs compostas obrigam membership e colaborador a pertencerem à mesma
  organização (validação F4-02/F4-08 comprova cross-tenant = violação de FK).
- **Em execução:** todo resolver recebe `organization_id` (intenção) e filtra por
  membership **ativa do `auth.uid()`** naquela organização; sem membership ativa
  no tenant ⇒ vazio/DENY; `resolver_alvos_escopo` e
  `resolver_capabilities_escopos_efetivas` já seguem esse padrão.
- **Frontend:** nunca transporta prova; transporta apenas `organization_id` como
  intenção (validada no servidor contra membership ativa).
- **Regra:** vínculo cross-tenant = impossível no banco e DENY na resolução
  (fail-closed). Nunca “herdar” vínculo de outro tenant.

---

## 7. Fronteiras de confiança

| Conceito | É | Não é | Fronteira |
| --- | --- | --- | --- |
| AuthIdentity (F5-01) | Conta autenticada (`auth.uid()` + sessão) | Fonte de colaborador/tenant/role; `organization_id` não é claim da sessão | `user_profile.id = auth.uid()` |
| membership | Alcance de tenant da conta | Vínculo com colaborador; papel | 1 conta → N memberships |
| MembershipCollaboratorLink | **O vínculo**: associa uma membership a ≤1 colaborador no mesmo tenant | Credencial; papel; cadastro da pessoa | no máx. 1 ativo por membership; Q3: no máx. 1 ativo por (colaborador, org); FKs compostas |
| colaborador (F3) | Pessoa organizacional com lifecycle temporal | Identidade da conta | Vincula-se por membership, nunca por e-mail/matrícula |
| ActorContext (F5-05) | Ator efetivo do engine, derivado de AuthIdentity + membership + vínculo | Estado global de UI | Consome o resultado da F5-02; não implementado aqui |

**Regra de ouro:** o vínculo é **dado de servidor/banco**; o cliente apenas
transporta contexto (ex.: organização pretendida) que será revalidado contra
membership ativa do `auth.uid()`.

---

## 8. Fluxo de resolução (alvo)

```
resolver Vínculo (por organização — caminho interno/server-side na F5-02):
  authUid (da sessão)
    → user_profiles ativo?        não ⇒ ∅ (sem vínculo; acesso já negado na F5-01)
    → membership ativa em org?     não ⇒ ∅ (sem membership ativa no tenant ⇒ DENY;
                                   organização do parâmetro é intenção, nunca claim)
    → link ativo p/ membership?    não ⇒ ∅ (usuário sem colaborador — D17)
    → colaborador existe?          não ⇒ ∅ (inconsistência — nunca heurística)
    → resultado: { colaborador, membership, link }  (0..1)
```

## 9. Estados inválidos

| Caso | Resolução prevista | Estado/comportamento |
| --- | --- | --- |
| Usuário sem vínculo (sem link) | `∅` | Sem SELF estrutural; ADMIN usa ORGANIZATION (D17); sem erro — é forma válida |
| Colaborador inexistente (órfão de FK impossível; porém migração/dados) | `∅` | Fail-closed; registrar inconsistência (Q6) |
| Colaborador em `inactive`/`leave` (status temporal) | `∅`? **não** — âncora preservada (Q5 FECHADA = A) | O vínculo continua resolvendo quem é o colaborador; regras funcionais de SELF/fluxos consideram o estado temporal no domínio/engine — status **não** remapeia identidade |
| Link para outro tenant | impossível (FK) | DENY garantido no banco; testes de regressão obrigatórios |
| Vínculo duplicado ativo (2 links ativos por membership ou 2 ativos por colaborador+org) | impossível (Q3 + UNIQUE atuais) | DENY garantido no banco |
| Membership revogada/`disabled` | `∅` | Resolução vazia; sem conteúdo estrutural (F4-08) |
| Link `disabled` | `∅` | Reativação no lugar (no modelo atual: na única linha); histórico preservado |
| Mudança de colaborador (usuário passa a ser outra pessoa organizacional) | **Q6 (ABERTA)** — ver análise A/B/C na §21 | Não executável hoje como “desabilitar + abrir nova na mesma membership” (UNIQUE(membership_id)); troca controlada ou linhas históricas a decidir |
| Mudança de organização do colaborador (reorganização) | não existe hoje (id imutável + FK RESTRICT) | Requer fluxo explícito futuro (Q6); vínculo antigo tratado antes |
| Inconsistência histórica (períodos de status sobrepostos, link órfão em snapshot) | fail-closed | Preservar histórico; registrar para auditoria |

---

## 10. Fail-closed

- Resolução retorna **vazio** em qualquer elo ausente/inativo/inconsistente —
  nunca “chute”, nunca e-mail/matrícula como fallback, nunca cargo;
- perfil inativo, membership inativa/revogada (ou inexistente no tenant),
  link desabilitado ou colaborador inexistente ⇒ sem vínculo resolvido ⇒ scopes
  SELF/estruturais não autorizam;
- **nenhuma superfície de leitura do vínculo é criada nesta F5-02 (Q1 = A
  FECHADA):** a tabela e os resolvers permanecem fechados a `authenticated`
  (F4-02/F4-08 preservados); a resolução do próprio vínculo ocorre apenas por
  caminhos internos/`service_role`; a necessidade de uma superfície adicional é
  reavaliada somente na F5-05 (Q2 N/A);
- mutações do vínculo **nunca** por DML direto de `authenticated`
  (deny-by-default + sem grants); somente caminho administrativo server-side
  (RPC/Edge), ainda a implementar (D9);
- nenhum estado novo degrada para identidade simulada/DEV fora do gate DEV.

---

## 11. Impacto no Policy Engine

O engine (F4-03+) é agnóstico ao significado do `actorId` (string opaca usada
coerentemente pelos providers). A F5-02 **não altera o engine**; ela define o
seam:

- em DEV: `actorId = String(matricula)` + providers do mundo local;
- em runtime real (F5-04/05): `actorId = user_profile.id (auth.uid())` e os
  providers de identidade/relação resolvem o colaborador vinculado por
  `(actorId, organizationId confirmado)` via o contrato da F5-02
  (`resolver_collaborador_vinculado` endurecido — caminho interno/server-side),
  depois usam os resolvers F3-07.

Impactos diretos:
- **SELF** e a raiz dos scopes estruturais passam a depender do vínculo
  (D17 F4-02): sem vínculo ativo ⇒ escopos estruturais vazios;
- origens **A** (membership→role→capability) continuam por `user_profile_id +
  organization_id`; o vínculo só entra quando o **scope** precisa de estrutura
  (SELF/DIRECT_REPORTS/DESCENDANTS/UNIT);
- origens **C/D** (grants por `beneficiaryUserProfileId`) **não dependem** do
  vínculo (podem beneficiar ADMIN sem colaborador) — preservadas;
- nenhuma capability nova, nenhuma regra por cargo/job_role/função.

---

## 12. Impacto em SELF/hierarquia (F3/F4)

- `resolver_alvos_escopo(SELF)` já parte de `resolver_collaborador_vinculado`
  (F4-02): a F5-02 apenas **consolida/endurece** essa origem;
- `DIRECT_REPORTS/DESCENDANTS` partem do colaborador vinculado via resolvers
  F3-07 (ocupações/reporting lines temporais): o vínculo é a porta de entrada —
  sem ele, resolvem vazio;
- hierarquia F3 (posições, reporting lines, ocupações) permanece intacta; a F5-02
  não mexe em estrutura;
- isolamento entre tenants: o vínculo reforça (nunca atravessa tenant);
- status temporal do colaborador (`active/leave/inactive`) **não** remapeia
  identidade (Q5 FECHADA): regras de SELF/hierarquia/fluxos avaliam o estado no
  domínio/Policy Engine conforme contratos existentes.

---

## 13. Interfaces necessárias

### 13.1 Banco (alvo de implementação)

- **Q4 (FECHADA = A):** endurecer `resolver_collaborador_vinculado` para exigir
  também `user_profiles.status='active'` (paridade com
  `resolver_capabilities_escopos_efetivas` — G2). Profile
  ausente/inativo/desconhecido ⇒ resolução vazia (fail-closed). A função
  permanece `SECURITY INVOKER` e **sem `EXECUTE` para `authenticated`**.
- **Q1 (FECHADA = A):** **não criar** `resolver_meu_colaborador_vinculado` nem
  qualquer nova superfície de leitura executável pelo frontend nesta F5-02;
  manter `membership_collaborator_links` e os resolvers existentes **fechados
  para `authenticated`** (menor privilégio; sem consumidor runtime ainda;
  preserva F4-02/F4-08).
- **Q2 (N/A nesta etapa):** a decisão INVOKER vs. DEFINER para uma eventual
  superfície de leitura será **reavaliada somente na F5-05**, se o ActorContext
  precisar; **não altera** o contrato fechado F4-02 D18.
- **Q3 (FECHADA = B):** garantir no banco a unicidade do vínculo **ativo** por
  `(collaborator_id, organization_id)`; a mecânica exata da constraint e o
  tratamento de histórico dependem de **Q6 (ABERTA)** — ver §21/§15.

### 13.2 Typescript (contrato p/ F5-05 consumir)

```ts
// F5-02 — contrato de resolução do vínculo (sem implementação nesta etapa e sem
// superfície executável pelo frontend — Q1 = A FECHADA).
export interface ColaboradorVinculado {
  readonly membership: MembershipAutenticada; // membership ativa origem
  readonly linkId: string;                    // id do link ativo
  readonly colaboradorId: string;             // collaborators.id (uuid)
  readonly organizationId: string;            // === membership.organizationId
}

export interface VinculoIdentityResolver {
  /** 0..1; null = sem vínculo ativo (usuário sem colaborador na organização). */
  resolverColaborador(authUserId: string, organizationId: string): Promise<ColaboradorVinculado | null>;
}
```

- F5-05 (ActorContext) consumirá `resolverColaborador` para montar o ator;
- nenhuma página/serviço funcional chama esta interface na F5-02;
- DEV permanece com seu mundo local (G9 — seam documentado).

---

## 14. Banco/RLS

**Estado atual:** tabela fechada (RLS sem policy, sem grant); resolvers sem
`EXECUTE` para `authenticated`; default privileges endurecidos (F4-08).

**Alvo (conforme Q1/Q2/Q3/Q4):**
- manter a tabela **fechada** para leitura ampla (sem policy SELECT por
  `authenticated` — impede enumeração de vínculos de terceiros) **e não expor
  função do próprio vínculo nesta F5-02** (Q1 = A; reavaliação em F5-05 — Q2 N/A);
- endurecer o resolver INVOKER com perfil ativo (Q4 = A), sem mudar grants;
- (Q3 = B) garantir no banco no máx. 1 vínculo **ativo** por
  `(collaborator_id, organization_id)` — forma final combinada com Q6;
- mutações somente por caminho administrativo server-side (D9), seguindo o
  padrão F4-08 (funções transacionais; sem DML direto).

---

## 15. Migrations — necessárias?

**Nesta etapa de desenho: NÃO** — nenhuma migration é criada agora (somente este
documento; validações não são alteradas).

**Para a implementação da F5-02** (conforme decisões fechadas Q1/Q3/Q4/Q5 e Q6
em aberto), a previsão **revisada** de migrations aditivas (sem coluna/tabela
nova de vínculo e sem reescrita de `user_organization_memberships`):

1. `create or replace function public.resolver_collaborador_vinculado(...)` com
   `join user_profiles up on up.id = m.user_profile_id and up.status = 'active'`
   — paridade D1/F4-08 (Q4 = A; corrige G2). **Sem** mudança de grants
   (permanece sem `EXECUTE` para `authenticated`).
2. **NÃO** haverá `resolver_meu_colaborador_vinculado` nem função
   `SECURITY DEFINER` para `authenticated` nesta F5-02 (Q1 = A; Q2 N/A → F5-05).
3. **Q3 (FECHADA = B):** unicidade do vínculo **ativo** por
   `(collaborator_id, organization_id)`. A mecânica exata é **condicionada à
   decisão de Q6 (ABERTA)**:
   - se Q6 = A (1 linha por membership com troca controlada): manter
     `uq_membership_collaborator_links_membership` e adicionar unique **parcial**
     do ativo por `(collaborator_id, organization_id)`;
   - se Q6 = B (múltiplas linhas históricas por membership): substituir o unique
     total por unique parcial (1 ativo por membership) **e** unique parcial (1
     ativo por `(collaborator_id, organization_id)`).
   Em ambos os casos: validar/consolidar os dados existentes (backfill) antes de
   criar a constraint e registrar rollback (recreate do unique anterior).

Nenhuma coluna/tabela nova de vínculo; nenhuma reescrita de
`user_organization_memberships` (G8 permanece proibido: vínculo não volta a ser
coluna de membership).

---

## 16. Estratégia de implementação (ordem sugerida)

1. Endurecer `resolver_collaborador_vinculado` (Q4 = A) com validação SQL via
   **caminhos internos/`service_role`** (perfil desabilitado/ausente/
   desconhecido ⇒ vazio; membership desabilitada ⇒ vazio; link desabilitado ⇒
   vazio);
2. **Não** criar função de leitura do próprio vínculo (Q1 = A);
3. Aplicar a unicidade do vínculo **ativo** (Q3 = B) na forma definida após a
   decisão de Q6 (migration aditiva com backfill/rollback);
4. Tipos/contrato TS `ColaboradorVinculado`/`VinculoIdentityResolver` **sem
   consumidores** e sem chamada pelo frontend;
5. Registrar o seam DEV→real (G9) para F5-04/05;
6. Fluxo GitHub por PR com `npm test`, `npm run build`, `npm run lint`,
   `git diff --check`.

---

## 17. Estratégia de testes

**Unitário (TS puro — futuro):**
- `VinculoIdentityResolver`: vínculo ativo → 1; sem link → null; link disabled →
  null; membership inativa → null; organização sem membership ativa → null.

**Integração (validação SQL — `supabase/validacao`, estilo F4-02/F4-08),**
**sempre pelos caminhos internos/`service_role` já previstos — sem abrir a
tabela a `authenticated` (Q1 = A):**
- vínculo feliz: MANAGER resolve exatamente 1 colaborador (manter cenário atual,
  executado como `service_role`);
- perfil ausente/inativo/desconhecido + membership ativa + link ativo ⇒
  **vazio** (Q4 = A);
- membership `disabled` ⇒ vazio; link `disabled` ⇒ vazio; reativação no lugar ⇒
  volta a resolver;
- **sem superfície para `authenticated`:** SELECT direto na tabela ⇒ permission
  denied; `EXECUTE` dos resolvers ⇒ negado; inexistência de função própria de
  leitura (schema guard — nada novo exposto);
- **tenant mismatch:** link de outra organização ⇒ impossível (FK); resolução
  com organização sem membership ativa do `auth.uid()` ⇒ vazio;
- **IDOR/forjado:** INSERT/UPDATE direto de link por `authenticated` ⇒ negado;
  tentativa de vincular colaborador de outro tenant ⇒ violação de FK;
- **(Q3):** segunda membership **ativa** ligada ao mesmo colaborador na mesma
  organização ⇒ violação da unique parcial (após a constraint);
- **colaborador inativo/licença (Q5 = A):** o vínculo continua resolvendo o
  colaborador; o uso funcional bloqueado por `inactive` é testado no
  domínio/Policy Engine (regressão TS F4);
- regressão: rotas/auth F5-01 e suítes F4 continuam verdes.

---

## 18. Critérios de aceite

1. Contrato do vínculo aprovado: chave `(auth.uid → membership)`; 1 membership →
   0..1 colaborador; nunca por e-mail/matrícula/nome/cargo;
2. G2 corrigido no resolver (perfil ativo exigido — Q4 = A) com validação SQL;
3. **Nenhuma superfície de leitura criada** para `authenticated` nesta F5-02
   (Q1 = A); reavaliação INVOKER vs. DEFINER registrada para F5-05 (Q2 N/A);
4. Unicidade do vínculo **ativo** por `(collaborator_id, organization_id)`
   garantida no banco (Q3 = B) na forma definida após Q6;
5. Status temporal do colaborador **não** remapeia identidade (Q5 = A);
6. **Q6 permanece aberta** com análise A/B/C registrada; **D8 não é fechada**
   enquanto Q6 estiver aberta;
7. Nenhuma regra por cargo/job_role/função; engine, `authorize`, `can`,
   RLS F4-08, F4-02 D18 e origens C/D inalterados;
8. Testes dos estados inválidos (seção 17) presentes e verdes;
9. `npm test`, `npm run build`, `npm run lint` e `git diff --check` verdes no PR
   de implementação.

---

## 19. Riscos

| Risco | Mitigação |
| --- | --- |
| Vínculo virar “identidade da conta” (regressão) | Invariante rígido: vínculo por membership; colaborador nunca identifica conta |
| Reintroduzir vínculo por e-mail/matrícula | Proibido no contrato (G8); código/RLS não oferecem caminho |
| Ambiguidade de SELF (mesmo colaborador, 2 memberships ativas na mesma org) | Q3 = B: unique parcial do ativo por (colaborador, org) |
| Perfil/membership/link desabilitado ainda resolvendo | Endurecimento G2 (Q4) + fail-closed em todos os elos |
| Expor leitura do vínculo e virar enumerador de terceiros | Q1 = A: nada exposto; tabela/resolvers fechados; reavaliação só em F5-05 (Q2) |
| DEV (matrícula) contaminar runtime real | Gate DEV; seam explícito (G9) |
| Troca de vínculo sem caminho executável (UNIQUE(membership_id)) | Q6 ABERTA — análise A/B/C antes de fechar D8/migration |
| Migration de unicidade (Q3) quebrar dados existentes | Backfill + rollback documentados; banco local antes de aplicar |

---

## 20. Fora de escopo (F5-02)

- organização ativa/switcher (F5-03); roles/capabilities em runtime (F5-04);
  ActorContext (F5-05);
- migração geral de `localStorage`; persistência remota dos domínios funcionais;
- hardening geral (F6); hosting/arquitetura online/observabilidade/backup;
- UI de administração do vínculo (fase posterior, caminho server-side);
- superfície de leitura do próprio vínculo para o frontend (Q1 = A: não nesta
  F5-02; avaliar em F5-05 — Q2 N/A);
- novas capabilities, mudanças no engine ou em F3-estrutura.

---

## 21. Questões para validação

### Q1 — Exposição do próprio vínculo ao runtime: função read-only agora? — **FECHADA (alternativa A APROVADA)**

- **Contexto:** a tabela do vínculo e os resolvers estão **fechados** a
  `authenticated` (F4-08). F5-03/F5-05 ainda não existem; a F5-01 também não
  precisa do colaborador.
- **Por que:** decidir se a implementação da F5-02 cria uma função read-only do
  próprio vínculo ou mantém tudo fechado até haver consumidor.
- **Alternativas:** (A) manter fechado; nada exposto agora; (B) 1 função
  `resolver_meu_colaborador_vinculado(org)` read-only, só do próprio usuário,
  fail-closed; (C) policy SELECT own-rows na tabela.
- **Decisão adotada (A):** manter `membership_collaborator_links` e os resolvers
  existentes **fechados para `authenticated`**; **não** criar
  `resolver_meu_colaborador_vinculado` nem qualquer nova superfície de leitura
  executável pelo frontend.
  Justificativa: F5-02 ainda não possui consumidor runtime dessa superfície; o
  consumo real ocorrerá em F5-05; princípio do menor privilégio (não abrir
  superfície sem necessidade concreta); preserva o contrato F4-02/F4-08
  (resolvers INVOKER internos e tabelas fechadas); evita introduzir agora um
  `SECURITY DEFINER` autenticado sem consumidor.
- **Impacto/risco:** nenhuma migration de exposição; testes do contrato via
  caminhos internos/`service_role`.
- **Seções dependentes:** 3 (G3), 10, 13, 14, 15, 17, 18.

### Q2 — Modo da função do próprio vínculo: INVOKER vs DEFINER — **N/A NESTA ETAPA (adiada para F5-05)**

- **Contexto:** F4-02 D18 fechou “resolvers INVOKER; bootstrap DEFINER restrito a
  service_role”. Como Q1 = A, **não haverá função de leitura do próprio vínculo
  nesta F5-02**.
- **Por que:** a decisão INVOKER vs. DEFINER só faz sentido se/ quando existir a
  função; não é o caso agora.
- **Alternativas:** (A) `SECURITY DEFINER` com guards explícitos; (B) INVOKER +
  policy own-row mínima.
- **Decisão adotada (N/A):** remover da implementação prevista desta etapa a
  decisão INVOKER vs. DEFINER para essa função; registrar que deve ser
  **reavaliada somente na F5-05**, caso o ActorContext necessite de uma
  superfície adicional. **Não alterar o contrato fechado F4-02 D18** nesta
  atividade.
- **Impacto/risco:** nenhum código/migration; risco nulo nesta fase.
- **Seções dependentes:** 10, 13, 14, 15, 18, 20.

### Q3 — Um colaborador pode ter mais de uma membership ativa na mesma organização? — **FECHADA (alternativa B APROVADA)**

- **Contexto:** o unique atual é só por `membership_id`; dois usuários distintos
  podem vincular a mesma organização ao mesmo `collaborator`.
- **Por que:** define SELF/identidade da pessoa na organização (1 colaborador =
  quantas contas ativas?).
- **Alternativas:** (A) permitir; (B) proibir no banco (unique **parcial** por
  `(collaborator_id, organization_id)` considerando apenas vínculos
  `status='active'`).
- **Decisão adotada (B):** um colaborador **não pode estar representado
  simultaneamente por duas memberships/contas ativas na mesma organização**;
  garantir no banco a unicidade do vínculo **ativo** por
  `(collaborator_id, organization_id)`. A constraint considera **apenas vínculos
  ativos** e preserva histórico, se o modelo histórico final (Q6) permitir
  múltiplas linhas.
- **Interação registrada:** a mecânica exata da constraint depende da decisão de
  **Q6 (ABERTA)** — revisar a interação antes de fechar a migration (ver §15 e
  Q6).
- **Impacto/risco:** migration aditiva (unique parcial) com backfill/rollback;
  impacta provisioning.
- **Seções dependentes:** 3 (G6), 4, 15, 17, 18, Q6.

### Q4 — Endurecer `resolver_collaborador_vinculado` com profile ativo: sempre? — **FECHADA (alternativa A APROVADA)**

- **Contexto:** a função hoje não junta `user_profiles`; `resolver_capabilities_escopos_efetivas`
  junta (G2).
- **Por que:** paridade do fail-closed (perfil desabilitado não deve resolver
  vínculo mesmo server-side).
- **Alternativas:** (A) adicionar o join; (B) confiar no ban do Auth (getUser) —
  insuficiente quando profile desabilitado sem ban.
- **Decisão adotada (A):** endurecer `resolver_collaborador_vinculado` para
  exigir `user_profile` **ativo**; perfil ausente/inativo/desconhecido ⇒
  resolução vazia (fail-closed).
- **Impacto/risco:** mudança aditiva da função (INVOKER, sem grants novos);
  regressão coberta por validação.
- **Seções dependentes:** 3 (G2), 5, 15, 17.

### Q5 — Colaborador inativo/licença × vínculo e SELF — **FECHADA (alternativa A APROVADA)**

- **Contexto:** status do colaborador é temporal (F3-01): `active/leave/inactive`.
- **Por que:** decidir se o vínculo deixa de resolver com status `inactive`/
  `leave` ou se permanece como âncora de identidade.
- **Alternativas:** (A) o vínculo continua sendo a âncora independente de
  `collaborator_status_periods`; (B) o vínculo deixa de resolver em
  `inactive`/`leave`.
- **Decisão adotada (A):** `active/leave/inactive` **não alteram quem é o
  colaborador vinculado**; o vínculo permanece a âncora de identidade
  organizacional. As regras funcionais de SELF/hierarquia/fluxos consideram o
  estado temporal **no domínio/Policy Engine**, conforme contratos já existentes;
  **não usar status do colaborador para remapear identidade**.
- **Impacto/risco:** semântica clara; testes de SELF com status distintos no
  domínio.
- **Seções dependentes:** 3 (G5), 8, 12, 17.

### Q6 — Mudança de colaborador/ligação e histórico — **ABERTA (nova análise; aguarda validação)**

- **Contexto / incompatibilidade identificada:** o desenho anterior recomendava
  “desabilitar o link antigo + criar novo link na mesma membership” para trocar o
  colaborador de um usuário. **Isso não é executável no schema atual**: existe
  `UNIQUE(membership_id)`, que permite **uma única linha por membership,
  inclusive quando a linha antiga está `disabled`** — a segunda linha violaria a
  constraint. Além disso, **Q3 (fechada)** passou a exigir no máximo 1 vínculo
  **ativo** por `(collaborator_id, organization_id)`, e a interação Q3×Q6 define
  o modelo histórico final.
- **Por que:** mudanças administrativas (“este usuário agora representa outro
  colaborador”, reorganizações) precisam de um caminho consistente que preserve
  histórico/auditoria e respeite as constraints.
- **Alternativas analisadas** (para cada uma: histórico, constraints, resolvers,
  RLS, testes, compatibilidade F4-02, migration estrutural, risco de duas
  identidades simultâneas, rollback/migração de dados):

**A) Uma linha por membership com troca controlada de `collaborator_id`**

- Histórico: a linha guarda apenas o vínculo corrente; a troca é registrada em
  **mecanismo separado de auditoria** (append-only), padrão já usado no
  repositório (ex.: `evaluation_succession_events`).
- Constraints: mantém `UNIQUE(membership_id)`; adiciona unique parcial do ativo
  por `(collaborator_id, organization_id)` (Q3). Nenhuma mudança no unique atual.
- Resolvers: inalterados (leem a única linha ativa).
- RLS: inalterado (tabela fechada; troca via RPC server-side).
- Testes: troca via RPC transacional; auditoria registra antigo→novo; resolver
  reflete o novo.
- Compatibilidade F4-02: preserva D1 (1 linha por membership) e D17/D18; a
  operação de troca é nova (antes inexistente).
- Migration estrutural: **sim, mínima** — unique parcial (Q3) e, quando existir
  o caminho de mutação, tabela de eventos de auditoria (ou reuso de mecanismo
  futuro); sem coluna nova na tabela do vínculo.
- Risco de duas identidades simultâneas: baixo (Q3 impede 2 ativos por
  colaborador+org; a troca é atômica na transação).
- Rollback/migração de dados: dados atuais permanecem; auditoria retroativa não é
  gerada; rollback = desfazer a RPC e reverter a auditoria (ou registrar
  compensação).

**B) Múltiplas linhas históricas por membership (1 ativa)**

- Histórico: histórico **na própria tabela** — trocar = `disabled` da linha atual
  + INSERT de nova linha `active` na mesma membership (as linhas antigas ficam
  legíveis como histórico).
- Constraints: **substituir** `UNIQUE(membership_id)` por unique **parcial** (1
  `active` por membership) e adicionar unique parcial (1 `active` por
  `(collaborator_id, organization_id)` — Q3).
- Resolvers: lógica inalterada (já filtram `l.status='active'`); garantem no
  máximo 1 ativo.
- RLS: inalterado (tabela fechada).
- Testes: INSERT de 2ª linha com 1 ativa ⇒ violação; desabilitar + abrir nova ⇒
  ok; resolver devolve o ativo.
- Compatibilidade F4-02: altera a **constraint** da F4-02 (drop + partial unique);
  a semântica D1 (“1 vínculo ativo por (usuário, organização)”) permanece; o
  desenho D1 já admitia validade temporal/histórica “se necessário”.
- Migration estrutural: **sim** (drop do unique total + 2 partial uniques) —
  maior alteração de constraint herdada da F4-02.
- Risco de duas identidades: eliminado (1 ativo por membership + Q3).
- Rollback/migração: consolidar os atuais (1 linha por membership) → backfill
  trivial; rollback = recriar o unique total após nova consolidação.

**C) Validade temporal explícita no vínculo (`valid_from`/`valid_to`)**

- Histórico: modela períodos sobrepostos/planejados (ex.: troca agendada).
- Constraints: colunas temporais + exclusion constraint (`btree_gist` já
  habilitado na F3) — mudança significativa do modelo; Q3 vira “1 ativo na data”.
- Resolvers: passam a receber **data de contexto** (mais mudanças em
  `resolver_alvos_escopo`, etc.).
- RLS: inalterado.
- Testes: períodos, sobreposição, resolução na data.
- Compatibilidade F4-02: maior desvio (amplia a tabela e os resolvers).
- Migration estrutural: **sim, maior** (colunas + exclusion).
- Risco de duas identidades: mitigado por constraints temporais (na data).
- Rollback/migração: complexo; só se a F5-03/gestão de pessoas exigir trocas
  agendadas/sobreposições — **não recomendada agora**.

- **Nova recomendação (preliminar): A** — mantém o `UNIQUE(membership_id)`
  herdado da F4-02 intacto (menor mudança de contrato), preserva histórico via
  **mecanismo separado de auditoria** (consistente com o padrão do repositório) e
  combina com Q3 por um único unique parcial novo. **B** é a alternativa
  preferível se o produto exigir histórico **consultável na própria linha** do
  vínculo (sem mecanismo separado) — ela implica alterar a constraint da F4-02
  (drop + partial). **C** fica descartada nesta fase.
- **Status: ABERTA** — aguarda validação (em especial a escolha entre “auditoria
  separada (A)” vs. “histórico na própria linha (B)”). D8 e a forma final da
  migration de Q3 **não são fechadas** até esta decisão.
- **Seções dependentes:** 3 (G7/G10), 4 (invariantes), 9, 15, 18, 19, D8, Q3.

---

## 22. Decisões arquiteturais (D1–D14 — revisadas no PR #161)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | Chave soberana do vínculo | `user_profile_id` (= `auth.uid()`, da sessão) + `organization_id` **confirmado server-side contra membership ativa** do `auth.uid()`; nunca e-mail, matrícula, nome ou cargo; `organization_id` não é claim da sessão/JWT | FECHADA |
| D2 | Cardinalidade | 1 membership → 0..1 colaborador ativo; ausência = sem vínculo/ADMIN (D17); reativação no lugar; sem exclusão física. Forma exata das linhas históricas depende de Q6 | FECHADA (núcleo) · nota Q6 |
| D3 | Tenant correlation | FKs compostas mantêm membership e colaborador no mesmo tenant; `organization_id` é intenção do chamador, confirmada contra membership ativa do `auth.uid()`; cross-tenant DENY | FECHADA |
| D4 | Vínculo não é identidade da conta | colaborador nunca identifica a conta; e-mail/matrícula nunca são chave; vínculo por tabela própria (F4-02 D1 = A) permanece | FECHADA |
| D5 | Porta de resolução | `resolver_collaborador_vinculado` endurecido (profile ativo — Q4 = A) é a origem **interna/server-side**; runtime real mapeia `(actorId=auth.uid(), organizationId confirmado) → colaborador` no consumo F5-05; **sem superfície nova nesta F5-02** (Q1 = A) | FECHADA |
| D6 | Sem vínculo = sem escopo estrutural | SELF/DR/DESCENDANTS/UNIT exigem vínculo ativo (D17 F4-02); sem vínculo resolvem vazio; ADMIN usa ORGANIZATION | FECHADA |
| D7 | Status do colaborador × vínculo | Vínculo é âncora de identidade independente de `collaborator_status_periods` (Q5 = A); status nunca remapeia identidade; regras funcionais no domínio/engine | FECHADA |
| D8 | Mudanças de vínculo | **ABERTA** — forma de trocar o colaborador (auditoria separada A vs. linhas históricas B vs. validade temporal C) depende de Q6; não fechar enquanto Q6 estiver aberta | **ABERTA (Q6)** |
| D9 | Mutações server-side | Criação/remoção/desativação/troca do vínculo somente por caminho administrativo server-side (RPC/Edge); sem DML direto de `authenticated` | FECHADA |
| D10 | Superfície de leitura mínima | **Nenhuma** superfície nova (Q1 = A): tabela e resolvers permanecem fechados a `authenticated`; reavaliação INVOKER vs. DEFINER só na F5-05 (Q2 N/A) | FECHADA |
| D11 | Falha em qualquer elo = vazio | profile/membership/link ausente, inativo ou inconsistente ⇒ resolução vazia (fail-closed); nunca heurística | FECHADA |
| D12 | Engine intacto | F5-02 não altera o Policy Engine; define o seam (actorId real → colaborador por (actorId, org confirmada)); origens C/D independentes do vínculo | FECHADA |
| D13 | Migrations na implementação | Sem migration no desenho; implementação: (1) `create or replace` do resolver (Q4); (2) **sem** função DEFINER p/ `authenticated` (Q1/Q2); (3) unique parcial do vínculo ativo (Q3) com forma condicionada a Q6; sem tabela/coluna nova | FECHADA (forma de Q3 aguarda Q6) |
| D14 | Seam DEV → real | Mundo DEV (matrícula) permanece isolado por gate; runtime real só usa a cadeia soberana (G9) | FECHADA |

---

## 23. Confirmações desta atividade

- Revisão incorporada ao **mesmo documento**, na **mesma branch**
  (`docs/f5-02-vinculo-usuario-colaborador`) e no **mesmo PR #161**.
- Status das questões: **Q1, Q3, Q4 e Q5 FECHADAS/APROVADAS**; **Q2 N/A (adiada
  para F5-05)**; **Q6 ABERTA** com nova análise (alternativas A/B/C) e
  recomendação preliminar A.
- Decisões D1–D14 revisadas; **D8 permanece ABERTA** enquanto Q6 estiver aberta.
- Fronteira de `organization_id` corrigida nas seções dependentes (D1/D3/D5,
  princípios, §5, §6, §7, §8): `organization_id` **não** é derivado da sessão —
  é intenção confirmada contra membership ativa do `auth.uid()`.
- Removida da implementação prevista qualquer criação de função
  `SECURITY DEFINER` para `authenticated` (Q1/Q2); F4-02 D18 inalterado.
- Nenhuma alteração funcional: o diff continua **somente documental**
  (`docs/F5-02-desenho-tecnico.md`).
- Próximos passos: validar Q6 (A vs. B) para então fechar D8 e a forma da
  migration de Q3; implementação do contrato em PR próprio (sem UI de gestão,
  sem F5-03/04/05).

---

## Anexo A — Fontes auditadas (referência)

- `supabase/migrations/20260908010000_authorization_scopes_membership_collaborator.sql`
  (tabela, constraints, resolvers, RLS deny-by-default);
- `supabase/migrations/20260907103100_collaborators_identifiers_status_periods.sql`
  (F3-01: identidade técnica, identifiers temporais, status periods);
- `supabase/migrations/20260908100000_f4_08_helpers_function_grants.sql` e
  `20260908140000_f4_08_revoke_excess_table_privileges.sql` (grants/revokes);
- `supabase/migrations/20260906203358_user_organization_memberships.sql`,
  `20260906205425_auth_read_policies.sql`, `20260906230400_criar_perfil_membership_rpc.sql`,
  `20260907000250_desativacao_perfil_policy.sql`;
- `supabase/validacao/02-validar-f4-02.sql` e `02-validar-f4-08.sql`
  (cenários de vínculo, cross-tenant por FK, tabelas fechadas);
- `docs/F4-02-desenho-tecnico.md` (D1/D17/D18) e `docs/F4-08-desenho-tecnico.md`;
- `src/authorization/*` (`mundoFuncional.ts`, `authorizationPolicy.ts`,
  `autorizacaoFuncional.ts`, `AuthorizationContext.ts`, `policyEngine/*`,
  `providers/*`), `src/contexts/UsuarioAtualProvider.tsx`,
  `src/auth/*` (tipos e contratos F5-01).
