# F6-A03 — Bootstrap mínimo seguro do GREENFIELD (desenho técnico)

> **Status:** desenho **fechado para implementação** (nenhum código funcional nesta atividade).
> **Atividade:** F6-A03 — Issue **#266**.
> **Base auditada:** `main` em `52348dd` (árvore limpa; nenhum artefato de runtime tocado).
> **Natureza:** documento de desenho. **Zero** migration, RPC, Edge, capability, role, policy,
> RLS, grant, página, teste ou workflow de CI criados/alterados aqui.

## 1. Objetivo, escopo e não-escopo

### 1.1 Objetivo

Destravar o cenário **GREENFIELD** da F6 (`.ai`/`docs/F6-01-desenho-tecnico.md:120-129`) hoje
**impossível de executar pelos fluxos reais do produto**, fechando a cadeia mínima:

```text
operador de plataforma autorizado
  → cria organização
    → estabelece o primeiro Admin do tenant
      → identidade + membership + role admin válidas
        → primeiro login operacional
```

### 1.2 Não-escopo (explícito)

| Fora de escopo | Motivo |
| --- | --- |
| Portal SaaS, billing, gestão comercial, planos, cobrança, limites por plano | Determinado pela Issue #266 e pelo enunciado da atividade |
| Lifecycle de organização (`status` de organização, suspensão, exclusão, renomeação pela UI) | `organizations` **não possui** lifecycle no contrato vigente — `docs/F5-03-desenho-tecnico.md:217-222` ("Disponibilidade = membership ativa (modelo atual não tem status de organização)") |
| UI/página de criação de organização | O desenho entrega o **caminho soberano** (Edge + RPC); a superfície de tela pertence a atividade posterior com Issue própria |
| Gestão comercial de operadores (autoatendimento, convite de operador, revogação em runtime) | Fora de escopo; ver **Q1** (§12) |
| Versão baseline de configuração de avaliação (`evaluation_config_bootstrap`) e criação de ciclo | F6-C; a F6-A03 termina no primeiro login operacional |
| Migração de `localStorage` ou cutover de domínios legados | F6-E; nenhuma relação com o bootstrap |
| Correção das dívidas de processo registradas em §10 | Registradas, não corrigidas |

### 1.3 Rastreabilidade da Issue (registro honesto)

O texto da **Issue #266 não é legível neste ambiente** (sem `gh` e sem mecanismo autorizado de
leitura da API; nenhum contorno com PAT/credencial foi usado — `AGENTS.md` §6 / DEV-04). O escopo
acima foi derivado **do enunciado da atividade** e da evidência do repositório. Se a Issue contiver
critério divergente, **este documento deve ser corrigido antes da implementação**.

---

## 2. Estado atual auditado (o que existe hoje)

### 2.1 Modelo de identidade — real e vigente

| Peça | Evidência | Papel |
| --- | --- | --- |
| `public.organizations` | `supabase/migrations/20260906201856_organizations_user_profiles.sql:40-48` | Raiz do tenant. Colunas: `id`, `name`, `created_at`, `updated_at`, `version`. **Sem `status`/lifecycle** e **sem unicidade de nome** (`:57-59`) |
| `public.user_profiles` | idem `:90-101` | Perfil interno 1:1 com `auth.users` (FK `RESTRICT`), `status ∈ {active, disabled}` |
| `public.user_organization_memberships` | `supabase/migrations/20260906203358_user_organization_memberships.sql:60-79` | Vínculo de acesso. `unique (user_profile_id, organization_id)`; `status ∈ {active, disabled}` |
| Policies mínimas de leitura | `supabase/migrations/20260906205425_auth_read_policies.sql:25-50` | `user_profiles` (próprio), memberships (próprias), `organizations` (via membership ativa) |
| Fronteira soberana de tenant | `supabase/migrations/20260908100000_f4_08_helpers_function_grants.sql:26+`; `20260908150000_f4_08_organizations_profile_active.sql:19-23` | `user_has_active_membership`: perfil **ativo** + membership **ativa** |
| Least privilege de tabela | `supabase/migrations/20260908140000_f4_08_revoke_excess_table_privileges.sql:27-28`, `:36` | `revoke all` de `anon`/`authenticated`; regrant **somente `SELECT`** em `organizations` |

### 2.2 Modelo de autorização — real e vigente

| Peça | Evidência | Papel |
| --- | --- | --- |
| `capabilities` (global, 31 códigos) | `supabase/migrations/20260908000000_authorization_capabilities_access_roles.sql`; `20260910000000_f5_04_catalog_reconciliation.sql:53-73` | Vocabulário global |
| `access_roles` | `20260908000000:102-122` | Roles de **sistema** (`is_system = true`, `organization_id NULL`) ou customizadas por organização |
| Role de sistema `admin` | `supabase/migrations/20260908000001_authorization_system_catalog.sql:69-70` (`c0000000-0000-4000-8000-0000000000f1`) | Única role administrativa de sistema |
| Bundle `admin` = **9** capabilities funcionais | `20260908000001:75-89` + `20260910000000:95-106` + `supabase/migrations/20260921000000_f5_09_p7_catalog_admin_bundle.sql` | `membership.read`, `collaborator.read`, `collaborator.create`, `collaborator.edit`, `org.structure.manage`, `org.catalog.manage`, `settings.manage`, `cycle.read`, `cycle.manage`. **Sem** `evaluation.*`, `goal.*`, `observation.*`, `report.read` (`supabase/validacao/02-validar-f4-01.sql:631-633`) |
| Atribuição membership→role | `20260908000000:199-230` | `unique (membership_id, access_role_id)`; revogação por estado |
| Primitivo de concessão | `20260908000000:305-372` — `conceder_acesso_role`, `SECURITY DEFINER`, `EXECUTE` só `service_role` (`:456-459`) | Valida membership ativa, perfil ativo, role ativa e tenant; reativa no lugar |
| Separação do plano administrativo | `20260910000000:112-151` (`enforce_role_capability_grantable`) | `membership.manage`/`access_role.manage` são `grantable_via_role = false`: **nenhuma** role pode carregá-las |
| Autoridade administrativa do tenant | `supabase/migrations/20260934000000_f5_11_p5_2_admin_authority_por_role.sql:37-62` | `usuario_eh_administrador` = membership ativa **+ atribuição ativa da role de sistema `admin` nominal** |
| Caminho administrativo do tenant | `supabase/migrations/20260936000000_f5_11_p5_4_avaliado_exclusivo_e_corrida.sql:48-122` | `conceder_acesso_role_rpc`: exige `usuario_eh_administrador` (`:107-110`) **e proíbe auto-concessão** (`:88-91`) |
| Trilha append-only de privilégio (D18) | `supabase/migrations/20260910010000_f5_04_privilege_audit_trail.sql:22-33`; evolução `20260933000000_f5_11_p5_1_self_read_observacoes.sql:186-223` | `action ∈ {grant, revoke, system_grant, system_revoke}` com constraint **bicondicional** de ator (humano exige ator; sistema exige `NULL`) |
| Representação de autoria na atribuição | `20260933000000:231-250` | `origin ∈ {human, system}`; `created_by` obrigatório quando `human` |

### 2.3 Plano de plataforma hoje — o único mecanismo existente

| Peça | Evidência | Comportamento |
| --- | --- | --- |
| Allowlist de operador | `supabase/config.toml:63-66` (`INVITE_ADMIN_USER_IDS`) | Lista de UUIDs de identidade; **não é credencial** |
| Verificação | `supabase/functions/convidar-usuario/index.ts:78-84`; `supabase/functions/gerenciar-usuario/index.ts:76-80` | JWT verificado (`auth.getUser`) → allowlist (fail-closed: variável ausente ⇒ 403) → `user_profiles.status = 'active'` |
| Alcance do convite | `supabase/functions/convidar-usuario/index.ts:104-110`, `:126-129` | `organization_id` vem **do corpo**, sem relação do chamador com o tenant — lacuna **G11** já registrada em `docs/F5-01-desenho-tecnico.md:254` |
| Criação de usuário | `supabase/functions/convidar-usuario/index.ts:113-145` | `auth.admin.inviteUserByEmail` + `criar_perfil_membership` + compensação (remove o usuário do Auth em falha) |
| Desativação | `supabase/functions/gerenciar-usuario/index.ts:108-141` | `user_profiles.status` + ban no Auth, **sem** recorte de tenant |

**Conclusão do plano de plataforma:** ele existe, é fail-closed e é **provisório por contrato**
(F4-01 invariante 6: "nenhuma allowlist provisória é removida antes de existir substituto seguro",
`docs/F4-01-desenho-tecnico.md:431-432`). Ele **não** confere capability, role nem escopo de tenant.

### 2.4 Primeiro login hoje

`src/auth/servico.ts:93-110` resolve perfil ativo → memberships ativas → organizações; `:99-101`
perfil ausente ⇒ `AccessNotProvisionedError`; `:102-104` perfil inativo ⇒ `ForbiddenError`
(fail-closed). `src/auth/organizacaoAtiva.ts:114-124` deriva a organização efetiva (N=0 ⇒ `null`;
N=1 ⇒ implícita). `src/auth/rotasProtegidas.ts:43-49` + `src/auth/SemOrganizacao.tsx:10-42` mostram
o estado `semOrganizacao`.

---

## 3. Bloqueios encontrados (o GREENFIELD não é executável hoje)

> Todos verificados por leitura de código, não por suposição. Cada bloqueio é citado com evidência.

### B1 — Não existe caminho autorizado para **criar organização**

- `public.organizations` está com RLS habilitado e **zero policies**
  (`20260906201856:144`; `20260906205425` não cria policy de escrita).
- `authenticated`/`anon` têm **todos** os privilégios de tabela revogados e recebem de volta
  **apenas `SELECT`** (`20260908140000:27-28`, `:36`).
- **Não existe RPC de criação de organização**: o inventário exaustivo de
  `create or replace function public.*` nas 62 migrations não contém nenhuma função que insira em
  `organizations`. A única função que toca organização funcionalmente é
  `criar_perfil_membership(p_user_id, p_organization_id)` (`20260906230400:19-35`), que **exige uma
  organização já existente**.
- Todas as ocorrências de `insert into public.organizations` no repositório estão em
  `supabase/validacao/*` (fixtures executadas como superuser) — nenhuma em caminho de produto.

**Efeito:** organizações só nascem por migration/fixture. O GREENFIELD da F6 exige "organização de
teste separada, construída progressivamente pelos fluxos reais" (`docs/F6-01-desenho-tecnico.md:125`).

### B2 — Não existe caminho para o **primeiro** `admin` (circularidade + anti-auto-concessão)

- `usuario_eh_administrador` exige atribuição **ativa** de `admin` na organização
  (`20260934000000:47-61`) — em tenant recém-nascido, ninguém a possui ⇒ **circular**.
- `conceder_acesso_role_rpc` exige `usuario_eh_administrador` do alvo
  (`20260936000000:107-110`) e **proíbe** que o ator conceda à própria membership (`:88-91`).
- O primitivo `conceder_acesso_role` (`20260908000000:305-372`) **não** tem checagem de autoridade,
  mas é `EXECUTE` **só `service_role`** e **nenhum caminho server-side o expõe para bootstrap**.

**Efeito:** mesmo com a allowlist de plataforma, não há como estabelecer o primeiro Admin.

### B3 — O convite produz membership **sem nenhuma role**

`convidar-usuario` chama apenas `criar_perfil_membership`
(`supabase/functions/convidar-usuario/index.ts:126-129`), que cria perfil + membership e **nenhuma
atribuição**. O convidado autentica, resolve identidade e organização, e chega ao produto com
**zero capabilities** — inclusive `admin`.

**Evidência circunstancial convergente:** no cenário local, a identidade da allowlist
(`b0000000-0000-0000-0000-000000000001`) é criada por fixture com perfil e membership e **sem
nenhuma atribuição de role** (`supabase/validacao/01-cenario-f2-10.sql:103-107`, `:156-162`,
`:170-175`). Isto é, **nem o operador de plataforma tem hoje qualquer capability de tenant** — o que
confirma materialmente a separação dos dois planos (§4).

### B4 — Não existe superfície de produto para atribuir role

O caminho administrativo do tenant existe no banco e em Edge
(`supabase/functions/gerenciar-access-role/index.ts:41-81`), mas:

- **nenhum módulo do cliente o invoca** (o cliente chama `functions.invoke` apenas para
  `convidar-usuario`, `avaliacoes`, `ciclos`, `colaboradores`, `metas`, `observacoes`);
- `[functions.gerenciar-access-role]` **não está declarado** em `supabase/config.toml` (o arquivo
  declara `convidar-usuario`, `gerenciar-usuario`, `avaliacoes`, `metas` e `observacoes` — `:71-104`).

**Efeito:** mesmo após B2 resolvido, o Admin do tenant não consegue conceder roles pela interface —
o que **limita** o "primeiro login operacional" (ver §9.3).

---

## 4. Separação: autoridade de plataforma × role `admin` do tenant

Esta é a decisão central da atividade.

### 4.1 Os dois planos

| Dimensão | **Plano de plataforma** | **Plano do tenant** |
| --- | --- | --- |
| Identidade | Operador autorizado na allowlist do ambiente + `user_profiles` ativo | Membership ativa + atribuição ativa da role de sistema `admin` |
| Onde é resolvida | Fronteira server-side (Edge), do JWT verificado | Banco: `usuario_eh_administrador` (`20260934000000:37-62`) |
| O que confere | **Zero** capabilities, **zero** roles, **zero** membership, **zero** escopo | 9 capabilities funcionais; administração **da sua** organização |
| Representação em dados | **Nenhuma** — não é `access_role`, não é `capability`, não é assignment | Linha em `membership_access_role_assignments` com `origin = 'human'` |
| Alcance | Operações de plataforma **enumeradas** (hoje: convidar/desativar conta; nesta atividade: provisionar organização inicial) | Tudo que as 9 capabilities permitem **dentro** do tenant |
| Auditoria | Trilha append-only própria (§6.4) + `privilege_mutation_audit` para o efeito de privilégio | `privilege_mutation_audit` (D18) |

### 4.2 Invariantes de separação (inegociáveis na implementação)

1. **A autoridade de plataforma NUNCA é registrada em `capabilities`, `access_roles`,
   `access_role_capabilities` ou `membership_access_role_assignments`.** Não existe role de
   plataforma, nem capability `platform.*`, nem assignment de plataforma.
2. **Ser operador de plataforma NÃO confere nenhuma capability de tenant** — nem administrativa,
   nem de conteúdo.
3. **Ser `admin` de um tenant NÃO confere nenhuma autoridade de plataforma**: nenhum caminho de
   tenant cria organização, altera a allowlist ou provisiona outro tenant.
4. A acumulação das duas autoridades por uma mesma pessoa é **contingente** (duas verificações
   independentes em planos distintos), nunca **derivada** de uma para a outra.
5. O plano de plataforma **não reduz** nenhum controle existente: `conceder_acesso_role_rpc`,
   `usuario_eh_administrador`, `enforce_role_capability_grantable`, a lista fechada de
   capabilities concedíveis e o anti-self-escalation do tenant permanecem **intocados**.

### 4.3 Coerência com decisões já FECHADAS (não reabertura)

| Decisão fechada | Como este desenho a respeita |
| --- | --- |
| **F4-01 D17** (`docs/F4-01-desenho-tecnico.md:697-710`): `admin` é por organização; "operação de plataforma" fica para quando as Edge Functions migrarem, **sem inventar papel global** | Este é exatamente aquele momento, **limitado ao mínimo**: a operação de plataforma é resolvida **sem** criar papel global — nenhuma role nova (§4.2.1) |
| **F4-01 D9** (`:578-591`): a atribuição inicial é feita por caminho administrativo e **nunca por UUID fixo em código** | A role `admin` é resolvida por `name = 'admin' and is_system = true` (canônico, molde `20260933000000:297-299`), **nunca** pelo UUID `c0000000-…-f1` |
| **F4-01 D16** (`:676-695`) e invariante 6 (`:431-432`): mecanismo mínimo server-side, sem ampliar RLS, sem substituir allowlist prematuramente | Nenhuma policy nova; a allowlist vigente é **reutilizada**, não substituída |
| **F5-04 D15/D16** (`docs/F5-04-desenho-tecnico.md:467-468`): plano administrativo separado; ator soberano; tenant revalidado; cross-tenant DENY | Mantidos; o novo caminho é de **plataforma**, não reclassifica o plano administrativo do tenant |
| **F5-11 P5.2** (`20260934000000`): autoridade administrativa discriminada pela role `admin` nominal | Preservada integralmente; o novo caminho **não** altera `usuario_eh_administrador` |
| **F6-01 §4** (`docs/F6-01-desenho-tecnico.md:120-129`): isolamento LEGACY × GREENFIELD | A organização GREENFIELD nasce por caminho soberano, com tenant próprio; nenhum dado LEGACY é tocado |
| **`.ai/architecture-rules.md` §1, §4** | `auth.uid()` soberano; tenant server-side; fail-closed; cross-tenant DENY; **nenhum `SECURITY DEFINER` novo** |

---

## 5. Fluxo mínimo proposto

```text
[1] Operador de plataforma autentica no produto (Supabase Auth)  →  JWT
        │
[2] Edge `provisionar-organizacao` (NOVA) — fronteira server-side única
        ├─ resolve identidade SOBERANA: auth.getUser(JWT)         (molde F5-04/F5-11)
        ├─ allowlist de plataforma (fail-closed: ausente ⇒ 403)   (reuso config.toml:63-66)
        ├─ piso `user_profiles.status = 'active'` (fail-closed)
        ├─ forma da intenção: allowlist ESTRITA de chaves
        │     { operation_id, organization_name, founder_user_id | founder_email }
        │     (chave fora da allowlist ⇒ INVALID_INPUT; forma NUNCA é autoridade)
        └─ e-mail ⇒ auth.admin.inviteUserByEmail  (+ compensação) (molde convidar-usuario:113-145)
        │
[3] RPC `organizacao_provisionar_inicial(...)` — UMA transação, idempotente
        (SECURITY INVOKER, search_path = public, EXECUTE só service_role — SEM DEFINER novo)
        a. gate de plataforma no banco: ator existe e está `active`
        b. idempotência: INSERT-ON-CONFLICT por `operation_id` + `payload_hash`
        c. INSERT organização (nome normalizado; `btrim` não vazio)
        d. INSERT `user_profiles` do founder SE AUSENTE (on conflict do nothing)
        e. INSERT membership (founder, nova org, `active`)
        f. `perform conceder_acesso_role(membership, admin_role, operador)`  ← REUSO F4-01
        g. INSERT `privilege_mutation_audit` (`grant`, ator = operador)      ← REUSO D18
        h. fecha o evento de provisionamento (org + operador + founder)
        │
[4] Founder autentica → identidade resolvida (perfil ativo + membership ativa + organizations)
        │  N=1 ⇒ organização efetiva implícita  (src/auth/organizacaoAtiva.ts:114-124)
        │
[5] Primeiro login operacional: `admin` resolve 9 capabilities funcionais no tenant novo
```

### 5.1 Por que a fronteira é Edge + RPC (e não SQL manual, e não UI)

- **SQL manual** não é fluxo de produto: o GREENFIELD F6 exige percurso pelas jornadas reais.
- **UI** é superfície posterior (§1.2); o desenho entrega o caminho soberano primeiro.
- **Edge + RPC** é o molde vigente e auditado do repositório (F5-04, F5-06, F5-09, F5-10, F5-11):
  identidade resolvida na Edge, execução com `service_role` **sem o JWT do usuário no
  `Authorization`** (`supabase/functions/gerenciar-access-role/index.ts:10-20`), ator passado como
  `p_actor_user_profile_id` derivado **exclusivamente** do JWT verificado.

### 5.2 Contenção por construção (não por checagem replicada)

O RPC de bootstrap é **estruturalmente incapaz** de escalar privilégio existente. Invariantes
verificáveis:

1. só **insere** organização (`organizations`); **nunca** atualiza nem exclui organização alguma;
2. só **insere** membership para um par (perfil, organização) **necessariamente novo** — a
   organização acabou de nascer na mesma transação;
3. só concede a role de sistema `admin` (resolvida por nome, nunca por UUID);
4. **nunca** toca organização, membership ou atribuição pré-existentes; qualquer estado que exija
   tocar algo existente ⇒ **LEVANTA** (fail-closed);
5. portanto a autoridade de plataforma **não** é um bypass genérico: mesmo em posse de
   `service_role`, o pior caso é criar **tenant novo e vazio** — nunca elevar privilégio dentro de
   um tenant existente.

> Consequência: o bootstrap **não** reutiliza `conceder_acesso_role_rpc` e **não** relaxa o
> anti-self-escalation do plano do tenant. Ele reutiliza o **primitivo** `conceder_acesso_role`
> (`20260908000000:305-372`) — que valida membership/perfil/role/tenant e reativa no lugar —, o que
> é possível porque a atribuição nasce junto com o tenant e não incide sobre autoridade pregressa.

---

## 6. Contratos técnicos propostos (não implementados nesta atividade)

### 6.1 Edge `provisionar-organizacao` (nova)

- Trio no molde vigente: `index.ts` (fino, só wiring + Deno APIs) + `core.ts` (núcleo testável, sem
  APIs de runtime) + reexport do contrato transportável.
- `verify_jwt = true` em `supabase/config.toml` (molde `[functions.metas]` / `[functions.observacoes]`).
- **Allowlist ESTRITA de chaves**: `{ operation_id, organization_name, founder_user_id,
  founder_email }`. Chave fora da allowlist ⇒ `INVALID_INPUT`.
- **Nunca transportáveis**: `actor_*`, `organization_id`, `access_role_id`, `capability`, `scope`,
  `status`, `version`, `origin`, `payload_hash`. A forma **nunca** é autoridade.
- `founder_user_id` **XOR** `founder_email` (ambos ou nenhum ⇒ `INVALID_INPUT`).
- `operation_id` obrigatório (UUID canônico).

### 6.2 RPC `organizacao_provisionar_inicial` (nova)

```text
organizacao_provisionar_inicial(
  p_operation_id            uuid,
  p_organization_name       text,
  p_founder_user_profile_id uuid,
  p_actor_user_profile_id   uuid
) returns uuid   -- organization_id
```

- `SECURITY INVOKER`, `set search_path = public` — **nenhum `SECURITY DEFINER` novo** (a validação
  F4-08 falha o CI se o conjunto de DEFINER mudar: `supabase/validacao/02-validar-f4-08.sql:41`).
- `revoke all ... from public, anon, authenticated` + `grant execute ... to service_role`.
- Fail-closed: `p_operation_id`/`p_actor_user_profile_id`/`p_founder_user_profile_id` nulos ⇒
  levanta; ator com perfil não ativo ⇒ levanta; founder inexistente em `auth.users` ⇒ levanta (FK);
  nome vazio após `btrim` ⇒ levanta.
- **Doutrina de idempotência (reuso do precedente P5.4 e do `payload_hash` server-side):**
  - `payload_hash` calculado **server-side** com
    `encode(sha256(convert_to(<payload canônico>::text,'UTF8')),'hex')` — mesmo molde de
    `20260914010000_f5_08_structure_rpc.sql:43-45`;
  - **um único** `insert ... on conflict (operation_id) do nothing returning id`
    (molde `20260936000000:30-33`): quem **retorna linha** é o dono da operação e prossegue;
    quem **não** retorna relê o evento:
    - mesmo `payload_hash` ⇒ **REPLAY**: devolve o `organization_id` já gravado, **sem** novo efeito;
    - `payload_hash` divergente ⇒ **RECUSA** (`OPERATION_ALREADY_APPLIED`), fail-closed.
  - **Sem advisory lock** (a constraint `unique` é o ponto de serialização — doutrina D10 do repo).
- Preflight de privilégios e guarda final fail-closed no molde das RPCs F5-09/F5-10/F5-11.

### 6.3 Códigos públicos (mapa fechado, molde `corpoDeErroEdge`)

| Código público | Condição |
| --- | --- |
| `NOT_AUTHORIZED` | Sem JWT válido · fora da allowlist de plataforma · perfil do operador não ativo |
| `INVALID_INPUT` | Corpo inválido · chave fora da allowlist · `operation_id` não-UUID · XOR de founder violado |
| `INVALID_NAME` | Nome vazio/normalizado vazio |
| `INVALID_FOUNDER` | Founder inexistente em `auth.users` ou perfil não ativo |
| `USER_EXISTS` | `founder_email` já corresponde a usuário existente (usar `founder_user_id`) |
| `OPERATION_ALREADY_APPLIED` | Mesmo `operation_id` com `payload_hash` divergente |
| `INTERNAL` | Qualquer outra falha (sem vazar detalhe interno) |

### 6.4 Tabela nova `platform_provisioning_events` (única tabela nova)

| Aspecto | Definição |
| --- | --- |
| Colunas | `id`, `operation_id` (UUID, **unique**), `payload_hash` (SHA-256 hex, CHECK), `organization_id`, `organization_name`, `actor_user_profile_id`, `founder_user_profile_id`, `created_at` |
| Papel | Âncora de **idempotência** + trilha de **criação de tenant** do plano de plataforma |
| RLS | `ENABLE ROW LEVEL SECURITY`, **zero policies** (deny-by-default integral — padrão D9/D22-A) |
| ACL | `revoke all` de `public`/`anon`/`authenticated`; `service_role` com **`SELECT` + `INSERT` apenas** (append-only) |
| Imutabilidade | trigger `before update` no molde de `enforce_privilege_audit_append_only` (`20260910010000:58-60`) |
| FKs | **Nenhuma** — precedente explícito de D18 (`20260910010000:35-39`): registro imutável não bloqueia o ciclo de vida da origem |
| Racional da tabela | É o único jeito de obter idempotência real **sem** que o cliente declare identidade: `organizations.id` continua gerado por `gen_random_uuid()` (convenção F1-02) |

---

## 7. Componentes reutilizados × novos

### 7.1 Reutilizados (não recriar)

| Componente | Reuso |
| --- | --- |
| Allowlist de plataforma (`INVITE_ADMIN_USER_IDS`) | Autoridade de plataforma vigente; **não** substituída (F4-01 invariante 6) |
| Molde Edge `index`/`core`/`contrato` | F5-04/F5-10/F5-11 |
| Identidade soberana por `auth.getUser` | F2-06/F2-07/F5-04/F5-11 |
| Compensação do Auth Admin | `convidar-usuario/index.ts:131-145` |
| `organizations`, `user_profiles`, `user_organization_memberships` | Entidades existentes; **nenhuma coluna nova** |
| `access_roles` (sistema `admin`, por nome) | F4-01 D9 |
| `conceder_acesso_role` (primitivo) | F4-01 D16 |
| `privilege_mutation_audit` | F5-04 D18 (+ evolução P5.1) |
| `sha256` / `payload_hash` server-side | F5-08/F5-09/F5-10/F5-11 |
| `INSERT ... ON CONFLICT ... RETURNING` como serialização | F5-11 P5.4 |
| `carregarErroEdge`/`corpoDeErroEdge` (taxonomia pública F0-05) | F2-06/Issue #221/#224 |
| Fluxo de sessão/organização efetiva | F5-01/F5-03 (`src/auth/*`) — **sem alteração** |

### 7.2 Novos (inventário para a atividade de implementação)

| Artefato | Observação |
| --- | --- |
| `supabase/migrations/<timestamp>_f6_a03_bootstrap_organizacao.sql` | Tabela `platform_provisioning_events` + RPC `organizacao_provisionar_inicial` |
| `supabase/functions/provisionar-organizacao/{index,core}.ts` | Edge nova |
| `src/infrastructure/supabase/plataforma/contrato.ts` (+ adapter fail-closed) | Contrato transportável único e adapter no molde `edgeObservacoes.ts` (3 caminhos: `error`, `data.error`, `data.ok !== true`) |
| `[functions.provisionar-organizacao]` em `supabase/config.toml` | `verify_jwt = true` |
| `supabase/validacao/44-cenario-f6-a03.sql` + `45-validar-f6-a03.sql` | Cenário sintético + validador (próximos números livres) |
| 2 passos novos em `.github/workflows/ci.yml` | Molde das duplas cenário/validador vigentes |
| Testes unitários da Edge/contrato | Molde `observacoesEdge.test.ts`, `metasContratoRpc.test.ts` |
| Página/UI de provisionamento | **Fora** desta atividade (§1.2) |

---

## 8. Guardas e validações impactadas

> Levantado por leitura; a implementação **deve** atualizá-las na mesma entrega, ou o CI falha.

| Guarda | Evidência | Impacto |
| --- | --- | --- |
| `DEFINER` esperado = **4** | `supabase/validacao/02-validar-f4-08.sql:41` | **Inalterado** — o desenho não cria `SECURITY DEFINER` |
| Policies esperadas = **23** | `02-validar-f4-08.sql:192` | **Inalterado** — a tabela nova nasce sem policy |
| Inventário D16 (tabelas) | `02-validar-f4-08.sql:385-409` (**assert**) | **Exige** inclusão de `platform_provisioning_events` (51 → 52) |
| Arrays de privilégio (3) | `02-validar-f4-08.sql:248-272`, `:290-314`, `:328-353` | Incluir a tabela nova nos 3 (fechadas) e atualizar as contagens em `raise notice` (`:282`, `:323`, `:373`) |
| Classificação duplicada | `supabase/validacao/03-validar-f4-08-mutacoes.sql:60-85` e `:97-120` | Incluir a tabela nova nas **duas** cópias |
| Listas fechadas de funções por domínio | `15-validar-f5-09-p9.sql`, `30-validar-f5-10-p7.sql`, `35-validar-f5-11-p1.sql` | **Inalterado** — o nome da função nova não casa com os filtros `%observa%`/`%meta%`/`%goal%` (o mesmo cuidado já documentado em `20260936000000:35-38`) |
| EXECUTE de funções novas | `02-validar-f4-08.sql:62-91` | `revoke` de `public`/`anon`/`authenticated` **obrigatório** |
| Contagem de capabilities = **31** | `15-validar-f5-09-p9.sql:2126`; preflight `20260933000000:44-47` | **Inalterado** — nenhuma capability nova |
| Bundle `admin` = **9** | `02-validar-f5-04.sql:186-192`; `11-validar-f5-09-p7.sql:28-31`; `02-validar-f4-01.sql:400-402` | **Inalterado** — nenhuma capability nova no bundle |
| `admin` sem `observation.*` | `20260933000000:71-79` | **Inalterado** |

---

## 9. Critérios de aceite

### 9.1 Do caminho (segurança e isolamento)

1. **Sem JWT válido** ⇒ `NOT_AUTHORIZED` (401); **sem allowlist configurada** ⇒ `NOT_AUTHORIZED`
   (fail-closed, molde `convidar-usuario:78-84`).
2. Identidade **fora** da allowlist ⇒ `NOT_AUTHORIZED` (403); operador com
   `user_profiles.status ≠ 'active'` ⇒ `NOT_AUTHORIZED` (403).
3. Chave fora da allowlist (ex.: `actor_user_profile_id`, `organization_id`, `capability`, `scope`)
   ⇒ `INVALID_INPUT`; **nenhum** campo de identidade/autoridade é aceito do corpo.
4. O ator gravado (`actor_user_profile_id`) é **exclusivamente** o `auth.uid()` verificado; não há
   caminho para declará-lo.
5. **Cross-tenant**: o provisionamento **não** referencia organização existente; um
   `organization_id` no corpo é recusado pela allowlist de chaves.
6. Nenhuma organização, membership ou atribuição **preexistente** é criada, alterada ou removida
   pelo caminho (prova negativa: contagens antes/depois idênticas fora do tenant criado).
7. O bundle do tenant novo é **exatamente** o de `admin` (9 capabilities); **nenhuma** capability
   de plataforma existe em `capabilities`.
8. `access_roles` permanece com **as mesmas** roles de sistema (nenhuma role nova);
   `capabilities` permanece com **31**; `enforce_role_capability_grantable` intacto.

### 9.2 Da transação e da idempotência

9. **Atomicidade**: falha em qualquer passo (d) a (h) ⇒ **nada** persiste (organização, perfil,
   membership, atribuição e eventos ausentes).
10. **Idempotência por replay**: repetir com o **mesmo** `operation_id` e **mesmo** payload ⇒
    devolve o **mesmo** `organization_id`, **sem** criar segunda organização, **sem** segundo
    evento e **sem** segunda linha de auditoria.
11. **Recusa por divergência**: mesmo `operation_id` com payload diferente ⇒
    `OPERATION_ALREADY_APPLIED`, fail-closed, **sem** efeito colateral.
12. **Concorrência real** (duas sessões, sem advisory lock): o perdedor **não** cria organização
    duplicada nem emite evento falso; o estado final tem **exatamente uma** organização para o
    `operation_id`.
13. Trilha: `privilege_mutation_audit` recebe **um** `grant` com ator = operador (não `NULL`);
    `platform_provisioning_events` recebe **uma** linha; `platform_provisioning_events` é
    append-only (UPDATE recusado) e invisível para `authenticated`/`anon`.

### 9.3 Do primeiro login operacional

14. O founder autentica, resolve perfil ativo + **uma** membership ativa e vê a organização nova
    (N=1 ⇒ organização efetiva implícita, `src/auth/organizacaoAtiva.ts:114-124`).
15. `src/auth/servico.ts:93-110` **não** devolve `AccessNotProvisionedError` nem `ForbiddenError`:
    o estado é `autenticado` (com organização), não `semOrganizacao`.
16. Autoridade do tenant efetiva: `resolver_capabilities_efetivas(founder, org_nova)` devolve as
    **9** capabilities de `admin`; `usuario_eh_administrador(founder, org_nova)` = `true`.
17. **Alcance declarado do primeiro login (limite honesto):** o Admin recém-criado consegue, por
    via soberana, administrar **estrutura e catálogos, colaboradores e ciclos**
    (`org.structure.manage`, `org.catalog.manage`, `collaborator.*`, `cycle.read`, `cycle.manage`) e
    criar a versão baseline de configuração (`evaluation_config_bootstrap` exige apenas ator válido,
    `20260911010000:141-143`). **Não** consegue, com o bundle `admin`: avaliações, metas,
    observações, relatórios — isso é **por contrato** (F4-01 D18) e continua dependente da
    atribuição de roles por caminho administrativo (**B4**, §10.3).
18. **Isolamento LEGACY × GREENFIELD**: nenhum dado LEGACY aparece no tenant novo; as consultas do
    founder não retornam linha alguma de organização alheia (RLS + `user_has_active_membership`).

### 9.4 Evidência exigida na implementação

19. `supabase db reset --local --yes` + validador focado (`44`/`45`) verdes, com o par de
    concorrência real (critério 12) — na ordem do CI.
20. `npm test`, `npm run build`, `npm run lint`, `git diff --check` verdes (ou limitação de ambiente
    registrada com comando, resultado e causa — molde do CRLF documentado).
21. CI no **SHA do PR** com os dois jobs verdes; correção posterior ⇒ novo SHA + novo CI (DEV-04).

---

## 10. Ameaças relevantes e mitigações

| # | Ameaça | Cenário | Mitigação neste desenho |
| --- | --- | --- | --- |
| T1 | **Escalada por auto-concessão** | Operador cria organização e se faz `admin` para, depois, usar `admin` para escalar dentro de um tenant | O caminho só toca tenant **recém-nascido e vazio** (§5.2); `conceder_acesso_role_rpc` e o anti-self-escalation do tenant permanecem intactos (`20260936000000:88-91`) |
| T2 | **Confusão de planos** (tratar o operador como super-admin de conteúdo) | Uso indevido da allowlist como autorização de tenant | §4.2.1–4.2.3: a autoridade de plataforma **não** é representável como role/capability; nenhum caminho de tenant a consulta |
| T3 | **Cross-tenant no convite** (lacuna G11 vigente) | Operador da allowlist convida usuário para organização **alheia**, pois o `organization_id` vem do corpo sem relação com o chamador (`convidar-usuario/index.ts:104-110`) | **Registrado** (já em `docs/F5-01-desenho-tecnico.md:254`). O caminho novo **não** repete o padrão: não aceita `organization_id` algum e cria a organização na própria transação. Correção do convite fica fora deste escopo (§10.3) |
| T4 | **Credencial de plataforma comprometida** | Quem detém `service_role` ou altera a allowlist | Contenção por construção (§5.2.5): o pior caso é criar tenant novo vazio; nenhuma leitura de conteúdo, nenhuma mutação de tenant existente |
| T5 | **Duplicação de tenant por retry** | Timeout/retry do operador cria duas organizações | Idempotência por `operation_id` + `payload_hash` (§6.2), recusa fail-closed em divergência |
| T6 | **Corrida no primeiro provisionamento** | Duas chamadas concorrentes | `insert ... on conflict ... returning` como ponto único de serialização (§6.2); **sem** advisory lock; o perdedor não emite evento falso (precedente P5.4) |
| T7 | **Identidade do founder forjada** | Corpo declara e-mail/UUID de terceiro | Legítimo **por desenho** (é o operador que designa o founder), mas: (i) o founder precisa existir em `auth.users` (FK); (ii) o efeito é **só** membership + `admin` no tenant **novo**; (iii) autor + founder ficam **ambos** registrados na trilha |
| T8 | **Founder com perfil inativo** | Conceder `admin` a perfil `disabled` | Recusa fail-closed (`INVALID_FOUNDER`), coerente com `conceder_acesso_role` (`20260908000000:339-346`) e com `resolver_capabilities_efetivas` (`20260910000000:186-187`) |
| T9 | **Role errada por UUID fixo/cópia** | Código resolvendo `admin` por literal e divergindo do catálogo | Resolução **nominal** (`name = 'admin' and is_system = true`), com preflight fail-closed (molde `20260933000000:297-302`) |
| T10 | **Vazamento de erro interno** | Mensagens de Postgres chegando ao cliente | Taxonomia pública fechada (§6.3) via `corpoDeErroEdge`; desconhecido ⇒ `INTERNAL`/`TechnicalError` |
| T11 | **Tabela nova furando o deny-by-default** | Nova tabela com grant/policy indevidos | RLS + zero policies + `revoke all` + `service_role` só `SELECT`/`INSERT` + append-only (§6.4); guardas F4-08 atualizadas (§8) |
| T12 | **Organização órfã/inutilizável** | Tenant criado sem admin operável | A transação só confirma com organização **+** membership **+** atribuição **+** trilha; falha parcial ⇒ rollback total (critério 9) |
| T13 | **Uso do bootstrap como API de autoatendimento** | Transformar o caminho em "criar minha própria conta/organização" | Allowlist de plataforma (não autoatendimento) + `operation_id` obrigatório + auditoria; a UI de provisionamento fica **fora** desta atividade |

---

## 11. Decisões fechadas deste desenho

| # | Decisão | Racional | Alternativa rejeitada |
| --- | --- | --- | --- |
| **D1** | A autoridade de plataforma **não** é `access_role`, **não** é `capability` e **não** é assignment | F4-01 D15/D17 (plano administrativo separado; `admin` por organização; sem SUPER_ADMIN) e `enforce_role_capability_grantable` (`20260910000000:112-151`), que recusaria qualquer capability de controle em role | Criar role de sistema `platform`/`super_admin` — reabriria D17 e criaria objeto atribuível por tenant |
| **D2** | A autoridade de plataforma é resolvida **na fronteira server-side**, reutilizando a allowlist vigente | Simplicidade, fail-closed, mecanismo já implementado e protegido pela invariante 6 da F4-01 (não remover allowlist sem substituto seguro) | Criar uma segunda allowlist só para provisionamento — duplicaria a superfície de configuração sem ganho de segurança |
| **D3** | O bootstrap tem **contenção por construção** (§5.2): só cria tenant novo e vazio | Elimina a necessidade de replicar checagem de autoridade dentro do RPC e mantém o anti-self-escalation do tenant intocado | Replicar `usuario_eh_administrador` dentro do RPC — seria uma segunda fonte de verdade da autoridade administrativa |
| **D4** | O bootstrap reutiliza o **primitivo** `conceder_acesso_role`, não a RPC do plano do tenant | A RPC exige autoridade de `admin` do tenant alvo (circular no nascimento) e proíbe auto-concessão; o primitivo valida membership/perfil/role/tenant e é `EXECUTE` só `service_role` | Reutilizar `conceder_acesso_role_rpc` (impossível) ou escrever um novo caminho de concessão (duplicaria a regra) |
| **D5** | Recusa **fail-closed** da auto-concessão do plano do tenant é **preservada** | F5-04 D15/D16 | Relaxar `20260936000000:88-91` "porque o operador é confiável" — proibido: misturaria os planos |
| **D6** | Idempotência por **replay verificado** de `operation_id` + `payload_hash` (não por criação duplicada, não por simples recusa) | É o que impede duplicação de tenant sem impedir retry legítimo | (a) recusar sempre o replay (operador veria erro após sucesso); (b) ignorar idempotência (risco de tenant duplicado) |
| **D7** | **Uma** tabela nova (`platform_provisioning_events`) como âncora de idempotência e trilha | Evita que o cliente declare identidade: `organizations.id` continua gerado por `gen_random_uuid()` (convenção F1-02) | Deixar o chamador fornecer `organization_id` como chave da operação — viola "identificador técnico gerado pelo banco" e o princípio de que a forma nunca é autoridade |
| **D8** | **Nenhum `SECURITY DEFINER` novo** | `.ai/architecture-rules.md` §1.8 e a guarda `02-validar-f4-08.sql:41` (exatamente 4) | Usar DEFINER "para simplificar" — quebraria o CI e a regra permanente |
| **D9** | **Nenhuma** capability, role, policy ou grant nova de cliente | F4-01 D14/D15 e o princípio de menor privilégio | Conceder `membership.manage` ao `admin` — proibido por D15 (`grantable_via_role = false`) |
| **D10** | Nenhuma mudança em `organizations` (nem coluna `status`, nem unicidade de nome) | O contrato vigente não tem lifecycle de organização (`docs/F5-03-desenho-tecnico.md:217-222`); alterar schema de F2-01 é contrato de outra fase | Adicionar `status`/`unique(name)` para "melhorar" o bootstrap — anteciparia decisão de domínio não tomada |
| **D11** | O founder pode já existir (reuso de perfil) ou ser convidado na hora | Ambos os casos são reais no GREENFIELD F6 (o operador pode ter perfil LEGACY e pode querer testar com uma identidade nova) | Exigir sempre identidade nova — impediria o auto-bootstrap; exigir sempre identidade existente — impediria o tenant com admin novo |
| **D12** | A nomenclatura da variável de allowlist **não** é alterada nesta atividade | Evitar refactor oportunista, mudança de configuração/CI/documentação sem ganho de segurança (`.ai/architecture-rules.md` §3) | Renomear para `PLATFORM_OPERATOR_USER_IDS` — cosmético; registrado como follow-up (§10.4) |
| **D13** | O nome da role `admin` é resolvido **nominalmente**, nunca pelo UUID do catálogo | F4-01 D9 ("nunca por UUID fixo em código") | Literal `c0000000-…-f1` espalhado no SQL |

---

## 12. Dúvidas que exigem decisão do orquestrador

> Somente as três abaixo. As demais foram fechadas em §11 com alternativa rejeitada registrada.

### Q1 — A autoridade de plataforma permanece na allowlist do ambiente, ou passa a ser uma tabela auditável?

- **Alternativas.**
  - **(A) Manter a allowlist `INVITE_ADMIN_USER_IDS`** (recomendada): simplicidade máxima, zero
    mudança de configuração, mecanismo já fail-closed, coerente com F4-01 invariante 6 e com D16.
    Limitação: não há auditoria em banco de quem é operador, nem revogação em runtime (exige
    alteração de secret/redeploy).
  - **(B) Criar `platform_operators`** (tabela dedicada, RLS deny-by-default, `service_role`
    `SELECT`/`INSERT`, trilha de grant/revoke): auditabilidade e revogação em runtime.
    Custo: nova tabela classificada (D16), +1 superfície de autorização de plataforma, mais guardas
    F4-08, e risco de virar embrião do "portal SaaS" que a atividade proíbe.
- **Pergunta:** confirma a alternativa **(A)** para esta atividade, mantendo **(B)** como follow-up
  registrado?

### Q2 — O operador pode ser o próprio primeiro Admin do tenant (auto-bootstrap)?

- **Alternativas.**
  - **(A) Permitir** (recomendada): necessário para o GREENFIELD F6 (organizações de teste isoladas
    criadas e operadas pelo mesmo agente) e para ambiente virgem; a separação de planos (§4) e a
    contenção por construção (§5.2) permanecem.
  - **(B) Exigir duas identidades** (operador ≠ founder): separação de funções mais forte; custo:
    exige provisionar previamente a identidade do founder (que, em ambiente virgem, depende do
    próprio convite administrativo) e inviabiliza o teste GREENFIELD conduzido por um único agente.
- **Pergunta:** confirma **(A)**, ou exige **(B)** (separação de funções obrigatória)?

### Q3 — O caminho pode criar o `user_profiles` do founder quando ausente?

- **Contexto:** o RPC existente `criar_perfil_membership` (`20260906230400:19-35`) insere perfil +
  membership, mas **exige organização existente** — logo é inaplicável ao nascimento do tenant.
- **Alternativas.**
  - **(A) Criar o perfil do founder na mesma transação, quando ausente** (recomendada): é o único
    jeito de um tenant novo ter admin em ambiente virgem; o founder já existe em `auth.users` (FK) e
    o ator é verificado server-side.
  - **(B) Exigir perfil preexistente**: mais conservador (nenhuma escrita nova em `user_profiles`),
    mas torna o bootstrap impossível em ambiente virgem — o founder precisaria ser provisionado por
    um convite, que por sua vez já exige uma organização existente (circular, B1/B2).
- **Pergunta:** confirma **(A)** com o escopo estrito "somente o perfil do founder, somente na
  transação de nascimento do tenant"?

---

## 13. Registros, dívidas e follow-ups (não corrigidos aqui)

> Registrado como memória técnica. **Nada disto vira Issue nem autoriza trabalho** sem decisão
> explícita do orquestrador (`docs/dividas-tecnicas.md:8-12`).

| # | Item | Evidência | Classificação |
| --- | --- | --- | --- |
| F1 | `[functions.gerenciar-access-role]` não declarado em `supabase/config.toml` | `supabase/config.toml:71-104`; Edge existe em `supabase/functions/gerenciar-access-role/index.ts` | **Verificação pendente** — não foi possível confirmar neste ambiente (sem shell/Docker) se o CLI auto-descobre a função sem a declaração; **não** afirmado como defeito |
| F2 | Convite administrativo sem vínculo do chamador com o tenant alvo (G11) | `supabase/functions/convidar-usuario/index.ts:104-110`; `docs/F5-01-desenho-tecnico.md:254` | Dívida já registrada; **fora** do escopo desta atividade |
| F3 | Desativação de usuário é global (sem recorte de tenant) | `supabase/functions/gerenciar-usuario/index.ts:108-141` | Dívida; **fora** do escopo |
| F4 | Ausência de superfície de produto para atribuir roles (B4) | §3 B4 | Limitação material do "primeiro login operacional"; candidata natural à **próxima** atividade da F6 |
| F5 | `user_profiles` do operador de plataforma não tem fluxo de produto | `supabase/validacao/01-cenario-f2-10.sql:156-162` (fixture) | Dependência operacional; consequência direta de **Q1** |
| F6 | Renomear a allowlist para refletir o plano de plataforma | §11 D12 | Follow-up cosmético, **não** necessário para segurança |
| F7 | `organizations` sem lifecycle/status | `docs/F5-03-desenho-tecnico.md:217-222` | Fora de escopo por decisão (§1.2, D10) |
| F8 | Texto da Issue #266 não verificável neste ambiente | §1.3 | Limitação de ambiente registrada |

---

## 14. Autoauditoria deste documento

- [x] **Nenhum código funcional** foi escrito: zero migration, RPC, Edge, capability, role, policy,
      RLS, grant, página, teste ou workflow de CI.
- [x] Toda afirmação sobre o estado atual é **rastreável** a arquivo:linha do repositório.
- [x] **Nenhuma decisão fechada** de contrato (F4/F5) foi reaberta; a relação com F4-01 D9/D16/D17,
      F5-03 §5.5, F5-04 D15/D16 e F5-11 P5.2 está explicitada (§4.3).
- [x] A separação **autoridade de plataforma × role `admin` do tenant** é explícita e tem
      invariantes verificáveis (§4.2).
- [x] Prioridades da atividade endereçadas: simplicidade (§7.1 reuso máximo), segurança (D8/D9,
      §4.2), fail-closed (§6.2/§6.3), isolamento multi-tenant (T3/§9.1.5) e transação/idempotência
      (§5.2/§9.2).
- [x] **Não** expande para portal SaaS, billing ou gestão comercial (§1.2).
- [x] Dúvidas limitadas ao que **realmente** exige decisão do orquestrador (§12, três).
- [x] Números de linha e de contagem citados foram lidos no estado atual da `main` (`52348dd`);
      contagens de guarda foram conferidas em `supabase/validacao/02-validar-f4-08.sql` e
      `03-validar-f4-08-mutacoes.sql`.
- [x] **Não verificável neste ambiente** (registrado, não silenciado): execução de `db reset`, CI,
      Docker e o texto da Issue #266.
