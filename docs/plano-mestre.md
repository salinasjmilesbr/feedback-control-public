# Plano Mestre — Virtus (v16)

> ## NOTA DE RASTREABILIDADE — LEIA ANTES DE USAR ESTE DOCUMENTO
>
> **(a) A numeração v16 vem do orquestrador.** As versões anteriores do Plano Mestre existem
> **fora deste repositório**; não há no repo nenhum artefato v1…v15 para comparar, e este documento
> **não** fabrica “o que mudou em relação à v15”.
>
> **(b) Dentro deste repositório, esta é a PRIMEIRA versão versionada do Plano Mestre.** O arquivo
> é novo (`docs/plano-mestre.md`).
>
> **(c) A única referência anterior no repositório** é uma citação de fonte, em
> `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:7` — “Fonte vigente para estado atual e
> próximos passos: Plano Mestre e contratos `docs/F5-XX-desenho-tecnico.md` fechados.” Ou seja: o
> Plano Mestre era **citado como fonte** sem estar versionado aqui.
>
> **(d) Por isso a v16 foi CONSTRUÍDA a partir das fontes vigentes do próprio repositório**, e não
> por cópia de uma versão anterior: `AGENTS.md`; `.ai/virtus-context.md`; `.ai/workflow.md`;
> `.ai/architecture-rules.md`; `.ai/git-rules.md`; `.ai/handoff.md`; `docs/etapa-5-certificacao.md`;
> `docs/F5-11-certificacao.md`; `docs/auditorias/*`; e os desenhos `docs/F3-*/F4-*/F5-*`.
>
> **Regra de manutenção:** este plano é **história + roadmap + manual operacional**. Ele **resume e
> aponta** para as fontes operacionais vigentes (`.ai/*`, desenhos, certificações) em vez de
> duplicá-las. Quando houver divergência entre este plano e uma fonte normativa, **prevalece a fonte
> normativa** (o desenho da atividade e `.ai/architecture-rules.md`) — e a divergência deve ser
> registrada aqui como item da Parte XVII.

| Campo | Valor |
|---|---|
| Versão | **v16** |
| Data-ação | Registro de governança documental da Issue #258 (reorganização do Plano Mestre) |
| Escopo | Reorganizar e preservar TODO o conhecimento vigente de doutrina, processo, roadmap e estado |
| Modelo | história + roadmap + manual operacional |
| Fontes | `.ai/*`, `AGENTS.md`, `docs/etapa-5-certificacao.md`, `docs/F5-11-certificacao.md`, `docs/auditorias/*`, desenhos `docs/F3-*/F4-*/F5-*` |
| Registro de dívidas | `docs/dividas-tecnicas.md` (canônico — **não enumerado nem duplicado aqui**) |
| Handoff operacional | `.ai/handoff.md` |

---

## Sumário

- [Parte I — História e evolução do Virtus](#parte-i--história-e-evolução-do-virtus)
- [Parte II — Roadmap completo](#parte-ii--roadmap-completo)
- [Parte III — Estado atual e próxima fase](#parte-iii--estado-atual-e-próxima-fase)
- [Parte IV — Princípios e regras imutáveis](#parte-iv--princípios-e-regras-imutáveis)
- [Parte V — Anti-overengineering](#parte-v--anti-overengineering)
- [Parte VI — Processo: Issue → … → main](#parte-vi--processo-issue----main)
- [Parte VII — Responsabilidades: Flash, GPT, Codex, orquestrador](#parte-vii--responsabilidades-flash-gpt-codex-orquestrador)
- [Parte VIII — Autonomia e regras de parada dos DEVs](#parte-viii--autonomia-e-regras-de-parada-dos-devs)
- [Parte IX — Regra de prompts curtos](#parte-ix--regra-de-prompts-curtos)
- [Parte X — Nota Flash obrigatória](#parte-x--nota-flash-obrigatória)
- [Parte XI — Git e GitHub](#parte-xi--git-e-github)
- [Parte XII — Estratégia de testes e gates](#parte-xii--estratégia-de-testes-e-gates)
- [Parte XIII — Custos e eficiência](#parte-xiii--custos-e-eficiência)
- [Parte XIV — Decisões arquiteturais transversais vigentes](#parte-xiv--decisões-arquiteturais-transversais-vigentes)
- [Parte XV — Dívidas técnicas e regra dívida → Issue](#parte-xv--dívidas-técnicas-e-regra-dívida--issue)
- [Parte XVI — Handoff](#parte-xvi--handoff)
- [Parte XVII — Contradições e divergências registradas](#parte-xvii--contradições-e-divergências-registradas)

---

## Parte I — História e evolução do Virtus

### I.1 O produto
O **Virtus** (Vivo Virtus / repositório `feedback-control`) é uma aplicação de **gestão de avaliações,
observações, metas e estrutura organizacional**. Stack principal: **React 19**, **TypeScript ~6.0.2**,
**Vite 8.3.0**, **Vitest 4.1.11**, **ESLint 10**, React Router, jsPDF; backend **Supabase** (Auth +
Postgres/RLS), ambiente local em Docker (`supabase_db_feedback-control`), PostgreSQL 17.6, CLI
`npx --yes supabase@2.116.0`. Detalhes estáveis: `.ai/virtus-context.md`.

### I.2 De onde veio (a virada de doutrina)
O sistema nasceu com **estado de domínio no navegador** (localStorage) e evoluiu para uma
arquitetura em que **PostgreSQL/RLS/RPC são a única autoridade**. Essa virada é o eixo da história do
projeto e está registrada em três movimentos:

1. **F1–F3 — fundação e modelagem:** base da aplicação, identidade/membership e estrutura
   organizacional (organizações, colaboradores, posições, ocupações, reporting line). Ainda conviviam
   com acervo local.
2. **F4 — autorização:** catálogo de capabilities, roles, assignments, **scopes**, RLS como barreira,
   trilha de auditoria de privilégios e o **Policy Engine** com `authorize()`/`can()`. É aqui que a
   doutrina “auth.uid() soberano + tenant server-side + fail-closed + cross-tenant DENY” se
   materializa em código e em banco.
3. **F5 — dados soberanos, fase a fase:** cada domínio de negócio deixou de ler/gravar o acervo local
   e passou a operar por **Edge Function → gate por operação → RPC soberana → RLS**. A **Etapa 5** é
   exatamente essa travessia: **ciclos (F5-09), colaboradores/histórico (F5-07/F5-08) e
   metas/observações (F5-10/F5-11)** — os três “blockers” históricos da Etapa 5 — mais a
   infraestrutura transversal (F5-01 a F5-06).

### I.3 O que mudou de doutrina ao longo do tempo (síntese)
| Antes | Depois (vigente) |
|---|---|
| Estado de domínio no navegador como fonte | **PostgreSQL/RLS/RPC como autoridade**; navegador só apresenta intenção |
| Autorização decidida na tela | **Policy Engine soberano**; `authorize()` = enforcement, `can()` = **UX** |
| Papel/role inferido por nome ou cardinalidade | **Capability + grant + scope explícitos**; membership **não** define papel |
| Concessão ampla por perfil único | **Perfis de sistema específicos** com conjunto EXATO de capabilities e guardas fail-closed |
| Trilha de auditoria com ator humano presumido | Trilha **append-only** com **ator humano obrigatório** para mutação humana e **ator sistêmico explícito** para mutação automática |
| Migração de dados locais para o banco | **Sem migração de `localStorage`** (D13): o acervo legado é barrado e vira somente-leitura |
| Correções por exceção local | **Fronteira de confiança única**: Edge valida JWT, allowlist estrita, tenant e gate antes de qualquer execução privilegiada |

### I.4 A centralidade da certificação
A F5 (Etapa 5) fechou com **certificação documental e por gates** (`docs/etapa-5-certificacao.md`,
`docs/F5-11-certificacao.md`), e não por “sensação de pronto”. A regra que ficou: **toda obrigação
assumida precisa de evidência citável** (arquivo:linha, bloco de validador, passo de CI, teste,
registro de gate) — o que não tem evidência é **dívida** ou **lacuna**, nunca “feito”.

---

## Parte II — Roadmap completo

### II.1 Concluído
| Etapa | Conteúdo | Estado |
|---|---|---|
| **F1** | Fundação da aplicação e modelagem inicial | Concluída |
| **F2** | Identidade, perfis, memberships e vínculos | Concluída |
| **F3** | Estrutura organizacional (organização, colaboradores, posições, ocupações, reporting line, histórico) | Concluída |
| **F4-01 … F4-10** | Autorização: catálogo de capabilities, roles/assignments/scopes, RLS, trilha de privilégios, Policy Engine, guardas de estrutura de UI, mutações/cutovers | Concluída |
| **F5-01 … F5-06** | Dados soberanos: identidade coerente, vínculos, memberships/concessões administrativas, catálogo/trilha, Policy Engine em fronteira (contexto real), avaliações | Concluída |
| **F5-07 / F5-08** | Colaboradores e histórico organizacional soberanos + cutover | Concluída |
| **F5-09** | Ciclos soberanos (incluindo P9 com matriz integrada e pares de concorrência) | Concluída |
| **F5-10** | Metas soberanas (P1–P7, matriz integrada) | Concluída |
| **F5-11** | Observações soberanas: P1, P1.1, P2, P3, P4, P5, P5.1, P5.2, P5.3, P5.4 e P6 (certificação integrada) | Concluída |
| **Etapa 5 — certificação transversal** | Issue #256 = **F5-12**: validação integrada e fechamento da Etapa 5 (matriz B1–B3, T1–T11, R1–R10) | Concluída; ver Parte III |

Detalhamento por fase (critérios, decisões, evidências): `docs/F5-01-desenho-tecnico.md` …
`docs/F5-11-desenho-tecnico.md`, `docs/F5-09-p9-matriz-integrada.md`,
`docs/F5-10-p7-matriz-integrada.md`, `docs/F5-11-certificacao.md`, `docs/etapa-5-certificacao.md`.

### II.2 Planejado
Roadmap **até produção**. As etapas abaixo vêm do **Plano Mestre externo v15** (que **não** está
versionado neste repositório — ver Parte XVII, item 5) e a v16 as traz por decisão do orquestrador,
sem inventar detalhe além do que o roadmap vigente define. Notação única: **Etapa N (FN)**.

| Etapa | Conteúdo esperado | Observação |
|---|---|---|
| **F5-12 (Issue #256)** | Validação integrada e fechamento formal da Etapa 5 | **É a certificação transversal já produzida** — não há fase posterior de fechamento dentro da F5 |
| **Etapa 6 (F6)** | **Auditoria visual/funcional READ-ONLY**, classificando cada achado como **QUEBRADO**, **REGRESSÃO** ou **MELHORIA**, com **consolidação de causas ANTES de criar trabalho** (nenhuma correção começa antes da consolidação) | **Próxima fase.** Escopo definido pelo roadmap vigente; exige Issue + desenho fechado (Parte VI) |
| **Etapa 7 (F7)** | **Segurança/hardening para produção** | Escopo definido pelo roadmap vigente; exige Issue + desenho fechado |
| **Etapas 8–10 (F8–F10)** | **Arquitetura-alvo**, **migração**, **pré-produção** e **produção** (posteriores) | Vêm do roadmap vigente; o detalhamento exige Issue + desenho próprios e **não** é fabricado nesta v16 |
| Backlog: dívidas e findings bloqueantes | Limpeza de resíduos legados, provas literais faltantes, defeitos de diagnóstico; **findings bloqueantes** (hoje: **nenhum em aberto** — o `DT-013` foi resolvido pela Issue #260 / PR #261) | Registro canônico: `docs/dividas-tecnicas.md` (seção de **FINDINGS BLOQUEANTES**); conversão em Issue só por decisão explícita (Parte XV) |

### II.3 Próxima fase
**A próxima fase é a Etapa 6 (F6): auditoria visual/funcional READ-ONLY**, que classifica cada achado
como **QUEBRADO**, **REGRESSÃO** ou **MELHORIA** e **consolida as causas antes de criar qualquer
trabalho** — nenhuma correção começa antes dessa consolidação. O que já está pronto para alimentá-la é
o **insumo documental**: a matriz da Etapa 5, o registro de dívidas/findings e o handoff. Como
qualquer fase, começa obrigatoriamente por **Issue + desenho fechado** (Parte VI).

---

## Parte III — Estado atual e próxima fase

### III.1 Certificado
- **Etapa 5 certificada transversalmente** (`docs/etapa-5-certificacao.md`): os três blockers
  históricos — **B1 ciclos**, **B2 colaboradores/histórico**, **B3 metas/observações no PostgreSQL** —
  estão **demonstrados** com evidência reutilizada (validadores, passos de CI, matrizes e
  certificações já produzidas), e as obrigações transversais **T1–T11** (trust boundaries, D1–D22,
  RLS/policies, ACL/grants, auditoria append-only, idempotência/concorrência, multi-tenant/IDOR,
  fail-closed, guardas de UI, CI completo e coerência promessa × prova) têm evidência citável.
- **F5-11 certificada** (`docs/F5-11-certificacao.md`), com a **emenda de D15** registrada no desenho
  (§24) e a cadeia de validadores `34…43` verde.
- **Nenhuma lacuna material bloqueante** foi encontrada na certificação transversal.

### III.2 Pendente de CI/PR/merge
- O **CI oficial do PR/SHA** é a **autoridade final** (em especial para os pares de concorrência) e é
  responsabilidade do **orquestrador** — as certificações registram isso explicitamente.
- **PR e merge são do orquestrador** (`gh` ausente no ambiente do agente; DEV-04): o agente entrega
  branch + SHA + título/corpo quando não há mecanismo autorizado de abertura de PR.
- **Estado da `main` de referência deste registro:** `f8bf8e33429b11d66e0f8ac9c7bf617c9b2788af`, com
  **CI #306 verde** (squash do PR #261 — correção do import da Edge `avaliacoes`, DT-013).
- **Esta branch (`docs/governanca-v16`, PR #259) segue ABERTA e não mergeada** — pode estar à frente
  da `main` acima; nenhum resultado de CI é afirmado aqui para esta branch.

### III.3 Dívida e findings (resumo; lista canônica em `docs/dividas-tecnicas.md`)
Resíduos legados de ciclo em módulos de apresentação (incluindo o caso **R1**, agora **verificado e
fechado** como não-autoritativo, restando limpeza de UX), `localCycleRepository` legado por decisão,
fixtures de teste que pré-carregam chaves locais, provas literais ainda ausentes em validadores e um
defeito latente de **diagnóstico** em validador da F5-11. O **finding BLOQUEANTE** registrado
(Edge `avaliacoes` com import de módulo inexistente — `DT-013`) foi **RESOLVIDO pela Issue #260 /
PR #261** (squash-merged; `main` = `f8bf8e33429b11d66e0f8ac9c7bf617c9b2788af`; **CI #306 verde**) e
**não há findings bloqueantes abertos**. Classificação e detalhes: Parte XV e o registro canônico de
dívidas (`docs/dividas-tecnicas.md`, seção **FINDINGS BLOQUEANTES**).

---

## Parte IV — Princípios e regras imutáveis

1. **`auth.uid()` é a raiz soberana de identidade.** Nenhum identificador de ator vem do corpo, do JWT
   como dado de negócio, do `localStorage` ou do payload.
2. **Tenant sempre validado server-side.** Organização/membership são revalidadas na fronteira em toda
   operação; divergência ⇒ recusa.
3. **O Policy Engine é o gate soberano de autorização.** `authorize()` é **enforcement**; `can()` serve
   **somente à UX**. Ocultar elemento na interface **não é** autorização efetiva.
4. **RLS é barreira de segurança** (F4-08). Tabelas autorizativas são fechadas; nenhum
   `SECURITY DEFINER` novo sem necessidade explícita e comprovada.
5. **Fail-closed.** Ausência, erro, incoerência ou ambiguidade de dado soberano ⇒ **recusa**, nunca
   “permite por default”. Probe/estado derivado de linha soberana; estado declarado pelo chamador
   **nunca** é autoridade.
6. **Cross-tenant DENY** e alvo sempre por `(id, tenant)`, com recusa **indistinguível** (sem oráculo
   de existência).
7. **Não duplicar regra de autorização** em páginas/componentes: use a policy e as capabilities
   centrais de `src/authorization`.
8. **Preservar a separação** entre autorização, workflow, cálculos, persistência e auditoria; preservar
   históricos e trilhas.
9. **Nenhum dado pessoal ou corporativo real** em código, fixtures, testes, documentação, commits ou
   PRs — somente dados fictícios.
10. **Contratos F4/F5 não se alteram** sem atividade explicitamente destinada a isso. Decisões `D#`
    fechadas e questões `Q#` encerradas não se reabrem sem **evidência técnica nova**.
11. **Backend é a autoridade**; o cliente declara **intenção**, nunca estado/autoria/tenant/versão.

Fonte normativa detalhada: `.ai/architecture-rules.md` e `AGENTS.md` §3.

---

## Parte V — Anti-overengineering

**Regra explícita e vinculante:** a menor solução compatível com a arquitetura existente.

1. **Reutilizar antes de criar.** Procure o mecanismo, perfil, helper, validador ou superfície já
   existentes antes de propor qualquer artefato novo.
2. **Sem abstração especulativa.** Nada de camada/indireção “para o futuro”, nada de generalização
   sem segundo consumidor real.
3. **Sem refatoração oportunista.** Refatoração só quando for **requisito** da atividade; “aproveitar
   para melhorar” é mudança de escopo.
4. **Sem duplicação de autoridade.** Uma decisão, um lugar: se a decisão é soberana (Policy Engine
   servidor, RLS, RPC), a UI não pode manter uma segunda regra decidindo o mesmo.
5. **Sem novo `SECURITY DEFINER`, sem advisory lock, sem DELETE físico de registro auditável**, sem
   mecanismo novo quando o existente resolve.
6. **Melhoria não é trabalho.** Melhoria identificada vira **dívida registrada** (Parte XV), não
   tarefa dentro da atividade corrente.
7. **Orçamento de mudança:** se a solução exige mudar contrato fechado, criar capability/role,
   reabrir `D#` ou enfraquecer gate, **pare e reporte** (Parte VIII).

---

## Parte VI — Processo: Issue → … → main

Fluxo oficial (detalhamento em `.ai/workflow.md`):

**Issue → branch → desenho/revisão → implementação → validação local → commit/push → PR → CI →
auditoria (GPT) / revisão (Codex) → squash merge em `main` → auditoria final.**

| Passo | Papel |
|---|---|
| **Issue** | Fonte de verdade do requisito e do escopo. Nada começa sem Issue (ou ordem explícita do orquestrador, com o desvio **registrado**, nunca oculto). |
| **Branch** | Uma branch por atividade; **desenho e implementação em branches separadas**; nomes por tipo (`feat/`, `docs/`, `fix/`). |
| **DEV-02** | **Agrupar execuções privilegiadas**, nunca relaxar controles: ler/analisar → implementar em lote → autoauditoria estática → **gate privilegiado integrado** → correções em lote → gate final. O antipadrão `editar → elevar → testar` repetido é proibido. |
| **DEV-03** | **Validação progressiva**: testes focados durante o desenvolvimento; **análise estática transversal antes de novos gates**; full gate reservado ao fechamento. |
| **DEV-04** | Com implementação e gates locais **verdes e sem blocker**: **commit + push e PR imediatamente** (`Closes #n` quando resolver integralmente). Se não houver mecanismo autorizado de PR, **não contorne** (nada de `gh`, PAT ou credencial): entregue **branch, SHA, título e corpo** e informe que o PR será aberto pelo orquestrador. CI antecipado; correção posterior gera **novo SHA com novo CI**. |
| **Gates** | Obrigatórios no fechamento: `npm test`, `npm run build`, `npm run lint`, `git diff --check` (+ cadeia de validadores da fase, quando aplicável). |
| **PR / CI** | PR auditável, CI verde no **SHA auditado**. |
| **Auditorias** | **GPT** audita; **Codex** revisa antes do merge; findings são tratados como itens com classificação (bloqueante / dívida / fora de escopo). |
| **Squash merge** | Somente com **CI verde e SHA auditado**, executado pelo **orquestrador**. **O agente de implementação nunca faz merge.** |
| **Dependabot/PRs de dependência** | Fora de atividades estruturais. |

---

## Parte VII — Responsabilidades: Flash, GPT, Codex, orquestrador

| Papel | Quem é | Responsabilidade |
|---|---|---|
| **Flash (DEV de implementação)** | Agente de implementação (modelo `deepseek-flash`) | Lê as fontes obrigatórias, implementa o lote aprovado, roda validação progressiva, **autoauditoria estática**, autua as **Notas Flash** (Parte X), registra desvios/dívidas e **nunca faz merge**. |
| **GPT (auditor)** | Auditor externo | Auditoria final: confronta o **SHA auditado** com o contrato e a Issue, verifica evidência × obrigação, aponta findings com severidade (bloqueante/dívida/fora de escopo). |
| **Codex (revisor)** | Revisor pré-merge | Revisão de código/contrato antes do merge; aponta defeitos materiais (segurança, autorização, integridade, contrato). |
| **Orquestrador** | Humano, autoridade decisória | Cria Issues e PRs, decide arquitetura (abre/fecha `D#`/`Q#`), **autoriza elevação de acesso**, aprova exceções, define escopo/fase, executa **squash merge** e o **CI oficial** é sua responsabilidade. |

Regra de ouro: **nenhum agente se autoconcede autoridade** — nem técnica, nem de elevação de acesso.

---

## Parte VIII — Autonomia e regras de parada dos DEVs

### VIII.1 O que o DEV corrige sozinho
Findings **locais e inequívocos**: implementação, fixture, harness, sintaxe/compilação, expectativa de
teste **comprovadamente** errada, nomes/assinaturas que divergem do contrato já fechado, ajustes de
diagnóstico — sempre **sem** alterar contrato, sem enfraquecer guarda e sem ampliar escopo.

### VIII.2 Quando PARAR e reportar (não decidir)
1. **Dúvida material de arquitetura/contrato** não coberta pelo desenho fechado.
2. **Segurança/autorização/RLS/integridade** com risco material, ou qualquer suspeita de escalada.
3. **Necessidade de alterar D1–D16/D21/D22** (ou qualquer `D#`) — inclusive **D15**.
4. **Criar capability nova**, role/perfil novo **fora do aprovado**, ou reabrir mapa fechado.
5. **Ampliar SELF para mutação** (SELF só lê o que lhe foi comunicado; mutação SELF é proibida).
6. **Enfraquecer qualquer gate** (validação, guarda, RLS, ACL, allowlist).
7. **Alteração de escopo** ou trabalho que exija mudar contrato fechado.
8. **Causa-raiz incerta**, ou duas falhas da **mesma classe** sem análise transversal prévia.

### VIII.3 Forma de parar
Parar **no ponto exato**, com **evidência arquivo:linha**, o que está bloqueado, o que **não** foi
alterado e as opções viáveis — sem implementar a parte controversa. Se o restante da atividade for
independente, **conclua o restante**.

---

## Parte IX — Regra de prompts curtos

**Defeito conhecido:** prompts gigantes **degradam a execução** — o executor perde foco, mistura
escopos e aumenta a chance de erro e de retrabalho.

**Regra:** prompts **enxutos e completos**:
1. **Objetivo em 1–3 frases** no topo (o que é “pronto”).
2. **Escopo e não-escopo explícitos** (o que NÃO fazer).
3. **Restrições duras** em lista curta (contrato, segurança, gates, arquivos permitidos).
4. **Entregáveis numerados** e, quando existirem, o **formato do relatório**.
5. **Apontar fontes** por caminho (contrato, desenho, molde) em vez de recolar conteúdo.
6. **Sem história da conversa**: só o contexto necessário para decidir.
7. **Regras de parada** (Parte VIII) citadas, não reproduzidas.
8. **Um lote por prompt**: mudanças grandes se dividem em lotes verificáveis.

---

## Parte X — Nota Flash obrigatória

**O que é:** nota curta e estruturada que **fecha toda entrega** do DEV de implementação (Flash),
anexada ao relatório final da atividade e refletida no handoff/PR.

**Quando é exigida:** em **toda** entrega (implementação, correção delta, documentação de
certificação) — inclusive quando a atividade termina sem código.

**Formato (mínimo, em bullets):**
1. **Branch e SHA** (base e head), e se houve push.
2. **Arquivos** criados/alterados (com o que mudou em cada um).
3. **Gates executados e resultados** (com os números reais; se não executou, dizer explicitamente).
4. **Decisões tomadas** dentro da autonomia (e o fundamento).
5. **Desvios/limitações do ambiente** (ex.: runner de shell indisponível, `gh` ausente).
6. **Findings e dívidas** classificados (bloqueante / dívida / fora de escopo).
7. **O que ficou pendente** e **quem** deve agir (orquestrador, próxima fase).

Sem nota Flash, a entrega **não é considerada fechada**.

---

## Parte XI — Git e GitHub

Fonte detalhada: `.ai/git-rules.md`.

1. **Uma branch por atividade**, criada da base indicada (normalmente `origin/main`), com prefixo de
   tipo (`feat/`, `docs/`, `fix/`).
2. **Desenho e implementação em branches/PRs separados**; nunca no mesmo PR.
3. **Commits objetivos**, no padrão do histórico (`feat(F5-11): … (#n)`, `fix(#n): …`, `docs(F5): …`).
4. **O agente nunca faz merge**; **squash merge** em `main` é do orquestrador, com CI verde e SHA
   auditado.
5. **DEV-04:** com gates verdes, **commit + push + PR imediatamente**; se não houver mecanismo
   autorizado de PR, entregar **branch + SHA + título/corpo** e registrar a limitação.
6. **CI associado ao SHA do PR.** Correção posterior ⟹ **novo SHA + novo CI**.
7. **Limitações do ambiente** (registradas nas entregas): `gh` **ausente** — o agente **não** cria
   Issue/PR e **não** contorna com PAT/credencial; e o *runner* de shell do host pode estar
   indisponível, exigindo elevação para comandos triviais (limitação de ambiente, não fluxo normal).
8. **Nunca** reescrever história publicada sem necessidade explícita; se houver reescrita (ex.:
   mensagem de commit errada em branch recém-criada, sem PR/CI), **registrar** o SHA antigo e o novo.
9. **Não** commitar artefatos de gate/uso interno (scripts locais, logs).

---

## Parte XII — Estratégia de testes e gates

1. **Focado durante o desenvolvimento; full gate no fechamento** (DEV-03). Não repetir gates **sem
   informação nova**.
2. **Cadeia de validadores por fase** em `supabase/validacao/` (cenário + validador, com `[PASS]`/
   `[FAIL]` e fail-fast): a fase da F5-11 usa a cadeia **`34…43`**; cada fase tem a sua, e o CI roda a
   cadeia na **ordem exata** dos steps.
3. **Gates de fechamento obrigatórios:** `npm test`, `npm run build`, `npm run lint`,
   `git diff --check` — e, quando a atividade tocar banco/RLS/autorização, o **gate de banco**
   (`db reset` + cadeia da fase via `psql` no container).
4. **Pipeline CI-equivalente**: reproduz os steps do `.github/workflows/ci.yml` **na ordem** (inclui
   reaplicação de migration para idempotência e **pares de concorrência reais**).
5. **Pares de concorrência**: exigem **duas sessões simultâneas** (sessão A em background e sessão B
   em foreground, dentro da janela do `pg_sleep`). No **harness local** isso é aproximado (A em
   background + dianteira de alguns segundos) e pode produzir **flake de medição** (ex.: espera de
   1,954 s contra limiar de 2 s); a **autoridade** é o CI.
6. **Testes do cliente**: Vitest, com guardas estruturais sobre o **fonte real** (`?raw`) para
   fronteiras (proibir `.rpc(`, credencial de serviço, `localStorage` em módulo de produção, decisão
   de autorização na UI). Ao casar texto, **remover comentários** antes (falso positivo é classe
   recorrente) e **nunca** afrouxar a asserção para “passar”.
7. **Falhas pré-existentes conhecidas** (fora do escopo das atividades): 2 falhas de
   **Windows/CRLF** em `AcompanhamentoMetasPage.test.tsx` e `MinhasMetasPage.test.tsx` — as suítes
   devem tolerar **apenas** essas, e nenhuma nova.
8. **Regra de ouro dos gates**: gate vermelho **não** se contorna; corrige-se a causa (código ou
   expectativa comprovadamente errada).

---

## Parte XIII — Custos e eficiência

1. **Não repetir gate sem informação nova** (ex.: mudança somente documental não justifica re-rodar o
   pipeline de banco já certificado na mesma árvore de código).
2. **Agrupar execuções privilegiadas** (DEV-02): um gate integrado em vez de N chamadas.
3. **Reaproveitar evidência certificada**: certificações e matrizes já produzidas são **prova
   reutilizável**; não refazer teste para “gerar prova nova”.
4. **Custo de contexto é custo real**: prompts curtos (Parte IX), leitura por `grep`/glob antes de ler
   arquivos inteiros, delegação de tarefas autocontidas, evitar reabrir arquivos grandes.
5. **Falhar barato e cedo**: validação progressiva e fail-fast na cadeia de validadores.
6. **Registrar limitações de ambiente** em vez de gastar rodadas contornando-as.
7. **Snapshot de consumo da API (informado pelo orquestrador):** total **US$ 69,68**; saldo
   **US$ 9,31**; últimos **7 dias US$ 29,39**; **13.744 requests**; **4.518.439.425 tokens**. O saldo
   é o recurso mais escasso do projeto e reforça as regras 1 a 4 desta parte (não repetir gate sem
   informação nova, agrupar execuções, reaproveitar evidência certificada e conter contexto).

---

## Parte XIV — Decisões arquiteturais transversais vigentes

> **Fonte normativa:** a enumeração canônica de `D1…D22` está nos desenhos `docs/F5-01-desenho-tecnico.md`
> e `docs/F5-02-desenho-tecnico.md` (e correlatos). Esta parte **não reenumera** todas as decisões para
> não criar segunda verdade; registra as **vigentes e transversais**, com a evidência disponível no
> repositório.

### XIV.1 Decisões transversais em vigor (com evidência)
| Decisão | Conteúdo vigente | Evidência no repo |
|---|---|---|
| **D3 / D4** | Identidade e **autoria** nunca vêm do corpo: o autor é a linha soberana, comparada ao vínculo do ator | validadores da F5-11 (autoria D5) e trigger de coerência de identidade da P1.1 |
| **D5** | **Só o autor** edita/exclui/revoga/comunica a própria linha — inclusive contra outro ator do mesmo tenant | gate `f5_11_exigir_autorizacao_observacao`; espelho no Policy Engine |
| **D7 / D8 / D9** | Comunicado é transição da própria capability de edição; leitura SELF só do **comunicado e não excluído** | RPCs de observação; matriz §8 |
| **D10** | Concorrência por **`expected_version` + `SELECT … FOR UPDATE`**, **sem advisory lock**; idempotência por `operation_id` (+ `payload_hash`); replay idêntico devolve o mesmo resultado | RPCs da F5-10/F5-11; upsert único antirracismo da P5.4 |
| **D11** | Estado do colaborador (status vigente por período) participa do gate; ausência ⇒ **DENY** | helper de status vigente; matriz D11 |
| **D12** | Estado do **ciclo** participa do gate: mutação exige ciclo ativo; leitura histórica permitida | matriz D12 |
| **D13** | **Sem migração de `localStorage`**: o acervo legado é barrado (somente leitura) e não é autoridade | barreira de escrita local; guarda de estrutura de UI |
| **D15 (EMENDADA)** | Concessão de `observation.*` por **perfis de sistema**: `observacoes_gestor` (gestão) e **`observacoes_avaliado`** (SELF, **exatamente** `observation.read`, **sem** scope, provisão **automática** por elegibilidade). `admin` permanece com **zero** `observation.*` | migration da P5.1 + emenda registrada no desenho (§24) + provas nos validadores |
| **D16 / catálogo fechado** | Mapa **fechado** de capabilities (31 códigos físicos); `admin` não recebe capability de leitura de conteúdo; perfis de sistema têm **conjunto exato** com guarda fail-closed | migrations de catálogo/perfis; validadores `35/37/39/41` |
| **D18** | Trilha de privilégios **append-only**; mutação **humana** exige **ator humano** (não nulo); mutação **sistêmica** grava `system_grant`/`system_revoke` com **ator NULL** (constraint discriminante bicondicional); **proibido** UUID sentinela ou beneficiário como ator | migration da P5.1 (D18) + P5.2 (admin por role) + P5.4 (exclusividade automática) |
| **D19 / D21 / D22** | Alvo autorizável obrigatório (alvo legado/global nunca autoriza); data de negócio e **instante soberano** server-side; relação/alcance por relação estrutural (união `DIRECT_REPORTS ∪ DESCENDANTS`) | validações de alvo/gate; contratos transportáveis (allowlist estrita, sem autoria/tenant/estado/instante) |

### XIV.2 Emendas registradas
- **Emenda de D15 (F5-11 P5.1):** passam a existir **dois** perfis de sistema com `observation.*`
  (`observacoes_gestor` e `observacoes_avaliado`), com a concessão SELF **automática** por
  elegibilidade (membership ativa + perfil ativo + vínculo ativo) e **sem scope assignment**. A guarda
  *point-in-time* da P3 (“única role com `observation.*`”) fica **superseded** pela emenda — registrado
  no desenho para não parecer contradição.
- **Emenda de autoridade administrativa (F5-11 P5.2):** `usuario_eh_administrador` passa a exigir a
  **role `admin`** explicitamente (não “qualquer role de sistema”), fechando escalada de privilégio.
- **Emenda de lifecycle (F5-11 P5.3):** mudança isolada de `user_profiles.status` passa a **propagar**
  o provisionamento (revoga/reativa a mesma assignment), reutilizando a **mesma** regra de
  elegibilidade.
- **Emenda de exclusividade (F5-11 P5.4):** `observacoes_avaliado` é **exclusivamente automática** —
  grant/revoke humano é **bloqueado** no caminho administrativo; a automação só altera assignment
  `origin='system'` e **falha** em colisão com `origin='human'`; a corrida do primeiro provisionamento
  é resolvida por **upsert único** (sem advisory lock), com evento apenas na transição vencedora.

---

## Parte XV — Dívidas técnicas e regra dívida → Issue

1. **Registro canônico:** `docs/dividas-tecnicas.md` (artefato de governança criado em atividade
   paralela desta mesma rodada). Este plano **não enumera** nem duplica identificadores de dívida —
   consulte o registro.
2. **Regra dívida → Issue (vinculante):**
   - **Dívida NÃO é Issue.** Dívida é **registro**;
   - uma dívida vira Issue **somente por decisão explícita do orquestrador**;
   - ao virar Issue, o identificador da dívida vai **no título** (ex.: `DT-xxx`), garantindo
     rastreabilidade registro ↔ Issue ↔ PR;
   - nenhum agente cria Issue por conta própria, e nenhum agente converte dívida em trabalho dentro de
     uma atividade em curso (Parte V, item 6).
3. **Natureza dos itens vigentes** (resumo qualitativo, sem IDs): resíduos legados em módulos de
   apresentação; leitores legados declaradamente LEGADO; fixtures que pré-carregam chaves locais;
   provas literais ainda ausentes em validadores; defeito latente de **diagnóstico** em validador;
   cenários de validação que derivam tenant de fase anterior.
4. **Nem todo item registrado é dívida aceita.** O registro separa duas coisas: **dívidas** (não
   bloqueantes, aceitas) e **FINDINGS BLOQUEANTES** — defeitos funcionais concretos e demonstrados,
   que **exigem Issue e correção antes do fechamento** da atividade correspondente. Um finding
   bloqueante **não** pode ser tratado como dívida nem silenciado por conveniência de cronograma
   (o único registrado até aqui, `DT-013` — Edge `avaliacoes` com import de módulo inexistente —, foi
   **resolvido pela Issue #260 / PR #261**, squash-merged em `main`
   `f8bf8e33429b11d66e0f8ac9c7bf617c9b2788af` com **CI #306 verde**; **não há findings bloqueantes
   abertos**).

---

## Parte XVI — Handoff

- **Contexto operacional de retomada:** `.ai/handoff.md` — **fonte viva** do estado da última entrega
  (branch, SHA, o que foi feito, o que ficou pendente, dívidas e limitações do ambiente).
- **Regra:** ao fim de **cada** entrega, o handoff é atualizado **no mesmo commit/PR** da atividade,
  com o marcador explícito de **gates pendentes do orquestrador** quando o CI oficial ainda não rodou
  (nunca afirmar resultado de gate/CI não executado).
- **Contexto persistente do projeto:** `.ai/virtus-context.md` (identidade, stack, fases, mapa do
  repositório).
- **Ordem de leitura obrigatória para qualquer atividade** (AGENTS.md §1): `AGENTS.md` →
  `.ai/virtus-context.md` → `.ai/workflow.md` → `.ai/architecture-rules.md` → `.ai/git-rules.md` →
  `.ai/handoff.md` → Issue → desenho da atividade.
- **Este Plano Mestre** é a **visão de conjunto** (história + roadmap + manual); o handoff é o
  **estado do momento**; o desenho da atividade é o **contrato**.

---

## Parte XVII — Contradições e divergências registradas

Registro obrigatório: **contradição não se resolve inventando uma versão** — registram-se as duas
fontes. Itens conhecidos:

1. **“Plano Mestre” citado como fonte sem existir versionado no repositório.**
   - Fonte A: `docs/auditorias/2026-09-10-checkpoint-etapa-5-pos-f5-06.md:7` afirma que o Plano Mestre
     é “fonte vigente para estado atual e próximos passos”.
   - Fonte B: busca por nome (`plano`/`mestre`/`master`/`roadmap`) em `docs/**` = **vazio**; `grep`
     por “Plano Mestre” em todo `*.md` = **1 ocorrência**, a própria citação acima.
   - **Desfecho registrado:** este documento é a **primeira versão versionada** do Plano Mestre no
     repositório (**v16**, numeração dada pelo orquestrador; versões anteriores existem **fora** do
     repo). Não há comparação com a v15 a ser feita aqui.
2. **“A próxima fase é a F5-12” × “a Issue #256 é a F5-12”.**
   - Fonte A (histórica): sequência de fases dos desenhos F5-07/F5-08 indicavam a **F5-12** como
     validação integrada **futura** da Etapa 5.
   - Fonte B (vigente): `docs/etapa-5-certificacao.md`, `.ai/handoff.md` e `.ai/virtus-context.md`
     após a correção da Issue #258 registram que **a Issue #256 É a própria F5-12** — não há fase
     posterior de fechamento dentro da F5.
   - **Vigente:** Fonte B. A F5-12 **é esta entrega**; a **próxima fase é a Etapa 6 (F6)** —
     auditoria visual/funcional READ-ONLY (Parte II.2/II.3), com escopo definido pelo roadmap vigente.
3. **Guarda *point-in-time* da P3 × emenda de D15.**
   - Fonte A: migration da P3 (integrada) proíbe `observation.*` em role de sistema fora de
     `observacoes_gestor` — coerente à época.
   - Fonte B: emenda de D15 (P5.1) cria `observacoes_avaliado` com `observation.read`.
   - **Desfecho registrado:** a guarda da P3 é **point-in-time** e roda **antes** da P5.1 em
     `db reset`; o invariante antigo fica **superseded** pela emenda — reaplicar a P3 **depois** da
     P5.1 falharia (documentado no desenho e na migration da P5).
4. **Harness local × CI nos pares de concorrência.**
   - Fonte A (CI): pares em duas sessões simultâneas reais (`A &` + `B` no mesmo shell).
   - Fonte B (harness local): sessão A em segundo plano com dianteira de alguns segundos; pode gerar
     **flake de medição** de tempo de bloqueio.
   - **Vigente:** a **autoridade** dos pares é o **CI oficial**; o resultado local deve ser declarado
     como aproximação quando houver flake.
5. **Roadmap até produção: v15 (externo) × v16 (este repositório).**
   - Fonte A (vigente e anterior): o **Plano Mestre externo v15** já definia o roadmap **até produção**
     — Etapa 6 (auditoria visual/funcional READ-ONLY com classificação QUEBRADO/REGRESSÃO/MELHORIA e
     consolidação de causas antes de criar trabalho), Etapa 7 (segurança/hardening para produção) e
     Etapas 8–10 (arquitetura-alvo, migração, pré-produção e produção).
   - Fonte B (v16, primeira versão versionada aqui): a primeira redação desta v16 **omitiu** esse
     roadmap e chegou a afirmar que a F6 estava “sem escopo”.
   - **Desfecho registrado:** a omissão foi **corrigida nesta v16 por decisão do orquestrador** — as
     Etapas 6–10 constam da Parte II.2/II.3, a próxima fase é a **Etapa 6 (F6)** com o escopo acima, e
     **não há mais nenhuma afirmação de que a F6/Etapa 6 esteja “sem escopo”**. O detalhamento das
     Etapas 8–10 **não** foi fabricado: permanece o que o roadmap vigente define, e o detalhamento
     exige Issue + desenho próprios. A causa de a v16 não trazer esse conteúdo antes é a mesma do item
     1 (o v15 **não está versionado** neste repositório).

---

*Fim da v16. Este documento é história + roadmap + manual operacional. Em caso de divergência com
`.ai/*` ou com o desenho de uma atividade, prevalece a fonte normativa — e a divergência deve ser
registrada aqui.*
