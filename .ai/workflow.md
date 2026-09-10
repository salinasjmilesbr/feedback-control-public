# Virtus — Workflow oficial dos agentes

> Fluxo operacional e responsabilidades por modo. Complementa `AGENTS.md`.
> GitHub é a fonte de verdade do andamento (Issues, PRs e revisões).

## 1. Fluxo oficial

```
Flash desenha
  → GPT revisa e fecha decisões
  → desenho entra em main
  → Pro implementa
  → GPT audita
  → CI
  → squash merge
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
   proporcionais ao risco; executa as validações locais.
6. **Auditoria (GPT)** — audita aderência ao contrato, invariantes de
   segurança/autorização e ausência de mudanças fora do escopo.
7. **CI verde** — `npm test`, `npm run build`, `npm run lint`,
   `git diff --check` e validações Supabase locais quando aplicável.
8. **Squash merge** — integra em `main` com **SHA auditado** e PR referenciando
   a Issue (`Closes #<n>` quando resolve integralmente).

Na implementação e na validação, a distinção entre **aprovação técnica** e
**autorização de elevação de acesso**, o trabalho em lote e o agrupamento de
comandos privilegiados seguem **§6**.

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
privilegiado seguem **§6**; a limitação conhecida de push está em
`.ai/git-rules.md` §3.

## 6. Elevação de acesso e economia de interrupções (DEV-02)

> Regra operacional derivada da Issue #177. Reduz drasticamente interrupções
> repetitivas por elevação de acesso **sem** relaxar nenhum controle de segurança,
> de Git ou arquitetural. Complementa §1–§5 e não os substitui.

### 6.1 Duas decisões distintas

| Decisão | De quem é | Quando acontece |
| --- | --- | --- |
| **Aprovação técnica/arquitetural** | fluxo oficial: revisão/fechamento no desenho (GPT) e auditoria independente após a implementação | desenho (§2, itens 3–4) e auditoria (§2, item 6) |
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
8. **Auditoria independente** (§2, item 6). Nenhum agente declara a própria
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

- merge **somente** com solicitação explícita do responsável (§2, item 8);
- **CI verde** e **SHA auditado** como condição de integração;
- **fail-closed** e as trust boundaries de `.ai/architecture-rules.md`;
- uma branch por atividade e a separação entre desenho e implementação (§2);
- as regras de push e a limitação conhecida do sandbox (`.ai/git-rules.md`).
