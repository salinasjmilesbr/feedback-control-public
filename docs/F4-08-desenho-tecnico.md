# F4-08 — Contrato arquitetural: RLS base e isolamento real entre tenants (Issue #95)

> **Status:** **CONTRATO ARQUITETURAL FECHADO** — revisão arquitetural concluída.
> **D1–D22 CLOSED / APPROVED** (§25) e **Q1–Q8 CLOSED / ANSWERED** (§26).
> Nenhuma implementação: sem código, migration, policy RLS, helper SQL, grant,
> view ou alteração de TypeScript nesta atividade. A **Issue #95 permanece
> aberta**; a **PR #153 é somente de documentação**; **sem merge**.

## 1. Objetivo, princípio e fronteira final

### 1.1 Objetivo (Issue #95)

Levar a autorização essencial à **fronteira do banco**: usuário autenticado de
uma organização não lê/insere/altera/exclui dados de outra — mesmo manipulando o
frontend, o `organizationId` enviado, a API direta do Supabase, IDs de outro
tenant, filtros ou tabelas filhas/relações indiretas. RLS resolve por
**identidade autenticada + membership persistida ativa**; nunca por filtro de
frontend.

### 1.2 Fronteira final Policy Engine × RLS (consolidada)

- **RLS responde:** "esta identidade autenticada possui membership ativa para
  tocar dados deste tenant?" (fronteira estrutural de tenant);
- **Policy Engine responde:** "esta identidade pode executar esta capability
  específica sobre este recurso?" (autorização funcional fina);
- **RLS NÃO concede capability**; **Policy Engine NÃO substitui o isolamento de
  banco**;
- F4-05/F4-06/F4-07 **nunca furam tenant boundary**; RLS não portará
  DIRECT_REPORTS/DESCENDANTS/ASSIGNED/scopes/capabilities para SQL nesta fase.

### 1.3 Fora de escopo

policies de entidades funcionais ainda em localStorage (F5); produção;
observabilidade externa. A F4-08 desenha a **base de RLS** sobre as tabelas
estruturais/autorizativas **já criadas** (F2/F3/F4-01/F4-02).

## 2. Estado atual real (inventário verificado)

- Supabase local + 19 migrations PostgreSQL; storage desabilitado; 2 Edge
  Functions server-side (`convidar-usuario`, `gerenciar-usuario`,
  `verify_jwt=false` + allowlist `INVITE_ADMIN_USER_IDS` — transitório).
- **28 tabelas `public.*`**, todas com `enable row level security`; **nenhuma
  FORCE**; **3 policies de identidade (estado final)** — `user_profiles_select_
  own` (auth.uid() = id AND status='active'), `user_organization_memberships_
  select_own` (user_profile_id = auth.uid()),
  `organizations_select_via_membership` (EXISTS membership ativa). As outras 25
  deny-by-default. Grants: SELECT→authenticated em 3 tabelas de identidade;
  EXECUTE→service_role em 4 funções DEFINER.
- **Visão física exata:** 22 tabelas com `organization_id NOT NULL`; 1 nullable
  (`access_roles`); 5 sem a coluna (`organizations`, `user_profiles`,
  `capabilities`, `access_role_capabilities`, `collaborator_status_periods`).
- **Views:** nenhuma. **Storage:** nenhum. **Tipos gerados:** nenhum.
- **31 funções `public.*`**; nenhuma usa `auth.uid()` (todas recebem ator por
  parâmetro; auth.uid() só nas policies). **4 SECURITY DEFINER** (service_role-
  only, search_path public); **27 INVOKER** (11 triggers + 16 resolvers/RPC)
  com EXECUTE default PUBLIC.
- Runtime TS: único acesso direto via supabase-js em `src/auth/adaptadores.ts`
  (3 SELECTs de identidade). Zero service_role/admin em `src`. Domínio
  funcional em localStorage (pré-F5).

## 3. Fonte soberana de tenant (D1 — fechada)

Fonte soberana de "quais tenants este usuário pode acessar":

```
auth.uid()
+ user_profile válido/ativo (user_profiles.status = 'active')
+ membership persistida ativa (user_organization_memberships.status = 'active')
```

Nunca como prova de autorização: `organizationId` do frontend, claims JWT de
tenant, user metadata, cargo/job_role, parâmetros arbitrários do caller.
Multi-tenant permitido apenas quando o mesmo user_profile tem memberships ativas
distintas (sem estado de "tenant atual" no banco). Cross-tenant = DENY
fail-closed.

## 4. Multi-tenant

Schema já suporta 1 user_profile → N memberships (unique por par). RLS resolve
por linha/consulta via membership ativa do `auth.uid()`. Nenhuma suposição de
"1 usuário = 1 tenant".

## 5. Inventário de tabelas (matriz real) e políticas por operação

28 tabelas. Classificação por domínio (cada tabela em uma categoria; soma 28):
**A)** 13 tenant-rooted diretas estruturais; **B)** 1 indireta
(`collaborator_status_periods`); **C)** 1 raiz (`organizations`); **D)** 2
identidade; **E)** 4 auditoria/histórico/snapshot; **F)** 7 segurança
(F4-01/F4-02).

> Convenção: **SELECT** permitido = leitura own-tenant via membership ativa
> (policy `<tabela>_select_same_tenant`); **INSERT/UPDATE/DELETE** =
> "não (authenticated)" = apenas por função/RPC transacional ou fechado; quando
> CRUD direto existir, exige contrato explícito + WITH CHECK/FK coerente (D7).

### 5.1 Identidade e raiz (D) — operações fechadas

| Tabela | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `user_profiles` | próprio profile ativo (policy atual) — sem ampliar | não (Auth/Edge/RPC) | não (Auth/Edge/RPC) | não |
| `user_organization_memberships` | próprias memberships (contrato atual); **sem enumerar memberships de terceiros** | não (caminho administrativo) | não | não |
| `organizations` | somente onde há membership ativa (policy atual) | não | não | não (administração = fluxo confiável separado) |

### 5.2 A — tenant-rooted estruturais (13) — operações fechadas

| Tabela | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `collaborators` | own-tenant (sim) | não agora (RPC/transação) | não agora | não agora |
| `collaborator_identifiers` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `job_roles` / `seniority_levels` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `organizational_units` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `organizational_unit_parent_periods` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `organizational_positions` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `position_reporting_lines` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `occupations` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `temporary_responsibilities` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `collegiate_configurations` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `collegiate_configuration_members` | own-tenant (sim) | via RPC/transação | via RPC/transação | via RPC/transação |
| `cycle_evaluation_responsibilities` | own-tenant (sim) | somente RPC F3-09 | somente RPC F3-09 | não |

Regras fechadas (D5/D7/D15): membership ativa dá **visibilidade estrutural BASE
do próprio tenant** (para resolução de hierarquia); RLS não implementa
DIRECT_REPORTS/DESCENDANTS/ASSIGNED/scopes (continuam no Policy Engine).
Mutações estruturais/temporais que preservam invariantes ficam em
**funções/RPCs transacionais**; nenhuma policy ampla de escrita direta por
membership; CRUD direto apenas p/ entidades simples com contrato explícito.

### 5.3 B — child/indirect (sem organization_id)

`collaborator_status_periods`: SELECT own-tenant via `EXISTS` em
`collaborators` do tenant (D6); INSERT/UPDATE/DELETE via RPC/transação.
Fail-closed se parent inexistente/FK órfã/inconsistente (sem acesso).

### 5.4 E — auditoria/histórico/snapshot (4) — operações fechadas

| Tabela | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `collegiate_cycle_snapshots` | own-tenant (leitura estrutural) | somente RPC materializar | não | não |
| `collegiate_cycle_snapshot_positions` | own-tenant | somente RPC materializar | não | não |
| `collegiate_cycle_snapshot_members` | own-tenant | somente RPC materializar | não | não |
| `evaluation_succession_events` | **não nesta fase** (auditoria fechada; fluxo futuro com capability) | somente RPC registrar_sucessao (endurecida) | não | não |

F3-08/F3-09 soberanos (D15): RLS protege tenant; membership não autoriza
reescrita histórica; sem UPDATE/DELETE direto por authenticated.

### 5.5 F — segurança/autorização (7) — exposição mínima (D13)

| Tabela | SELECT | INSERT | UPDATE | DELETE |
| --- | --- | --- | --- | --- |
| `capabilities` | **authenticated read-only** (global — D12) | não | não | não |
| `access_roles` | **não** por membership comum (mínimo; system org NULL não é wildcard — §7) | não (RPC adm.) | não | não |
| `access_role_capabilities` | **não** por membership comum | não | não | não |
| `membership_access_role_assignments` | **não** por membership comum | não (RPC conceder_acesso_role) | não (RPC revogar_acesso_role) | não |
| `membership_collaborator_links` | **não** por membership comum | não | não | não |
| `access_role_assignment_scopes` | **não** por membership comum | não | não | não |
| `access_role_assignment_unit_targets` | **não** por membership comum | não | não | não |

Exposição de leitura a authenticated somente quando houver caso funcional
explícito (decisão por tabela na implementação); escrita exclusivamente por
caminho administrativo controlado. `resolver_capabilities_efetivas` permanece
DEFINER service_role-only (não expor).

## 6. Policies por operação (detalhe obrigatório)

- **SELECT** — own-tenant (membership ativa) nas tabelas marcadas; condição via
  helper único/EXISTS (não "same tenant" genérico sem operação);
- **INSERT** — WITH CHECK que exige org da linha ∈ orgs ativas do caller **e**
  parent FK (se houver) no mesmo tenant (anti FK poisoning); quando "via RPC",
  nenhuma policy de INSERT para authenticated;
- **UPDATE** — USING (linha-alvo own-tenant) **e** WITH CHECK (linha-nova:
  org inalterada para outra tenant; parent FK não trocado para outro tenant);
- **DELETE** — USING own-tenant; fechado onde indicado (append-only/imutável);
- granularidade por comando (D18), naming `<tabela>_<cmd>_same_tenant` (ou
  sufixo específico: `_via_rpc`, `_system`), nunca `FOR ALL` amplo com semânticas
  diferentes.

## 7. access_roles com organization_id NULL (não é wildcard)

`access_roles.organization_id NULL` = **role de sistema** (contrato F4-01,
`is_system=true`); **não** é wildcard e **não** permite que qualquer membership
leia todas as roles system/custom automaticamente. Policy/exposição mínima
coerente com D13: leitura de roles apenas por caso funcional explícito (gestão
com capability), tratando system (org NULL) e custom (org própria) com regras
explícitas — sem "NULL = qualquer org".

## 8. Child tables / FK poisoning

Para qualquer INSERT/UPDATE de child: **não basta membership no org da linha** —
se houver parent FK, o parent deve pertencer ao mesmo tenant. Cross-tenant
parent swap = DENY. Isto aparece explicitamente na matriz de policies e nos
testes (WITH CHECK no INSERT/UPDATE e testes 18/19 da matriz). Para tabelas
existentes sem org (B), policies usam EXISTS/JOIN via parent tenant-rooted e
falham fechadas se parent inexistente/órfã/inconsistente (D6). Novas tabelas:
preferir `organization_id NOT NULL` direto quando fizer sentido + FK/constraint
que impeça inconsistência child×parent (D3) — sem denormalização oportunista da
F3 nesta fase.

## 9. Helpers SQL e grafo de dependência (D4)

- **Minimizar helpers.** `auth.uid()` já representa diretamente o user_profile
  no modelo atual. NÃO criar `current_user_profile_id()` nem
  `current_user_organization_ids()` automaticamente.
- Criar, no máximo, um único helper conceitual
  `user_has_active_membership(organization_id)` **somente se a implementação
  comprovar** que reduz repetição, não cria recursão, mantém legibilidade e
  performance. Se criado: SECURITY INVOKER, STABLE, `set search_path = public`,
  sem SECURITY DEFINER, sem ciclo de RLS.
- **Grafo final de dependências (acíclico):**
  1. `user_profiles` policy → somente `auth.uid()` (+ status);
  2. `user_organization_memberships` policy → somente `auth.uid()`;
  3. demais tabelas → policy usa membership (direta ou via helper único) —
     **membership é a raiz**; nenhuma policy de membership consulta tabela que
     consulta membership. Sem ciclo.

## 10. SECURITY DEFINER — inventário dos 4 existentes (D9)

| Função | Por que existe | EXECUTE atual | search_path | Role chamadora | Risco | Decisão |
| --- | --- | --- | --- | --- | --- | --- |
| `criar_perfil_membership` | criar perfil+membership atom | service_role | public | Edge/service | médio | **mantém** (endurecido: sem ampliar EXECUTE) |
| `conceder_acesso_role` | atribuir role | service_role | public | Edge/service | médio | **mantém** (endurecido; autorização do ator a validar no chamador) |
| `revogar_acesso_role` | revogar role | service_role | public | Edge/service | médio | **mantém** (endurecido; registrar revogador — dívida F4-06) |
| `resolver_capabilities_efetivas` | resolver caps p/ serviço | service_role | public | service | médio (lê qualquer par) | **mantém** (nunca ampliar EXECUTE) |

Regras: **nenhum NOVO SECURITY DEFINER na F4-08**; DEFINER proibido como atalho
para contornar RLS; os 4 são necessários, com EXECUTE restrito + search_path
explícito + chamador service_role e sem bypass cross-tenant → **mantém** (com
revisão na implementação). Qualquer novo no futuro exige decisão arquitetural
específica.

## 11. Funções INVOKER (27) — classificação individual (D11)

**11 triggers (plpgsql INVOKER)** — internas, não são RPC do cliente:

| Função | EXECUTE atual | authenticated deve chamar? | Ação F4-08 |
| --- | --- | --- | --- |
| `set_updated_at` | n/a (trigger) | não | internal only |
| `enforce_position_reporting_lines_within_positions` | n/a | não | internal only (+ FOUND/§12) |
| `enforce_position_reporting_lines_no_cycle` | n/a | não | internal only |
| `enforce_positions_close_without_open_reporting_lines` | n/a | não | internal only |
| `enforce_occupation_within_position` | n/a | não | internal only (+ FOUND/§12) |
| `enforce_collaborator_inactive_requires_closed_occupations` | n/a | não | internal only |
| `enforce_temporary_responsibility_within_position` | n/a | não | internal only (+ FOUND/§12) |
| `enforce_temporary_responsibility_not_self` | n/a | não | internal only |
| `enforce_collegiate_configuration_member_not_self` | n/a | não | internal only |
| `enforce_membership_role_within_organization` | n/a | não | internal only (+ `set search_path`) |
| `enforce_unit_target_scope_type` | n/a | não | internal only (+ `set search_path`) |

**16 resolvers/RPC INVOKER (sql/plpgsql STABLE/VOLATILE)** — hoje EXECUTE
default PUBLIC; **ação F4-08: REVOKE EXECUTE FROM PUBLIC** e grant explícito
somente às roles necessárias (não confiar em "hoje é seguro porque RLS bloqueia
tudo"):

| Função | Tipo | EXECUTE atual | authenticated deve chamar? | Ação F4-08 |
| --- | --- | --- | --- | --- |
| `organizacao_resolver_responsavel_posicao` | resolver sql STABLE | PUBLIC | não (chamada interna/futura) | revoke PUBLIC; grant conforme uso interno |
| `organizacao_resolver_gestor_direto` | resolver | PUBLIC | não | revoke PUBLIC |
| `organizacao_resolver_subordinados_diretos` | resolver | PUBLIC | não | revoke PUBLIC |
| `organizacao_resolver_descendentes` | resolver | PUBLIC | não | revoke PUBLIC |
| `organizacao_resolver_cadeia` | resolver | PUBLIC | não | revoke PUBLIC |
| `organizacao_resolver_escopo_posicoes` | resolver | PUBLIC | não | revoke PUBLIC |
| `organizacao_resolver_escopo_unidades` | resolver | PUBLIC | não | revoke PUBLIC |
| `organizacao_resolver_responsavel_avaliativo_posicao` | resolver | PUBLIC | não | revoke PUBLIC |
| `organizacao_resolver_avaliador_avaliado` | resolver | PUBLIC | não | revoke PUBLIC |
| `resolver_responsavel_avaliacao_vigente` | resolver | PUBLIC | não | revoke PUBLIC |
| `resolver_collaborador_vinculado` | resolver | PUBLIC | não | revoke PUBLIC |
| `resolver_capabilities_escopos_efetivas` | resolver | PUBLIC | não | revoke PUBLIC |
| `resolver_alvos_escopo` | resolver | PUBLIC | não | revoke PUBLIC (branches ORG/UNIT exigem tenant do chamador) |
| `materializar_colegiado_ciclo` | RPC escrita | PUBLIC | não (caminho transacional) | revoke PUBLIC; service_role/caminho autorizado |
| `materializar_responsabilidades_avaliacao` | RPC escrita | PUBLIC | não | revoke PUBLIC; service_role/caminho autorizado |
| `registrar_sucessao_avaliador` | RPC escrita | PUBLIC | **não (crítico — §12)** | revoke PUBLIC; endurecer tenant (§12) |

## 12. Achados de segurança — correções obrigatórias na futura implementação

1. **`registrar_sucessao_avaliador` (sem organization explícito).** Correção
   técnica recomendada conforme schema real: a RPC recebe
   `p_responsibility_ids` keyed por `cycle_evaluation_responsibilities.id`
   (que tem `organization_id` e FK composta p/ snapshot). A implementação deve
   validar que **todas** as responsabilidades informadas pertencem ao mesmo
   `organization_id` e correlacionar o tenant do snapshot/posição de forma
   soberana (derivado do banco, não do chamador), negando qualquer chamada que
   produza sucessão cross-tenant ou opere entidade sem tenant soberanamente
   correlacionado (fail-closed). Nenhuma solução é inventada aqui — a correção
   exata (ex.: derivar org pela responsabilidade e exigir consistência entre
   ids; ou adicionar parâmetro de org validado contra as responsabilidades) é
   definida na implementação com testes cross-tenant.
2. **Triggers F3-04/F3-05/F3-06 sem `FOUND` check.** Quando a consulta de
   parent/tenant não encontrar linha, o trigger deve **falhar fechado** (raise),
   nunca continuar com variável NULL/estado parcial — sem inconsistência
   silenciosa (ex.: `enforce_occupation_within_position`,
   `enforce_temporary_responsibility_within_position`,
   `enforce_position_reporting_lines_within_positions` e correlatos).
3. **Funções INVOKER com EXECUTE PUBLIC** — entram formalmente na superfície de
   endurecimento da F4-08 conforme D11 (§11), com REVOKE/GRANT por função e sem
   depender do "RLS bloqueia tudo" atual.

## 13. F4-05/F4-06/F4-07 × RLS (D22)

Temporary responsibility, exceptional access (C) e Pilot Full Access (D):
nenhum fura tenant boundary; todos operam no tenant válido. **Não criar tabelas
C/D agora.** Quando F4-06/F4-07 tiverem persistência real (F5/F4-09+),
requisito vinculante: sempre `organization_id`, tenant-scoped, beneficiary
coerente com membership, RLS própria, leitura mínima, escrita via fluxo
administrativo, sem wildcard cross-tenant. D jamais desabilita RLS.

## 14. Service role / anon / authenticated (D17)

- **service_role:** somente server-side (Edge Functions) e tooling local;
  nunca no bundle/frontend; nunca solução de autorização funcional;
- **anon:** sem acesso a dados privados (deny-by-default; sem grants novos);
- **authenticated:** apenas operações explicitamente necessárias, com a
  combinação correta **GRANT necessário + RLS policy necessária** por operação;
  sem DML amplo só porque existe RLS;
- least privilege; cada operação exige ambos (GRANT + policy).

## 15. FORCE ROW LEVEL SECURITY (D10 — fechado)

**F4-08 NÃO usa FORCE RLS.** Objetivo atual: proteger anon/authenticated e o
cliente Supabase. Table owner/service_role permanecem trust boundaries
privilegiadas. FORCE poderá ser reavaliado apenas quando existir arquitetura
backend/produção definitiva. (Sem texto "a decidir".)

## 16. Estratégia de migration (D21 — contrato vinculante)

Implementação futura **versionada e incremental** (não monolítica), por grupos
coerentes; cada etapa deixa o banco **igual ou mais restritivo**; nunca janela
intermediária cross-tenant permissiva; "policy pronta antes de conceder o acesso
correspondente". Ordem a adaptar ao schema:

1. fundação/helpers mínimos (D4);
2. grants/revokes de funções (D11);
3. identity/membership (D8);
4. tenant roots (`organizations`/`collaborators`/catálogos org);
5. F3 structural roots (unidades/posições/reporting/occupations/
   temporary_responsibilities);
6. child/indirect (`collaborator_status_periods`, `access_role_capabilities`);
7. security tables (D13);
8. history/audit (D14/D15);
9. global catalogs (`capabilities` read-only — D12);
10. testes/validation.

Padrão por tabela (fail-closed): helpers → `ENABLE RLS` → policies por comando
→ grants mínimos → índices; deny-by-default intermediário é seguro; testes
negativos antes de policies confirmam bloqueio.

## 17. Novas tabelas futuras (D16)

Regra obrigatória: **nenhuma nova tabela tenant-specific entra sem**: `ENABLE
RLS`; decisão explícita de tenant ownership; policy adequada; teste cross-tenant;
FK/`organization_id` coerente. Mecanismos: **(1) teste automatizado de schema**
(detectar tabela tenant-specific sem RLS; tabela registrada como tenant-specific
sem policy correspondente; violações do catálogo esperado) e **(2) checklist
obrigatório de PR**.

## 18. Views/RPC futuras (D19)

Views futuras com `security_invoker` quando aplicável; nunca view que bypassa RLS
silenciosamente. RPCs SECURITY INVOKER por padrão; DEFINER só por exceção
arquitetural explícita. Toda função: search_path explícito quando relevante,
grants explícitos, threat model e teste cross-tenant.

## 19. Matriz de testes (atualizada para as decisões fechadas)

Casos já previstos (usuário A lê A / não lê B; ID direto B; não insere org B;
não altera org A→B; não troca parent FK p/ B; não atualiza/exclui linha B;
membership inativa; profile inválido; auth.uid sem profile; múltiplas
memberships; child sem org via parent; join/count/view/RPC não vazam; INSERT/
UPDATE child com parent B → DENY; F4-05/06/07 não furam; orgId manipulado;
organization própria visível / outra invisível; tabela global conforme contrato;
security table fechada; audit não altera/apaga; histórico não reescrito; anon
sem acesso; authenticated sem membership; service role fora do bundle; policy
recursion ausente; dados incompletos fail-closed; tenant null seguro; FK órfã;
capability depende do Policy Engine; RLS não concede capability; bypass por
filtro falha) **e acrescenta**:

- authenticated chama função INVOKER não autorizada → permission denied;
- função explicitamente liberada continua obedecendo RLS;
- trigger com parent inexistente → fail-closed (raise);
- `registrar_sucessao_avaliador` não opera cross-tenant;
- `access_roles.organization_id NULL` não vira wildcard (role de sistema não
  legível por membership comum);
- `capabilities` global SELECT funciona; DML em capabilities falha;
- `organizations` UPDATE direto falha;
- `user_organization_memberships` INSERT/UPDATE/DELETE direto falha;
- `user_profiles` UPDATE direto falha;
- child parent swap A→B falha;
- membership ativa em A+B permite A e B e não C;
- membership inativa remove acesso;
- service_role não aparece no bundle/frontend;
- nenhum novo SECURITY DEFINER (teste de schema);
- schema CI detecta tabela tenant-specific futura sem RLS/policy.

## 20. Threat model (atualizado)

| Ameaça | Mitigação | Teste |
| --- | --- | --- |
| EXECUTE PUBLIC em funções INVOKER | REVOKE/GRANT por função (D11) | authenticated chama não autorizada → denied |
| `access_roles` system org NULL | NULL = global/system (F4-01), não wildcard; exposição mínima | NULL não vira wildcard |
| Parent FK poisoning (child swap A→B) | FK composta + WITH CHECK (USING/WITH CHECK) | swap A→B falha |
| Trigger sem FOUND | fail-closed (raise) nos triggers F3-04/05/06 | parent inexistente → raise |
| Sucessão sem tenant explícito | `registrar_sucessao_avaliador` endurecida (§12) | cross-tenant → DENY |
| Policy helper recursion | grafo acíclico; membership = raiz (§9) | policy recursion ausente |
| Global table accidental write | `capabilities` read-only | DML em capabilities falha |
| IDOR/enumeração/INSERT cross-tenant/update org swap/RPC/view bypass/DEFINER mal configurado/search_path/service role vazada/tabela esquecida/nova tabela sem RLS/nova FK cross-tenant | conforme §3/§8/§10/§14/§17/§18 | matriz §19 |

## 21. Riscos, dependências e itens fora de escopo

- **Riscos (mitigações fechadas):** policy mal escrita abre tenant (grafo
  acíclico + testes); funções INVOKER virando superfície (D11 §11); sucessão
  cross-tenant (endurecida §12); triggers NULL silencioso (fail-closed §12);
  recursão (grafo §9); performance de EXISTS (índices); drift futuro.
- **Dependências:** F2 (identidade/membership), F3-01..F3-09 (tabelas),
  F4-01/F4-02 (segurança), Policy Engine F4-03..F4-07 (autorização funcional),
  Supabase local + `supabase/validacao` (testes), F5 (domínios funcionais).
- **Fora de escopo:** implementação, policies de domínios localStorage (F5),
  produção, observabilidade, FORCE RLS, novos SECURITY DEFINER, tabelas C/D.

## 22. Contrato arquitetural fechado (resumo)

**RLS (tenant boundary):** `auth.uid()` + profile ativo + membership ativa ⇒
operar dados deste tenant; nunca cross-tenant; policies por comando; SELECT
own-tenant onde indicado; mutações estruturais/segurança/auditoria via RPC
controlada; sem escrita ampla por membership; sem FORCE RLS; sem novo SECURITY
DEFINER; capabilities read-only; access_roles system NULL ≠ wildcard; grants
mínimos; helpers minimizados (máx. `user_has_active_membership` condicionado);
membership = raiz do grafo acíclico; RLS nunca concede capability.
**Policy Engine:** capability/scope/hierarchy/ASSIGNED/temporary/exceptional/
pilot/DOMAIN_STATE — autorização funcional. **Achados de segurança** (§12)
entram no escopo da implementação. Migração incremental, igual-ou-mais-
restritiva, tests reais locais (SQL + Supabase local + positivos/negativos) sem
Supabase remoto. F4-08 cobre as 28 tabelas já criadas; domínios localStorage =
F5; persistências C/D = F5/F4-09+.

## 23. Decisões — D1–D22 (todas CLOSED / APPROVED; regra fechada, nenhuma em aberto)

1. **D1 Fonte soberana:** auth.uid + profile ativo + membership ativa; sem
   orgId do frontend/claims/metadata/cargo/parâmetros; multi-tenant por
   memberships distintas; cross = DENY.
2. **D2 Escopo:** tabelas estruturais/autorizativas já existentes (F2/F3/
   F4-01/F4-02); sem antecipar tabelas localStorage (F5); regra de engenharia
   + teste de schema p/ futuras.
3. **D3 org direto vs indireto:** novas tabelas preferem org NOT NULL direto +
   FK/constraint anti-inconsistência; não alterar schema das existentes só p/
   facilitar RLS; sem denormalização oportunista.
4. **D4 Helpers:** minimizar; NÃO criar current_user_profile_id/
   current_user_organization_ids; `auth.uid()` = user_profile; máximo 1 helper
   `user_has_active_membership(organization_id)` se comprovar benefício
   (INVOKER, STABLE, search_path, sem recursão/DEFINER).
5. **D5 SELECT F3:** membership ativa ⇒ visibilidade estrutural base do próprio
   tenant (RLS responde "pertence a este tenant?"); RLS não implementa
   DIRECT_REPORTS/DESCENDANTS/ASSIGNED/scopes/capabilities.
6. **D6 child/indirect:** EXISTS/JOIN via parent tenant-rooted; sem alterar
   schema p/ evitar EXISTS; fail-closed p/ parent inexistente/órfã/
   inconsistente; novas tabelas seguem D3.
7. **D7 INSERT/UPDATE/DELETE F3:** RLS ≠ "qualquer membro escreve qualquer
   linha"; mutações estruturais via RPC transacional; sem policies amplas de
   escrita; CRUD direto só com contrato explícito.
8. **D8 Identidade:** authenticated sem escrita direta em user_profiles/
   organizations/memberships; criação/desativação via Auth/Edge/RPC/backend;
   SELECT conforme contrato.
9. **D9 SECURITY DEFINER:** nenhum novo; proibido como atalho p/ RLS; os 4
   existentes mantidos (necessários, EXECUTE restrito, search_path, service_role
   only) com revisão; futuro exige decisão.
10. **D10 FORCE RLS:** NÃO aplicar na F4-08; reavaliar só com backend/produção
    definitiva.
11. **D11 Funções INVOKER:** REVOKE EXECUTE FROM PUBLIC nas que não precisam ser
    públicas + GRANT explícito; documentar por função (§11); não confiar em RLS
    atual; triggers internos seguem funcionais sem RPC ao cliente.
12. **D12 capabilities global:** SELECT authenticated read-only; sem DML; saber
    capability não a concede.
13. **D13 Tabelas de segurança:** membership simples não lê access_roles/grants/
    scopes/assignments; exposição mínima; escrita por caminho administrativo.
14. **D14 Auditoria:** append-only; authenticated comum sem UPDATE/DELETE; sem
    SELECT genérico nesta fase (fluxo futuro com capability); INSERT via
    RPC/serviço confiável; membership ≠ permissão de auditoria.
15. **D15 Histórico/snapshots:** F3-08/09 soberanos; RLS protege tenant;
    membership não reescreve; leitura own-tenant conforme necessidade; escrita
    só por caminhos materiais/transacionais; sem UPDATE/DELETE direto.
16. **D16 Novas tabelas:** teste de schema + checklist de PR; nenhuma tabela
    tenant-specific sem ENABLE RLS + tenant ownership + policy + teste
    cross-tenant + FK/org coerente.
17. **D17 Grants:** least privilege; GRANT + policy por operação; anon sem dados
    privados; authenticated mínimo; service_role server-side.
18. **D18 Granularidade:** policies por comando (SELECT/INSERT/UPDATE/DELETE);
    sem "FOR ALL" amplo; naming `<tabela>_<cmd>_same_tenant` adaptado.
19. **D19 Views/RPC futuras:** security_invoker; sem bypass; RPC INVOKER por
    padrão; DEFINER por exceção; search_path/grants/threat/teste por função.
20. **D20 Testes:** testes REAIS de RLS (SQL/policy + Supabase local +
    positivos/negativos + schema/config); mocks unitários insuficientes; sem
    Supabase remoto.
21. **D21 Migration:** incremental por grupos, fail-closed, sem big bang e sem
    janela permissiva; "policy antes de conceder acesso"; ordem §16.
22. **D22 Persistências C/D:** quando existirem (F5/F4-09+): org sempre,
    tenant-scoped, beneficiary+membership, RLS própria, leitura mínima, escrita
    administrativa, sem wildcard; não criar tabelas C/D agora.

## 24. Questões — Q1–Q8 (todas CLOSED / ANSWERED; sem pendências)

- **Q1 Escopo:** entram as tabelas estruturais/autorizativas existentes
  (F2/F3/F4-01/F4-02 e relacionadas materializadas); domínios localStorage = F5.
- **Q2 Funções transacionais:** mutações que preservam invariantes temporais/
  histórico/sucessão/estrutura/segurança/concessões permanecem em RPC/
  transação; CRUD direto só p/ entidades simples com contrato explícito.
- **Q3 Escrita F3:** preferir RPC/transação; CRUD direto na F5 só com Policy
  Engine + RLS + WITH CHECK + FKs; sem DML amplo de F3 agora.
- **Q4 Leitura F3 por membro:** sim (estrutura básica do próprio tenant);
  scopes/hierarchy continuam no Policy Engine.
- **Q5 Auditoria legível por quem:** nesta fase não por membership comum;
  auditoria fechada p/ leitura genérica do cliente; fluxos futuros com
  capability.
- **Q6 Edge Functions/allowlist:** caminho administrativo transitório; não é
  fonte soberana; não reutilizar p/ RLS; não redesenhar na F4-08.
- **Q7 capabilities legível:** sim, SELECT authenticated read-only.
- **Q8 FORCE RLS:** não aplicar nesta fase; reavaliar com backend/produção.

## 25. Confirmações desta atividade

Nenhum código, migration, policy RLS, helper SQL, grant ou view foi produzido —
somente `docs/F4-08-desenho-tecnico.md`. Issue #95 permanece aberta (PR sem
`Closes`). Sem merge.

## 26. Implementação — registro de entrega (Issue #95, PR #154)

> **Status:** implementado e validado no Supabase local; **PR #154 (Closes #95)**
> aberto, **sem merge**. Contrato D1–D22/Q1–Q8 (§23/§24) seguido integralmente.
> Nenhum FORCE RLS, nenhum novo SECURITY DEFINER, sem service role no cliente,
> sem Supabase remoto.

### 26.1 Migrations (incrementais, igual-ou-mais-restritivas)

1. `20260908100000_f4_08_helpers_function_grants.sql` — helper único +
   revoke/grant das funções INVOKER.
2. `20260908110000_f4_08_rls_select_own_tenant.sql` — policies SELECT own-tenant
   + grants.
3. `20260908120000_f4_08_capabilities_read_only.sql` — capabilities global
   read-only.
4. `20260908130000_f4_08_hardening.sql` — `registrar_sucessao_avaliador` +
   triggers + role lookup fail-closed.
5. `20260908140000_f4_08_revoke_excess_table_privileges.sql` — least privilege de
   tabela (revoga TRUNCATE/TRIGGER/REFERENCES/etc. de anon/authenticated) +
   default privileges endurecidos.
6. `20260908150000_f4_08_organizations_profile_active.sql` — `organizations`
   passa a exigir profile ativo (D1 completa).

### 26.2 Helper

`public.user_has_active_membership(uuid)` — SECURITY INVOKER, STABLE,
`set search_path = public`, sem DEFINER e sem recursão. Verifica a fronteira
soberana D1 COMPLETA: `auth.uid()` + user_profile ATIVO + membership ATIVA
(`join user_profiles` com `status='active'`). Grafo acíclico: consulta somente
`user_profiles` e `user_organization_memberships`, cujas policies usam apenas
`auth.uid()` (nenhuma chama o helper). EXECUTE somente a `authenticated`
(revoke de `public, anon`). Profile inativo ⇒ `false` (fail-closed).

### 26.3 Policies (18 novas → 21 no total)

- SELECT own-tenant (`<tabela>_select_same_tenant`) em 13 tabelas estruturais
  (A) + 3 snapshots F3-08 (E) + `collaborator_status_periods` (B, via EXISTS em
  `collaborators`);
- `capabilities_select_authenticated` (catálogo global read-only);
- `organizations_select_via_membership` reescrita para usar o helper (profile
  ativo + membership ativa; a versão F2-03 foi removida, sem OR de policies);
- 7 tabelas fechadas permanecem sem policy (6 de segurança F4-01/F4-02 +
  `evaluation_succession_events` de auditoria).

### 26.4 Grants/revokes (least privilege)

- 16 funções INVOKER de resolução/RPC (F3-07/F3-09/F4-02): `revoke execute from
  public, anon, authenticated` + `grant execute to service_role`.
- `revoke all on all tables/sequences in schema public from anon, authenticated`
  + regrant SELECT a `authenticated` somente nas 21 tabelas legíveis (remove
  TRUNCATE/TRIGGER/REFERENCES/INSERT/UPDATE/DELETE herdados por default
  privileges).
- Default privileges de `postgres` endurecidos (tables/sequences/functions sem
  grant a anon/authenticated). `supabase_admin`: limitação documentada (ver
  §26.8) — mitigada pelo schema guard de privilégios efetivos no CI.
- 4 SECURITY DEFINER existentes mantidos (EXECUTE `service_role`, sem ampliar).

### 26.5 Hardening de funções/triggers

- `registrar_sucessao_avaliador`: guard soberano de `organization_id` (todas as
  responsabilidades no mesmo tenant; cross-tenant = DENY fail-closed).
- Triggers F3-04/05/06: `if not found then raise` (fail-closed).
- Triggers F4-01/F4-02: `set search_path = public`.
- `enforce_membership_role_within_organization`: role INEXISTENTE agora é
  fail-closed (`if not found then raise`) — NULL de lookup ≠ system role; system
  role (org NULL) e tenant role (org própria) são tratados explicitamente.

### 26.6 Testes locais (Supabase local, docker/psql)

`supabase db reset` + `supabase/validacao/01-cenario-f4-08.sql` +
`02-validar-f4-08.sql` — **57 verificações `[PASS]`** + `03-validar-f4-08-mutacoes.sql`
(**8 mutation tests** do schema guard), incluindo:
- schema guard (FORCE RLS; RLS global; 4 DEFINER + **EXECUTE efetivo dos
  DEFINER**; EXECUTE indevido; policies; **privilégios efetivos via
  `has_table_privilege`** para anon/authenticated; **catálogo completo D16**
  (toda tabela `public` explicitamente classificada); **view/materialized view
  não aprovadas**; policy trivially-permissive);
- **profile inativo + membership ativa = DENY** (estrutura, `organizations` por
  listagem e por ID direto, e perfil);
- membership inativa / sem membership = DENY; multi-membership (Alfa+Beta, não
  Gama); cross-tenant por ID direto = DENY; anon sem acesso; joins sem vazamento;
- DML/TRUNCATE/capabilities/identity/memberships/auditoria/snapshots negados;
  troca `organization_id` A→B e parent/FK A→B negados;
- **`registrar_sucessao_avaliador`**: A isolada válida; B isolada válida;
  [A,B]/[B,A] rejeitados pelo guard de organization com causa ESPECÍFICA (sem
  `WHEN OTHERS`); ID inexistente; array com NULL; B em contexto indevido;
- triggers e role lookup com validação de causa específica (SQLERRM).

### 26.7 Schema guard

Em `02-validar-f4-08.sql` (§1): FORCE RLS; tabela `public` sem RLS (inclui
particionadas); SECURITY DEFINER além dos 4; **EXECUTE efetivo dos 4 DEFINER**
(public/anon/authenticated proibidos); EXECUTE indevido nas funções de negócio;
privilégios efetivos (`has_table_privilege`: SELECT/INSERT/UPDATE/DELETE/
TRUNCATE/REFERENCES/TRIGGER) para anon/authenticated; **catálogo completo D16**
(toda tabela `public` deve ser explicitamente classificada — nova tabela não
classificada ⇒ FAIL); **view/materialized view não aprovadas ⇒ FAIL**; policy
trivially-permissive e contagem de policies. O `03-validar-f4-08-mutacoes.sql`
prova que cada regra DETECTA a regressão correspondente (introduz → FAIL →
reverte → PASS), sem `WHEN OTHERS` mascarando causa.

### 26.8 Limitações/adiamentos

- **Correção sobre inlining:** os resolvers `language sql STABLE` POSSUEM
  `set search_path = public`, o que impede o inlining pelo PostgreSQL (funções
  com `SET`/proconfig não são inlined); portanto o `REVOKE EXECUTE` é EFETIVO e
  `authenticated` recebe `permission denied` (validado em teste real). A premissa
  anterior de "RLS como proteção complementar ao inlining" estava incorreta e foi
  removida.
- **Default privileges de `supabase_admin`:** não são alteráveis pela role de
  migration (`postgres`, não-superuser no Supabase local). Permanencem gerenciados
  pelo `roles.sql` do Supabase e afetam apenas objetos criados POR
  `supabase_admin`. Mitigação: o schema guard de privilégios efetivos falha o CI
  para QUALQUER tabela `public` com grant excedente a anon/authenticated,
  independentemente do criador.
- **Edge Functions (`convidar-usuario`/`gerenciar-usuario`)** permanecem como
  administração global privilegiada via allowlist + `service_role`
  (`verify_jwt=false`), exceção transitória aceita em Q6. NÃO redesenhadas na
  F4-08; risco residual (fronteira privilegiada/transitória) documentado para
  tratamento na fase apropriada.
- Persistências C/D e domínios `localStorage` permanecem para F5/F4-09+.

### 26.9 Resultados finais

- `npm test`: 55 arquivos / **748 testes** passaram.
- `npm run build`: OK. `npm run lint`: sem erros. `git diff --check`: limpo.
- Supabase local: **57 `[PASS]`** (validação RLS/schema guard) + **8 mutation
  tests** do schema guard, 0 falhas.
- CI (GitHub Actions): `quality` (test/build/lint/diff-check) + `supabase-local`
  (`db start` + `db reset` + cenário + validação RLS/schema guard + mutation tests).
