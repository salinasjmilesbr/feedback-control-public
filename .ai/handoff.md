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

- **Atividade:** F5-06 — Avaliações no PostgreSQL (Issue #103).
- **Branch:** `feat/f5-06-avaliacoes-postgresql` (sem PR aberto; sem merge).
- **Último commit:** consultar `git log --oneline -1` na branch (o SHA não é
  copiado aqui para não ficar obsoleto).
- **Push:** realizado no remoto da branch a cada rodada; a última tentativa
  concluiu sem a limitação de `GIT_ASKPASS`.
- **PR:** não aberto por decisão explícita do responsável (aguarda auditoria).
- **Estado:** F5-06 implementada de ponta a ponta no SQL e no caminho TypeScript
  (repository/infraestrutura Supabase, Edge Function `avaliacoes` com
  ActorContext/ResourceContext reais, Policy Engine com capability × scope,
  ASSIGNED por operação via F3-08/F3-09, service/controlador/hook/apresentação).
  Validadores SQL executados no Supabase local com exit 0 (F5-06, F4-08 e
  mutações F4-08). O CUTOVER é ESTRUTURAL: a origem de cada registro vem de
  evidência do caminho novo (UUID da escrita confirmada no banco), nunca de data;
  registro legado permanece somente leitura e sem dual-write.
- **Pendência real:** as TELAS antigas de avaliação
  (`src/services/feedbackStorage.ts` e as páginas que o consomem: Novo/Editar
  feedback, Minha avaliação e detalhes, painel de ciclo, detalhe de colaborador,
  além dos serviços de cancelamento/reabertura/ciclo) ainda leem e escrevem
  `localStorage`. A migração dessas telas para o caminho soberano exige a ponte
  matrícula → UUID no cliente (hoje só existe server-side) e a decisão de produto
  sobre o que a tela de edição pode ler por participante (D20 proíbe expor voto
  individual do colegiado). O caminho novo está pronto e testado para ser
  consumido; a troca da autoridade das telas é o que falta.
- **Contexto do repositório:** `main` contém os contratos F4 (encerrada) e
  F5-01..F5-05; a F5-06 é a atividade em curso nesta branch.
- **Próximos passos:** auditoria independente da branch → decisão sobre a
  migração das telas → PR → revisão → squash merge.
