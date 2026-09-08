# F4-04 — Desenho técnico: hierarquia e assignments na autorização (Issue #91)

> **Status:** revisão arquitetural **concluída**; decisões D1–D18 **fechadas**
> na seção 23 (D8, D17 e D18 com ajustes registrados). Nenhuma
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
- percorre descendentes formais e resolve os **occupants/titulares vigentes**
  (occupations na data; sem herança de autorização ao substituto temporário —
  D17, ver §11), deduplica por position e por collaborator;
- **posição vaga não é alvo humano**, mas **não quebra a árvore**: a recursão
  continua abaixo dela (ver decisão D1 — não interromper);
- **cross-tenant**: impossível (todos os nós pertencem à organização do ator;
  se algum nó divergisse, o provider nega e o engine falha fechado).

**Decisão (D1 = A):** posição vaga **intermediária** NÃO interrompe a travessia
de descendants (a árvore é de positions; a vacância é do occupant): atravessar;
os descendentes reais abaixo continuam alvos (invariante 4).

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
| Responsável formal (estrutura viva) | positions/reporting/occupations na data | escopos estruturais usam **occupants/titulares vigentes**; sem efeito autorizativo do substituto na F4-04 (D17) |
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

**Boundary com F4-05 (D17 = A ajustada):** a F4-04 **não** concede autorização
ao substituto temporário como efeito novo. Registro explícito:
- a árvore formal continua definida por **positions + reporting lines**;
- **occupants/titulares vigentes** são usados nos casos normais da F4-04;
- `temporary_responsibilities` permanecem como **dado estrutural da F3** (sem
  scope persistido, sem tratar o substituto como possuidor automático das
  capabilities/scopes do titular, sem antecipar o mapa
  responsibility_type × capability);
- se algum resolver F3-07 devolver `responsible_collaborator_id` com substituto,
  a F4-04 **não** converte isso automaticamente em nova concessão de
  autorização;
- **qualquer herança de autorização pelo substituto pertence exclusivamente à
  F4-05**;
- histórico de ciclo permanece soberano pela F3-08/F3-09.

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

## 15. Fluxos que devem migrar (D8 = A ajustada — fechada)

**Conjunto mínimo** migrado na F4-04 (necessário para provar hierarchy +
ASSIGNED da Issue #91 — sem big-bang):

1. **Visibilidade hierárquica de colaboradores/equipe**:
   - DIRECT_REPORTS; DESCENDANTS; união de múltiplas positions
   (`scopeCollaborators`/`getColaboradoresVisiveis` sobre os novos providers);
2. **Autorização de avaliação baseada em relação**:
   - gestor pela hierarquia (DIRECT_REPORTS/DESCENDANTS);
   - colegiado via ASSIGNED (derivado de F3-08);
   - responsabilidade avaliativa via fonte F3-09;
3. **Um fluxo de aprovação hierárquica de metas**, somente se puder reutilizar
   exatamente a mesma infraestrutura sem ampliar muito o PR.

Fluxos de avaliação/metas/observações fora desse mínimo **permanecem legados**
(até a migração em issues posteriores), sem big-bang.

**B — F4-05:** efeito autorizativo de substituição temporária.
**C — F5/F4-08:** enforcement server-side/RLS; vínculo auth↔collaborator.
**D — não é autorização:** rótulos de cargo, ordenações, formatações.

O piloto SELF da F4-03 permanece; o mapa legado é atualizado somente para os
fluxos cobertos (nunca runtime — D18 F4-03).

## 16. ASSIGNED e capability

Reforço: **ASSIGNED sozinho não concede nada** — capability decide a ação e o
tipo de recurso:

- `evaluation.read` + ASSIGNED(avaliação X) ⇒ permite X;
- `goal.read` + ASSIGNED(avaliação X) ⇒ **não** permite meta alguma.

**Contrato fechado capability ↔ tipo de alvo (D18 = A ajustada):** existe um
contrato de **compatibilidade** apenas para impedir combinações
semanticamente impossíveis:
- `evaluation.*` só opera sobre alvo `evaluation` (ou subtarget claramente
  derivado da avaliação);
- `goal.*` não usa ASSIGNED de `evaluation`;
- `observation.*` não usa alvo `goal`.

O contrato **não** concede autorização, não substitui capability/scope/
relationProvider, não reimplementa regras de domínio e não cria uma segunda
matriz de policy — apenas valida o tipo de recurso compatível com a capability
pedida. Incompatibilidade ⇒ DENY (fail-closed).

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

Invariantes **reforçadas na revisão arquitetural**:

1. cargo/job_role **nunca** participa da decisão runtime dos fluxos migrados;
2. DIRECT_REPORTS/DESCENDANTS partem de **todas** as positions confiáveis do
   ator;
3. o caller nunca escolhe qual position concede acesso;
4. posição vaga intermediária **não quebra** a árvore;
5. posição vaga nunca cria collaborator artificial;
6. múltiplas positions produzem **união deduplicada** de alvos;
7. colegiado concede somente o **recurso de avaliação atribuído**;
8. ASSIGNED não cria hierarchy;
9. ASSIGNED não funciona como wildcard;
10. F3-08/F3-09 são **fontes soberanas** para histórico e responsabilidades
    avaliativas;
11. estrutura viva e histórico de ciclo não se misturam;
12. substituição temporária **não concede autorização na F4-04**;
13. o efeito autorizativo da substituição pertence **exclusivamente à F4-05**;
14. tenant mismatch = DENY;
15. nenhum `SECURITY DEFINER` novo;
16. nenhuma migration necessária;
17. nenhum cache;
18. Policy Engine F4-03 continua sendo a única porta de decisão.

## 23. Decisões fechadas (D1–D18)

Registro final da revisão arquitetural: cada decisão indica a alternativa
**fechada** e o impacto correspondente. **D8, D17 e D18 incorporam ajustes
obrigatórios** da revisão.

**Resumo dos fechamentos:** D1 = A · D2 = A · D3 = A · D4 = A · D5 = A ·
D6 = A · D7 = A · D8 = **A ajustada** · D9 = A · D10 = A · D11 = A · D12 = A ·
D13 = A · D14 = A · D15 = A · D16 = A · D17 = **A ajustada** · D18 = **A
ajustada**.

### D1 — Posição vaga intermediária interrompe ou não descendants? — **FECHADA (A)**

- **Pergunta:** ao atravessar a árvore, uma posição vaga no meio interrompe a
  recursão?
- **Alternativas:** (A) atravessar (descendentes reais abaixo continuam alvos);
  (B) interromper.
- **Decisão (fechada): A** — atravessar: a árvore é de positions; a vacância é
  ausência de occupant.
- **Impacto:** gestão contínua sob posições vagas; invariante 4.

### D2 — Qual data governa a estrutura viva? — **FECHADA (A)**

- **Pergunta:** a data de contexto da estrutura viva vem de onde?
- **Alternativas:** (A) data explícita por request ("agora" = relógio do
  serviço); (B) `now()` interno ao provider.
- **Decisão (fechada): A** — data explícita (F4-02 D16 / F4-03 D13).
- **Impacto:** determinismo; sem inconsistência com snapshots.

### D3 — União de múltiplas positions (quem resolve) — **FECHADA (A)**

- **Pergunta:** quem determina as positions usadas na união?
- **Alternativas:** (A) provider resolve todas as positions confiáveis e o
  engine une; (B) caller informa a position.
- **Decisão (fechada): A** — o provider resolve **todas** as positions do ator;
  o caller nunca escolhe (invariantes 2 e 3).
- **Impacto:** impede escolha de position conveniente.

### D4 — Shape de ASSIGNED para avaliação — **FECHADA (A)**

- **Pergunta:** qual a representação do alvo ASSIGNED de avaliação?
- **Alternativas:** (A) derivado (alvo `evaluation`/`collaborator`+ciclo
  confirmado contra F3-08/09, sem tabela nova); (B) tabela de targets própria.
- **Decisão (fechada): A** — derivado das fontes soberanas; sem duplicação.
- **Impacto:** imutável por ciclo; sem paralelismo.

### D5 — Fonte soberana do colegiado — **FECHADA (A)**

- **Pergunta:** qual estrutura define "membro do colegiado de X no ciclo"?
- **Alternativas:** (A) `collegiate_cycle_snapshot_members` (F3-08); (B) cópia
  local no frontend.
- **Decisão (fechada): A** — snapshot da F3-08 é a verdade por ciclo.
- **Impacto:** histórico correto; invariante 10.

### D6 — Relação ASSIGNED × responsabilidade avaliativa (F3-09) — **FECHADA (A)**

- **Pergunta:** como o ASSIGNED de avaliador se relaciona com F3-09?
- **Alternativas:** (A) derivado da `cycle_evaluation_responsibilities` (com
  sucessão); (B) registrar ASSIGNED à parte.
- **Decisão (fechada): A** — F3-09 é a fonte; sem paralelismo.
- **Impacto:** coeso; invariante 10.

### D7 — Como o RelationProvider recebe targets tipados — **FECHADA (A)**

- **Pergunta:** a interface recebe quais targets?
- **Alternativas:** (A) `TargetRef` tipado (provider despacha por tipo);
  (B) strings livres.
- **Decisão (fechada): A** — contrato F4-03/D4.
- **Impacto:** sem spoofing.

### D8 — Quais fluxos legados migram agora — **FECHADA (A ajustada)**

- **Pergunta:** qual a extensão da migração na F4-04?
- **Alternativas:** (A) conjunto mínimo para provar hierarchy + ASSIGNED;
  (B) todos os fluxos.
- **Decisão (fechada): A ajustada** — **sem migração ampla**: apenas (1)
  visibilidade hierárquica de colaboradores/equipe (DIRECT_REPORTS,
  DESCENDANTS, união de múltiplas positions); (2) autorização de avaliação por
  relação (gestor pela hierarquia; colegiado via ASSIGNED; responsabilidade
  avaliativa via F3-09); (3) **um** fluxo de aprovação hierárquica de metas,
  somente se reutilizar exatamente a mesma infraestrutura sem ampliar o PR.
  O objetivo é remover dependência de cargo **nos fluxos cobertos**, não fazer
  big-bang (seção 15).
- **Impacto:** PR focado; demais fluxos permanecem legados até issues
  posteriores.

### D9 — Ator sem occupation (scopes estruturais) — **FECHADA (A)**

- **Pergunta:** DIRECT_REPORTS/DESCENDANTS quando o ator não possui
  collaborator/occupation?
- **Alternativas:** (A) vazio (fail-closed); (B) ORGANIZATION-like.
- **Decisão (fechada): A** — vazio.
- **Impacto:** sem alvos inventados.

### D10 — Deduplicação de alvos — **FECHADA (A)**

- **Pergunta:** como deduplicar entre positions/ramos?
- **Alternativas:** (A) dedup por `position_id` e `collaborator_id`;
  (B) sem dedup.
- **Decisão (fechada): A** — deduplicação por position e por collaborator
  (invariante 6).
- **Impacto:** conjuntos corretos em listagens e decisões.

### D11 — Tenant mismatch — **FECHADA (A)**

- **Pergunta:** comportamento quando algum nó pertence a outra org?
- **Alternativas:** (A) provider retorna falso/vazio; engine DENY; (B) ignorar.
- **Decisão (fechada): A** — DENY (invariante 14).
- **Impacto:** sem vazamento.

### D12 — Histórico vs estrutura viva (fronteira de fonte) — **FECHADA (A)**

- **Pergunta:** quem decide usar snapshot vs estrutura viva?
- **Alternativas:** (A) o contexto do request (ciclo ⇒ snapshot; vivo ⇒ data);
  (B) cada provider escolhe.
- **Decisão (fechada): A** — contexto dirige a fonte (invariante 11).
- **Impacto:** coerente.

### D13 — Responsabilidade por listAllowedTargets — **FECHADA (A)**

- **Pergunta:** quem resolve a lista de alvos para listagens?
- **Alternativas:** (A) serviço auxiliar delegando aos mesmos providers, sem
  decidir; (B) lógica própria.
- **Decisão (fechada): A** — D5 F4-03.
- **Impacto:** sem terceira fonte de decisão.

### D14 — Alguma migration é realmente necessária na F4-04? — **FECHADA (A)**

- **Pergunta:** o desenho exige alteração de schema?
- **Alternativas:** (A) não — relações derivam de F3/F4-02 e ASSIGNED de
  F3-08/09; implementação em TS/adapter; (B) sim.
- **Decisão (fechada): A** — **nenhuma migration** (invariante 16).
- **Impacto:** sem schema novo.

### D15 — SECURITY DEFINER seria necessário? — **FECHADA (A)**

- **Pergunta:** há necessidade de função privilegiada?
- **Alternativas:** (A) não; (B) sim.
- **Decisão (fechada): A** — nenhum DEFINER (invariante 15).
- **Impacto:** sem superfície privilegiada.

### D16 — Boundary F4-04 × F4-05 — **FECHADA (A)**

- **Pergunta:** onde termina a F4-04?
- **Alternativas:** (A) hierarquia + ASSIGNED derivado + fluxos mínimos;
  substituição e mapa de domínios na F4-05; (B) incluir substituição.
- **Decisão (fechada): A**.
- **Impacto:** escopo Issue #91; sem sobreposição com F4-05.

### D17 — Titular/responsável efetivo e boundary com F4-05 — **FECHADA (A ajustada)**

- **Pergunta:** DIRECT_REPORTS/DESCENDANTS no contexto vivo usam o titular ou o
  responsável efetivo com substituto operacional?
- **Alternativas:** (A) titular estrito para autorização na F4-04 (sem efeito
  do substituto); (B) responsável efetivo (herança ao substituto).
- **Decisão (fechada): A ajustada** — a F4-04 **não concede autorização ao
  substituto temporário como efeito novo**: a árvore formal é definida por
  positions + reporting lines; occupants/titulares vigentes são usados nos
  casos normais; `temporary_responsibilities` permanecem dado estrutural da F3
  (sem scope persistido, sem tratar o substituto como possuidor automático de
  capabilities/scopes do titular, sem antecipar o mapa responsibility_type ×
  capability); se um resolver F3-07 devolver `responsible_collaborator_id` com
  substituto, a F4-04 **não** converte isso automaticamente em concessão;
  qualquer herança autorizativa do substituto é **exclusivamente F4-05**
  (seção 11). Histórico de ciclo segue a F3-08/09 congelada.
- **Impacto:** invariantes 12 e 13 respeitadas; sem concessão antecipada.

### D18 — capability × tipo de target — **FECHADA (A ajustada)**

- **Pergunta:** como impedir `goal.read` + ASSIGNED(avaliação X) e confusões
  equivalentes?
- **Alternativas:** (A) contrato fechado de compatibilidade capability↔tipo de
  alvo; (B) só convenção.
- **Decisão (fechada): A ajustada** — criar um **contrato fechado** de
  compatibilidade entre capability e tipo de recurso/alvo apenas para impedir
  combinações semanticamente impossíveis (ex.: `evaluation.*` só sobre
  `evaluation`/subtarget derivado; `goal.*` não usa ASSIGNED de `evaluation`;
  `observation.*` não usa alvo `goal`). O contrato **não** concede autorização,
  não substitui capability/scope/relationProvider, não reimplementa regras de
  domínio e não cria uma segunda matriz de policy — só valida o tipo de
  recurso compatível; incompatibilidade ⇒ DENY fail-closed (seção 16).
- **Impacto:** impede confusão de resource type (invariantes 8 e 9); sem
  segunda policy.

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

## 26. Implementação e finalização (relatório)

Relatório da implementação da F4-04 (Issue #91), branch
`feat/issue-91-f4-04-hierarchy-assignments`, sobre o desenho aprovado
(D1–D18 fechadas + 18 invariantes). **Sem migration, sem `SECURITY DEFINER`,
sem policy RLS nova, sem Supabase remoto, sem grant local por cargo.**

### 26.1 Arquivos criados/alterados

- Criados:
  - `src/authorization/providers/structure.ts` — núcleo hierárquico puro
    (DIRECT_REPORTS/DESCENDANTS) sobre entrada F3-shaped (positions + reporting
    lines + occupants), com multi-position, travessia de vaga, dedup e tenant;
  - `src/authorization/providers/assigned.ts` — ASSIGNED derivado (colegiado
    F3-08 + responsabilidade avaliativa F3-09), sem hierarchy/wildcard;
  - `src/authorization/providers/structuralRelation.ts` — RelationProvider que
    compõe hierarchy + ASSIGNED atrás da porta `isTargetInScope` do engine F4-03;
  - `src/authorization/policyEngine/capabilityTarget.ts` — contrato capability×
    target (D18);
  - `src/authorization/providers/f4-04-core.test.ts` — testes com fixtures
    F3-shaped.
- Alterados:
  - `src/authorization/policyEngine/types.ts` (nova razão `TARGET_INCOMPATIBLE`;
    `RelationProvider.isTargetInScope` passa a receber `cycleId` para ASSIGNED);
  - `src/authorization/policyEngine/policyEngine.ts` (passo 5.1 do contrato
    capability×target; repassa `cycleId` à relação);
  - `src/authorization/policyEngine/errors.ts` (`TARGET_INCOMPATIBLE` →
    FORBIDDEN);
  - `src/authorization/Capability.ts` (`evaluation.read`/`evaluation.write`);
  - `src/authorization/policyEngine/legacyMap.ts` (mapeamento de documentação
    das regras de avaliação → capability+scope; **nunca** runtime);
  - `docs/F4-04-desenho-tecnico.md` (seção 26).

### 26.2 Providers implementados

DIRECT_REPORTS/DESCENDANTS (estrutura temporal por entrada F3-shaped, positions
do ator fornecidas por `resolveActorPositions` — nunca escolhidas pelo caller),
união de múltiplas positions, posição vaga sem collaborator e atravessada,
deduplicação por position/collaborator e isolamento por tenant; ASSIGNED
derivado de `collegiateMemberships` (F3-08) e `evaluationResponsibilities`
(F3-09); contrato capability×target rejeitando combinações impossíveis
(evaluation.*↔goal/observation; goal.*↔evaluation/observation; observation.*↔
goal/evaluation) sem conceder autorização.

### 26.3 Fluxos migrados

Nenhum fluxo de página/serviço (`permissaoAvaliacao`, `visibilidadeColaboradores`
etc.) foi migrado — ver §26.6. A integração foi entregue no **core + engine**
(capability×target na pipeline e `RelationProvider` estrutural pronto para a
fonte F5).

### 26.4 Dependências legadas removidas

Nenhuma nesta issue (nenhum fluxo runtime migrado). O mapa legado foi **apenas
estendido** como documentação (evaluation → capability+scope) e permanece não
consultado em runtime (D18 F4-03).

### 26.5 Decisões D1–D18 implementadas

D1–D18 preservadas. Implementadas no core: D1 (vaga atravessada), D3 (união por
positions confiáveis), D4/D5/D6 (ASSIGNED derivado de F3-08/09), D7 (TargetRef
tipado), D9 (ator sem occupation ⇒ vazio), D10 (dedup), D11/D14/D15/D17
(tenant fail-closed; sem migration; sem DEFINER; substituto sem efeito
autorizativo), D18 (contrato capability×target). D8 (migração de fluxos) está
**bloqueada** pela ausência da fonte runtime estrutural F3 (ver §26.6), conforme
Alternativa A aprovada.

### 26.6 Limitação de integração/runtime (registrada)

A migração dos fluxos hierárquicos (`permissaoAvaliacao`,
`visibilidadeColaboradores`, páginas de avaliação) **não foi realizada** porque,
no runtime atual pré-F5 (`localStorage`), **não existe a fonte estrutural F3**
(positions/reporting lines/occupations) nem roles/scopes como dado — apenas
`funcao` (cargo) e relações achatadas (`gestorDiretoMatricula`,
`avaliadoresColegiadoMatriculas`). Migrar sem cargo exigiria a fonte F3 no
runtime (F5). Isso **não altera D1–D18**; é limitação de integração/runtime, não
de contrato. O mapa legado permanece como artefato até a F5 (D18 F4-03).

### 26.7 Testes e resultados

- `src/authorization/providers/f4-04-core.test.ts` — 13 casos aplicáveis agora
  (DIRECT_REPORTS, DESCENDANTS com vaga atravessada, dedup, tenant, multi-
  position, ator sem occupation, fora da árvore, colegiado/avaliação ASSIGNED,
  snapshot por ciclo, contrato capability×target e negação no engine);
- **Executados agora** (matrix §20): 1–12, 15–16 (via fixtures F3-shaped),
  19 (tenant), 20 (sem occupation), 23 (capability×target), 24 (contrato/
  engine). **Dependentes da integração F5** (não executados por ausência de
  fonte runtime): 17/18 (membership/profile disabled nos fluxos reais),
  21 (grep de cargo nos fluxos migrados — nenhum fluxo migrado ainda),
  22 (substituto sem autorização — já garantido por não haver código de
  substituição) e os fluxos de página;
- `npm test` — **595 testes em 52 arquivos**, aprovados; `npm run build`
  (tsc + vite), `npm run lint` e `git diff --check` aprovados.

### 26.8 Riscos/limitações e deixado para depois

- F4-04 entrega o core estrutural + integração no engine; a migração dos fluxos
  hierárquicos depende da fonte F3 no runtime (**F5**);
- **F4-05**: efeito autorizativo de substituição temporária e mapa
  responsibility_type×capability (não implementado; substituto não recebe
  autorização — D17);
- **F4-06** auditoria; **F4-08** RLS final.

### 26.9 Confirmação explícita

`temporary_responsibilities` **não concedem autorização nesta issue** (D17):
nenhum scope de substituição foi persistido, nenhum mapa
responsibility_type×capability foi criado e nenhum `responsible_collaborator_id`
de substituto é convertido em concessão pelo core F4-04.

### 26.10 Correções aplicadas após revisão da PR

1. **ASSIGNED F3-09 deixou de ser wildcard:** `EvaluationTarget` agora exige
   `positionId` (+ `evaluatedCollaboratorId` + ciclo + tenant) e
   `EvaluationResponsibility` carrega `positionId` + `evaluatedCollaboratorId`;
   `isEvaluationAssigned` correlaciona **posição + avaliado + ciclo + tenant +
   responsável**. O alvo genérico é convertido pelo resolver tipado
   `EvaluationTargetResolver` (obrigatório no `StructuralRelationInput`; sem
   ele, ASSIGNED falha fechado). Teste negativo: ator responsável por A
   (p3/c_an1) consultando B (p4/c_an2) no mesmo ciclo/tenant ⇒ false/DENY —
   coberto em função, RelationProvider e Policy Engine.
2. **Contrato capability × target fechado:** `capabilityTarget.ts` passou de
   lista de proibidos para **allowlist explícita** `Record<Capability,
   readonly TargetType[]>` — combinação não prevista ⇒ incompatível ⇒ DENY
   (fail-closed). Testes de combinações válidas, inválidas e "não autorizada ⇒
   false".
