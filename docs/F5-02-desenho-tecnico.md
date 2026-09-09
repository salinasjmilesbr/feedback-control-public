# F5-02 — Vínculo usuário autenticado ↔ colaborador (contrato arquitetural e desenho)

> Documento de desenho técnico — **etapa de auditoria e desenho, sem código funcional**.
> Estado: **PROPOSTA para revisão** — decisões D1–D14 marcadas como propostas e
> questões Q1–Q6 aguardando validação antes da implementação.
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
- fail-closed; tenant mismatch = DENY; RLS F4-08 e isolamento entre tenants
  permanecem vigentes;
- F4-02 (decisões **fechadas**) já definiu: vínculo em **tabela própria**
  (`membership_collaborator_links`), 1 vínculo ativo por (usuário, organização),
  FK composta de tenant, ADMIN/usuários sem colaborador usam scopes não
  estruturais (D17) e resolvers `SECURITY INVOKER`/bootstrap DEFINER restrito a
  `service_role` (D18).

### 1.2 O que a F5-02 entrega e o que deixa para etapas posteriores

| Assunto | F5-02 (este documento) | Etapa futura |
| --- | --- | --- |
| Contrato do vínculo, chaves, invariantes e tenant correlation | ✅ define | — |
| Auditoria/endurecimento de `membership_collaborator_links`, resolvers, RLS/grants | ✅ audita e define o alvo | implementação do contrato (PR próprio) |
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
| 1 vínculo por membership | `uq_membership_collaborator_links_membership` unique (membership_id) |
| Tenant da membership | FK composta `(membership_id, organization_id)` → `user_organization_memberships(id, organization_id)` RESTRICT |
| Tenant do colaborador | FK composta `(collaborator_id, organization_id)` → `collaborators(id, organization_id)` RESTRICT |
| Reativação no lugar | `status active/disabled`; sem exclusão física; histórico preservado |
| Índices | `organization_id` e `collaborator_id` |
| RLS | `ENABLE ROW LEVEL SECURITY`, **zero policies** (deny-by-default) |
| Grants | Nenhum SELECT/DML a `authenticated`/`anon` (revogados na F4-08 `revoke_excess`; tabela entre as **7 fechadas** validadas em `02-validar-f4-08.sql`) |

### 2.2 Banco — resolvers/funções relacionadas (F4-02/F4-08)

| Função | Modo | Estado |
| --- | --- | --- |
| `resolver_collaborador_vinculado(user_profile_id, organization_id)` → `collaborator_id` | `SECURITY INVOKER`, STABLE | Une membership **ativa** (`m.status='active'`) × link **ativo** (`l.status='active'`) pelo `membership_id`; filtrado por `user_profile_id` e `organization_id`. **Não junta `user_profiles` (profile ativo não é verificado aqui)** — divergência de defesa em profundidade vs. `resolver_capabilities_escopos_efetivas`, que junta `up.status='active'`. |
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
  `service_role`.
- **F4-08 D1:** fronteira soberana de tenant = `auth.uid()` + `user_profiles`
  ativo + `user_organization_memberships` ativa; helper único
  `user_has_active_membership(org)`; cross-tenant DENY.
- **F5-01:** `user_profile.id = auth.uid()`; colaborador nunca identifica a
  conta; vínculo ocorre **no contexto da membership**.

---

## 3. Gaps (G1–G10)

| # | Gap | Evidência | Consequência | Endereçado em |
| --- | --- | --- | --- | --- |
| G1 | Nenhum caminho TS/runtime resolve o colaborador a partir da identidade real (`auth.uid → membership → colaborador`) | grep `src/` sem referência ao link/resolver | ActorContext/SELF futuros não têm a ponte; hoje só o DEV usa colaborador | F5-02 (contrato) + F5-05 |
| G2 | `resolver_collaborador_vinculado` não verifica `user_profiles.status='active'` | migration F4-02 (função) vs. `resolver_capabilities_escopos_efetivas` | Perfil desabilitado (sem ban) ainda resolveria o vínculo por `service_role`; quebra a paridade do fail-closed D1/F4-08 | F5-02 (hardening) |
| G3 | Tabela do vínculo é **fechada** (RLS sem policy + sem grant SELECT) e resolvers sem `EXECUTE` para `authenticated` | F4-08 `revoke_excess` + `helpers_function_grants` + validação “7 tabelas fechadas” | Não existe hoje superfície segura para o runtime resolver o próprio vínculo (nem para testes reais de RLS do vínculo) | F5-02 (decisão de exposição — Q1/Q2) |
| G4 | Sem testes automatizados (TS ou validação SQL) para os estados inválidos do vínculo: profile desabilitado × link, membership revogada × link, colaborador inativo/inexistente | validação F4-02 testa apenas o caso feliz do `resolver_collaborador_vinculado` + `resolver_capabilities_escopos_efetivas` p/ disabled | Regressões silenciosas quando o vínculo entrar em runtime | F5-02 (estratégia de testes) |
| G5 | Não há definição formal de “colaborador inativo” × vínculo (status temporal F3-01) no contrato de resolução | F3-01 status `active/leave/inactive`; link só tem `active/disabled` | SELF/hierarquia podem divergir sobre licença/desligado | F5-02 (Q5) |
| G6 | Possibilidade de um mesmo colaborador estar vinculado a **mais de um** membership da mesma organização (usuários distintos): `unique` é só por `membership_id` | constraint F4-02 | Ambiguidade de SELF para o colaborador na organização (definição de identidade da pessoa) | F5-02 (Q3) |
| G7 | Sem tratamento explícito de “mudança de colaborador”/“mudança de organização” com histórico (mover link, fechar e abrir, período) | modelo só tem status active/disabled e reativação no lugar | Mudanças administrativas futuras podem apagar ou conflitar vínculo sem auditoria | F5-02 (D8/D9, Q6) |
| G8 | `membership` não tem coluna `collaborator_id` (por decisão F4-02 D1 = A); há risco de alguém reintroduzir vínculo por e-mail/matrícula no futuro | F2-02/migração F4-02 | Anti-pattern de identidade (regressão ao vínculo por chave de negócio) | F5-02 (contrato/regra permanente) |
| G9 | Mundo DEV usa matrícula como `actorId`; a semântica real (`auth.uid()`) ainda não está conectada aos providers estruturais | `mundoFuncional.ts`, `authorizationPolicy.ts` | Transição DEV→real exige o mapa (actorId, org) → colaborador via vínculo | F5-02 (seam) + F5-04/05 |
| G10 | Sem contrato de “quem pode criar/mover/remover vínculo” (path administrativo) e sem auditoria do vínculo | sem função/RPC de gestão do vínculo além da tabela | Mutação direta poderia virar caminho (proibido: F4-08 mutações só por RPC/transação) | F5-02 (D9; implementação) |

---

## 4. Modelo de vínculo

### 4.1 Cadeia soberana

```
auth.uid()  ──1:1──▶  user_profiles.id        (conta habilitada)
   │
   ▼ (RLS: profile ativo + membership ativa)
user_organization_memberships.user_profile_id   (alcance de tenant)
   │
   ▼ (1:0..1 — uq por membership_id)
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
| membership → colaborador (via link) | 1 → **0..1** | unique por `membership_id`; ausência = usuário sem vínculo (ADMIN) |
| colaborador → membership (via link) | 1 → 0..N | **sem unique** por colaborador hoje (ver Q3) |
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
3. no máximo **1 link por membership**, em qualquer status (unique; reativação
   no lugar — nunca duplicar);
4. `collaborators.id` é UUID técnico imutável; matrícula/nome/e-mail **nunca**
   participam do vínculo;
5. sem vínculo ativo ⇒ scopes SELF/estruturais **não resolvem** (vazio = DENY);
6. link `disabled`/membership `disabled`/profile `disabled` ⇒ resolução vazia
   (fail-closed), sem exclusão física de histórico.

---

## 5. Chaves e invariantes da resolução

**Chave soberana do vínculo:** `(user_profile_id, organization_id)` derivados de
`auth.uid()` pela sessão — nunca e-mail, matrícula, nome ou cargo.

Resolução mínima do colaborador vinculado (contrato):

```
resolveCollaborator(authUid, organizationId):
  1. profile = user_profiles(authUid)              → ausente/inativo ⇒ vazio
  2. membership = memberships ativas(authUid, org) → ausente ⇒ vazio
  3. link = links ativos(membership.id)            → ausente/disabled ⇒ vazio
  4. colaborador = collaborators(link.collaborator_id)
  5. ⇒ { colaborador, membership, link } (0 ou 1)
```

Regras:
- retorna **no máximo 1** colaborador por (authUid, organizationId);
- organização é **sempre** parâmetro soberano derivado da sessão (validação por
  membership ativa), nunca do cliente;
- falhas de qualquer elo = **vazio** (fail-closed), nunca heurística;
- o resultado é **por organização**: o mesmo usuário pode ter vínculos distintos
  em tenants distintos (cada um no próprio contexto).

---

## 6. Tenant correlation

- **Declarativa:** `membership_collaborator_links` carrega `organization_id` e as
  FKs compostas obrigam membership e colaborador a pertencerem à mesma
  organização (validação F4-02/F4-08 comprova cross-tenant = violação de FK).
- **Em execução:** todo resolver recebe `organization_id` e filtra por membership
  ativa do `auth.uid()` naquela organização; `resolver_alvos_escopo` e
  `resolver_capabilities_escopos_efetivas` já seguem esse padrão.
- **Frontend:** nunca transporta prova; transporta apenas `organization_id` como
  intenção (validada no servidor).
- **Regra:** vínculo cross-tenant = impossível no banco e DENY na resolução
  (fail-closed). Nunca “herdar” vínculo de outro tenant.

---

## 7. Fronteiras de confiança

| Conceito | É | Não é | Fronteira |
| --- | --- | --- | --- |
| AuthIdentity (F5-01) | Conta autenticada (`auth.uid()` + sessão) | Fonte de colaborador/tenant/role | `user_profile.id = auth.uid()` |
| membership | Alcance de tenant da conta | Vínculo com colaborador; papel | 1 conta → N memberships |
| MembershipCollaboratorLink | **O vínculo**: associa uma membership a ≤1 colaborador no mesmo tenant | Credencial; papel; cadastro da pessoa | unique por membership; FKs compostas |
| colaborador (F3) | Pessoa organizacional com lifecycle temporal | Identidade da conta | Vincula-se por membership, nunca por e-mail/matrícula |
| ActorContext (F5-05) | Ator efetivo do engine, derivado de AuthIdentity + membership + vínculo | Estado global de UI | Consome o resultado da F5-02; não implementado aqui |

**Regra de ouro:** o vínculo é **dado de servidor/banco**; o cliente apenas
transporta contexto (ex.: organização pretendida) que será revalidado.

---

## 8. Fluxo de resolução (alvo)

```
resolver Vínculo (por organização):
  authUid (da sessão)
    → user_profiles ativo?        não ⇒ ∅ (sem vínculo; acesso já negado na F5-01)
    → memberships ativas?          não ⇒ ∅
    → link ativo p/ membership?    não ⇒ ∅ (usuário sem colaborador — D17)
    → colaborador existe?          não ⇒ ∅ (inconsistência — nunca heurística)
    → resultado: { colaborador, membership, link }  (0..1)
```

## 9. Estados inválidos

| Caso | Resolução prevista | Estado/comportamento |
| --- | --- | --- |
| Usuário sem vínculo (sem link) | `∅` | Sem SELF estrutural; ADMIN usa ORGANIZATION (D17); sem erro — é forma válida |
| Colaborador inexistente (órfão de FK impossível; porém migração/dados) | `∅` | Fail-closed; registrar inconsistência (Q6) |
| Colaborador inativo (status temporal `inactive`) | dependente de Q5 | Recomendação: vínculo continua sendo a âncora de identidade; **uso funcional** (SELF/fluxos) é bloqueado pelo estado de domínio/engine |
| Colaborador em licença (`leave`) | Q5 | Recomendação: âncora mantida; regras de negócio do domínio decidem fluxos |
| Link para outro tenant | impossível (FK) | DENY garantido no banco; testes de regressão obrigatórios |
| Vínculo duplicado (2 links por membership) | impossível (unique) | DENY garantido no banco |
| Membership revogada/`disabled` | `∅` | Resolução vazia; sem conteúdo estrutural (F4-08) |
| Link `disabled`/removido (soft) | `∅` | Reativação no lugar; histórico preservado |
| Mudança de colaborador (usuário passa a ser outra pessoa organizacional) | fechar link (disabled) + abrir novo na mesma membership (Q6) | Nunca UPDATE do colaborador no mesmo link; auditoria |
| Mudança de organização do colaborador (reorganização) | não existe hoje (id imutável + FK RESTRICT) | Requer fluxo explícito futuro (Q6); vínculo antigo tratado antes |
| Inconsistência histórica (períodos de status sobrepostos, link órfão em snapshot) | fail-closed | Preservar histórico; registrar para auditoria |

---

## 10. Fail-closed

- Resolução retorna **vazio** em qualquer elo ausente/inativo/inconsistente —
  nunca “chute”, nunca e-mail/matrícula como fallback, nunca cargo;
- perfil inativo, membership inativa/revogada, link desabilitado ou colaborador
  inexistente ⇒ sem vínculo resolvido ⇒ scopes SELF/estruturais não autorizam;
- mutações do vínculo **nunca** por DML direto de `authenticated`
  (deny-by-default + sem grants); somente caminho administrativo server-side
  (RPC/Edge), ainda a implementar (D9);
- superfície de leitura para o runtime do **próprio vínculo** só é criada com
  escopo mínimo e fail-closed (Q1/Q2), sem abrir a tabela a `authenticated`;
- nenhum estado novo degrada para identidade simulada/DEV fora do gate DEV.

---

## 11. Impacto no Policy Engine

O engine (F4-03+) é agnóstico ao significado do `actorId` (string opaca usada
coerentemente pelos providers). A F5-02 **não altera o engine**; ela define o
seam:

- em DEV: `actorId = String(matricula)` + providers do mundo local;
- em runtime real (F5-04/05): `actorId = user_profile.id (auth.uid())` e os
  providers de identidade/relação resolvem o colaborador vinculado por
  `(actorId, organizationId)` via o contrato da F5-02 (`resolver_collaborador_vinculado`
  endurecido / função de resolução própria), depois usam os resolvers F3-07.

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
- isolamento entre tenants: o vínculo reforça (nunca atravessa tenant).

---

## 13. Interfaces necessárias

### 13.1 Banco (alvo de implementação)

- Endurecer `resolver_collaborador_vinculado` para exigir também
  `user_profiles.status='active'` (paridade com `resolver_capabilities_escopos_efetivas` — G2);
- Decidir (Q1/Q2) se/qual função de **leitura do próprio vínculo** será exposta
  ao runtime:
  - opção A: manter fechado (nenhum `EXECUTE`/policy) e resolver tudo
    server-side quando F5-05 consumir — nada novo agora;
  - opção B: função dedicada **read-only do próprio vínculo** (ex.:
    `resolver_meu_colaborador_vinculado(p_organization_id)`), `SECURITY
    DEFINER`? ou INVOKER com policy mínima, restrita a `auth.uid()` + perfil
    ativo + membership ativa — concedida a `authenticated` (somente o próprio).
  Recomendação preliminar: **B mínima** (1 função read-only do próprio usuário),
  mantendo a tabela fechada e sem policy de SELECT ampla; validação em Q1/Q2.

### 13.2 Typescript (contrato p/ F5-05 consumir)

```ts
// F5-02 — contrato de resolução do vínculo (sem implementação nesta etapa).
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

**Alvo (decisões Q1/Q2/Q4):**
- manter a tabela **fechada** para leitura ampla (sem policy SELECT por
  `authenticated` — impede enumeração de vínculos de terceiros);
- expor, no máximo, função **do próprio usuário** (fail-closed), retornando o
  próprio vínculo por organização;
- endurecer o resolver INVOKER com perfil ativo (G2);
- mutações somente por caminho administrativo server-side (D9), seguindo o
  padrão F4-08 (funções transacionais; sem DML direto).

---

## 15. Migrations — necessárias?

**Nesta etapa de desenho: NÃO** — nenhuma migration é criada agora (somente este
documento; validações não são alteradas).

**Para a implementação da F5-02** (se aprovado em Q1/Q2/Q4), prevê-se **máximo 1
migration aditiva**, estritamente justificada, sem alterar a estrutura existente:

1. `create or replace function public.resolver_collaborador_vinculado(...)`
   adicionando `join user_profiles up on up.id = m.user_profile_id and
   up.status='active'` (paridade D1/F4-08 — corrige G2);
2. (se Q1 = B) `create function public.resolver_meu_colaborador_vinculado(p_organization_id uuid)`
   — read-only do próprio usuário, `SECURITY INVOKER`? `DEFINER` com `set
   search_path` e guardas explícitas (auth.uid, perfil ativo, membership ativa,
   link ativo, tenant), `revoke`/`grant execute` mínimo a `authenticated`, e
   **sem** abrir SELECT na tabela;
3. (se Q3 = B) unique adicional por (collaborator, organization) sobre links
   ativos, se a regra de negócio exigir 1 colaborador ↔ ≤1 membership ativa por
   organização.

Nenhuma coluna/tabela nova; nenhuma reescrita de `user_organization_memberships`
(G8 permanece proibido: vínculo não volta a ser coluna de membership).

---

## 16. Estratégia de implementação (ordem sugerida)

1. Endurecer o resolver (G2) + testes de validação SQL (perfil desabilitado,
   membership desabilitada, link desabilitado ⇒ vazio);
2. (Q1=B) criar a função read-only do próprio vínculo com grants mínimos e
   validar por `supabase/validacao` (cenários com `set role authenticated`);
3. Tipos/contrato TS `ColaboradorVinculado`/`VinculoIdentityResolver` sem
   consumidores;
4. (Q3) definir regra 1 colaborador ↔ membership(s) ativa(s) e, se aplicável,
   aplicar o unique;
5. Registrar o seam DEV→real (G9) para F5-04/05;
6. Fluxo GitHub por PR com `npm test`, `npm run build`, `npm run lint`,
   `git diff --check`.

---

## 17. Estratégia de testes

**Unitário (TS puro — futuro):**
- `VinculoIdentityResolver`: vínculo ativo → 1; sem link → null; link disabled →
  null; membership inativa → null; organização divergente → null.

**Integração (validação SQL — `supabase/validacao`, estilo F4-02/F4-08):**
- vínculo feliz: MANAGER resolve exatamente 1 colaborador (manter cenário atual);
- perfil desabilitado + membership ativa + link ativo ⇒ **vazio** (G2);
- membership `disabled` ⇒ vazio; link `disabled` ⇒ vazio; reativação no lugar
  ⇒ volta a resolver;
- **tenant mismatch:** link de outra organização ⇒ impossível (FK) e/ou função
  retorna vazio quando `organization_id` não pertence ao `auth.uid()`;
- **IDOR:** usuário A chamando a função com organização/parâmetro de B ⇒ vazio/
  erro; sem enumeração de vínculo de terceiros (tabela fechada);
- **vínculo forjado:** INSERT direto de link por `authenticated` ⇒ permission
  denied (sem grant); UPDATE de `organization_id` ⇒ negado;
- **colaborador inativo:** status temporal `inactive` (Q5) ⇒ uso funcional
  bloqueado pelo domínio/engine (semântica a validar);
- regressão: rotas/auth F5-01 e suítes F4 continuam verdes.

---

## 18. Critérios de aceite

1. Contrato do vínculo aprovado: chave `(auth.uid → membership)`; 1 membership →
   0..1 colaborador; nunca por e-mail/matrícula/nome/cargo;
2. G2 corrigido no resolver (perfil ativo exigido) com validação SQL;
3. Superfície de leitura decidida (Q1/Q2) e, se exposta, restrita ao próprio
   usuário, fail-closed, sem abrir a tabela;
4. Cardinalidade de colaborador ↔ membership(s) decidida (Q3) e garantida no
   banco se a regra assim exigir;
5. Semântica de colaborador inativo/licença decidida (Q5) com impacto em
   SELF/hierarquia documentado;
6. Nenhuma regra por cargo/job_role/função; engine, `authorize`, `can`,
   RLS F4-08 e origens C/D inalterados;
7. Testes dos estados inválidos (seção 17) presentes e verdes;
8. `npm test`, `npm run build`, `npm run lint` e `git diff --check` verdes no PR
   de implementação.

---

## 19. Riscos

| Risco | Mitigação |
| --- | --- |
| Vínculo virar “identidade da conta” (regressão) | Invariante rígido: vínculo por membership; colaborador nunca identifica conta |
| Reintroduzir vínculo por e-mail/matrícula | Proibido no contrato (G8); código/RLS não oferecem caminho |
| Ambiguidade de SELF (mesmo colaborador, 2 memberships na mesma org) | Q3 → unique (se necessário) + testes |
| Perfil/membership/link desabilitado ainda resolvendo | Endurecimento G2 + fail-closed em todos os elos |
| Expor leitura do vínculo e virar enumerador de terceiros | Função só do próprio usuário; tabela fechada (Q1/Q2) |
| DEV (matrícula) contaminar runtime real | Gate DEV; seam explícito (G9) |
| Mudanças de colaborador/org sem histórico | D8/D9 + Q6: fechar/abrir link; nunca UPDATE no link |

---

## 20. Fora de escopo (F5-02)

- organização ativa/switcher (F5-03); roles/capabilities em runtime (F5-04);
  ActorContext (F5-05);
- migração geral de `localStorage`; persistência remota dos domínios funcionais;
- hardening geral (F6); hosting/arquitetura online/observabilidade/backup;
- UI de administração do vínculo (fase posterior, caminho server-side);
- novas capabilities, mudanças no engine ou em F3-estrutura.

---

## 21. Questões para validação

### Q1 — Exposição do próprio vínculo ao runtime: função read-only agora?

- **Contexto:** a tabela do vínculo e os resolvers estão **fechados** a
  `authenticated` (F4-08). F5-03/F5-05 ainda não existem; a F5-01 também não
  precisa do colaborador.
- **Por que:** decidir se a implementação da F5-02 cria já uma função
  read-only do próprio vínculo (para futuros SELF/ActorContext e testes RLS
  reais) ou deixa tudo server-side até F5-05.
- **Alternativas:** (A) manter fechado; nada exposto agora; (B) 1 função
  `resolver_meu_colaborador_vinculado(org)` read-only, só do próprio usuário,
  fail-closed; (C) policy SELECT own-rows na tabela (não recomendado — superfície
  maior).
- **Recomendação:** (B) — permite validar o contrato com RLS real e dá o seam
  pronto a F5-05, sem abrir a tabela; (C) é rejeitada.
- **Impacto/risco:** 1 migration aditiva (função + grants); risco baixo se
  restrito a `auth.uid()`.
- **Seções dependentes:** 3 (G3), 13, 14, 15, 17.

### Q2 — Modo da função do próprio vínculo: INVOKER vs DEFINER

- **Contexto:** F4-02 D18 fechou “resolvers INVOKER; bootstrap DEFINER restrito a
  service_role”.
- **Por que:** uma função INVOKER dependerá de policies na tabela (que
  permanecerá fechada) e, portanto, retornaria vazio — inviável sem expor a
  tabela. Um DEFINER exige guardas explícitas e `set search_path`.
- **Alternativas:** (A) `SECURITY DEFINER` com guards explícitos (auth.uid,
  profile ativo, membership ativa, link ativo, tenant do parâmetro) e `search_path
  = public`, EXECUTE só `authenticated`; (B) INVOKER + policy own-row mínima na
  tabela.
- **Recomendação:** (A) — menor superfície (sem policy de leitura); alinhado à
  exceção já usada em `criar_perfil_membership` (F2-06) para bootstrap.
- **Impacto/risco:** DEFINER é sensível — mitigado com guards completos e testes
  adversarial (IDOR/tenant).
- **Seções dependentes:** 13, 14, 15, 17.

### Q3 — Um colaborador pode ter mais de uma membership ativa na mesma organização?

- **Contexto:** o unique atual é só por `membership_id`; dois usuários distintos
  podem vincular a mesma organização ao mesmo `collaborator`.
- **Por que:** define SELF/identidade da pessoa na organização (1 colaborador =
  quantas contas ativas?).
- **Alternativas:** (A) permitir (colaborador compartilhado é raro e deve ser
  bloqueado em domínio futuro); (B) proibir no banco (unique parcial por
  (collaborator_id, organization_id) onde status='active').
- **Recomendação:** (B) — evita ambiguidade de SELF e ataques de “segunda conta
  vinculada ao mesmo colaborador”; reativação no lugar permanece.
- **Impacto/risco:** 1 migration aditiva (index/constraint unique parcial);
  impacta provisioning.
- **Seções dependentes:** 3 (G6), 4, 18, testes.

### Q4 — Endurecer `resolver_collaborador_vinculado` com profile ativo: sempre?

- **Contexto:** a função hoje não junta `user_profiles`; `resolver_capabilities_escopos_efetivas`
  junta (G2).
- **Por que:** paridade do fail-closed (perfil desabilitado não deve resolver
  vínculo mesmo server-side).
- **Alternativas:** (A) adicionar o join (recomendado); (B) confiar no ban do
  Auth (getUser) — insuficiente quando profile desabilitado sem ban.
- **Recomendação:** (A).
- **Impacto/risco:** mudança aditiva da função; regressão coberta por validação.
- **Seções dependentes:** 3 (G2), 5, 15, 17.

### Q5 — Colaborador inativo/licença × vínculo e SELF

- **Contexto:** status do colaborador é temporal (F3-01): `active/leave/inactive`.
- **Por que:** decidir se o vínculo deixa de resolver quando o colaborador está
  em `inactive`/`leave`, ou se o vínculo (âncora de identidade) permanece e o
  **uso funcional** é bloqueado por estado de domínio.
- **Alternativas:** (A) resolver retorna o vínculo independentemente do status; o
  domínio/engine bloqueia fluxos por status do período; (B) resolver retorna
  vazio para `inactive` (e `leave`?).
- **Recomendação:** (A) — mantém a identidade da pessoa estável e delega regras
  de negócio (licença não encerra ocupação — F3-01); `inactive` bloqueia SELF de
  uso no domínio.
- **Impacto/risco:** semântica clara; testes de SELF com status distintos.
- **Seções dependentes:** 3 (G5), 8, 12, 17.

### Q6 — Mudança de colaborador/ligação e histórico

- **Contexto:** não há caminho formal para “este usuário agora representa outro
  colaborador” nem para reorganização (FK RESTRICT).
- **Por que:** mudanças administrativas precisam preservar histórico/auditoria.
- **Alternativas:** (A) fechar link atual (status disabled) + abrir novo link na
  mesma membership (sem UPDATE no mesmo id); (B) período/validade no link.
- **Recomendação:** (A) nesta fase — simples, preserva histórico e mantém o
  modelo; (B) reavaliar quando F5-03/gestão de pessoas exigir.
- **Impacto/risco:** sem migration estrutural agora; fluxo administrativo
  server-side a implementar depois.
- **Seções dependentes:** 3 (G7/G10), 8, 15.

---

## 22. Decisões arquiteturais (D1–D14 — PROPOSTAS para revisão)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | Chave soberana do vínculo | `(auth.uid() → user_profile → membership) + organization_id`; nunca e-mail, matrícula, nome ou cargo | PROPOSTA |
| D2 | Cardinalidade | 1 membership → 0..1 colaborador (unique por membership; ausência = sem vínculo/ADMIN); reativação no lugar; sem exclusão física | PROPOSTA |
| D3 | Tenant correlation | FKs compostas mantêm membership e colaborador no mesmo tenant; resolução sempre filtrada por `organization_id` da sessão; cross-tenant DENY | PROPOSTA |
| D4 | Vínculo não é identidade da conta | colaborador nunca identifica a conta; e-mail/matrícula nunca são chave; vínculo por tabela própria (F4-02 D1 = A) permanece | PROPOSTA |
| D5 | Porta de resolução | `resolver_collaborador_vinculado` endurecido (profile ativo — Q4) é a origem; runtime real mapeia `(actorId=auth.uid(), organizationId) → colaborador` (consumo em F5-05) | PROPOSTA |
| D6 | Sem vínculo = sem escopo estrutural | SELF/DR/DESCENDANTS/UNIT exigem vínculo ativo (D17 F4-02); sem vínculo resolvem vazio; ADMIN usa ORGANIZATION | PROPOSTA |
| D7 | Colaborador status × vínculo | Vínculo é âncora de identidade independente do status temporal; uso funcional decidido por estado de domínio (Q5) | PROPOSTA |
| D8 | Mudanças de vínculo | Nunca UPDATE no mesmo id: fechar (disabled) + abrir novo link (histórico/auditoria) (Q6) | PROPOSTA |
| D9 | Mutações server-side | Criação/remoção/desativação do vínculo somente por caminho administrativo server-side (RPC/Edge); sem DML direto de `authenticated` | PROPOSTA |
| D10 | Superfície de leitura mínima | Tabela permanece fechada; expõe-se no máximo função do próprio usuário (Q1/Q2); sem policy SELECT ampla | PROPOSTA |
| D11 | Falha em qualquer elo = vazio | profile/membership/link ausente, inativo ou inconsistente ⇒ resolução vazia (fail-closed); nunca heurística | PROPOSTA |
| D12 | Engine intacto | F5-02 não altera o Policy Engine; define o seam (actorId real → colaborador por (actorId, org)); origens C/D independentes do vínculo | PROPOSTA |
| D13 | Sem migration nesta etapa | Nenhuma migration no desenho; implementação prevê no máx. 1 migration aditiva (resolver endurecido; função própria; opcional unique Q3), sem mudar a estrutura existente | PROPOSTA |
| D14 | Seam DEV → real | Mundo DEV (matrícula) permanece isolado por gate; runtime real só usa a cadeia soberana (G9) | PROPOSTA |

---

## 23. Confirmações desta atividade

- Nenhuma alteração funcional foi feita; **somente** este documento.
- Auditoria baseada em leitura direta das migrations F4-02/F4-08/F3-01, das
  validações `supabase/validacao/*f4-02*/f4-08*`, dos contratos F4-02 (D1/D17/D18)
  e do código TS de auth/autorização.
- Próximos passos: revisar D1–D14 e responder Q1–Q6; implementação do contrato em
  PR próprio (sem UI de gestão, sem F5-03/04/05).

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
