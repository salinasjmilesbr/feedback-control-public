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
- **Branch:** `feat/f5-06-avaliacoes-postgresql` (sem PR; sem merge).
- **Último commit:** consultar `git log --oneline -1` na branch.
- **PR:** não aberto por decisão explícita do responsável.
- **Estado — SQL e fronteira (completo e validado):** migrations F5-06
  (schema, funções e `20260911020000_f5_06_cutover_leitura_e_ciclo.sql` com
  `evaluation_resolver_ciclo` e `evaluation_painel_participante`); Edge
  Function `avaliacoes` com ActorContext/ResourceContext reais, Policy Engine
  (capability × scope), ASSIGNED por operação (F3-08/F3-09) e ponte
  matrícula → UUID (F3-01) resolvida ANTES do engine; cutover ESTRUTURAL por
  evidência (nunca por data). Validadores SQL com exit 0:
  `02-validar-f5-06.sql`, `03-validar-f5-06-cutover.sql`,
  `02-validar-f4-08.sql`, `03-validar-f4-08-mutacoes.sql`.
- **Estado — caminho TS (pronto para consumo):** repository/service/controlador/
  hook/apresentação, incluindo as operações `painelParticipante` e
  `resolverCiclo` e o `cutoverAvaliacoesService` (criarNova, carregarPainel,
  gravarNotas/ComentarioDoPainel, concluir, cancelar, reabrir, lerStatus) sem
  cálculo oficial no cliente e sem escrita em `localStorage`.
- **PENDÊNCIA REAL (bloqueia "Supabase como única fonte de verdade"):** as TELAS
  ainda não consomem esse caminho. Continuam escrevendo avaliação nova em
  `localStorage`: `NovoFeedbackPage` (`saveFeedback`), `EditarFeedbackPage`
  (`updateFeedback`), `cicloEquipeService` (criação no ciclo e conclusão no
  encerramento), `cancelamentoAvaliacaoService` e
  `reaberturaAvaliacaoService` (persistências internas). Nenhuma delas faz
  dual-write, mas a autoridade de escrita ainda é local nessas telas.
- **Contexto do repositório:** `main` contém F4 e F5-01..F5-05; a F5-06 é a
  atividade em curso nesta branch.
- **Próximos passos:** migrar as telas/serviços listados para o caminho soberano
  (usando `cutoverAvaliacoesService`), tornar `feedbackStorage` somente leitura
  para o legado, atualizar os testes acoplados e rodar o gate final.
