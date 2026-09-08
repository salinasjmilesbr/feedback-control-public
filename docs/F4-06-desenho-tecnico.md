# F4-06 — Contrato arquitetural: acesso excepcional auditado a conteúdo confidencial (Issue #93)

> **Status:** **CONTRATO ARQUITETURAL FECHADO** — revisão arquitetural concluída.
> **D1–D20 CLOSED / APPROVED** (§18) e **Q1–Q8 CLOSED / ANSWERED** (§19).
> Nenhuma implementação: sem código, migration, RLS, `SECURITY DEFINER`,
> alteração de frontend/Edge Functions ou PR de implementação. A **Issue #93
> permanece aberta**; a **PR #149 é somente de documentação**; **sem merge**.
> A implementação da F4-06 poderá começar a partir deste contrato.

## 1. Objetivo, princípio e boundary

### 1.1 Objetivo

Permitir **acesso administrativo excepcional** a **conteúdo confidencial** de
forma **explícita, restrita, temporária e auditável** — elevação pontual por
capability e por target, com **justificativa obrigatória**, **vigência fechada**
e **trilha de auditoria** (concessão, revogação/expiração e uso efetivo) — sem
bypass genérico do Policy Engine, sem wildcard, sem `superadmin` irrestrito e
sem conceder ao ADMIN acesso automático a conteúdo confidencial (F4-01
D17/D18, vinculantes).

### 1.2 Princípio central de segurança

Acesso excepcional é **ELEVAÇÃO EXPLÍCITA + RESTRITA + TEMPORÁRIA +
AUDITÁVEL**. Modelos equivalentes a "admin pode ver tudo", "manager acessa
qualquer confidencial", "possuir role ignora o engine", "exceptional access =
bypass" ou "exceptional access = wildcard" são **rejeitados** (§3, §6, §7, §12).

### 1.3 Domínio-piloto (Q1, fechada)

O domínio-piloto da F4-06 é **conteúdo de avaliação/feedback de terceiros**
(notas, comentários, feedback final e conteúdo equivalente produzido por
terceiros dentro da avaliação — modelo `Feedback`). **Não** entram nesta fase:
observações como domínio genérico, relatórios como domínio genérico ou qualquer
categoria global "todo conteúdo confidencial". A arquitetura é **extensível** a
outros domínios via capabilities/classificadores próprios, sem alterar o
contrato do grant.

### 1.4 Fora de escopo

Implementação/migration/RLS/`SECURITY DEFINER` nesta atividade; workflow formal
de solicitação (D1); dual control (D2/Q5); escrita excepcional (D8/D15/Q8);
auditoria geral de leitura confidencial normal A/B (D12/Q4); F4-07/Pilot Full
Access (Q7); F4-08/policies RLS finais; fluxos legais/compliance por país, SIEM
externo e produção (Issue #93); correção do drift de vocabulário de capabilities
(registrado como dívida — Q6, §17).

## 2. Estado atual (fatos verificados)

- **Engine (F4-03/04/05):** pipeline determinística de 10 passos, única porta
  de decisão na application layer; origens **A** (membership/roles/scopes,
  `matchedScope`) e **B** (temporary responsibility F4-05, `temporary:<id>`)
  resolvidas por **união deduplicada** com origem preservada no diagnóstico;
  contrato fechado capability × tipo de target (F4-04); tenant mismatch = DENY;
  fail-closed; sem cargo/job_role; caller nunca escolhe position/origem/
  responsabilidade.
- **Confidencialidade: LACUNA.** Nenhum campo/flag de confidencialidade,
  privacidade ou restrição em `Observacao`, `Feedback`, `Meta`, `Colaborador`,
  `CicloAvaliacao`, `ExpectativaCargo`, `HistoricoOrganizacional`; nenhuma
  capability de confidencialidade catalogada (nem no catálogo SQL da F4-01 —
  21 capabilities — nem no runtime `src/authorization/Capability.ts` — 33
  códigos). F4-01 D18 decidiu: sem capability genérica `confidential.*`;
  confidencialidade **separável por domínio/recurso** quando houver necessidade
  concreta. A F4-06 cria essa necessidade concreta (Q1).
- **ADMIN no runtime:** não existe papel ADMIN (`FuncaoColaborador` não tem
  ADMIN); o sufixo `.admin` existe só em nomes de capability de consulta
  (`evaluation.view.admin`, `goal.view.admin`) e em desenho/migrations futuras.
  Teste fixa: "ADMIN sem capability confidencial ⇒ DENY (CAPABILITY_MISSING)".
  Allowlists provisórias `INVITE_ADMIN_USER_IDS`/`verify_jwt=false` não são
  fonte soberana de autorização (Q2). Impersonação é DEV-only (F2-09) e não
  participa de autorização server-side.
- **Auditoria atual:** trilhas de entidade append-only no runtime (históricos
  com autor+data+motivo) **não são log de autorização** (Q3); no banco,
  `created_by` sem motivo; **`revogar_acesso_role` não persiste revogador/
  motivo**; único ponto com autor+motivo append-only = `evaluation_succession_
  events` (F3-09). F4-03 §21 define os campos que a auditoria de autorização
  deverá registrar; F4-05 D10 já preserva origem sem schema.
- **Runtime pré-F5:** fontes F3/roles/scopes não existem como dado no runtime
  (localStorage); fluxos de página permanecem legados por cargo até a F5
  (Alternativa A F4-04; regra igual na F4-05). A F4-06 segue o mesmo padrão:
  **core/provider testável**, sem bootstrap por cargo e sem fonte fake.

## 3. Quatro origens de autorização (A, B, C, D)

| Origem | O que é | Fase | Origem no diagnóstico |
| --- | --- | --- | --- |
| **A — normal** | membership + roles + scopes + relação | F4-01/02/03/04 | `matchedScope` |
| **B — temporária** | temporary responsibility por data (allowlist por tipo) | F4-05 | `temporary:<id>` |
| **C — excepcional** | grant excepcional explícito (capability+target+janela+motivo) | F4-06 | `exceptional:<grantId>` |
| **D — Pilot Full Access** | acesso total de piloto temporário/removível | F4-07 | fora da F4-06 |

Regras vinculantes de coexistência (D6/D9/D12):

1. A e B continuam resolvidas por união deduplicada; **C é terceira origem
   independente** — não amplia A, não amplia B, não é derivada delas;
2. **C só é considerada quando A/B NÃO autorizam** (§6): se A/B ALLOW, a
   operação segue normal, C não é consumida e **nenhum evento de uso
   excepcional** é gerado;
3. temporary responsibility **nunca se transforma** em acesso excepcional
   (fontes distintas; F4-05 D1/D3/D10 preservados);
4. C **não antecipa D** (F4-07): grant excepcional é específico — nunca
   organização inteira, nunca wildcard, nunca bypass (Q7);
5. A capability de conceder (D3) não concede o conteúdo (D4); o concedente não
   recebe leitura pelo ato de conceder.

## 4. Confidencialidade: o que é e como o engine sabe (D7/Q1/Q6)

Fechado:

1. **Vocabulário de autorização:** capability de confidencialidade separável
   por domínio — nesta fase, o **domínio-piloto é avaliação/feedback de
   terceiros** e a capability de leitura do conteúdo no runtime é
   **`evaluation.read`** (código existente em `src/authorization/Capability.ts`,
   referência runtime da F4-06 — Q6). Não existe capability genérica única de
   confidencialidade.
2. **Classificação soberana:** fornecida pelo **domínio/probe** (o domínio
   declara; o engine consome). O **caller NÃO informa** se o recurso é
   confidencial. **Não** há flag de confidencialidade manipulável no `TargetRef`.
3. **Fail-closed:** classificação inexistente, ambígua ou indeterminada em
   contexto em que ela seja necessária ⇒ **DENY**.

Comportamento por tipo de conteúdo:

- **Normal:** usa A/B; C não participa (D9);
- **Confidencial (piloto: avaliação/feedback de terceiros):** exige a capability
  de leitura apropriada; quando A/B não cobrem o acesso, **C pode fornecer
  elevação pontual** se existir grant válido, exato e inequívoco;
- **Histórico/congelado (F3-08/F3-09, ciclo encerrado):** fontes congeladas
  soberanas; C, se aplicável, é **somente leitura** e nunca muta/reescreve
  (D15, §11);
- **Inexistente/inacessível:** tenant não resolvido ⇒ `TARGET_INVALID` /
  NOT_FOUND público (sem revelar existência);
- **Indeterminado:** qualquer indeterminação relevante à segurança ⇒ DENY.

## 5. O grant excepcional (modelo conceitual fechado)

### 5.1 Estrutura do grant (D11/D19/D10)

1 grant = **1 beneficiário + 1 capability + 1 target específico + 1 tenant +
contexto/ciclo quando aplicável + 1 janela temporal fechada**.

| Dimensão | Obrigatória | Regra |
| --- | --- | --- |
| `id` | sim | identificação inequívoca (origem `exceptional:<id>`) |
| `organizationId` (tenant) | sim | mesmo tenant do concedente/beneficiário (FKs compostas futuras) |
| `beneficiary` | sim | **user_profile via membership** (D19) — sem exigir collaborator (ADMIN sem collaborator ok) |
| `grantedBy` | sim | user_profile do concedente (D3/D4) |
| `capability` | sim | ∈ allowlist fechada de exceção (D8); piloto: `evaluation.read` |
| `target` | sim | `TargetRef` tipado — **nunca nulo/org-wide**; piloto: tipo `evaluation` |
| `cycleId` | condicional | **obrigatório quando o tipo de recurso é por ciclo** (avaliação é por ciclo); ausente quando não (D10). Sem "qualquer/todos os ciclos", sem ciclo wildcard |
| `justification` | sim | motivo obrigatório (trim, não vazio) |
| `validFrom`/`validTo` | sim | janela fechada, `valid_to > valid_from`; **sem grant permanente** (D13) |
| `status` | sim | `active`/`revoked` (revogação por estado; sem exclusão) |
| revogação | registro | `revokedAt`, `revokedBy`, `revocationMotive` (D14) |
| `createdAt`/`version` | sim | padrão do banco |

**Não existem nesta fase:** lote de targets, grant por árvore/scope/unidade/
organização inteira/conjunto aberto (D11); dupla aprovação (D2/Q5); workflow de
solicitação (D1); escrita (D8/D15/Q8).

### 5.2 Ciclo de vida

```
concessão administrativa direta (D1) → ATIVO
                                          ├─ EXPIRADO (automático por data, sem job/cache — D13)
                                          └─ REVOGADO (manual — D14; ou efeito por membership/profile
                                                        inválido — D14)
```

- Revogação/expiração **nunca excluem** o registro; histórico preservado (D20);
- Um eventual workflow de solicitação poderá ser acrescentado futuramente
  **sem alterar o contrato fundamental do grant** (D1).

## 6. Integração ao Policy Engine (D6/D17/D18)

### 6.1 Regra de ouro

C **nunca é avaliada antes de A/B e nunca substitui a avaliação normal**. O
engine continua a avaliar A/B sempre; C só é consultada quando A/B DENY e a
operação é elegível.

### 6.2 Fluxo fechado

```
A/B tentam autorizar normalmente (passos 1–4, 5, 5.1, 6/7, 8, 9 como hoje).

Se A/B ALLOW:
 → ALLOW normal/temporário (diagnóstico: matchedScope e/ou temporaryOrigins)
 → C NÃO é consumida
 → NENHUM evento de uso excepcional

Se A/B DENY:
 → verificar elegibilidade: capability ∈ allowlist fechada de exceção (D8)
    E classificação soberana do recurso = confidencial (D7)
 → resolver automaticamente grants C (ExceptionalGrantProvider — §10.1)
 → validar: beneficiário; tenant; capability exata; target exato; cycleId
    quando aplicável; vigência (data ∈ [validFrom, validTo)); status ativo;
    membership/profile do beneficiário válidos (passos 1–3 continuam valendo)
 → 0 grants aplicáveis            → mantém a DENY original (fail-closed)
 → exatamente 1 grant válido      → ALLOW excepcional
                                  → origem no diagnóstico: exceptional:<grantId>
                                  → registrar evento de uso efetivo (D12)
 → mais de 1 grant aplicável sem identificação determinística inequívoca
                                  → DENY fail-closed (D16) — nunca escolher
                                    arbitrariamente, nunca o caller escolhe
```

C **não** dispensa os gates globais: identidade/profile/membership (1–3),
tenant do alvo (4), contrato capability × tipo de target (5.1) e estado do
domínio (9). Passo 8 (data explícita) também se aplica.

### 6.3 Diagnóstico e razões internas (D17)

- ALLOW por C ⇒ `diagnostics.exceptionalGrant = { id, origin: "exceptional:<id>" }`
  (sem `matchedScope`);
- Razão interna específica de falha da origem C **pode existir** (log/
  diagnóstico interno), mas **nunca revela publicamente**: existência do grant,
  expiração, revogação nem existência do conteúdo confidencial. Externamente o
  contrato de erro seguro da F4-03 é preservado (FORBIDDEN; NOT_FOUND para
  cross-tenant).

### 6.4 listAllowedTargets (D18 — ajustada)

**Exceptional access NÃO participa de `listAllowedTargets` nesta fase.** A
origem C autoriza apenas um **target já conhecido e explicitamente
referenciado**; C **não** é usada para descobrir/listar conteúdo confidencial e
`listAllowedTargets` **não** revela inventário de targets confidenciais.
`authorize()` continua sendo a única decisão real.

## 7. Allowlist de exceção (D8/Q1/Q6 — fechada)

`EXCEPTIONAL_CAPABILITIES` — allowlist **FECHADA**, somente leitura:

- Piloto: **`evaluation.read`** (código runtime existente em
  `src/authorization/Capability.ts`);
- **Não** permitidos: escrita, edição, exclusão, administração, wildcard,
  prefix matching ou qualquer capability não listada explicitamente.

Regras fechadas:

- C concederá a capability **exata** do grant; sem prefixo genérico; sem
  segunda matriz genérica de autorização (D9);
- O alvo piloto é `TargetRef` tipo `evaluation` com `cycleId` obrigatório
  (recurso por ciclo — D10); demais tipos de target (collaborator/position)
  ficam **fora do piloto**, fechados nesta fase;
- Novos domínios confidenciais futuros entram por **capabilities/classificadores
  próprios** com decisão explícita — nunca por alargamento da allowlist sem
  revisão;
- **Contrato capability × target (F4-04) permanece soberano** para qualquer
  capability concedida via C.

## 8. Quem pode conceder (D1/D2/D3/D4/D5/D14)

- **Capability administrativa de concessão (D3):** contrato para capability
  específica, resolvida **pelo Policy Engine**, atribuída explicitamente por
  membership — nunca cargo/job_role, nunca regra externa ao engine, e o
  `access_role` ADMIN **não** autoriza conceder automaticamente.
  - **Nome técnico definitivo adotado no runtime F4-06: `exceptional_access.grant`**
    (novo código runtime; domínio novo `exceptional_access`, sem colisão com os
    33 códigos atuais de `Capability.ts`; finalidade: conceder e revogar grants
    excepcionais no tenant).
  - **Dívida de alinhamento (registrada, não corrigida na F4-06 — Q6/§17):** o
    domínio `exceptional_access.*` e a capability não existem no catálogo SQL
    (21 capabilities da F4-01); o alinhamento SQL×runtime é dívida futura. Se
    novos códigos runtime forem adicionados (este e/ou futuros), documentar
    nome, finalidade, necessidade e ausência no catálogo SQL.
- **Concedente não precisa possuir o conteúdo (D4):** conceder é ato
  administrativo; a capability de concessão não concede a capability de leitura;
  o concedente pode conceder acesso a target que ele próprio não pode ler.
- **Auto-concessão PROIBIDA (D5):** `grantedBy != beneficiary`, sem exceção e
  sem possibilidade de auto-concessão via segunda aprovação nesta fase (D2).
- **Sem dual control (D2/Q5):** uma única pessoa devidamente autorizada pode
  conceder. Controles obrigatórios: capability de conceder; auto-concessão
  proibida; target específico; capability específica; justificativa obrigatória;
  vigência fechada; auditoria da concessão, da revogação e do uso efetivo.
- **Sem workflow formal de solicitação (D1):** concessão administrativa direta,
  registrando concedente, beneficiário, tenant, capability, target,
  justificativa, início, fim e timestamp.
- **Revogação (D14):** permitida ao **concedente** ou a ator com a capability
  apropriada (`exceptional_access.grant`); com **motivo obrigatório**, registra
  `revokedAt`/`revokedBy`; **efeito imediato**; nunca exclusão física.
- **Membership/profile inválidos (D14):** o grant deixa imediatamente de
  autorizar (sem job); o estado de revogação/invalidação é registrado/derivado
  corretamente conforme o contrato de auditoria.

## 9. Auditoria (D12/Q3/Q4 + D20)

Trilha **append-only** (estado atual do grant **+** eventos separados, D20),
por **user_profile**, com tenant, timestamp e `grant_id`. **Baseline de audit
fechado (Q3):** evento de concessão; evento de revogação/invalidação/expiração
quando aplicável; evento de cada **utilização efetiva** da origem C. Os
históricos atuais das entidades **não** são reinterpretados como log de
autorização.

- **(A) Concessão:** concedente, beneficiário, quando, motivo (obrigatório),
  tenant, capability, target, `validFrom`, `validTo`;
- **(B) Ciclo de vida:** revogação (revogador, data, motivo), expiração/
  invalidação (derivada por data ou por membership/profile inválido) — eventos
  `granted | revoked | expired/invalidation | used` (D20);
- **(C) Uso efetivo:** evento **somente** quando C transforma uma decisão que
  seria DENY por A/B em ALLOW — qual grant (`exceptional:<id>`), quando, qual
  beneficiário, qual capability/ação, qual target, contexto data/ciclo,
  resultado.

**Posse × consumo (D12):** "grant existente" (registro ativo) ≠ "grant
consumido" (uso efetivo que autorizou uma operação). Evento de uso excepcional
**só** ocorre quando C efetivamente autoriza (A/B DENY → C ALLOW). Se A/B já
autorizam: C não é consumida e **não** há evento de uso excepcional. **Auditoria
geral de leitura confidencial normal A/B NÃO é implementada nesta F4-06** (Q4) —
fica separada da trilha específica de exceptional access.

## 10. Modelagem conceitual (tipos/contratos futuros — sem código/schema)

### 10.1 Contratos TS puros (entrada F3/F4-shaped para o provider)

```
ExceptionalAccessGrant {
  id: string; organizationId: string;
  beneficiaryUserProfileId: string;          // D19 (membership; sem exigir collaborator)
  grantedByUserProfileId: string;            // D3/D4/D5 (≠ beneficiary)
  capability: Capability;                    // ∈ EXCEPTIONAL_CAPABILITIES (D8)
  target: TargetRef;                         // tipo+id exatos (piloto: evaluation)
  cycleId?: string;                          // obrigatório p/ recurso por ciclo (D10)
  justification: string;                     // motivo obrigatório
  validFrom: Date; validTo: Date;            // janela fechada (D13)
  status: "active" | "revoked";
  revokedAt?: Date; revokedBy?: string; revocationMotive?: string;  // D14
  createdAt: Date; version: number;
}

EXCEPTIONAL_CAPABILITIES: Capability[]       // fechada, somente leitura (D8) — piloto: [evaluation.read]

ExceptionalGrantProvider {                    // origem C no engine (D6)
  isCapabilityExceptionalEligible(capability): boolean;
  isTargetConfidential(target, cycleId?, organizationId): boolean | undefined; // D7 (undefined ⇒ DENY)
  resolveExceptionalGrants(beneficiaryId, organizationId, capability,
                           target, date, cycleId?): ExceptionalGrant[];          // D16 (ambiguidade ⇒ DENY)
}
```

### 10.2 Persistência futura (D20 — descrita conceitualmente, SEM migration)

- **(A) Estado atual do grant:** linha de estado (`active`/`revoked`) com FKs
  compostas de tenant, sem exclusão física;
- **(B) Eventos append-only separados:** cobrindo no mínimo `granted`,
  `revoked`, `expired/invalidation` (quando aplicável) e `used`; histórico nunca
  é apagado; **duplicidade ambígua é impedida** (unicidade por
  (beneficiário, capability, target, janela) quando aplicável — D16).

### 10.3 Constraints conceituais (anti-wildcard/anti-bypass)

`capability` ∈ allowlist fechada; `target` NOT NULL e tipado (sem org-wide);
`cycleId` obrigatório quando o tipo é por ciclo; beneficiário ≠ concedente;
`justification` NOT NULL (trim não vazio); `valid_to > valid_from`; sem grant
permanente; revogação/expiração nunca apagam linha; tenant consistente por FKs
compostas; sem dois grants ativos equivalentes conflitantes; eventos exigem
`user_profile` ativo no mesmo tenant.

## 11. Recursos históricos/congelados (D15 — fechada)

Exceptional access é **SOMENTE LEITURA** nesta fase e **nunca**:

- altera snapshot (F3-08);
- altera autoria histórica;
- altera responsabilidade histórica;
- cria sucessão (F3-09);
- edita conteúdo congelado;
- reescreve F3-08/F3-09.

Fontes congeladas permanecem soberanas; C, quando aplicável, apenas **lê** o que
a fonte congelada expõe. Qualquer futura **escrita excepcional** exige nova
decisão arquitetural explícita.

## 12. Fronteira com a F4-07 / Pilot Full Access (Q7 — fechada)

F4-07 (Pilot Full Access) é **futura e fora** desta F4-06. Nenhum requisito de
full access, acesso irrestrito organization-wide, superuser, bypass global ou
acesso irrestrito de piloto pertence à F4-06 — tudo isso pertence
**exclusivamente à F4-07**. A F4-06 **não antecipa** F4-07 em nenhum ponto.

## 13. F4-08 / RLS — requisitos para a fase futura (documentar, sem policy)

A F4-08 deverá respeitar: RLS como última barreira server-side (F4-03 §19);
predicados por tabela **restritos** derivados dos mesmos conceitos (membership,
scopes, grants excepcionais) — sem predicado "tudo" para `authenticated`;
deny-by-default nas tabelas de grant/eventos com policies mínimas para quem tem
a capability de conceder/auditar; resolução server-side consumindo **os mesmos
contratos** (probe/providers), com revalidação atômica na mesma RPC/transação
(F4-03 D9 — requisito F5/F4-08). **Nenhuma policy/RPC é escrita nesta
atividade.**

## 14. Runtime pré-F5 (Q2 — regras para a implementação futura)

As fontes necessárias (roles/scopes resolvidos, classificação de
confidencialidade, membership resolvida no cliente, grants excepcionais) **não
existem no runtime atual**. A implementação futura deve entregar **core/provider
testável** (grant provider puro + allowlist fechada + eventos em memória para
teste), **sem** bootstrap por cargo, **sem** allowlist fake como fonte soberana
(Q2) e **sem** localStorage como fonte definitiva de exceção. Migração funcional
(UI administrativa) fica para a fonte F3/roles no runtime (F5) — mesmo
condicionamento das F4-04/F4-05. Auditoria de uso alimentada pelo contrato de
saída do engine (F4-03 §21), sem refazer o engine.

## 15. Matriz de testes (para a implementação futura — ajustada às decisões fechadas)

Cada caso valida contrato fechado, sem cargo, sem wildcard, somente leitura e
sem solicitação/dual control:

1. grant válido → ALLOW excepcional (origem `exceptional:<id>`);
2. grant expirado → DENY (sem uso);
3. grant futuro → DENY;
4. grant revogado → DENY (efeito imediato);
5. capability diferente da concedida → DENY;
6. target diferente → DENY;
7. target type diferente → DENY (piloto: somente `evaluation`);
8. cross-tenant (grant/alvo de outra org) → DENY;
9. beneficiário diferente → DENY;
10. caller tenta selecionar grant (não há campo; provider resolve) → impossível/inalterado;
11. caller tenta selecionar origem → impossível/inalterado;
12. justificativa ausente → concessão rejeitada;
13. concedente sem capability de conceder → DENY;
14. auto-concessão (`grantedBy = beneficiary`) → proibida;
15. conteúdo não confidencial (classificação normal) → C não consultada;
16. conteúdo confidencial do piloto → C consultada somente se A/B DENY;
17. recurso histórico/congelado → leitura somente; F3-08/09 intactos;
18. recurso inexistente → TARGET_INVALID/NOT_FOUND (sem revelar existência);
19. classificação de confidencialidade indeterminada → DENY (fail-closed);
20. normal ALLOW + grant existente → ALLOW normal, C não consumida, sem evento de uso;
21. normal DENY + grant válido → ALLOW excepcional com evento de uso;
22. coexistência com F4-05 (B e C simultâneas) → origens independentes, sem ampliação cruzada;
23. múltiplos grants aplicáveis ao mesmo pedido → DENY (fail-closed, D16);
24. múltiplos grants, apenas um corresponde ao pedido → ALLOW pelo correspondente;
25. tentativa de wildcard (target nulo/org-wide) → rejeitada na concessão;
26. capability fora da allowlist de exceção → não concedível;
27. capability × target incompatível (F4-04) → TARGET_INCOMPATIBLE;
28. dados incompletos (sem tenant/target/capability/justificativa) → rejeitado/DENY;
29. auditoria da concessão → evento com concedente/beneficiário/motivo/target/janela;
30. auditoria da revogação → evento com revogador/motivo/data;
31. auditoria da expiração/invalidação → derivada por data/membership inválida;
32. auditoria do uso efetivo → evento por operação consumida, com grant id;
33. decisão normal ALLOW sem consumo do grant (posse ≠ consumo);
34. grant existente mas fora do alcance (capability/target/tenant/ciclo) → DENY;
35. revogação com efeito imediato (sem cache);
36. grant vencendo entre duas operações → segunda operação DENY;
37. isolamento entre tenants (conceder/consumir);
38. reutilizar grant para outro recurso → DENY;
39. reutilizar grant para outra capability → DENY;
40. fail-closed quando não dá para determinar se o grant se aplica → DENY;
41. **C não participa de `listAllowedTargets`** → listagem não revela targets confidenciais (D18);
42. `cycleId` ausente em grant de recurso por ciclo → rejeitado/DENY (D10);
43. ADMIN sem grant explícito continua DENY em conteúdo confidencial (Issue #93);
44. revogação não exclui o registro (append-only);
45. concedente sem leitura do conteúdo pode conceder (D4), mas não lê via concessão;
46. membership/profile do beneficiário inválido ⇒ grant não autoriza (sem job).

## 16. Riscos, dependências e itens fora de escopo

- **Riscos e mitigações (contrato):** deriva para bypass/wildcard (allowlist
  fechada D8 + target/ciclo obrigatórios + janela D13); consumo acidental
  (C só quando A/B DENY — D6); auditoria incompleta (3 categorias + posse×uso —
  D12/Q3); escalada via concedente (capability de concessão + auto-concessão
  proibida — D3/D5); ambiguidade de múltiplos grants (DENY — D16); vazamento de
  existência (razões internas nunca públicas — D17); exposição de inventário
  confidencial via listagem (C fora de `listAllowedTargets` — D18).
- **Dependências:** F4-01 (capabilities/roles/ADMIN D17/D18), F4-02
  (scopes/tenant), F4-03 (engine/pipeline/§21/D5/D6/D8/D9), F4-04 (contrato
  capability×target), F4-05 (origens/união, fronteira vivo×congelado),
  F3-08/F3-09 (soberania de histórico), F4-07/F4-08 (fronteiras), F5 (runtime).
- **Fora de escopo:** implementação, UI final, F4-07, RLS (F4-08), fluxos
  legais/SIEM/produção, correção do drift de vocabulário (dívida registrada).

## 17. Conflitos/dívidas com contratos F3/F4 existentes

1. **Drift de numeração:** F4-01 chamou a fase de acesso excepcional de
   "F4-09"; F4-02+ chamam de F4-06. Sem efeito de contrato; registro para
   normalização futura.
2. **Dívida de vocabulário (Q6):** catálogo SQL (21 capabilities) × runtime
   `src/authorization/Capability.ts` (33) divergem; a F4-06 usa o **runtime**
   como referência e **não corrige** o drift silenciosamente. Novos códigos
   runtime (`exceptional_access.grant`) e a capability piloto (`evaluation.
   read`, já existente) são registrados com ausência/estado no catálogo SQL.
3. **Lacuna de auditoria externa:** `revogar_acesso_role` (F4-01) não persiste
   revogador/motivo; a F4-06 não corrige migrations (fora de escopo), mas o
   contrato exige revogador+motivo nos eventos próprios dos grants excepcionais.
4. **F4-01 D17/D18 (fechadas) vinculantes:** ADMIN por organização, sem
   conteúdo confidencial automático, confidencialidade separável por domínio —
   respeitadas sem reabertura.
5. **F4-03 D6/D8/D9/§21 e F4-05 D10/D16:** razões internas não públicas; sem
   SECURITY DEFINER novo; auditoria alimentada pelo contrato de saída; origem
   preservada sem schema — preservados.
6. **F4-08:** exposição do grant em policies futuras somente quando a RLS
   existir (não agora).

## 18. Decisões arquiteturais — D1–D20 (CLOSED / APPROVED)

> Nenhuma alternativa permanece em aberto; recomendações antigas conflitantes
> foram removidas. Texto de cada decisão = regra fechada.

- **D1 — Fluxo de concessão — CLOSED:** concessão administrativa direta nesta
  fase; **sem** workflow formal de solicitação. A concessão registra
  obrigatoriamente: concedente, beneficiário, tenant, capability, target,
  justificativa, início, fim e timestamp. Workflow de solicitação futuro pode
  ser acrescentado sem alterar o contrato fundamental do grant.
- **D2 — Dual control — CLOSED:** **não obrigatório** nesta fase; uma única
  pessoa autorizada pode conceder. Controles obrigatórios: capability
  específica de conceder; auto-concessão proibida; target específico;
  capability específica; justificativa obrigatória; vigência fechada;
  auditoria da concessão, da revogação e do uso efetivo. Dual control futuro só
  por requisito de compliance.
- **D3 — Quem pode conceder — CLOSED:** contrato de capability administrativa
  específica, resolvida pelo Policy Engine, atribuída explicitamente; **sem**
  cargo/job_role, **sem** regra externa, e o `access_role` ADMIN **não**
  autoriza conceder automaticamente. Nome adotado no runtime F4-06:
  **`exceptional_access.grant`** (dívida de alinhamento SQL registrada, §17.2).
- **D4 — Concedente precisa possuir o conteúdo? — CLOSED:** **não**. Conceder é
  ato administrativo distinto de possuir/ler; a capability de concessão não
  concede a capability de leitura; o concedente pode conceder a target que não
  pode ler.
- **D5 — Auto-concessão — CLOSED:** **proibida** (`grantedBy != beneficiary`),
  sem exceção e sem possibilidade via segunda aprovação nesta fase.
- **D6 — Ordem no Policy Engine — CLOSED:** origem C somente quando A/B **não**
  autorizam. A/B ALLOW → operação normal, C não consumida, sem evento de uso.
  A/B DENY → verificar elegibilidade → resolver C → grant exato e válido ⇒
  ALLOW excepcional + uso efetivo. C nunca antes de A/B e nunca substitui a
  avaliação normal.
- **D7 — Como identificar conteúdo confidencial — CLOSED:** (1) capability de
  confidencialidade separável por domínio como vocabulário; (2) classificação
  soberana fornecida pelo domínio/probe. Caller não informa confidencialidade;
  sem flag manipulável no `TargetRef`. Classificação inexistente/ambígua/
  indeterminada onde necessária ⇒ DENY.
- **D8 — Allowlist excepcional — CLOSED:** **fechada**; somente leitura; sem
  escrita, edição, exclusão, administração, wildcard, prefix matching ou
  capability não listada. Domínio-piloto: avaliação/feedback confidencial de
  terceiros → **`evaluation.read`** (runtime `Capability.ts`).
- **D9 — Conteúdo normal × confidencial — CLOSED:** conteúdo normal usa A/B; C
  não participa de recursos normais; conteúdo confidencial exige capability
  apropriada; quando A/B não cobrem, C pode elevar pontualmente se houver grant
  válido e exato. Sem segunda matriz genérica.
- **D10 — Contexto de ciclo — CLOSED:** `cycleId` **obrigatório** quando o tipo
  de recurso é associado a ciclo; **ausente** quando não é. Não existe
  "qualquer ciclo", "todos os ciclos" nem ciclo wildcard.
- **D11 — Granularidade — CLOSED:** 1 grant = 1 beneficiário + 1 capability + 1
  target específico + 1 tenant + contexto/ciclo quando aplicável + 1 janela
  temporal. Sem lote; sem grant por árvore/scope/unidade/organização inteira/
  conjunto aberto.
- **D12 — Posse × consumo e auditoria — CLOSED:** distinguir grant existente ×
  grant consumido; evento de uso só quando C transforma DENY (A/B) em ALLOW; se
  A/B autorizam, C não é consumida e não há evento de uso. Auditoria geral de
  leitura confidencial normal **não** é implementada nesta F4-06 (fica
  separada).
- **D13 — Duração — CLOSED:** `valid_to` obrigatório; **sem grant permanente**;
  `valid_to > valid_from`; expiração automática por comparação de data; sem
  cache que prolongue; sem job para invalidar.
- **D14 — Revogação — CLOSED:** manual, pelo concedente ou por ator com
  capability apropriada; motivo obrigatório; `revoked_at`; `revoked_by`; efeito
  imediato; nunca exclusão física. Membership/profile inválido ⇒ grant deixa de
  autorizar imediatamente (sem job); estado de revogação/invalidação registrado/
  derivado conforme auditoria.
- **D15 — Histórico/confidencial — CLOSED:** somente leitura nesta fase; nunca
  altera snapshot, autoria, responsabilidade histórica, sucessão, conteúdo
  congelado nem reescreve F3-08/F3-09. Escrita excepcional futura exige nova
  decisão explícita.
- **D16 — Múltiplos grants — CLOSED:** impedir grants equivalentes ativos
  conflitantes/sobrepostos sempre que possível; se a resolução produzir
  múltiplos grants aplicáveis ao mesmo pedido sem identificação determinística
  inequívoca ⇒ **DENY fail-closed**; nunca escolher arbitrariamente; nunca o
  caller escolhe.
- **D17 — Diagnóstico — CLOSED:** razão interna específica de falha da origem C
  é permitida, mas nunca revela publicamente existência do grant, expiração,
  revogação nem existência do conteúdo confidencial — contrato de erro seguro
  F4-03 preservado. Quando C autoriza, origem inequívoca
  `exceptional:<grantId>` para diagnóstico/auditoria.
- **D18 — listAllowedTargets — CLOSED (recomendação anterior ALTERADA):**
  exceptional access **não participa** de `listAllowedTargets`; C autoriza
  somente target já conhecido e explicitamente referenciado; C não descobre/
  lista conteúdo confidencial e `listAllowedTargets` não revela inventário
  confidencial. `authorize()` é a única decisão real.
- **D19 — Beneficiário — CLOSED:** identidade de usuário via user_profile/
  membership; sem exigir collaborator (compatível com ADMIN sem collaborator);
  relação com collaborator, quando o domínio exigir, é resolução contextual e
  não altera a identidade soberana do beneficiário.
- **D20 — Persistência futura — CLOSED:** modelo = (A) estado atual do grant +
  (B) eventos append-only separados; eventos cobrindo no mínimo `granted`,
  `revoked`, `expired/invalidation` (quando aplicável) e `used`; nunca apagar
  histórico; impedir duplicidade ambígua. **Nenhuma migration na F4-06.**

## 19. Questões — Q1–Q8 (CLOSED / ANSWERED)

- **Q1 — O que é conteúdo confidencial nesta primeira implementação? — CLOSED:**
  domínio-piloto = conteúdo de avaliação/feedback de **terceiros** (notas,
  comentários, feedback final e conteúdo equivalente produzido por terceiros na
  avaliação). Não entram: observações como domínio genérico, relatórios como
  domínio genérico, nem categoria global "todo conteúdo confidencial".
  Arquitetura extensível a outros domínios via capabilities/classificadores
  próprios.
- **Q2 — Quem opera a concessão hoje? — CLOSED:** o contrato não se vincula à
  allowlist DEV/legada atual; ela pode existir transitoriamente onde já existe,
  mas **não** é fonte soberana. Fonte definitiva = capability específica de
  concessão resolvida pelo Policy Engine. Pré-F5: implementar core/provider
  testável, sem bootstrap por cargo ou allowlist fake.
- **Q3 — Baseline de audit — CLOSED:** para a F4-06 = evento de concessão;
  evento de revogação/invalidação/expiração quando aplicável; evento de cada
  utilização efetiva da origem C. Não reinterpretar históricos atuais das
  entidades como log de autorização.
- **Q4 — Leitura confidencial normal A/B gera evento? — CLOSED:** **não** nesta
  fase; somente o consumo efetivo de C gera evento de uso excepcional.
  Auditoria geral de leitura sensível normal fica para o futuro, separada.
- **Q5 — Dual control? — CLOSED:** **não** nesta fase; concessão individual
  autorizada + controles do D2.
- **Q6 — Fonte soberana do vocabulário — CLOSED:** runtime
  `src/authorization/Capability.ts` é a referência da F4-06; drift entre
  catálogo SQL e runtime é **dívida registrada**, não corrigida na F4-06. Novos
  códigos runtime documentados com nome, finalidade, necessidade e ausência no
  catálogo SQL.
- **Q7 — F4-06 precisa de "ver tudo"? — CLOSED:** **não**. Full access,
  organization-wide irrestrito, superuser, bypass global ou acesso irrestrito de
  piloto pertencem **exclusivamente à F4-07**.
- **Q8 — Escrita excepcional? — CLOSED:** **não** nesta fase; F4-06 é somente
  leitura.

## 20. Contrato arquitetural fechado

### 20.1 Fluxo vinculante (resumo)

```
A/B tentam autorizar normalmente.
 A/B ALLOW  → ALLOW normal/temporário; C não é consumida; sem uso excepcional.
 A/B DENY   → operação elegível (capability ∈ allowlist fechada) e
              classificação soberana = confidencial?
              → resolver automaticamente grants C
                (beneficiário, tenant, capability, target, cycleId quando
                 aplicável, vigência, estado/revogação, membership/profile)
              → 0 grants            → mantém DENY original
              → 1 grant inequívoco  → ALLOW excepcional (exceptional:<grantId>)
                                      + evento de uso efetivo
              → >1 grant ambíguo    → DENY fail-closed
```

### 20.2 Invariantes finais

1. Policy Engine continua sendo a única porta de decisão (C é origem interna);
2. capability = ação; scope/relação = alcance; tenant mismatch = DENY;
   fail-closed; o caller nunca escolhe origem/grant/position;
3. sem cargo/job_role; sem wildcard/prefixo; sem grant permanente;
4. C não amplia A/B; temporary responsibility não vira exceção; F3-08/F3-09
   soberanos; sem reescrita de histórico;
5. exceção = somente leitura no piloto de avaliação/feedback de terceiros;
6. auto-concessão proibida; concedente ≠ beneficiário; conceder não dá leitura;
7. concessão/revogação/uso sempre rastreáveis e atribuíveis (eventos
   append-only); origem `exceptional:<grantId>` preservada;
8. ADMIN não recebe acesso excepcional automático; F4-07 (Pilot Full Access) e
   F4-08 (RLS) permanecem fora desta fase;
9. runtime `Capability.ts` é a referência de capabilities da implementação;
   drift SQL×runtime documentado como dívida;
10. nenhuma migration/RLS/`SECURITY DEFINER` nesta atividade; sem merge;
    Issue #93 aberta; PR #149 somente de documentação.

### 20.3 Próximo passo

Com D1–D20 e Q1–Q8 fechados, este documento é o **contrato arquitetural** para
a implementação da F4-06 (core/provider testável + allowlist `evaluation.read`
+ origem C no engine + eventos de auditoria em memória), a ser executada em
fase posterior com nova branch/PR de implementação — sempre sem migration/RLS/
DEFINER e sem antecipar F4-07/F4-08.

## 21. Implementação e finalização (Issue #93)

> Implementado o **core testável** da F4-06 (origem C), integrado ao Policy
> Engine. Sem migration, sem RLS, sem `SECURITY DEFINER`, sem conexão ao
> Supabase remoto e sem migração de fluxos de página (runtime pré-F5, mesmo
> condicionamento das F4-04/F4-05). D1–D20 e Q1–Q8 permanecem fechados.

### 21.1 Arquivos implementados

- **Alterado** `src/authorization/Capability.ts` — nova capability runtime
  `exceptional_access.grant` (administrativa de concessão; **não** pertence à
  allowlist de exceção e **não** é adicionada a bundle ADMIN — dívida de
  alinhamento SQL×runtime registrada em Q6/§17.2);
- **Alterado** `src/authorization/policyEngine/capabilityTarget.ts` — entrada
  fechada `"exceptional_access.grant": ["evaluation"]` (concessão somente sobre
  targets de avaliação, no piloto);
- **Alterado** `src/authorization/policyEngine/types.ts` — contratos
  `ExceptionalGrant`, `ExceptionalUsageRecord`, `ExceptionalProvider`,
  `PolicyEngineProviders.exceptional?` e diagnóstico `exceptionalGrant`
  (`{ id, origin }`);
- **Alterado** `src/authorization/policyEngine/policyEngine.ts` — origem C como
  fallback pós A/B DENY; gates globais (tenant, capability×target, data,
  DOMAIN_STATE) preservados; `listAllowedTargets` **remove** a origem C (D18);
- **Criado** `src/authorization/providers/exceptional.ts` — allowlist fechada
  `EXCEPTIONAL_CAPABILITIES` (`["evaluation.read"]`) e `createExceptionalProvider`
  (resolução exata por beneficiário/tenant/capability/target/cycleId/data/
  status; fail-closed);
- **Criado** `src/authorization/exceptionalAccess.ts` — serviço de concessão e
  revogação (auto-concessão proibida, justificativa, janela fechada, ciclo
  obrigatório p/ avaliação, `grantedBy ≠ beneficiary`, autorização do concedente
  via `exceptional_access.grant`) + eventos de auditoria `granted`/`revoked`/
  `used` (event sink);
- **Criado** `src/authorization/providers/f4-06-core.test.ts` — 49 testes da
  matriz (§15) + extras exigidos.

### 21.2 Integração ao Policy Engine

`autorizarOrigemExcepcional` é consultada somente quando A/B negam por
capability (`CAPABILITY_MISSING`) ou por scope/relação (`SCOPE_INSUFFICIENT`),
e apenas se `providers.exceptional` existe. Ordem interna: (1) capability ∈
allowlist fechada; (2) contrato capability×target (TARGET_INCOMPATIBLE); (3)
classificação soberana `=== true` (false/undefined ⇒ DENY); (4) data explícita;
(5) DOMAIN_STATE; (6) resolução de grants (0 ⇒ mantém a negação; 1 ⇒ ALLOW com
`exceptional:<id>` + `recordUsage`; >1 ⇒ DENY). Quando A/B ALLOW, C não é
consultada nem consumida. `listAllowedTargets` roda sem a origem C.

### 21.3 Classificação, auditoria e limitações

- **Classificação:** soberana via `ExceptionalProvider.isTargetConfidential`
  (domínio/probe); o caller não informa confidencialidade; indeterminada ⇒ DENY.
- **D10 (fail-closed no provider):** a correlação de `cycleId` é feita no
  `ExceptionalProvider` (fronteira de segurança), não presumindo que todo grant
  de entrada foi criado pelo serviço atual: para o alvo `evaluation` (recurso
  por ciclo), `cycleId` é obrigatório **no grant e no pedido**, não vazio e
  exatamente igual — `undefined` nunca é interpretado como "qualquer ciclo";
  grant ou pedido sem ciclo, ou ciclos diferentes ⇒ NÃO aplicável (DENY).
- **Auditoria:** `granted`/`revoked` (serviço) e `used` (engine, via
  `recordUsage`); expiração é **derivada** por data (sem job/evento armazenado);
  posse ≠ consumo; nenhum evento de uso quando A/B já autorizam.
- **Pré-F5:** core/provider testável com entrada F3/F4-shaped e event sink
  in-memory; sem bootstrap por cargo, sem allowlist fake, sem localStorage como
  fonte soberana; migração funcional (UI administrativa) fica para F5.
- **Adiados:** F4-07 (Pilot Full Access), F4-08 (RLS/policies), auditoria geral
  de leitura confidencial normal A/B, alinhamento SQL×runtime de capabilities.

### 21.4 Validação

- `npm test` → **685 testes / 54 arquivos aprovados** (+55 da F4-06);
- `npm run build` → aprovado (`tsc -b` + `vite build`);
- `npm run lint` → aprovado;
- `git diff --check` → aprovado.

### 21.5 Confirmações

- Nenhuma migration, RLS ou `SECURITY DEFINER`;
- Nenhum uso de cargo/job_role no novo caminho;
- `exceptional_access.grant` não concede leitura e `evaluation.read` não concede
  concessão; ADMIN não recebe acesso excepcional automático;
- Issue #93 será fechada pelo merge desta PR (não realizado aqui).
