# F4-08 — Desenho técnico: RLS base e isolamento real entre tenants (Issue #95)

> **Status:** desenho técnico da F4-08 **aguardando revisão** — decisões
> **D1–D22 ABERTAS** (recomendação indicada, sem fechamento) e seção
> **"Questões para validação"** (§41). Nenhuma implementação: sem código,
> migration, policy RLS, helper SQL, grant, view, alteração de TypeScript ou
> conexão ao Supabase remoto. A implementação só começa depois que D1–Dn forem
> revisadas/fechadas e o desenho aprovado como contrato técnico.

## 1. Objetivo, princípio e boundary

### 1.1 Objetivo (Issue #95)

Levar a autorização essencial para a **fronteira do banco**: garantir que um
usuário autenticado em uma organização **não consiga ler, inserir, alterar ou
excluir** dados de outra organização — mesmo manipulando o frontend, o
`organizationId` enviado, chamando a API do Supabase diretamente, conhecendo IDs
de outro tenant, alterando filtros ou explorando tabelas filhas/relações
indiretas. Critérios de aceite: usuário de A não lê/escreve dados de B; usuário
sem membership não obtém acesso implícito; policies versionadas em migrations;
service role fora do bundle/frontend; testes RLS positivos/negativos passam.

### 1.2 Princípio central

**Policy Engine e RLS são camadas COMPLEMENTARES**:

- **Policy Engine** decide autorização funcional fina (capability/scope/
  hierarchy/ASSIGNED/temporary/exceptional/pilot/DOMAIN_STATE);
- **RLS** estabelece a **fronteira estrutural** de acesso aos dados por tenant
  (identidade válida, membership válida, isolamento de organização e integridade
  de tenant nas mutações).

Não transformar RLS em duplicação integral do Policy Engine; não depender do
frontend; não depender de `organizationId` fornecido pelo caller como prova de
autorização; não usar cargo/job_role; não criar bypass genérico.

### 1.3 Fora de escopo (Issue #95 e contrato)

policies específicas de entidades funcionais ainda não migradas (localStorage →
F5); produção; observabilidade externa. Esta etapa desenha a **base de RLS**
sobre as tabelas **estruturais/autorizativas já criadas** (F2/F3/F4-01/F4-02).
Também fora: implementação; correção do drift SQL×runtime; F4-07 (gate) e F5.

## 2. Estado atual real (inventário verificado)

- **Supabase local + migrations PostgreSQL** (21 arquivos); `storage`
  desabilitado; `realtime` desabilitado; 2 Edge Functions server-side
  (`convidar-usuario`, `gerenciar-usuario`) com `verify_jwt=false` + allowlist
  `INVITE_ADMIN_USER_IDS` (F2-06/F2-07, transitório — F4-01 D17/Q2).
- **28 tabelas `public.*`**, TODAS com `enable row level security`; **nenhuma
  FORCE**; **nenhuma `disable`**.
- **Policies existentes: apenas 3 (2 arquivos), todas de identidade (F2-03/
  F2-07)**:
  - `user_profiles_select_own` (SELECT, authenticated, `auth.uid() = id AND
    status = 'active'` — após F2-07);
  - `user_organization_memberships_select_own` (SELECT, authenticated,
    `user_profile_id = auth.uid()`);
  - `organizations_select_via_membership` (SELECT, authenticated, `EXISTS`
    membership ativa).
  As demais **25 tabelas não têm policy** → deny-by-default (com os grants de DML
  default do Supabase a `authenticated`/`anon`, SELECT/UPDATE/DELETE afetam zero
  linhas e INSERT é rejeitado).
- **Grants:** `grant select` a `authenticated` somente em `user_profiles`,
  `user_organization_memberships` e `organizations`; nenhum grant de tabela a
  anon; nenhum grant de tabela a service_role nas migrations (service_role
  ignora RLS por definição e é usado apenas server-side).
- **Views:** nenhuma. **Storage:** nenhum uso/migration. **Tipos gerados do
  banco:** nenhum arquivo.
- **Funções SQL:** **31 `public.*`** (11 triggers plpgsql; 13 SQL STABLE de
  resolução F3-07/F3-09/F4-01/F4-02; 5 RPC plpgsql de escrita F2-06/F3-08/
  F3-09; 3 SECURITY DEFINER service_role + `set_updated_at`); **nenhuma usa
  `auth.uid()`** — todas recebem ator por parâmetro (auth.uid() aparece somente
  nas policies). **SECURITY DEFINER (4)** — `criar_perfil_membership` (F2-06),
  `conceder_acesso_role`, `revogar_acesso_role`, `resolver_capabilities_
  efetivas` (F4-01) — todas com EXECUTE **somente service_role** (revoke de
  public/anon/authenticated) e `set search_path = public`. As demais 27 são
  **INVOKER** (default) — o PostgreSQL concede EXECUTE a PUBLIC por padrão às
  funções sem revoke; hoje inertes para authenticated porque INVOKER sob RLS
  deny-by-default (F3-07 documenta isso).
- **Runtime TS:** o único acesso direto a tabelas via supabase-js está em
  `src/auth/adaptadores.ts` (leitura de `user_profiles`,
  `user_organization_memberships`, `organizations` — as 3 tabelas com policy).
  **Nenhum** uso de `service_role`/admin client/`bypassRls` em `src`. Domínios
  funcionais atuais vivem em **localStorage** (pré-F5).
- **Service role:** exclusivo de Edge Functions (Deno runtime,
  `SUPABASE_SERVICE_ROLE_KEY`) com allowlist fail-closed.

## 3. Trust boundary (fonte soberana de tenant)

Análise de dados confiáveis:

| Dado | Confiável? | Papel |
| --- | --- | --- |
| `auth.uid()` (JWT/sessão) | sim | identidade autenticada no Supabase Auth |
| `user_profiles.id` (FK 1:1 auth.users) | sim (se status ativo) | perfil interno |
| `user_organization_memberships` | sim (se status ativo) | **fonte soberana de "quais tenants este usuário pode acessar"** |
| `organizations` | sim (via membership ativa) | entidade-tenant |
| `organization_id` nas linhas | dado, não prova | pertence estruturalmente à linha |
| claims JWT / app_metadata | não (para tenant) | não usado como autorização de tenant |
| metadata do usuário | não | idem |
| parâmetros do cliente (ex.: `organizationId` do request) | **não** | nunca é prova de autorização |
| session | sim (auth) | contém auth.uid |
| service role | sim apenas server-side | nunca no frontend; nunca solução de autorização funcional |

**Fonte soberana:** "quais tenants este usuário pode acessar" deriva de
**identidade autenticada (`auth.uid()`) + membership persistida válida
(`user_organization_memberships.status = 'active'`)** — nunca do frontend.

## 4. Multi-tenant (1 usuário → N memberships)

O schema já suporta múltiplas memberships por user_profile (unique por
(user_profile_id, organization_id)). O desenho **não assume 1 usuário = 1
tenant**. RLS resolve as organizações acessíveis **por linha/por consulta**
através de membership ativa do `auth.uid()` — sem estado global de "tenant
atual" no banco. Cross-tenant é fail-closed (qualquer linha sem membership
válida do caller fica invisível/inacessível).

## 5. Inventário de tabelas (matriz real)

28 tabelas `public.*`, todas com RLS habilitada e **nenhuma policy** exceto as 3
de identidade (F2-03/F2-07). **Visão física verificada (contagem exata por
create block):** 22 tabelas com `organization_id NOT NULL`; 1 com
`organization_id` NULL (`access_roles` — NULL só para roles de sistema); 5 sem
a coluna (`organizations` — a raiz do tenant, `user_profiles`, `capabilities`,
`access_role_capabilities`, `collaborator_status_periods`). Classificação por
domínio (cada tabela em uma categoria; soma = 28):

- **(D) Identidade/tenant (2):** `user_profiles` (global por auth.users),
  `user_organization_memberships` (org NOT NULL — âncora de tenant);
  `organizations` é a **raiz do tenant** (C/raiz).
- **(A) Tenant-rooted DIRETAS estruturais (13):**

| Tabela | Domínio | FK p/ tenant | Policy atual | Ação F4-08 recomendada |
| --- | --- | --- | --- | --- |
| `collaborators` | F3-01 pessoas | própria (org) | nenhuma | SELECT própria-org via helper; INSERT/UPDATE/DELETE sob Policy Engine (função server-side ou policy mínima) |
| `collaborator_identifiers` | F3-01 business codes | própria (org) | nenhuma | idem |
| `job_roles` | F3-02 catálogo (org) | própria | nenhuma | SELECT própria-org |
| `seniority_levels` | F3-02 catálogo (org) | própria | nenhuma | SELECT própria-org |
| `organizational_units` | F3-03 unidades | própria | nenhuma | SELECT própria-org |
| `organizational_unit_parent_periods` | F3-03 hierarquia de unidades | própria | nenhuma | SELECT própria-org |
| `organizational_positions` | F3-03 posições | própria | nenhuma | SELECT própria-org |
| `position_reporting_lines` | F3-04 linhas de reporte | própria | nenhuma | SELECT própria-org |
| `occupations` | F3-05 ocupações | própria | nenhuma | SELECT própria-org |
| `temporary_responsibilities` | F3-06 substituições | própria | nenhuma | SELECT própria-org |
| `collegiate_configurations` | F3-08 config colegiado | própria | nenhuma | SELECT própria-org |
| `collegiate_configuration_members` | F3-08 membros config | própria | nenhuma | SELECT própria-org |
| `cycle_evaluation_responsibilities` | F3-09 responsabilidades | própria | nenhuma | SELECT própria-org (escrita via RPC F3-09) |

- **(B) Tenant-rooted INDIRETA (1):** `collaborator_status_periods` — sem
  `organization_id`; tenant via `collaborators.organization_id` (FK simples
  `collaborator_id`); policy usa EXISTS/JOIN no colaborador do próprio tenant.
- **(C) Raiz do tenant (1):** `organizations` — a própria raiz; policy já
  existente via membership ativa.
- **(D) Identidade (2):** `user_profiles` (global por auth.users) e
  `user_organization_memberships` (org NOT NULL — âncora de tenant).
- **(E) Auditoria/histórico/snapshot (4):** `collegiate_cycle_snapshots`,
  `collegiate_cycle_snapshot_positions`, `collegiate_cycle_snapshot_members`
  (imutáveis) e `evaluation_succession_events` (append-only) — tenant-rooted
  diretas com semântica histórica preservada.
- **(F) Segurança/autorização (7 tabelas F4-01/F4-02):** `capabilities`
  (catálogo global), `access_roles` (system global / custom por org),
  `access_role_capabilities` (sem org; tenant via `access_roles` — NULL =
  system global, org = custom), `membership_access_role_assignments`,
  `membership_collaborator_links`, `access_role_assignment_scopes`,
  `access_role_assignment_unit_targets` — tratadas em §22.

Total: **28** = 13 (A) + 1 (B) + 1 (C) + 2 (D) + 4 (E) + 7 (F). O quadro físico
(22 NOT NULL / 1 nullable / 5 sem coluna) é o que governa a construção das
policies.

## 6. Tabelas filhas e ausência de organization_id

Padrão real atual: praticamente **todas** as tabelas F3/F4 carregam
`organization_id` denormalizado + FKs compostas `(id, organization_id)` — o
schema **já adota o modelo "organization_id redundante de forma consistente"**.
Tabelas sem a coluna: `collaborator_status_periods` (tenant via `collaborators`)
e `access_role_capabilities` (tenant via `access_roles`, podendo ser global p/
role de sistema). Para elas e para futuras tabelas filhas:

- **(A) EXISTS/JOIN na policy** — resolve tenant pela FK do parent;
- **(B) organization_id redundante** — o padrão já usado no schema (segurança
  simples, mas risco de inconsistência e mais colunas);
- **(C) alterar modelagem** — não necessário agora;
- **(D) outra.**

Recomendação preliminar: manter o padrão **B** (já dominante) para novas tabelas
tenant-specific, e usar **A** pontualmente onde um join é inevitável — com
decisão em D5/D6 (comparando segurança × performance × complexidade × risco de
inconsistência × manutenção).

## 7. INSERT (WITH CHECK)

- Impedir usuário de A criar linha com `organization_id` de B: policy de INSERT
  exige `organization_id` = (única) organização autorizada do `auth.uid()` via
  membership ativa (helper) — `WITH CHECK` obrigatório;
- para tabelas filhas, as FKs apontadas (parent) também precisam pertencer ao
  mesmo tenant autorizado (FKs compostas `(id, organization_id)` já ajudam; a
  policy deve verificar o parent no tenant);
- `user_profiles`/`user_organization_memberships`/`organizations`: INSERT **não
  é aberto** a authenticated (criação é via Auth/Edge Function
  `criar_perfil_membership` com service_role);
- INSERT cross-tenant = **DENY** (WITH CHECK rejeita).

## 8. UPDATE (USING × WITH CHECK)

- **USING** (linha-alvo): impede editar linha de outro tenant (mesma condição do
  SELECT);
- **WITH CHECK** (linha-nova): impede pegar linha do próprio tenant e alterar
  `organization_id` para B; impede trocar parent FK para recurso de B; impede
  "mover" entidade entre tenants;
- política fail-closed: UPDATE exige USING e WITH CHECK coerentes; nenhuma
  operação permite mudança de tenant.

## 9. DELETE

- DELETE protegido contra cross-tenant (USING = próprio tenant);
- **RLS de tenant ≠ autorização funcional**: F4-08 garante "nunca cross-tenant";
  se a operação funcional (ex.: excluir ciclo planejado, excluir observação) é
  permitida, continua sendo decisão do **Policy Engine/domínio** na camada de
  serviço — e em F5 por função transacional/server-side, não CRUD direto amplo;
- tabelas append-only/imutáveis (E) não têm DELETE para usuários (decisão em
  D14).

## 10. SELECT

- SELECT impede enumeração cross-tenant (mesma condição por membership ativa);
- riscos registrados: consultas diretas, joins, RPC INVOKER (resolve sob RLS),
  contagens, `EXISTS` por ID, side channels via erro/`NOT_FOUND` — mitigados por
  fail-closed (linha sem membership = invisível; não revela existência além do
  necessário);
- não ampliar escopo além do necessário nesta fase; registrar riscos reais.

## 11. Membership (semântica exata para RLS)

- `status` em `user_organization_memberships`: `'active' | 'disabled'` (domínio
  F2-02, sem 'revoked'); sem datas de validade hoje;
- **válida para RLS = `status = 'active'`**; disabled ⇒ corta acesso
  imediatamente (na resolução por linha);
- profile inválido (`user_profiles.status != 'active'`) ⇒ nada resolve (a
  própria policy de perfil impede leitura e o helper depende do perfil ativo);
- comportamento fail-closed: membership inválida/ausente ⇒ zero linhas; sem
  fallback, sem cache residual (F5 confirma revalidação atômica).

## 12. user_profile × auth.uid()

- `user_profiles.id = auth.users.id` (FK 1:1, RESTRICT) — sem coluna extra;
- estados: `active | disabled`;
- profile inexistente ⇒ nada resolve (helpers falham/retornam vazio ⇒ DENY);
- profile duplicado: impossível por PK/FK 1:1;
- profile inativo ⇒ a própria policy `user_profiles_select_own` já impede e o
  helper de perfil deve exigir `active`;
- qualquer ambiguidade de identidade relevante à segurança ⇒ DENY.

## 13. Helpers SQL propostos (não criar agora; decisão D7/D8)

| Helper | Finalidade | Parâmetros | Retorno | SECURITY | search_path | Recursão | Volatilidade |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `current_user_profile_id()` | resolver perfil ativo do auth.uid | — | uuid ou null | INVOKER | public | consulta user_profiles (policy própria) | STABLE |
| `current_user_organization_ids()` | organizações ativas do auth.uid | — | uuid[] | INVOKER | public | consulta memberships (policy própria) | STABLE |
| `user_has_membership(p_org uuid)` | membership ativa em p_org | uuid | boolean | INVOKER | public | idem | STABLE |
| `is_same_tenant(...)` (opcional) | comparar org da linha com orgs do usuário | variado | boolean | INVOKER | public | usa os acima | STABLE |

Regras: INVOKER por padrão (resolve sob RLS — sem bypass); `set search_path =
public`; **risco de recursão RLS** se a policy de `user_organization_memberships`
consultar helper que consulta memberships — o design evita ciclos (§14); sem
privilege escalation; índices necessários (§30). `SECURITY DEFINER` evitado por
padrão; se indispensável, decisão crítica específica (D9).

## 14. Recursão de RLS

- dependências reais: policy de `organizations` usa `user_organization_
  memberships` (EXISTS) — camada única; policies novas usarão
  `user_organization_memberships` (e `user_profiles`) via helpers INVOKER;
- **ciclo proibido**: `user_organization_memberships`/`user_profiles` **não**
  podem ter policy que consulta tabelas que consultam memberships;
- arquitetura sem ciclos: (1) `user_profiles` policy só usa `auth.uid()`;
  (2) `user_organization_memberships` policy só usa `auth.uid()`; (3) demais
  tabelas usam helpers que leem as duas primeiras — grafo acíclico
  (user_profiles/memberships = folhas). Mapeamento explícito no desenho de
  implementação.

## 15. Policy Engine × RLS (fronteira)

- **RLS garante (mínimo):** identidade válida, membership válida, isolamento de
  tenant, integridade de tenant nas mutações;
- **Policy Engine continua responsável:** capability, scope, hierarchy,
  ASSIGNED, temporary responsibility (F4-05), exceptional access (F4-06), Pilot
  Full Access (F4-07), DOMAIN_STATE e regras funcionais;
- **não portar F4-03..F4-07 para SQL** nesta etapa; RLS não concede capability
  (uma policy só isola tenant, nunca "habilita ação");
- lista de operações que exigem função transacional/server-side (em vez de CRUD
  direto) será documentada na implementação (mutação de estrutura temporal,
  concessões C/D, sucessão F3-09, etc.) — critério de aceite da Issue.

## 16. F4-05 × RLS

Temporary responsibility **não cria membership em outro tenant**, não fura
tenant boundary e opera só no tenant válido (FKs compostas + org na linha).
RLS **não** reproduz a lógica hierárquica F4-05 nesta etapa (não há requisito
estrutural); a fonte runtime (F5) revalidará no servidor.

## 17. F4-06 × RLS

Exceptional access (grant C) **não fura tenant**: grant pertence a um tenant,
beneficiário precisa de identidade/membership válida e target do mesmo tenant.
A persistência futura de grants C (estado + eventos) será protegida por RLS
(leitura restrita a quem tem capability de conceder/auditar; escrita via
função server-side) — **não implementada agora** (não existe persistência ainda).

## 18. F4-07 × RLS

Pilot Full Access (D): continua tenant-scoped e development-only; **não é
bypass de RLS**, não autoriza outro tenant e **não usa service_role para
contornar policies**. D jamais desabilita RLS. Persistência futura de grants D
será protegida por RLS (mesma lógica do §17).

## 19. Service role (inventário real)

- **Uso real:** apenas em **Edge Functions** (`convidar-usuario`,
  `gerenciar-usuario`), via `SUPABASE_SERVICE_ROLE_KEY` injetada pelo runtime
  Deno, com allowlist `INVITE_ADMIN_USER_IDS` fail-closed + perfil ativo do
  chamador; e nas **RPCs DEFINER** (F2-06/F4-01) com EXECUTE service_role;
- **Regra arquitetural:** service role **não** pode ser usado pelo frontend nem
  como solução de autorização funcional; backend futuro legítimo com service
  role terá trust boundary definida (identidade do chamador validada, allowlist
  transitória substituída por capability) — registrado como requisito (F4-01
  D17/Q2);
- nenhuma chave service no cliente TS (verificado).

## 20. anon / authenticated / service_role (grants)

- `anon`: sem grants de tabela (apenas default PUBLIC de EXECUTE em funções
  INVOKER) → com RLS deny-by-default, nada privado legível;
- `authenticated`: SELECT em 3 tabelas de identidade (com policies);
- `service_role`: EXECUTE nas 4 funções DEFINER + ignora RLS (server-side);
- o Supabase concede DML default sobre `public` a anon/authenticated — a
  ausência de policies é o que nega; a F4-08 desenha a combinação
  **GRANT SQL + RLS POLICY** por tabela (leitura via policy; escrita somente
  onde o contrato exige, com WITH CHECK), sem grants amplos novos a
  `authenticated` além do necessário.

## 21. Tabelas globais

- `capabilities` (catálogo global de capabilities — sem dado tenant-specific);
  roles de sistema (`access_roles.is_system` com org NULL);
- justificativa: conteúdo de referência estático compartilhado entre tenants,
  sem dados privados; não forçar organization_id onde não faz sentido;
- acesso: leitura de `capabilities` pode ser aberta a authenticated **somente
  se necessário ao contrato** (ex.: validação de códigos) — decisão D12; nunca
  leitura ampla desnecessária.

## 22. Tabelas de segurança (exposição mínima)

Tabelas F4-01/F4-02 (capabilities, access_roles, access_role_capabilities,
membership_access_role_assignments, membership_collaborator_links,
access_role_assignment_scopes, access_role_assignment_unit_targets):

- **pergunta crítica:** um usuário comum pode consultar essas tabelas
  diretamente? **Não** por padrão — membership de tenant **não** implica ler
  configuração de segurança;
- exposição mínima: leitura apenas por funções/policies restritas a quem tem a
  capability correspondente (resolver de capabilities efetivas já é service_role
  DEFINER e deve continuar sem exposição a authenticated até policy dedicada);
- escrita exclusivamente via RPCs transacionais (conceder/revogar_acesso_role) —
  nunca CRUD direto;
- decisão D13 (nível de exposição por tabela de segurança).

## 23. Auditoria

- eventos de auditoria existentes no banco: `evaluation_succession_events`
  (append-only, autor+motivo); futuros grants/uso C (F4-06) e D (F4-07) e
  trilhas por entidade (localStorage hoje);
- requisitos RLS: **quem pode inserir** — função server-side confiável (RPC/
  backend), nunca CRUD de authenticated; **quem pode ler** — auditoria/gestão
  com capability específica (não todo membro); **alterar/excluir** — proibido
  para authenticated (append-only; sem apagar trilha pelo autor);
- tenant ownership da auditoria: events com organization_id (F3-09) →
  isolamento preservado; futuras trilhas C/D idem;
- necessidade futura de backend confiável para escrita/leitura de auditoria
  (decisão D14/Q7).

## 24. Histórico / snapshots (F3-08/F3-09)

- snapshots e eventos permanecem **soberanos**; RLS protege tenant **sem**
  alterar semântica histórica;
- políticas: **somente leitura** para `collegiate_cycle_snapshots(+positions/
  +members)` (imutáveis) dentro do tenant; `evaluation_succession_events` sem
  UPDATE/DELETE; escrita apenas pelas RPCs materiais (F3-08/09) que devem ser
  reavaliadas quanto a exposição (hoje INVOKER/PUBLIC) — decisão D11;
- membership **não** é permissão de reescrever história (nenhuma policy de
  UPDATE/DELETE em tabelas E para authenticated).

## 25. Organization (policy da própria tabela)

- SELECT da própria organização (via membership ativa) — já existente
  (`organizations_select_via_membership`);
- SELECT de outras organizações — negado;
- UPDATE/DELETE em `organizations` — negados para authenticated (somente
  server-side/admin com decisão explícita);
- separar visibilidade (SELECT) de administração (UPDATE/DELETE).

## 26. IDs não são segredo

UUID/IDs assumidos como não-secretos: conhecer o ID de outro tenant **nunca** é
suficiente (policy sempre resolve por membership). Teste conceitual: acesso
direto por ID de B ⇒ zero linhas.

## 27. Views

Nenhuma view existe hoje. Regra futura (quando houver): `security_invoker = on`
(herda RLS das tabelas-base), owner não-esquecido, `security_barrier` quando
necessário; view nunca herda comportamento automaticamente.

## 28. RPC / functions (inventário)

31 funções `public.*`; **nenhuma usa `auth.uid()`** (todas recebem o ator por
parâmetro; as DEFINER são chamadas por service_role, onde auth.uid() é nulo).
Resumo do risco por função (INVOKER resolve sob RLS):

- **F3-07 resolvers** (`organizacao_resolver_*`, 7× sql STABLE INVOKER): leem
  `occupations`/`temporary_responsibilities`/`position_reporting_lines`/
  `organizational_positions` **sem filtrar organization_id** e sem checar auth —
  hoje inertes (RLS deny); ao criar policies, tornam-se restritos ao tenant do
  caller (INVOKER) — comportamento desejado, mas a superfície RPC (EXECUTE
  default PUBLIC) precisa de reavaliação (D11);
- **F3-08/09**: `materializar_colegiado_ciclo` e `materializar_responsabilidades
  _avaliacao` são tenant-safe por `p_organization_id`; `resolver_responsavel_
  avaliacao_vigente` filtra por org; **`registrar_sucessao_avaliador` NÃO tem
  parâmetro de org** (keyed por responsibility id) — cross-tenant se chamada sem
  filtro; hoje contida por RLS deny; exige revoke de EXECUTE de authenticated/
  anon e chamada por caminho autorizado (D11/D7);
- **F4-02 resolvers** (`resolver_collaborador_vinculado`,
  `resolver_capabilities_escopos_efetivas` — aceitam qualquer user_profile_id —
  e `resolver_alvos_escopo`, cujos branches ORGANIZATIONAL_UNIT/ORGANIZATION
  **não validam membership do chamador**): INVOKER; sob RLS restringem-se ao
  tenant do caller, mas a exposição RPC deve ser mínima (D13);
- **DEFINER (4)** service_role-only (com search_path public): sem acesso de
  authenticated; nunca ampliar EXECUTE (`criar_perfil_membership` e
  `resolver_capabilities_efetivas` rodam sem RLS sobre dados de qualquer org);
- **Triggers (11, INVOKER):** 2 sem `set search_path` explícito
  (`enforce_membership_role_within_organization`,
  `enforce_unit_target_scope_type` — corpos qualificam `public.`; ganhar `set`
  por consistência). Riscos: triggers de integridade F3-04/05/06 fazem
  `select ... into` sem `FOUND` check — se o writer não enxergar a linha lida
  sob RLS futura, a validação pode passar silenciosamente (D9: avaliar DEFINER
  nos triggers de integridade ou garantir visibilidade do writer);
- regra: qualquer RPC capaz de acessar dados cross-tenant é **crítico** — com
  INVOKER + RLS fica restrita ao tenant do caller; DEFINER só com decisão
  explícita e revoke de EXECUTE para authenticated/anon (padrão já adotado).

## 29. Storage

Sem uso real de Supabase Storage (config desabilitado, nenhuma migration/
bucket). **Fora de escopo** da F4-08; se entrar no futuro (arquivos vinculados a
entidades tenant-specific), policies de `storage.objects` entram em decisão
própria.

## 30. Performance e índices

Classificação (não implementar):

- **obrigatórios para a F4-08:** índice em `user_organization_memberships
  (user_profile_id, organization_id)` [existente via unique], e em
  `(organization_id)` nas principais tabelas tenant-rooted usadas em policies/
  EXISTS; índice em `user_profiles(id, status)` (cobertura da policy);
- **recomendados:** índices para FKs compostas usadas em joins de policy
  (`(id, organization_id)`) e para `status` nas tabelas com filtro de estado;
- **futuros:** conforme consultas reais.

## 31. Estratégia de migration (ordem segura, sem "big bang")

Ordem recomendada (adaptada ao schema real de 28 tabelas), evitando janela em
que "RLS sem policy" ou "policy sem RLS" deixe lacuna:

1. **Fundação/helpers** (INVOKER, acíclicos — §13/§14) em migration própria;
2. **Identidade:** reforçar policies de `user_profiles`/`user_organization_
   memberships`/`organizations` (se necessário);
3. **Tenant roots funcionais** (colaboradores, catálogos org, unidades/posições,
   reporting lines, occupations, temporary_responsibilities): policy de SELECT
   própria-org;
4. **Tabelas filhas/indiretas** (`access_role_capabilities` etc.);
5. **Tabelas de segurança** (F4-01/F4-02) com exposição mínima;
6. **Auditoria/histórico/snapshot** (somente leitura/inserção via RPC);
7. **Views/RPC** (reavaliação de exposição INVOKER);
8. **Testes cross-tenant** (positivos/negativos).

Cada migration entrega o par "ENABLE + policy" na mesma transação, com testes
entre fases; nunca deixar tabela com RLS habilitada sem policy intencional na
fase final (deny-by-default é o estado seguro durante a migração).

## 32. Fail-closed durante a migração

Padrão por tabela: (1) `alter table ... enable row level security`; (2) criação
de helpers antes (migration de fundação); (3) `create policy` para cada comando
autorizado; (4) grants mínimos; (5) índices; opcional `FORCE`. A **ordem em
transação** é: helpers → ENABLE → policies → grants → índices. Durante a
migração, deny-by-default (RLS sem policy) **não abre** acesso; policies só são
criadas depois que helpers existem. Testes negativos rodam antes de políticas
para confirmar bloqueio.

## 33. FORCE ROW LEVEL SECURITY

Avaliação: `FORCE RLS` faz a RLS valer mesmo para o owner da tabela. Nos padrões
atuais (owner = postgres/roda migrations; nenhum backend autenticado como
owner), **FORCE não é necessário hoje**, mas é **registrado como decisão** (D10)
para: tabelas de segurança/auditoria (defesa em profundidade se um processo
server-side rodar como owner) e para impedir que um backend futuro rode como
owner contornando policies; migrações/seed continuam via papel que deve poder
escrever (caminho definido na implementação).

## 34. Convenção de nomenclatura de policies

```
<tabela>_select_same_tenant
<tabela>_insert_same_tenant
<tabela>_update_same_tenant
<tabela>_delete_same_tenant
```
(ex.: `collaborators_select_same_tenant`, `occupations_select_same_tenant`,
`evaluation_succession_events_insert_via_rpc`). Policies auditáveis e fáceis de
localizar por tabela/comando.

## 35. Estratégia de testes de segurança

Níveis (sem conectar Supabase remoto):

- **(A) testes SQL/policy**: cenários psql (padrão `supabase/validacao`) que
  autenticam como usuários sintéticos (roles/cliente com `request.jwt.claims`)
  e tentam SELECT/INSERT/UPDATE/DELETE cross-tenant;
- **(B) integração local Supabase** — a infraestrutura real do repo existe:
  pares `supabase/validacao/01-cenario-*.sql` (cenário sintético, inserido como
  superuser local/equivalente a service_role) + `02-validar-*.sql` (runner com
  `set role authenticated` provando deny-by-default; F2-10 usa runner `.mjs`
  com `@supabase/supabase-js` e chaves locais de `supabase status -o env`),
  executados via `npx --yes supabase@2.116.0` + `docker exec ... psql` no
  container `supabase_db_feedback-control`;
- **(C) testes do app** (TS) para identidade/resolução (sem UI);
- **(D) testes negativos cross-tenant** explícitos (novos runners por fase RLS).

## 36. Matriz mínima de testes futuros (40 itens da Issue + extras)

1. usuário A lê linha tenant A;
2. usuário A não lê linha tenant B;
3. ID direto de B → sem acesso;
4. usuário A não insere organization_id B;
5. usuário A não altera organization_id A→B;
6. usuário A não troca parent FK para parent B;
7. usuário A não atualiza linha B;
8. usuário A não exclui linha B;
9. membership inativa → sem acesso;
10. profile inválido → sem acesso;
11. auth.uid sem profile → sem acesso;
12. múltiplas memberships válidas → somente tenants correspondentes;
13. child sem org (access_role_capabilities) → isolamento via role/parent;
14. join não vaza B;
15. count não revela B;
16. view não vaza B (futuro; hoje sem views);
17. RPC INVOKER não vaza B (sob RLS);
18. INSERT child com parent B → DENY;
19. UPDATE child A→parent B → DENY;
20. temporary responsibility não fura tenant;
21. exceptional access (grant C) não fura tenant;
22. Pilot Full Access (D) não fura tenant;
23. caller organizationId manipulado não muda acesso;
24. organization própria visível conforme contrato;
25. outra organization invisível;
26. tabela global (capabilities) funciona conforme contrato;
27. security table não fica aberta apenas por membership;
28. audit log não pode ser alterado;
29. audit log não pode ser apagado;
30. histórico não pode ser reescrito por simples membership;
31. anon não acessa dados privados;
32. authenticated sem membership não acessa tenant;
33. service role não aparece no cliente (bundle);
34. policy recursion não ocorre (grafo acíclico);
35. policy com dados incompletos falha fechada;
36. tenant null em tabela tenant-specific → comportamento seguro (fail-closed);
37. FK órfã/inconsistente → sem acesso;
38. capability funcional continua dependente do Policy Engine;
39. RLS não concede capability;
40. tentativa de bypass via filtro/cliente direto falha.

## 37. Threat model

| Ameaça | Mitigação | Risco residual | Teste |
| --- | --- | --- | --- |
| Usuário autenticado malicioso | RLS por membership ativa | médio-baixo (config admin do próprio tenant continua Policy Engine) | 1,2 |
| Manipulação do frontend | servidor/RLS decide | baixo | 23,40 |
| API Supabase direta | RLS deny-by-default | baixo | 4,7 |
| IDOR por ID conhecido | policy por membership, não por ID | baixo | 3 |
| Cross-tenant INSERT | WITH CHECK | baixo | 4,18 |
| Cross-tenant UPDATE (mudar org/parent FK) | USING + WITH CHECK | baixo | 5,6,19 |
| FK poisoning | FKs compostas + policy do parent | baixo-médio | 18,19,37 |
| RPC bypass (INVOKER sem RLS) | INVOKER resolve sob RLS; revisão de exposição | médio (funções F3 hoje PUBLIC) | 17 |
| View bypass | security_invoker futura; hoje sem views | baixo | 16 |
| SECURITY DEFINER mal configurado | só service_role + revoke; decisão D9 | baixo | 33 |
| search_path attack | `set search_path = public` em todas | baixo | lint SQL |
| Service role vazada | nunca no bundle; allowlist fail-closed | médio | 33, CI/CodeQL |
| Policy recursion | grafo acíclico (§14) | baixo | 34 |
| Tabela esquecida sem RLS | checklist + teste de schema | médio (hoje todas com RLS) | §38 |
| Nova tabela futura sem RLS | regra de engenharia (§38) | médio | teste schema |
| Nova FK que cria caminho cross-tenant | revisão de FKs em PR/CI | baixo | 37 |

## 38. Novas tabelas futuras (regra de engenharia)

Regra: **nenhuma nova tabela tenant-specific entra sem decisão explícita de
RLS**. Mecanismos de prevenção a comparar (decisão D16): checklist obrigatório
em PR; teste automatizado de schema que verifica "tabela tenant-specific tem
ENABLE RLS + policy SELECT própria-org"; catálogo de tabelas tenant-specific;
lint/test SQL no CI. Recomendação preliminar: teste de schema + checklist.

## 39. Riscos e dependências

- **Riscos:** policy mal escrita abre tenant; helpers recursivos; função INVOKER
  hoje PUBLIC vira vetor se tabela base ganhar RLS incorreta; escrita ampla em
  tabelas F3 por membro do tenant (mitigado: RLS isola tenant; Policy Engine/
  função transacional decide a operação); performance de EXISTS em tabelas
  grandes (índices §30); drift futuro.
- **Dependências:** F2 (identidade/membership), F3-01..F3-09 (tabelas), F4-01/
  F4-02 (segurança), F4-03..F4-07 (Policy Engine/origens — complementares),
  Supabase local + `supabase/validacao` (testes), F5 (domínios funcionais).

## 40. Decisões arquiteturais (D1–D22 — ABERTAS)

> Nenhuma decisão é aprovada automaticamente. Cada uma: problema, alternativas,
> recomendação, justificativa, riscos, impacto, dependências.

- **D1 — Fonte soberana de tenant no RLS:** membership ativa por auth.uid
  (recomendada) vs claims JWT vs parâmetro. Recomendação: membership persistida
  ativa; claims/metadata não usados. Justificativa: revogação imediata, sem
  dependência de token. Riscos: custo de consulta por linha (mitigado por
  helper/índice).
- **D2 — Escopo das tabelas na F4-08:** somente as 28 criadas (estruturais/
  autorizativas) vs incluir previsão para domínios futuros F5. Recomendação:
  somente as atuais + regra de engenharia (§38).
- **D3 — Modelo org direto vs indireto:** manter denormalização org (padrão
  atual) para novas tabelas (recomendada) vs EXISTS/JOIN. Comparar segurança,
  performance, complexidade, risco de inconsistência, manutenção.
- **D4 — Helpers INVOKER e naming:** `current_user_profile_id()`,
  `current_user_organization_ids()`, `user_has_membership(uuid)` (recomendados),
  INVOKER, STABLE, search_path public; validar não-recursão e índices.
- **D5 — SELECT nas tabelas F3 (tenant roots):** policy `select_same_tenant`
  para todas (recomendada) vs subset. Impacto: leitura da estrutura por
  membros; coerente com scopes do Policy Engine na camada de serviço.
- **D6 — child/indirect (`access_role_capabilities`):** policy com EXISTS na
  role (custom própria-org OU system) — recomendação preliminar; sem alterar
  modelagem.
- **D7 — INSERT/UPDATE/DELETE em F3:** manter RLS somente-isolamento + escrita
  via função transacional/PG (recomendada) vs policies de escrita amplas.
  Nunca cross-tenant; operação funcional continua no Policy Engine.
- **D8 — Mutação de identidade/orgs:** nenhuma escrita de authenticated em
  user_profiles/organizations/user_organization_memberships (recomendada);
  criação/desativação via Auth/Edge Function (service_role) e RPC.
- **D9 — SECURITY DEFINER:** nenhum novo (recomendado); se indispensável,
  decisão crítica específica com revoke + search_path.
- **D10 — FORCE RLS:** registrar escopo (tabelas de segurança/auditoria em
  defesa em profundidade?) — recomendação: avaliar por grupo, sem aplicar
  cegamente; não necessário hoje.
- **D11 — Funções INVOKER hoje PUBLIC (F3 resolvers/RPC):** revisar exposição —
  revoke de EXECUTE a PUBLIC/authenticated com exceções explícitas (recomendado)
  vs manter. Impacto: caminhos de serviço futuros.
- **D12 — Tabela global `capabilities`:** leitura a authenticated? Recomendação:
  sim somente se o contrato exigir (validação de códigos) com policy dedicada;
  caso contrário, negada.
- **D13 — Tabelas de segurança (F4-01/F4-02):** exposição mínima (nenhuma leitura
  por membership comum; escrita só via RPC service_role; resolver de capabilities
  permanece DEFINER service_role) — recomendada.
- **D14 — Auditoria (E):** leitura restrita a capability de auditoria; INSERT via
  RPC confiável; sem UPDATE/DELETE de authenticated; decisão sobre quem lê
  `evaluation_succession_events`.
- **D15 — Histórico/snapshot:** somente leitura própria-org; escrita exclusiva
  das RPCs materiais (com reavaliação de exposição); sem reescrita por
  membership.
- **D16 — Novas tabelas futuras:** teste de schema + checklist (recomendado);
  alternativas: catálogo de tabelas, lint SQL no CI.
- **D17 — Grants:** manter SELECT a authenticated só em identidade + adicionar
  grants mínimos por policy; sem grants amplos novos (recomendado).
- **D18 — Granularidade de policy:** por comando (SELECT/INSERT/UPDATE/DELETE)
  em vez de policy única ampla — recomendada.
- **D19 — Views/RPC futuros:** `security_invoker=on` obrigatório em views
  futuras; RPC INVOKER por padrão — recomendada.
- **D20 — Estratégia de testes:** SQL/policy local (A) + integração local (B) +
  negativos (D) — recomendada; sem Supabase remoto.
- **D21 — Sequenciamento de migration:** fases por grupo (§31) com deny-by-default
  intermediário e testes por fase — recomendada; sem big bang.
- **D22 — F4-05/06/07 persistencias futuras:** grants C/D protegidos por RLS
  (leitura restrita, escrita via função) quando persistirem — registrar requisito;
  não implementar agora.

## 41. Questões para validação (Q1–Q8)

- **Q1 — Escopo real da F4-08:** a Issue pede policies nas "tabelas
  estruturais/autorizativas criadas até esta fase" — confirmar se as tabelas
  funcionais F3 (colaboradores/estrutura/ciclos) entram integralmente nesta
  fase ou se F4-08 cobre apenas identidade+segurança com leitura mínima.
  Impacto: D2/D5.
- **Q2 — Operações que exigem função transacional:** confirmar a lista de
  mutações que nunca serão CRUD direto (estrutura temporal F3, sucessão F3-09,
  concessões C/D, configuração de ciclo) para documentar na implementação.
- **Q3 — Escrita em tabelas F3 via policy vs RPC:** quando os domínios migrarem
  (F5), mutações virão por função server-side ou por CRUD com policy? Define o
  desenho D7.
- **Q4 — Leitura de estrutura F3 por membro do tenant:** qualquer membro ativo
  pode ler a árvore/estrutura do próprio tenant (para o futuro resolver
  hierarquia) ou isso deve respeitar scopes? Hoje o resolver usa parâmetro de
  resolução; confirmar se a política base é "tenant" (recomendado) com
  capacidade na camada de serviço.
- **Q5 — Auditoria legível por quem:** trilha de sucessão F3-09 (e futuras C/D)
  deve ser legível por gestão com capability ou por backend confiável apenas?
  Define D14.
- **Q6 — Edge Functions/allowlist:** confirmar que as funções
  `convidar-usuario`/`gerenciar-usuario` (service_role + allowlist) permanecem
  o caminho transitório de administração até a capability substituir a
  allowlist (F4-01 Q2) — sem vínculo soberano.
- **Q7 — Capabilities globais legíveis:** o frontend precisará ler o catálogo
  `capabilities` diretamente (validação/UI) ou sempre via resolver? Define D12.
- **Q8 — FORCE RLS:** existe plano de rodar processos server-side como owner da
  tabela no futuro (justificando FORCE)? Define D10.

## 42. Resumo para revisão

Para fechar como contrato da F4-08, a revisão deve fechar **D1–D22** e
responder **Q1–Q8**. Após o fechamento, a implementação futura entregará:
helpers INVOKER acíclicos (fundação), policies por comando
(`<tabela>_<cmd>_same_tenant`) nas 28 tabelas conforme a matriz real, grants
mínimos, reavaliação de exposição das funções INVOKER/DEFINER, decisão de FORCE,
índices, testes SQL/policy locais positivos e negativos e o sequenciamento
fail-closed por fases — tudo em migrations versionadas, sem service role no
cliente e sem alterar a semântica do Policy Engine (camadas complementares).

**Confirmação:** nenhum código, migration, policy RLS, helper, grant, view ou
alteração de TypeScript foi produzido nesta atividade — somente este documento.
