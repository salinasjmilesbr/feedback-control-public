# Virtus — Regras de Git

> Regras operacionais de branch, commit, merge e push. Complementa `AGENTS.md`.

## 1. Branch e PR

- **Uma branch por atividade** (Issue), com prefixo por tipo conforme o
  histórico do repositório: `docs/`, `feat/`, `fix/`, `chore/`, `refactor/`,
  `security/`, `ci/`.
- **Desenho e implementação separados**: documento de desenho em branch `docs/…`
  (sem código funcional); código em branch própria posterior, somente com
  contrato fechado.
- PR aberto com `.github/pull_request_template.md`; `Closes #<n>` apenas quando a
  entrega resolve integralmente a Issue.
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

## 3. Limitação conhecida do sandbox DeepSeek (push)

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

## 4. Checklist de entrega

- [ ] Branch correta da atividade; diff contém só arquivos previstos.
- [ ] `git diff --check` limpo.
- [ ] `npm test`, `npm run build`, `npm run lint` verdes (ou limitação registrada).
- [ ] Commit objetivo com mensagem no padrão do histórico.
- [ ] Push tentado; falha conhecida registrada (branch + SHA + comando).
- [ ] PR descrito conforme template; revisão/squash merge pendente de pedido.
