# F4-03 — Desenho técnico: authorization policy engine (Issue #90)

> **Status:** revisão arquitetural **concluída**; decisões D1–D18 **fechadas**
> na seção 23 (D1, D5, D9, D15 e D18 com ajustes registrados). Nenhuma
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

- **F4-04:** aplicação **ampla** de hierarchy + assignments à autorização
  (fluxos de avaliação, metas/aprovação, observações, relatórios dependentes
  de árvore) — fora do escopo da F4-03 (D15);
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

## 15. API/serviço proposto (D5 = A ajustada — fechada)

```ts
// Únicas portas de decisão do engine:
can(request: AuthorizationRequest): AuthorizationDecision;   // predicação (UX/UI)
authorize(request: AuthorizationRequest): void;             // mutações: lança erro público F0-05 quando DENY

// Serviço AUXILIAR de listagem/resolução (NÃO é fonte de decisão):
listAllowedTargets(actor, capability, scopeType, date): TargetRef[];
```

- `can` — auxiliar de **UX/predicação** (retorna decisão estruturada; não
  lança); **nunca é enforcement** (invariante 1);
- `authorize` — protege **mutações** (lança `ForbiddenError`/`NotFoundError`/
  `ConflictError`/`ValidationError` coerente com a razão interna);
- **`assertAuthorized` não existe** (redundante com `authorize`; não criar
  terceira API);
- `listAllowedTargets` pode existir como serviço auxiliar de resolução/
  listagem, mas **não se torna uma terceira fonte de decisão**: uma mutação
  nunca considera "estar na lista" como substituto de `authorize()` (D5).

## 16. Integração com SQL resolvers

- Hoje (localStorage) o engine usa **provedores TS** com a mesma semântica dos
  resolvers SQL (F3-07, F4-01/02): `capabilityProvider`, `scopeProvider`,
  `relationProvider`, `domainStateProvider` — interfaces em
  `src/authorization`, implementações atuais sobre o seed/localStorage;
- **não criar uma segunda implementação independente do engine em SQL** nesta
  fase (D1 = A ajustada): o engine TS é a fonte única de decisão na camada
  application; quando houver enforcement server-side real, ele **reutiliza a
  mesma regra/contrato arquitetural** e não diverge silenciosamente;
- quando um domínio migrar para Supabase (Fase 5), o adapter do domínio
  fornecerá estado e targets; os resolvers SQL INVOKER poderão ser consumidos
  por um servidor de confiança — mas sob **RLS deny-by-default** retornam vazio
  para `authenticated`; caminho privilegiado (service_role) só para servidor
  de confiança;
- **nenhum `SECURITY DEFINER`** novo nesta etapa (D8 = A); qualquer helper
  privilegiado futuro é **decisão explícita** com `EXECUTE` restrito.

## 17. Migração gradual das regras antigas (D15 = A ajustada — fechada)

Escopo da F4-03 (piloto, sem sobreposição com a F4-04):

1. **F4-03 (esta etapa):** engine genérico + contratos/providers + matriz
   positiva/negativa + **poucos fluxos-piloto de baixo risco** suficientes para
   provar o engine (ex.: auto-fluxos de metas/observações próprias e gates
   administrativos simples), com remoção de comparações por cargo **somente
   nesses fluxos cobertos**;
2. **F4-04:** aplicação **ampla** de hierarchy + assignments à autorização
   (fluxos de avaliação/metas/aprovação/relatórios dependentes de árvore) —
   fora da F4-03;
3. **somente após persistência Supabase dos domínios (Fase 5):** enforcement
   server-side real com RLS (F4-08) e vínculo auth↔collaborator;
4. relatórios/exportação e fluxos dependentes de árvore completa migram com a
   F3 como fonte viva do frontend.

`funcao` deixa de ser fonte de autorização nos fluxos migrados; permanece como
**rótulo de cargo** (exibição) até o corte.

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
- **TOCTOU (D9 = A ajustada — requisito arquitetural):**
  - no mundo atual/localStorage, `authorize()` ocorre **na mesma camada de
    serviço, imediatamente antes da mutação**; nenhuma mutação confia apenas em
    `can()` executado previamente pela UI;
  - no futuro Supabase, **operações críticas revalidam autorização server-side
    dentro da mesma RPC/transação** que realiza a mutação; RLS permanece a
    última barreira; **uma autorização calculada no cliente nunca é prova para
    a transação**;
  - registrado como requisito para **F5/F4-08**;
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

Invariantes **reforçadas na revisão arquitetural**:

1. **`can()` é auxiliar de UX/predicação; `authorize()` protege mutações** —
   nenhuma mutação confia em `can()` prévio da UI (D9).
2. **UI nunca é enforcement** — esconder botão/tela não autoriza nem desautoriza.
3. **Actor, tenant e estado do domínio não vêm de input arbitrário da UI** —
   resolvidos pela camada de serviço/repositório.
4. **Tenant do alvo é derivado do recurso carregado** — nunca do request.
5. **Capability e scope são resolvidos por providers, nunca declarados pelo
   caller** — o chamador só pede a ação.
6. **Regra de domínio permanece fora do engine** — predicates/probes do
   domínio soberano.
7. **Capability sem scope = DENY.**
8. **Scope sem capability = DENY.**
9. **Estado inválido = DENY mesmo com capability+scope válidos.**
10. **ASSIGNED não resolvido = DENY** (fail-closed até F4-05).
11. **Nenhum cargo/job_role participa da decisão runtime dos fluxos migrados**
    (o mapa legado é artefato de migração — D18).
12. **Nenhum `SECURITY DEFINER` novo nesta etapa** (D8).
13. **Nenhum cache nesta etapa** (D12).
14. **Cross-tenant não deve vazar a existência do recurso** (público NOT_FOUND).
15. **Policy engine não substitui RLS** (RLS é a última barreira — F4-08).
16. **Autorização e mutação crítica futuras devem ser atomicamente revalidadas
    server-side** (mesma RPC/transação — requisito F5/F4-08, D9).

Riscos: mapear regras por cargo incorretamente (o mapa é temporário e só de
regressão — nunca consultado em runtime como fonte de decisão — D18); vazar
razão interna; estado de domínio "inventado" no engine; permitir allow por
omissão; duplicar a árvore F3 no TS em divergência do SQL (usar adapters com a
mesma semântica e testes espelhados); criar segunda implementação SQL do engine
(D1).

## 23. Decisões fechadas (D1–D18)

Registro final da revisão arquitetural: cada decisão indica a alternativa
**fechada** e o impacto correspondente. **D1, D5, D9, D15 e D18 incorporam
ajustes obrigatórios** da revisão.

**Resumo dos fechamentos:** D1 = **A ajustada** · D2 = A · D3 = A · D4 = A ·
D5 = **A ajustada** · D6 = A · D7 = A · D8 = A · D9 = **A ajustada** · D10 = A ·
D11 = A · D12 = A · D13 = A · D14 = A · D15 = **A ajustada** · D16 = A ·
D17 = A · D18 = **A ajustada**.

### D1 — Engine TypeScript (fonte única na application) — **FECHADA (A ajustada)**

- **Pergunta:** onde o engine vive: TypeScript (application), SQL/funções do
  banco, ou híbrido?
- **Alternativas:** (A) TS em `src/authorization`; (B) SQL no banco; (C)
  híbrido (TS hoje + SQL server-side quando houver camada servidora).
- **Decisão (fechada): A ajustada** — o engine vive em **TypeScript nesta
  etapa como fonte única de decisão na camada application**, estruturado por
  **interfaces/providers** para que a origem dos dados possa migrar depois para
  Supabase/server-side **sem reescrever a semântica da decisão**. **Não criar
  uma segunda implementação independente do engine em SQL nesta fase**; quando
  houver enforcement server-side real, ele **reutiliza a mesma regra/contrato
  arquitetural** e não diverge silenciosamente.
- **Impacto:** testável (Vitest) e independente de servidor; sem duplicação
  divergente TS×SQL; a migração da fonte de dados é aditiva.

### D2 — Fonte soberana da decisão — **FECHADA (A)**

- **Pergunta:** qual o ponto único que decide autorização nos fluxos?
- **Alternativas:** (A) o engine em `src/authorization` é a única porta
  (`can`/`authorize`); (B) cada serviço decide localmente.
- **Decisão (fechada): A** — o engine é a **única porta** de decisão;
  nenhuma página/componente/serviço decide (a policy central atual evolui para
  o engine).
- **Impacto:** decisão auditável e coerente; sem duplicação.

### D3 — Onde as regras de domínio entram — **FECHADA (A)**

- **Pergunta:** como o engine incorpora estado de domínio sem reimplementar?
- **Alternativas:** (A) predicates/probes exportados pelos módulos de domínio
  (`domainStateProvider` na etapa 9); (B) engine conhece status de cada
  domínio.
- **Decisão (fechada): A** — o domínio declara `probe.allows(action)`; o engine
  apenas consome; **regra de domínio permanece fora do engine**.
- **Impacto:** domínio soberano e testável; sem acoplamento nem duplicação.

### D4 — Contrato de target — **FECHADA (A)**

- **Pergunta:** como representar o alvo sem strings livres/polimorfismo
  inseguro?
- **Alternativas:** (A) `TargetRef` tipado fechado (collaborator/position/unit/
  cycle/evaluation/goal/observation); (B) string livre; (C) alvo genérico
  `{type,id}` sem validação.
- **Decisão (fechada): A** — tipos fechados com tenant derivado do recurso;
  sem registro novo no banco nesta etapa.
- **Impacto:** sem IDOR/spoofing; extensível com contrato.

### D5 — API pública: can + authorize (listAllowedTargets é auxiliar) — **FECHADA (A ajustada)**

- **Pergunta:** quais portas o engine expõe?
- **Alternativas:** (A) `can` + `authorize`; (B) três (com `assertAuthorized`);
  (C) só `authorize`.
- **Decisão (fechada): A ajustada** — **apenas duas portas de decisão**:
  `can(request): AuthorizationDecision` (predicação/UX; nunca enforcement) e
  `authorize(request): void` (mutações; lança erro público F0-05 quando DENY).
  `assertAuthorized` **não existe**. `listAllowedTargets` pode existir como
  **serviço auxiliar de resolução/listagem**, mas **não se torna uma terceira
  fonte de decisão** — uma mutação nunca considera "estar na lista" como
  substituto de `authorize()` (seção 15).
- **Impacto:** superfície mínima e segura; listagem sem força de decisão.

### D6 — Razão de negação pública vs interna — **FECHADA (A)**

- **Pergunta:** quanto da razão de negação chega ao frontend?
- **Alternativas:** (A) só código/categoria pública F0-05; razões internas para
  log; (B) repassar razão detalhada.
- **Decisão (fechada): A** — enum interno mapeado para FORBIDDEN/NOT_FOUND/
  CONFLICT/VALIDATION/TECHNICAL; **cross-tenant não vaza existência**
  (NOT_FOUND).
- **Impacto:** sem vazamento; auxiliaria atacante seria rejeitado.

### D7 — Consumo dos resolvers SQL sob RLS deny-by-default — **FECHADA (A)**

- **Pergunta:** o engine TS deve chamar os resolvers SQL (INVOKER) hoje?
- **Alternativas:** (A) não — provedores TS com a mesma semântica; resolvers
  SQL ficam para a camada servidora futura (F5/F4-08); (B) chamar via cliente
  Supabase (retornaria vazio/deny para authenticated).
- **Decisão (fechada): A** — hoje os dados vivem em localStorage; o adapter
  Supabase chega com a Fase 5; usar o cliente agora seria inócuo (falso deny).
- **Impacto:** engine funcional sem servidor; SQL reutiliza o mesmo contrato
  (D1) quando houver camada servidora.

### D8 — Helper SECURITY DEFINER — **FECHADA (A)**

- **Pergunta:** é necessário criar função DEFINER para o engine?
- **Alternativas:** (A) não nesta etapa; (B) sim, para expor resolução.
- **Decisão (fechada): A** — **nenhum `SECURITY DEFINER` novo**; se a F4-08
  precisar de resolução privilegiada, será decisão explícita com `EXECUTE`
  restrito.
- **Impacto:** sem superfície privilegiada nova.

### D9 — TOCTOU: autorização + mutação — **FECHADA (A ajustada)**

- **Pergunta:** como evitar TOCTOU entre decidir e persistir?
- **Alternativas:** (A) autorizar no mesmo fluxo antes de persistir e revalidar
  server-side na transação futura; (B) decidir apenas na UI.
- **Decisão (fechada): A ajustada** —
  - **mundo atual/localStorage:** `authorize()` ocorre **na mesma camada de
    serviço, imediatamente antes da mutação**; nenhuma mutação confia apenas em
    `can()` executado previamente pela UI;
  - **futuro Supabase:** **operações críticas revalidam autorização
    server-side dentro da mesma RPC/transação** que realiza a mutação; RLS
    permanece a última barreira; **uma autorização calculada no cliente nunca é
    prova para a transação**;
  - registrado como **requisito arquitetural para F5/F4-08** (seção 19).
- **Impacto:** minimiza TOCTOU hoje e fecha a janela no server-side futuro.

### D10 — Recursos ainda em localStorage — **FECHADA (A)**

- **Pergunta:** como o engine lê estado/alvo de domínios ainda em localStorage?
- **Alternativas:** (A) provedores que carregam do repositório local (nunca do
  objeto passado pela UI) — mesma interface dos adapters Supabase futuros;
  (B) aceitar estado arbitrário do chamador.
- **Decisão (fechada): A** — repositório como fonte; a UI pede, o serviço
  carrega, o engine decide; limitação (sem enforcement server-side) documentada
  até F5/F4-08.
- **Impacto:** coerente e migrável; sem IDOR.

### D11 — Migração gradual — **FECHADA (A)**

- **Pergunta:** qual a ordem de migração dos fluxos por cargo?
- **Alternativas:** (A) poucos fluxos-piloto de baixo risco primeiro, cobertura
  ampla depois; (B) tudo de uma vez.
- **Decisão (fechada): A** — domínio a domínio, sem big-bang (D15/seção 17).
- **Impacto:** risco baixo e PRs revisáveis.

### D12 — Cache — **FECHADA (A)**

- **Pergunta:** cachear resoluções?
- **Alternativas:** (A) sem cache na F4-03; (B) cache com invalidação.
- **Decisão (fechada): A** — **nenhum cache nesta etapa** (barato hoje e
  revogação imediata); reavaliar com medição real.
- **Impacto:** simples; sem risco de revogação atrasada.

### D13 — Contexto temporal — **FECHADA (A)**

- **Pergunta:** como o engine recebe a data?
- **Alternativas:** (A) data explícita em toda decisão (contexto: agora ou
  ciclo); (B) engine usa `now()` internamente.
- **Decisão (fechada): A** — data explícita; determinismo e histórico corretos
  (D16 F4-02).
- **Impacto:** previsível; sem inconsistência com snapshots.

### D14 — ASSIGNED fail-closed — **FECHADA (A)**

- **Pergunta:** como tratar scopes ASSIGNED enquanto não há resolução de
  F3-08/09 no engine?
- **Alternativas:** (A) DENY sempre que a única via de allow for ASSIGNED sem
  provedor; (B) ignorar o scope e seguir.
- **Decisão (fechada): A** — **ASSIGNED não resolvido = DENY** (fail-closed);
  resolução de colegiado/avaliador chega com F4-05.
- **Impacto:** sem allow por omissão.

### D15 — Boundary F4-03 × F4-04 — **FECHADA (A ajustada)**

- **Pergunta:** o que exatamente a F4-03 entrega vs a F4-04?
- **Alternativas:** (A) F4-03: engine + contratos + matriz + poucos
  fluxos-piloto; F4-04: aplicação ampla; (B) F4-03 cobre todos os fluxos.
- **Decisão (fechada): A ajustada** — F4-03 implementa: **engine genérico;
  contratos/providers; matriz positiva/negativa; poucos fluxos-piloto de baixo
  risco suficientes para provar o engine; e remoção de comparações por cargo
  apenas nesses fluxos cobertos**. **Não migrar agora todos os fluxos
  hierárquicos** — a **F4-04** fará a aplicação ampla de hierarchy + assignments
  à autorização. Evitar sobreposição de escopo entre as duas issues (seção 17).
- **Impacto:** PR revisável e prova do engine sem escopo gigante.

### D16 — Input confiável (anti-IDOR/spoofing) — **FECHADA (A)**

- **Pergunta:** quem fornece actor/org/estado no request?
- **Alternativas:** (A) camada de serviço (sessão + repositório); o engine
  deriva tenant do alvo; (B) aceitar do chamador arbitrário.
- **Decisão (fechada): A** — actor e organização da sessão; **tenant do alvo
  derivado do recurso carregado**; capability/scope resolvidos por providers
  (nunca declarados pelo caller).
- **Impacto:** impede spoofing/IDOR.

### D17 — Identidade DEV × real — **FECHADA (A)**

- **Pergunta:** como o engine resolve actor/membership hoje, sem vínculo
  auth↔collaborator real?
- **Alternativas:** (A) actor da identidade DEV/impersonação (F2-09) resolvido
  via provedor; o mesmo contrato valerá com a identidade real (F5); (B)
  bloquear o engine fora de produção.
- **Decisão (fechada): A** — engine agnóstico de DEV/produção; limitação de
  enforcement server-side documentada.
- **Impacto:** evoluível; utilizável em DEV.

### D18 — Mapa legado cargo → capability/scope (somente migração) — **FECHADA (A ajustada)**

- **Pergunta:** como converter as ~15 regras por `funcao` sem perder semântica?
- **Alternativas:** (A) tabela única de mapeamento num módulo do engine; (B)
  migrar caso a caso sem tabela.
- **Decisão (fechada): A ajustada** — o mapa pode existir **SOMENTE como
  artefato temporário de migração/regressão**; **nunca é consultado pelo engine
  em runtime como fonte permanente de autorização**. Objetivos do mapa:
  documentar a regra antiga; indicar a capability/scope equivalente; permitir
  testes espelhados durante a migração; controlar quais fluxos ainda dependem
  do legado. À medida que cada fluxo migra, a decisão runtime vem
  **exclusivamente** de identity + membership + capability + scope + relation +
  domain state; **quando todos os fluxos forem migrados, o mapa deve poder ser
  removido sem alterar o comportamento do engine**.
- **Impacto:** transição auditável sem legado em runtime; remoção futura sem
  efeito colateral.

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
- **D5/D9:** teste de fronteira de que nenhuma mutação confia em `can()`/
  `listAllowedTargets` — mutações cobertas chamam `authorize()` na camada de
  serviço imediatamente antes de persistir;
- nenhuma página/componente contém comparação por cargo em decisão de ação
  (grep em testes de regressão — "autorização não depende de cargo === ..."
  nos fluxos cobertos; o mapa legado só existe como artefato de migração e não
  é consultado em runtime — D18);
- regras de domínio permanecem nos módulos de domínio (teste de fronteira:
  engine não importa status específico);
- `listAllowedTargets` nunca decide autorização (só listagem); CI/build/lint/
  diff-check e, após F5/F4-08, revalidação server-side atômica + RLS como
  última barreira.

Nada disso é implementado nesta entrega; fica como contrato para as próximas
etapas da Fase 4.

## 26. Implementação e finalização (relatório)

Relatório da implementação da F4-03 (Issue #90), branch
`feat/issue-90-f4-03-policy-engine`, sobre o desenho aprovado (D1–D18 fechadas
+ 16 invariantes). **Nenhuma** migration/RLS/`SECURITY DEFINER`/Supabase remoto.

### 26.1 Arquivos criados/alterados

- Criados:
  - `src/authorization/policyEngine/types.ts` — `AuthorizationRequest`,
    `AuthorizationDecision`, `DenialReason`, `TargetRef` tipado, `ScopeType` e
    contratos dos providers (Identity/Capability/Scope/Target/Relation +
    `DomainStateProbe`);
  - `src/authorization/policyEngine/policyEngine.ts` — `decidir` (pipeline
    determinística de 10 passos), `can`, `authorize` e `listAllowedTargets`;
  - `src/authorization/policyEngine/errors.ts` — mapeamento `DenialReason` →
    código público F0-05 (FORBIDDEN/NOT_FOUND/CONFLICT);
  - `src/authorization/policyEngine/legacyMap.ts` — **mapa legado** (artefato
    temporário de migração/regressão, nunca consultado pelo engine);
  - `src/authorization/providers/localWorld.ts` — providers do mundo atual
    (sem cargo em runtime: `goal.write` + `SELF`);
  - `src/authorization/policyEngine/policyEngine.test.ts` — matriz + fronteira.
- Alterados:
  - `src/authorization/Capability.ts` — adicionada a capability de ação
    `goal.write` (alinhada à taxonomia F4-01);
  - `src/services/metaStorage.ts` — mutações de meta própria passam a chamar
    `authorize()` (engine) na camada de serviço, antes de persistir;
  - `src/pages/MinhasMetasPage.tsx` — UI usa `can()` do engine (apenas UX);
    removido o gate por cargo e o `authorize` da página;
  - `src/services/metaStorage.test.ts` — atualizado para a nova semântica F0-05.

### 26.2 Contratos/providers implementados

Engine genérico com `can`/`authorize`/`listAllowedTargets` e pipeline 1–10
(identidade → profile → membership → tenant → capability → scope → relação →
contexto temporal → estado do domínio → ALLOW), fail-closed (qualquer
indeterminação = DENY). Providers no mundo atual sobre o domínio local; a
interface permite trocar para adapters Supabase (F5) sem reescrever a
semântica (D1/D7).

### 26.3 Fluxo-piloto migrado

**Metas próprias (SELF)** — `MinhasMetasPage` + `metaStorage` (criar, editar,
excluir, atualizar progresso, finalizar). A decisão runtime vem exclusivamente
de `goal.write` + scope `SELF` + relação "alvo = self" + estado do domínio
(ciclo ATIVO) — **sem** `actor.funcao`/cargo.

### 26.4 Regras legadas removidas nesses fluxos

- Removido o gate por cargo `perfilPossuiFluxosPropriosAtuais(funcao)` na
  decisão runtime de metas próprias;
- Removido o `authorize`/`can` legado da página (a UI agora usa `can` do engine
  só para experiência; a mutação autoriza na camada de serviço).

### 26.5 Decisões D1–D18 implementadas

D1 (engine TS com providers), D2 (fonte única de decisão), D3 (probe de domínio
fora do engine), D4 (TargetRef tipado), D5 (can + authorize; listAllowedTargets
auxiliar), D6 (razões internas → público F0-05), D7 (providers TS; sem chamada
SQL), D8 (sem DEFINER), D9 (authorize no serviço antes da mutação), D10
(estado/alvo do repositório local), D11/D15 (piloto sem big-bang), D12 (sem
cache), D13 (data explícita), D14 (ASSIGNED fail-closed), D16 (actor/tenant do
serviço/derivado do alvo), D17 (engine agnóstico DEV/produção), D18 (mapa
legado nunca consultado em runtime).

### 26.6 Testes e resultados

- `src/authorization/policyEngine/policyEngine.test.ts` — matriz positiva/
  negativa (20 pontos) + fronteira (engine não referencia cargo/job_role/
  legacyMap; mapa legado separado e não consultado);
- `src/services/metaStorage.test.ts` — mutações próprias negam com CONFLICT em
  ciclo cancelado (estado de domínio via probe) e com FORBIDDEN para
  colaborador desligado (authorize na camada de serviço);
- `npm test` — **557 testes** (50 arquivos + policyEngine) aprovados;
  `npm run build` (tsc + vite) e `npm run lint` aprovados; `git diff --check`
  aprovado.

### 26.7 Riscos e limitações

- Enforcement real server-side ainda não existe (domínios em localStorage):
  a decisão é correta na camada application, mas a barreira definitiva vem com
  F5/F4-08 (revalidação server-side atômica + RLS) — requisito registrado (D9);
- **Nota de comportamento:** no mundo atual, o provedor local concede `goal.write`
  (SELF) a todo colaborador ativo; com a remoção do gate por cargo, o perfil
  GERENTE também passa a gerenciar as próprias metas — consequência intencional
  da semântica SELF; qualquer restrição futura deve vir de role/scope, nunca de
  cargo;
- `listAllowedTargets` só lista; nunca decide (D5).

### 26.8 Deixado para etapas posteriores

- **F4-04:** aplicação ampla de hierarchy + assignments (aprovações de metas,
  avaliações, relatórios) e remoção dos demais gates por cargo;
- **F4-05:** resolução de ASSIGNED (colegiado/responsabilidades avaliativas) e
  substituição temporária;
- **F4-06:** auditoria; **F4-08:** policies RLS finais;
- **F5:** migração dos domínios para Supabase (adapters dos providers) e
  vínculo real auth↔collaborator.

### 26.9 Confirmação do mapa legado

O **mapa legado não participa da autorização runtime**: `legacyMap.ts` não é
importado por `policyEngine.ts` (teste de fronteira), não concede autorização e
é removível sem alterar o comportamento do engine quando todos os fluxos
migrarem (D18).
