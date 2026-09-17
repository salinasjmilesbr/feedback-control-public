# F6-A11 — Completar o bootstrap funcional do primeiro Admin GREENFIELD (desenho técnico curto)

> **Status:** desenho **FECHADO — pronto para implementação** — decisões **D22–D30 FECHADAS** neste
> documento (§3) e **Q4–Q6 FECHADAS na alternativa A** (§8), conforme a revisão da **PR #274**.
> **Atividade:** F6-A11 — Issue **#273**.
> **Base:** `main` = `ba04dfd` (`fix(F6-A09): restaura o boot das Edges…` **#272** integrado;
> `feat(F6-A04)…` **#269** em `0982359`).
> **Emenda:** `docs/F6-A03-desenho-tecnico.md` (D1–D21 e Q1–Q3 **FECHADAS**). Este documento **não
> reabre** decisão alguma da F6-A03; amplia o passo funcional do mesmo bootstrap.
> **Natureza:** documento de desenho. **Zero** arquivo de código, SQL, CI ou teste alterado aqui.
> **Evidência de origem:** auditoria F6-A08 (READ-ONLY) — o tenant GREENFIELD nasce com
> `collaborators = 0` e `membership_collaborator_links = 0`, e o primeiro Admin recebe
> `FORBIDDEN` em `collaborator.listar` mesmo possuindo `collaborator.read`.

## 1. Objetivo e não-escopo

### 1.1 Objetivo

Fazer o bootstrap GREENFIELD terminar com o primeiro Admin **funcionalmente ancorado** no próprio
tenant: organização + perfil + membership ativa + atribuição da role `admin` (**já funciona** —
F6-A03) **mais** o colaborador correspondente ao founder e o **vínculo F5-02 ativos**, criados na
**mesma transação** e pelo **mesmo caminho soberano** (Edge `provisionar-organizacao` → RPC
`organizacao_provisionar_inicial`).

Critério funcional da Issue: depois de criar a organização, o primeiro Admin possui sua âncora
funcional soberana e entra no domínio funcional conforme suas capabilities, **sem** depender de
fixtures nem da simulação DEV.

### 1.2 Não-escopo (explícito)

| Fora de escopo | Motivo |
| --- | --- |
| F6-A08 / remoção da contaminação da simulação DEV | Determinado pela Issue #273 (§Fora de escopo) |
| Redesign de autenticação, Policy Engine, roles ou RLS | Idem; qualquer mudança aí reabriria decisão fechada |
| Look & Feel da tela de login | Idem |
| Exceção de autorização para o Admin, ou contorno de `membership_collaborator_links` | Issue #273 §5: proibido |
| Estrutura organizacional do founder (unidade, cargo, posição, colegiado, reporting line) | **Não** é dado mínimo: a projeção soberana devolve `NULL` para ausência de estrutura, nunca erro (`20260913000000:406` e `LEFT JOIN`s `:494-510`) |
| Portal SaaS, listagem de tenants, lifecycle de organização, gestão de operadores/roles | F6-A03 **D21**; `docs/F5-03-desenho-tecnico.md:217-222` (organização sem lifecycle) |
| Backfill/migração de tenants já provisionados | Ver **D27** e **D30** — a remediação é organização nova, não backfill |
| Tabela `platform_operators` e a nomenclatura da allowlist | F6-A03 **D14**/**D12** (follow-ups registrados) |

## 2. Estado atual auditado (evidência arquivo:linha)

### 2.1 Onde vive (e onde NÃO vive) o nome humano — modelo existente

| Peça | Estado real | Evidência |
| --- | --- | --- |
| `user_profiles` | **Não tem coluna de nome**: `id, status, created_at, updated_at, version`. É identidade global 1:1 com `auth.users` | `supabase/migrations/20260906201856_organizations_user_profiles.sql:90-101,103-108` |
| `collaborators.full_name` | **Já é o "nome canônico da pessoa"**, `not null`, `check (full_name <> '' and full_name = btrim(full_name))` | `docs/F5-07-desenho-tecnico.md:351,361,366` |
| `auth.users.email` | Credencial/identificador de autenticação (PK da identidade) | `20260906201856:97-99` (FK de `user_profiles.id`) |
| `organizations.name` | Fonte **única** do nome da organização | Issue #273 §Requisito de UX/identidade; `20260937000000:260-261` |
| Metadados de Auth como fonte de nome | **Não existem**: o convite administrativo não grava metadados de nome | `supabase/functions/convidar-usuario/index.ts:113` (`inviteUserByEmail(email)`, sem `data`) |
| Consumidor do nome | Projeção soberana já devolve `full_name` do colaborador | `20260913000000:414-429,481` |

### 2.2 Vínculo F5-02 — primitivos existentes e reusáveis

| Peça | Papel | Evidência |
| --- | --- | --- |
| `resolver_collaborator_vinculado(profile, org)` | Leitura soberana do vínculo (perfil ativo + membership ativa + link ativo) | `20260909000000_f5_02_hardening_resolver_collaborador.sql:22-43` |
| `vincular_colaborador(membership, collaborator)` | **Criação canônica** do vínculo `active`: valida mesmo tenant, 1 link ativo por membership (Q6=B) e 1 por colaborador/organização (Q3=B) | `20260909020000_f5_02_link_mutation_functions.sql:29-93` |
| `desativar_vinculo_colaborador` / `trocar_vinculo_colaborador` | Mutação de vínculo atômica (histórico preservado) | idem `:98-187` |
| Fronteira | Todas `SECURITY INVOKER`; `EXECUTE` **somente** `service_role` | idem `:8-11,192-198` |

### 2.3 Criação canônica de colaborador — o que já existe e o que ela exige

`colaborador_criar(p_organization_id, p_actor_user_profile_id, p_operation_id, p_full_name,
p_email, p_matricula, p_admission_date, p_status_inicial)` — `SECURITY INVOKER`,
`EXECUTE` somente `service_role` (`20260913010000_f5_07_collaborators_rpc.sql:34-47,1863`):

- **exige** `operation_id`, `full_name` não vazio, `email` com `@`, **`matrícula` não vazia**
  (`:67-81`) e valida **matrícula única na organização em qualquer vigência** e **e-mail único**
  (`:113-131`);
- **revalida o ator no banco**: `colaborador_ator_valido(actor, org)` = perfil ativo **e**
  membership ativa **na organização** (`:86-88`; `20260913000000:367-389`);
- grava, na mesma transação: `collaborators` + `collaborator_identifiers` (**linha ABERTA**) +
  `collaborator_status_periods` + evento **`ADMISSAO`** (`:142-171`);
- o evento exige **`actor_user_profile_id` E `actor_membership_id` `NOT NULL`**, com FK composta
  `(actor_membership_id, organization_id) → user_organization_memberships`
  (`20260913000000:230-231,251-254`) e unicidade `(organization_id, operation_id)` (`:257-258`).

Contrato de operação correspondente: `docs/F5-07-desenho-tecnico.md:504` (efeitos) e `:540`
(matrícula normalizada e única).

### 2.4 Bootstrap atual — o que já faz e o que falta

`organizacao_provisionar_inicial(operation_id, organization_name, founder_user_profile_id,
actor_user_profile_id)` (`20260937000000:147-157`): `SECURITY INVOKER` (`:155`), `search_path`
fixo, `EXECUTE` somente `service_role` (`:335-338`), hash SHA-256 da intenção derivado
**server-side** (`:181-185`), idempotência por replay **antes** de qualquer validação de estado
(`:211-247`), organização nova (`:260-261`), `user_profiles` do founder/ator (`:266-275`),
membership ativa do founder (`:279-284`), `conceder_acesso_role` pelo **primitivo** e trilha de
auditoria (`:286-297`), guarda final fail-closed (`:299-317`).

**Falta exatamente o passo funcional:** nenhum `INSERT` em `collaborators` nem em
`membership_collaborator_links` (estado real do banco auditado na F6-A08: 1 organização
GREENFIELD, membership ativa, role `admin` com `collaborator.read`, **0 colaboradores, 0 links**).

### 2.5 Superfície de produto já existente (o que este desenho estende)

| Peça | Estado | Evidência |
| --- | --- | --- |
| Contrato transportável (allowlist estrita) | chaves `operacao, operation_id, organization_name, founder_user_id, founder_email` | `src/infrastructure/supabase/plataforma/contrato.ts:48-57` |
| Intenção de entrada | `founderUserId` **ou** `founderEmail` (XOR) | `contrato.ts:96-108,151-181` |
| Conversão pura do formulário | `montarEntradaProvisao` (fail-closed) | `src/services/plataforma/formularioPlataforma.ts:19-59` |
| Porta da aplicação | `NovaOrganizacaoPlataforma` | `src/application/ports/ProvisionamentoPlataforma.ts:20-33` |
| UI mínima | estados verificando/negado/formulário/concluído; não exibe identificadores internos | `src/pages/plataforma/NovaOrganizacaoPlataformaPage.tsx:15-38` |
| Edge | revalida operador, reconhece replay, convida founder **por e-mail**, executa a RPC, compensa best-effort | `supabase/functions/provisionar-organizacao/index.ts:63-159` |
| E-mail do founder já resolvido server-side | `admin.auth.admin.getUserById(founder)` | `index.ts:95-101` |

### 2.6 A circularidade que torna o bootstrap o ÚNICO caminho

`collaborator.criar` e `collaborator.listar` são operações **funcionais sem alvo explícito**: a
âncora autorizável é o **colaborador vinculado do próprio ator**
(`supabase/functions/colaboradores/core.ts:461-464,499-503`) e, sem âncora, a decisão é
`{ permitido: false, code: "FORBIDDEN" }` **antes** de consultar o Policy Engine (`:624-636`).

Consequência direta para o desenho: **não existe caminho de produto** pelo qual o primeiro Admin
crie o próprio colaborador depois de o tenant nascer. Qualquer tentativa seria (a) uma exceção de
autorização — proibida pela Issue §5 — ou (b) um segundo bootstrap fora do provisionamento. Logo,
o colaborador do founder **tem** de nascer no bootstrap.

## 3. Decisões fechadas deste desenho

> Numeração continua a série do contrato de plataforma da **F6-A03** (D1–D21), que este documento
> emenda. Alternativas consideradas são registradas em cada decisão.

### D22 — A fonte canônica do nome humano do primeiro Admin é `collaborators.full_name` (por tenant)

- **Decisão:** o nome humano capturado no provisionamento vive **exclusivamente** em
  `collaborators.full_name` do colaborador do founder na organização criada. `auth.users.email`
  continua credencial/identificador de autenticação; `user_profiles` continua identidade global
  **sem** nome; `organizations.name` continua a **única** fonte do nome da organização.
- **Fundamento:** é o campo que o modelo existente já define como "nome canônico da pessoa"
  (`docs/F5-07-desenho-tecnico.md:351,361`) e o que a projeção soberana já devolve
  (`20260913000000:481`). Criar coluna de nome em `user_profiles` seria campo novo **redundante**
  (a Issue pede explicitamente para evitar) e criaria **duas** fontes de nome no produto.
- **Consequência assumida:** o nome é **por organização** (uma linha de colaborador por tenant) —
  comportamento do modelo vigente (F5-07 D2/D3). **Não** há nome global de pessoa no produto, e
  este desenho **não** o introduz.
- **Alternativas rejeitadas:** (a) coluna `full_name`/`display_name` em `user_profiles` — campo
  novo redundante e segunda fonte de verdade; (b) `auth.users.raw_user_meta_data` — hoje o convite
  não grava metadados (`convidar-usuario/index.ts:113`), seria fonte paralela e não auditável pelo
  domínio; (c) duplicar o nome da organização em perfil/membership/colaborador — proibido pela
  Issue.

### D23 — Dados mínimos do colaborador inicial

| Campo | Valor | Origem | Fundamento |
| --- | --- | --- | --- |
| `organization_id` | a organização criada **na mesma transação** | server-side (nunca do corpo) | F6-A03 D3/D7 (`:260-261`) |
| `full_name` | nome humano do primeiro Admin | **novo parâmetro** validado (trim, não vazio) | **D22**; check da tabela (`F5-07:366`) |
| `email` | e-mail da **identidade autenticada** do founder | **resolvido server-side** pela Edge e revalidado pela RPC (`@`, não vazio) | obrigatório em `colaborador_criar:73-75`; nunca um segundo e-mail vindo do corpo |
| `matricula` (`business_code`) | matrícula declarada do founder na nova organização | **novo parâmetro** informado no formulário (ver **D26**/**D28**) | **obrigatória** no contrato canônico (`:76-78`; `F5-07:504,540`) |
| `admission_date` | `NULL` | — | não inventar data; a vigência de identificador/status/evento inicia em `now()` (`:62-64`) |
| `status_inicial` | `'active'` | default canônico | `:54,151-152` |
| Estrutura (ocupação/cargo/unidade/colegiado) | **nenhuma** | — | **não-escopo** §1.2; ausência ⇒ `NULL` na projeção (`:406,494-510`) |

**Efeitos canônicos do passo (todos criados pelo primitivo, na mesma transação):**
`collaborators` + `collaborator_identifiers` (linha ABERTA) + `collaborator_status_periods` +
evento `ADMISSAO` (`colaborador_criar:142-171`).

### D24 — Criação e vínculo F5-02 **atômicos**, por primitivos existentes, na mesma transação do bootstrap

**Sequência final de `organizacao_provisionar_inicial`** (preserva integralmente os passos
auditados da F6-A03 e apenas **acrescenta** ao final, antes da guarda fail-closed):

```text
(1)…(5)  forma → hash da intenção → gate de plataforma → role nominal → IDEMPOTÊNCIA/replay
(6)…(8)  founder/at/validações → organização nova → user_profiles (founder, ator)
(9)      membership ATIVA do founder                     → v_membership
(10)(11) conceder_acesso_role (primitivo F4-01) + trilha privilege_mutation_audit
(11.1)   NOVO: public.colaborador_criar(org, founder, operation_id,
                                         full_name, email_resolvido, matricula, NULL, NULL)
                                         → v_collaborator            [primitivo F5-07]
(11.2)   NOVO: public.vincular_colaborador(v_membership, v_collaborator)  [primitivo F5-02 D9]
(12)     guarda final fail-closed AMPLIADA: + colaborador ativo + vínculo ATIVO da membership
```

- **Reuso, não recópia** (precedente **D4** da F6-A03): o colaborador nasce pelo primitivo
  canônico `colaborador_criar` e o vínculo pelo primitivo canônico `vincular_colaborador` — **zero**
  duplicação de regra (matrícula/e-mail únicos, evento, hash, unicidade do vínculo) e **zero**
  `INSERT` direto em `membership_collaborator_links` (Issue §5).
- **Ator do evento `ADMISSAO` = o próprio founder.** `collaborator_events.actor_membership_id` é
  `NOT NULL` com FK composta **para a organização** (`20260913000000:230-231,251-254`) e, por
  desenho (F6-A03 §4/D21), **apenas o founder recebe membership no tenant novo** — logo o founder
  é o **único** ator FK-válido. `colaborador_ator_valido(founder, org)` torna-se verdadeiro
  imediatamente após o passo (9) (`:86-88,367-389`). A **autoria do ATO DE PLATAFORMA** permanece
  com o **operador** em `platform_provisioning_events.actor_user_profile_id`
  (`20260937000000:104-108`) e em `privilege_mutation_audit` — D17/D18 preservados.
- **Atomicidade:** tudo numa única transação da RPC; falha em qualquer passo ⇒ rollback total (sem
  tenant meio-criado, sem colaborador órfão, sem vínculo parcial).
- **Precedência da idempotência:** o replay continua resolvido **antes** de qualquer escrita
  (F6-A03 §5 e correção pós-auditoria `fef69fc`) ⇒ reexecutar a mesma intenção **não** cria um
  segundo colaborador, identificador, evento ou vínculo.
- **Sem exceção de autorização:** o bootstrap não cria capability, role, policy nem grant (D8/D9);
  as operações funcionais do Admin continuam decididas pelo Policy Engine sobre a âncora F5-02
  recém-criada.
- **Alternativas rejeitadas:** (a) `colaborador_criar` com `p_actor = operador` — **impossível**:
  o operador não tem membership no tenant novo (`colaborador_ator_valido` reprova;
  `:86-88`); (b) passar `actor_membership_id` do founder com `actor_user_profile_id` do operador —
  atribuição **falsa** (a FK não verifica a correspondência perfil↔membership); (c) tornar
  `actor_membership_id` anulável ou criar tipo de evento `BOOTSTRAP` — reabriria o contrato
  congelado dos eventos ("exatamente as 4 FKs do contrato congelado", `20260913000000:235`);
  (d) `INSERT` direto no vínculo — proibido pela Issue §5.

### D25 — Assinatura e idempotência: dois/três parâmetros novos, hash ampliado e **DROP explícito** da assinatura antiga

- **Nova assinatura** (parâmetros novos **no fim**, preservando as quatro posições atuais):

```text
organizacao_provisionar_inicial(
  p_operation_id uuid, p_organization_name text,
  p_founder_user_profile_id uuid, p_actor_user_profile_id uuid,
  p_founder_full_name text, p_founder_matricula text, p_founder_email text
) returns uuid
```

- **`DROP` obrigatório da assinatura antiga** na mesma migration: `create or replace` com lista de
  parâmetros diferente **cria sobrecarga**, não substitui — deixar as duas versões vivas manteria
  um caminho de bootstrap **sem** a âncora funcional:

```sql
drop function if exists public.organizacao_provisionar_inicial(uuid, text, uuid, uuid);
```

- **Hash canônico ampliado:** o SHA-256 server-side (`:181-185`) passa a cobrir
  `founder_full_name`, `founder_matricula` e o e-mail resolvido ⇒ retry **divergente** é recusado
  fail-closed; retry **idêntico** continua replay estável e sem efeito.
- **Ordem preservada:** forma → hash → gate → role → **idempotência** → validações de estado →
  escritas (§5 da F6-A03).
- **E-mail resolvido pela Edge, nunca pelo corpo:** a Edge passa a resolver
  `admin.auth.admin.getUserById(founderUserId).email` **depois** de a identidade existir (padrão já
  usado em `operacaoAplicada`, `index.ts:95-101`) e envia como parâmetro; a RPC valida não
  vazio/`@` e recusa fail-closed. Isso evita um segundo e-mail declarado pelo cliente e mantém a
  regra "o corpo carrega apenas INTENÇÃO" (`contrato.ts:9-18`).
- **Inventário obrigatório de atualização da assinatura** (regprocedure/campos):
  `supabase/migrations/20260937000000_…sql` (comentário `:323`, `revoke`/`grant` `:335-338`,
  guarda interna `:373`), `supabase/validacao/45-validar-f6-a03.sql:71` **e as 12 chamadas**
  (`:148,191,205,219,233,247,289,386,410,465,481,548`), `supabase/validacao/44-cenario-f6-a03.sql`
  (chamadas do cenário), Edge `provisionar-organizacao/index.ts:134-139`, comentários de
  `supabase/config.toml:110` e `supabase/migrations/README.md:63`.
- **Nota de rastreabilidade:** `docs/F6-A03-desenho-tecnico.md` **permanece** como registro
  histórico da assinatura original; a assinatura vigente passa a ser a desta §D25.

### D26 — Impacto no formulário de criação da organização (menor superfície possível)

| Camada | Mudança | Observação |
| --- | --- | --- |
| `src/infrastructure/supabase/plataforma/contrato.ts` | allowlist estrita ganha `founder_full_name` e `founder_matricula`; `EntradaProvisaoPlataforma` ganha os 2 campos; validação de forma (trim, não vazio) reusando a **taxonomia fechada** (`INVALID_NAME` para o nome, `INVALID_FOUNDER` para a matrícula) | **nenhum código público novo**; `founder_email` continua sendo a **identificação** do Admin (convite), não o e-mail do colaborador |
| `src/services/plataforma/formularioPlataforma.ts` | `EntradaMontagem`/`MotivoMontagem` ganham os 2 campos/motivos; `montarEntradaProvisao` continua fail-closed | lógica pura, testável sem DOM |
| `src/application/ports/ProvisionamentoPlataforma.ts` | `NovaOrganizacaoPlataforma` ganha os 2 campos | intenção, **nunca** autoridade |
| `src/pages/plataforma/NovaOrganizacaoPlataformaPage.tsx` | 2 campos rotulados ("Nome do primeiro Admin", "Matrícula do primeiro Admin"), mesmos estados e mesmas barreiras | continua **sem** decidir autorização, **sem** exibir identificadores internos e **sem** storage local |
| Edge `provisionar-organizacao` | passa os 3 parâmetros novos (2 do corpo + e-mail resolvido server-side) | `operadorAutorizado`, replay e compensação **inalterados** |

**Nada mais muda:** nenhuma rota, guard de rota, navegação funcional, Policy Engine, RLS, policy,
grant, capability ou role. O formulário continua sendo **intenção**; a decisão permanece na Edge +
RPC.

### D27 — Compatibilidade com tenants e bootstraps já existentes

- **Trilha append-only não é reescrita (D18):** nenhum `UPDATE`/`DELETE` em
  `platform_provisioning_events`; nenhum backfill silencioso; nenhuma nova coluna nessa tabela
  (ver **D29**).
- **Replay de intenção registrada ANTES desta mudança:** o hash recalculado (com os campos novos)
  diverge do registrado ⇒ **recusa fail-closed** (`F6_A03_CONFLICT`), sem qualquer efeito. É o
  comportamento desejado: divergência de intenção **nunca** passa em silêncio.
- **Tenant GREENFIELD já criado e incompleto** (o caso auditado: 1 organização, 0 colaboradores,
  0 vínculos) **não** é retro-completado por replay; a remediação é provisionar uma organização
  **nova** pelo fluxo completo (**D30**). Não há lifecycle de organização (D10; `docs/F5-03:217-222`),
  então o tenant antigo permanece válido e vazio — sem perda de dado e sem efeito colateral.
- **Tenants/bootstrap que já tenham colaborador + vínculo:** **nenhuma** migração de dados; a
  mudança é aditiva e restrita ao caminho do bootstrap.
- **Idempotência preservada:** `operation_id` continua a chave única da âncora; a unicidade
  `(organization_id, operation_id)` de `collaborator_events` (`:257-258`) permanece como segunda
  barreira contra duplicação do evento `ADMISSAO`.
- **Contratos preservados:** `SECURITY INVOKER` (nenhum `SECURITY DEFINER` novo — guarda F4-08 com
  exatamente 4, `supabase/validacao/02-validar-f4-08.sql:42-44`), `EXECUTE` somente `service_role`,
  RLS/policies/grants de cliente inalterados, catálogo com 31 capabilities e bundle `admin` com 9
  funcionais intactos (`20260937000000:397-418`).

### D28 — A matrícula do primeiro Admin é **campo obrigatório** do formulário de plataforma (Q4 = A)

- **Decisão:** o formulário mínimo de plataforma passa a coletar a **matrícula** do primeiro Admin
  (`founder_matricula`), validada por **forma** (trim, não vazia) e transportada como **intenção** —
  exatamente como o `full_name` (D26). Ela é o `business_code` da linha **aberta** de
  `collaborator_identifiers` criada pelo primitivo canônico (`colaborador_criar:147-149`).
- **Fundamento:** o contrato F5-07 **exige** matrícula na criação do colaborador (`:76-78`;
  `docs/F5-07:504,540`) e a define como código de negócio **declarado**, nunca inventado (F5-07
  **D2**). Em tenant recém-nascido a matrícula é livre por construção; a unicidade
  `(organization_id, business_code)` (`20260907103100:164-165`) permanece como backstop do banco.
- **Consequência de UI:** **dois** campos novos na tela de plataforma (nome e matrícula); **nenhum**
  código público novo (a taxonomia fechada é reutilizada — `INVALID_FOUNDER` para matrícula
  inválida); nenhuma alteração de rota, guard ou autorização.
- **Alternativas rejeitadas:** (a) derivar a matrícula server-side (ex.: parte local do e-mail) —
  **inventaria** identidade de negócio, contra F5-07 **D2**; (b) criar o colaborador **sem**
  matrícula — exigiria um caminho de criação paralelo ao primitivo canônico (duplicação de regra);
  (c) deixar a matrícula para definição posterior pelo próprio Admin — **inalcançável**: sem âncora
  funcional o Admin não executa operação funcional alguma (§2.6).

### D29 — A trilha `platform_provisioning_events` **não** ganha coluna do colaborador criado (Q5 = A)

- **Decisão:** nenhuma coluna nova na trilha de plataforma; o colaborador do primeiro Admin
  permanece **derivável** pelo vínculo ativo da membership do founder
  (`membership_collaborator_links` → `collaborators`), sem duplicar um UUID **imutável** em registro
  append-only.
- **Fundamento:** o precedente do `organization_name` na trilha (`20260937000000:71,100-102`) existe
  porque o nome da organização é **mutável** e a trilha o congela como *snapshot*; o UUID do
  colaborador não muda e não precisa de snapshot. Evita ainda alterar tabela e validador da F6-A03
  sem necessidade (menor superfície).
- **Alternativa registrada como follow-up reversível:** coluna aditiva e anulável
  `founder_collaborator_id` (trilha auto-contida), caso a auditoria futura a prefira — **não**
  adotada agora, sem reabrir nenhuma decisão da F6-A03.

### D30 — O tenant GREENFIELD já provisionado e incompleto é remediado por **organização nova** (Q6 = A)

- **Decisão:** a remediação do tenant incompleto (auditado na F6-A08: 1 organização, 0
  colaboradores, 0 vínculos) é **provisionar uma organização nova** pelo fluxo completo
  (D22–D29). O tenant antigo **permanece válido e vazio**: não há lifecycle de organização (D10;
  `docs/F5-03:217-222`) e **nenhum** backfill, replay forçado ou reescrita de trilha é executado
  (D27).
- **Fundamento:** preserva o **escopo fechado** do plano de plataforma (F6-A03 **D21**: exatamente
  duas operações) e o caráter **aditivo** da mudança; o tenant de teste não carrega dado de negócio,
  e a trilha append-only continua sendo o registro fiel do que cada operação criou.
- **Alternativas rejeitadas nesta atividade (follow-up reversível, exige decisão explícita do
  orquestrador):** (a) nova operação de plataforma "completar bootstrap" — ampliaria **D21** e
  criaria uma segunda porta de escrita no plano de plataforma; (b) procedimento administrativo único
  pelo proprietário, fora do produto — não auditável pela trilha de provisionamento.

## 4. Invariantes preservados (inegociáveis na implementação)

1. **Autoridade server-side:** o corpo continua carregando apenas intenção; `auth.uid()` continua a
   raiz de identidade; a allowlist de plataforma continua sendo a autoridade do provisionamento
   (F6-A03 D2/D14).
2. **Fail-closed:** qualquer elo ausente (perfil, membership, matrícula, e-mail, role, vínculo)
   ⇒ erro + rollback; nunca tenant/colaborador parcial.
3. **Tenant isolation:** o colaborador e o vínculo são criados **na organização nascida na mesma
   transação**; `vincular_colaborador` mantém as checagens explícitas de mesmo tenant e as
   unicidades parciais como backstop.
4. **RLS/grants:** nenhuma policy, grant ou privilégio de cliente novo; as tabelas continuam
   deny-by-default para `authenticated`/`anon`.
5. **Autoria e trilha:** autoria do ato de plataforma = operador; trilha funcional do `ADMISSAO`
   atribuída à membership do founder (**D24**); trilhas append-only preservadas.
6. **Sem exceção de autorização para o Admin:** nenhuma capability/role/policy/rota nova; a
   autorização funcional continua exigindo a âncora F5-02 e o Policy Engine.
7. **Fonte única de nome:** nome da organização em `organizations.name`; nome humano do Admin em
   `collaborators.full_name`; nenhuma cópia redundante (D22).

## 5. Critérios de aceite (para a implementação)

1. Após o bootstrap, existe **1** colaborador do founder (`active`), **1** identificador **aberto**,
   **1** período de status, **1** evento `ADMISSAO` (ator = membership do founder) e **1** vínculo
   F5-02 **ativo** — todos criados na **mesma transação** da RPC.
2. `collaborator.listar` e `collaborator.criar` deixam de responder `FORBIDDEN` ao primeiro Admin
   (a âncora resolve) — critério funcional da Issue.
3. Replay da **mesma** intenção ⇒ mesmo `organization_id`, **zero** linhas novas (nenhum segundo
   colaborador, identificador, evento ou vínculo).
4. Intenção **divergente** com o mesmo `operation_id` ⇒ recusa fail-closed, sem efeito.
5. Falha em qualquer passo (perfil ausente/inativo, membership ausente, matrícula/e-mail inválidos,
   role ausente, vínculo já existente) ⇒ **rollback total**.
6. Nenhum `SECURITY DEFINER` novo (exatamente 4); `EXECUTE` da RPC somente `service_role`;
   `authenticated`/`anon` não executam; zero policy na trilha de plataforma.
7. Catálogo **31** capabilities e bundle `admin` com **9** funcionais intactos; nenhuma role ou
   capability nova.
8. Formulário fail-closed sem nome/matrícula; nenhuma chave fora da allowlist é aceita; a UI não
   exibe identificadores internos e não decide autorização.
9. Nenhuma reescrita da trilha de provisionamento e nenhum dado existente alterado.

## 6. Estratégia de testes e validação (da implementação — não desta atividade)

| Camada | O que cobre |
| --- | --- |
| SQL — cenário `supabase/validacao/44-cenario-f6-a03.sql` | caminho feliz completo: organização + perfil + membership + role + **colaborador + identificador aberto + status + evento `ADMISSAO` + vínculo ativo** |
| SQL — validador `supabase/validacao/45-validar-f6-a03.sql` | assinatura nova (regprocedure), `INVOKER`/`search_path`/`EXECUTE` só `service_role`, replay sem duplicação, recusa por divergência, rollback fail-closed, invariantes 31/9, RLS zero-policy, **ausência de `INSERT` direto no vínculo** |
| SQL — cross-tenant | `vincular_colaborador` com colaborador de outra organização ⇒ erro; bootstrap nunca toca tenant preexistente |
| Vitest | `src/infrastructure/supabase/plataforma/edgeProvisionamento.test.ts` (chaves/hash/intenção) e `src/services/plataforma/formularioPlataforma.test.ts` (fail-closed dos campos novos); guarda estática da allowlist estrita |
| Runtime local | probe da Edge + jornada real do produto (criar organização ⇒ `colaborador.listar` sem `FORBIDDEN`) |
| Gates | `npm test`, `npm run build`, `npm run lint`, `git diff --check` e os validadores SQL aplicáveis |

## 7. Inventário de arquivos impactados (para a atividade de implementação)

| Arquivo | Mudança |
| --- | --- |
| `supabase/migrations/<timestamp>_f6_a11_bootstrap_funcional_admin.sql` (**nova**) | `drop function` da assinatura antiga + `create or replace` da RPC com os passos (11.1)/(11.2) e guarda ampliada |
| `supabase/validacao/44-cenario-f6-a03.sql` / `45-validar-f6-a03.sql` | assinatura nova, chamadas e novos blocos de aceite |
| `supabase/migrations/README.md` | entrada da migration F6-A11 |
| `supabase/functions/provisionar-organizacao/index.ts` (+ `core.ts` se a intenção mudar) | e-mail resolvido server-side + 3 parâmetros novos |
| `src/infrastructure/supabase/plataforma/contrato.ts` | allowlist, tipo e validação (2 chaves novas) |
| `src/services/plataforma/formularioPlataforma.ts`, `src/application/ports/ProvisionamentoPlataforma.ts`, `src/pages/plataforma/NovaOrganizacaoPlataformaPage.tsx`, `src/infrastructure/supabase/plataforma/edgePlataforma.ts` | campos novos e transporte |
| Testes correspondentes | `edgeProvisionamento.test.ts`, `formularioPlataforma.test.ts` (+ guarda estática) |

## 8. Q4–Q6 — **FECHADAS (alternativa A)** na revisão da PR #274

| # | Pergunta | Resposta | Decisão e consequências |
| --- | --- | --- | --- |
| **Q4** | Qual a origem da **matrícula** do primeiro Admin, dado que o contrato canônico a exige (`F5-07:504,540`)? | **A — campo obrigatório no formulário de plataforma** | **D28** — dois campos novos na UI de plataforma (nome + matrícula); **nenhum** código público novo; a matrícula segue código de negócio **declarado** (F5-07 **D2**) e a unicidade por organização permanece no banco como backstop |
| **Q5** | Registrar o `founder_collaborator_id` na trilha `platform_provisioning_events`? | **A — não registrar** | **D29** — trilha e validador da F6-A03 **intocados**; o colaborador é derivável pelo vínculo ativo da membership do founder; a alternativa "trilha auto-contida" fica como follow-up reversível |
| **Q6** | Como remediar o tenant GREENFIELD **já** provisionado e incompleto (auditoria F6-A08)? | **A — provisionar organização nova pelo fluxo completo** | **D30** — o tenant antigo permanece válido e vazio; **nenhum** backfill ou replay forçado; o escopo fechado **D21** é preservado; "completar bootstrap" e procedimento administrativo ficam como follow-up reversível |

**Nenhuma dúvida permanece aberta** nesta atividade. O contrato F6-A11 está **FECHADO** (D22–D30) e
autoriza a implementação, que é atividade/branch própria e é ela que **encerra a Issue #273**.

## 9. Autoauditoria deste documento

- [x] **Natureza respeitada:** nenhum arquivo de código, SQL, CI ou teste alterado nesta atividade.
- [x] **D22 fecha** a fonte canônica do nome com base no modelo **existente** (sem campo novo).
- [x] **D23 fecha** os dados mínimos do colaborador inicial, com a exigência de matrícula
  justificada pelo contrato canônico e **ratificada em D28** (Q4 = A).
- [x] **D24 fecha** criação + vínculo **atômicos** na mesma transação, por primitivos existentes,
  sem `INSERT` direto no vínculo e sem exceção de autorização.
- [x] **D25 fecha** assinatura/idempotência, incluindo o **`DROP` explícito** (sobrecarga) e o
  inventário de chamadas da assinatura.
- [x] **D26 fecha** o impacto no formulário (menor superfície, taxonomia fechada, zero código novo).
- [x] **D27 fecha** a compatibilidade (replay, trilha append-only, tenants existentes, aditividade).
- [x] **D28–D30 fecham Q4–Q6 na alternativa A** (matrícula como campo obrigatório do formulário;
  trilha de plataforma sem coluna nova; remediação do tenant incompleto por organização nova),
  conforme a revisão da **PR #274** — com as alternativas B/C registradas como follow-up reversível.
- [x] **Invariantes** de autorização, RLS, tenant isolation, autoria e fail-closed explicitados (§4).
- [x] **Nenhuma decisão fechada da F6-A03/F5-02/F5-07 é reaberta**; as alternativas rejeitadas estão
  registradas com o motivo.
- [x] **Não há redesign:** o desenho usa o modelo, os primitivos e a superfície existentes.
