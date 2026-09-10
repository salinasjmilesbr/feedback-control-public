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
