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
- **Último commit:** consultar `git log --oneline -1` na branch.
- **Push:** o push da branch conclui sem a limitação de `GIT_ASKPASS` no
  ambiente atual.
- **PR:** não aberto por decisão explícita do responsável (aguarda auditoria).
- **Estado (SQL e fronteira — completo e validado):**
  - migrations F5-06 (schema, funções e `20260911020000_f5_06_cutover_leitura_e_ciclo.sql`);
  - `evaluation_resolver_ciclo` (ano+ciclo → UUID soberano, fail-closed em zero,
    múltiplos ou ciclo cancelado, sempre dentro do tenant validado);
  - `evaluation_painel_participante` (leitura de EDIÇÃO do próprio participante:
    somente a ocorrência do ator + catálogo congelado; nunca voto/nota de
    terceiros; ocorrência resolvida server-side pelo vínculo F5-02 + vigência);
  - Edge Function `avaliacoes` com ActorContext/ResourceContext reais, Policy
    Engine (capability × scope), ASSIGNED por operação (F3-08/F3-09) e ponte
    matrícula → UUID (F3-01);
  - cutover ESTRUTURAL: a origem de cada registro vem de evidência do caminho
    novo (UUID de escrita confirmada), nunca de data; legado é somente leitura.
  - Validadores SQL executados com exit 0: `02-validar-f5-06.sql`,
    `03-validar-f5-06-cutover.sql`, `02-validar-f4-08.sql` e
    `03-validar-f4-08-mutacoes.sql`.
- **Pendência real (bloqueia declarar a F5-06 concluída no produto):** as TELAS
  ainda escrevem avaliação nova em `localStorage`:
  `NovoFeedbackPage` (`saveFeedback`), `EditarFeedbackPage` (`updateFeedback`),
  `cicloEquipeService` (criação automática no ciclo e recálculo no
  encerramento), `cancelamentoAvaliacaoService` e
  `reaberturaAvaliacaoService` (persistências internas auditadas).
  O caminho soberano está pronto para ser consumido (repository/service/
  controlador/hook/apresentação + as duas operações novas de leitura e de
  ciclo), inclusive a ponte matrícula → UUID; o que falta é a troca de autoridade
  dentro dessas telas/serviços, que exige refatoração de render síncrono para
  assíncrono e a remontagem do estado do formulário a partir do painel do
  participante.
- **Contexto do repositório:** `main` contém os contratos F4 (encerrada) e
  F5-01..F5-05; a F5-06 é a atividade em curso nesta branch.
- **Próximos passos:** migrar as telas/serviços acima para o caminho soberano →
  nova auditoria → PR → revisão → squash merge.
