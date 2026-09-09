# F4-10 — Matriz de rastreabilidade da validação integrada (Issue #97)

> **Status: validação EXECUTADA.** Gate de saída da Fase 4.
> Base: `main` `fb891bd7932651686289e3be37db88c69140105d`.
> Branch: `feat/issue-97-f4-10-integrated-authorization-validation`.
> PR de implementação **`Closes #97`** — **sem merge**.

## 1. Método e escopo

A F4-10 **não cria regra nova** (D1): ela prova, de forma integrada e
adversarial, que F4-01…F4-09 funcionam juntas e fail-closed. A cobertura usa o
princípio D11 — um mesmo teste pode evidenciar vários IDs; cada ID P0/P1 tem
ponteiro rastreável de execução. Fixtures 100% sintéticas (D9).

Legenda de evidência:

| Arquivo | Cobertura |
|---|---|
| `src/authorization/policyEngine/policyEngine.test.ts` | pipeline do engine (PIPE/CAP/SCOPE/PE) |
| `src/authorization/providers/f4-04-core.test.ts` | hierarquia/positions (HIER) |
| `src/authorization/providers/f4-05-core.test.ts` | temporary responsibility (TEMP) |
| `src/authorization/providers/f4-06-core.test.ts` | acesso excepcional C (EXC) |
| `src/authorization/providers/f4-07-core.test.ts` | Pilot Full Access D (PILOT) |
| `src/authorization/authorizationPolicy.test.ts` | domínios funcionais (EVAL/OBS/GOAL/CYCLE/REPORT/HIST/REV) |
| `src/authorization/f4-09-functional.test.ts` | mundo funcional sem cargo (EVAL/SCOPE/GOAL/OBS/REV/REPORT) |
| `src/authorization/f4-10-integrated.test.ts` | **nova** validação transversal/adversarial |
| `src/services/*.test.ts` | enforcement no service (authorize antes da mutação) |
| `supabase/validacao/01-cenario-f4-08.sql` + `02-validar-f4-08.sql` | tenant/RLS/grants (TENANT) |
| `supabase/validacao/03-validar-f4-08-mutacoes.sql` | mutation/security regression (MUT) |

## 2. Resultado consolidado (gate)

| Item | Resultado |
|---|---|
| Testes unitários/engine/provider/service/integration | **PASS** (ver §6) |
| Supabase local F4-08 (tenant/RLS/grants + mutações) | **PASS** (ver §6) |
| Ausência de autorização runtime por `funcao`/`cargo` | **PASS** (ver §7) |
| Achados CRÍTICO/ALTO de autorização | **nenhum** |
| Veredito do gate da Fase 4 | **APROVADO PARA ENCERRAR FASE 4** |

## 3. Matriz por família

### PIPE — precedência do pipeline soberano

| ID | Resultado | Evidência |
|---|---|---|
| PIPE-001 | PASS | `policyEngine.test.ts` "cross-tenant ⇒ DENY (NOT_FOUND)"; `f4-10` "PIPE-001/ATTACK-006" |
| PIPE-002 | PASS | `f4-07-core.test.ts` "23/24 target confidencial + D válido + C inexistente ⇒ DENY" |
| PIPE-003 | PASS | `f4-09` "SELF lê a própria avaliação somente em CONCLUIDA"; `f4-10` "PIPE-003/EVAL-002" |
| PIPE-004 | PASS | `f4-05-core.test.ts` "3. substituição expirada = DENY" |
| PIPE-005 | PASS | `policyEngine.test.ts` "ADMIN sem capability confidencial ⇒ DENY"; "ORGANIZATION sem capability" |
| PIPE-006 | PASS | `f4-10` "PIPE-006/CAP-005"; `f4-06` "7b"; `f4-07` "21"; `f4-05` "24" |
| PIPE-007 | PASS | `policyEngine.test.ts` "membership disabled ⇒ DENY"; `f4-05` "21" |

### TENANT / F4-08 (Supabase local — sem mocks)

| ID | Resultado | Evidência |
|---|---|---|
| TENANT-001…015 | PASS | `supabase/validacao/01-cenario-f4-08.sql` + `02-validar-f4-08.sql` (57 checagens RLS/grants/tenant) |

### CAP — capabilities (F4-01 + Q1 F4-09)

| ID | Resultado | Evidência |
|---|---|---|
| CAP-001 | PASS | `policyEngine.test.ts` (capability inexistente ⇒ CAPABILITY_MISSING) |
| CAP-002 | PASS | `f4-09` "capability removida ⇒ DENY imediato"; `f4-10` "REV-003" |
| CAP-003 | PASS | `f4-10` "CAP-003/HIER-008/ATTACK"; `policyEngine.test.ts` "engine não consulta cargo/job_role"; §7 |
| CAP-004 | PASS | `policyEngine.test.ts` "o mapa legado existe apenas como artefato documental"; `authorizationPolicy.test.ts` "colapsa evaluation.edit.*" |
| CAP-005 | PASS | `f4-10` "PIPE-006/CAP-005"; `policyEngine.test.ts` "capability × target" |
| CAP-006 | PASS | `policyEngine.test.ts` "ADMIN sem capability confidencial ⇒ DENY" |

### SCOPE / F4-02

| ID | Resultado | Evidência |
|---|---|---|
| SCOPE-001 | PASS | `policyEngine.test.ts` (SELF) |
| SCOPE-002 | PASS | `policyEngine.test.ts` "SELF sobre terceiro ⇒ DENY" |
| SCOPE-003 | PASS | `f4-09` "coordenador acessa seu DIRECT_REPORTS" |
| SCOPE-004 | PASS | `policyEngine.test.ts` "DESCENDANTS fora da árvore ⇒ DENY" |
| SCOPE-005 | PASS | `f4-09` "gerente acessa os descendentes pelo scope DESCENDANTS" |
| SCOPE-006 | PASS | `policyEngine.test.ts` "DESCENDANTS fora da árvore"; `f4-04-core` |
| SCOPE-007/008 | PASS | `f4-04-core.test.ts` (organizational unit) |
| SCOPE-009 | PASS | `policyEngine.test.ts` "ORGANIZATION sem capability ⇒ DENY" |
| SCOPE-010 | PASS | `f4-09` "colegiado acessa somente o alvo ASSIGNED" |
| SCOPE-011 | PASS | `f4-10` "SCOPE-011/SCOPE-012/GOAL-004"; `f4-09` "colegiado ... não vira hierarquia" |
| SCOPE-012 | PASS | idem |
| SCOPE-013 | PASS | `f4-09` "observação de terceiro: SELF = DENY" |
| SCOPE-014 | PASS | `f4-09` "ID/sujeito manipulado ⇒ TARGET_INVALID" |
| SCOPE-015 | PASS | `f4-10` "REV-010: mudança de gestor"; `f4-04-core` |
| SCOPE-016 | PASS | `f4-10` "PIPE-003/EVAL-002" |

### PE — Policy Engine / F4-03

| ID | Resultado | Evidência |
|---|---|---|
| PE-001 | PASS | `policyEngine.test.ts` "authorize lança erro público F0-05" (positivo); `authorizationPolicy.test.ts` "authorize não lança quando permitida" |
| PE-002 | PASS | `authorizationPolicy.test.ts` "authorize lança AuthorizationError tipado"; `policyEngine.test.ts` "authorize lança erro público" |
| PE-003 | PASS | `policyEngine.test.ts` "can devolve decisão estruturada sem lançar" |
| PE-004 | PASS | `policyEngine.test.ts` "listAllowedTargets é auxiliar, nunca substituto" |
| PE-005 | PASS | `src/services/cancelamentoCicloService.test.ts` (mutação exige authorize) |
| PE-006 | PASS | `f4-10` "PE-006/ATTACK-007 (TOCTOU)" |
| PE-007 | PASS | `f4-10` "PE-007/PE-011: domainState ausente ⇒ INDETERMINATE" |
| PE-008 | PASS | `f4-10` "PE-008/DISC-006"; `policyEngine.test.ts` "cross-tenant ⇒ NOT_FOUND" |
| PE-009 | PASS | `f4-10` "PE-008/DISC-006"; `policyEngine.test.ts` "cross-tenant ⇒ NOT_FOUND" |
| PE-010 | PASS | `policyEngine.test.ts` "contexto temporal" |
| PE-011 | PASS | `f4-10` "PE-007/PE-011"; `policyEngine.test.ts` "estado do domínio ausente ⇒ DENY" |

### HIER — hierarquia / F4-04

| ID | Resultado | Evidência |
|---|---|---|
| HIER-001…010 | PASS | `src/authorization/providers/f4-04-core.test.ts` (17 testes: DIRECT_REPORTS/DESCENDANTS/vacancy/colegiado/positions/cargo) |

### TEMP — substituição temporária / F4-05

| ID | Resultado | Evidência |
|---|---|---|
| TEMP-001…009 | PASS | `src/authorization/providers/f4-05-core.test.ts` (32 testes: vigência/allowlist/titular/raiz/ASSIGNED/cross-tenant/fail-closed) |

### EXC — acesso excepcional C / F4-06

| ID | Resultado | Evidência |
|---|---|---|
| EXC-001…013 | PASS | `src/authorization/providers/f4-06-core.test.ts` (grant/target/ciclo/janela/revogação/auditoria/wildcard/listAllowedTargets/confidencialidade) |

### PILOT — Pilot Full Access D / F4-07

| ID | Resultado | Evidência |
|---|---|---|
| PILOT-001…013 | PASS | `src/authorization/providers/f4-07-core.test.ts` (dev/profile/capabilities/confidencial/revogação/30dias/auditoria/cross-tenant) |

### EVAL — avaliações (F4-09 §15.1)

| ID | Resultado | Evidência |
|---|---|---|
| EVAL-001 | PASS | `f4-09` "funcionário A não lê avaliação de B" |
| EVAL-002 | PASS | `f4-09` "SELF lê a própria avaliação somente em CONCLUIDA"; `f4-10` "PIPE-003/EVAL-002" |
| EVAL-003 | PASS | `f4-09` (concluída ALLOW) |
| EVAL-004 | PASS | `authorizationPolicy.test.ts` "mantém cancelada consultável e bloqueada" + confidencialidade |
| EVAL-005 | PASS | `authorizationPolicy.test.ts` "histórico não concede autorização: ex-gestor DENY e gestor atual ALLOW" |
| EVAL-006 | PASS | idem |
| EVAL-007 | PASS | `f4-09` "gerente acessa os descendentes"; `policyEngine.test.ts` "DESCENDANTS fora da árvore" |
| EVAL-008 | PASS | `authorizationPolicy.test.ts` "nega as capabilities de avaliação fora do escopo" |
| EVAL-009 | PASS | `f4-09` "colegiado acessa somente o alvo ASSIGNED" |
| EVAL-010/011/012 | PASS | `f4-09` "ID/sujeito manipulado ⇒ TARGET_INVALID" |
| EVAL-013 | PASS | `src/services/feedbackStorage.test.ts` + `cancelamentoAvaliacaoService.test.ts` (authorize) |
| EVAL-014 | PASS | `authorizationPolicy.test.ts` (cancelar/reabrir respeita estado); `cancelamento/reaberturaAvaliacaoService.test.ts` |

### OBS — observações (F4-09 §15.2)

| ID | Resultado | Evidência |
|---|---|---|
| OBS-001 | PASS | `src/services/observacaoStorage.test.ts` + `f4-09` "observação de terceiro: SELF = DENY" |
| OBS-002 | PASS | `src/services/observacaoStorage.test.ts` (comunicada) |
| OBS-003 | PASS | `f4-09` "observação de terceiro: SELF = DENY" |
| OBS-004 | PASS | `authorizationPolicy.test.ts` (observation.edit/delete); `observacaoStorage.test.ts` |
| OBS-005 | PASS | `src/services/observacaoStorage.test.ts` (soft delete) |
| OBS-006 | PASS | `src/services/observacaoStorage.test.ts` (histórico) |
| OBS-007 | PASS | `authorizationPolicy.test.ts` "restringe capabilities de observação ao ciclo" |

### GOAL — metas (F4-09 §15.3)

| ID | Resultado | Evidência |
|---|---|---|
| GOAL-001 | PASS | `authorizationPolicy.test.ts` "aplica capabilities de metas próprias" |
| GOAL-002 | PASS | `authorizationPolicy.test.ts` "nega todas as mutações próprias sobre meta de outro colaborador" |
| GOAL-003 | PASS | `f4-09` "metas: aprovação só no alcance"; `authorizationPolicy.test.ts` "papéis de aprovação" |
| GOAL-004 | PASS | `f4-10` "SCOPE-011/SCOPE-012/GOAL-004"; `authorizationPolicy.test.ts` "coordenador que participa somente do colegiado" |
| GOAL-005 | PASS | `policyEngine.test.ts` "GERENTE também gerencia metas próprias (decisão não consulta cargo)" |
| GOAL-006 | PASS | `authorizationPolicy.test.ts` "restringe aprovação em ciclo ENCERRADO/CANCELADO" |

### CYCLE — ciclos (F4-09 §15.4)

| ID | Resultado | Evidência |
|---|---|---|
| CYCLE-001 | PASS | `f4-09` "ciclo (Q7): mutação administrativa exige capability E domainState" |
| CYCLE-002 | PASS | `authorizationPolicy.test.ts` "autoriza cancelamento de ciclo ativo somente para gerente" |
| CYCLE-003 | PASS | `f4-09` "ciclo (Q7)" (sem estado DENY) |
| CYCLE-004 | PASS | `f4-09` "ciclo (Q7)" (sem capability DENY) |

### REPORT — relatórios/agregações (D12 limit-then-aggregate)

| ID | Resultado | Evidência |
|---|---|---|
| REPORT-001 | PASS | `authorizationPolicy.test.ts` "mantém REPORT equivalente à regra pública do relatório" |
| REPORT-002 | PASS | `f4-10` "REPORT-003/004/DISC-002" + `f4-09` "listAllowedTargets limita o dataset" |
| REPORT-003 | PASS | `f4-10` "REPORT-003/004/DISC-002" |
| REPORT-004 | PASS | `authorizationPolicy.test.ts` "distingue colegiado no OPERATIONAL_TEAM e no REPORT" |
| REPORT-005 | PASS | `authorizationPolicy.test.ts` "mantém REPORT equivalente" |
| REPORT-006 | PASS | `policyEngine.test.ts` "ADMIN sem capability confidencial ⇒ DENY" |
| REPORT-007 | PASS | `authorizationPolicy.test.ts` "scopeCollaborators: report.read presente ⇒ somente targets ALLOW" |

### HIST — histórico (confidencialidade não diminui com o tempo)

| ID | Resultado | Evidência |
|---|---|---|
| HIST-001 | PASS | `f4-09` "funcionário A não lê avaliação de B" |
| HIST-002 | PASS | `authorizationPolicy.test.ts` "histórico não concede autorização: ex-gestor DENY" |
| HIST-003 | PASS | `authorizationPolicy.test.ts` "histórico não concede ... gestor atual ALLOW" (novo gestor sem relação prévia) |
| HIST-004 | PASS | `f4-04-core.test.ts` + `f4-05` "contexto congelado F3-08/F3-09" |
| HIST-005 | PASS | `f4-05-core.test.ts` "27. contexto congelado não é sobrescrito" |
| HIST-006 | PASS | `authorizationPolicy.test.ts` "histórico não concede autorização" |
| HIST-007 | PASS | idem |
| HIST-008 | PASS | `f4-09` "ID manipulado ⇒ TARGET_INVALID" |

### DISC — information disclosure

| ID | Resultado | Evidência |
|---|---|---|
| DISC-001 | PASS | `f4-09` "ID/sujeito manipulado ⇒ TARGET_INVALID" |
| DISC-002 | PASS | `f4-10` "REPORT-003/004/DISC-002" |
| DISC-003 | PASS | `f4-09` "listAllowedTargets limita o dataset" |
| DISC-004 | PASS | `policyEngine.test.ts` "cross-tenant ⇒ NOT_FOUND" |
| DISC-005 | PASS | `authorizationPolicy.test.ts` "scopeCollaborators: report.read presente ⇒ somente targets ALLOW" |
| DISC-006 | PASS | `f4-10` "PE-008/DISC-006"; `policyEngine.test.ts` "cross-tenant ⇒ NOT_FOUND" |
| DISC-007 | PASS | Q3 fechada: timing não-bloqueador (documentado no desenho §25.3) |

### REV — revogação / stale state

| ID | Resultado | Evidência |
|---|---|---|
| REV-001 | PASS | `policyEngine.test.ts` "membership disabled ⇒ DENY" |
| REV-002 | PASS | `policyEngine.test.ts` "profile disabled ⇒ DENY" |
| REV-003 | PASS | `f4-10` "REV-003"; `f4-09` "capability removida ⇒ DENY imediato" |
| REV-004 | PASS | `f4-06`/`f4-07` (access role inativada — access_roles) |
| REV-005 | PASS | `f4-05-core.test.ts` (scope assignment) |
| REV-006 | PASS | `f4-05-core.test.ts` "3. substituição expirada"; "4. retorno antecipado" |
| REV-007 | PASS | `f4-06-core.test.ts` "4. grant revogado ⇒ DENY" |
| REV-008 | PASS | `f4-07-core.test.ts` "42/43 revogação com efeito imediato" |
| REV-009 | PASS | `f4-10` "REV-009"; `f4-09` "revogação: remover o colegiado ⇒ DENY" |
| REV-010 | PASS | `f4-10` "REV-010: mudança de gestor" |
| REV-011 | PASS | `authorizationPolicy.test.ts` "bloqueia novas avaliações ... após desligamento" |

### ATTACK — adversariais

| ID | Resultado | Evidência |
|---|---|---|
| ATTACK-001 | PASS | `f4-09` "ID/sujeito manipulado ⇒ TARGET_INVALID" |
| ATTACK-002 | PASS | `f4-10` (enforcement fail-closed) + `f4-09` |
| ATTACK-003 | PASS | `src/services/*.test.ts` (service é a porta: authorize) |
| ATTACK-004 | PASS | `policyEngine.test.ts` "listAllowedTargets é auxiliar" |
| ATTACK-005 | PASS | `f4-10` "PIPE-001/ATTACK-006" |
| ATTACK-006 | PASS | idem |
| ATTACK-007 | PASS | `f4-10` "PE-006/ATTACK-007 (TOCTOU)" |
| ATTACK-008 | PASS | `f4-09` "ciclo (Q7)" (domainState soberano) |
| ATTACK-009 | PASS | `f4-10` "ATTACK-010" + service tests (authorize no serviço) |
| ATTACK-010 | PASS | `f4-10` "REV-003" |
| ATTACK-011 | PASS | `f4-09` "ID/sujeito manipulado" |
| ATTACK-012 | PASS | `f4-07-core.test.ts` "23/24 target confidencial + D ⇒ DENY" |
| ATTACK-013 | PASS | `f4-06-core.test.ts` (C não aparece em listAllowedTargets) |
| ATTACK-014 | PASS | `policyEngine.test.ts` "ADMIN sem capability confidencial ⇒ DENY" |
| ATTACK-015 | PASS | `f4-05-core.test.ts` "3. substituição expirada" |
| ATTACK-016 | PASS | `authorizationPolicy.test.ts` "histórico não concede ... ex-gestor DENY" |

### POS — positivos (hardening não torna o produto inutilizável)

| ID | Resultado | Evidência |
|---|---|---|
| POS-001 | PASS | `f4-09` "gerente acessa os descendentes" |
| POS-002 | PASS | `f4-09` "SELF lê a própria avaliação somente em CONCLUIDA" |
| POS-003 | PASS | `f4-10` "POS-003/POS-004"; `f4-09` "coordenador acessa seu DIRECT_REPORTS" |
| POS-004 | PASS | `f4-10` "POS-003/POS-004"; `f4-09` "colegiado acessa somente o alvo ASSIGNED" |
| POS-005 | PASS | `f4-06-core.test.ts` "1. grant válido ⇒ ALLOW excepcional" |
| POS-006 | PASS | `f4-07-core.test.ts` "1/28 grant válido em development ⇒ ALLOW" |
| POS-007 | PASS | `f4-05-core.test.ts` "1. substituição vigente concede" |
| POS-008 | PASS | `supabase/validacao/02-validar-f4-08.sql` (TENANT-006 multi-membership) |
| POS-009 | PASS | `authorizationPolicy.test.ts` "mantém criação de avaliação e observação" |
| POS-010 | PASS | `authorizationPolicy.test.ts` "caracteriza os papéis de aprovação" |

### MUT — mutation/security regression (schema guard)

| ID | Resultado | Evidência |
|---|---|---|
| MUT-* | PASS | `supabase/validacao/03-validar-f4-08-mutacoes.sql` (8 mutation tests) + `supabase/validacao/02-validar-f4-08.sql` (57 checagens) |

## 4. Ausência estática de autorização por cargo (regra crítica)

```bash
grep -nE "funcao ===|funcao !==|\.funcao ===|\.funcao !==|actor\.funcao|\.cargo ===|job_role" src/authorization
```

Resultado: em `src/authorization`, `funcao`/`cargo` NÃO aparecem como fonte de
ALLOW/DENY. Ocorrências remanescentes são (1) merge de contexto para UX
(`authorizationPolicy.ts` `resolverAtor`), (2) comentários documentais do
`legacyMap.ts`, e (3) regra de DOMÍNIO sobre o AVALIADO
(`funcaoUsaEstruturaAvaliacaoAnalista`) — nunca autorização do ator. A ausência
também é provada comportamentalmente por `policyEngine.test.ts` ("engine não
consulta cargo/job_role"), `f4-09` ("alterar funcao/cargo ... NÃO concede") e
`f4-10` ("CAP-003/HIER-008/ATTACK").

## 5. Achados

Nenhum achado CRÍTICO/ALTO de autorização, confidencialidade, tenant isolation,
revogação, privilege escalation ou bypass do Policy Engine. Nenhuma regra nova
foi criada; nenhuma correção de implementação foi necessária nesta validação.

## 6. Execução

- `npm test` — ver total no relatório do PR.
- `npm run build` / `npm run lint` / `git diff --check` — ver relatório do PR.
- Supabase local F4-08: `supabase db reset` + `01-cenario-f4-08.sql` +
  `02-validar-f4-08.sql` (57 PASS) + `03-validar-f4-08-mutacoes.sql` (8 mutações).

## 7. Veredito final

**APROVADO PARA ENCERRAR FASE 4** — todos os cenários P0 e P1 têm evidência
rastreável; tenant isolation, confidencialidade, histórico, revogação, SELF,
ADMIN-não-superuser, D-não-confidencial, C-sem-wildcard, ASSIGNED-sem-hierarquia
e limit-then-aggregate estão validados; sem autorização runtime por cargo.
