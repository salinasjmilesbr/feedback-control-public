# Instruções permanentes para agentes do Virtus

> Ponto de entrada obrigatório. **Leia integralmente antes de qualquer ação** no
> repositório e volte a ele sempre que iniciar uma nova atividade ou retomar uma
> entrega interrompida.

## 1. Ordem de leitura obrigatória

Antes de desenhar, implementar, revisar ou auditar qualquer atividade, leia:

1. `AGENTS.md` (este arquivo);
2. `.ai/virtus-context.md` — contexto persistente do projeto (identidade, stack, fases, mapa do repositório);
3. `.ai/workflow.md` — fluxo oficial (Flash desenha → GPT revisa/fecha → Pro implementa → GPT audita → CI → squash merge) e responsabilidades por modo;
4. `.ai/architecture-rules.md` — regras arquiteturais e trust boundaries permanentes;
5. `.ai/git-rules.md` — regras de Git e limitação conhecida de push do sandbox;
6. `.ai/handoff.md` — contexto operacional de retomada (estado da última entrega);
7. A **Issue** correspondente e a discussão do **PR** (GitHub é a fonte de verdade);
8. `docs/Fx-XX-desenho-tecnico.md` da atividade — **contrato específico da atividade**.

Se algum arquivo `.ai/` não existir em um checkout antigo, proceda sem ele e
registre a ausência na entrega.

## 2. Projeto

Repositório do **Virtus (Vivo Virtus / `feedback-control`)**, aplicação de gestão
de avaliações, observações, metas e estrutura organizacional. Stack principal:
React, TypeScript, Vite, React Router, Vitest, ESLint, jsPDF; Supabase
(Supabase Auth + Postgres/RLS). Detalhes estáveis em `.ai/virtus-context.md`.

O GitHub é a fonte de verdade para Issues, requisitos, histórico, decisões
registradas em revisões e Pull Requests. `docs/Fx-XX-desenho-tecnico.md` é o
contrato específico da atividade; decisões `D#` FECHADAS e questões `Q#`
encerradas não se reabrem sem evidência técnica nova (ver `.ai/workflow.md`).

## 3. Regras permanentes (síntese)

Regras detalhadas em `.ai/architecture-rules.md`. Síntese inegociável:

- `auth.uid()` é a raiz soberana de identidade; **tenant sempre validado
  server-side**; frontend/JWT/localStorage/payload **não concedem autoridade**;
  **fail-closed**; **cross-tenant DENY**.
- O **Policy Engine** é o gate soberano de autorização; `authorize()` é
  enforcement; `can()` serve somente à UX. Ocultar elemento na interface **não é**
  autorização efetiva.
- **RLS é barreira de segurança** (F4-08); tabelas autorizativas fechadas;
  nenhum `SECURITY DEFINER` novo sem necessidade explícita.
- Não duplique regras de autorização em páginas ou componentes; use a policy e
  as capabilities centrais em `src/authorization`.
- Preserve a separação entre autorização, workflow, cálculos, persistência e
  auditoria; preserve históricos e trilhas de auditoria.
- Não inclua dados pessoais ou corporativos reais em código, fixtures, testes,
  documentação, commits ou PRs — somente dados fictícios.
- Não altere contratos F4/F5 sem atividade explicitamente destinada a isso.

## 4. Qualidade e validação

Antes de concluir uma alteração, execute e registre no Pull Request:

```bash
npm test
npm run build
npm run lint
git diff --check
```

- Todos os comandos devem passar antes da entrega.
- Se uma validação não puder ser executada ou falhar por motivo externo ao
  escopo, registre claramente o comando, o resultado e a limitação no PR.
- Revise `git status --short` e o diff final: somente arquivos previstos no
  escopo da Issue.

## 5. Fluxo GitHub

- Uma **branch por atividade**; desenho e implementação em branches separadas.
- Desenho (documento de design) e implementação (código) **nunca** no mesmo PR;
  nenhuma implementação começa com decisão arquitetural aberta.
- Use commits objetivos compatíveis com o histórico do repositório.
- Abra Pull Request usando `.github/pull_request_template.md`; use `Closes #<n>`
  somente quando a entrega resolver integralmente o escopo da Issue.
- **Squash merge** em `main` com **CI verde** e **SHA auditado**.
- Não faça merge sem solicitação explícita.
- Dependabot e PRs de dependência ficam **fora** de atividades estruturais.
- Regras de push e a limitação conhecida do sandbox DeepSeek: `.ai/git-rules.md`.
