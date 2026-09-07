# F4-03 — Desenho técnico: authorization policy engine (Issue #90)

> **Status:** desenho técnico da F4-03 **aguardando revisão**. Decisões
> **D1–D18 abertas** (recomendação indicada em cada uma). Nenhuma
> implementação: sem código funcional, migrations, RLS final, `SECURITY
> DEFINER`, alteração de frontend/Edge Functions ou PR de implementação —
> somente este documento, em branch exclusiva de docs.
> Conteúdo 100% conceitual e sintético (sem dados reais).

## 1. Objetivo e escopo

### 1.1 Interpretação da Issue #90

Centralizar as decisões de autorização combinando **identidade, capability,
escopo, relação organizacional e estado do domínio**, em um **policy engine**
reutilizável na camada application/domain, substituindo gradualmente as
verificações hardcoded por cargo nos fluxos cobertos — sem depender de esconder
UI e devolvendo negações coerentes com a taxonomia F0-05.

### 1.2 O que entra na F4-03

- Desenho e (na implementação) criação do **engine** em TypeScript
  (`src/authorization`) com contrato de entrada/saída, pipeline determinística e
  mapeamento de negação para F0-05;
- mecanismo para regras de **domínio soberanas** alimentarem o engine
  (predicados), sem reimplementação de regra de negócio no engine;
- consumo das **capabilities** (F4-01) e **scopes** (F4-02) com a mesma
  semântica — inclusive a resolução "este alvo pertence ao scope?" delegada a
  provedores de relação (TS hoje; adapters Supabase/futuro);
- **matriz** positiva/negativa e migração gradual dos primeiros fluxos (sem
  big-bang).

### 1.3 O que fica para F4-04+ e F4-08

- **F4-04 em diante:** migração dos demais fluxos de domínio (avaliações,
  metas, observações, relatórios) para o engine, domínio a domínio;
- **F4-08:** policies RLS finais por tabela (o engine **não substitui RLS**;
  RLS é a última barreira server-side);
- migração funcional dos domínios para Supabase (Fase 5) e vínculo real
  auth↔collaborator;
- auditoria completa (F4-06) e UI administrativa.

## 2. Estado atual

### 2.1 Autorização atual no frontend/application

- `src/authorization` é a **policy central** atual (AGENTS.md):
  - `Capability.ts` — união TS de capabilities (vocabulário pré-banco, agora
    espelhado pelas capabilities globais da F4-01);
  - `authorizationPolicy.ts` — `can`/`authorize`/`scopeCollaborators`;
  - `AuthorizationContext` — `actor { matricula, funcao?, status }`;
  - `ResourceContext` — tipos de recurso (global, cycle, collaborator,
    collaborator-list, evaluation, goal, observation);
  - `authorizationError.ts` — `AuthorizationError` (FORBIDDEN, F0-05);
  - `perfisOperacionaisAtuais.ts` — `perfilPossuiFluxosPropriosAtuais(funcao)`.
- Páginas/componentes chamam `can`/`authorize`/`scopeCollaborators` com o
  `UsuarioAtual` (identidade DEV/impersonação sobre o seed; F2-09) — nenhuma
  página duplica a policy (regra respeitada).

### 2.2 Pontos hardcoded por função/cargo

- `authorizationPolicy.ts` decide por `actor.funcao === "GERENTE"/"COORDENADOR"`
  em ~15 pontos (collaborator.create/edit/list, cycle.*.manager,
  settings.manage, report.view, observation.*, goal.approve.*), além de regras
  relacionais via `obterPermissoesAvaliacao` (gerente/coordenador/colegiado) e
  `perfilPossuiFluxosPropriosAtuais`;
- `visibilidadeColaboradores.getColaboradoresVisiveis` — scoping legado por
  funcao + gestorDireto + colegiado (árvore em memória);
- `relatorioService.aplicarEscopoRelatorio` e `metaStorage.podeAprovarMetaNoCiclo`
  — escopo/aprovação por relação + cargo;
- `colaboradorStorage` deriva `funcao` a partir do `cargo` (nome) — a raiz da
  derivação cargo→permissão no mundo legado;
- UI: alguns gates diretos de `usuarioAtual.funcao` (ex.: exibição) — rótulos de
  cargo são exibição legítima; gates de **ação** devem migrar para o engine.

### 2.3 Capabilities (F4-01) e scopes (F4-02)

- Banco: 21 capabilities globais; access_roles (sistema + custom); scopes
  SELF/DIRECT_REPORTS/DESCENDANTS/ORGANIZATIONAL_UNIT/ORGANIZATION/ASSIGNED por
  assignment; vínculo membership→collaborator; resolvers SQL INVOKER
  (`resolver_capabilities_efetivas`, `resolver_capabilities_escopos_efetivas`,
  `resolver_alvos_escopo`).
- No mundo atual (localStorage) o TS não consulta esses resolvers: a F4-03
  precisa de um **adapter/provedor** que reproduza a mesma semântica sobre os
  dados disponíveis (seed/localStorage) e, futuramente, sobre Supabase.

### 2.4 Resolvers SQL existentes (F3/F4)

- F3-07 (INVOKER): responsável da posição, gestor direto, subordinados diretos,
  descendentes, cadeia, escopo de posições/unidades — por data;
- F3-08/09: snapshots de colegiado e responsabilidades avaliativas congeladas;
- F4-01/02: capabilities efetivas; capabilities×scopes; alvos por scope.

### 2.5 Limitações atuais

- Decisão por cargo é frágil e não corresponde ao modelo F4; capability sem
  alcance e alcance sem capability não são distinguidos; estado do domínio e
  autorização estão misturados nos serviços; sem mapeamento estruturado de
  negação (tudo FORBIDDEN); enforcement server-side inexistente até F4-08/F5.

## 3. Responsabilidade do policy engine

### 3.1 Papel

O engine é a **única porta** para "esta operação sobre este alvo é permitida?",
combinando as partes que o **servidor/domínio** conhece. Ele **não** decide
regra de negócio (quem pode avaliar é autorização; *quando* a avaliação é
imutável é domínio) e **não** substitui RLS.

### 3.2 Fórmula explícita

```
authenticated identity
+ active profile
+ active membership
+ tenant
+ capability
+ active role assignment
+ active scope
+ target/relation (alvo pertence ao scope)
+ temporal context (data)
+ domain state (predicados de domínio)
= ALLOW   (todas as cláusulas verdadeiras)
= DENY    (qualquer cláusula falsa — fail-closed)
```

### 3.3 Fail-closed

- Qualquer falha (indeterminação, alvo inválido, relação não resolvida,
  domínio em estado neutro, erro) ⇒ **DENY**;
- nenhuma exceção que permita por omissão; nenhum "escape" por cargo/função;
- ADMIN sem capability específica continua sem conteúdo confidencial.

## 4. Fronteira application/domain/database

| Camada | O que resolve | Não resolve |
| --- | --- | --- |
| Autenticação (F2) | identidade autenticada (auth.uid/sessão) | nada de permissão |
| Resolução de capability | união das capabilities das roles ativas da membership | alcance |
| Resolução de scope | scopes ativos da atribuição (F4-02) | se o alvo concreto pertence |
| Relação organizacional | "alvo ∈ escopo?" (árvore/posição/unidade/tenant — F3/F4-02) | permissão ou domínio |
| Regra de domínio | predicates do domínio (ciclo/estado/recurso) | autorização |
| Decisão de autorização | engine: ALLOW/DENY | persistência |
| RLS (F4-08) | última barreira server-side por linha | decisões de negócio |

**Anti-duplicação:** uma única implementação de engine em `src/authorization`;
páginas/componentes só chamam a porta; módulos de domínio exportam *predicados*
(estado) e não reescrevem decisões; o banco (resolvers F3/F4) replica a mesma
semântica para o futuro enforcement, nunca regras divergentes.

## 5. Contrato de entrada

Input mínimo tipado (sem campos frouxos):

```ts
type AuthorizationRequest = {
  actor: { userProfileId: string; organizationId: string }; // identidade+tenant
  capability: Capability;                                     // O QUE (código fechado)
  target: TargetRef;                                          // tipo+id do alvo (contrato §10)
  context: { date: Date; cycle?: CycleRef };                  // data/ciclo
  resourceState?: DomainStateProbe;                           // leitura de domínio (opcional)
};
```

- `user_profile_id`/`organization_id` vêm da **sessão/identidade** (nunca de
  input do usuário);
- `capability` é **pedida** pelo chamador (a ação pretendida), mas a posse é
  **resolvida pelo engine** via provedor — o chamador nunca declara suas
  capabilities/scopes/roles;
- o alvo carrega **tipo + id**, e o provedor deriva o tenant do próprio
  recurso (nunca aceitar tenant declarado pelo caller — §19);
- estado do domínio vem do **repositório** (não da UI) quando necessário.

## 6. Contrato de saída

```ts
type AuthorizationDecision = {
  allowed: boolean;
  denial?: { reason: DenialReason; publicCode: ApplicationErrorCode };
  diagnostics?: { matchedScope?: ScopeType; resolvedTarget?: TargetRef }; // interno
};
```

- `publicCode` pertence à taxonomia F0-05 (FORBIDDEN/NOT_FOUND/VALIDATION/
  CONFLICT/TECHNICAL/authentication) — é o que a UI pode ver;
- `reason` (enum interno: `NO_IDENTITY`, `PROFILE_DISABLED`,
  `MEMBERSHIP_INVALID`, `CROSS_TENANT`, `CAPABILITY_MISSING`,
  `SCOPE_INSUFFICIENT`, `DOMAIN_STATE_INVALID`, `TARGET_INVALID`) **não** é
  exposto ao frontend (só logging/diagnóstico futuro);
- `diagnostics` nunca sai do servidor/engine para a UI.

## 7. Ordem da decisão

Pipeline determinística (fail-fast, parando na primeira negação):

1. identidade válida (autenticada);
2. profile ativo;
3. membership ativa;
4. tenant correto (actor.org = alvo.org);
5. capability efetiva (ator possui, role/assignment ativos);
6. scope efetivo (pelo menos um scope ativo na atribuição que concedeu a
   capability);
7. alvo pertence ao scope (relação organizacional/target);
8. contexto temporal válido (data; snapshot quando ciclo);
9. estado do domínio permite a ação (predicados);
10. ALLOW.

Justificativa da ordem: cláusulas baratas e globais primeiro (1–4), depois as
resolvidas por provedor (5–7), depois as de domínio (8–9) — minimiza trabalho e
evita vazar detalhes (cross-tenant vs capability são razões distintas). Não há
razão para reordenar hoje; registrar em código como ordem única.

## 8. Capability

- **Consulta de capabilities efetivas**: provedor `capabilityProvider` → união
  das capabilities das roles ativas da membership ativa (mesma regra da
  `resolver_capabilities_efetivas` SQL — adapters local/Supabase);
- **capability disabled**: nunca é efetiva (F4-01 status);
- **múltiplas roles**: união (F4-01);
- **ausência**: DENY `CAPABILITY_MISSING` → público FORBIDDEN;
- **administrativa vs conteúdo**: capabilities de administração atuam sobre
  configuração/estrutura; capabilities de conteúdo exigem scope + relação e são
  as únicas que podem alcançar dados sensíveis; o engine não distingue por
  prefixo — a distinção é semântica e vive na **matriz capability×uso**
  (o ADMIN não possui capabilities de conteúdo na F4-01).

## 9. Scope

- O engine **não reconstrói a lógica estrutural**: ele pergunta ao
  `relationProvider` "o alvo X está no escopo Y do ator na data D?" e o
  provedor decide usando F3/F4-02 (TS hoje; SQL/adapters no futuro);
- SELF → colaborador vinculado;
- DIRECT_REPORTS → posições subordinadas diretas (reporting line), responsável
  efetivo na data (contexto vivo — D9 F4-02);
- DESCENDANTS → árvore F3 (união multi-position);
- ORGANIZATIONAL_UNIT → somente a unidade explícita (sem subunidades);
- ORGANIZATION → alcance do tenant (não permissão);
- ASSIGNED → **fail-closed na F4-03** (derivação de F3-08/09 é F4-05; sem
  resolução hoje ⇒ DENY — nunca allow por omissão).

## 10. Target/recurso

Targets tipados por recurso, com contrato fechado (sem strings livres nem
polimorfismo genérico):

```ts
type TargetRef =
  | { type: "collaborator"; id: string }
  | { type: "position"; id: string }
  | { type: "organizational_unit"; id: string }
  | { type: "cycle"; id: string }        // ciclo
  | { type: "evaluation"; id: string }   // avaliação (avaliado+posição+ciclo)
  | { type: "goal"; id: string }
  | { type: "observation"; id: string };
```

- cada tipo possui validação própria e deriva o tenant do recurso carregado;
- para recursos compostos (avaliação = avaliado × posição × ciclo) o engine
  resolve via sub-targets (collaborator/position) e o estado do domínio;
- nenhuma tabela/registro novo no banco nesta etapa (target é contrato do
  engine; persistência de ASSIGNED explícito ficou para a F4-02/F4-05).

## 11. Relação organizacional

- `relationProvider` consome a semântica F3/F4-02: ocupação/posição na data,
  reporting line, descendentes, unidade, vínculo membership→collaborator,
  múltiplas positions (união), histórico por data (snapshot quando ciclo);
- **nenhuma regra por nome de cargo**: o provedor só olha estrutura
  (positions/reporting/occupations) e atribuições (scopes);
- `gestorDireto`/coordenador/colegiado (regras atuais em `permissaoAvaliacao`
  etc.) tornam-se combinações de capability + scope (DESCENDANTS/ASSIGNED)
  avaliadas pelo provedor — a tabela de mapeamento vive **num único módulo**
  (evitar duplicação).

## 12. Contexto temporal

- toda decisão recebe **data explícita** (padrão; nenhuma derivação implícita
  de `now()` no meio da pipeline);
- "agora" = data corrente fornecida pelo caller confiável (sessão/relógio do
  serviço);
- ciclo = referência ao ciclo (ano/ciclo); avaliação/metas/observações de um
  ciclo usam o **snapshot/data do ciclo** (F3-08/09) — congelado;
- **estrutura viva × histórico**: contexto vivo usa responsável efetivo na
  data; contexto de ciclo usa o que estava congelado (D9 F4-02) — o provedor
  recebe a data e decide; o engine nunca mistura.

## 13. Estado de domínio

**Crítico.** O engine NÃO reimplementa regra de negócio. Cada domínio exporta
**predicados** ("domain state probes") consultados pelo engine na etapa 9:

- ciclo PLANEJADO/ATIVO/ENCERRADO/CANCELADO → quais ações o estado permite;
- avaliação CONCLUÍDA imutável em fluxo normal (reabertura = exceção auditada);
- observações mutáveis somente em ciclo ATIVO;
- configuração congelada após ativação (edição bloqueada);
- metas conforme lifecycle (aprovação só antes de finalização etc.).

Forma: `domain.getStateProbe(resource): DomainStateProbe` e o engine chama
`probe.allows(capability/action)` — o domínio declara, o engine decide. O
domínio permanece soberano e testável isoladamente; o engine não conhece
status específicos.

## 14. Taxonomia de negação

| Negação | `reason` interno | Código público (F0-05) | Exposto à UI? |
| --- | --- | --- | --- |
| não autenticado | NO_IDENTITY | (authentication — via guard F2-04) | não (fluxo de login) |
| membership inválida/disabled | MEMBERSHIP_INVALID | FORBIDDEN | não (mensagem genérica) |
| profile disabled | PROFILE_DISABLED | FORBIDDEN | não |
| capability ausente | CAPABILITY_MISSING | FORBIDDEN | não |
| scope insuficiente | SCOPE_INSUFFICIENT | FORBIDDEN | não |
| cross-tenant | CROSS_TENANT | NOT_FOUND (sem vazar existência) ou FORBIDDEN | não |
| estado de domínio inválido | DOMAIN_STATE_INVALID | CONFLICT ou VALIDATION | parcial (mensagem de estado, não de autorização) |
| recurso inexistente/inacessível | TARGET_INVALID | NOT_FOUND | mensagem genérica |

Regra: a UI recebe apenas `code`/`category`/mensagem pública (F0-05); razões
internas ficam para log/diagnóstico (F4-06). Cross-tenant vira NOT_FOUND quando
o ator não deveria saber que o recurso existe (evita enumeração).

## 15. API/serviço proposto

```ts
// porta única do engine
can(request: AuthorizationRequest): AuthorizationDecision;
authorize(request: AuthorizationRequest): void; // lança (F0-05 público) quando DENY
// scope list (para listagens): alvos permitidos de um capability+scope
listAllowedTargets(actor, capability, scopeType, date): TargetRef[];
```

- `can` — para UI/predicados (retorna decisão estruturada; não lança);
- `authorize` — para mutações (lança `ForbiddenError`/`NotFoundError`/
  `ConflictError`/`ValidationError` coerente com a razão interna);
- **`assertAuthorized` é redundante** (igual a `authorize`) — não criar uma
  terceira API; manter as duas + `listAllowedTargets`.

## 16. Integração com SQL resolvers

- Hoje (localStorage) o engine usa **provedores TS** com a mesma semântica dos
  resolvers SQL (F3-07, F4-01/02): `capabilityProvider`, `scopeProvider`,
  `relationProvider`, `domainStateProvider` — interfaces em
  `src/authorization`, implementações atuais sobre o seed/localStorage;
- quando um domínio migrar para Supabase (Fase 5), o adapter do domínio
  fornecerá estado e targets; e, se houver camada server-side própria, os
  resolvers SQL INVOKER passam a ser consumíveis — mas sob **RLS deny-by-
  default** eles retornam vazio para `authenticated`; um caminho privilegiado
  server-side (service_role) só existe para servidor de confiança;
- **nenhum `SECURITY DEFINER`** novo nesta etapa; qualquer helper privilegiado
  futuro é **decisão explícita** (D8/D18 F4-03) com `EXECUTE` restrito.

## 17. Migração gradual das regras antigas

Ordem proposta (sem big-bang, domínio a domínio):

1. **F4-03 (esta etapa):** engine + matriz capability/scope/relação/estado para
   os fluxos que já têm dados no domínio atual, começando pelos
   **auto-fluxos** (metas próprias, observações próprias/Comunicado) e
   **gates administrativos simples** (settings.manage, collaborator list);
2. **F4-03/F4-04:** fluxos de avaliação (criação/edição/cancelamento/reabertura)
   e metas/aprovação, substituindo `actor.funcao` por capability+scope+relação
   (mapping central);
3. **somente após persistência Supabase dos domínios (Fase 5):** enforcement
   server-side real com RLS (F4-08) e vínculo auth↔collaborator;
4. relatórios/exportação e fluxos que dependem de árvore completa migram quando
   a estrutura F3 for a fonte viva do frontend.

`funcao` deixa de ser fonte de autorização; permanece apenas como **rótulo de
cargo** (exibição) até o corte.

## 18. Matriz de autorização (sintética)

| # | Cenário | Resultado |
| --- | --- | --- |
| 1 | capability + scope válido + estado válido | ALLOW |
| 2 | capability sem scope (assignment sem scope) | DENY (SCOPE_INSUFFICIENT) |
| 3 | scope sem capability (role sem a capability) | DENY (CAPABILITY_MISSING) |
| 4 | capability + scope + estado inválido (avaliação CONCLUÍDA) | DENY (DOMAIN_STATE_INVALID) |
| 5 | cross-tenant (ator org A, alvo org B) | DENY (CROSS_TENANT → público NOT_FOUND) |
| 6 | membership disabled | DENY (MEMBERSHIP_INVALID) |
| 7 | profile disabled | DENY (PROFILE_DISABLED) |
| 8 | SELF sobre terceiro | DENY (SCOPE_INSUFFICIENT) |
| 9 | DESCENDANTS fora da árvore do ator | DENY (SCOPE_INSUFFICIENT) |
| 10 | ORGANIZATION sem capability de conteúdo | DENY (CAPABILITY_MISSING) |
| 11 | ADMIN sem capability confidencial | DENY (CAPABILITY_MISSING) |
| 12 | múltiplas positions | união correta (alvo em qualquer position autorizada ⇒ ALLOW) |
| 13 | contexto histórico | usa o congelado na data/ciclo (ALLOW/DENY correto para a época) |
| 14 | substituição temporária vigente | alvo na posição assume responsável efetivo (D9 F4-02) — sem estado novo |
| 15 | ASSIGNED sem resolução (F4-03) | DENY (fail-closed) |

## 19. Segurança

- **Trust boundary:** o engine é chamado por código interno (serviços/UI);
  nenhuma credencial/role/capability vem do cliente — o provedor resolve de
  fontes confiáveis;
- **caller-controlled input:** actor (org/tenant) e estado do domínio vêm do
  serviço, nunca do request/UI; capability é pedida, não declarada;
- **IDOR:** alvo é resolvido pelo engine contra o provedor (nunca "o caller
  já passou no filtro"); cross-tenant = NOT_FOUND;
- **tenant spoofing:** tenant do alvo derivado do recurso carregado;
- **confused deputy:** serviços de domínio chamam `authorize` antes de persistir
  e não expõem operações não autorizadas;
- **bypass frontend:** esconder botão não é autorização; o engine roda também
  onde a mutação acontece (mesma camada); enforcement server-side só com F5/
  F4-08 (limitação registrada);
- **TOCTOU:** autorização e mutação no mesmo fluxo síncrono; para Supabase
  (F5) revalidar **dentro da transação/RPC** (server-side) — ver D9;
- **RLS:** última barreira (F4-08); o engine nunca substitui.

## 20. Performance

- Custo por decisão = capability (1 consulta pequena) + scopes + relação
  (árvore sob demanda) + 1–2 probes de domínio — pequeno no mundo local;
- evitar N+1: `listAllowedTargets` agrega alvos por scope (uma travessia);
- **cache:** não na F4-03 — resoluções são baratas e revogação deve ser
  imediata; reavaliar só com perfil real de medição (não otimizar
  prematuramente).

## 21. Observabilidade/auditoria futura

Campos úteis de registrar futuramente (F4-06): actor (user_profile),
organization, capability, target (type+id), decisão, denial reason, matched
scope, contexto (data/ciclo), timestamp. Não implementar auditoria agora; o
contrato de saída já carrega `reason`/`matchedScope` para alimentá-la sem
refazer o engine.

## 22. Riscos e invariantes

Invariantes:

1. **Capability define a ação; scope define alcance** — os dois juntos e o
   alvo dentro do alcance;
2. **cargo/job_role nunca é fonte permanente** de autorização (nem no engine
   nem em páginas);
3. **relação organizacional vem de estrutura** (positions/reporting/
   occupations/vínculo), nunca do nome do cargo;
4. **estado do domínio é soberano** — estado inválido ⇒ DENY mesmo com
   capability+scope;
5. **membership/profile ativos** são pré-condição; **cross-tenant** ⇒ DENY;
6. **fail-closed** (indeterminação/ASSIGNED não resolvido ⇒ DENY);
7. **nenhum bypass** por UI/`can` — mutações usam `authorize` na camada certa;
8. **nenhum SUPER_ADMIN**; ADMIN sem conteúdo confidencial;
9. **sem SECURITY DEFINER novo** nesta etapa;
10. **policy engine não substitui RLS** (RLS é F4-08);
11. **negações coerentes com F0-05** (código público seguro; razões internas
    não vazam);
12. **sem duplicação** de regra entre engine, páginas, serviços e banco.

Riscos: mapear regras por cargo incorretamente (usar tabela única de
mapeamento); vazar razão interna; estado de domínio "inventado" no engine;
permitir allow por omissão; duplicar a árvore F3 no TS em divergência do SQL
(usar adapters com a mesma semântica e testes espelhados).

## 23. Decisões pendentes (D1–D18)

Para cada decisão: pergunta, alternativas, recomendação e impacto. Todas
**abertas** para revisão do desenho.

### D1 — Engine TypeScript vs SQL vs híbrido

- **Pergunta:** onde o engine vive: TypeScript (application), SQL/funções do
  banco, ou híbrido?
- **Alternativas:** (A) TS em `src/authorization`; (B) SQL no banco; (C)
  híbrido (TS hoje + SQL server-side quando houver camada servidora).
- **Recomendação:** (A) nesta etapa, com **provedores** (interfaces) que no
  futuro (F5/F4-08) trocam a fonte para Supabase sem reescrever o engine —
  evita duplicação divergente e mantém uma única semântica.
- **Impacto:** (A) testável em Vitest e independente de servidor; (C) exige
  camada servidora própria para o SQL ser útil (não existe ainda).

### D2 — Fonte soberana da decisão

- **Pergunta:** qual o ponto único que decide autorização nos fluxos?
- **Alternativas:** (A) o engine em `src/authorization` é a única porta
  (`can`/`authorize`); (B) cada serviço decide localmente.
- **Recomendação:** (A) — nenhuma página/componente/serviço decide; a policy
  central atual evolui para o engine.
- **Impacto:** (A) auditável e coerente; (B) duplicação (proibida).

### D3 — Onde as regras de domínio entram

- **Pergunta:** como o engine incorpora estado de domínio sem reimplementar?
- **Alternativas:** (A) predicates exportados pelos módulos de domínio
  (`domainStateProvider` consultado na etapa 9); (B) engine conhece status de
  cada domínio.
- **Recomendação:** (A) — domínio declara `probe.allows(action)`, engine só
  consome.
- **Impacto:** (A) mantém soberania e testabilidade do domínio; (B) acopla e
  duplica regra (rejeitado).

### D4 — Contrato de target

- **Pergunta:** como representar o alvo sem strings livres/polimorfismo
  inseguro?
- **Alternativas:** (A) `TargetRef` tipado fechado (collaborator/position/unit/
  cycle/evaluation/goal/observation); (B) string livre; (C) alvo genérico
  `{type,id}` sem validação.
- **Recomendação:** (A) — tipos fechados, tenant derivado do recurso, sem
  registro novo no banco nesta etapa.
- **Impacto:** (A) seguro e extensível; (B)/(C) IDOR/spoofing (rejeitado).

### D5 — API: can vs authorize vs assertAuthorized

- **Pergunta:** quais portas o engine expõe?
- **Alternativas:** (A) `can` + `authorize`; (B) três (com `assertAuthorized`);
  (C) só `authorize`.
- **Recomendação:** (A) — `can` para UI/predicados (decisão estruturada) e
  `authorize` para mutações (lança erro público F0-05); `assertAuthorized` é
  redundante; adicionar `listAllowedTargets` para listagens.
- **Impacto:** (A) superfície mínima; (C) força exceção para predicação de UI.

### D6 — Razão de negação pública vs interna

- **Pergunta:** quanto da razão de negação chega ao frontend?
- **Alternativas:** (A) só código/categoria pública F0-05; razões internas para
  log; (B) repassar razão detalhada.
- **Recomendação:** (A) — enum interno mapeado para FORBIDDEN/NOT_FOUND/
  CONFLICT/VALIDATION/TECHNICAL; cross-tenant vira NOT_FOUND.
- **Impacto:** (A) sem vazamento; (B) auxiliaria atacante (rejeitado).

### D7 — Consumo dos resolvers SQL sob RLS deny-by-default

- **Pergunta:** o engine TS deve chamar os resolvers SQL (INVOKER) hoje?
- **Alternativas:** (A) não — provedores TS com a mesma semântica; resolvers
  SQL ficam para a camada servidora futura (F5/F4-08); (B) chamar via cliente
  Supabase (retornaria vazio/deny para authenticated).
- **Recomendação:** (A) — hoje os dados de domínio vivem em localStorage; o
  adapter Supabase chega com a Fase 5; usar o cliente agora seria inócuo.
- **Impacto:** (A) engine funcional sem servidor; (B) falso deny em toda
  chamada (inútil).

### D8 — Helper SECURITY DEFINER

- **Pergunta:** é necessário criar função DEFINER para o engine?
- **Alternativas:** (A) não nesta etapa; (B) sim, para expor resolução.
- **Recomendação:** (A) — nenhum DEFINER novo; se a F4-08 precisar de
  resolução privilegiada, será decisão explícita com `EXECUTE` restrito.
- **Impacto:** (A) sem superfície privilegiada; (B) risco sem consumidor.

### D9 — Transação autorização + mutação

- **Pergunta:** como evitar TOCTOU entre decidir e persistir?
- **Alternativas:** (A) autorizar no mesmo fluxo antes de persistir (hoje
  síncrono) e, no Supabase (F5), revalidar dentro da RPC/transação;
  (B) decidir apenas na UI.
- **Recomendação:** (A) — mutação sempre passa por `authorize` na camada de
  serviço, e o futuro adapter Supabase revalida server-side na transação.
- **Impacto:** (A) minimiza TOCTOU; (B) bypass trivial (rejeitado).

### D10 — Recursos ainda em localStorage

- **Pergunta:** como o engine lê estado/alvo de domínios ainda em localStorage?
- **Alternativas:** (A) provedores que carregam do repositório local (nunca do
  objeto passado pela UI) — mesma interface que os adapters Supabase futuros;
  (B) aceitar estado arbitrário do chamador.
- **Recomendação:** (A) — repositório como fonte; a UI pede, o serviço carrega,
  o engine decide; limitação (sem enforcement server-side) documentada até
  F5/F4-08.
- **Impacto:** (A) coerente e migrável; (B) IDOR (rejeitado).

### D11 — Migração gradual

- **Pergunta:** qual a ordem de migração dos fluxos por cargo?
- **Alternativas:** (A) auto-fluxos e administrativos simples primeiro, depois
  avaliação/metas, depois relatórios; (B) tudo de uma vez.
- **Recomendação:** (A) — domínio a domínio, sem big-bang (§17).
- **Impacto:** (A) risco baixo; (B) regressão ampla (rejeitado).

### D12 — Cache

- **Pergunta:** cachear resoluções?
- **Alternativas:** (A) sem cache na F4-03; (B) cache com invalidação.
- **Recomendação:** (A) — barato hoje e revogação imediata; reavaliar com
  medição real.
- **Impacto:** (A) simples; (B) risco de revogação atrasada (prematuro).

### D13 — Contexto temporal

- **Pergunta:** como o engine recebe a data?
- **Alternativas:** (A) data explícita em toda decisão (contexto: agora ou
  ciclo); (B) engine usa `now()` internamente.
- **Recomendação:** (A) — determinismo e histórico corretos (D16 F4-02).
- **Impacto:** (A) previsível; (B) inconsistência com snapshots.

### D14 — ASSIGNED fail-closed

- **Pergunta:** como tratar scopes ASSIGNED enquanto não há resolução de
  F3-08/09 no engine?
- **Alternativas:** (A) DENY (fail-closed) sempre que a única via de allow for
  ASSIGNED sem provedor; (B) ignorar o scope e seguir.
- **Recomendação:** (A) — nenhum allow por omissão; resolução de colegiado/
  avaliador chega com F4-05.
- **Impacto:** (A) seguro; (B) allow indevido (rejeitado).

### D15 — Boundary F4-03 × F4-04

- **Pergunta:** o que exatamente a F4-03 entrega vs a F4-04?
- **Alternativas:** (A) F4-03: engine genérico + matriz + primeiros fluxos
  (auto-fluxos e administrativos simples); F4-04: demais fluxos de domínio;
  (B) F4-03 cobre todos os fluxos.
- **Recomendação:** (A) — engine pronto e provado em subconjunto; cobertura
  total é incremental.
- **Impacto:** (A) PR revisável; (B) escopo grande demais.

### D16 — Input confiável (anti-IDOR/spoofing)

- **Pergunta:** quem fornece actor/org/estado no request?
- **Alternativas:** (A) camada de serviço (sessão + repositório); o engine
  deriva tenant do alvo; (B) aceitar do chamador arbitrário.
- **Recomendação:** (A) — actor e organização da sessão; tenant do alvo
  derivado do recurso.
- **Impacto:** (A) impede spoofing/IDOR; (B) inseguro (rejeitado).

### D17 — Identidade DEV × real

- **Pergunta:** como o engine resolve actor/membership hoje, sem vínculo
  auth↔collaborator real?
- **Alternativas:** (A) actor da identidade DEV/impersonação (F2-09) resolvido
  via provedor; o mesmo contrato valerá com a identidade real (F5); (B)
  bloquear o engine fora de produção.
- **Recomendação:** (A) — engine agnóstico de DEV/produção; limitação de
  enforcement server-side documentada.
- **Impacto:** (A) evoluível; (B) inutilizável em DEV (rejeitado).

### D18 — Mapa das regras por cargo → capability/scope

- **Pergunta:** como converter as ~15 regras por `funcao` sem perder semântica?
- **Alternativas:** (A) tabela única de mapeamento (regra antiga → capability +
  scope/relação) num módulo do engine, validada por testes espelhados;
  (B) migrar caso a caso sem tabela.
- **Recomendação:** (A) — central e rastreável; a tabela some quando todos os
  fluxos estiverem no engine.
- **Impacto:** (A) transição auditável; (B) risco de regressão silenciosa.

## 24. Proposta de implementação futura

Arquivos/camadas provavelmente alterados na implementação (não executada aqui):

- `src/authorization/` — novo núcleo do engine: `policyEngine.ts`
  (`can`/`authorize`/`listAllowedTargets`), `types.ts` (AuthorizationRequest/
  Decision/DenialReason/TargetRef), `domainState.ts` (interface de probe);
- `src/authorization/providers/` — interfaces + adapters (capability/scope/
  relation/domain-state) para o mundo atual;
- `src/services/*` — cada domínio exporta `getStateProbe`; serviços passam a
  usar `authorize` no ponto de mutação;
- `src/authorization/Capability.ts` — passa a ser o catálogo tipado consumido
  pelo engine (sem duplicar o banco F4-01);
- páginas/componentes: substituem uso direto de cargo por `can` do engine;
- testes: `src/authorization/policyEngine.test.ts` + espelho dos serviços;
- futuro (F5/F4-08): adapters Supabase para providers e RLS consumindo a mesma
  semântica.

## 25. Proposta de validação

Testes positivos e negativos para provar a Issue #90 (Vitest, dados
sintéticos):

- matriz positiva/negativa da seção 18 (13+ casos) parametrizada;
- capability sem scope ⇒ deny; scope sem capability ⇒ deny; estado inválido ⇒
  deny mesmo com capability+scope; cross-tenant ⇒ deny (NOT_FOUND público);
- SELF sobre terceiro ⇒ deny; DESCENDANTS fora da árvore ⇒ deny; múltiplas
  positions ⇒ allow quando qualquer position autoriza; contexto histórico usa o
  congelado;
- ADMIN sem capability confidencial ⇒ deny; assignment sem scope ⇒ deny;
  membership/profile disabled ⇒ deny; ASSIGNED sem resolução ⇒ deny
  (fail-closed);
- `authorize` lança erro F0-05 correto (FORBIDDEN/NOT_FOUND/CONFLICT) e
  `can` devolve decisão estruturada sem lançar;
- nenhuma página/componente contém comparação por cargo em decisão de ação
  (grep em testes de regressão — "autorização não depende de cargo === ..."
  nos fluxos cobertos);
- regras de domínio permanecem nos módulos de domínio (teste de fronteira:
  engine não importa status específico);
- CI/build/lint/diff-check e, após F5, RLS como última barreira.

Nada disso é implementado nesta entrega; fica como contrato para as próximas
etapas da Fase 4.
