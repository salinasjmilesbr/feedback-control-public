# F4-07 — Desenho técnico: Pilot Full Access temporário e removível (Issue #94)

> **Status:** desenho técnico da F4-07 **aguardando revisão** — decisões
> **D1–D18 ABERTAS** (recomendação indicada, sem fechamento) e seção
> **"Questões para validação"** (§20). Nenhuma implementação: sem código,
> migration, RLS, `SECURITY DEFINER`, alteração de frontend/Edge Functions ou PR
> de implementação. A implementação só começa depois que D1–Dn forem revisadas e
> fechadas e o desenho for aprovado como contrato técnico.

## 1. Objetivo, princípio e boundary

### 1.1 Objetivo (Issue #94)

Permitir, **durante DEV/piloto**, que uma **conta explicitamente autorizada**
valide **todos os perfis e fluxos** do Virtus — sem criar exceção hardcoded por
usuário e sem transformar ADMIN em acesso irrestrito definitivo. Entrega:

- mecanismo de **acesso ampliado temporário e removível** para DEV/piloto;
- **assignment explícito e removível por membership**;
- **nenhuma identidade pessoal hardcoded**;
- **tenant isolation** preservada;
- uso/acessos sensíveis **registrados de forma compatível com auditoria**;
- **produção não recebe o mecanismo por padrão** (configuração/ambiente);
- procedimento de **remoção ao encerrar o piloto** documentado.

### 1.2 Princípio central

Pilot Full Access é tratado como uma **ELEVAÇÃO CONTROLADA** dentro da
arquitetura de autorização — uma **origem formal** (D) no Policy Engine, com
contrato explícito, fronteiras claras e caminho explícito de remoção. **Não** é
um bypass improvisado.

Modelos equivalentes a "if admin return true", "if pilot return true", email
allowlist espalhada no código, cargo/job_role, usuário especial hardcoded,
bypass fora do engine, service role, `SECURITY DEFINER` como atalho, RLS
desabilitado, tenant wildcard ou autorização permanente implícita são
**rejeitados**.

### 1.3 Fora de escopo

superadmin permanente; suporte multiempresa em produção; compliance final
(Issue #94); implementação nesta atividade; reescrita de contratos fechados das
F4-01..F4-06 sem decisão explícita; F4-08 (RLS/policies).

## 2. Estado atual (fatos verificados)

- **Origens no engine (F4-03/04/05/06):**
  - **A** — membership/roles/scopes (`matchedScope`);
  - **B** — temporary responsibility F4-05 (`temporary:<id>`), allowlist por
    tipo, fronteira vivo × congelado;
  - **C** — exceptional access F4-06 (`exceptional:<grantId>`), **somente
    consultada quando A/B DENY**, allowlist fechada `evaluation.read` no piloto,
    classificação soberana de confidencialidade, **fora de `listAllowedTargets`**
    (F4-06 D18), concessão/revogação auditada (`granted/revoked/used`),
    auto-concessão proibida, beneficiary = user_profile/membership;
  - Gates globais: identidade/profile/membership (1–3), tenant (4), capability×
    target (5.1), data (8), DOMAIN_STATE (9) — todos soberanos para qualquer
    origem; razões internas nunca públicas (F4-03 D6); sem cargo/job_role.
- **Runtime/capabilities:** referência runtime = `src/authorization/
  Capability.ts` (34 códigos, incl. `exceptional_access.grant`); drift SQL×
  runtime = dívida (F4-06 Q6). Contrato fechado capability×target
  (capabilityTarget.ts). `PolicyEngineProviders` já carrega `temporary?` (B) e
  `exceptional?` (C) como origens opcionais retrocompatíveis.
- **Ambiente/DEV:** `config/ambiente.ts` centraliza `configuracaoAmbiente.
  ambiente` (development|homologation|production) e
  `simulacaoDevPermitida` = `DEV && !PROD && ambiente === "development"`
  (precedente F2-09: gate DEV **sempre false** em HOMOLOG/PROD). Existe
  impersonação DEV-only (F2-09) que **não** participa de autorização
  server-side. Reset DEV (`resetDesenvolvimentoPermitido`) usa o mesmo gate.
- **ADMIN:** role de sistema por membership/org, sem conteúdo confidencial
  automático (F4-01 D17/D18); não existe papel ADMIN no runtime pré-F5.
  Allowlist `INVITE_ADMIN_USER_IDS`/`verify_jwt=false` são provisórias e não são
  fonte soberana (F4-06 Q2).
- **Pré-F5:** fontes F3/roles/scopes não existem como dado no runtime
  (localStorage); migração funcional fica para F5. F4-04/F4-05/F4-06
  implementaram **core/provider testável** com entrada F3/F4-shaped.

## 3. Significado de "Full Access" (questão central)

"Não presuma que significa 'pode fazer literalmente qualquer coisa'". O desenho
distingue categorias de operação e trata cada uma explicitamente:

| # | Categoria | Pergunta do piloto | Tratamento recomendado (aberto, D1/D3) |
| --- | --- | --- | --- |
| 1 | Acesso funcional amplo | o piloto opera os fluxos (metas, observações, avaliações em edição, ciclos, colaboradores) | allowlist fechada de capabilities funcionais elegíveis (D1/D3) |
| 2 | Ações administrativas | gerir ciclos/catálogos/estrutura | allowlist fechada; decisão explícita por capability (D3) |
| 3 | Gestão de segurança/autorização | roles, access roles, concessão de C/D, settings | **excluído** por padrão (D3) — sem auto-ampliação de segurança |
| 4 | Dados confidenciais | leitura de conteúdo confidencial (avaliação de terceiros) | depende de decisão (D3/D7/Q7): ou via allowlist D com auditoria, ou permanece só com C |
| 5 | Histórico/conteúdo congelado | leitura vs mutação de F3-08/F3-09 | **somente leitura**; mutação exige decisão (D6) |
| 6 | Operações estruturalmente proibidas | invariantes de domínio | **DOMAIN_STATE nunca é ignorado** (D5) |
| 7 | Operações futuras (capabilities novas) | capacidade adicionada depois | **não expande D automaticamente** (D16) |

### 3.1 Alternativas de modelo (D1)

- **(A) Conceder automaticamente todas as capabilities runtime** — simples, mas
  faz qualquer capability futura expandir o piloto sem revisão e mistura
  segurança/confidencial com operação;
- **(B) Allowlist fechada de capabilities elegíveis ao piloto** — contrato
  fechado, fail-closed, sem expansão automática;
- **(C) Meta-capability específica** (ex.: `pilot.full_access`) com semântica
  própria resolvida no engine — indireção a avaliar contra B;
- **(D) outro modelo** (ex.: role de sistema "pilot" via F4-01 + scope
  ORGANIZATION, ou grant dedicado tipo F4-06).

**Recomendação preliminar: (B)** — allowlist fechada versionada de capabilities
piloto-elegíveis, com **grant dedicado** (origem D) e não a role `admin`
(recomendação em D2). Se necessário, combinada com (C) apenas como código
canônico da allowlist (sem wildcard).

## 4. Modelo conceitual da origem D

### 4.1 PilotFullAccessGrant (shape proposto — decisões D2/D9/D15)

Consistente com a identidade soberana da F4-06 (D19 — user_profile/membership):

```
PilotFullAccessGrant {
  id; organizationId;                          // tenant (nunca org="*")
  beneficiaryUserProfileId;                    // identidade soberana (membership)
  grantedByUserProfileId;                      // concedente (≠ beneficiário — D10)
  justification;                               // motivo obrigatório
  validFrom; validTo;                          // janela fechada; sem permanente (D9)
  status: "active" | "revoked";
  revokedAt?; revokedBy?; revocationMotive?;   // D12
  profileVersion;                              // versão da allowlist piloto-elegível (D16)
  allowedCapabilities: Capability[];           // snapshot fechado OU derivado do perfil (D16)
  createdAt; version;
}
```

- **Sem wildcard**: `allowedCapabilities` é lista fechada (ou referência a perfil
  versionado), nunca "*"; nenhum target armazenado (D opera com alcance
  ORGANIZATION do tenant para as capabilities da allowlist — D2/D7);
- **Identidade**: user_profile via membership ativa; sem exigir collaborator;
  cross-tenant impossível (todas as referências com `organizationId` + FKs
  compostas futuras);
- **Estado**: ATIVO → EXPIRADO (por data) / REVOGADO (manual); nunca exclusão
  física; expiração/revogação **sem job/cache** (decisão sempre resolve por
  data/estado).

### 4.2 Vigência (D9)

- `validFrom` e `validTo` obrigatórios; `valid_to > valid_from`; sem grant
  permanente; duração máxima configurável (Q2); extensão/renovação limitada
  (novo evento ou novo grant — D9); retroativo proibido; timezone/date
  semantics seguem o padrão existente de `Date` explícita no contexto (F4-03
  D13/F4-06 D13).

## 5. Policy Engine — posição da origem D (D7)

### 5.1 Ordem conceitual A/B/C/D

```
1–4 identidade/profile/membership/tenant (gates globais — sempre)
5  capability A ⊕ B (união deduplicada)
5.1 capability × target (soberano — D4)
6/7 scope/relação A ⊕ B
   → se A/B ALLOW → ALLOW normal/temporário (C e D NÃO consumidos)
8  data explícita
9  DOMAIN_STATE (soberano — D5)
```

Quando A/B negam (capability ou scope):

```
→ conteúdo CONFIDENCIAL? (classificação soberana)
     sim → tentar C (F4-06) [C fora de listAllowedTargets — F4-06 D18]
            C ALLOW → ALLOW excepcional; C DENY → tentar D? (decisão D3/D7/Q7)
     não  → tentar D (Pilot Full Access)
            D ALLOW (grant ativo, perfil cobre a capability, tenant, vigência)
              → ALLOW pilot (origem pilot:<grantId>) + auditoria de uso
            D DENY → DENY seguro original
```

- D é origem **após** A/B e (para conteúdo confidencial) avaliada após C,
  conforme decisão D7/Q7 — nunca antes;
- D **pode ampliar alcance** de uma capability permitida (tenant), mas **não
  torna inválida uma combinação capability × target** (D4) e **não ignora
  DOMAIN_STATE** (D5);
- diagnóstico preserva **uma origem por decisão**: `matchedScope` (A),
  `temporaryOrigins` (B), `exceptionalGrant` (C), `pilotGrant`/`origin:
  "pilot:<grantId>"` (D) — origens nunca misturadas nem dupla contagem de uso;
- caller nunca seleciona origem/grant (o provider resolve; sem campo de
  seleção).

### 5.2 O que D pode e não pode ampliar

- **Pode:** alcance (tenant) das capabilities da allowlist fechada; cobertura
  de alvos do tenant para essas capabilities;
- **Nunca pode ignorar:** tenant (4), capability×target (5.1), data explícita
  (8), DOMAIN_STATE (9), identidade/membership/profile (1–3), e a exclusão de
  capabilities de segurança/administração não listadas (D3).

## 6. Confidencialidade e fronteira C × D (D3/D7/Q7)

F4-06 e F4-07 **não se misturam**: F4-07 **não** é implementada reutilizando
exceptional access como wildcard (`exceptional grant target=* capability=*` é
proibido). Pontos a fechar:

- C continua sendo o mecanismo **pontual** (1 beneficiário + 1 capability + 1
  target + vigência + justificativa + uso auditado);
- D é o mecanismo **de piloto** (amplo, temporário, governado);
- para conteúdo **confidencial**, C deve ser tentado **antes** de D
  (recomendação em D7) para manter a trilha específica de exceção; se D também
  cobrir leitura confidencial (Q7), o uso via D é auditado como tal;
- C e D podem coexistir para o mesmo usuário sem ampliação cruzada; uma
  temporary responsibility (B) nunca cria D, e D nunca cria C/B.

## 7. Concessão, revogação, renúncia e ciclo de vida (D10/D12)

**Concessão (D10):** ato administrativo autorizado pelo Policy Engine via
capability específica (nova — `pilot_full_access.grant`? decisão D10/D3) por
organization; **sem cargo**, **sem allowlist DEV como fonte soberana**, **sem
ADMIN automático**; auto-concessão **proibida**; justificativa **obrigatória**;
início/fim **obrigatórios**; duração máxima (D9); retroativo **proibido**;
renovação/extensão como evento novo ou novo grant (D9) — nunca edição
silenciosa.

**Revogação (D12):** pelo concedente, por outro ator com a capability
apropriada, ou **renúncia pelo próprio beneficiário** (decisão D12); motivo
obrigatório; efeito **imediato** (remoção restaura autorização normal — critério
de aceite da Issue); **sem job/cache**; membership/profile inválidos ⇒ grant
deixa de autorizar imediatamente; **sem autorização residual**.

**Ambiente (D13):** produção **não recebe o efeito do mecanismo por padrão**
(critério de aceite). Recomendação preliminar: gate central de ambiente
(padrão `simulacaoDevPermitida`/`config/ambiente.ts`) no ponto que **ativa/
materializa/consome** D — o core/engine permanece puro (sem saber de ambiente);
o gate garante que em HOMOLOG/PROD nenhum grant D produza ALLOW, mesmo que um
assignment exista (fail-closed por ambiente). Registro de como o DEV pré-F5
materializa grants D sem fonte persistente (bootstrap DEV documentado, não
fonte soberana — D13/Q4).

## 8. Auditoria (D14)

Eventos separados (append-only, por user_profile, tenant, timestamp,
`grant_id`, perfil/versão):

- **(A) concessão:** concedente, beneficiário, quando, motivo, tenant, perfil/
  capabilities cobertas, vigência;
- **(B) renovação/extensão** (se existir — D9): quem/quando/até quando;
- **(C) revogação:** revogador (ou beneficiário renunciante), quando, motivo;
- **(D) expiração/invalidação:** derivada por data/membership inválida (sem
  job);
- **(E) uso efetivo:** operações que **dependeram de D** (A/B/C DENY → D ALLOW):
  grant, tenant, beneficiário, capability, target, contexto/ciclo, timestamp,
  origem `pilot:<grantId>`.

**Posse × uso:** "possui Pilot Full Access" (registro ativo) ≠ "operação
autorizada graças a D". Se A/B (ou C para confidencial) já autorizam, D não é
consumido e **não** há evento de uso D (sem dupla contagem). Decisão sobre
auditar **todo** uso via D (recomendação: sim — piloto deve registrar acessos
sensíveis; granularidade em D14/Q5).

## 9. Capabilities e allowlist do piloto (D1/D3/D16)

- Referência runtime: `src/authorization/Capability.ts` (dívida SQL×runtime
  mantida — F4-06 Q6);
- **Allowlist fechada** de capabilities piloto-elegíveis (perfil versionado);
  exclusões recomendadas por padrão: gestão de roles/access roles
  (`access_role.manage`, etc.), concessão de exceptional access
  (`exceptional_access.grant`), concessão de Pilot Full Access (a nova
  capability de concessão D), settings, operações de segurança, operações
  destrutivas amplas, mutação de histórico congelado;
- **Conteúdo confidencial:** decide em D3/D7/Q7 se a leitura confidencial
  (ex.: avaliação de terceiros) entra na allowlist D ou permanece somente com C;
- **Evolução futura (D16):** novas capabilities **não** expandem D
  automaticamente — perfil versionado + allowlist explícita no código + decisão
  explícita para incluir; snapshot `allowedCapabilities` no grant é alternativa
  a avaliar (Q9).

## 10. capability × target e DOMAIN_STATE (D4/D5)

- **D4 — capability × target permanece soberano:** D pode ampliar o **alcance**
  de uma capability permitida, mas **não** transforma combinação
  capability×target inválida em válida (semântica da capability preservada);
- **D5 — DOMAIN_STATE não é ignorado:** D amplia autorização, não remove
  invariantes do domínio (ciclo fechado, avaliação congelada, recurso histórico
  ou inativo, operação proibida por regra de domínio ⇒ continua DENY).

## 11. Histórico / F3-08 / F3-09 (D6)

F3-08/F3-09 soberanos. D pode receber **capabilities de leitura elegíveis**
(inclusive de histórico), mas **nunca** reescreve história/snapshots/autoria/
responsabilidade/sucessão por bypass; qualquer **mutação** histórica exige
decisão explícita (D6). Mesma fronteira vivo × congelado das F4-05 (D8/D9) e
F4-06 (D15).

## 12. Tenant (D11)

D é **tenant-scoped**: `beneficiary + organization`, `grantedBy +
organization`, alvo/request/membership na mesma organização; sem
`organization="*"`; um grant por (beneficiário, organização) (unicidade — D15);
o mesmo usuário pode ter grants D em mais de uma organização, cada um isolado
(decisão D11). Cross-tenant impossível.

## 13. listAllowedTargets (D8)

F4-06 decidiu que C **não** participa. Para D (decisão própria):

- **(A)** participa; **(B)** não participa; **(C)** participa somente para
  tipos/capabilities **explicitamente elegíveis** no perfil D e **nunca** para
  targets confidenciais.
- Recomendação preliminar: **(C)** — o objetivo do piloto é operar os fluxos
  (a UI precisa listar alvos operacionais), mas D **não** deve enumerar nem
  revelar conteúdo confidencial (que fica com C, e C não participa). `authorize`
  continua sendo a decisão real; a listagem com D continua sendo auxiliar.

## 14. Ambiente / produção (D13/Q4)

Padrão existente: `config/ambiente.ts` + gates `simulacaoDevPermitida`/
`resetDesenvolvimentoPermitido` (sempre false em HOMOLOG/PROD). Recomendação:
gate central de ambiente aplicado **no ato de ativar/materializar/consumir D**
(concessão e consumo); core/engine **puros** (não conhecem ambiente); em
produção o efeito de D é bloqueado mesmo que um assignment exista (fail-closed
por ambiente); o procedimento de **remoção ao encerrar o piloto** é parte da
entrega (D13/§22).

## 15. Runtime pré-F5 (D13/Q4)

Fontes persistentes (grants D, membership resolvida, gate de ambiente real)
não existem no runtime atual. Implementação futura: **core/provider puro e
testável** (entrada F3/F4-shaped + event sink in-memory), **sem** bootstrap por
cargo, **sem** allowlist fake de produção, **sem** localStorage como fonte
soberana, **sem** Supabase remoto; materialização DEV documentada e separada;
migração funcional (páginas/serviços) fica para F5.

## 16. F4-08 / RLS (requisitos, sem implementar)

A F4-08 deverá respeitar: RLS como última barreira (F4-03 §19); predicados
restritos derivados dos mesmos contratos (membership, grants D, scopes) sem
predicado "tudo"; deny-by-default nas tabelas de grants/eventos D com policies
mínimas; resolução server-side consumindo os **mesmos contratos**, com
revalidação atômica na mesma RPC/transação (F4-03 D9 — requisito F5/F4-08).
Nenhuma policy/RPC é escrita nesta atividade.

## 17. Procedimento de remoção do piloto (entrega da Issue)

Documentar e entregar na fase de implementação: passos para revogar/remover
todos os grants D (quem executa, capability necessária, motivo), comportamento
imediato (volta à autorização normal), verificação de ausência de autorização
residual, encerramento de bootstrap DEV e desativação do gate quando o piloto
terminar. Este documento registra o requisito; o procedimento detalhado é
produto da implementação (D13).

## 18. Matriz de testes (para a futura implementação)

Mínimo exigido (52 itens da Issue) + complementos; cada caso valida contrato
fechado, sem cargo, sem wildcard, sem expansão automática e sem ambiente:

1. grant D válido → ALLOW pilot (`pilot:<grantId>`);
2. grant futuro → DENY;
3. grant expirado → DENY;
4. grant revogado → DENY;
5. tenant diferente → DENY;
6. beneficiário diferente → DENY;
7. membership inativa → DENY (sem fallback);
8. profile inválido → DENY;
9. justificativa ausente → concessão rejeitada;
10. período inválido → rejeitado;
11. tentativa de grant permanente → rejeitada;
12. duração acima do máximo → rejeitada/limitada;
13. concessão por ator não autorizado → DENY/ForbiddenError;
14. auto-concessão → proibida;
15. revogação registrada (revogador/motivo/data);
16. revogação com efeito imediato (sem cache/job);
17. expiração entre duas operações → segunda DENY;
18. renovação/extensão gera evento novo (nunca edição silenciosa);
19. capability permitida pela allowlist → ALLOW via D;
20. capability excluída da allowlist → DENY via D;
21. capability desconhecida/nova → NÃO expande D (DENY);
22. capability × target inválido → TARGET_INCOMPATIBLE (D não torna válida);
23. DOMAIN_STATE proibindo → DENY (D não ignora);
24. histórico congelado → leitura somente;
25. leitura histórica elegível → ALLOW via D (quando na allowlist);
26. tentativa de mutação histórica → DENY;
27. A autoriza → ALLOW normal, D não consumido;
28. B autoriza → ALLOW temporário, D não consumido;
29. C autoriza (confidencial) → ALLOW excepcional, D não consumido;
30. D autoriza → ALLOW pilot + uso auditado;
31. A/B autorizam + D existente → D não consumido (sem evento de uso D);
32. C e D simultaneamente elegíveis → ordem C → D; uma única origem no
    diagnóstico; sem dupla contagem;
33. múltiplos grants D ativos → DENY (fail-closed) ou unicidade imposta (D15);
34. caller tentando selecionar grant → impossível;
35. caller tentando selecionar origem → impossível;
36. wildcard (target/capability/organização "*") → rejeitado;
37. cross-tenant → DENY;
38. auditoria da concessão;
39. auditoria da revogação;
40. auditoria da expiração/invalidação (derivada);
41. auditoria do uso efetivo (origem `pilot:<grantId>`);
42. operação normal NÃO consumindo D;
43. operação autorizada por D registrando origem;
44. listAllowedTargets (comportamento D — D8);
45. target confidencial (C/D — D3/D7/Q7);
46. target normal;
47. capability administrativa (fora da allowlist D → DENY);
48. capability de segurança/concessão (fora da allowlist D → DENY);
49. nova capability adicionada após criação do mecanismo → não expande D sem
    decisão (perfil versionado);
50. dados incompletos/ambíguos → DENY;
51. fail-closed (indeterminação ⇒ DENY);
52. ausência de cargo/job_role no caminho D.

Complementos: gate de ambiente (HOMOLOG/PROD bloqueia efeito de D mesmo com
assignment — Q4/D13); renúncia pelo beneficiário; um usuário com grants D em
duas orgs (isolamento); auditoria de uso D não duplica quando A/B autorizam;
remoção do piloto restaura autorização normal.

## 19. Riscos, dependências e itens fora de escopo

- **Riscos e mitigações:** (r1) Full Access permanente acidental → janela
  fechada obrigatória + duração máxima (D9); (r2) expansão automática por
  capability futura → perfil versionado/allowlist fechada (D16); (r3) vazamento
  de confidencial → ordem C antes de D e D fora de targets confidenciais
  (D3/D7/D8); (r4) bypass do engine → D é origem interna, gates globais
  preservados (D4/D5/D7); (r5) ativação em produção → gate de ambiente central
  (D13); (r6) mistura com C/F4-06 → origens e diagnósticos separados (D7);
  (r7) auditoria incompleta → eventos A–E com posse × uso (D14);
  (r8) escalada de segurança → capabilities de segurança/concessão excluídas
  (D3) e concessão sem cargo/ADMIN automático (D10).
- **Dependências:** F4-01 (roles/ADMIN D17/D18), F4-02 (scopes/tenant), F4-03
  (engine/gates/§21), F4-04 (capability×target), F4-05 (B), F4-06 (C e
  contratos D1–D20/Q1–Q8), F2-09/ambiente (gate DEV), F3-08/F3-09 (histórico),
  F4-08 (RLS futura), F5 (runtime).
- **Fora de escopo:** implementação, superadmin permanente, multiempresa em
  produção, compliance final, F4-08, correção do drift de vocabulário.

## 20. Questões para validação

> Dúvidas/ambiguidades que dependem de validação; quando também arquiteturais,
> aparecem em D1–D18 (§21). O desenho pode ser concluído com estas abertas;
> serão revisadas junto com as decisões.

- **Q1 — Propósito real do "full access" do piloto:** quais domínios a conta de
  piloto precisa operar para "validar todos os perfis e fluxos" (metas,
  avaliações, observações, ciclos, colaboradores, estrutura, relatórios)?
  Impacto: D3 (allowlist) e o alcance real de D. Recomendação preliminar:
  domínios funcionais atuais + ciclos; confidencial depende de Q7.
- **Q2 — Duração típica/máxima do período de piloto:** dias/semanas? Define a
  duração máxima default e o limite de extensões (D9).
- **Q3 — Quantas contas de piloto por organização/ambiente (1..n)? E o mesmo
  piloto em várias organizações sintéticas?** Impacto: D11 (múltiplos grants
  por usuário/org) e unicidade.
- **Q4 — Como o grant D é materializado no DEV pré-F5** (sem fonte persistente):
  assignment manual em memória? bootstrap DEV documentado? gate
  `simulacaoDevPermitida`-style? Impacto: D10/D13 e §15; confirmar que nenhuma
  allowlist fake vira fonte soberana.
- **Q5 — Auditoria de "acessos sensíveis" do piloto (Issue #94):** registrar
  **todo** uso via D, ou somente operações sobre targets sensíveis?
  Granularidade e volume. Recomendação preliminar: registrar todo consumo de D
  (origem `pilot:<grantId>`) — a Issue pede rastreabilidade do piloto.
- **Q6 — Renovação/extensão:** automática pelo concedente, limitada em número,
  ou novo grant a cada período? Impacto: D9 e auditoria B.
- **Q7 — O piloto precisa LER conteúdo confidencial (ex.: avaliação de
  terceiros) para validar os fluxos?** Se sim: via allowlist D (com auditoria de
  uso D) ou exigir grants C pontuais? Impacto: D3/D7 e a fronteira C×D; define
  se a leitura confidencial entra ou não na allowlist D.
- **Q8 — Confirmação da posição do gate de ambiente:** mesmo com assignment D em
  PROD, o EFEITO deve ser bloqueado (fail-closed por ambiente) — confirmar que o
  gate age no consumo, não apenas na concessão. Impacto: D13.
- **Q9 — Snapshot de capabilities no grant vs perfil versionado referenciado:**
  qual versão "vale" quando a allowlist evolui durante a vigência do grant?
  Recomendação preliminar: perfil versionado + allowlist explícita no código,
  com decisão explícita por mudança (D16).

## 21. Decisões arquiteturais (D1–D18 — ABERTAS)

> Nenhuma decisão é considerada automaticamente aprovada. Cada uma: problema,
> alternativas, recomendação, justificativa, riscos, impacto, dependências.

### D1 — Modelo de capabilities do "Full Access"

- **Problema:** o que "Full Access" concede em termos de capabilities.
- **Alternativas:** (A) todas as capabilities runtime automaticamente;
  (B) allowlist fechada de capabilities piloto-elegíveis; (C) meta-capability;
  (D) outro.
- **Recomendação:** (B) allowlist fechada (perfil versionado, D16).
- **Justificativa:** fail-closed, least privilege e sem expansão automática por
  capability futura (§3.1).
- **Riscos:** (A) expansão silenciosa e mistura com segurança/confidencial;
  (B) custo de manutenção da lista.
- **Impacto:** resolução da origem D; evolução futura; auditoria.
- **Dependências:** D3, D16, F4-06 Q6 (vocabulário).

### D2 — Representação da origem D (grant dedicado × role × flag)

- **Problema:** como modelar D nos contratos.
- **Alternativas:** (A) grant dedicado `PilotFullAccessGrant` (como C na F4-06);
  (B) role de sistema F4-01 + assignment com scope ORGANIZATION; (C) flag em
  membership; (D) híbrido.
- **Recomendação:** (A) grant dedicado por membership/org, com perfil de
  allowlist versionado — não usar a role `admin` (que não pode carregar
  confidencial por padrão, F4-01 D18) nem cargo.
- **Justificativa:** ciclo de vida/vigência/auditoria próprios e origem
  distinguível no engine.
- **Riscos:** duplicar conceitos com role? mitigado por ser origem nova com
  semântica própria; (B/C) misturam com A/ADMIN.
- **Impacto:** tipos/contratos; engine; concessão.
- **Dependências:** F4-01 D17/D18, F4-06 D19.

### D3 — Allowlist do piloto (incluições/exclusões; confidencial)

- **Problema:** quais capabilities entram; quais ficam excluídas.
- **Alternativas:** (A) funcional ampla sem segurança e sem confidencial;
  (B) incluir leitura confidencial; (C) incluir administração não-segura; etc.
- **Recomendação:** (A) inicial — excluir gestão de roles/access, concessão de
  C e de D, settings, segurança, destrutivas amplas e mutação histórica;
  confidencial decide em Q7 (alternativa B/C como extensão explícita).
- **Justificativa:** evitar auto-ampliação de segurança e manter C como trilha
  de confidencial.
- **Riscos:** piloto não conseguir validar domínio que depende de confidencial
  (Q7); allowlist desatualizada.
- **Impacto:** D1, D7, D8, auditoria.
- **Dependências:** Q1, Q7, F4-06 D18.

### D4 — capability × target sob D

- **Problema:** D pode tornar combinação capability×target inválida válida?
- **Alternativas:** (A) contrato soberano — D amplia alcance, não semântica
  (recomendada); (B) D ignora o contrato.
- **Recomendação:** (A).
- **Justificativa:** preserva a semântica da capability (F4-04 D18) e o
  fail-closed.
- **Riscos:** (B) quebra contrato fechado; nenhum para (A).
- **Impacto:** engine (5.1) inalterado.
- **Dependências:** F4-04 D18.

### D5 — DOMAIN_STATE sob D

- **Problema:** D pode ignorar regras de domínio?
- **Alternativas:** (A) nunca (recomendada); (B) para um subconjunto explícito.
- **Recomendação:** (A) — D amplia autorização, não remove invariantes.
- **Justificativa:** ciclo fechado/congelado/histórico/inativo continuam
  protegidos (F4-03 D9).
- **Riscos:** (B) criaria caminho de bypass de domínio.
- **Impacto:** passo 9 inalterado.
- **Dependências:** F4-03 D3/D9.

### D6 — Histórico F3-08/F3-09 sob D

- **Problema:** D pode ler/alterar histórico?
- **Alternativas:** (A) leitura elegível somente; mutação nunca (recomendada);
  (B) permitir mutação com regras fortes.
- **Recomendação:** (A) — snapshots/autoria/responsabilidade/sucessão soberanos.
- **Justificativa:** F3-08/F3-09 imutáveis; mutação = decisão explícita.
- **Riscos:** (B) reescrita de histórico.
- **Impacto:** allowlist D (sem mutação histórica); §11.
- **Dependências:** F3-08/F3-09, F4-05 D8/D9, F4-06 D15.

### D7 — Ordem C × D e diagnóstico

- **Problema:** posição da origem D; quando é consumida; como coexistir com C.
- **Alternativas:** (A) A/B → (confidencial: C) → D → DENY (recomendada);
  (B) D antes de C; (C) união.
- **Recomendação:** (A) — C antes de D para conteúdo confidencial; origem única
  por decisão; sem dupla contagem de uso.
- **Justificativa:** trilhas separadas (C = exceção pontual; D = piloto) e
  menor privilégio.
- **Riscos:** (B/C) misturam origens e duplicam auditoria.
- **Impacto:** pipeline (§5), diagnóstico (`pilot:<grantId>`).
- **Dependências:** F4-06 D6/D12, D3/Q7.

### D8 — listAllowedTargets sob D

- **Problema:** D participa da listagem auxiliar?
- **Alternativas:** (A) sim; (B) não; (C) somente para capabilities/tipos
  explicitamente elegíveis e nunca confidencial (recomendada).
- **Recomendação:** (C).
- **Justificativa:** o piloto opera fluxos (precisa listar alvos operacionais),
  mas D não revela inventário confidencial; `authorize` continua a única
  decisão (F4-06 D18 preservado para C).
- **Riscos:** (A) vaza inventário; (B) UX do piloto inviável.
- **Impacto:** listAllowedTargets.
- **Dependências:** F4-06 D18, D3.

### D9 — Vigência, duração máxima, extensão/renovação

- **Problema:** regras temporais do grant D.
- **Alternativas:** (A) janela fechada + duração máxima + extensões limitadas
  (recomendada); (B) aberto com revalidação; (C) novo grant a cada extensão.
- **Recomendação:** (A) com (C) quando a duração máxima for alcançada; sem
  permanente; expiração derivada por data (sem job).
- **Justificativa:** sem Full Access permanente acidental; rastreabilidade.
- **Riscos:** (B) esquecimento; (C) atrito.
- **Impacto:** concessão/renovação/auditoria B.
- **Dependências:** Q2, Q6.

### D10 — Concessão (quem/capability/controles)

- **Problema:** como o grant D é concedido.
- **Alternativas:** (A) capability nova `pilot_full_access.grant` por
  organization resolvida no engine (recomendada); (B) reusar outra capability;
  (C) regra externa.
- **Recomendação:** (A) — sem ADMIN automático, sem cargo, sem allowlist DEV
  soberana; auto-concessão proibida; justificativa obrigatória; início/fim
  obrigatórios; retroativo proibido; renovação conforme D9.
- **Justificativa:** ato administrativo explícito e auditado; separado de
  conteúdo (como F4-06 D3/D4).
- **Riscos:** multiplicação de capabilities (dívida de vocabulário mantida).
- **Impacto:** catálogo runtime futuro; serviço de concessão; auditoria A.
- **Dependências:** F4-06 D3/D5/Q6, D9.

### D11 — Identidade e tenant (beneficiário; múltiplas orgs)

- **Problema:** identidade soberana e vínculo com organização.
- **Alternativas:** (A) user_profile via membership, um grant por
  (usuário, org), múltiplas orgs permitidas com isolamento (recomendada);
  (B) um único grant global por usuário.
- **Recomendação:** (A) — consistente com F4-06 D19; sem `org="*"`.
- **Justificativa:** tenant isolation; membership ativa exigida (1–3).
- **Riscos:** (B) cross-tenant implícito.
- **Impacto:** shape do grant; unicidade; revogação automática por membership.
- **Dependências:** F4-02 (tenant), F4-06 D19, Q3.

### D12 — Revogação e renúncia

- **Problema:** quem remove D; efeitos.
- **Alternativas:** (A) concedente + ator com capability + renúncia pelo
  beneficiário (recomendada); (B) somente concedente.
- **Recomendação:** (A) — motivo obrigatório; efeito imediato; sem job/cache;
  membership/profile inválidos ⇒ não autoriza.
- **Justificativa:** "removível" explícito (Issue #94); renúncia dá controle ao
  beneficiário.
- **Riscos:** (B) menos flexível; (A) renúncia sem motivo? motivo obrigatório.
- **Impacto:** serviço; auditoria C.
- **Dependências:** D10, F4-06 D14.

### D13 — Gate de ambiente e runtime pré-F5

- **Problema:** como impedir ativação em produção e materializar D no DEV.
- **Alternativas:** (A) gate central de ambiente (padrão `simulacaoDevPermitida`)
  no ato de conceder E no consumo; core puro; bootstrap DEV documentado
  (recomendada); (B) gate só na concessão; (C) sem gate.
- **Recomendação:** (A) — HOMOLOG/PROD bloqueiam o EFEITO de D mesmo com
  assignment; sem fonte fake/localStorage soberana.
- **Justificativa:** critério de aceite "produção não recebe o bypass por
  padrão"; precedente F2-09.
- **Riscos:** (B) assignment residual em PROD autorizaria; (C) inaceitável.
- **Impacto:** §14/§15; procedimento de remoção (§17).
- **Dependências:** F2-09/ambiente, Q4/Q8.

### D14 — Auditoria e granularidade de uso

- **Problema:** eventos e granularidade do uso D.
- **Alternativas:** (A) todo consumo de D gera evento (recomendada);
  (B) somente targets sensíveis.
- **Recomendação:** (A) — com posse × uso; sem evento quando A/B (ou C)
  autorizam; origens separadas por categoria (A–E).
- **Justificativa:** Issue #94 pede registrar usos/acessos do piloto;
  rastreabilidade de quem "dependeu de D".
- **Riscos:** volume de eventos no piloto (aceitável; gate de ambiente limita).
- **Impacto:** event sink; contrato de uso.
- **Dependências:** Q5, F4-06 Q3/Q4.

### D15 — Persistência futura e unicidade

- **Problema:** schema futuro (sem migration agora) e anti-ambiguidade.
- **Alternativas:** (A) estado + eventos append-only, unicidade por
  (beneficiário, organização) ativo (recomendada); (B) tabela única.
- **Recomendação:** (A) — nunca apagar; múltiplos grants ativos conflitantes ⇒
  DENY/unicidade.
- **Justificativa:** determinismo (padrão F3-09/F4-06 D20).
- **Riscos:** (B) perde append-only.
- **Impacto:** F4-08; resolução.
- **Dependências:** F4-06 D20.

### D16 — Evolução futura (nova capability não expande D)

- **Problema:** como evitar que capability nova amplie D sem revisão.
- **Alternativas:** (A) perfil versionado + allowlist explícita no código +
  decisão explícita (recomendada); (B) snapshot `allowedCapabilities` no grant;
  (C) catálogo dinâmico.
- **Recomendação:** (A) com (B) opcional — ver Q9.
- **Justificativa:** fail-closed contra expansão automática.
- **Riscos:** (C) expansão acidental; (A/B) custo de manutenção/atualização.
- **Impacto:** resolução D; auditoria (versão usada).
- **Dependências:** D1/D3, Q9.

### D17 — Razão interna/diagnóstico da origem D

- **Problema:** distinguir internamente falhas/ALLOW de D sem vazar.
- **Alternativas:** (A) origem `pilot:<grantId>` no diagnóstico + razões
  internas opcionais nunca públicas (recomendada); (B) nenhuma distinção.
- **Recomendação:** (A) — contrato de erro seguro F4-03 preservado.
- **Justificativa:** auditoria/rastreabilidade; sem revelar existência.
- **Impacto:** types/diagnóstico.
- **Dependências:** F4-03 D6.

### D18 — Fronteira com F4-06/F4-07 e "não-wildcard"

- **Problema:** garantir que D nunca vire exceção-wildcard nem full access
  permanente.
- **Alternativas:** (A) allowlist fechada + janela + ambiente + concessão
  explícita + auditoria (recomendada); (B) deixar aberto para reavaliação por
  caso.
- **Recomendação:** (A) — C e D permanecem modelos separados; nenhum
  `target=*`/`capability=*`/`organization="*"`.
- **Justificativa:** Issue #94 (não superadmin, não permanente, remoção
  documentada).
- **Riscos:** qualquer relaxamento criaria bypass.
- **Impacto:** todo o contrato.
- **Dependências:** D1/D3/D9/D13.

## 22. Resumo para revisão

Para tornar este documento o contrato arquitetural da F4-07, a revisão deve
fechar **D1–D18** e responder **Q1–Q9**. Após o fechamento, a implementação
futura entregará: core/provider testável (grant D + perfil de allowlist
versionado + resolução no engine + eventos de auditoria A–E em memória), a
origem D no pipeline (§5), o comportamento de `listAllowedTargets` (D8) e o
gate de ambiente (§14) — sempre sem migration/RLS/DEFINER, sem cargo/job_role e
sem antecipar F4-08. Confirma-se: nenhum código/migration/RLS/`SECURITY
DEFINER` foi produzido nesta atividade (somente este documento).
