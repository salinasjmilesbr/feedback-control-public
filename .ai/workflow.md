# Virtus — Workflow oficial dos agentes

> Fluxo operacional e responsabilidades por modo. Complementa `AGENTS.md`.
> GitHub é a fonte de verdade do andamento (Issues, PRs e revisões).

## 1. Fluxo oficial

```
Issue
  → branch
  → desenho (Flash) e revisão/fechamento das decisões (GPT) — quando a atividade exigir contrato
  → desenho entra em main
  → implementação (Pro) e validação local
  → commit + push
  → PR (agente, quando houver mecanismo autorizado; senão o orquestrador — §7)
  → CI no SHA do PR
  → auditoria (GPT; Codex quando aplicável)
  → squash merge (somente com solicitação explícita do responsável)
  → atualização da main
```

Regra mestre: **nenhuma implementação começa com decisão arquitetural aberta**.
Um documento de desenho só autoriza implementação quando a revisão fechou todas
as questões (`Q#`) como decisões (`D#`) e o documento foi para `main`.

## 2. Fases de uma atividade típica

1. **Leitura obrigatória** — `AGENTS.md`, `.ai/*`, Issue completa (escopo,
   critérios de aceite, fora de escopo), contratos relacionados e PRs em aberto.
2. **Desenho (Flash)** — branch de documentação própria; produz
   `docs/Fx-XX-desenho-tecnico.md` com o estado atual, modelo, invariantes,
   decisões propostas `D#`, questões `Q1/Q2/…`, critérios de aceite e estratégia
   de testes. **Sem código funcional**.
3. **Revisão e fechamento (GPT)** — comenta o PR de desenho; cada `Q#` é
   respondida e vira decisão fechada (`D#`) ou é absorvida por decisão existente,
   mantendo rastreabilidade. Documento passa ao estado **FECHADO — pronto para
   implementação**.
4. **Merge do desenho em `main`** — o contrato da atividade fica disponível.
5. **Implementação (Pro)** — branch própria de código, fora da branch de
   desenho; segue exclusivamente o contrato fechado; inclui testes e validadores
   proporcionais ao risco; executa as validações locais planejadas.
6. **Commit e push** — concluídas a implementação e as validações locais
   planejadas, **sem blocker**, o agente de implementação executa `commit + push`
   na branch da atividade (**§7.2**, regra 1).
7. **PR** — aberto **imediatamente após o push**, com vínculo à Issue
   (`Closes #<n>`): pelo próprio agente quando o ambiente possuir mecanismo
   **autorizado**; caso contrário, pelo **orquestrador**, a quem o agente entrega
   **branch, SHA, título e corpo** (**§7.2**, regras 2 a 4, e **§7.3**).
8. **CI verde no SHA do PR** — `npm test`, `npm run build`, `npm run lint`,
   `git diff --check` e validações Supabase locais quando aplicável; o CI fica
   associado ao **SHA efetivamente auditado**, e toda correção posterior gera
   **novo SHA** com **novo CI** correspondente (**§7.2**, regras 6 e 7).
9. **Auditoria** — GPT audita aderência ao contrato, invariantes de
   segurança/autorização e ausência de mudanças fora do escopo; Codex quando
   aplicável.
10. **Squash merge** — integra em `main` com **SHA auditado**, **somente com
    solicitação explícita do responsável**; o agente de implementação **nunca**
    faz merge (**§7.2**, regras 8 e 9).

Na implementação e na validação, a distinção entre **aprovação técnica** e
**autorização de elevação de acesso**, o trabalho em lote e o agrupamento de
comandos privilegiados seguem **§6**. A abertura do PR, o disparo antecipado do CI
e as regras de fechamento seguem **§7**.

## 3. Responsabilidades por modo

| Modo/ator | Papel |
| --- | --- |
| **Flash** | Análise e desenho (contratos, questões `Q#`, decisões propostas `D#`) |
| **Pro** | Implementação do contrato fechado (código, testes, validações) |
| **GPT/Codex** | Revisão, auditoria e fechamento de decisões arquiteturais |
| **GitHub** | Fonte de verdade: Issues, PRs, revisões e histórico |

## 4. Perguntas e decisões

- Pergunta arquitetural em aberto → registrar como **`Q#`** (contexto, problema,
  alternativas, recomendação, impacto/risco) no documento de desenho.
- Resposta aprovada na revisão → **`D#` FECHADA** (ou integração em decisão
  existente com rastreabilidade explícita `Q# → D#`).
- Documentos fechados (F4/F5 e demais) **não são reabertos** sem evidência
  técnica nova; uma necessidade real de mudança vira **nova `Q#`** com a
  evidência e tramita pelo fluxo normal.

## 5. O que ler antes de cada modo

| Modo | Leitura mínima |
| --- | --- |
| Desenhar | `AGENTS.md`, `.ai/*`, Issue, contratos de fases relacionadas, PRs em aberto |
| Implementar | `AGENTS.md`, `.ai/*`, Issue, **contrato `docs/Fx-XX` FECHADO**, validadores existentes |
| Revisar/auditar | `AGENTS.md`, `.ai/architecture-rules.md`, Issue, contrato da atividade, diff completo, evidências de CI |
| Retomar | `AGENTS.md`, `.ai/handoff.md`, Issue/PR da atividade, branch e SHA em andamento |

O ciclo de elevação de acesso durante implementar/validar e o agrupamento do gate
privilegiado seguem **§6**; a abertura do PR, o disparo antecipado do CI e as
regras de fechamento seguem **§7**; a limitação conhecida de push **e de criação
de PR** no sandbox está em `.ai/git-rules.md` §3.

## 6. Elevação de acesso e economia de interrupções (DEV-02)

> Regra operacional derivada da Issue #177. Reduz drasticamente interrupções
> repetitivas por elevação de acesso **sem** relaxar nenhum controle de segurança,
> de Git ou arquitetural. Complementa §1–§5 e não os substitui.

### 6.1 Duas decisões distintas

| Decisão | De quem é | Quando acontece |
| --- | --- | --- |
| **Aprovação técnica/arquitetural** | fluxo oficial: revisão/fechamento no desenho (GPT) e auditoria independente após a implementação | desenho (§2, itens 3–4) e auditoria (§2, item 9) |
| **Autorização de elevação de acesso** | responsável pelo ambiente/host | quando o sandbox/SO exige permissão para executar um comando |

São **independentes e não se substituem**:

- desenho FECHADO autoriza implementar o contrato, mas **não** é autorização de
  elevação de acesso do ambiente;
- elevação de acesso concedida pelo host **não** aprova decisão arquitetural nem
  dispensa auditoria;
- nenhuma das duas autoriza merge, `push --force`, reescrita de histórico ou
  qualquer ação irreversível (§6.2, alínea d).

### 6.2 Com desenho FECHADO: não repetir pedido de aprovação

Com o contrato da atividade **FECHADO** (§1) e já em `main`, **não** se pede nova
aprovação técnica para decisões já cobertas por ele: a implementação segue o
contrato fechado (§2, item 5). Interromper o fluxo é permitido **somente** por:

- **(a) contradição arquitetural real** — conflito objetivo entre o contrato,
  `.ai/architecture-rules.md` e/ou o código existente;
- **(b) decisão necessária não coberta** — o contrato é omisso sobre algo
  indispensável; registrar nova `Q#` (§4) e **não** decidir por conta própria;
- **(c) risco de segurança** — qualquer cenário que possa afetar trust
  boundaries, autorização, RLS, grants, fail-closed ou dados;
- **(d) ação irreversível que exija autorização** — por exemplo `push --force`,
  reescrita de histórico, remoção de dados, `db reset` destrutivo fora do ambiente
  local descartável, merge ou publicação.

Fora desses quatro casos, **prossiga** dentro do contrato.

### 6.3 Fluxo-alvo de implementação

```
ler/analisar tudo o que for possível
  → implementar em lote
  → autoauditoria estática
  → correções em lote
  → gate privilegiado integrado
  → correções em lote, se necessárias
  → gate final
  → auditoria independente
```

1. **Ler/analisar primeiro** — leitura, busca, diff, inspeção de contratos e
   análise estática antes de qualquer comando privilegiado.
2. **Implementar em lote** — agrupar as alterações relacionadas da mesma atividade
   em uma passada, em vez de micro-edições intercaladas com validação.
3. **Autoauditoria estática** — revisar o próprio diff: escopo, contratos,
   invariantes, imports, tipos, achados óbvios de lint e `git diff --check`.
4. **Correções em lote** — consolidar tudo **antes** de elevar.
5. **Gate privilegiado integrado** (§6.4).
6. **Correções em lote** para o que o gate apontar.
7. **Gate final**, uma vez, sobre o estado consolidado.
8. **Auditoria independente** (§2, item 9). Nenhum agente declara a própria
   entrega aprovada.

Antipadrão proibido: `editar → elevar → testar → editar → elevar → testar`
repetido.

### 6.4 Gate privilegiado: agrupar, não interromper

Reúna, quando tecnicamente possível, no **mesmo** gate:

- validações locais da atividade: `npm test`, `npm run build`, `npm run lint`,
  `git diff --check`, `git status --short`;
- validadores SQL/Supabase locais (Docker, `db reset`, cenários e validadores);
- `git add`, `commit` e `push` da atividade.

**Limitação do ambiente.** Se o host/sandbox exigir elevação
(`danger-full-access` ou equivalente) até para comandos triviais — `git status`,
`npm test`, `lint`, leituras e inspeções —, isso é **limitação do ambiente**, não
fluxo normal:

- reconheça e registre a limitação na entrega (e em `.ai/git-rules.md` quando for
  recorrente);
- agrupe o máximo de operações por gate, evitando uma interrupção por comando;
- **não** tente contornar a proteção de forma alguma.

### 6.5 Proibições (permanentes)

Para reduzir prompts de elevação é **proibido**:

- alterar PAT, tokens ou credenciais;
- alterar configurações de segurança/permissão do ambiente, do repositório ou do
  Git (credential helper, askpass, hooks de bypass);
- criar qualquer bypass, atalho, exceção ou substituição de comando privilegiado;
- reduzir, desativar ou afrouxar controles existentes (RLS, grants, fail-closed,
  `authorize()`, CI, `git diff --check`, limites do sandbox).

### 6.6 O que esta regra não altera

A economia de interrupções **não** modifica, em nenhuma hipótese:

- merge **somente** com solicitação explícita do responsável (§2, item 10);
- **CI verde** e **SHA auditado** como condição de integração;
- **fail-closed** e as trust boundaries de `.ai/architecture-rules.md`;
- uma branch por atividade e a separação entre desenho e implementação (§2);
- as regras de push e a limitação conhecida do sandbox (`.ai/git-rules.md`).

## 7. Abertura de PR e disparo antecipado do CI (DEV-04)

> Regra operacional derivada da Issue #234. Formaliza a **abertura do Pull
> Request logo após o `commit + push`**, quando a implementação e os gates locais
> planejados estiverem verdes e **não houver blocker**, para **disparar o CI
> antecipadamente** e reduzir etapas manuais de fechamento. **Complementa §1–§6**
> — em especial DEV-02 (**§6**) e DEV-03 — e **não** os substitui nem os
> enfraquece.

### 7.1 Fluxo de fechamento

```
Issue
  → branch
  → implementação
  → validação local
  → commit/push
  → PR
  → CI
  → auditoria GPT
  → Codex quando aplicável
  → squash merge
  → atualização da main
```

### 7.2 Regras

1. **Commit + push após os gates locais.** Concluídas a implementação e as
   **validações locais planejadas**, **sem blocker**, o agente de implementação
   executa `commit + push` na branch da atividade.
2. **PR imediato.** Se o ambiente do agente possuir mecanismo **autorizado** para
   criar PR, ele abre o PR **automaticamente**, logo após o push.
3. **Fallback para o orquestrador.** Se o ambiente **não** possuir mecanismo
   autorizado, o agente **não contorna** a limitação (**§7.3**) e entrega
   imediatamente: **branch**, **SHA final**, **título** e **corpo do PR** —
   informando **explicitamente** que o PR precisa ser aberto pelo orquestrador.
4. **Orquestrador.** O orquestrador ChatGPT pode abrir o PR pela **integração
   GitHub já autorizada**, sem PAT nem credenciais locais adicionais.
5. **Vínculo com a Issue.** Todo PR executável deve conter `Closes #<issue>`
   (quando a entrega resolve integralmente a Issue).
6. **CI por SHA.** O CI deve estar associado ao **SHA efetivamente auditado**, e o
   SHA do CI é confirmado **antes** da auditoria e do merge.
7. **Correção posterior ao PR.** Qualquer correção gera **novo SHA**, que exige o
   **CI correspondente** (nova execução no novo SHA).
8. **O agente de implementação nunca faz merge.**
9. **Squash merge** permanece condicionado aos **gates objetivos vigentes** e à
   **solicitação explícita do responsável**.

### 7.3 Limitação do ambiente: nunca contornar

Quando o ambiente do agente **não** permitir abrir PR por mecanismo autorizado, é
**proibido** — na mesma linha de **§6.5** — **instalar `gh`** por conta própria,
**criar ou usar PAT**, **alterar credenciais** ou `git config`, ou criar qualquer
bypass. O caminho correto é o **fallback ao orquestrador** (**§7.2**, regra 3),
registrando a limitação na entrega e em `.ai/git-rules.md` §3 — que cobre tanto o
`push` quanto a **criação do PR**.

### 7.4 Integração com DEV-03

- **Não** habilitar CI pesado em **todo push intermediário**: o PR é aberto quando
  a implementação e os gates locais estiverem **prontos**.
- O **CI completo continua sendo gate de fechamento**.
- **Não repetir** CI/gates sem mudança relevante de código, ambiente ou hipótese:
  uma execução deve produzir **informação nova**.
- Correções posteriores ao PR seguem a regra 7 de **§7.2** (**novo SHA → novo
  CI**).

### 7.5 Integração com DEV-02 (§6)

- DEV-04 **não** cria **nenhuma superfície nova de credencial** e **não** reduz
  sandbox nem controles de segurança.
- O **fallback ao orquestrador** é **preferível** a PAT ou credencial adicional.
- A abertura do PR **não** é autorização de elevação de acesso e **não** dispensa
  os gates de **§6**.

### 7.6 O que esta regra não altera

- merge **somente** com solicitação explícita do responsável;
- **CI verde** e **SHA auditado** como condição de integração;
- **fail-closed** e as trust boundaries de `.ai/architecture-rules.md`;
- uma branch por atividade e a separação entre desenho e implementação (§2);
- as regras de push/PR e a limitação conhecida do sandbox (`.ai/git-rules.md` §3);
- a **proibição de merge pelo agente de implementação**.

### 7.7 Rastreabilidade das regras DEV

| Regra | Origem | Onde está registrada |
| --- | --- | --- |
| DEV-01 | Issue #167 | `AGENTS.md` + esta camada `.ai/*` |
| DEV-02 | Issue #177 | **§6** e `AGENTS.md` §4 |
| DEV-03 | regra operacional vigente (gate de fechamento e uso de gates focados) | referenciada em contratos, matrizes de validação e corpos de Issue; **sem Issue e sem documento normativo próprio até esta atividade** |
| DEV-04 | Issue #234 | **§7** e `AGENTS.md` §6 |
