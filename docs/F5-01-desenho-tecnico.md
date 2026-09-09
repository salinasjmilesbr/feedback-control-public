# F5-01 — Contrato de Identidade Autenticada (raiz de confiança da Fase 5)

> Documento de desenho técnico — **etapa de auditoria e desenho, sem código funcional**.
> Estado: **contrato da F5-01 FECHADO para revisão** — questões Q1–Q5 APROVADAS e
> decisões D1–D14 FECHADAS (revisão registrada no PR #159). A implementação do
> contrato (tipos, controlador/guard, testes) é atividade separada e posterior.
>
> Fase: 5 — Identidade e Multiusuário · Atividade: F5-01 · Complexidade: Alta · Risco: Alto

---

## 1. Objetivo

Definir o contrato arquitetural da **identidade autenticada** do Virtus: a raiz de
confiança a partir da qual a Fase 5 integrará usuários reais à arquitetura já
consolidada das Fases 3 (estrutura organizacional) e 4 (autorização/segurança).

A F5-01 responde, no nível de contrato:

1. qual é a **fonte soberana** da identidade do usuário autenticado;
2. como `auth.uid()` e a sessão do provedor (Supabase Auth) entram no runtime;
3. qual é o papel de `user_profile` e o que ele pode/não pode fornecer;
4. como tratar os estados anômalos de identidade/sessão (sem perfil, perfil
   inativo, inconsistente, sessão inexistente/inválida/expirada, usuário
   removido/desabilitado, falhas de carregamento);
5. o que é dado confiável de servidor/banco e o que é apenas informação
   apresentada pelo cliente;
6. quais identificadores o frontend pode transportar sem virar fonte de
   autoridade;
7. como garantir **fail-closed** em inicialização, refresh, restauração,
   mudança de usuário, logout e erros;
8. qual é a fronteira entre `AuthIdentity`, `user_profile`, `membership`,
   `colaborador` e `ActorContext`.

**Princípio de fase:** a Fase 5 *integra* usuários reais à arquitetura existente
das Fases 3/4 — **não reconstrói a autorização**. O Policy Engine permanece o
gate soberano; `authorize()` é enforcement; `can()` serve à UX; capability =
ação; nenhuma autorização runtime por cargo/job_role/função; tenant mismatch =
DENY; fail-closed; contexto do cliente nunca é fonte soberana de identidade ou
tenant; ADMIN não é superuser de conteúdo; SELF/hierarquia/ASSIGNED/C/D e
RLS F4-08 continuam válidos (ver §12).

### 1.1 O que a F5-01 entrega

- Inventário verificado do estado atual de identidade/autenticação no código;
- gaps (G1–G11) entre o estado atual e o contrato necessário;
- fronteiras de confiança e modelo conceitual (camadas de identidade);
- fontes soberanas × não soberanas;
- fluxo-alvo de resolução da identidade e máquina de estados da sessão;
- regras fail-closed para cada fase do ciclo de vida;
- contratos/interfaces necessários **para as próximas atividades F5-02 a F5-05**,
  sem resolvê-los aqui;
- impacto esperado no código, estratégia de implementação e de testes;
- critérios de aceite, fora de escopo, riscos, decisões (D1–D14) e questões
  para validação (Q1–Q5 — fechadas/aprovadas).

### 1.2 Limites com as próximas atividades (não antecipar)

| Atividade futura | Assunto | O que a F5-01 faz | O que a F5-01 **não** faz |
| --- | --- | --- | --- |
| F5-02 | Vínculo usuário autenticado ↔ colaborador | Define que o vínculo é **por membership** (1 membership → ≤1 colaborador) e que o `colaborador` nunca identifica a conta de acesso | Não cria o fluxo de vínculo nem o consome |
| F5-03 | Membership e organização ativa | Define que `memberships` ativas são resolvidas integralmente; com N>1 exige **seleção explícita** antes do uso funcional (Q4 aprovada) e nenhuma escolha vira autoridade (é intenção validada no servidor) | Não implementa switcher/“organização ativa”, persistência da escolha nem UX de seleção |
| F5-04 | Access roles e capabilities | Define que a capability efetiva é derivada de membership → access_role → capability (já modelado no banco F4-01/F4-02) e que o binding DEV-only é transitório | Não cria o runtime de roles/capabilities |
| F5-05 | ActorContext | Define que o `ActorRef` do Policy Engine em runtime real é derivado da identidade resolvida (nunca da UI) | Não cria o ActorContext |

---

## 2. Estado atual encontrado no código (inventário verificado)

> Inventário feito por leitura direta dos arquivos citados; os números são do
> estado atual da branch `main`. Não há implementação nesta atividade.

### 2.1 Mapa dos módulos relevantes

**Autenticação/identidade — `src/auth/` (produzido na F2-03 a F2-09):**

| Arquivo | Papel |
| --- | --- |
| `contratos.ts` | Portas `Autenticador` e `RepositorioIdentidade`; tipo `EventoMudancaSessao` |
| `tipos.ts` | `UsuarioAuth`, `SessaoAuth`, `PerfilAutenticado`, `MembershipAutenticada`, `OrganizacaoResolvida`, `IdentidadeResolvida` |
| `erros.ts` | Mapeamento para taxonomia F0-05 (`applicationErrors`) |
| `servico.ts` | Camada pura: `entrar`, `sair`, `obterSessaoInicial`, recuperação/redefinição de senha, `resolverIdentidade` |
| `adaptadores.ts` | Adapters sobre `@supabase/supabase-js` (auth + leitura de `user_profiles`, `user_organization_memberships`, `organizations`) |
| `cliente.ts` | Fábrica do cliente Supabase de auth (persistSession/autoRefresh/detectSessionInUrl) |
| `controladorSessao.ts` | Máquina de sessão pura: `verificando/naoAutenticado/autenticado/acessoNegado/indisponivel/sessaoExpirada` |
| `politicaSessao.ts` | Política F2-08: inatividade 60 min; duração máxima 1 dia; intervalo de revalidação 60 s |
| `armazenamentoSessao.ts` | Marcador local do início de sessão (`virtus.auth.inicioSessao`, por userId) — metadado, nunca credencial |
| `AuthProvider.tsx` / `AuthContext.tsx` | Provider React que orquestra o controlador e expõe `estado`, `entrar`, `sair`, `solicitarRecuperacaoDeSenha`, `redefinirSenha`, `convidarUsuario`, `reconhecerExpiracao` |
| `rotasProtegidas.ts` / `LayoutAutenticado.tsx` | Guard de rotas funcionais (F2-04): carregando → nada; autenticado → permitir; senão → `/login` |
| `LoginPage`, `RecuperarSenhaPage`, `RedefinirSenhaPage`, `ConvidarUsuarioPage` | Fluxos de UI de autenticação/convite |
| `AuthStatus.tsx` | Estado de sessão no cabeçalho (e-mail exibido + Sair) |

**Identidade simulada de DEV — `src/contexts/` e `src/components/`:**

| Arquivo | Papel |
| --- | --- |
| `UsuarioAtualProvider.tsx` / `UsuarioAtualContext.tsx` | Contexto de **impersonação DEV** (F2-09): colaborador sintético “atual” sobre o seed local |
| `impersonacaoDev.ts` | Lógica pura da impersonação DEV; chave `feedback-control-usuario-atual`; candidatos = `Colaborador` ativo do `localStorage` |
| `UsuarioAtualBar.tsx` | Barra do usuário: `AuthStatus` real + seletor de impersonação DEV (somente DEV) |
| `App.tsx` | `BrandingProvider` → `AuthProvider` → `UsuarioAtualProvider` → rotas |

**Autorização (F4) que consome/condiciona identidade — `src/authorization/`:**

| Arquivo | Papel |
| --- | --- |
| `policyEngine/types.ts` | `ActorRef { actorId, organizationId }`, `AuthorizationRequest`, providers (`IdentityProvider`, `CapabilityProvider`, `ScopeProvider`, `TargetProvider`, `RelationProvider`, origens B/C/D) |
| `policyEngine/policyEngine.ts` | Engine: 1 identidade → 2 profile → 3 membership → 4 tenant → 5 capability … (fail-closed) |
| `mundoFuncional.ts` | Mundo local **pré-F5**: providers derivados dos dados do seed (`gestorDiretoMatricula`, colegiado); `LOCAL_ORGANIZATION_ID = "organizacao-sintetica-local"`; binding DEV-only de capabilities; `isMembershipActive: () => true` |
| `autorizacaoFuncional.ts` | Facade F4-09: `autorizar`/`pode`/`alvosPermitidos` com actor = `Colaborador` (actorId = `String(matricula)`) |
| `authorizationPolicy.ts` | Adaptador de compatibilidade: traduz capability + resource em requisição do engine; ator resolvido por matrícula na lista local |
| `AuthorizationContext.ts` | `AuthorizationContext { actor: { matricula, funcao?, status } }` — montado pelas páginas a partir do `usuarioAtual` DEV |
| `exceptionalAccess.ts` / `pilotAccess.ts` + `providers/*` | Origens C (F4-06) e D (F4-07): beneficiário/outorgante = `userProfileId` (**sem exigir colaborador**) |

**Configuração e infraestrutura:**

| Arquivo | Papel |
| --- | --- |
| `src/config/ambiente.ts` (+ README) | Único leitor de `import.meta.env`; `simulacaoDevPermitida` (gate único da impersonação DEV) |
| `src/infrastructure/supabase/supabaseClient.ts` | Cliente F1-04 com auth **desligado**; **sem consumidores hoje** |
| `src/auth/cliente.ts` | Cliente F2-03 de auth (usado pelo `AuthProvider`) — **segunda fábrica de cliente** |

**Banco/RLS (migrations) — identidade e tenant:**

| Migration | Papel |
| --- | --- |
| `20260906185540_foundation.sql` | Fundação (F1-03) |
| `20260906201856_organizations_user_profiles.sql` | `organizations` + `user_profiles` (1:1 com `auth.users`, `status active/disabled`, RLS deny-by-default) (F2-01) |
| `20260906203358_user_organization_memberships.sql` | `user_organization_memberships` (unique por par usuário/organização; F2-02) |
| `20260906205425_auth_read_policies.sql` | Policies mínimas de leitura da própria identidade (F2-03) |
| `20260906230400_criar_perfil_membership_rpc.sql` | RPC `criar_perfil_membership` (SECURITY DEFINER; EXECUTE só service_role) (F2-06) |
| `20260907000250_desativacao_perfil_policy.sql` | `user_profiles_select_own` passa a exigir `status='active'` (F2-07) |
| `20260908000000_authorization_capabilities_access_roles.sql` | Catálogo F4-01 (capabilities/access_roles/assignments) |
| `20260908000001_authorization_system_catalog.sql` | Catálogo de sistema F4-01 |
| `20260908010000_authorization_scopes_membership_collaborator.sql` | Scopes F4-02; **`membership_collaborator_links`** + `resolver_collaborador_vinculado` (base do vínculo membership→colaborador); RLS deny-by-default |
| `20260908100000_f4_08_helpers_function_grants.sql` | Helper único `user_has_active_membership(org)` (profile ativo + membership ativa via `auth.uid()`) + revokes/grants das funções INVOKER |
| `20260908110000_f4_08_rls_select_own_tenant.sql` | Policies SELECT own-tenant das tabelas estruturais F3 (F4-08) |
| `20260908130000_f4_08_hardening.sql` | Hardening: tenant correlation, FOUND checks, `search_path` |
| `20260908140000_f4_08_revoke_excess_table_privileges.sql` | Least privilege |
| `20260908150000_f4_08_organizations_profile_active.sql` | `organizations` legível só com profile ativo + membership ativa |

**Edge Functions (server-side):** `supabase/functions/convidar-usuario/index.ts`
(F2-06) e `gerenciar-usuario/index.ts` (F2-07) — usam `SUPABASE_SERVICE_ROLE_KEY`
e, como autorização provisória, **allowlist** `INVITE_ADMIN_USER_IDS` + perfil
ativo do chamador.

### 2.2 Mecanismos atuais de identidade — fluxo real (Supabase Auth)

1. `AuthProvider` cria o cliente via `criarClienteAuthSupabase()` e instancia
   `Autenticador`/`RepositorioIdentidade` (adapters) e o `ControladorSessao`.
2. `inicializar()` registra `onAuthStateChange` e lê a sessão inicial
   (`getSession`). O evento `INITIAL_SESSION` é classificado como “restauração”
   (preserva o marcador de início); `SIGNED_IN`/`PASSWORD_RECOVERY` como “novo
   login” (reinicia a janela da política F2-08).
3. Com sessão, `resolverIdentidade(authUserId, repositorio)` faz três consultas:
   `user_profiles` (próprio, ativo), `user_organization_memberships`
   (próprias, ativas) e `organizations` (alcançáveis). Perfil ausente ou
   inativo ⇒ `ForbiddenError` ⇒ estado `acessoNegado`. Zero memberships ⇒
   `autenticado` com listas vazias (comportamento atual — G5); o contrato
   aprovado (Q2) substitui esse caso por estado dedicado `semOrganizacao` na
   implementação — nenhuma organização é inventada.
4. `AuthProvider` agenda revalidação a cada 60 s e ao focar a janela:
   `autenticador.validarSessaoAtual()` (`auth.getUser`) + re-resolução — detecta
   desativação/banimento (F2-07) e aplica limites da F2-08.
5. Rotas funcionais só renderizam com `estado.status === "autenticado"` (ou DEV
   com simulação preservada quando `indisponivel`).

### 2.3 Identidade simulada/selecionável (DEV)

- `UsuarioAtualProvider` mantém o colaborador sintético selecionado
  (`feedback-control-colaboradores`, seed de `src/data/colaboradores`), com
  seleção guardada em `feedback-control-usuario-atual`.
- Gate único: `simulacaoDevPermitida = DEV && !PROD && VITE_APP_ENV=development`.
  Fora de DEV: nada é carregado como identidade e a troca é bloqueada.
- A impersonação DEV **não** altera `auth.uid()`/JWT/sessão e **não** participa
  de chamadas server-side como autorização (contrato F2-09, preservado).

### 2.4 Como as páginas consomem “usuário atual” hoje

Páginas e componentes funcionais leem `useUsuarioAtual()` e constroem o
`AuthorizationContext` (matrícula/função/status) que alimenta os adaptadores
F4-09 (`authorizationPolicy`/`autorizacaoFuncional`), que por sua vez delegam ao
Policy Engine com o mundo local (`mundoFuncional`). Ou seja: **em runtime, o
“ator” do engine é o colaborador sintético do DEV** (actorId =
`String(matricula)`), não o usuário real autenticado. Exemplos verificados:
`NavegacaoPrincipal.tsx`, `ColaboradoresPage.tsx`, `CiclosAvaliacaoPage.tsx`,
`ColaboradorDetalhePage.tsx`, `ObservacoesColaborador.tsx`, `metaStorage.ts`,
`cancelamentoAvaliacaoService.ts`, `correcaoPeriodoCicloService.ts`, entre outros.

A identidade **real** resolvida (`IdentidadeResolvida`) hoje só é consumida por
`LoginPage` (exibição de organizações), `ConvidarUsuarioPage` (lista de orgs para
o convite) e `AuthStatus` (e-mail + Sair).

### 2.5 Supabase Auth — integração verificada

- `@supabase/supabase-js` (^2.115.0) com `persistSession: true`,
  `autoRefreshToken: true`, `detectSessionInUrl: true` (cliente de auth).
- `auth.uid()` não aparece como chamada direta no TS; o runtime usa
  `session.user.id` do SDK (que é o mesmo `auth.uid()` que as policies SQL
  avaliam). `auth.getUser()` revalida o usuário no servidor (F2-07).
- Sem configuração pública (URL/anon key): cliente `null`, estado
  `indisponivel` — em DEV a simulação segue; em HOMOLOG/PROD o guard redireciona
  para login (falha segura).
- `enable_signup = false` (config.toml): a **única** via de criação de conta é o
  convite administrativo (Edge Function) — sem self-signup.
- Sessão do Supabase é persistida pelo próprio SDK (storage próprio do
  provedor); o Virtus só persiste o marcador de política
  `virtus.auth.inicioSessao` (metadado temporal).

### 2.6 Pontos onde IDs vindos do frontend participam (sem virar autoridade)

- `matricula` do colaborador selecionado em DEV → `actorId` do engine (mundo
  sintético; somente DEV).
- `organization_id` no convite (`ConvidarUsuarioPage` → `functions.invoke`) —
  autorização server-side provisória por allowlist, sem checagem de membership
  do chamador na organização-alvo.
- Parâmetros de rota `:id`/`:cicloId`/`:feedbackId` → alvos de recurso, sempre
  revalidados por `authorize()`/RLS (nunca confiados como prova).
- Nenhum fluxo funcional real (HOMOLOG/PROD) usa IDs de usuário autenticado
  porque o vínculo usuário→colaborador ainda não existe em runtime.

### 2.7 Dependências das Fases 3 e 4 relevantes para a F5-01

- **F3**: `collaborators` (id uuid + organization_id; identidade imutável e
  lifecycle temporal), posições/ocupações/reporting lines, colegiado e
  responsabilidades avaliativas — o `colaborador` é entidade de **domínio**,
  independente da conta de acesso.
- **F4-01/F4-02**: catálogo de capabilities/access_roles/assignments e
  scopes/targets; **já existe** `membership_collaborator_links` (1 membership →
  ≤1 colaborador) e `resolver_collaborador_vinculado` — porém **sem policies e
  sem grants** (deny-by-default; nenhum runtime consome).
- **F4-08**: fronteira soberana de tenant fechada — `auth.uid()` + `user_profile`
  ativo + `membership` ativa; helper único `user_has_active_membership`;
  cross-tenant DENY.
- **F4-09/F4-10**: Policy Engine é o gate soberano; o mundo local
  (`mundoFuncional`) é **transitório pré-F5** (substituído por membership →
  access_role → capability) e o binding DEV de capabilities é explícito.

---

## 3. Problemas e gaps (G1–G11)

| # | Gap | Evidência | Consequência | Endereçado em |
| --- | --- | --- | --- | --- |
| G1 | Não existe um único contrato runtime de “identidade autenticada” que conecte sessão real, perfil, memberships, organizações e o ator do engine; hoje há dois contextos desconexos (`AuthContext` e `UsuarioAtualContext`) e nenhum `ActorContext` | `App.tsx`, `AuthContext`, `UsuarioAtualContext` | Em HOMOLOG/PROD o usuário real autentica, mas a área funcional não tem identidade de ator (vazio); em DEV o ator é o colaborador sintético | F5-01 (contrato) + F5-02/03/05 (runtime) |
| G2 | `IdentidadeResolvida` só alimenta páginas de auth; nenhum serviço/domínio funcional a consome | grep de `estado.identidade` (apenas `LoginPage`, `ConvidarUsuarioPage`, `AuthStatus`) | A identidade real não chega à camada de aplicação | F5-02/05 |
| G3 | O vínculo usuário↔colaborador não existe em runtime (apenas a tabela F4-02 fechada); páginas assumem impersonação DEV | `mundoFuncional`, `authorizationPolicy`, páginas | Sem DEV não há “quem sou eu” funcional | F5-02 |
| G4 | Membership/orgs não participam do runtime funcional: mundo local usa tenant sintético único (`isMembershipActive: () => true`) | `mundoFuncional.ts` L201 | Capacidade real por tenant não é exercitada; multi-org sem efeito | F5-03/04 |
| G5 | Estado “autenticado com zero memberships” não tem UX definida na área funcional (rotas permitem; páginas sem `usuarioAtual` se comportam de formas distintas: algumas retornam vazio/redirect) | `LayoutAutenticado`, páginas que dão bail-out | Comportamento inconsistente em PROD — Q2 aprovada define estado dedicado `semOrganizacao` com área funcional bloqueada | F5-01 (estado) + F5-03 |
| G6 | Revalidação trata **qualquer** falha de `getUser` como fim de sessão — não distingue sessão inválida/revogada (401/ban) de falha transitória de rede/5xx | `controladorSessao.ts` (revalidar) | Queda de rede derruba a sessão local — Q1 aprovada exige distinguir: 401/ban/removido encerra o acesso; falha transitória mantém a sessão e reintenta (sem logout) | F5-01 (estado/fail-closed) |
| G7 | Adapter mapeia status desconhecido como **ativo** (`status === "disabled" ? "disabled" : "active"`), invertendo fail-closed em defesa em profundidade | `adaptadores.ts` (perfil e membership) | Um valor inesperado de status passaria como ativo no cliente (o banco CHECK protege hoje, mas a defesa em camadas pede o contrário) | F5-01 (correção na implementação) |
| G8 | Duas fábricas de cliente Supabase (F1-04 com auth desligado e sem consumidores; F2-03 de auth) e comentários desatualizados | `src/infrastructure/supabase/supabaseClient.ts`, `src/auth/cliente.ts` | Risco de drift de configuração; superfície de manutenção duplicada | F5-01 (normalização) ou etapa de infra |
| G9 | `user_profile` carrega apenas `id/status`; não há atributo de exibição; o nome exibido vem de `auth.users` (e-mail). O papel do perfil como provedor de informação está indefinido | `tipos.ts`, migrations F2-01/F2-07 | Impossível exibir nome de exibição sem depender do e-mail do provedor — Q5 aprovada mantém o perfil mínimo e o e-mail autenticado como nome até a F5-02 avaliar o colaborador vinculado | F5-01 (decisão Q5/D14) |
| G10 | Sem testes/estado dedicados para: profile ausente com conta criada fora do convite; perfil inconsistente; falha de carregamento da identidade durante restauração | `servico.test.ts`, `controladorSessao.test.ts` | Regressões silenciosas possíveis quando esses casos entrarem em runtime | F5-01 (estratégia de testes) |
| G11 | Edge Functions de convite/desativação usam allowlist provisória (`INVITE_ADMIN_USER_IDS`) como autorização, e o convite não valida membership do chamador na organização-alvo | `convidar-usuario/index.ts`, `gerenciar-usuario/index.ts` | Autorização administrativa ainda não é por capability | F5-04 (server-side) |

---

## 4. Fronteiras de confiança

Modelo em camadas (cada camada tem uma fonte soberana distinta):

```
┌────────────────────────────────────────────────────────────────┐
│ 1. Provedor de autenticação (Supabase Auth)                     │
│    fonte: auth.users / gotrue — sessão JWT, refresh, ban, MFA   │
│    responde: "quem se autenticou" (auth.uid())                  │
├────────────────────────────────────────────────────────────────┤
│ 2. Perfil interno (public.user_profiles)                        │
│    fonte: banco — 1:1 com auth.uid()                            │
│    responde: "a conta tem acesso ao Virtus?" (status active)    │
├────────────────────────────────────────────────────────────────┤
│ 3. Membership (public.user_organization_memberships)            │
│    fonte: banco + RLS (helper user_has_active_membership)       │
│    responde: "em quais tenants (organizações) esta conta atua?" │
├────────────────────────────────────────────────────────────────┤
│ 4. Colaborador (public.collaborators — domínio F3)              │
│    fonte: banco — entidade de domínio (pessoa na estrutura)     │
│    responde: "qual pessoa organizacional corresponde à conta"   │
│    (vínculo futuro por membership — F5-02)                      │
├────────────────────────────────────────────────────────────────┤
│ 5. ActorContext (runtime da aplicação — F5-05)                  │
│    fonte: derivada das camadas 1–4 pelo serviço (nunca pela UI) │
│    alimenta: ActorRef do Policy Engine (F4)                     │
└────────────────────────────────────────────────────────────────┘
```

**Fronteiras conceituais (fechadas para F5-01):**

| Conceito | É | NÃO é | Fronteira com |
| --- | --- | --- | --- |
| **AuthIdentity** | A identidade de autenticação: `auth.uid()` + sessão do provedor; o elo primário entre runtime e banco | Fonte de autorização, tenant, perfil ou papel | `user_profile.id = auth.uid()` |
| **user_profile** | O registro interno 1:1 da conta: existe/ativo = “usuário do Virtus”; âncora de memberships e auditoria (`created_by` em tabelas F4-02) | Credencial, segredo, e-mail de negócio, colaborador, papel | Membership e colaborador referenciam **via** perfil/membership, não por e-mail |
| **membership** | Vínculo de acesso conta↔organização (ativo = tenant acessível) | Papel/capability; cargo; vínculo com colaborador (este é o *link* F4-02) | 1 conta → N memberships; 1 membership → ≤1 colaborador (F5-02) |
| **colaborador** | Pessoa organizacional (domínio F3) com lifecycle temporal | Usuário de acesso; credencial | Vincula-se à conta apenas por membership (F5-02) |
| **ActorContext** | O ator efetivo no Policy Engine (ActorRef) derivado das camadas 1–4 | Estado global da UI; contexto de DEV | Criado em F5-05; F5-01 fixa o contrato de entrada |

---

## 5. Modelo conceitual proposto

### 5.1 Fontes soberanas e não soberanas

**Soberanas (servidor/banco — nunca o cliente):**

| Dado | Fonte soberana | Como é obtido |
| --- | --- | --- |
| `auth.uid()` (identidade autenticada) | Supabase Auth (`auth.users`) | Sessão JWT validada / `auth.getUser` / `auth.uid()` no SQL |
| Existência e status do perfil | `public.user_profiles` (RLS) | Resolução por `auth.uid()`; leitura própria só com `status='active'` |
| Memberships ativas | `public.user_organization_memberships` (RLS) | Filtro por `auth.uid()` + `status='active'` |
| Tenants alcançáveis | `public.organizations` via helper `user_has_active_membership` | RLS/consulta |
| Tenant do recurso | Coluna `organization_id` do recurso carregado | Resource load no servidor/RLS |
| Vínculo conta↔colaborador | `membership_collaborator_links` (F4-02; futuro F5-02) | Resolução server-side |
| Capacidade/escopo efetivos | Policy Engine + providers (F4) | `authorize()` no ponto de mutação |

**Não soberanas (informação apresentada pelo cliente / contexto de UX):**

| Dado | Papel | Nunca é |
| --- | --- | --- |
| `session.user.email` | Exibição (cabeçalho, mensagens) | Chave de vínculo/identificação de conta |
| `user.id` repetido em estado de UI | Identificador de sessão para chamadas | Prova de identidade (o servidor deriva de `auth.uid()`) |
| `organizationId` selecionado na UI | Intenção de tenant para a operação | Prova de membership/tenant (servidor valida sempre) |
| `matricula`/ids de colaborador | Alvo/recurso de UX | Ator ou prova de identidade em runtime real |
| Claims do JWT (role, metadata) | Transporte/claims do provedor | Fonte de autorização ou de tenant |

### 5.2 O que o frontend pode transportar (regra)

O frontend pode **transportar** identificadores de recurso e intenção de
contexto (ex.: `organization_id` para uma operação, ids de alvo em rotas), desde
que:

1. **nenhuma** prova de identidade/tenant seja aceita deles;
2. toda operação revalide no servidor (RLS + Policy Engine) com `auth.uid()`
   derivado da sessão;
3. falte validação ⇒ DENY (fail-closed), nunca ALLOW por omissão.

Proibido em runtime real: transportar o `user_profile_id`/`auth.uid()` do
próprio usuário para “provar” quem é; transportar `organization_id` como
prova de tenant; aceitar `role` de claims como capability.

### 5.3 Fronteira do dado confiável

Regra consolidada (já contratada na F4-08 e mantida): **dado confiável é o que
o servidor deriva de `auth.uid()` + estado persistido no banco sob RLS.** Tudo
o que o cliente apresenta (claims, headers, estado, seleções) é tratado como
contexto não confiável e revalidado.

---

## 6. Fluxo de resolução da identidade (alvo)

```
bootstrap (refresh/reabertura)          login (credenciais)          revalidação (F2-07)
─────────────────────────────           ────────────────────         ──────────────────────
1. getSession() → sessão?               1. signInWithPassword         1. limites F2-08 ok?
   ├─ não → naoAutenticado                 → evento SIGNED_IN            ├─ não → sessaoExpirada
   └─ sim → evento "inicial"            2. marca início (janela         └─ sim
2. política F2-08: duração?                 da política reinicia)      2. auth.getUser()
   ├─ > 1 dia → sessaoExpirada          3. resolverIdentidade(auth.uid)   ├─ inválida/revogada
   └─ ok → preserva marcador            4. autenticado/semOrganizacao      (401/ban/removido)
3. resolverIdentidade(auth.uid)             (ver abaixo)                   → encerra acesso
4. autenticado/semOrganizacao                                             ├─ falha transitória
   (ver abaixo)                                                             (rede/5xx) → mantém
                                                                             sessão local, reintenta
                                                                             (sem logout)
                                                                           └─ ok → re-resolve
                                                                              identidade
                                                                           3. autenticado/semOrganizacao

resolverIdentidade(authUserId) ── porta RepositorioIdentidade (RLS):
  perfil = buscarPerfil(authUserId)
    ├─ ausente        → acessoNegado com mensagem neutra/orientativa (Q3 aprovada)
    ├─ status != ativo→ acessoNegado (fail-closed)
    └─ ativo →
        memberships = buscarMembershipsAtivas(authUserId)   // somente ativas
        ├─ vazias     → estado dedicado semOrganizacao (Q2 aprovada — área
        │                funcional bloqueada; nenhum tenant inventado)
        └─ organizacoes = buscarOrganizacoes(ids das memberships)
           → IdentidadeResolvida { authUserId, perfil, memberships, organizacoes }
           (N>1 ⇒ seleção explícita antes do uso funcional — Q4 aprovada)
```

Invariantes do snapshot de identidade (`IdentidadeResolvida`):

1. `authUserId === perfil.id === user_profile.id === auth.uid()` (1:1);
2. `perfil.status === "active"` (senão o estado é de falha, nunca autenticado);
3. `memberships` contém **somente** ativas; `organizacoes` é derivada das
   memberships; **nenhuma seleção arbitrária** é feita;
4. o snapshot é imutável e por-request; páginas nunca o mutam.

---

## 7. Estados da identidade/sessão e tratamento dos casos

Estados da máquina (F2-03/F2-08, preservados e ampliados conceitualmente):

`verificando` → `naoAutenticado` / `autenticado` / `semOrganizacao` /
`acessoNegado` / `indisponivel` / `sessaoExpirada`

| Caso (escopo F5-01) | Resolução atual | Estado resultante | Comportamento fail-closed |
| --- | --- | --- | --- |
| Usuário autenticado **sem user_profile** (conta criada fora do convite) | `buscarPerfil` → null | `acessoNegado` — mensagem neutra/orientativa “acesso ainda não provisionado” para a própria conta (Q3 aprovada) + Sair; demais negados permanecem genéricos | Nenhum conteúdo funcional; sem criação automática de perfil (proibido auto-provisionar); sem expor detalhes internos |
| **Profile inexistente** (mesmo caso; ex.: limpeza) | idem | `acessoNegado` | Idem |
| **Profile inativo/desabilitado** (F2-07) | RLS oculta o próprio perfil (`status='active'`) e/ou ban no Auth | `acessoNegado` / `naoAutenticado` (via ban no getUser) | Revogação efetiva, mesmo com JWT pré-existente |
| **Profile inconsistente** (status inesperado, divergência de snapshot) | Banco CHECK limita o domínio; adapter hoje trata desconhecido como ativo (**G7**) | Deve ser `acessoNegado` | Corrigir mapeamento p/ fail-closed; nunca default ativo |
| **Sessão inexistente** (sem sessão salva) | `obterSessao` → null | `naoAutenticado` | Login público apenas |
| **Sessão inválida/revogada** (ban, token revogado, usuário removido) | `getUser` falha | `naoAutenticado` | 401/ban/usuário removido ⇒ **encerra o acesso** (Q1 aprovada); sem conteúdo; nova autenticação |
| **Sessão expirada** (política F2-08: 60 min inatividade / 1 dia) | motivo exposto no login | `sessaoExpirada` (com motivo) | Requer nova autenticação; marcador local limpo |
| **Usuário removido/desabilitado** | FK `user_profiles→auth.users` com RESTRICT + desativação via ban (sem delete físico); profile disabled | `acessoNegado` / `naoAutenticado` | Conta sem acesso; nada é fabricado |
| **Falha de carregamento da identidade** (erro ao resolver perfil/memberships) | erro técnico | `acessoNegado` (erro técnico seguro) | Nenhum conteúdo; re-tentativa via revalidação |
| **Falha transitória de rede na revalidação** | hoje tratada como fim de sessão (**G6**) | permanece `autenticado` — sessão local mantida, revalidação pendente/reintenta (Q1 aprovada, alternativa B) | Sem logout automático; nenhuma operação dependente de autorização/server-side é liberada offline (fail-closed preservado) |
| Autenticado com profile ativo e **zero memberships** ativas | listas vazias; rota funcional liberada (G5) | `semOrganizacao` (Q2 aprovada, alternativa A) — estado dedicado | Área funcional bloqueada com tela informativa; nenhum tenant inventado; **não** é shell funcional vazio; UX final de seleção pertence à F5-03 |

Regras transversais:

- Conteúdo funcional só é renderizado com `autenticado` **e** organização
  selecionada e validada (Q4); no estado `semOrganizacao` a área funcional
  permanece bloqueada;
- com múltiplas memberships ativas (N>1), nenhuma organização é escolhida
  silenciosamente: seleção explícita antes do uso funcional (Q4 aprovada); a
  seleção enviada pelo cliente é apenas intenção, validada contra memberships
  soberanas; persistência/UX/switcher ficam para F5-03;
- nenhum estado degrada para identidade simulada fora de DEV;
- nenhum estado fabrica perfil/membership/organização;
- erros de identidade são mapeados para a taxonomia F0-05 (nunca mensagens do
  provedor).

---

## 8. Comportamento fail-closed

| Momento | Regra |
| --- | --- |
| **Inicialização** | Estado inicial `verificando`; nada de conteúdo protegido antes da resolução; Supabase ausente ⇒ `indisponivel` (DEV simula; senão login) |
| **Refresh/restauração** | Evento “inicial”: preserva marcador; sessão com idade > 1 dia expira (não contorna o limite); identidade re-resolvida do servidor |
| **Revalidação periódica** | `getUser` (servidor) + re-resolução; perfil desabilitado/membership revogada refletem na próxima passada (≤60 s ou no foco). **Q1 aprovada:** sessão efetivamente inválida/revogada (401, ban, usuário removido) ⇒ encerra o acesso; falha transitória de transporte/5xx ⇒ mantém a sessão local e reintenta, **sem logout automático** — nenhuma operação dependente de autorização/server-side é liberada offline |
| **Mudança de usuário** | Troca de `auth.uid()` encerra a vigência da sessão anterior e abre janela nova apenas por sign-in explícito; nenhum resíduo de identidade anterior persiste no estado |
| **Logout** | `signOut` global; marcador e vigência limpos; estado `naoAutenticado` |
| **Erros** | Mapeados para taxonomia pública; nenhuma credencial/mensagem do provedor na UI; conteúdo nunca renderiza em dúvida |
| **Regra de ouro** | Em qualquer ambiguidade (dado ausente, status inesperado, tenant divergente, falha de carregamento) a decisão é **DENY/bloqueio**, nunca ALLOW por omissão |

---

## 9. Interfaces/contratos necessários

### 9.1 Contratos que F5-01 formaliza (sem implementar)

Contratos runtime de referência para a implementação (baseados nos tipos
existentes; nenhum código novo nesta atividade):

```ts
// Identidade de autenticação — raiz (evolução formal de IdentidadeResolvida).
// memberships vazias ⇒ estado dedicado `semOrganizacao` (Q2 aprovada), com a
// área funcional bloqueada — o snapshot permanece válido, sem tenant inventado.
interface AuthIdentity {
  readonly authUserId: string;        // === user_profile.id === auth.uid()
  readonly perfil: PerfilAutenticado; // { id, status: "active" } — pré-condição
  readonly memberships: MembershipAutenticada[]; // somente ativas
  readonly organizacoes: OrganizacaoResolvida[]; // derivadas; sem seleção
}

// Resolução de identidade — porta (já existe como RepositorioIdentidade).
interface IdentityResolver {
  resolver(authUserId: string): Promise<AuthIdentity>; // falha = acesso negado
}

// Ator efetivo no Policy Engine (F5-05 consumirá; o engine já está pronto).
// Em runtime real: actorId = user_profile.id (auth.uid()); organizationId =
// valido por membership ativa; o colaborador vinculado é resolvido por
// membership_collaborator_links (F5-02) para relações/escopo.
interface ActorContext {
  readonly identity: AuthIdentity;
  // tenant em uso — com N>1 memberships exige seleção explícita (Q4 aprovada);
  // a seleção é intenção validada no servidor; UX/persistência/switcher = F5-03.
  readonly organizationId: string;
  toActorRef(): ActorRef;          // { actorId: identity.authUserId, organizationId }
}
```

### 9.2 Requisitos de contrato que F5-01 impõe às próximas atividades

- **F5-02 (vínculo usuário↔colaborador):** deve usar **exclusivamente**
  membership → `membership_collaborator_links`; nunca e-mail/matrícula como
  chave de vínculo; 1 membership → ≤1 colaborador na mesma organização (FK
  composta de tenant já garante). O vínculo é opcional (ADMIN pode não ter
  colaborador). **Q5 aprovada:** a F5-02 avaliará o uso do colaborador vinculado
  como identidade de apresentação — o nome exibido segue pelo e-mail autenticado
  até lá.
- **F5-03 (membership/organização ativa):** a seleção de organização é **estado
  de sessão de UX validado no servidor** (nunca prova); com N>1 memberships
  ativas é obrigatória **seleção explícita antes do uso funcional** — nenhuma
  escolha silenciosa (Q4 aprovada); zero memberships é o estado dedicado
  `semOrganizacao` (Q2 aprovada), sem conteúdo e sem tenant inventado;
  persistência/UX/switcher ficam para F5-03.
- **F5-04 (access roles/capabilities):** capability efetiva derivada de
  membership → access_role → capability no banco (funções F4-02 existentes);
  o binding DEV-only de `mundoFuncional` é transitório e removível.
- **F5-05 (ActorContext):** única porta de entrada do `ActorRef` real no Policy
  Engine; nenhuma página monta `ActorRef`; `actorId` = `auth.uid()` (perfil),
  com resolução do colaborador vinculado dentro dos providers por
  `(actorId, organizationId)`.

### 9.3 Compatibilidade com o Policy Engine (F4)

O engine é agnóstico ao significado do `actorId` (opaque string usada de forma
consistente pelos providers). A transição DEV→real acontece **nos providers**,
não no engine:

- hoje (DEV): `actorId = String(matricula)` + providers do `mundoFuncional`;
- real (F5): `actorId = auth.uid()` + providers que consultam
  membership/access_role/colaborador vinculado (F5-04/05).

Origem C/D já operam com `beneficiaryUserProfileId`/`grantedByUserProfileId`
(F4-06/F4-07), ou seja, **já assumem o id do perfil** como identidade soberana —
coerente com `actorId = auth.uid()` em runtime real.

---

## 10. Impacto esperado no código

> Nenhuma alteração é feita nesta atividade; abaixo o impacto estimado para a
> implementação futura (F5-01 em si e interfaces de F5-02/05).

**Provável (F5-01):**
- `src/auth/tipos.ts` / `contratos.ts` — formalizar `AuthIdentity` e invariantes;
- `src/auth/adaptadores.ts` — corrigir mapeamento de status p/ fail-closed (G7);
- `src/auth/controladorSessao.ts` — representar os estados aprovados (falha
  transitória × revogação — Q1; `semOrganizacao` — Q2) e ajustar a revalidação;
- `src/auth/AuthContext.tsx` / `AuthProvider.tsx` — expor identidade/estados
  ampliados sem quebrar consumidores atuais;
- `src/auth/*.test.ts` — novos testes de caracterização dos casos do §7;
- testes de rotas/guard (`rotasProtegidas.test.ts`, `LayoutAutenticado.test.tsx`);
- possivelmente normalizar fábricas de cliente Supabase (G8).

**Pós-F5-01 (próximas atividades — apenas contratos definidos aqui):**
- `src/authorization/mundoFuncional.ts` — substituição gradual do mundo DEV;
- criação do módulo de ActorContext (F5-05) e do serviço de vínculo (F5-02);
- páginas passam a consumir o novo contexto de identidade real em lugar do
  `usuarioAtual` DEV (com DEV preservado para o seed).

**Banco:** nenhuma migration necessária para F5-01 (o modelo F2/F4 já cobre
perfil/membership/links). Ajustes futuros (ex.: atributos de exibição) são
decisões posteriores (Q5 aprovada — perfil mínimo; D14).

---

## 11. Compatibilidade com F3/F4

Preservados integralmente (nada desta atividade redesenha):

- Policy Engine = gate soberano de autorização; `authorize()` = enforcement;
  `can()` = UX; capability = ação;
- nenhuma autorização runtime por cargo/job_role/função;
- tenant mismatch = DENY; comportamento fail-closed;
- contexto do cliente não é fonte soberana de identidade ou tenant;
- ADMIN não é superuser de conteúdo;
- contratos SELF, hierarquia, ASSIGNED, C (excepcional) e D (pilot) vigentes;
- RLS F4-08 e isolamento de tenant vigentes (helper `user_has_active_membership`);
- mundo local `mundoFuncional` permanece como mundo DEV transitório até F5-04;
- impersonação DEV (F2-09) permanece exclusiva de DEV (`simulacaoDevPermitida`);
- compatibilidade com dados antigos de `localStorage`
  (`feedback-control-*`, inclusive `feedback-control-usuario-atual`) preservada.

F5-01 adiciona **semântica**, não novas regras de autorização: ela define quem é
a raiz de identidade que alimenta os contratos já existentes.

---

## 12. Estratégia de implementação (ordem sugerida — decisões aprovadas)

1. **Contrato**: formalizar `AuthIdentity` + invariantes e documentar as
   fronteiras do §4 no código (tipos/comentários) — sem mudança de
   comportamento.
2. **Fail-closed do adapter**: corrigir G7 (status desconhecido ⇒ inativo) com
   teste de regressão.
3. **Estados**: implementar as decisões aprovadas no controlador/guard, com
   testes: distinção falha transitória × revogação (Q1), estado dedicado
   `semOrganizacao` (Q2) e seleção explícita com N>1 (Q4 — contrato, sem UX).
4. **Exposição**: ampliar `AuthContext`/rotas conforme o contrato aprovado
   (inclui mensagem neutra/orientativa de conta não provisionada — Q3), sem
   afetar o fluxo DEV.
5. **Normalização** (G8): unificar a criação do cliente Supabase sob a
   configuração única (se aprovado no escopo).
6. **Registrar contratos para F5-02/05** (seção 9) como referência das próximas
   atividades (vínculo, organização ativa, ActorContext).
7. Cada passo segue o fluxo GitHub: branch por Issue, commits objetivos,
   validações `npm test`, `npm run build`, `npm run lint`, `git diff --check`.

---

## 13. Estratégia de testes

**Unidade (vitest, camada pura — padrão já usado em `src/auth/*.test.ts`):**
- resolução de identidade: perfil ausente (mensagem neutra — Q3); perfil
  `disabled`; status inesperado (fail-closed); membership desabilitada;
  múltiplas memberships sem seleção; zero memberships (estado dedicado
  `semOrganizacao` — Q2; área funcional bloqueada);
- máquina de sessão: bootstrap com/sem sessão; restauração com idade > 1 dia;
  revalidação com usuário revogado (401/ban/removido ⇒ encerra o acesso) **vs**
  falha transitória de rede/5xx (Q1 aprovada: mantém a sessão e reintenta, sem
  logout); mudança de usuário; logout; expiração com motivo;
- rotas/guard: `verificando`/`acessoNegado`/`sessaoExpirada`/`indisponivel`/
  `semOrganizacao` (DEV vs HOMOLOG/PROD).

**Integração/validação local (padrão `supabase/validacao`):**
- cenários SQL que confirmam as policies de identidade (próprio perfil ativo,
  memberships próprias ativas, organizations via `user_has_active_membership`),
  incluindo profile desabilitado ⇒ invisível e zero linhas;
- teste de ban (F2-07) revogando acesso apesar de JWT antigo.

**Caracterização (não quebrar contrato):** testes existentes de
`controladorSessao`, `servico`, `rotasProtegidas`, `LayoutAutenticado`,
`UsuarioAtualProvider` continuam verdes; adicionar negativos explícitos para os
casos do §7 (priorizar NEGATIVOS, padrão F4-09).

**Invariante de aceite:** nenhum teste deve depender de identidade simulada fora
do gate DEV.

---

## 14. Critérios de aceite

1. Documento aprovado: D1–D14 **fechadas** e Q1–Q5 **aprovadas** (revisão
   registrada no PR #159).
2. Contrato `AuthIdentity` formalizado no código com as invariantes do §6;
   nenhuma mudança de comportamento funcional fora do escopo.
3. Adapter de identidade fail-closed (status desconhecido/inconsistente não vira
   ativo) com teste.
4. Estados do §7 representados no controlador/guard (incluindo `semOrganizacao`);
   rotas funcionais nunca renderizam conteúdo em estado de dúvida.
5. (Q1 aprovada) Falha transitória de rede/5xx **não** derruba a sessão (mantém
   a sessão local e reintenta); sessão efetivamente inválida/revogada
   (401/ban/removido) encerra o acesso; ambos cobertos por teste.
6. (Q2 aprovada) Estado dedicado `semOrganizacao` com UX informativa; área
   funcional bloqueada; sem fabricação de tenant; não é shell funcional vazio.
7. (Q3 aprovada) Conta autenticada sem perfil exibe mensagem neutra/orientativa;
   demais casos de acesso negado permanecem genéricos.
8. (Q4 aprovada) Com N>1 memberships, nenhuma escolha silenciosa: seleção
   explícita como intenção validada no servidor — contrato registrado, sem
   switcher (F5-03).
9. DEV impersonação intacta e exclusiva de DEV; nenhuma identidade simulada em
   HOMOLOG/PROD (regressão coberta).
10. Fronteiras F5-02/03/04/05 registradas (§9) e nenhuma delas implementada
    nesta atividade.
11. `npm test`, `npm run build`, `npm run lint` e `git diff --check` verdes no
    PR da implementação.

---

## 15. Fora de escopo (F5-01)

> A F5-01 entrega somente o **contrato** de identidade. A implementação de
> **F5-02, F5-03, F5-04 e F5-05** permanece explicitamente fora desta atividade
> e **não está contida neste diff** (somente documentação).

- **F5-02**: vínculo usuário autenticado ↔ colaborador (fluxo e runtime);
- **F5-03**: membership e organização ativa (switcher, persistência da escolha);
- **F5-04**: access roles e capabilities em runtime (fonte real de capabilities);
- **F5-05**: ActorContext (implementação);
- migração geral de `localStorage` e persistência remota dos domínios funcionais;
- arquitetura definitiva de produção, hosting, observabilidade e backup;
- hardening geral da Fase 6;
- redesenhar o Policy Engine;
- autorização administrativa das Edge Functions por capability (G11 → F5-04);
- UI definitiva de perfil/preferências (Q5 aprovada → atividade posterior).

---

## 16. Riscos

| Risco | Mitigação |
| --- | --- |
| Contrato de identidade “estourar” para F5-02/05 | Limites explícitos no §1.2 e §9.2; nenhuma implementação cruzada |
| Quebrar o fluxo DEV (impersonação) durante a formalização | Gate `simulacaoDevPermitida` intocado; testes de caracterização |
| Tratar falha de rede como revogação (logout indesejado em campo) | Q1 aprovada (alternativa B): distinguir revogação de falha transitória; manter sessão local e reintentar; teste de rede simulada |
| UX inconsistente para zero-membership / conta não provisionada | Q2/Q3 aprovadas: estado dedicado `semOrganizacao` e mensagem neutra/orientativa; estados dedicados no guard/rotas |
| Drift entre as camadas de status (banco/RLS/adapter) | Corrigir adapter (G7); documentar que o banco é a fonte |
| Multiplicidade de clientes Supabase (G8) gerar drift | Normalização na implementação |
| Vínculo futuro por e-mail/matrícula (IDOR) | F5-02 restrito a membership → link (FK composta de tenant) |

---

## 17. Questões para validação

> Formato pedido pela F5-01: ID, contexto, por que a decisão é necessária,
> alternativas, recomendação, impacto/risco, seções dependentes.

## 17. Questões para validação (Q1–Q5 — FECHADAS/APROVADAS)

> Formato pedido pela F5-01: ID, contexto, por que a decisão é necessária,
> alternativas, recomendação, impacto/risco, seções dependentes.
>
> **Situação:** Q1–Q5 foram **APROVADAS** na revisão do PR #159 e suas decisões
> estão incorporadas às seções dependentes deste documento. Os itens abaixo
> mantêm o histórico completo para rastreabilidade; a decisão adotada é
> registrada em cada questão.

### Q1 — Falha transitória de rede × sessão inválida/revogada na revalidação — **FECHADA (alternativa B APROVADA)**

- **Decisão adotada (aprovada):** distinguir sessão realmente
  inválida/revogada (401, usuário removido, banido ou sessão efetivamente
  inválida) — **encerra o acesso** — de falha transitória de transporte/5xx —
  **não causa logout automático** (mantém a sessão local e reintenta). Durante a
  indisponibilidade, nenhuma operação que dependa de autorização/server-side
  pode ser liberada por confiança no estado local: o fail-closed permanece.
- **Contexto:** a revalidação F2-07 (`controladorSessao.revalidar`) trata
  qualquer erro de `getUser` como fim de sessão (`naoAutenticado`). Queda de
  rede, 5xx ou timeout do provedor derrubam a sessão local mesmo com JWT válido.
- **Por que é necessária:** o contrato F5-01 exige distinguir “sessão
  inexistente/inválida/expirada” de “falhas de carregamento da identidade”; o
  comportamento atual colapsa os dois casos e degrada a UX em campo (G6).
- **Alternativas:**
  - (A) manter o comportamento atual (qualquer falha ⇒ logout local; conservador);
  - (B) distinguir por natureza do erro: 401/ban/usuário removido ⇒ logout;
    falha de transporte/5xx ⇒ manter sessão local e reintentar com backoff,
    **sem** permitir mutações offline (autorização continua fail-closed);
  - (C) híbrida: (B) + estado visível “reconectando…” após N tentativas.
- **Recomendação:** (B) — é a única que representa fielmente os estados do §7
  sem abrir janela de uso não autorizado (nenhuma operação funcional ocorre sem
  servidor; RLS/engine permanecem soberanos).
- **Impacto/risco:** mudança na máquina de sessão e na política de erros; risco
  baixo se limitada à revalidação; exige testes de rede simulada.
- **Seções dependentes:** 3 (G6), 7, 8, 9.1, 13, 14.

### Q2 — Usuário autenticado com profile ativo e zero memberships ativas — **FECHADA (alternativa A APROVADA)**

- **Decisão adotada (aprovada):** usuário autenticado com profile ativo, mas
  sem membership ativa ⇒ entra em estado dedicado **“sem organização”**
  (`semOrganizacao`); a área funcional permanece bloqueada; não inventar tenant
  e não tratar o cenário como shell funcional vazio. A UX final de seleção de
  organização pertence à F5-03.
- **Contexto:** hoje `resolverIdentidade` permite `autenticado` com listas
  vazias e o guard libera as rotas funcionais; as páginas, sem `usuarioAtual`
  (fora de DEV), se comportam de forma inconsistente (G5).
- **Por que é necessária:** precisa-se de um estado/UX única para “conta válida
  mas ainda sem organização” antes da F5-03.
- **Alternativas:**
  - (A) estado dedicado “sem organização” — área funcional bloqueada com tela
    informativa (ex.: “aguarde o convite/atribuição de organização”);
  - (B) liberar o shell vazio (comportamento atual inconsistente);
  - (C) tratar como `acessoNegado` (indistinguível de conta sem perfil).
- **Recomendação:** (A) — mantém o usuário autenticado (pode sair/ver estado),
  não inventa tenant e dá caminho de produto claro; (C) perde o diagnóstico.
- **Impacto/risco:** novos estados no guard/rotas; baixo, mas precisa alinhar
  com F5-03 (que decide o switcher).
- **Seções dependentes:** 3 (G5), 7, 8, 9.1, 13, 14.

### Q3 — Conta autenticada sem user_profile (não provisionada): UX e mensagem — **FECHADA (alternativa B APROVADA)**

- **Decisão adotada (aprovada):** para a própria conta autenticada sem
  `user_profile`, usar mensagem neutra/orientativa de acesso ainda não
  provisionado; não expor detalhes internos de autorização. Os demais casos de
  acesso negado continuam genéricos.
- **Contexto:** `enable_signup=false`; a única via de criação é o convite. Mesmo
  assim, uma conta pode existir sem perfil (criação administrativa fora do
  fluxo, limpeza de dados). Hoje o usuário cai em `acessoNegado` com mensagem
  genérica FORBIDDEN + botão Sair.
- **Por que é necessária:** o contrato deve decidir se a mensagem genérica é
  suficiente ou se há valor em orientar o usuário legítimo sem vazar
  informações de provisionamento para terceiros.
- **Alternativas:**
  - (A) manter mensagem genérica (não diferencia “sem perfil” de “perfil
    inativo”); recomendação atual do código;
  - (B) mensagem neutra orientativa para o próprio usuário (“seu acesso ainda
    não foi liberado; fale com o administrador”), sem detalhar o motivo.
- **Recomendação:** (B) para o caso de **conta própria sem perfil** (sem
  vazamento: o dado pertence ao próprio usuário), mantendo (A) para os demais
  casos de acesso negado; validar tom com produto.
- **Impacto/risco:** apenas apresentação; nenhuma mudança de autorização.
- **Seções dependentes:** 7, 8, 13, 14.

### Q4 — Entrada com múltiplas memberships e fronteira com F5-03 — **FECHADA (alternativa A APROVADA)**

- **Decisão adotada (aprovada):** com múltiplas memberships ativas, nenhuma
  organização deve ser escolhida silenciosamente; é necessária **seleção
  explícita** antes do uso funcional. A seleção enviada pelo cliente é apenas
  intenção e sua validade deve ser confirmada contra as memberships soberanas.
  Persistência/UX/switcher ficam para F5-03.
- **Contexto:** um perfil pode ter N memberships ativas; o código resolve todas
  e **nunca** seleciona arbitrariamente. A F5-03 criará a “organização ativa”
  (switcher). A F5-01 precisa confirmar o princípio de entrada para não
  antecipar F5-03.
- **Por que é necessária:** decidir se a primeira entrada com N>1 exige seleção
  explícita (sem default mudo) e onde a escolha pode viver sem virar autoridade.
- **Alternativas:**
  - (A) seleção explícita obrigatória antes de qualquer rota funcional quando
    N>1; escolha é estado de UX validado no servidor a cada operação;
  - (B) escolher uma organização default (ordem de criação) sem seleção;
  - (C) permitir operar “sem organização” até escolher (sem conteúdo).
- **Recomendação:** (A) — coerente com a proibição atual de seleção arbitrária
  silenciosa e com “contexto do cliente não é prova”; a persistência/UX do
  switcher é decidida na F5-03.
- **Impacto/risco:** F5-01 só registra o princípio; nenhum código; alinhar com
  F5-03 para não duplicar estado.
- **Seções dependentes:** 4, 6, 7, 9.2 (F5-03), 12.

### Q5 — Evolução do `user_profile` e origem do nome exibido — **FECHADA (alternativa A APROVADA)**

- **Decisão adotada (aprovada):** manter `user_profile` mínimo nesta atividade;
  não criar `display_name`, preferências, idioma ou fuso agora. O nome exibido
  pode continuar usando o e-mail autenticado até a F5-02 avaliar o uso do
  colaborador vinculado como identidade de apresentação.
- **Contexto:** `user_profiles` tem apenas `id/status`; o nome exibido é o
  e-mail de `session.user` (`AuthStatus`, `LoginPage`). Não há “nome de
  exibição” do usuário Virtus, nem campos de preferência/idioma/fuso.
- **Por que é necessária:** o contrato F5-01 precisa dizer o que o perfil pode
  fornecer (ou não) para que F5-02+ não dependa de e-mail para exibir nome, nem
  duplique dados de `auth.users`.
- **Alternativas:**
  - (A) manter perfil mínimo (id/status) agora; exibição por e-mail do auth até
    haver contrato de perfil/preferências (fase posterior);
  - (B) adicionar agora `display_name` e afins ao `user_profiles` (migration +
    fluxo de edição).
- **Recomendação:** (A) — F5-01 não amplia schema; quando o vínculo
  usuário↔colaborador existir (F5-02), o nome a exibir pode vir do colaborador
  vinculado (domínio F3), sem duplicar em `user_profiles`. (B) fica para o
  contrato de preferências.
- **Impacto/risco:** definição de display-name fica pendente até F5-02; risco
  baixo porque hoje não há tela de perfil.
- **Seções dependentes:** 2.2, 3 (G9), 4, 5.1, 9.1.

---

## 18. Decisões arquiteturais (D1–D14 — FECHADAS)

| # | Decisão | Conteúdo | Status |
| --- | --- | --- | --- |
| D1 | Raiz de confiança | `auth.uid()` (id de `auth.users` exposto pela sessão JWT) é a raiz única; `user_profile.id = auth.uid()` (1:1); e-mail nunca é chave de vínculo | FECHADA |
| D2 | Sessão do provedor | Fonte de “quem autenticou” e de renovação/revogação; **não** é fonte de perfil interno, tenant ou autorização; claims (role/metadata) são transporte | FECHADA |
| D3 | Perfil interno | `user_profiles` é a fonte soberana de “conta habilitada no Virtus”; exigido `status='active'`; perfil ausente/inativo/desconhecido ⇒ bloqueio (fail-closed); nunca auto-provisionado em runtime. **(Q3 aprovada)** conta própria sem perfil exibe mensagem neutra/orientativa, sem expor detalhes internos; demais negados permanecem genéricos | FECHADA |
| D4 | Membership | `user_organization_memberships` (ativas) é a fonte dos tenants alcançáveis; pré-condição de operação funcional em tenant (contrato F4-08). **(Q2 aprovada)** zero membership ⇒ estado dedicado `semOrganizacao` (área funcional bloqueada). **(Q4 aprovada)** com N>1, nenhuma escolha silenciosa: seleção explícita validada no servidor | FECHADA |
| D5 | Fronteira conceitual | `AuthIdentity` (autenticação) × `user_profile` (conta Virtus) × `membership` (tenant) × `colaborador` (domínio F3) × `ActorContext` (ator do engine) — conforme §4 | FECHADA |
| D6 | Cliente nunca é fonte | Nenhum ID/claim/seleção vinda da UI prova identidade, tenant ou capability; tudo é revalidado no servidor (RLS + engine). **(Q4 aprovada)** a seleção de organização transportada pelo cliente é intenção, confirmada contra as memberships soberanas | FECHADA |
| D7 | ActorRef em runtime real | `actorId = user_profile.id (auth.uid())`; providers resolvem o colaborador vinculado por `(actorId, organizationId)` via `membership_collaborator_links`; `matricula` DEV nunca vira actorId fora do mundo DEV | FECHADA |
| D8 | Fail-closed universal | Todos os momentos do §8 bloqueiam por padrão; nenhum estado degrada para anônimo/simulado fora de DEV; área funcional exige `autenticado` **e** organização selecionada e validada (Q2/Q4 aprovadas) | FECHADA |
| D9 | DEV impersonação | Mantida exclusivamente em DEV (gate `simulacaoDevPermitida`); nunca altera `auth.uid()`/sessão; substituída gradualmente pelo fluxo real (F5-02/05), preservando o seed sintético | FECHADA |
| D10 | Mapeamento de status | Adapter de identidade passa a tratar **qualquer** status diferente de `active` como inativo (fail-closed) — corrige G7 | FECHADA |
| D11 | Falha transitória × revogação | **(Q1 aprovada — alternativa B)** a revalidação distingue sessão efetivamente inválida/revogada (401, ban, usuário removido) — **encerra o acesso** — de falha transitória de transporte/5xx — **mantém a sessão local e reintenta, sem logout automático**; nenhuma operação dependente de autorização/server-side é liberada durante indisponibilidade (fail-closed) | FECHADA |
| D12 | Zero-membership | **(Q2 aprovada — alternativa A)** profile ativo sem membership ativa ⇒ estado dedicado `semOrganizacao`: área funcional bloqueada, UX informativa, nenhum tenant inventado; não é shell funcional vazio; UX final de seleção pertence à F5-03 | FECHADA |
| D13 | Snapshot imutável | `AuthIdentity` é snapshot imutável por resolução; páginas não o mutam; re-resolução é o único caminho de atualização | FECHADA |
| D14 | Sem ampliação de schema na F5-01 | **(Q5 aprovada — alternativa A)** sem migration nesta atividade; `user_profiles` permanece mínimo (id/status); sem `display_name`, preferências, idioma ou fuso; o nome exibido segue do e-mail autenticado até a F5-02 avaliar o colaborador vinculado como identidade de apresentação; organização ativa fica para F5-03 | FECHADA |

> Compatibilidade verificada: todas as decisões D1–D14 foram revisadas contra as
> respostas aprovadas de Q1–Q5 e nenhuma permaneceu incompatível ou em aberto.

---

## 19. Confirmações desta atividade

- Revisão incorporada ao **mesmo documento**, na **mesma branch**
  (`docs/f5-01-contrato-identidade-autenticada`) e no **mesmo PR #159**.
- Q1–Q5 marcadas como **FECHADAS/APROVADAS**; as decisões adotadas foram
  incorporadas às seções dependentes (§1.2, §3, §6, §7, §8, §9, §10, §12, §13,
  §14, §15 e §16) — nenhuma questão foi removida do documento.
- D1–D14 revisadas e **fechadas**; nenhuma decisão ficou incompatível com as
  respostas aprovadas de Q1–Q5 (detalhe no §18).
- Nenhuma alteração funcional foi feita: o diff continua **somente documental**
  (`docs/F5-01-desenho-tecnico.md`).
- F5-02, F5-03, F5-04 e F5-05 permanecem fora do escopo de implementação desta
  atividade (§15) — aqui são definidos apenas contratos.
- Próximo passo: implementação do contrato da F5-01 (formalização de
  `AuthIdentity`, estados `semOrganizacao` e revalidação Q1, adapter fail-closed
  G7, mensagem Q3 e testes) em atividade separada, após aprovação do PR.

---

## Anexo A — Arquivos auditados (referência)

- `src/auth/`: `contratos.ts`, `tipos.ts`, `erros.ts`, `servico.ts`,
  `adaptadores.ts`, `cliente.ts`, `controladorSessao.ts`, `politicaSessao.ts`,
  `armazenamentoSessao.ts`, `AuthProvider.tsx`, `AuthContext.tsx`,
  `AuthStatus.tsx`, `LayoutAutenticado.tsx`, `rotasProtegidas.ts`,
  `LoginPage.tsx`, `RecuperarSenhaPage.tsx`, `RedefinirSenhaPage.tsx`,
  `ConvidarUsuarioPage.tsx`, `conviteAdministrativo.ts` e testes correlatos;
- `src/contexts/`: `UsuarioAtualProvider.tsx`, `UsuarioAtualContext.tsx`,
  `impersonacaoDev.ts`, `BrandingProvider.tsx`;
- `src/components/`: `UsuarioAtualBar.tsx`, `NavegacaoPrincipal.tsx`;
- `src/config/`: `ambiente.ts`, `README.md`; `src/infrastructure/supabase/`;
- `src/authorization/`: `policyEngine/*`, `mundoFuncional.ts`,
  `autorizacaoFuncional.ts`, `authorizationPolicy.ts`, `AuthorizationContext.ts`,
  `exceptionalAccess.ts`, `pilotAccess.ts`, `providers/*`, `ResourceContext.ts`,
  `Capability.ts`, `canonical.ts`, `authorizationError.ts`;
- `src/services/`: `colaboradorStorage.ts`, `resetBaseDesenvolvimento.ts`,
  `metaStorage.ts`, `cancelamentoAvaliacaoService.ts`,
  `reaberturaAvaliacaoService.ts`, `cancelamentoCicloService.ts`,
  `reaberturaCicloService.ts`, `correcaoPeriodoCicloService.ts`;
- `src/types/Colaborador.ts`, `src/errors/applicationErrors.ts`, `src/main.tsx`,
  `src/App.tsx`, `src/routes/AppRoutes.tsx`;
- `supabase/migrations/` (F1-03, F2-01..F2-07, F4-01/02, F4-08 completos);
- `supabase/functions/convidar-usuario/index.ts`, `gerenciar-usuario/index.ts`;
- `supabase/config.toml`, `supabase/seed.sql`, `.env.example`, `package.json`;
- `docs/F4-03-desenho-tecnico.md`, `docs/F4-08-desenho-tecnico.md`,
  `docs/F4-09-desenho-tecnico.md` (contratos F3/F4 que F5-01 respeita).
