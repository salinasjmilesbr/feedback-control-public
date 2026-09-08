# F4-05 — Desenho técnico: autorização temporária por substituição (Issue #92)

> **Status:** revisão arquitetural concluída — recomendações **D1–D16
> APROVADAS e FECHADAS** (com três esclarecimentos obrigatórios incorporados,
> §13) e passam a constituir o **contrato arquitetural da F4-05** (§14).
> Nenhuma implementação: sem código, migration, RLS, `SECURITY DEFINER`,
> alteração de frontend/Edge Functions ou PR de implementação. Somente este
> documento, em branch exclusiva de docs (PR #147 mantida).

## 1. Objetivo e boundary

### 1.1 Interpretação da Issue #92

Conceder ao **substituto** — durante a vigência de uma
`temporary_responsibility` (F3-06) — **apenas o escopo/capabilities
necessários** sobre o **alvo e o período aplicáveis**, com **revogação
automática no término** (e reflexo imediato em retorno antecipado/encerramento
administrativo), **sem** criar escopo permanente, **sem** hierarquia paralela,
**sem** revogar o titular e **sem** duplicar a F3.

### 1.2 Boundary exato da F4-05

- **Entra:** integração de `temporary_responsibilities` ao Policy Engine F4-03/
  F4-04 (provedor temporário puro sobre entrada F3-shaped), contrato
  `responsibility_type × capability`, tratamento de vigência/retorno, interação
  com DIRECT_REPORTS/DESCENDANTS/ASSIGNED e com o contrato capability×target,
  fronteira vivo × congelado (F3-08/F3-09) e registros de origem para auditoria
  futura;
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
  `EvaluationTargetResolver` (ASSIGNED específico), `DomainStateProbe`
  (consulta de estado do domínio na decisão).
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
  `responsibility_type`) com **alcance restrito à position substituída** —
  **nunca** as capabilities/scopes da membership do titular (sem herança
  genérica);
- a substitution **NÃO revoga nem suspende** a autorização do titular: titular
  e substituto podem permanecer autorizados simultaneamente, e exclusividade de
  atuação é questão de **estado/regra do domínio**, nunca regra genérica do
  Policy Engine nem suspensão implícita do titular;
- as **autorizações próprias do substituto** (derivadas das occupations/
  positions normais dele) **continuam válidas e independentes** durante a
  vigência: a substitution não as amplia nem as altera, e para o grant
  temporário a raiz estrutural é **exclusivamente a position substituída**;
- a decisão pode considerar a **união deduplicada dos grants válidos** (próprios
  + temporários), preservando a **origem de cada grant** no diagnóstico;
- a substitution **não é fonte para o histórico**: no contexto avaliativo ela só
  produz autorização temporária enquanto o ciclo/responsabilidade ainda **não
  estiver soberanamente congelado** por F3-08/F3-09 (que permanecem soberanos).

```
position (raiz estrutural, occupations)
   ├─ titular (occupation)         → autorização própria NÃO é revogada pela substitution
   └─ substituto (temporary_responsibility, por data, tipo X)
        └─ grant TEMPORÁRIO: capabilities elegíveis por X (mapa fechado D3)
        └─ alcance: posições sob a position / avaliação viva da position (D9)
        └─ expira em valid_to (resolução por data)
        └─ raiz exclusiva = position substituída (não usa occupations do substituto)
   └─ substituto também pode ter autorizações PRÓPRIAS (occupations normais)
        └─ independentes do grant temporário; união deduplicada preserva origem
```

## 4. Invariantes (contrato)

1. capability define a ação; scope define o alcance; a raiz continua sendo a
   position (positions + reporting lines + occupations);
2. `temporary_responsibilities` **não cria** hierarchy e **não duplica** a F3
   em nenhuma outra fonte (nenhuma tabela genérica de grants);
3. cargo/job_role/nome de função nunca participa da autorização runtime;
4. Policy Engine F4-03 é a única porta de decisão;
5. o caller nunca escolhe position, origem (própria × temporária) nem qual
   responsabilidade concede acesso;
6. **nenhuma herança implícita das capabilities do titular** — o substituto
   recebe só as elegíveis pelo tipo, no período e alvo (D1/D3);
7. a substitution **NÃO revoga nem suspende a autorização do titular**; titular
   e substituto podem estar autorizados simultaneamente (D2);
8. o Policy Engine **NÃO arbitra genericamente "titular × substituto"**;
   exclusividade de atuação é tratada explicitamente pelo estado/regra do
   domínio (`DomainStateProbe` ou mecanismo equivalente), nunca por regra
   genérica do engine nem por suspensão implícita (D6);
9. para o grant originado pela `temporary_responsibility`, a raiz estrutural é
   **exclusivamente a position substituída**; as **autorizações próprias** do
   substituto (occupations/positions normais) permanecem válidas e
   independentes — a substitution **nunca amplia nem altera** as positions
   próprias dele; a decisão considera a **união deduplicada dos grants válidos
   preservando a origem de cada um** (D4/D5/D12);
10. tenant mismatch = DENY; vigência fora de `[valid_from, valid_to)` = DENY
    (substituição futura/expirada); fail-closed;
11. **fronteira avaliativa (D8/D9):** `temporary_responsibility` dos tipos
    `evaluative`/`operational_evaluative` só produz autorização temporária no
    **contexto vivo** em que a responsabilidade avaliativa ainda não esteja
    soberanamente congelada por F3-08/F3-09; quando o recurso/ciclo for
    governado por snapshot/responsabilidade congelada, essas fontes **são
    soberanas**; `temporary_responsibilities` **não reescrevem, não substituem
    nem concorrem** com histórico/snapshot; **ausência de informação suficiente
    para distinguir contexto vivo de congelado = DENY**;
12. estrutura viva e histórico de ciclo permanecem separados; F3-08/F3-09 e
    snapshots **permanecem soberanos** (substituição atual não os reescreve);
13. ASSIGNED (F4-04) não vira wildcard; contrato capability×target (F4-04)
    permanece fechado (D13);
14. nenhuma migration/RLS/DEFINER nova (D16);
15. sem cache que atrase a revogação (retorno antecipado reflete imediatamente
    — a decisão é sempre resolvida por data na F3) (D15).

## 5. Integração com Policy Engine

Fluxo proposto (engine inalterado em forma; providers resolvem origens):

```
authorize(request)
 → 1–4 identidade/profile/membership/tenant (fail-closed)
 → grants próprios da membership do substituto (capabilities/roles efetivos)
     ⊕ grants TEMPORÁRIOS elegíveis (TemporaryResponsibilityProvider,
       origem "temporary:<id>")  → UNIÃO DEDUPLICADA preservando a origem
 → por grant: scope resolvido sobre a raiz adequada
     · grant temporário  → DIRECT_REPORTS/DESCENDANTS/ASSIGNED da POSITION
                           SUBSTITUÍDA na data (raiz exclusiva)
     · grant próprio     → positions/occupations normais do substituto
 → target ∈ alcance do grant correspondente
 → DomainStateProbe:
     · exclusividade de recurso/processo = estado do domínio (não do engine)
     · contexto avaliativo: se o ciclo/responsabilidade estiver congelado por
       F3-08/F3-09, o grant temporário avaliativo NÃO autoriza; fontes congeladas
       são soberanas
     · sem informação suficiente p/ distinguir vivo × congelado → DENY
 → ALLOW (diagnostics com matchedScope + origem de cada grant)
```

O substituto **não precisa** possuir a capability na membership para receber o
grant temporário: a elegibilidade é concedida pelo tipo da responsibility
**somente** quando a capability está no mapa fechado do tipo (D3) e o target
está no alcance da position substituída. Tudo fora disso = DENY. A existência
de autorização própria não é condição nem é afetada pelo grant temporário.

## 6. Providers/adapters necessários

- `TemporaryResponsibilityProvider` (puro, entrada F3-shaped):
  `getActiveForPosition(actorId, positionId, orgId, date)`, que devolve as
  responsibilities vigentes do ator na data (sem sobreposição — F3 garante);
- `ResponsibilityCapabilityMap` — mapa declarado e **fechado** (D3)
  `responsibility_type × capabilities elegíveis`, num único módulo;
- composição no `RelationProvider`: para o **grant temporário**, a raiz =
  **position substituída** (nunca as occupations do substituto); para grants
  próprios, raiz = positions normais do substituto (independentes);
- `DomainStateProbe`: consulta de estado do domínio para (a) exclusividade de
  recurso/processo (D6) e (b) status vivo × congelado do ciclo/responsabilidade
  avaliativa (D9); ausência de resposta ⇒ DENY;
- diagnóstico com **origem por grant** (`membership:…`, `temporary:<id>`) (D10).

## 7. Contrato responsibility_type × capability (D3 — fechada)

Mapa **declarado, fechado e único**, sem cargo (detalhe capability-por-
capability resolvido na implementação dentro da allowlist aprovada):

| Tipo | Domínios de capability elegíveis |
| --- | --- |
| `operational` | operação/gestão da position (ex.: estrutural/colaboradores/observações de equipe) |
| `evaluative` | avaliação viva da position/avaliado (capabilities `evaluation.*`; domínio avaliativo) |
| `operational_evaluative` | união dos dois conjuntos |

Regra fechada: **allowlist explícita** de capabilities por tipo; capability
fora da lista do tipo ⇒ o tipo não a concede (DENY); nunca "tudo"; nenhuma
capability entra por prefixo de domínio sem estar listada.

## 8. Interação com hierarchy (D4/D5/D12 — fechadas)

- A **árvore não muda**: reporting lines e occupations históricas intactas;
- **grant temporário** durante a substituição: o substituto age "pela position
  substituída" → DIRECT_REPORTS/DESCENDANTS são os subordinados/descendentes
  **da position substituída**, que é a **raiz exclusiva** desse grant;
- as **occupations/positions próprias do substituto continuam valendo** e
  gerando autorizações próprias independentes — a substitution **não as
  amplia, não as altera e não as suspende**;
- substituto **não ganha hierarchy própria por causa da substitution**: as
  positions próprias dele não são raiz do grant temporário, nem o grant
  temporário amplia o alcance das autorizações próprias.

## 9. Interação com ASSIGNED e fronteira vivo × congelado (D8/D9 — fechadas)

- **Contexto vivo (não congelado):** uma responsibility `evaluative`/
  `operational_evaluative` sobre a position pode autorizar o substituto como
  avaliador vivo daquela position/avaliado (origem temporária; ASSIGNED não
  vira wildcard);
- **Governado por F3-08/F3-09 (congelado):** snapshot e responsabilidades
  avaliativas congeladas são **soberanos**; a substitution **não autoriza,
  não reescreve, não substitui nem concorre** com essas fontes (quem avaliou
  no ciclo congelado permanece o que a F3-08/F3-09 registra);
- **Sem distinção possível** entre contexto vivo e congelado ⇒ **DENY**
  (fail-closed);
- a sucessão de avaliador registrada em F3-09 continua sendo o mecanismo
  histórico; a substitution atual é uma autorização temporária do contexto
  vivo, nunca uma mutação do histórico.

## 10. Temporalidade (D15 — fechada)

- Sempre resolvido **por data**: `date ∈ [valid_from, valid_to)` ⇒ vigente;
  futura/expirada ⇒ DENY; retorno antecipado/encerramento administrativo =
  fechar `valid_to` na F3 ⇒ data corrente deixa de casar ⇒ **sem cache**, sem
  ação manual de revogação no engine (reflexo imediato).

## 11. Tenant e fail-closed

- Responsibility, position, substitute e alvo da mesma organização (FKs F3);
  mismatch ⇒ provider vazio ⇒ DENY;
- ausência de data, responsabilidade inexistente, tipo desconhecido,
  capability fora do mapa do tipo ou **indistinção vivo × congelado** ⇒ DENY.

## 12. Fluxos candidatos à migração (D11 — fechada)

- No runtime atual **não há** ponto legado de substituição no frontend; a
  integração F4-05 é entregue no **core + engine** (provedor puro + mapa +
  origem temporária), e os fluxos de página migram **quando a fonte F3 estiver
  no runtime (F5)** — mesmo condicionamento da F4-04 (documentado).

## 13. Esclarecimentos obrigatórios da revisão arquitetural (incorporados)

Regras vinculantes adicionadas/aprimoradas sobre o desenho original, e
refletidas nas invariantes §4, no modelo §3, na integração §5–§9 e na matriz
de testes §15.

### 13.1 Titular × substituto (fecha D2/D6)

- A `temporary_responsibility` **NÃO revoga automaticamente** a autorização do
  titular; titular e substituto podem permanecer autorizados simultaneamente;
- quando um recurso/processo exigir **exclusividade de atuação**, essa
  exclusividade deve ser tratada **explicitamente pelo estado/regra do
  domínio** (`DomainStateProbe` ou mecanismo de domínio equivalente) — e não
  como regra genérica do Policy Engine nem como suspensão implícita do titular;
- o Policy Engine **não arbitra genericamente "titular versus substituto"**.

### 13.2 temporary responsibility avaliativa × F3-08/F3-09 (fecha D8/D9)

- `temporary_responsibility` dos tipos `evaluative`/`operational_evaluative`
  pode produzir autorização temporária avaliativa **somente no contexto vivo**
  em que a responsabilidade avaliativa ainda não esteja **soberanamente
  congelada** por F3-08/F3-09;
- quando o recurso/ciclo estiver governado pelo snapshot/responsabilidade
  congelada F3-08/F3-09, **essas fontes são soberanas**;
- `temporary_responsibilities` **não reescrevem, não substituem nem concorrem**
  com o histórico/snapshot;
- **ausência de informação suficiente para distinguir contexto vivo de
  congelado = DENY** (fail-closed).

### 13.3 Autorização própria do substituto × autorização temporária (fecha D4/D5/D12)

Correção de qualquer formulação que possa sugerir que as occupations próprias
do substituto deixam de valer durante uma substituição. A regra é:

- para resolver o **grant originado pela `temporary_responsibility`**, a raiz
  estrutural é **exclusivamente a position substituída**;
- o substituto pode **simultaneamente possuir autorizações próprias**,
  derivadas de suas occupations/positions normais;
- essas autorizações são **independentes**;
- a decisão pode considerar a **união deduplicada dos grants válidos**,
  **preservando a origem de cada um**;
- uma `temporary_responsibility` **nunca amplia nem altera** as positions
  próprias do substituto;
- o **caller nunca escolhe** qual origem/position concede o acesso.

## 14. Contrato arquitetural — decisões D1–D16 (FECHADAS)

As recomendações D1–D16 foram **aprovadas** na revisão arquitetural e, com os
esclarecimentos obrigatórios do §13, **passam a constituir o contrato
arquitetural da F4-05**. Regras vinculantes (não são recomendações):

1. **D1 — Sem herança genérica:** a substituição concede um conjunto **novo e
   restrito** (capabilities elegíveis do tipo + alcance da position
   substituída); o substituto **não herda** capabilities nem scopes do titular.
2. **D2 — Titular não é revogado:** a substitution é overlay adicional; titular
   e substituto podem estar autorizados simultaneamente (§13.1).
3. **D3 — Contrato fechado por tipo:** allowlist explícita capability-por-
   capability por `responsibility_type`, num único módulo, sem cargo e sem
   "tudo" (§7).
4. **D4 — Raiz do grant temporário:** position substituída, resolvida por
   data; o caller nunca informa a position.
5. **D5 — Alcance do grant temporário:** DIRECT_REPORTS/DESCENDANTS da
   position substituída; sem misturar occupations do substituto nesse grant.
6. **D6 — Sem arbitragem titular × substituto:** conflitos resolvidos pela
   união de autorizações; exclusividade somente via estado/regra do domínio
   (§13.1).
7. **D7 — Múltiplas substituições:** união deduplicada por position; F3 já
   impede sobreposição na mesma position; positions distintas ⇒ união de
   grants temporários com origem preservada.
8. **D8 — Histórico intocado:** nenhum efeito em histórico/snapshot; F3-08/F3-
   09 e snapshots soberanos; substitution atua só no contexto vivo.
9. **D9 — Fronteira vivo × congelado:** substitution avaliativa autoriza apenas
   no contexto vivo não congelado; congelado ⇒ F3-08/F3-09 soberanos; sem
   distinção possível ⇒ DENY (§13.2).
10. **D10 — Origem sem schema:** origem preservada no diagnóstico
    (`temporary:<id>` + reason); auditoria completa fica na F4-06.
11. **D11 — Fonte F3-shaped no core:** provider puro com entrada F3-shaped;
    migração de fluxos de página adiada à fonte F3 no runtime (F5).
12. **D12 — Autorizações próprias preservadas:** positions próprias do
    substituto continuam válidas e independentes; substitution não as amplia
    nem altera; união deduplicada preserva a origem; caller nunca escolhe a
    origem (§13.3).
13. **D13 — Contrato capability×target único:** reuso do contrato fechado da
    F4-04; nenhuma matriz paralela; combinações novas só com atualização da
    allowlist.
14. **D14 — listAllowedTargets auxiliar:** consome o mesmo provedor temporário
    (somente listagem); `authorize()` continua a única proteção efetiva.
15. **D15 — Reflexo imediato:** decisão sempre por data lendo a F3; nenhum
    estado copiado/cache; retorno antecipado/encerramento reflete na hora.
16. **D16 — Sem schema novo:** nenhuma migration/RLS/`SECURITY DEFINER`;
    origem no diagnóstico; se surgir necessidade real de schema, nova decisão
    antes de qualquer mudança.

## 15. Matriz de testes (projetada conforme o contrato)

**Vigência e temporalidade:**
- substituição vigente concede somente as capabilities previstas no período;
- responsabilidade expirada ⇒ DENY; futura ⇒ DENY;
- retorno antecipado (fechamento do `valid_to`) reflete imediatamente, sem
  cache/job (D15).

**Grants temporários (D1/D3/D4/D5):**
- `responsibility_type` incompatível com a capability ⇒ DENY;
- substituto não herda capability fora do mapa do tipo;
- capability fora da allowlist do tipo não é concedida (nunca "tudo");
- grant temporário com raiz exclusiva = position substituída (occupations do
  substituto não entram na raiz);
- DIRECT_REPORTS/DESCENDANTS do grant temporário = subordinados/descendentes
  da position substituída;
- capability incompatível com o target (contrato F4-04) ⇒ DENY (D13);
- múltiplas substituições em positions distintas ⇒ união deduplicada com
  origem preservada (D7).

**Titular × substituto (D2/D6):**
- titular permanece autorizado durante a vigência (não revogado/suspenso);
- titular e substituto autorizados simultaneamente sobre o mesmo alvo;
- recurso com exigência de exclusividade NÃO é decidido por regra genérica do
  engine: o engine delega ao estado do domínio (DomainStateProbe);
- sem nenhuma regra genérica "titular vs substituto" no engine.

**Autorizações próprias do substituto (D12):**
- substituto mantém grants próprios (occupations normais) durante a vigência;
- grants próprios e temporários são independentes e combináveis em união
  deduplicada;
- a substitution não amplia nem altera as positions próprias do substituto;
- diagnóstico preserva a origem de cada grant (próprio × `temporary:<id>`);
- caller nunca escolhe origem/position concedente.

**Fronteira avaliativa vivo × congelado (D8/D9):**
- substitution `evaluative`/`operational_evaluative` autoriza somente em
  contexto vivo não congelado;
- ciclo governado por snapshot/responsabilidade congelada F3-08/F3-09 ⇒
  fontes congeladas soberanas (substitution não autoriza, não reescreve, não
  concorre);
- sem informação suficiente p/ distinguir vivo × congelado ⇒ DENY.

**Tenant e fail-closed:**
- cross-tenant ⇒ DENY; profile/membership desabilitado ⇒ DENY; ator sem
  vínculo ⇒ DENY; responsabilidade inexistente/tipo desconhecido ⇒ DENY;
- períodos sobrepostos na mesma position (bloqueio F3); múltiplas positions do
  substituto;
- `listAllowedTargets` não substitui `authorize()` (D14).

## 16. Riscos, dependências e itens fora de escopo

- **Riscos e mitigações (contrato):** herança genérica (D1/D3); hierarquia
  paralela (proibida — invariante 2); janela de revogação (D15); duplicação da
  F3 (proibida); cargo em runtime (proibido); arbitragem titular × substituto
  no engine (proibida — D6, §13.1); indistinção vivo × congelado (DENY — D9);
  fonte inventada no runtime (D11).
- **Dependências:** F4-03 (engine), F4-04 (providers estruturais + ASSIGNED +
  contrato capability×target + DomainStateProbe), F3-06/07/09 (fontes), F5
  (fonte F3 no runtime para migração de fluxos).
- **Fora de escopo:** UI final, acesso excepcional (F4-06), RLS (F4-08),
  auditoria completa (F4-06), persistência dos domínios (F5).

## 17. Plano de implementação posterior (indicativo)

1. `TemporaryResponsibilityProvider` puro + `ResponsibilityCapabilityMap`
   (allowlist fechada D3) num módulo;
2. origem por grant no diagnóstico (`temporary:<id>`) — sem schema (D10/D16);
3. composição no `RelationProvider` (raiz = position substituída por data, D4/
   D5/D12) e consulta vivo × congelado via `DomainStateProbe` (D8/D9);
4. exclusividade como regra de domínio (D6), fora do engine;
5. testes da matriz §15; docs + PR de implementação.

Nada disso é implementado nesta entrega. **D1–D16 estão fechadas e constituem o
contrato arquitetural da F4-05** (§14), sujeito apenas a nova deliberação se um
dos pontos proibidos (migration/RLS/DEFINER, duplicação da F3, herança
genérica, suspensão implícita do titular, reescrita de histórico) se tornar
necessário — caso em que a decisão deve ser apresentada antes de qualquer
mudança.
