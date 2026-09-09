# F4-07 — Contrato arquitetural: Pilot Full Access temporário e removível (Issue #94)

> **Status:** **CONTRATO ARQUITETURAL FECHADO** — revisão arquitetural concluída.
> **D1–D18 CLOSED / APPROVED** (§21) e **Q1–Q9 CLOSED / ANSWERED** (§22).
> Nenhuma implementação: sem código, migration, RLS, `SECURITY DEFINER`,
> alteração de frontend/Edge Functions ou PR de implementação. A **Issue #94
> permanece aberta**; a **PR #151 é somente de documentação**; **sem merge**.

## 1. Objetivo e definição final

### 1.1 Objetivo (Issue #94)

Permitir, **durante DEV/piloto**, que uma **conta explicitamente autorizada**
valide os fluxos funcionais do Virtus — sem exceção hardcoded por usuário e sem
transformar ADMIN em acesso irrestrito definitivo. Entrega: assignment explícito
e removível por membership; nenhuma identidade pessoal hardcoded; tenant
isolation; uso auditado; produção sem o mecanismo por padrão; procedimento de
remoção documentado.

### 1.2 Definição final de Pilot Full Access (consolidada)

> **Pilot Full Access é uma origem formal de autorização (D), temporária e
> removível, exclusiva de development, atribuída explicitamente a uma
> membership dentro de um tenant, com duração máxima de 30 dias, baseada em
> perfil versionado e fechado de capabilities funcionais pilot-eligible, sem
> acesso confidencial, sem gestão de segurança, sem expansão automática por
> capabilities futuras, sem violar capability×target, DOMAIN_STATE ou
> F3-08/F3-09, e com todo uso efetivo auditado.**

Não é bypass improvisado; não é "admin pode tudo"; não é exceção por pessoa;
não é cargo/job_role; não é `exceptional access` (F4-06); não é permanente.

### 1.3 Fora de escopo

superadmin permanente; suporte multiempresa em produção; compliance final
(Issue #94); implementação nesta atividade; reescrita de contratos fechados
F4-01..F4-06; F4-08 (RLS/policies); correção do drift SQL×runtime de
capabilities (dívida mantida).

## 2. Estado atual (fatos verificados)

- **Origens no engine:** **A** — membership/roles/scopes (`matchedScope`);
  **B** — temporary responsibility F4-05 (`temporary:<id>`); **C** — exceptional
  access F4-06 (`exceptional:<grantId>`; somente quando A/B DENY; somente
  confidencial elegível; fora de `listAllowedTargets` — F4-06 D18; allowlist
  fechada `evaluation.read` no piloto F4-06).
- **Gates globais (F4-03/04):** identidade/profile/membership; tenant; contrato
  fechado capability×target; data explícita; DOMAIN_STATE (probe soberano);
  razões internas nunca públicas; sem cargo/job_role; caller nunca escolhe
  origem/grant.
- **Runtime/capabilities:** `src/authorization/Capability.ts` = 34 códigos
  (inclui `exceptional_access.grant`); drift SQL×runtime = dívida (F4-06 Q6).
  `PolicyEngineProviders` já carrega `temporary?` (B) e `exceptional?` (C)
  como origens opcionais retrocompatíveis.
- **Ambiente:** `config/ambiente.ts` (development|homologation|production) e
  gates `simulacaoDevPermitida`/`resetDesenvolvimentoPermitido` =
  `DEV && !PROD && ambiente === "development"` — sempre false em HOMOLOG/PROD
  (precedente F2-09).
- **ADMIN:** role de sistema por membership/org, sem conteúdo confidencial
  automático (F4-01 D17/D18); sem papel ADMIN no runtime pré-F5; allowlists
  provisórias não são fonte soberana (F4-06 Q2).
- **Pré-F5:** fontes F3/roles/scopes ausentes no runtime; F4-04/05/06
  implementaram core/provider testável; impersonação DEV (F2-09) é DEV-only e
  não participa de autorização server-side — pode complementar a validação de
  perfis no DEV sob autorização normal.

## 3. Quatro origens e fronteira C × D (D18)

| Origem | Natureza | Escopo | Conteúdo confidencial |
| --- | --- | --- | --- |
| **A — normal** | membership/roles/scopes | scopes | sim, quando A/B autoriza |
| **B — temporária** | temporary responsibility (F4-05) | position substituída | vivo; nunca confidencial-congelado por bypass |
| **C — excepcional** | F4-06, pontual (1 cap + 1 target) | target específico | **sim** (única via excepcional) |
| **D — Pilot Full Access** | F4-07, amplo funcional, perfil versionado | tenant (development only) | **não** — nunca |

Fronteiras fechadas (D7/D18):

- F4-06 e F4-07 são **mecanismos totalmente separados**; não se reutilizam
  `target=*`, `capability=*`, `organization="*"`, grant C como full access nem
  grant D como exceptional access;
- **C nunca é fallback de D** e **D nunca é fallback para confidencial**;
- B não cria C nem D; D não cria B nem C; nenhuma origem amplia outra.

## 4. Pipeline final (D7)

```
1. identidade / profile / membership;
2. tenant;
3. capability × target (soberano — D4);
4. A/B (união deduplicada);
5. data explícita;
6. DOMAIN_STATE (soberano — D5);
7. se A/B ALLOW → ALLOW A/B (matchedScope/temporaryOrigins); C e D NÃO consumidos;
8. se A/B DENY:
   - se o alvo for CONFIDENCIAL:
       → tentar C (F4-06);
       → C ALLOW → ALLOW C (exceptional:<id>);
       → C DENY → DENY;
       → D NÃO participa (não existe fallback D para confidencial);
   - se o alvo NÃO for confidencial:
       → avaliar D (Pilot Full Access):
           - ambiente === development (D13);
           - grant D ativo (status/vigência [validFrom, validTo));
           - profileVersion válido e fechado;
           - capability pilot-eligible no perfil;
           - tenant correto (grant e membership no mesmo tenant);
           - identidade/membership/profile válidos;
           - exatamente UM grant inequívoco (D15/D16 de unicidade);
           → ALLOW D + audit used (origem pilot:<grantId>);
9. qualquer ambiguidade / dados insuficientes → DENY fail-closed.
```

- A/B são sempre avaliadas antes de D; C é avaliada antes de D **somente para
  conteúdo confidencial**; caller nunca seleciona origem/grant;
- sem dupla contagem de origem: cada decisão ALLOW preserva **uma** origem
  (A/B ou C ou D).

## 5. Gates soberanos (D4/D5/D6)

- **capability × target (D4):** contrato fechado permanece soberano; D amplia o
  **alcance** (tenant) para capabilities pilot-eligible, mas **nunca** torna
  combinação semanticamente inválida em válida — `TARGET_INCOMPATIBLE` continua
  DENY;
- **DOMAIN_STATE (D5):** D **não ignora** estado de domínio — ciclo fechado,
  recurso congelado/inativo, operação proibida por regra de domínio continuam
  soberanos (D amplia autorização, não remove invariantes);
- **Histórico F3-08/F3-09 (D6):** D pode permitir **leitura histórica** apenas
  quando a capability é pilot-eligible, capability×target é válida e
  DOMAIN_STATE permite leitura; D **nunca** altera snapshot, autoria,
  responsabilidade histórica, cria sucessão, edita conteúdo congelado nem
  reescreve histórico — mutação histórica fica **fora da F4-07**;
- **Tenant (D11):** cross-tenant = DENY; sem `organization="*"`.

## 6. O grant D (modelo conceitual fechado — D2/D11/D15)

```
PilotFullAccessGrant {
  id: string;                                   // origem pilot:<grantId>
  organizationId: string;                       // tenant (nunca org="*")
  beneficiaryUserProfileId: string;             // user_profile via membership ativa
  grantedByUserProfileId: string;               // concedente (≠ beneficiário)
  justification: string;                        // motivo obrigatório
  validFrom: Date; validTo: Date;               // janela fechada; máx. 30 dias
  status: "active" | "revoked";
  revokedAt?: Date; revokedBy?: string; revocationMotive?: string;
  profileVersion: string;                       // ex.: "PILOT_PROFILE_V1"
  createdAt: Date; version: number;
}
```

- **Sem wildcard** e **sem snapshot de capabilities individuais escolhidas pelo
  concedente** (Q9): o grant referencia `profileVersion` de um perfil **fechado
  e explícito** (§10); o concedente não escolhe capabilities na concessão;
- **Identidade (D11):** beneficiário soberano = user_profile via **membership
  ativa**; podem existir múltiplos beneficiários e o mesmo usuário pode ter
  grants em organizações diferentes (cada um com `organizationId` próprio,
  membership válida naquele tenant e concessão independente) — sem grant
  coletivo;
- **Estado:** ATIVO → EXPIRADO (por data) / REVOGADO; nunca exclusão física;
  sem cache residual; sem necessidade de restart.

## 7. Concessão, revogação e renúncia (D10/D12)

**Concessão (D10):** cria capability administrativa específica —
**`pilot_full_access.grant`** (nome final adotado no runtime F4-07; dívida de
alinhamento SQL×runtime registrada). Regras:

- resolvida **pelo Policy Engine**; atribuída explicitamente por membership;
- **não** pertence automaticamente ao ADMIN; **não** deriva de cargo/job_role;
  **não** vem de allowlist DEV; **não** concedida implicitamente;
- auto-concessão **proibida**; justificativa **obrigatória**; `validFrom`/
  `validTo` **obrigatórios**; duração máxima **30 dias**; retroativo
  **proibido**; sem dual control nesta fase;
- a capability de concessão **não** concede conteúdo (ato administrativo
  separado, padrão F4-06 D3/D4) e **nunca** é concedida pelo próprio D.

**Revogação/renúncia (D12):** podem remover o grant (1) o concedente original,
(2) outro ator com capability apropriada, (3) o próprio beneficiário por
**renúncia voluntária**. Regras: motivo obrigatório para revogação
administrativa; renúncia gera evento próprio (`relinquished`, origem
"beneficiary") ou revogação com origem "beneficiary"; **efeito imediato**; sem
exclusão física; membership/profile inválidos ⇒ D imediatamente inelegível;
expiração ⇒ D imediatamente inelegível; sem cache residual; sem restart.

## 8. Vigência (D9/Q2/Q6)

- `validFrom` **obrigatório**; `validTo` **obrigatório**; `validTo > validFrom`;
- **duração máxima por grant: 30 dias**; não existe grant permanente;
- **não existe extensão in-place**; para continuar após expiração: **novo
  grant**, nova justificativa, novo evento de concessão, nova janela, novo
  `grantId` (cada renovação é uma nova concessão independente — Q6);
- retroativo proibido; expiração por **comparação de data** (sem job
  obrigatório; sem cache que prolongue acesso).

## 9. Ambiente (D13/Q8)

A origem D **só pode produzir ALLOW em `development`**. Em `homologation` e
`production`: **DENY D** — mesmo que exista grant válido persistido (fail-closed
por ambiente). Regras:

- gate **central** e coerente com `config/ambiente.ts` (padrão
  `simulacaoDevPermitida`), aplicado na composição/runtime — **não** bypass
  espalhado em múltiplos arquivos;
- o core/provider pode permanecer **puro e testável** sem dependência global
  direta, mas **não pode existir caminho real que ative D fora de development**;
- sem identidade hardcoded; sem allowlist pessoal.

## 10. Perfil de capabilities — PILOT_PROFILE_V1 (D1/D3/D16/Q1/Q9)

Perfil **versionado, fechado e explícito** (sem "*", sem "todas exceto", sem
prefix matching). Grant referencia `profileVersion`. Classificação de cada
capability do `src/authorization/Capability.ts` (34 códigos):

### 10.1 PILOT_ELIGIBLE — PILOT_PROFILE_V1 (20 códigos; funcionais, não
confidenciais, tenant-wide, DOMAIN_STATE soberano)

| Capability | Fluxo funcional validado pelo piloto |
| --- | --- |
| `collaborator.create` | cadastro de colaborador |
| `collaborator.edit` | edição de colaborador |
| `collaborator.list` | listagem de colaboradores |
| `cycle.coordinator.list` | listagem do painel do coordenador |
| `cycle.management.view` | visualização de gestão do ciclo |
| `cycle.team.panel.view` | painel de equipe do ciclo |
| `cycle.cancel.manager` | cancelamento de ciclo (ação funcional; DOMAIN_STATE soberano) |
| `cycle.reopen.manager` | reabertura de ciclo (ação funcional) |
| `cycle.period.correct.manager` | correção de período de ciclo (ação funcional) |
| `goal.write` | fluxo de metas (ação canônica) |
| `goal.approve` | aprovação funcional de metas |
| `goal.view.admin` | consulta de metas (não confidencial) |
| `goal.create.own` | criação de meta própria |
| `goal.edit.own` | edição de meta própria |
| `goal.delete.own` | exclusão de meta própria |
| `goal.progress.own` | acompanhamento de meta própria |
| `goal.finalize.own` | finalização de meta própria |
| `observation.create` | criação de observação (não confidencial no domínio-piloto F4-06) |
| `observation.edit` | edição de observação |
| `observation.delete` | exclusão de observação |

### 10.2 EXCLUDED_CONFIDENTIAL (fora de D — F4-06 soberano; A/B normal ou C)

| Capability | Motivo |
| --- | --- |
| `evaluation.create` | conteúdo de avaliação/feedback de terceiros |
| `evaluation.read` | idem (capability de leitura confidencial do F4-06) |
| `evaluation.write` | idem |
| `evaluation.cancel.manager` | idem |
| `evaluation.reopen.manager` | idem |
| `evaluation.view.admin` | idem |
| `evaluation.edit.manager` | idem |
| `evaluation.edit.coordinator` | idem |
| `evaluation.edit.board` | idem |
| `report.view` | leitura consolidada derivada de avaliações/notas de terceiros |

### 10.3 EXCLUDED_SECURITY / configuração sensível (fora de D)

| Capability | Motivo |
| --- | --- |
| `settings.manage` | configuração sensível |
| `exceptional_access.grant` | concessão de exceção (F4-06) — D não concede C |
| `pilot_full_access.grant` | concessão de D (nova, adicionada na implementação) — D não concede D |

> Gestão de roles/access roles não é representada no runtime
> `Capability.ts` (códigos como `access_role.manage`/`membership.manage` existem
> só no catálogo SQL — dívida de vocabulário); nada disso entraria em D.

### 10.4 EXCLUDED_LEGACY_ROLE_VARIANT (fora de D — variante legada de ação já coberta)

| Capability | Motivo |
| --- | --- |
| `goal.approve.manager` | variante legada com escopo de papel; a ação funcional já é coberta por `goal.approve` (tenant-wide em D) |
| `goal.approve.coordinator` | idem |

> **Evolução (D16/Q9):** nova capability adicionada ao Virtus **não entra** no
> perfil automaticamente — exige revisão, decisão e, se aprovada, **nova versão
> do perfil** (ex.: `PILOT_PROFILE_V2`). O concedente nunca escolhe capabilities
> na concessão (Q9).

## 11. Auditoria (D14/Q5)

Eventos separados, append-only, por user_profile, tenant, timestamp,
`grant_id`, `profileVersion`:

- **(A) `granted`:** concedente, beneficiário, quando, motivo, tenant, perfil/
  `profileVersion`, vigência;
- **(B) `revoked`:** revogador, quando, motivo;
- **(C) `relinquished` (renúncia pelo beneficiário):** origem "beneficiary";
- **(D) `expired`/`invalidation`:** derivada por data ou membership/profile
  inválido (quando aplicável);
- **(E) `used`:** **todo** uso efetivo da origem D gera evento identificando:
  `grantId`, beneficiary, organization, capability, target, timestamp,
  `profileVersion`, origin `pilot:<grantId>`.

**Posse × uso:** "possui Pilot Full Access" (grant ativo) ≠ "operação autorizada
graças a D". Se A/B já autorizam → D não é consumido → **sem** evento de uso D.
Se C autoriza conteúdo confidencial → D não é consumido → **sem** evento de uso
D. Logs de C (F4-06) e de D (F4-07) **não** são misturados semanticamente (Q5).

## 12. listAllowedTargets (D8)

D **pode participar** de `listAllowedTargets` somente quando: a capability é
**pilot-eligible**; o target type é permitido; o conteúdo **não** é confidencial;
o tenant é correto; demais gates aplicáveis são satisfeitos. C continua **fora**
de `listAllowedTargets` (F4-06 D18). D **não** revela conteúdo confidencial;
`authorize` continua sendo a decisão real.

## 13. Diagnóstico (D17)

Quando D autorizar: origem `pilot:<grantId>` preservada em diagnóstico
**separado** de `matchedScope`, `temporaryOrigins` e `exceptionalGrant`.
Razões internas podem diferenciar falhas da origem D, mas **nunca** revelam
publicamente: existência do grant, expiração, revogação, membership especial ou
perfil piloto — contrato de erro seguro da F4-03 preservado.

## 14. Persistência futura (D15)

Modelo conceitual: (1) estado atual do `PilotFullAccessGrant` + (2) eventos
append-only separados. Nunca apagar histórico; impedir duplicidade ambígua de
grants ativos equivalentes no mesmo tenant (unicidade por (beneficiário,
organização) ativo). **Nenhuma migration nesta fase.**

## 15. Runtime pré-F5 (Q4)

Implementação futura segue o padrão F4-04/F4-05/F4-06: **core/provider puro e
testável** (entrada F3/F4-shaped + event sink in-memory). Sem identidade
hardcoded; sem email allowlist pessoal; sem bootstrap por cargo; sem
localStorage como fonte soberana; sem fake grant de produção. Fonte
runtime/persistente definitiva fica **condicionada à F5**. Fixture/test double
DEV, se necessário, fica claramente isolado e não atua como fonte soberana de
produção. A impersonação DEV (F2-09) permanece DEV-only e complementa a
validação de perfis sob autorização normal; D cobre a amplitude funcional não
confidencial.

## 16. F4-08 / RLS (requisitos, sem implementar)

A F4-08 deverá respeitar: RLS como última barreira server-side (F4-03 §19);
predicados restritos derivados dos mesmos contratos (membership, grants D,
scopes) sem predicado "tudo"; deny-by-default nas tabelas de grant/eventos D
com policies mínimas; resolução server-side consumindo os mesmos contratos com
revalidação atômica na mesma RPC/transação (F4-03 D9 — requisito F5/F4-08);
gate de ambiente respeitado também server-side (D só produz ALLOW em
development). Nenhuma policy/RPC é escrita nesta atividade.

## 17. Procedimento de remoção do piloto (entrega da Issue)

Registra-se o requisito (a executar na implementação): procedimento documentado
para revogar/remover todos os grants D ao encerrar o piloto (quem executa, com
`pilot_full_access.grant`, motivo obrigatório), efeito imediato (retorno à
autorização normal), verificação de ausência de autorização residual,
encerramento do bootstrap DEV e desativação do mecanismo.

## 18. Matriz de testes (para a futura implementação)

Cada caso valida o contrato fechado (sem cargo, sem wildcard, sem confidencial,
development-only, máx. 30 dias, perfil fechado):

1. grant válido → ALLOW pilot (`pilot:<grantId>`);
2. grant futuro → DENY;
3. grant expirado → DENY;
4. grant revogado → DENY;
5. tenant diferente → DENY;
6. beneficiário diferente → DENY;
7. membership inativa → DENY;
8. profile inválido → DENY;
9. justificativa ausente → concessão rejeitada;
10. período inválido → rejeitado;
11. tentativa de grant permanente → rejeitada;
12. grant > 30 dias → inválido/rejeitado;
13. concessão por ator não autorizado (sem `pilot_full_access.grant`) → DENY;
14. auto-concessão → proibida;
15. revogação registrada (revogador/motivo/data);
16. revogação/renúncia com efeito imediato;
17. expiração entre duas operações → segunda DENY;
18. **novo grant após expiração funciona de forma independente** (novo grantId/
    justificativa/janela/evento — sem extensão in-place);
19. capability pilot-eligible → ALLOW via D;
20. capability excluída do perfil → DENY via D;
21. capability nova não presente no `profileVersion` → DENY;
22. capability × target inválido → TARGET_INCOMPATIBLE (D não torna válida);
23. DOMAIN_STATE inválido → DENY (D não ignora);
24. histórico congelado → leitura somente;
25. leitura histórica elegível → ALLOW via D (quando pilot-eligible e domínio
    permite);
26. tentativa de mutação histórica → DENY;
27. A autoriza → ALLOW normal, D não consumido;
28. B autoriza → ALLOW temporário, D não consumido;
29. conteúdo confidencial + C válido + D válido → C autoriza, D não consome;
30. conteúdo confidencial + C inexistente + D válido → **DENY** (D não é
    fallback para confidencial);
31. conteúdo normal + A/B ALLOW + D válido → A/B autoriza, D não consome;
32. conteúdo normal + A/B DENY + D válido → D pode autorizar;
33. múltiplos grants D ativos equivalentes → DENY (fail-closed)/unicidade;
34. caller tentando selecionar grant → impossível;
35. caller tentando selecionar origem → impossível;
36. wildcard (target/capability/organização) → rejeitado;
37. cross-tenant → DENY;
38. auditoria da concessão (`granted`);
39. auditoria da revogação (`revoked`);
40. auditoria da renúncia (`relinquished`);
41. auditoria da expiração/invalidação (derivada);
42. auditoria do uso efetivo (`used` — origem `pilot:<grantId>`,
    `profileVersion`);
43. operação normal NÃO consumindo D (posse ≠ uso; sem evento `used`);
44. operação autorizada por D registrando origem;
45. `listAllowedTargets` com D nunca expõe conteúdo confidencial;
46. capability de segurança (`exceptional_access.grant`,
    `pilot_full_access.grant`) + D válido → DENY;
47. `settings.manage` + D válido → DENY;
48. D não concede a própria `pilot_full_access.grant`;
49. D fora de development (homologation) → DENY;
50. D fora de development (production) → DENY;
51. dados incompletos/ambíguos → DENY;
52. fail-closed;
53. ausência de cargo/job_role no caminho D.

## 19. Riscos, dependências e itens fora de escopo

- **Riscos e mitigações (fechados):** permanente acidental (janela fechada +
  máx. 30 dias + sem extensão in-place — D9); expansão automática por
  capability futura (perfil versionado + decisão explícita — D16); vazamento de
  confidencial (D nunca é fallback para confidencial; C é a única via
  excepcional — D3/D7/Q7); ativação em produção (gate de ambiente central —
  D13/Q8); bypass do engine (D é origem interna com gates globais — D4/D5);
  mistura com F4-06 (origens/diagnósticos separados — D18/D17); auditoria
  incompleta (eventos A–E com posse × uso — D14); escalada de segurança
  (capabilities de concessão/configuração fora do perfil e concessão sem
  ADMIN/cargo — D3/D10); ambiguidade de múltiplos grants (fail-closed/unicidade
  — D15).
- **Dependências:** F4-01 (roles/ADMIN D17/D18), F4-02 (scopes/tenant), F4-03
  (engine/gates/§21), F4-04 (capability×target), F4-05 (B), F4-06 (C e
  D1–D20/Q1–Q8), F2-09/ambiente (gate DEV), F3-08/F3-09 (histórico), F4-08
  (RLS futura), F5 (runtime).
- **Fora de escopo:** implementação, superadmin permanente, multiempresa em
  produção, compliance final, F4-08, correção do drift de vocabulário.

## 20. Contrato arquitetural fechado

### 20.1 Resumo vinculante

- D = origem formal, temporária e removível, **exclusiva de development**,
  atribuída a **membership ativa** dentro de um tenant, **máx. 30 dias**, perfil
  **PILOT_PROFILE_V1** fechado/versionado de capabilities funcionais
  **pilot-eligible**, **sem confidencial**, **sem segurança/concessão/
  configuração**, **sem expansão automática**, sem violar capability×target,
  DOMAIN_STATE ou F3-08/F3-09; **todo uso efetivo auditado** (`pilot:<grantId>`).

### 20.2 Invariantes finais

1. Policy Engine é a única porta de decisão (D é origem interna);
2. capability = ação; scope/relação = alcance; tenant mismatch = DENY;
   fail-closed; caller nunca escolhe origem/grant;
3. sem cargo/job_role; sem wildcard; sem ADMIN/cargo como fonte; sem allowlist
   DEV soberana; sem extensão in-place; sem D fora de development;
4. D não amplia A/B/C; B não cria C/D; C e D separados; D nunca é fallback para
   confidencial (F4-06 soberano para conteúdo confidencial);
5. capability×target, DOMAIN_STATE e F3-08/F3-09 soberanos; histórico nunca é
   reescrito;
6. perfil versionado fechado: nova capability não entra sem revisão/nova versão;
7. concessão/renovação/revogação/renúncia/uso rastreáveis (eventos A–E);
   origem `pilot:<grantId>` preservada; posse ≠ consumo;
8. duration máx. 30 dias; expiração por data (sem job/cache); remoção imediata;
9. runtime `Capability.ts` é a referência; drift SQL×runtime documentado como
   dívida;
10. nenhuma migration/RLS/`SECURITY DEFINER` nesta atividade; sem merge;
    Issue #94 aberta; PR #151 somente de documentação.

### 20.3 Próximo passo

Com D1–D18 e Q1–Q9 fechados, este documento é o contrato arquitetural para a
implementação futura da F4-07 (core/provider testável + perfil PILOT_PROFILE_V1
+ origem D no pipeline com gate de ambiente + eventos de auditoria A–E em
memória), em nova fase com branch/PR de implementação — sempre sem migration/
RLS/DEFINER, sem cargo/job_role e sem antecipar F4-08.

## 21. Decisões — D1–D18 (CLOSED / APPROVED)

> Nenhuma alternativa permanece em aberto; textos antigos foram removidos.
> Regra fechada de cada decisão:

- **D1 — Modelo de capabilities — CLOSED:** Pilot Full Access NÃO é "todas as
  capabilities do runtime"; usa **allowlist fechada e versionada** de
  capabilities explicitamente pilot-eligible. Sem wildcard, prefix matching,
  "todas atuais/futuras automaticamente"; role ADMIN ≠ Pilot Full Access. Nova
  capability não amplia D automaticamente; expansão exige revisão explícita do
  perfil.
- **D2 — Representação da origem D — CLOSED:** grant dedicado
  `PilotFullAccessGrant` (beneficiary user_profile/membership + organizationId +
  vigência + profileVersion + concedente + justificativa + estado/revogação).
  Não modelar como cargo, job_role, ADMIN, exceptional access F4-06, scope
  wildcard ou role especial implícita.
- **D3 — Capabilities incluídas/excluídas — CLOSED:** D cobre somente
  capabilities FUNCIONAIS explicitamente pilot-eligible no perfil versionado.
  Excluídos: gestão de segurança/access roles/roles; `exceptional_access.grant`;
  `pilot_full_access.grant`; `settings.manage`; qualquer capability confidencial;
  capability futura não aprovada; operação estruturalmente proibida. Conteúdo
  confidencial NÃO é coberto por D (F4-06 soberano). D não é "ver tudo".
- **D4 — capability × target — CLOSED:** contrato fechado soberano; D amplia
  alcance para capabilities pilot-eligible mas nunca torna combinação inválida
  válida; `TARGET_INCOMPATIBLE` continua DENY.
- **D5 — DOMAIN_STATE — CLOSED:** D NÃO ignora DOMAIN_STATE; ciclo fechado,
  recurso congelado, operação proibida por regra de domínio permanecem soberanos.
- **D6 — Histórico F3-08/F3-09 — CLOSED:** F3-08/F3-09 soberanos; D pode
  permitir leitura histórica apenas com capability pilot-eligible + capability×
  target válido + DOMAIN_STATE permitindo leitura; D nunca altera snapshot/
  autoria/responsabilidade/sucessão/conteúdo congelado/histórico; mutação
  histórica fora da F4-07.
- **D7 — Ordem das origens — CLOSED:** gates globais → A/B → se A/B ALLOW,
  ALLOW A/B (C/D não consumidos); se A/B DENY e confidencial → tentar C (C ALLOW
  → ALLOW C; C DENY → DENY; **D não participa**); se A/B DENY e não confidencial
  → avaliar D (ambiente=development, grant ativo, profileVersion, capability
  pilot-eligible, tenant, vigência, identidade/membership, exatamente um grant
  inequívoco → ALLOW D + audit used). Não existe fallback D para confidencial;
  sem dupla contagem de origem.
- **D8 — listAllowedTargets — CLOSED:** D pode participar somente quando
  capability pilot-eligible + target type permitido + conteúdo NÃO confidencial
  + tenant correto + demais gates; C continua fora (F4-06 D18); D não revela
  confidencial; `authorize` é a decisão real.
- **D9 — Vigência/duração/renovação — CLOSED:** `validFrom`/`validTo`
  obrigatórios; `validTo > validFrom`; **duração máxima 30 dias**; sem grant
  permanente; **sem extensão in-place** (continuar = novo grant, nova
  justificativa, novo evento, nova vigência); retroativo proibido; expiração por
  comparação de data (sem job obrigatório, sem cache que prolongue).
- **D10 — Concessão — CLOSED:** capability administrativa **`pilot_full_access
  .grant`** (nome final adotado; dívida SQL×runtime registrada), resolvida pelo
  Policy Engine; não pertence automaticamente ao ADMIN; não deriva de cargo/
  job_role; não vem de allowlist DEV; não concedida implicitamente;
  auto-concessão proibida; justificativa obrigatória; validFrom/validTo
  obrigatórios; máx. 30 dias; sem dual control.
- **D11 — Identidade/tenant — CLOSED:** beneficiário soberano = user_profile via
  membership ativa; grant sempre tenant-scoped; podem existir múltiplos grants
  para a mesma pessoa em organizações diferentes (organizationId próprio,
  membership válida no tenant, concessão independente); sem `organization="*"`;
  cross-tenant = DENY.
- **D12 — Revogação/renúncia — CLOSED:** removem o grant: concedente original,
  outro ator com capability apropriada, ou o próprio beneficiário por renúncia
  voluntária; motivo obrigatório para revogação administrativa; renúncia gera
  evento próprio (`relinquished`, origem "beneficiary"); efeito imediato; sem
  exclusão física; membership/profile inválido ⇒ D imediatamente inelegível;
  expiração ⇒ D imediatamente inelegível; sem cache residual; sem restart.
- **D13 — Gate de ambiente — CLOSED:** origem D só produz ALLOW em
  `development`; HOMOLOG e PROD ⇒ DENY D mesmo com grant persistido (fail-closed);
  gate central coerente com `config/ambiente.ts` na composição/runtime; core
  puro testável permitido, mas sem caminho real de D fora de development; sem
  identidade hardcoded; sem allowlist pessoal; sem bypass espalhado.
- **D14 — Auditoria — CLOSED:** eventos separados: A `granted`, B `revoked`,
  C `relinquished` (renúncia), D `expired`/`invalidation` (derivado), E `used`;
  todo uso efetivo de D gera evento (`grantId`, beneficiary, organization,
  capability, target, timestamp, `profileVersion`, origin `pilot:<grantId>`);
  posse ≠ consumo; A/B ALLOW ⇒ D não consumido (sem evento de uso D); C
  autorizando confidencial ⇒ D não consumido; logs C e D não misturados.
- **D15 — Persistência futura — CLOSED:** estado atual do grant + eventos
  append-only separados; nunca apagar histórico; impedir duplicidade ambígua de
  grants ativos equivalentes no mesmo tenant; nenhuma migration nesta fase.
- **D16 — Evolução de capabilities — CLOSED:** nova capability não entra em D
  automaticamente; perfil versionado fechado (ex.: `PILOT_PROFILE_V1`, nova
  versão sob revisão/decisão); grant referencia `profileVersion`; sem "*" e sem
  "todas menos...".
- **D17 — Diagnóstico — CLOSED:** quando D autoriza, origem `pilot:<grantId>`
  preservada separadamente de `matchedScope`, `temporaryOrigins` e
  `exceptionalGrant`; razões internas podem diferenciar falhas de D mas nunca
  revelam publicamente existência/expiração/revogação/membership especial/perfil
  piloto — contrato de erro seguro F4-03 preservado.
- **D18 — Fronteira C × D — CLOSED:** F4-06 e F4-07 totalmente separados;
  C = pontual, target específico, capability específica, confidencial, auditado,
  excepcional; D = amplo funcional, tenant-scoped, perfil versionado, somente
  development, não confidencial; sem reutilizar `target=*`/`capability=*`/
  `organization="*"`/grant C como full access/grant D como exceptional access.

## 22. Questões — Q1–Q9 (CLOSED / ANSWERED)

- **Q1 — Domínios que o piloto opera — CLOSED:** todos os fluxos FUNCIONAIS
  necessários para validar o produto, excluindo segurança/autorização, gestão de
  grants C/D, configurações sensíveis, conteúdo confidencial e mutação
  histórica; allowlist exata derivada do `Capability.ts` real (§10).
- **Q2 — Duração — CLOSED:** máximo **30 dias por grant**; sem permanente.
- **Q3 — Quantas contas — CLOSED:** arquitetura não fixa quantidade; múltiplos
  beneficiários possíveis; cada grant é individual por (beneficiary +
  organization); sem grant coletivo.
- **Q4 — Materialização DEV pré-F5 — CLOSED:** padrão F4-04/F4-05/F4-06 (core/
  provider puro e testável); sem identidade hardcoded, email allowlist pessoal,
  bootstrap por cargo, localStorage soberano ou fake grant de produção; fonte
  definitiva condicionada à F5; fixture/test double DEV isolado, nunca fonte
  soberana.
- **Q5 — Auditoria de acessos sensíveis — CLOSED:** todo uso efetivo de D é
  auditado; conteúdo confidencial não passa por D; F4-06 continua auditando C;
  logs C e D não misturados semanticamente.
- **Q6 — Renovação — CLOSED:** não existe extensão in-place; ao expirar, novo
  grant (novo grantId, nova justificativa, nova janela, novo evento).
- **Q7 — Piloto lê conteúdo confidencial? — CLOSED:** NÃO; confidencial
  exclusivamente sob A/B (quando autorizado) ou C (F4-06); D nunca é fallback
  para confidencial.
- **Q8 — Gate de ambiente — CLOSED:** D só produz ALLOW em development;
  HOMOLOG e PROD ⇒ DENY D; gate central na composição/runtime; core testável sem
  caminho real de ativação fora de development.
- **Q9 — Snapshot vs perfil versionado — CLOSED:** **perfil versionado**;
  grant referencia `profileVersion`; composição fechada e explícita; nova
  capability não entra automaticamente; concedente não escolhe capabilities
  individualmente na concessão.

## 23. Confirmações desta atividade

Nenhum código, migration, RLS ou `SECURITY DEFINER` foi produzido — somente
`docs/F4-07-desenho-tecnico.md`. Issue #94 permanece aberta (PR sem `Closes`).
