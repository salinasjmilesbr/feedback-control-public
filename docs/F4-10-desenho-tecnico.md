# F4-10 — Contrato de validação integrada da matriz de autorização (Issue #97)

> **Status: DESENHO TÉCNICO — contrato em revisão de desenho.** Esta atividade é
> **somente documentação**: nenhum código, nenhuma migration, nenhuma alteração
> de banco, nenhum teste foi produzido. A Issue #97 **permanece aberta**; o PR
> desta atividade é somente documentação e **NÃO usa `Closes #97`**; **sem merge**.
>
> **Implementação da F4-10 ocorre somente após F4-08 e F4-09 implementadas.**
> A F4-08 (PR #154) ainda não foi mergeada; este desenho usa o CONTRATO fechado da
> F4-08 como referência arquitetural, sem presumir código não mergeado na main.

## 1. Objetivo

Fechar a Fase 4 demonstrando, de forma **sistemática e adversarial**, que as
regras construídas em F4-01…F4-09 funcionam juntas e **fail-closed**. Não se
testam apenas caminhos felizes. Prova-se:

- quem DEVE acessar consegue;
- quem NÃO deve acessar não consegue;
- nenhuma camada isolada cria bypass;
- mudanças de estado/tempo/relação/revogação têm efeito correto;
- dados confidenciais permanecem protegidos;
- acesso ao tenant nunca significa acesso irrestrito aos dados funcionais.

## 2. Base e fontes

Base: `main` em `c8fda5acc37b795ce3dc5ec661d87c1bd768f11d`. Fontes lidas:
Issue #97; docs F4-01…F4-09 (incl. `docs/F4-09-desenho-tecnico.md` — contrato
fechado Q1–Q7/D1–D12 e catálogo canônico); contratos F3-08/F3-09; Policy Engine
(`src/authorization/policyEngine/*`), providers, `Capability.ts`, scopes,
temporary responsibility (F4-05), exceptional access (F4-06), Pilot Full Access
(F4-07); testes de autorização existentes e validação Supabase local F4-08.

## 3. Papel da F4-10

A F4-10 **não cria nova arquitetura de autorização**. Ela: (1) consolida a matriz
existente; (2) define cenários integrados; (3) identifica lacunas de cobertura;
(4) define testes positivos e negativos; (5) define testes adversariais; (6)
estabelece critérios objetivos para declarar a Fase 4 concluída. **Nenhuma regra
nova surge silenciosamente na validação** — se a matriz revelar regra ausente ou
ambígua, registra-se como questão/defeito do contrato correspondente (F4-01…F4-09)
antes de prosseguir.

## 4. Princípio de segurança e adversários

- **Ameaça interna:** usuário legítimo tentando acesso indevido: avaliação de
  colega; a própria avaliação antes da liberação; ex-gestor no histórico;
  coordenador fora da equipe; gerente extrapolando scope; ADMIN como bypass;
  colegiado obtendo hierarquia; relatório de pessoas fora do alcance.
- **Ameaça externa:** sem membership; JWT inválido; token antigo; tenant errado;
  API direta; IDs manipulados; enumeration; inferência de existência.

A F4-10 valida **autorização, confidencialidade, isolamento, temporalidade,
revogação e information disclosure** — não pentest de produção (§26 fora de
escopo).

## 5. Matriz integrada consolidada

Dimensões por cenário: IDENTIDADE × TENANT × PROFILE × MEMBERSHIP × CAPABILITY ×
TARGET × SCOPE × RELAÇÃO × DOMAIN STATE × TEMPORALIDADE × CONFIDENCIALIDADE ×
ORIGEM (A/B/C/D) × RESULTADO (ALLOW | DENY — nunca "depende" sem regra).

Para cada cenário indicar ainda: camada soberana que nega/permite; `reason`
esperado; erro público esperado quando aplicável; se a leitura deve retornar
vazio/NOT_FOUND (anti-disclosure); evidência/teste necessário. O formato de
registro e os IDs estáveis estão na §21; as tabelas por área estão nas §§7–19; os
casos positivos na §20.

## 6. Ordem das camadas (pipeline soberano)

Valida-se a ordem: (1) identidade → (2) profile ativo → (3) membership ativa →
(4) tenant → (5) capability → (6) capability×target → (7) scope → (8) relação →
(9) temporalidade → (10) domainState → (11) confidencialidade → (12) origem A/B →
(13) C quando permitido → (14) D quando permitido → (15) ALLOW/DENY.

Testes de precedência (nenhuma etapa posterior supera um DENY soberano
anterior):

- capability válida **nunca** supera tenant inválido;
- D **nunca** supera target confidencial;
- SELF **nunca** supera estado não publicado;
- temporary responsibility expirada **nunca** concede;
- role/admin **nunca** supera ausência de relação quando relação é exigida;
- capability × target fora da allowlist ⇒ DENY antes de scope/relação;
- membership inativa ⇒ DENY antes de capability;
- C só participa quando A/B DENY; D só quando não-confidencial e A/B DENY.

Exemplos de cenários de precedência (matriz de teste §21):

| ID | Cenário | Resultado | Reason esperado | Camada soberana |
|---|---|---|---|---|
| PIPE-001 | capability válida, tenant errado | DENY | CROSS_TENANT | 4 tenant |
| PIPE-002 | D ativo, target confidencial | DENY | (C-only) / indeterminada | 11 confidencialidade |
| PIPE-003 | SELF + capability, avaliação não `CONCLUIDA` | DENY | DOMAIN_STATE_INVALID | 10 domainState |
| PIPE-004 | substitution expirada | DENY | SCOPE_INSUFFICIENT | 8/9 |
| PIPE-005 | ADMIN com capability, sem relação exigida | DENY | SCOPE_INSUFFICIENT | 8 relação/scope |
| PIPE-006 | capability×target não previsto | DENY | TARGET_INCOMPATIBLE | 6 |
| PIPE-007 | membership inativa + capability válida | DENY | MEMBERSHIP_INVALID | 3 |

## 7. Tenant / F4-08 (validação de integração; sem redesenho)

Planejar cenários sobre o contrato F4-08 (auth.uid + profile ativo + membership
ativa; deny-by-default; RLS por comando; audit fechada; sem FORCE; sem novo
DEFINER). Cobertura mínima:

| ID | Cenário | Resultado | Erro/leitura | Camada |
|---|---|---|---|---|
| TENANT-001 | usuário tenant A lê tabela/linha do tenant B | DENY | vazio/NOT_FOUND | RLS |
| TENANT-002 | usuário A altera/exclui linha do tenant B | DENY | 0 linhas/permission | RLS/grants |
| TENANT-003 | SELECT por ID direto de B (colaborador/posição/snapshot) | DENY | vazio | RLS |
| TENANT-004 | `organizationId` manipulado no cliente | DENY | NOT_FOUND | RLS/engine |
| TENANT-005 | parent/FK cross-tenant A→B (child com parent de B) | DENY | FK violation | constraint |
| TENANT-006 | multi-membership A+B acessa A e B, não C | ALLOW (A,B)/DENY(C) | — | RLS |
| TENANT-007 | sem membership | DENY | vazio | RLS |
| TENANT-008 | membership inativa | DENY | vazio | RLS |
| TENANT-009 | profile inativo (membership ativa) | DENY | vazio | RLS/helper |
| TENANT-010 | anon | DENY | permission denied/vazio | RLS/grants |
| TENANT-011 | capabilities global: SELECT ok, DML DENY | ALLOW(SELECT)/DENY(DML) | — | grants |
| TENANT-012 | security tables (access_roles etc.) fechadas | DENY | permission denied | grants/RLS |
| TENANT-013 | audit/history (snapshots, evaluation_succession_events) sem rewrite | DENY | 0 linhas | grants/RLS |
| TENANT-014 | TRUNCATE/TRIGGER/REFERENCES indevidos ausentes (guard) | PASS do guard | — | grants |
| TENANT-015 | membership revogada durante a sessão ⇒ efeito imediato | DENY após revogar | — | RLS |

## 8. Capabilities / F4-01 (integradas com a decisão F4-09 Q1)

| ID | Cenário | Resultado | Reason |
|---|---|---|---|
| CAP-001 | capability inexistente/desconhecida | DENY | CAPABILITY_MISSING |
| CAP-002 | capability removida durante a sessão ⇒ DENY na próxima operação | DENY | CAPABILITY_MISSING |
| CAP-003 | capability não é derivada de cargo (regressão: nenhum `funcao→capability`) | DENY/PASS guard | — |
| CAP-004 | capability representa ação (catálogo canônico F4-09 §6.3); alias legado não cria autorização paralela | DENY se só alias | CAPABILITY_MISSING |
| CAP-005 | capability × target fora da allowlist | DENY | TARGET_INCOMPATIBLE |
| CAP-006 | ADMIN não recebe conteúdo confidencial apenas por ser ADMIN | DENY | SCOPE_INSUFFICIENT |

## 9. Scopes / F4-02

Para **cada** scope — SELF, DIRECT_REPORTS, DESCENDANTS, ORGANIZATIONAL_UNIT,
ORGANIZATION, ASSIGNED — cobrir: caso positivo; alvo imediatamente fora; alvo
muito fora; manipulação de target; mudança de relação; combinação com estado/
confidencialidade.

| ID | Cenário | Resultado |
|---|---|---|
| SCOPE-001 | SELF resolve o próprio colaborador (vínculo ativo) | ALLOW |
| SCOPE-002 | SELF sem vínculo | vazio/DENY |
| SCOPE-003 | DIRECT_REPORTS: subordinado direto real | ALLOW |
| SCOPE-004 | DIRECT_REPORTS: subordinado de subordinado (não direto) | DENY |
| SCOPE-005 | DESCENDANTS: descendente transitivo | ALLOW |
| SCOPE-006 | DESCENDANTS: ramo de outra posição não confiável do ator | DENY |
| SCOPE-007 | ORGANIZATIONAL_UNIT: unidade atribuída | ALLOW |
| SCOPE-008 | ORGANIZATIONAL_UNIT: subunidade (não atribuída) | DENY |
| SCOPE-009 | ORGANIZATION: outro colaborador do tenant (alcance, não permissão) | ALLOW para leitura estrutural; conteúdo depende de capability |
| SCOPE-010 | ASSIGNED (colegiado): recurso de avaliação atribuído | ALLOW (só o alvo) |
| SCOPE-011 | ASSIGNED nunca vira hierarquia (avaliado não ganha DIRECT_REPORTS) | DENY |
| SCOPE-012 | ASSIGNED nunca vira wildcard (outro avaliado não atribuído) | DENY |
| SCOPE-013 | avaliação atribuída não concede metas/observações de terceiro | DENY |
| SCOPE-014 | target do scope manipulado (id de fora do alcance) | DENY |
| SCOPE-015 | mudança de relação (novo gestor/novo coordenador) reflete na data | ALLOW/DENY por contexto |
| SCOPE-016 | scope + estado (ex.: SELF + avaliação não publicada) | DENY |

## 10. Policy Engine / F4-03

| ID | Cenário | Resultado |
|---|---|---|
| PE-001 | `authorize` em mutação autorizada | ALLOW (executa) |
| PE-002 | `authorize` em mutação não autorizada | DENY → erro público (F0-05) |
| PE-003 | `can` é predicação (UX); NUNCA enforcement | can=false não impede teste direto; authorize é a prova |
| PE-004 | `listAllowedTargets` não autoriza mutação (usar lista ≠ authorize) | DENY na mutação |
| PE-005 | chamada direta ao service/use-case sem authorize | DENY (service é a porta) |
| PE-006 | TOCTOU: reutilizar decision antigo de can/list após revogação | DENY (authorize reavalia) |
| PE-007 | provider incompleto/erro ⇒ fail-closed | DENY (INDETERMINATE) |
| PE-008 | reason mapping: CROSS_TENANT/TARGET_INVALID ⇒ NOT_FOUND; DOMAIN_STATE_INVALID ⇒ CONFLICT; demais ⇒ FORBIDDEN | mapeado |
| PE-009 | CROSS_TENANT/TARGET_INVALID em leitura não vaza existência | NOT_FOUND/vazio |
| PE-010 | data de contexto ausente | DENY (INDETERMINATE) |
| PE-011 | domainState ausente | DENY (INDETERMINATE) |

## 11. Hierarquia / F4-04

| ID | Cenário | Resultado |
|---|---|---|
| HIER-001 | DIRECT_REPORTS correto (ocupante real) | ALLOW |
| HIER-002 | DESCENDANTS correto (transitivo, dedup) | ALLOW |
| HIER-003 | múltiplas posições confiáveis do ator (união) | ALLOW (união) |
| HIER-004 | vacancy não cria colaborador alvo artificial | sem colaborador |
| HIER-005 | vacancy intermediária não quebra a traversal | ALLOW nos descendentes |
| HIER-006 | colegiado não entra na hierarquia (sem DIRECT_REPORTS via ASSIGNED) | DENY |
| HIER-007 | caller não escolhe a posição soberana (todas as posições confiáveis) | DENY se forçar posição |
| HIER-008 | cargo/job_role/nome nunca autorizam | DENY |
| HIER-009 | histórico (snapshot F3-08) e estrutura live não se confundem | por data/contexto |
| HIER-010 | ator sem occupation/relação | vazio/DENY |

## 12. Temporary responsibility / F4-05

| ID | Cenário | Resultado |
|---|---|---|
| TEMP-001 | substituto válido dentro da janela `[valid_from, valid_to)` | ALLOW (caps do conjunto) |
| TEMP-002 | antes da janela | DENY |
| TEMP-003 | depois da janela | DENY |
| TEMP-004 | revogado/inativado | DENY |
| TEMP-005 | titular continua autorizado conforme contrato (overlay) | ALLOW (titular) |
| TEMP-006 | substituto não herda capabilities/scopes fora do conjunto permitido | DENY fora do conjunto |
| TEMP-007 | substitution não reescreve histórico (avaliador do ciclo = F3-08/09) | sem alteração |
| TEMP-008 | ASSIGNED avaliativo permanece soberano (contexto congelado) | DENY em contexto congelado |
| TEMP-009 | grants próprios do substituto continuam independentes | ALLOW (próprios) |

## 13. Exceptional access C / F4-06

| ID | Cenário | Resultado |
|---|---|---|
| EXC-001 | C entra somente quando A/B DENY; A/B ALLOW ⇒ C não consumido | ALLOW A/B; C não usado |
| EXC-002 | target confidencial + C `evaluation.read` na allowlist | ALLOW excepcional (1 grant) |
| EXC-003 | capability fora da allowlist (ex.: `goal.read` via C) | DENY |
| EXC-004 | target específico (avaliação × ciclo) — outro alvo | DENY |
| EXC-005 | ciclo específico obrigatório (undefined ≠ qualquer ciclo) | DENY |
| EXC-006 | janela válida | ALLOW |
| EXC-007 | revogado/expirado | DENY |
| EXC-008 | uso gera auditoria (`used`) | ALLOW + evento |
| EXC-009 | grant/revogação geram auditoria (`granted/revoked`) | evento |
| EXC-010 | C não vira wildcard (ambiguidade >1 grant ⇒ DENY) | DENY |
| EXC-011 | C não aparece em `listAllowedTargets` | ausente |
| EXC-012 | C não abre observações/relatórios (contrato não prevê) | DENY |
| EXC-013 | target malformed (sem ciclo, tipo errado) | DENY |

## 14. Pilot Full Access D / F4-07

| ID | Cenário | Resultado |
|---|---|---|
| PILOT-001 | D somente em development | ALLOW dev / DENY hom/prod |
| PILOT-002 | profile versionado (`PILOT_PROFILE_V1`); fora da versão | DENY |
| PILOT-003 | somente capabilities do perfil; capability nova fora do perfil | DENY |
| PILOT-004 | target não-confidencial permitido | ALLOW |
| PILOT-005 | confidencial (evaluation.*/report.read) nunca usa D | DENY |
| PILOT-006 | revogado | DENY |
| PILOT-007 | expirado (data) | DENY |
| PILOT-008 | janela > 30 dias inválida (estrutural) | DENY |
| PILOT-009 | grant malformed | DENY |
| PILOT-010 | A/B ALLOW ⇒ D não consumido | ALLOW A/B |
| PILOT-011 | uso efetivo auditado com origem `pilot:<grantId>` | evento |
| PILOT-012 | organização específica, nunca wildcard/tenant-wide indevido | DENY cross-tenant |
| PILOT-013 | D não cobre settings/segurança/concessão | DENY |

## 15. F4-09 — Autorização funcional (bloco central)

Usa o contrato fechado F4-09 (Q1–Q7/D1–D12; catálogo canônico: capability =
ação; papel por relação/scope/target/domainState). Validação dos domínios:

### 15.1 Avaliações

| ID | Cenário | Resultado | Reason/erro |
|---|---|---|---|
| EVAL-001 | funcionário A → avaliação de B | DENY | SCOPE_INSUFFICIENT/FORBIDDEN |
| EVAL-002 | SELF antes de `CONCLUIDA` (incl. `PRONTA_PARA_FEEDBACK`) | DENY | DOMAIN_STATE_INVALID/CONFLICT ou FORBIDDEN por Q4 |
| EVAL-003 | SELF em `CONCLUIDA` (quando permitido) | ALLOW | — |
| EVAL-004 | avaliação histórica continua confidencial (idade não reduz) | DENY sem autorização | — |
| EVAL-005 | gestor atual não recebe automaticamente avaliação anterior à gestão | DENY | Q5 |
| EVAL-006 | ex-gestor perde acesso | DENY | — |
| EVAL-007 | gerente fora do scope | DENY | SCOPE_INSUFFICIENT |
| EVAL-008 | coordenador fora de DIRECT_REPORTS | DENY | — |
| EVAL-009 | colegiado só no ASSIGNED correspondente | ALLOW/DENY por alvo | — |
| EVAL-010 | ID de avaliação manipulado | DENY/NOT_FOUND | TARGET_INVALID |
| EVAL-011 | cycleId manipulado | DENY/NOT_FOUND | — |
| EVAL-012 | collaboratorId manipulado | DENY/NOT_FOUND | — |
| EVAL-013 | criar/editar exige `authorize` (não só `can`) | ALLOW/DENY no serviço | — |
| EVAL-014 | cancelar/reabrir respeita estado (domainState) e relação | ALLOW/DENY | CONFLICT quando estado inválido |

### 15.2 Observações

| ID | Cenário | Resultado |
|---|---|---|
| OBS-001 | não-comunicada invisível ao avaliado (nem SELF) | DENY/vazio |
| OBS-002 | comunicada SELF pode ser lida conforme contrato | ALLOW |
| OBS-003 | outro colaborador lê observação | DENY |
| OBS-004 | editar/excluir exige `authorize` (▸ implementação) | ALLOW/DENY no serviço |
| OBS-005 | soft delete não vaza conteúdo (excluída não aparece ao avaliado) | vazio |
| OBS-006 | histórico preserva confidencialidade (edição/exclusão rastreáveis) | rastreável; conteúdo regido pela mesma regra |
| OBS-007 | criar exige ciclo ATIVO + avaliado ativo (domainState) | ALLOW/DENY |

### 15.3 Metas

| ID | Cenário | Resultado |
|---|---|---|
| GOAL-001 | SELF correto (dono, ciclo ATIVO, regra funcional Q3) | ALLOW |
| GOAL-002 | terceiro fora do scope | DENY |
| GOAL-003 | aprovação só no alcance (coordenador direto/gerente da cadeia) | ALLOW/DENY por scope |
| GOAL-004 | colegiado não recebe metas por ASSIGNED de avaliação | DENY |
| GOAL-005 | regras próprias via domainState (não por cargo) | conforme regra funcional |
| GOAL-006 | estado inválido (ciclo não ATIVO) bloqueia | DENY/CONFLICT |

### 15.4 Ciclos

| ID | Cenário | Resultado |
|---|---|---|
| CYCLE-001 | mutação administrativa exige authorize + domainState (Q7) | ALLOW só com ambos |
| CYCLE-002 | estado inválido (cancelar não-ATIVO etc.) | DENY/CONFLICT |
| CYCLE-003 | capability sem estado válido não basta | DENY |
| CYCLE-004 | estado válido sem capability não basta | DENY |

### 15.5 Relatórios (D12 — limit-then-aggregate)

| ID | Cenário | Resultado |
|---|---|---|
| REPORT-001 | contagem/média/ranking/export só sobre dataset autorizado | agregado correto |
| REPORT-002 | proibido agregar tudo e filtrar depois (guard) | falha do guard |
| REPORT-003 | sem targets autorizados ⇒ dataset vazio ⇒ agregado vazio | vazio |
| REPORT-004 | coordenador só equipe permitida (não colegiado no relatório) | dataset restrito |
| REPORT-005 | gerente só o scope permitido | dataset restrito |
| REPORT-006 | ADMIN não ganha conteúdo por cargo (D11) | DENY |
| REPORT-007 | filtros/export herdam dataset autorizado; não revelam existência fora do alcance | vazio/not-found |

## 16. Histórico (confidencialidade não diminui com o tempo)

| ID | Cenário | Resultado |
|---|---|---|
| HIST-001 | avaliação antiga de colega | DENY |
| HIST-002 | ex-gestor no histórico | DENY |
| HIST-003 | novo gestor sem relação histórica | DENY |
| HIST-004 | snapshot correto na data (quem era o avaliador/responsável no ciclo) | ALLOW só com relação no período |
| HIST-005 | sucessão correta (F3-09) não reescreve o passado | sem reescrita |
| HIST-006 | estrutura atual não reescreve o passado (Q5) | DENY a histórico pré-relação |
| HIST-007 | relação passada não concede o presente | DENY |
| HIST-008 | histórico não vira endpoint aberto | vazio/not-found |

## 17. Information disclosure

Ataques para descobrir EXISTÊNCIA: IDs; counts; autocomplete; filtros;
mensagens de erro; timing quando relevante; relatório; export; metadata; listas.
Definição de resposta esperada por contrato:

- leitura confidencial não autorizada: comportamento equivalente a inexistente
  quando o contrato determinar → `vazio` ou `NOT_FOUND`;
- mutação: `FORBIDDEN` (sem benefício em ocultar) ou `CONFLICT` (estado);
- engine: `CROSS_TENANT/TARGET_INVALID ⇒ NOT_FOUND`; `DOMAIN_STATE_INVALID ⇒
  CONFLICT`; demais ⇒ `FORBIDDEN` (F4-03 D6).

| ID | Cenário | Resposta esperada |
|---|---|---|
| DISC-001 | inferir existência de avaliação de colega por ID | NOT_FOUND/vazio |
| DISC-002 | contar avaliações fora do alcance | vazio (não "0 de N") |
| DISC-003 | autocomplete/filtro lista apenas alvos autorizados | lista limitada |
| DISC-004 | erro não revela existência em leitura confidencial | NOT_FOUND genérico |
| DISC-005 | relatório/export fora do alcance | vazio |
| DISC-006 | CROSS_TENANT em leitura | NOT_FOUND |
| DISC-007 | timing: não exigir distinção quando impraticável; registrar como não-bloqueador | documentado |

## 18. Revogação / stale state

Matriz: estado antes → ação de revogação → resultado imediatamente depois.
Cobertura: membership; profile; capability; access role; scope assignment;
temporary responsibility; grant C; grant D; ASSIGNED/colegiado; mudança de
gestor; desligamento/licença quando aplicável. **Não aceitar logout como
requisito de segurança, salvo contrato explícito** (RLS/engine reavaliam por
operação).

| ID | O que revoga | Resultado imediato |
|---|---|---|
| REV-001 | membership → disabled | DENY (vazio/RLS) |
| REV-002 | profile → disabled | DENY (D1 F4-08) |
| REV-003 | capability removida do role | DENY (CAPABILITY_MISSING) |
| REV-004 | access role inativada | DENY |
| REV-005 | scope assignment revogado/inativado | DENY (SCOPE_INSUFFICIENT) |
| REV-006 | temporary responsibility encerrada/expirada | DENY |
| REV-007 | grant C revogado/expirado | DENY |
| REV-008 | grant D revogado/expirado | DENY |
| REV-009 | ASSIGNED/colegiado alterado (snapshot muda? não — ciclo congelado) | regido por F3-08/09 |
| REV-010 | mudança de gestor/coordenador | perde alcance novo cenário |
| REV-011 | desligamento/licença do ator | DENY conforme status |

## 19. Testes adversariais

| ID | Ataque | Resultado esperado |
|---|---|---|
| ATTACK-001 | trocar IDs na URL | DENY/not-found |
| ATTACK-002 | alterar localStorage (dados/rolo) | não concede capability; enforcement de aplicação falha fechado |
| ATTACK-003 | chamar service diretamente sem authorize | DENY (service é a porta) |
| ATTACK-004 | chamar repository diretamente | não substitui a porta; sem efeito autorizante |
| ATTACK-005 | forjar target (tipo/org/tenant) | DENY (TARGET_INVALID/CROSS_TENANT) |
| ATTACK-006 | forjar tenant/organizationId | DENY |
| ATTACK-007 | reutilizar AuthorizationDecision antigo após revogação | DENY (TOCTOU) |
| ATTACK-008 | alterar estado no frontend | DENY (domainState server/engine) |
| ATTACK-009 | bypassar botão escondido (chamar operação sem can) | authorize no serviço nega |
| ATTACK-010 | operação após capability revogada | DENY |
| ATTACK-011 | inferir avaliação de colega | NOT_FOUND/vazio |
| ATTACK-012 | usar D em conteúdo confidencial | DENY |
| ATTACK-013 | usar C para listar targets | ausente em listAllowedTargets |
| ATTACK-014 | usar ADMIN como bypass de confidencial | DENY (D11) |
| ATTACK-015 | substituição expirada tentando avaliar | DENY |
| ATTACK-016 | ex-gestor no histórico | DENY |

## 20. Testes positivos (hardening não torna o produto inutilizável)

Para cada regra crítica deve existir pelo menos um ALLOW correspondente:

| ID | Cenário positivo |
|---|---|
| POS-001 | gestor correto acessa avaliação dentro do scope |
| POS-002 | colaborador lê a própria avaliação concluída |
| POS-003 | coordenador acessa direto correto |
| POS-004 | colegiado acessa o assignment correto |
| POS-005 | C válido acessa exatamente o target autorizado |
| POS-006 | D válido acessa target não-confidencial permitido (dev) |
| POS-007 | substituto válido executa operação permitida na janela |
| POS-008 | multi-membership acessa ambos os tenants legítimos |
| POS-009 | criar/editar observação por gestor/coordenador no alcance e ciclo ATIVO |
| POS-010 | aprovar meta no alcance |

## 21. Formato do test matrix (reproduzível)

Colunas sugeridas (por cenário):
`ID | Categoria | Ator | Tenant | Profile | Membership | Capability | Target |
Scope | Relação | Estado | Data/contexto | Confidencial? | Origem esperada |
Resultado (ALLOW/DENY) | Reason | Erro público | Camada soberana | Tipo de teste |
Automatizável? | Bloqueador de release?`

IDs estáveis por prefixo: `AUTH-*`, `PIPE-*`, `TENANT-*`, `CAP-*`, `SCOPE-*`,
`PE-*`, `HIER-*`, `TEMP-*`, `EXC-*`, `PILOT-*`, `EVAL-*`, `OBS-*`, `GOAL-*`,
`CYCLE-*`, `REPORT-*`, `HIST-*`, `DISC-*`, `REV-*`, `ATTACK-*`, `POS-*`,
`MUT-*` (mutation/security regression do schema guard). Cada cenário terá
"Automatizável?" e "Bloqueador de release?" explícitos.

## 22. Níveis de teste

Classificação por nível e regras:

- **unit** — funções puras (predicados, cálculo de alcance, janelas);
- **Policy Engine** — pipeline/decisions (unit/integration do engine);
- **provider** — cada provider (structure/relation/assigned/temporary/
  exceptional/pilot) com seu mundo;
- **service/use-case** — `authorize` antes da mutação (enforcement);
- **integration** — mundo local + domínios funcionais + regras F4-09;
- **Supabase local** — RLS/grants/tenant (F4-08) com fixtures sintéticas
  (docker/psql), sem remoto;
- **end-to-end** — somente quando unit/integration não bastar;
- **mutation/security regression** — schema guard F4-08 (detecta regressões:
  grant indevido, tabela sem RLS, view/matview, EXECUTE em DEFINER etc.).

Regra: **não exigir E2E onde unit/integration é suficiente**; **não aceitar
somente unit/mocks para propriedades que dependem de banco/RLS** (essas exigem
Supabase local).

## 23. Critério de saída da Fase 4

Saída exige TODOS os itens abaixo:

1. nenhuma questão arquitetural aberta;
2. F4-01…F4-09 implementadas;
3. matriz integrada executada;
4. todos os testes críticos PASS;
5. nenhum CRÍTICO/ALTO conhecido de autorização aberto;
6. tenant isolation validado (F4-08);
7. confidencialidade interna validada (F4-09);
8. avaliações históricas protegidas;
9. revogações validadas (sem exigir logout);
10. nenhuma autorização runtime por cargo;
11. ADMIN não é superusuário de conteúdo (D11 F4-09);
12. D não abre confidencial;
13. C não vira wildcard;
14. ASSIGNED não vira hierarquia;
15. SELF respeita estado;
16. limit-then-aggregate validado (D12 F4-09);
17. CI executa os guards críticos relevantes (incl. mutation/security regression
    e Supabase local quando o domínio estiver no banco);
18. documentação reflete a implementação final.

**Achados MÉDIOS:** podem permitir saída somente quando (a) não ampliam o
alcance de dados (apenas UX/legibilidade), ou (b) estão documentados como
limitação aceita com teste/guard de regressão associado e um item explícito no
backlog da fase seguinte. Achados com impacto em confidencialidade/isolamento/
revogação são tratados como ALTO/CRÍTICO e bloqueiam a saída.

## 24. Risco residual / F5

Separação explícita:

- **Garantia da F4:** enforcement de aplicação (Policy Engine) sobre domínios
  localStorage; RLS sobre tabelas estruturais/autorizativas; capacidade de teste
  adversarial em Supabase local para o que está no banco.
- **Garantia que só existirá após F5:** proteção por RLS das tabelas funcionais
  (avaliações/metas/observações/ciclos) e impossibilidade de bypass por chamada
  direta a API/banco para esses dados. **Não declarar segurança de API/banco
  para dados que ainda não estão persistidos ali.**
- **Invariantes que F5 deve preservar (mapeadas de F4-09 §15):** avaliação só
  acessível com autorização explícita (idade não reduz confidencialidade);
  avaliado vê somente observações `comunicado`; colegiado (ASSIGNED) sem
  hierarquia; ADMIN sem leitura de confidencial sem grant excepcional; SELF
  restrito por estado; mutação respeita estado; nenhuma segunda regra paralela;
  limit-then-aggregate.

## 25. Questões para validação

Se surgir decisão real, registra-se nesta seção (ID, contexto, decisão
necessária, alternativas, recomendação, riscos/impacto, seções dependentes) —
nunca assumida silenciosamente. Questões abertas em aberto ao fim do desenho
são permitidas, mas bloqueiam a declaração de saída (critério 1, §23). Questões
atuais (preenchidas na revisão de desenho):

1. **Q1 — Escopo de automatização do Supabase local para domínios funcionais
   ainda em localStorage.** Contexto: RLS só cobre tabelas estruturais; domínios
   funcionais são aplicação. Decisão necessária: os cenários F4-09 (EVAL/OBS/
   GOAL/CYCLE/REPORT) devem ser validados como integration no mundo local
   (engine) — sem exigir Supabase local? Alternativas: (a) integration local +
   engine; (b) esperar F5. Recomendação: (a); Supabase local permanece para os
   cenários de tenant/grants (TENANT-*, CAP-*, MUT-*). Seções: §15, §22, §24.
2. **Q2 — Definição de "teste crítico" e "bloqueador de release".** Contexto:
   critério 4/5 exige que testes críticos PASS e nenhum ALTO aberto. Decisão:
   quais categorias são bloqueadoras (confidencialidade, isolamento, revogação,
   precedência de camadas) e quais podem ser não-bloqueadoras. Recomendação:
   bloquear CRÍTICO/ALTO de confidencialidade/isolamento/revogação; MÉDIOS
   conforme §23. Seções: §21, §23.
3. **Q3 — Timing/information disclosure.** Contexto: timing pode revelar
   existência em leitura confidencial. Decisão: exigir mitigação de timing nesta
   fase? Recomendação: não-bloqueador; registrar limitação (DISC-007); mitigação
   real junto à persistência F5. Seções: §17, §23.

## 26. Fora de escopo (evitar overengineering)

F4-10 é o fechamento da Fase 4 (autorização/confidencialidade/isolamento/
temporalidade/revogação/disclosure). **Não ampliar** para: infraestrutura, DDoS,
malware, segurança física, backup/DR, SSO, produção, secrets management
completo, segurança de rede, compliance integral — temas de fases posteriores.

## 27. Decisões arquiteturais (D1…)

1. **D1 — F4-10 valida integração; não cria regra nova.** Toda regra ausente/
   ambígua revelada na matriz vira questão/defeito do contrato F4-01…F4-09.
2. **D2 — Pipeline de 15 etapas é a ordem soberana.** Nenhuma etapa posterior
   supera um DENY anterior; precedência é testada (§6, PIPE-*).
3. **D3 — enforcement = authorize no service; can = UX; listAllowedTargets =
   auxiliar; TOCTOU proibido** (herança F4-03/F4-09).
4. **D4 — Vocabulário canônico (F4-09 §6.3): capability = ação; aliases legados
   não criam autorização paralela.**
5. **D5 — Negativos e positivos obrigatórios** em cada regra crítica (§20).
6. **D6 — Testes dependentes de banco/RLS exigem Supabase local** (sem mocks).
7. **D7 — Leitura confidencial não autorizada = equivalente a inexistente**
   (vazio/NOT_FOUND) quando o contrato determina; mutação pode ser explícita.
8. **D8 — Revogação tem efeito imediato; logout não é requisito de segurança.**
9. **D9 — Dados totalmente sintéticos** em qualquer fixture (nenhum dado real).
10. **D10 — Critérios de saída objetivos** (§23); achados MÉDIOS só liberam sob
    condições; CRÍTICO/ALTO de confidencialidade/isolamento/revogação bloqueiam.

## 28. Confirmações da atividade

Nenhum código, nenhuma migration, nenhuma alteração de banco, nenhum teste foi
produzido — somente `docs/F4-10-desenho-tecnico.md`. Issue #97 permanece aberta;
o PR é somente documentação e **não usa `Closes #97`**; **sem merge**. A
implementação da F4-10 ocorre somente após F4-08 e F4-09 implementadas.
