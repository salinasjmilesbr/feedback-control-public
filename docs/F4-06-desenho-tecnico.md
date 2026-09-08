# F4-06 — Desenho técnico: acesso excepcional auditado a conteúdo confidencial (Issue #93)

> **Status:** desenho técnico da F4-06 **aguardando revisão** — decisões
> **D1–D20 ABERTAS** (recomendação indicada, sem fechamento) e seção
> **"Questões para validação"** (§19). Nenhuma implementação: sem código,
> migration, RLS, `SECURITY DEFINER`, alteração de frontend/Edge Functions ou PR
> de implementação. Somente este documento, em branch exclusiva de docs.
> A implementação só começa depois que D1–Dn forem revisadas e fechadas e o
> documento for aprovado como contrato técnico.

## 1. Objetivo e boundary

### 1.1 Interpretação da Issue #93

Permitir **acesso administrativo excepcional** a **conteúdo confidencial** de
forma **explícita, restrita, temporária e auditável** — elevando privilégio de
maneira pontual (por capability e por alvo), com **motivo obrigatório**,
**duração/expiração** e **trilha de auditoria** da concessão, da revogação e do
**uso efetivo** — sem criar bypass genérico do Policy Engine, sem wildcard, sem
`superadmin` irrestrito e sem conceder ao ADMIN acesso automático a conteúdo
confidencial (F4-01, D17/D18).

### 1.2 Princípio central de segurança

Acesso excepcional é modelado como uma **ELEVAÇÃO EXPLÍCITA + RESTRITA +
TEMPORÁRIA + AUDITÁVEL**:

- **Explícita:** só existe mediante um grant excepcional com identidade
  própria, motivo e concedente rastreáveis;
- **Restrita:** fechada por beneficiário, capability, target, tenant e janela
  de vigência — nunca "ver tudo", nunca "qualquer confidencial";
- **Temporária:** sempre com fim (`valid_to`), expirando automaticamente;
- **Auditável:** concessão, revogação/expiração/alteração e **uso efetivo**
  registrados de forma identificável e atribuível.

Modelos equivalentes a "admin pode ver tudo", "manager acessa qualquer
confidencial", "possuir role ignora o engine", "exceptional access = bypass" ou
"exceptional access = wildcard" são **rejeitados** (ver §2.3 e §15).

### 1.3 O que entra na F4-06

- Contrato conceitual do **grant excepcional** (dimensões, ciclo de vida,
  auditoria) e da **classificação de confidencialidade** que o engine precisa;
- Posição do acesso excepcional no **Policy Engine** (origem C distinta), sem
  bypass e sem alterar o contrato F4-01..F4-05 sem decisão explícita;
- Mecanismo de **auditoria em três categorias** (concessão, ciclo de vida,
  uso efetivo) e diferenciação **"possuir grant" × "consumir grant"**;
- Requisitos que a **F4-08 (RLS)** deverá respeitar (§13) e fronteira exata
  com a **F4-07/Pilot Full Access** (§12).

### 1.4 O que NÃO entra (fora de escopo)

- Implementação/migration/RLS/`SECURITY DEFINER` (nesta atividade);
- Fluxos legais/compliance por país, SIEM externo e produção (Issue #93);
- Pilot Full Access (F4-07), políticas RLS finais (F4-08), persistência dos
  domínios no runtime (F5) e UI administrativa final;
- Reescrita de qualquer contrato fechado das F4-01..F4-05 sem decisão explícita.

## 2. Estado atual (fatos verificados)

### 2.1 Autorização hoje (origens A e B)

O Policy Engine (F4-03, pipeline determinística de 10 passos; F4-04/05
integrados) é a única porta de decisão na application layer. Atualmente existem
**duas origens** independentes, resolvidas por **união deduplicada** com origem
preservada no diagnóstico:

- **A — membership/roles/scopes:** capability efetiva da membership
  (`capabilities.hasCapability`) + scope ativo + relação (`relations.
  isTargetInScope`), com `matchedScope` no diagnóstico;
- **B — temporary responsibility (F4-05):** capability elegível pelo
  `responsibility_type` (allowlist fechada `TEMPORARY_RESPONSIBILITY_
  CAPABILITIES`) com raiz = position substituída, vigência por data e fronteira
  vivo × congelado; origens `temporary:<id>` no diagnóstico (`temporaryOrigins`).

Capability × tipo de target é contrato **fechado** (allowlist F4-04); tenant
mismatch = DENY; falha/indeterminação = DENY (fail-closed); o caller nunca
escolhe position/origem/responsabilidade; cargo/job_role nunca participa.

### 2.2 Confidencialidade e conteúdo sensível: LACUNA

**Não existe hoje nenhuma representação de conteúdo confidencial/sensível no
modelo nem no runtime.** Verificado:

- Nenhum campo/flag de confidencialidade, privacidade, restrição ou
  classificação em `Observacao`, `Feedback`, `Meta`, `Colaborador`,
  `CicloAvaliacao`, `ExpectativaCargo` ou `HistoricoOrganizacional`;
- Nenhuma capability de confidencialidade catalogada (nem no catálogo SQL da
  F4-01 — 21 capabilities — nem em `src/authorization/Capability.ts` — 33
  códigos do engine). A F4-01 D18 **decidiu explicitamente** não criar
  capability genérica `confidential.*` e deixar confidencialidade **separável
  por domínio/recurso** quando a necessidade concreta surgir;
- O termo "confidencial" só aparece em testes de comportamento
  ("ADMIN sem capability confidencial => DENY") e em princípios documentais.

**Conteúdo candidato a "confidencial"** no domínio atual: textos de avaliação
de terceiros (notas, comentários por competência, feedback final de gerente/
coordenador, votos de colegiado — `Feedback`), observações sobre colaboradores
(`Observacao`), e possivelmente notas/relatórios (`report`). Nenhum deles tem
classificação hoje. Esta lacuna é registrada (§19, Q1) e o desenho assume a
abordagem da F4-01 D18: **capabilities de confidencialidade separáveis por
domínio/recurso**, sem marcador genérico único.

### 2.3 ADMIN e "full access": estado real

- **ADMIN** é, na F4-01 (D17, fechada), um **access_role de sistema por
  membership/organização**, com bundle sem capabilities confidenciais, não é
  SUPER_ADMIN e não exige collaborator. ADMIN **nunca** recebe conteúdo
  confidencial automaticamente (D18). No runtime pré-F5 **não existe** role
  `admin` resolvida (o frontend usa `funcao`); existem allowlists provisórias
  server-side (`INVITE_ADMIN_USER_IDS`, `verify_jwt=false`) a serem substituídas
  por capabilities no banco em etapas que migrarem as Edge Functions;
- **Não existe** nenhum conceito implementado de bypass, superadmin irrestrito,
  Pilot Full Access (F4-07) ou acesso excepcional. Os únicos usos da palavra
  "excepcional" no código são **regras de domínio legadas** (correção
  excepcional de período de ciclo, reabertura excepcional) — que já são tratadas
  como regras de domínio via `DomainStateProbe`/estado, **não** como bypass;
- **No runtime, "admin" não é papel**: `FuncaoColaborador` não tem ADMIN; o
  sufixo `.admin` existe só em nomes de capability (ex.: `evaluation.view.
  admin`, `goal.view.admin` = "consulta administrativa", gates de página) e em
  desenho futuro (docs F4-01..F4-03, migrations). O teste
  `policyEngine.test.ts` já fixa o comportamento "ADMIN sem capability
  confidencial ⇒ DENY (CAPABILITY_MISSING)": escopo ORGANIZATION **não** implica
  capability de conteúdo — conteúdo sensível exige capability explícita;
- A única "impersonação" existente é **DEV-only** (F2-09, gate
  `simulacaoDevPermitida`, fail-closed fora de DEV) e **não participa** de
  autorização server-side — não é caminho para acesso excepcional;
- Leitura de avaliação hoje é gated por páginas/services (ex.: capability
  `evaluation.view.admin`) sobre `permissaoAvaliacao` (cadeia de gestor,
  coordenador direto, colegiado) — **ocultação na UI não é autorização**
  (AGENTS/arquitetura); não há gate de "leitura confidencial" de dados.

### 2.4 Auditoria existente: parcial e não centralizada

- **Runtime (localStorage):** trilhas de entidade append-only em arrays
  `historico`/eventos com `acao`, `data`, `autorMatricula`, `autorNome` e
  campos anteriores (metas — `metaStorage`; observações — `historico` de
  `Observacao`; ciclos — `cancelamento`, `reaberturas`, `correcoesPeriodo` com
  `justificativa`/`autor`; avaliações — `reaberturas`, `canceladoPor*`).
  Não há log centralizado de decisões de autorização;
- **Banco (F3/F4):** colunas `created_at/updated_at/version` + períodos
  `valid_from/valid_to` com exclusion; `reason` em occupations/temporary_
  responsibilities **sem autor** (limitação documentada na F3); `created_by`
  (autor, sem motivo) em `membership_access_role_assignments` (F4-01 D13) e
  `access_role_assignment_scopes` (F4-02). **`revogar_acesso_role` valida o
  ator mas NÃO persiste quem revogou** (não há `revoked_at/revoked_by/motivo`);
- Único ponto com **autor + motivo + append-only** no banco:
  `evaluation_succession_events` (F3-09);
- O contrato de saída do engine (F4-03 §6) já carrega `reason`/`matchedScope`/
  diagnóstico para alimentar auditoria futura sem refazer o engine; a F4-03 §21
  lista os campos a registrar na F4-06 (actor/user_profile, organization,
  capability, target type+id, decisão, denial reason, matched scope, contexto
  data/ciclo, timestamp);
- A F4-05 (D10) já preserva a origem `temporary:<id>` no diagnóstico **sem
  schema** e delega a "auditoria completa" para a F4-06.

### 2.5 Runtime pré-F5 (limitação transversal)

As fontes F3 (positions/reporting lines/occupations), roles/scopes e
`temporary_responsibilities` **não existem como dado no runtime atual**
(localStorage); fluxos de página permanecem legados por cargo até a F5
(Alternativa A da F4-04; mesma regra na F4-05). A F4-06 segue o mesmo padrão:
**contratos/core testáveis** (entrada F3-shaped/pura), sem bootstrap por cargo,
sem grant fake e sem localStorage como fonte definitiva de excepcional.

## 3. Quatro origens de autorização (A, B, C, D) — fronteiras

O desenho estabelece e **mantém separadas** quatro origens:

| Origem | O que é | Fase | Regra-chave |
| --- | --- | --- | --- |
| **A — normal** | membership + roles + scopes + relação | F4-01/02/03/04 | ALLOW por capability+scope sobre o alvo; `matchedScope` |
| **B — temporária** | temporary responsibility por data (allowlist por tipo) | F4-05 | ALLOW restrito à position substituída/vivo; `temporary:<id>` |
| **C — excepcional** | grant excepcional explícito (capability+target+janela+motivo) | F4-06 (esta) | ALLOW pontual sobre conteúdo confidencial; `exceptional:<id>` |
| **D — Pilot Full Access** | acesso total de piloto temporário/removível | F4-07 (futuro) | fora da F4-06; nunca antecipado aqui |

Regras de coexistência (detalhadas nas decisões D5/D6/D8 e §6):

1. **A e B já convivem por união deduplicada** com origem preservada (F4-05);
   C é uma **terceira origem independente** — não amplia A, não amplia B, não é
   derivada delas;
2. **C só é considerada quando A/B não cobrem o acesso** (§6.2): se a
   autorização normal já ALLOW, a operação segue normal e **nenhum grant
   excepcional é consumido** (sem evento de "uso excepcional" artificial);
3. Uma temporary responsibility **nunca se transforma implicitamente** em
   acesso excepcional (são fontes e regras distintas; F4-05 D1/D3/D10);
4. C **não antecipa D**: grant excepcional é específico (capability+target+
   janela), nunca organização inteira, nunca wildcard;
5. A concessão excepcional **não** concede a capability de conceder, e o
   concedente não recebe o conteúdo pelo ato de conceder (§8).

## 4. Confidencialidade: o que é e como o engine sabe

### 4.1 Princípio (herança da F4-01 D18, fechada)

Conteúdo confidencial exige **capability explícita** — **separável por
domínio/recurso**, **nunca** incluída automaticamente no ADMIN, e **sem**
capability genérica única (`confidential.*`) que abra todos os domínios.
Exemplo textual da própria F4-01: "acesso excepcional a avaliações não implica
acesso a todo o conteúdo confidencial do Virtus".

### 4.2 Lacuna e abordagem proposta

Como **não há fonte soberana** de classificação hoje, o desenho propõe (decisão
D7/D9) um modelo em duas camadas coerente com a F4-01 D18:

- **(i) capabilities confidenciais por domínio** — futuras capabilities de
  leitura de conteúdo confidencial por domínio (ex.: `evaluation.confidential.
  read`) **ou**, na ausência de nova capability, o reuso de capabilities de
  leitura existentes com **classificação de recurso** — ver D7 (não decidido);
- **(ii) classificação do recurso** resolvida pelo domínio (análoga ao
  `DomainStateProbe`): um recurso é confidencial, não confidencial, histórico/
  congelado, inexistente ou de classificação indeterminada.

### 4.3 Comportamentos por tipo de conteúdo (requisitos)

- **Normal:** autorização A/B suficiente; C não é consultada;
- **Confidencial:** exige capability confidencial (D7); C (grant excepcional) é
  a única forma de elevação pontual quando A/B não cobrem;
- **Histórico/congelado (F3-08/F3-09 e ciclo encerrado):** fontes congeladas
  soberanas; C, se aplicável, é **somente leitura** do que a fonte congelada
  expõe — nunca mutação/reescrita (ver §11);
- **Inexistente/inacessível:** tenant não resolvido ⇒ `TARGET_INVALID`
  (NOT_FOUND público) — comportamento atual preservado;
- **Classificação indeterminada:** qualquer indeterminação relevante à
  segurança (não dá para saber se é confidencial, vivo × congelado, ou se o
  grant se aplica) ⇒ **DENY** (fail-closed), ver D15.

## 5. O grant excepcional (modelo conceitual)

### 5.1 Dimensões mínimas seguras (todas obrigatórias salvo indicação em D10)

| Dimensão | Obrigatória | Observação |
| --- | --- | --- |
| `organizationId` (tenant) | sim | FKs compostas futuras; cross-tenant impossível |
| `beneficiary` | sim | membership/user_profile (F4-01 D17: ADMIN sem collaborator) |
| `grantedBy` | sim | user_profile do concedente (auditoria) |
| `capability` | sim | código fechado (allowlist de capabilities elegíveis, D7/D8) |
| `target` | sim | `TargetRef` tipado (tipo + id) — **nunca nulo/org-wide** |
| `cycleId`/contexto | condicional | quando o recurso é por ciclo (avaliação); D10 |
| `justification` | sim | motivo obrigatório (trim, não vazio) |
| `validFrom`/`validTo` | sim | janela fechada; `valid_to > valid_from`; sem "permanente acidental" |
| `status` | sim | `active`/`revoked` (revogação por estado, sem exclusão) |
| revogação | registro | `revokedAt`, `revokedBy`, `revocationMotive` (D14) |
| `createdAt`/`version` | sim | padrão do banco |

Nenhuma dimensão pode ser "opcional" de forma a criar wildcard ou ambiguidade:
**capability nula, target nulo, sem beneficiário, sem justificativa, período
inválido, grant retroativo indevido ou duplicidade ambígua são proibidos** por
constraints conceituais (§10.3).

### 5.2 Estado/cycle de vida

```
SOLICITADO (opcional, D1) → ATIVO → EXPIRADO (automático por data)
        │                      │
        └── NEGADO / CANCELADO ─┴──→ REVOGADO (manual, motivo, efeito imediato D14)
```

- Expiração é **por data** (decisão sempre resolve vigência lendo o grant; sem
  cache — mesmo princípio da F4-05 D15);
- Revogação tem **efeito imediato** e nunca exclui o registro (append-only);
- "Possuir grant" (registro ativo) ≠ "consumir grant" (uso efetivo para
  autorizar uma operação) — §9.

## 6. Integração ao Policy Engine

### 6.1 Onde NÃO entra

**Nunca** antes do engine, depois do engine ou fora dele (nenhum bypass; a UI
nunca decide). O `authorize()`/`decidir()` permanece a única porta; C é uma
origem avaliada **dentro** do pipeline.

### 6.2 Ordem recomendada (D6/D8 — aberta, com recomendação)

Preservar os passos atuais 1–4 (identidade/profile/membership/tenant) e 5.1
(capability × target) para **todas** as origens, e avaliar:

```
1–4 base (inalterados; fail-closed)
5  capability A (membership)  ⊕ 5.0 capability B (temporária elegível)
   → se A/B ALLOW capability → seguir 6/7
   → se NENHUMA origem A/B tem a capability:
        - se capability ∈ allowlist-de-exceção (fechada, D8):
            consultar origem C (grant excepcional) — §6.3
        - senão → CAPABILITY_MISSING (inalterado)
5.1 capability × target (compartilhado; inalterado)
6/7 scope/relação A ⊕ B (inalterado; união com origem preservada)
   → se A/B ALLOW alvo ∈ alcance → ALLOW normal (matchedScope/temporaryOrigins)
   → se A/B DENY por escopo (SCOPE_INSUFFICIENT) E capability ∈ allowlist-de-exceção:
        consultar origem C (§6.3)
8  contexto temporal explícito
9  estado do domínio (probe soberano; inclui exclusividade e vivo × congelado)
10 ALLOW
```

Ou seja: **a origem C só é consultada quando (i) a capability é elegível a
exceção (allowlist fechada), (ii) A/B não autorizaram a operação e (iii) o
estado do domínio não já negou a operação.** Isso materializa o requisito
"exceptional access só deve ser considerado quando a autorização normal não
cobre o acesso" e evita consumo desnecessário de grant.

### 6.3 Consulta da origem C (provider)

`ExceptionalGrantProvider` (contrato puro, entrada F3/F4-shaped — §10.1):

```
resolveExceptionalGrants(beneficiaryId, organizationId, capability, target,
                         date, cycleId?): ExceptionalGrant[]
```

- Filtra por **beneficiário + tenant + vigência + status ativo + capability +
  target** (todos os dados vindos do provider; o caller **não informa** id de
  grant nem origem);
- Resultado: 0 grants ⇒ mantém a negação original (fail-closed);
  1 grant ⇒ ALLOW **excepcional** (diagnóstico `exceptionalGrant` = id/origem);
  >1 grant aplicável ⇒ política de ambiguidade (D16): fail-closed por padrão,
  com alternativa de menor privilégio;
- Reutilização indevida é impedida estruturalmente: o mesmo grant **não**
  autoriza capability diferente (o filtro exige igualdade exata), target
  diferente (igualdade exata do `TargetRef`), outro tenant (igualdade), nem fora
  da vigência (data ∈ [validFrom, validTo)).

### 6.4 Diferenciação na decisão e no diagnóstico

| Situação | `allowed` | Diagnóstico |
| --- | --- | --- |
| A/B ALLOW | true | `matchedScope` e/ou `temporaryOrigins` (origem normal/temporária) |
| C ALLOW | true | `exceptionalGrant: { id, origin: "exceptional:<id>" }` (sem `matchedScope`) |
| DENY | false | `denial.reason` + `publicCode` (razão interna só p/ log, F4-03 D6) |

- Origem preservada por grant (padrão F4-05 D10): `exceptional:<id>`;
- Razões internas de negação da exceção (ex.: grant inexistente/expirado/
  revogado/capability não elegível) permanecem internas — o público é FORBIDDEN
  (ou NOT_FOUND para cross-tenant), **sem revelar** a existência do grant;
- Se precisar diferenciar internamente a negação da origem C, avaliar uma razão
  nova (ex.: `EXCEPTIONAL_GRANT_UNAVAILABLE`) — registro em D17; **não** alterar
  o enum existente sem decisão explícita.

### 6.5 Restrições transversais (inalteradas)

- `can` é auxiliar; `authorize` protege mutações (F4-03 D5);
- `listAllowedTargets` continua auxiliar e **nunca** é fonte de decisão; deve
  refletir C apenas quando o pedido explicitamente avalia conteúdo confidencial
  — ver D18;
- DOMAIN_STATE (passo 9) continua soberano: se o domínio nega (ex.: ciclo
  congelado que não admite escrita, conteúdo com leitura restrita), a exceção
  não "furar" a regra de domínio.

## 7. Confidencialidade × capabilities (allowlist de exceção)

Duas questões encadeadas (D7/D8): (a) quais capabilities um grant excepcional
pode conceder; (b) como o engine sabe que o alvo é confidencial.

- **(a)** Contrato **fechado**: `EXCEPTIONAL_CAPABILITIES` (allowlist explícita
  — sem prefixo genérico, sem wildcard). Recomendação (D8): começar **somente
  leitura** de conteúdo confidencial por domínio (ex.: leitura de avaliação
  `evaluation.read`/variante confidencial, leitura de observação/report), **sem
  capabilities de escrita/exclusão** na F4-06 (exceto decisão explícita);
- **(b)** Recomendação (D7): capabilities de confidencialidade **separáveis por
  domínio** criadas quando a implementação exigir (F4-01 D18), mantendo o
  engine com capability única por ação; o domínio classifica o recurso e o
  `TargetRef` aponta a instância. A classificação vem do domínio (probe), nunca
  do caller.

**Inconsistência nominal registrada** (ver §17 e Q6): o catálogo SQL da F4-01
(21 códigos, ex.: `observation.write`, `report.read`) difere dos códigos do
engine (33, ex.: `observation.create/edit/delete`, `report.view`,
`goal.view.admin`). A allowlist de exceção deve ser definida sobre **um**
vocabulário — recomendação preliminar: os códigos do engine
(`src/authorization/Capability.ts`), com alinhamento futuro do catálogo
(questão para validação, não resolvida aqui).

## 8. Quem pode conceder (sem cargo, sem escalada)

- **Concedente** é identificado por **user_profile** com autorização de
  conceder resolvida no engine (nunca por cargo). Recomendação (D2/D3): existir
  **capability própria de concessão excepcional** (administrativa), separável da
  capability de conteúdo — ex.: `exceptional_access.grant` (nome NÃO definitivo;
  registrar como decisão arquitetural, não inventada silenciosamente);
- **Sobre quais targets:** dentro do tenant do concedente; o concedente
  concede **sem precisar possuir o conteúdo** (conceder é ato administrativo;
  possuir o conteúdo é ato operacional — D4);
- **Auto-concessão:** recomendação **proibida** (concedente ≠ beneficiário);
  alternativa com aprovação de segundo concedente (dual control) em D2/D3;
- **Escalada:** sem role nova automática; o grant concede somente a capability
  do allowlist fechado; conceder não adiciona role nem scope; a capability de
  conceder é por organização (membership), sem papel global (F4-01 D17);
- **Aprovação adicional:** D2 — recomendação de aprovação de **dois
  concedentes independentes** para conteúdos de maior sensibilidade, com
  fluxo alternativo de concessão única auditada.

## 9. Auditoria (três categorias + posse × uso)

Trilha **append-only**, por **user_profile** (não colaborador), com tenant,
timestamp e grant id. Reusa o padrão F3-09 (`evaluation_succession_events`) e
os campos da F4-03 §21. Conceitualmente três fluxos de eventos (schema futuro
descrito em §10.2; **sem migration nesta atividade**):

- **(A) Concessão:** quem concedeu (e quem aprovou, se dual control), para
  quem, quando, por quê (motivo obrigatório), tenant, capability, target,
  `validFrom`, `validTo`;
- **(B) Ciclo de vida:** revogação (quem/quando/motivo), expiração
  (automática, por data — evento registrável), alteração (janela/motivo — nova
  versão ou close+open, nunca edição silenciosa);
- **(C) Uso efetivo:** cada operação autorizada **pelo grant excepcional**:
  quando, qual grant (`exceptional:<id>`), qual beneficiário, qual
  capability/ação, qual target, contexto data/ciclo, e o resultado (ALLOW).

**Posse × consumo:** a existência de grant ativo não gera evento de uso; apenas
a **decisão que efetivamente consumiu o grant** gera. Se a autorização normal
já permitir a operação, **não existe evento de "uso excepcional"** (D12) — a
origem C não foi necessária. (Exceção a avaliar em D12: leituras de conteúdo
classificado confidencial sob autorização normal — "baseline de audit",
Q3/Q4.)

## 10. Modelagem conceitual (tipos/contratos futuros — sem código/schema)

### 10.1 Contratos TS puros (entrada para provider — F3/F4-shaped)

```
ExceptionalAccessGrant {
  id: string; organizationId: string;
  beneficiaryUserProfileId: string;      // (ou membershipId — D19)
  grantedByUserProfileId: string;
  approvedByUserProfileId?: string;      // dual control (D2/D3)
  capability: Capability;                // ∈ allowlist fechada (D8)
  target: TargetRef;                     // tipo+id exatos
  cycleId?: string;                      // quando o recurso é por ciclo (D10)
  justification: string;                 // motivo obrigatório
  validFrom: Date; validTo: Date;        // janela fechada
  status: "active" | "revoked";
  revokedAt?: Date; revokedBy?: string; revocationMotive?: string;
  createdAt: Date; version: number;
}

ExceptionalGrantProvider {               // origem C no engine
  isCapabilityExceptionalEligible(capability): boolean;   // allowlist D8
  resolveExceptionalGrants(beneficiaryId, organizationId, capability,
                           target, date, cycleId?): ExceptionalGrant[];
}
```

### 10.2 Schema futuro (descrito conceitualmente — NÃO criar migration)

Tabelas/eventos futuros (nomes sugestivos): `exceptional_access_grants` (linha
de estado ativo/revogado, FKs compostas de tenant, `created_by`/`approved_by`,
sem exclusão física) e eventos append-only `exceptional_access_events`
(categoria `granted|revoked|expired|altered|used`, com motivo/autor/campos da
F4-03 §21 e `grant_id`). O desenho da F4-06 **não decide** ainda se haverá uma
ou duas tabelas (D20).

### 10.3 Constraints conceituais (anti-wildcard/anti-bypass)

- `capability` NOT NULL e ∈ allowlist fechada de exceção; `target` NOT NULL
  (sem target org-wide); sem `target_type` genérico com id livre (usa
  `TargetRef` tipado — F4-03 D4);
- beneficiário ≠ concedente (auto-concessão proibida, D3);
- `justification` NOT NULL (trim, não vazio) e `valid_to > valid_from`;
- revogação/expiração nunca apagam linha; `status` limitado;
- unicidade de tenant por FK composta em todas as referências;
- duplicidade ambígua: sem dois grants ativos "equivalentes" conflitantes para
  o mesmo (beneficiário, capability, target, janela) quando isso gerar
  ambiguidade de decisão (regra em D16/D20);
- `created_by`/eventos exigem `user_profile` ativo e mesmo tenant.

## 11. Recursos históricos/congelados (F3-08/F3-09)

- F3-08 (snapshots imutáveis) e F3-09 (responsabilidades + sucessão append-only)
  permanecem **soberanos**; acesso excepcional **não os reescreve, não os
  substitui e não concorre** com eles;
- Sobre conteúdo congelado, o grant excepcional, quando aplicável, permite
  **somente leitura** do que a fonte congelada registra — **nunca** alterar
  autoria/responsabilidade histórica, **nunca** criar sucessão implícita,
  **nunca** mutar snapshot (mesma fronteira vivo × congelado da F4-05 D8/D9);
- Recurso vivo × congelado: se o domínio não consegue distinguir ⇒ DENY;
- Qualquer possibilidade futura de **mutação** de conteúdo histórico/
  confidencial via exceção é **decisão arquitetural explícita** (D15) — não
  existe nesta fase.

## 12. Fronteira com a F4-07 / Pilot Full Access

- A F4-07 (Pilot Full Access) é **futura e fora destes cinco documentos de
  desenho** (não há menção nos docs F4-01..F4-05). A F4-06 **não a antecipa**:
  não cria wildcard, acesso implícito organização-wide, bypass genérico,
  superuser ou admin universal;
- Se alguma necessidade da F4-06 parecer exigir "ver tudo"/acesso de piloto,
  isso é registrado como **questão/decisão** (D5/Q7) e **não** implementado;
- A fronteira operacional será: F4-06 = grant excepcional específico
  (capability + target + janela + auditoria); F4-07 = full access de piloto
  temporário/removível com modelo próprio (a definir na F4-07).

## 13. F4-08 / RLS — requisitos que o desenho impõe (documentar, sem policy)

A F4-08 deverá respeitar:

1. RLS como **última barreira server-side** por linha; o engine nunca substitui
   RLS (F4-03 §19);
2. Predicados RLS futuros por tabela **restritos**, derivados dos mesmos
   conceitos (membership ativa, scopes, grants excepcionais) — sem predicado
   que conceda "tudo" a `authenticated`;
3. Tabelas do grant excepcional e eventos de auditoria com **deny-by-default**
   e policies mínimas (própria leitura/escrita de quem tem a capability de
   conceder/auditar);
4. A resolução server-side deve consumir **os mesmos contratos** (probe/
   providers) — revalidação atômica na mesma RPC/transação (F4-03 D9, requisito
   F5/F4-08);
5. Nenhuma policy/RPC é escrita nesta atividade (fora de escopo).

## 14. Runtime pré-F5 (limitação e regras para a implementação futura)

- As fontes necessárias (roles/scopes resolvidos, classification de
  confidencialidade, user_profile↔membership no cliente, grants excepcionais)
  **não existem no runtime atual**;
- A implementação futura deve entregar **contratos/core testáveis** (provider
  puro + allowlist + eventos em memória para teste), **sem** bootstrap por
  cargo, **sem** grant fake/local como fonte definitiva e **sem** localStorage
  como fonte soberana de exceção;
- Migração funcional (UI administrativa, telas de concessão) fica para a fonte
  F3/roles no runtime (F5) — mesmo condicionamento das F4-04/F4-05;
- A auditoria de uso deve ser alimentada pelo contrato de saída do engine
  (`reason`/`matchedScope`/origens), sem refazer o engine (F4-03 §21).

## 15. Matriz de testes (para a futura implementação)

Mínimo exigido (40 itens da Issue) + complementos; cada caso valida contrato
fechado, sem cargo e sem wildcard:

1. grant válido → ALLOW excepcional (origem `exceptional:<id>`);
2. grant expirado → DENY (sem uso);
3. grant futuro → DENY;
4. grant revogado → DENY (efeito imediato);
5. capability diferente da concedida → DENY;
6. target diferente → DENY;
7. target type diferente → DENY;
8. cross-tenant (grant de outra org / alvo de outra org) → DENY;
9. beneficiário diferente → DENY;
10. caller tenta selecionar grant (não há campo; provider resolve) → impossível/inalterado;
11. caller tenta selecionar origem → impossível/inalterado;
12. justificativa ausente → concessão rejeitada (validação de domínio);
13. concedente sem autorização (sem capability de conceder) → DENY;
14. auto-concessão → proibida;
15. conteúdo não confidencial → grant excepcional não consultado (A/B decidem);
16. conteúdo confidencial → C consultada somente se A/B DENY;
17. recurso histórico/congelado → leitura somente, sem reescrita (F3-08/09 intactos);
18. recurso inexistente → TARGET_INVALID/NOT_FOUND (sem revelar existência);
19. classificação de confidencialidade indeterminada → DENY;
20. normal ALLOW + grant existente → ALLOW normal, sem consumo (sem evento de uso);
21. normal DENY + grant válido → ALLOW excepcional com evento de uso;
22. coexistência com F4-05 (origens B e C simultâneas) → origens independentes,
    sem ampliação cruzada;
23. múltiplos grants válidos → política de ambiguidade (D16);
24. múltiplos grants, apenas um corresponde ao target → ALLOW pelo correspondente;
25. tentativa de wildcard (target nulo/org-wide) → rejeitada na concessão;
26. capability não prevista na allowlist de exceção → não concedível;
27. target não previsto (tipo incompatível com capability — F4-04) → TARGET_INCOMPATIBLE;
28. dados incompletos (sem tenant/target/capability) → DENY/rejeitado;
29. auditoria da concessão → evento append-only com concedente/beneficiário/
    motivo/target/janela;
30. auditoria da revogação → evento com revogador/motivo/data;
31. auditoria da expiração → evento/derivação por data;
32. auditoria do uso efetivo → evento por operação consumida, com grant id;
33. decisão normal ALLOW sem consumir grant (≠ consumo);
34. grant existente mas fora do alcance (capability/target/tenant) → DENY;
35. revogação com efeito imediato (sem cache);
36. grant vencendo entre duas operações → segunda operação DENY;
37. isolamento entre tenants (conceder/consumir);
38. reutilizar grant para outro recurso → DENY;
39. reutilizar grant para outra capability → DENY;
40. fail-closed quando não dá para determinar se o grant se aplica → DENY.

Complementos recomendados: concessão com dual control (se D2 = dual) — um
aprovador ausente ⇒ não ativa; revogação não exclui registro; concedente ≠
beneficiário; ADMIN sem grant explícito continua DENY em conteúdo confidencial
(Issue #93); capability de conceder não concede o conteúdo; engine não
consulta cargo/job_role em nenhum caminho C.

## 16. Riscos, dependências e itens fora de escopo

- **Riscos:** (r1) deriva para bypass/wildcard (mitigado por allowlist fechada
  D8 + target obrigatório + janela); (r2) consumo acidental de grant (mitigado
  por C só quando A/B DENY, D6); (r3) auditoria incompleta (mitigado por 3
  categorias + posse×uso, §9); (r4) escalada via concedente (mitigado por
  auto-concessão proibida + capability de conceder por org); (r5) ambiguidade de
  múltiplos grants (D16 fail-closed); (r6) vazamento de existência (razões
  internas nunca públicas, F4-03 D6).
- **Dependências:** F4-01 (capabilities/roles/ADMIN D17/D18), F4-02 (scopes/
  tenant), F4-03 (engine/pipeline/§21), F4-04 (contrato capability×target),
  F4-05 (origens/unidade union, fronteira vivo×congelado), F3-08/F3-09
  (soberania de histórico), F4-07/F4-08 (fronteiras), F5 (runtime).
- **Fora de escopo:** implementação, UI final, F4-07, RLS (F4-08), fluxos
  legais/SIEM/produção, correção de inconsistência de catálogo de capabilities
  (registrada, Q6).

## 17. Conflitos/atenções com contratos F3/F4 existentes

1. **Drift de numeração:** a F4-01 chama a fase de acesso excepcional de
   "F4-09" (D3/D7/§8); F4-02+ chamam de F4-06. Não altera contrato, mas deve ser
   normalizado na revisão;
2. **Inconsistência nominal de capabilities:** catálogo SQL F4-01 (21 códigos)
   × códigos do engine (33). A allowlist de exceção precisa de vocabulário único
   (Q6);
3. **`revogar_acesso_role` não persiste revogador/motivo** e
   `membership_access_role_assignments` não tem `revoked_at/revoked_by` — a F4-06
   não corrige migrations (fora de escopo), mas registra o requisito de auditoria
   própria dos grants excepcionais com revogador/motivo desde o desenho;
4. **F4-01 D17/D18 (fechadas)** são vinculantes: ADMIN por org, sem conteúdo
   confidencial automático, confidencialidade separável por domínio sem
   capability genérica — a F4-06 respeita sem reabrir;
5. **F4-03 D6/D8/D9 e §21**: razões internas não públicas; sem SECURITY DEFINER
   novo; auditoria alimentada pelo contrato de saída; revalidação server-side é
   F5/F4-08;
6. **F4-05 D10/D16**: origem no diagnóstico sem schema; auditoria completa é
   desta fase; sem migration — preservado;
7. **F4-08:** o grant excepcional será exposto em policies futuras somente
   quando a RLS existir (não agora).

## 18. Decisões arquiteturais (D1–D20 — ABERTAS)

> Nenhuma decisão é considerada automaticamente aprovada. Cada uma lista
> problema, alternativas, recomendação, justificativa, riscos, impacto e
> dependências. Quando a questão também for de validação de negócio, aparece em
> §19 (Questões para validação).

### D1 — Fluxo de solicitação × concessão administrativa

- **Problema:** existe um pedido (request) de acesso excepcional ou somente a
  concessão administrativa direta?
- **Alternativas:** (A) somente concessão administrativa (concedente cria o
  grant ativo; registra concessão); (B) fluxo de solicitação: beneficiário pede
  com justificativa e concedente aprova; (C) híbrido (solicitação opcional).
- **Recomendação:** (B) com concessão administrativa como atalho autorizado —
  porém **aberta**; depende da operação real (Q2/Q5).
- **Justificativa:** a Issue pede "mecanismo explícito de concessão/uso" e
  motivo obrigatório; um pedido formal melhora auditoria, mas custa fluxo.
- **Riscos:** (A) sem rastro do "porquê foi pedido"; (C) superfície maior.
- **Impacto:** UI/estado do grant (status SOLICITADO); eventos de auditoria.
- **Dependências:** D2 (quem aprova), D13 (vigência), §9.

### D2 — Aprovação adicional (dual control)

- **Problema:** a concessão exige um segundo concedente independente?
- **Alternativas:** (A) concessão única auditada; (B) dual control obrigatório;
  (C) dual control somente para domínios de maior sensibilidade.
- **Recomendação:** (C), com lista de domínios sensíveis fechada.
- **Justificativa:** reduz risco de abuso sem burocratizar todo acesso.
- **Riscos:** (A) escalada por concedente único; (B) atrasos; (C) definição de
  sensibilidade.
- **Impacto:** campos `approvedBy`, status intermediário, eventos.
- **Dependências:** D1, D3, §8.

### D3 — Quem pode conceder (capability de concessão)

- **Problema:** como autorizar o ato de conceder sem cargo e sem escalada.
- **Alternativas:** (A) nova capability administrativa (ex.:
  `exceptional_access.grant`) por organização, nunca no bundle `admin`
  automático; (B) reusar `access_role.manage`; (C) sem capability — regra
  externa.
- **Recomendação:** (A), com nome registrado como decisão (não definitivo) e
  fora do bundle `admin` automático.
- **Justificativa:** concessão de exceção é ato administrativo distinto de
  conteúdo; separação evita "quem lê também concede".
- **Riscos:** multiplicação de capabilities; bundle futuro acidental.
- **Impacto:** catálogo futuro de capabilities (sem migration agora), resolução
  de quem pode conceder no engine.
- **Dependências:** D7 (allowlist), F4-01 D17/D18, §8.

### D4 — Concedente precisa possuir o conteúdo?

- **Problema:** quem concede precisa ter acesso normal ao conteúdo?
- **Alternativas:** (A) não — conceder é ato administrativo; (B) sim —
  concedente só concede o que alcança.
- **Recomendação:** (A), com rastro; possuir o conteúdo é ato operacional.
- **Justificativa:** evita acoplamento admin×conteúdo (F4-01 D17/D18).
- **Riscos:** concedente "cego" pode conceder demais → mitigado pela allowlist
  fechada e target obrigatório.
- **Impacto:** nenhum requisito de scope para o concedente além da capability.
- **Dependências:** D3.

### D5 — Auto-concessão

- **Problema:** o concedente pode conceder a si mesmo?
- **Alternativas:** (A) proibida; (B) permitida com auditoria; (C) permitida
  somente com dual control.
- **Recomendação:** (A) proibida (concedente ≠ beneficiário), com exceção
  registrada se dual control aprovar.
- **Justificativa:** princípio de segregação; teste 14 da matriz.
- **Riscos:** (B/C) conflito de interesse.
- **Impacto:** constraint conceitual (§10.3).
- **Dependências:** D2.

### D6 — Quando a origem C é consultada (ordem)

- **Problema:** posicionar C sem enfraquecer A/B e sem consumo acidental.
- **Alternativas:** (A) C só quando A/B DENY (recomendada); (B) C avaliada em
  paralelo e escolhida por menor privilégio; (C) C antes de A/B (não).
- **Recomendação:** (A) — C é fallback pontual, nunca substituta da avaliação
  normal (a normal **continua sendo avaliada** sempre).
- **Justificativa:** "exceptional access só considerado quando normal não cobre"
  (Issue) e não gerar evento de uso excepcional quando normal ALLOW (D12).
- **Riscos:** (A) dupla avaliação em casos normais (custo mínimo — gate por
  allowlist); (B) ambiguidade de qual origem vence.
- **Impacto:** pipeline do engine (§6.2); sem alterar passos 1–4/5.1/8–9.
- **Dependências:** D8, D16.

### D7 — Como o engine sabe que o alvo é confidencial

- **Problema:** não existe classificação hoje (§2.2).
- **Alternativas:** (A) capabilities confidenciais por domínio (F4-01 D18) —
  nova capability só quando implementar; (B) probe/classificação do domínio
  sobre o recurso carregado; (C) marcador no target.
- **Recomendação:** (A) como vocabulário + (B) como fonte de verdade da
  classificação no runtime (o domínio declara; o engine consome), sem marcador
  no TargetRef (evita caller classificar).
- **Justificativa:** alinha com F4-01 D18 e com o papel soberano do
  DomainStateProbe (F4-03 D3/D9).
- **Riscos:** (A) nova capability sem catálogo SQL (vocabulário do engine);
  (B) domínio precisa expor classificação (trabalho futuro).
- **Impacto:** contrato de entrada do provider C e probe.
- **Dependências:** Q1 (o que é confidencial), D8.

### D8 — Allowlist de capabilities excepcionais (fechada)

- **Problema:** quais capabilities um grant excepcional pode conceder.
- **Alternativas:** (A) somente leitura confidencial por domínio (recomendada);
  (B) leitura+escrita pontual; (C) qualquer capability.
- **Recomendação:** (A) — allowlist explícita fechada, sem prefixo/wildcard,
  sem escrita nesta fase; escrita excepcional seria decisão separada (D15).
- **Justificativa:** menor privilégio; Issue pede "limitado por capability e
  escopo"; escrita em conteúdo confidencial é risco alto.
- **Riscos:** (B/C) ampliação silenciosa; (A) necessidade futura de escrita →
  reabre decisão.
- **Impacto:** allowlist no core (sem catálogo SQL nesta fase).
- **Dependências:** D7, Q6 (vocabulário).

### D9 — Conteúdo normal × confidencial na decisão

- **Problema:** garantir que recurso normal nunca dependa de C e que recurso
  confidencial não seja acessível por A/B sem a capability adequada.
- **Alternativas:** (A) confidencialidade materializada como capability extra
  por domínio (recomendada — recurso confidencial só com capability
  confidencial OU grant excepcional); (B) apenas grant excepcional para
  qualquer confidencial.
- **Recomendação:** (A) — mantém gestor com escopo normal lendo o que lhe é
  permitido e exige elevação só para o que A/B não cobrem.
- **Justificativa:** não criar segunda matriz de policy; capability única por
  ação (F4-04 D18).
- **Riscos:** duplicidade capability normal×confidencial por domínio.
- **Impacto:** modelo conceitual de capability; testes 15/16/21.
- **Dependências:** D7/D8, Q1.

### D10 — Contexto por ciclo no grant (cycleId opcional?)

- **Problema:** o grant deve poder apontar um ciclo (avaliação de um ciclo)?
- **Alternativas:** (A) target específico SEM ciclo (recurso confidencial
  pontual, ex.: uma observação); (B) target + `cycleId` quando o recurso é por
  ciclo (avaliação de ciclo Y); (C) permitir ambos com regra fechada.
- **Recomendação:** (C) com regra: se o tipo de recurso é por ciclo, `cycleId`
  é obrigatório; senão ausente. Nada de "todos os ciclos".
- **Justificativa:** alvo preciso sem wildcard temporal.
- **Riscos:** esquecer ciclo em recurso por ciclo → escopo amplo acidental.
- **Impacto:** dimensão `cycleId` (§5.1); TargetRef.
- **Dependências:** D8, matriz testes 6/7.

### D11 — Granularidade: instância única por grant

- **Problema:** um grant pode cobrir N instâncias/recursos?
- **Alternativas:** (A) 1 grant = 1 capability + 1 target (recomendado);
  (B) grant por lote de targets explícitos; (C) por escopo (não).
- **Recomendação:** (A), com (B) apenas como lista explícita fechada de ids se
  necessário — nunca escopo/árvore.
- **Justificativa:** rastreabilidade direta (qual grant usou qual recurso);
  evita "grant = mini-scope".
- **Riscos:** volume de grants para muitos recursos (aceitável).
- **Impacto:** shape do grant; auditoria por target.
- **Dependências:** §5, D16.

### D12 — Consumo × posse; leitura sensível sob autorização normal

- **Problema:** quando registrar "uso" e se leituras sensíveis normais entram
  no baseline de audit.
- **Alternativas:** (A) evento de uso somente quando C autoriza (recomendado);
  (B) também registrar leituras de conteúdo classificado confidencial sob A/B
  ("baseline de audit"); (C) ambos com granularidade distinta.
- **Recomendação:** (C) com (A) obrigatório e (B) como item de validação (Q3/
  Q4) — o significado de "baseline de audit" da Issue precisa de definição.
- **Justificativa:** auditoria de exceção exige (A); a Issue menciona
  "leituras/ações sensíveis conforme baseline de audit", cuja semântica não está
  definida em nenhum doc (Q3).
- **Riscos:** (B) explosão de eventos; (A) só, pode perder contexto de leitura
  sensível normal.
- **Impacto:** contrato de evento de uso; custo de escrita.
- **Dependências:** Q3/Q4.

### D13 — Duração/expiração (defaults)

- **Problema:** como impor fim sem "permanente acidental".
- **Alternativas:** (A) janela fechada obrigatória, sem default de "até
  segundo aviso" (recomendado); (B) permitir aberto com revalidação periódica.
- **Recomendação:** (A) — `valid_to` obrigatório; expiração automática por data
  (sem job/cache).
- **Justificativa:** F4-01 D7 adiou janela para F4-06; requisito
  "duração/expiração quando aplicável" e "acesso pode expirar".
- **Riscos:** (B) esquecimento de revogar.
- **Impacto:** estado; evento de expiração (derivável por data).
- **Dependências:** D1/D14.

### D14 — Revogação (quem/quando/motivo/efeito)

- **Problema:** ciclo de vida da revogação.
- **Alternativas:** (A) revogação manual por concedente (ou quem tem a
  capability), com motivo, efeito imediato, sem exclusão (recomendado);
  (B) também revogação automática por encerramento de vínculo/perfil.
- **Recomendação:** (A) + (B) automática quando membership/profile desativar
  (reflexo na resolução, sem job).
- **Justificativa:** Issue pede revogação sem alterar hierarquia e com efeito
  imediato; corrige a lacuna observada no padrão F4-01 (revogador não
  persistido).
- **Riscos:** revogação esquecida → janela curta default + revisão.
- **Impacto:** campos revoked*; evento categoria B.
- **Dependências:** D13, §9.

### D15 — Mutação de conteúdo histórico/confidencial via exceção

- **Problema:** o grant excepcional pode autorizar escrita em conteúdo
  confidencial/histórico?
- **Alternativas:** (A) somente leitura nesta fase (recomendado); (B) leitura
  + escrita pontual com regras de domínio fortes; (C) nunca.
- **Recomendação:** (A) — F3-08/F3-09 soberanos; qualquer mutação de histórico
  é decisão explícita futura (§11).
- **Justificativa:** proteger snapshots e autoria; Issue não exige escrita.
- **Riscos:** necessidade futura de ajuste → reabrir decisão com aprovação.
- **Impacto:** allowlist D8 (só leitura); testes 17.
- **Dependências:** D8, §11.

### D16 — Múltiplos grants aplicáveis (ambiguidade)

- **Problema:** dois ou mais grants ativos casam com o mesmo pedido.
- **Alternativas:** (A) fail-closed (DENY com log) — recomendado; (B) união
  (ALLOW se qualquer um casar); (C) menor privilégio (mais restrito/que expira
  primeiro).
- **Recomendação:** (A) por padrão; evoluir para (C) se a operação exigir —
  evitar decisão não determinística.
- **Justificativa:** duplicidade ambígua = risco; determinismo.
- **Riscos:** (A) pode bloquear caso legítimo raro (mitigado: constraint
  conceitual anti-duplicidade §10.3 impede o estado).
- **Impacto:** resolução no provider; testes 23/24.
- **Dependências:** D20 (unicidade), §10.3.

### D17 — Razões de negação/diagnóstico da origem C

- **Problema:** o engine precisa de razão/diagnóstico novo para C?
- **Alternativas:** (A) reutilizar razões atuais e diferenciar só por
  diagnóstico (`exceptionalGrant` presente); (B) adicionar razão interna
  (ex.: `EXCEPTIONAL_GRANT_UNAVAILABLE`) mapeada para FORBIDDEN; (C) expor
  motivo da não concessão.
- **Recomendação:** (B) como razão interna (nunca pública — F4-03 D6), com
  (A) no diagnóstico; (C) rejeitado (não revelar existência).
- **Justificativa:** log/auditoria interna sem vazar informação.
- **Riscos:** ampliar enum sem necessidade.
- **Impacto:** `DenialReason` futuro, errors.ts, §21 F4-03.
- **Dependências:** D6/D8.

### D18 — listAllowedTargets e UI sob exceção

- **Problema:** listagem auxiliar deve refletir C?
- **Alternativas:** (A) `listAllowedTargets` continua avaliando A/B; para
  conteúdo confidencial lista apenas com contexto explícito de exceção
  (recomendado); (B) nunca lista via C (UI pede o alvo direto).
- **Recomendação:** (A) restrito — listagem nunca é fonte de decisão (F4-03 D5);
  authorize continua a única proteção.
- **Justificativa:** evita vazar inventário de confidencial na listagem.
- **Riscos:** (B) UX pior; (A) vazar existência → listagem exige capability de
  concessão.
- **Impacto:** superfície auxiliar.
- **Dependências:** F4-03 D5, D8.

### D19 — Beneficiário: membership/user_profile vs colaborador

- **Problema:** quem recebe o grant.
- **Alternativas:** (A) user_profile via membership (recomendado — cobre ADMIN
  sem collaborator, F4-01 D17); (B) colaborador vinculado.
- **Recomendação:** (A), com resolução colaborador quando necessário.
- **Justificativa:** F4-01 D17 e F4-02 (vínculo membership→collaborator).
- **Riscos:** (B) exclui ADMIN sem collaborator.
- **Impacto:** chave do grant; providers.
- **Dependências:** F4-01 D17, F4-02.

### D20 — Schema futuro: 1 tabela × tabela+eventos; unicidade

- **Problema:** forma do armazenamento futuro (sem migration agora) e
  unicidade.
- **Alternativas:** (A) linha de estado + eventos append-only separados
  (recomendado, espelha F3-09); (B) tabela única com histórico em linha;
  (C) só eventos deriváveis.
- **Recomendação:** (A), com unicidade que impeça dois grants ativos
  "equivalentes" conflitantes (chave única por (beneficiário, capability,
  target, janela aberta) quando aplicável) e eventos imutáveis.
- **Justificativa:** auditoria fiel + leitura simples; padrão F3-09.
- **Riscos:** (B) perde append-only; (C) reconstrução frágil.
- **Impacto:** F4-08 (policies), D16.
- **Dependências:** §10.2, D16, F4-08.

## 19. Questões para validação (consolidadas para revisão única)

> Questões de negócio/ambiguidade que **dependem de validação**. Quando também
> são arquiteturais, estão em D1–D20. O desenho pode ser concluído com estas
> abertas; elas serão revisadas junto com as decisões.

- **Q1 — O que é "conteúdo confidencial" no Virtus?** Contexto: não há
  classificação (§2.2). Por que: todo o desenho (D7/D8/D9) depende da
  definição do piloto. Alternativas: (a) avaliações/feedbacks de terceiros
  (notas, comentários, votos); (b) observações; (c) relatórios; (d) flag futura
  por recurso. Recomendação: começar por avaliação/feedback de ciclo
  (conteúdo de terceiros) como domínio-piloto. Impacto/risco: definir amplo
  demais = wildcard; estreito demais = fase pouco exercitada. Depende: §4, D7/D9.
- **Q2 — Existe papel de "administrador de acesso" hoje operando (allowlist
  INVITE_ADMIN_USER_IDS)?** Por que: definir quem exercerá a capability D3 no
  piloto. Alternativas: pessoa da allowlist atual × role `admin` futura ×
  concedentes dedicados. Recomendação: manter allowlist atual como origem
  transitória somente para testes, sem criar vínculo definitivo.
- **Q3 — O que é o "baseline de audit" citado na Issue #93?** Contexto: não
  consta em nenhum doc do repo (grep). Por que: a Issue pede "registrar
  leituras/ações sensíveis conforme baseline de audit". Alternativas: (a) o
  conjunto de eventos append-only atuais (histórico de metas/observações/ciclos
  + sucessão F3-09); (b) trilha nova de leitura sensível; (c) definir na F4-06.
  Recomendação: tratar como (c), alinhado a D12, e documentar a interpretação.
- **Q4 — Leituras sensíveis sob autorização NORMAL geram evento de auditoria?**
  (baseline de audit; ver D12). Recomendação preliminar: somente consumo de C
  obrigatório; leitura normal sensível é questão aberta por volume/custo.
- **Q5 — Concessão é ato individual ou existe hierarquia de aprovação
  (dupla)?** (ver D1/D2). Depende da operação real; sem resposta, D2=(C) com
  lista de domínios sensíveis fica pendente.
- **Q6 — Vocabulário de capabilities: qual a fonte soberana (catálogo SQL de
  21 × engine de 33)?** (ver §2.2/§17.2/D8). Recomendação preliminar: engine;
  alinhamento futuro do catálogo. A allowlist de exceção não pode ser definida
  sobre dois vocabulários.
- **Q7 — Alguma necessidade real da F4-06 exige "ver tudo" (full access)?**
  Se sim, pertence à F4-07/Pilot Full Access e deve ser registrada aqui como
  requisito para lá — nunca implementada nesta fase (§12).
- **Q8 — O grant excepcional pode ser concedido para capacidade de ESCRITA em
  conteúdo confidencial em algum cenário (ex.: correção administrativa)?**
  Recomendação: não nesta fase (D15); se o negócio exigir, vira decisão
  separada com regras de domínio.

## 20. Resumo para revisão (o que precisa ser fechado)

Para tornar este documento o contrato arquitetural da F4-06, a revisão deve
fechar **D1–D20** e responder **Q1–Q8**. Após fechamento, a implementação
futura entregará: core testável (`ExceptionalGrantProvider` + allowlist de
exceção + eventos de auditoria em memória), integração da origem C no engine
(§6) e atualização deste documento com a seção final de implementação — sempre
sem migration/RLS/DEFINER e sem antecipar F4-07/F4-08.
