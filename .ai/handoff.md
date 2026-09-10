# Virtus — Handoff (contexto operacional de retomada)

> Registro **operacional e estável** para retomada entre agentes/sessões.
> **Não copie** dados pessoais, segredos, credenciais, tokens, chaves ou
> informações corporativas sensíveis. Referencie Issues/PRs/documentos em vez de
> transcrever conteúdo. GitHub continua sendo a fonte de verdade do andamento.

## 1. Como retomar uma atividade interrompida

1. Leia `AGENTS.md` e `AGENTS.md` → `.ai/*` (ordem de `.ai/virtus-context.md`).
2. Leia **este arquivo** — seção 3 (registro de estado) — para saber onde a
   última entrega parou.
3. Confirme no GitHub (fonte de verdade) a Issue, o PR e o estado real da branch.
4. Em paralelo ao registro, verifique localmente com:

```bash
git status -sb        # branch atual, ahead/behind de origin
git log --oneline -3  # últimos commits locais
git diff --stat       # alterações não commitadas
```

5. Se um push falhou pela limitação conhecida (`.ai/git-rules.md`), o trabalho
   está **commitado localmente** e aguarda o usuário executar o push; não refaça
   e não tente contornar.

## 2. Instrução permanente de manutenção

A cada entrega (concluída ou interrompida), **atualize a seção 3** com o novo
estado e remova entradas obsoletas. Mantenha apenas contexto operacional:
branch, SHA, PR, atividade e próximos passos. **Nunca** adicione segredos,
credenciais, conteúdo real de pessoas/empresa ou trechos de documentos aqui.

## 3. Registro de estado (última entrega)

> Atualizar ao final de cada atividade.

- **Atividade:** DEV-01 — Contexto persistente para agentes (Issue #167).
- **Branch:** `chore/agent-instructions-persistent-context`.
- **Último commit:** SHA local desta entrega — ver `git log --oneline -1` na
  branch (mantido por leitura, não por cópia).
- **Push:** a preencher no handoff seguinte (resultado; em caso de falha
  conhecida, aguarda o usuário executar `git push -u origin
  chore/agent-instructions-persistent-context`).
- **PR:** a abrir pelo usuário após o push (referenciar `Closes #167` se a
  entrega resolver integralmente a Issue).
- **Estado:** documentação/infraestrutura de processo concluída localmente;
  aguardando push e revisão.
- **Contexto do repositório na criação deste registro:** `main` contém os
  contratos F4 (encerrada) e F5-01..F5-03; F5-04 (access roles/capabilities
  reais) está em branch de documentação própria (`docs/f5-04-…`) aguardando push/
  revisão — fora do escopo do DEV-01.
- **Próximos passos:** push pelo usuário → abrir PR → revisão → squash merge.
- **Atenção (fora de escopo do DEV-01):** resolver autenticação/push do sandbox;
  mudar arquitetura funcional; alterar contratos F4/F5; criar automações externas.
