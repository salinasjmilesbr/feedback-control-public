# F5-04 — Access roles / capabilities reais (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de análise e desenho, sem código funcional**.
> Estado: **FECHADO — contrato pronto para implementação** (revisão no PR #166).
> Q1–Q5 **resolvidas** e incorporadas como **D14–D18**; D1–D18 **FECHADAS**.
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
catálogo DB. **Fechado por D14/D15** (ver §17): o **DB é a fonte canônica** dos
códigos concedíveis por role, com **convergência controlada DB ↔ engine** e
teste de paridade.

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
| Catálogo de códigos concedíveis | **`public.capabilities` (DB)** — espelho TS literal só verifica (D14) | Soberana (servidor) |
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

**Fail-closed do vocabulário (D14):** código de capability **desconhecido/que
não existe no catálogo DB** ⇒ tratado como **DENY** — **nenhuma tradução
fuzzy/permissiva** entre DB e engine; a convergência é feita **no catálogo**
(migration aditiva) e verificada por **teste de paridade**, nunca por mapper em
runtime.

### 4.5 Capabilities diretas e plano administrativo

- **Capabilities funcionais:** sempre herdadas de access role (D3 F4-01); não há
  tabela de “capability direta por usuário/membership”.
- **Plano funcional × plano administrativo (D15):** capabilities que administram
  o próprio mecanismo (`membership.manage`, `access_role.manage` e as de C/D —
  `exceptional_access.grant`, `pilot_full_access.grant`) **não são concedíveis
  por role auto-servida**: pertencem ao plano administrativo de controle,
  restritas a caminhos server-side auditados; **prevenção de self-escalation**
  (quem concede não pode se auto-conceder plano administrativo). `exceptional_
  access.grant` e `pilot_full_access.grant` ficam **fora do catálogo concedível
  por role**.

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
cliente. Código desconhecido pelo engine ⇒ DENY (D14).

---

## 5. Isolamento entre organizações

- Roles customizadas são org-scoped; atribuições carregam `organization_id`
  garantido pela FK composta; trigger bloqueia role de outra org; roles de
  sistema são atribuíveis por membership (ainda assim **scoped à organização da
  membership** na resolução).
- Resolução sempre por `(user_profile_id, organization_id)` com membership ativa
  — sem vazamento cross-tenant (validado F4-01: usuário sem membership na org
  resolve vazio).
- Operações administrativas revalidam o **tenant** contra membership ativa do
  ator (D16); cross-tenant = DENY.
- RLS mantém as tabelas de autorização **fechadas** a `authenticated` (F4-08);
  nenhuma abertura genérica.

---

## 6. Revogação, TOCTOU e trilha de mutações

- Revogação: `revogar_acesso_role` (status `revoked`, sem delete); desativar a
  **role** (`access_roles.status='disabled'`) ou a **capability**
  (`capabilities.status='disabled'`) ou a **membership** também cortam o efeito,
  porque o resolver reavalia **todos os elos ativos** a cada chamada.
- **Sem cache de ALLOW entre requisições (D17):** cache no máximo **intra-
  request**; a decisão do engine e o RLS reavaliam membership/role/capability/
  scope no momento da operação — **revogação efetiva na operação subsequente**.
  TOCTOU (revogação entre T0 e T2) ⇒ DENY na operação em T2 — mesmo princípio da
  F5-03 (§6).
- Reativação no lugar (uma linha por par) preserva histórico.
- **Trilha de mutações (D18):** mutações de privilégio (conceder/revogar
  atribuições e alterações de role/capability que afetem privilégios) geram
  registro **append-only** (ou equivalente rastreável) com **autoria soberana**
  (o ator é derivado de `auth.uid()` e validado server-side), registrando quem
  mutou, o quê, quando e com qual organização — preservando a trilha existente
  (`created_by`/`version` já presentes) e evoluindo para tabela de eventos quando
  o domínio administrativo exigir.

---

## 7. RLS / policies

- Sem novas policies nesta F5-04: tabelas de autorização permanecem fechadas
  (F4-08); funções de resolução permanecem sem `EXECUTE` para `authenticated`
  (Q1/Q2 F5-02 e F4-08 preservados).
- Nenhum `SECURITY DEFINER` novo **sem** necessidade explícita: os DEFINER já
  existentes (conceder/revogar/resolver F4-01) são suficientes; novas funções
  seguem o mesmo padrão de grants (service_role) e são **transacionais/
  server-side** (D16).

---

## 8. Funções/resolvers necessários

Existentes e reutilizados: `resolver_capabilities_efetivas`,
`resolver_capabilities_escopos_efetivas`, `conceder_acesso_role`,
`revogar_acesso_role`, helpers F4-08.

Acréscimos (conforme decisões fechadas):
- **D14:** migration aditiva de **reconciliação de catálogo** (códigos DB =
  canônicos do engine; deprecação de aliases sem remoção física) + **teste de
  paridade** DB↔TS.
- **D15:** **separação do plano administrativo**: capabilities de controle e de
  C/D fora do concedível por role; funções/guards de gestão restritas a
  server-side/transacional com validação do ator e anti-self-escalation.
- **D16:** operações administrativas (conceder/revogar/gerir roles) via RPC/Edge
  transacional (DEFINER service_role), ator soberano `auth.uid()` + tenant
  revalidado.
- **D18:** funções/registro append-only da trilha de mutações de privilégio.
- Nenhuma função executável pelo frontend.

---

## 9. Impacto no frontend e no backend/Supabase

- **Frontend:** `can()`/`authorize()` continuam servindo UX/enforcement; a fonte
  de capabilities para UI passa (em F5-05) a ser o resultado **server-side**
  (nunca role/capability em localStorage/estado). Nesta F5-04 não há mudança de
  UI obrigatória.
- **Backend/Supabase:** a F5-04 consolida a resolução efetiva (DB + contrato) e
  prevê a migration aditiva de reconciliação do catálogo; mantém o modelo
  F4-01/02 intacto no que não é defeito.

---

## 10. Compatibilidade com F4-05/06/07

- **B** (substituição temporária): resolve por responsabilidade temporária
  (F3-06) → mapa capability×responsibility_type (F4-05). A F5-04 não mistura:
  origem B é alternativa/união na decisão do engine, não “role”.
- **C** (excepcional): grants por `beneficiaryUserProfileId`; não dependem de
  role; a F5-04 não os altera. C é consultado **somente** quando A/B DENY e o
  alvo é confidencial (contrato F4-06). `exceptional_access.grant` (gestão de C)
  fica **fora do catálogo concedível por role** (D15).
- **D** (pilot): dev-only, perfil fechado; não vira role;
  `pilot_full_access.grant` fica **fora do catálogo concedível por role** (D15).
- A F5-04 apenas garante que a origem **A** (membership→role→capability) seja a
  fonte real e que C/D continuem **independentes** e com seus guards.

---

## 11. Limites F5-04 × F5-05

- **F5-04:** contrato da resolução efetiva de roles/capabilities/scopes por
  membership/org; catálogo reconciliado; invariantes; plano administrativo
  separado; testes; server-side.
- **F5-05:** montar `ActorContext`/`ResourceContext` — instanciar o provider
  real no engine com `actorId=auth.uid()` + org validada + vínculo, carregar
  recursos por tenant e alimentar `authorize()/can()` reais. **Não antecipar.**

---

## 12. Estratégia de implementação futura (pós-aprovação)

1. **D14 — Reconciliação de catálogo:** migration aditiva alinhando o catálogo DB
   ao vocabulário canônico do engine; espelho TS literal; **teste de paridade**
   (DB↔TS) em CI; ajuste aditivo dos validadores F4-01/F4-02 (contagens/bundles).
2. **D15 — Plano administrativo separado:** definir/implementar restrições para
   capabilities de controle e C/D fora do concedível por role; guards de
   anti-self-escalation.
3. **D16 — Operações administrativas server-side/transacionais:** RPC/Edge com
   ator soberano `auth.uid()` + tenant revalidado, sobre as funções DEFINER
   existentes.
4. **D17 — Política de cache:** nenhum cache de ALLOW entre requisições.
5. **D18 — Trilha append-only** de mutações de privilégio com autoria soberana.
6. Testes do contrato (seção 14) via `supabase/validacao` + TS.
7. F5-05 consome o resultado.

---

## 13. Critérios de aceite

1. Resolução efetiva por `(auth.uid, org validada)` derivada somente do banco
   (membership → role → capability → scope), fail-closed e sem cache de ALLOW
   entre requisições (D17).
2. **DB é a fonte canônica dos códigos concedíveis por role (D14)**; convergência
   controlada DB↔engine com **migration aditiva** e **teste automatizado de
   paridade**; **código desconhecido ⇒ DENY** (fail-closed); **sem tradução
   fuzzy/permissiva** em runtime.
3. **Plano funcional de roles separado do plano administrativo de controle
   (D15)**; `exceptional_access.grant` e `pilot_full_access.grant` **fora do
   catálogo concedível por role**; **prevenção de self-escalation**.
4. **Operações administrativas exclusivamente server-side/transacionais (D16)**;
   ator soberano derivado de `auth.uid()`; **tenant revalidado** contra
   membership ativa; **cross-tenant DENY**.
5. Múltiplas roles ⇒ união; sem role ⇒ vazio; membership/perfil/role/capability
   desabilitados ⇒ vazio; **revogação efetiva na operação subsequente**.
6. **Trilha append-only/equivalente** para mutações de privilégio, com autoria
   soberana (D18).
7. Cross-tenant impossível (roles/atribuições/resolução); nenhuma superfície nova
   a `authenticated`; nenhum `SECURITY DEFINER` novo desnecessário.
8. ADMIN sem collaborator resolve capabilities org-scoped; scopes estruturais
   vazios; ADMIN não lê confidencial (bundle sem conteúdo).
9. F4-05/06/07 e F5-01/02/03 preservados.

---

## 14. Estratégia de testes

- **SQL (`supabase/validacao`):** reexecutar/estender F4-01/F4-02 (união de
  roles, revogação, reativação, lifecycle, cross-tenant, RLS fechado) + cenários
  novos: catálogo reconciliado sem códigos órfãos; concessão de capability de
  controle/C-D **fora do concedível** ⇒ negada; self-escalation ⇒ negada;
  operação administrativa cross-tenant ⇒ negada; trilha append-only registrada
  com autoria.
- **TS:** **teste de paridade DB↔TS** (conjunto de códigos do catálogo DB ==
  união canônica do engine); teste de **código desconhecido ⇒ DENY** (provider
  real tipado em F5-05); regressão F4/F5-01..03.
- **Segurança:** spoofing de role/capability pelo cliente ⇒ sem efeito; payload
  com capability extra/desconhecida ⇒ DENY; IDOR cross-tenant; revogação
  mid-session ⇒ DENY na operação seguinte.

---

## 15. Riscos

| Risco | Mitigação |
| --- | --- |
| Divergência de catálogo DB×TS causando false-ALLOW/DENY | D14: reconciliação + teste de paridade; desconhecido ⇒ DENY |
| Capabilities de gestão/controle viram privilégio auto-servido | D15: plano administrativo separado; C/D fora do concedível; anti-self-escalation |
| Stale após revogação | D17: sem cache de ALLOW entre requisições; revogação na operação seguinte |
| C/D “misturados” a roles | D15/D12: origens C/D independentes (F4-06/07) e fora do concedível |
| Frontend confiando em role/capability local | Nunca; só UX (`can`) com fonte server-side (F5-05) |
| Auditoria insuficiente de mutações | D18: trilha append-only com autoria soberana |
| Regressão de fixtures/validadores F4 | Ajuste aditivo de validadores, sem reescrever contrato |

---

## 16. Fora de escopo (F5-04)

- ActorContext/ResourceContext e instalação do provider real no runtime (F5-05);
- UI de gestão de roles/capabilities por organização (fluxo administrativo);
- migração de domínios funcionais/persistência remota; localStorage geral;
- hardening geral (F6); hosting/observabilidade/backup;
- redesenho do Policy Engine ou dos contratos F4-01/02/03/05/06/07.

---

## 17. Decisões arquiteturais (D1–D18 — FECHADAS)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | Role = única via de capability | Mantém D3 F4-01: nenhuma capability direta por usuário/membership; novas capabilities entram por role | FECHADA |
| D2 | Fonte soberana de privilégios | `(auth.uid, org validada)` → membership → assignments → roles → capabilities (+scopes), resolvido no servidor; nunca do cliente/JWT/localStorage/estado | FECHADA |
| D3 | Múltiplas roles = união | 0..N roles por membership; capabilities efetivas = união das roles ativas (F4-01) | FECHADA |
| D4 | Scope acompanha assignment | Par (capability, scope) efetivo vem da F4-02 por (user_profile, org); scopes estruturais exigem vínculo (D17 F4-02) | FECHADA |
| D5 | Engine consumidor final | Providers reais (F5-05) usam `resolver_capabilities_efetivas`/`resolver_capabilities_escopos_efetivas`; engine decide | FECHADA |
| D6 | Catálogo DB = fonte dos códigos concedíveis | TS mantém união literal espelhando o DB; teste de paridade; reconciliação via migration aditiva (detalhe em D14) | FECHADA |
| D7 | Sem capability direta e sem role fantasma por cargo | Nenhuma role/capability derivada de job_role/função; ADMIN é role de sistema atribuível por membership | FECHADA |
| D8 | Revogação por estado, efeito imediato | `revoked`/`disabled` cortam o efeito na próxima operação; reativação no lugar; sem cache de ALLOW (D17) | FECHADA |
| D9 | Isolamento por organização | Roles customizadas org-scoped; atribuição com tenant por FK/trigger; resolução por org validada; cross-tenant DENY | FECHADA |
| D10 | Nenhuma superfície nova a authenticated | Tabelas fechadas; resolvers sem `EXECUTE` p/ `authenticated`; DEFINER novos só com necessidade explícita | FECHADA |
| D11 | ADMIN sem colaborador | Roles/capabilities org-scoped resolvem; scopes estruturais vazios; ADMIN sem conteúdo confidencial | FECHADA |
| D12 | C/D/B independentes de role | Substituição temporária, acesso excepcional e pilot continuam origens próprias no engine (F4-05/06/07) | FECHADA |
| D13 | Limite F5-04 × F5-05 | F5-04 fecha o contrato de privilégios efetivos; ActorContext/ResourceContext é F5-05 | FECHADA |
| D14 | Catálogo canônico = DB; convergência controlada (resolve Q1) | DB é a **fonte canônica** dos códigos concedíveis por role; espelho TS literal + **teste automatizado de paridade**; **migration aditiva**; **código desconhecido ⇒ DENY (fail-closed)**; **sem tradução fuzzy/permissiva** em runtime | FECHADA |
| D15 | Plano funcional × plano administrativo (resolve Q2) | Capabilities funcionais por role; capabilities de **controle** (`membership.manage`, `access_role.manage`) e **C/D** (`exceptional_access.grant`, `pilot_full_access.grant`) **fora do catálogo concedível por role**; **prevenção de self-escalation** | FECHADA |
| D16 | Operações administrativas server-side/transacionais (resolve Q3) | Conceder/revogar/gerir roles via RPC/Edge transacional (DEFINER service_role); **ator soberano derivado de auth.uid()**; **tenant revalidado** contra membership ativa; **cross-tenant DENY** | FECHADA |
| D17 | Sem cache de ALLOW entre requisições (resolve Q4) | Cache no máx. intra-request; **revogação efetiva na operação subsequente** (TOCTOU) | FECHADA |
| D18 | Trilha append-only de mutações de privilégio (resolve Q5) | Mutações de privilégio geram registro **append-only/equivalente** com **autoria soberana** (ator `auth.uid()` validado server-side) | FECHADA |

---

## 18. Questões para validação (Q1–Q5 — FECHADAS/APROVADAS)

Rastreabilidade: cada questão foi **resolvida** na revisão (PR #166) e incorporada
como **decisão fechada (D14–D18)**. Mantidas abaixo apenas para rastreamento.

### Q1 — Reconciliação do catálogo DB × vocabulário canônico do engine — **FECHADA (resolvida por D14)**

- **Contexto:** o engine decide sobre o vocabulário TS canônico, mas as roles no
  banco concedem códigos do catálogo DB que não espelham 1:1 o TS.
- **Problema:** sem alinhamento, o provider real DB→engine não traduz de forma
  segura.
- **Alternativas:** (A) DB = fonte + migration aditiva + espelho TS + teste de
  paridade; (B) renomear códigos DB; (C) mapper de equivalência em runtime.
- **Decisão (A — D14):** DB como fonte canônica; convergência controlada DB↔engine;
  migration aditiva; teste automatizado de paridade; código desconhecido ⇒ DENY;
  sem tradução fuzzy/permissiva.
- **Impacto/risco:** migration aditiva + ajuste de validadores; baixo se aditivo.
- **Seções dependentes:** 2.4, 4.4, 8, 12, 14, D6, D14.

### Q2 — Capabilities de gestão de acesso e de C/D no catálogo concedível? — **FECHADA (resolvida por D15)**

- **Contexto:** catálogo contém `membership.manage`/`access_role.manage`; engine
  usa `exceptional_access.grant`/`pilot_full_access.grant`, ausentes no DB.
- **Problema:** risco de privilege escalation e exposição de C/D.
- **Alternativas:** (A) fora do concedível por role (controle restrito server-
  side); (B) concedíveis por role com auditoria.
- **Decisão (A — D15):** separação entre plano funcional de roles e plano
  administrativo de controle; C/D fora do catálogo concedível por role;
  prevenção de self-escalation.
- **Impacto/risco:** limita a gestão de acesso a caminhos auditados; evita
  escalation.
- **Seções dependentes:** 4.5, 8, 10, D10, D15, Q3.

### Q3 — Fluxo administrativo de concessão/revogação por organização — **FECHADA (resolvida por D16)**

- **Contexto:** `conceder_acesso_role`/`revogar_acesso_role` são DEFINER
  service_role; autorização administrativa atual provisória (allowlist); sem UI.
- **Problema:** definir quem atribui roles e por qual caminho.
- **Alternativas:** (A) RPC/Edge transacional validando o ator e a capacidade de
  gestão restrita (server-side); (B) apenas service_role/tooling nesta fase.
- **Decisão (A — D16):** operações administrativas **exclusivamente
  server-side/transacionais**; ator soberano derivado de `auth.uid()`; tenant
  revalidado; cross-tenant DENY.
- **Impacto/risco:** superfície nova mitigada por grants service_role + validação
  server-side + auditoria (D18).
- **Seções dependentes:** 4.3, 8, 12, D8/D9/D10/D16, Q2.

### Q4 — Cache intra-requisição de capabilities/roles — **FECHADA (resolvida por D17)**

- **Contexto:** resolver chamado por operação; cache mal feito geraria stale.
- **Problema:** decidir onde cachear sem violar revogação/TOCTOU.
- **Alternativas:** (A) sem cache entre requisições (no máx. intra-request);
  (B) cache com TTL curto.
- **Decisão (A — D17):** sem cache de ALLOW entre requisições; revogação efetiva
  na operação subsequente.
- **Impacto/risco:** custo de resolução por operação; aceitável (queries
  indexadas).
- **Seções dependentes:** 6, 13, D8, D17.

### Q5 — Auditoria/rastreabilidade de mutações de privilégio — **FECHADA (resolvida por D18)**

- **Contexto:** atribuições têm `created_by`/`version`; não há histórico por
  evento.
- **Problema:** trilha completa de quem concedeu/revogou.
- **Alternativas:** (A) manter mínimo nesta fase; (B) tabela de eventos
  append-only agora.
- **Decisão (B — D18):** trilha **append-only/equivalente** para mutações de
  privilégio, com **autoria soberana**; evolução para tabela de eventos quando o
  domínio administrativo exigir.
- **Impacto/risco:** novo artefato de auditoria (design); sem abrir superfície a
  `authenticated`.
- **Seções dependentes:** 4.3, 6, 8, 13, 14, D18.

---

## 19. Confirmações desta atividade

- Nenhuma implementação funcional; **somente** este documento (atualização na
  mesma branch/PR #166).
- Q1–Q5 **FECHADAS/APROVADAS** e incorporadas como **D14–D18** (rastreabilidade
  explícita na §18); nenhuma questão arquitetural permanece aberta.
- D1–D18 **FECHADAS**; estado “PROPOSTA” removido; critérios de aceite e
  estratégia de testes atualizados conforme a revisão.
- Contratos F4 e F5 anteriores **preservados**; F5-05 **não antecipada**.
- Próximo passo: implementação da F5-04 em PR próprio, seguindo D1–D18.
