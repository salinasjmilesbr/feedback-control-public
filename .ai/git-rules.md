# Virtus — Regras de Git

> Regras operacionais de branch, commit, push, PR, CI e merge. Complementa `AGENTS.md`.

## 1. Branch e PR

- **Uma branch por atividade** (Issue), com prefixo por tipo conforme o
  histórico do repositório: `docs/`, `feat/`, `fix/`, `chore/`, `refactor/`,
  `security/`, `ci/`.
- **Desenho e implementação separados**: documento de desenho em branch `docs/…`
  (sem código funcional); código em branch própria posterior, somente com
  contrato fechado.
- PR aberto com `.github/pull_request_template.md`; `Closes #<n>` apenas quando a
  entrega resolve integralmente a Issue.
- **PR imediato (DEV-04)** — concluídas a implementação e as validações locais
  **planejadas**, sem blocker: `commit + push` e, **em seguida**, o PR. O agente
  abre o PR quando o ambiente tiver mecanismo **autorizado**; caso contrário,
  entrega **branch + SHA + título + corpo** e informa que o PR deve ser aberto
  pelo **orquestrador** (`.ai/workflow.md` §7).
- **CI por SHA (DEV-04)** — o CI fica associado ao **SHA do PR**, que é o SHA
  auditado; toda correção posterior gera **novo SHA** e exige **novo CI**
  correspondente.
- **O agente de implementação nunca faz merge.**
- **Squash merge** em `main`, com **CI verde** e **SHA auditado** (registrar o
  SHA que entrou em `main`).
- Sem merge sem solicitação explícita do responsável.
- **Dependabot/PRs de dependência** ficam fora de atividades estruturais: não
  entram no escopo de uma atividade em curso nem bloqueiam seu fluxo.

## 2. Validações locais antes de commitar

```bash
npm test
npm run build
npm run lint
git diff --check
git status --short   # conferir que só arquivos previstos estão incluídos
```

- Todas devem passar; falha por motivo externo ao escopo é registrada no PR com
  comando, resultado e limitação.
- Validações SQL/Supabase locais quando a atividade mexe em migrations/policies.

## 3. Limitação conhecida do sandbox DeepSeek (push e criação de PR)

O ambiente do DeepSeek pode **falhar no `git push`** por não conseguir ler
credenciais HTTPS (`GIT_ASKPASS` — o askpass do VS Code não executa no sandbox;
erro típico: `could not read Username for 'https://github.com'`).

Regras obrigatórias ao enfrentar essa falha:

- **Não usar PAT** nem token pessoal de acesso.
- **Não alterar** configuração de segurança nem `git config` (credential
  helper/askpass) para contornar.
- **Não contornar** a falha por outros meios (não tentar resolver a autenticação
  do sandbox).
- Após o commit, **informar**: branch, SHA do commit, resultado do push e o
  comando exato para o usuário executar no próprio terminal, ex.:

```bash
git push -u origin <nome-da-branch>
```

**A mesma limitação se aplica à criação do PR (DEV-04).** Quando o ambiente não
dispõe de mecanismo autorizado para abrir PR (por exemplo, `gh` ausente), a
resposta correta é o **fallback ao orquestrador**: entregar **branch, SHA,
título e corpo do PR** e informar explicitamente que o PR precisa ser aberto por
ele. É **proibido** instalar `gh` por conta própria, criar/usar PAT ou alterar
credenciais/`git config` para contornar. Detalhes: `.ai/workflow.md` §7.3.

## 4. Checklist de entrega

- [ ] Branch correta da atividade; diff contém só arquivos previstos.
- [ ] `git diff --check` limpo.
- [ ] `npm test`, `npm run build`, `npm run lint` verdes (ou limitação registrada).
- [ ] Commit objetivo com mensagem no padrão do histórico.
- [ ] Push tentado; falha conhecida registrada (branch + SHA + comando).
- [ ] **DEV-04**: PR aberto **imediatamente após o push** — pelo agente, quando
      houver mecanismo autorizado; senão **entregue ao orquestrador** (branch +
      SHA + título + corpo), com aviso explícito de que o PR precisa ser aberto
      por ele.
- [ ] **DEV-04**: CI confirmado no **SHA do PR**; correção posterior gera novo SHA
      e exige novo CI correspondente.
- [ ] PR descrito conforme template; revisão/squash merge pendente de pedido.
- [ ] Nenhum merge executado pelo agente.
