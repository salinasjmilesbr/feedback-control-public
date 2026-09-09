# F4-10 — Matriz de rastreabilidade da validação integrada (Issue #97)

> **Status: validação EXECUTADA.** Gate de saída da Fase 4.
> Base: `main` `fb891bd7932651686289e3be37db88c69140105d`.
> Branch: `feat/issue-97-f4-10-integrated-authorization-validation`.
> PR de implementação **`Closes #97`** — **sem merge**.

## 1. Método e priorização

A F4-10 **não cria regra nova** (D1): prova que F4-01…F4-09 funcionam juntas e
fail-closed (D2/D11/D12). Cada ID tem linha rastreável com prioridade, resultado
e evidência concreta (arquivo + teste/check). Fixtures 100% sintéticas (D9).

**Prioridade por ID** (conforme §23/D12 do desenho):

- **P0** (bloqueadores): PIPE-*, TENANT-*, REV-*, EXC-*, PILOT-*, ATTACK-*,
  DISC-* de confidencial e MUT-* (schema guard).
- **P1** (regras centrais): CAP-*, SCOPE-*, PE-*, HIER-*, TEMP-*, EVAL-*, OBS-*,
  GOAL-*, CYCLE-*, REPORT-*, HIST-*, POS-*.
- **P2** (hardening/completude): DISC-* secundário (DISC-007 timing).

Legenda de arquivos:

| Arquivo | Famílias |
|---|---|
| `src/authorization/policyEngine/policyEngine.test.ts` | PIPE/CAP/SCOPE/PE |
| `src/authorization/providers/f4-04-core.test.ts` | HIER/SCOPE |
| `src/authorization/providers/f4-05-core.test.ts` | TEMP |
| `src/authorization/providers/f4-06-core.test.ts` | EXC |
| `src/authorization/providers/f4-07-core.test.ts` | PILOT |
| `src/authorization/authorizationPolicy.test.ts` | EVAL/OBS/GOAL/CYCLE/REPORT/HIST/REV |
| `src/authorization/f4-09-functional.test.ts` | EVAL/SCOPE/GOAL/OBS/REV/REPORT |
| `src/authorization/f4-10-integrated.test.ts` | PIPE/PE/REV/ATTACK/REPORT/DISC/CAP |
| `src/services/*.test.ts` | enforcement (authorize) |
| `supabase/validacao/0*-f4-08*.sql` | TENANT/MUT (RLS/grants/tenant) |

## 2. Matriz por ID

### PIPE — precedência do pipeline (P0)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| PIPE-001 | P0 | PASS | `policyEngine.test.ts` "cross-tenant => DENY com público NOT_FOUND"; `supabase/validacao/02-validar-f4-08.sql` (TENANT-001..004) |
| PIPE-002 | P0 | PASS | `f4-07-core.test.ts` "23/24. target confidencial + D válido + C inexistente ⇒ DENY (D não é fallback)" |
| PIPE-003 | P0 | PASS | `f4-09-functional.test.ts` "SELF lê a própria avaliação somente em CONCLUIDA"; `f4-10-integrated.test.ts` "PIPE-003/EVAL-002" |
| PIPE-004 | P0 | PASS | `f4-05-core.test.ts` "3. substituição expirada = DENY" |
| PIPE-005 | P0 | PASS | `policyEngine.test.ts` "ADMIN sem capability confidencial => DENY (CAPABILITY_MISSING)" |
| PIPE-006 | P0 | PASS | `f4-10-integrated.test.ts` "PIPE-006/CAP-005"; `f4-04-core.test.ts` "engine nega capability incompatível com target (TARGET_INCOMPATIBLE)" |
| PIPE-007 | P0 | PASS | `policyEngine.test.ts` "membership disabled => DENY (MEMBERSHIP_INVALID)" |

### TENANT / F4-08 (P0)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| TENANT-001 | P0 | PASS | `supabase/validacao/02-validar-f4-08.sql` (RLS cross-tenant SELECT) |
| TENANT-002 | P0 | PASS | idem (RLS/grants DML) |
| TENANT-003 | P0 | PASS | idem (SELECT por ID direto) |
| TENANT-004 | P0 | PASS | idem (organizationId manipulado) |
| TENANT-005 | P0 | PASS | idem (FK cross-tenant constraint) |
| TENANT-006 | P0 | PASS | idem (multi-membership A+B) |
| TENANT-007 | P0 | PASS | idem (sem membership) |
| TENANT-008 | P0 | PASS | idem (membership inativa) |
| TENANT-009 | P0 | PASS | idem (profile inativo) |
| TENANT-010 | P0 | PASS | idem (anon) |
| TENANT-011 | P0 | PASS | idem (SELECT ok / DML DENY) |
| TENANT-012 | P0 | PASS | idem (security tables fechadas) |
| TENANT-013 | P0 | PASS | idem (audit/history sem rewrite) |
| TENANT-014 | P0 | PASS | idem (TRUNCATE/TRIGGER/REFERENCES guard) |
| TENANT-015 | P0 | PASS | idem (membership revogada ⇒ efeito imediato) |

### CAP — capabilities (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| CAP-001 | P1 | PASS | `policyEngine.test.ts` "scope sem capability => DENY (CAPABILITY_MISSING)" |
| CAP-002 | P1 | PASS | `f4-09-functional.test.ts` "capability removida do binding ⇒ DENY imediato"; `f4-10-integrated.test.ts` "REV-003" |
| CAP-003 | P1 | PASS | `f4-10-integrated.test.ts` "CAP-003/HIER-008/ATTACK"; `policyEngine.test.ts` "engine não consulta cargo/job_role (comportamental)"; §4 |
| CAP-004 | P1 | PASS | `policyEngine.test.ts` "o mapa legado existe apenas como artefato documental"; `authorizationPolicy.test.ts` "colapsa evaluation.edit.* em evaluation.write" |
| CAP-005 | P1 | PASS | `f4-10-integrated.test.ts` "PIPE-006/CAP-005"; `f4-04-core.test.ts` "engine nega capability incompatível com target" |
| CAP-006 | P1 | PASS | `policyEngine.test.ts` "ADMIN sem capability confidencial => DENY (CAPABILITY_MISSING)" |

### SCOPE (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| SCOPE-001 | P1 | PASS | `policyEngine.test.ts` "capability + scope + relação + estado válidos => ALLOW" |
| SCOPE-002 | P1 | PASS | `policyEngine.test.ts` "SELF sobre terceiro => DENY (SCOPE_INSUFFICIENT)" |
| SCOPE-003 | P1 | PASS | `f4-09-functional.test.ts` "coordenador acessa seu DIRECT_REPORTS e não acessa quem está fora" |
| SCOPE-004 | P1 | PASS | `policyEngine.test.ts` "DESCENDANTS fora da árvore => DENY" |
| SCOPE-005 | P1 | PASS | `f4-09-functional.test.ts` "gerente acessa os descendentes pelo scope DESCENDANTS" |
| SCOPE-006 | P1 | PASS | `f4-04-core.test.ts` "DESCENDANTS: coordenação paralela não é alcançada pelo outro coordenador" |
| SCOPE-007 | P1 | PASS | `f4-04-core.test.ts` (organizational unit — occupants) |
| SCOPE-008 | P1 | PASS | `f4-04-core.test.ts` "collaborator fora da árvore não pertence ao scope" |
| SCOPE-009 | P1 | PASS | `policyEngine.test.ts` "ORGANIZATION sem capability => DENY (CAPABILITY_MISSING)" |
| SCOPE-010 | P1 | PASS | `f4-09-functional.test.ts` "colegiado acessa somente o alvo ASSIGNED e não vira hierarquia" |
| SCOPE-011 | P1 | PASS | `f4-10-integrated.test.ts` "SCOPE-011/SCOPE-012/GOAL-004" |
| SCOPE-012 | P1 | PASS | idem; `f4-04-core.test.ts` "responsabilidade de A não vira wildcard para B" |
| SCOPE-013 | P1 | PASS | `f4-09-functional.test.ts` "observação de terceiro: SELF = DENY" |
| SCOPE-014 | P1 | PASS | `f4-09-functional.test.ts` "ID/sujeito manipulado (inexistente) ⇒ DENY/TARGET_INVALID" |
| SCOPE-015 | P1 | PASS | `f4-10-integrated.test.ts` "REV-010: mudança de gestor" |
| SCOPE-016 | P1 | PASS | `f4-10-integrated.test.ts` "PIPE-003/EVAL-002" |

### PE — Policy Engine (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| PE-001 | P1 | PASS | `authorizationPolicy.test.ts` "authorize não lança quando a decisão é permitida" |
| PE-002 | P1 | PASS | `authorizationPolicy.test.ts` "authorize lança AuthorizationError tipado quando negado"; `policyEngine.test.ts` "authorize lança erro público F0-05" |
| PE-003 | P1 | PASS | `policyEngine.test.ts` "can devolve decisão estruturada sem lançar" |
| PE-004 | P1 | PASS | `policyEngine.test.ts` "listAllowedTargets é auxiliar (filtra), nunca substituto de authorize()" |
| PE-005 | P1 | PASS | `cancelamentoCicloService.test.ts` "rejeita não gerente e motivo vazio sem modificar o ciclo" |
| PE-006 | P1 | PASS | `f4-10-integrated.test.ts` "PE-006/ATTACK-007 (TOCTOU)" |
| PE-007 | P1 | PASS | `f4-10-integrated.test.ts` "PE-007/PE-011: domainState ausente ⇒ INDETERMINATE" |
| PE-008 | P1 | PASS | `f4-10-integrated.test.ts` "PE-008/DISC-006"; `policyEngine.test.ts` "cross-tenant => DENY com público NOT_FOUND" |
| PE-009 | P1 | PASS | `policyEngine.test.ts` "cross-tenant => DENY com público NOT_FOUND" |
| PE-010 | P1 | PASS | `policyEngine.test.ts` "contexto temporal/histórico é usado pela relação" |
| PE-011 | P1 | PASS | `policyEngine.test.ts` "estado do domínio ausente => DENY (INDETERMINATE — fail-closed)" |

### HIER — hierarquia (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| HIER-001 | P1 | PASS | `f4-04-core.test.ts` "DIRECT_REPORTS: subordinados diretos (positions + occupants), vaga sem collaborator" |
| HIER-002 | P1 | PASS | `f4-04-core.test.ts` "DESCENDANTS: árvore completa, atravessa vaga intermediária e deduplica collaborator" |
| HIER-003 | P1 | PASS | `f4-04-core.test.ts` "multi-positions: união de todas as positions do ator" |
| HIER-004 | P1 | PASS | `f4-04-core.test.ts` "DIRECT_REPORTS: ... vaga sem collaborator" |
| HIER-005 | P1 | PASS | `f4-04-core.test.ts` "DESCENDANTS: árvore completa, atravessa vaga intermediária" |
| HIER-006 | P1 | PASS | `f4-04-core.test.ts` "colegiado permite somente o membro atribuído" |
| HIER-007 | P1 | PASS | `f4-04-core.test.ts` "multi-positions: união de todas as positions do ator" |
| HIER-008 | P1 | PASS | `f4-10-integrated.test.ts` "CAP-003/HIER-008/ATTACK"; `policyEngine.test.ts` "engine não consulta cargo/job_role" |
| HIER-009 | P1 | PASS | `f4-04-core.test.ts` "snapshot/ciclo é soberano (outro ciclo => sem atribuição)" |
| HIER-010 | P1 | PASS | `f4-04-core.test.ts` "ator sem occupation: conjunto vazio" |

### TEMP — substituição temporária (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| TEMP-001 | P1 | PASS | `f4-05-core.test.ts` "1. substituição vigente concede capability permitida" |
| TEMP-002 | P1 | PASS | `f4-05-core.test.ts` "2. substituição futura = DENY" |
| TEMP-003 | P1 | PASS | `f4-05-core.test.ts` "3. substituição expirada = DENY" |
| TEMP-004 | P1 | PASS | `f4-05-core.test.ts` "4. retorno antecipado (valid_to atualizado) reflete imediatamente" |
| TEMP-005 | P1 | PASS | `f4-05-core.test.ts` "8. titular mantém autorização própria durante a substituição" |
| TEMP-006 | P1 | PASS | `f4-05-core.test.ts` "7. substituto não herda scopes/capabilities do titular" |
| TEMP-007 | P1 | PASS | `f4-05-core.test.ts` "26. contexto congelado F3-08/F3-09 não é sobrescrito por temporary" |
| TEMP-008 | P1 | PASS | `f4-05-core.test.ts` "28. ASSIGNED temporário não vira wildcard (correlação específica)" |
| TEMP-009 | P1 | PASS | `f4-05-core.test.ts` "15. autorizações próprias continuam válidas e independentes" |

### EXC — acesso excepcional C (P0)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| EXC-001 | P0 | PASS | `f4-06-core.test.ts` "19. A/B ALLOW + grant C existente ⇒ ALLOW normal, C não consumida, sem uso" |
| EXC-002 | P0 | PASS | `f4-06-core.test.ts` "16. conteúdo confidencial ⇒ C consultada (ALLOW excepcional)" |
| EXC-003 | P0 | PASS | `f4-06-core.test.ts` "28. allowlist é fechada: somente evaluation.read" |
| EXC-004 | P0 | PASS | `f4-06-core.test.ts` "6. target diferente ⇒ DENY" |
| EXC-005 | P0 | PASS | `f4-06-core.test.ts` "8. cycleId errado ⇒ DENY; cycleId ausente ⇒ DENY" |
| EXC-006 | P0 | PASS | `f4-06-core.test.ts` "1. grant válido ⇒ ALLOW excepcional" |
| EXC-007 | P0 | PASS | `f4-06-core.test.ts` "4. grant revogado ⇒ DENY"; "2. grant expirado ⇒ DENY" |
| EXC-008 | P0 | PASS | `f4-06-core.test.ts` "33. uso efetivo registrado somente quando C autoriza" |
| EXC-009 | P0 | PASS | `f4-06-core.test.ts` "30. concessão válida gera evento granted"; "31. revogação gera evento revoked" |
| EXC-010 | P0 | PASS | `f4-06-core.test.ts` "24. múltiplos grants aplicáveis ao mesmo pedido ⇒ DENY fail-closed" |
| EXC-011 | P0 | PASS | `f4-06-core.test.ts` "46. C NÃO participa de listAllowedTargets" |
| EXC-012 | P0 | PASS | `f4-06-core.test.ts` "27. capability não elegível (escrita) ⇒ DENY"; "38. target não elegível" |
| EXC-013 | P0 | PASS | `f4-06-core.test.ts` "49/50/51/52/54. cycleId ausente/diferente ⇒ NÃO aplicável" |

### PILOT — Pilot Full Access D (P0)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| PILOT-001 | P0 | PASS | `f4-07-core.test.ts` "29/30/31. ambiente: development elegível; homologation/production DENY" |
| PILOT-002 | P0 | PASS | `f4-07-core.test.ts` "12. profileVersion desconhecido ⇒ DENY" |
| PILOT-003 | P0 | PASS | `f4-07-core.test.ts` "14. capability fora do perfil ⇒ DENY"; "15. capability futura/nova ⇒ DENY" |
| PILOT-004 | P0 | PASS | `f4-07-core.test.ts` "1/28. grant válido em development ⇒ ALLOW pilot" |
| PILOT-005 | P0 | PASS | `f4-07-core.test.ts` "23/24. target confidencial + D válido + C inexistente ⇒ DENY" |
| PILOT-006 | P0 | PASS | `f4-07-core.test.ts` "4. grant revogado ⇒ DENY"; "42/43. revogação com efeito imediato" |
| PILOT-007 | P0 | PASS | `f4-07-core.test.ts` "3. grant expirado ⇒ DENY" |
| PILOT-008 | P0 | PASS | `f4-07-core.test.ts` "58. grant persistido com duração de 31 dias ⇒ não aplicável" |
| PILOT-009 | P0 | PASS | `f4-07-core.test.ts` "66. engine: grant malformado ⇒ DENY" |
| PILOT-010 | P0 | PASS | `f4-07-core.test.ts` "26/27. A/B ALLOW ⇒ D não consumido" |
| PILOT-011 | P0 | PASS | `f4-07-core.test.ts` "1/28. ... + uso"; auditoria origem `pilot:<grantId>` |
| PILOT-012 | P0 | PASS | `f4-07-core.test.ts` "8/8b. tenant diferente ⇒ DENY/CROSS_TENANT" |
| PILOT-013 | P0 | PASS | `f4-07-core.test.ts` "18/19/20. settings/segurança/concessão fora de D ⇒ DENY" |

### EVAL — avaliações (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| EVAL-001 | P1 | PASS | `f4-09-functional.test.ts` "funcionário A não lê avaliação de B" |
| EVAL-002 | P1 | PASS | `f4-09-functional.test.ts` "SELF lê a própria avaliação somente em CONCLUIDA" |
| EVAL-003 | P1 | PASS | idem (concluída ALLOW) |
| EVAL-004 | P1 | PASS | `authorizationPolicy.test.ts` "mantém cancelada consultável e bloqueada para edição" |
| EVAL-005 | P1 | PASS | `authorizationPolicy.test.ts` "histórico não concede autorização: ex-gestor DENY e gestor atual ALLOW" |
| EVAL-006 | P1 | PASS | idem (ex-gestor DENY) |
| EVAL-007 | P1 | PASS | `policyEngine.test.ts` "DESCENDANTS fora da árvore => DENY" |
| EVAL-008 | P1 | PASS | `authorizationPolicy.test.ts` "nega as capabilities de avaliação fora do escopo" |
| EVAL-009 | P1 | PASS | `f4-09-functional.test.ts` "colegiado acessa somente o alvo ASSIGNED" |
| EVAL-010 | P1 | PASS | `f4-09-functional.test.ts` "ID/sujeito manipulado ⇒ TARGET_INVALID" |
| EVAL-011 | P1 | PASS | `f4-06-core.test.ts` "8. cycleId errado ⇒ DENY" |
| EVAL-012 | P1 | PASS | `f4-09-functional.test.ts` "ID/sujeito manipulado ⇒ TARGET_INVALID" |
| EVAL-013 | P1 | PASS | `cancelamentoAvaliacaoService.test.ts` (authorize antes da mutação) |
| EVAL-014 | P1 | PASS | `authorizationPolicy.test.ts` "autoriza cancelamento de ciclo ativo somente para gerente"; `reaberturaCicloService.test.ts` "rejeita não gerente ... estados inelegíveis" |

### OBS — observações (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| OBS-001 | P1 | PASS | `f4-09-functional.test.ts` "observação de terceiro: SELF = DENY" |
| OBS-002 | P1 | PASS | `src/services/observacaoStorage.test.ts` (comunicada) |
| OBS-003 | P1 | PASS | `f4-09-functional.test.ts` "observação de terceiro: SELF = DENY" |
| OBS-004 | P1 | PASS | `authorizationPolicy.test.ts` "caracteriza observation.edit/delete"; `observacaoStorage.test.ts` |
| OBS-005 | P1 | PASS | `src/services/observacaoStorage.test.ts` (soft delete) |
| OBS-006 | P1 | PASS | `src/services/observacaoStorage.test.ts` (histórico) |
| OBS-007 | P1 | PASS | `authorizationPolicy.test.ts` "restringe capabilities de observação ao ciclo" |

### GOAL — metas (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| GOAL-001 | P1 | PASS | `authorizationPolicy.test.ts` "aplica capabilities de metas próprias à configuração atual" |
| GOAL-002 | P1 | PASS | `authorizationPolicy.test.ts` "nega todas as mutações próprias sobre meta de outro colaborador" |
| GOAL-003 | P1 | PASS | `f4-09-functional.test.ts` "metas: aprovação só no alcance"; `authorizationPolicy.test.ts` "caracteriza os papéis de aprovação" |
| GOAL-004 | P1 | PASS | `f4-10-integrated.test.ts` "SCOPE-011/SCOPE-012/GOAL-004"; `authorizationPolicy.test.ts` "nega aprovação ao coordenador que participa somente do colegiado" |
| GOAL-005 | P1 | PASS | `policyEngine.test.ts` "GERENTE também gerencia metas próprias (decisão não consulta cargo)" |
| GOAL-006 | P1 | PASS | `authorizationPolicy.test.ts` "restringe aprovação em ciclo ENCERRADO/CANCELADO" |

### CYCLE — ciclos (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| CYCLE-001 | P1 | PASS | `f4-09-functional.test.ts` "ciclo (Q7): mutação administrativa exige capability E domainState" |
| CYCLE-002 | P1 | PASS | `authorizationPolicy.test.ts` "autoriza cancelamento de ciclo ativo somente para gerente" |
| CYCLE-003 | P1 | PASS | `f4-09-functional.test.ts` "ciclo (Q7)" (sem estado ⇒ DENY) |
| CYCLE-004 | P1 | PASS | `f4-09-functional.test.ts` "ciclo (Q7)" (sem capability ⇒ DENY) |

### REPORT — relatórios/agregações (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| REPORT-001 | P1 | PASS | `relatorioService.test.ts` "LIMIT → THEN → AGGREGATE: agregações usam apenas o dataset autorizado" |
| REPORT-002 | P1 | PASS | idem (média = 2, não 3,5 — detecta agregação pré-limite) |
| REPORT-003 | P1 | PASS | `f4-10-integrated.test.ts` "REPORT-003/004/DISC-002"; `f4-09-functional.test.ts` "listAllowedTargets limita o dataset" |
| REPORT-004 | P1 | PASS | `authorizationPolicy.test.ts` "distingue colegiado no OPERATIONAL_TEAM e no REPORT"; `relatorioService.test.ts` "restringe o relatório do coordenador à equipe direta" |
| REPORT-005 | P1 | PASS | `authorizationPolicy.test.ts` "mantém REPORT equivalente à regra pública do relatório" |
| REPORT-006 | P1 | PASS | `policyEngine.test.ts` "ADMIN sem capability confidencial => DENY" |
| REPORT-007 | P1 | PASS | `authorizationPolicy.test.ts` "scopeCollaborators: report.read presente ⇒ somente targets ALLOW" |

### HIST — histórico (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| HIST-001 | P1 | PASS | `f4-09-functional.test.ts` "funcionário A não lê avaliação de B" |
| HIST-002 | P1 | PASS | `authorizationPolicy.test.ts` "histórico não concede autorização: ex-gestor DENY" |
| HIST-003 | P1 | PASS | idem (gestor atual sem relação prévia) |
| HIST-004 | P1 | PASS | `f4-05-core.test.ts` "26. contexto congelado F3-08/F3-09 não é sobrescrito" |
| HIST-005 | P1 | PASS | idem |
| HIST-006 | P1 | PASS | `authorizationPolicy.test.ts` "histórico não concede autorização" |
| HIST-007 | P1 | PASS | idem |
| HIST-008 | P1 | PASS | `f4-09-functional.test.ts` "ID/sujeito manipulado ⇒ TARGET_INVALID" |

### DISC — information disclosure (P0 confidencial; P2 timing)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| DISC-001 | P0 | PASS | `f4-09-functional.test.ts` "ID/sujeito manipulado ⇒ TARGET_INVALID" |
| DISC-002 | P0 | PASS | `f4-10-integrated.test.ts` "REPORT-003/004/DISC-002"; `relatorioService.test.ts` "LIMIT → THEN → AGGREGATE" |
| DISC-003 | P0 | PASS | `f4-09-functional.test.ts` "listAllowedTargets limita o dataset" |
| DISC-004 | P0 | PASS | `policyEngine.test.ts` "cross-tenant => DENY com público NOT_FOUND" |
| DISC-005 | P0 | PASS | `relatorioService.test.ts` "LIMIT → THEN → AGGREGATE" (fora do alcance excluído) |
| DISC-006 | P0 | PASS | `f4-10-integrated.test.ts` "PE-008/DISC-006"; `policyEngine.test.ts` "cross-tenant => NOT_FOUND" |
| DISC-007 | P2 | PASS | Q3 fechada: timing não-bloqueador (desenho §25.3) — documentado |

### REV — revogação / stale state (P0)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| REV-001 | P0 | PASS | `policyEngine.test.ts` "membership disabled => DENY (MEMBERSHIP_INVALID)" |
| REV-002 | P0 | PASS | `policyEngine.test.ts` "profile disabled => DENY (PROFILE_DISABLED)" |
| REV-003 | P0 | PASS | `f4-10-integrated.test.ts` "REV-003"; `f4-09-functional.test.ts` "capability removida ⇒ DENY imediato" |
| REV-004 | P0 | PASS | `f4-06-core.test.ts`/`f4-07-core.test.ts` (access role / concessão revogada) |
| REV-005 | P0 | PASS | `f4-05-core.test.ts` (scope assignment revogado) |
| REV-006 | P0 | PASS | `f4-05-core.test.ts` "3. substituição expirada"; "4. retorno antecipado" |
| REV-007 | P0 | PASS | `f4-06-core.test.ts` "4. grant revogado ⇒ DENY" |
| REV-008 | P0 | PASS | `f4-07-core.test.ts` "42/43. revogação com efeito imediato" |
| REV-009 | P0 | PASS | `f4-10-integrated.test.ts` "REV-009"; `f4-09-functional.test.ts` "revogação: remover o colegiado ⇒ DENY" |
| REV-010 | P0 | PASS | `f4-10-integrated.test.ts` "REV-010: mudança de gestor" |
| REV-011 | P0 | PASS | `authorizationPolicy.test.ts` "bloqueia novas avaliações e observações após desligamento" |

### ATTACK — adversariais (P0)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| ATTACK-001 | P0 | PASS | `f4-09-functional.test.ts` "ID/sujeito manipulado ⇒ TARGET_INVALID" |
| ATTACK-002 | P0 | PASS | `f4-09-functional.test.ts` "alterar funcao/cargo sem alterar relação NÃO concede" |
| ATTACK-003 | P0 | PASS | `cancelamentoCicloService.test.ts` "rejeita não gerente e motivo vazio sem modificar o ciclo" (authorize no serviço) |
| ATTACK-004 | P0 | PASS | `policyEngine.test.ts` "listAllowedTargets é auxiliar, nunca substituto de authorize()" |
| ATTACK-005 | P0 | PASS | `f4-10-integrated.test.ts` "target forjado ⇒ TARGET_INVALID" |
| ATTACK-006 | P0 | PASS | `policyEngine.test.ts` "cross-tenant => DENY"; `supabase/validacao/02-validar-f4-08.sql` |
| ATTACK-007 | P0 | PASS | `f4-10-integrated.test.ts` "PE-006/ATTACK-007 (TOCTOU)" |
| ATTACK-008 | P0 | PASS | `f4-09-functional.test.ts` "ciclo (Q7)" (domainState soberano) |
| ATTACK-009 | P0 | PASS | `correcaoPeriodoCicloService.test.ts` "rejeita perfil não autorizado e estados inelegíveis sem alteração" |
| ATTACK-010 | P0 | PASS | `f4-10-integrated.test.ts` "REV-003" |
| ATTACK-011 | P0 | PASS | `f4-09-functional.test.ts` "ID/sujeito manipulado" |
| ATTACK-012 | P0 | PASS | `f4-07-core.test.ts` "23/24. target confidencial + D ⇒ DENY" |
| ATTACK-013 | P0 | PASS | `f4-06-core.test.ts` "46. C NÃO participa de listAllowedTargets" |
| ATTACK-014 | P0 | PASS | `policyEngine.test.ts` "ADMIN sem capability confidencial => DENY" |
| ATTACK-015 | P0 | PASS | `f4-05-core.test.ts` "3. substituição expirada" |
| ATTACK-016 | P0 | PASS | `authorizationPolicy.test.ts` "histórico não concede ... ex-gestor DENY" |

### POS — positivos (P1)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| POS-001 | P1 | PASS | `f4-09-functional.test.ts` "gerente acessa os descendentes" |
| POS-002 | P1 | PASS | `f4-09-functional.test.ts` "SELF lê a própria avaliação somente em CONCLUIDA" |
| POS-003 | P1 | PASS | `f4-10-integrated.test.ts` "POS-003/POS-004"; `f4-09-functional.test.ts` "coordenador acessa seu DIRECT_REPORTS" |
| POS-004 | P1 | PASS | `f4-10-integrated.test.ts` "POS-003/POS-004" |
| POS-005 | P1 | PASS | `f4-06-core.test.ts` "1. grant válido ⇒ ALLOW excepcional" |
| POS-006 | P1 | PASS | `f4-07-core.test.ts` "1/28. grant válido em development ⇒ ALLOW" |
| POS-007 | P1 | PASS | `f4-05-core.test.ts` "1. substituição vigente concede" |
| POS-008 | P1 | PASS | `supabase/validacao/02-validar-f4-08.sql` (TENANT-006 multi-membership) |
| POS-009 | P1 | PASS | `authorizationPolicy.test.ts` "mantém criação de avaliação e observação" |
| POS-010 | P1 | PASS | `authorizationPolicy.test.ts` "caracteriza os papéis de aprovação" |

### MUT — mutation/security regression (P0)

| ID | P | Resultado | Evidência |
|---|---|---|---|
| MUT-* | P0 | PASS | `supabase/validacao/03-validar-f4-08-mutacoes.sql` (8 mutation tests: EXECUTE indevido, tabela sem RLS, grant excessivo, view/matview, TRUNCATE, policy permissive) |

## 3. Consolidação objetiva (contagem)

| Prioridade | Total | PASS | FAIL |
|---|---|---|---|
| **P0** | **82** | **82** | **0** |
| **P1** | **108** | **108** | **0** |
| **P2** | **1** | **1** | **0** |
| **Total** | **191** | **191** | **0** |

Nenhum cenário P0/P1 sem evidência rastreável.

## 4. Ausência estática de autorização por cargo (regra crítica)

```bash
grep -nE "funcao ===|funcao !==|\.funcao ===|\.funcao !==|\.cargo ===|job_role" src/authorization
```

Resultado: em `src/authorization`, `funcao`/`cargo` NÃO são fonte de ALLOW/DENY.
Ocorrências remanescentes: (1) merge de contexto para UX (`authorizationPolicy.ts`
`resolverAtor`); (2) comentários documentais (`legacyMap.ts`); (3) regra de
DOMÍNIO sobre o AVALIADO (`funcaoUsaEstruturaAvaliacaoAnalista`) — nunca
autorização do ator. Provado comportamentalmente por `policyEngine.test.ts`
"engine não consulta cargo/job_role", `f4-09` "alterar funcao/cargo ... NÃO
concede" e `f4-10` "CAP-003/HIER-008/ATTACK".

## 5. Achados

Nenhum achado CRÍTICO/ALTO. Nenhuma regra nova; nenhuma correção de
implementação necessária.

## 6. Veredito final

**APROVADO PARA ENCERRAR FASE 4.**
