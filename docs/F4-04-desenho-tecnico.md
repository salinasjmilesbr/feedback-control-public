# F4-04 — Desenho técnico: hierarquia e assignments na autorização (Issue #91)

> **Status:** desenho técnico da F4-04 **aguardando revisão**. Decisões
> **D1–D18 abertas** (recomendação indicada em cada uma). Nenhuma
> implementação: sem código, migrations, RLS, `SECURITY DEFINER`, alteração de
> frontend/Edge Functions ou PR de implementação — somente este documento, em
> branch exclusiva de docs.
> Conteúdo 100% conceitual e sintético (sem dados reais).

## 1. Objetivo e boundary

### 1.1 Interpretação da Issue #91

Aplicar, no Policy Engine da F4-03, o **escopo hierárquico** (DIRECT_REPORTS e
DESCENDANTS sobre a estrutura temporal da F3) e as **atribuições explícitas**
(ASSIGNED de colegiado e responsabilidades avaliativas), de modo que gestores,
coordenadores, colegiado e múltiplas posições funcionem pela **mesma relação
organizacional** — nunca por cargo.

### 1.2 O que a F4-04 implementará

- `DIRECT_REPORTS`/`DESCENDANTS` consumindo reporting lines + occupations
  vigentes (F3), com união de múltiplas positions e posição vaga bem definida;
- `ASSIGNED` derivado das **fontes soberanas existentes** (colegiado F3-08 e
  responsabilidades avaliativas F3-09) — sem hierarquia paralela e sem
  duplicação;
- **RelationProvider** evoluído (novos provedores: positions do ator, direct
  reports, descendants, occupations, assigned) integrado ao engine F4-03;
- migração dos **fluxos hierárquicos de avaliação/visibilidade** que ainda
  dependem de cargo/relações legadas (permissaoAvaliacao,
  visibilidadeColaboradores etc.) para capability+scope+relação, na extensão da
  Issue #91 (sem big-bang).

### 1.3 O que permanece para F4-05+

- **Substituição temporária** (F4-05), acesso excepcional (F4-06), RLS final
  (F4-08), persistência Supabase dos domínios (F5) e UI administrativa.

## 2. Estado atual após F4-03

- **Policy Engine** (TS, `src/authorization/policyEngine/`): pipeline 1–10,
  `can`/`authorize`/`listAllowedTargets`, mapeamento F0-05, fail-closed;
  providers por interfaces (identity/capabilities/scopes/targets/relations).
- **Fluxo-piloto SELF** migrado (metas próprias): providers `localWorld`
  (goal.write + SELF), sem cargo.
- **Scopes F4-02**: tipos armazenáveis + resolução SQL INVOKER; no mundo atual
  os providers TS reproduzem a semântica (relações via adapters).
- **Resolvers F3** (INVOKER, por data): responsável da posição, gestor direto,
  subordinados diretos, descendentes, cadeia, escopo de posições/unidades.
- **Pontos legados ainda dependentes de cargo/hierarquia**:
  - `authorizationPolicy.ts` — branches `evaluation.edit.manager/coordinator/
    board`, `goal.approve.manager/coordinator`, `observation.*` etc. via
    `actor.funcao`;
  - `permissaoAvaliacao.ts` — `funcao === GERENTE/COORDENADOR` + gestor direto
    + `avaliadoresColegiadoMatriculas` (lista manual no colaborador);
  - `visibilidadeColaboradores.ts` — scoping por funcao + gestorDireto +
    colegiado;
  - páginas que chamam esses gates (FeedbackDetalhe, EditarFeedback,
    CiclosAvaliacao, PainelCiclo, NavegacaoPrincipal etc.).

## 3. Modelo de autorização hierárquica

```
capability
+ DIRECT_REPORTS / DESCENDANTS (scope ativo da atribuição)
+ positions vigentes do ator (occupations na data)
+ reporting lines vigentes (F3)
+ occupations vigentes do alvo (collaborators reais)
+ tenant (mesma organização)
+ contexto temporal (data)
= relação permitida
```

Sem nenhuma referência ao nome do cargo: a relação é **reporting line entre
positions + occupations**, e o alvo humano é o **ocupante real** da posição na
data. O engine F4-03 permanece a porta única (nenhuma segunda implementação de
autorização).

## 4. DIRECT_REPORTS

Precisamente:

1. **Positions do ator**: todas as occupations vigentes do colaborador vinculado
   à membership na data de contexto (resolver vinculo F4-02 → occupations F3);
2. **Positions subordinadas**: `position_reporting_lines` vigentes com
   `manager_position_id` ∈ positions do ator;
3. **Occupants**: occupations vigentes dessas positions subordinadas na data →
   colaboradores reais;
4. **Posição vaga**: não retorna collaborator (não cria pessoa artificial);
5. **Multi-position**: união das posições subordinadas de cada position do ator,
   **deduplicada por collaborator**;
6. **Tenant**: todas as linhas da mesma organização (FKs compostas na F3); o
   provider nunca cruza org.

**Ator sem collaborator/occupation**: DIRECT_REPORTS resolve **vazio**
(fail-closed) — nenhum alvo inventado.

## 5. DESCENDANTS

- Consome a **árvore formal da F3** (reporting lines temporais, sem ciclos por
  trigger F3-04), partindo de **todas** as positions vigentes do ator;
- percorre descendentes formais, resolve occupants (responsável efetivo no
  contexto vivo — D9 F4-02), deduplica por position e por collaborator;
- **posição vaga não é alvo humano**, mas **não quebra a árvore**: a recursão
  continua abaixo dela (ver decisão D1 — não interromper);
- **cross-tenant**: impossível (todos os nós pertencem à organização do ator;
  se algum nó divergisse, o provider nega e o engine falha fechado).

**Decisão explícita requerida (D1):** posição vaga **intermediária** NÃO
interrompe a travessia de descendents (a árvore é de positions; a vacância é do
occupant). Recomendação: atravessar; os descendentes reais abaixo continuam
alvos. (Registrar como decisão — não assumir.)

## 6. Níveis futuros

Prova arquitetural: Coordenador, Gerente, Gerente Sênior, Diretor — e qualquer
nível futuro — funcionam **pela mesma relação de reporting line**:
um Diretor ocupa uma position-raiz; `DIRECT_REPORTS`/`DESCENDANTS` resolvem da
mesma forma que para um Gerente. Não existem:
- `if role === GERENTE`, `if funcao === COORDENADOR`;
- capabilities `manager.*`/`director.*`;
- níveis codificados.

O alcance cresce **apenas** porque a position ocupada está mais alta na árvore
(mesma regra, mais nós alcançados).

## 7. Múltiplas positions

- O scope (DIRECT_REPORTS/DESCENDANTS) pertence à **atribuição
  (membership→role→scope)**, e se aplica à **união** dos alcances de **todas**
  as positions vigentes do colaborador vinculado na data;
- o caller **não escolhe** qual position concede acesso: o provider resolve
  todas as positions confiáveis e o engine calcula a união (D3/D18 segurança);
- **deduplicação** por alvo (collaborator/position);
- mesma pessoa em dois ramos: entra uma vez como alvo;
- position A com DIRECT_REPORTS e position B com DESCENDANTS: união dos dois
  conjuntos (o scope é único; as regras são do mesmo tipo de scope);
- tenant soberano em cada ramo.

## 8. ASSIGNED

**Crítico.** O engine resolve ASSIGNED **sem criar hierarquia paralela** e sem
duplicar fontes existentes.

### A. Fontes soberanas existentes (implementar na F4-04)

- **Colegiado/snapshot (F3-08)**: quem é membro do colegiado do avaliado X no
  ciclo está em `collegiate_cycle_snapshot_members` (imutável) — a fonte do
  ASSIGNED de colegiado;
- **Responsabilidade avaliativa (F3-09)**: quem é avaliador responsável de uma
  posição/avaliado no ciclo está em `cycle_evaluation_responsibilities`
  (+ sucessão) — a fonte do ASSIGNED de avaliador.

O `relationProvider` resolve "o alvo (avaliado/posição + ciclo) está ASSIGNED
ao ator?" consultando essas estruturas — **sem tabela de targets nova** nesta
fase.

### B. Futuras atribuições ad hoc

Somente quando houver fonte concreta (persistência F5/futuro), com targets
tipados por entidade e integridade de tenant — nunca `target_type + target_id`
genérico sem integridade.

**Para a F4-04**: implementar somente as fontes concretas da Issue #91
(colegiado e responsabilidade avaliativa derivados).

## 9. Colegiado

Definições explícitas:

- membro do colegiado recebe acesso **somente à avaliação/recurso atribuído**
  (o avaliado X no ciclo C);
- **não** recebe acesso ao collaborator inteiro;
- **não** recebe DIRECT_REPORTS nem DESCENDANTS do avaliado;
- **não** recebe outros recursos do mesmo colaborador por consequência (ex.:
  ASSIGNED a X não dá metas/observações de X — ver §16);
- o **snapshot do ciclo é soberano** para histórico; alterações posteriores da
  estrutura **não reescrevem** colegiado histórico.

Representação no TargetRef/RelationProvider: alvo `evaluation` (avaliado ×
posição × ciclo) derivado do snapshot; o provider de relações confirma
membro∈snapshot_members(X,C) — nunca por cargo.

## 10. Responsabilidade avaliativa

Integração com F3-09, distinguindo:

| Conceito | Fonte | Papel na autorização |
| --- | --- | --- |
| Responsável formal (estrutura viva) | positions/reporting/occupations na data (F3-07) | escopos estruturais no contexto vivo (D9 F4-02) |
| Responsável avaliativo congelado | `cycle_evaluation_responsibilities` (F3-09, snapshot por ciclo) | base do ASSIGNED de avaliador no ciclo |
| Sucessão explícita | `evaluation_succession_events` (append-only) | atualiza o responsável avaliativo do ciclo (não reescreve histórico) |
| ASSIGNED | derivado das duas anteriores | capability de avaliação sobre o avaliado/posição do ciclo |

Substituição temporária (F4-05) fica fora. Nenhuma duplicação de F3-09.

## 11. Estrutura viva vs histórico

- **Operações organizacionais atuais** (ex.: listar subordinados hoje, mover
  estrutura): reporting lines/occupations **na data do contexto** (data
  corrente do serviço);
- **Avaliações/ciclos**: snapshots e responsabilidades **congeladas** quando
  aplicável (F3-08/09);
- **nunca** reconstruir histórico usando apenas a estrutura atual — o engine
  recebe o contexto (ciclo) e o provider decide a fonte (D9/D12 F4-02/F4-04).

## 12. Posição vaga

- Posição vaga **não é collaborator**: nenhuma autorização para pessoa
  inexistente;
- como **alvo** (ex.: abrir occupation): é alvo estrutural legítimo para quem
  tem escopo sobre a posição/unidade — o engine distingue alvo `position`
  (estrutural, sem occupant) de alvo `collaborator` (pessoa);
- posição vaga **intermediária** na árvore: **não** faz desaparecer os
  descendentes reais abaixo dela (D1) — a árvore é de positions.

## 13. Providers

Evolução dos providers F4-03 (sem provider monolítico). Novas interfaces
candidatas (TS, mundo atual; adapters Supabase no futuro):

```ts
interface PositionsProvider {
  getPositions(actorId, orgId, date): PositionRef[];       // occupations vigentes do ator
}
interface HierarchyProvider {
  getDirectReports(positions, date): TargetRef[];           // occupants reais
  getDescendants(positions, date): TargetRef[];             // árvore (dedup; atravessa vaga)
  isAncestorOf(actorPositions, targetPosition, date): boolean;
}
interface OccupationsProvider {
  getOccupants(position, date): CollaboratorRef[];          // vazia se vaga
}
interface AssignedProvider {
  isAssigned(actorId, orgId, capability, target, context): boolean; // F3-08/09 derivado
}
```

O `RelationProvider` do engine (F4-03) passa a delegar a esses provedores por
tipo de scope, mantendo a mesma porta de decisão.

## 14. Integração com Policy Engine

Fluxo (engine F4-03, inalterado):

```
authorize(request)
 → pipeline 1–4 (identidade/profile/membership/tenant)
 → capability (provider)
 → scope ativo (provider)          [DIRECT_REPORTS | DESCENDANTS | ... ]
 → relationProvider.isTargetInScope(actor, org, scope, target, date)
      · DIRECT_REPORTS/DESCENDANTS → HierarchyProvider + OccupationsProvider
      · ASSIGNED                   → AssignedProvider (F3-08/09)
 → target (tenant derivado do recurso)
 → domain state (probe)
 → decision (ALLOW/DENY)
```

O engine **não sabe** o que é Gerente/Coordenador: conhece apenas
`capability` + `scope` + `target` + `date` + probe.

## 15. Fluxos que devem migrar

Classificação (inventário concreto do estado atual):

**A — migrar na F4-04 (escopo Issue #91):**
- `authorizationPolicy` branches de avaliação por relação
  (`evaluation.create`, `evaluation.edit.manager/coordinator/board`,
  `evaluation.cancel/reopen.manager`, `evaluation.view.admin`), resolvidos
  agora por `obterPermissoesAvaliacao`/`podeAprovarMetaNoCiclo` (parcial);
- visibilidade de colaboradores (`scopeCollaborators`/`getColaboradoresVisiveis`)
  para gestão de equipe (DIRECT_REPORTS/DESCENDANTS) e colegiado (ASSIGNED);
- aprovação de metas por gerente/coordenador (DIRECT_REPORTS/DESCENDANTS) e
  gates `goal.approve.*`.

**B — deixar para F4-05:**
- efeito de substituição temporária nos scopes.

**C — deixar para a persistência F5/F4-08:**
- enforcement server-side/RLS; vínculo real auth↔collaborator; avaliações/metas
  em Supabase.

**D — não é autorização:**
- rótulos de cargo (exibição), ordenações, formatações.

Sem big-bang além da Issue #91: o piloto SELF da F4-03 permanece e os fluxos A
migram sobre o mesmo engine (mapa legado atualizado, nunca runtime — D18 F4-03).

## 16. ASSIGNED e capability

Reforço: **ASSIGNED sozinho não concede nada** — capability decide a ação e o
tipo de recurso:

- `evaluation.read` + ASSIGNED(avaliação X) ⇒ permite X;
- `goal.read` + ASSIGNED(avaliação X) ⇒ **não** permite meta alguma.

Impedir confusão de resource type: o alvo tipado (`evaluation` vs `goal` vs
`collaborator`) é vinculado à capability pedida por um **validador capability↔
tipo de alvo** (ex.: capabilities `evaluation.*` só aceitam alvo `evaluation`/
`collaborator` em contexto avaliativo; `goal.*` só `goal`/`collaborator` dono).
Sem validação ⇒ DENY (fail-closed).

## 17. Tenant isolation

Todos os caminhos com tenant explícito (FKs compostas na F3; org derivada do
recurso no engine):
- position do ator, occupation do alvo, reporting line, collegiate snapshot,
  evaluation responsibility e assigned target — qualquer mismatch ⇒
  provider retorna falso/vazio e o engine DENY (fail-closed); nenhum alvo de
  outra organização é resolvido.

## 18. Segurança

- **IDOR:** alvo resolvido por provider (nunca confiar que o caller "já
  passou");
- **spoofing de collaborator/position:** tenant/positions derivados de fontes
  confiáveis (occupations/reporting lines), nunca do request;
- **caller escolhendo uma position conveniente:** o provider resolve **todas**
  as positions confiáveis do ator; o engine calcula a união — o caller não
  indica qual position usar (D3);
- **união excessiva em multi-position:** a união é limitada às positions
  reais do colaborador vinculado (nunca qualquer position da org);
- **ASSIGNED como wildcard:** ASSIGNED confere somente o alvo tipado
  atribuído; capability↔tipo valida; nada além;
- **árvore histórica reconstruída incorretamente:** contexto de ciclo usa
  snapshot (nunca estrutura atual);
- **posição vaga:** sem pessoa artificial; alvo estrutural explícito;
- **cross-tenant:** §17;
- **bypass por frontend:** engine continua a única porta; mutações usam
  `authorize()` na camada de serviço (D9 F4-03).

## 19. Performance

- Descendants: travessia única com `distinct` (F3-07 no futuro servidor;
  TS no mundo atual sobre o grafo local) — evita N+1;
- múltiplas positions: união em um passe;
- deduplicação por position/collaborator;
- **sem cache** que atrase revogação nesta fase (reavaliar com medição, F4-03
  D12).

## 20. Matriz de exemplos (sintéticos)

| # | Cenário | Resultado |
| --- | --- | --- |
| 1 | Gerente → todos os descendents | ALLOW (DESCENDANTS) |
| 2 | Coordenador → seus direct reports | ALLOW (DIRECT_REPORTS) |
| 3 | Coordenador → descendants do próprio ramo | ALLOW (DESCENDANTS no ramo) |
| 4 | Coordenador → outra coordenação | DENY (fora da árvore) |
| 5 | Coordenador → avaliação externa via ASSIGNED | ALLOW só nessa avaliação |
| 6 | o mesmo ASSIGNED não dá acesso ao resto da outra coordenação | DENY (fora do alvo) |
| 7 | Colegiado → apenas a avaliação atribuída | ALLOW (ASSIGNED derivado F3-08) |
| 8 | Colegiado → hierarchy do avaliado | DENY (sem DIRECT_REPORTS/DESCENDANTS) |
| 9 | Diretor funciona pela árvore | ALLOW (sem regra por cargo) |
| 10 | Gerente Sênior funciona pela árvore | ALLOW (sem regra por cargo) |
| 11 | Pessoa com duas positions | união correta de escopos |
| 12 | Posição vaga como alvo (estrutural) | ALLOW só para alvo position; sem pessoa |
| 13 | Posição vaga intermediária | árvore continua; descendentes reais alvos (D1) |
| 14 | Collaborator fora da árvore | DENY |
| 15 | Membership disabled | DENY |
| 16 | Profile disabled | DENY |
| 17 | Cross-tenant | DENY/NOT_FOUND |
| 18 | Histórico de ciclo permanece congelado | ALLOW/DENY pela F3-08/09 da época |

## 21. Testes de regressão

Como provar que nenhum fluxo migrado continua consultando cargo/job_role/nome
de cargo/gerente-coordenador hardcoded:

- testes de fronteira (estilo F4-03): o módulo de decisão dos fluxos migrados
  não referencia `funcao`/`cargo`/`job_role` (verificação da superfície e
  comportamento com cargos distintos);
- matriz comportamental: mesmo cenário com atores de cargos diferentes (Gerente
  vs Diretor vs Analista) e posições equivalentes produz decisões idênticas —
  a diferença vem só da árvore;
- grep de regressão (CI) sobre `src` dos fluxos cobertos para `=== "GERENTE"`,
  `=== "COORDENADOR"`, `funcao ===`;
- `authorizationPolicy` legado: usado apenas pelos fluxos ainda não migrados;
  testes existentes continuam (caracterização) até a migração completa.

## 22. Riscos e invariantes

Invariantes:

1. capability define a ação; scope define o alcance; relação vem de
   positions/reporting lines/occupations (nunca cargo);
2. DIRECT_REPORTS/DESCENDANTS usam a estrutura temporal da F3 na data;
3. múltiplas positions ⇒ união deduplicada de alvos; tenant soberano;
4. posição vaga não cria collaborator artificial e não interrompe a árvore
   (D1);
5. colegiado concede somente o recurso/avaliação atribuído (ASSIGNED), sem
   hierarchy nem outros recursos por consequência;
6. ASSIGNED sozinho não concede nada; capability decide a ação e o tipo de
   alvo;
7. estrutura viva × histórico de ciclo permanecem separados (snapshot
   soberano);
8. F4-03 Policy Engine é a porta central; nenhuma segunda implementação;
9. fail-closed; sem SUPER_ADMIN; sem capabilities por cargo;
10. nenhuma migration/RLS/DEFINER nesta fase (salvo decisão explícita);
11. nenhum cache que atrase revogação;
12. cross-tenant impossível (mismatch ⇒ DENY).

## 23. Decisões pendentes (D1–D18)

Para cada decisão: pergunta, alternativas, recomendação e impacto. Todas
**abertas** para revisão do desenho.

### D1 — Posição vaga intermediária interrompe ou não descendants?

- **Pergunta:** ao atravessar a árvore, uma posição vaga no meio interrompe a
  recursão?
- **Alternativas:** (A) atravessar: descendentes reais abaixo continuam alvos;
  (B) interromper: ramo vazio a partir da vaga.
- **Recomendação:** (A) — a árvore é de positions (F3-04); vacância é ausência
  de occupant; interromper criaria buracos indevidos de acesso de gestão.
- **Impacto:** (A) gestão contínua sob posições vagas (alvos reais preservados);
  (B) simplifica mas "desliga" ramos sem necessidade.

### D2 — Qual data governa a estrutura viva?

- **Pergunta:** a data de contexto da estrutura viva vem de onde?
- **Alternativas:** (A) data explícita por request (padrão; "agora" = relógio do
  serviço); (B) `now()` interno ao provider.
- **Recomendação:** (A) — determinismo e consistência com ciclo (F4-02 D16 /
  F4-03 D13).
- **Impacto:** (A) previsível e testável; (B) inconsistente com snapshots.

### D3 — União de múltiplas positions (quem resolve)

- **Pergunta:** quem determina as positions usadas na união?
- **Alternativas:** (A) provider resolve todas as positions confiáveis do ator
  e o engine une; (B) caller informa a position.
- **Recomendação:** (A) — impede escolha de position conveniente (security §18).
- **Impacto:** (A) seguro; (B) ampliaria privilégio (rejeitado).

### D4 — Shape de ASSIGNED para avaliação

- **Pergunta:** qual a representação do alvo ASSIGNED de avaliação?
- **Alternativas:** (A) derivado: alvo `evaluation`/`collaborator`+ciclo
  confirmado contra F3-08/09 (sem tabela nova); (B) tabela de targets própria.
- **Recomendação:** (A) — fonte soberana já existe (F3-08/09); sem duplicação.
- **Impacto:** (A) sem duplicação e imutável por ciclo; (B) duplicaria.

### D5 — Fonte soberana do colegiado

- **Pergunta:** qual estrutura define "membro do colegiado de X no ciclo"?
- **Alternativas:** (A) `collegiate_cycle_snapshot_members` (F3-08) (ou a
  configuração temporal `collegiate_configurations` antes da materialização);
  (B) cópia local no frontend.
- **Recomendação:** (A) — snapshot é a verdade por ciclo.
- **Impacto:** (A) histórico correto; (B) divergente (rejeitado).

### D6 — Relação ASSIGNED × responsabilidade avaliativa (F3-09)

- **Pergunta:** como o ASSIGNED de avaliador se relaciona com F3-09?
- **Alternativas:** (A) derivado da `cycle_evaluation_responsibilities` (com
  sucessão) — o avaliador "atribuído" é o responsável avaliativo do ciclo;
  (B) registrar ASSIGNED à parte.
- **Recomendação:** (A) — F3-09 é a fonte; sem paralelismo.
- **Impacto:** (A) coeso; (B) duas fontes (rejeitado).

### D7 — Como o RelationProvider recebe targets tipados

- **Pergunta:** a interface recebe quais targets?
- **Alternativas:** (A) `TargetRef` tipado (collaborator/position/evaluation/
  ...) e o provider despacha por tipo; (B) strings livres.
- **Recomendação:** (A) — continua o contrato F4-03/D4.
- **Impacto:** (A) sem spoofing; (B) inseguro (rejeitado).

### D8 — Quais fluxos legados migram agora

- **Pergunta:** qual a extensão da migração na F4-04?
- **Alternativas:** (A) fluxos A da seção 15 (avaliação por relação,
  visibilidade de gestão, aprovação de metas); (B) todos os fluxos.
- **Recomendação:** (A) — escopo Issue #91, sem big-bang.
- **Impacto:** (A) revisável; (B) grande demais.

### D9 — Ator sem occupation (scopes estruturais)

- **Pergunta:** o que DIRECT_REPORTS/DESCENDANTS retornam quando o ator não
  possui collaborator/occupation?
- **Alternativas:** (A) vazio (fail-closed); (B) tratar como ORGANIZATION-like.
- **Recomendação:** (A) — estrutura exige positions reais.
- **Impacto:** (A) seguro; (B) ampliaria (rejeitado).

### D10 — Deduplicação de alvos

- **Pergunta:** como deduplicar alvos entre positions/ramos?
- **Alternativas:** (A) dedup por `position_id` e por `collaborator_id`
  (collaborator com 2 positions entra uma vez como alvo humano); (B) sem dedup.
- **Recomendação:** (A).
- **Impacto:** (A) conjuntos corretos; (B) duplicidade em listagens.

### D11 — Tenant mismatch

- **Pergunta:** comportamento quando qualquer nó da resolução pertence a outra
  org?
- **Alternativas:** (A) provider retorna falso/vazio; engine DENY (fail-closed);
  (B) ignorar o nó.
- **Recomendação:** (A).
- **Impacto:** (A) sem vazamento; (B) vazamento (rejeitado).

### D12 — Histórico vs estrutura viva (fronteira de fonte)

- **Pergunta:** quem decide usar snapshot vs estrutura viva?
- **Alternativas:** (A) o contexto do request (ciclo ⇒ snapshot; vivo ⇒ data) —
  o provider recebe contexto e usa a fonte certa; (B) cada provider escolhe.
- **Recomendação:** (A) — F4-02 D9/D16.
- **Impacto:** (A) coerente; (B) divergência.

### D13 — Responsabilidade por listAllowedTargets

- **Pergunta:** quem resolve a lista de alvos para listagens?
- **Alternativas:** (A) serviço auxiliar delegando aos mesmos providers
  (Hierarchy/Occupations/Assigned), nunca decidindo; (B) lógica própria.
- **Recomendação:** (A) — D5 F4-03.
- **Impacto:** (A) sem terceira fonte de decisão; (B) duplicaria.

### D14 — Alguma migration é realmente necessária na F4-04?

- **Pergunta:** o desenho exige alteração de schema?
- **Alternativas:** (A) não — relações derivam de F3/F4-02 e o ASSIGNED de
  F3-08/09 (tudo já modelado); implementação em TS/adapter; (B) sim (ex.:
  tabela de ASSIGNED explícito).
- **Recomendação:** (A) — evita migration sem consumidor concreto; ad hoc
  (B) fica para quando houver fonte persistente (F5).
- **Impacto:** (A) sem schema novo; (B) antecipação.

### D15 — SECURITY DEFINER seria necessário?

- **Pergunta:** há necessidade de função privilegiada?
- **Alternativas:** (A) não (resolução INVOKER/TS no mundo atual; servidor
  futuro via service_role com contrato único); (B) sim.
- **Recomendação:** (A) — nenhum DEFINER novo.
- **Impacto:** (A) sem superfície privilegiada.

### D16 — Boundary F4-04 × F4-05

- **Pergunta:** onde termina a F4-04?
- **Alternativas:** (A) hierarquia + ASSIGNED derivado (colegiado/avaliador) +
  fluxos A; substituição temporária e mapa de domínios na F4-05; (B) incluir
  substituição.
- **Recomendação:** (A).
- **Impacto:** (A) escopo Issue #91; (B) sobreposição com F4-05.

### D17 — Responsável efetivo vs titular no contexto vivo (resolução hierárquica)

- **Pergunta:** DIRECT_REPORTS/DESCENDANTS no contexto vivo usam o titular ou o
  responsável efetivo da posição (substituto operacional)?
- **Alternativas:** (A) responsável efetivo na data (F3-07; D9 F4-02); (B)
  titular estrito.
- **Recomendação:** (A) — coerente com F3-07; histórico de ciclo segue a F3-08/09
  congelada.
- **Impacto:** (A) gestão flui com substituto; histórico intacto.

### D18 — Validação capability ↔ tipo de alvo (evitar confusão)

- **Pergunta:** como impedir `goal.read` + ASSIGNED(avaliação X)?
- **Alternativas:** (A) validador capability↔tipo de alvo no engine (regras por
  domínio: evaluation.*→evaluation; goal.*→goal; ...); (B) só convenção.
- **Recomendação:** (A) — mapeamento declarado no engine (ou fornecido por
  módulo de domínio), fail-closed.
- **Impacto:** (A) impede confusão; (B) risco (rejeitado).

## 24. Proposta de implementação

Arquivos/camadas provavelmente alterados (reutilizando F3/F4-02/F4-03):

- `src/authorization/policyEngine/` — `RelationProvider` delegando a novos
  provedores; validador capability↔alvo (D18);
- `src/authorization/providers/hierarchy.ts`, `occupations.ts`,
  `assigned.ts` — novos providers (positions do ator, direct reports,
  descendants, occupants, assigned F3-08/09) sobre os dados locais/F3;
- `src/services/` — migração dos fluxos A (avaliação, visibilidade,
  aprovação) para `authorize`/`can` do engine;
- `src/authorization/authorizationPolicy.ts` — reduzido aos fluxos ainda não
  migrados (mapa legado atualizado, nunca runtime);
- testes espelhados + regressão (grep cargo).

## 25. Proposta de validação

Testes positivos/negativos e de regressão:

- matriz §20 (18 cenários) parametrizada no engine com providers sintéticos
  multi-position e multi-org;
- DIRECT_REPORTS/DESCENDANTS: união correta, dedup, vaga sem pessoa, vaga
  intermediária atravessada (D1), tenant;
- ASSIGNED: colegiado só na avaliação atribuída; sem hierarchy; sem
  extravasar para metas/observações (D18); responsabilidade avaliativa derivada
  de F3-09;
- níveis futuros: Diretor/Gerente Sênior sem regra por cargo (comportamental);
- lifecycle: membership/profile disabled ⇒ DENY; cross-tenant ⇒ DENY/NOT_FOUND;
- contexto: histórico congelado (snapshot) não reescrito;
- regressão: nenhum fluxo migrado consulta cargo (testes de fronteira + grep);
- suite completa: `npm test` (inclui caracterização existente), `npm run build`,
  `npm run lint`, `git diff --check`.

Nada disso é implementado nesta entrega; fica como contrato para as próximas
etapas da Fase 4.
