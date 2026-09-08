# F4-05 — Desenho técnico: autorização temporária por substituição (Issue #92)

> **Status:** desenho técnico da F4-05 **aguardando revisão** — decisões
> **D1–D16 abertas** (recomendação indicada, sem fechamento). Nenhuma
> implementação: sem código, migration, RLS, `SECURITY DEFINER`, alteração de
> frontend/Edge Functions ou PR de implementação. Somente este documento, em
> branch exclusiva de docs. Conteúdo 100% conceitual e sintético.

## 1. Objetivo e boundary

### 1.1 Interpretação da Issue #92

Conceder ao **substituto** — durante a vigência de uma
`temporary_responsibility` (F3-06) — **apenas o escopo/capabilities
necessários** sobre o **alvo e o período aplicáveis**, com **revogação
automática no término** (e reflexo imediato em retorno antecipado/encerramento
administrativo), **sem** criar escopo permanente, **sem** hierarquia paralela e
**sem** duplicar a F3.

### 1.2 Boundary exato da F4-05

- **Entra:** integração de `temporary_responsibilities` ao Policy Engine F4-03/
  F4-04 (provedor temporário puro sobre entrada F3-shaped), contrato
  `responsibility_type × capability`, tratamento de vigência/retorno, interação
  com DIRECT_REPORTS/DESCENDANTS/ASSIGNED e com o contrato capability×target,
  e registros de origem para auditoria futura;
- **Fora:** UI final de substituição, acesso excepcional (F4-06), RLS (F4-08),
  persistência dos domínios no runtime (F5) — a migração de fluxos de página
  permanece condicionada à fonte F3 no runtime (mesma limitação da F4-04).

## 2. Estado atual

- **F3-06 `temporary_responsibilities`**: (id, organization_id,
  organizational_position_id, substitute_collaborator_id, responsibility_type
  `operational`/`evaluative`/`operational_evaluative`, reason, período
  **fechado** `[valid_from, valid_to)`, exclusion por posição (sem
  sobreposição), triggers de validade dentro da posição e anti-auto-
  substituição).
- **F3-07 resolvers** retornam `responsible_collaborator_id` (substituto
  operacional > titular) — usados **com cuidado** (F4-04 D17: não viram
  concessão automática).
- **F4-03/04**: Policy Engine (pipeline 1–10, fail-closed), contrato
  capability×target fechado (allowlist), providers estruturais
  (`structure.ts`, `assigned.ts`, `structuralRelation.ts`), `TargetRef` tipado,
  `EvaluationTargetResolver` (ASSIGNED específico).
- **Legado no runtime atual**: não há representação local de substituição
  (apenas no banco F3) — logo **nenhum ponto legado** de substituição/delegação
  no frontend; a migração de fluxos depende da fonte F3 no runtime (F5).

## 3. Modelo conceitual

- A **position é a raiz estrutural** e continua definida por positions +
  reporting lines + occupations. `temporary_responsibilities` **NÃO cria
  hierarquia**: ela sobrepõe, por data, **quem age pela position** em certas
  capacidades;
- **Titular formal** = occupant da position (occupation vigente);
  **responsável temporário** = substitute da responsibility vigente na data;
- a substitution concede ao substituto, **somente durante `[valid_from,
  valid_to)`**, um **conjunto de capabilities "elegíveis"** (pelo
  `responsibility_type`) com **alcance restrito à position** (subordinados/
  descendentes/unidade da position) — **nunca** as capabilities/scopes da
  membership do titular (sem herança genérica).

```
position (raiz estrutural, occupations)
   └─ titular (occupation)         → acesso próprio (sem herança de permissões)
   └─ substituto (temporary_responsibility, por data, tipo X)
        └─ capabilities elegíveis por X (mapa responsibility_type × capability)
        └─ alcance: posições sob a position / avaliação da position (ASSIGNED vivo)
        └─ expira em valid_to (resolução por data)
```

## 4. Invariantes

1. capability define a ação; scope define o alcance; a raiz continua sendo a
   position (positions + reporting lines + occupations);
2. `temporary_responsibilities` **não cria** hierarchy e **não duplica** a F3
   em nenhuma outra fonte (nenhuma tabela genérica de grants);
3. cargo/job_role/nome de função nunca participa da autorização runtime;
4. Policy Engine F4-03 é a única porta de decisão;
5. o caller nunca escolhe position nem qual responsabilidade concede acesso;
6. **nenhuma herança implícita de todas as capabilities do titular** — o
   substituto recebe só as elegíveis pelo tipo, no período e alvo;
7. tenant mismatch = DENY; vigência fora de `[valid_from, valid_to)` = DENY
   (substituição futura/expirada); fail-closed;
8. estrutura viva e histórico de ciclo permanecem separados; F3-08/F3-09 e
   snapshots **permanecem soberanos** (substituição atual não os reescreve);
9. ASSIGNED (F4-04) não vira wildcard; contrato capability×target (F4-04)
   permanece fechado;
10. nenhuma migration/RLS/DEFINER nova (salvo decisão explícita);
11. sem cache que atrase a revogação (retorno antecipado reflete imediatamente
    — a decisão é sempre resolvida por data na F3).

## 5. Integração com Policy Engine

Fluxo proposto (engine inalterado em forma):

```
authorize(request)  [request.capability e target do substituto]
 → 1–4 identidade/profile/membership/tenant
 → capability efetiva da membership do substituto  (se possuir, para o caso base)
 → OU capability TEMPORÁRIA elegível (via TemporaryResponsibilityProvider,
     marcada como origem "temporary:<id>")
 → scope (DIRECT_REPORTS/DESCENDANTS/ASSIGNED) resolvido sobre a POSITION
     substituída na data
 → target ∈ alcance
 → domain state (probe)
 → ALLOW (diagnostics com matchedScope + origem temporária)
```

O substituto **não precisa** possuir a capability na membership: a
elegibilidade é concedida pelo tipo da responsibility **somente** quando a
capability está no mapa do tipo e o target está no alcance da position. Tudo
fora disso = DENY.

## 6. Providers/adapters necessários

- `TemporaryResponsibilityProvider` (puro, entrada F3-shaped):
  `getActiveForPosition(actorId, positionId, orgId, date)`, que devolve as
  responsibilities vigentes do ator na data (sem sobreposição — F3 garante);
- `ResponsibilityCapabilityMap` — tabela declarada (D3) `tipo × capabilities
  elegíveis`, num único módulo;
- composição no `RelationProvider`: para DIRECT_REPORTS/DESCENDANTS, a raiz
  viva do substituto = a **position substituída** (não as occupations do
  substituto); para ASSIGNED avaliativo vivo, alvo da position substituída.

## 7. responsibility_type × capability (D3)

Mapa **declarado e fechado** por tipo (a definir em detalhe na decisão D3),
sem cargo:

| Tipo | Domínios de capability elegíveis (candidatos) |
| --- | --- |
| `operational` | operação/gestão da position (ex.: estrutural/colaboradores/observações de equipe) |
| `evaluative` | avaliação da position/avaliado (capabilities `evaluation.*`; domínio avaliativo) |
| `operational_evaluative` | união dos dois conjuntos |

Exato (capability por capability) fica **aberto em D3** — a recomendação é
listar explicitamente cada capability elegível (allowlist, nunca "tudo").

## 8. Interação com hierarchy

- A **árvore não muda**: reporting lines e occupations históricas intactas;
- DIRECT_REPORTS/DESCENDANTS **durante a substituição**: o substituto age
  "pela position" → os alvos são os subordinados/descendentes **da position**
  (não do substituto); a posição continua sendo a mesma raiz estrutural (D4/D5);
- substituto **não ganha hierarchy própria**: nada que venha das occupations
  do substituto é usado como raiz durante a substituição.

## 9. Interação com ASSIGNED

- No **contexto vivo**, uma responsibility `evaluative`/
  `operational_evaluative` sobre a position pode autorizar o substituto a atuar
  como avaliador daquela position/avaliado (origem temporária; ASSIGNED não
  vira wildcard);
- no **histórico de ciclo**, a F3-09 (responsabilidades congeladas +
  sucessão) e os snapshots F3-08 continuam soberanos — substituição atual não
  reescreve quem avaliou naquele ciclo (D8).

## 10. Temporalidade

- Sempre resolvido **por data**: `date ∈ [valid_from, valid_to)` ⇒ vigente;
  futura/expirada ⇒ DENY; retorno antecipado/encerramento administrativo =
  fechar `valid_to` na F3 ⇒ data corrente deixa de casar ⇒ **sem cache**, sem
  ação manual de revogação no engine.

## 11. Tenant e fail-closed

- Responsibility, position, substitute e alvo da mesma organização (FKs F3);
  mismatch ⇒ provider vazio ⇒ DENY;
- ausência de data, responsabilidade inexistente, tipo desconhecido ou
  capability fora do mapa ⇒ DENY.

## 12. Fluxos candidatos à migração

- No runtime atual **não há** ponto legado de substituição no frontend; a
  integração F4-05 é entregue no **core + engine** (provedor puro + mapa +
  origem temporária), e os fluxos de página migram **quando a fonte F3 estiver
  no runtime (F5)** — mesmo condicionamento da F4-04 (documentado).

## 13. Decisões abertas (D1–D16)

Cada decisão: problema, alternativas, impactos e recomendação **aberta**.

### D1 — O substituto herda capability, scope, ambos ou nenhum?

- **Problema:** o que exatamente a substituição concede?
- **Alternativas:** (A) nenhum — concede apenas um conjunto **novo e
  restrito** (capabilities elegíveis + alcance da position); (B) herda todas
  as capabilities do titular; (C) herda scopes do titular.
- **Impactos:** (A) menor privilégio e auditável; (B) herança genérica
  (proibida pelo contrato); (C) depende de haver scopes persistidos.
- **Recomendação (aberta):** (A).

### D2 — O titular mantém acesso durante a substituição?

- **Problema:** conflito titular × substituto em acesso à mesma position.
- **Alternativas:** (A) titular mantém (substituição é overlay adicional);
  (B) titular suspenso no período (posição "exclusiva" do substituto).
- **Impactos:** (A) simples; recursos de exclusividade (1 avaliador/
  aprovação) podem precisar de regra de domínio; (B) mais fiel à operação mas
  exige desativar o titular por data.
- **Recomendação (aberta):** (A) com regra de domínio de exclusividade onde
  houver (D6).

### D3 — Contrato responsibility_type × capability (formato e granularidade)

- **Problema:** definir o mapa elegível por tipo sem cargo e sem "tudo".
- **Alternativas:** (A) allowlist explícita capability-por-capability por tipo,
  num módulo único; (B) regras por prefixo de domínio; (C) lista ampla.
- **Impactos:** (A) fechado e verificável; (B) mais solto; (C) herança
  genérica.
- **Recomendação (aberta):** (A).

### D4 — Como o substituto entra na decisão (position como raiz viva)

- **Problema:** qual "position do ator" o engine usa durante a vigência.
- **Alternativas:** (A) raiz = position substituída (resolvida por data) — o
  caller não informa; (B) position informada.
- **Impactos:** (A) seguro e alinhado à F4-04 D3; (B) escolha pelo caller
  (proibida).
- **Recomendação (aberta):** (A).

### D5 — DIRECT_REPORTS/DESCENDANTS durante a substituição

- **Problema:** o que o substituto alcança.
- **Alternativas:** (A) subordinados/descendentes da position substituída;
  (B) da position do próprio substituto (occupation própria); (C) ambos.
- **Impactos:** (A) espelha a operação; (B) mistura fontes; (C) amplia.
- **Recomendação (aberta):** (A), sem misturar occupations do substituto.

### D6 — Conflitos titular × substituto e exclusividade

- **Problema:** quando os dois agem sobre o mesmo recurso.
- **Alternativas:** (A) união (ambos permitidos) com origem no diagnóstico;
  (B) o substituto prevalece durante a vigência em recursos exclusivos
  (regra de domínio explícita).
- **Impactos:** (A) simples; (B) coerente com "quem está respondendo pela
  posição".
- **Recomendação (aberta):** (A) + (B) apenas com regra de domínio
  documentada.

### D7 — Múltiplas substituições e sobreposição

- **Problema:** várias responsibilities do mesmo substituto ou em posições
  diferentes.
- **Alternativas:** (A) união por position (F3 já impede sobreposição na mesma
  position por exclusion); (B) permitir e arbitrar por prioridade.
- **Impactos:** (A) sem ambiguidade na mesma position; múltiplas positions ⇒
  união deduplicada (padrão F4-04).
- **Recomendação (aberta):** (A).

### D8 — Substituição × histórico/snapshot

- **Problema:** efeito em avaliações/colegiado de ciclos passados.
- **Alternativas:** (A) nenhum — F3-08/09 e snapshots soberanos; substituição
  afeta apenas contexto vivo; (B) reescrever histórico.
- **Impactos:** (A) preserva auditoria; (B) reescrita (proibida).
- **Recomendação (aberta):** (A).

### D9 — Interação com ASSIGNED avaliativo (vivo)

- **Problema:** avaliador da position no contexto vivo durante a substituição.
- **Alternativas:** (A) responsibility `evaluative` autoriza o substituto como
  avaliador vivo da position (origem temporária); histórico segue F3-09;
  (B) ASSIGNED avaliativo só por F3-09 congelada.
- **Impactos:** (A) cobre operação corrente; (B) substituto não avalia no
  corrente.
- **Recomendação (aberta):** (A) restrita ao vivo e ao tipo.

### D10 — Origem/auditoria do acesso temporário

- **Problema:** rastrear que o acesso veio de uma substitution.
- **Alternativas:** (A) campo `origin` no diagnóstico da decisão
  (`temporary:<id>`) + reason; (B) tabela de auditoria nova.
- **Impactos:** (A) sem schema (F4-06 audita depois); (B) migration (fora).
- **Recomendação (aberta):** (A).

### D11 — Fonte no runtime atual (pré-F5)

- **Problema:** não existe `temporary_responsibilities` no runtime local.
- **Alternativas:** (A) provider puro com entrada F3-shaped (testado) e
  migração de fluxos adiada à F5; (B) grant local derivado.
- **Impactos:** (A) coerente com F4-04; (B) fonte inventada (proibida).
- **Recomendação (aberta):** (A).

### D12 — Múltiplas positions do substituto

- **Problema:** interação de occupations próprias com a position substituída.
- **Alternativas:** (A) manter separadas (raiz = só a position substituída);
  (B) unir.
- **Impactos:** (A) não amplia; (B) ampliaria o alcance.
- **Recomendação (aberta):** (A).

### D13 — Contrato capability × target (F4-04) sob substituição

- **Problema:** capabilities temporárias precisam respeitar o contrato fechado.
- **Alternativas:** (A) reutilizar o contrato existente (sem novas combinações
  sem atualizar a allowlist); (B) contrato paralelo.
- **Impactos:** (A) sem segunda matriz; (B) duplicaria.
- **Recomendação (aberta):** (A).

### D14 — ListAllowedTargets e authorize sob substituição

- **Problema:** listagem de alvos disponíveis ao substituto.
- **Alternativas:** (A) listAllowedTargets consome o mesmo provedor temporário
  (só listagem) e authorize continua a única proteção; (B) listagem própria.
- **Impactos:** (A) alinhado a D5 F4-03/F4-04.
- **Recomendação (aberta):** (A).

### D15 — Retorno antecipado/encerramento (imediato)

- **Problema:** reflexo imediato sem cache.
- **Alternativas:** (A) decisão sempre por data lendo a F3 (nenhum estado
  copiado); (B) job de revogação.
- **Impactos:** (A) imediato e sem duplicação; (B) janela + estado.
- **Recomendação (aberta):** (A).

### D16 — Migration/RLS/DEFINER

- **Problema:** alguma alteração de banco seria necessária?
- **Alternativas:** (A) nenhuma (tudo derivado da F3; origem no diagnóstico);
  (B) migration p/ auditoria de origem.
- **Impactos:** (A) sem schema; (B) antecipação (F4-06).
- **Recomendação (aberta):** (A) — se surgir necessidade real, apresentar
  decisão antes.

## 14. Matriz de testes (a projetar)

- substituição vigente concede somente capabilities previstas;
- expirada ⇒ DENY; futura ⇒ DENY;
- responsibility_type incompatível com capability ⇒ DENY;
- substituto não herda capability não prevista;
- substituto não ganha hierarchy própria;
- posição formal continua definindo a árvore;
- titular mantém/não mantém acesso conforme D2;
- múltiplas substituições; períodos sobrepostos (bloqueio F3); cross-tenant;
- profile/membership disabled; ator sem vínculo; múltiplas positions;
- DIRECT_REPORTS/DESCENDANTS durante a substituição; ASSIGNED vivo;
- ciclo histórico não reescrito; snapshot F3-08/09 inalterado;
- capability incompatível com target = DENY;
- listAllowedTargets não substitui authorize().

## 15. Riscos, dependências e itens fora de escopo

- **Riscos:** herança genérica (mitigada por D1/D3); hierarquia paralela
  (proibida); janela de revogação (mitigada por D15); duplicação da F3
  (proibida); cargo na runtime (proibido).
- **Dependências:** F4-03 (engine), F4-04 (providers estruturais + ASSIGNED +
  contrato capability×target), F3-06/07/09 (fontes), F5 (fonte F3 no runtime
  para migração de fluxos).
- **Fora de escopo:** UI final, acesso excepcional (F4-06), RLS (F4-08),
  auditoria completa, persistência dos domínios (F5).

## 16. Plano de implementação posterior (indicativo)

1. `TemporaryResponsibilityProvider` puro + mapa `responsibility_type ×
   capability` (allowlist) num módulo;
2. origem temporária no diagnóstico (sem schema);
3. composição no `RelationProvider` (raiz = position substituída, por data);
4. testes da matriz §14; docs + PR.

Nada disso é implementado nesta entrega; fica como contrato aberto para
revisão das decisões D1–D16.
