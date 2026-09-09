# F5-04 — Access roles / capabilities reais (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de análise e desenho, sem código funcional**.
> Estado: **PROPOSTA para revisão** — decisões D1–D13 propostas; questões Q1–Q5
> registradas para validação (podem permanecer abertas no PR).
>
> Fase: 5 — Identidade e Multiusuário · Atividade: F5-04 · Issue #165
> Base: `main` (F5-01, F5-02 e F5-03 concluídas)

---

## 1. Objetivo

Responder, **dentro da organização validada**, qual é o conjunto real de
**access roles** e **capabilities** (com seus **scopes**) que o usuário
autenticado possui, derivado da cadeia soberana:

```
auth.uid()
→ user_profile
→ membership (ativa, organização validada)
→ (opcional) MembershipCollaboratorLink → collaborator   [F5-02]
→ access roles atribuídos à membership                      [F4-01]
→ capabilities + scopes                                       [F4-01/F4-02]
```

A F5-04 **conecta** o modelo já persistido da F4-01/F4-02 (catálogos,
atribuições, scopes) à identidade/membership reais das F5-01/F5-02/F5-03 e ao
**Policy Engine** — **sem** construir o ActorContext/ResourceContext completo
(F5-05).

### 1.1 Pergunta central

> “Dentro da organização validada, quais access roles e capabilities o usuário
> autenticado realmente possui?”

Resposta (contrato): o conjunto é **derivado do servidor** por
`(user_profile_id = auth.uid(), organization_id validada)` a partir de
`membership → membership_access_role_assignments → access_roles →
access_role_capabilities → capabilities` e dos scopes da F4-02 — **nunca** de
role/capability informada pelo cliente, JWT, localStorage, estado React ou cache
que sobreviva à revogação.

### 1.2 Limites com F5-05

A F5-05 montará o **ActorContext/ResourceContext** real (quem é o ator, com
`ActorRef.organizationId`, e como recursos são carregados). A F5-04 entrega o
**contrato de resolução de privilégios efetivos** (o que alimentará o ActorRef e
os providers do engine), sem antecipar a montagem do contexto.

---

## 2. Estado atual encontrado (inventário verificado)

### 2.1 Banco — modelo já persistido (F4-01/F4-02) ✅

- `public.capabilities` — catálogo **global** (sem `organization_id`); `code`
  único em `domínio.verbo`; `status active/disabled`. **21 capabilities** semeadas
  (migration `20260908000001_authorization_system_catalog.sql`), **sem** capability
  confidencial genérica (`confidential.*`) e **sem** capability “de papel”.
- `public.access_roles` — roles de **sistema** (`is_system=true`,
  `organization_id null`) ou **customizadas por organização**
  (`organization_id not null`); `status active/disabled`; role de sistema única
  inicial: `admin`.
- `public.access_role_capabilities` — N:N role→capability (unique por par).
- `public.membership_access_role_assignments` — atribuição membership→role:
  **múltiplas roles por membership** (D4 F4-01), unique por par
  `(membership_id, access_role_id)` em qualquer status; `status
  active/revoked` (revogação **no lugar**, sem exclusão física); `created_by`
  (autor).
- Trigger `enforce_membership_role_within_organization` bloqueia role
  customizada de outra organização (system role é livre).
- FKs compostas de tenant garantem `organization_id` da atribuição == da
  membership; cross-tenant por construção.
- RLS **deny-by-default** nas 4 tabelas (zero policies, zero grants); funções
  server-side **somente `service_role`**.

### 2.2 Banco — funções/resolvers existentes (F4-01/F4-02)

| Função | Modo | Papel |
| --- | --- | --- |
| `conceder_acesso_role(membership, role, ator)` | SECURITY DEFINER, EXECUTE só `service_role` | Concede/reativa atribuição (valida membership ativa, perfil ativo, role ativa, tenant) |
| `revogar_acesso_role(membership, role, ator)` | SECURITY DEFINER, service_role | Revoga por `status='revoked'` (histórico) |
| `resolver_capabilities_efetivas(user_profile, org)` | SECURITY DEFINER, service_role | Predicado canônico de capabilities efetivas **sem escopo** (união de roles ativas) |
| `resolver_capabilities_escopos_efetivas(user_profile, org)` | SECURITY INVOKER, service_role | Capability × **scope** (× alvo de unidade) por atribuição ativa (F4-02) |
| `resolver_alvos_escopo(...)` | SECURITY INVOKER, service_role | Alvos de SELF/DR/DESCENDANTS/UNIT/ORG (F4-02) |

Validado em `supabase/validacao/02-validar-f4-01.sql`: múltiplas roles ⇒ união;
membro sem atribuição ⇒ vazio; usuário sem membership na org ⇒ vazio; role
customizada cross-tenant rejeitada; membership/perfil desabilitado ⇒ vazio;
revogação ⇒ vazio; reativação no lugar; `authenticated` sem leitura/DML/EXECUTE;
`admin` resolve bundle de 9 capabilities **sem conteúdo confidencial**.

### 2.3 Frontend/Policy Engine — onde ainda há simulação (F4-09/Q2)

- `src/authorization/mundoFuncional.ts` — mundo local **pré-F5**: providers do
  engine derivados dos **dados do seed DEV** + `bindingsDev` (binding DEV-only de
  capabilities derivado da **estrutura**, comentado como transitório: “a F5
  substitui por membership → access_role → capability”).
- `src/authorization/autorizacaoFuncional.ts` / `authorizationPolicy.ts` —
  fachadas de compatibilidade que montam o ator a partir do colaborador DEV
  (`actorId = String(matricula)`) e delegam ao engine com o mundo local.
- `src/authorization/Capability.ts` — **catálogo canônico TS** (capability =
  ação) usado pelo engine; contém também **aliases legados** mapeados por
  `canonicalizarCapability` (`canonical.ts`).
- **Nenhum** arquivo TS consome `resolver_capabilities_efetivas`/
  `resolver_capabilities_escopos_efetivas`/`membership_access_role_assignments`
  (grep verificado) — a resolução real ainda não está ligada ao runtime.

### 2.4 Gap objetivo: vocabulário DB × TS (evidência)

| Fonte | Exemplos de códigos |
| --- | --- |
| Catálogo DB (F4-01, 21) | `collaborator.read`, `collaborator.manage`, `observation.write`, `cycle.manage`, `membership.read`, `access_role.manage`, `org.structure.manage`, … |
| Catálogo canônico TS (engine) | `collaborator.create/edit/read`, `observation.create/edit/delete`, `cycle.cancel/reopen/period.correct`, `goal.write/approve`, `evaluation.*`, `report.read`, `exceptional_access.grant`, `pilot_full_access.grant` |

Há **divergência real**: o engine decide sobre o vocabulário TS canônico
(F4-09 §6.3), mas roles (no banco) concedem códigos **do catálogo DB**, que não
espelham 1:1 o TS (ex.: `collaborator.create/edit` e `cycle.period.correct` não
existem no DB; `observation.create/edit/delete` vs `observation.write`;
`membership.*`, `access_role.manage`, `org.*` não existem no TS). Também
`exceptional_access.grant`/`pilot_full_access.grant` (engine) **não** estão no
catálogo DB. Sem reconciliação, o provider real do engine não consegue traduzir
DB→engine de forma segura (false-ALLOW/DENY ou códigos órfãos).

---

## 3. Contratos anteriores relevantes (preservados)

- **F4-01 D3/D4/D12/D16:** roles são a única via de concessão; múltiplas roles
  por membership; atribuição por linha âncora; mecanismo mínimo server-side
  (DEFINER/service_role).
- **F4-02:** scope pertence à assignment (nunca à role); 1 par
  (assignment, scope_type) unique; scopes estruturais exigem vínculo
  (D17); ORGANIZATION explícito; ASSIGNED não deriva hierarquia.
- **F4-03:** Policy Engine = gate; providers `identity/capabilities/scopes/
  targets/relations` + origens temporária/excepcional/pilot (B/C/D); fail-closed.
- **F4-05/06/07:** substituição temporária (mapa capability×responsibility_type);
  acesso excepcional C (allowlist fechada de capabilities; nunca confidencial por
  ADMIN); Pilot Full Access D (dev-only, perfil fechado).
- **F4-08/F4-09/F4-10:** RLS real entre tenants; mundo local DEV transitório;
  matriz integrada de autorização.
- **F5-01/02/03:** identidade autenticada; vínculo membership→colaborador;
  organização ativa = intenção (server valida membership por operação).

---

## 4. Modelo proposto

### 4.1 Cadeia de privilégios efetivos (por organização validada)

```
(auth.uid) ─▶ membership ativa (org validada) ─▶ assignments (active)
        ─▶ access_roles (active; sistema ou org) ─▶ access_role_capabilities
        ─▶ capabilities (active)                = capabilities efetivas (união)
        ─▶ access_role_assignment_scopes (active) × capability = escopos efetivos
        ─▶ (alvo unit quando ORGANIZATIONAL_UNIT)
```

Invariante: **role → capability → (capability × scope)**. Nenhuma capability é
concedida fora de role (D3 F4-01). Scopes existem por assignment (F4-02).

### 4.2 Fontes de verdade

| Item | Fonte | Categoria |
| --- | --- | --- |
| `auth.uid()` | Sessão autenticada (Supabase) | Soberana |
| Organização validada | Membership ativa do `auth.uid()` (banco/RLS) | Soberana (derivada no servidor) |
| Membership ativa | `user_organization_memberships` | Soberana |
| Access roles do usuário na org | `membership_access_role_assignments` (active) → `access_roles` | Soberana (servidor) |
| Capabilities das roles | `access_role_capabilities` → `capabilities` | Soberana (servidor) |
| Scopes por assignment | `access_role_assignment_scopes` (+targets de unidade) | Soberana (servidor) |
| “Role/capability” informada pelo cliente | payload/JWT/localStorage/React | **Não confiável** (intenção nunca concede) |
| `actorId`/`organizationId` no engine | Derivado pela camada de aplicação (F5-05) do servidor | Derivada |

Regra de ouro: o **efeito** (ALLOW) é sempre calculado no servidor por
operação; nada do cliente aumenta o conjunto de roles/capabilities.

### 4.3 Membership ↔ access roles

- Uma membership pode ter **0..N access roles** (D4 F4-01); múltiplas roles
  produzem **união de capabilities** (validado em F4-01).
- Roles podem ser de **sistema** (atribuíveis a qualquer membership, ex.:
  `admin`) ou **customizadas da organização** (org-scoped; cross-tenant negado
  por trigger/FK).
- Uma linha por par (membership, role) em qualquer status; revogação no lugar.
- **Sem collaborator** (ADMIN): a resolução de roles/capabilities independe do
  vínculo F5-02; apenas **scopes estruturais** (SELF/DR/…) ficam vazios (D17
  F4-02).

### 4.4 Derivação de capabilities efetivas

```
capabilities_efetivas(org) =
  ⋃  { c.code | assignment a (active) da membership ativa do auth.uid em org,
                 role r = a.role (active), rc ∈ access_role_capabilities(r),
                 c = capability(rc.capability), c.status = active }
```
Espelhada por `resolver_capabilities_efetivas` (sem escopo) e por
`resolver_capabilities_escopos_efetivas` (com escopo) — **chamadas por operação
no servidor**, sem cache de decisão entre requisições.

### 4.5 Capabilities diretas?

**Não** (D3 F4-01): capability é sempre herdada de uma access role. A F5-04
mantém esse contrato; capabilities “extras” só entram via **nova role** ou
**adição de capability a role existente** (server-side). Não há tabela de
“capability direta por usuário/membership”.

### 4.6 Interação com scopes

- O par (capability, scope) efetivo é o que o engine consome em runtime real
  (`hasCapability` + `getActiveScopes` + relação/target). A F4-02 já resolve
  isso por (user_profile, org).
- Scopes estruturais dependem do **vínculo** (F5-02); sem vínculo ⇒ vazios.
- ASSIGNED/colegiado não é derivado de role (F4-02/F4-04); permanece regra do
  engine.

### 4.7 Interação com o Policy Engine

O engine (F4-03) já é agnóstico. A F5-04 define o **provider real** a ser
usado por F5-05:

```
CapabilityProvider.hasCapability(actorId=auth.uid, org, cap)
   → cap ∈ resolver_capabilities_escopos_efetivas(auth.uid, org)
ScopeProvider.getActiveScopes(actorId, org)
   → scopes das assignments ativas (F4-02)
RelationProvider / TargetProvider
   → estrutura (F3) via resolvers, dentro do tenant
```

Contrato F5-04: fornecer (server-side) o **conjunto efetivo** e a **tradução
DB→engine** dos códigos; o engine decide. Nenhuma capability/scope chega do
cliente.

---

## 5. Isolamento entre organizações

- Roles customizadas são org-scoped; atribuições carregam `organization_id`
  garantido pela FK composta; trigger bloqueia role de outra org; roles de
  sistema são atribuíveis por membership (ainda assim **scoped à organização da
  membership** na resolução).
- Resolução sempre por `(user_profile_id, organization_id)` com membership ativa
  — sem vazamento cross-tenant (validado F4-01: usuário sem membership na org
  resolve vazio).
- RLS mantém as tabelas de autorização **fechadas** a `authenticated` (F4-08);
  nenhuma abertura genérica.

---

## 6. Revogação e TOCTOU

- Revogação: `revogar_acesso_role` (status `revoked`, sem delete); desativar a
  **role** (`access_roles.status='disabled'`) ou a **capability**
  (`capabilities.status='disabled'`) ou a **membership** também cortam o efeito,
  porque o resolver reavalia **todos os elos ativos** a cada chamada.
- **Anti-stale:** nenhum cache de ALLOW entre operações; a decisão do engine e
  o RLS reavaliam membership/role/capability/scope no momento da operação.
  TOCTOU (revogação entre T0 e T2) ⇒ DENY na operação em T2 — mesmo princípio da
  F5-03 (§6).
- Reativação no lugar (uma linha por par) preserva histórico.

---

## 7. RLS / policies

- Sem novas policies nesta F5-04: tabelas de autorização permanecem fechadas
  (F4-08); funções de resolução permanecem sem `EXECUTE` para `authenticated`
  (Q1/Q2 F5-02 e F4-08 preservados).
- Nenhum `SECURITY DEFINER` novo **sem** necessidade explícita: os DEFINER já
  existentes (conceder/revogar/resolver F4-01) são suficientes; novas funções
  (se aprovadas em Q1/Q2) seguem o mesmo padrão de grants (service_role).

---

## 8. Funções/resolvers necessários

Existentes e reutilizados: `resolver_capabilities_efetivas`,
`resolver_capabilities_escopos_efetivas`, `conceder_acesso_role`,
`revogar_acesso_role`, helpers F4-08.

Possíveis acréscimos (condicionados às questões):
- **Q1:** migration aditiva de **reconciliação de catálogo** (códigos DB =
  canônicos do engine; deprecação de aliases) e ajuste do espelho TS + teste de
  paridade DB↔TS.
- **Q2:** se capabilities de gestão de acesso (ex.: `membership.manage`,
  `access_role.manage`) e as de C/D (`exceptional_access.grant`,
  `pilot_full_access.grant`) entrarem no catálogo concedível — decisão e
  possíveis funções de gestão de role por organização (server-side) e guards.
- Nenhuma função executável pelo frontend.

---

## 9. Impacto no frontend e no backend/Supabase

- **Frontend:** `can()`/`authorize()` continuam servindo UX/enforcement; a fonte
  de capabilities para UI passa (em F5-05) a ser o resultado **server-side**
  (nunca role/capability em localStorage/estado). Nesta F5-04 não há mudança de
  UI obrigatória.
- **Backend/Supabase:** a F5-04 consolida a resolução efetiva (DB +
  contrato) e prevê a migration aditiva de reconciliação do catálogo; mantém o
  modelo F4-01/02 intacto no que não é defeito.

---

## 10. Compatibilidade com F4-05/06/07

- **B** (substituição temporária): resolve por responsabilidade temporária
  (F3-06) → mapa capability×responsibility_type (F4-05). A F5-04 não mistura:
  origem B é alternativa/união na decisão do engine, não “role”.
- **C** (excepcional): grants por `beneficiaryUserProfileId`; não dependem de
  role; a F5-04 não os altera. C é consultado **somente** quando A/B DENY e o
  alvo é confidencial (contrato F4-06).
- **D** (pilot): dev-only, perfil fechado; não vira role.
- A F5-04 apenas garante que a origem **A** (membership→role→capability) seja a
  fonte real e que C/D continuem **independentes** e com seus guards.

---

## 11. Limites F5-04 × F5-05

- **F5-04:** contrato da resolução efetiva de roles/capabilities/scopes por
  membership/org; catálogo reconciliado; invariantes; testes; server-side.
- **F5-05:** montar `ActorContext`/`ResourceContext` — instanciar o provider
  real no engine com `actorId=auth.uid()` + org validada + vínculo, carregar
  recursos por tenant e alimentar `authorize()/can()` reais. **Não antecipar.**

---

## 12. Estratégia de implementação futura (pós-aprovação)

1. Reconciliação de catálogo (Q1) com migration aditiva + espelho TS + teste de
   paridade.
2. Ajuste (se necessário) dos validadores F4-01/F4-02 para o novo catálogo
   (contagens/bundles) sem reescrever o contrato.
3. Definição/implementação de quaisquer funções server-side novas (Q2/Q3).
4. Testes de contrato (seção 14) via `supabase/validacao`.
5. F5-05 consome o resultado.

---

## 13. Critérios de aceite (propostos)

1. Resolução efetiva por `(auth.uid, org validada)` derivada somente do banco
   (membership → role → capability → scope), fail-closed e sem cache entre
   operações.
2. Catálogo DB ↔ vocabulário TS do engine reconciliados (sem códigos órfãos);
   teste de paridade.
3. Múltiplas roles ⇒ união; sem role ⇒ vazio; membership/perfil/role/capability
   desabilitados ⇒ vazio.
4. Cross-tenant impossível (roles/atribuições/resolução); nenhuma superfície nova
   a `authenticated`; nenhum `SECURITY DEFINER` novo desnecessário.
5. ADMIN sem collaborator resolve capabilities org-scoped; scopes estruturais
   vazios; ADMIN não lê confidencial (bundle sem conteúdo).
6. Revogação/desativação ⇒ efeito imediato na próxima operação (sem stale);
   TOCTOU coberto.
7. F4-05/06/07 e F5-01/02/03 preservados.

---

## 14. Estratégia de testes (proposta)

- **SQL (`supabase/validacao`):** reexecutar/estender F4-01/F4-02 (união de
  roles, revogação, reativação, lifecycle, cross-tenant, RLS fechado) e cenários
  novos: reconhecimento do catálogo reconciliado; nenhum código órfão.
- **TS:** teste de **paridade DB↔TS** (conjunto de códigos do espelho == união
  canônica do engine); providers reais (F5-05) apenas tipados nesta fase.
- **Segurança:** spoofing de role/capability pelo cliente ⇒ sem efeito; payload
  com capability extra ⇒ DENY; IDOR cross-tenant; revogação mid-session ⇒ DENY.

---

## 15. Riscos

| Risco | Mitigação |
| --- | --- |
| Divergência de catálogo DB×TS causando false-ALLOW/DENY | Q1: reconciliação + teste de paridade |
| Capabilities de gestão de acesso viram privilégio | Q2: restrição (system-only) + least privilege |
| Stale após revogação | Reavaliação por operação; sem cache de ALLOW |
| C/D “misturados” a roles | Origem C/D permanece independente (F4-06/07) |
| Frontend confiando em role/capability local | Nunca; só UX (`can`) com fonte server-side (F5-05) |
| Regressão de fixtures/validadores F4 | Ajuste aditivo de validadores, sem reescrever contrato |

---

## 16. Fora de escopo (F5-04)

- ActorContext/ResourceContext e instalação do provider real no runtime (F5-05);
- UI de gestão de roles/capabilities por organização (fluxo administrativo);
- migração de domínios funcionais/persistência remota; localStorage geral;
- hardening geral (F6); hosting/observabilidade/backup;
- redesenho do Policy Engine ou dos contratos F4-01/02/03/05/06/07.

---

## 17. Decisões arquiteturais (D1–D13 — PROPOSTAS)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | Role = única via de capability | Mantém D3 F4-01: nenhuma capability direta por usuário/membership; novas capabilities entram por role | PROPOSTA |
| D2 | Fonte soberana de privilégios | `(auth.uid, org validada)` → membership → assignments → roles → capabilities (+scopes), resolvido no servidor; nunca do cliente/JWT/localStorage/estado | PROPOSTA |
| D3 | Múltiplas roles = união | 0..N roles por membership; capabilities efetivas = união das roles ativas (F4-01) | PROPOSTA |
| D4 | Scope acompanha assignment | Par (capability, scope) efetivo vem da F4-02 por (user_profile, org); scopes estruturais exigem vínculo (D17 F4-02) | PROPOSTA |
| D5 | Engine consumidor final | Providers reais (F5-05) usam `resolver_capabilities_efetivas`/`resolver_capabilities_escopos_efetivas`; engine decide | PROPOSTA |
| D6 | Catálogo DB = fonte dos códigos concedíveis | TS mantém união literal espelhando o DB; teste de paridade; reconciliação via migration aditiva (Q1) | PROPOSTA (depende Q1) |
| D7 | Sem capability direta e sem role fantasma por cargo | Nenhuma role/capability derivada de job_role/função; ADMIN é role de sistema atribuível por membership | PROPOSTA |
| D8 | Revogação por estado, efeito imediato | `revoked`/`disabled` cortam o efeito na próxima operação; reativação no lugar; sem cache de ALLOW (TOCTOU) | PROPOSTA |
| D9 | Isolamento por organização | Roles customizadas org-scoped; atribuição com tenant por FK/trigger; resolução por org validada; cross-tenant DENY | PROPOSTA |
| D10 | Nenhuma superfície nova a authenticated | Tabelas fechadas; resolvers sem `EXECUTE` p/ `authenticated`; DEFINER novos só com necessidade explícita (Q2) | PROPOSTA |
| D11 | ADMIN sem colaborador | Roles/capabilities org-scoped resolvem; scopes estruturais vazios; ADMIN sem conteúdo confidencial | PROPOSTA |
| D12 | C/D/B independentes de role | Substituição temporária, acesso excepcional e pilot continuam origens próprias no engine (F4-05/06/07) | PROPOSTA |
| D13 | Limite F5-04 × F5-05 | F5-04 fecha o contrato de privilégios efetivos; ActorContext/ResourceContext é F5-05 | PROPOSTA |

---

## 18. Questões para validação

### Q1 — Reconciliação do catálogo DB × vocabulário canônico do engine

- **Contexto:** o engine (F4-09 §6.3) decide sobre o vocabulário TS canônico
  (`src/authorization/Capability.ts`), mas as roles no banco concedem códigos do
  catálogo DB (F4-01, 21 códigos) que **não espelham 1:1** o TS (ex.:
  `collaborator.create/edit` e `cycle.period.correct` ausentes no DB;
  `observation.write` vs `observation.create/edit/delete`; `membership.*`,
  `access_role.manage`, `org.*` ausentes no TS; `exceptional_access.grant`/
  `pilot_full_access.grant` ausentes no DB).
- **Problema:** sem alinhamento, o provider real DB→engine não consegue
  traduzir de forma segura → false-ALLOW/DENY ou códigos órfãos.
- **Alternativas:**
  - (A) **DB = fonte**: migration aditiva adiciona ao catálogo os códigos
    canônicos ausentes (e deprecia/mantém os existentes), e o TS mantém união
    literal + lista-espelho com **teste de paridade** (DB↔TS) — recomendada;
  - (B) renomear códigos do DB para bater com o TS (mais invasivo; exige
    atualização de fixtures/validadores/seed);
  - (C) tradução runtime DB→TS em um mapper (tabela de equivalência) — frágil,
    duplica verdade.
- **Recomendação:** (A) — fonte única no DB; espelho TS verificável; aliases
  legados só para regressão.
- **Impacto/risco:** migration aditiva + ajuste de validadores F4-01 (contagem de
  capabilities/bundle admin) e de testes TS; baixo se aditivo.
- **Seções dependentes:** 2.4, 4.4, 8, 12, 14, D6.

### Q2 — Capabilities de gestão de acesso e de C/D no catálogo concedível?

- **Contexto:** o catálogo DB contém `membership.manage`, `access_role.manage`
  (gestão de acesso) e o engine usa `exceptional_access.grant`,
  `pilot_full_access.grant` (gestão de C/D) — estes últimos **não** existem no
  DB.
- **Problema:** se concedíveis por roles customizadas/org, criam vetor de
  **privilege escalation** (quem gerencia roles concede a si mesmo mais roles) e
  podem expor C/D de forma indevida.
- **Alternativas:**
  - (A) capabilities de **gestão de acesso** e de **C/D** ficam **fora do
    catálogo concedível por role** (ou restritas a roles de sistema/allowlist
    server-side explícita) — recomendada (least privilege);
  - (B) concedíveis por role, com auditoria e restrições adicionais.
- **Recomendação:** (A) — restringir a concessão de “meta-capabilities” de
  acesso a caminhos administrativos auditados (allowlist/funções DEFINER já
  existentes), nunca a roles auto-servidas.
- **Impacto/risco:** define limites da “gestão de acesso” (Q3); evita
  escalation; pode exigir migration para separar meta-capabilities.
- **Seções dependentes:** 2.4, 4.5, 8, 10, D10, Q3.

### Q3 — Fluxo administrativo de concessão/revogação por organização (quem administra roles)

- **Contexto:** `conceder_acesso_role`/`revogar_acesso_role` são DEFINER
  service_role; a autorização administrativa atual é provisória (allowlist em
  Edge F2-06/07); não há UI de gestão de roles.
- **Problema:** F5-04 precisa definir **quem** pode atribuir roles em uma
  organização e por qual caminho, sem abrir DML/execução a `authenticated`.
- **Alternativas:**
  - (A) caminho server-side transacional (Edge Function/RPC) que valida
    `membership.manage`/`access_role.manage` do ator (resolvido server-side)
    antes de chamar as funções DEFINER — recomendada;
  - (B) manter apenas service_role/tooling interno nesta fase (gestão de roles
    fora do produto até F5 posterior).
- **Recomendação:** (A) desenhada, implementada com capacidade de gestão
  restrita (Q2) e auditoria (`created_by` já existe).
- **Impacto/risco:** superfície administrativa nova; mitigada por grants
  service_role + validação server-side.
- **Seções dependentes:** 4.3, 8, 12, D8/D9/D10, Q2.

### Q4 — Cache intra-requisição de capabilities/roles: permitido?

- **Contexto:** o resolver é chamado por operação; caro para consultas
  frequentes; um cache mal feito geraria stale.
- **Problema:** decidir onde (se) cachear sem violar revogação/TOCTOU.
- **Alternativas:**
  - (A) **sem cache entre requisições**; no máximo cache **dentro da mesma
    requisição/transação** (igual para todas as chamadas do engine naquele
    request) — recomendada;
  - (B) cache com TTL curto — rejeitada (janela de stale).
- **Recomendação:** (A).
- **Impacto/risco:** custo de resolução por operação; aceitável (queries
  indexadas).
- **Seções dependentes:** 6, 13, D8.

### Q5 — Como o `created_by`/auditoria de atribuições deve evoluir (rastreabilidade completa)?

- **Contexto:** atribuições têm `created_by` mínimo (D13 F4-01) e
  `updated_at/version`; não há histórico por evento de concessão/revogação.
- **Problema:** produto pode exigir trilha de auditoria completa de quem
  concedeu/revogou e quando.
- **Alternativas:**
  - (A) manter mínimo nesta fase (atributo/autor + timestamps bastam) —
    recomendada; histórico por eventos quando o domínio de gestão de acesso
    existir;
  - (B) criar tabela de eventos de atribuição (append-only) agora.
- **Recomendação:** (A) — sem nova tabela nesta F5-04; requisito registrado.
- **Impacto/risco:** rastreabilidade limitada à linha; aceitável enquanto a
  gestão de acesso é restrita (Q2/Q3).
- **Seções dependentes:** 4.3, 8, D8.

---

## 19. Confirmações desta atividade

- Nenhuma implementação funcional; **somente** este documento.
- Análise baseada no estado real: migrations F4-01/F4-02 e catálogo de sistema,
  validadores `02-validar-f4-01.sql`, `mundoFuncional.ts` (binding DEV
  transitório), `Capability.ts`/`canonical.ts` e o grep de ausência de consumo
  TS dos resolvers DB.
- Decisões D1–D13 **propostas**; questões Q1–Q5 registradas (podem permanecer
  abertas no PR). **Não implementar enquanto houver decisão aberta.**
