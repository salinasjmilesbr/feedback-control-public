# F5-02 — Vínculo usuário autenticado ↔ colaborador (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de auditoria e desenho, sem código funcional**.
> Estado: **FECHADO — contrato pronto para implementação** (PR #161). Q1–Q6
> **todas resolvidas**: Q1, Q3, Q4, Q5 e Q6 **FECHADAS/APROVADAS**; Q2 **N/A
> (adiada para F5-05)**. Decisões D1–D14 **FECHADAS**.
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
  → MembershipCollaboratorLink (vínculo 1:0..1 ativo; histórico por linhas)
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
  (`membership_collaborator_links`), FK composta de tenant, ADMIN/usuários sem
  colaborador usam scopes não estruturais (D17) e resolvers `SECURITY INVOKER`/
  bootstrap DEFINER restrito a `service_role` (D18 — **inalterado nesta
  atividade**).

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
| 1 vínculo por membership | `uq_membership_collaborator_links_membership` unique (membership_id) — **vale inclusive quando a linha está `disabled`** (1 única linha por membership em qualquer status). **Este contrato muda na implementação (Q6 = B):** passa a ser unicidade **parcial** (no máx. 1 `active` por membership), permitindo linhas `disabled` históricas. |
| Tenant da membership | FK composta `(membership_id, organization_id)` → `user_organization_memberships(id, organization_id)` RESTRICT |
| Tenant do colaborador | FK composta `(collaborator_id, organization_id)` → `collaborators(id, organization_id)` RESTRICT |
| Reativação no lugar | `status active/disabled`; sem exclusão física; histórico preservado na linha |
| Índices | `organization_id` e `collaborator_id` |
| RLS | `ENABLE ROW LEVEL SECURITY`, **zero policies** (deny-by-default) |
| Grants | Nenhum SELECT/DML a `authenticated`/`anon` (revogados na F4-08 `revoke_excess`; tabela entre as **7 fechadas** validadas em `02-validar-f4-08.sql`) |

### 2.2 Banco — resolvers/funções relacionadas (F4-02/F4-08)

| Função | Modo | Estado |
| --- | --- | --- |
| `resolver_collaborador_vinculado(user_profile_id, organization_id)` → `collaborator_id` | `SECURITY INVOKER`, STABLE | Une membership **ativa** (`m.status='active'`) × link **ativo** (`l.status='active'`) pelo `membership_id`; filtrado por `user_profile_id` e `organization_id`. **Não junta `user_profiles` (profile ativo não é verificado aqui)** — divergência de defesa em profundidade vs. `resolver_capabilities_escopos_efetivas`, que junta `up.status='active'` (G2; corrigido na implementação por Q4 = A). |
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
| G7 | Sem tratamento executável de “mudança de colaborador” com histórico (UNIQUE(membership_id) impede 2ª linha histórica na mesma membership) | modelo só tem status active/disabled e **UNIQUE(membership_id)** | Mudanças administrativas sem caminho consistente e sem auditoria | F5-02 (**Q6 FECHADA = B** — múltiplas linhas históricas, 1 ativa por membership) |
| G8 | `membership` não tem coluna `collaborator_id` (por decisão F4-02 D1 = A); há risco de alguém reintroduzir vínculo por e-mail/matrícula no futuro | F2-02/migração F4-02 | Anti-pattern de identidade (regressão ao vínculo por chave de negócio) | F5-02 (contrato/regra permanente) |
| G9 | Mundo DEV usa matrícula como `actorId`; a semântica real (`auth.uid()`) ainda não está conectada aos providers estruturais | `mundoFuncional.ts`, `authorizationPolicy.ts` | Transição DEV→real exige o mapa (actorId, org) → colaborador via vínculo | F5-02 (seam) + F5-04/05 |
| G10 | Sem caminho server-side/transacional de mutação do vínculo (criar/trocar/desativar) com auditoria | sem função/RPC de gestão do vínculo além da tabela | Mutação direta poderia virar caminho (proibido: F4-08 mutações só por RPC/transação) | F5-02 (D9; implementação) |

---

## 4. Modelo de vínculo

### 4.1 Cadeia soberana

```
auth.uid()  ──1:1──▶  user_profiles.id        (conta habilitada)
   │
   ▼ (profile ativo + membership ativa, confirmada server-side)
user_organization_memberships.user_profile_id   (alcance de tenant)
   │
   ▼ (no máx. 1 link ativo por membership; linhas disabled = histórico)
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
| membership → colaborador (via link) | 1 → **0..1 ativo** | unique **parcial** (1 `active` por membership) — Q6 = B; linhas `disabled` históricas são permitidas |
| colaborador → membership (via link) | 1 → 0..1 **ativo** por organização | unique **parcial** (1 `active` por `(collaborator_id, organization_id)`) — Q3 = B |
| link → tenant | 1 organização | FKs compostas (membership e colaborador) |

Formas válidas por (usuário, organização):
- membership ativa **sem** link ativo → usuário da organização **sem
  colaborador** (ADMIN/administrativo; D17 F4-02) ou com vínculo desativado
  (histórico);
- membership ativa **com** link ativo → usuário com colaborador (SELF e raiz de
  escopos estruturais);
- linhas `disabled` → **histórico preservado** (mudança de colaborador = nova
  linha ativa); nunca sobrescrever `collaborator_id` de linha histórica.

### 4.3 Invariantes do modelo

1. `link.membership_id` aponta para membership ativa (resolução) **e** o
   `user_profiles` do dono da membership está ativo (D1/F4-08 — G2);
2. `link.organization_id` = `membership.organization_id` = `collaborator.organization_id`
   (FKs compostas — indecomponível no banco);
3. no máximo **1 link `active` por membership** (unique parcial — Q6 = B);
   múltiplas linhas `disabled` por membership são históricas;
4. no máximo **1 link `active` por `(collaborator_id, organization_id)`**
   (Q3 = B): um colaborador não é representado por duas contas/memberships ativas
   na mesma organização;
5. `collaborators.id` é UUID técnico imutável; matrícula/nome/e-mail **nunca**
   participam do vínculo;
6. sem vínculo ativo ⇒ scopes SELF/estruturais **não resolvem** (vazio = DENY);
7. link `disabled`/membership `disabled`/profile `disabled` ⇒ resolução vazia
   (fail-closed), sem exclusão física de histórico;
8. **mudança de colaborador é transacional:** desativar o link ativo atual +
   inserir nova linha ativa para o novo colaborador, na mesma transação — nunca
   `UPDATE` de `collaborator_id` em linha existente (histórica ou ativa);
9. **sem `valid_from`/`valid_to`** no vínculo nesta fase (Q6 = B, item 5):
   temporalidade explícita completa fica adiada até existir necessidade concreta.

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
  3. link = link active da membership              → sem link ativo ⇒ vazio
     (a linha disabled histórica NÃO resolve)
  4. colaborador = collaborators(link.collaborator_id)
  5. ⇒ { colaborador, membership, link } (0 ou 1)
```

Regras:
- retorna **no máximo 1** colaborador por (authUid, organizationId) — somente o
  link **ativo** resolve; linhas `disabled` são histórico e **nunca** resolvem;
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
- **Mudança de colaborador (Q6 = B):** a troca preserva tenant correlation — as
  novas linhas são inseridas com a mesma `organization_id`, garantida pelas FKs
  compostas existentes.
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
| MembershipCollaboratorLink | **O vínculo**: associa uma membership a ≤1 colaborador ativo no mesmo tenant; linhas `disabled` = histórico | Credencial; papel; cadastro da pessoa | 1 `active` por membership (Q6); 1 `active` por (colaborador, org) (Q3); FKs compostas |
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
    → link active da membership?   não ⇒ ∅ (usuário sem colaborador — D17; linha
                                   disabled histórica não resolve)
    → colaborador existe?          não ⇒ ∅ (inconsistência — nunca heurística)
    → resultado: { colaborador, membership, link }  (0..1)
```

Fluxo de **mudança de colaborador** (Q6 = B; transacional, server-side — D9):

```
trocarColaborador(membership, novoCollaboratorId, autor) [transação]:
  1. valida tenant: membership e novo colaborador na MESMA organization_id
     (FKs compostas; cross-tenant ⇒ erro/rollback)
  2. desativa o link ACTIVE atual  (status = 'disabled')   ← linha preservada
  3. insere NOVA linha ACTIVE (membership_id, organization_id, novo colaborador)
  4. Q3: falha se já existir outro link ACTIVE para (novo colaborador, org)
  5. Q6: falha se já existir outro link ACTIVE para a membership
  ⇒ ou tudo (2+3) ou nada (rollback)
```

---

## 9. Estados inválidos

| Caso | Resolução prevista | Estado/comportamento |
| --- | --- | --- |
| Usuário sem vínculo ativo (sem link ativo) | `∅` | Sem SELF estrutural; ADMIN usa ORGANIZATION (D17); sem erro — forma válida; linhas `disabled` (histórico) não resolvem |
| Colaborador inexistente (órfão de FK impossível; porém migração/dados) | `∅` | Fail-closed; registrar inconsistência |
| Colaborador em `inactive`/`leave` (status temporal) | âncora preservada (Q5 FECHADA = A) | O vínculo continua resolvendo quem é o colaborador; regras funcionais de SELF/fluxos consideram o estado temporal no domínio/engine — status **não** remapeia identidade |
| Link para outro tenant | impossível (FK) | DENY garantido no banco; testes de regressão obrigatórios |
| 2 links `active` para a mesma membership | impossível (unique parcial Q6) | DENY garantido no banco; rollback transacional |
| 2 links `active` para o mesmo `(collaborator_id, organization_id)` | impossível (unique parcial Q3) | DENY garantido no banco |
| Membership revogada/`disabled` | `∅` | Resolução vazia; sem conteúdo estrutural (F4-08) |
| Link `disabled` (histórico) | `∅` | Não resolve; preservado como histórico; reativação = nova linha `active` (ou reativar a linha se for o mesmo colaborador e não houver outra ativa) |
| Mudança de colaborador (usuário passa a ser outra pessoa organizacional) | **Q6 = B:** desativar link ativo + inserir nova linha ativa, transacional; linha antiga permanece `disabled`; nunca sobrescrever `collaborator_id` | Auditoria/histórico na própria tabela |
| Mudança de organização do colaborador (reorganização) | não existe hoje (id imutável + FK RESTRICT) | Requer fluxo explícito futuro; vínculo antigo tratado antes |
| Inconsistência histórica (períodos de status sobrepostos, link órfão em snapshot) | fail-closed | Preservar histórico; registrar para auditoria |

---

## 10. Fail-closed

- Resolução retorna **vazio** em qualquer elo ausente/inativo/inconsistente —
  nunca “chute”, nunca e-mail/matrícula como fallback, nunca cargo; linhas
  `disabled` (histórico) **nunca** resolvem;
- perfil inativo, membership inativa/revogada (ou inexistente no tenant),
  link desabilitado ou colaborador inexistente ⇒ sem vínculo resolvido ⇒ scopes
  SELF/estruturais não autorizam;
- **nenhuma superfície de leitura do vínculo é criada nesta F5-02 (Q1 = A
  FECHADA):** a tabela e os resolvers permanecem fechados a `authenticated`
  (F4-02/F4-08 preservados); a resolução do próprio vínculo ocorre apenas por
  caminhos internos/`service_role`; a necessidade de uma superfície adicional é
  reavaliada somente na F5-05 (Q2 N/A);
- mutações do vínculo (criar/trocar/desativar) **nunca** por DML direto de
  `authenticated` (deny-by-default + sem grants); somente caminho administrativo
  **server-side/transacional** (RPC/Edge — D9), com rollback atômico (Q6 = B);
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
- **Q3 (FECHADA = B) + Q6 (FECHADA = B):** no banco, no máximo **1 link `active`
  por membership** e no máximo **1 link `active` por `(collaborator_id,
  organization_id)`** — ambos por unicidade **parcial** sobre `status='active'`;
  linhas `disabled` permanecem como histórico.

### 13.2 Typescript (contrato p/ F5-05 consumir)

```ts
// F5-02 — contrato de resolução do vínculo (sem implementação nesta etapa e sem
// superfície executável pelo frontend — Q1 = A FECHADA).
export interface ColaboradorVinculado {
  readonly membership: MembershipAutenticada; // membership ativa origem
  readonly linkId: string;                    // id do link ativo (único por membership)
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

**Alvo (conforme Q1/Q2/Q3/Q4/Q6):**
- manter a tabela **fechada** para leitura ampla (sem policy SELECT por
  `authenticated` — impede enumeração de vínculos de terceiros) **e não expor
  função do próprio vínculo nesta F5-02** (Q1 = A; reavaliação em F5-05 — Q2 N/A);
- endurecer o resolver INVOKER com perfil ativo (Q4 = A), sem mudar grants;
- unicidade **parcial** do link ativo: 1 por membership (Q6 = B) e 1 por
  `(collaborator_id, organization_id)` (Q3 = B);
- mutações (inclusive a troca A→B) somente por caminho administrativo
  **server-side/transacional** (D9), seguindo o padrão F4-08 (funções
  transacionais; sem DML direto de `authenticated`).

---

## 15. Migrations — necessárias?

**Nesta etapa de desenho: NÃO** — nenhuma migration é criada agora (somente este
documento; validações não são alteradas).

**Para a implementação da F5-02** (decisões Q1/Q2/Q3/Q4/Q5/Q6 já fechadas), a
previsão **definitiva** de migrations aditivas (sem coluna/tabela nova de vínculo
e sem reescrita de `user_organization_memberships`):

1. **Q4 (= A) — resolver:** `create or replace function
   public.resolver_collaborador_vinculado(...)` com
   `join user_profiles up on up.id = m.user_profile_id and up.status = 'active'`
   (paridade D1/F4-08; corrige G2). **Sem** mudança de grants (permanece sem
   `EXECUTE` para `authenticated`).
2. **Q1/Q2:** **não** há `resolver_meu_colaborador_vinculado` nem função
   `SECURITY DEFINER` para `authenticated` nesta F5-02.
3. **Q6 (= B) — unicidade por membership:** `drop constraint
   uq_membership_collaborator_links_membership` e criar **unique index parcial**
   (1 `active` por `membership_id`): `create unique index
   uq_membership_collaborator_links_active_membership on ... (membership_id)
   where status = 'active';` — permite múltiplas linhas `disabled` históricas por
   membership.
4. **Q3 (= B) — unicidade por colaborador+org:** `create unique index
   uq_membership_collaborator_links_active_collaborator on ...
   (collaborator_id, organization_id) where status = 'active';` — impede duas
   contas/memberships ativas representando o mesmo colaborador no mesmo tenant.
   > Nota: unicidade **parcial** exige índice único com predicado (constraint
   `UNIQUE` não aceita `WHERE`); o nome/forma segue a convenção de constraints
   únicas da F1-02, documentando a exceção do predicado.
5. **Pré-condição/backfill antes das migrations 3–4:** validar que não existem
   dados atuais violando as novas regras (1 `active` por membership e 1 `active`
   por `(collaborator, organization)`); nenhum backfill destrutivo é esperado
   (fixtures atuais têm 1 linha por membership).
6. **Rollback:** recriar `uq_membership_collaborator_links_membership` (unique
   total) após consolidar (1 linha por membership) e dropar os dois unique
   indexes parciais.

**Não há** `valid_from`/`valid_to` no vínculo nesta fase (Q6 = B, item 5):
temporalidade explícita completa fica adiada até existir necessidade concreta.
Nenhuma coluna/tabela nova de vínculo; nenhuma reescrita de
`user_organization_memberships` (G8 permanece proibido: vínculo não volta a ser
coluna de membership).

---

## 16. Estratégia de implementação (ordem sugerida)

1. Endurecer `resolver_collaborador_vinculado` (Q4 = A) com validação SQL via
   **caminhos internos/`service_role`** (perfil desabilitado/ausente/
   desconhecido ⇒ vazio; membership desabilitada ⇒ vazio; link `disabled` ⇒
   vazio);
2. **Não** criar função de leitura do próprio vínculo (Q1 = A);
3. Migration de unicidade (Q6 = B + Q3 = B): drop do unique total + 2 unique
   indexes parciais do ativo, com backfill/rollback documentados (§15);
4. Tipos/contrato TS `ColaboradorVinculado`/`VinculoIdentityResolver` **sem
   consumidores** e sem chamada pelo frontend;
5. Caminho server-side/transacional de mutação (RPC/Edge — D9) para criar/
   trocar/desativar vínculo (a troca A→B usa desativar + inserir, atômico);
6. Registrar o seam DEV→real (G9) para F5-04/05;
7. Fluxo GitHub por PR com `npm test`, `npm run build`, `npm run lint`,
   `git diff --check`.

---

## 17. Estratégia de testes

**Unitário (TS puro — futuro):**
- `VinculoIdentityResolver`: vínculo ativo → 1; sem link → null; link `disabled`
  (histórico) → null; membership inativa → null; organização sem membership
  ativa → null.

**Integração (validação SQL — `supabase/validacao`, estilo F4-02/F4-08),**
**sempre pelos caminhos internos/`service_role` — sem abrir a tabela a
`authenticated` (Q1 = A):**

Resolução:
- vínculo feliz: MANAGER resolve exatamente 1 colaborador (manter cenário atual,
  executado como `service_role`);
- perfil ausente/inativo/desconhecido + membership ativa + link ativo ⇒
  **vazio** (Q4 = A);
- membership `disabled` ⇒ vazio; link `disabled` (histórico) ⇒ vazio (não
  resolve);
- **sem superfície para `authenticated`:** SELECT direto na tabela ⇒ permission
  denied; `EXECUTE` dos resolvers ⇒ negado; inexistência de função própria de
  leitura (schema guard — nada novo exposto);
- **tenant mismatch:** link de outra organização ⇒ impossível (FK); resolução
  com organização sem membership ativa do `auth.uid()` ⇒ vazio;
- **IDOR/forjado:** INSERT/UPDATE direto de link por `authenticated` ⇒ negado;
  tentativa de vincular colaborador de outro tenant ⇒ violação de FK;
- **colaborador inativo/licença (Q5 = A):** o vínculo continua resolvendo o
  colaborador; o uso funcional bloqueado por `inactive` é testado no
  domínio/Policy Engine (regressão TS F4).

Unicidade e troca (Q3/Q6 = B):
- **troca válida A→B na mesma membership** (RPC transacional, `service_role`):
  linha A fica `disabled`, nova linha B `active`;
- **linha antiga permanece `disabled`** (histórico preservado; `collaborator_id`
  da linha antiga não é sobrescrito);
- **exatamente uma linha `active` por membership** após a troca;
- **segundo vínculo `active` para a mesma membership falha** (unique parcial
  Q6);
- **segundo vínculo `active` para o mesmo `(collaborator_id, organization_id)`
  falha** (unique parcial Q3);
- **cross-tenant continua impossível** (FKs compostas) mesmo na troca;
- **rollback transacional:** forçar falha no meio da troca ⇒ **nenhum estado
  intermediário inválido** (link antigo continua `active`; nenhuma linha nova);
- regressão: rotas/auth F5-01 e suítes F4 continuam verdes.

---

## 18. Critérios de aceite

1. Contrato do vínculo aprovado: chave `(auth.uid → membership)`; 1 membership →
   0..1 colaborador ativo; nunca por e-mail/matrícula/nome/cargo;
2. G2 corrigido no resolver (perfil ativo exigido — Q4 = A) com validação SQL;
3. **Nenhuma superfície de leitura criada** para `authenticated` nesta F5-02
   (Q1 = A); reavaliação INVOKER vs. DEFINER registrada para F5-05 (Q2 N/A);
4. **Q6 = B aplicada:** no máx. 1 link `active` por membership (unique parcial);
   linhas `disabled` preservadas como histórico; troca de colaborador
   transacional (desativar + inserir), sem `UPDATE` de `collaborator_id`;
5. **Q3 = B aplicada:** no máx. 1 link `active` por `(collaborator_id,
   organization_id)`;
6. Status temporal do colaborador **não** remapeia identidade (Q5 = A);
7. Sem `valid_from`/`valid_to` no vínculo nesta fase (Q6 = B, item 5);
8. Nenhuma regra por cargo/job_role/função; engine, `authorize`, `can`,
   RLS F4-08, F4-02 D18 e origens C/D inalterados;
9. Testes das seções 17 (incluindo troca, unicidade e rollback) verdes;
10. `npm test`, `npm run build`, `npm run lint` e `git diff --check` verdes no PR
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
| Troca de colaborador com estado intermediário inválido | Q6 = B: transação única (desativar + inserir) com rollback atômico; testes de rollback |
| Mudança de constraint da F4-02 (drop do unique total) quebrar dependências | Migration aditiva com backfill/rollback documentados; banco local antes de aplicar; validadores atualizados |
| Migration de unicidade (Q3/Q6) com dados existentes conflitantes | Backfill/consolidação prévia + rollback documentados (§15) |

---

## 20. Fora de escopo (F5-02)

- organização ativa/switcher (F5-03); roles/capabilities em runtime (F5-04);
  ActorContext (F5-05);
- migração geral de `localStorage`; persistência remota dos domínios funcionais;
- hardening geral (F6); hosting/arquitetura online/observabilidade/backup;
- UI de administração do vínculo (fase posterior, caminho server-side);
- superfície de leitura do próprio vínculo para o frontend (Q1 = A: não nesta
  F5-02; avaliar em F5-05 — Q2 N/A);
- validade temporal explícita (`valid_from`/`valid_to`) no vínculo (Q6 = B, item
  5 — adiada até necessidade concreta);
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
  ativos** e preserva histórico, conforme o modelo final da Q6 (= B, múltiplas
  linhas).
- **Impacto/risco:** unique index parcial (migration aditiva) com
  backfill/rollback; impacta provisioning.
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

### Q6 — Mudança de colaborador/ligação e histórico — **FECHADA (alternativa B APROVADA)**

- **Contexto / incompatibilidade resolvida:** o desenho anterior recomendava
  “desabilitar o link antigo + criar novo link na mesma membership”, o que **não
  era executável** com `UNIQUE(membership_id)` (1 única linha por membership,
  inclusive `disabled`). A Q6 fecha esse ponto optando por **múltiplas linhas
  históricas** com no máximo **1 linha `active` por membership**.
- **Por que:** mudanças administrativas (“este usuário agora representa outro
  colaborador”) precisam de um caminho consistente que preserve histórico e
  respeite as constraints, interagindo com a Q3 (1 ativo por colaborador+org).
- **Alternativas avaliadas:** (A) uma linha por membership com troca controlada +
  auditoria separada; (B) múltiplas linhas históricas por membership (1 ativa);
  (C) validade temporal explícita (`valid_from`/`valid_to`). Análise completa em
  revisões anteriores deste documento (histórico, constraints, resolvers, RLS,
  testes, compatibilidade F4-02, migration estrutural, risco de duas identidades,
  rollback).
- **Decisão adotada (B):** adotar **múltiplas linhas históricas** em
  `membership_collaborator_links`, mantendo **no máximo 1 linha `ACTIVE` por
  membership**. Contrato final:
  1. substituir a unicidade total atual de `membership_id` por unicidade
     **parcial** para vínculos ativos (no máximo 1 link `status='active'` por
     membership);
  2. preservar as linhas `disabled` como **histórico**; mudança de colaborador
     ocorre de forma **transacional**: desativar o vínculo ativo atual; criar
     nova linha ativa para o novo colaborador; **nunca sobrescrever
     `collaborator_id`** da linha histórica;
  3. aplicar também a Q3 (fechada): no máximo 1 vínculo ativo por
     `(collaborator_id, organization_id)` — impedir que duas contas/memberships
     ativas representem simultaneamente o mesmo colaborador no mesmo tenant;
  4. a troca preserva tenant correlation pelas **FKs compostas existentes**;
  5. **não introduzir `valid_from`/`valid_to`** nesta fase — temporalidade
     explícita completa fica adiada até existir necessidade concreta;
  6. o caminho de mutação é **server-side/transacional** conforme D9; **não**
     conceder DML direto a `authenticated`;
  7. testes previstos: troca válida A→B na mesma membership; linha antiga
     permanece `disabled`; exatamente uma linha `active` por membership; segundo
     vínculo `active` para a mesma membership falha; segundo vínculo `active`
     para o mesmo `(collaborator+organization)` falha; cross-tenant impossível;
     rollback transacional sem estado intermediário inválido.
- **Impacto/risco:** migration aditiva (drop do unique total + 2 unique indexes
  parciais do ativo) com backfill/rollback documentados; testes de validação
  atualizados (validações F4-02/F4-08 que inserem links continuam válidas, com
  ajuste dos casos que dependiam do unique total).
- **Seções dependentes:** 3 (G7), 4 (invariantes), 6, 8, 9, 10, 13, 14, 15, 16,
  17, 18, D2/D8/D9/D13, Q3.

---

## 22. Decisões arquiteturais (D1–D14 — FECHADAS)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | Chave soberana do vínculo | `user_profile_id` (= `auth.uid()`, da sessão) + `organization_id` **confirmado server-side contra membership ativa** do `auth.uid()`; nunca e-mail, matrícula, nome ou cargo; `organization_id` não é claim da sessão/JWT | FECHADA |
| D2 | Cardinalidade e histórico | 1 membership → 0..1 colaborador **ativo**; **múltiplas linhas históricas por membership** (no máx. 1 `active`) — Q6 = B; ausência de link ativo = sem vínculo/ADMIN (D17); sem exclusão física | FECHADA |
| D3 | Tenant correlation | FKs compostas mantêm membership e colaborador no mesmo tenant; `organization_id` é intenção do chamador, confirmada contra membership ativa do `auth.uid()`; cross-tenant DENY (inclusive na troca) | FECHADA |
| D4 | Vínculo não é identidade da conta | colaborador nunca identifica a conta; e-mail/matrícula nunca são chave; vínculo por tabela própria (F4-02 D1 = A) permanece | FECHADA |
| D5 | Porta de resolução | `resolver_collaborador_vinculado` endurecido (profile ativo — Q4 = A) é a origem **interna/server-side**; resolve apenas o link `active` (histórico não resolve); runtime real mapeia `(actorId=auth.uid(), organizationId confirmado) → colaborador` no consumo F5-05; **sem superfície nova nesta F5-02** (Q1 = A) | FECHADA |
| D6 | Sem vínculo ativo = sem escopo estrutural | SELF/DR/DESCENDANTS/UNIT exigem vínculo ativo (D17 F4-02); sem vínculo resolvem vazio; ADMIN usa ORGANIZATION | FECHADA |
| D7 | Status do colaborador × vínculo | Vínculo é âncora de identidade independente de `collaborator_status_periods` (Q5 = A); status nunca remapeia identidade; regras funcionais no domínio/engine | FECHADA |
| D8 | Mudanças de vínculo | **Q6 = B FECHADA:** troca transacional = desativar link ativo (linha vira histórico `disabled`) + inserir nova linha `active`; nunca `UPDATE` de `collaborator_id` em linha existente; sem `valid_from`/`valid_to` nesta fase | FECHADA |
| D9 | Mutações server-side | Criação/remoção/desativação/**troca** do vínculo somente por caminho administrativo **server-side/transacional** (RPC/Edge, rollback atômico); sem DML direto de `authenticated` | FECHADA |
| D10 | Superfície de leitura mínima | **Nenhuma** superfície nova (Q1 = A): tabela e resolvers permanecem fechados a `authenticated`; reavaliação INVOKER vs. DEFINER só na F5-05 (Q2 N/A) | FECHADA |
| D11 | Falha em qualquer elo = vazio | profile/membership/link ausente, inativo ou inconsistente ⇒ resolução vazia (fail-closed); linhas `disabled` (histórico) nunca resolvem; nunca heurística | FECHADA |
| D12 | Engine intacto | F5-02 não altera o Policy Engine; define o seam (actorId real → colaborador por (actorId, org confirmada)); origens C/D independentes do vínculo | FECHADA |
| D13 | Migrations na implementação | Sem migration no desenho. Implementação: (1) `create or replace` do resolver (Q4); (2) **sem** função DEFINER p/ `authenticated` (Q1/Q2); (3) **Q6 = B**: drop do unique total + unique index parcial (1 `active` por membership); (4) **Q3 = B**: unique index parcial (1 `active` por `(collaborator_id, organization_id)`); com backfill/rollback; sem coluna/tabela nova e sem `valid_from`/`valid_to` | FECHADA |
| D14 | Seam DEV → real | Mundo DEV (matrícula) permanece isolado por gate; runtime real só usa a cadeia soberana (G9) | FECHADA |

---

## 23. Confirmações desta atividade

- **Q1–Q6 todas resolvidas:** Q1 (A), Q3 (B), Q4 (A), Q5 (A) e Q6 (B)
  **FECHADAS/APROVADAS**; Q2 **N/A — adiada para F5-05** (F4-02 D18 inalterado).
- **D1–D14 FECHADAS**, incluindo **D8** (fechada com Q6 = B) e **D13** (migration
  definitiva: resolver endurecido + drop do unique total + 2 unique indexes
  parciais do ativo, sem temporalidade).
- Contrato da F5-02: **FECHADO e pronto para implementação** (PR próprio, sem UI
  de gestão, sem F5-03/04/05).
- Fronteira de `organization_id` mantida conforme a F5-01 nas seções e decisões:
  intenção confirmada contra membership ativa do `auth.uid()`.
- Nenhuma alteração funcional: o diff continua **somente documental**
  (`docs/F5-02-desenho-tecnico.md`).

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
